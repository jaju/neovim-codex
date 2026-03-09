local list_mod = require("neovim_codex.nvim.workbench.list")
local thread_identity = require("neovim_codex.nvim.thread_identity")

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

function Tray:layout_config()
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

function Tray:title(thread_id, fragments)
  if not thread_id then
    return "Workbench · no active thread"
  end
  return string.format(
    "Workbench · thread %s · %d fragment%s",
    thread_identity.short_id(thread_id),
    #fragments,
    #fragments == 1 and "" or "s"
  )
end

function Tray:bufnr_value()
  return self.list:bufnr_value()
end

function Tray:show(thread_id, fragments, winid)
  self.thread_id = thread_id
  self.fragments = fragments or {}
  self.visible = true
  self.list:update(thread_id, self.fragments)
  self.list:set_window(winid)
end

function Tray:hide()
  self.visible = false
  self.list:set_window(nil)
end

function Tray:update(thread_id, fragments, winid)
  self.thread_id = thread_id
  self.fragments = fragments or {}
  self.list:update(thread_id, self.fragments)
  self.list:set_window(winid)
end

function Tray:is_visible()
  return self.visible == true and valid_window(self.list.winid)
end

function Tray:current_fragment()
  return self.list:current_fragment()
end

function Tray:focus()
  if valid_window(self.list.winid) then
    vim.api.nvim_set_current_win(self.list.winid)
    return true
  end
  return false
end

function Tray:inspect()
  return {
    visible = self.visible,
    thread_id = self.thread_id,
    fragments = self.fragments,
    list = self.list:inspect(),
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
      end
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
    open_help = function()
      if handlers.open_help then
        handlers.open_help()
      end
    end,
  })

  return tray
end

return M
