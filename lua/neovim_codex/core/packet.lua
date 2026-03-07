local M = {}

local function present(value)
  return value ~= nil and type(value) ~= "userdata"
end

local function trim(value)
  local text = tostring(value or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local function split_lines(text)
  local value = tostring(text or "")
  if value == "" then
    return {}
  end
  return vim.split(value, "\n", { plain = true })
end

local function append_lines(target, source)
  for _, line in ipairs(source or {}) do
    target[#target + 1] = tostring(line)
  end
end

local function display_path(path)
  if not present(path) or tostring(path) == "" then
    return nil
  end

  local text = tostring(path)
  local home = os.getenv("HOME")
  if home and text:sub(1, #home) == home then
    return "~" .. text:sub(#home + 1)
  end
  return text
end

local function range_label(range)
  if type(range) ~= "table" then
    return nil
  end

  local start_line = tonumber(range.start_line)
  local end_line = tonumber(range.end_line) or start_line
  if not start_line then
    return nil
  end
  if end_line == start_line then
    return tostring(start_line)
  end
  return string.format("%d-%d", start_line, end_line)
end

local function plain_snippet(value, limit)
  if not present(value) then
    return nil
  end

  local text = tostring(value)
  text = text:gsub("`+", "")
  text = text:gsub("[%*_>#-]+", " ")
  text = text:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
  text = text:gsub("\n", " ")
  text = text:gsub("%s+", " ")
  text = trim(text)
  if text == "" then
    return nil
  end

  if #text <= limit then
    return text
  end
  return text:sub(1, math.max(1, limit - 3)) .. "..."
end

local function heading_label(fragment)
  local label = fragment.label or fragment.kind or "Fragment"
  return trim(label)
end

function M.fragment_summary(fragment)
  local kind = tostring(fragment.kind or "fragment")
  local label = heading_label(fragment)
  return string.format("[%s] %s", kind, label)
end

function M.fragment_preview(fragment)
  if fragment.kind == "path_ref" then
    return display_path(fragment.path or fragment.label) or fragment.label
  end

  if fragment.kind == "code_range" then
    local path = display_path(fragment.path) or fragment.label or "selection"
    local range = range_label(fragment.range)
    if range then
      return string.format("%s:%s", path, range)
    end
    return path
  end

  if fragment.kind == "diagnostic" then
    return plain_snippet(fragment.message or fragment.label, 88) or heading_label(fragment)
  end

  if fragment.kind == "chat_block" then
    return plain_snippet(fragment.excerpt or fragment.label, 88) or heading_label(fragment)
  end

  return plain_snippet(fragment.text or fragment.label, 88) or heading_label(fragment)
end

function M.fragment_detail_lines(fragment)
  local lines = { string.format("# %s", M.fragment_summary(fragment)) }

  if fragment.thread_id then
    lines[#lines + 1] = string.format("- Thread: `%s`", fragment.thread_id)
  end
  if fragment.turn_id then
    lines[#lines + 1] = string.format("- Turn: `%s`", fragment.turn_id)
  end
  if fragment.path then
    lines[#lines + 1] = string.format("- Path: `%s`", display_path(fragment.path) or fragment.path)
  end
  local range = range_label(fragment.range)
  if range then
    lines[#lines + 1] = string.format("- Lines: `%s`", range)
  end
  if fragment.filetype then
    lines[#lines + 1] = string.format("- Filetype: `%s`", fragment.filetype)
  end
  if fragment.kind == "diagnostic" and fragment.code then
    lines[#lines + 1] = string.format("- Code: `%s`", fragment.code)
  end
  if fragment.kind == "diagnostic" and fragment.severity then
    lines[#lines + 1] = string.format("- Severity: `%s`", fragment.severity)
  end

  local body_lines = {}
  if fragment.kind == "path_ref" then
    body_lines = { string.format("`%s`", display_path(fragment.path or fragment.label) or fragment.label or "") }
  elseif fragment.kind == "code_range" then
    local fence = fragment.filetype or "text"
    body_lines = { string.format("```%s", fence) }
    append_lines(body_lines, split_lines(fragment.text))
    body_lines[#body_lines + 1] = "```"
  elseif fragment.kind == "chat_block" then
    for _, line in ipairs(split_lines(fragment.text)) do
      body_lines[#body_lines + 1] = line == "" and ">" or "> " .. line
    end
  else
    append_lines(body_lines, split_lines(fragment.text or fragment.message or fragment.label or ""))
  end

  if #body_lines > 0 then
    lines[#lines + 1] = ""
    append_lines(lines, body_lines)
  end

  return lines
end

local function render_fragment_lines(fragment)
  local lines = { string.format("### %s", heading_label(fragment)) }

  if fragment.kind == "path_ref" then
    lines[#lines + 1] = string.format("- Path: `%s`", display_path(fragment.path or fragment.label) or fragment.label or "")
    return lines
  end

  if fragment.kind == "code_range" then
    lines[#lines + 1] = string.format("- Path: `%s`", display_path(fragment.path) or fragment.path or "")
    local range = range_label(fragment.range)
    if range then
      lines[#lines + 1] = string.format("- Lines: `%s`", range)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("```%s", fragment.filetype or "text")
    append_lines(lines, split_lines(fragment.text))
    lines[#lines + 1] = "```"
    return lines
  end

  if fragment.kind == "diagnostic" then
    lines[#lines + 1] = string.format("- Source: `%s`", fragment.source or "diagnostic")
    if fragment.code then
      lines[#lines + 1] = string.format("- Code: `%s`", fragment.code)
    end
    if fragment.path then
      lines[#lines + 1] = string.format("- Path: `%s`", display_path(fragment.path) or fragment.path)
    end
    if fragment.message then
      lines[#lines + 1] = ""
      append_lines(lines, split_lines(fragment.message))
    end
    return lines
  end

  if fragment.kind == "chat_block" then
    if fragment.thread_id then
      lines[#lines + 1] = string.format("- Thread: `%s`", fragment.thread_id)
    end
    if fragment.turn_id then
      lines[#lines + 1] = string.format("- Turn: `%s`", fragment.turn_id)
    end
    lines[#lines + 1] = ""
    for _, line in ipairs(split_lines(fragment.text)) do
      lines[#lines + 1] = line == "" and ">" or "> " .. line
    end
    return lines
  end

  lines[#lines + 1] = ""
  append_lines(lines, split_lines(fragment.text or fragment.label or ""))
  return lines
end

function M.render_packet_text(message, fragments)
  local lines = {}
  local trimmed_message = trim(message or "")

  if trimmed_message ~= "" then
    append_lines(lines, split_lines(trimmed_message))
  end

  if fragments and #fragments > 0 then
    if #lines > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = "---"
      lines[#lines + 1] = ""
    end

    lines[#lines + 1] = "## Workbench Context"

    for _, fragment in ipairs(fragments) do
      lines[#lines + 1] = ""
      append_lines(lines, render_fragment_lines(fragment))
    end
  end

  if #lines == 0 then
    lines = { "" }
  end

  return table.concat(lines, "\n")
end

function M.build_input_items(message, fragments)
  return {
    {
      type = "text",
      text = M.render_packet_text(message, fragments),
    },
  }
end

return M
