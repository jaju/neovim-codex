local selectors = require("neovim_codex.core.selectors")
local value = require("neovim_codex.core.value")
local coalesced_schedule = require("neovim_codex.nvim.coalesced_schedule")
local viewer_stack = require("neovim_codex.nvim.viewer_stack")
local request_input = require("neovim_codex.nvim.server_requests.input")
local request_render = require("neovim_codex.nvim.server_requests.render")
local ui_prompt = require("neovim_codex.nvim.ui_prompt")

local M = {}
M.__index = M

local surface_help = require("neovim_codex.nvim.surface_help")

local function array_items(value)
  if type(value) == "table" then
    return value
  end
  return {}
end

local select_sync = ui_prompt.select_sync

function M.new(opts, handlers)
  opts = opts or {}
  handlers = handlers or {}
  local instance = setmetatable({
    opts = opts,
    handlers = handlers,
    store = nil,
    unsubscribe = nil,
    dismissed = {},
    render_cache = {},
    current = nil,
    input_bufnr = nil,
    input_session = nil,
    sync_job = nil,
  }, M)
  instance.input = request_input.new(opts, {
    notify = handlers.notify,
    state_target = instance,
    open_shortcuts = function(surface)
      require("neovim_codex").open_shortcuts({ surface = surface })
    end,
  })
  return instance
end

function M:attach(store)
  if self.unsubscribe then
    self.unsubscribe()
    self.unsubscribe = nil
  end
  if self.sync_job then
    self.sync_job:dispose()
    self.sync_job = nil
  end
  self.store = store
  self.sync_job = coalesced_schedule.new(function(store_state)
    self:sync(store_state)
  end)
  self.unsubscribe = store:subscribe(function(store_state)
    self.sync_job:trigger(store_state)
  end)
  self:sync(store:get_state())
end

function M:dismiss_request(key)
  if key then
    self.dismissed[key] = true
  end
end

function M:clear_dismissal(key)
  if key then
    self.dismissed[key] = nil
  end
end

function M:_request_keymaps()
  return (((self.opts or {}).keymaps or {}).request) or {}
end

function M:_rendered_request(request, keymaps)
  local key = request and request.key
  if not key then
    return request_render.render_request(request, keymaps)
  end

  self.render_cache = self.render_cache or {}
  local cached = self.render_cache[key]
  if cached then
    return cached
  end

  local rendered = request_render.render_request(request, keymaps)
  self.render_cache[key] = rendered
  return rendered
end

function M:_request_spec(request)
  local keymaps = self:_request_keymaps()
  local rendered = self:_rendered_request(request, keymaps)
  local mappings = {}

  if keymaps.respond ~= false then
    mappings[#mappings + 1] = {
      mode = "n",
      lhs = keymaps.respond or "<CR>",
      rhs = function()
        self:respond_current()
      end,
      desc = "Resolve pending Codex request",
    }
  end

  if keymaps.help ~= false then
    local primary_help = keymaps.help or "g?"
    mappings[#mappings + 1] = {
      mode = "n",
      lhs = primary_help,
      rhs = function()
        require("neovim_codex").open_shortcuts({ surface = "request" })
      end,
      desc = "Show Codex request shortcuts",
    }
    for _, lhs in ipairs(surface_help.keys(self.opts, primary_help)) do
      if lhs ~= primary_help then
        mappings[#mappings + 1] = {
          mode = "n",
          lhs = lhs,
          rhs = function()
            require("neovim_codex").open_shortcuts({ surface = "request" })
          end,
          desc = "Show Codex request shortcuts",
        }
      end
    end
  end

  for _, lhs in ipairs({ "i", "I", "o", "O", "A", "R" }) do
    mappings[#mappings + 1] = {
      mode = "n",
      lhs = lhs,
      rhs = function() end,
      desc = "Request viewer is read-only",
    }
  end

  if request.method == "item/commandExecution/requestApproval" then
    local decisions = request_render.command_decisions(request)
    local shortcut_map = {
      a = "accept",
      s = "acceptForSession",
      d = "decline",
      c = "cancel",
    }
    for lhs, _ in pairs(shortcut_map) do
      local configured = ({
        a = keymaps.accept,
        s = keymaps.accept_for_session,
        d = keymaps.decline,
        c = keymaps.cancel,
      })[lhs]
      if configured ~= false and request_render.choice_for_shortcut(lhs, decisions) then
        mappings[#mappings + 1] = {
          mode = "n",
          lhs = configured or lhs,
          rhs = function()
            self:respond_with_decision(request, request_render.choice_for_shortcut(lhs, decisions))
          end,
          desc = string.format("Respond to Codex request with %s", lhs),
        }
      end
    end
  elseif request.method == "item/fileChange/requestApproval" then
    local decisions = request_render.file_change_decisions()
    local shortcut_map = {
      a = "accept",
      s = "acceptForSession",
      d = "decline",
      c = "cancel",
    }
    for lhs, decision in pairs(shortcut_map) do
      local configured = ({
        a = keymaps.accept,
        s = keymaps.accept_for_session,
        d = keymaps.decline,
        c = keymaps.cancel,
      })[lhs]
      if configured ~= false then
        mappings[#mappings + 1] = {
          mode = "n",
          lhs = configured or lhs,
          rhs = function()
            self:respond_with_decision(request, decision)
          end,
          desc = string.format("Respond to Codex file change request with %s", decision),
        }
      end
    end
  end

  return {
    key = "server-request",
    title = rendered.title,
    role = "request",
    filetype = "markdown",
    width = ((self.opts.ui or {}).requests or {}).width or 0.64,
    height = ((self.opts.ui or {}).requests or {}).height or 0.58,
    border = ((self.opts.ui or {}).requests or {}).border or "rounded",
    wrap = ((self.opts.ui or {}).requests or {}).wrap ~= false,
    lines = rendered.lines,
    sticky = true,
    enter_mode = "normal",
    prevent_insert = true,
    on_close = function()
      self:dismiss_request(request.key)
    end,
    mappings = mappings,
  }
end

function M:sync(store_state)
  local active_thread = selectors.get_active_thread(store_state)
  local request = selectors.get_active_request_for_thread(store_state, active_thread and active_thread.id or nil)
  self.current = value.deep_copy(request)

  if not request then
    viewer_stack.close("server-request")
    viewer_stack.close("server-request-input")
    self.dismissed = {}
    self.render_cache = {}
    return
  end

  if self.dismissed[request.key] then
    return
  end

  viewer_stack.open(self:_request_spec(request))
end

function M:open_current(opts)
  opts = opts or {}
  if not self.store then
    return nil, "request manager is not attached"
  end
  local state = self.store:get_state()
  local thread_id = opts.thread_id or (selectors.get_active_thread(state) and selectors.get_active_thread(state).id)
  local request = selectors.get_active_request_for_thread(state, thread_id)
  if not request then
    return nil, "no pending Codex request"
  end
  self:clear_dismissal(request.key)
  self.current = value.deep_copy(request)
  viewer_stack.open(self:_request_spec(request))
  return request, nil
end

function M:respond_with_decision(request, decision)
  local payload = { decision = value.deep_copy(decision) }
  local ok, err

  if request.method == "item/commandExecution/requestApproval" then
    ok, err = self.handlers.respond_command(request, payload)
  elseif request.method == "item/fileChange/requestApproval" then
    ok, err = self.handlers.respond_file_change(request, payload)
  else
    return nil, "request does not use decision responses"
  end

  if not ok then
    if self.handlers.notify then
      self.handlers.notify(err or "failed to send response", vim.log.levels.ERROR)
    end
    return nil, err
  end

  if self.handlers.notify then
    self.handlers.notify("Codex request response sent", vim.log.levels.INFO)
  end
  return true, nil
end

function M:respond_current()
  if not self.store then
    return nil, "request manager is not attached"
  end

  local request = selectors.get_active_request(self.store:get_state())
  if not request then
    return nil, "no pending Codex request"
  end

  if request.method == "item/tool/requestUserInput" then
    local answers = {}
    for _, question in ipairs(array_items(request.params.questions)) do
      local response, err = self.input:ask_question(question)
      if err then
        if self.handlers.notify then
          self.handlers.notify("Cancelled tool input collection", vim.log.levels.INFO)
        end
        return nil, err
      end
      answers[question.id] = { answers = response }
    end

    local ok, send_err = self.handlers.respond_tool_input(request, { answers = answers })
    if not ok then
      if self.handlers.notify then
        self.handlers.notify(send_err or "failed to send tool answers", vim.log.levels.ERROR)
      end
      return nil, send_err
    end

    if self.handlers.notify then
      self.handlers.notify("Codex tool answers sent", vim.log.levels.INFO)
    end
    return true, nil
  end

  local decisions = request.method == "item/commandExecution/requestApproval" and request_render.command_decisions(request) or request_render.file_change_decisions()
  local choices = {}
  for _, decision in ipairs(decisions) do
      choices[#choices + 1] = {
        label = request_render.decision_label(decision),
        value = value.deep_copy(decision),
      }
  end

  local selection = select_sync(choices, {
    prompt = "Select Codex decision",
    format_item = function(item)
      return item.label
    end,
  })
  if not selection then
    if self.handlers.notify then
      self.handlers.notify("Cancelled request decision", vim.log.levels.INFO)
    end
    return nil, "cancelled"
  end

  return self:respond_with_decision(request, selection.value)
end

function M:inspect()
  local input_state = self.input and self.input:inspect() or {}
  return {
    current = value.deep_copy(self.current),
    dismissed = value.deep_copy(self.dismissed),
    input_active = input_state.input_active == true,
  }
end

return M
