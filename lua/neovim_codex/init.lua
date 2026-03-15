local client_mod = require("neovim_codex.core.client")
local selectors = require("neovim_codex.core.selectors")
local store_mod = require("neovim_codex.core.store")
local chat = require("neovim_codex.nvim.chat")
local presentation = require("neovim_codex.nvim.presentation")
local requests = require("neovim_codex.nvim.server_requests")
local smoke = require("neovim_codex.nvim.smoke")
local workbench = require("neovim_codex.nvim.workbench")
local renderer = require("neovim_codex.nvim.thread_renderer")
local transport_mod = require("neovim_codex.nvim.transport")
local thread_identity = require("neovim_codex.nvim.thread_identity")
local thread_params = require("neovim_codex.nvim.thread_params")
local thread_runtime = require("neovim_codex.nvim.thread_runtime")
local thread_runtime_picker = require("neovim_codex.nvim.thread_runtime_picker")
local chat_layout = require("neovim_codex.nvim.chat.layout")

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
        mode = "rail",
        width = 0.88,
        height = 0.84,
        border = "rounded",
        rail = {
          width = 0.42,
          height = 0.96,
          margin_top = 1,
          margin_right = 1,
        },
        reader = {
          width = 0.82,
          height = 0.88,
        },
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
      requests = {
        width = 0.64,
        height = 0.58,
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
    workbench = {
      tray = {
        width = 0.34,
        height = 0.30,
        border = "rounded",
        margin_right = 3,
        margin_bottom = 2,
      },
      review = {
        width = 0.84,
        height = 0.76,
        border = "rounded",
        message_width = 0.62,
        fragments_width = 0.38,
      },
    },
  },
  keymaps = {
    global_modes = { "n", "i", "x" },
    surface_help = "<F1>",
    global = {
      chat = false,
      new_thread = false,
      threads = false,
      read_thread = false,
      thread_rename = false,
      thread_fork = false,
      thread_archive = false,
      thread_settings = false,
      interrupt = false,
      shortcuts = false,
      request = false,
      workbench = false,
      compose = false,
      capture_path = false,
      capture_selection = false,
      capture_diagnostic = false,
    },
    transcript = {
      close = "q",
      focus_composer = "i",
      switch_pane = "<C-w>w",
      inspect = "<CR>",
      next_turn = "]]",
      prev_turn = "[[",
      help = "g?",
      request = "gr",
      toggle_reader = "gR",
    },
    composer = {
      send = "<C-s>",
      send_normal = "gS",
      switch_pane = "<C-w>w",
      close = "q",
      help = "g?",
      request = "gr",
      toggle_reader = "gR",
    },
    request = {
      respond = "<CR>",
      accept = "a",
      accept_for_session = "s",
      decline = "d",
      cancel = "c",
      help = "g?",
    },
    workbench = {
      close = "q",
      inspect = "<CR>",
      remove = "dd",
      clear = "D",
      compose = "o",
      insert_handle = "i",
      park = "p",
      unpark = "u",
      preview = "P",
      focus_message = false,
      help = "g?",
    },
    compose_review = {
      send = "<C-s>",
      send_normal = "gS",
      close = "q",
      preview = "P",
      focus_fragments = "<Tab>",
      help = "g?",
    },
  },
}

local runtime = nil
local ensure_runtime
local submit_thread_rename
local config = vim.deepcopy(defaults)

local function notify(message, level, enabled)
  if enabled == false then
    return
  end
  vim.notify(message, level)
end

local function map_if(lhs, modes, rhs, desc)
  if not lhs then
    return
  end
  vim.keymap.set(modes or "n", lhs, rhs, { silent = true, desc = desc })
end

local function apply_global_keymaps()
  local keymaps = config.keymaps.global or {}
  local global_modes = config.keymaps.global_modes or { "n" }
  map_if(keymaps.chat, global_modes, function()
    require("neovim_codex").chat()
  end, "Toggle Codex chat")
  map_if(keymaps.new_thread, global_modes, function()
    require("neovim_codex").new_thread()
  end, "Create a new Codex thread")
  map_if(keymaps.threads, global_modes, function()
    require("neovim_codex").pick_thread({ action = "resume" })
  end, "Pick a Codex thread")
  map_if(keymaps.read_thread, global_modes, function()
    require("neovim_codex").pick_thread({ action = "read" })
  end, "Read a Codex thread")
  map_if(keymaps.thread_rename, global_modes, function()
    require("neovim_codex").rename_thread()
  end, "Rename the active Codex thread")
  map_if(keymaps.thread_fork, global_modes, function()
    require("neovim_codex").fork_thread()
  end, "Fork the active Codex thread")
  map_if(keymaps.thread_archive, global_modes, function()
    require("neovim_codex").archive_thread()
  end, "Archive a Codex thread")
  map_if(keymaps.thread_settings, global_modes, function()
    require("neovim_codex").configure_thread()
  end, "Configure the active Codex thread")
  map_if(keymaps.interrupt, global_modes, function()
    require("neovim_codex").interrupt()
  end, "Interrupt the active Codex turn")
  map_if(keymaps.request, global_modes, function()
    require("neovim_codex").open_request()
  end, "Open the active Codex request")
  map_if(keymaps.shortcuts, global_modes, function()
    require("neovim_codex").open_shortcuts()
  end, "Show contextual Codex shortcuts")
  map_if(keymaps.workbench, global_modes, function()
    require("neovim_codex").toggle_workbench()
  end, "Toggle the Codex workbench")
  map_if(keymaps.compose, global_modes, function()
    require("neovim_codex").open_compose_review()
  end, "Open Codex compose review")
  map_if(keymaps.capture_path, global_modes, function()
    require("neovim_codex").capture_current_file()
  end, "Add the current file to the Codex workbench")
  if keymaps.capture_selection then
    vim.keymap.set("x", keymaps.capture_selection, function()
      require("neovim_codex").capture_visual_selection()
    end, { silent = true, desc = "Add the current selection to the Codex workbench" })
  end
  map_if(keymaps.capture_diagnostic, global_modes, function()
    require("neovim_codex").capture_current_diagnostic()
  end, "Add the current diagnostic to the Codex workbench")
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

local function send_server_request_response(request_key, payload)
  local rt = ensure_runtime()
  local request = selectors.get_pending_request(rt.client:get_state(), request_key)
  if not request then
    return nil, "pending request was not found"
  end
  rt.client:respond_server_request(request.request_id, payload)
  return true, nil
end

function ensure_runtime()
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
  local request_manager = requests.new(config, {
    notify = function(message, level)
      notify(message, level, true)
    end,
    respond_command = function(request, payload)
      return send_server_request_response(request.key, payload)
    end,
    respond_file_change = function(request, payload)
      return send_server_request_response(request.key, payload)
    end,
    respond_tool_input = function(request, payload)
      return send_server_request_response(request.key, payload)
    end,
  })
  request_manager:attach(store)

  runtime = {
    store = store,
    transport = transport,
    client = client,
    requests = request_manager,
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

  workbench.attach(store, config, {
    ensure_thread = function(opts)
      return require("neovim_codex").new_thread(vim.tbl_extend("force", opts or {}, { wait = true, notify = false }))
    end,
    submit_packet = function(message, input)
      return require("neovim_codex").submit_text(message, {
        input = input,
        notify = false,
      })
    end,
    after_packet_sent = function()
      chat.clear_draft()
    end,
  })

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

local function select_sync(items, opts)
  local choice = nil
  local finished = false
  vim.ui.select(items, opts or {}, function(item)
    choice = item
    finished = true
  end)
  vim.wait(10000, function()
    return finished
  end, 20)
  return choice
end

local function input_sync(opts)
  local value = nil
  local finished = false
  vim.ui.input(opts or {}, function(input)
    value = input
    finished = true
  end)
  vim.wait(10000, function()
    return finished
  end, 20)
  return value
end

local function select_async(items, opts, on_choice)
  vim.schedule(function()
    vim.ui.select(items, opts or {}, function(item)
      vim.schedule(function()
        on_choice(item)
      end)
    end)
  end)
end

local function input_async(opts, on_input)
  vim.schedule(function()
    vim.ui.input(opts or {}, function(input)
      vim.schedule(function()
        on_input(input)
      end)
    end)
  end)
end

local compact_text = thread_runtime.compact_text
local clone_runtime_settings = thread_runtime.clone_settings
local effective_runtime_model = thread_runtime.effective_model
local effective_runtime_effort = thread_runtime.effective_effort
local normalize_runtime_settings = thread_runtime.normalize

local function runtime_picker(rt)
  return thread_runtime_picker.new({
    client = rt.client,
    request_with_wait = request_with_wait,
    notify = function(message, level, enabled)
      notify(message, level, enabled)
    end,
    experimental_api = config.experimental_api,
  })
end

local function query_loaded_threads(rt, opts)
  return runtime_picker(rt):query_loaded_threads(opts)
end

local function pick_thread_runtime_async(rt, opts, on_done)
  return runtime_picker(rt):pick_async(opts, on_done)
end

local function turn_preview(turn, index)
  local summary = nil
  for _, item in ipairs(turn.items or {}) do
    if item.type == "userMessage" or item.type == "agentMessage" then
      summary = compact_text(item.text, 88)
      if summary then
        break
      end
    end
  end
  summary = summary or "(no message preview)"
  return string.format("Turn %d · %s · %s", index, tostring(turn.status or "unknown"), summary)
end

local function build_thread_start_params(opts)
  return thread_params.build_thread_start(config, current_cwd(), opts)
end

local function build_thread_resume_params(opts)
  return thread_params.build_thread_resume(config, opts)
end

local function build_thread_fork_params(opts)
  return thread_params.build_thread_fork(config, opts)
end

local function build_thread_list_params(opts)
  return thread_params.build_thread_list(config, current_cwd(), opts)
end

local function build_turn_start_params(thread_id, text, opts)
  return thread_params.build_turn_start(config, thread_id, text, opts)
end

local function chat_actions()
  return {
    submit_text = function(text)
      return require("neovim_codex").submit_text(text)
    end,
  }
end

local function reveal_chat(rt, mode)
  if mode then
    return chat.open_with_mode(rt.store, config, chat_actions(), mode)
  end
  return chat.open(rt.store, config, chat_actions())
end

local function toggle_chat(rt)
  return chat.toggle(rt.store, config, chat_actions())
end

local function short_thread_id(thread_id)
  return thread_identity.short_id(thread_id)
end

local function thread_title(thread)
  return thread_identity.title(thread)
end

local function format_thread_label(thread, active_id, state, loaded_threads)
  local marker = thread.id == active_id and "●" or "○"
  local status = thread.status and thread.status.type or "unknown"
  local loaded = loaded_threads and loaded_threads[thread.id] and "⚡ " or ""
  local pending = selectors.pending_request_count_for_thread(state, thread.id)
  local pending_text = pending > 0 and string.format(" · inbox:%d", pending) or ""
  return string.format("%s %s%s  [%s]%s  %s", marker, loaded, short_thread_id(thread.id), status, pending_text, thread_title(thread))
end

local function merge_known_threads(threads, state, opts)
  local merged = {}
  local seen = {}
  for _, thread in ipairs(threads or {}) do
    merged[#merged + 1] = thread
    seen[thread.id] = true
  end

  local expected_archived = opts.archived ~= nil and opts.archived or config.thread_list.archived
  local expected_cwd = opts.cwd or (config.thread_list.cwd_only and current_cwd() or nil)
  for _, thread in ipairs(selectors.list_threads(state)) do
    if not seen[thread.id] and thread.closed ~= true then
      local archived_ok = expected_archived == true and thread.archived == true or expected_archived ~= true and thread.archived ~= true
      local cwd_ok = expected_cwd == nil or thread.cwd == nil or thread.cwd == expected_cwd
      if archived_ok and cwd_ok then
        merged[#merged + 1] = thread
        seen[thread.id] = true
      end
    end
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

function M.open_chat_rail()
  local rt = ensure_runtime()
  if not chat.is_visible() and not rt.client:status().initialized then
    M.start()
  end
  return reveal_chat(rt, "rail")
end

function M.open_chat_reader()
  local rt = ensure_runtime()
  if not chat.is_visible() and not rt.client:status().initialized then
    M.start()
  end
  return reveal_chat(rt, "reader")
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
  if workbench.has_fragments() then
    return workbench.open_review(chat.read_draft())
  end
  return chat.submit()
end

local function update_thread_runtime(thread_id, runtime_settings)
  if not thread_id then
    return
  end
  ensure_runtime().store:dispatch({
    type = "thread_runtime_updated",
    thread_id = thread_id,
    runtime = normalize_runtime_settings(runtime_settings or {}),
  })
end

local function current_thread_runtime(thread_id)
  local state = ensure_runtime().client:get_state()
  local thread = selectors.get_thread(state, thread_id) or selectors.get_active_thread(state)
  return normalize_runtime_settings(clone_runtime_settings(thread))
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

  if result and result.thread then
    update_thread_runtime(result.thread.id, {
      model = opts.model,
      effort = opts.effort,
      summary = opts.summary,
      collaborationModeMask = opts.collaboration_mode_mask,
      ephemeral = opts.ephemeral,
    })
    if opts.name and vim.trim(tostring(opts.name)) ~= "" then
      submit_thread_rename(rt, result.thread, opts.name, { wait = true, notify = false, timeout_ms = opts.timeout_ms })
    end
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

  if result and result.thread then
    local runtime_settings = clone_runtime_settings(result.thread)
    if opts.model ~= nil then runtime_settings.model = opts.model end
    if opts.effort ~= nil then runtime_settings.effort = opts.effort end
    if opts.summary ~= nil then runtime_settings.summary = opts.summary end
    if opts.collaboration_mode_mask ~= nil then runtime_settings.collaborationModeMask = opts.collaboration_mode_mask end
    update_thread_runtime(result.thread.id, runtime_settings)
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
  local rt, ready_err = ensure_ready(opts.timeout_ms)
  if not rt then
    notify(ready_err, vim.log.levels.ERROR, opts.notify)
    return nil, ready_err
  end

  local result, err = M.list_threads(vim.tbl_extend("force", opts, { notify = false }))
  if err then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  local state = M.get_state()
  local loaded_threads = query_loaded_threads(rt, opts)
  if type(loaded_threads) ~= "table" then
    loaded_threads = {}
  end

  local threads = merge_known_threads(result.data or {}, state, opts)
  if #threads == 0 then
    notify("No matching Codex threads found", vim.log.levels.INFO, opts.notify)
    return nil, "no threads found"
  end

  local active_id = state.threads.active_id
  vim.ui.select(threads, {
    prompt = opts.prompt or "Select Codex thread",
    format_item = function(thread)
      return format_thread_label(thread, active_id, state, loaded_threads)
    end,
  }, function(choice)
    if not choice then
      return
    end

    if opts.action == "read" then
      M.open_thread_report({ thread_id = choice.id, notify = opts.notify })
      return
    end
    if opts.action == "archive" then
      M.archive_thread({ thread_id = choice.id, notify = opts.notify })
      return
    end

    local local_thread = selectors.get_thread(M.get_state(), choice.id)
    if choice.id == M.get_state().threads.active_id then
      reveal_chat(rt)
      return
    end

    if loaded_threads[choice.id] and local_thread and #((local_thread.turns_order) or {}) > 0 then
      rt.store:dispatch({ type = "thread_activated", thread_id = choice.id })
      reveal_chat(rt)
      return
    end

    M.resume_thread({ thread_id = choice.id, open_chat = true, notify = opts.notify })
  end)

  return threads, nil
end

function M.create_thread_with_settings(opts)
  opts = opts or {}
  local rt, err = ensure_ready(opts.timeout_ms)
  if not rt then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  pick_thread_runtime_async(rt, {
    include_name = true,
    include_ephemeral = true,
    seed = opts.seed,
    timeout_ms = opts.timeout_ms,
    notify = opts.notify,
  }, function(settings, settings_err)
    if settings_err then
      if settings_err ~= "cancelled" then
        notify(settings_err, vim.log.levels.ERROR, opts.notify)
      end
      return
    end

    M.new_thread(vim.tbl_extend("force", opts, {
      name = settings.name,
      ephemeral = settings.ephemeral,
      model = settings.model,
      effort = settings.effort,
      collaboration_mode_mask = settings.collaborationModeMask,
    }))
  end)

  return { pending = true }, nil
end

function M.configure_thread(opts)
  opts = opts or {}
  local rt, err = ensure_ready(opts.timeout_ms)
  if not rt then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  local snapshot = rt.client:get_state()
  local thread = opts.thread_id and selectors.get_thread(snapshot, opts.thread_id) or selectors.get_active_thread(snapshot)
  if not thread then
    return nil, "no active thread"
  end

  local seed = clone_runtime_settings(thread)
  seed.ephemeral = thread.ephemeral == true or seed.ephemeral == true
  pick_thread_runtime_async(rt, {
    include_name = false,
    include_ephemeral = false,
    seed = seed,
    timeout_ms = opts.timeout_ms,
    notify = opts.notify,
  }, function(settings, settings_err)
    if settings_err then
      if settings_err ~= "cancelled" then
        notify(settings_err, vim.log.levels.ERROR, opts.notify)
      end
      return
    end

    update_thread_runtime(thread.id, {
      model = settings.model,
      effort = settings.effort,
      summary = seed.summary,
      collaborationModeMask = settings.collaborationModeMask,
      ephemeral = seed.ephemeral,
    })

    notify(string.format("Updated thread settings · %s", short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
  end)

  return { threadId = thread.id }, nil
end

function M.fork_thread(opts)
  opts = opts or {}
  local rt, err = ensure_ready(opts.timeout_ms)
  if not rt then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  local source_thread = opts.thread_id and selectors.get_thread(rt.client:get_state(), opts.thread_id) or selectors.get_active_thread(rt.client:get_state())
  if not source_thread then
    return nil, "no active thread"
  end

  local thread_result, thread_err = M.read_thread({ thread_id = source_thread.id, include_turns = true, notify = false, timeout_ms = opts.timeout_ms })
  if thread_err then
    notify(thread_err, vim.log.levels.ERROR, opts.notify)
    return nil, thread_err
  end

  local turns = thread_result.thread.turns or {}
  if #turns == 0 then
    return nil, "thread has no turns to fork"
  end

  local turn_choices = {}
  for index, turn in ipairs(turns) do
    turn_choices[#turn_choices + 1] = { index = index, turn = turn }
  end
  select_async(turn_choices, {
    prompt = "Fork from turn",
    format_item = function(item)
      return turn_preview(item.turn, item.index)
    end,
  }, function(selected)
    if not selected then
      return
    end

    local seed = clone_runtime_settings(source_thread)
    seed.name = thread_title(source_thread)
    seed.ephemeral = source_thread.ephemeral == true or seed.ephemeral == true
    pick_thread_runtime_async(rt, {
      include_name = true,
      include_ephemeral = true,
      seed = seed,
      timeout_ms = opts.timeout_ms,
      notify = opts.notify,
    }, function(settings, settings_err)
      if settings_err then
        if settings_err ~= "cancelled" then
          notify(settings_err, vim.log.levels.ERROR, opts.notify)
        end
        return
      end

      local fork_result, fork_err = request_with_wait(function(done)
        rt.client:thread_fork(build_thread_fork_params({
          thread_id = source_thread.id,
          cwd = opts.cwd,
          model = settings.model,
          approval_policy = opts.approval_policy,
          sandbox = opts.sandbox,
          ephemeral = settings.ephemeral,
        }), done)
      end, wait_opts(opts))
      if fork_err then
        notify(fork_err, vim.log.levels.ERROR, opts.notify)
        return
      end

      local dropped_turns = #turns - selected.index
      if dropped_turns > 0 then
        local rollback_result, rollback_err = request_with_wait(function(done)
          rt.client:thread_rollback({ threadId = fork_result.thread.id, numTurns = dropped_turns }, done)
        end, wait_opts(opts))
        if rollback_err then
          notify(rollback_err, vim.log.levels.ERROR, opts.notify)
          return
        end
        fork_result = rollback_result or fork_result
      end

      update_thread_runtime(fork_result.thread.id, {
        model = settings.model,
        effort = settings.effort,
        summary = seed.summary,
        collaborationModeMask = settings.collaborationModeMask,
        ephemeral = settings.ephemeral,
      })
      if settings.name and settings.name ~= "" then
        submit_thread_rename(rt, fork_result.thread, settings.name, { wait = true, notify = false, timeout_ms = opts.timeout_ms })
      end

      reveal_chat(rt)
      notify(string.format("Forked thread %s from %s", short_thread_id(fork_result.thread.id), short_thread_id(source_thread.id)), vim.log.levels.INFO, opts.notify)
    end)
  end)

  return { threadId = source_thread.id }, nil
end

submit_thread_rename = function(rt, thread, name, opts)
  local normalized_name = vim.trim(tostring(name))

  if opts.wait == true then
    local result, request_err = request_with_wait(function(done)
      rt.client:thread_name_set({ threadId = thread.id, name = normalized_name }, done)
    end, wait_opts(opts))

    if request_err then
      notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    if normalized_name == "" then
      notify(string.format("Cleared thread name · %s", short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
    else
      notify(string.format("Renamed thread %s to %s", short_thread_id(thread.id), normalized_name), vim.log.levels.INFO, opts.notify)
    end
    return result, nil
  end

  rt.client:thread_name_set({ threadId = thread.id, name = normalized_name }, function(request_err)
    if request_err then
      notify(request_err, vim.log.levels.ERROR, opts.notify)
      return
    end

    if normalized_name == "" then
      notify(string.format("Cleared thread name · %s", short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
    else
      notify(string.format("Renamed thread %s to %s", short_thread_id(thread.id), normalized_name), vim.log.levels.INFO, opts.notify)
    end
  end)

  return { threadId = thread.id, name = normalized_name }, nil
end

function M.rename_thread(opts)
  opts = opts or {}
  local rt, err = ensure_ready(opts.timeout_ms)
  if not rt then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  local snapshot = rt.client:get_state()
  local thread = opts.thread_id and selectors.get_thread(snapshot, opts.thread_id) or selectors.get_active_thread(snapshot)
  if not thread then
    notify("No active Codex thread to rename", vim.log.levels.INFO, opts.notify)
    return nil, "no active thread"
  end

  local name = opts.name
  if name == nil then
    vim.ui.input({
      prompt = string.format("Rename Codex thread %s: ", short_thread_id(thread.id)),
      default = thread.name ~= nil and thread.name ~= vim.NIL and tostring(thread.name) or thread_title(thread),
    }, function(input)
      if input == nil then
        notify("Cancelled thread rename", vim.log.levels.INFO, opts.notify)
        return
      end
      M.rename_thread({
        thread_id = thread.id,
        name = input,
        notify = opts.notify,
        timeout_ms = opts.timeout_ms,
        wait = true,
      })
    end)
    return { threadId = thread.id }, nil
  end

  return submit_thread_rename(rt, thread, name, opts)
end

function M.archive_thread(opts)
  opts = opts or {}
  local rt, err = ensure_ready(opts.timeout_ms)
  if not rt then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  local snapshot = rt.client:get_state()
  local thread = opts.thread_id and selectors.get_thread(snapshot, opts.thread_id) or selectors.get_active_thread(snapshot)
  if not thread then
    return M.pick_thread({ action = "archive", notify = opts.notify, timeout_ms = opts.timeout_ms })
  end

  local _, request_err = request_with_wait(function(done)
    rt.client:thread_archive({ threadId = thread.id }, done)
  end, wait_opts(opts))
  if request_err then
    notify(request_err, vim.log.levels.ERROR, opts.notify)
    return nil, request_err
  end

  if snapshot.threads.active_id == thread.id then
    rt.store:dispatch({ type = "thread_activated", thread_id = nil })
  end

  notify(string.format("Archived thread %s", short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
  return { threadId = thread.id }, nil
end

function M.open_shortcuts(opts)
  opts = opts or {}
  return require("neovim_codex.nvim.shortcuts").open(config, opts)
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
    rt.client:turn_start(build_turn_start_params(active_thread.id, prompt, vim.tbl_extend("force", opts, {
      thread_runtime = clone_runtime_settings(active_thread),
    })), done)
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
  return presentation.status_line(state.connection, state.threads, state.server_requests, state.workbench)
end

function M.toggle_workbench()
  local rt, err = ensure_ready(4000)
  if not rt then
    notify(err, vim.log.levels.ERROR, true)
    return nil, err
  end

  return workbench.toggle()
end

function M.open_compose_review(opts)
  opts = opts or {}
  local rt, err = ensure_ready(opts.timeout_ms or 4000)
  if not rt then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end

  local draft = opts.seed_message
  if draft == nil then
    draft = chat.read_draft()
  end
  return workbench.open_review(draft)
end

function M.capture_current_file(opts)
  opts = opts or {}
  local result, err = workbench.add_path(opts)
  if err then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end
  return result, nil
end

function M.capture_visual_selection(opts)
  opts = opts or {}
  local result, err = workbench.add_selection(opts)
  if err then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end
  return result, nil
end

function M.capture_current_diagnostic(opts)
  opts = opts or {}
  local result, err = workbench.add_diagnostic(opts)
  if err then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end
  return result, nil
end

function M.capture_text_fragment(opts)
  opts = opts or {}
  local result, err = workbench.add_text_fragment(opts)
  if err then
    notify(err, vim.log.levels.ERROR, opts.notify)
    return nil, err
  end
  return result, nil
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

function M.open_request(opts)
  opts = opts or {}
  local rt = ensure_runtime()
  local thread_id = opts.thread_id or (selectors.get_active_thread(rt.client:get_state()) and selectors.get_active_thread(rt.client:get_state()).id)
  local request, err = rt.requests:open_current({ thread_id = thread_id })
  if err then
    notify(err, vim.log.levels.INFO, opts.notify)
    return nil, err
  end
  return request, nil
end

function M.get_chat_state()
  return chat.inspect()
end

function M.get_workbench_state()
  return workbench.inspect()
end

function M.get_request_state()
  local rt = ensure_runtime()
  return rt.requests:inspect()
end

function M.get_config()
  return vim.deepcopy(config)
end

return M
