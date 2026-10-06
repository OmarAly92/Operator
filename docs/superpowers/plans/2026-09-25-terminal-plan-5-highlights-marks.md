# Terminal Plan 5 — Highlights and marks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **If the superpowers skills are not installed in your session, run the process by hand:** one fresh implementer subagent per task (give it this whole plan and its task number), then one spec-compliance review subagent and one code-quality review subagent on that task's diff, fix what they find, then move on; after the last task, one whole-branch review subagent on `git diff origin/development...HEAD`.

**Goal:** One highlight model in the terminal renderer — selection, find hits and user marks are ranges in stable-row coordinates with a kind and a priority, painted by one painter — plus user marks ("highlight your words") configured in Operator Settings and applied to every terminal.

**Architecture:** `ts/renderer-dom` gets a pure model (`highlights.ts`: `Highlight { kind, range, colour, rank }`, the priority table, `rowPaint`), a DOM painter (`highlight-painter.ts`, the only code that writes highlight paint to row elements), a marks module (`marks.ts`: compile rules, match per visible logical line, cache per line) and `renderer-highlights.ts`, which owns the selection state, the find hits and the compiled marks and calls the painter from `finishPaint` and on every change. The find bar stops touching the DOM and hands its hits to the renderer through a new `FindBarHost.highlightFind`. The package seam for marks is `DomBlockRenderer.setMarks(rules)` and `TerminalSurface`'s `marks` prop; Operator stores a list of `{pattern, regex, colour}` in `localStorage` through `ui-store`, edits it in Settings → Terminal highlights, and `BlockTerminal` turns it into renderer rules.

**Tech Stack:** TypeScript (renderer-dom, react, frontend), Vitest + jsdom, React 19 + shadcn primitives, zustand, Playwright benches (`bench:feel`, `bench:selection`, `bench:affordances`, `bench:agent:*`, `run.mjs --panes-only`).

**Spec:** `docs/terminal/2026-09-24-terminal-roadmap-design.md` "Plan 5 — Highlights and marks" and "Rules every plan obeys"; survey entries §1.8 and §5.6 in `docs/terminal/2026-09-19-terminal-reference-survey.md`; `TERMINAL.md` (whole file; §3, §4.11, §4.13, §4.26, §4.27, §4.28, §6).

**Branch:** `terminal/plan-5-highlights-marks`, cut from `origin/development` (planned against `5185f35be`). Push it; never merge it; never commit to `development` or `master`.

**Shared files (sibling plans in the same wave — Plan 3 OSC title/notifications, Plan 6 line-editor typeahead, Plan 7 "Load older output"):** this plan edits `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` (ends at exactly 600 lines, the `check:boundaries` cap), `packages/terminal/ts/renderer-dom/src/index.ts`, `packages/terminal/ts/react/src/TerminalSurface.tsx`, `packages/terminal/ts/react/src/index.ts`, `packages/terminal/bench/agent-session/main.ts`, `packages/terminal/bench/agent-session/run.mjs`, `packages/terminal/CHANGELOG.md`, `TERMINAL.md`, `docs/terminal/2026-09-19-terminal-reference-survey.md`, `docs/terminal/2026-09-24-not-done-plain-language.md`, `frontend/src/renderer/stores/ui-store.ts`, `frontend/src/renderer/i18n/en.json`, `frontend/src/renderer/components/BlockTerminal.tsx`, `frontend/src/renderer/components/BlockTerminal.test.tsx`, `frontend/src/renderer/components/GlobalSettingsForm.tsx`. Whoever merges second rebases; if `dom-block-renderer.ts` then exceeds 600 lines, move the six predictive-echo forwarders (`setPredictiveEcho` … `predictionCount`) behind one `echo` getter in a follow-up, not in this branch.

## Global Constraints

- No comments in new code (user's global rule; `TERMINAL.md` §3 rule 3). Existing comments may be corrected, never added.
- Commits: explicit paths only (`git add <path> …`). Never `git add -A`, `git add .`, `git commit -a`, or `git stash`. Never commit to `development` or `master`; never merge.
- Every commit message ends with the trailer line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- `packages/terminal` stays product-independent (`TERMINAL.md` §3 rule 1): no Operator name, path, palette or setting inside it. The package takes any CSS colour; Operator picks the palette.
- Cite `file:line` or write "not known". No guessed causes.
- No file under `packages/terminal` over 600 lines: `npm run check:boundaries` (in `packages/terminal`) must print `boundary check passed`.
- `styles.css` and `styles.ts` are not edited by this plan; `styles-parity.test.ts` must still pass (it forbids `contain: paint|size|strict|content` and `content-visibility`, and requires `styles.ts` byte-identical to `styles.css`).
- Kitty's marks are GPL-3.0: clean-room only. Do not open or copy any Kitty file. Ghostty `src/terminal/highlight.zig` (MIT) may be followed for behaviour; no Ghostty code is adapted here, so no attribution file.
- Pixels: with no marks, no selection and no find, `bench:feel` must be byte-identical to the **Task 0 baseline recorded on the unmodified tree in your environment** (the committed PNGs are not reproducible across machines). Selection and find screenshots must be byte-identical to the Task 0 captures. Never commit re-recorded feel baselines; `bench:affordances --action hover|hint|redact` rewrites committed PNGs — restore them with `git checkout -- packages/terminal/bench/agent-session/baselines` before any commit.
- Every listener you add has a teardown test; highlighting must never schedule a repaint (no invalidate loop).
- New `TERMINAL.md` section number for this plan: **§4.31** (§4.30 belongs to a sibling plan; leave the gap).
- Frontend: shadcn primitives from `frontend/src/renderer/components/ui/*`, copy through `t()` with keys in `frontend/src/renderer/i18n/en.json`, look per `DESIGN.md` top banner (clone agent-orchestrator; the terminal keeps its own palette).
- Tools that may be missing in a cloud session: the superpowers plugin (see header), Playwright's browser download (403 — Task 0 Step 3 workaround), Go module/toolchain downloads (`export GOTOOLCHAIN=auto`; if Go still cannot build, write `not run: <reason>` for the `bench:agent:gate` reopen row). A real desktop app cannot run in the cloud: the real-app checklist in the final task is for the user and is reported as `not run: no display in the cloud session`.

## Review Focus

- **Find hits on the alternate screen.** Find rows are stable transcript rows; alternate-screen rows are numbered 0…n, so a hit on stable row 3 could tint alt row 3. Expected: find paints nothing on the alternate screen (today's `TRANSCRIPT_ROWS` selector `[data-terminal-block-id] [data-terminal-row]`, `find-bar.ts:24`, excluded it). Test: Task 4 "marks the alternate screen but never paints find hits on it".
- **A mark colour the browser rejects.** All layers of a row live in one `background-image` declaration; one invalid colour makes the browser drop the whole declaration and the selection on that row vanishes. Expected: the bad rule is dropped at compile time and the selection stays. Tests: Task 3 "drops a colour the browser does not accept", Task 4 "keeps the selection when a mark's colour is rejected".
- **A pattern that matches everywhere** (`.`, `\d`, `\w+`). Expected: no hundreds of gradient layers per row — touching matches of one rule merge into one span. Test: Task 3 "merges touching matches of one rule into one span".
- **Settings changes reaching parked panes.** Operator applies marks to every terminal, including ones parked off screen, which must not be mutated (`parkedMutations` 0, `TERMINAL.md` §5 "What a parked pane still costs"). Expected: a parked pane paints nothing until shown, then paints the marks. Test: Task 4 "does not touch a parked pane's rows until it is shown again".
- **Rows the spinner rebuilds every frame.** Claude Code rewrites rows every 100 ms (`TERMINAL.md` §4.13); a mark painted once on an element that is then replaced would disappear. Expected: the painter repaints on every paint and the new row element carries the mark. Test: Task 4 "repaints marks on rows a later paint rebuilds".

---

## Design decisions (all fixed; the executor does not re-decide them)

1. **One model.** `Highlight = { kind, range, colour, rank }` where `range` is the selection's own `SelectionRange` (`selection-model.ts:7-8`: `{ start: {blockId, row, cell}, end: {…} }`, rows are stable rows — `TERMINAL.md` §2 "Stable rows"). Kinds and priority: `selection` 3 > `find-current` 2 > `find` 1 > `mark` 0; among marks, the earlier rule in the list wins (`rank` = index). `rowPaint(highlights, box, order, cellWidth)` turns them into per-row paint, top layer first. Ghostty's `highlight.zig:1-10` is the behavioural reference (one representation for selection, search and anything else); no code adapted.
2. **One painter, below the text.** `HighlightPainter.paint(rows, highlights, order, cellWidth)` writes each row's layers as a comma-joined `background-image` of the existing `fillGradient` strings (`selection-fill.ts:13-15`), and the same layers clipped with `runFill` onto runs that have their own background (`selection-fill.ts:5-11`, the §4.11 rule). It diffs against what it painted last, so an unchanged row gets no write (the "extending the selection by one row repaints one row" guard, `terminal-selection.test.ts`, keeps passing). It runs from `finishPaint` (today's `this.selection.paintFill()`, `dom-block-renderer.ts:563`) and synchronously on every highlight change; it never schedules a repaint.
3. **Links, hints, redaction and prediction stay on `decorations.ts`.** Evidence: they are overlays drawn *above* the text — `.terminal-decorations { z-index: 2; }` (`styles.css:226-228`); a redaction must hide the glyphs (`.terminal-redaction { background: var(--terminal-foreground); opacity: 0.85; }`, `styles.css:262-265`); a prediction draws text (`styles.css:269-281`); a link is a border under the cells (`styles.css:235-237`); a hint match paints over its label cells (`styles.css:242-244`, Alacritty's order). The highlight model paints *under* the text (row `background-image`, `TERMINAL.md` §4.11). Moving them onto the model would change what they are (a redaction would stop hiding secrets) and change pixels, so they stay where they are.
4. **Find keeps today's look, byte for byte.** Today a hit row gets class `terminal-find-row-match` (`background: var(--terminal-selection)` — the row's background colour, `styles.css:538-540`) and each row of the current hit gets `terminal-find-row-active` (a 1 px cursor-colour outline, `styles.css:542-545`) (`find-bar.ts:106-123`). The painter keeps both classes and both `data-terminal-find-row-*` attributes. Measured while planning (Chromium, a row with the selection colour as `background-color` against the same colour as a `linear-gradient` layer): 8,278 channel values differ, by at most 1 — so the find fill stays `background-color`, which is byte-identical. **One exception, by rule:** a row that has both a find hit and a mark gets the find fill as an image layer *above* the marks (so find > mark holds) and loses the class; only those rows can differ by that 1 level. The current hit is shown by the outline, not by a second fill (a second 40 % fill would double the tint).
5. **Find hits are whole rows, as today.** The find bar hands over `{ rows: Set<stableRow>, current: {row, endRow} | null }` (the same data `applyHighlights` uses, `find-bar.ts:106-123`); the model turns every *painted* row in the set into a whole-row `find` highlight using the row's own block id, so `FindMatch.blockId` is never needed for paint. Rows of the alternate screen are skipped (Review Focus 1).
6. **Marks are computed per painted row, and only touched rows are measured.** The painter gets layout-free row references and calls `getBoundingClientRect` only on rows a highlight touches (measured: measuring every row per paint doubled script time with 5 marks, Task 6 Step 9). Each paint joins the logical lines of the rows actually rendered (`visibleLogicalLines`, which never joins a line twice), runs every rule over each line's text, and maps matches back to cells with `LogicalLineView.rangeOf` (`logical-lines.ts:51-61`). Resulting ranges are cached per logical line and reused while its text and row offsets are unchanged (`MarkCache`, 512 lines, cleared when the rules change). Nothing is stored in rows, so a trim or a rewrap cannot leave a mark behind: the next paint recomputes from the text. Marks read the masked text (`overlays.textRows()`), so a mark can never outline a redacted secret. Marks apply on the alternate screen too.
7. **Rule semantics.** Literal = case-insensitive, special characters escaped, flags `gi`. Regex = exactly as written, flags `g` (case-sensitive). An empty pattern, an invalid regex or a colour `CSS.supports("color", …)` rejects is dropped with no error. A zero-length match is skipped (so `^`, `\b`, `x*` on text without `x` paint nothing and never loop — `String.prototype.matchAll` advances past empty matches). Touching or overlapping matches of one rule merge into one span.
8. **Package seam.** `MarkRule = { pattern: string; regex: boolean; colour: string }` (any CSS colour); `DomBlockRenderer.setMarks(rules)`, `DomBlockRenderer.setFindHighlights(find)`, `TerminalSurface` prop `marks?: readonly MarkRule[]` (re-applied after the surface rebuilds its renderer, and only when the rules' JSON changes), `FindBarHost.highlightFind(find | null)` (required). `MarkRule` is exported from `@operator/terminal-renderer-dom` and re-exported from `@operator/terminal-react`.
9. **Operator palette: five fixed colours, no picker.** Yellow (`--terminal-ansi-3`), red (`--terminal-ansi-1`), green (`--terminal-ansi-2`), cyan (`--terminal-ansi-6`), magenta (`--terminal-ansi-5`), each painted as `color-mix(in srgb, var(--terminal-ansi-N) 40%, transparent)`. Why: the colours come from the terminal's own palette variables (`style-vars.ts:8-10` sets `--terminal-ansi-0…15` on the container), so they follow the terminal theme; 40 % is the selection's own strength (`theme-warp.ts:17-20`, Warp's `rgb(118 167 250 / 0.4)`), strong enough to see and weak enough to keep white text readable; blue (`--terminal-ansi-4`) is left out because a blue mark would read as selected text; a fixed list stores a name, not a colour, so a theme change recolours every mark and no contrast check is needed.
10. **Operator persistence and UI.** `localStorage` key `opr.terminal.marks` holding a JSON array of `{ id, pattern, regex, colour }`, read and sanitised at startup, written on every change — the same pattern as `terminal-predictive-echo.ts` + `ui-store.ts:30,71,103,157,172,213-217`. At most 10 entries, 200 characters each (every rule runs over every painted line on every changed paint; the perf check uses 5). Settings → General gets a new section "Terminal highlights" right after the General rows (`GlobalSettingsForm.tsx:45-49`): one row per mark with an `Input`, a `.*` toggle `Button` (`aria-pressed`), a colour `SettingsOptionMenu` with swatches, and a remove `Button`; an "Add highlight" button; an invalid regex shows an inline alert and is not sent to terminals.
11. **Parked panes.** The painter does nothing while the renderer is not painting (`setVisible(false)`); the first paint after it is shown paints everything.

---

## File map

| Path | Status | Responsibility |
|---|---|---|
| `packages/terminal/ts/renderer-dom/src/highlights.ts` | create | Model: kinds, priority, `rowPaint` |
| `packages/terminal/ts/renderer-dom/src/highlights.test.ts` | create | Overlap order, spans, find rules |
| `packages/terminal/ts/renderer-dom/src/highlight-painter.ts` | create | The one painter: rows, runs, find classes, diffing |
| `packages/terminal/ts/renderer-dom/src/highlight-painter.test.ts` | create | Painter tests |
| `packages/terminal/ts/renderer-dom/src/marks.ts` | create | `MarkRule`, `compileMarks`, `markSpans`, `MarkCache`, `visibleLogicalLines`, `markHighlights` |
| `packages/terminal/ts/renderer-dom/src/marks.test.ts` | create | Literal/regex/case, invalid, zero-width, merge, wrap, cache |
| `packages/terminal/ts/renderer-dom/src/renderer-highlights.ts` | create | Owns selection + find + marks, calls the painter |
| `packages/terminal/ts/renderer-dom/src/dom-block-renderer.highlights.test.ts` | create | Integration: overlap, trim, rewrap, no repaint, parked, alt, dispose |
| `packages/terminal/ts/renderer-dom/src/renderer-selection.ts` | modify | Drop its own fill; ask for a highlight paint |
| `packages/terminal/ts/renderer-dom/src/selection-view.ts` | modify | Task 2: layout-free `renderedRowRefs` + `measureRow`; Task 4: delete `selectionFills` (moved into the painter) |
| `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` | modify | `highlights` field, `setMarks`, `setFindHighlights` |
| `packages/terminal/ts/renderer-dom/src/find-bar.ts` | modify | Hand hits to `host.highlightFind`; no DOM marking |
| `packages/terminal/ts/renderer-dom/src/find-bar.test.ts` | modify | Host gains `highlightFind` |
| `packages/terminal/ts/renderer-dom/src/find-bar.incremental.test.ts` | modify | Host gains `highlightFind`; new teardown test |
| `packages/terminal/ts/renderer-dom/src/index.ts` | modify | Export `FindHighlights`, `compileMarks`, `MarkRule`, `HIGHLIGHT_PRIORITY`, `HighlightKind` |
| `packages/terminal/ts/react/src/TerminalSurface.tsx` | modify | `marks` prop, `highlightFind` host |
| `packages/terminal/ts/react/src/TerminalSurface.marks.test.tsx` | create | Seam tests |
| `packages/terminal/ts/react/src/index.ts` | modify | Re-export `MarkRule` |
| `packages/terminal/bench/agent-session/highlight-probe.ts` | create | Bench helpers: select cells, drive the find bar, set marks |
| `packages/terminal/bench/agent-session/main.ts` | modify | Expose the probe; `?marks=N` |
| `packages/terminal/bench/agent-session/affordance-gate.mjs` | modify | `select`, `find`, `marks` actions; `--out`, `--compare` |
| `packages/terminal/bench/agent-session/run.mjs` | modify | `--marks N` |
| `packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-25-marks-*.json` | create | A/B evidence |
| `frontend/src/renderer/lib/terminal-marks.ts` | create | Palette, storage, sanitising, renderer rules |
| `frontend/src/renderer/lib/terminal-marks.test.ts` | create | |
| `frontend/src/renderer/stores/ui-store.ts` | modify | `terminalMarks`, `setTerminalMarks` |
| `frontend/src/renderer/stores/ui-store.terminal-marks.test.ts` | create | |
| `frontend/src/renderer/components/settings/TerminalMarksSection.tsx` | create | Settings UI |
| `frontend/src/renderer/components/settings/TerminalMarksSection.test.tsx` | create | |
| `frontend/src/renderer/components/GlobalSettingsForm.tsx` | modify | Render the section |
| `frontend/src/renderer/i18n/en.json` | modify | 15 keys |
| `frontend/src/renderer/components/BlockTerminal.tsx` | modify | Pass `marks` |
| `frontend/src/renderer/components/BlockTerminal.test.tsx` | modify | Two tests |
| `packages/terminal/CHANGELOG.md`, `TERMINAL.md`, survey, plain-language doc | modify | Docs |

---

### Task 0: Branch, toolchains, baselines and the selection/find probe

**Files:**
- Create: `packages/terminal/bench/agent-session/highlight-probe.ts`
- Modify: `packages/terminal/bench/agent-session/main.ts:10-12,16,545-546`
- Modify: `packages/terminal/bench/agent-session/affordance-gate.mjs:1,12-16,58-59,73-83`
- Outside the repo (never committed): `/tmp/plan5-baselines/`

**Interfaces:**
- Produces: `window.__agentSession.selectCells(fromRow, fromCell, toRow, toCell)`, `selectionClear()`, `findShow(query, steps) → count text`, `findHide()`; `affordance-gate.mjs --action select|find [--out <dir>] [--compare <dir>]`; the baseline directory `/tmp/plan5-baselines` with `feel/<fixture>/offset-*.png`, `affordance-select/*.png`, `affordance-find/*.png`, `counts.txt`.

- [ ] **Step 1: Create the branch**

```bash
cd "$(git rev-parse --show-toplevel)"
git fetch origin
git switch -c terminal/plan-5-highlights-marks origin/development
git log --oneline -1
```
Expected: one line; the hash is `5185f35be` or a later `development` commit. If it is later, run `git log --oneline 5185f35be..HEAD -- packages/terminal/ts/renderer-dom/src/find-bar.ts packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts packages/terminal/ts/renderer-dom/src/renderer-selection.ts` and, if it prints anything, re-check every quoted "find this text" block below against the file before editing.

- [ ] **Step 2: Check the toolchains and install**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
node --version
rustc --version
rustup target list --installed
wasm-bindgen --version
go version || true
npm ci --no-audit --no-fund
cd ../../frontend && npm ci --no-audit --no-fund
```
Expected: `rustc 1.96.0 …`; `wasm32-unknown-unknown` listed; `wasm-bindgen 0.2.127` (if missing: `cargo install wasm-bindgen-cli --version 0.2.127 --locked`; if `rustc` is another version, `rustup toolchain install 1.96.0 --target wasm32-unknown-unknown`, the repo's `packages/terminal/rust-toolchain.toml` pins it); both `npm ci` end with `added N packages`. If Go downloads fail later, `export GOTOOLCHAIN=auto` and retry once; `backend/go.mod:3` asks for `go 1.25.7`.

- [ ] **Step 3: Build and make Playwright's Chromium available**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
npm run build
npx playwright install chromium || echo "playwright download failed"
node -e 'const { chromium } = require("playwright"); console.log(chromium.executablePath())'
```
Expected: `npm run build` ends with the `tsc -b …` line and no error (it writes the gitignored `ts/core/wasm` and every `dist`). If the Playwright download fails (403) and `/opt/pw-browsers` exists, point Playwright at the preinstalled browsers, outside the repo:

```bash
export PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
ls /opt/pw-browsers
WANT_REV=$(node -e 'const p = require("playwright").chromium.executablePath(); console.log(p.split("/").find((part) => /^chromium-\d+$/.test(part)).split("-")[1])')
HAVE_FULL=$(ls -d /opt/pw-browsers/chromium-* | head -1)
HAVE_SHELL=$(ls -d /opt/pw-browsers/chromium_headless_shell-* | head -1)
[ -e "/opt/pw-browsers/chromium-$WANT_REV" ] || ln -s "$HAVE_FULL" "/opt/pw-browsers/chromium-$WANT_REV"
[ -e "/opt/pw-browsers/chromium_headless_shell-$WANT_REV" ] || ln -s "$HAVE_SHELL" "/opt/pw-browsers/chromium_headless_shell-$WANT_REV"
```
Keep `export PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers` in every later shell that runs a bench. If neither the download nor `/opt/pw-browsers` works, every Playwright gate in this plan is `not run: no Chromium` — say so in the report and continue.

- [ ] **Step 4: Record the unmodified tree's feel baseline outside the repo**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
mkdir -p /tmp/plan5-baselines/feel
node bench/agent-session/feel-gate.mjs --record
(cd bench/agent-session/baselines && for f in */offset-*.png; do mkdir -p "/tmp/plan5-baselines/feel/$(dirname "$f")"; cp "$f" "/tmp/plan5-baselines/feel/$f"; done)
git checkout -- bench/agent-session/baselines
git status --short
ls /tmp/plan5-baselines/feel
```
Expected: the record run ends with `recorded feel baselines`; `git status --short` prints nothing; the listing shows `act-probe claude-long-50k claude-markdown-reply claude-spinner-10s glyph-probe`.

- [ ] **Step 5: Record the unit-suite and lint counts**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
for p in core renderer-dom react editor; do (cd ts/$p && echo "== $p" && npx vitest run 2>&1 | grep -E "Test Files|Tests  "); done | tee /tmp/plan5-baselines/counts.txt
cd ../../frontend
npx vitest run --config vite.renderer.config.ts 2>&1 | grep -E "Test Files|Tests  " | tee -a /tmp/plan5-baselines/counts.txt
npx eslint src 2>&1 | tail -2 | tee -a /tmp/plan5-baselines/counts.txt
```
Expected: every suite passes (on the planning machine: renderer-dom `56 passed` files / `915 passed` tests, core `80 passed`, editor `162 passed`); eslint ends with `(0 errors, N warnings)`. Keep the file; later tasks compare against it.

- [ ] **Step 6: Write the probe module**

Create `packages/terminal/bench/agent-session/highlight-probe.ts`:

```ts
import { defaultStrings, type BlockRenderer, type TerminalCore } from "@operator/terminal-core";
import { createFindBar, type DomBlockRenderer, type FindBar, type SelectionPoint } from "@operator/terminal-renderer-dom";

export type HighlightProbe = {
	selectCells(fromRow: number, fromCell: number, toRow: number, toCell: number): Promise<void>;
	selectionClear(): Promise<void>;
	findShow(query: string, steps: number): Promise<string>;
	findHide(): Promise<void>;
};

function frame(): Promise<void> {
	return new Promise((resolve) => requestAnimationFrame(() => resolve()));
}

async function frames(count: number): Promise<void> {
	for (let index = 0; index < count; index += 1) await frame();
}

export function highlightProbe(host: HTMLElement, core: TerminalCore, renderer: DomBlockRenderer): HighlightProbe {
	let bar: FindBar | null = null;
	const point = (row: number, cell: number): SelectionPoint => {
		const node = host.querySelector<HTMLElement>(`[data-terminal-row="${core.snapshot().firstStableRow + row}"]`);
		if (!node) throw new Error(`row ${row} is not rendered`);
		const rect = node.getBoundingClientRect();
		const { cellWidth, cellHeight } = renderer.measure();
		const found = renderer.pointAt(rect.left + (cell + 0.25) * cellWidth, rect.top + cellHeight / 2);
		if (!found) throw new Error(`no cell at ${row}:${cell}`);
		return found;
	};
	return {
		async selectCells(fromRow, fromCell, toRow, toCell) {
			renderer.selectionBegin(point(fromRow, fromCell), "simple");
			renderer.selectionUpdate(point(toRow, toCell));
			await frames(2);
		},
		async selectionClear() {
			renderer.selectionClear();
			await frames(2);
		},
		async findShow(query, steps) {
			if (!bar) {
				bar = createFindBar({
					core,
					renderer: renderer as unknown as BlockRenderer,
					host: {
						scrollToBlock: (id, align) => renderer.scrollToBlock(id, align),
						scrollToRow: (row, align) => renderer.scrollToRow(row, align),
						invalidate: (range) => renderer.invalidate(range),
						afterRepaint: (listener) => renderer.onPaint(listener),
					},
					strings: defaultStrings,
				});
				bar.mount(host);
			}
			bar.open();
			const input = host.querySelector<HTMLInputElement>("input[data-terminal-find-input]");
			if (!input) throw new Error("the find bar has no input");
			input.value = query;
			input.dispatchEvent(new Event("input", { bubbles: true }));
			await frames(8);
			for (let step = 0; step < steps; step += 1) {
				input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));
				await frames(4);
			}
			input.blur();
			await frames(2);
			return host.querySelector("[data-terminal-find-count]")?.textContent ?? "";
		},
		async findHide() {
			bar?.close();
			await frames(2);
		},
	};
}
```

- [ ] **Step 7: Expose it from the agent-session page**

In `packages/terminal/bench/agent-session/main.ts`:

Find (lines 10-12):
```ts
} from "@operator/terminal-renderer-dom";

type SizeEntry = { offset: number; cols: number; rows: number };
```
Replace with:
```ts
} from "@operator/terminal-renderer-dom";
import { highlightProbe, type HighlightProbe } from "./highlight-probe";

type SizeEntry = { offset: number; cols: number; rows: number };
```

Find (line 16):
```ts
		__agentSession: AgentSession;
```
Replace with:
```ts
		__agentSession: AgentSession & HighlightProbe;
```

Find (lines 545-546):
```ts
	blocks: () => decodeBlocks(core.snapshot()).length,
} as AgentSession & { blocks(): number };
```
Replace with:
```ts
	blocks: () => decodeBlocks(core.snapshot()).length,
	...highlightProbe(host, core, domRenderer),
} as AgentSession & HighlightProbe & { blocks(): number };
```

- [ ] **Step 8: Add `select` and `find` actions, `--out` and `--compare` to the affordance gate**

In `packages/terminal/bench/agent-session/affordance-gate.mjs`:

Find (line 1):
```js
import { mkdir, writeFile } from "node:fs/promises";
```
Replace with:
```js
import { mkdir, readFile, writeFile } from "node:fs/promises";
```

Find (lines 12-16):
```js
const action = argv.includes("--action") ? argv[argv.indexOf("--action") + 1] : undefined;
if (!action) {
	process.stderr.write("usage: affordance-gate.mjs --action <hover|hint|redact>\n");
	process.exit(2);
}
```
Replace with:
```js
const action = argv.includes("--action") ? argv[argv.indexOf("--action") + 1] : undefined;
const outArg = argv.includes("--out") ? argv[argv.indexOf("--out") + 1] : undefined;
const compareDir = argv.includes("--compare") ? path.resolve(argv[argv.indexOf("--compare") + 1]) : undefined;
if (!action) {
	process.stderr.write("usage: affordance-gate.mjs --action <hover|hint|redact|select|find|marks> [--out <dir>] [--compare <dir>]\n");
	process.exit(2);
}
```

Find (lines 58-60):
```js
		return [["redact-boxes", painted, null]];
	},
};
```
Replace with:
```js
		return [["redact-boxes", painted, null]];
	},
	async select(page, shoot) {
		await page.evaluate(() => window.__agentSession.selectCells(0, 5, 2, 12));
		await shoot("select-rows");
		await page.evaluate(() => window.__agentSession.selectCells(3, 6, 3, 20));
		await shoot("select-one-row");
		await page.evaluate(() => window.__agentSession.selectionClear());
		await shoot("select-cleared");
		return [];
	},
	async find(page, shoot) {
		const first = await page.evaluate(() => window.__agentSession.findShow("example", 0));
		await shoot("find-first");
		const next = await page.evaluate(() => window.__agentSession.findShow("example", 1));
		await shoot("find-next");
		await page.evaluate(() => window.__agentSession.selectCells(0, 2, 0, 30));
		await shoot("find-under-selection");
		await page.evaluate(() => window.__agentSession.selectionClear());
		await page.evaluate(() => window.__agentSession.findHide());
		await shoot("find-closed");
		return [["find-count", first, next]];
	},
};
```

Find (lines 73-83):
```js
	const outDir = path.join(baselinesDir, `affordance-${action}`);
	await mkdir(outDir, { recursive: true });
	const shoot = async (name) => {
		await writeFile(path.join(outDir, `${name}.png`), await page.screenshot({ type: "png", animations: "disabled", caret: "hide" }));
		process.stdout.write(`side-by-side act-probe/affordance-${action}/${name}.png (compare with act-probe/offset-0.png)\n`);
	};
	const run = actions[action];
	if (!run) throw new Error(`unknown action ${action}`);
	const report = await run(page, shoot);
	process.stdout.write(`${JSON.stringify({ action, report })}\n`);
	await page.close();
```
Replace with:
```js
	const outDir = outArg ? path.resolve(outArg) : path.join(baselinesDir, `affordance-${action}`);
	await mkdir(outDir, { recursive: true });
	const shots = new Map();
	const differ = [];
	const shoot = async (name) => {
		const shot = await page.screenshot({ type: "png", animations: "disabled", caret: "hide" });
		shots.set(name, shot);
		await writeFile(path.join(outDir, `${name}.png`), shot);
		process.stdout.write(`side-by-side ${path.join(outDir, `${name}.png`)} (compare with act-probe/offset-0.png)\n`);
		if (!compareDir) return;
		const baseline = await readFile(path.join(compareDir, `${name}.png`));
		const same = Buffer.compare(baseline, shot) === 0;
		if (!same) differ.push(name);
		process.stdout.write(`${same ? "SAME" : "DIFF"} ${name}\n`);
	};
	const run = actions[action];
	if (!run) throw new Error(`unknown action ${action}`);
	const report = await run(page, shoot);
	if (shots.has("marks-before") && shots.has("marks-after")) {
		report.push(["marks-after-equals-before", Buffer.compare(shots.get("marks-before"), shots.get("marks-after")) === 0, null]);
	}
	process.stdout.write(`${JSON.stringify({ action, report })}\n`);
	await page.close();
	if (differ.length > 0) throw new Error(`${differ.length} screenshot(s) differ from ${compareDir}: ${differ.join(", ")}`);
	if (compareDir) process.stdout.write(`PASS ${action}: every screenshot matches ${compareDir}\n`);
```

- [ ] **Step 9: Capture selection and find on the unmodified renderer**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
node bench/agent-session/affordance-gate.mjs --action select --out /tmp/plan5-baselines/affordance-select | grep -v side-by-side
node bench/agent-session/affordance-gate.mjs --action find --out /tmp/plan5-baselines/affordance-find | grep -v side-by-side
ls /tmp/plan5-baselines/affordance-select /tmp/plan5-baselines/affordance-find
git status --short
```
Expected:
```
{"action":"select","report":[]}
{"action":"find","report":[["find-count","1 of 3","2 of 3"]]}
```
then `select-cleared.png select-one-row.png select-rows.png` and `find-closed.png find-first.png find-next.png find-under-selection.png`; `git status --short` lists only the three bench files. Open `find-under-selection.png`: rows 0, 2 and 7 carry the blue row tint, row 2 has a thin outline, row 0 has a brighter selection band from cell 2 to cell 30.

- [ ] **Step 10: Commit the probe**

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/bench/agent-session/highlight-probe.ts packages/terminal/bench/agent-session/main.ts packages/terminal/bench/agent-session/affordance-gate.mjs
git commit -m "bench: selection and find probes for the affordance gate, with --out and --compare

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 1: The highlight model

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/highlights.ts`
- Test: `packages/terminal/ts/renderer-dom/src/highlights.test.ts`

**Interfaces:**
- Consumes: `rowFillSpan(range: SelectionRange, box: RowBox, order: BlockOrder, cellWidth: number): FillSpan | null` (`selection-geometry.ts:47-62`), `ROW_END`, `SelectionRange`, `BlockOrder` (`selection-model.ts`), `FillSpan` (`selection-fill.ts:1`).
- Produces:
  - `type HighlightKind = "selection" | "find-current" | "find" | "mark"`
  - `type Highlight = Readonly<{ kind: HighlightKind; range: SelectionRange; colour: string; rank: number }>`
  - `type FillLayer = Readonly<{ span: FillSpan; colour: string }>`
  - `type RowPaint = Readonly<{ layers: readonly FillLayer[]; findMatch: boolean; findFill: boolean; findCurrent: boolean }>`
  - `const HIGHLIGHT_PRIORITY`, `const SELECTION_COLOUR = "var(--terminal-selection)"`, `const EMPTY_ROW_PAINT`
  - `compareHighlights(a, b): number`, `rowPaint(highlights, box, order, cellWidth): RowPaint`

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/renderer-dom/src/highlights.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { compareHighlights, EMPTY_ROW_PAINT, HIGHLIGHT_PRIORITY, rowPaint, SELECTION_COLOUR, type Highlight } from "./highlights";
import type { RowBox } from "./selection-geometry";
import { ROW_END, type BlockOrder } from "./selection-model";

const CELL = 10;
const order: BlockOrder = (blockId) => (blockId === "b" ? 0 : -1);
const box = (row: number): RowBox => ({ blockId: "b", row, firstRow: 100, rowCount: 10, left: 0, top: row * 20, bottom: row * 20 + 20, width: 400 });
const range = (startRow: number, startCell: number, endRow: number, endCell: number) => ({
	start: { blockId: "b", row: startRow, cell: startCell },
	end: { blockId: "b", row: endRow, cell: endCell },
});
const mark = (startCell: number, endCell: number, colour = "red", rank = 0, row = 101): Highlight => ({ kind: "mark", range: range(row, startCell, row, endCell), colour, rank });
const selection = (startCell: number, endCell: number, row = 101): Highlight => ({ kind: "selection", range: range(row, startCell, row, endCell), colour: SELECTION_COLOUR, rank: 0 });
const find = (row = 101): Highlight => ({ kind: "find", range: range(row, 0, row, ROW_END), colour: SELECTION_COLOUR, rank: 0 });
const current = (row = 101): Highlight => ({ kind: "find-current", range: range(row, 0, row, ROW_END), colour: SELECTION_COLOUR, rank: 0 });

describe("highlight priority", () => {
	it("orders selection over the current find hit over other find hits over user marks", () => {
		expect(HIGHLIGHT_PRIORITY.selection).toBeGreaterThan(HIGHLIGHT_PRIORITY["find-current"]);
		expect(HIGHLIGHT_PRIORITY["find-current"]).toBeGreaterThan(HIGHLIGHT_PRIORITY.find);
		expect(HIGHLIGHT_PRIORITY.find).toBeGreaterThan(HIGHLIGHT_PRIORITY.mark);
	});

	it("puts an earlier mark rule above a later one", () => {
		expect(compareHighlights(mark(0, 1, "red", 0), mark(0, 1, "blue", 1))).toBeLessThan(0);
		expect(compareHighlights(mark(0, 1, "blue", 1), selection(0, 1))).toBeGreaterThan(0);
	});
});

describe("rowPaint", () => {
	it("paints nothing on a row no highlight touches", () => {
		expect(rowPaint([mark(0, 3)], box(105), order, CELL)).toBe(EMPTY_ROW_PAINT);
	});

	it("lists fill layers top first: selection above a mark it overlaps", () => {
		const paint = rowPaint([mark(2, 8), selection(4, 6)], box(101), order, CELL);
		expect(paint.layers.map((layer) => layer.colour)).toEqual([SELECTION_COLOUR, "red"]);
		expect(paint.layers[0]!.span).toEqual({ left: 40, right: 60 });
		expect(paint.layers[1]!.span).toEqual({ left: 20, right: 80 });
	});

	it("keeps a find hit on the row's own colour when no mark shares the row", () => {
		const paint = rowPaint([find(), selection(1, 3)], box(101), order, CELL);
		expect(paint.findMatch).toBe(true);
		expect(paint.findFill).toBe(true);
		expect(paint.layers.map((layer) => layer.colour)).toEqual([SELECTION_COLOUR]);
	});

	it("lifts a find hit into a layer above the marks when a mark shares the row", () => {
		const paint = rowPaint([mark(2, 5), find(), selection(0, 1)], box(101), order, CELL);
		expect(paint.findMatch).toBe(true);
		expect(paint.findFill).toBe(false);
		expect(paint.layers.map((layer) => layer.colour)).toEqual([SELECTION_COLOUR, SELECTION_COLOUR, "red"]);
		expect(paint.layers[1]!.span).toEqual({ left: 0, right: 400 });
	});

	it("marks the current hit as an outline, not a second fill", () => {
		const paint = rowPaint([find(), current()], box(101), order, CELL);
		expect(paint.findCurrent).toBe(true);
		expect(paint.findFill).toBe(true);
		expect(paint.layers).toEqual([]);
	});

	it("paints a find hit even on a row with no width yet", () => {
		const paint = rowPaint([find()], { ...box(101), width: 0 }, order, CELL);
		expect(paint.findMatch).toBe(true);
	});

	it("fills a mark that wraps across rows to the edge of every row but its last", () => {
		const wrapped: Highlight = { kind: "mark", range: range(101, 30, 103, 4), colour: "red", rank: 0 };
		expect(rowPaint([wrapped], box(101), order, CELL).layers[0]!.span).toEqual({ left: 300, right: 400 });
		expect(rowPaint([wrapped], box(102), order, CELL).layers[0]!.span).toEqual({ left: 0, right: 400 });
		expect(rowPaint([wrapped], box(103), order, CELL).layers[0]!.span).toEqual({ left: 0, right: 40 });
	});

	it("drops an empty range", () => {
		expect(rowPaint([mark(4, 4)], box(101), order, CELL)).toBe(EMPTY_ROW_PAINT);
	});
});
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/renderer-dom"
npx vitest run src/highlights.test.ts
```
Expected: FAIL — `Failed to resolve import "./highlights"`.

- [ ] **Step 3: Implement**

Create `packages/terminal/ts/renderer-dom/src/highlights.ts`:

```ts
import type { FillSpan } from "./selection-fill.js";
import { rowFillSpan, type RowBox } from "./selection-geometry.js";
import type { BlockOrder, SelectionRange } from "./selection-model.js";

export type HighlightKind = "selection" | "find-current" | "find" | "mark";

export type Highlight = Readonly<{ kind: HighlightKind; range: SelectionRange; colour: string; rank: number }>;

export type FillLayer = Readonly<{ span: FillSpan; colour: string }>;

export type RowPaint = Readonly<{ layers: readonly FillLayer[]; findMatch: boolean; findFill: boolean; findCurrent: boolean }>;

export const HIGHLIGHT_PRIORITY: Readonly<Record<HighlightKind, number>> = { selection: 3, "find-current": 2, find: 1, mark: 0 };

export const SELECTION_COLOUR = "var(--terminal-selection)";

export const EMPTY_ROW_PAINT: RowPaint = { layers: [], findMatch: false, findFill: false, findCurrent: false };

export function compareHighlights(a: Highlight, b: Highlight): number {
	return HIGHLIGHT_PRIORITY[b.kind] - HIGHLIGHT_PRIORITY[a.kind] || a.rank - b.rank;
}

export function rowPaint(highlights: readonly Highlight[], box: RowBox, order: BlockOrder, cellWidth: number): RowPaint {
	const hits: { highlight: Highlight; span: FillSpan }[] = [];
	for (const highlight of highlights) {
		if (highlight.kind === "find" || highlight.kind === "find-current") {
			if (highlight.range.start.blockId === box.blockId && highlight.range.start.row === box.row) hits.push({ highlight, span: { left: 0, right: box.width } });
			continue;
		}
		const span = rowFillSpan(highlight.range, box, order, cellWidth);
		if (span) hits.push({ highlight, span });
	}
	if (hits.length === 0) return EMPTY_ROW_PAINT;
	hits.sort((a, b) => compareHighlights(a.highlight, b.highlight));
	const marked = hits.some(({ highlight }) => highlight.kind === "mark");
	const layers: FillLayer[] = [];
	let findMatch = false;
	let findCurrent = false;
	for (const { highlight, span } of hits) {
		if (highlight.kind === "find-current") {
			findCurrent = true;
			continue;
		}
		if (highlight.kind === "find") {
			if (findMatch) continue;
			findMatch = true;
			if (!marked) continue;
		}
		layers.push({ span, colour: highlight.colour });
	}
	return { layers, findMatch, findFill: findMatch && !marked, findCurrent };
}
```

- [ ] **Step 4: Run it to see it pass**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/renderer-dom"
npx vitest run src/highlights.test.ts
npx tsc --noEmit -p .
```
Expected: `Tests  10 passed (10)`; `tsc` prints nothing.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/ts/renderer-dom/src/highlights.ts packages/terminal/ts/renderer-dom/src/highlights.test.ts
git commit -m "renderer-dom: one highlight model with a kind, a priority and stable-row ranges

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: The painter

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/highlight-painter.ts`
- Test: `packages/terminal/ts/renderer-dom/src/highlight-painter.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/selection-view.ts:107-135` (split `renderedRows` into a layout-free `renderedRowRefs` and `measureRow`)

**Interfaces:**
- Consumes: Task 1's `rowPaint`, `FillLayer`, `Highlight`; `fillGradient`, `runFill` (`selection-fill.ts:5-15`); `compareBoundary`, `BlockOrder` (`selection-model.ts:11-20`).
- Produces:
  - in `selection-view.ts`: `type RowRef = Readonly<{ element: HTMLElement; blockId: string; row: number; firstRow: number; rowCount: number }>`, `renderedRowRefs(altRoot, filteredBlocks, blockElements, firstStableRow): RowRef[]` (no layout read), `measureRow(ref: RowRef): RenderedRow` (one `getBoundingClientRect`); `renderedRows(...)` keeps its signature and returns `renderedRowRefs(...).map(measureRow)`.
  - in `highlight-painter.ts`: `class HighlightPainter { idle(): boolean; paint(rows: readonly RowRef[], highlights: readonly Highlight[], order: BlockOrder, cellWidth: number): void; reset(): void }`; `class HighlightIndex { constructor(highlights, order); at(ref: RowRef): Highlight[] }`; `BUCKET_ROWS = 64`; `CLASS_ROW_MATCH = "terminal-find-row-match"`, `CLASS_ROW_ACTIVE = "terminal-find-row-active"`, `ATTR_ROW_MATCH = "data-terminal-find-row-match"`, `ATTR_ROW_ACTIVE = "data-terminal-find-row-active"`.

Why the painter takes `RowRef`s and measures lazily: the first build measured every rendered row with `getBoundingClientRect` on every paint (the old `renderedRows`). With 5 marks on the 10-visible pane-cost row that doubled ScriptDuration (0.27–0.33 s → 0.63–0.77 s per 10 s, planning run v1) and TaskDuration went 0.83–0.99 s → 1.29–1.57 s. Measuring only rows a highlight touches (`HighlightIndex` buckets short ranges by row; long ranges are checked with the same boundary test `rowFillSpan` uses) removed it (Task 6 Step 9).

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/renderer-dom/src/highlight-painter.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest";
import { ATTR_ROW_ACTIVE, ATTR_ROW_MATCH, BUCKET_ROWS, CLASS_ROW_ACTIVE, CLASS_ROW_MATCH, HighlightIndex, HighlightPainter } from "./highlight-painter";
import { SELECTION_COLOUR, type Highlight } from "./highlights";
import { ROW_END, type BlockOrder } from "./selection-model";
import type { RowRef } from "./selection-view";

const order: BlockOrder = () => 0;
const CELL = 10;

function row(index: number, runBackground = ""): RowRef {
	const element = document.createElement("div");
	element.dataset.terminalRow = String(index);
	element.getBoundingClientRect = () => ({ left: 0, right: 400, width: 400, top: index * 20, bottom: index * 20 + 20, height: 20, x: 0, y: index * 20, toJSON: () => ({}) }) as DOMRect;
	const run = document.createElement("span");
	run.dataset.terminalRun = "";
	run.style.backgroundColor = runBackground;
	run.getBoundingClientRect = () => ({ left: 20, right: 120, width: 100, top: 0, bottom: 20, height: 20, x: 20, y: 0, toJSON: () => ({}) }) as DOMRect;
	element.append(run);
	return { element, blockId: "b", row: index, firstRow: 0, rowCount: 200 };
}

const at = (kind: Highlight["kind"], rowIndex: number, startCell: number, endCell: number, colour = SELECTION_COLOUR, rank = 0): Highlight => ({
	kind,
	range: { start: { blockId: "b", row: rowIndex, cell: startCell }, end: { blockId: "b", row: rowIndex, cell: endCell } },
	colour,
	rank,
});

describe("HighlightPainter", () => {
	it("paints a selection exactly the way the selection fill did", () => {
		const rows = [row(0)];
		new HighlightPainter().paint(rows, [at("selection", 0, 2, 5)], order, CELL);
		expect(rows[0]!.element.style.backgroundImage).toBe(
			"linear-gradient(to right, transparent 20px, var(--terminal-selection) 20px, var(--terminal-selection) 50px, transparent 50px)",
		);
	});

	it("stacks layers top first so the selection sits above a mark", () => {
		const rows = [row(0)];
		new HighlightPainter().paint(rows, [at("mark", 0, 0, 8, "red"), at("selection", 0, 2, 5)], order, CELL);
		const image = rows[0]!.element.style.backgroundImage;
		expect(image.indexOf("var(--terminal-selection)")).toBeLessThan(image.indexOf("red"));
	});

	it("gives a find hit the row class and attribute, and the current hit the outline class", () => {
		const rows = [row(0), row(1)];
		new HighlightPainter().paint(rows, [at("find", 0, 0, ROW_END), at("find", 1, 0, ROW_END), at("find-current", 1, 0, ROW_END)], order, CELL);
		expect(rows[0]!.element.classList.contains(CLASS_ROW_MATCH)).toBe(true);
		expect(rows[0]!.element.hasAttribute(ATTR_ROW_MATCH)).toBe(true);
		expect(rows[0]!.element.classList.contains(CLASS_ROW_ACTIVE)).toBe(false);
		expect(rows[1]!.element.classList.contains(CLASS_ROW_ACTIVE)).toBe(true);
		expect(rows[1]!.element.hasAttribute(ATTR_ROW_ACTIVE)).toBe(true);
		expect(rows[0]!.element.style.backgroundImage).toBe("");
	});

	it("paints layers onto a run that has its own background, clipped to the run", () => {
		const rows = [row(0, "rgb(58, 58, 58)")];
		new HighlightPainter().paint(rows, [at("mark", 0, 3, 6, "red")], order, CELL);
		const run = rows[0]!.element.querySelector<HTMLElement>("[data-terminal-run]")!;
		expect(run.style.backgroundImage).toBe("linear-gradient(to right, transparent 10px, red 10px, red 40px, transparent 40px)");
	});

	it("leaves a run without a background alone", () => {
		const rows = [row(0)];
		new HighlightPainter().paint(rows, [at("mark", 0, 3, 6, "red")], order, CELL);
		expect(rows[0]!.element.querySelector<HTMLElement>("[data-terminal-run]")!.style.backgroundImage).toBe("");
	});

	it("clears everything it painted when the highlights go away", () => {
		const rows = [row(0, "rgb(58, 58, 58)"), row(1)];
		const painter = new HighlightPainter();
		painter.paint(rows, [at("mark", 0, 3, 6, "red"), at("find", 1, 0, ROW_END), at("find-current", 1, 0, ROW_END)], order, CELL);
		painter.paint(rows, [], order, CELL);
		expect(rows[0]!.element.style.backgroundImage).toBe("");
		expect(rows[0]!.element.querySelector<HTMLElement>("[data-terminal-run]")!.style.backgroundImage).toBe("");
		expect(rows[1]!.element.className).toBe("");
		expect(rows[1]!.element.hasAttribute(ATTR_ROW_MATCH)).toBe(false);
		expect(rows[1]!.element.hasAttribute(ATTR_ROW_ACTIVE)).toBe(false);
		expect(painter.idle()).toBe(true);
	});

	it("writes nothing to a row whose paint did not change", () => {
		const rows = [row(0), row(1)];
		const painter = new HighlightPainter();
		painter.paint(rows, [at("mark", 0, 0, 4, "red"), at("mark", 1, 0, 4, "red")], order, CELL);
		const writes: Node[] = [];
		const observer = new MutationObserver((records) => records.forEach((record) => writes.push(record.target)));
		for (const { element } of rows) observer.observe(element, { attributes: true });
		painter.paint(rows, [at("mark", 0, 0, 4, "red"), at("mark", 1, 0, 6, "red")], order, CELL);
		const records = observer.takeRecords();
		observer.disconnect();
		expect(records.map((record) => record.target)).toEqual([rows[1]!.element]);
	});

	it("measures only the rows a highlight touches", () => {
		const rows = Array.from({ length: 50 }, (_, index) => row(index));
		const measured = rows.map((ref) => vi.spyOn(ref.element, "getBoundingClientRect"));
		new HighlightPainter().paint(rows, [at("mark", 7, 0, 4, "red"), at("find", 30, 0, ROW_END)], order, CELL);
		expect(measured.flatMap((spy, index) => (spy.mock.calls.length > 0 ? [index] : []))).toEqual([7, 30]);
	});
});

describe("HighlightIndex", () => {
	const span = (startRow: number, endRow: number, blockId = "b"): Highlight => ({
		kind: "selection",
		range: { start: { blockId, row: startRow, cell: 0 }, end: { blockId, row: endRow, cell: 3 } },
		colour: SELECTION_COLOUR,
		rank: 0,
	});

	it("finds a short range on each of its rows and nowhere else", () => {
		const index = new HighlightIndex([span(3, 5)], order);
		expect([2, 3, 4, 5, 6].map((index_) => index.at(row(index_)).length)).toEqual([0, 1, 1, 1, 0]);
	});

	it("finds a range longer than a bucket on every row it covers", () => {
		const index = new HighlightIndex([span(1, BUCKET_ROWS + 10)], order);
		expect(index.at(row(0))).toHaveLength(0);
		expect(index.at(row(1))).toHaveLength(1);
		expect(index.at(row(BUCKET_ROWS + 5))).toHaveLength(1);
		expect(index.at(row(BUCKET_ROWS + 11))).toHaveLength(0);
	});

	it("follows block order for a selection that crosses blocks", () => {
		const twoBlocks: BlockOrder = (blockId) => (blockId === "a" ? 0 : blockId === "b" ? 1 : -1);
		const crossing: Highlight = { kind: "selection", range: { start: { blockId: "a", row: 8, cell: 2 }, end: { blockId: "b", row: 11, cell: 1 } }, colour: SELECTION_COLOUR, rank: 0 };
		const index = new HighlightIndex([crossing], twoBlocks);
		expect(index.at({ ...row(10), blockId: "b" })).toHaveLength(1);
		expect(index.at({ ...row(12), blockId: "b" })).toHaveLength(0);
		expect(index.at({ ...row(9), blockId: "a" })).toHaveLength(1);
		expect(index.at({ ...row(7), blockId: "a" })).toHaveLength(0);
	});
});
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/renderer-dom"
npx vitest run src/highlight-painter.test.ts
```
Expected: FAIL — `Failed to resolve import "./highlight-painter"`.

- [ ] **Step 3: Split `renderedRows` in `selection-view.ts`**

In `packages/terminal/ts/renderer-dom/src/selection-view.ts`, find (lines 107-135):
```ts
export function renderedRows(
	altRoot: HTMLElement | null,
	filteredBlocks: readonly BlockView[],
	blockElements: ReadonlyMap<BlockId, HTMLElement>,
	firstStableRow: number,
): RenderedRow[] {
	const out: RenderedRow[] = [];
	const push = (blockId: string, firstRow: number, rowCount: number, element: HTMLElement) => {
		const rect = element.getBoundingClientRect();
		out.push({
			element,
			box: { blockId, row: Number(element.dataset.terminalRow), firstRow, rowCount, left: rect.left, top: rect.top, bottom: rect.bottom, width: rect.width },
		});
	};
	const alt = altRoot && !altRoot.hidden ? altRoot : null;
	if (alt) {
		const rows = alt.querySelectorAll<HTMLElement>("[data-terminal-row]");
		for (const row of rows) push(ALT_BLOCK_ID, 0, rows.length, row);
		return out;
	}
	const byId = new Map(filteredBlocks.map((block) => [block.id, block] as const));
	for (const [id, section] of blockElements) {
		const block = byId.get(id);
		for (const row of section.querySelectorAll<HTMLElement>("[data-terminal-row]")) {
			push(id, firstStableRow + (block?.firstRow ?? 0), block?.rowCount ?? 0, row);
		}
	}
	return out;
}
```
Replace with:
```ts
export type RowRef = Readonly<{ element: HTMLElement; blockId: string; row: number; firstRow: number; rowCount: number }>;

export function renderedRowRefs(
	altRoot: HTMLElement | null,
	filteredBlocks: readonly BlockView[],
	blockElements: ReadonlyMap<BlockId, HTMLElement>,
	firstStableRow: number,
): RowRef[] {
	const out: RowRef[] = [];
	const alt = altRoot && !altRoot.hidden ? altRoot : null;
	if (alt) {
		const rows = alt.querySelectorAll<HTMLElement>("[data-terminal-row]");
		for (const element of rows) out.push({ element, blockId: ALT_BLOCK_ID, row: Number(element.dataset.terminalRow), firstRow: 0, rowCount: rows.length });
		return out;
	}
	const byId = new Map(filteredBlocks.map((block) => [block.id, block] as const));
	for (const [id, section] of blockElements) {
		const block = byId.get(id);
		const firstRow = firstStableRow + (block?.firstRow ?? 0);
		const rowCount = block?.rowCount ?? 0;
		for (const element of section.querySelectorAll<HTMLElement>("[data-terminal-row]")) {
			out.push({ element, blockId: id, row: Number(element.dataset.terminalRow), firstRow, rowCount });
		}
	}
	return out;
}

export function measureRow(ref: RowRef): RenderedRow {
	const rect = ref.element.getBoundingClientRect();
	return {
		element: ref.element,
		box: { blockId: ref.blockId, row: ref.row, firstRow: ref.firstRow, rowCount: ref.rowCount, left: rect.left, top: rect.top, bottom: rect.bottom, width: rect.width },
	};
}

export function renderedRows(
	altRoot: HTMLElement | null,
	filteredBlocks: readonly BlockView[],
	blockElements: ReadonlyMap<BlockId, HTMLElement>,
	firstStableRow: number,
): RenderedRow[] {
	return renderedRowRefs(altRoot, filteredBlocks, blockElements, firstStableRow).map(measureRow);
}
```
(`selectionFills`, lines 137-152, stays until Task 4.)

- [ ] **Step 4: Implement the painter**

Create `packages/terminal/ts/renderer-dom/src/highlight-painter.ts`:

```ts
import { rowPaint, type FillLayer, type Highlight } from "./highlights.js";
import { fillGradient, runFill } from "./selection-fill.js";
import { compareBoundary, type BlockOrder } from "./selection-model.js";
import { measureRow, type RowRef } from "./selection-view.js";

export const CLASS_ROW_MATCH = "terminal-find-row-match";
export const CLASS_ROW_ACTIVE = "terminal-find-row-active";
export const ATTR_ROW_MATCH = "data-terminal-find-row-match";
export const ATTR_ROW_ACTIVE = "data-terminal-find-row-active";
export const BUCKET_ROWS = 64;

type ElementPaint = Readonly<{ image: string; findMatch: boolean; findFill: boolean; findCurrent: boolean }>;

const BLANK: ElementPaint = { image: "", findMatch: false, findFill: false, findCurrent: false };

function rowImage(layers: readonly FillLayer[]): string {
	return layers.map((layer) => fillGradient(layer.span, layer.colour)).join(", ");
}

function runImage(layers: readonly FillLayer[], run: HTMLElement, rowLeft: number): string {
	const box = run.getBoundingClientRect();
	const parts: string[] = [];
	for (const layer of layers) {
		const span = runFill(box, rowLeft, layer.span);
		if (span) parts.push(fillGradient(span, layer.colour));
	}
	return parts.join(", ");
}

function apply(element: HTMLElement, before: ElementPaint, after: ElementPaint): void {
	if (before.image !== after.image) element.style.backgroundImage = after.image;
	if (before.findFill !== after.findFill) element.classList.toggle(CLASS_ROW_MATCH, after.findFill);
	if (before.findMatch !== after.findMatch) element.toggleAttribute(ATTR_ROW_MATCH, after.findMatch);
	if (before.findCurrent !== after.findCurrent) {
		element.classList.toggle(CLASS_ROW_ACTIVE, after.findCurrent);
		element.toggleAttribute(ATTR_ROW_ACTIVE, after.findCurrent);
	}
}

function touches(highlight: Highlight, ref: RowRef, order: BlockOrder): boolean {
	const here = { blockId: ref.blockId, row: ref.row, cell: 0 };
	const { start, end } = highlight.range;
	const startsHere = start.blockId === ref.blockId && start.row === ref.row;
	const endsHere = end.blockId === ref.blockId && end.row === ref.row;
	if (!startsHere && compareBoundary(here, start, order) < 0) return false;
	if (!endsHere && compareBoundary(here, end, order) > 0) return false;
	return true;
}

export class HighlightIndex {
	private readonly buckets = new Map<string, Highlight[]>();
	private readonly wide: Highlight[] = [];

	constructor(highlights: readonly Highlight[], private readonly order: BlockOrder) {
		for (const highlight of highlights) {
			const { start, end } = highlight.range;
			if (start.blockId !== end.blockId || end.row - start.row > BUCKET_ROWS) {
				this.wide.push(highlight);
				continue;
			}
			for (let row = start.row; row <= end.row; row += 1) {
				const key = `${start.blockId}:${row}`;
				const bucket = this.buckets.get(key);
				if (bucket) bucket.push(highlight);
				else this.buckets.set(key, [highlight]);
			}
		}
	}

	at(ref: RowRef): Highlight[] {
		const near = this.buckets.get(`${ref.blockId}:${ref.row}`) ?? [];
		const far = this.wide.filter((highlight) => touches(highlight, ref, this.order));
		return far.length === 0 ? near : [...near, ...far];
	}
}

export class HighlightPainter {
	private painted = new Map<HTMLElement, ElementPaint>();

	idle(): boolean {
		return this.painted.size === 0;
	}

	paint(rows: readonly RowRef[], highlights: readonly Highlight[], order: BlockOrder, cellWidth: number): void {
		const next = new Map<HTMLElement, ElementPaint>();
		if (highlights.length > 0) {
			const index = new HighlightIndex(highlights, order);
			for (const ref of rows) {
				const here = index.at(ref);
				if (here.length === 0) continue;
				const { box, element } = measureRow(ref);
				const paint = rowPaint(here, box, order, cellWidth);
				if (paint.layers.length === 0 && !paint.findMatch && !paint.findCurrent) continue;
				next.set(element, { image: rowImage(paint.layers), findMatch: paint.findMatch, findFill: paint.findFill, findCurrent: paint.findCurrent });
				if (paint.layers.length === 0) continue;
				for (const run of element.querySelectorAll<HTMLElement>("[data-terminal-run]")) {
					if (run.style.backgroundColor === "") continue;
					const image = runImage(paint.layers, run, box.left);
					if (image !== "") next.set(run, { ...BLANK, image });
				}
			}
		}
		for (const [element, before] of this.painted) {
			if (!next.has(element)) apply(element, before, BLANK);
		}
		for (const [element, after] of next) apply(element, this.painted.get(element) ?? BLANK, after);
		this.painted = next;
	}

	reset(): void {
		this.painted = new Map();
	}
}
```

- [ ] **Step 5: Run it to see it pass**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/renderer-dom"
npx vitest run src/highlight-painter.test.ts src/terminal-selection.test.ts
npx tsc --noEmit -p .
```
Expected: `highlight-painter.test.ts` 11 passed and `terminal-selection.test.ts` still passes (it goes through `renderedRows`); `tsc` prints nothing.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/ts/renderer-dom/src/highlight-painter.ts packages/terminal/ts/renderer-dom/src/highlight-painter.test.ts packages/terminal/ts/renderer-dom/src/selection-view.ts
git commit -m "renderer-dom: one painter for highlight layers, runs and find row classes, measuring only touched rows

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Marks (pure)

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/marks.ts`
- Test: `packages/terminal/ts/renderer-dom/src/marks.test.ts`

**Interfaces:**
- Consumes: `logicalLineAt(rows: TextRows, blockId, row): LogicalLineView | null` (`logical-lines.ts:19`), `LogicalLineView.rangeOf(start, end): LinkRange` (`logical-lines.ts:51-61`), `LogicalLineView.rowOffsets`, `TextRows` (`selection-text.ts`), Task 1's `Highlight`.
- Produces:
  - `type MarkRule = Readonly<{ pattern: string; regex: boolean; colour: string }>`
  - `type CompiledMark = Readonly<{ regex: RegExp; colour: string }>`
  - `type MarkSpan = Readonly<{ start: number; end: number; rank: number }>`
  - `type RowId = Readonly<{ blockId: string; row: number }>` (a `RowRef` from Task 2 satisfies it)
  - `const MARK_CACHE_LINES = 512`
  - `compileMarks(rules): CompiledMark[]`, `markSpans(text, marks): MarkSpan[]`
  - `class MarkCache { highlights(line: LogicalLineView, marks): Highlight[]; size(): number; clear(): void }` — keyed by `blockId:firstRow`, reused while the line's text **and** row offsets are unchanged (a rewrap with the same text recomputes)
  - `visibleLogicalLines(rows: TextRows, rendered: readonly RowId[]): LogicalLineView[]`
  - `markHighlights(lines, marks, cache): Highlight[]`

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/renderer-dom/src/marks.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import { logicalLineAt } from "./logical-lines";
import { compileMarks, markHighlights, MarkCache, MARK_CACHE_LINES, markSpans, visibleLogicalLines, type RowId } from "./marks";
import type { TextRows } from "./selection-text";

const RED = "rgb(255 0 0 / 0.4)";
const BLUE = "rgb(0 0 255 / 0.4)";

function textRows(rows: readonly string[], wrapped: readonly number[] = [], firstRow = 100): TextRows {
	return {
		blockIds: ["b"],
		firstRow: () => firstRow,
		rowCount: () => rows.length,
		rowText: (_id, row) => rows[row - firstRow] ?? "",
		rowSpans: () => [],
		rowWrapped: (_id, row) => wrapped.includes(row),
	};
}

function rendered(rows: readonly number[]): RowId[] {
	return rows.map((row) => ({ blockId: "b", row }));
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("compileMarks", () => {
	it("reads a literal pattern as plain text in any case", () => {
		const [mark] = compileMarks([{ pattern: "a.b", regex: false, colour: RED }]);
		expect(markSpans("A.B axb a.b", [mark!])).toEqual([
			{ start: 0, end: 3, rank: 0 },
			{ start: 8, end: 11, rank: 0 },
		]);
	});

	it("reads a regex pattern as written, case included", () => {
		const marks = compileMarks([{ pattern: "err(or)?", regex: true, colour: RED }]);
		expect(markSpans("err ERROR error", marks)).toEqual([
			{ start: 0, end: 3, rank: 0 },
			{ start: 10, end: 15, rank: 0 },
		]);
	});

	it("drops an invalid regex and keeps the rules around it", () => {
		const marks = compileMarks([
			{ pattern: "(unclosed", regex: true, colour: RED },
			{ pattern: "ok", regex: false, colour: BLUE },
		]);
		expect(marks.map((mark) => mark.colour)).toEqual([BLUE]);
	});

	it("drops an empty pattern and an empty colour", () => {
		expect(compileMarks([
			{ pattern: "", regex: false, colour: RED },
			{ pattern: "x", regex: false, colour: "" },
		])).toEqual([]);
	});

	it("drops a colour the browser does not accept", () => {
		vi.stubGlobal("CSS", { supports: (_property: string, value: string) => value !== "not-a-colour" });
		const marks = compileMarks([
			{ pattern: "x", regex: false, colour: "not-a-colour" },
			{ pattern: "y", regex: false, colour: RED },
		]);
		expect(marks.map((mark) => mark.colour)).toEqual([RED]);
	});
});

describe("markSpans", () => {
	it("yields nothing for a pattern that only matches empty text", () => {
		for (const pattern of ["^", "$", "\\b", "x*", "(?=a)"]) {
			expect(markSpans("aaa bbb", compileMarks([{ pattern, regex: true, colour: RED }]))).toEqual([]);
		}
	});

	it("keeps the non-empty matches of a pattern that can also match empty text", () => {
		expect(markSpans("axxb", compileMarks([{ pattern: "x*", regex: true, colour: RED }]))).toEqual([{ start: 1, end: 3, rank: 0 }]);
	});

	it("merges touching matches of one rule into one span", () => {
		expect(markSpans("abcd", compileMarks([{ pattern: ".", regex: true, colour: RED }]))).toEqual([{ start: 0, end: 4, rank: 0 }]);
	});

	it("ranks each rule by its place in the list", () => {
		const marks = compileMarks([
			{ pattern: "fail", regex: false, colour: RED },
			{ pattern: "failed", regex: false, colour: BLUE },
		]);
		expect(markSpans("it failed", marks)).toEqual([
			{ start: 3, end: 7, rank: 0 },
			{ start: 3, end: 9, rank: 1 },
		]);
	});

	it("gives the same answer when run twice on a global regex", () => {
		const marks = compileMarks([{ pattern: "a", regex: false, colour: RED }]);
		expect(markSpans("a a", marks)).toEqual(markSpans("a a", marks));
	});
});

describe("visibleLogicalLines", () => {
	it("joins a soft-wrapped line once, whichever of its rows are painted", () => {
		const rows = textRows(["the err", "or here", "next"], [100]);
		const lines = visibleLogicalLines(rows, rendered([100, 101, 102]));
		expect(lines.map((line) => [line.firstRow, line.text])).toEqual([
			[100, "the error here"],
			[102, "next"],
		]);
	});
});

describe("markHighlights", () => {
	it("places a match that crosses a soft wrap on both rows, in stable rows", () => {
		const rows = textRows(["the err", "or here"], [100]);
		const marks = compileMarks([{ pattern: "error", regex: false, colour: RED }]);
		const [highlight] = markHighlights(visibleLogicalLines(rows, rendered([100, 101])), marks, new MarkCache());
		expect(highlight).toEqual({
			kind: "mark",
			range: { start: { blockId: "b", row: 100, cell: 4 }, end: { blockId: "b", row: 101, cell: 2 } },
			colour: RED,
			rank: 0,
		});
	});

	it("follows the text when the same line moves to other stable rows", () => {
		const marks = compileMarks([{ pattern: "error", regex: false, colour: RED }]);
		const cache = new MarkCache();
		const before = markHighlights(visibleLogicalLines(textRows(["an error"], [], 100), rendered([100])), marks, cache);
		const after = markHighlights(visibleLogicalLines(textRows(["an error"], [], 40), rendered([40])), marks, cache);
		expect(before[0]!.range.start).toEqual({ blockId: "b", row: 100, cell: 3 });
		expect(after[0]!.range.start).toEqual({ blockId: "b", row: 40, cell: 3 });
	});

	it("returns nothing and touches no text when there are no rules", () => {
		const rowText = vi.fn(() => "error");
		const rows = { ...textRows(["error"]), rowText };
		expect(markHighlights(visibleLogicalLines(rows, []), [], new MarkCache())).toEqual([]);
		expect(rowText).not.toHaveBeenCalled();
	});
});

describe("MarkCache", () => {
	it("reuses a line's highlights while its text and wrap are unchanged", () => {
		const marks = compileMarks([{ pattern: "a", regex: false, colour: RED }]);
		const cache = new MarkCache();
		const line = logicalLineAt(textRows(["a b a"]), "b", 100)!;
		const first = cache.highlights(line, marks);
		expect(cache.highlights(logicalLineAt(textRows(["a b a"]), "b", 100)!, marks)).toBe(first);
		expect(cache.highlights(logicalLineAt(textRows(["a b aa"]), "b", 100)!, marks)).not.toBe(first);
	});

	it("recomputes when the same text wraps differently", () => {
		const marks = compileMarks([{ pattern: "error", regex: false, colour: RED }]);
		const cache = new MarkCache();
		const wide = cache.highlights(logicalLineAt(textRows(["an error"]), "b", 100)!, marks);
		const narrow = cache.highlights(logicalLineAt(textRows(["an er", "ror"], [100]), "b", 100)!, marks);
		expect(wide[0]!.range.end).toEqual({ blockId: "b", row: 100, cell: 8 });
		expect(narrow[0]!.range.end).toEqual({ blockId: "b", row: 101, cell: 3 });
	});

	it("never holds more than its line budget", () => {
		const marks = compileMarks([{ pattern: "a", regex: false, colour: RED }]);
		const cache = new MarkCache();
		for (let index = 0; index < MARK_CACHE_LINES * 2 + 3; index += 1) cache.highlights(logicalLineAt(textRows(["a"], [], index), "b", index)!, marks);
		expect(cache.size()).toBeLessThanOrEqual(MARK_CACHE_LINES);
	});
});
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/renderer-dom"
npx vitest run src/marks.test.ts
```
Expected: FAIL — `Failed to resolve import "./marks"`.

- [ ] **Step 3: Implement**

Create `packages/terminal/ts/renderer-dom/src/marks.ts`:

```ts
import type { Highlight } from "./highlights.js";
import { logicalLineAt, type LogicalLineView } from "./logical-lines.js";
import type { TextRows } from "./selection-text.js";

export type MarkRule = Readonly<{ pattern: string; regex: boolean; colour: string }>;
export type CompiledMark = Readonly<{ regex: RegExp; colour: string }>;
export type MarkSpan = Readonly<{ start: number; end: number; rank: number }>;

export const MARK_CACHE_LINES = 512;

const LITERAL_SPECIALS = /[.*+?^${}()|[\]\\]/g;

function validColour(colour: string): boolean {
	if (colour.trim() === "") return false;
	const css = (globalThis as { CSS?: { supports?: (property: string, value: string) => boolean } }).CSS;
	return typeof css?.supports !== "function" || css.supports("color", colour);
}

export function compileMarks(rules: readonly MarkRule[]): CompiledMark[] {
	const out: CompiledMark[] = [];
	for (const rule of rules) {
		if (rule.pattern === "" || !validColour(rule.colour)) continue;
		try {
			const regex = rule.regex ? new RegExp(rule.pattern, "g") : new RegExp(rule.pattern.replace(LITERAL_SPECIALS, "\\$&"), "gi");
			out.push({ regex, colour: rule.colour });
		} catch {
			continue;
		}
	}
	return out;
}

export function markSpans(text: string, marks: readonly CompiledMark[]): MarkSpan[] {
	const out: MarkSpan[] = [];
	marks.forEach((mark, rank) => {
		mark.regex.lastIndex = 0;
		let open: { start: number; end: number } | null = null;
		for (const match of text.matchAll(mark.regex)) {
			const start = match.index ?? 0;
			const end = start + match[0].length;
			if (end <= start) continue;
			if (open && start <= open.end) {
				open.end = Math.max(open.end, end);
				continue;
			}
			if (open) out.push({ ...open, rank });
			open = { start, end };
		}
		if (open) out.push({ ...open, rank });
	});
	return out;
}

export type RowId = Readonly<{ blockId: string; row: number }>;

function lineHighlights(line: LogicalLineView, marks: readonly CompiledMark[]): Highlight[] {
	return markSpans(line.text, marks).map((span) => {
		const range = line.rangeOf(span.start, span.end);
		return {
			kind: "mark",
			range: {
				start: { blockId: range.blockId, row: range.startRow, cell: range.startCell },
				end: { blockId: range.blockId, row: range.endRow, cell: range.endCell },
			},
			colour: marks[span.rank]!.colour,
			rank: span.rank,
		};
	});
}

export class MarkCache {
	private readonly lines = new Map<string, { shape: string; highlights: Highlight[] }>();

	highlights(line: LogicalLineView, marks: readonly CompiledMark[]): Highlight[] {
		const key = `${line.blockId}:${line.firstRow}`;
		const shape = `${line.rowOffsets.join(",")}\u0000${line.text}`;
		const hit = this.lines.get(key);
		if (hit && hit.shape === shape) return hit.highlights;
		const highlights = lineHighlights(line, marks);
		if (this.lines.size >= MARK_CACHE_LINES) this.lines.clear();
		this.lines.set(key, { shape, highlights });
		return highlights;
	}

	size(): number {
		return this.lines.size;
	}

	clear(): void {
		this.lines.clear();
	}
}

export function visibleLogicalLines(rows: TextRows, rendered: readonly RowId[]): LogicalLineView[] {
	const covered = new Set<string>();
	const lines: LogicalLineView[] = [];
	for (const { blockId, row } of rendered) {
		if (covered.has(`${blockId}:${row}`)) continue;
		const line = logicalLineAt(rows, blockId, row);
		if (!line) continue;
		for (let row = line.firstRow; row < line.firstRow + line.rowCount; row += 1) covered.add(`${line.blockId}:${row}`);
		lines.push(line);
	}
	return lines;
}

export function markHighlights(lines: readonly LogicalLineView[], marks: readonly CompiledMark[], cache: MarkCache): Highlight[] {
	if (marks.length === 0) return [];
	return lines.flatMap((line) => cache.highlights(line, marks));
}
```

- [ ] **Step 4: Run it to see it pass**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/renderer-dom"
npx vitest run src/marks.test.ts
npx tsc --noEmit -p .
```
Expected: `Tests  17 passed (17)`; `tsc` prints nothing.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/ts/renderer-dom/src/marks.ts packages/terminal/ts/renderer-dom/src/marks.test.ts
git commit -m "renderer-dom: user marks matched per visible logical line, cached per line

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Selection, find hits and marks on the one model in the renderer

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/renderer-highlights.ts`
- Test: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.highlights.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/renderer-selection.ts:4-14,68-88`
- Modify: `packages/terminal/ts/renderer-dom/src/selection-view.ts` (imports at lines 4-5; `selectionFills` at the end of the file)
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:35,48,100-105,272-296,407,504,515,522,563`
- Modify: `packages/terminal/ts/renderer-dom/src/find-bar.ts:10-31,95-123,296-301`
- Modify: `packages/terminal/ts/renderer-dom/src/find-bar.test.ts:113`
- Modify: `packages/terminal/ts/renderer-dom/src/find-bar.incremental.test.ts:91,209,240,250-251`
- Modify: `packages/terminal/ts/renderer-dom/src/index.ts:16`
- Modify: `packages/terminal/bench/agent-session/highlight-probe.ts` (one line)

**Interfaces:**
- Consumes: Tasks 1–3 (`HighlightPainter`, `SELECTION_COLOUR`, `Highlight`, `compileMarks`, `markHighlights`, `MarkCache`, `visibleLogicalLines`, `MarkRule`), `ALT_BLOCK_ID` (`selection-view.ts:9`), Task 2's `RowRef` and `renderedRowRefs`, `ROW_END` (`selection-model.ts:12`).
- Produces:
  - `type FindHighlights = Readonly<{ rows: ReadonlySet<number>; current: Readonly<{ row: number; endRow: number }> | null }>`
  - `class RendererHighlights { readonly selection: RendererSelection; setFind(find: FindHighlights | null): void; setMarks(rules: readonly MarkRule[]): void; paint(): void; reset(): void }`
  - `DomBlockRenderer.setMarks(rules: readonly MarkRule[]): void`, `DomBlockRenderer.setFindHighlights(find: FindHighlights | null): void`
  - `FindBarHost.highlightFind(find: FindHighlights | null): void` (required)
  - `RendererSelectionDeps = { hasCore, textRows, repaint }` (was `{ hasCore, textRows, renderedRows, cellWidth }`)

- [ ] **Step 1: Write the failing integration test**

Create `packages/terminal/ts/renderer-dom/src/dom-block-renderer.highlights.test.ts` (jsdom normalises colours, so the test colours are written the way jsdom prints them):

```ts
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "./index";
import { feed, flushRepaint, font, loadedCore, stubRowLayout, theme } from "./renderer-harness";

const CELL_W = 10;
const CELL_H = 20;
const RED = "rgba(255, 0, 0, 0.4)";
const BLUE = "rgba(0, 0, 255, 0.4)";

beforeAll(async () => {
	await loadedCore();
});

afterEach(() => {
	vi.restoreAllMocks();
	vi.unstubAllGlobals();
});

function mount(core: TerminalCore): { host: HTMLElement; renderer: DomBlockRenderer } {
	const host = document.createElement("div");
	document.body.append(host);
	const renderer = new DomBlockRenderer();
	renderer.measure = () => ({ cellWidth: CELL_W, cellHeight: CELL_H });
	renderer.mount(host, core);
	renderer.setTheme(theme);
	renderer.setFont(font);
	return { host, renderer };
}

function coreWith(text: string, columns = 40, scrollback = 100): TerminalCore {
	const core = createTerminalCore({ columns, scrollback });
	feed(core, text);
	return core;
}

function rowsHolding(host: HTMLElement, text: string): HTMLElement[] {
	return [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].filter((row) => (row.textContent ?? "").includes(text));
}

function paintedRows(host: HTMLElement): HTMLElement[] {
	return [...host.querySelectorAll<HTMLElement>("[data-terminal-row]")].filter((row) => row.style.backgroundImage !== "");
}

describe("DomBlockRenderer highlights", () => {
	it("paints a user mark over the matching cells of a rendered row", async () => {
		stubRowLayout();
		const { host, renderer } = mount(coreWith("all good\r\nan error here\r\nfine"));
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		const [row] = rowsHolding(host, "an error here");
		expect(row!.style.backgroundImage).toBe(`linear-gradient(to right, transparent 30px, ${RED} 30px, ${RED} 80px, transparent 80px)`);
		expect(paintedRows(host)).toEqual([row]);
		renderer.dispose();
	});

	it("orders selection over the current find hit over other hits over marks on one row", async () => {
		stubRowLayout();
		const core = coreWith("error one\r\nerror two");
		const { host, renderer } = mount(core);
		await flushRepaint();
		const [first] = rowsHolding(host, "error one");
		const [second] = rowsHolding(host, "error two");
		const firstRow = Number(first!.dataset.terminalRow);
		const secondRow = Number(second!.dataset.terminalRow);
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		renderer.setFindHighlights({ rows: new Set([firstRow, secondRow]), current: { row: secondRow, endRow: secondRow } });
		renderer.selectionBegin({ blockId: first!.closest<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!, row: firstRow, column: 0, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId: first!.closest<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!, row: firstRow, column: 2, side: "right" });
		const layers = first!.style.backgroundImage.split("linear-gradient").filter(Boolean).map((layer) => (layer.includes(RED) ? "mark" : "selection-colour"));
		expect(layers).toEqual(["selection-colour", "selection-colour", "mark"]);
		expect(first!.classList.contains("terminal-find-row-match")).toBe(false);
		expect(first!.hasAttribute("data-terminal-find-row-match")).toBe(true);
		expect(second!.classList.contains("terminal-find-row-active")).toBe(true);
		expect(first!.classList.contains("terminal-find-row-active")).toBe(false);
		renderer.dispose();
	});

	it("keeps a mark on its text after the scrollback trims rows off the front", async () => {
		stubRowLayout();
		const core = createTerminalCore({ columns: 40, scrollback: 8, rows: 4 });
		const { host, renderer } = mount(core);
		for (let index = 0; index < 12; index += 1) feed(core, `line ${index}\r\n`);
		feed(core, "the needle\r\n");
		await flushRepaint();
		renderer.setMarks([{ pattern: "needle", regex: false, colour: RED }]);
		const before = rowsHolding(host, "the needle")[0]!;
		const trimmedBefore = core.snapshot().firstStableRow;
		for (let index = 0; index < 3; index += 1) feed(core, `more ${index}\r\n`);
		await flushRepaint();
		expect(core.snapshot().firstStableRow).toBeGreaterThan(trimmedBefore);
		const after = rowsHolding(host, "the needle")[0]!;
		expect(after.dataset.terminalRow).toBe(before.dataset.terminalRow);
		expect(after.style.backgroundImage).toContain(RED);
		expect(paintedRows(host)).toEqual([after]);
		renderer.dispose();
	});

	it("moves a mark with its text when a narrower width rewraps the line", async () => {
		stubRowLayout();
		const core = coreWith("prefix words then error at the end\r\nnext\r\n", 40);
		const { host, renderer } = mount(core);
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		expect(paintedRows(host).map((row) => row.textContent)).toEqual(["prefix words then error at the end"]);
		core.resize(12, 24);
		await flushRepaint();
		const painted = paintedRows(host);
		expect(painted).toHaveLength(1);
		expect(painted[0]!.textContent).toContain("error");
		renderer.dispose();
	});

	it("paints a mark that a soft wrap splits on both rows", async () => {
		stubRowLayout();
		const { host, renderer } = mount(coreWith("0123456789abcderror", 16));
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		expect(paintedRows(host).map((row) => row.textContent)).toEqual(["0123456789abcder", "ror"]);
		renderer.dispose();
	});

	it("never schedules a repaint when highlights change", async () => {
		stubRowLayout();
		const { host, renderer } = mount(coreWith("error here"));
		await flushRepaint();
		const paints = vi.fn();
		renderer.onPaint(paints);
		const frames = vi.spyOn(globalThis, "requestAnimationFrame");
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		renderer.setFindHighlights({ rows: new Set([0]), current: null });
		const row = host.querySelector<HTMLElement>("[data-terminal-row]")!;
		const blockId = row.closest<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId, row: 0, column: 0, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId, row: 0, column: 3, side: "right" });
		renderer.setFindHighlights(null);
		renderer.setMarks([]);
		expect(frames).not.toHaveBeenCalled();
		await flushRepaint();
		expect(paints).not.toHaveBeenCalled();
		renderer.dispose();
	});

	it("reads no layout and writes no style on a paint with nothing highlighted", async () => {
		const core = coreWith("plain\r\n");
		const { host, renderer } = mount(core);
		await flushRepaint();
		const rects = vi.spyOn(HTMLElement.prototype, "getBoundingClientRect");
		for (let index = 0; index < 5; index += 1) feed(core, `row ${index}\r\n`);
		await flushRepaint();
		expect(rects.mock.contexts.filter((element) => (element as HTMLElement).hasAttribute("data-terminal-row"))).toEqual([]);
		expect(paintedRows(host)).toEqual([]);
		renderer.dispose();
	});

	it("repaints marks on rows a later paint rebuilds", async () => {
		stubRowLayout();
		const core = coreWith("error 0");
		const { host, renderer } = mount(core);
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		const before = rowsHolding(host, "error 0")[0]!;
		feed(core, "\x1b[2K\rerror 1");
		await flushRepaint();
		const after = rowsHolding(host, "error 1")[0]!;
		expect(after).not.toBe(before);
		expect(after.style.backgroundImage).toContain(RED);
		renderer.dispose();
	});

	it("does not touch a parked pane's rows until it is shown again", async () => {
		stubRowLayout();
		const { host, renderer } = mount(coreWith("error here"));
		await flushRepaint();
		renderer.setVisible(false);
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		expect(paintedRows(host)).toEqual([]);
		renderer.setVisible(true);
		expect(rowsHolding(host, "error here")[0]!.style.backgroundImage).toContain(RED);
		renderer.dispose();
	});

	it("marks the alternate screen but never paints find hits on it", async () => {
		stubRowLayout();
		const core = coreWith("\x1b[?1049herror on alt");
		const { host, renderer } = mount(core);
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		renderer.setFindHighlights({ rows: new Set([0]), current: { row: 0, endRow: 0 } });
		const alt = host.querySelector<HTMLElement>(".terminal-alt-surface [data-terminal-row]")!;
		expect(alt.style.backgroundImage).toContain(RED);
		expect(alt.hasAttribute("data-terminal-find-row-match")).toBe(false);
		expect(alt.classList.contains("terminal-find-row-active")).toBe(false);
		renderer.dispose();
	});

	it("keeps the selection when a mark's colour is rejected", async () => {
		stubRowLayout();
		vi.stubGlobal("CSS", { supports: (_property: string, value: string) => value !== "nonsense" });
		const { host, renderer } = mount(coreWith("error here"));
		await flushRepaint();
		const row = host.querySelector<HTMLElement>("[data-terminal-row]")!;
		const blockId = row.closest<HTMLElement>("[data-terminal-block-id]")!.dataset.terminalBlockId!;
		renderer.selectionBegin({ blockId, row: 0, column: 0, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId, row: 0, column: 3, side: "right" });
		renderer.setMarks([{ pattern: "error", regex: false, colour: "nonsense" }, { pattern: "here", regex: false, colour: BLUE }]);
		expect(row.style.backgroundImage).toContain("var(--terminal-selection)");
		expect(row.style.backgroundImage).toContain(BLUE);
		expect(row.style.backgroundImage).not.toContain("nonsense");
		renderer.dispose();
	});

	it("forgets marks and find hits on dispose, and a disposed renderer ignores new ones", async () => {
		stubRowLayout();
		const core = coreWith("error here");
		const { renderer } = mount(core);
		await flushRepaint();
		renderer.setMarks([{ pattern: "error", regex: false, colour: RED }]);
		renderer.setFindHighlights({ rows: new Set([0]), current: null });
		renderer.dispose();
		expect(() => renderer.setMarks([{ pattern: "here", regex: false, colour: RED }])).not.toThrow();
		expect(() => renderer.setFindHighlights({ rows: new Set([0]), current: null })).not.toThrow();
		const fresh = document.createElement("div");
		renderer.mount(fresh, core);
		await flushRepaint();
		expect(paintedRows(fresh)).toEqual([]);
		expect(fresh.querySelector("[data-terminal-find-row-match]")).toBeNull();
		renderer.dispose();
	});
});
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/renderer-dom"
npx vitest run src/dom-block-renderer.highlights.test.ts
```
Expected: FAIL — `renderer.setMarks is not a function` (every test that calls it).

- [ ] **Step 3: Create `renderer-highlights.ts`**

Create `packages/terminal/ts/renderer-dom/src/renderer-highlights.ts`:

```ts
import { HighlightPainter } from "./highlight-painter.js";
import { SELECTION_COLOUR, type Highlight } from "./highlights.js";
import { compileMarks, markHighlights, MarkCache, visibleLogicalLines, type CompiledMark, type MarkRule } from "./marks.js";
import { RendererSelection } from "./renderer-selection.js";
import { ROW_END, type BlockOrder } from "./selection-model.js";
import type { TextRows } from "./selection-text.js";
import { ALT_BLOCK_ID, type RowRef } from "./selection-view.js";

export type { MarkRule } from "./marks.js";

export type FindHighlights = Readonly<{ rows: ReadonlySet<number>; current: Readonly<{ row: number; endRow: number }> | null }>;

export type RendererHighlightsDeps = Readonly<{
	hasCore: () => boolean;
	painting: () => boolean;
	textRows: () => TextRows;
	rowRefs: () => RowRef[];
	cellWidth: () => number;
}>;

export class RendererHighlights {
	readonly selection: RendererSelection;
	private find: FindHighlights | null = null;
	private marks: CompiledMark[] = [];
	private readonly markCache = new MarkCache();
	private readonly painter = new HighlightPainter();

	constructor(private readonly deps: RendererHighlightsDeps) {
		this.selection = new RendererSelection({ hasCore: deps.hasCore, textRows: deps.textRows, repaint: () => this.paint() });
	}

	setFind(find: FindHighlights | null): void {
		this.find = find;
		this.paint();
	}

	setMarks(rules: readonly MarkRule[]): void {
		this.marks = compileMarks(rules);
		this.markCache.clear();
		this.paint();
	}

	paint(): void {
		if (!this.deps.painting()) return;
		const selection = this.selection.view();
		const active = selection !== null || this.find !== null || this.marks.length > 0;
		if (!active && this.painter.idle()) return;
		const rows = this.deps.rowRefs();
		const textRows = selection?.rows ?? (this.deps.hasCore() ? this.deps.textRows() : null);
		const highlights: Highlight[] = [];
		if (selection) highlights.push({ kind: "selection", range: selection.range, colour: SELECTION_COLOUR, rank: 0 });
		this.collectFind(rows, highlights);
		if (textRows && this.marks.length > 0) highlights.push(...markHighlights(visibleLogicalLines(textRows, rows), this.marks, this.markCache));
		this.painter.paint(rows, highlights, selection?.order ?? blockOrder(textRows), this.deps.cellWidth());
	}

	reset(): void {
		this.selection.reset();
		this.find = null;
		this.marks = [];
		this.markCache.clear();
		this.painter.reset();
	}

	private collectFind(rows: readonly RowRef[], out: Highlight[]): void {
		const find = this.find;
		if (!find) return;
		for (const box of rows) {
			if (box.blockId === ALT_BLOCK_ID) continue;
			const range = { start: { blockId: box.blockId, row: box.row, cell: 0 }, end: { blockId: box.blockId, row: box.row, cell: ROW_END } };
			if (find.rows.has(box.row)) out.push({ kind: "find", range, colour: SELECTION_COLOUR, rank: 0 });
			if (find.current && box.row >= find.current.row && box.row <= find.current.endRow) out.push({ kind: "find-current", range, colour: SELECTION_COLOUR, rank: 0 });
		}
	}
}

function blockOrder(rows: TextRows | null): BlockOrder {
	const index = new Map((rows?.blockIds ?? []).map((id, position) => [id, position] as const));
	return (blockId) => index.get(blockId) ?? -1;
}
```

- [ ] **Step 4: Make `RendererSelection` ask for a paint instead of painting**

In `packages/terminal/ts/renderer-dom/src/renderer-selection.ts`:

Find (lines 4-14):
```ts
import { resolveSelectionView, selectionFills, type RenderedRow, type SelectionView } from "./selection-view.js";

export type RendererSelectionDeps = Readonly<{
	hasCore: () => boolean;
	textRows: () => TextRows;
	renderedRows: () => RenderedRow[];
	cellWidth: () => number;
}>;

export class RendererSelection {
	private filled: Map<HTMLElement, string> = new Map();
	private selection: SelectionState | null = null;
```
Replace with:
```ts
import { resolveSelectionView, type SelectionView } from "./selection-view.js";

export type RendererSelectionDeps = Readonly<{
	hasCore: () => boolean;
	textRows: () => TextRows;
	repaint: () => void;
}>;

export class RendererSelection {
	private selection: SelectionState | null = null;
```

Find (lines 68-88):
```ts
	paintFill(): void {
		const view = this.view();
		const next = view ? selectionFills(view, this.deps.renderedRows(), this.deps.cellWidth()) : new Map<HTMLElement, string>();
		for (const element of this.filled.keys()) {
			if (!next.has(element)) element.style.backgroundImage = "";
		}
		for (const [element, image] of next) {
			if (this.filled.get(element) !== image) element.style.backgroundImage = image;
		}
		this.filled = next;
	}

	reset(): void {
		this.filled = new Map();
		this.selection = null;
	}

	private changed(): void {
		this.paintFill();
		this.notifyListeners();
	}
```
Replace with:
```ts
	reset(): void {
		this.selection = null;
	}

	private changed(): void {
		this.deps.repaint();
		this.notifyListeners();
	}
```

- [ ] **Step 5: Delete `selectionFills` from `selection-view.ts`**

In `packages/terminal/ts/renderer-dom/src/selection-view.ts`:

Find (lines 4-5):
```ts
import { fillGradient, runFill } from "./selection-fill.js";
import { rowFillSpan, type RowBox } from "./selection-geometry.js";
```
Replace with:
```ts
import type { RowBox } from "./selection-geometry.js";
```

Then delete the blank line before `export function selectionFills(view: SelectionView, rows: readonly RenderedRow[], cellWidth: number): Map<HTMLElement, string> {` and that whole function to its closing `}` (it is the last function in the file; 16 lines), so the file ends with the closing `}` of `renderedRows` followed by one newline. Check: `grep -l selectionFills packages/terminal/ts/renderer-dom/src/*.ts` prints nothing (Step 4 already removed the only caller); `dom-block-renderer.ts` still calls `paintFill`, which Step 6 fixes.

- [ ] **Step 6: Wire the renderer**

In `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts`:

Find (line 35):
```ts
import { renderedRows, snapshotTextRows, type RenderedRow } from "./selection-view.js";
```
Replace with:
```ts
import { renderedRowRefs, renderedRows, snapshotTextRows, type RenderedRow } from "./selection-view.js";
```

Find (line 48):
```ts
import { RendererSelection } from "./renderer-selection.js";
```
Replace with:
```ts
import { RendererHighlights, type FindHighlights, type MarkRule } from "./renderer-highlights.js";
```

Find (lines 100-105):
```ts
	private readonly selection = new RendererSelection({
		hasCore: () => this.core !== null,
		textRows: () => this.overlays.textRows(),
		renderedRows: () => this.renderedRows(),
		cellWidth: () => this.cellMetrics().cellWidth,
	});
```
Replace with:
```ts
	private readonly highlights = new RendererHighlights({
		hasCore: () => this.core !== null,
		painting: () => this.painting(),
		textRows: () => this.overlays.textRows(),
		rowRefs: () => renderedRowRefs(this.altRoot, this.filteredBlocks, this.elements.blockElements, this.paintedFirstStableRow),
		cellWidth: () => this.cellMetrics().cellWidth,
	});
```

Find (line 407):
```ts
		this.selection.reset();
```
Replace with:
```ts
		this.highlights.reset();
```

Find (line 563):
```ts
		this.selection.paintFill();
```
Replace with:
```ts
		this.highlights.paint();
```

Then rename every remaining `this.selection.` to `this.highlights.selection.` (lines 273, 277, 281, 285, 289, 293, 504, 515, 522):
```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/renderer-dom/src"
sed -i 's/this\.selection\./this.highlights.selection./g' dom-block-renderer.ts
grep -n "this.selection\b\|highlights.selection" dom-block-renderer.ts
```
Expected: nine lines, all `this.highlights.selection.` (`begin`, `update`, `clear`, `view`, `text`, `onChange`, `drop`, `drop`, `dropUnlessShown`). On macOS use `sed -i ''`.

Find (the end of `onSelectionChange`, lines 292-296 before your edits):
```ts
	onSelectionChange(listener: () => void): () => void {
		return this.highlights.selection.onChange(listener);
	}

	private rawTextRows(): TextRows {
```
Replace with:
```ts
	onSelectionChange(listener: () => void): () => void {
		return this.highlights.selection.onChange(listener);
	}

	setMarks(rules: readonly MarkRule[]): void {
		this.highlights.setMarks(rules);
	}

	setFindHighlights(find: FindHighlights | null): void {
		this.highlights.setFind(find);
	}

	private rawTextRows(): TextRows {
```

```bash
wc -l dom-block-renderer.ts
```
Expected: `600 dom-block-renderer.ts`. If it is more (a sibling plan landed first), stop and move lines out as the header describes before going on.

- [ ] **Step 7: Move the find bar onto the model**

In `packages/terminal/ts/renderer-dom/src/find-bar.ts`:

Find (lines 10-31):
```ts
} from "@operator/terminal-core";

const CLASS_BAR = "terminal-find-bar";
const CLASS_INPUT = "terminal-find-input";
const CLASS_COUNT = "terminal-find-count";
const CLASS_REGEX = "terminal-find-regex";
const CLASS_ROW_MATCH = "terminal-find-row-match";
const CLASS_ROW_ACTIVE = "terminal-find-row-active";
const ATTR_BAR = "data-terminal-find-bar";
const ATTR_INPUT = "data-terminal-find-input";
const ATTR_COUNT = "data-terminal-find-count";
const ATTR_REGEX = "data-terminal-find-regex";
const ATTR_ROW_MATCH = "data-terminal-find-row-match";
const ATTR_ROW_ACTIVE = "data-terminal-find-row-active";
const TRANSCRIPT_ROWS = "[data-terminal-block-id] [data-terminal-row]";

export type FindBarHost = Readonly<{
	scrollToBlock(id: BlockId, align: "start" | "center" | "end"): void;
	scrollToRow?(row: number, align: "start" | "center" | "end"): boolean;
	invalidate(range: RowRange): void;
	afterRepaint(listener: () => void): () => void;
}>;
```
Replace with:
```ts
} from "@operator/terminal-core";
import type { FindHighlights } from "./renderer-highlights.js";

const CLASS_BAR = "terminal-find-bar";
const CLASS_INPUT = "terminal-find-input";
const CLASS_COUNT = "terminal-find-count";
const CLASS_REGEX = "terminal-find-regex";
const ATTR_BAR = "data-terminal-find-bar";
const ATTR_INPUT = "data-terminal-find-input";
const ATTR_COUNT = "data-terminal-find-count";
const ATTR_REGEX = "data-terminal-find-regex";

export type FindBarHost = Readonly<{
	scrollToBlock(id: BlockId, align: "start" | "center" | "end"): void;
	scrollToRow?(row: number, align: "start" | "center" | "end"): boolean;
	invalidate(range: RowRange): void;
	afterRepaint(listener: () => void): () => void;
	highlightFind(find: FindHighlights | null): void;
}>;
```

Find (lines 95-123):
```ts
	const clearMarks = (): void => {
		if (!container) return;
		container
			.querySelectorAll<HTMLElement>(`[${ATTR_ROW_MATCH}], [${ATTR_ROW_ACTIVE}]`)
			.forEach((node) => {
				node.classList.remove(CLASS_ROW_MATCH, CLASS_ROW_ACTIVE);
				node.removeAttribute(ATTR_ROW_MATCH);
				node.removeAttribute(ATTR_ROW_ACTIVE);
			});
	};

	const applyHighlights = (): void => {
		if (!container) return;
		clearMarks();
		const active = session;
		if (!active || active.results.length === 0) return;
		const current = active.results[active.current];
		container.querySelectorAll<HTMLElement>(TRANSCRIPT_ROWS).forEach((node) => {
			const row = Number(node.dataset.terminalRow);
			if (active.rows.has(row)) {
				node.classList.add(CLASS_ROW_MATCH);
				node.setAttribute(ATTR_ROW_MATCH, "");
			}
			if (current && row >= current.row && row <= current.endRow) {
				node.classList.add(CLASS_ROW_ACTIVE);
				node.setAttribute(ATTR_ROW_ACTIVE, "");
			}
		});
	};
```
Replace with:
```ts
	const clearMarks = (): void => {
		host.highlightFind(null);
	};

	const applyHighlights = (): void => {
		const active = session;
		if (!active || active.results.length === 0) {
			clearMarks();
			return;
		}
		const current = active.results[active.current];
		host.highlightFind({ rows: active.rows, current: current ? { row: current.row, endRow: current.endRow } : null });
	};
```

Find (lines 296-301):
```ts
		if (repaintOff === null) {
			repaintOff = host.afterRepaint(() => {
				applyHighlights();
				if (session) schedulePump();
			});
		}
```
Replace with:
```ts
		if (repaintOff === null) {
			repaintOff = host.afterRepaint(() => {
				if (session) schedulePump();
			});
		}
```

- [ ] **Step 8: Give the existing find-bar test hosts `highlightFind`**

In `packages/terminal/ts/renderer-dom/src/find-bar.test.ts`, find (lines 113-115):
```ts
		afterRepaint: (listener) => renderer.onPaint(listener),
	};
}
```
Replace with:
```ts
		afterRepaint: (listener) => renderer.onPaint(listener),
		highlightFind: (find) => renderer.setFindHighlights(find),
	};
}
```

In `packages/terminal/ts/renderer-dom/src/find-bar.incremental.test.ts`:

Find (lines 90-92):
```ts
		invalidate: (range) => renderer.invalidate(range),
		afterRepaint: (listener) => renderer.onPaint(listener),
	};
```
Replace with:
```ts
		invalidate: (range) => renderer.invalidate(range),
		afterRepaint: (listener) => renderer.onPaint(listener),
		highlightFind: (find) => renderer.setFindHighlights(find),
	};
```

Find (lines 208-210):
```ts
			invalidate: (range) => renderer.invalidate(range),
			afterRepaint,
		};
```
Replace with:
```ts
			invalidate: (range) => renderer.invalidate(range),
			afterRepaint,
			highlightFind: (find) => renderer.setFindHighlights(find),
		};
```

Find (line 240):
```ts
			host: { scrollToBlock: () => undefined, invalidate: (range) => renderer.invalidate(range), afterRepaint: (listener) => renderer.onPaint(listener) },
```
Replace with:
```ts
			host: { scrollToBlock: () => undefined, invalidate: (range) => renderer.invalidate(range), afterRepaint: (listener) => renderer.onPaint(listener), highlightFind: (find) => renderer.setFindHighlights(find) },
```

Find (the file's last two lines, 250-251):
```ts
	});
});
```
Replace with:
```ts
	});

	it("hands its hits to the host's highlight model instead of marking rows, and clears them on close and dispose", async () => {
		const core = createTerminalCore({ columns: 40, scrollback: 1000, rows: 1 });
		for (const line of lines(3)) feedBlock(core, line);
		const host = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setFont(font);
		const highlightFind = vi.fn();
		const bar = createFindBar({
			core,
			renderer: renderer as unknown as BlockRenderer,
			host: { scrollToBlock: () => undefined, invalidate: (range) => renderer.invalidate(range), afterRepaint: (listener) => renderer.onPaint(listener), highlightFind },
			strings: defaultStrings,
		});
		bar.mount(host);
		bar.open();
		type(host.querySelector<HTMLInputElement>("input[data-terminal-find-input]")!, "line 1");
		await flushFrames();
		expect(highlightFind).toHaveBeenLastCalledWith({ rows: new Set([1]), current: { row: 1, endRow: 1 } });
		expect(host.querySelector("[data-terminal-find-row-match]")).toBeNull();
		bar.close();
		expect(highlightFind).toHaveBeenLastCalledWith(null);
		bar.open();
		type(host.querySelector<HTMLInputElement>("input[data-terminal-find-input]")!, "line");
		await flushFrames();
		expect(highlightFind).toHaveBeenLastCalledWith({ rows: new Set([0, 1, 2]), current: { row: 0, endRow: 0 } });
		bar.dispose();
		expect(highlightFind).toHaveBeenLastCalledWith(null);
		renderer.dispose();
	});
});
```

- [ ] **Step 9: Export the new API**

In `packages/terminal/ts/renderer-dom/src/index.ts`, find (line 16):
```ts
export { createFindBar, type FindBar, type FindBarHost, type FindBarOptions } from "./find-bar.js";
```
Replace with:
```ts
export { createFindBar, type FindBar, type FindBarHost, type FindBarOptions } from "./find-bar.js";
export type { FindHighlights } from "./renderer-highlights.js";
export { compileMarks, type MarkRule } from "./marks.js";
export { HIGHLIGHT_PRIORITY, type HighlightKind } from "./highlights.js";
```

- [ ] **Step 10: Let the bench probe's find bar reach the renderer**

In `packages/terminal/bench/agent-session/highlight-probe.ts`, find:
```ts
						afterRepaint: (listener) => renderer.onPaint(listener),
					},
```
Replace with:
```ts
						afterRepaint: (listener) => renderer.onPaint(listener),
						highlightFind: (find) => renderer.setFindHighlights(find),
					},
```

- [ ] **Step 11: Run the renderer suite**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/renderer-dom"
npx tsc --noEmit -p .
npx vitest run
```
Expected: `tsc` prints nothing; vitest `Test Files  60 passed (60)` and `Tests  966 passed (966)` on the planning tree — in general the Task 0 counts for renderer-dom plus 4 files and 51 tests. Every existing selection and find test passes unchanged: `terminal-selection.test.ts`, `selection-fill.test.ts`, `find-bar.test.ts` (still asserts the `terminal-find-row-match` class and `[data-terminal-find-row-active]`).

- [ ] **Step 12: Prove selection and find look exactly as before**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
npm run build:ts
npm run check:boundaries
node bench/agent-session/affordance-gate.mjs --action select --out /tmp/plan5-after/affordance-select --compare /tmp/plan5-baselines/affordance-select | grep -v side-by-side
node bench/agent-session/affordance-gate.mjs --action find --out /tmp/plan5-after/affordance-find --compare /tmp/plan5-baselines/affordance-find | grep -v side-by-side
npm run bench:selection
```
Expected:
```
boundary check passed
no ownership timers found (5 files scanned)
SAME select-rows
SAME select-one-row
SAME select-cleared
{"action":"select","report":[]}
PASS select: every screenshot matches /tmp/plan5-baselines/affordance-select
SAME find-first
SAME find-next
SAME find-under-selection
SAME find-closed
{"action":"find","report":[["find-count","1 of 3","2 of 3"]]}
PASS find: every screenshot matches /tmp/plan5-baselines/affordance-find
PASS selection survived N repaints
```

- [ ] **Step 13: Prove the idle pixels did not move**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
(cd /tmp/plan5-baselines/feel && for f in */offset-*.png; do cp "$f" "$OLDPWD/bench/agent-session/baselines/$f"; done)
node bench/agent-session/feel-gate.mjs; echo "feel exit $?"
git checkout -- bench/agent-session/baselines
git status --short bench/agent-session/baselines
```
Expected: `PASS feel gate: zero pixel diff`, `feel exit 0`, and an empty `git status` line. (`$OLDPWD` is the `packages/terminal` directory the subshell left; if your shell does not set it, replace it with the absolute path of `packages/terminal`.)

- [ ] **Step 14: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/ts/renderer-dom/src/renderer-highlights.ts packages/terminal/ts/renderer-dom/src/dom-block-renderer.highlights.test.ts packages/terminal/ts/renderer-dom/src/renderer-selection.ts packages/terminal/ts/renderer-dom/src/selection-view.ts packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts packages/terminal/ts/renderer-dom/src/find-bar.ts packages/terminal/ts/renderer-dom/src/find-bar.test.ts packages/terminal/ts/renderer-dom/src/find-bar.incremental.test.ts packages/terminal/ts/renderer-dom/src/index.ts packages/terminal/bench/agent-session/highlight-probe.ts
git commit -m "renderer-dom: selection, find hits and user marks paint through one highlight model

The find bar hands its hits to the renderer (FindBarHost.highlightFind) and no
longer marks rows itself; DomBlockRenderer gains setMarks and setFindHighlights.
Selection and find screenshots are byte-identical to the unmodified tree.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: The `TerminalSurface` seam

**Files:**
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx:12,62,95,119,162,184,242`
- Modify: `packages/terminal/ts/react/src/index.ts:10`
- Test: `packages/terminal/ts/react/src/TerminalSurface.marks.test.tsx`

**Interfaces:**
- Consumes: `DomBlockRenderer.setMarks`, `DomBlockRenderer.setFindHighlights`, `MarkRule` (Task 4).
- Produces: `TerminalSurfaceProps.marks?: readonly MarkRule[]`; `export { warpDarkTheme, type MarkRule } from "@operator/terminal-renderer-dom"` in `@operator/terminal-react`.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/react/src/TerminalSurface.marks.test.tsx`:

```tsx
import { act, cleanup, render } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer, type MarkRule } from "@operator/terminal-renderer-dom";
import { TerminalSurface } from "./index";
import { feed, font, ignoreRaw, loadWasm, theme } from "./surface-harness";

const ERROR_MARK: MarkRule = { pattern: "error", regex: false, colour: "rgba(255, 0, 0, 0.4)" };

function flushFrames(count = 6): Promise<void> {
	return new Promise((resolve) => {
		let remaining = count;
		const step = () => {
			remaining -= 1;
			if (remaining <= 0) resolve();
			else requestAnimationFrame(step);
		};
		requestAnimationFrame(step);
	});
}

describe("TerminalSurface marks", () => {
	beforeAll(loadWasm);
	afterEach(() => {
		cleanup();
		vi.restoreAllMocks();
	});

	it("passes the marks prop to the renderer and an empty list when there is none", () => {
		const setMarks = vi.spyOn(DomBlockRenderer.prototype, "setMarks");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { rerender } = render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={ignoreRaw} />);
		expect(setMarks).toHaveBeenLastCalledWith([]);
		rerender(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={ignoreRaw} marks={[ERROR_MARK]} />);
		expect(setMarks).toHaveBeenLastCalledWith([ERROR_MARK]);
	});

	it("does not recompile marks for a new array with the same rules", () => {
		const setMarks = vi.spyOn(DomBlockRenderer.prototype, "setMarks");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const onSend = () => undefined;
		const { rerender } = render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={onSend} onSendRaw={ignoreRaw} marks={[ERROR_MARK]} />);
		setMarks.mockClear();
		rerender(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={onSend} onSendRaw={ignoreRaw} marks={[{ ...ERROR_MARK }]} />);
		expect(setMarks).not.toHaveBeenCalled();
	});

	it("keeps the marks on a renderer the surface rebuilds for a new onSend", () => {
		const mount = vi.spyOn(DomBlockRenderer.prototype, "mount");
		const setMarks = vi.spyOn(DomBlockRenderer.prototype, "setMarks");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const surfaceWith = (onSend: () => void) => (
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={onSend} onSendRaw={ignoreRaw} marks={[ERROR_MARK]} />
		);
		const { rerender } = render(surfaceWith(() => undefined));
		const first = mount.mock.contexts.at(-1);
		setMarks.mockClear();
		rerender(surfaceWith(() => undefined));
		const rebuilt = mount.mock.contexts.at(-1);
		expect(rebuilt).not.toBe(first);
		expect(setMarks).toHaveBeenLastCalledWith([ERROR_MARK]);
		expect(setMarks.mock.contexts.at(-1)).toBe(rebuilt);
	});

	it("routes the find bar's hits into the renderer's highlights and clears them when the surface unmounts", async () => {
		const setFindHighlights = vi.spyOn(DomBlockRenderer.prototype, "setFindHighlights");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		feed(core, "one\r\nerror\r\n");
		const { container, unmount } = render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={ignoreRaw} />);
		await act(async () => {
			document.dispatchEvent(new KeyboardEvent("keydown", { key: "f", metaKey: true, bubbles: true }));
		});
		const input = container.querySelector<HTMLInputElement>("input[data-terminal-find-input]")!;
		await act(async () => {
			input.value = "error";
			input.dispatchEvent(new Event("input", { bubbles: true }));
			await flushFrames();
		});
		expect(setFindHighlights).toHaveBeenLastCalledWith({ rows: new Set([1]), current: { row: 1, endRow: 1 } });
		unmount();
		expect(setFindHighlights).toHaveBeenLastCalledWith(null);
	});
});
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
npm run build:ts
cd ts/react && npx vitest run src/TerminalSurface.marks.test.tsx
```
Expected: `build:ts` succeeds (nothing uses `marks` yet); vitest FAILS: the first test sees `setMarks` never called (`expected "spy" to be called with arguments: [ [] ]`), the fourth sees `setFindHighlights` never called.

- [ ] **Step 3: Implement the prop and the find host**

In `packages/terminal/ts/react/src/TerminalSurface.tsx`:

Find (lines 12-13):
```tsx
	type HintEvent,
	type RendererFeatures,
```
Replace with:
```tsx
	type HintEvent,
	type MarkRule,
	type RendererFeatures,
```

Find (lines 62-63):
```tsx
	features?: Partial<RendererFeatures>;
	onPaint?: () => void;
```
Replace with:
```tsx
	features?: Partial<RendererFeatures>;
	marks?: readonly MarkRule[];
	onPaint?: () => void;
```

Find (lines 95-96):
```tsx
	features,
}: TerminalSurfaceProps): ReactElement {
```
Replace with:
```tsx
	features,
	marks,
}: TerminalSurfaceProps): ReactElement {
```

Find (lines 118-119):
```tsx
	const featuresRef = useRef(features);
	featuresRef.current = features;
```
Replace with:
```tsx
	const featuresRef = useRef(features);
	featuresRef.current = features;
	const marksRef = useRef(marks);
	marksRef.current = marks;
```

Find (line 162):
```tsx
		renderer.setSecretPatterns(secretPatternsRef.current ?? []);
```
Replace with:
```tsx
		renderer.setSecretPatterns(secretPatternsRef.current ?? []);
		renderer.setMarks(marksRef.current ?? []);
```

Find (line 184):
```tsx
				afterRepaint: (listener) => renderer.onPaint(listener),
```
Replace with:
```tsx
				afterRepaint: (listener) => renderer.onPaint(listener),
				highlightFind: (find) => renderer.setFindHighlights(find),
```

Find (lines 240-242):
```tsx
	useLayoutEffect(() => {
		rendererRef.current?.setSecretPatterns(secretPatterns ?? []);
	}, [secretPatterns]);
```
Replace with:
```tsx
	useLayoutEffect(() => {
		rendererRef.current?.setSecretPatterns(secretPatterns ?? []);
	}, [secretPatterns]);

	const marksKey = JSON.stringify(marks ?? []);
	useLayoutEffect(() => {
		rendererRef.current?.setMarks(marksRef.current ?? []);
	}, [marksKey]);
```

In `packages/terminal/ts/react/src/index.ts`, find (line 10):
```ts
export { warpDarkTheme } from "@operator/terminal-renderer-dom";
```
Replace with:
```ts
export { warpDarkTheme, type MarkRule } from "@operator/terminal-renderer-dom";
```

- [ ] **Step 4: Run it to see it pass**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
npm run build:ts
cd ts/react && npx vitest run
```
Expected: `build:ts` succeeds; `TerminalSurface.marks.test.tsx` 4 passed and the whole react suite passes (Task 0 count plus 1 file and 4 tests; on the planning tree `Test Files  12 passed (12)`, `Tests  127 passed (127)`).

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/ts/react/src/TerminalSurface.tsx packages/terminal/ts/react/src/index.ts packages/terminal/ts/react/src/TerminalSurface.marks.test.tsx
git commit -m "react: TerminalSurface takes a marks prop and routes find hits into the renderer

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Bench marks, the marks screenshots and the streaming A/B

**Files:**
- Modify: `packages/terminal/bench/agent-session/highlight-probe.ts`
- Modify: `packages/terminal/bench/agent-session/main.ts` (the probe import from Task 0, line 98, line 289)
- Modify: `packages/terminal/bench/agent-session/affordance-gate.mjs` (after the `find` action)
- Modify: `packages/terminal/bench/agent-session/run.mjs:18,27,38-40,151,160,298,307,352`
- Create: `packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-25-marks-control-run{1,2,3}.json`, `2026-09-25-marks-5-run{1,2,3}.json`, `2026-09-25-marks-profile-visible10.txt`

**Interfaces:**
- Consumes: `DomBlockRenderer.setMarks` (Task 4).
- Produces: `BENCH_MARKS` (5 rules), `window.__agentSession.setMarks(rules)`, agent-session URL param `?marks=N` (first N of `BENCH_MARKS`, applied to the main pane and every extra pane), `run.mjs --marks N`, `affordance-gate.mjs --action marks`.

- [ ] **Step 1: Add bench marks to the probe**

In `packages/terminal/bench/agent-session/highlight-probe.ts`:

Find:
```ts
import { createFindBar, type DomBlockRenderer, type FindBar, type SelectionPoint } from "@operator/terminal-renderer-dom";

export type HighlightProbe = {
```
Replace with:
```ts
import { createFindBar, type DomBlockRenderer, type FindBar, type MarkRule, type SelectionPoint } from "@operator/terminal-renderer-dom";

const tint = (ansi: number): string => `color-mix(in srgb, var(--terminal-ansi-${ansi}) 40%, transparent)`;

export const BENCH_MARKS: readonly MarkRule[] = [
	{ pattern: "thinking", regex: false, colour: tint(3) },
	{ pattern: "effort", regex: false, colour: tint(1) },
	{ pattern: "\\d+", regex: true, colour: tint(2) },
	{ pattern: "claude", regex: false, colour: tint(6) },
	{ pattern: "multipl\\w*", regex: true, colour: tint(5) },
];

export type HighlightProbe = {
```

Find:
```ts
	findHide(): Promise<void>;
};
```
Replace with:
```ts
	findHide(): Promise<void>;
	setMarks(rules: readonly MarkRule[]): Promise<void>;
};
```

Find:
```ts
		async findHide() {
			bar?.close();
			await frames(2);
		},
	};
```
Replace with:
```ts
		async findHide() {
			bar?.close();
			await frames(2);
		},
		async setMarks(rules) {
			renderer.setMarks(rules);
			await frames(2);
		},
	};
```

(The five patterns were chosen from `claude-spinner-10s`'s own text: `thinking` 67 times, `effort` 88, `multiply`/`multiplication` 7, `claude` in `brewupgradeclaude`, and digits on every spinner frame — so every rule paints while the spinner runs.)

- [ ] **Step 2: `?marks=N` on the agent-session page**

In `packages/terminal/bench/agent-session/main.ts`:

Find:
```ts
import { highlightProbe, type HighlightProbe } from "./highlight-probe";
```
Replace with:
```ts
import { BENCH_MARKS, highlightProbe, type HighlightProbe } from "./highlight-probe";
```

Find (line 98):
```ts
domRenderer.setFocused(params.get("focused") !== "0");
```
Replace with:
```ts
domRenderer.setFocused(params.get("focused") !== "0");
const benchMarks = BENCH_MARKS.slice(0, Number(params.get("marks") ?? "0"));
if (benchMarks.length > 0) domRenderer.setMarks(benchMarks);
```

Find (line 289, inside `mountPanes`, now two lines lower):
```ts
		(pane.getCoreForBench() as TerminalCore).setAgentTuiMode(true);
```
Replace with:
```ts
		(pane.getCoreForBench() as TerminalCore).setAgentTuiMode(true);
		if (benchMarks.length > 0) (pane as unknown as { renderer: DomBlockRenderer }).renderer.setMarks(benchMarks);
```
Check `wc -l packages/terminal/bench/agent-session/main.ts` prints `552` (≤ 600).

- [ ] **Step 3: `--marks N` in `run.mjs`**

In `packages/terminal/bench/agent-session/run.mjs`:

Find (line 18):
```js
	const out = { fixture: undefined, gate: false, features: "", panesOnly: false, profile: false, ungated: false, css: "", profileRow: "parked9" };
```
Replace with:
```js
	const out = { fixture: undefined, gate: false, features: "", panesOnly: false, profile: false, ungated: false, css: "", profileRow: "parked9", marks: 0 };
```

Find (line 27):
```js
		else if (argv[index] === "--profile-row") out.profileRow = argv[++index];
```
Replace with:
```js
		else if (argv[index] === "--profile-row") out.profileRow = argv[++index];
		else if (argv[index] === "--marks") out.marks = Number(argv[++index]);
```

Find (lines 38-40):
```js
async function openPage(browser, port, fixture, features, ungated = false, css = "") {
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	const suffix = `${features ? `&features=${encodeURIComponent(features)}` : ""}${ungated ? "&ungated=1" : ""}${css ? `&css=${encodeURIComponent(css)}` : ""}`;
```
Replace with:
```js
async function openPage(browser, port, fixture, features, ungated = false, css = "", marks = 0) {
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	const suffix = `${features ? `&features=${encodeURIComponent(features)}` : ""}${ungated ? "&ungated=1" : ""}${css ? `&css=${encodeURIComponent(css)}` : ""}${marks > 0 ? `&marks=${marks}` : ""}`;
```

Find (line 151):
```js
async function paneRows(browser, port, name, features, profile, ungated = false, css = "", profileRow = "parked9") {
```
Replace with:
```js
async function paneRows(browser, port, name, features, profile, ungated = false, css = "", profileRow = "parked9", marks = 0) {
```

Find (line 160):
```js
		const page = await openPage(browser, port, name, features, ungated, css);
```
Replace with:
```js
		const page = await openPage(browser, port, name, features, ungated, css, marks);
```

Find (line 298):
```js
	if (args.css) report.css = args.css;
```
Replace with:
```js
	if (args.css) report.css = args.css;
	if (args.marks > 0) report.marks = args.marks;
```

Find (line 307):
```js
				rows.panes = await paneRows(browser, port, name, args.features, args.profile, args.ungated, args.css, args.profileRow);
```
Replace with:
```js
				rows.panes = await paneRows(browser, port, name, args.features, args.profile, args.ungated, args.css, args.profileRow, args.marks);
```

Find (line 352):
```js
			process.stdout.write(`${JSON.stringify({ fixture: name, ...(args.css ? { css: args.css } : {}), ...rows })}\n`);
```
Replace with:
```js
			process.stdout.write(`${JSON.stringify({ fixture: name, ...(args.css ? { css: args.css } : {}), ...(args.marks > 0 ? { marks: args.marks } : {}), ...rows })}\n`);
```

- [ ] **Step 4: The `marks` affordance action**

In `packages/terminal/bench/agent-session/affordance-gate.mjs`, find (the end of the `find` action added in Task 0):
```js
		return [["find-count", first, next]];
	},
};
```
Replace with:
```js
		return [["find-count", first, next]];
	},
	async marks(page, shoot) {
		await shoot("marks-before");
		await page.evaluate(() => window.__agentSession.setMarks([
			{ pattern: "example", regex: false, colour: "color-mix(in srgb, var(--terminal-ansi-3) 40%, transparent)" },
			{ pattern: "TEXT", regex: false, colour: "color-mix(in srgb, var(--terminal-ansi-1) 40%, transparent)" },
			{ pattern: "\\d+", regex: true, colour: "color-mix(in srgb, var(--terminal-ansi-2) 40%, transparent)" },
		]));
		await shoot("marks-on");
		await page.evaluate(() => window.__agentSession.findShow("example", 1));
		await page.evaluate(() => window.__agentSession.selectCells(0, 2, 0, 30));
		await shoot("marks-overlap");
		await page.evaluate(() => window.__agentSession.selectionClear());
		await page.evaluate(() => window.__agentSession.findHide());
		await page.evaluate(() => window.__agentSession.setMarks([]));
		await shoot("marks-after");
		const painted = await page.evaluate(() => [...document.querySelectorAll("[data-terminal-row]")].filter((row) => row.style.backgroundImage !== "").length);
		return [["marks-rows-painted-after", painted, null]];
	},
};
```

- [ ] **Step 5: Run the marks screenshots and look at them**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
npm run build:ts
node bench/agent-session/affordance-gate.mjs --action marks --out /tmp/plan5-after/affordance-marks | grep -v side-by-side
```
Expected: `{"action":"marks","report":[["marks-rows-painted-after",0,null],["marks-after-equals-before",true,null]]}`. Open `/tmp/plan5-after/affordance-marks/marks-on.png`: `example` tinted yellow, both `text` words tinted red (literal, any case), every digit run tinted green; `marks-overlap.png`: on row 0 the selection band sits over the find tint, which sits over the yellow `example` mark; row 2 carries the current-hit outline. These PNGs are review evidence, not committed.

- [ ] **Step 6: The streaming A/B (alternated, three pairs)**

No other bench or build may run while this step runs.

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
mkdir -p /tmp/plan5-ab
cat > /tmp/plan5-ab/run.sh <<'EOF'
#!/usr/bin/env bash
set -eu
cd "$1"
i=0
for arm in control marks marks control control marks; do
  i=$((i+1))
  if [ "$arm" = marks ]; then node bench/agent-session/run.mjs --panes-only --marks 5 | tail -1 > "/tmp/plan5-ab/$i-$arm.json"
  else node bench/agent-session/run.mjs --panes-only | tail -1 > "/tmp/plan5-ab/$i-$arm.json"; fi
done
EOF
bash /tmp/plan5-ab/run.sh "$PWD"
cat > /tmp/plan5-ab/summary.mjs <<'EOF'
import { readFileSync, readdirSync } from "node:fs";
const dir = "/tmp/plan5-ab";
const fmt = (value) => value.toFixed(3);
const rows = readdirSync(dir).filter((name) => name.endsWith(".json")).sort().map((file) => {
	const report = JSON.parse(readFileSync(`${dir}/${file}`, "utf8"));
	return { file, arm: report.marks ? `marks=${report.marks}` : "control", solo: report.panes.solo, ten: report.panes.visible10 };
});
console.log("run | arm | solo task s | solo script s | 10-visible task s | 10-visible script s | 10-visible layout s | 10-visible style s");
for (const row of rows) console.log(`${row.file} | ${row.arm} | ${fmt(row.solo.TaskDuration)} | ${fmt(row.solo.ScriptDuration)} | ${fmt(row.ten.TaskDuration)} | ${fmt(row.ten.ScriptDuration)} | ${fmt(row.ten.LayoutDuration)} | ${fmt(row.ten.RecalcStyleDuration)}`);
for (const arm of ["control", "marks=5"]) {
	const values = rows.filter((row) => row.arm === arm).map((row) => row.ten.TaskDuration).sort((a, b) => a - b);
	console.log(`${arm}: 10-visible task ${fmt(values[0])}-${fmt(values[values.length - 1])} s over ${values.length} runs`);
}
EOF
node /tmp/plan5-ab/summary.mjs
```
Expected: six rows and two range lines. **Gate:** the `marks=5` 10-visible TaskDuration range must overlap the control range, or its lowest value must be within 10 % of the control's highest; otherwise stop, run Step 7, and report the numbers and the profile instead of claiming the gate. On the planning machine (Apple silicon, Chromium 1223, one run of this exact script): see the table in Step 9.

- [ ] **Step 7: Cross-check with a profile**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
node bench/agent-session/run.mjs --panes-only --marks 5 --profile --profile-row visible10 | tail -1 > /tmp/plan5-ab/profile.json
node -e 'const r = require("/tmp/plan5-ab/profile.json"); const p = r.panes.visible10.profile; console.log(`total self ms ${p.totalMs.toFixed(1)}`); for (const f of p.top) console.log(`${f.selfMs}\t${f.fn}`)' | tee /tmp/plan5-ab/profile-top.txt
grep -E "highlight|marks|rowPaint|markSpans|paint " /tmp/plan5-ab/profile-top.txt || echo "no highlight function in the top 20 self-time frames"
```
Expected: the top-20 self-time list over the 10-visible, 10-second window; either no highlight function appears, or the ones that do are listed with their milliseconds. Report what it printed.

- [ ] **Step 8: Keep the evidence**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/bench/agent-session/baselines/pane-cost"
cp /tmp/plan5-ab/1-control.json 2026-09-25-marks-control-run1.json
cp /tmp/plan5-ab/4-control.json 2026-09-25-marks-control-run2.json
cp /tmp/plan5-ab/5-control.json 2026-09-25-marks-control-run3.json
cp /tmp/plan5-ab/2-marks.json 2026-09-25-marks-5-run1.json
cp /tmp/plan5-ab/3-marks.json 2026-09-25-marks-5-run2.json
cp /tmp/plan5-ab/6-marks.json 2026-09-25-marks-5-run3.json
cp /tmp/plan5-ab/profile-top.txt 2026-09-25-marks-profile-visible10.txt
```

- [ ] **Step 9: Reference numbers from planning**

Measured on the planning machine with exactly Steps 6–7 (not a gate for your environment; put your own table in the report and in `TERMINAL.md` §4.31):

Final build (lazy row measuring, this plan's code), seconds per 10 s window:

| run | arm | solo task | solo script | 10-visible task | 10-visible script | 10-visible layout | 10-visible style |
|---|---|---|---|---|---|---|---|
| 1 | control | 0.344 | 0.103 | 1.277 | 0.424 | 0.371 | 0.117 |
| 2 | marks=5 | 0.432 | 0.155 | 1.085 | 0.456 | 0.272 | 0.096 |
| 3 | marks=5 | 0.374 | 0.133 | 1.155 | 0.486 | 0.291 | 0.103 |
| 4 | control | 0.202 | 0.053 | 1.266 | 0.424 | 0.365 | 0.117 |
| 5 | control | 0.298 | 0.086 | 1.088 | 0.363 | 0.315 | 0.098 |
| 6 | marks=5 | 0.304 | 0.108 | 1.124 | 0.478 | 0.287 | 0.101 |

10-visible TaskDuration: control 1.088–1.277 s, marks 1.085–1.155 s (overlapping — gate met). ScriptDuration is 0.03–0.12 s higher with marks per 10 s across ten panes. Profile cross-check (`--profile --profile-row visible10`): `paint highlight-painter.js` 23.7 ms and `apply highlight-painter.js` 13.8 ms self time over the 10 s window; `getBoundingClientRect` 357 ms with marks against 418 ms in the control profile — that is the pinned-header forced layout every visible pane already pays (`TERMINAL.md` §5 "What a parked pane still costs"), not the marks.

First build, for the record (it measured every rendered row on every paint through `renderedRows`): control 10-visible task 0.827–0.987 s / script 0.272–0.325 s; marks 1.292–1.568 s / 0.626–0.766 s — a failed gate, which is why Task 2 measures lazily. If your numbers look like this, the lazy path is not wired: check that `RendererHighlights` receives `rowRefs` from `renderedRowRefs`, not `renderedRows`.

- [ ] **Step 10: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/bench/agent-session/highlight-probe.ts packages/terminal/bench/agent-session/main.ts packages/terminal/bench/agent-session/affordance-gate.mjs packages/terminal/bench/agent-session/run.mjs packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-25-marks-control-run1.json packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-25-marks-control-run2.json packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-25-marks-control-run3.json packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-25-marks-5-run1.json packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-25-marks-5-run2.json packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-25-marks-5-run3.json packages/terminal/bench/agent-session/baselines/pane-cost/2026-09-25-marks-profile-visible10.txt
git commit -m "bench: marks on the agent-session page, run.mjs --marks, and the marks A/B

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Operator storage for marks

**Files:**
- Create: `frontend/src/renderer/lib/terminal-marks.ts`
- Test: `frontend/src/renderer/lib/terminal-marks.test.ts`
- Modify: `frontend/src/renderer/stores/ui-store.ts:30,71,103,157,172,216-217`
- Test: `frontend/src/renderer/stores/ui-store.terminal-marks.test.ts`

**Interfaces:**
- Consumes: `type MarkRule` from `@operator/terminal-react` (Task 5).
- Produces (`lib/terminal-marks.ts`): `terminalMarksStorageKey = "opr.terminal.marks"`, `MAX_TERMINAL_MARKS = 10`, `MAX_TERMINAL_MARK_PATTERN = 200`, `TERMINAL_MARK_COLOURS` (`{ id, ansi }[]`), `type TerminalMarkColour`, `type TerminalMark = { id, pattern, regex, colour }`, `terminalMarkAnsi(colour)`, `terminalMarkColourCss(colour)`, `terminalMarkPatternValid(pattern, regex)`, `terminalMarkRules(marks): MarkRule[]`, `sanitizeTerminalMarks(value)`, `readStoredTerminalMarks()`, `writeStoredTerminalMarks(marks)`, `newTerminalMark(existing)`. Store: `terminalMarks: readonly TerminalMark[]`, `setTerminalMarks(marks)`.

- [ ] **Step 1: Write the failing tests**

Create `frontend/src/renderer/lib/terminal-marks.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import {
	MAX_TERMINAL_MARK_PATTERN,
	MAX_TERMINAL_MARKS,
	TERMINAL_MARK_COLOURS,
	newTerminalMark,
	readStoredTerminalMarks,
	sanitizeTerminalMarks,
	terminalMarkColourCss,
	terminalMarkPatternValid,
	terminalMarkRules,
	terminalMarksStorageKey,
	writeStoredTerminalMarks,
	type TerminalMark,
} from "./terminal-marks";

const mark = (overrides: Partial<TerminalMark> = {}): TerminalMark => ({ id: "a", pattern: "error", regex: false, colour: "red", ...overrides });

describe("terminal marks", () => {
	afterEach(() => {
		vi.unstubAllGlobals();
		window.localStorage.clear();
	});

	it("offers five colours from the terminal palette and none of them is the selection's blue", () => {
		expect(TERMINAL_MARK_COLOURS.map((colour) => colour.id)).toEqual(["yellow", "red", "green", "cyan", "magenta"]);
		expect(TERMINAL_MARK_COLOURS.map((colour) => colour.ansi)).not.toContain(4);
	});

	it("tints a colour from the terminal's own ANSI variable at the selection's strength", () => {
		expect(terminalMarkColourCss("red")).toBe("color-mix(in srgb, var(--terminal-ansi-1) 40%, transparent)");
		expect(terminalMarkColourCss("cyan")).toBe("color-mix(in srgb, var(--terminal-ansi-6) 40%, transparent)");
	});

	it("turns stored marks into renderer rules and skips empty and broken patterns", () => {
		expect(terminalMarkRules([
			mark(),
			mark({ id: "b", pattern: "" }),
			mark({ id: "c", pattern: "(oops", regex: true }),
			mark({ id: "d", pattern: "FAIL|panic", regex: true, colour: "yellow" }),
		])).toEqual([
			{ pattern: "error", regex: false, colour: terminalMarkColourCss("red") },
			{ pattern: "FAIL|panic", regex: true, colour: terminalMarkColourCss("yellow") },
		]);
	});

	it("accepts any literal and only a regex that compiles", () => {
		expect(terminalMarkPatternValid("(oops", false)).toBe(true);
		expect(terminalMarkPatternValid("(oops", true)).toBe(false);
		expect(terminalMarkPatternValid("err(or)?", true)).toBe(true);
	});

	it("reads back what it wrote", () => {
		const marks = [mark(), mark({ id: "b", pattern: "warn", regex: true, colour: "green" })];
		writeStoredTerminalMarks(marks);
		expect(window.localStorage.getItem(terminalMarksStorageKey)).toBe(JSON.stringify(marks));
		expect(readStoredTerminalMarks()).toEqual(marks);
	});

	it("reads nothing from missing, broken or foreign storage", () => {
		expect(readStoredTerminalMarks()).toEqual([]);
		window.localStorage.setItem(terminalMarksStorageKey, "{not json");
		expect(readStoredTerminalMarks()).toEqual([]);
		window.localStorage.setItem(terminalMarksStorageKey, JSON.stringify({ pattern: "x" }));
		expect(readStoredTerminalMarks()).toEqual([]);
	});

	it("falls back to no marks when storage throws", () => {
		vi.stubGlobal("localStorage", {
			getItem: () => {
				throw new Error("denied");
			},
			setItem: () => {
				throw new Error("denied");
			},
		});
		expect(readStoredTerminalMarks()).toEqual([]);
		expect(() => writeStoredTerminalMarks([mark()])).not.toThrow();
	});

	it("drops malformed entries, duplicate ids, unknown colours and anything past the cap", () => {
		const many = Array.from({ length: MAX_TERMINAL_MARKS + 3 }, (_, index) => mark({ id: `m${index}` }));
		expect(sanitizeTerminalMarks([
			null,
			"error",
			{ id: "x", pattern: "a", regex: "yes", colour: "red" },
			{ id: "y", pattern: "a", regex: false, colour: "blue" },
			{ id: "", pattern: "a", regex: false, colour: "red" },
			mark({ id: "z" }),
			mark({ id: "z", pattern: "again" }),
		])).toEqual([mark({ id: "z" })]);
		expect(sanitizeTerminalMarks(many)).toHaveLength(MAX_TERMINAL_MARKS);
		expect(sanitizeTerminalMarks([mark({ pattern: "x".repeat(MAX_TERMINAL_MARK_PATTERN + 50) })])[0]!.pattern).toHaveLength(MAX_TERMINAL_MARK_PATTERN);
	});

	it("starts a new mark empty, literal, with a fresh id and the first colour not yet used", () => {
		const first = newTerminalMark([]);
		expect(first).toMatchObject({ pattern: "", regex: false, colour: "yellow" });
		const second = newTerminalMark([first]);
		expect(second.colour).toBe("red");
		expect(second.id).not.toBe(first.id);
	});
});
```

Create `frontend/src/renderer/stores/ui-store.terminal-marks.test.ts`:

```ts
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useUiStore } from "./ui-store";
import { MAX_TERMINAL_MARKS, terminalMarksStorageKey, type TerminalMark } from "../lib/terminal-marks";

const mark = (id: string): TerminalMark => ({ id, pattern: `word ${id}`, regex: false, colour: "red" });

describe("ui-store terminal marks", () => {
	beforeEach(() => {
		useUiStore.setState({ terminalMarks: [] });
	});

	afterEach(() => window.localStorage.clear());

	it("persists the list", () => {
		useUiStore.getState().setTerminalMarks([mark("a")]);
		expect(useUiStore.getState().terminalMarks).toEqual([mark("a")]);
		expect(window.localStorage.getItem(terminalMarksStorageKey)).toBe(JSON.stringify([mark("a")]));
	});

	it("keeps no more than the cap", () => {
		useUiStore.getState().setTerminalMarks(Array.from({ length: MAX_TERMINAL_MARKS + 2 }, (_, index) => mark(`m${index}`)));
		expect(useUiStore.getState().terminalMarks).toHaveLength(MAX_TERMINAL_MARKS);
	});

	it("starts from the marks a previous run saved", async () => {
		window.localStorage.setItem(terminalMarksStorageKey, JSON.stringify([mark("saved")]));
		vi.resetModules();
		const { useUiStore: fresh } = await import("./ui-store");
		expect(fresh.getState().terminalMarks).toEqual([mark("saved")]);
	});
});
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$(git rev-parse --show-toplevel)/frontend"
npx vitest run --config vite.renderer.config.ts src/renderer/lib/terminal-marks.test.ts src/renderer/stores/ui-store.terminal-marks.test.ts
```
Expected: FAIL — `Failed to resolve import "./terminal-marks"` and `Failed to resolve import "../lib/terminal-marks"`.

- [ ] **Step 3: Implement the library**

Create `frontend/src/renderer/lib/terminal-marks.ts`:

```ts
import type { MarkRule } from "@operator/terminal-react";

export const terminalMarksStorageKey = "opr.terminal.marks";
export const MAX_TERMINAL_MARKS = 10;
export const MAX_TERMINAL_MARK_PATTERN = 200;

export const TERMINAL_MARK_COLOURS = [
	{ id: "yellow", ansi: 3 },
	{ id: "red", ansi: 1 },
	{ id: "green", ansi: 2 },
	{ id: "cyan", ansi: 6 },
	{ id: "magenta", ansi: 5 },
] as const;

export type TerminalMarkColour = (typeof TERMINAL_MARK_COLOURS)[number]["id"];

export type TerminalMark = Readonly<{ id: string; pattern: string; regex: boolean; colour: TerminalMarkColour }>;

function getLocalStorage() {
	if (typeof window === "undefined" || !window.localStorage) return null;
	return window.localStorage;
}

function isColour(value: unknown): value is TerminalMarkColour {
	return TERMINAL_MARK_COLOURS.some((colour) => colour.id === value);
}

export function terminalMarkAnsi(colour: TerminalMarkColour): number {
	return TERMINAL_MARK_COLOURS.find((entry) => entry.id === colour)?.ansi ?? 3;
}

export function terminalMarkColourCss(colour: TerminalMarkColour): string {
	return `color-mix(in srgb, var(--terminal-ansi-${terminalMarkAnsi(colour)}) 40%, transparent)`;
}

export function terminalMarkPatternValid(pattern: string, regex: boolean): boolean {
	if (!regex) return true;
	try {
		new RegExp(pattern, "g");
		return true;
	} catch {
		return false;
	}
}

export function terminalMarkRules(marks: readonly TerminalMark[]): MarkRule[] {
	return marks
		.filter((mark) => mark.pattern !== "" && terminalMarkPatternValid(mark.pattern, mark.regex))
		.map((mark) => ({ pattern: mark.pattern, regex: mark.regex, colour: terminalMarkColourCss(mark.colour) }));
}

export function sanitizeTerminalMarks(value: unknown): TerminalMark[] {
	if (!Array.isArray(value)) return [];
	const out: TerminalMark[] = [];
	for (const entry of value) {
		if (out.length >= MAX_TERMINAL_MARKS) break;
		if (!entry || typeof entry !== "object") continue;
		const { id, pattern, regex, colour } = entry as Record<string, unknown>;
		if (typeof id !== "string" || id === "" || typeof pattern !== "string" || typeof regex !== "boolean" || !isColour(colour)) continue;
		if (out.some((mark) => mark.id === id)) continue;
		out.push({ id, pattern: pattern.slice(0, MAX_TERMINAL_MARK_PATTERN), regex, colour });
	}
	return out;
}

export function readStoredTerminalMarks(): TerminalMark[] {
	try {
		const raw = getLocalStorage()?.getItem(terminalMarksStorageKey);
		return raw ? sanitizeTerminalMarks(JSON.parse(raw)) : [];
	} catch {
		return [];
	}
}

export function writeStoredTerminalMarks(marks: readonly TerminalMark[]): void {
	try {
		getLocalStorage()?.setItem(terminalMarksStorageKey, JSON.stringify(marks));
	} catch {
		return;
	}
}

export function newTerminalMark(existing: readonly TerminalMark[]): TerminalMark {
	const used = new Set(existing.map((mark) => mark.colour));
	const colour = TERMINAL_MARK_COLOURS.find((entry) => !used.has(entry.id))?.id ?? TERMINAL_MARK_COLOURS[existing.length % TERMINAL_MARK_COLOURS.length]!.id;
	return { id: globalThis.crypto.randomUUID(), pattern: "", regex: false, colour };
}
```

- [ ] **Step 4: Add the store field**

In `frontend/src/renderer/stores/ui-store.ts`:

Find (line 30):
```ts
import { readStoredTerminalPredictiveEcho, terminalPredictiveEchoStorageKey } from "../lib/terminal-predictive-echo";
```
Replace with:
```ts
import { readStoredTerminalPredictiveEcho, terminalPredictiveEchoStorageKey } from "../lib/terminal-predictive-echo";
import { MAX_TERMINAL_MARKS, readStoredTerminalMarks, writeStoredTerminalMarks, type TerminalMark } from "../lib/terminal-marks";
```

Find (line 71):
```ts
	terminalPredictiveEcho: boolean;
	openFilesIn: OpenFilesIn;
```
Replace with:
```ts
	terminalPredictiveEcho: boolean;
	terminalMarks: readonly TerminalMark[];
	openFilesIn: OpenFilesIn;
```

Find (line 103):
```ts
	setTerminalPredictiveEcho: (enabled: boolean) => void;
```
Replace with:
```ts
	setTerminalPredictiveEcho: (enabled: boolean) => void;
	setTerminalMarks: (marks: readonly TerminalMark[]) => void;
```

Find (line 157):
```ts
const initialTerminalPredictiveEcho = readStoredTerminalPredictiveEcho();
```
Replace with:
```ts
const initialTerminalPredictiveEcho = readStoredTerminalPredictiveEcho();
const initialTerminalMarks = readStoredTerminalMarks();
```

Find (line 172):
```ts
	terminalPredictiveEcho: initialTerminalPredictiveEcho,
	openFilesIn: initialOpenFilesIn,
```
Replace with:
```ts
	terminalPredictiveEcho: initialTerminalPredictiveEcho,
	terminalMarks: initialTerminalMarks,
	openFilesIn: initialOpenFilesIn,
```

Find (lines 216-217):
```ts
		set({ terminalPredictiveEcho });
	},
```
Replace with:
```ts
		set({ terminalPredictiveEcho });
	},
	setTerminalMarks: (marks) => {
		const terminalMarks = marks.slice(0, MAX_TERMINAL_MARKS);
		writeStoredTerminalMarks(terminalMarks);
		set({ terminalMarks });
	},
```

- [ ] **Step 5: Run them to see them pass**

```bash
cd "$(git rev-parse --show-toplevel)/frontend"
npx vitest run --config vite.renderer.config.ts src/renderer/lib/terminal-marks.test.ts src/renderer/stores/ui-store.terminal-marks.test.ts
npx tsc --noEmit -p .
```
Expected: `Tests  12 passed (12)` (9 + 3); `tsc` prints nothing. (If `tsc` cannot find `MarkRule` in `@operator/terminal-react`, rebuild the package: `cd ../packages/terminal && npm run build:ts`.)

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add frontend/src/renderer/lib/terminal-marks.ts frontend/src/renderer/lib/terminal-marks.test.ts frontend/src/renderer/stores/ui-store.ts frontend/src/renderer/stores/ui-store.terminal-marks.test.ts
git commit -m "frontend: store terminal highlight words with a fixed five-colour palette

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Settings → Terminal highlights

**Files:**
- Create: `frontend/src/renderer/components/settings/TerminalMarksSection.tsx`
- Test: `frontend/src/renderer/components/settings/TerminalMarksSection.test.tsx`
- Modify: `frontend/src/renderer/components/GlobalSettingsForm.tsx:10,47-49`
- Modify: `frontend/src/renderer/i18n/en.json:608`

**Interfaces:**
- Consumes: Task 7's store and library; `Input` (`components/ui/input.tsx`), `Button` (`components/ui/button.tsx`, variants `ghost`/`secondary`, sizes `sm`/`icon-sm`), `SettingsOptionMenu` (`components/settings/SettingsOptionMenu.tsx`), `SettingsSection` (`components/settings/SettingsSection.tsx`), `warpDarkTheme` from `@operator/terminal-react` (the swatch colours; the test setup mocks it with black), `MessageKey` (`i18n/messages.ts`).
- Produces: `TerminalMarksSection({ titleHidden?: boolean })`.

- [ ] **Step 1: Add the copy**

In `frontend/src/renderer/i18n/en.json`, find (line 608):
```json
	"settings.terminalPredictiveEcho": "Show typing instantly on slow connections",
```
Replace with:
```json
	"settings.terminalPredictiveEcho": "Show typing instantly on slow connections",
	"settings.terminalMarks": "Terminal highlights",
	"settings.terminalMarks.empty": "Highlight words like error in every terminal.",
	"settings.terminalMarks.hint": "Words match in any case. Regular expressions match exactly as written.",
	"settings.terminalMarks.add": "Add highlight",
	"settings.terminalMarks.pattern": "Highlight {{index}} words",
	"settings.terminalMarks.placeholder": "error",
	"settings.terminalMarks.regex": "Use regular expression",
	"settings.terminalMarks.colour": "Highlight {{index}} colour",
	"settings.terminalMarks.remove": "Remove highlight {{index}}",
	"settings.terminalMarks.invalid": "Not a valid regular expression. This highlight is off until it is fixed.",
	"settings.terminalMarks.colour.yellow": "Yellow",
	"settings.terminalMarks.colour.red": "Red",
	"settings.terminalMarks.colour.green": "Green",
	"settings.terminalMarks.colour.cyan": "Cyan",
	"settings.terminalMarks.colour.magenta": "Magenta",
```
Check: `node -e 'JSON.parse(require("fs").readFileSync("frontend/src/renderer/i18n/en.json","utf8")); console.log("json ok")'` from the repo root prints `json ok`.

- [ ] **Step 2: Write the failing test**

Create `frontend/src/renderer/components/settings/TerminalMarksSection.test.tsx`:

```tsx
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, test } from "vitest";
import { MAX_TERMINAL_MARKS, terminalMarksStorageKey, type TerminalMark } from "../../lib/terminal-marks";
import { useUiStore } from "../../stores/ui-store";
import { TerminalMarksSection } from "./TerminalMarksSection";

const stored = (): TerminalMark[] => JSON.parse(window.localStorage.getItem(terminalMarksStorageKey) ?? "[]") as TerminalMark[];

afterEach(() => {
	useUiStore.setState({ terminalMarks: [] });
	window.localStorage.clear();
});

test("starts empty and says what a highlight is for", () => {
	render(<TerminalMarksSection />);
	expect(screen.getByText("Highlight words like error in every terminal.")).toBeInTheDocument();
	expect(screen.queryAllByTestId("terminal-mark-row")).toHaveLength(0);
});

test("adds a highlight, types its words and saves them", async () => {
	render(<TerminalMarksSection />);
	await userEvent.click(screen.getByRole("button", { name: "Add highlight" }));
	await userEvent.type(screen.getByRole("textbox", { name: "Highlight 1 words" }), "error");
	expect(useUiStore.getState().terminalMarks).toMatchObject([{ pattern: "error", regex: false, colour: "yellow" }]);
	expect(stored()).toMatchObject([{ pattern: "error", regex: false, colour: "yellow" }]);
	expect(screen.getByText("Words match in any case. Regular expressions match exactly as written.")).toBeInTheDocument();
});

test("switches a highlight to a regular expression and flags one that does not compile", async () => {
	useUiStore.setState({ terminalMarks: [{ id: "a", pattern: "(oops", regex: false, colour: "red" }] });
	render(<TerminalMarksSection />);
	expect(screen.queryByRole("alert")).toBeNull();
	const toggle = screen.getByRole("button", { name: "Use regular expression" });
	expect(toggle).toHaveAttribute("aria-pressed", "false");
	await userEvent.click(toggle);
	expect(useUiStore.getState().terminalMarks[0]!.regex).toBe(true);
	expect(screen.getByRole("button", { name: "Use regular expression" })).toHaveAttribute("aria-pressed", "true");
	expect(screen.getByRole("alert")).toHaveTextContent("Not a valid regular expression");
	expect(screen.getByRole("textbox", { name: "Highlight 1 words" })).toHaveAttribute("aria-invalid", "true");
});

test("changes a highlight's colour from the fixed palette", async () => {
	useUiStore.setState({ terminalMarks: [{ id: "a", pattern: "error", regex: false, colour: "yellow" }] });
	render(<TerminalMarksSection />);
	const trigger = screen.getByRole("button", { name: "Highlight 1 colour" });
	expect(trigger).toHaveTextContent("Yellow");
	await userEvent.click(trigger);
	const items = await screen.findAllByRole("menuitem");
	expect(items.map((item) => item.textContent)).toEqual(["Yellow", "Red", "Green", "Cyan", "Magenta"]);
	await userEvent.click(within(document.body).getByRole("menuitem", { name: "Cyan" }));
	expect(useUiStore.getState().terminalMarks[0]!.colour).toBe("cyan");
	expect(stored()[0]!.colour).toBe("cyan");
});

test("removes a highlight", async () => {
	useUiStore.setState({
		terminalMarks: [
			{ id: "a", pattern: "error", regex: false, colour: "red" },
			{ id: "b", pattern: "warn", regex: false, colour: "yellow" },
		],
	});
	render(<TerminalMarksSection />);
	await userEvent.click(screen.getByRole("button", { name: "Remove highlight 1" }));
	expect(useUiStore.getState().terminalMarks.map((mark) => mark.id)).toEqual(["b"]);
	expect(screen.getAllByTestId("terminal-mark-row")).toHaveLength(1);
});

test("stops offering Add at the cap", () => {
	useUiStore.setState({
		terminalMarks: Array.from({ length: MAX_TERMINAL_MARKS }, (_, index) => ({ id: `m${index}`, pattern: `w${index}`, regex: false, colour: "red" as const })),
	});
	render(<TerminalMarksSection />);
	expect(screen.queryByRole("button", { name: "Add highlight" })).toBeNull();
});
```

- [ ] **Step 3: Run it to see it fail**

```bash
cd "$(git rev-parse --show-toplevel)/frontend"
npx vitest run --config vite.renderer.config.ts src/renderer/components/settings/TerminalMarksSection.test.tsx
```
Expected: FAIL — `Failed to resolve import "./TerminalMarksSection"`.

- [ ] **Step 4: Implement the section**

Create `frontend/src/renderer/components/settings/TerminalMarksSection.tsx`:

```tsx
import { Plus, Trash2 } from "lucide-react";
import { Fragment } from "react";
import { useTranslation } from "react-i18next";
import { warpDarkTheme } from "@operator/terminal-react";
import type { MessageKey } from "../../i18n/messages";
import {
	MAX_TERMINAL_MARK_PATTERN,
	MAX_TERMINAL_MARKS,
	TERMINAL_MARK_COLOURS,
	newTerminalMark,
	terminalMarkPatternValid,
	type TerminalMark,
	type TerminalMarkColour,
} from "../../lib/terminal-marks";
import { useUiStore } from "../../stores/ui-store";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { SettingsOptionMenu, type SettingsOption } from "./SettingsOptionMenu";
import { SettingsSection } from "./SettingsSection";

const COLOUR_LABELS: Record<TerminalMarkColour, MessageKey> = {
	yellow: "settings.terminalMarks.colour.yellow",
	red: "settings.terminalMarks.colour.red",
	green: "settings.terminalMarks.colour.green",
	cyan: "settings.terminalMarks.colour.cyan",
	magenta: "settings.terminalMarks.colour.magenta",
};

function Swatch({ ansi }: { ansi: number }) {
	return (
		<span
			aria-hidden="true"
			className="size-3.5 shrink-0 rounded-full border border-white/15"
			style={{ backgroundColor: warpDarkTheme.ansi[ansi] }}
		/>
	);
}

export function TerminalMarksSection({ titleHidden }: { titleHidden?: boolean }) {
	const { t } = useTranslation();
	const marks = useUiStore((state) => state.terminalMarks);
	const setMarks = useUiStore((state) => state.setTerminalMarks);
	const update = (id: string, patch: Partial<Omit<TerminalMark, "id">>) =>
		setMarks(marks.map((mark) => (mark.id === id ? { ...mark, ...patch } : mark)));
	const colourOptions = TERMINAL_MARK_COLOURS.map((colour) => ({
		value: colour.id,
		label: t(COLOUR_LABELS[colour.id]),
		icon: <Swatch ansi={colour.ansi} />,
	})) satisfies SettingsOption<TerminalMarkColour>[];

	return (
		<SettingsSection title={t("settings.terminalMarks")} titleHidden={titleHidden} grouped>
			<div className="settings-row-bar">
				<span className="text-sm leading-5 text-settings-muted">
					{marks.length === 0 ? t("settings.terminalMarks.empty") : t("settings.terminalMarks.hint")}
				</span>
			</div>
			{marks.map((mark, index) => {
				const invalid = !terminalMarkPatternValid(mark.pattern, mark.regex);
				const position = index + 1;
				return (
					<Fragment key={mark.id}>
						<div className="settings-row-bar gap-2" data-testid="terminal-mark-row">
							<Input
								aria-label={t("settings.terminalMarks.pattern", { index: position })}
								aria-invalid={invalid || undefined}
								className="min-w-0 flex-1 font-mono"
								maxLength={MAX_TERMINAL_MARK_PATTERN}
								placeholder={t("settings.terminalMarks.placeholder")}
								spellCheck={false}
								value={mark.pattern}
								onChange={(event) => update(mark.id, { pattern: event.target.value })}
							/>
							<Button
								type="button"
								variant={mark.regex ? "secondary" : "ghost"}
								size="sm"
								className="font-mono"
								aria-label={t("settings.terminalMarks.regex")}
								aria-pressed={mark.regex}
								title={t("settings.terminalMarks.regex")}
								onClick={() => update(mark.id, { regex: !mark.regex })}
							>
								.*
							</Button>
							<SettingsOptionMenu
								aria-label={t("settings.terminalMarks.colour", { index: position })}
								value={mark.colour}
								options={colourOptions}
								onChange={(colour) => update(mark.id, { colour })}
							/>
							<Button
								type="button"
								variant="ghost"
								size="icon-sm"
								aria-label={t("settings.terminalMarks.remove", { index: position })}
								onClick={() => setMarks(marks.filter((entry) => entry.id !== mark.id))}
							>
								<Trash2 aria-hidden="true" />
							</Button>
						</div>
						{invalid ? (
							<p role="alert" className="px-3 pb-2 text-xs leading-4 text-destructive">
								{t("settings.terminalMarks.invalid")}
							</p>
						) : null}
					</Fragment>
				);
			})}
			{marks.length < MAX_TERMINAL_MARKS ? (
				<div className="settings-row-bar">
					<Button type="button" variant="ghost" size="sm" onClick={() => setMarks([...marks, newTerminalMark(marks)])}>
						<Plus aria-hidden="true" />
						{t("settings.terminalMarks.add")}
					</Button>
				</div>
			) : null}
		</SettingsSection>
	);
}
```

- [ ] **Step 5: Put it on the Settings page**

In `frontend/src/renderer/components/GlobalSettingsForm.tsx`:

Find (line 10):
```tsx
import { SettingsSection } from "./settings/SettingsSection";
```
Replace with:
```tsx
import { SettingsSection } from "./settings/SettingsSection";
import { TerminalMarksSection } from "./settings/TerminalMarksSection";
```

Find (lines 47-49):
```tsx
							titleHidden={leadingTitleHidden}
						/>
						<SettingsSection title={t("settings.preferences")} grouped>
```
Replace with:
```tsx
							titleHidden={leadingTitleHidden}
						/>
						<TerminalMarksSection />
						<SettingsSection title={t("settings.preferences")} grouped>
```

- [ ] **Step 6: Run the tests**

```bash
cd "$(git rev-parse --show-toplevel)/frontend"
npx vitest run --config vite.renderer.config.ts src/renderer/components/settings src/renderer/components/GlobalSettingsForm.test.tsx
npx tsc --noEmit -p .
npx eslint src/renderer/components/settings/TerminalMarksSection.tsx src/renderer/components/settings/TerminalMarksSection.test.tsx src/renderer/components/GlobalSettingsForm.tsx
```
Expected: every file passes (`TerminalMarksSection.test.tsx` 6 tests); `tsc` prints nothing; eslint prints nothing for these three files.

- [ ] **Step 7: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add frontend/src/renderer/components/settings/TerminalMarksSection.tsx frontend/src/renderer/components/settings/TerminalMarksSection.test.tsx frontend/src/renderer/components/GlobalSettingsForm.tsx frontend/src/renderer/i18n/en.json
git commit -m "frontend: Settings → Terminal highlights, a list of words or patterns with a colour each

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Every terminal gets the marks

**Files:**
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx:19,464,597-598`
- Modify: `frontend/src/renderer/components/BlockTerminal.test.tsx:54,178-181,411,561`

**Interfaces:**
- Consumes: `terminalMarkRules` (Task 7), `TerminalSurface` prop `marks` (Task 5).
- Produces: `BlockTerminal` passes `marks` to `TerminalSurface`.

- [ ] **Step 1: Write the failing tests**

In `frontend/src/renderer/components/BlockTerminal.test.tsx`:

Find (line 54):
```tsx
		visible: undefined as boolean | undefined,
```
Replace with:
```tsx
		visible: undefined as boolean | undefined,
		marks: undefined as readonly { pattern: string; regex: boolean; colour: string }[] | undefined,
```

Find (lines 178-181):
```tsx
			visible?: boolean;
		}) => {
			mockState.focusToken = props.focusToken;
			mockState.visible = props.visible;
```
Replace with:
```tsx
			visible?: boolean;
			marks?: readonly { pattern: string; regex: boolean; colour: string }[];
		}) => {
			mockState.focusToken = props.focusToken;
			mockState.visible = props.visible;
			mockState.marks = props.marks;
```

Find (line 411, now 413):
```tsx
	mockState.visible = undefined;
```
Replace with:
```tsx
	mockState.visible = undefined;
	mockState.marks = undefined;
```

Find (line 561, now 564):
```tsx
	it("hands the host's focus token to the surface", async () => {
```
Replace with:
```tsx
	it("gives the surface no marks while Settings has none", async () => {
		useUiStore.setState({ terminalMarks: [] });
		renderTerminal();
		await waitFor(() => expect(mockState.marks).toEqual([]));
	});

	it("hands Settings' highlights to the surface as renderer rules and follows edits", async () => {
		useUiStore.setState({ terminalMarks: [{ id: "a", pattern: "error", regex: false, colour: "red" }] });
		renderTerminal();
		await waitFor(() =>
			expect(mockState.marks).toEqual([{ pattern: "error", regex: false, colour: "color-mix(in srgb, var(--terminal-ansi-1) 40%, transparent)" }]),
		);
		act(() => {
			useUiStore.setState({
				terminalMarks: [
					{ id: "a", pattern: "error", regex: false, colour: "red" },
					{ id: "b", pattern: "(broken", regex: true, colour: "green" },
					{ id: "c", pattern: "FAIL|panic", regex: true, colour: "yellow" },
				],
			});
		});
		await waitFor(() => expect(mockState.marks?.map((mark) => mark.pattern)).toEqual(["error", "FAIL|panic"]));
		useUiStore.setState({ terminalMarks: [] });
	});

	it("hands the host's focus token to the surface", async () => {
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$(git rev-parse --show-toplevel)/frontend"
npx vitest run --config vite.renderer.config.ts src/renderer/components/BlockTerminal.test.tsx -t "marks|highlights"
```
Expected: FAIL — both new tests time out in `waitFor` with `expected undefined to deeply equal []` / `… to deeply equal [ { pattern: 'error', … } ]`.

- [ ] **Step 3: Pass the marks**

In `frontend/src/renderer/components/BlockTerminal.tsx`:

Find (line 19):
```tsx
import { terminalPredictiveEchoThresholdMs } from "../lib/terminal-predictive-echo";
```
Replace with:
```tsx
import { terminalPredictiveEchoThresholdMs } from "../lib/terminal-predictive-echo";
import { terminalMarkRules } from "../lib/terminal-marks";
```

Find (line 464):
```tsx
	const predictiveEcho = useUiStore((state) => state.terminalPredictiveEcho);
```
Replace with:
```tsx
	const terminalMarks = useUiStore((state) => state.terminalMarks);
	const marks = useMemo(() => terminalMarkRules(terminalMarks), [terminalMarks]);
	const predictiveEcho = useUiStore((state) => state.terminalPredictiveEcho);
```

Find (lines 597-598, now 600-601):
```tsx
		visible,
		onDraftChange,
```
Replace with:
```tsx
		visible,
		marks,
		onDraftChange,
```

- [ ] **Step 4: Run them to see them pass**

```bash
cd "$(git rev-parse --show-toplevel)/frontend"
npx vitest run --config vite.renderer.config.ts src/renderer/components/BlockTerminal.test.tsx
npx tsc --noEmit -p .
```
Expected: the whole file passes including the two new tests; `tsc` prints nothing.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add frontend/src/renderer/components/BlockTerminal.tsx frontend/src/renderer/components/BlockTerminal.test.tsx
git commit -m "frontend: every terminal paints the highlight words from Settings

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: Documentation

**Files:**
- Modify: `packages/terminal/CHANGELOG.md:3-4`
- Modify: `TERMINAL.md:257-262` (§3 rule 2), `:939-941` (new §4.31 before `## 5.`), `:943-947` (§5 first bullet)
- Modify: `docs/terminal/2026-09-19-terminal-reference-survey.md:50,61,97,116,683,2490,3359`
- Modify: `docs/terminal/2026-09-24-not-done-plain-language.md:33-39`

- [ ] **Step 1: CHANGELOG**

In `packages/terminal/CHANGELOG.md`, find (lines 3-4):
```markdown
## Unreleased

```
Replace with (one entry; keep the blank line after it):
```markdown
## Unreleased

- renderer-dom/react: one highlight model (roadmap Plan 5, survey §1.8 and §5.6). `highlights.ts` holds `Highlight { kind, range, colour, rank }` with ranges in stable rows and the priority selection > current find hit > other find hits > user marks; `highlight-painter.ts` is the only code that paints them (row `background-image` layers top first, the same layers clipped onto runs with their own background, and the find row classes); `renderer-highlights.ts` owns the selection, the find hits and the marks and paints from `finishPaint` and on every change without scheduling a repaint. The find bar no longer marks rows: it hands `{ rows, current }` to `FindBarHost.highlightFind` (new, required), which `TerminalSurface` wires to `DomBlockRenderer.setFindHighlights`. User marks: `DomBlockRenderer.setMarks(rules)` and `TerminalSurface`'s `marks` prop take `MarkRule { pattern, regex, colour }` (literal = any case; regex = as written; invalid, empty, zero-width or badly coloured rules are ignored), matched per painted logical line and cached per line, so they survive a trim and a rewrap. Pixels: with nothing highlighted, `bench:feel` is unchanged; selection and find screenshots are byte-identical to before; a row with both a find hit and a mark draws the find tint as a layer above the mark (≤ 1 colour level from the old fill). Links, hints, redaction and prediction stay overlays in `decorations.ts` (they paint above the text). Bench: `affordance-gate.mjs --action select|find|marks`, `--out`, `--compare`; agent-session `?marks=N`; `run.mjs --marks N`.
```

- [ ] **Step 2: `TERMINAL.md` §3 rule 2**

Find (lines 257-262):
```markdown
2. **Match Warp, cite Warp.** Rendering/behaviour decisions quote the Warp file
   and line they mirror (see the comments already in `styles.css`, `screen.rs`).
   Find cites two MIT/Apache references for behaviour only, no code adapted:
   Ghostty `src/terminal/search/active.zig:11-19` (re-search only what can
   change) and Alacritty `alacritty_terminal/src/term/search.rs:39-40` (smart
   case).
```
Replace with:
```markdown
2. **Match Warp, cite Warp.** Rendering/behaviour decisions quote the Warp file
   and line they mirror (see the comments already in `styles.css`, `screen.rs`).
   Find cites two MIT/Apache references for behaviour only, no code adapted:
   Ghostty `src/terminal/search/active.zig:11-19` (re-search only what can
   change) and Alacritty `alacritty_terminal/src/term/search.rs:39-40` (smart
   case). Highlights (§4.31) cite Ghostty `src/terminal/highlight.zig:1-10`
   (one representation for selection, search and marks) for behaviour only, no
   code adapted; Kitty's marks are GPL-3.0 and were not read.
```

- [ ] **Step 3: `TERMINAL.md` §4.31**

Find (lines 939-941):
```markdown
  `useTerminalSession.test.tsx` health tests.

## 5. Known gaps (not bugs, decisions pending)
```
Replace with:
```markdown
  `useTerminalSession.test.tsx` health tests.

### 4.31 One look for highlights; user marks — roadmap Plan 5
- Before: the selection painted its own `background-image` per row
  (`selection-view.ts` `selectionFills`), the find bar added and removed row
  classes itself on every repaint (`find-bar.ts` `applyHighlights`), and there
  were no user marks. Two paint paths for one idea, and nothing to put a third
  kind on.
- Now: `highlights.ts` is the model — `Highlight { kind, range, colour, rank }`,
  `range` in stable rows (§2), priority selection 3 > current find hit 2 > find
  hit 1 > mark 0, earlier mark rule above a later one. `highlight-painter.ts` is
  the only code that paints them: a row's layers, top first, as one
  `background-image` of `fillGradient` strings, the same layers clipped by
  `runFill` onto runs with their own background (the §4.11 rule, now for every
  kind), and the find classes. It diffs against what it painted, so an unchanged
  row gets no write. `renderer-highlights.ts` collects selection, find and
  marks and calls it from `finishPaint` and on every change; it never schedules
  a repaint, and it paints nothing while the pane is parked.
- Find keeps its old pixels on purpose: a hit row keeps
  `terminal-find-row-match` (a background colour) and the current hit keeps the
  `terminal-find-row-active` outline. A gradient layer of the same colour
  differs by up to 1 level per channel (measured while planning: 8,278 channel
  values in a 900×60 Chromium shot), so the colour stays a colour — except on a
  row that also has a mark, where the find tint becomes a layer above the mark
  so the priority holds. Find paints only transcript rows, never the alternate
  screen, as before.
- Marks: `setMarks(rules)` / `TerminalSurface` `marks`, `MarkRule { pattern,
  regex, colour }`. Literal = escaped, any case; regex = as written. Invalid
  regex, empty pattern, zero-length matches and colours `CSS.supports` rejects
  are dropped; touching matches of one rule merge. Each paint joins the logical
  lines of the rendered rows once (`visibleLogicalLines`), matches each line,
  and maps back with `rangeOf`; `MarkCache` keeps each line's spans while its
  text is unchanged. Nothing is stored in rows, so a trim or a rewrap cannot
  strand a mark. Marks read the masked text, so they never outline a redacted
  secret. Operator: Settings → Terminal highlights, five colours
  (`color-mix(in srgb, var(--terminal-ansi-N) 40%, transparent)` for yellow 3,
  red 1, green 2, cyan 6, magenta 5 — no blue, the selection's colour), at most
  10 rules, stored under `opr.terminal.marks`.
- Not moved onto the model: links, hints, redaction and prediction. They are
  overlays above the text (`.terminal-decorations { z-index: 2 }`); a redaction
  must cover glyphs. The model paints under the text.
- Cost (`run.mjs --panes-only`, `claude-spinner-10s`, alternated A/B, three
  pairs, 5 `BENCH_MARKS`, planning machine): 10-visible TaskDuration control
  1.088–1.277 s, marks 1.085–1.155 s, ScriptDuration +0.03–0.12 s per 10 s
  across ten panes (replace with your Task 6 numbers if they differ). The
  painter measures only rows a highlight touches; a first build that measured
  every rendered row per paint doubled ScriptDuration;
  profile of the marks 10-visible row in
  `bench/agent-session/baselines/pane-cost/2026-09-25-marks-profile-visible10.txt`.
- Known risk, not fixed: JavaScript has no regex time limit. A user regex with
  catastrophic backtracking runs on each changed painted line. The per-line
  cache means only lines whose text changed are rescanned.
- Guards: `highlights.test.ts`, `highlight-painter.test.ts`, `marks.test.ts`,
  `dom-block-renderer.highlights.test.ts` (overlap order, trim, rewrap, no
  repaint scheduled, no layout read when idle, parked, alternate screen,
  rejected colour, dispose), `find-bar.incremental.test.ts` "hands its hits…",
  `TerminalSurface.marks.test.tsx`, `terminal-selection.test.ts` (unchanged),
  `bench:affordances --action select|find --compare <Task 0 captures>` (byte
  identical), `bench:selection`, `bench:feel`; Operator:
  `terminal-marks.test.ts`, `ui-store.terminal-marks.test.ts`,
  `TerminalMarksSection.test.tsx`, `BlockTerminal.test.tsx` "hands Settings'
  highlights…".

## 5. Known gaps (not bugs, decisions pending)
```

- [ ] **Step 4: `TERMINAL.md` §5 first bullet**

Find (lines 943-947):
```markdown
- **Find exports every hit on every change.** `findResults` copies all hits
  out of wasm whenever an update adds or removes one; while Claude streams, a
  query with hundreds of thousands of hits (a single letter) pays that per
  paint. Hits are still row classes, not decorations (survey §1.8, Plan 5),
  and there is no host `onResultsChanged` (survey §3.12).
```
Replace with:
```markdown
- **Find exports every hit on every change.** `findResults` copies all hits
  out of wasm whenever an update adds or removes one; while Claude streams, a
  query with hundreds of thousands of hits (a single letter) pays that per
  paint. Hits paint through the highlight model since Plan 5 (§4.31) but still
  as whole rows, not the hit's cells, and there is no host `onResultsChanged`
  (survey §3.12).
```

- [ ] **Step 5: Survey status lines and table**

In `docs/terminal/2026-09-19-terminal-reference-survey.md`:

Line 61 — find:
```markdown
| §1.8 | Not done | The selection paints through `selection-fill` and find hits use row classes; Plan E's range painter (`decorations.ts`) serves links, hints, redaction and prediction only. |
```
Replace with:
```markdown
| §1.8 | Done | Roadmap Plan 5 — `highlights.ts` (ranges in stable rows, a kind, a priority) painted only by `highlight-painter.ts`; selection, find hits and user marks all go through it (`renderer-highlights.ts`). Links, hints, redaction and prediction stay overlays in `decorations.ts` because they paint above the text. Find hits keep their whole-row look. |
```

Line 97 — find:
```markdown
| §3.12 | Partial | Plan 2 — the find bar updates on every paint through `findUpdate` (new matches appear without retyping; history is not rescanned) and keeps the current hit anchored by stable row. Not done: hits as decorations (still row classes, §1.8) and a host `onResultsChanged`. |
```
Replace with:
```markdown
| §3.12 | Partial | Plan 2 — the find bar updates on every paint through `findUpdate` (new matches appear without retyping; history is not rescanned) and keeps the current hit anchored by stable row. Plan 5 — hits paint through the highlight model (§1.8), still whole rows. Not done: a host `onResultsChanged`. |
```

Line 116 — find:
```markdown
| §5.6 | Not done | No host highlight-rule or marker API. |
```
Replace with:
```markdown
| §5.6 | Done | Roadmap Plan 5 — `DomBlockRenderer.setMarks` / `TerminalSurface` `marks` (`MarkRule { pattern, regex, colour }`), matched per painted logical line; Operator Settings → Terminal highlights. Not built: next/previous-mark navigation. |
```

Line 683 — find:
```markdown
> **Status: Not done.** The selection paints through `selection-fill` and find hits use row classes; Plan E's range painter (`decorations.ts`) serves links, hints, redaction and prediction only.
```
Replace with:
```markdown
> **Status: Done.** Roadmap Plan 5 — one model (`highlights.ts`), one painter (`highlight-painter.ts`) for selection, find hits and user marks; links, hints, redaction and prediction stay overlays in `decorations.ts` (above the text). See `TERMINAL.md` §4.31.
```

Line 2490 — find:
```markdown
> **Status: Partial.** Plan 2 — re-search on every paint through `findUpdate`, current hit anchored by stable row. Not done: hits as decorations (still row classes, §1.8) and `onResultsChanged`.
```
Replace with:
```markdown
> **Status: Partial.** Plan 2 — re-search on every paint through `findUpdate`, current hit anchored by stable row. Plan 5 — hits paint through the highlight model (§1.8). Not done: `onResultsChanged`.
```

Line 3359 — find:
```markdown
> **Status: Not done.** No host highlight-rule or marker API.
```
Replace with:
```markdown
> **Status: Done.** Roadmap Plan 5 — `setMarks(rules)` / `TerminalSurface` `marks`, literal (any case) or regex rules with a colour, painted by the §1.8 model; Operator Settings → Terminal highlights. Not built: next/previous-mark navigation. See `TERMINAL.md` §4.31.
```

Recount and fix line 50:
```bash
cd "$(git rev-parse --show-toplevel)"
awk -F'|' '/^\| §/ {gsub(/ /,"",$3); print $3}' docs/terminal/2026-09-19-terminal-reference-survey.md | sort | uniq -c
```
Expected on the planning tree after the edits: `41 Done`, `1 N/A`, `19 Notdone`, `1 Notneeded`, `7 Notpursued`, `19 Partial`. Then in line 50 find `39 done, 19 partial, 21 not done, 7 not pursued, 1 not needed, 1 n/a` and replace it with the numbers the command printed, in the same order and wording (planning tree: `41 done, 19 partial, 19 not done, 7 not pursued, 1 not needed, 1 n/a`); in the same line find `"Roadmap Plan 1" is the paste-safety plan (`docs/superpowers/plans/2026-09-24-terminal-plan-1-paste-safety.md`).` and replace it with `"Roadmap Plan 1" is the paste-safety plan (`docs/superpowers/plans/2026-09-24-terminal-plan-1-paste-safety.md`); "Roadmap Plan 5" is the highlights plan (`docs/superpowers/plans/2026-09-25-terminal-plan-5-highlights-marks.md`).`

- [ ] **Step 6: Plain-language doc items 3 and 4**

In `docs/terminal/2026-09-24-not-done-plain-language.md`, find (lines 33-39):
```markdown
3. **One look for everything highlighted (§1.8).** Selected text, search
   matches and other marks are drawn by separate code, so they can look
   inconsistent or clash. *If done:* they all look and behave the same, and
   overlap cleanly.
4. **Highlight words you care about (§5.6).** You can't tell the terminal
   "always highlight the word ERROR in red". *If done:* important words stand
   out while you scroll.
```
Replace with:
```markdown
3. **One look for everything highlighted (§1.8).** Selected text, search
   matches and other marks are drawn by separate code, so they can look
   inconsistent or clash. *If done:* they all look and behave the same, and
   overlap cleanly.
   **Done (roadmap Plan 5):** selection, search matches and your own
   highlights are drawn by one piece of code. Where they overlap, the
   selection is on top, then the current search match, then other matches,
   then your highlights. Selection and search look exactly as before.
4. **Highlight words you care about (§5.6).** You can't tell the terminal
   "always highlight the word ERROR in red". *If done:* important words stand
   out while you scroll.
   **Done (roadmap Plan 5):** Settings → Terminal highlights. Add a word (any
   capitalisation matches) or a pattern (the `.*` button), pick one of five
   colours, and it is coloured in every terminal, Claude Code panes included.
```
Also, in line 7 of the same file, find `(item 5 has since been done, roadmap Plan 1)` and replace it with `(items 3, 4 and 5 have since been done, roadmap Plans 5 and 1)`.

- [ ] **Step 7: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/CHANGELOG.md TERMINAL.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/terminal/2026-09-24-not-done-plain-language.md
git commit -m "docs: TERMINAL.md §4.31 highlights and marks; survey §1.8 and §5.6 done

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 11: Every gate

**Files:** none changed (restore any bench PNG a gate rewrote before the next step).

- [ ] **Step 1: Package build, boundaries and unit suites**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
npm run build
npm run check:boundaries
for p in core renderer-dom editor react; do (cd ts/$p && echo "== $p" && npx vitest run 2>&1 | grep -E "Test Files|Tests  "); done
wc -l ts/renderer-dom/src/dom-block-renderer.ts ts/renderer-dom/src/renderer-highlights.ts ts/renderer-dom/src/highlight-painter.ts ts/renderer-dom/src/marks.ts ts/renderer-dom/src/highlights.ts bench/agent-session/main.ts
```
Expected: `boundary check passed`, `no ownership timers found (5 files scanned)`; every suite passes; renderer-dom = Task 0 + 4 files / + 51 tests; react = Task 0 + 1 file / + 4 tests; core and editor unchanged; `dom-block-renderer.ts` 600 lines, every listed file ≤ 600.

- [ ] **Step 2: Frontend**

```bash
cd "$(git rev-parse --show-toplevel)/frontend"
npm run typecheck
npm run lint 2>&1 | tail -2
npx vitest run --config vite.renderer.config.ts 2>&1 | grep -E "Test Files|Tests  "
```
Expected: typecheck clean; lint `(0 errors, N warnings)` with N equal to Task 0's count; vitest = Task 0 + 3 files / + 20 tests, all passed.

- [ ] **Step 3: Pixel gates**

```bash
export PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH:-}
cd "$(git rev-parse --show-toplevel)/packages/terminal"
(cd /tmp/plan5-baselines/feel && for f in */offset-*.png; do cp "$f" "$OLDPWD/bench/agent-session/baselines/$f"; done)
node bench/agent-session/feel-gate.mjs; echo "feel exit $?"
git checkout -- bench/agent-session/baselines
node bench/agent-session/affordance-gate.mjs --action select --out /tmp/plan5-after/affordance-select --compare /tmp/plan5-baselines/affordance-select | grep -E "^(SAME|DIFF|PASS)"
node bench/agent-session/affordance-gate.mjs --action find --out /tmp/plan5-after/affordance-find --compare /tmp/plan5-baselines/affordance-find | grep -E "^(SAME|DIFF|PASS)"
node bench/agent-session/affordance-gate.mjs --action marks --out /tmp/plan5-after/affordance-marks | grep -v side-by-side
npm run bench:selection
for a in hover hint redact; do node bench/agent-session/affordance-gate.mjs --action $a | grep -v side-by-side; done
git checkout -- bench/agent-session/baselines
git status --short
```
Expected: `PASS feel gate: zero pixel diff`, `feel exit 0`; seven `SAME` lines and two `PASS … every screenshot matches` lines; the marks report `[["marks-rows-painted-after",0,null],["marks-after-equals-before",true,null]]`; `PASS selection survived N repaints`; three JSON report lines for hover/hint/redact (these are side-by-side only, never diffed); an empty `git status`.

- [ ] **Step 4: Agent gates**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal"
export GOTOOLCHAIN=auto
npm run bench:agent:gate 2>&1 | tail -3
npm run bench:agent:scroll 2>&1 | tail -3
git status --short
```
Expected: `PASS agent-session gate` and the scroll gate's `PASS` line; if the gate fails only in the reopen row because Go cannot build, write `not run: <the Go error line>` for that row and quote every other line. Delete nothing under `bench/results` (gitignored).

---

### Task 12: Push and report

- [ ] **Step 1: Final checks and push**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --short
git log --oneline origin/development..HEAD
git push -u origin terminal/plan-5-highlights-marks
```
Expected: clean status; eleven commits (Tasks 0–10); the push prints the new branch. Do not open or merge a pull request unless the user asks.

- [ ] **Step 2: Completion report (post it as your final message)**

The report has these sections, each gate with the exact line it printed or `not run: <reason>`:

1. Branch, head commit, commit list.
2. Gates: `check:boundaries`; each unit suite's `Test Files`/`Tests` lines against Task 0's `counts.txt`; frontend typecheck, lint summary line, vitest lines; `bench:feel` against the Task 0 baseline; `bench:affordances` select and find (`SAME`/`PASS` lines) and marks (report line); `bench:selection`; `bench:agent:gate`; `bench:agent:scroll`; the A/B table (six rows, two range lines) and the profile's highlight lines.
3. Design decisions that differ from the roadmap text, with evidence: decorations stay (Design decision 3); find keeps whole-row paint (4, 5).
4. Anything that deviated from this plan and why.
5. Real-app checklist for the user (`not run: no display in the cloud session` for you). On macOS, from the repo root with a scrubbed environment (`env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT npm run tauri:dev`, per `RUN_APP_COMMANDS.md`):
   - Settings → Terminal highlights → Add highlight → type `error`, colour Red. Open a Claude Code session and ask it to print the word "Error" and "error"; both are tinted red, including inside Claude's grey user-message band; the tint follows the word when the window is narrowed (rewrap) and while Claude keeps streaming.
   - Toggle `.*` and type `(`: the alert appears and nothing in the terminal changes; fix it to `err(or)?`: `err` and `error` tint, `ERROR` does not.
   - Press Cmd+F, search a word on screen: hit rows tint exactly as before; press Enter: the current row gets the thin outline. Drag a selection across a hit row: the selection band is on top of the find tint.
   - With `error` marked and a find for a word on the same row as `error`: selection > current hit outline > find tint > red mark, from top to bottom.
   - Park the pane (switch session) and edit the highlight; switch back: the pane shows the new colour.
   - Remove every highlight: nothing stays tinted.
