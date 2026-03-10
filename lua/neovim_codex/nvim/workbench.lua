local packet = require("neovim_codex.core.packet")
local presentation = require("neovim_codex.nvim.presentation")
local viewer_stack = require("neovim_codex.nvim.viewer_stack")
local thread_identity = require("neovim_codex.nvim.thread_identity")

local M = {}

local state = {
  store = nil,
  opts = nil,
  actions = nil,
  tray = nil,
  review = nil,
  unsubscribe = nil,
}

local function notify(message, level, enabled)
  if enabled == false then
    return
  end
  vim.notify(message, level or vim.log.levels.INFO)
end

local function clone_value(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for key, item in pairs(value) do
    out[key] = clone_value(item)
  end
  return out
end

local function selectors()
  return require("neovim_codex.core.selectors")
end

local function ensure_modules()
  if state.tray and state.review then
    return true
  end

  local ok_tray, tray_mod = pcall(require, "neovim_codex.nvim.workbench.tray")
  if not ok_tray then
    notify(string.format("Failed to load workbench tray: %s", tray_mod), vim.log.levels.ERROR, true)
    return false
  end

  local ok_review, review_mod = pcall(require, "neovim_codex.nvim.workbench.review")
  if not ok_review then
    notify(string.format("Failed to load compose review: %s", review_mod), vim.log.levels.ERROR, true)
    return false
  end

  state.tray = tray_mod.new(state.opts, {
    close = function()
      viewer_stack.close("workbench-tray")
    end,
    inspect = function(fragment)
      M.inspect_fragment(fragment)
    end,
    remove = function(fragment)
      M.remove_fragment(fragment and fragment.id)
    end,
    clear = function()
      M.clear()
    end,
    compose = function()
      M.open_review()
    end,
    insert_handle = function(fragment)
      M.open_review_for_fragment(fragment)
    end,
    park = function(fragment)
      M.park_fragment(fragment and fragment.id)
    end,
    unpark = function(fragment)
      M.unpark_fragment(fragment and fragment.id)
    end,
    preview = function()
      M.preview_packet()
    end,
    open_help = function()
      require("neovim_codex").open_shortcuts({ surface = "workbench" })
    end,
  })

  state.review = review_mod.new(state.opts, {
    close = function()
      viewer_stack.close("compose-review")
    end,
    send = function()
      M.send_packet()
    end,
    preview = function()
      M.preview_packet()
    end,
    inspect = function(fragment)
      M.inspect_fragment(fragment)
    end,
    remove = function(fragment)
      M.remove_fragment(fragment and fragment.id)
    end,
    clear = function()
      M.clear()
    end,
    park = function(fragment)
      M.park_fragment(fragment and fragment.id)
    end,
    unpark = function(fragment)
      M.unpark_fragment(fragment and fragment.id)
    end,
    open_help = function()
      require("neovim_codex").open_shortcuts({ surface = "compose_review" })
    end,
    message_changed = function(message)
      M.set_message(message)
    end,
  })

  return true
end

local function active_thread_id()
  if not state.store then
    return nil
  end
  return state.store:get_state().threads.active_id
end

local function active_workbench()
  if not state.store then
    return nil, nil
  end

  local snapshot = state.store:get_state()
  return selectors().get_active_workbench(snapshot), snapshot.threads.active_id
end

local function refresh_ui()
  if not ensure_modules() then
    return
  end

  local workbench, thread_id = active_workbench()
  if not thread_id then
    return nil, "No active thread for compose review"
  end
  local fragments = selectors().list_fragments(workbench)
  local message = selectors().workbench_message(workbench)
  if viewer_stack.is_open("workbench-tray") then
    viewer_stack.refresh("workbench-tray", M._tray_viewer_spec(thread_id, fragments))
  else
    state.tray:update(thread_id, fragments)
  end

  if viewer_stack.is_open("compose-review") then
    viewer_stack.refresh("compose-review", M._review_viewer_spec(thread_id, message, fragments))
  else
    state.review:update(thread_id, message, fragments)
  end
end

local function attach(store)
  if state.unsubscribe then
    state.unsubscribe()
    state.unsubscribe = nil
  end

  state.store = store
  state.unsubscribe = store:subscribe(function(_, event)
    if not event.type:match("^workbench_") and event.type ~= "thread_activated" and event.type ~= "thread_received" then
      return
    end
    vim.schedule(refresh_ui)
  end)
end

local function now_id(prefix)
  return string.format("%s_%d_%d", prefix, os.time(), math.random(1000, 9999))
end

local function display_path(path)
  local text = tostring(path or "")
  local home = vim.env.HOME
  if home and text:sub(1, #home) == home then
    return "~" .. text:sub(#home + 1)
  end
  return text
end

local function diagnostic_severity_label(severity)
  if severity == vim.diagnostic.severity.ERROR then
    return "error"
  end
  if severity == vim.diagnostic.severity.WARN then
    return "warn"
  end
  if severity == vim.diagnostic.severity.INFO then
    return "info"
  end
  if severity == vim.diagnostic.severity.HINT then
    return "hint"
  end
  return nil
end

local function current_file_target()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return nil, "Current buffer is not backed by a file"
  end

  if vim.bo[bufnr].buftype ~= "" or path:match("^neovim%-codex://") then
    return nil, "Current buffer is not a normal file buffer"
  end

  return {
    bufnr = bufnr,
    path = path,
    filetype = vim.bo[bufnr].filetype,
  }, nil
end

local function current_diagnostic_target()
  local target, err = current_file_target()
  if err then
    return nil, nil, err
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1] - 1
  local col = cursor[2]
  local diagnostics = vim.diagnostic.get(target.bufnr, { lnum = lnum })
  if not diagnostics or #diagnostics == 0 then
    return nil, nil, "No diagnostic under cursor"
  end

  local current = diagnostics[1]
  for _, diagnostic in ipairs(diagnostics) do
    local start_col = tonumber(diagnostic.col) or 0
    local end_col = tonumber(diagnostic.end_col) or start_col
    if end_col < start_col then
      end_col = start_col
    end
    if col >= start_col and col <= end_col then
      current = diagnostic
      break
    end
  end

  return target, current, nil
end

local function ensure_thread(opts)
  local thread_id = active_thread_id()
  if thread_id then
    return thread_id, nil
  end

  local create = state.actions and state.actions.ensure_thread
  if not create then
    return nil, "No active thread and thread creation is unavailable"
  end

  local result, err = create(opts or {})
  if err then
    return nil, err
  end

  return result.thread.id, nil
end

local function add_fragment_for_thread(thread_id, fragment, opts)
  state.store:dispatch({
    type = "workbench_fragment_added",
    thread_id = thread_id,
    fragment = fragment,
  })

  local workbench = selectors().get_workbench(state.store:get_state(), thread_id)
  local stored_fragment = selectors().get_fragment(workbench, fragment.id) or fragment
  notify(string.format("Added %s to workbench · thread %s", stored_fragment.kind, thread_id), vim.log.levels.INFO, opts and opts.notify)
  refresh_ui()
  return stored_fragment, nil
end

function M.attach(store, opts, actions)
  state.opts = opts
  state.actions = actions or {}
  attach(store)
  ensure_modules()
  refresh_ui()
end

function M.toggle()
  if not ensure_modules() then
    return false, "workbench UI is unavailable"
  end

  local workbench, thread_id = active_workbench()
  if viewer_stack.is_open("workbench-tray") then
    viewer_stack.close("workbench-tray")
    return false, nil
  end

  viewer_stack.open(M._tray_viewer_spec(thread_id, selectors().list_fragments(workbench)))
  return true, nil
end

function M.open_review(seed_message)
  if not ensure_modules() then
    return nil, "compose review UI is unavailable"
  end

  local workbench, thread_id = active_workbench()
  if not thread_id then
    return nil, "No active thread"
  end

  local fragments = selectors().list_fragments(workbench)
  local current_message = selectors().workbench_message(workbench)
  if seed_message ~= nil and current_message == "" then
    state.store:dispatch({ type = "workbench_message_updated", thread_id = thread_id, message = seed_message })
    workbench = selectors().get_active_workbench(state.store:get_state())
    current_message = selectors().workbench_message(workbench)
  end

  viewer_stack.close("workbench-tray")
  viewer_stack.open(M._review_viewer_spec(thread_id, current_message, fragments))
  return true, nil
end

function M.open_review_for_fragment(fragment)
  if not fragment then
    return nil, "No fragment is selected"
  end

  local ok, err = M.open_review()
  if not ok then
    return nil, err
  end

  if not state.review or not state.review.insert_handle then
    return nil, "Compose review is unavailable"
  end

  if not state.review:insert_handle(fragment) then
    return nil, "Failed to insert fragment handle"
  end

  return true, nil
end

function M.set_message(message)
  local thread_id = active_thread_id()
  if not thread_id then
    return nil, "No active thread for compose review"
  end
  state.store:dispatch({ type = "workbench_message_updated", thread_id = thread_id, message = message })
  return true, nil
end

function M.add_path(opts)
  opts = opts or {}
  local target, err = current_file_target()
  if err then
    return nil, err
  end

  local thread_id, err = ensure_thread({ notify = false, open_chat = false })
  if err then
    return nil, err
  end

  local fragment = {
    id = now_id("path"),
    kind = "path_ref",
    label = display_path(target.path),
    path = target.path,
    filetype = target.filetype,
    source = "buffer",
  }

  return add_fragment_for_thread(thread_id, fragment, opts)
end

function M.add_selection(opts)
  opts = opts or {}
  local target, err = current_file_target()
  if err then
    return nil, err
  end

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = tonumber(start_pos[2])
  local end_line = tonumber(end_pos[2])
  if not start_line or not end_line or start_line == 0 or end_line == 0 then
    return nil, "Visual selection is required"
  end
  if end_line < start_line then
    start_line, end_line = end_line, start_line
  end

  local lines = vim.api.nvim_buf_get_lines(target.bufnr, start_line - 1, end_line, false)
  local text = table.concat(lines, "\n")
  if vim.trim(text) == "" then
    return nil, "Visual selection is empty"
  end

  local thread_id, err = ensure_thread({ notify = false, open_chat = false })
  if err then
    return nil, err
  end

  local label = string.format("%s:%d-%d", display_path(target.path), start_line, end_line)
  local fragment = {
    id = now_id("code"),
    kind = "code_range",
    label = label,
    path = target.path,
    filetype = target.filetype,
    range = { start_line = start_line, end_line = end_line },
    text = text,
    source = "visual_selection",
  }

  return add_fragment_for_thread(thread_id, fragment, opts)
end

function M.add_diagnostic(opts)
  opts = opts or {}
  local target, diagnostic, err = current_diagnostic_target()
  if err then
    return nil, err
  end

  local thread_id, err = ensure_thread({ notify = false, open_chat = false })
  if err then
    return nil, err
  end

  local start_line = (tonumber(diagnostic.lnum) or 0) + 1
  local end_line = (tonumber(diagnostic.end_lnum) or tonumber(diagnostic.lnum) or 0) + 1
  local code = diagnostic.code and tostring(diagnostic.code) or nil
  local severity = diagnostic_severity_label(diagnostic.severity)
  local label = string.format("%s %s:%d", code or "diagnostic", display_path(target.path), start_line)
  local fragment = {
    id = now_id("diag"),
    kind = "diagnostic",
    label = label,
    path = target.path,
    filetype = target.filetype,
    range = { start_line = start_line, end_line = end_line },
    message = diagnostic.message,
    source = diagnostic.source or "diagnostic",
    severity = severity,
    code = code,
  }

  return add_fragment_for_thread(thread_id, fragment, opts)
end

function M.remove_fragment(fragment_id, opts)
  opts = opts or {}
  if not fragment_id then
    return nil, "No fragment is selected"
  end

  local thread_id = active_thread_id()
  if not thread_id then
    return nil, "No active thread"
  end

  state.store:dispatch({ type = "workbench_fragment_removed", thread_id = thread_id, fragment_id = fragment_id })
  notify("Removed fragment from workbench", vim.log.levels.INFO, opts.notify)
  refresh_ui()
  return true, nil
end

function M.set_fragment_parked(fragment_id, parked, opts)
  opts = opts or {}
  if not fragment_id then
    return nil, "No fragment is selected"
  end

  local thread_id = active_thread_id()
  if not thread_id then
    return nil, "No active thread"
  end

  state.store:dispatch({
    type = "workbench_fragment_parked",
    thread_id = thread_id,
    fragment_id = fragment_id,
    parked = parked == true,
  })
  notify(parked and "Parked fragment" or "Unparked fragment", vim.log.levels.INFO, opts.notify)
  refresh_ui()
  return true, nil
end

function M.park_fragment(fragment_id, opts)
  return M.set_fragment_parked(fragment_id, true, opts)
end

function M.unpark_fragment(fragment_id, opts)
  return M.set_fragment_parked(fragment_id, false, opts)
end

function M.clear(opts)
  opts = opts or {}
  local thread_id = active_thread_id()
  if not thread_id then
    return nil, "No active thread"
  end

  state.store:dispatch({ type = "workbench_cleared", thread_id = thread_id })
  notify(string.format("Cleared workbench · thread %s", thread_id), vim.log.levels.INFO, opts.notify)
  refresh_ui()
  return true, nil
end

function M.fragment_count()
  if not state.store then
    return 0
  end
  return selectors().workbench_fragment_count(state.store:get_state())
end

function M.has_fragments()
  return M.fragment_count() > 0
end

function M.send_packet()
  local workbench, thread_id = active_workbench()
  if not thread_id then
    return nil, "No active thread"
  end

  local fragments = selectors().list_fragments(workbench)
  local message = selectors().workbench_message(workbench)
  local submit = state.actions and state.actions.submit_packet
  if not submit then
    return nil, "Packet submission is unavailable"
  end

  local input, compiled, build_err = packet.build_input_items(message, fragments)
  if build_err then
    notify(build_err, vim.log.levels.ERROR, true)
    return nil, build_err
  end

  local result, err = submit(compiled.compiled_text, input)
  if err then
    notify(err, vim.log.levels.ERROR, true)
    return nil, err
  end

  state.store:dispatch({ type = "workbench_active_cleared", thread_id = thread_id })
  state.store:dispatch({ type = "workbench_message_updated", thread_id = thread_id, message = "" })
  if state.actions.after_packet_sent then
    state.actions.after_packet_sent()
  end
  viewer_stack.close("compose-review")
  refresh_ui()
  return result, nil
end

function M.preview_packet()
  local workbench, thread_id = active_workbench()
  if not thread_id then
    return nil, "No active thread"
  end

  local fragments = selectors().list_fragments(workbench)
  local message = selectors().workbench_message(workbench)
  local lines = nil
  local analysis = nil
  local err = nil
  lines, analysis, err = packet.preview_lines(message, fragments)
  local key = string.format("packet-preview-%s", thread_id)
  local title = string.format("Packet preview · thread %s", thread_identity.short_id(thread_id))
  presentation.open_report(key, lines, {
    title = title,
    role = "packet_preview",
    width = 0.78,
    height = 0.70,
    wrap = true,
  })
  return analysis, err
end

function M.inspect_fragment(fragment)
  if not fragment then
    return nil, "No fragment is selected"
  end

  local key = string.format("fragment-%s", fragment.id or fragment.label or "details")
  local title = string.format("Fragment · %s", packet.fragment_summary(fragment))
  presentation.open_report(key, packet.fragment_detail_lines(fragment), {
    title = title,
    role = "workbench_fragment",
    width = 0.74,
    height = 0.66,
    wrap = true,
  })
  return true, nil
end

function M.inspect()
  local workbench, thread_id = active_workbench()
  return {
    thread_id = thread_id,
    workbench = clone_value(workbench),
    tray = state.tray and state.tray:inspect() or {},
    review = state.review and state.review:inspect() or {},
    viewers = viewer_stack.inspect(),
  }
end

function M._tray_viewer_spec(thread_id, fragments)
  local layout = state.tray:layout_config()
  return {
    key = "workbench-tray",
    title = state.tray:title(thread_id, fragments or {}),
    role = "workbench",
    thread_id = thread_id,
    fragments = clone_value(fragments or {}),
    bufnr = state.tray:bufnr_value(),
    manage_buffer = false,
    relative = layout.relative,
    position = layout.position,
    size = layout.size,
    border = ((state.opts.ui or {}).workbench or {}).tray.border or "rounded",
    wrap = true,
    prevent_insert = true,
    on_show = function(entry)
      state.tray:show(entry.spec.thread_id, entry.spec.fragments, entry.popup and entry.popup.winid)
    end,
    on_refresh = function(entry)
      state.tray:update(entry.spec.thread_id, entry.spec.fragments, entry.popup and entry.popup.winid)
    end,
    on_hide = function()
      state.tray:hide()
    end,
  }
end

function M._review_viewer_spec(thread_id, message, fragments)
  return {
    key = "compose-review",
    title = string.format("Compose review · thread %s", thread_id and thread_identity.short_id(thread_id) or "none"),
    role = "compose_review",
    thread_id = thread_id,
    message = message or "",
    fragments = clone_value(fragments or {}),
    surface = {
      open = function(entry)
        state.review:show(entry.spec.thread_id, entry.spec.message, entry.spec.fragments)
      end,
      refresh = function(entry)
        state.review:update(entry.spec.thread_id, entry.spec.message, entry.spec.fragments)
      end,
      hide = function()
        state.review:hide()
      end,
      focus = function()
        state.review:focus_message()
      end,
      is_visible = function()
        return state.review:is_visible()
      end,
      inspect = function()
        return state.review:inspect()
      end,
    },
  }
end

return M
