local text_utils = require("neovim_codex.core.text")
local value = require("neovim_codex.core.value")

local M = {}

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

local function define_default_highlight(name, target)
  vim.api.nvim_set_hl(0, name, {
    default = true,
    link = target,
  })
end

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function normalize_lines(lines)
  return text_utils.split_lines(lines, { empty = { "" } })
end

local function common_window_tail(winid, previous_count)
  if not valid_window(winid) then
    return false
  end

  local current = vim.api.nvim_get_current_win()
  if current ~= winid then
    return true
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  return cursor[1] >= math.max(1, (previous_count or 1) - 1)
end

local function scroll_tail_into_view(winid, line_count)
  if not valid_window(winid) then
    return
  end

  vim.api.nvim_win_set_cursor(winid, { math.max(1, line_count), 0 })
  pcall(vim.api.nvim_win_call, winid, function()
    vim.cmd("normal! zb")
  end)
end

function M.ensure_default_highlights()
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
  define_default_highlight("NeovimCodexChatFooterRunning", "DiffAdded")
  define_default_highlight("NeovimCodexChatFooterWaiting", "WarningMsg")
  define_default_highlight("NeovimCodexChatFooterIdle", "Comment")
  define_default_highlight("NeovimCodexChatFooterError", "DiagnosticError")
end

function M.patch_lines(bufnr, winid, lines, previous_line_count)
  if not valid_buffer(bufnr) then
    return 0
  end

  local normalized = normalize_lines(lines or { "" })
  if #normalized == 0 then
    normalized = { "" }
  end

  local existing = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local start_index = 1
  local limit = math.min(#existing, #normalized)
  while start_index <= limit and existing[start_index] == normalized[start_index] do
    start_index = start_index + 1
  end

  local old_tail = #existing
  local new_tail = #normalized
  while old_tail >= start_index and new_tail >= start_index and existing[old_tail] == normalized[new_tail] do
    old_tail = old_tail - 1
    new_tail = new_tail - 1
  end

  local cursor_at_end = common_window_tail(winid, previous_line_count)

  if start_index <= old_tail or start_index <= new_tail then
    local replacement = {}
    if start_index <= new_tail then
      replacement = vim.list_slice(normalized, start_index, new_tail)
    end

    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, start_index - 1, old_tail, false, replacement)
    vim.bo[bufnr].modifiable = false
  end

  if cursor_at_end and valid_window(winid) then
    scroll_tail_into_view(winid, #normalized)
  end

  return #normalized
end

function M.render_blocks(bufnr, namespace, blocks)
  local rendered_blocks = value.deep_copy(blocks or {})
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  for _, block in ipairs(rendered_blocks) do
    if block.line_start and block.line_end and block.line_end >= block.line_start then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, block.line_start - 1, 0, {
        end_row = block.line_end,
        hl_mode = "combine",
      })
    end

    local highlight = HEADER_HIGHLIGHTS[block.surface] or HEADER_HIGHLIGHTS[block.kind]
    if highlight and block.header_line_start and block.header_line_end then
      for line = block.header_line_start, block.header_line_end do
        vim.api.nvim_buf_add_highlight(bufnr, namespace, highlight, line - 1, 0, -1)
      end
    end
  end

  return rendered_blocks
end

return M
