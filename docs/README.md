# Documentation Index

This repository keeps documentation in six categories.

## Vision

Use these when the question is what the product is trying to become, not only how the current implementation works.

- `vision/README.md` - entrypoint and load order for long-lived design memory
- `vision/tenets.md` - central product rules that should stay stable across features
- `vision/workspace-model.md` - the code world and conversation world as two first-class semantic domains
- `vision/context-mobility.md` - how context should move between code, chat, and the next turn
- `vision/composer-fragments.md` - the target model for semantic composition of follow-up turns

## Contracts

Use these when the question is what upstream or internal surface we are intentionally willing to depend on.

- `contracts/README.md` - contract load order and relationship to machine-checked manifests
- `contracts/codex-app-server/README.md` - the narrow app-server surface this plugin tracks
- `contracts/codex-app-server/interest-set.md` - the maintained list of watched app-server types and why they matter
- `contracts/codex-app-server/drift-policy.md` - how to detect and review app-server drift
- `contracts/neovim/README.md` - the NeoVim-side boundary rule and abstraction focus
- `contracts/neovim/core-models.md` - the stable small internal models worth preserving
- `contracts/neovim/ui-surface-mapping.md` - how semantic content maps to transcript, details, modals, and events

## Stable Architecture

Use these when the structure or contracts matter.

- `architecture/layers.md` - dependency order and module responsibilities
- `architecture/protocol-first.md` - protocol-first transcript mapping and item-surface rules

## Development

Use these when hacking on the plugin itself.

- `development/workflow.md` - local test commands and the dogfood loop inside NeoVim

## Usage

Use these to install and exercise the plugin.

- `usage/lazy-nvim.md` - step-by-step setup for a local `lazy.nvim` configuration
- `usage/chat.md` - daily chat, thread, and report flows inside NeoVim

## Episodic Notes

Use these as compact project memory snapshots that can be injected later.

- `episodes/0001-bootstrap.md` - why the repository starts with connection and handshake primitives
- `episodes/0002-beads-bootstrap.md` - how local beads tracking was initialized and what the first roadmap looks like
- `episodes/0003-dogfood-loop.md` - how the initial smoke and health loop was established
- `episodes/0004-thread-turn-chat.md` - how the first in-editor chat loop and thread lifecycle support landed
- `episodes/0005-overlay-chat-ui.md` - how the split prompt UI was refactored into a markdown overlay with semantic rendering
- `episodes/0006-protocol-first-projection.md` - why transcript projection now follows the app-server protocol types directly
- `episodes/0007-conversation-first-inspector.md` - how the overlay split into conversation, activity, and details surfaces
- `episodes/0008-vision-tree.md` - why long-lived product intent now lives under `docs/vision/`
- `episodes/0009-contracts-and-drift.md` - why the plugin now keeps a narrow watched app-server contract and checks it for drift

## Update Rule

Every meaningful architectural or workflow change should update:

1. `README.md` if the user-facing behavior changed
2. `CHANGELOG.md` if the repository state changed
3. one `docs/vision/*` file if product intent changed
4. one `docs/contracts/*` file if a boundary or integration surface changed
5. one `docs/architecture/*` file if contracts or layering changed
6. one `docs/development/*` file if the developer workflow changed
7. one `docs/usage/*` file if installation or operation changed
8. one `docs/episodes/*` file if the change is primarily historical or iterative
