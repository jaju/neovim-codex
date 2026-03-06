# Episode 0003: Dogfood-first development loop

Date: 2026-03-06

## Goal

Make the bootstrap slice usable from a real NeoVim instance so future work can be driven from the plugin itself.

## Delivered

- `:checkhealth neovim_codex`
- `:CodexSmoke`
- a headless test runner under `./scripts/test`
- development workflow docs describing how to reload and exercise the plugin from NeoVim

## Important Behavior

- stderr from `codex app-server` is recorded without automatically marking the connection as failed
- an expected stop no longer leaves stale error state behind
- the smoke report is available both for manual dogfooding and for headless integration testing

## Follow-on Impact

Future tasks can rely on:

- a stable smoke command for quick regression checks
- a stable headless test command
- a documented lazy.nvim reload loop for interactive development
