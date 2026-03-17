local selectors = require("neovim_codex.core.selectors")
local items = require("neovim_codex.nvim.chat.document.items")
local shared = require("neovim_codex.nvim.chat.document.shared")
local thread_identity = require("neovim_codex.nvim.thread_identity")

local M = {}

local IN_PROGRESS_ITEM_TYPES = {
  commandExecution = true,
  fileChange = true,
  mcpToolCall = true,
  dynamicToolCall = true,
  collabAgentToolCall = true,
}

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

local function in_progress_item_count(turn)
  local count = 0
  for _, item in ipairs(selectors.list_items(turn)) do
    if IN_PROGRESS_ITEM_TYPES[item.type] and shared.value_or(item.status, "") == "inProgress" then
      count = count + 1
    end
  end
  return count
end

local function turn_title(turn, index)
  local current_items = selectors.list_items(turn)

  for _, item in ipairs(current_items) do
    if item.type == "userMessage" then
      local snippet = shared.plain_snippet(shared.user_message_text(item.content), 72)
      if snippet then
        return string.format("## %s", snippet)
      end
    end
  end

  for _, item in ipairs(current_items) do
    if item.type == "plan" then
      local snippet = shared.plain_snippet(item.text, 72)
      if snippet then
        return string.format("## %s", snippet)
      end
    end
    if item.type == "agentMessage" then
      local snippet = shared.plain_snippet(item.text, 72)
      if snippet then
        return string.format("## %s", snippet)
      end
    end
  end

  return string.format("## Turn %d", index)
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

  local workbench_summary
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

  local footer = string.format("thread %s · %s · %s", short_id, title, table.concat(trailing_parts, " · "))
  local segments = {
    { text = string.format("thread %s", short_id), highlight = "NeovimCodexChatFooterMeta" },
    { text = " · ", highlight = "NeovimCodexChatFooterMeta" },
    { text = title, highlight = "NeovimCodexChatFooterThread" },
    { text = string.format(" · %s", table.concat(trailing_parts, " · ")), highlight = "NeovimCodexChatFooterMeta" },
  }

  return footer, segments
end

local function turn_heading(index, turn)
  local lines = {}
  if index > 1 then
    lines[#lines + 1] = "---"
  end

  lines[#lines + 1] = turn_title(turn, index)

  local details = { string.format("turn %d", index) }
  if shared.present(turn.status) and turn.status ~= "completed" then
    details[#details + 1] = string.format("status `%s`", turn.status)
  end
  if shared.present(turn.error) and shared.present(turn.error.message) then
    details[#details + 1] = string.format("error: %s", turn.error.message)
  end
  if #details > 0 then
    lines[#lines + 1] = string.format("_%s_", table.concat(details, " · "))
  end

  return shared.new_block({
    kind = "turn_boundary",
    surface = "turn_heading",
    collapsed_by_default = false,
    lines = lines,
  })
end

function M.project(thread, opts)
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
    shared.add_block(doc.blocks, shared.new_block({
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
    shared.add_block(doc.blocks, shared.new_block({
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
    shared.add_block(doc.blocks, heading)

    local turn_items = list_turn_items(turn)
    if #turn_items == 0 then
      shared.add_block(doc.blocks, {
        id = string.format("turn:%s:pending", turn.id),
        kind = "metadata",
        surface = "notice",
        turn_id = turn.id,
        collapsed_by_default = false,
        header_lines = 1,
        lines = { "_Waiting for items..._" },
      })
    else
      for _, item in ipairs(turn_items) do
        local block = items.summarize(item)
        if block then
          block.id = string.format("turn:%s:item:%s", turn.id, item.id or item.type)
          block.turn_id = turn.id
          block.item_id = item.id
          shared.add_block(doc.blocks, block)
        end
      end
    end
  end

  return doc
end

return M
