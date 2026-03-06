local document = require("neovim_codex.nvim.chat.document")
local render = require("neovim_codex.nvim.chat.render")

local M = {}

function M.render_placeholder(state)
  return render.render(document.project_active(state))
end

function M.render_thread(thread, opts)
  return render.render(document.project_thread(thread, opts))
end

return M
