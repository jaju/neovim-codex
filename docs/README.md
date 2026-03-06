# Documentation Index

This repository keeps documentation in three categories.

## Stable Architecture

Use these when the structure or contracts matter.

- `architecture/layers.md` - dependency order and module responsibilities

## Usage

Use these to install and exercise the plugin.

- `usage/lazy-nvim.md` - step-by-step setup for a local `lazy.nvim` configuration

## Episodic Notes

Use these as compact project memory snapshots that can be injected later.

- `episodes/0001-bootstrap.md` - why the repository starts with connection and handshake primitives
- `episodes/0002-beads-bootstrap.md` - how local beads tracking was initialized and what the first roadmap looks like

## Update Rule

Every meaningful architectural or workflow change should update:

1. `README.md` if the user-facing behavior changed
2. `CHANGELOG.md` if the repository state changed
3. one `docs/architecture/*` file if contracts or layering changed
4. one `docs/usage/*` file if installation or operation changed
5. one `docs/episodes/*` file if the change is primarily historical or iterative
