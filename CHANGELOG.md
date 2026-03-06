# Changelog

All notable changes to this project will be documented in this file.

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
