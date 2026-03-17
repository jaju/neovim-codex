local presentation = require("neovim_codex.nvim.presentation")
local renderer = require("neovim_codex.nvim.thread_renderer")
local selectors = require("neovim_codex.core.selectors")
local ui_prompt = require("neovim_codex.nvim.ui_prompt")
local shared = require("neovim_codex.nvim.thread_api.shared")

local M = {}

local select_async = ui_prompt.select_async

function M.attach(api, ctx)
  function api.new_thread(opts)
    opts = opts or {}
    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    if opts.open_chat ~= false then
      ctx.reveal_chat(rt)
    end

    local result, request_err = ctx.request_with_wait(function(done)
      rt.client:thread_start(ctx.build_thread_start_params(opts), done)
    end, ctx.wait_opts(opts))

    if request_err then
      ctx.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    if result and result.thread then
      ctx.update_thread_runtime(result.thread.id, {
        model = opts.model,
        effort = opts.effort,
        summary = opts.summary,
        collaborationModeMask = opts.collaboration_mode_mask,
        ephemeral = opts.ephemeral,
      })
      if opts.name and vim.trim(tostring(opts.name)) ~= "" then
        shared.submit_thread_rename(ctx, rt, result.thread, opts.name, {
          wait = true,
          notify = false,
          timeout_ms = opts.timeout_ms,
        })
      end
    end

    ctx.notify(string.format("Started thread %s", result.thread.id), vim.log.levels.INFO, opts.notify)
    return result, nil
  end

  function api.resume_thread(opts)
    opts = opts or {}
    if not opts.thread_id then
      return nil, "thread_id is required"
    end

    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local result, request_err = ctx.request_with_wait(function(done)
      rt.client:thread_resume(ctx.build_thread_resume_params(opts), done)
    end, ctx.wait_opts(opts))

    if request_err then
      ctx.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    if opts.open_chat ~= false then
      ctx.reveal_chat(rt)
    end

    if result and result.thread then
      local runtime_settings = ctx.clone_runtime_settings(result.thread)
      if opts.model ~= nil then runtime_settings.model = opts.model end
      if opts.effort ~= nil then runtime_settings.effort = opts.effort end
      if opts.summary ~= nil then runtime_settings.summary = opts.summary end
      if opts.collaboration_mode_mask ~= nil then runtime_settings.collaborationModeMask = opts.collaboration_mode_mask end
      ctx.update_thread_runtime(result.thread.id, runtime_settings)
    end

    ctx.notify(string.format("Resumed thread %s", result.thread.id), vim.log.levels.INFO, opts.notify)
    return result, nil
  end

  function api.list_threads(opts)
    opts = opts or {}
    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local result, request_err = ctx.request_with_wait(function(done)
      rt.client:thread_list(ctx.build_thread_list_params(opts), done)
    end, ctx.wait_opts(opts))

    if request_err then
      ctx.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    return result, nil
  end

  function api.read_thread(opts)
    opts = opts or {}
    if not opts.thread_id then
      return nil, "thread_id is required"
    end

    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local result, request_err = ctx.request_with_wait(function(done)
      rt.client:thread_read({
        threadId = opts.thread_id,
        includeTurns = opts.include_turns ~= false,
      }, done)
    end, ctx.wait_opts(opts))

    if request_err then
      ctx.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    return result, nil
  end

  function api.open_thread_report(opts)
    opts = opts or {}
    local result, err = api.read_thread(vim.tbl_extend("force", opts, { include_turns = true }))
    if err and err:match("includeTurns is unavailable") then
      result, err = api.read_thread(vim.tbl_extend("force", opts, { include_turns = false, notify = false }))
    end
    if err then
      return nil, err
    end

    local view = renderer.render_thread(result.thread, { title = "# Codex Thread" })
    presentation.open_report(string.format("thread-%s", result.thread.id), view.lines)
    return result, nil
  end

  function api.pick_thread(opts)
    opts = opts or {}
    local rt, ready_err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(ready_err, vim.log.levels.ERROR, opts.notify)
      return nil, ready_err
    end

    local result, err = api.list_threads(vim.tbl_extend("force", opts, { notify = false }))
    if err then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local state = ctx.get_state()
    local loaded_threads = ctx.query_loaded_threads(rt, opts)
    if type(loaded_threads) ~= "table" then
      loaded_threads = {}
    end

    local threads = shared.merge_known_threads(ctx, result.data or {}, state, opts)
    if #threads == 0 then
      ctx.notify("No matching Codex threads found", vim.log.levels.INFO, opts.notify)
      return nil, "no threads found"
    end

    local active_id = state.threads.active_id
    select_async(threads, {
      prompt = opts.prompt or "Select Codex thread",
      format_item = function(thread)
        return shared.format_thread_label(thread, active_id, state, loaded_threads)
      end,
    }, function(choice)
      if not choice then
        return
      end

      if opts.action == "read" then
        api.open_thread_report({ thread_id = choice.id, notify = opts.notify })
        return
      end
      if opts.action == "archive" then
        api.archive_thread({ thread_id = choice.id, notify = opts.notify, timeout_ms = opts.timeout_ms })
        return
      end
      if opts.action == "unarchive" then
        api.unarchive_thread({ thread_id = choice.id, notify = opts.notify, timeout_ms = opts.timeout_ms })
        return
      end
      if opts.action == "compact" then
        api.compact_thread({ thread_id = choice.id, notify = opts.notify, timeout_ms = opts.timeout_ms })
        return
      end

      local current_state = ctx.get_state()
      local local_thread = selectors.get_thread(current_state, choice.id)
      if choice.id == current_state.threads.active_id then
        ctx.reveal_chat(rt)
        return
      end

      if loaded_threads[choice.id] and local_thread and #((local_thread.turns_order) or {}) > 0 then
        rt.store:dispatch({ type = "thread_activated", thread_id = choice.id })
        ctx.reveal_chat(rt)
        return
      end

      api.resume_thread({ thread_id = choice.id, open_chat = true, notify = opts.notify })
    end)

    return threads, nil
  end

  function api.create_thread_with_settings(opts)
    opts = opts or {}
    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    ctx.pick_thread_runtime_async(rt, {
      include_name = true,
      include_ephemeral = true,
      seed = opts.seed,
      timeout_ms = opts.timeout_ms,
      notify = opts.notify,
    }, function(settings, settings_err)
      if settings_err then
        if settings_err ~= "cancelled" then
          ctx.notify(settings_err, vim.log.levels.ERROR, opts.notify)
        end
        return
      end

      api.new_thread(vim.tbl_extend("force", opts, {
        name = settings.name,
        ephemeral = settings.ephemeral,
        model = settings.model,
        effort = settings.effort,
        collaboration_mode_mask = settings.collaborationModeMask,
      }))
    end)

    return { pending = true }, nil
  end

  function api.configure_thread(opts)
    opts = opts or {}
    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local snapshot = rt.client:get_state()
    local thread = opts.thread_id and selectors.get_thread(snapshot, opts.thread_id) or selectors.get_active_thread(snapshot)
    if not thread then
      return nil, "no active thread"
    end

    local seed = ctx.clone_runtime_settings(thread)
    seed.ephemeral = thread.ephemeral == true or seed.ephemeral == true
    ctx.pick_thread_runtime_async(rt, {
      include_name = false,
      include_ephemeral = false,
      seed = seed,
      timeout_ms = opts.timeout_ms,
      notify = opts.notify,
    }, function(settings, settings_err)
      if settings_err then
        if settings_err ~= "cancelled" then
          ctx.notify(settings_err, vim.log.levels.ERROR, opts.notify)
        end
        return
      end

      ctx.update_thread_runtime(thread.id, {
        model = settings.model,
        effort = settings.effort,
        summary = seed.summary,
        collaborationModeMask = settings.collaborationModeMask,
        ephemeral = seed.ephemeral,
      })

      ctx.notify(
        string.format("Updated thread settings · %s", shared.short_thread_id(thread.id)),
        vim.log.levels.INFO,
        opts.notify
      )
    end)

    return { threadId = thread.id }, nil
  end
end

return M
