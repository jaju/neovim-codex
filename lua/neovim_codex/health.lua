local health = vim.health or require("health")

local M = {}

function M.check()
  local codex = require("neovim_codex")
  local result = codex.run_smoke({
    open_report = false,
    notify = false,
    stop_after = true,
    timeout_ms = 4000,
  })

  health.start("neovim-codex")

  for _, check in ipairs(result.checks) do
    local message = check.title
    if check.detail and check.detail ~= "" then
      message = string.format("%s (%s)", check.title, check.detail)
    end

    if check.ok then
      health.ok(message)
    else
      health.error(message)
    end
  end

  health.info("Commands: :CodexStart, :CodexStop, :CodexStatus, :CodexEvents, :CodexSmoke")
  health.info("Dogfood loop: :Lazy reload neovim-codex -> :checkhealth neovim_codex -> :CodexSmoke")
end

return M
