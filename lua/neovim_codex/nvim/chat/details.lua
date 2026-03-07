local Popup = nil

local M = {}

local function present(value)
  return value ~= nil and type(value) ~= "userdata"
end

local function value_or(value, fallback)
  if present(value) and value ~= "" then
    return tostring(value)
  end
  return fallback
end

local function split_lines(text)
  if not present(text) or text == "" then
    return {}
  end
  return vim.split(tostring(text), "\n", { plain = true })
end

local function push_lines(lines, text)
  for _, line in ipairs(split_lines(text)) do
    lines[#lines + 1] = line
  end
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

local function duration_label(duration_ms)
  local value = tonumber(duration_ms)
  if not value then
    return nil
  end
  if value < 1000 then
    return string.format("%d ms", value)
  end
  return string.format("%.2f s", value / 1000)
end

local function plain_snippet(text, limit)
  if not present(text) then
    return nil
  end

  local value = tostring(text)
  value = value:gsub("`+", "")
  value = value:gsub("[%*_>#-]+", " ")
  value = value:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
  value = value:gsub("\n", " ")
  value = value:gsub("%s+", " ")
  value = vim.trim(value)
  if value == "" then
    return nil
  end

  if #value <= limit then
    return value
  end
  return value:sub(1, math.max(1, limit - 3)) .. "..."
end

local function first_nonempty_line(lines)
  for _, line in ipairs(lines or {}) do
    local trimmed = vim.trim(tostring(line))
    if trimmed ~= "" then
      return trimmed
    end
  end
  return nil
end

local function fence(lines, lang)
  local out = { string.format("```%s", lang or "") }
  if type(lines) == "string" then
    push_lines(out, lines)
  else
    for _, line in ipairs(lines or {}) do
      out[#out + 1] = tostring(line)
    end
  end
  out[#out + 1] = "```"
  return out
end

local function append_section(lines, heading, body)
  if not body then
    return
  end

  local body_lines = type(body) == "table" and body or split_lines(body)
  if #body_lines == 0 then
    return
  end

  if #lines > 0 then
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = heading
  lines[#lines + 1] = ""
  for _, line in ipairs(body_lines) do
    lines[#lines + 1] = line
  end
end

local function bullet(label, value)
  if not present(value) or tostring(value) == "" then
    return nil
  end
  return string.format("- %s: %s", label, tostring(value))
end

local function json_lines(value)
  if not present(value) then
    return nil
  end
  local ok, encoded = pcall(vim.json.encode, value)
  if not ok then
    return nil
  end
  return fence(encoded, "json")
end

local function format_action(action)
  local action_type = value_or(action and action.type, "unknown")
  if action_type == "read" then
    return string.format("- Read `%s`", display_path(action.path) or value_or(action.name, "file"))
  end
  if action_type == "listFiles" then
    return string.format("- Listed files in `%s`", display_path(action.path) or "workspace")
  end
  if action_type == "search" then
    local query = plain_snippet(action.query, 64)
    if query then
      return string.format("- Searched `%s` for `%s`", display_path(action.path) or "workspace", query)
    end
    return string.format("- Searched `%s`", display_path(action.path) or "workspace")
  end
  return string.format("- Action `%s`", action_type)
end

function M.render_block(block)
  if not block then
    return { title = "Details", lines = { "# Details", "", "No transcript block is selected." } }
  end

  local protocol = (block.protocol or {}).item or {}
  local item_type = (block.protocol or {}).item_type or protocol.type or block.kind
  local lines = {}
  local title = plain_snippet(first_nonempty_line(block.lines), 72) or value_or(item_type, "Details")

  if item_type == "userMessage" then
    lines = { "# Request", "" }
    local found = false
    for _, content_item in ipairs(protocol.content or {}) do
      if content_item.type == "text" and present(content_item.text) then
        push_lines(lines, content_item.text)
        found = true
      end
    end
    if not found then
      lines[#lines + 1] = "_No request text available._"
    end
    return { title = title, lines = lines }
  end

  if item_type == "agentMessage" then
    local phase = value_or(protocol.phase, "")
    lines = { phase == "commentary" and "# Working note" or "# Response", "" }
    push_lines(lines, value_or(protocol.text, "_No response text available._"))
    return { title = title, lines = lines }
  end

  if item_type == "plan" then
    lines = { "# Plan", "" }
    push_lines(lines, value_or(protocol.text, "_No plan text available._"))
    return { title = title, lines = lines }
  end

  if item_type == "reasoning" then
    lines = { "# Reasoning details" }
    if protocol.summary and #protocol.summary > 0 then
      append_section(lines, "## Summary", protocol.summary)
    end
    if protocol.content and #protocol.content > 0 then
      append_section(lines, "## Raw content", protocol.content)
    end
    if #lines == 1 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = "No reasoning content is available."
    end
    return { title = title, lines = lines }
  end

  if item_type == "commandExecution" then
    lines = { string.format("# Command · %s", value_or(protocol.status, "unknown")), "" }
    local meta = {
      bullet("Working directory", display_path(protocol.cwd)),
      bullet("Duration", duration_label(protocol.durationMs)),
      bullet("Exit code", present(protocol.exitCode) and tostring(protocol.exitCode) or nil),
    }
    for _, line in ipairs(meta) do
      if line then
        lines[#lines + 1] = line
      end
    end
    append_section(lines, "## Command", fence(value_or(protocol.command, "_No command available._"), "sh"))
    if protocol.commandActions and #protocol.commandActions > 0 then
      local action_lines = {}
      for _, action in ipairs(protocol.commandActions) do
        action_lines[#action_lines + 1] = format_action(action)
      end
      append_section(lines, "## Actions", action_lines)
    end
    if present(protocol.aggregatedOutput) and tostring(protocol.aggregatedOutput) ~= "" then
      append_section(lines, "## Output", fence(protocol.aggregatedOutput, "text"))
    end
    return { title = title, lines = lines }
  end

  if item_type == "fileChange" then
    lines = { "# File changes", "" }
    local changes = protocol.changes or {}
    if #changes == 0 then
      lines[#lines + 1] = "- No file details were reported."
    else
      for _, change in ipairs(changes) do
        local kind = type(change.kind) == "table" and value_or(change.kind.type, "updated") or value_or(change.kind, "updated")
        lines[#lines + 1] = string.format("- `%s` · %s", display_path(change.path) or "unknown", kind)
      end
    end
    return { title = title, lines = lines }
  end

  if item_type == "dynamicToolCall" or item_type == "mcpToolCall" or item_type == "collabAgentToolCall" then
    lines = { string.format("# Tool · %s", value_or(protocol.status, "unknown")), "" }
    lines[#lines + 1] = string.format("- Tool: `%s`", value_or(protocol.tool, "tool"))
    if present(protocol.server) then
      lines[#lines + 1] = string.format("- Server: `%s`", protocol.server)
    end
    if present(protocol.durationMs) then
      lines[#lines + 1] = string.format("- Duration: %s", duration_label(protocol.durationMs))
    end
    if protocol.contentItems and #protocol.contentItems > 0 then
      local content_lines = {}
      for _, item in ipairs(protocol.contentItems) do
        if item.type == "inputText" and present(item.text) then
          push_lines(content_lines, item.text)
        end
      end
      append_section(lines, "## Content", content_lines)
    end
    if protocol.result then
      append_section(lines, "## Result", json_lines(protocol.result))
    end
    if protocol.error and present(protocol.error.message) then
      append_section(lines, "## Error", { protocol.error.message })
    end
    return { title = title, lines = lines }
  end

  if item_type == "webSearch" then
    lines = { "# Web search", "", string.format("- Query: `%s`", value_or(protocol.query, "query")) }
    return { title = title, lines = lines }
  end

  if item_type == "enteredReviewMode" or item_type == "exitedReviewMode" then
    lines = { "# Review mode", "", string.format("- State: %s", item_type == "enteredReviewMode" and "entered" or "exited") }
    if present(protocol.review) then
      lines[#lines + 1] = string.format("- Review: `%s`", protocol.review)
    end
    return { title = title, lines = lines }
  end

  if item_type == "contextCompaction" then
    return { title = title, lines = { "# Context compaction", "", "Codex compacted the conversation history for this thread." } }
  end

  lines = { string.format("# %s", value_or(item_type, "Details")) }
  local encoded = json_lines(protocol)
  if encoded then
    append_section(lines, "## Protocol payload", encoded)
  else
    lines[#lines + 1] = ""
    lines[#lines + 1] = value_or(first_nonempty_line(block.lines), "No detail is available.")
  end
  return { title = title, lines = lines }
end

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local Details = {}
Details.__index = Details

function Details:_overlay_config()
  local ui = vim.api.nvim_list_uis()[1]
  local total_width = ui and ui.width or vim.o.columns
  local total_height = ui and ui.height or vim.o.lines
  local opts = self.opts.ui.chat.details or {}
  local width = math.max(60, math.floor(total_width * (opts.width or 0.72)))
  local height = math.max(16, math.floor(total_height * (opts.height or 0.68)))
  return {
    position = {
      row = math.max(1, math.floor((total_height - height) / 2)),
      col = math.max(1, math.floor((total_width - width) / 2)),
    },
    size = { width = width, height = height },
  }
end

function Details:_ensure_buffer()
  if valid_buffer(self.bufnr) then
    return self.bufnr
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  self.bufnr = bufnr
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_name(bufnr, "neovim-codex://chat/details")
  vim.b[bufnr].neovim_codex = true
  vim.b[bufnr].neovim_codex_role = "details"

  local function close()
    self:hide()
  end
  vim.keymap.set("n", "q", close, { buffer = bufnr, silent = true, desc = "Close Codex details" })
  vim.keymap.set("n", "<Esc>", close, { buffer = bufnr, silent = true, desc = "Close Codex details" })
  return bufnr
end

function Details:_ensure_popup(title)
  if not Popup then
    local ok, popup_mod = pcall(require, "nui.popup")
    if not ok then
      error(popup_mod)
    end
    Popup = popup_mod
  end

  if self.popup then
    self.popup.border:set_text("top", string.format(" %s ", title or "Details"), "center")
    return self.popup
  end

  local overlay = self:_overlay_config()
  self.popup = Popup({
    enter = true,
    focusable = true,
    relative = "editor",
    position = overlay.position,
    size = overlay.size,
    zindex = 60,
    border = {
      style = ((self.opts.ui.chat.details or {}).border) or "rounded",
      text = {
        top = string.format(" %s ", title or "Details"),
        top_align = "center",
      },
    },
    bufnr = self:_ensure_buffer(),
    win_options = {
      winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder",
    },
  })
  return self.popup
end

function Details:_set_lines(lines)
  local bufnr = self:_ensure_buffer()
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

function Details:show(block)
  local rendered = M.render_block(block)
  self.last_block = block
  self.last_render = rendered

  if self:is_visible() then
    self:hide()
  end

  local popup = self:_ensure_popup(rendered.title)
  local overlay = self:_overlay_config()
  popup:update({
    relative = "editor",
    position = overlay.position,
    size = overlay.size,
    border = {
      style = ((self.opts.ui.chat.details or {}).border) or "rounded",
      text = { top = string.format(" %s ", rendered.title or "Details"), top_align = "center" },
    },
  })
  self:_set_lines(rendered.lines)
  popup:mount()

  if valid_window(popup.winid) then
    vim.wo[popup.winid].number = false
    vim.wo[popup.winid].relativenumber = false
    vim.wo[popup.winid].signcolumn = "no"
    vim.wo[popup.winid].wrap = ((self.opts.ui.chat.details or {}).wrap) ~= false
    vim.wo[popup.winid].linebreak = ((self.opts.ui.chat.details or {}).wrap) ~= false
    vim.api.nvim_set_current_win(popup.winid)
  end
end

function Details:hide()
  if self.popup and self.popup._ and self.popup._.mounted then
    self.popup:unmount()
  end
end

function Details:is_visible()
  return self.popup and self.popup._ and self.popup._.mounted or false
end

function Details:inspect()
  return {
    visible = self:is_visible(),
    bufnr = self.bufnr,
    winid = self.popup and self.popup.winid or nil,
    last_render = self.last_render,
  }
end

function M.new(opts)
  return setmetatable({ opts = opts, bufnr = nil, popup = nil, last_block = nil, last_render = nil }, Details)
end

return M
