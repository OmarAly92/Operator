# Agent-TUI Plan D — Text & Glyphs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Claude Code pane can render the text attributes it prints (italic, underline in every style, strikethrough, blink, hidden, overline, coloured underline), lays out emoji sequences and CJK in the cells a terminal expects, keeps the cursor legible over any band and hollow when unfocused, and shows IME composition at the cursor — every visible change default-off behind one `RendererFeatures` object, so that with every flag off the feel gate reports zero pixel diff after every task.

**Architecture:** The terminal model (`vt-core`) gains an attribute word and an underline colour per style run and a grapheme-cluster width mode, both exported through the incremental `ExportBuffers` path (a wider style-run stride and a new per-row cell-span buffer) so the renderer never recomputes widths. The DOM renderer (`ts/renderer-dom`) reads those words and paints attributes, cursor inversion/hollowing and cluster-aware selection only when the matching `RendererFeatures` flag is on; `TerminalSurface` forwards a `features` prop. The bench harness gains a glyph probe fixture and a side-by-side mode that renders each fixture with one feature on beside the feature-off baseline, which is how the user compares before any default changes.

**Tech Stack:** Rust (`vt-core`, `vt-wasm` via wasm-bindgen, `vt-host` C-ABI wasm run by wazero; `unicode-width` 0.2.2 and `unicode-segmentation` 1.13.3, both Unicode 17.0), Go (`backend/internal/adapters/runtime/ptyhost/vtwasm`), TypeScript (`ts/core`, `ts/renderer-dom`, `ts/editor`, `ts/react`, `frontend/`), Vite + Playwright benches, Python 3 (corpus import tool).

**Spec:** `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` — Plan D covers exactly Part 4 ("Text and glyph fidelity"), gated on Plan A (landed `9a71794e9`; B `ba6dd6d35` and C `7412050f4` have also landed, so the export is incremental). Survey entries cited: `docs/terminal/2026-09-19-terminal-reference-survey.md` §1.17, §2.8, §2.12, §3.2, §3.10, §3.14, §5.9, §7.5. Read `TERMINAL.md` end to end before starting — §2 (snapshot layout and the checklist for adding a field), §3 (product independence), §5 (known gaps: underline/italic/strike not rendered), §6 (verify-and-ship recipe).

## Global Constraints

Every task inherits these; they are the spec's "Global constraints" plus `TERMINAL.md` §3.

- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no Operator import, path, default or concept inside it. Flags, tables and corpora are package assets. Operator wiring goes in `frontend/` and `backend/`; Operator needs no settings UI in Plan D — the harness is where the flags are exercised.
- No comments in new code (user's global instruction). Existing comments may be corrected when they become false. A code comment that cites a reference names the repository and path (`alacritty_terminal/src/term/cell.rs`, `xterm.js/src/browser/input/CompositionHelper.ts`, `ghostty/src/renderer/cursor.zig`, `kitty/kitty_tests/GraphemeBreakTest.json`, `warp/app/src/terminal/grid_renderer.rs`) the way `styles.css` cites Warp — such citations are the one kind of new comment permitted.
- A `vt-core` change is live only after **both** wasm artifacts are rebuilt (`vt_core` for the renderer via `npm run build:wasm -- --force`, `vt_host.wasm` copied into `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/`) and the daemon is rebuilt (`npm --prefix frontend run build:daemon`). Old pty-host processes keep the old wasm for the life of the session; every such task ends with "restart the daemon and the app".
- TDD: failing test first, run it, minimal implementation, run it, commit. Every `TERMINAL.md` §4 guard keeps passing.
- Rust: `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` from `/Users/omaraly/development/AI/Operator/packages/terminal`. TS: `npx vitest run` in each of `ts/core`, `ts/renderer-dom`, `ts/editor`, `ts/react`; `npx tsc --noEmit -p .` in `/Users/omaraly/development/AI/Operator/frontend`. Go: `go test ./internal/adapters/runtime/ptyhost/...` in `/Users/omaraly/development/AI/Operator/backend`.
- Changelog: `packages/terminal/CHANGELOG.md`, "Unreleased", one entry per behaviour change. Commits go to `development` with the `Co-Authored-By` trailer the harness gives you.
- Use absolute paths in every shell command (`TERMINAL.md` §6: parallel Bash calls share the working directory).
- **Feel gate:** every task ends with `npm run bench:feel` from `/Users/omaraly/development/AI/Operator/packages/terminal` and it must print `PASS feel gate: zero pixel diff` with every flag off. No task in this plan declares a pixel change in the default configuration; the user's words are "currently it feels perfect". A task that adds a flag also records that flag's side-by-side screenshots (`npm run bench:feel -- --feature <name>`).
- Decision 4 of the spec is settled: the SGR default is `"plain"` (today's look). Every `RendererFeatures` flag defaults off.
- Do not change behaviour the spec does not ask for: no default-on flags, no theme colour changes, no font changes, no selection-gesture or copy-format changes (Part 5), no mobile (`packages/mobile`) changes, no `vte::ansi` refactor.
- `npm run bench:selection` runs after any change to row or glyph DOM structure (Tasks 4, 8, 9, 10, 11).

## Deviations from the spec and the brief, decided here

- **`STYLE_RUN_WORDS` grows by two words, not one.** The spec says "snapshot stride grows by one word". Ten attribute bits plus a 24-bit RGB underline colour with its tag (26 bits, the `StyleCode` layout) do not fit one `u32`, and packing the attributes into the three free bits of the `fg` word plus the six free bits of the `bg` word would tie the attribute layout to the colour layout. The run becomes `(end, fg, bg, attrs, underline)`, `STYLE_RUN_WORDS = 5`, one commit across every site (Task 3). The `TERMINAL.md` §2 line that names the stride is updated in Task 12.
- **The side-by-side mode lands in Task 2, not Task 1.** Rendering "each fixture with a named feature on" needs `setFeatures` to exist; Task 1 delivers the evidence screenshots and the decision, Task 2 delivers `RendererFeatures` and the mode together so the mode is tested against a real flag from its first commit.
- **`cell-width.ts` is replaced unconditionally, not behind `graphemes`.** The exported cell spans describe the cell layout the core actually used, in both width modes; a flag to keep a hand-written table that disagrees with the core has no user. This is the one behaviour change in Plan D that is observable with every flag off, and it is not a pixel change: copying a selection across a code point the table misclassifies (`🚀` U+1F680 is width 2 in the core and absent from `WIDE_RANGES`) yields the right characters instead of one off. Recorded in the CHANGELOG as a correction of the copy path to the core's layout; the selection gate and the feel gate are unaffected. If the user wants it gated anyway, Task 7 Step 3's `rowCells` falls back to the old table when `features.graphemes` is false — a five-line change, not a redesign.
- **An underlined trailing blank stays trimmed.** `Cell::is_blank` keeps testing colour only (`is_default_paint`), so a row ending in underlined spaces exports exactly the bytes it does today and no block boundary or row shape moves with the flag off. Underlined spaces *inside* a row render as `\xa0` under `attributes: "warp"` (xterm.js `DomRendererRowFactory.ts:176-184`); trailing ones are lost, recorded in `TERMINAL.md` §5.
- **The pty-host mirror stays in scalar width mode.** `vt-host` gains no grapheme flag in Plan D: the mirror renders text for the attach replay and `GetOutput`, and the replay is re-parsed by the client core in the client's own mode. The mirror's `clip_row` clips by `char` count today (pre-existing, `TERMINAL.md` §4.7) and is out of scope. When `graphemes` ships default-on, the core default flips and both cores agree again; recorded in `TERMINAL.md` §5.
- **IME has no flag** (spec Part 4: "no flag (only affects composition)"). The composition view exists only between `compositionstart` and `compositionend`, which no fixture exercises, so the feel gate cannot see it; the spec's "manual Japanese-IME test first" is Task 9's last step and is reported, not skipped.
- **The alt screen also exports cell spans.** The spec only names the primary snapshot, but `snapshotTextRows` serves the alt view through the same `TextRows` interface, so an alt view without spans would regress CJK selection there. `AltSnapshot` gains the same two buffers.
- **The two conditional items are written as full tasks (10, 11) with a gate step**, executed only if Task 1's `EVIDENCE.json` says `needed`. The brief forbids deciding from memory; the plan cannot know the answer before Task 1 runs, so both tasks are complete and the executor skips the one the evidence rules out, recording the skip in Task 12.

## The style word and the cell span — single source of truth

Every layer below must agree with this table exactly (self-review checks it).

| Word | Rust (`vt-wasm/src/export.rs push_row`) | TS (`ts/core/src/style-runs.ts`) |
|---|---|---|
| 0 | `end` (byte offset of the run end, row-relative) | `stylePairs[i * STYLE_RUN_WORDS]` |
| 1 | `style.fg.value()` (colour + FLAG_BOLD `0x0400_0000` + FLAG_DIM `0x0800_0000`; FLAG_REVERSE is resolved at print time, `parser.rs:790`) | `+ 1` |
| 2 | `style.bg.value()` | `+ 2` |
| 3 | `style.attrs.bits() as u32` | `+ 3` |
| 4 | `style.underline.value()` (`StyleCode::DEFAULT` = 255 means "same as the foreground") | `+ 4` |

`STYLE_RUN_WORDS = 5` in `crates/vt-wasm/src/export.rs` and `ts/core/src/style-runs.ts`.

Attribute bits (`Attrs` in `crates/vt-core/src/style.rs`; `ATTR_*` in `ts/core/src/style-runs.ts`): `ITALIC = 1 << 0`, `UNDERLINE = 1 << 1`, `DOUBLE_UNDERLINE = 1 << 2`, `CURLY_UNDERLINE = 1 << 3`, `DOTTED_UNDERLINE = 1 << 4`, `DASHED_UNDERLINE = 1 << 5`, `STRIKE = 1 << 6`, `BLINK = 1 << 7`, `HIDDEN = 1 << 8`, `OVERLINE = 1 << 9`. The five underline bits are mutually exclusive: setting one clears the other four.

Cell span (`CellSpan` in `crates/vt-core/src/grid.rs`; `CELL_SPAN_WORDS = 3` in `crates/vt-wasm/src/export.rs` and `ts/core/src/cell-spans.ts`): `(start, end, width)` — row-relative byte offsets of one cluster and the cells it occupies. A row only lists clusters that are not a single scalar of width 1, so ASCII rows list nothing; `spanRanges` is a per-row `(start, end)` pair into `cellSpans`, shaped exactly like `runRanges` into `stylePairs`.

`RendererFeatures` (`ts/renderer-dom/src/features.ts`):

```ts
export type RendererFeatures = Readonly<{
	attributes: "plain" | "warp";
	graphemes: boolean;
	cursorContrast: boolean;
	cursorHollowUnfocused: boolean;
	widthCache: boolean;
	boxDrawing: boolean;
}>;
export const DEFAULT_FEATURES: RendererFeatures = {
	attributes: "plain",
	graphemes: false,
	cursorContrast: false,
	cursorHollowUnfocused: false,
	widthCache: false,
	boxDrawing: false,
};
```

## File structure

| Task | Files |
|---|---|
| 1 | `packages/terminal/bench/agent-session/probes/glyph-probe/{recording,size.json}`, `bench/agent-session/probes.mjs`, `bench/agent-session/glyph-probe.mjs`, `bench/agent-session/main.ts` (`dir` param), `bench/agent-session/feel-gate.mjs` (probes join the gate), `bench/agent-session/baselines/glyph-probe/{offset-*.png,EVIDENCE.json,EVIDENCE.md}`, `bench/agent-session/fixtures.test.mjs`, `packages/terminal/package.json` (`bench:glyphs`) |
| 2 | `ts/renderer-dom/src/{features.ts,features.test.ts,dom-block-renderer.ts,index.ts}`, `ts/react/src/{TerminalSurface.tsx,TerminalSurface.test.tsx}`, `bench/agent-session/main.ts` (`features`, `focused` params), `bench/agent-session/feel-gate.mjs` (`--feature`), `bench/agent-session/session-api.test.mjs` |
| 3 | `crates/vt-core/src/{style.rs,sgr.rs,parser.rs,history.rs,lib.rs,grid.rs,screen.rs,scrollback.rs}`, `crates/vt-core/tests/{sgr_attributes.rs,ref.rs}`, `crates/vt-core/tests/ref/{sgr,underline,colored_underline,clear_underline}/styles.json`, `tools/import-alacritty-ref.py`, `crates/vt-wasm/src/{export.rs,lib.rs}`, `crates/vt-wasm/tests/{exit_encoding.rs,export_layout.rs,incremental_export.rs}`, `crates/vt-host/src/lib.rs`, `backend/internal/adapters/runtime/ptyhost/vtwasm/{replay_test.go,assets/vt_host.wasm}`, `ts/core/src/{style-runs.ts,terminal-core.test.ts}`, `ts/renderer-dom/src/{alt-surface.test.ts,block-glyphs.test.ts}`, `CHANGELOG.md` |
| 4 | `ts/renderer-dom/src/{attributes.ts,attributes.test.ts,row-builder.ts,block-body.ts,alt-surface.ts,dom-block-renderer.ts,styles.css,styles.ts,styles-parity.test.ts}`, `CHANGELOG.md` |
| 5 | `Cargo.toml`, `crates/vt-core/Cargo.toml`, `Cargo.lock`, `crates/vt-core/src/{width.rs,lib.rs,parser.rs,screen.rs,row_index.rs,history.rs}`, `crates/vt-core/tests/{grapheme_clusters.rs,grapheme_break_test.rs}`, `crates/vt-core/tests/grapheme/{GraphemeBreakTest.json,GRAPHEME-ATTRIBUTION.md}`, `crates/vt-wasm/src/lib.rs`, `ts/core/src/{terminal-core.ts,terminal-core.test.ts}`, `ts/react/src/TerminalSurface.tsx`, `CHANGELOG.md` |
| 6 | `crates/vt-core/src/{grid.rs,lib.rs,screen/snapshot.rs}`, `crates/vt-core/tests/{cell_spans.rs,common/mod.rs}`, `crates/vt-wasm/src/{export.rs,lib.rs}`, `crates/vt-wasm/tests/{exit_encoding.rs,export_layout.rs,incremental_export.rs}`, `ts/core/src/{cell-spans.ts,types.ts,terminal-core.ts,terminal-core.test.ts,index-browser.ts}`, `CHANGELOG.md` |
| 7 | `ts/renderer-dom/src/{clusters.ts,clusters.test.ts,words.ts,words.test.ts,selection-text.ts,selection-text.test.ts,selection-model.ts,selection-model.test.ts,selection-view.ts,terminal-selection.test.ts}`, delete `ts/renderer-dom/src/{cell-width.ts,cell-width.test.ts}`, `CHANGELOG.md` |
| 8 | `ts/renderer-dom/src/{cursor-contrast.ts,cursor-contrast.test.ts,cursor.ts,cursor.test.ts,terminal-cursor.test.ts,block-body.ts,dom-block-renderer.ts,dom-block-renderer.test.ts,styles.css,styles.ts,styles-parity.test.ts}`, `ts/react/src/{TerminalSurface.tsx,TerminalSurface.test.tsx}`, `CHANGELOG.md` |
| 9 | `ts/core/src/{composition-target.ts,composition-target.test.ts}`, `ts/editor/src/{line-editor.ts,line-editor.test.ts,styles.css,styles.ts}`, `ts/react/src/{TerminalSurface.tsx,TerminalSurface.ime.test.tsx}`, `ts/renderer-dom/src/{styles.css,styles.ts}`, `CHANGELOG.md` |
| 10 (conditional) | `ts/renderer-dom/src/{box-glyphs.ts,box-glyphs.test.ts,row-builder.ts,styles.css,styles.ts,styles-parity.test.ts}`, `CHANGELOG.md` |
| 11 (conditional) | `ts/renderer-dom/src/{width-cache.ts,width-cache.test.ts,row-builder.ts,dom-block-renderer.ts}`, `CHANGELOG.md` |
| 12 | `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` (Plan D note, baseline table), `TERMINAL.md` (§2 checklist, §5, §6), `CHANGELOG.md` |

---

### Task 1: Glyph probe fixture, baseline screenshots, evidence for the two conditional items

**Files:**
- Create: `packages/terminal/bench/agent-session/probes/glyph-probe/recording`
- Create: `packages/terminal/bench/agent-session/probes/glyph-probe/size.json`
- Create: `packages/terminal/bench/agent-session/glyph-probe.mjs`
- Create: `packages/terminal/bench/agent-session/baselines/glyph-probe/{offset-0.png,…,offset-100.png,EVIDENCE.json,EVIDENCE.md,box-zoom.png}`
- Modify: `packages/terminal/bench/agent-session/fixtures.mjs` (add `PROBES_DIR`, `listProbes`, `loadProbe`)
- Modify: `packages/terminal/bench/agent-session/fixtures.test.mjs`
- Modify: `packages/terminal/bench/agent-session/main.ts` (`dir` query param, `cellMetrics()`)
- Modify: `packages/terminal/bench/agent-session/feel-gate.mjs` (probes join the gate)
- Modify: `packages/terminal/package.json` (`bench:glyphs`)

**Interfaces:**
- Consumes: `window.__agentSession` (`bench/agent-session/main.ts`), `DomBlockRenderer.measure()` (`ts/renderer-dom/src/dom-block-renderer.ts:164`), the Vite `serve-fixture-recordings` middleware (`bench/vite.config.ts`, serves any path ending in `/recording`).
- Produces: `listProbes() -> string[]`, `loadProbe(name) -> { name, recording, sizes }`, `PROBES_DIR`; `window.__agentSession.cellMetrics() -> { cellWidth, cellHeight }`; the page URL form `index.html?fixture=<name>&dir=fixtures|probes`; `npm run bench:glyphs` writing `baselines/glyph-probe/EVIDENCE.json` with the fields `boxGapPx`, `wideDriftPx`, `cjkDriftPx`, `seqDriftPx`, `boxDrawing: "needed" | "not needed"`, `widthCache: "needed" | "not needed"`. Tasks 10 and 11 read `boxDrawing` and `widthCache`; Task 5's side-by-side reads `seqDriftPx`.

A probe lives under `probes/`, not `fixtures/`, because `run.mjs` (`bench/agent-session/run.mjs:215`) treats every fixture directory as a long recording (feed cost at 50k rows, a Go reopen test keyed by fixture name) and would fail on an 800-byte probe.

- [ ] **Step 1: Write the failing probe-layout test**

Append to `packages/terminal/bench/agent-session/fixtures.test.mjs`:

```js
import { listProbes, loadProbe, PROBES_DIR } from "./fixtures.mjs";

test("every probe has a recording and a well-formed size.json and is not a fixture", async () => {
	const probes = listProbes();
	assert.ok(probes.includes("glyph-probe"), `probes: ${probes.join(", ")}`);
	for (const name of probes) {
		assert.ok(existsSync(join(PROBES_DIR, name, "recording")));
		assert.ok(!listFixtures().includes(name), `${name} must not also be a fixture`);
		const probe = await loadProbe(name);
		assert.ok(probe.recording.length > 0);
		assert.equal(probe.sizes[0].offset, 0);
	}
});

test("the glyph probe holds the rows the evidence script measures", async () => {
	const { recording } = await loadProbe("glyph-probe");
	const text = Buffer.from(recording).toString("utf8");
	for (const marker of ["│ box", "│ rows", "wide: ", "cjk: ", "seq: ", "attrs: ", "band: "]) {
		assert.ok(text.includes(marker), `probe is missing ${JSON.stringify(marker)}`);
	}
	assert.equal(text.split("\x1b[40G|").length - 1, 3, "three rows carry the column-40 marker");
});
```

(`existsSync`, `join`, `assert`, `test`, `listFixtures` are already imported at the top of the file.)

- [ ] **Step 2: Run it to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && node --test ./bench/agent-session/fixtures.test.mjs`
Expected: FAIL — `listProbes` is not exported from `./fixtures.mjs`.

- [ ] **Step 3: Add the probe loader and generate the recording**

Append to `packages/terminal/bench/agent-session/fixtures.mjs`:

```js
export const PROBES_DIR = fileURLToPath(new URL("./probes/", import.meta.url));

export function listProbes() {
	return readdirSync(PROBES_DIR, { withFileTypes: true })
		.filter((entry) => entry.isDirectory())
		.map((entry) => entry.name)
		.sort();
}

export async function loadProbe(name) {
	const dir = join(PROBES_DIR, name);
	const recording = new Uint8Array(await readFile(join(dir, "recording")));
	const sizes = JSON.parse(await readFile(join(dir, "size.json"), "utf8"));
	if (!Array.isArray(sizes)) throw new Error(`${name}/size.json must be a JSON array`);
	return { name, recording, sizes };
}
```

Generate the recording (the bytes are committed; this command is how they were made and is not a build step):

```bash
mkdir -p /Users/omaraly/development/AI/Operator/packages/terminal/bench/agent-session/probes/glyph-probe && cd /Users/omaraly/development/AI/Operator/packages/terminal/bench/agent-session/probes/glyph-probe && node -e '
const rows = [
	"0123456789".repeat(8),
	"┌────────┐",
	"│ box    │",
	"│ rows   │",
	"└────────┘",
	"├─ branch ⎿ tail",
	"wide: 🚀✅😀 \x1b[40G|",
	"cjk: 漢字テスト中文 \x1b[40G|",
	"seq: ❤️ 👨‍👩‍👧 👋🏽 🇪🇬 \x1b[40G|",
	"attrs: \x1b[1mbold\x1b[0m \x1b[2mdim\x1b[0m \x1b[3mitalic\x1b[0m \x1b[4munder\x1b[0m \x1b[4:2mdouble\x1b[0m \x1b[4:3mcurly\x1b[0m \x1b[4:4mdotted\x1b[0m \x1b[4:5mdashed\x1b[0m \x1b[9mstrike\x1b[0m \x1b[5mblink\x1b[0m \x1b[8mhidden\x1b[0m \x1b[53mover\x1b[0m \x1b[4;58;2;255;0;255mpink\x1b[0m",
	"band: \x1b[48;5;236m grey band \x1b[0m \x1b[48;2;25;170;216m cursor band \x1b[0m\x1b[8D",
];
process.stdout.write(rows.join("\r\n"));
' > recording && printf '[{"offset":0,"cols":80,"rows":24}]' > size.json && wc -c recording
```

The last row leaves the cursor eight cells back inside the `#19aad8` band (the theme's own cursor colour, `theme-warp.ts` `cursor`), which is the zero-contrast case Task 8 paints.

- [ ] **Step 4: Run the test to see it pass**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && node --test ./bench/agent-session/fixtures.test.mjs`
Expected: PASS (both new tests).

- [ ] **Step 5: Teach the page and the feel gate about probes**

In `packages/terminal/bench/agent-session/main.ts` replace the two fetch lines:

```ts
const fixtureDir = params.get("dir") === "probes" ? "probes" : "fixtures";
const [recordingResponse, sizesResponse] = await Promise.all([
	fetch(`/agent-session/${fixtureDir}/${fixtureName}/recording`),
	fetch(`/agent-session/${fixtureDir}/${fixtureName}/size.json`),
]);
```

Add `cellMetrics(): { cellWidth: number; cellHeight: number };` to the `AgentSession` type and `cellMetrics: () => domRenderer.measure(),` to the `window.__agentSession` object.

In `packages/terminal/bench/agent-session/feel-gate.mjs` replace the import and the fixture list:

```js
import { listFixtures, listProbes } from "./fixtures.mjs";
…
const targets = [
	...listFixtures().map((name) => ({ name, dir: "fixtures" })),
	...listProbes().map((name) => ({ name, dir: "probes" })),
].filter((target) => !only || target.name === only);
```

and the loop header `for (const fixture of fixtures)` becomes `for (const { name: fixture, dir } of targets)` with the `goto` URL `…/agent-session/index.html?fixture=${fixture}&dir=${dir}`. Everything else in the loop is unchanged.

- [ ] **Step 6: Record the probe baseline and confirm the gate still passes for the two fixtures**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && npm run bench:feel`
Expected: five lines `recorded glyph-probe/offset-N.png` (a missing baseline is recorded, not diffed) and then `PASS feel gate: zero pixel diff`. Re-run `npm run bench:feel` once more: `PASS feel gate: zero pixel diff` with no `recorded` lines.

- [ ] **Step 7: Write the evidence script**

`packages/terminal/bench/agent-session/glyph-probe.mjs`:

```js
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const agentDir = path.dirname(fileURLToPath(import.meta.url));
const benchDir = path.resolve(agentDir, "..");
const configFile = path.join(benchDir, "vite.config.ts");
const outDir = path.join(agentDir, "baselines", "glyph-probe");
const MARKER_COLUMN = 40;
const NEEDED_PX = 1;

function verdict(px) {
	return Math.abs(px) >= NEEDED_PX ? "needed" : "not needed";
}

const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await chromium.launch({ headless: true });
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
	const features = process.argv.includes("--features") ? process.argv[process.argv.indexOf("--features") + 1] : "";
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=glyph-probe&dir=probes&features=${encodeURIComponent(features)}`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	await page.evaluate(() => window.__agentSession.feedAll());
	await page.waitForTimeout(300);

	const layout = await page.evaluate((markerColumn) => {
		const session = window.__agentSession;
		const { cellWidth, cellHeight } = session.cellMetrics();
		const rows = [...document.querySelectorAll("[data-terminal-row]")];
		const rowStarting = (prefix) => rows.find((row) => (row.textContent ?? "").startsWith(prefix)) ?? null;
		const markerDrift = (prefix) => {
			const row = rowStarting(prefix);
			if (!row) throw new Error(`no row starts with ${prefix}`);
			const walker = document.createTreeWalker(row, NodeFilter.SHOW_TEXT);
			for (let node = walker.nextNode(); node; node = walker.nextNode()) {
				const index = node.data.indexOf("|");
				if (index < 0) continue;
				const range = document.createRange();
				range.setStart(node, index);
				range.setEnd(node, index + 1);
				const left = range.getBoundingClientRect().left - row.getBoundingClientRect().left;
				return left - markerColumn * cellWidth;
			}
			throw new Error(`row ${prefix} has no | marker`);
		};
		const box = rowStarting("│ box");
		const rowsRow = rowStarting("│ rows");
		if (!box || !rowsRow) throw new Error("box rows missing");
		const boxRect = box.getBoundingClientRect();
		const rowsRect = rowsRow.getBoundingClientRect();
		return {
			cellWidth,
			cellHeight,
			wideDriftPx: markerDrift("wide:"),
			cjkDriftPx: markerDrift("cjk:"),
			seqDriftPx: markerDrift("seq:"),
			bar: { x: boxRect.left + cellWidth / 2, top: boxRect.top, bottom: rowsRect.bottom, left: boxRect.left },
		};
	}, MARKER_COLUMN);

	const clip = { x: Math.floor(layout.bar.left), y: Math.floor(layout.bar.top), width: Math.ceil(layout.cellWidth * 4), height: Math.ceil(layout.bar.bottom - layout.bar.top) };
	const shot = await page.screenshot({ type: "png", clip, animations: "disabled", caret: "hide" });
	const gap = await page.evaluate(async ({ png, clip, x }) => {
		const image = new Image();
		image.src = `data:image/png;base64,${png}`;
		await image.decode();
		const canvas = document.createElement("canvas");
		canvas.width = clip.width;
		canvas.height = clip.height;
		const context = canvas.getContext("2d");
		context.drawImage(image, 0, 0);
		const column = Math.round(x - clip.x);
		const { data } = context.getImageData(column, 0, 1, clip.height);
		const ink = [];
		for (let y = 0; y < clip.height; y += 1) {
			const r = data[y * 4], g = data[y * 4 + 1], b = data[y * 4 + 2];
			ink.push(Math.max(r, g, b) > 60);
		}
		const middle = Math.floor(clip.height / 2);
		let up = middle;
		while (up > 0 && !ink[up]) up -= 1;
		let down = middle;
		while (down < clip.height - 1 && !ink[down]) down += 1;
		return ink[middle] ? 0 : down - up - 1;
	}, { png: shot.toString("base64"), clip, x: layout.bar.x });

	const evidence = {
		measuredAt: new Date().toISOString(),
		features: features || "(all off)",
		cellWidth: layout.cellWidth,
		cellHeight: layout.cellHeight,
		boxGapPx: gap,
		wideDriftPx: Number(layout.wideDriftPx.toFixed(2)),
		cjkDriftPx: Number(layout.cjkDriftPx.toFixed(2)),
		seqDriftPx: Number(layout.seqDriftPx.toFixed(2)),
		boxDrawing: verdict(gap),
		widthCache: verdict(Math.max(Math.abs(layout.wideDriftPx), Math.abs(layout.cjkDriftPx))),
	};
	await mkdir(outDir, { recursive: true });
	const suffix = features ? `-${features.replace(/[^a-z0-9]+/gi, "_")}` : "";
	await writeFile(path.join(outDir, `box-zoom${suffix}.png`), shot);
	await writeFile(path.join(outDir, `EVIDENCE${suffix}.json`), JSON.stringify(evidence, null, "\t"));
	process.stdout.write(`${JSON.stringify(evidence)}\n`);
	await page.close();
} finally {
	await browser?.close();
	await server.close();
}
```

`features` is read from the URL by Task 2; until then the parameter is ignored by `main.ts` and the script measures the default configuration. Add to `packages/terminal/package.json` scripts: `"bench:glyphs": "node ./bench/agent-session/glyph-probe.mjs"`.

- [ ] **Step 8: Run the probe and record the decision**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:glyphs`
Expected: one JSON line, and `bench/agent-session/baselines/glyph-probe/EVIDENCE.json` + `box-zoom.png` written. Open `box-zoom.png` (Read tool) and confirm by eye that the number in `boxGapPx` matches what the zoom shows between the two `│` rows. `seqDriftPx` is expected to be strongly negative (the model lays the ZWJ family out over 6 cells and the flag emoji over 2 single cells while the font draws each as one 2-cell glyph); that number is the grapheme item's evidence and does not feed either verdict.

Write `bench/agent-session/baselines/glyph-probe/EVIDENCE.md` by hand from the JSON — do not paraphrase numbers you did not read:

```markdown
# Glyph probe evidence (Plan D Task 1)

Measured <measuredAt> on the default configuration (every RendererFeatures flag off), font Hack 14px, lineHeight 1.2 (`ts/renderer-dom/src/default-font.ts:7`), cell <cellWidth>×<cellHeight> px.

| Item | Measurement | Verdict |
|---|---|---|
| Box drawing (spec Part 4 "only if the baseline shows hairline gaps between `│` rows") | `boxGapPx` = <n> between the `│ box` and `│ rows` rows at the bar's x (`box-zoom.png`) | <needed / not needed> |
| Width cache (spec Part 4 "only if a baseline screenshot of an emoji/CJK row shows drift") | `wideDriftPx` = <n> (🚀✅😀), `cjkDriftPx` = <n> (漢字テスト中文): distance of the column-40 `|` marker from 40 × cellWidth | <needed / not needed> |
| Grapheme clusters (not conditional; evidence for Task 5) | `seqDriftPx` = <n> on the ❤️ 👨‍👩‍👧 👋🏽 🇪🇬 row | Task 5 re-measures with `--features graphemes` |

Rule: `needed` when the measured gap or drift is ≥ 1 px (`NEEDED_PX` in `glyph-probe.mjs`); sub-pixel amounts cannot be corrected by `letter-spacing` or a CSS border.
Task 10 runs only if the first row says needed; Task 11 only if the second row says needed.
```

- [ ] **Step 9: Verify and commit**

Run, from `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `node --test ./bench/agent-session/fixtures.test.mjs ./bench/agent-session/session-api.test.mjs` → PASS
- `npm run bench:feel` → `PASS feel gate: zero pixel diff`

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/bench/agent-session packages/terminal/package.json && git commit -m "bench: glyph probe fixture and the evidence for Plan D's conditional items

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `RendererFeatures` plumbing (no behaviour) and the side-by-side mode

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/features.ts`
- Create: `packages/terminal/ts/renderer-dom/src/features.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` (`setFeatures`, `features()`)
- Modify: `packages/terminal/ts/renderer-dom/src/index.ts`
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx` (`features` prop)
- Modify: `packages/terminal/ts/react/src/TerminalSurface.test.tsx`
- Modify: `packages/terminal/bench/agent-session/main.ts` (`features` param, `features()` probe)
- Modify: `packages/terminal/bench/agent-session/session-api.test.mjs`
- Modify: `packages/terminal/bench/agent-session/feel-gate.mjs` (`--feature <list>`)

**Interfaces:**
- Consumes: `DomBlockRenderer.scheduleRepaint()`, the private `rebuildAll` flag (`dom-block-renderer.ts:100`, set by `setFont`), `TerminalSurfaceProps` (`TerminalSurface.tsx:36-65`).
- Produces: `RendererFeatures`, `DEFAULT_FEATURES`, `resolveFeatures(partial?: Partial<RendererFeatures>): RendererFeatures`, `parseFeatureList(text: string): Partial<RendererFeatures>` (grammar: comma-separated `name` or `name=value`; `attributes=warp`; a bare boolean name means `true`; unknown names throw); `DomBlockRenderer.setFeatures(partial: Partial<RendererFeatures>): void` and `DomBlockRenderer.features(): RendererFeatures`; `TerminalSurface` prop `features?: Partial<RendererFeatures>`; page URL `?features=<list>`; `window.__agentSession.features()`; `npm run bench:feel -- --feature <list>` writing `baselines/<fixture>/feature-<list with non-alphanumerics as _>/offset-N.png`. Every later task uses these names.

- [ ] **Step 1: Write the failing features tests**

`packages/terminal/ts/renderer-dom/src/features.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { DEFAULT_FEATURES, parseFeatureList, resolveFeatures } from "./features";

describe("RendererFeatures", () => {
	it("defaults every flag off and attributes to plain", () => {
		expect(DEFAULT_FEATURES).toEqual({
			attributes: "plain",
			graphemes: false,
			cursorContrast: false,
			cursorHollowUnfocused: false,
			widthCache: false,
			boxDrawing: false,
		});
		expect(resolveFeatures()).toEqual(DEFAULT_FEATURES);
		expect(resolveFeatures({ graphemes: true })).toEqual({ ...DEFAULT_FEATURES, graphemes: true });
	});

	it("parses the harness list grammar", () => {
		expect(parseFeatureList("")).toEqual({});
		expect(parseFeatureList("attributes=warp,graphemes")).toEqual({ attributes: "warp", graphemes: true });
		expect(parseFeatureList("cursorContrast=false")).toEqual({ cursorContrast: false });
	});

	it("rejects a name it does not know and a bad attributes value", () => {
		expect(() => parseFeatureList("ligatures")).toThrow(/unknown feature/);
		expect(() => parseFeatureList("attributes=bold")).toThrow(/attributes/);
	});
});
```

Add to `packages/terminal/ts/react/src/TerminalSurface.test.tsx` (inside the existing top-level `describe`, using its `font`/`theme`/`createTerminalCore` helpers):

```ts
it("forwards the features prop to the renderer and defaults it to every flag off", () => {
	const setFeatures = vi.spyOn(DomBlockRenderer.prototype, "setFeatures");
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	const { rerender } = render(
		<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={() => undefined} />,
	);
	expect(setFeatures).toHaveBeenLastCalledWith({});
	rerender(
		<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={() => undefined} features={{ attributes: "warp" }} />,
	);
	expect(setFeatures).toHaveBeenLastCalledWith({ attributes: "warp" });
	setFeatures.mockRestore();
});
```

(`DomBlockRenderer` is imported from `@operator/terminal-renderer-dom`; add the import beside the existing ones.)

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/features.test.ts` → FAIL, module `./features` not found.
Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/react && npx vitest run src/TerminalSurface.test.tsx -t "forwards the features prop"` → FAIL, `setFeatures` is not a function.

- [ ] **Step 3: Implement `features.ts`, `setFeatures`, the prop**

`packages/terminal/ts/renderer-dom/src/features.ts`:

```ts
export type RendererFeatures = Readonly<{
	attributes: "plain" | "warp";
	graphemes: boolean;
	cursorContrast: boolean;
	cursorHollowUnfocused: boolean;
	widthCache: boolean;
	boxDrawing: boolean;
}>;

export const DEFAULT_FEATURES: RendererFeatures = {
	attributes: "plain",
	graphemes: false,
	cursorContrast: false,
	cursorHollowUnfocused: false,
	widthCache: false,
	boxDrawing: false,
};

const BOOLEAN_FEATURES = ["graphemes", "cursorContrast", "cursorHollowUnfocused", "widthCache", "boxDrawing"] as const;

export function resolveFeatures(partial?: Partial<RendererFeatures>): RendererFeatures {
	return { ...DEFAULT_FEATURES, ...partial };
}

export function parseFeatureList(text: string): Partial<RendererFeatures> {
	const out: Record<string, string | boolean> = {};
	for (const item of text.split(",")) {
		const entry = item.trim();
		if (entry === "") continue;
		const [name, value] = entry.split("=", 2) as [string, string | undefined];
		if (name === "attributes") {
			if (value !== "plain" && value !== "warp") throw new Error(`attributes must be plain or warp, got ${String(value)}`);
			out.attributes = value;
			continue;
		}
		if (!(BOOLEAN_FEATURES as readonly string[]).includes(name)) throw new Error(`unknown feature ${name}`);
		out[name] = value === undefined ? true : value === "true";
	}
	return out as Partial<RendererFeatures>;
}

export function sameFeatures(a: RendererFeatures, b: RendererFeatures): boolean {
	return a.attributes === b.attributes && BOOLEAN_FEATURES.every((name) => a[name] === b[name]);
}
```

In `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` add the import `import { DEFAULT_FEATURES, resolveFeatures, sameFeatures, type RendererFeatures } from "./features.js";`, the field `private activeFeatures: RendererFeatures = DEFAULT_FEATURES;` and, after `setFont`:

```ts
	setFeatures(partial: Partial<RendererFeatures>): void {
		const next = resolveFeatures({ ...this.activeFeatures, ...partial });
		if (sameFeatures(next, this.activeFeatures)) return;
		this.activeFeatures = next;
		this.rebuildAll = true;
		this.scheduleRepaint();
	}

	features(): RendererFeatures {
		return this.activeFeatures;
	}
```

Add to `packages/terminal/ts/renderer-dom/src/index.ts`:

```ts
export { DEFAULT_FEATURES, parseFeatureList, resolveFeatures, type RendererFeatures } from "./features.js";
```

In `packages/terminal/ts/react/src/TerminalSurface.tsx`: import `type RendererFeatures` from `@operator/terminal-renderer-dom`; add `features?: Partial<RendererFeatures>;` to `TerminalSurfaceProps` after `focusToken`; destructure `features`; inside the mount `useLayoutEffect` after `renderer.setFont(font)` add `renderer.setFeatures(features ?? {});` — no, `features` must not be a dependency of the mount effect (it would remount the renderer). Instead add a dedicated effect next to the theme one:

```tsx
	const featuresKey = JSON.stringify(features ?? {});
	useLayoutEffect(() => {
		rendererRef.current?.setFeatures(features ?? {});
	}, [featuresKey]);
```

with `// eslint` untouched (the file has no eslint directives; `featuresKey` is the intended dependency and `features` is read through the closure of the same render).

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/features.test.ts` → PASS.
Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && cd ts/react && npx vitest run src/TerminalSurface.test.tsx` → PASS (the react package resolves renderer-dom through its built `dist`, so build first).

- [ ] **Step 5: Wire the harness and the side-by-side mode**

`packages/terminal/bench/agent-session/session-api.test.mjs`: extend the name list to `["feedNextSynced", "rowNodesAdded", "extendSelectionByOneRow", "mountPanes", "cellMetrics", "features"]`. Run `node --test ./bench/agent-session/session-api.test.mjs` → FAIL on `features`.

`packages/terminal/bench/agent-session/main.ts`: import `parseFeatureList` from `@operator/terminal-renderer-dom`; after `domRenderer` is obtained:

```ts
const featureList = params.get("features") ?? "";
if (featureList !== "") domRenderer.setFeatures(parseFeatureList(featureList));
```

add `features(): RendererFeatures;` to the `AgentSession` type (import `type RendererFeatures`) and `features: () => domRenderer.features(),` to the exported object. Run the session-api test → PASS.

`packages/terminal/bench/agent-session/feel-gate.mjs`: after `const only = …` add

```js
const feature = argv.includes("--feature") ? argv[argv.indexOf("--feature") + 1] : undefined;
const featureDirName = feature ? `feature-${feature.replace(/[^a-z0-9]+/gi, "_")}` : undefined;
```

and, inside the target loop after the baseline pass has closed its page, a second pass that runs only when `feature` is set:

```js
		if (feature) {
			const side = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
			await side.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=${fixture}&dir=${dir}&features=${encodeURIComponent(feature)}`);
			await side.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
			await side.evaluate(() => window.__agentSession.feedAll());
			await side.waitForTimeout(300);
			const sideDir = path.join(baselinesDir, fixture, featureDirName);
			await mkdir(sideDir, { recursive: true });
			for (const fraction of OFFSETS) {
				const name = `offset-${Math.round(fraction * 100)}.png`;
				await side.evaluate(async (f) => {
					const session = window.__agentSession;
					await session.setScrollTop(Math.round(session.scrollHeight() * f));
				}, fraction);
				await side.waitForTimeout(100);
				await writeFile(path.join(sideDir, name), await side.screenshot({ type: "png", animations: "disabled", caret: "hide" }));
				process.stdout.write(`side-by-side ${fixture}/${featureDirName}/${name} (compare with ${fixture}/${name})\n`);
			}
			await side.close();
		}
```

Side-by-side screenshots are never diffed; the final `PASS feel gate` line still reports only the flags-off comparison.

- [ ] **Step 6: Verify**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `npm run build:ts` → clean.
- `for p in core renderer-dom react; do (cd ts/$p && npx vitest run); done` → PASS.
- `node --test ./bench/agent-session/fixtures.test.mjs ./bench/agent-session/session-api.test.mjs` → PASS.
- `npm run bench:feel` → `PASS feel gate: zero pixel diff`.
- `npm run bench:feel -- --feature graphemes` → five `side-by-side …` lines per target under `baselines/<fixture>/feature-graphemes/` (byte-identical to the baseline today, since no task has given the flag a behaviour yet) and `PASS feel gate: zero pixel diff`.
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → clean (the new prop is optional).

- [ ] **Step 7: Commit**

Side-by-side directories are committed only by the task that gives the flag a behaviour; delete `baselines/*/feature-graphemes/` from this step before committing.

```bash
cd /Users/omaraly/development/AI/Operator && rm -rf packages/terminal/bench/agent-session/baselines/*/feature-graphemes && git add packages/terminal/ts/renderer-dom/src packages/terminal/ts/react/src packages/terminal/bench/agent-session && git commit -m "renderer-dom: RendererFeatures options object, default off, and the feel gate's side-by-side mode

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: SGR attributes in the model — parser, style word, export stride, mirror replay, ref corpus (ONE commit)

**This task is one commit across `vt-core`, `vt-wasm`, `vt-host`, the Go mirror asset, `ts/core`, the renderer-dom tests that hand-build style pairs, and the ref fixtures.** The export stride cannot be half-migrated: the moment `push_row` writes five words, `STYLE_RUN_WORDS` on the TS side must be 5 and every test that builds a `stylePairs` array by hand must write five words per run, or `validateMultipleOf("stylePairs", …)` (`ts/core/src/terminal-core.ts:264`) throws on the first snapshot. Work through Steps 1–12 and commit once at Step 13. The `TERMINAL.md` §2 checklist for a per-run field, every item touched here: `GridSnapshot` (`style_pairs` element type), `SnapshotCtx::push` / `export_history_row` / `export_screen_row` (`grid.rs`), `AltSnapshot` (`screen/snapshot.rs`), `ExportedRow` (`grid.rs:21`), `ExportBuffers::refresh`/`apply`/`push_row`/`truncate_screen`/`rewrite_history_from`/`compact` (`vt-wasm/src/export.rs`, every `* 3` / `/ 3`), `*_ptr/_len` (unchanged names, wider buffer), `terminal-core.ts` (the validator), `types.ts` (no shape change; documented stride), `vt-wasm/tests/exit_encoding.rs` (the `GridSnapshot` literal compiles unchanged — its `style_pairs` is empty — but `export_layout.rs` and `incremental_export.rs` pin the stride), `history_rows` (`HistoryRow.styles` carries `CellStyle`, so attributes cross a reopen once `vt-host` re-emits them).

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/style.rs` (`Attrs`, `CellStyle.attrs`, `CellStyle.underline`)
- Create: `packages/terminal/crates/vt-core/src/sgr.rs` (one `apply` for both parsers)
- Modify: `packages/terminal/crates/vt-core/src/parser.rs:652-705` (`apply_sgr` delegates), `crates/vt-core/src/history.rs:148-187` (delete the duplicate), `crates/vt-core/src/lib.rs` (`mod sgr;`, `pub use style::Attrs`)
- Create: `packages/terminal/crates/vt-core/tests/sgr_attributes.rs`
- Modify: `packages/terminal/crates/vt-core/tests/ref.rs` (styles expectation)
- Create: `packages/terminal/crates/vt-core/tests/ref/{sgr,underline,colored_underline,clear_underline}/styles.json`
- Modify: `packages/terminal/tools/import-alacritty-ref.py` (emits `styles.json`)
- Modify: `packages/terminal/crates/vt-wasm/src/export.rs` (`STYLE_RUN_WORDS = 5`), `crates/vt-wasm/src/lib.rs` (re-export), `crates/vt-wasm/tests/export_layout.rs`, `crates/vt-wasm/tests/incremental_export.rs:31`
- Modify: `packages/terminal/crates/vt-host/src/lib.rs:629-650` (`style_sgr_params` re-emits attributes)
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/replay_test.go` (`sgrRE` accepts `:`; new test), `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` (rebuilt)
- Modify: `packages/terminal/ts/core/src/style-runs.ts` (`STYLE_RUN_WORDS = 5`, `ATTR_*`, `STYLE_DEFAULT_UNDERLINE`), `ts/core/src/terminal-core.test.ts:25`, `ts/core/src/index-browser.ts` (export the new constants)
- Modify: `packages/terminal/ts/renderer-dom/src/alt-surface.test.ts:28-32`, `ts/renderer-dom/src/block-glyphs.test.ts:14` (five words per run)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `read_extended_colour(groups, index) -> (Option<StyleCode>, usize)` (`parser.rs`, already parses 58), vte `Params` sub-parameter groups (`4:3` arrives as `[4, 3]`), `StyleCode` accessors, `AttributeMap<CellStyle>` (`Copy + Eq` bound is all it needs).
- Produces (Rust): `pub struct Attrs(u16)` with `Attrs::NONE`, the ten bit constants of the layout table, `bits()`, `from_bits(u16)`, `contains(u16) -> bool`, `with(u16, bool) -> Attrs`, `without(u16) -> Attrs`, `is_empty()`; `CellStyle { fg, bg, attrs: Attrs, underline: StyleCode }` with `CellStyle::new(fg, bg)` and `from_fg(fg)` filling `attrs: Attrs::NONE, underline: StyleCode::DEFAULT`; `pub(crate) fn sgr::apply(style: &mut CellStyle, params: &Params)`; `vt_wasm::STYLE_RUN_WORDS: usize = 5`.
- Produces (TS): `STYLE_RUN_WORDS = 5`, `ATTR_ITALIC … ATTR_OVERLINE`, `STYLE_DEFAULT_UNDERLINE = 255` from `@operator/terminal-core`.
- Produces (corpus): `tests/ref/<name>/styles.json` = `{"rows": [[ [start_char, end_char, attrs, underline], … ], …]}` (top→bottom screen rows, trailing blank rows dropped, only non-default segments listed, a row with none is `[]`), asserted by `ref.rs` whenever the file exists.

- [ ] **Step 1: Write the failing parser tests**

`packages/terminal/crates/vt-core/tests/sgr_attributes.rs`:

```rust
use vt_core::{Attrs, CellStyle, StyleCode, TerminalCore};

fn style_of(bytes: &[u8]) -> CellStyle {
    let mut core = TerminalCore::new(40, 100).expect("core");
    core.resize(40, 10);
    core.feed(b"\x1b[?1049h");
    core.feed(bytes);
    core.alt_grid().expect("alt").cell(0, 0).style
}

fn attrs_of(bytes: &[u8]) -> Attrs {
    style_of(bytes).attrs
}

#[test]
fn italic_strike_blink_hidden_overline_set_and_reset() {
    assert!(attrs_of(b"\x1b[3mA").contains(Attrs::ITALIC));
    assert!(!attrs_of(b"\x1b[3m\x1b[23mA").contains(Attrs::ITALIC));
    assert!(attrs_of(b"\x1b[9mA").contains(Attrs::STRIKE));
    assert!(!attrs_of(b"\x1b[9m\x1b[29mA").contains(Attrs::STRIKE));
    assert!(attrs_of(b"\x1b[5mA").contains(Attrs::BLINK));
    assert!(attrs_of(b"\x1b[6mA").contains(Attrs::BLINK));
    assert!(!attrs_of(b"\x1b[5m\x1b[25mA").contains(Attrs::BLINK));
    assert!(attrs_of(b"\x1b[8mA").contains(Attrs::HIDDEN));
    assert!(!attrs_of(b"\x1b[8m\x1b[28mA").contains(Attrs::HIDDEN));
    assert!(attrs_of(b"\x1b[53mA").contains(Attrs::OVERLINE));
    assert!(!attrs_of(b"\x1b[53m\x1b[55mA").contains(Attrs::OVERLINE));
}

#[test]
fn every_underline_style_is_exclusive_and_24_clears_all_of_them() {
    assert_eq!(attrs_of(b"\x1b[4mA").bits(), Attrs::UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:1mA").bits(), Attrs::UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:2mA").bits(), Attrs::DOUBLE_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[21mA").bits(), Attrs::DOUBLE_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:3mA").bits(), Attrs::CURLY_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:4mA").bits(), Attrs::DOTTED_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:5mA").bits(), Attrs::DASHED_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:3m\x1b[4:1mA").bits(), Attrs::UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4;4:2mA").bits(), Attrs::DOUBLE_UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:2;4:1mA").bits(), Attrs::UNDERLINE);
    assert_eq!(attrs_of(b"\x1b[4:3m\x1b[24mA").bits(), 0);
    assert_eq!(attrs_of(b"\x1b[4m\x1b[4:0mA").bits(), 0);
    assert_eq!(attrs_of(b"\x1b[4:9mA").bits(), 0);
}

#[test]
fn an_underline_colour_is_read_in_both_spellings_and_59_restores_the_default() {
    assert_eq!(style_of(b"\x1b[58;2;255;0;255mA").underline, StyleCode::rgb(255, 0, 255));
    assert_eq!(style_of(b"\x1b[58:5:196mA").underline, StyleCode::indexed(196));
    assert_eq!(style_of(b"\x1b[58;5;196;4mA").attrs.bits(), Attrs::UNDERLINE);
    assert_eq!(style_of(b"\x1b[58;5;196m\x1b[59mA").underline, StyleCode::DEFAULT);
    assert_eq!(style_of(b"\x1b[58;5;196mA").fg, StyleCode::DEFAULT);
}

#[test]
fn sgr_0_clears_attributes_and_the_underline_colour_with_the_colours() {
    let style = style_of(b"\x1b[3;4:3;9;5;8;53;58;5;196;31;42m\x1b[0mA");
    assert_eq!(style, CellStyle::DEFAULT);
    assert!(style.attrs.is_empty());
}

#[test]
fn attributes_survive_reverse_resolution_and_a_colour_change() {
    let style = style_of(b"\x1b[7;3;4m\x1b[38;5;196mA");
    assert!(style.attrs.contains(Attrs::ITALIC));
    assert!(style.attrs.contains(Attrs::UNDERLINE));
    assert!(!style.fg.is_reverse());
    assert_eq!(style.bg, StyleCode::indexed(196));
}

#[test]
fn attributes_survive_the_trip_into_scrollback() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 2);
    core.feed(b"\x1b[3;4:3;58;2;1;2;3mabc\x1b[0m\r\nsecond\r\nthird\r\n");
    let snapshot = core.snapshot().expect("snapshot");
    let row = (0..snapshot.row_count())
        .find(|index| snapshot.row_text(*index) == "abc")
        .expect("the styled row was committed");
    let (end, style) = snapshot.row_style_pairs(row)[0];
    assert_eq!(end, 3);
    assert!(style.attrs.contains(Attrs::ITALIC));
    assert!(style.attrs.contains(Attrs::CURLY_UNDERLINE));
    assert_eq!(style.underline, StyleCode::rgb(1, 2, 3));
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn attributes_round_trip_through_a_history_chunk() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\live\r\n");
    core.feed(b"\x1b]7000;v=1;history=999,1\x1b\\");
    core.feed(b"\x1b[9;4:2;58:5:196mold\x1b[0m\r\n");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "old");
    let style = snapshot.row_style_pairs(0)[0].1;
    assert!(style.attrs.contains(Attrs::STRIKE));
    assert!(style.attrs.contains(Attrs::DOUBLE_UNDERLINE));
    assert_eq!(style.underline, StyleCode::indexed(196));
    assert_eq!(core.verify_integrity(), Ok(()));
}

#[test]
fn an_underlined_trailing_blank_is_still_trimmed_from_the_export() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(b"ab\x1b[4m  \x1b[0m");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "ab");
}
```

- [ ] **Step 2: Run to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test sgr_attributes`
Expected: compile error — no `Attrs` in `vt_core`, no field `attrs` on `CellStyle`.

- [ ] **Step 3: Add `Attrs`, widen `CellStyle`, unify SGR parsing**

`packages/terminal/crates/vt-core/src/style.rs` — add after `StyleCode`'s impl:

```rust
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct Attrs(u16);

impl Attrs {
    pub const NONE: Self = Self(0);
    pub const ITALIC: u16 = 1 << 0;
    pub const UNDERLINE: u16 = 1 << 1;
    pub const DOUBLE_UNDERLINE: u16 = 1 << 2;
    pub const CURLY_UNDERLINE: u16 = 1 << 3;
    pub const DOTTED_UNDERLINE: u16 = 1 << 4;
    pub const DASHED_UNDERLINE: u16 = 1 << 5;
    pub const STRIKE: u16 = 1 << 6;
    pub const BLINK: u16 = 1 << 7;
    pub const HIDDEN: u16 = 1 << 8;
    pub const OVERLINE: u16 = 1 << 9;
    pub const ALL_UNDERLINES: u16 = Self::UNDERLINE
        | Self::DOUBLE_UNDERLINE
        | Self::CURLY_UNDERLINE
        | Self::DOTTED_UNDERLINE
        | Self::DASHED_UNDERLINE;

    pub const fn from_bits(bits: u16) -> Self {
        Self(bits)
    }

    pub const fn bits(self) -> u16 {
        self.0
    }

    pub const fn is_empty(self) -> bool {
        self.0 == 0
    }

    pub const fn contains(self, flag: u16) -> bool {
        self.0 & flag == flag
    }

    pub const fn with(self, flag: u16, on: bool) -> Self {
        if on {
            Self(self.0 | flag)
        } else {
            Self(self.0 & !flag)
        }
    }

    pub const fn without(self, mask: u16) -> Self {
        Self(self.0 & !mask)
    }

    pub const fn with_underline(self, kind: u16) -> Self {
        Self((self.0 & !Self::ALL_UNDERLINES) | kind)
    }
}
```

and change `CellStyle`:

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CellStyle {
    pub fg: StyleCode,
    pub bg: StyleCode,
    pub attrs: Attrs,
    pub underline: StyleCode,
}

impl CellStyle {
    pub const DEFAULT: Self = Self {
        fg: StyleCode::DEFAULT,
        bg: StyleCode::DEFAULT_BACKGROUND,
        attrs: Attrs::NONE,
        underline: StyleCode::DEFAULT,
    };

    pub const fn new(fg: StyleCode, bg: StyleCode) -> Self {
        Self { fg, bg, attrs: Attrs::NONE, underline: StyleCode::DEFAULT }
    }

    pub const fn from_fg(fg: StyleCode) -> Self {
        Self::new(fg, StyleCode::DEFAULT_BACKGROUND)
    }

    pub const fn resolved(self) -> Self {
        if !self.fg.is_reverse() {
            return self;
        }
        Self {
            fg: self.fg.with_reverse(false).with_colour(self.bg.colour()),
            bg: self.fg.colour(),
            attrs: self.attrs,
            underline: self.underline,
        }
    }

    pub const fn is_default_paint(self) -> bool {
        self.fg.value() == StyleCode::DEFAULT.value()
            && self.bg.value() == StyleCode::DEFAULT_BACKGROUND.value()
    }
}
```

`packages/terminal/crates/vt-core/src/sgr.rs` (new; the body is `parser.rs:652-705` moved, with the new arms):

```rust
use vte::Params;

use crate::parser::read_extended_colour;
use crate::style::{Attrs, CellStyle, StyleCode};

pub(crate) fn apply(style: &mut CellStyle, params: &Params) {
    let groups: Vec<Vec<u16>> = params.iter().map(|sub| sub.to_vec()).collect();
    if groups.is_empty() {
        *style = CellStyle::DEFAULT;
        return;
    }
    let mut index = 0;
    while index < groups.len() {
        let group = &groups[index];
        let code = group.first().copied().unwrap_or(0);
        if matches!(code, 38 | 48 | 58) {
            let (colour, consumed) = read_extended_colour(&groups, index);
            if let Some(colour) = colour {
                match code {
                    38 => style.fg = style.fg.with_colour(colour),
                    48 => style.bg = colour,
                    _ => style.underline = colour,
                }
            }
            index += consumed;
            continue;
        }
        match code {
            0 => *style = CellStyle::DEFAULT,
            1 => style.fg = style.fg.with_bold(true),
            2 => style.fg = style.fg.with_dim(true),
            3 => style.attrs = style.attrs.with(Attrs::ITALIC, true),
            4 => {
                let kind = match group.get(1).copied() {
                    None | Some(1) => Attrs::UNDERLINE,
                    Some(0) => 0,
                    Some(2) => Attrs::DOUBLE_UNDERLINE,
                    Some(3) => Attrs::CURLY_UNDERLINE,
                    Some(4) => Attrs::DOTTED_UNDERLINE,
                    Some(5) => Attrs::DASHED_UNDERLINE,
                    Some(_) => 0,
                };
                style.attrs = style.attrs.with_underline(kind);
            }
            5 | 6 => style.attrs = style.attrs.with(Attrs::BLINK, true),
            7 => style.fg = style.fg.with_reverse(true),
            8 => style.attrs = style.attrs.with(Attrs::HIDDEN, true),
            9 => style.attrs = style.attrs.with(Attrs::STRIKE, true),
            21 => style.attrs = style.attrs.with_underline(Attrs::DOUBLE_UNDERLINE),
            22 => style.fg = style.fg.with_bold(false).with_dim(false),
            23 => style.attrs = style.attrs.with(Attrs::ITALIC, false),
            24 => style.attrs = style.attrs.without(Attrs::ALL_UNDERLINES),
            25 => style.attrs = style.attrs.with(Attrs::BLINK, false),
            27 => style.fg = style.fg.with_reverse(false),
            28 => style.attrs = style.attrs.with(Attrs::HIDDEN, false),
            29 => style.attrs = style.attrs.with(Attrs::STRIKE, false),
            30..=37 => style.fg = style.fg.with_colour(StyleCode::ansi((code - 30) as u8)),
            39 => style.fg = style.fg.with_colour(StyleCode::DEFAULT),
            40..=47 => style.bg = StyleCode::ansi((code - 40) as u8),
            49 => style.bg = StyleCode::DEFAULT_BACKGROUND,
            53 => style.attrs = style.attrs.with(Attrs::OVERLINE, true),
            55 => style.attrs = style.attrs.with(Attrs::OVERLINE, false),
            59 => style.underline = StyleCode::DEFAULT,
            90..=97 => style.fg = style.fg.with_colour(StyleCode::ansi((code - 90 + 8) as u8)),
            100..=107 => style.bg = StyleCode::ansi((code - 100 + 8) as u8),
            _ => {}
        }
        index += 1;
    }
}
```

`parser.rs`: replace the body of `Parser::apply_sgr` with `crate::sgr::apply(&mut self.pending_style, params); self.sync_erase_background();` and delete `set_pending_style` if it is now unused (the other callers at `parser.rs:238,300,307` assign `pending_style` directly — check with `cargo clippy`). `history.rs`: delete the local `apply_sgr` (lines 148-187) and call `crate::sgr::apply(self.style, params)` at line 136. `lib.rs`: add `mod sgr;` next to `mod history;` and change the re-export to `pub use style::{Attrs, CellStyle, StyleCode};`. The `Cell` doc comment "It is boxed so the common cell stays two words" (`screen.rs:24`) is now false (`CellStyle` is 16 bytes); correct it to "so the common cell stays small" — a corrected existing comment, not a new one.

- [ ] **Step 4: Run the vt-core tests**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core`
Expected: `sgr_attributes` PASS; every existing test still PASS (`style_codes::a_background_or_underline_colour_does_not_repaint_the_foreground` keeps passing because 58 now lands in `underline`, not `fg`).

- [ ] **Step 5: Widen the export to five words**

`packages/terminal/crates/vt-wasm/src/export.rs`: add `pub const STYLE_RUN_WORDS: usize = 5;` beside `BLOCK_RECORD_WORDS`; in `refresh` (both the primary and the `alt` loops) and `push_row`, after `self.style_pairs.push(style.bg.value());` add

```rust
            self.style_pairs.push(u32::from(style.attrs.bits()));
            self.style_pairs.push(style.underline.value());
```

(and the same two lines for `alt_style_pairs`); replace every `/ 3` and `* 3` on `style_pairs`/`history_pairs`/`dead_pairs` (`apply`, `rewrite_history_from`, `truncate_screen`, `push_row`, `compact`) with `/ STYLE_RUN_WORDS` and `* STYLE_RUN_WORDS`. `crates/vt-wasm/src/lib.rs`: add `STYLE_RUN_WORDS` to the `pub use export::{…}` list.

Tests: `crates/vt-wasm/tests/export_layout.rs::flattens_rows_and_runs_as_u32_pairs` expectation becomes

```rust
    assert_eq!(
        buffers.style_pairs(),
        &[3, 1, 254, 0, 255, 6, 255, 254, 0, 255, 5, 255, 254, 0, 255]
    );
```

`crates/vt-wasm/tests/incremental_export.rs:31`: `pairs[pair_start * 3..pair_end * 3]` → `pairs[pair_start * STYLE_RUN_WORDS..pair_end * STYLE_RUN_WORDS]` with `use vt_wasm::STYLE_RUN_WORDS;`. Add to `incremental_export.rs` a proptest op that emits attributes so the equality property covers the new words: in the `Op` strategy add `2 => (0u8..=5).prop_map(|k| Op::Bytes(format!("\x1b[3;4:{k};9;58;5;196mat\x1b[0m").into_bytes()))`.

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-wasm` → PASS.

- [ ] **Step 6: Re-emit attributes from the mirror**

`packages/terminal/crates/vt-host/src/lib.rs` `style_sgr_params` (line 629): after the dim push add

```rust
    let attrs = style.attrs;
    if attrs.contains(Attrs::ITALIC) {
        params.push("3".to_string());
    }
    let underline = [
        (Attrs::UNDERLINE, "4:1"),
        (Attrs::DOUBLE_UNDERLINE, "4:2"),
        (Attrs::CURLY_UNDERLINE, "4:3"),
        (Attrs::DOTTED_UNDERLINE, "4:4"),
        (Attrs::DASHED_UNDERLINE, "4:5"),
    ]
    .into_iter()
    .find(|(flag, _)| attrs.contains(*flag));
    if let Some((_, code)) = underline {
        params.push(code.to_string());
    }
    if attrs.contains(Attrs::BLINK) {
        params.push("5".to_string());
    }
    if attrs.contains(Attrs::HIDDEN) {
        params.push("8".to_string());
    }
    if attrs.contains(Attrs::STRIKE) {
        params.push("9".to_string());
    }
    if attrs.contains(Attrs::OVERLINE) {
        params.push("53".to_string());
    }
    if style.underline != StyleCode::DEFAULT {
        params.push(underline_colour_params(style.underline));
    }
```

with

```rust
fn underline_colour_params(colour: StyleCode) -> String {
    let value = colour.value();
    if value & TAG_RGB != 0 {
        let rgb = value & 0x00ff_ffff;
        format!("58;2;{};{};{}", (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff)
    } else {
        format!("58;5;{}", value & 0xff)
    }
}
```

and `use vt_core::Attrs;` at the top. Then the Go test — `backend/internal/adapters/runtime/ptyhost/vtwasm/replay_test.go`: change `sgrRE` to `regexp.MustCompile("\x1b\\[[0-9;:]*m")` and add

```go
// Attributes the child set must come back on reopen, or an italic tool name,
// an underlined link and a struck diff line turn plain after every reattach.
func TestReplayKeepsSgrAttributesAndTheUnderlineColour(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "\x1b[3;4:3;9;58;5;196mstyled\x1b[0m plain\r\n")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	for _, want := range []string{";3;", "4:3", ";9", "58;5;196"} {
		if !strings.Contains(out, want) {
			t.Fatalf("replay lost %q:\n%q", want, out)
		}
	}
	if !strings.Contains(stripSGR(out), "styled plain") {
		t.Fatalf("replay text changed:\n%q", stripSGR(out))
	}
}
```

Rebuild and run:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...
```

Expected: the new test PASS; `TestProcessEnvironmentLetsOverridesWin` may fail as it does on `master` (`TERMINAL.md` §5) — nothing else.

- [ ] **Step 7: Move the TS side to five words**

`packages/terminal/ts/core/src/style-runs.ts`:

```ts
export const STYLE_RUN_WORDS = 5;

export const STYLE_DEFAULT_FOREGROUND = 255;

export const STYLE_DEFAULT_BACKGROUND = 254;

export const STYLE_DEFAULT_UNDERLINE = 255;

export const ATTR_ITALIC = 1 << 0;
export const ATTR_UNDERLINE = 1 << 1;
export const ATTR_DOUBLE_UNDERLINE = 1 << 2;
export const ATTR_CURLY_UNDERLINE = 1 << 3;
export const ATTR_DOTTED_UNDERLINE = 1 << 4;
export const ATTR_DASHED_UNDERLINE = 1 << 5;
export const ATTR_STRIKE = 1 << 6;
export const ATTR_BLINK = 1 << 7;
export const ATTR_HIDDEN = 1 << 8;
export const ATTR_OVERLINE = 1 << 9;
```

`ts/core/src/index-browser.ts:48`: export the eleven new names from `./style-runs.js` beside `STYLE_RUN_WORDS`. `ts/core/src/terminal-core.test.ts:25`: `[3, 1, 254, 0, 255, 9, 255, 254, 0, 255, 5, 255, 254, 0, 255]`. `ts/renderer-dom/src/alt-surface.test.ts:28-32`: push `bytes.byteLength, rowStyleCodes[i] ?? DEFAULT_STYLE_CODE, DEFAULT_BACKGROUND_CODE, 0, DEFAULT_STYLE_CODE`. `ts/renderer-dom/src/block-glyphs.test.ts:14`: `Uint32Array.from([content.byteLength, styleCode, DEFAULT_BACKGROUND, 0, DEFAULT_FOREGROUND])`. `row-builder.ts` needs no change yet (it reads words 0–2 by index); `alt-surface.ts` fingerprints by `STYLE_RUN_WORDS` and follows the constant.

Rebuild the renderer wasm and run every TS suite:

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done
```

Expected: PASS everywhere; `frontend/src/renderer/test/setup.ts:61` and `BlockTerminal.test.tsx:192` build empty `stylePairs` and need nothing.

- [ ] **Step 8: Write the failing styles.json assertion in `ref.rs`**

Append to `packages/terminal/crates/vt-core/tests/ref.rs`:

```rust
#[derive(Deserialize)]
struct StylesExpectation {
    rows: Vec<Vec<(usize, usize, u16, u32)>>,
}

fn styled_segments(core: &TerminalCore) -> Vec<Vec<(usize, usize, u16, u32)>> {
    let snapshot = core.snapshot().expect("snapshot");
    let mut rows = Vec::new();
    for index in 0..snapshot.row_count() {
        let text = snapshot.row_text(index);
        let char_at = |byte: usize| text[..byte.min(text.len())].chars().count();
        let mut segments: Vec<(usize, usize, u16, u32)> = Vec::new();
        let mut start = 0usize;
        for &(end, style) in snapshot.row_style_pairs(index) {
            let end = end as usize;
            let attrs = style.attrs.bits();
            let underline = style.underline.value();
            if attrs != 0 || underline != vt_core::StyleCode::DEFAULT.value() {
                let (from, to) = (char_at(start), char_at(end));
                match segments.last_mut() {
                    Some(last) if last.1 == from && last.2 == attrs && last.3 == underline => last.1 = to,
                    _ => segments.push((from, to, attrs, underline)),
                }
            }
            start = end;
        }
        rows.push(segments);
    }
    while rows.last().is_some_and(|row| row.is_empty()) {
        rows.pop();
    }
    rows
}
```

and, at the end of `ref_test` (after the cursor assertion):

```rust
    let styles_path = dir.join("styles.json");
    if styles_path.exists() {
        let expected: StylesExpectation =
            serde_json::from_str(&fs::read_to_string(&styles_path).expect("styles.json"))
                .expect("styles.json");
        let got = styled_segments(&core);
        assert_eq!(
            got, expected.rows,
            "styled segments differ from styles.json (rows of [start_char, end_char, attrs, underline])"
        );
    }
```

Then create a deliberately wrong placeholder to see the assertion bite: `echo '{"rows":[[[0,1,1,255]]]}' > /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/tests/ref/sgr/styles.json` and run `cargo test -p vt-core --test ref sgr` → FAIL with the segment diff. Delete that placeholder.

- [ ] **Step 9: Generate `styles.json` from Alacritty's `grid.json`**

Extend `packages/terminal/tools/import-alacritty-ref.py` with a `--styles` mode (the import of recordings is unchanged):

```python
FLAG_BITS = {
    "ITALIC": 1 << 0,
    "UNDERLINE": 1 << 1,
    "DOUBLE_UNDERLINE": 1 << 2,
    "UNDERCURL": 1 << 3,
    "DOTTED_UNDERLINE": 1 << 4,
    "DASHED_UNDERLINE": 1 << 5,
    "STRIKEOUT": 1 << 6,
    "HIDDEN": 1 << 8,
}
TAG_INDEXED = 0x0100_0000
TAG_RGB = 0x0200_0000
DEFAULT_UNDERLINE = 255


def underline_code(extra):
    colour = (extra or {}).get("underline_color")
    if not colour:
        return DEFAULT_UNDERLINE
    if "Spec" in colour:
        spec = colour["Spec"]
        return TAG_RGB | (spec["r"] << 16) | (spec["g"] << 8) | spec["b"]
    if "Indexed" in colour:
        index = colour["Indexed"]
        return index if index < 16 else TAG_INDEXED | index
    return DEFAULT_UNDERLINE


def cell_is_blank(cell):
    return (
        cell["c"] == " "
        and not (cell.get("flags") or "")
        and cell["fg"] == {"Named": "Foreground"}
        and cell["bg"] == {"Named": "Background"}
        and not (cell.get("extra") or {}).get("zerowidth")
    )


def row_segments(line):
    cells = [cell for cell in line["inner"] if "WIDE_CHAR_SPACER" not in (cell.get("flags") or "")]
    while cells and cell_is_blank(cells[-1]):
        cells.pop()
    segments = []
    for index, cell in enumerate(cells):
        attrs = 0
        for flag in (cell.get("flags") or "").split("|"):
            attrs |= FLAG_BITS.get(flag.strip(), 0)
        underline = underline_code(cell.get("extra"))
        if attrs == 0 and underline == DEFAULT_UNDERLINE:
            continue
        if segments and segments[-1][1] == index and segments[-1][2] == attrs and segments[-1][3] == underline:
            segments[-1][1] = index + 1
        else:
            segments.append([index, index + 1, attrs, underline])
    return segments


def write_styles(name):
    with open(os.path.join(SOURCE, name, "grid.json")) as handle:
        grid = json.load(handle)
    raw = grid["raw"]
    assert raw["zero"] == 0
    rows = [row_segments(line) for line in reversed(raw["inner"])]
    while rows and not rows[-1]:
        rows.pop()
    with open(os.path.join(TARGET, name, "styles.json"), "w") as handle:
        json.dump({"rows": rows}, handle)
```

and in `main()`: `if "--styles" in sys.argv: for name in sys.argv[sys.argv.index("--styles") + 1:]: write_styles(name); return 0`. Run:

```bash
python3 /Users/omaraly/development/AI/Operator/packages/terminal/tools/import-alacritty-ref.py --styles sgr underline colored_underline clear_underline
```

`FLAG_BITS` has no `BLINK`/`OVERLINE` entries because Alacritty's `Flags` (`alacritty_terminal/src/term/cell.rs:22-40`) has none; those two attributes are covered by `sgr_attributes.rs` only. Note that `styles.json` lists rows top→bottom exactly as `ref.rs` numbers snapshot rows (`TRIAGE.md`: these four recordings differ from Alacritty only by blank-row padding at the bottom, which both sides drop).

- [ ] **Step 10: Run the corpus**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test ref`
Expected: PASS for all 46 including the four with `styles.json`. If `colored_underline` differs only by a combining-mark cell (Alacritty stores `extra.zerowidth` on the base cell; our text keeps the mark, so `char_at` counts one more char), fix the expectation generator to count the zero-width scalars of `extra.zerowidth` into the char index (`index + len(zerowidth)` accumulated) — the tool is the side that owns the char count, never the assertion.

- [ ] **Step 11: Full verification**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` → clean, PASS.
- `npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.
- `npm run bench:selection` → PASS.
- `npm run bench:feel` → `PASS feel gate: zero pixel diff` (the renderer still reads words 0–2 only).
- `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...` → PASS (bar the pre-existing `TestProcessEnvironmentLetsOverridesWin`).
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → clean.
- `cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon` → `frontend/daemon/opr` rebuilt.

- [ ] **Step 12: CHANGELOG**

Under "Unreleased" in `packages/terminal/CHANGELOG.md`:

```markdown
- vt-core: SGR 3, 4 and `4:0-5`, 5/6, 8, 9, 21, 23, 24, 25, 28, 29, 53, 55, 58 and 59 are parsed into `CellStyle.attrs` (`Attrs`, ten bits after `alacritty_terminal/src/term/cell.rs` `Flags`) and `CellStyle.underline`; the style run grows to five words `(end, fg, bg, attrs, underline)` — `STYLE_RUN_WORDS = 5` in `vt-wasm` and `@operator/terminal-core`. The renderer still paints words 0–2 only, so nothing is drawn differently until `RendererFeatures.attributes` is `"warp"`. The mirror re-emits the attributes in the attach replay, and the Alacritty `sgr`, `underline`, `colored_underline` and `clear_underline` recordings now assert a `styles.json` derived from Alacritty's own grid.
```

- [ ] **Step 13: Commit (one commit)**

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates packages/terminal/tools packages/terminal/ts/core/src packages/terminal/ts/renderer-dom/src packages/terminal/CHANGELOG.md backend/internal/adapters/runtime/ptyhost/vtwasm/replay_test.go backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && git commit -m "vt-core: SGR attributes and underline colour in the style word, five-word style runs

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

### Task 4: Render SGR attributes behind `attributes: "warp"`

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/attributes.ts`
- Create: `packages/terminal/ts/renderer-dom/src/attributes.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/row-builder.ts` (`buildRowNode` gains `features`)
- Modify: `packages/terminal/ts/renderer-dom/src/block-body.ts` (`BlockBodyInput.features`)
- Modify: `packages/terminal/ts/renderer-dom/src/alt-surface.ts` (`renderAltSurface` gains `features`; fingerprint includes `attributes`)
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` (passes `this.activeFeatures`)
- Modify: `packages/terminal/ts/renderer-dom/src/styles.css`, `styles.ts` (identical copies), `styles-parity.test.ts`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `STYLE_RUN_WORDS`, `ATTR_*`, `STYLE_DEFAULT_UNDERLINE` (Task 3), `styleCodeToCssVar` (`style-code.ts`), `RendererFeatures` (Task 2).
- Produces: `decorationAttributes(attrs: number, underlineCode: number): Decorations` where `Decorations = { italic: boolean; hidden: boolean; blink: boolean; underline: "single" | "double" | "curly" | "dotted" | "dashed" | null; decor: "u" | "s" | "o" | "us" | "uo" | "so" | "uso" | null; underlineColour: string | null }`; `applyAttributes(run: HTMLElement, attrs: number, underlineCode: number): boolean` (returns whether the run is underlined, so the caller substitutes `\xa0`); `underlinedText(text: string): string`; `CLASS_BLINK = "terminal-blink"`; DOM contract on `.terminal-run`: `data-italic`, `data-hidden`, `data-underline="<style>"`, `data-decor="<u|s|o combination>"`, `--terminal-underline` custom property, class `terminal-blink`; `buildRowNode(source, row, label, decoder, cellWidth = 0, features = DEFAULT_FEATURES)`; `renderAltSurface(view, root, decoder, metrics, features = DEFAULT_FEATURES)`.

Attributes are expressed as data attributes plus stylesheet rules rather than inline `text-decoration-*` properties because jsdom's `CSSStyleDeclaration` does not round-trip `text-decoration-style`/`-thickness`, so a test could not read back an inline value that a browser would honour; data attributes are readable everywhere and keep the run's inline style to colour, weight and opacity as today.

- [ ] **Step 1: Write the failing tests**

`packages/terminal/ts/renderer-dom/src/attributes.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
	ATTR_BLINK,
	ATTR_CURLY_UNDERLINE,
	ATTR_DOUBLE_UNDERLINE,
	ATTR_HIDDEN,
	ATTR_ITALIC,
	ATTR_OVERLINE,
	ATTR_STRIKE,
	ATTR_UNDERLINE,
	STYLE_DEFAULT_UNDERLINE,
} from "@operator/terminal-core";
import { applyAttributes, CLASS_BLINK, decorationAttributes, underlinedText } from "./attributes";
import { buildRowNode, type RowSource } from "./row-builder";
import { DEFAULT_FEATURES } from "./features";

const RGB_MAGENTA = 0x0200_0000 | (255 << 16) | 255;

function rowOf(text: string, attrs: number, underline = STYLE_DEFAULT_UNDERLINE, features = DEFAULT_FEATURES): HTMLElement {
	const content = new TextEncoder().encode(text);
	const source: RowSource = {
		content,
		rows: Uint32Array.from([0, content.byteLength]),
		runRanges: Uint32Array.from([0, 1]),
		stylePairs: Uint32Array.from([content.byteLength, 255, 254, attrs, underline]),
	};
	return buildRowNode(source, 0, 0, new TextDecoder("utf-8", { fatal: true }), 8, features);
}

describe("decorationAttributes", () => {
	it("maps each bit to its decoration", () => {
		expect(decorationAttributes(ATTR_ITALIC, STYLE_DEFAULT_UNDERLINE)).toMatchObject({ italic: true, underline: null, decor: null });
		expect(decorationAttributes(ATTR_UNDERLINE, STYLE_DEFAULT_UNDERLINE)).toMatchObject({ underline: "single", decor: "u" });
		expect(decorationAttributes(ATTR_DOUBLE_UNDERLINE, STYLE_DEFAULT_UNDERLINE).underline).toBe("double");
		expect(decorationAttributes(ATTR_CURLY_UNDERLINE | ATTR_STRIKE | ATTR_OVERLINE, STYLE_DEFAULT_UNDERLINE)).toMatchObject({ underline: "curly", decor: "uso" });
		expect(decorationAttributes(ATTR_STRIKE, STYLE_DEFAULT_UNDERLINE).decor).toBe("s");
		expect(decorationAttributes(ATTR_HIDDEN | ATTR_BLINK, STYLE_DEFAULT_UNDERLINE)).toMatchObject({ hidden: true, blink: true });
	});

	it("resolves an explicit underline colour and leaves the default to currentColor", () => {
		expect(decorationAttributes(ATTR_UNDERLINE, RGB_MAGENTA).underlineColour).toBe("rgb(255 0 255)");
		expect(decorationAttributes(ATTR_UNDERLINE, STYLE_DEFAULT_UNDERLINE).underlineColour).toBeNull();
	});

	it("keeps an underline visible across spaces with no-break spaces", () => {
		expect(underlinedText("a b")).toBe("a b");
	});
});

describe("row attributes under attributes: warp", () => {
	const warp = { ...DEFAULT_FEATURES, attributes: "warp" as const };

	it("marks the run with data attributes and the underline colour", () => {
		const run = rowOf("x y", ATTR_ITALIC | ATTR_CURLY_UNDERLINE | ATTR_STRIKE, RGB_MAGENTA, warp).querySelector<HTMLElement>(".terminal-run")!;
		expect(run.dataset.italic).toBe("");
		expect(run.dataset.underline).toBe("curly");
		expect(run.dataset.decor).toBe("us");
		expect(run.style.getPropertyValue("--terminal-underline")).toBe("rgb(255 0 255)");
		expect(run.textContent).toBe("x y");
	});

	it("hides a hidden run and tags a blinking one", () => {
		const run = rowOf("secret", ATTR_HIDDEN | ATTR_BLINK, STYLE_DEFAULT_UNDERLINE, warp).querySelector<HTMLElement>(".terminal-run")!;
		expect(run.dataset.hidden).toBe("");
		expect(run.classList.contains(CLASS_BLINK)).toBe(true);
		expect(run.textContent).toBe("secret");
	});

	it("does nothing under the plain default", () => {
		const run = rowOf("x y", ATTR_ITALIC | ATTR_UNDERLINE | ATTR_STRIKE | ATTR_HIDDEN | ATTR_BLINK, RGB_MAGENTA).querySelector<HTMLElement>(".terminal-run")!;
		expect(Object.keys(run.dataset)).toEqual(["terminalRun"]);
		expect(run.className).toBe("terminal-run");
		expect(run.style.getPropertyValue("--terminal-underline")).toBe("");
		expect(run.textContent).toBe("x y");
	});

	it("applyAttributes reports whether the run is underlined", () => {
		const run = document.createElement("span");
		expect(applyAttributes(run, ATTR_STRIKE, STYLE_DEFAULT_UNDERLINE)).toBe(false);
		expect(applyAttributes(run, ATTR_UNDERLINE, STYLE_DEFAULT_UNDERLINE)).toBe(true);
	});
});
```

Add to `styles-parity.test.ts`:

```ts
	it("draws every SGR decoration from data attributes, with Warp's underline thickness", () => {
		for (const rule of [
			".terminal-run[data-italic]",
			".terminal-run[data-hidden]",
			'.terminal-run[data-underline="double"]',
			'.terminal-run[data-underline="curly"]',
			'.terminal-run[data-underline="dotted"]',
			'.terminal-run[data-underline="dashed"]',
			'.terminal-run[data-decor="uso"]',
			"--terminal-underline",
			"text-decoration-thickness: 0.09em",
		]) {
			expect(terminalStyles).toContain(rule);
		}
		expect(terminalStyles).not.toContain("@keyframes");
	});
```

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/attributes.test.ts src/styles-parity.test.ts`
Expected: FAIL — `./attributes` missing; the parity rules absent.

- [ ] **Step 3: Implement**

`packages/terminal/ts/renderer-dom/src/attributes.ts`:

```ts
import {
	ATTR_BLINK,
	ATTR_CURLY_UNDERLINE,
	ATTR_DASHED_UNDERLINE,
	ATTR_DOTTED_UNDERLINE,
	ATTR_DOUBLE_UNDERLINE,
	ATTR_HIDDEN,
	ATTR_ITALIC,
	ATTR_OVERLINE,
	ATTR_STRIKE,
	ATTR_UNDERLINE,
	STYLE_DEFAULT_UNDERLINE,
} from "@operator/terminal-core";
import { styleCodeToCssVar } from "./style-code.js";

export const CLASS_BLINK = "terminal-blink";

export type UnderlineStyle = "single" | "double" | "curly" | "dotted" | "dashed";

export type Decorations = Readonly<{
	italic: boolean;
	hidden: boolean;
	blink: boolean;
	underline: UnderlineStyle | null;
	decor: string | null;
	underlineColour: string | null;
}>;

const UNDERLINES: readonly (readonly [number, UnderlineStyle])[] = [
	[ATTR_UNDERLINE, "single"],
	[ATTR_DOUBLE_UNDERLINE, "double"],
	[ATTR_CURLY_UNDERLINE, "curly"],
	[ATTR_DOTTED_UNDERLINE, "dotted"],
	[ATTR_DASHED_UNDERLINE, "dashed"],
];

export function decorationAttributes(attrs: number, underlineCode: number): Decorations {
	const underline = UNDERLINES.find(([bit]) => (attrs & bit) !== 0)?.[1] ?? null;
	const decor = `${underline ? "u" : ""}${attrs & ATTR_STRIKE ? "s" : ""}${attrs & ATTR_OVERLINE ? "o" : ""}`;
	return {
		italic: (attrs & ATTR_ITALIC) !== 0,
		hidden: (attrs & ATTR_HIDDEN) !== 0,
		blink: (attrs & ATTR_BLINK) !== 0,
		underline,
		decor: decor === "" ? null : decor,
		underlineColour: underlineCode === STYLE_DEFAULT_UNDERLINE ? null : styleCodeToCssVar(underlineCode),
	};
}

export function applyAttributes(run: HTMLElement, attrs: number, underlineCode: number): boolean {
	const decorations = decorationAttributes(attrs, underlineCode);
	if (decorations.italic) run.dataset.italic = "";
	if (decorations.hidden) run.dataset.hidden = "";
	if (decorations.blink) run.classList.add(CLASS_BLINK);
	if (decorations.underline) run.dataset.underline = decorations.underline;
	if (decorations.decor) run.dataset.decor = decorations.decor;
	if (decorations.underlineColour) run.style.setProperty("--terminal-underline", decorations.underlineColour);
	return decorations.underline !== null;
}

// xterm.js src/browser/renderer/dom/DomRendererRowFactory.ts:176-184
export function underlinedText(text: string): string {
	return text.replaceAll(" ", " ");
}
```

`row-builder.ts`: import `DEFAULT_FEATURES, type RendererFeatures` from `./features.js` and `applyAttributes, underlinedText` from `./attributes.js`; add the sixth parameter `features: RendererFeatures = DEFAULT_FEATURES`; inside the pair loop after the dim branch:

```ts
		let text = decoder.decode(slice);
		if (features.attributes === "warp") {
			const attrs = stylePairs[elementIndex + 3] ?? 0;
			const underlineCode = stylePairs[elementIndex + 4] ?? STYLE_DEFAULT_UNDERLINE;
			if (applyAttributes(run, attrs, underlineCode)) text = underlinedText(text);
		}
		appendRunText(run, text, foreground);
```

(replacing the existing `appendRunText(run, decoder.decode(slice), foreground);`; import `STYLE_DEFAULT_UNDERLINE` beside `STYLE_RUN_WORDS`).

`block-body.ts`: add `features: RendererFeatures;` to `BlockBodyInput` and pass `input.features` as the sixth argument of `buildRowNode`. `alt-surface.ts`: `renderAltSurface(view, root, decoder, metrics, features: RendererFeatures = DEFAULT_FEATURES)`; `replaceRows(source, into, rowCount, decoder, features)` calls `buildRowNode(source, row, row, decoder, 0, features)`; `RowFingerprint` gains `attributes: RendererFeatures["attributes"]`, `fingerprintRow` records it and `rowMatches` returns false when it differs. `dom-block-renderer.ts`: pass `features: this.activeFeatures` in the `populateBlock` input (line 614 area) and as the fifth argument of `renderAltSurface` (line 511).

`styles.css` (and the identical block in `styles.ts`), after the `.terminal-run` rule:

```css
/* SGR decorations, drawn only when RendererFeatures.attributes is "warp".
   Thickness follows Warp's UNDERLINE_THICKNESS_SCALE_FACTOR = 0.15 of the
   cell width (app/src/terminal/grid_renderer.rs:52,2352); Hack's advance is
   0.6em, so 0.09em. Blink gets a class and no animation: Warp's
   ansi_handler.rs terminal_attribute has no Blink arm. */
.terminal-run[data-italic] {
	font-style: italic;
}

.terminal-run[data-hidden] {
	visibility: hidden;
}

.terminal-run[data-underline] {
	text-decoration-thickness: 0.09em;
	text-decoration-color: var(--terminal-underline, currentColor);
}

.terminal-run[data-underline="double"] {
	text-decoration-style: double;
}

.terminal-run[data-underline="curly"] {
	text-decoration-style: wavy;
}

.terminal-run[data-underline="dotted"] {
	text-decoration-style: dotted;
}

.terminal-run[data-underline="dashed"] {
	text-decoration-style: dashed;
}

.terminal-run[data-decor="u"] {
	text-decoration-line: underline;
}

.terminal-run[data-decor="s"] {
	text-decoration-line: line-through;
}

.terminal-run[data-decor="o"] {
	text-decoration-line: overline;
}

.terminal-run[data-decor="us"] {
	text-decoration-line: underline line-through;
}

.terminal-run[data-decor="uo"] {
	text-decoration-line: underline overline;
}

.terminal-run[data-decor="so"] {
	text-decoration-line: line-through overline;
}

.terminal-run[data-decor="uso"] {
	text-decoration-line: underline line-through overline;
}
```

The comment above is a reference citation (repository and path), the one kind of new comment permitted.

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run` → PASS (all files, including `styles-parity`).

- [ ] **Step 5: Verify, side-by-side, feel gate**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.
- `npm run bench:selection` → PASS (row DOM structure gained attributes on runs).
- `npm run bench:feel` → `PASS feel gate: zero pixel diff`.
- `npm run bench:feel -- --feature attributes=warp` → side-by-side screenshots under `baselines/{claude-spinner-10s,claude-long-50k,glyph-probe}/feature-attributes_warp/`. Open `baselines/glyph-probe/feature-attributes_warp/offset-0.png` with the Read tool and confirm the `attrs:` row shows italic, single/double/wavy/dotted/dashed underlines, strikethrough, the hidden word absent, an overline and a magenta underline; the two Claude fixtures show whether Claude Code uses any of these (the spec left that "not measured" — write what you see into the CHANGELOG entry below).
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → clean.

- [ ] **Step 6: CHANGELOG and commit**

```markdown
- renderer-dom: `RendererFeatures.attributes: "warp"` paints italic, underline (single/double/curly/dotted/dashed with SGR 58 colour), strikethrough, overline and hidden from the style word's attribute bits, and tags blink with `terminal-blink` without animating it (Warp ignores SGR 5). Default `"plain"` paints exactly as before. Side-by-side: `bench/agent-session/baselines/*/feature-attributes_warp/`. In the two Claude Code fixtures the attributes present are: <list what the side-by-side shows, or "none">.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom/src packages/terminal/bench/agent-session/baselines packages/terminal/CHANGELOG.md && git commit -m "renderer-dom: SGR decorations behind RendererFeatures.attributes = warp

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Grapheme clusters in the core behind `set_grapheme_clusters`, with the Unicode corpus

**Files:**
- Modify: `packages/terminal/Cargo.toml` (workspace dep `unicode-segmentation = "=1.13.3"`), `crates/vt-core/Cargo.toml`, `Cargo.lock`
- Create: `packages/terminal/crates/vt-core/src/width.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs` (`pub mod width`, re-exports, `set_grapheme_clusters`/`grapheme_clusters`, history `begin` gets the mode)
- Modify: `packages/terminal/crates/vt-core/src/parser.rs` (`width_mode` field, `set_width_mode`, `enter_alt` at :289-300, `rewrap_hot` call at :491, `rows_for` call at :634)
- Modify: `packages/terminal/crates/vt-core/src/screen.rs` (`width_mode` field + setter, `print` at :409, `join_previous`, `cell_width_at`, `push_zerowidth` → `append_scalar`)
- Modify: `packages/terminal/crates/vt-core/src/row_index.rs` (`rewrap_hot`, `rows_for`, `rewrap`, `push_line` take `WidthMode`; the loop at :344-368 walks clusters)
- Modify: `packages/terminal/crates/vt-core/src/history.rs` (`begin(first_stable_row, rows, cols, mode)`)
- Create: `packages/terminal/crates/vt-core/tests/grapheme_clusters.rs`
- Create: `packages/terminal/crates/vt-core/tests/grapheme_break_test.rs`
- Create: `packages/terminal/crates/vt-core/tests/grapheme/GraphemeBreakTest.json`, `tests/grapheme/GRAPHEME-ATTRIBUTION.md`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs` (`set_grapheme_clusters`, `grapheme_clusters`)
- Modify: `packages/terminal/ts/core/src/terminal-core.ts`, `ts/core/src/terminal-core.test.ts`
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx` (features effect also sets the core mode)
- Modify: `packages/terminal/bench/agent-session/main.ts` (`graphemes` in `?features=` sets the core mode)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `unicode_segmentation::UnicodeSegmentation::{grapheme_indices, graphemes}` (Unicode 17.0.0, `unicode-segmentation-1.13.3/src/tables.rs:17`), `unicode_width::UnicodeWidthStr::width` (Unicode 17.0.0, `unicode-width-0.2.2/src/tables.rs:165`; its documented rules give ZWJ sequences, modifier sequences and presentation sequences width 2), `ScreenGrid::attach_zerowidth` (`screen.rs:436`), `Cell::push_zerowidth` (`screen.rs:72`).
- Produces: `pub enum WidthMode { Scalar, Grapheme }` (`Default` = `Scalar`), `pub struct Cluster { pub start: usize, pub end: usize, pub width: usize }`, `pub fn clusters(text: &str, mode: WidthMode) -> Vec<Cluster>` (Scalar: one cluster per scalar with zero-width scalars folded into the previous cluster; Grapheme: one per extended grapheme cluster, width = `UnicodeWidthStr::width`), `pub(crate) fn joins_previous(previous: &str, ch: char) -> bool`, `pub(crate) fn cluster_width(text: &str) -> usize`; `TerminalCore::set_grapheme_clusters(on: bool)`, `TerminalCore::grapheme_clusters() -> bool`, `Parser::set_width_mode(mode)`, `Parser::width_mode()`; wasm `set_grapheme_clusters(on)` / `grapheme_clusters()`; TS `TerminalCore.setGraphemeClusters(on: boolean)`, `graphemeClusters(): boolean`. Task 6's export uses `clusters(text, parser.width_mode())` for history rows.

Verified on this machine before writing the plan (`unicode-width` 0.2.2 + `unicode-segmentation` 1.13.3): `"👨‍👩‍👧"` str width 2 / 1 grapheme (scalars 2,0,2,0,2); `"❤️"` 2 / 1 (1,0); `"👋🏽"` 2 / 1 (2,2); `"🇪🇬"` 2 / 1 (1,1); `"🚀"` 2; `"e\u{301}"` 1 / 1. These are the numbers the tests below assert.

- [ ] **Step 1: Copy the corpus with attribution**

```bash
mkdir -p /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/tests/grapheme && cp /Users/omaraly/development/AI/kitty/kitty_tests/GraphemeBreakTest.json /Users/omaraly/development/AI/Operator/packages/terminal/crates/vt-core/tests/grapheme/GraphemeBreakTest.json && cd /Users/omaraly/development/AI/kitty && git rev-parse --short HEAD
```

`packages/terminal/crates/vt-core/tests/grapheme/GRAPHEME-ATTRIBUTION.md`:

```markdown
# Grapheme break corpus

`GraphemeBreakTest.json` is the Unicode Character Database's
`GraphemeBreakTest.txt` (Unicode 17.0.0, © Unicode, Inc., used under the
Unicode License v3, https://www.unicode.org/license.txt) in the JSON form
kitty ships at `kitty_tests/GraphemeBreakTest.json` (https://github.com/kovidgoyal/kitty,
commit `<the hash printed above>`): each entry's `data` is the list of
extended grapheme clusters the standard defines for that case, and `comment`
is the standard's own annotation. Only the data file is copied; kitty's own
code (GPL-3.0) is not.

`tests/grapheme_break_test.rs` asserts that `vt_core::clusters(text, WidthMode::Grapheme)`
splits every case exactly as `data` does. `unicode-segmentation` 1.13.3 tracks
Unicode 17.0.0 (`src/tables.rs:17`), the same version as the corpus; a
failure after a crate upgrade is version drift and is reported, not patched.
```

- [ ] **Step 2: Write the failing tests**

`packages/terminal/crates/vt-core/tests/grapheme_break_test.rs`:

```rust
use std::fs;
use std::path::Path;

use serde::Deserialize;
use vt_core::{clusters, WidthMode};

#[derive(Deserialize)]
struct Case {
    data: Vec<String>,
    comment: String,
}

#[test]
fn every_case_in_the_unicode_grapheme_break_corpus_splits_as_the_standard_says() {
    let path = Path::new(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/grapheme/GraphemeBreakTest.json"
    ));
    let cases: Vec<Case> =
        serde_json::from_str(&fs::read_to_string(path).expect("corpus")).expect("corpus json");
    assert!(cases.len() > 700, "corpus has {} cases", cases.len());
    let mut failures = Vec::new();
    for case in &cases {
        let text: String = case.data.concat();
        let got: Vec<&str> = clusters(&text, WidthMode::Grapheme)
            .iter()
            .map(|cluster| &text[cluster.start..cluster.end])
            .collect();
        let want: Vec<&str> = case.data.iter().map(String::as_str).collect();
        if got != want {
            failures.push(format!("{}\n  want {want:?}\n  got  {got:?}", case.comment));
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} cases differ:\n{}",
        failures.len(),
        cases.len(),
        failures.join("\n")
    );
}

#[test]
fn scalar_mode_folds_zero_width_scalars_into_the_previous_cluster() {
    let text = "e\u{301}x";
    let got: Vec<(usize, usize, usize)> = clusters(text, WidthMode::Scalar)
        .iter()
        .map(|c| (c.start, c.end, c.width))
        .collect();
    assert_eq!(got, vec![(0, 3, 1), (3, 4, 1)]);
    let family = "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}";
    assert_eq!(clusters(family, WidthMode::Scalar).len(), 3);
    assert_eq!(clusters(family, WidthMode::Grapheme).len(), 1);
    assert_eq!(clusters(family, WidthMode::Grapheme)[0].width, 2);
}
```

`packages/terminal/crates/vt-core/tests/grapheme_clusters.rs`:

```rust
use vt_core::TerminalCore;

const FAMILY: &str = "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}";

fn core(columns: usize, rows: usize, graphemes: bool) -> TerminalCore {
    let mut core = TerminalCore::new(columns, 100).expect("core");
    core.resize(columns, rows);
    core.set_grapheme_clusters(graphemes);
    core
}

fn cursor_after(input: &str, graphemes: bool) -> u32 {
    let mut core = core(20, 5, graphemes);
    core.feed(input.as_bytes());
    core.snapshot().expect("snapshot").cursor_col
}

fn alt_cell(input: &str, col: usize, graphemes: bool) -> char {
    let mut core = core(20, 5, graphemes);
    core.feed(b"\x1b[?1049h");
    core.feed(input.as_bytes());
    core.alt_grid().expect("alt").cell(0, col).ch
}

#[test]
fn the_mode_defaults_off_and_is_reported() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    assert!(!core.grapheme_clusters());
    core.set_grapheme_clusters(true);
    assert!(core.grapheme_clusters());
}

#[test]
fn a_zwj_family_occupies_two_cells_with_clusters_on_and_six_off() {
    assert_eq!(cursor_after(FAMILY, true), 2);
    assert_eq!(cursor_after(FAMILY, false), 6);
    assert_eq!(alt_cell(FAMILY, 1, true), '\0');
    assert_eq!(alt_cell(FAMILY, 2, true), ' ');
}

#[test]
fn vs16_widens_a_text_presentation_heart() {
    assert_eq!(cursor_after("\u{2764}\u{fe0f}x", true), 3);
    assert_eq!(cursor_after("\u{2764}\u{fe0f}x", false), 2);
    assert_eq!(alt_cell("\u{2764}\u{fe0f}x", 1, true), '\0');
    assert_eq!(alt_cell("\u{2764}\u{fe0f}x", 2, true), 'x');
}

#[test]
fn a_skin_tone_modifier_joins_its_base() {
    assert_eq!(cursor_after("\u{1f44b}\u{1f3fd}", true), 2);
    assert_eq!(cursor_after("\u{1f44b}\u{1f3fd}", false), 4);
}

#[test]
fn a_regional_indicator_pair_is_one_wide_cell() {
    assert_eq!(cursor_after("\u{1f1ea}\u{1f1ec}", true), 2);
    assert_eq!(alt_cell("\u{1f1ea}\u{1f1ec}", 1, true), '\0');
    assert_eq!(alt_cell("\u{1f1ea}\u{1f1ec}", 1, false), '\u{1f1ec}');
}

#[test]
fn a_combining_mark_still_attaches_and_a_leading_mark_still_lands_on_a_blank() {
    let mut core = core(20, 5, true);
    core.feed("e\u{301}\u{301}".as_bytes());
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "e\u{301}\u{301}");
    assert_eq!(snapshot.cursor_col, 1);
    let mut core = core(20, 5, true);
    core.feed("\u{301}".as_bytes());
    assert_eq!(core.snapshot().expect("snapshot").row_text(0), " \u{301}");
}

#[test]
fn widening_in_the_last_column_keeps_the_cell_narrow() {
    let mut core = core(3, 5, true);
    core.feed("ab\u{2764}\u{fe0f}".as_bytes());
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "ab\u{2764}\u{fe0f}");
    assert_eq!(snapshot.row_count(), 1);
    assert_eq!(snapshot.cursor_col, 2);
}

#[test]
fn rewrap_measures_a_family_as_two_cells_with_clusters_on() {
    for (graphemes, rows) in [(true, 1), (false, 2)] {
        let mut core = core(20, 2, graphemes);
        core.feed(format!("xxxx{FAMILY}yy\r\nsecond\r\nthird\r\n").as_bytes());
        core.resize(10, 2);
        let snapshot = core.snapshot().expect("snapshot");
        let family_rows = (0..snapshot.row_count())
            .filter(|index| snapshot.row_text(*index).contains("xxxx") || snapshot.row_text(*index).contains("yy"))
            .count();
        assert_eq!(family_rows, rows, "graphemes={graphemes}");
        assert_eq!(core.verify_integrity(), Ok(()));
    }
}

#[test]
fn a_combining_mark_after_a_space_stays_with_the_space_on_rewrap_in_both_modes() {
    for graphemes in [false, true] {
        let mut core = core(8, 2, graphemes);
        core.feed("ab \u{301}cdef\r\nsecond\r\nthird\r\n".as_bytes());
        core.resize(3, 2);
        let snapshot = core.snapshot().expect("snapshot");
        for index in 0..snapshot.row_count() {
            assert!(!snapshot.row_text(index).starts_with('\u{301}'), "graphemes={graphemes} row {index}");
        }
    }
}

#[test]
fn a_history_chunk_is_laid_out_in_the_cores_width_mode() {
    for (graphemes, rows) in [(true, 2), (false, 1)] {
        let mut core = TerminalCore::new(20, 10_000).expect("core");
        core.set_grapheme_clusters(graphemes);
        core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\live\r\n");
        core.feed(b"\x1b]7000;v=1;history=999,1\x1b\\");
        core.feed("\u{2764}\u{fe0f}x\r\n".as_bytes());
        core.resize(2, 24);
        let snapshot = core.snapshot().expect("snapshot");
        let heart_rows = (0..snapshot.row_count())
            .filter(|index| {
                let text = snapshot.row_text(*index);
                text.contains('\u{2764}') || text == "x"
            })
            .count();
        assert_eq!(heart_rows, rows, "graphemes={graphemes}");
    }
}
```

- [ ] **Step 3: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test grapheme_break_test --test grapheme_clusters`
Expected: compile errors — no `clusters`, `WidthMode`, `set_grapheme_clusters`.

- [ ] **Step 4: Implement `width.rs` and the mode plumbing**

`Cargo.toml` (workspace): add `unicode-segmentation = "=1.13.3"` under `[workspace.dependencies]`; `crates/vt-core/Cargo.toml`: `unicode-segmentation = { workspace = true }`. Run `cargo fetch --offline` to confirm the registry copy resolves (it is in `~/.cargo/registry/src/index.crates.io-*/unicode-segmentation-1.13.3`).

`packages/terminal/crates/vt-core/src/width.rs`:

```rust
use unicode_segmentation::UnicodeSegmentation;
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum WidthMode {
    #[default]
    Scalar,
    Grapheme,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Cluster {
    pub start: usize,
    pub end: usize,
    pub width: usize,
}

pub fn clusters(text: &str, mode: WidthMode) -> Vec<Cluster> {
    match mode {
        WidthMode::Grapheme => text
            .grapheme_indices(true)
            .map(|(start, grapheme)| Cluster {
                start,
                end: start + grapheme.len(),
                width: cluster_width(grapheme),
            })
            .collect(),
        WidthMode::Scalar => {
            let mut out: Vec<Cluster> = Vec::new();
            for (start, ch) in text.char_indices() {
                let end = start + ch.len_utf8();
                let width = UnicodeWidthChar::width(ch).unwrap_or(0);
                match out.last_mut() {
                    Some(last) if width == 0 => last.end = end,
                    _ => out.push(Cluster { start, end, width }),
                }
            }
            out
        }
    }
}

pub(crate) fn cluster_width(text: &str) -> usize {
    UnicodeWidthStr::width(text)
}

pub(crate) fn joins_previous(previous: &str, ch: char) -> bool {
    if previous.is_empty() || (ch.is_ascii() && previous.is_ascii()) {
        return false;
    }
    let mut joined = String::with_capacity(previous.len() + ch.len_utf8());
    joined.push_str(previous);
    joined.push(ch);
    joined.graphemes(true).nth(1).is_none()
}
```

`lib.rs`: `pub mod width;` and `pub use width::{clusters, Cluster, WidthMode};`; on `TerminalCore`:

```rust
    pub fn set_grapheme_clusters(&mut self, on: bool) {
        self.parser.set_width_mode(if on { WidthMode::Grapheme } else { WidthMode::Scalar });
    }

    pub fn grapheme_clusters(&self) -> bool {
        self.parser.width_mode() == WidthMode::Grapheme
    }
```

and at `lib.rs:246` pass `self.parser.width_mode()` as a fourth argument to `self.history.begin(…)`.

`parser.rs`: field `width_mode: WidthMode` (default in `new`), `pub fn width_mode(&self) -> WidthMode`, `pub fn set_width_mode(&mut self, mode: WidthMode)` that stores it, calls `self.screen.set_width_mode(mode)` and `alt.set_width_mode(mode)` on `self.alt` if present; `enter_alt` (`:289-300`) calls `alt.set_width_mode(self.width_mode)` after `set_clear_policy`; the `rewrap_hot` call (`:491`) and `rows_for` call (`:634`) pass `self.width_mode`.

`screen.rs`: field `width_mode: WidthMode` (init `WidthMode::default()` in `new`), `pub fn set_width_mode(&mut self, mode: WidthMode)`; rename `Cell::push_zerowidth` to `Cell::append_scalar` (same body; update `attach_zerowidth`'s call); replace `print`:

```rust
    pub fn print(&mut self, ch: char, style: CellStyle) {
        if self.width_mode == WidthMode::Grapheme && self.join_previous(ch, style) {
            return;
        }
        let width = UnicodeWidthChar::width(ch).unwrap_or(0);
        if width == 0 {
            self.attach_zerowidth(ch);
            return;
        }
        … (the rest of today's body, unchanged)
    }

    fn previous_cell(&self) -> Option<(usize, usize)> {
        let mut col = self.col;
        if !self.pending_wrap {
            col = col.checked_sub(1)?;
        }
        if self.cell_ref(self.row, col).is_some_and(|cell| cell.ch == '\0') {
            col = col.checked_sub(1)?;
        }
        (self.row < self.rows && col < self.cols).then_some((self.row, col))
    }

    fn cell_width_at(&self, row: usize, col: usize) -> usize {
        1 + (col + 1..self.cols)
            .take_while(|next| self.cell_ref(row, *next).is_some_and(|cell| cell.ch == '\0'))
            .count()
    }

    fn join_previous(&mut self, ch: char, style: CellStyle) -> bool {
        let Some((row, col)) = self.previous_cell() else {
            return false;
        };
        let index = self.phys_start(row) + col;
        let mut buffer = [0u8; 4];
        let previous = self.cells[index].text(&mut buffer).to_string();
        if !width::joins_previous(&previous, ch) {
            return false;
        }
        let old_width = self.cell_width_at(row, col);
        self.cells[index].append_scalar(ch);
        let new_width = width::cluster_width(self.cells[index].text(&mut buffer));
        if new_width > old_width && col + 1 < self.cols {
            self.set(row, col + 1, Cell::new('\0', style));
            if self.row == row && self.col == col + 1 {
                self.col += 1;
                if self.col >= self.cols {
                    self.col = self.cols - 1;
                    self.pending_wrap = true;
                }
            }
        }
        self.raise_max_cursor_row(row);
        self.mark_dirty(row);
        true
    }
```

(`use crate::width::{self, WidthMode};` at the top. `set` is the existing cell writer that marks the row dirty.) The `attach_zerowidth` doc comment still describes the zero-width path correctly; leave it.

`row_index.rs`: `rewrap_hot(&mut self, content, cols, cut_at, mode: WidthMode)`, `rows_for(&mut self, content, cols, range, mode)`, `rewrap(&mut self, content, cols, mode)`, `push_line(&mut self, content, start, end, cols, mode)`; every internal call forwards `mode`; the loop at `:344-368` becomes

```rust
        for cluster in crate::width::clusters(text, mode) {
            let piece = &text[cluster.start..cluster.end];
            let offset = cluster.start;
            if piece.starts_with(' ') && cluster.width == 1 {
                width += 1;
                if word_in_piece {
                    last_break = Some((start + cluster.end as u64, width));
                }
                continue;
            }
            let ch_width = cluster.width;
            if ch_width > 0 && width > 0 && width + ch_width > limit {
                let (cut, cut_width) = last_break.unwrap_or((start + offset as u64, width));
                … (unchanged)
            }
            width += ch_width;
            word_in_piece |= ch_width > 0;
        }
```

and its unit tests pass `WidthMode::Scalar` (e.g. `r.rewrap_hot(&content, 80, 80, WidthMode::Scalar)` at `:651`). Remove the now-unused `use unicode_width::UnicodeWidthChar;` from `row_index.rs` if `marker_width` is its last user — it is not (`:44` still uses it); keep it.

`history.rs`: `begin(&mut self, first_stable_row, rows, cols, mode: WidthMode)` calls `screen.set_width_mode(mode)` after `set_records_eviction(false)`.

- [ ] **Step 5: Run the Rust tests**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core`
Expected: the two new files PASS; `graphemes.rs`, `rewrap.rs`, `ref.rs` (`zerowidth` included) still PASS. If `grapheme_break_test` reports failures, print them into the CHANGELOG entry verbatim and stop to report — do not edit the corpus.

- [ ] **Step 6: Expose the mode through wasm and TS**

`crates/vt-wasm/src/lib.rs` after `set_agent_tui_mode`:

```rust
    #[wasm_bindgen(js_name = setGraphemeClusters)]
    pub fn set_grapheme_clusters(&mut self, on: bool) {
        self.core.set_grapheme_clusters(on);
    }

    #[wasm_bindgen(js_name = graphemeClusters)]
    pub fn grapheme_clusters(&self) -> bool {
        self.core.grapheme_clusters()
    }
```

`ts/core/src/terminal-core.test.ts` — add:

```ts
	it("lays a ZWJ family out over two cells once grapheme clusters are on", () => {
		const family = "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}";
		const off = createTerminalCore({ columns: 20, scrollback: 10 });
		off.feed(new TextEncoder().encode(family));
		expect(off.graphemeClusters()).toBe(false);
		expect(off.snapshot().cursorColumn).toBe(6);
		const on = createTerminalCore({ columns: 20, scrollback: 10 });
		on.setGraphemeClusters(true);
		expect(on.graphemeClusters()).toBe(true);
		on.feed(new TextEncoder().encode(family));
		expect(on.snapshot().cursorColumn).toBe(2);
	});
```

`ts/core/src/terminal-core.ts` (next to `setAgentTuiMode`):

```ts
	setGraphemeClusters(on: boolean): void {
		if (this.disposed) return;
		this.inner.setGraphemeClusters(on);
	}

	graphemeClusters(): boolean {
		return this.inner.graphemeClusters();
	}
```

`ts/react/src/TerminalSurface.tsx`: the features effect from Task 2 becomes

```tsx
	useLayoutEffect(() => {
		rendererRef.current?.setFeatures(features ?? {});
		core.setGraphemeClusters(resolveFeatures(features).graphemes);
	}, [core, featuresKey]);
```

(import `resolveFeatures` from `@operator/terminal-renderer-dom`). `bench/agent-session/main.ts`: after `domRenderer.setFeatures(parsed)` add `if (parsed.graphemes) core.setGraphemeClusters(true);` (bind `const parsed = parseFeatureList(featureList)` first).

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.

- [ ] **Step 7: Verify, side-by-side, evidence re-measure**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` → clean, PASS.
- `cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && (cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...)` → PASS (the mirror's behaviour is unchanged; the artifact is rebuilt because the crate changed).
- `npm run bench:feel` → `PASS feel gate: zero pixel diff`.
- `npm run bench:feel -- --feature graphemes` → side-by-side under `baselines/*/feature-graphemes/`; open `baselines/glyph-probe/feature-graphemes/offset-0.png` and confirm the `seq:` row's `|` now sits under the ruler's column 40 like the other two rows.
- `npm run bench:glyphs -- --features graphemes` → writes `EVIDENCE-graphemes.json`; `seqDriftPx` must be within 1 px of `wideDriftPx` (both rows are now laid out from the same widths). Record both numbers in the CHANGELOG entry.
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → clean; `cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon`.

- [ ] **Step 8: CHANGELOG and commit**

```markdown
- vt-core: `TerminalCore::set_grapheme_clusters(true)` (TS `setGraphemeClusters`, `RendererFeatures.graphemes`) prints by extended grapheme cluster: ZWJ sequences, emoji modifier sequences and regional-indicator pairs occupy two cells, VS16 widens a text-presentation base, and the rewrap measures the same clusters (`unicode-segmentation` 1.13.3 + `unicode-width` 0.2.2, both Unicode 17). Default off: scalar widths as before. The Unicode `GraphemeBreakTest` corpus (`tests/grapheme/`, via kitty) runs against the splitter. In both modes a zero-width scalar after a space now rewraps with the space instead of starting a row. Evidence: glyph probe `seqDriftPx` <off value> → <on value> px (`baselines/glyph-probe/EVIDENCE-graphemes.json`).
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/Cargo.toml packages/terminal/Cargo.lock packages/terminal/crates packages/terminal/ts/core/src packages/terminal/ts/react/src packages/terminal/bench/agent-session packages/terminal/CHANGELOG.md backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && git commit -m "vt-core: grapheme-cluster widths behind set_grapheme_clusters, Unicode corpus test

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

### Task 6: Cell spans exported from the core — `spanRanges`/`cellSpans` through the incremental path

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/grid.rs` (`CellSpan`, `ExportedRow.spans`, `GridSnapshot.span_ranges`/`cell_spans`, `row_cell_spans`, `SnapshotCtx::push`, `export_history_row(…, mode)`, `export_screen_row`)
- Modify: `packages/terminal/crates/vt-core/src/lib.rs` (`build_snapshot` and `export_history_rows` pass `self.parser.width_mode()`; `pub use grid::CellSpan`)
- Modify: `packages/terminal/crates/vt-core/src/screen/snapshot.rs` (`AltSnapshot.span_ranges`/`cell_spans`)
- Create: `packages/terminal/crates/vt-core/tests/cell_spans.rs`
- Modify: `packages/terminal/crates/vt-core/tests/common/mod.rs` (`check` verifies spans)
- Modify: `packages/terminal/crates/vt-wasm/src/export.rs` (`CELL_SPAN_WORDS = 3`, the buffers, dead/history accounting, alt), `crates/vt-wasm/src/lib.rs` (`span_ranges_ptr/len`, `cell_spans_ptr/len`, `alt_span_ranges_ptr/len`, `alt_cell_spans_ptr/len`, re-export)
- Modify: `packages/terminal/crates/vt-wasm/tests/{exit_encoding.rs,export_layout.rs,incremental_export.rs}`
- Create: `packages/terminal/ts/core/src/cell-spans.ts`
- Modify: `packages/terminal/ts/core/src/{types.ts,terminal-core.ts,terminal-core.test.ts,index-browser.ts}`
- Modify: `frontend/src/renderer/test/setup.ts:56-64` and `frontend/src/renderer/components/BlockTerminal.test.tsx:192` only if `tsc` demands the new fields on their fake snapshots
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `clusters(text, mode)` and `WidthMode` (Task 5), `Cell::text`, the `'\0'` spacer convention (`screen.rs` `print`), `ExportBuffers`'s dead-prefix accounting (`export.rs` `drop_front`/`compact`).
- Produces (Rust): `pub struct CellSpan { pub start: u32, pub end: u32, pub width: u8 }` (row-relative bytes; `width` 0, 1 or 2); `ExportedRow.spans: Vec<CellSpan>`; `GridSnapshot.span_ranges: Vec<(u32, u32)>`, `GridSnapshot.cell_spans: Vec<CellSpan>`, `GridSnapshot::row_cell_spans(index) -> &[CellSpan]`; `AltSnapshot.span_ranges`, `AltSnapshot.cell_spans`; `vt_wasm::CELL_SPAN_WORDS: usize = 3`; `ExportBuffers::{span_ranges, cell_spans, alt_span_ranges, alt_cell_spans}`.
- Produces (TS): `CELL_SPAN_WORDS = 3` from `@operator/terminal-core`; `TerminalSnapshot.spanRanges: Uint32Array` (pairs, one per row), `TerminalSnapshot.cellSpans: Uint32Array` (stride 3: `start, end, width`); the same two on `AltScreenView`. Task 7 reads them.

The rule for listing a span: a cluster is listed when it is **not** a single scalar of width 1. So ASCII rows list nothing; `漢` lists `(start, end, 2)`; `e\u{301}` lists `(start, end, 1)`; a lone combining mark on a blank lists `(start, end, 1)` with the space (it is the space's cluster). Screen rows derive spans from the cells (the cell's text plus the count of `'\0'` spacers after it); history rows derive them from the row text through `clusters(text, mode)`; both yield the same list for the same row, which `cell_spans.rs` pins.

- [ ] **Step 1: Write the failing Rust tests**

`packages/terminal/crates/vt-core/tests/cell_spans.rs`:

```rust
mod common;

use vt_core::{CellSpan, TerminalCore};

const FAMILY: &str = "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}";

fn spans_of(input: &str, graphemes: bool) -> Vec<(u32, u32, u8)> {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.set_grapheme_clusters(graphemes);
    core.feed(input.as_bytes());
    let snapshot = core.snapshot().expect("snapshot");
    common::check(&core);
    snapshot
        .row_cell_spans(0)
        .iter()
        .map(|span| (span.start, span.end, span.width))
        .collect()
}

#[test]
fn an_ascii_row_lists_no_spans() {
    assert!(spans_of("plain text", false).is_empty());
}

#[test]
fn wide_and_joined_clusters_are_listed_with_their_bytes_and_cells() {
    assert_eq!(spans_of("a\u{6f22}b", false), vec![(1, 4, 2)]);
    assert_eq!(spans_of("e\u{301}x", false), vec![(0, 3, 1)]);
    assert_eq!(spans_of("\u{301}", false), vec![(0, 3, 1)]);
}

#[test]
fn a_family_is_three_spans_in_scalar_mode_and_one_in_grapheme_mode() {
    assert_eq!(spans_of(FAMILY, false), vec![(0, 7, 2), (7, 14, 2), (14, 18, 2)]);
    assert_eq!(spans_of(FAMILY, true), vec![(0, 18, 2)]);
    assert_eq!(spans_of("\u{2764}\u{fe0f}", true), vec![(0, 6, 2)]);
    assert_eq!(spans_of("\u{2764}\u{fe0f}", false), vec![(0, 6, 1)]);
}

#[test]
fn a_row_committed_to_scrollback_keeps_the_same_spans_it_had_on_screen() {
    for graphemes in [false, true] {
        let mut core = TerminalCore::new(20, 100).expect("core");
        core.resize(20, 2);
        core.set_grapheme_clusters(graphemes);
        core.feed(format!("a\u{6f22}{FAMILY}e\u{301}").as_bytes());
        let on_screen: Vec<CellSpan> = core.snapshot().expect("snapshot").row_cell_spans(0).to_vec();
        assert!(!on_screen.is_empty());
        core.feed(b"\r\nsecond\r\nthird\r\n");
        let snapshot = core.snapshot().expect("snapshot");
        common::check(&core);
        let row = (0..snapshot.row_count())
            .find(|index| snapshot.row_text(*index).starts_with('a'))
            .expect("row committed");
        assert!(row < snapshot.history_rows as usize, "the row is in scrollback");
        assert_eq!(snapshot.row_cell_spans(row), on_screen.as_slice(), "graphemes={graphemes}");
    }
}

#[test]
fn the_alternate_screen_exports_spans_too() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(b"\x1b[?1049h");
    core.feed("x\u{6f22}".as_bytes());
    let alt = core.snapshot().expect("snapshot").alt.expect("alt snapshot");
    assert_eq!(alt.span_ranges[0], (0, 1));
    assert_eq!(alt.cell_spans[0], CellSpan { start: 1, end: 4, width: 2 });
}
```

Add to `packages/terminal/crates/vt-core/tests/common/mod.rs`:

```rust
pub fn check(core: &TerminalCore) {
    if let Err(error) = core.verify_integrity() {
        panic!("integrity violated: {error:?}");
    }
    let snapshot = core.snapshot().expect("snapshot builds");
    for row in 0..snapshot.row_count() {
        let len = snapshot.row_text(row).len() as u32;
        let mut previous_end = 0u32;
        for span in snapshot.row_cell_spans(row) {
            assert!(span.start >= previous_end && span.start < span.end && span.end <= len, "row {row} span {span:?} outside {len} bytes or out of order");
            assert!(span.width <= 2, "row {row} span {span:?} width");
            previous_end = span.end;
        }
    }
}
```

(replacing the existing body; every integration test that calls `common::check` now verifies spans.)

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test cell_spans` → compile error, no `CellSpan`/`row_cell_spans`.

- [ ] **Step 3: Implement in `grid.rs`, `screen/snapshot.rs`, `lib.rs`**

`grid.rs`:

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CellSpan {
    pub start: u32,
    pub end: u32,
    pub width: u8,
}
```

`ExportedRow` gains `pub spans: Vec<CellSpan>`; `GridSnapshot` gains `pub span_ranges: Vec<(u32, u32)>` and `pub cell_spans: Vec<CellSpan>`, plus

```rust
    pub fn row_cell_spans(&self, index: usize) -> &[CellSpan] {
        let (start, end) = self.span_ranges[index];
        &self.cell_spans[start as usize..end as usize]
    }
```

`build_snapshot` gains a `width_mode: WidthMode` parameter (after `first_stable_row`), allocates `span_ranges`/`cell_spans`, hands them to `SnapshotCtx` (two more fields), and `SnapshotCtx::push` appends `row.spans` the way it appends `row.styles`:

```rust
        let span_start = checked_u32(self.cell_spans.len())?;
        self.cell_spans.extend(row.spans);
        let span_end = checked_u32(self.cell_spans.len())?;
        self.span_ranges.push((span_start, span_end));
```

`export_history_row(content, styles, row, mode: WidthMode)`:

```rust
    let text = std::str::from_utf8(&bytes).expect("row is valid utf-8");
    let spans = text_spans(text, mode);
```

with

```rust
pub(crate) fn text_spans(text: &str, mode: WidthMode) -> Vec<CellSpan> {
    crate::width::clusters(text, mode)
        .into_iter()
        .filter(|cluster| cluster.width != 1 || text[cluster.start..cluster.end].chars().nth(1).is_some())
        .map(|cluster| CellSpan {
            start: cluster.start as u32,
            end: cluster.end as u32,
            width: cluster.width.min(2) as u8,
        })
        .collect()
}
```

`export_screen_row` builds spans from cells inside its column loop:

```rust
        let start = bytes.len() as u32;
        let text = cell.text(&mut buffer);
        bytes.extend_from_slice(text.as_bytes());
        let spacers = (col + 1..screen.cols())
            .take_while(|next| screen.cell(row, *next).ch == '\0')
            .count();
        let cell_width = 1 + spacers;
        if cell_width != 1 || text.chars().nth(1).is_some() {
            spans.push(CellSpan { start, end: bytes.len() as u32, width: cell_width as u8 });
        }
```

(The spacer count walks to `screen.cols()`, not to the trailing-blank-trimmed `width`: `Cell::is_blank` matches `'\0'` with default paint, so a wide cell at the end of a row has its spacer trimmed out of `width` while it is still the cell's second column. Add `assert_eq!(spans_of("a\u{6f22}", false), vec![(1, 4, 2)]);` to `wide_and_joined_clusters_are_listed_with_their_bytes_and_cells` to pin that.)

`screen/snapshot.rs`: `AltSnapshot` gains `pub span_ranges: Vec<(u32, u32)>` and `pub cell_spans: Vec<CellSpan>`, filled in the same loop with the same spacer logic, `span_ranges.push((span_start, cell_spans.len() as u32))` per row.

`lib.rs`: pass `self.parser.width_mode()` into `build_snapshot` and into `export_history_row` inside `export_history_rows` (`lib.rs:367`); `pub use grid::{CellSpan, ExportedRow};`.

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core` → PASS (all files; `delta.rs:168` compares `row.styles` only and keeps passing).

- [ ] **Step 4: Write the failing vt-wasm tests**

`crates/vt-wasm/tests/export_layout.rs` — add:

```rust
#[test]
fn exports_cell_spans_beside_the_rows_as_start_end_width_triples() {
    let mut core = TerminalCore::new(16, 10).unwrap();
    core.feed("ab\u{6f22}c\r\ne\u{301}".as_bytes());
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&core.snapshot().unwrap()).unwrap();

    assert_eq!(buffers.span_ranges(), &[0, 1, 1, 2]);
    assert_eq!(buffers.cell_spans(), &[2, 5, 2, 0, 3, 1]);
}
```

`crates/vt-wasm/tests/incremental_export.rs`: in the "incremental equals full" comparison add `assert_eq!(incremental.span_ranges(), full.span_ranges()); assert_eq!(incremental.cell_spans(), full.cell_spans()); assert_eq!(incremental.alt_span_ranges(), full.alt_span_ranges()); assert_eq!(incremental.alt_cell_spans(), full.alt_cell_spans());` and add to the `Op` strategy `2 => Just(Op::Bytes("w\u{6f22}e\u{301}\r\n".as_bytes().to_vec()))`. `exit_encoding.rs`: the `GridSnapshot` literal gains `span_ranges: Vec::new(), cell_spans: Vec::new(),`.

Run: `cargo test -p vt-wasm` → compile error on `span_ranges()`.

- [ ] **Step 5: Implement the export buffers**

`export.rs`: `pub const CELL_SPAN_WORDS: usize = 3;`; fields `span_ranges: Vec<u32>`, `cell_spans: Vec<u32>`, `alt_span_ranges: Vec<u32>`, `alt_cell_spans: Vec<u32>`, `dead_spans: usize`, `history_spans: usize`. Then, mirroring `style_pairs`/`run_ranges` at every site:

- `refresh`: clear the four vectors; after the `run_ranges` loop push `(start, end)` pairs from `snapshot.span_ranges`; push each `CellSpan` as `start, end, u32::from(width)`; the same for `alt`; set `dead_spans = 0` and `history_spans = if history_rows == 0 { 0 } else { self.span_ranges[history_rows * 2 - 1] as usize }`.
- `apply`: after the history rows are appended, `self.history_spans = self.cell_spans.len() / CELL_SPAN_WORDS;`.
- `drop_front`: `self.dead_spans = if self.history_rows > 0 { self.span_ranges[first_live] as usize } else { self.history_spans };`.
- `rewrite_history_from`: `cut_spans` from `self.span_ranges[cut_row * 2 - 1]`, truncate `span_ranges` to `cut_row * 2` and `cell_spans` to `cut_spans * CELL_SPAN_WORDS`.
- `truncate_screen`: `span_ranges.truncate(keep_rows * 2)`, `cell_spans.truncate(self.history_spans * CELL_SPAN_WORDS)`.
- `push_row`: `let span_start = checked_u32_from_u64((self.cell_spans.len() / CELL_SPAN_WORDS) as u64)?;` push the triples, `span_end`, `span_ranges.push(span_start); span_ranges.push(span_end);`.
- `compact`: drain `span_ranges[..dead_rows * 2]`, subtract `dead_spans` from every remaining `span_ranges` entry, drain `cell_spans[..dead_spans * CELL_SPAN_WORDS]`, `history_spans -= dead_spans`, `dead_spans = 0`.
- `clear_alt`: clear the two alt vectors.
- Getters: `span_ranges(&self) -> &[u32]` (`&self.span_ranges[self.dead_rows * 2..]`), `cell_spans(&self) -> &[u32]` (whole buffer, like `style_pairs`), `alt_span_ranges`, `alt_cell_spans`.

`lib.rs` (vt-wasm): `pub use export::{…, CELL_SPAN_WORDS}` and eight getters `span_ranges_ptr/len`, `cell_spans_ptr/len`, `alt_span_ranges_ptr/len`, `alt_cell_spans_ptr/len` shaped like `run_ranges_ptr/len`.

Run: `cargo test -p vt-wasm` → PASS (the proptest is the incremental-vs-full guard for the new buffers; if it finds a mismatch the dead/history accounting above is where to look).

- [ ] **Step 6: TS views and validation**

`ts/core/src/cell-spans.ts`: `export const CELL_SPAN_WORDS = 3;`. `index-browser.ts`: export it. `types.ts`: `spanRanges: Uint32Array; cellSpans: Uint32Array;` on both `TerminalSnapshot` (after `stylePairs`) and `AltScreenView`. `terminal-core.ts` `buildSnapshot`: read the four `ptr/len` pairs, `validateEvenLength("spanRanges", spanRangesLen)`, throw if `spanRangesLen !== rowsLen`, `validateMultipleOf("cellSpans", cellSpansLen, CELL_SPAN_WORDS)`, and add the views to both objects.

`terminal-core.test.ts` — add:

```ts
	it("exports cell spans for wide and joined clusters", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 10 });
		core.feed(new TextEncoder().encode("ab漢c\r\né"));
		const snapshot = core.snapshot();
		expect([...snapshot.spanRanges]).toEqual([0, 1, 1, 2]);
		expect([...snapshot.cellSpans]).toEqual([2, 5, 2, 0, 3, 1]);
	});
```

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS. `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → if the fake snapshots in `test/setup.ts:56-64` / `BlockTerminal.test.tsx:192` fail the type check, add `spanRanges: new Uint32Array(0), cellSpans: new Uint32Array(0)` to each.

- [ ] **Step 7: Verify and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` → clean, PASS.
- `cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && (cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...)` → PASS.
- `npm run bench:feel` → `PASS feel gate: zero pixel diff`; `npm run bench:agent:gate` → PASS (the export grew two buffers; the feed+sync flatness row must still hold — a regression here is a failure to report, not to tune).
- `cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon`.

CHANGELOG:

```markdown
- vt-core/vt-wasm/core: the snapshot exports `spanRanges`/`cellSpans` (`CELL_SPAN_WORDS = 3`: row-relative byte `start`, `end`, cell `width`) for every cluster that is not a single width-1 scalar, on the primary and the alternate screen, through the incremental export like the style runs. Nothing reads them yet.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates packages/terminal/ts/core/src packages/terminal/CHANGELOG.md backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm frontend/src/renderer/test/setup.ts frontend/src/renderer/components/BlockTerminal.test.tsx && git commit -m "vt-core: export cell spans (cluster bytes and widths) through the incremental snapshot

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

### Task 7: The renderer's cell placement follows the exported spans — `cell-width.ts` deleted

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/clusters.ts`
- Create: `packages/terminal/ts/renderer-dom/src/clusters.test.ts`
- Delete: `packages/terminal/ts/renderer-dom/src/cell-width.ts`, `cell-width.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/words.ts`, `words.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/selection-text.ts`, `selection-text.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/selection-model.ts`, `selection-model.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/selection-view.ts` (`snapshotTextRows` supplies `rowSpans`)
- Modify: `packages/terminal/ts/renderer-dom/src/terminal-selection.test.ts`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `TerminalSnapshot.spanRanges`/`cellSpans`, `AltScreenView.spanRanges`/`cellSpans`, `CELL_SPAN_WORDS` (Task 6).
- Produces: `type Cluster = Readonly<{ text: string; start: number; end: number }>` (cells); `rowClusters(text: string, spans: ArrayLike<number>): Cluster[]`; `cellSlice(text, spans, fromCell, toCell): string`; `cellCount(text, spans): number`; `wordCellRange(text, spans, cell): { start, end }`; `TextRows.rowSpans(blockId, row): ArrayLike<number>`; `resolveRange(state, order, rowText, rowSpans = () => [])`. Task 8's cursor paint uses `rowClusters` to find the cell under the cursor.

`spans` are the row's slice of `cellSpans` (byte offsets relative to the row, stride 3). `rowClusters` walks the string's code points while tracking the UTF-8 byte offset, so it never re-encodes the row; a code point not covered by a span is one cell wide (the export's contract, Task 6). With no spans at all (a hand-built test row, or a row of ASCII) every code point is one cell — which is why the old table's zero-width and wide ranges are no longer needed anywhere.

- [ ] **Step 1: Write the failing tests**

`packages/terminal/ts/renderer-dom/src/clusters.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { cellCount, cellSlice, rowClusters } from "./clusters";

const HAN = "漢";
const ROCKET = "\u{1f680}";
const FAMILY = "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}";

describe("rowClusters", () => {
	it("gives every code point one cell when the row has no spans", () => {
		expect(rowClusters("ab", [])).toEqual([
			{ text: "a", start: 0, end: 1 },
			{ text: "b", start: 1, end: 2 },
		]);
	});
	it("follows the exported spans for wide, joined and multi-scalar clusters", () => {
		expect(rowClusters(`a${HAN}b`, [1, 4, 2])).toEqual([
			{ text: "a", start: 0, end: 1 },
			{ text: HAN, start: 1, end: 3 },
			{ text: "b", start: 3, end: 4 },
		]);
		expect(rowClusters("éx", [0, 3, 1])).toEqual([
			{ text: "é", start: 0, end: 1 },
			{ text: "x", start: 1, end: 2 },
		]);
		expect(rowClusters(`${FAMILY}!`, [0, 18, 2])).toEqual([
			{ text: FAMILY, start: 0, end: 2 },
			{ text: "!", start: 2, end: 3 },
		]);
	});
	it("gives a rocket the two cells the core gave it", () => {
		expect(cellCount(`${ROCKET}ab`, [0, 4, 2])).toBe(4);
	});
});

describe("cellSlice", () => {
	it("cuts ascii by column", () => {
		expect(cellSlice("hello world", [], 6, 11)).toBe("world");
	});
	it("keeps a wide character whose first cell is inside the cut", () => {
		expect(cellSlice(`a${HAN}b`, [1, 4, 2], 1, 3)).toBe(HAN);
		expect(cellSlice(`a${HAN}b`, [1, 4, 2], 2, 4)).toBe("b");
	});
	it("keeps combining marks with their base", () => {
		expect(cellSlice("éx", [0, 3, 1], 0, 1)).toBe("é");
	});
	it("clamps past the end", () => {
		expect(cellSlice("abc", [], 1, 99)).toBe("bc");
		expect(cellCount(`a${HAN}b`, [1, 4, 2])).toBe(4);
	});
});
```

`words.test.ts`: every `wordCellRange(text, cell)` call becomes `wordCellRange(text, [], cell)`; add

```ts
	it("steps over a wide cluster as one cell pair", () => {
		expect(wordCellRange(`ab ${"漢"}c d`, [3, 6, 2], 4)).toEqual({ start: 3, end: 6 });
	});
```

`selection-text.test.ts`: add `rowSpans: (id, row) => (id === "a" && row === 2 ? [6, 9, 2, 9, 12, 2] : [])` to `rows` and `rowSpans: () => []` to `trimmed`; add

```ts
	it("cuts by cells, not code points, across a wide cluster", () => {
		expect(selectedText({ start: { blockId: "a", row: 2, cell: 6 }, end: { blockId: "a", row: 2, cell: 8 } }, rows)).toBe("漢");
	});
```

`selection-model.test.ts`: unchanged calls keep working through the default `rowSpans`; add

```ts
	it("expands a word over a wide cluster using the row's spans", () => {
		const wide = (id: string, row: number) => (id === "0" && row === 0 ? "go 漢字 now" : "");
		const spans = (id: string, row: number) => (id === "0" && row === 0 ? [3, 6, 2, 6, 9, 2] : []);
		const range = resolveRange({ head: at("0", 0, 4), tail: at("0", 0, 4), kind: "word" }, order, wide, spans)!;
		expect(range.start.cell).toBe(3);
		expect(range.end.cell).toBe(7);
	});
```

`terminal-selection.test.ts`: add, using the file's existing `mount`/`CELL_W`/`CELL_H` helpers:

```ts
	it("copies across a rocket by the core's cells, not a hand-written width table", () => {
		const { renderer } = mount("\u{1f680}ab");
		renderer.selectionBegin(renderer.pointAt(0, CELL_H * 0.5)!, "simple");
		renderer.selectionUpdate(renderer.pointAt(CELL_W * 3 - 1, CELL_H * 0.5)!);
		expect(renderer.selectedText()).toBe("\u{1f680}a");
	});
```

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/clusters.test.ts src/words.test.ts src/selection-text.test.ts src/selection-model.test.ts src/terminal-selection.test.ts`
Expected: `clusters` module missing; the words/selection tests fail on the new signatures; the rocket test reports `"🚀ab"`.

- [ ] **Step 3: Implement `clusters.ts` and rewire the consumers**

`packages/terminal/ts/renderer-dom/src/clusters.ts`:

```ts
import { CELL_SPAN_WORDS } from "@operator/terminal-core";

export type Cluster = Readonly<{ text: string; start: number; end: number }>;

function utf8Length(codePoint: number): number {
	if (codePoint < 0x80) return 1;
	if (codePoint < 0x800) return 2;
	if (codePoint < 0x10000) return 3;
	return 4;
}

export function rowClusters(text: string, spans: ArrayLike<number>): Cluster[] {
	const out: Cluster[] = [];
	const spanCount = Math.floor(spans.length / CELL_SPAN_WORDS);
	let spanIndex = 0;
	let byte = 0;
	let cell = 0;
	let pending: { text: string; end: number; width: number } | null = null;
	for (const character of text) {
		const length = utf8Length(character.codePointAt(0) ?? 0);
		if (pending) {
			pending.text += character;
			byte += length;
			if (byte >= pending.end) {
				out.push({ text: pending.text, start: cell, end: cell + Math.max(pending.width, 1) });
				cell += pending.width;
				pending = null;
			}
			continue;
		}
		if (spanIndex < spanCount && spans[spanIndex * CELL_SPAN_WORDS] === byte) {
			const end = spans[spanIndex * CELL_SPAN_WORDS + 1]!;
			const width = spans[spanIndex * CELL_SPAN_WORDS + 2]!;
			spanIndex += 1;
			byte += length;
			if (byte >= end) {
				out.push({ text: character, start: cell, end: cell + Math.max(width, 1) });
				cell += width;
			} else {
				pending = { text: character, end, width };
			}
			continue;
		}
		out.push({ text: character, start: cell, end: cell + 1 });
		cell += 1;
		byte += length;
	}
	if (pending) out.push({ text: pending.text, start: cell, end: cell + Math.max(pending.width, 1) });
	return out;
}

export function cellCount(text: string, spans: ArrayLike<number>): number {
	const clusters = rowClusters(text, spans);
	return clusters.length === 0 ? 0 : clusters[clusters.length - 1]!.end;
}

export function cellSlice(text: string, spans: ArrayLike<number>, fromCell: number, toCell: number): string {
	let out = "";
	for (const cluster of rowClusters(text, spans)) {
		if (cluster.end <= fromCell) continue;
		if (cluster.start >= toCell) break;
		out += cluster.text;
	}
	return out;
}
```

`words.ts`: delete the `cell-width` import and the local `cells()`; `wordCellRange(text: string, spans: ArrayLike<number>, cell: number)` builds `const list = rowClusters(text, spans)` and otherwise keeps its body, with `isWordBoundary(c.text)` applied only to single-scalar clusters:

```ts
export function isWordBoundary(character: string): boolean {
	if ([...character].length !== 1) return false;
	if (/\s/u.test(character)) return true;
	if (ALLOWLIST.includes(character)) return false;
	return BOUNDARY_CHARS.includes(character);
}
```

`selection-text.ts`: `TextRows` gains `rowSpans(blockId: string, row: number): ArrayLike<number>;`; `cut(text, spans, from, to)` calls `cellSlice(text, spans, from, to === ROW_END ? Number.MAX_SAFE_INTEGER : to)` (the `from === 0 && to === ROW_END` shortcut stays); `selectedText` passes `rows.rowSpans(blockId, row)`.

`selection-model.ts`: `export type RowSpans = (blockId: string, row: number) => ArrayLike<number>;` `expand(point, kind, rowText, rowSpans)` calls `wordCellRange(rowText(…), rowSpans(…), point.column)`; `resolveRange(state, order, rowText, rowSpans: RowSpans = () => [])`.

`selection-view.ts`: `resolveRange(selection, order, rows.rowText, rows.rowSpans)`; `snapshotTextRows` adds, for the alt branch, `rowSpans: (_id, row) => spanSlice(alt.spanRanges, alt.cellSpans, row)` and for blocks `rowSpans: (id, row) => { … same bounds check as rowText …; return spanSlice(snapshot.spanRanges, snapshot.cellSpans, flat); }` with

```ts
function spanSlice(spanRanges: Uint32Array, cellSpans: Uint32Array, row: number): Uint32Array {
	const start = spanRanges[row * 2] ?? 0;
	const end = spanRanges[row * 2 + 1] ?? start;
	return cellSpans.subarray(start * CELL_SPAN_WORDS, end * CELL_SPAN_WORDS);
}
```

Delete `cell-width.ts` and `cell-width.test.ts`; `grep -rn "cell-width" ts/` must return nothing.

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run` → PASS.

- [ ] **Step 5: Verify and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.
- `npm run bench:selection` → PASS.
- `npm run bench:feel` → `PASS feel gate: zero pixel diff`.
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → clean.

CHANGELOG:

```markdown
- renderer-dom: selection and copy place cells from the snapshot's exported cell spans instead of a hand-written width table (`cell-width.ts`, deleted). Copying across a code point the table misclassified (`🚀` U+1F680 was one cell in the table and is two in the core) now yields the characters under the selection. With `graphemes` on, a ZWJ sequence or a flag is one two-cell cluster to the selection too.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add -A packages/terminal/ts/renderer-dom/src packages/terminal/CHANGELOG.md && git commit -m "renderer-dom: cell placement from exported spans; delete the cell-width table

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Cursor — invert below contrast 1.5, hollow when unfocused

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/cursor-contrast.ts`
- Create: `packages/terminal/ts/renderer-dom/src/cursor-contrast.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/style-code.ts` (export `indexedRgb`)
- Modify: `packages/terminal/ts/renderer-dom/src/cursor.ts` (`CursorPaint`, classes, `placeCursor` paint argument, `cursorPaintFor`)
- Modify: `packages/terminal/ts/renderer-dom/src/cursor.test.ts`, `terminal-cursor.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/block-body.ts` (`BlockBodyInput.cursorPaint`)
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` (`setFocused`, `focused` field, computes `cursorPaint` per paint)
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/styles.css`, `styles.ts`, `styles-parity.test.ts`
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx` (focus seam), `TerminalSurface.test.tsx`
- Modify: `packages/terminal/bench/agent-session/main.ts` (`focused` param), `bench/agent-session/feel-gate.mjs` (`--feature cursorHollowUnfocused` adds `&focused=0`)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `rowClusters` (Task 7), `TerminalTheme` colours as `#rrggbb` (`theme-warp.ts`; `selection` is `rgb(… / …)` and never a cursor or background), the style word (Task 3: `fg` and `bg` are already reverse-resolved, `parser.rs:790`), `RendererFeatures.cursorContrast`/`cursorHollowUnfocused`.
- Produces: `MIN_CURSOR_CONTRAST = 1.5`; `parseHexColour(text: string): Rgb | null` (`Rgb = readonly [number, number, number]`); `relativeLuminance(rgb): number`; `contrastRatio(a: Rgb, b: Rgb): number`; `styleCodeToRgb(code: number, theme: TerminalTheme, role: "foreground" | "background"): Rgb | null`; `cursorLacksContrast(theme: TerminalTheme, backgroundCode: number): boolean`; `type CursorPaint = Readonly<{ inverted: boolean; hollow: boolean; text: string; cells: number }>`; `PLAIN_CURSOR_PAINT` (`{ inverted: false, hollow: false, text: "", cells: 1 }`); `CLASS_CURSOR_INVERTED = "terminal-cursor-inverted"`, `CLASS_CURSOR_HOLLOW = "terminal-cursor-hollow"`; `placeCursor(row, cursor, column, cellWidth, paint = PLAIN_CURSOR_PAINT)`; `cursorPaintFor(input: { source: RowSource; row: number; column: number; theme: TerminalTheme; features: RendererFeatures; focused: boolean; decoder: TextDecoder }): CursorPaint`; `DomBlockRenderer.setFocused(focused: boolean)`; harness `?focused=0`.

References: Alacritty `alacritty/src/display/content.rs:21-22` (`MIN_CURSOR_CONTRAST = 1.5`) and `:124-134` (swap cursor and text colours below it); the contrast formula is W3C's, as implemented by `vte-0.15.0/src/ansi.rs:66-104` `Rgb::luminance`/`Rgb::contrast`; Ghostty `src/renderer/cursor.zig:58-60` (`if (!opts.focused) return .block_hollow`); Warp draws a `HollowBlock` as a border of `thickness` (`app/src/terminal/grid_renderer.rs:2471-2475`). The inverted cursor carries the cell's own text above the run, coloured `theme.background` on `theme.foreground`, the way xterm.js's DOM renderer paints its block-cursor cell (`src/browser/renderer/dom/DomRendererRowFactory.ts`, `xterm-cursor-block`), because a `z-index: -1` box cannot flip the glyph over it.

- [ ] **Step 1: Write the failing tests**

`packages/terminal/ts/renderer-dom/src/cursor-contrast.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { contrastRatio, cursorLacksContrast, MIN_CURSOR_CONTRAST, parseHexColour, relativeLuminance, styleCodeToRgb } from "./cursor-contrast";
import { warpDarkTheme } from "./theme-warp";

const RGB = (r: number, g: number, b: number) => 0x0200_0000 | (r << 16) | (g << 8) | b;
const INDEXED = (i: number) => 0x0100_0000 | i;

describe("colour parsing and contrast", () => {
	it("parses #rrggbb and rejects anything else", () => {
		expect(parseHexColour("#19aad8")).toEqual([0x19, 0xaa, 0xd8]);
		expect(parseHexColour("rgb(1 2 3)")).toBeNull();
	});
	it("computes W3C luminance and contrast like vte's Rgb::contrast", () => {
		expect(relativeLuminance([255, 255, 255])).toBeCloseTo(1, 5);
		expect(relativeLuminance([0, 0, 0])).toBeCloseTo(0, 5);
		expect(contrastRatio([255, 255, 255], [0, 0, 0])).toBeCloseTo(21, 5);
		expect(contrastRatio([0, 0, 0], [255, 255, 255])).toBeCloseTo(21, 5);
	});
	it("resolves style codes through the theme", () => {
		expect(styleCodeToRgb(254, warpDarkTheme, "background")).toEqual([0x05, 0x05, 0x05]);
		expect(styleCodeToRgb(255, warpDarkTheme, "foreground")).toEqual([0xff, 0xff, 0xff]);
		expect(styleCodeToRgb(1, warpDarkTheme, "foreground")).toEqual([0xff, 0x82, 0x72]);
		expect(styleCodeToRgb(INDEXED(196), warpDarkTheme, "foreground")).toEqual([255, 0, 0]);
		expect(styleCodeToRgb(INDEXED(236), warpDarkTheme, "background")).toEqual([48, 48, 48]);
		expect(styleCodeToRgb(RGB(25, 170, 216), warpDarkTheme, "background")).toEqual([25, 170, 216]);
	});
	it("flags a background that matches the cursor and accepts the default background", () => {
		expect(MIN_CURSOR_CONTRAST).toBe(1.5);
		expect(cursorLacksContrast(warpDarkTheme, RGB(25, 170, 216))).toBe(true);
		expect(cursorLacksContrast(warpDarkTheme, 254)).toBe(false);
		expect(cursorLacksContrast(warpDarkTheme, INDEXED(236))).toBe(false);
	});
});
```

Add to `cursor.test.ts`:

```ts
describe("placeCursor with a paint", () => {
	it("stays a plain box by default", () => {
		const row = document.createElement("div");
		const cursor = createCursorElement(0, 8);
		placeCursor(row, cursor, 3, 8);
		expect(cursor.className).toBe(CLASS_CURSOR);
		expect(cursor.textContent).toBe("");
		expect(cursor.style.width).toBe("8px");
	});
	it("inverts with the cell's text and spans the cluster's cells", () => {
		const row = document.createElement("div");
		const cursor = createCursorElement(0, 8);
		placeCursor(row, cursor, 3, 8, { inverted: true, hollow: false, text: "漢", cells: 2 });
		expect(cursor.classList.contains(CLASS_CURSOR_INVERTED)).toBe(true);
		expect(cursor.textContent).toBe("漢");
		expect(cursor.style.width).toBe("16px");
		placeCursor(row, cursor, 3, 8);
		expect(cursor.classList.contains(CLASS_CURSOR_INVERTED)).toBe(false);
		expect(cursor.textContent).toBe("");
	});
	it("hollows when asked", () => {
		const cursor = createCursorElement(0, 8);
		placeCursor(document.createElement("div"), cursor, 0, 8, { inverted: false, hollow: true, text: "", cells: 1 });
		expect(cursor.classList.contains(CLASS_CURSOR_HOLLOW)).toBe(true);
	});
});

describe("cursorPaintFor", () => {
	const encoder = new TextEncoder();
	const decoder = new TextDecoder();
	const RGB_CURSOR_BAND = 0x0200_0000 | (25 << 16) | (170 << 8) | 216;
	function source(text: string, background: number, spans: number[] = []): RowSource {
		const content = encoder.encode(text);
		return {
			content,
			rows: Uint32Array.from([0, content.byteLength]),
			runRanges: Uint32Array.from([0, 1]),
			stylePairs: Uint32Array.from([content.byteLength, 255, background, 0, 255]),
			spanRanges: Uint32Array.from([0, spans.length / 3]),
			cellSpans: Uint32Array.from(spans),
		};
	}
	const base = { row: 0, theme: warpDarkTheme, focused: true, decoder };

	it("is plain with every flag off, whatever the band", () => {
		expect(cursorPaintFor({ ...base, source: source("ab", RGB_CURSOR_BAND), column: 1, features: DEFAULT_FEATURES })).toEqual(PLAIN_CURSOR_PAINT);
	});
	it("inverts over a band that matches the cursor colour and carries the cell's cluster", () => {
		const features = { ...DEFAULT_FEATURES, cursorContrast: true };
		expect(cursorPaintFor({ ...base, source: source("a漢b", RGB_CURSOR_BAND, [1, 4, 2]), column: 1, features })).toEqual({ inverted: true, hollow: false, text: "漢", cells: 2 });
		expect(cursorPaintFor({ ...base, source: source("ab", 254), column: 1, features })).toEqual({ ...PLAIN_CURSOR_PAINT, text: "b" });
		expect(cursorPaintFor({ ...base, source: source("ab", RGB_CURSOR_BAND), column: 7, features })).toEqual({ inverted: true, hollow: false, text: "", cells: 1 });
	});
	it("hollows when unfocused only with its flag", () => {
		const features = { ...DEFAULT_FEATURES, cursorHollowUnfocused: true };
		expect(cursorPaintFor({ ...base, source: source("ab", 254), column: 0, features, focused: false }).hollow).toBe(true);
		expect(cursorPaintFor({ ...base, source: source("ab", 254), column: 0, features, focused: true }).hollow).toBe(false);
		expect(cursorPaintFor({ ...base, source: source("ab", 254), column: 0, features: DEFAULT_FEATURES, focused: false }).hollow).toBe(false);
	});
});
```

(imports: `CLASS_CURSOR_INVERTED, CLASS_CURSOR_HOLLOW, cursorPaintFor, PLAIN_CURSOR_PAINT` from `./cursor`, `DEFAULT_FEATURES` from `./features`, `warpDarkTheme` from `./theme-warp`, `type RowSource` from `./row-builder`. `RowSource` gains optional `spanRanges?: Uint32Array; cellSpans?: Uint32Array;` in this task.)

`terminal-cursor.test.ts` — add, using the file's `mountWith` (extend it to return the renderer):

```ts
	it("inverts over the cursor-coloured band only when cursorContrast is on", async () => {
		const { host, renderer } = mountWith("\x1b[48;2;25;170;216m  band  \x1b[0m\x1b[4D");
		expect(host.querySelector(".terminal-cursor-inverted")).toBeNull();
		renderer.setFeatures({ cursorContrast: true });
		await flushRepaint();
		const cursor = host.querySelector<HTMLElement>("[data-terminal-cursor-cell]")!;
		expect(cursor.classList.contains("terminal-cursor-inverted")).toBe(true);
		expect(cursor.textContent).toBe("n");
	});

	it("hollows when the host reports blur, only with cursorHollowUnfocused", async () => {
		const { host, renderer } = mountWith("> hi");
		renderer.setFocused(false);
		await flushRepaint();
		expect(host.querySelector(".terminal-cursor-hollow")).toBeNull();
		renderer.setFeatures({ cursorHollowUnfocused: true });
		await flushRepaint();
		expect(host.querySelector(".terminal-cursor-hollow")).not.toBeNull();
		renderer.setFocused(true);
		await flushRepaint();
		expect(host.querySelector(".terminal-cursor-hollow")).toBeNull();
	});
```

`TerminalSurface.test.tsx` — add:

```ts
	it("tells the renderer when focus enters and leaves the surface", () => {
		const setFocused = vi.spyOn(DomBlockRenderer.prototype, "setFocused");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={() => undefined} />,
		);
		const editor = container.querySelector<HTMLElement>(".terminal-editor")!;
		act(() => editor.focus());
		expect(setFocused).toHaveBeenLastCalledWith(true);
		act(() => editor.blur());
		expect(setFocused).toHaveBeenLastCalledWith(false);
		setFocused.mockRestore();
	});
```

`styles-parity.test.ts` — add:

```ts
	it("paints the inverted cursor above its glyph and the unfocused cursor hollow", () => {
		expect(terminalStyles).toContain(".terminal-cursor-inverted");
		expect(terminalStyles).toContain(".terminal-cursor-hollow");
		expect(terminalStyles).toContain("box-shadow: inset 0 0 0 1px var(--terminal-cursor)");
	});
```

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/cursor-contrast.test.ts src/cursor.test.ts src/terminal-cursor.test.ts src/styles-parity.test.ts` → FAIL (missing module/exports/classes). `cd ../react && npx vitest run src/TerminalSurface.test.tsx -t "focus enters"` → FAIL (`setFocused` missing).

- [ ] **Step 3: Implement**

`style-code.ts`: add

```ts
export function indexedRgb(index: number): readonly [number, number, number] {
	if (index < 232) {
		const offset = index - 16;
		return [CUBE_LEVELS[Math.floor(offset / 36) % 6]!, CUBE_LEVELS[Math.floor(offset / 6) % 6]!, CUBE_LEVELS[offset % 6]!];
	}
	const level = 8 + (index - 232) * 10;
	return [level, level, level];
}
```

and make `indexedToCss` use it for `index >= 16`.

`cursor-contrast.ts`:

```ts
import type { TerminalTheme } from "@operator/terminal-core";
import { indexedRgb } from "./style-code.js";

export type Rgb = readonly [number, number, number];

// alacritty/src/display/content.rs:21-22
export const MIN_CURSOR_CONTRAST = 1.5;

const TAG_INDEXED = 0x0100_0000;
const TAG_RGB = 0x0200_0000;
const TAG_MASK = 0x0300_0000;
const COLOUR_MASK = 0x00ff_ffff;

export function parseHexColour(text: string): Rgb | null {
	const match = /^#([0-9a-f]{6})$/iu.exec(text.trim());
	if (!match) return null;
	const value = Number.parseInt(match[1]!, 16);
	return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
}

// vte-0.15.0/src/ansi.rs:66-104 (Rgb::luminance, Rgb::contrast)
export function relativeLuminance([r, g, b]: Rgb): number {
	const channel = (value: number) => {
		const c = value / 255;
		return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
	};
	return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

export function contrastRatio(a: Rgb, b: Rgb): number {
	const la = relativeLuminance(a);
	const lb = relativeLuminance(b);
	const [darker, lighter] = la > lb ? [lb, la] : [la, lb];
	return (lighter + 0.05) / (darker + 0.05);
}

export function styleCodeToRgb(code: number, theme: TerminalTheme, role: "foreground" | "background"): Rgb | null {
	const tag = code & TAG_MASK;
	if (tag === TAG_RGB) return [(code >> 16) & 0xff, (code >> 8) & 0xff, code & 0xff];
	if (tag === TAG_INDEXED) {
		const index = code & 0xff;
		return index < 16 ? parseHexColour(theme.ansi[index]!) : indexedRgb(index);
	}
	const plain = code & COLOUR_MASK;
	if (plain <= 15) return parseHexColour(theme.ansi[plain]!);
	if (plain === 255) return parseHexColour(theme.foreground);
	if (plain === 254) return parseHexColour(role === "background" ? theme.background : theme.foreground);
	return null;
}

export function cursorLacksContrast(theme: TerminalTheme, backgroundCode: number): boolean {
	const cursor = parseHexColour(theme.cursor);
	const background = styleCodeToRgb(backgroundCode, theme, "background");
	if (!cursor || !background) return false;
	return contrastRatio(cursor, background) < MIN_CURSOR_CONTRAST;
}
```

`cursor.ts` additions:

```ts
export const CLASS_CURSOR_INVERTED = "terminal-cursor-inverted";
export const CLASS_CURSOR_HOLLOW = "terminal-cursor-hollow";

export type CursorPaint = Readonly<{ inverted: boolean; hollow: boolean; text: string; cells: number }>;
export const PLAIN_CURSOR_PAINT: CursorPaint = { inverted: false, hollow: false, text: "", cells: 1 };

export function placeCursor(row: HTMLElement, cursor: HTMLElement, column: number, cellWidth: number, paint: CursorPaint = PLAIN_CURSOR_PAINT): void {
	cursor.dataset.column = String(column);
	cursor.style.width = `${cellWidth * Math.max(1, paint.cells)}px`;
	cursor.style.transform = `translateX(${column * cellWidth}px)`;
	cursor.classList.toggle(CLASS_CURSOR_INVERTED, paint.inverted);
	cursor.classList.toggle(CLASS_CURSOR_HOLLOW, paint.hollow);
	const text = paint.inverted ? paint.text : "";
	if (cursor.textContent !== text) cursor.textContent = text;
	if (cursor.parentElement !== row) row.append(cursor);
}

export function cursorPaintFor(input: {
	source: RowSource;
	row: number;
	column: number;
	theme: TerminalTheme;
	features: RendererFeatures;
	focused: boolean;
	decoder: TextDecoder;
}): CursorPaint {
	const { source, row, column, theme, features, focused, decoder } = input;
	const hollow = features.cursorHollowUnfocused && !focused;
	if (!features.cursorContrast) return hollow ? { ...PLAIN_CURSOR_PAINT, hollow } : PLAIN_CURSOR_PAINT;
	const start = source.rows[row * 2] ?? 0;
	const end = source.rows[row * 2 + 1] ?? start;
	const text = decoder.decode(source.content.subarray(start, end));
	const spanStart = source.spanRanges?.[row * 2] ?? 0;
	const spanEnd = source.spanRanges?.[row * 2 + 1] ?? spanStart;
	const spans = source.cellSpans?.subarray(spanStart * CELL_SPAN_WORDS, spanEnd * CELL_SPAN_WORDS) ?? [];
	let byte = 0;
	let cell: Cluster | null = null;
	for (const cluster of rowClusters(text, spans)) {
		if (cluster.start === column) {
			cell = cluster;
			break;
		}
		if (cluster.start > column) break;
		byte += new TextEncoder().encode(cluster.text).byteLength;
	}
	const pairStart = source.runRanges[row * 2] ?? 0;
	const pairEnd = source.runRanges[row * 2 + 1] ?? pairStart;
	let background = 254;
	for (let pair = pairStart; pair < pairEnd; pair += 1) {
		const runEnd = source.stylePairs[pair * STYLE_RUN_WORDS] ?? 0;
		if (byte < runEnd || (cell === null && pair === pairEnd - 1 && byte === runEnd)) {
			background = source.stylePairs[pair * STYLE_RUN_WORDS + 2] ?? 254;
			break;
		}
	}
	return {
		inverted: cursorLacksContrast(theme, background),
		hollow,
		text: cell?.text ?? "",
		cells: cell ? cell.end - cell.start : 1,
	};
}
```

(`cursorPaintFor` runs once per paint for one row, so the per-cluster `TextEncoder` is not a hot path; imports: `CELL_SPAN_WORDS, STYLE_RUN_WORDS, type TerminalTheme` from `@operator/terminal-core`, `rowClusters, type Cluster` from `./clusters.js`, `cursorLacksContrast` from `./cursor-contrast.js`, `type RendererFeatures` from `./features.js`, `type RowSource` from `./row-builder.js`.) A cursor past the row's text (the common case: the cursor sits after the last glyph) reads the row's last run's background — that is the band case the probe's last row exercises, where `printf ' cursor band '` leaves the cursor inside the band's run.

`block-body.ts`: `BlockBodyInput` gains `cursorPaint: CursorPaint;` and the `placeCursor` call passes `input.cursorPaint`. `dom-block-renderer.ts`: field `private focused = true;`, method

```ts
	setFocused(focused: boolean): void {
		if (this.focused === focused) return;
		this.focused = focused;
		if (this.activeFeatures.cursorHollowUnfocused) this.scheduleRepaint();
	}
```

and in `repaint`, after `const cursor = primaryCursorPlacement(snapshot);`:

```ts
		const cursorPaint = cursor
			? cursorPaintFor({ source: snapshot, row: cursor.row, column: cursor.column, theme: this.theme, features: this.activeFeatures, focused: this.focused, decoder: this.decoder })
			: PLAIN_CURSOR_PAINT;
```

passed as `cursorPaint` into `populateBlock`'s input. The cursor element must be refreshed when only its paint changed: `placeCursor` runs on every paint for the cursor row (block-body places it whenever `input.cursor.row === snapshotRow`), so a features or focus change that schedules a repaint is enough.

`styles.css`/`styles.ts`, after `.terminal-cursor`:

```css
/* Below MIN_CURSOR_CONTRAST the cursor takes the foreground and its glyph the
   background (alacritty/src/display/content.rs:124-134); it rises above the
   run to carry that glyph, as xterm.js's DOM block cursor does
   (src/browser/renderer/dom/DomRendererRowFactory.ts, xterm-cursor-block).
   Unfocused, a hollow block (ghostty/src/renderer/cursor.zig:58-60; Warp
   HollowBlock, app/src/terminal/grid_renderer.rs:2471). */
.terminal-cursor-inverted {
	z-index: 1;
	background: var(--terminal-foreground);
	color: var(--terminal-background);
	white-space: pre;
}

.terminal-cursor-hollow {
	background: transparent;
	box-shadow: inset 0 0 0 1px var(--terminal-cursor);
}

.terminal-cursor-inverted.terminal-cursor-hollow {
	color: inherit;
	box-shadow: inset 0 0 0 1px var(--terminal-foreground);
}
```

`TerminalSurface.tsx`: in the effect that binds `onFocusIn`/`onFocusOut` (`:459-498`), give the surface root a ref (`surfaceRef` on the `.terminal-surface` div) and add

```ts
		const surface = surfaceRef.current;
		const reportFocus = () => rendererRef.current?.setFocused(surface !== null && surface.contains(document.activeElement));
		surface?.addEventListener("focusin", reportFocus);
		surface?.addEventListener("focusout", () => queueMicrotask(reportFocus));
```

with matching `removeEventListener`s in the cleanup (keep the listener references in `const`s). `bench/agent-session/main.ts`: `domRenderer.setFocused(params.get("focused") !== "0");` after the features call; `feel-gate.mjs`: build the side-by-side URL with `const focusParam = feature.split(",").includes("cursorHollowUnfocused") ? "&focused=0" : "";` appended.

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in renderer-dom react; do (cd ts/$p && npx vitest run); done` → PASS.

- [ ] **Step 5: Verify, side-by-side, commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS; `node --test ./bench/agent-session/session-api.test.mjs` → PASS.
- `npm run bench:selection` → PASS.
- `npm run bench:feel` → `PASS feel gate: zero pixel diff`.
- `npm run bench:feel -- --feature cursorContrast` → open `baselines/glyph-probe/feature-cursorContrast/offset-100.png`: the cursor inside the `cursor band` row is white with a dark glyph; the `grey band` is untouched.
- `npm run bench:feel -- --feature cursorHollowUnfocused` → open `baselines/glyph-probe/feature-cursorHollowUnfocused/offset-100.png`: the cursor is an outline.
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → clean.

CHANGELOG:

```markdown
- renderer-dom: `RendererFeatures.cursorContrast` inverts the cursor (foreground box, background-coloured glyph) when the cell's background is within contrast 1.5 of the cursor colour (Alacritty `MIN_CURSOR_CONTRAST`); `cursorHollowUnfocused` draws a hollow block while the surface has no focus (Ghostty `cursor.zig`), reported by `TerminalSurface` through `DomBlockRenderer.setFocused`. Both default off. Side-by-side: `baselines/glyph-probe/feature-cursorContrast/`, `feature-cursorHollowUnfocused/`.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom/src packages/terminal/ts/react/src packages/terminal/bench/agent-session packages/terminal/CHANGELOG.md && git commit -m "renderer-dom: contrast-inverted and hollow-unfocused cursor behind flags

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: IME composition view at the cursor, one send after `setTimeout(0)`

**Files:**
- Modify: `packages/terminal/ts/core/src/composition-target.ts`, `composition-target.test.ts`
- Modify: `packages/terminal/ts/core/src/index-browser.ts` (export `anchorFromElement`, `type CompositionAnchor`)
- Modify: `packages/terminal/ts/editor/src/line-editor.ts` (`EditorHost.compositionAnchor`), `line-editor.test.ts`, `ts/editor/src/styles.css` + `styles.ts` (`.terminal-editor { position: relative }`)
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx` (anchors for both targets)
- Create: `packages/terminal/ts/react/src/TerminalSurface.ime.test.tsx`
- Modify: `packages/terminal/ts/renderer-dom/src/styles.css`, `styles.ts`, `styles-parity.test.ts` (`.terminal-composition-view`)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `createCompositionTarget` (`composition-target.ts`, already tracks start/end and commits on blur), the keydown swallow while composing (`TerminalSurface.tsx:223`, `line-editor.ts:169`) which stays as is, the primary cursor element `[data-terminal-cursor-cell]` (`cursor.ts` `CURSOR_ATTR`) and the alt cursor `[data-terminal-cursor]` (`alt-surface.ts:5`).
- Produces: `type CompositionAnchor = Readonly<{ left: number; top: number; height: number }>` (px inside `parent`'s padding box, scroll included); `createCompositionTarget({ parent, onCommit, anchor?: (parent: HTMLElement) => CompositionAnchor | null })`; `CompositionTarget.view: HTMLElement` (the `.terminal-composition-view` span, class `active` while composing); `anchorFromElement(parent: HTMLElement, cell: Element | null): CompositionAnchor | null`; `EditorHost.compositionAnchor?: (parent: HTMLElement) => CompositionAnchor | null`.

Port of `xterm.js/src/browser/input/CompositionHelper.ts:73-95` (`compositionstart` records the textarea selection as the composition start and activates the view; `compositionupdate` writes `‎<data>‎` and repositions) and `:120-200` (`_finalizeComposition`: after `compositionend`, a `setTimeout(0)` reads the textarea's settled value — Chromium's `compositionend.data` is unreliable and the last `compositionupdate` is not always the final text — and sends `value.substring(start)` once, or `substring(start, newStart)` when another composition already began). Warp draws marked text over the grid from the cursor point, underlined (`app/src/terminal/grid_renderer.rs:657-675`), which is the look the view copies.

- [ ] **Step 1: Rewrite the composition-target tests for the settled-value contract and the view**

In `composition-target.test.ts` replace "commits the composed text once, on compositionend", "clears the textarea after a commit…" and "does not commit an empty composition" with:

```ts
	it("commits the textarea's settled value once, a tick after compositionend", () => {
		vi.useFakeTimers();
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.value = "に";
		target.element.dispatchEvent(new CompositionEvent("compositionupdate", { data: "に" }));
		target.element.value = "日";
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "日" }));
		expect(onCommit).not.toHaveBeenCalled();
		target.element.value = "日本";
		vi.runAllTimers();
		expect(onCommit).toHaveBeenCalledTimes(1);
		expect(onCommit).toHaveBeenCalledWith("日本");
		expect(target.element.value).toBe("");
		expect(target.isComposing()).toBe(false);
		vi.useRealTimers();
	});

	it("sends only the finished part when a new composition starts before the tick", () => {
		vi.useFakeTimers();
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.value = "日";
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "日" }));
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.value = "日ほ";
		vi.runAllTimers();
		expect(onCommit).toHaveBeenCalledTimes(1);
		expect(onCommit).toHaveBeenCalledWith("日");
		expect(target.isComposing()).toBe(true);
		expect(target.element.value).toBe("日ほ");
		vi.useRealTimers();
	});

	it("does not commit an empty composition", () => {
		vi.useFakeTimers();
		const onCommit = vi.fn();
		const target = createCompositionTarget({ parent, onCommit });
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "" }));
		vi.runAllTimers();
		expect(onCommit).not.toHaveBeenCalled();
		vi.useRealTimers();
	});

	it("shows the in-progress text at the anchor and hides it when composition ends", () => {
		vi.useFakeTimers();
		const target = createCompositionTarget({ parent, onCommit: () => undefined, anchor: () => ({ left: 24, top: 40, height: 20 }) });
		expect(parent.contains(target.view)).toBe(true);
		expect(target.view.classList.contains("active")).toBe(false);
		target.element.dispatchEvent(new CompositionEvent("compositionstart"));
		target.element.value = "に";
		target.element.dispatchEvent(new CompositionEvent("compositionupdate", { data: "に" }));
		expect(target.view.classList.contains("active")).toBe(true);
		expect(target.view.textContent).toBe("‎に‎");
		expect(target.view.style.left).toBe("24px");
		expect(target.view.style.top).toBe("40px");
		expect(target.view.style.height).toBe("20px");
		target.element.dispatchEvent(new CompositionEvent("compositionend", { data: "に" }));
		expect(target.view.classList.contains("active")).toBe(false);
		vi.runAllTimers();
		vi.useRealTimers();
	});

	it("anchorFromElement measures the cell against the parent's padding box", () => {
		const cell = document.createElement("span");
		parent.append(cell);
		vi.spyOn(parent, "getBoundingClientRect").mockReturnValue({ left: 100, top: 50 } as DOMRect);
		vi.spyOn(cell, "getBoundingClientRect").mockReturnValue({ left: 132, top: 90, height: 20 } as DOMRect);
		Object.defineProperty(parent, "clientLeft", { value: 1 });
		Object.defineProperty(parent, "clientTop", { value: 1 });
		Object.defineProperty(parent, "scrollTop", { value: 10, writable: true });
		expect(anchorFromElement(parent, cell)).toEqual({ left: 31, top: 49, height: 20 });
		expect(anchorFromElement(parent, null)).toBeNull();
	});
```

The blur test stays (blur commits immediately from the textarea value, as today).

`line-editor.test.ts` — add inside `describe("LineEditor ownership")` (the file's `mount()` returns `{ editor, host, container, … }`; extend `mount` to accept an optional `compositionAnchor` on `host`):

```ts
	it("hands the host's composition anchor to its composition target", () => {
		const { container } = mount({ compositionAnchor: () => ({ left: 8, top: 16, height: 20 }) });
		const input = container.querySelector<HTMLTextAreaElement>("[data-terminal-input]")!;
		input.dispatchEvent(new CompositionEvent("compositionstart"));
		input.dispatchEvent(new CompositionEvent("compositionupdate", { data: "に" }));
		const view = container.querySelector<HTMLElement>(".terminal-composition-view")!;
		expect(view.classList.contains("active")).toBe(true);
		expect(view.style.left).toBe("8px");
	});
```

`TerminalSurface.ime.test.tsx` (new, same preamble as `TerminalSurface.paste.test.tsx`):

```tsx
describe("IME composition on the surface", () => {
	it("sends the composed text once, from the settled textarea, in the alternate screen", () => {
		vi.useFakeTimers();
		const onSendRaw = vi.fn();
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive onSend={() => undefined} onSendRaw={onSendRaw} />,
		);
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		const input = container.querySelector<HTMLTextAreaElement>(".terminal-host [data-terminal-input]")!;
		act(() => {
			input.dispatchEvent(new CompositionEvent("compositionstart"));
			input.value = "に";
			input.dispatchEvent(new CompositionEvent("compositionupdate", { data: "に" }));
			input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", keyCode: 229, bubbles: true }));
		});
		expect(onSendRaw).not.toHaveBeenCalled();
		act(() => {
			input.value = "日本";
			input.dispatchEvent(new CompositionEvent("compositionend", { data: "日本" }));
			vi.runAllTimers();
		});
		expect(onSendRaw).toHaveBeenCalledTimes(1);
		expect(onSendRaw).toHaveBeenCalledWith("日本");
		expect(container.querySelector(".terminal-host .terminal-composition-view")).not.toBeNull();
		vi.useRealTimers();
	});

	it("gives the normal-buffer editor an anchor on the transcript cursor", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={() => undefined} />,
		);
		act(() => {
			feed(core, "> hi");
		});
		const input = container.querySelector<HTMLTextAreaElement>(".terminal-editor [data-terminal-input]")!;
		act(() => {
			input.dispatchEvent(new CompositionEvent("compositionstart"));
			input.dispatchEvent(new CompositionEvent("compositionupdate", { data: "に" }));
		});
		const view = container.querySelector<HTMLElement>(".terminal-editor .terminal-composition-view")!;
		expect(view.classList.contains("active")).toBe(true);
		expect(container.querySelector("[data-terminal-cursor-cell]")).not.toBeNull();
	});
});
```

`styles-parity.test.ts` — add `expect(terminalStyles).toContain(".terminal-composition-view.active");` in a new `it("styles the IME composition view like Warp's marked text")`.

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run src/composition-target.test.ts` → FAIL (commit fires synchronously with `event.data`; no `view`, no `anchorFromElement`). `cd ../editor && npx vitest run src/line-editor.test.ts` → FAIL. `cd ../react && npx vitest run src/TerminalSurface.ime.test.tsx` → FAIL.

- [ ] **Step 3: Implement**

`composition-target.ts`:

```ts
export type CompositionAnchor = Readonly<{ left: number; top: number; height: number }>;

export interface CompositionTarget {
	element: HTMLTextAreaElement;
	view: HTMLElement;
	focus(): void;
	isComposing(): boolean;
	dispose(): void;
}

export function anchorFromElement(parent: HTMLElement, cell: Element | null): CompositionAnchor | null {
	if (!cell) return null;
	const c = cell.getBoundingClientRect();
	const p = parent.getBoundingClientRect();
	return {
		left: c.left - p.left - parent.clientLeft + parent.scrollLeft,
		top: c.top - p.top - parent.clientTop + parent.scrollTop,
		height: c.height,
	};
}

export function createCompositionTarget(opts: {
	parent: HTMLElement;
	onCommit(text: string): void;
	anchor?: (parent: HTMLElement) => CompositionAnchor | null;
}): CompositionTarget {
	const element = document.createElement("textarea");
	… (the existing attributes and styles, unchanged)
	const view = document.createElement("span");
	view.className = "terminal-composition-view";
	view.setAttribute("aria-hidden", "true");

	let composing = false;
	let start = 0;
	let sending = false;

	const place = () => {
		const anchor = opts.anchor?.(opts.parent) ?? null;
		if (!anchor) return;
		view.style.left = `${anchor.left}px`;
		view.style.top = `${anchor.top}px`;
		view.style.height = `${anchor.height}px`;
		view.style.lineHeight = `${anchor.height}px`;
	};
	const selectionStart = () => {
		const s = element.selectionStart ?? element.value.length;
		const e = element.selectionEnd ?? s;
		return Math.min(s, e);
	};
	const onStart = () => {
		composing = true;
		start = selectionStart();
		view.textContent = "";
		view.classList.add("active");
		place();
	};
	const onUpdate = (event: CompositionEvent) => {
		view.textContent = `‎${event.data ?? ""}‎`;
		place();
	};
	// xterm.js src/browser/input/CompositionHelper.ts:120-200 (_finalizeComposition)
	const onEnd = () => {
		composing = false;
		view.classList.remove("active");
		const finishedStart = start;
		sending = true;
		setTimeout(() => {
			if (!sending) return;
			sending = false;
			const text = composing ? element.value.substring(finishedStart, start) : element.value.substring(finishedStart);
			if (!composing) element.value = "";
			if (text !== "") opts.onCommit(text);
		}, 0);
	};
	const onBlur = () => {
		if (!composing) return;
		composing = false;
		sending = false;
		view.classList.remove("active");
		const text = element.value.substring(start);
		element.value = "";
		if (text !== "") opts.onCommit(text);
	};

	element.addEventListener("compositionstart", onStart);
	element.addEventListener("compositionupdate", onUpdate);
	element.addEventListener("compositionend", onEnd);
	element.addEventListener("blur", onBlur);
	opts.parent.append(element, view);

	return {
		element,
		view,
		focus: () => element.focus({ preventScroll: true }),
		isComposing: () => composing,
		dispose: () => {
			sending = false;
			element.removeEventListener("compositionstart", onStart);
			element.removeEventListener("compositionupdate", onUpdate);
			element.removeEventListener("compositionend", onEnd);
			element.removeEventListener("blur", onBlur);
			element.remove();
			view.remove();
		},
	};
}
```

`index-browser.ts:43`: also export `anchorFromElement` and `type CompositionAnchor`.

`line-editor.ts`: `EditorHost` gains `compositionAnchor?: (parent: HTMLElement) => CompositionAnchor | null;`; `mount` passes `anchor: host.compositionAnchor` into `createCompositionTarget`. `ts/editor/src/styles.css` and its `styles.ts` copy: add `position: relative;` to `.terminal-editor` (no offsets, so no pixel change; it makes the root the view's containing block).

`TerminalSurface.tsx`: the normal-buffer mount passes `editor.mount(editorHost, core, { send: onSend, sendRaw: onSendRaw, compositionAnchor: (parent) => anchorFromElement(parent, blockHost.querySelector("[data-terminal-cursor-cell]")) })`; the alt-screen target passes `anchor: (parent) => anchorFromElement(parent, parent.querySelector("[data-terminal-cursor]"))`. (Import `anchorFromElement` from `@operator/terminal-core`.)

`styles.css`/`styles.ts` (renderer-dom), after the cursor rules:

```css
/* IME marked text over the cursor cell, underlined as Warp draws it
   (app/src/terminal/grid_renderer.rs:657-675); positioned like xterm.js's
   composition-view (css/xterm.css:79-91). */
.terminal-composition-view {
	position: absolute;
	display: none;
	z-index: 2;
	pointer-events: none;
	white-space: pre;
	font: inherit;
	color: var(--terminal-foreground);
	background: var(--terminal-background);
	text-decoration: underline;
	text-decoration-thickness: 0.09em;
}

.terminal-composition-view.active {
	display: inline-block;
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.

- [ ] **Step 5: Verify and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `npm run bench:selection` → PASS (a hidden span joined each surface).
- `npm run bench:feel` → `PASS feel gate: zero pixel diff`.
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p . && npx vitest run src/renderer/components/BlockTerminal.test.tsx` → PASS.

CHANGELOG:

```markdown
- core/editor/react: IME composition draws its in-progress text at the cursor cell (`.terminal-composition-view`, underlined like Warp's marked text) in both the transcript editor and the alternate screen, and the composed text is sent once from the textarea's settled value a tick after `compositionend` (xterm.js `CompositionHelper`), so Chromium's early `compositionend` no longer sends a partial string. Manual Japanese-IME check: <pending — see Step 6>.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts packages/terminal/CHANGELOG.md && git commit -m "terminal: IME composition view at the cursor and a settled single send on compositionend

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Manual IME verification (reported, not automated)**

Rebuild and hand over: `cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon`, then ask the user to restart the daemon and the app, open a Claude Code session, switch macOS input to Japanese (Hiragana), type `nihongo` and press Enter twice. Expected: the underlined preedit appears at the pane's cursor while typing; Claude's input box receives `日本語` exactly once, no romaji fragments. Record the outcome in the CHANGELOG line above (replace `<pending>` with the result and the date) in Task 12; until then, say it is pending and do not claim it verified.

---

### Task 10 (conditional): Box-drawing glyphs as cell-filling rectangles behind `boxDrawing`

**Gate:** run this task only if `packages/terminal/bench/agent-session/baselines/glyph-probe/EVIDENCE.json` from Task 1 says `"boxDrawing": "needed"`. Otherwise skip it and record in Task 12: "box drawing: not needed — `boxGapPx` = <n> (`EVIDENCE.json`, measured <date>)".

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/box-glyphs.ts`
- Create: `packages/terminal/ts/renderer-dom/src/box-glyphs.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/row-builder.ts` (`appendRunText` gains the box path under the flag)
- Modify: `packages/terminal/ts/renderer-dom/src/styles.css`, `styles.ts`, `styles-parity.test.ts`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: the block-glyph mechanism (`block-glyphs.ts` `GlyphRect` percent rectangles, `row-builder.ts` `glyphNode`, `.terminal-block-glyph` CSS), `RendererFeatures.boxDrawing`.
- Produces: `boxGlyph(codePoint: number): BoxGlyph | null` with `BoxGlyph = Readonly<{ rects: readonly GlyphRect[] }>` for `─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ ╭ ╮ ╰ ╯` (U+2500, 2502, 250C, 2510, 2514, 2518, 251C, 2524, 252C, 2534, 253C, 256D–2570) and `⎿` (U+23BF, drawn as `└`); `CLASS_BOX_GLYPH = "terminal-box-glyph"`; `BOX_STROKE_PERCENT = 8` (of the cell width; Ghostty derives `box_thickness` from the font's underline thickness, `src/font/sprite/draw/box.zig`, and at Hack 14px that is one device pixel, which 8 % of a ~8.4 px cell rounds to).

Reference: Ghostty `src/font/sprite/Face.zig:1-12` and `src/font/sprite/draw/box.zig` draw the box-drawing range procedurally at exactly the cell size so vertical strokes meet at row boundaries whatever the line height. The set above is what Claude Code prints (spec "What a Claude Code pane is"); rounded corners are drawn square (Ghostty draws arcs; a rect cannot, and a corner is one cell, so the difference is sub-glyph). Other code points in U+2500–257F keep coming from the font.

- [ ] **Step 1: Write the failing tests**

`box-glyphs.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { boxGlyph, BOX_STROKE_PERCENT, CLASS_BOX_GLYPH } from "./box-glyphs";
import { buildRowNode, type RowSource } from "./row-builder";
import { DEFAULT_FEATURES } from "./features";

function rowOf(text: string, boxDrawing: boolean): HTMLElement {
	const content = new TextEncoder().encode(text);
	const source: RowSource = {
		content,
		rows: Uint32Array.from([0, content.byteLength]),
		runRanges: Uint32Array.from([0, 1]),
		stylePairs: Uint32Array.from([content.byteLength, 255, 254, 0, 255]),
	};
	return buildRowNode(source, 0, 0, new TextDecoder(), 8, { ...DEFAULT_FEATURES, boxDrawing });
}

describe("boxGlyph", () => {
	it("draws a vertical bar the full cell height and a horizontal bar the full width", () => {
		const half = 50 - BOX_STROKE_PERCENT / 2;
		expect(boxGlyph(0x2502)).toEqual({ rects: [{ x: half, y: 0, width: BOX_STROKE_PERCENT, height: 100 }] });
		expect(boxGlyph(0x2500)).toEqual({ rects: [{ x: 0, y: half, width: 100, height: BOX_STROKE_PERCENT }] });
	});
	it("composes corners, tees and the cross from half-arms", () => {
		expect(boxGlyph(0x250c)!.rects).toHaveLength(2);
		expect(boxGlyph(0x253c)!.rects).toHaveLength(4);
		expect(boxGlyph(0x23bf)).toEqual(boxGlyph(0x2514));
		expect(boxGlyph(0x256d)).toEqual(boxGlyph(0x250c));
	});
	it("claims nothing outside the set", () => {
		expect(boxGlyph(0x2501)).toBeNull();
		expect(boxGlyph(0x41)).toBeNull();
	});
});

describe("box glyphs in a row", () => {
	it("stay font glyphs by default and become rectangles under boxDrawing", () => {
		expect(rowOf("│a", false).querySelector(`.${CLASS_BOX_GLYPH}`)).toBeNull();
		const row = rowOf("│a", true);
		const glyph = row.querySelector<HTMLElement>(`.${CLASS_BOX_GLYPH}`)!;
		expect(glyph.textContent).toBe("│");
		expect(glyph.querySelectorAll("i")).toHaveLength(1);
		expect(row.textContent).toBe("│a");
	});
});
```

`styles-parity.test.ts`: `expect(terminalStyles).toContain(".terminal-box-glyph");`.

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/box-glyphs.test.ts src/styles-parity.test.ts` → FAIL.

- [ ] **Step 3: Implement**

`box-glyphs.ts`:

```ts
import type { GlyphRect } from "./block-glyphs.js";

export const CLASS_BOX_GLYPH = "terminal-box-glyph";
export const BOX_STROKE_PERCENT = 8;

export type BoxGlyph = Readonly<{ rects: readonly GlyphRect[] }>;

type Arm = "up" | "down" | "left" | "right";

const HALF = 50 - BOX_STROKE_PERCENT / 2;

// ghostty/src/font/sprite/draw/box.zig: every glyph is a union of arms from
// the cell centre to an edge; the centre square keeps the joins seamless.
function arm(side: Arm): GlyphRect {
	switch (side) {
		case "up":
			return { x: HALF, y: 0, width: BOX_STROKE_PERCENT, height: 50 + BOX_STROKE_PERCENT / 2 };
		case "down":
			return { x: HALF, y: HALF, width: BOX_STROKE_PERCENT, height: 50 + BOX_STROKE_PERCENT / 2 };
		case "left":
			return { x: 0, y: HALF, width: 50 + BOX_STROKE_PERCENT / 2, height: BOX_STROKE_PERCENT };
		case "right":
			return { x: HALF, y: HALF, width: 50 + BOX_STROKE_PERCENT / 2, height: BOX_STROKE_PERCENT };
	}
}

const FULL_VERTICAL: BoxGlyph = { rects: [{ x: HALF, y: 0, width: BOX_STROKE_PERCENT, height: 100 }] };
const FULL_HORIZONTAL: BoxGlyph = { rects: [{ x: 0, y: HALF, width: 100, height: BOX_STROKE_PERCENT }] };

const ARMS: ReadonlyMap<number, readonly Arm[]> = new Map([
	[0x250c, ["down", "right"]],
	[0x2510, ["down", "left"]],
	[0x2514, ["up", "right"]],
	[0x2518, ["up", "left"]],
	[0x251c, ["up", "down", "right"]],
	[0x2524, ["up", "down", "left"]],
	[0x252c, ["down", "left", "right"]],
	[0x2534, ["up", "left", "right"]],
	[0x253c, ["up", "down", "left", "right"]],
	[0x256d, ["down", "right"]],
	[0x256e, ["down", "left"]],
	[0x256f, ["up", "left"]],
	[0x2570, ["up", "right"]],
	[0x23bf, ["up", "right"]],
]);

export function boxGlyph(codePoint: number): BoxGlyph | null {
	if (codePoint === 0x2502) return FULL_VERTICAL;
	if (codePoint === 0x2500) return FULL_HORIZONTAL;
	const arms = ARMS.get(codePoint);
	return arms ? { rects: arms.map(arm) } : null;
}

export function isBoxGlyph(codePoint: number): boolean {
	return codePoint === 0x2500 || codePoint === 0x2502 || ARMS.has(codePoint);
}
```

`row-builder.ts`: `appendRunText(run, text, foreground, features)`; the pattern test becomes `BLOCK_GLYPH_PATTERN.test(text) || (features.boxDrawing && BOX_GLYPH_PATTERN.test(text))` with `const BOX_GLYPH_PATTERN = /[─│┌┐└┘├┤┬┴┼╭-╰⎿]/;`; in the per-character loop, when `features.boxDrawing` and `boxGlyph(cp)` is non-null, append `boxNode(character, glyph, foreground)`:

```ts
function boxNode(character: string, glyph: BoxGlyph, foreground: string): HTMLElement {
	const node = document.createElement("span");
	node.className = CLASS_BOX_GLYPH;
	node.textContent = character;
	for (const rect of glyph.rects) {
		const fill = document.createElement("i");
		fill.style.left = `${rect.x}%`;
		fill.style.top = `${rect.y}%`;
		fill.style.width = `${rect.width}%`;
		fill.style.height = `${rect.height}%`;
		fill.style.background = foreground;
		node.append(fill);
	}
	return node;
}
```

`styles.css`/`styles.ts`: `.terminal-box-glyph` with the same declarations as `.terminal-block-glyph` (`position: relative; display: inline-block; vertical-align: top; height: var(--terminal-line-height); width: 1ch; color: transparent; letter-spacing: 0;`) and `.terminal-box-glyph > i { position: absolute; }`, under a citation comment naming `ghostty/src/font/sprite/draw/box.zig`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run` → PASS.

- [ ] **Step 5: Verify, evidence, commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS; `npm run bench:selection` → PASS.
- `npm run bench:feel` → `PASS feel gate: zero pixel diff`.
- `npm run bench:feel -- --feature boxDrawing` and `npm run bench:glyphs -- --features boxDrawing` → `EVIDENCE-boxDrawing.json` must report `boxGapPx: 0`; if it does not, the stroke rectangles do not meet at the row boundary — inspect `box-zoom-boxDrawing.png` before touching the CSS.

CHANGELOG:

```markdown
- renderer-dom: `RendererFeatures.boxDrawing` draws `─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ ╭ ╮ ╰ ╯ ⎿` as cell-filling rectangles (Ghostty `src/font/sprite/draw/box.zig`), closing the <n> px gap the baseline showed between `│` rows at line-height 1.2 (`baselines/glyph-probe/EVIDENCE.json` → `EVIDENCE-boxDrawing.json`). Default off.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom/src packages/terminal/bench/agent-session/baselines packages/terminal/CHANGELOG.md && git commit -m "renderer-dom: procedural box-drawing glyphs behind RendererFeatures.boxDrawing

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11 (conditional): Width cache — per-cluster `letter-spacing` for fallback glyphs, behind `widthCache`

**Gate:** run this task only if `EVIDENCE.json` from Task 1 says `"widthCache": "needed"`. Otherwise skip it and record in Task 12: "width cache: not needed — `wideDriftPx` = <n>, `cjkDriftPx` = <n> (`EVIDENCE.json`, measured <date>)".

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/width-cache.ts`
- Create: `packages/terminal/ts/renderer-dom/src/width-cache.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/row-builder.ts` (`buildRowNode` gains an optional `widths: WidthCache | null` after `features`)
- Modify: `packages/terminal/ts/renderer-dom/src/block-body.ts`, `alt-surface.ts`, `dom-block-renderer.ts` (owns one `WidthCache`, cleared on `setFont`/DPR change)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `rowClusters` and the row's spans (Task 7), the hidden measure host (`host-dom.ts` `ensureMeasureHost`, `dom-block-renderer.ts:474` `applyFontToMeasureNode`), `RendererFeatures.widthCache`.
- Produces: `class WidthCache { constructor(measure: (text: string, bold: boolean, italic: boolean) => number); get(text, bold, italic): number; clear(): void }`; `REPEAT = 32`; `createDomMeasurer(node: HTMLElement): (text, bold, italic) => number`; `buildRowNode(source, row, label, decoder, cellWidth, features, widths = null)`.

Reference: `xterm.js/src/browser/renderer/dom/WidthCache.ts:1-60` (a flat array for code points < 256 × four font variants and a `Map` beyond, measured with `REPEAT = 32` copies in a hidden span, cleared on font change) and `DomRendererRowFactory.ts:477-480` (`letter-spacing = cells × cellWidth − measured` on the span). Only clusters with a non-ASCII scalar are measured; ASCII is the monospace font's own advance.

- [ ] **Step 1: Write the failing tests**

`width-cache.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest";
import { REPEAT, WidthCache } from "./width-cache";
import { buildRowNode, type RowSource } from "./row-builder";
import { DEFAULT_FEATURES } from "./features";

describe("WidthCache", () => {
	it("measures each distinct text once per variant and forgets on clear", () => {
		const measure = vi.fn((text: string) => (text === "漢" ? 17 : 8));
		const cache = new WidthCache(measure);
		expect(cache.get("漢", false, false)).toBe(17);
		expect(cache.get("漢", false, false)).toBe(17);
		expect(cache.get("漢", true, false)).toBe(17);
		expect(measure).toHaveBeenCalledTimes(2);
		cache.clear();
		cache.get("漢", false, false);
		expect(measure).toHaveBeenCalledTimes(3);
		expect(REPEAT).toBe(32);
	});
});

describe("letter-spacing correction in a row", () => {
	function rowOf(text: string, spans: number[], widthCache: boolean, measured: number): HTMLElement {
		const content = new TextEncoder().encode(text);
		const source: RowSource = {
			content,
			rows: Uint32Array.from([0, content.byteLength]),
			runRanges: Uint32Array.from([0, 1]),
			stylePairs: Uint32Array.from([content.byteLength, 255, 254, 0, 255]),
			spanRanges: Uint32Array.from([0, spans.length / 3]),
			cellSpans: Uint32Array.from(spans),
		};
		const cache = new WidthCache(() => measured);
		return buildRowNode(source, 0, 0, new TextDecoder(), 8, { ...DEFAULT_FEATURES, widthCache }, cache);
	}
	it("pads a glyph narrower than its cells and pulls in one that is wider", () => {
		const wide = rowOf("a漢b", [1, 4, 2], true, 17);
		const corrected = wide.querySelector<HTMLElement>("[data-terminal-width]")!;
		expect(corrected.textContent).toBe("漢");
		expect(corrected.style.letterSpacing).toBe("-1px");
		expect(wide.textContent).toBe("a漢b");
		const narrow = rowOf("a漢b", [1, 4, 2], true, 15);
		expect(narrow.querySelector<HTMLElement>("[data-terminal-width]")!.style.letterSpacing).toBe("1px");
	});
	it("leaves ascii and exact glyphs alone, and everything alone with the flag off", () => {
		expect(rowOf("abc", [], true, 8).querySelector("[data-terminal-width]")).toBeNull();
		expect(rowOf("a漢b", [1, 4, 2], true, 16).querySelector("[data-terminal-width]")).toBeNull();
		expect(rowOf("a漢b", [1, 4, 2], false, 17).querySelector("[data-terminal-width]")).toBeNull();
	});
});
```

- [ ] **Step 2: Run to see it fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/width-cache.test.ts` → FAIL.

- [ ] **Step 3: Implement**

`width-cache.ts`:

```ts
// xterm.js src/browser/renderer/dom/WidthCache.ts
export const REPEAT = 32;

export type Measurer = (text: string, bold: boolean, italic: boolean) => number;

export class WidthCache {
	private readonly cache = new Map<string, number>();

	constructor(private readonly measure: Measurer) {}

	get(text: string, bold: boolean, italic: boolean): number {
		const key = `${bold ? "b" : ""}${italic ? "i" : ""}:${text}`;
		let width = this.cache.get(key);
		if (width === undefined) {
			width = this.measure(text, bold, italic);
			this.cache.set(key, width);
		}
		return width;
	}

	clear(): void {
		this.cache.clear();
	}
}

export function createDomMeasurer(node: HTMLElement): Measurer {
	return (text, bold, italic) => {
		node.style.fontWeight = bold ? "700" : "";
		node.style.fontStyle = italic ? "italic" : "";
		node.textContent = text.repeat(REPEAT);
		const width = node.getBoundingClientRect().width / REPEAT;
		node.textContent = "M";
		node.style.fontWeight = "";
		node.style.fontStyle = "";
		return width;
	};
}
```

`row-builder.ts`: seventh parameter `widths: WidthCache | null = null`; when `features.widthCache && widths && cellWidth > 0` and the run's text is not pure ASCII, instead of `appendRunText(run, text, foreground)` call `appendMeasuredText(run, text, spansForRow, cellWidth, bold, italic, widths, foreground)`:

```ts
function appendMeasuredText(run: HTMLElement, text: string, spans: ArrayLike<number>, cellWidth: number, bold: boolean, italic: boolean, widths: WidthCache, foreground: string): void {
	let plain = "";
	for (const cluster of rowClusters(text, spans)) {
		const ascii = cluster.text.codePointAt(0)! < 0x80 && cluster.text.length === 1;
		const spacing = ascii ? 0 : Math.round((cluster.end - cluster.start) * cellWidth - widths.get(cluster.text, bold, italic));
		if (spacing === 0) {
			plain += cluster.text;
			continue;
		}
		if (plain !== "") {
			appendRunText(run, plain, foreground);
			plain = "";
		}
		const node = document.createElement("span");
		node.dataset.terminalWidth = "";
		node.textContent = cluster.text;
		node.style.letterSpacing = `${spacing}px`;
		run.append(node);
	}
	if (plain !== "") appendRunText(run, plain, foreground);
}
```

The run's `spans` slice comes from `source.spanRanges`/`cellSpans` for the row, offset by `rowCursor` (subtract the run's byte start from each span start/end; the row-level slice is computed once per row before the loop). `bold`/`italic` come from `styleCodeIsBold(styleCode)` and `(features.attributes === "warp" && (attrs & ATTR_ITALIC) !== 0)`.

`dom-block-renderer.ts`: `private widths: WidthCache | null = null;` created lazily in `measure()` from `createDomMeasurer(node)` once `metricsCache` is built, cleared in `invalidateMetrics()`; passed through `populateBlock` (`BlockBodyInput.widths`) and `renderAltSurface(…, features, widths)`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run` → PASS.

- [ ] **Step 5: Verify, evidence, commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS; `npm run bench:selection` → PASS.
- `npm run bench:feel` → `PASS feel gate: zero pixel diff`.
- `npm run bench:feel -- --feature widthCache` and `npm run bench:glyphs -- --features widthCache` → `EVIDENCE-widthCache.json`: `wideDriftPx` and `cjkDriftPx` within 1 px of 0.

CHANGELOG:

```markdown
- renderer-dom: `RendererFeatures.widthCache` measures each non-ASCII cluster once per font variant (xterm.js `WidthCache`) and applies `letter-spacing` so a fallback glyph wider or narrower than its cells no longer shifts the rest of the row; the baseline showed <wideDriftPx> / <cjkDriftPx> px of drift on the probe's emoji / CJK rows, now <values> (`EVIDENCE-widthCache.json`). Default off.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom/src packages/terminal/bench/agent-session/baselines packages/terminal/CHANGELOG.md && git commit -m "renderer-dom: width cache with per-cluster letter-spacing behind RendererFeatures.widthCache

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Measurement with every flag off and on, the "Plan D landed" note, `TERMINAL.md`

**Files:**
- Modify: `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` (baseline table "After Plan D" column; a "Plan D landed" paragraph after "Plan C landed")
- Modify: `TERMINAL.md` (§2 snapshot layout and checklist, §5 known gaps, §6 recipe)
- Modify: `packages/terminal/CHANGELOG.md` (the Task 9 pending line, if the manual IME check has been done)
- Modify: `packages/terminal/bench/agent-session/run.mjs` (`--features <list>` pass-through so the flags-on rows are measured by the same script)

**Interfaces:**
- Consumes: `npm run bench:agent`, `bench:agent:gate`, `bench:agent:scroll`, `bench:feel`, `bench:glyphs`; `?features=` on the harness page (Task 2).
- Produces: `npm run bench:agent -- --features <list>` (the page URL gains `&features=<list>`; nothing else changes), the documentation below.

No number in this task is invented. Every cell is copied from the command output of this HEAD after both wasm artifacts and the daemon were rebuilt. A flags-off regression against the "After Plan C" column beyond run-to-run noise is a **failure of Plan D**: stop, report it with the two outputs side by side, and do not tune anything to make it pass. A flags-on number that is worse than flags-off is reported as the cost of that flag.

- [ ] **Step 1: `run.mjs --features`**

In `packages/terminal/bench/agent-session/run.mjs` `parseArgs` add `else if (argv[index] === "--features") out.features = argv[++index];` (default `""`), thread `args.features` into `openPage(browser, port, fixture, features)` and append `&features=${encodeURIComponent(features)}` to its `goto` URL when non-empty. Run `node --test ./bench/agent-session/session-api.test.mjs ./bench/agent-session/fixtures.test.mjs` → PASS.

- [ ] **Step 2: Measure, flags off**

From `/Users/omaraly/development/AI/Operator/packages/terminal`, after `npm run build:wasm -- --force && npm run build:ts` and the vt-host/daemon rebuilds of the last Rust task:

```bash
npm run bench:agent
npm run bench:agent:gate
npm run bench:agent:scroll
npm run bench:feel
npm run bench:glyphs
```

Copy from the JSON lines: `feedCost` and `feedSyncCost` medians at 1k/5k/50k with their `reached`/`samples`, `spinner` paints/addedNodes/rowNodesAdded, `tearing`, `longTask.queued` (frames, total, mean, longest), `idlePanes.taskDurationS`, `selectionRepaint.rowsRepainted`, `reopen.{firstPaintMs,allRowsMs,rows}`, `rendererMemoryBytes`, `widthChange`, the scroll gate's coverage/trim/width lines, the feel gate's `PASS`, and the probe's `boxGapPx`/`wideDriftPx`/`cjkDriftPx`/`seqDriftPx`.

- [ ] **Step 3: Measure, every flag on**

```bash
npm run bench:agent -- --features attributes=warp,graphemes,cursorContrast,cursorHollowUnfocused,widthCache,boxDrawing
npm run bench:glyphs -- --features attributes=warp,graphemes,cursorContrast,cursorHollowUnfocused,widthCache,boxDrawing
```

(Drop `widthCache`/`boxDrawing` from both lists if Task 10/11 was skipped — a name the plumbing knows but no code reads is still a valid flag, so leaving them in is also correct; say which you did.) Copy the same rows. `bench:agent:gate` is not run with flags on: its thresholds are defined for the default configuration.

- [ ] **Step 4: Fill the spec**

In `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`:

1. Add an "After Plan D" column to the baseline table. Each cell holds the flags-off number first, then "flags on: …" for the rows Plan D can move (`feed()` cost, `feed()`+`snapshot()` cost, paints/s and DOM nodes per paint, row nodes per paint, idle panes, memory, pixel diff — `PASS` flags off; the side-by-side directories flags on) and "unchanged; Plan D does not touch it" with the number for the rest (scroll, reopen, width change, slow-link burst, torn frames — still measured, still copied).
2. After the "Plan C landed" paragraph add:

```markdown
Plan D landed <date>, measured on `development` HEAD (`<hash>`) after both wasm
artifacts and the daemon were rebuilt. Every visible change is behind
`RendererFeatures` (`packages/terminal/ts/renderer-dom/src/features.ts`),
set through `DomBlockRenderer.setFeatures` and the `features` prop of
`TerminalSurface`; Operator passes nothing, so every flag is at its default:

| Flag | Default | What it changes | Side-by-side |
|---|---|---|---|
| `attributes` | `"plain"` | `"warp"` paints italic/underline (5 styles, SGR 58 colour)/strike/overline/hidden, tags blink | `bench/agent-session/baselines/*/feature-attributes_warp/` |
| `graphemes` | `false` | core prints and rewraps by grapheme cluster; selection follows the exported spans | `…/feature-graphemes/`, `baselines/glyph-probe/EVIDENCE-graphemes.json` |
| `cursorContrast` | `false` | inverted cursor below contrast 1.5 | `…/feature-cursorContrast/` |
| `cursorHollowUnfocused` | `false` | hollow block while unfocused | `…/feature-cursorHollowUnfocused/` |
| `widthCache` | `false` | per-cluster letter-spacing (Task 11: <landed / not needed — evidence>) | `…/feature-widthCache/` or n/a |
| `boxDrawing` | `false` | procedural box glyphs (Task 10: <landed / not needed — evidence>) | `…/feature-boxDrawing/` or n/a |

Decision 4 stands: `attributes` defaults to `"plain"`. Flipping any default is a
one-line change in `DEFAULT_FEATURES` plus a re-recorded feel baseline; the
side-by-side screenshots above are what the user compares before that.

The IME composition view has no flag (spec Part 4). Manual Japanese-IME check:
<result and date, or "pending — not yet performed by the user">.

Conditional items, decided from `baselines/glyph-probe/EVIDENCE.json`
(measured <date>, cell <w>×<h> px): box drawing — `boxGapPx` = <n> →
<needed/not needed>; width cache — `wideDriftPx` = <n>, `cjkDriftPx` = <n> →
<needed/not needed>. `seqDriftPx` = <off> px with graphemes off and <on> px on.

Flags-off rows against Plan C: <one line per row: unchanged within noise, or
the regression and its size>. Flags-on cost: <feed at 50k, feed+sync at 50k,
nodes per paint, idle panes, memory — on vs off>.

Known gaps carried into `TERMINAL.md` §5: an underlined trailing blank is
still trimmed from the export; the pty-host mirror stays in scalar width mode
(its `clip_row` clips by `char`); `styles.json` covers no blink/overline case
because Alacritty's cell flags have none.
```

- [ ] **Step 5: `TERMINAL.md`**

- §2 "Snapshot" bullet: `stylePairs` (stride `STYLE_RUN_WORDS = 5`: `end, fg, bg, attrs, underline`), and add `spanRanges`/`cellSpans` (stride `CELL_SPAN_WORDS = 3`: `start, end, width` per cluster that is not a single width-1 scalar) to the list; in the checklist sentence add "…and, for a per-cell field, `AltSnapshot` in `screen/snapshot.rs` and the dead-prefix accounting in `ExportBuffers` (`dead_*`/`history_*` counters, `drop_front`, `rewrite_history_from`, `truncate_screen`, `compact`)".
- §2, a new bullet **Width mode**: `Parser::width_mode` (`WidthMode::Scalar` default, `Grapheme` via `TerminalCore::set_grapheme_clusters`), what joins in `ScreenGrid::join_previous`, that `RowIndex` measures rewrap with the same `clusters()`, that the mirror is always Scalar (Plan D deviation), and the corpus test.
- §5: replace the sentence that underline/italic/strike are not rendered with: rendered behind `RendererFeatures.attributes = "warp"`, default plain; add the three carried gaps from Step 4; note that a zero-width scalar after a space now rewraps with the space (Task 5).
- §6: add `npm run bench:glyphs` (evidence for the glyph probe) and `npm run bench:feel -- --feature <list>` (side-by-side, never diffed) after `bench:feel`.

- [ ] **Step 6: Final verification and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`: `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test`; `npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done`; `npm run bench:selection`; `npm run bench:feel` → `PASS feel gate: zero pixel diff`; `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...`; `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .`; `cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon`.

```bash
cd /Users/omaraly/development/AI/Operator && git add docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md TERMINAL.md packages/terminal/CHANGELOG.md packages/terminal/bench/agent-session/run.mjs && git commit -m "docs: Plan D landed — flags, side-by-side locations, conditional-item evidence, measurements

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

## Self-review record (written with the plan)

- **Spec coverage, Part 4 bullet by bullet:** SGR attributes parsed (Task 3) and rendered behind a flag (Task 4) including `4:x`, 58/59 and the four Alacritty recordings with a style expectation; grapheme clusters — ZWJ, VS16, modifiers, regional indicators (Task 5), TS width tables replaced by exported widths (Tasks 6, 7), corpus copied with attribution (Task 5); width cache only if the baseline shows drift (Task 1 evidence → Task 11); box drawing only if hairline gaps (Task 1 → Task 10); cursor inversion below 1.5 and hollow when unfocused behind flags (Task 8); IME composition view with the send-on-end race handled (Task 9). Global constraints and Decision 4: the header; the Plan D note and measurements: Task 12.
- **Placeholders:** the angle-bracket fields in Tasks 1, 4, 5, 9, 10, 11 and 12 are values the executor must copy from command output at execution time (numbers, dates, hashes, the manual IME result); they are not implementation gaps. No step says "similar to", "TBD" or "appropriate handling".
- **Type consistency:** the style word is `(end, fg, bg, attrs, underline)`, `STYLE_RUN_WORDS = 5`, in the layout table, Task 3 (Rust `push_row`, `export_layout.rs`, TS `style-runs.ts`, the three hand-built test arrays), Task 4 (`stylePairs[elementIndex + 3/4]`), Task 8 (`cursorPaintFor`, `source()` helper), Tasks 10–11 (`rowOf` helpers) and Task 12. Attribute bit names and values are identical in Rust `Attrs`, TS `ATTR_*`, the corpus tool's `FLAG_BITS` and the layout table. `CELL_SPAN_WORDS = 3` and the `(start, end, width)` order match across Task 6 (Rust, TS), Task 7 (`rowClusters`), Task 8 and Task 11. The six feature names and their defaults are identical in the layout section, Task 2's `features.ts`/tests/`parseFeatureList`, every later `{ ...DEFAULT_FEATURES, … }` use, the harness `--feature` names and Task 12's table. `set_grapheme_clusters`/`setGraphemeClusters`/`graphemeClusters` and `WidthMode::{Scalar, Grapheme}` are the same in Tasks 5, 6 and 12. `setFocused`, `CursorPaint`, `PLAIN_CURSOR_PAINT` and the two cursor classes are the same in Task 8's tests, implementation and CSS. `CompositionAnchor`/`anchorFromElement`/`compositionAnchor`/`view` are the same across `composition-target.ts`, `line-editor.ts` and `TerminalSurface.tsx` in Task 9.
