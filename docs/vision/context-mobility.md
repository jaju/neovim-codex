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

The chat world is still important for understanding and inspection, but chat-to-workbench capture is not part of the first useful slice.

For the current direction:

- the chat surface should stay easy to read and inspect
- the user can copy chat text manually when needed
- workbench capture should focus on code-world semantics first

Chat-side semantic capture can return later if it solves a real problem that simple copy and paste does not.

## What Must Be Preserved

When context moves, it should keep useful attributes where possible:

- source kind
- file path
- line span
- symbol identity
- formatting intent
- whether the content is best treated as code, prose, diagnostic evidence, or reference

## Wrong Model

The wrong model is:

- copy plain text
- paste into a generic prompt
- lose origin and structure

That creates drift and extra work.

## Better Model

The better model is:

- capture a semantic fragment from the code world
- preserve provenance
- stage it in a thread-local workbench
- compose a packet by inserting fragment handles inline in the authored message
- render a clear outgoing packet preview before send

## UX Bias

Operations should feel fast enough that the user reaches for them naturally.

Examples of desirable verbs:

- add current path to workbench
- add selected code range to workbench
- add current diagnostic to workbench
- add current symbol usage summary to workbench
- add current definition or reference set to workbench

## Why This Matters

Once context mobility becomes natural, the plugin stops being “chat in NeoVim” and becomes a real accelerator for follow-up reasoning and implementation.

## Workbench Rule

Captured context should not disappear into the composer immediately.

It should first become visible in a thread-local workbench so the user can:

- quick-peek current staged context
- remove fragments easily
- verify thread ownership
- move into compose review deliberately

## Packet Rule

The authored compose text should be able to reference staged fragments inline using short handles.

The final outbound packet should be compiled at send time by expanding those handles into minimal complete markdown blocks close to the local prose that needs them.

This is better than appending all fragments after the covering message because it reduces the distance between instruction and evidence.
