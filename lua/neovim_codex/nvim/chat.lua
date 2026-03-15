local presentation = require("neovim_codex.nvim.presentation")

local M = {}

local state = {
  store = nil,
  actions = nil,
  opts = nil,
  unsubscribe = nil,
  composer = nil,
  surface = nil,
  document = nil,
  render = nil,
  projector = nil,
  last_document = nil,
  last_render = nil,
  mode = nil,
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.ERROR)
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

local function open_help()
  require("neovim_codex").open_shortcuts()
end

local function preferred_mode()
  return require("neovim_codex.nvim.chat.layout").normalize_mode(state.mode, state.opts)
end

local function ensure_modules()
  if state.projector and state.render then
    return true
  end

  local ok_projector, projector = pcall(require, "neovim_codex.nvim.chat.document")
  if not ok_projector then
    notify(projector)
    return false
  end

  local ok_render, render = pcall(require, "neovim_codex.nvim.chat.render")
  if not ok_render then
    notify(render)
    return false
  end

  state.projector = projector
  state.render = render
  return true
end

local function ensure_surface()
  if state.surface and state.composer and state.details then
    return true
  end

  local ok_composer, composer_mod = pcall(require, "neovim_codex.nvim.chat.composer")
  if not ok_composer then
    notify(string.format("Failed to load composer UI: %s", composer_mod))
    return false
  end

  local ok_surface, surface_mod = pcall(require, "neovim_codex.nvim.chat.surface")
  if not ok_surface then
    notify(string.format("Failed to load chat overlay. Install nui.nvim and reload: %s", surface_mod))
    return false
  end

  local ok_details, details_mod = pcall(require, "neovim_codex.nvim.chat.details")
  if not ok_details then
    notify(string.format("Failed to load chat details overlay. Install nui.nvim and reload: %s", details_mod))
    return false
  end

  state.composer = composer_mod.new(state.opts, {
    send = function()
      M.submit()
    end,
    hide = function()
      M.close()
    end,
    focus_transcript = function()
      if state.surface then
        state.surface:focus_transcript()
      end
    end,
    open_request = function()
      require("neovim_codex").open_request()
    end,
    open_thread_settings = function()
      require("neovim_codex").configure_thread()
    end,
    toggle_reader = function()
      M.toggle_reader()
    end,
    open_help = open_help,
    on_height_changed = function(height)
      if state.surface then
        state.surface:set_composer_height(height)
      end
    end,
  })

  state.details = details_mod.new(state.opts)

  state.surface = surface_mod.new(state.opts, {
    composer = state.composer,
    close_overlay = function()
      M.close()
    end,
    focus_composer = function()
      state.composer:focus()
    end,
    inspect_current_block = function()
      M.inspect_current_block()
    end,
    open_request = function()
      require("neovim_codex").open_request()
    end,
    open_thread_settings = function()
      require("neovim_codex").configure_thread()
    end,
    toggle_reader = function()
      M.toggle_reader()
    end,
    open_help = open_help,
  })

  return true
end

local function render()
  if not state.store or not ensure_modules() or not ensure_surface() then
    return false
  end

  local snapshot = state.store:get_state()
  local document = state.projector.project_active(snapshot)
  local render_result = state.render.render(document)
  state.last_document = document
  state.last_render = render_result
  state.surface:update(render_result)
  return true
end

local function attach(store)
  if state.unsubscribe then
    state.unsubscribe()
    state.unsubscribe = nil
  end

  state.store = store
  state.unsubscribe = store:subscribe(function()
    if not (state.surface and state.surface:is_visible()) then
      return
    end
    vim.schedule(render)
  end)
end

local function show_overlay(mode)
  if not ensure_surface() then
    return false
  end
  local reuse_render = state.surface and state.surface:is_visible() and state.last_render ~= nil
  state.mode = require("neovim_codex.nvim.chat.layout").normalize_mode(mode or state.mode, state.opts)
  state.surface:set_mode(state.mode)
  state.surface:show()
  if reuse_render and state.last_render then
    state.surface:update(state.last_render)
  else
    render()
  end
  state.composer:focus()
  return true
end

function M.open(store, opts, actions)
  state.opts = opts
  state.actions = actions or {}
  state.mode = preferred_mode()
  attach(store)
  return show_overlay(state.mode)
end

function M.open_with_mode(store, opts, actions, mode)
  state.opts = opts
  state.actions = actions or {}
  state.mode = require("neovim_codex.nvim.chat.layout").normalize_mode(mode, opts)
  attach(store)
  return show_overlay(state.mode)
end

function M.toggle(store, opts, actions)
  state.opts = opts
  state.actions = actions or {}
  attach(store)
  if not ensure_surface() then
    return false
  end

  local target_mode = preferred_mode()
  if state.surface:is_visible() and state.surface:mode() == target_mode then
    M.close()
    return true
  end

  return show_overlay(target_mode)
end

function M.read_draft()
  if not ensure_surface() then
    return ""
  end
  return state.composer:read()
end

function M.set_draft(text)
  if not ensure_surface() then
    return false
  end
  state.composer:set_text(text or "")
  return true
end

function M.clear_draft()
  if not ensure_surface() then
    return false
  end
  state.composer:clear()
  return true
end

function M.current_block()
  if not ensure_surface() then
    return nil
  end
  return state.surface:current_block()
end

function M.submit()
  if not ensure_surface() then
    return nil, "chat overlay is unavailable"
  end

  local text = state.composer:read()
  local submit = state.actions and state.actions.submit_text
  if not submit then
    return nil, "submit_text action is unavailable"
  end

  local result, err = submit(text)
  if not err then
    state.composer:clear()
  end
  return result, err
end

function M.inspect_current_block()
  if not ensure_surface() then
    return nil, "chat overlay is unavailable"
  end

  if not state.surface:is_visible() then
    return nil, "chat overlay is hidden"
  end

  local block = state.surface:current_block()
  if not block then
    return nil, "no transcript block is selected"
  end

  state.details:show(block)
  return block, nil
end

function M.toggle_reader()
  if not ensure_surface() then
    return false
  end
  local next_mode = state.surface:mode() == "reader" and "rail" or "reader"
  state.mode = next_mode
  return show_overlay(next_mode)
end

function M.focus_composer()
  if not ensure_surface() then
    return false
  end
  return state.surface:focus_composer()
end

function M.close()
  presentation.close_viewers({ preserve_sticky = true })
  if state.details then
    state.details:hide()
  end
  if state.surface then
    state.surface:hide()
  end
end

function M.is_visible()
  return state.surface and state.surface:is_visible() or false
end

function M.inspect()
  local surface_state = state.surface and state.surface:inspect() or {}
  surface_state.document = clone_value(state.last_document)
  surface_state.render = clone_value(state.last_render)
  surface_state.mode = state.surface and state.surface:mode() or preferred_mode()
  surface_state.details = state.details and state.details:inspect() or {}
  surface_state.viewers = presentation.inspect_viewers()
  return surface_state
end

return M
