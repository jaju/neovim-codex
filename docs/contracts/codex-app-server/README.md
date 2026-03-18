# Codex App-Server Contract

This directory defines the narrow app-server surface that `neovim-codex` intentionally tracks.

## Rule

Track only what the plugin truly depends on.

Do not mirror the entire app-server protocol.

## Sources Of Truth

Use these in order:

1. the live app-server source and generated schema in the Codex repository rooted at `CODEX_REPO_ROOT`
2. the checked-in watched manifest under `contracts/codex-app-server/watch-manifest.json`
3. the checked-in snapshots under `contracts/codex-app-server/snapshots/`
4. the docs in this directory that explain why each watched area matters

`CODEX_REPO_ROOT` is expected to come from a local `.envrc` loaded by `direnv`. The drift checker derives the schema path from that checkout as `codex-rs/app-server-protocol/schema/typescript`.

Use `./scripts/contracts-check` for the default source-of-truth comparison. Use `./scripts/contracts-check --generate` only when you intentionally want to compare against the installed `codex` binary instead of the configured checkout.

## Current Interest Areas

- connection and conversation control
  - initialize
  - thread lifecycle, including archive, unarchive, rename, loaded-list, and compaction flows
  - response payloads that seed local thread state and sticky runtime settings
  - turn lifecycle
- streamed turn output
  - item start/completion
  - agent message, plan, reasoning, command output, file change, diff, and plan-update deltas
  - thread name/archive lifecycle notifications
- blocking server requests
  - command approval
  - file-change approval
  - permissions approval
  - tool `requestUserInput`
  - MCP elicitation
- experimental extension path
  - dynamic tools

## Policy

When the app-server protocol already provides typed structure, the plugin must project from that structure directly.

Do not rediscover meaning from shell strings or rendered transcript text when the protocol already gives stronger truth.
