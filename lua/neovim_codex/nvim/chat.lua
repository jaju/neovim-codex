local coalesced_schedule = require("neovim_codex.nvim.coalesced_schedule")
local presentation = require("neovim_codex.nvim.presentation")
local value = require("neovim_codex.core.value")

local M = {}

local state = {
  store = nil,
  actions = nil,
  opts = nil,
  unsubscribe = nil,
  composer = nil,
  overlay_surface = nil,
  rail_surface = nil,
  details = nil,
  render = nil,
  projector = nil,
  last_document = nil,
  last_render = nil,
  mode = nil,
  visible_mode = nil,
  render_job = nil,
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.ERROR)
end

local function open_help()
  require("neovim_codex").open_shortcuts()
end

local function normalize_mode(mode)
  return require("neovim_codex.nvim.chat.layout").normalize_mode(mode, state.opts)
end

local function preferred_mode()
  return normalize_mode(state.mode)
end

local function visible_surface()
  if state.rail_surface and state.rail_surface:is_visible() then
    return state.rail_surface
  end
  if state.overlay_surface and state.overlay_surface:is_visible() then
    return state.overlay_surface
  end
  return nil
end

local function surface_for_mode(mode)
  local resolved = normalize_mode(mode)
  if resolved == "rail" then
    return state.rail_surface
  end
  return state.overlay_surface
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

local function focus_transcript()
  local surface = visible_surface()
  if surface then
    surface:focus_transcript()
  end
end

local function set_composer_height(height)
  if state.rail_surface then
    state.rail_surface:set_composer_height(height)
  end
  if state.overlay_surface then
    state.overlay_surface:set_composer_height(height)
  end
end

local function ensure_surfaces()
  if state.overlay_surface and state.rail_surface and state.composer and state.details then
    return true
  end

  local ok_composer, composer_mod = pcall(require, "neovim_codex.nvim.chat.composer")
  if not ok_composer then
    notify(string.format("Failed to load composer UI: %s", composer_mod))
    return false
  end

  local ok_overlay, overlay_mod = pcall(require, "neovim_codex.nvim.chat.surface")
  if not ok_overlay then
    notify(string.format("Failed to load chat overlay. Install nui.nvim and reload: %s", overlay_mod))
    return false
  end

  local ok_rail, rail_mod = pcall(require, "neovim_codex.nvim.chat.rail_split")
  if not ok_rail then
    notify(string.format("Failed to load rail chat surface: %s", rail_mod))
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
    steer = function()
      require("neovim_codex").steer()
    end,
    hide = function()
      M.close()
    end,
    focus_transcript = focus_transcript,
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
    on_height_changed = set_composer_height,
  })

  state.details = details_mod.new(state.opts)

  local common_handlers = {
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
  }

  state.overlay_surface = overlay_mod.new(state.opts, common_handlers)
  state.rail_surface = rail_mod.new(state.opts, common_handlers)
  return true
end

local function render()
  if not state.store or not ensure_modules() or not ensure_surfaces() then
    return false
  end

  local snapshot = state.store:get_state()
  local document = state.projector.project_active(snapshot)
  local render_result = state.render.render(document)
  state.last_document = document
  state.last_render = render_result

  local current_surface = visible_surface()
  if current_surface then
    current_surface:update(render_result)
  end
  return true
end

local function attach(store)
  if state.unsubscribe then
    state.unsubscribe()
    state.unsubscribe = nil
  end
  if state.render_job then
    state.render_job:dispose()
    state.render_job = nil
  end

  state.store = store
  state.render_job = coalesced_schedule.new(render)
  state.unsubscribe = store:subscribe(function()
    if not state.visible_mode then
      return
    end
    state.render_job:trigger()
  end)
end

local function show_surface(mode)
  if not ensure_surfaces() then
    return false
  end

  local target_mode = normalize_mode(mode or state.mode)
  local next_surface = surface_for_mode(target_mode)
  local current_surface = visible_surface()
  local reuse_render = current_surface == next_surface and state.last_render ~= nil

  if current_surface and current_surface ~= next_surface then
    current_surface:hide()
  end

  state.mode = target_mode
  state.visible_mode = target_mode
  next_surface:set_mode(target_mode)
  next_surface:show()

  if reuse_render and state.last_render then
    next_surface:update(state.last_render)
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
  return show_surface(state.mode)
end

function M.open_with_mode(store, opts, actions, mode)
  state.opts = opts
  state.actions = actions or {}
  state.mode = normalize_mode(mode)
  attach(store)
  return show_surface(state.mode)
end

function M.toggle(store, opts, actions)
  state.opts = opts
  state.actions = actions or {}
  attach(store)
  if not ensure_surfaces() then
    return false
  end

  local target_mode = preferred_mode()
  local current_surface = visible_surface()
  if current_surface and current_surface:mode() == target_mode then
    M.close()
    return true
  end

  return show_surface(target_mode)
end

function M.read_draft()
  if not ensure_surfaces() then
    return ""
  end
  return state.composer:read()
end

function M.set_draft(text)
  if not ensure_surfaces() then
    return false
  end
  state.composer:set_text(text or "")
  return true
end

function M.clear_draft()
  if not ensure_surfaces() then
    return false
  end
  state.composer:clear()
  return true
end

function M.current_block()
  if not ensure_surfaces() then
    return nil
  end
  local surface = visible_surface() or surface_for_mode(preferred_mode())
  return surface and surface:current_block() or nil
end

function M.submit()
  if not ensure_surfaces() then
    return nil, "chat shell is unavailable"
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
  if not ensure_surfaces() then
    return nil, "chat shell is unavailable"
  end

  local surface = visible_surface()
  if not surface then
    return nil, "chat shell is hidden"
  end

  local block = surface:current_block()
  if not block then
    return nil, "no transcript block is selected"
  end

  state.details:show(block)
  return block, nil
end

function M.toggle_reader()
  if not ensure_surfaces() then
    return false
  end
  local current_surface = visible_surface()
  local current_mode = current_surface and current_surface:mode() or preferred_mode()
  local next_mode = current_mode == "reader" and "rail" or "reader"
  state.mode = next_mode
  return show_surface(next_mode)
end

function M.focus_composer()
  if not ensure_surfaces() then
    return false
  end
  local surface = visible_surface() or surface_for_mode(preferred_mode())
  return surface and surface:focus_composer() or false
end

function M.close()
  presentation.close_viewers({ preserve_sticky = true })
  if state.details then
    state.details:hide()
  end
  if state.overlay_surface then
    state.overlay_surface:hide()
  end
  if state.rail_surface then
    state.rail_surface:hide()
  end
  state.visible_mode = nil
end

function M.is_visible()
  return visible_surface() ~= nil
end

function M.inspect()
  local surface = visible_surface() or surface_for_mode(preferred_mode())
  local surface_state = surface and surface:inspect() or {}
  surface_state.document = value.deep_copy(state.last_document)
  surface_state.render = value.deep_copy(state.last_render)
  surface_state.mode = surface and surface:mode() or preferred_mode()
  surface_state.details = state.details and state.details:inspect() or {}
  surface_state.viewers = presentation.inspect_viewers()
  return surface_state
end

return M
