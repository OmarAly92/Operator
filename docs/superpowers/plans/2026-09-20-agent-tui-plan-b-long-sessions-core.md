# Agent-TUI Plan B — Long Sessions Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Claude Code session of 200,000 rows keeps every row, costs the same per chunk of output at row 200k as at row 1k, repaints only the rows that changed, and never jumps the viewport when old rows are trimmed or rewrapped.

**Architecture:** Both `vt-core` copies (renderer wasm and pty-host mirror) take a `Limits { rows, bytes }` budget instead of a row count. Rows get a stable id (`flat + trimmed_total`, WezTerm's `stable_row_index_offset`) so blocks, selection, find hits and the scroll anchor stop being renumbered by trims. The parser records what changed (`Delta`: appended history rows, dirty screen rows, trimmed rows, rewrap remap) and the wasm export applies deltas to buffers it keeps between frames, so `feed()` stops copying the whole scrollback (Ghostty's `RenderState`); `ts/core` memoises the snapshot per generation. The DOM renderer anchors its scroll position to a stable row, keeps row elements in a pool keyed by stable row and patches only dirty rows (xterm.js `DomRenderer` row pool, Alacritty's selection damage diff).

**Tech Stack:** Rust (`vt-core`, `vt-wasm` via wasm-bindgen, `vt-host` C-ABI wasm run by wazero, `proptest`), Go (`backend/internal/adapters/runtime/ptyhost`, `vtwasm`), TypeScript (`ts/core`, `ts/renderer-dom`, `ts/react`, `frontend/`), Vite + Playwright benches (`bench/agent-session`).

**Spec:** `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` — Plan B is Part 1.3 items A, B, C, D, E and Part 3. Survey entries cited: `docs/superpowers/specs/2026-09-19-terminal-reference-survey.md` §1.2, §1.13, §2.3, §3.1, §3.5, §4.1, §4.2 (sequence numbers only). Read `TERMINAL.md` end to end before starting.

**Gate:** Plan A (`docs/superpowers/plans/2026-09-19-agent-tui-plan-a-frame-fidelity.md`) landed on `development` in `9a71794e9` (merge, 2026-09-20): the `bench/agent-session` harness and feel gate, the `claude-long-50k` fixture, the `tests/ref` corpus, `verify_integrity`/`debug_check`/`advance_vte`, `feed_at`/`tick`/`sync` with the "notify only when the generation changed" rule, and `enqueue`/`drain` are all in the tree and this plan builds on them. Plan A's review left three required fixes in its Task 5 open at the time of writing: the trailing blank row in the `screen()` helper of `crates/vt-core/tests/synchronized_output.rs`, the renderer never ticking a BSU-only block (`ts/core/src/terminal-core.ts:78-80`), and the overflow branch of `TerminalCore::feed_at` (`crates/vt-core/src/lib.rs:100-107`). No task below depends on the behaviour of those three spots; every test helper in this plan trims trailing empty rows itself.

## Global Constraints

Every task inherits these; they are the spec's "Global constraints" plus `TERMINAL.md` §3.

- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no Operator import, path, default or concept inside it. The Operator limits (`rows: 200_000, bytes: 128 MiB`) are stated in `frontend/src/renderer/components/BlockTerminal.tsx` and `backend/internal/adapters/runtime/ptyhost/host_main.go`; the package only takes them as options. `Limits::DEFAULT` exists in `vt-core` for the package's own ref harness and tests; the product never imports it.
- No comments in new code (user's global instruction). Existing comments may be corrected when they become false. A code comment that cites a reference names the repository and path (`wezterm/term/src/screen.rs`, `ghostty/src/terminal/render.zig`, `xterm.js/src/browser/renderer/dom/DomRenderer.ts`, `alacritty/alacritty/src/display/damage.rs`) the way `styles.css` cites Warp — such citations are the one kind of new comment permitted.
- A `vt-core` change is live only after **both** wasm artifacts are rebuilt (`vt_core` for the renderer via `npm run build:wasm -- --force`, `vt_host.wasm` via `cargo build --release -p vt-host --target wasm32-unknown-unknown` copied into `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`) and the daemon is rebuilt (`npm --prefix frontend run build:daemon`). Old pty-host processes keep the old wasm for the life of the session; every such task ends with "restart the daemon and the app".
- TDD: failing test first, run it, minimal implementation, run it, commit. Every `TERMINAL.md` §4 guard keeps passing.
- Rust: `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` from `/Users/omaraly/development/AI/Operator/packages/terminal`. TS: `npx vitest run` in each of `ts/core`, `ts/renderer-dom`, `ts/react`; `npx tsc --noEmit -p .` in `frontend/`. Go: `go test ./internal/adapters/runtime/ptyhost/...` in `backend/` (the pre-existing `TestProcessEnvironmentLetsOverridesWin` failure is not yours, `TERMINAL.md` §5).
- Changelog: `packages/terminal/CHANGELOG.md`, "Unreleased", one entry per behaviour change. Commits go to `development` with the `Co-Authored-By` trailer the harness gives you.
- Use absolute paths in every shell command (`TERMINAL.md` §6: parallel Bash calls share the working directory).
- Feel gate: every task ends with `npm run bench:feel` and it must report `PASS feel gate: zero pixel diff`. No task in this plan declares a pixel change.
- Do not change behaviour the spec does not ask for: no resize-debounce change (`TERMINAL.md` §4.6), no rewrap change (lazy rewrap is Plan C, spec Decision 5), no replay change (Plan C 1.3.G), no mux protocol change (Plan C 1.3.H), no §4.8 de-dup heuristic (spec Decision 3), no persistence across app restarts (spec Decision 2).
- Decisions taken from the spec's "Decisions needed": caps `Limits { rows: 200_000, bytes: 128 * 1024 * 1024 }` per core (Decision 1).
- Code blocks in this plan contain `//` lines that point at existing code ("the existing body of …"); they are instructions to the reader and are never typed into the tree.
- Stable rows are `u64` in Rust (`trimmed_total`, `first_stable_row`, `Delta.remap`, `FindMatch.row`), two `u32` words in the wasm export, `number` in TS. Flat rows (indices into the current snapshot) stay `usize`/`u32`/`number`.

## Deviations from the spec, decided here

- **§1.3.C "`BlockGrid` stores stable rows".** `Block.first_row` stays `usize` (changing the public `Block`/`BlockSummary`/`BlockTree` types to `u64` would touch every block test for no behaviour) and now holds the stable row; `BlockGrid` gains `origin: usize` (the stable row of flat row 0, equal to `Parser::trimmed_total`) and converts at its public boundary, so every caller keeps passing and reading flat rows through `flat_extent(&Block)`. `trim_to_first_row` is deleted; `advance_origin(dropped)` replaces it and only pops closed blocks that lie wholly before the origin. `verify_integrity` pins `grid.origin() as u64 == trimmed_total`.
- **§1.3.B `Delta.remap: Option<Vec<(usize, usize)>>`.** The pairs are `(u64, u64)` stable rows. A rewrap runs inside `commit_evicted` before the trim of the same feed; stable pairs stay correct across that trim, flat pairs would not.
- **§1.3.B "`full_dirty` set by … `trim_to` that trims below `history_exported_rows`".** A trim never forces `Full`. `trimmed_rows` counts only rows the export already held; rows appended and trimmed inside the same interval never appear in a delta. Forcing `Full` on every steady-state trim at the cap would reintroduce the O(session) export the item removes.
- **§1.3.B "`screen_dirty: Vec<bool>` on `Parser`".** The dirty bits live in `ScreenGrid` (`take_dirty()`), because `ScreenGrid::set`, `blank_row`, `rotate_region_up/down`, `attach_zerowidth`, `reset`, `reset_cells` and `resize_cells` are the only cell writers (`screen/edit.rs` and `screen/scroll.rs` write no cell directly) and the funnel is the one place that cannot be bypassed. While the alternate screen is active every delta is `Full` (the alt grid is a whole-screen snapshot today and full-screen apps repaint everything anyway).
- **§1.3.B "dirty rows … `populateBlock` patches rows whose stable row is in the delta's dirty set".** The renderer paints at most 60 times a second while `snapshot()` (and therefore `sync()`) can run several times per frame (`selectionView()` on every mouse move). The wasm side therefore accumulates dirty rows across syncs until the renderer acknowledges them (`TerminalCore.takeDirty()` → `ack_dirty`), and a dirty set past 4,096 rows collapses to `full`.
- **§1.3.A "`memory_stats_ptr/len` as four `u32`".** `WasmTerminalCore::memory_stats()` returns a `Vec<u32>` of four words (wasm-bindgen copies it into a `Uint32Array`); a pointer pair would need a mutable refresh step for a `&self` getter and buys nothing for a call made once per bench sample.
- **§1.3.B invariant "byte-identical to a full rebuild".** The incremental export keeps trimmed rows as a dead prefix until compaction, so its raw buffers equal a full rebuild only after `compact()`. The property test asserts raw byte identity after `compact()` **and** row-projected identity (every row's bytes, indent, style runs, every block record, the cursor) before it, after every chunk.
- **§1.3.C "the pinned header index … hold[s] stable rows".** The pinned header is `windowResult.pinnedBlockIndex`, recomputed from geometry on every paint (`viewport.ts::computeWindow`) and never carried across paints; blocks are addressed by `BlockId`, which is already stable. Nothing to convert.
- **§1.3.C `find.rs` results.** `FindMatch.row` becomes a `u64` stable row computed at match time (`row_for_offset + grid.origin()`), because results accumulate across `find_step` calls while trims happen; converting at read time would misattribute earlier hits. `next_block` (a block index) still shifts when a trimmed block is popped — pre-existing, out of scope.
- **Snapshot fields.** Two fields are added to `GridSnapshot` beyond the spec's `first_stable_row`: `history_rows: u32` (how many rows of the export are scrollback; the incremental export needs it to find the screen section, and the renderer needs it to tell immutable history rows from mutable screen rows). Both go through the `TERMINAL.md` §2 checklist.
- **`vt-wasm` `feed()`.** Keeps its `Result<(), JsError>` signature and no longer exports. `generation()` becomes the core's own `Parser::generation` (truncated to `u32`), incremented by every parse, resize and bookmark change, so Plan A's "notify only when the generation changed" rule keeps working without a snapshot.

## File structure

New or modified, by task:

| Task | Files |
|---|---|
| 1 | `packages/terminal/bench/agent-session/{main.ts,run.mjs}`, spec baseline table (new Part 3 rows) |
| 2 | `crates/vt-core/src/{limits.rs,lib.rs,parser.rs,content.rs,attribute_map.rs}`, `crates/vt-core/tests/{limits.rs,ref.rs}`, `CHANGELOG.md` |
| 3 | `crates/vt-wasm/src/lib.rs`, `crates/vt-wasm/tests/export_layout.rs`, `crates/vt-host/src/lib.rs`, `backend/.../ptyhost/vtwasm/{vtwasm.go,vtwasm_test.go,replay_test.go,bench_test.go,agent_session_test.go,assets/vt_host.wasm}`, `backend/.../ptyhost/{host_main.go,respawn.go,host_test.go,host_parser_test.go,attach_replay_test.go}`, `ts/core/src/{types.ts,terminal-core.ts,terminal-core.test.ts}`, `frontend/src/renderer/components/BlockTerminal.tsx`, `CHANGELOG.md` |
| 4 | `crates/vt-core/src/{parser.rs,block_grid.rs,grid.rs,find.rs,integrity.rs,lib.rs}`, `crates/vt-core/tests/{stable_rows.rs,find.rs}`, `crates/vt-wasm/src/{export.rs,lib.rs}`, `crates/vt-wasm/tests/exit_encoding.rs`, `CHANGELOG.md` |
| 5 | `ts/core/src/{types.ts,terminal-core.ts}`, `ts/renderer-dom/src/{block-body.ts,row-builder.ts,row-geometry.ts,row-geometry.test.ts,selection-geometry.ts,selection-geometry.test.ts,selection-text.ts,selection-text.test.ts,selection-view.ts,selection-model.test.ts,find-bar.ts,find-bar.test.ts,dom-block-renderer.ts,terminal-selection.test.ts}`, `bench/agent-session/scroll-gate.mjs`, `CHANGELOG.md` |
| 6 | `crates/vt-core/src/{delta.rs,lib.rs,parser.rs,screen.rs,screen/scroll.rs,grid.rs,integrity.rs}`, `crates/vt-core/tests/delta.rs`, `CHANGELOG.md` |
| 7 | `crates/vt-wasm/src/{export.rs,lib.rs}`, `crates/vt-wasm/Cargo.toml`, `crates/vt-wasm/tests/{incremental_export.rs,exit_encoding.rs,export_layout.rs}`, `CHANGELOG.md` |
| 8 | `ts/core/src/{terminal-core.ts,terminal-core.test.ts,blocks.ts,block-contract.test.ts,types.ts,index-browser.ts}`, `ts/renderer-dom/src/dom-block-renderer.ts`, `CHANGELOG.md` |
| 9 | `ts/renderer-dom/src/{viewport.ts,viewport.test.ts,dom-block-renderer.ts,dom-block-renderer.test.ts,index.ts}`, `bench/agent-session/scroll-gate.mjs`, `CHANGELOG.md` |
| 10 | `ts/renderer-dom/src/{element-pool.ts,element-pool.test.ts,block-body.ts,dom-block-renderer.ts,dom-block-renderer.test.ts}`, `CHANGELOG.md` |
| 11 | `ts/renderer-dom/src/{selection-view.ts,dom-block-renderer.ts,dom-block-renderer.test.ts}`, `CHANGELOG.md` |
| 12 | `bench/agent-session/run.mjs`, spec baseline table ("After Plan B" column, Part 1.4 rows), `TERMINAL.md` (§2, §4.18, §5), `CHANGELOG.md` |

Task order and why: Task 1 records the Part 3 "before" numbers first because a CPU/paint baseline cannot be taken after the paint path changes. Then A (Tasks 2–3) → C (Tasks 4–5) → B (Tasks 6–8) → D (Task 9) → E (Tasks 10–11) → Part 3 (Task 12), the order the user set. C precedes B because the incremental export's blocks and row events are expressed in stable rows.

---

### Task 1: Part 3 "before" numbers in the agent-session harness

The Part 3 acceptance (spec "Part 3 — Paint cost": ten idle panes at ≤ 25 % of the baseline's CPU, a mouse move during streaming repaints one row) and the Part 1.4 row "≤ 2 DOM nodes per changed row" have no "Today" number yet. `feed()` will also stop exporting in Task 7, so the `feedCost` row would silently stop measuring the export; a `feed + snapshot` cost is added now so the two columns stay comparable.

**Files:**
- Modify: `packages/terminal/bench/agent-session/main.ts` (`window.__agentSession` gains `feedNextSynced`, `rowNodesAdded`, `extendSelectionByOneRow`, `mountPanes`)
- Modify: `packages/terminal/bench/agent-session/run.mjs` (new metrics `feedSyncCost`, `spinner.rowNodesAdded`, `idlePanes`, `selectionRepaint`)
- Modify: `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` (four new baseline rows)

**Interfaces:**
- Consumes: Plan A's `window.__agentSession` (`feedNext`, `feedUntilRows`, `feedFrames`, `paintCount`, `addedNodes`, `resetCounters`, `core()`), `DomBenchmarkRenderer` (`mount`, private `renderer: DomBlockRenderer` reached by the same cast `main.ts:61` already uses), `DomBlockRenderer.selectionBegin/selectionUpdate/pointAt`.
- Produces: `feedNextSynced(limit): number` (ms for `core.feed` + `core.snapshot()`), `rowNodesAdded(): number` (elements with class `terminal-row` added since `resetCounters`), `extendSelectionByOneRow(): Promise<number>` (rows whose `style` attribute mutated when a two-row selection grows to three), `mountPanes(count): Promise<void>` (mounts `count` extra renderers, each on its own core, all fed by `feedFrames`); `run.mjs` rows `feedSyncCost` (same shape as `feedCost`), `spinner.rowNodesAdded`, `idlePanes: { panes: 10, seconds: 10, taskDurationS }` (CDP `Performance.getMetrics` `TaskDuration` delta), `selectionRepaint: { rowsRepainted }`.

- [ ] **Step 1: Write the failing harness test**

`bench/agent-session/fixtures.test.mjs` already runs under `node --test`. Add a sibling `bench/agent-session/session-api.test.mjs` that checks the page script declares the four new entries (a static check is all Node can do without a browser; the Playwright run is the real test):

```js
import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
import { test } from "node:test";

test("the agent-session page exposes the Plan B probes", async () => {
	const source = await readFile(new URL("./main.ts", import.meta.url), "utf8");
	for (const name of ["feedNextSynced", "rowNodesAdded", "extendSelectionByOneRow", "mountPanes"]) {
		assert.ok(source.includes(`${name}(`), `${name} is missing from main.ts`);
		assert.ok(source.includes(`${name},`) || source.includes(`${name}:`), `${name} is not exported on window.__agentSession`);
	}
});
```

Add it to the `test` script in `packages/terminal/package.json` next to `./bench/agent-session/fixtures.test.mjs`.

- [ ] **Step 2: Run it to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && node --test ./bench/agent-session/session-api.test.mjs`
Expected: FAIL, "feedNextSynced is missing from main.ts".

- [ ] **Step 3: Add the probes to `main.ts`**

In `packages/terminal/bench/agent-session/main.ts`, extend the `AgentSession` type and the object:

```ts
type AgentSession = {
	// the existing members of `AgentSession` (main.ts:13-35) stay as they are
	feedNextSynced(limit: number): number;
	rowNodesAdded(): number;
	extendSelectionByOneRow(): Promise<number>;
	mountPanes(count: number): Promise<void>;
};
```

Counters and probes (place after the existing `MutationObserver`):

```ts
let rowNodesAdded = 0;
new MutationObserver((records) => {
	for (const record of records) {
		for (const node of record.addedNodes) {
			if (node instanceof HTMLElement && node.classList.contains("terminal-row")) rowNodesAdded += 1;
		}
	}
}).observe(host, { childList: true, subtree: true });

function feedNextSynced(limit: number): number {
	const end = Math.min(recording.length, fed + limit);
	if (end <= fed) return 0;
	applyResizesUpTo(fed);
	const chunk = recording.subarray(fed, end);
	const before = performance.now();
	core.feed(chunk);
	core.snapshot();
	const cost = performance.now() - before;
	fed = end;
	return cost;
}

const extraPanes: DomBenchmarkRenderer[] = [];

async function mountPanes(count: number): Promise<void> {
	for (let index = 0; index < count; index += 1) {
		const paneHost = document.createElement("div");
		paneHost.style.width = "800px";
		paneHost.style.height = "300px";
		document.body.append(paneHost);
		const pane = new DomBenchmarkRenderer();
		await pane.mount(paneHost, { columns: sizes[0].cols, rows: sizes[0].rows, scrollback });
		(pane.getCoreForBench() as TerminalCore).setAgentTuiMode(true);
		extraPanes.push(pane);
	}
}

async function extendSelectionByOneRow(): Promise<number> {
	const rows = [...host!.querySelectorAll<HTMLElement>("[data-terminal-row]")];
	if (rows.length < 4) throw new Error("need at least four rendered rows");
	const at = (row: HTMLElement) => {
		const rect = row.getBoundingClientRect();
		return { x: rect.left + 4, y: rect.top + rect.height / 2 };
	};
	const first = domRenderer.pointAt(at(rows[0]!).x, at(rows[0]!).y);
	const second = domRenderer.pointAt(at(rows[1]!).x, at(rows[1]!).y);
	const third = domRenderer.pointAt(at(rows[2]!).x, at(rows[2]!).y);
	if (!first || !second || !third) throw new Error("rows have no selection point");
	domRenderer.selectionBegin(first, "simple");
	domRenderer.selectionUpdate(second);
	await nextFrame();
	const mutated = new Set<Node>();
	const observer = new MutationObserver((records) => {
		for (const record of records) {
			const target = record.target;
			if (target instanceof HTMLElement && target.classList.contains("terminal-row")) mutated.add(target);
		}
	});
	observer.observe(host!, { attributes: true, attributeFilter: ["style"], subtree: true });
	domRenderer.selectionUpdate(third);
	await nextFrame();
	for (const record of observer.takeRecords()) {
		if (record.target instanceof HTMLElement && record.target.classList.contains("terminal-row")) mutated.add(record.target);
	}
	observer.disconnect();
	domRenderer.selectionClear();
	return mutated.size;
}
```

`domRenderer` is the existing cast at `main.ts:61`; widen its type to `DomBlockRenderer` (import the type from `@operator/terminal-renderer-dom`) so `pointAt`, `selectionBegin`, `selectionUpdate` and `selectionClear` type-check. `feedFrames` feeds every extra pane the same chunk:

```ts
async function feedFrames(count: number, intervalMs: number): Promise<void> {
	const ends = frameEnds().filter((end) => end > fed).slice(0, count);
	for (const end of ends) {
		const start = fed;
		feedChunk(start, end);
		for (const pane of extraPanes) (pane.getCoreForBench() as TerminalCore).feed(recording.subarray(start, end));
		await new Promise((resolve) => setTimeout(resolve, intervalMs));
	}
}
```

Export the four on `window.__agentSession` and reset `rowNodesAdded` in `resetCounters`.

- [ ] **Step 4: Add the metrics to `run.mjs`**

```js
async function feedSyncCostAt(page, rows) {
	const reached = await page.evaluate((target) => window.__agentSession.feedUntilRows(target), rows);
	if (reached < rows) return { rows, reached, medianMs: null };
	const samples = await page.evaluate(() => {
		const out = [];
		for (let index = 0; index < 20; index += 1) {
			const cost = window.__agentSession.feedNextSynced(4096);
			if (cost === 0) break;
			out.push(cost);
		}
		return out;
	});
	return { rows, reached, medianMs: median(samples), samples: samples.length };
}

async function idlePanes(page) {
	const session = await page.context().newCDPSession(page);
	await session.send("Performance.enable");
	await page.evaluate(() => window.__agentSession.mountPanes(9));
	const before = (await session.send("Performance.getMetrics")).metrics.find((m) => m.name === "TaskDuration").value;
	await page.evaluate(() => window.__agentSession.feedFrames(100, 100));
	const after = (await session.send("Performance.getMetrics")).metrics.find((m) => m.name === "TaskDuration").value;
	return { panes: 10, seconds: 10, taskDurationS: after - before };
}

async function selectionRepaint(page) {
	await page.evaluate(() => window.__agentSession.feedFrames(5, 20));
	const rowsRepainted = await page.evaluate(() => window.__agentSession.extendSelectionByOneRow());
	return { rowsRepainted };
}
```

In `main()`: for `claude-spinner-10s`, after `rows.spinner = await spinnerPaints(page)` add `rows.spinner.rowNodesAdded = await page.evaluate(() => window.__agentSession.rowNodesAdded())` (reset happens inside `spinnerPaints`), then on fresh pages `rows.idlePanes = await idlePanes(idlePage)` and `rows.selectionRepaint = await selectionRepaint(selectionPage)`. For the long fixture, next to `rows.feedCost` add `rows.feedSyncCost = []` filled by `feedSyncCostAt` for `[1000, 5000, 50000]` on a second fresh page (the first page has already consumed the recording past 50k).

- [ ] **Step 5: Run the static test and the harness**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && node --test ./bench/agent-session/session-api.test.mjs && npm run build && npm run bench:agent`
Expected: the test passes; `bench:agent` prints one JSON line per fixture containing `feedSyncCost`, `spinner.rowNodesAdded`, `idlePanes.taskDurationS`, `selectionRepaint.rowsRepainted`. Record the printed numbers.

- [ ] **Step 6: Add the rows to the spec's baseline table**

In `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`, "The table", append four rows with the measured values in the "After Plan A" column (that is the current state) and `—` under "Today":

```
| `feed()` + `snapshot()` cost at 1k / 5k / 50k rows | `performance.now()` around `core.feed` then `core.snapshot()` for a 4 KiB chunk | — | <measured> |
| row nodes created per paint under the spinner | `MutationObserver` `addedNodes` filtered to `.terminal-row` over 100 spinner frames | — | <measured> |
| main-thread task time of ten idle spinner panes over 10 s | CDP `Performance.getMetrics` `TaskDuration` delta, 10 renderers fed the same 100 frames at 100 ms | — | <measured> |
| rows repainted when a mouse move extends the selection by one row | `MutationObserver` on `style` of `.terminal-row` around one `selectionUpdate` during streaming | — | <measured> |
```

- [ ] **Step 7: Feel gate and commit**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel`
Expected: `PASS feel gate: zero pixel diff` (the harness page mounts extra panes only when asked).

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/bench/agent-session packages/terminal/package.json docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md && git commit -m "bench: Plan B probes — feed+sync cost, row nodes per paint, ten-pane idle CPU, selection repaint rows" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `Limits { rows, bytes }` and `memory_stats` in `vt-core` (§1.3.A)

**Files:**
- Create: `packages/terminal/crates/vt-core/src/limits.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs:50-85` (`TerminalCore` fields, `new`, `with_limits`, `memory_stats`), `:207-208` and `:310` (`trim_to` calls)
- Modify: `packages/terminal/crates/vt-core/src/parser.rs:384-395` (`trim_to`)
- Modify: `packages/terminal/crates/vt-core/src/content.rs` (`resident_bytes`)
- Modify: `packages/terminal/crates/vt-core/src/attribute_map.rs` (`len`, `byte_len`)
- Modify: `packages/terminal/crates/vt-core/tests/ref.rs:7,91` (`REF_SCROLLBACK_ROWS` → `Limits::DEFAULT`)
- Create: `packages/terminal/crates/vt-core/tests/limits.rs`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `RowIndex::trim_to(max_total) -> Option<u64>` (`row_index.rs:189`), `Content::drop_before`, `AttributeMap::drop_before`, `BlockGrid::trim_to_first_row(dropped)` (still present until Task 4).
- Produces:
  ```rust
  // vt_core::limits
  #[derive(Clone, Copy, Debug, PartialEq, Eq)]
  pub struct Limits { pub rows: usize, pub bytes: usize }
  impl Limits {
      pub const DEFAULT: Limits = Limits { rows: 200_000, bytes: 128 * 1024 * 1024 };
      pub const fn rows_only(rows: usize) -> Limits { Limits { rows, bytes: usize::MAX } }
  }
  #[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
  pub struct MemoryStats { pub content_bytes: usize, pub style_entries: usize, pub rows: usize, pub blocks: usize }
  // TerminalCore
  pub fn with_limits(columns: usize, limits: Limits) -> Result<Self, CoreError>   // Err(ZeroScrollback) when limits.rows == 0
  pub fn new(columns: usize, scrollback_rows: usize) -> Result<Self, CoreError>  // = with_limits(columns, Limits::rows_only(scrollback_rows))
  pub fn limits(&self) -> Limits
  pub fn memory_stats(&self) -> MemoryStats
  // Parser
  pub fn trim_to(&mut self, limits: Limits) -> usize   // rows dropped from the front
  // Content / AttributeMap
  pub fn resident_bytes(&self) -> usize                 // sum of retained chunk lengths
  pub fn len(&self) -> usize; pub fn byte_len(&self) -> usize   // entries; entries * (size_of::<u64>() + size_of::<A>())
  ```
  Re-exported: `pub use limits::{Limits, MemoryStats};` in `lib.rs`.

- [ ] **Step 1: Write the failing tests**

`packages/terminal/crates/vt-core/tests/limits.rs`:

```rust
mod common;

use vt_core::{Limits, MemoryStats, TerminalCore};

fn rows_of(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    let mut rows: Vec<String> = (0..snapshot.row_count())
        .map(|i| snapshot.row_text(i).to_string())
        .collect();
    while rows.last().is_some_and(|row| row.is_empty()) {
        rows.pop();
    }
    rows
}

fn feed_numbered(core: &mut TerminalCore, count: usize) {
    for i in 0..count {
        core.feed(format!("row {i:05} xxxxxxxxxx\r\n").as_bytes());
    }
}

#[test]
fn byte_cap_trims_whole_rows_and_keeps_blocks_consistent() {
    let mut core = TerminalCore::with_limits(40, Limits { rows: 100_000, bytes: 8_192 }).unwrap();
    core.resize(40, 3);
    core.feed(b"\x1b]133;A\x07");
    feed_numbered(&mut core, 600);
    let stats = core.memory_stats();
    assert!(stats.content_bytes + stats.style_entries * 16 <= 8_192, "{stats:?}");
    assert!(stats.rows > 100 && stats.rows < 600, "{stats:?}");
    let rows = rows_of(&core);
    assert!(rows[0].starts_with("row "), "first retained row is whole: {:?}", rows[0]);
    assert_eq!(rows.last().map(String::as_str), Some("row 00599 xxxxxxxxxx"));
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.blocks.len(), 1);
    assert_eq!(snapshot.blocks[0].first_row, 0);
    assert_eq!(snapshot.blocks[0].row_count as usize, snapshot.row_count());
    common::check(&core);
}

#[test]
fn row_cap_still_applies() {
    let mut limited = TerminalCore::with_limits(40, Limits { rows: 50, bytes: usize::MAX }).unwrap();
    let mut legacy = TerminalCore::new(40, 50).unwrap();
    for core in [&mut limited, &mut legacy] {
        core.resize(40, 3);
        feed_numbered(core, 100);
    }
    assert_eq!(limited.memory_stats().rows, 49);
    assert_eq!(rows_of(&limited), rows_of(&legacy));
    assert_eq!(legacy.limits(), Limits { rows: 50, bytes: usize::MAX });
    common::check(&limited);
}

#[test]
fn memory_stats_match_after_trim() {
    let mut core = TerminalCore::with_limits(40, Limits { rows: 200, bytes: usize::MAX }).unwrap();
    core.resize(40, 3);
    core.feed(b"\x1b]133;A\x07");
    feed_numbered(&mut core, 400);
    let stats = core.memory_stats();
    let snapshot = core.snapshot().unwrap();
    let history_rows = snapshot.row_count() - 3;
    assert_eq!(stats.rows, history_rows);
    assert_eq!(stats.rows, 199);
    let history_bytes: usize = (0..history_rows).map(|i| snapshot.row_text(i).len()).sum();
    assert!(stats.content_bytes >= history_bytes, "{stats:?} vs {history_bytes}");
    assert!(stats.content_bytes < history_bytes + 4_096, "{stats:?} vs {history_bytes}");
    assert_eq!(stats.blocks, 1);
    assert_ne!(stats, MemoryStats::default());
    common::check(&core);
}

#[test]
fn zero_rows_is_rejected() {
    assert!(TerminalCore::with_limits(40, Limits { rows: 0, bytes: 1 }).is_err());
}
```

The `history_rows = row_count() - 3` line relies on the fact that `GridSnapshot` exports `content_rows = max_cursor_row + 1` screen rows: after `"...\r\n"` the cursor sits on the third screen row, so three screen rows are exported, the last one blank.

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test limits`
Expected: compile error, `Limits` and `with_limits` do not exist.

- [ ] **Step 3: Implement `limits.rs`, the constructor, the stats and the byte-aware trim**

`crates/vt-core/src/limits.rs`:

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Limits {
    pub rows: usize,
    pub bytes: usize,
}

impl Limits {
    pub const DEFAULT: Limits = Limits {
        rows: 200_000,
        bytes: 128 * 1024 * 1024,
    };

    pub const fn rows_only(rows: usize) -> Limits {
        Limits {
            rows,
            bytes: usize::MAX,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct MemoryStats {
    pub content_bytes: usize,
    pub style_entries: usize,
    pub rows: usize,
    pub blocks: usize,
}
```

`lib.rs`: add `pub mod limits;` and `pub use limits::{Limits, MemoryStats};`; replace the `scrollback_rows: usize` field with `limits: Limits`:

```rust
    pub fn new(columns: usize, scrollback_rows: usize) -> Result<Self, CoreError> {
        Self::with_limits(columns, Limits::rows_only(scrollback_rows))
    }

    pub fn with_limits(columns: usize, limits: Limits) -> Result<Self, CoreError> {
        if columns == 0 {
            return Err(CoreError::ZeroColumns);
        }
        if limits.rows == 0 {
            return Err(CoreError::ZeroScrollback);
        }
        Ok(Self {
            parser: parser::Parser::new(columns),
            vte: VteParser::new(),
            mark_decoder: MarkDecoder::new(),
            alt_screen: alt_screen::AltScreen::new(),
            line_editor: line_editor::LineEditorTracker::default(),
            limits,
            rows: DEFAULT_ROWS,
            fed_total: 0,
            sync: sync::SyncBuffer::default(),
            now_ms: 0,
        })
    }

    pub fn limits(&self) -> Limits {
        self.limits
    }

    pub fn memory_stats(&self) -> MemoryStats {
        MemoryStats {
            content_bytes: self.parser.content().resident_bytes(),
            style_entries: self.parser.styles().len(),
            rows: self.parser.rows().completed().len(),
            blocks: self.parser.grid().len(),
        }
    }
```

`Parser::new(width)` drops its unused `_scrollback_rows` parameter (update the two unit tests at `parser.rs:629,649` and `integrity.rs`'s `parser_with`). Both `self.parser.trim_to(self.scrollback_rows)` calls (`lib.rs:208,310`) become `self.parser.trim_to(self.limits)`.

`parser.rs`:

```rust
    pub fn trim_to(&mut self, limits: Limits) -> usize {
        let before = self.rows.completed().len();
        loop {
            let completed = self.rows.completed().len();
            let over_rows = completed + 1 > limits.rows;
            let over_bytes = self.content.resident_bytes() + self.styles.byte_len() > limits.bytes;
            if completed == 0 || !(over_rows || over_bytes) {
                break;
            }
            let keep = if over_rows { limits.rows } else { completed };
            let Some(new_start) = self.rows.trim_to(keep) else {
                break;
            };
            self.content.drop_before(new_start);
            self.styles.drop_before(new_start);
        }
        let dropped = before - self.rows.completed().len();
        if dropped > 0 {
            self.grid.trim_to_first_row(dropped);
        }
        dropped
    }
```

(`RowIndex::trim_to(max_total)` pops while `completed.len() + 1 > max_total`; passing `completed` pops exactly one row for the byte case.) Import `crate::limits::Limits` in `parser.rs`. Delete the now-false comment block above the old `trim_to_first_row` call.

`content.rs`:

```rust
    pub fn resident_bytes(&self) -> usize {
        self.chunks.iter().map(|chunk| chunk.bytes.len()).sum()
    }
```

`attribute_map.rs`:

```rust
    pub fn len(&self) -> usize {
        self.ends.len()
    }

    pub fn is_empty(&self) -> bool {
        self.ends.is_empty()
    }

    pub fn byte_len(&self) -> usize {
        self.ends.len() * (std::mem::size_of::<u64>() + std::mem::size_of::<A>())
    }
```

`tests/ref.rs`: delete `REF_SCROLLBACK_ROWS` and build the core with `TerminalCore::with_limits(first.cols, Limits::DEFAULT)`.

- [ ] **Step 4: Run the tests**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test limits && cargo test -p vt-core`
Expected: the four new tests pass; the whole crate is green (the 107 existing `TerminalCore::new(cols, rows)` call sites are untouched).

- [ ] **Step 5: CHANGELOG**

Under "Unreleased" add:

```
Scrollback is capped by bytes as well as rows.

- `TerminalCore::with_limits(columns, Limits { rows, bytes })` trims whole rows
  from the front while either budget is exceeded (Ghostty
  `src/terminal/PageList.zig` `Limits`, `setMaxBytes`); `new(columns, rows)`
  stays as `Limits::rows_only(rows)`. `memory_stats()` reports resident content
  bytes, style entries, scrollback rows and blocks.
```

- [ ] **Step 6: Verify and commit**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test`
Expected: clean. No wasm rebuild yet (Task 3 rebuilds both after the wiring), no pixel change, so `npm run bench:feel` is deferred to Task 3 where the renderer wasm is rebuilt.

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-core packages/terminal/CHANGELOG.md && git commit -m "vt-core: Limits { rows, bytes } byte budget and memory_stats" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Limits through `vt-wasm`, `ts/core`, `vt-host`, Go and the two products (§1.3.A wiring)

**Files:**
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs:29-44` (constructor), new `memory_stats`, `js_error_from_core`
- Modify: `packages/terminal/crates/vt-wasm/tests/export_layout.rs` (stats export test)
- Modify: `packages/terminal/crates/vt-host/src/lib.rs:24-38` (`vt_new`), new `vt_memory_stats`
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go:32-50` (`Limits`, `New`, `MemoryStats`)
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/{vtwasm_test.go,replay_test.go:11,bench_test.go:33,agent_session_test.go:35}`
- Modify: `backend/internal/adapters/runtime/ptyhost/{host_main.go:165,respawn.go:63,host_test.go:704,host_parser_test.go:12,37,attach_replay_test.go:24}`, new `mirror_limits.go`
- Modify: `packages/terminal/ts/core/src/types.ts:103-108` (`TerminalCoreOptions`, `TerminalLimits`, `MemoryStats`), `terminal-core.ts:61-71` (`create`), new `memoryStats()`
- Modify: `packages/terminal/ts/core/src/terminal-core.test.ts`
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx:66,290`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: Task 2's `TerminalCore::with_limits`, `Limits`, `MemoryStats`.
- Produces (wasm-bindgen): `WasmTerminalCore::new(columns: usize, rows_limit: usize, bytes_limit: usize)`, `memory_stats(&self) -> Vec<u32>` (`[content_bytes, style_entries, rows, blocks]`).
- Produces (TS): `type TerminalLimits = Readonly<{ rows: number; bytes: number }>`; `TerminalCoreOptions = Readonly<{ columns: number; rows?: number; host?: HostCapabilities; scrollback?: number; limits?: TerminalLimits }>` (one of `scrollback`/`limits` required; `scrollback: n` means `{ rows: n, bytes: 0xffff_ffff }`); `type MemoryStats = Readonly<{ contentBytes: number; styleEntries: number; rows: number; blocks: number }>`; `TerminalCore.memoryStats(): MemoryStats`; `export const UNBOUNDED_BYTES = 0xffff_ffff`.
- Produces (vt-host): `vt_new(cols: u32, rows: u32, scrollback_rows: u32, scrollback_bytes: u32) -> u32`; `vt_memory_stats(handle: u32, out_ptr: u32) -> u32` writes four little-endian `u32` (16 bytes) and returns 1, or 0 for an unknown handle.
- Produces (Go): `type Limits struct { Rows, Bytes uint32 }`; `func New(ctx context.Context, wasmModule []byte, cols, rows uint32, limits Limits) (*Parser, error)`; `type MemoryStats struct { ContentBytes, StyleEntries, Rows, Blocks uint32 }`; `func (p *Parser) MemoryStats() (MemoryStats, error)`; in package `ptyhost`: `var mirrorLimits = vtwasm.Limits{Rows: 200_000, Bytes: 128 << 20}` (`mirror_limits.go`).
- Produces (frontend): `const DEFAULT_LIMITS = { rows: 200_000, bytes: 128 * 1024 * 1024 } as const` in `BlockTerminal.tsx`.

- [ ] **Step 1: Failing Rust tests (vt-wasm and vt-host)**

Append to `crates/vt-wasm/tests/export_layout.rs`:

```rust
#[test]
fn memory_stats_are_exported_as_four_words() {
    let mut core = TerminalCore::with_limits(16, vt_core::Limits { rows: 10, bytes: usize::MAX }).unwrap();
    core.feed(b"\x1b[31mred\x1b[0m ok\r\nplain\r\n");
    let stats = core.memory_stats();
    let words = vt_wasm::memory_stats_words(&stats);
    assert_eq!(words, [stats.content_bytes as u32, stats.style_entries as u32, stats.rows as u32, stats.blocks as u32]);
    assert_eq!(words[2], 2);
}
```

(`memory_stats_words` is a plain Rust function in `vt-wasm` that `WasmTerminalCore::memory_stats` wraps, so the layout is testable without a browser.)

- [ ] **Step 2: Run to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-wasm --test export_layout`
Expected: compile error, `memory_stats_words` missing.

- [ ] **Step 3: Implement the vt-wasm and vt-host exports**

`crates/vt-wasm/src/lib.rs`:

```rust
pub fn memory_stats_words(stats: &vt_core::MemoryStats) -> [u32; 4] {
    [
        stats.content_bytes as u32,
        stats.style_entries as u32,
        stats.rows as u32,
        stats.blocks as u32,
    ]
}

#[wasm_bindgen]
impl WasmTerminalCore {
    #[wasm_bindgen(constructor)]
    pub fn new(columns: usize, rows_limit: usize, bytes_limit: usize) -> Result<WasmTerminalCore, JsError> {
        let core = TerminalCore::with_limits(
            columns,
            vt_core::Limits { rows: rows_limit, bytes: bytes_limit },
        )
        .map_err(js_error_from_core)?;
        // the rest is the existing body of `new` (vt-wasm/src/lib.rs:32-43): ExportBuffers, generation 0, the find fields
    }

    pub fn memory_stats(&self) -> Vec<u32> {
        memory_stats_words(&self.core.memory_stats()).to_vec()
    }
}
```

`crates/vt-host/src/lib.rs`:

```rust
#[no_mangle]
pub extern "C" fn vt_new(cols: u32, rows: u32, scrollback_rows: u32, scrollback_bytes: u32) -> u32 {
    let limits = vt_core::Limits {
        rows: scrollback_rows as usize,
        bytes: scrollback_bytes as usize,
    };
    let Ok(mut core) = TerminalCore::with_limits(cols as usize, limits) else {
        return 0;
    };
    // the rest is the existing body of `vt_new` (vt-host/src/lib.rs:28-37): reflow off, answers queries, resize, register the handle
}

#[no_mangle]
pub extern "C" fn vt_memory_stats(handle: u32, out_ptr: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => {
            let stats = core.memory_stats();
            let words = [
                stats.content_bytes as u32,
                stats.style_entries as u32,
                stats.rows as u32,
                stats.blocks as u32,
            ];
            let out = out_ptr as *mut u8;
            for (index, word) in words.iter().enumerate() {
                let bytes = word.to_le_bytes();
                unsafe {
                    std::ptr::copy_nonoverlapping(bytes.as_ptr(), out.add(index * 4), 4);
                }
            }
            1
        }
        None => 0,
    })
}
```

- [ ] **Step 4: Run the Rust tests, rebuild both wasm artifacts**

Run:
```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && npm run build:wasm -- --force
```
Expected: green; both artifacts rebuilt.

- [ ] **Step 5: Failing Go test**

In `backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm_test.go`:

```go
func TestNewAcceptsByteLimit(t *testing.T) {
	p, err := New(context.Background(), Module, 40, 3, Limits{Rows: 100000, Bytes: 8192})
	if err != nil {
		t.Fatalf("new: %v", err)
	}
	t.Cleanup(func() { _ = p.Close() })
	for i := 0; i < 600; i++ {
		if err := p.Feed([]byte(fmt.Sprintf("row %05d xxxxxxxxxx\r\n", i))); err != nil {
			t.Fatalf("feed: %v", err)
		}
	}
	stats, err := p.MemoryStats()
	if err != nil {
		t.Fatalf("memory stats: %v", err)
	}
	if stats.ContentBytes+stats.StyleEntries*16 > 8192 {
		t.Fatalf("byte cap not enforced: %+v", stats)
	}
	if stats.Rows < 100 || stats.Rows >= 600 {
		t.Fatalf("rows outside the trimmed range: %+v", stats)
	}
	text, err := p.RenderTail(1)
	if err != nil || !strings.Contains(text, "row 00599") {
		t.Fatalf("newest row missing after trim: %q, %v", text, err)
	}
}
```

Add `"context"` and `"fmt"` to the imports.

- [ ] **Step 6: Run to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/vtwasm/ -run TestNewAcceptsByteLimit`
Expected: compile error, `Limits` undefined.

- [ ] **Step 7: Implement the Go side and update every call site**

`vtwasm.go`:

```go
type Limits struct {
	Rows  uint32
	Bytes uint32
}

type MemoryStats struct {
	ContentBytes uint32
	StyleEntries uint32
	Rows         uint32
	Blocks       uint32
}

func New(ctx context.Context, wasmModule []byte, cols, rows uint32, limits Limits) (*Parser, error) {
	rt := wazero.NewRuntime(ctx)
	mod, err := rt.Instantiate(ctx, wasmModule)
	if err != nil {
		_ = rt.Close(ctx)
		return nil, fmt.Errorf("vtwasm: instantiate: %w", err)
	}
	res, err := mod.ExportedFunction("vt_new").Call(ctx, uint64(cols), uint64(rows), uint64(limits.Rows), uint64(limits.Bytes))
	// the rest is the existing body of `New` (vtwasm.go:40-50): handle check, identity, return
}

const memoryStatsBytes = 16

func (p *Parser) MemoryStats() (MemoryStats, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, memoryStatsBytes)
	if err != nil {
		return MemoryStats{}, fmt.Errorf("vtwasm: alloc stats: %w", err)
	}
	out := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), memoryStatsBytes) }()
	res, err = p.module.ExportedFunction("vt_memory_stats").Call(p.ctx, uint64(p.handle), uint64(out))
	if err != nil {
		return MemoryStats{}, fmt.Errorf("vtwasm: memory_stats: %w", err)
	}
	if res[0] != 1 {
		return MemoryStats{}, fmt.Errorf("vtwasm: memory_stats failed for handle %d", p.handle)
	}
	raw, ok := p.module.Memory().Read(out, memoryStatsBytes)
	if !ok {
		return MemoryStats{}, fmt.Errorf("vtwasm: read stats out of range")
	}
	return MemoryStats{
		ContentBytes: binary.LittleEndian.Uint32(raw[0:4]),
		StyleEntries: binary.LittleEndian.Uint32(raw[4:8]),
		Rows:         binary.LittleEndian.Uint32(raw[8:12]),
		Blocks:       binary.LittleEndian.Uint32(raw[12:16]),
	}, nil
}
```

`backend/internal/adapters/runtime/ptyhost/mirror_limits.go`:

```go
package ptyhost

import "github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"

var mirrorLimits = vtwasm.Limits{Rows: 200_000, Bytes: 128 << 20}
```

Call sites: `host_main.go:165` and `respawn.go:63` pass `mirrorLimits`; the test call sites listed under **Files** pass `vtwasm.Limits{Rows: <the number they passed before>, Bytes: 0xffffffff}` (inside the `vtwasm` package: `Limits{...}`). `MaxOutputLines` stays for the `Ring` and for `Replay(MaxOutputLines)` (`host.go:773`, Plan C changes the replay).

- [ ] **Step 8: Run the Go tests**

Run: `cd /Users/omaraly/development/AI/Operator/backend && go build ./... && go test ./internal/adapters/runtime/ptyhost/...`
Expected: `TestNewAcceptsByteLimit` passes; everything else unchanged (bar the pre-existing `TestProcessEnvironmentLetsOverridesWin`).

- [ ] **Step 9: Failing TS test**

In `ts/core/src/terminal-core.test.ts`:

```ts
	it("takes limits or the scrollback alias and reports memory stats", () => {
		const limited = createTerminalCore({ columns: 40, limits: { rows: 100_000, bytes: 8192 } });
		const encoder = new TextEncoder();
		for (let i = 0; i < 600; i += 1) limited.feed(encoder.encode(`row ${String(i).padStart(5, "0")} xxxxxxxxxx\r\n`));
		const stats = limited.memoryStats();
		expect(stats.contentBytes + stats.styleEntries * 16).toBeLessThanOrEqual(8192);
		expect(stats.rows).toBeGreaterThan(100);
		expect(stats.rows).toBeLessThan(600);
		const alias = createTerminalCore({ columns: 40, scrollback: 50 });
		for (let i = 0; i < 100; i += 1) alias.feed(encoder.encode(`row ${i}\r\n`));
		expect(alias.memoryStats().rows).toBe(49);
		expect(() => createTerminalCore({ columns: 40 } as never)).toThrow(/limits/);
	});
```

- [ ] **Step 10: Run to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run terminal-core.test.ts -t "takes limits"`
Expected: FAIL, `memoryStats is not a function` / type error on `limits`.

- [ ] **Step 11: Implement the TS options and `memoryStats`**

`types.ts`:

```ts
export type TerminalLimits = Readonly<{ rows: number; bytes: number }>;

export type MemoryStats = Readonly<{ contentBytes: number; styleEntries: number; rows: number; blocks: number }>;

export type TerminalCoreOptions = Readonly<{
	columns: number;
	rows?: number;
	host?: HostCapabilities;
	scrollback?: number;
	limits?: TerminalLimits;
}>;
```

`terminal-core.ts`:

```ts
export const UNBOUNDED_BYTES = 0xffff_ffff;

function limitsOf(options: TerminalCoreOptions): TerminalLimits {
	if (options.limits) return options.limits;
	if (options.scrollback !== undefined) return { rows: options.scrollback, bytes: UNBOUNDED_BYTES };
	throw new Error("terminal core needs limits or scrollback");
}

	static create(options: TerminalCoreOptions): TerminalCore {
		if (!isInitialized()) {
			throw new Error("terminal core WASM is not initialized");
		}
		const limits = limitsOf(options);
		const inner = new WasmTerminalCore(options.columns, limits.rows, limits.bytes);
		// the rest is the existing body of `create` (terminal-core.ts:66-70)
	}

	memoryStats(): MemoryStats {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		const words = this.inner.memory_stats();
		return { contentBytes: words[0]!, styleEntries: words[1]!, rows: words[2]!, blocks: words[3]! };
	}
```

Export `UNBOUNDED_BYTES` and the two types from `index-browser.ts` next to `FEED_BUDGET_MS`.

- [ ] **Step 12: Wire the product default**

`frontend/src/renderer/components/BlockTerminal.tsx`: replace `const DEFAULT_SCROLLBACK = 5000;` with `const DEFAULT_LIMITS = { rows: 200_000, bytes: 128 * 1024 * 1024 } as const;` and the `createTerminalCore` call with `createTerminalCore({ columns: DEFAULT_COLUMNS, limits: DEFAULT_LIMITS })`.

- [ ] **Step 13: Run everything the task touched**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in core renderer-dom react; do (cd ts/$p && npx vitest run); done && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: all green, `PASS feel gate: zero pixel diff`, `PASS agent-session gate`. Then `npm run bench:agent` for the long fixture: the `rendererMemoryBytes` and reopen rows are unchanged (the renderer already ran at 200k in the harness; the mirror now retains up to 200k rows, so the Go-side mirror memory in the reopen report rises above the 4,128,768 bytes of the 1,000-row cap — record the new number in Task 12, not here).

- [ ] **Step 14: CHANGELOG and commit**

```
- `TerminalCoreOptions.limits { rows, bytes }` replaces `scrollback` (kept as
  an alias for one release: `scrollback: n` is `{ rows: n, bytes: unbounded }`);
  `TerminalCore.memoryStats()`. `vt_new` takes a byte budget and
  `vt_memory_stats` reports it; the Go mirror takes `vtwasm.Limits`.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal backend frontend/src/renderer/components/BlockTerminal.tsx && git commit -m "terminal: byte-budget limits in the renderer core, the host mirror and both products" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

### Task 4: Stable row ids in `vt-core` and `BlockGrid`, exported as `first_stable_row` (§1.3.C, model half)

Reference: `wezterm/term/src/screen.rs:30` (`stable_row_index_offset`), `:523-535` (`phys_to_stable_row_index`, `stable_row_to_phys` returning `None` once the row is gone), `:734` (the offset advances exactly where rows are dropped).

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/parser.rs` (`trimmed_total`, `first_stable_row`, `stable_row`, `flat_row`, `trim_to`)
- Modify: `packages/terminal/crates/vt-core/src/block_grid.rs` (`origin`, `advance_origin`, `flat_extent`, delete `trim_to_first_row`, conversions in `start_output`, `covered_end`, `next_row`, `sync_next_row`, `push_synthetic`, `clamp_to_rows`, `remap_rows`; rewrite the five trim unit tests)
- Modify: `packages/terminal/crates/vt-core/src/grid.rs` (`GridSnapshot.first_stable_row`, `build_snapshot` uses `flat_extent`)
- Modify: `packages/terminal/crates/vt-core/src/find.rs:39-43,188-217` (`FindMatch.row: u64`, stable)
- Modify: `packages/terminal/crates/vt-core/src/integrity.rs` (`flat_extent`, `OriginMismatch`)
- Modify: `packages/terminal/crates/vt-core/src/lib.rs` (`first_stable_row`, `stable_row`, `flat_row`, `snapshot` passes the offset)
- Create: `packages/terminal/crates/vt-core/tests/stable_rows.rs`
- Modify: `packages/terminal/crates/vt-core/tests/find.rs`
- Modify: `packages/terminal/crates/vt-wasm/src/export.rs` (`first_stable_row`), `crates/vt-wasm/src/lib.rs` (`first_stable_row_lo/hi`, `find_step` row word), `crates/vt-wasm/tests/exit_encoding.rs` (fixture field)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: Task 2's `Parser::trim_to(limits) -> usize`.
- Produces:
  ```rust
  // Parser
  pub fn first_stable_row(&self) -> u64                  // == trimmed_total
  pub fn stable_row(&self, flat: usize) -> u64           // flat as u64 + trimmed_total
  pub fn flat_row(&self, stable: u64) -> Option<usize>   // None when stable < trimmed_total
  // BlockGrid (rows stored stable; the public API stays flat)
  pub fn origin(&self) -> usize
  pub fn advance_origin(&mut self, dropped: usize)       // pops closed blocks whose end <= new origin; next_row = max(next_row, origin)
  pub fn flat_extent(&self, block: &Block) -> (usize, usize)   // (first_row, row_count) clamped to the origin
  // TerminalCore
  pub fn first_stable_row(&self) -> u64
  pub fn stable_row(&self, flat: usize) -> u64
  pub fn flat_row(&self, stable: u64) -> Option<usize>
  // GridSnapshot
  pub first_stable_row: u64
  // FindMatch
  pub row: u64                                            // stable row
  // IntegrityError
  OriginMismatch { origin: usize, trimmed_total: u64 }
  // vt-wasm
  ExportBuffers::first_stable_row(&self) -> u64; WasmTerminalCore::first_stable_row_lo() -> u32; first_stable_row_hi() -> u32
  ```

- [ ] **Step 1: Write the failing tests**

`crates/vt-core/tests/stable_rows.rs`:

```rust
mod common;

use vt_core::{Limits, TerminalCore};

fn core() -> TerminalCore {
    let mut core = TerminalCore::with_limits(40, Limits::rows_only(6)).unwrap();
    core.resize(40, 2);
    core
}

fn feed_lines(core: &mut TerminalCore, lines: &[&str]) {
    for line in lines {
        core.feed(format!("{line}\r\n").as_bytes());
    }
}

#[test]
fn stable_row_survives_trim() {
    let mut core = core();
    feed_lines(&mut core, &["1", "2", "3", "4"]);
    assert_eq!(core.first_stable_row(), 0);
    assert_eq!(core.stable_row(2), 2);
    assert_eq!(core.snapshot().unwrap().row_text(2), "3");
    feed_lines(&mut core, &["5", "6", "7"]);
    assert_eq!(core.first_stable_row(), 1);
    let flat = core.flat_row(2).expect("row 3 is still retained");
    assert_eq!(flat, 1);
    assert_eq!(core.stable_row(flat), 2);
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.first_stable_row, 1);
    assert_eq!(snapshot.row_text(flat), "3");
    common::check(&core);
}

#[test]
fn flat_row_is_none_after_trim() {
    let mut core = core();
    feed_lines(&mut core, &["1", "2", "3", "4", "5", "6", "7"]);
    assert_eq!(core.first_stable_row(), 1);
    assert_eq!(core.flat_row(0), None);
    assert_eq!(core.flat_row(1), Some(0));
    common::check(&core);
}

#[test]
fn blocks_keep_rows_across_trim() {
    let mut core = core();
    feed_lines(&mut core, &["1", "2"]);
    core.feed(b"\x1b]133;A\x07");
    let before = core.snapshot().unwrap();
    assert_eq!(before.blocks.len(), 2);
    assert_eq!(before.blocks[1].first_row, 2);
    assert_eq!(core.stable_row(before.blocks[1].first_row as usize), 2);
    feed_lines(&mut core, &["3", "4", "5", "6", "7"]);
    let after = core.snapshot().unwrap();
    assert_eq!(after.first_stable_row, 1);
    assert_eq!(after.blocks.len(), 2);
    assert_eq!(after.blocks[0].first_row, 0);
    assert_eq!(after.blocks[0].row_count, 1);
    assert_eq!(after.blocks[1].first_row, 1);
    assert_eq!(core.stable_row(after.blocks[1].first_row as usize), 2);
    assert_eq!(after.row_text(after.blocks[1].first_row as usize), "3");
    common::check(&core);
}
```

Trace for the reader: with a 2-row screen, printing `n\r\n` evicts the previous line, so after `["1","2","3","4"]` the history is `1 2 3` and the screen shows `4` above a blank cursor row; `["5","6","7"]` evicts `4 5 6`, the row cap of 6 (five completed rows plus the open one) drops `1`, and `trimmed_total` becomes 1. In the third test the block opens at flat row 2 (one completed row plus the cursor on screen row 1), and the rows before it become an abandoned synthetic block.

Append to `crates/vt-core/tests/find.rs`:

```rust
#[test]
fn find_hits_carry_stable_rows_across_a_trim() {
    let mut core = TerminalCore::with_limits(40, vt_core::Limits::rows_only(6)).unwrap();
    core.resize(40, 2);
    for line in ["1", "2", "needle", "4"] {
        core.feed(format!("{line}\r\n").as_bytes());
    }
    let mut cursor = core.find(FindQuery::literal("needle"));
    while !cursor.is_complete() {
        cursor.step(4);
    }
    assert_eq!(cursor.results()[0].row, 2);
    for line in ["5", "6", "7"] {
        core.feed(format!("{line}\r\n").as_bytes());
    }
    let mut cursor = core.find(FindQuery::literal("needle"));
    while !cursor.is_complete() {
        cursor.step(4);
    }
    assert_eq!(core.first_stable_row(), 1);
    assert_eq!(cursor.results()[0].row, 2);
    assert_eq!(core.snapshot().unwrap().row_text(core.flat_row(2).unwrap()), "needle");
}
```

Rewrite the five `BlockGrid` unit tests that call `trim_to_first_row` (`block_grid.rs:416-518`) to the origin API. The first one in full; the other four keep their names and assert the same numbers through `flat_extent`:

```rust
    #[test]
    fn trimming_drops_blocks_whose_rows_are_all_gone() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();
        grid.note_row_completed();
        grid.close_block(Some(0));
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();

        grid.advance_origin(2);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].first_row, 2, "the open block keeps its stable row");
        assert_eq!(grid.flat_extent(blocks[0]), (0, 1));
        assert_eq!(grid.origin(), 2);
    }
```

For `a_partially_trimmed_block_keeps_its_surviving_rows`: `advance_origin(2)` → `flat_extent == (0, 3)` and `first_row == 0` (stable, unchanged). For `trim_inside_a_closed_block_does_not_underflow`: extents `(0, 3)` and `(3, 1)`. For `trim_after_popping_all_closed_blocks_keeps_open_block_rows`: one block left, extent `(0, 3)`. For `partial_trim_rebases_an_open_block_after_an_unmarked_prefix`: `sync_next_row(2)` then open, six rows, `advance_origin(5)` → extent `(0, 3)`.

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test stable_rows`
Expected: compile errors (`first_stable_row`, `flat_row`, `first_stable_row` field).

- [ ] **Step 3: Implement**

`block_grid.rs` — add the field and the conversions:

```rust
pub struct BlockGrid {
    closed: BlockTree,
    open: Option<Block>,
    next_id: BlockId,
    pending_meta: BlockMeta,
    pending_extension: bool,
    next_row: usize,
    origin: usize,
}

impl BlockGrid {
    pub fn origin(&self) -> usize {
        self.origin
    }

    pub fn advance_origin(&mut self, dropped: usize) {
        self.origin += dropped;
        while let Some(front) = self.closed.iter().next() {
            if front.first_row + front.row_count <= self.origin {
                self.closed.pop_front();
            } else {
                break;
            }
        }
        self.next_row = self.next_row.max(self.origin);
    }

    pub fn flat_extent(&self, block: &Block) -> (usize, usize) {
        let first = block.first_row.max(self.origin) - self.origin;
        let end = (block.first_row + block.row_count).max(self.origin) - self.origin;
        (first, end - first)
    }

    pub(crate) fn start_output(&mut self, first_row: usize) {
        if let Some(block) = self.open.as_mut() {
            if !block.meta.command.is_empty() {
                block.first_row = self.origin + first_row;
            }
        }
    }

    pub fn covered_end(&self) -> usize {
        let stable = match (&self.open, self.closed.len()) {
            (Some(block), _) => block.first_row,
            (None, 0) => self.origin,
            (None, len) => self
                .closed
                .get(len - 1)
                .map_or(self.origin, |block| block.first_row + block.row_count),
        };
        stable.max(self.origin) - self.origin
    }

    pub fn next_row(&self) -> usize {
        self.next_row - self.origin
    }

    pub fn sync_next_row(&mut self, next_row: usize) {
        self.next_row = self.origin + next_row;
    }

    pub fn push_synthetic(&mut self, first_row: usize, end_row: usize, state: BlockState, exit_code: Option<i32>) {
        if end_row <= first_row {
            return;
        }
        self.closed.push(Block {
            id: self.next_id,
            first_row: self.origin + first_row,
            row_count: end_row - first_row,
            state,
            source: BlockSource::Synthetic,
            meta: BlockMeta { exit_code, ..BlockMeta::default() },
        });
        self.next_id += 1;
    }

    pub fn clamp_to_rows(&mut self, total_rows: usize) {
        let limit = self.origin + total_rows;
        self.next_row = self.next_row.min(limit);
        if let Some(block) = self.open.as_mut() {
            block.first_row = block.first_row.min(limit);
        }
        let needs_clamp = self.closed.iter().any(|block| block.first_row + block.row_count > limit);
        if !needs_clamp {
            return;
        }
        let mut drained: Vec<Block> = Vec::new();
        while let Some(block) = self.closed.pop_front() {
            drained.push(block);
        }
        for mut block in drained {
            block.first_row = block.first_row.min(limit);
            block.row_count = block.row_count.min(limit - block.first_row);
            self.closed.push(block);
        }
    }

    pub fn remap_rows(&mut self, map: &[usize]) {
        let Some((&new_len, old_rows)) = map.split_last() else {
            return;
        };
        let old_len = old_rows.len();
        let origin = self.origin;
        let remap = |stable: usize| -> usize {
            if stable < origin {
                return stable;
            }
            let row = stable - origin;
            let new_row = match map.get(row) {
                Some(&new_row) => new_row,
                None => row - old_len + new_len,
            };
            origin + new_row
        };
        // the drain/push loop, the open-block line and `self.next_row = remap(self.next_row)` are the existing lines block_grid.rs:333-346, now calling this `remap`
    }
}
```

`open_block` and `close_block` compare `first_row` with `next_row`, both stable — unchanged. Delete `trim_to_first_row` and its doc comment (the "Task 11 CHANGELOG" remark in it is stale). Fix the struct doc comment that says rows are "relative to the oldest retained row" — they are stable rows now.

`parser.rs`:

```rust
pub(crate) struct Parser {
    // the existing fields (parser.rs:15-33) plus:
    trimmed_total: u64,
}

    pub fn first_stable_row(&self) -> u64 {
        self.trimmed_total
    }

    pub fn stable_row(&self, flat: usize) -> u64 {
        flat as u64 + self.trimmed_total
    }

    pub fn flat_row(&self, stable: u64) -> Option<usize> {
        stable.checked_sub(self.trimmed_total).map(|flat| flat as usize)
    }

    pub fn trim_to(&mut self, limits: Limits) -> usize {
        // the trim loop from Task 2 is unchanged
        let dropped = before - self.rows.completed().len();
        if dropped > 0 {
            self.trimmed_total += dropped as u64;
            self.grid.advance_origin(dropped);
        }
        dropped
    }
```

`grid.rs`: `GridSnapshot` gains `pub first_stable_row: u64`; `build_snapshot` takes `first_stable_row: u64` as its last parameter and stores it; the block loop becomes:

```rust
        for block in grid.blocks() {
            let (flat_first, flat_count) = grid.flat_extent(block);
            let command = append_block_text(&mut block_text, &block.meta.command)?;
            let cwd = append_block_text(&mut block_text, &block.meta.cwd)?;
            let git_branch = append_block_text(&mut block_text, &block.meta.git_branch)?;
            let first_row = checked_u32(flat_first)?;
            let row_count = if block.state == BlockState::Running {
                checked_u32(row_ranges.len().saturating_sub(flat_first))?
            } else {
                checked_u32(flat_count)?
            };
            // the rest of the loop body (grid.rs:141-160: duration, records.push) is unchanged
        }
```

`lib.rs`: `snapshot()` passes `self.parser.first_stable_row()`; add the three delegating methods.

`find.rs`: `pub row: u64`; `block_byte_range(rows, grid, block)` uses `let (first, count) = grid.flat_extent(block); if count == 0 { return None; } let last = first + count - 1;`; `row_for_offset` result becomes `(row as u64) + grid.origin() as u64` at the two call sites that build a `FindMatch`.

`integrity.rs`: replace the block loop's `block.first_row + block.row_count` / `block.first_row` with `grid.flat_extent(block)` (`end = first + count` for closed blocks, `first` for the open one); add before the style-key loop:

```rust
        if self.grid().origin() as u64 != self.trimmed_total() {
            return Err(IntegrityError::OriginMismatch {
                origin: self.grid().origin(),
                trimmed_total: self.trimmed_total(),
            });
        }
```

with `pub(crate) fn trimmed_total(&self) -> u64` on `Parser`.

`vt-wasm`: `ExportBuffers` gains `first_stable_row: u64`, set in `refresh` from `snapshot.first_stable_row`, read by `first_stable_row()`; `WasmTerminalCore::first_stable_row_lo()` returns `self.export.first_stable_row() as u32`, `_hi()` `(self.export.first_stable_row() >> 32) as u32`; in `find_step` the row word becomes `checked_u32_from_u64(hit.row).map_err(|_| ExportError::FindOffsetOverflow)?`. `tests/exit_encoding.rs` adds `first_stable_row: 0,` to the fixture.

- [ ] **Step 4: Run the tests**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core && cargo test -p vt-wasm`
Expected: green, including `tests/integrity.rs` (the proptest and `a_trim_past_a_block_that_starts_above_the_cut_does_not_underflow`, `TERMINAL.md` §4.17) and `tests/rewrap.rs` (`remap_rows` still moves blocks with their rows).

- [ ] **Step 5: CHANGELOG**

```
Rows have stable ids.

- `TerminalCore::stable_row(flat)` / `flat_row(stable)` / `first_stable_row()`
  (WezTerm `term/src/screen.rs` `stable_row_index_offset`): a row keeps its id
  when older rows are trimmed. `BlockGrid` stores stable rows and is no longer
  renumbered by a trim; the snapshot exports `first_stable_row`; find hits
  report stable rows.
```

- [ ] **Step 6: Verify, rebuild both wasm artifacts and the daemon, commit**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom react; do (cd ts/$p && npx vitest run); done && npm run bench:selection && npm run bench:feel
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: all green; `PASS feel gate: zero pixel diff` (the TS side does not read the new field yet).

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && git commit -m "vt-core: stable row ids; BlockGrid keeps its rows across a trim; find hits and the snapshot carry stable rows" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

### Task 5: The renderer addresses rows by stable id (§1.3.C, renderer half)

Today `data-terminal-row` carries the row's offset inside its block (`row-builder.ts:37`, label = `rowOffset` from `block-body.ts:31`), selection points are `{ blockId, row: <block-relative>, ... }` (`selection-model.ts:5`), and `find-bar.ts:110-122` queries `[data-terminal-row="${match.row}"]` with a **flat** row, which only matches while the block starts at flat row 0. After this task every `data-terminal-row` is the stable row, selection points and find hits hold stable rows, and `paintedRowOrigin` converts through `firstStableRow`.

**Files:**
- Modify: `packages/terminal/ts/core/src/types.ts:69-89` (`TerminalSnapshot.firstStableRow`), `:25-30` (`FindMatch.row` is the stable row)
- Modify: `packages/terminal/ts/core/src/terminal-core.ts:177-241` (`snapshot()` reads `first_stable_row_lo/hi`)
- Modify: `packages/terminal/ts/renderer-dom/src/block-body.ts:19-44` (label = `firstStableRow + snapshotRow`; `BlockBodyInput.firstStableRow`)
- Modify: `packages/terminal/ts/renderer-dom/src/selection-geometry.ts` (`RowBox.firstRow`, clamp in `pointAtFromRows`)
- Modify: `packages/terminal/ts/renderer-dom/src/selection-text.ts` (`TextRows.firstRow`, `selectedText` bounds)
- Modify: `packages/terminal/ts/renderer-dom/src/selection-view.ts` (`snapshotTextRows` maps stable → flat, `renderedRows(altRoot, blocks, elements, firstStableRow)`)
- Modify: `packages/terminal/ts/renderer-dom/src/row-geometry.ts` (`paintedRowOrigin(..., firstStableRow)`)
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:183-190,212-216,266-271,474-482,530-532`
- Modify tests: `selection-geometry.test.ts`, `selection-text.test.ts`, `row-geometry.test.ts`, `selection-model.test.ts` (new "a selection survives a trim above it"), `find-bar.test.ts` (labels), `terminal-selection.test.ts` (if any assertion reads `data-terminal-row` values)
- Modify: `packages/terminal/bench/agent-session/scroll-gate.mjs` (contiguity is now per stable row, unchanged logic — just confirm it passes)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: Task 4's `first_stable_row_lo/hi`, `FindMatch.row` (stable).
- Produces:
  ```ts
  // @operator/terminal-core
  TerminalSnapshot.firstStableRow: number
  // renderer-dom
  type RowBox = Readonly<{ blockId: string; row: number; firstRow: number; rowCount: number; left; top; bottom; width }>  // row and firstRow are stable rows
  type TextRows = Readonly<{ rowText(blockId, row: number): string; firstRow(blockId): number; rowCount(blockId): number; blockIds: readonly string[] }>
  function renderedRows(altRoot, filteredBlocks, blockElements, firstStableRow: number): RenderedRow[]
  function paintedRowOrigin(blocks, elements, row: number /* flat */, cellHeight, firstStableRow: number): RowOrigin | null
  type BlockBodyInput = Readonly<{ block; snapshot; rowWindow; rowHeight; cellWidth; cursor; decoder; firstStableRow: number }>
  ```
  `SelectionPoint.row`, `Boundary.row` and `FindMatch.row` are stable rows. `DomBlockRenderer.rowOrigin(row)` still takes a flat row (its one caller, `ts/react/src/surface-geometry.ts:54`, passes `firstScreenRow(snapshot, grid.rows)`).

- [ ] **Step 1: Write the failing tests**

`ts/core/src/terminal-core.test.ts`:

```ts
	it("exports the first stable row and keeps it across a trim", () => {
		const core = createTerminalCore({ columns: 40, limits: { rows: 6, bytes: 0xffff_ffff }, rows: 2 });
		const encoder = new TextEncoder();
		for (const line of ["1", "2", "3", "4"]) core.feed(encoder.encode(`${line}\r\n`));
		expect(core.snapshot().firstStableRow).toBe(0);
		for (const line of ["5", "6", "7"]) core.feed(encoder.encode(`${line}\r\n`));
		const snapshot = core.snapshot();
		expect(snapshot.firstStableRow).toBe(1);
		const flat = 2 - snapshot.firstStableRow;
		expect(new TextDecoder().decode(snapshot.content.subarray(snapshot.rows[flat * 2]!, snapshot.rows[flat * 2 + 1]!))).toBe("3");
	});
```

`ts/renderer-dom/src/selection-model.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "./dom-block-renderer";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");
beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

describe("stable-row selection", () => {
	it("a selection survives a trim above it", async () => {
		const core = createTerminalCore({ columns: 40, limits: { rows: 6, bytes: 0xffff_ffff }, rows: 2 });
		const encoder = new TextEncoder();
		for (const line of ["1", "2", "needle", "4"]) core.feed(encoder.encode(`${line}\r\n`));
		const host = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		const blockId = host.querySelector<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId, row: 2, column: 0, side: "left" }, "line");
		expect(renderer.selectedText()).toBe("needle");
		for (const line of ["5", "6", "7"]) core.feed(encoder.encode(`${line}\r\n`));
		expect(core.snapshot().firstStableRow).toBe(1);
		expect(renderer.selectedText()).toBe("needle");
		await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
		expect(host.querySelector('[data-terminal-row="2"]')?.textContent).toBe("needle");
		expect(host.querySelector('[data-terminal-row="0"]')).toBeNull();
		renderer.dispose();
	});
});
```

`selection-geometry.test.ts`: the `box` helper gains `firstRow`: `const box = (blockId, row, top, rowCount = 4, firstRow = 0): RowBox => ({ blockId, row, firstRow, rowCount, left: 100, top, bottom: top + ch, width: 400 })`, and add:

```ts
	it("clamps to the block's stable rows", () => {
		const rows = [box("a", 10, 0, 4, 10)];
		expect(pointAtFromRows(rows, 100, 1000, cw, ch)!.row).toBe(13);
		expect(pointAtFromRows(rows, 100, -1000, cw, ch)!.row).toBe(10);
	});
```

`selection-text.test.ts`: `rows` gains `firstRow: () => 0`, plus:

```ts
	it("walks whole rows from the block's first stable row", () => {
		const shifted: TextRows = { blockIds: ["a"], firstRow: () => 100, rowCount: () => 3, rowText: (_id, row) => blocks.a![row - 100] ?? "" };
		expect(selectedText({ start: { blockId: "a", row: 100, cell: 6 }, end: { blockId: "a", row: 102, cell: 5 } }, shifted)).toBe("beta\n\ngamma");
	});
```

`row-geometry.test.ts`: the `section` helper labels rows with stable ids; the existing case becomes `section([0, 1, 2], …)`, `section([3, 4, 5, 6], …)` (labels are now `firstStableRow + flat`) and `paintedRowOrigin(blocks, elements, 4, 16, 0)`; add a case with `firstStableRow = 100` and labels `[103, 104, 105, 106]` expecting the same `{ left: 40, top: 216 }`.

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run terminal-core.test.ts -t "first stable row"; cd ../renderer-dom && npx vitest run selection-model.test.ts selection-geometry.test.ts selection-text.test.ts row-geometry.test.ts`
Expected: FAIL (`firstStableRow` undefined; type errors on `firstRow`; the trim test selects the wrong row).

- [ ] **Step 3: Implement**

`ts/core`: `TerminalSnapshot` gains `firstStableRow: number`; in `snapshot()`: `firstStableRow: this.inner.first_stable_row_hi() * 2 ** 32 + this.inner.first_stable_row_lo(),`.

`block-body.ts`: `BlockBodyInput` gains `firstStableRow: number`; the loop builds `buildRowNode(snapshot, snapshotRow, input.firstStableRow + snapshotRow, decoder, input.cellWidth)`.

`selection-geometry.ts`:

```ts
export type RowBox = Readonly<{ blockId: string; row: number; firstRow: number; rowCount: number; left: number; top: number; bottom: number; width: number }>;

	const rowDelta = Math.floor((y - anchor.top) / cellHeight);
	const last = anchor.firstRow + Math.max(anchor.rowCount - 1, 0);
	const row = Math.min(Math.max(anchor.row + rowDelta, anchor.firstRow), last);
```

`selection-text.ts`:

```ts
export type TextRows = Readonly<{
	rowText(blockId: string, row: number): string;
	firstRow(blockId: string): number;
	rowCount(blockId: string): number;
	blockIds: readonly string[];
}>;

		const fromRow = index === first ? range.start.row : rows.firstRow(blockId);
		let toRow = index === last ? range.end.row : rows.firstRow(blockId) + rows.rowCount(blockId) - 1;
```

`selection-view.ts`:

```ts
export function snapshotTextRows(snapshot: TerminalSnapshot, filter: BlockFilter | null, decoder: TextDecoder): TextRows {
	// rowString unchanged
	const alt = snapshot.altScreen;
	if (alt) {
		return { blockIds: [ALT_BLOCK_ID], firstRow: () => 0, rowCount: () => alt.rows, rowText: (_id, row) => rowString(alt.content, alt.rowRanges, row) };
	}
	const blocks = applyFilter(decodeBlocks(snapshot), filter).map((block) => trimTrailingBlankRows(snapshot, block));
	const byId = new Map(blocks.map((block) => [block.id, block] as const));
	const base = snapshot.firstStableRow;
	return {
		blockIds: blocks.map((block) => block.id),
		firstRow: (id) => base + (byId.get(id)?.firstRow ?? 0),
		rowCount: (id) => byId.get(id)?.rowCount ?? 0,
		rowText: (id, row) => {
			const block = byId.get(id);
			if (!block) return "";
			const flat = row - base;
			if (flat < block.firstRow || flat >= block.firstRow + block.rowCount) return "";
			return rowString(snapshot.content, snapshot.rows, flat);
		},
	};
}

export function renderedRows(altRoot, filteredBlocks, blockElements, firstStableRow: number): RenderedRow[] {
	const push = (blockId: string, firstRow: number, rowCount: number, element: HTMLElement) => { /* box gains firstRow */ };
	// alt: push(ALT_BLOCK_ID, 0, rows.length, row)
	const byId = new Map(filteredBlocks.map((block) => [block.id, block] as const));
	for (const [id, section] of blockElements) {
		const block = byId.get(id);
		for (const row of section.querySelectorAll<HTMLElement>("[data-terminal-row]")) {
			push(id, firstStableRow + (block?.firstRow ?? 0), block?.rowCount ?? 0, row);
		}
	}
```

`row-geometry.ts`: `paintedRowOrigin(blocks, elements, row, cellHeight, firstStableRow)` with `const target = firstStableRow + row;` (the `blocks.find` still uses flat `row`).

`dom-block-renderer.ts`: `rowOrigin(row)` passes `this.core.snapshot().firstStableRow`; `renderedRows()` passes it too; `populateBlock` gets `firstStableRow: snapshot.firstStableRow`. The `selectionUpdate` path is unchanged: points already come from `pointAt`, which now yields stable rows.

`find-bar.ts` needs no code change: `match.row` is now the stable row and so is the label. Add to `find-bar.test.ts` one case where the block's rows are labelled from a non-zero stable base and a match with that row is highlighted.

- [ ] **Step 4: Run the suites**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in core renderer-dom react; do (cd ts/$p && npx vitest run); done`
Expected: green. `terminal-selection.test.ts` and `TerminalSurface.mouse.test.tsx` pass unchanged (single block at stable row 0 → same numbers).

- [ ] **Step 5: Gates**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection && npm run bench:feel && npm run bench:agent:scroll`
Expected: selection gate passes (a selection survives 20 repaints); `PASS feel gate: zero pixel diff` (labels are attributes, not pixels); the scroll gate reports the same `covered`/`total` as before — the per-block contiguity check is unaffected because stable rows are consecutive inside a block.

- [ ] **Step 6: CHANGELOG and commit**

```
- `data-terminal-row` carries the stable row; selection points, find hits and
  `paintedRowOrigin` address rows by stable id, so a selection no longer drifts
  when scrollback is trimmed above it.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal && git commit -m "renderer-dom: rows, selection and find hits addressed by stable row id" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Dirty tracking, `generation`, `Delta` and the row-export API in `vt-core` (§1.3.B, model half)

Reference: `ghostty/src/terminal/render.zig:280-295` (`Dirty { false, partial, full }`), `:26-40` (why a stateful update replaced the per-frame clone), `ghostty/src/terminal/page.zig:2067-2078` (per-row dirty set by every write). `wezterm/wezterm-surface/src/line/line.rs:283-300` (`last_change_seqno`) is the sequence-number idea behind `generation`.

**Files:**
- Create: `packages/terminal/crates/vt-core/src/delta.rs`
- Modify: `packages/terminal/crates/vt-core/src/screen.rs` (`dirty`, `mark_dirty`, `mark_all_dirty`, `take_dirty`, `raise_max_cursor_row`; marks in `set:240`, `blank_row:251`, `rotate_region_up:289`, `rotate_region_down:301`, `attach_zerowidth:389`, `reset:424`, `reset_cells:455`, `resize_cells:486`; `move_to:331`, `print:373`, `attach_zerowidth:401` use `raise_max_cursor_row`)
- Modify: `packages/terminal/crates/vt-core/src/parser.rs` (`generation`, `history_exported_rows`, `pending_full`, `pending_trimmed`, `pending_remap`, `note_mutation`, `mark_full`, `note_remap`, `take_delta`; marks in `resize:331`, `enter_alt:167`, `leave_alt:181`, `process_boundary:101`, `commit_evicted:363-366`, `trim_to`)
- Modify: `packages/terminal/crates/vt-core/src/grid.rs` (`ExportedRow`, `export_history_row`, `export_screen_row`, `export_blocks`; `build_snapshot` rebuilt on them; `GridSnapshot.history_rows`)
- Modify: `packages/terminal/crates/vt-core/src/lib.rs` (`generation`, `take_delta`, `history_rows`, `export_*`, `alt_snapshot`; `note_mutation` calls in `feed_raw`, `resize`, `set_block_bookmarked`)
- Modify: `packages/terminal/crates/vt-core/src/integrity.rs` (`ExportPrefixPastRows`)
- Create: `packages/terminal/crates/vt-core/tests/delta.rs`
- Modify: `packages/terminal/crates/vt-wasm/src/export.rs` + `tests/exit_encoding.rs` (the `history_rows` field, so the workspace compiles)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: Task 4's `trimmed_total`, `flat_extent`; `RowIndex::rewrap` map (`row_index.rs:100-120`, old flat row → new flat row, last element = new length).
- Produces:
  ```rust
  // vt_core::delta (re-exported at the crate root)
  #[derive(Clone, Copy, Debug, PartialEq, Eq)]
  pub enum DeltaKind { Full, Partial }
  #[derive(Clone, Debug, PartialEq, Eq)]
  pub struct Delta {
      pub generation: u64,
      pub kind: DeltaKind,
      pub trimmed_rows: usize,                 // exported history rows dropped from the front since the last delta
      pub appended_history: Range<usize>,      // flat indices of completed rows not yet exported (post-trim numbering)
      pub screen_rows: Vec<usize>,             // screen-relative dirty rows (Partial) or 0..content_rows (Full), ascending
      pub remap: Option<Vec<(u64, u64)>>,      // (old stable row, new stable row) after a rewrap, composed if two happened
  }
  // vt_core::grid (re-exported)
  #[derive(Clone, Debug, PartialEq, Eq)]
  pub struct ExportedRow { pub bytes: Vec<u8>, pub indent: u16, pub styles: Vec<(u32, CellStyle)> }
  // GridSnapshot
  pub history_rows: u32
  // TerminalCore
  pub fn generation(&self) -> u64
  pub fn take_delta(&mut self) -> Delta
  pub fn history_rows(&self) -> usize                                   // completed rows
  pub fn export_history_rows(&self, range: Range<usize>) -> Vec<ExportedRow>
  pub fn export_screen_rows(&self) -> Vec<ExportedRow>                   // content_rows() rows
  pub fn export_blocks(&self, total_rows: usize, row_has_bytes: impl Fn(usize) -> bool) -> Result<(Vec<BlockRecord>, Vec<u8>), CoreError>
  pub fn export_cursor(&self) -> (usize, usize, bool)                    // flat row, column, visible
  pub fn alt_snapshot(&self) -> Option<alt::AltSnapshot>
  // ScreenGrid (pub(crate))
  fn mark_dirty(&mut self, row: usize); fn mark_all_dirty(&mut self); pub fn take_dirty(&mut self) -> Vec<usize>
  // IntegrityError
  ExportPrefixPastRows { exported: usize, completed: usize }
  ```
  `generation` starts at 0 and increments once per `feed_raw` that reached the parser, per `resize`, per `set_block_bookmarked`. The first `take_delta` after construction is `Full`.

- [ ] **Step 1: Write the failing tests**

`crates/vt-core/tests/delta.rs`:

```rust
mod common;

use vt_core::{Delta, DeltaKind, Limits, TerminalCore};

fn core() -> TerminalCore {
    let mut core = TerminalCore::with_limits(40, Limits::rows_only(6)).unwrap();
    core.resize(40, 3);
    let first = core.take_delta();
    assert_eq!(first.kind, DeltaKind::Full);
    core
}

fn feed_lines(core: &mut TerminalCore, lines: &[&str]) {
    for line in lines {
        core.feed(format!("{line}\r\n").as_bytes());
    }
}

#[test]
fn printing_marks_one_screen_row_dirty() {
    let mut core = core();
    feed_lines(&mut core, &["a", "b"]);
    core.take_delta();
    let before = core.generation();
    core.feed(b"\x1b[2;1HX");
    assert_eq!(core.generation(), before + 1);
    let delta = core.take_delta();
    assert_eq!(delta.kind, DeltaKind::Partial);
    assert_eq!(delta.screen_rows, vec![1]);
    assert_eq!(delta.appended_history, 0..0);
    assert_eq!(delta.trimmed_rows, 0);
    assert_eq!(delta.remap, None);
    assert_eq!(core.snapshot().unwrap().row_text(1), "X");
    common::check(&core);
}

#[test]
fn scroll_off_appends_history_and_marks_moved_rows() {
    let mut core = core();
    feed_lines(&mut core, &["a", "b", "c"]);
    core.take_delta();
    feed_lines(&mut core, &["d"]);
    let delta = core.take_delta();
    assert_eq!(delta.kind, DeltaKind::Partial);
    assert_eq!(delta.appended_history, 1..2);
    assert_eq!(delta.screen_rows, vec![0, 1, 2]);
    assert_eq!(core.history_rows(), 2);
    let snapshot = core.snapshot().unwrap();
    assert_eq!(snapshot.history_rows, 2);
    assert_eq!(snapshot.row_text(1), "b");
    common::check(&core);
}

#[test]
fn rewrap_yields_full_delta_with_remap() {
    let mut core = TerminalCore::with_limits(20, Limits::rows_only(100)).unwrap();
    core.resize(20, 2);
    core.take_delta();
    core.feed(b"aaaaaaaaaabbbbbbbbbbcccccccccc\r\n");
    core.feed(b"tail\r\n");
    core.take_delta();
    assert_eq!(core.history_rows(), 2);
    core.resize(40, 2);
    let delta = core.take_delta();
    assert_eq!(delta.kind, DeltaKind::Full);
    assert_eq!(core.history_rows(), 2);
    assert_eq!(delta.remap, Some(vec![(0, 0), (1, 0), (2, 1)]));
    assert_eq!(delta.screen_rows, vec![0]);
    assert_eq!(core.snapshot().unwrap().row_text(0), "aaaaaaaaaabbbbbbbbbbcccccccccc");
    assert_eq!(core.snapshot().unwrap().row_text(1), "tail");
    common::check(&core);
}

#[test]
fn trim_reports_trimmed_rows() {
    let mut core = core();
    feed_lines(&mut core, &["1", "2", "3", "4", "5"]);
    let first = core.take_delta();
    assert_eq!(first.appended_history, 0..3);
    feed_lines(&mut core, &["6", "7", "8"]);
    let delta = core.take_delta();
    assert_eq!(delta.kind, DeltaKind::Partial);
    assert_eq!(delta.trimmed_rows, 1);
    assert_eq!(delta.appended_history, 2..5);
    assert_eq!(core.first_stable_row(), 1);
    common::check(&core);
}

#[test]
fn take_delta_clears() {
    let mut core = core();
    feed_lines(&mut core, &["a", "b", "c", "d"]);
    let first = core.take_delta();
    assert_ne!(first.screen_rows, Vec::<usize>::new());
    let generation = core.generation();
    let second = core.take_delta();
    assert_eq!(
        second,
        Delta {
            generation,
            kind: DeltaKind::Partial,
            trimmed_rows: 0,
            appended_history: 2..2,
            screen_rows: Vec::new(),
            remap: None,
        }
    );
    common::check(&core);
}

#[test]
fn alt_screen_and_process_boundary_are_full() {
    let mut core = core();
    feed_lines(&mut core, &["a"]);
    core.take_delta();
    core.feed(b"\x1b[?1049h");
    assert_eq!(core.take_delta().kind, DeltaKind::Full);
    core.feed(b"x");
    assert_eq!(core.take_delta().kind, DeltaKind::Full);
    core.feed(b"\x1b[?1049l");
    assert_eq!(core.take_delta().kind, DeltaKind::Full);
    core.feed(b"\x1b]7000;v=1;boundary=0\x07");
    assert_eq!(core.take_delta().kind, DeltaKind::Full);
    common::check(&core);
}

#[test]
fn snapshot_equals_the_export_api() {
    let mut core = core();
    feed_lines(&mut core, &["\x1b[31mred\x1b[0m", "plain", "  - bullet"]);
    let snapshot = core.snapshot().unwrap();
    let history = core.export_history_rows(0..core.history_rows());
    let screen = core.export_screen_rows();
    assert_eq!(history.len() + screen.len(), snapshot.row_count());
    for (index, row) in history.iter().chain(screen.iter()).enumerate() {
        assert_eq!(row.bytes, snapshot.row_text(index).as_bytes());
        assert_eq!(usize::from(row.indent), snapshot.row_indent(index));
        assert_eq!(row.styles.as_slice(), snapshot.row_style_pairs(index));
    }
    let (records, text) = core
        .export_blocks(snapshot.row_count(), |row| snapshot.rows[row].1 > snapshot.rows[row].0)
        .unwrap();
    assert_eq!(records, snapshot.blocks);
    assert_eq!(text, snapshot.block_text);
    let (row, col, visible) = core.export_cursor();
    assert_eq!((row as u32, col as u32, visible), (snapshot.cursor_row, snapshot.cursor_col, snapshot.cursor_visible));
}
```

Traces the reader needs: `core()` uses a 3-row screen, so `["a","b"]` leaves `a` on row 0, `b` on row 1 and the cursor on row 2; `CSI 2;1 H X` overwrites row 1 only. In `scroll_off…`, `["a","b","c"]` fills rows 0–2 with the cursor wrapping: the `\r\n` after `c` scrolls `a` into history (`history_rows == 1`, exported by the `take_delta`), then `d` scrolls `b` off — history rows `1..2` appended, every screen row rotated. In `rewrap…` at 20 columns the 30-character line wraps across screen rows 0–1; its `\r\n` evicts the first 20 characters as a `wrapped` history row and `tail`'s `\r\n` evicts the remaining 10, so history is two rows with `tail` on the screen. The shell-mode resize (`reflow_on_resize`) evicts `tail` too, then the rewrap joins the three old rows into two (`row_index.rs:100-120` maps old 0→0, 1→0, 2→1) and the screen restarts blank with one content row. In `trim…`, five lines through a 3-row screen commit `1 2 3` (the delta exports them); three more commit `4 5 6`, the cap of 6 drops `1`, so one exported row is trimmed and `4 5 6` are flat `2..5`.

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test delta`
Expected: compile errors (`Delta`, `take_delta`, `generation`, `history_rows`, `export_*`).

- [ ] **Step 3: Implement `delta.rs`, the screen dirty bits and the parser bookkeeping**

`crates/vt-core/src/delta.rs`:

```rust
use std::ops::Range;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DeltaKind {
    Full,
    Partial,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Delta {
    pub generation: u64,
    pub kind: DeltaKind,
    pub trimmed_rows: usize,
    pub appended_history: Range<usize>,
    pub screen_rows: Vec<usize>,
    pub remap: Option<Vec<(u64, u64)>>,
}
```

`screen.rs`:

```rust
pub struct ScreenGrid {
    // the existing fields (screen.rs:89-108) plus:
    dirty: Vec<bool>,
}

    // in new(): dirty: vec![false; rows],

    fn mark_dirty(&mut self, row: usize) {
        if let Some(flag) = self.dirty.get_mut(row) {
            *flag = true;
        }
    }

    fn mark_all_dirty(&mut self) {
        self.dirty.fill(true);
    }

    pub fn take_dirty(&mut self) -> Vec<usize> {
        let exported = self.content_rows().min(self.rows);
        let mut rows = Vec::new();
        for row in 0..exported {
            if self.dirty[row] {
                self.dirty[row] = false;
                rows.push(row);
            }
        }
        rows
    }

    fn raise_max_cursor_row(&mut self, row: usize) {
        if row > self.max_cursor_row {
            for new_row in self.max_cursor_row + 1..=row {
                self.mark_dirty(new_row);
            }
            self.max_cursor_row = row;
        }
    }
```

`set` marks `row` after the write; `blank_row` marks `row`; `attach_zerowidth` marks `row` after `push_zerowidth`; `rotate_region_up`, `rotate_region_down` and `reset` call `mark_all_dirty()`; `reset_cells` and `resize_cells` set `self.dirty = vec![true; rows]`; the three `self.max_cursor_row = self.max_cursor_row.max(...)` lines become `self.raise_max_cursor_row(...)`.

`parser.rs`:

```rust
pub(crate) struct Parser {
    // the existing fields plus Task 4's `trimmed_total`, plus:
    generation: u64,
    history_exported_rows: usize,
    pending_full: bool,
    pending_trimmed: usize,
    pending_remap: Option<Vec<(u64, u64)>>,
}
// new(): generation: 0, history_exported_rows: 0, pending_full: true, pending_trimmed: 0, pending_remap: None

    pub(crate) fn note_mutation(&mut self) {
        self.generation = self.generation.wrapping_add(1);
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    pub(crate) fn history_exported_rows(&self) -> usize {
        self.history_exported_rows
    }

    fn mark_full(&mut self) {
        self.pending_full = true;
    }

    fn note_remap(&mut self, map: &[usize]) {
        let Some((_, old_rows)) = map.split_last() else {
            return;
        };
        let origin = self.trimmed_total;
        let pairs: Vec<(u64, u64)> = old_rows
            .iter()
            .enumerate()
            .map(|(old, &new)| (old as u64 + origin, new as u64 + origin))
            .collect();
        self.pending_remap = Some(match self.pending_remap.take() {
            None => pairs,
            Some(previous) => previous
                .into_iter()
                .map(|(first, mid)| {
                    let last = mid
                        .checked_sub(origin)
                        .and_then(|index| old_rows.get(index as usize))
                        .map_or(mid, |&new| new as u64 + origin);
                    (first, last)
                })
                .collect(),
        });
    }

    pub fn take_delta(&mut self) -> Delta {
        let completed = self.rows.completed().len();
        let full = std::mem::take(&mut self.pending_full) || self.alt.is_some();
        let screen_rows = if full {
            self.screen.take_dirty();
            (0..self.screen.content_rows()).collect()
        } else {
            self.screen.take_dirty()
        };
        let delta = Delta {
            generation: self.generation,
            kind: if full { DeltaKind::Full } else { DeltaKind::Partial },
            trimmed_rows: std::mem::take(&mut self.pending_trimmed),
            appended_history: self.history_exported_rows.min(completed)..completed,
            screen_rows,
            remap: self.pending_remap.take(),
        };
        self.history_exported_rows = completed;
        delta
    }
```

`resize` calls `self.mark_full()` first; `enter_alt` and `leave_alt` call `self.mark_full()`; `process_boundary` calls `self.mark_full()` first; in `commit_evicted` the rewrap branch becomes:

```rust
        if std::mem::take(&mut self.rewrap_pending) {
            let map = self.rows.rewrap(&self.content, self.width);
            self.grid.remap_rows(&map);
            self.note_remap(&map);
            self.history_exported_rows = self.history_exported_rows.min(self.rows.completed().len());
            self.mark_full();
        }
```

`trim_to` after computing `dropped`:

```rust
        if dropped > 0 {
            let exported_dropped = dropped.min(self.history_exported_rows);
            self.history_exported_rows -= exported_dropped;
            self.pending_trimmed += exported_dropped;
            self.trimmed_total += dropped as u64;
            self.grid.advance_origin(dropped);
        }
```

`lib.rs`: `feed_raw` calls `self.parser.note_mutation()` after `trim_to` (before `debug_check`); `resize` and `set_block_bookmarked` call it after their mutation. Add:

```rust
    pub fn generation(&self) -> u64 {
        self.parser.generation()
    }

    pub fn take_delta(&mut self) -> Delta {
        self.parser.take_delta()
    }

    pub fn history_rows(&self) -> usize {
        self.parser.rows().completed().len()
    }

    pub fn export_history_rows(&self, range: Range<usize>) -> Vec<ExportedRow> {
        let completed = self.parser.rows().completed();
        range
            .filter_map(|index| completed.get(index))
            .map(|row| grid::export_history_row(self.parser.content(), self.parser.styles(), row))
            .collect()
    }

    pub fn export_screen_rows(&self) -> Vec<ExportedRow> {
        let screen = self.parser.screen();
        (0..screen.content_rows())
            .map(|row| grid::export_screen_row(screen, row))
            .collect()
    }

    pub fn export_blocks(
        &self,
        total_rows: usize,
        row_has_bytes: impl Fn(usize) -> bool,
    ) -> Result<(Vec<BlockRecord>, Vec<u8>), CoreError> {
        grid::export_blocks(self.parser.grid(), total_rows, row_has_bytes)
    }

    pub fn export_cursor(&self) -> (usize, usize, bool) {
        let screen = self.parser.screen();
        let (row, col) = screen.cursor();
        (self.history_rows() + row, col, screen.cursor_visible())
    }

    pub fn alt_snapshot(&self) -> Option<alt::AltSnapshot> {
        self.parser.alt().map(|grid| grid.snapshot())
    }
```

`grid.rs`: extract `append_row` into `pub(crate) fn export_history_row(content, styles, row: &RowRange) -> ExportedRow` (bytes = `content.copy_range(row.start, row.end)`, styles = `styles.runs(row.start, row.end)` when non-empty else empty, indent = `row.indent`) and `append_screen_row` into `pub(crate) fn export_screen_row(screen, row) -> ExportedRow` (same loop, pairs relative to the row start, indent 0); `SnapshotCtx::push(&mut self, row: ExportedRow) -> Result<(), CoreError>` appends bytes, `(base, end)` range, indent, pairs and the run range. Move the block-record loop and the trailing synthetic record into `pub(crate) fn export_blocks(grid: &BlockGrid, total_rows: usize, row_has_bytes: impl Fn(usize) -> bool) -> Result<(Vec<BlockRecord>, Vec<u8>), CoreError>`; the Running-block `row_count` is `total_rows.saturating_sub(flat_first)` and the trailing check is `(covered_end..total_rows).any(&row_has_bytes)`. `build_snapshot` becomes: push every history row, remember `history_rows`, push every screen row, `export_blocks(grid, row_ranges.len(), |row| row_ranges[row].1 > row_ranges[row].0)`, cursor, and stores `history_rows: checked_u32(history_rows)?`. `GridSnapshot` gains `pub history_rows: u32`; `vt-wasm/tests/exit_encoding.rs` adds `history_rows: 0,`.

`integrity.rs`: after the `OpenRowDetached` check:

```rust
        if self.history_exported_rows() > completed.len() {
            return Err(IntegrityError::ExportPrefixPastRows {
                exported: self.history_exported_rows(),
                completed: completed.len(),
            });
        }
```

- [ ] **Step 4: Run the tests**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core && cargo test -p vt-wasm`
Expected: green. `tests/ref.rs` (the 50-case corpus) and `tests/synchronized_output.rs` prove `build_snapshot` on the export API is byte-for-byte what it was.

- [ ] **Step 5: CHANGELOG**

```
The model reports what changed.

- `TerminalCore::generation()` counts mutations; `take_delta()` returns the
  history rows appended, the screen rows written, the exported rows trimmed
  and the rewrap remap since the last call (Ghostty
  `src/terminal/render.zig` `Dirty`; WezTerm line `seqno`). Every
  `ScreenGrid` write marks its row. `export_history_rows` /
  `export_screen_rows` / `export_blocks` / `export_cursor` are the pieces
  `build_snapshot` is made of.
```

- [ ] **Step 6: Verify, rebuild the host wasm (the mirror embeds vt-core), commit**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom react; do (cd ts/$p && npx vitest run); done && npm run bench:feel
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```
Expected: green; `PASS feel gate: zero pixel diff` (the export is still a full rebuild per mutation until Task 7).

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && git commit -m "vt-core: generation, dirty screen rows, take_delta and the row-export API behind build_snapshot" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

### Task 7: Incremental `ExportBuffers`, `sync()`, and the byte-identity property test (§1.3.B, wasm half)

Today `WasmTerminalCore::feed` (`vt-wasm/src/lib.rs:46-51`) and `resize`/`tick`/`set_block_bookmarked` each call `core.snapshot()` + `export.refresh()` (`:94-99`), and `refresh` (`export.rs:52-160`) clears and refills every buffer. After this task `feed`/`tick`/`resize` only mutate the core; `sync()` applies the pending `Delta` to buffers kept between calls and returns the generation the export now reflects.

**Files:**
- Modify: `packages/terminal/crates/vt-wasm/src/export.rs` (state fields, `apply`, `compact`, `refresh` sets the section markers, sliced accessors)
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs` (`sync`, `generation`, dirty accumulation, row events, `feed`/`tick`/`resize`/`set_block_bookmarked` no longer export)
- Modify: `packages/terminal/crates/vt-wasm/Cargo.toml` (`[dev-dependencies] proptest = "1"`)
- Create: `packages/terminal/crates/vt-wasm/tests/incremental_export.rs`
- Modify: `packages/terminal/crates/vt-wasm/tests/export_layout.rs` (`refresh_clears_previous_buffers` keeps passing; add `apply_matches_refresh_for_a_partial_delta`)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: Task 6's `TerminalCore::{generation, take_delta, history_rows, export_history_rows, export_screen_rows, export_blocks, export_cursor, alt_snapshot, line_editor_state, first_stable_row}`, `GridSnapshot.history_rows`.
- Produces (Rust, `vt_wasm`):
  ```rust
  impl ExportBuffers {
      pub fn refresh(&mut self, snapshot: &GridSnapshot) -> Result<(), ExportError>              // full rebuild (unchanged contract)
      pub fn apply(&mut self, core: &TerminalCore, delta: &Delta) -> Result<(), ExportError>     // Full → refresh(core.snapshot()); Partial → incremental
      pub fn compact(&mut self)                                                                  // drop the dead prefix, rebase offsets
      pub fn dead_rows(&self) -> usize
      pub fn history_rows(&self) -> usize
      // rows()/row_indents()/run_ranges() return the live slice (dead prefix skipped); content()/style_pairs() return the whole buffer
  }
  pub const COMPACTION_DIVISOR: usize = 4;   // compact when dead rows > live/4 or dead bytes > live/4
  ```
- Produces (wasm-bindgen `WasmTerminalCore`): `sync() -> Result<u32, JsError>` (`number` in TS; the generation the export reflects), `generation() -> u32` (the core's, truncated), `history_rows() -> u32`, `dirty_full() -> bool`, `dirty_rows_ptr() -> *const u32`, `dirty_rows_len() -> usize` (stable rows dirtied since the last `ack_dirty`), `ack_dirty()`, `row_events_trimmed() -> u32`, `remap_ptr() -> *const u32`, `remap_len() -> usize` (pairs of `u32`: old stable row, new stable row), `clear_row_events()`. `feed`, `tick`, `resize`, `set_block_bookmarked` keep their signatures and no longer export. `pub const DIRTY_ROWS_CAP: usize = 4096` (past it `dirty_full` is set and the list cleared).

- [ ] **Step 1: Write the failing property test**

`crates/vt-wasm/Cargo.toml`: add

```toml
[dev-dependencies]
proptest = "1"
```

`crates/vt-wasm/tests/incremental_export.rs`:

```rust
use std::path::PathBuf;

use proptest::prelude::*;
use vt_core::{Limits, TerminalCore};
use vt_wasm::ExportBuffers;

fn full_export(core: &TerminalCore) -> ExportBuffers {
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&core.snapshot().unwrap()).unwrap();
    buffers
}

fn projected_rows(buffers: &ExportBuffers) -> Vec<(Vec<u8>, u16, Vec<u32>)> {
    let rows = buffers.rows();
    let indents = buffers.row_indents();
    let runs = buffers.run_ranges();
    let pairs = buffers.style_pairs();
    let content = buffers.content();
    (0..rows.len() / 2)
        .map(|row| {
            let (start, end) = (rows[row * 2] as usize, rows[row * 2 + 1] as usize);
            let (pair_start, pair_end) = (runs[row * 2] as usize, runs[row * 2 + 1] as usize);
            (
                content[start..end].to_vec(),
                indents[row],
                pairs[pair_start * 3..pair_end * 3].to_vec(),
            )
        })
        .collect()
}

fn assert_projection_equal(incremental: &ExportBuffers, full: &ExportBuffers) {
    assert_eq!(projected_rows(incremental), projected_rows(full));
    assert_eq!(incremental.blocks(), full.blocks());
    assert_eq!(incremental.block_text(), full.block_text());
    assert_eq!(incremental.cursor_row(), full.cursor_row());
    assert_eq!(incremental.cursor_col(), full.cursor_col());
    assert_eq!(incremental.cursor_visible(), full.cursor_visible());
    assert_eq!(incremental.line_editor_state(), full.line_editor_state());
    assert_eq!(incremental.first_stable_row(), full.first_stable_row());
    assert_eq!(incremental.alt_active(), full.alt_active());
    assert_eq!(incremental.alt_content(), full.alt_content());
    assert_eq!(incremental.alt_row_ranges(), full.alt_row_ranges());
    assert_eq!(incremental.alt_run_ranges(), full.alt_run_ranges());
    assert_eq!(incremental.alt_style_pairs(), full.alt_style_pairs());
}

fn assert_bytes_equal(incremental: &ExportBuffers, full: &ExportBuffers) {
    assert_eq!(incremental.content(), full.content());
    assert_eq!(incremental.rows(), full.rows());
    assert_eq!(incremental.row_indents(), full.row_indents());
    assert_eq!(incremental.run_ranges(), full.run_ranges());
    assert_eq!(incremental.style_pairs(), full.style_pairs());
    assert_projection_equal(incremental, full);
}

#[derive(Clone, Debug)]
enum Op {
    Bytes(Vec<u8>),
    Resize(usize, usize),
}

fn op() -> impl Strategy<Value = Op> {
    prop_oneof![
        8 => proptest::collection::vec(any::<u8>(), 1..64).prop_map(Op::Bytes),
        6 => "[a-z ]{1,40}(\r\n)?".prop_map(|text| Op::Bytes(text.into_bytes())),
        3 => (1u16..=6, 1u16..=40).prop_map(|(n, m)| Op::Bytes(format!("\x1b[{n};{m}H").into_bytes())),
        2 => (0u8..=2).prop_map(|mode| Op::Bytes(format!("\x1b[{mode}J").into_bytes())),
        2 => (0u8..=2).prop_map(|mode| Op::Bytes(format!("\x1b[{mode}K").into_bytes())),
        3 => (30u8..=37).prop_map(|colour| Op::Bytes(format!("\x1b[{colour}mst\x1b[0m").into_bytes())),
        1 => Just(Op::Bytes(b"\x1b]133;A\x07".to_vec())),
        1 => Just(Op::Bytes(b"\x1b]133;C\x07".to_vec())),
        1 => Just(Op::Bytes(b"\x1b]133;D;0\x07".to_vec())),
        1 => Just(Op::Bytes(b"\x1b]7000;v=1;boundary=0\x07".to_vec())),
        1 => Just(Op::Bytes(b"\x1b[?1049h".to_vec())),
        1 => Just(Op::Bytes(b"\x1b[?1049l".to_vec())),
        2 => (10usize..=60, 2usize..=8).prop_map(|(cols, rows)| Op::Resize(cols, rows)),
    ]
}

fn run(ops: &[Op], limits: Limits, syncs_every: usize) {
    let mut core = TerminalCore::with_limits(40, limits).unwrap();
    core.resize(40, 4);
    let mut incremental = ExportBuffers::default();
    incremental.apply(&core, &core.take_delta()).unwrap();
    for (index, op) in ops.iter().enumerate() {
        match op {
            Op::Bytes(bytes) => core.feed(bytes),
            Op::Resize(cols, rows) => core.resize(*cols, *rows),
        }
        if index % syncs_every == 0 {
            incremental.apply(&core, &core.take_delta()).unwrap();
            assert_projection_equal(&incremental, &full_export(&core));
        }
    }
    incremental.apply(&core, &core.take_delta()).unwrap();
    let full = full_export(&core);
    assert_projection_equal(&incremental, &full);
    incremental.compact();
    assert_bytes_equal(&incremental, &full);
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(128))]

    #[test]
    fn incremental_export_equals_full_rebuild(
        ops in proptest::collection::vec(op(), 1..120),
        rows_cap in 5usize..40,
        bytes_cap in prop_oneof![Just(usize::MAX), Just(600usize), Just(4_096usize)],
        syncs_every in 1usize..5,
    ) {
        run(&ops, Limits { rows: rows_cap, bytes: bytes_cap }, syncs_every);
    }
}

#[test]
fn incremental_export_equals_full_rebuild_over_the_ref_corpus() {
    let corpus = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../vt-core/tests/ref");
    for name in ["claude_spinner_10s", "zsh_tab_completion", "vttest_insert"] {
        let recording = std::fs::read(corpus.join(name).join("recording")).expect("recording");
        for chunk in [1usize, 7, 64, 4096] {
            let mut core = TerminalCore::with_limits(120, Limits { rows: 200, bytes: usize::MAX }).unwrap();
            core.resize(120, 40);
            let mut incremental = ExportBuffers::default();
            incremental.apply(&core, &core.take_delta()).unwrap();
            for piece in recording.chunks(chunk) {
                core.feed(piece);
                incremental.apply(&core, &core.take_delta()).unwrap();
                assert_projection_equal(&incremental, &full_export(&core));
            }
            incremental.compact();
            assert_bytes_equal(&incremental, &full_export(&core));
        }
    }
}

#[test]
fn compaction_preserves_offsets() {
    let mut core = TerminalCore::with_limits(20, Limits::rows_only(12)).unwrap();
    core.resize(20, 2);
    let mut incremental = ExportBuffers::default();
    incremental.apply(&core, &core.take_delta()).unwrap();
    for i in 0..40 {
        core.feed(format!("\x1b[3{}mrow {i:02}\x1b[0m tail\r\n", i % 8).as_bytes());
        incremental.apply(&core, &core.take_delta()).unwrap();
        let full = full_export(&core);
        assert_projection_equal(&incremental, &full);
        let live_rows = incremental.rows().len() / 2;
        assert!(incremental.dead_rows() * vt_wasm::COMPACTION_DIVISOR <= live_rows.max(1), "dead prefix is bounded: {} dead, {live_rows} live", incremental.dead_rows());
    }
    incremental.compact();
    assert_eq!(incremental.dead_rows(), 0);
    assert_bytes_equal(&incremental, &full_export(&core));
}
```

Pick three corpus directories that exist (`ls /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/tests/ref`); the three named above do at the time of writing.

Append to `tests/export_layout.rs`:

```rust
#[test]
fn apply_matches_refresh_for_a_partial_delta() {
    let mut core = TerminalCore::new(16, 10).unwrap();
    core.resize(16, 2);
    let mut incremental = ExportBuffers::default();
    incremental.apply(&core, &core.take_delta()).unwrap();
    core.feed(b"first row\r\nsecond\r\n");
    let delta = core.take_delta();
    assert_eq!(delta.kind, vt_core::DeltaKind::Partial);
    incremental.apply(&core, &delta).unwrap();
    let mut full = ExportBuffers::default();
    full.refresh(&core.snapshot().unwrap()).unwrap();
    assert_eq!(incremental.content(), full.content());
    assert_eq!(incremental.rows(), full.rows());
    assert_eq!(incremental.run_ranges(), full.run_ranges());
    assert_eq!(incremental.style_pairs(), full.style_pairs());
    assert_eq!(incremental.blocks(), full.blocks());
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-wasm --test incremental_export --test export_layout`
Expected: compile errors (`apply`, `compact`, `dead_rows`, `COMPACTION_DIVISOR`).

- [ ] **Step 3: Implement the incremental buffers**

`crates/vt-wasm/src/export.rs`:

```rust
use vt_core::{Delta, DeltaKind, ExportedRow, GridSnapshot, TerminalCore};

pub const COMPACTION_DIVISOR: usize = 4;

#[derive(Default)]
pub struct ExportBuffers {
    // the existing fields (export.rs:27-49) and Task 4's `first_stable_row`, plus:
    dead_rows: usize,
    dead_bytes: usize,
    dead_pairs: usize,
    history_rows: usize,
    history_end: usize,
    history_pairs: usize,
}

impl ExportBuffers {
    pub fn refresh(&mut self, snapshot: &GridSnapshot) -> Result<(), ExportError> {
        // the existing body (export.rs:52-159; `first_stable_row` is set there since Task 4), then:
        self.dead_rows = 0;
        self.dead_bytes = 0;
        self.dead_pairs = 0;
        self.history_rows = snapshot.history_rows as usize;
        self.history_end = if self.history_rows == 0 { 0 } else { self.rows[self.history_rows * 2 - 1] as usize };
        self.history_pairs = if self.history_rows == 0 { 0 } else { self.run_ranges[self.history_rows * 2 - 1] as usize };
        Ok(())
    }

    pub fn apply(&mut self, core: &TerminalCore, delta: &Delta) -> Result<(), ExportError> {
        if delta.kind == DeltaKind::Full {
            let snapshot = core.snapshot().map_err(|_| ExportError::OffsetOverflow)?;
            return self.refresh(&snapshot);
        }
        self.drop_front(delta.trimmed_rows);
        self.truncate_screen();
        for row in core.export_history_rows(delta.appended_history.clone()) {
            self.push_row(&row)?;
            self.history_rows += 1;
        }
        self.history_end = self.content.len();
        self.history_pairs = self.style_pairs.len() / 3;
        for row in core.export_screen_rows() {
            self.push_row(&row)?;
        }
        let total_rows = self.rows.len() / 2 - self.dead_rows;
        let live_rows = &self.rows[self.dead_rows * 2..];
        let (records, text) = core
            .export_blocks(total_rows, |row| live_rows[row * 2 + 1] > live_rows[row * 2])
            .map_err(|_| ExportError::OffsetOverflow)?;
        self.write_blocks(&records, &text)?;
        let (cursor_row, cursor_col, cursor_visible) = core.export_cursor();
        self.cursor_row = checked_u32_from_u64(cursor_row as u64)?;
        self.cursor_col = checked_u32_from_u64(cursor_col as u64)?;
        self.cursor_visible = cursor_visible;
        self.line_editor_state = core.line_editor_state().wire();
        self.first_stable_row = core.first_stable_row();
        self.clear_alt();
        self.maybe_compact();
        Ok(())
    }

    fn drop_front(&mut self, trimmed: usize) {
        if trimmed == 0 {
            return;
        }
        let trimmed = trimmed.min(self.history_rows);
        self.dead_rows += trimmed;
        self.history_rows -= trimmed;
        let first_live = self.dead_rows * 2;
        self.dead_bytes = if self.history_rows > 0 { self.rows[first_live] as usize } else { self.history_end };
        self.dead_pairs = if self.history_rows > 0 { self.run_ranges[first_live] as usize } else { self.history_pairs };
    }

    fn truncate_screen(&mut self) {
        let keep_rows = self.dead_rows + self.history_rows;
        self.content.truncate(self.history_end);
        self.rows.truncate(keep_rows * 2);
        self.row_indents.truncate(keep_rows);
        self.run_ranges.truncate(keep_rows * 2);
        self.style_pairs.truncate(self.history_pairs * 3);
    }

    fn push_row(&mut self, row: &ExportedRow) -> Result<(), ExportError> {
        let content_base = checked_u32_from_u64(self.content.len() as u64)?;
        let content_end = checked_u32_from_u64((self.content.len() + row.bytes.len()) as u64)?;
        self.content.extend_from_slice(&row.bytes);
        self.rows.push(content_base);
        self.rows.push(content_end);
        self.row_indents.push(row.indent);
        let pair_start = checked_u32_from_u64((self.style_pairs.len() / 3) as u64)?;
        for &(end, style) in &row.styles {
            self.style_pairs.push(end);
            self.style_pairs.push(style.fg.value());
            self.style_pairs.push(style.bg.value());
        }
        let pair_end = checked_u32_from_u64((self.style_pairs.len() / 3) as u64)?;
        self.run_ranges.push(pair_start);
        self.run_ranges.push(pair_end);
        Ok(())
    }

    fn maybe_compact(&mut self) {
        let live_rows = self.rows.len() / 2 - self.dead_rows;
        let live_bytes = self.content.len() - self.dead_bytes;
        if self.dead_rows * COMPACTION_DIVISOR > live_rows.max(1) || self.dead_bytes * COMPACTION_DIVISOR > live_bytes.max(1) {
            self.compact();
        }
    }

    pub fn compact(&mut self) {
        if self.dead_rows == 0 && self.dead_bytes == 0 {
            return;
        }
        let dead_bytes = self.dead_bytes as u32;
        let dead_pairs = self.dead_pairs as u32;
        self.content.drain(..self.dead_bytes);
        self.rows.drain(..self.dead_rows * 2);
        for offset in &mut self.rows {
            *offset -= dead_bytes;
        }
        self.row_indents.drain(..self.dead_rows);
        self.run_ranges.drain(..self.dead_rows * 2);
        for index in &mut self.run_ranges {
            *index -= dead_pairs;
        }
        self.style_pairs.drain(..self.dead_pairs * 3);
        self.history_end -= self.dead_bytes;
        self.history_pairs -= self.dead_pairs;
        self.dead_rows = 0;
        self.dead_bytes = 0;
        self.dead_pairs = 0;
    }

    pub fn dead_rows(&self) -> usize {
        self.dead_rows
    }

    pub fn history_rows(&self) -> usize {
        self.history_rows
    }

    pub fn first_stable_row(&self) -> u64 {
        self.first_stable_row
    }

    pub fn rows(&self) -> &[u32] {
        &self.rows[self.dead_rows * 2..]
    }

    pub fn row_indents(&self) -> &[u16] {
        &self.row_indents[self.dead_rows..]
    }

    pub fn run_ranges(&self) -> &[u32] {
        &self.run_ranges[self.dead_rows * 2..]
    }
}
```

`write_blocks(&records, &text)` is the existing block-record loop from `refresh` (`export.rs:118-158`) moved into a method that clears `blocks`/`block_text` first; `refresh` calls it too. `clear_alt` resets the nine `alt_*` fields (`export.rs:64-73`). `refresh` itself builds rows through `push_row` from the snapshot's `(rows, row_indents, run_ranges, style_pairs, content)` so both paths share one writer — simplest is to keep `refresh`'s existing direct copy and rely on the property test, which is what the plan requires; either way the test decides.

`crates/vt-wasm/src/lib.rs`:

```rust
pub const DIRTY_ROWS_CAP: usize = 4096;

#[wasm_bindgen]
pub struct WasmTerminalCore {
    core: TerminalCore,
    export: ExportBuffers,
    synced_generation: Option<u64>,
    dirty_rows: Vec<u32>,
    dirty_full: bool,
    row_events_trimmed: u32,
    remap: Vec<u32>,
    // find fields unchanged
}

    #[wasm_bindgen(constructor)]
    pub fn new(columns: usize, rows_limit: usize, bytes_limit: usize) -> Result<WasmTerminalCore, JsError> {
        let core = TerminalCore::with_limits(columns, vt_core::Limits { rows: rows_limit, bytes: bytes_limit })
            .map_err(js_error_from_core)?;
        let mut this = WasmTerminalCore {
            core,
            export: ExportBuffers::default(),
            synced_generation: None,
            dirty_rows: Vec::new(),
            dirty_full: true,
            row_events_trimmed: 0,
            remap: Vec::new(),
            find_sessions: HashMap::new(),
            find_free_ids: Vec::new(),
            find_next_id: 1,
            find_results: Vec::new(),
        };
        this.sync()?;
        Ok(this)
    }

    pub fn feed(&mut self, bytes: &[u8], now_ms: f64) -> Result<(), JsError> {
        self.core.feed_at(bytes, clock(now_ms));
        Ok(())
    }

    pub fn tick(&mut self, now_ms: f64) -> Result<bool, JsError> {
        Ok(self.core.tick(clock(now_ms)))
    }

    pub fn resize(&mut self, columns: usize, rows: usize) -> Result<(), JsError> {
        self.core.resize(columns, rows);
        Ok(())
    }

    pub fn set_block_bookmarked(&mut self, id_lo: u32, id_hi: u32, bookmarked: bool) -> Result<(), JsError> {
        let id = ((id_hi as u64) << 32) | (id_lo as u64);
        self.core.set_block_bookmarked(id, bookmarked);
        Ok(())
    }

    pub fn sync(&mut self) -> Result<u32, JsError> {
        let generation = self.core.generation();
        if self.synced_generation == Some(generation) {
            return Ok(generation as u32);
        }
        let delta = self.core.take_delta();
        self.export.apply(&self.core, &delta)?;
        self.synced_generation = Some(generation);
        let first_stable = self.export.first_stable_row();
        let first_screen = first_stable + self.export.history_rows() as u64;
        match delta.kind {
            vt_core::DeltaKind::Full => {
                self.dirty_full = true;
                self.dirty_rows.clear();
            }
            vt_core::DeltaKind::Partial => {
                for row in delta.appended_history.clone() {
                    self.push_dirty(first_stable + row as u64)?;
                }
                for row in &delta.screen_rows {
                    self.push_dirty(first_screen + *row as u64)?;
                }
            }
        }
        self.row_events_trimmed = self.row_events_trimmed.saturating_add(delta.trimmed_rows as u32);
        if let Some(pairs) = delta.remap {
            self.remap.clear();
            for (old, new) in pairs {
                self.remap.push(checked_u32_from_u64(old)?);
                self.remap.push(checked_u32_from_u64(new)?);
            }
        }
        Ok(generation as u32)
    }

    fn push_dirty(&mut self, stable_row: u64) -> Result<(), JsError> {
        if self.dirty_full {
            return Ok(());
        }
        if self.dirty_rows.len() >= DIRTY_ROWS_CAP {
            self.dirty_full = true;
            self.dirty_rows.clear();
            return Ok(());
        }
        self.dirty_rows.push(checked_u32_from_u64(stable_row)?);
        Ok(())
    }

    pub fn generation(&self) -> u32 {
        self.core.generation() as u32
    }

    pub fn history_rows(&self) -> u32 {
        self.export.history_rows() as u32
    }

    pub fn dirty_full(&self) -> bool {
        self.dirty_full
    }

    pub fn dirty_rows_ptr(&self) -> *const u32 {
        self.dirty_rows.as_ptr()
    }

    pub fn dirty_rows_len(&self) -> usize {
        self.dirty_rows.len()
    }

    pub fn ack_dirty(&mut self) {
        self.dirty_full = false;
        self.dirty_rows.clear();
    }

    pub fn row_events_trimmed(&self) -> u32 {
        self.row_events_trimmed
    }

    pub fn remap_ptr(&self) -> *const u32 {
        self.remap.as_ptr()
    }

    pub fn remap_len(&self) -> usize {
        self.remap.len()
    }

    pub fn clear_row_events(&mut self) {
        self.row_events_trimmed = 0;
        self.remap.clear();
    }
```

The appended history rows are pushed as dirty because the renderer treats "new" and "changed" alike (it has no node for a new row yet). `first_stable_row_lo/hi` (Task 4) keep reading `self.export`. Delete `refresh_after_mutation`.

- [ ] **Step 4: Run the tests**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-wasm && cargo test -p vt-core`
Expected: green; the proptest runs 128 cases. If it finds a divergence, the failing `ops` are printed and saved under `crates/vt-wasm/tests/incremental_export.proptest-regressions` — fix `apply`, never the test.

- [ ] **Step 5: CHANGELOG**

```
The export is incremental.

- `WasmTerminalCore::feed`/`tick`/`resize` no longer rebuild the export;
  `sync()` applies the pending delta (appended history rows, the rewritten
  screen section, trimmed rows as a dead prefix compacted past 25 %) and
  returns the generation it reflects. A rewrap, a resize, the alternate
  screen and a process boundary rebuild in full. A property test pins that
  the incremental buffers equal a full rebuild after any chunking, resize
  and trim. Dirty stable rows accumulate until `ack_dirty`; row events
  (`row_events_trimmed`, `remap`) until `clear_row_events`.
```

- [ ] **Step 6: Verify and commit**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test && npm run build:wasm -- --force`
Expected: green. The TS side is not switched yet (Task 8): `ts/core` still calls `feed` then reads pointers without `sync()`, so **do not run the vitest suites or the feel gate at this commit** — they would read a stale export. Task 8 is the other half of this change and lands next; commit this half on its own so the Rust review is separable.

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates packages/terminal/CHANGELOG.md && git commit -m "vt-wasm: incremental ExportBuffers applied from take_delta; sync() replaces the per-feed rebuild" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: `ts/core` syncs lazily, memoises the snapshot and `decodeBlocks`, and surfaces dirty rows and row events (§1.3.B, TS half)

**Files:**
- Modify: `packages/terminal/ts/core/src/terminal-core.ts:43-59` (fields), `:73-81` (`feed`), `:177-241` (`snapshot`), new `takeDirty`, `onRowEvents`, `dispose` clears the cache
- Modify: `packages/terminal/ts/core/src/blocks.ts:10-12` (memo)
- Modify: `packages/terminal/ts/core/src/types.ts` (`TerminalSnapshot.historyRows`, `DirtyRows`, `RowEvent`, `RowEventListener`)
- Modify: `packages/terminal/ts/core/src/index-browser.ts` (export the new types)
- Modify: `packages/terminal/ts/core/src/terminal-core.test.ts`, `block-contract.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:388-516` (`repaint` acknowledges dirt after painting)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: Task 7's `sync`, `generation`, `history_rows`, `dirty_full`, `dirty_rows_ptr/len`, `ack_dirty`, `row_events_trimmed`, `remap_ptr/len`, `clear_row_events`.
- Produces:
  ```ts
  // types.ts
  TerminalSnapshot.historyRows: number
  export type DirtyRows = Readonly<{ full: boolean; rows: ReadonlySet<number> }>;          // stable rows
  export type RowEvent = Readonly<{ trimmed: number; remap: ReadonlyArray<readonly [number, number]> | null }>;
  export type RowEventListener = (event: RowEvent) => void;
  // TerminalCore
  snapshot(): TerminalSnapshot          // calls inner.sync(); same object while the generation and the wasm buffer are unchanged
  takeDirty(): DirtyRows                // reads and acknowledges the dirt accumulated since the previous call
  onRowEvents(listener: RowEventListener): () => void   // fired from snapshot() when a sync produced trims or a remap, after the cache is updated
  // blocks.ts
  decodeBlocks(snapshot)                // returns the same array for the same snapshot object (WeakMap)
  ```

- [ ] **Step 1: Write the failing tests**

`ts/core/src/terminal-core.test.ts`:

```ts
import { WasmTerminalCore } from "../wasm/vt_core.js";

	it("snapshot is cached per generation", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100, rows: 1 });
		core.feed(new TextEncoder().encode("one\r\n"));
		const first = core.snapshot();
		expect(core.snapshot()).toBe(first);
		expect(decodeBlocks(first)).toBe(decodeBlocks(first));
		core.feed(new TextEncoder().encode("two\r\n"));
		const second = core.snapshot();
		expect(second).not.toBe(first);
		expect(second.generation).not.toBe(first.generation);
		expect(second.historyRows).toBe(2);
		expect(second.rows.length / 2).toBeGreaterThan(second.historyRows);
	});

	it("feed alone does not export", () => {
		const sync = vi.spyOn(WasmTerminalCore.prototype, "sync");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		sync.mockClear();
		core.feed(new TextEncoder().encode("alpha\r\n"));
		core.feed(new TextEncoder().encode("beta\r\n"));
		expect(sync).not.toHaveBeenCalled();
		core.snapshot();
		expect(sync).toHaveBeenCalledTimes(1);
		core.snapshot();
		expect(sync).toHaveBeenCalledTimes(2);
	});

	it("still notifies onChange per parsed feed without exporting", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const generations: number[] = [];
		core.onChange((generation) => generations.push(generation));
		core.feed(new TextEncoder().encode("a"));
		core.feed(new TextEncoder().encode("b"));
		expect(generations).toHaveLength(2);
		expect(generations[0]).not.toBe(generations[1]);
	});

	it("accumulates dirty stable rows until they are taken", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100, rows: 3 });
		core.snapshot();
		expect(core.takeDirty().full).toBe(true);
		core.feed(new TextEncoder().encode("a\r\nb"));
		core.snapshot();
		core.feed(new TextEncoder().encode("\x1b[1;1HX"));
		core.snapshot();
		const dirty = core.takeDirty();
		expect(dirty.full).toBe(false);
		expect([...dirty.rows].sort((x, y) => x - y)).toEqual([0, 1]);
		expect(core.takeDirty()).toEqual({ full: false, rows: new Set() });
	});

	it("emits row events for a trim and a rewrap", () => {
		const core = createTerminalCore({ columns: 20, limits: { rows: 6, bytes: 0xffff_ffff }, rows: 2 });
		const events: RowEvent[] = [];
		core.onRowEvents((event) => events.push(event));
		const encoder = new TextEncoder();
		core.snapshot();
		for (const line of ["1", "2", "3", "4"]) core.feed(encoder.encode(`${line}\r\n`));
		core.snapshot();
		for (const line of ["5", "6", "7"]) core.feed(encoder.encode(`${line}\r\n`));
		core.snapshot();
		expect(events).toEqual([{ trimmed: 1, remap: null }]);
		core.feed(encoder.encode("aaaaaaaaaabbbbbbbbbbcccccccccc\r\n"));
		core.snapshot();
		core.resize(40, 2);
		core.snapshot();
		const remap = events.at(-1)!.remap!;
		expect(remap.length).toBeGreaterThan(0);
		expect(remap.every(([from, to]) => to <= from)).toBe(true);
		expect(core.snapshot().firstStableRow).toBeGreaterThan(0);
	});
```

Import `decodeBlocks` and `type RowEvent` from `./index`. `block-contract.test.ts`: add

```ts
	it("decodes the same snapshot once", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		core.feed(new TextEncoder().encode("alpha\nbravo"));
		const snapshot = core.snapshot();
		expect(decodeBlocks(snapshot)).toBe(decodeBlocks(snapshot));
		expect(decodeBlocks({ blocks: snapshot.blocks, blockText: snapshot.blockText })).toEqual(decodeBlocks(snapshot));
	});
```

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && cd ts/core && npx vitest run`
Expected: the new tests fail (`takeDirty`/`onRowEvents` missing, `historyRows` undefined, snapshots not cached); the existing ones break too because `snapshot()` does not call `sync()` yet — that is the state Task 7 left and this task fixes.

- [ ] **Step 3: Implement**

`types.ts`: add `historyRows: number` to `TerminalSnapshot`, and:

```ts
export type DirtyRows = Readonly<{ full: boolean; rows: ReadonlySet<number> }>;

export type RowEvent = Readonly<{ trimmed: number; remap: ReadonlyArray<readonly [number, number]> | null }>;

export type RowEventListener = (event: RowEvent) => void;
```

`terminal-core.ts`:

```ts
	private cached: { generation: number; buffer: ArrayBufferLike; snapshot: TerminalSnapshot } | null = null;
	private readonly rowEventListeners = new Set<RowEventListener>();

	snapshot(): TerminalSnapshot {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		const generation = this.inner.sync();
		const memory = getMemory();
		const cached = this.cached;
		if (cached && cached.generation === generation && cached.buffer === memory.buffer) {
			return cached.snapshot;
		}
		const snapshot = this.buildSnapshot(memory, generation);
		this.cached = { generation, buffer: memory.buffer, snapshot };
		this.emitRowEvents();
		return snapshot;
	}

	private buildSnapshot(memory: WebAssembly.Memory, generation: number): TerminalSnapshot {
		// the existing body of snapshot() from `const contentPtr` to the returned object, with
		//   generation,
		//   firstStableRow: this.inner.first_stable_row_hi() * 2 ** 32 + this.inner.first_stable_row_lo(),
		//   historyRows: this.inner.history_rows(),
	}

	private emitRowEvents(): void {
		const trimmed = this.inner.row_events_trimmed();
		const remapLen = this.inner.remap_len();
		if (trimmed === 0 && remapLen === 0) return;
		const words = u32View(getMemory(), this.inner.remap_ptr(), remapLen);
		const remap: Array<readonly [number, number]> = [];
		for (let index = 0; index + 1 < words.length; index += 2) remap.push([words[index]!, words[index + 1]!]);
		this.inner.clear_row_events();
		const event: RowEvent = { trimmed, remap: remap.length > 0 ? remap : null };
		for (const listener of [...this.rowEventListeners]) listener(event);
	}

	takeDirty(): DirtyRows {
		if (this.disposed) {
			return { full: false, rows: new Set() };
		}
		this.inner.sync();
		const full = this.inner.dirty_full();
		const rows = new Set<number>(u32View(getMemory(), this.inner.dirty_rows_ptr(), this.inner.dirty_rows_len()));
		this.inner.ack_dirty();
		return { full, rows: full ? new Set() : rows };
	}

	onRowEvents(listener: RowEventListener): () => void {
		this.rowEventListeners.add(listener);
		return () => {
			this.rowEventListeners.delete(listener);
		};
	}
```

`dispose()` sets `this.cached = null` and clears `rowEventListeners`. `feed`, `enqueue`, `drain`, `tick`, `resize` are unchanged (Plan A's generation rule still holds because `generation()` is the core's counter now).

`blocks.ts`:

```ts
const decoded = new WeakMap<object, BlockView[]>();

export function decodeBlocks(snapshot: Pick<TerminalSnapshot, "blocks" | "blockText">): BlockView[] {
	const hit = decoded.get(snapshot);
	if (hit) return hit;
	const views = decodeBlockRecords(snapshot);
	decoded.set(snapshot, views);
	return views;
}
```

(`decodeBlockRecords` is the existing function body.) Export `DirtyRows`, `RowEvent`, `RowEventListener` from `index-browser.ts`.

`dom-block-renderer.ts` `repaint`: after `this.notifyPainted()` in both the alt branch and the main branch, call `core.takeDirty()` (the value is used from Task 10 on; taking it now keeps the wasm dirty list from growing between paints).

- [ ] **Step 4: Run the TS suites, the gates and the harness rows this task moves**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in core renderer-dom react; do (cd ts/$p && npx vitest run); done && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate && npm run bench:agent -- --fixture claude-long-50k
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
```
Expected: green; `PASS feel gate: zero pixel diff`; `PASS agent-session gate`. In the `claude-long-50k` line, `feedCost` at 50k drops to the 1k figure (feed no longer exports) and `feedSyncCost` at 50k is within 20 % of its 1k figure — that is the §1.4 "feed cost flat" row; write both numbers down for Task 12. If `feedSyncCost` at 50k is not flat, find what still walks the history (`export_blocks` is O(blocks), `trimTrailingBlankRows` is O(1) per paint, `renderableRowCount` in the harness is not part of the timed region) before continuing.

- [ ] **Step 5: CHANGELOG and commit**

```
- `TerminalCore.feed` only parses; `snapshot()` syncs the export lazily and
  returns the same object while the generation is unchanged, so a paint, a
  mouse move and a find share one export per frame; `decodeBlocks` is memoised
  per snapshot. `takeDirty()` and `onRowEvents()` expose the delta to the renderer.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal && git commit -m "terminal-core: lazy sync, snapshot and decodeBlocks memoised per generation, dirty rows and row events" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Scroll position anchored to a stable row (§1.3.D)

Today `repaint` (`dom-block-renderer.ts:448-449`) computes the window from the pre-paint `scrollTop` and restores that pixel afterwards (`:507-511`). When a trim removes rows above the viewport the same pixel now shows text `trimmed × rowHeight` further down — the jump this task removes.

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/viewport.ts` (`rowTop`, `anchorAt`, `RowAnchor`)
- Modify: `packages/terminal/ts/renderer-dom/src/viewport.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:111-115` (scroll listener), `:203-210` (`scrollToLatest`), `:446-461` and `:507-511` (`repaint`), `:534-550` (`updateStickiness`), `mount`/`dispose` (row-event subscription), new `scrollAnchor()`, `captureAnchor()`, `anchoredScrollTop()`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/index.ts` (`type ScrollAnchor`)
- Modify: `packages/terminal/bench/agent-session/scroll-gate.mjs` (the trim phase)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: Task 8's `TerminalSnapshot.firstStableRow`, `TerminalCore.onRowEvents`; `computeWindow`'s `blockHeight`/`headerHeightFor`/padding split (`viewport.ts:33-45,53-57`).
- Produces:
  ```ts
  // viewport.ts
  export type RowAnchor = Readonly<{ flatRow: number; offsetPx: number }>;
  export function rowTop(blocks: readonly BlockView[], flatRow: number, rowHeight: number, headerHeight: number, paddingY: number): number | null;
  export function anchorAt(blocks: readonly BlockView[], scrollTop: number, rowHeight: number, headerHeight: number, paddingY: number): RowAnchor | null;
  // dom-block-renderer.ts
  export type ScrollAnchor = Readonly<{ stableRow: number; offsetPx: number }>;
  DomBlockRenderer.scrollAnchor(): ScrollAnchor | null     // null while stuck to the bottom
  ```
  Invariant: `anchorAt(blocks, rowTop(blocks, a.flatRow, …) + a.offsetPx, …)` equals `a`, so a paint with unchanged geometry sets the same `scrollTop` it read — the feel gate depends on it.

- [ ] **Step 1: Write the failing tests**

`viewport.test.ts` (use the file's existing `block()` helper for `BlockView`s):

```ts
describe("rowTop and anchorAt", () => {
	const rowHeight = 10;
	const headerHeight = 25;
	const paddingY = 21;
	const paddingTop = paddingY * (1.1 / 2.1);
	const blocks = [block("a", 0, 5, "osc133"), block("b", 5, 100, "synthetic")];

	it("places a row below its block's header and top padding", () => {
		expect(rowTop(blocks, 0, rowHeight, headerHeight, paddingY)).toBe(headerHeight + paddingTop);
		expect(rowTop(blocks, 3, rowHeight, headerHeight, paddingY)).toBe(headerHeight + paddingTop + 30);
		const blockAHeight = 5 * rowHeight + headerHeight + paddingY;
		expect(rowTop(blocks, 5, rowHeight, headerHeight, paddingY)).toBe(blockAHeight + paddingTop);
		expect(rowTop(blocks, 105, rowHeight, headerHeight, paddingY)).toBeNull();
	});

	it("anchors to the row under the top edge with its pixel offset", () => {
		const top = rowTop(blocks, 7, rowHeight, headerHeight, paddingY)!;
		const anchor = anchorAt(blocks, top + 4, rowHeight, headerHeight, paddingY)!;
		expect(anchor.flatRow).toBe(7);
		expect(anchor.offsetPx).toBeCloseTo(4, 9);
	});

	it("anchors to a block's first row while the edge is inside its header", () => {
		const anchor = anchorAt(blocks, 3, rowHeight, headerHeight, paddingY)!;
		expect(anchor.flatRow).toBe(0);
		expect(anchor.offsetPx).toBeLessThan(0);
	});

	it("round-trips through rowTop for every row", () => {
		for (let row = 0; row < 105; row += 1) {
			for (const offset of [0, 3, 9.5]) {
				const top = rowTop(blocks, row, rowHeight, headerHeight, paddingY)!;
				const anchor = anchorAt(blocks, top + offset, rowHeight, headerHeight, paddingY)!;
				expect(anchor.flatRow).toBe(row);
				expect(anchor.offsetPx).toBeCloseTo(offset, 9);
			}
		}
	});
});
```

If the file's `block()` helper has no `source` parameter, extend it (`source: BlockSource = "synthetic"`).

`dom-block-renderer.test.ts` (the `mountWith`, `feed`, `flushRepaint`, `font` helpers exist at the top of the file):

```ts
function scrollable(): HTMLElement {
	const container = document.createElement("div");
	Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
	Object.defineProperty(container, "scrollHeight", { value: 100_000, configurable: true });
	Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
	return container;
}

describe("scroll anchor", () => {
	it("keeps the text under the top edge when rows are trimmed above the viewport", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 20, limits: { rows: 150, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 100; i += 1) feed(core, `line ${i}\r\n`);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		const rowHeight = renderer.measure().cellHeight;
		expect(renderer.scrollAnchor()).toBeNull();
		container.scrollTop = Math.round(rowHeight * 80);
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const anchor = renderer.scrollAnchor()!;
		expect(anchor.stableRow).toBeGreaterThan(70);
		expect(container.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)?.textContent).toBe(`line ${anchor.stableRow}`);
		const before = container.scrollTop;
		for (let i = 100; i < 200; i += 1) feed(core, `line ${i}\r\n`);
		await flushRepaint();
		const trimmed = core.snapshot().firstStableRow;
		expect(trimmed).toBeGreaterThan(0);
		expect(renderer.scrollAnchor()).toEqual(anchor);
		expect(container.scrollTop).toBeCloseTo(before - trimmed * rowHeight, 3);
		expect(container.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)?.textContent).toBe(`line ${anchor.stableRow}`);
		renderer.dispose();
	});

	it("keeps it across a rewrap", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 20, limits: { rows: 1000, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 100; i += 1) feed(core, `${"x".repeat(25)} ${i}\r\n`);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		const rowHeight = renderer.measure().cellHeight;
		container.scrollTop = Math.round(rowHeight * 60);
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const anchor = renderer.scrollAnchor()!;
		const textBefore = container.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)!.textContent!.trim();
		core.resize(40, 2);
		await flushRepaint();
		const after = renderer.scrollAnchor()!;
		expect(after.stableRow).toBeLessThanOrEqual(anchor.stableRow);
		const textAfter = container.querySelector(`[data-terminal-row="${after.stableRow}"]`)!.textContent!;
		expect(textAfter).toContain(textBefore);
		renderer.dispose();
	});

	it("clamps a trimmed anchor to the first row", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 20, limits: { rows: 60, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 50; i += 1) feed(core, `line ${i}\r\n`);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		container.scrollTop = Math.round(renderer.measure().cellHeight * 5);
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const anchor = renderer.scrollAnchor()!;
		for (let i = 50; i < 200; i += 1) feed(core, `line ${i}\r\n`);
		await flushRepaint();
		const first = core.snapshot().firstStableRow;
		expect(first).toBeGreaterThan(anchor.stableRow);
		expect(renderer.scrollAnchor()!.stableRow).toBe(first);
		renderer.dispose();
	});
});
```

Traces: history rows are numbered from 0 and hold `line N`, so stable row N reads `line N` for every history row; a 150-row cap with a 2-row screen keeps 149 history rows, so 200 lines trim 50 — below the anchor near row 78, above the anchor near row 4 in the clamp test (a 60-row cap trims 140 there); in the rewrap test each 28-character line wraps into two 20-column rows and the widening to 40 joins them, so the anchor's row moves to a smaller stable id and the joined row contains the piece's text.

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run viewport.test.ts dom-block-renderer.test.ts -t "anchor"`
Expected: FAIL (`rowTop`/`anchorAt`/`scrollAnchor` missing).

- [ ] **Step 3: Implement**

`viewport.ts`:

```ts
export type RowAnchor = Readonly<{ flatRow: number; offsetPx: number }>;

function paddingTopOf(paddingY: number): number {
	return paddingY * (BLOCK_PADDING_TOP_LINES / (BLOCK_PADDING_TOP_LINES + BLOCK_PADDING_BOTTOM_LINES));
}

export function rowTop(blocks: readonly BlockView[], flatRow: number, rowHeight: number, headerHeight: number, paddingY: number): number | null {
	let accumulated = 0;
	for (const block of blocks) {
		if (flatRow >= block.firstRow && flatRow < block.firstRow + block.rowCount) {
			return accumulated + headerHeightFor(block, headerHeight) + paddingTopOf(paddingY) + (flatRow - block.firstRow) * rowHeight;
		}
		accumulated += blockHeight(block, rowHeight, headerHeight, paddingY);
	}
	return null;
}

export function anchorAt(blocks: readonly BlockView[], scrollTop: number, rowHeight: number, headerHeight: number, paddingY: number): RowAnchor | null {
	let accumulated = 0;
	for (const block of blocks) {
		const rowsTop = accumulated + headerHeightFor(block, headerHeight) + paddingTopOf(paddingY);
		const rowsBottom = rowsTop + block.rowCount * rowHeight;
		if (block.rowCount > 0 && scrollTop < rowsBottom) {
			const index = Math.min(Math.max(0, Math.floor((scrollTop - rowsTop) / rowHeight)), block.rowCount - 1);
			return { flatRow: block.firstRow + index, offsetPx: scrollTop - (rowsTop + index * rowHeight) };
		}
		accumulated += blockHeight(block, rowHeight, headerHeight, paddingY);
	}
	return null;
}
```

`computeWindow` already computes the same `paddingTop`; replace its inline expression with `paddingTopOf(paddingY)` so the two cannot drift.

`dom-block-renderer.ts`:

```ts
export type ScrollAnchor = Readonly<{ stableRow: number; offsetPx: number }>;

	private anchor: ScrollAnchor | null = null;
	private paintedFirstStableRow = 0;
	private rowEventsUnsubscribe: (() => void) | null = null;

	// mount():
		this.scrollUnsubscribe = listenScroll(container, () => {
			this.updateStickiness();
			if (!this.stickToBottom) this.captureAnchor();
			this.scheduleRepaint();
		});
		this.rowEventsUnsubscribe = core.onRowEvents((event) => this.remapAnchor(event.remap));

	scrollAnchor(): ScrollAnchor | null {
		return this.stickToBottom ? null : this.anchor;
	}

	private layout(): { rowHeight: number; headerHeight: number; paddingY: number } {
		const { cellHeight } = this.measure();
		const rowHeight = cellHeight > 0 ? cellHeight : this.font.lineHeight * this.font.sizePx;
		return { rowHeight, headerHeight: rowHeight * (2 + BLOCK_COMMAND_GAP_LINES), paddingY: blockPaddingY(rowHeight) + 1 };
	}

	private captureAnchor(): void {
		const container = this.container;
		if (!container) return;
		const { rowHeight, headerHeight, paddingY } = this.layout();
		const anchor = anchorAt(this.filteredBlocks, container.scrollTop, rowHeight, headerHeight, paddingY);
		this.anchor = anchor ? { stableRow: this.paintedFirstStableRow + anchor.flatRow, offsetPx: anchor.offsetPx } : null;
	}

	private remapAnchor(remap: ReadonlyArray<readonly [number, number]> | null): void {
		if (!remap || !this.anchor) return;
		let low = 0;
		let high = remap.length - 1;
		while (low <= high) {
			const mid = (low + high) >> 1;
			const [from, to] = remap[mid]!;
			if (from === this.anchor.stableRow) {
				this.anchor = { stableRow: to, offsetPx: this.anchor.offsetPx };
				return;
			}
			if (from < this.anchor.stableRow) low = mid + 1;
			else high = mid - 1;
		}
	}

	private anchoredScrollTop(firstStableRow: number, fallback: number): number {
		const anchor = this.anchor;
		if (!anchor) return fallback;
		const { rowHeight, headerHeight, paddingY } = this.layout();
		const flat = Math.max(0, anchor.stableRow - firstStableRow);
		if (flat === 0 && anchor.stableRow < firstStableRow) this.anchor = { stableRow: firstStableRow, offsetPx: anchor.offsetPx };
		const top = rowTop(this.filteredBlocks, flat, rowHeight, headerHeight, paddingY);
		return top === null ? fallback : Math.max(0, top + anchor.offsetPx);
	}
```

In `repaint`, after `this.filteredBlocks` is computed and before `computeWindow`:

```ts
		this.paintedFirstStableRow = snapshot.firstStableRow;
		const { rowHeight, headerHeight, paddingY } = this.layout();
		const previousScrollTop = container.scrollTop;
		const scrollTop = this.stickToBottom ? Number.MAX_SAFE_INTEGER : this.anchoredScrollTop(snapshot.firstStableRow, previousScrollTop);
		const windowResult = computeWindow({ blocks: this.filteredBlocks, scrollTop, viewportHeight, rowHeight, headerHeight, overscanRows: OVERSCAN_ROWS, blockPaddingY: paddingY });
```

and the block at `:507-511` becomes:

```ts
		if (this.stickToBottom) {
			this.applyStickiness();
		} else if (Math.abs(container.scrollTop - scrollTop) > 0.5) {
			container.scrollTop = scrollTop;
		}
```

`updateStickiness`: when `this.stickToBottom` becomes `true`, set `this.anchor = null`. `scrollToLatest`: `this.anchor = null`. `dispose`: unsubscribe row events, `this.anchor = null`. The `cellMetrics()` and `measure()` calls that `repaint` already makes are unchanged; `headerHeight`/`paddingY` values are exactly the ones `repaint` passed to `computeWindow` before (`:457,459`).

- [ ] **Step 4: Run the suites**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in core renderer-dom react; do (cd ts/$p && npx vitest run); done`
Expected: green, including "opens at the tail and reaches earlier rows when scrolled up" (`:251`), which now goes through `anchoredScrollTop` and lands on the same rows.

- [ ] **Step 5: Extend the scroll gate with the trim phase**

In `bench/agent-session/scroll-gate.mjs`, after the existing scroll loop result, open a second page with a cap that forces a trim and assert the top-edge stable row:

```js
	const trimPage = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await trimPage.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=${fixture}&scrollback=55000`);
	await trimPage.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	const trim = await trimPage.evaluate(async () => {
		const session = window.__agentSession;
		await session.feedUntilRows(50000);
		await session.setScrollTop(Math.floor(session.scrollHeight() / 2));
		const before = session.visibleRows()[0];
		const firstBefore = session.core().snapshot().firstStableRow;
		for (let i = 0; i < 40 && session.fed < session.fixture.bytes; i += 1) session.feedNext(256 * 1024);
		await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
		const after = session.visibleRows()[0];
		const firstAfter = session.core().snapshot().firstStableRow;
		return { before, after, firstBefore, firstAfter };
	});
	await trimPage.close();
	if (trim.firstAfter <= trim.firstBefore) throw new Error(`no trim happened (first stable row ${trim.firstBefore} → ${trim.firstAfter})`);
	if (!trim.before || !trim.after || trim.before.row !== trim.after.row) throw new Error(`top-edge row moved across a trim: ${JSON.stringify(trim.before)} → ${JSON.stringify(trim.after)}`);
	process.stdout.write(`${JSON.stringify({ fixture, trim })}\n`);
```

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent:scroll`
Expected: the trim line prints with `before.row === after.row` and `firstAfter > firstBefore`. The pre-existing 3-row coverage gap (`TERMINAL.md`/spec table: 60,134/60,137) still makes the first phase exit non-zero; that is Plan A's known residue, not this task's — report it, do not fix it here.

- [ ] **Step 6: Feel gate, CHANGELOG, commit**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate`
Expected: `PASS feel gate: zero pixel diff` — the anchor reproduces the previous `scrollTop` exactly when geometry is unchanged (the round-trip test in Step 1).

```
Scrolling stays put when scrollback is trimmed or rewrapped.

- While not stuck to the bottom, `DomBlockRenderer` anchors the viewport to
  the stable row under its top edge plus a pixel offset and recomputes
  `scrollTop` from it after every paint (`scrollAnchor()`), following a rewrap
  through the remap row event. A trimmed anchor clamps to the first row.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal && git commit -m "renderer-dom: viewport anchored to a stable row across trims and rewraps" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Row-element pool, dirty-row patching and a moved cursor element (§1.3.E, rows)

References: `xterm.js/src/browser/renderer/dom/DomRenderer.ts:336-351` (`_refreshRowElements`: row elements created once and kept), `:527-563` (`renderRows(start, end)` refills only the rows in the dirty range), `:488-491` (`handleCursorMove` repaints the cursor rows only); `ghostty/src/terminal/render.zig:228-252` (per-row `dirty` and `applied_styles` in the render state).

Today `populateBlock` (`block-body.ts:19-44`) builds a fresh fragment with a new header, new row nodes and a new cursor element for every visible block on every paint, and `repaint` (`dom-block-renderer.ts:501-506`) empties and drops the element of every block that left the window.

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/element-pool.ts`, `element-pool.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/block-body.ts` (whole file)
- Modify: `packages/terminal/ts/renderer-dom/src/cursor.ts` (`placeCursor`)
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` (`mount`, `repaint`, `ensureBlockElement`, `setFont`, `dispose`)
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: Task 8's `TerminalCore.takeDirty(): DirtyRows`, `TerminalSnapshot.historyRows`, `generation`; Task 5's `firstStableRow` labels.
- Produces:
  ```ts
  // element-pool.ts
  export class ElementPool {
      take(id: string): HTMLElement | undefined;                       // removes and returns
      put(id: string, element: HTMLElement, capacity: number): void;   // most-recent last; evicts the oldest past capacity, emptying its children
      clear(): void;
      get size(): number;
  }
  // block-body.ts
  export type BlockBodyInput = Readonly<{
      block: BlockView; snapshot: RowSource; rowWindow: RowWindow | null; rowHeight: number; cellWidth: number;
      cursor: CursorPlacement | null; cursorElement: HTMLElement; decoder: TextDecoder;
      firstStableRow: number; generation: number;
      rowIsFresh: (stableRow: number, node: HTMLElement) => boolean;
  }>;
  export function populateBlock(section: HTMLElement, input: BlockBodyInput): { cursorPlaced: boolean };
  export const ROW_GENERATION_ATTR = "data-terminal-row-gen";
  // cursor.ts
  export function placeCursor(row: HTMLElement, cursor: HTMLElement, column: number, cellWidth: number): void;   // updates width/transform, appends (moves) the element when it is not already in `row`
  ```
  Row reuse rule (the renderer's `rowIsFresh`): a node is reused iff `Number(node.getAttribute(ROW_GENERATION_ATTR)) >= fullSince` and (`stableRow < firstStableRow + historyRows` or (the block was not taken from the pool this paint and `!dirty.rows.has(stableRow)`)). `fullSince` is the generation of the last paint whose `takeDirty()` reported `full`, or of the paint after a font change.

- [ ] **Step 1: Write the failing tests**

`element-pool.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { ElementPool } from "./element-pool";

function section(text: string): HTMLElement {
	const element = document.createElement("section");
	element.append(document.createTextNode(text));
	return element;
}

describe("ElementPool", () => {
	it("returns a pooled element once", () => {
		const pool = new ElementPool();
		const a = section("a");
		pool.put("a", a, 3);
		expect(pool.take("a")).toBe(a);
		expect(pool.take("a")).toBeUndefined();
	});
	it("evicts the least recently pooled element past capacity and empties it", () => {
		const pool = new ElementPool();
		const a = section("a");
		const b = section("b");
		pool.put("a", a, 2);
		pool.put("b", b, 2);
		pool.put("a", a, 2);
		pool.put("c", section("c"), 2);
		expect(pool.size).toBe(2);
		expect(pool.take("b")).toBeUndefined();
		expect(b.childNodes.length).toBe(0);
		expect(pool.take("a")).toBe(a);
		expect(a.childNodes.length).toBe(1);
	});
	it("clear empties every element", () => {
		const pool = new ElementPool();
		const a = section("a");
		pool.put("a", a, 2);
		pool.clear();
		expect(pool.size).toBe(0);
		expect(a.childNodes.length).toBe(0);
	});
});
```

`dom-block-renderer.test.ts`:

```ts
describe("row pool", () => {
	const rowNode = (host: HTMLElement, stableRow: number): HTMLElement =>
		host.querySelector<HTMLElement>(`[data-terminal-row="${stableRow}"]`)!;

	it("row elements are reused across paints", async () => {
		const { core, host } = mountWith("one\r\ntwo\r\nthree");
		await flushRepaint();
		const first = rowNode(host, 0);
		const third = rowNode(host, 2);
		feed(core, "!");
		await flushRepaint();
		expect(rowNode(host, 0)).toBe(first);
		expect(rowNode(host, 2)).not.toBe(third);
		expect(rowNode(host, 2).textContent).toBe("three!");
	});

	it("an unchanged row is not rebuilt when another row changed", async () => {
		const { core, host } = mountWith("one\r\ntwo\r\nthree");
		await flushRepaint();
		const observer = new MutationObserver(() => undefined);
		observer.observe(host, { childList: true, subtree: true });
		observer.takeRecords();
		feed(core, "\x1b[2;1HTWO");
		await flushRepaint();
		const added = observer
			.takeRecords()
			.flatMap((record) => [...record.addedNodes])
			.filter((node): node is HTMLElement => node instanceof HTMLElement);
		observer.disconnect();
		expect(added.filter((node) => node.classList.contains("terminal-row")).map((node) => node.dataset.terminalRow)).toEqual(["1"]);
		expect(added.filter((node) => node.classList.contains("terminal-run"))).toHaveLength(1);
		expect(added.every((node) => node.classList.contains("terminal-row") || node.classList.contains("terminal-run") || node.hasAttribute("data-terminal-cursor-cell"))).toBe(true);
		expect(rowNode(host, 1).textContent).toBe("TWO");
	});

	it("moves the cursor element instead of recreating it", async () => {
		const { core, host } = mountWith("one\r\ntwo");
		await flushRepaint();
		const cursor = host.querySelector<HTMLElement>("[data-terminal-cursor-cell]")!;
		expect(cursor.parentElement).toBe(rowNode(host, 1));
		feed(core, "\r\nthree");
		await flushRepaint();
		expect(host.querySelectorAll("[data-terminal-cursor-cell]")).toHaveLength(1);
		expect(host.querySelector("[data-terminal-cursor-cell]")).toBe(cursor);
		expect(cursor.parentElement).toBe(rowNode(host, 2));
	});

	it("a block scrolled out and back in keeps its nodes", async () => {
		const container = document.createElement("div");
		Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
		Object.defineProperty(container, "scrollHeight", { value: 100_000, configurable: true });
		Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
		const core = createTerminalCore({ columns: 16, scrollback: 1000, rows: 2 });
		for (const name of ["a", "b", "c"]) {
			feed(core, "\x1b]133;A\x07\x1b]133;C\x07");
			for (let i = 0; i < 40; i += 1) feed(core, `${name}${i}\r\n`);
			feed(core, "\x1b]133;D;0\x07");
		}
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		await flushRepaint();
		const snapshot = core.snapshot();
		const last = decodeBlocks(snapshot).at(-1)!;
		const stable = snapshot.firstStableRow + last.firstRow + 30;
		const section = container.querySelector<HTMLElement>(`[data-terminal-block-id="${last.id}"]`)!;
		const row = rowNode(container, stable);
		expect(row).toBeTruthy();
		container.scrollTop = 0;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		expect(container.querySelector(`[data-terminal-block-id="${last.id}"]`)).toBeNull();
		container.scrollTop = 99_900;
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		expect(container.querySelector(`[data-terminal-block-id="${last.id}"]`)).toBe(section);
		expect(rowNode(container, stable)).toBe(row);
		renderer.dispose();
	});
});
```

Import `decodeBlocks` from `@operator/terminal-core` at the top of the test file. `mountWith` calls `setFont`, which schedules a rebuild-all repaint, so every test flushes once before capturing node identities. In the last test the screen is 2 rows, so row 30 of the last 40-row block is a history row and the rule reuses it even though the block came back from the pool; the `flushRepaint()` after `setFont` lets the font-change rebuild land before the identities are captured.

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run element-pool.test.ts dom-block-renderer.test.ts -t "row pool|ElementPool"`
Expected: FAIL (module missing; identity assertions fail because every paint rebuilds).

- [ ] **Step 3: Implement**

`element-pool.ts`:

```ts
export class ElementPool {
	private readonly entries = new Map<string, HTMLElement>();

	take(id: string): HTMLElement | undefined {
		const element = this.entries.get(id);
		if (element) this.entries.delete(id);
		return element;
	}

	put(id: string, element: HTMLElement, capacity: number): void {
		this.entries.delete(id);
		this.entries.set(id, element);
		while (this.entries.size > Math.max(0, capacity)) {
			const oldest = this.entries.keys().next().value as string;
			const evicted = this.entries.get(oldest)!;
			this.entries.delete(oldest);
			evicted.replaceChildren();
		}
	}

	clear(): void {
		for (const element of this.entries.values()) element.replaceChildren();
		this.entries.clear();
	}

	get size(): number {
		return this.entries.size;
	}
}
```

`cursor.ts`:

```ts
export function placeCursor(row: HTMLElement, cursor: HTMLElement, column: number, cellWidth: number): void {
	cursor.dataset.column = String(column);
	cursor.style.width = `${cellWidth}px`;
	cursor.style.transform = `translateX(${column * cellWidth}px)`;
	if (cursor.parentElement !== row) row.append(cursor);
}
```

`block-body.ts`:

```ts
import { defaultStrings, type BlockView } from "@operator/terminal-core";
import { renderBlockHeader } from "./block-header.js";
import { placeCursor, type CursorPlacement } from "./cursor.js";
import { buildRowNode, type RowSource } from "./row-builder.js";
import type { RowWindow } from "./viewport.js";

const CLASS_SPACER = "terminal-spacer";
const HEADER_KEY_SEPARATOR = "";
export const ROW_GENERATION_ATTR = "data-terminal-row-gen";

export type BlockBodyInput = Readonly<{
	block: BlockView;
	snapshot: RowSource;
	rowWindow: RowWindow | null;
	rowHeight: number;
	cellWidth: number;
	cursor: CursorPlacement | null;
	cursorElement: HTMLElement;
	decoder: TextDecoder;
	firstStableRow: number;
	generation: number;
	rowIsFresh: (stableRow: number, node: HTMLElement) => boolean;
}>;

type BlockBody = {
	rows: Map<number, HTMLElement>;
	header: HTMLElement | null;
	headerKey: string;
	leading: HTMLElement;
	trailing: HTMLElement;
};

const bodies = new WeakMap<HTMLElement, BlockBody>();

function bodyOf(section: HTMLElement): BlockBody {
	let body = bodies.get(section);
	if (!body) {
		body = { rows: new Map(), header: null, headerKey: "", leading: spacer(), trailing: spacer() };
		bodies.set(section, body);
	}
	return body;
}

function headerKeyOf(block: BlockView): string {
	return [block.state, block.source, block.exitCode, block.durationMs, block.command, block.cwd, block.gitBranch, block.bookmarked].join(HEADER_KEY_SEPARATOR);
}

export function populateBlock(section: HTMLElement, input: BlockBodyInput): { cursorPlaced: boolean } {
	const { block, snapshot, rowWindow, rowHeight, decoder } = input;
	const body = bodyOf(section);
	const key = headerKeyOf(block);
	if (!body.header || body.headerKey !== key) {
		body.header = renderBlockHeader(block, defaultStrings);
		body.headerKey = key;
	}
	const desired: Node[] = [body.header];
	const firstRow = rowWindow ? rowWindow.firstRow : 0;
	const lastRow = rowWindow ? rowWindow.lastRow : block.rowCount - 1;
	if (rowWindow && firstRow > 0) {
		body.leading.style.height = `${firstRow * rowHeight}px`;
		desired.push(body.leading);
	}
	let cursorPlaced = false;
	const keep = new Set<number>();
	for (let rowOffset = firstRow; rowOffset <= lastRow; rowOffset += 1) {
		const snapshotRow = block.firstRow + rowOffset;
		const stableRow = input.firstStableRow + snapshotRow;
		keep.add(stableRow);
		let node = body.rows.get(stableRow);
		if (!node || !input.rowIsFresh(stableRow, node)) {
			node = buildRowNode(snapshot, snapshotRow, stableRow, decoder, input.cellWidth);
			node.setAttribute(ROW_GENERATION_ATTR, String(input.generation));
			body.rows.set(stableRow, node);
		}
		if (input.cursor && input.cursor.row === snapshotRow) {
			placeCursor(node, input.cursorElement, input.cursor.column, input.cellWidth);
			cursorPlaced = true;
		}
		desired.push(node);
	}
	for (const stableRow of [...body.rows.keys()]) {
		if (!keep.has(stableRow)) body.rows.delete(stableRow);
	}
	if (rowWindow) {
		const trailingRows = block.rowCount - 1 - lastRow;
		if (trailingRows > 0) {
			body.trailing.style.height = `${trailingRows * rowHeight}px`;
			desired.push(body.trailing);
		}
	}
	reconcileChildren(section, desired);
	return { cursorPlaced };
}

function reconcileChildren(section: HTMLElement, desired: readonly Node[]): void {
	const wanted = new Set(desired);
	for (const child of [...section.childNodes]) {
		if (!wanted.has(child)) child.remove();
	}
	for (let index = 0; index < desired.length; index += 1) {
		const want = desired[index]!;
		const have = section.childNodes[index] ?? null;
		if (have !== want) section.insertBefore(want, have);
	}
}

function spacer(): HTMLElement {
	const element = document.createElement("div");
	element.className = CLASS_SPACER;
	element.dataset.terminalRowSpacer = "true";
	return element;
}
```

Stale children are removed before the positional pass so a kept node never moves (a move is a removal plus an insertion and would show up as a created node in the `MutationObserver` the tests and the harness count).

`dom-block-renderer.ts`:

```ts
import { ElementPool } from "./element-pool.js";
import { createCursorElement, primaryCursorPlacement, type CursorPlacement } from "./cursor.js";
import { populateBlock, ROW_GENERATION_ATTR } from "./block-body.js";

const POOL_CAPACITY_FACTOR = 3;

	private readonly pool = new ElementPool();
	private cursorElement: HTMLElement | null = null;
	private fullSince = 0;
	private rebuildAll = false;

	// setFont(): this.rebuildAll = true; before invalidateMetrics()

	// repaint(), main branch, after `const cursor = primaryCursorPlacement(snapshot)`:
		const dirty = core.takeDirty();
		if (dirty.full || this.rebuildAll) {
			this.fullSince = snapshot.generation;
			this.rebuildAll = false;
			this.pool.clear();
		}
		const firstScreenStable = snapshot.firstStableRow + snapshot.historyRows;
		const pooledThisPaint = new Set<BlockId>();
		const freshFor = (blockId: BlockId) => (stableRow: number, node: HTMLElement): boolean => {
			const built = Number(node.getAttribute(ROW_GENERATION_ATTR));
			if (!Number.isFinite(built) || built < this.fullSince) return false;
			if (stableRow < firstScreenStable) return true;
			return !pooledThisPaint.has(blockId) && !dirty.rows.has(stableRow);
		};
		const cursorElement = this.cursorElement ?? (this.cursorElement = createCursorElement(0, 0));
		let cursorPlaced = false;
		// in the visible-block loop:
				const { element, pooled } = this.ensureBlockElement(block);
				if (pooled) pooledThisPaint.add(block.id);
				const placed = populateBlock(element, {
					block, snapshot, rowWindow, rowHeight, cellWidth, cursor, cursorElement, decoder: this.decoder,
					firstStableRow: snapshot.firstStableRow, generation: snapshot.generation, rowIsFresh: freshFor(block.id),
				});
				if (placed.cursorPlaced) cursorPlaced = true;
		// after the loop:
		if (!cursorPlaced) cursorElement.remove();
		// blocks leaving the window (replaces `:501-506`):
		const capacity = POOL_CAPACITY_FACTOR * Math.max(1, orderedVisible.length);
		for (const [id, element] of this.blockElements) {
			if (!visibleIds.has(id)) {
				this.pool.put(id, element, capacity);
				this.blockElements.delete(id);
			}
		}

	private ensureBlockElement(block: BlockView): { element: HTMLElement; pooled: boolean } {
		const existing = this.blockElements.get(block.id);
		if (existing) return { element: existing, pooled: false };
		const pooled = this.pool.take(block.id);
		if (pooled) {
			pooled.setAttribute("style", styleVarsString(this.theme, this.font));
			this.blockElements.set(block.id, pooled);
			return { element: pooled, pooled: true };
		}
		const section = document.createElement("section");
		section.className = CLASS_BLOCK;
		section.dataset.terminalBlockId = block.id;
		section.setAttribute("style", styleVarsString(this.theme, this.font));
		this.blockElements.set(block.id, section);
		return { element: section, pooled: false };
	}
```

The `takeDirty()` call this task adds replaces the discard-only call Task 8 put at the end of the main branch (keep the one in the alt branch so dirt does not accumulate while the alt screen is shown; when it closes the next delta is `Full`). `dispose()` calls `this.pool.clear()`, removes `this.cursorElement` and nulls it, resets `fullSince = 0` and `rebuildAll = false`. `applyStyleVars` is unchanged (pooled elements are restyled on `take`). The font-change rebuild exists because a reused row's indent padding is `indent * cellWidth` px (`row-builder.ts:39-41`).

- [ ] **Step 4: Run the suites and the gates**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in core renderer-dom react; do (cd ts/$p && npx vitest run); done && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate`
Expected: green; `PASS feel gate: zero pixel diff` (the same nodes with the same content in the same order); the selection gate passes (the fill is repainted from the model, not from node identity).

- [ ] **Step 5: Harness numbers**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent -- --fixture claude-spinner-10s`
Expected: `spinner.addedNodes` and `spinner.rowNodesAdded` per paint fall well below Plan A's 28.69 nodes/paint (the spinner rewrites a handful of screen rows per frame). Record both for Task 12.

- [ ] **Step 6: CHANGELOG and commit**

```
Rows are patched, not rebuilt.

- `populateBlock` keeps row nodes keyed by stable row on the block element,
  rebuilds only rows the core reports dirty or new, reuses the block header
  until its fields change, and moves one cursor element instead of creating
  one per paint (xterm.js `DomRenderer.ts` row pool and `renderRows`). Block
  elements that leave the window wait in an LRU pool (3× the window) and come
  back with their nodes.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal && git commit -m "renderer-dom: row-element pool, dirty-row patching, single moved cursor element" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Selection fill by diff (§1.3.E, survey §2.3)

Reference: `alacritty/alacritty/src/display/damage.rs:16-30` (`DamageTracker` keeps the previous selection), `:106` (`damage_selection` damages the union of the old and new rectangles); `alacritty_terminal/src/term/mod.rs:450-452` (selection damage is a renderer-side diff, never model state). Today `paintSelectionFill` (`dom-block-renderer.ts:522-528`) clears every previously filled element and refills from scratch on every repaint and every mouse move.

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/selection-view.ts:77-94` (`selectionFills` returns the images without writing)
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:78,522-528` (`filled: Map<HTMLElement, string>`, diffing `paintSelectionFill`)
- Modify: `packages/terminal/ts/renderer-dom/src/terminal-selection.test.ts`, `selection-view` users in `dom-block-renderer.test.ts` if any
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `resolveSelectionView`, `renderedRows` (Task 5 shape), `rowFillSpan`, `runFill`, `fillGradient`.
- Produces: `export function selectionFills(view: SelectionView, rows: readonly RenderedRow[], cellWidth: number): Map<HTMLElement, string>` (row and run elements → the `background-image` value each should carry); `paintSelectionFill` in `selection-view.ts` is removed.

- [ ] **Step 1: Write the failing test**

In `terminal-selection.test.ts` (its `mountWith`, `layoutLive`, `CELL_H` helpers):

```ts
	it("extending the selection by one row repaints one row", async () => {
		const { host, renderer } = mountWith("one\r\ntwo\r\nthree\r\nfour");
		await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
		const restore = layoutLive(host);
		renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(600, CELL_H * 1.5)!);
		expect([...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].filter((row) => row.style.backgroundImage !== "")).toHaveLength(2);
		const observer = new MutationObserver(() => undefined);
		observer.observe(host, { attributes: true, attributeFilter: ["style"], subtree: true });
		observer.takeRecords();
		renderer.selectionUpdate(renderer.pointAt(600, CELL_H * 2.5)!);
		const touched = new Set(
			observer
				.takeRecords()
				.map((record) => record.target)
				.filter((target): target is HTMLElement => target instanceof HTMLElement && target.classList.contains("terminal-row")),
		);
		observer.disconnect();
		restore();
		expect([...touched].map((row) => row.dataset.terminalRow)).toEqual(["2"]);
		renderer.selectionClear();
		expect([...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].filter((row) => row.style.backgroundImage !== "")).toHaveLength(0);
	});
```

Row 1 is a full-width fill both before (the range ends at its last cell) and after (it is a middle row), so only row 2 gains a fill; the first `await` lets the font-change repaint of `mountWith` land first.

- [ ] **Step 2: Run to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run terminal-selection.test.ts -t "extending the selection"`
Expected: FAIL — rows 0, 1 and 2 are all touched because every fill is cleared and rewritten.

- [ ] **Step 3: Implement**

`selection-view.ts`:

```ts
export function selectionFills(view: SelectionView, rows: readonly RenderedRow[], cellWidth: number): Map<HTMLElement, string> {
	const fills = new Map<HTMLElement, string>();
	const colour = "var(--terminal-selection)";
	for (const { box, element } of rows) {
		const span = rowFillSpan(view.range, box, view.order, cellWidth);
		if (!span) continue;
		fills.set(element, fillGradient(span, colour));
		for (const run of element.querySelectorAll<HTMLElement>("[data-terminal-run]")) {
			if (run.style.backgroundColor === "") continue;
			const runSpan = runFill(run.getBoundingClientRect(), box.left, span);
			if (!runSpan) continue;
			fills.set(run, fillGradient(runSpan, colour));
		}
	}
	return fills;
}
```

`dom-block-renderer.ts`:

```ts
	private filled: Map<HTMLElement, string> = new Map();

	private paintSelectionFill(): void {
		const view = this.selectionView();
		const next = view ? selectionFills(view, this.renderedRows(), this.cellMetrics().cellWidth) : new Map<HTMLElement, string>();
		for (const element of this.filled.keys()) {
			if (!next.has(element)) element.style.backgroundImage = "";
		}
		for (const [element, image] of next) {
			if (this.filled.get(element) !== image) element.style.backgroundImage = image;
		}
		this.filled = next;
	}
```

`dispose()` resets `this.filled = new Map()` (replacing `this.filledRows = []`). A row node that Task 10 rebuilt is a new element, so its entry drops out of `filled` and the fresh node is filled from `next` — no stale style survives on a reused node because reuse keeps the element and therefore its map entry.

- [ ] **Step 4: Run the suites and the gates**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in core renderer-dom react; do (cd ts/$p && npx vitest run); done && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate`
Expected: green; `PASS feel gate: zero pixel diff`; the selection gate's `selectedRows` count is unchanged (`bench/selection-gate.mjs:50` counts rows whose style carries `terminal-selection`).

- [ ] **Step 5: Harness number, CHANGELOG, commit**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent -- --fixture claude-spinner-10s`
Expected: `selectionRepaint.rowsRepainted` is 1 (Task 1's probe extends a two-row selection by one row while frames stream). Record it.

```
- The selection fill is diffed against the previous paint: extending a
  selection by one row writes one row's background (Alacritty
  `display/damage.rs` `damage_selection`).
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal && git commit -m "renderer-dom: selection fill diffed against the previous paint" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Part 3 measurement, the "After Plan B" column, acceptance rows, `TERMINAL.md`

This task measures; it does not tune. A missed target is reported in the table and in the commit message, and the decision what to do about it is the user's.

**Files:**
- Modify: `packages/terminal/bench/agent-session/run.mjs` (a `--gate` check for the Plan B rows that are hard requirements: `feedSyncCost` flat, trim phase of the scroll gate reachable from `bench:agent:gate`)
- Modify: `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` (baseline table "After Plan B" column; Part 1.4 rows Plan B owns; "Plan B landed" paragraph under the table)
- Modify: `TERMINAL.md` (§2, new §4.18, §5)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: every row `run.mjs` prints (`feedCost`, `feedSyncCost`, `spinner.{paints,addedNodes,rowNodesAdded}`, `tearing`, `longTask`, `reopen`, `rendererMemoryBytes`, `idlePanes`, `selectionRepaint`), `bench:agent:scroll` (coverage + trim phase), `bench:feel`, the Go reopen report's mirror memory (`vtwasm/agent_session_test.go`, `TestAgentSessionReplayReport`).
- Produces: the gate additions below; the filled table.

- [ ] **Step 1: Add the Plan B gate checks to `run.mjs --gate`**

After the existing long-task checks in `main()`:

```js
			const long = report.fixtures["claude-long-50k"];
			if (long?.feedSyncCost) {
				const at1k = long.feedSyncCost.find((row) => row.rows === 1000)?.medianMs;
				const at50k = long.feedSyncCost.find((row) => row.rows === 50000)?.medianMs;
				if (at1k !== null && at50k !== null && at50k > at1k * 1.2 + 0.2) throw new Error(`feed+sync at 50k rows costs ${at50k.toFixed(2)}ms vs ${at1k.toFixed(2)}ms at 1k (limit 20 % + 0.2 ms)`);
			}
			const spinner = report.fixtures["claude-spinner-10s"]?.spinner;
			if (spinner && spinner.paints > 0) {
				const rowsPerPaint = spinner.rowNodesAdded / spinner.paints;
				const nodesPerPaint = spinner.addedNodes / spinner.paints;
				process.stdout.write(`spinner: ${rowsPerPaint.toFixed(2)} row nodes and ${nodesPerPaint.toFixed(2)} DOM nodes per paint\n`);
			}
```

The `+ 0.2 ms` absolute term keeps sub-millisecond medians from failing on timer jitter; the spec's "within 20 %" is judged on the recorded numbers in Step 3 as well.

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && node --test ./bench/agent-session/session-api.test.mjs && npm run bench:agent:gate`
Expected: `PASS agent-session gate` with the spinner line printed.

- [ ] **Step 2: Measure**

Run each and keep the printed JSON lines:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build && npm run bench:agent
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent:scroll
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent:gate
```

Also run the memory probe at the mirror's new cap: `cd /Users/omaraly/development/AI/Operator/backend && OPERATOR_AGENT_FIXTURE=/Users/omaraly/development/AI/Operator/packages/terminal/bench/agent-session/fixtures/claude-long-50k OPERATOR_AGENT_REPLAY_OUT=/tmp/replay.bin go test ./internal/adapters/runtime/ptyhost/vtwasm/ -run TestAgentSessionReplayReport -v -count=1` and read the mirror wasm memory it reports (the mirror now holds every row up to `mirrorLimits`, so this number rises from the 4,128,768 bytes of the 1,000-row cap; it must stay under 128 MiB).

- [ ] **Step 3: Fill the spec**

In the baseline table add an "After Plan B" column with the measured values for every row (the `—`/"unchanged" rows from Plan A included: `feedCost`, `feedSyncCost`, paints/s and nodes/paint, long task, scroll (coverage, frames > 50 ms, plus the trim phase result), reopen, memory (renderer and mirror), feel gate, torn frames, and the four Part 3 rows Task 1 added). Under the table, after the "Plan A landed" paragraph, add a "Plan B landed <date>" paragraph that states, per Part 1.4 row Plan B owns, pass or miss with the number:

- `feed()` for a 4 KiB chunk at row 50k within 20 % of row 1k (`feedSyncCost`; the spec's 200k target is measured at the fixture's 50k — say so);
- a paint under the spinner creates ≤ 2 DOM nodes per changed row and 0 for unchanged rows (`spinner.addedNodes / spinner.paints` against `spinner.rowNodesAdded / spinner.paints`; a rebuilt row is one `div` plus one `span` per style run, so report the ratio and whether the spinner's rows have more than one run);
- scroll bottom → row 0: every stable row in order, no frame > 50 ms, the top-edge row unchanged across a trim (`bench:agent:scroll` first phase and trim phase; the pre-existing 3-row coverage gap is reported as such);
- renderer core and mirror memory at the fixture's 60k rows (< 128 MiB each);
- Part 3: ten idle panes' main-thread task time vs Task 1's number (target ≤ 25 %), and `selectionRepaint.rowsRepainted` (target 1).

Numbers only from the runs above. A miss is written as a miss.

- [ ] **Step 4: `TERMINAL.md`**

- §2: after the `Snapshot` bullet, add bullets for **Limits** (`Limits { rows, bytes }`, `memory_stats`, both cores take them from the product: `BlockTerminal.tsx` `DEFAULT_LIMITS`, `ptyhost/mirror_limits.go`), **Stable rows** (`trimmed_total`, `stable_row`/`flat_row`, `BlockGrid.origin`, `first_stable_row` in the export, `data-terminal-row` = stable row), and **Delta / incremental export** (`generation`, `take_delta`, `ScreenGrid` dirty bits, `ExportBuffers::apply` with the dead prefix and compaction, `sync()` from `snapshot()`, `takeDirty`/`onRowEvents`). Extend the checklist sentence: adding a snapshot field now also means `ExportedRow`/`push_row` in `export.rs` and `history_rows` if the field is per-section.
- New **§4.18 Viewport jump when scrollback trims** — symptom (scrolled up, the text under the top edge shifted by the trimmed height on every trim at the cap), cause (`repaint` restored a pixel `scrollTop`), now (stable-row anchor, `scrollAnchor()`, remap on rewrap), guards (`viewport.test.ts` "rowTop and anchorAt", `dom-block-renderer.test.ts` "scroll anchor", `bench:agent:scroll` trim phase).
- §5: delete the "Every selection operation takes one fresh `core.snapshot()`…" gap (closed by Task 8) and the "Rewrap walks all scrollback rows…" line's "revisit if scrollback caps grow" clause becomes "caps are 200k since Plan B; lazy rewrap is Plan C 1.3.F".
- §6: unchanged (the recipe already covers every layer).

- [ ] **Step 5: CHANGELOG, commit**

```
- Plan B measured (see the spec's baseline table, "After Plan B"): <one line
  with the feed+sync, nodes-per-paint, ten-pane CPU and selection-repaint numbers>.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/bench/agent-session/run.mjs packages/terminal/CHANGELOG.md docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md TERMINAL.md && git commit -m "bench/docs: Plan B numbers, gate rows, TERMINAL.md §2/§4.18/§5" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app (the last vt-core change was Task 6; every task since Task 3 rebuilt both wasm artifacts and the daemon, and the running pty-hosts still carry the pre-Plan-B mirror until restarted).

---

## Verification summary (run at the end of every task; the task's own steps say which apply)

```bash
# Rust (vt-core, vt-wasm, vt-host)
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test

# Host mirror wasm -> backend asset (committed binary) after any vt-core / vt-host change
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...

# Renderer wasm + TS after any vt-core / vt-wasm / ts change
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal && for p in core renderer-dom react; do (cd ts/$p && npx vitest run); done
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection && npm run bench:feel && npm run bench:agent:gate

# Frontend + daemon
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
# -> restart the daemon AND the app
```

Bench rows per task: Task 8 — `feedCost`/`feedSyncCost` at 1k/5k/50k; Task 9 — `bench:agent:scroll` trim phase; Task 10 — `spinner.addedNodes`, `spinner.rowNodesAdded`; Task 11 — `selectionRepaint`; Task 12 — everything.
