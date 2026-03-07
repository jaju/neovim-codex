local Popup = require("nui.popup")

local list_mod = require("neovim_codex.nvim.workbench.list")

local M = {}

local function valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function resolve_dimension(value, total, minimum)
  if type(value) == "number" then
    if value > 0 and value < 1 then
      return math.max(minimum, math.floor(total * value))
    end
    return math.max(minimum, math.floor(value))
  end

  if type(value) == "string" and value:sub(-1) == "%" then
    local percentage = tonumber(value:sub(1, -2)) or 0
    return math.max(minimum, math.floor(total * (percentage / 100)))
  end

  return math.max(minimum, total)
end

local Tray = {}
Tray.__index = Tray

function Tray:_ui_size()
  local ui = vim.api.nvim_list_uis()[1]
  return ui and ui.width or vim.o.columns, ui and ui.height or vim.o.lines
end

function Tray:_config()
  local opts = self.opts.ui.workbench.tray or {}
  local total_width, total_height = self:_ui_size()
  local width = resolve_dimension(opts.width or 0.34, total_width, 34)
  local height = resolve_dimension(opts.height or 0.30, total_height, 10)
  return {
    relative = "editor",
    position = {
      row = math.max(1, total_height - height - (opts.margin_bottom or 2)),
      col = math.max(1, total_width - width - (opts.margin_right or 3)),
    },
    size = {
      width = width,
      height = height,
    },
  }
end

function Tray:_title(thread_id, fragments)
  if not thread_id then
    return " Workbench · no active thread "
  end
  return string.format(" Workbench · thread %s · %d fragment%s ", thread_id, #fragments, #fragments == 1 and "" or "s")
end

function Tray:_ensure_popup()
  if self.popup then
    return self.popup
  end

  self.popup = Popup({
    enter = false,
    focusable = true,
    zindex = 70,
    border = {
      style = (self.opts.ui.workbench.tray or {}).border or "rounded",
      text = { top = " Workbench ", top_align = "center" },
    },
    bufnr = self.list:bufnr_value(),
    win_options = {
      winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder",
    },
  })

  return self.popup
end

function Tray:_sync_window()
  self.list:set_window(self.popup and self.popup.winid)
end

function Tray:show(thread_id, fragments)
  local popup = self:_ensure_popup()
  popup.border:set_text("top", self:_title(thread_id, fragments or {}), "center")
  popup:update_layout(self:_config())
  self.list:update(thread_id, fragments or {})

  if popup._ and popup._.mounted then
    popup:show()
  else
    popup:mount()
  end

  self.visible = true
  self:_sync_window()
end

function Tray:hide()
  if not self.popup or not self.visible then
    return
  end
  self.popup:hide()
  self.visible = false
end

function Tray:toggle(thread_id, fragments)
  if self.visible then
    self:hide()
    return false
  end

  self:show(thread_id, fragments)
  return true
end

function Tray:update(thread_id, fragments)
  self.thread_id = thread_id
  self.fragments = fragments or {}
  if not self.visible then
    return
  end

  local popup = self:_ensure_popup()
  popup.border:set_text("top", self:_title(thread_id, self.fragments), "center")
  self.list:update(thread_id, self.fragments)
  if valid_window(popup.winid) then
    self:_sync_window()
  end
end

function Tray:is_visible()
  return self.visible
end

function Tray:current_fragment()
  return self.list:current_fragment()
end

function Tray:focus()
  if self.popup and valid_window(self.popup.winid) then
    vim.api.nvim_set_current_win(self.popup.winid)
    return true
  end
  return false
end

function Tray:inspect()
  return {
    visible = self.visible,
    popup = self.popup and self.popup.winid or nil,
    list = self.list:inspect(),
    thread_id = self.thread_id,
    fragments = self.fragments,
  }
end

function M.new(opts, handlers)
  local tray = setmetatable({
    opts = opts,
    handlers = handlers or {},
    visible = false,
    thread_id = nil,
    fragments = {},
  }, Tray)

  tray.list = list_mod.new(opts, "workbench", {
    close = function()
      if handlers.close then
        handlers.close()
        return
      end
      tray:hide()
    end,
    inspect = function()
      if handlers.inspect then
        handlers.inspect(tray:current_fragment())
      end
    end,
    remove = function()
      if handlers.remove then
        handlers.remove(tray:current_fragment())
      end
    end,
    clear = function()
      if handlers.clear then
        handlers.clear()
      end
    end,
    compose = function()
      if handlers.compose then
        handlers.compose()
      end
    end,
    open_help = handlers.open_help,
  })

  return tray
end

return M
