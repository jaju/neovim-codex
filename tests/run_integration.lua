local script_path = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fs.dirname(vim.fs.dirname(script_path))
local nui_path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "nui.nvim")

vim.opt.runtimepath:append(repo_root)
if vim.fn.isdirectory(nui_path) == 1 then
  vim.opt.runtimepath:append(nui_path)
end
vim.cmd("runtime plugin/neovim_codex.lua")
vim.o.showmode = false

local function termcodes(value)
  return vim.api.nvim_replace_termcodes(value, true, false, true)
end

local codex = require("neovim_codex")
codex.setup({})

assert(vim.fn.exists(":CodexStart") == 2, "CodexStart command should exist")
assert(vim.fn.exists(":CodexSmoke") == 2, "CodexSmoke command should exist")
assert(vim.fn.exists(":CodexChat") == 2, "CodexChat command should exist")
assert(vim.fn.exists(":CodexSend") == 2, "CodexSend command should exist")
assert(vim.fn.exists(":CodexThreadNew") == 2, "CodexThreadNew command should exist")
assert(vim.fn.exists(":CodexThreads") == 2, "CodexThreads command should exist")
assert(vim.fn.exists(":CodexThreadRead") == 2, "CodexThreadRead command should exist")
assert(vim.fn.exists(":CodexThreadRename") == 2, "CodexThreadRename command should exist")
assert(vim.fn.exists(":CodexRequest") == 2, "CodexRequest command should exist")
assert(vim.fn.exists(":CodexWorkbench") == 2, "CodexWorkbench command should exist")
assert(vim.fn.exists(":CodexCompose") == 2, "CodexCompose command should exist")
assert(vim.fn.exists(":CodexCapturePath") == 2, "CodexCapturePath command should exist")
assert(vim.fn.exists(":CodexCaptureSelection") == 2, "CodexCaptureSelection command should exist")
assert(vim.fn.exists(":CodexCaptureDiagnostic") == 2, "CodexCaptureDiagnostic command should exist")
assert(vim.fn.exists(":CodexShortcuts") == 2, "CodexShortcuts command should exist")
assert(vim.fn.exists(":CodexCaptureBlock") == 0, "CodexCaptureBlock command should not exist")
assert(type(require("neovim_codex.health").check) == "function", "health module should expose check()")
assert(pcall(require, "nui.popup"), "nui.nvim should be available on runtimepath")

local report = codex.run_smoke({
  open_report = false,
  notify = false,
  stop_after = false,
  timeout_ms = 8000,
})

assert(report.success, table.concat(report.lines, "\n"))
assert(report.connection.initialized == true, "smoke should reach initialized state")

local base_window = vim.api.nvim_get_current_win()
codex.chat()
local chat_state = codex.get_chat_state()
assert(chat_state.visible == true, "chat overlay should be visible after opening")
assert(chat_state.transcript_buf and vim.api.nvim_buf_is_valid(chat_state.transcript_buf), "chat transcript buffer should exist")
assert(chat_state.composer_buf and vim.api.nvim_buf_is_valid(chat_state.composer_buf), "chat composer buffer should exist")
assert(vim.bo[chat_state.transcript_buf].filetype == "markdown", "transcript should use markdown")
assert(vim.bo[chat_state.composer_buf].filetype == "markdown", "composer should use markdown")
assert(vim.bo[chat_state.composer_buf].buftype == "nofile", "composer should be a normal scratch buffer")

vim.api.nvim_set_current_win(chat_state.transcript_win)
vim.api.nvim_feedkeys(termcodes("<C-w>w"), "xt", false)
vim.wait(1000, function()
  return codex.get_chat_state().composer_win == vim.api.nvim_get_current_win()
end, 20)
assert(codex.get_chat_state().composer_win == vim.api.nvim_get_current_win(), "Ctrl-w w should switch from the transcript to the composer inside the overlay")

vim.api.nvim_feedkeys(termcodes("<C-w>w"), "xt", false)
vim.wait(1000, function()
  return codex.get_chat_state().transcript_win == vim.api.nvim_get_current_win()
end, 20)
assert(codex.get_chat_state().transcript_win == vim.api.nvim_get_current_win(), "Ctrl-w w should switch back to the transcript inside the overlay")
assert(vim.api.nvim_get_mode().mode == "n", "transcript focus should leave insert mode")

vim.api.nvim_set_current_win(base_window)
vim.wait(1000, function()
  return codex.get_chat_state().visible == false
end, 20)
assert(codex.get_chat_state().visible == false, "leaving plugin-owned windows should close the chat overlay")

codex.chat()
assert(codex.get_chat_state().visible == true, "chat command should reopen the overlay after focus escape")

local visible_again_state = codex.get_chat_state()
vim.api.nvim_set_current_win(visible_again_state.composer_win)
vim.cmd("startinsert")
codex.chat()
local hidden_chat_state = codex.get_chat_state()
assert(hidden_chat_state.visible == false, "chat command should toggle the overlay closed")
assert(hidden_chat_state.container_win == nil or not vim.api.nvim_win_is_valid(hidden_chat_state.container_win), "container window should be closed when the overlay hides")
assert(hidden_chat_state.transcript_win == nil or not vim.api.nvim_win_is_valid(hidden_chat_state.transcript_win), "transcript window should close when the overlay hides")
assert(hidden_chat_state.composer_win == nil or not vim.api.nvim_win_is_valid(hidden_chat_state.composer_win), "composer window should close when the overlay hides")

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
  timeout_ms = 8000,
})
assert(thread_err == nil, thread_err or "thread start failed")
assert(thread_result and thread_result.thread and thread_result.thread.id, "thread start should return a thread id")

local list_result, list_err = codex.list_threads({
  notify = false,
  cwd = repo_root,
  limit = 10,
  timeout_ms = 8000,
})
assert(list_err == nil, list_err or "thread list failed")
assert(type(list_result.data) == "table", "thread list should return a data array")

local read_result, read_err = codex.read_thread({
  thread_id = thread_result.thread.id,
  notify = false,
  include_turns = false,
  timeout_ms = 8000,
})
assert(read_err == nil, read_err or "thread read failed")
assert(read_result.thread.id == thread_result.thread.id, "thread/read should return the same thread")

assert(codex.get_state().threads.active_id == thread_result.thread.id, "new thread should become active")

if #list_result.data > 0 then
  local resume_result, resume_err = codex.resume_thread({
    thread_id = list_result.data[1].id,
    notify = false,
    open_chat = false,
    timeout_ms = 8000,
  })
  assert(resume_err == nil, resume_err or "thread resume failed")
  assert(resume_result.thread.id == list_result.data[1].id, "thread/resume should return the requested stored thread")
  assert(codex.get_state().threads.active_id == list_result.data[1].id, "resumed stored thread should become active")
end

local capture_thread_result, capture_thread_err = codex.new_thread({
  notify = false,
  open_chat = false,
  cwd = repo_root,
  timeout_ms = 8000,
})
assert(capture_thread_err == nil, capture_thread_err or "capture thread start failed")
assert(capture_thread_result and capture_thread_result.thread and capture_thread_result.thread.id, "capture flow should run against a fresh thread")
assert(codex.get_state().threads.active_id == capture_thread_result.thread.id, "fresh capture thread should become active")

local rename_result, rename_err = codex.rename_thread({ name = "Workbench thread", notify = false, timeout_ms = 8000 })
assert(rename_err == nil, rename_err or "thread rename should succeed")
assert(rename_result ~= nil, "thread rename should return a result")
vim.wait(1000, function()
  return codex.get_state().threads.by_id[capture_thread_result.thread.id].name == "Workbench thread"
end, 20)
assert(codex.get_state().threads.by_id[capture_thread_result.thread.id].name == "Workbench thread", "thread rename should update the active thread name")

require("neovim_codex.nvim.presentation").close_viewers()

vim.cmd(string.format("edit %s", vim.fn.fnameescape(repo_root .. "/README.md")))
local path_fragment, path_err = codex.capture_current_file({ notify = false })
assert(path_err == nil, path_err or "current file capture should succeed")
assert(path_fragment.kind == "path_ref", "current file capture should stage a path_ref fragment")
assert(path_fragment.handle == "f1", "first captured fragment should get the first stable handle")
assert(codex.get_workbench_state().thread_id == codex.get_state().threads.active_id, "workbench should stay thread-local to the active thread")
assert(codex.get_workbench_state().workbench.fragments_order[1] == path_fragment.id, "captured file should appear in the active workbench")

codex.toggle_workbench()
assert(codex.get_workbench_state().tray.visible == true, "workbench tray should open")
local tray_viewers = require("neovim_codex.nvim.viewer_stack").inspect()
assert(tray_viewers.top and tray_viewers.top.key == "workbench-tray", "workbench tray should open through the stacked viewer layer")
codex.toggle_workbench()
assert(codex.get_workbench_state().tray.visible == false, "workbench tray should toggle closed")

vim.fn.setpos("'<", { 0, 1, 1, 0 })
vim.fn.setpos("'>", { 0, 3, 1, 0 })
local selection_fragment, selection_err = codex.capture_visual_selection({ notify = false })
assert(selection_err == nil, selection_err or "visual selection capture should succeed")
assert(selection_fragment.kind == "code_range", "visual selection capture should stage a code_range fragment")
assert(selection_fragment.handle == "f2", "second captured fragment should get the second stable handle")

local diagnostic_ns = vim.api.nvim_create_namespace("neovim_codex_test")
vim.diagnostic.set(diagnostic_ns, 0, {
  {
    lnum = 0,
    end_lnum = 0,
    col = 0,
    end_col = 4,
    severity = vim.diagnostic.severity.ERROR,
    message = "Title formatting is inconsistent",
    source = "markdownlint",
    code = "MD001",
  },
})
vim.api.nvim_win_set_cursor(0, { 1, 1 })
local diagnostic_fragment, diagnostic_err = codex.capture_current_diagnostic({ notify = false })
assert(diagnostic_err == nil, diagnostic_err or "diagnostic capture should succeed")
assert(diagnostic_fragment.kind == "diagnostic", "diagnostic capture should stage a diagnostic fragment")
assert(diagnostic_fragment.handle == "f3", "third captured fragment should get the third stable handle")

local before_review_count = #codex.get_workbench_state().workbench.fragments_order
local review_result, review_err = codex.open_compose_review({ seed_message = "Preserve this review draft with [[f1]], [[f2]], and [[f3]]." })
assert(review_err == nil, review_err or "compose review should open when requested")
assert(review_result ~= nil, "compose review should return state when opened")
local review_state = codex.get_workbench_state().review
assert(review_state.visible == true, "compose review should open when requested")
assert(review_state.thread_id == codex.get_state().threads.active_id, "compose review should show the active thread")
assert(#review_state.fragments == before_review_count, "compose review should show the staged fragments")
assert(codex.get_workbench_state().workbench.draft_message == "Preserve this review draft with [[f1]], [[f2]], and [[f3]].", "compose review should seed the initial packet template")
local review_viewers = require("neovim_codex.nvim.viewer_stack").inspect()
assert(review_viewers.top and review_viewers.top.key == "compose-review", "compose review should open through the stacked viewer layer")
assert(review_state.fragments[1].handle == "f1", "compose review should display the staged fragment handles")

codex.open_compose_review({ seed_message = "Do not overwrite this." })
assert(codex.get_workbench_state().workbench.draft_message == "Preserve this review draft with [[f1]], [[f2]], and [[f3]].", "compose review should not overwrite an existing packet template")

require("neovim_codex.nvim.presentation").close_viewers()
local review_closed = codex.get_workbench_state().review
assert(review_closed.visible == false, "compose review should report hidden after viewer close")
local viewers_after_close = require("neovim_codex.nvim.viewer_stack").inspect()
assert(viewers_after_close.top == nil, "compose review close should not leave a stacked viewer shell behind")

vim.cmd("enew")
local invalid_path, invalid_path_err = codex.capture_current_file({ notify = false })
assert(invalid_path == nil, "scratch buffer should not capture a path fragment")
assert(invalid_path_err == "Current buffer is not backed by a file" or invalid_path_err == "Current buffer is not a normal file buffer", "scratch buffer path capture should fail cleanly")

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
  return selectors.get_active_request(request_store:get_state()) ~= nil
end, 20)
local active_request = selectors.get_active_request(request_store:get_state())
assert(active_request and active_request.method == "item/commandExecution/requestApproval", "command approval request should become active")
local reopened_request, reopen_err = request_manager:open_current()
assert(reopen_err == nil, reopen_err or "request viewer should reopen from the active request")
assert(reopened_request and reopened_request.request_id == "req_command", "request viewer should reopen the active command request")
local request_viewers = require("neovim_codex.nvim.viewer_stack").inspect()
assert(request_viewers.top and request_viewers.top.key == "server-request", "pending server request should open in the stacked viewer layer")
assert(vim.api.nvim_get_mode().mode == "n", "request viewer should open in normal mode")
vim.api.nvim_feedkeys(termcodes("s"), "xt", false)
vim.wait(1000, function()
  return captured_command ~= nil
end, 20)
assert(captured_command and captured_command.payload.decision == "acceptForSession", "command approval payload should honor the session shortcut")
request_store:dispatch({ type = "server_request_resolved", request_id = "req_command" })
vim.wait(1000, function()
  local top = require("neovim_codex.nvim.viewer_stack").inspect().top
  return top == nil or top.key ~= "server-request"
end, 20)

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
vim.schedule(function()
  vim.wait(1000, function()
    return request_manager.input_session ~= nil and request_manager.input_bufnr ~= nil and vim.api.nvim_buf_is_valid(request_manager.input_bufnr)
  end, 20)
  assert(request_manager.input_session ~= nil, "tool answer popup should activate an input session")
  vim.api.nvim_buf_set_lines(request_manager.input_bufnr, 6, -1, false, { "captured answer" })
  request_manager.input_session.text = "captured answer"
  request_manager.input_session.done = true
  require("neovim_codex.nvim.viewer_stack").close("server-request-input")
end)
local tool_ok, tool_err = request_manager:respond_current()
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
