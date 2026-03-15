local Layout = require("nui.layout")
local Popup = require("nui.popup")
local Line = require("nui.line")
local Text = require("nui.text")
local readonly_surface = require("neovim_codex.nvim.readonly_surface")
local chat_layout = require("neovim_codex.nvim.chat.layout")

local M = {}

local surface_help = require("neovim_codex.nvim.surface_help")

local namespace = vim.api.nvim_create_namespace("neovim_codex.chat.surface")

local HEADER_HIGHLIGHTS = {
  turn_heading = "NeovimCodexChatTurnHeading",
  message_user = "NeovimCodexChatUserHeading",
  message_assistant = "NeovimCodexChatAssistantHeading",
  assistant_note = "NeovimCodexChatReasoningHeading",
  plan = "NeovimCodexChatPlanHeading",
  reasoning = "NeovimCodexChatReasoningHeading",
  activity = "NeovimCodexChatActivityHeading",
  command_detail = "NeovimCodexChatCommandHeading",
  file_change = "NeovimCodexChatFileChangeHeading",
  tool = "NeovimCodexChatToolHeading",
  review = "NeovimCodexChatReviewHeading",
  notice = "NeovimCodexChatNoticeHeading",
  metadata = "NeovimCodexChatNoticeHeading",
  unknown = "NeovimCodexChatNoticeHeading",
}

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function buffer_is_codex_owned(bufnr)
  return valid_buffer(bufnr) and vim.b[bufnr].neovim_codex == true
end

local function window_is_auxiliary(winid)
  if not valid_window(winid) then
    return false
  end

  local config = vim.api.nvim_win_get_config(winid)
  if config and config.relative and config.relative ~= "" then
    return true
  end

  if vim.wo[winid].previewwindow then
    return true
  end

  return false
end

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

local function define_default_highlight(name, target)
  vim.api.nvim_set_hl(0, name, {
    default = true,
    link = target,
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

local function normalize_lines(lines)
  local out = {}
  for _, line in ipairs(lines or {}) do
    local value = tostring(line)
    local split = vim.split(value, "\n", { plain = true })
    if #split == 0 then
      out[#out + 1] = ""
    else
      for _, part in ipairs(split) do
        out[#out + 1] = part
      end
    end
  end
  return out
end

local function clone_lines(lines)
  return normalize_lines(lines)
end

local function block_signature(block)
  return {
    id = block.id,
    kind = block.kind,
    surface = block.surface,
    turn_id = block.turn_id,
    item_id = block.item_id,
    collapsed_by_default = block.collapsed_by_default == true,
    line_start = block.line_start,
    line_end = block.line_end,
    header_line_start = block.header_line_start,
    header_line_end = block.header_line_end,
  }
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

local function render_signature(render_result)
  local block_signatures = {}
  for _, block in ipairs(render_result.blocks or {}) do
    block_signatures[#block_signatures + 1] = block_signature(block)
  end

  return {
    thread_id = render_result.thread_id,
    footer = render_result.footer,
    footer_segments = clone_value(render_result.footer_segments),
    lines = clone_lines(render_result.lines),
    turn_lines = clone_value(render_result.turn_lines or {}),
    blocks = block_signatures,
  }
end

local Surface = {}
Surface.__index = Surface

function Surface:_ensure_highlights()
  define_default_highlight("NeovimCodexChatTurnHeading", "Title")
  define_default_highlight("NeovimCodexChatUserHeading", "Identifier")
  define_default_highlight("NeovimCodexChatAssistantHeading", "Function")
  define_default_highlight("NeovimCodexChatPlanHeading", "Type")
  define_default_highlight("NeovimCodexChatReasoningHeading", "Comment")
  define_default_highlight("NeovimCodexChatActivityHeading", "Special")
  define_default_highlight("NeovimCodexChatCommandHeading", "Statement")
  define_default_highlight("NeovimCodexChatFileChangeHeading", "PreProc")
  define_default_highlight("NeovimCodexChatToolHeading", "Type")
  define_default_highlight("NeovimCodexChatReviewHeading", "MoreMsg")
  define_default_highlight("NeovimCodexChatNoticeHeading", "Comment")
  define_default_highlight("NeovimCodexChatFooterMeta", "Comment")
  define_default_highlight("NeovimCodexChatFooterThread", "Identifier")
end

function Surface:_overlay_config()
  return chat_layout.overlay_config(self.opts, self.shell_mode)
end

function Surface:_shell_title()
  return chat_layout.shell_title(self.shell_mode, self.last_render)
end

function Surface:_composer_total_height(total_height)
  local body_height = self.composer:body_height_value()
  local wanted = body_height + 2
  return math.min(math.max(wanted, 5), math.max(5, total_height - 6))
end

function Surface:_layout_box()
  local config = self:_overlay_config()
  local total_height = config.size.height
  local composer_height = self:_composer_total_height(total_height)
  local transcript_height = math.max(6, total_height - composer_height)

  return Layout.Box({
    Layout.Box(self.transcript_popup, { size = transcript_height }),
    Layout.Box(self.composer_popup, { size = composer_height }),
  }, { dir = "col" })
end

function Surface:_apply_transcript_contract(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_name(bufnr, "neovim-codex://chat/transcript")
  vim.b[bufnr].neovim_codex = true
  vim.b[bufnr].neovim_codex_role = "transcript"
end

function Surface:_bind_transcript_keymaps(bufnr)
  local keymaps = self.opts.keymaps.transcript or {}
  map_if(keymaps.close, "n", function()
    if self.handlers.close_overlay then
      self.handlers.close_overlay()
      return
    end
    self:hide()
  end, { buffer = bufnr, desc = "Hide Codex overlay" })
  map_if(keymaps.focus_composer, "n", function()
    self.handlers.focus_composer()
  end, { buffer = bufnr, desc = "Focus Codex composer" })
  for _, lhs in ipairs({ "a", "A", "i", "I", "o", "O", "R" }) do
    vim.keymap.set("n", lhs, function()
      self.handlers.focus_composer()
    end, {
      buffer = bufnr,
      silent = true,
      nowait = true,
      desc = "Focus Codex composer",
    })
  end
  map_if(keymaps.switch_pane, { "n", "i" }, function()
    self:focus_next_pane()
  end, { buffer = bufnr, desc = "Switch Codex chat pane" })
  map_if(keymaps.request, "n", function()
    if self.handlers.open_request then
      self.handlers.open_request()
    end
  end, { buffer = bufnr, desc = "Open Codex inbox" })
  map_if(keymaps.toggle_reader, "n", function()
    if self.handlers.toggle_reader then
      self.handlers.toggle_reader()
    end
  end, { buffer = bufnr, desc = "Toggle Codex reader width" })
  map_if(keymaps.inspect, "n", function()
    self.handlers.inspect_current_block()
  end, { buffer = bufnr, desc = "Inspect current Codex block" })
  map_if(keymaps.next_turn, "n", function()
    self:goto_turn(1)
  end, { buffer = bufnr, desc = "Next Codex turn" })
  map_if(keymaps.prev_turn, "n", function()
    self:goto_turn(-1)
  end, { buffer = bufnr, desc = "Previous Codex turn" })
  surface_help.bind(map_if, self.opts, keymaps.help, "n", function()
    self.handlers.open_help()
  end, { buffer = bufnr, desc = "Codex chat help" })
end

function Surface:_ensure_transcript_buffer()
  if valid_buffer(self.transcript_bufnr) then
    return self.transcript_bufnr
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  self.transcript_bufnr = bufnr
  self:_apply_transcript_contract(bufnr)
  self:_bind_transcript_keymaps(bufnr)
  readonly_surface.attach(bufnr, {
    augroup = self.augroup,
    is_target_active = function()
      return valid_window(self.transcript_popup and self.transcript_popup.winid)
        and vim.api.nvim_get_current_win() == self.transcript_popup.winid
    end,
    on_insert_attempt = function()
      if self.handlers.focus_composer then
        self.handlers.focus_composer()
        return true
      end
      return false
    end,
  })
  return bufnr
end

function Surface:_ensure_components()
  if self.layout then
    return
  end

  local chat_opts = self.opts.ui.chat
  local overlay = self:_overlay_config()
  local transcript_bufnr = self:_ensure_transcript_buffer()
  local composer_bufnr = self.composer:bufnr_value()

  self.container = Popup({
    enter = false,
    focusable = false,
    relative = "editor",
    position = overlay.position,
    size = overlay.size,
    border = {
      style = (chat_opts.layout or {}).border or "rounded",
      text = {
        top = self:_shell_title(),
        top_align = "center",
        bottom = "",
        bottom_align = "left",
      },
    },
    win_options = {
      winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder",
    },
  })

  self.transcript_popup = Popup({
    enter = false,
    focusable = true,
    border = "none",
    bufnr = transcript_bufnr,
    win_options = {
      winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder",
    },
  })

  self.composer_popup = Popup({
    enter = false,
    focusable = true,
    border = {
      style = "single",
      text = {
        top = chat_layout.composer_title(self.opts, self.shell_mode),
        top_align = "left",
      },
    },
    bufnr = composer_bufnr,
    win_options = {
      winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder",
    },
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

  vim.api.nvim_create_autocmd("WinEnter", {
    group = self.augroup,
    callback = function()
      vim.schedule(function()
        self:_handle_focus_change()
      end)
    end,
  })
end

function Surface:_refresh_layout()
  if not self.layout then
    return
  end

  local overlay = self:_overlay_config()
  if self.container then
    self.container.border:set_text("top", self:_shell_title(), "center")
  end
  if self.composer_popup then
    self.composer_popup.border:set_text("top", chat_layout.composer_title(self.opts, self.shell_mode), "left")
  end
  self.layout:update({
    relative = "editor",
    position = overlay.position,
    size = overlay.size,
  }, self:_layout_box())
  self:_sync_windows()
end

function Surface:_set_footer(text, segments)
  if not self.container then
    return
  end

  self.container.border:set_text("top", self:_shell_title(), "center")

  if type(segments) == "table" and #segments > 0 then
    local line = Line()
    for _, segment in ipairs(segments) do
      line:append(Text(segment.text or "", segment.highlight))
    end
    self.container.border:set_text("bottom", line, "left")
    return
  end

  self.container.border:set_text("bottom", text or "", "left")
end

function Surface:_is_overlay_window(winid)
  if not valid_window(winid) then
    return false
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  return buffer_is_codex_owned(bufnr)
end

function Surface:_handle_focus_change()
  if not self.visible then
    return
  end

  local current = vim.api.nvim_get_current_win()
  if self:_is_overlay_window(current) or window_is_auxiliary(current) then
    return
  end

  if self.handlers.close_overlay then
    self.handlers.close_overlay()
    return
  end

  self:hide()
end

function Surface:_sync_windows()
  if valid_window(self.transcript_popup and self.transcript_popup.winid) then
    local transcript_opts = self.opts.ui.chat.transcript or {}
    vim.wo[self.transcript_popup.winid].number = false
    vim.wo[self.transcript_popup.winid].relativenumber = false
    vim.wo[self.transcript_popup.winid].signcolumn = "no"
    vim.wo[self.transcript_popup.winid].foldcolumn = "0"
    vim.wo[self.transcript_popup.winid].wrap = transcript_opts.wrap ~= false
    vim.wo[self.transcript_popup.winid].linebreak = transcript_opts.wrap ~= false
  end

  self.composer:set_window(self.composer_popup and self.composer_popup.winid)
end

function Surface:_update_thread_context(thread_id)
  local value = thread_id or ""
  if valid_buffer(self.transcript_bufnr) then
    vim.b[self.transcript_bufnr].neovim_codex_thread_id = value
  end
  local composer_bufnr = self.composer:bufnr_value()
  if valid_buffer(composer_bufnr) then
    vim.b[composer_bufnr].neovim_codex_thread_id = value
  end
end

function Surface:_render_blocks(blocks)
  self.block_ranges = clone_value(blocks or {})
  vim.api.nvim_buf_clear_namespace(self.transcript_bufnr, namespace, 0, -1)

  for _, block in ipairs(self.block_ranges) do
    if block.line_start and block.line_end and block.line_end >= block.line_start then
      vim.api.nvim_buf_set_extmark(self.transcript_bufnr, namespace, block.line_start - 1, 0, {
        end_row = block.line_end,
        hl_mode = "combine",
      })
    end

    local highlight = HEADER_HIGHLIGHTS[block.surface] or HEADER_HIGHLIGHTS[block.kind]
    if highlight and block.header_line_start and block.header_line_end then
      for line = block.header_line_start, block.header_line_end do
        vim.api.nvim_buf_add_highlight(self.transcript_bufnr, namespace, highlight, line - 1, 0, -1)
      end
    end
  end
end

function Surface:_set_transcript_lines(lines)
  local normalized = normalize_lines(lines or { "" })
  if #normalized == 0 then
    normalized = { "" }
  end
  local cursor_at_end = false
  local previous_count = self.last_line_count or 1

  if valid_window(self.transcript_popup and self.transcript_popup.winid) then
    local current = vim.api.nvim_get_current_win()
    if current ~= self.transcript_popup.winid then
      cursor_at_end = true
    else
      local cursor = vim.api.nvim_win_get_cursor(self.transcript_popup.winid)
      cursor_at_end = cursor[1] >= math.max(1, previous_count - 1)
    end
  end

  vim.bo[self.transcript_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.transcript_bufnr, 0, -1, false, normalized)
  vim.bo[self.transcript_bufnr].modifiable = false
  self.last_line_count = #normalized

  if cursor_at_end and valid_window(self.transcript_popup and self.transcript_popup.winid) then
    vim.api.nvim_win_set_cursor(self.transcript_popup.winid, { math.max(1, #normalized), 0 })
  end
end

function Surface:show()
  if self.layout and self.layout._ and self.layout._.mounted then
    local stale = not valid_window(self.container and self.container.winid)
      or not valid_window(self.transcript_popup and self.transcript_popup.winid)
      or not valid_window(self.composer_popup and self.composer_popup.winid)
    if stale then
      self.layout = nil
      self.container = nil
      self.transcript_popup = nil
      self.composer_popup = nil
    end
  end

  self:_ensure_components()

  if self.visible then
    self:_sync_windows()
    return
  end

  self.layout:show()

  self.visible = true
  self:_refresh_layout()
  self:_sync_windows()
end

function Surface:hide()
  if not self.layout or not self.visible then
    return
  end

  vim.cmd("stopinsert")

  local windows = {
    self.composer_popup and self.composer_popup.winid or nil,
    self.transcript_popup and self.transcript_popup.winid or nil,
    self.container and self.container.winid or nil,
  }

  pcall(function()
    self.layout:unmount()
  end)

  for _, winid in ipairs(windows) do
    if valid_window(winid) then
      pcall(vim.api.nvim_win_close, winid, true)
    end
  end

  self.visible = false
  self.layout = nil
  self.container = nil
  self.transcript_popup = nil
  self.composer_popup = nil
end

function Surface:toggle()
  if self.visible then
    self:hide()
  else
    self:show()
  end
end

function Surface:set_mode(mode)
  local next_mode = chat_layout.normalize_mode(mode, self.opts)
  if next_mode == self.shell_mode then
    return
  end

  self.shell_mode = next_mode
  if self.visible then
    self:hide()
  end
end

function Surface:mode()
  return self.shell_mode
end

function Surface:is_visible()
  return self.visible
end

function Surface:update(render_result)
  self:_ensure_components()

  local next_signature = render_signature(render_result)
  local previous_signature = self.last_signature
  local thread_changed = not previous_signature or previous_signature.thread_id ~= next_signature.thread_id
  local footer_changed = not previous_signature or previous_signature.footer ~= next_signature.footer or not vim.deep_equal(previous_signature.footer_segments, next_signature.footer_segments)
  local lines_changed = not previous_signature or not vim.deep_equal(previous_signature.lines, next_signature.lines)
  local blocks_changed = not previous_signature or not vim.deep_equal(previous_signature.blocks, next_signature.blocks)
  local turn_lines_changed = not previous_signature or not vim.deep_equal(previous_signature.turn_lines, next_signature.turn_lines)

  self.last_render = render_result
  self.last_signature = next_signature

  if not (thread_changed or footer_changed or lines_changed or blocks_changed or turn_lines_changed) then
    return
  end

  self.update_count = (self.update_count or 0) + 1

  if thread_changed then
    self:_update_thread_context(render_result.thread_id)
  end
  if footer_changed then
    self:_set_footer(render_result.footer, render_result.footer_segments)
  end
  if lines_changed then
    self:_set_transcript_lines(render_result.lines)
  end
  if lines_changed or blocks_changed then
    self:_render_blocks(render_result.blocks)
  end

end

function Surface:set_composer_height(_)
  if self.visible then
    self:_refresh_layout()
  end
end

local function contains_line(block, line)
  return block.line_start and block.line_end and line >= block.line_start and line <= block.line_end
end

function Surface:current_block()
  if not valid_window(self.transcript_popup and self.transcript_popup.winid) then
    return nil
  end

  local cursor_line = vim.api.nvim_win_get_cursor(self.transcript_popup.winid)[1]
  local previous = nil
  for _, block in ipairs(self.block_ranges or {}) do
    if contains_line(block, cursor_line) then
      return clone_value(block)
    end
    if block.line_end and block.line_end < cursor_line then
      previous = block
    end
  end

  return clone_value(previous)
end

function Surface:goto_turn(direction)
  if not valid_window(self.transcript_popup and self.transcript_popup.winid) then
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(self.transcript_popup.winid)[1]
  local target = nil

  if direction > 0 then
    for _, line in ipairs(self.last_render and self.last_render.turn_lines or {}) do
      if line > cursor_line then
        target = line
        break
      end
    end
  else
    for index = #(self.last_render and self.last_render.turn_lines or {}), 1, -1 do
      local line = self.last_render.turn_lines[index]
      if line < cursor_line then
        target = line
        break
      end
    end
  end

  if target then
    vim.api.nvim_set_current_win(self.transcript_popup.winid)
    vim.api.nvim_win_set_cursor(self.transcript_popup.winid, { target, 0 })
  end
end

function Surface:focus_composer()
  self:show()
  return self.composer:focus()
end

function Surface:focus_transcript()
  self:show()
  if not valid_window(self.transcript_popup and self.transcript_popup.winid) then
    return false
  end

  vim.api.nvim_set_current_win(self.transcript_popup.winid)
  vim.cmd("stopinsert")
  return true
end

function Surface:focus_next_pane()
  local current = vim.api.nvim_get_current_win()
  if current == (self.transcript_popup and self.transcript_popup.winid) then
    return self:focus_composer()
  end
  return self:focus_transcript()
end

function Surface:inspect()
  return {
    visible = self.visible,
    transcript_buf = self.transcript_bufnr,
    transcript_win = self.transcript_popup and self.transcript_popup.winid or nil,
    container_win = self.container and self.container.winid or nil,
    composer_buf = self.composer:bufnr_value(),
    composer_win = self.composer_popup and self.composer_popup.winid or nil,
    prompt_buf = self.composer:bufnr_value(),
    prompt_win = self.composer_popup and self.composer_popup.winid or nil,
    blocks = clone_value(self.block_ranges or {}),
    turn_lines = clone_value(self.last_render and self.last_render.turn_lines or {}),
    current_block = self:current_block(),
    update_count = self.update_count or 0,
    mode = self.shell_mode,
  }
end

function M.new(opts, handlers)
  local surface = setmetatable({
    opts = opts,
    handlers = handlers,
    composer = handlers.composer,
    transcript_bufnr = nil,
    layout = nil,
    container = nil,
    transcript_popup = nil,
    composer_popup = nil,
    visible = false,
    block_ranges = {},
    last_render = nil,
    last_signature = nil,
    last_line_count = 1,
    augroup = vim.api.nvim_create_augroup("NeovimCodexChatSurface", { clear = false }),
    shell_mode = chat_layout.normalize_mode(nil, opts),
  }, Surface)

  surface:_ensure_highlights()
  surface:_ensure_components()
  return surface
end

return M
