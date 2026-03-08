local M = {}

local function present(value)
  return value ~= nil and value ~= vim.NIL
end

function M.short_id(thread_id)
  local text = tostring(thread_id or "")
  if #text <= 8 then
    return text
  end
  return text:sub(1, 8)
end

function M.title(thread, opts)
  opts = opts or {}
  local max_length = tonumber(opts.max_length) or 72
  local fallback = opts.fallback or "(untitled thread)"

  local title = nil
  if type(thread) == "table" and present(thread.name) and thread.name ~= "" then
    title = thread.name
  elseif type(thread) == "table" and present(thread.preview) and thread.preview ~= "" then
    title = thread.preview
  else
    title = fallback
  end

  title = tostring(title):gsub("\n", " "):gsub("%s+", " ")
  if #title > max_length then
    title = title:sub(1, max_length - 3) .. "..."
  end
  return title
end

function M.picker_label(thread, active_id)
  local marker = thread.id == active_id and "●" or "○"
  local status = thread.status and thread.status.type or "unknown"
  return string.format("%s %s  [%s]  %s", marker, M.short_id(thread.id), status, M.title(thread))
end

return M
