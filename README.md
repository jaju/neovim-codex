# neovim-codex

A NeoVim-hosted client for `codex app-server`.

This repository starts from a clean architecture:

- pure Lua communication core with no `vim` dependency
- pure Lua state store and reducer
- NeoVim host bridge for process management and UI wiring
- incremental delivery, with every milestone remaining usable

## Current Status

This repository currently implements the first usable slice:

- starts `codex app-server`
- performs the `initialize` / `initialized` handshake
- tracks connection state in a pure Lua store
- exposes connection diagnostics through `:checkhealth neovim_codex`
- exposes `:CodexSmoke` for an in-editor smoke run
- exposes `:CodexStart`, `:CodexStop`, `:CodexStatus`, and `:CodexEvents`

It does **not** yet implement thread or turn management.

## Requirements

- NeoVim `0.11+`
- local `codex` executable on `PATH`

Check prerequisites inside NeoVim:

```vim
:echo has('nvim-0.11')
:echo executable('codex')
```

Both commands should print `1`.

## Installation

### lazy.nvim

Add this plugin spec to your `lazy.nvim` setup:

```lua
{
  dir = "/Users/jaju/github/neovim-codex",
  name = "neovim-codex",
  config = function()
    require("neovim_codex").setup({
      codex_cmd = { "codex", "app-server" },
      client_info = {
        name = "neovim_codex",
        title = "NeoVim Codex",
        version = "0.1.0-dev",
      },
      experimental_api = true,
      max_log_entries = 400,
    })
  end,
}
```

Then inside NeoVim:

```vim
:Lazy sync
:Lazy load neovim-codex
:checkhealth neovim_codex
:CodexSmoke
```

A more explicit step-by-step guide lives in [`docs/usage/lazy-nvim.md`](docs/usage/lazy-nvim.md).

## Commands

- `:CodexStart` - start `codex app-server` and complete the handshake
- `:CodexStop` - stop the running app-server process
- `:CodexStatus` - print current connection state
- `:CodexEvents` - open a scratch buffer with the protocol event log
- `:CodexSmoke` - run the current smoke checks and open a report buffer
- `:checkhealth neovim_codex` - verify NeoVim version, `codex` availability, and handshake viability

## Development Workflow

- Run the automated checks with `./scripts/test`
- Use the in-editor dogfood loop:
  1. `:Lazy reload neovim-codex`
  2. `:checkhealth neovim_codex`
  3. `:CodexSmoke`
  4. `:CodexEvents`

A fuller workflow note lives in [`docs/development/workflow.md`](docs/development/workflow.md).

## Configuration

```lua
require("neovim_codex").setup({
  codex_cmd = { "codex", "app-server" },
  client_info = {
    name = "neovim_codex",
    title = "NeoVim Codex",
    version = "0.1.0-dev",
  },
  experimental_api = true,
  max_log_entries = 400,
})
```

## Repository Layout

- `lua/neovim_codex/core/` - pure Lua protocol and state logic
- `lua/neovim_codex/nvim/` - NeoVim runtime bridge and presentation
- `plugin/` - user command registration
- `docs/architecture/` - stable architecture notes
- `docs/development/` - local development and dogfooding workflow
- `docs/episodes/` - episodic progress notes for future context injection
- `docs/usage/` - installation and usage flows
- `tests/` - headless unit and integration test runners
- `scripts/` - local development commands

## Next Steps

1. add thread start/resume/list/read support
2. introduce a real thread and turn state machine
3. add approvals and request-user-input handling
4. add prompt composition from buffer, LSP, and tree-sitter context
5. add dynamic tools and the first TypeScript adapter daemon
