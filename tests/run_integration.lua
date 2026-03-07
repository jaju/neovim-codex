local script_path = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fs.dirname(vim.fs.dirname(script_path))
local nui_path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "nui.nvim")

vim.opt.runtimepath:append(repo_root)
if vim.fn.isdirectory(nui_path) == 1 then
  vim.opt.runtimepath:append(nui_path)
end
vim.cmd("runtime plugin/neovim_codex.lua")
vim.o.showmode = false

local codex = require("neovim_codex")
codex.setup({})

assert(vim.fn.exists(":CodexStart") == 2, "CodexStart command should exist")
assert(vim.fn.exists(":CodexSmoke") == 2, "CodexSmoke command should exist")
assert(vim.fn.exists(":CodexChat") == 2, "CodexChat command should exist")
assert(vim.fn.exists(":CodexSend") == 2, "CodexSend command should exist")
assert(vim.fn.exists(":CodexThreadNew") == 2, "CodexThreadNew command should exist")
assert(vim.fn.exists(":CodexThreads") == 2, "CodexThreads command should exist")
assert(vim.fn.exists(":CodexThreadRead") == 2, "CodexThreadRead command should exist")
assert(vim.fn.exists(":CodexRequest") == 2, "CodexRequest command should exist")
assert(type(require("neovim_codex.health").check) == "function", "health module should expose check()")
assert(pcall(require, "nui.popup"), "nui.nvim should be available on runtimepath")

local report = codex.run_smoke({
  open_report = false,
  notify = false,
  stop_after = false,
  timeout_ms = 4000,
})

assert(report.success, table.concat(report.lines, "\n"))
assert(report.connection.initialized == true, "smoke should reach initialized state")

codex.chat()
local chat_state = codex.get_chat_state()
assert(chat_state.visible == true, "chat overlay should be visible after opening")
assert(chat_state.transcript_buf and vim.api.nvim_buf_is_valid(chat_state.transcript_buf), "chat transcript buffer should exist")
assert(chat_state.composer_buf and vim.api.nvim_buf_is_valid(chat_state.composer_buf), "chat composer buffer should exist")
assert(vim.bo[chat_state.transcript_buf].filetype == "markdown", "transcript should use markdown")
assert(vim.bo[chat_state.composer_buf].filetype == "markdown", "composer should use markdown")
assert(vim.bo[chat_state.composer_buf].buftype == "nofile", "composer should be a normal scratch buffer")

codex.chat()
local hidden_chat_state = codex.get_chat_state()
assert(hidden_chat_state.visible == false, "chat command should toggle the overlay closed")
assert(hidden_chat_state.container_win == nil or not vim.api.nvim_win_is_valid(hidden_chat_state.container_win), "container window should be closed when the overlay hides")

codex.chat()
assert(codex.get_chat_state().visible == true, "chat command should toggle the overlay open again")

codex.open_events()
local event_viewers = codex.get_chat_state().viewers
assert(event_viewers.top and event_viewers.top.key == "events", "events should open in the stacked viewer layer")

local inspect_block, inspect_err = codex.inspect_current_block({ notify = false })
assert(inspect_err == nil, inspect_err or "inspect should succeed for the current transcript block")
assert(inspect_block ~= nil, "inspect should return the selected block")
local detail_viewers = codex.get_chat_state().viewers
assert(detail_viewers.top and detail_viewers.top.key == "details", "details should become the top viewer after inspect")
require("neovim_codex.nvim.presentation").close_viewers()

local thread_result, thread_err = codex.new_thread({
  notify = false,
  open_chat = false,
  cwd = repo_root,
  timeout_ms = 4000,
})
assert(thread_err == nil, thread_err or "thread start failed")
assert(thread_result and thread_result.thread and thread_result.thread.id, "thread start should return a thread id")

local list_result, list_err = codex.list_threads({
  notify = false,
  cwd = repo_root,
  limit = 10,
  timeout_ms = 4000,
})
assert(list_err == nil, list_err or "thread list failed")
assert(type(list_result.data) == "table", "thread list should return a data array")

local read_result, read_err = codex.read_thread({
  thread_id = thread_result.thread.id,
  notify = false,
  include_turns = false,
  timeout_ms = 4000,
})
assert(read_err == nil, read_err or "thread read failed")
assert(read_result.thread.id == thread_result.thread.id, "thread/read should return the same thread")

assert(codex.get_state().threads.active_id == thread_result.thread.id, "new thread should become active")

if #list_result.data > 0 then
  local resume_result, resume_err = codex.resume_thread({
    thread_id = list_result.data[1].id,
    notify = false,
    open_chat = false,
    timeout_ms = 4000,
  })
  assert(resume_err == nil, resume_err or "thread resume failed")
  assert(resume_result.thread.id == list_result.data[1].id, "thread/resume should return the requested stored thread")
  assert(codex.get_state().threads.active_id == list_result.data[1].id, "resumed stored thread should become active")
end


require("neovim_codex.nvim.presentation").close_viewers()

local request_store = require("neovim_codex.core.store").new({ max_log_entries = 20 })
local selectors = require("neovim_codex.core.selectors")
local captured_command = nil
local captured_tool = nil
local request_manager = require("neovim_codex.nvim.server_requests").new(codex.get_config(), {
  notify = function() end,
  respond_command = function(request, payload)
    captured_command = { request = request, payload = payload }
    return true, nil
  end,
  respond_file_change = function(_, _)
    return true, nil
  end,
  respond_tool_input = function(request, payload)
    captured_tool = { request = request, payload = payload }
    return true, nil
  end,
})
request_manager:attach(request_store)

request_store:dispatch({
  type = "server_request_received",
  request = {
    method = "item/commandExecution/requestApproval",
    id = "req_command",
    params = {
      threadId = "thr_req",
      turnId = "turn_req",
      itemId = "item_req",
      command = "ls -la",
      cwd = repo_root,
      commandActions = {
        { type = "listFiles", path = repo_root },
      },
    },
  },
})
vim.wait(1000, function()
  local top = require("neovim_codex.nvim.viewer_stack").inspect().top
  return top and top.key == "server-request"
end, 20)
local request_viewers = require("neovim_codex.nvim.viewer_stack").inspect()
assert(request_viewers.top and request_viewers.top.key == "server-request", "pending server request should open in the stacked viewer layer")
local active_request = selectors.get_active_request(request_store:get_state())
assert(active_request and active_request.method == "item/commandExecution/requestApproval", "command approval request should become active")
local responded_ok, responded_err = request_manager:respond_with_decision(active_request, "accept")
assert(responded_err == nil, responded_err or "command approval should respond")
assert(responded_ok == true, "command approval should report success")
assert(captured_command and captured_command.payload.decision == "accept", "command approval payload should be forwarded")
request_store:dispatch({ type = "server_request_resolved", request_id = "req_command" })
vim.wait(1000, function()
  local top = require("neovim_codex.nvim.viewer_stack").inspect().top
  return top == nil or top.key ~= "server-request"
end, 20)

local original_input = vim.ui.input
vim.ui.input = function(opts, callback)
  callback("captured answer")
end
request_store:dispatch({
  type = "server_request_received",
  request = {
    method = "item/tool/requestUserInput",
    id = "req_tool",
    params = {
      threadId = "thr_req",
      turnId = "turn_req",
      itemId = "item_tool",
      questions = {
        {
          id = "question_one",
          header = "Question",
          question = "What should we do next?",
          isOther = false,
          isSecret = false,
          options = vim.NIL,
        },
      },
    },
  },
})
local tool_ok, tool_err = request_manager:respond_current()
vim.ui.input = original_input
assert(tool_err == nil, tool_err or "tool question should collect an answer")
assert(tool_ok == true, "tool question should report success")
assert(captured_tool ~= nil, "tool answer payload should be forwarded")
assert(captured_tool.payload.answers.question_one.answers[1] == "captured answer", "tool answer should be forwarded with the expected shape")
request_store:dispatch({ type = "server_request_resolved", request_id = "req_tool" })
require("neovim_codex.nvim.presentation").close_viewers()

codex.stop()
vim.wait(4000, function()
  return codex.get_state().connection.status == "stopped"
end, 50)
assert(codex.get_state().connection.status == "stopped", "runtime should stop cleanly")

print("ok - integration smoke and overlay chat lifecycle")
