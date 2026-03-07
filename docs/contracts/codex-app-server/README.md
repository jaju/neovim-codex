# Codex App-Server Contract

This directory defines the narrow app-server surface that `neovim-codex` intentionally tracks.

## Rule

Track only what the plugin truly depends on.

Do not mirror the entire app-server protocol.

## Sources Of Truth

Use these in order:

1. the live app-server source and generated schema in the Codex repository
2. the checked-in watched manifest under `contracts/codex-app-server/watch-manifest.json`
3. the checked-in snapshots under `contracts/codex-app-server/snapshots/`
4. the docs in this directory that explain why each watched area matters

## Current Interest Areas

- connection and conversation control
  - initialize
  - thread lifecycle
  - turn lifecycle
- streamed turn output
  - item start/completion
  - agent message, plan, reasoning, command output, file change deltas
- blocking server requests
  - command approval
  - file-change approval
  - tool `requestUserInput`
- experimental extension path
  - dynamic tools

## Policy

When the app-server protocol already provides typed structure, the plugin must project from that structure directly.

Do not rediscover meaning from shell strings or rendered transcript text when the protocol already gives stronger truth.
