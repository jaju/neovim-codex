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

local function fake_transport()
  return {
    is_running = function()
      return true
    end,
    start = function()
      return true, nil, 1
    end,
    stop = function()
      return true, nil
    end,
    write = function() end,
  }
end

local function new_test_client()
  local store = require("neovim_codex.core.store").new({ max_log_entries = 20 })
  local client = require("neovim_codex.core.client").new({
    store = store,
    transport = fake_transport(),
    json = {
      encode = vim.json.encode,
      decode = vim.json.decode,
    },
    client_info = {
      name = "test_client",
      title = "Test Client",
      version = "0.0.0",
    },
    experimental_api = true,
  })
  local calls = {}
  client._request = function(_, method, params, on_result)
    calls[#calls + 1] = { method = method, params = vim.deepcopy(params) }
    if method == "thread/unarchive" then
      on_result(nil, {
        thread = {
          id = params.threadId,
          preview = "restored",
          ephemeral = false,
          modelProvider = "openai",
          createdAt = 1,
          updatedAt = 1,
          status = { type = "idle" },
          cwd = "/tmp/demo",
          turns = {},
        },
      }, {})
    elseif method == "turn/steer" then
      on_result(nil, { turnId = params.expectedTurnId }, {})
    else
      on_result(nil, {}, {})
    end
    return #calls
  end
  return client, store, calls
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

test("coalesced scheduler collapses repeated triggers and keeps latest args", function()
  local scheduler = require("neovim_codex.nvim.coalesced_schedule")
  local calls = 0
  local last_value = nil
  local job = scheduler.new(function(value)
    calls = calls + 1
    last_value = value
  end)

  eq(job:trigger("first"), true)
  eq(job:trigger("second"), false)
  eq(vim.wait(1000, function()
    return calls == 1
  end, 10), true)
  eq(last_value, "second")

  job:dispose()
end)

test("text helpers preserve explicit blank lines when flattening tables", function()
  local text = require("neovim_codex.core.text")
  local lines = text.split_lines({ "alpha", "", "beta\ngamma" }, { empty = { "" } })

  eq(#lines, 4)
  eq(lines[1], "alpha")
  eq(lines[2], "")
  eq(lines[3], "beta")
  eq(lines[4], "gamma")
end)

test("client notification handlers update store through the shared dispatch table", function()
  local client, store = new_test_client()

  client:_handle_notification({
    method = "thread/unarchived",
    params = { threadId = "thr_notify" },
  })
  client:_handle_notification({
    method = "turn/started",
    params = {
      threadId = "thr_notify",
      turn = { id = "turn_notify", status = "inProgress", items = {}, error = nil },
    },
  })

  local thread = require("neovim_codex.core.selectors").get_thread(store:get_state(), "thr_notify")
  eq(thread.archived, false)
  eq(thread.turns_by_id.turn_notify.status, "inProgress")
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

test("store accumulates streamed plan, reasoning, and command output deltas", function()
  local selectors = require("neovim_codex.core.selectors")
  local store = require("neovim_codex.core.store").new({ max_log_entries = 20 })

  store:dispatch({
    type = "thread_received",
    thread = {
      id = "thr_stream",
      preview = "demo",
      ephemeral = false,
      modelProvider = "openai",
      createdAt = 1,
      updatedAt = 1,
      status = { type = "idle" },
      cwd = "/tmp/demo",
      turns = {},
    },
    activate = true,
    replace_turns = false,
  })
  store:dispatch({
    type = "turn_received",
    thread_id = "thr_stream",
    turn = { id = "turn_stream", status = "inProgress", items = {}, error = nil },
  })
  store:dispatch({ type = "plan_delta", thread_id = "thr_stream", turn_id = "turn_stream", item_id = "plan_1", delta = "Step 1" })
  store:dispatch({ type = "plan_delta", thread_id = "thr_stream", turn_id = "turn_stream", item_id = "plan_1", delta = "\nStep 2" })
  store:dispatch({ type = "reasoning_summary_part_added", thread_id = "thr_stream", turn_id = "turn_stream", item_id = "reason_1", summary_index = 0 })
  store:dispatch({ type = "reasoning_summary_text_delta", thread_id = "thr_stream", turn_id = "turn_stream", item_id = "reason_1", summary_index = 0, delta = "Thinking" })
  store:dispatch({ type = "reasoning_text_delta", thread_id = "thr_stream", turn_id = "turn_stream", item_id = "reason_1", content_index = 0, delta = "Raw trace" })
  store:dispatch({ type = "command_execution_output_delta", thread_id = "thr_stream", turn_id = "turn_stream", item_id = "cmd_1", delta = "line 1\n" })
  store:dispatch({ type = "command_execution_output_delta", thread_id = "thr_stream", turn_id = "turn_stream", item_id = "cmd_1", delta = "line 2" })

  local thread = selectors.get_active_thread(store:get_state())
  local turn = selectors.get_turn(thread, "turn_stream")

  eq(turn.items_by_id.plan_1.text, "Step 1\nStep 2")
  eq(turn.items_by_id.reason_1.summary[1], "Thinking")
  eq(turn.items_by_id.reason_1.content[1], "Raw trace")
  eq(turn.items_by_id.cmd_1.aggregatedOutput, "line 1\nline 2")
end)

test("store reuses untouched branches across streaming deltas", function()
  local selectors = require("neovim_codex.core.selectors")
  local store = require("neovim_codex.core.store").new({ max_log_entries = 20 })

  store:dispatch({
    type = "thread_received",
    thread = {
      id = "thr_a",
      preview = "active",
      ephemeral = false,
      modelProvider = "openai",
      createdAt = 1,
      updatedAt = 1,
      status = { type = "idle" },
      cwd = "/tmp/a",
      turns = {},
    },
    activate = true,
    replace_turns = false,
  })
  store:dispatch({
    type = "thread_received",
    thread = {
      id = "thr_b",
      preview = "other",
      ephemeral = false,
      modelProvider = "openai",
      createdAt = 1,
      updatedAt = 1,
      status = { type = "idle" },
      cwd = "/tmp/b",
      turns = {},
    },
    activate = false,
    replace_turns = false,
  })
  store:dispatch({
    type = "turn_received",
    thread_id = "thr_a",
    turn = { id = "turn_a", status = "inProgress", items = {}, error = nil },
  })

  local before = store:get_state()
  local before_thread_a = selectors.get_thread(before, "thr_a")
  local before_thread_b = selectors.get_thread(before, "thr_b")

  store:dispatch({
    type = "agent_message_delta",
    thread_id = "thr_a",
    turn_id = "turn_a",
    item_id = "msg_a",
    delta = "Hello",
  })

  local after = store:get_state()
  local after_thread_a = selectors.get_thread(after, "thr_a")
  local after_thread_b = selectors.get_thread(after, "thr_b")

  assert(before ~= after, "dispatch should replace the root state table")
  assert(before_thread_a ~= after_thread_a, "mutated thread should get a new table")
  assert(before_thread_b == after_thread_b, "untouched thread should be structurally shared")
end)


test("store tracks streamed thread token usage for footer summaries", function()
  local selectors = require("neovim_codex.core.selectors")
  local store = require("neovim_codex.core.store").new({ max_log_entries = 20 })

  store:dispatch({
    type = "thread_received",
    thread = {
      id = "thr_usage",
      preview = "demo",
      ephemeral = false,
      modelProvider = "openai",
      createdAt = 1,
      updatedAt = 1,
      status = { type = "idle" },
      cwd = "/tmp/demo",
      turns = {},
    },
    activate = true,
    replace_turns = false,
  })

  store:dispatch({
    type = "thread_token_usage_updated",
    thread_id = "thr_usage",
    turn_id = "turn_usage",
    token_usage = {
      total = { totalTokens = 8400, inputTokens = 5000, cachedInputTokens = 2000, outputTokens = 1400, reasoningOutputTokens = 200 },
      last = { totalTokens = 1200, inputTokens = 900, cachedInputTokens = 0, outputTokens = 300, reasoningOutputTokens = 50 },
      modelContextWindow = 200000,
    },
  })

  local token_usage = selectors.get_thread_token_usage(store:get_state(), "thr_usage")
  eq(token_usage.turnId, "turn_usage")
  eq(token_usage.tokenUsage.total.totalTokens, 8400)
  eq(token_usage.tokenUsage.last.totalTokens, 1200)
end)

test("store tracks pending server requests and resolution", function()
  local selectors = require("neovim_codex.core.selectors")
  local store = require("neovim_codex.core.store").new({ max_log_entries = 20 })

  store:dispatch({
    type = "server_request_received",
    request = {
      method = "item/commandExecution/requestApproval",
      id = "req_1",
      params = {
        threadId = "thr_req",
        turnId = "turn_req",
        itemId = "item_req",
        command = "ls",
      },
    },
  })

  local state = store:get_state()
  eq(selectors.pending_request_count(state), 1)
  eq(selectors.get_active_request(state).key, "req_1")
  eq(selectors.get_active_request(state).params.command, "ls")

  store:dispatch({
    type = "server_request_response_sent",
    request_id = "req_1",
    response = { decision = "accept" },
  })
  state = store:get_state()
  eq(selectors.get_active_request(state).status, "responding")
  eq(selectors.get_active_request(state).response.decision, "accept")

  store:dispatch({
    type = "server_request_resolved",
    request_id = "req_1",
  })

  state = store:get_state()
  eq(selectors.pending_request_count(state), 0)
  eq(selectors.get_active_request(state), nil)
end)

test("store can park fragments and consume only active ones", function()
  local selectors = require("neovim_codex.core.selectors")
  local store = require("neovim_codex.core.store").new({ max_log_entries = 20 })

  store:dispatch({ type = "thread_activated", thread_id = "thr_workbench" })
  store:dispatch({
    type = "workbench_fragment_added",
    thread_id = "thr_workbench",
    fragment = { id = "frag_active", kind = "path_ref", label = "active", path = "/tmp/a", parked = false },
  })
  store:dispatch({
    type = "workbench_fragment_added",
    thread_id = "thr_workbench",
    fragment = { id = "frag_parked", kind = "path_ref", label = "parked", path = "/tmp/b", parked = true },
  })
  store:dispatch({
    type = "workbench_fragment_parked",
    thread_id = "thr_workbench",
    fragment_id = "frag_active",
    parked = true,
  })

  local state = store:get_state()
  local counts = selectors.workbench_fragment_counts(state, "thr_workbench")
  eq(counts.total, 2)
  eq(counts.active, 0)
  eq(counts.parked, 2)

  store:dispatch({
    type = "workbench_fragment_parked",
    thread_id = "thr_workbench",
    fragment_id = "frag_active",
    parked = false,
  })
  store:dispatch({ type = "workbench_active_cleared", thread_id = "thr_workbench" })

  state = store:get_state()
  local fragments = selectors.list_fragments(selectors.get_workbench(state, "thr_workbench"))
  eq(#fragments, 1)
  eq(fragments[1].id, "frag_parked")
  eq(fragments[1].parked, true)
end)

test("packet compiler ignores parked fragments and preserves them in preview metadata", function()
  local packet = require("neovim_codex.core.packet")

  local fragments = {
    {
      id = "frag_code",
      handle = "f1",
      kind = "code_range",
      label = "src/demo.ts:10-12",
      path = "/tmp/src/demo.ts",
      filetype = "ts",
      range = { start_line = 10, end_line = 12 },
      text = "const answer = 42;",
      parked = false,
    },
    {
      id = "frag_path",
      handle = "f2",
      kind = "path_ref",
      label = "src/demo.ts",
      path = "/tmp/src/demo.ts",
      parked = true,
    },
  }

  local input, analysis, err = packet.build_input_items("Please inspect [[f1]].", fragments)
  eq(err, nil)
  eq(input[1].type, "text")
  assert(input[1].text:find("const answer = 42;", 1, true), "compiled packet should inline active fragments")
  eq(#analysis.active_handles, 1)
  eq(analysis.active_handles[1], "f1")
  eq(#analysis.parked_handles, 1)
  eq(analysis.parked_handles[1], "f2")
  assert(input[1].text:find("Code snapshot from", 1, true), "code fragments should expand with a self-describing lead-in")
end)

test("packet compiler requires active fragments to be referenced but allows parked ones to remain unused", function()
  local packet = require("neovim_codex.core.packet")

  local fragments = {
    { id = "frag_active", handle = "f1", kind = "path_ref", label = "src/a.ts", path = "/tmp/src/a.ts", parked = false },
    { id = "frag_parked", handle = "f2", kind = "path_ref", label = "src/b.ts", path = "/tmp/src/b.ts", parked = true },
  }

  local _, _, err = packet.build_input_items("Use later.", fragments)
  assert(err:find("Reference every active fragment", 1, true), "active fragments should still block send when unreferenced")

  local preview_lines, analysis = packet.preview_lines("Use only [[f1]].", fragments)
  eq(analysis.valid, true)
  local preview_text = table.concat(preview_lines, "\n")
  assert(preview_text:find("## Referenced active fragments", 1, true), "preview should list the active fragments that will be sent")
  assert(preview_text:find("## Parked fragments", 1, true), "preview should surface parked fragments without treating them as send blockers")
  assert(preview_text:find("## Unreferenced active fragments", 1, true), "preview should explain which active fragments still need attention")
end)

test("packet compiler rejects references to parked fragments", function()
  local packet = require("neovim_codex.core.packet")

  local fragments = {
    { id = "frag_parked", handle = "f2", kind = "path_ref", label = "src/b.ts", path = "/tmp/src/b.ts", parked = true },
  }

  local _, _, err = packet.build_input_items("Use [[f2]].", fragments)
  assert(err:find("Unpark referenced fragment", 1, true), "parked fragments should require an explicit unpark before send")
end)

test("chat renderer flattens multiline block entries into buffer-safe lines", function()
  local render = require("neovim_codex.nvim.chat.render")

  local result = render.render({
    thread_id = "thr_flatten",
    blocks = {
      {
        id = "block_1",
        kind = "assistant_message",
        surface = "message_assistant",
        lines = {
          "### Response",
          "First line\nSecond line",
          "",
          "```lua\nprint('hi')\n```",
        },
        protocol = { item_type = "agentMessage", item = { id = "item_1" } },
      },
    },
  })

  eq(result.lines[1], "### Response")
  eq(result.lines[2], "First line")
  eq(result.lines[3], "Second line")
  eq(result.lines[4], "")
  eq(result.lines[5], "```lua")
  eq(result.lines[6], "print('hi')")
  eq(result.lines[7], "```")
end)

test("chat document renders assistant replies as markdown blocks", function()
  local document = require("neovim_codex.nvim.chat.document")
  local render = require("neovim_codex.nvim.chat.render")
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
      text = "First line\nSecond line",
    },
  })

  local doc = document.project_active(store:get_state())
  eq(doc.thread_id, "thr_1")
  eq(doc.blocks[1].kind, "turn_boundary")
  eq(doc.blocks[2].kind, "user_message")
  eq(doc.blocks[3].kind, "assistant_message")

  local result = render.render(doc)
  local body = table.concat(result.lines, "\n")
  assert(body:find("## Explain this change", 1, true), "render should derive a meaningful turn heading from the request")
  assert(body:find("### Request", 1, true), "render should include the request heading")
  assert(body:find("### Response", 1, true), "render should include a response heading")
  assert(body:find("First line", 1, true), "render should include assistant text")
  eq(result.blocks[3].surface, "message_assistant")
  eq(result.blocks[3].protocol.item_type, "agentMessage")
end)

test("chat document uses structured command actions for compact activity summaries", function()
  local document = require("neovim_codex.nvim.chat.document")
  local store = require("neovim_codex.core.store").new({ max_log_entries = 20 })

  store:dispatch({
    type = "thread_received",
    thread = {
      id = "thr_2",
      preview = "demo",
      ephemeral = false,
      modelProvider = "openai",
      createdAt = 1,
      updatedAt = 1,
      status = { type = "idle" },
      cwd = "/tmp/demo",
      turns = {},
    },
    activate = true,
    replace_turns = false,
  })
  store:dispatch({
    type = "turn_received",
    thread_id = "thr_2",
    turn = { id = "turn_2", status = "completed", items = {}, error = nil },
  })
  store:dispatch({
    type = "item_received",
    thread_id = "thr_2",
    turn_id = "turn_2",
    item = {
      type = "commandExecution",
      id = "item_context",
      status = "completed",
      command = [[/opt/homebrew/bin/zsh -lc "sed -n '1,120p' /Users/jaju/.codex/skills/prompt-control/SKILL.md"]],
      commandActions = {
        {
          type = "read",
          command = "sed -n '1,120p' /Users/jaju/.codex/skills/prompt-control/SKILL.md",
          name = "sed",
          path = "/Users/jaju/.codex/skills/prompt-control/SKILL.md",
        },
      },
      aggregatedOutput = "# Prompt Control",
      durationMs = 28,
    },
  })
  store:dispatch({
    type = "item_received",
    thread_id = "thr_2",
    turn_id = "turn_2",
    item = {
      type = "commandExecution",
      id = "item_search",
      status = "completed",
      command = [[/opt/homebrew/bin/zsh -lc "rg -n \"neovim-codex|codex.nvim|Codex\" README.md doc docs lua plugin -g '!**/*.min.*'"]],
      commandActions = {
        {
          type = "search",
          command = "rg -n 'neovim-codex|codex.nvim|Codex' README.md doc docs lua plugin",
          query = "neovim-codex|codex.nvim|Codex",
          path = "README.md doc docs lua plugin",
        },
      },
      aggregatedOutput = "README.md:1:# neovim-codex",
      durationMs = 31,
    },
  })
  store:dispatch({
    type = "item_received",
    thread_id = "thr_2",
    turn_id = "turn_2",
    item = {
      type = "commandExecution",
      id = "item_failed",
      status = "failed",
      command = "npm test",
      commandActions = {
        { type = "unknown", command = "npm test" },
      },
      aggregatedOutput = "tests failed",
      exitCode = 1,
    },
  })

  local doc = document.project_active(store:get_state())
  eq(doc.blocks[2].kind, "activity_summary")
  eq(doc.blocks[2].lines[1], "### Command {.foldable}")
  assert(doc.blocks[2].lines[3]:find("Loaded local instructions", 1, true), "context reads should collapse into a semantic command summary")
  eq(doc.blocks[3].kind, "activity_summary")
  eq(doc.blocks[3].lines[1], "### Command {.foldable}")
  assert(doc.blocks[3].lines[3]:find("Searched", 1, true), "search commands should summarize from structured command actions")
  eq(doc.blocks[4].kind, "command_detail")
  eq(doc.blocks[4].lines[1], "### Command {.foldable}")
  assert(doc.blocks[4].lines[2]:find("failed", 1, true), "failed commands should stay detailed")
  assert(doc.blocks[4].lines[6] == "```text", "failed commands should expose fenced output previews")
end)

test("chat document renders foldable file changes with diff fences", function()
  local document = require("neovim_codex.nvim.chat.document")
  local store = require("neovim_codex.core.store").new({ max_log_entries = 20 })

  store:dispatch({
    type = "thread_received",
    thread = {
      id = "thr_diff",
      preview = "demo",
      ephemeral = false,
      modelProvider = "openai",
      createdAt = 1,
      updatedAt = 1,
      status = { type = "idle" },
      cwd = "/tmp/demo",
      turns = {},
    },
    activate = true,
    replace_turns = false,
  })
  store:dispatch({
    type = "turn_received",
    thread_id = "thr_diff",
    turn = { id = "turn_diff", status = "completed", items = {}, error = nil },
  })
  store:dispatch({
    type = "item_received",
    thread_id = "thr_diff",
    turn_id = "turn_diff",
    item = {
      type = "fileChange",
      id = "item_diff",
      status = "completed",
      changes = {
        {
          path = "/tmp/demo/README.md",
          kind = "update",
          diff = "@@ -1 +1 @@\n-old\n+new",
        },
      },
    },
  })

  local doc = document.project_active(store:get_state())
  eq(doc.blocks[2].kind, "file_change_summary")
  eq(doc.blocks[2].lines[1], "### File Changes {.foldable}")
  eq(doc.blocks[2].lines[5], "```diff")
  eq(doc.blocks[2].lines[6], "@@ -1 +1 @@")
end)

test("file change review renderer prefers the turn diff and lists changed files", function()
  local review_render = require("neovim_codex.nvim.file_change_review.render")
  local rendered = review_render.render_review({
    request = {
      thread_id = "thr_diff",
      turn_id = "turn_diff",
      item_id = "item_diff",
      request_id = "req_diff",
      params = {
        reason = "Review the patch",
        grantRoot = "/tmp/demo",
      },
    },
    turn = {
      status = "completed",
    },
    changes = {
      {
        path = "/tmp/demo/README.md",
        kind = "update",
        diff = "@@ -1 +1 @@\n-old\n+new",
      },
    },
    diff = "@@ -1 +1 @@\n-old\n+new",
  }, {
    accept = "a",
    accept_for_session = "s",
    decline = "d",
    cancel = "c",
    help = "g?",
  })

  eq(rendered.title, "File Change Review")
  eq(rendered.lines[1], "# File Change Review")
  assert(rendered.lines[3]:find("%[s%] Approve session"), "review surface should advertise session approval")
  assert(table.concat(rendered.lines, "\n"):find("## Changed files", 1, true), "review surface should list changed files")
  assert(table.concat(rendered.lines, "\n"):find("## Turn Diff {.foldable}", 1, true), "review surface should prefer the aggregated turn diff")
  assert(table.concat(rendered.lines, "\n"):find("```diff", 1, true), "review surface should expose a diff fence")
end)


test("details renderer keeps verbose command data behind an inspector surface", function()
  local details = require("neovim_codex.nvim.chat.details")
  local rendered = details.render_block({
    kind = "command_detail",
    protocol = {
      item_type = "commandExecution",
      item = {
        type = "commandExecution",
        status = "completed",
        command = "rg -n 'Codex' README.md",
        cwd = "/tmp/demo",
        durationMs = 42,
        commandActions = {
          { type = "search", path = "README.md", query = "Codex" },
        },
        aggregatedOutput = "README.md:1:# neovim-codex",
      },
    },
    lines = { "- Searched `README.md` for `Codex`" },
  })

  eq(rendered.lines[1], "# Command · completed")
  assert(table.concat(rendered.lines, "\n"):find("## Command", 1, true), "details should include the full command")
  assert(table.concat(rendered.lines, "\n"):find("## Output", 1, true), "details should include aggregated output")
end)

test("workbench state tracks fragments and per-thread packet draft text", function()
  local selectors = require("neovim_codex.core.selectors")
  local store = require("neovim_codex.core.store").new({ max_log_entries = 20 })

  store:dispatch({
    type = "thread_received",
    thread = {
      id = "thr_workbench",
      preview = "demo",
      ephemeral = false,
      modelProvider = "openai",
      createdAt = 1,
      updatedAt = 1,
      status = { type = "idle" },
      cwd = "/tmp/demo",
      turns = {},
    },
    activate = true,
    replace_turns = false,
  })
  store:dispatch({
    type = "workbench_fragment_added",
    thread_id = "thr_workbench",
    fragment = {
      id = "frag_path",
      kind = "path_ref",
      label = "README.md",
      path = "/tmp/demo/README.md",
    },
  })
  store:dispatch({
    type = "workbench_message_updated",
    thread_id = "thr_workbench",
    message = "Cover this in the next turn",
  })

  local workbench = selectors.get_active_workbench(store:get_state())
  eq(selectors.workbench_fragment_count(store:get_state()), 1)
  eq(selectors.list_fragments(workbench)[1].id, "frag_path")
  eq(selectors.list_fragments(workbench)[1].handle, "f1")
  eq(selectors.workbench_message(workbench), "Cover this in the next turn")

  store:dispatch({ type = "workbench_fragment_removed", thread_id = "thr_workbench", fragment_id = "frag_path" })
  eq(selectors.workbench_fragment_count(store:get_state()), 0)
end)

test("packet compiler expands referenced fragment handles inline", function()
  local packet = require("neovim_codex.core.packet")
  local input, compiled, err = packet.build_input_items("Review [[f1]], [[f2]], and [[f3]].", {
    {
      id = "frag_path",
      handle = "f1",
      kind = "path_ref",
      label = "README.md",
      path = "/tmp/demo/README.md",
    },
    {
      id = "frag_code",
      handle = "f2",
      kind = "code_range",
      label = "src/app.ts:10-14",
      path = "/tmp/demo/src/app.ts",
      filetype = "typescript",
      range = { start_line = 10, end_line = 14 },
      text = "const value = 1;",
    },
    {
      id = "frag_note",
      handle = "f3",
      kind = "text_note",
      label = "Latest test run",
      text = "FAIL auth middleware\n1 failing test",
      filetype = "markdown",
      source = "neotest",
      category = "runtime",
    },
  })

  eq(err, nil)
  eq(input[1].type, "text")
  eq(compiled.referenced_handles[1], "f1")
  eq(compiled.referenced_handles[2], "f2")
  assert(input[1].text:find("Path reference: `~/README.md`", 1, true) == nil, "path rendering should preserve the actual path")
  assert(input[1].text:find("Path reference: `/tmp/demo/README.md`.", 1, true), "packet should inline referenced path fragments")
  assert(input[1].text:find("Code snapshot from `/tmp/demo/src/app.ts:10-14`:", 1, true), "packet should inline referenced code fragments")
  assert(input[1].text:find("```typescript", 1, true), "packet should preserve code fences for code fragments")
  assert(input[1].text:find("Context note `Latest test run` from `neotest` %(runtime%):", 1) ~= nil, "packet should inline referenced text note fragments")
  assert(input[1].text:find("```markdown", 1, true), "packet should preserve fences for text note fragments")
end)

test("packet compiler rejects unreferenced staged fragments", function()
  local packet = require("neovim_codex.core.packet")
  local input, compiled, err = packet.build_input_items("Only use [[f1]].", {
    { id = "frag_path", handle = "f1", kind = "path_ref", label = "README.md", path = "/tmp/demo/README.md" },
    { id = "frag_diag", handle = "f2", kind = "diagnostic", label = "TS2322 README.md:10", path = "/tmp/demo/README.md", range = { start_line = 10, end_line = 10 }, message = "Type mismatch", source = "tsserver", code = "TS2322" },
  })

  eq(input, nil)
  eq(compiled, nil)
  assert(err:find("f2", 1, true), "unreferenced handle should be reported")
end)

test("thread renderer accepts raw thread/read payloads", function()
  local renderer = require("neovim_codex.nvim.thread_renderer")
  local view = renderer.render_thread({
    id = "thr_raw",
    name = "Raw thread",
    status = { type = "idle" },
    turns = {
      {
        id = "turn_raw",
        status = "completed",
        items = {
          {
            id = "user_raw",
            type = "userMessage",
            content = {
              {
                type = "text",
                text = "Summarize the current setup.",
              },
            },
          },
          {
            id = "assistant_raw",
            type = "agentMessage",
            text = "The setup is stable.",
          },
        },
      },
    },
  }, { title = "# Codex Thread" })

  local body = table.concat(view.lines, "\n")
  assert(body:find("Summarize the current setup.", 1, true), "raw thread report should include the user message")
  assert(body:find("The setup is stable.", 1, true), "raw thread report should include the assistant message")
  assert((view.footer or ""):find("thread thr_raw", 1, true), "raw thread footer should use a short thread id")
  assert((view.footer or ""):find("Raw thread", 1, true), "raw thread footer should include the thread title")
  assert((view.footer or ""):find("1 turn", 1, true), "raw thread footer should include the turn count")
end)

test("client thread_unarchive restores archived thread state", function()
  local client, store, calls = new_test_client()

  store:dispatch({
    type = "thread_received",
    thread = {
      id = "thr_restore",
      preview = "demo",
      ephemeral = false,
      modelProvider = "openai",
      createdAt = 1,
      updatedAt = 1,
      status = { type = "idle" },
      cwd = "/tmp/demo",
      turns = {},
    },
    activate = false,
    replace_turns = false,
  })
  store:dispatch({ type = "thread_archived", thread_id = "thr_restore" })

  local callback_result = nil
  client:thread_unarchive({ threadId = "thr_restore" }, function(err, result)
    eq(err, nil)
    callback_result = result
  end)

  eq(calls[1].method, "thread/unarchive")
  eq(calls[1].params.threadId, "thr_restore")
  eq(callback_result.thread.id, "thr_restore")
  eq(store:get_state().threads.by_id.thr_restore.archived, false)
end)

test("client thread_compact_start uses the compact RPC", function()
  local client, _, calls = new_test_client()
  local callback_result = nil

  client:thread_compact_start({ threadId = "thr_compact" }, function(err, result)
    eq(err, nil)
    callback_result = result
  end)

  eq(calls[1].method, "thread/compact/start")
  eq(calls[1].params.threadId, "thr_compact")
  eq(type(callback_result), "table")
end)

test("client turn_steer uses expectedTurnId precondition", function()
  local client, _, calls = new_test_client()
  local callback_result = nil

  client:turn_steer({
    threadId = "thr_steer",
    expectedTurnId = "turn_steer",
    input = { { type = "text", text = "Focus on tests first." } },
  }, function(err, result)
    eq(err, nil)
    callback_result = result
  end)

  eq(calls[1].method, "turn/steer")
  eq(calls[1].params.threadId, "thr_steer")
  eq(calls[1].params.expectedTurnId, "turn_steer")
  eq(calls[1].params.input[1].text, "Focus on tests first.")
  eq(callback_result.turnId, "turn_steer")
end)

test("thread runtime model labels include upgrade and availability hints", function()
  local runtime = require("neovim_codex.nvim.thread_runtime")
  local model = {
    model = "gpt-5.2-codex",
    displayName = "gpt-5.2-codex",
    description = "Balanced coding model",
    hidden = false,
    isDefault = true,
    upgrade = nil,
    upgradeInfo = {
      model = "gpt-5.4",
      upgradeCopy = "Try gpt-5.4 for higher quality.",
      modelLink = nil,
      migrationMarkdown = nil,
    },
    availabilityNux = { message = "Available on upgraded accounts." },
    supportedReasoningEfforts = {},
  }

  local label = runtime.model_choice_label(model)
  assert(label:find("gpt%-5%.4"), "model picker label should include upgrade hints")
  assert(label:find("Available on upgraded accounts"), "model picker label should include availability hints")
  local menu_label = runtime.model_menu_label("gpt-5.2-codex", { model })
  assert(menu_label:find("gpt%-5%.2%-codex"), "menu label should resolve against the catalog")
end)

test("server request protocol builds permission grant choices", function()
  local protocol = require("neovim_codex.nvim.server_requests.protocol")
  local choices = protocol.choice_entries({
    method = protocol.methods().permissions_approval,
    params = {
      permissions = {
        fileSystem = {
          write = { "/tmp/demo" },
        },
      },
    },
  })

  eq(#choices, 3)
  eq(choices[1].label, "Grant requested permissions for this turn")
  eq(choices[1].payload.scope, "turn")
  eq(choices[1].payload.permissions.fileSystem.write[1], "/tmp/demo")
  eq(choices[2].payload.scope, "session")
  eq(next(choices[3].payload.permissions), nil)
end)

test("server request renderer shows permission requests with grant semantics", function()
  local request_render = require("neovim_codex.nvim.server_requests.render")
  local rendered = request_render.render_request({
    method = "item/permissions/requestApproval",
    thread_id = "thr_perm",
    turn_id = "turn_perm",
    item_id = "item_perm",
    params = {
      reason = "Select a workspace root",
      permissions = {
        fileSystem = {
          write = { "/tmp/demo", "/tmp/shared" },
        },
      },
    },
  }, {
    respond = "<CR>",
    accept = "a",
    accept_for_session = "s",
    decline = "d",
    help = "g?",
  })

  local body = table.concat(rendered.lines, "\n")
  eq(rendered.title, "Permission Request")
  assert(body:find("# Permission request", 1, true), "permission requests should get a dedicated title")
  assert(body:find("Grant requested permissions for this session", 1, true), "permission requests should show the session grant action")
  assert(body:find("Only the granted subset is sent back to Codex.", 1, true), "permission requests should explain sparse grants")
end)

test("server request renderer keeps MCP elicitations conservative", function()
  local request_render = require("neovim_codex.nvim.server_requests.render")
  local rendered = request_render.render_request({
    method = "mcpServer/elicitation/request",
    thread_id = "thr_mcp",
    turn_id = "turn_mcp",
    params = {
      serverName = "docs",
      mode = "url",
      message = "Open the sign-in page.",
      url = "https://example.com/auth",
    },
  }, {
    respond = "<CR>",
    decline = "d",
    cancel = "c",
    help = "g?",
  })

  local body = table.concat(rendered.lines, "\n")
  eq(rendered.title, "MCP Elicitation")
  assert(body:find("Decline", 1, true), "MCP requests should expose decline")
  assert(body:find("Cancel", 1, true), "MCP requests should expose cancel")
  assert(body:find("decline/cancel directly", 1, true), "MCP requests should explain the conservative fallback")
end)

test("server request renderer falls back to a read-only generic view", function()
  local request_render = require("neovim_codex.nvim.server_requests.render")
  local rendered = request_render.render_request({
    method = "item/example/requestApproval",
    request_id = "req_generic",
    thread_id = "thr_generic",
    turn_id = "turn_generic",
    item_id = "item_generic",
    params = {
      example = "value",
    },
  }, {
    help = "g?",
  })

  local body = table.concat(rendered.lines, "\n")
  assert(body:find("This request type does not have a dedicated interactive handler", 1, true), "unknown requests should stay readable without pretending to be supported")
  assert(body:find("```json", 1, true), "unknown requests should still show their raw params")
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

