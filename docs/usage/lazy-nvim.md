# lazy.nvim Setup

This guide covers both a normal install from a Git remote and a local checkout for development or dogfooding.

## 1. Add the plugin spec

### Remote install

Add this to your plugin list to install from the public GitHub repository:

```lua
{
  "jaju/neovim-codex",
  dependencies = {
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("neovim_codex").setup({
      keymaps = {
        global_modes = { "n", "i", "x" }, -- let your chosen global Codex mappings work across common modes
        global = {
          chat = false, -- toggle the chat overlay globally
          threads = false, -- open the thread picker
          request = false, -- reopen the current approval or question
          workbench = false, -- toggle the workbench tray
          compose = false, -- open compose review
          capture_path = false, -- stage the current file path
          capture_selection = false, -- stage the current visual selection
          capture_diagnostic = false, -- stage the current diagnostic
        },
      },
    })
  end,
}
```

`client_info`, `experimental_api`, and `max_log_entries` are internal plugin defaults. Leave them alone unless you are working on the plugin itself.

### Local checkout

For local development, swap the repo string for a `dir = ...` entry that points at your checkout:

```lua
{
  dir = vim.fn.expand("~/src/neovim-codex"),
  name = "neovim-codex",
  dependencies = {
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("neovim_codex").setup({
      codex_cmd = { "codex", "app-server" }, -- only override this if you want a non-default Codex binary
    })
  end,
}
```

If you already use `render-markdown.nvim`, it will apply automatically because the transcript and composer are plain markdown buffers.

If you want global mappings immediately, add them here instead of leaving them disabled:

```lua
keymaps = {
  global = {
    chat = "<leader>ac",
    threads = "<leader>at",
    read_thread = "<leader>aT",
    interrupt = "<leader>ai",
  },
},
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

## 4. Smoke-check the environment

Run:

```vim
:checkhealth neovim_codex
:CodexSmoke
```

Expected behavior:

- `checkhealth neovim_codex` reports the environment, `nui.nvim`, and handshake viability
- `CodexSmoke` opens a report buffer and reports pass/fail

## 5. Start chatting

Run:

```vim
:CodexChat
```

Then:

1. write in the composer at the bottom of the overlay
2. send with `<C-s>` or `:CodexSend`
3. watch the transcript update above it
4. run `:CodexChat` again to hide the overlay

Useful commands while dogfooding:

```vim
:CodexThreadNew
:CodexThreads
:CodexThreadRead
:CodexEvents
:CodexStatus
```

## 6. Stop the process

Run:

```vim
:CodexStop
```

This requests shutdown of the managed `codex app-server` process.
