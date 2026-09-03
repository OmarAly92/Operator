# Design — Phase 8: the Warp-grade terminal on Flutter

Status: not started. This spec covers phase 8 of
[`2026-08-29-warp-terminal-package-design.md`](2026-08-29-warp-terminal-package-design.md)
in full.
Date: 2026-09-03
Author: design session with the user, 2026-09-03
Parent spec: `2026-08-29-warp-terminal-package-design.md` §14 phase 8, §2.2
Reference codebase: Warp at `/Users/omaraly/development/AI/warp` (read-only; we never
copy code, we learn from it)

---

## 0. How to use this spec

**0.1 — The decisions in §2 are closed.** They were made by the user in a design
session on 2026-09-03. Every one has its reasoning recorded. Do not reopen them, do
not "improve" them, do not propose an alternative in the plan. If you believe one is
wrong, stop and say so to the user in one paragraph — do not silently plan something
else.

**0.2 — The evidence is checkable. Check it.** Every claim about Warp cites
`file:line` in `/Users/omaraly/development/AI/warp`; every claim about Operator cites
`file:line` in this repo. If a citation does not say what this spec says it says, that
is a bug in this spec — report it rather than planning around it.

**0.3 — The parent spec's rules still bind.** §0.1–§0.7, §3 (where Warp is wrong for
us), §7 (the mark protocol), §15 (wrong turns) of the parent spec apply unchanged. This
document adds to them; it overrides nothing.

**0.4 — This is one spec covering full parity, by explicit user decision.** The parent
spec's §0.3 ("a plan covers one phase") is satisfied here by §8's internal stages: the
stages are ordered, each is independently shippable, and each has mechanically checkable
acceptance criteria. A plan covers **one stage**. The user chose full parity over
decomposition into 8a/8b/8c after being shown the trade-off.

**0.5 — Acceptance criteria are the contract.** "It works" is not a criterion.
`flutter test --plain-name 'vectors'` passing against the shared protocol vectors is.

**0.6 — Scope discipline.** This spec covers a new Dart package, the changes to
`packages/mobile` needed to host it, and two named gaps in `core/mux`. It does not
authorize backend changes, changes to `packages/terminal`, or refactoring any other
mobile feature.

**0.7 — CLAUDE.md wins over general Flutter convention.** `packages/mobile` has its own
rules (AppSkin rather than `AppColors`/`AppTextStyle` colour constants, inline English
copy rather than a `LocaleKeys` catalogue, `Navigator.of(context)` with `RoutesStrings`,
hand-written models, cubit-only, no `freezed`/`json_serializable`). Where a general
Flutter skill or convention contradicts CLAUDE.md, CLAUDE.md wins. The new package is
a *package*, not a feature, so the feature-architecture tree applies to
`feature/terminal` only.

---

## 1. What phase 8 is

The parent spec allots phase 8 four lines: deliver the block renderer and input editor
in Flutter against the same daemon block stream, accept when `flutter analyze` and
`flutter test` pass and a session shows the same blocks on phone and desktop.

That understates the work in one specific way, and this spec exists mostly to correct
it.

**The daemon block stream is history, not rendering.** `terminalBlockFrame.RawOutput`
is raw PTY bytes (`backend/internal/terminal/protocol.go:110`), and terminal blocks are
published only once committed. `GetOutput` returns plain text, not styled spans
(`backend/internal/session_manager/manager.go:196`). There is no server-side styled
rendering to consume. A live terminal on a phone therefore needs a **VT parser on the
client**, exactly as the desktop does — the daemon stream supplies durability and
scrollback, not pixels.

Everything below follows from that.

---

## 2. Decisions

**2.1 — The VT engine is Dart, built on the vendored `xterm` fork.**
`packages/mobile/packages/xterm` is a complete 13,213-line Dart VT stack (parser,
buffer, cell, reflow, snapshot, input) already vendored, already shipping, already
building on both platforms with no native toolchain.
*Reasoning:* the alternative is `vt-core` (~6,000 lines of Rust) over `dart:ffi`, which
buys cell-level parity with desktop at the cost of NDK and Xcode in CI, prebuilt binary
artifacts, and a build gate — and CLAUDE.md is explicit that native code is covered by
neither `flutter analyze` nor `flutter test` today. Desktop parity is enforced where it
actually matters, at the **mark protocol** (§4), not cell-for-cell.
*Consequence accepted:* a second VT implementation exists and must be kept honest.

**2.2 — The `xterm` fork becomes an engine, not a widget.** We keep `lib/src/core/`
(parser, buffer, cell, reflow, snapshot, input) and delete `terminal_view.dart` and
`lib/src/ui/`. Operator owns every pixel.
*Reasoning:* follows from 2.4 and 2.5 — if Operator renders both the normal buffer and
the alternate screen, the fork's own widget layer has no remaining caller.
*Consequence accepted:* the fork's role changes materially and its `FORK.md` must say
so. Diffs against upstream stay small in `core/`, which is where re-applying matters.

**2.3 — Full parity in one spec, including completions.** Blocks, editor, alt screen,
completions, navigation, find, actions.
*Reasoning:* user decision. Supported by measurement: our own `ts/completions` is 1,582
lines with three providers (command, flag, path) and three specs (cd, docker, git) —
a modest port, not the phase-sized risk that Warp's `warp_completer` crate tree would
suggest.
*Consequence accepted:* §8's stages carry the sequencing that decomposition would
otherwise have provided.

**2.4 — The block terminal replaces the xterm surface outright.**
`raw_terminal_pane.dart` and the fork's `TerminalView` are deleted in this phase. **No
user-facing flag and no fallback surface ever ships.** Both surfaces exist in the tree
during stages 8.2–8.5 purely because the replacement is not finished until 8.6 deletes
them (wrong turn 10); that is an implementation interval, not a dual-surface period the
user is ever exposed to or asked to choose between.
*Reasoning:* user decision, and the cost that normally forbids this does not apply —
Operator has no users yet, and breaking changes are this project's budget for complete
removals. Desktop needed the phase 3→7 arc because it was replacing a surface people
used daily; mobile is not in that position.
*Consequence accepted:* there is no escape hatch. Any gap ships as a broken terminal.
This raises the bar on §9's testing rather than lowering it, and it is why the bench
baseline in §8.0 is recorded **before** anything is replaced.

**2.5 — The alternate screen gets a Dart grid too.** One renderer owns both buffers.
*Reasoning:* user decision; it is what makes 2.2 and 2.4 coherent — keeping
`TerminalView` only for the alt screen would leave two input paths and two renderers
alive permanently.
*Consequence accepted:* mouse reporting, focus reporting, cursor shapes and DECSET
modes are reimplemented in Dart for a case a phone user hits least often.

**2.6 — Completions render as a floating popup above the composer.** Name, description
and source tag per row.
*Reasoning:* user decision, chosen over an accessory strip and a grouped sheet after
seeing all three. It is the only one of the three with room for the command-signature
data the engine produces, and it reuses desktop's mental model and most of its
selection logic.
*Consequence accepted:* the popup occludes the block list. §6.4 makes mitigating that
an obligation with tests, not a matter of taste.

**2.7 — The engine is a pub workspace package with a host seam.**
`packages/mobile/packages/operator_terminal`, beside the `xterm` and `speech_to_text`
forks.
*Reasoning:* `packages/terminal` is deliberately product-independent — Operator
concepts stay on the host side of the seam. The Dart engine holds the same line: it is
testable without the app, and the mark decoder gets a natural home.
*Consequence accepted:* a workspace member and a `flutter pub get` after the pubspec
change.

**2.8 — Phase 8 has a bench gate, mirroring desktop's.**
*Reasoning:* user decision. It is the only way "same quality" is checkable rather than
asserted, and it runs under `flutter test` with no new toolchain.
*Consequence accepted:* §8.0 must record the xterm baseline before replacing anything,
because a baseline cannot be recovered after the thing being measured is deleted.

---

## 3. Package structure

`packages/mobile/packages/operator_terminal`, mirroring `packages/terminal`'s split:

| Directory | Owns | Desktop counterpart |
| --- | --- | --- |
| `lib/src/vt/` | VT engine; both buffers; alt-screen state | `crates/vt-core` |
| `lib/src/marks/` | Dart mark decoder | `crates/marks`, `go/marks` |
| `lib/src/blockgrid/` | Block identity, sum tree, index, filter, selection, find | `vt-core` blockgrid |
| `lib/src/render/` | Block list, block body, alt grid, cursor, sticky header | `ts/renderer-dom` |
| `lib/src/editor/` | Line editor, buffer replica, history, ownership | `ts/editor` |
| `lib/src/completions/` | Parse/match/rank, providers, popup surface | `ts/completions` |
| `lib/src/host/` | `TerminalHost` — the seam | `HostCapabilities` |

**Nothing Operator-specific crosses into the package.** No `ServerConfig`, no
`MuxClient`, no `GlobalResponse`, no Operator model. `feature/terminal` implements
`TerminalHost` and composes the package's widgets, staying the thin
data/logic/presentation feature CLAUDE.md describes.

**`TerminalHost` has no method that can execute anything.** It writes bytes, resizes,
fetches committed blocks, persists bookmarks, and reaches clipboard and haptics. The
rerun action writes a command into the editor; the *user* runs it. This is the parent
spec §14 phase 5 rule, carried over verbatim.

### 3.1 The engine's relationship to the fork

`TerminalEngine` **composes** the fork's `Terminal`
(`packages/mobile/packages/xterm/lib/src/terminal.dart:28`, which already
`implements EscapeHandler`) rather than reimplementing a grid. Blocks are attached by:

1. intercepting `unknownOSC(String ps, List<String> pt)` (`terminal.dart:903`), where
   OSC 133 and OSC 7000 already arrive today classified as unknown; and
2. recording the cursor row at mark time.

**A block is a row-range into the xterm buffer, never a second copy of the text.** This
is the load-bearing simplification of the whole design: it is what makes a Rust core's
job affordable in Dart, and it is why §9's reflow tests matter more here than they did
on desktop.

---

## 4. Marks — the third decoder

`lib/src/marks/` is a pure Dart decoder: bytes in, `MarkEvent`s out, zero Flutter
imports.

It is conformance-tested against `packages/terminal/protocol/vectors/*.json` — the same
20 vectors the Rust and Go decoders read. **A change to the protocol fails all three
decoders at once.** That is the stated purpose of the vectors directory
(`packages/terminal/protocol/SPEC.md` §1), and Dart becomes its third client.

The decoder never throws and never drops a block:

- `A` with a block already open → close the previous as unterminated
  (`a-with-block-already-open.json`)
- `B` with no preceding `A` → open implicitly (`b-with-no-preceding-a.json`)
- `C` with no preceding `B` → tolerated (`c-with-no-preceding-b.json`)
- `D` with no open block → ignored (`d-with-no-open-block.json`)
- `D` with a missing exit code → block closes, exit unknown (`d-with-missing-exit.json`)
- truncated sequence → consumed and discarded (`malformed-truncated-sequence.json`)
- unknown OSC 7000 keys → ignored individually, never fatally
  (`extension-higher-version-ignored.json`)

**Tier 1 must stand alone.** No code path may require a Tier-2 mark to close a block.
A session with no bootstrap — plain ssh, a container — still produces usable blocks
from OSC 133 alone. This gets an explicit test, not an assumption.

---

## 5. Data flow

### 5.1 Three inputs, one timeline

1. **Live bytes.** `ch:terminal` → `TerminalDataEvent(Uint8List)`
   (`packages/mobile/lib/core/mux/mux_client.dart:185`) → the existing chunked UTF-8
   decoder (`.../terminal_cubit.dart:108`, which exists so a multi-byte rune split
   across two frames still decodes — keep it) → `TerminalEngine.write` → parser →
   `unknownOSC` → `MarkDecoder` → blocks form. **This is the only source that can render
   the in-progress block.**
2. **Committed blocks, live.** `ch:blocks` with `blockType: "terminal_block"`, keyed by
   `handleId`.
3. **Committed blocks, history.** `GET /api/v1/shell-terminals/{handleId}/blocks?limit=100`,
   paged backward for scrollback above the live session.

### 5.2 Two gaps in `core/mux` that must be closed

Both are verified defects today, not new features:

- **Terminal block subscription is a separate opt-in.** The daemon keeps `termBlockSubs`
  distinct from `blockSubs` and selects between them on
  `msg.BlockType == blockTypeTerminalBlock`
  (`backend/internal/terminal/manager.go:544`). `MuxClient` has no way to send it;
  it needs `subscribeTerminalBlocks(handleId)` / `unsubscribeTerminalBlocks(handleId)`,
  keyed by handle, restored on reconnect the way `_blockSessions` already is.
- **Terminal block frames are silently dropped.** The server sends the payload under
  `terminalBlock` (`manager.go:638`), while `MuxClient` reads only `msg['block']`
  (`mux_client.dart:204`). A terminal-block branch and a `TerminalBlockEnvelope` are
  required.

`EndPoints` also needs `shellTerminalBlocks(String handleId)` as a **static method** —
interpolating at the call site is forbidden by CLAUDE.md, and
`end_points.dart:45,47` already establishes the pattern with `shellTerminal(handleId)`.

### 5.3 Reconciliation — the hardest problem in phase 8

Sources 1 and 2 overlap: a block you watched run live *also* arrives committed. Without
reconciliation, every command appears twice the moment it finishes.

The blockgrid holds one map `sourceId → BlockId`.

- A committed record for a **known** `sourceId` **replaces in place**, keeping its
  `BlockId`, its bookmark, and its scroll identity. It never appends.
- A committed record for an **unknown** `sourceId` inserts, ordered by
  `(captureEpoch, startOffset)` — the only ordering that survives a daemon restart
  mid-session. Both fields are on the wire
  (`backend/internal/terminal/protocol.go:117-119`).
- Live blocks are **provisional**. The committed record is authoritative for
  `exitCode`, `truncatedLines` and `truncatedBytes`.

### 5.4 Rendering committed blocks

`rawOutput` is raw ANSI. It is parsed by a **detached** `TerminalEngine` at the block's
own width — never the live engine — so replaying history cannot disturb the live grid
or cursor. The result is cell runs cached against the block and re-parsed only on width
change.

### 5.5 Input, gated

Keystrokes reach the PTY one of two ways, and `InputOwnership` is the gate:

- **Not owned** — passthrough. Bytes go straight to `ch:terminal`, exactly as today.
  This is the alternate screen, and any moment we have not been told the line editor is
  idle.
- **Owned** — the Dart line editor holds the line. Nothing reaches the PTY until submit,
  at which point the command plus `\r` is written.

**Ownership flips only on `input-ready` / `input-released` marks.** No timer, no precmd
proxy, no heuristic.

This is parent spec §3.5, and reading the reference confirmed it rather than softening
it: Warp decides the line editor is idle with a 50ms timer
(`app/src/terminal/line_editor_status.rs:18`) plus `did_receive_zsh_precmd`
(`:39`) as a proxy for whether the session is bootstrapped. Its own comment says the
delay exists to avoid "sending an escape sequence to an arbitrary running program".
We have an explicit mark and do not need either. **Take nothing from this file.**

**Unknown state means not owned**, so the failure mode is a plain working terminal,
never a swallowed keystroke.

### 5.6 Alternate screen

`AltScreenState` is explicit tracked state driven by `?1049` — modelled as state, not
inferred at each use, which is the one thing Warp's `app/src/terminal/alt_screen/` gets
right for us. On entry: blocks freeze, the editor releases, completions go inert,
`AltScreenView` takes the viewport. On exit: the block list resumes at the bottom.

Parent spec §15 item 18 applies: `?1049` reflects what the **outermost** program wants,
and since the tmux removal the outermost program is the agent, which is in the normal
buffer.

---

## 6. Rendering

### 6.1 Viewport anchoring — taken from Warp

`app/src/terminal/block_list_viewport.rs` is the most directly applicable file in the
reference, and it solves a problem a naive Flutter `ListView` gets wrong.

- **Scroll is tracked from the top when the input sits below the block list, and from
  the bottom when the list is inverted** (`:68-73`), so a long-running command emitting
  output does not drag the viewport out from under the reader. This is the mechanism
  that makes a live-growing list feel stable, and we take it.
- **`OverhangingBlock`** (`:302`) models a block partially scrolled off the bottom
  explicitly rather than letting it fall out of the layout.
- **Viewport iteration is in model coordinates regardless of render direction**
  (`:338`, `:380`), so a block index means one thing everywhere. We adopt this: render
  direction never leaks into `BlockId` ordering.

### 6.2 Block list

`BlockListView` virtualizes over the blockgrid sum tree, whose summary carries row count
and match count — which is what makes viewport and find queries O(log n) rather than a
walk. `applyFilter` stays a pure function that never mutates, reorders, evicts, or
renumbers `BlockId`s.

### 6.3 Visible absence

`truncatedLines` / `truncatedBytes` render as a visible marker in the block body, never
silently swallowed. A `gap.json` epoch break shows as a discontinuity in the timeline.
This is parent spec §13.1's visible-absence rule.

### 6.4 The completions popup, and its obligation

Decision 2.6's known weakness is occlusion. These are requirements with tests, not
preferences:

- at most 4 rows;
- the in-progress block stays scrolled above the popup;
- the popup dismisses on block-list scroll;
- the popup is **inert** when ownership is not held — no popup over `vim`.

The editor cubit publishes a **buffer replica** (value + cursor offset) and the
completions engine subscribes to *that*, debounced. It never touches the
`TextEditingController`. This is Warp's `InputBufferModel`
(`app/src/terminal/input/buffer_model.rs:7`) — "a 'replica' of the input buffer's
contents that may be subscribed to without a strict dependency on the Input view
itself" — and it is the right shape precisely because a popup re-queries on every
keystroke.

### 6.5 Completions engine

A Dart port of our own `parse` → `match` → `rank` → providers pipeline
(`packages/terminal/ts/completions/src/`), keeping ranking identical across clients.

From Warp's completer we take the **token model only**: lex → lite parse → type-driven
parse, with `Span { start, end }` on every token
(`crates/warp_completer/src/parsers/README.md`). We do **not** take
`command-signatures-v2` or any other asset file — parent spec §17.1 forbids
transplanting assets, and the checkout carries no LICENSE. Our completion specs stay
ours: `cd`, `docker`, `git`, extended as we choose.

Nothing in completions executes anything in the user's shell (parent spec §3.6), and
history never reads the user's shell history file (§10.4). Dedup, ordering and
per-directory ranking come from `app/src/terminal/history.rs` as mechanism.

---

## 7. Error handling

**Client memory bound.** The engine caps retained blocks and evicts oldest-first.
**Eviction never renumbers `BlockId`s** — identity must be stable or find and bookmarks
break. Evicted blocks remain fetchable from REST. The daemon's own bounds (100 blocks
per terminal, 5,000 output lines per block, an 8 MiB raw cap with recorded omission
counts) are the ceiling this sits under.

**Transport.** Two behaviours in CLAUDE.md are load-bearing and must not be
"optimized":

- the 12-second `connectTimeout`/`receiveTimeout`
  (`packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart:44`) — over
  Tailscale a sleeping host otherwise hangs for the OS TCP timeout of 75–120s;
- **the block-history fetch must not join a `Future.wait` fan-out.** The daemon locks a
  device out for a minute after 5 failed auths; a stale password under a fan-out burns
  extra failures per tick and arms the lockout before the user can re-pair. Sequential
  auth probing exists for this reason and a test pins the call order.

The error envelope is `{error, code, message, requestId}`; `code` drives UI branching
and `requestId` is preserved — dropping it is a regression, not a simplification.

**Degradation ladder**, each step visible to the user:

| Failure | Result |
| --- | --- |
| Marks stop arriving | Blocks stop forming; the raw grid still renders |
| Ownership never asserted | Passthrough terminal; no editor, no completions |
| Blocks REST unreachable | Live-only timeline with an explicit "history unavailable" state |
| Socket down | Existing `MuxStatus` reconnect with backoff |

---

## 8. Stages

Each stage is independently shippable and has mechanically checkable criteria. **A plan
covers one stage** (§0.4). `flutter analyze` reporting "No issues found!" and
`flutter test` passing are criteria of *every* stage and are not repeated below.

### 8.0 — Baseline and skeleton

**Deliver:** the `operator_terminal` package as a workspace member; the `TerminalHost`
interface; the bench harness; **the recorded xterm baseline**.

**Accept when:** `flutter pub get` resolves the workspace; the bench harness runs under
`flutter test` and writes numbers for `large-output` (16 MiB) throughput, parse cost per
MiB, and frame build time under sustained output, measured against the **current**
`TerminalView`.

**Owned-input latency has no xterm baseline and must not be given a relative one.**
Once the editor owns the line there is no echo and no PTY round trip, so the current
surface has nothing comparable to measure — the same reason desktop gave
`input-latency-owned` an absolute ceiling rather than a baseline multiple (parent spec
§9.4). It is gated in 8.3 at **one frame, 16.7 ms p95**, not here.

**This stage must land before anything is replaced.** A baseline cannot be recovered
after the thing being measured is deleted (decision 2.8).

### 8.1 — Marks

**Deliver:** the Dart mark decoder.

**Accept when:** all 20 `packages/terminal/protocol/vectors/*.json` pass, read from
disk at test time; a Tier-1-only byte stream produces correct blocks with no Tier-2
mark present.

### 8.2 — Blockgrid and the block renderer

**Deliver:** blockgrid over the xterm buffer; `BlockListView` with §6.1's anchoring;
block header, body, status; the three-input timeline and §5.3 reconciliation; the two
`core/mux` fixes and the new endpoint.

**Accept when:** a live-then-committed `sourceId` yields **one** block retaining its
original `BlockId`; blocks survive a reconnect and an app restart; scrollback pages
backward from REST; the bench gate holds against 8.0's baseline.

### 8.3 — The line editor

**Deliver:** line editor, buffer replica, ownership, history.

**Accept when:** ownership flips only on `input-ready`/`input-released`; unknown state
is passthrough and no keystroke is lost; **owned-input latency p95 ≤ 16.7 ms** (one
frame at 60fps — an absolute ceiling, see 8.0); history dedups and ranks per directory
without reading the user's shell history file.

### 8.4 — Alternate screen

**Deliver:** `AltScreenState`, `AltScreenView`, mouse and focus reporting, cursor
shapes.

**Accept when:** `vim` and `htop` render and accept input; entering and leaving restores
the block list at the bottom; blocks, editor and completions are inert while alt is
active.

### 8.5 — Completions

**Deliver:** the Dart engine and the popup surface.

**Accept when:** ported `parse`/`match`/`rank` cases rank identically to
`ts/completions`; all four §6.4 obligations hold under test.

### 8.6 — Navigation, actions, and retirement

**Deliver:** find, block navigation, filter, bookmark, block action sheet, sticky
header; deletion of `raw_terminal_pane.dart`, the fork's `terminal_view.dart` and
`lib/src/ui/`; `FORK.md` updated to record the fork's new role as an engine.

**Accept when:** no reference to `TerminalView` remains in `packages/mobile/lib`; find
is incremental and cancellable; no action can execute a command; the bench gate holds.

---

## 9. Testing

The gate stays `flutter analyze` (clean) and `flutter test`. No new CI toolchain — that
is the point of decision 2.1.

| Layer | How it is tested |
| --- | --- |
| `marks` | The 20 shared protocol vectors, read from disk |
| `vt` | Fixture byte streams → asserted cell/attribute runs; `protocol/redraw-vectors` and `alt-vectors` reused |
| `blockgrid` | Sum-tree invariants; identity stable across eviction, filter and reflow; §5.3 reconciliation |
| `editor` | Ownership transitions from mark sequences only; passthrough never swallows a keystroke |
| `completions` | Ported ranking cases from `ts/completions`; the four §6.4 obligations |
| `render` | Widget tests on the cell/run model and viewport arithmetic |
| `host` | Fakes; `feature/terminal`'s adapter against real mux and REST shapes |

**No golden tests.** `packages/mobile` has 155 test files and uses `matchesGoldenFile`
in none of them. Goldens on a font-dependent terminal grid would be the flakiest tests
in the repo. Assert on the cell/run model, not on pixels.

**Bench thresholds are recorded from 8.0's measured baseline, not guessed now.**
Desktop's `input-latency` ceiling had to be amended once already (parent spec §9.5);
inventing a number here would repeat that mistake.

---

## 10. Named risks

1. **Reconciliation.** §5.3 is where subtle duplicate and ordering bugs will live. It
   is the one piece with no desktop counterpart to copy — desktop renders live blocks
   and never merges a committed stream into them.
2. **Reflow.** A phone rotates; a desktop rarely resizes. Because a block is a row-range
   into the buffer (§3.1), reflow stresses block identity harder here than desktop has
   ever stressed it.
3. **No fallback.** Decision 2.4 removes the escape hatch, which is why 8.0 lands the
   bench baseline first and why 8.6 is the only stage that deletes anything.

---

## 11. Wrong turns

Specific ways this design gets quietly broken.

1. **Copying text into a block.** Blocks are row-ranges (§3.1). A block that owns a
   string copy doubles memory and desynchronizes on reflow.
2. **Parsing committed blocks with the live engine.** §5.4. It corrupts the live grid
   and cursor.
3. **Appending a committed block that was already rendered live.** §5.3. Every command
   appears twice.
4. **Reaching for a timer to decide when input is safe to take.** §5.5. Warp does this
   and we read the file specifically to confirm we should not.
5. **Letting completions read the `TextEditingController`.** §6.4. Use the buffer
   replica.
6. **Renumbering `BlockId`s on eviction or filter.** §6.2, §7. Find and bookmarks break.
7. **Joining the block-history fetch into a `Future.wait`.** §7. It arms the auth
   lockout.
8. **Copying Warp's `command-signatures-v2` or any other asset file.** §6.5, parent
   §17.1. Read the mechanism, write our own specs.
9. **Adding a second mark encoding for mobile.** Parent §7.3. Unknown keys are the
   versioning story.
10. **Deleting `TerminalView` before 8.6.** It is the only working surface until the
    Dart one is complete, and 2.4 already removed the fallback.
11. **Introducing golden tests.** §9.
12. **Putting the engine in `lib/feature/terminal`.** §3, decision 2.7. The engine and
    the product entangle immediately.
13. **Using `flutter_screenutil` in the package.** CLAUDE.md: feature code takes raw
    ints; type goes through `AppTextStyle`.

---

## 12. Glossary

Terms not already in the parent spec's §16.

- **Committed block** — a block persisted by the daemon and delivered over
  `ch:blocks` / REST. Authoritative for exit code and truncation.
- **Provisional block** — a block formed client-side from live marks, before its
  committed record arrives.
- **Reconciliation** — merging the two by `sourceId` so one command is one block (§5.3).
- **Buffer replica** — a subscribable copy of the editor's value and cursor, decoupled
  from the text field (§6.4).
- **The seam** — `TerminalHost`; the boundary no Operator type crosses (§3).
