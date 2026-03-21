# Development Workflow

This repository is meant to be dogfooded from a real NeoVim instance.

## Automated checks

From the repository root:

```bash
./scripts/test
```

This runs:

1. the app-server contract drift check when `CODEX_REPO_ROOT` is present in the environment
2. pure Lua unit checks for the JSON-RPC decoder, state store, and chat-document projection
3. a headless NeoVim integration run that validates:
   - plugin load
   - overlay chat creation
   - thread start/list/read/resume command surface
   - clean shutdown
   - approval and `requestUserInput` request-state handling


## Contract drift checks

The primary source of truth is the Codex checkout at `CODEX_REPO_ROOT`, typically loaded from a local `.envrc` by `direnv`.

Example `.envrc`:

```bash
export CODEX_REPO_ROOT="$HOME/src/codex"
```

After creating or updating `.envrc`, run:

```bash
direnv allow
```

Use this when the Codex source tree changes and you want to know whether the plugin's watched app-server surface drifted:

```bash
./scripts/contracts-check
```

Against a Codex source checkout:

```bash
./scripts/contracts-check --codex-repo /path/to/codex
```

Against the installed `codex` binary:

```bash
./scripts/contracts-check --generate
```

Use a direct schema dir only when the schema lives outside the normal Codex repo layout:

```bash
./scripts/contracts-check --schema-dir /path/to/codex-rs/app-server-protocol/schema/typescript
```

Refresh the checked-in snapshots only after reviewing the drift and updating code/docs intentionally:

```bash
./scripts/contracts-check --update
```

## Dogfood loop inside NeoVim

Use this when iterating on the plugin from your normal editor session.

```vim
:Lazy reload neovim-codex
:checkhealth neovim_codex
:CodexChat
:CodexThreadNew
```

Then write a short prompt in the composer and send it with `<C-s>` or `:CodexSend`.

Recommended loop:

1. edit code in the local checkout
2. `:Lazy reload neovim-codex`
3. `:checkhealth neovim_codex`
4. `:CodexChat`
5. `:CodexThreadNew`
6. write a short prompt and press `<C-s>`
7. inspect `:CodexEvents` if the transcript or thread state looks wrong
8. use `:CodexThreadRead` to inspect the stored view of a thread when debugging history behavior

## Current test scope

The current workflow validates:

- plugin load
- app-server startup and handshake
- markdown transcript and multiline composer creation
- overlay toggle behavior
- thread start, list, read, and resume APIs
- client-side `thread/rollback` request and local-store update wiring
- semantic chat-document rendering for live assistant replies and compact activity summaries

It does not yet validate:

- fork
- dynamic tools
- TypeScript adapter behavior

## Current app-server behavior to remember

- a freshly created thread without a persisted user turn may not appear in `thread/list` yet
- that same empty thread may not be resumable from storage yet
- `thread/read includeTurns=true` can fail before the first user message is persisted; the plugin falls back to metadata-only reads in that case
