local selectors = require("neovim_codex.core.selectors")
local text_utils = require("neovim_codex.core.text")
local value = require("neovim_codex.core.value")
local thread_identity = require("neovim_codex.nvim.thread_identity")

local M = {}

local CONTEXT_PATTERNS = {
  ".codex/skills",
  "agents.md",
  ".agent-kit",
  "docs/knowledge",
  "prompt-control",
  "topics.agent.tsv",
}

local IN_PROGRESS_ITEM_TYPES = {
  commandExecution = true,
  fileChange = true,
  mcpToolCall = true,
  dynamicToolCall = true,
  collabAgentToolCall = true,
}

local display_path = text_utils.display_path
local present = value.present
local split_lines = text_utils.split_lines

local function value_or(value, fallback)
  if present(value) and value ~= "" then
    return tostring(value)
  end
  return fallback
end

local function push_text(lines, text)
  for _, line in ipairs(split_lines(text)) do
    lines[#lines + 1] = line
  end
end

local function add_block(blocks, block)
  if not block then
    return
  end
  blocks[#blocks + 1] = block
end

local function duration_label(duration_ms)
  local value = tonumber(duration_ms)
  if not value then
    return nil
  end

  if value < 1000 then
    return string.format("%d ms", value)
  end

  return string.format("%.2f s", value / 1000)
end

local function trim_text(text, limit)
  if not present(text) then
    return nil
  end

  local value = tostring(text)
  if #value <= limit then
    return value
  end

  return value:sub(1, math.max(1, limit - 3)) .. "..."
end

local function compact_inline_code(text)
  local value = trim_text(text, 64)
  if not value then
    return nil
  end
  return string.format("`%s`", value)
end

local function plain_snippet(text, limit)
  if not present(text) then
    return nil
  end

  local value = tostring(text)
  value = value:gsub("`+", "")
  value = value:gsub("[%*_>#-]+", " ")
  value = value:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
  value = value:gsub("\n", " ")
  value = value:gsub("%s+", " ")
  value = vim.trim(value)
  if value == "" then
    return nil
  end

  return trim_text(value, limit)
end

local function first_nonempty_line(lines)
  for _, line in ipairs(lines or {}) do
    local trimmed = vim.trim(tostring(line))
    if trimmed ~= "" then
      return trimmed
    end
  end
  return nil
end

local function compact_output_preview(text)
  local line = first_nonempty_line(split_lines(text))
  return plain_snippet(line, 96)
end

local function markdown_heading(level, title, opts)
  local foldable = opts and opts.foldable == true and " {.foldable}" or ""
  return string.format("%s %s%s", string.rep("#", math.max(1, level or 1)), title, foldable)
end

local function preview_lines(text, max_lines)
  local lines = split_lines(text)
  local limit = math.max(1, tonumber(max_lines) or 8)
  if #lines <= limit then
    return lines
  end

  local out = {}
  for index = 1, limit do
    out[#out + 1] = lines[index]
  end
  out[#out + 1] = "..."
  return out
end

local function fenced_block(language, text, max_lines)
  local body = type(text) == "table" and value.deep_copy(text) or preview_lines(text, max_lines)
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

local function extend_lines(lines, extra)
  for _, line in ipairs(extra or {}) do
    lines[#lines + 1] = line
  end
  return lines
end

local function join_parts(parts, separator)
  local values = {}
  for _, part in ipairs(parts or {}) do
    if present(part) and tostring(part) ~= "" then
      values[#values + 1] = tostring(part)
    end
  end
  return table.concat(values, separator or " · ")
end

local function protocol_payload(item)
  return {
    item_type = item.type,
    item = value.deep_copy(item),
  }
end

local function new_block(spec)
  return {
    kind = spec.kind,
    surface = spec.surface or spec.kind,
    collapsed_by_default = spec.collapsed_by_default == true,
    header_lines = spec.header_lines or 1,
    lines = spec.lines or {},
    protocol = spec.protocol,
  }
end

local function user_content_lines(content)
  local lines = {}

  if not content or #content == 0 then
    return { "_Empty message._" }
  end

  for _, item in ipairs(content) do
    if item.type == "text" then
      push_text(lines, item.text)
    elseif item.type == "skill" then
      lines[#lines + 1] = string.format("- Skill `%s` (`%s`)", value_or(item.name, "skill"), display_path(item.path) or "")
    elseif item.type == "mention" then
      lines[#lines + 1] = string.format("- Mention `%s` (`%s`)", value_or(item.name, "mention"), value_or(item.path, ""))
    elseif item.type == "image" then
      lines[#lines + 1] = string.format("- Image `%s`", value_or(item.url, ""))
    elseif item.type == "localImage" then
      lines[#lines + 1] = string.format("- Local image `%s`", display_path(item.path) or "")
    else
      lines[#lines + 1] = string.format("- %s", value_or(item.type, "unknown item"))
    end
  end

  if #lines == 0 then
    return { "_Empty message._" }
  end

  return lines
end

local function user_message_text(content)
  local parts = {}

  for _, item in ipairs(content or {}) do
    if item.type == "text" and present(item.text) then
      parts[#parts + 1] = item.text
    end
  end

  return table.concat(parts, "\n")
end

local function lower_text(value)
  return string.lower(value_or(value, ""))
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

local function command_action_type(action)
  return value_or(action and action.type, "unknown")
end

local function describe_command_action(action)
  local action_type = command_action_type(action)

  if action_type == "read" then
    local path = display_path(action.path)
    if path then
      return string.format("Read %s", compact_inline_code(path) or path)
    end
    return string.format("Read %s", compact_inline_code(action.name or "file") or "file")
  end

  if action_type == "listFiles" then
    local path = display_path(action.path) or "workspace"
    return string.format("Listed files in %s", compact_inline_code(path) or path)
  end

  if action_type == "search" then
    local path = display_path(action.path) or "workspace"
    local query = plain_snippet(action.query, 40)
    if query then
      return string.format("Searched %s for %s", compact_inline_code(path) or path, compact_inline_code(query) or query)
    end
    return string.format("Searched %s", compact_inline_code(path) or path)
  end

  return nil
end

local function action_targets_context(action)
  local action_type = command_action_type(action)

  if action_type == "read" then
    return matches_context_target(action.path) or matches_context_target(action.name)
  end

  if action_type == "listFiles" then
    return matches_context_target(action.path)
  end

  if action_type == "search" then
    return matches_context_target(action.path) or matches_context_target(action.query)
  end

  return false
end

local function summarize_command_actions(actions)
  local summaries = {}
  local known_actions = 0
  local unknown_actions = 0
  local context_actions = 0

  for _, action in ipairs(actions or {}) do
    local description = describe_command_action(action)
    if description then
      summaries[#summaries + 1] = description
      known_actions = known_actions + 1
    else
      unknown_actions = unknown_actions + 1
    end

    if action_targets_context(action) then
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

local function in_progress_item_count(turn)
  local count = 0
  for _, item in ipairs(selectors.list_items(turn)) do
    if IN_PROGRESS_ITEM_TYPES[item.type] and value_or(item.status, "") == "inProgress" then
      count = count + 1
    end
  end
  return count
end

local function turn_title(turn, index)
  local items = selectors.list_items(turn)

  for _, item in ipairs(items) do
    if item.type == "userMessage" then
      local snippet = plain_snippet(user_message_text(item.content), 72)
      if snippet then
        return string.format("## %s", snippet)
      end
    end
  end

  for _, item in ipairs(items) do
    if item.type == "plan" then
      local snippet = plain_snippet(item.text, 72)
      if snippet then
        return string.format("## %s", snippet)
      end
    end
    if item.type == "agentMessage" then
      local snippet = plain_snippet(item.text, 72)
      if snippet then
        return string.format("## %s", snippet)
      end
    end
  end

  return string.format("## Turn %d", index)
end

local function list_thread_turns(thread)
  if type(thread) ~= "table" then
    return {}
  end

  if type(thread.turns_order) == "table" and type(thread.turns_by_id) == "table" then
    return selectors.list_turns(thread)
  end

  if type(thread.turns) == "table" then
    return thread.turns
  end

  return {}
end

local function format_token_count(value)
  local count = tonumber(value) or 0
  if count >= 1000000 then
    return string.format("%.1fm", count / 1000000)
  end
  if count >= 1000 then
    return string.format("%.1fk", count / 1000)
  end
  return tostring(math.floor(count))
end

local function token_usage_summary(token_usage_state)
  if type(token_usage_state) ~= "table" or type(token_usage_state.tokenUsage) ~= "table" then
    return nil
  end

  local usage = token_usage_state.tokenUsage
  local total = usage.total or {}
  local last = usage.last or {}
  local parts = {
    string.format("tokens %s last", format_token_count(last.totalTokens or 0)),
    string.format("%s total", format_token_count(total.totalTokens or 0)),
  }

  if tonumber(usage.modelContextWindow) and usage.modelContextWindow > 0 and tonumber(total.totalTokens) then
    local used = (total.totalTokens / usage.modelContextWindow) * 100
    parts[#parts + 1] = string.format("%.0f%% ctx", used)
  end

  return table.concat(parts, " / ")
end

local function list_turn_items(turn)
  if type(turn) ~= "table" then
    return {}
  end

  if type(turn.items_order) == "table" and type(turn.items_by_id) == "table" then
    return selectors.list_items(turn)
  end

  if type(turn.items) == "table" then
    return turn.items
  end

  return {}
end

local function thread_footer(state, thread, pending_requests)
  local turns = list_thread_turns(thread)
  local status = thread.status and thread.status.type or "unknown"
  local active_turn = turns[#turns]
  local status_bits = { status }
  local fragment_counts = state and selectors.workbench_fragment_counts(state, thread.id) or { total = 0, active = 0, parked = 0 }
  local token_usage = state and selectors.get_thread_token_usage(state, thread.id) or nil
  local short_id = thread_identity.short_id(thread.id)
  local title = thread_identity.title(thread, { max_length = 32 })

  if active_turn and active_turn.status == "inProgress" then
    local running = in_progress_item_count(active_turn)
    if running > 0 then
      status_bits[#status_bits + 1] = string.format("%d operation%s running", running, running == 1 and "" or "s")
    else
      status_bits[#status_bits + 1] = "waiting for response"
    end
  end

  if (pending_requests or 0) > 0 then
    status_bits[#status_bits + 1] = string.format("%d request%s pending", pending_requests, pending_requests == 1 and "" or "s")
  end

  local workbench_summary = nil
  if fragment_counts.parked > 0 then
    workbench_summary = string.format("workbench %d active / %d parked", fragment_counts.active, fragment_counts.parked)
  else
    workbench_summary = string.format("workbench %d fragment%s", fragment_counts.total, fragment_counts.total == 1 and "" or "s")
  end
  local token_summary = token_usage_summary(token_usage)

  local trailing_parts = { workbench_summary }
  if token_summary then
    trailing_parts[#trailing_parts + 1] = token_summary
  end
  trailing_parts[#trailing_parts + 1] = string.format("%d turn%s", #turns, #turns == 1 and "" or "s")
  trailing_parts[#trailing_parts + 1] = table.concat(status_bits, " · ")

  local footer = string.format(
    "thread %s · %s · %s",
    short_id,
    title,
    table.concat(trailing_parts, " · ")
  )

  local segments = {
    { text = string.format("thread %s", short_id), highlight = "NeovimCodexChatFooterMeta" },
    { text = " · ", highlight = "NeovimCodexChatFooterMeta" },
    { text = title, highlight = "NeovimCodexChatFooterThread" },
    { text = string.format(" · %s", table.concat(trailing_parts, " · ")), highlight = "NeovimCodexChatFooterMeta" },
  }

  return footer, segments
end

local function summarize_user_message(item)
  local content_lines = user_content_lines(item.content)
  return new_block({
    kind = "user_message",
    surface = "message_user",
    collapsed_by_default = false,
    lines = extend_lines({ markdown_heading(3, "Request") }, content_lines),
    protocol = protocol_payload(item),
  })
end

local function summarize_assistant_message(item)
  local text = present(item.text) and item.text ~= "" and item.text or "_Streaming response..._"
  local lines = split_lines(text)
  local phase = value_or(item.phase, "")

  if phase == "commentary" then
    local quoted = { markdown_heading(3, "Working Note", { foldable = true }), "" }
    for _, line in ipairs(lines) do
      quoted[#quoted + 1] = line == "" and ">" or "> " .. line
    end
    return new_block({
      kind = "assistant_message",
      surface = "assistant_note",
      collapsed_by_default = true,
      lines = quoted,
      protocol = protocol_payload(item),
    })
  end

  return new_block({
    kind = "assistant_message",
    surface = "message_assistant",
    collapsed_by_default = false,
    lines = extend_lines({ markdown_heading(3, "Response") }, lines),
    protocol = protocol_payload(item),
  })
end

local function summarize_plan(item)
  local text = present(item.text) and item.text ~= "" and item.text or "_Streaming plan..._"
  return new_block({
    kind = "plan",
    surface = "plan",
    collapsed_by_default = true,
    lines = extend_lines({ markdown_heading(3, "Plan", { foldable = true }) }, split_lines(text)),
    protocol = protocol_payload(item),
  })
end

local function summarize_reasoning(item)
  if item.summary and #item.summary > 0 then
    local lines = { markdown_heading(3, "Reasoning Summary", { foldable = true }) }
    for _, summary in ipairs(item.summary) do
      lines[#lines + 1] = string.format("- %s", value_or(plain_snippet(summary, 160), "summary available"))
    end
    return new_block({
      kind = "reasoning_summary",
      surface = "reasoning",
      collapsed_by_default = true,
      lines = lines,
      protocol = protocol_payload(item),
    })
  end

  if item.content and #item.content > 0 then
    local lines = {
      markdown_heading(3, "Reasoning", { foldable = true }),
      "- Raw reasoning content is available.",
    }
    return new_block({
      kind = "reasoning_summary",
      surface = "reasoning",
      collapsed_by_default = true,
      lines = lines,
      protocol = protocol_payload(item),
    })
  end

  return nil
end

local function summarize_successful_command(item, actions)
  local parts = {}

  if actions.has_context then
    parts[#parts + 1] = "Loaded local instructions and workspace context"
  elseif #actions.summaries > 0 then
    parts[#parts + 1] = actions.summaries[1]
  else
    parts[#parts + 1] = string.format("Completed command %s", compact_inline_code(trim_text(item.command, 48)) or "")
  end

  if #actions.summaries > 1 and not actions.has_context then
    parts[#parts + 1] = string.format("%d additional step%s", #actions.summaries - 1, #actions.summaries - 1 == 1 and "" or "s")
  end

  local lines = {
    markdown_heading(3, "Command", { foldable = true }),
    string.format("- Status: `%s`", value_or(item.status, "completed")),
    string.format("- Summary: %s", join_parts(parts, " · ")),
  }
  local duration = duration_label(item.durationMs)
  if duration then
    lines[#lines + 1] = string.format("- Duration: `%s`", duration)
  end

  return new_block({
    kind = "activity_summary",
    surface = "activity",
    collapsed_by_default = true,
    lines = lines,
    protocol = protocol_payload(item),
  })
end

local function summarize_command_failure(item, actions)
  local status = value_or(item.status, "unknown")
  local label = compact_inline_code(trim_text(item.command, 56)) or "command"
  local lines = {
    markdown_heading(3, "Command", { foldable = true }),
    string.format("- Status: `%s`", status),
    string.format("- Command: %s", label),
  }

  if present(item.exitCode) then
    lines[#lines + 1] = string.format("- Exit code: `%s`", tostring(item.exitCode))
  end

  if #actions.summaries > 0 then
    lines[#lines + 1] = string.format("- Action: %s", actions.summaries[1])
  end

  if #fenced_block("text", item.aggregatedOutput, 8) > 0 then
    lines[#lines + 1] = ""
    extend_lines(lines, fenced_block("text", item.aggregatedOutput, 8))
  end

  return new_block({
    kind = "command_detail",
    surface = "command_detail",
    collapsed_by_default = true,
    lines = lines,
    protocol = protocol_payload(item),
  })
end

local function summarize_command(item)
  local status = value_or(item.status, "unknown")
  if status == "inProgress" then
    return nil
  end

  local actions = summarize_command_actions(item.commandActions)
  if status == "completed" then
    return summarize_successful_command(item, actions)
  end

  return summarize_command_failure(item, actions)
end

local function describe_patch_kind(kind)
  if type(kind) == "table" then
    local kind_type = value_or(kind.type, "update")
    if kind_type == "update" and present(kind.movePath) then
      return string.format("updated (moved to `%s`)", display_path(kind.movePath) or tostring(kind.movePath))
    end
    return kind_type
  end

  return value_or(kind, "updated")
end

local function summarize_file_changes(item)
  local changes = item.changes or {}
  local lines = {
    markdown_heading(3, "File Changes", { foldable = true }),
    string.format("- Files: `%d`", #changes),
  }

  if #changes == 0 then
    lines[#lines + 1] = "- No file details were reported."
  else
    for _, change in ipairs(changes) do
      local path = display_path(change.path) or "unknown"
      local kind = describe_patch_kind(change.kind)
      lines[#lines + 1] = string.format("- `%s` · %s", path, kind)
    end

    local first_change = changes[1]
    if first_change and present(first_change.diff) then
      lines[#lines + 1] = ""
      extend_lines(lines, fenced_block("diff", first_change.diff, 20))
    end
  end

  return new_block({
    kind = "file_change_summary",
    surface = "file_change",
    collapsed_by_default = false,
    lines = lines,
    protocol = protocol_payload(item),
  })
end

local function json_preview(value)
  if not present(value) then
    return nil
  end

  local ok, encoded = pcall(vim.json.encode, value)
  if not ok then
    return nil
  end

  return trim_text(encoded, 160)
end

local function summarize_tool_call(item)
  local status = value_or(item.status, "unknown")
  if status == "inProgress" then
    return nil
  end

  local name = item.type == "dynamicToolCall" and value_or(item.tool, "tool") or string.format("%s/%s", value_or(item.server, "server"), value_or(item.tool, "tool"))
  local preview = nil
  if item.type == "dynamicToolCall" and item.contentItems then
    for _, content_item in ipairs(item.contentItems) do
      if content_item.type == "inputText" and present(content_item.text) then
        preview = plain_snippet(content_item.text, 96)
        break
      end
    end
  elseif item.type == "mcpToolCall" and type(item.error) == "table" and present(item.error.message) then
    preview = plain_snippet(item.error.message, 96)
  elseif item.type == "mcpToolCall" and item.result then
    preview = json_preview(item.result)
  end

  local lines = {
    markdown_heading(3, "Tool Call", { foldable = true }),
    string.format("- Status: `%s`", status),
    string.format("- Tool: %s", compact_inline_code(name) or name),
  }
  if preview then
    lines[#lines + 1] = string.format("- Preview: %s", preview)
  end

  return new_block({
    kind = "tool_summary",
    surface = "tool",
    collapsed_by_default = true,
    lines = lines,
    protocol = protocol_payload(item),
  })
end

local function summarize_collab_tool_call(item)
  local status = value_or(item.status, "unknown")
  if status == "inProgress" then
    return nil
  end

  local receiver_count = type(item.receiverThreadIds) == "table" and #item.receiverThreadIds or 0

  local lines = {
    markdown_heading(3, "Collaboration", { foldable = true }),
    string.format("- Status: `%s`", status),
    string.format("- Tool: %s", compact_inline_code(value_or(item.tool, "tool"))),
  }
  if present(item.model) then
    lines[#lines + 1] = string.format("- Model: `%s`", item.model)
  end
  if present(item.reasoningEffort) then
    lines[#lines + 1] = string.format("- Effort: `%s`", item.reasoningEffort)
  end
  if receiver_count > 0 then
    lines[#lines + 1] = string.format("- Targets: `%d`", receiver_count)
  end
  if present(item.prompt) then
    lines[#lines + 1] = string.format("- Prompt: %s", value_or(plain_snippet(item.prompt, 96), "prompt available"))
  end

  return new_block({
    kind = "tool_summary",
    surface = "tool",
    collapsed_by_default = true,
    lines = lines,
    protocol = protocol_payload(item),
  })
end

local function summarize_web_search(item)
  local query = plain_snippet(item.query, 72) or "query"
  return new_block({
    kind = "activity_summary",
    surface = "activity",
    collapsed_by_default = true,
    lines = {
      markdown_heading(3, "Web Search", { foldable = true }),
      string.format("- Query: %s", query),
    },
    protocol = protocol_payload(item),
  })
end

local function summarize_image_item(item)
  if item.type == "imageView" then
    return new_block({
      kind = "status_notice",
      surface = "notice",
      collapsed_by_default = true,
      lines = {
        markdown_heading(3, "Image View", { foldable = true }),
        string.format("- Path: %s", compact_inline_code(display_path(item.path) or "image") or ""),
      },
      protocol = protocol_payload(item),
    })
  end

  local result = plain_snippet(item.result, 72) or value_or(item.status, "unknown")
  return new_block({
    kind = "status_notice",
    surface = "notice",
    collapsed_by_default = true,
    lines = {
      markdown_heading(3, "Image Generation", { foldable = true }),
      string.format("- Result: %s", result),
    },
    protocol = protocol_payload(item),
  })
end

local function summarize_review_mode(item)
  local entered = item.type == "enteredReviewMode"
  return new_block({
    kind = "review_mode",
    surface = "review",
    collapsed_by_default = true,
    lines = {
      markdown_heading(3, "Review Mode", { foldable = true }),
      string.format("- State: `%s`", entered and "entered" or "exited"),
      string.format("- Review: `%s`", value_or(item.review, "unknown")),
    },
    protocol = protocol_payload(item),
  })
end

local function summarize_context_compaction(item)
  return new_block({
    kind = "status_notice",
    surface = "notice",
    collapsed_by_default = true,
    lines = {
      markdown_heading(3, "Context Compaction", { foldable = true }),
      "- Codex compacted the conversation history for this thread.",
    },
    protocol = protocol_payload(item),
  })
end

local function summarize_unknown_item(item)
  return new_block({
    kind = "unknown_item",
    surface = "notice",
    collapsed_by_default = true,
    lines = {
      markdown_heading(3, "Protocol Notice", { foldable = true }),
      string.format("- Item `%s` is available in raw protocol logs.", value_or(item.type, "unknown")),
    },
    protocol = protocol_payload(item),
  })
end

local function summarize_item(item)
  if item.type == "userMessage" then
    return summarize_user_message(item)
  end
  if item.type == "agentMessage" then
    return summarize_assistant_message(item)
  end
  if item.type == "plan" then
    return summarize_plan(item)
  end
  if item.type == "reasoning" then
    return summarize_reasoning(item)
  end
  if item.type == "commandExecution" then
    return summarize_command(item)
  end
  if item.type == "fileChange" then
    return summarize_file_changes(item)
  end
  if item.type == "mcpToolCall" or item.type == "dynamicToolCall" then
    return summarize_tool_call(item)
  end
  if item.type == "collabAgentToolCall" then
    return summarize_collab_tool_call(item)
  end
  if item.type == "webSearch" then
    return summarize_web_search(item)
  end
  if item.type == "imageView" or item.type == "imageGeneration" then
    return summarize_image_item(item)
  end
  if item.type == "enteredReviewMode" or item.type == "exitedReviewMode" then
    return summarize_review_mode(item)
  end
  if item.type == "contextCompaction" then
    return summarize_context_compaction(item)
  end

  return summarize_unknown_item(item)
end

local function turn_heading(index, turn)
  local lines = {}

  if index > 1 then
    lines[#lines + 1] = "---"
  end

  lines[#lines + 1] = turn_title(turn, index)

  local details = { string.format("turn %d", index) }
  if present(turn.status) and turn.status ~= "completed" then
    details[#details + 1] = string.format("status `%s`", turn.status)
  end
  if present(turn.error) and present(turn.error.message) then
    details[#details + 1] = string.format("error: %s", turn.error.message)
  end
  if #details > 0 then
    lines[#lines + 1] = string.format("_%s_", table.concat(details, " · "))
  end

  return new_block({
    kind = "turn_boundary",
    surface = "turn_heading",
    collapsed_by_default = false,
    lines = lines,
  })
end

local function project_thread(thread, opts)
  opts = opts or {}

  local pending_requests = opts.state and selectors.pending_request_count(opts.state) or 0
  local footer, footer_segments = thread_footer(opts.state, thread, pending_requests)
  local doc = {
    title = opts.title,
    thread_id = thread.id,
    footer = footer,
    footer_segments = footer_segments,
    pending_requests = pending_requests,
    blocks = {},
  }

  if opts.title then
    add_block(doc.blocks, new_block({
      kind = "metadata",
      surface = "notice",
      lines = {
        opts.title,
        string.format("_Thread `%s`_", thread.id),
      },
    }))
  end

  local turns = list_thread_turns(thread)
  if #turns == 0 then
    add_block(doc.blocks, new_block({
      kind = "metadata",
      surface = "notice",
      lines = {
        "## Ready",
        "- The thread has no turns yet.",
        "- Write in the composer and send when ready.",
      },
    }))
    return doc
  end

  for index, turn in ipairs(turns) do
    local heading = turn_heading(index, turn)
    heading.id = string.format("turn:%s", turn.id)
    heading.turn_id = turn.id
    add_block(doc.blocks, heading)

    local items = list_turn_items(turn)
    if #items == 0 then
      add_block(doc.blocks, {
        id = string.format("turn:%s:pending", turn.id),
        kind = "metadata",
        surface = "notice",
        turn_id = turn.id,
        collapsed_by_default = false,
        header_lines = 1,
        lines = { "_Waiting for items..._" },
      })
    else
      for _, item in ipairs(items) do
        local block = summarize_item(item)
        if block then
          block.id = string.format("turn:%s:item:%s", turn.id, item.id or item.type)
          block.turn_id = turn.id
          block.item_id = item.id
          add_block(doc.blocks, block)
        end
      end
    end
  end

  return doc
end

function M.project_active(state, opts)
  local thread = selectors.get_active_thread(state)
  if thread then
    return project_thread(thread, vim.tbl_extend("force", opts or {}, { state = state }))
  end

  return {
    footer = string.format("connection %s", value_or(state.connection and state.connection.status, "unknown")),
    blocks = {
      new_block({
        kind = "metadata",
        surface = "notice",
        lines = {
          "## Ready",
          "- Open or resume a thread, then start composing below.",
          "- `:CodexThreadNew` creates a fresh thread.",
          "- `:CodexThreads` resumes a stored thread.",
        },
      }),
    },
  }
end

function M.project_thread(thread, opts)
  return project_thread(thread, vim.tbl_extend("force", opts or {}, { state = nil }))
end

return M
