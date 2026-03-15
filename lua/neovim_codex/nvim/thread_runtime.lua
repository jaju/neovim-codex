local M = {}

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
