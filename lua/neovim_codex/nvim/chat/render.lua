local M = {}

local function append_lines(target, source)
  for _, line in ipairs(source or {}) do
    target[#target + 1] = tostring(line)
  end
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

function M.render(document)
  local lines = {}
  local blocks = {}
  local turn_lines = {}

  for index, block in ipairs(document.blocks or {}) do
    local start_line = #lines + 1
    append_lines(lines, block.lines)
    local end_line = #lines
    local header_lines = math.max(1, tonumber(block.header_lines) or 1)

    blocks[#blocks + 1] = {
      id = block.id,
      kind = block.kind,
      surface = block.surface or block.kind,
      turn_id = block.turn_id,
      item_id = block.item_id,
      collapsed_by_default = block.collapsed_by_default == true,
      line_start = start_line,
      line_end = end_line,
      header_line_start = start_line,
      header_line_end = math.min(end_line, start_line + header_lines - 1),
      protocol = clone_value(block.protocol),
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
    footer_segments = clone_value(document.footer_segments),
    thread_id = document.thread_id,
  }
end

return M
