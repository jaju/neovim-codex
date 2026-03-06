local selectors = require("neovim_codex.core.selectors")

local M = {}

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

local function user_content_lines(content)
  local lines = {}

  if not content or #content == 0 then
    return { "_Empty message._" }
  end

  for _, item in ipairs(content) do
    if item.type == "text" then
      push_text(lines, item.text)
    elseif item.type == "skill" then
      lines[#lines + 1] = string.format("- Skill `%s` (`%s`)", value_or(item.name, "skill"), value_or(item.path, ""))
    elseif item.type == "mention" then
      lines[#lines + 1] = string.format("- Mention `%s` (`%s`)", value_or(item.name, "mention"), value_or(item.path, ""))
    elseif item.type == "image" then
      lines[#lines + 1] = string.format("- Image `%s`", value_or(item.url, ""))
    elseif item.type == "localImage" then
      lines[#lines + 1] = string.format("- Local image `%s`", value_or(item.path, ""))
    else
      lines[#lines + 1] = string.format("- %s", value_or(item.type, "unknown item"))
    end
  end

  if #lines == 0 then
    return { "_Empty message._" }
  end

  return lines
end

local function command_kind(item)
  local command = string.lower(value_or(item.command, ""))
  local context_patterns = {
    ".codex/skills",
    "agents.md",
    ".agent-kit",
    "docs/knowledge",
    "prompt-control",
    "topics.agent.tsv",
  }
  local inspection_patterns = {
    "sed -n",
    " cat ",
    " rg ",
    " rg --files",
    " find ",
    " fd ",
    " ls ",
    " pwd",
    " test ",
    " head ",
    " tail ",
    " stat ",
  }

  for _, pattern in ipairs(context_patterns) do
    if command:find(pattern, 1, true) then
      return "context"
    end
  end

  if value_or(item.status, "unknown") == "completed" then
    for _, pattern in ipairs(inspection_patterns) do
      if command:find(pattern, 1, true) then
        return "inspection"
      end
    end
  end

  return "detail"
end

local function summarize_command(item)
  local kind = command_kind(item)
  if kind == "context" then
    return {
      kind = "activity_summary",
      collapsed_by_default = true,
      lines = {
        "#### Activity",
        "- Loaded local instructions and workspace context.",
      },
    }
  end

  if kind == "inspection" then
    return {
      kind = "activity_summary",
      collapsed_by_default = true,
      lines = {
        "#### Activity",
        "- Inspected local files and workspace state.",
      },
    }
  end

  local lines = {
    string.format("#### Command · `%s`", value_or(item.status, "unknown")),
    "```sh",
    value_or(item.command, ""),
    "```",
  }

  local output_lines = split_lines(item.aggregatedOutput)
  if #output_lines > 0 then
    lines[#lines + 1] = "```text"
    local preview_limit = 6
    for index = 1, math.min(#output_lines, preview_limit) do
      lines[#lines + 1] = output_lines[index]
    end
    if #output_lines > preview_limit then
      lines[#lines + 1] = string.format("... (%d more lines)", #output_lines - preview_limit)
    end
    lines[#lines + 1] = "```"
  end

  return {
    kind = "command_detail",
    collapsed_by_default = true,
    lines = lines,
  }
end

local function summarize_file_changes(item)
  local changes = item.changes or {}
  local lines = {
    string.format("#### File changes · `%s`", value_or(item.status, "unknown")),
  }

  if #changes == 0 then
    lines[#lines + 1] = "- No file details were reported."
  else
    for index, change in ipairs(changes) do
      local path = value_or(change.path or change.filePath or change.uri, string.format("change-%d", index))
      local status = value_or(change.changeType or change.kind or change.status, "changed")
      lines[#lines + 1] = string.format("- `%s` · %s", path, status)
    end
  end

  return {
    kind = "file_change_summary",
    collapsed_by_default = true,
    lines = lines,
  }
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

  return {
    kind = "turn_boundary",
    collapsed_by_default = false,
    lines = lines,
  }
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
    add_block(doc.blocks, {
      id = string.format("thread:%s:title", thread.id),
      kind = "metadata",
      lines = {
        opts.title,
        string.format("_Thread `%s`_", thread.id),
      },
    })
  end

  local turns = selectors.list_turns(thread)
  if #turns == 0 then
    add_block(doc.blocks, {
      id = string.format("thread:%s:empty", thread.id),
      kind = "metadata",
      lines = {
        "## Ready",
        "- The thread has no turns yet.",
        "- Write in the composer and send when ready.",
      },
    })
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
        turn_id = turn.id,
        lines = { "_Waiting for items..._" },
      })
    else
      for _, item in ipairs(items) do
        local block = nil

        if item.type == "userMessage" then
          block = {
            kind = "user_message",
            collapsed_by_default = false,
            lines = vim.list_extend({ "### You" }, user_content_lines(item.content)),
          }
        elseif item.type == "agentMessage" then
          local text = present(item.text) and item.text ~= "" and item.text or "_Streaming response..._"
          block = {
            kind = "assistant_message",
            collapsed_by_default = false,
            lines = vim.list_extend({ "### Codex" }, split_lines(text)),
          }
        elseif item.type == "plan" and present(item.text) then
          block = {
            kind = "plan",
            collapsed_by_default = false,
            lines = vim.list_extend({ "#### Plan" }, split_lines(item.text)),
          }
        elseif item.type == "reasoning" and item.summary and #item.summary > 0 then
          local lines = { "#### Reasoning summary" }
          for _, summary in ipairs(item.summary) do
            lines[#lines + 1] = string.format("- %s", summary)
          end
          block = {
            kind = "reasoning_summary",
            collapsed_by_default = true,
            lines = lines,
          }
        elseif item.type == "commandExecution" then
          block = summarize_command(item)
        elseif item.type == "fileChange" then
          block = summarize_file_changes(item)
        end

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
    return project_thread(thread, opts)
  end

  return {
    footer = string.format("connection %s", value_or(state.connection and state.connection.status, "unknown")),
    blocks = {
      {
        id = "placeholder",
        kind = "metadata",
        lines = {
          "## Ready",
          "- Open or resume a thread, then start composing below.",
          "- `:CodexThreadNew` creates a fresh thread.",
          "- `:CodexThreads` resumes a stored thread.",
        },
      },
    },
  }
end

function M.project_thread(thread, opts)
  return project_thread(thread, opts)
end

return M
