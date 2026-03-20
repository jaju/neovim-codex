local text_utils = require("neovim_codex.core.text")
local value = require("neovim_codex.core.value")
local chat_layout = require("neovim_codex.nvim.chat.layout")
local readonly_surface = require("neovim_codex.nvim.readonly_surface")
local surface_help = require("neovim_codex.nvim.surface_help")

local M = {}

local namespace = vim.api.nvim_create_namespace("neovim_codex.chat.rail")

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

local function window_is_chat_shell(winid)
  return valid_window(winid) and vim.w[winid].neovim_codex_chat_shell == true
end

local function define_default_highlight(name, target)
  vim.api.nvim_set_hl(0, name, {
    default = true,
    link = target,
  })
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

local function normalize_lines(lines)
  return text_utils.split_lines(lines, { empty = { "" } })
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

local function render_signature(render_result)
  local block_signatures = {}
  for _, block in ipairs(render_result.blocks or {}) do
    block_signatures[#block_signatures + 1] = block_signature(block)
  end

  return {
    thread_id = render_result.thread_id,
    footer = render_result.footer,
    footer_segments = value.deep_copy(render_result.footer_segments),
    lines = clone_lines(render_result.lines),
    turn_lines = value.deep_copy(render_result.turn_lines or {}),
    blocks = block_signatures,
  }
end

local RailSplit = {}
RailSplit.__index = RailSplit

function RailSplit:_ensure_highlights()
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
end

function RailSplit:_composer_total_height()
  local body_height = self.composer:body_height_value()
  local wanted = body_height + 2
  return math.min(math.max(wanted, 5), math.max(5, vim.o.lines - 8))
end

function RailSplit:_apply_transcript_contract(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_name(bufnr, "neovim-codex://chat/transcript/rail")
  vim.b[bufnr].neovim_codex = true
  vim.b[bufnr].neovim_codex_role = "transcript"
end

function RailSplit:_bind_transcript_keymaps(bufnr)
  local keymaps = self.opts.keymaps.transcript or {}
  map_if(keymaps.close, "n", function()
    if self.handlers.close_overlay then
      self.handlers.close_overlay()
      return
    end
    self:hide()
  end, { buffer = bufnr, desc = "Close Codex chat shell" })
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
  map_if(keymaps.settings, "n", function()
    if self.handlers.open_thread_settings then
      self.handlers.open_thread_settings()
    end
  end, { buffer = bufnr, desc = "Open Codex thread settings" })
  map_if(keymaps.toggle_reader, "n", function()
    if self.handlers.toggle_reader then
      self.handlers.toggle_reader()
    end
  end, { buffer = bufnr, desc = "Switch Codex chat shell" })
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

function RailSplit:_ensure_transcript_buffer()
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
      return valid_window(self.transcript_win)
        and vim.api.nvim_get_current_win() == self.transcript_win
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

function RailSplit:_update_thread_context(thread_id)
  local current = thread_id or ""
  if valid_buffer(self.transcript_bufnr) then
    vim.b[self.transcript_bufnr].neovim_codex_thread_id = current
  end
  local composer_bufnr = self.composer:bufnr_value()
  if valid_buffer(composer_bufnr) then
    vim.b[composer_bufnr].neovim_codex_thread_id = current
  end
end

function RailSplit:_refresh_titles()
  if valid_window(self.transcript_win) then
    vim.wo[self.transcript_win].winbar = chat_layout.shell_title("rail", self.last_render)
    vim.wo[self.transcript_win].statusline = self.last_render and (self.last_render.footer or "") or ""
  end
  if valid_window(self.composer_win) then
    vim.wo[self.composer_win].winbar = chat_layout.composer_title(self.opts, "rail")
  end
end

function RailSplit:_sync_windows()
  if valid_window(self.transcript_win) then
    local transcript_opts = self.opts.ui.chat.transcript or {}
    vim.w[self.transcript_win].neovim_codex_chat_shell = true
    vim.w[self.transcript_win].neovim_codex_chat_role = "transcript"
    vim.wo[self.transcript_win].number = false
    vim.wo[self.transcript_win].relativenumber = false
    vim.wo[self.transcript_win].signcolumn = "no"
    vim.wo[self.transcript_win].foldcolumn = "0"
    vim.wo[self.transcript_win].wrap = transcript_opts.wrap ~= false
    vim.wo[self.transcript_win].linebreak = transcript_opts.wrap ~= false
    vim.wo[self.transcript_win].winfixwidth = true
  end

  if valid_window(self.composer_win) then
    vim.w[self.composer_win].neovim_codex_chat_shell = true
    vim.w[self.composer_win].neovim_codex_chat_role = "composer"
    vim.wo[self.composer_win].winfixwidth = true
  end

  self.composer:set_window(self.composer_win)
  self:_refresh_titles()
end

function RailSplit:_ensure_windows()
  local stale = self.visible
    and (not valid_window(self.transcript_win) or not valid_window(self.composer_win))
  if stale then
    self.visible = false
    self.transcript_win = nil
    self.composer_win = nil
  end

  if self.visible then
    self:_sync_windows()
    return
  end

  local transcript_bufnr = self:_ensure_transcript_buffer()
  local composer_bufnr = self.composer:bufnr_value()
  local dimensions = chat_layout.rail_dimensions(self.opts)
  local current = vim.api.nvim_get_current_win()

  if valid_window(current)
    and not window_is_chat_shell(current)
    and not buffer_is_codex_owned(vim.api.nvim_win_get_buf(current))
  then
    self.last_editor_win = current
  end

  vim.cmd("botright vsplit")
  self.transcript_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(self.transcript_win, transcript_bufnr)
  vim.api.nvim_win_set_width(self.transcript_win, dimensions.width)

  vim.cmd("belowright split")
  self.composer_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(self.composer_win, composer_bufnr)
  vim.api.nvim_win_set_height(self.composer_win, self:_composer_total_height())

  if valid_window(self.transcript_win) then
    vim.api.nvim_set_current_win(self.transcript_win)
  end

  self.visible = true
  self:_sync_windows()
end

function RailSplit:_render_blocks(blocks)
  self.block_ranges = value.deep_copy(blocks or {})
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

function RailSplit:_set_transcript_lines(lines)
  local normalized = normalize_lines(lines or { "" })
  if #normalized == 0 then
    normalized = { "" }
  end
  local cursor_at_end = false
  local previous_count = self.last_line_count or 1

  if valid_window(self.transcript_win) then
    local current = vim.api.nvim_get_current_win()
    if current ~= self.transcript_win then
      cursor_at_end = true
    else
      local cursor = vim.api.nvim_win_get_cursor(self.transcript_win)
      cursor_at_end = cursor[1] >= math.max(1, previous_count - 1)
    end
  end

  vim.bo[self.transcript_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.transcript_bufnr, 0, -1, false, normalized)
  vim.bo[self.transcript_bufnr].modifiable = false
  self.last_line_count = #normalized

  if cursor_at_end and valid_window(self.transcript_win) then
    vim.api.nvim_win_set_cursor(self.transcript_win, { math.max(1, #normalized), 0 })
  end
end

function RailSplit:show()
  self:_ensure_windows()
end

function RailSplit:hide()
  if not self.visible
    and not valid_window(self.transcript_win)
    and not valid_window(self.composer_win)
  then
    return
  end

  vim.cmd("stopinsert")

  local composer_win = self.composer_win
  local transcript_win = self.transcript_win
  self.visible = false
  self.composer_win = nil
  self.transcript_win = nil

  if valid_window(composer_win) then
    pcall(vim.api.nvim_win_close, composer_win, true)
  end
  if valid_window(transcript_win) then
    pcall(vim.api.nvim_win_close, transcript_win, true)
  end

  if valid_window(self.last_editor_win) then
    pcall(vim.api.nvim_set_current_win, self.last_editor_win)
  end
end

function RailSplit:set_mode(_)
  self.shell_mode = "rail"
end

function RailSplit:mode()
  return "rail"
end

function RailSplit:is_visible()
  return self.visible
    and valid_window(self.transcript_win)
    and valid_window(self.composer_win)
end

function RailSplit:update(render_result)
  self:_ensure_transcript_buffer()

  local next_signature = render_signature(render_result)
  local previous_signature = self.last_signature
  local thread_changed = not previous_signature
    or previous_signature.thread_id ~= next_signature.thread_id
  local footer_changed = not previous_signature
    or previous_signature.footer ~= next_signature.footer
    or not vim.deep_equal(previous_signature.footer_segments, next_signature.footer_segments)
  local lines_changed = not previous_signature
    or not vim.deep_equal(previous_signature.lines, next_signature.lines)
  local blocks_changed = not previous_signature
    or not vim.deep_equal(previous_signature.blocks, next_signature.blocks)
  local turn_lines_changed = not previous_signature
    or not vim.deep_equal(previous_signature.turn_lines, next_signature.turn_lines)

  self.last_render = render_result
  self.last_signature = next_signature

  if not (thread_changed or footer_changed or lines_changed or blocks_changed or turn_lines_changed) then
    return
  end

  self.update_count = (self.update_count or 0) + 1

  if thread_changed then
    self:_update_thread_context(render_result.thread_id)
  end
  if lines_changed then
    self:_set_transcript_lines(render_result.lines)
  end
  if lines_changed or blocks_changed then
    self:_render_blocks(render_result.blocks)
  end
  if footer_changed and self:is_visible() then
    self:_refresh_titles()
  end
end

function RailSplit:set_composer_height(_)
  if valid_window(self.composer_win) then
    pcall(vim.api.nvim_win_set_height, self.composer_win, self:_composer_total_height())
  end
end

local function contains_line(block, line)
  return block.line_start and block.line_end and line >= block.line_start and line <= block.line_end
end

function RailSplit:current_block()
  if not valid_window(self.transcript_win) then
    return nil
  end

  local cursor_line = vim.api.nvim_win_get_cursor(self.transcript_win)[1]
  local previous = nil
  for _, block in ipairs(self.block_ranges or {}) do
    if contains_line(block, cursor_line) then
      return value.deep_copy(block)
    end
    if block.line_end and block.line_end < cursor_line then
      previous = block
    end
  end

  return value.deep_copy(previous)
end

function RailSplit:goto_turn(direction)
  if not valid_window(self.transcript_win) then
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(self.transcript_win)[1]
  local target = nil
  local turn_lines = self.last_render and self.last_render.turn_lines or {}

  if direction > 0 then
    for _, line in ipairs(turn_lines) do
      if line > cursor_line then
        target = line
        break
      end
    end
  else
    for index = #turn_lines, 1, -1 do
      local line = turn_lines[index]
      if line < cursor_line then
        target = line
        break
      end
    end
  end

  if target then
    vim.api.nvim_set_current_win(self.transcript_win)
    vim.api.nvim_win_set_cursor(self.transcript_win, { target, 0 })
  end
end

function RailSplit:focus_composer()
  self:show()
  return self.composer:focus()
end

function RailSplit:focus_transcript()
  self:show()
  if not valid_window(self.transcript_win) then
    return false
  end

  vim.api.nvim_set_current_win(self.transcript_win)
  vim.cmd("stopinsert")
  return true
end

function RailSplit:focus_next_pane()
  local current = vim.api.nvim_get_current_win()
  if current == self.transcript_win then
    return self:focus_composer()
  end
  return self:focus_transcript()
end

function RailSplit:inspect()
  return {
    visible = self:is_visible(),
    transcript_buf = self.transcript_bufnr,
    transcript_win = self.transcript_win,
    container_win = nil,
    composer_buf = self.composer:bufnr_value(),
    composer_win = self.composer_win,
    prompt_buf = self.composer:bufnr_value(),
    prompt_win = self.composer_win,
    blocks = value.deep_copy(self.block_ranges or {}),
    turn_lines = value.deep_copy(self.last_render and self.last_render.turn_lines or {}),
    current_block = self:current_block(),
    update_count = self.update_count or 0,
    mode = "rail",
  }
end

function M.new(opts, handlers)
  local surface = setmetatable({
    opts = opts,
    handlers = handlers,
    composer = handlers.composer,
    transcript_bufnr = nil,
    transcript_win = nil,
    composer_win = nil,
    visible = false,
    block_ranges = {},
    last_render = nil,
    last_signature = nil,
    last_line_count = 1,
    last_editor_win = nil,
    update_count = 0,
    augroup = vim.api.nvim_create_augroup("NeovimCodexChatRail", { clear = false }),
    shell_mode = "rail",
  }, RailSplit)

  surface:_ensure_highlights()
  surface:_ensure_transcript_buffer()
  return surface
end

return M
