# Workspace Model

## The Product Model

`neovim-codex` is a thinking workspace inside NeoVim.

It is not only a prompt box over a model.

The workspace has two primary domains.

## Domain 1: Code World

This is the world the user already inhabits in NeoVim.

Important entities:

- files
- buffers
- windows
- tabs
- paths
- line ranges
- symbols
- diagnostics
- quickfix/location entries
- tree-sitter captures
- LSP definitions, references, implementations, code actions

The code world is already structured and navigable.

The plugin should leverage that rather than flattening it into text.

## Domain 2: Conversation World

This is the world created by Codex app-server and rendered in the plugin.

Important entities:

- threads
- turns
- typed items
- user requests
- assistant responses
- plans
- activity summaries
- command/tool/file-change details
- server-request flows

The conversation world is also structured and should stay structured inside the plugin.

## Why This Split Matters

Most generic AI editor plugins treat one world as primary and the other as an attachment.

This project should not.

The user should be able to:

- inspect code and send context into chat
- inspect chat and send context back into code work
- treat multiple threads as parallel problem-solving spaces
- use one thread as primary and another as supplementary

## Threads As Mini-Worlds

A thread is not just a message list.

A thread is a bounded working context with:

- its own history
- its own active problem
- its own evidence trail
- its own follow-up possibilities

Different threads may represent:

- independent tasks
- subproblems of one larger task
- research vs implementation tracks
- exploratory branches of thought

The UI should make those contexts easy to re-enter without flattening them into one giant transcript.

## Current Practical Consequence

Right now:

- chat is the base surface
- secondary viewers open above it
- thread lifecycle is already real

Later, this should support:

- smoother cross-thread navigation
- forked thread exploration
- explicit context handoff between threads
