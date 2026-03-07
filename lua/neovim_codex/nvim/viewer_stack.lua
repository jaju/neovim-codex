local Popup = nil

local M = {}

local state = {
  entries = {},
  stack = {},
}

local apply_window_options

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function clone_value(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for key, item in pairs(value) do
    out[key] = clone_value(item)
  end
  return out
end

local function present(value)
  return value ~= nil and type(value) ~= "userdata"
end

local function split_lines(value)
  if type(value) == "table" then
    local lines = {}
    for _, line in ipairs(value) do
      for _, part in ipairs(vim.split(tostring(line), "\n", { plain = true })) do
        lines[#lines + 1] = part
      end
    end
    return lines
  end

  if not present(value) or tostring(value) == "" then
    return { "" }
  end

  return vim.split(tostring(value), "\n", { plain = true })
end

local function resolve_dimension(value, total, minimum)
  if type(value) == "number" then
    if value > 0 and value < 1 then
      return math.max(minimum, math.floor(total * value))
    end
    return math.max(minimum, math.floor(value))
  end

  if type(value) == "string" and value:sub(-1) == "%" then
    local percentage = tonumber(value:sub(1, -2)) or 0
    return math.max(minimum, math.floor(total * (percentage / 100)))
  end

  return math.max(minimum, total)
end

local function overlay_config(spec)
  if spec.relative and spec.position and spec.size then
    return {
      relative = spec.relative,
      position = clone_value(spec.position),
      size = clone_value(spec.size),
    }
  end

  local ui = vim.api.nvim_list_uis()[1]
  local total_width = ui and ui.width or vim.o.columns
  local total_height = ui and ui.height or vim.o.lines
  local width = resolve_dimension(spec.width or 0.76, total_width, 60)
  local height = resolve_dimension(spec.height or 0.72, total_height, 16)

  return {
    relative = "editor",
    position = {
      row = math.max(1, math.floor((total_height - height) / 2)),
      col = math.max(1, math.floor((total_width - width) / 2)),
    },
    size = {
      width = width,
      height = height,
    },
  }
end

local function entry_visible(entry)
  if not entry then
    return false
  end

  if entry.surface and entry.surface.is_visible then
    return entry.surface.is_visible(entry) == true
  end

  return entry.popup and entry.popup._ and entry.popup._.mounted or false
end

local function hide_entry(entry)
  if not entry then
    return
  end

  if entry.surface and entry.surface.hide then
    entry.surface.hide(entry)
    return
  end

  if entry.popup and entry.popup._ and entry.popup._.mounted then
    entry.popup:hide()
  end
end

local function show_entry(entry)
  if not entry then
    return
  end

  if entry.surface and entry.surface.open then
    entry.surface.open(entry)
    if entry.surface.focus then
      entry.surface.focus(entry)
    end
    return
  end

  if entry.popup._.mounted then
    entry.popup:show()
  else
    entry.popup:mount()
  end

  apply_window_options(entry)

  if valid_window(entry.popup.winid) then
    vim.api.nvim_set_current_win(entry.popup.winid)
  end
end

local function stack_index(key)
  for index, entry in ipairs(state.stack) do
    if entry.key == key then
      return index
    end
  end
  return nil
end

local function top_entry()
  return state.stack[#state.stack]
end

local function set_buffer_contract(entry)
  local bufnr = entry.bufnr
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = entry.spec.filetype or "markdown"
  vim.api.nvim_buf_set_name(bufnr, string.format("neovim-codex://%s/%s", entry.spec.role or "viewer", entry.key))
  vim.b[bufnr].neovim_codex = true
  vim.b[bufnr].neovim_codex_role = entry.spec.role or "viewer"
end

local function set_buffer_lines(entry, lines)
  local bufnr = entry.bufnr
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, split_lines(lines))
  vim.bo[bufnr].modifiable = false
end

function apply_window_options(entry)
  local popup = entry.popup
  if not popup or not valid_window(popup.winid) then
    return
  end

  vim.wo[popup.winid].number = false
  vim.wo[popup.winid].relativenumber = false
  vim.wo[popup.winid].signcolumn = "no"
  vim.wo[popup.winid].wrap = entry.spec.wrap ~= false
  vim.wo[popup.winid].linebreak = entry.spec.wrap ~= false
end

local function clear_custom_mappings(entry)
  for _, mapping in ipairs(entry.custom_mappings or {}) do
    pcall(vim.keymap.del, mapping.mode, mapping.lhs, { buffer = entry.bufnr })
  end
  entry.custom_mappings = {}
end

local function apply_custom_mappings(entry)
  clear_custom_mappings(entry)
  for _, mapping in ipairs(entry.spec.mappings or {}) do
    vim.keymap.set(mapping.mode or "n", mapping.lhs, mapping.rhs, {
      buffer = entry.bufnr,
      silent = mapping.silent ~= false,
      nowait = mapping.nowait ~= false,
      desc = mapping.desc,
    })
    entry.custom_mappings[#entry.custom_mappings + 1] = {
      mode = mapping.mode or "n",
      lhs = mapping.lhs,
    }
  end
end

local function close_key(key)
  local index = stack_index(key)
  if not index then
    return false
  end

  local entry = table.remove(state.stack, index)
  if entry.spec and entry.spec.on_close then
    entry.spec.on_close(entry)
  end
  hide_entry(entry)

  if index == #state.stack + 1 then
    local previous = top_entry()
    if previous then
      show_entry(previous)
    end
  end

  return true
end

local function ensure_popup(entry)
  if not Popup then
    local ok, popup_mod = pcall(require, "nui.popup")
    if not ok then
      error(popup_mod)
    end
    Popup = popup_mod
  end

  if entry.popup then
    return entry.popup
  end

  local popup = Popup({
    enter = true,
    focusable = true,
    zindex = entry.spec.zindex or 60,
    border = {
      style = entry.spec.border or "rounded",
      text = {
        top = string.format(" %s ", entry.spec.title or "Viewer"),
        top_align = "center",
      },
    },
    bufnr = entry.bufnr,
    win_options = {
      winhighlight = entry.spec.winhighlight or "Normal:NormalFloat,FloatBorder:FloatBorder",
    },
  })

  popup:update_layout(overlay_config(entry.spec))
  popup:map("n", { "q", "<Esc>" }, function()
    close_key(entry.key)
  end, { silent = true, nowait = true })

  entry.popup = popup
  return popup
end

local function apply_spec(entry, spec)
  entry.spec = vim.tbl_deep_extend("force", entry.spec or {}, spec)
  entry.surface = entry.spec.surface

  if entry.surface and entry.surface.refresh then
    entry.surface.refresh(entry)
    return
  end

  if not entry.bufnr or not valid_buffer(entry.bufnr) then
    entry.bufnr = entry.spec.bufnr and valid_buffer(entry.spec.bufnr) and entry.spec.bufnr or vim.api.nvim_create_buf(false, true)
  end
  if entry.spec.manage_buffer ~= false then
    set_buffer_contract(entry)
    set_buffer_lines(entry, entry.spec.lines or { "" })
  end

  local popup = ensure_popup(entry)
  popup.border:set_text("top", string.format(" %s ", entry.spec.title or "Viewer"), "center")
  popup:update_layout(overlay_config(entry.spec))

  apply_window_options(entry)
  apply_custom_mappings(entry)
end

function M.open(spec)
  assert(spec and spec.key, "viewer stack requires a stable key")

  local current = top_entry()
  if current and current.key ~= spec.key then
    hide_entry(current)
  end

  local index = stack_index(spec.key)
  local entry = index and table.remove(state.stack, index) or state.entries[spec.key]
  if not entry then
    entry = { key = spec.key, spec = {}, custom_mappings = {} }
    state.entries[spec.key] = entry
  end

  apply_spec(entry, spec)
  state.stack[#state.stack + 1] = entry

  show_entry(entry)

  return entry
end

function M.refresh(key, spec)
  local entry = state.entries[key]
  if not entry then
    return nil
  end

  apply_spec(entry, vim.tbl_extend("force", spec or {}, { key = key }))
  return entry
end

function M.close(key)
  if key then
    return close_key(key)
  end

  local current = top_entry()
  if not current then
    return false
  end
  return close_key(current.key)
end

function M.close_all(opts)
  opts = opts or {}
  local preserve_sticky = opts.preserve_sticky == true

  while #state.stack > 0 do
    local current = state.stack[#state.stack]
    if preserve_sticky and current.spec and current.spec.sticky then
      break
    end
    close_key(current.key)
  end
end

function M.inspect()
  local stack = {}
  for _, entry in ipairs(state.stack) do
    stack[#stack + 1] = {
      key = entry.key,
      title = entry.spec.title,
      role = entry.spec.role,
      sticky = entry.spec.sticky == true,
      bufnr = entry.bufnr,
      winid = entry.popup and entry.popup.winid or nil,
      visible = entry_visible(entry),
      surface = entry.surface and type(entry.surface) == "table" and clone_value(entry.surface.inspect and entry.surface.inspect(entry) or {}) or nil,
    }
  end

  return {
    stack = stack,
    top = clone_value(stack[#stack]),
  }
end

function M.is_open(key)
  return stack_index(key) ~= nil
end

return M
