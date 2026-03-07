# Central Tenets

This document is the stable product memory for `neovim-codex`.

If a feature proposal conflicts with these tenets, the feature should be challenged before implementation.

## 1. NeoVim Is The Moat

`neovim-codex` is not just a chat client embedded in an editor.

It is valuable because it lives inside a programmable environment that already knows how to reason about code, files, symbols, diagnostics, selections, locations, and workflows.

That means:

- the codebase and the editor are first-class context sources
- the plugin should reuse native NeoVim concepts wherever possible
- features should increase leverage from the user’s existing configuration, not bypass it

## 2. Two Semantic Worlds Must Be First-Class

The user operates in two distinct but connected worlds:

1. the code world
2. the Codex conversation world

The code world contains:

- files
- symbols
- diagnostics
- quickfix/location entries
- tree-sitter nodes
- LSP references, definitions, and ranges

The conversation world contains:

- requests
- responses
- plans
- activity summaries
- failures
- typed details that can inform the next turn

Neither world is secondary. The product must help the user move information between them quickly and accurately.

## 3. The Main Chat Surface Is For Thinking, Not Logging

The transcript should optimize for:

- reading
- orientation
- summarization
- follow-up thought

It should not become:

- a terminal log
- a protocol dump
- a permanent progress ticker

Operational detail should be available, but only when needed.

Current policy:

- conversation lives in the main transcript
- terse operational summaries may appear inline
- verbose details live in secondary viewers
- raw protocol lives in `:CodexEvents`

## 4. Protocol Truth Comes First

When Codex app-server already provides structure, the plugin must use it.

Do not rediscover typed meaning from raw shell strings when the protocol already exposes it.

This applies to:

- thread items
- command actions
- server requests
- tool activity
- future approval and user-input flows

Presentation may compress or hide, but it must not invent a weaker or less truthful model than the protocol already provides.

## 5. User Customization Must Flow Through Native Contracts

The plugin should prefer normal NeoVim contracts over bespoke formats.

Examples:

- use plain `markdown` where markdown semantics should apply
- use buffer variables rather than custom filetypes when possible
- allow user treesitter, conceal, rendering, and keymap customizations to keep working

The plugin should be easy to personalize because personalization is part of the product advantage.

## 6. Context Mobility Is The Core UX Problem

The hardest and most valuable problem is not sending a prompt.

It is enabling the user to quickly gather, preserve, transform, and reuse high-value context across:

- code buffers
- diagnostics
- compiler/test/lint output
- chat responses
- protocol-derived detail views

The product should reduce friction in moving that context into the next turn.

## 7. Composition Must Become Semantic

The composer should evolve beyond a plain text box.

The target is a composition surface built from meaningful fragments such as:

- file paths
- file ranges
- symbols
- diagnostics
- transcript blocks
- command outputs
- test failures
- references

These fragments should preserve provenance and formatting intent.

## 8. The UI Should Behave Like A Controlled Stack

Secondary surfaces should not feel like random windows.

The user should be able to:

- open a detail surface
- inspect it
- close it
- return cleanly to the previous surface

The current direction is:

- chat overlay as the base interaction surface
- secondary viewers stacked above it
- `q` / `<Esc>` pops the latest viewer

A visible navigator may come later, but the stack behavior must be solid first.

## 9. Fast Movement Beats Decorative Complexity

UI polish matters, but speed and clarity matter more.

Features should bias toward:

- rapid inspection
- rapid composition
- rapid return to the previous context
- minimal friction for common paths

Avoid adding complexity unless it improves thinking speed or context accuracy.

## 10. Design For Plucking, Filtering, And Reuse

Anything the user reads in the chat world should eventually be selectable as structured follow-up material.

The system should support, over time:

- plucking semantic blocks from transcript/detail views
- sending them to the composer
- passing them through filters or enrichers
- exporting them into notes or docs

This must be enabled by preserving semantics in the data model, not by scraping rendered text later.
