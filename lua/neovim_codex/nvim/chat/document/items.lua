local command_actions = require("neovim_codex.nvim.chat.document.command_actions")
local shared = require("neovim_codex.nvim.chat.document.shared")

local M = {}

local present = shared.present

local function summarize_user_message(item)
  local content_lines = shared.user_content_lines(item.content)
  return shared.new_block({
    kind = "user_message",
    surface = "message_user",
    collapsed_by_default = false,
    lines = shared.extend_lines({ shared.markdown_heading(3, "Request") }, content_lines),
    protocol = shared.protocol_payload(item),
  })
end

local function summarize_assistant_message(item)
  local text = present(item.text) and item.text ~= "" and item.text or "_Streaming response..._"
  local lines = shared.split_lines(text)
  local phase = shared.value_or(item.phase, "")

  if phase == "commentary" then
    local quoted = { shared.markdown_heading(3, "Working Note", { foldable = true }), "" }
    for _, line in ipairs(lines) do
      quoted[#quoted + 1] = line == "" and ">" or "> " .. line
    end
    return shared.new_block({
      kind = "assistant_message",
      surface = "assistant_note",
      collapsed_by_default = true,
      lines = quoted,
      protocol = shared.protocol_payload(item),
    })
  end

  return shared.new_block({
    kind = "assistant_message",
    surface = "message_assistant",
    collapsed_by_default = false,
    lines = shared.extend_lines({ shared.markdown_heading(3, "Response") }, lines),
    protocol = shared.protocol_payload(item),
  })
end

local function summarize_plan(item)
  local text = present(item.text) and item.text ~= "" and item.text or "_Streaming plan..._"
  return shared.new_block({
    kind = "plan",
    surface = "plan",
    collapsed_by_default = true,
    lines = shared.extend_lines({ shared.markdown_heading(3, "Plan", { foldable = true }) }, shared.split_lines(text)),
    protocol = shared.protocol_payload(item),
  })
end

local function summarize_reasoning(item)
  if item.summary and #item.summary > 0 then
    local lines = { shared.markdown_heading(3, "Reasoning Summary", { foldable = true }) }
    for _, summary in ipairs(item.summary) do
      lines[#lines + 1] = string.format("- %s", shared.value_or(shared.plain_snippet(summary, 160), "summary available"))
    end
    return shared.new_block({
      kind = "reasoning_summary",
      surface = "reasoning",
      collapsed_by_default = true,
      lines = lines,
      protocol = shared.protocol_payload(item),
    })
  end

  if item.content and #item.content > 0 then
    return shared.new_block({
      kind = "reasoning_summary",
      surface = "reasoning",
      collapsed_by_default = true,
      lines = {
        shared.markdown_heading(3, "Reasoning", { foldable = true }),
        "- Raw reasoning content is available.",
      },
      protocol = shared.protocol_payload(item),
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
    parts[#parts + 1] = string.format("Completed command %s", shared.compact_inline_code(shared.trim_text(item.command, 48)) or "")
  end

  if #actions.summaries > 1 and not actions.has_context then
    parts[#parts + 1] = string.format("%d additional step%s", #actions.summaries - 1, #actions.summaries - 1 == 1 and "" or "s")
  end

  local lines = {
    shared.markdown_heading(3, "Command", { foldable = true }),
    string.format("- Status: `%s`", shared.value_or(item.status, "completed")),
    string.format("- Summary: %s", shared.join_parts(parts, " · ")),
  }
  local duration = shared.duration_label(item.durationMs)
  if duration then
    lines[#lines + 1] = string.format("- Duration: `%s`", duration)
  end

  return shared.new_block({
    kind = "activity_summary",
    surface = "activity",
    collapsed_by_default = true,
    lines = lines,
    protocol = shared.protocol_payload(item),
  })
end

local function summarize_command_failure(item, actions)
  local status = shared.value_or(item.status, "unknown")
  local label = shared.compact_inline_code(shared.trim_text(item.command, 56)) or "command"
  local lines = {
    shared.markdown_heading(3, "Command", { foldable = true }),
    string.format("- Status: `%s`", status),
    string.format("- Command: %s", label),
  }

  if present(item.exitCode) then
    lines[#lines + 1] = string.format("- Exit code: `%s`", tostring(item.exitCode))
  end

  if #actions.summaries > 0 then
    lines[#lines + 1] = string.format("- Action: %s", actions.summaries[1])
  end

  if #shared.fenced_block("text", item.aggregatedOutput, 8) > 0 then
    lines[#lines + 1] = ""
    shared.extend_lines(lines, shared.fenced_block("text", item.aggregatedOutput, 8))
  end

  return shared.new_block({
    kind = "command_detail",
    surface = "command_detail",
    collapsed_by_default = true,
    lines = lines,
    protocol = shared.protocol_payload(item),
  })
end

local function summarize_command(item)
  local status = shared.value_or(item.status, "unknown")
  if status == "inProgress" then
    return nil
  end

  local actions = command_actions.summarize(item.commandActions)
  if status == "completed" then
    return summarize_successful_command(item, actions)
  end

  return summarize_command_failure(item, actions)
end

local function describe_patch_kind(kind)
  if type(kind) == "table" then
    local kind_type = shared.value_or(kind.type, "update")
    if kind_type == "update" and present(kind.movePath) then
      return string.format("updated (moved to `%s`)", shared.display_path(kind.movePath) or tostring(kind.movePath))
    end
    return kind_type
  end

  return shared.value_or(kind, "updated")
end

local function summarize_file_changes(item)
  local changes = item.changes or {}
  local lines = {
    shared.markdown_heading(3, "File Changes", { foldable = true }),
    string.format("- Files: `%d`", #changes),
  }

  if #changes == 0 then
    lines[#lines + 1] = "- No file details were reported."
  else
    for _, change in ipairs(changes) do
      local path = shared.display_path(change.path) or "unknown"
      local kind = describe_patch_kind(change.kind)
      lines[#lines + 1] = string.format("- `%s` · %s", path, kind)
    end

    local first_change = changes[1]
    if first_change and present(first_change.diff) then
      lines[#lines + 1] = ""
      shared.extend_lines(lines, shared.fenced_block("diff", first_change.diff, 20))
    end
  end

  return shared.new_block({
    kind = "file_change_summary",
    surface = "file_change",
    collapsed_by_default = false,
    lines = lines,
    protocol = shared.protocol_payload(item),
  })
end

local function json_preview(current)
  if not present(current) then
    return nil
  end

  local ok, encoded = pcall(vim.json.encode, current)
  if not ok then
    return nil
  end

  return shared.trim_text(encoded, 160)
end

local function summarize_tool_call(item)
  local status = shared.value_or(item.status, "unknown")
  if status == "inProgress" then
    return nil
  end

  local name = item.type == "dynamicToolCall"
    and shared.value_or(item.tool, "tool")
    or string.format("%s/%s", shared.value_or(item.server, "server"), shared.value_or(item.tool, "tool"))

  local preview = nil
  if item.type == "dynamicToolCall" and item.contentItems then
    for _, content_item in ipairs(item.contentItems) do
      if content_item.type == "inputText" and present(content_item.text) then
        preview = shared.plain_snippet(content_item.text, 96)
        break
      end
    end
  elseif item.type == "mcpToolCall" and type(item.error) == "table" and present(item.error.message) then
    preview = shared.plain_snippet(item.error.message, 96)
  elseif item.type == "mcpToolCall" and item.result then
    preview = json_preview(item.result)
  end

  local lines = {
    shared.markdown_heading(3, "Tool Call", { foldable = true }),
    string.format("- Status: `%s`", status),
    string.format("- Tool: %s", shared.compact_inline_code(name) or name),
  }
  if preview then
    lines[#lines + 1] = string.format("- Preview: %s", preview)
  end

  return shared.new_block({
    kind = "tool_summary",
    surface = "tool",
    collapsed_by_default = true,
    lines = lines,
    protocol = shared.protocol_payload(item),
  })
end

local function summarize_collab_tool_call(item)
  local status = shared.value_or(item.status, "unknown")
  if status == "inProgress" then
    return nil
  end

  local receiver_count = type(item.receiverThreadIds) == "table" and #item.receiverThreadIds or 0
  local lines = {
    shared.markdown_heading(3, "Collaboration", { foldable = true }),
    string.format("- Status: `%s`", status),
    string.format("- Tool: %s", shared.compact_inline_code(shared.value_or(item.tool, "tool"))),
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
    lines[#lines + 1] = string.format("- Prompt: %s", shared.value_or(shared.plain_snippet(item.prompt, 96), "prompt available"))
  end

  return shared.new_block({
    kind = "tool_summary",
    surface = "tool",
    collapsed_by_default = true,
    lines = lines,
    protocol = shared.protocol_payload(item),
  })
end

local function summarize_web_search(item)
  local query = shared.plain_snippet(item.query, 72) or "query"
  return shared.new_block({
    kind = "activity_summary",
    surface = "activity",
    collapsed_by_default = true,
    lines = {
      shared.markdown_heading(3, "Web Search", { foldable = true }),
      string.format("- Query: %s", query),
    },
    protocol = shared.protocol_payload(item),
  })
end

local function summarize_image_item(item)
  if item.type == "imageView" then
    return shared.new_block({
      kind = "status_notice",
      surface = "notice",
      collapsed_by_default = true,
      lines = {
        shared.markdown_heading(3, "Image View", { foldable = true }),
        string.format("- Path: %s", shared.compact_inline_code(shared.display_path(item.path) or "image") or ""),
      },
      protocol = shared.protocol_payload(item),
    })
  end

  local result = shared.plain_snippet(item.result, 72) or shared.value_or(item.status, "unknown")
  return shared.new_block({
    kind = "status_notice",
    surface = "notice",
    collapsed_by_default = true,
    lines = {
      shared.markdown_heading(3, "Image Generation", { foldable = true }),
      string.format("- Result: %s", result),
    },
    protocol = shared.protocol_payload(item),
  })
end

local function summarize_review_mode(item)
  local entered = item.type == "enteredReviewMode"
  return shared.new_block({
    kind = "review_mode",
    surface = "review",
    collapsed_by_default = true,
    lines = {
      shared.markdown_heading(3, "Review Mode", { foldable = true }),
      string.format("- State: `%s`", entered and "entered" or "exited"),
      string.format("- Review: `%s`", shared.value_or(item.review, "unknown")),
    },
    protocol = shared.protocol_payload(item),
  })
end

local function summarize_context_compaction(item)
  return shared.new_block({
    kind = "status_notice",
    surface = "notice",
    collapsed_by_default = true,
    lines = {
      shared.markdown_heading(3, "Context Compaction", { foldable = true }),
      "- Codex compacted the conversation history for this thread.",
    },
    protocol = shared.protocol_payload(item),
  })
end

local function summarize_unknown_item(item)
  return shared.new_block({
    kind = "unknown_item",
    surface = "notice",
    collapsed_by_default = true,
    lines = {
      shared.markdown_heading(3, "Protocol Notice", { foldable = true }),
      string.format("- Item `%s` is available in raw protocol logs.", shared.value_or(item.type, "unknown")),
    },
    protocol = shared.protocol_payload(item),
  })
end

function M.summarize(item)
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

return M
