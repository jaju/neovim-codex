# Context Mobility

## Problem Statement

The core UX problem is not sending text to Codex.

It is moving the right information from the right place into the next turn with minimal friction and maximal accuracy.

## Source Zones

The user should be able to collect context from at least these zones.

### Code-side zones

- current file path
- current cursor symbol
- current visual selection
- current function/class/tree-sitter node
- diagnostics under cursor
- quickfix/location list entries
- LSP definitions and references
- failing tests or build/lint output already surfaced in NeoVim

### Chat-side zones

- a response block
- a plan block
- a failure summary
- a command or tool detail block
- a quoted snippet from the transcript
- an item selected in a details viewer

## What Must Be Preserved

When context moves, it should keep useful attributes where possible:

- source kind
- file path
- line span
- symbol identity
- thread/turn/item provenance
- formatting intent
- whether the content is best treated as code, prose, quote, or reference

## Wrong Model

The wrong model is:

- copy plain text
- paste into a generic prompt
- lose origin and structure

That creates drift and extra work.

## Better Model

The better model is:

- capture a semantic fragment
- preserve provenance
- stage it in a thread-local workbench
- open compose review when deliberate control is needed
- render a clear outgoing packet preview before send

## UX Bias

Operations should feel fast enough that the user reaches for them naturally.

Examples of desirable verbs:

- add current path to composer
- add selected code range to composer
- add current diagnostic to composer
- add transcript block to composer
- add inspected detail to composer
- quote this block for follow-up

## Why This Matters

Once context mobility becomes natural, the plugin stops being “chat in NeoVim” and becomes a real accelerator for follow-up reasoning and implementation.

## Workbench Rule

Captured context should not disappear into the composer immediately.

It should first become visible in a thread-local workbench so the user can:

- quick-peek current staged context
- remove fragments easily
- verify thread ownership
- move into compose review deliberately
