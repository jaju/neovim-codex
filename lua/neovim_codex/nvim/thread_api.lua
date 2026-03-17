local shared = require("neovim_codex.nvim.thread_api.shared")
local session = require("neovim_codex.nvim.thread_api.session")
local mutations = require("neovim_codex.nvim.thread_api.mutations")

local M = {}

function M.new(deps)
  local ctx = {
    ensure_runtime = deps.ensure_runtime,
    ensure_ready = deps.ensure_ready,
    notify = deps.notify,
    request_with_wait = deps.request_with_wait,
    wait_opts = deps.wait_opts,
    build_thread_start_params = deps.build_thread_start_params,
    build_thread_resume_params = deps.build_thread_resume_params,
    build_thread_fork_params = deps.build_thread_fork_params,
    build_thread_list_params = deps.build_thread_list_params,
    build_turn_steer_params = deps.build_turn_steer_params,
    reveal_chat = deps.reveal_chat,
    workbench = deps.workbench,
    chat = deps.chat,
    compact_text = deps.compact_text,
    clone_runtime_settings = deps.clone_runtime_settings,
    normalize_runtime_settings = deps.normalize_runtime_settings,
    current_cwd = deps.current_cwd,
    get_config = deps.get_config,
  }

  function ctx.get_state()
    return deps.ensure_runtime().client:get_state()
  end

  function ctx.runtime_picker(rt)
    return deps.make_runtime_picker(rt)
  end

  function ctx.query_loaded_threads(rt, opts)
    return ctx.runtime_picker(rt):query_loaded_threads(opts)
  end

  function ctx.pick_thread_runtime_async(rt, opts, on_done)
    return ctx.runtime_picker(rt):pick_async(opts, on_done)
  end

  function ctx.update_thread_runtime(thread_id, runtime_settings)
    return shared.update_thread_runtime(ctx, thread_id, runtime_settings)
  end

  local api = {}
  session.attach(api, ctx)
  mutations.attach(api, ctx)
  return api
end

return M
