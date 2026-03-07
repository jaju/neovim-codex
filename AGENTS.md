# Agent Instructions

## Repository Entry Points

Start with these files instead of reverse-deriving intent from code:

- `README.md` for current user-facing behavior, command surface, and status
- `docs/README.md` for the documentation index and question-to-file routing
- `docs/development/workflow.md` for the current local development and verification loop

For Codex app-server protocol, contract, or drift questions:

- the upstream source of truth is the local Codex checkout at `CODEX_REPO_ROOT`
- `CODEX_REPO_ROOT` is expected to come from a local `.envrc` loaded by `direnv`
- start with `docs/contracts/codex-app-server/README.md`
- then read `docs/contracts/codex-app-server/drift-policy.md`
- machine-checked artifacts live at `contracts/codex-app-server/watch-manifest.json`, `contracts/codex-app-server/snapshots/`, and `scripts/check_codex_app_server_contracts.py`
- prefer `./scripts/contracts-check` for drift checks; use `--generate` only when intentionally comparing against the installed `codex` binary instead of the configured checkout

## Issue Tracking

This repository uses `bd` (beads) for task tracking.

### Required Workflow

1. Run `bd ready` to identify unblocked work.
2. Open the selected task with `bd show <id>`.
3. Claim it with `bd update <id> --claim` before implementation.
4. Keep task context current while working.
5. Before closing a task:
   - demonstrate the user-visible goal to the user
   - get explicit user confirmation that the goal is met
   - update dependent tasks with the exact details clarified during implementation
   - update `README.md`, `CHANGELOG.md`, and the relevant files under `docs/`
   - create a git commit with a descriptive message
6. Only after the user confirms and dependent tasks are updated may the task be closed.

### Commands

```bash
bd ready
bd show <id>
bd update <id> --claim
bd update <id> --body-file <file>
bd close <id>
```

## Shell Safety

Use non-interactive flags for file operations to avoid hanging on prompts.

Examples:

```bash
cp -f source dest
mv -f source dest
rm -f file
rm -rf directory
```
