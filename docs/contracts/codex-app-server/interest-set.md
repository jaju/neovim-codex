# Interest Set

This is the maintained list of app-server surfaces that `neovim-codex` currently cares about.

## 1. Conversation Control

Watched files:

- `Thread.ts`
- `Turn.ts`
- `ThreadStartParams.ts`
- `ThreadStartResponse.ts`
- `ThreadResumeParams.ts`
- `ThreadResumeResponse.ts`
- `ThreadForkParams.ts`
- `ThreadForkResponse.ts`
- `ThreadReadParams.ts`
- `ThreadReadResponse.ts`
- `ThreadListParams.ts`
- `ThreadListResponse.ts`
- `ThreadLoadedListParams.ts`
- `ThreadLoadedListResponse.ts`
- `ThreadArchiveParams.ts`
- `ThreadUnarchiveParams.ts`
- `ThreadUnarchiveResponse.ts`
- `ThreadSetNameParams.ts`
- `ThreadRollbackParams.ts`
- `ThreadRollbackResponse.ts`
- `ThreadCompactStartParams.ts`
- `ThreadUnsubscribeParams.ts`
- `TurnStartParams.ts`
- `TurnStartResponse.ts`
- `TurnSteerParams.ts`
- `TurnInterruptParams.ts`

Why:

- these types define how the plugin creates, resumes, forks, reads, lists, renames, archives, unarchives, compacts, unsubscribes, and drives conversations
- start/resume/fork/unarchive responses seed local runtime state such as approval policy and collaboration mode
- list/read/loaded-list/rollback/turn-start responses feed the local thread and turn store directly
- `thread/fork.ephemeral` is part of the supported fork surface and must stay visible in thread fork UX
- changes here can invalidate the pure Lua request layer and thread/turn state machine

## 2. Streamed Notifications

Watched files:

- `ThreadStartedNotification.ts`
- `ThreadStatusChangedNotification.ts`
- `ThreadArchivedNotification.ts`
- `ThreadNameUpdatedNotification.ts`
- `ThreadUnarchivedNotification.ts`
- `ThreadClosedNotification.ts`
- `TurnStartedNotification.ts`
- `TurnCompletedNotification.ts`
- `TurnDiffUpdatedNotification.ts`
- `TurnPlanUpdatedNotification.ts`
- `ItemStartedNotification.ts`
- `ItemCompletedNotification.ts`
- `AgentMessageDeltaNotification.ts`
- `PlanDeltaNotification.ts`
- `ReasoningSummaryPartAddedNotification.ts`
- `ReasoningSummaryTextDeltaNotification.ts`
- `ReasoningTextDeltaNotification.ts`
- `CommandExecutionOutputDeltaNotification.ts`
- `FileChangeOutputDeltaNotification.ts`
- `ThreadTokenUsageUpdatedNotification.ts`
- `ThreadTokenUsage.ts`
- `TokenUsageBreakdown.ts`
- `CommandExecutionSource.ts`
- `ThreadItem.ts`
- `CommandAction.ts`

Why:

- these types define the canonical turn stream and the item families we project into transcript, activity, details, and footer surfaces
- `commandExecution.source` distinguishes agent-driven commands from explicit user `!` shell commands and unified-exec lifecycle steps
- `collabAgentToolCall.model` and `collabAgentToolCall.reasoningEffort` are now part of our surfaced multi-agent observability
- streamed `thread/tokenUsage/updated` notifications drive the lightweight token summary in the chat footer
- thread archive/name/close notifications and turn diff/plan updates already feed local store state and review UX
- `agentMessage` now carries optional `memoryCitation`; if we decide to surface it beyond the raw item payload, add `MemoryCitation.ts` and `MemoryCitationEntry.ts` explicitly instead of re-parsing free text
- changes here can silently break the protocol-first rendering rule

## 3. Blocking Server Requests

Watched files:

- `CommandExecutionRequestApprovalParams.ts`
- `CommandExecutionRequestApprovalResponse.ts`
- `FileChangeRequestApprovalParams.ts`
- `FileChangeRequestApprovalResponse.ts`
- `PermissionsRequestApprovalParams.ts`
- `PermissionsRequestApprovalResponse.ts`
- `ToolRequestUserInputParams.ts`
- `ToolRequestUserInputResponse.ts`
- `McpServerElicitationRequestParams.ts`
- `McpServerElicitationRequestResponse.ts`
- `ServerRequestResolvedNotification.ts`

Why:

- these are not transcript items
- they are blocking request/response flows that must map to modal or stacked viewer state machines
- permissions approvals and MCP elicitations already route through the shared request protocol layer
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
