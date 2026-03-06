vim.api.nvim_create_user_command("CodexStart", function()
  require("neovim_codex").start()
end, {})

vim.api.nvim_create_user_command("CodexStop", function()
  require("neovim_codex").stop()
end, {})

vim.api.nvim_create_user_command("CodexStatus", function()
  print(require("neovim_codex").status())
end, {})

vim.api.nvim_create_user_command("CodexEvents", function()
  require("neovim_codex").open_events()
end, {})

vim.api.nvim_create_user_command("CodexSmoke", function()
  require("neovim_codex").smoke()
end, {})

vim.api.nvim_create_user_command("CodexChat", function()
  require("neovim_codex").chat()
end, {})

vim.api.nvim_create_user_command("CodexSend", function()
  require("neovim_codex").send()
end, {})

vim.api.nvim_create_user_command("CodexThreadNew", function()
  require("neovim_codex").new_thread()
end, {})

vim.api.nvim_create_user_command("CodexThreads", function()
  require("neovim_codex").pick_thread({ action = "resume" })
end, {})

vim.api.nvim_create_user_command("CodexThreadRead", function(command)
  local args = vim.trim(command.args or "")
  if args == "" then
    require("neovim_codex").pick_thread({ action = "read" })
    return
  end
  require("neovim_codex").open_thread_report({ thread_id = args })
end, { nargs = "?" })

vim.api.nvim_create_user_command("CodexInterrupt", function()
  require("neovim_codex").interrupt()
end, {})
