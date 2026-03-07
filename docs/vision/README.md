# Vision Index

This folder is the long-lived design memory for `neovim-codex`.

Use it when the problem is not “how does the current code work?” but “what are we trying to build, and what must stay true while we build it?”

## Load Order

When starting new work, prefer this order:

1. `vision/tenets.md`
2. one focused vision document for the feature area you are touching
3. only then the architecture docs or episodic notes

## Why this exists

The repository now has enough moving parts that chat history is not a reliable source of product intent.

This tree captures the stable direction so future work does not drift into:

- generic chat UI work
- execution-log-first rendering
- ad hoc prompt stuffing
- tool-specific hacks that ignore the NeoVim environment as the moat

## Current Vision Contexts

- `vision/tenets.md`
  - central rules that should remain stable across features
- `vision/workspace-model.md`
  - how code buffers and chat buffers form two first-class semantic worlds
- `vision/context-mobility.md`
  - how information should move between the codebase, the chat surface, and the next-turn composer
- `vision/composer-fragments.md`
  - the target model for semantic composition of follow-up turns

## Relationship To Other Docs

- `architecture/*`
  - explains current contracts and layering
- `usage/*`
  - explains how to operate the current plugin
- `episodes/*`
  - explains how the design evolved over time

The `vision/*` docs are not implementation notes. They are the stable intent that should steer implementation choices.
