local text_utils = require("neovim_codex.core.text")
local value = require("neovim_codex.core.value")

local M = {}

local function normalize_lines(lines)
  return text_utils.split_lines(lines, { empty = { "" } })
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

function M.signature(render_result)
  local block_signatures = {}
  for _, block in ipairs(render_result.blocks or {}) do
    block_signatures[#block_signatures + 1] = block_signature(block)
  end

  return {
    thread_id = render_result.thread_id,
    footer = render_result.footer,
    footer_segments = value.deep_copy(render_result.footer_segments),
    lines = normalize_lines(render_result.lines),
    blocks = block_signatures,
  }
end

function M.diff(previous_signature, next_signature)
  return {
    thread_changed = not previous_signature
      or previous_signature.thread_id ~= next_signature.thread_id,
    footer_changed = not previous_signature
      or previous_signature.footer ~= next_signature.footer
      or not vim.deep_equal(previous_signature.footer_segments, next_signature.footer_segments),
    lines_changed = not previous_signature
      or not vim.deep_equal(previous_signature.lines, next_signature.lines),
    blocks_changed = not previous_signature
      or not vim.deep_equal(previous_signature.blocks, next_signature.blocks),
  }
end

return M
