local presentation = require("neovim_codex.nvim.presentation")

local M = {}

local function add_section(lines, title, entries)
  if not entries or #entries == 0 then
    return
  end
  if #lines > 0 then
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = title
  lines[#lines + 1] = ""
  for _, entry in ipairs(entries) do
    lines[#lines + 1] = entry
  end
end

local function add_mapping(entries, lhs, label)
  if lhs == false or lhs == nil then
    return
  end
  entries[#entries + 1] = string.format("- `%s` — %s", lhs, label)
end

local function surface_from_role(role)
  local mapping = {
    transcript = "transcript",
    composer = "composer",
    request = "request",
    request_input = "request_input",
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

local function lines_for_surface(config, surface)
  local lines = { "# Codex shortcuts", "", string.format("- Surface: `%s`", surface) }
  local global = (config.keymaps or {}).global or {}
  local global_entries = {}
  add_mapping(global_entries, global.chat, "Toggle chat overlay")
  add_mapping(global_entries, global.threads, "Pick or resume a thread")
  add_mapping(global_entries, global.read_thread, "Open a thread report")
  add_mapping(global_entries, global.thread_rename, "Rename the active thread")
  add_mapping(global_entries, global.request, "Reopen the active request")
  add_mapping(global_entries, global.workbench, "Toggle the workbench tray")
  add_mapping(global_entries, global.compose, "Open compose review")
  add_mapping(global_entries, global.capture_path, "Stage the current file path")
  add_mapping(global_entries, global.capture_selection, "Stage the current visual selection")
  add_mapping(global_entries, global.capture_diagnostic, "Stage the diagnostic under cursor")
  add_mapping(global_entries, global.shortcuts, "Show contextual shortcuts")
  add_section(lines, "## Global", global_entries)

  local entries = {}
  if surface == "transcript" then
    local keymaps = (config.keymaps or {}).transcript or {}
    add_mapping(entries, keymaps.inspect, "Inspect the current transcript block")
    add_mapping(entries, keymaps.focus_composer, "Focus the composer")
    add_mapping(entries, keymaps.switch_pane, "Switch between transcript and composer")
    add_mapping(entries, keymaps.prev_turn, "Jump to the previous turn")
    add_mapping(entries, keymaps.next_turn, "Jump to the next turn")
    add_mapping(entries, keymaps.close, "Hide the chat overlay")
  elseif surface == "composer" then
    local keymaps = (config.keymaps or {}).composer or {}
    add_mapping(entries, keymaps.send, "Send the current message")
    add_mapping(entries, keymaps.send_normal, "Send the current message from normal mode")
    add_mapping(entries, keymaps.switch_pane, "Switch between composer and transcript")
    add_mapping(entries, keymaps.close, "Hide the chat overlay")
  elseif surface == "request" then
    local keymaps = (config.keymaps or {}).request or {}
    add_mapping(entries, keymaps.respond, "Choose a decision or answer")
    add_mapping(entries, keymaps.accept, "Approve once")
    add_mapping(entries, keymaps.accept_for_session, "Approve for session")
    add_mapping(entries, keymaps.decline, "Decline")
    add_mapping(entries, keymaps.cancel, "Cancel")
    add_mapping(entries, keymaps.help, "Show request shortcuts")
    add_mapping(entries, "q", "Hide the request viewer")
  elseif surface == "request_input" then
    local send = ((config.keymaps or {}).composer or {}).send or ((config.keymaps or {}).compose_review or {}).send or "<C-s>"
    add_mapping(entries, send, "Submit the typed answer")
    add_mapping(entries, "q", "Cancel the typed answer")
    add_mapping(entries, "<Esc>", "Leave insert mode")
  elseif surface == "workbench" then
    local keymaps = (config.keymaps or {}).workbench or {}
    add_mapping(entries, keymaps.inspect, "Inspect the selected fragment")
    add_mapping(entries, keymaps.remove, "Remove the selected fragment")
    add_mapping(entries, keymaps.clear, "Clear the active workbench")
    add_mapping(entries, keymaps.compose, "Open compose review")
    add_mapping(entries, keymaps.insert_handle, "Insert the selected handle")
    add_mapping(entries, keymaps.close, "Close the workbench tray")
  elseif surface == "compose_review" then
    local keymaps = (config.keymaps or {}).compose_review or {}
    add_mapping(entries, keymaps.send, "Compile and send the packet")
    add_mapping(entries, keymaps.send_normal, "Compile and send from normal mode")
    add_mapping(entries, keymaps.focus_fragments, "Focus the staged fragments list")
    add_mapping(entries, keymaps.close, "Close compose review")
  end

  add_section(lines, string.format("## %s", surface:gsub("_", " "):gsub("^%l", string.upper)), entries)
  if #entries == 0 then
    add_section(lines, "## Notes", { "- No contextual shortcuts are defined for this surface yet." })
  end
  return lines
end

function M.open(config, opts)
  local surface = infer_surface(opts)
  local lines = lines_for_surface(config, surface)
  presentation.open_report(string.format("shortcuts:%s", surface), lines, {
    title = string.format("Codex Shortcuts · %s", surface),
    role = "shortcuts",
    width = 0.56,
    height = 0.58,
    wrap = true,
  })
  return surface, lines
end

return M
