# Episode 0010: Codex Repo Root And Agent Start Points

Date: 2026-03-07

## What changed

The repository now treats `CODEX_REPO_ROOT` as the primary source-of-truth pointer for Codex app-server contract work.

The contract drift checker can resolve the upstream schema from that checkout directly, and the repo now exposes `./scripts/contracts-check` as the stable command entrypoint.

The repository instructions and docs index also gained explicit fast paths so protocol-contract questions start from the contract docs instead of being rediscovered from implementation code.

## Why it mattered

The previous contract workflow was technically present but too implicit.

Two problems followed:

- the source Codex checkout path lived only in examples instead of a configured local contract
- agents could answer protocol-contract questions by scanning scripts and docs backward instead of starting from a small, explicit index

## Consequence

Contract drift work is now routed through:

1. local `.envrc` and `direnv`
2. `CODEX_REPO_ROOT`
3. `./scripts/contracts-check`
4. the contract docs under `docs/contracts/codex-app-server/`
