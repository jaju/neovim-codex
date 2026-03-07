# Episode 0013: Inline Packet Templates And Code-First Capture

## What Changed

The accepted next direction for workbench and packet assembly changed before the implementation was allowed to continue.

The workbench is now explicitly constrained to:

- stay optional so chat remains useful without it
- focus on code-world capture first
- avoid transcript-to-workbench capture in the first useful slice
- compile packet text from inline fragment handles rather than appending all fragments as a distant appendix

## Why

Two design problems became clear during dogfooding.

### 1. Chat capture was not pulling its weight

Capturing transcript blocks into the workbench added complexity without enough leverage.

The same information is already present in the active conversation context, and the user can already navigate, copy, and paste from the chat surface using normal NeoVim motions.

That means chat capture should not be part of the first slice unless it proves a stronger value later.

### 2. Appendix-style packet rendering was too weak

A covering message followed by a large appended `## Workbench Context` section forces Codex to connect instructions and evidence across longer distances.

Inline fragment-handle expansion is better because it keeps:

- the local instruction
- the supporting evidence
- the next local instruction

close together in the final packet text.

## Guardrails Added

To keep future implementation aligned, the long-lived docs now record that:

- chat must stay useful without workbench complexity
- workbench capture starts from the code world
- packet drafting should use authored template text plus short fragment handles
- send-time expansion should use captured fragment snapshots by default
- tray and compose review must obey the existing viewer-stack discipline instead of bypassing it
- the earlier tray z-index bug is treated as an architecture violation, not a one-off UI glitch

## Immediate Implementation Consequences

The next pass should:

1. remove transcript capture commands and bindings from the first workbench slice
2. fix the tray/review layering so they stack above chat like the other secondary surfaces
3. add diagnostic capture from the code world
4. replace append-all packet rendering with inline handle expansion and compiled-packet preview
5. keep all of that grounded in the recorded contracts instead of re-deriving the design from memory
