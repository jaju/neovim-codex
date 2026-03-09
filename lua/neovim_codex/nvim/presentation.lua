local selectors = require("neovim_codex.core.selectors")
local viewer_stack = require("neovim_codex.nvim.viewer_stack")

local M = {}

local state = {
  events_buf = nil,
  unsubscribe = nil,
  reports = {},
}

local function ensure_report_buffer(name, filetype)
  local buf = state.reports[name]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end

  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = filetype or "markdown"
  vim.api.nvim_buf_set_name(buf, string.format("neovim-codex://%s", name))
  state.reports[name] = buf
  return buf
end

local function render_lines(store_state)
  local active_thread = selectors.get_active_thread(store_state)
  local lines = {
    string.format("status: %s", store_state.connection.status),
    string.format("pid: %s", store_state.connection.pid or "-"),
    string.format("initialized: %s", tostring(store_state.connection.initialized)),
    string.format("user_agent: %s", store_state.connection.user_agent or "-"),
    string.format("active_thread: %s", active_thread and active_thread.id or "-"),
    string.format("thread_count: %d", #store_state.threads.order),
    string.format("last_error: %s", store_state.connection.last_error or "-"),
    string.format("last_stderr: %s", store_state.connection.last_stderr or "-"),
    "",
    "events:",
  }

  for _, entry in ipairs(store_state.logs) do
    lines[#lines + 1] = string.format("[%s] %s %s", entry.at, entry.direction or entry.kind, entry.body)
  end

  return lines
end

local function set_buffer_lines(buf, lines)
  local normalized = {}
  for _, line in ipairs(lines) do
    local parts = vim.split(tostring(line), "\n", { plain = true })
    for _, part in ipairs(parts) do
      normalized[#normalized + 1] = part
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, normalized)
  vim.bo[buf].modifiable = false
end

local function refresh_events(store)
  if not state.events_buf or not vim.api.nvim_buf_is_valid(state.events_buf) then
    return
  end

  set_buffer_lines(state.events_buf, render_lines(store:get_state()))
end

function M.open_events(store)
  if not state.events_buf or not vim.api.nvim_buf_is_valid(state.events_buf) then
    state.events_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.events_buf].bufhidden = "hide"
    vim.bo[state.events_buf].filetype = "markdown"
    vim.api.nvim_buf_set_name(state.events_buf, "neovim-codex://events")
    vim.b[state.events_buf].neovim_codex = true
    vim.b[state.events_buf].neovim_codex_role = "events"
  end

  refresh_events(store)
  viewer_stack.open({
    key = "events",
    title = "Codex Events",
    role = "events",
    filetype = "markdown",
    width = 0.84,
    height = 0.72,
    wrap = false,
    lines = vim.api.nvim_buf_get_lines(state.events_buf, 0, -1, false),
  })

  if state.unsubscribe then
    state.unsubscribe()
    state.unsubscribe = nil
  end

  state.unsubscribe = store:subscribe(function()
    vim.schedule(function()
      refresh_events(store)
      viewer_stack.refresh("events", {
        title = "Codex Events",
        role = "events",
        filetype = "markdown",
        width = 0.84,
        height = 0.72,
        wrap = false,
        lines = vim.api.nvim_buf_get_lines(state.events_buf, 0, -1, false),
      })
    end)
  end)
end

function M.open_report(name, lines, opts)
  opts = opts or {}
  local buf = ensure_report_buffer(name, opts.filetype)
  set_buffer_lines(buf, lines)
  viewer_stack.open({
    key = string.format("report:%s", name),
    title = opts.title or name,
    role = opts.role or "report",
    filetype = opts.filetype or "markdown",
    width = opts.width or 0.78,
    height = opts.height or 0.74,
    wrap = opts.wrap ~= false,
    enter_mode = "normal",
    prevent_insert = true,
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
  })
  return buf
end

function M.status_line(connection, threads, server_requests, workbench)
  local pieces = {
    string.format("status=%s", connection.status),
    string.format("pid=%s", connection.pid or "-"),
  }

  if threads and threads.active_id then
    pieces[#pieces + 1] = string.format("thread=%s", threads.active_id)
  end

  if connection.user_agent then
    pieces[#pieces + 1] = string.format("ua=%s", connection.user_agent)
  end

  if server_requests and server_requests.active_id then
    pieces[#pieces + 1] = string.format("pending=%d", #(server_requests.order or {}))
  end

  local active_id = threads and threads.active_id or nil
  local count = active_id and workbench and workbench.by_thread_id and workbench.by_thread_id[active_id] and #((workbench.by_thread_id[active_id].fragments_order) or {}) or 0
  pieces[#pieces + 1] = string.format("workbench=%d", count)

  if connection.last_error then
    pieces[#pieces + 1] = string.format("error=%s", connection.last_error)
  end

  return table.concat(pieces, " ")
end

function M.close_viewers(opts)
  viewer_stack.close_all(opts)
end

function M.inspect_viewers()
  return viewer_stack.inspect()
end

return M
