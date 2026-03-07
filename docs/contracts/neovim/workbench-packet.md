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
- represent one captured semantic unit that can be inspected, removed, rendered, and intentionally included in the next packet

Implemented v1 fields:
- `id`
  - stable local identifier
- `kind`
  - one of the allowed fragment kinds
- `label`
  - concise human-facing identifier for list rendering
- `source`
  - capture origin such as `buffer`, `visual_selection`, or `chat`

Kind-specific fields:

`path_ref`
- `path`
- `filetype`

`code_range`
- `path`
- `filetype`
- `range = { start_line, end_line }`
- `text`

`diagnostic`
- `source`
- `code?`
- `severity?`
- `path?`
- `message`

`chat_block`
- `thread_id`
- `turn_id`
- `block_id?`
- `excerpt?`
- `text`

### Allowed `Fragment.kind` values for v1

Only allow these now:

- `path_ref`
- `code_range`
- `diagnostic`
- `chat_block`

Do not introduce broader fragment kinds until the first workbench loop is exercised.

## `WorkbenchState`

Purpose:
- hold the staged fragments and compose-review draft message for one thread

Implemented v1 fields:
- `thread_id`
- `fragments_order`
- `fragments_by_id`
- `draft_message`
- `updated_at`

Rules:
- thread-local only
- visible count should be derivable cheaply
- remove must be O(1) by id plus order update
- no hidden fragment inclusion outside this state

## `PacketDraft`

Purpose:
- represent the final outbound turn being prepared for send

Implemented v1 shape:
- `thread_id`
- `message_text`
- ordered staged fragments from the active `WorkbenchState`
- rendered into a single text input item for `turn/start`

That rendered text currently has two sections:
- the covering message, if any
- `## Workbench Context` with one structured subsection per fragment

This is intentionally simple. It preserves ordering and source identity without pretending the app-server currently has a richer native fragment wire type for these captures.

## Behavioral Rules

### 1. Thread locality

A `WorkbenchState` belongs to exactly one thread.

### 2. Explicit inclusion

Only fragments present in the active workbench may become part of the packet.

### 3. Consume on send

The default send behavior clears the active workbench and its draft message for that thread after successful packet submission.

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

The first supported capture actions are:

- add current file path to workbench
- add visual selection as `code_range`
- add selected transcript block as `chat_block`

Diagnostic capture remains allowed by the contract, but it is not yet part of the first implemented slice.
