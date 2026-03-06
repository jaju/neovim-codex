local selectors = require("neovim_codex.core.selectors")
local renderer = require("neovim_codex.nvim.thread_renderer")

local M = {}

local state = {
  store = nil,
  actions = nil,
  opts = nil,
  transcript_buf = nil,
  prompt_buf = nil,
  transcript_win = nil,
  prompt_win = nil,
  unsubscribe = nil,
  turn_lines = {},
}

local function valid_buffer(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_window(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function map_if(lhs, mode, rhs, opts)
  if not lhs then
    return
  end
  local map_opts = {
    silent = true,
    nowait = true,
    buffer = opts.buffer,
    desc = opts.desc,
  }
  vim.keymap.set(mode, lhs, rhs, map_opts)
end

local function close_windows()
  if valid_window(state.prompt_win) then
    vim.api.nvim_win_close(state.prompt_win, true)
    state.prompt_win = nil
  end
  if valid_window(state.transcript_win) then
    vim.api.nvim_win_close(state.transcript_win, true)
    state.transcript_win = nil
  end
end

local function focus_prompt()
  if not valid_window(state.prompt_win) then
    return false
  end
  vim.api.nvim_set_current_win(state.prompt_win)
  vim.cmd("startinsert")
  return true
end

local function goto_turn(direction)
  if not valid_window(state.transcript_win) then
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(state.transcript_win)[1]
  local target = nil

  if direction > 0 then
    for _, line in ipairs(state.turn_lines) do
      if line > cursor_line then
        target = line
        break
      end
    end
  else
    for index = #state.turn_lines, 1, -1 do
      local line = state.turn_lines[index]
      if line < cursor_line then
        target = line
        break
      end
    end
  end

  if target then
    vim.api.nvim_set_current_win(state.transcript_win)
    vim.api.nvim_win_set_cursor(state.transcript_win, { target, 0 })
  end
end

local function open_help()
  vim.cmd("help neovim-codex-chat")
end

local function bind_transcript_keymaps(buf)
  local keymaps = state.opts.keymaps.transcript or {}
  map_if(keymaps.close, "n", close_windows, { buffer = buf, desc = "Close Codex chat" })
  map_if(keymaps.focus_prompt, "n", focus_prompt, { buffer = buf, desc = "Focus Codex prompt" })
  map_if(keymaps.next_turn, "n", function()
    goto_turn(1)
  end, { buffer = buf, desc = "Next Codex turn" })
  map_if(keymaps.prev_turn, "n", function()
    goto_turn(-1)
  end, { buffer = buf, desc = "Previous Codex turn" })
  map_if(keymaps.help, "n", open_help, { buffer = buf, desc = "Codex chat help" })
end

local function bind_prompt_keymaps(buf)
  local keymaps = state.opts.keymaps.prompt or {}
  map_if(keymaps.close, "n", close_windows, { buffer = buf, desc = "Close Codex chat" })
  map_if(keymaps.help, "n", open_help, { buffer = buf, desc = "Codex chat help" })
end

local function ensure_transcript_buffer()
  if valid_buffer(state.transcript_buf) then
    return state.transcript_buf
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, "neovim-codex://chat/transcript")
  bind_transcript_keymaps(buf)
  state.transcript_buf = buf
  return buf
end

local function ensure_prompt_buffer()
  if valid_buffer(state.prompt_buf) then
    return state.prompt_buf
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].buftype = "prompt"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, "neovim-codex://chat/prompt")
  vim.fn.prompt_setprompt(buf, state.opts.ui.chat.prompt_prefix)
  vim.fn.prompt_setcallback(buf, function(text)
    if state.actions and state.actions.submit_text then
      state.actions.submit_text(text)
    end
  end)
  bind_prompt_keymaps(buf)
  state.prompt_buf = buf
  return buf
end

local function apply_window_options(win, opts)
  vim.wo[win].wrap = opts.wrap
  vim.wo[win].linebreak = opts.wrap
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
end

local function ensure_layout()
  if valid_window(state.transcript_win) and valid_window(state.prompt_win) then
    return
  end

  local transcript_buf = ensure_transcript_buffer()
  local prompt_buf = ensure_prompt_buffer()
  local chat_opts = state.opts.ui.chat

  vim.cmd(string.format("botright vertical %dsplit", chat_opts.width))
  state.transcript_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.transcript_win, transcript_buf)
  apply_window_options(state.transcript_win, chat_opts)

  vim.cmd(string.format("botright %dsplit", chat_opts.prompt_height))
  state.prompt_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.prompt_win, prompt_buf)
  vim.wo[state.prompt_win].number = false
  vim.wo[state.prompt_win].relativenumber = false
  vim.wo[state.prompt_win].signcolumn = "no"
  vim.wo[state.prompt_win].wrap = false

  if valid_window(state.transcript_win) then
    vim.api.nvim_set_current_win(state.prompt_win)
  end
end

local function set_lines(buf, lines)
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

local function render()
  if not valid_buffer(state.transcript_buf) or not state.store then
    return
  end

  local snapshot = state.store:get_state()
  local thread = selectors.get_active_thread(snapshot)
  local view = thread and renderer.render_thread(thread) or renderer.render_placeholder(snapshot)
  state.turn_lines = view.turn_lines
  set_lines(state.transcript_buf, view.lines)

  if valid_window(state.transcript_win) then
    local current = vim.api.nvim_get_current_win()
    local keep_at_end = current == state.transcript_win
    if keep_at_end then
      vim.api.nvim_win_set_cursor(state.transcript_win, { #view.lines, 0 })
    end
  end
end

local function attach(store)
  if state.unsubscribe then
    state.unsubscribe()
    state.unsubscribe = nil
  end

  state.store = store
  state.unsubscribe = store:subscribe(function()
    vim.schedule(render)
  end)
end

function M.open(store, opts, actions)
  state.opts = opts
  state.actions = actions or {}
  attach(store)
  ensure_layout()
  render()
  focus_prompt()
end

function M.focus_prompt()
  return focus_prompt()
end

function M.close()
  close_windows()
end

function M.inspect()
  return {
    transcript_buf = state.transcript_buf,
    prompt_buf = state.prompt_buf,
    transcript_win = state.transcript_win,
    prompt_win = state.prompt_win,
    turn_lines = vim.deepcopy(state.turn_lines),
  }
end

return M
