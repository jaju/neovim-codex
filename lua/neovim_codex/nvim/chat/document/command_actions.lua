local shared = require("neovim_codex.nvim.chat.document.shared")

local M = {}

local CONTEXT_PATTERNS = {
  ".codex/skills",
  "agents.md",
  ".agent-kit",
  "docs/knowledge",
  "prompt-control",
  "topics.agent.tsv",
}

local function lower_text(value)
  return string.lower(shared.value_or(value, ""))
end

local function matches_context_target(value)
  local text = lower_text(value)
  if text == "" then
    return false
  end

  for _, pattern in ipairs(CONTEXT_PATTERNS) do
    if text:find(pattern, 1, true) then
      return true
    end
  end

  return false
end

local function action_type(action)
  return shared.value_or(action and action.type, "unknown")
end

local function describe_action(action)
  local current_type = action_type(action)

  if current_type == "read" then
    local path = shared.display_path(action.path)
    if path then
      return string.format("Read %s", shared.compact_inline_code(path) or path)
    end
    return string.format("Read %s", shared.compact_inline_code(action.name or "file") or "file")
  end

  if current_type == "listFiles" then
    local path = shared.display_path(action.path) or "workspace"
    return string.format("Listed files in %s", shared.compact_inline_code(path) or path)
  end

  if current_type == "search" then
    local path = shared.display_path(action.path) or "workspace"
    local query = shared.plain_snippet(action.query, 40)
    if query then
      return string.format("Searched %s for %s", shared.compact_inline_code(path) or path, shared.compact_inline_code(query) or query)
    end
    return string.format("Searched %s", shared.compact_inline_code(path) or path)
  end

  return nil
end

local function targets_context(action)
  local current_type = action_type(action)

  if current_type == "read" then
    return matches_context_target(action.path) or matches_context_target(action.name)
  end

  if current_type == "listFiles" then
    return matches_context_target(action.path)
  end

  if current_type == "search" then
    return matches_context_target(action.path) or matches_context_target(action.query)
  end

  return false
end

function M.summarize(actions)
  local summaries = {}
  local known_actions = 0
  local unknown_actions = 0
  local context_actions = 0

  for _, action in ipairs(actions or {}) do
    local description = describe_action(action)
    if description then
      summaries[#summaries + 1] = description
      known_actions = known_actions + 1
    else
      unknown_actions = unknown_actions + 1
    end

    if targets_context(action) then
      context_actions = context_actions + 1
    end
  end

  return {
    summaries = summaries,
    known_only = known_actions > 0 and unknown_actions == 0,
    has_context = context_actions > 0,
    total = known_actions + unknown_actions,
  }
end

return M
