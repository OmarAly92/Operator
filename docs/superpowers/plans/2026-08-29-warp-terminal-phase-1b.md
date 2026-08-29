# Warp Terminal Phase 1b Implementation Plan — the renderer, the daemon capture, and Operator

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the block-aware core visible and usable — a virtualized DOM block list with Warp-style headers, mounted in Operator as the session pane, with the daemon recording blocks whether or not a client is attached.

**Architecture:** `renderer-dom` virtualizes twice, by block and by row within a tall block, driven by the fourteen-word block records Phase 1a Task 1 froze. Full-screen TUIs hand the pane to the existing `XtermTerminal` and take it back on exit. Server-side, `tmux pipe-pane` streams the pane to a reader that uses `go/marks`, so a session nobody is watching still records its scrollback exactly once.

**Tech Stack:** TypeScript 5 / React 19 / Vitest / Playwright, Rust 1.96.0 (`vt-core`, `vt-wasm`), Go 1.25.7, tmux, Tauri 2.

**Spec:** `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`

**Companion plan:** `docs/superpowers/plans/2026-08-29-warp-terminal-phase-1a.md`

## Global Constraints

Copied verbatim from the spec and from what Phase 0 and 1a landed. Every task's requirements implicitly include this section.

- **No source file over 600 lines.** `npm --prefix packages/terminal run check:boundaries` enforces it.
- **No import may escape `packages/terminal/`.** The package MUST NOT import from `frontend/`, `backend/`, or `packages/shared/`. `frontend/` imports the package **by package name only** — `@operator/terminal-react` — never by relative path.
- **`renderer-dom` MUST NOT import `editor` or `completions`.** Same checker.
- **`BLOCK_RECORD_WORDS` is 14** and is pinned on both sides. Word 4 packs `state | source << 8 | has_exit << 16`; word 5 is the raw two's-complement `i32`. Do not change the layout in this phase.
- **Rows are built from typed-array slices. Never build a JS object per cell** (spec §6.2, wrong turn 1).
- **No canvas fast-path inside a DOM block** (spec §9.3, wrong turn 11). The escape hatch is a whole renderer behind `BlockRenderer`, not a hybrid.
- **`XtermTerminal.tsx` is not deleted.** It becomes the alt-screen surface (spec §11, wrong turn 12).
- **The package owns no Operator concepts.** Strings arrive through `TerminalStrings`; theme through `TerminalTheme`; no `react-i18next` inside the package.
- **Every new user-facing string that reaches Operator goes into all eight locale files** under `frontend/src/renderer/i18n/` — `en, zh-CN, ja, ko, es, fr, de, pt-BR` — non-empty and key-matched.
- **Windows gets no shell blocks.** A Windows session opens the raw grid and says shell blocks are unavailable. Do not silently degrade.
- **Prompt suppression stays OFF.** `spawnRecipe` throws on `suppressPrompt: true` and that guard stays until Phase 2.
- Desktop visual language: shadcn primitives from `components/ui/*`, agent-orchestrator's language with the refined-blue accent, and the terminal pane's interior is pixel-Warp per `DESIGN.md:36`.
- Gates: `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `npm run frontend:typecheck`, `npm run lint`, `npm --prefix packages/terminal run check:boundaries`.

---

## Dependency on Phase 1a — read before scheduling

Phase 1a Task 1 is **merged at `e9da036db`**. Fork this work from that commit or later. It gives you the frozen contract: `TerminalSnapshot.blocks` / `.blockText`, `decodeBlocks`, `BlockView`, `BLOCK_RECORD_WORDS`.

Today that contract emits **one synthetic block covering every row**. That is enough to build and test every renderer task against — a one-block list is still a list, and the virtualizer's arithmetic does not care how the blocks were formed.

| 1b Task | Needs from 1a | May start |
| --- | --- | --- |
| 1 bench DOM adapter | Task 1 only | now |
| 2 virtualized block list | Task 1 only | now |
| 3 block headers | Task 1 only | now |
| 4 selection, copy, hover | Task 1 only | now |
| 5 alt-screen handoff | Task 1 only | now |
| 6 daemon capture | **1a Task 6 (`go/marks`)** | after 1a Task 6 merges |
| 7 Operator wiring | Tasks 2-5 | after them |
| 8 the perf gate | **all of 1a** | after 1a merges in full |
| 9 acceptance close-out | everything | last |

**Task 8 is the one that touches `vt-core` and `vt-wasm`.** Tasks 1-7 touch only `ts/renderer-dom`, `ts/react`, `bench/`, `frontend/`, and `backend/`, so they cannot conflict with 1a's work in `crates/`. Do not start Task 8 until Phase 1a is merged, and expect to rebase.

---

## Findings That Shape This Plan

**1. The renderer already exists and is nearly the right shape.** `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` (240 lines) implements `BlockRenderer`, subscribes via `core.onChange`, and repaints by rebuilding every row into a document fragment. Task 2 replaces `repaint()`'s body with a virtualizing one; `mount`, `setTheme`, `setFont`, `measure` and `dispose` stay as they are.

**2. `repaint()` rebuilds the whole DOM on every feed, and that is the thing to fix.** It loops `rows.length / 2` times per feed with no windowing. At Phase 0 scale that is invisible. At the spec's 50,000-block criterion it is the whole problem.

**3. The snapshot still carries every row on every feed.** Phase 1a's Finding 3 deliberately deferred this: the Rust side rebuilds all rows into `GridSnapshot` on each `feed`, so even a perfect virtualizer pays O(total rows) in Rust. **Task 8 owns it**, because the perf gate is what proves the cost is real and what shape fixes it. Tasks 2-7 MUST NOT attempt it.

**4. The bench harness has a renderer slot that is wired shut.** `packages/terminal/bench/runner.mjs:38` rejects anything but `xterm`, and `bench/adapters/` holds only `xterm.ts`. Task 1 opens it, so every later task can measure against the recorded xterm baseline in `bench/baselines/darwin-arm64-xterm.json` rather than guessing.

**5. Operator's terminal mount point is one lazy import.** `frontend/src/renderer/components/TerminalPane.tsx:47` lazily imports `XtermTerminal` and mounts it at `:1075`. Task 7 changes what is mounted there; `useTerminalSession`, the mux transport, and the retained-handle cache underneath are untouched.

**6. The `blocks` mux channel already exists end to end.** `frontend/src/renderer/lib/terminal-mux.ts:12` documents it, `:75-80` are the subscribe frames, and `:226-232` dispatches `block` frames to listeners. Task 6 publishes onto it; no new channel is invented.

**7. `blockevent.Record` is hook-shaped and must not be bent.** `backend/internal/service/blockevent/types.go:14-17` already says `SourceID` is "a hook's tool_use_id today, a shell mark's counter later". Task 6 adds a **second entry point** beside `Service.Record` (`service.go:46`), which takes `ports.ActivitySignal`. A `ToolUseID` carrying a command counter is the lie the spec's §13.1 forbids.

**8. `tmux pipe-pane` is the capture path and it has never been used here.** The adapter shells out for `capture-pane` at `backend/internal/adapters/runtime/tmux/commands.go:123`; `pipe-pane` goes beside it in the same style. Parsing at `attachment.onData` instead would duplicate every block with two clients attached and record nothing with zero attached — that analysis is settled (spec §13.1) and is not reopened.

**9. The shell's argv is already a seam.** `backend/internal/service/shellterm/loginshell.go:20` returns a bare `[$SHELL]`, and `ports.RuntimeConfig` (`backend/internal/ports/outbound.go`) carries `Argv` and `Env`. Task 6 asks the package for a `SpawnRecipe` and passes it through; the daemon never learns the protocol.

---

## Planned File Structure

```
packages/terminal/
  bench/
    adapters/dom.ts             NEW: the package's own renderer under the harness
    runner.mjs                  MODIFY: accept --renderer dom
  ts/renderer-dom/src/
    dom-block-renderer.ts       MODIFY: repaint() becomes virtualized
    viewport.ts                 NEW: which blocks and rows are visible
    block-header.ts             NEW: the Warp header row for one block
    block-actions.ts            NEW: hover actions (copy command, copy output, rerun)
    selection.ts                NEW: browser selection mapped to block coordinates
    styles.css                  MODIFY: header, actions, virtualization spacers
  ts/react/src/
    TerminalSurface.tsx         MODIFY: alt-screen surface slot
    AltScreenSlot.tsx           NEW: the seam a host fills with its raw surface

frontend/src/renderer/
  components/TerminalPane.tsx   MODIFY: mount the package, pass XtermTerminal as the slot
  components/BlockTerminal.tsx  NEW: the adapter between Operator and the package
  i18n/*.json                   MODIFY: eight locales

backend/internal/
  adapters/runtime/tmux/commands.go     MODIFY: pipe-pane args
  adapters/runtime/tmux/pipepane.go     NEW: the capture reader
  service/blockevent/shell.go           NEW: the second entry point
  service/shellterm/service.go          MODIFY: spawn with the package's recipe
```

---

### Task 1: Open the bench renderer slot and add the DOM adapter

The gate comes first so every later task can measure instead of guessing.

**Files:**
- Create: `packages/terminal/bench/adapters/dom.ts`
- Modify: `packages/terminal/bench/runner.mjs`
- Modify: `packages/terminal/bench/main.ts`
- Test: `packages/terminal/bench/runner.test.mjs`

**Interfaces:**
- Consumes `createTerminalCore`, `initTerminalCore` from `@operator/terminal-core` and `DomBlockRenderer` from `@operator/terminal-renderer-dom`.
- Produces `npm run bench:terminal -- --renderer dom --scenario vtebench|large-output|input-latency`.
- The adapter reports `{ renderer: "dom", rendererVersion: <package version> }` so `verifyWorkloads` can tell the two apart.

- [ ] **Step 1: Write the runner argument test**

Create `packages/terminal/bench/runner.test.mjs`:

```js
import test from "node:test";
import assert from "node:assert/strict";
import { parseArguments } from "./runner.mjs";

test("accepts the dom renderer", () => {
	const parsed = parseArguments(["--renderer", "dom", "--scenario", "vtebench"]);
	assert.equal(parsed.renderer, "dom");
	assert.deepEqual(parsed.names, ["vtebench"]);
});

test("accepts the xterm renderer", () => {
	const parsed = parseArguments(["--renderer", "xterm", "--scenario", "large-output"]);
	assert.equal(parsed.renderer, "xterm");
});

test("rejects an unknown renderer", () => {
	assert.throws(() => parseArguments(["--renderer", "webgl", "--scenario", "vtebench"]));
});

test("record measures every scenario and refuses a single scenario", () => {
	const parsed = parseArguments(["--renderer", "dom", "--record"]);
	assert.equal(parsed.record, true);
	assert.ok(parsed.names.length >= 3);
	assert.throws(() => parseArguments(["--renderer", "dom", "--record", "--scenario", "vtebench"]));
});
```

`parseArguments` currently calls `process.exit(2)` on bad input, which a test cannot assert on. Change it to throw a `UsageError` and have the CLI entry point catch it, print the usage text and exit 2. That keeps the CLI behaviour identical and makes the parser testable.

- [ ] **Step 2: Run and confirm red**

Run: `node --test packages/terminal/bench/runner.test.mjs`
Expected: FAIL — `parseArguments` is not exported and `dom` is rejected.

- [ ] **Step 3: Open the slot**

In `runner.mjs`, replace the `if (renderer !== "xterm")` check with a set of `["xterm", "dom"]`, export `parseArguments`, and carry `renderer` through to `verifyWorkloads`. `verifyWorkloads` keeps pinning `xterm` to version `5.5.0` and pins `dom` to the package version read from `packages/terminal/package.json`.

**Results and baselines stay keyed by renderer.** `bench/baselines/darwin-arm64-xterm.json` is not overwritten by a `dom` run; a `dom` record writes `darwin-arm64-dom.json` beside it. The xterm baseline is the number we are measured against and it does not move.

- [ ] **Step 4: Write the DOM adapter**

`bench/adapters/dom.ts` mirrors `adapters/xterm.ts`: it mounts a surface into the harness page, exposes `write(bytes)` and a completion signal, and reports its renderer identity. It creates the core with `createTerminalCore({ columns: 120, scrollback: 5000 })` to match `bench/scenarios.json`, mounts a `DomBlockRenderer` over it, and feeds bytes straight into `core.feed`.

- [ ] **Step 5: Run both renderers on one scenario**

```bash
npm --prefix packages/terminal run bench:terminal -- --renderer xterm --scenario vtebench
npm --prefix packages/terminal run bench:terminal -- --renderer dom --scenario vtebench
```

Expected: both exit 0 and print a number. **The `dom` number is expected to be worse right now** — Task 2 has not virtualized anything and Finding 3's Rust-side cost is untouched. Record both; do not act on them yet.

- [ ] **Step 6: Commit**

```bash
git add packages/terminal/bench
git commit -m "test(terminal): add the DOM renderer to the bench harness"
```

---

### Task 2: Virtualize the block list

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/viewport.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/styles.css`
- Test: `packages/terminal/ts/renderer-dom/src/viewport.test.ts`
- Test: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts` (extend)

**Interfaces:**
- Produces `computeWindow(input: WindowInput): WindowResult`.

```ts
export type WindowInput = Readonly<{
	blocks: readonly BlockView[];
	scrollTop: number;
	viewportHeight: number;
	rowHeight: number;
	headerHeight: number;
	overscanRows: number;
}>;

export type WindowResult = Readonly<{
	firstBlock: number;
	lastBlock: number;
	leadingSpacer: number;
	trailingSpacer: number;
	rowWindows: ReadonlyMap<number, { firstRow: number; lastRow: number }>;
}>;
```

`computeWindow` is a pure function with no DOM, which is why it can be tested exhaustively and why the renderer stays testable in jsdom.

- [ ] **Step 1: Write the viewport tests**

```ts
import { describe, expect, it } from "vitest";
import { computeWindow } from "./viewport";

function blocks(counts: number[]) {
	let firstRow = 0;
	return counts.map((rowCount, index) => {
		const block = {
			id: `0:${index}`,
			firstRow,
			rowCount,
			state: "finished" as const,
			source: "osc133" as const,
			exitCode: 0,
			durationMs: null,
			command: "",
			cwd: "",
			gitBranch: "",
		};
		firstRow += rowCount;
		return block;
	});
}

const base = { rowHeight: 20, headerHeight: 24, overscanRows: 2, viewportHeight: 100 };

describe("computeWindow", () => {
	it("selects only the blocks intersecting the viewport", () => {
		const result = computeWindow({ ...base, blocks: blocks([2, 2, 2, 2, 2]), scrollTop: 0 });
		expect(result.firstBlock).toBe(0);
		expect(result.lastBlock).toBeLessThan(4);
	});

	it("skips blocks entirely above the viewport and reports a leading spacer", () => {
		const result = computeWindow({ ...base, blocks: blocks([2, 2, 2, 2, 2]), scrollTop: 200 });
		expect(result.firstBlock).toBeGreaterThan(0);
		expect(result.leadingSpacer).toBeGreaterThan(0);
	});

	it("windows rows inside a single very tall block", () => {
		const result = computeWindow({ ...base, blocks: blocks([10_000]), scrollTop: 40_000 });
		expect(result.firstBlock).toBe(0);
		expect(result.lastBlock).toBe(0);
		const window = result.rowWindows.get(0);
		expect(window).toBeDefined();
		expect(window!.lastRow - window!.firstRow).toBeLessThan(20);
		expect(window!.firstRow).toBeGreaterThan(1_000);
	});

	it("spacers plus rendered height equal the total content height", () => {
		const list = blocks([3, 7, 5, 11]);
		const result = computeWindow({ ...base, blocks: list, scrollTop: 60 });
		const total = list.reduce((sum, b) => sum + b.rowCount * 20 + 24, 0);
		let rendered = 0;
		for (let i = result.firstBlock; i <= result.lastBlock; i += 1) {
			rendered += list[i].rowCount * 20 + 24;
		}
		expect(result.leadingSpacer + rendered + result.trailingSpacer).toBe(total);
	});

	it("an empty block list produces an empty window", () => {
		const result = computeWindow({ ...base, blocks: [], scrollTop: 0 });
		expect(result.firstBlock).toBe(0);
		expect(result.lastBlock).toBe(-1);
		expect(result.leadingSpacer).toBe(0);
		expect(result.trailingSpacer).toBe(0);
	});

	it("clamps a scrollTop past the end instead of producing a negative window", () => {
		const result = computeWindow({ ...base, blocks: blocks([2, 2]), scrollTop: 999_999 });
		expect(result.firstBlock).toBeLessThanOrEqual(result.lastBlock);
		expect(result.trailingSpacer).toBeGreaterThanOrEqual(0);
	});
});
```

- [ ] **Step 2: Run and confirm red**

Run: `npx vitest run --root packages/terminal/ts/renderer-dom viewport`
Expected: FAIL — `computeWindow` does not exist.

- [ ] **Step 3: Implement `computeWindow`**

Walk the block list accumulating height (`rowCount * rowHeight + headerHeight`) until the accumulated height passes `scrollTop`; that is `firstBlock` and the accumulated height before it is `leadingSpacer`. Continue until the accumulated height passes `scrollTop + viewportHeight`; that is `lastBlock`, and everything after it sums into `trailingSpacer`. For any selected block taller than the viewport, compute a row window inside it with `overscanRows` on each side.

**This walk is O(number of blocks), not O(rows).** That is acceptable at 50,000 blocks and is the reason `BlockView` carries `rowCount` — the caller never touches row data to lay out.

- [ ] **Step 4: Rewrite `repaint()` to use it**

`repaint()` reads `decodeBlocks(snapshot)`, calls `computeWindow` with the container's current `scrollTop` and `clientHeight` and the measured cell metrics, then builds DOM only for the selected blocks and, within them, the selected rows. Leading and trailing spacers are two `div`s with an explicit `height` so the scrollbar reflects the whole content.

Attach a `scroll` listener on the container that calls `repaint()`. Coalesce both the scroll and the `onChange` repaints through one `requestAnimationFrame` so a burst of feeds paints once per frame.

Rows are still built from `content.subarray(...)` — **no JS object per cell** (Global Constraints, wrong turn 1).

- [ ] **Step 5: Extend the renderer tests**

Add to `dom-block-renderer.test.ts`:

```ts
it("renders only the visible slice of a tall block", () => {
	const container = document.createElement("div");
	Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
	const core = createTerminalCore({ columns: 20, scrollback: 100_000 });
	for (let i = 0; i < 5_000; i += 1) {
		core.feed(new TextEncoder().encode(`line ${i}\n`));
	}
	const renderer = new DomBlockRenderer();
	renderer.mount(container, core);

	const rows = container.querySelectorAll("[data-terminal-row]");
	expect(rows.length).toBeLessThan(60);
	expect(rows.length).toBeGreaterThan(0);
	renderer.dispose();
});
```

- [ ] **Step 6: Run every renderer test and the gates**

```bash
npm --prefix packages/terminal test
npm --prefix packages/terminal run check:boundaries
npm --prefix packages/terminal run bench:terminal -- --renderer dom --scenario large-output
```

Expected: tests pass; the `large-output` number improves materially against Task 1 Step 5's recording. Record it.

- [ ] **Step 7: Commit**

```bash
git add packages/terminal/ts/renderer-dom
git commit -m "feat(terminal): virtualize the block list by block and by row"
```

---

### Task 3: Warp-style block headers

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/block-header.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/{dom-block-renderer.ts,styles.css}`
- Modify: `packages/terminal/ts/core/src/types.ts` (add `TerminalStrings`)
- Test: `packages/terminal/ts/renderer-dom/src/block-header.test.ts`

**Interfaces:**
- Produces `renderBlockHeader(block: BlockView, strings: TerminalStrings): HTMLElement`.
- Produces `TerminalStrings`, a flat object of English defaults a host may override:

```ts
export type TerminalStrings = Readonly<{
	blockRunning: string;
	blockSucceeded: string;
	blockFailed: string;
	blockAbandoned: string;
	copyCommand: string;
	copyOutput: string;
	rerunCommand: string;
	shellBlocksUnavailable: string;
}>;
```

The package ships English defaults and **no locale files**. Operator's eight-locale duty is Task 7.

- [ ] **Step 1: Write the header tests**

```ts
import { describe, expect, it } from "vitest";
import { defaultStrings } from "@operator/terminal-core";
import { renderBlockHeader } from "./block-header";

const base = {
	id: "0:1",
	firstRow: 0,
	rowCount: 2,
	source: "extension" as const,
	command: "git status",
	cwd: "/Users/me/project",
	gitBranch: "main",
};

describe("renderBlockHeader", () => {
	it("shows the command, cwd and branch", () => {
		const el = renderBlockHeader(
			{ ...base, state: "finished", exitCode: 0, durationMs: 1200 },
			defaultStrings,
		);
		expect(el.textContent).toContain("git status");
		expect(el.textContent).toContain("main");
	});

	it("marks a non-zero exit as failed and shows the code", () => {
		const el = renderBlockHeader(
			{ ...base, state: "finished", exitCode: 127, durationMs: 5 },
			defaultStrings,
		);
		expect(el.dataset.blockStatus).toBe("failed");
		expect(el.textContent).toContain("127");
	});

	it("marks exit zero as succeeded", () => {
		const el = renderBlockHeader(
			{ ...base, state: "finished", exitCode: 0, durationMs: 5 },
			defaultStrings,
		);
		expect(el.dataset.blockStatus).toBe("succeeded");
	});

	it("marks a running block as running and shows no exit code", () => {
		const el = renderBlockHeader(
			{ ...base, state: "running", exitCode: null, durationMs: null },
			defaultStrings,
		);
		expect(el.dataset.blockStatus).toBe("running");
		expect(el.textContent).not.toContain("null");
	});

	it("marks an abandoned block distinctly from a failed one", () => {
		const el = renderBlockHeader(
			{ ...base, state: "abandoned", exitCode: null, durationMs: null },
			defaultStrings,
		);
		expect(el.dataset.blockStatus).toBe("abandoned");
	});

	it("renders a synthetic block without a header chrome row", () => {
		const el = renderBlockHeader(
			{ ...base, source: "synthetic", state: "running", exitCode: null, durationMs: null, command: "" },
			defaultStrings,
		);
		expect(el.dataset.blockStatus).toBe("plain");
	});

	it("escapes command text rather than interpreting it as markup", () => {
		const el = renderBlockHeader(
			{ ...base, state: "finished", exitCode: 0, durationMs: 1, command: "<img src=x onerror=1>" },
			defaultStrings,
		);
		expect(el.querySelector("img")).toBeNull();
		expect(el.textContent).toContain("<img");
	});

	it("formats sub-second and multi-second durations differently", () => {
		const fast = renderBlockHeader({ ...base, state: "finished", exitCode: 0, durationMs: 42 }, defaultStrings);
		const slow = renderBlockHeader({ ...base, state: "finished", exitCode: 0, durationMs: 92_000 }, defaultStrings);
		expect(fast.textContent).toContain("42ms");
		expect(slow.textContent).toContain("1m");
	});
});
```

The escaping test is not decoration: command text is arbitrary bytes from the user's terminal, and the header is the first place it becomes markup-adjacent. Build the header with `textContent` and `createElement`, never `innerHTML`.

- [ ] **Step 2: Run and confirm red**

Run: `npx vitest run --root packages/terminal/ts/renderer-dom block-header`
Expected: FAIL — module does not exist.

- [ ] **Step 3: Implement the header**

A `header` element carrying `data-block-status` of `running | succeeded | failed | abandoned | plain`, a status dot, the command, the cwd shortened with a leading tilde for `$HOME` when the host supplies it, the branch, and the duration. A `synthetic` block gets `plain` and renders no chrome — output that arrived with no marks must not pretend to be a command.

- [ ] **Step 4: Style it to match Warp**

In `styles.css`: rounded block card, hairline border in `--terminal-block-border`, header row in `--terminal-block-header-foreground`, status dot coloured from the ANSI palette (green 2 for succeeded, red 1 for failed, yellow 3 for running, bright black 8 for abandoned). Keep the terminal's own palette per `DESIGN.md:36`.

- [ ] **Step 5: Run tests and commit**

```bash
npm --prefix packages/terminal test
git add packages/terminal/ts
git commit -m "feat(terminal): add Warp-style block headers"
```

---

### Task 4: Per-block selection, copy, and hover actions

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/{selection.ts,block-actions.ts}`
- Modify: `packages/terminal/ts/renderer-dom/src/{dom-block-renderer.ts,styles.css}`
- Test: `packages/terminal/ts/renderer-dom/src/{selection.test.ts,block-actions.test.ts}`

**Interfaces:**
- Produces `selectionToBlockRange(root: HTMLElement, selection: Selection): BlockRange | null`.
- Produces `renderBlockActions(block: BlockView, host: HostCapabilities, strings: TerminalStrings, text: BlockTextSource): HTMLElement`.
- `BlockTextSource = { command(id: BlockId): string; output(id: BlockId): string }` — the renderer supplies it; actions never reach into the core.

- [ ] **Step 1: Write the selection tests**

```ts
import { describe, expect, it } from "vitest";
import { selectionToBlockRange } from "./selection";

function fixture(): HTMLElement {
	const root = document.createElement("div");
	root.innerHTML = "";
	for (const id of ["0:1", "0:2"]) {
		const block = document.createElement("section");
		block.dataset.terminalBlockId = id;
		for (let r = 0; r < 2; r += 1) {
			const row = document.createElement("div");
			row.dataset.terminalRow = String(r);
			row.textContent = `block ${id} row ${r}`;
			block.append(row);
		}
		root.append(block);
	}
	document.body.append(root);
	return root;
}

describe("selectionToBlockRange", () => {
	it("returns null when nothing is selected", () => {
		const root = fixture();
		expect(selectionToBlockRange(root, window.getSelection()!)).toBeNull();
	});

	it("maps a selection inside one block to that block", () => {
		const root = fixture();
		const row = root.querySelector("[data-terminal-row]")!;
		const range = document.createRange();
		range.selectNodeContents(row);
		const selection = window.getSelection()!;
		selection.removeAllRanges();
		selection.addRange(range);

		const result = selectionToBlockRange(root, selection);
		expect(result?.startBlock).toBe("0:1");
		expect(result?.endBlock).toBe("0:1");
	});

	it("maps a selection spanning two blocks to both ends", () => {
		const root = fixture();
		const rows = root.querySelectorAll("[data-terminal-row]");
		const range = document.createRange();
		range.setStart(rows[0], 0);
		range.setEnd(rows[3], 0);
		const selection = window.getSelection()!;
		selection.removeAllRanges();
		selection.addRange(range);

		const result = selectionToBlockRange(root, selection);
		expect(result?.startBlock).toBe("0:1");
		expect(result?.endBlock).toBe("0:2");
	});
});
```

Native browser selection is the reason this design chose DOM (spec §9.3). We **map** it rather than reimplement it — no custom hit-testing, no synthetic caret.

- [ ] **Step 2: Run and confirm red**

Run: `npx vitest run --root packages/terminal/ts/renderer-dom selection`
Expected: FAIL — module does not exist.

- [ ] **Step 3: Implement selection mapping**

Walk up from `selection.anchorNode` and `selection.focusNode` to the nearest `[data-terminal-block-id]`, and return `{ startBlock, endBlock }` in document order. Return `null` when the selection is collapsed or lands outside `root`.

- [ ] **Step 4: Write the action tests**

```ts
import { describe, expect, it, vi } from "vitest";
import { defaultStrings } from "@operator/terminal-core";
import { renderBlockActions } from "./block-actions";

const block = {
	id: "0:1", firstRow: 0, rowCount: 1, state: "finished" as const,
	source: "extension" as const, exitCode: 0, durationMs: 1,
	command: "ls -la", cwd: "/tmp", gitBranch: "main",
};

const text = { command: () => "ls -la", output: () => "a.txt\nb.txt" };

describe("renderBlockActions", () => {
	it("copies the command through the host clipboard", async () => {
		const writeClipboard = vi.fn().mockResolvedValue(undefined);
		const el = renderBlockActions(block, { writeClipboard } as never, defaultStrings, text);
		el.querySelector<HTMLButtonElement>("[data-action='copy-command']")!.click();
		expect(writeClipboard).toHaveBeenCalledWith("ls -la");
	});

	it("copies the output through the host clipboard", () => {
		const writeClipboard = vi.fn().mockResolvedValue(undefined);
		const el = renderBlockActions(block, { writeClipboard } as never, defaultStrings, text);
		el.querySelector<HTMLButtonElement>("[data-action='copy-output']")!.click();
		expect(writeClipboard).toHaveBeenCalledWith("a.txt\nb.txt");
	});

	it("offers no rerun action on a synthetic block", () => {
		const el = renderBlockActions(
			{ ...block, source: "synthetic", command: "" },
			{ writeClipboard: vi.fn() } as never,
			defaultStrings,
			text,
		);
		expect(el.querySelector("[data-action='rerun']")).toBeNull();
	});

	it("every action is a real button reachable by keyboard", () => {
		const el = renderBlockActions(block, { writeClipboard: vi.fn() } as never, defaultStrings, text);
		for (const node of el.querySelectorAll("[data-action]")) {
			expect(node.tagName).toBe("BUTTON");
			expect(node.getAttribute("aria-label")).toBeTruthy();
		}
	});
});
```

- [ ] **Step 5: Implement the actions and wire them in**

Actions are real `<button>` elements with `aria-label`, revealed on block hover and on focus-within so keyboard users reach them. A `synthetic` block offers copy-output only — it has no command to copy or rerun. **Rerun emits an event the host handles; the package never writes to the transport on its own.**

- [ ] **Step 6: Run tests, gates, and commit**

```bash
npm --prefix packages/terminal test
npm --prefix packages/terminal run check:boundaries
git add packages/terminal/ts
git commit -m "feat(terminal): add per-block selection, copy, and hover actions"
```

---

### Task 5: The alt-screen handoff seam

**Files:**
- Create: `packages/terminal/ts/react/src/AltScreenSlot.tsx`
- Modify: `packages/terminal/ts/react/src/{TerminalSurface.tsx,index.ts}`
- Modify: `packages/terminal/ts/core/src/types.ts`
- Test: `packages/terminal/ts/react/src/TerminalSurface.test.tsx` (extend)

**Interfaces:**
- `TerminalSurfaceProps` gains `altScreenSurface?: ReactNode` and `altScreenActive: boolean`.
- The package renders `altScreenSurface` in place of the block list while `altScreenActive` is true, and keeps the block list mounted but hidden so returning does not lose scroll position.

**The package does not own `XtermTerminal`.** It exposes the slot; Operator fills it (Task 7). A different host fills it with something else, or with nothing, in which case the pane shows the raw grid it already has.

- [ ] **Step 1: Write the tests**

```tsx
it("shows the alt-screen surface instead of the block list when active", () => {
	render(
		<TerminalSurface
			core={core}
			theme={theme}
			font={font}
			altScreenActive
			altScreenSurface={<div data-testid="raw-surface" />}
		/>,
	);
	expect(screen.getByTestId("raw-surface")).toBeVisible();
	expect(screen.getByTestId("terminal-block-list")).not.toBeVisible();
});

it("returns to the block list when the alt screen exits", () => {
	const { rerender } = render(
		<TerminalSurface core={core} theme={theme} font={font} altScreenActive
			altScreenSurface={<div data-testid="raw-surface" />} />,
	);
	rerender(
		<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false}
			altScreenSurface={<div data-testid="raw-surface" />} />,
	);
	expect(screen.getByTestId("terminal-block-list")).toBeVisible();
});

it("keeps the block list mounted while the alt screen is active", () => {
	render(
		<TerminalSurface core={core} theme={theme} font={font} altScreenActive
			altScreenSurface={<div data-testid="raw-surface" />} />,
	);
	expect(screen.getByTestId("terminal-block-list")).toBeInTheDocument();
});

it("falls back to the block list when no alt-screen surface is supplied", () => {
	render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive />);
	expect(screen.getByTestId("terminal-block-list")).toBeVisible();
});
```

Hiding rather than unmounting is what makes returning from `vim` land you where you were. Unmounting throws away scroll position and every DOM node the virtualizer built.

- [ ] **Step 2: Run, implement, run again**

Run: `npx vitest run --root packages/terminal/ts/react`
Expected: FAIL, then PASS after `AltScreenSlot` renders the two children with `hidden` toggled.

- [ ] **Step 3: Commit**

```bash
git add packages/terminal/ts/react packages/terminal/ts/core
git commit -m "feat(terminal): add the alt-screen surface slot"
```

---

### Task 6: Daemon-side block capture via `tmux pipe-pane`

**Depends on Phase 1a Task 6 (`go/marks`) being merged.** Do not start before it.

**Files:**
- Modify: `backend/internal/adapters/runtime/tmux/commands.go`
- Create: `backend/internal/adapters/runtime/tmux/pipepane.go`
- Create: `backend/internal/adapters/runtime/tmux/pipepane_test.go`
- Create: `backend/internal/service/blockevent/shell.go`
- Create: `backend/internal/service/blockevent/shell_test.go`
- Modify: `backend/internal/service/shellterm/service.go`
- Modify: `backend/go.mod` (require the `go/marks` module via a `replace` to `../packages/terminal/go/marks`)

**Interfaces:**
- Produces `tmux.PipePaneArgs(paneID, command string) []string`.
- Produces `blockevent.Service.RecordShellBlock(ctx, sessionID domain.SessionID, block ShellBlock) error`, a **second entry point** beside `Record`.

```go
// ShellBlock is one completed shell block, as the mark decoder saw it.
// It is deliberately not an ActivitySignal: a shell command is not a hook,
// and a SourceID carrying a command counter through ToolUseID is a lie that
// costs a week later.
type ShellBlock struct {
    SourceID  string
    Command   string
    Cwd       string
    Branch    string
    ExitCode  *int
    Output    []byte
    StartedAt time.Time
    EndedAt   time.Time
}
```

- [ ] **Step 1: Write the pipe-pane argument test**

```go
func TestPipePaneArgsTargetsThePaneAndStreamsToTheCommand(t *testing.T) {
	got := PipePaneArgs("%3", "cat > /tmp/x")
	want := []string{"pipe-pane", "-o", "-t", "%3", "cat > /tmp/x"}
	if !slices.Equal(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func TestPipePaneArgsWithAnEmptyCommandStopsPiping() {
	got := PipePaneArgs("%3", "")
	want := []string{"pipe-pane", "-t", "%3"}
	if !slices.Equal(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}
```

`-o` makes the pipe toggle-safe: tmux only starts a new pipe if one is not already running, which is what stops a reconnect from attaching a second reader and recording every block twice.

- [ ] **Step 2: Run and confirm red**

Run: `cd backend && go test ./internal/adapters/runtime/tmux/...`
Expected: FAIL — `PipePaneArgs` undefined.

- [ ] **Step 3: Implement the args and the reader**

`PipePaneArgs` goes beside `capturePaneArgs` (`commands.go:123`) in the same style. `pipepane.go` starts the pipe pointing at a long-lived reader owned by the daemon, feeds every byte through `marks.Decoder`, and assembles `ShellBlock` values from the event stream.

**Capture suspends between `AltScreenEnter` and `AltScreenLeave`.** A full-screen TUI's redraws are not block output, and recording them would fill the store with screen paint.

**Bound the output buffer.** A single block's captured output is capped; past the cap the block records what it has plus a truncation count, exactly as `blockevent.Record` already does for hook events (`TruncatedLines` in `types.go`). A `yes` loop must not grow the daemon without limit.

- [ ] **Step 4: Write the second entry point's test**

```go
func TestRecordShellBlockDoesNotBorrowToolFields(t *testing.T) {
	store := &fakeStore{}
	svc := NewService(store, &fakePublisher{}, 100)
	exit := 0
	err := svc.RecordShellBlock(context.Background(), "s1", ShellBlock{
		SourceID: "block-7", Command: "ls", ExitCode: &exit, Output: []byte("a.txt"),
	})
	if err != nil {
		t.Fatal(err)
	}
	rec := store.records[0]
	if rec.SourceID != "block-7" {
		t.Fatalf("SourceID = %q", rec.SourceID)
	}
	if rec.ToolUseID != "" || rec.ToolName != "" {
		t.Fatal("a shell block must not populate tool fields")
	}
}

func TestRecordShellBlockRedactsSecretsLikeEveryOtherRecord(t *testing.T) {
	store := &fakeStore{}
	svc := NewService(store, &fakePublisher{}, 100)
	err := svc.RecordShellBlock(context.Background(), "s1", ShellBlock{
		SourceID: "block-8", Command: "echo", Output: []byte("export TOKEN=ghp_0123456789abcdefghij"),
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(store.records[0].RedactedSpans) == 0 {
		t.Fatal("shell block output must go through the same redaction as hook events")
	}
}
```

The redaction test matters: `Service.Record` already redacts, truncates, persists, trims and publishes. `RecordShellBlock` must reuse that pipeline rather than write to the store directly, or shell blocks become the one path where secrets are stored in the clear.

- [ ] **Step 5: Implement `RecordShellBlock`**

It maps `ShellBlock` onto `Record` and calls the same internal persist-and-publish path `Record` uses. `SourceID` is the mark's block id — never invented here, per the comment already at `types.go:14-17`.

- [ ] **Step 6: Spawn with the package's recipe**

`shellterm/service.go` asks the package for the argv and env instead of using the bare `[$SHELL]` from `loginshell.go:20`. The Go side reads `packages/terminal/shell/zsh.sh` as an asset and builds the same recipe `spawnRecipe` returns; it does **not** re-implement the protocol.

**Non-zsh shells and Windows get the bare shell and no bootstrap.** They still produce Tier-1 blocks if the user's own config emits OSC 133, and no blocks otherwise. On Windows the session opens the raw grid and reports shell blocks unavailable — the visible-absence rule, not a silent degrade.

- [ ] **Step 7: Prove the two capture invariants**

```go
func TestZeroClientsAttachedStillRecordsBlocks(t *testing.T) {
	requireTmux(t)
	env := startSession(t)
	// No client ever attaches. This is the case that recorded nothing under
	// the spec's original in-band design.
	env.RunCommand("echo hello")
	blocks := env.WaitForBlocks(t, 1)
	if got := string(blocks[0].Text); !strings.Contains(got, "hello") {
		t.Fatalf("block text = %q, want it to contain hello", got)
	}
}

func TestTwoClientsAttachedRecordEachBlockExactlyOnce(t *testing.T) {
	requireTmux(t)
	env := startSession(t)
	first := env.Attach(t)
	defer first.Close()
	second := env.Attach(t)
	defer second.Close()

	env.RunCommand("echo twice")

	blocks := env.WaitForBlocks(t, 1)
	matching := 0
	for _, block := range blocks {
		if strings.Contains(string(block.Text), "twice") {
			matching++
		}
	}
	if matching != 1 {
		t.Fatalf("recorded the block %d times with two clients attached, want 1", matching)
	}
}

func requireTmux(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("tmux"); err != nil {
		t.Skip("tmux is not installed")
	}
}
```

These are the two failures that killed the spec's original in-band design (§13.1) and they are the reason `pipe-pane` was chosen. They must be real integration tests against a live tmux, skipped with a clear message when tmux is absent.

- [ ] **Step 8: Run the gates and commit**

```bash
npm run lint
git add backend packages/terminal
git commit -m "feat(terminal): record shell blocks server-side via tmux pipe-pane"
```

---

### Task 7: Mount the package in Operator

**Files:**
- Create: `frontend/src/renderer/components/BlockTerminal.tsx`
- Create: `frontend/src/renderer/components/BlockTerminal.test.tsx`
- Modify: `frontend/src/renderer/components/TerminalPane.tsx`
- Modify: `frontend/src/renderer/i18n/*.json` (all eight)

**Interfaces:**
- `BlockTerminal` is the only file that knows both Operator and the package. It builds a `PtyTransport` over the existing mux terminal channel, derives `TerminalTheme` from the skin, supplies `HostCapabilities` from Operator's clipboard and `lib/external-link-policy.ts`, passes Operator's translations as `TerminalStrings`, and hands `XtermTerminal` in as `altScreenSurface`.

- [ ] **Step 1: Write the adapter tests**

```tsx
import { render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { BlockTerminal } from "./BlockTerminal";

function harness(overrides: Partial<Parameters<typeof BlockTerminal>[0]> = {}) {
	const listeners: Array<(bytes: Uint8Array) => void> = [];
	const transport = {
		write: vi.fn(),
		onData: (cb: (bytes: Uint8Array) => void) => {
			listeners.push(cb);
			return () => {};
		},
		resize: vi.fn(),
		dispose: vi.fn(),
	};
	const emit = (text: string) => listeners.forEach((cb) => cb(new TextEncoder().encode(text)));
	return { transport, emit, overrides };
}

describe("BlockTerminal", () => {
	it("feeds bytes from the mux channel into the core", async () => {
		const { transport, emit } = harness();
		render(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
		emit("\x1b]133;A\x07\x1b]133;C\x07hello\n\x1b]133;D;0\x07");
		await waitFor(() => expect(screen.getByText(/hello/)).toBeInTheDocument());
	});

	it("passes XtermTerminal as the alt-screen surface", async () => {
		const { transport, emit } = harness();
		render(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
		emit("\x1b[?1049h");
		await waitFor(() => expect(screen.getByTestId("xterm-surface")).toBeVisible());
	});

	it("routes copy actions through Operator's clipboard bridge", async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		const { transport, emit } = harness();
		render(
			<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} clipboard={{ writeText }} />,
		);
		emit("\x1b]133;A\x07\x1b]7000;v=1;cmd=ls\x07\x1b]133;C\x07a.txt\n\x1b]133;D;0\x07");
		const button = await screen.findByRole("button", { name: /copy command/i });
		button.click();
		await waitFor(() => expect(writeText).toHaveBeenCalledWith("ls"));
	});

	it("renders history blocks before any live block arrives", async () => {
		const { transport } = harness();
		render(
			<BlockTerminal
				transport={transport}
				sessionId="s1"
				historyBlocks={[{ sourceId: "block-1", command: "git log", text: "commit abc", exitCode: 0 }]}
			/>,
		);
		expect(await screen.findByText(/git log/)).toBeInTheDocument();
	});

	it("does not duplicate a block present in both history and the live stream", async () => {
		const { transport, emit } = harness();
		render(
			<BlockTerminal
				transport={transport}
				sessionId="s1"
				historyBlocks={[{ sourceId: "block-1", command: "git log", text: "commit abc", exitCode: 0 }]}
			/>,
		);
		emit("\x1b]133;A\x07\x1b]7000;v=1;id=block-1;cmd=git%20log\x07\x1b]133;C\x07commit abc\n\x1b]133;D;0\x07");
		await waitFor(() => expect(screen.getAllByText(/git log/)).toHaveLength(1));
	});
});
```

The last two are the convergence requirement from spec §13.3: history comes from `GET /sessions/{id}/blocks` and live blocks come from the package's own parse of the same stream. Both paths must land on the same `BlockId`, which is why block-id continuity is a Tier-2 field (spec §7.2). Deduplicate on that id, not on position.

- [ ] **Step 2: Run and confirm red**

Run: `npm --prefix frontend test -- BlockTerminal`
Expected: FAIL — component does not exist.

- [ ] **Step 3: Implement `BlockTerminal`**

Import from `@operator/terminal-react` **by package name** (Global Constraints). Do not reach into `packages/terminal` by relative path — `check:boundaries` guards the package side, and this is the side it cannot see.

- [ ] **Step 4: Swap the mount in `TerminalPane`**

`TerminalPane.tsx:47` lazily imports `XtermTerminal` and mounts it at `:1075`. Mount `BlockTerminal` there instead, passing the lazy `XtermTerminal` down as the alt-screen surface. `useTerminalSession`, the mux transport and the retained-handle cache underneath are **untouched** — this phase changes what paints, not how the session attaches.

- [ ] **Step 5: Add every new string to all eight locales**

```bash
node -e "
const fs=require('fs');const d='frontend/src/renderer/i18n';
const en=JSON.parse(fs.readFileSync(d+'/en.json'));
for (const f of fs.readdirSync(d).filter(f=>f.endsWith('.json'))) {
  const o=JSON.parse(fs.readFileSync(d+'/'+f));
  const missing=Object.keys(en).filter(k=>!(k in o)||!o[k]);
  if (missing.length) { console.error(f, 'missing/empty:', missing); process.exit(1); }
}
console.log('all eight locales complete');
"
```

Expected: exit 0.

- [ ] **Step 6: See it in the real app**

```bash
cd frontend && npm run tauri:dev
```

Open a session. You should see block cards with headers, hover actions, and a working shell. Run `vim`, confirm the pane hands over and hands back. Then:

```bash
opr preview
```

Report what you saw. **A screenshot or a description of the actual pane is the deliverable of this step** — not "the tests pass".

- [ ] **Step 7: Run the gates and commit**

```bash
npm run frontend:typecheck
npm --prefix frontend test
npm run lint
git add frontend
git commit -m "feat(terminal): mount the block terminal as the session pane"
```

---

### Task 8: Meet the perf gate

**Depends on all of Phase 1a being merged.** This is the only 1b task that touches `crates/`. Rebase onto master first.

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/{lib.rs,grid.rs}`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs`
- Modify: `packages/terminal/ts/core/src/{terminal-core.ts,types.ts}`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts`
- Test: `packages/terminal/crates/vt-core/tests/windowed_rows.rs`

**Interfaces:**
- Produces `TerminalCore::snapshot_window(&self, first_row: usize, row_count: usize) -> Result<GridSnapshot, CoreError>`.
- Produces `WasmTerminalCore::refresh_window(first_row: usize, row_count: usize) -> Result<(), JsError>`.
- Produces TypeScript `TerminalCore.snapshotWindow(firstRow: number, rowCount: number): TerminalSnapshot`.

**The problem this solves, stated plainly.** Phase 1a Finding 3 left `build_snapshot` rebuilding every row on every feed. Task 2's virtualizer fixed the DOM cost but not that one: at 50,000 blocks the Rust side still copies every row into the snapshot on each feed, so `large-output` and the 60fps criterion cannot both pass. The renderer only ever paints a window, so the core should only ever build one.

**Block records stay whole.** `snapshot_window` narrows *rows*, never blocks — the virtualizer needs every block's `rowCount` to lay out, and 50,000 fourteen-word records is 2.8 MB, which is cheap. Narrowing blocks too would make the scrollbar wrong.

- [ ] **Step 1: Write the windowing tests**

```rust
#[test]
fn a_window_returns_only_the_requested_rows_with_correct_text() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    for index in 0..100 {
        core.feed(format!("row{index:03}\n").as_bytes());
    }
    let window = core.snapshot_window(10, 5).unwrap();
    assert_eq!(window.row_count(), 5);
    assert_eq!(window.row_text(0), "row010");
    assert_eq!(window.row_text(4), "row014");
}

#[test]
fn a_window_carries_every_block_regardless_of_the_row_range() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    for index in 0..40 {
        core.feed(format!("\x1b]133;A\x07\x1b]133;C\x07row{index:03}\n\x1b]133;D;0\x07").as_bytes());
    }
    let all = core.snapshot().unwrap().blocks.len();
    let window = core.snapshot_window(0, 3).unwrap();
    assert_eq!(window.blocks.len(), all, "blocks are never narrowed");
}

#[test]
fn a_window_past_the_end_is_empty_rather_than_an_error() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    core.feed(b"only\n");
    assert_eq!(core.snapshot_window(500, 10).unwrap().row_count(), 0);
}

#[test]
fn a_window_clamps_when_it_overruns_the_end() {
    let mut core = TerminalCore::new(20, 1000).unwrap();
    for index in 0..5 {
        core.feed(format!("row{index}\n").as_bytes());
    }
    assert_eq!(core.snapshot_window(3, 100).unwrap().row_count(), 3);
}
```

- [ ] **Step 2: Run, implement, run again**

`build_snapshot` gains a row range and `snapshot()` becomes `snapshot_window(0, usize::MAX)` so every existing caller and test keeps working unchanged. The renderer calls `snapshotWindow` with the range `computeWindow` just produced, plus overscan.

- [ ] **Step 3: Run the gate against the recorded xterm baseline**

```bash
npm --prefix packages/terminal run bench:terminal -- --renderer dom --scenario large-output
npm --prefix packages/terminal run bench:terminal -- --renderer dom --scenario vtebench
npm --prefix packages/terminal run bench:terminal -- --renderer dom --scenario input-latency
```

Against `bench/baselines/darwin-arm64-xterm.json`, the spec's §9.4 gate is:

| Scenario | Requirement |
| --- | --- |
| `large-output` | at or above the xterm baseline |
| `input-latency` | p95 at or below the xterm baseline |
| `vtebench` | at least 0.9x the xterm baseline |

**If a gate misses after honest optimisation, stop and report the numbers.** That is the documented trigger for a WebGL renderer behind the `BlockRenderer` interface (spec §9.4) — a decision for the user, not for this plan. Do not reach for a canvas fast-path inside a DOM block (wrong turn 11).

- [ ] **Step 4: Prove the 50,000-block criterion**

Add a Playwright scenario under `packages/terminal/bench/` that drives the real renderer:

```ts
test("scrolling fifty thousand blocks holds 60fps", async ({ page }) => {
	await page.goto(benchUrl);
	await page.evaluate(async () => {
		const core = window.__benchCore;
		const encoder = new TextEncoder();
		for (let i = 0; i < 50_000; i += 1) {
			core.feed(encoder.encode(`\x1b]133;A\x07\x1b]133;C\x07row ${i}\n\x1b]133;D;0\x07`));
		}
	});

	const frames: number[] = await page.evaluate(async () => {
		const container = document.querySelector("[data-testid='terminal-block-list']")!;
		const samples: number[] = [];
		let last = performance.now();
		for (let step = 0; step < 120; step += 1) {
			container.scrollTop += container.clientHeight;
			await new Promise((resolve) => requestAnimationFrame(resolve));
			const now = performance.now();
			samples.push(now - last);
			last = now;
		}
		return samples;
	});

	frames.sort((a, b) => a - b);
	const p95 = frames[Math.floor(frames.length * 0.95)];
	expect(p95).toBeLessThan(16.7);
});
```

Criterion: no frame over 16.7ms at the 95th percentile on the reference machine.

- [ ] **Step 5: Record the DOM baseline and commit**

```bash
npm --prefix packages/terminal run bench:baseline -- --renderer dom --record
git add packages/terminal
git commit -m "perf(terminal): build only the rows the renderer paints"
```

---

### Task 9: Close Phase 1

**Files:**
- Modify: `packages/terminal/{CHANGELOG.md,README.md}`
- Modify: `.github/workflows/terminal.yml`

- [ ] **Step 1: Add the DOM bench job to CI**

Add a job that runs `--renderer dom --scenario large-output` and fails when the number falls under the recorded xterm baseline. A perf gate nobody runs is not a gate.

- [ ] **Step 2: Run the full matrix from a clean tree**

Everything Phase 1a Task 11 Step 2 lists, plus:

```bash
cd packages/terminal/go/marks && go test ./... && go vet ./... && cd -
npm --prefix frontend test
npm --prefix packages/terminal run bench:terminal -- --renderer dom --scenario large-output
```

Expected: every command exits 0.

- [ ] **Step 3: Prove every Phase 1 acceptance criterion**

Now the whole spec §14 Phase 1 list can be claimed, and each needs a named proof:

| Spec criterion | Proven by |
| --- | --- |
| OSC 133 alone produces correct blocks | 1a `blocks_from_marks.rs` |
| every recovery row has a vector in both decoders | 1a `marks/tests/vectors.rs`, `go/marks/marks_test.go` |
| fuzz clean including split-across-read marks | 1a `cargo fuzz run decode` |
| zero clients attached still records blocks | Task 6 Step 7 |
| two clients attached record each block once | Task 6 Step 7 |
| `vim` suspends and resumes capture, one collapsed block | Task 6 Step 3 + Task 7 Step 6 |
| **usable as the daily driver** | Task 7 Step 6, reported by hand |
| the §9.4 perf gate | Task 8 Step 3 |
| 50,000 blocks at 60fps | Task 8 Step 4 |

- [ ] **Step 4: Confirm what Phase 1 did NOT deliver**

```bash
rg -n "input-ready|input-released|suppressPrompt: true" packages/terminal --glob '!*.md' --glob '!protocol/**'
```

Expected: matches only in `spawn-recipe.ts`'s guard and its test. Typing is still the shell's readline (spec §14.0) — say so plainly in the changelog rather than letting a reader assume Phase 2 landed.

- [ ] **Step 5: Update the docs and commit**

`CHANGELOG.md` gains a `## 0.3.0` covering the virtualized renderer, block headers, selection and actions, the alt-screen slot, server-side capture, and the Operator mount. `README.md`'s capability statement becomes: forms blocks from OSC 133 and the extension, renders them, hands full-screen programs to a raw surface, and **does not own input**.

```bash
git add packages/terminal .github/workflows/terminal.yml
git commit -m "chore(terminal): close phase 1"
```

---

## Self-Review

**Spec coverage.** §9.1 renderer interface — already satisfied by Phase 0's `BlockRenderer`; Tasks 2-4 implement against it without changing it. §9.2 two-level virtualization — Task 2. §9.3 what DOM buys — Task 4 maps native selection rather than replacing it. §9.4 the perf gate — Tasks 1 and 8. §11 alt-screen handoff — Task 5 (seam) and Task 7 (Operator fills it). §12.1 theme — Task 3 styles from `TerminalTheme`. §12.2 strings — Task 3 defines `TerminalStrings`, Task 7 supplies the eight locales. §13.2 the daemon's job — Task 6. §13.3 the renderer's job and history/live convergence — Task 7. §14 Phase 1 acceptance — Task 9.

**Deferred, deliberately.** Phase 2 owns the input editor, prompt suppression and the line-editor signal. Phase 4 owns the find *UI* (1a shipped the engine). Phase 6 owns retiring `ShellTerminalsView`, `ShellTerminalTab`, `useShellTerminals` and the `/terminals` route — this plan leaves them alone.

**Type consistency.** `BlockView` is the only block type the renderer sees, and it comes from `decodeBlocks`. `computeWindow` takes `readonly BlockView[]` and returns block *indices*, never ids, so it cannot disagree with the array it was handed. `TerminalStrings` is defined once in `ts/core/src/types.ts` and consumed by `renderBlockHeader` and `renderBlockActions`. `ShellBlock` (Go) maps onto the existing `blockevent.Record` and never onto `ports.ActivitySignal`.

**The one number that could stop this phase.** Task 8 Step 3 is the honest branch point: if the DOM renderer misses the gate after real optimisation, the spec's answer is a WebGL renderer behind the same interface, and that is a decision to bring back to the user with numbers rather than to make inside a task.
