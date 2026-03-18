local selectors = require("neovim_codex.core.selectors")
local value = require("neovim_codex.core.value")
local coalesced_schedule = require("neovim_codex.nvim.coalesced_schedule")
local viewer_stack = require("neovim_codex.nvim.viewer_stack")
local request_input = require("neovim_codex.nvim.server_requests.input")
local request_protocol = require("neovim_codex.nvim.server_requests.protocol")
local request_render = require("neovim_codex.nvim.server_requests.render")
local surface_help = require("neovim_codex.nvim.surface_help")
local ui_prompt = require("neovim_codex.nvim.ui_prompt")

local M = {}
M.__index = M

local select_sync = ui_prompt.select_sync

local function array_items(input)
  if type(input) == "table" then
    return input
  end
  return {}
end

local function keymap_for_choice(keymaps, shortcut)
  local mapping = {
    a = keymaps.accept,
    s = keymaps.accept_for_session,
    d = keymaps.decline,
    c = keymaps.cancel,
  }
  return mapping[shortcut]
end

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

function M:_append_respond_mapping(mappings, request, keymaps)
  local response_kind = request_protocol.response_kind(request)
  if response_kind ~= "tool_input" and response_kind ~= "choice" then
    return
  end
  if keymaps.respond == false then
    return
  end

  mappings[#mappings + 1] = {
    mode = "n",
    lhs = keymaps.respond or "<CR>",
    rhs = function()
      self:respond_current()
    end,
    desc = "Resolve pending Codex request",
  }
end

function M:_append_help_mappings(mappings, keymaps)
  if keymaps.help == false then
    return
  end

  local primary_help = keymaps.help or "g?"
  local function open_help()
    require("neovim_codex").open_shortcuts({ surface = "request" })
  end

  mappings[#mappings + 1] = {
    mode = "n",
    lhs = primary_help,
    rhs = open_help,
    desc = "Show Codex request shortcuts",
  }
  for _, lhs in ipairs(surface_help.keys(self.opts, primary_help)) do
    if lhs ~= primary_help then
      mappings[#mappings + 1] = {
        mode = "n",
        lhs = lhs,
        rhs = open_help,
        desc = "Show Codex request shortcuts",
      }
    end
  end
end

function M:_append_read_only_mappings(mappings)
  for _, lhs in ipairs({ "i", "I", "o", "O", "A", "R" }) do
    mappings[#mappings + 1] = {
      mode = "n",
      lhs = lhs,
      rhs = function() end,
      desc = "Request viewer is read-only",
    }
  end
end

function M:_append_review_mapping(mappings, request, keymaps)
  if not request_protocol.allows_review(request) then
    return
  end
  if keymaps.review == false or not self.handlers.open_file_change_review then
    return
  end

  mappings[#mappings + 1] = {
    mode = "n",
    lhs = keymaps.review or "o",
    rhs = function()
      self.handlers.open_file_change_review(request)
    end,
    desc = "Open the studied file change review",
  }
end

function M:_append_choice_mappings(mappings, request, keymaps)
  for _, item in ipairs(request_protocol.choice_entries(request)) do
    local lhs = item.shortcut and (keymap_for_choice(keymaps, item.shortcut) or item.shortcut) or nil
    if lhs ~= false and lhs ~= nil then
      mappings[#mappings + 1] = {
        mode = "n",
        lhs = lhs,
        rhs = function()
          self:respond_with_payload(request, item.payload)
        end,
        desc = string.format("Respond to the current Codex request with %s", item.label),
      }
    end
  end
end

function M:_request_spec(request)
  local keymaps = self:_request_keymaps()
  local rendered = self:_rendered_request(request, keymaps)
  local mappings = {}

  self:_append_respond_mapping(mappings, request, keymaps)
  self:_append_help_mappings(mappings, keymaps)
  self:_append_read_only_mappings(mappings)
  self:_append_review_mapping(mappings, request, keymaps)
  self:_append_choice_mappings(mappings, request, keymaps)

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
  local active_thread = selectors.get_active_thread(state)
  local thread_id = opts.thread_id or (active_thread and active_thread.id or nil)
  local request = selectors.get_active_request_for_thread(state, thread_id)
  if not request then
    return nil, "no pending Codex request"
  end
  self:clear_dismissal(request.key)
  self.current = value.deep_copy(request)
  viewer_stack.open(self:_request_spec(request))
  return request, nil
end

function M:respond_with_payload(request, payload)
  local ok, err = self.handlers.respond_request(request, value.deep_copy(payload))
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

function M:_respond_tool_input(request)
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

  return self:respond_with_payload(request, { answers = answers })
end

function M:_respond_choice_request(request)
  local choices = request_protocol.choice_entries(request)
  if #choices == 0 then
    return nil, "request has no available responses"
  end

  local selection = select_sync(choices, {
    prompt = "Select Codex response",
    format_item = function(item)
      return item.label
    end,
  })
  if not selection then
    if self.handlers.notify then
      self.handlers.notify("Cancelled request response", vim.log.levels.INFO)
    end
    return nil, "cancelled"
  end

  return self:respond_with_payload(request, selection.payload)
end

function M:respond_current()
  if not self.store then
    return nil, "request manager is not attached"
  end

  local request = selectors.get_active_request(self.store:get_state())
  if not request then
    return nil, "no pending Codex request"
  end

  local response_kind = request_protocol.response_kind(request)
  if response_kind == "tool_input" then
    return self:_respond_tool_input(request)
  end
  if response_kind == "choice" then
    return self:_respond_choice_request(request)
  end

  if self.handlers.notify then
    self.handlers.notify("This Codex request type is read-only in neovim-codex right now", vim.log.levels.WARN)
  end
  return nil, "unsupported request type"
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
