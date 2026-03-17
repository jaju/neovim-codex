local M = {}

local surface_help = require("neovim_codex.nvim.surface_help")

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local Composer = {}
Composer.__index = Composer

local function map_if(lhs, mode, rhs, opts)
  if not lhs then
    return
  end
  vim.keymap.set(mode, lhs, rhs, {
    buffer = opts.buffer,
    silent = true,
    nowait = true,
    desc = opts.desc,
  })
end

function Composer:_apply_buffer_contract(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_name(bufnr, "neovim-codex://chat/composer")
  vim.b[bufnr].neovim_codex = true
  vim.b[bufnr].neovim_codex_role = "composer"
end

function Composer:_bind_keymaps(bufnr)
  local keymaps = self.opts.keymaps.composer or {}
  map_if(keymaps.send, { "i", "n" }, function()
    self.handlers.send()
  end, { buffer = bufnr, desc = "Send Codex prompt" })
  map_if(keymaps.send_normal, "n", function()
    self.handlers.send()
  end, { buffer = bufnr, desc = "Send Codex prompt" })
  map_if(keymaps.steer, { "i", "n" }, function()
    if self.handlers.steer then
      self.handlers.steer()
    end
  end, { buffer = bufnr, desc = "Steer the active Codex turn" })
  map_if(keymaps.switch_pane, "n", function()
    if self.handlers.focus_transcript then
      self.handlers.focus_transcript()
    end
  end, { buffer = bufnr, desc = "Switch Codex chat pane" })
  map_if(keymaps.request, { "n", "i" }, function()
    if self.handlers.open_request then
      self.handlers.open_request()
    end
  end, { buffer = bufnr, desc = "Open Codex inbox" })
  map_if(keymaps.settings, { "n", "i" }, function()
    if self.handlers.open_thread_settings then
      self.handlers.open_thread_settings()
    end
  end, { buffer = bufnr, desc = "Open Codex thread settings" })
  map_if(keymaps.toggle_reader, { "n", "i" }, function()
    if self.handlers.toggle_reader then
      self.handlers.toggle_reader()
    end
  end, { buffer = bufnr, desc = "Toggle Codex reader width" })
  map_if(keymaps.close, "n", function()
    self.handlers.hide()
  end, { buffer = bufnr, desc = "Hide Codex overlay" })
  surface_help.bind(map_if, self.opts, keymaps.help, { "n", "i" }, function()
    self.handlers.open_help()
  end, { buffer = bufnr, desc = "Codex chat help" })
end

function Composer:_refresh_height()
  if not valid_buffer(self.bufnr) then
    return
  end

  local composer_opts = self.opts.ui.chat.composer or {}
  local line_count = vim.api.nvim_buf_line_count(self.bufnr)
  local next_height = clamp(line_count, composer_opts.min_height, composer_opts.max_height)
  if next_height == self.body_height then
    return
  end

  self.body_height = next_height
  if self.handlers.on_height_changed then
    self.handlers.on_height_changed(next_height)
  end
end

function Composer:_create_autocmds(bufnr)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = self.augroup,
    buffer = bufnr,
    callback = function()
      self:_refresh_height()
    end,
  })
end

function Composer:_ensure_buffer()
  if valid_buffer(self.bufnr) then
    return self.bufnr
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  self.bufnr = bufnr
  self:_apply_buffer_contract(bufnr)
  self:_bind_keymaps(bufnr)
  self:_create_autocmds(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
  self:_refresh_height()
  return bufnr
end

function Composer:bufnr_value()
  return self:_ensure_buffer()
end

function Composer:set_window(winid)
  self.winid = winid
  if not valid_window(winid) then
    return
  end

  local win_opts = self.opts.ui.chat.composer or {}
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].wrap = win_opts.wrap ~= false
  vim.wo[winid].linebreak = win_opts.wrap ~= false
end

function Composer:focus()
  if not valid_window(self.winid) then
    return false
  end

  vim.api.nvim_set_current_win(self.winid)
  vim.cmd("startinsert")
  return true
end

function Composer:read()
  if not valid_buffer(self:_ensure_buffer()) then
    return ""
  end
  return table.concat(vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false), "\n")
end

function Composer:set_text(text)
  self:_ensure_buffer()
  local lines = vim.split(text or "", "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  self:_refresh_height()
end

function Composer:clear()
  self:set_text("")
end

function Composer:body_height_value()
  self:_ensure_buffer()
  return self.body_height
end

function Composer:inspect()
  return {
    bufnr = self.bufnr,
    winid = self.winid,
    body_height = self.body_height,
  }
end

function M.new(opts, handlers)
  local composer = setmetatable({
    opts = opts,
    handlers = handlers,
    augroup = vim.api.nvim_create_augroup("NeovimCodexComposer", { clear = false }),
    bufnr = nil,
    winid = nil,
    body_height = (opts.ui.chat.composer or {}).default_height or 8,
  }, Composer)

  composer:_ensure_buffer()
  return composer
end

return M
