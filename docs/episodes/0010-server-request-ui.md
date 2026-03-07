# 0010 - Server Request UI

This milestone implements the first blocking server-request path against the locked Codex app-server contract.

## What changed

- command approval requests now open in a stacked request viewer instead of appearing as transcript noise
- file-change approvals use the same request surface and decision model
- tool `requestUserInput` prompts reuse `vim.ui.select` / `vim.ui.input` instead of inventing a parallel chooser/input layer
- pending request state now lives in the pure Lua store and is surfaced in selectors and footer/status summaries
- `serverRequest/resolved` now clears the pending request state and collapses the viewer stack cleanly

## Why it matters

The plugin now treats blocking app-server requests as first-class protocol state machines rather than as transcript content or future TODOs. That keeps the implementation aligned with the upstream wire contract and preserves a clean split between conversation reading surfaces and modal decision surfaces.

## Consequence for later work

Future history, semantic composition, and dynamic-tool work should keep using the same rule: protocol-first state in pure Lua, deliberate UI surface mapping in NeoVim, and user-configurable collection surfaces where NeoVim already has strong primitives.
