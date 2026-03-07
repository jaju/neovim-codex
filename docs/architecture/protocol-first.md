# Protocol-First Projection

This plugin treats the Codex app-server protocol as the source of truth.

## Central Rule

- projection and rendering must start from the typed app-server payloads
- when the protocol already provides structured fields, the client must not rediscover them from raw shell text
- transcript compaction is a presentation choice, not a data-loss step
- every rendered block should retain the originating protocol item in metadata so later selection, filtering, export, or enrichment flows have a truthful source

## Thread Item to UI Surface Mapping

The current `ThreadItem` variants from app-server v2 map to the transcript like this:

- `userMessage` -> primary user message block
- `agentMessage` -> primary assistant message block
- `plan` -> plan block
- `reasoning` -> collapsed reasoning summary block
- `commandExecution` -> either a compact activity block or a detailed command block, derived from typed `commandActions`, `status`, `exitCode`, `durationMs`, and `aggregatedOutput`
- `fileChange` -> file-change summary block
- `dynamicToolCall` -> tool summary block
- `mcpToolCall` -> tool summary block
- `collabAgentToolCall` -> collaboration summary block
- `webSearch` -> web-search summary block
- `imageView` / `imageGeneration` -> image status block
- `enteredReviewMode` / `exitedReviewMode` -> review status block
- `contextCompaction` -> compact notice block
- unknown item types -> generic notice block that keeps the raw protocol payload available for inspection

## Command Execution Rule

`commandExecution` items must be projected from:

- `commandActions`
- `status`
- `aggregatedOutput`
- `exitCode`
- `durationMs`
- `cwd`

Do not classify commands by shell-string heuristics when `commandActions` already tells us whether the command was a `read`, `listFiles`, `search`, or `unknown` action.

If `commandActions` is fully known and the command completed successfully, the transcript should render a terse activity summary.

If the command failed or has unknown actions, the transcript should render a terse failure summary and expose the full detail through the details inspector.

If the command is still running, keep that state in the footer or another transient status surface rather than consuming transcript space.

## Streaming Rule

When the protocol exposes item-specific deltas, the store should fold them back into the same typed item fields that appear on the completed item.

Current handled deltas:

- `item/agentMessage/delta` -> `agentMessage.text`
- `item/plan/delta` -> `plan.text`
- `item/reasoning/summaryPartAdded` / `item/reasoning/summaryTextDelta` -> `reasoning.summary`
- `item/reasoning/textDelta` -> `reasoning.content`
- `item/commandExecution/outputDelta` -> `commandExecution.aggregatedOutput`

Raw protocol notifications still remain visible in `:CodexEvents`.

## Server Requests

Server-initiated JSON-RPC requests are not transcript items and should not be forced into the main conversation view.

They need dedicated UI surfaces later:

- `item/commandExecution/requestApproval` -> command approval modal
- `item/fileChange/requestApproval` -> file-change approval modal
- `tool/requestUserInput` -> question form/modal
- `serverRequest/resolved` -> clear pending request UI state

These flows are planned for the approval and request-user-input milestone, but the architecture should already respect these protocol boundaries.

## Rendering Policy

The main transcript should prioritize:

- user messages
- assistant responses
- plans
- concise activity summaries
- concise failure summaries

The main transcript should not become a raw protocol dump, a progress log, or a place where every typed item gets equal visual weight.

Detailed payloads belong in a secondary inspection surface. Raw notifications, request payloads, and unfiltered low-level debugging belong in `:CodexEvents`.
