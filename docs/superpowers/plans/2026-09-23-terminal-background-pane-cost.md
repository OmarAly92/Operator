# Terminal Background Pane Cost Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A retained terminal pane the user is not looking at keeps its model current and keeps reporting finished blocks, but stops painting DOM — and a hidden (minimised) Operator window keeps draining and notifying instead of freezing.

**Architecture:** `DomBlockRenderer` gets a host-driven visibility seam (`setVisible(boolean | null)`). Every frame still drains and ticks the core; block-finished detection moves into its own method that runs on painting and non-painting frames alike; the DOM repaint, overlays and predictive echo run only while the host says the pane is visible, with one synchronous catch-up paint (a full rebuild) when it becomes visible again. `LineEditor` gets the same seam. While `document.visibilityState === "hidden"` (where `requestAnimationFrame` never fires) the renderer schedules its frames on a timer instead. Operator drives the seam from `TerminalPane`'s activation phases: every phase except `"parked"` paints.

**Tech Stack:** TypeScript, vt-core wasm (`@operator/terminal-core`), Vitest + jsdom, React 19 (`TerminalSurface`, `TerminalPane`), Playwright + CDP (bench).

**Spec:** [`docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md`](../specs/2026-09-23-background-pane-cost-measurement.md) — the measurement this plan argues from. Read it before Task 1. The baseline table it feeds is in [`docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`](../specs/2026-09-19-agent-tui-experience-design.md) ("The table").

## Why this plan has this shape (from the measurement)

- A parked pane costs what a visible one does: +122 forced layouts and +222 style recalcs per pane per 100 output frames, ~0.065–0.088 s of main thread per pane per 10 s against ~0.081 s for a visible one. `visibility: hidden` saves nothing. So the paint gate is worth building.
- Of the paint-loop time in the 1+9 profile, `repaint` is 615 ms inclusive; `drain` 74 ms; `LineEditor.ingestHistory` 73 ms. So the gate must skip `repaint`, keep `drain`, and also idle the `LineEditor` (Task 5), or ~half of what remains per parked pane stays.
- WKWebView fires **zero** animation frames while the window is minimised or app-hidden, and throttles `setTimeout` to ~1/s. Today that stops draining and block-finished detection for every pane, so the notification feature is silent while the window is hidden. The hidden-document path (Task 7) is required, not optional.
- Acks to the pty-host go out on receipt, not on parse (`useTerminalSession.ts:590-598`), so nothing here changes flow control.

## Global Constraints

- Read `TERMINAL.md` end to end and `AGENTS.md` before Task 1.
- `packages/terminal` stays product-independent (TERMINAL.md §3.1): no Operator phase names, paths or concepts inside it. The package only learns "visible: true/false/unset".
- **No comments in new code** (the user's global rule), except reference citations naming a repository and path. Do not add explanatory comments.
- Do not change what a **visible** pane paints: `npm run bench:feel` must show zero pixel diff after every task. No task re-records feel baselines.
- Do not change the resize debounce (`RESIZE_DEBOUNCE_MS`), the feed budget (`FEED_BUDGET_MS = 12`, `terminal-core.ts:42`), `PAINT_INTERVAL_MS`, or any `RendererFeatures` default. The one deliberate exception to the 12 ms budget is Task 7's hidden-document tick, which passes its own `HIDDEN_DRAIN_MS` to `drain(deadlineMs)` (`terminal-core.ts:136`); `FEED_BUDGET_MS` itself and every animation-frame drain stay at 12 ms.
- One `packages/terminal/CHANGELOG.md` entry under "Unreleased" per behaviour change.
- The checkout is shared with other sessions: **never `git stash`, never `git commit -a`**; commit with an explicit path list. Commits go to `development`, message ends with the `Co-Authored-By` trailer the harness gives you.
- Every command uses absolute paths (TERMINAL.md §6).
- The app runs the built `dist/`, not source: real-app checks need `npm run build:ts` in `packages/terminal` and a `tauri:dev` restart with the scrubbed env (memory notes "Rebuild terminal dist before testing renderer fixes", "Scrub CLAUDE* env before running Operator dev").
- TDD: every new-behaviour test is run and **seen failing** before the implementation. Characterization tests (Task 2) pass before and after — say so in the step.

## Review Focus

1. **A pane shown while its output is mid-sync-block.** A parked pane revealed while a DEC 2026 block is open must not paint a half frame; the catch-up paint must see the same model the frame loop would. Pinned in Task 4 ("reveal during an open sync block paints the last complete frame").
2. **Park → reveal within one frame.** Switching A→B→A faster than a frame: `setVisible(false)` then `setVisible(true)` before any frame ran must still paint once and not leave `catchUp` set. Pinned in Task 4.
3. **Window hidden while a pane is parked, then shown while it is still parked.** The timer path must not paint the parked pane when the document becomes visible. Pinned in Task 7.
4. **A block that finishes while the pane is parked AND the alternate screen is up.** Today's deferral (reported on the first primary-screen frame) must survive the move, parked or not. Pinned in Task 2 and re-checked in Task 4.
5. **Dispose while hidden.** A renderer disposed while the hidden timer is armed must not tick a disposed core. Pinned in Task 7.

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `packages/terminal/bench/agent-session/run.mjs`, `main.ts` | pane-cost rows (`--panes-only`, `--profile`), parked panes | committed with the measurement; 4, 8 |
| `packages/terminal/bench/adapters/dom.ts` | `DomBenchmarkRenderer.setVisible` for parked bench panes | 4, 5 |
| `packages/terminal/ts/renderer-dom/src/block-finished.ts` | `finishedBlocks`, `rendererVisible`, `documentHidden` | 3 |
| `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` | detection method, visibility seam, paint gate, hidden timer | 2, 3, 4, 7 |
| `packages/terminal/ts/renderer-dom/src/dom-block-renderer.visibility.test.ts` (new) | every visibility / parked / hidden test | 2, 3, 4, 7 |
| `packages/terminal/ts/editor/src/line-editor.ts` + `line-editor.test.ts` | `LineEditor.setVisible` | 5 |
| `packages/terminal/ts/react/src/TerminalSurface.tsx` + `TerminalSurface.test.tsx` | `visible` prop → renderer + editor | 3, 5 |
| `frontend/src/renderer/components/BlockTerminal.tsx` + test | `visible` prop passthrough | 6 |
| `frontend/src/renderer/components/TerminalPane.tsx` + test | `isRendered` from the activation phase | 6 |
| `packages/terminal/CHANGELOG.md`, `TERMINAL.md`, the spec table | docs | 2–8 |

---

### Task 1: Pane-cost measurement (already committed)

The bench rows, the WKWebView probe (`scripts/probe-wkwebview-hidden.swift`), the raw runs (`packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-23-before-run{1,2,3}.json`) and the measurement note were committed with this plan. Nothing to do except confirm they are on `development`:

- [ ] **Step 1: Confirm**

Run: `git -C /Users/omaraly/development/AI/Operator log --oneline -3 -- packages/terminal/bench/agent-session/run.mjs docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md`
Expected: the `bench(terminal): measure parked-pane cost …` commit.

---

### Task 2: Block-finished detection as its own step

Behaviour-preserving extraction: detection leaves the body of `repaint` for a method both painting and (later) non-painting frames call. Its tests are **characterization tests** — they pass before and after this task, and pin the semantics Task 4 must keep.

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:932-942` (the detection block in `repaint`)
- Create: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.visibility.test.ts`
- Modify: `packages/terminal/CHANGELOG.md` — none (no behaviour change)

**Interfaces:**
- Produces: `private detectFinishedBlocks(snapshot: TerminalSnapshot): BlockView[]` — decodes blocks, fires `onBlockFinished` listeners for blocks that left `"running"`, updates `blockStates`, returns the decoded blocks. Skips (returns `[]` and leaves `blockStates` untouched) when `snapshot.altScreen !== null`, exactly like today's early return at `:898-923`.
- Produces: `private shownToUser(): boolean` — today `this.container !== null && rendererVisible(this.container)`; Task 3 changes its body.

- [ ] **Step 1: Write the test file with its harness and the characterization tests**

```ts
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import {
	createTerminalCore,
	initTerminalCore,
	type FontConfig,
	type TerminalCore,
} from "@operator/terminal-core";
import { DomBlockRenderer, warpDarkTheme } from "./index";
import type { BlockFinishedEvent } from "./block-finished";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
const fixture = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "bench", "agent-session", "fixtures", "claude-spinner-10s", "recording");

const font: FontConfig = { family: "ui-monospace, monospace", sizePx: 14, lineHeight: 1.2, weight: 400, letterSpacingPx: 0, ligatures: false };

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

afterEach(() => {
	vi.restoreAllMocks();
	vi.unstubAllGlobals();
	document.body.replaceChildren();
});

function text(value: string): Uint8Array {
	return new TextEncoder().encode(value);
}

function flushRepaint(): Promise<void> {
	return new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
}

function scrollable(): HTMLElement {
	const container = document.createElement("div");
	Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
	Object.defineProperty(container, "scrollHeight", { value: 100_000, configurable: true });
	Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
	return container;
}

function parkingLot(): HTMLElement {
	const lot = document.createElement("div");
	lot.setAttribute("aria-hidden", "true");
	lot.style.visibility = "hidden";
	document.body.append(lot);
	return lot;
}

function park(container: HTMLElement, lot: HTMLElement): void {
	container.setAttribute("inert", "");
	container.setAttribute("aria-hidden", "true");
	container.style.pointerEvents = "none";
	container.style.visibility = "hidden";
	lot.append(container);
}

function mounted(columns = 40): { core: TerminalCore; host: HTMLElement; renderer: DomBlockRenderer; events: BlockFinishedEvent[] } {
	const core = createTerminalCore({ columns, scrollback: 1000, rows: 5 });
	const host = scrollable();
	document.body.append(host);
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(warpDarkTheme);
	renderer.setFont(font);
	const events: BlockFinishedEvent[] = [];
	renderer.onBlockFinished((event) => events.push(event));
	return { core, host, renderer, events };
}

const OPEN_BLOCK = "\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07out\r\n";
const CLOSE_BLOCK = "\x1b]133;D;0\x07";

describe("block-finished detection", () => {
	it("reports a block that finishes in a parked container as not visible", async () => {
		const { core, host, renderer, events } = mounted();
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		park(host, parkingLot());
		core.enqueue(text(CLOSE_BLOCK));
		await flushRepaint();
		await flushRepaint();
		expect(events).toHaveLength(1);
		expect(events[0]).toMatchObject({ exitCode: 0, visible: false });
		renderer.dispose();
	});

	it("reports a block that finishes under the alternate screen once the primary screen returns, not before", async () => {
		const { core, renderer, events } = mounted();
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		core.feed(text(`\x1b[?1049h${CLOSE_BLOCK}`));
		await flushRepaint();
		await flushRepaint();
		expect(events).toHaveLength(0);
		core.feed(text("\x1b[?1049l"));
		await flushRepaint();
		expect(events).toHaveLength(1);
		renderer.dispose();
	});

	it("reports each finished block once", async () => {
		const { core, renderer, events } = mounted();
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		core.feed(text(CLOSE_BLOCK));
		await flushRepaint();
		core.feed(text("more\r\n"));
		await flushRepaint();
		expect(events).toHaveLength(1);
		renderer.dispose();
	});
});
```

- [ ] **Step 2: Run them on today's code — they must PASS (characterization)**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/dom-block-renderer.visibility.test.ts`
Expected: 3 passed. If the alternate-screen test fails, stop: the semantics recorded in the measurement note ("reported late, not dropped") are wrong, and the plan's assumption must be revisited with the user before continuing.

- [ ] **Step 3: Extract the method**

In `dom-block-renderer.ts`, add the `TerminalSnapshot` and `BlockView` type imports from `@operator/terminal-core` if not already imported, then add:

```ts
	private shownToUser(): boolean {
		return this.container !== null && rendererVisible(this.container);
	}

	private detectFinishedBlocks(snapshot: TerminalSnapshot): BlockView[] {
		if (snapshot.altScreen !== null) return [];
		const blocks = decodeBlocks(snapshot);
		const finished = finishedBlocks(this.blockStates, blocks);
		this.blockStates = new Map(blocks.map((block) => [block.id, block.state] as const));
		if (finished.length === 0) return blocks;
		const visible = this.shownToUser();
		for (const block of finished) {
			for (const listener of [...this.blockFinishedListeners]) {
				listener({ id: block.id, exitCode: block.exitCode, durationMs: block.durationMs, visible });
			}
		}
		return blocks;
	}
```

and replace `repaint`'s block at `:932-942` (from `const blocks = decodeBlocks(snapshot);` through the closing brace of `if (finished.length > 0) { … }`) with:

```ts
		const blocks = this.detectFinishedBlocks(snapshot);
```

- [ ] **Step 4: Run the new file and the renderer suite**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run`
Expected: all pass, including `dom-block-renderer.test.ts` "fires onBlockFinished once when a running block finishes, with the pane's visibility".

- [ ] **Step 5: TERMINAL.md §6 verification for renderer-dom**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts
for p in core renderer-dom react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel && npm run bench:selection
```
Expected: all green; `PASS feel gate: zero pixel diff`.

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts packages/terminal/ts/renderer-dom/src/dom-block-renderer.visibility.test.ts
git commit -m "refactor(terminal): block-finished detection is its own renderer step"
```

---

### Task 3: The visibility seam

The host states whether the pane is shown; the package only uses it for the `visible` flag of `onBlockFinished` in this task (the paint gate is Task 4). Unset (`null`, the default) keeps today's `rendererVisible(container)` fallback. A hidden document always reports `visible: false`.

`rendererVisible` is deliberately **not** used as a paint gate for hosts that set nothing: it forces a layout (`getClientRects`) and returns false in jsdom and for any unlaid-out container, so gating paint on it would reintroduce the cost this plan removes and stop hosts that never opted in from painting.

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/block-finished.ts:9-13`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` (field, `setVisible`, `shownToUser`)
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx:43-75` (prop), after the geometry effect ending at `:283` (effect)
- Test: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.visibility.test.ts`, `packages/terminal/ts/react/src/TerminalSurface.test.tsx`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Produces: `export function documentHidden(): boolean` in `block-finished.ts` (re-exported from the package index only if `rendererVisible` is; keep exports symmetric).
- Produces: `DomBlockRenderer.setVisible(visible: boolean | null): void` and `DomBlockRenderer.visibility(): boolean | null`.
- Produces: `TerminalSurfaceProps.visible?: boolean` — `undefined` maps to `setVisible(null)`.

- [ ] **Step 1: Write the failing tests**

Append to `dom-block-renderer.visibility.test.ts`:

```ts
function setDocumentVisibility(state: DocumentVisibilityState): void {
	Object.defineProperty(document, "visibilityState", { configurable: true, get: () => state });
	document.dispatchEvent(new Event("visibilitychange"));
}

describe("visibility seam", () => {
	afterEach(() => setDocumentVisibility("visible"));

	it("reports the host's fact instead of guessing from the DOM", async () => {
		const { core, renderer, events } = mounted();
		renderer.setVisible(true);
		expect(renderer.visibility()).toBe(true);
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		core.feed(text(CLOSE_BLOCK));
		await flushRepaint();
		expect(events[0]).toMatchObject({ visible: true });
		renderer.dispose();
	});

	it("reports not visible when the host says so even if the DOM looks visible", async () => {
		const { core, host, renderer, events } = mounted();
		host.getClientRects = () => [{}] as unknown as DOMRectList;
		renderer.setVisible(false);
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		core.enqueue(text(CLOSE_BLOCK));
		await flushRepaint();
		await flushRepaint();
		expect(events[0]).toMatchObject({ visible: false });
		renderer.dispose();
	});

	it("falls back to the DOM when the host sets nothing", async () => {
		const { core, host, renderer, events } = mounted();
		host.getClientRects = () => [{}] as unknown as DOMRectList;
		renderer.setVisible(true);
		renderer.setVisible(null);
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		core.feed(text(CLOSE_BLOCK));
		await flushRepaint();
		expect(events[0]).toMatchObject({ visible: true });
		renderer.dispose();
	});

	it("reports not visible while the document is hidden, whatever the host says", () => {
		const { core, renderer, events } = mounted();
		renderer.setVisible(true);
		core.feed(text(OPEN_BLOCK));
		setDocumentVisibility("hidden");
		core.feed(text(CLOSE_BLOCK));
		(renderer as unknown as { detectFinishedBlocks(s: unknown): unknown }).detectFinishedBlocks(core.snapshot());
		expect(events.at(-1)).toMatchObject({ visible: false });
		renderer.dispose();
	});
});
```

jsdom does not reflect the `inert` property to the attribute (checked: `el.inert = true` leaves `closest("[inert]")` null), so tests set the attribute; real browsers reflect it, which is what `TerminalPane.setTerminalPhase` relies on.

The last test calls the private method directly because rAF never fires in a hidden document and the timer path does not exist until Task 7; Task 7 replaces this call with the real path.

Append to `packages/terminal/ts/react/src/TerminalSurface.test.tsx`, reusing that file's existing core/render helpers (read the top of the file for their names — do not add a second harness):

```tsx
it("hands the host's visibility to the renderer", () => {
	const spy = vi.spyOn(DomBlockRenderer.prototype, "setVisible");
	const { rerender } = renderSurface({ visible: false });
	expect(spy).toHaveBeenLastCalledWith(false);
	rerender(surfaceElement({ visible: true }));
	expect(spy).toHaveBeenLastCalledWith(true);
	rerender(surfaceElement({}));
	expect(spy).toHaveBeenLastCalledWith(null);
});
```

(`renderSurface` / `surfaceElement` stand for whatever the file's render helper and element builder are called; if it has only a render helper, render twice with `rerender(<TerminalSurface {...props} visible />)`.)

- [ ] **Step 2: Run and see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/dom-block-renderer.visibility.test.ts`
Expected: FAIL — `renderer.setVisible is not a function`.
Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/react && npx vitest run src/TerminalSurface.test.tsx -t "visibility"`
Expected: FAIL — spy never called.

- [ ] **Step 3: Implement**

`block-finished.ts`:

```ts
export function documentHidden(): boolean {
	return typeof document !== "undefined" && document.visibilityState === "hidden";
}

export function rendererVisible(container: HTMLElement): boolean {
	if (!container.isConnected || container.closest("[inert]") !== null) return false;
	if (documentHidden()) return false;
	return container.getClientRects().length > 0;
}
```

`dom-block-renderer.ts` — field beside `focused` (`:119`):

```ts
	private hostVisible: boolean | null = null;
```

methods beside `setFocused` (`:213`):

```ts
	setVisible(visible: boolean | null): void {
		this.hostVisible = visible;
	}

	visibility(): boolean | null {
		return this.hostVisible;
	}
```

replace `shownToUser`:

```ts
	private shownToUser(): boolean {
		if (this.hostVisible !== null) return this.hostVisible && !documentHidden();
		return this.container !== null && rendererVisible(this.container);
	}
```

import `documentHidden` beside `rendererVisible` at `:17`. In `dispose()` add `this.hostVisible = null;`.

`TerminalSurface.tsx` — add to `TerminalSurfaceProps` after `focusToken?: number;`:

```ts
	visible?: boolean;
```

destructure `visible` in the component signature, and add this effect **directly after** the geometry/refit effect that ends `}, [core, onGeometry, refitToken]);` (so a pane shown into a new slot is refitted before Task 4's catch-up paint):

```ts
	useLayoutEffect(() => {
		rendererRef.current?.setVisible(visible ?? null);
	}, [visible]);
```

- [ ] **Step 4: Run and see them pass**

Run the two commands from Step 2. Expected: PASS.

- [ ] **Step 5: CHANGELOG**

Under "Unreleased" in `packages/terminal/CHANGELOG.md`:

```md
- renderer-dom/react: `DomBlockRenderer.setVisible(boolean | null)` and `TerminalSurface`'s `visible` prop let a host state whether a pane is shown. `onBlockFinished`'s `visible` now follows that fact when set (and is always false while the document is hidden); unset keeps the `rendererVisible` DOM check.
```

- [ ] **Step 6: TERMINAL.md §6 verification (renderer-dom, react)** — same block as Task 2 Step 5. Expected: all green, zero pixel diff.

- [ ] **Step 7: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add packages/terminal/ts/renderer-dom/src/block-finished.ts packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts packages/terminal/ts/renderer-dom/src/dom-block-renderer.visibility.test.ts packages/terminal/ts/react/src/TerminalSurface.tsx packages/terminal/ts/react/src/TerminalSurface.test.tsx packages/terminal/CHANGELOG.md
git commit -m "feat(terminal): a host-stated visibility seam on the renderer"
```

---

### Task 4: The paint gate

While `hostVisible === false`: every frame still drains and ticks (Plan A's budget untouched), takes a snapshot, runs block detection and discards the wasm dirty set; it touches no DOM. Overlays and predictive echo are idle. On `setVisible(true)` after hidden frames, one **synchronous** full-rebuild paint runs inside the call, so the first visible browser frame shows the current tail (TerminalPane reveals in layout effects before the next animation frame — see Task 6).

Decision on dirty rows: while hidden each frame calls `core.takeDirty()` and discards it (bounded: the wasm set never outlives one frame) and sets `catchUp`; the catch-up paint sets `rebuildAll`, which clears the element pool and `pooledDirty` and rebuilds the visible window from scratch (`:955-961`) — the same path `setFont`/`setFeatures` use, so it paints what an incremental paint would. Replaying an accumulated dirty set was rejected: its size is unbounded for a long-parked pane, and `rebuildAll` costs one ordinary first paint of the window.

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` — `repaintOnFrame` (`:826-840`), `setVisible`, `linkChanged` (`:461-466`), `reconcilePredictions` (`:649-660`), `noteReceived` (`:588-595`), `dispose`
- Modify: `packages/terminal/bench/adapters/dom.ts`, `packages/terminal/bench/agent-session/main.ts` (`park()` calls `setVisible(false)`; parked-mutation counter)
- Test: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.visibility.test.ts`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `setVisible`, `shownToUser`, `detectFinishedBlocks` (Tasks 2–3).
- Produces: `private painting(): boolean` (`this.hostVisible !== false`), `private settleHidden(): void`, `private catchUp: boolean`. Task 7 reuses `settleHidden`.
- Produces (bench): `DomBenchmarkRenderer.setVisible(visible: boolean): void`; `window.__agentSession.parkedMutations(): number`.

- [ ] **Step 1: Write the failing tests**

Append to `dom-block-renderer.visibility.test.ts`:

```ts
function observeMutations(root: HTMLElement): () => number {
	let count = 0;
	const observer = new MutationObserver((records) => {
		count += records.length;
	});
	observer.observe(root, { childList: true, subtree: true, attributes: true, characterData: true });
	return () => {
		count += observer.takeRecords().length;
		observer.disconnect();
		return count;
	};
}

async function spinnerChunks(): Promise<Uint8Array[]> {
	const bytes = new Uint8Array(await readFile(fixture));
	const chunks: Uint8Array[] = [];
	for (let at = 0; at < bytes.length; at += 4096) chunks.push(bytes.subarray(at, Math.min(bytes.length, at + 4096)));
	return chunks;
}

function rowTexts(host: HTMLElement): string[] {
	return [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].map((row) => row.textContent ?? "");
}

describe("paint gate", () => {
	it("keeps draining a hidden pane without touching its DOM", async () => {
		const { core, host, renderer } = mounted(120);
		core.feed(text("before\r\n"));
		await flushRepaint();
		renderer.setVisible(false);
		const generation = core.snapshot().generation;
		const stop = observeMutations(host);
		for (let index = 0; index < 20; index += 1) {
			core.enqueue(text(`line ${index}\r\n`));
			await flushRepaint();
		}
		expect(stop()).toBe(0);
		expect(core.hasBacklog()).toBe(false);
		expect(core.snapshot().generation).toBeGreaterThan(generation);
		renderer.dispose();
	});

	it("still reports a finished block from a hidden pane, as not visible", async () => {
		const { core, renderer, events } = mounted();
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		renderer.setVisible(false);
		core.enqueue(text(CLOSE_BLOCK));
		await flushRepaint();
		await flushRepaint();
		expect(events).toHaveLength(1);
		expect(events[0]).toMatchObject({ exitCode: 0, visible: false });
		renderer.dispose();
	});

	it("paints the current tail on the call that reveals it, stuck to the bottom", async () => {
		const { core, host, renderer } = mounted(120);
		core.feed(text("first screen\r\n"));
		await flushRepaint();
		renderer.setVisible(false);
		const hiddenRows = rowTexts(host);
		for (const chunk of await spinnerChunks()) {
			core.enqueue(chunk);
			await flushRepaint();
		}
		core.enqueue(text("\r\ntail marker\r\n"));
		await flushRepaint();
		expect(rowTexts(host)).toEqual(hiddenRows);
		renderer.setVisible(true);
		const shown = rowTexts(host);
		expect(shown.join("\n")).toContain("tail marker");
		expect(renderer.scrollAnchor()).toBeNull();
		renderer.dispose();
	});

	it("paints while the host says visible even when the container is hidden and inert", async () => {
		const { core, host, renderer } = mounted();
		host.setAttribute("inert", "");
		host.style.visibility = "hidden";
		renderer.setVisible(true);
		core.enqueue(text("preparing paint\r\n"));
		await flushRepaint();
		expect(rowTexts(host).join("\n")).toContain("preparing paint");
		renderer.dispose();
	});

	it("keeps the scroll anchor and the selection across park and reveal", async () => {
		const core = createTerminalCore({ columns: 20, limits: { rows: 1000, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 100; i += 1) core.feed(text(`line ${i}\r\n`));
		const host = scrollable();
		document.body.append(host);
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setFont(font);
		const rowHeight = renderer.measure().cellHeight;
		host.scrollTop = Math.round(rowHeight * 60);
		host.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const anchor = renderer.scrollAnchor()!;
		const blockId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId, row: anchor.stableRow, column: 0, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId, row: anchor.stableRow, column: 4, side: "right" });
		const selected = renderer.selectedText();
		renderer.setVisible(false);
		for (let i = 100; i < 140; i += 1) {
			core.enqueue(text(`line ${i}\r\n`));
			await flushRepaint();
		}
		renderer.setVisible(true);
		expect(renderer.scrollAnchor()).toEqual(anchor);
		expect(host.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)?.textContent).toBe(`line ${anchor.stableRow}`);
		expect(renderer.selectedText()).toBe(selected);
		renderer.dispose();
	});

	it("neither samples round trips nor paints predictions while hidden", async () => {
		const { core, host, renderer } = mounted();
		core.feed(text("$ "));
		await flushRepaint();
		renderer.setPredictiveEcho({ thresholdMs: 0 });
		renderer.noteRoundTrip(0, 50);
		expect(renderer.predictKey({ text: "a", ctrlKey: false, altKey: false, metaKey: false, isComposing: false }, performance.now())).toBe(true);
		const rtt = (renderer as unknown as { rtt: { median(): number | null } }).rtt;
		const medianBefore = rtt.median();
		renderer.noteSend(performance.now());
		renderer.setVisible(false);
		expect(renderer.predictionCount()).toBe(0);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
		core.enqueue(text("a"));
		await flushRepaint();
		expect(rtt.median()).toBe(medianBefore);
		renderer.dispose();
	});

	it("paints once when hidden and shown again before any frame ran", async () => {
		const { core, host, renderer } = mounted();
		core.feed(text("steady\r\n"));
		await flushRepaint();
		renderer.setVisible(false);
		core.enqueue(text("late\r\n"));
		renderer.setVisible(true);
		await flushRepaint();
		expect(rowTexts(host).join("\n")).toContain("late");
		renderer.dispose();
	});

	it("reveals mid sync block with the last complete frame, not half of the next", async () => {
		const { core, host, renderer } = mounted();
		core.feed(text("frame one\r\n"));
		await flushRepaint();
		renderer.setVisible(false);
		core.enqueue(text("\x1b[?2026hhalf of frame two"));
		await flushRepaint();
		renderer.setVisible(true);
		const shown = rowTexts(host).join("\n");
		expect(shown).toContain("frame one");
		expect(shown).not.toContain("half of frame two");
		renderer.dispose();
	});
});
```

Also add the find-state test to `packages/terminal/ts/renderer-dom/src/find-bar.test.ts`, inside its `describe("find-bar")`, using that file's `makeMountedCore`, `makeBarHost`, `flushFrames`:

```ts
	it("keeps the query and the count across park and reveal", async () => {
		const { core, host, renderer } = makeMountedCore();
		unmount = () => renderer.dispose();
		const bar = createFindBar({ core, renderer: renderer as unknown as BlockRenderer, host: makeBarHost(renderer), strings: defaultStrings });
		bar.mount(host);
		bar.open();
		const input = host.querySelector<HTMLInputElement>("input[data-terminal-find-input]")!;
		input.value = "line 1";
		input.dispatchEvent(new Event("input", { bubbles: true }));
		await flushFrames(8);
		const count = host.querySelector<HTMLElement>("[data-terminal-find-count]")!;
		const before = count.textContent;
		renderer.setVisible(false);
		core.enqueue(new TextEncoder().encode("unrelated output\r\n"));
		await flushFrames(8);
		renderer.setVisible(true);
		await flushFrames(8);
		expect(input.value).toBe("line 1");
		expect(count.textContent).toBe(before);
	});
```

- [ ] **Step 2: Run and see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/dom-block-renderer.visibility.test.ts src/find-bar.test.ts`
Expected: FAIL — "keeps draining a hidden pane" sees mutations > 0; "paints the current tail on the call that reveals it" fails because the DOM already moved while hidden; "neither samples…" sees a prediction still counted. The "paints while … hidden and inert" and "reports … as not visible" tests may already pass (they pin today's behaviour for the gate to keep); "keeps the query" may pass too. Record which failed.

- [ ] **Step 3: Implement the gate**

Fields beside `hostVisible`:

```ts
	private catchUp = false;
```

Replace `repaintOnFrame`:

```ts
	private repaintOnFrame(timestamp: number): void {
		if (
			this.painting() &&
			this.lastPaintAt !== null &&
			timestamp - this.lastPaintAt + FRAME_EPSILON_MS < PAINT_INTERVAL_MS
		) {
			this.rafHandle = requestAnimationFrame((nextTimestamp) =>
				this.repaintOnFrame(nextTimestamp),
			);
			return;
		}
		this.core?.drain();
		this.core?.tick(Date.now());
		this.rafHandle = null;
		if (!this.painting()) {
			this.settleHidden();
			return;
		}
		this.repaint(timestamp);
	}

	private painting(): boolean {
		return this.hostVisible !== false;
	}

	private settleHidden(): void {
		const core = this.core;
		if (!core || !this.container) return;
		this.detectFinishedBlocks(core.snapshot());
		core.takeDirty();
		this.catchUp = true;
		this.rescheduleIfPending(core);
	}
```

Replace `setVisible`:

```ts
	setVisible(visible: boolean | null): void {
		const wasPainting = this.painting();
		this.hostVisible = visible;
		if (!this.painting()) {
			if (wasPainting) {
				this.sentCursor = null;
				this.predictionsClear();
			}
			return;
		}
		if (wasPainting) return;
		if (this.rafHandle !== null && typeof cancelAnimationFrame === "function") cancelAnimationFrame(this.rafHandle);
		this.rafHandle = null;
		this.core?.drain();
		this.core?.tick(Date.now());
		this.rebuildAll = this.rebuildAll || this.catchUp;
		this.catchUp = false;
		this.repaint(performance.now());
	}
```

Guard the overlay entry points that paint outside `repaint`:

```ts
	private linkChanged(): void {
		const link = this.linkifier.current();
		this.container?.classList.toggle("terminal-link-hover", link !== null);
		if (this.painting()) this.paintDecorations();
		for (const listener of [...this.linkHoverListeners]) listener(link);
	}
```

At the top of `reconcilePredictions` add `if (!this.painting()) return;`, and at the top of `noteReceived` add `if (!this.painting()) return;`. `predictKey` needs no guard: a parked pane is inert and never receives keys, and `predictionsClear` on park already emptied the layer.

In `dispose()` add `this.catchUp = false;`.

`repaint` itself is unchanged: `mount` (`:185`) still paints once synchronously, and a host that never calls `setVisible` never enters the hidden branch.

- [ ] **Step 4: Run and see them pass**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run`
Expected: all pass, the whole renderer suite included.

- [ ] **Step 5: Bench parks the way Operator will**

`packages/terminal/bench/adapters/dom.ts`, beside `getCoreForBench`:

```ts
	setVisible(visible: boolean): void {
		this.renderer?.setVisible(visible);
	}
```

`packages/terminal/bench/agent-session/main.ts`: in `mountPanes`, after `if (mode === "parked") park(paneHost);` make it

```ts
		if (mode === "parked") {
			park(paneHost);
			pane.setVisible(false);
		}
```

and count parked-pane mutations — beside `parkingLot`:

```ts
let parkedMutations = 0;
```

in `parking()` after `document.body.append(lot);`:

```ts
	new MutationObserver((records) => {
		parkedMutations += records.length;
	}).observe(lot, { childList: true, subtree: true, attributes: true, characterData: true });
```

(`park()` appends the pane to the lot before `pane.setVisible(false)`, so the one append record lands before the reset below.) In the `AgentSession` type add `parkedMutations(): number;` and `resetParkedMutations(): void;`, and in `window.__agentSession` add `parkedMutations: () => parkedMutations, resetParkedMutations: () => { parkedMutations = 0; },`. In `run.mjs` `paneLoad`, call `await page.evaluate(() => window.__agentSession.resetParkedMutations?.());` right before `const before = await metricsNow(session);`, and after `out.parkedState = …` add `out.parkedMutations = await page.evaluate(() => window.__agentSession.parkedMutations());`.

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && node bench/agent-session/run.mjs --panes-only`
Expected: `parked3.parkedMutations` and `parked9.parkedMutations` are `0`; every `parkedState` entry has `backlog: false` and the same generation as before the gate (118). Report the TaskDuration numbers in the commit message body; they are recorded properly in Task 8.

- [ ] **Step 6: CHANGELOG**

```md
- renderer-dom: a renderer whose host set `setVisible(false)` stops painting. Each frame still drains and ticks the core (the 12 ms feed budget is unchanged) and still reports finished blocks; the DOM, the link underline, hints, redaction masks and the predictive-echo overlay are left alone, the round-trip meter does not sample, and the wasm dirty set is discarded. `setVisible(true)` paints the current model synchronously as a full rebuild, so the first visible frame is the current tail. Measured cost of a parked pane before this: the same as a visible one (docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md).
```

- [ ] **Step 7: TERMINAL.md §6 verification** — Task 2 Step 5's block plus `npm run bench:agent:gate` and `npm run bench:agent:scroll`. Expected: all green, zero pixel diff (no visible pane calls `setVisible(false)`).

- [ ] **Step 8: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts packages/terminal/ts/renderer-dom/src/dom-block-renderer.visibility.test.ts packages/terminal/ts/renderer-dom/src/find-bar.test.ts packages/terminal/bench/adapters/dom.ts packages/terminal/bench/agent-session/main.ts packages/terminal/bench/agent-session/run.mjs packages/terminal/CHANGELOG.md
git commit -m "feat(terminal): a hidden pane drains and reports blocks but does not paint"
```

---

### Task 5: The line editor idles while hidden

The profile's second-largest parked cost is `LineEditor`'s change listener: `ingestHistory` takes `core.snapshot()` and decodes every block on every change (`line-editor.ts:85-88`, `:474-478`), then `render()`. While hidden, skip both and do them once on reveal. `TerminalSurface`'s `visible` effect drives the editor too.

**Files:**
- Modify: `packages/terminal/ts/editor/src/line-editor.ts:51-96` (listener), add `setVisible`
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx` (the Task 3 effect)
- Modify: `packages/terminal/bench/adapters/dom.ts` (`setVisible` also reaches the editor)
- Test: `packages/terminal/ts/editor/src/line-editor.test.ts`, `packages/terminal/ts/react/src/TerminalSurface.test.tsx`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Produces: `LineEditor.setVisible(visible: boolean): void`.

- [ ] **Step 1: Write the failing test**

In `line-editor.test.ts`, using its existing mount helper (read the top of the file; it builds a core and mounts a `LineEditor` on a host):

```ts
it("does no history or render work while hidden and catches up when shown", () => {
	const { core, editor } = mountEditor();
	const snapshots = vi.spyOn(core, "snapshot");
	editor.setVisible(false);
	for (let index = 0; index < 10; index += 1) {
		core.feed(new TextEncoder().encode(`\x1b]133;A\x07\x1b]133;B\x07cmd${index}\x1b]133;C\x07\r\n\x1b]133;D;0\x07`));
	}
	expect(snapshots).not.toHaveBeenCalled();
	editor.setVisible(true);
	expect(snapshots).toHaveBeenCalled();
});
```

(`mountEditor` stands for the file's helper; if it returns other names, use them. If the file has a history-recall test, extend this one to press ArrowUp after `setVisible(true)` and expect `cmd9`.)

In `TerminalSurface.test.tsx`:

```tsx
it("hands the host's visibility to the line editor", () => {
	const spy = vi.spyOn(LineEditor.prototype, "setVisible");
	const { rerender } = renderSurface({ visible: false });
	expect(spy).toHaveBeenLastCalledWith(false);
	rerender(surfaceElement({}));
	expect(spy).toHaveBeenLastCalledWith(true);
});
```

- [ ] **Step 2: Run and see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/editor && npx vitest run src/line-editor.test.ts -t "hidden"`
Expected: FAIL — `editor.setVisible is not a function`.

- [ ] **Step 3: Implement**

`line-editor.ts` fields beside `history`:

```ts
	private visible = true;
	private staleWhileHidden = false;
```

listener in `mount`:

```ts
		this.unsubscribe = core.onChange(() => {
			if (!this.visible) {
				this.staleWhileHidden = true;
				return;
			}
			this.ingestHistory();
			this.render();
		});
```

method:

```ts
	setVisible(visible: boolean): void {
		this.visible = visible;
		if (!visible || !this.staleWhileHidden) return;
		this.staleWhileHidden = false;
		this.ingestHistory();
		this.render();
	}
```

reset both fields in `dispose()` (`visible = true`, `staleWhileHidden = false`).

`TerminalSurface.tsx`, the Task 3 effect becomes:

```ts
	useLayoutEffect(() => {
		rendererRef.current?.setVisible(visible ?? null);
		editorRef.current?.setVisible(visible !== false);
	}, [visible]);
```

`bench/adapters/dom.ts`:

```ts
	setVisible(visible: boolean): void {
		this.renderer?.setVisible(visible);
		this.editor?.setVisible(visible);
	}
```

- [ ] **Step 4: Run and see them pass**

Run: `for p in editor react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done`
Expected: all pass.

- [ ] **Step 5: CHANGELOG**

```md
- editor/react: `LineEditor.setVisible(false)` (driven by `TerminalSurface`'s `visible`) skips the per-change history ingest and render — a full `core.snapshot()` and block decode per change — and does them once when shown again.
```

- [ ] **Step 6: TERMINAL.md §6 verification** — Task 2 Step 5's block, with `editor` added to the vitest loop. Expected: all green, zero pixel diff.

- [ ] **Step 7: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add packages/terminal/ts/editor/src/line-editor.ts packages/terminal/ts/editor/src/line-editor.test.ts packages/terminal/ts/react/src/TerminalSurface.tsx packages/terminal/ts/react/src/TerminalSurface.test.tsx packages/terminal/bench/adapters/dom.ts packages/terminal/CHANGELOG.md
git commit -m "feat(terminal): the line editor idles while its pane is hidden"
```

---

### Task 6: Operator drives the seam from the activation phase

`TerminalPane` owns the fact. A cached entry paints in every phase except `"parked"` — `"preparing"` must paint while still `visibility: hidden` (that is the reveal path's point, `TerminalPane.tsx:197-210`), and `"ready"`/`"revealed"`/`"visible"` are on the way to or on screen. A direct, uncached mount (reviewer terminals) is always rendered. This stays separate from `isVisible` (`phase === "visible"`), which drives focus and the attachment.

The reveal ordering this relies on: `showTerminal` → rerender → `TerminalSurface`'s layout effect calls `setVisible(true)` → synchronous catch-up paint (Task 4) — all before the browser paints; `markReveal` clears `visibility: hidden` later in a layout effect, and `markActivated` runs two animation frames after that (`:262-274`). So the first frame the user sees is current.

Split view (`docs/superpowers/plans/2026-09-22-split-view.md`, not built) gives each pane its own slot and entry; this wiring is per entry, so several panes can be visible at once without change.

**Files:**
- Modify: `frontend/src/renderer/components/TerminalPane.tsx:276-285` (portal props), `:820-835` (`AttachedTerminal` props), `:1002-1014` (`BlockTerminal` props)
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx:42-68` (props), `:575-608` (`surfaceProps`)
- Test: `frontend/src/renderer/components/TerminalPane.test.tsx`, `frontend/src/renderer/components/BlockTerminal.test.tsx`

**Interfaces:**
- Consumes: `TerminalSurfaceProps.visible` (Task 3).
- Produces: `BlockTerminalProps.visible?: boolean`; `AttachedTerminal` prop `isRendered?: boolean` (default `true`).

- [ ] **Step 1: Write the failing tests**

`TerminalPane.test.tsx` — extend the `BlockTerminal` mock (`:65-83`) to take `visible?: boolean` and render `data-visible={String(props.visible)}`. Then, in `describe("TerminalPane focus")` beside the retained-focus test:

```tsx
	it("paints a retained terminal on screen and stops painting it while parked", async () => {
		const sessionA = { ...worker, id: "sess-a", title: "session A", terminalHandleId: "handle-a" };
		const sessionB = { ...worker, id: "sess-b", title: "session B", terminalHandleId: "handle-b" };
		const view = renderCachedPane({ session: sessionA, sessions: [sessionA, sessionB] });
		try {
			await waitFor(() => expect(activeFocusToken()).toBe("1"));
			const paneA = screen.getByTestId("block-terminal");
			expect(paneA.getAttribute("data-visible")).toBe("true");

			view.show(sessionB);
			await waitFor(() => expect(paneA.getAttribute("data-visible")).toBe("false"));
			expect(within(screen.getByTestId("session-terminal-slot")).getByTestId("block-terminal").getAttribute("data-visible")).toBe("true");

			view.show(sessionA);
			await waitFor(() => expect(activeFocusToken()).toBe("2"));
			expect(paneA.getAttribute("data-visible")).toBe("true");
		} finally {
			view.restore();
		}
	});

	it("paints a retained terminal while it is being prepared, before it is revealed", async () => {
		const sessionA = { ...worker, id: "sess-a", title: "session A", terminalHandleId: "handle-a" };
		const sessionB = { ...worker, id: "sess-b", title: "session B", terminalHandleId: "handle-b" };
		const view = renderCachedPane({ session: sessionA, sessions: [sessionA, sessionB] });
		try {
			await waitFor(() => expect(activeFocusToken()).toBe("1"));
			const paneA = screen.getByTestId("block-terminal");
			view.show(sessionB);
			await waitFor(() => expect(paneA.getAttribute("data-visible")).toBe("false"));
			view.show(sessionA);
			const container = paneA.closest<HTMLElement>("[data-terminal-activation-phase]")!;
			await waitFor(() => expect(container.dataset.terminalActivationPhase).not.toBe("parked"));
			expect(paneA.getAttribute("data-visible")).toBe("true");
		} finally {
			view.restore();
		}
	});
```

If the second test cannot observe `"preparing"` because the phases settle within one `waitFor` tick, keep its assertion as written (it checks the first non-parked phase already paints) — do not add sleeps.

`BlockTerminal.test.tsx` — beside "hands the host's focus token to the surface", mirror that test with `visible={false}` and assert the surface received `visible: false` (use the same way that test captures `TerminalSurface` props).

- [ ] **Step 2: Run and see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run src/renderer/components/TerminalPane.test.tsx src/renderer/components/BlockTerminal.test.tsx`
Expected: FAIL — `data-visible` is `"undefined"`.

- [ ] **Step 3: Implement**

`BlockTerminal.tsx` — in `BlockTerminalProps` after `focusToken?: number;`:

```ts
	visible?: boolean;
```

destructure it and add `visible,` to `surfaceProps` beside `focusToken,`.

`TerminalPane.tsx` — `AttachedTerminal` props: add `isRendered = true,` to the destructuring and `isRendered?: boolean;` to its prop type; pass `visible={isRendered}` to `<BlockTerminal … />` beside `focusToken={focusToken}`. In `CachedTerminalPortal`'s `<AttachedTerminal … />` add:

```tsx
			isRendered={active && entry.activationPhase !== "parked"}
```

- [ ] **Step 4: Run and see them pass**

Run: `cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run src/renderer/components/TerminalPane.test.tsx src/renderer/components/BlockTerminal.test.tsx && npx tsc --noEmit -p .`
Expected: PASS; no type errors.

- [ ] **Step 5: Real-app check**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts
```

Restart `tauri:dev` with the scrubbed env (memory "Scrub CLAUDE* env before running Operator dev"). Open two worker sessions running Claude Code, give session A a long prompt, switch to B for ~30 s, switch back. Expected: A shows its current tail on the first frame, no flash of the old viewport. Evidence: `screencapture -l <window id>` (memory "Verify Operator desktop via daemon API and /mux") right after switching back. If the window cannot be captured, say so in the report — do not claim it.

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add frontend/src/renderer/components/TerminalPane.tsx frontend/src/renderer/components/TerminalPane.test.tsx frontend/src/renderer/components/BlockTerminal.tsx frontend/src/renderer/components/BlockTerminal.test.tsx
git commit -m "feat(terminal): parked worker panes stop painting"
```

---

### Task 7: Keep draining and notifying while the window is hidden

Measured: WKWebView fires no animation frames while minimised or app-hidden and throttles timers to ~1/s. While `document.visibilityState === "hidden"`, `scheduleRepaint` arms a timer instead of `requestAnimationFrame`; the timer does exactly what a hidden frame does (`drain`, `tick`, `settleHidden`). On `visibilitychange` to visible the timer is cancelled and a normal frame is scheduled, which paints only if the host says visible. On `visibilitychange` to hidden a pending animation frame is cancelled and replaced by the timer, because a pending frame would otherwise block `scheduleRepaint`'s de-duplication forever.

The hidden tick drains with its own, much larger budget: `core.drain(HIDDEN_DRAIN_MS)` with `HIDDEN_DRAIN_MS = 250`, not the default 12 ms. Nothing paints while the document is hidden, so there is no frame to protect, and WebKit throttles the tick to ~1/s: at 12 ms per second a busy session's closing mark would sit in the backlog until the window is restored, and the block would then be reported `visible: true` and its notification suppressed — the very bug this task fixes. `FEED_BUDGET_MS` is unchanged and animation-frame drains keep using it. A producer needing more than ~250 ms of parse per second can still grow the backlog while hidden (recorded in TERMINAL.md §5 in Task 8).

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` — `scheduleRepaint` (`:817-824`), `mount`, `dispose`
- Test: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.visibility.test.ts`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `settleHidden`, `painting`, `documentHidden` (Tasks 3–4).
- Produces: `export const HIDDEN_TICK_MS = 100;` and `export const HIDDEN_DRAIN_MS = 250;` (module constants in `dom-block-renderer.ts`, exported for the test, not added to the package index), `private hiddenTimer`, `private readonly onVisibilityChange`.

- [ ] **Step 1: Write the failing tests**

Append to `dom-block-renderer.visibility.test.ts` (it already has `setDocumentVisibility`). These stub `requestAnimationFrame` so it never fires — what WKWebView does while hidden:

```ts
function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

describe("hidden document", () => {
	afterEach(() => setDocumentVisibility("visible"));

	it("drains and reports finished blocks on a timer while the document is hidden", async () => {
		const { core, renderer, events } = mounted();
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		vi.stubGlobal("requestAnimationFrame", () => 0);
		setDocumentVisibility("hidden");
		core.enqueue(text(`done\r\n${CLOSE_BLOCK}`));
		await sleep(400);
		expect(core.hasBacklog()).toBe(false);
		expect(events).toHaveLength(1);
		expect(events[0]).toMatchObject({ visible: false });
		renderer.dispose();
	});

	it("paints the visible pane when the document is shown again, and not the parked one", async () => {
		const shown = mounted();
		const parked = mounted();
		parked.renderer.setVisible(false);
		shown.renderer.setVisible(true);
		await flushRepaint();
		const parkedRows = rowTexts(parked.host);
		setDocumentVisibility("hidden");
		shown.core.enqueue(text("while away\r\n"));
		parked.core.enqueue(text("while away\r\n"));
		await sleep(400);
		setDocumentVisibility("visible");
		await flushRepaint();
		expect(rowTexts(shown.host).join("\n")).toContain("while away");
		expect(rowTexts(parked.host)).toEqual(parkedRows);
		shown.renderer.dispose();
		parked.renderer.dispose();
	});

	it("drains ~2 MiB enqueued while hidden within a few ticks and reports the block closing at its end as not visible", async () => {
		const { core, renderer, events } = mounted(80);
		core.feed(text(OPEN_BLOCK));
		await flushRepaint();
		vi.stubGlobal("requestAnimationFrame", () => 0);
		setDocumentVisibility("hidden");
		const drain = vi.spyOn(core, "drain");
		const line = text(`${"x".repeat(78)}\r\n`);
		const burst = new Uint8Array(line.length * 26_000);
		for (let at = 0; at < burst.length; at += line.length) burst.set(line, at);
		for (let at = 0; at < burst.length; at += 64 * 1024) core.enqueue(burst.subarray(at, Math.min(burst.length, at + 64 * 1024)));
		core.enqueue(text(CLOSE_BLOCK));
		for (let waited = 0; events.length === 0 && waited < 5000; waited += 50) await sleep(50);
		expect(core.hasBacklog()).toBe(false);
		expect(drain).toHaveBeenCalledWith(HIDDEN_DRAIN_MS);
		expect(drain.mock.calls.length).toBeLessThanOrEqual(3);
		expect(events).toHaveLength(1);
		expect(events[0]).toMatchObject({ visible: false });
		renderer.dispose();
	});

	it("stops its timer when disposed while hidden", async () => {
		const { core, renderer } = mounted();
		vi.stubGlobal("requestAnimationFrame", () => 0);
		setDocumentVisibility("hidden");
		core.enqueue(text("x\r\n"));
		const drain = vi.spyOn(core, "drain");
		renderer.dispose();
		await sleep(400);
		expect(drain).not.toHaveBeenCalled();
	});
});
```

Add `import { HIDDEN_DRAIN_MS } from "./dom-block-renderer";` to the file's imports. The burst is 26,000 × 80 bytes = 2,080,000 bytes (~2 MiB). The tick bound (≤ 3 drain calls) is what fails against a 12 ms budget: the spec measured a 2 MiB synchronous parse at 57 ms in Chromium, so 12 ms per tick needs ~5 or more ticks. If the bound is too tight for this machine's Node wasm, measure one 2 MiB `drain(HIDDEN_DRAIN_MS)` in the test and derive the bound from it, stating the measured time in the commit message — never loosen it to a bound a 12 ms budget would also pass.

Then replace the Task 3 test "reports not visible while the document is hidden, whatever the host says" body's private call with the real path: stub `requestAnimationFrame` to `() => 0`, set hidden, `core.enqueue(text(CLOSE_BLOCK))`, `await sleep(400)`, expect `events.at(-1)` to match `{ visible: false }`.

- [ ] **Step 2: Run and see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/dom-block-renderer.visibility.test.ts -t "hidden"`
Expected: FAIL — backlog still present and no event after 400 ms (nothing drains without animation frames); the ~2 MiB test fails on the same missing path. After Step 3, if an intermediate version calls `core.drain()` with no argument, the ~2 MiB test must still fail on `toHaveBeenCalledWith(HIDDEN_DRAIN_MS)` and the tick bound — that is the failure this test exists for.

- [ ] **Step 3: Implement**

Module constant beside `PAINT_INTERVAL_MS` (`:68`):

```ts
export const HIDDEN_TICK_MS = 100;
export const HIDDEN_DRAIN_MS = 250;
```

fields:

```ts
	private hiddenTimer: ReturnType<typeof setTimeout> | null = null;
	private readonly onVisibilityChange = () => {
		if (this.rafHandle !== null && typeof cancelAnimationFrame === "function") cancelAnimationFrame(this.rafHandle);
		this.rafHandle = null;
		if (this.hiddenTimer !== null) clearTimeout(this.hiddenTimer), (this.hiddenTimer = null);
		this.scheduleRepaint();
	};
```

`scheduleRepaint`:

```ts
	private scheduleRepaint(): void {
		if (this.rafHandle !== null || this.hiddenTimer !== null) return;
		if (documentHidden()) {
			this.hiddenTimer = setTimeout(() => this.hiddenTick(), HIDDEN_TICK_MS);
			return;
		}
		if (typeof requestAnimationFrame !== "function") {
			this.repaint();
			return;
		}
		this.rafHandle = requestAnimationFrame((timestamp) => this.repaintOnFrame(timestamp));
	}

	private hiddenTick(): void {
		this.hiddenTimer = null;
		const core = this.core;
		if (!core) return;
		core.drain(HIDDEN_DRAIN_MS);
		core.tick(Date.now());
		this.settleHidden();
	}
```

In `mount`, after the `core.onChange` subscription: `document.addEventListener("visibilitychange", this.onVisibilityChange);`. In `dispose`, first lines: `document.removeEventListener("visibilitychange", this.onVisibilityChange);` and `if (this.hiddenTimer !== null) clearTimeout(this.hiddenTimer), (this.hiddenTimer = null);`.

`settleHidden` already calls `rescheduleIfPending`, which re-arms the timer while backlog or an open sync block remains, and it sets `catchUp` — now also for a pane the host shows, since the timer runs for every pane while the document is hidden. Move the `catchUp` consumption into `repaint` so the first painting frame after the document is shown does the full rebuild, whoever triggers it. At the top of `repaint`, before `const core = this.core;`:

```ts
		if (this.catchUp) {
			this.rebuildAll = true;
			this.catchUp = false;
		}
```

and in `setVisible` replace the two lines

```ts
		this.rebuildAll = this.rebuildAll || this.catchUp;
		this.catchUp = false;
```

with nothing (the following `this.repaint(performance.now());` now consumes `catchUp` itself).

- [ ] **Step 4: Run and see them pass**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run`
Expected: all pass.

- [ ] **Step 5: Real-app check of the notification**

Rebuild `dist` and restart `tauri:dev` (as Task 6 Step 5). In a shell session run `sleep 15; echo done` (longer than `BLOCK_NOTIFY_AFTER_MS`, `BlockTerminal.tsx`), minimise Operator, wait 20 s. Expected: the "command finished" notification arrives while the window is minimised. Before this task it arrived only after restoring the window, or not at all for the active pane (measurement note, "Hidden window"). Report what you saw; if you could not observe the notification, say so.

- [ ] **Step 6: CHANGELOG**

```md
- renderer-dom: while `document.visibilityState` is `"hidden"` (a minimised or hidden window, where WebKit fires no animation frames) the renderer drains (with a 250 ms budget per tick, `HIDDEN_DRAIN_MS`, since nothing paints and WebKit throttles the timer to ~1/s; animation-frame drains keep the 12 ms `FEED_BUDGET_MS`), ticks and reports finished blocks on a timer instead of animation frames, and paints the visible pane once the document is shown. Before, a hidden window parsed nothing and fired no `onBlockFinished` until it was shown again.
```

- [ ] **Step 7: TERMINAL.md §6 verification** — Task 2 Step 5's block plus `npm run bench:agent:gate`. Expected: green, zero pixel diff.

- [ ] **Step 8: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts packages/terminal/ts/renderer-dom/src/dom-block-renderer.visibility.test.ts packages/terminal/CHANGELOG.md
git commit -m "fix(terminal): drain and report finished blocks while the window is hidden"
```

---

### Task 8: Re-measure and record

**Files:**
- Modify: `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` ("The table" and its notes)
- Modify: `docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md` (append an "After" section)
- Modify: `TERMINAL.md` §5 (and §4 — a new entry for the hidden-window bug)
- Create: `packages/terminal/bench/agent-session/baselines/pane-cost/<date>-after-run{1,2,3}.json`

- [ ] **Step 1: Rebuild and measure three times, plus one profile**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
for i in 1 2 3; do node /Users/omaraly/development/AI/Operator/packages/terminal/bench/agent-session/run.mjs --panes-only | grep '^{' > /Users/omaraly/development/AI/Operator/packages/terminal/bench/agent-session/baselines/pane-cost/$(date +%F)-after-run$i.json; done
node /Users/omaraly/development/AI/Operator/packages/terminal/bench/agent-session/run.mjs --panes-only --profile | grep '^{' > /tmp/after-profile.json
```

Record for each row: TaskDuration, Script/Layout/RecalcStyle durations, LayoutCount, RecalcStyleCount, `parkedMutations`, `parkedState`.

- [ ] **Step 2: Judge against the before numbers, honestly**

Before (measurement note): solo 0.23–0.39 s; 1+3 parked 0.53–0.64 s; 1+9 parked 0.89–1.00 s; 10 visible 0.86–1.13 s; +122 layouts per parked pane per 100 frames. Expectation, stated so a miss is visible: parked panes add **0 layouts and 0 style recalcs**, `parkedMutations` 0, and the 1+9 row lands near solo plus the parse (profile share ~8 ms per pane per 10 s) plus the per-change `core.snapshot()` still taken by block detection and `TerminalSurface`'s alt-screen listener (`TerminalSurface.tsx:287-291`, which the bench does not mount). If the 1+9 row is not clearly below the 10-visible row, report it as a miss with the profile's top self-time functions — do not tune the harness to hit it. The 10-visible row must be unchanged within noise (no visible-pane change).

- [ ] **Step 3: The baseline table**

In `2026-09-19-agent-tui-experience-design.md` "The table", add two rows after the "main-thread task time of ten idle spinner panes" row:

```md
| main-thread task time, 1 visible + 3 parked spinner panes over 10 s | `run.mjs --panes-only` `parked3`: CDP `TaskDuration`, `LayoutDuration`, `RecalcStyleDuration` deltas; parked panes built like `TerminalPane.parkTerminal` and fed by `enqueue` | 0.532–0.642 s (2026-09-23, `development` `b59c3b27c`; +122 layouts per parked pane per 100 frames) | — | — | — | — | — |
| main-thread task time, 1 visible + 9 parked spinner panes over 10 s | same, `parked9` | 0.886–1.004 s (2026-09-23; run 1 under the profiler) | — | — | — | — | — |
```

and write the after-numbers into a new sentence at the end of each of these two rows' "Today" cell ("After the background-pane gate (2026-09-2x): …"), and the same for the 10-visible row's last cell. Do not add a column. Use measured values only; if a run failed, say so in the cell.

- [ ] **Step 4: TERMINAL.md**

§4 — add "### 4.24 A hidden window drained nothing and notified nothing" (symptom; cause: `requestAnimationFrame` never fires in a hidden WKWebView, measured by `scripts/probe-wkwebview-hidden.swift`; now: Task 7's timer path and Task 4's paint gate; guards: `dom-block-renderer.visibility.test.ts` "hidden document" and "paint gate" describes, `TerminalPane.test.tsx` "paints a retained terminal on screen and stops painting it while parked").

§5 — add a bullet "**What a parked pane still costs.**" with: the measured after-numbers from Step 1; that each change still builds one snapshot (block detection, `TerminalSurface`'s alt-screen read) and decodes blocks; that a hidden window drains up to `HIDDEN_DRAIN_MS` (250 ms) of parse per timer tick, which WebKit throttles to ~1/s, so only a producer needing more than ~250 ms of parse per second grows the backlog while hidden — and why the budget is larger than `FEED_BUDGET_MS` there (no paint to protect; a 12 ms budget left a busy session's closing mark in the backlog until restore, where the block was reported `visible: true` and its notification suppressed); that `rendererVisible` remains the fallback only for `onBlockFinished` when a host sets nothing, and is never a paint gate; and that the forced layout at `dom-block-renderer.ts:1055` is still paid by every **visible** pane (measurement note, "Follow-ups").

- [ ] **Step 5: Manual real-app checks**

The WKWebView probe was a plain WKWebView and the bench never mounts the React layer, so the two user-facing outcomes need the real app. Rebuild `dist` (`cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts`) and restart `tauri:dev` with the scrubbed env (memory "Scrub CLAUDE* env before running Operator dev"), then:

(a) **Notification while minimised.** In a Claude Code worker session, have Claude run a command that takes more than 10 s (e.g. ask it to run `sleep 15 && echo done`). While it runs, minimise Operator. Expected: the "command finished" notification arrives while the window is still minimised.

(b) **Reveal shows the tail.** With a background session streaming (Claude Code working in session A), switch to session B's tab, wait ~30 s, switch back to A. Expected: A's first visible frame shows its current tail, stuck to the bottom — no frame of the old viewport. Evidence: `screencapture -l <window id>` immediately after switching back (memory "Verify Operator desktop via daemon API and /mux").

Report each as **observed** (what was seen, with the evidence) or **not verified** (and why it could not be driven). Never report either as passing without having seen it.

- [ ] **Step 6: Measurement note "After" section**

Append "## After (<date>)" to `2026-09-23-background-pane-cost-measurement.md` with the table from Step 1 in the same shape as "Numbers", the profile's top 10 self-time functions, a one-line verdict per expectation from Step 2 (met / missed, with the number), and Step 5's two real-app results exactly as reported (observed / not verified).

- [ ] **Step 7: Full verification**

TERMINAL.md §6 block for every touched layer:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts
for p in core renderer-dom editor react; do (cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/$p && npx vitest run); done
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel && npm run bench:selection && npm run bench:agent:gate && npm run bench:agent:scroll
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p . && npx vitest run src/renderer/components/TerminalPane.test.tsx src/renderer/components/BlockTerminal.test.tsx
```

Expected: all green; `PASS feel gate: zero pixel diff`.

- [ ] **Step 8: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add TERMINAL.md docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md packages/terminal/bench/agent-session/baselines/pane-cost
git commit -m "docs(terminal): parked-pane cost after the paint gate"
```
