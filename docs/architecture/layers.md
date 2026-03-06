# Layering

## Dependency Order

1. `lua/neovim_codex/core/jsonrpc.lua`
2. `lua/neovim_codex/core/store.lua`
3. `lua/neovim_codex/core/client.lua`
4. `lua/neovim_codex/nvim/transport.lua`
5. `lua/neovim_codex/nvim/presentation.lua`
6. `lua/neovim_codex/init.lua`
7. `plugin/neovim_codex.lua`

The core layers must remain free of `vim` dependencies.

## Current Vertical Slice

The first usable slice stops at connection management:

- spawn `codex app-server`
- perform `initialize`
- send `initialized`
- record protocol traffic and state transitions
- expose status and logs in NeoVim

This is intentional. It proves the transport, handshake, and store boundaries before thread and turn workflows are added.
