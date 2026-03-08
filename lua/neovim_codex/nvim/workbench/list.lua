local packet = require("neovim_codex.core.packet")

local M = {}

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function map_if(lhs, mode, rhs, opts)
  if not lhs or not rhs then
    return
  end
  vim.keymap.set(mode, lhs, rhs, {
    buffer = opts.buffer,
    silent = true,
    nowait = true,
    desc = opts.desc,
  })
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

local function split_lines(value)
  if type(value) == "table" then
    return value
  end

  local text = tostring(value or "")
  if text == "" then
    return { "" }
  end

  return vim.split(text, "\n", { plain = true })
end

local function contains_line(entry, line)
  return entry.line_start and entry.line_end and line >= entry.line_start and line <= entry.line_end
end

local ListView = {}
ListView.__index = ListView

function ListView:_apply_buffer_contract(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_name(bufnr, string.format("neovim-codex://workbench/%s", self.role))
  vim.b[bufnr].neovim_codex = true
  vim.b[bufnr].neovim_codex_role = self.role
end

function ListView:_bind_keymaps(bufnr)
  local keymaps = self.opts.keymaps.workbench or {}
  map_if(keymaps.close, "n", function()
    if self.handlers.close then
      self.handlers.close()
    end
  end, { buffer = bufnr, desc = "Close Codex workbench" })
  map_if(keymaps.inspect, "n", function()
    if self.handlers.inspect then
      self.handlers.inspect()
    end
  end, { buffer = bufnr, desc = "Inspect selected fragment" })
  map_if(keymaps.remove, "n", function()
    if self.handlers.remove then
      self.handlers.remove()
    end
  end, { buffer = bufnr, desc = "Remove selected fragment" })
  map_if(keymaps.clear, "n", function()
    if self.handlers.clear then
      self.handlers.clear()
    end
  end, { buffer = bufnr, desc = "Clear staged fragments" })
  map_if(keymaps.compose, "n", function()
    if self.handlers.compose then
      self.handlers.compose()
    end
  end, { buffer = bufnr, desc = "Open compose review" })
  map_if(keymaps.insert_handle, "n", function()
    if self.handlers.insert_handle then
      self.handlers.insert_handle()
    end
  end, { buffer = bufnr, desc = "Insert selected fragment handle into the packet template" })
  map_if(keymaps.focus_message, "n", function()
    if self.handlers.focus_message then
      self.handlers.focus_message()
    end
  end, { buffer = bufnr, desc = "Focus packet template" })
  map_if(keymaps.help, "n", function()
    if self.handlers.open_help then
      self.handlers.open_help()
    end
  end, { buffer = bufnr, desc = "Codex workbench help" })
end

function ListView:_ensure_buffer()
  if valid_buffer(self.bufnr) then
    return self.bufnr
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  self.bufnr = bufnr
  self:_apply_buffer_contract(bufnr)
  self:_bind_keymaps(bufnr)
  return bufnr
end

function ListView:bufnr_value()
  return self:_ensure_buffer()
end

function ListView:set_window(winid)
  self.winid = winid
  if not valid_window(winid) then
    return
  end

  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].wrap = true
  vim.wo[winid].linebreak = true
end

function ListView:update(thread_id, fragments)
  local bufnr = self:_ensure_buffer()
  local lines = {}
  local entries = {}

  vim.b[bufnr].neovim_codex_thread_id = thread_id or ""

  if not thread_id then
    lines = { "_No active thread._" }
  elseif not fragments or #fragments == 0 then
    lines = { "_Workbench is empty._" }
  else
    for _, fragment in ipairs(fragments) do
      local start_line = #lines + 1
      lines[#lines + 1] = string.format("- %s", packet.fragment_summary(fragment))
      local preview = packet.fragment_preview(fragment)
      if preview and preview ~= fragment.label then
        lines[#lines + 1] = string.format("  %s", preview)
      end
      entries[#entries + 1] = {
        fragment = clone_value(fragment),
        line_start = start_line,
        line_end = #lines,
      }
      if #entries < #fragments then
        lines[#lines + 1] = ""
      end
    end
  end

  self.fragments = entries
  self.signature = { thread_id = thread_id, lines = clone_value(lines) }

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

function ListView:current_fragment()
  if not valid_window(self.winid) then
    return nil
  end

  local line = vim.api.nvim_win_get_cursor(self.winid)[1]
  local previous = nil
  for _, entry in ipairs(self.fragments or {}) do
    if contains_line(entry, line) then
      return clone_value(entry.fragment)
    end
    if entry.line_end and entry.line_end < line then
      previous = entry.fragment
    end
  end

  return clone_value(previous)
end

function ListView:inspect()
  return {
    bufnr = self.bufnr,
    winid = self.winid,
    fragments = clone_value(self.fragments or {}),
    signature = clone_value(self.signature),
  }
end

function M.new(opts, role, handlers)
  return setmetatable({
    opts = opts,
    role = role or "workbench",
    handlers = handlers or {},
    bufnr = nil,
    winid = nil,
    fragments = {},
    signature = nil,
  }, ListView)
end

return M
