local presentation = require("neovim_codex.nvim.presentation")
local surface_help = require("neovim_codex.nvim.surface_help")

local M = {}

local function add_section(lines, title, entries, empty_note)
  if #lines > 0 then
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = title
  lines[#lines + 1] = ""
  if entries and #entries > 0 then
    for _, entry in ipairs(entries) do
      lines[#lines + 1] = entry
    end
    return
  end
  lines[#lines + 1] = empty_note or "- Nothing is configured for this lane."
end

local function add_mapping(entries, lhs, label)
  if lhs == false or lhs == nil then
    return
  end
  entries[#entries + 1] = string.format("- `%s` — %s", lhs, label)
end

local function add_mappings(entries, keys, label)
  for _, lhs in ipairs(keys or {}) do
    add_mapping(entries, lhs, label)
  end
end

local function surface_from_role(role)
  local mapping = {
    transcript = "transcript",
    composer = "composer",
    request = "request",
    request_input = "request_input",
    file_change_review = "file_change_review",
    workbench = "workbench",
    compose_review_message = "compose_review",
    compose_review_fragments = "compose_review",
  }
  return mapping[role] or "global"
end

local function infer_surface(opts)
  if opts and opts.surface then
    return opts.surface
  end
  local ok_role, role = pcall(function()
    return vim.b.neovim_codex_role
  end)
  if ok_role and role then
    return surface_from_role(role)
  end
  return "global"
end

local function fast_entries(config)
  local global = (config.keymaps or {}).global or {}
  local entries = {}
  add_mapping(entries, global.chat, "Toggle the Codex shell")
  add_mapping(entries, global.request, "Reopen the active thread inbox")
  add_mapping(entries, global.shortcuts, "Open this shortcut sheet from anywhere")
  return entries
end

local function workflow_entries(config)
  local global = (config.keymaps or {}).global or {}
  local entries = {}
  add_mapping(entries, global.new_thread, "Create a new thread")
  add_mapping(entries, global.threads, "Pick or resume a thread")
  add_mapping(entries, global.read_thread, "Open a thread report")
  add_mapping(entries, global.thread_rename, "Rename the active thread")
  add_mapping(entries, global.thread_fork, "Fork the active thread")
  add_mapping(entries, global.thread_archive, "Archive a thread")
  add_mapping(entries, global.thread_unarchive, "Restore an archived thread")
  add_mapping(entries, global.thread_settings, "Edit the active thread settings")
  add_mapping(entries, global.thread_compact, "Start manual history compaction")
  add_mapping(entries, global.interrupt, "Interrupt the active Codex turn")
  add_mapping(entries, global.turn_steer, "Steer the running Codex turn")
  add_mapping(entries, global.workbench, "Toggle the workbench tray")
  add_mapping(entries, global.compose, "Open compose review")
  add_mapping(entries, global.capture_path, "Stage the current file path")
  add_mapping(entries, global.capture_selection, "Stage the current visual selection")
  add_mapping(entries, global.capture_diagnostic, "Stage the diagnostic under cursor")
  return entries
end

local function surface_entries(config, surface)
  local entries = {}
  if surface == "transcript" then
    local keymaps = (config.keymaps or {}).transcript or {}
    add_mapping(entries, keymaps.inspect, "Inspect the current transcript block")
    add_mapping(entries, keymaps.focus_composer, "Focus the composer")
    add_mapping(entries, keymaps.switch_pane, "Switch between transcript and composer")
    add_mapping(entries, keymaps.request, "Reopen the active thread inbox")
    add_mapping(entries, keymaps.settings, "Edit the active thread settings")
    add_mapping(entries, keymaps.toggle_reader, "Toggle between rail and reader widths")
    add_mapping(entries, keymaps.prev_turn, "Jump to the previous turn")
    add_mapping(entries, keymaps.next_turn, "Jump to the next turn")
    add_mapping(entries, keymaps.close, "Hide the chat overlay")
    add_mappings(entries, surface_help.keys(config, keymaps.help), "Open contextual Codex help")
  elseif surface == "composer" then
    local keymaps = (config.keymaps or {}).composer or {}
    add_mapping(entries, keymaps.send, "Send the message, or open compose review when fragments are staged")
    add_mapping(entries, keymaps.send_normal, "Send from normal mode")
    add_mapping(entries, keymaps.steer, "Steer the running turn with the current draft")
    add_mapping(entries, keymaps.switch_pane, "Switch between composer and transcript")
    add_mapping(entries, keymaps.request, "Reopen the active thread inbox")
    add_mapping(entries, keymaps.settings, "Edit the active thread settings")
    add_mapping(entries, keymaps.toggle_reader, "Toggle between rail and reader widths")
    add_mapping(entries, keymaps.close, "Hide the chat overlay")
    add_mappings(entries, surface_help.keys(config, keymaps.help), "Open contextual Codex help")
  elseif surface == "request" then
    local keymaps = (config.keymaps or {}).request or {}
    add_mapping(entries, keymaps.respond, "Choose a decision or answer")
    add_mapping(entries, keymaps.review, "Open the studied file-change review")
    add_mapping(entries, keymaps.accept, "Approve once")
    add_mapping(entries, keymaps.accept_for_session, "Approve for session")
    add_mapping(entries, keymaps.decline, "Decline")
    add_mapping(entries, keymaps.cancel, "Cancel")
    add_mappings(entries, surface_help.keys(config, keymaps.help), "Open contextual Codex help")
    add_mapping(entries, "q", "Hide the request viewer")
  elseif surface == "file_change_review" then
    local keymaps = (config.keymaps or {}).file_change_review or {}
    add_mapping(entries, keymaps.accept, "Approve the reviewed file change once")
    add_mapping(entries, keymaps.accept_for_session, "Approve the reviewed file change for this session")
    add_mapping(entries, keymaps.decline, "Decline the reviewed file change")
    add_mapping(entries, keymaps.cancel, "Cancel the reviewed file change")
    add_mappings(entries, surface_help.keys(config, keymaps.help), "Open contextual Codex help")
    add_mapping(entries, "q", "Close the review surface")
  elseif surface == "request_input" then
    local help_keys = surface_help.keys(config, ((config.keymaps or {}).request or {}).help)
    local send = ((config.keymaps or {}).composer or {}).send or ((config.keymaps or {}).compose_review or {}).send or "<C-s>"
    add_mapping(entries, send, "Submit the typed answer")
    add_mapping(entries, "q", "Cancel the typed answer")
    add_mappings(entries, help_keys, "Open contextual Codex help")
    add_mapping(entries, "<Esc>", "Leave insert mode")
  elseif surface == "workbench" then
    local keymaps = (config.keymaps or {}).workbench or {}
    add_mapping(entries, keymaps.inspect, "Inspect the selected fragment")
    add_mapping(entries, keymaps.remove, "Remove the selected fragment")
    add_mapping(entries, keymaps.clear, "Clear the active workbench")
    add_mapping(entries, keymaps.compose, "Open compose review")
    add_mapping(entries, keymaps.insert_handle, "Open compose review and insert the selected fragment handle")
    add_mapping(entries, keymaps.park, "Park the selected fragment")
    add_mapping(entries, keymaps.unpark, "Unpark the selected fragment")
    add_mapping(entries, keymaps.preview, "Open packet preview")
    add_mapping(entries, keymaps.focus_message, "Focus the packet template")
    add_mappings(entries, surface_help.keys(config, keymaps.help), "Open contextual Codex help")
  elseif surface == "compose_review" then
    local keymaps = (config.keymaps or {}).compose_review or {}
    add_mapping(entries, keymaps.send, "Compile and send the packet")
    add_mapping(entries, keymaps.send_normal, "Compile and send from normal mode")
    add_mapping(entries, keymaps.preview, "Open packet preview")
    add_mapping(entries, keymaps.focus_fragments, "Focus the staged fragments list")
    add_mapping(entries, ((config.keymaps or {}).workbench or {}).insert_handle, "Insert the selected fragment handle and return to the packet template")
    add_mapping(entries, keymaps.close, "Close compose review")
    add_mappings(entries, surface_help.keys(config, keymaps.help), "Open contextual Codex help")
  end
  return entries
end

local function lines_for_surface(config, surface)
  local lines = {
    "# Codex shortcuts",
    "",
    string.format("- Surface: `%s`", surface),
    string.format("- From Codex surfaces, use `%s` to reopen this sheet.", surface_help.label(config, (((config.keymaps or {})[surface == "compose_review" and "compose_review" or surface] or {}).help) or "g?")),
    "- From anywhere, use `:CodexShortcuts` or your configured global shortcut.",
  }

  add_section(lines, "## This surface", surface_entries(config, surface), "- No contextual shortcuts are defined for this surface.")
  add_section(lines, "## Global fast", fast_entries(config), "- No global fast shortcuts are configured.")
  add_section(lines, "## Global workflow", workflow_entries(config), "- No global workflow shortcuts are configured.")

  if surface == "global" then
    add_section(lines, "## Start here", {
      "- Open chat with the fast toggle, then pick or create a thread.",
      "- Use the workbench only when you need staged code context.",
      "- Use compose review when fragments are staged or you want a final packet check.",
    })
  end

  return lines
end

function M.open(config, opts)
  local surface = infer_surface(opts)
  local lines = lines_for_surface(config, surface)
  presentation.open_report(string.format("shortcuts:%s", surface), lines, {
    title = string.format("Codex Shortcuts · %s", surface:gsub("_", " ")),
    role = "shortcuts",
    width = 0.58,
    height = 0.62,
    wrap = true,
  })
  return surface, lines
end

return M
