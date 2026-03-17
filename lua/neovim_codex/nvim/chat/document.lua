local selectors = require("neovim_codex.core.selectors")
local shared = require("neovim_codex.nvim.chat.document.shared")
local threads = require("neovim_codex.nvim.chat.document.threads")

local M = {}

function M.project_active(state, opts)
  local thread = selectors.get_active_thread(state)
  if thread then
    return threads.project(thread, vim.tbl_extend("force", opts or {}, { state = state }))
  end

  return {
    footer = string.format("connection %s", shared.value_or(state.connection and state.connection.status, "unknown")),
    blocks = {
      shared.new_block({
        kind = "metadata",
        surface = "notice",
        lines = {
          "## Ready",
          "- Open or resume a thread, then start composing below.",
          "- `:CodexThreadNew` creates a fresh thread.",
          "- `:CodexThreads` resumes a stored thread.",
        },
      }),
    },
  }
end

function M.project_thread(thread, opts)
  return threads.project(thread, vim.tbl_extend("force", opts or {}, { state = nil }))
end

return M
