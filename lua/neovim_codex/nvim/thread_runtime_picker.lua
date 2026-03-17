local runtime = require("neovim_codex.nvim.thread_runtime")
local ui_prompt = require("neovim_codex.nvim.ui_prompt")

local M = {}
M.__index = M

local select_sync = ui_prompt.select_sync
local input_sync = ui_prompt.input_sync
local select_async = ui_prompt.select_async
local input_async = ui_prompt.input_async

local function same_mode_mask(left, right)
  if left == right then
    return true
  end
  if type(left) ~= "table" or type(right) ~= "table" then
    return false
  end
  return left.name == right.name
    and left.mode == right.mode
    and (left.model or left.model_id or left.modelId) == (right.model or right.model_id or right.modelId)
    and left.reasoning_effort == right.reasoning_effort
end

local function build_mode_choices(modes)
  local choices = { { label = "No collaboration mode override", value = nil } }
  for _, mask in ipairs(modes or {}) do
    choices[#choices + 1] = {
      label = runtime.mode_choice_label(mask),
      value = mask,
    }
  end
  return choices
end

local function build_model_choices(models)
  local model_lookup = {}
  local choices = { { label = "Default model", value = nil } }
  for _, model in ipairs(models or {}) do
    model_lookup[model.model] = model
    if model.hidden ~= true then
      choices[#choices + 1] = {
        label = runtime.model_choice_label(model),
        value = model.model,
        model_info = model,
      }
    end
  end
  return choices, model_lookup
end

function M.new(opts)
  return setmetatable({
    client = opts.client,
    request_with_wait = opts.request_with_wait,
    notify = opts.notify,
    experimental_api = opts.experimental_api ~= false,
  }, M)
end

function M:query_model_catalog(opts)
  local result, err = self.request_with_wait(function(done)
    self.client:model_list({ includeHidden = opts and opts.include_hidden or false }, done)
  end, { wait = true, timeout_ms = opts and opts.timeout_ms or 4000 })
  if err then
    return nil, err
  end
  return result and result.data or {}, nil
end

function M:query_collaboration_modes(opts)
  if self.experimental_api == false then
    return {}, nil
  end

  local result, err = self.request_with_wait(function(done)
    self.client:collaboration_mode_list({}, done)
  end, { wait = true, timeout_ms = opts and opts.timeout_ms or 4000 })
  if err then
    return {}, err
  end
  return result and result.data or {}, nil
end

function M:query_loaded_threads(opts)
  local result, err = self.request_with_wait(function(done)
    self.client:thread_loaded_list({}, done)
  end, { wait = true, timeout_ms = opts and opts.timeout_ms or 4000 })
  if err then
    return {}, err
  end

  local loaded = {}
  for _, thread_id in ipairs(result and result.data or {}) do
    loaded[thread_id] = true
  end
  return loaded, nil
end

function M:query_runtime_catalogs_async(opts, on_done)
  opts = opts or {}
  local finished = false
  local timeout_ms = opts.timeout_ms or 4000
  local models = nil
  local modes = self.experimental_api == false and {} or nil
  local mode_err = nil

  local function finish(models_value, modes_value, err_value, mode_warning)
    if finished then
      return
    end
    finished = true
    vim.schedule(function()
      on_done(models_value, modes_value, err_value, mode_warning)
    end)
  end

  vim.defer_fn(function()
    finish(nil, nil, "timed out waiting for thread runtime options", nil)
  end, timeout_ms)

  local function maybe_finish()
    if models ~= nil and modes ~= nil then
      finish(models, modes, nil, mode_err)
    end
  end

  self.client:model_list({ includeHidden = opts.include_hidden or false }, function(err, result)
    if err then
      finish(nil, nil, err, nil)
      return
    end
    models = result and result.data or {}
    maybe_finish()
  end)

  if self.experimental_api == false then
    maybe_finish()
    return
  end

  self.client:collaboration_mode_list({}, function(err, result)
    mode_err = err
    modes = result and result.data or {}
    maybe_finish()
  end)
end

local function select_effort_for_model(model, seed_effort)
  local choices = runtime.supported_effort_choices(model)
  local selection = select_sync(choices, {
    prompt = "Codex reasoning effort",
    format_item = function(item)
      if seed_effort == item.value then
        return item.label .. "  (current)"
      end
      return item.label
    end,
  })
  if not selection then
    return nil, "cancelled"
  end
  return selection.value, nil
end

local function select_effort_for_model_async(model, seed_effort, on_done)
  local choices = runtime.supported_effort_choices(model)
  if #choices <= 1 then
    on_done(choices[1] and choices[1].value or nil, nil)
    return
  end

  select_async(choices, {
    prompt = "Codex reasoning effort",
    format_item = function(item)
      if seed_effort == item.value then
        return item.label .. "  (current)"
      end
      return item.label
    end,
  }, function(selection)
    if not selection then
      on_done(nil, "cancelled")
      return
    end
    on_done(selection.value, nil)
  end)
end

function M:pick_async(opts, on_done)
  opts = opts or {}
  local settings = runtime.normalize(vim.deepcopy(opts.seed or {}))
  settings.name = settings.name
  settings.ephemeral = settings.ephemeral == true
  settings.modelCatalog = {}
  settings.modeCatalog = {}
  settings.modeError = nil

  local function finish(result, err)
    if err == "cancelled" then
      on_done(nil, err)
      return
    end
    if err then
      self.notify(err, vim.log.levels.ERROR, opts.notify)
      on_done(nil, err)
      return
    end
    on_done(runtime.normalize(result), nil)
  end

  local function current_mode_label()
    local mask = settings.collaborationModeMask
    if type(mask) ~= "table" then
      return "None"
    end
    return mask.name or tostring(mask.mode)
  end

  local function current_model_label()
    return runtime.model_menu_label(runtime.effective_model(settings), settings.modelCatalog)
  end

  local function current_effort_label()
    local effort = runtime.effective_effort(settings)
    return effort == nil and "Default" or tostring(effort)
  end

  local function choose_name(next_step)
    input_async({
      prompt = opts.name_prompt or "Codex thread name (optional): ",
      default = settings.name or "",
    }, function(thread_name)
      if thread_name == nil then
        finish(nil, "cancelled")
        return
      end
      settings.name = vim.trim(thread_name or "")
      next_step()
    end)
  end

  local function choose_ephemeral(next_step)
    select_async({
      { label = "Persistent", value = false },
      { label = "Ephemeral", value = true },
    }, {
      prompt = opts.ephemeral_prompt or "Codex thread lifetime",
      format_item = function(item)
        if item.value == settings.ephemeral then
          return item.label .. "  (current)"
        end
        return item.label
      end,
    }, function(ephemeral_choice)
      if not ephemeral_choice then
        finish(nil, "cancelled")
        return
      end
      settings.ephemeral = ephemeral_choice.value == true
      next_step()
    end)
  end

  local function choose_mode(next_step)
    local mode_choices = build_mode_choices(settings.modeCatalog)
    select_async(mode_choices, {
      prompt = "Codex collaboration mode",
      format_item = function(item)
        local current = same_mode_mask(settings.collaborationModeMask, item.value)
        if settings.collaborationModeMask == nil and item.value == nil then
          current = true
        end
        if current then
          return item.label .. "  (current)"
        end
        return item.label
      end,
    }, function(mode_selection)
      if not mode_selection then
        finish(nil, "cancelled")
        return
      end
      settings.collaborationModeMask = mode_selection.value and vim.deepcopy(mode_selection.value) or nil
      settings = runtime.normalize(settings)
      next_step()
    end)
  end

  local function choose_model(next_step)
    local model_choices, model_lookup = build_model_choices(settings.modelCatalog)
    local selected_model = runtime.effective_model(settings)
    select_async(model_choices, {
      prompt = "Codex model",
      format_item = function(item)
        if item.value == selected_model then
          return item.label .. "  (current)"
        end
        return item.label
      end,
    }, function(model_selection)
      if not model_selection then
        finish(nil, "cancelled")
        return
      end
      settings.model = model_selection.value
      settings = runtime.normalize(settings)
      next_step(model_selection.model_info or model_lookup[settings.model])
    end)
  end

  local function choose_effort(next_step)
    local current_model = runtime.effective_model(settings)
    local model_info = runtime.find_model(settings.modelCatalog, current_model)
    local selected_effort = runtime.effective_effort(settings)
    select_effort_for_model_async(model_info, selected_effort, function(effort, effort_err)
      if effort_err then
        finish(nil, effort_err)
        return
      end
      settings.effort = effort
      settings = runtime.normalize(settings)
      next_step()
    end)
  end

  local function show_menu()
    local items = {}
    if opts.include_name ~= false then
      items[#items + 1] = { key = "name", label = string.format("Name: %s", settings.name ~= nil and settings.name ~= "" and settings.name or "(unnamed)") }
    end
    if opts.include_ephemeral ~= false then
      items[#items + 1] = { key = "ephemeral", label = string.format("Lifetime: %s", settings.ephemeral and "Ephemeral" or "Persistent") }
    end
    items[#items + 1] = { key = "mode", label = string.format("Collaboration mode: %s", current_mode_label()) }
    items[#items + 1] = { key = "model", label = string.format("Model: %s", current_model_label()) }
    items[#items + 1] = { key = "effort", label = string.format("Effort: %s", current_effort_label()) }
    items[#items + 1] = { key = "done", label = "Save settings" }
    items[#items + 1] = { key = "cancel", label = "Cancel" }

    select_async(items, {
      prompt = "Codex thread settings",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if not choice or choice.key == "cancel" then
        finish(nil, "cancelled")
        return
      end
      if choice.key == "done" then
        finish(settings, nil)
        return
      end
      if choice.key == "name" then
        choose_name(show_menu)
        return
      end
      if choice.key == "ephemeral" then
        choose_ephemeral(show_menu)
        return
      end
      if choice.key == "mode" then
        choose_mode(show_menu)
        return
      end
      if choice.key == "model" then
        choose_model(show_menu)
        return
      end
      if choice.key == "effort" then
        choose_effort(show_menu)
        return
      end
      show_menu()
    end)
  end

  self:query_runtime_catalogs_async(opts, function(models, modes, catalogs_err, mode_err)
    if catalogs_err then
      finish(nil, catalogs_err)
      return
    end
    settings.modelCatalog = models or {}
    settings.modeCatalog = type(modes) == "table" and modes or {}
    settings.modeError = mode_err
    show_menu()
  end)
end

function M:pick(opts)
  opts = opts or {}
  local seed = vim.deepcopy(opts.seed or {})

  local thread_name = opts.include_name ~= false and input_sync({
    prompt = opts.name_prompt or "Codex thread name (optional): ",
    default = seed.name or "",
  })
  if opts.include_name ~= false and thread_name == nil then
    return nil, "cancelled"
  end

  local ephemeral = seed.ephemeral == true
  if opts.include_ephemeral ~= false then
    local ephemeral_choice = select_sync({
      { label = "Persistent", value = false },
      { label = "Ephemeral", value = true },
    }, {
      prompt = opts.ephemeral_prompt or "Codex thread lifetime",
      format_item = function(item)
        if item.value == ephemeral then
          return item.label .. "  (current)"
        end
        return item.label
      end,
    })
    if not ephemeral_choice then
      return nil, "cancelled"
    end
    ephemeral = ephemeral_choice.value == true
  end

  self.notify("Loading Codex runtime options...", vim.log.levels.INFO, opts.notify)
  local models, model_err = self:query_model_catalog(opts)
  if model_err then
    return nil, model_err
  end
  local modes, mode_err = self:query_collaboration_modes(opts)
  if mode_err and self.experimental_api == false then
    mode_err = nil
  end

  local selected_mode_mask = seed.collaborationModeMask
  local mode_choices = build_mode_choices(type(modes) == "table" and modes or {})
  if #mode_choices > 1 then
    local mode_selection = select_sync(mode_choices, {
      prompt = "Codex collaboration mode",
      format_item = function(item)
        local current = same_mode_mask(selected_mode_mask, item.value)
        if selected_mode_mask == nil and item.value == nil then
          current = true
        end
        if current then
          return item.label .. "  (current)"
        end
        return item.label
      end,
    })
    if not mode_selection then
      return nil, "cancelled"
    end
    selected_mode_mask = mode_selection.value
  end

  local model_choices, model_lookup = build_model_choices(models)
  local selected_model = seed.model or (selected_mode_mask and (selected_mode_mask.model or selected_mode_mask.model_id or selected_mode_mask.modelId))
  local selected_effort = seed.effort
  if selected_effort == nil and selected_mode_mask then
    selected_effort = selected_mode_mask.reasoning_effort
  end

  local model_selection = select_sync(model_choices, {
    prompt = "Codex model",
    format_item = function(item)
      if item.value == selected_model then
        return item.label .. "  (current)"
      end
      return item.label
    end,
  })
  if not model_selection then
    return nil, "cancelled"
  end
  selected_model = model_selection.value
  local selected_model_info = model_selection.model_info or model_lookup[selected_model]
  local effort_err
  selected_effort, effort_err = select_effort_for_model(selected_model_info, selected_effort)
  if effort_err then
    return nil, effort_err
  end

  return {
    name = opts.include_name ~= false and vim.trim(thread_name or "") or seed.name,
    ephemeral = ephemeral,
    model = selected_model,
    effort = selected_effort,
    collaborationModeMask = selected_mode_mask,
    modelCatalog = models,
    modeCatalog = type(modes) == "table" and modes or {},
    modeError = mode_err,
  }, nil
end

return M
