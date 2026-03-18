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

local function count_chat_shell_windows()
  local count = 0
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[winid].neovim_codex_chat_shell == true then
      count = count + 1
    end
  end
  return count
end

local codex = require("neovim_codex")
local selectors = require("neovim_codex.core.selectors")
local test_thread_cwd = vim.fn.tempname() .. "-neovim-codex-threads"

vim.fn.mkdir(test_thread_cwd, "p")

codex.setup({})

assert(vim.fn.exists(":CodexStart") == 2, "CodexStart command should exist")
assert(vim.fn.exists(":CodexSmoke") == 2, "CodexSmoke command should exist")
assert(vim.fn.exists(":CodexChat") == 2, "CodexChat command should exist")
assert(vim.fn.exists(":CodexSend") == 2, "CodexSend command should exist")
assert(vim.fn.exists(":CodexThreadNew") == 2, "CodexThreadNew command should exist")
assert(vim.fn.exists(":CodexThreads") == 2, "CodexThreads command should exist")
assert(vim.fn.exists(":CodexThreadRead") == 2, "CodexThreadRead command should exist")
assert(vim.fn.exists(":CodexThreadRename") == 2, "CodexThreadRename command should exist")
assert(vim.fn.exists(":CodexThreadUnarchive") == 2, "CodexThreadUnarchive command should exist")
assert(vim.fn.exists(":CodexThreadCompact") == 2, "CodexThreadCompact command should exist")
assert(vim.fn.exists(":CodexRequest") == 2, "CodexRequest command should exist")
assert(vim.fn.exists(":CodexReview") == 2, "CodexReview command should exist")
assert(vim.fn.exists(":CodexWorkbench") == 2, "CodexWorkbench command should exist")
assert(vim.fn.exists(":CodexCompose") == 2, "CodexCompose command should exist")
assert(vim.fn.exists(":CodexSteer") == 2, "CodexSteer command should exist")
assert(vim.fn.exists(":CodexCapturePath") == 2, "CodexCapturePath command should exist")
assert(vim.fn.exists(":CodexCaptureSelection") == 2, "CodexCaptureSelection command should exist")
assert(vim.fn.exists(":CodexCaptureDiagnostic") == 2, "CodexCaptureDiagnostic command should exist")
assert(type(codex.capture_text_fragment) == "function", "capture_text_fragment API should exist")
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

vim.api.nvim_set_current_win(codex.get_chat_state().composer_win)
vim.cmd("startinsert")
vim.api.nvim_set_current_win(codex.get_chat_state().transcript_win)
vim.wait(1000, function()
  return vim.api.nvim_get_mode().mode == "n"
end, 20)
assert(vim.api.nvim_get_mode().mode == "n", "transcript focus should force normal mode even when entered from insert mode")

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
assert(codex.get_chat_state().mode == "rail", "chat toggle should reopen in rail mode")
assert(count_chat_shell_windows() == 3, "chat reopen should leave exactly one mounted shell")

vim.cmd("CodexChatReader")
assert(codex.get_chat_state().mode == "reader", "reader command should switch the shell into reader mode")
assert(count_chat_shell_windows() == 3, "reader mode should leave exactly one mounted shell")
vim.api.nvim_set_current_win(codex.get_chat_state().composer_win)
vim.api.nvim_feedkeys(termcodes("gR"), "xt", false)
vim.wait(1000, function()
  return codex.get_chat_state().mode == "rail"
end, 20)
assert(codex.get_chat_state().mode == "rail", "gR should switch the shell back to rail mode")
assert(count_chat_shell_windows() == 3, "toggling back to rail should not leave stale shell windows behind")

codex.setup({
  keymaps = {
    global = {
      chat = "<leader>cc",
      request = "<leader>cr",
      shortcuts = "<leader>c?",
      thread_unarchive = "<leader>cu",
      thread_compact = "<leader>ck",
      turn_steer = "<leader>ct",
    },
  },
})

local shortcuts_surface, shortcut_lines = codex.open_shortcuts({ surface = "composer" })
assert(shortcuts_surface == "composer", "shortcut sheet should target the requested surface")
local shortcuts_body = table.concat(shortcut_lines, "\n")
assert(shortcuts_body:find("## This surface", 1, true), "shortcut sheet should show the current surface lane")
assert(shortcuts_body:find("## Global fast", 1, true), "shortcut sheet should show the fast global lane")
assert(shortcuts_body:find("## Global workflow", 1, true), "shortcut sheet should show the workflow global lane")
assert(shortcuts_body:find("g? / <F1>", 1, true), "shortcut sheet should explain the local help entrypoints")
assert(shortcuts_body:find("Edit the active thread settings", 1, true), "shortcut sheet should expose the local thread settings path")
assert(shortcuts_body:find("Restore an archived thread", 1, true), "shortcut sheet should expose thread restore actions in the workflow lane")
assert(shortcuts_body:find("Start manual history compaction", 1, true), "shortcut sheet should expose thread compaction in the workflow lane")
assert(shortcuts_body:find("Steer the running Codex turn", 1, true), "shortcut sheet should expose global steer actions in the workflow lane")
assert(shortcuts_body:find("Steer the running turn with the current draft", 1, true), "shortcut sheet should expose the composer-local steer path")
require("neovim_codex.nvim.presentation").close_viewers()

vim.cmd("startinsert")
local shortcuts_surface_insert, _ = codex.open_shortcuts({ surface = "composer" })
assert(shortcuts_surface_insert == "composer", "shortcut sheet should still target the requested surface from insert mode")
assert(vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i", "shortcut sheet should force normal mode on read-only reports")
require("neovim_codex.nvim.presentation").close_viewers()

local aux_buf = vim.api.nvim_create_buf(false, true)
local aux_win = vim.api.nvim_open_win(aux_buf, true, {
  relative = "editor",
  row = 2,
  col = 4,
  width = 24,
  height = 4,
  style = "minimal",
})
assert(codex.get_chat_state().visible == true, "chat should remain visible while an auxiliary float is focused")
vim.api.nvim_win_close(aux_win, true)

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
  cwd = test_thread_cwd,
  timeout_ms = 8000,
})
assert(thread_err == nil, thread_err or "thread start failed")
assert(thread_result and thread_result.thread and thread_result.thread.id, "thread start should return a thread id")

local list_result, list_err = codex.list_threads({
  notify = false,
  cwd = test_thread_cwd,
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

local archive_thread_result, archive_thread_err = codex.new_thread({
  notify = false,
  open_chat = false,
  cwd = test_thread_cwd,
  timeout_ms = 8000,
})
assert(archive_thread_err == nil, archive_thread_err or "archive test thread should start")
assert(archive_thread_result and archive_thread_result.thread and archive_thread_result.thread.id, "archive test thread should return a thread id")
local archive_turn_result, archive_turn_err = codex.submit_text("materialize archive rollout", {
  notify = false,
  open_chat = false,
  timeout_ms = 8000,
})
assert(archive_turn_err == nil, archive_turn_err or "archive test turn should start cleanly")
assert(archive_turn_result ~= nil, "archive test turn should return a result")
vim.wait(15000, function()
  local thread = codex.get_state().threads.by_id[archive_thread_result.thread.id]
  return thread ~= nil and type(thread.path) == "string" and thread.path ~= "" and vim.uv.fs_stat(thread.path) ~= nil
end, 50)
local archived_thread_snapshot = codex.get_state().threads.by_id[archive_thread_result.thread.id]
assert(
  archived_thread_snapshot ~= nil
    and type(archived_thread_snapshot.path) == "string"
    and archived_thread_snapshot.path ~= ""
    and vim.uv.fs_stat(archived_thread_snapshot.path) ~= nil,
  "archive test thread should materialize a rollout path before archiving"
)
local archive_action, archive_action_err = codex.archive_thread({ thread_id = archive_thread_result.thread.id, notify = false, timeout_ms = 8000 })
assert(archive_action_err == nil, archive_action_err or "thread archive should succeed")
assert(archive_action ~= nil, "thread archive should return a result")
vim.wait(1000, function()
  local thread = codex.get_state().threads.by_id[archive_thread_result.thread.id]
  return thread and thread.archived == true
end, 20)
assert(codex.get_state().threads.by_id[archive_thread_result.thread.id].archived == true, "thread archive should mark the thread archived")
local unarchive_action, unarchive_err = codex.unarchive_thread({ thread_id = archive_thread_result.thread.id, notify = false, timeout_ms = 8000 })
assert(unarchive_err == nil, unarchive_err or "thread unarchive should succeed")
assert(unarchive_action ~= nil, "thread unarchive should return a result")
vim.wait(1000, function()
  local thread = codex.get_state().threads.by_id[archive_thread_result.thread.id]
  return thread and thread.archived == false
end, 20)
assert(codex.get_state().threads.by_id[archive_thread_result.thread.id].archived == false, "thread unarchive should restore the archived thread")

local archive_cleanup_action, archive_cleanup_err = codex.archive_thread({
  thread_id = archive_thread_result.thread.id,
  notify = false,
  timeout_ms = 8000,
})
assert(archive_cleanup_err == nil, archive_cleanup_err or "archive cleanup should succeed")
assert(archive_cleanup_action ~= nil, "archive cleanup should return a result")
vim.wait(1000, function()
  local thread = codex.get_state().threads.by_id[archive_thread_result.thread.id]
  return thread and thread.archived == true
end, 20)
assert(codex.get_state().threads.by_id[archive_thread_result.thread.id].archived == true, "archive cleanup should hide the archive test thread again")

local capture_thread_result, capture_thread_err = codex.new_thread({
  notify = false,
  open_chat = false,
  cwd = test_thread_cwd,
  timeout_ms = 8000,
})
assert(capture_thread_err == nil, capture_thread_err or "capture thread start failed")
assert(capture_thread_result and capture_thread_result.thread and capture_thread_result.thread.id, "capture flow should run against a fresh thread")
assert(codex.get_state().threads.active_id == capture_thread_result.thread.id, "fresh capture thread should become active")

local steer_none_result, steer_none_err = codex.steer({ text = "Focus on failing tests first.", notify = false, timeout_ms = 8000 })
assert(steer_none_result == nil, "steer should refuse when no turn is running")
assert(steer_none_err == "no running turn", "steer should report when no turn is running")

local compact_result, compact_err = codex.compact_thread({ thread_id = capture_thread_result.thread.id, notify = false, timeout_ms = 8000 })
assert(compact_err == nil, compact_err or "thread compaction should start cleanly")
assert(compact_result ~= nil, "thread compaction should return a result")

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
local steer_blocked_result, steer_blocked_err = codex.steer({ text = "Actually patch tests first.", notify = false, timeout_ms = 8000 })
assert(steer_blocked_result == nil, "steer should refuse while workbench fragments are staged")
assert(steer_blocked_err == "workbench fragments are staged", "steer should explain why staged fragments block the request")

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
local note_fragment, note_err = codex.capture_text_fragment({
  label = "Latest test run",
  text = "FAIL auth middleware\n1 failing test",
  filetype = "markdown",
  source = "neotest",
  category = "runtime",
  notify = false,
})
assert(note_err == nil, note_err or "text fragment capture should succeed")
assert(note_fragment.kind == "text_note", "text fragment capture should stage a text_note fragment")
assert(type(note_fragment.handle) == "string" and note_fragment.handle:match("^f%d+$"), "text fragment should get a stable workbench handle")

local before_review_count = #codex.get_workbench_state().workbench.fragments_order
local review_result, review_err = codex.open_compose_review({ seed_message = "Preserve this review draft with [[f1]], [[f2]], [[f3]], and [[f4]]." })
assert(review_err == nil, review_err or "compose review should open when requested")
assert(review_result ~= nil, "compose review should return state when opened")
local review_state = codex.get_workbench_state().review
assert(review_state.visible == true, "compose review should open when requested")
assert(review_state.thread_id == codex.get_state().threads.active_id, "compose review should show the active thread")
assert(#review_state.fragments == before_review_count, "compose review should show the staged fragments")
assert(codex.get_workbench_state().workbench.draft_message == "Preserve this review draft with [[f1]], [[f2]], [[f3]], and [[f4]].", "compose review should seed the initial packet template")
local review_viewers = require("neovim_codex.nvim.viewer_stack").inspect()
assert(review_viewers.top and review_viewers.top.key == "compose-review", "compose review should open through the stacked viewer layer")
assert(review_state.fragments[1].handle == "f1", "compose review should display the staged fragment handles")
local saw_text_note = false
for _, fragment in ipairs(review_state.fragments or {}) do
  if fragment.kind == "text_note" then
    saw_text_note = true
    break
  end
end
assert(saw_text_note, "compose review should display text note fragments")

codex.open_compose_review({ seed_message = "Do not overwrite this." })
assert(codex.get_workbench_state().workbench.draft_message == "Preserve this review draft with [[f1]], [[f2]], [[f3]], and [[f4]].", "compose review should not overwrite an existing packet template")

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
local captured_file_change = nil
local captured_tool = nil
local request_manager = require("neovim_codex.nvim.server_requests").new(codex.get_config(), {
  notify = function() end,
  respond_request = function(request, payload)
    if request.method == "item/commandExecution/requestApproval" then
      captured_command = { request = request, payload = payload }
    elseif request.method == "item/fileChange/requestApproval" then
      captured_file_change = { request = request, payload = payload }
    elseif request.method == "item/tool/requestUserInput" then
      captured_tool = { request = request, payload = payload }
    end
    return true, nil
  end,
})
request_manager:attach(request_store)
local review_manager = require("neovim_codex.nvim.file_change_review").new(codex.get_config(), {
  notify = function() end,
  respond_request = function(request, payload)
    captured_file_change = { request = request, payload = payload }
    return true, nil
  end,
})
review_manager:attach(request_store)

request_store:dispatch({
  type = "thread_received",
  thread = { id = "thr_req", status = { type = "idle" }, turns = {} },
  replace_turns = true,
  activate = true,
})
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
local reopened_request, reopen_err = request_manager:open_current({ thread_id = "thr_req" })
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
  type = "turn_received",
  thread_id = "thr_req",
  turn = { id = "turn_diff", status = "completed", items = {}, error = nil },
})
request_store:dispatch({
  type = "item_received",
  thread_id = "thr_req",
  turn_id = "turn_diff",
  item = {
    type = "fileChange",
    id = "item_diff",
    status = "completed",
    changes = {
      {
        path = repo_root .. "/README.md",
        kind = "update",
        diff = "@@ -1 +1 @@\n-old\n+new",
      },
      {
        path = repo_root .. "/lua/neovim_codex/init.lua",
        kind = "update",
        diff = "@@ -1 +1 @@\n-old init\n+new init",
      },
    },
  },
})
request_store:dispatch({
  type = "turn_diff_updated",
  thread_id = "thr_req",
  turn_id = "turn_diff",
  diff = "@@ -1 +1 @@\n-old\n+new",
})
request_store:dispatch({
  type = "server_request_received",
  request = {
    method = "item/fileChange/requestApproval",
    id = "req_diff",
    params = {
      threadId = "thr_req",
      turnId = "turn_diff",
      itemId = "item_diff",
      reason = "Review the patch",
      grantRoot = repo_root,
    },
  },
})
local reviewed_request, review_err = review_manager:open_current({ thread_id = "thr_req" })
assert(review_err == nil, review_err or "file change review should open for the pending diff request")
assert(reviewed_request and reviewed_request.request_id == "req_diff", "file change review should target the pending file change request")
local review_viewers = require("neovim_codex.nvim.viewer_stack").inspect()
assert(review_viewers.top and review_viewers.top.key == "file-change-review", "file change review should open in the stacked viewer layer")
vim.api.nvim_feedkeys(termcodes("o"), "xt", false)
vim.wait(1000, function()
  local top = require("neovim_codex.nvim.viewer_stack").inspect().top
  return top and top.key == "file-change-review-detail"
end, 20)
local diff_viewers = require("neovim_codex.nvim.viewer_stack").inspect()
assert(diff_viewers.top and diff_viewers.top.key == "file-change-review-detail", "file change review should open a dedicated file diff viewer")
local diff_lines = vim.api.nvim_buf_get_lines(diff_viewers.top.bufnr, 0, -1, false)
assert(diff_lines[1] == "@@ -1 +1 @@", "file diff viewer should show the selected unified diff")
vim.api.nvim_feedkeys(termcodes("]f"), "xt", false)
vim.wait(1000, function()
  local top = require("neovim_codex.nvim.viewer_stack").inspect().top
  if not top or top.key ~= "file-change-review-detail" then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(top.bufnr, 0, -1, false)
  return lines[2] == "-old init"
end, 20)
local next_diff_lines = vim.api.nvim_buf_get_lines(require("neovim_codex.nvim.viewer_stack").inspect().top.bufnr, 0, -1, false)
assert(next_diff_lines[2] == "-old init", "file diff viewer should move to the next changed file")
vim.api.nvim_feedkeys(termcodes("q"), "xt", false)
vim.wait(1000, function()
  local top = require("neovim_codex.nvim.viewer_stack").inspect().top
  return top and top.key == "file-change-review"
end, 20)
local review_shortcuts_surface, review_shortcuts_lines = codex.open_shortcuts({ surface = "file_change_review" })
assert(review_shortcuts_surface == "file_change_review", "shortcut sheet should target the file change review surface")
local review_shortcuts_body = table.concat(review_shortcuts_lines, "\n")
assert(review_shortcuts_body:find("Open the selected file diff", 1, true), "file change review shortcuts should expose diff opening")
assert(review_shortcuts_body:find("Move to the next changed file", 1, true), "file change review shortcuts should expose file navigation")
require("neovim_codex.nvim.presentation").close_viewers()

reviewed_request, review_err = review_manager:open_current({ thread_id = "thr_req" })
assert(review_err == nil, review_err or "file change review should reopen after checking shortcuts")
vim.api.nvim_feedkeys(termcodes("s"), "xt", false)
vim.wait(1000, function()
  return captured_file_change ~= nil
end, 20)
assert(captured_file_change and captured_file_change.payload.decision == "acceptForSession", "file change review should send the session decision shortcut")
request_store:dispatch({ type = "server_request_resolved", request_id = "req_diff" })
vim.wait(1000, function()
  local top = require("neovim_codex.nvim.viewer_stack").inspect().top
  return top == nil or top.key ~= "file-change-review"
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
