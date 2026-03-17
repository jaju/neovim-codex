local text_utils = require("neovim_codex.core.text")
local value = require("neovim_codex.core.value")

local M = {}

local append_lines = text_utils.append_lines
local display_path = text_utils.display_path
local present = value.present
local split_lines = text_utils.split_lines

local function value_or(value, fallback)
  if present(value) and tostring(value) ~= "" then
    return tostring(value)
  end
  return fallback
end

local function array_items(value)
  if type(value) == "table" then
    return value
  end
  return {}
end

local function append_section(lines, heading, body)
  local body_lines = type(body) == "table" and body or split_lines(body)
  if not body_lines or #body_lines == 0 then
    return
  end
  if #lines > 0 then
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = heading
  lines[#lines + 1] = ""
  append_lines(lines, body_lines)
end

local function fence(text, lang)
  local out = { string.format("```%s", lang or "") }
  append_lines(out, type(text) == "table" and text or split_lines(text))
  out[#out + 1] = "```"
  return out
end

local function json_fence(value)
  if not present(value) then
    return nil
  end
  local ok, encoded = pcall(vim.json.encode, value)
  if not ok then
    return nil
  end
  return fence(encoded, "json")
end

local function compact(text, limit)
  if not present(text) then
    return nil
  end
  local value = tostring(text):gsub("\n", " "):gsub("%s+", " ")
  value = vim.trim(value)
  if value == "" then
    return nil
  end
  if #value <= limit then
    return value
  end
  return value:sub(1, math.max(1, limit - 3)) .. "..."
end

local function action_summary(action)
  local action_type = value_or(action and action.type, "unknown")
  if action_type == "read" then
    return string.format("- Read `%s`", display_path(action.path) or value_or(action.name, "file"))
  end
  if action_type == "listFiles" then
    return string.format("- Listed files in `%s`", display_path(action.path) or "workspace")
  end
  if action_type == "search" then
    local query = compact(action.query, 48)
    if query then
      return string.format("- Searched `%s` for `%s`", display_path(action.path) or "workspace", query)
    end
    return string.format("- Searched `%s`", display_path(action.path) or "workspace")
  end
  return string.format("- Action `%s`", action_type)
end

local function decision_kind(decision)
  if type(decision) == "string" then
    return decision
  end
  if type(decision) == "table" then
    return next(decision)
  end
  return "unknown"
end

function M.decision_label(decision)
  local kind = decision_kind(decision)
  if kind == "accept" then
    return "Approve once"
  end
  if kind == "acceptForSession" then
    return "Approve for session"
  end
  if kind == "decline" then
    return "Decline"
  end
  if kind == "cancel" then
    return "Cancel"
  end
  if kind == "acceptWithExecpolicyAmendment" then
    return "Approve and persist similar commands"
  end
  if kind == "applyNetworkPolicyAmendment" then
    return "Apply proposed network policy"
  end
  return kind
end

function M.command_decisions(request)
  local decisions = request.params.availableDecisions
  if type(decisions) == "table" and #decisions > 0 then
    return value.deep_copy(decisions)
  end
  return { "accept", "acceptForSession", "decline", "cancel" }
end

function M.file_change_decisions()
  return { "accept", "acceptForSession", "decline", "cancel" }
end

function M.choice_for_shortcut(shortcut, decisions)
  for _, decision in ipairs(decisions or {}) do
    local kind = decision_kind(decision)
    if shortcut == "a" and kind == "accept" then
      return value.deep_copy(decision)
    end
    if shortcut == "s" and kind == "acceptForSession" then
      return value.deep_copy(decision)
    end
    if shortcut == "d" and kind == "decline" then
      return value.deep_copy(decision)
    end
    if shortcut == "c" and kind == "cancel" then
      return value.deep_copy(decision)
    end
  end
  return nil
end

local function request_action_line(request, keymaps)
  keymaps = keymaps or {}
  local pieces = {}

  local function add(lhs, label)
    if lhs == false or lhs == nil then
      return
    end
    pieces[#pieces + 1] = string.format("[%s] %s", lhs, label)
  end

  if request.method == "item/tool/requestUserInput" then
    add(keymaps.respond or "<CR>", "Answer")
  else
    local decisions = request.method == "item/commandExecution/requestApproval" and M.command_decisions(request) or M.file_change_decisions()
    if M.choice_for_shortcut("a", decisions) then
      add(keymaps.accept or "a", "Approve once")
    end
    if M.choice_for_shortcut("s", decisions) then
      add(keymaps.accept_for_session or "s", "Approve session")
    end
    if M.choice_for_shortcut("d", decisions) then
      add(keymaps.decline or "d", "Decline")
    end
    if M.choice_for_shortcut("c", decisions) then
      add(keymaps.cancel or "c", "Cancel")
    end
    add(keymaps.respond or "<CR>", "Choose")
  end

  add(keymaps.help or "g?", "Shortcuts")
  add("q", "Hide")
  return string.format("> Actions: %s", table.concat(pieces, " · "))
end

local function render_command_request(request, keymaps)
  local lines = { "# Command approval", "", request_action_line(request, keymaps), "" }
  lines[#lines + 1] = string.format("- Thread: `%s`", value_or(request.thread_id, "-"))
  lines[#lines + 1] = string.format("- Turn: `%s`", value_or(request.turn_id, "-"))
  lines[#lines + 1] = string.format("- Item: `%s`", value_or(request.item_id, "-"))
  if present(request.params.reason) then
    lines[#lines + 1] = string.format("- Reason: %s", request.params.reason)
  end
  if present(request.params.cwd) then
    lines[#lines + 1] = string.format("- Working directory: `%s`", display_path(request.params.cwd) or request.params.cwd)
  end
  if present(request.params.networkApprovalContext) then
    append_section(lines, "## Network approval context", json_fence(request.params.networkApprovalContext))
  end
  local command_actions = array_items(request.params.commandActions)
  if #command_actions > 0 then
    local action_lines = {}
    for _, action in ipairs(command_actions) do
      action_lines[#action_lines + 1] = action_summary(action)
    end
    append_section(lines, "## Parsed actions", action_lines)
  end
  if present(request.params.command) then
    append_section(lines, "## Command", fence(request.params.command, "sh"))
  end
  if present(request.params.additionalPermissions) then
    append_section(lines, "## Additional permissions", json_fence(request.params.additionalPermissions))
  end
  if present(request.params.skillMetadata) then
    append_section(lines, "## Skill metadata", json_fence(request.params.skillMetadata))
  end
  if present(request.params.proposedExecpolicyAmendment) then
    append_section(lines, "## Proposed exec policy amendment", json_fence(request.params.proposedExecpolicyAmendment))
  end
  if present(request.params.proposedNetworkPolicyAmendments) then
    append_section(lines, "## Proposed network policy amendments", json_fence(request.params.proposedNetworkPolicyAmendments))
  end
  local decision_lines = {}
  for _, decision in ipairs(M.command_decisions(request)) do
    decision_lines[#decision_lines + 1] = string.format("- %s", M.decision_label(decision))
  end
  append_section(lines, "## Available decisions", decision_lines)
  return { title = "Command Approval", lines = lines }
end

local function render_file_change_request(request, keymaps)
  local lines = { "# File change approval", "", request_action_line(request, keymaps), "" }
  lines[#lines + 1] = string.format("- Thread: `%s`", value_or(request.thread_id, "-"))
  lines[#lines + 1] = string.format("- Turn: `%s`", value_or(request.turn_id, "-"))
  lines[#lines + 1] = string.format("- Item: `%s`", value_or(request.item_id, "-"))
  if present(request.params.reason) then
    lines[#lines + 1] = string.format("- Reason: %s", request.params.reason)
  end
  if present(request.params.grantRoot) then
    lines[#lines + 1] = string.format("- Grant root: `%s`", display_path(request.params.grantRoot) or request.params.grantRoot)
  end
  append_section(lines, "## Available decisions", {
    "- Approve once",
    "- Approve for session",
    "- Decline",
    "- Cancel",
  })
  return { title = "File Change Approval", lines = lines }
end

local function render_tool_request(request, keymaps)
  local lines = { "# Tool question", "", request_action_line(request, keymaps), "" }
  lines[#lines + 1] = string.format("- Thread: `%s`", value_or(request.thread_id, "-"))
  lines[#lines + 1] = string.format("- Turn: `%s`", value_or(request.turn_id, "-"))
  lines[#lines + 1] = string.format("- Item: `%s`", value_or(request.item_id, "-"))

  for index, question in ipairs(array_items(request.params.questions)) do
    local header = value_or(question.header, string.format("Question %d", index))
    local question_lines = {
      string.format("- Prompt: %s", value_or(question.question, "-")),
      string.format("- Accepts custom answer: %s", question.isOther and "yes" or "no"),
      string.format("- Secret input: %s", question.isSecret and "yes" or "no"),
    }
    for _, option in ipairs(array_items(question.options)) do
      question_lines[#question_lines + 1] = string.format("- Option: %s — %s", option.label, value_or(option.description, ""))
    end
    append_section(lines, string.format("## %s", header), question_lines)
  end

  return { title = "Tool Input Request", lines = lines }
end

function M.render_request(request, keymaps)
  if not request then
    return { title = "Pending Request", lines = { "# Pending request", "", "No request is active." } }
  end
  if request.method == "item/commandExecution/requestApproval" then
    return render_command_request(request, keymaps)
  end
  if request.method == "item/fileChange/requestApproval" then
    return render_file_change_request(request, keymaps)
  end
  if request.method == "item/tool/requestUserInput" then
    return render_tool_request(request, keymaps)
  end
  return {
    title = value_or(request.method, "Pending Request"),
    lines = {
      "# Pending request",
      "",
      string.format("- Method: `%s`", value_or(request.method, "unknown")),
      string.format("- Request id: `%s`", value_or(request.request_id, "-")),
    },
  }
end

return M
