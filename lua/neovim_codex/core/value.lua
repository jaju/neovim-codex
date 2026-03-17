local M = {}

local vim_nil = rawget(_G, "vim") and vim.NIL or nil

function M.present(value)
  return value ~= nil and value ~= vim_nil and type(value) ~= "userdata"
end

function M.deep_copy(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for key, item in pairs(value) do
    out[key] = M.deep_copy(item)
  end
  return out
end

function M.shallow_copy(value)
  local out = {}
  for key, item in pairs(value or {}) do
    out[key] = item
  end
  return out
end

function M.copy_array(values)
  local out = {}
  for index, item in ipairs(values or {}) do
    out[index] = item
  end
  return out
end

return M
