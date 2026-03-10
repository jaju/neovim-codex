local M = {}

local function copy_ordered(order, by_id)
  local out = {}
  for _, id in ipairs(order or {}) do
    local value = by_id[id]
    if value then
      out[#out + 1] = value
    end
  end
  return out
end

local function request_key(request_id)
  return request_id and tostring(request_id) or nil
end

local function filter_fragments(fragments, parked)
  local out = {}
  for _, fragment in ipairs(fragments or {}) do
    if (fragment.parked == true) == parked then
      out[#out + 1] = fragment
    end
  end
  return out
end

function M.list_threads(state)
  return copy_ordered(state.threads.order, state.threads.by_id)
end

function M.get_thread(state, thread_id)
  if not thread_id then
    return nil
  end
  return state.threads.by_id[thread_id]
end

function M.get_active_thread(state)
  return M.get_thread(state, state.threads.active_id)
end

function M.list_turns(thread)
  if not thread then
    return {}
  end
  return copy_ordered(thread.turns_order, thread.turns_by_id)
end

function M.get_turn(thread, turn_id)
  if not thread or not turn_id then
    return nil
  end
  return thread.turns_by_id[turn_id]
end

function M.get_active_turn(state)
  local thread = M.get_active_thread(state)
  if not thread then
    return nil
  end

  for index = #thread.turns_order, 1, -1 do
    local turn_id = thread.turns_order[index]
    local turn = thread.turns_by_id[turn_id]
    if turn then
      return turn
    end
  end

  return nil
end

function M.find_running_turn(state, thread_id)
  local thread = M.get_thread(state, thread_id) or M.get_active_thread(state)
  if not thread then
    return nil
  end

  for index = #thread.turns_order, 1, -1 do
    local turn = thread.turns_by_id[thread.turns_order[index]]
    if turn and turn.status == "inProgress" then
      return turn, thread
    end
  end

  return nil, thread
end

function M.list_items(turn)
  if not turn then
    return {}
  end
  return copy_ordered(turn.items_order, turn.items_by_id)
end

function M.list_pending_requests(state)
  return copy_ordered(state.server_requests.order, state.server_requests.by_id)
end

function M.get_pending_request(state, request_id)
  local key = request_key(request_id)
  if not key then
    return nil
  end
  return state.server_requests.by_id[key]
end

function M.get_active_request(state)
  return M.get_pending_request(state, state.server_requests.active_id)
end

function M.pending_request_count(state)
  return #(state.server_requests.order or {})
end

function M.get_workbench(state, thread_id)
  local key = thread_id or (state.threads and state.threads.active_id)
  if not key then
    return nil
  end
  return state.workbench.by_thread_id[key]
end

function M.get_active_workbench(state)
  return M.get_workbench(state, state.threads.active_id)
end

function M.list_fragments(workbench, opts)
  if not workbench then
    return {}
  end

  local fragments = copy_ordered(workbench.fragments_order, workbench.fragments_by_id)
  if not opts or opts.parked == nil then
    return fragments
  end

  return filter_fragments(fragments, opts.parked == true)
end

function M.list_active_fragments(workbench)
  return M.list_fragments(workbench, { parked = false })
end

function M.list_parked_fragments(workbench)
  return M.list_fragments(workbench, { parked = true })
end

function M.get_fragment(workbench, fragment_id)
  if not workbench or not fragment_id then
    return nil
  end
  return workbench.fragments_by_id[fragment_id]
end

function M.fragment_counts(workbench)
  local fragments = M.list_fragments(workbench)
  local active = 0
  local parked = 0
  for _, fragment in ipairs(fragments) do
    if fragment.parked then
      parked = parked + 1
    else
      active = active + 1
    end
  end

  return {
    total = #fragments,
    active = active,
    parked = parked,
  }
end

function M.workbench_fragment_count(state, thread_id)
  return M.fragment_counts(M.get_workbench(state, thread_id)).total
end

function M.workbench_fragment_counts(state, thread_id)
  return M.fragment_counts(M.get_workbench(state, thread_id))
end

function M.workbench_message(workbench)
  if not workbench then
    return ""
  end
  return workbench.draft_message or ""
end

return M
