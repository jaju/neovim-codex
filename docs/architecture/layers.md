# Layering

## Dependency Order

1. `lua/neovim_codex/core/jsonrpc.lua`
2. `lua/neovim_codex/core/store.lua`
3. `lua/neovim_codex/core/selectors.lua`
4. `lua/neovim_codex/core/client.lua`
5. `lua/neovim_codex/nvim/transport.lua`
6. `lua/neovim_codex/nvim/thread_renderer.lua`
7. `lua/neovim_codex/nvim/presentation.lua`
8. `lua/neovim_codex/nvim/chat.lua`
9. `lua/neovim_codex/init.lua`
10. `plugin/neovim_codex.lua`

The core layers must remain free of `vim` dependencies.

## Current Vertical Slice

The current usable slice now includes:

- spawn `codex app-server`
- perform `initialize`
- send `initialized`
- create, read, list, and resume threads
- start turns from a NeoVim prompt buffer
- reconstruct streamed transcript state from `item/*` notifications and `item/agentMessage/delta`
- render a chat transcript and a thread report in NeoVim

## Important Contract Notes

- the pure store models app-server truth for threads, turns, and items; the NeoVim layer renders selectors derived from that state
- request/response methods mutate state only through the store, never by direct UI-side shadow state
- the chat UI is intentionally minimal and conservative; richer widgets belong to later tasks
- optional app-server fields can arrive as `vim.NIL` through `vim.json.decode`, so rendering boundaries must treat null-like values explicitly
- request failures are not the same thing as transport failures and should not poison connection state
