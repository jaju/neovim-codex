# Chat Workflow

This is the day-to-day user flow for the current plugin slice.

## Open the chat

```vim
:CodexChat
```

This opens:

- a transcript buffer on the right
- a prompt buffer below it

## Send a turn

1. type a prompt in the prompt buffer
2. press `<Enter>`

If no active thread exists yet, the plugin creates one first and then sends the turn.

## Thread commands

- `:CodexThreadNew` - start a fresh thread explicitly
- `:CodexThreads` - pick and resume a stored thread
- `:CodexThreadRead` - inspect a thread without resuming it
- `:CodexInterrupt` - interrupt the current turn

## Default chat-buffer mappings

Transcript buffer:

- `q` - close the chat split
- `i` - jump to the prompt buffer
- `[[` - previous turn
- `]]` - next turn
- `g?` - open help

Prompt buffer:

- `<Enter>` - submit the prompt
- `q` in normal mode - close the chat split
- `g?` in normal mode - open help

## Overriding mappings

Mappings are merged over defaults in `setup()`.

```lua
require("neovim_codex").setup({
  keymaps = {
    transcript = {
      focus_prompt = "<CR>",
      next_turn = "]c",
      prev_turn = "[c",
    },
    prompt = {
      close = false,
    },
  },
})
```

Set any mapping to `false` to disable it.

## Known behavior

- a brand-new empty thread may not appear in `thread/list` yet
- a brand-new empty thread may not be resumable yet because the rollout is not materialized
- reading an empty thread with turns included can fail until the first user message is persisted; the plugin falls back to metadata-only reads for thread reports
