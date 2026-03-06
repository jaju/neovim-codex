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
        version = "0.2.0-dev",
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

- `checkhealth neovim_codex` reports the environment and handshake viability
- `CodexSmoke` opens a report buffer and reports pass/fail

## 5. Start chatting

Run:

```vim
:CodexChat
```

Then:

1. type in the prompt buffer at the bottom of the chat split
2. press `<Enter>` to send
3. watch the transcript buffer update above it

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
