local M = {}

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

local function ui_size()
  local ui = vim.api.nvim_list_uis()[1]
  local width = ui and ui.width or vim.o.columns
  local height = ui and ui.height or vim.o.lines
  return width, height
end

function M.normalize_mode(mode, opts)
  local default_mode = ((((opts or {}).ui or {}).chat or {}).layout or {}).mode or "rail"
  local resolved = mode or default_mode
  if resolved == "centered" or resolved == "overlay" then
    return "reader"
  end
  if resolved == "reader" or resolved == "rail" then
    return resolved
  end
  return "rail"
end

function M.overlay_config(opts, mode)
  local chat_opts = ((opts or {}).ui or {}).chat or {}
  local layout_opts = chat_opts.layout or {}
  local shell_mode = M.normalize_mode(mode, opts)
  local ui_width, ui_height = ui_size()

  if shell_mode == "rail" then
    local rail_opts = layout_opts.rail or {}
    local width = resolve_dimension(rail_opts.width or 0.42, ui_width, 48)
    local height = resolve_dimension(rail_opts.height or (ui_height - 2), ui_height, 16)
    local margin_top = resolve_dimension(rail_opts.margin_top or 1, ui_height, 0)
    local margin_right = resolve_dimension(rail_opts.margin_right or 1, ui_width, 0)
    return {
      mode = shell_mode,
      position = {
        row = math.max(0, margin_top),
        col = math.max(0, ui_width - width - margin_right),
      },
      size = {
        width = width,
        height = math.min(height, math.max(16, ui_height - margin_top)),
      },
    }
  end

  local reader_opts = layout_opts.reader or {}
  local width = resolve_dimension(reader_opts.width or layout_opts.width or 0.88, ui_width, 60)
  local height = resolve_dimension(reader_opts.height or layout_opts.height or 0.84, ui_height, 16)
  return {
    mode = shell_mode,
    position = {
      row = math.max(1, math.floor((ui_height - height) / 2)),
      col = math.max(1, math.floor((ui_width - width) / 2)),
    },
    size = {
      width = width,
      height = height,
    },
  }
end

function M.shell_title(mode, render_result)
  local shell_mode = mode == "reader" and "Reader" or "Rail"
  local pieces = { string.format(" Codex %s ", shell_mode) }
  local pending = render_result and render_result.pending_requests or 0
  if pending > 0 then
    pieces[#pieces + 1] = string.format("· Inbox %d ", pending)
  end
  return table.concat(pieces, "")
end

function M.composer_title(opts, mode)
  local keymaps = ((opts or {}).keymaps or {}).composer or {}
  local help = require("neovim_codex.nvim.surface_help").label(opts, keymaps.help or "g?")
  local send = keymaps.send or "<C-s>"
  local inbox = keymaps.request or "gr"
  local reader = keymaps.toggle_reader or "gR"
  local shell = mode == "reader" and "reader" or "rail"
  return string.format(" Compose · %s send · %s inbox · %s %s ", send, inbox, reader, shell == "reader" and "rail" or "reader")
end

return M
