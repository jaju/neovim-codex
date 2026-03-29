local protocol = require("neovim_codex.nvim.server_requests.protocol")
local text_utils = require("neovim_codex.core.text")
local value = require("neovim_codex.core.value")

local M = {}

local append_lines = text_utils.append_lines
local display_path = text_utils.display_path
local present = value.present
local split_lines = text_utils.split_lines
local methods = protocol.methods()

local function value_or(input, fallback)
  if present(input) and tostring(input) ~= "" then
    return tostring(input)
  end
  return fallback
end

local function array_items(input)
  if type(input) == "table" then
    return input
  end
  return {}
end

local function keymap_for_choice(keymaps, shortcut)
  local mapping = {
    a = keymaps.accept,
    s = keymaps.accept_for_session,
    d = keymaps.decline,
    c = keymaps.cancel,
  }
  return mapping[shortcut]
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

local function json_fence(input)
  if not present(input) then
    return nil
  end
  local ok, encoded = pcall(vim.json.encode, input)
  if not ok then
    return nil
  end
  return fence(encoded, "json")
end

local function compact(text, limit)
  if not present(text) then
    return nil
  end
  local compacted = tostring(text):gsub("\n", " "):gsub("%s+", " ")
  compacted = vim.trim(compacted)
  if compacted == "" then
    return nil
  end
  if #compacted <= limit then
    return compacted
  end
  return compacted:sub(1, math.max(1, limit - 3)) .. "..."
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

local function request_action_line(request, keymaps)
  keymaps = keymaps or {}
  local pieces = {}
  local response_kind = protocol.response_kind(request)

  local function add(lhs, label)
    if lhs == false or lhs == nil then
      return
    end
    pieces[#pieces + 1] = string.format("[%s] %s", lhs, label)
  end

  if response_kind == "tool_input" then
    add(keymaps.respond or "<CR>", "Answer")
  elseif response_kind == "choice" then
    if protocol.allows_review(request) then
      add(keymaps.review or "o", "Review diff")
    end
    local choice_entries = protocol.choice_entries(request)
    for _, item in ipairs(choice_entries) do
      local lhs = item.shortcut and (keymap_for_choice(keymaps, item.shortcut) or item.shortcut) or nil
      add(lhs, item.label)
    end
    if #choice_entries > 0 then
      add(keymaps.respond or "<CR>", "Choose")
    end
  end

  add(keymaps.help or "g?", "Shortcuts")
  add("q", "Hide")
  return string.format("> Actions: %s", table.concat(pieces, " · "))
end

local function choice_lines(request)
  local lines = {}
  for _, item in ipairs(protocol.choice_entries(request)) do
    lines[#lines + 1] = string.format("- %s", item.label)
  end
  return lines
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
  if present(request.params.proposedExecpolicyAmendment) then
    append_section(lines, "## Proposed exec policy amendment", json_fence(request.params.proposedExecpolicyAmendment))
  end
  if present(request.params.proposedNetworkPolicyAmendments) then
    append_section(lines, "## Proposed network policy amendments", json_fence(request.params.proposedNetworkPolicyAmendments))
  end
  append_section(lines, "## Available decisions", choice_lines(request))
  return { title = "Command Approval", lines = lines }
end

local function render_file_change_request(request, keymaps)
  local lines = { "# File change approval", "", request_action_line(request, keymaps), "" }
  lines[#lines + 1] = string.format("- Thread: `%s`", value_or(request.thread_id, "-"))
  lines[#lines + 1] = string.format("- Turn: `%s`", value_or(request.turn_id, "-"))
  lines[#lines + 1] = string.format("- Item: `%s`", value_or(request.item_id, "-"))
  lines[#lines + 1] = string.format("- Request id: `%s`", value_or(request.request_id, "-"))
  if present(request.params.reason) then
    lines[#lines + 1] = string.format("- Reason: %s", request.params.reason)
  end
  if present(request.params.grantRoot) then
    lines[#lines + 1] = string.format("- Grant root: `%s`", display_path(request.params.grantRoot) or request.params.grantRoot)
  end
  append_section(lines, "## Available decisions", choice_lines(request))
  append_section(lines, "## Review", {
    string.format("- `%s` opens the studied diff review before you decide.", keymaps.review or "o"),
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

local function render_permissions_request(request, keymaps)
  local lines = { "# Permission request", "", request_action_line(request, keymaps), "" }
  lines[#lines + 1] = string.format("- Thread: `%s`", value_or(request.thread_id, "-"))
  lines[#lines + 1] = string.format("- Turn: `%s`", value_or(request.turn_id, "-"))
  lines[#lines + 1] = string.format("- Item: `%s`", value_or(request.item_id, "-"))
  if present(request.params.reason) then
    lines[#lines + 1] = string.format("- Reason: %s", request.params.reason)
  end
  append_section(lines, "## Requested permissions", json_fence(request.params.permissions))
  append_section(lines, "## Available responses", choice_lines(request))
  append_section(lines, "## Notes", {
    "- Only the granted subset is sent back to Codex.",
    "- Any omitted permissions are treated as denied.",
  })
  return { title = "Permission Request", lines = lines }
end

local function render_mcp_request(request, keymaps)
  local params = request.params or {}
  local lines = { "# MCP elicitation", "", request_action_line(request, keymaps), "" }
  lines[#lines + 1] = string.format("- Thread: `%s`", value_or(request.thread_id, "-"))
  lines[#lines + 1] = string.format("- Turn: `%s`", value_or(request.turn_id, "-"))
  lines[#lines + 1] = string.format("- Server: `%s`", value_or(params.serverName, "-"))
  lines[#lines + 1] = string.format("- Mode: `%s`", value_or(params.mode, "-"))
  if present(params.message) then
    lines[#lines + 1] = string.format("- Message: %s", params.message)
  end
  if params.mode == "url" and present(params.url) then
    lines[#lines + 1] = string.format("- URL: `%s`", params.url)
  end
  if params.mode == "form" and present(params.requestedSchema) then
    append_section(lines, "## Requested schema", json_fence(params.requestedSchema))
  end
  append_section(lines, "## Available responses", choice_lines(request))
  append_section(lines, "## Notes", {
    "- This client currently exposes decline/cancel directly for MCP elicitations.",
  })
  return { title = "MCP Elicitation", lines = lines }
end

local function render_generic_request(request, keymaps)
  local lines = { "# Pending request", "", request_action_line(request, keymaps), "" }
  lines[#lines + 1] = string.format("- Method: `%s`", value_or(request.method, "unknown"))
  lines[#lines + 1] = string.format("- Request id: `%s`", value_or(request.request_id, "-"))
  if present(request.thread_id) then
    lines[#lines + 1] = string.format("- Thread: `%s`", request.thread_id)
  end
  if present(request.turn_id) then
    lines[#lines + 1] = string.format("- Turn: `%s`", request.turn_id)
  end
  if present(request.item_id) then
    lines[#lines + 1] = string.format("- Item: `%s`", request.item_id)
  end
  append_section(lines, "## Parameters", json_fence(request.params))
  append_section(lines, "## Notes", {
    "- This request type does not have a dedicated interactive handler in neovim-codex yet.",
    "- The request viewer stays read-only until the protocol route is implemented.",
  })
  return {
    title = value_or(request.method, "Pending Request"),
    lines = lines,
  }
end

function M.decision_label(decision)
  return protocol.decision_label(decision)
end

function M.command_decisions(request)
  return protocol.command_decisions(request)
end

function M.file_change_decisions()
  return protocol.file_change_decisions()
end

function M.choice_for_shortcut(shortcut, decisions)
  local fake_request = { method = methods.command_approval, params = { availableDecisions = decisions } }
  local choice_item = protocol.choice_for_shortcut(fake_request, shortcut)
  return choice_item and choice_item.payload and choice_item.payload.decision or nil
end

function M.render_request(request, keymaps)
  if not request then
    return { title = "Pending Request", lines = { "# Pending request", "", "No request is active." } }
  end
  if request.method == methods.command_approval then
    return render_command_request(request, keymaps)
  end
  if request.method == methods.file_change_approval then
    return render_file_change_request(request, keymaps)
  end
  if request.method == methods.tool_input then
    return render_tool_request(request, keymaps)
  end
  if request.method == methods.permissions_approval then
    return render_permissions_request(request, keymaps)
  end
  if request.method == methods.mcp_elicitation then
    return render_mcp_request(request, keymaps)
  end
  return render_generic_request(request, keymaps)
end

return M
