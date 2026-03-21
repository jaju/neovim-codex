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

vim.api.nvim_create_user_command("CodexChatRail", function()
  require("neovim_codex").open_chat_rail()
end, {})

vim.api.nvim_create_user_command("CodexChatOverlay", function()
  require("neovim_codex").open_chat_overlay()
end, {})

vim.api.nvim_create_user_command("CodexChatReader", function()
  require("neovim_codex").open_chat_overlay()
end, {})

vim.api.nvim_create_user_command("CodexSend", function()
  require("neovim_codex").send()
end, {})

vim.api.nvim_create_user_command("CodexSteer", function(command)
  local args = vim.trim(command.args or "")
  require("neovim_codex").steer(args == "" and {} or { text = args })
end, { nargs = "*" })

vim.api.nvim_create_user_command("CodexThreadNew", function()
  require("neovim_codex").new_thread()
end, {})

vim.api.nvim_create_user_command("CodexThreadNewConfig", function()
  require("neovim_codex").create_thread_with_settings()
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

vim.api.nvim_create_user_command("CodexThreadRename", function(command)
  local args = vim.trim(command.args or "")
  require("neovim_codex").rename_thread(args == "" and {} or { name = args })
end, { nargs = "?" })

vim.api.nvim_create_user_command("CodexThreadFork", function(command)
  local args = vim.trim(command.args or "")
  require("neovim_codex").fork_thread(args == "" and {} or { thread_id = args })
end, { nargs = "?" })

vim.api.nvim_create_user_command("CodexThreadArchive", function(command)
  local args = vim.trim(command.args or "")
  require("neovim_codex").archive_thread(args == "" and {} or { thread_id = args })
end, { nargs = "?" })

vim.api.nvim_create_user_command("CodexThreadUnarchive", function(command)
  local args = vim.trim(command.args or "")
  require("neovim_codex").unarchive_thread(args == "" and {} or { thread_id = args })
end, { nargs = "?" })

vim.api.nvim_create_user_command("CodexThreadRollback", function(command)
  local args = vim.trim(command.args or "")
  require("neovim_codex").rollback_thread(args == "" and {} or { thread_id = args })
end, { nargs = "?" })

vim.api.nvim_create_user_command("CodexThreadCompact", function(command)
  local args = vim.trim(command.args or "")
  require("neovim_codex").compact_thread(args == "" and {} or { thread_id = args })
end, { nargs = "?" })

vim.api.nvim_create_user_command("CodexHistory", function(command)
  local args = vim.trim(command.args or "")
  require("neovim_codex").open_history(args == "" and {} or { thread_id = args })
end, { nargs = "?" })

vim.api.nvim_create_user_command("CodexThreadSettings", function(command)
  local args = vim.trim(command.args or "")
  require("neovim_codex").configure_thread(args == "" and {} or { thread_id = args })
end, { nargs = "?" })

vim.api.nvim_create_user_command("CodexInterrupt", function()
  require("neovim_codex").interrupt()
end, {})

vim.api.nvim_create_user_command("CodexInspect", function()
  require("neovim_codex").inspect_current_block()
end, {})

vim.api.nvim_create_user_command("CodexRequest", function()
  require("neovim_codex").open_request()
end, {})

vim.api.nvim_create_user_command("CodexReview", function(command)
  local args = vim.trim(command.args or "")
  require("neovim_codex").open_review(args == "" and {} or { request_key = args })
end, { nargs = "?" })

vim.api.nvim_create_user_command("CodexWorkbench", function()
  require("neovim_codex").toggle_workbench()
end, {})

vim.api.nvim_create_user_command("CodexCompose", function()
  require("neovim_codex").open_compose_review()
end, {})

vim.api.nvim_create_user_command("CodexCapturePath", function()
  require("neovim_codex").capture_current_file()
end, {})

vim.api.nvim_create_user_command("CodexCaptureSelection", function()
  require("neovim_codex").capture_visual_selection()
end, { range = true })

vim.api.nvim_create_user_command("CodexCaptureDiagnostic", function()
  require("neovim_codex").capture_current_diagnostic()
end, {})

vim.api.nvim_create_user_command("CodexShortcuts", function()
  require("neovim_codex").open_shortcuts()
end, {})
