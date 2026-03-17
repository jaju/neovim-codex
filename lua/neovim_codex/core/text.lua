local value = require("neovim_codex.core.value")

local M = {}

local function clone_empty(opts)
  if opts and type(opts.empty) == "table" then
    return value.copy_array(opts.empty)
  end
  return {}
end

local function split_scalar(input, opts)
  if not value.present(input) then
    return clone_empty(opts)
  end

  local text = tostring(input)
  if text == "" then
    if opts and opts.preserve_empty then
      return { "" }
    end
    return clone_empty(opts)
  end

  return vim.split(text, "\n", { plain = true })
end

function M.split_lines(input, opts)
  if type(input) ~= "table" then
    return split_scalar(input, opts)
  end

  local lines = {}
  for _, item in ipairs(input) do
    for _, line in ipairs(split_scalar(item, { preserve_empty = true })) do
      lines[#lines + 1] = line
    end
  end

  if #lines == 0 then
    return clone_empty(opts)
  end

  return lines
end

function M.append_lines(target, source)
  for _, line in ipairs(M.split_lines(source)) do
    target[#target + 1] = tostring(line)
  end
end

function M.display_path(path)
  if not value.present(path) then
    return nil
  end

  local text = tostring(path)
  if text == "" then
    return nil
  end

  local home = (rawget(_G, "vim") and vim.env and vim.env.HOME) or os.getenv("HOME")
  if home and text:sub(1, #home) == home then
    return "~" .. text:sub(#home + 1)
  end
  return text
end

return M
