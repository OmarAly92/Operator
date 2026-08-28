# Plan 6 — Block actions, cross-block selection, find

Status: written
Date: 2026-08-28
Spec: `docs/superpowers/specs/2026-08-27-session-blocks-design.md`, step 8
Scope: `frontend/src/renderer`, `frontend/e2e`, `packages/mobile`, `testdata/`, `backend/internal/service/blockevent`, `backend/internal/httpd`
Depends on: plans 1, 2, 3, 4a, 4b, 5 — all landed on `master`. Independent of 7, 8, 9.

## One plan, with one fork point

**Tasks 1-3 must be run by a single agent.** They produce a pure-logic core that
exists twice — once in TypeScript, once in Dart — and is pinned by shared JSON
fixtures that both suites read. This is plan 5's situation exactly: the two ports
share an *output contract*, not a requirements list, and neither a Dart-only nor a
TypeScript-only agent can run the check that matters. A disagreement would surface
only when the second branch merged, in the other client's code.

**Tasks 4-6 (desktop) and 7-9 (mobile) are independent once tasks 1-3 are on
`master`.** After the contract lands, the desktop lane touches no Dart and the mobile
lane touches no TypeScript. Their only shared files are the fixtures, which neither
lane may modify. If you want two agents in two worktrees, **this is the fork point**,
and the operational recipe is at the end of this document.

**Tasks 10-12 are the tail** and are marked with what may be cut.

## What this delivers

A block is no longer only something to read. From either client the user can:

- **Act on a block** — copy it, copy a shell command or its output, re-run a prompt,
  rewind the conversation to the turn it belongs to. Every action is gated on a
  capability the source actually reports, never on the session's mode.
- **Collapse a block**, so a forty-line tool result stops burying the turn around it.
- **Find across blocks**, with a ranked matcher shared with the rest of the app rather
  than a second, weaker one grown for this screen.
- **Filter the list to matches**, with configurable context blocks around each hit.
- **Select several blocks and copy them** as one plain-text transcript.

And, as the amendment table requires, blocks reach the browser e2e suite, driven by a
load-generating source in the product rather than by "profile it under a long
session", which is not a testable instruction.

## Read this before you plan any work

### Everything this plan needs already exists on the daemon side

There is **no new daemon vocabulary** in tasks 1-9. Capabilities, decisions, turn
state and rollback all shipped in plan 5. Task 10 adds one dev-only route and
nothing else on the backend. If you find yourself editing `queries/`, `migrations/`,
`backend/internal/storage/sqlite/gen/`, `ports/chat.go` or `blockdispatch`, scope has
slipped.

### The rewind question the spec left open, answered

The spec says: *"Rewind is three capabilities, not one — conversation, files, or both.
Operator has `/api/v1/sessions/{sessionId}/rollback`; which of the three it means must
be stated before rewind reaches a block action, because a user who expects files
reverted and gets only conversation has lost work."*

Two corrections, both established by reading the code, and both binding on this plan:

1. **The spec names the wrong route.** `POST /api/v1/sessions/{sessionId}/rollback`
   (`backend/internal/httpd/controllers/sessions.go:199`, handler at `sessions.go:1230`)
   undoes a *partially-completed spawn* — it deletes or kills a half-created session.
   It has nothing to do with conversation history. The rewind route is
   `POST /api/v1/sessions/{sessionId}/conversation/turns/{turnId}/rollback`
   (`controllers/conversations.go:75`).

2. **It is conversation-only. It never touches files.** `controllers/conversations.go:242`
   documents it as discarding "a turn and everything after it, from the agent's memory
   as well as from the timeline", and the implementation at
   `backend/internal/service/chat/controller.go:1177-1186` calls the provider's
   `Rollback(ctx, turn.ProviderTurnID)` and then `store.RollbackTurns(...)`. There is
   no worktree operation anywhere in that path.

**Therefore:** the block action is labelled *rewind the conversation*, never *rewind*
or *undo*. Both clients must say, in the confirmation the user sees, that files on
disk are not reverted. Do not invent `supportsRewindFiles`; Operator has one rewind
capability, `rollback`, and it means conversation only.

### Actions are gated per capability, not per mode

`ChatCapability` is defined at `backend/internal/ports/chat.go:66-119` and serialized
verbatim by `capabilityNames()` at `controllers/dto.go:1821`. The strings a client
sees are the Go constant *values*, not the constant names. The ones this plan reads:

| Capability string | Constant | Gates |
| --- | --- | --- |
| `rollback` | `ChatCapabilityRollback` | the rewind action |
| `steer` | `ChatCapabilitySteer` | (already wired, do not re-gate) |
| `approvals` | `ChatCapabilityApprovals` | (already wired, do not re-gate) |

**This is where the last agent to touch this area got it wrong**, and the failure is
worth restating because this plan adds more gates. Plan 5's first pass gated on
`"approve"`; the daemon emits `"approvals"`, so the feature was dead while fourteen
integration tests were green — because they asserted the implementation's own string
rather than the daemon's. **Every capability string in this plan must be traced back
to `ports/chat.go` before it is used, and at least one test per gate must use the
string as the daemon spells it.**

A `tui` session reports **no chat capabilities at all** — it has no chat controller.
Its action set is therefore derived from what a TUI session can do (send text into the
composer), never from an empty capability list read as "everything is allowed".

### The desktop i18n gate will fail you if you skip it

`frontend/src/renderer/i18n/renderer-coverage.test.ts` walks every `.tsx` under
`src/renderer` with the TypeScript AST and fails on any hardcoded English in JSX text
or in an `alt` / `aria-label` / `placeholder` / `title` attribute. There is an
allowlist and a `deferredLocalizationFiles` set; **do not add a new file to either.**

`frontend/src/renderer/i18n/instance.test.ts:149-173` then requires that **every one of
the eight locale catalogs** carries every English key with a non-empty value and with
identical `{{placeholders}}`:

```
frontend/src/renderer/i18n/en.json      ← source of truth, keys are typed from it
frontend/src/renderer/i18n/zh-CN.json
frontend/src/renderer/i18n/ja.json
frontend/src/renderer/i18n/ko.json
frontend/src/renderer/i18n/es.json
frontend/src/renderer/i18n/fr.json
frontend/src/renderer/i18n/de.json
frontend/src/renderer/i18n/pt-BR.json
```

Every string this plan adds to the desktop goes into all eight, translated. Existing
block keys are namespaced `blocks.*` (`blocks.jumpToLatest`, `blocks.rollback`,
`blocks.noDecisions`, …); follow that.

**Mobile has no such gate and no catalogue.** Mobile copy is inline English, by
convention. Do not add a `LocaleKeys` for this.

### The two render slots already exist — extend them, do not replace them

Plan 5 replaced four permission-shaped props with one render slot on each client.
Keep that shape:

```tsx
// frontend/src/renderer/components/blocks/BlockCard.tsx
export const BlockCard = memo(function BlockCard({ block, renderActions }: {
  block: SessionBlock;
  renderActions?: (block: SessionBlock) => ReactNode;
}) { … })
```

```dart
// packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart
class BlockCard extends StatelessWidget {
  const BlockCard({super.key, required this.block, this.actionsBuilder});
  final SessionBlock block;
  final Widget? Function(SessionBlock block)? actionsBuilder;
}
```

`renderActions` / `actionsBuilder` carries **provider-specific** controls: approval
decisions and the elicitation card. It stays exactly as it is. This plan adds a
**second, orthogonal** input for the standard action set, because those are derived
from the block and a capability context rather than supplied by the caller.

### What the block model gives you

`frontend/src/renderer/lib/session-block.ts` and
`packages/mobile/lib/feature/blocks/logic/session_block.dart` are mirrors:

```ts
export type BlockKind = "prompt" | "assistant" | "reasoning" | "tool" | "todo" | "compaction" | "permission" | "notice";
export type BlockStatus = "running" | "ok" | "failed" | "blocked";
export type SessionBlock = {
  id: string; firstSeq: number; lastSeq: number;
  kind: BlockKind; status: BlockStatus; turnId?: string;
  title: string; body: string; detail?: BlockDetail;
  toolName?: string; errorType?: string;
  truncatedLines: number; redacted: boolean;
  createdAt?: string; children?: SessionBlock[];
};
export function blockDisplay(block: SessionBlock): { displayName: string; summary: string; errorText?: string };
```

`blockDisplay` is what the card renders. **Search and copy operate on `blockDisplay`
output, not on raw fields**, so that a highlight offset lines up with the characters
the user is looking at. This is not a detail you may vary between clients.

`BlockDetail` variants: `shell{command,output,exitCode}`, `file_change{files,truncated}`,
`plan{steps}`, `mcp_tool{server,tool,args,result}`, `usage{...}`, `compaction{trigger,preTokens}`,
`unknown{raw}`. On Dart these are subclasses of `sealed class BlockDetail`
(`ShellBlockDetail`, `FileChangeBlockDetail`, …), matched with a `switch` expression.

### Redacted text is already redacted

`backend/internal/service/blockevent/service.go` redacts before persistence and
before transmission. A block whose `redacted` flag is true carries text with the
secret already replaced. **Copying it is safe. Do not add a guard that refuses to
copy a redacted block** — you would be protecting against something that is not
there, and hiding the user's own output from them.

### Test harnesses that already exist — use them, do not write a second one

- **Desktop virtualized list.** `installVirtualLayout({ heights })` at
  `frontend/src/renderer/test/virtual-layout.ts`, used by
  `BlockList.actions.test.tsx:38` as:
  ```ts
  teardown = installVirtualLayout({ heights: () => currentBlocks.map(() => 80) });
  ```
  It fakes `ResizeObserver` and element geometry so `@tanstack/react-virtual` produces
  real virtual items under jsdom. Every `BlockList` test needs it.
- **Mobile widget pump.** The `_pump` helper at
  `packages/mobile/test/feature/blocks/presentation/block_card_actions_test.dart:33`
  wraps the widget in `SkinScope(skin: const DarkSkin(), …)` + `ScreenUtilInit` +
  `MaterialApp`. Copy that shape; `context.skin` throws without the scope.
- **Desktop e2e fakes.** `frontend/e2e/support/fake-bridge.ts` and
  `frontend/e2e/support/fake-terminal-mux.ts`. Task 11 adds a third beside them and
  models it on `fake-terminal-mux.ts` exactly.
- **Shared fixture paths.** vitest reads `path.resolve(process.cwd(), "../testdata/blocks")`
  (`frontend/src/renderer/lib/block-assembly.fixtures.test.ts:62`); `flutter test` reads
  `File('../../testdata/blocks/$name.json')`
  (`packages/mobile/test/feature/blocks/logic/block_assembly_fixtures_test.dart:32`).

### Conventions that apply throughout

**Mobile** (`CLAUDE.md`): Cubit only, never `Bloc` with events. Static-only classes are
`sealed class X`. No `freezed`, `json_serializable` or `build_runner` — the drift
exception belongs to plan 9's `lib/core/cache/` and does not extend here. Models
hand-written, all fields nullable. Feature code never imports `flutter_screenutil`
(test files may, and do). Copy is inline English. `AppSkin` through `context.skin`;
type as `AppTextStyle.style<Size><Weight>` or the parallel `mono*` set. Navigation is
`Navigator.of(context)` with `RoutesStrings` names.

**Desktop** (`DESIGN.md`, `CLAUDE.md`): the renderer clones the agent-orchestrator web
app verbatim with a refined-blue accent; build from shadcn primitives in
`components/ui/*` where one fits — `button.tsx` (`variant`: `primary | outline |
secondary | ghost`), `input.tsx`, `dropdown-menu.tsx`, `tooltip.tsx` all exist.

**Both:** no code comments unless the surrounding file already comments heavily.
`session-block.ts` and `dispatch.go` comment heavily; `BlockCard.tsx` and
`block_card.dart` do not.

**Two mobile behaviours that must not be "optimized"**, both in `CLAUDE.md`: the
12-second Dio timeouts, and the sequential auth probing in
`sessions_remote_data_source.dart`. Neither is in this plan's path; do not wander into
them.

## Verification gates

Run the gate for what the task touched. A task is not done until it is green.

```bash
npm run frontend:typecheck
```
```bash
npm --prefix frontend run test
```
```bash
flutter analyze
```
```bash
flutter test
```

`flutter analyze` and `flutter test` run from `packages/mobile`; `analyze` must print
`No issues found!`. The two npm commands run from the repo root — there is no root
alias for the vitest script.

**A task that touches `testdata/` runs both suites.** That is the whole reason tasks
1-3 are not split by client.

Task 10 adds `npm run lint` (go test + golangci-lint) and `npm run api`. Task 11 adds
`npm --prefix frontend run test:e2e`. No task in this plan runs `npm run sqlc`.

---

# Phase A — the shared contract (one agent, tasks 1-3)

## Task 1 — One ranked text matcher, in both languages, fixture-first.

The spec: *"Find uses one ranked matcher, shared. … Step 8's find across blocks should
not grow a second, weaker matcher."* Operator today has exactly the weaker matcher the
spec warns about — `matchScore` at `frontend/src/renderer/lib/command-palette.ts:329`,
a four-branch integer score with no Dart counterpart. This task adds the real one.
Task 12 migrates the palette onto it.

The reference implementation is paseo's `packages/protocol/src/search/text-match.ts`
(Apache-2.0). Port it; do not redesign it. A match is `{tier, offset, spread?}` where
**lower is better on every field**, so callers sort ascending and never invent a scale.

### 1a. `testdata/search/text-match.json` — write this first

Three arrays. `options.fuzzy` is `null`, or an object `{maxEdits, transpositionsOnly}`,
or the string `"auto"` meaning "use `fuzzyPolicyForToken(query)`". `expect` is `null`
for no match; otherwise an object whose **omitted `spread` asserts that the
implementation produced no spread** (`undefined` in TS, `null` in Dart).

```json
{
  "score": [
    { "name": "empty query matches everything at tier 0", "query": "", "text": "main", "options": {}, "expect": { "tier": 0, "offset": 0 } },
    { "name": "whole string equal is exact", "query": "main", "text": "main", "options": {}, "expect": { "tier": 0, "offset": 0 } },
    { "name": "case is folded", "query": "MAIN", "text": "main", "options": {}, "expect": { "tier": 0, "offset": 0 } },
    { "name": "a bounded word is whole-word", "query": "test", "text": "run the test suite", "options": {}, "expect": { "tier": 1, "offset": 8 } },
    { "name": "a leading unbounded hit is prefix", "query": "mai", "text": "maintenance", "options": {}, "expect": { "tier": 2, "offset": 0 } },
    { "name": "an unbounded hit at a word start is word-start", "query": "sui", "text": "run the suite", "options": {}, "expect": { "tier": 3, "offset": 8 } },
    { "name": "an interior hit is substring", "query": "uit", "text": "run the suite", "options": {}, "expect": { "tier": 4, "offset": 9 } },
    { "name": "the earliest hit of the best tier wins", "query": "the", "text": "the other the", "options": {}, "expect": { "tier": 1, "offset": 0 } },
    { "name": "scattered characters are a subsequence, with spread", "query": "rts", "text": "run the suite", "options": {}, "expect": { "tier": 5, "offset": 0, "spread": 9 } },
    { "name": "subsequence off makes a near miss no match", "query": "rts", "text": "run the suite", "options": { "subsequence": false }, "expect": null },
    { "name": "a transposition inside a four-letter token", "query": "mian", "text": "the main branch", "options": { "fuzzy": { "maxEdits": 1, "transpositionsOnly": true } }, "expect": { "tier": 6, "offset": 4, "spread": 1 } },
    { "name": "a substitution is refused when only transpositions are allowed", "query": "mail", "text": "the main branch", "options": { "fuzzy": { "maxEdits": 1, "transpositionsOnly": true }, "subsequence": false }, "expect": null },
    { "name": "a typo in a long word is forgiven", "query": "confug", "text": "configuration", "options": { "fuzzy": "auto", "subsequence": false }, "expect": { "tier": 6, "offset": 0, "spread": 1 } },
    { "name": "fuzzy is off by default", "query": "confug", "text": "configuration", "options": { "subsequence": false }, "expect": null },
    { "name": "the exact tiers always beat the fuzzy tier", "query": "main", "text": "mian main", "options": { "fuzzy": "auto" }, "expect": { "tier": 1, "offset": 5 } }
  ],
  "policy": [
    { "token": "abc", "expect": null },
    { "token": "main", "expect": { "maxEdits": 1, "transpositionsOnly": true } },
    { "token": "branch", "expect": { "maxEdits": 1, "transpositionsOnly": false } },
    { "token": "configuration", "expect": { "maxEdits": 2, "transpositionsOnly": false } }
  ],
  "textFields": [
    { "name": "an empty query is a tier-0 aggregate", "query": "", "fields": ["Prompt", "run the tests"], "options": {}, "expect": { "tier": 0, "offset": 0, "spread": 0 } },
    { "name": "every token must land in some field", "query": "prompt tests", "fields": ["Prompt", "run the tests"], "options": {}, "expect": { "tier": 1, "offset": 8, "spread": 11 } },
    { "name": "one unmatched token fails the whole query", "query": "prompt zebra", "fields": ["Prompt", "run the tests"], "options": { "subsequence": false }, "expect": null },
    { "name": "tokens may split across fields", "query": "tool bash", "fields": ["Tool", "bash -lc ls"], "options": {}, "expect": { "tier": 2, "offset": 0, "spread": 8 } }
  ],
  "ranges": [
    { "name": "exact covers the whole text", "query": "main", "text": "main", "expect": [{ "start": 0, "length": 4 }] },
    { "name": "a substring hit is one span", "query": "the", "text": "run the suite", "expect": [{ "start": 4, "length": 3 }] },
    { "name": "a subsequence hit marks the characters it walked, merging neighbours", "query": "rts", "text": "run the suite", "expect": [{ "start": 0, "length": 1 }, { "start": 6, "length": 1 }, { "start": 8, "length": 1 }] },
    { "name": "a typo hit marks the whole word", "query": "mian", "text": "the main branch", "expect": [{ "start": 4, "length": 4 }] },
    { "name": "an empty query marks nothing", "query": "", "text": "main", "expect": [] }
  ]
}
```

`ranges` cases each state the tier they intend implicitly; compute the score with
`scoreMatch(query, text, { fuzzy: "auto" })` in the test and feed it to
`matchRanges`. **Every one of the expected values above is a claim about the
algorithm, not a guess: if an implementation faithful to the reference disagrees with
a number here, the number is wrong and you fix the fixture in this task — but only in
this task, and only with the disagreement written into the commit message.** From
task 2 onward, a failing fixture is never fixed by editing the fixture.

### 1b. TypeScript — `frontend/src/renderer/lib/text-match.ts`

```ts
export type MatchScore = { tier: number; offset: number; spread?: number };
export type FuzzyPolicy = { maxEdits: number; transpositionsOnly: boolean };
export type MatchOptions = { fuzzy?: FuzzyPolicy | null; subsequence?: boolean };
export type TextFieldsOptions = { typoTolerant?: boolean; subsequence?: boolean };
export type MatchRange = { start: number; length: number };

export const TIER_EXACT = 0;
export const TIER_WHOLE_WORD = 1;
export const TIER_PREFIX = 2;
export const TIER_WORD_START = 3;
export const TIER_SUBSTRING = 4;
export const TIER_SUBSEQUENCE = 5;
export const TIER_FUZZY = 6;

export function fuzzyPolicyForToken(token: string): FuzzyPolicy | null;
export function scoreMatch(query: string, text: string, options?: MatchOptions): MatchScore | null;
export function scoreTextFields(query: string, fields: readonly string[], options?: TextFieldsOptions): MatchScore | null;
export function matchRanges(query: string, text: string, score: MatchScore): MatchRange[];
export function compareMatchScores(a: MatchScore, b: MatchScore): number;
export function tokenizeQuery(query: string): string[];
```

Behaviour, all of it load-bearing:

- `subsequence` defaults to **on** in `scoreMatch`; callers that preselect a row turn
  it off. `fuzzy` defaults to **off** (`undefined`/`null`).
- `scoreSubstringMatch` walks every occurrence and keeps the best `(tier, offset)`.
  Tier is whole-word when both edges are word boundaries, prefix when the hit is at
  index 0, word-start when only the left edge is a boundary, substring otherwise. A
  word-boundary character is anything not matching `/[a-z0-9]/`, and the *absence* of
  a character (start or end of string) counts as a boundary.
- `boundedEditDistance` is Damerau-Levenshtein, abandoned as soon as every cell in a
  row exceeds the budget. This bound is what makes the fuzzy tier affordable.
- `scoreFuzzyMatch` compares the query against each **word** of the text, and against
  that word's leading slices at lengths `query.length` and `query.length + maxEdits`,
  so a typo in a prefix still lands.
- `scoreTextFields` sums `tier`, `offset` and `spread` across tokens, taking the best
  field per token, and returns `null` if any token matches nowhere. A token's `spread`
  defaults to the token's own length when the per-token score carried none.
- `matchRanges` derives ranges from a score rather than producing them alongside it,
  because ranking touches every candidate and only rendered rows need ranges.

Unit test file `frontend/src/renderer/lib/text-match.test.ts` reads the fixture from
`path.resolve(process.cwd(), "../testdata/search/text-match.json")` and runs all four
arrays.

### 1c. Dart — `packages/mobile/lib/core/search/text_match.dart`

`lib/core/`, not a feature: the Kanban board's session picker and plan 9's cache
search will both want it, and a matcher nested under `feature/blocks` would make them
depend on blocks.

```dart
class MatchScore extends Equatable {
  const MatchScore({required this.tier, required this.offset, this.spread});
  final int tier;
  final int offset;
  final int? spread;
  @override List<Object?> get props => [tier, offset, spread];
}

class FuzzyPolicy extends Equatable {
  const FuzzyPolicy({required this.maxEdits, required this.transpositionsOnly});
  final int maxEdits;
  final bool transpositionsOnly;
  @override List<Object?> get props => [maxEdits, transpositionsOnly];
}

class MatchRange extends Equatable {
  const MatchRange({required this.start, required this.length});
  final int start;
  final int length;
  @override List<Object?> get props => [start, length];
}

sealed class TextMatch {
  static const int tierExact = 0;
  static const int tierWholeWord = 1;
  static const int tierPrefix = 2;
  static const int tierWordStart = 3;
  static const int tierSubstring = 4;
  static const int tierSubsequence = 5;
  static const int tierFuzzy = 6;

  static FuzzyPolicy? fuzzyPolicyForToken(String token);
  static MatchScore? score(String query, String text, {FuzzyPolicy? fuzzy, bool subsequence = true});
  static MatchScore? scoreTextFields(String query, List<String> fields, {bool typoTolerant = false, bool subsequence = true});
  static List<MatchRange> ranges(String query, String text, MatchScore score);
  static int compare(MatchScore a, MatchScore b);
  static List<String> tokenize(String query);
}
```

Test file `packages/mobile/test/core/search/text_match_fixtures_test.dart`, reading
`File('../../testdata/search/text-match.json')`, with the same
`reason: 'the shared fixture is missing; never fix a failing fixture by editing it'`
existence assertion the block fixture test uses.

**Gate:** both suites green.

## Task 2 — The block action model and block-to-text, both languages.

Two pure modules, no UI, no clipboard, no HTTP.

### 2a. The action set

```ts
// frontend/src/renderer/lib/block-actions.ts
export type BlockActionKind = "copy_block" | "copy_command" | "copy_output" | "rerun" | "rewind";

export type BlockActionContext = {
  mode: "tui" | "chat";
  capabilities: readonly string[];
  canSend: boolean;
  turnInFlight: boolean;
  rollbackableTurnIds: readonly string[];
};

export type BlockAction = { kind: BlockActionKind; payload?: string; turnId?: string };

export function blockActionsFor(block: SessionBlock, ctx: BlockActionContext): BlockAction[];
export function blockCopyText(block: SessionBlock): string;
export function blocksToText(blocks: readonly SessionBlock[]): string;
```

```dart
// packages/mobile/lib/feature/blocks/logic/block_actions.dart
enum BlockActionKind { copyBlock, copyCommand, copyOutput, rerun, rewind }

class BlockActionContext extends Equatable {
  const BlockActionContext({
    required this.mode,
    this.capabilities = const [],
    this.canSend = false,
    this.turnInFlight = false,
    this.rollbackableTurnIds = const [],
  });
  final String mode;
  final List<String> capabilities;
  final bool canSend;
  final bool turnInFlight;
  final List<String> rollbackableTurnIds;
  @override List<Object?> get props => [mode, capabilities, canSend, turnInFlight, rollbackableTurnIds];
}

class BlockAction extends Equatable {
  const BlockAction({required this.kind, this.payload, this.turnId});
  final BlockActionKind kind;
  final String? payload;
  final String? turnId;
  @override List<Object?> get props => [kind, payload, turnId];
}

sealed class BlockActions {
  static List<BlockAction> forBlock(SessionBlock block, BlockActionContext ctx);
  static String copyText(SessionBlock block);
  static String blocksToText(List<SessionBlock> blocks);
}
```

**The rules, in this order, producing the list in this order.** Each is a fixture case.

1. **`copy_block`** — always, for every block, with `payload = blockCopyText(block)`.
2. **`copy_command`** — only when `detail` is the shell variant and its `command` is
   non-empty. `payload` is the command.
3. **`copy_output`** — when `detail` is the shell variant and its `output` is
   non-empty, `payload` is the output; otherwise when `block.kind === "tool"` and
   `block.body` is non-empty, `payload` is the body. Never both.
4. **`rerun`** — only when all of: `ctx.canSend`, `block.kind === "prompt"`,
   `block.body` non-empty, and `!ctx.turnInFlight`. `payload` is the body.
   **A tool block never gets `rerun`.** Re-issuing a tool call is the agent's
   operation, not Operator's; there is no route for it in either mode. Shell re-run
   arrives with plan 7 (shell blocks), which owns the mark protocol that would make it
   meaningful. Say this in the commit message so the next reviewer does not read the
   absence as an oversight.
5. **`rewind`** — only when all of: `ctx.mode === "chat"`, `ctx.capabilities`
   contains the literal string `"rollback"`, `!ctx.turnInFlight`, `block.turnId` is
   set and non-empty, and `ctx.rollbackableTurnIds` contains it. `turnId` is carried
   on the action; `payload` is unset.

Two prohibitions:

- **Never derive an action from `mode` where a capability exists.** `rewind` checks
  `mode === "chat"` only because a `tui` session has no conversation at all; the
  capability check is what actually gates it, and both must pass.
- **Never synthesize a decision id or a turn id.** `rollbackableTurnIds` is supplied
  by the caller from the snapshot; a turn absent from it is not rewindable, full stop.

### 2b. Block-to-text

`blockCopyText(block)` is deterministic and identical in both languages:

```
<display.displayName>
<display.summary>            ← omitted entirely when empty
<display.errorText>          ← omitted entirely when absent
```

joined with `\n`, then trailing whitespace trimmed. Children are appended after the
parent, each child's whole rendering indented by **two spaces on every line**,
separated from the parent and from each other by a blank line. Nesting is one level
deep by the block model's own rule, but the function recurses so a deeper tree is
still serialized rather than dropped.

`blocksToText(blocks)` joins `blockCopyText` of each top-level block with `\n\n`.

### 2c. `testdata/blocks/block_actions.json`

```json
{
  "actions": [
    {
      "name": "every block can be copied",
      "block": { "id": "b-1", "kind": "notice", "status": "ok", "title": "Session started", "body": "" },
      "context": { "mode": "tui", "canSend": true },
      "expect": [{ "kind": "copy_block", "payload": "Session started" }]
    },
    {
      "name": "a shell tool offers command and output separately",
      "block": { "id": "b-2", "kind": "tool", "status": "ok", "title": "Tool", "body": "", "detail": { "type": "shell", "command": "npm test", "output": "ok 42 tests", "exitCode": 0 } },
      "context": { "mode": "tui", "canSend": true },
      "expect": [
        { "kind": "copy_block", "payload": "Shell\nnpm test\n\nok 42 tests" },
        { "kind": "copy_command", "payload": "npm test" },
        { "kind": "copy_output", "payload": "ok 42 tests" }
      ]
    },
    {
      "name": "a non-shell tool falls back to its body for output",
      "block": { "id": "b-3", "kind": "tool", "status": "ok", "title": "Read", "body": "42 lines" },
      "context": { "mode": "tui", "canSend": true },
      "expect": [
        { "kind": "copy_block", "payload": "Read\n42 lines" },
        { "kind": "copy_output", "payload": "42 lines" }
      ]
    },
    {
      "name": "a prompt can be re-run when the composer is live",
      "block": { "id": "b-4", "kind": "prompt", "status": "ok", "title": "Prompt", "body": "run the tests" },
      "context": { "mode": "tui", "canSend": true },
      "expect": [
        { "kind": "copy_block", "payload": "Prompt\nrun the tests" },
        { "kind": "rerun", "payload": "run the tests" }
      ]
    },
    {
      "name": "re-run is withheld while a turn is in flight",
      "block": { "id": "b-5", "kind": "prompt", "status": "ok", "title": "Prompt", "body": "run the tests" },
      "context": { "mode": "chat", "canSend": true, "turnInFlight": true, "capabilities": ["rollback"], "rollbackableTurnIds": [] },
      "expect": [{ "kind": "copy_block", "payload": "Prompt\nrun the tests" }]
    },
    {
      "name": "rewind needs the rollback capability, spelled as the daemon spells it",
      "block": { "id": "b-6", "kind": "prompt", "status": "ok", "turnId": "t-1", "title": "Prompt", "body": "run the tests" },
      "context": { "mode": "chat", "canSend": true, "capabilities": ["rollback"], "rollbackableTurnIds": ["t-1"] },
      "expect": [
        { "kind": "copy_block", "payload": "Prompt\nrun the tests" },
        { "kind": "rerun", "payload": "run the tests" },
        { "kind": "rewind", "turnId": "t-1" }
      ]
    },
    {
      "name": "a capability list without rollback offers no rewind",
      "block": { "id": "b-7", "kind": "prompt", "status": "ok", "turnId": "t-1", "title": "Prompt", "body": "hi" },
      "context": { "mode": "chat", "canSend": true, "capabilities": ["streaming", "tools", "approvals"], "rollbackableTurnIds": ["t-1"] },
      "expect": [
        { "kind": "copy_block", "payload": "Prompt\nhi" },
        { "kind": "rerun", "payload": "hi" }
      ]
    },
    {
      "name": "a turn the snapshot says is not rollbackable offers no rewind",
      "block": { "id": "b-8", "kind": "prompt", "status": "ok", "turnId": "t-2", "title": "Prompt", "body": "hi" },
      "context": { "mode": "chat", "canSend": true, "capabilities": ["rollback"], "rollbackableTurnIds": ["t-1"] },
      "expect": [
        { "kind": "copy_block", "payload": "Prompt\nhi" },
        { "kind": "rerun", "payload": "hi" }
      ]
    },
    {
      "name": "tui never offers rewind however the context is filled in",
      "block": { "id": "b-9", "kind": "prompt", "status": "ok", "turnId": "t-1", "title": "Prompt", "body": "hi" },
      "context": { "mode": "tui", "canSend": true, "capabilities": ["rollback"], "rollbackableTurnIds": ["t-1"] },
      "expect": [
        { "kind": "copy_block", "payload": "Prompt\nhi" },
        { "kind": "rerun", "payload": "hi" }
      ]
    },
    {
      "name": "a redacted block is copyable; redaction already happened upstream",
      "block": { "id": "b-10", "kind": "tool", "status": "ok", "title": "Bash", "body": "token=***", "redacted": true },
      "context": { "mode": "tui", "canSend": false },
      "expect": [
        { "kind": "copy_block", "payload": "Bash\ntoken=***" },
        { "kind": "copy_output", "payload": "token=***" }
      ]
    }
  ],
  "copyText": [
    {
      "name": "a failed shell carries its exit code line",
      "block": { "id": "c-1", "kind": "tool", "status": "failed", "title": "Tool", "body": "", "detail": { "type": "shell", "command": "npm test", "output": "1 failing", "exitCode": 1 } },
      "expect": "Shell\nnpm test\n\n1 failing\nExit code 1"
    },
    {
      "name": "children are indented two spaces and separated by a blank line",
      "block": {
        "id": "c-2", "kind": "tool", "status": "ok", "title": "Task", "body": "spawned 1 subagent",
        "children": [{ "id": "c-2a", "kind": "tool", "status": "ok", "title": "Bash", "body": "ls" }]
      },
      "expect": "Task\nspawned 1 subagent\n\n  Bash\n  ls"
    }
  ],
  "selectionText": [
    {
      "name": "selected blocks join with a blank line",
      "blocks": [
        { "id": "s-1", "kind": "prompt", "status": "ok", "title": "Prompt", "body": "run the tests" },
        { "id": "s-2", "kind": "assistant", "status": "ok", "title": "Assistant", "body": "all green" }
      ],
      "expect": "Prompt\nrun the tests\n\nAssistant\nall green"
    }
  ]
}
```

**The fixture's block shape needs a decoder in each test suite, and only in the test
suite.** Production never parses a `SessionBlock` from JSON — it assembles one from
events. Write `blockFromFixture(json)` beside each fixture test:

- Fields: `id`, `kind`, `status`, `title` required; `body` defaults `""`, `turnId`,
  `detail`, `toolName`, `errorType`, `truncatedLines` default 0, `redacted` default
  false, `children` default absent, `firstSeq`/`lastSeq` default 1.
- On Dart, `detail` goes through the production `BlockDetail.fromJson`, which already
  exists at `session_block.dart:14`. Do not write a second detail decoder.
- Do not export either decoder from production code and do not put it in
  `lib/` or `src/renderer/lib/`.

**Gate:** both suites green.

## Task 3 — Find and filter over blocks, both languages.

```ts
// frontend/src/renderer/lib/block-find.ts
export type BlockMatch = { blockId: string; field: "displayName" | "summary"; score: MatchScore; ranges: MatchRange[] };
export type FilterResult = { blocks: SessionBlock[]; matchIds: ReadonlySet<string>; hiddenCount: number };

export function blockSearchFields(block: SessionBlock): string[];
export function findBlockMatches(blocks: readonly SessionBlock[], query: string): BlockMatch[];
export function filterBlocks(blocks: readonly SessionBlock[], query: string, contextBlocks: number): FilterResult;
export function nextMatchId(matches: readonly BlockMatch[], currentId: string | undefined, forward: boolean): string | undefined;
```

```dart
// packages/mobile/lib/feature/blocks/logic/block_find.dart
enum BlockMatchField { displayName, summary }

class BlockMatch extends Equatable { … blockId, field, score, ranges … }
class BlockFilterResult extends Equatable { … blocks, matchIds, hiddenCount … }

sealed class BlockFind {
  static List<String> searchFields(SessionBlock block);
  static List<BlockMatch> matches(List<SessionBlock> blocks, String query);
  static BlockFilterResult filter(List<SessionBlock> blocks, String query, int contextBlocks);
  static String? nextMatchId(List<BlockMatch> matches, String? currentId, {required bool forward});
}
```

**The rules.**

- `blockSearchFields(block)` returns exactly
  `[blockDisplay(block).displayName, blockDisplay(block).summary]`, in that order,
  with empty strings kept so field indices are stable. **Not raw `title`/`body`** —
  the offsets have to line up with what the card paints.
- `findBlockMatches` calls
  `scoreMatch(query, field, { subsequence: false })` per field and keeps the best
  field per block by `compareMatchScores`. **`subsequence` is off**, and
  **`typoTolerant` is off**: the find bar preselects its first result and scrolls to
  it, which is precisely the case paseo's own comment warns about — a near miss would
  jump the viewport away from what the user is reading. Record that reason in the
  commit message; it will look like a missing feature otherwise.
- The result is in **document order**, not rank order. Ranking exists so a match's
  quality is comparable; navigation through a transcript is positional. A block with
  no match contributes nothing.
- **Children are searched, and a matching child promotes its parent.** The match's
  `blockId` is the child's, so a client can highlight the child, but `filterBlocks`
  keeps the top-level ancestor. A child is never hoisted to the top level.
- An empty or whitespace-only query yields `[]` matches, and `filterBlocks` returns
  the input list unchanged with `hiddenCount` 0 and an empty `matchIds`.
- `filterBlocks` keeps every matching top-level block plus `contextBlocks` neighbours
  on each side; overlapping windows merge; order is preserved; `hiddenCount` is
  `blocks.length - result.blocks.length`. `contextBlocks` of 0 is legal and means
  matches only.
- `nextMatchId` wraps in both directions. With no current id, forward yields the
  first match and backward yields the last. With an id absent from `matches`, it
  behaves as if there were no current id.

`testdata/blocks/block_find.json`, three arrays — `matches`, `filter`, `navigation` —
using the same fixture block shape and `blockFromFixture` decoder as task 2. Cover at
minimum: a hit in `displayName` only; a hit in `summary` only; a query matching
neither; the subsequence-off case (`"rts"` against `"run the tests"` finds nothing);
a child match promoting its parent; context windows merging across two adjacent
matches; `contextBlocks: 0`; wrap-around forward from the last match and backward
from the first.

**Gate:** both suites green. **This is the fork point.** Commit, merge to `master`,
and if you are running two agents, create the worktrees now.

---

# Phase B, desktop lane — tasks 4-6

These three tasks touch only `frontend/`. They must not edit anything under
`testdata/` or `packages/mobile`.

## Task 4 — Desktop: collapse, and the standard action row.

### `BlockCard.tsx`

Add, alongside the untouched `renderActions`:

```tsx
export const BlockCard = memo(function BlockCard({
  block, renderActions, actions, onAction, collapsed, onToggleCollapse, highlight, selected, onToggleSelect,
}: {
  block: SessionBlock;
  renderActions?: (block: SessionBlock) => ReactNode;
  actions?: readonly BlockAction[];
  onAction?: (block: SessionBlock, action: BlockAction) => void;
  collapsed?: boolean;
  onToggleCollapse?: (blockId: string) => void;
  highlight?: { field: "displayName" | "summary"; ranges: readonly MatchRange[] };
  selected?: boolean;
  onToggleSelect?: (blockId: string, extend: boolean) => void;
})
```

`highlight`, `selected` and `onToggleSelect` are wired in tasks 5 and 6; declare them
now so the card is edited once.

- **Collapse.** `BlockCardHeader` becomes a `<button type="button">` when
  `onToggleCollapse` is supplied, with `aria-expanded` and a chevron from `lucide-react`
  (`ChevronRight` / `ChevronDown`). When `collapsed` is true, render the header and
  nothing else — no summary, no children, no error line, no redaction note, no
  truncation note, no action row. The header already carries the status dot, display
  name and kind, which is enough to find the block again.
- **Action row.** Render standard actions after the caller's `renderActions` output,
  inside the same `data-testid="block-actions"` footer, separated by a
  `<Separator orientation="vertical" />` when both are present. One `Button` per
  action, `size="sm"`, `variant="ghost"`, `data-testid={`block-action-${action.kind}`}`,
  label from i18n. `rewind` gets `variant="outline"` — it is destructive and should not
  read like a copy button.
- The card must remain `memo`'d and its props must stay comparable by reference:
  compute `actions` once per block in the parent with `useMemo`, never inline in JSX.

### Wiring in `BlocksView.tsx`

`BlocksView` owns collapse state:

```tsx
const [collapsedIds, setCollapsedIds] = useState<ReadonlySet<string>>(() => new Set());
useEffect(() => setCollapsedIds(new Set()), [sessionId]);
```

**Collapse is not persisted.** A block id is per-session, the loaded window is
bounded, and persisting would add a store for a preference nobody has asked to
survive a restart. Say so in the commit message.

`BlocksView` gains `actionContext: BlockActionContext` and
`onAction: (block, action) => void`, both required, and passes a memoized
`actionsByBlockId` down through `BlockList` to `BlockCard`.

### Wiring in `CenterPane.tsx`

`TuiSessionBlocksPane` (`CenterPane.tsx:711`) builds:

```tsx
const actionContext: BlockActionContext = { mode: "tui", capabilities: [], canSend: sessionId !== "", turnInFlight: false, rollbackableTurnIds: [] };
```

`ChatSessionBlocksPane` (`CenterPane.tsx:748`) builds it from the snapshot it already
reads. `capabilities` comes from `conversation.snapshot.capabilities` — the same array
`snapshotCan` consults; do not re-derive it. `rollbackableTurnIds` is exactly the turn
ids for which the existing `canRollbackTurnPredicate` (`CenterPane.tsx:869`) would
return true; **extract that predicate's body into a helper and use it for both**, so
the turn-group rollback control and the per-block rewind action can never disagree.

`onAction` handles:

| kind | desktop behaviour |
| --- | --- |
| `copy_block` / `copy_command` / `copy_output` | `await operatorBridge.clipboard.writeText(action.payload ?? "")` — imported from `../lib/bridge`, as `SessionsBoard.tsx:58` does |
| `rerun` | prefill the composer with `action.payload`; **do not send.** Re-running is the user's decision, and a one-click resend of a prompt into a live agent is not recoverable |
| `rewind` | open a confirmation dialog (`components/ui/dialog.tsx`), then `commands.rollback(action.turnId)` |

The rewind dialog's body text must say that the agent forgets the turn and everything
after it, and that **files on disk are not reverted**. See the rewind finding above.

### i18n

New `en.json` keys, and the same eight files: `blocks.action.copyBlock`,
`blocks.action.copyCommand`, `blocks.action.copyOutput`, `blocks.action.rerun`,
`blocks.action.rewind`, `blocks.action.collapse`, `blocks.action.expand`,
`blocks.rewindTitle`, `blocks.rewindBody`, `blocks.rewindConfirm`, `blocks.cancel`.

### Tests

`frontend/src/renderer/components/blocks/BlockCard.actions.test.tsx` — collapsing
hides summary, children, error, truncation and the action row while keeping the
header; the action row renders one button per action in order; clicking one calls
`onAction` with the block and that action.

Extend `CenterPane.blocks.test.tsx` — a chat snapshot whose `capabilities` contain the
literal `"rollback"` and whose turn is rollbackable renders `block-action-rewind`; the
same snapshot with `capabilities: ["streaming"]` does not. **Assert the string as the
daemon spells it.**

**Gate:** typecheck + vitest.

## Task 5 — Desktop: the find bar, filtering and highlighting.

### `frontend/src/renderer/components/blocks/BlockFindBar.tsx`

An `Input` from `components/ui/input.tsx`, a match counter, previous/next buttons
(`ChevronUp`/`ChevronDown`), a filter toggle (`Filter`), and a close button (`X`).
Props: `query`, `onQueryChange`, `matchCount`, `activeIndex`, `onPrevious`, `onNext`,
`filtering`, `onToggleFilter`, `onClose`.

The counter reads `{{index}} / {{total}}` and shows `blocks.find.noMatches` at zero.

### State, in `BlocksView.tsx`

```tsx
const [findOpen, setFindOpen] = useState(false);
const [query, setQuery] = useState("");
const [filtering, setFiltering] = useState(false);
const [activeMatchId, setActiveMatchId] = useState<string | undefined>(undefined);

const matches = useMemo(() => findBlockMatches(blocks, query), [blocks, query]);
const filtered = useMemo(
  () => (filtering ? filterBlocks(blocks, query, FIND_CONTEXT_BLOCKS) : { blocks, matchIds: EMPTY_SET, hiddenCount: 0 }),
  [blocks, filtering, query],
);
```

`FIND_CONTEXT_BLOCKS = 1`, exported from `block-find.ts` so both clients use the same
default.

- Changing the query resets `activeMatchId` to `matches[0]?.blockId`.
- `Cmd/Ctrl+F` opens the bar and focuses the input when the blocks pane has focus;
  bind on the scroll container, not on `window`. `Escape` closes, clears the query and
  turns filtering off. `Enter` / `Shift+Enter` step forward and backward.
- When `filtering` is on and `hiddenCount > 0`, render a one-line notice above the
  list: `blocks.find.hidden` with `{{count}}`.
- When the query is non-empty but `matches` is empty, the list still renders
  unfiltered; do not blank the screen.

### Highlighting and scrolling, in `BlockList.tsx`

`BlockList` takes `matchesByBlockId: ReadonlyMap<string, BlockMatch>` and
`activeMatchId`, passes `highlight` to the matching `BlockCard`, and on
`activeMatchId` change calls `virtualizer.scrollToIndex(index, { align: "center" })`
for that block's index in its current (possibly filtered) list.

`BlockCard` renders a highlighted string with a small local helper:

```tsx
function highlighted(text: string, ranges: readonly MatchRange[]): ReactNode
```

which slices `text` by ranges and wraps each range in
`<mark className="rounded-[2px] bg-warning/30 text-foreground">`. The active block's
`<mark>` gets `data-testid="block-match-active"`. Ranges arrive sorted and
non-overlapping from `matchRanges`; assert that with a test rather than defensively
sorting at render time.

### i18n

`blocks.find.open`, `blocks.find.placeholder`, `blocks.find.previous`,
`blocks.find.next`, `blocks.find.close`, `blocks.find.filter`, `blocks.find.counter`,
`blocks.find.noMatches`, `blocks.find.hidden` — eight files each.

### Tests

`BlockFindBar.test.tsx` and an extension of `BlockList.test.tsx`: typing a query marks
the matching substring; next/prev move the active match and wrap; the filter toggle
reduces the rendered blocks and shows the hidden count; `Escape` clears everything.

**Gate:** typecheck + vitest.

## Task 6 — Desktop: cross-block selection and copy.

**Native text selection across blocks is deliberately not offered.** The list is
virtualized by `@tanstack/react-virtual`; rows outside the window are unmounted, so a
DOM selection anchored above the rendered range silently truncates when copied. A
silent truncation of the user's transcript is worse than an explicit selection
affordance. Native selection **within** one block is untouched and keeps working.

Instead: block-granular selection.

- A `Select` toggle in the find bar enters selection mode. In selection mode each
  `BlockCard` header gets a checkbox-shaped hit target; clicking anywhere on the
  header toggles that block; `Shift`-click extends from the last-toggled anchor by
  index in the currently rendered list.
- An action bar pinned to the bottom of the pane shows `{{count}} selected`, a **Copy**
  button and a **Cancel** button. Copy writes `blocksToText(selected)` through
  `operatorBridge.clipboard.writeText`, then exits selection mode.
- `Escape` exits selection mode. Changing session clears it, like collapse state.
- Selection order is document order, never click order: `blocksToText` receives the
  blocks filtered from the list, not from the selection set's iteration order.

`selected` and `onToggleSelect` were already declared on `BlockCard` in task 4; wire
them now. Selected cards get `data-testid="session-block-selected"` and a
`border-primary` ring.

i18n: `blocks.select.enter`, `blocks.select.count`, `blocks.select.copy`,
`blocks.select.cancel` — eight files.

Tests: shift-click selects a contiguous run; copy calls the bridge with the blocks
joined in document order regardless of click order; leaving selection mode clears it.

**Gate:** typecheck + vitest.

---

# Phase B, mobile lane — tasks 7-9

These three tasks touch only `packages/mobile/`. They must not edit anything under
`testdata/` or `frontend/`.

## Task 7 — Mobile: collapse, and the block action sheet.

### `block_card.dart`

```dart
const BlockCard({
  super.key,
  required this.block,
  this.actionsBuilder,
  this.actions = const [],
  this.onAction,
  this.collapsed = false,
  this.onToggleCollapse,
  this.highlight,
  this.selected = false,
  this.onToggleSelect,
  this.selectionMode = false,
});
```

`highlight`, `selected`, `onToggleSelect` and `selectionMode` are wired in tasks 8 and
9; declare them now so the card is edited once.

- **Collapse.** Tapping the header toggles it when `onToggleCollapse` is non-null. The
  header gains a leading `Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
  size: 16, color: skin.textTertiary)`. Collapsed renders the header alone.
- **Actions.** Long-pressing the card opens a bottom sheet
  (`showModalBottomSheet`, following `conversation_menu_sheet.dart`'s shape) listing
  one row per `BlockAction`, with `Haptics.tap()` on open. The existing
  `actionsBuilder` output continues to render inline in the card footer, unchanged —
  approvals must stay one tap away, not behind a long-press.
- Copy actions use `Clipboard.setData(ClipboardData(text: action.payload ?? ''))`
  followed by `Haptics.success()` and a `SnackBar`. `chat_atoms.dart:131` is the
  existing precedent for this exact pair.

New widget file:
`packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_action_sheet.dart`,
exposing `Future<BlockAction?> showBlockActionSheet(BuildContext, List<BlockAction>)`.
Labels are inline English: `Copy block`, `Copy command`, `Copy output`,
`Re-run this prompt`, `Rewind the conversation`.

### Wiring

`BlocksBody` (tui) builds
`const BlockActionContext(mode: 'tui', canSend: true)`.

`ChatBlocksBody` builds it from the snapshot it already reads at
`chat_blocks_body.dart:57` and `:103-111`:

```dart
final capabilities = snapshot?.capabilities ?? const <String>[];
final hasInFlightTurn = snapshot?.turns.any((t) => t.state == 'running' || t.state == 'queued') ?? false;
```

`rollbackableTurnIds` must be produced by the **same** predicate as
`canRollbackTurnGroup` at `chat_blocks_body.dart:199`. Extract that body into a
function in `block_actions.dart` or a local helper used by both; two copies of this
rule will drift.

`rewind` opens an `AlertDialog` confirming that the agent forgets the turn and
everything after it and that **files on disk are not reverted**, then calls
`repository.rollbackTurn(sessionId, RollbackTurnParams(turnId: action.turnId!))` —
the call already used at `chat_blocks_body.dart:191`.

`rerun` fills the composer rather than sending. On chat that is
`ChatComposer`'s controller, reached from `ChatBody`; on tui it is the send route.
If threading the text to the composer is more than a small change in the mobile lane,
**stop and report it** rather than sending on the user's behalf.

Collapse state is a `Set<String>` in `_BlocksBodyState` / `ChatBlocksBodyState`,
cleared when `sessionId` changes. Not persisted, for the same reason as desktop.

### Tests

`packages/mobile/test/feature/blocks/presentation/block_card_collapse_test.dart` and
`block_action_sheet_test.dart`, both using the `_pump` shape from
`block_card_actions_test.dart:33`. Extend
`test/feature/blocks/presentation/chat_blocks_body_test.dart` with a snapshot whose
`capabilities` contain the literal `'rollback'` and one that does not.

**Gate:** `flutter analyze` (must print `No issues found!`) and `flutter test`.

## Task 8 — Mobile: find, filter and highlight.

New widget
`packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_find_bar.dart`
— an `AppTextField` (`core/widgets/main_widgets/app_text_field.dart`), a counter, up
and down `IconButton`s, a filter toggle and a close button, laid out in a `Row` above
the list.

State lives in `_BlocksBodyState` and `ChatBlocksBodyState`: `query`, `filtering`,
`activeMatchId`, plus `matches` and `filtered` recomputed from `BlockFind` on every
build. Both use `FIND_CONTEXT_BLOCKS` = 1, matching desktop.

**Opening it.** Both screens already reach their body's state through a
`GlobalKey`; `ChatScreen` does exactly this at `chat_screen.dart:29` and `:41`
(`_body.currentState?.openMenu()`). Follow it:

- Rename `_BlocksBodyState` to `BlocksBodyState` and `_ChatBlocksBodyState` to
  `ChatBlocksBodyState`, both with a public `void openFind()`. `BlockListState` is
  already public for the same reason, so this is the established pattern rather than a
  new one.
- `ChatBody` holds a `GlobalKey<ChatBlocksBodyState>` and exposes
  `ChatBodyState.openFind()`, which `ChatScreen` calls from a new search
  `IconButton` in `GlobalAppbar.sub`'s `actions`, beside the existing overflow button.
- The tui path adds the same button wherever `BlocksBody` is mounted
  (`terminal_body.dart:78`).

**Scrolling to a match.** `BlockListState.scrollBlockIntoView(int index)` already
exists (`block_list.dart:139`); call it with the active match's index in the current
list. Do not add a second scroll path.

**Highlighting.** `BlockCard` renders the display name and summary through a helper
that builds a `Text.rich` with a `TextSpan` per range, the marked spans carrying
`backgroundColor: skin.tintAmber`. Keep it in `block_card.dart`; it is four lines and
does not want a file.

Tests: `block_find_bar_test.dart` (typing filters, counter text, next wraps) and an
extension of `block_list_test.dart` asserting a highlighted span appears on the
matching card.

**Gate:** `flutter analyze` and `flutter test`.

## Task 9 — Mobile: selection mode and copy.

- **Long-pressing a block header** enters selection mode with `Haptics.select()`.
  (Long-pressing the card *body* opens the action sheet from task 7; the two gestures
  must not collide, so the sheet's `GestureDetector` wraps the body only.)
- In selection mode, tapping any card toggles it; the header shows a leading
  check circle; selected cards get `border: Border.all(color: skin.blue)`.
- A bar pinned above the composer shows `N selected`, **Copy** and **Cancel**.
  Copy writes `BlockActions.blocksToText(selected)` to the clipboard with
  `Haptics.success()` and a `SnackBar`, then exits.
- Selection is cleared on session change and on back navigation. Android's system
  back gesture must exit selection mode rather than leaving the screen: wrap in a
  `PopScope` with `canPop: !selectionMode`.
- Blocks are copied in document order, never selection order.

Test: `block_selection_test.dart` — long-press enters the mode, tap toggles, copy
writes document order for an out-of-order selection, `PopScope` blocks the pop while
selecting.

**Gate:** `flutter analyze` and `flutter test`.

---

# Phase C — the testing debt from the amendment table

The amendment *"Load-generating source + browser e2e | Testing | 4b, then 6"* landed
after plans 4a and 4b shipped, so it falls here. **These two tasks are the cut line.**
If the plan has to shrink, cut 11 then 10, and record in the spec that the obligation
moved to plan 7. Cutting anything in phases A or B instead would ship a feature
without its contract.

## Task 10 — A load-generating block source, in the product.

The spec: *"'Frame-time profiling under a synthetic long session' is not a testable
instruction. … Build the equivalent: a source that replays a fixture stream at a
configurable rate onto the `blocks` channel."*

`backend/internal/service/blockevent/replay.go`:

```go
// Replay drives synthetic block events through the real Record path so a long
// session can be reproduced by hand and driven from a test.
type Replay struct{ Svc *Service }

type ReplayInput struct {
    SessionID domain.SessionID
    Harness   string
    Events    int
    RatePerSecond int
}

func (r *Replay) Run(ctx context.Context, in ReplayInput) error
```

It emits a repeating cycle through `Service.Record` — `session-start`,
`user-prompt-submit`, four `post-tool-use` with distinct `ToolUseID`s, one
`post-tool-use-failure`, `stop` — spaced by a `time.Ticker` at `RatePerSecond`, until
`Events` have been recorded or `ctx` is done. Event names must come from
`claudeCodeEvents` at
`backend/internal/adapters/agent/blockdispatch/dispatch.go:39-47`; an unrecognized
name maps to `BlockEventUnknown` and the replay would be testing the wrong path.

Because it goes through `Record`, it exercises redaction, truncation, persistence,
trimming and the mux publish exactly as a real hook would. That is the point: a
replayer that publishes straight to the channel would test the client against a path
production never takes.

**Route.** `POST /api/v1/dev/block-replay`, registered in `DevController.Register`
(`backend/internal/httpd/controllers/dev.go:28`) beside the three existing dev routes,
returning `202` immediately and running on its own goroutine.

**It must be inert unless explicitly enabled.** The existing dev routes are in the
shipped binary, and this one writes into a real session's block log. Guard it: unless
`OPERATOR_DEV_BLOCK_REPLAY=1` is set in the daemon's environment, the handler answers
with `apispec.NotImplemented`, exactly as an unwired service does. State the variable
in the handler's doc comment — `dev.go` comments its exported surface, so a comment
belongs here.

Request/response DTOs go in `controllers/dto.go` beside `DevImportProjectsRequest`.

**Gates:** `npm run lint` and `npm run api` (dev routes *are* in
`backend/internal/httpd/apispec/openapi.yaml` — see lines 339, 376, 413 — so the
generated spec and `frontend/src/api/schema.ts` both move). Never hand-edit
`openapi.yaml` or `backend/internal/storage/sqlite/gen/`.

Test: a fake `Store`/`Publisher` pair counting records, asserting the kind sequence,
that `Events` is respected exactly, and that cancelling the context stops it.

## Task 11 — Blocks reach the browser e2e suite.

### Threshold virtualization

The spec, from the paseo review: *"Virtualize above a threshold, not always. … Adopt
the threshold."* Plans 4a and 4b predate that amendment and virtualize
unconditionally.

In `frontend/src/renderer/lib/block-viewport.ts`:

```ts
export const VIRTUALIZATION_THRESHOLD = 100;
export function virtualizationThreshold(): number;
```

`virtualizationThreshold()` reads
`globalThis.__OPERATOR_E2E_BLOCK_VIRTUALIZATION_THRESHOLD` when it is a finite number
and returns `VIRTUALIZATION_THRESHOLD` otherwise. This is the one place a test-only
global is read, which is what keeps the branch out of `BlockList` and out of every
other production path — the mechanic is borrowed from paseo's
`__PASEO_E2E_WEB_PARTIAL_VIRTUALIZATION_THRESHOLD` for exactly that reason.

`BlockList` renders all rows when `blocks.length < virtualizationThreshold()` and
virtualizes above it. The mounted path still needs append anchoring and the sticky
header; keep both code paths behind the same handlers rather than forking the
component.

### The fake blocks socket

`frontend/e2e/support/fake-blocks-mux.ts`, modeled on
`frontend/e2e/support/fake-terminal-mux.ts` — a `page.addInitScript` that installs a
`FakeWebSocket` answering the `blocks` channel. The client frames it must honour are
in `frontend/src/renderer/lib/terminal-mux.ts:75-80`:

```ts
JSON.stringify({ ch: "blocks", type: "subscribe", id: sessionId })
JSON.stringify({ ch: "blocks", type: "unsubscribe", id: sessionId })
```

and the server frames it emits are the `ch: "blocks"` shape handled at
`terminal-mux.ts:226`. Expose `window.__aoFakeBlocksMux` with `emit(sessionId, record)`
and `stats()`, following the terminal fake's controller shape exactly. **No production
code may branch on being under test.**

### The specs

`frontend/e2e/blocks-viewport.spec.ts` — with the threshold overridden to 4 so a
twelve-block fixture exercises the virtualized path:

- appended blocks follow the tail while pinned;
- appended blocks do not move the viewport while scrolled up;
- **Load older** prepends without moving the read position;
- the sticky header appears for a short block and is suppressed for a block taller
  than the viewport (`headerSticks`'s exception).

`frontend/e2e/blocks-find.spec.ts`:

- the find bar filters the list and reports the hidden count;
- next/previous scroll the active match into view and wrap;
- selection mode copies the selected blocks in document order.

Clipboard assertions in Playwright read
`navigator.clipboard.readText()` after granting `clipboard-read`/`clipboard-write`
permissions on the context.

**Gate:** `npm --prefix frontend run test:e2e`, plus typecheck and vitest for the
`block-viewport.ts` change.

## Task 12 — Optional: put the command palette on the shared matcher.

`matchScore` at `frontend/src/renderer/lib/command-palette.ts:329` is the second,
weaker matcher the spec names. Reimplement it over `scoreTextFields`:

```ts
export function matchScore(query: string, item: CommandItem): number
```

keeps its signature and its "higher is better" contract for `filterCommands`
(`command-palette.ts:352`), computed as `Number.MAX_SAFE_INTEGER` minus the aggregate,
or `0` for no match. Fields are `[item.title, item.subtitle ?? "", ...(item.keywords ?? [])]`
and **`subsequence: false`** — the palette preselects its first row, and that is the
case paseo's comment calls out by name.

`frontend/src/renderer/lib/command-palette.test.ts` will move. **If an assertion
changes, do not edit it to match the new output unless the new order is defensibly
better; stop and report the diff instead.** This task exists to remove a duplicate,
not to change what the palette does, and it is the one task in this plan that is
allowed to end in a report rather than a merge.

**Gate:** typecheck + vitest.

---

## Running this with two agents

1. One agent, one worktree: tasks 1-3. Merge to `master`.
2. Fork two worktrees from that commit.
   - Agent **D**: *"Execute plan 6, tasks 4, 5 and 6, from
     `docs/superpowers/plans/2026-08-28-block-actions-find-selection.md`. Phase A is
     already on master. Do not edit `testdata/` or `packages/mobile`."*
   - Agent **M**: *"Execute plan 6, tasks 7, 8 and 9, from the same file. Phase A is
     already on master. Do not edit `testdata/` or `frontend/`."*
   Each worktree needs its own `node_modules` (root, `frontend/`, and
   `frontend/src/landing/`) or its own `flutter pub get`; a worktree with neither runs
   no gate at all.
3. Merge both, run **all four** gates on merged `master`, not on either branch.
4. Tasks 10-12 afterwards, in either worktree or a third.

**Why the split is here and not between the clients from the start.** Tasks 1-3
produce one algorithm written twice and pinned by fixtures both suites read; a
Dart-only agent cannot run vitest and a TypeScript-only agent cannot run
`flutter test`, so a disagreement would surface only at the second merge, in the other
client's code. That is exactly the reasoning that kept plan 5 whole. Once the fixtures
are green in both languages, the two UI lanes share no file and the argument stops
applying.

## Risks

- **Capability-string drift, again.** Plan 5 shipped a dead feature by gating on
  `"approve"` instead of `"approvals"`, with fourteen green tests. Every gate in this
  plan is traced to `ports/chat.go` in task 2's fixture, and the fixture spells the
  strings the daemon spells. Do not re-derive them from a client-side constant.
- **Rewind labelled as more than it is.** Operator's rollback discards conversation
  history and touches no files. If either client's copy implies otherwise, a user will
  lose work believing it was reverted.
- **A green suite over a dead surface.** Plan 5's cleanup found mobile chat rendering
  a block list with no composer, because every test asserted what the code did and none
  asserted that a user could send a message. Each UI task here ends with a test that
  drives the *user's* path — open find, type, jump; select two blocks, copy, read the
  clipboard — not one that asserts a prop was threaded.
- **The card is edited by both lanes.** `BlockCard.tsx` and `block_card.dart` each take
  their full prop set in tasks 4 and 7 respectively, before find and selection need
  them, so the later tasks in each lane add behaviour rather than signatures.
- **e2e is a separate gate and a separate cost.** Task 11 is the only task that needs a
  browser. If it is cut, say so in the spec rather than leaving the amendment table
  claiming coverage that does not exist.

## Spec changes this plan requires

When phase A merges, update
`docs/superpowers/specs/2026-08-27-session-blocks-design.md`:

- In *Block actions*, correct the rewind route and record that Operator's rollback is
  **conversation-only**, replacing the open question with the answer.
- In *Implementation plans*, mark row 6 `written` with this file's name.
- If tasks 10-11 are cut, move the *Load-generating source + browser e2e* amendment
  from plan 6 to plan 7 in the amendment table, and add the gap to *Limits*.
