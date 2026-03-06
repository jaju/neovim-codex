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

local function reducer(state, event)
  local next_state = clone(state)

  if event.type == "transport_started" then
    next_state.connection.status = "initializing"
    next_state.connection.pid = event.pid
    next_state.connection.last_error = nil
  elseif event.type == "transport_stopped" then
    next_state.connection.status = "stopped"
    next_state.connection.pid = nil
    next_state.connection.initialized = false
    next_state.connection.user_agent = nil
    next_state.connection.last_error = event.reason
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
