# Workbench Model

## Why This Exists

The next turn should not be assembled by copying loose text between the code world and the Codex world.

The plugin needs a small, explicit staging model that makes context capture visible, reversible, and thread-local.

## Terms

Use these terms consistently:

- `fragment`
  - one captured semantic unit
- `workbench`
  - the staged fragment set for the active thread
- `packet`
  - the final outbound turn payload
- `compose review`
  - the surface where the message and staged fragments are finalized before send

Do not use alternative names like `attachment` or `clipboard` for this model.

## UX Shape

The workbench is not the main chat surface and not a permanent side panel.

The intended flow is:

1. capture fragments from the code world when needed
2. quick-peek the thread-local workbench
3. open compose review when the user wants deliberate control
4. send the packet

Normal chat use should remain fast without touching the workbench.

## Why Not A Permanent Side Panel

A permanent panel creates visual rent:

- it steals columns from code
- it duplicates information when empty or trivial
- it pushes the user toward maintaining another always-open surface
- it turns staging into ambient clutter instead of an explicit action

The right default is a toggleable tray.

## Workbench Tray

The tray should be:

- compact
- summary-first
- thread-local
- easy to show or hide
- easy to remove fragments from
- easy to park or unpark fragments in
- layered through the same secondary-viewer stack as the other widgets

The tray is a quick peek, not a second transcript.

It should always reinforce the active thread, for example:

- `Workbench · thread <id>`
- `3 fragments staged`

## Compose Review

Compose review is the finalization surface.

It should make three things visible at once:

1. the active thread
2. the authored compose text
3. the ordered staged fragments that can be referenced from that text

This is where the user edits intent and reviews context together.

## Thread Visibility Rule

Thread ownership must be visible in every workbench-related surface:

- chat footer
- workbench tray title
- compose review title

The user should never have to guess which thread owns the staged context.

## Thread Locality Rule

The workbench is thread-local by default.

That means:

- switching threads switches workbench state
- fragments do not silently follow the user across threads
- cross-thread movement, if it exists later, must be explicit

## Consumption Rule

Active fragments should be consumed on send by default.

Parked fragments remain available to the same thread for later use. Pinned or reusable context can exist later, but the default should still reduce stale active carryover.

## First Useful Slice

The first useful slice should stay small.

Capture from code:

- current file path
- current visual selection as code range with path and lines
- current diagnostic under cursor

Do not capture from chat in the first slice.

That is enough to prove the workbench model without overbuilding it.
