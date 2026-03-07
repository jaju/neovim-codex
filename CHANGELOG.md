# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- `.envrc.example` to document the expected local `CODEX_REPO_ROOT` setup for contract drift checks.
- The first thread-local semantic-composition slice: pure-Lua workbench state, a workbench tray, a compose-review overlay, and the initial fragment capture flows.
- `lua/neovim_codex/core/packet.lua` as the pure-Lua outbound packet renderer that folds staged fragments into the final app-server `turn/start` input.
- `docs/vision/workbench-model.md`, `docs/contracts/neovim/workbench-packet.md`, and `docs/episodes/0011-workbench-packet-contract.md` to lock the next semantic-composition slice around thread-local workbench state and outbound packet assembly.
- `scripts/contracts-check` as the stable entrypoint for app-server contract drift checks.
- Agent-facing repository entry points in `AGENTS.md` so protocol-contract questions start from the docs index and contract docs instead of code spelunking.

### Changed
- `scripts/check_codex_app_server_contracts.py` now resolves the Codex source-of-truth checkout from `--codex-repo` or `CODEX_REPO_ROOT` before falling back to installed-binary generation.
- `:CodexSend` now routes through compose review whenever the active thread workbench contains staged fragments.
- Status lines, chat footers, widget titles, and commands now consistently use the terminology `fragment`, `workbench`, `packet`, and `compose review`.
- Vision and NeoVim contract docs now describe `fragment -> workbench -> packet` as the next implementation boundary, including the workbench tray and compose-review UI surfaces.
- Vision and contract docs now record the next accepted workbench direction: keep chat useful without workbench complexity, prefer code-world capture over transcript capture, and move from append-all packet assembly to inline fragment-handle expansion at send time.
- `./scripts/test` now runs the contract drift check automatically when `CODEX_REPO_ROOT` is present in the environment.
- Contract and development docs now route protocol-contract work through the configured Codex checkout and the `./scripts/contracts-check` wrapper.

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
