local M = {}

local function dedupe(items)
  local seen = {}
  local out = {}
  for _, item in ipairs(items) do
    if item and item ~= false and not seen[item] then
      seen[item] = true
      out[#out + 1] = item
    end
  end
  return out
end

function M.keys(config, local_key)
  local global_key = (((config or {}).keymaps or {}).surface_help)
  return dedupe({ local_key, global_key })
end

function M.label(config, local_key)
  return table.concat(M.keys(config, local_key), ' / ')
end

function M.bind(map_if, config, local_key, mode, rhs, opts)
  for _, lhs in ipairs(M.keys(config, local_key)) do
    map_if(lhs, mode, rhs, opts)
  end
end

return M
