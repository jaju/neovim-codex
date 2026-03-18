local M = {}

local APPROVAL_POLICY_LABELS = {
  untrusted = "Untrusted",
  ["on-failure"] = "On failure",
  ["on-request"] = "On request",
  never = "Never",
}

function M.compact_text(text, limit)
  if text == nil or text == vim.NIL then
    return nil
  end
  local value = vim.trim(tostring(text):gsub("\n", " "):gsub("%s+", " "))
  if value == "" then
    return nil
  end
  if #value <= limit then
    return value
  end
  return value:sub(1, math.max(1, limit - 3)) .. "..."
end

function M.clone_settings(thread)
  local runtime_settings = type(thread) == "table" and type(thread.runtime) == "table" and thread.runtime or {}
  return vim.deepcopy(runtime_settings)
end

function M.build_collaboration_mode(mask, opts)
  if type(mask) ~= "table" then
    return nil
  end
  opts = opts or {}
  local mode = mask.mode
  local model = opts.model or mask.model or mask.model_id or mask.modelId
  if not mode or not model or model == vim.NIL then
    return nil
  end

  return {
    mode = mode,
    settings = {
      model = model,
      reasoning_effort = opts.effort ~= nil and opts.effort or mask.reasoning_effort,
      developer_instructions = vim.NIL,
    },
  }
end

function M.effective_model(settings)
  if type(settings) ~= "table" then
    return nil
  end
  if settings.model ~= nil then
    return settings.model
  end
  local mask = settings.collaborationModeMask
  if type(mask) ~= "table" then
    return nil
  end
  return mask.model or mask.model_id or mask.modelId
end

function M.effective_effort(settings)
  if type(settings) ~= "table" then
    return nil
  end
  if settings.effort ~= nil then
    return settings.effort
  end
  local mask = settings.collaborationModeMask
  if type(mask) ~= "table" then
    return nil
  end
  return mask.reasoning_effort
end

function M.normalize(settings)
  local normalized = type(settings) == "table" and vim.deepcopy(settings) or {}
  local mask = normalized.collaborationModeMask
  if type(mask) == "table" then
    mask = vim.deepcopy(mask)
    local model = M.effective_model(normalized)
    local effort = M.effective_effort(normalized)
    if model ~= nil then
      mask.model = model
    end
    mask.reasoning_effort = effort
    normalized.collaborationModeMask = mask
  end
  normalized.model = M.effective_model(normalized)
  normalized.effort = M.effective_effort(normalized)
  return normalized
end

function M.approval_policy_choice_label(policy)
  if policy == nil then
    return "Default"
  end
  if type(policy) == "table" then
    return "Granular"
  end
  return APPROVAL_POLICY_LABELS[policy] or tostring(policy)
end

function M.approval_policy_menu_label(policy, default_policy)
  if policy == nil then
    if default_policy ~= nil then
      return string.format("Default (%s)", M.approval_policy_choice_label(default_policy))
    end
    return "Default"
  end
  return M.approval_policy_choice_label(policy)
end

function M.approval_policy_choices()
  return {
    { label = "Default", value = nil },
    { label = "Untrusted", value = "untrusted" },
    { label = "On request", value = "on-request" },
    { label = "On failure", value = "on-failure" },
    { label = "Never", value = "never" },
  }
end

function M.find_model(model_catalog, model_name)
  if not model_name then
    return nil
  end
  for _, model in ipairs(model_catalog or {}) do
    if model.model == model_name then
      return model
    end
  end
  return nil
end

local function model_upgrade_hint(model)
  local upgrade_info = type(model) == "table" and model.upgradeInfo or nil
  if type(upgrade_info) == "table" then
    local copy = M.compact_text(upgrade_info.upgradeCopy, 44)
    if copy then
      return copy
    end
    if upgrade_info.model then
      return string.format("upgrade: %s", upgrade_info.model)
    end
  end
  if type(model) == "table" and model.upgrade then
    return string.format("upgrade: %s", model.upgrade)
  end
  return nil
end

local function model_availability_hint(model)
  local availability = type(model) == "table" and model.availabilityNux or nil
  if type(availability) ~= "table" then
    return nil
  end
  return M.compact_text(availability.message, 44)
end

function M.model_choice_label(model)
  if type(model) ~= "table" then
    return "Default model"
  end

  local label = model.displayName or model.model or "Unknown model"
  local description = M.compact_text(model.description, 56)
  if description then
    label = string.format("%s — %s", label, description)
  end

  local hints = {}
  local upgrade = model_upgrade_hint(model)
  if upgrade then
    hints[#hints + 1] = upgrade
  end
  local availability = model_availability_hint(model)
  if availability then
    hints[#hints + 1] = availability
  end
  if model.isDefault then
    hints[#hints + 1] = "default"
  end

  if #hints > 0 then
    label = string.format("%s [%s]", label, table.concat(hints, " · "))
  end

  return M.compact_text(label, 132) or label
end

function M.model_menu_label(model_name, model_catalog)
  if not model_name then
    return "Default"
  end
  local model = M.find_model(model_catalog, model_name)
  if not model then
    return tostring(model_name)
  end
  return M.compact_text(M.model_choice_label(model), 72) or tostring(model_name)
end

function M.mode_choice_label(mask)
  if type(mask) ~= "table" then
    return "No collaboration mode override"
  end
  local reasoning = mask.reasoning_effort == nil and "default" or tostring(mask.reasoning_effort)
  return string.format("%s — mode=%s, model=%s, effort=%s", mask.name, tostring(mask.mode), tostring(mask.model), reasoning)
end

function M.supported_effort_choices(model)
  local choices = { { label = "Default", value = nil } }
  for _, option in ipairs((model and model.supportedReasoningEfforts) or {}) do
    local effort = option.reasoningEffort
    if effort then
      local label = effort
      local description = M.compact_text(option.description, 72)
      if description then
        label = string.format("%s — %s", effort, description)
      end
      choices[#choices + 1] = {
        label = label,
        value = effort,
      }
    end
  end
  return choices
end

return M
