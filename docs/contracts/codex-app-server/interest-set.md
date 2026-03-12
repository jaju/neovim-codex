# Interest Set

This is the maintained list of app-server surfaces that `neovim-codex` currently cares about.

## 1. Conversation Control

Watched files:

- `Thread.ts`
- `Turn.ts`
- `ThreadStartParams.ts`
- `ThreadResumeParams.ts`
- `ThreadForkParams.ts`
- `ThreadReadParams.ts`
- `ThreadListParams.ts`
- `ThreadRollbackParams.ts`
- `TurnStartParams.ts`
- `TurnSteerParams.ts`
- `TurnInterruptParams.ts`

Why:

- these types define how the plugin creates, resumes, forks, reads, lists, rolls back, and drives conversations
- `thread/fork.ephemeral` is part of the supported fork surface and must stay visible in thread fork UX
- changes here can invalidate the pure Lua request layer and thread/turn state machine

## 2. Streamed Notifications

Watched files:

- `ThreadStartedNotification.ts`
- `ThreadStatusChangedNotification.ts`
- `TurnStartedNotification.ts`
- `TurnCompletedNotification.ts`
- `ItemStartedNotification.ts`
- `ItemCompletedNotification.ts`
- `AgentMessageDeltaNotification.ts`
- `PlanDeltaNotification.ts`
- `ReasoningSummaryPartAddedNotification.ts`
- `ReasoningSummaryTextDeltaNotification.ts`
- `ReasoningTextDeltaNotification.ts`
- `CommandExecutionOutputDeltaNotification.ts`
- `FileChangeOutputDeltaNotification.ts`
- `ThreadItem.ts`
- `CommandAction.ts`

Why:

- these types define the canonical turn stream and the item families we project into transcript, activity, details, and footer surfaces
- `collabAgentToolCall.model` and `collabAgentToolCall.reasoningEffort` are now part of our surfaced multi-agent observability
- changes here can silently break the protocol-first rendering rule

## 3. Blocking Server Requests

Watched files:

- `CommandExecutionRequestApprovalParams.ts`
- `CommandExecutionRequestApprovalResponse.ts`
- `FileChangeRequestApprovalParams.ts`
- `FileChangeRequestApprovalResponse.ts`
- `ToolRequestUserInputParams.ts`
- `ToolRequestUserInputResponse.ts`
- `ServerRequestResolvedNotification.ts`

Why:

- these are not transcript items
- they are blocking request/response flows that must map to modal or stacked viewer state machines
- `skillMetadata` on command approvals is part of the surfaced request context
- approval and question UX must follow these typed contracts directly

## 4. Experimental Extension Surface

Watched files:

- `DynamicToolSpec.ts`
- `DynamicToolCallParams.ts`
- `DynamicToolCallResponse.ts`
- `DynamicToolCallOutputContentItem.ts`

Why:

- this is the likely long-term extension seam for language-aware deterministic tooling
- it is experimental, so drift here should be expected and quarantined rather than ignored

## When To Update This List

Update the interest set only when one of these becomes true:

1. the plugin starts depending on a new app-server method or type family
2. an old watched type is no longer part of the plugin boundary
3. the same contract is better represented by a smaller watched surface

Do not expand this list just because more protocol exists upstream.
