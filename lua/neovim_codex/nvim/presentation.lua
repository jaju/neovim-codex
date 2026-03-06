local selectors = require("neovim_codex.core.selectors")

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
    vim.bo[state.events_buf].bufhidden = "wipe"
    vim.bo[state.events_buf].filetype = "json"
    vim.api.nvim_buf_set_name(state.events_buf, "neovim-codex://events")
  end

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, state.events_buf)
  refresh_events(store)

  if state.unsubscribe then
    state.unsubscribe()
    state.unsubscribe = nil
  end

  state.unsubscribe = store:subscribe(function()
    vim.schedule(function()
      refresh_events(store)
    end)
  end)
end

function M.open_report(name, lines, opts)
  opts = opts or {}
  local buf = ensure_report_buffer(name, opts.filetype)
  vim.cmd(opts.command or "botright split")
  vim.api.nvim_win_set_buf(0, buf)
  set_buffer_lines(buf, lines)
  return buf
end

function M.status_line(connection, threads)
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

  if connection.last_error then
    pieces[#pieces + 1] = string.format("error=%s", connection.last_error)
  end

  return table.concat(pieces, " ")
end

return M
