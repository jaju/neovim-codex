# 0011 - Workbench And Packet Contract

This milestone does not add UI code yet. It locks the next composition model before implementation starts.

## Why now

The chat loop is usable enough that the next leverage point is not more transcript plumbing. It is context mobility.

Without a stable model, workbench and compose-review work would drift into:

- copy/paste behavior with lost provenance
- duplicate state between tray and composer
- ambiguous terminology like `attachment` versus `fragment`
- thread confusion when staged context belongs to one conversation but is sent in another

## What is locked

- `fragment` is the single captured semantic unit
- `workbench` is the thread-local staging area for fragments
- `packet` is the final outbound turn payload
- `compose review` is the finalization surface

The first implementation slice should stay small:

- path capture
- visual selection capture
- transcript block capture
- quick-peek workbench tray
- compose review over the same staged state

## Consequence for later work

Future semantic composition and TypeScript-aware context work should build on these terms and these state boundaries instead of inventing new staging metaphors.
