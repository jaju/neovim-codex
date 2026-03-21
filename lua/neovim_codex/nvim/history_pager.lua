local details = require("neovim_codex.nvim.chat.details")
local history = require("neovim_codex.nvim.chat.history")
local renderer = require("neovim_codex.nvim.thread_renderer")
local surface_help = require("neovim_codex.nvim.surface_help")
local thread_identity = require("neovim_codex.nvim.thread_identity")
local viewer_stack = require("neovim_codex.nvim.viewer_stack")

local M = {}

local VIEWER_KEY = "history"
local DEFAULTS = {
  width = 0.84,
  height = 0.76,
  border = "rounded",
  wrap = true,
  max_turns_per_chunk = 10,
  max_lines_per_chunk = 1200,
}

local state = {
  config = nil,
  thread = nil,
  chunks = {},
  chunk_index = 1,
  last_render = nil,
}

local function pager_config(config)
  local opts = ((config or {}).ui or {}).history_pager or {}
  return {
    width = opts.width or DEFAULTS.width,
    height = opts.height or DEFAULTS.height,
    border = opts.border or DEFAULTS.border,
    wrap = opts.wrap ~= false,
    max_turns_per_chunk = math.max(1, tonumber(opts.max_turns_per_chunk) or DEFAULTS.max_turns_per_chunk),
    max_lines_per_chunk = math.max(1, tonumber(opts.max_lines_per_chunk) or DEFAULTS.max_lines_per_chunk),
  }
end

local function chunk_label(chunk)
  return string.format("turns %d-%d", chunk.start_index, chunk.end_index)
end

local current_block
local chunk_view

local function current_turn_index()
  local block = current_block()
  if not block or not block.turn_id then
    return nil
  end

  return history.turn_index(history.list_turns(state.thread), block.turn_id)
end

local function open_details(block)
  local rendered = details.render_block(block)
  viewer_stack.open({
    key = "details",
    title = rendered.title or "Details",
    role = "details",
    filetype = "markdown",
    width = 0.72,
    height = 0.68,
    wrap = true,
    lines = rendered.lines,
  })
end

local function open_turn_focus(turn_index)
  if not turn_index then
    return
  end

  local view = chunk_view(state.thread, state.config, {
    start_index = turn_index,
    end_index = turn_index,
  }, turn_index, turn_index)
  local thread = state.thread or {}

  viewer_stack.open({
    key = "history-turn",
    title = string.format("Codex Turn · %s · turn %d", thread_identity.short_id(thread.id or ""), turn_index),
    role = "history_pager",
    filetype = "markdown",
    width = pager_config(state.config).width,
    height = pager_config(state.config).height,
    border = pager_config(state.config).border,
    wrap = pager_config(state.config).wrap,
    enter_mode = "normal",
    prevent_insert = true,
    lines = view.lines,
  })
end

local function viewer_winid()
  local top = viewer_stack.inspect().top
  if top and top.key == VIEWER_KEY and top.visible == true then
    return top.winid
  end
  return nil
end

local function contains_line(block, line)
  return block.line_start and block.line_end and line >= block.line_start and line <= block.line_end
end

current_block = function()
  local winid = viewer_winid()
  if not winid or not state.last_render then
    return nil
  end

  local cursor_line = vim.api.nvim_win_get_cursor(winid)[1]
  local previous = nil
  for _, block in ipairs(state.last_render.blocks or {}) do
    if contains_line(block, cursor_line) then
      return vim.deepcopy(block)
    end
    if block.line_end and block.line_end < cursor_line then
      previous = block
    end
  end

  return previous and vim.deepcopy(previous) or nil
end

local function goto_turn(direction)
  local winid = viewer_winid()
  if not winid or not state.last_render then
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(winid)[1]
  local turn_lines = state.last_render.turn_lines or {}
  local target = nil

  if direction > 0 then
    for _, line in ipairs(turn_lines) do
      if line > cursor_line then
        target = line
        break
      end
    end
  else
    for index = #turn_lines, 1, -1 do
      local line = turn_lines[index]
      if line < cursor_line then
        target = line
        break
      end
    end
  end

  if target then
    vim.api.nvim_set_current_win(winid)
    vim.api.nvim_win_set_cursor(winid, { target, 0 })
  end
end

chunk_view = function(thread, config, chunk, chunk_index, chunk_count)
  local title = string.format("# Codex History · %d/%d", chunk_index, chunk_count)
  return renderer.render_thread(thread, {
    title = title,
    config = config,
    turn_range = {
      start_index = chunk.start_index,
      end_index = chunk.end_index,
    },
    show_history_notice = false,
  })
end

local function build_chunks(thread, config)
  local turns = history.list_turns(thread)
  local chunks = {}
  local segments = history.compaction_segments(turns)
  local opts = pager_config(config)

  for _, segment in ipairs(segments) do
    local start_index = segment.start_index
    while start_index <= segment.end_index do
      local end_index = math.min(segment.end_index, start_index + opts.max_turns_per_chunk - 1)
      local view = chunk_view(thread, config, {
        start_index = start_index,
        end_index = end_index,
      }, 1, 1)

      while #view.lines > opts.max_lines_per_chunk and end_index > start_index do
        end_index = end_index - 1
        view = chunk_view(thread, config, {
          start_index = start_index,
          end_index = end_index,
        }, 1, 1)
      end

      chunks[#chunks + 1] = {
        start_index = start_index,
        end_index = end_index,
        anchor = start_index == segment.start_index and segment.anchor or "history",
      }
      start_index = end_index + 1
    end
  end

  if #chunks == 0 then
    chunks[1] = { start_index = 1, end_index = 0, anchor = "empty" }
  end

  return chunks
end

local function clamp_chunk_index(index)
  return math.max(1, math.min(#state.chunks, tonumber(index) or 1))
end

local function viewer_title()
  local thread = state.thread or {}
  local short_id = thread.id and thread_identity.short_id(thread.id) or "(no thread)"
  local title = thread_identity.title(thread, { max_length = 32 })
  local chunk = state.chunks[state.chunk_index] or { start_index = 1, end_index = 1 }
  return string.format("Codex History · %s · %s · %d/%d", short_id, title, state.chunk_index, #state.chunks)
    .. string.format(" · %s", chunk_label(chunk))
end

local function render_spec()
  local chunk = state.chunks[state.chunk_index]
  local view = chunk_view(state.thread, state.config, chunk, state.chunk_index, #state.chunks)
  state.last_render = view

  local mappings = {
    { mode = "n", lhs = "]h", rhs = function() M.next_chunk() end, desc = "Next history chunk" },
    { mode = "n", lhs = "[h", rhs = function() M.prev_chunk() end, desc = "Previous history chunk" },
    { mode = "n", lhs = "]]", rhs = function() goto_turn(1) end, desc = "Next history turn" },
    { mode = "n", lhs = "[[", rhs = function() goto_turn(-1) end, desc = "Previous history turn" },
    {
      mode = "n",
      lhs = "<CR>",
      rhs = function()
        local block = current_block()
        if block then
          open_details(block)
        end
      end,
      desc = "Inspect current history block",
    },
    {
      mode = "n",
      lhs = "o",
      rhs = function()
        open_turn_focus(current_turn_index())
      end,
      desc = "Open the current turn in a focused history view",
    },
  }

  for _, lhs in ipairs(surface_help.keys(state.config, "g?")) do
    mappings[#mappings + 1] = {
      mode = "n",
      lhs = lhs,
      rhs = function()
        require("neovim_codex").open_shortcuts({ surface = "history_pager" })
      end,
      desc = "Codex history help",
    }
  end

  return {
    key = VIEWER_KEY,
    title = viewer_title(),
    role = "history_pager",
    filetype = "markdown",
    width = pager_config(state.config).width,
    height = pager_config(state.config).height,
    border = pager_config(state.config).border,
    wrap = pager_config(state.config).wrap,
    enter_mode = "normal",
    prevent_insert = true,
    lines = view.lines,
    mappings = mappings,
  }
end

function M.open(thread, opts)
  opts = opts or {}
  state.thread = thread
  state.config = opts.config or {}
  state.chunks = build_chunks(thread, state.config)
  state.chunk_index = clamp_chunk_index(opts.chunk_index or #state.chunks)
  viewer_stack.open(render_spec())
  return {
    chunk_index = state.chunk_index,
    chunk_count = #state.chunks,
  }
end

function M.next_chunk()
  if state.chunk_index >= #state.chunks then
    return false
  end
  state.chunk_index = state.chunk_index + 1
  viewer_stack.refresh(VIEWER_KEY, render_spec())
  return true
end

function M.prev_chunk()
  if state.chunk_index <= 1 then
    return false
  end
  state.chunk_index = state.chunk_index - 1
  viewer_stack.refresh(VIEWER_KEY, render_spec())
  return true
end

function M.inspect()
  return {
    thread_id = state.thread and state.thread.id or nil,
    chunk_index = state.chunk_index,
    chunk_count = #state.chunks,
    last_render = vim.deepcopy(state.last_render),
  }
end

return M
