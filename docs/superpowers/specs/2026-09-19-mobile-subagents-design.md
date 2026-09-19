# Mobile subagents — design

**Date:** 2026-09-19
**Status:** approved in conversation, awaiting implementation plan
**Scope:** `backend/internal` (transcript projection, block-event storage and
routes, one hook mapping), `packages/mobile` (agent card, agent strip, one
new nested screen). No desktop renderer changes: the desktop shows the
agent's own terminal, which already renders subagents.

## 1. Problem

When a Claude Code session dispatches subagents (the Agent tool), the phone
shows nothing about them beyond a plain `Agent` row inside a tool group. The
TUI, by contrast, lists running agents under the composer with their status
and elapsed time and lets the user open each one's transcript. The user asked
for the same on the phone: a visible list of working subagents, a tap that
opens that agent's conversation, and a back gesture that returns to the parent
session.

Cause. The daemon drops every subagent record on both channels:

- The Claude Code transcript mapper returns nothing for a record with
  `isSidechain: true`
  (`backend/internal/adapters/agent/claudecode/transcript.go:64-66`), and the
  transcript supervisor tails only the session's main file, one tail per
  session (`backend/internal/observe/transcript/supervisor.go:153-227`).
- The `subagent-stop` hook is mapped to `drop: true`
  (`backend/internal/adapters/agent/blockdispatch/dispatch.go:61`).
- The Agent tool's result carries the agent id, type, status, duration, tool
  count and token totals in the record's top-level `toolUseResult`, but the
  mapper reads only `message.content` and flattens the result to text
  (`transcript.go:169-187`).

The data exists on disk. Verified on this machine on 2026-09-19 under
`~/.claude/projects/-Users-omaraly-development-AI-Operator/ebfdb96a-…/`:

- Each subagent has its own file `subagents/agent-<agentId>.jsonl` beside the
  main `<sessionId>.jsonl`. Records carry `agentId`, `isSidechain: true`,
  `sessionId` (the parent), and the same `user` / `assistant` / `attachment`
  shapes as the main transcript. The first `user` record's content is the
  prompt the Agent tool was called with.
- The main transcript's `tool_use` for the Agent tool has input
  `{description, prompt, model, run_in_background}`; the matching `user`
  record's `toolUseResult` has keys `agentId, agentType, status, resolvedModel,
  totalDurationMs, totalTokens, totalToolUseCount, usage, content, prompt`.
- The usage collector already discovers these files
  (`backend/internal/service/usage/collector.go:1333`
  `discoverClaudeSubagentPaths`) and validates their layout
  (`collector.go:1635-1643`); the block projection reuses the same rule.

Codex is out of scope: its transcript has no equivalent sidechain files
verified here, and `blocktranscript.Mappers` keeps working unchanged for it.

## 2. Goals

- A running subagent is visible in the parent session screen within one
  reconcile tick (2 s, `supervisor.go:17`) of its first transcript record.
- Tapping a subagent, either its Agent card in the timeline or its row in the
  strip, opens a read-only conversation for that agent with the same block
  rendering, search, copy and collapse as the parent screen. Back returns to
  the parent at its previous scroll position.
- Finished agents stay reachable forever, from their card and from the
  strip's history row.
- The desktop and every other client keep working: the main-session block
  stream is unchanged by default.

Non-goals: sending messages to a subagent; answering a subagent's
permission or question from the nested screen (the dialog belongs to the
parent pane and is answered there); nesting deeper than one level (Claude
Code subagents cannot spawn subagents).

## 3. Daemon

### 3.1 Block events gain an agent scope

Migration `0115_block_events_agent.sql` adds `agent_id TEXT NOT NULL DEFAULT
''` to `block_events` (`0090_block_events.sql:9-27`) and an index on
`(session_id, agent_id, seq)`. `blockevent.Record`
(`backend/internal/service/blockevent/types.go:18`), the store, and
`BlockEventView` (`backend/internal/httpd/controllers/dto.go:306`) carry
`AgentID` / `agentId` (omitted when empty). `domain.BlockTranscriptEvent`
(`backend/internal/domain/blockevent.go:61`) gains `AgentID` and a new
`Detail string` (JSON, see 3.3).

`GET /sessions/{id}/blocks` (`controllers/sessions.go:1233`) takes an
optional `agentId` query parameter. Absent or empty means main only
(`agent_id = ''`), which is today's behaviour. A value returns that agent's
events only. `History` / `HistoryBefore` (`sessions.go:145-146`) gain the
parameter. The mux publishes every event for the session on the existing
per-session subscription; clients partition on `agentId`. Nothing in the
socket protocol changes.

### 3.2 Subagent tails

The supervisor keeps its one main tail per session and adds zero or more
subagent tails per Claude Code session. On each reconcile, after resolving
the main path, it lists `filepath.Join(filepath.Dir(main),
strings.TrimSuffix(filepath.Base(main), ".jsonl"), "subagents",
"agent-*.jsonl")`, the same layout the usage collector validates. Each new
file becomes a `tail` with `agentID` set from the file name. Subagent tails
are pumped, watched and retired with the session exactly like the main tail.

Offsets are keyed by session id today (`tail.go:27-30`). Subagent tails use
the key `<sessionId>#<agentId>` so a daemon restart resumes each file where
it stopped; no table change is needed because the key column is free text.

The mapper is called through a new `MapSidechainRecord`, which is
`MapTranscriptRecord` without the `isSidechain` early return and which
stamps `AgentID` on every event. Records in the main file that carry
`isSidechain: true` are still dropped, so the main stream never gains
duplicate content. Inside an agent's transcript, the `tool_use` /
`tool_result` pairs, `text`, `thinking` and `turn_model` records map exactly
as they do for the main file, so the phone renders them with zero new block
kinds.

### 3.3 Agent identity on the parent stream

Claude Code writes `subagents/agent-<id>.meta.json` beside each agent
transcript with `agentType`, `description`, `toolUseId`, `model` and
`requestShape` (verified on this machine, 2026-09-19). When the supervisor
first sees an agent file (stored cursor at 0) it reads that meta file and
emits one main-scope `agent_start` event: `SourceID` = agent id, `ToolUseID`
from the meta file, `ToolName` = `Agent`, `Detail` = the meta fields plus
`agentId`. Because it carries the tool use id, the phone correlates it onto
the same block as the Agent tool's `tool_start`, so the card knows its agent
id from the first tick, live or on a cold open. A missing meta file just
means no `agent_start`; the card then falls back to the prompt match below.

The Agent tool's `tool_result` additionally sets `Detail` to the JSON lifted
from the record's `toolUseResult` when `toolUseResult.agentId` is non-empty:
`agentId` always, `agentType`, `status`, `resolvedModel` when non-empty, and
`totalDurationMs`, `totalToolUseCount`, `totalTokens` only when non-zero. A
background agent's result arrives immediately with `status: "async_launched"`
and zero totals; the phone treats that status as still running.

Two records mark an agent finished, both published on the MAIN scope (empty
`agentId`) with the agent id in `sourceId`, so they are part of the parent's
history and a cold open sees them:

- The `subagent-stop` hook maps to `agent_stop` with `agent_id` from the
  payload (`backend/internal/cli/hooks.go:157-163`).
- The parent transcript's hand-back record, a `user` text starting with
  `<agent-message from="<id>">`, maps to `agent_stop` as well. This covers
  agents that finished while the daemon was not running.

### 3.4 Linking a live tail to its Agent card

The `agent_start` event above is the primary link. As a fallback for agents
without a meta file, the sidechain mapper emits a `prompt_submit` transcript
event for a `user` record of the agent file whose content is text (not a
`tool_result`), with the prompt as `Text`; the phone matches the first such
prompt against Agent blocks whose `toolInput.prompt` equals it. An agent
whose prompt matches nothing still appears in the strip under its
`agentType` (or "Agent") so it is never hidden.

## 4. Mobile

### 4.1 Data

`BlockEventModel` gains `agentId` and `detail` (raw JSON string).
`GetSessionBlocksParams` gains `agentId`. `BlocksCubit` takes an optional
`agentId`; its live filter becomes `sessionId == this.sessionId &&
(event.agentId ?? '') == (this.agentId ?? '')`, and `refresh` / `loadOlder`
pass the parameter. Nothing else in the cubit changes, so every existing
test still holds.

`SessionBlock` gains `agentId`. A new `AgentBlockDetail` in
`session_block.dart` holds `description, prompt, model, runInBackground`
(from `toolInput`) and `agentId, agentType, status, resolvedModel,
durationMs, toolUseCount, totalTokens` (from the `agent_start` and result
details). The assembly (`block_assembly.dart`) builds it when `toolName ==
'Agent'`, merges `agent_start` and `tool_result` details onto it, and marks
the detail `status: completed` on an `agent_stop` naming its agent id. An
agent whose status is `async_launched` counts as running until then.

A new pure function `subagentsOf(List<SessionBlock> mainBlocks,
Map<String, SubagentSummary> tails)` in `lib/feature/blocks/logic/
subagents.dart` returns the ordered list the strip and the cards render:
one entry per Agent block, joined to a live tail by `agentId` when known or
by prompt otherwise, plus one entry per tail that matched nothing.
`SubagentSummary` is what the phone knows about a tail from the parent
stream alone: its `agentId`, first prompt, first and last `createdAt`, and
whether an `agent_stop` arrived. `BlocksCubit` for the main scope collects
these summaries from the `agentId`-scoped events it already receives on the
socket and would otherwise discard, and exposes them; it does not assemble
subagent blocks itself.

### 4.2 Agent card

In `block_card.dart`, a tool block whose detail is `AgentBlockDetail`
renders as `RailKind.agent`: description as the title, `agentType · model`
as the subtitle, a status dot using `blockStatusColor`, and on the right a
mono meta line: `running · 2m14s · 7 tools` while running (the timer
reuses the session header's elapsed-time ticker), or
`done · 6m02s · 41 tools` / `failed` when finished. Tapping anywhere on the
card pushes the subagent screen. It keeps long-press actions. It stays
inside the tool group when the group is collapsed, so "Using 2 tools"
counts it, but the group's compact row shows the agent description rather
than the bare word `Agent`.

### 4.3 Agent strip

`SubagentStrip` sits between `BlocksBody` and the composer in
`terminal_body.dart` and is built only when `subagentsOf` is non-empty. One
row, 44 pt tall, horizontally scrolling: running agents first, each a pill
with a pulsing status dot, the description ellipsised at 22 characters and
the elapsed time in mono; then, when any agent has finished, a trailing
`N done` pill. Tapping a running pill opens that agent. Tapping `N done`
expands a bottom sheet listing finished agents with description, type,
duration and tool count, newest first; tapping a row opens it. Colors and
type are the tool-group header's (`tool_group_header.dart`): secondary text,
`skin.tintRed` / `skin.red` for a failed agent's pill.

### 4.4 Subagent screen

Route `RoutesStrings.subagent = '/session/agent'`, arguments `sessionId`,
`agentId`, and the `AgentBlockDetail` (may be partial). The app bar mirrors
the session screen: back chevron, the description as title (falls back to
`agentType`, then `Agent`), `agentType · model · status` as the subtitle in
the same mono style, and above the title a one-line breadcrumb `↩ <parent
session name>` in tertiary text so the nesting reads at a glance. The body
is `BlocksBody` under a `BlocksCubit(sessionId, agentId: agentId)` and a
`SessionCommandCubit` for the parent session (needed by `BlocksBody`'s
providers; its row is not shown). No composer. Pull-to-refresh is the
cubit's `refresh`. The block list, search bar, sticky header, selection and
copy come for free.

Permission and question blocks inside a subagent render with their buttons
hidden and the line `Answer in the parent session`; they resolve by the
same rules as the parent's (turn boundary, tool completion, activity patch)
because the same assembly runs.

## 5. Error handling

- A subagent file that disappears (Claude Code cleans up) retires its tail
  on the next tick; already projected events stay in the store.
- A malformed `toolUseResult` yields no detail; the card falls back to
  `Agent` with the description from `toolInput`, and linking waits for
  `agent_stop` or never happens. The agent remains reachable from the strip.
- `GET /blocks?agentId=` for an unknown agent returns an empty list, not an
  error; the screen shows the existing empty state.
- The strip never blocks the composer: it collapses to zero height when
  `subagentsOf` is empty and is not drawn in selection mode.

## 6. Testing

Go:
- `transcript_test.go`: `MapSidechainRecord` on a fixture copied from a real
  `agent-*.jsonl` (first 20 lines, redacted) yields `prompt_submit` first,
  then the same kinds as the main mapper, all with `AgentID`. The main mapper
  still drops sidechain records.
- `transcript_test.go`: the Agent `tool_result` fixture produces `Detail`
  with the seven keys; a non-agent result produces none.
- `supervisor_test.go`: a session whose directory gains
  `subagents/agent-x.jsonl` between ticks acquires a second tail, its events
  reach the sink with `AgentID: "x"`, offsets are keyed `<id>#x`, and the
  tail retires with the session.
- `blockdispatch/dispatch_test.go`: `subagent-stop` maps to `agent_stop`.
- `controllers/sessions_block_events_test.go`: `agentId` filter; default
  excludes agent rows; the view carries `agentId`.
- `service/blockevent`: store round-trips `AgentID`.

Mobile (`flutter analyze`, `flutter test`):
- `block_assembly_test.dart`: Agent tool builds `AgentBlockDetail`; result
  merges the metadata; `agent_stop` completes an unmatched agent.
- `subagents_test.dart`: linking by `agentId`, by prompt, unmatched tails,
  ordering (running first, then finished newest first).
- `blocks_cubit_test.dart`: an `agentId`-scoped cubit ignores main events and
  vice versa; the main cubit collects `SubagentSummary` from agent events.
- Widget tests: agent card meta line and tap navigates; strip appears only
  with agents, `N done` opens the sheet; subagent screen shows breadcrumb and
  no composer; permission inside an agent shows `Answer in the parent
  session` and no buttons.

Real-app check before merge: pair the phone to a rebuilt daemon, run a
session that dispatches two background agents, and confirm the strip shows
both within a few seconds, each opens to a live transcript, and both move to
`2 done` when they finish.
