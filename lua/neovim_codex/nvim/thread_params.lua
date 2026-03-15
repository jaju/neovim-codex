local runtime = require("neovim_codex.nvim.thread_runtime")

local M = {}

function M.build_thread_start(config, cwd, opts)
  opts = opts or {}
  local params = {
    cwd = opts.cwd or (config.thread.cwd == "current" and cwd or config.thread.cwd),
    persistExtendedHistory = config.thread.persist_extended_history,
    experimentalRawEvents = config.thread.experimental_raw_events,
  }

  if opts.model then
    params.model = opts.model
  end
  if opts.model_provider then
    params.modelProvider = opts.model_provider
  end
  if opts.service_tier then
    params.serviceTier = opts.service_tier
  end
  if opts.service_name then
    params.serviceName = opts.service_name
  end
  if opts.personality then
    params.personality = opts.personality
  end
  if opts.base_instructions then
    params.baseInstructions = opts.base_instructions
  end
  if opts.developer_instructions then
    params.developerInstructions = opts.developer_instructions
  end
  if opts.approval_policy then
    params.approvalPolicy = opts.approval_policy
  end
  if opts.approvals_reviewer then
    params.approvalsReviewer = opts.approvals_reviewer
  end
  if opts.sandbox then
    params.sandbox = opts.sandbox
  end
  if opts.config_overrides then
    params.config = opts.config_overrides
  end
  if opts.ephemeral ~= nil then
    params.ephemeral = opts.ephemeral
  end

  return params
end

function M.build_thread_resume(config, opts)
  opts = opts or {}
  local params = {
    threadId = opts.thread_id,
    persistExtendedHistory = config.thread.persist_extended_history,
  }

  if opts.cwd then
    params.cwd = opts.cwd
  end
  if opts.personality then
    params.personality = opts.personality
  end
  if opts.base_instructions then
    params.baseInstructions = opts.base_instructions
  end
  if opts.developer_instructions then
    params.developerInstructions = opts.developer_instructions
  end
  if opts.model then
    params.model = opts.model
  end
  if opts.model_provider then
    params.modelProvider = opts.model_provider
  end
  if opts.service_tier then
    params.serviceTier = opts.service_tier
  end
  if opts.approval_policy then
    params.approvalPolicy = opts.approval_policy
  end
  if opts.approvals_reviewer then
    params.approvalsReviewer = opts.approvals_reviewer
  end
  if opts.sandbox then
    params.sandbox = opts.sandbox
  end
  if opts.config_overrides then
    params.config = opts.config_overrides
  end

  return params
end

function M.build_thread_fork(config, opts)
  opts = opts or {}
  local params = {
    threadId = opts.thread_id,
    persistExtendedHistory = config.thread.persist_extended_history,
  }

  if opts.turn_id then
    params.turnId = opts.turn_id
  end
  if opts.path then
    params.path = opts.path
  end
  if opts.cwd then
    params.cwd = opts.cwd
  end
  if opts.model then
    params.model = opts.model
  end
  if opts.model_provider then
    params.modelProvider = opts.model_provider
  end
  if opts.service_tier then
    params.serviceTier = opts.service_tier
  end
  if opts.base_instructions then
    params.baseInstructions = opts.base_instructions
  end
  if opts.developer_instructions then
    params.developerInstructions = opts.developer_instructions
  end
  if opts.approval_policy then
    params.approvalPolicy = opts.approval_policy
  end
  if opts.approvals_reviewer then
    params.approvalsReviewer = opts.approvals_reviewer
  end
  if opts.sandbox then
    params.sandbox = opts.sandbox
  end
  if opts.config_overrides then
    params.config = opts.config_overrides
  end
  if opts.ephemeral ~= nil then
    params.ephemeral = opts.ephemeral
  end

  return params
end

function M.build_thread_list(config, cwd, opts)
  opts = opts or {}
  return {
    limit = opts.limit or config.thread_list.limit,
    cursor = opts.cursor,
    archived = opts.archived ~= nil and opts.archived or config.thread_list.archived,
    cwd = opts.cwd or (config.thread_list.cwd_only and cwd or nil),
    searchTerm = opts.search_term,
  }
end

function M.build_turn_start(_config, thread_id, text, opts)
  opts = opts or {}
  local runtime_settings = vim.deepcopy(opts.thread_runtime or {})
  local params = {
    threadId = thread_id,
    input = opts.input or {
      { type = "text", text = text },
    },
  }

  if opts.cwd then
    params.cwd = opts.cwd
  end
  if opts.approval_policy then
    params.approvalPolicy = opts.approval_policy
  end
  if opts.approvals_reviewer then
    params.approvalsReviewer = opts.approvals_reviewer
  end
  if opts.sandbox_policy then
    params.sandboxPolicy = opts.sandbox_policy
  end

  local collaboration_mode = opts.collaboration_mode or runtime.build_collaboration_mode(runtime_settings.collaborationModeMask, {
    model = opts.model or runtime_settings.model,
    effort = opts.effort or runtime_settings.effort,
  })
  if collaboration_mode then
    params.collaborationMode = collaboration_mode
  else
    params.model = opts.model or runtime_settings.model
    params.effort = opts.effort or runtime_settings.effort
  end

  if opts.service_tier then
    params.serviceTier = opts.service_tier
  end
  if opts.summary or runtime_settings.summary then
    params.summary = opts.summary or runtime_settings.summary
  end
  if opts.personality then
    params.personality = opts.personality
  end
  if opts.output_schema then
    params.outputSchema = opts.output_schema
  end

  return params
end

return M
