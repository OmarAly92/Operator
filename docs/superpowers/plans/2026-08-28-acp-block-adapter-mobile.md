# Plan 5a — ACP block adapter, mobile

Status: written
Date: 2026-08-28
Spec: `docs/superpowers/specs/2026-08-27-session-blocks-design.md`, step 7
Scope: `packages/mobile`, plus the shared fixtures in `testdata/blocks`
Depends on: plans 1, 2. Independent of 3, 4a, 4b, 6, 7, 8, 9.
Parallel sibling: **plan 5b (desktop)**. Read *The frozen contract* below before
starting; it is the only surface the two plans share.

## What this delivers

A `chat` session renders through the **same block screen** a `tui` session does. One
block model, one set of block components, two source adapters — hooks and ACP — and no
second timeline.

This is the plan the spec calls "where the duplication actually dies." It is also, per
the amendments of 2026-08-28, **the fidelity plan**: `chat` sessions carry the agent's
full output, so this is what puts assistant prose, reasoning, plans, compaction and
structured tool detail on the block screen. Cutting this plan is not a saving.

## Read this before you plan any work

**The backend already emits everything this plan needs. Do not change it.**

`backend/internal/ports/chat.go:613` defines a provider-neutral `ChatEventKind` with 25
members. Among them, already implemented:

| Kind | What it gives the block model |
| --- | --- |
| `turn.started` / `turn.completed` | turn grouping and turn timing |
| `message.delta` / `message.completed` | assistant prose |
| `reasoning.delta` | the `reasoning` block kind |
| `activity.started` / `activity.completed` | tool blocks with lifecycle |
| `thread.compacted` | the `compaction` block kind |
| `turn.plan` | the `todo` block kind |
| `usage` | context-window metering |
| `approval.requested` / `approval.resolved` | permission blocks |
| `input.requested` / `input.resolved` | elicitation |
| `command.output.delta` | real command output on a tool block |
| `turn.diff` | per-turn changed files |

The persisted shapes are equally complete. `backend/internal/domain/conversation.go:514`
— `ConversationMessage` carries `{id, conversationId, turnId, sequence, revision, role,
origin, text, streaming, providerItemId, clientMessageId, createdAt, updatedAt}`.
`conversation.go:539` — `ConversationActivity` carries `{id, conversationId, turnId,
sequence, revision, kind, status, summary, detail, requestId, providerItemId,
commandOutput, commandOutputTruncated, streamedText, streamedTextTruncated, createdAt,
updatedAt}`.

`domain.ActivityKind` (`conversation.go:86`) already has eleven members: `command`,
`file_change`, `plan`, `reasoning`, `approval`, `usage`, `error`, `system`, `mcp_tool`,
`auto_review`, `user_input`.

**Therefore this plan is entirely client-side.** No Go change, no migration, no
`npm run api`, no `npm run sqlc`, no `npm run lint`. If a task appears to need one, you
have misread something — stop and say so rather than widening scope.

**The spec's model amendments land here.** The 2026-08-28 amendments added `reasoning`,
`todo` and `compaction` kinds, turn grouping and structured tool detail to the block
model, and recorded that they are cheaper before this plan than after. They are part of
this plan rather than a prerequisite because this is the plan whose source produces
them: the hook adapter has no `compaction` event to emit.

## Working in parallel with plan 5b

5a and 5b run in separate worktrees and share **no source file**. Dart and TypeScript
models, adapters, grouping functions, cubits and widgets are all per-client.

The one shared directory is `testdata/blocks/`, and *The frozen contract* pins its
contents exactly so both agents produce identical files. Whoever merges first wins;
the second finds the files present, verifies them, and moves on.

**If you finish before 5b:** do not touch `frontend/`. A desktop change from this
worktree is a merge conflict with a plan that is still running.

## The frozen contract (identical in plan 5a and plan 5b — do not deviate)

Plans 5a and 5b run in parallel worktrees and touch no shared source file. They do
share **three things**, reproduced here byte-identically in both plans. If your copy
disagrees with the other plan's copy, the plans are out of sync and you must stop and
say so rather than picking one.

If any file in this section **already exists on your base branch**, the other agent
merged first. Verify it matches this contract exactly and move on. Do not rewrite it,
and do not "improve" it.

### 1. The extended block model

Both clients add, to their existing `SessionBlock`:

- `turnId` — optional string.
- Three kinds, appended to the existing `prompt | assistant | tool | permission |
  notice`: **`reasoning`**, **`todo`**, **`compaction`**.
- `detail` — optional, a closed union with exactly these variants:

| Variant | Fields |
| --- | --- |
| `shell` | `command`, `output`, `exitCode` |
| `file_change` | `files[{path, oldPath, status, additions, deletions}]`, `truncated` |
| `plan` | `steps[{text, status}]` |
| `mcp_tool` | `server`, `tool`, `args`, `result` |
| `usage` | `contextUsed`, `contextWindow`, `inputTokens`, `outputTokens` |
| `compaction` | `trigger` (`auto` \| `manual`), `preTokens` |
| `unknown` | `raw` |

**The `unknown` variant is not optional and is not a placeholder.** It is what lets a
provider ship a new activity kind without this code dropping the block. A mapping that
throws, returns null, or skips an unrecognized kind is a plan failure.

Each client also adds one display function, mirroring paseo's
`buildToolCallDisplayModel`: `blockDisplay(block) -> {displayName, summary, errorText}`.
The block card calls it instead of formatting inline. This is what stops the two
clients drifting on presentation, and it is cheap only while there is one source.

### 2. Turn grouping rules

A pure function per client: `groupBlocksByTurn(blocks) -> TurnGroup[]`, where a
`TurnGroup` is `{turnId?, blocks, startedAt, completedAt, durationMs}`.

1. **Canonical turn id wins.** Where both neighbours carry a `turnId`, they are in the
   same turn iff the ids are equal.
2. **Otherwise a new turn starts at each `prompt` block.** Hook-sourced blocks carry no
   turn id, so this rule keeps `tui` sessions grouped with no backend change.
3. **A visible response may span several canonical turns**, because some prompts are
   system-injected and never appear as a block. Grouping strictly by turn id would
   render those as headless turns.

Rule 3 means **two functions, not one with a flag**: `continuesTurn` (strict — used for
boundaries and any future rewind) and `continuesResponse` (relaxed — used for
run-together display). The spec is explicit that conflating them is the bug.

Turn timing is **derived here, never stored per block**: `startedAt` from the group's
first block, `completedAt` from its last, and a running start for an unfinished turn.

This is what makes a conversational turn visibly finish — the symptom from the first
live run, where a prompt with no tool calls rendered as a prompt and then silence.

### 3. Shared fixtures

Four new files in `testdata/blocks/`, asserted by **both** suites
(`frontend/src/renderer/lib/block-assembly.fixtures.test.ts` and
`packages/mobile/test/feature/blocks/logic/block_assembly_fixtures_test.dart`).

ACP fixtures use `{"snapshot": {...}, "expected": [...]}`, not the `{"records": [...]}`
shape the hook fixtures use, because the input is a conversation snapshot rather than a
hook-event stream. Add a second fixture list to each suite rather than widening the
existing one.

**`acp_stream_basic.json`**

```json
{
  "snapshot": {
    "sessionId": "s-1",
    "harness": "claude-code",
    "items": [
      { "id": "m-1", "type": "message", "turnId": "t-1", "sequence": 1, "revision": 0, "role": "user", "text": "run the tests" },
      { "id": "a-1", "type": "activity", "turnId": "t-1", "sequence": 2, "revision": 0, "activityKind": "reasoning", "status": "completed", "streamedText": "checking the suite" },
      { "id": "a-2", "type": "activity", "turnId": "t-1", "sequence": 3, "revision": 1, "activityKind": "command", "status": "completed", "summary": "npm test", "commandOutput": "ok 42 tests" },
      { "id": "m-2", "type": "message", "turnId": "t-1", "sequence": 4, "revision": 2, "role": "assistant", "text": "all green", "streaming": false }
    ]
  },
  "expected": [
    { "id": "m-1", "kind": "prompt", "status": "ok", "turnId": "t-1", "title": "Prompt", "body": "run the tests" },
    { "id": "a-1", "kind": "reasoning", "status": "ok", "turnId": "t-1", "body": "checking the suite" },
    { "id": "a-2", "kind": "tool", "status": "ok", "turnId": "t-1", "detail": "shell", "body": "ok 42 tests" },
    { "id": "m-2", "kind": "assistant", "status": "ok", "turnId": "t-1", "body": "all green" }
  ]
}
```

**`acp_stream_tool_failure.json`** — a `command` activity with `status: "failed"`, a
non-zero `exitCode` in its detail, `commandOutputTruncated: true`, and an assistant
message after it. Asserts `status: "failed"`, that the truncation flag survives into
the block, and that a failed tool does not fail its turn's other blocks.

**`acp_stream_compaction.json`** — a snapshot whose `compactedAt` is set, with items
on both sides of it. Asserts exactly one `compaction` block, positioned by
`compactedAt` rather than appended at the end.

**`acp_stream_nested_subagent.json`** — a parent `mcp_tool` activity and two children
correlated by `parentToolUseID`, plus a grandchild. Asserts one level of nesting, the
grandchild flattened into the nearest nesting parent, and no infinite loop when a
parent id points at its own descendant.

**The contract, stated once:** a failing fixture is never fixed by editing the fixture.
If your client disagrees with a fixture, either your adapter is wrong or the other
client's is; find out which.

## Facts established by reading the real thing

**The block model today.** `packages/mobile/lib/feature/blocks/logic/session_block.dart`:

```dart
enum BlockKind { prompt, assistant, tool, permission, notice }
enum BlockStatus { running, ok, failed, blocked }

class SessionBlock extends Equatable {
  final String id;
  final int firstSeq;
  final int lastSeq;
  final BlockKind kind;
  final BlockStatus status;
  final String title;
  final String body;
  final String? toolName;
  final String? errorType;
  final int truncatedLines;
  final bool redacted;
  final String? createdAt;
  // copyWith({status, body, lastSeq, errorType, truncatedLines, redacted, createdAt})
}
```

`BlockHarnesses.covers(harness)` mirrors `blockdispatch.Mappers` — `claude-code`,
`grok`, `codex`. **This gate is about hooks and must not be applied to a chat
session.** Task 4 has a test for it, because getting it wrong makes chat blocks
silently unavailable for opencode and droid.

**The conversation snapshot.**
`lib/feature/chat/data/model/conversation_snapshot_model.dart:231` —
`ConversationSnapshotModel` carries `{conversationId, sessionId, harness, mode,
controllerState, controllerError, latestSequence, oldestSequence, hasMoreBefore, turns,
items, settings, title, usage, rateLimits, compactedAt, modelReroute, account,
threadState, mcpServers, capabilities}`.

`items` is `List<ConversationItemModel>`, a `sealed class`
(`conversation_item_model.dart:4`) with base fields `{id, turnId, sequence, revision,
createdAt}` and two subclasses:

- `ConversationMessageModel{role, origin, text, streaming, delivery, senderLabel}`
- `ConversationActivityModel{activityKind, status, summary, detail, requestId,
  providerItemId, decisions}`

**`capabilities: List<String>` already exists on the snapshot.** It is the capability
primitive the spec's *Block actions* section requires. Task 6 gates every action on it
and invents nothing.

**Turn grouping and activity nesting already exist**, in
`lib/feature/chat/logic/timeline_model.dart`:

- `groupConversationByTurn(...)` -> `List<ConversationGroup>` (line 75)
- `activityHierarchy(...)` -> `List<ActivityNode>` (line 194), with `_activityCycle`
  (line 232) guarding a parent cycle
- `conversationMarkers(...)` (124), `canRollbackTurn(...)` (173),
  `activityStartsExpanded(...)` (183)

**Move these, do not rewrite them.** They are tested logic that already solves Task 2
and the nesting half of Task 3. Their tests move with them.

**Routing today.**
`lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart:93`
returns `ChatScreen(...)` when `session?.mode == 'chat'`, and a `MultiBlocProvider`
stack (`TerminalCubit`, `SessionViewCubit`, `BlocksCubit`, `PreviewCubit`) wrapping
`TerminalScreen` when `== 'tui'`. Chat never reaches the block screen.

**`BlocksCubit`** (`lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart`)
is constructed `BlocksCubit(MuxClient, BlocksRepository, sessionId, {harness})`,
subscribes to `_mux.blockEvents`/`status`/`sessionPatches` in its constructor, and calls
`_mux.unsubscribeBlocks(sessionId)` in `close()`.

**Test conventions.** `mocktail`, `class _MockX extends Mock implements X {}`,
`registerFallbackValue` in `setUpAll`, one stream controller per mux stream. The exact
shape is `test/feature/blocks/presentation/blocks_cubit_test.dart:15-51`. Follow it.

**Package conventions that apply to every task here** (`CLAUDE.md`): Cubit only, never
`Bloc` with events. Static-only classes are `sealed class X`. No `freezed`,
`json_serializable` or `build_runner` in this plan — the drift exception is plan 9's
and does not extend here. Models hand-written, all fields nullable. One params class per
method under `data/model/params/`, never shared. Parameterized paths get static methods
on `EndPoints`. Feature code never imports `flutter_screenutil`. User-facing copy is
inline English. `AppSkin` through `context.skin`, type as `AppTextStyle.style<Size><Weight>`.

## Verification gate

From `packages/mobile`, after every task:

```bash
flutter analyze
flutter test
```

`flutter analyze` must print "No issues found!". Neither gate covers `ios/`, `android/`
or a vendored package, and this plan touches none of them.

## Task 1 — Extend the block model and add the display function.

Implement section 1 of *The frozen contract* in Dart.

`BlockDetail` is a `sealed class` with the seven variants, per the package convention
for closed sets — and because `switch` exhaustiveness is what catches a missed variant
at analyze time rather than at runtime.

Add `blockDisplay(SessionBlock) -> BlockDisplay` in `lib/feature/blocks/logic/`, and
change `block_card.dart` to call it instead of formatting inline.

**The hook adapter must not change behaviour.** `block_assembly.dart` gains
`turnId: null` and `detail: BlockDetailUnknown(...)` on the blocks it already produces,
and every existing test and hook fixture passes untouched. **If a hook fixture needs
editing, you have changed behaviour — stop.**

Add `acp_detail_variants.json` exercising every variant including `unknown`.

## Task 2 — Turn grouping.

Implement section 2 of *The frozen contract* as
`lib/feature/blocks/logic/block_turns.dart`.

Move `groupConversationByTurn` out of `feature/chat/logic/timeline_model.dart`,
generalized over `SessionBlock` instead of `ConversationItemModel`. Do not write a
second grouping function.

Render a finished turn group's duration and an unfinished one as running. Assert both —
this is the "a conversational turn never says it finished" symptom from the first live
run, and a test that only covers the finished case would not have caught it.

## Task 3 — The ACP adapter.

Create `lib/feature/blocks/logic/conversation_blocks.dart`:

```dart
List<SessionBlock> blocksFromConversation(ConversationSnapshotModel snapshot);
```

Pure and synchronous: no Dio, no cubit, no widgets. It consumes the snapshot the chat
repository already returns and produces the same `SessionBlock` list the hook adapter
produces.

### The mapping table

| Conversation item | Block |
| --- | --- |
| message, role user | `prompt` |
| message, role assistant | `assistant`, `status: streaming ? running : ok` |
| activity `reasoning` | `reasoning`, body from `streamedText` |
| activity `command` | `tool`, `detail: shell`, body from `commandOutput` |
| activity `file_change` | `tool`, `detail: file_change` |
| activity `mcp_tool` | `tool`, `detail: mcp_tool` |
| activity `plan` | `todo`, `detail: plan` |
| activity `approval` | `permission`, `status: blocked` until resolved |
| activity `user_input` | `permission`, distinct title; **not** an approval |
| activity `auto_review` | `notice` — a decision made *for* the user, visible after the fact |
| activity `usage` | `notice`, `detail: usage` |
| activity `error` | `notice`, `status: failed` |
| activity `system` | `notice` |
| snapshot `compactedAt` | `compaction` block, positioned by its timestamp |

### Six rules that are not obvious, each needing its own test

1. **`sequence` is the block's `firstSeq`/`lastSeq`, and the item's `id` is the block
   id.** Never mint either — the spec's "ids are minted at the source" rule. A consumer
   that invents ids cannot deduplicate on reconnect.
2. **`revision` is not `sequence`.** A message rewritten by streaming keeps its sequence
   and bumps its revision. The block updates in place; it never appends.
3. **Empty settled text does not erase streamed text.** `conversation.go:731` states this
   for the backend and the same rule applies here: a settle carrying nothing means the
   provider settled nothing, not that what the user watched arrive was wrong.
4. **`commandOutput` and `streamedText` must not merge.** The domain comment at
   `conversation.go:566` explains why — one is the program's bytes, the other is the
   agent's — and a reader must be able to tell "the agent typed this" from "the program
   printed this".
5. **`commandOutputTruncated` / `streamedTextTruncated` map to the block's truncation
   reporting.** Losing "this was cut" silently is exactly the failure the spec's
   *Unbounded output* section exists to prevent.
6. **A rolled-back turn is excluded from the timeline but stays countable.**
   `ConversationTurn.RolledBackAt` (`conversation.go:441`) means the agent no longer
   remembers the exchange, so its messages and activities are left out — but the turn
   renders as a `notice` saying how much was undone. History that silently shrinks is
   the thing that domain comment says not to do.

### Nesting

`parentToolUseID` correlation gives **one level** of child blocks on a parent tool
block, per the spec's subagent amendment. Deeper descendants flatten into the nearest
nesting parent — a tree UI is a different design and this list is not one. Guard against
a parent cycle.

Reuse `activityHierarchy` and `_activityCycle` by moving them into
`lib/feature/blocks/logic/`, generalized over blocks. Their tests move too.

**Tests** (`test/feature/blocks/logic/conversation_blocks_test.dart`): one per mapping
row, one per numbered rule, and three nesting cases — one level, flattened grandchild,
and a cycle that must terminate.

Add the four `acp_stream_*` fixtures and a second fixture list in
`test/feature/blocks/logic/block_assembly_fixtures_test.dart`. Do not widen the
existing list — the two input shapes differ.

## Task 4 — Route chat sessions through the block screen.

Add `ConversationBlocksCubit` under
`lib/feature/blocks/presentation/blocks_screen/logic/`, subscribing to the existing
`feature/chat/data/data_source/chat_event_data_source.dart` and `ChatRepository`, and
emitting `List<SessionBlock>` through `blocksFromConversation`.

**Do not extend `BlocksCubit`.** It is constructed with `MuxClient` and
`BlocksRepository` and pins its mux subscription in `close()`; a second source would
make its constructor branch on mode and its teardown conditional. Two cubits, one
screen, one model.

Register it in `service_locator.dart`'s `_blocksFeatureSetup()`, alongside the existing
`registerFactoryParam<BlocksCubit, String, String?>`.

Change `session_route_screen.dart:93` so the `chat` branch builds the block screen with
`ConversationBlocksCubit` instead of returning `ChatScreen(...)`.

**Four things to get right, each with a test:**

1. **Support is not `BlockHarnesses.covers(harness)`.** That set describes *hook*
   coverage. A chat session is supported iff it has a conversation. **Write this test
   first.**
2. **"Unavailable" is not "error".** The daemon distinguishes `SESSION_MODE_MISMATCH`
   and `CHAT_CONTROLLER_NOT_READY` from transient failures. Render them as an
   explanation — never as a failure, never as a spinner that does not resolve.
3. **There is no Raw toggle in chat mode.** `chat` has no agent terminal, so there is
   nothing to toggle to. Hide the control; do not disable it. `SessionViewCubit` does
   not belong on a chat session.
4. **The composer sends structured messages**, through the chat repository's send path,
   not the `tui` send route. The composer takes a send function rather than choosing
   one.

## Task 5 — Retire the timeline widgets.

Only now, with the screen green, delete.

**Delete**, with their tests, from
`lib/feature/chat/presentation/chat_screen/ui/widgets/`: `chat_timeline.dart`,
`timeline_item.dart`, `activity_row.dart`, `activity_run.dart`, `activity_meta.dart`,
`turn_summary.dart`, `plan_card.dart`, `file_change_list.dart`, `chat_markdown.dart`,
`highlighted_code_text.dart`, and the timeline half of `chat_body.dart`.

**Keep** — these are interaction, not timeline, and deleting them removes shipped
features:

- `chat_composer.dart` and `logic/composer_suggestions.dart`, until Task 6 merges them
- `approval_card.dart`, `user_input_card.dart`, `logic/elicitation_model.dart`
- `chat_settings_sheet.dart`, `conversation_menu_sheet.dart`,
  `conversation_map_sheet.dart`, `live_turn_bar.dart`, `chat_meta_bar.dart`
- `conversation_banners.dart`, `inline_banner.dart` — controller state, auth, rate
  limits and reroutes are not timeline entries
- **all of `feature/chat/data/**`**, unchanged
- **all of `feature/chat/voice/**`**, untouched

**Do not delete a file to reach a count.** The spec's "retires most of the 38 files"
refers to desktop and overstates it there too; here, expect roughly ten widgets.

## Task 6 — Capability-gated actions, and merge the composers.

Wire the kept interactions as block actions, gated on the snapshot's
`capabilities: List<String>`:

- a `permission` block declares approve/deny **only** when capabilities say the
  provider supports it;
- a `user_input` block opens the elicitation surface;
- a turn group offers rollback only when `canRollbackTurn(...)` — already implemented at
  `timeline_model.dart:173` — says so.

**Never render an action the source cannot perform.** An action that fails after the
user taps it is worse than an absent one, and per-mode gating is too coarse: within
`chat`, providers differ.

Then merge attachments, slash-command suggestions and steering into the block composer,
behind the same capability check. **Last, not first** — merging before the screen
renders blocks means debugging two things at once.

## Risks

- **The support gate.** `BlockHarnesses.covers` returning false for a chat session shows
  "blocks unavailable" on a session with a perfectly good conversation. Test it first.
- **Deleting an interaction by mistake.** Mitigated by the explicit Keep list and by
  Task 5 deleting nothing until Task 4 is green.
- **Fixture divergence with 5b.** A failing fixture is never fixed by editing the
  fixture. If your client disagrees, either your adapter is wrong or desktop's is.
- **Streaming churn.** A chat session re-derives every block on every SSE event. That is
  acceptable for correctness and is **not** fixed here — the spec's coalescing and
  history/live-split amendments address it, and doing that work inside this plan would
  confuse a mapping bug with a performance one. Record the measurement; do not optimize.
- **Scope creep into the viewport.** This plan changes what blocks exist, never how they
  scroll.
