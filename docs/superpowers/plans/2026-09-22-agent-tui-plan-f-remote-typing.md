# Agent-TUI Plan F — Remote Typing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**The measurement came first, and it decided this plan's shape twice.** The
wait the user opened with — typing in the mobile composer, pressing send,
waiting for Claude Code to answer — is dominated by Claude's own turn. Over the
daemon's public tunnel a keystroke round trip is 106.7 ms at the median
(111.7 ms until the character is on screen); on loopback the whole local
pipeline is 6.6 ms. Claude's turn for the cheapest prompt that can be written
is 1.07–1.57 s (median 1.24 s), and a real prompt is tens of seconds — so
network is **~8 % of the floor** of a send→answer wait and under 1 % of a
realistic one. **Predictive echo does nothing for that**, and as Part 6
specifies it — a dim overlay glyph in `packages/terminal/ts/renderer-dom` — it
cannot reach the phone at all, because the Flutter app draws with its own
vendored `packages/mobile/packages/xterm` fork and never loads that renderer.

**But the measurement could not answer the question predictive echo actually
turns on**, because that question is about how the user works, not about this
machine: do they run the desktop app against a *remote* daemon, where the
~107 ms is paid per keystroke in Claude Code's prompt? Put to them directly on
2026-09-22, the answer is **yes, often**. So predictive echo is built here —
for the desktop-against-remote-daemon case it demonstrably helps, and not for
the phone, which gets it only through §4.2. The numbers and the method are in
[`../specs/2026-09-22-remote-typing-latency-measurement.md`](../specs/2026-09-22-remote-typing-latency-measurement.md).

**Goal:** Two deliverables. (1) The design spec for survey §4.2 — the pty-host
mirror promoted from replay source to the model of record, with clients pulling
rows by `(stable row, generation)` — which is the only route by which the phone
ever gets a shared renderer or an echo. (2) Predictive local echo in the
desktop renderer: a dim overlay glyph at the cursor while the measured RTT
exceeds a host threshold, painted in both surfaces, default off, touching no
row and no model.

**Architecture:** Tasks 1–2 write documents. Tasks 3–7 write code, and every
line of it lives above the model: a pure prediction state machine
(`prediction.ts`) and an RTT meter (`rtt.ts`) with no DOM, then an overlay in
`DomBlockRenderer`'s existing `.terminal-decorations` layer — the same
mechanism Plan E's link underlines and redaction masks use, and for the same
reason the selection is not a DOM range (`TERMINAL.md` §4.13). Nothing is
written into `vt-core`, the snapshot, `textRows()` or a pooled row element. The
prediction is registered where the keystroke leaves
(`TerminalSurface.tsx:296`'s `onSendRaw(data)`) and retired when real output
moves the cursor past it or a deadline passes.

**Tech Stack:** TypeScript (`packages/terminal/ts/renderer-dom`, `ts/react`)
and CSS for the echo; `frontend/` for the host switch; Markdown for the specs.
Vite + Playwright for the `bench:feel` and `bench:selection` gates. **No Rust,
no Go, no wasm rebuild** — the echo never touches the engine, which is the
whole point of the overlay design.

**Spec:** `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`,
Part 6 ("Remote typing"), whose two bullets are the server-owned model
(Task 1) and predictive echo (Tasks 3–7). Its survey input is
`docs/terminal/2026-09-19-terminal-reference-survey.md` §4.2 in full,
plus §4.3 and §6.5 for the echo. Gated on Plan C, which has landed
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
  corrected when they become false. The one permitted kind of new comment is a
  reference citation naming the repository and path, the way `styles.css` cites
  Warp — here that means
  `wezterm/wezterm-client/src/pane/renderable.rs` and
  `vscode/src/vs/workbench/contrib/terminalContrib/typeAhead/browser/terminalTypeAheadAddon.ts`
  where the prediction rules are ported.
- Changelog: `packages/terminal/CHANGELOG.md`, "Unreleased", one entry per
  behaviour change. Tasks 1 and 2 change no behaviour and add none. Tasks 3–7
  add exactly one entry between them, in Task 7, because the behaviour only
  becomes reachable when the host switch is wired — five entries for one
  user-visible change would be noise.
- **Feel gate:** every code task (3–7) ends with `npm run bench:feel` from
  `/Users/omaraly/development/AI/Operator/packages/terminal` printing
  `PASS feel gate: zero pixel diff`. The echo is **default off** and paints
  nothing without a host threshold and a measured RTT above it, so there is no
  task in this plan that is allowed to change a pixel of the current pane. If
  the gate reddens, the prediction is painting when it must not — that is the
  bug, not the baseline.
- `npm run bench:selection` runs on every task that touches the renderer's
  overlay or text path (Tasks 5, 6, 7).
- Do not change any Part 4 or Part 5 flag default (`features.ts`
  `DEFAULT_FEATURES`), and do not add the echo to `RendererFeatures` — the
  threshold and the switch are host-side, for the reason given in "Design
  decisions" below.
- Do not change `packages/mobile`. The phone is out of scope for the echo by
  construction.
- Use absolute paths in every shell command (`TERMINAL.md` §6: parallel Bash
  calls share and change the working directory, and `cd` into a directory you
  are already in fails silently).
- Cite `file:line` for every claim about current behaviour, or write "not
  known". Never count lines from a piped listing; open the file. This is the
  repo's standing rule and the spec produced here is judged by it; Task 1 ships
  the script that enforces it.
- TDD: failing test first, run it, minimal implementation, run it, commit.
  Every `TERMINAL.md` §4 guard keeps passing.
- TS verification for a code task, from
  `/Users/omaraly/development/AI/Operator/packages/terminal`: `npm run build:ts`
  then `npx vitest run` in each of `ts/core`, `ts/renderer-dom`, `ts/editor`,
  `ts/react` (the react package resolves renderer-dom through its built `dist`,
  so build first). Then `npx tsc --noEmit -p .` in
  `/Users/omaraly/development/AI/Operator/frontend`. **No `cargo`, no `go`, no
  `build:wasm`, no daemon rebuild and no "restart the daemon" instruction** —
  no task here touches Rust, Go or the engine.
- Commits go to `development` with the `Co-Authored-By` trailer the harness
  gives you. Never commit to `master`.

## Design decisions (settled here, so they are not re-litigated per task)

- **The echo is built for the desktop against a remote daemon, and for nothing
  else.** That configuration pays ~107 ms per keystroke in Claude Code's
  prompt, and the user confirmed on 2026-09-22 that they work that way often.
  Every other configuration either pays ~7 ms (local desktop — below any sane
  threshold, so the echo never arms) or cannot run the renderer at all (the
  phone). This is why the threshold gate in Task 4 is not a nicety: on a local
  daemon the feature must be invisible, and the `bench:feel` gate proves it.
- **It does not shorten the wait the user opened with.** The mobile composer is
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
- **The phone gets an echo only through §4.2**, never by porting this into the
  Dart fork — that would add a second, divergent implementation to the very
  fork §4.2 exists to delete. Task 2 records this in `TERMINAL.md` §5 so a
  later session does not "finish the job" by writing one in Dart.
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
- **It is an overlay in the existing decoration layer**:
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
| `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` | **Modify**, Part 6: a note saying what Plan F delivered. | 2 |
| `packages/terminal/ts/renderer-dom/src/prediction.ts` | **Create.** The pure prediction state machine: what may be predicted, what confirms it, what expires it. No DOM, no snapshot. | 3 |
| `packages/terminal/ts/renderer-dom/src/prediction.test.ts` | **Create.** One test per exclusion rule. | 3 |
| `packages/terminal/ts/renderer-dom/src/rtt.ts` | **Create.** `RttMeter`: `performance.now()` samples, rolling median, threshold gate. | 4 |
| `packages/terminal/ts/renderer-dom/src/rtt.test.ts` | **Create.** | 4 |
| `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` | **Modify.** A `predictions` decoration layer painted from the block cursor cell, plus the public seam the host drives. | 5, 7 |
| `packages/terminal/ts/renderer-dom/src/alt-surface.ts` | **Modify.** The same overlay anchored to the alt cursor. | 6 |
| `packages/terminal/ts/renderer-dom/src/styles.css` | **Modify.** `.terminal-prediction`, dim, non-interactive. | 5 |
| `packages/terminal/ts/react/src/TerminalSurface.tsx` | **Modify.** Register a prediction where the keystroke leaves (`:296`), retire it on feed. | 7 |
| `packages/terminal/ts/core/src/types.ts` | **Modify.** `HostCapabilities.predictiveEcho?: { thresholdMs: number }` — host-side, not a `RendererFeatures` flag. `HostCapabilities` lives in **`ts/core`** (`:244`), not in `renderer-dom`, which only imports it (`block-actions.ts:4`); there is no `renderer-dom/src/types.ts`. | 7 |
| `frontend/src/renderer/components/BlockTerminal.tsx` | **Modify.** Pass Operator's threshold through; default absent (off). | 7 |
| `packages/terminal/CHANGELOG.md` | **Modify.** One "Unreleased" entry, in Task 7 only. | 7 |

Seven tasks. Tasks 1 and 2 are split because a reviewer could accept the design
spec and reject the wording of the `TERMINAL.md` entry, or the reverse. Tasks
3–7 split on the same rule: the state machine and the RTT meter are pure and
independently rejectable; each surface's painting can be judged on its own; and
the wiring that finally makes the feature reachable is the only task that
changes user-visible behaviour, which is why it alone carries the CHANGELOG
entry and the host switch. The measurement and its script are already on disk
in the same commit as this plan.

---

### Task 1: The §4.2 server-owned model design spec

**Files:**
- Create: `/Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md`
- Read (do not modify): `/Users/omaraly/development/AI/Operator/docs/terminal/2026-09-19-terminal-reference-survey.md` §4.2 (lines 2654-2755), §4.3 (2757-2801), §6.5 (3673-3709); `/Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`; `/Users/omaraly/development/AI/Operator/TERMINAL.md`; `/Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md`
- Test: `/Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md` is checked by the greps in Steps 2 and 8 (there is no code to unit-test; the gate is that every required section exists, every `file:line` citation resolves, and no placeholder survives)

**Interfaces:**
- Consumes: nothing from an earlier task. The measurement document and the
  script already exist on disk.
- Produces: the file path above, which Task 2 cites by name in both
  `TERMINAL.md` §5 and the agent-TUI spec's Part 6 note. Task 2 must spell the
  filename exactly as created here.

- [ ] **Step 1: Write the citation-check script that the spec must pass**

This is the failing test. It extracts every `` `path:line` `` and
`` `path:line-line` `` citation from the spec and asserts the path **exists**
and the file has at least that many lines, asserts each required section
heading is present, and fails on the placeholder words.

**The convention it enforces, because a §4.2 spec names files that do not exist
yet:** a path the design proposes creating is written `` `some/new/file.ts
(new)` `` — no line number — and is skipped. A path with a line number must
resolve. A bare path with no line number is ignored (prose, not a citation). A
`(new)` path carrying a line number is itself a failure, since that combination
can only be a mistake. Paths resolve against the current working directory, so
every command below `cd`s to the repository root first — an earlier draft of
this script derived the root from its own location and, run from anywhere else,
silently passed every citation in the file.

**Two consequences to accept rather than work around.** First, a line-numbered
citation in the §4.2 spec must be **repo-relative**
(`packages/terminal/crates/vt-core/src/lib.rs:291`), not the package-relative
shorthand that `TERMINAL.md` and this plan use in prose (`lib.rs:291`). The
shorthand is idiomatic in a document a human reads beside its Files block; it
is not mechanically checkable, and the §4.2 spec is the document whose
citations must be. Second, **this checker is for the spec, not for this plan**:
the plan embeds the script's own source, so it necessarily contains the
placeholder words the script rejects. Do not run it against the plan, and do
not edit the plan to satisfy it.

Create `/Users/omaraly/development/AI/Operator/scripts/check-spec-citations.mjs`:

```js
#!/usr/bin/env node
import { readFile, stat } from "node:fs/promises";
import { createReadStream } from "node:fs";
import { createInterface } from "node:readline";
import { resolve } from "node:path";

const [, , specPath, ...required] = process.argv;
if (!specPath) {
	console.error("usage: check-spec-citations.mjs <spec.md> [requiredHeading ...]");
	process.exit(2);
}

const root = resolve(process.cwd());
let text;
try {
	text = await readFile(specPath, "utf8");
} catch {
	console.error(`FAIL spec not found: ${specPath}`);
	process.exit(1);
}

const failures = [];
for (const heading of required) {
	if (!text.includes(heading)) failures.push(`missing required section: ${heading}`);
}
for (const bad of ["TBD", "TODO", "fill in", "implement later"]) {
	if (text.includes(bad)) failures.push(`placeholder present: ${bad}`);
}

const citation = /`(\/?[A-Za-z0-9_./-]+\.(?:rs|go|ts|tsx|dart|mjs|sh|css|md|yaml))(?::(\d+)(?:-(\d+))?)?(\s*\(new\))?`/g;
const seen = new Set();
let checked = 0;
for (const match of text.matchAll(citation)) {
	const [, rel, from, to, proposed] = match;
	const key = `${rel}:${from ?? ""}:${to ?? ""}`;
	if (seen.has(key)) continue;
	seen.add(key);
	if (proposed) {
		if (from) failures.push(`${rel}: a "(new)" path must not carry a line number`);
		continue;
	}
	if (!from) continue;
	const abs = rel.startsWith("/") ? rel : resolve(root, rel);
	let info = null;
	try {
		info = await stat(abs);
	} catch {
		info = null;
	}
	if (info === null || !info.isFile()) {
		failures.push(`${rel}:${from} does not exist (mark a path the design proposes creating as \`${rel} (new)\`, without a line number)`);
		continue;
	}
	checked += 1;
	const want = Number(to ?? from);
	let lines = 0;
	const reader = createInterface({ input: createReadStream(abs), crlfDelay: Infinity });
	for await (const _line of reader) lines += 1;
	if (lines < want) failures.push(`${rel}:${want} past end of file (${lines} lines)`);
}

if (failures.length > 0) {
	for (const failure of failures) console.error(`FAIL ${failure}`);
	process.exit(1);
}
console.log(`PASS spec citations: ${checked} resolved, ${required.length} sections present`);
```

- [ ] **Step 2: Run it against the not-yet-written spec to verify it fails**

```bash
cd /Users/omaraly/development/AI/Operator && node /Users/omaraly/development/AI/Operator/scripts/check-spec-citations.mjs /Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md "## Today" "## The gap" "## The design" "## Acceptance" "## Decisions needed" "## Non-goals"
```

Expected: exit 1 and exactly

```
FAIL spec not found: /Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md
```

Then prove the checker's three real failure modes on throwaway inputs, so the
gate is known to have teeth before anything is trusted to it:

```bash
cd /Users/omaraly/development/AI/Operator && for probe in 'packages/terminal/src/does-not-exist.ts:99' 'TERMINAL.md:999999' 'packages/terminal/ts/x.ts:12 (new)'; do printf 'p\n\n`%s`\n' "$probe" > /tmp/plan-f-probe.md; node /Users/omaraly/development/AI/Operator/scripts/check-spec-citations.mjs /tmp/plan-f-probe.md; done; rm -f /tmp/plan-f-probe.md
```

Expected, in order: `FAIL ... does not exist (mark a path the design proposes
creating as ...)`, `FAIL TERMINAL.md:999999 past end of file (940 lines)`, and
`FAIL ... a "(new)" path must not carry a line number`. Then confirm a passing
case against a spec that does exist:

```bash
cd /Users/omaraly/development/AI/Operator && node /Users/omaraly/development/AI/Operator/scripts/check-spec-citations.mjs /Users/omaraly/development/AI/Operator/docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md
```

Expected: `PASS spec citations: 5 resolved, 0 sections present`.

- [ ] **Step 3: Write the spec's frame — header, motivation, today**

Create the spec with this header (fill the date and the confirmed hashes):

```markdown
# Server-owned terminal model: the mirror as the model of record

**Date:** 2026-09-22
**Decision owner:** Omar Aly
**Status:** design only — no implementation tasks in this document
**Derived from:** `docs/terminal/2026-09-19-terminal-reference-survey.md` §4.2
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

Expected: `PASS spec citations: <n> resolved, 6 sections present`, exit 0,
where `<n>` is however many line-numbered citations the spec ended up with.

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
  (`terminal_cubit.dart:99`, `:281-283`). The desktop renderer **does** have a
  predictive echo as of Plan F (default off, armed only above a host RTT
  threshold — the desktop-against-remote-daemon case the user confirmed they
  use); the route to the same thing on the phone is the shared renderer that
  `docs/superpowers/specs/2026-09-22-server-owned-terminal-model-design.md`
  designs. **Do not build a second prediction implementation in the Dart
  fork** — that is the fork §4.2 exists to delete.
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
1 % of a realistic one. So **predictive echo does nothing for the phone case**
— it cannot even reach the phone (renderer-only overlay; the Flutter app draws
with its own `xterm` fork), and the mobile composer is already local echo. The
configuration it does help is the **desktop app against a remote daemon**,
which pays the full ~107 ms per keystroke in Claude Code's prompt; the user
confirmed on 2026-09-22 that they work that way often. Plan F therefore
delivered both bullets: the §4.2 design spec
(`2026-09-22-server-owned-terminal-model-design.md`) and predictive echo in the
desktop renderer as an overlay in the Plan E decoration layer — default off,
armed only above a host RTT threshold, painting in both surfaces, touching no
row and no model.
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

No CHANGELOG entry for Tasks 1–2: they change no behaviour. The echo's single
entry lands in Task 7.

---


### Task 3: The prediction state machine (pure, no DOM)

**Files:**
- Create: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom/src/prediction.ts`
- Test: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom/src/prediction.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces, used by Tasks 5, 6 and 7 with exactly these names and types:
  - `type KeyDescriptor = Readonly<{ text: string; ctrlKey: boolean; altKey: boolean; metaKey: boolean; isComposing: boolean }>`
  - `type CursorPoint = Readonly<{ row: number; column: number }>`
  - `type Prediction = Readonly<{ text: string; at: CursorPoint; sentAtMs: number }>`
  - `class PredictionState` with
    `register(key: KeyDescriptor, cursor: CursorPoint, nowMs: number): boolean`,
    `reconcile(cursor: CursorPoint, rowText: string, nowMs: number): void`,
    `pending(): readonly Prediction[]`,
    `suppressed(): boolean`,
    `clear(): void`
  - `const PREDICTION_TTL_MS = 500`

- [ ] **Step 1: Write the failing test**

Create `prediction.test.ts`. `ESC` below is written as the two-character escape
`` inside a TypeScript string literal, as the surrounding test files do.

```ts
import { describe, expect, it } from "vitest";
import { PredictionState, PREDICTION_TTL_MS } from "./prediction.js";

const key = (text: string, over: Partial<{ ctrlKey: boolean; altKey: boolean; metaKey: boolean; isComposing: boolean }> = {}) => ({
	text,
	ctrlKey: false,
	altKey: false,
	metaKey: false,
	isComposing: false,
	...over,
});

describe("PredictionState", () => {
	it("predicts a printable key at the cursor", () => {
		const state = new PredictionState();
		expect(state.register(key("a"), { row: 3, column: 5 }, 1000)).toBe(true);
		expect(state.pending()).toEqual([{ text: "a", at: { row: 3, column: 5 }, sentAtMs: 1000 }]);
	});

	it("does not predict a control or non-printable key", () => {
		const state = new PredictionState();
		expect(state.register(key("\r"), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("[A"), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key(""), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("c", { ctrlKey: true }), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("b", { altKey: true }), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("v", { metaKey: true }), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.pending()).toEqual([]);
	});

	it("does not predict a paste (more than one character in one event)", () => {
		const state = new PredictionState();
		expect(state.register(key("hello"), { row: 0, column: 0 }, 0)).toBe(false);
	});

	it("does not predict while an IME composition is open", () => {
		const state = new PredictionState();
		expect(state.register(key("a", { isComposing: true }), { row: 0, column: 0 }, 0)).toBe(false);
	});

	it("does not predict a wide or combining cluster", () => {
		const state = new PredictionState();
		expect(state.register(key("世"), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("́"), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("\u{1f600}"), { row: 0, column: 0 }, 0)).toBe(false);
	});

	it("retires a prediction the real output confirms", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 6 }, "xxxxxa", 1010);
		expect(state.pending()).toEqual([]);
	});

	it("expires a prediction that is never confirmed", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 5 }, "xxxxx", 1000 + PREDICTION_TTL_MS + 1);
		expect(state.pending()).toEqual([]);
	});

	it("suppresses prediction when the cursor did not advance after the last keystroke", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 5 }, "xxxxx", 1000 + PREDICTION_TTL_MS + 1);
		expect(state.suppressed()).toBe(true);
		expect(state.register(key("b"), { row: 3, column: 5 }, 2000)).toBe(false);
	});

	it("leaves suppression once the cursor advances again", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 5 }, "xxxxx", 1000 + PREDICTION_TTL_MS + 1);
		state.reconcile({ row: 3, column: 6 }, "xxxxxa", 3000);
		expect(state.suppressed()).toBe(false);
		expect(state.register(key("b"), { row: 3, column: 6 }, 3100)).toBe(true);
	});

	it("drops every prediction when the cursor jumps rows (a full redraw)", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 9, column: 0 }, "", 1010);
		expect(state.pending()).toEqual([]);
	});

	it("clear() drops everything and resets suppression", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 5 }, "xxxxx", 1000 + PREDICTION_TTL_MS + 1);
		state.clear();
		expect(state.pending()).toEqual([]);
		expect(state.suppressed()).toBe(false);
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/prediction.test.ts
```

Expected: FAIL — `Failed to resolve import "./prediction.js"`.

- [ ] **Step 3: Write the minimal implementation**

Create `prediction.ts`. The threshold gate lives in Task 4; this file decides
only *what* is predictable and *when* a prediction dies.

```ts
export const PREDICTION_TTL_MS = 500;

export type KeyDescriptor = Readonly<{
	text: string;
	ctrlKey: boolean;
	altKey: boolean;
	metaKey: boolean;
	isComposing: boolean;
}>;

export type CursorPoint = Readonly<{ row: number; column: number }>;

export type Prediction = Readonly<{ text: string; at: CursorPoint; sentAtMs: number }>;

// wezterm/wezterm-client/src/pane/renderable.rs predict_from_key_event
// vscode/src/vs/workbench/contrib/terminalContrib/typeAhead/browser/terminalTypeAheadAddon.ts
function isPredictable(key: KeyDescriptor): boolean {
	if (key.isComposing || key.ctrlKey || key.altKey || key.metaKey) return false;
	if ([...key.text].length !== 1) return false;
	const code = key.text.codePointAt(0)!;
	if (code < 0x20 || code === 0x7f) return false;
	if (code > 0x7e) return false;
	return true;
}

export class PredictionState {
	private predictions: Prediction[] = [];
	private suppress = false;
	private lastCursor: CursorPoint | null = null;

	register(key: KeyDescriptor, cursor: CursorPoint, nowMs: number): boolean {
		if (this.suppress || !isPredictable(key)) return false;
		const column = cursor.column + this.predictions.length;
		this.predictions.push({ text: key.text, at: { row: cursor.row, column }, sentAtMs: nowMs });
		this.lastCursor = cursor;
		return true;
	}

	reconcile(cursor: CursorPoint, rowText: string, nowMs: number): void {
		if (this.lastCursor !== null && cursor.row !== this.lastCursor.row) {
			this.predictions = [];
			this.lastCursor = cursor;
			return;
		}
		const kept: Prediction[] = [];
		for (const prediction of this.predictions) {
			const landed = cursor.column > prediction.at.column && rowText[prediction.at.column] === prediction.text;
			if (landed) {
				this.suppress = false;
				continue;
			}
			if (nowMs - prediction.sentAtMs > PREDICTION_TTL_MS) {
				this.suppress = true;
				continue;
			}
			kept.push(prediction);
		}
		this.predictions = kept;
		if (this.lastCursor !== null && cursor.column > this.lastCursor.column) this.suppress = false;
		this.lastCursor = cursor;
	}

	pending(): readonly Prediction[] {
		return this.predictions;
	}

	suppressed(): boolean {
		return this.suppress;
	}

	clear(): void {
		this.predictions = [];
		this.suppress = false;
		this.lastCursor = null;
	}
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/prediction.test.ts
```

Expected: PASS, 11 tests.

- [ ] **Step 5: Full package verification**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && (cd ts/renderer-dom && npx vitest run) && npm run bench:feel
```

Expected: build clean, every renderer-dom test passing, `PASS feel gate: zero
pixel diff` — nothing is wired yet, so the pane cannot have changed.

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom/src/prediction.ts packages/terminal/ts/renderer-dom/src/prediction.test.ts && git commit -m "renderer-dom: prediction state machine with its exclusion rules

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: The RTT meter and the threshold gate

**Files:**
- Create: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom/src/rtt.ts`
- Test: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom/src/rtt.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces, used by Tasks 5 and 7:
  - `class RttMeter` with `sent(nowMs: number): void`, `received(nowMs: number): void`,
    `median(): number | null`, `shouldPredict(thresholdMs: number): boolean`
  - `const RTT_WINDOW = 8`

**The clock rule, which is load-bearing.** `RttMeter` takes its milliseconds
from `performance.now()` at the call sites (Tasks 5 and 7) and **never** from
`Date.now()`. Plan E moved the feed clock to `Date.now()` because block
timestamps must be epoch milliseconds comparable with the Go mirror's
`time.Now().UnixMilli()` (`TERMINAL.md` §2, "BlockGrid clock"). Mixing the two
yields a difference of roughly 1.7 trillion, which would hold `shouldPredict`
above every threshold forever. The meter takes the number as an argument rather
than reading a clock itself precisely so this is testable.

- [ ] **Step 1: Write the failing test**

Create `rtt.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { RttMeter, RTT_WINDOW } from "./rtt.js";

describe("RttMeter", () => {
	it("has no median before any round trip completes", () => {
		const meter = new RttMeter();
		expect(meter.median()).toBe(null);
		meter.sent(100);
		expect(meter.median()).toBe(null);
	});

	it("measures one round trip", () => {
		const meter = new RttMeter();
		meter.sent(100);
		meter.received(180);
		expect(meter.median()).toBe(80);
	});

	it("takes the median of the window, not the last sample", () => {
		const meter = new RttMeter();
		for (const rtt of [100, 110, 90, 900, 105]) {
			meter.sent(0);
			meter.received(rtt);
		}
		expect(meter.median()).toBe(105);
	});

	it("keeps only the most recent RTT_WINDOW samples", () => {
		const meter = new RttMeter();
		for (let i = 0; i < RTT_WINDOW; i += 1) {
			meter.sent(0);
			meter.received(500);
		}
		for (let i = 0; i < RTT_WINDOW; i += 1) {
			meter.sent(0);
			meter.received(10);
		}
		expect(meter.median()).toBe(10);
	});

	it("ignores a receive with no matching send", () => {
		const meter = new RttMeter();
		meter.received(50);
		expect(meter.median()).toBe(null);
	});

	it("does not arm below the threshold", () => {
		const meter = new RttMeter();
		meter.sent(0);
		meter.received(7);
		expect(meter.shouldPredict(30)).toBe(false);
	});

	it("arms at or above the threshold", () => {
		const meter = new RttMeter();
		meter.sent(0);
		meter.received(107);
		expect(meter.shouldPredict(30)).toBe(true);
	});

	it("does not arm before any measurement exists", () => {
		expect(new RttMeter().shouldPredict(30)).toBe(false);
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/rtt.test.ts
```

Expected: FAIL — `Failed to resolve import "./rtt.js"`.

- [ ] **Step 3: Write the minimal implementation**

Create `rtt.ts`:

```ts
export const RTT_WINDOW = 8;

// wezterm/wezterm-client/src/pane/renderable.rs should_predict
export class RttMeter {
	private samples: number[] = [];
	private sentAt: number | null = null;

	sent(nowMs: number): void {
		if (this.sentAt === null) this.sentAt = nowMs;
	}

	received(nowMs: number): void {
		if (this.sentAt === null) return;
		this.samples.push(nowMs - this.sentAt);
		if (this.samples.length > RTT_WINDOW) this.samples.shift();
		this.sentAt = null;
	}

	median(): number | null {
		if (this.samples.length === 0) return null;
		const sorted = [...this.samples].sort((a, b) => a - b);
		return sorted[Math.floor(sorted.length / 2)]!;
	}

	shouldPredict(thresholdMs: number): boolean {
		const median = this.median();
		return median !== null && median >= thresholdMs;
	}
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/rtt.test.ts
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Full package verification**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && (cd ts/renderer-dom && npx vitest run) && npm run bench:feel
```

Expected: all green, `PASS feel gate: zero pixel diff`.

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom/src/rtt.ts packages/terminal/ts/renderer-dom/src/rtt.test.ts && git commit -m "renderer-dom: RTT meter and the predictive-echo threshold gate

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Paint predictions in the block surface

**Files:**
- Modify: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` (a `paintPredictions` beside `paintDecorations` at `:559` and `paintRedactions` at `:568`, called from the same two places those are called, `:774-776` and `:936-938`)
- Modify: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom/src/styles.css` (after `.terminal-redaction` at `:262`)
- Test: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts` (add a `describe` block)

**Interfaces:**
- Consumes from Task 3: `PredictionState`, `KeyDescriptor`, `Prediction`,
  `CursorPoint`. From Task 4: `RttMeter`.
- Produces, used by Tasks 6 and 7:
  - `setPredictiveEcho(config: { thresholdMs: number } | null): void`
  - `noteSend(nowMs: number): void`
  - `noteRoundTrip(sentMs: number, receivedMs: number): void`
  - `predictKey(key: KeyDescriptor, nowMs: number): boolean`
  - `predictionsClear(): void`
  - `predictionCount(): number`

- [ ] **Step 1: Write the failing test**

Add to `dom-block-renderer.test.ts`, using the mount helper the existing file
already defines:

```ts
const printable = (text: string) => ({ text, ctrlKey: false, altKey: false, metaKey: false, isComposing: false });

describe("predictive echo", () => {
	it("paints nothing when the host set no threshold", () => {
		const { renderer, host } = mountRenderer();
		renderer.predictKey(printable("a"), 1000);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
		expect(renderer.predictionCount()).toBe(0);
	});

	it("paints one dim glyph at the cursor once armed", () => {
		const { renderer, host } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), 1000);
		const painted = host.querySelectorAll(".terminal-prediction");
		expect(painted).toHaveLength(1);
		expect(painted[0]!.textContent).toBe("a");
	});

	it("paints nothing when the measured RTT is below the threshold", () => {
		const { renderer, host } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 7);
		renderer.predictKey(printable("a"), 1000);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
	});

	it("removes the glyph when real output confirms it", () => {
		const { renderer, host, feed } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), 1000);
		feed("a");
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
	});

	it("predictionsClear removes every painted glyph", () => {
		const { renderer, host } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), 1000);
		renderer.predictionsClear();
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
	});

	it("setPredictiveEcho(null) disarms and clears", () => {
		const { renderer, host } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), 1000);
		renderer.setPredictiveEcho(null);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
		expect(renderer.predictKey(printable("b"), 1100)).toBe(false);
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/dom-block-renderer.test.ts -t "predictive echo"
```

Expected: FAIL — `renderer.predictKey is not a function`.

- [ ] **Step 3: Implement the layer and its seams**

In `dom-block-renderer.ts`, import `PredictionState` and `KeyDescriptor` from
`./prediction.js` and `RttMeter` from `./rtt.js`, then add:

```ts
	private predictions = new PredictionState();
	private rtt = new RttMeter();
	private echoThresholdMs: number | null = null;

	setPredictiveEcho(config: { thresholdMs: number } | null): void {
		this.echoThresholdMs = config?.thresholdMs ?? null;
		if (this.echoThresholdMs === null) this.predictionsClear();
	}

	noteSend(nowMs: number): void {
		this.rtt.sent(nowMs);
	}

	noteRoundTrip(sentMs: number, receivedMs: number): void {
		this.rtt.sent(sentMs), this.rtt.received(receivedMs);
	}

	predictKey(key: KeyDescriptor, nowMs: number): boolean {
		if (this.echoThresholdMs === null || !this.rtt.shouldPredict(this.echoThresholdMs)) return false;
		const cursor = this.cursorPoint();
		if (cursor === null) return false;
		if (!this.predictions.register(key, cursor, nowMs)) return false;
		this.paintPredictions();
		return true;
	}

	predictionsClear(): void {
		this.predictions.clear();
		this.paintPredictions();
	}

	predictionCount(): number {
		return this.predictions.pending().length;
	}

	private paintPredictions(): void {
		const layer = this.layer("predictions");
		const container = this.container;
		if (!layer || !container) return;
		const pending = this.predictions.pending();
		const anchor = container.querySelector<HTMLElement>("[data-terminal-cursor-cell]");
		if (pending.length === 0 || !anchor) {
			paintBoxes(layer, "terminal-prediction", []);
			return;
		}
		const { cellWidth, cellHeight } = this.cellMetrics();
		const origin = container.getBoundingClientRect();
		const cell = anchor.getBoundingClientRect();
		const boxes = pending.map((_, index) => ({
			left: cell.left - origin.left + container.scrollLeft + index * cellWidth,
			top: cell.top - origin.top + container.scrollTop,
			width: cellWidth,
			height: cellHeight,
		}));
		paintBoxes(layer, "terminal-prediction", boxes, pending.map((prediction) => prediction.text));
	}
```

`cursorPoint()` returns `{ row, column }` read from the snapshot the renderer
already holds (`cursorRow`, `cursorColumn`), or `null` when the snapshot has no
visible cursor. Add `this.predictions.reconcile(cursor, rowText, performance.now())`
followed by `this.paintPredictions()` at the two places that already call
`this.paintDecorations(); this.paintRedactions();` — `:774-776` and `:936-938`
— so a prediction is reconciled on exactly the paints that can confirm it, and
never inside a half-parsed frame (`TERMINAL.md` §4.16).

Add to `styles.css` after `.terminal-redaction`:

```css
/* warp/crates/warp_terminal/src/model/grid/grid_renderer.rs draws provisional
   text at reduced alpha so it reads as not-yet-confirmed. */
.terminal-prediction {
	position: absolute;
	pointer-events: none;
	opacity: 0.45;
	font: inherit;
	line-height: var(--terminal-line-height);
	color: var(--terminal-foreground);
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/dom-block-renderer.test.ts -t "predictive echo"
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Full verification including both Playwright gates**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && (cd ts/renderer-dom && npx vitest run) && npm run bench:selection && npm run bench:feel
```

Expected: all green; `npm run bench:feel` prints `PASS feel gate: zero pixel
diff`. It must, because the harness sets no threshold — if it reddens, the
default-off gate is broken and that is the bug, not the baseline.

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts packages/terminal/ts/renderer-dom/src/styles.css packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts && git commit -m "renderer-dom: paint predictions in the block surface decoration layer

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Paint predictions on the alternate screen

**Files:**
- Modify: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` (`paintPredictions` picks its anchor per surface)
- Test: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts`

**Interfaces:**
- Consumes from Task 5: `paintPredictions`, `predictKey`, `setPredictiveEcho`,
  `noteRoundTrip`, `predictionsClear`, `predictionCount`. Adds no public name.

**Why this is its own task.** Claude Code's prompt is the **alternate screen**,
so the surface this plan exists to help is the one Task 5 does *not* cover. The
two surfaces mark the cursor with different attributes: the block cursor is
`[data-terminal-cursor-cell]` (`cursor.ts:8`, set at `:101`), the alt cursor is
`[data-terminal-cursor]` (`alt-surface.ts:7`, queried at `:83` and `:133`). A
prediction that paints in only one of them is a feature that works everywhere
except where it is needed.

- [ ] **Step 1: Write the failing test**

```ts
describe("predictive echo on the alternate screen", () => {
	it("paints at the alt cursor when the alt surface is showing", () => {
		const { renderer, host, enterAltScreen } = mountRenderer();
		enterAltScreen();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), 1000);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(1);
	});

	it("paints in whichever surface is showing, never both at once", () => {
		const { renderer, host, enterAltScreen, leaveAltScreen } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		enterAltScreen();
		renderer.predictKey(printable("a"), 1000);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(1);
		leaveAltScreen();
		renderer.predictionsClear();
		renderer.predictKey(printable("b"), 1100);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(1);
	});

	it("drops predictions when the alt screen redraws the whole frame", () => {
		const { renderer, host, enterAltScreen, feed } = mountRenderer();
		enterAltScreen();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), 1000);
		feed("[H[2J");
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/dom-block-renderer.test.ts -t "alternate screen"
```

Expected: FAIL — zero painted glyphs on the alt surface, because
`paintPredictions` queries `[data-terminal-cursor-cell]`, which the alt surface
does not have.

- [ ] **Step 3: Make the anchor surface-aware**

In `paintPredictions`, replace the single query with:

```ts
		const anchor =
			container.querySelector<HTMLElement>("[data-terminal-cursor]") ??
			container.querySelector<HTMLElement>("[data-terminal-cursor-cell]");
```

The alt cursor is queried first because while the alt surface is mounted it is
the live one and the block cursor element is not in the container. The
full-frame-redraw case needs no new code: Task 3's `reconcile` already drops
every prediction when the cursor changes row, which `ESC[H ESC[2J` does.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/dom-block-renderer.test.ts -t "predictive echo"
```

Expected: PASS, 9 tests — Task 5's six plus these three.

- [ ] **Step 5: Full verification including both Playwright gates**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && (cd ts/renderer-dom && npx vitest run) && npm run bench:selection && npm run bench:feel
```

Expected: all green, `PASS feel gate: zero pixel diff`.

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts && git commit -m "renderer-dom: predictions paint on the alternate screen too

Claude Code's prompt is the alt screen, so the surface that needs the echo is
the one the block-cursor anchor does not cover.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Wire the keystroke, the round trip and the host switch

**Files:**
- Modify: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/react/src/TerminalSurface.tsx` (the alt-screen `onKeyDown` whose send is at `:296`)
- Modify: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/core/src/types.ts` (`HostCapabilities`, defined at `:244`)
- Modify: `/Users/omaraly/development/AI/Operator/frontend/src/renderer/components/BlockTerminal.tsx`
- Modify: `/Users/omaraly/development/AI/Operator/packages/terminal/CHANGELOG.md`
- Test: `/Users/omaraly/development/AI/Operator/packages/terminal/ts/react/src/TerminalSurface.test.tsx` — and because this task's type change lands in **`ts/core`**, Step 6's suite list must include `ts/core` as well as `ts/renderer-dom` and `ts/react`. It does; do not trim it.

**Interfaces:**
- Consumes from Tasks 3–6: `predictKey`, `noteSend`, `noteRoundTrip`,
  `predictionsClear`, `setPredictiveEcho`, `predictionCount`, `KeyDescriptor`.
- Produces: `HostCapabilities.predictiveEcho?: Readonly<{ thresholdMs: number }>`
  — **optional and absent by default**, which is what makes the feature off.

**Why the switch is host-side and not a `RendererFeatures` flag.**
`RendererFeatures` (`features.ts:1-16`) is a set of *rendering* choices — how an
attribute, a cluster or a cursor is drawn — resolved once and applied
uniformly. The echo is not a rendering choice: whether it should arm depends on
the transport the **host** put the renderer behind, and the threshold is a
number only the host can pick (Operator knows whether a pane's daemon is
loopback or tunnelled; the package cannot). Putting it in `RendererFeatures`
would also make it flippable through `npm run bench:feel -- --feature`, letting
a pixel gate arm a feature that must never paint unprompted.

- [ ] **Step 1: Write the failing test**

Add to `TerminalSurface.test.tsx`:

```tsx
it("predicts a printable keystroke on the alternate screen when the host set a threshold", async () => {
	const { renderer, surface, typeKey } = await mountAltSurface({ predictiveEcho: { thresholdMs: 30 } });
	renderer.noteRoundTrip(0, 107);
	typeKey("a");
	expect(renderer.predictionCount()).toBe(1);
	expect(surface.querySelectorAll(".terminal-prediction")).toHaveLength(1);
});

it("predicts nothing when the host set no threshold", async () => {
	const { renderer, typeKey } = await mountAltSurface({});
	renderer.noteRoundTrip(0, 107);
	typeKey("a");
	expect(renderer.predictionCount()).toBe(0);
});

it("does not predict the copy chord or a control key", async () => {
	const { renderer, typeKey } = await mountAltSurface({ predictiveEcho: { thresholdMs: 30 } });
	renderer.noteRoundTrip(0, 107);
	typeKey("c", { metaKey: true });
	typeKey("Enter");
	expect(renderer.predictionCount()).toBe(0);
});

it("clears predictions when the pane tears down", async () => {
	const { renderer, typeKey, unmountSurface } = await mountAltSurface({ predictiveEcho: { thresholdMs: 30 } });
	renderer.noteRoundTrip(0, 107);
	typeKey("a");
	unmountSurface();
	expect(renderer.predictionCount()).toBe(0);
});
```

`mountAltSurface(host)` follows the existing alt-screen tests in this file;
`typeKey(key, modifiers?)` dispatches a `keydown` on the block host the way
they already do.

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && (cd ts/react && npx vitest run src/TerminalSurface.test.tsx -t "predict")
```

Expected: FAIL — the surface never calls `predictKey`.

- [ ] **Step 3: Wire the surface**

In `TerminalSurface.tsx`, in the alt-screen `onKeyDown` handler, immediately
before `onSendRaw(data)` at `:296`:

```tsx
			const now = performance.now();
			rendererRef.current?.noteSend(now);
			rendererRef.current?.predictKey(
				{ text: event.key, ctrlKey: event.ctrlKey, altKey: event.altKey, metaKey: event.metaKey, isComposing: event.isComposing },
				now,
			);
```

This sits after the existing copy-chord and `encodeKey` guards, so a chord or
an unencodable key has already returned and cannot register a prediction. The
matching `received` is called from the renderer's feed path with
`performance.now()`, never `Date.now()` — Task 4's clock rule.

Add the field to `HostCapabilities` in
`/Users/omaraly/development/AI/Operator/packages/terminal/ts/core/src/types.ts`,
as the last member, beside the other optional host-supplied capabilities
(`notify?`, `listDirectory?`, `resolvePath?`, `openPath?`, `secretPatterns?`):

```ts
	predictiveEcho?: Readonly<{ thresholdMs: number }>;
```

It is optional, so `NOOP_HOST` (`ts/core/src/terminal-core.ts:58`) and every
existing host need no change, and `HostCapabilities` is re-exported wholesale
from `ts/core/src/index-browser.ts:18`, so no export list changes either.
**This edit is in `ts/core`, which `renderer-dom` and `react` both build
against** — hence the `npm run build:ts` before the react tests in Steps 2 and
4, and `ts/core` in the suite list in Step 6.

Call `renderer.setPredictiveEcho(host.predictiveEcho ?? null)` where the other
host capabilities are applied, and `renderer.predictionsClear()` in the same
teardown that already clears the selection.

In `BlockTerminal.tsx`, pass `predictiveEcho` straight through from Operator's
props, defaulting to absent. Do **not** invent an Operator default here: the
host decides, and until Operator sets one the feature stays off.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && (cd ts/react && npx vitest run src/TerminalSurface.test.tsx -t "predict")
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Add the CHANGELOG entry**

In `packages/terminal/CHANGELOG.md`, under "Unreleased":

```markdown
- Predictive local echo on the alternate screen: while the measured input round
  trip stays at or above a host-supplied threshold, a printable keystroke
  paints a dim provisional glyph at the cursor, retired when real output
  confirms it or after 500 ms. An overlay in the decoration layer — no row,
  snapshot or model is touched. Off unless the host sets
  `HostCapabilities.predictiveEcho.thresholdMs`; skipped for pastes, control
  and modified keys, IME composition, wide and combining clusters, and while
  the previous keystroke produced no cursor advance.
```

- [ ] **Step 6: Full verification across every package the change reaches**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run) || exit 1; done && npm run bench:selection && npm run bench:feel
```

```bash
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p . && npm run lint
```

Expected: every suite green, `PASS feel gate: zero pixel diff`, typecheck and
lint clean. No wasm rebuild and no daemon rebuild: nothing in Rust or Go
changed.

- [ ] **Step 7: See it work against a remote daemon**

The gates prove it does not paint when off; this step proves it paints when on.
Stand up the rig the measurement used
(`docs/superpowers/specs/2026-09-22-remote-typing-latency-measurement.md` §1
and §6), set Operator's threshold to 30 ms, point the desktop app at the
tunnelled daemon and type in a Claude Code pane. Expected: each character
appears dim at the cursor within a frame and turns solid ~107 ms later as the
real repaint lands; with the app on its local daemon (~7 ms) no dim glyph ever
appears. Record what you saw in the commit message.

- [ ] **Step 8: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/react/src/TerminalSurface.tsx packages/terminal/ts/react/src/TerminalSurface.test.tsx packages/terminal/ts/core/src/types.ts packages/terminal/CHANGELOG.md frontend/src/renderer/components/BlockTerminal.tsx && git commit -m "terminal: wire predictive echo to the keystroke, the round trip and a host threshold

Off unless the host sets predictiveEcho.thresholdMs. Verified against a
tunnelled daemon: dim glyph within a frame, solid when the real repaint lands
~107ms later; nothing paints on a local daemon.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Self-review record (written with the plan)

- **Does the plan's shape follow the numbers?** Yes, on both axes, and that was
  the test it had to pass. The measurement put Claude's turn at 1.24 s median
  against 106.7 ms of network over the tunnel and 6.6 ms locally, so the phone
  case the user opened with is Claude-bound and predictive echo is not its
  answer — the §4.2 spec is, and it comes first (Task 1). The measurement also
  showed the remote *per-keystroke* cost is real and almost entirely network,
  and the one configuration paying it inside Claude Code's prompt is the
  desktop against a remote daemon. Whether the user works that way is not a
  fact about this machine, so it was asked rather than assumed; the answer was
  "yes, often", which is the brief's third branch and is why Tasks 3–7 exist.
  Had the answer been no, they would not.
- **Spec coverage, Part 6 bullet by bullet.** *Server-owned model* — Task 1,
  whose Steps 3–5 enumerate every element the brief requires: `(stable row,
  generation)` with the mirror as the model of record; what replaces the byte
  channel and what stays; Plan C's attach/replay/history mapped on; the
  renderer's own `vt-core` copy; what it buys; what it costs and breaks
  including the mux protocol, both mux clients, the editor's local-echo path,
  offline behaviour and Plan C's flow-control acks; the landed prerequisites
  with hashes; the decisions it needs; and the measurement as its motivation.
  *Predictive echo* — Tasks 3–7: the dim overlay glyph at the cursor (5, 6),
  the measured-RTT threshold gate (4), removal when real output advances the
  cursor and expiry when it does not (3), and the skip after a keystroke that
  produced no cursor advance (3, `suppressed()`).
- **Every exclusion the brief listed has its own test.** No-echo/password →
  `suppressed()` after a keystroke the cursor did not follow (Task 3, two
  tests). Cursor moved but text did not → the same pair. Alt-screen full redraw
  → "drops every prediction when the cursor jumps rows" (Task 3) and "drops
  predictions when the alt screen redraws the whole frame" (Task 6). Paste →
  "does not predict a paste (more than one character in one event)". Control or
  non-printable key → "does not predict a control or non-printable key", six
  assertions, plus Task 7's chord test at the real call site. Wide/CJK cluster
  → "does not predict a wide or combining cluster", three assertions. A
  keystroke while a DEC 2026 block is open → covered by construction rather
  than by a rule, and this is deliberate: the renderer paints only complete
  frames (`TERMINAL.md` §4.16), so `reconcile` never runs against a half-parsed
  frame; the prediction survives to the terminator or dies on the 500 ms TTL,
  which is the "never confirmed must expire" case. Both surfaces → Task 6.
- **Placeholder scan.** No "TBD", "TODO", "implement later", "add appropriate
  handling" or "similar to Task N". Task 1 Step 1 ships the checker that fails
  on those words, and Task 1 Step 2 proves its three failure modes on throwaway
  inputs before the executor trusts it — including the one this plan's first
  draft got wrong, where a citation to a path that does not exist was silently
  skipped, and the one after that, where deriving the repository root from the
  script's own location made every citation pass when it was invoked from
  elsewhere.
- **Type consistency.** `KeyDescriptor` is `{ text, ctrlKey, altKey, metaKey,
  isComposing }` in `prediction.ts`, both test files, `predictKey`'s signature
  and the `TerminalSurface` call site. `CursorPoint` is `{ row, column }` in
  `prediction.ts`, `reconcile` and `cursorPoint()`. `Prediction` is `{ text,
  at, sentAtMs }` in Task 3's assertions and Task 5's `paintPredictions`.
  `PREDICTION_TTL_MS = 500` matches the CHANGELOG's "after 500 ms". `RttMeter`'s
  four methods (`sent`, `received`, `median`, `shouldPredict`) are spelled the
  same in `rtt.ts`, `rtt.test.ts` and the renderer's `noteSend` /
  `noteRoundTrip`. The renderer's six public seams — `setPredictiveEcho`,
  `noteSend`, `noteRoundTrip`, `predictKey`, `predictionsClear`,
  `predictionCount` — are spelled identically in Tasks 5, 6, 7 and the File
  Structure table. `HostCapabilities.predictiveEcho.thresholdMs` is spelled the
  same in `ts/core/src/types.ts` (where `HostCapabilities` actually lives —
  `renderer-dom` has no `types.ts` and only imports the type),
  `TerminalSurface`, `BlockTerminal` and the CHANGELOG.
  `.terminal-prediction` matches across `styles.css`, `paintBoxes` and every
  test query. The `printable()` helper is defined once in Task 5 and reused by
  Task 6, which is why Task 6's tests do not redefine it. The four merge hashes
  (`ba6dd6d35`, `7412050f4`, `b4c3067b2`, `7336d8150`) match
  `git log --oneline | grep -i "merge: Plan"`.
- **Constraints deliberately not applied, stated so the omission reads as a
  decision.** No `cargo`, no `go`, no `build:wasm`, no daemon rebuild and no
  "restart the daemon" line: the echo is an overlay and touches neither engine.
  One CHANGELOG entry, in Task 7 only, because that is where the behaviour
  becomes reachable. `bench:feel` on every code task expecting **zero** pixel
  diff, because default-off means the current pane must stay byte-identical;
  `bench:selection` on Tasks 5–7, which touch the overlay.
