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
  assert(body:find("**Request**", 1, true), "render should include the request label")
  assert(body:find("### Response · First line Second line", 1, true), "render should include a meaningful response heading")
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
  assert(doc.blocks[2].lines[1]:find("Loaded local instructions", 1, true), "context reads should collapse into a context activity")
  eq(doc.blocks[3].kind, "activity_summary")
  assert(doc.blocks[3].lines[1]:find("Searched", 1, true), "search commands should summarize from structured command actions")
  eq(doc.blocks[4].kind, "command_detail")
  assert(doc.blocks[4].lines[1]:find("failed", 1, true), "failed commands should stay detailed")
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
  local input, compiled, err = packet.build_input_items("Review [[f1]] before changing [[f2]].", {
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
  })

  eq(err, nil)
  eq(input[1].type, "text")
  eq(compiled.referenced_handles[1], "f1")
  eq(compiled.referenced_handles[2], "f2")
  assert(input[1].text:find("The relevant file path is `~/README.md`", 1, true) == nil, "path rendering should preserve the actual path")
  assert(input[1].text:find("The relevant file path is `/tmp/demo/README.md`.", 1, true), "packet should inline referenced path fragments")
  assert(input[1].text:find("The relevant code snippet from `/tmp/demo/src/app.ts:10-14` is:", 1, true), "packet should inline referenced code fragments")
  assert(input[1].text:find("```typescript", 1, true), "packet should preserve code fences for code fragments")
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
