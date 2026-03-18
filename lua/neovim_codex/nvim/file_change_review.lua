local selectors = require("neovim_codex.core.selectors")
local coalesced_schedule = require("neovim_codex.nvim.coalesced_schedule")
local review_render = require("neovim_codex.nvim.file_change_review.render")
local surface_help = require("neovim_codex.nvim.surface_help")
local viewer_stack = require("neovim_codex.nvim.viewer_stack")

local M = {}
M.__index = M

local FILE_CHANGE_METHOD = "item/fileChange/requestApproval"
local VIEWER_KEY = "file-change-review"
local DETAIL_VIEWER_KEY = "file-change-review-detail"

local function array_items(input)
  if type(input) == "table" then
    return input
  end
  return {}
end

local function find_file_change_request(state, opts)
  opts = opts or {}

  if opts.request_key then
    local request = selectors.get_pending_request(state, opts.request_key)
    if request and request.method == FILE_CHANGE_METHOD then
      return request, nil
    end
    return nil, "pending file change request was not found"
  end

  local thread_id = opts.thread_id
  if not thread_id then
    local active_thread = selectors.get_active_thread(state)
    thread_id = active_thread and active_thread.id or nil
  end
  if not thread_id then
    return nil, "no active thread"
  end

  local requests = selectors.list_pending_requests_for_thread(state, thread_id)
  for index = #requests, 1, -1 do
    if requests[index].method == FILE_CHANGE_METHOD then
      return requests[index], nil
    end
  end

  return nil, "no pending file change review"
end

local function resolve_context(state, request)
  local thread = selectors.get_thread(state, request.thread_id)
  local turn = thread and selectors.get_turn(thread, request.turn_id) or nil
  local item = turn and turn.items_by_id and turn.items_by_id[request.item_id] or nil

  return {
    request = request,
    thread = thread,
    turn = turn,
    item = item,
    changes = array_items(item and item.changes),
    diff = type(turn and turn.diff) == "string" and turn.diff or nil,
  }
end

function M.new(opts, handlers)
  opts = opts or {}
  handlers = handlers or {}
  return setmetatable({
    opts = opts,
    handlers = handlers,
    store = nil,
    unsubscribe = nil,
    refresh_job = nil,
    current_request_key = nil,
    current_file_index = 1,
  }, M)
end

local function clamp_file_index(context, index)
  local changes = array_items(context and context.changes)
  if #changes == 0 then
    return nil
  end

  index = tonumber(index) or 1
  if index < 1 then
    return 1
  end
  if index > #changes then
    return #changes
  end
  return index
end

function M:_close_review_stack()
  viewer_stack.close(DETAIL_VIEWER_KEY)
  viewer_stack.close(VIEWER_KEY)
  self.current_request_key = nil
end

function M:_selected_context()
  if not self.store or not self.current_request_key then
    return nil, "no active file change review"
  end

  local request = selectors.get_pending_request(self.store:get_state(), self.current_request_key)
  if not request or request.method ~= FILE_CHANGE_METHOD then
    return nil, "no active file change request"
  end

  local context = resolve_context(self.store:get_state(), request)
  self.current_file_index = clamp_file_index(context, self.current_file_index) or 1
  return context, nil
end

function M:_step_file(delta)
  local context, err = self:_selected_context()
  if not context then
    return nil, err
  end

  local current = clamp_file_index(context, self.current_file_index)
  if not current then
    return nil, "no changed files are available for review"
  end

  self.current_file_index = clamp_file_index(context, current + delta)
  viewer_stack.refresh(VIEWER_KEY, self:_review_spec(context))
  if viewer_stack.is_open(DETAIL_VIEWER_KEY) then
    viewer_stack.refresh(DETAIL_VIEWER_KEY, self:_detail_spec(context))
  end
  return self.current_file_index, nil
end

function M:open_selected_file_diff()
  local context, err = self:_selected_context()
  if not context then
    return nil, err
  end

  local current = clamp_file_index(context, self.current_file_index)
  if not current then
    return nil, "no changed files are available for review"
  end

  self.current_file_index = current
  viewer_stack.open(self:_detail_spec(context))
  return current, nil
end

function M:attach(store)
  if self.unsubscribe then
    self.unsubscribe()
    self.unsubscribe = nil
  end
  if self.refresh_job then
    self.refresh_job:dispose()
    self.refresh_job = nil
  end

  self.store = store
  self.refresh_job = coalesced_schedule.new(function(store_state)
    self:sync(store_state)
  end)
  self.unsubscribe = store:subscribe(function(store_state)
    self.refresh_job:trigger(store_state)
  end)
end

function M:_review_keymaps()
  return (((self.opts or {}).keymaps or {}).file_change_review) or {}
end

function M:_open_shortcuts()
  require("neovim_codex").open_shortcuts({ surface = "file_change_review" })
end

function M:_review_spec(context)
  local keymaps = self:_review_keymaps()
  self.current_file_index = clamp_file_index(context, self.current_file_index) or 1
  local rendered = review_render.render_review(context, keymaps, self.current_file_index)
  local mappings = {}

  local function add_mapping(lhs, rhs, desc)
    if lhs == false or lhs == nil then
      return
    end
    mappings[#mappings + 1] = {
      mode = "n",
      lhs = lhs,
      rhs = rhs,
      desc = desc,
    }
  end

  add_mapping(keymaps.accept or "a", function()
    self:respond_with_decision("accept")
  end, "Approve the current Codex file change once")
  add_mapping(keymaps.accept_for_session or "s", function()
    self:respond_with_decision("acceptForSession")
  end, "Approve the current Codex file change for this session")
  add_mapping(keymaps.decline or "d", function()
    self:respond_with_decision("decline")
  end, "Decline the current Codex file change")
  add_mapping(keymaps.cancel or "c", function()
    self:respond_with_decision("cancel")
  end, "Cancel the current Codex file change review")
  add_mapping(keymaps.open_file or "o", function()
    self:open_selected_file_diff()
  end, "Open the selected changed file diff")
  add_mapping(keymaps.next_file or "]f", function()
    self:_step_file(1)
  end, "Move to the next changed file")
  add_mapping(keymaps.prev_file or "[f", function()
    self:_step_file(-1)
  end, "Move to the previous changed file")

  local primary_help = keymaps.help or "g?"
  add_mapping(primary_help, function()
    self:_open_shortcuts()
  end, "Show file change review shortcuts")
  for _, lhs in ipairs(surface_help.keys(self.opts, primary_help)) do
    if lhs ~= primary_help then
      add_mapping(lhs, function()
        self:_open_shortcuts()
      end, "Show file change review shortcuts")
    end
  end

  local details = (((self.opts or {}).ui or {}).chat or {}).details or {}
  return {
    key = VIEWER_KEY,
    title = rendered.title,
    role = "file_change_review",
    filetype = "markdown",
    width = details.width or 0.72,
    height = details.height or 0.68,
    border = details.border or "rounded",
    wrap = details.wrap ~= false,
    sticky = true,
    enter_mode = "normal",
    prevent_insert = true,
    lines = rendered.lines,
    on_close = function()
      self.current_request_key = nil
    end,
    mappings = mappings,
  }
end

function M:_detail_spec(context)
  local keymaps = self:_review_keymaps()
  local rendered = review_render.render_change_detail(context, self.current_file_index)
  local mappings = {}

  local function add_mapping(lhs, rhs, desc)
    if lhs == false or lhs == nil then
      return
    end
    mappings[#mappings + 1] = {
      mode = "n",
      lhs = lhs,
      rhs = rhs,
      desc = desc,
    }
  end

  add_mapping(keymaps.open_file or "o", function()
    self:open_selected_file_diff()
  end, "Refresh the selected changed file diff")
  add_mapping(keymaps.next_file or "]f", function()
    self:_step_file(1)
  end, "Move to the next changed file")
  add_mapping(keymaps.prev_file or "[f", function()
    self:_step_file(-1)
  end, "Move to the previous changed file")
  add_mapping(keymaps.accept or "a", function()
    self:respond_with_decision("accept")
  end, "Approve the current Codex file change once")
  add_mapping(keymaps.accept_for_session or "s", function()
    self:respond_with_decision("acceptForSession")
  end, "Approve the current Codex file change for this session")
  add_mapping(keymaps.decline or "d", function()
    self:respond_with_decision("decline")
  end, "Decline the current Codex file change")
  add_mapping(keymaps.cancel or "c", function()
    self:respond_with_decision("cancel")
  end, "Cancel the current Codex file change review")

  local primary_help = keymaps.help or "g?"
  add_mapping(primary_help, function()
    self:_open_shortcuts()
  end, "Show file change review shortcuts")
  for _, lhs in ipairs(surface_help.keys(self.opts, primary_help)) do
    if lhs ~= primary_help then
      add_mapping(lhs, function()
        self:_open_shortcuts()
      end, "Show file change review shortcuts")
    end
  end

  local details = (((self.opts or {}).ui or {}).chat or {}).details or {}
  return {
    key = DETAIL_VIEWER_KEY,
    title = rendered.title,
    role = "file_change_review",
    filetype = rendered.filetype or "diff",
    width = math.max(details.width or 0.72, 0.82),
    height = math.max(details.height or 0.68, 0.76),
    border = details.border or "rounded",
    wrap = false,
    sticky = true,
    enter_mode = "normal",
    prevent_insert = true,
    lines = rendered.lines,
    mappings = mappings,
  }
end

function M:sync(store_state)
  if not self.current_request_key then
    return
  end

  local request = selectors.get_pending_request(store_state, self.current_request_key)
  if not request or request.method ~= FILE_CHANGE_METHOD then
    self:_close_review_stack()
    return
  end

  local context = resolve_context(store_state, request)
  self.current_file_index = clamp_file_index(context, self.current_file_index) or 1
  viewer_stack.refresh(VIEWER_KEY, self:_review_spec(context))
  if viewer_stack.is_open(DETAIL_VIEWER_KEY) then
    viewer_stack.refresh(DETAIL_VIEWER_KEY, self:_detail_spec(context))
  end
end

function M:open_current(opts)
  if not self.store then
    return nil, "file change review is not attached"
  end

  local request, err = find_file_change_request(self.store:get_state(), opts)
  if not request then
    return nil, err
  end

  self.current_request_key = request.key
  self.current_file_index = 1
  viewer_stack.open(self:_review_spec(resolve_context(self.store:get_state(), request)))
  return request, nil
end

function M:respond_with_decision(decision)
  if not self.store then
    return nil, "file change review is not attached"
  end
  if not self.current_request_key then
    return nil, "no active file change review"
  end

  local request = selectors.get_pending_request(self.store:get_state(), self.current_request_key)
  if not request or request.method ~= FILE_CHANGE_METHOD then
    self:_close_review_stack()
    return nil, "no active file change request"
  end

  local ok, err = self.handlers.respond_request(request, { decision = decision })
  if not ok then
    if self.handlers.notify then
      self.handlers.notify(err or "failed to send file change response", vim.log.levels.ERROR)
    end
    return nil, err
  end

  if self.handlers.notify then
    self.handlers.notify("Codex file change response sent", vim.log.levels.INFO)
  end
  self:_close_review_stack()
  return true, nil
end

return M
