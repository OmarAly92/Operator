# Plan 5b — ACP block adapter, desktop

Status: written
Date: 2026-08-28
Spec: `docs/superpowers/specs/2026-08-27-session-blocks-design.md`, step 7
Scope: `frontend/src/renderer`, plus the shared fixtures in `testdata/blocks`
Depends on: plans 1, 3. Independent of 2, 4a, 4b, 6, 7, 8, 9.
Parallel sibling: **plan 5a (mobile)**. Read *The frozen contract* below before
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

## Working in parallel with plan 5a

5a and 5b run in separate worktrees and share **no source file**. TypeScript and Dart
models, adapters, grouping functions, hooks and components are all per-client.

The one shared directory is `testdata/blocks/`, and *The frozen contract* pins its
contents exactly so both agents produce identical files. Whoever merges first wins; the
second finds the files present, verifies them, and moves on.

**If you finish before 5a:** do not touch `packages/mobile`. A mobile change from this
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

**The block model today.** `frontend/src/renderer/lib/session-block.ts`:

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

`BLOCK_HARNESSES` mirrors `blockdispatch.Mappers`. **This gate is about hooks and must
not be applied to a chat session.** Task 4 has a test for it, because getting it wrong
makes chat blocks silently unavailable for opencode and droid.

**Conversation access.** `frontend/src/renderer/hooks/useConversation.ts:85` —
`useConversation(sessionId)` is a `useInfiniteQuery` over
`GET /api/v1/sessions/{sessionId}/conversation` with `CONVERSATION_PAGE_SIZE = 200`,
paged by `beforeSequence`, merged by `mergeConversationPages` (line 780) and shaped by
`toSnapshot` (661), `toMessage` (805) and `toActivity` (827).

Its result type is:

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

and returns `unavailable` for `SESSION_MODE_MISMATCH` and `CHAT_CONTROLLER_NOT_READY`.
**Preserve that distinction exactly.** It is the difference between "this session is
TUI, that is why there is no conversation" and a spinner that never resolves.

**Live updates are invalidations, not deltas.** CDC events on `/api/v1/events` invalidate
`conversationQueryKey(sessionId)` (`lib/event-transport.ts:95`) and the snapshot is
refetched. This plan does not change that.

**`BlocksView` props are already right** (`components/blocks/BlocksView.tsx:6`):

```ts
export type BlocksViewProps = {
	blocks: SessionBlock[];
	isLoading: boolean;
	isLoadingOlder: boolean;
	hasOlder: boolean;
	error?: string;
	harness?: string;
	sessionId: string;
	supported: boolean;
	onLoadOlder: () => void;
	onRetry: () => void;
};
```

`useConversation`'s `hasOlder` / `isLoadingOlder` / `loadOlder` mean the same thing and
map straight through. **Do not change this prop shape** — plan 4b's viewport work sits
behind it.

**Routing today.** `components/CenterPane.tsx:127` — `const showBlocks = viewMode === "blocks";`
line 445 chooses `<SessionBlocksPane session={session} />` or `<TerminalPane .../>`, and
`SessionBlocksPane` is defined at line 669. Chat never reaches the block screen.

**Design conventions that apply to every task here** (`DESIGN.md`, `CLAUDE.md`): the
renderer **clones the agent-orchestrator web app verbatim** with a refined-blue accent;
build from shadcn primitives in `components/ui/*` where one fits; the terminal palette
carve-out applies to Raw mode only. Every new i18n key goes into **all eight** locale
files. No code comments unless the surrounding file already comments heavily.

## Verification gate

After every task:

```bash
npm run frontend:typecheck
npm --prefix frontend run test
```

There is no root alias for the test script. The Playwright suite
(`npm --prefix frontend run test:e2e`) is a separate gate and is **not** part of this
plan — vitest excludes `e2e/**`.

## Task 1 — Extend the block model and add the display function.

Implement section 1 of *The frozen contract* in TypeScript.

`BlockDetail` is a discriminated union on a `type` field, with the seven variants.
Exhaustiveness is checked by a `never` default in each `switch`, so a missed variant is
a typecheck failure rather than a runtime surprise.

Add `blockDisplay(block)` in `lib/`, and change `components/blocks/BlockCard.tsx` to
call it instead of formatting inline.

**The hook adapter must not change behaviour.** `lib/block-assembly.ts` gains
`turnId: undefined` and `detail: {type: "unknown", raw}` on the blocks it already
produces, and every existing test and hook fixture passes untouched. **If a hook fixture
needs editing, you have changed behaviour — stop.**

Add `acp_detail_variants.json` exercising every variant including `unknown`.

## Task 2 — Turn grouping.

Implement section 2 of *The frozen contract* as `lib/block-turns.ts`.

Render a finished turn group's duration and an unfinished one as running. Assert both —
this is the "a conversational turn never says it finished" symptom from the first live
run, and a test that only covers the finished case would not have caught it.

## Task 3 — The ACP adapter.

Create `frontend/src/renderer/lib/conversation-blocks.ts`:

```ts
export function blocksFromConversation(snapshot: ConversationSnapshot): SessionBlock[];
```

Pure and synchronous: no React, no fetching, no query client. It consumes the
`ConversationSnapshot` that `useConversation` already returns and produces the same
`SessionBlock[]` the hook adapter produces.

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

The mobile client's `_activityCycle` in
`packages/mobile/lib/feature/chat/logic/timeline_model.dart:232` is the reference
implementation for the cycle guard. **Read it; do not edit it** — that file belongs to
plan 5a's worktree.

**Tests** (`lib/conversation-blocks.test.ts`): one per mapping row, one per numbered
rule, and three nesting cases — one level, flattened grandchild, and a cycle that must
terminate.

Add the four `acp_stream_*` fixtures and a second fixture list in
`lib/block-assembly.fixtures.test.ts`. Do not widen the existing `FIXTURES` array — the
two input shapes differ, so this is a second list with its own reader.

## Task 4 — Route chat sessions through the block screen.

Extend `SessionBlocksPane` (`CenterPane.tsx:669`) to select its source by session mode:

- `mode === "tui"` → the existing `useSessionBlocks` path, unchanged.
- `mode === "chat"` → `useConversation(sessionId)` piped through
  `blocksFromConversation`.

`BlocksView`'s props do not change.

**Four things to get right, each with a test:**

1. **`supported` is not `blocksCoverHarness(harness)`.** That set describes *hook*
   coverage. A chat session is supported iff it has a conversation. Passing the hook
   gate here makes chat blocks vanish for opencode and droid. **Write this test first.**
2. **`unavailable` is not `error`.** Render `useConversation`'s `unavailable` as an
   explanation — never as a failure, never as a spinner that does not resolve.
3. **There is no Raw toggle in chat mode.** `chat` has no agent terminal, so there is
   nothing to toggle to. Hide the control at `CenterPane.tsx:413`; do not disable it.
4. **The composer sends structured messages** through `useConversationCommands`, not a
   POST to the `tui` send route. `BlockComposer` takes a send function rather than
   choosing one — it currently posts to `/api/v1/sessions/{sessionId}/send` directly.

## Task 5 — Retire the timeline components.

Only now, with the pane green, delete.

**Delete**, with their tests, from `components/chat/`: `ChatTimelineItems.tsx`,
`ActivityRun.tsx`, `TurnPlan.tsx`, `activity-command.ts`, `ChatMarkdown.tsx` and
`HighlightedCode.tsx` **as timeline renderers**, `CopyButton.tsx` where `BlockCard`
already provides one, and the timeline half of `ChatWorkspace.tsx` and
`SessionChatSurface.tsx`.

**Keep** — these are interaction, not timeline, and deleting them removes shipped
features:

- `ChatComposer.tsx` and `composerSuggest.ts`, until Task 6 merges them
- `ElicitationCard.tsx`, `HumanMessageEditor.tsx`
- `TurnSettingsBar.tsx`, `ContextMeter.tsx`, `ConversationBranchNavigator.tsx`
- `ChatStatusBanners.tsx` — controller state, auth, rate limits and reroutes are not
  timeline entries
- **`hooks/useConversation.ts` entirely**, including every command hook
- `code-theme.css`, if a kept component still loads it

**Do not delete a file to reach a count.** The spec claims this "retires most of the 38
files under `components/chat/`"; that overstates it. About a third of the directory is
timeline rendering, so expect roughly 12–14 files including tests, not 38. **Correct the
spec's claim in the same PR** rather than deleting working features to make it true.

## Task 6 — Capability-gated actions, and merge the composers.

Wire the kept interactions as block actions, gated on the snapshot's capabilities:

- a `permission` block declares approve/deny **only** when capabilities say the provider
  supports it;
- a `user_input` block opens `ElicitationCard`;
- a turn group offers rollback only when the snapshot says it can.

**Never render an action the source cannot perform.** An action that fails after the
user clicks it is worse than an absent one, and per-mode gating is too coarse: within
`chat`, providers differ.

Then merge attachments, slash-command suggestions and steering into `BlockComposer`,
behind the same capability check. **Last, not first** — merging before the pane renders
blocks means debugging two things at once.

Every new string gets a key in **all eight** locale files.

## Risks

- **The `supported` gate.** `blocksCoverHarness` returning false for a chat session shows
  "blocks unavailable" on a session with a perfectly good conversation. Test it first.
- **Deleting an interaction by mistake.** Mitigated by the explicit Keep list and by Task
  5 deleting nothing until Task 4 is green.
- **Fixture divergence with 5a.** A failing fixture is never fixed by editing the
  fixture. If your client disagrees, either your adapter is wrong or mobile's is.
- **Streaming churn.** A chat session invalidates its whole query on every CDC event and
  re-derives every block. That is acceptable for correctness and is **not** fixed here —
  the spec's coalescing and history/live-split amendments address it, and doing that work
  inside this plan would confuse a mapping bug with a performance one. Record the
  measurement; do not optimize.
- **Scope creep into the viewport.** This plan changes what blocks exist, never how they
  scroll. `BlocksView`'s prop shape is plan 4b's boundary; leave it alone.
