local request_render = require("neovim_codex.nvim.server_requests.render")
local text_utils = require("neovim_codex.core.text")
local value = require("neovim_codex.core.value")

local M = {}

local append_lines = text_utils.append_lines
local display_path = text_utils.display_path
local present = value.present
local split_lines = text_utils.split_lines

local function value_or(input, fallback)
  if present(input) and tostring(input) ~= "" then
    return tostring(input)
  end
  return fallback
end

local function array_items(input)
  if type(input) == "table" then
    return input
  end
  return {}
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

local function change_kind_label(kind)
  local labels = {
    create = "A",
    update = "M",
    delete = "D",
    rename = "R",
  }
  return labels[tostring(kind or "")] or "?"
end

local function file_summary_lines(changes)
  local lines = {}
  for _, change in ipairs(array_items(changes)) do
    lines[#lines + 1] = string.format(
      "- `%s` `%s`",
      change_kind_label(change.kind),
      display_path(change.path) or value_or(change.path, "-")
    )
  end
  return lines
end

local function fallback_diff_sections(changes)
  local lines = {}
  for _, change in ipairs(array_items(changes)) do
    if present(change.diff) then
      append_section(
        lines,
        string.format("## %s {.foldable}", display_path(change.path) or value_or(change.path, "Changed file")),
        fence(change.diff, "diff")
      )
    end
  end
  return lines
end

local function action_summary(keymaps)
  keymaps = keymaps or {}
  local pieces = {}

  local function add(lhs, label)
    if lhs == false or lhs == nil then
      return
    end
    pieces[#pieces + 1] = string.format("[%s] %s", lhs, label)
  end

  add(keymaps.accept or "a", "Approve once")
  add(keymaps.accept_for_session or "s", "Approve session")
  add(keymaps.decline or "d", "Decline")
  add(keymaps.cancel or "c", "Cancel")
  add(keymaps.help or "g?", "Shortcuts")
  add("q", "Close")

  return string.format("> Actions: %s", table.concat(pieces, " · "))
end

function M.render_review(context, keymaps)
  local request = context.request or {}
  local turn = context.turn or {}
  local changes = array_items(context.changes)
  local lines = {
    "# File Change Review",
    "",
    action_summary(keymaps),
    "",
    string.format("- Thread: `%s`", value_or(request.thread_id, "-")),
    string.format("- Turn: `%s`", value_or(request.turn_id, "-")),
    string.format("- Item: `%s`", value_or(request.item_id, "-")),
    string.format("- Request id: `%s`", value_or(request.request_id, "-")),
    string.format("- Files changed: `%d`", #changes),
  }

  if present(request.params and request.params.reason) then
    lines[#lines + 1] = string.format("- Reason: %s", request.params.reason)
  end
  if present(request.params and request.params.grantRoot) then
    lines[#lines + 1] = string.format(
      "- Grant root: `%s`",
      display_path(request.params.grantRoot) or request.params.grantRoot
    )
  end
  if present(turn.status) then
    lines[#lines + 1] = string.format("- Turn status: `%s`", turn.status)
  end

  append_section(lines, "## Review scope", {
    "- Decisions apply to the whole patch currently exposed by Codex.",
    string.format("- Available decisions: %s", table.concat({
      request_render.decision_label("accept"),
      request_render.decision_label("acceptForSession"),
      request_render.decision_label("decline"),
      request_render.decision_label("cancel"),
    }, ", ")),
  })

  append_section(lines, "## Changed files", file_summary_lines(changes))

  if present(context.diff) then
    append_section(lines, "## Turn Diff {.foldable}", fence(context.diff, "diff"))
  else
    append_lines(lines, fallback_diff_sections(changes))
  end

  return {
    title = "File Change Review",
    lines = lines,
  }
end

return M
