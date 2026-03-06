# Episode 0002: Local beads workflow bootstrap

Date: 2026-03-06

## Goal

Initialize repository-local issue tracking without polluting tracked source files with database artifacts.

## Decisions

- `bd` was initialized in this repository with prefix `ncodex`.
- The beads database lives under `.beads/` and remains local to the repository.
- `.git/info/exclude` was used so tracker storage stays out of normal git status noise.
- The tracked repository changes are limited to workflow scaffolding:
  - `AGENTS.md`
  - `.gitignore` additions for Dolt database artifacts

## Initial Roadmap

Epic: `ncodex-bzw`

Child tasks:

- `ncodex-bzw.1` - development workflow and automated smoke tests
- `ncodex-bzw.2` - thread and turn lifecycle support
- `ncodex-bzw.3` - thread history UI and server-backed rewind controls
- `ncodex-bzw.4` - approvals and request-user-input flows
- `ncodex-bzw.5` - explicit prompt composer from NeoVim context
- `ncodex-bzw.6` - dynamic tool registration and dispatch
- `ncodex-bzw.7` - deterministic TypeScript adapter daemon

## Process Rule

Each task must be demoed to the user before closure. After the user confirms the task outcome, dependent tasks must be updated with the implementation details that became concrete during the completed task.
