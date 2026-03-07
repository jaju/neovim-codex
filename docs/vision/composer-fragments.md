# Composer Fragments

## Why This Exists

The current composer is a multiline markdown buffer.

That is a good start, but it is not the end state.

The next meaningful step is to make the outgoing turn semantically composable.

## Target Model

A future turn should be assembled from:

1. user-authored instruction text
2. ordered semantic fragments staged in a thread-local workbench
3. a rendered preview of what Codex will receive as the outbound packet

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

## First Stable Slice

The first implementation slice should stay narrow:

- `path_ref`
- `code_range`
- `diagnostic`

And the first capture actions should be:

- current file path
- visual selection as code range
- diagnostic under cursor

This is enough to prove the model before adding richer semantic capture sources. Chat text can still be copied manually when it is genuinely worth reusing.
