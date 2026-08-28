# Plan 5 — ACP adapter: chat sessions render as blocks

Status: written
Date: 2026-08-28
Spec: `docs/superpowers/specs/2026-08-27-session-blocks-design.md`, step 7
Scope: `frontend/src/renderer`, `packages/mobile`, `testdata/blocks`
Depends on: plans 1, 2, 3. Independent of 4a, 4b, 6, 7, 8, 9.

**One plan, both clients, deliberately.** An earlier draft split this by client the
way plan 4 was split. That was wrong: 4a and 4b shared a *requirements list*, which
each side can satisfy alone, while this plan's two adapters share an *output
contract* — the `testdata/blocks/` fixtures, asserted by both suites. Neither a
Dart-only nor a TypeScript-only agent can run the check that matters, so the
agreement would only be tested when the second branch merged. Here, one agent runs
`flutter test` and vitest against the same fixtures and sees any disagreement
immediately.

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

## Facts established by reading the real thing

### The block model today

`frontend/src/renderer/lib/session-block.ts`:

```ts
export type BlockKind = "prompt" | "assistant" | "tool" | "permission" | "notice";
export type BlockStatus = "running" | "ok" | "failed" | "blocked";

export type SessionBlock = {
	id: string;
	firstSeq: number;
	lastSeq: number;
	kind: BlockKind;
	status: BlockStatus;
	title: string;
	body: string;
	toolName?: string;
	errorType?: string;
	truncatedLines: number;
	redacted: boolean;
	createdAt?: string;
};

export const BLOCK_HARNESSES: ReadonlySet<string> = new Set(["claude-code", "grok", "codex"]);
export function blocksCoverHarness(harness: string | undefined): boolean;
```

`packages/mobile/lib/feature/blocks/logic/session_block.dart` mirrors it exactly —
`enum BlockKind { prompt, assistant, tool, permission, notice }`, the same fields, and
a `copyWith` whose parameters are `{status, body, lastSeq, errorType, truncatedLines,
redacted, createdAt}`. Dart's gate is `BlockHarnesses.covers(harness)`.

`BLOCK_HARNESSES` mirrors `blockdispatch.Mappers`. **That gate is about hooks and must
not be applied to a chat session** — a chat session's blocks come from ACP. Tasks 6
and 7 each test this, because getting it wrong makes chat blocks silently unavailable
for opencode and droid.

### Desktop conversation access

`frontend/src/renderer/hooks/useConversation.ts:85` — a `useInfiniteQuery` over
`GET /api/v1/sessions/{sessionId}/conversation`, `CONVERSATION_PAGE_SIZE = 200`, paged
by `beforeSequence`, merged by `mergeConversationPages` (780) and shaped by
`toSnapshot` (661), `toMessage` (805), `toActivity` (827). Its result:

```ts
export interface ConversationQueryResult {
	snapshot?: ConversationSnapshot;
	isLoading: boolean;
	/** Set when the session exists but has no chat conversation to show. */
	unavailable?: { code: string; message: string };
	error?: string;
	hasOlder: boolean;
	isLoadingOlder: boolean;
	loadOlder: () => void;
}
```

It already separates permanent failures from transient:

```ts
const PERMANENT_CODES = new Set([
	"SESSION_MODE_MISMATCH",
	"SESSION_NOT_FOUND",
	"SESSION_MODE_UNSUPPORTED",
	"CHAT_AUTH_REQUIRED",
]);
```

returning `unavailable` for `SESSION_MODE_MISMATCH` and `CHAT_CONTROLLER_NOT_READY`.
**Preserve that distinction exactly.** It is the difference between "this session is
TUI, that is why there is no conversation" and a spinner that never resolves.

Live updates are **invalidations, not deltas**: CDC events on `/api/v1/events`
invalidate `conversationQueryKey(sessionId)` (`lib/event-transport.ts:95`) and the
snapshot refetches. This plan does not change that.

`BlocksView`'s props are already right (`components/blocks/BlocksView.tsx:6`) —
`{blocks, isLoading, isLoadingOlder, hasOlder, error, harness, sessionId, supported,
onLoadOlder, onRetry}`. `useConversation`'s `hasOlder`/`isLoadingOlder`/`loadOlder`
mean the same thing and map straight through. **Do not change this prop shape**; plan
4b's viewport work sits behind it.

### Mobile conversation access

`lib/feature/chat/data/model/conversation_snapshot_model.dart:231` —
`ConversationSnapshotModel{conversationId, sessionId, harness, mode, controllerState,
controllerError, latestSequence, oldestSequence, hasMoreBefore, turns, items,
settings, title, usage, rateLimits, compactedAt, modelReroute, account, threadState,
mcpServers, capabilities}`.

`items` is `List<ConversationItemModel>`, a `sealed class`
(`conversation_item_model.dart:4`) with base fields `{id, turnId, sequence, revision,
createdAt}` and two subclasses:

- `ConversationMessageModel{role, origin, text, streaming, delivery, senderLabel}`
- `ConversationActivityModel{activityKind, status, summary, detail, requestId,
  providerItemId, decisions}`

**`capabilities: List<String>` already exists on the snapshot.** It is the capability
primitive the spec's *Block actions* section requires. Task 8 gates every action on it
and invents nothing.

### Mobile already has turn grouping and activity nesting

In `lib/feature/chat/logic/timeline_model.dart`:

- `groupConversationByTurn(...)` -> `List<ConversationGroup>` (line 75)
- `activityHierarchy(...)` -> `List<ActivityNode>` (194), with `_activityCycle` (232)
  guarding a parent cycle
- `conversationMarkers(...)` (124), `canRollbackTurn(...)` (173),
  `activityStartsExpanded(...)` (183)

**Move these, do not rewrite them.** They are tested logic that already solves Task 2
and the nesting half of Task 4 for the mobile side, and `_activityCycle` is the
reference the TypeScript cycle guard should follow. Their tests move with them.

### Routing today

Desktop: `components/CenterPane.tsx:127` — `const showBlocks = viewMode === "blocks";`
line 445 chooses `<SessionBlocksPane session={session} />` or `<TerminalPane .../>`,
and `SessionBlocksPane` is defined at line 669.

Mobile: `lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart:93`
returns `ChatScreen(...)` when `session?.mode == 'chat'`, and a `MultiBlocProvider`
stack (`TerminalCubit`, `SessionViewCubit`, `BlocksCubit`, `PreviewCubit`) wrapping
`TerminalScreen` when `== 'tui'`.

**Chat never reaches the block screen on either client.**

`BlocksCubit` (`lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart`)
is constructed `BlocksCubit(MuxClient, BlocksRepository, sessionId, {harness})`,
subscribes to `_mux.blockEvents`/`status`/`sessionPatches` in its constructor, and
calls `_mux.unsubscribeBlocks(sessionId)` in `close()`.

### Shared fixtures

`testdata/blocks/` holds ten files today, asserted by
`frontend/src/renderer/lib/block-assembly.fixtures.test.ts` and
`packages/mobile/test/feature/blocks/logic/block_assembly_fixtures_test.dart`. The
hook fixtures use `{"records": [...], "expected": [...]}`.

### Conventions that apply throughout

**Mobile** (`CLAUDE.md`): Cubit only, never `Bloc` with events. Static-only classes are
`sealed class X`. No `freezed`, `json_serializable` or `build_runner` — the drift
exception belongs to plan 9 and does not extend here. Models hand-written, all fields
nullable. One params class per method under `data/model/params/`, never shared.
Parameterized paths get static methods on `EndPoints`. Feature code never imports
`flutter_screenutil`. Copy is inline English. `AppSkin` through `context.skin`, type as
`AppTextStyle.style<Size><Weight>`.

**Desktop** (`DESIGN.md`, `CLAUDE.md`): the renderer clones the agent-orchestrator web
app verbatim with a refined-blue accent; build from shadcn primitives in
`components/ui/*` where one fits. Every new i18n key goes into **all eight** locale
files.

**Both:** no code comments unless the surrounding file already comments heavily.

## Verification gates

Run the gate for what the task touched. A task is not done until it is green.

```bash
npm run frontend:typecheck            # from the repo root
npm --prefix frontend run test        # no root alias exists for this
```

```bash
flutter analyze                       # from packages/mobile; must print "No issues found!"
flutter test
```

**A task that touches the shared fixtures runs both suites**, because a fixture is
asserted twice by construction. This is the whole reason this plan is not split by
client.

`npm run lint`, `npm run api`, `npm run sqlc` and the Playwright suite
(`npm --prefix frontend run test:e2e`) are **not** part of this plan. If you find
yourself running them, scope has slipped.

## The model, decided up front

Both clients add, to their existing `SessionBlock`:

- `turnId` — optional string.
- Three kinds appended to `prompt | assistant | tool | permission | notice`:
  **`reasoning`**, **`todo`**, **`compaction`**.
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

TypeScript: a discriminated union on `type`, with a `never` default in each `switch`
so a missed variant is a typecheck failure. Dart: a `sealed class BlockDetail`, per
the package convention for closed sets and because `switch` exhaustiveness catches a
missed variant at analyze time rather than at runtime.

Each client also gains one display function, mirroring paseo's
`buildToolCallDisplayModel`: `blockDisplay(block) -> {displayName, summary, errorText}`.
The block card calls it instead of formatting inline. This is what stops the two
clients drifting on presentation, and it is cheap only while there is one source.

## What is retired, and what is not

The spec says chat's presentation layer retires. Read precisely: **the timeline
rendering retires; the interaction surfaces do not.** Chat can do things blocks
cannot, and deleting them would remove shipped features.

**Retired — replaced by block components:**

Desktop (`components/chat/`): `ChatTimelineItems.tsx`, `ActivityRun.tsx`,
`TurnPlan.tsx`, `activity-command.ts`, `ChatMarkdown.tsx` and `HighlightedCode.tsx`
*as timeline renderers*, `CopyButton.tsx` where `BlockCard` already provides one, and
the timeline half of `ChatWorkspace.tsx` and `SessionChatSurface.tsx`.

Mobile (`lib/feature/chat/presentation/chat_screen/ui/widgets/`): `chat_timeline.dart`,
`timeline_item.dart`, `activity_row.dart`, `activity_run.dart`, `activity_meta.dart`,
`turn_summary.dart`, `plan_card.dart`, `file_change_list.dart`, `chat_markdown.dart`,
`highlighted_code_text.dart`, and the timeline half of `chat_body.dart`.

**Kept — interaction, not timeline:**

- **Composers.** `ChatComposer.tsx` + `composerSuggest.ts`, `chat_composer.dart` +
  `logic/composer_suggestions.dart`. Task 8 merges them; nothing deletes them first.
- **Approval and elicitation.** `ElicitationCard.tsx`, `HumanMessageEditor.tsx`,
  `approval_card.dart`, `user_input_card.dart`, `logic/elicitation_model.dart`.
- **Turn settings, model selection, context meter, branch navigation, rollback.**
  `TurnSettingsBar.tsx`, `ContextMeter.tsx`, `ConversationBranchNavigator.tsx`,
  `chat_settings_sheet.dart`, `conversation_menu_sheet.dart`,
  `conversation_map_sheet.dart`, `live_turn_bar.dart`, `chat_meta_bar.dart`.
- **Status banners.** `ChatStatusBanners.tsx`, `conversation_banners.dart`,
  `inline_banner.dart` — controller state, auth, rate limits and reroutes are not
  timeline entries.
- **Every `data/` layer on both clients**, unchanged. `hooks/useConversation.ts` keeps
  its entire surface including every command hook; `feature/chat/data/**` keeps every
  model, param and data source.
- **Voice** (`feature/chat/voice/**`), untouched.

**The spec's "retires most of the 38 files" is an overstatement and this plan corrects
it.** About a third of `components/chat/` is timeline rendering. Expect roughly 12–14
desktop files including tests, and about ten mobile widgets. **Deleting a file to
reach a number is a regression, not progress.**

## Task 1 — Extend the block model, both clients, one commit.

Implement *The model, decided up front* in TypeScript and Dart together. One commit,
so the two can never disagree at any point in history.

Add `blockDisplay` to each client and change `components/blocks/BlockCard.tsx` and
`block_card.dart` to call it instead of formatting inline.

**The hook adapter must not change behaviour.** `lib/block-assembly.ts` and
`block_assembly.dart` gain `turnId: undefined` / `null` and an `unknown` detail on the
blocks they already produce. Every existing test and every hook fixture passes
untouched. **If a hook fixture needs editing, you have changed behaviour — stop.**

Add `testdata/blocks/acp_detail_variants.json` exercising every variant including
`unknown`, and assert it from both suites.

**Gate:** desktop typecheck + test, and `flutter analyze` + `flutter test`. Both.

## Task 2 — Turn grouping, both clients, one commit.

A pure function per client: `groupBlocksByTurn(blocks) -> TurnGroup[]`, where a
`TurnGroup` is `{turnId?, blocks, startedAt, completedAt, durationMs}`.

Three rules:

1. **Canonical turn id wins.** Where both neighbours carry a `turnId`, they are in the
   same turn iff the ids are equal.
2. **Otherwise a new turn starts at each `prompt` block.** Hook-sourced blocks carry
   no turn id, so this rule keeps `tui` sessions grouped with no backend change.
3. **A visible response may span several canonical turns**, because some prompts are
   system-injected and never appear as a block. Grouping strictly by turn id would
   render those as headless turns.

Rule 3 means **two functions, not one with a flag**: `continuesTurn` (strict — used
for boundaries and any future rewind) and `continuesResponse` (relaxed — used for
run-together display). The spec is explicit that conflating them is the bug.

Turn timing is **derived here, never stored per block**: `startedAt` from the group's
first block, `completedAt` from its last, and a running start for an unfinished turn.

Mobile: move `groupConversationByTurn` out of `feature/chat/logic/timeline_model.dart`
into `feature/blocks/logic/`, generalized over `SessionBlock`. Do not write a second
grouping function. Desktop: `lib/block-turns.ts`.

Render a finished group's duration and an unfinished one as running. **Assert both** —
this is the "a conversational turn never says it finished" symptom from the first live
run, and a test covering only the finished case would not have caught it.

Add `testdata/blocks/acp_turn_grouping.json` with a system-injected prompt (no
`prompt` block, two canonical turn ids) and a hook-style stream with no turn ids.

**Gate:** both.

## Task 3 — The fixtures.

Add four files to `testdata/blocks/`, and a **second fixture list** in each suite —
not a widening of the existing one, because the input shapes differ. ACP fixtures are
`{"snapshot": {...}, "expected": [...]}`.

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
non-zero `exitCode` in its detail and `commandOutputTruncated: true`, followed by an
assistant message. Asserts `status: "failed"`, that the truncation flag survives into
the block, and that a failed tool does not fail its turn's other blocks.

**`acp_stream_compaction.json`** — a snapshot whose `compactedAt` is set, with items on
both sides of it. Asserts exactly one `compaction` block, positioned by `compactedAt`
rather than appended at the end.

**`acp_stream_nested_subagent.json`** — a parent `mcp_tool` activity, two children
correlated by `parentToolUseID`, and a grandchild. Asserts one level of nesting, the
grandchild flattened into the nearest nesting parent, and termination when a parent id
points at its own descendant.

The fixtures land before either adapter, so both adapters are written against a
failing test rather than toward one. **A failing fixture is never fixed by editing the
fixture.**

**Gate:** both suites, red for the new list — that is the expected state at the end of
this task, and the next two tasks turn it green.

## Task 4 — The adapters, both clients.

`frontend/src/renderer/lib/conversation-blocks.ts`:

```ts
export function blocksFromConversation(snapshot: ConversationSnapshot): SessionBlock[];
```

`packages/mobile/lib/feature/blocks/logic/conversation_blocks.dart`:

```dart
List<SessionBlock> blocksFromConversation(ConversationSnapshotModel snapshot);
```

Both pure and synchronous: no React, no Dio, no cubit, no fetching. Each consumes the
snapshot its client already has and produces the same `SessionBlock` list the hook
adapter produces.

**Write them one after the other in the same task, not in separate tasks.** The second
one is where a disagreement surfaces, and it surfaces as a fixture failure you can fix
in five minutes rather than a merge conflict you cannot.

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

Mobile: reuse `activityHierarchy` and `_activityCycle` by moving them into
`feature/blocks/logic/`, generalized over blocks; their tests move too. Desktop:
follow `_activityCycle` as the reference for the cycle guard.

**Tests** (`conversation-blocks.test.ts`, `conversation_blocks_test.dart`): one per
mapping row, one per numbered rule, and three nesting cases — one level, flattened
grandchild, and a cycle that must terminate.

**Gate:** both suites green, including Task 3's fixture list on both sides.

## Task 5 — Desktop: route chat through the block screen.

Extend `SessionBlocksPane` (`CenterPane.tsx:669`) to select its source by session mode:

- `mode === "tui"` → the existing `useSessionBlocks` path, unchanged.
- `mode === "chat"` → `useConversation(sessionId)` through `blocksFromConversation`.

`BlocksView`'s props do not change.

**Four things to get right, each with a test:**

1. **`supported` is not `blocksCoverHarness(harness)`.** That set describes *hook*
   coverage. A chat session is supported iff it has a conversation. **Write this test
   first.**
2. **`unavailable` is not `error`.** Render it as an explanation — never as a failure,
   never as a spinner that does not resolve.
3. **There is no Raw toggle in chat mode.** `chat` has no agent terminal, so there is
   nothing to toggle to. Hide the control at `CenterPane.tsx:413`; do not disable it.
4. **The composer sends structured messages** through `useConversationCommands`, not a
   POST to the `tui` send route. `BlockComposer` takes a send function rather than
   choosing one — today it posts to `/api/v1/sessions/{sessionId}/send` directly.

**Gate:** desktop typecheck + test.

## Task 6 — Mobile: route chat through the block screen.

Add `ConversationBlocksCubit` under
`lib/feature/blocks/presentation/blocks_screen/logic/`, subscribing to the existing
`feature/chat/data/data_source/chat_event_data_source.dart` and `ChatRepository`, and
emitting `List<SessionBlock>` through `blocksFromConversation`.

**Do not extend `BlocksCubit`.** It is constructed with `MuxClient` and
`BlocksRepository` and pins its mux subscription in `close()`; a second source would
make its constructor branch on mode and its teardown conditional. Two cubits, one
screen, one model.

Register it in `service_locator.dart`'s `_blocksFeatureSetup()` alongside the existing
`registerFactoryParam<BlocksCubit, String, String?>`, and change
`session_route_screen.dart:93` so the `chat` branch builds the block screen instead of
returning `ChatScreen(...)`.

The four rules from Task 5 apply identically, including that `SessionViewCubit` and
the Raw toggle do not belong on a chat session. Tests follow the
`_MockX extends Mock implements X` + `registerFallbackValue` shape at
`test/feature/blocks/presentation/blocks_cubit_test.dart:15-51`.

**Gate:** `flutter analyze` + `flutter test`.

## Task 7 — Retire the timeline layer, both clients.

Only now, with both screens green, delete. Use the Retired and Kept lists above
literally.

Correct the spec's "retires most of the 38 files" claim in the same commit, with the
real count.

**Gate:** both.

## Task 8 — Capability-gated actions, and merge the composers.

Wire the kept interactions as block actions, gated on the snapshot's `capabilities`:

- a `permission` block declares approve/deny **only** when capabilities say the
  provider supports it;
- a `user_input` block opens the elicitation surface;
- a turn group offers rollback only when `canRollbackTurn(...)` — already implemented
  at `timeline_model.dart:173` — says so.

**Never render an action the source cannot perform.** An action that fails after the
user acts on it is worse than an absent one, and per-mode gating is too coarse: within
`chat`, providers differ.

Then merge attachments, slash-command suggestions and steering into the block
composer on both clients, behind the same capability check. **Last, not first** —
merging before both screens render blocks means debugging two things at once. Every
new desktop string gets a key in all eight locale files.

**Gate:** both, plus a manual pass — open a chat session on desktop and on a phone,
send a message, approve a permission, watch a turn finish.

## Risks

- **The `supported` gate.** `blocksCoverHarness` / `BlockHarnesses.covers` returning
  false for a chat session shows "blocks unavailable" on a session with a perfectly
  good conversation. Test it first on both clients.
- **Deleting an interaction by mistake.** Mitigated by the explicit Kept list and by
  Task 7 deleting nothing until Tasks 5 and 6 are green.
- **The two adapters drifting.** Mitigated by Task 3 landing the fixtures before either
  adapter, and by Task 4 writing both in one task. This is the risk that motivated
  keeping this as one plan.
- **Streaming churn.** A chat session re-derives every block on every event. That is
  acceptable for correctness and is **not** fixed here — the spec's coalescing and
  history/live-split amendments address it, and doing that work inside this plan would
  confuse a mapping bug with a performance one. Record the measurement; do not
  optimize.
- **Scope creep into the viewport.** This plan changes what blocks exist, never how
  they scroll. `BlocksView`'s prop shape is plan 4b's boundary; leave it alone.
