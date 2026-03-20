# neovim-codex

NeoVim-native Codex for developers who want AI help without leaving the editor or flattening everything into a terminal pane.

`neovim-codex` speaks the `codex app-server` protocol directly. It keeps thread, turn, request, workbench, and packet state inside NeoVim, and it treats code context as something you stage and compose deliberately rather than paste into a prompt box.

This is not Codex inside a floating terminal.

## Why This Exists

Generic AI chat tools are fine for question answering, but they are usually weak at staying close to code and weak at respecting how NeoVim users already work.

`neovim-codex` is built around a different idea:

- keep the conversation inside NeoVim
- keep code, diagnostics, and follow-up context close together
- use editor-native review, inspection, and navigation flows
- make AI interaction feel like part of editing, not a detour out of the editor

If you already think in buffers, motions, selections, diagnostics, and window layouts, this plugin is trying to meet you there.

## What You Get

- a rail-first markdown chat shell with a widened reader mode
- protocol-backed approvals and request flows that reopen safely
- thread and session controls for create, switch, fork, archive, rename, model, effort, approval policy, and collaboration mode
- a workbench and compose review flow for packet-backed follow-up context
- a pure Lua client and state core instead of a terminal wrapper

In practice, that means you can:

- start and talk to `codex app-server`
- create, resume, read, fork, rename, archive, and tune threads
- inspect activity without drowning the transcript in raw command noise
- stage code, diagnostics, and runtime notes into a workbench
- preview and send compiled packets with explicit `[[fN]]` fragment handles

## Screenshots

### Main chat overlay

![Main chat overlay](docs/assets/screenshots/chat-overlay-main.png)

A NeoVim-native Codex surface with a rail-first shell, explicit thread state, and a transcript that stays readable instead of turning into a log.

### Workbench and compose review

![Workbench and compose review](docs/assets/screenshots/workbench-compose-review.png)

Stage fragments from the code world, keep the useful ones, place `[[fN]]` handles where they matter, and review the packet before you send it.

### Thread and session controls

![Thread and session controls](docs/assets/screenshots/thread-session-controls.png)

Switch threads, fork from earlier turns, and adjust sticky runtime settings without leaving the editor.

## Requirements

- NeoVim `0.11+`
- local `codex` executable on `PATH`
- [`MunifTanjim/nui.nvim`](https://github.com/MunifTanjim/nui.nvim)

Optional but useful:

- [`MeanderingProgrammer/render-markdown.nvim`](https://github.com/MeanderingProgrammer/render-markdown.nvim) if you already use it for markdown buffers

Check prerequisites inside NeoVim:

```vim
:echo has('nvim-0.11')
:echo executable('codex')
```

Both commands should print `1`.

## Quick Start

If you want the shortest path to a first successful run:

1. install the plugin
2. confirm `codex` is available to NeoVim
3. run `:checkhealth neovim_codex`
4. run `:CodexSmoke`
5. open the overlay with `:CodexChat`
6. write a prompt in the composer and send it with `<C-s>` or `:CodexSend`

If you want the full setup walkthrough, use [docs/usage/lazy-nvim.md](docs/usage/lazy-nvim.md).

## Installation

### `lazy.nvim`

Add a plugin spec like this to your `lazy.nvim` setup:

```lua
{
  "jaju/neovim-codex",
  dependencies = {
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("neovim_codex").setup({
      keymaps = {
        global_fast_modes = { "n", "i", "x" },
        global_workflow_modes = { "n" },
        global = {
          chat = false, -- set a mapping like "<C-,>" to toggle the chat overlay
          request = "<F2>", -- reopen the active approval or question
          shortcuts = false,
          threads = false,
          workbench = false,
          compose = false,
          thread_settings = false,
          turn_steer = false,
          capture_path = false,
          capture_selection = false,
          capture_diagnostic = false,
        },
      },
    })
  end,
}
```

For local development or dogfooding, use a `dir = ...` spec instead. The full setup flow is documented in [docs/usage/lazy-nvim.md](docs/usage/lazy-nvim.md).

`client_info`, `experimental_api`, and `max_log_entries` are plugin-managed defaults. They are omitted on purpose because they are not meaningful day-to-day user settings.

## First Flow

From a normal NeoVim session:

```vim
:CodexChat
```

Then:

1. write your prompt in the composer at the bottom of the overlay
2. press `<C-s>` or run `:CodexSend`
3. watch the transcript stream above it
4. run `:CodexChat` again to hide the overlay

Useful commands for the common loop:

- `:CodexThreadNew` - create and activate a fresh thread
- `:CodexThreads` - pick and resume a stored thread
- `:CodexThreadRead` - inspect a stored thread without resuming it
- `:CodexRequest` - reopen the active approval or question request
- `:CodexInterrupt` - interrupt the running turn, if any
- `:CodexSteer [text]` - steer the currently running turn
- `:CodexShortcuts` - open the shortcut sheet for the current surface

## Workbench And Compose Review

The workbench is where the plugin stops being “chat in NeoVim” and starts becoming an editor-native context tool.

Use it when you want to gather structured context from the code world:

- `:CodexCapturePath` - stage the current file
- `:CodexCaptureSelection` - stage the current visual selection
- `:CodexCaptureDiagnostic` - stage the diagnostic under cursor
- `:CodexWorkbench` - open the staged-fragment tray
- `:CodexCompose` - open compose review for the active thread

The intended flow is:

1. capture context from code buffers
2. inspect the staged fragments in the workbench
3. remove or park stale fragments if needed
4. open compose review or send from chat
5. review the packet and send it

Chat text can still be copied manually when needed, but workbench capture is intentionally code-world first.

## Ambient Status

The plugin exposes a built-in statusline component if you want Codex state visible while staying in normal editing windows:

```vim
set statusline+=%{%v:lua.require('neovim_codex').statusline()%}
```

It reports:

- whether Codex is running, waiting, idle, stopped, or in error
- the active thread
- the pending request count and reopen hint
- the active workbench count

The default fast reopen shortcut for hidden request dialogs is `<F2>`.

## Why It Feels Different

This project is a good fit if you want:

- NeoVim to stay the center of gravity
- Codex to feel like part of the editor, not an external detour
- structured thread and workbench state instead of ad hoc prompt stuffing
- a transcript that supports reading and follow-up, not just logging
- protocol-backed approvals and file review flows instead of shell scraping

It is probably not the right tool if you want:

- a generic chat client
- a browser-first experience
- a terminal wrapper with minimal editor integration

## Docs

Start here after the landing page:

- [docs/usage/lazy-nvim.md](docs/usage/lazy-nvim.md) - installation and dogfood setup
- [docs/usage/chat.md](docs/usage/chat.md) - day-to-day chat, thread, request, and workbench flows
- [docs/usage/reference.md](docs/usage/reference.md) - command surface, keymaps, transcript rules, and configuration details
- [docs/vision/README.md](docs/vision/README.md) - where the product is trying to go
- [docs/contracts/README.md](docs/contracts/README.md) - the app-server and NeoVim boundaries this plugin tracks
- [docs/development/workflow.md](docs/development/workflow.md) - local development and verification loop

## Current Status

The current slice already supports the usable core loop:

- start and talk to `codex app-server`
- create, resume, read, fork, rename, archive, and tune threads
- inspect activity without drowning the main transcript in raw command noise
- stage code, diagnostics, and runtime notes into a workbench
- preview and send compiled packets with explicit fragment handles

It does not yet implement dynamic tools or language-specific adapter daemons, but the app-server-native chat/session/workbench loop is already in place.
