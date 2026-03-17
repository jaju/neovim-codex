local M = {}

local function dispatch(store, event)
  store:dispatch(event)
end

local function turn_event(params)
  return {
    type = "turn_received",
    thread_id = params.threadId,
    turn = params.turn,
    replace_items = false,
  }
end

local function item_event(params)
  return {
    type = "item_received",
    thread_id = params.threadId,
    turn_id = params.turnId,
    item = params.item,
  }
end

local HANDLERS = {
  initialized = function() end,
  ["thread/started"] = function(store, params)
    dispatch(store, {
      type = "thread_received",
      thread = params.thread,
      replace_turns = false,
      activate = false,
    })
  end,
  ["thread/status/changed"] = function(store, params)
    dispatch(store, {
      type = "thread_status_changed",
      thread_id = params.threadId,
      status = params.status,
    })
  end,
  ["thread/archived"] = function(store, params)
    dispatch(store, { type = "thread_archived", thread_id = params.threadId })
  end,
  ["thread/name/updated"] = function(store, params)
    dispatch(store, {
      type = "thread_name_updated",
      thread_id = params.threadId,
      thread_name = params.threadName,
    })
  end,
  ["thread/unarchived"] = function(store, params)
    dispatch(store, { type = "thread_unarchived", thread_id = params.threadId })
  end,
  ["thread/closed"] = function(store, params)
    dispatch(store, { type = "thread_closed", thread_id = params.threadId })
  end,
  ["turn/started"] = function(store, params)
    dispatch(store, turn_event(params))
  end,
  ["turn/completed"] = function(store, params)
    dispatch(store, turn_event(params))
  end,
  ["thread/tokenUsage/updated"] = function(store, params)
    dispatch(store, {
      type = "thread_token_usage_updated",
      thread_id = params.threadId,
      turn_id = params.turnId,
      token_usage = params.tokenUsage,
    })
  end,
  ["turn/diff/updated"] = function(store, params)
    dispatch(store, {
      type = "turn_diff_updated",
      thread_id = params.threadId,
      turn_id = params.turnId,
      diff = params.diff,
    })
  end,
  ["turn/plan/updated"] = function(store, params)
    dispatch(store, {
      type = "turn_plan_updated",
      thread_id = params.threadId,
      turn_id = params.turnId,
      plan = params.plan,
    })
  end,
  ["item/started"] = function(store, params)
    dispatch(store, item_event(params))
  end,
  ["item/completed"] = function(store, params)
    dispatch(store, item_event(params))
  end,
  ["item/agentMessage/delta"] = function(store, params)
    dispatch(store, {
      type = "agent_message_delta",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      delta = params.delta,
    })
  end,
  ["item/plan/delta"] = function(store, params)
    dispatch(store, {
      type = "plan_delta",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      delta = params.delta,
    })
  end,
  ["item/reasoning/summaryPartAdded"] = function(store, params)
    dispatch(store, {
      type = "reasoning_summary_part_added",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      summary_index = params.summaryIndex,
    })
  end,
  ["item/reasoning/summaryTextDelta"] = function(store, params)
    dispatch(store, {
      type = "reasoning_summary_text_delta",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      summary_index = params.summaryIndex,
      delta = params.delta,
    })
  end,
  ["item/reasoning/textDelta"] = function(store, params)
    dispatch(store, {
      type = "reasoning_text_delta",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      content_index = params.contentIndex,
      delta = params.delta,
    })
  end,
  ["item/commandExecution/outputDelta"] = function(store, params)
    dispatch(store, {
      type = "command_execution_output_delta",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      delta = params.delta,
    })
  end,
  ["serverRequest/resolved"] = function(store, params)
    dispatch(store, {
      type = "server_request_resolved",
      thread_id = params.threadId,
      request_id = params.requestId,
    })
  end,
}

function M.handle(store, message)
  local handler = HANDLERS[message.method]
  if not handler then
    return false
  end

  handler(store, message.params or {})
  return true
end

return M
