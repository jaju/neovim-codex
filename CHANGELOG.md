# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.4.0] - 2026-03-21

### Added
- A real side-rail chat shell plus an explicit centered overlay command, with both views sharing the same app-server-backed state.
- First-class thread/session controls: `:CodexThreadNewConfig`, `:CodexThreadSettings`, `:CodexThreadFork`, `:CodexThreadArchive`, `:CodexThreadUnarchive`, `:CodexThreadCompact`, and `:CodexSteer`.
- Thread-scoped request inboxes, a dedicated request reopen path, and a statusline component for turn state, pending requests, and workbench counts.
- Protocol-backed file-change review surfaces with per-file navigation and Vim-native diff tabs.
- A thread-local workbench model with parked fragments, compose review, packet preview, handle-based packet compilation, and first-class text-note fragments through `capture_text_fragment(...)`.
- Diagnostic capture under cursor through `:CodexCaptureDiagnostic`.
- `:CodexShortcuts` plus structured fast/workflow/surface shortcut lanes.
- `scripts/contracts-check`, `.envrc.example`, and expanded watched app-server schema snapshots for drift checking.

### Changed
- `:CodexChat` now opens and toggles the side rail by default, while `:CodexChatOverlay` opens the centered overlay explicitly.
- The transcript is now projected as semantic, markdown-first conversation output with foldable sections, compact activity summaries, and deeper inspection behind dedicated detail surfaces.
- Request routing now follows typed protocol families with safe fallbacks instead of assuming a single approval shape.
- Thread runtime settings are now explicit and sticky per thread, including model, reasoning effort, collaboration mode, and approval policy.
- Thread creation, forking, and settings flows now use async picker/input paths instead of blocking the UI.
- The README and docs are now organized around an app-server-native product pitch, with dense reference material moved into `docs/`.

### Fixed
- Store updates during streaming no longer deep-clone the full state tree on every event; the hot path now uses targeted structural sharing.
- Store-driven UI refreshes are now coalesced so long streaming responses do not fan out redundant redraw work.
- Chat footers and status surfaces now distinguish running turns from true pending-request waits more accurately.
- File edits now surface through explicit thread approval policy settings instead of silently depending on ambient backend defaults.
- Rail/overlay shell transitions, title rendering, and rail pane partitioning no longer leave stale shells behind or corrupt the editor layout.
- Thread pickers now preserve locally created threads in-session so fresh threads remain reachable before the backend list catches up.

## [0.3.0] - 2026-03-06

### Added
- `docs/contracts/` as a stable boundary tree for Codex app-server and NeoVim-side contracts.
- `contracts/codex-app-server/watch-manifest.json` and checked snapshots of the watched generated app-server TypeScript types.
- `scripts/check_codex_app_server_contracts.py` to detect drift against either a Codex source tree or the installed `codex` binary.
- `docs/vision/` as a stable design-memory tree with central tenets, workspace model, context-mobility, and composer-fragment vision docs.
- Centered overlay chat UI built on `nui.nvim` instead of the earlier split layout.
- A multiline markdown composer with explicit send via `:CodexSend`, `<C-s>`, or `gS`.
- Semantic `ChatDocument` projection and markdown renderer between raw app-server state and the chat UI.
- Protocol-first transcript mapping docs for app-server item surfaces and streaming rules.
- Buffer tagging for transcript/composer/event buffers so user markdown customization can target Codex buffers cleanly.
- Transcript heading highlight groups that can be overridden without changing the markdown buffer contract.
- Unit coverage for markdown chat projection, streamed protocol delta handling, the details inspector formatter, and the server-request state machine.
- A dedicated request viewer and `:CodexRequest` command for command approvals, file-change approvals, and tool `requestUserInput` flows.

### Changed
- `:CodexChat` now toggles the overlay instead of only opening a side split.
- The main transcript is now conversation-first markdown with outline-friendly turn headings and compact activity summaries instead of raw item dumps.
- Command projection now uses app-server `commandActions` and typed item fields instead of shell-string heuristics.
- The pure Lua store now folds streamed plan, reasoning, and command-output deltas back into the corresponding typed items.
- Hiding the overlay now dismisses the outer container cleanly instead of leaving an empty frame behind.
- The thread report renderer now uses the same markdown projection path as the live chat UI.
- Health checks now verify `nui.nvim` in addition to the existing app-server smoke path.
- Verbose command, tool, and reasoning detail now lives behind `:CodexInspect` instead of occupying the main transcript by default.
- Events, reports, transcript inspection, and blocking request prompts now share a stacked popup layer instead of opening as unrelated windows or hidden splits.
- Command approval, file-change approval, and tool-question handling now follow the locked app-server request contracts instead of staying as planned-only UX.
- The chat overlay now avoids redraw churn for store events that do not change the rendered conversation, reducing terminal flicker while Codex is streaming background state.
- Legacy chat config keys are normalized into the new overlay/composer configuration shape.

## [0.2.0] - 2026-03-06

### Added
- `:CodexChat` with a transcript buffer and a prompt buffer for in-editor Codex conversations.
- Thread lifecycle support for `thread/start`, `thread/list`, `thread/read`, and `thread/resume`.
- Turn lifecycle support for `turn/start` plus streamed `item/agentMessage/delta` updates.
- `:CodexThreadNew`, `:CodexThreads`, `:CodexThreadRead`, and `:CodexInterrupt`.
- A merged keymap configuration surface so defaults can be overridden or disabled cleanly.
- Headless integration coverage for the command surface, chat buffer creation, and thread lifecycle round-trips.

### Changed
- Status reporting now includes the active thread id when one is selected.
- Event presentation now includes thread counts and the active thread.
- Read/report flows fall back when `thread/read includeTurns=true` is unavailable for an empty thread.
- JSON-RPC request errors no longer poison the connection status as transport failures.

## [0.1.2] - 2026-03-06

### Added
- `:CodexSmoke` for an in-editor smoke run of the bootstrap slice.
- `:checkhealth neovim_codex` health reporting for prerequisites and handshake viability.
- Headless unit and integration test runners under `tests/` plus `./scripts/test`.
- Development workflow documentation for driving iteration from a real NeoVim session.

### Changed
- stderr from `codex app-server` is now logged without automatically forcing the connection into an error state.
- expected process shutdown now clears stale error state instead of leaving the last stop reason as an error.

## [0.1.1] - 2026-03-06

### Added
- Repository workflow scaffolding for local `bd` task tracking.
- A repo-specific `AGENTS.md` aligned with the required task lifecycle.
- An episodic note recording the initial beads roadmap and local tracker setup.

## [0.1.0] - 2026-03-06

### Added
- Initial repository skeleton for a NeoVim-hosted `codex app-server` client.
- Pure Lua JSON-RPC line decoder and client orchestration core.
- Pure Lua connection state store with reducer and subscriptions.
- NeoVim `uv.spawn` transport for `codex app-server`.
- User commands for starting, stopping, querying status, and opening a protocol event log.
- Documentation structure under `docs/` for architecture, usage, and episodic notes.
- `lazy.nvim` installation and smoke-test instructions for the current vertical slice.
