# Agent-TUI Plan F — Remote Typing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**The measurement came first, and it changed this plan's shape.** The wait the
user actually feels — typing in the mobile composer, pressing send, waiting for
Claude Code to answer — is dominated by Claude's own turn. Over the daemon's
public tunnel a keystroke round trip is 107 ms at the median (114.9 ms until
the character is on screen, p95 253.3 ms); on loopback the whole local pipeline
is 7.3 ms. Claude's turn for the cheapest prompt that can be written is
1.07–1.57 s (median 1.24 s), and a real prompt is tens of seconds. Network is
**~8 % of the floor** of a send→answer wait (~15 % at p95) and under 1 % of a
realistic one. Predictive echo
shortens none of it; and as Part 6 specifies it — a dim overlay glyph in
`packages/terminal/ts/renderer-dom` — it cannot reach the phone at all, because
the Flutter app draws with its own vendored `packages/mobile/packages/xterm`
fork and never loads that renderer. The numbers and the method are in
[`../specs/2026-09-22-remote-typing-latency-measurement.md`](../specs/2026-09-22-remote-typing-latency-measurement.md).

**Goal:** Deliver the design spec for survey §4.2 — the pty-host mirror promoted
from replay source to the model of record, with clients pulling rows by
`(stable row, generation)` — as the whole of Plan F, and record in
`TERMINAL.md` and in the agent-TUI spec that the phone has no predictive echo
and gets one only through §4.2.

**Architecture:** This plan writes documents; it changes no code. Task 1
produces `docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md`
in the shape of the agent-TUI spec (today with citations, the gap, the design,
acceptance, decisions needed, non-goals) with **no implementation tasks** — a
later plan turns it into tasks. Task 2 records the outcome in `TERMINAL.md` §5
and fills the Part 6 note in the agent-TUI spec. Predictive echo is deferred,
with the reason, in the section below — it is deliberately **not** tasks.

**Tech Stack:** Markdown only. The facts the spec argues from live in Rust
(`packages/terminal/crates/vt-core`, `vt-wasm`, `vt-host`), Go
(`backend/internal/adapters/runtime/ptyhost`, `backend/internal/httpd`),
TypeScript (`packages/terminal/ts/core`, `ts/renderer-dom`, `frontend/src/renderer`)
and Dart (`packages/mobile`); the executor reads them, and writes none of them.

**Spec:** `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`,
Part 6 ("Remote typing"), whose two bullets are predictive echo (deferred here)
and the server-owned model (Task 1). Its survey input is
`docs/superpowers/specs/2026-09-19-terminal-reference-survey.md` §4.2 in full,
plus §4.3 and §6.5 for the deferred echo. Gated on Plan C, which has landed
(`7412050f4`), as have B (`ba6dd6d35`), D (`b4c3067b2`) and E (`7336d8150`) —
confirm with `git log --oneline | grep -i "merge: Plan"`. Read `TERMINAL.md`
end to end before starting: §1 (the input and output paths), §2 (the model,
the snapshot, stable rows, prepended history, delta export), §3 (product
independence), §4.13 and the alt-screen entries, §4.16, §4.19–§4.22, §5 (known
gaps, including the ack-accounting one this spec must address), §6 (the
verify-and-ship recipe).

## Global Constraints

Every task inherits these; they are the agent-TUI spec's "Global constraints"
plus `TERMINAL.md` §3.

- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no
  Operator import, path, default or concept inside it. In this plan that is a
  constraint on what the *design* may propose, not on files touched: the
  protocol, the daemon and the mobile client are Operator's
  (`backend/`, `frontend/`, `packages/mobile`), while `TerminalCore`'s row-cache
  API is the package's and must be describable to a second, non-Operator host.
- No comments in new code (user's global instruction). Existing comments may be
  corrected when they become false. A comment that cites a reference names the
  repository and path. **No task in this plan writes code**, so this constrains
  only the code snippets the design spec may contain (illustrative signatures,
  uncommented).
- Changelog: `packages/terminal/CHANGELOG.md`, "Unreleased", one entry per
  behaviour change. **No task in this plan changes behaviour**, so no task adds
  a CHANGELOG entry; adding one would be wrong.
- The feel and selection gates (`npm run bench:feel` → `PASS feel gate: zero
  pixel diff`, `npm run bench:selection`) attach to code tasks. **This plan has
  no code tasks**, and its verification is the documentation checks written
  into each task instead. A later plan that implements §4.2 inherits both gates
  in full.
- Use absolute paths in every shell command (`TERMINAL.md` §6: parallel Bash
  calls share and change the working directory, and `cd` into a directory you
  are already in fails silently).
- Cite `file:line` for every claim about current behaviour, or write "not
  known". Never count lines from a piped listing; open the file. This is the
  repo's standing rule and the spec produced here is judged by it.
- Commits go to `development` with the `Co-Authored-By` trailer the harness
  gives you. Never commit to `master`.

## Deferred: predictive echo (not tasks — do not implement)

Part 6's first bullet is deferred, and this is the reason, recorded so it is
not re-litigated from the spec alone:

- **It does not shorten the wait the user described.** The mobile composer is
  already local echo: text sits in a Flutter field and goes as one payload on
  send (`terminalPayload`, `packages/mobile/lib/feature/terminal/logic/send_route.dart:20-21`,
  pushed by `_writeToPty` → `MuxClient.sendInput`,
  `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:354-356`).
  Nothing is echoed per keystroke there, so nothing can be predicted. What is
  waited on after send is Claude's turn: 1.07–1.57 s (median 1.24 s) at the floor against ~107 ms
  of network.
- **Where per-keystroke lag on mobile is real, the overlay cannot reach.** The
  raw terminal pane and the key row forward every keypress individually
  (`terminal.onOutput = (data) => _mux.sendInput(...)`,
  `terminal_cubit.dart:99`; `sendKey`, `:281-283`) and a remote user pays the
  full ~107 ms per character. But Part 6's echo is a renderer-only overlay in
  `packages/terminal/ts/renderer-dom`, and the phone draws with
  `packages/mobile/packages/xterm`. Building it in the Dart fork instead would
  add a second, divergent implementation to the very fork §4.2 exists to
  delete.
- **The one configuration it would help is the desktop app against a remote
  daemon**, which pays ~107 ms per keystroke in the alt-screen path. Whether
  the user works that way is **not known**; it is not observable from this
  machine's configuration and must not be assumed. If the user confirms they
  do, predictive echo becomes its own plan.
- **When it is built, it belongs in the shared renderer §4.2 delivers**, not in
  the Dart fork — that is the only route by which the phone ever gets it.
- **The survey's own objection does not apply and must not be used to kill it
  later.** Survey §4.3 concludes predictive echo is impossible without §4.2
  because WezTerm predicts by writing into its cached row
  (`/Users/omaraly/development/AI/wezterm/wezterm-client/src/pane/renderable.rs`,
  `apply_prediction` `:145-206`). The agent-TUI spec's version is an overlay
  that touches no row, so it does not need §4.2 — **the spec wins over the
  survey on this point**. VS Code's type-ahead is the reference for the
  client-only form
  (`/Users/omaraly/development/AI/vscode/src/vs/workbench/contrib/terminalContrib/typeAhead/browser/terminalTypeAheadAddon.ts`),
  and `should_predict` (`renderable.rs:136-142`) and `predict_from_key_event`
  (`:212-246`) are the reference for the threshold and the key filter.
- **If it is ever built, it is an overlay in the existing decoration layer**:
  `DomBlockRenderer`'s `.terminal-decorations` container
  (`packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:156-160`) and
  its `layer(name)` helper (`:547-557`), painted through `rangeBoxes` /
  `paintBoxes` (`decorations.ts:6`, `:24`) — never by writing into `vt-core`,
  the snapshot, `textRows()` (Plan E made it the single place text is read:
  copy, word selection, linkifier, hints, block text) or a pooled row element,
  for the same reason the selection is not one (`TERMINAL.md` §4.13). It must
  paint in **both** surfaces, because Claude Code's prompt is the alternate
  screen: the alt cursor is `[data-terminal-cursor]`
  (`alt-surface.ts:7`, used at `:83`, `:133`), the block cursor is
  `[data-terminal-cursor-cell]` (`cursor.ts:8`, set at `:101`). Default off,
  with the threshold and the switch host-side rather than a `RendererFeatures`
  flag (`features.ts`); RTT renderer-local and measured with
  `performance.now()` — never mixed with the feed clock, which Plan E moved to
  `Date.now()` (`TERMINAL.md` §2, "BlockGrid clock"). The exclusions are the
  risky part and each needs its own test: no-echo/password, cursor moved but
  text did not, alt-screen full redraw, paste, control or non-printable key,
  wide/CJK cluster, a keystroke while a DEC 2026 block is open
  (`TERMINAL.md` §4.16), and a prediction never confirmed that must expire.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md` | **Create.** The §4.2 design spec: today with citations, the gap, the design, acceptance, decisions needed, non-goals. No implementation tasks. | 1 |
| `docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md` | **Exists** (committed with this plan). The motivation section of the spec above cites it; Task 1 does not rewrite it. | — |
| `scripts/measure-remote-typing-latency.mjs` | **Exists** (committed with this plan). The reproduction path for the numbers. | — |
| `TERMINAL.md` | **Modify**, §5 "Known gaps": one entry recording that the phone has no predictive echo and gets one only through §4.2. | 2 |
| `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` | **Modify**, Part 6: a note saying what Plan F actually delivered. | 2 |

Two tasks, because a reviewer could accept the design spec and reject the
wording of the `TERMINAL.md` entry, or the reverse. Nothing else splits: the
measurement and the script are already on disk in the same commit as this plan,
and the deferral above is a section of this plan, not a deliverable.

---

### Task 1: The §4.2 server-owned model design spec

**Files:**
- Create: `/Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md`
- Read (do not modify): `/Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-19-terminal-reference-survey.md` §4.2 (lines 2559-2658), §4.3 (2660-2703), §6.5 (3550-3585); `/Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`; `/Users/omaraly/development/AI/Operator/TERMINAL.md`; `/Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md`
- Test: `/Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md` is checked by the greps in Steps 2 and 8 (there is no code to unit-test; the gate is that every required section exists, every `file:line` citation resolves, and no placeholder survives)

**Interfaces:**
- Consumes: nothing from an earlier task. The measurement document and the
  script already exist on disk.
- Produces: the file path above, which Task 2 cites by name in both
  `TERMINAL.md` §5 and the agent-TUI spec's Part 6 note. Task 2 must spell the
  filename exactly as created here.

- [ ] **Step 1: Write the citation-check script that the spec must pass**

This is the failing test. It extracts every `path:line` and `path:line-line`
citation from the spec and asserts the path exists and the file has at least
that many lines, and it asserts each required section heading is present.

Create `/Users/omaraly/development/AI/Operator/scripts/check-spec-citations.mjs`:

```js
#!/usr/bin/env node
import { readFile, stat } from "node:fs/promises";
import { createReadStream } from "node:fs";
import { createInterface } from "node:readline";

const [, , specPath, ...required] = process.argv;
if (!specPath) {
	console.error("usage: check-spec-citations.mjs <spec.md> [requiredHeading ...]");
	process.exit(2);
}

const root = new URL("../", import.meta.url).pathname;
const text = await readFile(specPath, "utf8");
const failures = [];

for (const heading of required) {
	if (!text.includes(heading)) failures.push(`missing required section: ${heading}`);
}

for (const bad of ["TBD", "TODO", "fill in", "implement later"]) {
	if (text.includes(bad)) failures.push(`placeholder present: ${bad}`);
}

const citation = /`([A-Za-z0-9_./-]+\.(?:rs|go|ts|tsx|dart|mjs|css|md|yaml))(?::(\d+)(?:-(\d+))?)?`/g;
const seen = new Set();
for (const match of text.matchAll(citation)) {
	const [, rel, from, to] = match;
	const key = `${rel}:${from ?? ""}:${to ?? ""}`;
	if (seen.has(key)) continue;
	seen.add(key);
	const abs = rel.startsWith("/") ? rel : `${root}${rel}`;
	let info;
	try {
		info = await stat(abs);
	} catch {
		continue;
	}
	if (!info.isFile()) continue;
	const want = Number(to ?? from ?? 0);
	if (!want) continue;
	let lines = 0;
	const reader = createInterface({ input: createReadStream(abs), crlfDelay: Infinity });
	for await (const _ of reader) lines += 1;
	if (lines < want) failures.push(`${rel}:${want} past end of file (${lines} lines)`);
}

if (failures.length > 0) {
	for (const failure of failures) console.error(`FAIL ${failure}`);
	process.exit(1);
}
console.log(`PASS spec citations: ${seen.size} checked, ${required.length} sections present`);
```

- [ ] **Step 2: Run it against the not-yet-written spec to verify it fails**

```bash
cd /Users/omaraly/development/AI/Operator && node /Users/omaraly/development/AI/Operator/scripts/check-spec-citations.mjs /Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md "## Today" "## The gap" "## The design" "## Acceptance" "## Decisions needed" "## Non-goals"
```

Expected: a non-zero exit with `ENOENT` on the spec path (the file does not
exist yet). Confirm the script itself runs by pointing it at a spec that does
exist:

```bash
cd /Users/omaraly/development/AI/Operator && node /Users/omaraly/development/AI/Operator/scripts/check-spec-citations.mjs /Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md
```

Expected: `PASS spec citations: <n> checked, 0 sections present`.

- [ ] **Step 3: Write the spec's frame — header, motivation, today**

Create the spec with this header (fill the date and the confirmed hashes):

```markdown
# Server-owned terminal model: the mirror as the model of record

**Date:** 2026-09-22
**Decision owner:** Omar Aly
**Status:** design only — no implementation tasks in this document
**Derived from:** `docs/superpowers/specs/2026-09-19-terminal-reference-survey.md` §4.2
(with §4.5 for width, §1.9 and §3.1 for what it subsumes), and
`docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` Part 6.
**Motivated by:** `docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md`.
**Prerequisites, all landed:** Plan B `ba6dd6d35` (stable rows, incremental
export), Plan C `7412050f4` (attach/replay with history, flow control), Plan D
`b4c3067b2` (text and glyphs), Plan E `7336d8150` (wrapped and link exports).
Confirm with `git log --oneline | grep -i "merge: Plan"`.
```

Then a **Why** section stating the motivation in the measurement's terms: the
phone's felt wait is Claude's turn, so this is not a latency project — it is
about the phone being a second, weaker terminal. Quote the numbers: 107 ms
median keystroke echo over the tunnel against 1.07–1.57 s (median 1.24 s) for Claude's cheapest
turn; the phone runs a second VT engine that cannot know about blocks.

Then `## Today`, with citations, covering:
- The byte channel: the daemon forwards the pty-host's raw bytes as
  `{ch:'terminal', type:'data', data:base64}`
  (`backend/internal/terminal/protocol.go:20-26`, `:91-103`;
  `backend/internal/httpd/terminal_mux.go`). Every client parses every byte.
- The desktop feeds them to its own `vt-core`
  (`frontend/src/renderer/components/BlockTerminal.tsx`,
  `packages/terminal/ts/core/src/terminal-core.ts:114-118` `feed`).
- The phone feeds them to the vendored Dart `xterm`
  (`packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:99`,
  `packages/mobile/packages/xterm`).
- The mirror already runs `vt-core` server-side but only to produce the attach
  replay (`backend/internal/adapters/runtime/ptyhost/vtwasm`, `attach.go`;
  `TERMINAL.md` §1).
- What the model already has that §4.2 needs: stable rows
  (`packages/terminal/crates/vt-core/src/lib.rs:340`, `:344`;
  `parser.rs:34`, `:95`), a generation counter and a dirty-row delta
  (`lib.rs:291`, `:295`; `crates/vt-wasm/src/export.rs:141`), and the block
  origin (`crates/vt-core/src/block_grid.rs:27`, `:45`).

- [ ] **Step 4: Write `## The gap` and `## The design`**

`## The gap`: the mirror is the only party that sees every byte from the
child's first (it already answers XTVERSION/DA1/DECRQM for exactly that
reason — `TERMINAL.md` §4.16), yet it is treated as a replay source. Each
client re-derives the same model from bytes, so the phone needs a VT engine to
show a terminal at all, and every affordance Plans D and E built lives only in
the renderer the phone does not run.

`## The design`, covering every item the plan's brief lists:

1. **Rows addressed by `(stable row, generation)`.** A per-row generation
   stamped on every mutation, `changed_since(generation) -> ranges`, and
   `rows(stable range)`. Cite WezTerm's equivalents: `last_change_seqno` and
   `changed_since` (`/Users/omaraly/development/AI/wezterm/wezterm-surface/src/line/line.rs:283-300`),
   `dirty_line` (`/Users/omaraly/development/AI/wezterm/term/src/screen.rs:342-345`),
   `get_changed_since` (`/Users/omaraly/development/AI/wezterm/mux/src/pane.rs:179-192`),
   `compute_changes` (`/Users/omaraly/development/AI/wezterm/wezterm-mux-server-impl/src/sessionhandler.rs:39-145`),
   and the client's `LineEntry` cache
   (`/Users/omaraly/development/AI/wezterm/wezterm-client/src/pane/renderable.rs:31-43`, `:305-370`, `:495`).
   State plainly what our `generation()` (`lib.rs:291`) is and is not: it is
   per-core, not per-row, so a per-row stamp is new work.
2. **What replaces the byte channel and what stays.** A `render_changes` push
   and a `get_rows` request replacing `type: 'data'` for the normal screen;
   what happens to the alt screen; what stays byte-shaped (input, which is
   still keystrokes to a pty), and what the daemon's fan-out
   (`connState.handleTerminal`) becomes.
3. **How Plan C's attach/replay/history map onto it.** The READY-first frame,
   the 512-row chunks and the origin mark (`TERMINAL.md` §4.19, §4.20, §4.21;
   `backend/internal/adapters/runtime/ptyhost/attach.go`;
   `crates/vt-core/src/parser.rs:529` `adopt_origin`, `:542`
   `apply_history_chunk`) become "the viewport now, the rest on scroll", which
   is `get_rows` — say explicitly which of the four traps §4.19–§4.22 record
   disappear and which survive in a new form.
4. **What happens to the renderer's own `vt-core` copy.** The `TerminalCore`
   API stays; `feed` is replaced by `applyDelta` for daemon sessions, and the
   DOM renderer above `snapshot()` is untouched. Say whether the local editor
   path and any non-daemon host keep `feed` (they must — `packages/terminal`
   is product-independent).
5. **What it buys.** One model for desktop and phone; `packages/mobile/packages/xterm`
   deleted; the phone gets Plans D and E's affordances (blocks, styles,
   grapheme clusters, logical-line copy, links, hints, redaction, block
   timestamps) with no second implementation; and predictive echo becomes
   reachable for the phone at all.
6. **What it costs and breaks.** The mux protocol and both mux clients
   (`backend/internal/httpd/terminal_mux.go`,
   `frontend/src/renderer/hooks/useTerminalSession.ts`,
   `packages/mobile/lib/core/mux/mux_client.dart`); the editor's local-echo
   path (`packages/terminal/ts/editor`); offline behaviour on the phone; and
   the flow-control acks Plan C added — including the two ways ack accounting
   already fails open (`TERMINAL.md` §5, "Ack accounting is per pty-host
   CONNECTION, not per mux client"), which a row-delta protocol either fixes
   by construction or must state it does not.
7. **Width.** One mirror at the largest attached grid with clients rewrapping
   logical lines locally, versus one mirror per grid (survey §4.5). Do not
   decide it here; put it in `## Decisions needed` with the measurement it
   would take.

- [ ] **Step 5: Write `## Acceptance`, `## Decisions needed`, `## Non-goals`**

`## Acceptance` — observable statements a later plan's tests can be written
against, not tasks. At minimum: two clients at different generations receive
disjoint deltas; a reattaching client with a stale generation receives the
viewport as bonus rows; a chunked history fetch reconstructs the same rows the
byte replay produces today; the phone renders a delta with blocks; and the
desktop's pixel output is unchanged (`npm run bench:feel` → zero pixel diff),
which is the constraint the whole agent-TUI spec ships under.

`## Decisions needed` — numbered, each with what it turns on: the width
strategy (item 7 above); whether the alt screen is served as rows or stays
bytes; whether `generation` is per row or per range; whether the mirror
persists across app restarts (the agent-TUI spec's open Decision 2); and
whether the mobile `xterm` fork is deleted in the same release or after a
soak.

`## Non-goals` — predictive echo (deferred, with a pointer to this plan's
deferral section and the measurement); shell-mode behaviour; anything in the
agent-TUI spec's own non-goals; and **implementation tasks**, which belong to a
later plan.

- [ ] **Step 6: Add the motivation section's numbers and cross-links**

Link `docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md`
from the Why section and quote its headline table row (tunnel visible median
114.9 ms, p95 253.3 ms; loopback visible median 7.7 ms; Claude's trivial turn
1.07–1.57 s (median 1.24 s)). State that §4.2 does **not** improve either number — it changes
what the phone is, not how fast it is — so nobody later reads this spec as a
latency fix.

- [ ] **Step 7: Verify every claim about current behaviour resolves**

For each `file:line` in the spec, open the file at that line and confirm it says
what the spec claims. Spot-check with:

```bash
cd /Users/omaraly/development/AI/Operator && sed -n '340p;344p;291p;295p' /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/src/lib.rs && sed -n '99p' /Users/omaraly/development/AI/Operator/packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart
```

Expected: `stable_row` / `flat_row`, `generation` / `take_delta`, and the
`terminal.onOutput` forwarding line. Any citation that does not resolve is
replaced with the real line or with "not known".

- [ ] **Step 8: Run the citation check and confirm it passes**

```bash
cd /Users/omaraly/development/AI/Operator && node /Users/omaraly/development/AI/Operator/scripts/check-spec-citations.mjs /Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md "## Today" "## The gap" "## The design" "## Acceptance" "## Decisions needed" "## Non-goals"
```

Expected: `PASS spec citations: <n> checked, 6 sections present`, exit 0.

- [ ] **Step 9: Confirm the spec proposes no implementation and no code change**

```bash
cd /Users/omaraly/development/AI/Operator && git status --porcelain && grep -c "^- \[ \]" /Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md
```

Expected: `git status` lists only the two new files under `docs/` and
`scripts/` — no file under `packages/`, `backend/`, `frontend/` — and the grep
prints `0` (exit 1 from `grep -c` on zero matches is the pass here; a non-zero
count means task checkboxes leaked into a design spec).

- [ ] **Step 10: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md scripts/check-spec-citations.mjs && git commit -m "docs: server-owned terminal model design spec (survey 4.2)

The pty-host mirror becomes the model of record and clients pull rows by
(stable row, generation). Design only, no implementation tasks. Motivated by
the remote-typing latency measurement: the phone's wait is Claude's turn, not
the terminal, so this is about the phone being a second VT engine rather than
about latency.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Record the outcome in `TERMINAL.md` §5 and the spec's Part 6 note

**Files:**
- Modify: `/Users/omaraly/development/AI/Operator/TERMINAL.md` (§5 "Known gaps (not bugs, decisions pending)")
- Modify: `/Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` (Part 6, at the heading `## Part 6 — Remote typing (after Part 1.G/H)`)
- Test: the greps in Steps 2 and 6

**Interfaces:**
- Consumes: from Task 1, the exact filename
  `docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md`,
  which both edits cite.
- Produces: nothing a later task consumes.

- [ ] **Step 1: Write the failing check**

Create `/Users/omaraly/development/AI/Operator/scripts/check-plan-f-notes.sh`:

```sh
#!/bin/sh
set -e
root=/Users/omaraly/development/AI/Operator
fail=0
grep -q "predictive echo" "$root/TERMINAL.md" || { echo "FAIL TERMINAL.md has no predictive-echo gap entry"; fail=1; }
grep -q "2026-09-22-server-owned-terminal-model-design.md" "$root/TERMINAL.md" || { echo "FAIL TERMINAL.md does not point at the 4.2 spec"; fail=1; }
grep -q "2026-09-22-remote-typing-latency-measurement.md" "$root/docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md" || { echo "FAIL Part 6 note does not cite the measurement"; fail=1; }
grep -q "2026-09-22-server-owned-terminal-model-design.md" "$root/docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md" || { echo "FAIL Part 6 note does not cite the 4.2 spec"; fail=1; }
[ "$fail" -eq 0 ] || exit 1
echo "PASS Plan F notes recorded"
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/omaraly/development/AI/Operator && sh /Users/omaraly/development/AI/Operator/scripts/check-plan-f-notes.sh
```

Expected: four `FAIL` lines and exit 1.

- [ ] **Step 3: Add the `TERMINAL.md` §5 entry**

Append to the bullet list in §5 "Known gaps (not bugs, decisions pending)",
after the last existing bullet:

```markdown
- **The phone has no predictive local echo, and gets one only through survey
  §4.2.** Part 6's predictive echo is a renderer-only dim overlay in
  `ts/renderer-dom`; the Flutter client draws with its own vendored fork
  (`packages/mobile/packages/xterm`) and never loads that renderer. It also
  would not help the case it was proposed for: the mobile composer is already
  local echo (text sits in a Flutter field and goes as one payload on send,
  `packages/mobile/lib/feature/terminal/logic/send_route.dart:20-21`), and the
  wait after send is Claude's turn — measured 2026-09-22 at 1.07–1.57 s (median 1.24 s) for the
  cheapest possible prompt against a 107 ms median keystroke round trip over
  the daemon's public tunnel and 7.3 ms on loopback
  (`docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md`,
  reproduce with `scripts/measure-remote-typing-latency.mjs`). Per-keystroke
  lag on mobile is real only in the raw terminal pane and the key row
  (`terminal_cubit.dart:99`, `:281-283`). The route to an echo on the phone is
  the shared renderer that
  `docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md`
  designs; do not build a second prediction implementation in the Dart fork.
```

- [ ] **Step 4: Fill the spec's Part 6 note**

In `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`, under
`## Part 6 — Remote typing (after Part 1.G/H)`, leave the two existing bullets
in place and append:

```markdown
**What Plan F delivered (2026-09-22).** The measurement first
(`2026-09-22-remote-typing-latency-measurement.md`): over the daemon's public
tunnel a keystroke round trip is 107 ms median / 234 ms p95, and the character
is on screen at 114.9 ms median / 253.3 ms p95; on loopback the whole local
pipeline is 7.3 ms. Claude's own turn for the cheapest prompt writable is
1.07–1.57 s (median 1.24 s), so network is ~8 % of the floor of a send→answer wait and under
1 % of a realistic one. **Predictive echo is deferred**: it cannot reach the
phone (renderer-only overlay; the Flutter app draws with its own `xterm` fork)
and it does not shorten the wait the user described (the mobile composer is
already local echo). It is worth building only for the desktop app against a
remote daemon, which the user has not confirmed they use. Plan F therefore
delivered the §4.2 design spec as its whole scope:
`2026-09-22-server-owned-terminal-model-design.md`.
```

- [ ] **Step 5: Confirm no other part of the spec changed**

```bash
cd /Users/omaraly/development/AI/Operator && git diff --stat && git diff /Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md | grep -c "^-[^-]"
```

Expected: the stat lists exactly `TERMINAL.md` and the agent-TUI spec, and the
grep prints `0` — the Part 6 edit is purely additive, and no Part 4 or Part 5
flag default, and no other Part, is touched.

- [ ] **Step 6: Run the check and confirm it passes**

```bash
cd /Users/omaraly/development/AI/Operator && sh /Users/omaraly/development/AI/Operator/scripts/check-plan-f-notes.sh
```

Expected: `PASS Plan F notes recorded`, exit 0.

- [ ] **Step 7: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add TERMINAL.md docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md scripts/check-plan-f-notes.sh && git commit -m "docs: Plan F landed — measurement, deferred predictive echo, 4.2 spec as the deliverable

TERMINAL.md 5 records that the phone has no predictive echo and gets one only
through the server-owned model; the agent-TUI spec's Part 6 records the
numbers and what Plan F delivered.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

No CHANGELOG entry: `packages/terminal/CHANGELOG.md` records behaviour changes,
and this plan changes no behaviour. No daemon or wasm rebuild, and no restart
instruction, for the same reason.

---

## Self-review record (written with the plan)

- **Does the plan's shape follow the numbers?** Yes, and that was the test it
  had to pass. The measurement put Claude's turn at 1.07–1.57 s (median 1.24 s) for the cheapest
  possible prompt against 107 ms of network over the tunnel and 7.3 ms locally,
  so the brief's first branch applies: the plan says so in its first paragraph,
  its entire deliverable is the §4.2 design spec plus the measurement already
  taken, and predictive echo is a deferral section with its reason rather than
  tasks. The third branch — implementing the echo — was not taken, because
  whether the user runs the desktop app against a remote daemon is not known,
  and the brief says to treat it as unknown unless the measurement or the user
  says otherwise. The measurement cannot say it: it is a property of how the
  user works, not of this machine.
- **Spec coverage, Part 6 bullet by bullet.** *Predictive echo* — deferred, in
  the "Deferred" section, with the reason, the configuration in which it would
  be worth building, the layer it would have to live in, both cursor selectors,
  the clock rule, the full exclusion list, and the resolution of the
  survey-versus-spec contradiction (the spec wins: an overlay touches no row).
  *Server-owned model* — Task 1, whose Steps 3–5 enumerate every element the
  brief requires: `(stable row, generation)` with the mirror as the model of
  record; what replaces the byte channel and what stays; Plan C's
  attach/replay/history mapped on; the renderer's own `vt-core` copy; what it
  buys; what it costs and breaks including the mux protocol, both mux clients,
  the editor's local-echo path, offline behaviour and Plan C's flow-control
  acks; the landed prerequisites with hashes; the decisions it needs; and the
  measurement as its motivation section. Task 2 covers the two recording
  obligations.
- **Placeholder scan.** No "TBD", "TODO", "implement later", "add appropriate
  handling" or "similar to Task N" appears. The angle-bracket fields are
  `<n>` in expected command output (a count the executor reads, not writes) —
  and Task 1 Step 1 ships the checker that fails the build on the placeholder
  words, so the prohibition is enforced by a command rather than by good
  intentions. Both tasks' verification steps are runnable commands with stated
  expected output, as required even though no task writes code.
- **Type consistency.** The filename
  `docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md` is
  spelled identically in Task 1's Files block, Task 1 Steps 2, 8, 9 and 10,
  Task 2's Interfaces, Steps 1, 3 and 4, and this plan's File Structure table.
  `docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md` is
  spelled identically in the opening paragraph, the File Structure table, Task
  1 Steps 2, 3 and 6, and Task 2 Steps 1, 3 and 4.
  `scripts/measure-remote-typing-latency.mjs` matches the file on disk.
  `scripts/check-spec-citations.mjs` is created in Task 1 Step 1 and invoked
  under that exact name in Steps 2 and 8 and committed in Step 10;
  `scripts/check-plan-f-notes.sh` likewise in Task 2 Steps 1, 2, 6 and 7. The
  six required headings passed to the checker in Step 2 are the same six
  strings written in Steps 3–5 and re-passed in Step 8. The four merge hashes
  (`ba6dd6d35`, `7412050f4`, `b4c3067b2`, `7336d8150`) match
  `git log --oneline | grep -i "merge: Plan"` and are spelled the same in the
  plan header and in Task 1 Step 3.
- **Global constraints that do not apply, stated rather than silently
  dropped.** No code task means no `npm run bench:feel`, no
  `npm run bench:selection`, no wasm rebuild, no daemon rebuild and no
  CHANGELOG entry. Each is called out in Global Constraints or in Task 2's
  closing note so a reviewer sees the omission was decided, not forgotten.
