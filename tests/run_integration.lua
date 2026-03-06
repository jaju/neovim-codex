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

codex.stop()
vim.wait(4000, function()
  return codex.get_state().connection.status == "stopped"
end, 50)
assert(codex.get_state().connection.status == "stopped", "runtime should stop cleanly")

print("ok - integration smoke and overlay chat lifecycle")
