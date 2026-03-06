# Episode 0006: Protocol-First Transcript Projection

Date: 2026-03-06

## What changed

The chat projection stopped classifying command items by shell-string heuristics and now projects transcript surfaces from the app-server protocol types and fields directly.

## Why it mattered

The app-server already exposes structured `commandExecution` items with `commandActions`, `status`, `aggregatedOutput`, `exitCode`, and `durationMs`.

Using shell-string heuristics on top of that was both weaker and less truthful than the protocol itself. Shell-wrapped commands like `zsh -lc "rg ..."` exposed that weakness immediately.

## Architectural consequence

The central rule is now explicit:

- conform to the protocol shapes implemented in the Codex source tree
- preserve the raw structured item payload in transcript metadata
- compact only at presentation time

This is now documented under `docs/architecture/protocol-first.md` and reflected in the `ChatDocument` projection layer.

## User-visible consequence

- successful read/list/search commands can render as compact activity blocks using typed `commandActions`
- failed or unknown commands stay as detailed command blocks
- transcript headings are highlighted by semantic surface type while staying inside normal markdown buffers
- raw protocol remains available in `:CodexEvents`

## What remains later

Approval and question-request UI is still a later milestone, but the docs now spell out that these are server requests rather than transcript items:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `tool/requestUserInput`
- `serverRequest/resolved`
