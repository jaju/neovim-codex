# UI Surface Mapping

Each meaningful app-server or NeoVim-side semantic event should map to a deliberate UI surface.

## Main Transcript

Use for:
- user requests
- assistant responses
- plans
- concise failures
- concise activity summaries that matter for current understanding

Do not use it as:
- a raw protocol log
- a terminal dump
- a permanent progress ticker

## Footer / Status Line

Use for:
- in-progress execution state
- streaming status
- active thread/turn summary
- active thread workbench count

Do not persist ephemeral status inline when it adds no reasoning value.

## Workbench Tray

Use for:
- quick-peek visibility into the staged fragments for the active thread
- lightweight fragment removal
- compact per-fragment summaries
- short fragment handles visible to the user
- an obvious transition point into compose review

The tray should stay summary-first.
It is not a second transcript and not the final edit surface.

The tray is a secondary surface and must participate in the same viewer-stack discipline as other secondary widgets. It must not bypass the stack or render beneath the chat overlay.

## Compose Review

Use for:
- editing the authored packet template
- reviewing the ordered staged fragments for the active thread
- previewing what will become the compiled packet before send

This is the deliberate finalization surface, not the always-on capture surface.

Compose review is also a secondary surface and must obey the same stack and pop-back rules as the tray, details inspector, and reports.

## Details Inspector / Viewer Stack

Use for:
- verbose command detail
- stdout or structured output previews
- typed item payload detail
- reasoning detail when explicitly requested
- stored thread reports
- event log viewing
- fragment inspection

The viewer stack should be poppable and return the user to the previous context cleanly.

## Modal / Blocking Request Surface

Use for:
- command approval requests
- file-change approval requests
- tool `requestUserInput`

These flows are not transcript content.
They are server-driven request/response state machines.
The viewer explains the request; answer collection itself should reuse `vim.ui.select` / `vim.ui.input` so user UI personalization still applies.

## Events Viewer

Use for:
- raw JSON-RPC or normalized protocol trace
- debugging protocol ordering or missing fields

This is the debugging truth surface, not the main reading surface.

## Selection And Composition Rule

Any information shown in transcript or details should eventually be selectable as structured follow-up material.

For the current implementation slice, structured workbench capture should come from the code world first, not the transcript.

Thread visibility must remain explicit across chat footer, workbench tray, and compose review so staged context never feels detached from its owning conversation.

Read-only secondary surfaces must be hosted by the shared `viewer_stack` popup path and opt into the no-insert baseline. If a surface is immutable, it should not own a one-off popup lifecycle or allow itself to drift into insert mode. Composite editor surfaces may use custom layouts, but they must rebuild cleanly after hide/show cycles instead of reusing stale window ids.

That requires:
- stable semantic block identities
- provenance retained behind rendered content
- no dependence on scraping already-rendered markdown later
