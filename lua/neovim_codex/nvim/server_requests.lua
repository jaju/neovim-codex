local selectors = require("neovim_codex.core.selectors")
local viewer_stack = require("neovim_codex.nvim.viewer_stack")

local M = {}
M.__index = M

local surface_help = require("neovim_codex.nvim.surface_help")

local function present(value)
  return value ~= nil and type(value) ~= "userdata"
end

local function clone_value(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for key, item in pairs(value) do
    out[key] = clone_value(item)
  end
  return out
end

local function value_or(value, fallback)
  if present(value) and tostring(value) ~= "" then
    return tostring(value)
  end
  return fallback
end

local function display_path(path)
  if not present(path) then
    return nil
  end
  local text = tostring(path)
  local home = vim.env.HOME
  if home and text:sub(1, #home) == home then
    return "~" .. text:sub(#home + 1)
  end
  return text
end

local function array_items(value)
  if type(value) == "table" then
    return value
  end
  return {}
end

local function split_lines(text)
  if not present(text) or tostring(text) == "" then
    return {}
  end
  return vim.split(tostring(text), "\n", { plain = true })
end

local function append_lines(target, lines)
  for _, line in ipairs(lines or {}) do
    target[#target + 1] = tostring(line)
  end
end

local function append_section(lines, heading, body)
  local body_lines = type(body) == "table" and body or split_lines(body)
  if not body_lines or #body_lines == 0 then
    return
  end
  if #lines > 0 then
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = heading
  lines[#lines + 1] = ""
  append_lines(lines, body_lines)
end

local function fence(text, lang)
  local out = { string.format("```%s", lang or "") }
  append_lines(out, type(text) == "table" and text or split_lines(text))
  out[#out + 1] = "```"
  return out
end

local function json_fence(value)
  if not present(value) then
    return nil
  end
  local ok, encoded = pcall(vim.json.encode, value)
  if not ok then
    return nil
  end
  return fence(encoded, "json")
end

local function compact(text, limit)
  if not present(text) then
    return nil
  end
  local value = tostring(text):gsub("\n", " "):gsub("%s+", " ")
  value = vim.trim(value)
  if value == "" then
    return nil
  end
  if #value <= limit then
    return value
  end
  return value:sub(1, math.max(1, limit - 3)) .. "..."
end

local function action_summary(action)
  local action_type = value_or(action and action.type, "unknown")
  if action_type == "read" then
    return string.format("- Read `%s`", display_path(action.path) or value_or(action.name, "file"))
  end
  if action_type == "listFiles" then
    return string.format("- Listed files in `%s`", display_path(action.path) or "workspace")
  end
  if action_type == "search" then
    local query = compact(action.query, 48)
    if query then
      return string.format("- Searched `%s` for `%s`", display_path(action.path) or "workspace", query)
    end
    return string.format("- Searched `%s`", display_path(action.path) or "workspace")
  end
  return string.format("- Action `%s`", action_type)
end

local function decision_kind(decision)
  if type(decision) == "string" then
    return decision
  end
  if type(decision) == "table" then
    return next(decision)
  end
  return "unknown"
end

local function decision_label(decision)
  local kind = decision_kind(decision)
  if kind == "accept" then
    return "Approve once"
  end
  if kind == "acceptForSession" then
    return "Approve for session"
  end
  if kind == "decline" then
    return "Decline"
  end
  if kind == "cancel" then
    return "Cancel"
  end
  if kind == "acceptWithExecpolicyAmendment" then
    return "Approve and persist similar commands"
  end
  if kind == "applyNetworkPolicyAmendment" then
    return "Apply proposed network policy"
  end
  return kind
end

local function command_decisions(request)
  local decisions = request.params.availableDecisions
  if type(decisions) == "table" and #decisions > 0 then
    return clone_value(decisions)
  end
  return { "accept", "acceptForSession", "decline", "cancel" }
end

local function file_change_decisions()
  return { "accept", "acceptForSession", "decline", "cancel" }
end

local function choice_for_shortcut(shortcut, decisions)
  for _, decision in ipairs(decisions or {}) do
    local kind = decision_kind(decision)
    if shortcut == "a" and kind == "accept" then
      return clone_value(decision)
    end
    if shortcut == "s" and kind == "acceptForSession" then
      return clone_value(decision)
    end
    if shortcut == "d" and kind == "decline" then
      return clone_value(decision)
    end
    if shortcut == "c" and kind == "cancel" then
      return clone_value(decision)
    end
  end
  return nil
end

local function select_sync(items, opts)
  local choice = nil
  local finished = false
  vim.ui.select(items, opts or {}, function(item)
    choice = item
    finished = true
  end)
  vim.wait(10000, function()
    return finished
  end, 20)
  return choice
end

local function input_sync(opts)
  local value = nil
  local finished = false
  vim.ui.input(opts or {}, function(input)
    value = input
    finished = true
  end)
  vim.wait(10000, function()
    return finished
  end, 20)
  return value
end

local function set_prompt_buffer_contract(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_name(bufnr, "neovim-codex://request/input")
  vim.b[bufnr].neovim_codex = true
  vim.b[bufnr].neovim_codex_role = "request_input"
end

local function set_prompt_buffer_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

local function prompt_buffer_text(bufnr, start_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, -1, false)
  while #lines > 0 and vim.trim(lines[#lines]) == "" do
    table.remove(lines)
  end
  return table.concat(lines, "\n")
end

local function ask_question(manager, question)
  local options = question.options
  if type(options) == "table" and #options > 0 then
    local choices = {}
    for _, option in ipairs(options) do
      choices[#choices + 1] = {
        label = option.label,
        description = option.description,
        value = option.label,
        is_other = false,
      }
    end
    if question.isOther then
      choices[#choices + 1] = {
        label = "Other",
        description = "Enter a custom answer.",
        value = nil,
        is_other = true,
      }
    end

    local selection = select_sync(choices, {
      prompt = string.format("%s: %s", value_or(question.header, "Question"), value_or(question.question, "")),
      format_item = function(item)
        if item.description and item.description ~= "" then
          return string.format("%s — %s", item.label, item.description)
        end
        return item.label
      end,
    })
    if not selection then
      return nil, "cancelled"
    end
    if selection.is_other then
      local text
      if question.isSecret then
        text = vim.fn.inputsecret(value_or(question.question, "Answer: "))
      else
        local response, err = manager:_open_text_input(question)
        if err then
          return nil, err
        end
        text = response
      end
      if text == nil then
        return nil, "cancelled"
      end
      return { tostring(text) }, nil
    end
    return { tostring(selection.value) }, nil
  end

  local text
  if question.isSecret then
    text = vim.fn.inputsecret(value_or(question.question, "Answer: "))
  else
    local response, err = manager:_open_text_input(question)
    if err then
      return nil, err
    end
    text = response
  end
  if text == nil then
    return nil, "cancelled"
  end
  return { tostring(text) }, nil
end

local function request_action_line(request, keymaps)
  keymaps = keymaps or {}
  local pieces = {}

  local function add(lhs, label)
    if lhs == false or lhs == nil then
      return
    end
    pieces[#pieces + 1] = string.format("[%s] %s", lhs, label)
  end

  if request.method == "item/tool/requestUserInput" then
    add(keymaps.respond or "<CR>", "Answer")
  else
    local decisions = request.method == "item/commandExecution/requestApproval" and command_decisions(request) or file_change_decisions()
    if choice_for_shortcut("a", decisions) then
      add(keymaps.accept or "a", "Approve once")
    end
    if choice_for_shortcut("s", decisions) then
      add(keymaps.accept_for_session or "s", "Approve session")
    end
    if choice_for_shortcut("d", decisions) then
      add(keymaps.decline or "d", "Decline")
    end
    if choice_for_shortcut("c", decisions) then
      add(keymaps.cancel or "c", "Cancel")
    end
    add(keymaps.respond or "<CR>", "Choose")
  end

  add(keymaps.help or "g?", "Shortcuts")
  add("q", "Hide")
  return string.format("> Actions: %s", table.concat(pieces, " · "))
end

local function render_command_request(request, keymaps)
  local lines = { "# Command approval", "", request_action_line(request, keymaps), "" }
  lines[#lines + 1] = string.format("- Thread: `%s`", value_or(request.thread_id, "-"))
  lines[#lines + 1] = string.format("- Turn: `%s`", value_or(request.turn_id, "-"))
  lines[#lines + 1] = string.format("- Item: `%s`", value_or(request.item_id, "-"))
  if present(request.params.reason) then
    lines[#lines + 1] = string.format("- Reason: %s", request.params.reason)
  end
  if present(request.params.cwd) then
    lines[#lines + 1] = string.format("- Working directory: `%s`", display_path(request.params.cwd) or request.params.cwd)
  end
  if present(request.params.networkApprovalContext) then
    append_section(lines, "## Network approval context", json_fence(request.params.networkApprovalContext))
  end
  local command_actions = array_items(request.params.commandActions)
  if #command_actions > 0 then
    local action_lines = {}
    for _, action in ipairs(command_actions) do
      action_lines[#action_lines + 1] = action_summary(action)
    end
    append_section(lines, "## Parsed actions", action_lines)
  end
  if present(request.params.command) then
    append_section(lines, "## Command", fence(request.params.command, "sh"))
  end
  if present(request.params.additionalPermissions) then
    append_section(lines, "## Additional permissions", json_fence(request.params.additionalPermissions))
  end
  if present(request.params.proposedExecpolicyAmendment) then
    append_section(lines, "## Proposed exec policy amendment", json_fence(request.params.proposedExecpolicyAmendment))
  end
  if present(request.params.proposedNetworkPolicyAmendments) then
    append_section(lines, "## Proposed network policy amendments", json_fence(request.params.proposedNetworkPolicyAmendments))
  end
  local decision_lines = {}
  for _, decision in ipairs(command_decisions(request)) do
    decision_lines[#decision_lines + 1] = string.format("- %s", decision_label(decision))
  end
  append_section(lines, "## Available decisions", decision_lines)
  return { title = "Command Approval", lines = lines }
end

local function render_file_change_request(request, keymaps)
  local lines = { "# File change approval", "", request_action_line(request, keymaps), "" }
  lines[#lines + 1] = string.format("- Thread: `%s`", value_or(request.thread_id, "-"))
  lines[#lines + 1] = string.format("- Turn: `%s`", value_or(request.turn_id, "-"))
  lines[#lines + 1] = string.format("- Item: `%s`", value_or(request.item_id, "-"))
  if present(request.params.reason) then
    lines[#lines + 1] = string.format("- Reason: %s", request.params.reason)
  end
  if present(request.params.grantRoot) then
    lines[#lines + 1] = string.format("- Grant root: `%s`", display_path(request.params.grantRoot) or request.params.grantRoot)
  end
  append_section(lines, "## Available decisions", {
    "- Approve once",
    "- Approve for session",
    "- Decline",
    "- Cancel",
  })
  return { title = "File Change Approval", lines = lines }
end

local function render_tool_request(request, keymaps)
  local lines = { "# Tool question", "", request_action_line(request, keymaps), "" }
  lines[#lines + 1] = string.format("- Thread: `%s`", value_or(request.thread_id, "-"))
  lines[#lines + 1] = string.format("- Turn: `%s`", value_or(request.turn_id, "-"))
  lines[#lines + 1] = string.format("- Item: `%s`", value_or(request.item_id, "-"))

  for index, question in ipairs(array_items(request.params.questions)) do
    local header = value_or(question.header, string.format("Question %d", index))
    local question_lines = {
      string.format("- Prompt: %s", value_or(question.question, "-")),
      string.format("- Accepts custom answer: %s", question.isOther and "yes" or "no"),
      string.format("- Secret input: %s", question.isSecret and "yes" or "no"),
    }
    for _, option in ipairs(array_items(question.options)) do
      question_lines[#question_lines + 1] = string.format("- Option: %s — %s", option.label, value_or(option.description, ""))
    end
    append_section(lines, string.format("## %s", header), question_lines)
  end

  return { title = "Tool Input Request", lines = lines }
end

local function render_request(request, keymaps)
  if not request then
    return { title = "Pending Request", lines = { "# Pending request", "", "No request is active." } }
  end
  if request.method == "item/commandExecution/requestApproval" then
    return render_command_request(request, keymaps)
  end
  if request.method == "item/fileChange/requestApproval" then
    return render_file_change_request(request, keymaps)
  end
  if request.method == "item/tool/requestUserInput" then
    return render_tool_request(request, keymaps)
  end
  return {
    title = value_or(request.method, "Pending Request"),
    lines = {
      "# Pending request",
      "",
      string.format("- Method: `%s`", value_or(request.method, "unknown")),
      string.format("- Request id: `%s`", value_or(request.request_id, "-")),
    },
  }
end

function M.new(opts, handlers)
  return setmetatable({
    opts = opts or {},
    handlers = handlers or {},
    store = nil,
    unsubscribe = nil,
    dismissed = {},
    current = nil,
    input_bufnr = nil,
    input_session = nil,
  }, M)
end

function M:attach(store)
  if self.unsubscribe then
    self.unsubscribe()
    self.unsubscribe = nil
  end
  self.store = store
  self.unsubscribe = store:subscribe(function(store_state)
    vim.schedule(function()
      self:sync(store_state)
    end)
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

function M:_request_spec(request)
  local keymaps = self:_request_keymaps()
  local rendered = render_request(request, keymaps)
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
    local decisions = command_decisions(request)
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
      if configured ~= false and choice_for_shortcut(lhs, decisions) then
        mappings[#mappings + 1] = {
          mode = "n",
          lhs = configured or lhs,
          rhs = function()
            self:respond_with_decision(request, choice_for_shortcut(lhs, decisions))
          end,
          desc = string.format("Respond to Codex request with %s", lhs),
        }
      end
    end
  elseif request.method == "item/fileChange/requestApproval" then
    local decisions = file_change_decisions()
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

function M:_ensure_input_buffer()
  if self.input_bufnr and vim.api.nvim_buf_is_valid(self.input_bufnr) then
    return self.input_bufnr
  end
  self.input_bufnr = vim.api.nvim_create_buf(false, true)
  set_prompt_buffer_contract(self.input_bufnr)
  return self.input_bufnr
end

function M:_open_text_input(question)
  local bufnr = self:_ensure_input_buffer()
  local prompt_lines = {
    string.format("# %s", value_or(question.header, "Answer")),
    "",
    value_or(question.question, "Answer:"),
    "",
    "> Submit with <C-s>. Press q to cancel.",
    "",
    "",
  }
  set_prompt_buffer_lines(bufnr, prompt_lines)

  local input_start_line = #prompt_lines
  local session = {
    done = false,
    cancelled = false,
    text = nil,
  }
  self.input_session = session

  local send_key = ((((self.opts or {}).keymaps or {}).composer or {}).send) or ((((self.opts or {}).keymaps or {}).compose_review or {}).send) or "<C-s>"
  local request_keymaps = self:_request_keymaps()

  local entry = viewer_stack.open({
    key = "server-request-input",
    title = value_or(question.header, "Tool answer"),
    role = "request_input",
    filetype = "markdown",
    bufnr = bufnr,
    manage_buffer = false,
    width = 0.58,
    height = 0.28,
    border = ((self.opts.ui or {}).requests or {}).border or "rounded",
    wrap = true,
    sticky = true,
    enter_mode = "insert",
    on_close = function()
      if self.input_session == session and not session.done then
        session.cancelled = true
        session.done = true
      end
    end,
    mappings = {
      {
        mode = { "i", "n" },
        lhs = send_key,
        rhs = function()
          local answer = prompt_buffer_text(bufnr, input_start_line)
          if vim.trim(answer) == "" then
            if self.handlers.notify then
              self.handlers.notify("Answer is empty", vim.log.levels.INFO)
            end
            return
          end
          session.text = answer
          session.done = true
          viewer_stack.close("server-request-input")
        end,
        desc = "Submit Codex request answer",
      },
      {
        mode = "n",
        lhs = request_keymaps.help or "g?",
        rhs = function()
          require("neovim_codex").open_shortcuts({ surface = "request_input" })
        end,
        desc = "Show Codex request input shortcuts",
      },
    },
  })

  if entry and entry.popup and entry.popup.winid and vim.api.nvim_win_is_valid(entry.popup.winid) then
    for _, lhs in ipairs(surface_help.keys(self.opts, request_keymaps.help or "g?")) do
      if lhs ~= (request_keymaps.help or "g?") then
        vim.keymap.set({ "n", "i" }, lhs, function()
          require("neovim_codex").open_shortcuts({ surface = "request_input" })
        end, { buffer = bufnr, silent = true, nowait = true, desc = "Show Codex request input shortcuts" })
      end
    end
    vim.api.nvim_set_current_win(entry.popup.winid)
    vim.api.nvim_win_set_cursor(entry.popup.winid, { input_start_line, 0 })
  end

  vim.wait(10000, function()
    return session.done
  end, 20)

  if self.input_session == session then
    self.input_session = nil
  end

  if session.cancelled then
    return nil, "cancelled"
  end
  return session.text, nil
end

function M:sync(store_state)
  local request = selectors.get_active_request(store_state)
  self.current = clone_value(request)

  if not request then
    viewer_stack.close("server-request")
    viewer_stack.close("server-request-input")
    self.dismissed = {}
    return
  end

  if self.dismissed[request.key] then
    return
  end

  viewer_stack.open(self:_request_spec(request))
end

function M:open_current()
  if not self.store then
    return nil, "request manager is not attached"
  end
  local request = selectors.get_active_request(self.store:get_state())
  if not request then
    return nil, "no pending Codex request"
  end
  self:clear_dismissal(request.key)
  self.current = clone_value(request)
  viewer_stack.open(self:_request_spec(request))
  return request, nil
end

function M:respond_with_decision(request, decision)
  local payload = { decision = clone_value(decision) }
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
      local response, err = ask_question(self, question)
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

  local decisions = request.method == "item/commandExecution/requestApproval" and command_decisions(request) or file_change_decisions()
  local choices = {}
  for _, decision in ipairs(decisions) do
    choices[#choices + 1] = {
      label = decision_label(decision),
      value = clone_value(decision),
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
  return {
    current = clone_value(self.current),
    dismissed = clone_value(self.dismissed),
    input_active = self.input_session ~= nil,
  }
end

return M
