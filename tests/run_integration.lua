local script_path = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fs.dirname(vim.fs.dirname(script_path))

vim.opt.runtimepath:append(repo_root)
vim.cmd("runtime plugin/neovim_codex.lua")

local codex = require("neovim_codex")
codex.setup({})

assert(vim.fn.exists(":CodexStart") == 2, "CodexStart command should exist")
assert(vim.fn.exists(":CodexSmoke") == 2, "CodexSmoke command should exist")
assert(type(require("neovim_codex.health").check) == "function", "health module should expose check()")

local report = codex.run_smoke({
  open_report = false,
  notify = false,
  stop_after = true,
  timeout_ms = 4000,
})

assert(report.success, table.concat(report.lines, "\n"))
assert(report.connection.initialized == true, "smoke should reach initialized state before optional stop")
assert(report.final_connection.status == "stopped", "smoke should stop the runtime when stop_after=true")

print("ok - integration smoke")
