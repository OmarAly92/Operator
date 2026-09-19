# Agent-TUI Plan A — Frame Fidelity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Claude Code pane never shows a half-painted Ink frame, never stalls the main thread on a big tool result, stops re-measuring the font every paint, and the terminal model gains the harness, recordings, reference corpus and integrity checker that every later plan is measured against.

**Architecture:** Synchronized output (DEC 2026) is buffered *in the parser* (`vt-core`), so neither the renderer core nor the pty-host mirror ever holds a partial frame — the port of `vte`'s `Processor::advance_sync`. The renderer's animation-frame loop becomes the single place that drains queued bytes under a time budget, ticks the sync deadline, and paints. A Playwright harness under `packages/terminal/bench/agent-session/` replays recorded Claude Code streams to measure the baseline and to gate every task on a zero-pixel diff ("feel gate"). A `tests/ref` corpus (Alacritty's 45 recordings plus our own) and a debug-build integrity checker guard the model.

**Tech Stack:** Rust (`vt-core`, `vt-wasm` via wasm-bindgen, `vt-host` C-ABI wasm run by wazero), Go (`backend/internal/adapters/runtime/ptyhost`), TypeScript (`ts/core`, `ts/renderer-dom`, `ts/react`, `frontend/`), Vite + Playwright benches, `proptest` (dev-dependency), Python 3 (recording tool, corpus import).

**Spec:** `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` — Plan A covers the baseline harness and feel gate, §2.5, §2.1, §2.2, §2.3, §2.4 (the "Plan A task outline" section). Survey entries cited: `docs/superpowers/specs/2026-09-19-terminal-reference-survey.md` §1.14, §2.1, §2.9, §2.10, §3.3, §3.13, §5.10, §7.6. Read `TERMINAL.md` end to end before starting.

## Global Constraints

Every task inherits these; they are the spec's "Global constraints" plus `TERMINAL.md` §3.

- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no Operator import, path, default or concept inside it. Operator wiring goes in `frontend/` and `backend/`.
- No comments in new code (user's global instruction). Existing comments may be corrected when they become false. A code comment that cites a reference names the repository and path (`vte-0.15.0/src/ansi.rs`, `xterm.js/src/browser/services/CharSizeService.ts`, `alacritty_terminal/tests/ref.rs`) the way `styles.css` cites Warp — such citations are the one kind of new comment permitted.
- A `vt-core` change is live only after **both** wasm artifacts are rebuilt (`vt_core` for the renderer, `vt_host.wasm` copied into `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/`) and the daemon is rebuilt (`npm --prefix frontend run build:daemon`). Old pty-host processes keep the old wasm for the life of the session; every such task ends with "restart the daemon and the app".
- TDD: failing test first, run it, minimal implementation, run it, commit. Every `TERMINAL.md` §4 guard keeps passing.
- Rust: `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` from `/Users/omaraly/development/AI/Operator/packages/terminal`. TS: `npx vitest run` in each of `ts/core`, `ts/renderer-dom`, `ts/react`; `npx tsc --noEmit -p .` in `frontend/`. Go: `go test ./internal/adapters/runtime/ptyhost/...` in `backend/`.
- Changelog: `packages/terminal/CHANGELOG.md`, "Unreleased", one entry per behaviour change. Commits go to `development` with the `Co-Authored-By` trailer the harness gives you.
- Use absolute paths in every shell command (`TERMINAL.md` §6: parallel Bash calls share the working directory).
- Do not change behaviour the spec does not ask for. Specifically: no leading edge or max-wait on the resize debounce (`TERMINAL.md` §4.6); no change to scrollback caps or the snapshot export shape (Plan B); do not chase the §4.8 duplicate row.
- Feel gate: from Task 1 on, every task ends with `npm run bench:feel` and it must report zero diff. No task in this plan declares a scoped pixel change.
- Timestamps are milliseconds. In Rust they are `u64` (`now_ms`), in wasm-bindgen `f64`, in TS `number` from `performance.now()`, in Go `int64` from `time.Now().UnixMilli()`.

## Deviations from the spec, decided here

- **§2.3 TextMetrics.** The spec prefers `measureText('W')` + `fontBoundingBoxAscent/Descent` with the DOM span as fallback. Task 7 caches the DOM-span measurement and adds no `TextMetrics` path: once cached, the measurement runs once per font/DPR change so the strategy no longer affects cost, and the feel gate requires the exact numbers the span produced today (a `TextMetrics` height is the font box, not the span's rect, and would move every row). If the user wants `TextMetrics` anyway it is a one-function change behind the same cache.
- **§2.3 `ResizeObserver` on the measure host.** Not added. `#terminal-measure-host` is a document-wide singleton (`host-dom.ts:3-19`) whose span every renderer restyles in `measure()`; `observe()` fires an initial notification (one spurious invalidate per renderer) and two renderers with different fonts would invalidate each other forever. `setFont`/`setTheme` and the DPR query cover every way the cell size changes.
- **§2.4 "export prefix counters ≤ actual lengths".** Those counters (`history_exported_rows/bytes`) are Plan B's; the checker gains that clause when they exist.
- **§2.4 "`wrapped` rows are followed by a row".** Pinned as "a `wrapped` row is never empty" plus contiguity: the continuation of the last scrollback row can legitimately sit on the screen, and an in-place clear may have blanked it, so "followed by a row" is not a true invariant of the model.
- **§2.4 "blocks tile the flat row space in order without overlap".** Not an invariant of this model: `Parser::open_block` starts a block at the cursor row (`block_start_row`, `parser.rs:283-286`), so a prompt mark after a cursor-up legitimately opens a block above the previous block's end, and the random CUP + OSC 133 sequences of the property test hit that at once. The checker pins what does hold — every block lies inside the flat row space and `next_row` does not run past it — and the spec's overlap clause is dropped rather than encoded as a known-failing test.
- **§2.4 "one failing fixture per invariant" in `tests/integrity.rs`.** Corrupting the model to trip one invariant needs crate-private access, so those seven fixtures are unit tests in `src/integrity.rs`; the property test and the public-API regressions are in `tests/integrity.rs` as the spec says.
- **§2.5 `Limits::DEFAULT`.** `Limits` is Plan B's. The ref harness uses `REF_SCROLLBACK_ROWS = 200_000` (the spec's row cap); Plan B switches it to `Limits::DEFAULT`.
- **Baseline table.** `claude-spinner-10s` has too few rows for the 1k/5k/50k rows, scroll, memory and reopen rows. Task 1 measures what the spinner fixture supports (paints/s, DOM nodes per paint, torn paints); Task 2 records `claude-long-50k` and fills the rest. Numbers are measured, never invented.
- **Replay inside a sync block (§2.1 Go test).** `vt_replay` renders the mirror's last complete frame and then appends the mirror's still-buffered sync bytes verbatim. The attaching client therefore paints the previous frame (no half frame) *and* buffers the partial frame in its own core, so the live bytes that follow complete it correctly. Rendering the partial would tear; dropping it would corrupt the client until the next full repaint.

## File structure

New or modified, by task:

| Task | Files |
|---|---|
| 1 | `packages/terminal/bench/agent-session/{index.html,main.ts,fixtures.mjs,fixtures.test.mjs,run.mjs,feel-gate.mjs,scroll-gate.mjs,record-pty.py}`, `bench/agent-session/fixtures/claude-spinner-10s/{recording,size.json}`, `bench/agent-session/baselines/claude-spinner-10s/*.png`, `packages/terminal/package.json` (scripts), spec baseline table |
| 2 | `backend/internal/adapters/runtime/ptyhost/{record.go,record_test.go,host.go,host_main.go,host_main_test.go}`, `RUN_APP_COMMANDS.md`, `bench/agent-session/fixtures/claude-long-50k/*`, `bench/agent-session/baselines/claude-long-50k/*.png`, `backend/internal/adapters/runtime/ptyhost/vtwasm/agent_session_test.go`, spec baseline table |
| 3 | `packages/terminal/crates/vt-core/tests/ref.rs`, `tests/ref/<name>/{recording,size.json,screen.txt,cursor.json}` ×46, `tests/ref/ALACRITTY-ATTRIBUTION.md`, `tests/ref/LICENSE-APACHE`, `tests/ref/LICENSE-MIT`, `tests/ref/TRIAGE.md`, `packages/terminal/tools/import-alacritty-ref.py`, `packages/terminal/tools/alacritty-grid-text.py` |
| 4 | `crates/vt-core/src/{integrity.rs,trace.rs,lib.rs,parser.rs,content.rs,attribute_map.rs,row_index.rs}`, `crates/vt-core/Cargo.toml`, `crates/vt-core/tests/common/mod.rs`, `crates/vt-core/tests/integrity.rs` |
| 5 | `crates/vt-core/src/{sync.rs,lib.rs,parser.rs}`, `crates/vt-core/tests/synchronized_output.rs`, `crates/vt-wasm/src/lib.rs`, `ts/core/src/{terminal-core.ts,terminal-core.test.ts}`, `ts/renderer-dom/src/{dom-block-renderer.ts,dom-block-renderer.test.ts}`, `crates/vt-host/src/lib.rs`, `backend/.../ptyhost/vtwasm/{vtwasm.go,vtwasm_test.go,replay_test.go,assets/vt_host.wasm}`, `backend/.../ptyhost/{host.go,host_test.go,pump_test.go}`, `TERMINAL.md` (§4.16), `CHANGELOG.md` |
| 6 | `ts/core/src/{terminal-core.ts,terminal-core.test.ts}`, `ts/renderer-dom/src/dom-block-renderer.ts`, `frontend/src/renderer/components/{BlockTerminal.tsx,BlockTerminal.test.tsx}`, `bench/agent-session/run.mjs`, `CHANGELOG.md` |
| 7 | `ts/renderer-dom/src/{dom-block-renderer.ts,dom-block-renderer.test.ts}`, `CHANGELOG.md` |
| 8 | `bench/agent-session/run.mjs`, `packages/terminal/package.json`, spec baseline table (After column), `TERMINAL.md` §6 |

Fixture and corpus layout, shared by Tasks 1–3:

```
<dir>/recording        raw pty bytes, exactly as the child wrote them
<dir>/size.json        JSON array: [{"offset":0,"cols":120,"rows":40}, {"offset":18342,"cols":100,"rows":40}, ...]
                       offset = byte offset into recording at which that grid took effect; first entry offset 0
```

---

### Task 1: Agent-session harness, feel gate, spinner fixture

**Files:**
- Create: `packages/terminal/bench/agent-session/index.html`
- Create: `packages/terminal/bench/agent-session/main.ts`
- Create: `packages/terminal/bench/agent-session/fixtures.mjs`
- Create: `packages/terminal/bench/agent-session/fixtures.test.mjs`
- Create: `packages/terminal/bench/agent-session/run.mjs`
- Create: `packages/terminal/bench/agent-session/feel-gate.mjs`
- Create: `packages/terminal/bench/agent-session/scroll-gate.mjs`
- Create: `packages/terminal/bench/agent-session/record-pty.py`
- Create: `packages/terminal/bench/agent-session/fixtures/claude-spinner-10s/{recording,size.json}`
- Create: `packages/terminal/bench/agent-session/baselines/claude-spinner-10s/*.png`
- Modify: `packages/terminal/package.json` (scripts `bench:agent`, `bench:feel`, `test`)
- Modify: `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` (baseline table "Today" column)

**Interfaces:**
- Consumes: `DomBenchmarkRenderer` from `bench/adapters/dom.ts` (`mount(host, {columns, rows, scrollback})`, `write(bytes)`, `waitForPaint()`, `getCoreForBench()`), `decodeBlocks` and `TerminalCore` from `@operator/terminal-core`.
- Produces: `bench/agent-session/fixtures.mjs` exporting `loadFixture(name) -> { name, recording: Uint8Array, sizes: Array<{offset, cols, rows}> }`, `listFixtures() -> string[]`, `FIXTURES_DIR`; `window.__agentSession` (see Step 5); `npm run bench:agent [-- --fixture <name>]` printing one JSON object per metric row; `npm run bench:feel [-- --record] [-- --fixture <name>]`.

- [ ] **Step 1: Write the failing fixture-layout test**

`packages/terminal/bench/agent-session/fixtures.test.mjs`:

```js
import assert from "node:assert/strict";
import { test } from "node:test";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { FIXTURES_DIR, listFixtures, loadFixture } from "./fixtures.mjs";

test("every fixture directory has a recording and a well-formed size.json", async () => {
	const names = listFixtures();
	assert.ok(names.includes("claude-spinner-10s"), `fixtures: ${names.join(", ")}`);
	for (const name of names) {
		assert.ok(existsSync(join(FIXTURES_DIR, name, "recording")));
		const fixture = await loadFixture(name);
		assert.ok(fixture.recording.length > 0, `${name}: empty recording`);
		assert.ok(fixture.sizes.length >= 1, `${name}: size.json has no entries`);
		assert.equal(fixture.sizes[0].offset, 0, `${name}: first size entry must start at offset 0`);
		let previous = -1;
		for (const size of fixture.sizes) {
			assert.ok(Number.isInteger(size.offset) && size.offset > previous, `${name}: offsets must increase`);
			assert.ok(size.offset <= fixture.recording.length, `${name}: offset past the recording`);
			assert.ok(size.cols >= 1 && size.cols <= 1000 && size.rows >= 1 && size.rows <= 1000, `${name}: grid out of range`);
			previous = size.offset;
		}
	}
});

test("the spinner fixture contains synchronized-output frames", async () => {
	const { recording } = await loadFixture("claude-spinner-10s");
	const text = Buffer.from(recording).toString("latin1");
	const esus = text.split("\x1b[?2026l").length - 1;
	assert.ok(esus >= 50, `expected at least 50 ESU-terminated frames, found ${esus}`);
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && node --test ./bench/agent-session/fixtures.test.mjs`
Expected: FAIL — `Cannot find module './fixtures.mjs'`.

- [ ] **Step 3: Write `fixtures.mjs`**

`packages/terminal/bench/agent-session/fixtures.mjs`:

```js
import { readdirSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

export const FIXTURES_DIR = fileURLToPath(new URL("./fixtures/", import.meta.url));

export function listFixtures() {
	return readdirSync(FIXTURES_DIR, { withFileTypes: true })
		.filter((entry) => entry.isDirectory())
		.map((entry) => entry.name)
		.sort();
}

export async function loadFixture(name) {
	const dir = join(FIXTURES_DIR, name);
	const recording = new Uint8Array(await readFile(join(dir, "recording")));
	const sizes = JSON.parse(await readFile(join(dir, "size.json"), "utf8"));
	if (!Array.isArray(sizes)) throw new Error(`${name}/size.json must be a JSON array`);
	return { name, recording, sizes };
}

export function frameBoundaries(recording) {
	const esu = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x6c];
	const ends = [];
	for (let index = 0; index + esu.length <= recording.length; index += 1) {
		let match = true;
		for (let k = 0; k < esu.length; k += 1) {
			if (recording[index + k] !== esu[k]) {
				match = false;
				break;
			}
		}
		if (match) {
			ends.push(index + esu.length);
			index += esu.length - 1;
		}
	}
	return ends;
}
```

`frameBoundaries` returns the byte offset just past every ESU; the runner and Task 8's tearing gate slice frames with it.

- [ ] **Step 4: Record the spinner fixture with the pty recorder**

`packages/terminal/bench/agent-session/record-pty.py` (the `TERMINAL.md` §7 capture tool, made permanent; runs any command under a pty at a fixed grid, tees the raw child output and the size log in the fixture layout):

```python
#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import pty
import select
import signal
import struct
import sys
import termios
import tty


def set_winsize(fd, cols, rows):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def main():
    parser = argparse.ArgumentParser(description="record a pty session in the agent-session fixture layout")
    parser.add_argument("--out", required=True, help="fixture directory to create")
    parser.add_argument("--cols", type=int, default=120)
    parser.add_argument("--rows", type=int, default=40)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command:
        parser.error("command is required")
    os.makedirs(args.out, exist_ok=True)
    recording = open(os.path.join(args.out, "recording"), "wb")
    sizes = [{"offset": 0, "cols": args.cols, "rows": args.rows}]
    written = 0

    def write_sizes():
        with open(os.path.join(args.out, "size.json"), "w") as handle:
            json.dump(sizes, handle)

    write_sizes()
    pid, master = pty.fork()
    if pid == 0:
        os.execvp(args.command[0], args.command)
    set_winsize(master, args.cols, args.rows)
    state = {"cols": args.cols, "rows": args.rows}

    def on_winch(_signum, _frame):
        try:
            packed = fcntl.ioctl(sys.stdout.fileno(), termios.TIOCGWINSZ, b"\0" * 8)
        except OSError:
            return
        rows, cols, _, _ = struct.unpack("HHHH", packed)
        if cols == 0 or rows == 0 or (cols, rows) == (state["cols"], state["rows"]):
            return
        state["cols"], state["rows"] = cols, rows
        set_winsize(master, cols, rows)
        sizes.append({"offset": written, "cols": cols, "rows": rows})
        write_sizes()

    signal.signal(signal.SIGWINCH, on_winch)
    stdin = sys.stdin.fileno()
    saved = termios.tcgetattr(stdin)
    tty.setraw(stdin)
    try:
        while True:
            ready, _, _ = select.select([master, stdin], [], [])
            if master in ready:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                recording.write(data)
                recording.flush()
                written += len(data)
                os.write(sys.stdout.fileno(), data)
            if stdin in ready:
                data = os.read(stdin, 65536)
                if not data:
                    break
                os.write(master, data)
    finally:
        termios.tcsetattr(stdin, termios.TCSADRAIN, saved)
        recording.close()
        write_sizes()
    _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status)


if __name__ == "__main__":
    sys.exit(main())
```

Record, from a real terminal (not from inside a Claude Code session — see the memory `scrub-claude-env-before-running-operator-dev`; the recorder itself must not carry `CLAUDE*` variables or the child disables transcripts, which does not matter for bytes but changes its banner):

```bash
cd /tmp && mkdir -p agent-fixture-scratch && cd agent-fixture-scratch && git init -q . && env $(env | grep -o '^CLAUDE[A-Z_0-9]*=' | sed 's/=$//; s/^/-u /') python3 /Users/omaraly/development/AI/Operator/packages/terminal/bench/agent-session/record-pty.py --out /Users/omaraly/development/AI/Operator/packages/terminal/bench/agent-session/fixtures/claude-spinner-10s --cols 120 --rows 40 claude
```

In the session: type a prompt that makes Claude think for a while without printing much (for example `Think carefully about the Collatz conjecture for 30 seconds and then answer with one word.`), wait ≥ 10 s of spinner, then `/exit`. Trim the recording to about 100 frames after the spinner starts:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && node -e '
const fs = require("node:fs");
const dir = "bench/agent-session/fixtures/claude-spinner-10s";
const bytes = fs.readFileSync(dir + "/recording");
const text = bytes.toString("latin1");
const esu = "\x1b[?2026l";
let ends = []; let at = 0;
while ((at = text.indexOf(esu, at)) !== -1) { ends.push(at + esu.length); at += esu.length; }
if (ends.length < 120) throw new Error("recording has only " + ends.length + " frames; record a longer spinner");
const keep = ends[ends.length - 1] <= ends[119] ? bytes.length : ends[119];
fs.writeFileSync(dir + "/recording", bytes.subarray(0, keep));
const sizes = JSON.parse(fs.readFileSync(dir + "/size.json", "utf8")).filter((s) => s.offset < keep);
fs.writeFileSync(dir + "/size.json", JSON.stringify(sizes));
console.log("kept", keep, "bytes,", Math.min(ends.length, 120), "frames");
'
```

Check the recording for secrets before committing (`strings` it; an API key or a path under `~/` that the user does not want published means re-record in a scratch project). The fixture is committed as bytes.

- [ ] **Step 5: Run the fixture test to see it pass**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && node --test ./bench/agent-session/fixtures.test.mjs`
Expected: PASS (2 tests).

- [ ] **Step 6: Write the browser page**

`packages/terminal/bench/agent-session/index.html`:

```html
<!doctype html>
<html lang="en">
	<head>
		<meta charset="UTF-8" />
		<title>agent session harness</title>
		<style>
			html, body, #terminal { width: 100%; height: 100%; margin: 0; overflow: hidden; background: #0b0d10; }
			#terminal { padding: 8px; box-sizing: border-box; }
		</style>
	</head>
	<body>
		<div id="terminal"></div>
		<script type="module" src="/agent-session/main.ts"></script>
	</body>
</html>
```

`packages/terminal/bench/agent-session/main.ts`:

```ts
import { decodeBlocks, type TerminalCore } from "@operator/terminal-core";
import { DomBenchmarkRenderer } from "../adapters/dom";

type SizeEntry = { offset: number; cols: number; rows: number };

declare global {
	interface Window {
		__agentSession: AgentSession;
		__agentSessionReady: boolean;
	}
}

type AgentSession = {
	fixture: { name: string; sizes: SizeEntry[]; bytes: number };
	fed: number;
	feedAll(): Promise<void>;
	feedUntilRows(target: number): Promise<number>;
	feedNext(limit: number): number;
	feedChunk(start: number, end: number): number;
	feedFrames(count: number, intervalMs: number): Promise<void>;
	rowCount(): number;
	paintCount(): number;
	addedNodes(): number;
	resetCounters(): void;
	longTasks(): number[];
	memoryBytes(): number;
	scrollHeight(): number;
	scrollTop(): number;
	setScrollTop(top: number): Promise<void>;
	visibleRows(): Array<{ block: string; row: number }>;
	textHash(): string;
	modelHash(): string;
	core(): TerminalCore;
};

const host = document.getElementById("terminal");
if (!host) throw new Error("agent-session host is missing");
const params = new URLSearchParams(location.search);
const fixtureName = params.get("fixture") ?? "claude-spinner-10s";
const scrollback = Number(params.get("scrollback") ?? "200000");

const [recordingResponse, sizesResponse] = await Promise.all([
	fetch(`/agent-session/fixtures/${fixtureName}/recording`),
	fetch(`/agent-session/fixtures/${fixtureName}/size.json`),
]);
if (!recordingResponse.ok || !sizesResponse.ok) throw new Error(`fixture ${fixtureName} is missing`);
const recording = new Uint8Array(await recordingResponse.arrayBuffer());
const sizes = (await sizesResponse.json()) as SizeEntry[];

const renderer = new DomBenchmarkRenderer();
await renderer.mount(host, { columns: sizes[0].cols, rows: sizes[0].rows, scrollback });
const core = renderer.getCoreForBench() as TerminalCore;
core.setAgentTuiMode(true);

let paints = 0;
let addedNodes = 0;
let fed = 0;
let nextResize = 1;
const longTasks: number[] = [];
const domRenderer = (renderer as unknown as { renderer: { onPaint(listener: () => void): () => void } }).renderer;
domRenderer.onPaint(() => {
	paints += 1;
});
new MutationObserver((records) => {
	for (const record of records) addedNodes += record.addedNodes.length;
}).observe(host, { childList: true, subtree: true });
if (typeof PerformanceObserver === "function") {
	try {
		new PerformanceObserver((list) => {
			for (const entry of list.getEntries()) longTasks.push(entry.duration);
		}).observe({ entryTypes: ["longtask"] });
	} catch {}
}

function applyResizesUpTo(offset: number): void {
	while (nextResize < sizes.length && sizes[nextResize].offset <= offset) {
		const size = sizes[nextResize];
		core.resize(size.cols, size.rows);
		nextResize += 1;
	}
}

function feedChunk(start: number, end: number): number {
	applyResizesUpTo(start);
	const chunk = recording.subarray(start, end);
	const before = performance.now();
	core.feed(chunk);
	const cost = performance.now() - before;
	fed = Math.max(fed, end);
	return cost;
}

function feedNext(limit: number): number {
	const end = Math.min(recording.length, fed + limit);
	if (end <= fed) return 0;
	return feedChunk(fed, end);
}

function rowCount(): number {
	return core.snapshot().rows.length / 2;
}

async function nextFrame(): Promise<void> {
	await new Promise((resolve) => requestAnimationFrame(() => resolve(undefined)));
}

async function feedAll(): Promise<void> {
	while (fed < recording.length) {
		feedNext(64 * 1024);
		await nextFrame();
	}
	await renderer.waitForPaint().catch(() => undefined);
}

async function feedUntilRows(target: number): Promise<number> {
	while (fed < recording.length && rowCount() < target) {
		feedNext(64 * 1024);
		await nextFrame();
	}
	await renderer.waitForPaint().catch(() => undefined);
	return rowCount();
}

function frameEnds(): number[] {
	const esu = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x6c];
	const ends: number[] = [];
	for (let index = 0; index + esu.length <= recording.length; index += 1) {
		let match = true;
		for (let k = 0; k < esu.length; k += 1) {
			if (recording[index + k] !== esu[k]) {
				match = false;
				break;
			}
		}
		if (match) {
			ends.push(index + esu.length);
			index += esu.length - 1;
		}
	}
	return ends;
}

async function feedFrames(count: number, intervalMs: number): Promise<void> {
	const ends = frameEnds().filter((end) => end > fed).slice(0, count);
	for (const end of ends) {
		feedChunk(fed, end);
		await new Promise((resolve) => setTimeout(resolve, intervalMs));
	}
}

function visibleRows(): Array<{ block: string; row: number }> {
	const box = host!.getBoundingClientRect();
	const out: Array<{ block: string; row: number }> = [];
	for (const section of host!.querySelectorAll<HTMLElement>("[data-terminal-block-id]")) {
		const block = section.dataset.terminalBlockId ?? "";
		for (const row of section.querySelectorAll<HTMLElement>("[data-terminal-row]")) {
			const rect = row.getBoundingClientRect();
			if (rect.bottom >= box.top && rect.top <= box.bottom) out.push({ block, row: Number(row.dataset.terminalRow) });
		}
	}
	return out;
}

function fnv(text: string): string {
	let hash = 2166136261;
	for (const ch of text) {
		hash ^= ch.codePointAt(0)!;
		hash = Math.imul(hash, 16777619) >>> 0;
	}
	return hash.toString(16);
}

function textHash(): string {
	const rows = [...host!.querySelectorAll<HTMLElement>("[data-terminal-row]")].map((row) => row.textContent ?? "");
	return fnv(rows.join("\n"));
}

function modelHash(): string {
	const snapshot = core.snapshot();
	const decoder = new TextDecoder();
	let text = `${snapshot.cursorRow}:${snapshot.cursorColumn}\n`;
	for (let index = 0; index < snapshot.rows.length; index += 2) {
		text += `${decoder.decode(snapshot.content.subarray(snapshot.rows[index]!, snapshot.rows[index + 1]!))}\n`;
	}
	return fnv(text);
}

const scroller = host.querySelector<HTMLElement>(".terminal-host") ?? host;

window.__agentSession = {
	fixture: { name: fixtureName, sizes, bytes: recording.length },
	get fed() {
		return fed;
	},
	feedAll,
	feedUntilRows,
	feedNext,
	feedChunk,
	feedFrames,
	rowCount,
	paintCount: () => paints,
	addedNodes: () => addedNodes,
	resetCounters: () => {
		paints = 0;
		addedNodes = 0;
		longTasks.length = 0;
	},
	longTasks: () => [...longTasks],
	memoryBytes: () => core.snapshot().content.buffer.byteLength,
	scrollHeight: () => scroller.scrollHeight,
	scrollTop: () => scroller.scrollTop,
	setScrollTop: async (top: number) => {
		scroller.scrollTop = top;
		scroller.dispatchEvent(new Event("scroll"));
		await nextFrame();
		await nextFrame();
	},
	visibleRows,
	textHash,
	modelHash,
	core: () => core,
	blocks: () => decodeBlocks(core.snapshot()).length,
} as AgentSession & { blocks(): number };
window.__agentSessionReady = true;
```

The `DomBenchmarkRenderer` keeps its `DomBlockRenderer` in a private field named `renderer`; the cast above reads it for `onPaint`. Check that `DomBlockRenderer.mount` sets the scroll container: it is the element handed to `mount`, i.e. `host` itself (the adapter mounts on `host`), so `scroller` resolves to `host` — keep the `.terminal-host` lookup for the React surface case and the fallback for this one.

- [ ] **Step 7: Write `run.mjs` (the measurements)**

`packages/terminal/bench/agent-session/run.mjs`:

```js
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";
import { frameBoundaries, listFixtures, loadFixture } from "./fixtures.mjs";

const benchDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const configFile = path.join(benchDir, "vite.config.ts");
const resultsDir = path.join(benchDir, "results");

function parseArgs(argv) {
	const out = { fixture: undefined, gate: false };
	for (let index = 0; index < argv.length; index += 1) {
		if (argv[index] === "--fixture") out.fixture = argv[++index];
		else if (argv[index] === "--gate") out.gate = true;
		else throw new Error(`unsupported argument ${argv[index]}`);
	}
	return out;
}

function median(values) {
	const sorted = [...values].sort((a, b) => a - b);
	return sorted.length === 0 ? null : sorted[Math.floor(sorted.length / 2)];
}

async function openPage(browser, port, fixture) {
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=${fixture}`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	return page;
}

async function feedCostAt(page, rows) {
	const reached = await page.evaluate((target) => window.__agentSession.feedUntilRows(target), rows);
	if (reached < rows) return { rows, reached, medianMs: null };
	const samples = await page.evaluate(() => {
		const out = [];
		for (let index = 0; index < 20; index += 1) {
			const cost = window.__agentSession.feedNext(4096);
			if (cost === 0) break;
			out.push(cost);
		}
		return out;
	});
	return { rows, reached, medianMs: median(samples), samples: samples.length };
}

async function spinnerPaints(page) {
	await page.evaluate(() => window.__agentSession.resetCounters());
	await page.evaluate(() => window.__agentSession.feedFrames(100, 100));
	await page.waitForTimeout(200);
	return page.evaluate(() => ({
		paints: window.__agentSession.paintCount(),
		addedNodes: window.__agentSession.addedNodes(),
	}));
}

async function tornPaints(page, recording) {
	const ends = frameBoundaries(recording);
	const states = await page.evaluate((frameEnds) => {
		const session = window.__agentSession;
		let tornStates = 0;
		let start = session.fed;
		for (const end of frameEnds) {
			if (end <= start) continue;
			let last = session.modelHash();
			for (let at = start; at < end; at += 1) {
				session.feedChunk(at, at + 1);
				const hash = session.modelHash();
				if (hash !== last) {
					if (at + 1 < end) tornStates += 1;
					last = hash;
				}
			}
			start = end;
		}
		return { frames: frameEnds.length, tornStates };
	}, ends);
	return states;
}

async function paintsPerFrame(page, recording) {
	const ends = frameBoundaries(recording);
	return page.evaluate(async (frameEnds) => {
		const session = window.__agentSession;
		const frame = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
		let tornPaints = 0;
		let multiPaintFrames = 0;
		let start = session.fed;
		for (const end of frameEnds) {
			if (end <= start) continue;
			const before = session.textHash();
			const cuts = [start + Math.floor((end - start) / 3), start + Math.floor((2 * (end - start)) / 3), end];
			const seen = new Set();
			let from = start;
			for (const cut of cuts) {
				if (cut > from) session.feedChunk(from, cut);
				from = cut;
				await frame();
				seen.add(session.textHash());
			}
			const after = session.textHash();
			for (const hash of seen) if (hash !== before && hash !== after) tornPaints += 1;
			const distinct = [...seen].filter((hash) => hash !== before).length;
			if (distinct > 1) multiPaintFrames += 1;
			start = end;
		}
		return { tornPaints, multiPaintFrames };
	}, ends);
}

async function longTask2MiB(page) {
	await page.evaluate(() => window.__agentSession.resetCounters());
	const feedMs = await page.evaluate(() => window.__agentSession.feedNext(2 * 1024 * 1024));
	await page.waitForTimeout(500);
	const tasks = await page.evaluate(() => window.__agentSession.longTasks());
	return { feedMs, longestTaskMs: tasks.length ? Math.max(...tasks) : null, longTasks: tasks.length };
}

async function main() {
	const args = parseArgs(process.argv.slice(2));
	const fixtures = args.fixture ? [args.fixture] : listFixtures();
	const server = await createServer({ configFile, logLevel: "error" });
	let browser;
	const report = { measuredAt: new Date().toISOString(), fixtures: {} };
	try {
		await server.listen(0);
		const port = server.httpServer.address().port;
		browser = await chromium.launch({ headless: true });
		for (const name of fixtures) {
			const fixture = await loadFixture(name);
			const rows = {};
			if (name === "claude-spinner-10s") {
				const page = await openPage(browser, port, name);
				rows.spinner = await spinnerPaints(page);
				await page.close();
				const tearPage = await openPage(browser, port, name);
				const states = await tornPaints(tearPage, fixture.recording);
				await tearPage.close();
				const paintPage = await openPage(browser, port, name);
				rows.tearing = { ...states, ...(await paintsPerFrame(paintPage, fixture.recording)) };
				await paintPage.close();
			} else {
				const page = await openPage(browser, port, name);
				rows.feedCost = [];
				for (const target of [1000, 5000, 50000]) rows.feedCost.push(await feedCostAt(page, target));
				rows.longTask = await longTask2MiB(page);
				await page.evaluate(() => window.__agentSession.feedAll());
				rows.rows = await page.evaluate(() => window.__agentSession.rowCount());
				rows.rendererMemoryBytes = await page.evaluate(() => window.__agentSession.memoryBytes());
				await page.close();
			}
			report.fixtures[name] = rows;
			process.stdout.write(`${JSON.stringify({ fixture: name, ...rows })}\n`);
		}
		await mkdir(resultsDir, { recursive: true });
		await writeFile(path.join(resultsDir, `agent-session-${report.measuredAt.replace(/[:.]/g, "-")}.json`), JSON.stringify(report, null, "\t"));
		if (args.gate) {
			const tearing = report.fixtures["claude-spinner-10s"]?.tearing;
			if (!tearing) throw new Error("gate needs the claude-spinner-10s fixture");
			if (tearing.tornStates !== 0) throw new Error(`${tearing.tornStates} model states inside a sync block became visible`);
			if (tearing.tornPaints !== 0) throw new Error(`${tearing.tornPaints} paints showed a partial frame`);
			if (tearing.multiPaintFrames !== 0) throw new Error(`${tearing.multiPaintFrames} frames painted more than once`);
			const longTask = Object.values(report.fixtures).find((rows) => rows.longTask)?.longTask;
			if (longTask && longTask.longestTaskMs !== null && longTask.longestTaskMs > 16) throw new Error(`2 MiB feed blocked the main thread for ${longTask.longestTaskMs.toFixed(1)}ms`);
			process.stdout.write("PASS agent-session gate\n");
		}
	} catch (error) {
		process.stderr.write(`FAIL ${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	} finally {
		await browser?.close();
		await server.close();
	}
}

await main();
```

`--gate` is inert until Task 8 wires it into the scripts; it exists now so the same file measures "Today" and gates "After".

- [ ] **Step 8: Write `scroll-gate.mjs`**

`packages/terminal/bench/agent-session/scroll-gate.mjs` (measures scroll bottom → row 0 and asserts contiguity; the 50 ms frame budget is reported, not asserted, until Plan B):

```js
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const benchDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const configFile = path.join(benchDir, "vite.config.ts");
const fixture = process.argv.includes("--fixture") ? process.argv[process.argv.indexOf("--fixture") + 1] : "claude-long-50k";

const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await chromium.launch({ headless: true });
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=${fixture}`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	await page.evaluate(() => window.__agentSession.feedAll());
	const result = await page.evaluate(async () => {
		const session = window.__agentSession;
		const total = session.rowCount();
		const seen = new Map();
		const slow = [];
		let step = 0;
		const viewport = 450;
		let top = session.scrollHeight();
		let last = performance.now();
		while (top > 0) {
			top = Math.max(0, top - viewport);
			await session.setScrollTop(top);
			const now = performance.now();
			if (now - last > 50) slow.push(now - last);
			last = now;
			const byBlock = new Map();
			for (const { block, row } of session.visibleRows()) {
				if (!byBlock.has(block)) byBlock.set(block, []);
				byBlock.get(block).push(row);
				if (!seen.has(block)) seen.set(block, new Set());
				seen.get(block).add(row);
			}
			for (const [block, rows] of byBlock) {
				rows.sort((a, b) => a - b);
				for (let index = 1; index < rows.length; index += 1) {
					if (rows[index] !== rows[index - 1] + 1) throw new Error(`block ${block} rendered rows ${rows[index - 1]} and ${rows[index]} without ${rows[index - 1] + 1} at step ${step}`);
				}
			}
			step += 1;
		}
		let covered = 0;
		for (const rows of seen.values()) covered += rows.size;
		return { total, covered, steps: step, framesOver50ms: slow.length, worstFrameMs: slow.length ? Math.max(...slow) : 0 };
	});
	if (result.covered < result.total) throw new Error(`scrolling reached ${result.covered} of ${result.total} rows`);
	process.stdout.write(`${JSON.stringify({ fixture, ...result })}\n`);
} catch (error) {
	process.stderr.write(`FAIL ${error instanceof Error ? error.message : String(error)}\n`);
	process.exitCode = 1;
} finally {
	await browser?.close();
	await server.close();
}
```

- [ ] **Step 9: Write `feel-gate.mjs`**

`packages/terminal/bench/agent-session/feel-gate.mjs`:

```js
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";
import { listFixtures } from "./fixtures.mjs";

const agentDir = path.dirname(fileURLToPath(import.meta.url));
const benchDir = path.resolve(agentDir, "..");
const configFile = path.join(benchDir, "vite.config.ts");
const baselinesDir = path.join(agentDir, "baselines");
const diffDir = path.join(benchDir, "results", "feel-diff");
const OFFSETS = [0, 0.25, 0.5, 0.75, 1];

const argv = process.argv.slice(2);
const record = argv.includes("--record");
const only = argv.includes("--fixture") ? argv[argv.indexOf("--fixture") + 1] : undefined;
const fixtures = only ? [only] : listFixtures();

const server = await createServer({ configFile, logLevel: "error" });
let browser;
let failures = 0;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await chromium.launch({ headless: true });
	for (const fixture of fixtures) {
		const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
		await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=${fixture}`);
		await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
		await page.evaluate(() => window.__agentSession.feedAll());
		await page.waitForTimeout(300);
		const dir = path.join(baselinesDir, fixture);
		await mkdir(dir, { recursive: true });
		for (const fraction of OFFSETS) {
			const name = `offset-${Math.round(fraction * 100)}.png`;
			await page.evaluate(async (f) => {
				const session = window.__agentSession;
				await session.setScrollTop(Math.round(session.scrollHeight() * f));
			}, fraction);
			await page.waitForTimeout(100);
			const shot = await page.screenshot({ type: "png", animations: "disabled", caret: "hide" });
			const file = path.join(dir, name);
			if (record || !existsSync(file)) {
				await writeFile(file, shot);
				process.stdout.write(`recorded ${fixture}/${name}\n`);
				continue;
			}
			const baseline = await readFile(file);
			if (Buffer.compare(baseline, shot) !== 0) {
				failures += 1;
				await mkdir(path.join(diffDir, fixture), { recursive: true });
				await writeFile(path.join(diffDir, fixture, name), shot);
				process.stderr.write(`DIFF ${fixture}/${name} (actual saved under bench/results/feel-diff)\n`);
			}
		}
		await page.close();
	}
	if (failures > 0) throw new Error(`${failures} screenshot(s) differ from the baseline`);
	process.stdout.write(record ? "recorded feel baselines\n" : "PASS feel gate: zero pixel diff\n");
} catch (error) {
	process.stderr.write(`FAIL ${error instanceof Error ? error.message : String(error)}\n`);
	process.exitCode = 1;
} finally {
	await browser?.close();
	await server.close();
}
```

Byte-equal PNGs from the same Chromium at the same viewport and scale factor are pixel-equal; `animations: "disabled"` and `caret: "hide"` remove the only nondeterminism the page has. Baselines are recorded on this machine with this Playwright build; the gate is a before/after check within Plan A, not a cross-machine artefact.

- [ ] **Step 10: Add the npm scripts**

In `packages/terminal/package.json` `scripts`, add after `"bench:gate"`:

```json
		"bench:agent": "node ./bench/agent-session/run.mjs",
		"bench:agent:scroll": "node ./bench/agent-session/scroll-gate.mjs",
		"bench:feel": "node ./bench/agent-session/feel-gate.mjs"
```

and extend `"test"` so the fixture test runs with the other node tests:

```json
		"test": "npm run build && npm run test --workspaces --if-present && node --test ./scripts/browser-types.test.mjs ./scripts/spawn-recipe-package.test.mjs ./bench/agent-session/fixtures.test.mjs",
```

- [ ] **Step 11: Build, run the harness, record the feel baseline**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent -- --fixture claude-spinner-10s
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel -- --record --fixture claude-spinner-10s
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel -- --fixture claude-spinner-10s
```

Expected: `bench:agent` prints one JSON line with `spinner: { paints, addedNodes }` and `tearing: { frames, tornStates, tornPaints, multiPaintFrames }`; the second `bench:feel` prints `PASS feel gate: zero pixel diff`. If it does not pass twice in a row on an unchanged tree, the page is nondeterministic — find the cause (a timer-driven repaint, a font not yet loaded at the first screenshot) before continuing; add a `await page.evaluate(() => document.fonts.ready)` after `feedAll` if fonts are the cause.

- [ ] **Step 12: Fill the baseline table (spinner rows only)**

In the spec's "The table" (`docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`), replace "not known" in the row *paints/s and DOM nodes created per paint under the spinner* with the measured values as `<paints>/10 s → <paints/10> paints/s, <addedNodes/paints> nodes/paint` and add a row:

```
| torn frames in `claude-spinner-10s` | `run.mjs` `tearing`: model states that became visible inside a sync block (fed byte by byte), paints showing a partial frame and frames painted more than once (fed in thirds, one frame per third) | <tornStates> states / <tornPaints> paints / <multiPaintFrames> multi-paint of <frames> frames |
```

Leave every other "not known" for Task 2. Do not round to a nicer number; copy what the run printed.

- [ ] **Step 13: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/bench/agent-session packages/terminal/package.json docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md && git commit -m "bench: agent-session harness, feel gate and the claude-spinner-10s fixture

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

**Verification (TERMINAL.md §6, layers touched: TS bench only):**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && node --test ./bench/agent-session/fixtures.test.mjs
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
```

---

### Task 2: `OPERATOR_PTY_RECORD` in the pty-host and the long fixture

**Files:**
- Create: `backend/internal/adapters/runtime/ptyhost/record.go`
- Create: `backend/internal/adapters/runtime/ptyhost/record_test.go`
- Modify: `backend/internal/adapters/runtime/ptyhost/host.go` (`ServeConfig`, `host`, `deliver`, `applyLargestLocked`)
- Modify: `backend/internal/adapters/runtime/ptyhost/host_main.go` (read the env, open the recorder)
- Modify: `backend/internal/adapters/runtime/ptyhost/host_main_test.go` (`TestRecordEnvTeesOutputAndSizes`)
- Create: `backend/internal/adapters/runtime/ptyhost/vtwasm/agent_session_test.go` (reopen report)
- Modify: `RUN_APP_COMMANDS.md`
- Create: `packages/terminal/bench/agent-session/fixtures/claude-long-50k/{recording,size.json}`, `bench/agent-session/baselines/claude-long-50k/*.png`
- Modify: spec baseline table

**Interfaces:**
- Consumes: `deliver(batch)` and `applyLargestLocked()` in `host.go`; `ServeConfig`.
- Produces: `type recorder struct`, `openRecorder(dir, sessionID string) (*recorder, error)`, `(*recorder).write(batch []byte)`, `(*recorder).resize(cols, rows int)`, `(*recorder).close() error`; `ServeConfig.Recorder *recorder`; env `OPERATOR_PTY_RECORD`; `recordEnv = "OPERATOR_PTY_RECORD"`.

- [ ] **Step 1: Write the failing recorder tests**

`backend/internal/adapters/runtime/ptyhost/record_test.go`:

```go
package ptyhost

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestRecorderTeesBytesAndLogsSizesAtByteOffsets(t *testing.T) {
	dir := t.TempDir()
	rec, err := openRecorder(dir, "sess-1", 120, 40)
	if err != nil {
		t.Fatalf("openRecorder: %v", err)
	}
	rec.write([]byte("hello "))
	rec.resize(100, 30)
	rec.write([]byte("world"))
	if err := rec.close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	got, err := os.ReadFile(filepath.Join(dir, "sess-1.recording"))
	if err != nil {
		t.Fatalf("read recording: %v", err)
	}
	if string(got) != "hello world" {
		t.Fatalf("recording = %q, want %q", got, "hello world")
	}
	raw, err := os.ReadFile(filepath.Join(dir, "sess-1.size.json"))
	if err != nil {
		t.Fatalf("read size.json: %v", err)
	}
	var sizes []recordSize
	if err := json.Unmarshal(raw, &sizes); err != nil {
		t.Fatalf("size.json: %v\n%s", err, raw)
	}
	want := []recordSize{{Offset: 0, Cols: 120, Rows: 40}, {Offset: 6, Cols: 100, Rows: 30}}
	if len(sizes) != len(want) {
		t.Fatalf("sizes = %+v, want %+v", sizes, want)
	}
	for i := range want {
		if sizes[i] != want[i] {
			t.Fatalf("sizes[%d] = %+v, want %+v", i, sizes[i], want[i])
		}
	}
}

func TestRecorderIgnoresARedundantResize(t *testing.T) {
	dir := t.TempDir()
	rec, err := openRecorder(dir, "sess-2", 80, 24)
	if err != nil {
		t.Fatalf("openRecorder: %v", err)
	}
	rec.resize(80, 24)
	_ = rec.close()
	raw, _ := os.ReadFile(filepath.Join(dir, "sess-2.size.json"))
	var sizes []recordSize
	_ = json.Unmarshal(raw, &sizes)
	if len(sizes) != 1 {
		t.Fatalf("sizes = %+v, want the birth entry only", sizes)
	}
}

func TestNilRecorderIsANoOp(t *testing.T) {
	var rec *recorder
	rec.write([]byte("x"))
	rec.resize(1, 1)
	if err := rec.close(); err != nil {
		t.Fatalf("close: %v", err)
	}
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/ -run 'TestRecorder|TestNilRecorder' 2>&1 | head`
Expected: FAIL to compile — `undefined: openRecorder`, `undefined: recordSize`.

- [ ] **Step 3: Write `record.go`**

```go
package ptyhost

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

const recordEnv = "OPERATOR_PTY_RECORD"

type recordSize struct {
	Offset int64 `json:"offset"`
	Cols   int   `json:"cols"`
	Rows   int   `json:"rows"`
}

type recorder struct {
	mu        sync.Mutex
	recording *os.File
	sizesPath string
	sizes     []recordSize
	written   int64
	err       error
}

func openRecorder(dir, sessionID string, cols, rows int) (*recorder, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	recording, err := os.OpenFile(filepath.Join(dir, sessionID+".recording"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return nil, err
	}
	r := &recorder{
		recording: recording,
		sizesPath: filepath.Join(dir, sessionID+".size.json"),
		sizes:     []recordSize{{Offset: 0, Cols: cols, Rows: rows}},
	}
	r.writeSizesLocked()
	return r, nil
}

func (r *recorder) write(batch []byte) {
	if r == nil || len(batch) == 0 {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.err != nil {
		return
	}
	n, err := r.recording.Write(batch)
	r.written += int64(n)
	if err != nil {
		r.err = err
	}
}

func (r *recorder) resize(cols, rows int) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	last := r.sizes[len(r.sizes)-1]
	if last.Cols == cols && last.Rows == rows {
		return
	}
	r.sizes = append(r.sizes, recordSize{Offset: r.written, Cols: cols, Rows: rows})
	r.writeSizesLocked()
}

func (r *recorder) writeSizesLocked() {
	data, err := json.Marshal(r.sizes)
	if err != nil {
		r.err = err
		return
	}
	if err := os.WriteFile(r.sizesPath, data, 0o600); err != nil {
		r.err = err
	}
}

func (r *recorder) close() error {
	if r == nil {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if err := r.recording.Close(); err != nil && r.err == nil {
		r.err = err
	}
	return r.err
}
```

- [ ] **Step 4: Run the recorder tests to see them pass**

Run: `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/ -run 'TestRecorder|TestNilRecorder' -v`
Expected: PASS ×3.

- [ ] **Step 5: Write the failing host-level test**

Append to `host_main_test.go`:

```go
func TestRecordEnvTeesOutputAndSizes(t *testing.T) {
	dir := t.TempDir()
	t.Setenv(recordEnv, dir)
	rec := recorderFromEnv("sess-rec", 80, 24)
	if rec == nil {
		t.Fatal("recorderFromEnv returned nil with the env set")
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	pty := newFakePTY(300)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- Serve(ctx, ServeConfig{SessionID: "sess-rec", Listener: ln, PTY: pty, Ring: NewRing(), Recorder: rec})
	}()
	c := newTestClient(t, ln.Addr().String())
	syncClientRegistered(t, c)
	if _, err := pty.WriteOutput([]byte("first\r\n")); err != nil {
		t.Fatalf("write: %v", err)
	}
	c.readFrame(t)
	waitFor(t, 2*time.Second, func() bool {
		info, err := os.Stat(filepath.Join(dir, "sess-rec.recording"))
		return err == nil && info.Size() == 7
	})
	payload, _ := json.Marshal(ResizePayload{Cols: 100, Rows: 30})
	if err := c.send(MsgResize, payload); err != nil {
		t.Fatalf("resize: %v", err)
	}
	pty.waitResizes(t, 1)
	if _, err := pty.WriteOutput([]byte("second\r\n")); err != nil {
		t.Fatalf("write: %v", err)
	}
	c.readFrame(t)
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Serve did not return")
	}
	c.close()

	got, err := os.ReadFile(filepath.Join(dir, "sess-rec.recording"))
	if err != nil {
		t.Fatalf("read recording: %v", err)
	}
	if string(got) != "first\r\nsecond\r\n" {
		t.Fatalf("recording = %q", got)
	}
	raw, _ := os.ReadFile(filepath.Join(dir, "sess-rec.size.json"))
	var sizes []recordSize
	if err := json.Unmarshal(raw, &sizes); err != nil {
		t.Fatalf("size.json: %v", err)
	}
	if len(sizes) != 2 || sizes[1] != (recordSize{Offset: 7, Cols: 100, Rows: 30}) {
		t.Fatalf("sizes = %+v", sizes)
	}
}

func TestRecorderFromEnvIsNilWhenUnset(t *testing.T) {
	t.Setenv(recordEnv, "")
	if rec := recorderFromEnv("sess-none", 80, 24); rec != nil {
		t.Fatal("expected no recorder without the env")
	}
}
```

Add `"context"`, `"encoding/json"`, `"net"`, `"os"`, `"time"` to that file's imports. `waitFor` is `pump_test.go`'s helper (same package); the recorder writes after `deliver` releases the lock, so the test waits for the bytes to land before it resizes.

- [ ] **Step 6: Run to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/ -run 'TestRecordEnv|TestRecorderFromEnv' 2>&1 | head`
Expected: FAIL to compile — `undefined: recorderFromEnv`, `unknown field Recorder`.

- [ ] **Step 7: Wire the recorder into the host**

`host.go` — add to `ServeConfig` after `InitialRows int`:

```go
	Recorder    *recorder
```

Add to the `host` struct after `capture *captureSink`:

```go
	recorder *recorder
```

In `Serve`, add `recorder: cfg.Recorder,` to the `&host{...}` literal. In `deliver`, after `h.capture.write(batch)` (line 489, off the lock):

```go
	h.recorder.write(batch)
```

In `applyLargestLocked`, after the parser resize (line 292):

```go
	h.recorder.resize(bestCols, bestRows)
```

In `Shutdown` (the `shutdownOnce.Do` body), before `_ = h.cfg.Listener.Close()`:

```go
		_ = h.recorder.close()
```

`host_main.go` — add:

```go
func recorderFromEnv(sessionID string, cols, rows int) *recorder {
	dir := os.Getenv(recordEnv)
	if dir == "" {
		return nil
	}
	rec, err := openRecorder(dir, sessionID, cols, rows)
	if err != nil {
		fmt.Fprintf(os.Stderr, "pty-host [%s]: %s: %v\n", sessionID, recordEnv, err)
		return nil
	}
	return rec
}
```

and in `RunHost` set `Recorder: recorderFromEnv(sessionID, parsed.cols, parsed.rows),` in the `ServeConfig` literal (after `InitialRows`).

- [ ] **Step 8: Run the Go tests**

Run: `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...`
Expected: PASS, except the pre-existing `TestProcessEnvironmentLetsOverridesWin` (`TERMINAL.md` §5) if it still fails on `development`; nothing else may fail.

- [ ] **Step 9: Document the switch**

In `RUN_APP_COMMANDS.md`, under "## Backend on its own" after the daemon command, add:

```markdown
To record every session's raw pty bytes (for `packages/terminal/bench/agent-session`
fixtures and `crates/vt-core/tests/ref`), start the daemon with
`OPERATOR_PTY_RECORD=<dir>`; each pty-host writes `<dir>/<session-id>.recording` and
`<dir>/<session-id>.size.json` (`[{offset, cols, rows}, …]`, one entry per grid change).
The variable reaches the pty-host through the daemon's environment, so it works for
`npm run tauri:dev` too.
```

- [ ] **Step 10: Commit the recorder**

```bash
cd /Users/omaraly/development/AI/Operator && git add backend/internal/adapters/runtime/ptyhost RUN_APP_COMMANDS.md && git commit -m "ptyhost: OPERATOR_PTY_RECORD tees raw pty output and grid changes per session

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 11: Rebuild the daemon and record `claude-long-50k`**

```bash
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```

Restart the daemon and the app. Then launch the dev shell with the recording switch, scrubbing `CLAUDE*` (memory `scrub-claude-env-before-running-operator-dev`):

```bash
cd /Users/omaraly/development/AI/Operator/frontend && mkdir -p /tmp/operator-recordings && env $(env | grep -o '^CLAUDE[A-Z_0-9]*=' | sed 's/=$//; s/^/-u /') -u OPERATOR_DATA_DIR -u OPERATOR_RUN_FILE -u OPERATOR_PORT OPERATOR_PTY_RECORD=/tmp/operator-recordings npm run tauri:dev
```

Open a Claude Code session in a scratch project at a 120×40 pane. Produce ≥ 50,000 rows of real output: assistant text prints in full (tool results collapse), so prompts like "Print the numbers 1 to 3000, one per line, no commentary" repeated, or a long real working session, both count. Check the row count as you go:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && node -e '
const fs = require("node:fs");
const path = require("node:path");
const dir = "/tmp/operator-recordings";
for (const file of fs.readdirSync(dir).filter((f) => f.endsWith(".recording"))) {
	const bytes = fs.readFileSync(path.join(dir, file));
	const rows = bytes.toString("latin1").split("\r\n").length;
	console.log(file, bytes.length, "bytes, ~", rows, "CRLF rows");
}'
```

The CRLF count is an upper bound; the harness's `rowCount()` is the truth. When done, copy the pair into the fixture:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && mkdir -p bench/agent-session/fixtures/claude-long-50k && cp /tmp/operator-recordings/<session-id>.recording bench/agent-session/fixtures/claude-long-50k/recording && cp /tmp/operator-recordings/<session-id>.size.json bench/agent-session/fixtures/claude-long-50k/size.json
```

Then confirm with the harness: `npm run bench:agent -- --fixture claude-long-50k` must print `rows >= 50000`. Scan the recording for secrets before committing; if the scratch project's paths or any token appear, re-record in a fresh scratch directory.

- [ ] **Step 12: The reopen report (Go)**

`backend/internal/adapters/runtime/ptyhost/vtwasm/agent_session_test.go`:

```go
package vtwasm

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestAgentSessionReplayReport(t *testing.T) {
	fixture := os.Getenv("OPERATOR_AGENT_FIXTURE")
	if fixture == "" {
		t.Skip("set OPERATOR_AGENT_FIXTURE to a fixture directory")
	}
	recording, err := os.ReadFile(filepath.Join(fixture, "recording"))
	if err != nil {
		t.Fatalf("read recording: %v", err)
	}
	raw, err := os.ReadFile(filepath.Join(fixture, "size.json"))
	if err != nil {
		t.Fatalf("read size.json: %v", err)
	}
	var sizes []struct {
		Offset int `json:"offset"`
		Cols   uint32
		Rows   uint32
	}
	if err := json.Unmarshal(raw, &sizes); err != nil {
		t.Fatalf("size.json: %v", err)
	}
	p, err := New(context.Background(), Module, sizes[0].Cols, sizes[0].Rows, 1000)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	defer p.Close()
	next := 1
	for offset := 0; offset < len(recording); {
		end := min(offset+64<<10, len(recording))
		if next < len(sizes) && sizes[next].Offset < end {
			end = sizes[next].Offset
		}
		if end > offset {
			if err := p.Feed(recording[offset:end]); err != nil {
				t.Fatalf("feed: %v", err)
			}
			offset = end
		}
		if next < len(sizes) && sizes[next].Offset == offset {
			if err := p.Resize(sizes[next].Cols, sizes[next].Rows); err != nil {
				t.Fatalf("resize: %v", err)
			}
			next++
		}
	}
	start := time.Now()
	replay, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	elapsed := time.Since(start)
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	report := map[string]any{
		"replayBytes":      len(replay),
		"replayRows":       strings.Count(replay, "\r\n") + 1,
		"replayRenderMs":   float64(elapsed.Microseconds()) / 1000,
		"mirrorWasmBytes":  p.module.Memory().Size(),
		"goHeapAllocBytes": stats.HeapAlloc,
	}
	if out := os.Getenv("OPERATOR_AGENT_REPLAY_OUT"); out != "" {
		if err := os.WriteFile(out, []byte(replay), 0o600); err != nil {
			t.Fatalf("write replay: %v", err)
		}
	}
	encoded, _ := json.Marshal(report)
	t.Logf("REPORT %s", encoded)
}
```

Extend `run.mjs` (Task 1) so the non-spinner branch also runs it and feeds the replay into the page for the "time to first paint" number. Add the imports `import { spawnSync } from "node:child_process";` and `import { readFile } from "node:fs/promises";`, and this function:

```js
async function reopenReport(page, fixtureName) {
	const fixtureDir = path.join(benchDir, "agent-session", "fixtures", fixtureName);
	const replayOut = path.join(resultsDir, `${fixtureName}-replay.bin`);
	await mkdir(resultsDir, { recursive: true });
	const backend = path.resolve(benchDir, "../../../backend");
	const run = spawnSync("go", ["test", "./internal/adapters/runtime/ptyhost/vtwasm/", "-run", "TestAgentSessionReplayReport", "-v", "-count=1"], {
		cwd: backend,
		env: { ...process.env, OPERATOR_AGENT_FIXTURE: fixtureDir, OPERATOR_AGENT_REPLAY_OUT: replayOut },
		encoding: "utf8",
	});
	const line = run.stdout.split("\n").find((entry) => entry.includes("REPORT "));
	if (!line) throw new Error(`reopen report missing:\n${run.stdout}\n${run.stderr}`);
	const report = JSON.parse(line.slice(line.indexOf("REPORT ") + 7));
	const replay = new Uint8Array(await readFile(replayOut));
	const firstPaintMs = await page.evaluate(async (bytes) => {
		const session = window.__agentSession;
		const start = performance.now();
		session.resetCounters();
		session.core().feed(new Uint8Array(bytes));
		while (session.paintCount() === 0) await new Promise((resolve) => requestAnimationFrame(resolve));
		return performance.now() - start;
	}, Array.from(replay));
	return { ...report, firstPaintMs };
}
```

Call it in `main()`'s non-spinner branch on a *fresh* page (a reopen starts from an empty core): after `rows.rendererMemoryBytes = ...; await page.close();` add:

```js
				const reopenPage = await openPage(browser, port, name);
				rows.reopen = await reopenReport(reopenPage, name);
				await reopenPage.close();
```

- [ ] **Step 13: Measure, record baselines, fill the table**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent -- --fixture claude-long-50k
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent:scroll -- --fixture claude-long-50k
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel -- --record --fixture claude-long-50k
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
```

Fill the spec table's remaining "Today" cells from the printed JSON: `feed()` cost at 1k / 5k / 50k (`feedCost[*].medianMs`; if `reached < rows` for 50k, write the reached count and its number), main-thread block for 2 MB (`longTask.feedMs` and `longestTaskMs`), scroll (`framesOver50ms`, `worstFrameMs`, `covered/total`), reopen (`replayRows`, `replayBytes`, `firstPaintMs`, `replayRenderMs`), memory (`rendererMemoryBytes`, `mirrorWasmBytes`). The reopen row measures at the mirror's 1,000-row cap; write the cap next to the numbers as the spec's row already does.

- [ ] **Step 14: Commit the fixture, baselines and table**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/bench/agent-session backend/internal/adapters/runtime/ptyhost/vtwasm/agent_session_test.go docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md && git commit -m "bench: claude-long-50k fixture, reopen report and the measured baseline

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

**Verification (layers touched: Go host, daemon, bench):**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
```

Restart the daemon and the app (the pty-host binary changed).

---

### Task 3: `tests/ref.rs` harness and the Alacritty corpus

**Files:**
- Create: `packages/terminal/crates/vt-core/tests/ref.rs`
- Create: `packages/terminal/crates/vt-core/tests/ref/<name>/{recording,size.json,screen.txt,cursor.json}` for the 45 Alacritty recordings plus `claude_spinner_10s`
- Create: `packages/terminal/crates/vt-core/tests/ref/ALACRITTY-ATTRIBUTION.md`, `tests/ref/LICENSE-APACHE`, `tests/ref/LICENSE-MIT` (copied from `/Users/omaraly/development/AI/alacritty/`)
- Create: `packages/terminal/crates/vt-core/tests/ref/TRIAGE.md`
- Create: `packages/terminal/tools/import-alacritty-ref.py`
- Create: `packages/terminal/tools/alacritty-grid-text.py`

**Interfaces:**
- Consumes: `TerminalCore::new(cols, rows_cap)`, `resize`, `feed`, `snapshot().row_text(i)`, `snapshot().cursor_row/cursor_col/cursor_visible`.
- Produces: `ref_tests! { … }` macro in `tests/ref.rs`; `REF_SCROLLBACK_ROWS: usize = 200_000`; env `UPDATE_REF=1` regenerates expectations; the corpus layout above; `TRIAGE.md` with one line per directory.

Reference: `alacritty_terminal/tests/ref.rs:16-27` (macro) and `:94-130` (replay + first-difference report); Warp `app/src/terminal/ref_tests/mod.rs:1-2,25` (the same harness over a block model — Warp starts a background block so marks are not required; our markless rows form a synthetic block by themselves, so no such step is needed).

- [ ] **Step 1: Write `tests/ref.rs` with one entry so it fails for want of the directory**

```rust
use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use vt_core::TerminalCore;

const REF_SCROLLBACK_ROWS: usize = 200_000;

#[derive(Deserialize, Clone, Copy)]
struct SizeEntry {
    offset: usize,
    cols: usize,
    rows: usize,
}

#[derive(Deserialize, serde::Serialize, PartialEq, Eq, Debug)]
struct CursorExpectation {
    row: u32,
    col: u32,
    visible: bool,
}

macro_rules! ref_tests {
    ($($name:ident)*) => {
        $(
            #[test]
            fn $name() {
                let dir = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/ref")).join(stringify!($name));
                ref_test(&dir);
            }
        )*
    };
}

ref_tests! {
    sgr
}

fn replay(dir: &Path) -> TerminalCore {
    let recording = fs::read(dir.join("recording")).expect("recording");
    let sizes: Vec<SizeEntry> =
        serde_json::from_str(&fs::read_to_string(dir.join("size.json")).expect("size.json"))
            .expect("size.json is a JSON array of {offset, cols, rows}");
    let first = sizes.first().expect("size.json has at least one entry");
    assert_eq!(first.offset, 0, "the first size entry starts at offset 0");
    let mut core = TerminalCore::new(first.cols, REF_SCROLLBACK_ROWS).expect("core");
    core.resize(first.cols, first.rows);
    let mut fed = 0usize;
    for size in sizes.iter().skip(1) {
        let upto = size.offset.min(recording.len());
        if upto > fed {
            core.feed(&recording[fed..upto]);
            fed = upto;
        }
        core.resize(size.cols, size.rows);
    }
    if fed < recording.len() {
        core.feed(&recording[fed..]);
    }
    core
}

fn render(core: &TerminalCore) -> (String, CursorExpectation) {
    let snapshot = core.snapshot().expect("snapshot");
    let mut screen = String::new();
    for index in 0..snapshot.row_count() {
        for _ in 0..snapshot.row_indent(index) {
            screen.push(' ');
        }
        screen.push_str(snapshot.row_text(index));
        screen.push('\n');
    }
    let cursor = CursorExpectation {
        row: snapshot.cursor_row,
        col: snapshot.cursor_col,
        visible: snapshot.cursor_visible,
    };
    (screen, cursor)
}

fn ref_test(dir: &Path) {
    let core = replay(dir);
    let (screen, cursor) = render(&core);
    let screen_path: PathBuf = dir.join("screen.txt");
    let cursor_path: PathBuf = dir.join("cursor.json");
    if std::env::var_os("UPDATE_REF").is_some() {
        fs::write(&screen_path, &screen).expect("write screen.txt");
        fs::write(&cursor_path, serde_json::to_string(&cursor).unwrap()).expect("write cursor.json");
        return;
    }
    let expected_screen = fs::read_to_string(&screen_path).expect("screen.txt (run with UPDATE_REF=1 to create)");
    let expected_cursor: CursorExpectation =
        serde_json::from_str(&fs::read_to_string(&cursor_path).expect("cursor.json")).expect("cursor.json");
    if screen != expected_screen {
        let got: Vec<&str> = screen.lines().collect();
        let want: Vec<&str> = expected_screen.lines().collect();
        let mut reported = 0;
        for index in 0..got.len().max(want.len()) {
            let g = got.get(index).copied().unwrap_or("<missing>");
            let w = want.get(index).copied().unwrap_or("<missing>");
            if g != w {
                eprintln!("row {index}\n  want: {w:?}\n  got:  {g:?}");
                reported += 1;
                if reported == 10 {
                    break;
                }
            }
        }
        panic!("{} rows differ from screen.txt ({} got, {} want)", reported, got.len(), want.len());
    }
    assert_eq!(cursor, expected_cursor, "cursor differs from cursor.json");
}
```

`serde` with `derive` and `serde_json` are already dev-dependencies of `vt-core` (`crates/vt-core/Cargo.toml`).

- [ ] **Step 2: Run it to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test ref`
Expected: FAIL — `sgr` panics reading `tests/ref/sgr/recording` (No such file).

- [ ] **Step 3: Write the import script**

`packages/terminal/tools/import-alacritty-ref.py`:

```python
#!/usr/bin/env python3
import json
import os
import shutil
import sys

SOURCE = "/Users/omaraly/development/AI/alacritty/alacritty_terminal/tests/ref"
TARGET = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "crates", "vt-core", "tests", "ref")


def main():
    names = sorted(entry for entry in os.listdir(SOURCE) if os.path.isdir(os.path.join(SOURCE, entry)))
    for name in names:
        src = os.path.join(SOURCE, name)
        dst = os.path.join(TARGET, name)
        os.makedirs(dst, exist_ok=True)
        shutil.copyfile(os.path.join(src, "alacritty.recording"), os.path.join(dst, "recording"))
        with open(os.path.join(src, "size.json")) as handle:
            size = json.load(handle)
        with open(os.path.join(dst, "size.json"), "w") as handle:
            json.dump([{"offset": 0, "cols": size["columns"], "rows": size["screen_lines"]}], handle)
    print("\n".join(names))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Run it and copy the licences and write the attribution:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && python3 tools/import-alacritty-ref.py
cp /Users/omaraly/development/AI/alacritty/LICENSE-APACHE /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/tests/ref/LICENSE-APACHE
cp /Users/omaraly/development/AI/alacritty/LICENSE-MIT /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/tests/ref/LICENSE-MIT
```

`crates/vt-core/tests/ref/ALACRITTY-ATTRIBUTION.md`:

```markdown
# Reference recordings

The 45 `recording` files listed below are `alacritty.recording` from
`alacritty_terminal/tests/ref/<name>/` in Alacritty
(https://github.com/alacritty/alacritty, commit `d692748d`), used under the
Apache-2.0 / MIT dual licence (`LICENSE-APACHE`, `LICENSE-MIT` beside this file).
Only the byte streams are imported; every `size.json` is rewritten into this
crate's `[{offset, cols, rows}]` layout and every `screen.txt` / `cursor.json`
is generated from `vt-core` (`UPDATE_REF=1 cargo test -p vt-core --test ref`),
so the expectations are this model's, not Alacritty's. `TRIAGE.md` records where
the two differ and why.

`claude_spinner_10s` is this repository's own recording
(`packages/terminal/bench/agent-session/fixtures/claude-spinner-10s`).
```

Copy the spinner fixture in as a corpus entry too:

```bash
mkdir -p /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/tests/ref/claude_spinner_10s && cp /Users/omaraly/development/AI/Operator/packages/terminal/bench/agent-session/fixtures/claude-spinner-10s/recording /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/tests/ref/claude_spinner_10s/recording && cp /Users/omaraly/development/AI/Operator/packages/terminal/bench/agent-session/fixtures/claude-spinner-10s/size.json /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/tests/ref/claude_spinner_10s/size.json
```

- [ ] **Step 4: List every directory in the macro and generate expectations**

Replace the `ref_tests! { sgr }` invocation with all 46 names (the 45 printed by the import script, in that order, plus `claude_spinner_10s`):

```rust
ref_tests! {
    alt_reset
    clear_underline
    colored_reset
    colored_underline
    csi_rep
    decaln_reset
    deccolm_reset
    delete_chars_reset
    delete_lines
    erase_chars_reset
    erase_in_line
    fish_cc
    grid_reset
    history
    hyperlinks
    indexed_256_colors
    insert_blank_reset
    issue_855
    ll
    newline_with_cursor_beyond_scroll_region
    origin_goto
    region_scroll_down
    row_reset
    saved_cursor
    saved_cursor_alt
    scroll_in_region_up_preserves_history
    scroll_up_reset
    selective_erasure
    sgr
    tab_rendering
    tmux_git_log
    tmux_htop
    underline
    vim_24bitcolors_bce
    vim_large_window_scroll
    vim_simple_edit
    vttest_cursor_movement_1
    vttest_insert
    vttest_origin_mode_1
    vttest_origin_mode_2
    vttest_scroll
    vttest_tab_clear_set
    wrapline_alt_toggle
    zerowidth
    zsh_tab_completion
    claude_spinner_10s
}
```

Generate, then run for real:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && UPDATE_REF=1 cargo test -p vt-core --test ref
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test ref
```

Expected: the first run passes (it only writes); the second passes with 46 tests. A panic in the first run (a recording that crashes `vt-core`) is a real finding: keep the test in the list, mark it `#[ignore]` by splitting it out of the macro into its own `#[test] #[ignore = "…"] fn` with the panic message, add a `TERMINAL.md` §5 entry, and continue — do not fix the parser in this task.

- [ ] **Step 5: Triage against Alacritty's grid**

`packages/terminal/tools/alacritty-grid-text.py` renders Alacritty's `grid.json` as text (top of history to bottom of screen) so the executor can compare the visible screen by eye:

```python
#!/usr/bin/env python3
import json
import sys


def main():
    if len(sys.argv) != 2:
        print("usage: alacritty-grid-text.py <ref dir>", file=sys.stderr)
        return 2
    with open(f"{sys.argv[1]}/grid.json") as handle:
        grid = json.load(handle)
    raw = grid["raw"]
    assert raw["zero"] == 0, "grid.json is serialised after truncate(); zero must be 0"
    rows = []
    for line in reversed(raw["inner"]):
        text = "".join(cell["c"] for cell in line["inner"] if "WIDE_CHAR_SPACER" not in (cell.get("flags") or ""))
        rows.append(text.rstrip())
    print("\n".join(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

(`Storage::compute_index`, `alacritty_terminal/src/grid/storage.rs:220-234`: after `truncate()` the buffer is stored bottom-up, so reversing `inner` yields oldest history first, then the screen top to bottom.)

For each of the 45 directories compare the last `rows` lines of our `screen.txt` with the last `rows` lines of the script's output:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && for d in crates/vt-core/tests/ref/*/; do n=$(basename $d); [ -f /Users/omaraly/development/AI/alacritty/alacritty_terminal/tests/ref/$n/grid.json ] || continue; rows=$(python3 -c "import json;print(json.load(open('$d/size.json'))[0]['rows'])"); python3 tools/alacritty-grid-text.py /Users/omaraly/development/AI/alacritty/alacritty_terminal/tests/ref/$n | tail -n $rows | sed 's/[[:space:]]*$//' > /tmp/ref-$n.alacritty; tail -n $rows $d/screen.txt | sed 's/[[:space:]]*$//' > /tmp/ref-$n.ours; if diff -q /tmp/ref-$n.alacritty /tmp/ref-$n.ours >/dev/null; then echo "$n: match"; else echo "$n: DIFFERS ($(diff /tmp/ref-$n.alacritty /tmp/ref-$n.ours | grep -c '^[<>]') lines)"; fi; done
```

Write `crates/vt-core/tests/ref/TRIAGE.md` with one line per directory in this exact shape, filled from what you see (no guessing — a difference you cannot explain after reading the bytes is written as "not triaged: <what differs>"):

```markdown
# Triage of the Alacritty corpus against vt-core (2026-09-XX)

Categories: **match** (visible screen identical), **model** (a deliberate
difference of this model — blank-row commits, rewrap, no scroll-region history,
tabs rendered as spaces), **parser** (a vt-core dispatch gap; not fixed here,
listed for a follow-up), **upstream** (the recording itself exercises behaviour
Alacritty defines differently from xterm).

| dir | category | note |
|---|---|---|
| alt_reset | … | … |
```

A `parser` category is a bug list, not a fix: add each one as a `TERMINAL.md` §5 "Known gaps" bullet naming the corpus directory.

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-core/tests/ref.rs packages/terminal/crates/vt-core/tests/ref packages/terminal/tools TERMINAL.md && git commit -m "vt-core: reference-recording corpus (Alacritty's 45 plus claude-spinner-10s) with a ref_tests! harness

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

**Verification (layers touched: Rust tests only):**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
```

---

### Task 4: Integrity checker, dispatch trace, property test

**Files:**
- Create: `packages/terminal/crates/vt-core/src/integrity.rs`
- Create: `packages/terminal/crates/vt-core/src/trace.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs` (module, re-export, debug checks, trace API, per-byte advance under the feature)
- Modify: `packages/terminal/crates/vt-core/src/parser.rs` (trace hooks in `Perform`, `osc_dispatch`)
- Modify: `packages/terminal/crates/vt-core/src/content.rs` (`start_offset`)
- Modify: `packages/terminal/crates/vt-core/src/attribute_map.rs` (`keys`)
- Modify: `packages/terminal/crates/vt-core/src/row_index.rs` (`open_start` without `cfg(test)`, `completed_mut` for tests)
- Modify: `packages/terminal/crates/vt-core/Cargo.toml` (`[features] trace = []`, `proptest` dev-dependency)
- Create: `packages/terminal/crates/vt-core/tests/common/mod.rs`
- Create: `packages/terminal/crates/vt-core/tests/integrity.rs`

**Interfaces:**
- Consumes: `Parser` internals (`content`, `rows`, `styles`, `grid`, `screen`), `BlockGrid::blocks()/next_row()`, `RowIndex::completed()`.
- Produces: `pub enum IntegrityError { RowOutsideContent { row: usize }, RowsNotContiguous { row: usize }, OpenRowDetached, WrappedRowEmpty { row: usize }, BlockPastEnd { block: usize }, NextRowPastEnd, StyleKeyOutsideContent { offset: u64 } }`; `Parser::verify_integrity(&self) -> Result<(), IntegrityError>` (`pub(crate)`); `TerminalCore::verify_integrity(&self) -> Result<(), IntegrityError>`; under `feature = "trace"`: `pub struct TraceEntry { pub offset: u64, pub action: TraceAction }`, `pub enum TraceAction { Print(char), Execute(u8), Csi { params: Vec<Vec<u16>>, intermediates: Vec<u8>, action: char }, Esc { intermediates: Vec<u8>, byte: u8 }, Osc(Vec<Vec<u8>>) }`, `TerminalCore::trace(&self) -> &[TraceEntry]`, `TerminalCore::clear_trace(&mut self)`; `tests/common/mod.rs::check(&TerminalCore)`; a private `TerminalCore::advance_vte(&mut self, bytes: &[u8])` that Task 5 reuses.

Reference: Ghostty `src/terminal/PageList.zig:796-930` (`verifyIntegrity` after every mutation in debug builds); Kitty `vt-parser.c` `REPORT_COMMAND` (survey §5.10) for the trace.

- [ ] **Step 1: Write the failing integration tests**

`crates/vt-core/tests/common/mod.rs`:

```rust
use vt_core::TerminalCore;

pub fn check(core: &TerminalCore) {
    if let Err(error) = core.verify_integrity() {
        panic!("integrity violated: {error:?}");
    }
    core.snapshot().expect("snapshot builds");
}
```

`crates/vt-core/tests/integrity.rs`:

```rust
mod common;

use proptest::prelude::*;
use vt_core::TerminalCore;

#[derive(Debug, Clone)]
enum Op {
    Print(String),
    Newline,
    Sgr(u8),
    Cup(u8, u8),
    Ed(u8),
    El(u8),
    Il(u8),
    Dl(u8),
    Resize(u8, u8),
    PromptStart,
    CommandStart,
    OutputStart,
    CommandEnd(u8),
    Boundary,
}

fn op() -> impl Strategy<Value = Op> {
    prop_oneof![
        4 => "[ -~]{0,40}".prop_map(Op::Print),
        3 => Just(Op::Newline),
        1 => (0u8..=107).prop_map(Op::Sgr),
        1 => ((1u8..=30), (1u8..=100)).prop_map(|(r, c)| Op::Cup(r, c)),
        1 => (0u8..=2).prop_map(Op::Ed),
        1 => (0u8..=2).prop_map(Op::El),
        1 => (1u8..=5).prop_map(Op::Il),
        1 => (1u8..=5).prop_map(Op::Dl),
        1 => ((4u8..=60), (2u8..=20)).prop_map(|(c, r)| Op::Resize(c, r)),
        1 => Just(Op::PromptStart),
        1 => Just(Op::CommandStart),
        1 => Just(Op::OutputStart),
        1 => (0u8..=2).prop_map(Op::CommandEnd),
        1 => Just(Op::Boundary),
    ]
}

fn apply(core: &mut TerminalCore, op: &Op) {
    match op {
        Op::Print(text) => core.feed(text.as_bytes()),
        Op::Newline => core.feed(b"\r\n"),
        Op::Sgr(n) => core.feed(format!("\x1b[{n}m").as_bytes()),
        Op::Cup(r, c) => core.feed(format!("\x1b[{r};{c}H").as_bytes()),
        Op::Ed(n) => core.feed(format!("\x1b[{n}J").as_bytes()),
        Op::El(n) => core.feed(format!("\x1b[{n}K").as_bytes()),
        Op::Il(n) => core.feed(format!("\x1b[{n}L").as_bytes()),
        Op::Dl(n) => core.feed(format!("\x1b[{n}M").as_bytes()),
        Op::Resize(c, r) => core.resize(usize::from(*c), usize::from(*r)),
        Op::PromptStart => core.feed(b"\x1b]133;A\x07"),
        Op::CommandStart => core.feed(b"\x1b]133;B\x07"),
        Op::OutputStart => core.feed(b"\x1b]133;C\x07"),
        Op::CommandEnd(n) => core.feed(format!("\x1b]133;D;{n}\x07").as_bytes()),
        Op::Boundary => core.feed(b"\x1b]7000;v=1;boundary=0\x07"),
    }
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 256, ..ProptestConfig::default() })]

    #[test]
    fn every_operation_leaves_the_model_consistent(
        agent_tui in any::<bool>(),
        ops in prop::collection::vec(op(), 1..80),
    ) {
        let mut core = TerminalCore::new(40, 32).unwrap();
        core.resize(40, 8);
        core.set_agent_tui_mode(agent_tui);
        common::check(&core);
        for op in &ops {
            apply(&mut core, op);
            common::check(&core);
        }
    }
}

#[test]
fn a_fresh_core_is_consistent() {
    let core = TerminalCore::new(80, 100).unwrap();
    common::check(&core);
}

#[test]
fn a_trimmed_core_is_consistent() {
    let mut core = TerminalCore::new(20, 4).unwrap();
    core.resize(20, 2);
    for index in 0..50 {
        core.feed(format!("row {index}\r\n").as_bytes());
        common::check(&core);
    }
}

#[test]
fn a_rewrapped_core_is_consistent() {
    let mut core = TerminalCore::new(40, 100).unwrap();
    core.resize(40, 3);
    core.feed(b"- a bullet line that is long enough to need wrapping when narrow\r\nplain\r\n");
    for cols in [12usize, 8, 30, 60] {
        core.resize(cols, 3);
        common::check(&core);
    }
}
```

- [ ] **Step 2: Add the dev-dependency and run to see it fail**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo add proptest@1 --dev -p vt-core
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test integrity 2>&1 | head -20
```

Expected: FAIL to compile — `no method named verify_integrity found for struct TerminalCore`.

- [ ] **Step 3: Write the unit tests that pin each invariant with a corrupted model**

Append to `crates/vt-core/src/integrity.rs` (the file is created in Step 4; write the test module now so the file's shape is fixed):

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::block::BlockState;
    use crate::parser::Parser;
    use crate::row_index::RowRange;
    use vte::Parser as VteParser;

    fn parser_with(text: &[u8]) -> Parser {
        let mut parser = Parser::new(20, 100);
        let mut vte = VteParser::new();
        vte.advance(&mut parser, text);
        parser.commit_evicted();
        parser
    }

    #[test]
    fn a_healthy_parser_passes() {
        let parser = parser_with(b"one\r\ntwo\r\nthree\r\n");
        assert_eq!(parser.verify_integrity(), Ok(()));
    }

    #[test]
    fn a_row_past_the_content_end_is_reported() {
        let mut parser = parser_with(b"one\r\ntwo\r\n");
        let end = parser.content().end_offset();
        parser.rows_mut().completed_mut()[1].end = end + 5;
        assert_eq!(parser.verify_integrity(), Err(IntegrityError::RowOutsideContent { row: 1 }));
    }

    #[test]
    fn a_gap_between_rows_is_reported() {
        let mut parser = parser_with(b"one\r\ntwo\r\n");
        parser.rows_mut().completed_mut()[1].start += 1;
        assert_eq!(parser.verify_integrity(), Err(IntegrityError::RowsNotContiguous { row: 0 }));
    }

    #[test]
    fn a_wrapped_row_with_no_bytes_is_reported() {
        let mut parser = parser_with(b"one\r\n");
        let end = parser.content().end_offset();
        parser.rows_mut().completed_mut().push_back(RowRange { start: end, end, wrapped: true, indent: 0 });
        assert_eq!(parser.verify_integrity(), Err(IntegrityError::WrappedRowEmpty { row: 1 }));
    }

    #[test]
    fn a_block_that_starts_above_the_previous_one_is_not_an_error() {
        let mut parser = parser_with(b"one\r\ntwo\r\nthree\r\n");
        parser.grid_mut().push_synthetic(0, 2, BlockState::Finished, Some(0));
        parser.grid_mut().push_synthetic(1, 3, BlockState::Finished, Some(0));
        assert_eq!(parser.verify_integrity(), Ok(()));
    }

    #[test]
    fn a_block_past_the_last_row_is_reported() {
        let mut parser = parser_with(b"one\r\n");
        parser.grid_mut().push_synthetic(0, 500, BlockState::Finished, Some(0));
        assert_eq!(parser.verify_integrity(), Err(IntegrityError::BlockPastEnd { block: 0 }));
    }

    #[test]
    fn a_style_key_before_the_content_start_is_reported() {
        let mut parser = parser_with(b"\x1b[31mred\x1b[0m plain\r\n");
        parser.styles_mut().insert_key_for_test(u64::MAX - 1);
        assert_eq!(parser.verify_integrity(), Err(IntegrityError::StyleKeyOutsideContent { offset: u64::MAX - 1 }));
    }
}
```

- [ ] **Step 4: Write `integrity.rs`**

```rust
use crate::parser::Parser;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IntegrityError {
    RowOutsideContent { row: usize },
    RowsNotContiguous { row: usize },
    OpenRowDetached,
    WrappedRowEmpty { row: usize },
    BlockPastEnd { block: usize },
    NextRowPastEnd,
    StyleKeyOutsideContent { offset: u64 },
}

impl Parser {
    pub(crate) fn verify_integrity(&self) -> Result<(), IntegrityError> {
        let content_start = self.content().start_offset();
        let content_end = self.content().end_offset();
        let completed = self.rows().completed();
        let mut previous_end: Option<u64> = None;
        for (row, range) in completed.iter().enumerate() {
            if range.start > range.end || range.start < content_start || range.end > content_end {
                return Err(IntegrityError::RowOutsideContent { row });
            }
            if let Some(end) = previous_end {
                if range.start != end {
                    return Err(IntegrityError::RowsNotContiguous { row: row - 1 });
                }
            }
            if range.wrapped && range.end == range.start {
                return Err(IntegrityError::WrappedRowEmpty { row });
            }
            previous_end = Some(range.end);
        }
        if self.rows().open_start() != content_end {
            return Err(IntegrityError::OpenRowDetached);
        }
        let total_rows = completed.len() + self.screen().rows();
        for (index, block) in self.grid().blocks().enumerate() {
            let end = block.first_row + block.row_count;
            if end > total_rows || block.first_row > total_rows {
                return Err(IntegrityError::BlockPastEnd { block: index });
            }
        }
        if self.grid().next_row() > total_rows {
            return Err(IntegrityError::NextRowPastEnd);
        }
        for offset in self.styles().keys() {
            if offset < content_start || offset > content_end {
                return Err(IntegrityError::StyleKeyOutsideContent { offset });
            }
        }
        Ok(())
    }
}
```

followed by the `#[cfg(test)] mod tests` from Step 3.

Accessors this needs:

`content.rs`, in `impl Content`:

```rust
    pub fn start_offset(&self) -> u64 {
        self.chunks.front().map_or(self.next_offset, |chunk| chunk.start)
    }
```

`attribute_map.rs`, in `impl<A: Copy + Eq> AttributeMap<A>`:

```rust
    pub fn keys(&self) -> impl Iterator<Item = u64> + '_ {
        self.ends.keys().copied()
    }

    #[cfg(test)]
    pub(crate) fn insert_key_for_test(&mut self, offset: u64) {
        self.ends.insert(offset, self.tail);
    }
```

`row_index.rs`: remove the `#[cfg(test)]` above `pub fn open_start` and add

```rust
    #[cfg(test)]
    pub(crate) fn completed_mut(&mut self) -> &mut VecDeque<RowRange> {
        &mut self.completed
    }
```

`parser.rs`, next to `grid_mut`:

```rust
    #[cfg(test)]
    pub(crate) fn rows_mut(&mut self) -> &mut RowIndex {
        &mut self.rows
    }

    #[cfg(test)]
    pub(crate) fn styles_mut(&mut self) -> &mut AttributeMap<CellStyle> {
        &mut self.styles
    }
```

`lib.rs`: add `pub mod integrity;` after `pub mod grid;`, `pub use integrity::IntegrityError;` next to the other re-exports, and in `impl TerminalCore`:

```rust
    pub fn verify_integrity(&self) -> Result<(), IntegrityError> {
        self.parser.verify_integrity()
    }

    #[cfg(debug_assertions)]
    fn debug_check(&self) {
        if let Err(error) = self.parser.verify_integrity() {
            panic!("vt-core integrity violated: {error:?}");
        }
    }

    #[cfg(not(debug_assertions))]
    fn debug_check(&self) {}
```

Call `self.debug_check();` as the last statement of `feed` (after `trim_to`), `resize` (after `trim_to`), `set_reflow_on_resize`, `set_agent_tui_mode` and `set_block_bookmarked`.

- [ ] **Step 5: Run the unit and integration tests**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core integrity
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test integrity
```

Expected: the seven unit tests and the four integration tests pass. If the property test finds a violation: `proptest` prints the minimal failing `ops`; turn it into a named regression test in `tests/integrity.rs` with the literal sequence. If the fix is a local, obviously-wrong bookkeeping step (the §4.1/§4.4 class), fix it with its own commit and CHANGELOG line; otherwise mark the regression test `#[ignore = "<what is wrong>"]`, add a `TERMINAL.md` §5 entry, and stop for the user — do not widen the invariant to make the test pass.

Also confirm the debug checks cost is acceptable: `time cargo test -p vt-core` before and after must be within 2×; if not, replace the per-mutation `debug_check` in `feed` with one at the end of `feed` only (it already is) and report the timing in the commit message.

- [ ] **Step 6: Commit the checker**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-core packages/terminal/Cargo.lock && git commit -m "vt-core: integrity checker after every mutation in debug builds, with a proptest over the VT surface

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Write the failing trace test**

Append to `tests/integrity.rs`:

```rust
#[cfg(feature = "trace")]
#[test]
fn trace_records_every_dispatched_action_with_its_stream_offset() {
    use vt_core::trace::TraceAction;
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.feed(b"ab\x1b[31m\r\n");
    core.feed(b"\x1b]133;A\x07c");
    let entries = core.trace();
    let summary: Vec<(u64, String)> = entries
        .iter()
        .map(|entry| {
            let action = match &entry.action {
                TraceAction::Print(c) => format!("print {c}"),
                TraceAction::Execute(b) => format!("execute {b:#04x}"),
                TraceAction::Csi { action, params, .. } => format!("csi {action} {params:?}"),
                TraceAction::Esc { byte, .. } => format!("esc {byte:#04x}"),
                TraceAction::Osc(params) => format!("osc {}", params.len()),
            };
            (entry.offset, action)
        })
        .collect();
    assert_eq!(
        summary,
        vec![
            (0, "print a".to_string()),
            (1, "print b".to_string()),
            (6, "csi m [[31]]".to_string()),
            (7, "execute 0x0d".to_string()),
            (8, "execute 0x0a".to_string()),
            (16, "osc 2".to_string()),
            (17, "print c".to_string()),
        ]
    );
    core.clear_trace();
    assert!(core.trace().is_empty());
}
```

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --features trace --test integrity trace_records 2>&1 | head`
Expected: FAIL — unknown feature `trace` / no module `trace`.

- [ ] **Step 8: Write `trace.rs` and the hooks**

`Cargo.toml` of `vt-core`, add:

```toml
[features]
trace = []
```

`crates/vt-core/src/trace.rs`:

```rust
use std::collections::VecDeque;

pub const TRACE_CAP: usize = 4096;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TraceAction {
    Print(char),
    Execute(u8),
    Csi { params: Vec<Vec<u16>>, intermediates: Vec<u8>, action: char },
    Esc { intermediates: Vec<u8>, byte: u8 },
    Osc(Vec<Vec<u8>>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TraceEntry {
    pub offset: u64,
    pub action: TraceAction,
}

#[derive(Default)]
pub(crate) struct Trace {
    entries: VecDeque<TraceEntry>,
    pub(crate) offset: u64,
}

impl Trace {
    pub(crate) fn record(&mut self, action: TraceAction) {
        if self.entries.len() == TRACE_CAP {
            self.entries.pop_front();
        }
        self.entries.push_back(TraceEntry { offset: self.offset, action });
    }

    pub(crate) fn entries(&mut self) -> &[TraceEntry] {
        self.entries.make_contiguous()
    }

    pub(crate) fn clear(&mut self) {
        self.entries.clear();
    }
}
```

`lib.rs`: `#[cfg(feature = "trace")] pub mod trace;`. In `Parser` (`parser.rs`) add the field `#[cfg(feature = "trace")] pub(crate) trace: crate::trace::Trace,` and the line `#[cfg(feature = "trace")] trace: Default::default(),` in the `Self { … }` literal of `Parser::new`. In the `Perform` impl:

```rust
    fn print(&mut self, c: char) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Print(c));
        let style = self.pending_style.resolved();
        self.active_screen_mut().print(c, style);
    }

    fn execute(&mut self, byte: u8) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Execute(byte));
        let screen = self.active_screen_mut();
        match byte {
            0x08 => screen.move_by(0, -1),
            0x09 => screen.tab(),
            0x0A..=0x0C => screen.line_feed(),
            0x0D => screen.carriage_return(),
            _ => {}
        }
    }

    fn csi_dispatch(&mut self, params: &Params, intermediates: &[u8], _ignore: bool, c: char) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Csi {
            params: params.iter().map(|group| group.to_vec()).collect(),
            intermediates: intermediates.to_vec(),
            action: c,
        });
        if c == 'm' {
            self.apply_sgr(params);
            return;
        }
        if intermediates.first() == Some(&b'?') && matches!(c, 'h' | 'l') {
            let set = c == 'h';
            for group in params.iter() {
                match group.first().copied() {
                    Some(1) => self.app_cursor = set,
                    Some(mode) => self.note_private_mode(mode, set),
                    None => {}
                }
            }
        }
        self.active_screen_mut().csi(params, intermediates, c);
    }

    fn esc_dispatch(&mut self, intermediates: &[u8], _ignore: bool, byte: u8) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Esc { intermediates: intermediates.to_vec(), byte });
        #[cfg(not(feature = "trace"))]
        let _ = intermediates;
        self.active_screen_mut().esc(byte);
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], _bell_terminated: bool) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Osc(params.iter().map(|p| p.to_vec()).collect()));
        #[cfg(not(feature = "trace"))]
        let _ = params;
    }
```

(`esc_dispatch`'s first parameter loses its underscore because it is now read.) `lib.rs`, in `TerminalCore`: a stream-offset counter and the per-byte advance used everywhere `vte.advance` is called today:

```rust
    fed_total: u64,
```

(add to the struct and initialise to 0 in `new`), then replace both `self.vte.advance(&mut self.parser, …)` calls in `feed` with `self.advance_vte(&bytes[parsed..upto])` / `self.advance_vte(&bytes[parsed..])`, and add:

```rust
    fn advance_vte(&mut self, bytes: &[u8]) {
        #[cfg(feature = "trace")]
        {
            for byte in bytes {
                self.parser.trace.offset = self.fed_total;
                self.vte.advance(&mut self.parser, std::slice::from_ref(byte));
                self.fed_total += 1;
            }
        }
        #[cfg(not(feature = "trace"))]
        {
            self.vte.advance(&mut self.parser, bytes);
            self.fed_total += bytes.len() as u64;
        }
    }

    #[cfg(feature = "trace")]
    pub fn trace(&mut self) -> &[trace::TraceEntry] {
        self.parser.trace.entries()
    }

    #[cfg(feature = "trace")]
    pub fn clear_trace(&mut self) {
        self.parser.trace.clear();
    }
```

`trace()` takes `&mut self` because `VecDeque::make_contiguous` does; the test above calls it on a `let mut core`.

- [ ] **Step 9: Run with and without the feature**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --features trace --test integrity
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test
```

Expected: both PASS. The rule the test encodes: an entry's `offset` is the stream offset of the byte whose consumption dispatched the action — `a` at 0, `b` at 1, the SGR on its final `m` at 6, CR at 7, LF at 8, the OSC on its BEL at 16 (the sequence occupies 9..=16), `c` at 17.

- [ ] **Step 10: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-core && git commit -m "vt-core: optional dispatch trace (feature trace) pinning every vte action to its stream offset

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

**Verification (layers touched: vt-core; both wasm artifacts embed it, so rebuild):**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo clippy --all-targets --features trace -- -D warnings && cargo test -p vt-core --features trace --test integrity
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp /Users/omaraly/development/AI/Operator/packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm /Users/omaraly/development/AI/Operator/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/react && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```

Commit the rebuilt `vt_host.wasm` with the task. Restart the daemon and the app.

---

### Task 5: Synchronized output buffered in the parser (§2.1)

Port of `vte-0.15.0/src/ansi.rs:298-415` (`Processor::advance`, `advance_sync`, `advance_sync_csi`, `stop_sync_internal`) — the crate is at `/Users/omaraly/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/vte-0.15.0/src/ansi.rs`; read those lines before Step 3. Two differences from vte: (1) a BSU that starts outside a sync block is found by `memmem` over a 7-byte carry of the previously parsed bytes instead of by `advance_until_terminated`, because our mark decoder (`crates/marks`) is fed by byte offset alongside vte and must not see bytes twice; (2) the package has no clock, so `feed_at(bytes, now_ms)` and `tick(now_ms)` take the host's milliseconds (`TerminalCore::tick` is the survey §2.1 proposal).

**Files:**
- Create: `packages/terminal/crates/vt-core/src/sync.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs`
- Create: `packages/terminal/crates/vt-core/tests/synchronized_output.rs`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs`
- Modify: `packages/terminal/ts/core/src/terminal-core.ts`, `terminal-core.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts`, `dom-block-renderer.test.ts`
- Modify: `packages/terminal/crates/vt-host/src/lib.rs`
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go`, create `vtwasm_test.go`, modify `replay_test.go`, replace `assets/vt_host.wasm`
- Modify: `backend/internal/adapters/runtime/ptyhost/host.go`, `host_test.go`
- Modify: `TERMINAL.md` (§4.16), `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: Task 4's `advance_vte`, `debug_check`; `Parser::commit_evicted`, `trim_to`.
- Produces (Rust): `pub const SYNC_TIMEOUT_MS: u64 = 150`, `pub const SYNC_BUFFER_CAP: usize = 2 * 1024 * 1024` (in `vt_core::sync`); `TerminalCore::feed_at(&mut self, bytes: &[u8], now_ms: u64) -> bool` (true when any byte reached the parser), `TerminalCore::feed(&mut self, bytes)` (uses the last clock), `TerminalCore::tick(&mut self, now_ms: u64) -> bool` (true when a flush happened), `TerminalCore::synchronized_output(&self) -> bool`, `TerminalCore::pending_sync_bytes(&self) -> &[u8]`.
- Produces (wasm-bindgen): `feed(bytes: &[u8], now_ms: f64)`, `tick(now_ms: f64) -> bool`, `synchronized_output() -> bool`.
- Produces (TS `TerminalCore`): `feed(bytes)` passes `performance.now()`; `tick(nowMs: number): boolean`; `synchronizedOutput(): boolean`. `feed`/`resize` notify `onChange` listeners only when the wasm generation changed.
- Produces (vt-host): `vt_feed(handle, ptr, len, now_ms: u64)`, `vt_tick(handle, now_ms: u64) -> u32`, `vt_in_sync(handle) -> u32`; `vt_replay` appends the pending sync bytes after the cursor placement.
- Produces (Go): `(*Parser).FeedAt(bytes []byte, nowMs int64) error`, `(*Parser).Feed(bytes)` = `FeedAt(bytes, time.Now().UnixMilli())`, `(*Parser).Tick(nowMs int64) (bool, error)`, `(*Parser).InSync() (bool, error)`; `deliver(batch) bool` returns the mirror's in-sync state; `syncHoldTimeout = 150 * time.Millisecond`.

#### 5a — vt-core

- [ ] **Step 1: Write the failing tests**

`crates/vt-core/tests/synchronized_output.rs`:

```rust
mod common;

use vt_core::sync::{SYNC_BUFFER_CAP, SYNC_TIMEOUT_MS};
use vt_core::{BlockSource, TerminalCore};

const BSU: &[u8] = b"\x1b[?2026h";
const ESU: &[u8] = b"\x1b[?2026l";

fn core() -> TerminalCore {
    let mut core = TerminalCore::new(40, 100).unwrap();
    core.resize(40, 5);
    core
}

fn screen(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    let mut rows: Vec<String> = (0..snapshot.row_count()).map(|i| snapshot.row_text(i).to_string()).collect();
    while rows.last().is_some_and(|row| row.is_empty()) {
        rows.pop();
    }
    rows
}

fn cat(parts: &[&[u8]]) -> Vec<u8> {
    parts.concat()
}

(`screen` drops trailing empty rows because the export always includes the cursor row — `content_rows = max_cursor_row + 1`, `screen.rs:199-201` — so `"one\r\n"` exports `["one", ""]` and a fresh core `[""]`.)

#[test]
fn bytes_inside_a_sync_block_are_invisible_until_esu() {
    let mut core = core();
    core.feed_at(b"one\r\n", 0);
    core.feed_at(&cat(&[BSU, b"two\r\n"]), 10);
    assert_eq!(screen(&core), vec!["one"]);
    assert!(core.synchronized_output());
    core.feed_at(ESU, 20);
    assert_eq!(screen(&core), vec!["one", "two"]);
    assert!(!core.synchronized_output());
    common::check(&core);
}

#[test]
fn a_frame_split_across_three_feeds_snapshots_once() {
    let mut core = core();
    let mut changes = 0;
    let mut last = screen(&core);
    for (bytes, at) in [(cat(&[BSU, b"alpha"]), 0u64), (b"\r\nbeta".to_vec(), 5), (ESU.to_vec(), 10)] {
        core.feed_at(&bytes, at);
        let now = screen(&core);
        if now != last {
            changes += 1;
            last = now;
        }
    }
    assert_eq!(changes, 1);
    assert_eq!(screen(&core), vec!["alpha", "beta"]);
}

#[test]
fn a_mark_inside_a_sync_block_lands_after_the_rows_before_it() {
    let bytes = b"before\r\n\x1b]133;A\x07$ \x1b]133;B\x07";
    let mut plain = core();
    plain.feed_at(bytes, 0);
    let mut synced = core();
    synced.feed_at(BSU, 0);
    synced.feed_at(&bytes[..4], 1);
    synced.feed_at(&bytes[4..], 2);
    synced.feed_at(ESU, 3);
    let describe = |core: &TerminalCore| -> Vec<(u32, u32, BlockSource)> {
        core.snapshot().unwrap().blocks.iter().map(|b| (b.first_row, b.row_count, b.source)).collect()
    };
    assert_eq!(describe(&synced), describe(&plain));
    assert_eq!(describe(&synced)[1].0, 1, "{:?}", describe(&synced));
    common::check(&synced);
}

#[test]
fn overflow_flushes() {
    let mut core = core();
    core.feed_at(BSU, 0);
    let row = [b"x".repeat(38).as_slice(), b"\r\n"].concat();
    let mut fed = 0usize;
    while fed < SYNC_BUFFER_CAP + row.len() {
        core.feed_at(&row, 0);
        fed += row.len();
    }
    assert!(!screen(&core).is_empty(), "the cap must force a flush without an ESU");
    common::check(&core);
}

#[test]
fn an_oversized_chunk_starting_with_bsu_is_parsed_plainly() {
    let mut core = core();
    let row = [b"x".repeat(38).as_slice(), b"\r\n"].concat();
    let mut chunk = BSU.to_vec();
    while chunk.len() < SYNC_BUFFER_CAP {
        chunk.extend_from_slice(&row);
    }
    assert!(core.feed_at(&chunk, 0));
    assert!(!core.synchronized_output());
    assert!(!screen(&core).is_empty());
    common::check(&core);
}

#[test]
fn tick_past_deadline_flushes() {
    let mut core = core();
    core.feed_at(&cat(&[BSU, b"late"]), 0);
    assert!(!core.tick(SYNC_TIMEOUT_MS - 1));
    assert!(screen(&core).is_empty());
    assert!(core.tick(SYNC_TIMEOUT_MS));
    assert_eq!(screen(&core), vec!["late"]);
    assert!(!core.synchronized_output());
}

#[test]
fn bsu_inside_a_block_extends_the_deadline() {
    let mut core = core();
    core.feed_at(&cat(&[BSU, b"a"]), 0);
    core.feed_at(&cat(&[BSU, b"b"]), 100);
    assert!(!core.tick(200));
    assert!(screen(&core).is_empty());
    assert!(core.tick(250));
    assert_eq!(screen(&core), vec!["ab"]);
}

#[test]
fn resize_flushes() {
    let mut core = core();
    core.feed_at(&cat(&[BSU, b"x"]), 0);
    core.resize(40, 6);
    assert_eq!(screen(&core), vec!["x"]);
    assert!(!core.synchronized_output());
}

#[test]
fn unknown_private_modes_still_ignored() {
    let mut core = core();
    core.feed_at(b"\x1b[?2027h\x1b[?2026;1hok\x1b[?2026l", 0);
    assert_eq!(screen(&core), vec!["ok"]);
    assert!(!core.synchronized_output());
    assert!(!core.mouse_tracking());
    assert!(!core.bracketed_paste());
}

#[test]
fn a_bsu_split_byte_by_byte_still_buffers() {
    let mut core = core();
    for byte in cat(&[BSU, b"hidden"]) {
        core.feed_at(&[byte], 0);
    }
    assert!(core.synchronized_output());
    assert!(screen(&core).is_empty());
    for byte in ESU {
        core.feed_at(&[*byte], 1);
    }
    assert_eq!(screen(&core), vec!["hidden"]);
    common::check(&core);
}

#[test]
fn a_boundary_mark_inside_a_sync_block_flushes() {
    let mut core = core();
    core.set_agent_tui_mode(true);
    core.feed_at(&cat(&[BSU, b"old"]), 0);
    core.feed_at(b"\x1b]7000;v=1;boundary=0\x07", 1);
    assert!(!core.synchronized_output());
    assert_eq!(screen(&core), vec!["old"]);
    assert_eq!(core.snapshot().unwrap().blocks[0].exit_code, Some(0));
}

#[test]
fn pending_sync_bytes_are_the_unflushed_tail() {
    let mut core = core();
    core.feed_at(b"seen", 0);
    core.feed_at(&cat(&[BSU, b"half"]), 0);
    assert_eq!(core.pending_sync_bytes(), cat(&[BSU, b"half"]).as_slice());
    core.feed_at(ESU, 0);
    assert!(core.pending_sync_bytes().is_empty());
}

#[test]
fn feed_without_a_clock_keeps_the_last_one() {
    let mut core = core();
    core.feed_at(BSU, 40);
    core.feed(b"x");
    assert!(core.synchronized_output());
    assert!(core.tick(40 + SYNC_TIMEOUT_MS));
    assert_eq!(screen(&core), vec!["x"]);
}

#[test]
fn feed_at_reports_whether_anything_was_parsed() {
    let mut core = core();
    assert!(core.feed_at(&cat(&[b"a", BSU]), 0), "the bytes before a BSU are parsed");
    assert!(!core.feed_at(b"b", 0));
    assert!(core.feed_at(ESU, 0));
    assert!(!core.feed_at(BSU, 0), "a bare BSU parses nothing");
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test synchronized_output 2>&1 | head`
Expected: FAIL to compile — `unresolved import vt_core::sync`, `no method feed_at`.

- [ ] **Step 3: Write `sync.rs`**

```rust
use memchr::memmem;

pub const SYNC_TIMEOUT_MS: u64 = 150;
pub const SYNC_BUFFER_CAP: usize = 2 * 1024 * 1024;
pub(crate) const BSU: &[u8] = b"\x1b[?2026h";
pub(crate) const ESU: &[u8] = b"\x1b[?2026l";
pub(crate) const BOUNDARY_MARK: &[u8] = b"\x1b]7000;v=1;boundary=";
const ESCAPE_LEN: usize = 8;
const CARRY_LEN: usize = ESCAPE_LEN - 1;

pub(crate) enum TailScan {
    Keep,
    FlushAll,
    FlushBefore(usize),
}

#[derive(Default)]
pub(crate) struct SyncBuffer {
    pub(crate) bytes: Vec<u8>,
    deadline_ms: Option<u64>,
    carry: Vec<u8>,
}

impl SyncBuffer {
    pub(crate) fn is_active(&self) -> bool {
        self.deadline_ms.is_some()
    }

    pub(crate) fn deadline(&self) -> Option<u64> {
        self.deadline_ms
    }

    pub(crate) fn begin(&mut self, now_ms: u64) {
        self.deadline_ms = Some(now_ms + SYNC_TIMEOUT_MS);
    }

    pub(crate) fn end(&mut self) {
        self.deadline_ms = None;
    }

    pub(crate) fn note_parsed(&mut self, bytes: &[u8]) {
        if bytes.len() >= CARRY_LEN {
            self.carry.clear();
            self.carry.extend_from_slice(&bytes[bytes.len() - CARRY_LEN..]);
        } else {
            self.carry.extend_from_slice(bytes);
            if self.carry.len() > CARRY_LEN {
                let drop = self.carry.len() - CARRY_LEN;
                self.carry.drain(..drop);
            }
        }
    }

    pub(crate) fn find_bsu(&self, bytes: &[u8]) -> Option<usize> {
        if let Some(index) = memmem::find(bytes, BSU) {
            return Some(index);
        }
        let mut probe = Vec::with_capacity(self.carry.len() + bytes.len().min(ESCAPE_LEN));
        probe.extend_from_slice(&self.carry);
        probe.extend_from_slice(&bytes[..bytes.len().min(ESCAPE_LEN)]);
        match memmem::find(&probe, BSU) {
            Some(index) if index < self.carry.len() => Some(0),
            _ => None,
        }
    }

    pub(crate) fn would_overflow(&self, additional: usize) -> bool {
        self.bytes.len() + additional >= SYNC_BUFFER_CAP - 1
    }

    pub(crate) fn append(&mut self, bytes: &[u8], now_ms: u64) -> TailScan {
        self.bytes.extend_from_slice(bytes);
        let len = self.bytes.len();
        let start = (len - bytes.len()).saturating_sub(BOUNDARY_MARK.len() - 1);
        if memmem::find(&self.bytes[start..], BOUNDARY_MARK).is_some() {
            return TailScan::FlushAll;
        }
        let start = (len - bytes.len()).saturating_sub(CARRY_LEN);
        let end = len.saturating_sub(CARRY_LEN);
        let mut bsu_offset = None;
        for index in memchr::memchr_iter(0x1b, &self.bytes[start..end]).rev() {
            let offset = start + index;
            let escape = &self.bytes[offset..offset + ESCAPE_LEN];
            if escape == BSU {
                self.deadline_ms = Some(now_ms + SYNC_TIMEOUT_MS);
                bsu_offset = Some(offset);
            } else if escape == ESU {
                return match bsu_offset {
                    Some(keep_from) => TailScan::FlushBefore(keep_from),
                    None => TailScan::FlushAll,
                };
            }
        }
        TailScan::Keep
    }

    pub(crate) fn take(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.bytes)
    }
}
```

`memchr` is already a dependency of `vt-core` (`Cargo.toml`), with `memmem` in its default features.

- [ ] **Step 4: Wire `TerminalCore`**

`lib.rs`: add `pub mod sync;` after `pub mod row_index;`. Add to the struct:

```rust
    sync: sync::SyncBuffer,
    now_ms: u64,
```

(initialise `sync: sync::SyncBuffer::default(), now_ms: 0,` in `new`). Rename the current `feed` body to `feed_raw` and add the sync front:

```rust
    pub fn feed(&mut self, bytes: &[u8]) {
        let now_ms = self.now_ms;
        self.feed_at(bytes, now_ms);
    }

    pub fn feed_at(&mut self, bytes: &[u8], now_ms: u64) -> bool {
        self.now_ms = now_ms;
        let mut parsed = false;
        if self.sync.is_active() && self.sync.deadline().is_some_and(|deadline| now_ms >= deadline) {
            parsed |= self.flush_sync(None);
        }
        let mut rest = bytes;
        while !rest.is_empty() {
            if self.sync.is_active() {
                if self.sync.would_overflow(rest.len()) {
                    parsed |= self.flush_sync(None);
                    self.feed_raw(rest);
                    parsed = true;
                    rest = &[];
                    continue;
                }
                match self.sync.append(rest, now_ms) {
                    sync::TailScan::Keep => {}
                    sync::TailScan::FlushAll => parsed |= self.flush_sync(None),
                    sync::TailScan::FlushBefore(keep_from) => parsed |= self.flush_sync(Some(keep_from)),
                }
                rest = &[];
            } else {
                match self.sync.find_bsu(rest) {
                    Some(split) => {
                        if split > 0 {
                            self.feed_raw(&rest[..split]);
                            parsed = true;
                        }
                        self.sync.begin(now_ms);
                        rest = &rest[split..];
                    }
                    None => {
                        self.feed_raw(rest);
                        parsed = true;
                        rest = &[];
                    }
                }
            }
        }
        parsed
    }

    pub fn tick(&mut self, now_ms: u64) -> bool {
        self.now_ms = now_ms;
        if self.sync.is_active() && self.sync.deadline().is_some_and(|deadline| now_ms >= deadline) {
            return self.flush_sync(None);
        }
        false
    }

    pub fn synchronized_output(&self) -> bool {
        self.sync.is_active()
    }

    pub fn pending_sync_bytes(&self) -> &[u8] {
        &self.sync.bytes
    }

    fn flush_sync(&mut self, keep_from: Option<usize>) -> bool {
        let buffer = self.sync.take();
        let upto = keep_from.unwrap_or(buffer.len());
        let parsed = upto > 0;
        if parsed {
            self.feed_raw(&buffer[..upto]);
        }
        match keep_from {
            Some(from) => self.sync.bytes = buffer[from..].to_vec(),
            None => self.sync.end(),
        }
        parsed
    }

    fn feed_raw(&mut self, bytes: &[u8]) {
        self.sync.note_parsed(bytes);
        let events = self.mark_decoder.feed_with_offsets(bytes);
        let mut parsed = 0usize;
        for (offset, event) in events {
            let upto = offset.min(bytes.len());
            if upto > parsed {
                self.advance_vte(&bytes[parsed..upto]);
                parsed = upto;
            }
            if self.alt_screen.is_active() && !matches!(event, MarkEvent::AltScreenLeave) {
                continue;
            }
            match event {
                MarkEvent::InputReady => self.line_editor.on_input_ready(),
                MarkEvent::InputReleased => self.line_editor.on_input_released(),
                MarkEvent::AltScreenEnter => self.line_editor.on_alt_screen_enter(),
                _ => {}
            }
            let switch = event.clone();
            apply_event(&mut self.parser, &mut self.alt_screen, event);
            match switch {
                MarkEvent::AltScreenEnter => self.parser.enter_alt(self.rows),
                MarkEvent::AltScreenLeave => self.parser.leave_alt(),
                _ => {}
            }
        }
        if parsed < bytes.len() {
            self.advance_vte(&bytes[parsed..]);
        }
        self.parser.commit_evicted();
        self.parser.trim_to(self.scrollback_rows);
        self.debug_check();
    }

The two existing comment blocks inside today's `feed` ("Marks are decoded separately…" and "Re-read the alt-screen state…") move with the body unchanged.
```

`resize`: add `self.flush_sync(None);` as its first statement. A `FlushBefore(keep_from)` keeps the deadline `append` just extended (the newer BSU's), exactly as `stop_sync_internal(Some(bsu_offset))` does at `ansi.rs:340-348`. A chunk that would overflow the cap is flushed *and then parsed plainly* (`ansi.rs:375-381`): flushing alone and looping would find the same BSU again and spin when the buffer is empty and the chunk itself is over the cap.

- [ ] **Step 5: Run the tests**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test synchronized_output && cargo test`
Expected: all 14 new tests pass and the whole workspace still passes (every existing test calls `feed`, which now routes through `feed_at` with clock 0; none of them contain `?2026`).

- [ ] **Step 6: CHANGELOG and commit**

Add under "## Unreleased" in `packages/terminal/CHANGELOG.md`:

```markdown
Synchronized output (DEC private mode 2026) is buffered in the parser.

- `vt-core` holds every byte between `ESC[?2026h` and `ESC[?2026l` back from
  the model and parses the whole frame at once when the terminator, a 2 MiB
  cap, a 150 ms deadline (`TerminalCore::tick(now_ms)`, the host's clock), a
  resize or a process-boundary mark arrives — the `vte::ansi::Processor`
  mechanism (`vte-0.15.0/src/ansi.rs`, `advance_sync`), so neither the
  renderer core nor the pty-host mirror ever contains half of an Ink frame.
  `feed_at(bytes, now_ms)` carries the clock; `feed` keeps the last one.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-core packages/terminal/CHANGELOG.md && git commit -m "vt-core: buffer DEC 2026 synchronized output in the parser (feed_at/tick)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

#### 5b — vt-wasm, ts/core, renderer

- [ ] **Step 7: Write the failing TS tests**

Append to `ts/core/src/terminal-core.test.ts`:

```ts
describe("TerminalCore synchronized output", () => {
	const BSU = "\x1b[?2026h";
	const ESU = "\x1b[?2026l";

	it("notifies a pending sync block without exposing it, and flushes on the terminator", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const listener = vi.fn();
		core.onChange(listener);
		const generationBefore = core.snapshot().generation;
		core.feed(new TextEncoder().encode(`${BSU}hidden`));
		expect(listener).toHaveBeenCalledTimes(1);
		expect(core.snapshot().generation).toBe(generationBefore);
		expect(core.synchronizedOutput()).toBe(true);
		expect(new TextDecoder().decode(core.snapshot().content)).toBe("");
		core.feed(new TextEncoder().encode(ESU));
		expect(listener).toHaveBeenCalledTimes(2);
		expect(core.synchronizedOutput()).toBe(false);
		expect(new TextDecoder().decode(core.snapshot().content)).toBe("hidden");
	});

	it("tick past the deadline flushes and notifies", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const listener = vi.fn();
		core.onChange(listener);
		const start = performance.now();
		core.feed(new TextEncoder().encode(`${BSU}late`));
		expect(listener).toHaveBeenCalledTimes(1);
		expect(core.tick(start + 100)).toBe(false);
		expect(listener).toHaveBeenCalledTimes(1);
		expect(core.tick(start + 200)).toBe(true);
		expect(listener).toHaveBeenCalledTimes(2);
		expect(new TextDecoder().decode(core.snapshot().content)).toBe("late");
	});
});
```

Append to `ts/renderer-dom/src/dom-block-renderer.test.ts` inside `describe("DomBlockRenderer", …)`:

```ts
	it("does not paint a half frame", async () => {
		const { core, host } = mountWith("alpha");
		feed(core, "\x1b[?2026h\r\nbeta");
		await flushRepaint();
		expect(host.querySelectorAll("[data-terminal-row]")).toHaveLength(1);
		expect(host.textContent).toBe("alpha");
		feed(core, "\x1b[?2026l");
		await flushRepaint();
		expect(host.querySelectorAll("[data-terminal-row]")).toHaveLength(2);
		expect(host.textContent).toBe("alphabeta");
	});

	it("paints a buffered frame once the deadline passes without more bytes", async () => {
		const { core, host } = mountWith("alpha");
		feed(core, "\x1b[?2026h\r\nbeta");
		await flushRepaint();
		expect(host.textContent).toBe("alpha");
		await new Promise((resolve) => setTimeout(resolve, 180));
		await flushRepaint();
		expect(host.textContent).toBe("alphabeta");
	});
```

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run` and `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run dom-block-renderer.test.ts`
Expected: FAIL — `core.synchronizedOutput is not a function` in `ts/core`; in `renderer-dom` both new tests see "alphabeta" right after the first feed, because the wasm under `ts/core/wasm` is still the pre-Task-5 build and nothing buffers yet.

- [ ] **Step 8: vt-wasm**

`crates/vt-wasm/src/lib.rs`, replace `feed` and add `tick` / `synchronized_output`:

```rust
    pub fn feed(&mut self, bytes: &[u8], now_ms: f64) -> Result<(), JsError> {
        if self.core.feed_at(bytes, clock(now_ms)) {
            self.refresh_after_mutation()?;
        }
        Ok(())
    }

    pub fn tick(&mut self, now_ms: f64) -> Result<bool, JsError> {
        if !self.core.tick(clock(now_ms)) {
            return Ok(false);
        }
        self.refresh_after_mutation()?;
        Ok(true)
    }

    pub fn synchronized_output(&self) -> bool {
        self.core.synchronized_output()
    }
```

and at module level:

```rust
fn clock(now_ms: f64) -> u64 {
    if now_ms.is_finite() && now_ms > 0.0 {
        now_ms as u64
    } else {
        0
    }
}
```

`resize` keeps refreshing unconditionally.

- [ ] **Step 9: ts/core**

`ts/core/src/terminal-core.ts`: add a field `private lastNotifiedGeneration = 0;` and a module function

```ts
function nowMs(): number {
	return typeof performance !== "undefined" ? performance.now() : Date.now();
}
```

Replace `feed`:

```ts
	feed(bytes: Uint8Array): void {
		if (this.disposed) {
			return;
		}
		this.inner.feed(bytes, nowMs());
		if (!this.notifyIfChanged() && this.inner.synchronized_output()) {
			this.notifyAll();
		}
	}

	tick(nowMs: number): boolean {
		if (this.disposed) {
			return false;
		}
		if (!this.inner.tick(nowMs)) {
			return false;
		}
		this.notifyIfChanged();
		return true;
	}

	synchronizedOutput(): boolean {
		if (this.disposed) {
			return false;
		}
		return this.inner.synchronized_output();
	}

	private notifyIfChanged(): boolean {
		const generation = this.inner.generation();
		if (generation === this.lastNotifiedGeneration) {
			return false;
		}
		this.lastNotifiedGeneration = generation;
		this.notifyAll();
		return true;
	}

	private notifyAll(): void {
		const generation = this.inner.generation();
		let failures: unknown[] | null = null;
		for (const listener of this.listeners) {
			try {
				listener(generation);
			} catch (error) {
				(failures ??= []).push(error);
			}
		}
		if (failures) {
			throw new AggregateError(failures, "terminal core change listener failed");
		}
	}
```

The existing comment block inside `feed` ("Every listener runs even when one throws…") moves with the loop into `notifyAll` unchanged. `resize` becomes `this.inner.resize(columns, rows); this.notifyIfChanged();`. A feed that only buffered still notifies (generation unchanged, so subscribers re-read the same model): the renderer schedules frames from `onChange` alone (`dom-block-renderer.ts:112`), and that frame's `tick` is what paints a stalled block after the deadline — without the notification a `BSU` with no terminator would sit unpainted until the next byte.

- [ ] **Step 10: Renderer tick**

`ts/renderer-dom/src/dom-block-renderer.ts`, `repaintOnFrame`:

```ts
	private repaintOnFrame(timestamp: number): void {
		if (
			this.lastPaintAt !== null &&
			timestamp - this.lastPaintAt + FRAME_EPSILON_MS < PAINT_INTERVAL_MS
		) {
			this.rafHandle = requestAnimationFrame((nextTimestamp) =>
				this.repaintOnFrame(nextTimestamp),
			);
			return;
		}
		this.core?.tick(performance.now());
		this.rafHandle = null;
		this.repaint(timestamp);
	}
```

(`tick` runs while `rafHandle` is still set so the listener it fires cannot schedule a second frame. It passes `performance.now()`, the clock `TerminalCore.feed` stamps bytes with, rather than the frame's `timestamp`: in a browser they are the same clock, in jsdom they are not.) At the end of `repaint`, after `this.notifyPainted();`:

```ts
		if (core.synchronizedOutput()) this.scheduleRepaint();
```

- [ ] **Step 11: Rebuild the renderer wasm and run the TS suites**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/react && npx vitest run
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
```

Expected: PASS. `bench/adapters/dom.ts` and every other `core.feed(bytes)` caller compile unchanged (the clock is added inside `TerminalCore`).

- [ ] **Step 12: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-wasm packages/terminal/ts/core packages/terminal/ts/renderer-dom && git commit -m "terminal: renderer ticks the sync deadline each frame and never paints a half frame

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

#### 5c — vt-host, Go mirror, pump hold

- [ ] **Step 13: Write the failing Go tests**

`backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm_test.go`:

```go
package vtwasm

import (
	"strings"
	"testing"
)

const (
	bsu = "\x1b[?2026h"
	esu = "\x1b[?2026l"
)

func TestFeedAtBuffersASyncBlockUntilItsTerminator(t *testing.T) {
	p := newTestParser(t, 80, 24)
	if err := p.FeedAt([]byte(bsu+"hidden"), 1000); err != nil {
		t.Fatalf("feed: %v", err)
	}
	in, err := p.InSync()
	if err != nil || !in {
		t.Fatalf("InSync = %v, %v; want true", in, err)
	}
	text, _ := p.RenderTail(5)
	if strings.Contains(text, "hidden") {
		t.Fatalf("render shows buffered bytes: %q", text)
	}
	if err := p.FeedAt([]byte(esu), 1001); err != nil {
		t.Fatalf("feed: %v", err)
	}
	text, _ = p.RenderTail(5)
	if !strings.Contains(text, "hidden") {
		t.Fatalf("render after ESU = %q", text)
	}
}

func TestTickPastTheDeadlineFlushesTheSyncBlock(t *testing.T) {
	p := newTestParser(t, 80, 24)
	if err := p.FeedAt([]byte(bsu+"late"), 0); err != nil {
		t.Fatalf("feed: %v", err)
	}
	if flushed, err := p.Tick(149); err != nil || flushed {
		t.Fatalf("Tick(149) = %v, %v", flushed, err)
	}
	if flushed, err := p.Tick(150); err != nil || !flushed {
		t.Fatalf("Tick(150) = %v, %v", flushed, err)
	}
	text, _ := p.RenderTail(5)
	if !strings.Contains(text, "late") {
		t.Fatalf("render after tick = %q", text)
	}
}
```

Append to `vtwasm/replay_test.go`:

```go
func TestReplayNeverStartsInsideASyncBlock(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "frame one\r\n")
	partial := "\x1b[?2026h\x1b[1A\rhalf"
	feed(t, p, partial)

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	painted := out[:strings.Index(out, "\x1b[?2026h")]
	if !strings.Contains(painted, "frame one") {
		t.Fatalf("replay must paint the last complete frame, got:\n%q", out)
	}
	if strings.Contains(painted, "half") {
		t.Fatalf("replay painted bytes from an open sync block:\n%q", out)
	}
	if !strings.HasSuffix(out, partial) {
		t.Fatalf("replay must end with the buffered sync bytes so the client can complete the frame:\n%q", out)
	}
}
```

Append to `host_test.go`:

```go
func TestDeliverHoldsAcrossASyncBlock(t *testing.T) {
	f, c := newTestHostWithParser(t)
	defer f.cancel()
	defer c.close()
	syncClientRegistered(t, c)

	f.feedPTY(t, "\x1b[?2026h\x1b[2K\rframe")
	typ, payload := c.readFrame(t)
	if typ != MsgTerminalData || !strings.HasPrefix(string(payload), "\x1b[?2026h") {
		t.Fatalf("first frame = 0x%02x %q", typ, payload)
	}
	f.feedPTY(t, " one")
	select {
	case fr := <-c.frameC:
		t.Fatalf("host flushed %q while the mirror was inside a sync block", fr.payload)
	case <-time.After(3 * flushInterval):
	}
	f.feedPTY(t, "\x1b[?2026l")
	_, payload = c.readFrame(t)
	if string(payload) != " one\x1b[?2026l" {
		t.Fatalf("held batch = %q, want the rest of the frame in one message", payload)
	}
}

func TestSyncHoldEndsAtTheDeadlineAndTicksTheMirror(t *testing.T) {
	f, c := newTestHostWithParser(t)
	defer f.cancel()
	defer c.close()
	syncClientRegistered(t, c)

	f.feedPTY(t, "\x1b[?2026h\x1b[2K\rstuck")
	c.readFrame(t)
	f.feedPTY(t, " tail")
	start := time.Now()
	_, payload := c.readFrame(t)
	if string(payload) != " tail" {
		t.Fatalf("deadline batch = %q", payload)
	}
	if since := time.Since(start); since < 100*time.Millisecond {
		t.Fatalf("flushed after %v, want the %v hold", since, syncHoldTimeout)
	}
	if text := c.getOutput(t, 5); !strings.Contains(text, "stuck tail") {
		t.Fatalf("mirror after the deadline = %q, want the flushed frame", text)
	}
}
```

Run: `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... 2>&1 | head`
Expected: FAIL to compile — `p.FeedAt undefined`, `p.Tick undefined`, `syncHoldTimeout undefined`.

- [ ] **Step 14: vt-host**

`crates/vt-host/src/lib.rs`: replace `vt_feed` and add `vt_tick`, `vt_in_sync`:

```rust
#[no_mangle]
pub extern "C" fn vt_feed(handle: u32, ptr: u32, len: u32, now_ms: u64) {
    let bytes = unsafe { std::slice::from_raw_parts(ptr as *const u8, len as usize) };
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.feed_at(bytes, now_ms);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_tick(handle: u32, now_ms: u64) -> u32 {
    CORES.with(|c| match c.borrow_mut().get_mut(&handle) {
        Some(core) if core.tick(now_ms) => 1,
        _ => 0,
    })
}

#[no_mangle]
pub extern "C" fn vt_in_sync(handle: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) if core.synchronized_output() => 1,
        _ => 0,
    })
}
```

In `vt_replay`: the function builds `text: String`; change the tail so the pending bytes are appended as bytes. Replace the block from `if text.is_empty() {` to the end of the function with:

```rust
        let mut out = text.into_bytes();
        out.extend_from_slice(core.pending_sync_bytes());
        if out.is_empty() {
            return 0;
        }
        if out.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(out.as_ptr(), out_ptr as *mut u8, out.len());
        }
        out.len() as u32
```

and change the early `if total == 0 || blank { return 0; }` in the non-alt branch to

```rust
            if total == 0 || blank {
                let pending = core.pending_sync_bytes();
                if pending.is_empty() {
                    return 0;
                }
                if pending.len() > out_cap as usize {
                    return RENDER_TOO_BIG;
                }
                unsafe {
                    std::ptr::copy_nonoverlapping(pending.as_ptr(), out_ptr as *mut u8, pending.len());
                }
                return pending.len() as u32;
            }
```

Rebuild and install the mirror wasm:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp /Users/omaraly/development/AI/Operator/packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm /Users/omaraly/development/AI/Operator/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
```

- [ ] **Step 15: Go mirror API**

`vtwasm/vtwasm.go`: add `"time"` to the imports; replace `Feed` with

```go
func (p *Parser) Feed(bytes []byte) error {
	return p.FeedAt(bytes, time.Now().UnixMilli())
}

func (p *Parser) FeedAt(bytes []byte, nowMs int64) error {
	if len(bytes) == 0 {
		return nil
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, uint64(len(bytes)))
	if err != nil {
		return fmt.Errorf("vtwasm: alloc: %w", err)
	}
	ptr := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(ptr), uint64(len(bytes))) }()

	if !p.module.Memory().Write(ptr, bytes) {
		return fmt.Errorf("vtwasm: write %d bytes at %d out of range", len(bytes), ptr)
	}
	_, err = p.module.ExportedFunction("vt_feed").Call(p.ctx, uint64(p.handle), uint64(ptr), uint64(len(bytes)), uint64(nowMs))
	return err
}

func (p *Parser) Tick(nowMs int64) (bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_tick").Call(p.ctx, uint64(p.handle), uint64(nowMs))
	if err != nil {
		return false, fmt.Errorf("vtwasm: tick: %w", err)
	}
	return res[0] == 1, nil
}

func (p *Parser) InSync() (bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_in_sync").Call(p.ctx, uint64(p.handle))
	if err != nil {
		return false, fmt.Errorf("vtwasm: in_sync: %w", err)
	}
	return res[0] == 1, nil
}
```

- [ ] **Step 16: Pump hold and attach tick**

`host.go`: add `"bytes"` to the imports and the constants next to `readBufferSize`:

```go
const (
	readBufferSize  = 0x4_0000
	flushInterval   = time.Second / 60
	syncHoldTimeout = 150 * time.Millisecond
)

var esuCSI = []byte("\x1b[?2026l")
```

`deliver` returns whether the mirror is inside a sync block after the feed. Change its signature to `func (h *host) deliver(batch []byte) bool`, and replace

```go
	h.feedParserLocked(batch)
	h.mu.Unlock()
```

with

```go
	h.feedParserLocked(batch)
	inSync := h.parserInSyncLocked()
	h.mu.Unlock()
```

and end the function with `return inSync` (after `h.recorder.write(batch)`). Add:

```go
func (h *host) parserInSyncLocked() bool {
	if h.parser == nil {
		return false
	}
	in, err := h.parser.InSync()
	return err == nil && in
}

func (h *host) tickParser() {
	if parser := h.currentParser(); parser != nil {
		_, _ = parser.Tick(time.Now().UnixMilli())
	}
}
```

`pumpPTY`: replace the body from `var pending []byte` to the end of the function with

```go
	var pending []byte
	var lastFlush time.Time
	var holdUntil time.Time
	timer := time.NewTimer(time.Hour)
	if !timer.Stop() {
		<-timer.C
	}
	timerArmed := false

	flush := func() {
		if len(pending) == 0 {
			return
		}
		if h.deliver(pending) {
			holdUntil = time.Now().Add(syncHoldTimeout)
		} else {
			holdUntil = time.Time{}
		}
		pending = nil
		lastFlush = time.Now()
	}
	holding := func() bool {
		return !holdUntil.IsZero() && time.Now().Before(holdUntil) &&
			len(pending) < readBufferSize && !bytes.Contains(pending, esuCSI)
	}
	arm := func(d time.Duration) {
		if timerArmed && !timer.Stop() {
			<-timer.C
		}
		timer.Reset(d)
		timerArmed = true
	}

	for {
		select {
		case chunk, ok := <-chunks:
			if !ok {
				flush()
				h.finishPump(pty, done)
				return
			}
			pending = append(pending, chunk...)
		drain:
			for len(pending) < readBufferSize {
				select {
				case more, ok := <-chunks:
					if !ok {
						flush()
						h.finishPump(pty, done)
						return
					}
					pending = append(pending, more...)
				default:
					break drain
				}
			}
			if holding() {
				arm(time.Until(holdUntil))
			} else if len(pending) >= readBufferSize || time.Since(lastFlush) >= flushInterval {
				if timerArmed && !timer.Stop() {
					<-timer.C
				}
				timerArmed = false
				flush()
				if !holdUntil.IsZero() {
					arm(time.Until(holdUntil))
				}
			} else if !timerArmed {
				arm(flushInterval - time.Since(lastFlush))
			}
		case <-timer.C:
			timerArmed = false
			if holding() {
				arm(time.Until(holdUntil))
				continue
			}
			holdUntil = time.Time{}
			h.tickParser()
			flush()
			if !holdUntil.IsZero() {
				arm(time.Until(holdUntil))
			}
		}
	}
```

A flush that leaves the mirror inside a sync block always arms the timer for the hold deadline, even when nothing else arrives: the deadline tick is what flushes a stalled child's half frame into the mirror, so `GetOutput` and an attach replay see it after 150 ms rather than at the next byte. Add to `host_test.go`:

```go
func TestAStalledSyncBlockReachesTheMirrorAtTheDeadline(t *testing.T) {
	f, c := newTestHostWithParser(t)
	defer f.cancel()
	defer c.close()
	syncClientRegistered(t, c)

	f.feedPTY(t, "\x1b[?2026h\x1b[2K\rstalled")
	c.readFrame(t)
	if text := c.getOutput(t, 5); strings.Contains(text, "stalled") {
		t.Fatalf("mirror exposed an open sync block: %q", text)
	}
	time.Sleep(syncHoldTimeout + 50*time.Millisecond)
	if text := c.getOutput(t, 5); !strings.Contains(text, "stalled") {
		t.Fatalf("mirror after the deadline = %q, want the stalled frame", text)
	}
}
```

The mirror is ticked *before* the deadline flush so its own expired buffer is parsed first and `deliver` then sees `InSync() == false` — otherwise a stalled child would re-arm the hold every 150 ms. `replayFrameLocked`: before `rendered, err := h.parser.Replay(MaxOutputLines)` add

```go
		_, _ = h.parser.Tick(time.Now().UnixMilli())
```

Update the `pumpPTY` doc comment's last sentence to say the hold exists: "…while a lone keystroke echo never waits. When the mirror reports that a batch ended inside a DEC 2026 synchronized block, the next flush waits for the terminator or `syncHoldTimeout`, so a frame is not split across two client messages more than once."

- [ ] **Step 17: Run the Go tests**

Run: `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... -count=1`
Expected: PASS (plus the pre-existing `TestProcessEnvironmentLetsOverridesWin` failure if it still fails on `development`). `TestPumpFlushesImmediatelyWhenIdle` and `TestPumpCoalescesUnderLoad` must be unaffected: their fixture has no parser, so `deliver` returns false and nothing holds.

- [ ] **Step 18: `TERMINAL.md` §4.16 and CHANGELOG, then commit**

Add to `TERMINAL.md` after §4.15:

```markdown
### 4.16 Half-painted Ink frames
- Symptom: under Claude Code's 100 ms spinner the pane tore — a paint could
  show the top of one frame and the bottom of the previous one, and a pane
  reopened mid-frame replayed half a frame.
- Cause: Claude Code brackets every Ink frame with DEC 2026
  (`ESC[?2026h` … `ESC[?2026l`); `note_private_mode` ignored the mode, so the
  renderer painted whatever had been parsed when its animation frame fired,
  and the pty-host mirror rendered the attach replay from the same half-parsed
  state.
- Now: `vt-core` buffers the bytes of an open sync block in front of the
  parser (`sync.rs`, the port of `vte-0.15.0/src/ansi.rs` `advance_sync`) and
  parses the whole frame on the terminator, a 2 MiB cap, a 150 ms deadline
  (`TerminalCore::tick(now_ms)`), a resize or a process-boundary mark. The
  renderer ticks the core at the top of every animation frame
  (`DomBlockRenderer.repaintOnFrame`) and keeps scheduling frames while a
  block is open; the Go mirror is fed with the wall clock and ticked from the
  pump timer and before every attach replay; `vt_replay` paints the last
  complete frame and appends the still-buffered bytes so the client completes
  the frame from the live stream. The pump holds the flush after a batch that
  ended inside a block until the terminator or the deadline, so a frame is
  split across two mux messages at most once.
- Guards: `vt-core/tests/synchronized_output.rs` (`bytes_inside_a_sync_block_are_invisible_until_esu`,
  `a_frame_split_across_three_feeds_snapshots_once`, `a_mark_inside_a_sync_block_lands_after_the_rows_before_it`,
  `overflow_flushes`, `tick_past_deadline_flushes`, `bsu_inside_a_block_extends_the_deadline`,
  `resize_flushes`, `unknown_private_modes_still_ignored`, `a_bsu_split_byte_by_byte_still_buffers`,
  `a_boundary_mark_inside_a_sync_block_flushes`); `ts/core/src/terminal-core.test.ts`
  "notifies a pending sync block without exposing it…", "tick past the deadline flushes and notifies";
  `dom-block-renderer.test.ts` "does not paint a half frame", "paints a buffered frame once the
  deadline passes…"; Go `vtwasm_test.go::TestFeedAtBuffersASyncBlockUntilItsTerminator`,
  `TestTickPastTheDeadlineFlushesTheSyncBlock`, `replay_test.go::TestReplayNeverStartsInsideASyncBlock`,
  `host_test.go::TestDeliverHoldsAcrossASyncBlock`, `TestSyncHoldEndsAtTheDeadlineAndTicksTheMirror`,
  `TestAStalledSyncBlockReachesTheMirrorAtTheDeadline`;
  `bench/agent-session/run.mjs --gate` (zero torn paints, Task 8).
```

Add to the CHANGELOG entry from Step 6 two bullets:

```markdown
- The renderer ticks the core's sync deadline at the top of every animation
  frame and keeps painting frames while a block is open, so a stalled
  application is shown after 150 ms at the latest; `TerminalCore.feed` and
  `resize` notify `onChange` when the model changed or a sync block is
  pending, never for a feed that changed nothing.
- The host mirror (`vt-host`) takes the clock on `vt_feed`, exposes `vt_tick`
  and `vt_in_sync`, and `vt_replay` appends the bytes of an open sync block
  after the last complete frame so an attach never paints half a frame and
  never loses the half either.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates/vt-host backend/internal/adapters/runtime/ptyhost TERMINAL.md packages/terminal/CHANGELOG.md && git commit -m "ptyhost: mirror takes the clock, pump holds a split sync frame, replay never starts inside a sync block

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

**Verification (layers touched: vt-core, both wasm artifacts, Go, TS, daemon):**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp /Users/omaraly/development/AI/Operator/packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm /Users/omaraly/development/AI/Operator/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... -count=1
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/react && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent -- --fixture claude-spinner-10s
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```

`bench:agent` must now print `tearing.tornStates === 0`, `tornPaints === 0` and `multiPaintFrames === 0` for the spinner fixture; if it does not, the renderer path is wrong, not the fixture. The feel gate stays at zero diff: the fixture's last frame is complete, so the final pixels are the same. Commit the rebuilt `vt_host.wasm` with the task. **Restart the daemon and the app.**

---

### Task 6: Feed budget per animation frame (§2.2)

Reference: xterm.js `src/common/input/WriteBuffer.ts:20-33` (`WRITE_TIMEOUT_MS = 12`), Alacritty `alacritty_terminal/src/event_loop.rs:23-27` (`MAX_LOCKED_READ = u16::MAX`).

**Files:**
- Modify: `packages/terminal/ts/core/src/terminal-core.ts`, `terminal-core.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts`
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx`, `BlockTerminal.test.tsx`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: Task 5's `TerminalCore.feed/tick/synchronizedOutput`, `notifyIfChanged`; `DomBlockRenderer.repaintOnFrame`.
- Produces: `export const FEED_BUDGET_MS = 12`, `export const FEED_SLICE_BYTES = 64 * 1024` (from `@operator/terminal-core`); `TerminalCore.enqueue(bytes: Uint8Array): void`, `TerminalCore.drain(deadlineMs = FEED_BUDGET_MS): { remaining: number }`, `TerminalCore.hasBacklog(): boolean`, `TerminalCore.onFeedParsed(listener: (bytes: number) => void): () => void`. `enqueue` notifies `onChange` listeners once when the backlog goes from empty to non-empty (so the renderer schedules a frame); `feed` stays synchronous for tests, history blocks and replay.

- [ ] **Step 1: Write the failing tests**

Append to `ts/core/src/terminal-core.test.ts`:

```ts
describe("TerminalCore feed budget", () => {
	function rows(count: number): Uint8Array {
		let text = "";
		for (let index = 0; index < count; index += 1) text += `row ${String(index).padStart(6, "0")}\r\n`;
		return new TextEncoder().encode(text);
	}

	it("a 1 MiB enqueue drains over several frames in order", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 200000 });
		const bytes = rows(100000);
		expect(bytes.length).toBeGreaterThan(1024 * 1024);
		core.enqueue(bytes);
		expect(core.hasBacklog()).toBe(true);
		let calls = 0;
		while (core.drain(0).remaining > 0) calls += 1;
		expect(calls).toBeGreaterThan(10);
		expect(core.hasBacklog()).toBe(false);
		const snapshot = core.snapshot();
		const text = new TextDecoder().decode(snapshot.content);
		expect(text.startsWith("row 000000row 000001")).toBe(true);
		expect(text.endsWith("row 099999")).toBe(true);
	});

	it("drain stops at the deadline", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 200000 });
		core.enqueue(rows(100000));
		let tick = 0;
		const spy = vi.spyOn(performance, "now").mockImplementation(() => (tick += 20));
		const { remaining } = core.drain(12);
		spy.mockRestore();
		expect(remaining).toBeGreaterThan(0);
		expect(new TextDecoder().decode(core.snapshot().content).length).toBeLessThanOrEqual(64 * 1024);
	});

	it("onFeedParsed fires per slice", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 200000 });
		const parsed = vi.fn();
		core.onFeedParsed(parsed);
		core.enqueue(rows(20000));
		while (core.drain(0).remaining > 0) {}
		expect(parsed.mock.calls.length).toBeGreaterThan(2);
		const total = parsed.mock.calls.reduce((sum, [bytes]) => sum + (bytes as number), 0);
		expect(total).toBe(rows(20000).length);
	});

	it("enqueue notifies onChange once when the backlog becomes non-empty", () => {
		const core = createTerminalCore({ columns: 80, scrollback: 100 });
		const listener = vi.fn();
		core.onChange(listener);
		core.enqueue(new TextEncoder().encode("a"));
		core.enqueue(new TextEncoder().encode("b"));
		expect(listener).toHaveBeenCalledTimes(1);
		core.drain();
		expect(new TextDecoder().decode(core.snapshot().content)).toBe("ab");
	});
});
```

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run`
Expected: FAIL — `core.enqueue is not a function`.

- [ ] **Step 2: Implement in `ts/core`**

`terminal-core.ts`: export the constants next to `FIND_STEP_BUDGET`:

```ts
export const FEED_BUDGET_MS = 12;

export const FEED_SLICE_BYTES = 64 * 1024;
```

Add fields:

```ts
	private backlog: Uint8Array[] = [];
	private backlogBytes = 0;
	private readonly feedParsedListeners = new Set<(bytes: number) => void>();
```

Add methods after `feed`:

```ts
	enqueue(bytes: Uint8Array): void {
		if (this.disposed || bytes.length === 0) {
			return;
		}
		const wasEmpty = this.backlogBytes === 0;
		this.backlog.push(bytes);
		this.backlogBytes += bytes.length;
		if (wasEmpty) {
			this.notifyAll();
		}
	}

	drain(deadlineMs: number = FEED_BUDGET_MS): { remaining: number } {
		if (this.disposed) {
			return { remaining: 0 };
		}
		const start = nowMs();
		while (this.backlog.length > 0) {
			const head = this.backlog[0]!;
			let slice: Uint8Array;
			if (head.length <= FEED_SLICE_BYTES) {
				slice = head;
				this.backlog.shift();
			} else {
				slice = head.subarray(0, FEED_SLICE_BYTES);
				this.backlog[0] = head.subarray(FEED_SLICE_BYTES);
			}
			this.backlogBytes -= slice.length;
			this.feed(slice);
			for (const listener of [...this.feedParsedListeners]) listener(slice.length);
			if (nowMs() - start >= deadlineMs) {
				break;
			}
		}
		return { remaining: this.backlogBytes };
	}

	hasBacklog(): boolean {
		return this.backlogBytes > 0;
	}

	onFeedParsed(listener: (bytes: number) => void): () => void {
		this.feedParsedListeners.add(listener);
		return () => {
			this.feedParsedListeners.delete(listener);
		};
	}
```

(`notifyAll` and `notifyIfChanged` exist since Task 5; `enqueue` reuses them.) In `dispose`, add `this.backlog = []; this.backlogBytes = 0; this.feedParsedListeners.clear();` before `this.inner.free()`. Export the two constants from `index-browser.ts` next to `FIND_STEP_BUDGET`:

```ts
export { FEED_BUDGET_MS, FEED_SLICE_BYTES, FIND_STEP_BUDGET } from "./terminal-core.js";
```

- [ ] **Step 3: Run the ts/core tests**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run`
Expected: PASS.

- [ ] **Step 4: Renderer drains before it ticks and paints**

`dom-block-renderer.ts`, `repaintOnFrame`: change the two lines before `this.rafHandle = null;` to

```ts
		this.core?.drain();
		this.core?.tick(performance.now());
		this.rafHandle = null;
		this.repaint(timestamp);
```

and the last line of `repaint` (Task 5 added it) to

```ts
		if (core.hasBacklog() || core.synchronizedOutput()) this.scheduleRepaint();
```

Add to `dom-block-renderer.test.ts`:

```ts
	it("drains enqueued bytes on the next frame and keeps going until the backlog is empty", async () => {
		const { core, host } = mountWith("alpha");
		let text = "";
		for (let index = 0; index < 20000; index += 1) text += `\r\nline ${index}`;
		core.enqueue(new TextEncoder().encode(text));
		expect(host.textContent).toBe("alpha");
		for (let frames = 0; frames < 200 && core.hasBacklog(); frames += 1) await flushRepaint();
		expect(core.hasBacklog()).toBe(false);
		expect(new TextDecoder().decode(core.snapshot().content).endsWith("line 19999")).toBe(true);
	});
```

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run`
Expected: PASS.

- [ ] **Step 5: BlockTerminal switches to `enqueue`**

`frontend/src/renderer/components/BlockTerminal.tsx`:

```ts
function feedToCore(core: TerminalCore, bytes: Uint8Array, historyIds: Set<string>): void {
	const marks = scanSourceIdMarks(bytes);
	const reconnectsHistoryBlock = marks.some((mark) => historyIds.has(mark.id));
	core.enqueue(reconnectsHistoryBlock ? withoutRanges(bytes, marks) : bytes);
}
```

`feedHistory` keeps `core.feed(block.rawOutput)` (history blocks are fed once, synchronously, before the pane is shown). `reportReplayPainted` must wait until the backlog is parsed, or the cover lifts one frame after `enqueue` with most of the replay still queued:

```ts
	const reportReplayPainted = useCallback(() => {
		if (replayPaintedReportedRef.current) return;
		replayPaintedReportedRef.current = true;
		terminalDebug("block-terminal", "replay painted");
		const announce = () => {
			requestAnimationFrame(() => {
				if (coreRef.current?.hasBacklog()) {
					announce();
					return;
				}
				onReplayPaintedRef.current?.();
			});
		};
		announce();
	}, []);
```

Update the comment above it: the first sentence stays; append "With a queued feed the frame that carries the rows is the first one after the backlog drains, so the announcement waits for `hasBacklog()` to clear."

`BlockTerminal.test.tsx`: extend `MockCore` with

```ts
	enqueue: (bytes: Uint8Array) => void;
	hasBacklog: () => boolean;
```

and in the mock `createTerminalCore`, after `feed: (bytes) => {…},` add

```ts
				enqueue: (bytes: Uint8Array) => core.feed(bytes),
				hasBacklog: () => false,
```

(`core` is the `const core: MockCore = {…}` object being built; `enqueue` references it lazily, which is legal because the arrow runs after the literal is complete.) Add one test in the file's `describe("BlockTerminal", …)` next to "feeds output straight through once the core is sized" (the helpers `renderTerminal`, `encode` and `emit` are the file's own):

```tsx
	it("queues transport bytes on the core instead of parsing them inline", async () => {
		const enqueued: Uint8Array[] = [];
		renderTerminal({
			agentTui: true,
			coreOverrides: {
				enqueue: (bytes: Uint8Array) => {
					enqueued.push(bytes);
					mockState.feeds.push(bytes);
				},
			},
		});
		await waitFor(() => expect(mockState.core).toBeDefined());
		emit(encode("hello"));
		expect(enqueued).toHaveLength(1);
		expect(new TextDecoder().decode(enqueued[0]!)).toBe("hello");
	});
```

Run: `cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run src/renderer/components/BlockTerminal.test.tsx && npx tsc --noEmit -p .`
Expected: PASS.

- [ ] **Step 6: Measure, CHANGELOG, commit**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent -- --fixture claude-long-50k
```

The `longTask` row now measures a synchronous `feed` (the harness calls `core.feed` directly) — leave it; Task 8 adds an `enqueue` variant. CHANGELOG "Unreleased":

```markdown
Bytes are parsed under a per-frame budget.

- `TerminalCore.enqueue(bytes)` queues output and `drain(deadlineMs = 12)`
  parses it in 64 KiB slices from the renderer's animation-frame loop until
  the budget is spent (xterm.js `WriteBuffer.ts` `WRITE_TIMEOUT_MS`), so a
  multi-megabyte tool result no longer blocks the main thread for the whole
  parse. `hasBacklog()` and `onFeedParsed(listener)` expose progress; `feed`
  stays synchronous for callers that need it.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/core packages/terminal/ts/renderer-dom frontend/src/renderer/components/BlockTerminal.tsx frontend/src/renderer/components/BlockTerminal.test.tsx packages/terminal/CHANGELOG.md && git commit -m "terminal: parse queued output under a 12 ms per-frame budget

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

**Verification (layers touched: TS packages, frontend):**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/react && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p . && npx vitest run src/renderer/components/BlockTerminal.test.tsx src/renderer/components/TerminalPane.test.tsx
```

The frontend renderer changed (`BlockTerminal.tsx`); the daemon did not. Restart the app to pick it up (Vite dev reloads it on its own).

---

### Task 7: Cached char metrics (§2.3)

Reference: xterm.js `src/browser/services/CharSizeService.ts:11-40` (measure on construction and font change only, cached width/height) and `src/browser/renderer/dom/DomRenderer.ts:330-334` (`handleDevicePixelRatioChange` re-arms a `matchMedia` resolution query).

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `measure()`, `applyFontToMeasureNode`, `setFont`, `setTheme`, `dispose`, `ensureMeasureHost`.
- Produces: the same `measure(): { cellWidth, cellHeight }` signature; a private `invalidateMetrics()`; private `metricsCache: { cellWidth: number; cellHeight: number } | null`, `dprQuery: MediaQueryList | null`.

- [ ] **Step 1: Write the failing test**

Add to `dom-block-renderer.test.ts`:

```ts
	it("measure() reads layout once until the font changes", () => {
		const { renderer } = mountWith("alpha");
		const spy = vi.spyOn(HTMLElement.prototype, "getBoundingClientRect");
		renderer.measure();
		renderer.measure();
		renderer.blockContentInset();
		const measureNode = document.getElementById("terminal-m-measure")!;
		const measureCalls = () => spy.mock.contexts.filter((context) => context === measureNode).length;
		expect(measureCalls()).toBe(1);
		renderer.setFont({ ...font, sizePx: 16 });
		renderer.measure();
		renderer.measure();
		expect(measureCalls()).toBe(2);
		renderer.setTheme({ ...theme, foreground: "#ffffff" });
		renderer.measure();
		expect(measureCalls()).toBe(3);
	});
```

`mountWith` already calls `setTheme` and `setFont` once after `mount`, so the spy is installed after those; the first `measure()` after the spy is the one read.

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run dom-block-renderer.test.ts -t "reads layout once"`
Expected: FAIL — `expected 3 to be 1` (every call reads layout today).

- [ ] **Step 2: Implement the cache**

`dom-block-renderer.ts`: add fields

```ts
	private metricsCache: { cellWidth: number; cellHeight: number } | null = null;
	private dprQuery: MediaQueryList | null = null;
	private readonly onDprChange = () => this.invalidateMetrics();
```

Replace `measure()`:

```ts
	measure(): { cellWidth: number; cellHeight: number } {
		if (this.metricsCache) return this.metricsCache;
		const host = this.measureHost ?? ensureMeasureHost();
		const node = this.measureNode ?? host.querySelector<HTMLElement>(`#${HIDDEN_MEASURE_ID}`);
		if (!node) {
			return { cellWidth: 0, cellHeight: 0 };
		}
		this.applyFontToMeasureNode(node);
		const rect = node.getBoundingClientRect();
		const cellWidth = rect.width > 0 ? rect.width : this.font.sizePx * 0.6;
		const cellHeight =
			rect.height > 0 ? rect.height : this.font.lineHeight * this.font.sizePx;
		this.metricsCache = { cellWidth, cellHeight };
		this.watchDevicePixelRatio();
		return this.metricsCache;
	}

	private invalidateMetrics(): void {
		this.metricsCache = null;
		this.scheduleRepaint();
	}

	private watchDevicePixelRatio(): void {
		if (typeof matchMedia !== "function") return;
		this.dprQuery?.removeEventListener("change", this.onDprChange);
		this.dprQuery = matchMedia(`(resolution: ${window.devicePixelRatio}dppx)`);
		this.dprQuery.addEventListener("change", this.onDprChange);
	}
```

In `setTheme` and `setFont`, call `this.invalidateMetrics();` after `this.applyStyleVars();` (`setFont` changes the measured glyph; `setTheme` is included because the spec lists it and a theme can carry a font-affecting variable). In `dispose`, before `this.container = null;`:

```ts
		this.dprQuery?.removeEventListener("change", this.onDprChange);
		this.dprQuery = null;
		this.metricsCache = null;
```

`invalidateMetrics` schedules a repaint so a DPR change re-lays out rows; `scheduleRepaint` is a no-op when no core is mounted (`repaint` returns early), so calling it from `setFont` before `mount` is harmless.

- [ ] **Step 3: Run the renderer suite**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run`
Expected: PASS, including `host-styling.test.ts`, `TerminalSurface.test.tsx` "sizes the grid to the space inside the block padding" (run in `ts/react`) and the selection tests, which all go through `cellMetrics()`.

- [ ] **Step 4: CHANGELOG and commit**

```markdown
Cell metrics are measured once per font change.

- `DomBlockRenderer.measure()` caches the cell width and height and
  invalidates on `setFont`, `setTheme`, a `devicePixelRatio` change
  (`matchMedia` resolution query, xterm.js `DomRenderer.ts`
  `handleDevicePixelRatioChange`), instead
  of forcing a layout read on every paint, every selection update and every
  jump-to-bottom check (xterm.js `CharSizeService.ts`).
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom packages/terminal/CHANGELOG.md && git commit -m "renderer-dom: cache cell metrics until the font, theme or device pixel ratio changes

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

**Verification (layers touched: renderer-dom):**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/react && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
```

The feel gate must be zero: the cached number is the very number the span produced. Restart the app.

---

### Task 8: Feel gate re-run, tearing gate, "After Plan A" column

**Files:**
- Modify: `packages/terminal/bench/agent-session/run.mjs` (an `enqueue` variant of the 2 MiB row)
- Modify: `packages/terminal/package.json` (`bench:agent:gate`)
- Modify: `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` (After column)
- Modify: `TERMINAL.md` §6 (the agent-session lines join the recipe)

**Interfaces:**
- Consumes: Task 1's `run.mjs --gate`, `window.__agentSession`, Task 6's `enqueue/drain/hasBacklog`.
- Produces: `npm run bench:agent:gate` = `node ./bench/agent-session/run.mjs --gate`; the spec's baseline table gains an "After Plan A" column.

- [ ] **Step 1: Write the failing gate expectation as a script**

Add to `packages/terminal/package.json` scripts:

```json
		"bench:agent:gate": "node ./bench/agent-session/run.mjs --gate",
```

and in `run.mjs` replace `longTask2MiB` with a version that measures both paths:

```js
async function longTask2MiB(page) {
	await page.evaluate(() => window.__agentSession.resetCounters());
	const feedMs = await page.evaluate(() => window.__agentSession.feedNext(2 * 1024 * 1024));
	await page.waitForTimeout(500);
	const syncTasks = await page.evaluate(() => window.__agentSession.longTasks());
	await page.evaluate(() => window.__agentSession.resetCounters());
	const queued = await page.evaluate(async () => {
		const session = window.__agentSession;
		const core = session.core();
		const start = session.fed;
		const end = Math.min(session.fixture.bytes, start + 2 * 1024 * 1024);
		const bytes = await (await fetch(`/agent-session/fixtures/${session.fixture.name}/recording`)).arrayBuffer();
		const chunk = new Uint8Array(bytes).subarray(start, end);
		const began = performance.now();
		core.enqueue(chunk);
		let frames = 0;
		while (core.hasBacklog()) {
			await new Promise((resolve) => requestAnimationFrame(resolve));
			frames += 1;
		}
		return { frames, totalMs: performance.now() - began };
	});
	await page.waitForTimeout(500);
	const queuedTasks = await page.evaluate(() => window.__agentSession.longTasks());
	return {
		feedMs,
		longestTaskMs: syncTasks.length ? Math.max(...syncTasks) : null,
		queued: { ...queued, longestTaskMs: queuedTasks.length ? Math.max(...queuedTasks) : null, longTasks: queuedTasks.length },
	};
}
```

and change the gate's long-task check to read the queued path:

```js
			const longTask = Object.values(report.fixtures).find((rows) => rows.longTask)?.longTask;
			if (longTask && longTask.queued.longestTaskMs !== null && longTask.queued.longestTaskMs > 16) throw new Error(`queued 2 MiB feed blocked the main thread for ${longTask.queued.longestTaskMs.toFixed(1)}ms`);
```

The `feedFrames`-based spinner row and the two tearing measurements stay as Task 1 wrote them. (The page reads the recording again for the queued chunk because `main.ts` keeps `recording` private; `session.fed` marks where the synchronous 2 MiB feed stopped, so the queued feed parses the next 2 MiB, not the same bytes twice.)

- [ ] **Step 2: Run the gate**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent:gate
```

Expected: `PASS agent-session gate` — `tornStates === 0`, `tornPaints === 0`, `multiPaintFrames === 0`, queued 2 MiB longest task ≤ 16 ms. A failure is a defect in Task 5 or 6, not in the gate: read the JSON line above the FAIL, reproduce in the vitest suites, fix there with its own commit, re-run.

- [ ] **Step 3: Re-run the feel gate and the scroll gate**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent:scroll -- --fixture claude-long-50k
```

Expected: `PASS feel gate: zero pixel diff` for both fixtures; the scroll gate reports coverage of every row.

- [ ] **Step 4: Fill the "After Plan A" column**

Add a column `After Plan A` to the spec's baseline table and copy the numbers `bench:agent` prints for both fixtures (feed cost, paints/s and nodes/paint, sync and queued 2 MiB numbers, scroll, reopen, memory, torn paints). Where a metric is unchanged by design (feed cost, scroll, reopen, memory — Plan B's targets), write the number anyway; it is the confirmation that Plan A did not move them. Add under the table:

```markdown
Plan A landed 2026-09-XX: torn states/paints 0/0 (was <n>/<m>), queued 2 MiB longest task
<x> ms (was <y> ms synchronous); every other row is Plan B's target and is
unchanged within run-to-run noise.
```

- [ ] **Step 5: Add the harness to the `TERMINAL.md` §6 recipe**

After `npm run bench:selection      # Playwright: a selection must survive 20 repaints` add:

```bash
npm run bench:feel           # Playwright: zero pixel diff vs bench/agent-session/baselines (record with -- --record)
npm run bench:agent:gate     # Playwright: no torn paint under the spinner, queued 2 MiB never blocks > 16 ms
```

and to §8 a bullet: "A visual change must re-record the feel baselines (`npm run bench:feel -- --record`) in the same commit and say why in the CHANGELOG."

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/bench/agent-session/run.mjs packages/terminal/package.json docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md TERMINAL.md && git commit -m "bench: agent-session gate (no torn paints, bounded queued parse) and the post-Plan-A numbers

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

**Verification (whole recipe, since this is the plan's last task):**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown && cmp /Users/omaraly/development/AI/Operator/packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm /Users/omaraly/development/AI/Operator/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... -count=1
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/react && npx vitest run
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:selection
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:feel
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent:gate
cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .
cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon
```

`cmp` must be silent (the committed mirror wasm is the one the tree builds). Restart the daemon and the app, open a Claude Code session, and watch the spinner for 30 s: no tearing, no stall on a long tool result. Then hand over to the `plan-then-clean-session-then-review` flow (memory): review, real-app verification, merge.
