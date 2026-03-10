local Layout = require("nui.layout")
local Popup = require("nui.popup")

local packet = require("neovim_codex.core.packet")
local list_mod = require("neovim_codex.nvim.workbench.list")
local thread_identity = require("neovim_codex.nvim.thread_identity")

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

local Review = {}
Review.__index = Review

local function summarize_packet_state(message, fragments)
  local analysis = packet.analyze_packet(message or "", fragments or {})
  return analysis, {
    referenced = #analysis.referenced_handles,
    pending = #analysis.unreferenced_handles,
    parked = #analysis.parked_handles,
  }
end

function Review:_ui_size()
  local ui = vim.api.nvim_list_uis()[1]
  return ui and ui.width or vim.o.columns, ui and ui.height or vim.o.lines
end

function Review:_overlay_config()
  local opts = self.opts.ui.workbench.review or {}
  local total_width, total_height = self:_ui_size()
  local width = resolve_dimension(opts.width or 0.84, total_width, 70)
  local height = resolve_dimension(opts.height or 0.76, total_height, 16)

  return {
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

function Review:_layout_box()
  local review_opts = self.opts.ui.workbench.review or {}
  local message_width = review_opts.message_width or 0.64
  local list_width = review_opts.fragments_width or (1 - message_width)

  return Layout.Box({
    Layout.Box(self.message_popup, { size = message_width }),
    Layout.Box(self.list_popup, { size = list_width }),
  }, { dir = "row" })
end

function Review:_apply_message_contract(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_name(bufnr, "neovim-codex://workbench/compose-message")
  vim.b[bufnr].neovim_codex = true
  vim.b[bufnr].neovim_codex_role = "compose_review_message"
end

function Review:_bind_message_keymaps(bufnr)
  local keymaps = self.opts.keymaps.compose_review or {}
  map_if(keymaps.send, { "i", "n" }, function()
    if self.handlers.send then
      self.handlers.send()
    end
  end, { buffer = bufnr, desc = "Send packet" })
  map_if(keymaps.send_normal, "n", function()
    if self.handlers.send then
      self.handlers.send()
    end
  end, { buffer = bufnr, desc = "Send packet" })
  map_if(keymaps.preview, "n", function()
    if self.handlers.preview then
      self.handlers.preview()
    end
  end, { buffer = bufnr, desc = "Preview packet" })
  map_if(keymaps.close, "n", function()
    if self.handlers.close then
      self.handlers.close()
      return
    end
    self:hide()
  end, { buffer = bufnr, desc = "Close compose review" })
  map_if(keymaps.focus_fragments, { "i", "n" }, function()
    self:focus_fragments()
  end, { buffer = bufnr, desc = "Focus staged fragments" })
  map_if(keymaps.help, "n", function()
    if self.handlers.open_help then
      self.handlers.open_help()
    end
  end, { buffer = bufnr, desc = "Codex compose review help" })
end

function Review:_set_titles(message, fragments)
  if not self.container or not self.message_popup or not self.list_popup then
    return
  end

  local analysis, counts = summarize_packet_state(message, fragments)
  local thread_label = self.thread_id and thread_identity.short_id(self.thread_id) or "none"
  local top = string.format(
    " Compose review · thread %s · %d referenced · %d pending · %d parked ",
    thread_label,
    counts.referenced,
    counts.pending,
    counts.parked
  )
  self.container.border:set_text("top", top, "center")

  local message_label = analysis.valid and " Packet template · ready " or " Packet template · needs attention "
  self.message_popup.border:set_text("top", message_label, "left")
  self.list_popup.border:set_text(
    "top",
    string.format(" Staged fragments · %d active · %d parked ", #analysis.active_handles, counts.parked),
    "left"
  )
end

function Review:_create_autocmds(bufnr)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = self.augroup,
    buffer = bufnr,
    callback = function()
      self:_set_titles(self:read_message(), self.fragments)
      if self.handlers.message_changed then
        self.handlers.message_changed(self:read_message())
      end
    end,
  })
end

function Review:_ensure_message_buffer()
  if valid_buffer(self.message_bufnr) then
    return self.message_bufnr
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  self.message_bufnr = bufnr
  self:_apply_message_contract(bufnr)
  self:_bind_message_keymaps(bufnr)
  self:_create_autocmds(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
  return bufnr
end

function Review:_destroy_components()
  pcall(vim.cmd, "stopinsert")

  self.list:set_window(nil)

  if self.layout and self.layout.hide then
    pcall(function()
      self.layout:hide()
    end)
  end

  if self.layout and self.layout.unmount then
    pcall(function()
      self.layout:unmount()
    end)
  end

  if self.message_popup and self.message_popup.unmount then
    pcall(function()
      self.message_popup:unmount()
    end)
  end

  if self.list_popup and self.list_popup.unmount then
    pcall(function()
      self.list_popup:unmount()
    end)
  end

  if self.container and self.container.unmount then
    pcall(function()
      self.container:unmount()
    end)
  end

  self.layout = nil
  self.container = nil
  self.message_popup = nil
  self.list_popup = nil
end

function Review:_ensure_components()
  if self.layout then
    return
  end

  local review_opts = self.opts.ui.workbench.review or {}
  local overlay = self:_overlay_config()

  self.container = Popup({
    enter = false,
    focusable = false,
    zindex = 70,
    relative = "editor",
    position = overlay.position,
    size = overlay.size,
    border = {
      style = review_opts.border or "rounded",
      text = { top = string.format(" Compose review · %s send · %s preview ", ((self.opts.keymaps.compose_review or {}).send or "<C-s>"), ((self.opts.keymaps.compose_review or {}).preview or "P")), top_align = "center" },
    },
    win_options = {
      winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder",
    },
  })

  self.message_popup = Popup({
    enter = false,
    focusable = true,
    zindex = 71,
    border = { style = "single", text = { top = " Packet template ", top_align = "left" } },
    bufnr = self:_ensure_message_buffer(),
    win_options = { winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder" },
  })

  self.list_popup = Popup({
    enter = false,
    focusable = true,
    zindex = 71,
    border = { style = "single", text = { top = " Staged fragments ", top_align = "left" } },
    bufnr = self.list:bufnr_value(),
    win_options = { winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder" },
  })

  self.layout = Layout(self.container, self:_layout_box())

  vim.api.nvim_create_autocmd("VimResized", {
    group = self.augroup,
    callback = function()
      if self.visible then
        self:_refresh_layout()
      end
    end,
  })
end

function Review:_refresh_layout()
  if not self.layout then
    return
  end

  local overlay = self:_overlay_config()
  self.layout:update({
    relative = "editor",
    position = overlay.position,
    size = overlay.size,
  }, self:_layout_box())
  self:_sync_windows()
end

function Review:_sync_windows()
  if valid_window(self.message_popup and self.message_popup.winid) then
    vim.wo[self.message_popup.winid].number = false
    vim.wo[self.message_popup.winid].relativenumber = false
    vim.wo[self.message_popup.winid].signcolumn = "no"
    vim.wo[self.message_popup.winid].wrap = true
    vim.wo[self.message_popup.winid].linebreak = true
  end

  self.list:set_window(self.list_popup and self.list_popup.winid)
end

function Review:read_message()
  local bufnr = self:_ensure_message_buffer()
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

function Review:set_message(text)
  local bufnr = self:_ensure_message_buffer()
  local lines = vim.split(text or "", "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

function Review:focus_message()
  if valid_window(self.message_popup and self.message_popup.winid) then
    vim.api.nvim_set_current_win(self.message_popup.winid)
    vim.cmd("startinsert")
    return true
  end
  return false
end

function Review:focus_fragments()
  if valid_window(self.list_popup and self.list_popup.winid) then
    vim.api.nvim_set_current_win(self.list_popup.winid)
    return true
  end
  return false
end

function Review:insert_current_handle()
  return self:insert_handle(self:current_fragment())
end

function Review:insert_handle(fragment)
  local token = packet.handle_token(fragment)
  if not token then
    return false
  end

  local winid = self.message_popup and self.message_popup.winid or nil
  if not valid_window(winid) then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local row = cursor[1]
  local col = cursor[2]
  local bufnr = self:_ensure_message_buffer()
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  local next_line = line:sub(1, col) .. token .. line:sub(col + 1)
  vim.api.nvim_buf_set_lines(bufnr, row - 1, row, false, { next_line })
  vim.api.nvim_win_set_cursor(winid, { row, col + #token })
  self:focus_message()
  self:_set_titles(self:read_message(), self.fragments)
  return true
end

function Review:current_fragment()
  return self.list:current_fragment()
end

function Review:show(thread_id, message, fragments)
  if self.layout and not self.visible then
    self:_destroy_components()
  end
  self:_ensure_components()
  self.thread_id = thread_id
  self.fragments = fragments or {}
  self.list:update(thread_id, self.fragments)
  self:set_message(message or "")

  self.layout:show()

  self.visible = true
  self:_set_titles(message or "", self.fragments)
  self:_refresh_layout()
  self:_sync_windows()
  self:focus_message()
end

function Review:update(thread_id, message, fragments)
  self.thread_id = thread_id
  self.fragments = fragments or {}
  if not self.visible then
    return
  end

  self.list:update(thread_id, self.fragments)
  if message ~= nil and message ~= self:read_message() then
    self:set_message(message)
  end
  self:_set_titles(self:read_message(), self.fragments)
  self:_sync_windows()
end

function Review:hide()
  if not self.layout or not self.visible then
    return
  end
  self.visible = false
  self:_destroy_components()
end

function Review:is_visible()
  return self.visible
end

function Review:inspect()
  return {
    visible = self.visible,
    thread_id = self.thread_id,
    fragments = self.fragments,
    message_bufnr = self.message_bufnr,
    message_win = self.message_popup and self.message_popup.winid or nil,
    list = self.list:inspect(),
  }
end

function M.new(opts, handlers)
  local review = setmetatable({
    opts = opts,
    handlers = handlers or {},
    visible = false,
    thread_id = nil,
    fragments = {},
    augroup = vim.api.nvim_create_augroup("NeovimCodexComposeReview", { clear = false }),
    message_bufnr = nil,
  }, Review)

  review.list = list_mod.new(opts, "compose_review_fragments", {
    close = function()
      if handlers.close then
        handlers.close()
        return
      end
      review:hide()
    end,
    inspect = function()
      if handlers.inspect then
        handlers.inspect(review:current_fragment())
      end
    end,
    remove = function()
      if handlers.remove then
        handlers.remove(review:current_fragment())
      end
    end,
    clear = function()
      if handlers.clear then
        handlers.clear()
      end
    end,
    insert_handle = function()
      review:insert_current_handle()
    end,
    park = function()
      if handlers.park then
        handlers.park(review:current_fragment())
      end
    end,
    unpark = function()
      if handlers.unpark then
        handlers.unpark(review:current_fragment())
      end
    end,
    preview = function()
      if handlers.preview then
        handlers.preview()
      end
    end,
    focus_message = function()
      review:focus_message()
    end,
    open_help = handlers.open_help,
  })

  return review
end

return M
