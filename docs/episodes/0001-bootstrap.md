# Episode 0001: Bootstrap the app-server client

Date: 2026-03-06

## Goal

Create the smallest usable vertical slice that validates the chosen architecture.

## Why This Slice First

The repository was empty. The highest-leverage first step is not thread UI or prompt composition. It is proving that:

- the plugin can supervise `codex app-server`
- the JSON-RPC handshake works
- protocol traffic can be captured cleanly
- state can live outside NeoVim-specific code

## Delivered

- pure Lua decoder and request routing core
- pure Lua store with subscriptions
- NeoVim runtime transport using `vim.uv.spawn`
- command surface for start, stop, status, and event inspection

## Deferred

- threads and turns
- approvals
- dynamic tools
- TypeScript adapter
- rich UI layout
