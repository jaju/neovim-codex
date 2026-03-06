local M = {}

local function append_lines(target, source)
  for _, line in ipairs(source or {}) do
    target[#target + 1] = tostring(line)
  end
end

function M.render(document)
  local lines = {}
  local blocks = {}
  local turn_lines = {}

  for index, block in ipairs(document.blocks or {}) do
    local start_line = #lines + 1
    append_lines(lines, block.lines)
    local end_line = #lines

    blocks[#blocks + 1] = {
      id = block.id,
      kind = block.kind,
      turn_id = block.turn_id,
      item_id = block.item_id,
      collapsed_by_default = block.collapsed_by_default == true,
      line_start = start_line,
      line_end = end_line,
    }

    if block.kind == "turn_boundary" then
      turn_lines[#turn_lines + 1] = start_line
    end

    if index < #(document.blocks or {}) then
      lines[#lines + 1] = ""
    end
  end

  if #lines == 0 then
    lines = { "" }
  end

  return {
    lines = lines,
    blocks = blocks,
    turn_lines = turn_lines,
    footer = document.footer,
    thread_id = document.thread_id,
  }
end

return M
