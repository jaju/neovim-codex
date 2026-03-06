local M = {}

local state = {
  events_buf = nil,
  unsubscribe = nil,
}

local function render_lines(store_state)
  local lines = {
    string.format("status: %s", store_state.connection.status),
    string.format("pid: %s", store_state.connection.pid or "-"),
    string.format("initialized: %s", tostring(store_state.connection.initialized)),
    string.format("user_agent: %s", store_state.connection.user_agent or "-"),
    string.format("last_error: %s", store_state.connection.last_error or "-"),
    "",
    "events:",
  }

  for _, entry in ipairs(store_state.logs) do
    lines[#lines + 1] = string.format("[%s] %s %s", entry.at, entry.direction or entry.kind, entry.body)
  end

  return lines
end

local function refresh_buffer(store)
  if not state.events_buf or not vim.api.nvim_buf_is_valid(state.events_buf) then
    return
  end

  local lines = render_lines(store:get_state())
  vim.bo[state.events_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.events_buf, 0, -1, false, lines)
  vim.bo[state.events_buf].modifiable = false
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
  refresh_buffer(store)

  if state.unsubscribe then
    state.unsubscribe()
    state.unsubscribe = nil
  end

  state.unsubscribe = store:subscribe(function()
    vim.schedule(function()
      refresh_buffer(store)
    end)
  end)
end

function M.status_line(connection)
  local pieces = {
    string.format("status=%s", connection.status),
    string.format("pid=%s", connection.pid or "-"),
  }

  if connection.user_agent then
    pieces[#pieces + 1] = string.format("ua=%s", connection.user_agent)
  end

  if connection.last_error then
    pieces[#pieces + 1] = string.format("error=%s", connection.last_error)
  end

  return table.concat(pieces, " ")
end

return M
