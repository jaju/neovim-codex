local M = {}

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function clone(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for key, item in pairs(value) do
    out[key] = clone(item)
  end
  return out
end

local function present(value)
  return value ~= nil and type(value) ~= "userdata"
end

local function request_key(value)
  return tostring(value)
end

local function append_log(state, entry)
  local logs = state.logs
  logs[#logs + 1] = entry
  local overflow = #logs - state.settings.max_log_entries
  if overflow > 0 then
    for _ = 1, overflow do
      table.remove(logs, 1)
    end
  end
end

local function upsert_order(order, id)
  for _, current in ipairs(order) do
    if current == id then
      return
    end
  end
  order[#order + 1] = id
end

local function remove_order(order, id)
  for index, current in ipairs(order or {}) do
    if current == id then
      table.remove(order, index)
      return
    end
  end
end

local function replace_order(existing_order, preferred_ids)
  local seen = {}
  local next_order = {}

  for _, id in ipairs(preferred_ids or {}) do
    if id and not seen[id] then
      next_order[#next_order + 1] = id
      seen[id] = true
    end
  end

  for _, id in ipairs(existing_order or {}) do
    if id and not seen[id] then
      next_order[#next_order + 1] = id
      seen[id] = true
    end
  end

  return next_order
end

local function ensure_thread(state, thread_id)
  local thread = state.threads.by_id[thread_id]
  if thread then
    return thread
  end

  thread = {
    id = thread_id,
    preview = "",
    ephemeral = false,
    modelProvider = nil,
    createdAt = nil,
    updatedAt = nil,
    status = { type = "notLoaded" },
    path = nil,
    cwd = nil,
    cliVersion = nil,
    source = nil,
    agentNickname = nil,
    agentRole = nil,
    gitInfo = nil,
    name = nil,
    archived = false,
    closed = false,
    turns_order = {},
    turns_by_id = {},
  }

  state.threads.by_id[thread_id] = thread
  upsert_order(state.threads.order, thread_id)
  return thread
end

local function ensure_turn(thread, turn_id)
  local turn = thread.turns_by_id[turn_id]
  if turn then
    return turn
  end

  turn = {
    id = turn_id,
    status = "pending",
    error = nil,
    items_order = {},
    items_by_id = {},
    diff = nil,
    plan = nil,
  }

  thread.turns_by_id[turn_id] = turn
  upsert_order(thread.turns_order, turn_id)
  return turn
end

local function merge_item(turn, item)
  local current = turn.items_by_id[item.id] or {}
  turn.items_by_id[item.id] = clone(item)
  local merged = turn.items_by_id[item.id]

  if item.type == "agentMessage" then
    if present(current.text) and item.text == "" then
      merged.text = current.text
    elseif not present(item.text) then
      merged.text = present(current.text) and current.text or ""
    end
  elseif item.type == "plan" then
    if present(current.text) and item.text == "" then
      merged.text = current.text
    elseif not present(item.text) then
      merged.text = present(current.text) and current.text or ""
    end
  elseif item.type == "reasoning" then
    if type(merged.summary) ~= "table" or #merged.summary == 0 then
      merged.summary = type(current.summary) == "table" and clone(current.summary) or {}
    end
    if type(merged.content) ~= "table" or #merged.content == 0 then
      merged.content = type(current.content) == "table" and clone(current.content) or {}
    end
  elseif item.type == "commandExecution" then
    if not present(merged.aggregatedOutput) then
      merged.aggregatedOutput = present(current.aggregatedOutput) and current.aggregatedOutput or ""
    end
    if type(merged.commandActions) ~= "table" or #merged.commandActions == 0 then
      merged.commandActions = type(current.commandActions) == "table" and clone(current.commandActions) or {}
    end
  end

  upsert_order(turn.items_order, item.id)
  return merged
end

local function ensure_item(turn, item_id, defaults)
  local item = turn.items_by_id[item_id]
  if item then
    return item
  end

  item = clone(defaults or {})
  item.id = item_id
  turn.items_by_id[item_id] = item
  upsert_order(turn.items_order, item_id)
  return item
end

local function ensure_array_slot(list, index)
  while #list < index do
    list[#list + 1] = ""
  end

  if not present(list[index]) then
    list[index] = ""
  end
end

local function merge_turn(thread, turn, opts)
  opts = opts or {}
  local current = ensure_turn(thread, turn.id)
  current.status = present(turn.status) and turn.status or current.status
  current.error = present(turn.error) and clone(turn.error) or nil

  if opts.replace_items then
    current.items_order = {}
    current.items_by_id = {}
  end

  if turn.items then
    for _, item in ipairs(turn.items) do
      merge_item(current, item)
    end
  end

  return current
end

local function merge_thread(state, thread_data, opts)
  opts = opts or {}
  local thread = ensure_thread(state, thread_data.id)

  if present(thread_data.preview) then
    thread.preview = thread_data.preview
  end
  if type(thread_data.ephemeral) == "boolean" then
    thread.ephemeral = thread_data.ephemeral
  end
  if present(thread_data.modelProvider) then
    thread.modelProvider = thread_data.modelProvider
  end
  if present(thread_data.createdAt) then
    thread.createdAt = thread_data.createdAt
  end
  if present(thread_data.updatedAt) then
    thread.updatedAt = thread_data.updatedAt
  end
  if present(thread_data.status) then
    thread.status = clone(thread_data.status)
  end
  if present(thread_data.path) then
    thread.path = thread_data.path
  end
  if present(thread_data.cwd) then
    thread.cwd = thread_data.cwd
  end
  if present(thread_data.cliVersion) then
    thread.cliVersion = thread_data.cliVersion
  end
  if present(thread_data.source) then
    thread.source = clone(thread_data.source)
  end
  if present(thread_data.agentNickname) then
    thread.agentNickname = thread_data.agentNickname
  end
  if present(thread_data.agentRole) then
    thread.agentRole = thread_data.agentRole
  end
  if present(thread_data.gitInfo) then
    thread.gitInfo = clone(thread_data.gitInfo)
  end
  if present(thread_data.name) then
    thread.name = thread_data.name
  end
  thread.closed = opts.closed ~= nil and opts.closed or thread.closed
  thread.archived = opts.archived ~= nil and opts.archived or thread.archived

  if opts.replace_turns then
    thread.turns_order = {}
    thread.turns_by_id = {}
    for _, turn in ipairs(thread_data.turns or {}) do
      merge_turn(thread, turn, { replace_items = true })
    end
  end

  if opts.activate then
    state.threads.active_id = thread.id
  end

  upsert_order(state.threads.order, thread.id)
  return thread
end

local function ensure_workbench(state, thread_id)
  if not thread_id then
    return nil
  end

  local workbench = state.workbench.by_thread_id[thread_id]
  if workbench then
    return workbench
  end

  workbench = {
    thread_id = thread_id,
    fragments_order = {},
    fragments_by_id = {},
    next_handle_seq = 1,
    draft_message = "",
    updated_at = nil,
  }

  state.workbench.by_thread_id[thread_id] = workbench
  return workbench
end

local function clear_server_requests(state)
  state.server_requests = {
    active_id = nil,
    order = {},
    by_id = {},
  }
end

local function upsert_server_request(state, message)
  local params = clone(message.params or {})
  local key = request_key(message.id)
  local request = state.server_requests.by_id[key] or {
    key = key,
    request_id = message.id,
    method = message.method,
    kind = message.method,
    thread_id = nil,
    turn_id = nil,
    item_id = nil,
    params = {},
    status = "pending",
    created_at = now_iso(),
    responded_at = nil,
    response = nil,
  }

  request.request_id = message.id
  request.method = message.method
  request.kind = message.method
  request.thread_id = params.threadId
  request.turn_id = params.turnId
  request.item_id = params.itemId
  request.params = params
  request.status = "pending"
  request.responded_at = nil
  request.response = nil

  state.server_requests.by_id[key] = request
  upsert_order(state.server_requests.order, key)
  state.server_requests.active_id = key
  return request
end

local function mark_server_request_responded(state, request_id, response)
  local key = request_key(request_id)
  local request = state.server_requests.by_id[key]
  if not request then
    return nil
  end

  request.status = "responding"
  request.responded_at = now_iso()
  request.response = clone(response)
  state.server_requests.active_id = key
  return request
end

local function resolve_server_request(state, request_id)
  local key = request_key(request_id)
  state.server_requests.by_id[key] = nil
  remove_order(state.server_requests.order, key)
  if state.server_requests.active_id == key then
    state.server_requests.active_id = state.server_requests.order[#state.server_requests.order]
  end
end

local function add_workbench_fragment(state, thread_id, fragment)
  local workbench = ensure_workbench(state, thread_id)
  if not workbench then
    return nil
  end

  local next_fragment = clone(fragment)
  if not next_fragment.handle then
    next_fragment.handle = string.format("f%d", workbench.next_handle_seq)
    workbench.next_handle_seq = workbench.next_handle_seq + 1
  end

  workbench.fragments_by_id[next_fragment.id] = next_fragment
  upsert_order(workbench.fragments_order, next_fragment.id)
  workbench.updated_at = now_iso()
  return workbench
end

local function remove_workbench_fragment(state, thread_id, fragment_id)
  local workbench = ensure_workbench(state, thread_id)
  if not workbench then
    return nil
  end

  workbench.fragments_by_id[fragment_id] = nil
  remove_order(workbench.fragments_order, fragment_id)
  workbench.updated_at = now_iso()
  return workbench
end

local function clear_workbench(state, thread_id)
  local workbench = ensure_workbench(state, thread_id)
  if not workbench then
    return nil
  end

  workbench.fragments_order = {}
  workbench.fragments_by_id = {}
  workbench.updated_at = now_iso()
  return workbench
end

local function set_workbench_message(state, thread_id, message)
  local workbench = ensure_workbench(state, thread_id)
  if not workbench then
    return nil
  end

  workbench.draft_message = tostring(message or "")
  workbench.updated_at = now_iso()
  return workbench
end

local function reducer(state, event)
  local next_state = clone(state)

  if event.type == "transport_started" then
    next_state.connection.status = "initializing"
    next_state.connection.pid = event.pid
    next_state.connection.last_error = nil
    next_state.connection.stop_requested = false
  elseif event.type == "transport_stop_requested" then
    next_state.connection.status = "stopping"
    next_state.connection.stop_requested = true
  elseif event.type == "transport_stopped" then
    next_state.connection.status = "stopped"
    next_state.connection.pid = nil
    next_state.connection.initialized = false
    next_state.connection.user_agent = nil
    next_state.connection.stop_requested = false
    clear_server_requests(next_state)
    if event.expected then
      next_state.connection.last_error = nil
    else
      next_state.connection.last_error = event.reason
    end
  elseif event.type == "initialize_requested" then
    next_state.connection.status = "initializing"
  elseif event.type == "initialize_succeeded" then
    next_state.connection.status = "ready"
    next_state.connection.initialized = true
    next_state.connection.user_agent = event.user_agent
    next_state.connection.last_error = nil
  elseif event.type == "protocol_error" then
    next_state.connection.status = "error"
    next_state.connection.last_error = event.message
  elseif event.type == "transport_error" then
    next_state.connection.status = "error"
    next_state.connection.last_error = event.message
  elseif event.type == "stderr_received" then
    next_state.connection.last_stderr = event.message
  elseif event.type == "thread_received" then
    merge_thread(next_state, event.thread, {
      activate = event.activate,
      replace_turns = event.replace_turns,
      archived = event.archived,
      closed = event.closed,
    })
  elseif event.type == "threads_list_received" then
    local ordered_ids = {}
    for _, thread in ipairs(event.threads or {}) do
      merge_thread(next_state, thread, { replace_turns = false })
      ordered_ids[#ordered_ids + 1] = thread.id
    end
    next_state.threads.order = replace_order(next_state.threads.order, ordered_ids)
    next_state.threads.next_cursor = event.next_cursor
  elseif event.type == "thread_activated" then
    next_state.threads.active_id = event.thread_id
    if event.thread_id then
      ensure_thread(next_state, event.thread_id)
    end
  elseif event.type == "thread_status_changed" then
    ensure_thread(next_state, event.thread_id).status = clone(event.status)
  elseif event.type == "thread_archived" then
    ensure_thread(next_state, event.thread_id).archived = true
  elseif event.type == "thread_name_updated" then
    ensure_thread(next_state, event.thread_id).name = event.thread_name
  elseif event.type == "thread_unarchived" then
    ensure_thread(next_state, event.thread_id).archived = false
  elseif event.type == "thread_closed" then
    ensure_thread(next_state, event.thread_id).closed = true
  elseif event.type == "turn_received" then
    local thread = ensure_thread(next_state, event.thread_id)
    merge_turn(thread, event.turn, { replace_items = event.replace_items })
  elseif event.type == "turn_diff_updated" then
    local thread = ensure_thread(next_state, event.thread_id)
    ensure_turn(thread, event.turn_id).diff = clone(event.diff)
  elseif event.type == "turn_plan_updated" then
    local thread = ensure_thread(next_state, event.thread_id)
    ensure_turn(thread, event.turn_id).plan = clone(event.plan)
  elseif event.type == "item_received" then
    local thread = ensure_thread(next_state, event.thread_id)
    local turn = ensure_turn(thread, event.turn_id)
    merge_item(turn, event.item)
  elseif event.type == "agent_message_delta" then
    local thread = ensure_thread(next_state, event.thread_id)
    local turn = ensure_turn(thread, event.turn_id)
    local item = ensure_item(turn, event.item_id, {
      type = "agentMessage",
      text = "",
      phase = nil,
    })
    item.text = (present(item.text) and item.text or "") .. event.delta
  elseif event.type == "plan_delta" then
    local thread = ensure_thread(next_state, event.thread_id)
    local turn = ensure_turn(thread, event.turn_id)
    local item = ensure_item(turn, event.item_id, {
      type = "plan",
      text = "",
    })
    item.text = (present(item.text) and item.text or "") .. event.delta
  elseif event.type == "reasoning_summary_part_added" then
    local thread = ensure_thread(next_state, event.thread_id)
    local turn = ensure_turn(thread, event.turn_id)
    local item = ensure_item(turn, event.item_id, {
      type = "reasoning",
      summary = {},
      content = {},
    })
    item.summary = type(item.summary) == "table" and item.summary or {}
    ensure_array_slot(item.summary, (tonumber(event.summary_index) or 0) + 1)
  elseif event.type == "reasoning_summary_text_delta" then
    local thread = ensure_thread(next_state, event.thread_id)
    local turn = ensure_turn(thread, event.turn_id)
    local item = ensure_item(turn, event.item_id, {
      type = "reasoning",
      summary = {},
      content = {},
    })
    item.summary = type(item.summary) == "table" and item.summary or {}
    local index = (tonumber(event.summary_index) or 0) + 1
    ensure_array_slot(item.summary, index)
    item.summary[index] = item.summary[index] .. event.delta
  elseif event.type == "reasoning_text_delta" then
    local thread = ensure_thread(next_state, event.thread_id)
    local turn = ensure_turn(thread, event.turn_id)
    local item = ensure_item(turn, event.item_id, {
      type = "reasoning",
      summary = {},
      content = {},
    })
    item.content = type(item.content) == "table" and item.content or {}
    local index = (tonumber(event.content_index) or 0) + 1
    ensure_array_slot(item.content, index)
    item.content[index] = item.content[index] .. event.delta
  elseif event.type == "command_execution_output_delta" then
    local thread = ensure_thread(next_state, event.thread_id)
    local turn = ensure_turn(thread, event.turn_id)
    local item = ensure_item(turn, event.item_id, {
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
    item.aggregatedOutput = (present(item.aggregatedOutput) and item.aggregatedOutput or "") .. event.delta
  elseif event.type == "server_request_received" then
    upsert_server_request(next_state, event.request)
  elseif event.type == "server_request_response_sent" then
    mark_server_request_responded(next_state, event.request_id, event.response)
  elseif event.type == "server_request_resolved" then
    resolve_server_request(next_state, event.request_id)
  elseif event.type == "workbench_fragment_added" then
    add_workbench_fragment(next_state, event.thread_id, event.fragment)
  elseif event.type == "workbench_fragment_removed" then
    remove_workbench_fragment(next_state, event.thread_id, event.fragment_id)
  elseif event.type == "workbench_cleared" then
    clear_workbench(next_state, event.thread_id)
  elseif event.type == "workbench_message_updated" then
    set_workbench_message(next_state, event.thread_id, event.message)
  end

  if event.log_entry then
    append_log(next_state, event.log_entry)
  end

  return next_state
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
    return clone(state)
  end

  function store:dispatch(event)
    if not event.log_entry and event.type ~= "state_snapshot" then
      event.log_entry = {
        at = now_iso(),
        kind = "state",
        direction = "internal",
        body = event.type,
      }
    end
    state = reducer(state, event)
    for _, callback in ipairs(subscribers) do
      callback(self:get_state(), event)
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
