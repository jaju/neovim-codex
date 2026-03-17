local text_utils = require("neovim_codex.core.text")
local value = require("neovim_codex.core.value")

local M = {}

M.display_path = text_utils.display_path
M.present = value.present
M.split_lines = text_utils.split_lines

function M.value_or(candidate, fallback)
  if M.present(candidate) and candidate ~= "" then
    return tostring(candidate)
  end
  return fallback
end

function M.push_text(lines, text)
  for _, line in ipairs(M.split_lines(text)) do
    lines[#lines + 1] = line
  end
end

function M.add_block(blocks, block)
  if block then
    blocks[#blocks + 1] = block
  end
end

function M.duration_label(duration_ms)
  local numeric = tonumber(duration_ms)
  if not numeric then
    return nil
  end
  if numeric < 1000 then
    return string.format("%d ms", numeric)
  end
  return string.format("%.2f s", numeric / 1000)
end

function M.trim_text(text, limit)
  if not M.present(text) then
    return nil
  end

  local rendered = tostring(text)
  if #rendered <= limit then
    return rendered
  end

  return rendered:sub(1, math.max(1, limit - 3)) .. "..."
end

function M.compact_inline_code(text)
  local rendered = M.trim_text(text, 64)
  if not rendered then
    return nil
  end
  return string.format("`%s`", rendered)
end

function M.plain_snippet(text, limit)
  if not M.present(text) then
    return nil
  end

  local rendered = tostring(text)
  rendered = rendered:gsub("`+", "")
  rendered = rendered:gsub("[%*_>#-]+", " ")
  rendered = rendered:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
  rendered = rendered:gsub("\n", " ")
  rendered = rendered:gsub("%s+", " ")
  rendered = vim.trim(rendered)
  if rendered == "" then
    return nil
  end

  return M.trim_text(rendered, limit)
end

function M.markdown_heading(level, title, opts)
  local foldable = opts and opts.foldable == true and " {.foldable}" or ""
  return string.format("%s %s%s", string.rep("#", math.max(1, level or 1)), title, foldable)
end

function M.preview_lines(text, max_lines)
  local lines = M.split_lines(text)
  local limit = math.max(1, tonumber(max_lines) or 8)
  if #lines <= limit then
    return lines
  end

  local preview = {}
  for index = 1, limit do
    preview[#preview + 1] = lines[index]
  end
  preview[#preview + 1] = "..."
  return preview
end

function M.fenced_block(language, text, max_lines)
  local body = type(text) == "table" and value.deep_copy(text) or M.preview_lines(text, max_lines)
  if #body == 0 then
    return {}
  end

  local lines = { string.format("```%s", language or "") }
  for _, line in ipairs(body) do
    lines[#lines + 1] = tostring(line)
  end
  lines[#lines + 1] = "```"
  return lines
end

function M.extend_lines(lines, extra)
  for _, line in ipairs(extra or {}) do
    lines[#lines + 1] = line
  end
  return lines
end

function M.join_parts(parts, separator)
  local values = {}
  for _, part in ipairs(parts or {}) do
    if M.present(part) and tostring(part) ~= "" then
      values[#values + 1] = tostring(part)
    end
  end
  return table.concat(values, separator or " · ")
end

function M.protocol_payload(item)
  return {
    item_type = item.type,
    item = value.deep_copy(item),
  }
end

function M.new_block(spec)
  return {
    kind = spec.kind,
    surface = spec.surface or spec.kind,
    collapsed_by_default = spec.collapsed_by_default == true,
    header_lines = spec.header_lines or 1,
    lines = spec.lines or {},
    protocol = spec.protocol,
  }
end

function M.user_content_lines(content)
  local lines = {}

  if not content or #content == 0 then
    return { "_Empty message._" }
  end

  for _, item in ipairs(content) do
    if item.type == "text" then
      M.push_text(lines, item.text)
    elseif item.type == "skill" then
      lines[#lines + 1] = string.format("- Skill `%s` (`%s`)", M.value_or(item.name, "skill"), M.display_path(item.path) or "")
    elseif item.type == "mention" then
      lines[#lines + 1] = string.format("- Mention `%s` (`%s`)", M.value_or(item.name, "mention"), M.value_or(item.path, ""))
    elseif item.type == "image" then
      lines[#lines + 1] = string.format("- Image `%s`", M.value_or(item.url, ""))
    elseif item.type == "localImage" then
      lines[#lines + 1] = string.format("- Local image `%s`", M.display_path(item.path) or "")
    else
      lines[#lines + 1] = string.format("- %s", M.value_or(item.type, "unknown item"))
    end
  end

  if #lines == 0 then
    return { "_Empty message._" }
  end

  return lines
end

function M.user_message_text(content)
  local parts = {}
  for _, item in ipairs(content or {}) do
    if item.type == "text" and M.present(item.text) then
      parts[#parts + 1] = item.text
    end
  end
  return table.concat(parts, "\n")
end

return M
