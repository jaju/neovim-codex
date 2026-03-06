# Layering

## Dependency Order

1. `lua/neovim_codex/core/jsonrpc.lua`
2. `lua/neovim_codex/core/store.lua`
3. `lua/neovim_codex/core/selectors.lua`
4. `lua/neovim_codex/core/client.lua`
5. `lua/neovim_codex/nvim/transport.lua`
6. `lua/neovim_codex/nvim/chat/document.lua`
7. `lua/neovim_codex/nvim/chat/render.lua`
8. `lua/neovim_codex/nvim/chat/composer.lua`
9. `lua/neovim_codex/nvim/chat/surface.lua`
10. `lua/neovim_codex/nvim/thread_renderer.lua`
11. `lua/neovim_codex/nvim/presentation.lua`
12. `lua/neovim_codex/nvim/chat.lua`
13. `lua/neovim_codex/init.lua`
14. `plugin/neovim_codex.lua`

The core layers must remain free of `vim` dependencies.

## Current Vertical Slice

The current usable slice now includes:

- spawn `codex app-server`
- perform `initialize`
- send `initialized`
- create, read, list, and resume threads
- start turns from a NeoVim markdown composer
- reconstruct streamed transcript state from `item/*` notifications and `item/agentMessage/delta`
- project raw app-server state into a semantic `ChatDocument`
- render that document into a markdown transcript inside a centered overlay

## Important Contract Notes

- the pure store models app-server truth for threads, turns, and items; the NeoVim layer renders only projections derived from that state
- `ChatDocument` is the seam between raw state and user-facing markdown; UI modules should not read store internals directly
- request/response methods mutate state only through the store, never by direct UI-side shadow state
- transcript and composer buffers intentionally use plain `markdown` so user filetype, treesitter, and markdown-renderer customization can apply naturally
- plugin-owned markdown buffers are distinguished through buffer variables, not custom filetypes
- optional app-server fields can arrive as `vim.NIL` through `vim.json.decode`, so rendering boundaries must treat null-like values explicitly
- request failures are not the same thing as transport failures and should not poison connection state
