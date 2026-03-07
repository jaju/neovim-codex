# Documentation Index

This repository keeps documentation in four categories.

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

## Update Rule

Every meaningful architectural or workflow change should update:

1. `README.md` if the user-facing behavior changed
2. `CHANGELOG.md` if the repository state changed
3. one `docs/architecture/*` file if contracts or layering changed
4. one `docs/development/*` file if the developer workflow changed
5. one `docs/usage/*` file if installation or operation changed
6. one `docs/episodes/*` file if the change is primarily historical or iterative
