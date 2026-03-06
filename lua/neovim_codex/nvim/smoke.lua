local presentation = require("neovim_codex.nvim.presentation")

local M = {}

local function add_check(checks, ok, title, detail)
  checks[#checks + 1] = {
    ok = ok,
    title = title,
    detail = detail,
  }
  return ok
end

local function render_report(checks, report)
  local lines = {
    "# neovim-codex smoke report",
    "",
  }

  for _, check in ipairs(checks) do
    local prefix = check.ok and "- [x]" or "- [ ]"
    lines[#lines + 1] = string.format("%s %s", prefix, check.title)
    if check.detail and check.detail ~= "" then
      lines[#lines + 1] = string.format("  - %s", check.detail)
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Connection"
  lines[#lines + 1] = string.format("- status: %s", report.connection.status)
  lines[#lines + 1] = string.format("- pid: %s", report.connection.pid or "-")
  lines[#lines + 1] = string.format("- initialized: %s", tostring(report.connection.initialized))
  lines[#lines + 1] = string.format("- user_agent: %s", report.connection.user_agent or "-")
  lines[#lines + 1] = string.format("- last_error: %s", report.connection.last_error or "-")
  lines[#lines + 1] = string.format("- last_stderr: %s", report.connection.last_stderr or "-")

  if #report.tail_logs > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Recent events"
    for _, entry in ipairs(report.tail_logs) do
      lines[#lines + 1] = string.format("- [%s] %s %s", entry.at, entry.direction or entry.kind, entry.body)
    end
  end

  return lines
end

function M.run(runtime, opts)
  opts = opts or {}
  local checks = {}
  local timeout_ms = opts.timeout_ms or 4000
  local started_here = false
  local stopped_here = false
  local success = true

  local version_ok = vim.fn.has("nvim-0.11") == 1
  success = add_check(checks, version_ok, "NeoVim version is at least 0.11", vim.version and vim.version().major and string.format("detected %d.%d.%d", vim.version().major, vim.version().minor, vim.version().patch) or "") and success

  local codex_bin = runtime.config.codex_cmd[1]
  local executable_ok = vim.fn.executable(codex_bin) == 1
  success = add_check(checks, executable_ok, string.format("`%s` is executable", codex_bin), executable_ok and "binary found on PATH" or "binary not found on PATH") and success

  if executable_ok and version_ok then
    local connection = runtime.client:status()
    if connection.initialized then
      add_check(checks, true, "app-server handshake completed", "existing runtime is already ready")
    else
      local ok, err = runtime.client:start()
      if ok then
        started_here = true
        add_check(checks, true, "app-server process started", string.format("pid=%s", runtime.client:status().pid or "-"))
      elseif err == "app-server is already running" then
        add_check(checks, true, "app-server process started", "runtime was already running")
      else
        success = add_check(checks, false, "app-server process started", err) and success
      end

      if ok or err == "app-server is already running" then
        local ready = runtime.wait_until_ready(timeout_ms)
        local ready_connection = runtime.client:status()
        local detail = ready_connection.user_agent or ready_connection.last_error or "timed out waiting for initialize"
        success = add_check(checks, ready, "app-server handshake completed", detail) and success
      end
    end
  end

  local connection_snapshot = runtime.client:get_state().connection

  if opts.stop_after and started_here then
    local stop_ok = runtime.client:stop()
    if stop_ok then
      stopped_here = runtime.wait_until_stopped(timeout_ms)
    end
  end

  local final_state = runtime.client:get_state()
  local logs = final_state.logs
  local tail_logs = {}
  local start_index = math.max(1, #logs - 9)
  for index = start_index, #logs do
    tail_logs[#tail_logs + 1] = logs[index]
  end

  local report = {
    success = success,
    checks = checks,
    connection = connection_snapshot,
    final_connection = final_state.connection,
    started_here = started_here,
    stopped_here = stopped_here,
    tail_logs = tail_logs,
  }

  report.lines = render_report(checks, report)

  if opts.open_report ~= false then
    presentation.open_report("smoke", report.lines)
  end

  if opts.notify ~= false then
    local level = report.success and vim.log.levels.INFO or vim.log.levels.ERROR
    local message = report.success and "neovim-codex smoke checks passed" or "neovim-codex smoke checks failed"
    vim.notify(message, level)
  end

  return report
end

return M
