local text_utils = require("neovim_codex.core.text")
local value = require("neovim_codex.core.value")

local M = {}

local display_path = text_utils.display_path
local present = value.present

local CONTEXT_PATTERNS = {
  ".codex/skills",
  "agents.md",
  ".agent-kit",
  "docs/knowledge",
  "prompt-control",
  "topics.agent.tsv",
}

local function value_or(candidate, fallback)
  if present(candidate) and candidate ~= "" then
    return tostring(candidate)
  end
  return fallback
end

local function trim_text(text, limit)
  if not present(text) then
    return nil
  end

  local rendered = tostring(text)
  if #rendered <= limit then
    return rendered
  end

  return rendered:sub(1, math.max(1, limit - 3)) .. "..."
end

local function compact_inline_code(text)
  local rendered = trim_text(text, 64)
  if not rendered then
    return nil
  end
  return string.format("`%s`", rendered)
end

local function plain_snippet(text, limit)
  if not present(text) then
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

  return trim_text(rendered, limit)
end

local function lower_text(candidate)
  return string.lower(value_or(candidate, ""))
end

local function matches_context_target(candidate)
  local text = lower_text(candidate)
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
  return value_or(action and action.type, "unknown")
end

local function describe_action(action)
  local current_type = action_type(action)

  if current_type == "read" then
    local path = display_path(action.path)
    if path then
      return string.format("Read %s", compact_inline_code(path) or path)
    end
    return string.format("Read %s", compact_inline_code(action.name or "file") or "file")
  end

  if current_type == "listFiles" then
    local path = display_path(action.path) or "workspace"
    return string.format("Listed files in %s", compact_inline_code(path) or path)
  end

  if current_type == "search" then
    local path = display_path(action.path) or "workspace"
    local query = plain_snippet(action.query, 40)
    if query then
      return string.format("Searched %s for %s", compact_inline_code(path) or path, compact_inline_code(query) or query)
    end
    return string.format("Searched %s", compact_inline_code(path) or path)
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
