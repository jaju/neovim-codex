# NeoVim Contract

This directory defines the stable internal abstractions on the NeoVim side.

The goal is to keep pure Lua logic independent from NeoVim APIs and keep editor-specific concepts from leaking downward.

## Boundary Rule

- pure Lua core owns transport-neutral protocol handling, state, selectors, projections, and internal semantic models
- NeoVim-facing code owns buffers, windows, LSP, treesitter, diagnostics, quickfix, and UI affordances
- NeoVim APIs should not leak into lower layers when a plain Lua model is sufficient

## Current Focus

The current abstractions intentionally stay small:

- code and text location references
- diagnostics and semantic slices
- transcript block references
- future compose fragments
- UI surface mapping from semantic content to transcript/activity/details/modal/events
