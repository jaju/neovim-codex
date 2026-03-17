local selectors = require("neovim_codex.core.selectors")
local ui_prompt = require("neovim_codex.nvim.ui_prompt")
local shared = require("neovim_codex.nvim.thread_api.shared")

local M = {}

local input_async = ui_prompt.input_async
local select_async = ui_prompt.select_async

function M.attach(api, ctx)
  function api.fork_thread(opts)
    opts = opts or {}
    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local source_thread = opts.thread_id and selectors.get_thread(rt.client:get_state(), opts.thread_id)
      or selectors.get_active_thread(rt.client:get_state())
    if not source_thread then
      return nil, "no active thread"
    end

    local thread_result, thread_err = api.read_thread({
      thread_id = source_thread.id,
      include_turns = true,
      notify = false,
      timeout_ms = opts.timeout_ms,
    })
    if thread_err then
      ctx.notify(thread_err, vim.log.levels.ERROR, opts.notify)
      return nil, thread_err
    end

    local turns = thread_result.thread.turns or {}
    if #turns == 0 then
      return nil, "thread has no turns to fork"
    end

    local turn_choices = {}
    for index, turn in ipairs(turns) do
      turn_choices[#turn_choices + 1] = { index = index, turn = turn }
    end

    select_async(turn_choices, {
      prompt = "Fork from turn",
      format_item = function(item)
        return shared.turn_preview(ctx, item.turn, item.index)
      end,
    }, function(selected)
      if not selected then
        return
      end

      local seed = ctx.clone_runtime_settings(source_thread)
      seed.name = shared.thread_title(source_thread)
      seed.ephemeral = source_thread.ephemeral == true or seed.ephemeral == true
      ctx.pick_thread_runtime_async(rt, {
        include_name = true,
        include_ephemeral = true,
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

        local fork_result, fork_err = ctx.request_with_wait(function(done)
          rt.client:thread_fork(ctx.build_thread_fork_params({
            thread_id = source_thread.id,
            cwd = opts.cwd,
            model = settings.model,
            approval_policy = opts.approval_policy,
            sandbox = opts.sandbox,
            ephemeral = settings.ephemeral,
          }), done)
        end, ctx.wait_opts(opts))
        if fork_err then
          ctx.notify(fork_err, vim.log.levels.ERROR, opts.notify)
          return
        end

        local dropped_turns = #turns - selected.index
        if dropped_turns > 0 then
          local rollback_result, rollback_err = ctx.request_with_wait(function(done)
            rt.client:thread_rollback({ threadId = fork_result.thread.id, numTurns = dropped_turns }, done)
          end, ctx.wait_opts(opts))
          if rollback_err then
            ctx.notify(rollback_err, vim.log.levels.ERROR, opts.notify)
            return
          end
          fork_result = rollback_result or fork_result
        end

        ctx.update_thread_runtime(fork_result.thread.id, {
          model = settings.model,
          effort = settings.effort,
          summary = seed.summary,
          collaborationModeMask = settings.collaborationModeMask,
          ephemeral = settings.ephemeral,
        })
        if settings.name and settings.name ~= "" then
          shared.submit_thread_rename(ctx, rt, fork_result.thread, settings.name, {
            wait = true,
            notify = false,
            timeout_ms = opts.timeout_ms,
          })
        end

        ctx.reveal_chat(rt)
        ctx.notify(
          string.format(
            "Forked thread %s from %s",
            shared.short_thread_id(fork_result.thread.id),
            shared.short_thread_id(source_thread.id)
          ),
          vim.log.levels.INFO,
          opts.notify
        )
      end)
    end)

    return { threadId = source_thread.id }, nil
  end

  function api.rename_thread(opts)
    opts = opts or {}
    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local snapshot = rt.client:get_state()
    local thread = opts.thread_id and selectors.get_thread(snapshot, opts.thread_id) or selectors.get_active_thread(snapshot)
    if not thread then
      ctx.notify("No active Codex thread to rename", vim.log.levels.INFO, opts.notify)
      return nil, "no active thread"
    end

    local name = opts.name
    if name == nil then
      input_async({
        prompt = string.format("Rename Codex thread %s: ", shared.short_thread_id(thread.id)),
        default = thread.name ~= nil and thread.name ~= vim.NIL and tostring(thread.name) or shared.thread_title(thread),
      }, function(input)
        if input == nil then
          ctx.notify("Cancelled thread rename", vim.log.levels.INFO, opts.notify)
          return
        end
        api.rename_thread({
          thread_id = thread.id,
          name = input,
          notify = opts.notify,
          timeout_ms = opts.timeout_ms,
          wait = true,
        })
      end)
      return { threadId = thread.id }, nil
    end

    return shared.submit_thread_rename(ctx, rt, thread, name, opts)
  end

  function api.archive_thread(opts)
    opts = opts or {}
    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local snapshot = rt.client:get_state()
    local thread = opts.thread_id and selectors.get_thread(snapshot, opts.thread_id) or selectors.get_active_thread(snapshot)
    if not thread then
      return api.pick_thread({ action = "archive", notify = opts.notify, timeout_ms = opts.timeout_ms })
    end

    local _, request_err = ctx.request_with_wait(function(done)
      rt.client:thread_archive({ threadId = thread.id }, done)
    end, ctx.wait_opts(opts))
    if request_err then
      ctx.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    if snapshot.threads.active_id == thread.id then
      rt.store:dispatch({ type = "thread_activated", thread_id = nil })
    end

    ctx.notify(string.format("Archived thread %s", shared.short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
    return { threadId = thread.id }, nil
  end

  function api.unarchive_thread(opts)
    opts = opts or {}
    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    if not opts.thread_id then
      return api.pick_thread({
        action = "unarchive",
        archived = true,
        prompt = "Select archived Codex thread",
        notify = opts.notify,
        timeout_ms = opts.timeout_ms,
      })
    end

    local result, request_err = ctx.request_with_wait(function(done)
      rt.client:thread_unarchive({ threadId = opts.thread_id }, done)
    end, ctx.wait_opts(opts))
    if request_err then
      ctx.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    ctx.notify(string.format("Restored thread %s", shared.short_thread_id(opts.thread_id)), vim.log.levels.INFO, opts.notify)
    return result or { threadId = opts.thread_id }, nil
  end

  function api.compact_thread(opts)
    opts = opts or {}
    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local snapshot = rt.client:get_state()
    local thread = opts.thread_id and selectors.get_thread(snapshot, opts.thread_id) or selectors.get_active_thread(snapshot)
    if not thread then
      return api.pick_thread({
        action = "compact",
        archived = false,
        prompt = "Select Codex thread to compact",
        notify = opts.notify,
        timeout_ms = opts.timeout_ms,
      })
    end

    local result, request_err = ctx.request_with_wait(function(done)
      rt.client:thread_compact_start({ threadId = thread.id }, done)
    end, ctx.wait_opts(opts))
    if request_err then
      ctx.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    ctx.notify(string.format("Started compaction for %s", shared.short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
    return result or { threadId = thread.id }, nil
  end

  function api.steer(opts)
    opts = opts or {}
    local rt, err = ctx.ensure_ready(opts.timeout_ms)
    if not rt then
      ctx.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    if ctx.workbench.has_fragments() then
      ctx.notify("Steer is unavailable while workbench fragments are staged", vim.log.levels.INFO, opts.notify)
      return nil, "workbench fragments are staged"
    end

    local turn, thread = selectors.find_running_turn(rt.client:get_state(), opts.thread_id)
    if not turn or not thread then
      ctx.notify("No running Codex turn to steer", vim.log.levels.INFO, opts.notify)
      return nil, "no running turn"
    end

    local using_draft = false
    local text = opts.text
    if opts.input == nil and text == nil then
      if not ctx.chat.is_visible() then
        ctx.notify("Steer text is required when chat is hidden", vim.log.levels.INFO, opts.notify)
        return nil, "steer text is required"
      end
      text = ctx.chat.read_draft()
      using_draft = true
    end

    if opts.input == nil and vim.trim(tostring(text or "")) == "" then
      ctx.notify("Steer text is empty", vim.log.levels.INFO, opts.notify)
      return nil, "steer text is empty"
    end

    local result, request_err = ctx.request_with_wait(function(done)
      rt.client:turn_steer(ctx.build_turn_steer_params(thread.id, turn.id, text, opts), done)
    end, ctx.wait_opts(opts))
    if request_err then
      ctx.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    if using_draft and opts.clear_draft ~= false then
      ctx.chat.clear_draft()
    end

    ctx.notify(string.format("Steered turn %s", turn.id), vim.log.levels.INFO, opts.notify)
    return result or { turnId = turn.id }, nil
  end
end

return M
