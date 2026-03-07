local client_mod = require("neovim_codex.core.client")
local selectors = require("neovim_codex.core.selectors")
local store_mod = require("neovim_codex.core.store")
local chat = require("neovim_codex.nvim.chat")
local presentation = require("neovim_codex.nvim.presentation")
local smoke = require("neovim_codex.nvim.smoke")
local renderer = require("neovim_codex.nvim.thread_renderer")
local transport_mod = require("neovim_codex.nvim.transport")

local M = {}

local defaults = {
  codex_cmd = { "codex", "app-server" },
  client_info = {
    name = "neovim_codex",
    title = "NeoVim Codex",
    version = "0.3.0-dev",
  },
  experimental_api = true,
  max_log_entries = 400,
  thread = {
    cwd = "current",
    persist_extended_history = true,
    experimental_raw_events = false,
  },
  thread_list = {
    limit = 50,
    cwd_only = true,
    archived = false,
  },
  ui = {
    chat = {
      layout = {
        width = 0.88,
        height = 0.84,
        border = "rounded",
      },
      transcript = {
        wrap = true,
      },
      details = {
        width = 0.72,
        height = 0.68,
        border = "rounded",
        wrap = true,
      },
      composer = {
        min_height = 6,
        max_height = 12,
        default_height = 8,
        wrap = true,
      },
    },
  },
  keymaps = {
    global = {
      chat = false,
      new_thread = false,
      threads = false,
      read_thread = false,
      interrupt = false,
    },
    transcript = {
      close = "q",
      focus_composer = "i",
      inspect = "<CR>",
      next_turn = "]]",
      prev_turn = "[[",
      help = "g?",
    },
    composer = {
      send = "<C-s>",
      send_normal = "gS",
      close = "q",
      help = "g?",
    },
  },
}

local runtime = nil
local config = vim.deepcopy(defaults)

local function notify(message, level, enabled)
  if enabled == false then
    return
  end
  vim.notify(message, level)
end

local function map_if(lhs, rhs, desc)
  if not lhs then
    return
  end
  vim.keymap.set("n", lhs, rhs, { silent = true, desc = desc })
end

local function apply_global_keymaps()
  local keymaps = config.keymaps.global or {}
  map_if(keymaps.chat, function()
    require("neovim_codex").chat()
  end, "Open Codex chat")
  map_if(keymaps.new_thread, function()
    require("neovim_codex").new_thread()
  end, "Create a new Codex thread")
  map_if(keymaps.threads, function()
    require("neovim_codex").pick_thread({ action = "resume" })
  end, "Pick a Codex thread")
  map_if(keymaps.read_thread, function()
    require("neovim_codex").pick_thread({ action = "read" })
  end, "Read a Codex thread")
  map_if(keymaps.interrupt, function()
    require("neovim_codex").interrupt()
  end, "Interrupt the active Codex turn")
end

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
  return vim.deepcopy(config)
end

local function on_server_request(message)
  vim.schedule(function()
    notify(string.format("Codex sent `%s`, but request handling arrives in task 4", message.method), vim.log.levels.WARN, true)
  end)
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
    on_server_request = on_server_request,
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

local function ensure_ready(timeout_ms)
  local rt = ensure_runtime()
  local connection = rt.client:status()

  if connection.initialized then
    return rt, nil
  end

  local ok, err = rt.client:start()
  if not ok and err ~= "app-server is already running" then
    return nil, err
  end

  local ready = rt.wait_until_ready(timeout_ms)
  if not ready then
    local failed_connection = rt.client:status()
    return nil, failed_connection.last_error or "timed out waiting for app-server initialization"
  end

  return rt, nil
end

local function request_with_wait(request_fn, opts)
  opts = opts or {}
  local done = false
  local result = nil
  local err_message = nil

  request_fn(function(err, payload)
    done = true
    err_message = err
    result = payload
  end)

  if opts.wait then
    local ok = vim.wait(opts.timeout_ms or 4000, function()
      return done
    end, 50)
    if not ok then
      return nil, "timed out waiting for app-server response"
    end
  end

  return result, err_message
end

local function wait_opts(opts)
  return {
    wait = opts.wait ~= false,
    timeout_ms = opts.timeout_ms,
  }
end

local function current_cwd()
  return vim.fn.getcwd()
end

local function build_thread_start_params(opts)
  local params = {
    cwd = opts.cwd or (config.thread.cwd == "current" and current_cwd() or config.thread.cwd),
    persistExtendedHistory = config.thread.persist_extended_history,
    experimentalRawEvents = config.thread.experimental_raw_events,
  }

  if opts.model then
    params.model = opts.model
  end
  if opts.model_provider then
    params.modelProvider = opts.model_provider
  end
  if opts.service_name then
    params.serviceName = opts.service_name
  end
  if opts.personality then
    params.personality = opts.personality
  end
  if opts.approval_policy then
    params.approvalPolicy = opts.approval_policy
  end
  if opts.sandbox then
    params.sandbox = opts.sandbox
  end
  if opts.ephemeral ~= nil then
    params.ephemeral = opts.ephemeral
  end

  return params
end

local function build_thread_resume_params(opts)
  local params = {
    threadId = opts.thread_id,
    persistExtendedHistory = config.thread.persist_extended_history,
  }

  if opts.cwd then
    params.cwd = opts.cwd
  end
  if opts.personality then
    params.personality = opts.personality
  end
  if opts.model then
    params.model = opts.model
  end
  if opts.model_provider then
    params.modelProvider = opts.model_provider
  end
  if opts.approval_policy then
    params.approvalPolicy = opts.approval_policy
  end
  if opts.sandbox then
    params.sandbox = opts.sandbox
  end

  return params
end

local function build_thread_list_params(opts)
  opts = opts or {}
  return {
    limit = opts.limit or config.thread_list.limit,
    cursor = opts.cursor,
    archived = opts.archived ~= nil and opts.archived or config.thread_list.archived,
    cwd = opts.cwd or (config.thread_list.cwd_only and current_cwd() or nil),
    searchTerm = opts.search_term,
  }
end

local function build_turn_start_params(thread_id, text, opts)
  local params = {
    threadId = thread_id,
    input = opts.input or {
      { type = "text", text = text },
    },
  }

  if opts.cwd then
    params.cwd = opts.cwd
  end
  if opts.approval_policy then
    params.approvalPolicy = opts.approval_policy
  end
  if opts.sandbox_policy then
    params.sandboxPolicy = opts.sandbox_policy
  end
  if opts.model then
    params.model = opts.model
  end
  if opts.personality then
    params.personality = opts.personality
  end
  if opts.output_schema then
    params.outputSchema = opts.output_schema
  end

  return params
end

local function chat_actions()
  return {
    submit_text = function(text)
      return require("neovim_codex").submit_text(text)
    end,
  }
end

local function reveal_chat(rt)
  return chat.open(rt.store, config, chat_actions())
end

local function toggle_chat(rt)
  return chat.toggle(rt.store, config, chat_actions())
end

local function format_thread_label(thread)
  local title = nil
  if thread.name ~= nil and thread.name ~= vim.NIL and thread.name ~= "" then
    title = thread.name
  elseif thread.preview ~= nil and thread.preview ~= vim.NIL and thread.preview ~= "" then
    title = thread.preview
  else
    title = "(untitled thread)"
  end
  title = tostring(title):gsub("\n", " ")
  return string.format("%s  [%s]  %s", thread.id, thread.status and thread.status.type or "unknown", title)
end

local function merge_current_thread(threads, active_thread)
  if not active_thread then
    return threads
  end

  for _, thread in ipairs(threads) do
    if thread.id == active_thread.id then
      return threads
    end
  end

  local merged = { active_thread }
  for _, thread in ipairs(threads) do
    merged[#merged + 1] = thread
  end
  return merged
end

local function normalize_legacy_config(opts)
  opts = vim.deepcopy(opts or {})
  local chat_opts = ((opts.ui or {}).chat) or {}

  if chat_opts.width ~= nil or chat_opts.prompt_height ~= nil or chat_opts.wrap ~= nil then
    chat_opts.layout = chat_opts.layout or {}
    chat_opts.transcript = chat_opts.transcript or {}
    chat_opts.composer = chat_opts.composer or {}

    if chat_opts.width ~= nil and chat_opts.layout.width == nil then
      chat_opts.layout.width = chat_opts.width
    end
    if chat_opts.wrap ~= nil and chat_opts.transcript.wrap == nil then
      chat_opts.transcript.wrap = chat_opts.wrap
    end
    if chat_opts.wrap ~= nil and chat_opts.composer.wrap == nil then
      chat_opts.composer.wrap = chat_opts.wrap
    end
    if chat_opts.prompt_height ~= nil and chat_opts.composer.default_height == nil then
      chat_opts.composer.default_height = chat_opts.prompt_height
    end
    if chat_opts.prompt_height ~= nil and chat_opts.composer.min_height == nil then
      chat_opts.composer.min_height = math.max(4, chat_opts.prompt_height)
    end
    if chat_opts.prompt_height ~= nil and chat_opts.composer.max_height == nil then
      chat_opts.composer.max_height = math.max(12, chat_opts.prompt_height)
    end

    opts.ui = opts.ui or {}
    opts.ui.chat = chat_opts
  end

  local keymaps = opts.keymaps or {}
  if keymaps.prompt and not keymaps.composer then
    keymaps.composer = vim.deepcopy(keymaps.prompt)
  end
  if keymaps.transcript and keymaps.transcript.focus_prompt and not keymaps.transcript.focus_composer then
    keymaps.transcript.focus_composer = keymaps.transcript.focus_prompt
  end
  opts.keymaps = keymaps

  return opts
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), normalize_legacy_config(opts))
  apply_global_keymaps()
end

function M.start()
  local rt = ensure_runtime()
  if rt.client:status().initialized then
    notify("Codex app-server is already ready", vim.log.levels.INFO, true)
    return true
  end

  local ok, err = rt.client:start()
  if not ok and err then
    if err == "app-server is already running" then
      notify("Codex app-server is already running", vim.log.levels.INFO, true)
      return true
    end
    notify(err, vim.log.levels.ERROR, true)
    return false
  end

  notify("Codex app-server started", vim.log.levels.INFO, true)
  return true
end

function M.stop()
  if not runtime then
    notify("Codex app-server is not running", vim.log.levels.INFO, true)
    return false
  end

  local ok, err = runtime.client:stop()
  if not ok and err then
    notify(err, vim.log.levels.INFO, true)
    return false
  end

  notify("Codex app-server stop requested", vim.log.levels.INFO, true)
  return true
end

function M.chat()
  local rt = ensure_runtime()
  if not chat.is_visible() and not rt.client:status().initialized then
    M.start()
  end
  return toggle_chat(rt)
end

function M.inspect_current_block(opts)
  opts = opts or {}
  local block, err = chat.inspect_current_block()
  if err then
    notify(err, vim.log.levels.INFO, opts.notify)
    return nil, err
  end
  return block, nil
end

function M.send()
  local rt, err = ensure_ready(4000)
  if not rt then
    notify(err, vim.log.levels.ERROR, true)
    return nil, err
  end

  reveal_chat(rt)
  return chat.submit()
end

function M.new_thread(opts)
  opts = opts or {}
  local rt, err = ensure_ready(opts.timeout_ms)
  if not rt then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  if opts.open_chat ~= false then
    reveal_chat(rt)
  end

  local result, request_err = request_with_wait(function(done)
    rt.client:thread_start(build_thread_start_params(opts), done)
  end, wait_opts(opts))

  if request_err then
    notify(request_err, vim.log.levels.ERROR, opts.notify)
    return nil, request_err
  end

  notify(string.format("Started thread %s", result.thread.id), vim.log.levels.INFO, opts.notify)
  return result, nil
end

function M.resume_thread(opts)
  opts = opts or {}
  if not opts.thread_id then
    return nil, "thread_id is required"
  end

  local rt, err = ensure_ready(opts.timeout_ms)
  if not rt then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  local result, request_err = request_with_wait(function(done)
    rt.client:thread_resume(build_thread_resume_params(opts), done)
  end, wait_opts(opts))

  if request_err then
    notify(request_err, vim.log.levels.ERROR, opts.notify)
    return nil, request_err
  end

  if opts.open_chat ~= false then
    reveal_chat(rt)
  end

  notify(string.format("Resumed thread %s", result.thread.id), vim.log.levels.INFO, opts.notify)
  return result, nil
end

function M.list_threads(opts)
  opts = opts or {}
  local rt, err = ensure_ready(opts.timeout_ms)
  if not rt then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  local result, request_err = request_with_wait(function(done)
    rt.client:thread_list(build_thread_list_params(opts), done)
  end, wait_opts(opts))

  if request_err then
    notify(request_err, vim.log.levels.ERROR, opts.notify)
    return nil, request_err
  end

  return result, nil
end

function M.read_thread(opts)
  opts = opts or {}
  if not opts.thread_id then
    return nil, "thread_id is required"
  end

  local rt, err = ensure_ready(opts.timeout_ms)
  if not rt then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  local result, request_err = request_with_wait(function(done)
    rt.client:thread_read({
      threadId = opts.thread_id,
      includeTurns = opts.include_turns ~= false,
    }, done)
  end, wait_opts(opts))

  if request_err then
    notify(request_err, vim.log.levels.ERROR, opts.notify)
    return nil, request_err
  end

  return result, nil
end

function M.open_thread_report(opts)
  opts = opts or {}
  local result, err = M.read_thread(vim.tbl_extend("force", opts, { include_turns = true }))
  if err and err:match("includeTurns is unavailable") then
    result, err = M.read_thread(vim.tbl_extend("force", opts, { include_turns = false, notify = false }))
  end
  if err then
    return nil, err
  end

  local view = renderer.render_thread(result.thread, { title = "# Codex Thread" })
  presentation.open_report(string.format("thread-%s", result.thread.id), view.lines)
  return result, nil
end

function M.pick_thread(opts)
  opts = opts or {}
  local result, err = M.list_threads(vim.tbl_extend("force", opts, { notify = false }))
  if err then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  local threads = merge_current_thread(result.data or {}, selectors.get_active_thread(M.get_state()))
  if #threads == 0 then
    notify("No matching Codex threads found", vim.log.levels.INFO, opts.notify)
    return nil, "no threads found"
  end

  vim.ui.select(threads, {
    prompt = opts.prompt or "Select Codex thread",
    format_item = format_thread_label,
  }, function(choice)
    if not choice then
      return
    end

    if opts.action == "read" then
      M.open_thread_report({ thread_id = choice.id, notify = opts.notify })
    elseif choice.id == M.get_state().threads.active_id then
      local rt = ensure_runtime()
      if not rt.client:status().initialized then
        M.start()
      end
      reveal_chat(rt)
    else
      M.resume_thread({ thread_id = choice.id, open_chat = true, notify = opts.notify })
    end
  end)

  return threads, nil
end

function M.submit_text(text, opts)
  opts = opts or {}
  local prompt = text and tostring(text) or ""
  if vim.trim(prompt) == "" then
    notify("Prompt is empty", vim.log.levels.INFO, opts.notify)
    return nil, "prompt is empty"
  end

  local rt, err = ensure_ready(opts.timeout_ms)
  if not rt then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  if opts.open_chat ~= false then
    reveal_chat(rt)
  end

  local active_thread = selectors.get_active_thread(rt.client:get_state())
  if not active_thread then
    local thread_result, thread_err = M.new_thread({
      cwd = opts.cwd,
      wait = true,
      notify = false,
      open_chat = false,
      timeout_ms = opts.timeout_ms,
    })
    if thread_err then
      notify(thread_err, vim.log.levels.ERROR, opts.notify)
      return nil, thread_err
    end
    active_thread = thread_result.thread
  end

  local result, request_err = request_with_wait(function(done)
    rt.client:turn_start(build_turn_start_params(active_thread.id, prompt, opts), done)
  end, wait_opts(opts))

  if request_err then
    notify(request_err, vim.log.levels.ERROR, opts.notify)
    return nil, request_err
  end

  return result, nil
end

function M.interrupt(opts)
  opts = opts or {}
  local rt = ensure_runtime()
  local turn, thread = selectors.find_running_turn(rt.client:get_state())
  if not turn or not thread then
    notify("No running Codex turn to interrupt", vim.log.levels.INFO, opts.notify)
    return nil, "no running turn"
  end

  local result, err = request_with_wait(function(done)
    rt.client:turn_interrupt({ threadId = thread.id, turnId = turn.id }, done)
  end, wait_opts(opts))

  if err then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  notify(string.format("Interrupt requested for %s", turn.id), vim.log.levels.INFO, opts.notify)
  return result, nil
end

function M.status()
  local rt = ensure_runtime()
  local state = rt.client:get_state()
  return presentation.status_line(state.connection, state.threads)
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

function M.get_chat_state()
  return chat.inspect()
end

function M.get_config()
  return vim.deepcopy(config)
end

return M
