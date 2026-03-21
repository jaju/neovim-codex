local client_mod = require("neovim_codex.core.client")
local selectors = require("neovim_codex.core.selectors")
local store_mod = require("neovim_codex.core.store")
local chat = require("neovim_codex.nvim.chat")
local file_change_review = require("neovim_codex.nvim.file_change_review")
local presentation = require("neovim_codex.nvim.presentation")
local requests = require("neovim_codex.nvim.server_requests")
local smoke = require("neovim_codex.nvim.smoke")
local statusline = require("neovim_codex.nvim.statusline")
local workbench = require("neovim_codex.nvim.workbench")
local transport_mod = require("neovim_codex.nvim.transport")
local thread_params = require("neovim_codex.nvim.thread_params")
local thread_runtime = require("neovim_codex.nvim.thread_runtime")
local thread_api_mod = require("neovim_codex.nvim.thread_api")
local chat_layout = require("neovim_codex.nvim.chat.layout")

local M = {}

local defaults = {
  codex_cmd = { "codex", "app-server" },
  client_info = {
    name = "neovim_codex",
    title = "NeoVim Codex",
    version = "0.4.0",
  },
  experimental_api = true,
  max_log_entries = 400,
  thread = {
    cwd = "current",
    approval_policy = "on-request",
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
    global_fast_modes = { "n", "i", "x" },
    global_workflow_modes = { "n" },
    global_modes = { "n", "i", "x" },
    surface_help = "<F1>",
    global = {
      chat = "<C-,>",
      chat_overlay = false,
      new_thread = false,
      new_thread_config = false,
      threads = false,
      read_thread = false,
      thread_rename = false,
      thread_fork = false,
      thread_archive = false,
      thread_unarchive = false,
      thread_settings = false,
      thread_compact = false,
      interrupt = false,
      turn_steer = false,
      shortcuts = false,
      request = "<F2>",
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
      settings = "gs",
    },
    composer = {
      send = "<C-s>",
      send_normal = "gS",
      steer = "gT",
      switch_pane = "<C-w>w",
      close = "q",
      help = "g?",
      request = "gr",
      toggle_reader = "gR",
      settings = "gs",
    },
    request = {
      respond = "<CR>",
      review = "o",
      accept = "a",
      accept_for_session = "s",
      decline = "d",
      cancel = "c",
      help = "g?",
    },
    file_change_review = {
      open_file = "o",
      next_file = "]f",
      prev_file = "[f",
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

local function global_modes_for(lane, fallback)
  local keymaps = config.keymaps or {}
  if lane == "fast" then
    return keymaps.global_fast_modes or keymaps.global_modes or fallback
  end
  return keymaps.global_workflow_modes or keymaps.global_modes or fallback
end

local function apply_global_keymaps()
  local keymaps = config.keymaps.global or {}
  local fast_modes = global_modes_for("fast", { "n", "i", "x" })
  local workflow_modes = global_modes_for("workflow", { "n" })

  map_if(keymaps.chat, fast_modes, function()
    require("neovim_codex").chat()
  end, "Open the Codex side rail")
  map_if(keymaps.chat_overlay, fast_modes, function()
    require("neovim_codex").open_chat_overlay()
  end, "Open the centered Codex overlay")
  map_if(keymaps.request, fast_modes, function()
    require("neovim_codex").open_request()
  end, "Open the active Codex request")
  map_if(keymaps.shortcuts, fast_modes, function()
    require("neovim_codex").open_shortcuts()
  end, "Show contextual Codex shortcuts")

  map_if(keymaps.new_thread, workflow_modes, function()
    require("neovim_codex").new_thread()
  end, "Create a new Codex thread")
  map_if(keymaps.new_thread_config, workflow_modes, function()
    require("neovim_codex").create_thread_with_settings()
  end, "Create a configured Codex thread")
  map_if(keymaps.threads, workflow_modes, function()
    require("neovim_codex").pick_thread({ action = "resume" })
  end, "Pick a Codex thread")
  map_if(keymaps.read_thread, workflow_modes, function()
    require("neovim_codex").pick_thread({ action = "read" })
  end, "Read a Codex thread")
  map_if(keymaps.thread_rename, workflow_modes, function()
    require("neovim_codex").rename_thread()
  end, "Rename the active Codex thread")
  map_if(keymaps.thread_fork, workflow_modes, function()
    require("neovim_codex").fork_thread()
  end, "Fork the active Codex thread")
  map_if(keymaps.thread_archive, workflow_modes, function()
    require("neovim_codex").archive_thread()
  end, "Archive a Codex thread")
  map_if(keymaps.thread_unarchive, workflow_modes, function()
    require("neovim_codex").unarchive_thread()
  end, "Restore an archived Codex thread")
  map_if(keymaps.thread_settings, workflow_modes, function()
    require("neovim_codex").configure_thread()
  end, "Configure the active Codex thread")
  map_if(keymaps.thread_compact, workflow_modes, function()
    require("neovim_codex").compact_thread()
  end, "Compact Codex thread history")
  map_if(keymaps.interrupt, workflow_modes, function()
    require("neovim_codex").interrupt()
  end, "Interrupt the active Codex turn")
  map_if(keymaps.turn_steer, workflow_modes, function()
    require("neovim_codex").steer()
  end, "Steer the running Codex turn")
  map_if(keymaps.workbench, workflow_modes, function()
    require("neovim_codex").toggle_workbench()
  end, "Toggle the Codex workbench")
  map_if(keymaps.compose, workflow_modes, function()
    require("neovim_codex").open_compose_review()
  end, "Open Codex compose review")
  map_if(keymaps.capture_path, workflow_modes, function()
    require("neovim_codex").capture_current_file()
  end, "Add the current file to the Codex workbench")
  if keymaps.capture_selection then
    vim.keymap.set("x", keymaps.capture_selection, function()
      require("neovim_codex").capture_visual_selection()
    end, { silent = true, desc = "Add the current selection to the Codex workbench" })
  end
  map_if(keymaps.capture_diagnostic, workflow_modes, function()
    require("neovim_codex").capture_current_diagnostic()
  end, "Add the current diagnostic to the Codex workbench")
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
    json = vim.json,
    client_info = config.client_info,
    experimental_api = config.experimental_api,
  })
  local review_manager = file_change_review.new(config, {
    notify = function(message, level)
      notify(message, level, true)
    end,
    respond_request = function(request, payload)
      return send_server_request_response(request.key, payload)
    end,
  })
  local request_manager = requests.new(config, {
    notify = function(message, level)
      notify(message, level, true)
    end,
    respond_request = function(request, payload)
      return send_server_request_response(request.key, payload)
    end,
    open_file_change_review = function(request)
      return review_manager:open_current({ request_key = request.key })
    end,
  })
  request_manager:attach(store)
  review_manager:attach(store)
  statusline.attach(store, config)

  runtime = {
    store = store,
    transport = transport,
    client = client,
    requests = request_manager,
    review = review_manager,
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

local request_with_wait = thread_api_mod.request_with_wait
local wait_opts = thread_api_mod.wait_opts

local function current_cwd()
  return vim.fn.getcwd()
end

local clone_runtime_settings = thread_runtime.clone_settings

local function build_thread_start_params(opts)
  return thread_params.build_thread_start(config, current_cwd(), opts)
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
  statusline.configure(config)
  if runtime then
    statusline.attach(runtime.store, config)
  end
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
  local chat_state = chat.inspect()
  if chat_state.visible and chat_state.mode == "rail" then
    chat.close()
    return true
  end
  return reveal_chat(rt, "rail")
end

function M.open_chat_rail()
  local rt = ensure_runtime()
  if not chat.is_visible() and not rt.client:status().initialized then
    M.start()
  end
  return reveal_chat(rt, "rail")
end

function M.open_chat_overlay()
  local rt = ensure_runtime()
  if not chat.is_visible() and not rt.client:status().initialized then
    M.start()
  end
  return reveal_chat(rt, "reader")
end

function M.open_chat_reader()
  return M.open_chat_overlay()
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

local thread_api = thread_api_mod.new({
  ensure_runtime = ensure_runtime,
  ensure_ready = ensure_ready,
  notify = notify,
  reveal_chat = reveal_chat,
  workbench = workbench,
  chat = chat,
  get_config = function()
    return config
  end,
})

for _, method_name in ipairs({
  "new_thread",
  "resume_thread",
  "list_threads",
  "read_thread",
  "open_thread_report",
  "pick_thread",
  "create_thread_with_settings",
  "configure_thread",
  "fork_thread",
  "rename_thread",
  "archive_thread",
  "unarchive_thread",
  "compact_thread",
  "steer",
}) do
  M[method_name] = function(opts)
    return thread_api[method_name](opts)
  end
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
  if not runtime then
    return statusline.render_plain({
      connection = { status = "stopped" },
      threads = { by_id = {}, order = {}, active_id = nil },
      server_requests = { by_id = {}, order = {}, active_id = nil },
      workbench = { by_thread_id = {} },
    }, config)
  end
  return statusline.render_plain(runtime.client:get_state(), config)
end

function M.statusline()
  if not runtime then
    return statusline.render({
      connection = { status = "stopped" },
      threads = { by_id = {}, order = {}, active_id = nil },
      server_requests = { by_id = {}, order = {}, active_id = nil },
      workbench = { by_thread_id = {} },
    }, config)
  end
  return statusline.render(runtime.client:get_state(), config)
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

function M.open_review(opts)
  opts = opts or {}
  local rt = ensure_runtime()
  local request, err = rt.review:open_current(opts)
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
