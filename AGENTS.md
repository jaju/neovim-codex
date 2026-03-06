# Agent Instructions

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
