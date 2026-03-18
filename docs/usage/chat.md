# Chat Workflow

This is the day-to-day user flow for the current plugin slice.

## Open the overlay

```vim
:CodexChat
```

This toggles the default Codex shell mode, which is now a narrow right-side rail.

Use these when you want an explicit mode:

```vim
:CodexChatRail
:CodexChatReader
```

The rail keeps Codex available as an operational shell. The reader opens the same transcript/composer state in a wider centered view for comfortable reading.

The shell contains:

- a markdown transcript at the top
- a multiline markdown composer at the bottom

Run `:CodexChat` again to hide it.

## Send a turn

1. write a prompt in the composer
2. press `<C-s>` or run `:CodexSend`
3. keep using `<CR>` for newlines inside the draft

If the workbench is non-empty, `:CodexSend` opens compose review instead of sending immediately. Compose review is where you write the packet template, insert fragment handles such as `[[f1]]`, and preview the staged context that will be expanded at send time.

If no active thread exists yet, the plugin creates one first and then sends the turn.

If `<C-s>` is captured by your terminal, remap `keymaps.composer.send` or run `stty -ixon` in that shell.

## Transcript surfaces

The main transcript is protocol-first and conversation-first.

You should expect to see:

- user messages and final assistant responses as the primary reading surface
- plan blocks when Codex emits them
- commentary projected as markdown headings plus quoted working notes
- compact activity summaries for successful read/list/search command items
- terse failure summaries when a command or tool needs attention
- file-change summaries and other typed status blocks when they matter

You should not expect the main transcript to become a raw protocol dump or a live execution log.

Use `:CodexInspect` on the selected block when you need the full command, output, or typed payload. Use `:CodexEvents` for the underlying wire payloads and event sequencing. Both now open in the same stacked viewer layer above the chat overlay, so `q` or `<Esc>` closes the latest viewer and returns you to the previous one. If focus leaves all plugin-owned windows, the chat overlay closes instead of leaving a hidden cursor behind the modal.

## Blocking requests

When Codex asks for a decision or follow-up answer, the plugin opens a dedicated request viewer above the chat overlay.

This applies to:

- command approvals
- file-change approvals
- tool `requestUserInput` prompts

These are server-request state machines, not transcript content.

Use `:CodexRequest` or the default global `<F2>` mapping to reopen the active request if you hide it before responding. The request viewer opens in normal mode, uses your configured `vim.ui.select` for option choices, and opens a focused stacked text-answer popup for free-form responses. For file-change approvals, use the request-local `o` mapping or `:CodexReview` to inspect the structured diff review surface before you decide. Inside the review surface, `]f` and `[f` move between changed files and `o` opens a dedicated per-file diff viewer.

Default request viewer mappings:

- the viewer opens in normal mode and stays read-only
- `<CR>` - resolve the current request
- `a` - approve once when available
- `s` - approve for session when available
- `d` - decline
- `c` - cancel
- `o` - open the file-change review when the pending request is a file-change approval
- `g?` or `<F1>` - open the shortcut sheet for the current surface
- `q` or `<Esc>` - hide the viewer without resolving the request

Default file-change review mappings:

- `o` - open the currently selected changed file in a dedicated diff viewer
- `]f` - move to the next changed file
- `[f` - move to the previous changed file
- `a` - approve once
- `s` - approve for session
- `d` - decline
- `c` - cancel
- `g?` or `<F1>` - open the shortcut sheet for the current surface
- `q` or `<Esc>` - close the top review viewer and return to the previous review layer

If you want Codex state visible while you stay in normal editing windows, add the built-in statusline component to your own statusline:

```vim
set statusline+=%{%v:lua.require('neovim_codex').statusline()%}
```

It reports whether Codex is running, waiting for a request response, idle, stopped, or in error, and includes the pending-request reopen hint.

## Thread commands

- `:CodexThreadNew` - start a fresh thread explicitly
- `:CodexThreadNewConfig` - start a thread through the runtime settings flow
- `:CodexThreads` - pick and resume a stored thread
- `:CodexThreadRead` - inspect a thread without resuming it
- `:CodexThreadRename [name]` - rename the active thread
  - when no name is supplied, the prompt is collected asynchronously so the UI does not freeze first
- `:CodexThreadFork [thread-id]` - fork from a chosen turn in the active thread, or the supplied thread id
- `:CodexThreadArchive [thread-id]` - archive the active thread, or pick one to archive
- `:CodexThreadUnarchive [thread-id]` - restore an archived thread, or pick one from archived threads
- `:CodexThreadSettings [thread-id]` - edit sticky model, effort, approval policy, and collaboration mode for a thread
- `:CodexThreadCompact [thread-id]` - start manual history compaction for the active thread, or pick one
- `:CodexSteer [text]` - steer the currently running turn, or use the active draft when the shell is open
- `:CodexReview [request-key]` - open the current pending file-change review, or reopen one by request key
- `:CodexInterrupt` - interrupt the current turn

## Default overlay mappings

Transcript buffer:

- `q` - hide the overlay
- `gr` - reopen the active thread inbox
- `gR` - toggle between rail and reader widths
- `i` - jump to the composer
- insert-like keys in the transcript (`a`, `A`, `i`, `I`, `o`, `O`, `R`) also jump to the composer instead of entering insert mode
- `<C-w>w` - switch to the composer without leaving the overlay
- `<CR>` - inspect the selected transcript block in the stacked viewer layer
- `[[` - previous turn
- `]]` - next turn
- `g?` or `<F1>` - open the shortcut sheet for the current surface

Composer buffer:

- `<C-s>` - send the current draft from normal or insert mode
- `gS` - send the current draft from normal mode
- `gT` - steer the running turn with the current draft
- `<C-w>w` in normal mode - switch back to the transcript
- `q` in normal mode - hide the overlay
- `gr` - reopen the active thread inbox
- `gs` - open the active thread settings sheet
- `gR` - toggle between rail and reader widths
- `g?` or `<F1>` in normal mode - open the shortcut sheet for the current surface
- `<CR>` - insert a newline

## Overriding mappings

Mappings are merged over defaults in `setup()`.

```lua
require("neovim_codex").setup({
  keymaps = {
    global_fast_modes = { "n", "i", "x" },
    global_workflow_modes = { "n" },
    transcript = {
      focus_composer = "<CR>",
      next_turn = "]c",
      prev_turn = "[c",
    },
    composer = {
      send = "<C-s>",
      send_normal = false,
      steer = "gT",
    },
  },
})
```

Set any mapping to `false` to disable it.

## Markdown personalization

The transcript and composer are plain markdown buffers. Foldable secondary sections are projected as markdown headings with attribute markers such as `### Command {.foldable}`, so your own markdown folding or rendering config can decide how to treat them. The plugin marks them with:

- `b:neovim_codex = true`
- `b:neovim_codex_role = "transcript" | "composer" | "details" | "events" | "workbench" | "compose_review_message" | "compose_review_fragments"`
- `b:neovim_codex_thread_id = <thread-id>`

That means your own markdown ftplugin, treesitter config, render-markdown setup, or custom autocommands can target Codex buffers without special filetypes.

Example:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(args)
    if vim.b[args.buf].neovim_codex ~= true then
      return
    end
    vim.opt_local.wrap = true
    vim.opt_local.conceallevel = 2
  end,
})
```

The overlay also exposes highlight groups for transcript headings, so colorschemes or user config can tune them without changing the markdown filetype contract:

- `NeovimCodexChatTurnHeading`
- `NeovimCodexChatUserHeading`
- `NeovimCodexChatAssistantHeading`
- `NeovimCodexChatPlanHeading`
- `NeovimCodexChatReasoningHeading`
- `NeovimCodexChatActivityHeading`
- `NeovimCodexChatCommandHeading`
- `NeovimCodexChatFileChangeHeading`
- `NeovimCodexChatToolHeading`
- `NeovimCodexChatReviewHeading`
- `NeovimCodexChatNoticeHeading`

## Known behavior

- a fresh thread that has not accumulated turns can still be missing from the persisted `thread/list` view after a restart, depending on backend persistence behavior; within the current NeoVim session the picker merges locally known threads so they remain reachable
- a brand-new empty thread may not be resumable yet because the rollout is not materialized
- reading an empty thread with turns included can fail until the first user message is persisted; the plugin falls back to metadata-only reads for thread reports
- raw protocol and low-signal internal activity stay in `:CodexEvents`; the main transcript stays terse and uses `:CodexInspect` for verbose detail


## Workbench and compose review

The workbench is a thread-local staging area for semantic fragments.

You should expect to use it like this:

1. capture context from code buffers
2. quick-peek the staged fragments in `:CodexWorkbench`
3. remove stale fragments if needed
4. open `:CodexCompose` or just press `:CodexSend` from chat
5. review the packet and send it

The workbench tray is a small floating summary surface. The compose review is the larger finalization surface.

The footer of the chat overlay always shows the active thread id and the number of staged fragments:

- `thread <id> · workbench 3 fragments · ...`

Current capture commands:

- `:CodexCapturePath` - add the current file as a `path_ref`
- `:CodexCaptureSelection` - add the current visual selection as a `code_range`
- `:CodexCaptureDiagnostic` - add the current diagnostic under cursor as a `diagnostic`
- chat text can still be copied manually when needed; the workbench stays code-first in this slice


Workbench tray defaults:

- `<CR>` - inspect the selected fragment
- `dd` - remove the selected fragment
- `D` - clear the active thread workbench
- `o` - open compose review
- `i` - open compose review and insert the selected fragment handle
- `q` - close the tray

Compose review defaults:

- `<C-s>` - send the current packet from normal or insert mode
- `gS` - send the current packet from normal mode
- `<Tab>` - focus the fragment list from the message editor
- `i` - insert the selected fragment handle into the packet template
- `q` - close compose review

The workbench is thread-local. Active fragments are consumed on successful send, while parked fragments remain staged for the same thread. Only referenced active fragment handles are compiled into the outbound packet. If active fragments remain unreferenced, send fails cleanly so the packet stays explicit. Packet preview shows:

- referenced active fragments that will be sent
- unreferenced active fragments that still need attention
- parked fragments that will remain staged
- the final compiled text before send

Compose review itself also shows the live packet state in its borders:

- referenced active fragments already placed in the packet
- pending active fragments that still need placement or parking
- parked fragments that are staying out of this packet

## Suggested keymap grouping

If you want a coherent global cluster, keep capture and staging actions together and leave movement inside plugin-owned buffers buffer-local. One reasonable starting point is:

```lua
require("neovim_codex").setup({
  keymaps = {
    global = {
      chat = "<leader>ac",
      threads = "<leader>at",
      workbench = "<leader>aw",
      compose = "<leader>ap",
      capture_path = "<leader>af",
      capture_selection = "<leader>as",
      capture_diagnostic = "<leader>ad",
    },
  },
})
```

This keeps the mental grouping simple:

- `a` / agent cluster
- `c` / chat
- `t` / threads
- `w` / workbench
- `p` / packet / compose review
- `f` / file
- `s` / selection

The transcript stays a reading and inspection surface. Workbench capture is deliberately code-first for now.


Lua API:
- `require("neovim_codex").capture_text_fragment({ label = "Latest test run", text = "...", filetype = "markdown", source = "neotest", category = "runtime" })` stages a first-class `text_note` fragment without pretending the text came from a file.
