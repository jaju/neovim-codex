# Episode 0004: First in-editor chat loop

Date: 2026-03-06

## Goal

Land the first usable Codex conversation loop inside NeoVim itself.

## Delivered

- thread lifecycle support:
  - `thread/start`
  - `thread/list`
  - `thread/read`
  - `thread/resume`
- turn lifecycle support for `turn/start`
- transcript reconstruction from live `item/*` notifications and `item/agentMessage/delta`
- a split chat UI with:
  - transcript buffer
  - prompt buffer
- command surface:
  - `:CodexChat`
  - `:CodexThreadNew`
  - `:CodexThreads`
  - `:CodexThreadRead`
  - `:CodexInterrupt`
- merged keymap configuration so defaults remain user-overridable

## Important Constraints Learned

- `thread/list` does not reliably include a freshly created empty thread yet
- an empty thread may not be resumable until the first user turn is persisted
- `thread/read includeTurns=true` can fail before that first persisted user turn exists
- request failures must not be treated as transport failures in client state
- app-server payloads decoded through `vim.json` can carry `vim.NIL` for optional fields and must be normalized at rendering boundaries

## Why This Matters

This is the first milestone where plugin development can be driven from NeoVim itself instead of from headless smoke checks alone.
