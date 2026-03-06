local store_mod = require("neovim_codex.core.store")
local client_mod = require("neovim_codex.core.client")
local transport_mod = require("neovim_codex.nvim.transport")
local presentation = require("neovim_codex.nvim.presentation")
local smoke = require("neovim_codex.nvim.smoke")

local M = {}

local defaults = {
  codex_cmd = { "codex", "app-server" },
  client_info = {
    name = "neovim_codex",
    title = "NeoVim Codex",
    version = "0.1.0-dev",
  },
  experimental_api = true,
  max_log_entries = 400,
}

local runtime = nil
local config = vim.deepcopy(defaults)

local function json_codec()
  return {
    encode = function(value)
      return vim.json.encode(value)
    end,
    decode = function(value)
      return vim.json.decode(value)
    end,
  }
end

local function current_runtime_config()
  return {
    codex_cmd = vim.deepcopy(config.codex_cmd),
    client_info = vim.deepcopy(config.client_info),
    experimental_api = config.experimental_api,
    max_log_entries = config.max_log_entries,
  }
end

local function ensure_runtime()
  if runtime then
    return runtime
  end

  local store = store_mod.new({ max_log_entries = config.max_log_entries })
  local transport = transport_mod.new({ cmd = config.codex_cmd })
  local client = client_mod.new({
    store = store,
    transport = transport,
    json = json_codec(),
    client_info = config.client_info,
    experimental_api = config.experimental_api,
  })

  runtime = {
    store = store,
    transport = transport,
    client = client,
    config = current_runtime_config(),
  }

  function runtime.wait_until_ready(timeout_ms)
    return vim.wait(timeout_ms or 4000, function()
      local connection = client:status()
      return connection.initialized or connection.status == "error"
    end, 50) and client:status().initialized
  end

  function runtime.wait_until_stopped(timeout_ms)
    return vim.wait(timeout_ms or 4000, function()
      return client:status().status == "stopped"
    end, 50)
  end

  return runtime
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.start()
  local rt = ensure_runtime()
  if rt.client:status().initialized then
    vim.notify("Codex app-server is already ready", vim.log.levels.INFO)
    return true
  end

  local ok, err = rt.client:start()
  if not ok and err then
    if err == "app-server is already running" then
      vim.notify("Codex app-server is already running", vim.log.levels.INFO)
      return true
    end
    vim.notify(err, vim.log.levels.ERROR)
    return false
  end

  vim.notify("Codex app-server started", vim.log.levels.INFO)
  return true
end

function M.stop()
  if not runtime then
    vim.notify("Codex app-server is not running", vim.log.levels.INFO)
    return false
  end

  local ok, err = runtime.client:stop()
  if not ok and err then
    vim.notify(err, vim.log.levels.INFO)
    return false
  end

  vim.notify("Codex app-server stop requested", vim.log.levels.INFO)
  return true
end

function M.status()
  local rt = ensure_runtime()
  return presentation.status_line(rt.client:status())
end

function M.open_events()
  local rt = ensure_runtime()
  presentation.open_events(rt.store)
end

function M.run_smoke(opts)
  local rt = ensure_runtime()
  return smoke.run(rt, opts)
end

function M.smoke()
  local report = M.run_smoke({
    open_report = true,
    notify = true,
    stop_after = false,
    timeout_ms = 4000,
  })
  return report.success
end

function M.get_state()
  local rt = ensure_runtime()
  return rt.client:get_state()
end

return M
