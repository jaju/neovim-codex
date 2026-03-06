# neovim-codex

A NeoVim-hosted client for `codex app-server`.

This repository is built in layers:

- pure Lua communication core with no `vim` dependency
- pure Lua state store and reducer
- semantic chat-document projection between raw app-server state and UI rendering
- NeoVim host bridge for process management and UI wiring
- incremental delivery, with every milestone remaining usable

## Current Status

This repository now implements the first usable in-editor Codex conversation loop with a markdown-native overlay:

- starts `codex app-server`
- performs the `initialize` / `initialized` handshake
- tracks connection, thread, turn, and item state in pure Lua
- opens a centered overlay inside NeoVim with:
  - a markdown transcript buffer
  - a multiline markdown composer buffer
- supports `thread/start`, `thread/list`, `thread/read`, and `thread/resume`
- supports `turn/start` and streamed `item/agentMessage/delta` updates
- exposes health and smoke checks through `:checkhealth neovim_codex` and `:CodexSmoke`

It does **not** yet implement approvals, request-user-input flows, rewind/fork UI, or dynamic tools.

## Requirements

- NeoVim `0.11+`
- local `codex` executable on `PATH`
- [`MunifTanjim/nui.nvim`](https://github.com/MunifTanjim/nui.nvim) for the overlay layout

Optional but useful:

- [`MeanderingProgrammer/render-markdown.nvim`](https://github.com/MeanderingProgrammer/render-markdown.nvim) if you already use it for markdown buffers

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
  dependencies = {
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("neovim_codex").setup({
      codex_cmd = { "codex", "app-server" },
      client_info = {
        name = "neovim_codex",
        title = "NeoVim Codex",
        version = "0.3.0-dev",
      },
      experimental_api = true,
      max_log_entries = 400,
      keymaps = {
        global = {
          chat = false,
          new_thread = false,
          threads = false,
          read_thread = false,
          interrupt = false,
        },
      },
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

## First Chat Flow

From your normal NeoVim session:

```vim
:CodexChat
```

Then:

1. write your prompt in the composer at the bottom of the overlay
2. press `<C-s>` or run `:CodexSend`
3. watch the transcript stream above it
4. run `:CodexChat` again to hide the overlay

Useful thread commands:

- `:CodexThreadNew` - create and activate a fresh thread
- `:CodexThreads` - pick and resume a stored thread
- `:CodexThreadRead` - inspect a stored thread without resuming it
- `:CodexInterrupt` - interrupt the running turn, if any

## Commands

- `:CodexStart` - start `codex app-server` and complete the initialize handshake
- `:CodexStop` - stop the running app-server process
- `:CodexStatus` - print current connection state and active thread id
- `:CodexEvents` - open a scratch buffer with the protocol event log
- `:CodexSmoke` - run the current smoke checks and open a report buffer
- `:CodexChat` - toggle the Codex overlay
- `:CodexSend` - send the current composer contents
- `:CodexThreadNew` - create a new thread and activate it
- `:CodexThreads` - pick and resume a stored thread
- `:CodexThreadRead [thread-id]` - read a thread into a report buffer
- `:CodexInterrupt` - interrupt the active turn
- `:checkhealth neovim_codex` - verify NeoVim version, `codex` availability, `nui.nvim`, and handshake viability

## Keymaps

Global mappings are disabled by default. Buffer-local mappings exist only inside plugin-owned chat buffers.

Transcript buffer defaults:

- `q` - hide the overlay
- `i` - focus the composer
- `[[` - jump to the previous turn boundary
- `]]` - jump to the next turn boundary
- `g?` - open help for the chat buffer

Composer buffer defaults:

- `<C-s>` - send the current draft from normal or insert mode
- `gS` - send the current draft from normal mode
- `q` in normal mode - hide the overlay
- `g?` in normal mode - open help for the chat buffer
- `<CR>` - insert a newline

All mappings are configurable through `setup()` and merged over defaults. Set a mapping to `false` to disable it.

```lua
require("neovim_codex").setup({
  keymaps = {
    global = {
      chat = "<leader>ac",
      threads = "<leader>at",
      read_thread = "<leader>aT",
    },
    transcript = {
      focus_composer = "<CR>",
      next_turn = "]c",
      prev_turn = "[c",
    },
    composer = {
      send = "<leader>as",
      send_normal = false,
    },
  },
})
```

If `<C-s>` is captured by terminal flow control, either run `stty -ixon` for that shell or remap `keymaps.composer.send`.

## Markdown Buffer Contract

The overlay transcript and composer are plain markdown buffers with normal NeoVim buffer contracts:

- `buftype=nofile`
- `bufhidden=hide`
- `swapfile=false`
- `filetype=markdown`

The plugin tags its buffers with buffer variables so your own markdown autocommands or renderers can target them cleanly:

- `b:neovim_codex = true`
- `b:neovim_codex_role = "transcript" | "composer" | "events"`
- `b:neovim_codex_thread_id = <thread-id>`

That means existing markdown treesitter, conceal, render-markdown, and ftplugin customization can apply naturally inside the overlay.

## Current Limitations

- approval and request-user-input flows are not implemented yet; that arrives in task 4
- a newly created thread without a persisted user turn may not appear in `thread/list` yet and may not be resumable from storage yet
- `thread/read` with `includeTurns=true` can fail for an empty thread before the first user message is persisted; the plugin falls back to a metadata-only read in that case
- the transcript currently keeps activity summaries compact by default; raw protocol remains in `:CodexEvents`

## Development Workflow

- Run the automated checks with `./scripts/test`
- Use the in-editor dogfood loop:
  1. `:Lazy reload neovim-codex`
  2. `:checkhealth neovim_codex`
  3. `:CodexChat`
  4. `:CodexThreadNew`
  5. write a short prompt in the composer and press `<C-s>`
  6. inspect `:CodexEvents` if something looks wrong

A fuller workflow note lives in [`docs/development/workflow.md`](docs/development/workflow.md).

## Configuration

```lua
require("neovim_codex").setup({
  codex_cmd = { "codex", "app-server" },
  client_info = {
    name = "neovim_codex",
    title = "NeoVim Codex",
    version = "0.3.0-dev",
  },
  experimental_api = true,
  max_log_entries = 400,
  ui = {
    chat = {
      layout = {
        width = 0.88,
        height = 0.84,
        border = "rounded",
      },
      transcript = {
        wrap = true,
      },
      composer = {
        min_height = 6,
        max_height = 12,
        default_height = 8,
        wrap = true,
      },
    },
  },
  keymaps = {
    global = {
      chat = false,
      new_thread = false,
      threads = false,
      read_thread = false,
      interrupt = false,
    },
    transcript = {
      close = "q",
      focus_composer = "i",
      next_turn = "]]",
      prev_turn = "[[",
      help = "g?",
    },
    composer = {
      send = "<C-s>",
      send_normal = "gS",
      close = "q",
      help = "g?",
    },
  },
})
```

The older `ui.chat.width`, `ui.chat.prompt_height`, `ui.chat.wrap`, and `keymaps.prompt` values are normalized into the new layout/composer shape so your local config does not break immediately.

## Repository Layout

- `lua/neovim_codex/core/` - pure Lua protocol, selectors, and state logic
- `lua/neovim_codex/nvim/chat/` - semantic document projection, overlay surface, and composer modules
- `lua/neovim_codex/nvim/` - NeoVim runtime bridge and presentation helpers
- `plugin/` - user command registration
- `docs/architecture/` - stable architecture notes
- `docs/development/` - local development and dogfooding workflow
- `docs/episodes/` - episodic progress notes for future context injection
- `docs/usage/` - installation and usage flows
- `tests/` - headless unit and integration test runners
- `scripts/` - local development commands

## Next Steps

1. add thread history UI with server-backed fork and rollback
2. implement approval and request-user-input handling
3. add explicit prompt composition from buffer, LSP, and tree-sitter context
4. add dynamic tools and the first TypeScript adapter daemon
