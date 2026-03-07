# Workbench And Packet Contract

This document freezes the smallest useful internal contract for staged context and outbound turn assembly.

It is an internal design contract, not a public API promise.

## Terms

Use these names consistently in code, UI, docs, and task notes:

- `Fragment`
- `WorkbenchState`
- `PacketDraft`

## `Fragment`

Purpose:
- represent one captured semantic unit that can be inspected, removed, rendered, and included in the next packet intentionally

Minimum fields:
- `id`
  - stable local identifier
- `thread_id`
  - owning thread
- `kind`
  - one of the allowed fragment kinds
- `label`
  - concise human-facing identifier for list rendering
- `summary`
  - one-line summary for workbench tray rendering
- `payload`
  - kind-specific structured content
- `provenance`
  - enough information to trace origin without scraping rendered text later

### Allowed `Fragment.kind` values for v1

Only allow these now:

- `path_ref`
- `code_range`
- `diagnostic`
- `chat_block`

Do not introduce broader fragment kinds until the first workbench loop is exercised.

### `Fragment.payload` by kind

`path_ref`
- `location: LocationRef`

`code_range`
- `slice: TextSlice`

`diagnostic`
- `diagnostic: DiagnosticRef`

`chat_block`
- `block: ChatBlockRef`
- optional `slice: TextSlice`

### `Fragment.provenance`

The exact shape may remain lightweight, but it must preserve enough to support:

- inspect
- remove
- render in the tray
- render into the packet preview
- future export/enrichment work

For v1, provenance should come from existing stable models when possible:

- `LocationRef`
- `DiagnosticRef`
- `ChatBlockRef`
- `TextSlice`

## `WorkbenchState`

Purpose:
- hold the staged fragments for one thread

Minimum fields:
- `thread_id`
- `order`
  - ordered fragment ids
- `by_id`
  - fragment lookup table

Rules:
- thread-local only
- visible count should be derivable cheaply
- remove must be O(1) by id plus order update
- no hidden fragment inclusion outside this state

## `PacketDraft`

Purpose:
- represent the final outbound turn being prepared for send

Minimum fields:
- `thread_id`
- `message_text`
- `fragment_ids`
  - the ordered fragment ids being included

Derived views may include:
- rendered preview lines
- estimated size
- grouped summaries

But these are projections, not new source-of-truth state.

## Behavioral Rules

### 1. Thread locality

A `WorkbenchState` belongs to exactly one thread.

### 2. Explicit inclusion

Only fragments present in the active workbench may become part of the packet.

### 3. Consume on send

The default send behavior should clear the active workbench for that thread after successful packet submission.

### 4. No duplicate hidden state

The workbench tray and compose review must project from the same `WorkbenchState`.

### 5. No raw scraping

Fragments must be created from semantic editor or transcript state, not by scraping already-rendered markdown where stronger structure exists.

## UI Surface Mapping

`Fragment`
- appears as one row in the workbench tray
- can be inspected or removed

`WorkbenchState`
- drives chat footer count
- drives tray contents
- drives compose review fragment list

`PacketDraft`
- drives compose review
- drives final send payload assembly

## First Capture Actions

The first supported capture actions should be:

- add current file path to workbench
- add visual selection as `code_range`
- add selected transcript block as `chat_block`

Diagnostic capture may be included in the first slice if it falls out cheaply from existing editor state, but it is not required to prove the model.
