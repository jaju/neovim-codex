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

Do not persist ephemeral status inline when it adds no reasoning value.

## Details Inspector / Viewer Stack

Use for:
- verbose command detail
- stdout or structured output previews
- typed item payload detail
- reasoning detail when explicitly requested
- stored thread reports
- event log viewing

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

That requires:
- stable semantic block identities
- provenance retained behind rendered content
- no dependence on scraping already-rendered markdown later
