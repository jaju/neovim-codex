local selectors = require("neovim_codex.core.selectors")
local coalesced_schedule = require("neovim_codex.nvim.coalesced_schedule")
local thread_identity = require("neovim_codex.nvim.thread_identity")

local M = {}

local BLINK_FRAMES = { "●", "○" }

local state = {
  config = nil,
  store = nil,
  unsubscribe = nil,
  refresh_job = nil,
  blink_timer = nil,
  blink_index = 1,
}

local HIGHLIGHTS = {
  NeovimCodexStatusRunning = { default = true, link = "DiffAdded" },
  NeovimCodexStatusWaiting = { default = true, link = "WarningMsg" },
  NeovimCodexStatusIdle = { default = true, link = "Comment" },
  NeovimCodexStatusError = { default = true, link = "DiagnosticError" },
  NeovimCodexStatusThread = { default = true, link = "Directory" },
  NeovimCodexStatusHint = { default = true, link = "Special" },
  NeovimCodexStatusMuted = { default = true, link = "Comment" },
}

local function define_highlights()
  for group, spec in pairs(HIGHLIGHTS) do
    pcall(vim.api.nvim_set_hl, 0, group, spec)
  end
end

local function redraw_statusline()
  pcall(vim.cmd, "redrawstatus")
end

local function request_hint(config)
  local keymaps = ((config or {}).keymaps or {}).global or {}
  local lhs = keymaps.request
  if lhs and lhs ~= false then
    return lhs
  end
  return ":CodexRequest"
end

local function running_turn(store_state)
  local turn, thread = selectors.find_running_turn(store_state)
  return turn, thread
end

local function state_label(store_state)
  local connection = (store_state or {}).connection or {}
  local turn, thread = running_turn(store_state)
  if turn then
    return {
      group = "NeovimCodexStatusRunning",
      icon = BLINK_FRAMES[state.blink_index] or BLINK_FRAMES[1],
      label = "RUN",
      thread = thread,
    }
  end

  if selectors.pending_request_count(store_state) > 0 then
    return {
      group = "NeovimCodexStatusWaiting",
      icon = "!",
      label = "WAIT",
      thread = selectors.get_active_thread(store_state),
    }
  end

  if connection.status == "error" then
    return {
      group = "NeovimCodexStatusError",
      icon = "!",
      label = "ERR",
      thread = selectors.get_active_thread(store_state),
    }
  end

  if connection.status == "initializing" then
    return {
      group = "NeovimCodexStatusRunning",
      icon = "…",
      label = "INIT",
      thread = selectors.get_active_thread(store_state),
    }
  end

  if connection.status == "stopping" then
    return {
      group = "NeovimCodexStatusMuted",
      icon = "·",
      label = "STOP",
      thread = selectors.get_active_thread(store_state),
    }
  end

  if connection.status == "ready" then
    return {
      group = "NeovimCodexStatusIdle",
      icon = "○",
      label = "IDLE",
      thread = selectors.get_active_thread(store_state),
    }
  end

  return {
    group = "NeovimCodexStatusMuted",
    icon = "○",
    label = "OFF",
    thread = selectors.get_active_thread(store_state),
  }
end

local function thread_label(thread)
  if type(thread) ~= "table" then
    return nil
  end
  return string.format(
    "%s %s",
    thread_identity.short_id(thread.id),
    thread_identity.title(thread, { max_length = 28, fallback = "thread" })
  )
end

local function workbench_label(store_state, thread_id)
  local counts = selectors.workbench_fragment_counts(store_state, thread_id)
  if not counts or counts.total <= 0 then
    return nil
  end
  if counts.parked > 0 then
    return string.format("WB %d/%d", counts.active, counts.total)
  end
  return string.format("WB %d", counts.total)
end

local function push_plain(parts, value)
  if value and value ~= "" then
    parts[#parts + 1] = value
  end
end

local function push_statusline(parts, group, value)
  if not value or value == "" then
    return
  end
  parts[#parts + 1] = string.format("%%#%s# %s %%*", group, value)
end

local function render_parts(store_state, config)
  local current = state_label(store_state)
  local thread = current.thread or selectors.get_active_thread(store_state)
  local pending = selectors.pending_request_count(store_state)
  local parts = {
    state = string.format("%s %s", current.icon, current.label),
    state_group = current.group,
    thread = thread_label(thread),
    request = pending > 0 and string.format("REQ %d %s", pending, request_hint(config)) or nil,
    request_group = pending > 0 and "NeovimCodexStatusWaiting" or nil,
    workbench = workbench_label(store_state, thread and thread.id or nil),
    workbench_group = "NeovimCodexStatusMuted",
  }
  return parts
end

local function stop_blink_timer()
  if state.blink_timer then
    state.blink_timer:stop()
    state.blink_timer:close()
    state.blink_timer = nil
  end
  state.blink_index = 1
end

local function ensure_blink_timer()
  if state.blink_timer then
    return
  end
  local timer = vim.uv.new_timer()
  timer:start(0, 450, vim.schedule_wrap(function()
    if not state.store then
      stop_blink_timer()
      return
    end
    if not running_turn(state.store:get_state()) then
      stop_blink_timer()
      redraw_statusline()
      return
    end
    state.blink_index = (state.blink_index % #BLINK_FRAMES) + 1
    redraw_statusline()
  end))
  state.blink_timer = timer
end

local function sync_animation(store_state)
  if running_turn(store_state) then
    ensure_blink_timer()
    return
  end
  stop_blink_timer()
end

function M.configure(config)
  state.config = config
  define_highlights()
  redraw_statusline()
end

function M.attach(store, config)
  state.store = store
  state.config = config or state.config
  define_highlights()

  if state.unsubscribe then
    state.unsubscribe()
    state.unsubscribe = nil
  end
  if state.refresh_job then
    state.refresh_job:dispose()
    state.refresh_job = nil
  end

  state.refresh_job = coalesced_schedule.new(function(store_state)
    sync_animation(store_state)
    redraw_statusline()
  end)
  state.unsubscribe = store:subscribe(function(store_state)
    state.refresh_job:trigger(store_state)
  end)

  local store_state = store:get_state()
  sync_animation(store_state)
  redraw_statusline()
end

function M.render_plain(store_state, config)
  local parts = render_parts(store_state, config or state.config)
  local out = {}
  push_plain(out, string.format("codex=%s", parts.state:gsub("^%S+%s+", "")))
  push_plain(out, parts.thread and string.format("thread=%s", parts.thread))
  push_plain(out, parts.request and string.format("request=%s", parts.request))
  push_plain(out, parts.workbench and string.format("workbench=%s", parts.workbench))
  return table.concat(out, " ")
end

function M.render(store_state, config)
  local parts = render_parts(store_state, config or state.config)
  local out = {}
  push_statusline(out, parts.state_group, parts.state)
  push_statusline(out, "NeovimCodexStatusThread", parts.thread)
  push_statusline(out, parts.request_group, parts.request)
  push_statusline(out, parts.workbench_group, parts.workbench)
  return table.concat(out, "")
end

function M.snapshot()
  if not state.store then
    return nil
  end
  return state.store:get_state()
end

return M
