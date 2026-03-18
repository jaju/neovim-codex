local value = require("neovim_codex.core.value")

local M = {}

local SEP = string.char(31)

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local deep_copy = value.deep_copy
local shallow_copy = value.shallow_copy
local copy_array = value.copy_array
local present = value.present

local function request_key(value)
  return tostring(value)
end

local function key2(first, second)
  return string.format("%s%s%s", tostring(first), SEP, tostring(second))
end

local function key3(first, second, third)
  return string.format("%s%s%s%s%s", tostring(first), SEP, tostring(second), SEP, tostring(third))
end

local function append_log(logs, max_entries, entry)
  logs[#logs + 1] = entry
  local overflow = #logs - max_entries
  if overflow > 0 then
    local kept = #logs - overflow
    for index = 1, kept do
      logs[index] = logs[index + overflow]
    end
    for index = #logs, kept + 1, -1 do
      logs[index] = nil
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

local function new_thread(thread_id)
  return {
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
    runtime = {
      model = nil,
      effort = nil,
      summary = nil,
      approvalPolicy = nil,
      collaborationMode = nil,
      ephemeral = nil,
    },
    tokenUsage = nil,
    archived = false,
    closed = false,
    turns_order = {},
    turns_by_id = {},
  }
end

local function new_turn(turn_id)
  return {
    id = turn_id,
    status = "pending",
    error = nil,
    items_order = {},
    items_by_id = {},
    diff = nil,
    plan = nil,
  }
end

local function new_workbench(thread_id)
  return {
    thread_id = thread_id,
    fragments_order = {},
    fragments_by_id = {},
    next_handle_seq = 1,
    draft_message = "",
    updated_at = nil,
  }
end

local function new_draft(state)
  return {
    next_state = shallow_copy(state),
    connection_touched = false,
    logs_touched = false,
    threads_touched = false,
    threads_by_id_touched = false,
    threads_order_touched = false,
    thread_touched = {},
    thread_turns_by_id_touched = {},
    thread_turns_order_touched = {},
    turn_touched = {},
    turn_items_by_id_touched = {},
    turn_items_order_touched = {},
    item_touched = {},
    server_requests_touched = false,
    server_requests_by_id_touched = false,
    server_requests_order_touched = false,
    server_request_touched = {},
    workbench_touched = false,
    workbench_by_thread_id_touched = false,
    workbench_entry_touched = {},
    workbench_fragments_by_id_touched = {},
    workbench_fragments_order_touched = {},
    workbench_fragment_touched = {},
  }
end

local function touch_connection(draft)
  if not draft.connection_touched then
    draft.next_state.connection = shallow_copy(draft.next_state.connection)
    draft.connection_touched = true
  end
  return draft.next_state.connection
end

local function touch_logs(draft)
  if not draft.logs_touched then
    draft.next_state.logs = copy_array(draft.next_state.logs)
    draft.logs_touched = true
  end
  return draft.next_state.logs
end

local function touch_threads(draft)
  if not draft.threads_touched then
    draft.next_state.threads = shallow_copy(draft.next_state.threads)
    draft.threads_touched = true
  end
  return draft.next_state.threads
end

local function touch_threads_by_id(draft)
  local threads = touch_threads(draft)
  if not draft.threads_by_id_touched then
    threads.by_id = shallow_copy(threads.by_id)
    draft.threads_by_id_touched = true
  end
  return threads.by_id
end

local function touch_threads_order(draft)
  local threads = touch_threads(draft)
  if not draft.threads_order_touched then
    threads.order = copy_array(threads.order)
    draft.threads_order_touched = true
  end
  return threads.order
end

local function read_thread(draft, thread_id)
  local threads = draft.next_state.threads
  return threads and threads.by_id and threads.by_id[thread_id] or nil
end

local function touch_thread(draft, thread_id)
  local key = tostring(thread_id)
  local by_id = touch_threads_by_id(draft)
  if draft.thread_touched[key] then
    return by_id[thread_id]
  end

  local current = by_id[thread_id]
  local thread = current and shallow_copy(current) or new_thread(thread_id)
  by_id[thread_id] = thread
  draft.thread_touched[key] = true

  if not current then
    upsert_order(touch_threads_order(draft), thread_id)
  end

  return thread
end

local function touch_thread_turns_by_id(draft, thread_id)
  local thread = touch_thread(draft, thread_id)
  local key = tostring(thread_id)
  if not draft.thread_turns_by_id_touched[key] then
    thread.turns_by_id = shallow_copy(thread.turns_by_id or {})
    draft.thread_turns_by_id_touched[key] = true
  end
  return thread.turns_by_id
end

local function touch_thread_turns_order(draft, thread_id)
  local thread = touch_thread(draft, thread_id)
  local key = tostring(thread_id)
  if not draft.thread_turns_order_touched[key] then
    thread.turns_order = copy_array(thread.turns_order)
    draft.thread_turns_order_touched[key] = true
  end
  return thread.turns_order
end

local function reset_thread_turns(draft, thread_id)
  local thread = touch_thread(draft, thread_id)
  local key = tostring(thread_id)
  thread.turns_by_id = {}
  thread.turns_order = {}
  draft.thread_turns_by_id_touched[key] = true
  draft.thread_turns_order_touched[key] = true
  return thread
end

local function read_turn(draft, thread_id, turn_id)
  local thread = read_thread(draft, thread_id)
  return thread and thread.turns_by_id and thread.turns_by_id[turn_id] or nil
end

local function ensure_turn(draft, thread_id, turn_id)
  local turns_by_id = touch_thread_turns_by_id(draft, thread_id)
  local key = key2(thread_id, turn_id)
  if draft.turn_touched[key] then
    return turns_by_id[turn_id]
  end

  local current = turns_by_id[turn_id]
  local turn = current and shallow_copy(current) or new_turn(turn_id)
  turns_by_id[turn_id] = turn
  draft.turn_touched[key] = true

  if not current then
    upsert_order(touch_thread_turns_order(draft, thread_id), turn_id)
  end

  return turn
end

local function touch_turn_items_by_id(draft, thread_id, turn_id)
  local turn = ensure_turn(draft, thread_id, turn_id)
  local key = key2(thread_id, turn_id)
  if not draft.turn_items_by_id_touched[key] then
    turn.items_by_id = shallow_copy(turn.items_by_id or {})
    draft.turn_items_by_id_touched[key] = true
  end
  return turn.items_by_id
end

local function touch_turn_items_order(draft, thread_id, turn_id)
  local turn = ensure_turn(draft, thread_id, turn_id)
  local key = key2(thread_id, turn_id)
  if not draft.turn_items_order_touched[key] then
    turn.items_order = copy_array(turn.items_order)
    draft.turn_items_order_touched[key] = true
  end
  return turn.items_order
end

local function reset_turn_items(draft, thread_id, turn_id)
  local turn = ensure_turn(draft, thread_id, turn_id)
  local key = key2(thread_id, turn_id)
  turn.items_by_id = {}
  turn.items_order = {}
  draft.turn_items_by_id_touched[key] = true
  draft.turn_items_order_touched[key] = true
  return turn
end

local function read_item(draft, thread_id, turn_id, item_id)
  local turn = read_turn(draft, thread_id, turn_id)
  return turn and turn.items_by_id and turn.items_by_id[item_id] or nil
end

local function replace_item(draft, thread_id, turn_id, item)
  local items_by_id = touch_turn_items_by_id(draft, thread_id, turn_id)
  items_by_id[item.id] = item
  draft.item_touched[key3(thread_id, turn_id, item.id)] = true
  upsert_order(touch_turn_items_order(draft, thread_id, turn_id), item.id)
  return item
end

local function ensure_item(draft, thread_id, turn_id, item_id, defaults)
  local items_by_id = touch_turn_items_by_id(draft, thread_id, turn_id)
  local key = key3(thread_id, turn_id, item_id)
  if draft.item_touched[key] then
    return items_by_id[item_id]
  end

  local current = items_by_id[item_id]
  local item = current and shallow_copy(current) or deep_copy(defaults or {})
  item.id = item_id
  items_by_id[item_id] = item
  draft.item_touched[key] = true

  if not current then
    upsert_order(touch_turn_items_order(draft, thread_id, turn_id), item_id)
  end

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


local function touch_server_requests(draft)
  if not draft.server_requests_touched then
    draft.next_state.server_requests = shallow_copy(draft.next_state.server_requests)
    draft.server_requests_touched = true
  end
  return draft.next_state.server_requests
end

local function touch_server_requests_by_id(draft)
  local server_requests = touch_server_requests(draft)
  if not draft.server_requests_by_id_touched then
    server_requests.by_id = shallow_copy(server_requests.by_id)
    draft.server_requests_by_id_touched = true
  end
  return server_requests.by_id
end

local function touch_server_requests_order(draft)
  local server_requests = touch_server_requests(draft)
  if not draft.server_requests_order_touched then
    server_requests.order = copy_array(server_requests.order)
    draft.server_requests_order_touched = true
  end
  return server_requests.order
end

local function read_server_request(draft, request_id)
  local key = request_key(request_id)
  local server_requests = draft.next_state.server_requests
  return server_requests and server_requests.by_id and server_requests.by_id[key] or nil
end

local function touch_server_request(draft, request_id)
  local key = request_key(request_id)
  local by_id = touch_server_requests_by_id(draft)
  if draft.server_request_touched[key] then
    return by_id[key]
  end

  local current = by_id[key]
  if not current then
    return nil
  end

  by_id[key] = shallow_copy(current)
  draft.server_request_touched[key] = true
  return by_id[key]
end

local function clear_server_requests(draft)
  local server_requests = touch_server_requests(draft)
  server_requests.active_id = nil
  server_requests.order = {}
  server_requests.by_id = {}
  draft.server_requests_order_touched = true
  draft.server_requests_by_id_touched = true
end

local function upsert_server_request(draft, message)
  local key = request_key(message.id)
  local params = deep_copy(message.params or {})
  local current = read_server_request(draft, message.id)
  local request = current and shallow_copy(current) or {
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

  touch_server_requests_by_id(draft)[key] = request
  draft.server_request_touched[key] = true
  upsert_order(touch_server_requests_order(draft), key)
  touch_server_requests(draft).active_id = key
  return request
end

local function mark_server_request_responded(draft, request_id, response)
  local key = request_key(request_id)
  local request = touch_server_request(draft, request_id)
  if not request then
    return nil
  end

  request.status = "responding"
  request.responded_at = now_iso()
  request.response = deep_copy(response)
  touch_server_requests(draft).active_id = key
  return request
end

local function resolve_server_request(draft, request_id)
  local key = request_key(request_id)
  touch_server_requests_by_id(draft)[key] = nil
  remove_order(touch_server_requests_order(draft), key)
  local server_requests = touch_server_requests(draft)
  if server_requests.active_id == key then
    server_requests.active_id = server_requests.order[#server_requests.order]
  end
end

local function touch_workbench_root(draft)
  if not draft.workbench_touched then
    draft.next_state.workbench = shallow_copy(draft.next_state.workbench)
    draft.workbench_touched = true
  end
  return draft.next_state.workbench
end

local function touch_workbench_by_thread_id(draft)
  local workbench = touch_workbench_root(draft)
  if not draft.workbench_by_thread_id_touched then
    workbench.by_thread_id = shallow_copy(workbench.by_thread_id)
    draft.workbench_by_thread_id_touched = true
  end
  return workbench.by_thread_id
end

local function ensure_workbench(draft, thread_id)
  if not thread_id then
    return nil
  end

  local key = tostring(thread_id)
  local by_thread_id = touch_workbench_by_thread_id(draft)
  if draft.workbench_entry_touched[key] then
    return by_thread_id[thread_id]
  end

  local current = by_thread_id[thread_id]
  local workbench = current and shallow_copy(current) or new_workbench(thread_id)
  by_thread_id[thread_id] = workbench
  draft.workbench_entry_touched[key] = true
  return workbench
end

local function touch_workbench_fragments_by_id(draft, thread_id)
  local workbench = ensure_workbench(draft, thread_id)
  local key = tostring(thread_id)
  if not draft.workbench_fragments_by_id_touched[key] then
    workbench.fragments_by_id = shallow_copy(workbench.fragments_by_id or {})
    draft.workbench_fragments_by_id_touched[key] = true
  end
  return workbench.fragments_by_id
end

local function touch_workbench_fragments_order(draft, thread_id)
  local workbench = ensure_workbench(draft, thread_id)
  local key = tostring(thread_id)
  if not draft.workbench_fragments_order_touched[key] then
    workbench.fragments_order = copy_array(workbench.fragments_order)
    draft.workbench_fragments_order_touched[key] = true
  end
  return workbench.fragments_order
end

local function touch_workbench_fragment(draft, thread_id, fragment_id)
  local fragments_by_id = touch_workbench_fragments_by_id(draft, thread_id)
  local key = key2(thread_id, fragment_id)
  if draft.workbench_fragment_touched[key] then
    return fragments_by_id[fragment_id]
  end

  local current = fragments_by_id[fragment_id]
  if not current then
    return nil
  end

  fragments_by_id[fragment_id] = shallow_copy(current)
  draft.workbench_fragment_touched[key] = true
  return fragments_by_id[fragment_id]
end

local function add_workbench_fragment(draft, thread_id, fragment)
  local workbench = ensure_workbench(draft, thread_id)
  if not workbench then
    return nil
  end

  local next_fragment = deep_copy(fragment)
  if not next_fragment.handle then
    next_fragment.handle = string.format("f%d", workbench.next_handle_seq)
    workbench.next_handle_seq = workbench.next_handle_seq + 1
  end
  if next_fragment.parked == nil then
    next_fragment.parked = false
  end

  touch_workbench_fragments_by_id(draft, thread_id)[next_fragment.id] = next_fragment
  draft.workbench_fragment_touched[key2(thread_id, next_fragment.id)] = true
  upsert_order(touch_workbench_fragments_order(draft, thread_id), next_fragment.id)
  workbench.updated_at = now_iso()
  return workbench
end

local function remove_workbench_fragment(draft, thread_id, fragment_id)
  local workbench = ensure_workbench(draft, thread_id)
  if not workbench then
    return nil
  end

  touch_workbench_fragments_by_id(draft, thread_id)[fragment_id] = nil
  remove_order(touch_workbench_fragments_order(draft, thread_id), fragment_id)
  workbench.updated_at = now_iso()
  return workbench
end

local function set_workbench_fragment_parked(draft, thread_id, fragment_id, parked)
  local workbench = ensure_workbench(draft, thread_id)
  if not workbench then
    return nil
  end

  local fragment = touch_workbench_fragment(draft, thread_id, fragment_id)
  if not fragment then
    return nil
  end

  fragment.parked = parked == true
  workbench.updated_at = now_iso()
  return workbench
end

local function clear_active_workbench_fragments(draft, thread_id)
  local workbench = ensure_workbench(draft, thread_id)
  if not workbench then
    return nil
  end

  local next_order = {}
  local next_by_id = {}
  local current_order = workbench.fragments_order or {}
  local current_by_id = workbench.fragments_by_id or {}

  for _, fragment_id in ipairs(current_order) do
    local fragment = current_by_id[fragment_id]
    if fragment and fragment.parked then
      next_order[#next_order + 1] = fragment_id
      next_by_id[fragment_id] = fragment
    end
  end

  workbench.fragments_order = next_order
  workbench.fragments_by_id = next_by_id
  draft.workbench_fragments_order_touched[tostring(thread_id)] = true
  draft.workbench_fragments_by_id_touched[tostring(thread_id)] = true
  workbench.updated_at = now_iso()
  return workbench
end

local function clear_workbench(draft, thread_id)
  local workbench = ensure_workbench(draft, thread_id)
  if not workbench then
    return nil
  end

  workbench.fragments_order = {}
  workbench.fragments_by_id = {}
  draft.workbench_fragments_order_touched[tostring(thread_id)] = true
  draft.workbench_fragments_by_id_touched[tostring(thread_id)] = true
  workbench.updated_at = now_iso()
  return workbench
end

local function set_workbench_message(draft, thread_id, message)
  local workbench = ensure_workbench(draft, thread_id)
  if not workbench then
    return nil
  end

  workbench.draft_message = tostring(message or "")
  workbench.updated_at = now_iso()
  return workbench
end

M.now_iso = now_iso
M.deep_copy = deep_copy
M.copy_array = copy_array
M.present = present
M.append_log = append_log
M.replace_order = replace_order
M.new_draft = new_draft
M.touch_connection = touch_connection
M.touch_logs = touch_logs
M.touch_threads = touch_threads
M.touch_thread = touch_thread
M.reset_thread_turns = reset_thread_turns
M.ensure_turn = ensure_turn
M.reset_turn_items = reset_turn_items
M.read_item = read_item
M.replace_item = replace_item
M.ensure_item = ensure_item
M.ensure_array_slot = ensure_array_slot
M.clear_server_requests = clear_server_requests
M.upsert_server_request = upsert_server_request
M.mark_server_request_responded = mark_server_request_responded
M.resolve_server_request = resolve_server_request
M.add_workbench_fragment = add_workbench_fragment
M.remove_workbench_fragment = remove_workbench_fragment
M.set_workbench_fragment_parked = set_workbench_fragment_parked
M.clear_active_workbench_fragments = clear_active_workbench_fragments
M.clear_workbench = clear_workbench
M.set_workbench_message = set_workbench_message

return M
