# Episode 0009: Contracts Tree And Drift Check

Date: 2026-03-07

## What changed

The repository gained a `docs/contracts/` tree plus a machine-readable watched-surface manifest and schema snapshots for Codex app-server integration.

It also gained `scripts/check_codex_app_server_contracts.py` so the watched app-server surface can be checked against:

- a local Codex source tree
- or the installed `codex` binary

## Why it mattered

The product now depends on two ecosystems with different change rates.

- NeoVim is stable and conceptually narrow
- Codex app-server is evolving quickly and needs explicit drift tracking

Without a contracts layer, the repository would have vision docs but no durable record of which upstream surfaces were intentionally depended on.

## Architectural consequence

The docs tree now separates:

- `vision/*` for product intent
- `contracts/*` for stable boundaries and drift policy
- `architecture/*` for current implementation structure
- `episodes/*` for historical evolution

## What this enables next

Future work on approvals, request-user-input flows, dynamic tools, and semantic composition can now name their exact upstream dependencies and detect drift explicitly instead of rediscovering it informally.
