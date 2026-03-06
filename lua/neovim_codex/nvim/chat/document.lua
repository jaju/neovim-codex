local selectors = require("neovim_codex.core.selectors")

local M = {}

local CONTEXT_PATTERNS = {
  ".codex/skills",
  "agents.md",
  ".agent-kit",
  "docs/knowledge",
  "prompt-control",
  "topics.agent.tsv",
}

local function present(value)
  return value ~= nil and type(value) ~= "userdata"
end

local function value_or(value, fallback)
  if present(value) and value ~= "" then
    return tostring(value)
  end
  return fallback
end

local function split_lines(text)
  if not present(text) or text == "" then
    return {}
  end
  return vim.split(tostring(text), "\n", { plain = true })
end

local function push_text(lines, text)
  for _, line in ipairs(split_lines(text)) do
    lines[#lines + 1] = line
  end
end

local function add_block(blocks, block)
  blocks[#blocks + 1] = block
end

local function clone_value(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for key, item in pairs(value) do
    out[key] = clone_value(item)
  end
  return out
end

local function display_path(path)
  if not present(path) then
    return nil
  end

  local text = tostring(path)
  local home = vim.env.HOME
  if home and text:sub(1, #home) == home then
    return "~" .. text:sub(#home + 1)
  end
  return text
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

  return value:sub(1, limit - 3) .. "..."
end

local function preview_text_block(lines, fence, text, limit)
  local preview_lines = split_lines(text)
  if #preview_lines == 0 then
    return
  end

  lines[#lines + 1] = string.format("```%s", fence)
  for index = 1, math.min(#preview_lines, limit) do
    lines[#lines + 1] = preview_lines[index]
  end
  if #preview_lines > limit then
    lines[#lines + 1] = string.format("... (%d more lines)", #preview_lines - limit)
  end
  lines[#lines + 1] = "```"
end

local function protocol_payload(item)
  return {
    item_type = item.type,
    item = clone_value(item),
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
    local name = value_or(action.name, path or "file")
    if path then
      return string.format("Read `%s`.", path)
    end
    return string.format("Read `%s`.", name)
  end

  if action_type == "listFiles" then
    local path = display_path(action.path) or "workspace"
    return string.format("Listed files in `%s`.", path)
  end

  if action_type == "search" then
    local path = display_path(action.path) or "workspace"
    local query = trim_text(action.query, 72)
    if query then
      return string.format("Searched `%s` for `%s`.", path, query)
    end
    return string.format("Searched `%s`.", path)
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

local function append_command_metadata(lines, item)
  if present(item.cwd) then
    lines[#lines + 1] = string.format("- Working directory: `%s`", display_path(item.cwd) or tostring(item.cwd))
  end

  local duration = duration_label(item.durationMs)
  if duration then
    lines[#lines + 1] = string.format("- Duration: `%s`", duration)
  end

  if present(item.exitCode) then
    lines[#lines + 1] = string.format("- Exit code: `%s`", tostring(item.exitCode))
  end
end

local function summarize_command_activity(item, actions)
  local lines = {
    string.format("#### Activity · `%s`", value_or(item.status, "unknown")),
  }

  if actions.has_context then
    lines[#lines + 1] = "- Loaded local instructions and workspace context."
  end

  local limit = actions.has_context and 2 or 3
  for index = 1, math.min(#actions.summaries, limit) do
    lines[#lines + 1] = "- " .. actions.summaries[index]
  end

  if #actions.summaries > limit then
    lines[#lines + 1] = string.format("- %d more inspection step%s.", #actions.summaries - limit, #actions.summaries - limit == 1 and "" or "s")
  end

  local duration = duration_label(item.durationMs)
  if duration then
    lines[#lines + 1] = string.format("- Completed in `%s`.", duration)
  end

  return new_block({
    kind = "activity_summary",
    surface = "activity",
    collapsed_by_default = true,
    lines = lines,
    protocol = protocol_payload(item),
  })
end

local function summarize_command_detail(item, actions)
  local lines = {
    string.format("#### Command · `%s`", value_or(item.status, "unknown")),
  }

  if #actions.summaries > 0 then
    lines[#lines + 1] = "- Actions:"
    for _, summary in ipairs(actions.summaries) do
      lines[#lines + 1] = "  - " .. summary
    end
  end

  append_command_metadata(lines, item)

  lines[#lines + 1] = "```sh"
  lines[#lines + 1] = value_or(item.command, "")
  lines[#lines + 1] = "```"

  preview_text_block(lines, "text", item.aggregatedOutput, 8)

  return new_block({
    kind = "command_detail",
    surface = "command_detail",
    collapsed_by_default = true,
    lines = lines,
    protocol = protocol_payload(item),
  })
end

local function summarize_command(item)
  local actions = summarize_command_actions(item.commandActions)
  if value_or(item.status, "unknown") == "completed" and actions.known_only then
    return summarize_command_activity(item, actions)
  end

  return summarize_command_detail(item, actions)
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
    string.format("#### File changes · `%s`", value_or(item.status, "unknown")),
  }

  if #changes == 0 then
    lines[#lines + 1] = "- No file details were reported."
  else
    for _, change in ipairs(changes) do
      local path = display_path(change.path) or "unknown"
      local kind = describe_patch_kind(change.kind)
      lines[#lines + 1] = string.format("- `%s` · %s", path, kind)
    end
  end

  return new_block({
    kind = "file_change_summary",
    surface = "file_change",
    collapsed_by_default = true,
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

local function summarize_tool_result_lines(item)
  if item.type == "dynamicToolCall" and item.contentItems then
    local lines = {}
    for _, content_item in ipairs(item.contentItems) do
      if content_item.type == "inputText" and present(content_item.text) then
        push_text(lines, content_item.text)
      elseif content_item.type == "inputImage" and present(content_item.imageUrl) then
        lines[#lines + 1] = string.format("Image: %s", content_item.imageUrl)
      end
    end
    return lines
  end

  if item.type == "mcpToolCall" and item.result then
    if present(item.result.content) then
      return split_lines(item.result.content)
    end
    local preview = json_preview(item.result)
    return preview and { preview } or {}
  end

  return {}
end

local function summarize_tool_call(item)
  local label = item.type == "dynamicToolCall" and "Dynamic tool" or "Tool"
  local lines = {
    string.format("#### %s · `%s`", label, value_or(item.status, "unknown")),
  }

  if item.type == "dynamicToolCall" then
    lines[#lines + 1] = string.format("- Tool: `%s`", value_or(item.tool, "unknown"))
    if item.success ~= nil then
      lines[#lines + 1] = string.format("- Success: `%s`", tostring(item.success))
    end
  else
    lines[#lines + 1] = string.format("- Server: `%s`", value_or(item.server, "unknown"))
    lines[#lines + 1] = string.format("- Tool: `%s`", value_or(item.tool, "unknown"))
    if item.error and present(item.error.message) then
      lines[#lines + 1] = string.format("- Error: %s", item.error.message)
    end
  end

  local duration = duration_label(item.durationMs)
  if duration then
    lines[#lines + 1] = string.format("- Duration: `%s`", duration)
  end

  local preview_lines = summarize_tool_result_lines(item)
  if #preview_lines > 0 then
    lines[#lines + 1] = "```text"
    for index = 1, math.min(#preview_lines, 6) do
      lines[#lines + 1] = preview_lines[index]
    end
    if #preview_lines > 6 then
      lines[#lines + 1] = string.format("... (%d more lines)", #preview_lines - 6)
    end
    lines[#lines + 1] = "```"
  else
    local arguments = json_preview(item.arguments)
    if arguments then
      lines[#lines + 1] = string.format("- Arguments: `%s`", arguments)
    end
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
  local lines = {
    string.format("#### Collaboration · `%s`", value_or(item.status, "unknown")),
    string.format("- Tool: `%s`", value_or(item.tool, "unknown")),
    string.format("- Sender thread: `%s`", value_or(item.senderThreadId, "unknown")),
  }

  if item.receiverThreadIds and #item.receiverThreadIds > 0 then
    lines[#lines + 1] = string.format("- Receiver threads: `%s`", table.concat(item.receiverThreadIds, "`, `"))
  end

  if present(item.prompt) then
    lines[#lines + 1] = string.format("- Prompt: `%s`", trim_text(item.prompt, 100))
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
  local lines = {
    "#### Web search",
    string.format("- Query: `%s`", value_or(item.query, "")),
  }

  if item.action and present(item.action.type) then
    lines[#lines + 1] = string.format("- Action: `%s`", item.action.type)
    if present(item.action.url) then
      lines[#lines + 1] = string.format("- URL: `%s`", item.action.url)
    end
    if present(item.action.pattern) then
      lines[#lines + 1] = string.format("- Pattern: `%s`", item.action.pattern)
    end
  end

  return new_block({
    kind = "activity_summary",
    surface = "activity",
    collapsed_by_default = true,
    lines = lines,
    protocol = protocol_payload(item),
  })
end

local function summarize_image_item(item)
  local lines = {}

  if item.type == "imageView" then
    lines = {
      "#### Image view",
      string.format("- Path: `%s`", display_path(item.path) or ""),
    }
  else
    lines = {
      string.format("#### Image generation · `%s`", value_or(item.status, "unknown")),
      string.format("- Result: `%s`", value_or(item.result, "")),
    }
    if present(item.revisedPrompt) then
      lines[#lines + 1] = string.format("- Revised prompt: `%s`", trim_text(item.revisedPrompt, 120))
    end
  end

  return new_block({
    kind = "status_notice",
    surface = "notice",
    collapsed_by_default = true,
    lines = lines,
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
      entered and "#### Review mode entered" or "#### Review mode exited",
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
      "#### Context compaction",
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
      string.format("#### Item · `%s`", value_or(item.type, "unknown")),
      "- This item does not have a dedicated transcript surface yet.",
      "- Inspect `:CodexEvents` for the full raw protocol payload.",
    },
    protocol = protocol_payload(item),
  })
end

local function summarize_reasoning(item)
  local lines = { "#### Reasoning summary" }

  if item.summary and #item.summary > 0 then
    for _, summary in ipairs(item.summary) do
      lines[#lines + 1] = string.format("- %s", summary)
    end
  elseif item.content and #item.content > 0 then
    lines[#lines + 1] = "- Raw reasoning content is available for this item."
    preview_text_block(lines, "text", table.concat(item.content, "\n"), 6)
  else
    lines[#lines + 1] = "- Reasoning is still streaming."
  end

  return new_block({
    kind = "reasoning_summary",
    surface = "reasoning",
    collapsed_by_default = true,
    lines = lines,
    protocol = protocol_payload(item),
  })
end

local function summarize_plan(item)
  local text = present(item.text) and item.text ~= "" and item.text or "_Streaming plan..._"
  return new_block({
    kind = "plan",
    surface = "plan",
    collapsed_by_default = false,
    lines = vim.list_extend({ "#### Plan" }, split_lines(text)),
    protocol = protocol_payload(item),
  })
end

local function summarize_user_message(item)
  return new_block({
    kind = "user_message",
    surface = "message_user",
    collapsed_by_default = false,
    lines = vim.list_extend({ "### You" }, user_content_lines(item.content)),
    protocol = protocol_payload(item),
  })
end

local function summarize_agent_message(item)
  local text = present(item.text) and item.text ~= "" and item.text or "_Streaming response..._"
  local heading = "### Codex"
  if present(item.phase) then
    heading = string.format("### Codex · `%s`", item.phase)
  end

  return new_block({
    kind = "assistant_message",
    surface = "message_assistant",
    collapsed_by_default = false,
    lines = vim.list_extend({ heading }, split_lines(text)),
    protocol = protocol_payload(item),
  })
end

local function summarize_item(item)
  if item.type == "userMessage" then
    return summarize_user_message(item)
  end
  if item.type == "agentMessage" then
    return summarize_agent_message(item)
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

  lines[#lines + 1] = string.format("## Turn %d", index)

  local details = {}
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
    header_lines = 1,
    lines = lines,
  })
end

local function thread_footer(thread)
  local turns = selectors.list_turns(thread)
  local status = thread.status and thread.status.type or "unknown"
  return string.format("thread %s · %d turn%s · %s", thread.id, #turns, #turns == 1 and "" or "s", status)
end

local function project_thread(thread, opts)
  opts = opts or {}

  local doc = {
    title = opts.title,
    thread_id = thread.id,
    footer = thread_footer(thread),
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

  local turns = selectors.list_turns(thread)
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

    local items = selectors.list_items(turn)
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
        block.id = string.format("turn:%s:item:%s", turn.id, item.id or item.type)
        block.turn_id = turn.id
        block.item_id = item.id
        add_block(doc.blocks, block)
      end
    end
  end

  return doc
end

function M.project_active(state, opts)
  local thread = selectors.get_active_thread(state)
  if thread then
    return project_thread(thread, opts)
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
  return project_thread(thread, opts)
end

return M
