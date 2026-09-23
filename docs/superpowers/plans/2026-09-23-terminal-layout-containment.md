# Terminal Layout Containment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Find out, by measurement, whether `contain: layout` on `.terminal-row` (then `.terminal-block`) makes the one layout each visible terminal pane pays per output frame cheaper. Keep a step only if it is pixel-identical and a real gain; otherwise record that it was measured and did not help.

**Architecture:** Measure first, change source second. Task 1 adds bench-only tooling: a `?css=` page parameter that injects a stylesheet, a Chromium trace script, a synchronous repaint loop that also runs in WebKit, and a `--profile-row` flag. With those tools a candidate rule can be A/B-measured in one session, interleaved with a control, **without touching the package's CSS**. Only a candidate that wins goes into `styles.css`/`styles.ts`, test first, and then through the pixel gates. "No gain, nothing changed" is a legitimate outcome, and then the deliverable is the measurement note plus the TERMINAL.md entry.

**Tech Stack:** CSS containment; `@operator/terminal-renderer-dom` (`styles.css` + its byte-identical copy `styles.ts`); Vitest; Playwright 1.60.0 (Chromium + CDP, optionally WebKit); Vite dev server for the bench page.

**Spec:** [`docs/superpowers/specs/2026-09-23-layout-containment-measurement.md`](../specs/2026-09-23-layout-containment-measurement.md) is the before measurement this plan argues from. Read it before Task 1. Origin: [`docs/terminal/2026-09-23-day-to-day-suggestions.md`](../../terminal/2026-09-23-day-to-day-suggestions.md) item 1. Background: [`docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md`](../specs/2026-09-23-background-pane-cost-measurement.md).

## What planning found (read before any task)

The request that produced this plan made several claims. Planning checked each one on `development` at `f4d93ba68`. Where the code says otherwise, the code wins:

1. **Plan 4 is fully merged.** `terminal-background-pane` (`86cea9339`) was merged at `f4d93ba68`, Task 11 included (`13ad4994d`, `0961fb455`).
2. **Line numbers moved.** `reconcileChildren` is at `ts/renderer-dom/src/dom-block-renderer.ts:1146`. The pinned-header `getBoundingClientRect` test is at `:1147-1151`, with the read itself at `:1149`. `applyStickiness` reads `scrollHeight` at `:1222` and is called from `:1165`. TERMINAL.md §5 cites `:1141`, which is also stale; Task 5 corrects it.
3. **The scroller is already contained.** `mount()` sets `container.style.contain = "strict"` (`dom-block-renderer.ts:161`, since `4d0e90ca1` "virtualize the block list by block and by row") and `dispose()` removes it (`:798`). `styles.css` has no `contain` because this one is inline. The scroller is therefore already a size+layout boundary: a changed row dirties the row, its block, `.terminal-list` and the scroller, and the dirtying **stops there**. It never reaches the rest of the page, the other panes included.
4. **No frame pays two layouts.** Every layout in the 100-frame feed is forced inside `repaint`, with 0 in the render step (122/122 solo, 1220–1221/1220–1221 for 10 visible, two traces; measurement note "Does any frame pay two layouts?"). **Deriving the pinned-header test from the windowing result is therefore out of scope.** No task for it.
5. **Each layout already touches a median of 142 dirty objects out of 274–370** (`Layout` trace event `beginData`). Containment can only save work on the clean ones. Expectation: a small gain or none (measurement note, read-outs).
6. **`npm run bench:feel` does not diff the `feature-*` baselines.** With `--feature <f>` it *overwrites* `baselines/<target>/feature-<f>/offset-*.png` without comparing them (`bench/agent-session/feel-gate.mjs:64-83`); only the default `offset-*.png` are diffed (`:55-61`). `npm run bench:affordances` with no `--action` exits with a usage error (`affordance-gate.mjs:13-14`), and it also only writes its PNGs. Task 1 therefore captures regenerated copies before any change, and every pixel gate below compares byte-for-byte against those copies. All four targets (`claude-long-50k`, `claude-spinner-10s`, `act-probe`, `glyph-probe`) carry all six `feature-*` dirs.
7. **`--profile` profiles only the `parked9` row** (`run.mjs:159`). Task 1 adds `--profile-row`.
8. **There is no TERMINAL.md "overscroll" entry.** The WKWebView rubber-band fix exists only as two CHANGELOG.md Unreleased entries (lines 25–26 on `f4d93ba68`), `overscrolled()` (`dom-block-renderer.ts:66-68`), the scroll-anchor guard at `:1166`, `applyScrollOverflow` (`:1265-1269`) and the unit test `dom-block-renderer.test.ts:967` "does not fight an elastic overscroll past either edge".
9. **The overlays are not inside rows or blocks.** The link underline, hint matches and labels, redaction masks and prediction overlay are painted in `.terminal-decorations`, a child of the scroller appended after the list (`dom-block-renderer.ts:178-182`, layers from `:589`). The pinned header is a scroller child before the list (`:175-177`). The jump-to-bottom button is a scroller child (`jump-to-bottom.ts:130`). The find bar and palette append to the container (`find-bar.ts:322`, `palette.ts:181`). The IME composition view appends to the host or the editor root (`ts/core/src/composition-target.ts:107`). `renderBlockActions` (`block-actions.ts:109`) is exported but mounted by nothing in `ts/` or `frontend/src`. The selection fill is the row's own `background-image` (`dom-block-renderer.ts:1184-1194`), inside the row box. Inside `.terminal-block` the only positioned descendants are `.terminal-row` (`position: relative; z-index: 0`, styles.css:295-300), `.terminal-cursor` (absolute, inside the row, `cursor.ts:49`) and `.terminal-block-glyph > i` (absolute, inside the glyph, which is `position: relative`, styles.css:437-448).
10. **Row height is not provably one line**, so `contain: size`, `contain: strict` and `content-visibility: auto` stay out of scope. Runs are `inline-block` at exactly `--terminal-line-height` (styles.css:362-367), and so are block glyphs (`:437-444). But a row's text past its last style run is appended **directly into the row's own line box** as a text node or glyph (`row-builder.ts:116-119`), so that line's height comes from the fonts of whatever glyphs land there, fallback fonts included. Nothing in the code bounds it. A row is also `min-height`, not `height` (styles.css:299).
11. **Playwright WebKit is not installed** (`~/Library/Caches/ms-playwright` holds `chromium-*` and `chromium_headless_shell-*` only). Installing it is a download the user must approve (Task 1 Step 9).
12. **`styles.ts` is a hand-kept byte copy of `styles.css`.** `styles-parity.test.ts` "is byte-identical to the published styles.css export" fails unless both change together.

## Global Constraints

- Read `TERMINAL.md` end to end, `AGENTS.md`, and the measurement note before Task 1.
- `packages/terminal` stays product-independent (TERMINAL.md §3.1). This is terminal-package CSS and bench tooling only: no `frontend/`, no Operator UI, no `DESIGN.md`.
- **No comments in new code, CSS or scripts** (the user's global rule). Existing comments may be corrected if they become false.
- Every `styles.css` change is made byte-for-byte in `styles.ts` too.
- The only `contain` values this plan may add are `layout` (and `style` only if a later measurement argues for it; this plan does not). Never `paint`, `size`, `inline-size`, `strict`, `content`, and never `content-visibility`.
- Do not touch Plan 4's behaviour (`docs/superpowers/plans/2026-09-23-terminal-background-pane-cost.md`): the visibility seam, the paint gate, the hidden-document timer, `settleHidden`, `HIDDEN_*` constants, the unload. No change to `dom-block-renderer.ts` at all.
- Pixel identity: never re-record a feel baseline or commit a regenerated `feature-*`/`affordance-*` PNG to make a gate pass.
- Specs, notes and TERMINAL.md cite `file:line` or write "not known". Never count from a piped listing.
- Warp (`/Users/omaraly/development/AI/warp`) is AGPL: read for ideas only, never copy.
- The checkout is shared with other sessions: **never `git stash`, never `git commit -a`**; commit with an explicit path list, on `development`, message ending with the harness's `Co-Authored-By` trailer.
- Every command uses absolute paths (TERMINAL.md §6). `$T` below means `/Users/omaraly/development/AI/Operator/packages/terminal`, and `$S` means your session's scratchpad directory. Set both in every Bash call (`T=/Users/omaraly/development/AI/Operator/packages/terminal; S=<your scratchpad>`), because shell state does not persist.
- The bench runs `dist/`: after any `ts/` or CSS change run `npm run build:ts` in `$T` before measuring or gating (memory note "Rebuild terminal dist before testing renderer fixes").
- Record the 1-minute load average (`uptime`) at the start and end of every measurement run, into a load log committed next to the run files.

## Review Focus

1. **Paint that overflows a row or block**: the cursor, a curly or double underline under `attributes: "warp"`, a fallback glyph taller than the line, an inverted cursor. Expected: pixel-identical, because `contain: layout` does not clip. Pinned by the stylesheet guard test (Task 2 Step 8) and the `feature-attributes_warp`, `feature-cursorContrast` and `feature-cursorHollowUnfocused` byte comparisons in every pixel gate.
2. **Scroll extent and stick-to-bottom**: `scrollHeight`, `applyStickiness`, `overscrolled()`, the rubber-band guard. Expected: unchanged, because layout containment does not change an element's size. Pinned by `bench:feel` (its five offsets are fractions of `scrollHeight`, so a changed extent changes every screenshot), `bench:agent:scroll`, `dom-block-renderer.test.ts:967`, and the Task 4 real-app overscroll check.
3. **Overlays above a block that has become a stacking context** (Task 3 only). `contain: layout` makes `.terminal-block` a stacking context, which it is not today (no `position`, no `z-index`, styles.css:93-113), so its background moves from the block-background paint phase to the z-index-0 positioned phase in tree order. The link underline, hint labels and redaction masks sit in `.terminal-decorations` at `z-index: 2` (styles.css:215-228). The pinned header is sticky at `z-index: 2` (`:528-531`). Expected: unchanged. Pinned by the `affordance-hover`, `affordance-hint` and `affordance-redact` byte comparisons (Task 3 Step 6) and the Task 4 real-app hover check.
4. **Selection fill across rows and across a block boundary.** Expected: unchanged. Pinned by `npm run bench:selection` (Task 4) and the real-app select check.
5. **The pinned header over a scrolled shell block** once blocks are stacking contexts. The Claude Code fixtures' blocks are synthetic (header `display: none`, styles.css:550-552), so no bench screenshot shows it. Pinned only by the Task 4 real-app check: a shell pane scrolled into a long command's output, with the pinned header drawn above the rows. Report it "not verified" with the reason if it cannot be run.

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `packages/terminal/bench/agent-session/main.ts` | `?css=` injection; `repaintLoop(frames)` | 1 |
| `packages/terminal/bench/agent-session/run.mjs` | `--css`, `--profile-row` | 1 |
| `packages/terminal/bench/agent-session/layout-trace.mjs` (new) | trace: forced vs render-step layouts, dirty objects; a CPU profile of a chosen row | 1 |
| `packages/terminal/bench/agent-session/repaint-loop.mjs` (new) | synchronous repaint timing in Chromium or WebKit | 1 |
| `packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-23-containment-*` | raw run output (new files only, never overwrite) | 1, 2, 3 |
| `packages/terminal/ts/renderer-dom/src/styles.css` + `styles.ts` | `contain: layout` on `.terminal-row` / `.terminal-block`, only if kept | 2, 3 |
| `packages/terminal/ts/renderer-dom/src/styles-parity.test.ts` | the containment tests and the guard | 2, 3, 5 |
| `packages/terminal/CHANGELOG.md` | one Unreleased entry per kept change, and one for the bench tooling | 1, 2, 3 |
| `docs/superpowers/specs/2026-09-23-layout-containment-measurement.md` | "After" section | 5 |
| `TERMINAL.md` | §4.26 entry; §5 line-number correction | 5 |

---

### Task 1: Measurement tooling, before-state confirmation, pixel copies, WebKit

The before numbers were measured during planning on `f4d93ba68` (measurement note "Before"; run files `baselines/pane-cost/2026-09-23-containment-before-run{1,2,3}.json`, `…-before-trace-run{1,2}.json`, `…-before-load.txt`). This task confirms they still describe the tree, adds the tools Tasks 2–3 measure with, captures the pixel before-state, and settles WebKit.

**Files:**
- Modify: `packages/terminal/bench/agent-session/main.ts` (type `AgentSession` at `:20-65`, after `domRenderer.setFocused(…)` at `:97`, `window.__agentSession` at `:415`)
- Modify: `packages/terminal/bench/agent-session/run.mjs:17-42,149-164,304`
- Create: `packages/terminal/bench/agent-session/layout-trace.mjs`
- Create: `packages/terminal/bench/agent-session/repaint-loop.mjs`
- Modify: `packages/terminal/CHANGELOG.md` (Unreleased)

**Interfaces:**
- Produces: bench page query parameter `css=<stylesheet text>`, appended to `<head>` as a `<style data-bench-css>`.
- Produces: `window.__agentSession.repaintLoop(frames: number): { frames: number; totalMs: number }`. It feeds the next `frames` DEC 2026 frames to the main pane and every visible extra pane, then calls each visible pane's `DomBlockRenderer.repaint()` synchronously, once per frame.
- Produces: `node bench/agent-session/run.mjs --panes-only [--css <text>] [--profile --profile-row <solo|parked3|parked9|visible10>]`.
- Produces: `node bench/agent-session/layout-trace.mjs [--css <text>]` prints one JSON line: `{ measuredAt, css, trace: { solo, visible10 }, profile: { visible10: { file, top } } }`.
- Produces: `node bench/agent-session/repaint-loop.mjs --browser <chromium|webkit> [--css <text>] [--frames <n>]` prints one JSON line: `{ measuredAt, browser, css, solo: { frames, totalMs }, visible10: { frames, totalMs } }`.

- [x] **Step 1: Confirm the before numbers still describe the tree**

```bash
cd /Users/omaraly/development/AI/Operator && git log --oneline -1 && git diff --stat f4d93ba68 HEAD -- packages/terminal/ts packages/terminal/crates packages/terminal/bench/agent-session/main.ts packages/terminal/bench/adapters
```

Expected: empty diff. If it is **not** empty, renderer or harness code changed after the before-runs. Rebuild (`cd $T && npm run build:wasm -- --force && npm run build:ts`), re-run `node $T/bench/agent-session/run.mjs --panes-only` three times, save them as `baselines/pane-cost/<today>-containment-before-rerun{1,2,3}.json`, and add a "Before (re-run)" subsection to the measurement note. If the trace (Step 7) then shows any render-step layout, **stop and report**: the double-layout finding no longer holds, and the pinned-header task the request describes would come back into scope.

- [x] **Step 2: `?css=` injection in the bench page**

In `$T/bench/agent-session/main.ts`, directly after `domRenderer.setFocused(params.get("focused") !== "0");` (`:97`):

```ts
const benchCss = params.get("css");
if (benchCss) {
	const tag = document.createElement("style");
	tag.dataset.benchCss = "";
	tag.textContent = benchCss;
	document.head.append(tag);
}
```

The injected rule has the same specificity as the package rule, and no package rule sets `contain` on a row or block, so `.terminal-row{contain:layout}` injected is the same computed style as the source change Task 2 would make.

- [x] **Step 3: `repaintLoop`**

In the `AgentSession` type (`main.ts:20-65`), after `feedFrames(count: number, intervalMs: number): Promise<void>;`:

```ts
	repaintLoop(frames: number): { frames: number; totalMs: number };
```

After the `feedFrames` function (`:362-374`):

```ts
function visibleRenderers(): DomBlockRenderer[] {
	return [
		domRenderer,
		...extraPanes
			.filter(({ mode }) => mode === "visible")
			.map(({ pane }) => (pane as unknown as { renderer: DomBlockRenderer }).renderer),
	];
}

function repaintLoop(count: number): { frames: number; totalMs: number } {
	const ends = frameEnds().filter((end) => end > fed).slice(0, count);
	const renderers = visibleRenderers();
	const began = performance.now();
	for (const end of ends) {
		const start = fed;
		feedChunk(start, end);
		for (const { pane, mode } of extraPanes) {
			if (mode === "visible") (pane.getCoreForBench() as TerminalCore).feed(recording.subarray(start, end));
		}
		for (const paneRenderer of renderers) (paneRenderer as unknown as { repaint(): void }).repaint();
	}
	return { frames: ends.length, totalMs: performance.now() - began };
}
```

In the `window.__agentSession = { … }` object, after `feedFrames,`:

```ts
	repaintLoop,
```

`repaintLoop` measures script, style and the forced layout of `repaint` itself, in any engine, with `performance.now()` totals over ~100 frames. That matters because WebKit coarsens `performance.now()`, and a total over hundreds of milliseconds survives the coarsening where per-call timings would not. It measures neither paint nor the render step, and the render step lays out nothing today (planning finding 4).

- [x] **Step 4: `run.mjs` flags**

In `$T/bench/agent-session/run.mjs`:

`parseArgs` (`:17-29`): replace the `out` initialiser and add two branches:

```js
	const out = { fixture: undefined, gate: false, features: "", panesOnly: false, profile: false, ungated: false, css: "", profileRow: "parked9" };
```

```js
		else if (argv[index] === "--css") out.css = argv[++index];
		else if (argv[index] === "--profile-row") out.profileRow = argv[++index];
```

`openPage` (`:36-42`):

```js
async function openPage(browser, port, fixture, features, ungated = false, css = "") {
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	const suffix = `${features ? `&features=${encodeURIComponent(features)}` : ""}${ungated ? "&ungated=1" : ""}${css ? `&css=${encodeURIComponent(css)}` : ""}`;
```

(the rest of `openPage` unchanged). `paneRows` (`:149-164`):

```js
async function paneRows(browser, port, name, features, profile, ungated = false, css = "", profileRow = "parked9") {
	const rows = {};
	const shapes = [
		["solo", { extra: 0, mode: "visible" }],
		["parked3", { extra: 3, mode: "parked" }],
		["parked9", { extra: 9, mode: "parked" }],
		["visible10", { extra: 9, mode: "visible" }],
	];
	for (const [key, shape] of shapes) {
		const page = await openPage(browser, port, name, features, ungated, css);
		const profileOut = profile && key === profileRow ? path.join(resultsDir, `${key}-${Date.now()}.cpuprofile`) : undefined;
		rows[key] = await paneLoad(page, { ...shape, profileOut });
		await page.close();
	}
	return rows;
}
```

The `--panes-only` call (`:304`):

```js
				rows.panes = await paneRows(browser, port, name, args.features, args.profile, args.ungated, args.css, args.profileRow);
```

Add `if (args.css) report.css = args.css;` directly after `const report = { … };` (`:295`), and change the stdout line (`:349`) to `process.stdout.write(`${JSON.stringify({ fixture: name, ...(args.css ? { css: args.css } : {}), ...rows })}\n`);` so every run file says which stylesheet it measured.

- [x] **Step 5: `layout-trace.mjs`**

Create `$T/bench/agent-session/layout-trace.mjs`. It is the planning-time script (which produced `…-before-trace-run{1,2}.json`) plus `--css`:

```js
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const benchDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const configFile = path.join(benchDir, "vite.config.ts");
const resultsDir = path.join(benchDir, "results");
const SCRIPT_EVENTS = new Set(["FireAnimationFrame", "FunctionCall", "TimerFire", "EvaluateScript", "EventDispatch", "RunMicrotasks", "v8.callFunction"]);
const CATEGORIES = ["devtools.timeline", "disabled-by-default-devtools.timeline", "disabled-by-default-devtools.timeline.frame", "blink"];

function parseArgs(argv) {
	const out = { css: "" };
	for (let index = 0; index < argv.length; index += 1) {
		if (argv[index] === "--css") out.css = argv[++index];
		else throw new Error(`unsupported argument ${argv[index]}`);
	}
	return out;
}

function median(values) {
	const sorted = [...values].sort((a, b) => a - b);
	return sorted.length === 0 ? null : sorted[Math.floor(sorted.length / 2)];
}

function intervalsOf(events) {
	const out = [];
	const open = new Map();
	for (const event of events) {
		if (event.ph === "X") out.push({ name: event.name, start: event.ts, end: event.ts + (event.dur ?? 0), args: event.args ?? {} });
		else if (event.ph === "B") {
			if (!open.has(event.name)) open.set(event.name, []);
			open.get(event.name).push(event);
		} else if (event.ph === "E") {
			const begin = open.get(event.name)?.pop();
			if (begin) out.push({ name: event.name, start: begin.ts, end: event.ts, args: { ...(begin.args ?? {}), ...(event.args ?? {}) } });
		}
	}
	return out;
}

function analyze(events) {
	const names = new Map();
	for (const event of events) if (event.ph === "M" && event.name === "thread_name") names.set(`${event.pid}:${event.tid}`, event.args.name);
	const byThread = new Map();
	for (const event of events) {
		if (event.ph === "M") continue;
		const key = `${event.pid}:${event.tid}`;
		if (!byThread.has(key)) byThread.set(key, []);
		byThread.get(key).push(event);
	}
	let main = null;
	let most = -1;
	for (const [key, list] of byThread) {
		if (names.get(key) !== "CrRendererMain") continue;
		const count = list.filter((event) => event.name === "Layout").length;
		if (count > most) (most = count), (main = key);
	}
	const list = (byThread.get(main) ?? []).sort((a, b) => a.ts - b.ts);
	const intervals = intervalsOf(list);
	const scripts = intervals.filter((entry) => SCRIPT_EVENTS.has(entry.name)).sort((a, b) => a.start - b.start);
	const layouts = intervals.filter((entry) => entry.name === "Layout").sort((a, b) => a.start - b.start);
	const recalcs = intervals.filter((entry) => entry.name === "UpdateLayoutTree").sort((a, b) => a.start - b.start);
	const frameStarts = list.filter((event) => event.name === "BeginMainThreadFrame").map((event) => event.ts);
	const rafs = scripts.filter((entry) => entry.name === "FireAnimationFrame").map((entry) => entry.start);
	const marks = frameStarts.length > 0 ? frameStarts : rafs;
	const inScript = (t) => scripts.some((entry) => entry.start <= t && t < entry.end);
	const frameOf = (t) => {
		let lo = 0;
		let hi = marks.length - 1;
		let found = -1;
		while (lo <= hi) {
			const mid = (lo + hi) >> 1;
			if (marks[mid] <= t) (found = mid), (lo = mid + 1);
			else hi = mid - 1;
		}
		return found;
	};
	const perFrame = new Map();
	const tally = (t, field) => {
		const frame = frameOf(t);
		if (!perFrame.has(frame)) perFrame.set(frame, { forced: 0, renderStep: 0, recalcForced: 0, recalcRenderStep: 0 });
		perFrame.get(frame)[field] += 1;
	};
	let forcedMs = 0;
	let renderStepMs = 0;
	const dirty = [];
	const total = [];
	for (const layout of layouts) {
		const forced = inScript(layout.start);
		if (forced) forcedMs += (layout.end - layout.start) / 1000;
		else renderStepMs += (layout.end - layout.start) / 1000;
		tally(layout.start, forced ? "forced" : "renderStep");
		const begin = layout.args.beginData ?? {};
		if (typeof begin.dirtyObjects === "number") dirty.push(begin.dirtyObjects);
		if (typeof begin.totalObjects === "number") total.push(begin.totalObjects);
	}
	for (const recalc of recalcs) tally(recalc.start, inScript(recalc.start) ? "recalcForced" : "recalcRenderStep");
	const frames = [...perFrame.values()];
	return {
		frameDelimiter: frameStarts.length > 0 ? "BeginMainThreadFrame" : "FireAnimationFrame",
		frameMarks: marks.length,
		layouts: layouts.length,
		forcedLayouts: layouts.filter((layout) => inScript(layout.start)).length,
		renderStepLayouts: layouts.filter((layout) => !inScript(layout.start)).length,
		forcedLayoutMs: Number(forcedMs.toFixed(1)),
		renderStepLayoutMs: Number(renderStepMs.toFixed(1)),
		framesWithLayout: frames.filter((frame) => frame.forced + frame.renderStep > 0).length,
		framesWithForcedAndRenderStep: frames.filter((frame) => frame.forced > 0 && frame.renderStep > 0).length,
		framesWithTwoOrMoreLayouts: frames.filter((frame) => frame.forced + frame.renderStep >= 2).length,
		maxLayoutsInOneFrame: Math.max(0, ...frames.map((frame) => frame.forced + frame.renderStep)),
		styleRecalcs: recalcs.length,
		forcedStyleRecalcs: recalcs.filter((recalc) => inScript(recalc.start)).length,
		renderStepStyleRecalcs: recalcs.filter((recalc) => !inScript(recalc.start)).length,
		medianDirtyObjects: median(dirty),
		medianTotalObjects: median(total),
	};
}

function selfTimeTop(profile, count) {
	const byId = new Map(profile.nodes.map((node) => [node.id, node]));
	const self = new Map();
	for (let index = 0; index < profile.samples.length; index += 1) {
		const frame = byId.get(profile.samples[index]).callFrame;
		const url = frame.url ? frame.url.replace(/^https?:\/\/[^/]+/, "").replace(/\?.*$/, "") : "";
		const key = `${frame.functionName || "(anonymous)"} ${url}${url ? `:${frame.lineNumber + 1}` : ""}`;
		self.set(key, (self.get(key) ?? 0) + (profile.timeDeltas[index] ?? 0) / 1000);
	}
	return [...self.entries()].sort((a, b) => b[1] - a[1]).slice(0, count).map(([fn, ms]) => ({ fn, selfMs: Number(ms.toFixed(1)) }));
}

async function openPane(browser, port, extra, css) {
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=claude-spinner-10s${css ? `&css=${encodeURIComponent(css)}` : ""}`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	if (extra > 0) await page.evaluate((count) => window.__agentSession.mountPanes(count, "visible"), extra);
	return page;
}

async function traced(browser, port, extra, css) {
	const page = await openPane(browser, port, extra, css);
	const session = await page.context().newCDPSession(page);
	const events = [];
	session.on("Tracing.dataCollected", ({ value }) => events.push(...value));
	const complete = new Promise((resolve) => session.once("Tracing.tracingComplete", resolve));
	await session.send("Tracing.start", { transferMode: "ReportEvents", traceConfig: { includedCategories: CATEGORIES } });
	await page.evaluate(() => window.__agentSession.feedFrames(100, 100));
	await session.send("Tracing.end");
	await complete;
	await page.close();
	return analyze(events);
}

async function profiled(browser, port, extra, css) {
	const page = await openPane(browser, port, extra, css);
	const session = await page.context().newCDPSession(page);
	await session.send("Profiler.enable");
	await session.send("Profiler.setSamplingInterval", { interval: 100 });
	await session.send("Profiler.start");
	await page.evaluate(() => window.__agentSession.feedFrames(100, 100));
	const { profile } = await session.send("Profiler.stop");
	await page.close();
	await mkdir(resultsDir, { recursive: true });
	const file = path.join(resultsDir, `visible10-${Date.now()}.cpuprofile`);
	await writeFile(file, JSON.stringify(profile));
	return { file, top: selfTimeTop(profile, 15) };
}

const args = parseArgs(process.argv.slice(2));
const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await chromium.launch({ headless: true });
	const report = {
		measuredAt: new Date().toISOString(),
		css: args.css,
		trace: { solo: await traced(browser, port, 0, args.css), visible10: await traced(browser, port, 9, args.css) },
		profile: { visible10: await profiled(browser, port, 9, args.css) },
	};
	process.stdout.write(`${JSON.stringify(report)}\n`);
} finally {
	await browser?.close();
	await server.close();
}
```

- [x] **Step 6: `repaint-loop.mjs`**

Create `$T/bench/agent-session/repaint-loop.mjs`:

```js
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, webkit } from "playwright";
import { createServer } from "vite";

const benchDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const configFile = path.join(benchDir, "vite.config.ts");

function parseArgs(argv) {
	const out = { browser: "chromium", css: "", frames: 100 };
	for (let index = 0; index < argv.length; index += 1) {
		if (argv[index] === "--browser") out.browser = argv[++index];
		else if (argv[index] === "--css") out.css = argv[++index];
		else if (argv[index] === "--frames") out.frames = Number(argv[++index]);
		else throw new Error(`unsupported argument ${argv[index]}`);
	}
	if (out.browser !== "chromium" && out.browser !== "webkit") throw new Error(`unsupported browser ${out.browser}`);
	return out;
}

async function loop(browser, port, extra, args) {
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=claude-spinner-10s${args.css ? `&css=${encodeURIComponent(args.css)}` : ""}`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 60000 });
	if (extra > 0) await page.evaluate((count) => window.__agentSession.mountPanes(count, "visible"), extra);
	const result = await page.evaluate((frames) => window.__agentSession.repaintLoop(frames), args.frames);
	await page.close();
	return result;
}

const args = parseArgs(process.argv.slice(2));
const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await (args.browser === "webkit" ? webkit : chromium).launch({ headless: true });
	const report = {
		measuredAt: new Date().toISOString(),
		browser: args.browser,
		css: args.css,
		solo: await loop(browser, port, 0, args),
		visible10: await loop(browser, port, 9, args),
	};
	process.stdout.write(`${JSON.stringify(report)}\n`);
} catch (error) {
	process.stderr.write(`FAIL ${error instanceof Error ? error.stack : String(error)}\n`);
	process.exitCode = 1;
} finally {
	await browser?.close();
	await server.close();
}
```

- [x] **Step 7: Check the tooling reproduces the before-state**

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; cd $T && npm run build:ts && uptime && node $T/bench/agent-session/run.mjs --panes-only && node $T/bench/agent-session/layout-trace.mjs && node $T/bench/agent-session/repaint-loop.mjs --browser chromium && uptime
```

Expected: the `run.mjs` line's `panes.solo` reads `LayoutCount` 122 and `RecalcStyleCount` 222, and `panes.visible10` reads 1220–1221 and 2256–2257 (the harness change adds nothing to a run without `--css`). The trace reads `renderStepLayouts: 0` in both rows. `repaint-loop` prints `frames: 100` for both rows and a finite `totalMs`. If a layout or recalc count moves, Step 2 or 3 broke the page: fix before continuing.

- [x] **Step 8: The bench gates still pass with the harness change**

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; cd $T && npm run bench:agent:gate && npm run bench:agent:scroll && npm run bench:feel
```

Expected: `PASS agent-session gate`, the scroll gate green, `PASS feel gate: zero pixel diff`.

- [x] **Step 9: WebKit — ask, then try**

Ask the user in chat, and wait for a clear yes: "Task 1 needs Playwright's WebKit build to measure the engine the desktop app uses (WKWebView). May I run `npx playwright install webkit` in `packages/terminal`? It downloads Playwright's WebKit build from Playwright's CDN; the installer prints the size." Do not run it without that yes.

- If declined: WebKit is "not measured — install declined by the user" in the note. Skip the rest of this step and every WebKit step below.
- If approved:

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; cd $T && npx playwright install webkit && node $T/bench/agent-session/repaint-loop.mjs --browser webkit
```

Expected: one JSON line with `browser: "webkit"`, `frames: 100` in both rows. If it fails (the page never sets `__agentSessionReady`, wasm fails, a WebKit build does not exist for this macOS), record the exact error text in the note as the reason WebKit could not be measured. Then skip the WebKit steps below.

- [x] **Step 10: Capture the pixel before-state**

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; cd $T && git status --porcelain -- bench/agent-session/baselines && npm run bench:feel && for f in attributes=warp cursorContrast cursorHollowUnfocused graphemes=false graphemes=false,widthCache=false widthCache=false; do npm run bench:feel -- --feature "$f" || exit 1; done && for a in hover hint redact; do npm run bench:affordances -- --action "$a" || exit 1; done; git status --porcelain -- bench/agent-session/baselines
```

The first `git status` must be empty; if it is not, another session has baseline changes in flight, so stop and report. The last `git status` says whether the committed `feature-*`/`affordance-*` PNGs reproduce on the unmodified tree: empty means they do. Record the answer in the note either way, listing any file that differs.

Copy the regenerated set to the scratchpad; it is the reference for every later pixel gate:

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; S=<your scratchpad>; rm -rf "$S/pixels-before" && mkdir -p "$S/pixels-before" && cd $T/bench/agent-session/baselines && find . \( -path './*/feature-*/offset-*.png' -o -path './*/affordance-*/*.png' \) -print | tar -cf - -T - | tar -xf - -C "$S/pixels-before" && find "$S/pixels-before" -name '*.png' | wc -l
```

Then, **only if** the last `git status` listed files, restore the committed ones. They are this run's own generated output, so run `git -C /Users/omaraly/development/AI/Operator diff --name-only -- packages/terminal/bench/agent-session/baselines` first, read the list, and `git checkout -- <each listed path>`. Never commit regenerated PNGs.

- [x] **Step 11: CHANGELOG and commit**

Add under `## Unreleased` in `$T/CHANGELOG.md`, as the first bullet:

```markdown
- bench: the agent-session page takes `?css=<stylesheet>` and exposes `repaintLoop(frames)` (a synchronous feed-and-repaint loop timed with `performance.now()`, so it also runs in WebKit); `run.mjs` takes `--css` and `--profile-row`; `layout-trace.mjs` counts forced and render-step layouts per frame from a Chromium trace; `repaint-loop.mjs --browser chromium|webkit` runs the loop. Measurement tooling only; nothing in `ts/` changes.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/bench/agent-session/main.ts packages/terminal/bench/agent-session/run.mjs packages/terminal/bench/agent-session/layout-trace.mjs packages/terminal/bench/agent-session/repaint-loop.mjs packages/terminal/CHANGELOG.md && git commit -m "bench(terminal): css injection, repaint loop and layout trace for the containment measurement

Co-Authored-By: <the harness trailer>"
```

---

### Task 2: `contain: layout` on `.terminal-row`

**Files (only if the step is kept):**
- Modify: `packages/terminal/ts/renderer-dom/src/styles.css:295-300` and the same rule in `styles.ts` (`.terminal-row {`, currently `styles.ts:295-300`)
- Test: `packages/terminal/ts/renderer-dom/src/styles-parity.test.ts`
- Modify: `packages/terminal/CHANGELOG.md`
- Always: `packages/terminal/bench/agent-session/baselines/pane-cost/<today>-containment-row-*` run files

**Interfaces:**
- Consumes: Task 1's `run.mjs --css`, `layout-trace.mjs --css`, `repaint-loop.mjs --css`, `$S/pixels-before/`.
- Produces: either `.terminal-row { …; contain: layout; }` in both style files, or nothing in source.

- [x] **Step 1: Interleaved A/B in Chromium, three pairs**

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; S=<your scratchpad>; D=$T/bench/agent-session/baselines/pane-cost; DAY=$(date +%F); cd $T && for i in 1 2 3; do echo "control$i $(date -u +%FT%TZ) $(uptime | sed 's/.*load averages: //')" >> $D/$DAY-containment-row-load.txt; node bench/agent-session/run.mjs --panes-only > $D/$DAY-containment-row-control-run$i.json || exit 1; echo "row$i $(date -u +%FT%TZ) $(uptime | sed 's/.*load averages: //')" >> $D/$DAY-containment-row-load.txt; node bench/agent-session/run.mjs --panes-only --css '.terminal-row{contain:layout}' > $D/$DAY-containment-row-after-run$i.json || exit 1; done; echo "end $(date -u +%FT%TZ) $(uptime | sed 's/.*load averages: //')" >> $D/$DAY-containment-row-load.txt
```

Before running, `ls $D` and make sure no `$DAY-containment-row-*` file exists; never overwrite a run file. Print the table:

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; D=$T/bench/agent-session/baselines/pane-cost; DAY=$(date +%F); node -e 'const fs=require("fs");for(const kind of ["control","after"])for(const i of [1,2,3]){const r=JSON.parse(fs.readFileSync(`'$D'/'$DAY'-containment-row-${kind}-run${i}.json`,"utf8").trim().split("\n")[0]).panes;for(const k of ["solo","visible10"]){const x=r[k];console.log(kind,i,k,x.TaskDuration.toFixed(3),x.LayoutDuration.toFixed(3),x.RecalcStyleDuration.toFixed(3),x.LayoutCount,x.RecalcStyleCount)}}'
```

- [x] **Step 2: One trace each way**

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; D=$T/bench/agent-session/baselines/pane-cost; DAY=$(date +%F); cd $T && node bench/agent-session/layout-trace.mjs > $D/$DAY-containment-row-control-trace.json && node bench/agent-session/layout-trace.mjs --css '.terminal-row{contain:layout}' > $D/$DAY-containment-row-after-trace.json
```

Record from each: `forcedLayoutMs`, `renderStepLayouts` (must stay 0), `medianDirtyObjects`, `medianTotalObjects`, and `getBoundingClientRect` self time from `profile.visible10.top`.

- [x] **Step 3: WebKit A/B, three pairs (skip if Task 1 Step 9 did not get WebKit running)**

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; D=$T/bench/agent-session/baselines/pane-cost; DAY=$(date +%F); cd $T && for i in 1 2 3; do node bench/agent-session/repaint-loop.mjs --browser webkit > $D/$DAY-containment-row-webkit-control-run$i.json || exit 1; node bench/agent-session/repaint-loop.mjs --browser webkit --css '.terminal-row{contain:layout}' > $D/$DAY-containment-row-webkit-after-run$i.json || exit 1; done
```

Run the same loop with `--browser chromium` into `…-row-chromium-loop-{control,after}-run$i.json`, so both engines have the same metric.

- [x] **Step 4: Judge**

Chromium, the rule from the request: **kept only if the median of the three `after` `visible10.LayoutDuration` readings is below the minimum of the three `control` readings from Step 1.** The control runs are the "before" for this rule because they ran in the same session under the same load. The planning-time before minimum (0.229 s, measurement note) is reported beside them. If the Step 1 control range lies outside the planning-time before range (0.229–0.234 s) by more than that range's own spread, write that the machine load differed, and quote the load log. Anything else is **no gain**, including an after median inside the control's range.

Also report, not gate: `visible10.TaskDuration`, the solo row, `LayoutCount`/`RecalcStyleCount` (containment must not add layouts), and the Step 2 trace figures.

WebKit (if measured): the same rule on `visible10.totalMs` of `repaint-loop` (after median below control minimum). Then decide:

| Chromium | WebKit | action |
|---|---|---|
| gain | gain, or not measured | keep: go to Step 5 |
| gain | after median **above** control maximum (a regression) | **stop and report to the user**; do not decide |
| no gain | gain | **stop and report to the user**; the app is WKWebView, so this is theirs to decide |
| no gain | no gain, or not measured | not kept: go to Step 12 |

- [ ] **Step 5 (kept only): Write the failing test**

Append inside the `describe("terminalStyles", …)` block of `$T/ts/renderer-dom/src/styles-parity.test.ts`:

```ts
	it("makes each row a layout boundary", () => {
		const start = terminalStyles.indexOf(".terminal-row {");
		const row = terminalStyles.slice(start, terminalStyles.indexOf("}", start));
		expect(row).toContain("contain: layout;");
	});
```

- [ ] **Step 6 (kept only): Run it and see it fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/styles-parity.test.ts
```

Expected: FAIL on "makes each row a layout boundary" (`expected … to contain 'contain: layout;'`).

- [ ] **Step 7 (kept only): Implement in both files**

In `$T/ts/renderer-dom/src/styles.css`, the `.terminal-row` rule becomes:

```css
.terminal-row {
	position: relative;
	z-index: 0;
	display: block;
	min-height: var(--terminal-line-height);
	contain: layout;
}
```

Make the identical edit to the `.terminal-row {` rule inside the template string in `$T/ts/renderer-dom/src/styles.ts`.

- [ ] **Step 8 (kept only): The guard test**

Append in the same `describe`:

```ts
	it("never uses a containment that clips paint or fixes size", () => {
		expect(terminalStyles).not.toMatch(/contain:[^;]*\b(paint|size|inline-size|strict|content)\b/);
		expect(terminalStyles).not.toContain("content-visibility");
	});
```

It passes on this tree. It is a guard for Review Focus 1, not a TDD step.

- [ ] **Step 9 (kept only): Unit tests pass**

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; for p in core renderer-dom react; do (cd $T/ts/$p && npx vitest run) || exit 1; done
```

Expected: all green, the two new tests and "is byte-identical to the published styles.css export" included.

- [ ] **Step 10 (kept only): Pixel gate on the built source**

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; S=<your scratchpad>; cd $T && npm run build:ts && npm run bench:feel && for f in attributes=warp cursorContrast cursorHollowUnfocused graphemes=false graphemes=false,widthCache=false widthCache=false; do npm run bench:feel -- --feature "$f" || exit 1; done && for a in hover hint redact; do npm run bench:affordances -- --action "$a" || exit 1; done; cd $T/bench/agent-session/baselines && find . \( -path './*/feature-*/offset-*.png' -o -path './*/affordance-*/*.png' \) -print | while read -r f; do cmp -s "$f" "$S/pixels-before/$f" || echo "DIFF $f"; done; echo "compared $(find . \( -path './*/feature-*/offset-*.png' -o -path './*/affordance-*/*.png' \) | wc -l) files"
```

Pass means `PASS feel gate: zero pixel diff`, no `DIFF` line, and the compared count equal to Task 1 Step 10's count. Then restore any tracked PNG the regeneration changed, as in Task 1 Step 10 (list with `git diff --name-only`, then `git checkout --` each). On any diff: revert Steps 5–8 (`git checkout -- ts/renderer-dom/src/styles.css ts/renderer-dom/src/styles.ts ts/renderer-dom/src/styles-parity.test.ts`, after `git diff` shows only this task's edits in them), rebuild, and record "reverted: pixel diff in <files>". Keep the `DIFF` files by copying them to `$S/pixels-row-diff/`, and describe what moved in the note.

- [ ] **Step 11 (kept only): CHANGELOG and commit**

Under `## Unreleased`, first bullet. Fill the numbers from Step 1 and Step 3:

```markdown
- renderer-dom: `.terminal-row` carries `contain: layout`. On the pane-cost harness (10 visible `claude-spinner-10s` panes, 100 frames) Layout time went from <control min–max> s to <after min–max> s (median <control median> → <after median>), interleaved in one session; WebKit repaint loop <control median> → <after median> ms, or "not measured: <reason>". Pixel-identical on every feel, feature and affordance screenshot. `paint`, `size`, `strict`, `content` and `content-visibility` are ruled out (TERMINAL.md §4.26).
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom/src/styles.css packages/terminal/ts/renderer-dom/src/styles.ts packages/terminal/ts/renderer-dom/src/styles-parity.test.ts packages/terminal/CHANGELOG.md packages/terminal/bench/agent-session/baselines/pane-cost/<each new containment-row file, listed by name> && git commit -m "perf(terminal): contain layout per transcript row

Co-Authored-By: <the harness trailer>"
```

- [x] **Step 12 (not kept): Commit the evidence only**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/bench/agent-session/baselines/pane-cost/<each new containment-row file, listed by name> && git commit -m "bench(terminal): row layout containment measured, no gain

Co-Authored-By: <the harness trailer>"
```

Skip Task 3.

---

### Task 3: `contain: layout` on `.terminal-block` — only if Task 2 was kept

Why it is safe to try, from planning finding 9: making `.terminal-block` a containing block changes no absolutely positioned element's containing block. The cursor's is its row (`cursor.ts:49`, row `position: relative`), and the block-glyph fill's is its glyph (styles.css:437-448). No overlay lives inside a block. What does change: the block becomes a stacking context (Review Focus 3), so its background paints at the z-index-0 positioned phase instead of the block-background phase. Planning expects no visible difference, because blocks do not overlap each other and every overlay in the scroller is at `z-index: 2`. The affordance screenshots decide.

**Files (only if kept):** `styles.css:93-113` and the matching `.terminal-block {` rule in `styles.ts`; `styles-parity.test.ts`; `CHANGELOG.md`. Always: the `<today>-containment-block-*` run files.

**Interfaces:**
- Consumes: Task 2's kept row containment (now in `dist/` after `npm run build:ts`), Task 1's tools, `$S/pixels-before/`.
- Produces: either `.terminal-block { …; contain: layout; }` in both files, or nothing in source.

- [ ] **Step 1: Interleaved A/B, three pairs.** Same commands as Task 2 Step 1, with file prefix `$DAY-containment-block-`: control is no `--css` (the tree now has row containment built in) and after is `--css '.terminal-block{contain:layout}'`. Print the same table.
- [ ] **Step 2: One trace each way.** Task 2 Step 2's commands, prefix `containment-block-`, with the after using `--css '.terminal-block{contain:layout}'`.
- [ ] **Step 3: WebKit A/B, three pairs, and the Chromium loop.** Task 2 Step 3's commands, prefix `containment-block-`, with the same `--css`.
- [ ] **Step 4: Judge** with Task 2 Step 4's rule and table. The control is this task's Step 1 control (row containment in place).
- [ ] **Step 5 (kept only): Write the failing test**

```ts
	it("makes each block a layout boundary", () => {
		const start = terminalStyles.indexOf(".terminal-block {");
		const block = terminalStyles.slice(start, terminalStyles.indexOf("}", start));
		expect(block).toContain("contain: layout;");
	});
```

- [ ] **Step 6 (kept only): Run it and see it fail**: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/styles-parity.test.ts`. Expected: FAIL on "makes each block a layout boundary".
- [ ] **Step 7 (kept only): Implement**: add `contain: layout;` as the last declaration of `.terminal-block` (after `white-space: pre;`, styles.css:112) in `styles.css`, and identically in `styles.ts`.
- [ ] **Step 8 (kept only): Unit tests**: Task 2 Step 9's loop. Expected: all green.
- [ ] **Step 9 (kept only): Pixel gate**: Task 2 Step 10's commands, same pass rule and same revert-on-diff procedure (diff copies to `$S/pixels-block-diff/`). The `affordance-*` comparison is the check for Review Focus 3.
- [ ] **Step 10 (kept only): CHANGELOG and commit**: a bullet in Task 2 Step 11's form for `.terminal-block` with this task's numbers. Commit message `perf(terminal): contain layout per block`, with an explicit path list.
- [ ] **Step 11 (not kept)**: commit the `containment-block-*` run files only, message `bench(terminal): block layout containment measured, no gain`.

---

### Task 4: Full gate on the final state

- [ ] **Step 1: Which state is final.** `git -C /Users/omaraly/development/AI/Operator diff f4d93ba68 HEAD -- packages/terminal/ts`. If it is empty, no CSS was kept. Run Step 2 anyway, since the bench harness changed, and report every Step 3 item as "not verified — no renderer change shipped, so there is nothing new to see in the app". Then go to Task 5.
- [ ] **Step 2: Bench and unit gates**

```bash
T=/Users/omaraly/development/AI/Operator/packages/terminal; cd $T && npm run build:ts && for p in core renderer-dom react; do (cd $T/ts/$p && npx vitest run) || exit 1; done && npm run bench:selection && npm run bench:agent:scroll && npm run bench:agent:gate && npm run bench:feel
```

Then the affordance and feature comparison exactly as in Task 2 Step 10 (all three actions, all six features, `cmp` against `$S/pixels-before/`, restore tracked PNGs afterwards). Expected: all green, `PASS agent-session gate`, zero pixel diff, no `DIFF` line. Paste each command's final line into the report.

- [ ] **Step 3: Real app (only if CSS was kept)**

Check for a running app first: `lsof -nP -iTCP:3002 -iTCP:5173 -sTCP:LISTEN`. If either port is held, do not start a second instance or kill anything. Record the `lsof` output, and report every item below as "not verified — dev ports busy".

Otherwise start the app with the `CLAUDE*` variables scrubbed (memory note "Scrub CLAUDE* env before running Operator dev"; `RUN_APP_COMMANDS.md`), from the repository root, in the background:

```bash
cd /Users/omaraly/development/AI/Operator && env $(env | grep -o '^CLAUDE[A-Z_0-9]*=' | sed 's/=$//; s/^/-u /') -u OPERATOR_DATA_DIR -u OPERATOR_RUN_FILE -u OPERATOR_PORT npm run tauri:dev
```

Before spawning anything, confirm that `ps eww <daemon pid>` shows zero `CLAUDE*` entries. Automation cannot click the Tauri window (memory note "Verify Operator desktop via daemon API and /mux"). Drive it with the computer-use tools if they are available, and capture evidence with `screencapture -l <window id>`. If they are not available, each item is "not verified — no way to drive the window". For each item, report "observed" with the screenshot path or "not verified" with the reason:

1. Split view with at least three streaming Claude Code panes side by side: every pane paints and nothing tears.
2. Scroll one pane to the bottom and keep scrolling (trackpad overscroll): it stops hard, with no vibration (the two CHANGELOG entries on `overscroll-behavior-y: none` and the elastic overscroll).
3. Drag a selection across several rows and across a block boundary: the fill is continuous, and the copy (`Cmd+C`) matches the text.
4. Hover a file path Claude printed: underline and pointing hand (TERMINAL.md §4.23).
5. The cursor in Claude Code's input box: it sits on the right cell, and nothing is clipped.
6. The find bar (`Cmd+F`): it opens above the transcript and highlights matches.
7. (Task 3 kept only) A shell pane scrolled into a long command's output: the pinned header is drawn above the rows (Review Focus 5).

Stop the app you started when done.

---

### Task 5: Record

**Files:**
- Modify: `docs/superpowers/specs/2026-09-23-layout-containment-measurement.md` (append "After")
- Modify: `TERMINAL.md` (§4, after §4.25 at `TERMINAL.md:783-806`; §5 line reference at `:1074`)
- Modify (no-gain outcome only): `packages/terminal/ts/renderer-dom/src/styles-parity.test.ts` (the guard test from Task 2 Step 8)

- [ ] **Step 1: "After" section of the measurement note.** Append `## After (<date>)` with: the tree (commit), the load log excerpts, and for each of Task 2 and Task 3 a table of control against after per run (TaskDuration, Layout, RecalcStyle, layout and recalc counts for solo and 10 visible), the trace figures, the WebKit loop figures or "WebKit: not measured — <reason from Task 1 Step 9>", and the verdict ("kept" / "not kept: no gain" / "reverted: pixel diff in …" / "stopped: reported to the user because …"). Add the Task 1 Step 10 answer (whether the committed feature and affordance PNGs reproduce on the unmodified tree) and the Task 4 results item by item. Every number cites its run file.

- [ ] **Step 2: TERMINAL.md §4.26.** Insert after §4.25, before `## 5.`. Use the variant that matches the outcome and fill every `<…>` from the note:

Kept (Task 2 and/or Task 3):

```markdown
### 4.26 Layout containment per row (and block) — measured, not a bug
- What: `.terminal-row` <and `.terminal-block`> carry `contain: layout`
  (`ts/renderer-dom/src/styles.css`, mirrored in `styles.ts`). The scroller
  was already `contain: strict`, inline, from `mount()`
  (`dom-block-renderer.ts:161`). `.terminal-list` gets nothing: the scroller
  bounds it one level up, and its height is what `scrollHeight` measures.
- Why: every visible pane pays one forced layout per output frame, at the
  pinned-header `getBoundingClientRect` (`dom-block-renderer.ts:1149`); the
  render step lays out nothing (trace, 0 render-step layouts). Containment
  cut the 10-visible Layout time from <control range> to <after range> s
  (<date>, `docs/superpowers/specs/2026-09-23-layout-containment-measurement.md`
  "After"); WebKit <result>.
- Ruled out, do not add: `paint` (clips at the box and saves no layout; a
  row's cursor, underlines and fallback glyphs may overflow it); `size`,
  `strict`, `content`, `content-visibility: auto` (a row's height is not
  provably one line: text past its last run sits in the row's own line box,
  `row-builder.ts:116-119`, and blocks are content-sized; the virtualiser
  already mounts only visible rows, so there is nothing for
  `content-visibility` to skip); `style` (no counters or quotes in the
  stylesheet, so it scopes nothing).
- Guards: `styles-parity.test.ts` "makes each row a layout boundary"<, "makes
  each block a layout boundary">, "never uses a containment that clips paint
  or fixes size"; `bench:feel` and the feature/affordance byte comparisons in
  the plan (`docs/superpowers/plans/2026-09-23-terminal-layout-containment.md`).
```

Not kept:

```markdown
### 4.26 Layout containment — measured, no gain, not applied
- What was tried: `contain: layout` on `.terminal-row`<, then
  `.terminal-block`>, A/B in one session against a control
  (`bench/agent-session/run.mjs --panes-only --css …`). 10-visible Layout:
  control <range>, with containment <range> s — inside noise (<date>,
  `docs/superpowers/specs/2026-09-23-layout-containment-measurement.md`
  "After"); WebKit <result>. Nothing was changed.
- Why it cannot help much here: the scroller is already `contain: strict`
  (`dom-block-renderer.ts:161`), so a frame's layout never leaves the pane,
  and each layout already has a median of 142 dirty objects out of 274–370
  (trace `beginData`); those are new row nodes that need layout anyway. There
  is also no second layout to remove: 0 render-step layouts per frame.
- Ruled out, do not add: `paint` (clips at the box and saves no layout);
  `size`, `strict`, `content`, `content-visibility: auto` (a row's height is
  not provably one line: text past its last run sits in the row's own line
  box, `row-builder.ts:116-119`; the virtualiser already mounts only visible
  rows); `style` (nothing to scope).
- Guard: `styles-parity.test.ts` "never uses a containment that clips paint
  or fixes size".
```

- [ ] **Step 3: Correct the stale line in §5.** In TERMINAL.md §5 "What a parked pane still costs", the text `(now \`dom-block-renderer.ts:1141\`, the pinned-header \`getBoundingClientRect\`)` is false. Change `:1141` to `:1149`, after checking with `grep -n "getBoundingClientRect" /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` that `:1149` is still the line.

- [ ] **Step 4 (no-gain outcome only): Land the guard test.** Add Task 2 Step 8's `it("never uses a containment that clips paint or fixes size", …)` to `styles-parity.test.ts`. Run `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/styles-parity.test.ts`. Expected: PASS. It pins the ruled-out values the §4.26 entry names.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add docs/superpowers/specs/2026-09-23-layout-containment-measurement.md TERMINAL.md <packages/terminal/ts/renderer-dom/src/styles-parity.test.ts, only in the no-gain outcome> && git commit -m "docs(terminal): layout containment measured — <kept on rows|kept on rows and blocks|no gain>

Co-Authored-By: <the harness trailer>"
```
