local jsonrpc = require("neovim_codex.core.jsonrpc")

local M = {}
M.__index = M

local function log_entry(direction, body)
  return {
    at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    kind = "protocol",
    direction = direction,
    body = body,
  }
end

local function error_message(error)
  if type(error) == "table" then
    return error.message or "request failed"
  end
  return error or "request failed"
end

function M.new(opts)
  assert(opts and opts.store, "store is required")
  assert(opts and opts.transport, "transport is required")
  assert(opts and opts.json, "json codec is required")
  assert(opts and opts.client_info, "client_info is required")

  local self = setmetatable({
    store = opts.store,
    transport = opts.transport,
    json = opts.json,
    client_info = opts.client_info,
    experimental_api = opts.experimental_api ~= false,
    decoder = jsonrpc.new_decoder({ json = opts.json }),
    next_id = 1,
    pending = {},
    stop_requested = false,
    on_server_request = opts.on_server_request,
  }, M)

  return self
end

function M:is_running()
  return self.transport:is_running()
end

function M:_request(method, params, on_result)
  local id = self.next_id
  self.next_id = self.next_id + 1
  self.pending[id] = on_result
  local payload = jsonrpc.encode_request(self.json, id, method, params)
  self.store:dispatch({
    type = "request_sent",
    log_entry = log_entry("outgoing", payload:gsub("\n$", "")),
  })
  self.transport:write(payload)
  return id
end

function M:_notify(method, params)
  local payload = jsonrpc.encode_notification(self.json, method, params)
  self.store:dispatch({
    type = "notification_sent",
    log_entry = log_entry("outgoing", payload:gsub("\n$", "")),
  })
  self.transport:write(payload)
end

function M:respond(id, result)
  local payload = jsonrpc.encode_response(self.json, id, result)
  self.store:dispatch({
    type = "response_sent",
    log_entry = log_entry("outgoing", payload:gsub("\n$", "")),
  })
  self.transport:write(payload)
end

function M:respond_server_request(request_id, result, meta)
  meta = meta or {}
  self.store:dispatch({
    type = "server_request_response_sent",
    request_id = request_id,
    response = result,
  })
  self:respond(request_id, result)
  return true
end

function M:_dispatch_result(message, on_result)
  if not on_result then
    return
  end

  if message.error then
    local err = error_message(message.error)
    self.store:dispatch({ type = "request_failed", message = err })
    on_result(err, nil, message)
    return
  end

  on_result(nil, message.result or {}, message)
end

function M:_handle_notification(message)
  local params = message.params or {}

  if message.method == "initialized" then
    return
  elseif message.method == "thread/started" then
    self.store:dispatch({
      type = "thread_received",
      thread = params.thread,
      replace_turns = false,
      activate = false,
    })
  elseif message.method == "thread/status/changed" then
    self.store:dispatch({
      type = "thread_status_changed",
      thread_id = params.threadId,
      status = params.status,
    })
  elseif message.method == "thread/archived" then
    self.store:dispatch({ type = "thread_archived", thread_id = params.threadId })
  elseif message.method == "thread/name/updated" then
    self.store:dispatch({
      type = "thread_name_updated",
      thread_id = params.threadId,
      thread_name = params.threadName,
    })
  elseif message.method == "thread/unarchived" then
    self.store:dispatch({ type = "thread_unarchived", thread_id = params.threadId })
  elseif message.method == "thread/closed" then
    self.store:dispatch({ type = "thread_closed", thread_id = params.threadId })
  elseif message.method == "turn/started" or message.method == "turn/completed" then
    self.store:dispatch({
      type = "turn_received",
      thread_id = params.threadId,
      turn = params.turn,
      replace_items = false,
    })
  elseif message.method == "turn/diff/updated" then
    self.store:dispatch({
      type = "turn_diff_updated",
      thread_id = params.threadId,
      turn_id = params.turnId,
      diff = params.diff,
    })
  elseif message.method == "turn/plan/updated" then
    self.store:dispatch({
      type = "turn_plan_updated",
      thread_id = params.threadId,
      turn_id = params.turnId,
      plan = params.plan,
    })
  elseif message.method == "item/started" or message.method == "item/completed" then
    self.store:dispatch({
      type = "item_received",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item = params.item,
    })
  elseif message.method == "item/agentMessage/delta" then
    self.store:dispatch({
      type = "agent_message_delta",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      delta = params.delta,
    })
  elseif message.method == "item/plan/delta" then
    self.store:dispatch({
      type = "plan_delta",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      delta = params.delta,
    })
  elseif message.method == "item/reasoning/summaryPartAdded" then
    self.store:dispatch({
      type = "reasoning_summary_part_added",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      summary_index = params.summaryIndex,
    })
  elseif message.method == "item/reasoning/summaryTextDelta" then
    self.store:dispatch({
      type = "reasoning_summary_text_delta",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      summary_index = params.summaryIndex,
      delta = params.delta,
    })
  elseif message.method == "item/reasoning/textDelta" then
    self.store:dispatch({
      type = "reasoning_text_delta",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      content_index = params.contentIndex,
      delta = params.delta,
    })
  elseif message.method == "item/commandExecution/outputDelta" then
    self.store:dispatch({
      type = "command_execution_output_delta",
      thread_id = params.threadId,
      turn_id = params.turnId,
      item_id = params.itemId,
      delta = params.delta,
    })
  elseif message.method == "serverRequest/resolved" then
    self.store:dispatch({
      type = "server_request_resolved",
      thread_id = params.threadId,
      request_id = params.requestId,
    })
  end
end

function M:_handle_server_request(message)
  self.store:dispatch({
    type = "server_request_received",
    request = message,
  })

  if self.on_server_request then
    self.on_server_request(message, self)
  end
end

function M:_handle_message(message)
  local encoded = self.json.encode(message)
  self.store:dispatch({
    type = "message_received",
    log_entry = log_entry("incoming", encoded),
  })

  if message.method and message.id ~= nil then
    self:_handle_server_request(message)
    return
  end

  if message.id ~= nil then
    local callback = self.pending[message.id]
    self.pending[message.id] = nil
    self:_dispatch_result(message, callback)
    return
  end

  if message.method then
    self:_handle_notification(message)
  end
end

function M:_on_stdout(chunk)
  local messages, err = self.decoder:push(chunk)
  if err then
    self.store:dispatch({ type = "protocol_error", message = err })
    return
  end

  for _, message in ipairs(messages) do
    self:_handle_message(message)
  end
end

function M:_on_stderr(chunk)
  if not chunk or chunk == "" then
    return
  end

  self.store:dispatch({
    type = "stderr_received",
    message = chunk,
    log_entry = log_entry("stderr", chunk:gsub("\n$", "")),
  })
end

function M:_on_exit(code, signal)
  self.store:dispatch({
    type = "transport_stopped",
    expected = self.stop_requested,
    reason = string.format("process exited with code=%s signal=%s", code, signal),
  })
  self.stop_requested = false
end

function M:start()
  if self.transport:is_running() then
    return false, "app-server is already running"
  end

  self.stop_requested = false
  local ok, err, pid = self.transport:start({
    on_stdout = function(chunk)
      self:_on_stdout(chunk)
    end,
    on_stderr = function(chunk)
      self:_on_stderr(chunk)
    end,
    on_exit = function(code, signal)
      self:_on_exit(code, signal)
    end,
  })

  if not ok then
    self.store:dispatch({ type = "transport_error", message = err })
    return false, err
  end

  self.store:dispatch({ type = "transport_started", pid = pid })
  self.store:dispatch({ type = "initialize_requested" })

  self:_request("initialize", {
    clientInfo = self.client_info,
    capabilities = {
      experimentalApi = self.experimental_api,
    },
  }, function(err_message, result)
    if err_message then
      return
    end

    self.store:dispatch({
      type = "initialize_succeeded",
      user_agent = result.userAgent,
    })
    self:_notify("initialized")
  end)

  return true, nil
end

function M:stop()
  if not self.transport:is_running() then
    return false, "app-server is not running"
  end

  self.stop_requested = true
  self.store:dispatch({ type = "transport_stop_requested" })
  self.transport:stop()
  return true, nil
end

function M:thread_start(params, on_result)
  return self:_request("thread/start", params, function(err, result, message)
    if not err and result.thread then
      self.store:dispatch({
        type = "thread_received",
        thread = result.thread,
        replace_turns = false,
        activate = true,
      })
    end
    if on_result then
      on_result(err, result, message)
    end
  end)
end

function M:thread_resume(params, on_result)
  return self:_request("thread/resume", params, function(err, result, message)
    if not err and result.thread then
      self.store:dispatch({
        type = "thread_received",
        thread = result.thread,
        replace_turns = true,
        activate = true,
      })
    end
    if on_result then
      on_result(err, result, message)
    end
  end)
end

function M:thread_name_set(params, on_result)
  return self:_request("thread/name/set", params, function(err, result, message)
    if not err then
      self.store:dispatch({
        type = "thread_name_updated",
        thread_id = params.threadId,
        thread_name = params.name,
      })
    end
    if on_result then
      on_result(err, result, message)
    end
  end)
end

function M:thread_read(params, on_result)
  return self:_request("thread/read", params, function(err, result, message)
    if not err and result.thread then
      self.store:dispatch({
        type = "thread_received",
        thread = result.thread,
        replace_turns = params.includeTurns == true,
        activate = false,
      })
    end
    if on_result then
      on_result(err, result, message)
    end
  end)
end

function M:thread_list(params, on_result)
  return self:_request("thread/list", params, function(err, result, message)
    if not err then
      self.store:dispatch({
        type = "threads_list_received",
        threads = result.data or {},
        next_cursor = result.nextCursor,
      })
    end
    if on_result then
      on_result(err, result, message)
    end
  end)
end

function M:turn_start(params, on_result)
  return self:_request("turn/start", params, function(err, result, message)
    if not err and result.turn then
      self.store:dispatch({
        type = "turn_received",
        thread_id = params.threadId,
        turn = result.turn,
        replace_items = false,
      })
    end
    if on_result then
      on_result(err, result, message)
    end
  end)
end

function M:turn_interrupt(params, on_result)
  return self:_request("turn/interrupt", params, function(err, result, message)
    if on_result then
      on_result(err, result, message)
    end
  end)
end

function M:status()
  return self.store:get_state().connection
end

function M:get_state()
  return self.store:get_state()
end

return M
