# Shell Extraction Path

`neovim-codex` remains the active proving ground for Codex interaction design, workbench semantics, and app-server integration discipline.

A future shell should reuse these semantic contracts instead of rebuilding them:
- semantic chat document / transcript blocks
- fragment and workbench model
- packet compilation rules
- request inbox semantics
- thread runtime settings

## Migration Rule
A surface can migrate to the shell only when the shell can own it completely. Do not keep the same long-term interaction surface half in NeoVim and half in the shell.

## Near-Term Extraction Target
The first shell-owned surface should be the transcript and its attached activity/details views. Editor-local capture and workbench-driven context assembly should stay in `neovim-codex` until the shell proves its focus and rendering model.
