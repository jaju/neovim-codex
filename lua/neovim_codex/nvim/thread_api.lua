local history = require("neovim_codex.nvim.chat.history")
local history_pager = require("neovim_codex.nvim.history_pager")
local selectors = require("neovim_codex.core.selectors")
local thread_identity = require("neovim_codex.nvim.thread_identity")
local thread_params = require("neovim_codex.nvim.thread_params")
local thread_runtime = require("neovim_codex.nvim.thread_runtime")
local thread_runtime_picker = require("neovim_codex.nvim.thread_runtime_picker")
local ui_prompt = require("neovim_codex.nvim.ui_prompt")

local M = {}

local compact_text = thread_runtime.compact_text
local clone_runtime_settings = thread_runtime.clone_settings
local input_async = ui_prompt.input_async
local normalize_runtime_settings = thread_runtime.normalize
local select_async = ui_prompt.select_async

local function request_with_wait(request_fn, opts)
  opts = opts or {}
  local done = false
  local result = nil
  local err_message = nil

  request_fn(function(err, payload)
    done = true
    err_message = err
    result = payload
  end)

  if opts.wait then
    local ok = vim.wait(opts.timeout_ms or 4000, function()
      return done
    end, 50)
    if not ok then
      return nil, "timed out waiting for app-server response"
    end
  end

  return result, err_message
end

local function wait_opts(opts)
  return {
    wait = opts.wait ~= false,
    timeout_ms = opts.timeout_ms,
  }
end

M.request_with_wait = request_with_wait
M.wait_opts = wait_opts

local function current_cwd()
  return vim.fn.getcwd()
end

local function build_thread_start_params(deps, opts)
  return thread_params.build_thread_start(deps.get_config(), current_cwd(), opts)
end

local function build_thread_resume_params(deps, opts)
  return thread_params.build_thread_resume(deps.get_config(), opts)
end

local function build_thread_fork_params(deps, opts)
  return thread_params.build_thread_fork(deps.get_config(), opts)
end

local function build_thread_list_params(deps, opts)
  return thread_params.build_thread_list(deps.get_config(), current_cwd(), opts)
end

local function build_turn_steer_params(thread_id, turn_id, text, opts)
  return thread_params.build_turn_steer(thread_id, turn_id, text, opts)
end

local function short_thread_id(thread_id)
  return thread_identity.short_id(thread_id)
end

local function resolve_thread(snapshot, thread_id)
  if thread_id then
    return selectors.get_thread(snapshot, thread_id)
  end
  return selectors.get_active_thread(snapshot)
end

local function thread_title(thread)
  return thread_identity.title(thread)
end

local function list_turn_items(turn)
  if type(turn) ~= "table" then
    return {}
  end

  if type(turn.items_order) == "table" and type(turn.items_by_id) == "table" then
    return selectors.list_items(turn)
  end

  if type(turn.items) == "table" then
    return turn.items
  end

  return {}
end

local function turn_preview(turn, index)
  local summary = nil
  for _, item in ipairs(list_turn_items(turn)) do
    if item.type == "userMessage" or item.type == "agentMessage" then
      summary = compact_text(item.text, 88)
      if summary then
        break
      end
    end
  end

  summary = summary or "(no message preview)"
  return string.format("Turn %d · %s · %s", index, tostring(turn.status or "unknown"), summary)
end

local function build_turn_choices(turns)
  local choices = {}
  choices[#choices + 1] = {
    cancel = true,
    label = "Cancel",
  }
  for index, turn in ipairs(turns or {}) do
    choices[#choices + 1] = {
      index = index,
      turn = turn,
    }
  end
  return choices
end

local function format_turn_choice(item)
  if item.cancel == true then
    return item.label or "Cancel"
  end
  return turn_preview(item.turn, item.index)
end

local function perform_thread_rollback(rt, thread_id, dropped_turns, opts)
  if dropped_turns <= 0 then
    return { threadId = thread_id }, nil
  end

  return request_with_wait(function(done)
    rt.client:thread_rollback({ threadId = thread_id, numTurns = dropped_turns }, done)
  end, {
    wait = true,
    timeout_ms = (opts or {}).timeout_ms,
  })
end

local function update_thread_runtime(deps, thread_id, runtime_settings)
  if not thread_id then
    return
  end

  deps.ensure_runtime().store:dispatch({
    type = "thread_runtime_updated",
    thread_id = thread_id,
    runtime = normalize_runtime_settings(runtime_settings or {}),
  })
end

local function format_thread_label(thread, active_id, state, loaded_threads)
  local marker = thread.id == active_id and "●" or "○"
  local status = thread.status and thread.status.type or "unknown"
  local loaded = loaded_threads and loaded_threads[thread.id] and "⚡ " or ""
  local pending = selectors.pending_request_count_for_thread(state, thread.id)
  local pending_text = pending > 0 and string.format(" · inbox:%d", pending) or ""
  return string.format(
    "%s %s%s  [%s]%s  %s",
    marker,
    loaded,
    short_thread_id(thread.id),
    status,
    pending_text,
    thread_title(thread)
  )
end

local function merge_known_threads(deps, threads, state, opts)
  local merged = {}
  local seen = {}

  for _, thread in ipairs(threads or {}) do
    merged[#merged + 1] = thread
    seen[thread.id] = true
  end

  local thread_list_config = (deps.get_config().thread_list) or {}
  local expected_archived = opts.archived ~= nil and opts.archived or thread_list_config.archived
  local expected_cwd = opts.cwd or (thread_list_config.cwd_only and current_cwd() or nil)

  for _, thread in ipairs(selectors.list_threads(state)) do
    if not seen[thread.id] and thread.closed ~= true then
      local archived_ok = expected_archived == true and thread.archived == true or expected_archived ~= true and thread.archived ~= true
      local cwd_ok = expected_cwd == nil or thread.cwd == nil or thread.cwd == expected_cwd
      if archived_ok and cwd_ok then
        merged[#merged + 1] = thread
        seen[thread.id] = true
      end
    end
  end

  return merged
end

local function make_runtime_picker(deps, rt)
  return thread_runtime_picker.new({
    client = rt.client,
    config = deps.get_config(),
    request_with_wait = request_with_wait,
    notify = function(message, level, enabled)
      deps.notify(message, level, enabled)
    end,
    experimental_api = deps.get_config().experimental_api,
  })
end

local function query_loaded_threads(deps, rt, opts)
  return make_runtime_picker(deps, rt):query_loaded_threads(opts)
end

local function pick_thread_runtime_async(deps, rt, opts, on_done)
  return make_runtime_picker(deps, rt):pick_async(opts, on_done)
end

local function submit_thread_rename(deps, rt, thread, name, opts)
  opts = opts or {}
  local normalized_name = vim.trim(tostring(name))

  if opts.wait == true then
    local result, request_err = request_with_wait(function(done)
      rt.client:thread_name_set({ threadId = thread.id, name = normalized_name }, done)
    end, wait_opts(opts))

    if request_err then
      deps.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    if normalized_name == "" then
      deps.notify(string.format("Cleared thread name · %s", short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
    else
      deps.notify(
        string.format("Renamed thread %s to %s", short_thread_id(thread.id), normalized_name),
        vim.log.levels.INFO,
        opts.notify
      )
    end
    return result, nil
  end

  rt.client:thread_name_set({ threadId = thread.id, name = normalized_name }, function(request_err)
    if request_err then
      deps.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return
    end

    if normalized_name == "" then
      deps.notify(string.format("Cleared thread name · %s", short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
    else
      deps.notify(
        string.format("Renamed thread %s to %s", short_thread_id(thread.id), normalized_name),
        vim.log.levels.INFO,
        opts.notify
      )
    end
  end)

  return { threadId = thread.id, name = normalized_name }, nil
end

function M.new(deps)
  local api = {}

  local function ensure_thread_turns(thread, opts)
    local turns = history.list_turns(thread)
    if #turns > 0 then
      return thread, turns, nil
    end

    local result, err = api.read_thread({
      thread_id = thread.id,
      include_turns = true,
      notify = false,
      timeout_ms = opts.timeout_ms,
    })
    if err and err:match("includeTurns is unavailable") then
      return nil, nil, "thread history is unavailable for rollback"
    end
    if err then
      return nil, nil, err
    end

    local loaded_thread = result and result.thread or thread
    return loaded_thread, history.list_turns(loaded_thread), nil
  end

  local function ensure_thread_metadata(thread, opts)
    if thread and thread.status then
      return thread, nil
    end

    local result, err = api.read_thread({
      thread_id = thread.id,
      include_turns = false,
      notify = false,
      timeout_ms = opts.timeout_ms,
    })
    if err then
      return nil, err
    end

    return result and result.thread or thread, nil
  end

  local function confirm_rollback_async(thread, keep_index, dropped_turns, opts, on_choice)
    local choices = {
      {
        proceed = true,
        label = string.format("Rollback to turn %d", keep_index),
        detail = string.format(
          "Keep turns 1-%d and drop the last %d newer %s. File changes are not reverted.",
          keep_index,
          dropped_turns,
          dropped_turns == 1 and "turn" or "turns"
        ),
      },
      {
        proceed = false,
        label = "Cancel",
        detail = "Leave this thread history unchanged.",
      },
    }

    select_async(choices, {
      prompt = string.format("Rollback %s?", short_thread_id(thread.id)),
      format_item = function(item)
        return string.format("%s · %s", item.label, item.detail)
      end,
    }, function(choice)
      on_choice(choice and choice.proceed == true)
    end)
  end

  local function start_rollback_flow(rt, thread, opts)
    local loaded_thread, turns, turns_err = ensure_thread_turns(thread, opts)
    if turns_err then
      deps.notify(turns_err, vim.log.levels.ERROR, opts.notify)
      return nil, turns_err
    end

    if #turns == 0 then
      deps.notify("Thread has no turns to roll back", vim.log.levels.INFO, opts.notify)
      return nil, "thread has no turns to roll back"
    end

    local keep_index = tonumber(opts.keep_index)
    if keep_index == nil and opts.turn_id then
      keep_index = history.turn_index(turns, opts.turn_id)
    end

    if keep_index == nil then
      select_async(build_turn_choices(turns), {
        prompt = "Rollback to turn",
        format_item = format_turn_choice,
      }, function(selected)
        if not selected or selected.cancel == true then
          deps.notify("Cancelled thread rollback", vim.log.levels.INFO, opts.notify)
          return
        end

        api.rollback_thread(vim.tbl_extend("force", opts, {
          thread_id = loaded_thread.id,
          keep_index = selected.index,
        }))
      end)

      return { pending = true, threadId = loaded_thread.id }, nil
    end

    if keep_index < 1 or keep_index > #turns then
      local err = string.format("turn index %d is out of range for %d turns", keep_index, #turns)
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local dropped_turns = #turns - keep_index
    if dropped_turns <= 0 then
      deps.notify(
        string.format("Turn %d is already the latest turn in %s", keep_index, short_thread_id(loaded_thread.id)),
        vim.log.levels.INFO,
        opts.notify
      )
      return {
        threadId = loaded_thread.id,
        kept_turns = keep_index,
        dropped_turns = 0,
      }, nil
    end

    if opts.confirm ~= false and opts._confirmed ~= true then
      confirm_rollback_async(loaded_thread, keep_index, dropped_turns, opts, function(confirmed)
        if not confirmed then
          deps.notify("Cancelled thread rollback", vim.log.levels.INFO, opts.notify)
          return
        end

        api.rollback_thread(vim.tbl_extend("force", opts, {
          thread_id = loaded_thread.id,
          keep_index = keep_index,
          _confirmed = true,
        }))
      end)

      return {
        pending = true,
        threadId = loaded_thread.id,
        kept_turns = keep_index,
      }, nil
    end

    local result, rollback_err = perform_thread_rollback(rt, loaded_thread.id, dropped_turns, opts)
    if rollback_err then
      deps.notify(rollback_err, vim.log.levels.ERROR, opts.notify)
      return nil, rollback_err
    end

    if type(opts.on_success) == "function" then
      opts.on_success((result or {}).thread or loaded_thread, {
        keep_index = keep_index,
        dropped_turns = dropped_turns,
      })
    end

    deps.notify(
      string.format(
        "Rolled back %s to turn %d · dropped %d newer %s",
        short_thread_id(loaded_thread.id),
        keep_index,
        dropped_turns,
        dropped_turns == 1 and "turn" or "turns"
      ),
      vim.log.levels.INFO,
      opts.notify
    )

    return result or {
      threadId = loaded_thread.id,
      kept_turns = keep_index,
      dropped_turns = dropped_turns,
    }, nil
  end

  function api.new_thread(opts)
    opts = opts or {}
    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    if opts.open_chat ~= false then
      deps.reveal_chat(rt)
    end

    local result, request_err = request_with_wait(function(done)
      rt.client:thread_start(build_thread_start_params(deps, opts), done)
    end, wait_opts(opts))

    if request_err then
      deps.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    local started_thread = result and result.thread or nil
    if started_thread then
      local runtime_seed = clone_runtime_settings(selectors.get_thread(rt.client:get_state(), started_thread.id))
      update_thread_runtime(deps, started_thread.id, {
        model = runtime_seed.model,
        effort = runtime_seed.effort,
        summary = opts.summary,
        approvalPolicy = runtime_seed.approvalPolicy,
        collaborationModeMask = opts.collaboration_mode_mask,
        ephemeral = opts.ephemeral ~= nil and opts.ephemeral or runtime_seed.ephemeral,
      })
      if opts.name and vim.trim(tostring(opts.name)) ~= "" then
        submit_thread_rename(deps, rt, started_thread, opts.name, {
          wait = true,
          notify = false,
          timeout_ms = opts.timeout_ms,
        })
      end
    end

    local started_label = started_thread and started_thread.id or "(unknown id)"
    deps.notify(string.format("Started thread %s", started_label), vim.log.levels.INFO, opts.notify)
    return result, nil
  end

  function api.resume_thread(opts)
    opts = opts or {}
    if not opts.thread_id then
      return nil, "thread_id is required"
    end

    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local result, request_err = request_with_wait(function(done)
      rt.client:thread_resume(build_thread_resume_params(deps, opts), done)
    end, wait_opts(opts))

    if request_err then
      deps.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    if opts.open_chat ~= false then
      deps.reveal_chat(rt)
    end

    if result and result.thread then
      local runtime_settings = clone_runtime_settings(result.thread)
      if opts.model ~= nil then runtime_settings.model = opts.model end
      if opts.effort ~= nil then runtime_settings.effort = opts.effort end
      if opts.summary ~= nil then runtime_settings.summary = opts.summary end
      if opts.collaboration_mode_mask ~= nil then runtime_settings.collaborationModeMask = opts.collaboration_mode_mask end
      update_thread_runtime(deps, result.thread.id, runtime_settings)
    end

    deps.notify(string.format("Resumed thread %s", result.thread.id), vim.log.levels.INFO, opts.notify)
    return result, nil
  end

  function api.list_threads(opts)
    opts = opts or {}
    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local result, request_err = request_with_wait(function(done)
      rt.client:thread_list(build_thread_list_params(deps, opts), done)
    end, wait_opts(opts))

    if request_err then
      deps.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    return result, nil
  end

  function api.read_thread(opts)
    opts = opts or {}
    if not opts.thread_id then
      return nil, "thread_id is required"
    end

    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local result, request_err = request_with_wait(function(done)
      rt.client:thread_read({
        threadId = opts.thread_id,
        includeTurns = opts.include_turns ~= false,
      }, done)
    end, wait_opts(opts))

    if request_err then
      deps.notify(request_err, vim.log.levels.ERROR, opts.notify)
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

    history_pager.open(result.thread, {
      config = deps.get_config(),
      chunk_index = opts.chunk_index,
    })
    return result, nil
  end

  function api.open_history(opts)
    opts = opts or {}

    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local snapshot = rt.client:get_state()
    local thread = resolve_thread(snapshot, opts.thread_id)
    if not thread and not opts.thread_id then
      return api.pick_thread({
        action = "history",
        archived = false,
        prompt = "Select Codex thread history",
        notify = opts.notify,
        timeout_ms = opts.timeout_ms,
      })
    end

    if (not thread or #history.list_turns(thread) == 0) and opts.thread_id then
      local result, read_err = api.read_thread({
        thread_id = opts.thread_id,
        include_turns = true,
        notify = false,
        timeout_ms = opts.timeout_ms,
      })
      if read_err and read_err:match("includeTurns is unavailable") then
        result, read_err = api.read_thread({
          thread_id = opts.thread_id,
          include_turns = false,
          notify = false,
          timeout_ms = opts.timeout_ms,
        })
      end
      if read_err then
        deps.notify(read_err, vim.log.levels.ERROR, opts.notify)
        return nil, read_err
      end
      thread = result.thread
    end

    if not thread then
      return nil, "no active thread"
    end

    return history_pager.open(thread, {
      config = deps.get_config(),
      chunk_index = opts.chunk_index,
    }), nil
  end

  function api.pick_thread(opts)
    opts = opts or {}
    local rt, ready_err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(ready_err, vim.log.levels.ERROR, opts.notify)
      return nil, ready_err
    end

    local result, err = api.list_threads(vim.tbl_extend("force", opts, { notify = false }))
    if err then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local state = deps.ensure_runtime().client:get_state()
    local loaded_threads = query_loaded_threads(deps, rt, opts)
    if type(loaded_threads) ~= "table" then
      loaded_threads = {}
    end

    local threads = merge_known_threads(deps, result.data or {}, state, opts)
    if #threads == 0 then
      deps.notify("No matching Codex threads found", vim.log.levels.INFO, opts.notify)
      return nil, "no threads found"
    end

    local active_id = state.threads.active_id
    select_async(threads, {
      prompt = opts.prompt or "Select Codex thread",
      format_item = function(thread)
        return format_thread_label(thread, active_id, state, loaded_threads)
      end,
    }, function(choice)
      if not choice then
        return
      end

      if opts.action == "read" then
        api.open_thread_report({ thread_id = choice.id, notify = opts.notify })
        return
      end
      if opts.action == "history" then
        api.open_history({ thread_id = choice.id, notify = opts.notify, timeout_ms = opts.timeout_ms })
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
      if opts.action == "rollback" then
        api.rollback_thread({ thread_id = choice.id, notify = opts.notify, timeout_ms = opts.timeout_ms })
        return
      end

      local current_state = deps.ensure_runtime().client:get_state()
      local local_thread = selectors.get_thread(current_state, choice.id)
      if choice.id == current_state.threads.active_id then
        deps.reveal_chat(rt)
        return
      end

      if loaded_threads[choice.id] and local_thread and #((local_thread.turns_order) or {}) > 0 then
        rt.store:dispatch({ type = "thread_activated", thread_id = choice.id })
        deps.reveal_chat(rt)
        return
      end

      api.resume_thread({ thread_id = choice.id, open_chat = true, notify = opts.notify })
    end)

    return threads, nil
  end

  function api.create_thread_with_settings(opts)
    opts = opts or {}
    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    pick_thread_runtime_async(deps, rt, {
      include_name = true,
      include_ephemeral = true,
      include_developer_instructions = true,
      include_config_read = true,
      cwd = opts.cwd or current_cwd(),
      seed = opts.seed,
      timeout_ms = opts.timeout_ms,
      notify = opts.notify,
    }, function(settings, settings_err)
      if settings_err then
        if settings_err ~= "cancelled" then
          deps.notify(settings_err, vim.log.levels.ERROR, opts.notify)
        end
        return
      end

      api.new_thread(vim.tbl_extend("force", opts, {
        name = settings.name,
        ephemeral = settings.ephemeral,
        model = settings.model,
        effort = settings.effort,
        approval_policy = settings.approvalPolicy,
        collaboration_mode_mask = settings.collaborationModeMask,
        developer_instructions = settings.developerInstructions,
      }))
    end)

    return { pending = true }, nil
  end

  function api.configure_thread(opts)
    opts = opts or {}
    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local snapshot = rt.client:get_state()
    local thread = resolve_thread(snapshot, opts.thread_id)
    if not thread then
      if opts.thread_id then
        local loaded_thread, load_err = ensure_thread_metadata({ id = opts.thread_id }, opts)
        if load_err then
          deps.notify(load_err, vim.log.levels.ERROR, opts.notify)
          return nil, load_err
        end
        thread = loaded_thread
      else
        return nil, "no active thread"
      end
    end

    if not thread then
      return nil, "no active thread"
    end

    local seed = clone_runtime_settings(thread)
    seed.ephemeral = thread.ephemeral == true or seed.ephemeral == true
    pick_thread_runtime_async(deps, rt, {
      include_name = false,
      include_ephemeral = false,
      seed = seed,
      timeout_ms = opts.timeout_ms,
      notify = opts.notify,
    }, function(settings, settings_err)
      if settings_err then
        if settings_err ~= "cancelled" then
          deps.notify(settings_err, vim.log.levels.ERROR, opts.notify)
        end
        return
      end

      update_thread_runtime(deps, thread.id, {
        model = settings.model,
        effort = settings.effort,
        summary = seed.summary,
        approvalPolicy = settings.approvalPolicy,
        collaborationModeMask = settings.collaborationModeMask,
        ephemeral = seed.ephemeral,
      })

      deps.notify(
        string.format("Updated thread settings · %s", short_thread_id(thread.id)),
        vim.log.levels.INFO,
        opts.notify
      )
    end)

    return { threadId = thread.id }, nil
  end

  function api.fork_thread(opts)
    opts = opts or {}
    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local source_thread = resolve_thread(rt.client:get_state(), opts.thread_id)
    if not source_thread and opts.thread_id then
      source_thread = { id = opts.thread_id }
    end
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
      deps.notify(thread_err, vim.log.levels.ERROR, opts.notify)
      return nil, thread_err
    end

    source_thread = thread_result.thread or source_thread

    local turns = thread_result.thread.turns or {}
    if #turns == 0 then
      return nil, "thread has no turns to fork"
    end

    select_async(build_turn_choices(turns), {
      prompt = "Fork from turn",
      format_item = format_turn_choice,
    }, function(selected)
      if not selected or selected.cancel == true then
        return
      end

      local seed = clone_runtime_settings(source_thread)
      seed.name = thread_title(source_thread)
      seed.ephemeral = source_thread.ephemeral == true or seed.ephemeral == true
      pick_thread_runtime_async(deps, rt, {
        include_name = true,
        include_ephemeral = true,
        seed = seed,
        timeout_ms = opts.timeout_ms,
        notify = opts.notify,
      }, function(settings, settings_err)
        if settings_err then
          if settings_err ~= "cancelled" then
            deps.notify(settings_err, vim.log.levels.ERROR, opts.notify)
          end
          return
        end

        local fork_result, fork_err = request_with_wait(function(done)
          rt.client:thread_fork(build_thread_fork_params(deps, {
            thread_id = source_thread.id,
            cwd = opts.cwd,
            model = settings.model,
            approval_policy = settings.approvalPolicy,
            sandbox = opts.sandbox,
            ephemeral = settings.ephemeral,
          }), done)
        end, wait_opts(opts))
        if fork_err then
          deps.notify(fork_err, vim.log.levels.ERROR, opts.notify)
          return
        end

        local dropped_turns = #turns - selected.index
        if dropped_turns > 0 then
          local rollback_result, rollback_err = perform_thread_rollback(rt, fork_result.thread.id, dropped_turns, opts)
          if rollback_err then
            deps.notify(rollback_err, vim.log.levels.ERROR, opts.notify)
            return
          end
          fork_result = rollback_result or fork_result
        end

        local runtime_seed = clone_runtime_settings(selectors.get_thread(rt.client:get_state(), fork_result.thread.id))
        update_thread_runtime(deps, fork_result.thread.id, {
          model = runtime_seed.model,
          effort = runtime_seed.effort,
          summary = seed.summary,
          approvalPolicy = runtime_seed.approvalPolicy,
          collaborationModeMask = settings.collaborationModeMask,
          ephemeral = settings.ephemeral ~= nil and settings.ephemeral or runtime_seed.ephemeral,
        })
        if settings.name and settings.name ~= "" then
          submit_thread_rename(deps, rt, fork_result.thread, settings.name, {
            wait = true,
            notify = false,
            timeout_ms = opts.timeout_ms,
          })
        end

        deps.reveal_chat(rt)
        deps.notify(
          string.format(
            "Forked thread %s from %s",
            short_thread_id(fork_result.thread.id),
            short_thread_id(source_thread.id)
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
    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local snapshot = rt.client:get_state()
    local thread = resolve_thread(snapshot, opts.thread_id)
    if not thread then
      if opts.thread_id then
        if opts.name ~= nil then
          thread = { id = opts.thread_id }
        else
          local loaded_thread, load_err = ensure_thread_metadata({ id = opts.thread_id }, opts)
          if load_err then
            deps.notify(load_err, vim.log.levels.ERROR, opts.notify)
            return nil, load_err
          end
          thread = loaded_thread
        end
      else
        deps.notify("No active Codex thread to rename", vim.log.levels.INFO, opts.notify)
        return nil, "no active thread"
      end
    end

    if not thread then
      deps.notify("No active Codex thread to rename", vim.log.levels.INFO, opts.notify)
      return nil, "no active thread"
    end

    local name = opts.name
    if name == nil then
      input_async({
        prompt = string.format("Rename Codex thread %s: ", short_thread_id(thread.id)),
        default = thread.name ~= nil and thread.name ~= vim.NIL and tostring(thread.name) or thread_title(thread),
      }, function(input)
        if input == nil then
          deps.notify("Cancelled thread rename", vim.log.levels.INFO, opts.notify)
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

    return submit_thread_rename(deps, rt, thread, name, opts)
  end

  function api.archive_thread(opts)
    opts = opts or {}
    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local snapshot = rt.client:get_state()
    local thread = resolve_thread(snapshot, opts.thread_id)
    if not thread then
      if opts.thread_id then
        thread = { id = opts.thread_id }
      else
        return api.pick_thread({ action = "archive", notify = opts.notify, timeout_ms = opts.timeout_ms })
      end
    end

    if not thread then
      return api.pick_thread({ action = "archive", notify = opts.notify, timeout_ms = opts.timeout_ms })
    end

    local _, request_err = request_with_wait(function(done)
      rt.client:thread_archive({ threadId = thread.id }, done)
    end, wait_opts(opts))
    if request_err then
      deps.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    if snapshot.threads.active_id == thread.id then
      rt.store:dispatch({ type = "thread_activated", thread_id = nil })
    end

    deps.notify(string.format("Archived thread %s", short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
    return { threadId = thread.id }, nil
  end

  function api.unarchive_thread(opts)
    opts = opts or {}
    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
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

    local result, request_err = request_with_wait(function(done)
      rt.client:thread_unarchive({ threadId = opts.thread_id }, done)
    end, wait_opts(opts))
    if request_err then
      deps.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    deps.notify(string.format("Restored thread %s", short_thread_id(opts.thread_id)), vim.log.levels.INFO, opts.notify)
    return result or { threadId = opts.thread_id }, nil
  end

  function api.compact_thread(opts)
    opts = opts or {}
    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local snapshot = rt.client:get_state()
    local thread = resolve_thread(snapshot, opts.thread_id)
    if not thread then
      if opts.thread_id then
        thread = { id = opts.thread_id }
      else
        return api.pick_thread({
          action = "compact",
          archived = false,
          prompt = "Select Codex thread to compact",
          notify = opts.notify,
          timeout_ms = opts.timeout_ms,
        })
      end
    end

    if not thread then
      return api.pick_thread({
        action = "compact",
        archived = false,
        prompt = "Select Codex thread to compact",
        notify = opts.notify,
        timeout_ms = opts.timeout_ms,
      })
    end

    local result, request_err = request_with_wait(function(done)
      rt.client:thread_compact_start({ threadId = thread.id }, done)
    end, wait_opts(opts))
    if request_err then
      deps.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    deps.notify(string.format("Started compaction for %s", short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
    return result or { threadId = thread.id }, nil
  end

  function api.rollback_thread(opts)
    opts = opts or {}
    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    local snapshot = rt.client:get_state()
    local thread = resolve_thread(snapshot, opts.thread_id)

    if not thread and opts.thread_id then
      thread = { id = opts.thread_id }
    end

    if not thread then
      return api.pick_thread({
        action = "rollback",
        archived = false,
        prompt = "Select Codex thread to roll back",
        notify = opts.notify,
        timeout_ms = opts.timeout_ms,
      })
    end

    return start_rollback_flow(rt, thread, opts)
  end

  function api.steer(opts)
    opts = opts or {}
    local rt, err = deps.ensure_ready(opts.timeout_ms)
    if not rt then
      deps.notify(err, vim.log.levels.ERROR, opts.notify)
      return nil, err
    end

    if deps.workbench.has_fragments() then
      deps.notify("Steer is unavailable while workbench fragments are staged", vim.log.levels.INFO, opts.notify)
      return nil, "workbench fragments are staged"
    end

    local turn, thread = selectors.find_running_turn(rt.client:get_state(), opts.thread_id)
    if not turn or not thread then
      deps.notify("No running Codex turn to steer", vim.log.levels.INFO, opts.notify)
      return nil, "no running turn"
    end

    local using_draft = false
    local text = opts.text
    if opts.input == nil and text == nil then
      if not deps.chat.is_visible() then
        deps.notify("Steer text is required when chat is hidden", vim.log.levels.INFO, opts.notify)
        return nil, "steer text is required"
      end
      text = deps.chat.read_draft()
      using_draft = true
    end

    if opts.input == nil and vim.trim(tostring(text or "")) == "" then
      deps.notify("Steer text is empty", vim.log.levels.INFO, opts.notify)
      return nil, "steer text is empty"
    end

    local result, request_err = request_with_wait(function(done)
      rt.client:turn_steer(build_turn_steer_params(thread.id, turn.id, text, opts), done)
    end, wait_opts(opts))
    if request_err then
      deps.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    if using_draft and opts.clear_draft ~= false then
      deps.chat.clear_draft()
    end

    deps.notify(string.format("Steered turn %s", turn.id), vim.log.levels.INFO, opts.notify)
    return result or { turnId = turn.id }, nil
  end

  return api
end

return M
