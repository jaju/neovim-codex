local M = {}

local HANDLE_PATTERN = "%[%[([%w_%-]+)%]%]"

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

local function location_label(fragment)
  local path = display_path(fragment.path or fragment.label)
  local range = range_label(fragment.range)
  if path and range then
    return string.format("%s:%s", path, range)
  end
  return path or range
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

local function join_handles(handles)
  if not handles or #handles == 0 then
    return nil
  end
  local out = {}
  for _, handle in ipairs(handles) do
    out[#out + 1] = string.format("[[%s]]", handle)
  end
  return table.concat(out, ", ")
end

function M.fragment_handle(fragment)
  if type(fragment) ~= "table" then
    return nil
  end

  local handle = trim(fragment.handle or "")
  if handle == "" then
    return nil
  end
  return handle
end

function M.handle_token(fragment_or_handle)
  local handle = nil
  if type(fragment_or_handle) == "table" then
    handle = M.fragment_handle(fragment_or_handle)
  else
    handle = trim(fragment_or_handle or "")
  end

  if not handle or handle == "" then
    return nil
  end
  return string.format("[[%s]]", handle)
end

function M.fragment_summary(fragment)
  local kind = tostring(fragment.kind or "fragment")
  local label = heading_label(fragment)
  local handle = M.fragment_handle(fragment)
  if handle then
    return string.format("[%s] [%s] %s", handle, kind, label)
  end
  return string.format("[%s] %s", kind, label)
end

function M.fragment_preview(fragment)
  if fragment.kind == "path_ref" then
    return display_path(fragment.path or fragment.label) or fragment.label
  end

  if fragment.kind == "code_range" then
    local text_preview = plain_snippet(fragment.text, 88)
    if text_preview then
      return text_preview
    end
    return location_label(fragment) or display_path(fragment.path) or fragment.label or "selection"
  end

  if fragment.kind == "diagnostic" then
    local summary = plain_snippet(fragment.message or fragment.label, 88) or heading_label(fragment)
    if present(fragment.code) then
      return string.format("%s · %s", tostring(fragment.code), summary)
    end
    return summary
  end

  return plain_snippet(fragment.text or fragment.label, 88) or heading_label(fragment)
end

local function render_fragment_expansion(fragment)
  local lines = {}

  if fragment.kind == "path_ref" then
    lines[#lines + 1] = string.format("The relevant file path is `%s`.", display_path(fragment.path or fragment.label) or fragment.label or "")
    return lines
  end

  if fragment.kind == "code_range" then
    local location = location_label(fragment) or display_path(fragment.path) or fragment.label or "snippet"
    lines[#lines + 1] = string.format("The relevant code snippet from `%s` is:", location)
    lines[#lines + 1] = string.format("```%s", fragment.filetype or "text")
    append_lines(lines, split_lines(fragment.text))
    lines[#lines + 1] = "```"
    return lines
  end

  if fragment.kind == "diagnostic" then
    local location = location_label(fragment)
    if location then
      lines[#lines + 1] = string.format("The relevant diagnostic from `%s` is:", location)
    else
      lines[#lines + 1] = "The relevant diagnostic is:"
    end
    if present(fragment.source) then
      lines[#lines + 1] = string.format("- Source: `%s`", tostring(fragment.source))
    end
    if present(fragment.code) then
      lines[#lines + 1] = string.format("- Code: `%s`", tostring(fragment.code))
    end
    if present(fragment.severity) then
      lines[#lines + 1] = string.format("- Severity: `%s`", tostring(fragment.severity))
    end
    if present(fragment.message) then
      lines[#lines + 1] = string.format("- Message: %s", tostring(fragment.message))
    end
    return lines
  end

  append_lines(lines, split_lines(fragment.text or fragment.label or ""))
  return lines
end

function M.fragment_detail_lines(fragment)
  local lines = { string.format("# %s", M.fragment_summary(fragment)) }

  local handle = M.fragment_handle(fragment)
  if handle then
    lines[#lines + 1] = string.format("- Handle: `%s`", M.handle_token(handle))
  end
  lines[#lines + 1] = string.format("- State: `%s`", fragment.parked and "parked" or "active")
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

  local body_lines = render_fragment_expansion(fragment)
  if #body_lines > 0 then
    lines[#lines + 1] = ""
    append_lines(lines, body_lines)
  end

  return lines
end

function M.analyze_packet(template_text, fragments)
  local template = tostring(template_text or "")
  local active_by_handle = {}
  local parked_by_handle = {}
  local active_handles = {}
  local parked_handles = {}
  local referenced_handles = {}
  local referenced_seen = {}
  local used_counts = {}
  local missing_handles = {}
  local parked_reference_handles = {}
  local unreferenced_handles = {}

  for _, fragment in ipairs(fragments or {}) do
    local handle = M.fragment_handle(fragment)
    if handle then
      if fragment.parked then
        parked_by_handle[handle] = fragment
        parked_handles[#parked_handles + 1] = handle
      else
        active_by_handle[handle] = fragment
        active_handles[#active_handles + 1] = handle
      end
    end
  end

  local compiled_text = template:gsub(HANDLE_PATTERN, function(handle)
    local fragment = active_by_handle[handle]
    if fragment then
      used_counts[handle] = (used_counts[handle] or 0) + 1
      if not referenced_seen[handle] then
        referenced_seen[handle] = true
        referenced_handles[#referenced_handles + 1] = handle
      end
      return table.concat(render_fragment_expansion(fragment), "\n")
    end

    if parked_by_handle[handle] then
      parked_reference_handles[#parked_reference_handles + 1] = handle
      return string.format("[[%s]]", handle)
    end

    missing_handles[#missing_handles + 1] = handle
    return string.format("[[%s]]", handle)
  end)

  for _, handle in ipairs(active_handles) do
    if not referenced_seen[handle] then
      unreferenced_handles[#unreferenced_handles + 1] = handle
    end
  end

  return {
    compiled_text = compiled_text,
    active_handles = active_handles,
    parked_handles = parked_handles,
    referenced_handles = referenced_handles,
    missing_handles = missing_handles,
    parked_reference_handles = parked_reference_handles,
    unreferenced_handles = unreferenced_handles,
    used_counts = used_counts,
    valid = #missing_handles == 0 and #parked_reference_handles == 0 and #unreferenced_handles == 0,
  }
end

local function validation_error(analysis)
  if #analysis.missing_handles > 0 then
    return string.format(
      "Unknown fragment handle%s: %s",
      #analysis.missing_handles == 1 and "" or "s",
      table.concat(analysis.missing_handles, ", ")
    )
  end

  if #analysis.parked_reference_handles > 0 then
    return string.format(
      "Unpark referenced fragment%s before sending: %s",
      #analysis.parked_reference_handles == 1 and "" or "s",
      table.concat(analysis.parked_reference_handles, ", ")
    )
  end

  if #analysis.unreferenced_handles > 0 then
    return string.format(
      "Reference every active fragment before sending, or park the unused ones: %s",
      table.concat(analysis.unreferenced_handles, ", ")
    )
  end

  return nil
end

function M.preview_lines(template_text, fragments)
  local analysis = M.analyze_packet(template_text, fragments)
  local lines = {
    "# Packet preview",
    "",
    string.format("- Active fragments: %d", #analysis.active_handles),
    string.format("- Parked fragments: %d", #analysis.parked_handles),
  }

  local active_labels = join_handles(analysis.active_handles)
  if active_labels then
    lines[#lines + 1] = string.format("- Active handles: %s", active_labels)
  end
  local parked_labels = join_handles(analysis.parked_handles)
  if parked_labels then
    lines[#lines + 1] = string.format("- Parked handles: %s", parked_labels)
  end

  local error_message = validation_error(analysis)
  if error_message then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Validation"
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("- %s", error_message)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Compiled packet"
  lines[#lines + 1] = ""
  if trim(analysis.compiled_text) == "" then
    lines[#lines + 1] = "_Packet is empty._"
  else
    append_lines(lines, split_lines(analysis.compiled_text))
  end

  return lines, analysis, error_message
end

function M.build_input_items(template_text, fragments)
  local analysis = M.analyze_packet(template_text, fragments)
  local err = validation_error(analysis)
  if err then
    return nil, nil, err
  end

  return {
    {
      type = "text",
      text = analysis.compiled_text,
    },
  }, analysis, nil
end

return M
