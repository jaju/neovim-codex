# lazy.nvim Setup

This guide installs the current local checkout of `neovim-codex` into an existing `lazy.nvim` setup.

## 1. Add the plugin spec

Add this to your plugin list:

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

## 2. Verify prerequisites

Inside NeoVim:

```vim
:echo has('nvim-0.11')
:echo executable('codex')
```

Expected result:

- both commands print `1`

If `executable('codex')` prints `0`, make sure the `codex` binary is on the PATH seen by NeoVim.

## 3. Install and load

Inside NeoVim:

```vim
:Lazy sync
:Lazy load neovim-codex
```

If the plugin is already loaded and you are iterating on the code locally, reload it with:

```vim
:Lazy reload neovim-codex
```

## 4. Exercise the current vertical slice

Run:

```vim
:checkhealth neovim_codex
:CodexSmoke
:CodexStart
:CodexStatus
:CodexEvents
```

Expected behavior:

- `checkhealth neovim_codex` reports the environment and handshake viability
- `CodexSmoke` opens a report buffer and reports pass/fail
- `CodexStart` notifies that the app-server started, unless it is already ready
- `CodexStatus` reports `status=ready`
- `CodexEvents` opens a scratch buffer showing outgoing `initialize`, incoming response, and the `initialized` notification

## 5. Stop the process

Run:

```vim
:CodexStop
```

This requests shutdown of the managed `codex app-server` process.
