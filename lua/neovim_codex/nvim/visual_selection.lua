local M = {}

local BLOCKWISE = "\22"

local function normalize_mode(mode)
  if mode == "v" or mode == "V" or mode == BLOCKWISE then
    return mode
  end
  return "v"
end

local function ordered_positions(start_pos, end_pos)
  local start_line = tonumber(start_pos[2]) or 0
  local start_col = tonumber(start_pos[3]) or 0
  local end_line = tonumber(end_pos[2]) or 0
  local end_col = tonumber(end_pos[3]) or 0

  if end_line < start_line or (end_line == start_line and end_col < start_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  return start_line, start_col, end_line, end_col
end

local function block_slice(line, start_col, end_col)
  local text = tostring(line or "")
  if start_col < 1 then
    start_col = 1
  end
  if end_col < start_col then
    end_col = start_col
  end
  return text:sub(start_col, end_col)
end

local function selection_result(lines, start_line, end_line, start_col, end_col)
  return {
    text = table.concat(lines, "\n"),
    range = {
      start_line = start_line,
      end_line = end_line,
      start_col = start_col,
      end_col = end_col,
    },
  }
end

local function charwise_selection(bufnr, start_line, start_col, end_line, end_col)
  local lines = vim.api.nvim_buf_get_text(bufnr, start_line - 1, start_col - 1, end_line - 1, end_col, {})
  return selection_result(lines, start_line, end_line, start_col, end_col)
end

local function linewise_selection(bufnr, start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  return selection_result(lines, start_line, end_line, 1, nil)
end

local function blockwise_selection(bufnr, start_line, start_col, end_line, end_col)
  local start_byte = math.min(start_col, end_col)
  local end_byte = math.max(start_col, end_col)
  local source_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local lines = {}

  for _, line in ipairs(source_lines) do
    lines[#lines + 1] = block_slice(line, start_byte, end_byte)
  end

  return selection_result(lines, start_line, end_line, start_byte, end_byte)
end

function M.capture(bufnr, opts)
  opts = opts or {}
  local start_pos = opts.start_pos or vim.fn.getpos("'<")
  local end_pos = opts.end_pos or vim.fn.getpos("'>")
  local start_line, start_col, end_line, end_col = ordered_positions(start_pos, end_pos)

  if start_line == 0 or end_line == 0 then
    return nil, "Visual selection is required"
  end

  local mode = normalize_mode(opts.selection_mode or vim.fn.visualmode())
  if mode == "V" then
    return linewise_selection(bufnr, start_line, end_line), nil
  end
  if mode == BLOCKWISE then
    return blockwise_selection(bufnr, start_line, start_col, end_line, end_col), nil
  end
  return charwise_selection(bufnr, start_line, start_col, end_line, end_col), nil
end

return M
