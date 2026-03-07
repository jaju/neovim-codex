# Episode 0012: First Workbench Slice

This episode adds the first semantic-composition loop on top of the chat overlay:

- thread-local pure-Lua workbench state
- a toggleable workbench tray for quick peeks and fragment removal
- a compose-review overlay for final packet assembly
- initial capture flows from code buffers and chat transcript blocks

The important architectural choice in this slice is that the workbench lives in the pure Lua store. The tray and compose review are only projections over that state.
