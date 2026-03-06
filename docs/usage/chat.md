# Chat Workflow

This is the day-to-day user flow for the current plugin slice.

## Open the overlay

```vim
:CodexChat
```

This toggles a centered overlay with:

- a markdown transcript at the top
- a multiline markdown composer at the bottom

Run `:CodexChat` again to hide it.

## Send a turn

1. write a prompt in the composer
2. press `<C-s>` or run `:CodexSend`
3. keep using `<CR>` for newlines inside the draft

If no active thread exists yet, the plugin creates one first and then sends the turn.

If `<C-s>` is captured by your terminal, remap `keymaps.composer.send` or run `stty -ixon` in that shell.

## Thread commands

- `:CodexThreadNew` - start a fresh thread explicitly
- `:CodexThreads` - pick and resume a stored thread
- `:CodexThreadRead` - inspect a thread without resuming it
- `:CodexInterrupt` - interrupt the current turn

## Default overlay mappings

Transcript buffer:

- `q` - hide the overlay
- `i` - jump to the composer
- `[[` - previous turn
- `]]` - next turn
- `g?` - open help

Composer buffer:

- `<C-s>` - send the current draft from normal or insert mode
- `gS` - send the current draft from normal mode
- `q` in normal mode - hide the overlay
- `g?` in normal mode - open help
- `<CR>` - insert a newline

## Overriding mappings

Mappings are merged over defaults in `setup()`.

```lua
require("neovim_codex").setup({
  keymaps = {
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

Set any mapping to `false` to disable it.

## Markdown personalization

The transcript and composer are plain markdown buffers. The plugin marks them with:

- `b:neovim_codex = true`
- `b:neovim_codex_role = "transcript" | "composer" | "events"`
- `b:neovim_codex_thread_id = <thread-id>`

That means your own markdown ftplugin, treesitter config, render-markdown setup, or custom autocommands can target Codex buffers without special filetypes.

Example:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(args)
    if vim.b[args.buf].neovim_codex ~= true then
      return
    end
    vim.opt_local.wrap = true
    vim.opt_local.conceallevel = 2
  end,
})
```

## Known behavior

- a brand-new empty thread may not appear in `thread/list` yet
- a brand-new empty thread may not be resumable yet because the rollout is not materialized
- reading an empty thread with turns included can fail until the first user message is persisted; the plugin falls back to metadata-only reads for thread reports
- raw protocol and low-signal internal activity stay in `:CodexEvents`; the main transcript keeps those details compact by default
