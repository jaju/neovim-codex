# Episode 0005: Overlay chat UI and semantic rendering

Date: 2026-03-06

## Goal

Replace the first split-and-prompt chat surface with a NeoVim-native overlay that is readable enough to dogfood daily.

## Delivered

- centered overlay chat UI built on `nui.nvim`
- transcript and composer as plain markdown scratch buffers
- multiline composer with explicit send:
  - `<C-s>`
  - `gS`
  - `:CodexSend`
- `:CodexChat` now toggles the overlay instead of only opening it
- semantic `ChatDocument` projection between raw app-server thread state and transcript rendering
- compact activity summaries for low-signal internal command noise
- buffer variables for markdown personalization:
  - `b:neovim_codex`
  - `b:neovim_codex_role`
  - `b:neovim_codex_thread_id`

## Important Constraints Learned

- the right architectural seam is not the window system; it is the projection from raw store state into semantic transcript blocks
- markdown filetype is a better contract than a custom filetype because it lets user treesitter, markdown renderers, and ftplugins apply naturally
- a prompt-style single-line buffer fights real prompt composition; a normal multiline buffer is the correct primitive
- explicit send is better than `<Enter>` in a multiline composer, but `<C-s>` must remain overridable because terminal flow control is still a reality
- raw protocol and low-signal internal command chatter need a separate home (`:CodexEvents`) instead of dominating the main transcript

## Why This Matters

This is the first UI slice that is both structurally extensible and pleasant enough to act as the actual development surface for the plugin.
