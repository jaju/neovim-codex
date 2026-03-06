# Development Workflow

This repository is meant to be dogfooded from a real NeoVim instance.

## Automated checks

From the repository root:

```bash
./scripts/test
```

This runs:

1. pure Lua unit checks for the JSON-RPC decoder and state store
2. a headless NeoVim integration smoke run that loads the plugin and validates the app-server handshake

## Dogfood loop inside NeoVim

Use this when iterating on the plugin from your normal editor session.

```vim
:Lazy reload neovim-codex
:checkhealth neovim_codex
:CodexSmoke
:CodexEvents
```

Recommended flow:

1. edit code in the local checkout
2. `:Lazy reload neovim-codex`
3. `:checkhealth neovim_codex`
4. `:CodexSmoke`
5. inspect protocol traffic in `:CodexEvents`

## Current test scope

The current workflow validates only the connection/bootstrap slice:

- plugin load
- app-server process startup
- initialize/initialized handshake
- status reporting
- smoke report generation

It does not yet validate threads, turns, approvals, or dynamic tools.
