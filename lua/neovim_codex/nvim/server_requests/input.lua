local viewer_stack = require("neovim_codex.nvim.viewer_stack")
local value = require("neovim_codex.core.value")
local surface_help = require("neovim_codex.nvim.surface_help")
local ui_prompt = require("neovim_codex.nvim.ui_prompt")

local M = {}
M.__index = M

local function value_or(candidate, fallback)
  if value.present(candidate) and tostring(candidate) ~= "" then
    return tostring(candidate)
  end
  return fallback
end

local function array_items(value)
  if type(value) == "table" then
    return value
  end
  return {}
end

local select_sync = ui_prompt.select_sync

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

function M.new(opts, handlers)
  handlers = handlers or {}
  return setmetatable({
    opts = opts or {},
    handlers = handlers,
    state_target = handlers.state_target,
    input_bufnr = nil,
    input_session = nil,
  }, M)
end

function M:_sync_public_state()
  if not self.state_target then
    return
  end
  self.state_target.input_bufnr = self.input_bufnr
  self.state_target.input_session = self.input_session
end

function M:_request_keymaps()
  return (((self.opts or {}).keymaps or {}).request) or {}
end

function M:_ensure_buffer()
  if self.input_bufnr and vim.api.nvim_buf_is_valid(self.input_bufnr) then
    return self.input_bufnr
  end
  self.input_bufnr = vim.api.nvim_create_buf(false, true)
  set_prompt_buffer_contract(self.input_bufnr)
  self:_sync_public_state()
  return self.input_bufnr
end

function M:open_text_input(question)
  local bufnr = self:_ensure_buffer()
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
  self:_sync_public_state()

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
          if self.handlers.open_shortcuts then
            self.handlers.open_shortcuts("request_input")
          end
        end,
        desc = "Show Codex request input shortcuts",
      },
    },
  })

  if entry and entry.popup and entry.popup.winid and vim.api.nvim_win_is_valid(entry.popup.winid) then
    for _, lhs in ipairs(surface_help.keys(self.opts, request_keymaps.help or "g?")) do
      if lhs ~= (request_keymaps.help or "g?") then
        vim.keymap.set({ "n", "i" }, lhs, function()
          if self.handlers.open_shortcuts then
            self.handlers.open_shortcuts("request_input")
          end
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
    self:_sync_public_state()
  end

  if session.cancelled then
    return nil, "cancelled"
  end
  return session.text, nil
end

function M:ask_question(question)
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
        local response, err = self:open_text_input(question)
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
    local response, err = self:open_text_input(question)
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

function M:inspect()
  return {
    input_active = self.input_session ~= nil,
  }
end

return M
