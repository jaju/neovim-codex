# Workbench And Packet Contract

This document freezes the next implementation target for staged context and outbound turn assembly.

It is an internal design contract, not a public API promise.

Current implementation note:
- the current code compiles an authored packet template with inline fragment handles at send time
- only referenced staged fragments are included in the compiled packet

## Terms

Use these names consistently in code, UI, docs, and task notes:

- `Fragment`
- `WorkbenchState`
- `PacketDraft`
- `CompiledPacket`

## `Fragment`

Purpose:
- represent one captured semantic unit that can be inspected, removed, rendered, and intentionally included in the next packet

Implemented v1 fields:
- `id`
  - stable local canonical identifier
- `handle`
  - short user-facing reference token such as `f3`
- `kind`
  - one of the allowed fragment kinds
- `label`
  - concise human-facing identifier for list rendering
- `source`
  - capture origin such as `buffer`, `visual_selection`, or `diagnostic`

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
- `range?`
- `message`

### Allowed `Fragment.kind` values for the next slice

Only allow these now:

- `path_ref`
- `code_range`
- `diagnostic`

Do not introduce broader fragment kinds until the first inline-packet loop is exercised.

## `WorkbenchState`

Purpose:
- hold the staged fragments and compose-review draft message for one thread

Implemented target fields:
- `thread_id`
- `fragments_order`
- `fragments_by_id`
- `draft_message`
  - semantically, this is the packet template text
- `updated_at`

Rules:
- thread-local only
- visible count should be derivable cheaply
- remove must be O(1) by id plus order update
- no hidden fragment inclusion outside this state

## `PacketDraft`

Purpose:
- represent the user-authored message before send-time expansion

Implemented target shape:
- `thread_id`
- `template_text`
- ordered staged fragments from the active `WorkbenchState`

`template_text` may contain fragment handle references such as:

- `[[f1]]`
- `[[f3]]`

The user should manipulate short handles, not long internal ids.

## `CompiledPacket`

Purpose:
- represent the final outbound turn payload after fragment expansion

Implemented target shape:
- `thread_id`
- `compiled_text`
- rendered into a single text input item for `turn/start`

The compiled text is produced by:

1. validating every referenced fragment handle
2. resolving it from the active `WorkbenchState`
3. expanding it with a kind-specific renderer
4. preserving authored prose order

## Fragment Expansion Rule

Fragment expansion must be:

- deterministic
- kind-specific
- minimal but complete
- based on captured fragment snapshots by default

Do not silently reread live files at send time for existing fragments unless the user explicitly refreshes them.

## Renderer Expectations

`path_ref`
- render as a compact path reference only

`code_range`
- render as a path and line-range introduction plus a fenced code block

`diagnostic`
- render as a precise diagnostic fact with location and message

Each renderer should make the fragment understandable without additional surrounding explanation.

## Behavioral Rules

### 1. Thread locality

A `WorkbenchState` belongs to exactly one thread.

### 2. Explicit inclusion

Only fragments referenced in the authored packet template may become part of the compiled packet.

Fragments staged in the workbench but not referenced remain available but are not sent.

### 3. Consume on send

The default send behavior clears the active workbench and its draft template for that thread after successful packet submission.

### 4. No duplicate hidden state

The workbench tray and compose review must project from the same `WorkbenchState`.

### 5. No raw scraping

Fragments must be created from semantic editor state, not by scraping already-rendered markdown where stronger structure exists.

### 6. No transcript capture in the first slice

Do not capture transcript blocks into the workbench in this implementation slice.

Manual copy from the chat surface remains sufficient until transcript capture proves its value.

## UI Surface Mapping

`Fragment`
- appears as one row in the workbench tray
- can be inspected or removed
- exposes a short user-facing handle for template insertion

`WorkbenchState`
- drives chat footer count
- drives tray contents
- drives compose review fragment list

`PacketDraft`
- drives compose review editor content
- may contain inline fragment handles

`CompiledPacket`
- drives final send payload assembly
- should be previewable before send

## First Capture Actions

The first supported capture actions are:

- add current file path to workbench
- add visual selection as `code_range`
- add diagnostic under cursor as `diagnostic`

Do not add transcript capture in this slice.
