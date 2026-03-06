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
