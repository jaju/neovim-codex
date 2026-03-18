local value = require("neovim_codex.core.value")

local M = {}

local METHOD_COMMAND_APPROVAL = "item/commandExecution/requestApproval"
local METHOD_FILE_CHANGE_APPROVAL = "item/fileChange/requestApproval"
local METHOD_TOOL_INPUT = "item/tool/requestUserInput"
local METHOD_PERMISSIONS_APPROVAL = "item/permissions/requestApproval"
local METHOD_MCP_ELICITATION = "mcpServer/elicitation/request"

local function decision_kind(decision)
  if type(decision) == "string" then
    return decision
  end
  if type(decision) == "table" then
    return next(decision)
  end
  return "unknown"
end

local function decision_label(decision)
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

local function command_decisions(request)
  local decisions = request and request.params and request.params.availableDecisions
  if type(decisions) == "table" and #decisions > 0 then
    return value.deep_copy(decisions)
  end
  return { "accept", "acceptForSession", "decline", "cancel" }
end

local function file_change_decisions()
  return { "accept", "acceptForSession", "decline", "cancel" }
end

local function choice(shortcut, label, payload)
  return {
    shortcut = shortcut,
    label = label,
    payload = value.deep_copy(payload),
  }
end

local function decision_choices(decisions)
  local out = {}
  local shortcut_map = {
    accept = "a",
    acceptForSession = "s",
    decline = "d",
    cancel = "c",
  }

  for _, decision in ipairs(decisions or {}) do
    out[#out + 1] = choice(shortcut_map[decision_kind(decision)], decision_label(decision), {
      decision = decision,
    })
  end

  return out
end

local function granted_permissions_subset(request)
  local permissions = request and request.params and request.params.permissions or nil
  local out = {}

  if type(permissions) ~= "table" then
    return out
  end
  if permissions.network ~= nil then
    out.network = value.deep_copy(permissions.network)
  end
  if permissions.fileSystem ~= nil then
    out.fileSystem = value.deep_copy(permissions.fileSystem)
  end

  return out
end

local function permission_choices(request)
  local granted = granted_permissions_subset(request)
  return {
    choice("a", "Grant requested permissions for this turn", {
      permissions = granted,
      scope = "turn",
    }),
    choice("s", "Grant requested permissions for this session", {
      permissions = granted,
      scope = "session",
    }),
    choice("d", "Deny requested permissions", {
      permissions = {},
      scope = "turn",
    }),
  }
end

local function mcp_choices()
  return {
    choice("d", "Decline", {
      action = "decline",
      content = vim.NIL,
      _meta = vim.NIL,
    }),
    choice("c", "Cancel", {
      action = "cancel",
      content = vim.NIL,
      _meta = vim.NIL,
    }),
  }
end

local function route_for(request)
  local method = request and request.method or nil

  if method == METHOD_COMMAND_APPROVAL then
    return {
      key = "command_approval",
      response_kind = "choice",
      choices = function()
        return decision_choices(command_decisions(request))
      end,
    }
  end

  if method == METHOD_FILE_CHANGE_APPROVAL then
    return {
      key = "file_change_approval",
      response_kind = "choice",
      allows_review = true,
      choices = function()
        return decision_choices(file_change_decisions())
      end,
    }
  end

  if method == METHOD_TOOL_INPUT then
    return {
      key = "tool_input",
      response_kind = "tool_input",
    }
  end

  if method == METHOD_PERMISSIONS_APPROVAL then
    return {
      key = "permissions_approval",
      response_kind = "choice",
      choices = function()
        return permission_choices(request)
      end,
    }
  end

  if method == METHOD_MCP_ELICITATION then
    return {
      key = "mcp_elicitation",
      response_kind = "choice",
      choices = mcp_choices,
    }
  end

  return {
    key = "unsupported",
    response_kind = "unsupported",
  }
end

function M.route_for(request)
  return route_for(request)
end

function M.response_kind(request)
  return route_for(request).response_kind
end

function M.allows_review(request)
  return route_for(request).allows_review == true
end

function M.choice_entries(request)
  local route = route_for(request)
  if route.response_kind ~= "choice" or type(route.choices) ~= "function" then
    return {}
  end
  return route.choices()
end

function M.choice_for_shortcut(request, shortcut)
  for _, item in ipairs(M.choice_entries(request)) do
    if item.shortcut == shortcut then
      return value.deep_copy(item)
    end
  end
  return nil
end

function M.command_decisions(request)
  return command_decisions(request)
end

function M.file_change_decisions()
  return file_change_decisions()
end

function M.decision_kind(decision)
  return decision_kind(decision)
end

function M.decision_label(decision)
  return decision_label(decision)
end

function M.methods()
  return {
    command_approval = METHOD_COMMAND_APPROVAL,
    file_change_approval = METHOD_FILE_CHANGE_APPROVAL,
    tool_input = METHOD_TOOL_INPUT,
    permissions_approval = METHOD_PERMISSIONS_APPROVAL,
    mcp_elicitation = METHOD_MCP_ELICITATION,
  }
end

return M
