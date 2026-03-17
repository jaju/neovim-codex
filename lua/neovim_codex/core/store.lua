local draft_state = require("neovim_codex.core.store_draft")

local M = {}

local function merge_text_item(current, merged)
  if draft_state.present(current.text) and merged.text == "" then
    merged.text = current.text
  elseif not draft_state.present(merged.text) then
    merged.text = draft_state.present(current.text) and current.text or ""
  end
end

local function merge_item(draft, thread_id, turn_id, item)
  local current = draft_state.read_item(draft, thread_id, turn_id, item.id) or {}
  local merged = draft_state.deep_copy(item)

  if item.type == "agentMessage" or item.type == "plan" then
    merge_text_item(current, merged)
  elseif item.type == "reasoning" then
    if type(merged.summary) ~= "table" or #merged.summary == 0 then
      merged.summary = type(current.summary) == "table" and draft_state.deep_copy(current.summary) or {}
    end
    if type(merged.content) ~= "table" or #merged.content == 0 then
      merged.content = type(current.content) == "table" and draft_state.deep_copy(current.content) or {}
    end
  elseif item.type == "commandExecution" then
    if not draft_state.present(merged.aggregatedOutput) then
      merged.aggregatedOutput = draft_state.present(current.aggregatedOutput) and current.aggregatedOutput or ""
    end
    if type(merged.commandActions) ~= "table" or #merged.commandActions == 0 then
      merged.commandActions = type(current.commandActions) == "table" and draft_state.deep_copy(current.commandActions) or {}
    end
  end

  return draft_state.replace_item(draft, thread_id, turn_id, merged)
end

local function merge_turn(draft, thread_id, turn, opts)
  opts = opts or {}
  local current = draft_state.ensure_turn(draft, thread_id, turn.id)
  current.status = draft_state.present(turn.status) and turn.status or current.status
  current.error = draft_state.present(turn.error) and draft_state.deep_copy(turn.error) or nil

  if opts.replace_items then
    draft_state.reset_turn_items(draft, thread_id, turn.id)
  end

  if turn.items then
    for _, item in ipairs(turn.items) do
      merge_item(draft, thread_id, turn.id, item)
    end
  end

  return current
end

local function set_thread_runtime(draft, thread_id, runtime)
  local thread = draft_state.touch_thread(draft, thread_id)
  thread.runtime = draft_state.deep_copy(runtime or {})
  return thread
end

local function merge_thread(draft, thread_data, opts)
  opts = opts or {}
  local thread = draft_state.touch_thread(draft, thread_data.id)

  if draft_state.present(thread_data.preview) then
    thread.preview = thread_data.preview
  end
  if type(thread_data.ephemeral) == "boolean" then
    thread.ephemeral = thread_data.ephemeral
  end
  if draft_state.present(thread_data.modelProvider) then
    thread.modelProvider = thread_data.modelProvider
  end
  if draft_state.present(thread_data.createdAt) then
    thread.createdAt = thread_data.createdAt
  end
  if draft_state.present(thread_data.updatedAt) then
    thread.updatedAt = thread_data.updatedAt
  end
  if draft_state.present(thread_data.status) then
    thread.status = draft_state.deep_copy(thread_data.status)
  end
  if draft_state.present(thread_data.path) then
    thread.path = thread_data.path
  end
  if draft_state.present(thread_data.cwd) then
    thread.cwd = thread_data.cwd
  end
  if draft_state.present(thread_data.cliVersion) then
    thread.cliVersion = thread_data.cliVersion
  end
  if draft_state.present(thread_data.source) then
    thread.source = draft_state.deep_copy(thread_data.source)
  end
  if draft_state.present(thread_data.agentNickname) then
    thread.agentNickname = thread_data.agentNickname
  end
  if draft_state.present(thread_data.agentRole) then
    thread.agentRole = thread_data.agentRole
  end
  if draft_state.present(thread_data.gitInfo) then
    thread.gitInfo = draft_state.deep_copy(thread_data.gitInfo)
  end
  if draft_state.present(thread_data.name) then
    thread.name = thread_data.name
  end
  if opts.closed ~= nil then
    thread.closed = opts.closed
  end
  if opts.archived ~= nil then
    thread.archived = opts.archived
  end

  if opts.replace_turns then
    draft_state.reset_thread_turns(draft, thread_data.id)
    for _, turn in ipairs(thread_data.turns or {}) do
      merge_turn(draft, thread_data.id, turn, { replace_items = true })
    end
  end

  if opts.activate then
    draft_state.touch_threads(draft).active_id = thread.id
  end

  return thread
end

local function reducer(state, event)
  local draft = draft_state.new_draft(state)

  if event.type == "transport_started" then
    local connection = draft_state.touch_connection(draft)
    connection.status = "initializing"
    connection.pid = event.pid
    connection.last_error = nil
    connection.stop_requested = false
  elseif event.type == "transport_stop_requested" then
    local connection = draft_state.touch_connection(draft)
    connection.status = "stopping"
    connection.stop_requested = true
  elseif event.type == "transport_stopped" then
    local connection = draft_state.touch_connection(draft)
    connection.status = "stopped"
    connection.pid = nil
    connection.initialized = false
    connection.user_agent = nil
    connection.stop_requested = false
    draft_state.clear_server_requests(draft)
    if event.expected then
      connection.last_error = nil
    else
      connection.last_error = event.reason
    end
  elseif event.type == "initialize_requested" then
    draft_state.touch_connection(draft).status = "initializing"
  elseif event.type == "initialize_succeeded" then
    local connection = draft_state.touch_connection(draft)
    connection.status = "ready"
    connection.initialized = true
    connection.user_agent = event.user_agent
    connection.last_error = nil
  elseif event.type == "protocol_error" then
    local connection = draft_state.touch_connection(draft)
    connection.status = "error"
    connection.last_error = event.message
  elseif event.type == "transport_error" then
    local connection = draft_state.touch_connection(draft)
    connection.status = "error"
    connection.last_error = event.message
  elseif event.type == "stderr_received" then
    draft_state.touch_connection(draft).last_stderr = event.message
  elseif event.type == "thread_received" then
    merge_thread(draft, event.thread, {
      activate = event.activate,
      replace_turns = event.replace_turns,
      archived = event.archived,
      closed = event.closed,
    })
  elseif event.type == "threads_list_received" then
    local ordered_ids = {}
    for _, thread in ipairs(event.threads or {}) do
      merge_thread(draft, thread, { replace_turns = false })
      ordered_ids[#ordered_ids + 1] = thread.id
    end
    local threads = draft_state.touch_threads(draft)
    threads.order = draft_state.replace_order(threads.order, ordered_ids)
    draft.threads_order_touched = true
    threads.next_cursor = event.next_cursor
  elseif event.type == "thread_activated" then
    draft_state.touch_threads(draft).active_id = event.thread_id
    if event.thread_id then
      draft_state.touch_thread(draft, event.thread_id)
    end
  elseif event.type == "thread_status_changed" then
    draft_state.touch_thread(draft, event.thread_id).status = draft_state.deep_copy(event.status)
  elseif event.type == "thread_archived" then
    draft_state.touch_thread(draft, event.thread_id).archived = true
  elseif event.type == "thread_name_updated" then
    draft_state.touch_thread(draft, event.thread_id).name = event.thread_name
  elseif event.type == "thread_unarchived" then
    draft_state.touch_thread(draft, event.thread_id).archived = false
  elseif event.type == "thread_closed" then
    draft_state.touch_thread(draft, event.thread_id).closed = true
  elseif event.type == "thread_runtime_updated" then
    set_thread_runtime(draft, event.thread_id, event.runtime)
  elseif event.type == "turn_received" then
    merge_turn(draft, event.thread_id, event.turn, { replace_items = event.replace_items })
  elseif event.type == "turn_diff_updated" then
    draft_state.ensure_turn(draft, event.thread_id, event.turn_id).diff = draft_state.deep_copy(event.diff)
  elseif event.type == "turn_plan_updated" then
    draft_state.ensure_turn(draft, event.thread_id, event.turn_id).plan = draft_state.deep_copy(event.plan)
  elseif event.type == "thread_token_usage_updated" then
    draft_state.touch_thread(draft, event.thread_id).tokenUsage = {
      turnId = event.turn_id,
      tokenUsage = draft_state.deep_copy(event.token_usage),
    }
  elseif event.type == "item_received" then
    merge_item(draft, event.thread_id, event.turn_id, event.item)
  elseif event.type == "agent_message_delta" then
    local item = draft_state.ensure_item(draft, event.thread_id, event.turn_id, event.item_id, {
      type = "agentMessage",
      text = "",
      phase = nil,
    })
    item.text = (draft_state.present(item.text) and item.text or "") .. event.delta
  elseif event.type == "plan_delta" then
    local item = draft_state.ensure_item(draft, event.thread_id, event.turn_id, event.item_id, {
      type = "plan",
      text = "",
    })
    item.text = (draft_state.present(item.text) and item.text or "") .. event.delta
  elseif event.type == "reasoning_summary_part_added" then
    local item = draft_state.ensure_item(draft, event.thread_id, event.turn_id, event.item_id, {
      type = "reasoning",
      summary = {},
      content = {},
    })
    if type(item.summary) ~= "table" then
      item.summary = {}
    else
      item.summary = draft_state.copy_array(item.summary)
    end
    draft_state.ensure_array_slot(item.summary, (tonumber(event.summary_index) or 0) + 1)
  elseif event.type == "reasoning_summary_text_delta" then
    local item = draft_state.ensure_item(draft, event.thread_id, event.turn_id, event.item_id, {
      type = "reasoning",
      summary = {},
      content = {},
    })
    if type(item.summary) ~= "table" then
      item.summary = {}
    else
      item.summary = draft_state.copy_array(item.summary)
    end
    local index = (tonumber(event.summary_index) or 0) + 1
    draft_state.ensure_array_slot(item.summary, index)
    item.summary[index] = item.summary[index] .. event.delta
  elseif event.type == "reasoning_text_delta" then
    local item = draft_state.ensure_item(draft, event.thread_id, event.turn_id, event.item_id, {
      type = "reasoning",
      summary = {},
      content = {},
    })
    if type(item.content) ~= "table" then
      item.content = {}
    else
      item.content = draft_state.copy_array(item.content)
    end
    local index = (tonumber(event.content_index) or 0) + 1
    draft_state.ensure_array_slot(item.content, index)
    item.content[index] = item.content[index] .. event.delta
  elseif event.type == "command_execution_output_delta" then
    local item = draft_state.ensure_item(draft, event.thread_id, event.turn_id, event.item_id, {
      type = "commandExecution",
      command = "",
      cwd = nil,
      processId = nil,
      status = "inProgress",
      commandActions = {},
      aggregatedOutput = "",
      exitCode = nil,
      durationMs = nil,
    })
    item.aggregatedOutput = (draft_state.present(item.aggregatedOutput) and item.aggregatedOutput or "") .. event.delta
  elseif event.type == "server_request_received" then
    draft_state.upsert_server_request(draft, event.request)
  elseif event.type == "server_request_response_sent" then
    draft_state.mark_server_request_responded(draft, event.request_id, event.response)
  elseif event.type == "server_request_resolved" then
    draft_state.resolve_server_request(draft, event.request_id)
  elseif event.type == "workbench_fragment_added" then
    draft_state.add_workbench_fragment(draft, event.thread_id, event.fragment)
  elseif event.type == "workbench_fragment_removed" then
    draft_state.remove_workbench_fragment(draft, event.thread_id, event.fragment_id)
  elseif event.type == "workbench_fragment_parked" then
    draft_state.set_workbench_fragment_parked(draft, event.thread_id, event.fragment_id, event.parked)
  elseif event.type == "workbench_active_cleared" then
    draft_state.clear_active_workbench_fragments(draft, event.thread_id)
  elseif event.type == "workbench_cleared" then
    draft_state.clear_workbench(draft, event.thread_id)
  elseif event.type == "workbench_message_updated" then
    draft_state.set_workbench_message(draft, event.thread_id, event.message)
  end

  if event.log_entry then
    draft_state.append_log(draft_state.touch_logs(draft), draft.next_state.settings.max_log_entries, event.log_entry)
  end

  return draft.next_state
end

function M.new(opts)
  opts = opts or {}

  local state = {
    connection = {
      status = "stopped",
      pid = nil,
      initialized = false,
      user_agent = nil,
      last_error = nil,
      last_stderr = nil,
      stop_requested = false,
    },
    threads = {
      active_id = nil,
      order = {},
      by_id = {},
      next_cursor = nil,
    },
    server_requests = {
      active_id = nil,
      order = {},
      by_id = {},
    },
    workbench = {
      by_thread_id = {},
    },
    logs = {},
    settings = {
      max_log_entries = opts.max_log_entries or 400,
    },
  }

  local subscribers = {}
  local store = {}

  function store:get_state()
    return state
  end

  function store:dispatch(event)
    if not event.log_entry and event.type ~= "state_snapshot" then
      event.log_entry = {
        at = draft_state.now_iso(),
        kind = "state",
        direction = "internal",
        body = event.type,
      }
    end
    state = reducer(state, event)
    for _, callback in ipairs(subscribers) do
      callback(state, event)
    end
  end

  function store:subscribe(callback)
    subscribers[#subscribers + 1] = callback
    return function()
      for index, candidate in ipairs(subscribers) do
        if candidate == callback then
          table.remove(subscribers, index)
          break
        end
      end
    end
  end

  return store
end

return M
