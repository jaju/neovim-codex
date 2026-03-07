# Episode 0008: Vision Tree And Central Tenets

Date: 2026-03-07

## What changed

The repository gained a new `docs/vision/` subtree for long-lived product intent.

This tree now holds:

- a central tenets document
- the workspace model
- context-mobility goals
- the target direction for semantic composer fragments

## Why it mattered

By this point, the project had accumulated enough implementation and UX detail that chat history was no longer a safe memory system.

The risk was drift:

- treating the product like generic chat UI work
- forgetting that NeoVim itself is the moat
- optimizing the transcript as a log instead of a thinking surface
- postponing the semantic-composition direction until it became harder to recover

## Architectural consequence

The docs tree now has a stable place for product intent that is separate from:

- architecture contracts
- usage docs
- episodic implementation history

The intended load order is now:

1. `docs/vision/tenets.md`
2. one focused `docs/vision/*` file relevant to the feature area
3. only then architecture or episodic notes

## What this enables next

Future work on composer, semantic selection, context plucking, and code/chat mobility can now stay aligned with a stable written vision instead of depending on memory across long chats.
