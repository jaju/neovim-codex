# Layering

## Dependency Order

1. `lua/neovim_codex/core/jsonrpc.lua`
2. `lua/neovim_codex/core/store.lua`
3. `lua/neovim_codex/core/selectors.lua`
4. `lua/neovim_codex/core/packet.lua`
5. `lua/neovim_codex/core/client.lua`
6. `lua/neovim_codex/nvim/transport.lua`
7. `lua/neovim_codex/nvim/chat/document.lua`
8. `lua/neovim_codex/nvim/chat/render.lua`
9. `lua/neovim_codex/nvim/chat/composer.lua`
10. `lua/neovim_codex/nvim/viewer_stack.lua`
11. `lua/neovim_codex/nvim/chat/details.lua`
12. `lua/neovim_codex/nvim/workbench/list.lua`
13. `lua/neovim_codex/nvim/workbench/tray.lua`
14. `lua/neovim_codex/nvim/workbench/review.lua`
15. `lua/neovim_codex/nvim/workbench.lua`
16. `lua/neovim_codex/nvim/server_requests/render.lua`
17. `lua/neovim_codex/nvim/server_requests/input.lua`
18. `lua/neovim_codex/nvim/server_requests.lua`
19. `lua/neovim_codex/nvim/thread_runtime.lua`
20. `lua/neovim_codex/nvim/thread_params.lua`
21. `lua/neovim_codex/nvim/thread_runtime_picker.lua`
22. `lua/neovim_codex/nvim/chat/surface.lua`
23. `lua/neovim_codex/nvim/thread_renderer.lua`
24. `lua/neovim_codex/nvim/presentation.lua`
25. `lua/neovim_codex/nvim/chat.lua`
26. `lua/neovim_codex/init.lua`
27. `plugin/neovim_codex.lua`

The core layers must remain free of `vim` dependencies. Thread runtime selection and request-input UI now live in the NeoVim layer on purpose, even when they are partly data-shaping helpers.

## Refactor Seams

The next UI-heavy features should build on these explicit orchestration seams instead of re-expanding the top-level files.

- `nvim/thread_runtime.lua`, `nvim/thread_params.lua`, and `nvim/thread_runtime_picker.lua` own thread runtime normalization, request-time catalog lookup, and thread/turn param construction. `init.lua` should orchestrate commands, not own those details directly.
- `nvim/server_requests/render.lua` owns request presentation text and decision labels.
- `nvim/server_requests/input.lua` owns free-form request answer capture. `nvim/server_requests.lua` should stay the inbox/request orchestrator.

## Semantic Seams

There are two important semantic seams.

### `ChatDocument`

`ChatDocument` is the seam between app-server state and the main chat UI.

- the store keeps protocol truth for threads, turns, items, and streaming deltas
- the projector converts that truth into semantic blocks with explicit UI surfaces
- the renderer converts semantic blocks into markdown lines plus render metadata
- the chat surface owns the primary transcript/composer overlay

### `WorkbenchState` and Packet Compilation

`WorkbenchState` is the seam between code-world capture and outbound turn assembly.

- code-world capture creates structured fragments
- the workbench owns fragment staging and authored packet-template state per thread
- `core/packet.lua` compiles authored template text plus referenced fragments into final outbound text for `turn/start`
- workbench tray and compose review are projections over the same thread-local workbench state

## Viewer-Stack Rule

`viewer_stack.lua` owns secondary widget layering and pop-back behavior.

That rule applies to all secondary surfaces, including:

- details inspector
- events viewer
- reports
- blocking server-request viewers
- workbench tray
- compose review
- fragment inspection

No secondary widget may bypass the viewer stack or mount itself directly in a way that renders beneath or alongside the chat overlay unpredictably.

If a secondary surface needs to appear above chat, it belongs to the viewer stack.

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
- stage code-world fragments in a thread-local workbench
- open secondary viewers through a poppable stack above the chat overlay

## Important Contract Notes

- request/response methods mutate state only through the store
- transcript and composer buffers intentionally use plain `markdown` so user filetype, treesitter, and markdown-renderer customization can apply naturally
- plugin-owned markdown buffers are distinguished through buffer variables, not custom filetypes
- optional app-server fields can arrive as `vim.NIL` through `vim.json.decode`, so projection and render metadata must clone values safely
- request failures are not the same thing as transport failures and should not poison connection state
- server-initiated approval and question requests are not transcript items; they now use a dedicated stacked request surface backed by their own store state and response path
- workbench tray and compose review are not special-case overlays; they are secondary surfaces and must obey the same stack discipline as other viewers
