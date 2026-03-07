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
9. `lua/neovim_codex/nvim/viewer_stack.lua`
10. `lua/neovim_codex/nvim/chat/details.lua`
11. `lua/neovim_codex/nvim/chat/surface.lua`
12. `lua/neovim_codex/nvim/thread_renderer.lua`
13. `lua/neovim_codex/nvim/presentation.lua`
14. `lua/neovim_codex/nvim/chat.lua`
15. `lua/neovim_codex/init.lua`
16. `plugin/neovim_codex.lua`

The core layers must remain free of `vim` dependencies.

## Semantic Seam

`ChatDocument` is the semantic seam between app-server state and the UI.

- the store keeps protocol truth for threads, turns, items, and streaming deltas
- the projector converts that truth into semantic blocks with explicit UI surfaces
- the renderer converts semantic blocks into markdown lines plus render metadata
- the surface owns the primary transcript/composer overlay
- the viewer stack owns secondary widget layering and pop-back behavior
- the details module formats verbose block inspection without changing the transcript contract

UI modules should not inspect raw store internals directly when the same information already exists in `ChatDocument`.

## Protocol-First Rule

The projector must conform to the app-server protocol as implemented in the Codex source tree.

- use structured item fields first
- preserve the original item payload in block metadata
- compact only at presentation time
- keep raw protocol available through `:CodexEvents`

See `architecture/protocol-first.md` for the current mapping rules.

## Current Vertical Slice

The current usable slice includes:

- spawn `codex app-server`
- perform `initialize`
- send `initialized`
- create, read, list, and resume threads
- start turns from a NeoVim markdown composer
- reconstruct streamed item state from the typed app-server delta notifications currently handled by the client
- project app-server items into semantic transcript blocks
- render those blocks into a markdown transcript inside a centered overlay

## Important Contract Notes

- request/response methods mutate state only through the store
- transcript and composer buffers intentionally use plain `markdown` so user filetype, treesitter, and markdown-renderer customization can apply naturally
- plugin-owned markdown buffers are distinguished through buffer variables, not custom filetypes
- optional app-server fields can arrive as `vim.NIL` through `vim.json.decode`, so projection and render metadata must clone values safely
- request failures are not the same thing as transport failures and should not poison connection state
- server-initiated approval and question requests are not transcript items; they need dedicated UI surfaces later
