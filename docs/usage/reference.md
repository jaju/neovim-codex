# Reference

This page holds the denser user-facing reference material that no longer belongs on the landing README.

## Commands

Core commands:

- `:CodexStart` - start `codex app-server` and complete the initialize handshake
- `:CodexStop` - stop the running app-server process
- `:CodexStatus` - print current connection state and active thread id
- `:CodexSmoke` - run the current smoke checks and open a report buffer
- `:CodexChat` - open or focus the side rail
- `:CodexChatRail` - open the narrow side-rail shell explicitly
- `:CodexChatOverlay` - open the centered overlay explicitly
- `:CodexChatReader` - backward-compatible alias for `:CodexChatOverlay`
- `:CodexSend` - send the current composer contents, or open compose review if the workbench is non-empty
- `:CodexInspect` - push a details viewer for the selected transcript block
- `:CodexEvents` - open the protocol event log in the stacked viewer layer
- `:checkhealth neovim_codex` - verify NeoVim version, `codex` availability, `nui.nvim`, and handshake viability

Thread controls:

- `:CodexThreadNew` - create and activate a fresh thread
- `:CodexThreadNewConfig` - create a thread with runtime settings like model, effort, approval policy, collaboration mode, name, and ephemeral state
- `:CodexThreads` - pick and resume a stored thread
- `:CodexThreadRead [thread-id]` - inspect a stored thread in the history pager without resuming it
- `:CodexHistory [thread-id]` - open the active thread history pager, or inspect a specific thread by id
- `:CodexThreadRename [name]` - rename the active thread, or prompt asynchronously for a name
- `:CodexThreadFork [thread-id]` - fork from a chosen turn in the active thread, or the supplied thread id
- `:CodexThreadArchive [thread-id]` - archive the active thread, or pick/archive another thread
- `:CodexThreadUnarchive [thread-id]` - restore an archived thread, or pick one from archived threads
- `:CodexThreadSettings [thread-id]` - open the editable thread settings sheet
- `:CodexThreadCompact [thread-id]` - start manual history compaction for the active thread, or pick one
- `:CodexInterrupt` - interrupt the running turn, if any
- `:CodexSteer [text]` - steer the currently running turn, or use the current chat draft when the shell is open
- `:CodexRequest` - reopen the active approval or question request if one is pending
- `:CodexReview [request-key]` - open the current pending file-change review, or reopen a specific pending file-change request by key
- `:CodexShortcuts` - open the Codex shortcut sheet for the current surface

Workbench and compose commands:

- `:CodexWorkbench` - toggle the thread-local workbench tray
- `:CodexCompose` - open compose review for the current thread
- `:CodexCapturePath` - stage the current file as a `path_ref` fragment
- `:CodexCaptureSelection` - stage the current visual selection as a `code_range` fragment
- `:CodexCaptureDiagnostic` - stage the current diagnostic under cursor as a `diagnostic` fragment
- Lua API: `require("neovim_codex").capture_text_fragment({ label = "Latest test run", text = "...", filetype = "markdown", source = "neotest", category = "runtime" })` stages a first-class `text_note` fragment for runtime context, tool output, logs, or notes

## Keymaps

Global mappings are mostly disabled by default. The one fast-path exception is request reopen on `<F2>`, so hidden approvals or questions are always one movement away.

Fast open/reopen actions use `keymaps.global_fast_modes`; workflow actions use `keymaps.global_workflow_modes`. If you only set the older `keymaps.global_modes`, it still works as the fallback for both lanes.

Buffer-local mappings exist only inside plugin-owned Codex buffers. Use `g?` or `<F1>` inside a Codex surface to reopen the current shortcut sheet, which is grouped into `This surface`, `Global fast`, and `Global workflow`.

Transcript buffer defaults:

- `q` - close the current chat shell
- `gr` - reopen the active thread inbox
- `gR` - switch between the side rail and the centered overlay
- `gh` - open the active thread history pager
- `i` - focus the composer
- insert-like keys in the transcript (`a`, `A`, `i`, `I`, `o`, `O`, `R`) also jump to the composer instead of entering insert mode in the read-only transcript
- `<C-w>w` - switch between transcript and composer without leaving the current shell
- `<CR>` - push the selected transcript block onto the viewer stack
- `[[` - jump to the previous turn boundary
- `]]` - jump to the next turn boundary
- `g?` or `<F1>` - open the Codex shortcut sheet for the current surface

Composer buffer defaults:

- `<C-s>` - send the current draft from normal or insert mode
- `gS` in normal mode - send the current draft
- `gT` in normal mode - steer the running turn with the current draft
- `<C-w>w` in normal mode - switch back to the transcript
- `q` in normal mode - close the current chat shell
- `gr` in normal mode - reopen the active thread inbox
- `gh` in normal mode - open the active thread history pager
- `gs` in normal mode - open the active thread settings
- `gR` in normal mode - switch between the side rail and the centered overlay
- `g?` or `<F1>` in normal mode - open the Codex shortcut sheet for the current surface
- `<CR>` - insert a newline

Pending request viewer defaults:

- the viewer is read-only and opens in normal mode
- `<CR>` - resolve the current request
- `a` - approve once when that decision exists
- `s` - approve for session when that decision exists
- `d` - decline
- `c` - cancel
- `g?` or `<F1>` - open the Codex shortcut sheet for the current surface
- `q` or `<Esc>` - hide the request viewer without resolving the request

Workbench tray defaults:

- `<CR>` - inspect the selected fragment
- `dd` - remove the selected fragment
- `D` - clear the active thread workbench
- `o` - open compose review
- `i` - open compose review and insert the selected fragment handle
- `p` - park the selected active fragment
- `u` - unpark the selected parked fragment
- `P` - open packet preview
- `g?` or `<F1>` - open the shortcut sheet for the current surface
- `q` - close the tray

Compose review defaults:

- `<C-s>` - send the current packet from normal or insert mode
- `gS` - send the current packet from normal mode
- `<Tab>` - focus the fragment list from the message editor
- `i` - insert the selected fragment handle into the packet template
- `q` - close compose review

History pager defaults:

- `[h` - move to the previous history chunk
- `]h` - move to the next history chunk
- `[[` - move to the previous turn in the current chunk
- `]]` - move to the next turn in the current chunk
- `<CR>` - inspect the current history block
- `o` - open the current turn in a focused history view
- `g?` or `<F1>` - open the Codex shortcut sheet for the current surface
- `q` or `<Esc>` - close the history pager

All mappings are configurable through `setup()` and merged over defaults. Set a mapping to `false` to disable it. Use `keymaps.global_fast_modes = { "n", "i", "x" }` to keep fast global Codex actions available without changing modes, and `keymaps.global_workflow_modes = { "n" }` to keep workflow actions normal-mode only.

Example:

```lua
require("neovim_codex").setup({
  keymaps = {
    global_fast_modes = { "n", "i", "x" },
    global_workflow_modes = { "n" },
    global = {
      chat = "<C-,>",
      chat_overlay = "<C-.>",
      request = "<F2>",
      shortcuts = "<F1>",
      new_thread = "<leader>cn",
      new_thread_config = "<leader>cN",
      threads = "<leader>ct",
      read_thread = "<leader>cT",
      thread_settings = "<leader>cs",
      thread_unarchive = "<leader>cu",
      thread_compact = "<leader>ck",
      turn_steer = "<leader>cS",
      workbench = "<leader>cw",
      compose = "<leader>cp",
      capture_path = "<leader>cf",
      capture_selection = "<leader>cx",
      capture_diagnostic = "<leader>cd",
    },
  },
})
```

## Protocol-First Transcript

The transcript is derived from app-server protocol types, not from shell-string heuristics.

The active chat shell is also bounded by design. It keeps a recent working set instead of trying to render the full thread indefinitely. When multiple compaction boundaries are known, the visible chat prefers the penultimate compaction boundary; otherwise it falls back to a recent tail budget and trims further if the active render line budget is exceeded.

Blocking app-server requests are protocol-first too. Command approvals, file-change approvals, and tool questions do not render inline as transcript content. They open in a stacked request viewer in normal mode, use your configured `vim.ui.select` for option choices, and open a focused stacked text-answer popup for free-form responses.

Use `:CodexRequest` or `<F2>` to reopen the current request if you close it before responding. Use `:CodexReview` or the request-local `o` mapping to inspect a structured file-change review. Inside that review, `]f` and `[f` move between changed files and `o` opens a dedicated per-file diff viewer before you decide.

Examples:

- successful `commandExecution` items with typed `commandActions` like `read`, `listFiles`, or `search` are compacted into single-line activity summaries
- in-progress execution stays in the footer instead of occupying transcript space
- failed or unknown commands stay compact in the transcript but open into a details inspector on demand
- typed item families such as file changes, tool calls, review mode, and context compaction each map to their own UI surface with their raw protocol preserved

For the design contract, see [docs/architecture/protocol-first.md](../architecture/protocol-first.md).

## Markdown Buffer Contract

The chat transcript and composer are plain markdown buffers with normal NeoVim buffer contracts:

- `buftype=nofile`
- `bufhidden=hide`
- `swapfile=false`
- `filetype=markdown`

The plugin tags its buffers with buffer variables so your own markdown autocommands or renderers can target them cleanly:

- `b:neovim_codex = true`
- `b:neovim_codex_role = "transcript" | "composer" | "details" | "events" | "workbench" | "compose_review_message" | "compose_review_fragments"`
- `b:neovim_codex_thread_id = <thread-id>`

Foldable secondary sections are projected as markdown headings with attribute markers such as `### Command {.foldable}`, so your own markdown tooling can decide how to treat them.

The overlay also exposes highlight groups for transcript headings:

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

## Ambient Status

Expose the built-in statusline component in your own statusline:

```vim
set statusline+=%{%v:lua.require('neovim_codex').statusline()%}
```

It shows the current Codex state (`RUN`, `WAIT`, `IDLE`, `ERR`, `OFF`), the active thread, any pending request count plus reopen hint, and the active workbench count.

## Configuration Notes

Most users only need `keymaps.global`.

Use `codex_cmd` only if `codex` is not on your `PATH` or you want to point at a specific binary. The `client_info`, `experimental_api`, and log-limit fields are plugin-owned defaults and are intentionally left out of normal user config examples.

Transcript scale controls live under:

- `ui.chat.history.max_turns`
- `ui.chat.history.max_lines`
- `ui.chat.history.prefer_penultimate_compaction`
- `ui.history_pager.max_turns_per_chunk`
- `ui.history_pager.max_lines_per_chunk`

The older `ui.chat.width`, `ui.chat.prompt_height`, `ui.chat.wrap`, and `keymaps.prompt` values are normalized into the new layout/composer shape so older local configs do not break immediately.

## Known Behavior

- a fresh thread that has not accumulated turns can still be missing from the persisted `thread/list` view after a restart, depending on backend persistence behavior; within the current NeoVim session the picker merges locally known threads so they remain reachable
- a brand-new empty thread may not be resumable yet because the rollout is not materialized
- reading an empty thread with turns included can fail until the first user message is persisted; the plugin falls back to metadata-only reads for thread reports and history opens
- history paging is render-efficient but not yet payload-efficient for unloaded threads because the current app-server contract still returns full turns for `thread/read includeTurns=true`
- raw protocol and low-signal internal activity stay in `:CodexEvents`; the main transcript stays terse and uses `:CodexInspect` for verbose detail
