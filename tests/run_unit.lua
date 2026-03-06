local script_path = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fs.dirname(vim.fs.dirname(script_path))
package.path = table.concat({
  repo_root .. "/lua/?.lua",
  repo_root .. "/lua/?/init.lua",
  package.path,
}, ";")

local failures = 0
local tests = {}

local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function eq(actual, expected, message)
  if actual ~= expected then
    error(message or string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual)))
  end
end

test("jsonrpc decoder handles partial lines", function()
  local jsonrpc = require("neovim_codex.core.jsonrpc")
  local decoder = jsonrpc.new_decoder({
    json = {
      encode = vim.json.encode,
      decode = vim.json.decode,
    },
  })

  local messages, err = decoder:push('{"jsonrpc":"2.0","id":1')
  eq(#messages, 0)
  eq(err, nil)

  messages, err = decoder:push(',"result":{"userAgent":"ua"}}\n')
  eq(err, nil)
  eq(#messages, 1)
  eq(messages[1].result.userAgent, "ua")
end)

test("store tracks initialize success without stderr poisoning state", function()
  local store = require("neovim_codex.core.store").new({ max_log_entries = 10 })

  store:dispatch({ type = "transport_started", pid = 42 })
  store:dispatch({ type = "stderr_received", message = "warning" })
  store:dispatch({ type = "initialize_requested" })
  store:dispatch({ type = "initialize_succeeded", user_agent = "ua" })

  local state = store:get_state()
  eq(state.connection.status, "ready")
  eq(state.connection.initialized, true)
  eq(state.connection.user_agent, "ua")
  eq(state.connection.last_stderr, "warning")
  eq(state.connection.last_error, nil)
end)

test("store clears errors on expected stop", function()
  local store = require("neovim_codex.core.store").new({ max_log_entries = 10 })

  store:dispatch({ type = "transport_started", pid = 42 })
  store:dispatch({ type = "initialize_succeeded", user_agent = "ua" })
  store:dispatch({ type = "transport_stop_requested" })
  store:dispatch({ type = "transport_stopped", expected = true, reason = "code=0" })

  local state = store:get_state()
  eq(state.connection.status, "stopped")
  eq(state.connection.last_error, nil)
end)

test("store reconstructs a live thread transcript from items and deltas", function()
  local selectors = require("neovim_codex.core.selectors")
  local store = require("neovim_codex.core.store").new({ max_log_entries = 20 })

  store:dispatch({
    type = "thread_received",
    thread = {
      id = "thr_1",
      preview = "demo",
      ephemeral = false,
      modelProvider = "openai",
      createdAt = 1,
      updatedAt = 1,
      status = { type = "idle" },
      path = nil,
      cwd = "/tmp/demo",
      cliVersion = "0.0.0",
      source = { type = "appServer" },
      agentNickname = nil,
      agentRole = nil,
      gitInfo = nil,
      name = nil,
      turns = {},
    },
    activate = true,
    replace_turns = false,
  })

  store:dispatch({
    type = "turn_received",
    thread_id = "thr_1",
    turn = { id = "turn_1", status = "inProgress", items = {}, error = nil },
  })
  store:dispatch({
    type = "item_received",
    thread_id = "thr_1",
    turn_id = "turn_1",
    item = {
      type = "userMessage",
      id = "item_user",
      content = {
        { type = "text", text = "Explain this change" },
      },
    },
  })
  store:dispatch({
    type = "item_received",
    thread_id = "thr_1",
    turn_id = "turn_1",
    item = {
      type = "agentMessage",
      id = "item_agent",
      text = "",
      phase = nil,
    },
  })
  store:dispatch({
    type = "agent_message_delta",
    thread_id = "thr_1",
    turn_id = "turn_1",
    item_id = "item_agent",
    delta = "First line",
  })
  store:dispatch({
    type = "agent_message_delta",
    thread_id = "thr_1",
    turn_id = "turn_1",
    item_id = "item_agent",
    delta = "\nSecond line",
  })

  local state = store:get_state()
  local thread = selectors.get_active_thread(state)
  eq(thread.id, "thr_1")

  local turn = selectors.get_active_turn(state)
  eq(turn.id, "turn_1")
  eq(turn.items_by_id.item_agent.text, "First line\nSecond line")
  eq(turn.items_order[1], "item_user")
  eq(turn.items_order[2], "item_agent")
end)

for _, case in ipairs(tests) do
  local ok, err = pcall(case.fn)
  if ok then
    print("ok - " .. case.name)
  else
    failures = failures + 1
    print("not ok - " .. case.name)
    print(err)
  end
end

if failures > 0 then
  os.exit(1)
end
