local selectors = require("neovim_codex.core.selectors")

local M = {}

local function present(value)
  return value ~= nil and value ~= vim.NIL
end

local function add_text_block(lines, prefix, text)
  if not present(text) or text == "" then
    lines[#lines + 1] = prefix
    return
  end

  for _, segment in ipairs(vim.split(tostring(text), "\n", { plain = true })) do
    lines[#lines + 1] = prefix .. segment
  end
end

local function render_user_input(lines, content)
  if not content or #content == 0 then
    lines[#lines + 1] = "  (empty user input)"
    return
  end

  for _, item in ipairs(content) do
    if item.type == "text" then
      add_text_block(lines, "  ", item.text)
    elseif item.type == "skill" then
      lines[#lines + 1] = string.format("  [$skill] %s (%s)", present(item.name) and item.name or "skill", present(item.path) and item.path or "")
    elseif item.type == "mention" then
      lines[#lines + 1] = string.format("  [@app] %s (%s)", present(item.name) and item.name or "mention", present(item.path) and item.path or "")
    elseif item.type == "image" then
      lines[#lines + 1] = string.format("  [image] %s", present(item.url) and item.url or "")
    elseif item.type == "localImage" then
      lines[#lines + 1] = string.format("  [local image] %s", present(item.path) and item.path or "")
    else
      lines[#lines + 1] = string.format("  [%s]", item.type or "unknown")
    end
  end
end

local function render_item(lines, item)
  if item.type == "userMessage" then
    lines[#lines + 1] = "User"
    render_user_input(lines, item.content)
  elseif item.type == "agentMessage" then
    lines[#lines + 1] = "Codex"
    add_text_block(lines, "  ", item.text)
  elseif item.type == "plan" then
    lines[#lines + 1] = "Plan"
    add_text_block(lines, "  ", item.text)
  elseif item.type == "reasoning" then
    lines[#lines + 1] = "Reasoning"
    if item.summary and #item.summary > 0 then
      for _, summary in ipairs(item.summary) do
        lines[#lines + 1] = string.format("  - %s", summary)
      end
    else
      lines[#lines + 1] = "  (streaming reasoning)"
    end
  elseif item.type == "commandExecution" then
    lines[#lines + 1] = string.format("Command [%s]", item.status or "unknown")
    lines[#lines + 1] = string.format("  %s", item.command or "")
    if present(item.aggregatedOutput) and item.aggregatedOutput ~= "" then
      add_text_block(lines, "  | ", item.aggregatedOutput)
    end
  elseif item.type == "fileChange" then
    lines[#lines + 1] = string.format("File change [%s]", item.status or "unknown")
    lines[#lines + 1] = string.format("  changes: %d", #(item.changes or {}))
  else
    lines[#lines + 1] = string.format("%s", item.type or "item")
  end
end

function M.render_placeholder(state)
  local lines = {
    "# Codex Chat",
    "",
    string.format("connection: %s", state.connection.status),
    "",
    "No active thread.",
    "Type in the prompt below and press <Enter> to start a new conversation.",
    "Use :CodexThreads to resume a stored thread.",
  }

  if state.connection.last_error then
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("last_error: %s", state.connection.last_error)
  end

  return {
    lines = lines,
    turn_lines = {},
  }
end

function M.render_thread(thread, opts)
  opts = opts or {}
  local title = opts.title or "# Codex Chat"
  local lines = {
    title,
    "",
    string.format("thread: %s", thread.id),
    string.format("status: %s", thread.status and thread.status.type or "unknown"),
    string.format("cwd: %s", present(thread.cwd) and thread.cwd or "-"),
    string.format("name: %s", present(thread.name) and thread.name or "-"),
    string.format("preview: %s", present(thread.preview) and thread.preview ~= "" and thread.preview or "-"),
    "",
  }
  local turn_lines = {}
  local turns = selectors.list_turns(thread)

  if #turns == 0 then
    lines[#lines + 1] = "No turns yet."
    return {
      lines = lines,
      turn_lines = turn_lines,
    }
  end

  for index, turn in ipairs(turns) do
    turn_lines[#turn_lines + 1] = #lines + 1
    lines[#lines + 1] = string.format("Turn %d  [%s]", index, turn.status or "unknown")
    if present(turn.error) and turn.error.message then
      lines[#lines + 1] = string.format("  error: %s", turn.error.message)
    end

    local items = selectors.list_items(turn)
    if #items == 0 then
      lines[#lines + 1] = "  (no items yet)"
    else
      for _, item in ipairs(items) do
        render_item(lines, item)
      end
    end

    if index < #turns then
      lines[#lines + 1] = ""
    end
  end

  return {
    lines = lines,
    turn_lines = turn_lines,
  }
end

return M
