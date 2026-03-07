# Contracts Index

This subtree holds the integration contracts that `neovim-codex` intentionally depends on.

Use these docs when the question is not “what are we trying to build?” but “what are we willing to depend on, and how do we detect drift?”

## Load Order

When doing contract-sensitive work:

1. read `docs/vision/tenets.md`
2. read the relevant file in `docs/contracts/`
3. only then read `docs/architecture/*` or code

## Two Contract Families

- `contracts/codex-app-server/*`
  - the narrow app-server surface we depend on
  - the drift policy for that watched surface
- `contracts/neovim/*`
  - the stable internal abstractions that separate pure Lua from NeoVim-specific behavior

## Machine-Readable Counterpart

The docs in this tree have a checked counterpart at the repo root:

- `contracts/codex-app-server/watch-manifest.json`
- `contracts/codex-app-server/snapshots/`
- `scripts/check_codex_app_server_contracts.py`

Those artifacts exist so the human contract and the automated drift check stay aligned.
