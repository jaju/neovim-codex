local selectors = require("neovim_codex.core.selectors")
local thread_identity = require("neovim_codex.nvim.thread_identity")

local M = {}

function M.short_thread_id(thread_id)
  return thread_identity.short_id(thread_id)
end

function M.thread_title(thread)
  return thread_identity.title(thread)
end

function M.turn_preview(ctx, turn, index)
  local summary = nil
  for _, item in ipairs(turn.items or {}) do
    if item.type == "userMessage" or item.type == "agentMessage" then
      summary = ctx.compact_text(item.text, 88)
      if summary then
        break
      end
    end
  end

  summary = summary or "(no message preview)"
  return string.format("Turn %d · %s · %s", index, tostring(turn.status or "unknown"), summary)
end

function M.update_thread_runtime(ctx, thread_id, runtime_settings)
  if not thread_id then
    return
  end

  ctx.ensure_runtime().store:dispatch({
    type = "thread_runtime_updated",
    thread_id = thread_id,
    runtime = ctx.normalize_runtime_settings(runtime_settings or {}),
  })
end

function M.format_thread_label(thread, active_id, state, loaded_threads)
  local marker = thread.id == active_id and "●" or "○"
  local status = thread.status and thread.status.type or "unknown"
  local loaded = loaded_threads and loaded_threads[thread.id] and "⚡ " or ""
  local pending = selectors.pending_request_count_for_thread(state, thread.id)
  local pending_text = pending > 0 and string.format(" · inbox:%d", pending) or ""
  return string.format(
    "%s %s%s  [%s]%s  %s",
    marker,
    loaded,
    M.short_thread_id(thread.id),
    status,
    pending_text,
    M.thread_title(thread)
  )
end

function M.merge_known_threads(ctx, threads, state, opts)
  local merged = {}
  local seen = {}

  for _, thread in ipairs(threads or {}) do
    merged[#merged + 1] = thread
    seen[thread.id] = true
  end

  local thread_list_config = (ctx.get_config().thread_list) or {}
  local expected_archived = opts.archived ~= nil and opts.archived or thread_list_config.archived
  local expected_cwd = opts.cwd or (thread_list_config.cwd_only and ctx.current_cwd() or nil)

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

function M.submit_thread_rename(ctx, rt, thread, name, opts)
  opts = opts or {}
  local normalized_name = vim.trim(tostring(name))

  if opts.wait == true then
    local result, request_err = ctx.request_with_wait(function(done)
      rt.client:thread_name_set({ threadId = thread.id, name = normalized_name }, done)
    end, ctx.wait_opts(opts))

    if request_err then
      ctx.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return nil, request_err
    end

    if normalized_name == "" then
      ctx.notify(string.format("Cleared thread name · %s", M.short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
    else
      ctx.notify(
        string.format("Renamed thread %s to %s", M.short_thread_id(thread.id), normalized_name),
        vim.log.levels.INFO,
        opts.notify
      )
    end
    return result, nil
  end

  rt.client:thread_name_set({ threadId = thread.id, name = normalized_name }, function(request_err)
    if request_err then
      ctx.notify(request_err, vim.log.levels.ERROR, opts.notify)
      return
    end

    if normalized_name == "" then
      ctx.notify(string.format("Cleared thread name · %s", M.short_thread_id(thread.id)), vim.log.levels.INFO, opts.notify)
    else
      ctx.notify(
        string.format("Renamed thread %s to %s", M.short_thread_id(thread.id), normalized_name),
        vim.log.levels.INFO,
        opts.notify
      )
    end
  end)

  return { threadId = thread.id, name = normalized_name }, nil
end

return M
