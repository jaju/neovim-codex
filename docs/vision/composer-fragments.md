# Composer Fragments

## Why This Exists

The current composer is a multiline markdown buffer.

That is a good start, but it is not the end state.

The next meaningful step is to make the outgoing turn semantically composable.

## Target Model

A future turn should be assembled from:

1. user-authored instruction text
2. ordered semantic fragments
3. a rendered preview of what Codex will receive

## Fragment Types

Illustrative fragment types:

- `path_ref`
- `code_range`
- `symbol_ref`
- `diagnostic`
- `quickfix_entry`
- `lsp_reference_set`
- `transcript_block`
- `detail_block`
- `command_output_excerpt`
- `test_failure`
- `note`

## Minimum Fragment Properties

Each fragment should eventually carry at least:

- `kind`
- `label`
- `content`
- `source`
- `provenance`
- optional formatting hint

## Example Provenance

- file path and line range
- symbol name and location
- thread id / turn id / item id
- diagnostic code and source
- quickfix source list

## Why Structure Matters

This gives us room for later capabilities such as:

- reorder fragments without losing meaning
- quote or compress specific fragments
- route fragments through deterministic filters
- route fragments through optional enrichment paths
- export fragments into docs or notes

## Non-Goal For Now

This document does not freeze an internal schema yet.

It exists to keep implementation pointed at the right target:

- semantic composition
- provenance preservation
- low-friction movement from source to next turn
