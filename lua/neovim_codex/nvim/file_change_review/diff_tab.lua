local text_utils = require("neovim_codex.core.text")
local value = require("neovim_codex.core.value")
local surface_help = require("neovim_codex.nvim.surface_help")

local M = {}
M.__index = M

local split_lines = text_utils.split_lines
local display_path = text_utils.display_path
local present = value.present

local function valid_tabpage(tabpage)
  return tabpage and vim.api.nvim_tabpage_is_valid(tabpage)
end

local function valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function escape_statusline(text)
  return tostring(text or ""):gsub("%%", "%%%%")
end

local function array_items(input)
  if type(input) == "table" then
    return input
  end
  return {}
end

local function clamp_index(changes, index)
  local count = #array_items(changes)
  if count == 0 then
    return nil
  end
  index = tonumber(index) or 1
  if index < 1 then
    return 1
  end
  if index > count then
    return count
  end
  return index
end

local function diff_filetype(path)
  if not present(path) then
    return "text"
  end

  local match = vim.filetype.match({ filename = tostring(path) })
  if present(match) then
    return match
  end
  return "text"
end

local function build_hunk_buffers(diff_text)
  if not present(diff_text) then
    return nil
  end

  local left = {}
  local right = {}
  local saw_hunk = false

  for _, line in ipairs(split_lines(diff_text, { empty = { "" } })) do
    if vim.startswith(line, "@@") then
      saw_hunk = true
      left[#left + 1] = line
      right[#right + 1] = line
    elseif vim.startswith(line, "\\ ") then
      left[#left + 1] = line
      right[#right + 1] = line
    elseif vim.startswith(line, "---") or vim.startswith(line, "+++") or vim.startswith(line, "diff ") or vim.startswith(line, "index ") then
      -- Skip unified-diff headers in the split view.
    else
      local prefix = line:sub(1, 1)
      local payload = line:sub(2)
      if prefix == " " then
        left[#left + 1] = payload
        right[#right + 1] = payload
      elseif prefix == "-" then
        left[#left + 1] = payload
      elseif prefix == "+" then
        right[#right + 1] = payload
      else
        left[#left + 1] = line
        right[#right + 1] = line
      end
    end
  end

  if not saw_hunk then
    return nil
  end

  if #left == 0 then
    left = { "" }
  end
  if #right == 0 then
    right = { "" }
  end

  return left, right
end

M._build_hunk_buffers = build_hunk_buffers

local function selected_change(context, index)
  local changes = array_items(context and context.changes)
  local current = clamp_index(changes, index)
  if not current then
    return nil, nil
  end
  return changes[current], current
end

local function set_buffer_content(bufnr, lines, filetype, name)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = filetype or "text"
  if present(name) then
    pcall(vim.api.nvim_buf_set_name, bufnr, name)
  end
  vim.b[bufnr].neovim_codex = true
  vim.b[bufnr].neovim_codex_role = "file_change_review"
end

local function apply_window_options(winid)
  if not valid_window(winid) then
    return
  end
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = true
end

function M.new(opts, handlers)
  return setmetatable({
    opts = opts or {},
    handlers = handlers or {},
    tabpage = nil,
    left_win = nil,
    right_win = nil,
    left_buf = nil,
    right_buf = nil,
    current_request_key = nil,
  }, M)
end

function M:is_open()
  if not valid_tabpage(self.tabpage) then
    self.tabpage = nil
    self.left_win = nil
    self.right_win = nil
    self.left_buf = nil
    self.right_buf = nil
    self.current_request_key = nil
    return false
  end
  return true
end

function M:close()
  if not self:is_open() then
    return false
  end

  local tabpage = self.tabpage
  local tabnr = vim.api.nvim_tabpage_get_number(tabpage)
  self.tabpage = nil
  self.left_win = nil
  self.right_win = nil
  self.left_buf = nil
  self.right_buf = nil
  self.current_request_key = nil

  vim.cmd(string.format("tabclose %d", tabnr))
  return true
end

function M:_map_buffer(bufnr)
  if not valid_buffer(bufnr) then
    return
  end

  local keymaps = (((self.opts or {}).keymaps or {}).file_change_review) or {}

  local function map(lhs, rhs, desc)
    if lhs == false or lhs == nil then
      return
    end
    vim.keymap.set("n", lhs, rhs, {
      buffer = bufnr,
      silent = true,
      nowait = true,
      desc = desc,
    })
  end

  map(keymaps.open_file or "o", function()
    if self.handlers.refresh_current then
      self.handlers.refresh_current()
    end
  end, "Refresh the selected Codex file diff")
  map(keymaps.next_file or "]f", function()
    if self.handlers.next_file then
      self.handlers.next_file()
    end
  end, "Move to the next changed file")
  map(keymaps.prev_file or "[f", function()
    if self.handlers.prev_file then
      self.handlers.prev_file()
    end
  end, "Move to the previous changed file")
  map(keymaps.accept or "a", function()
    if self.handlers.respond then
      self.handlers.respond("accept")
    end
  end, "Approve the current Codex file change once")
  map(keymaps.accept_for_session or "s", function()
    if self.handlers.respond then
      self.handlers.respond("acceptForSession")
    end
  end, "Approve the current Codex file change for this session")
  map(keymaps.decline or "d", function()
    if self.handlers.respond then
      self.handlers.respond("decline")
    end
  end, "Decline the current Codex file change")
  map(keymaps.cancel or "c", function()
    if self.handlers.respond then
      self.handlers.respond("cancel")
    end
  end, "Cancel the current Codex file change review")
  map("q", function()
    self:close()
  end, "Close the Codex diff review tab")

  local primary_help = keymaps.help or "g?"
  map(primary_help, function()
    if self.handlers.open_help then
      self.handlers.open_help()
    end
  end, "Show file change review shortcuts")
  for _, lhs in ipairs(surface_help.keys(self.opts, primary_help)) do
    if lhs ~= primary_help then
      map(lhs, function()
        if self.handlers.open_help then
          self.handlers.open_help()
        end
      end, "Show file change review shortcuts")
    end
  end
end

function M:_set_winbars(change, index, total)
  local path_label = display_path(change.path) or tostring(change.path or "changed file")
  local meta = string.format("%s (%d/%d)", path_label, index or 1, total or 1)
  if valid_window(self.left_win) then
    vim.wo[self.left_win].winbar = escape_statusline(string.format(" Codex Diff · before · %s ", meta))
  end
  if valid_window(self.right_win) then
    vim.wo[self.right_win].winbar = escape_statusline(string.format(" Codex Diff · after · %s ", meta))
  end
end

function M:_render(context, index)
  local change, current = selected_change(context, index)
  if not change then
    return nil, "no changed files are available for review"
  end

  local left_lines, right_lines = build_hunk_buffers(change.diff)
  if not left_lines or not right_lines then
    return nil, "selected file diff is not available"
  end

  local filetype = diff_filetype(change.path)
  local path_label = display_path(change.path) or tostring(change.path or "changed file")

  set_buffer_content(
    self.left_buf,
    left_lines,
    filetype,
    string.format("neovim-codex://review/%s/before", path_label)
  )
  set_buffer_content(
    self.right_buf,
    right_lines,
    filetype,
    string.format("neovim-codex://review/%s/after", path_label)
  )

  self:_set_winbars(change, current, #array_items(context.changes))
  return current, nil
end

function M:_ensure_layout()
  if self:is_open() then
    return true
  end

  vim.cmd("tabnew")
  self.tabpage = vim.api.nvim_get_current_tabpage()
  self.left_win = vim.api.nvim_get_current_win()
  self.left_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(self.left_win, self.left_buf)

  vim.cmd("vsplit")
  self.right_win = vim.api.nvim_get_current_win()
  self.right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(self.right_win, self.right_buf)

  apply_window_options(self.left_win)
  apply_window_options(self.right_win)

  self:_map_buffer(self.left_buf)
  self:_map_buffer(self.right_buf)

  vim.api.nvim_set_current_win(self.left_win)
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(self.right_win)
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(self.left_win)

  return true
end

function M:open(context, index)
  if not self:_ensure_layout() then
    return nil, "failed to open the Codex diff review tab"
  end

  self.current_request_key = context and context.request and context.request.key or nil
  local current, err = self:_render(context, index)
  if err then
    self:close()
    return nil, err
  end

  if valid_tabpage(self.tabpage) then
    vim.api.nvim_set_current_tabpage(self.tabpage)
  end
  if valid_window(self.right_win) then
    vim.api.nvim_set_current_win(self.right_win)
  end

  return current, nil
end

function M:refresh(context, index)
  if not self:is_open() then
    return false
  end

  local current, err = self:_render(context, index)
  if err then
    self:close()
    return false
  end
  return current ~= nil
end

return M
