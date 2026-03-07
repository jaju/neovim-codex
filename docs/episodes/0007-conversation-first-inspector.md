# Episode 0007: Conversation-First Transcript and Details Inspector

Date: 2026-03-07

## What changed

The chat overlay stopped treating every typed item as equally important in the main transcript.

The transcript is now explicitly conversation-first:

- turn headings derive from the request text so markdown outline mode stays useful
- commentary renders as inline working notes instead of heading-heavy status blocks
- successful command execution stays terse in the transcript
- verbose command, tool, reasoning, and file-change details move into an on-demand inspector popup

## Why it mattered

The earlier protocol-first pass preserved truth, but it still surfaced too much operational detail inline.

That made the transcript harder to read, made the markdown outline almost useless, and spent too much vertical space on execution mechanics that matter only occasionally.

## Architectural consequence

The UI model is now explicit:

- conversation in the main transcript
- activity as terse summaries in the transcript
- details in a secondary popup surface
- raw protocol in `:CodexEvents`

The key rule did not change: all of these still project from the typed app-server payloads first.

## User-visible consequence

- `<CR>` on a transcript block opens `:CodexInspect` details for that block
- `:CodexInspect` exposes full command text, output, and typed metadata without polluting the main transcript
- `:CodexEvents` and report viewers now open in the same stacked popup layer, so secondary widgets no longer disappear behind the main overlay
- in-progress execution moves to the footer instead of appearing as inline chatter

## What remains later

Native folding and richer per-block widgets can still build on top of this. The important change here is that the transcript no longer has to carry every detail just to preserve access to them.
