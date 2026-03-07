# Core Models

These are the smallest NeoVim-side models worth stabilizing now.

They are internal contracts, not public API promises.

## 1. `LocationRef`

Purpose:
- anchor information to a file and optional range

Fields:
- `path`
- `filetype`
- `range?`

Use for:
- file references
- code selections
- diagnostics
- LSP locations
- tree-sitter captures

## 2. `TextSlice`

Purpose:
- carry text plus the minimum provenance needed to reuse it later

Fields:
- `text`
- `language_or_filetype?`
- `location?`
- `source_kind`

Use for:
- selected code
- selected prose
- compiler/test excerpts
- transcript excerpts

## 3. `DiagnosticRef`

Purpose:
- normalize diagnostic-like information from LSP, compiler, lint, or test sources

Fields:
- `source`
- `code?`
- `severity`
- `message`
- `location`

Use for:
- quickfix-backed follow-up capture
- sending a precise failure into the next turn
- future targeted validation flows

## 4. `ComposeFragment`

Purpose:
- represent the future seam between the code world and the outbound Codex packet

Kinds to allow now:
- plain text
- path reference
- code slice
- diagnostic reference

Minimum rule:
- every fragment should preserve enough provenance to be rendered, inspected, and reused intentionally

Avoid freezing anything more detailed than this until real composition flows exist.
