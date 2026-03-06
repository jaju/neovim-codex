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
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.ERROR)
end

local function open_help()
  vim.cmd("help neovim-codex-chat")
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
  if state.surface and state.composer then
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

  state.composer = composer_mod.new(state.opts, {
    send = function()
      M.submit()
    end,
    hide = function()
      if state.surface then
        state.surface:hide()
      end
    end,
    open_help = open_help,
    on_height_changed = function(height)
      if state.surface then
        state.surface:set_composer_height(height)
      end
    end,
  })

  state.surface = surface_mod.new(state.opts, {
    composer = state.composer,
    focus_composer = function()
      state.composer:focus()
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
    vim.schedule(render)
  end)
end

local function show_overlay()
  if not ensure_surface() then
    return false
  end
  state.surface:show()
  render()
  state.composer:focus()
  return true
end

function M.open(store, opts, actions)
  state.opts = opts
  state.actions = actions or {}
  attach(store)
  return show_overlay()
end

function M.toggle(store, opts, actions)
  state.opts = opts
  state.actions = actions or {}
  attach(store)
  if not ensure_surface() then
    return false
  end

  if state.surface:is_visible() then
    state.surface:hide()
    return true
  end

  return show_overlay()
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

function M.focus_composer()
  if not ensure_surface() then
    return false
  end
  return state.surface:focus_composer()
end

function M.close()
  if state.surface then
    state.surface:hide()
  end
end

function M.is_visible()
  return state.surface and state.surface:is_visible() or false
end

function M.inspect()
  local surface_state = state.surface and state.surface:inspect() or {}
  surface_state.document = vim.deepcopy(state.last_document)
  surface_state.render = vim.deepcopy(state.last_render)
  return surface_state
end

return M
