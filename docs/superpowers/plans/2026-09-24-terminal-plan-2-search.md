# Terminal Plan 2 — Search That Keeps Up, Smarter Search — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The terminal find bar picks up matching output while Claude is still writing (no retyping, no rescanning history), ignores case unless the query has a capital, offers a regex toggle, and keeps next/previous anchored on the current hit while output streams — and, found while writing this plan, it finds text in Claude Code panes and on the live screen at all.

**Architecture:** `vt-core` gets a `FindSession` kept by the caller and advanced by `TerminalCore::find_update(&mut session, budget_bytes)`: settled history (completed rows up to the last row that ends a line) is scanned once, oldest first, from a `scanned_to` content offset, and never again; the unsettled tail plus the live screen is re-searched only when `generation()` changed; hits are content byte ranges that re-resolve to stable rows through the row index at `find_results` time, so trims and rewraps need no rescan. `vt-wasm` swaps `find_step`/`find_is_complete` for `find_update`/`find_export`/`find_history_bytes_scanned`; `@operator/terminal-core` exposes `findUpdate`/`findResults(id)`; the find bar calls `findUpdate` on every paint while open, refetches results only when something changed, re-anchors the current hit by (stable row, byte), scrolls to the hit's row through a new `DomBlockRenderer.scrollToRow`, and gains a `.*` regex toggle.

**Tech Stack:** Rust 1.96.0 (`vt-core`, `vt-wasm`, `vt-host`; `memchr`, `regex-automata` 0.4.18 `meta::Regex`), wasm-bindgen 0.2.127, TypeScript 5.9 + vitest 4 (jsdom), Playwright 1.60 benches, Go 1.25.7 (pty-host tests), Node ≥ 20.

**Spec:** `docs/terminal/2026-09-24-terminal-roadmap-design.md` — "Plan 2 — Search that keeps up, smarter search (§1.7, §3.12, §2.6)" and "Rules every plan obeys". Survey entries: `docs/terminal/2026-09-19-terminal-reference-survey.md` §1.7 (line 626), §2.6 (line 1521), §3.12 (line 2488). `TERMINAL.md` (repo root) must be read end to end before Task 1 — §2 (model, snapshot/export layout), §3 (hard rules, product independence), §6 (verify-and-ship recipe).

---

## Global Constraints

- No comments in new code — Rust, TypeScript, CSS, scripts (`TERMINAL.md` §3 rule 3; the user's global instruction). Existing comments may be corrected only if they become false.
- Commit with explicit paths only: `git add <path> …` / `git rm <path>`. Never `git add -A`, `git add .`, `git commit -a`, or `git stash`.
- Work on branch `terminal/plan-2-search` cut from `origin/development`. Never commit to `master` or `development`, never merge, never bump a version.
- End every commit message with the `Co-Authored-By:` trailer your harness gives you.
- `packages/terminal` stays product-independent (`TERMINAL.md` §3 rule 1): nothing under `crates/` or `ts/` names Operator. The only Operator-side edit is one string in `frontend/src/renderer/components/BlockTerminal.tsx`.
- No file under `packages/terminal` may exceed 600 lines (`scripts/check-boundaries.mjs:42`, `LINE_LIMIT = 600`). `crates/vt-wasm/src/lib.rs` is at exactly 600 today; `dom-block-renderer.ts` is at 585; `find-bar.test.ts` is at 468 — new find-bar tests go in a new file.
- Cite `file:line` or write "not known" in every doc you write. Numbers you report come from a command you ran in this session.
- References: Ghostty (MIT), Alacritty (Apache-2.0/MIT), xterm.js (MIT) — behaviour may be followed. This plan adapts **no** reference code (behaviour only: Ghostty `src/terminal/search/active.zig:11-19` re-searches only the mutable area; Alacritty `alacritty_terminal/src/term/search.rs:39-40` smart case), so no attribution file is added. Never copy Kitty (GPL-3.0) or Warp (AGPL-3.0) code. You do not need to read any reference repository for this plan.
- A `vt-core` change rebuilds both wasm artifacts (`npm run build:wasm -- --force` for the renderer, `cargo build --release -p vt-host --target wasm32-unknown-unknown` for the committed `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`) and runs the pty-host Go tests (`TERMINAL.md` §6).
- `npm run bench:feel` must show zero pixel difference from pixels recorded in the same environment on the base commit (Task 0 Step 7 explains why the committed baselines are not usable in the cloud).
- Do not edit `frontend/src/renderer/i18n/*.json`; new copy uses `t(key, { defaultValue })` like its siblings (`BlockTerminal.tsx:509-514`).
- Toolchain pins: `rustc 1.96.0` (`packages/terminal/rust-toolchain.toml`), `wasm-bindgen 0.2.127` exactly (`scripts/build-wasm.mjs:22`), Go `1.25.7` (`backend/go.mod:3`).

## Review Focus

1. **Claude Code panes and text still on the screen** — every Claude Code session has zero OSC 133 marks (`TERMINAL.md` §5 "What a parked pane still costs"), so `BlockGrid` is empty and today's `FindCursor` finds nothing (verified: 0 hits for "the" on `claude-long-50k`); a person expects the bar to find what they can see. Pinned by `every_line_of_a_session_without_marks_is_searched` and `a_block_that_reaches_into_the_screen_is_searched` (Task 1), `find.test.ts` "searches a session without block marks" (Task 3), `find-bar.incremental.test.ts` "finds text in a session that has no block marks" (Task 4).
2. **A half-typed pattern with the regex toggle on** (`line [0-`) — must not throw or wedge the bar; it shows "No matches", marks the input `aria-invalid`, and recovers on the next keystroke. Pinned by "reads the query as a regular expression while the toggle is pressed" (Task 4).
3. **Zero-width and empty patterns** (`x*`, `^`, empty string) — must terminate and yield no empty hits. Pinned by `a_zero_width_pattern_finds_nothing_and_completes` (Task 1) and the `find.rs` unit tests `a_zero_width_pattern_yields_only_non_empty_hits`, `an_empty_query_finds_nothing`.
4. **Scrollback trimmed at the row cap while the bar is open** — hits in the trimmed rows disappear, the rest keep their stable rows, nothing panics. Pinned by `hits_keep_their_stable_rows_across_a_trim` (Task 1).
5. **A width change (rewrap) while the bar is open** — every hit still lands on its text. Pinned by `a_rewrap_keeps_every_hit_on_its_text` (Task 1).

---

## Facts checked while writing this plan (2026-09-24, `origin/development` @ `20bf1e58c`)

Read these before starting; several differ from the survey.

- `crates/vt-core/src/find.rs:15-18` `FindQuery::{Literal, Regex}`; `:50-59` `FindCursor`; `:107` `step(budget_blocks)`; `:124-144` `results`/`is_complete`/`cancel`/`next_block`/`into_parts`. The cursor walks `BlockGrid` blocks (`:112`) and searches a block only when **all** its rows are completed history: `block_byte_range` (`:194-204`) returns `None` when the block's last row is still on the screen. A core with no OSC 133 marks has an empty `BlockGrid` (the "one synthetic block" exists only at export, `crates/vt-core/src/grid.rs:196-214`), so the old find returns **nothing** in Claude Code panes and never searches screen rows. Verified with a scratch test: 20 lines, 5-row screen, markless → 0 hits; the same inside an open block → 0 hits; `claude-long-50k` → 0 hits.
- The old search also matched across hard row breaks: rows are stored back to back with no terminator (`crates/vt-core/src/scrollback.rs` test `no_terminator_byte_is_written`), and `search_block` searched a block's concatenated bytes.
- `row_for_offset` (`find.rs:209-216`) is a linear scan of every row per hit.
- `crates/vt-core/src/lib.rs:39` re-exports `FindCursor, FindMatch, FindQuery`; `:443-468` `find`/`find_with_state`.
- `crates/vt-wasm/src/lib.rs:5` imports them; `:38-41` session fields; `:463-553` `find_open`/`find_step`/`find_results_ptr`/`find_results_len`/`find_is_complete`/`find_cancel`; `:582-600` its own `struct FindSession`. `find_step` re-flattens every result on every step. `find_cancel` pushes an id onto the free list without removing the session, so cancelling twice pushes it twice. `crates/vt-wasm/src/export.rs:13` `FIND_MATCH_WORDS = 5`.
- `ts/core/src/terminal-core.ts:38-40` `FIND_MATCH_WORDS = 5`, `FIND_STEP_BUDGET = 1000`; `:383-436` `findOpen`/`findStep`/`findResults()`/`findIsComplete`/`findCancel`. `ts/core/src/types.ts:27-32` `FindMatch { blockId, row, byteRangeStart, byteRangeEnd }`. `ts/core/src/index-browser.ts:16` exports the type, `:75` exports `FIND_STEP_BUDGET`.
- `ts/renderer-dom/src/find-bar.ts:237-254` `openSession` calls `core.findOpen(query, false)` (`:245`) once per keystroke; `runStep` (`:195-230`) steps until complete and then stops for good, so new output is never searched. On every repaint (`:326-329`) it decodes every block (`refreshBlocks`, `:180-182`) and runs two `querySelector` calls per hit (`applyHighlights`, `:125-162`). Next/previous (`walk`, `:301-314`) already moves an index through the results array and calls `host.scrollToBlock(blockId)` — which, in a Claude Code pane, scrolls to the one synthetic block that holds the whole transcript.
- **Directional lazy DFAs (survey §2.6, Alacritty `search.rs:34-137`) are not needed**: next/previous is an index step through a sorted array, O(1), and the incremental session never rescans. They are left out.
- Callers of the find API: `ts/react/src/TerminalSurface.tsx:173-183` (the bar), `bench/find.bench.ts:2,43-62` + `bench/harness.ts:150-167` (the `find-500k` scenario, budget 100 ms p95 and sensitivity ≥ 1.5× in `bench/gate.mjs:41,61-72`), `README.md:11-18`. The pty-host (`vt-host`, Go `vtwasm`) never calls find. `vt_host.wasm` still changes bytes when `find.rs` changes (measured in one directory: 316,867 → 316,814 bytes), so it is rebuilt and committed (Task 6).
- `TerminalStrings` objects are built in full by `ts/core/src/types.ts:207-229` (`defaultStrings`), `ts/renderer-dom/src/palette.test.ts:5-26`, `ts/renderer-dom/src/jump-to-bottom.test.ts:5-26` and `frontend/src/renderer/components/BlockTerminal.tsx:495-525`. `ts/renderer-dom/tsconfig.json` compiles test files, so adding a key breaks `npm run build:ts` until all four are updated.
- `ts/renderer-dom/src/styles.ts` must be byte-identical to `styles.css` (`styles-parity.test.ts:8-12`). `.terminal-find-input:focus-visible` is at line 507 of both.
- `claude-long-50k` fed at 120×40 in agent-TUI + grapheme mode: 60,097 history rows but only 341,367 bytes of history text (the recording is mostly short numbered lines), so a full rescan there already costs ~1–4 ms; the perf check reports it honestly rather than inventing a bigger buffer.

## File map

| File | Change | Responsibility |
|---|---|---|
| `packages/terminal/crates/vt-core/src/find.rs` | rewrite | `FindQuery` (smart case, escaping, regex), `FindSession` (incremental scan, screen re-search, result resolution), haystack/scan helpers + unit tests |
| `packages/terminal/crates/vt-core/src/lib.rs` | modify `:39`, `:443-468` | re-exports; `find_update`, `find_results`, private `find_view` |
| `packages/terminal/crates/vt-core/tests/find_session.rs` | create | integration tests (15) |
| `packages/terminal/crates/vt-core/tests/find.rs` | delete | cases moved into `find_session.rs` |
| `packages/terminal/crates/vt-wasm/src/lib.rs` | modify `:5`, `:463-553`, `:581-600` | wasm exports over `FindSession` |
| `packages/terminal/crates/vt-wasm/src/export.rs` | modify `:13` | `FIND_MATCH_WORDS = 6` |
| `packages/terminal/ts/renderer-dom/src/scroll-tracker.ts` | modify (before `:102`) | `scrollToRow` |
| `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` | modify (before `:245`) | `scrollToRow` wrapper |
| `packages/terminal/ts/renderer-dom/src/dom-block-renderer.scroll.test.ts` | append | `scrollToRow` test |
| `packages/terminal/ts/core/src/terminal-core.ts` | modify `:14-28`, `:38-40`, `:390-436` | `findUpdate`, `findResults(id)`, `findHistoryBytesScanned` |
| `packages/terminal/ts/core/src/types.ts` | modify `:27-32`, `:199`, `:223` | `FindMatch`, `FindUpdate`, `findRegexLabel` |
| `packages/terminal/ts/core/src/index-browser.ts` | modify `:16`, `:75` | exports |
| `packages/terminal/ts/core/src/find.test.ts` | rewrite | core binding tests |
| `packages/terminal/bench/find.bench.ts`, `bench/harness.ts` | modify | `find-500k` on the new API |
| `packages/terminal/ts/renderer-dom/src/find-bar.ts` | rewrite | incremental pump, anchoring, regex toggle, row scrolling |
| `packages/terminal/ts/renderer-dom/src/find-bar.incremental.test.ts` | create | streaming / anchoring / regex / smart-case / markless tests |
| `packages/terminal/ts/renderer-dom/src/styles.css`, `styles.ts` | modify after `:509` | `.terminal-find-regex` |
| `packages/terminal/ts/renderer-dom/src/palette.test.ts`, `jump-to-bottom.test.ts` | modify `:22` | `findRegexLabel` |
| `packages/terminal/ts/react/src/TerminalSurface.tsx` | modify `:177` | pass `scrollToRow` |
| `frontend/src/renderer/components/BlockTerminal.tsx` | modify `:514` | `findRegexLabel` string |
| `packages/terminal/bench/find-update.mjs`, `packages/terminal/package.json` | create / modify | perf check script `bench:find-update` |
| `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` | rebuild | host mirror wasm |
| `packages/terminal/CHANGELOG.md`, `packages/terminal/README.md`, `TERMINAL.md`, survey, plain-language doc | modify | docs |

---

### Task 0: Cloud branch, toolchain, baseline

**Files:** none changed (except a temporary baseline recording that is restored in Step 7).

**Interfaces:** Produces the branch and the baseline numbers every later task compares against.

- [ ] **Step 1: Create the branch**

```bash
git fetch origin && git checkout -b terminal/plan-2-search origin/development
git log -1 --oneline
```
Expected: the last line is the tip of `origin/development` (it was `20bf1e58c` when this plan was written; a later commit is fine). If a file this plan edits no longer matches the line numbers quoted here, find the quoted text with `grep -n` and use that; report the drift in the completion report.

- [ ] **Step 2: Read the docs**

Read `TERMINAL.md` end to end, then `packages/terminal/CHANGELOG.md` "Unreleased", then the spec section named in the header. Do not start Task 1 before this.

- [ ] **Step 3: Rust toolchain and wasm-bindgen**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && rustup show active-toolchain && rustc --version && rustup target list --installed
```
Expected: `1.96.0-…` active (the `rust-toolchain.toml` installs it and `wasm32-unknown-unknown` on first use), `rustc 1.96.0 (…)`, and `wasm32-unknown-unknown` listed. If the target is missing: `rustup target add wasm32-unknown-unknown --toolchain 1.96.0`.

```bash
wasm-bindgen --version || cargo install wasm-bindgen-cli --version 0.2.127 --locked
wasm-bindgen --version
```
Expected: `wasm-bindgen 0.2.127` exactly (`scripts/build-wasm.mjs` refuses any other version).

- [ ] **Step 4: Node, Go, Playwright**

```bash
node --version && npm --version && (go version || echo "go missing")
```
Expected: Node `v20` or newer; Go `go1.25.x`. If Go is missing:
```bash
curl -sSL https://go.dev/dl/go1.25.7.linux-amd64.tar.gz -o /tmp/go.tgz && mkdir -p "$HOME/.local" && tar -C "$HOME/.local" -xzf /tmp/go.tgz && export PATH="$HOME/.local/go/bin:$PATH" && go version
```
(Every later Go command must be run with that `PATH` prefix in the same shell command if you had to install it.) If the download is blocked, write "Go: not run — <exact error>" in the report and continue; Task 6's Go step becomes not-run.

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm ci && npx playwright install --with-deps chromium
```
Expected: `npm ci` ends with `added … packages`; Playwright prints the chromium download or "is already installed". If `--with-deps` fails for lack of root, retry `npx playwright install chromium`; if that fails too, record "Playwright: not run — <exact error>" and every bench step becomes not-run with that reason.

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npm ci
```
Expected: `added … packages`. On failure record it; Task 4 Step 12 becomes not-run.

- [ ] **Step 5: Baseline Rust and TS gates**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test 2>&1 | grep -E "^test result|FAILED|panicked" | sort | uniq -c
```
Expected: no `FAILED`, no `panicked`; every line `test result: ok.`. Record the output.

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor completions react; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Test Files|Tests "); done && npm run check:boundaries
```
Expected: `build-wasm: vt_core.js, vt_core.d.ts, vt_core_bg.wasm, vt_core_bg.wasm.d.ts ready`; five pairs of `Test Files N passed` / `Tests N passed` (on the author's machine: core 8/79, renderer-dom 55/907, editor 13/129, completions 10/109, react 11/118); `boundary check passed` and `no ownership timers found`. Record the counts; any failure here is pre-existing and must be named in the report.

- [ ] **Step 6: Baseline host wasm hash**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo build --release -p vt-host --target wasm32-unknown-unknown && sha256sum target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
```
Expected: two hashes (they usually differ from each other — the committed binary was built on another machine). Record the first; Task 6 compares against it.

- [ ] **Step 7: Record feel baselines for this environment, then restore the committed ones**

The committed baselines under `bench/agent-session/baselines/` only match the machine and checkout they were recorded in: the author ran the unmodified tree from a copied directory on the same Mac and got `FAIL 25 screenshot(s) differ from the baseline`. So record this environment's pixels on the base commit into a scratch copy (with pixels recorded that way, the author's finished plan reported `PASS feel gate: zero pixel diff`):

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:feel -- --record && rm -rf /tmp/plan2-feel-base && cp -R bench/agent-session/baselines /tmp/plan2-feel-base && git checkout -- bench/agent-session/baselines && git status --short bench/agent-session/baselines
```
Expected: the record run prints one line per recorded screenshot; the final `git status --short` prints nothing (committed baselines restored). If it lists untracked files, delete exactly those paths with `git clean -fd -- bench/agent-session/baselines` and re-run `git status --short bench/agent-session/baselines` until it prints nothing. If Playwright is unavailable, write "bench:feel: not run — <reason>" and skip.

- [ ] **Step 8: No commit** — nothing to commit in Task 0.

---

### Task 1: `FindSession` in vt-core (and the vt-wasm Rust exports)

**Files:**
- Create: `packages/terminal/crates/vt-core/tests/find_session.rs`
- Delete: `packages/terminal/crates/vt-core/tests/find.rs`
- Rewrite: `packages/terminal/crates/vt-core/src/find.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs:39`, `:443-468`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs:5`, `:463-553`, `:581-600`
- Modify: `packages/terminal/crates/vt-wasm/src/export.rs:13`

**Interfaces:**
- Produces (Rust, re-exported from `vt_core`):
  - `pub struct FindQuery` with `pub fn literal(needle: &str) -> FindQuery` and `pub fn regex(pattern: &str) -> Result<FindQuery, Box<regex_automata::meta::BuildError>>`. Both are smart case: case-insensitive unless the text contains a char for which `char::is_uppercase` is true. An empty query matches nothing.
  - `pub struct FindSession` with `pub fn new(query: FindQuery) -> FindSession`, `len`, `is_empty`, `pub fn history_bytes_scanned(&self) -> u64`, `pub fn screen_scans(&self) -> u64`.
  - `#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)] pub struct FindUpdate { pub added: usize, pub removed: usize, pub complete: bool }`.
  - `#[derive(Clone, Copy, Debug, PartialEq, Eq)] pub struct FindMatch { pub block: BlockId, pub row: u64, pub end_row: u64, pub start: usize, pub end: usize }` — `row`/`end_row` are **stable** rows of the hit's first and last byte; `start` is a byte offset inside `row`'s text, `end` an exclusive byte offset inside `end_row`'s text (the same bytes `GridSnapshot::row_text` returns).
  - `TerminalCore::find_update(&self, session: &mut FindSession, budget_bytes: usize) -> FindUpdate` and `TerminalCore::find_results(&self, session: &FindSession) -> Vec<FindMatch>` (sorted by row, then start).
  - Removed: `FindCursor`, `TerminalCore::find`, `TerminalCore::find_with_state`.
- Produces (wasm, `WasmTerminalCore`): `find_open(query, is_regex) -> Result<u32, JsError>` (unchanged), `find_update(id, budget_bytes) -> Result<Vec<u32>, JsError>` returning `[added, removed, complete as 0|1]`, `find_export(id) -> Result<(), JsError>` filling the results buffer with 6 words per hit `[block_lo, block_hi, row, end_row, start, end]`, `find_results_ptr`/`find_results_len` (unchanged), `find_history_bytes_scanned(id) -> Result<f64, JsError>`, `find_cancel(id)` (no `Result`; forgets the session; idempotent). Removed: `find_step`, `find_is_complete`.

- [ ] **Step 1: Write the failing integration tests**

Create `packages/terminal/crates/vt-core/tests/find_session.rs`:

```rust
use vt_core::{FindMatch, FindQuery, FindSession, Limits, TerminalCore};

const ALL: usize = usize::MAX;

fn core(columns: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::new(columns, 10_000).unwrap();
    core.resize(columns, rows);
    core
}

fn feed_lines(core: &mut TerminalCore, lines: impl IntoIterator<Item = String>) {
    for line in lines {
        core.feed(format!("{line}\r\n").as_bytes());
    }
}

fn feed_block(core: &mut TerminalCore, text: &str) {
    core.feed(format!("\x1b]133;A\x07\x1b]133;C\x07{text}\x1b]133;D;0\x07\r\n").as_bytes());
}

fn search(core: &TerminalCore, query: FindQuery) -> (FindSession, Vec<FindMatch>) {
    let mut session = FindSession::new(query);
    assert!(core.find_update(&mut session, ALL).complete);
    let hits = core.find_results(&session);
    (session, hits)
}

fn refresh(core: &TerminalCore, session: &mut FindSession) -> Vec<FindMatch> {
    assert!(core.find_update(session, ALL).complete);
    core.find_results(session)
}

fn hit_text(core: &TerminalCore, hit: &FindMatch) -> String {
    let snapshot = core.snapshot().unwrap();
    let first = core.flat_row(hit.row).unwrap();
    let last = core.flat_row(hit.end_row).unwrap();
    let mut text = String::new();
    for flat in first..=last {
        let row = snapshot.row_text(flat);
        let from = if flat == first { hit.start } else { 0 };
        let to = if flat == last { hit.end } else { row.len() };
        text.push_str(&row[from..to]);
    }
    text
}

#[test]
fn every_line_of_a_session_without_marks_is_searched() {
    let mut core = core(40, 5);
    feed_lines(&mut core, (0..20).map(|index| format!("hello {index}")));
    let (_, hits) = search(&core, FindQuery::literal("hello"));
    assert_eq!(hits.len(), 20);
    for hit in &hits {
        assert_eq!(hit_text(&core, hit), "hello");
    }
}

#[test]
fn a_block_that_reaches_into_the_screen_is_searched() {
    let mut core = core(40, 5);
    core.feed(b"\x1b]133;A\x07\x1b]133;C\x07");
    feed_lines(&mut core, (0..20).map(|index| format!("hello {index}")));
    let (_, hits) = search(&core, FindQuery::literal("hello"));
    assert_eq!(hits.len(), 20);
    let block = core.snapshot().unwrap().blocks[0].id;
    assert!(hits.iter().all(|hit| hit.block == block));
}

#[test]
fn history_is_not_rescanned_when_output_arrives() {
    let mut core = core(40, 5);
    feed_lines(
        &mut core,
        (0..50).map(|index| format!("line {index} of text")),
    );
    let (mut session, hits) = search(&core, FindQuery::literal("line"));
    assert_eq!(hits.len(), 50);
    let scanned = session.history_bytes_scanned();
    let history_before = core.snapshot().unwrap().history_rows as usize;
    feed_lines(
        &mut core,
        (50..53).map(|index| format!("line {index} of text")),
    );
    let hits = refresh(&core, &mut session);
    assert_eq!(hits.len(), 53);
    let snapshot = core.snapshot().unwrap();
    let history_after = snapshot.history_rows as usize;
    let settled: usize = (history_before..history_after)
        .map(|flat| snapshot.row_text(flat).len())
        .sum();
    assert!(settled > 0);
    assert_eq!(session.history_bytes_scanned() - scanned, settled as u64);
    assert!(scanned > 10 * settled as u64);
}

#[test]
fn the_screen_is_searched_again_only_when_it_changes() {
    let mut core = core(40, 5);
    feed_lines(&mut core, ["one needle".to_string()]);
    let (mut session, _) = search(&core, FindQuery::literal("needle"));
    let scans = session.screen_scans();
    let quiet = core.find_update(&mut session, ALL);
    assert_eq!((quiet.added, quiet.removed), (0, 0));
    assert_eq!(session.screen_scans(), scans);
    core.feed(b"x");
    core.find_update(&mut session, ALL);
    assert_eq!(session.screen_scans(), scans + 1);
}

#[test]
fn a_hit_on_the_live_screen_follows_the_frame() {
    let mut core = core(40, 3);
    core.feed(b"status: idle");
    let (mut session, hits) = search(&core, FindQuery::literal("idle"));
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].row, core.stable_row(core.history_rows()));
    assert_eq!(hit_text(&core, &hits[0]), "idle");
    core.feed(b"\x1b[H\x1b[2Kstatus: busy");
    let update = core.find_update(&mut session, ALL);
    assert_eq!((update.added, update.removed), (0, 1));
    assert!(core.find_results(&session).is_empty());
    assert_eq!(session.history_bytes_scanned(), 0);
}

#[test]
fn a_match_across_the_scrollback_and_screen_boundary_is_one_hit() {
    let mut core = core(10, 2);
    core.feed(b"123456789NEEDLE\r\n");
    assert_eq!(core.history_rows(), 1);
    let (mut session, hits) = search(&core, FindQuery::literal("NEEDLE"));
    assert_eq!(hits.len(), 1);
    assert_eq!(
        (hits[0].row, hits[0].start, hits[0].end_row, hits[0].end),
        (0, 9, 1, 5)
    );
    assert_eq!(hit_text(&core, &hits[0]), "NEEDLE");
    core.feed(b"a\r\nb\r\n");
    let settled = refresh(&core, &mut session);
    assert_eq!(settled, hits);
    assert!(session.history_bytes_scanned() > 0);
}

#[test]
fn a_rewrap_keeps_every_hit_on_its_text() {
    let mut core = core(30, 3);
    feed_lines(
        &mut core,
        (0..40).map(|index| format!("entry {index} carries the needle word")),
    );
    let (mut session, hits) = search(&core, FindQuery::literal("needle"));
    assert_eq!(hits.len(), 40);
    core.resize(12, 3);
    let hits = refresh(&core, &mut session);
    assert_eq!(hits.len(), 40);
    for hit in &hits {
        assert_eq!(hit_text(&core, hit), "needle");
    }
}

#[test]
fn smart_case_ignores_case_only_for_a_query_without_capitals() {
    let mut core = core(40, 5);
    feed_lines(
        &mut core,
        ["Error one", "error two", "ERROR three"].map(String::from),
    );
    assert_eq!(search(&core, FindQuery::literal("error")).1.len(), 3);
    assert_eq!(search(&core, FindQuery::literal("Error")).1.len(), 1);
    assert_eq!(search(&core, FindQuery::regex("err.r").unwrap()).1.len(), 3);
    assert_eq!(search(&core, FindQuery::regex("ERR.R").unwrap()).1.len(), 1);
}

#[test]
fn a_query_without_capitals_folds_unicode_case() {
    let mut core = core(40, 5);
    feed_lines(&mut core, ["ÉCOLE ouverte".to_string()]);
    let (_, hits) = search(&core, FindQuery::literal("école"));
    assert_eq!(hits.len(), 1);
    assert_eq!(hit_text(&core, &hits[0]), "ÉCOLE");
}

#[test]
fn a_regex_reads_metacharacters_and_a_literal_does_not() {
    let mut core = core(40, 5);
    feed_lines(&mut core, ["a.c abc".to_string()]);
    let (_, literal) = search(&core, FindQuery::literal("a.c"));
    assert_eq!(literal.len(), 1);
    assert_eq!(hit_text(&core, &literal[0]), "a.c");
    assert_eq!(search(&core, FindQuery::regex("a.c").unwrap()).1.len(), 2);
}

#[test]
fn an_invalid_regex_is_an_error_not_a_panic() {
    assert!(FindQuery::regex("(unclosed").is_err());
}

#[test]
fn a_zero_width_pattern_finds_nothing_and_completes() {
    let mut core = core(40, 5);
    feed_lines(&mut core, ["abc".to_string(), "def".to_string()]);
    assert!(search(&core, FindQuery::regex("x*").unwrap()).1.is_empty());
    assert!(search(&core, FindQuery::regex("^").unwrap()).1.is_empty());
}

#[test]
fn the_budget_splits_the_first_scan_and_resumes() {
    let mut core = core(40, 2);
    feed_lines(
        &mut core,
        (0..100).map(|index| format!("line {index} of text")),
    );
    let mut session = FindSession::new(FindQuery::literal("line"));
    let first = core.find_update(&mut session, 64);
    assert!(!first.complete);
    let partial = core.find_results(&session).len();
    assert!(partial > 0 && partial < 100);
    let mut rounds = 0;
    while !core.find_update(&mut session, 64).complete {
        rounds += 1;
        assert!(rounds < 1_000);
    }
    assert_eq!(core.find_results(&session).len(), 100);
}

#[test]
fn hits_keep_their_stable_rows_across_a_trim() {
    let mut core = TerminalCore::with_limits(40, Limits::rows_only(6)).unwrap();
    core.resize(40, 2);
    for line in ["1", "2", "needle", "4"] {
        feed_block(&mut core, line);
    }
    let (mut session, hits) = search(&core, FindQuery::literal("needle"));
    assert_eq!(hits[0].row, 2);
    for line in ["5", "6", "7"] {
        feed_block(&mut core, line);
    }
    let hits = refresh(&core, &mut session);
    assert_eq!(core.first_stable_row(), 1);
    assert_eq!(hits[0].row, 2);
    assert_eq!(hit_text(&core, &hits[0]), "needle");
    for line in 8..20 {
        feed_block(&mut core, &line.to_string());
    }
    let update = core.find_update(&mut session, ALL);
    assert!(update.removed >= 1);
    assert!(core.find_results(&session).is_empty());
}

#[test]
fn a_hit_names_the_block_that_holds_it() {
    let mut core = core(40, 1);
    for text in ["alpha", "needle", "gamma"] {
        feed_block(&mut core, text);
    }
    let (_, hits) = search(&core, FindQuery::literal("needle"));
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].block, core.snapshot().unwrap().blocks[1].id);
}
```

- [ ] **Step 2: Delete the old integration test**

`tests/find.rs` uses `TerminalCore::find`, which this task removes. Its five cases live on in `find_session.rs` (literal → `every_line…`, budget/resume → `the_budget_splits…`, invalid regex → `an_invalid_regex…`, regex across blocks → `a_regex_reads…`, stable rows across a trim → `hits_keep_their_stable_rows…`).

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && git rm crates/vt-core/tests/find.rs
```
Expected: `rm 'packages/terminal/crates/vt-core/tests/find.rs'`.

- [ ] **Step 3: Run the new tests and watch them fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo test -p vt-core --test find_session 2>&1 | grep -E "^error" | head -5
```
Expected: compile errors, including `error[E0432]: unresolved import` naming `vt_core::FindSession`.

- [ ] **Step 4: Rewrite `crates/vt-core/src/find.rs`**

Replace the whole file with:

```rust
use std::ops::Range;

use memchr::memmem::Finder;
use regex_automata::meta::{BuildError, Regex};
use regex_automata::util::syntax;
use regex_automata::Input;

use crate::block::{BlockId, BlockRecord};
use crate::content::Content;
use crate::grid::export_screen_row;
use crate::row_index::{RowIndex, RowRange};
use crate::screen::ScreenGrid;

const META_CHARACTERS: &str = "\\.+*?()|[]{}^$#&-~";

#[derive(Clone)]
pub struct FindQuery {
    matcher: Matcher,
}

#[derive(Clone)]
enum Matcher {
    Empty,
    Literal(Finder<'static>),
    Regex(Regex),
}

impl FindQuery {
    pub fn literal(needle: &str) -> Self {
        let matcher = if needle.is_empty() {
            Matcher::Empty
        } else if has_uppercase(needle) {
            Matcher::Literal(Finder::new(needle.as_bytes()).into_owned())
        } else {
            build_regex(&escape(needle), true).map_or_else(
                |_| Matcher::Literal(Finder::new(needle.as_bytes()).into_owned()),
                Matcher::Regex,
            )
        };
        Self { matcher }
    }

    pub fn regex(pattern: &str) -> Result<Self, Box<BuildError>> {
        if pattern.is_empty() {
            return Ok(Self {
                matcher: Matcher::Empty,
            });
        }
        build_regex(pattern, !has_uppercase(pattern)).map(|regex| Self {
            matcher: Matcher::Regex(regex),
        })
    }

    fn next_match(&self, haystack: &[u8], span: Range<usize>) -> Option<Range<usize>> {
        match &self.matcher {
            Matcher::Empty => None,
            Matcher::Literal(finder) => {
                let offset = finder.find(&haystack[span.clone()])?;
                let start = span.start + offset;
                Some(start..start + finder.needle().len())
            }
            Matcher::Regex(regex) => regex
                .find_iter(Input::new(haystack).span(span))
                .find(|found| !found.is_empty())
                .map(|found| found.range()),
        }
    }
}

fn has_uppercase(text: &str) -> bool {
    text.chars().any(char::is_uppercase)
}

fn escape(text: &str) -> String {
    let mut escaped = String::with_capacity(text.len() * 2);
    for ch in text.chars() {
        if META_CHARACTERS.contains(ch) {
            escaped.push('\\');
        }
        escaped.push(ch);
    }
    escaped
}

fn build_regex(pattern: &str, case_insensitive: bool) -> Result<Regex, Box<BuildError>> {
    Regex::builder()
        .syntax(
            syntax::Config::new()
                .case_insensitive(case_insensitive)
                .multi_line(true),
        )
        .build(pattern)
        .map_err(Box::new)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FindMatch {
    pub block: BlockId,
    pub row: u64,
    pub end_row: u64,
    pub start: usize,
    pub end: usize,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FindUpdate {
    pub added: usize,
    pub removed: usize,
    pub complete: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct ScreenHit {
    row: u64,
    start: usize,
    end_row: u64,
    end: usize,
}

pub struct FindSession {
    query: FindQuery,
    history: Vec<Range<u64>>,
    started: bool,
    scanned_from: u64,
    scanned_to: u64,
    bytes_scanned: u64,
    screen: Vec<ScreenHit>,
    screen_generation: Option<u64>,
    screen_scans: u64,
}

pub(crate) struct FindView<'a> {
    pub content: &'a Content,
    pub rows: &'a RowIndex,
    pub screen: &'a ScreenGrid,
    pub generation: u64,
    pub first_stable_row: u64,
}

impl FindSession {
    pub fn new(query: FindQuery) -> Self {
        Self {
            query,
            history: Vec::new(),
            started: false,
            scanned_from: 0,
            scanned_to: 0,
            bytes_scanned: 0,
            screen: Vec::new(),
            screen_generation: None,
            screen_scans: 0,
        }
    }

    pub fn len(&self) -> usize {
        self.history.len() + self.screen.len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn history_bytes_scanned(&self) -> u64 {
        self.bytes_scanned
    }

    pub fn screen_scans(&self) -> u64 {
        self.screen_scans
    }

    pub(crate) fn update(&mut self, view: &FindView<'_>, budget_bytes: usize) -> FindUpdate {
        let mut update = FindUpdate::default();
        let completed = view.rows.completed();
        let settled = settled_rows(completed);
        let history_start = completed
            .front()
            .map_or(view.rows.open_start(), |row| row.start);
        let settled_end = if settled == 0 {
            history_start
        } else {
            completed[settled - 1].end
        };
        if !self.started || history_start < self.scanned_from || settled_end < self.scanned_to {
            update.removed += self.history.len();
            self.history.clear();
            self.started = true;
            self.scanned_from = history_start;
            self.scanned_to = history_start;
        }
        if history_start > self.scanned_from {
            let dropped = self
                .history
                .partition_point(|hit| hit.start < history_start);
            self.history.drain(..dropped);
            update.removed += dropped;
            self.scanned_from = history_start;
            self.scanned_to = self.scanned_to.max(history_start);
        }
        if self.scanned_to < settled_end {
            update.added += self.scan_history(view, settled, budget_bytes);
        }
        if self.screen_generation != Some(view.generation) {
            let fresh = self.search_screen(view, settled);
            if fresh != self.screen {
                update.removed += self.screen.len();
                update.added += fresh.len();
                self.screen = fresh;
            }
            self.screen_generation = Some(view.generation);
            self.screen_scans += 1;
        }
        update.complete = self.scanned_to >= settled_end;
        update
    }

    fn scan_history(&mut self, view: &FindView<'_>, settled: usize, budget_bytes: usize) -> usize {
        let completed = view.rows.completed();
        let first = completed.partition_point(|row| row.start < self.scanned_to);
        if first >= settled {
            self.scanned_to = completed[settled - 1].end;
            return 0;
        }
        let budget = budget_bytes.max(1) as u64;
        let from = completed[first].start;
        let mut last = first;
        while last < settled {
            let row = &completed[last];
            last += 1;
            if !row.wrapped && row.end - from >= budget {
                break;
            }
        }
        let to = completed[last - 1].end;
        let bytes = view.content.copy_range(from, to);
        let mut haystack = Haystack::default();
        for row in completed.range(first..last) {
            let slice = &bytes[(row.start - from) as usize..(row.end - from) as usize];
            haystack.push(slice, row.start, row.wrapped);
        }
        haystack.close();
        let before = self.history.len();
        scan(&self.query, &haystack, |found| {
            if let Some((head, tail)) = haystack.locate(&found) {
                let start = head.key + (found.start - head.at) as u64;
                let end = tail.key + (found.end - tail.at) as u64;
                self.history.push(start..end);
            }
        });
        self.bytes_scanned += to - from;
        self.scanned_to = to;
        self.history.len() - before
    }

    fn search_screen(&self, view: &FindView<'_>, settled: usize) -> Vec<ScreenHit> {
        let completed = view.rows.completed();
        let mut haystack = Haystack::default();
        for (index, row) in completed.iter().enumerate().skip(settled) {
            let bytes = view.content.copy_range(row.start, row.end);
            haystack.push(&bytes, view.first_stable_row + index as u64, row.wrapped);
        }
        for row in 0..view.screen.content_rows() {
            let exported = export_screen_row(view.screen, row);
            let stable = view.first_stable_row + (completed.len() + row) as u64;
            haystack.push(&exported.bytes, stable, exported.wrapped);
        }
        haystack.close();
        let mut hits = Vec::new();
        scan(&self.query, &haystack, |found| {
            if let Some((head, tail)) = haystack.locate(&found) {
                hits.push(ScreenHit {
                    row: head.key,
                    start: found.start - head.at,
                    end_row: tail.key,
                    end: found.end - tail.at,
                });
            }
        });
        hits
    }

    pub(crate) fn results(&self, view: &FindView<'_>, blocks: &[BlockRecord]) -> Vec<FindMatch> {
        let completed = view.rows.completed();
        let mut out = Vec::with_capacity(self.len());
        for hit in &self.history {
            let first = completed.partition_point(|row| row.end <= hit.start);
            let last = completed.partition_point(|row| row.end < hit.end);
            let (Some(head), Some(tail)) = (completed.get(first), completed.get(last)) else {
                continue;
            };
            if hit.start < head.start || hit.end < tail.start {
                continue;
            }
            out.push(FindMatch {
                block: block_at(blocks, first),
                row: view.first_stable_row + first as u64,
                end_row: view.first_stable_row + last as u64,
                start: (hit.start - head.start) as usize,
                end: (hit.end - tail.start) as usize,
            });
        }
        for hit in &self.screen {
            let Some(flat) = hit.row.checked_sub(view.first_stable_row) else {
                continue;
            };
            out.push(FindMatch {
                block: block_at(blocks, flat as usize),
                row: hit.row,
                end_row: hit.end_row,
                start: hit.start,
                end: hit.end,
            });
        }
        out
    }
}

fn settled_rows(completed: &std::collections::VecDeque<RowRange>) -> usize {
    let mut settled = completed.len();
    while settled > 0 && completed[settled - 1].wrapped {
        settled -= 1;
    }
    settled
}

fn block_at(blocks: &[BlockRecord], flat: usize) -> BlockId {
    let index = blocks.partition_point(|block| block.first_row as usize <= flat);
    index
        .checked_sub(1)
        .and_then(|found| blocks.get(found))
        .or_else(|| blocks.first())
        .map_or(0, |block| block.id)
}

struct Piece {
    at: usize,
    len: usize,
    key: u64,
}

#[derive(Default)]
struct Haystack {
    bytes: Vec<u8>,
    lines: Vec<Range<usize>>,
    pieces: Vec<Piece>,
    open: Option<usize>,
}

impl Haystack {
    fn push(&mut self, piece: &[u8], key: u64, continues: bool) {
        let at = self.bytes.len();
        if self.open.is_none() {
            self.open = Some(at);
        }
        self.bytes.extend_from_slice(piece);
        self.pieces.push(Piece {
            at,
            len: piece.len(),
            key,
        });
        if !continues {
            self.close();
        }
    }

    fn close(&mut self) {
        if let Some(start) = self.open.take() {
            self.lines.push(start..self.bytes.len());
            self.bytes.push(b'\n');
        }
    }

    fn locate(&self, found: &Range<usize>) -> Option<(&Piece, &Piece)> {
        let head = self
            .pieces
            .partition_point(|piece| piece.at + piece.len <= found.start);
        let tail = self
            .pieces
            .partition_point(|piece| piece.at + piece.len < found.end);
        Some((self.pieces.get(head)?, self.pieces.get(tail)?))
    }
}

fn scan(query: &FindQuery, haystack: &Haystack, mut visit: impl FnMut(Range<usize>)) {
    let bytes = &haystack.bytes;
    let mut from = 0;
    while from < bytes.len() {
        let Some(found) = query.next_match(bytes, from..bytes.len()) else {
            return;
        };
        let line = haystack
            .lines
            .partition_point(|bounds| bounds.end < found.start);
        let Some(bounds) = haystack.lines.get(line).cloned() else {
            return;
        };
        if found.end <= bounds.end {
            from = found.end;
            visit(found);
            continue;
        }
        if found.start < bounds.end {
            if let Some(inner) = query.next_match(bytes, found.start..bounds.end) {
                from = inner.end;
                visit(inner);
                continue;
            }
        }
        from = bounds.end + 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn found(query: &FindQuery, lines: &[&str]) -> Vec<String> {
        let mut haystack = Haystack::default();
        for (index, line) in lines.iter().enumerate() {
            haystack.push(line.as_bytes(), index as u64, false);
        }
        let mut out = Vec::new();
        scan(query, &haystack, |range| {
            out.push(String::from_utf8(haystack.bytes[range].to_vec()).unwrap());
        });
        out
    }

    #[test]
    fn every_meta_character_is_literal_in_a_literal_query() {
        for ch in META_CHARACTERS.chars() {
            let needle = format!("a{ch}b");
            let hits = found(
                &FindQuery::literal(&needle),
                &[&format!("x {needle} y"), "axb"],
            );
            assert_eq!(hits, vec![needle.clone()], "meta character {ch:?}");
        }
    }

    #[test]
    fn a_match_that_crosses_a_line_is_searched_again_inside_the_line() {
        let query = FindQuery::regex("x[^y]*z").unwrap();
        assert_eq!(found(&query, &["ab xz", "zz"]), vec!["xz".to_string()]);
    }

    #[test]
    fn a_match_that_starts_on_the_separator_is_skipped() {
        let query = FindQuery::regex(r"\s+b").unwrap();
        assert!(found(&query, &["a", "b c"]).is_empty());
    }

    #[test]
    fn a_zero_width_pattern_yields_only_non_empty_hits() {
        let query = FindQuery::regex("x*").unwrap();
        assert!(found(&query, &["abc"]).is_empty());
        assert_eq!(found(&query, &["axxb"]), vec!["xx".to_string()]);
    }

    #[test]
    fn an_empty_query_finds_nothing() {
        assert!(found(&FindQuery::literal(""), &["abc"]).is_empty());
        assert!(found(&FindQuery::regex("").unwrap(), &["abc"]).is_empty());
    }

    #[test]
    fn anchors_match_at_every_line() {
        let query = FindQuery::regex("^b").unwrap();
        assert_eq!(found(&query, &["ab", "bc", "b"]).len(), 2);
    }

    #[test]
    fn a_soft_wrapped_line_is_one_line_to_the_search() {
        let mut haystack = Haystack::default();
        haystack.push(b"hello nee", 0, true);
        haystack.push(b"dle there", 1, false);
        let mut hits = Vec::new();
        scan(&FindQuery::literal("needle"), &haystack, |range| {
            let (head, tail) = haystack.locate(&range).unwrap();
            hits.push((
                head.key,
                range.start - head.at,
                tail.key,
                range.end - tail.at,
            ));
        });
        assert_eq!(hits, vec![(0, 6, 1, 3)]);
    }
}
```

How it works, for the reviewer (not for the code): a history batch copies whole logical lines from `Content`, pushes each row as a `Piece` keyed by its content offset, and closes a line (appending a `\n` separator the query can never cross silently) after every row whose `wrapped` flag is false. `scan` restarts a match that crosses a separator inside its own line (restricted span), so a greedy regex cannot hide a match that is wholly inside the line; a match that starts on a separator is skipped. The screen haystack is the unsettled tail of history (rows after the last row that ends a line — at most one soft-wrapped logical line) followed by the screen rows, keyed by stable row. `META_CHARACTERS` is the set `regex-syntax`'s `is_meta_character` escapes.

- [ ] **Step 5: Wire it into `TerminalCore` (`crates/vt-core/src/lib.rs`)**

At `lib.rs:39` replace

```rust
pub use find::{FindCursor, FindMatch, FindQuery};
```

with

```rust
pub use find::{FindMatch, FindQuery, FindSession, FindUpdate};
```

At `lib.rs:443-468` replace the two methods

```rust
    pub fn find(&self, query: find::FindQuery) -> find::FindCursor<'_> {
        find::FindCursor::new(
            self.parser.grid(),
            self.parser.rows(),
            self.parser.content(),
            query,
        )
    }

    pub fn find_with_state(
        &self,
        query: find::FindQuery,
        next_block: usize,
        results: Vec<find::FindMatch>,
        complete: bool,
    ) -> find::FindCursor<'_> {
        find::FindCursor::with_state(
            self.parser.grid(),
            self.parser.rows(),
            self.parser.content(),
            query,
            next_block,
            results,
            complete,
        )
    }
```

with

```rust
    fn find_view(&self) -> find::FindView<'_> {
        find::FindView {
            content: self.parser.content(),
            rows: self.parser.rows(),
            screen: self.parser.screen(),
            generation: self.parser.generation(),
            first_stable_row: self.parser.first_stable_row(),
        }
    }

    pub fn find_update(&self, session: &mut FindSession, budget_bytes: usize) -> FindUpdate {
        session.update(&self.find_view(), budget_bytes)
    }

    pub fn find_results(&self, session: &FindSession) -> Vec<FindMatch> {
        let total = self.history_rows() + self.parser.screen().content_rows();
        let blocks = grid::export_blocks(self.parser.grid(), total, |_| true)
            .map(|(records, _)| records)
            .unwrap_or_default();
        session.results(&self.find_view(), &blocks)
    }
```

(`export_blocks` with `|_| true` names the trailing synthetic block whenever rows exist past the last closed block; a hit always sits on a row with bytes, so its id matches the snapshot's.)

- [ ] **Step 6: Run the vt-core tests**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo test -p vt-core --test find_session 2>&1 | tail -4 && cargo test -p vt-core --lib find:: 2>&1 | tail -3
```
Expected: `test result: ok. 15 passed; 0 failed` then `test result: ok. 7 passed; 0 failed`.

- [ ] **Step 7: Port vt-wasm to the session API**

`crates/vt-wasm/src/export.rs:13`: replace `pub const FIND_MATCH_WORDS: usize = 5;` with `pub const FIND_MATCH_WORDS: usize = 6;`.

`crates/vt-wasm/src/lib.rs:5`: replace `use vt_core::{FindCursor, FindMatch, FindQuery, TerminalCore};` with `use vt_core::{FindQuery, FindSession, TerminalCore};`.

Then replace everything from the line `    pub fn find_open(&mut self, query: &str, is_regex: bool) -> Result<u32, JsError> {` (line 463) up to, not including, the line `fn clock(now_ms: f64) -> u64 {`, and delete the old `struct FindSession` + `impl FindSession` at the end of the file (lines 582-600). This script does both and checks its anchors:

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && python3 - <<'PY'
from pathlib import Path
path = Path("crates/vt-wasm/src/lib.rs")
text = path.read_text()
start = text.index("    pub fn find_open(&mut self, query: &str, is_regex: bool) -> Result<u32, JsError> {")
end = text.index("fn clock(now_ms: f64) -> u64 {")
block = '''    pub fn find_open(&mut self, query: &str, is_regex: bool) -> Result<u32, JsError> {
        let parsed = if is_regex {
            FindQuery::regex(query).map_err(|err| JsError::new(&format!("invalid regex: {err}")))?
        } else {
            FindQuery::literal(query)
        };
        let id = if let Some(reused) = self.find_free_ids.pop() {
            reused
        } else {
            let id = self.find_next_id;
            self.find_next_id = self.find_next_id.wrapping_add(1).max(1);
            id
        };
        self.find_sessions.insert(id, FindSession::new(parsed));
        self.find_results.clear();
        Ok(id)
    }

    pub fn find_update(&mut self, id: u32, budget_bytes: usize) -> Result<Vec<u32>, JsError> {
        let session = self
            .find_sessions
            .get_mut(&id)
            .ok_or_else(|| JsError::new("unknown find session"))?;
        let update = self.core.find_update(session, budget_bytes);
        Ok(vec![
            u32::try_from(update.added).unwrap_or(u32::MAX),
            u32::try_from(update.removed).unwrap_or(u32::MAX),
            u32::from(update.complete),
        ])
    }

    pub fn find_export(&mut self, id: u32) -> Result<(), JsError> {
        let session = self
            .find_sessions
            .get(&id)
            .ok_or_else(|| JsError::new("unknown find session"))?;
        let hits = self.core.find_results(session);
        let mut flattened = Vec::with_capacity(hits.len() * FIND_MATCH_WORDS);
        for hit in &hits {
            flattened.push(hit.block as u32);
            flattened.push((hit.block >> 32) as u32);
            for word in [hit.row, hit.end_row, hit.start as u64, hit.end as u64] {
                flattened
                    .push(checked_u32_from_u64(word).map_err(|_| ExportError::FindOffsetOverflow)?);
            }
        }
        self.find_results = flattened;
        Ok(())
    }

    pub fn find_results_ptr(&self) -> *const u32 {
        self.find_results.as_ptr()
    }

    pub fn find_results_len(&self) -> usize {
        self.find_results.len()
    }

    pub fn find_history_bytes_scanned(&self, id: u32) -> Result<f64, JsError> {
        let session = self
            .find_sessions
            .get(&id)
            .ok_or_else(|| JsError::new("unknown find session"))?;
        Ok(session.history_bytes_scanned() as f64)
    }

    pub fn find_cancel(&mut self, id: u32) {
        if self.find_sessions.remove(&id).is_some() {
            self.find_free_ids.push(id);
        }
    }
}

'''
text = text[:start] + block + text[end:]
tail = text.index("struct FindSession {")
text = text[:tail].rstrip() + "\n"
path.write_text(text)
PY
wc -l crates/vt-wasm/src/lib.rs && grep -n "FindCursor\|find_step\|find_is_complete\|struct FindSession" crates/vt-wasm/src/lib.rs
```
Expected: `560 crates/vt-wasm/src/lib.rs` (±2), and the `grep` prints nothing. The struct field `find_sessions: HashMap<u32, FindSession>` (line 38) now names `vt_core::FindSession` through the import; no other line changes.

- [ ] **Step 8: Format, lint, full Rust tests**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo fmt && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test 2>&1 | grep -E "^test result|FAILED|panicked" | sort | uniq -c
```
Expected: clippy prints `Finished`, no warnings; every `test result: ok.`; no `FAILED`/`panicked`. (If clippy reports `result_large_err`, `build_regex` is not returning `Box<BuildError>` — fix it to match Step 4.)

- [ ] **Step 9: Commit**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && git add crates/vt-core/src/find.rs crates/vt-core/src/lib.rs crates/vt-core/tests/find_session.rs crates/vt-wasm/src/lib.rs crates/vt-wasm/src/export.rs && git commit -m "feat(terminal): incremental find session in vt-core

FindSession scans settled history once from a scanned_to offset and
re-searches the unsettled tail and the live screen only when the
generation changes. Hits are content byte ranges resolved to stable
rows at export, so a trim or rewrap needs no rescan. Smart case follows
Alacritty (search.rs:39-40). The old block walker searched nothing in a
markless (Claude Code) pane and no row still on the screen.

<Co-Authored-By trailer from your harness>"
```
Expected: one commit with 5 files changed plus the deletion staged in Step 2 (6 paths).

---

### Task 2: `DomBlockRenderer.scrollToRow`

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/scroll-tracker.ts` (insert before `updateStickiness(): void {`, line 102)
- Modify: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` (insert before `scrollToLatest(): void {`, line 245)
- Test: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.scroll.test.ts` (append)

**Interfaces:**
- Produces: `DomBlockRenderer.scrollToRow(row: number, align: "start" | "center" | "end"): boolean` — `row` is a **stable** row; scrolls so the row sits at the top/centre/bottom of the viewport, leaves stick-to-bottom, captures the scroll anchor, schedules a repaint; returns `false` (and does nothing) when the row is trimmed, not in a shown block, or the renderer is not mounted. Also `ScrollTracker.scrollToRow` with the same signature.

- [ ] **Step 1: Write the failing test**

Append to the end of `ts/renderer-dom/src/dom-block-renderer.scroll.test.ts` (the file already imports `createTerminalCore`, `DomBlockRenderer`, `font`, `feed`, `flushRepaint` and defines `scrollable()`):

```ts

describe("scrollToRow", () => {
	it("brings a far row into the rendered window and refuses a row it does not hold", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 20, limits: { rows: 1000, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 500; i += 1) feed(core, `line ${i}\r\n`);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		await flushRepaint();
		expect(container.querySelector('[data-terminal-row="10"]')).toBeNull();
		expect(renderer.scrollToRow(10, "center")).toBe(true);
		await flushRepaint();
		expect(container.querySelector('[data-terminal-row="10"]')?.textContent).toBe("line 10");
		expect(renderer.scrollToRow(100_000, "center")).toBe(false);
		renderer.dispose();
	});
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/renderer-dom" && npx vitest run src/dom-block-renderer.scroll.test.ts 2>&1 | grep -E "scrollToRow is not a function|Tests "
```
Expected: `TypeError: renderer.scrollToRow is not a function` and `Tests  1 failed | … passed`.

- [ ] **Step 3: Implement**

In `ts/renderer-dom/src/scroll-tracker.ts`, insert immediately before the line `	updateStickiness(): void {` (`rowTop` is already imported on line 2):

```ts
	scrollToRow(row: number, align: "start" | "center" | "end"): boolean {
		const container = this.deps.container();
		const flat = row - this.deps.paintedFirstStableRow();
		if (!container || flat < 0) return false;
		const { rowHeight, headerHeight, paddingY } = this.deps.layout();
		const top = rowTop(this.deps.blocks(), flat, rowHeight, headerHeight, paddingY);
		if (top === null) return false;
		const room = Math.max(0, container.clientHeight - rowHeight);
		const offset = align === "start" ? 0 : align === "end" ? room : room / 2;
		this.stickToBottom = false;
		container.scrollTop = Math.max(0, top - offset);
		this.captureAnchor();
		return true;
	}

```

In `ts/renderer-dom/src/dom-block-renderer.ts`, insert immediately before the line `	scrollToLatest(): void {`:

```ts
	scrollToRow(row: number, align: "start" | "center" | "end"): boolean {
		const moved = this.scroll.scrollToRow(row, align);
		if (moved) this.scheduleRepaint();
		return moved;
	}

```

- [ ] **Step 4: Run the test and the renderer suite**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/renderer-dom" && npx vitest run src/dom-block-renderer.scroll.test.ts 2>&1 | grep -E "Tests " && npx vitest run 2>&1 | grep -E "Test Files|Tests " && wc -l src/dom-block-renderer.ts src/scroll-tracker.ts
```
Expected: the scroll file all passed; the whole suite passes (Task 0's count + 1 test); `591 src/dom-block-renderer.ts`, `170 src/scroll-tracker.ts`.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && git add ts/renderer-dom/src/scroll-tracker.ts ts/renderer-dom/src/dom-block-renderer.ts ts/renderer-dom/src/dom-block-renderer.scroll.test.ts && git commit -m "feat(terminal): scroll the transcript to a stable row

<Co-Authored-By trailer from your harness>"
```

---

### Task 3: `@operator/terminal-core` find bindings and the find-500k bench

**Files:**
- Modify: `packages/terminal/ts/core/src/terminal-core.ts:14-28` (type import), `:38-40`, `:390-436`
- Modify: `packages/terminal/ts/core/src/types.ts:27-32`
- Modify: `packages/terminal/ts/core/src/index-browser.ts:16`, `:75`
- Rewrite: `packages/terminal/ts/core/src/find.test.ts`
- Modify: `packages/terminal/bench/find.bench.ts:2`, `:43-62`; `packages/terminal/bench/harness.ts:16`, `:163`, `:166`

**Interfaces:**
- Consumes: the wasm methods from Task 1 Step 7.
- Produces (TS, exported from `@operator/terminal-core`):
  - `type FindMatch = Readonly<{ blockId: BlockId; row: number; endRow: number; startByte: number; endByte: number }>` (stable rows; row-relative byte offsets).
  - `type FindUpdate = Readonly<{ added: number; removed: number; complete: boolean }>`.
  - `const FIND_UPDATE_BUDGET_BYTES = 1 << 20` (replaces `FIND_STEP_BUDGET`), `FIND_MATCH_WORDS = 6`.
  - `TerminalCore.findOpen(query: string, isRegex: boolean): number` (unchanged), `findUpdate(id: number, budgetBytes?: number): FindUpdate`, `findResults(id: number): FindMatch[]`, `findHistoryBytesScanned(id: number): number`, `findCancel(id: number): void` (forgets the session; a later `findUpdate(id)` throws). Removed: `findStep`, `findIsComplete`, zero-argument `findResults()`.
- Note: after this task `npm run build:ts` fails in `ts/renderer-dom/src/find-bar.ts` (it still calls `findStep`) until Task 4. Only build and test `ts/core` here.

- [ ] **Step 1: Write the failing core tests**

Replace `ts/core/src/find.test.ts` entirely with:

```ts
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, decodeBlocks, initTerminalCore } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

const encoder = new TextEncoder();

function feedBlocks(core: ReturnType<typeof createTerminalCore>, count: number, from: number = 0): void {
	for (let index = from; index < from + count; index += 1) {
		core.feed(encoder.encode(`\x1b]133;A\x07\x1b]133;C\x07line ${index} of text\x1b]133;D;0\x07\r\n`));
	}
}

function makeCore(): ReturnType<typeof createTerminalCore> {
	return createTerminalCore({ columns: 40, scrollback: 1000, rows: 1 });
}

describe("TerminalCore.findOpen / findUpdate / findResults", () => {
	it("finds a literal across a synthetic 5-block scrollback", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const blocks = decodeBlocks(core.snapshot());
		expect(blocks.length).toBe(5);
		const session = core.findOpen("line 2", false);
		expect(core.findUpdate(session).complete).toBe(true);
		const matches = core.findResults(session);
		expect(matches).toHaveLength(1);
		expect(blocks.map((block) => block.id)).toContain(matches[0]!.blockId);
		expect(matches[0]!.row).toBe(2);
		expect(matches[0]!.endRow).toBe(2);
		expect(matches[0]!.startByte).toBe(0);
		expect(matches[0]!.endByte).toBe(6);
		core.findCancel(session);
		core.dispose();
	});

	it("returns no matches when the literal is absent", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const session = core.findOpen("absent-needle", false);
		expect(core.findUpdate(session).complete).toBe(true);
		expect(core.findResults(session)).toEqual([]);
		core.findCancel(session);
		core.dispose();
	});

	it("surfaces an unparseable regex as a rejected open, leaving the core alive", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		expect(() => core.findOpen("(unclosed", true)).toThrow();
		core.feed(encoder.encode("after-error"));
		expect(new TextDecoder().decode(core.snapshot().content)).toContain("after-error");
		core.dispose();
	});

	it("finds every occurrence when updated with a tiny budget", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const session = core.findOpen("line", false);
		let guard = 0;
		while (!core.findUpdate(session, 8).complete && guard < 1000) {
			guard += 1;
		}
		expect(guard).toBeGreaterThan(0);
		expect(core.findResults(session)).toHaveLength(5);
		core.findCancel(session);
		core.dispose();
	});

	it("matches a valid regex across blocks", () => {
		const core = makeCore();
		feedBlocks(core, 5);
		const session = core.findOpen("line \\d of", true);
		core.findUpdate(session);
		expect(core.findResults(session)).toHaveLength(5);
		core.findCancel(session);
		core.dispose();
	});

	it("ignores case for a query without capitals", () => {
		const core = makeCore();
		core.feed(encoder.encode("Error one\r\nerror two\r\n"));
		const lower = core.findOpen("error", false);
		core.findUpdate(lower);
		expect(core.findResults(lower)).toHaveLength(2);
		const upper = core.findOpen("Error", false);
		core.findUpdate(upper);
		expect(core.findResults(upper)).toHaveLength(1);
		core.dispose();
	});

	it("searches a session without block marks, screen rows included", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 1000, rows: 5 });
		for (let index = 0; index < 20; index += 1) core.feed(encoder.encode(`hello ${index}\r\n`));
		const session = core.findOpen("hello", false);
		core.findUpdate(session);
		expect(core.findResults(session)).toHaveLength(20);
		core.dispose();
	});
});

describe("TerminalCore.findUpdate on a growing buffer", () => {
	it("picks up output that arrives after the scan completed", () => {
		const core = makeCore();
		feedBlocks(core, 3);
		const session = core.findOpen("UNIQUE_NEEDLE", false);
		expect(core.findUpdate(session).complete).toBe(true);
		expect(core.findResults(session)).toEqual([]);
		core.feed(encoder.encode("\x1b]133;A\x07\x1b]133;C\x07UNIQUE_NEEDLE appears here\x1b]133;D;0\x07\r\n"));
		const update = core.findUpdate(session);
		expect(update.added).toBe(1);
		expect(update.complete).toBe(true);
		expect(core.findResults(session)).toHaveLength(1);
		core.findCancel(session);
		core.dispose();
	});

	it("scans only the new history when output arrives", () => {
		const core = makeCore();
		feedBlocks(core, 50);
		const session = core.findOpen("line", false);
		core.findUpdate(session);
		const scanned = core.findHistoryBytesScanned(session);
		expect(scanned).toBeGreaterThan(0);
		const quiet = core.findUpdate(session);
		expect(quiet).toEqual({ added: 0, removed: 0, complete: true });
		expect(core.findHistoryBytesScanned(session)).toBe(scanned);
		feedBlocks(core, 1, 50);
		core.findUpdate(session);
		const grown = core.findHistoryBytesScanned(session) - scanned;
		expect(grown).toBeGreaterThan(0);
		expect(grown).toBeLessThan(scanned / 10);
		expect(core.findResults(session)).toHaveLength(51);
		core.dispose();
	});
});

describe("TerminalCore.findCancel", () => {
	it("forgets the session, so a later update is an error", () => {
		const core = makeCore();
		feedBlocks(core, 3);
		const session = core.findOpen("line", false);
		core.findUpdate(session);
		core.findCancel(session);
		expect(() => core.findUpdate(session)).toThrow();
		expect(() => core.findCancel(session)).not.toThrow();
		core.dispose();
	});

	it("reuses a session id after cancel", () => {
		const core = makeCore();
		feedBlocks(core, 3);
		const first = core.findOpen("line", false);
		core.findCancel(first);
		const second = core.findOpen("line", false);
		expect(second).toBe(first);
		core.findCancel(second);
		core.dispose();
	});

	it("assigns distinct ids to overlapping open sessions", () => {
		const core = makeCore();
		feedBlocks(core, 3);
		const a = core.findOpen("line", false);
		const b = core.findOpen("other", false);
		expect(a).not.toBe(b);
		core.findCancel(a);
		core.findCancel(b);
		core.dispose();
	});
});
```

- [ ] **Step 2: Rebuild the renderer wasm and watch the tests fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build:wasm -- --force && (cd ts/core && npx vitest run src/find.test.ts 2>&1 | grep -E "findUpdate is not a function|Tests ")
```
Expected: `build-wasm: … ready`, then failures with `TypeError: core.findUpdate is not a function` and `Tests  … failed`.

- [ ] **Step 3: Update `ts/core/src/types.ts`**

Replace (lines 27-32)

```ts
export type FindMatch = Readonly<{
	blockId: BlockId;
	row: number;
	byteRangeStart: number;
	byteRangeEnd: number;
}>;
```

with

```ts
export type FindMatch = Readonly<{
	blockId: BlockId;
	row: number;
	endRow: number;
	startByte: number;
	endByte: number;
}>;

export type FindUpdate = Readonly<{
	added: number;
	removed: number;
	complete: boolean;
}>;
```

- [ ] **Step 4: Update `ts/core/src/index-browser.ts`**

In the `export type { … }` list replace the line `	FindMatch,` (line 16) with the two lines

```ts
	FindMatch,
	FindUpdate,
```

and in the value export block replace `	FIND_STEP_BUDGET,` (line 75) with `	FIND_UPDATE_BUDGET_BYTES,`.

- [ ] **Step 5: Update `ts/core/src/terminal-core.ts`**

In the `import type { … } from "./types.js";` list (lines 14-28) replace `	FindMatch,` with

```ts
	FindMatch,
	FindUpdate,
```

Replace lines 38-40

```ts
export const FIND_MATCH_WORDS = 5;

export const FIND_STEP_BUDGET = 1000;
```

with

```ts
export const FIND_MATCH_WORDS = 6;

export const FIND_UPDATE_BUDGET_BYTES = 1 << 20;
```

Replace everything from `	findStep(id: number, budget: number = FIND_STEP_BUDGET): void {` through the closing `	}` of `findCancel` (lines 390-436; `findOpen` above it stays) with:

```ts
	findUpdate(id: number, budgetBytes: number = FIND_UPDATE_BUDGET_BYTES): FindUpdate {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		const words = this.inner.find_update(id, budgetBytes);
		return { added: words[0]!, removed: words[1]!, complete: words[2] === 1 };
	}

	findResults(id: number): FindMatch[] {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		this.inner.find_export(id);
		const memory = getMemory();
		const ptr = this.inner.find_results_ptr();
		const len = this.inner.find_results_len();
		if (len % FIND_MATCH_WORDS !== 0) {
			throw new Error(
				`find results length ${len} is not a multiple of ${FIND_MATCH_WORDS}`,
			);
		}
		const view = u32View(memory, ptr, len);
		const count = len / FIND_MATCH_WORDS;
		const matches: FindMatch[] = [];
		for (let index = 0; index < count; index += 1) {
			const base = index * FIND_MATCH_WORDS;
			matches.push({
				blockId: `${view[base + 1]!}:${view[base]!}`,
				row: view[base + 2]!,
				endRow: view[base + 3]!,
				startByte: view[base + 4]!,
				endByte: view[base + 5]!,
			});
		}
		return matches;
	}

	findHistoryBytesScanned(id: number): number {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		return this.inner.find_history_bytes_scanned(id);
	}

	findCancel(id: number): void {
		if (this.disposed) {
			throw new Error("terminal core is disposed");
		}
		this.inner.find_cancel(id);
	}
```

`getMemory()` is read after `find_export` on purpose: the export may grow wasm memory and detach older views.

- [ ] **Step 6: Port the find-500k bench**

`bench/find.bench.ts` line 2: replace `import { FIND_STEP_BUDGET, type TerminalCore } from "@operator/terminal-core";` with `import { FIND_UPDATE_BUDGET_BYTES, type TerminalCore } from "@operator/terminal-core";`, and replace the whole `measureFindFirstResult` function (lines 43-62, to the end of the file) with:

```ts
export function measureFindFirstResult(renderer: BenchmarkRenderer, budget: number = FIND_UPDATE_BUDGET_BYTES): number {
	const core = domCoreOf(renderer);
	const session = core.findOpen(FIND_QUERY, false);
	const startedAt = performance.now();
	let guard = 0;
	while (guard < 1_000_000) {
		const update = core.findUpdate(session, budget);
		if (update.added > 0) {
			core.findCancel(session);
			return performance.now() - startedAt;
		}
		if (update.complete) {
			break;
		}
		guard += 1;
	}
	core.findCancel(session);
	throw new Error("find-500k: no match in 1,000,000 steps");
}
```

`bench/harness.ts`: after the line `} from "./find.bench.js";` (line 16) add the line

```ts
import { UNBOUNDED_BYTES } from "@operator/terminal-core";
```

and replace both occurrences of `measureFindFirstResult(renderer, Number.MAX_SAFE_INTEGER)` (lines 163 and 166) with `measureFindFirstResult(renderer, UNBOUNDED_BYTES)` (a wasm `usize` is 32-bit; `UNBOUNDED_BYTES` is `0xffff_ffff`).

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && grep -n "MAX_SAFE_INTEGER\|FIND_STEP_BUDGET\|findStep\|findIsComplete" bench/find.bench.ts bench/harness.ts
```
Expected: no output.

- [ ] **Step 7: Build core and run its tests**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npx tsc -b ts/core && (cd ts/core && npx vitest run 2>&1 | grep -E "Test Files|Tests ")
```
Expected: `tsc` prints nothing; `Test Files  8 passed (8)` and `Tests  N passed` where N = Task 0's core count − 11 old find tests + 12 new ones (79 → 80 on the author's machine).

- [ ] **Step 8: Commit**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && git add ts/core/src/terminal-core.ts ts/core/src/types.ts ts/core/src/index-browser.ts ts/core/src/find.test.ts bench/find.bench.ts bench/harness.ts && git commit -m "feat(terminal): findUpdate and per-session findResults in terminal-core

The renderer-dom find bar moves to this API in the next commit.

<Co-Authored-By trailer from your harness>"
```

---

### Task 4: The find bar keeps up, smart case, regex toggle

**Files:**
- Rewrite: `packages/terminal/ts/renderer-dom/src/find-bar.ts`
- Create: `packages/terminal/ts/renderer-dom/src/find-bar.incremental.test.ts`
- Modify: `packages/terminal/ts/core/src/types.ts:199`, `:223` (`findRegexLabel`)
- Modify: `packages/terminal/ts/renderer-dom/src/palette.test.ts:22`, `jump-to-bottom.test.ts:22`
- Modify: `packages/terminal/ts/renderer-dom/src/styles.css` and `styles.ts` (after line 509)
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx:177`
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx:514`

**Interfaces:**
- Consumes: `findOpen`, `findUpdate`, `findResults(id)`, `findCancel`, `FIND_UPDATE_BUDGET_BYTES`, `FindMatch`, `FindUpdate` (Task 3); `DomBlockRenderer.scrollToRow` (Task 2).
- Produces: `FindBarHost` gains optional `scrollToRow?(row: number, align: "start" | "center" | "end"): boolean` (the bar falls back to `scrollToBlock` when it is absent or returns `false`); `TerminalStrings.findRegexLabel: string` (default `"Use regular expression"`); DOM: `button[data-terminal-find-regex].terminal-find-regex` with `aria-pressed`, the input gets `aria-invalid="true"` for an unparseable pattern.
- Behaviour: the bar calls `core.findUpdate` once per animation frame until the first scan completes and then after every renderer paint; it calls `core.findResults` only when an update reports `added > 0 || removed > 0` (or on the first update); highlights mark every rendered transcript row (`[data-terminal-block-id] [data-terminal-row]`) whose stable row a hit covers, in O(rendered rows); the current hit is re-found by (row, startByte) after each refresh.

- [ ] **Step 1: Write the failing bar tests**

Create `ts/renderer-dom/src/find-bar.incremental.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import {
	createTerminalCore,
	defaultStrings,
	initTerminalCore,
	type BlockRenderer,
	type FontConfig,
	type TerminalCore,
} from "@operator/terminal-core";
import { DomBlockRenderer, warpDarkTheme } from "./index";
import { createFindBar, type FindBar, type FindBarHost } from "./find-bar";

const wasmPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm");

const font: FontConfig = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.2,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
};

const encoder = new TextEncoder();

function flushFrames(count: number = 8): Promise<void> {
	return new Promise((resolve) => {
		let remaining = count;
		const step = () => {
			remaining -= 1;
			if (remaining <= 0) {
				resolve();
				return;
			}
			requestAnimationFrame(step);
		};
		requestAnimationFrame(step);
	});
}

function feedBlock(core: TerminalCore, text: string): void {
	core.feed(encoder.encode(`\x1b]133;A\x07\x1b]133;C\x07${text}\x1b]133;D;0\x07\r\n`));
}

type Mounted = {
	core: TerminalCore;
	host: HTMLElement;
	renderer: DomBlockRenderer;
	bar: FindBar;
	input: HTMLInputElement;
	count: HTMLElement;
	scrolled: ReturnType<typeof vi.fn>;
};

let mounted: Mounted | null = null;

beforeAll(async () => {
	const bytes = await readFile(wasmPath);
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});

afterEach(() => {
	mounted?.bar.dispose();
	mounted?.renderer.dispose();
	mounted = null;
	vi.restoreAllMocks();
});

function mount(lines: readonly string[]): Mounted {
	const core = createTerminalCore({ columns: 40, scrollback: 1000, rows: 1 });
	for (const line of lines) feedBlock(core, line);
	const host = document.createElement("div");
	Object.defineProperty(host, "clientHeight", { value: 800, configurable: true });
	Object.defineProperty(host, "scrollHeight", { value: 2000, configurable: true });
	Object.defineProperty(host, "scrollTop", { value: 1500, configurable: true, writable: true });
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(warpDarkTheme);
	renderer.setFont(font);
	const scrolled = vi.fn();
	const barHost: FindBarHost = {
		scrollToBlock: () => undefined,
		scrollToRow: (row, align) => {
			scrolled(row, align);
			return true;
		},
		invalidate: (range) => renderer.invalidate(range),
		afterRepaint: (listener) => renderer.onPaint(listener),
	};
	const bar = createFindBar({ core, renderer: renderer as unknown as BlockRenderer, host: barHost, strings: defaultStrings });
	bar.mount(host);
	bar.open();
	const input = host.querySelector<HTMLInputElement>("input[data-terminal-find-input]")!;
	const count = host.querySelector<HTMLElement>("[data-terminal-find-count]")!;
	mounted = { core, host, renderer, bar, input, count, scrolled };
	return mounted;
}

function type(input: HTMLInputElement, value: string): void {
	input.value = value;
	input.dispatchEvent(new Event("input", { bubbles: true }));
}

function press(input: HTMLInputElement, key: string, shiftKey: boolean = false): void {
	input.dispatchEvent(new KeyboardEvent("keydown", { key, shiftKey, bubbles: true, cancelable: true }));
}

const lines = (count: number): string[] => Array.from({ length: count }, (_, index) => `line ${index} of text`);

describe("find-bar while output streams", () => {
	it("a new match appears without retyping", async () => {
		const { core, input, count } = mount(lines(5));
		type(input, "needle");
		await flushFrames();
		expect(count.textContent).toBe("No matches");
		feedBlock(core, "a needle arrives");
		await flushFrames();
		expect(count.textContent).toBe("1 of 1");
		expect(input.value).toBe("needle");
	});

	it("does not rescan history on repaint", async () => {
		const { core, renderer, input } = mount(lines(200));
		const opened = vi.spyOn(core, "findOpen");
		const updates = vi.spyOn(core, "findUpdate");
		type(input, "line");
		await flushFrames();
		const id = opened.mock.results[0]!.value as number;
		const scanned = core.findHistoryBytesScanned(id);
		expect(scanned).toBeGreaterThan(0);
		const calls = updates.mock.calls.length;
		for (let repaint = 0; repaint < 3; repaint += 1) {
			renderer.invalidate({ start: 0, end: 1 });
			await flushFrames(4);
		}
		expect(updates.mock.calls.length).toBeGreaterThan(calls);
		expect(core.findHistoryBytesScanned(id)).toBe(scanned);
	});

	it("keeps the current hit anchored while output streams", async () => {
		const { core, host, input, count, scrolled } = mount(lines(5));
		type(input, "line");
		await flushFrames();
		expect(count.textContent).toBe("1 of 5");
		press(input, "Enter");
		press(input, "Enter");
		await flushFrames(2);
		expect(count.textContent).toBe("3 of 5");
		expect(scrolled).toHaveBeenLastCalledWith(2, "center");
		for (let index = 5; index < 8; index += 1) feedBlock(core, `line ${index} of text`);
		await flushFrames();
		expect(count.textContent).toBe("3 of 8");
		expect(host.querySelector<HTMLElement>("[data-terminal-find-row-active]")?.dataset.terminalRow).toBe("2");
		press(input, "Enter", true);
		await flushFrames(2);
		expect(count.textContent).toBe("2 of 8");
		expect(scrolled).toHaveBeenLastCalledWith(1, "center");
	});

	it("reads the query as a regular expression while the toggle is pressed", async () => {
		const { host, input, count } = mount(lines(5));
		const toggle = host.querySelector<HTMLButtonElement>("button[data-terminal-find-regex]")!;
		expect(toggle.getAttribute("aria-pressed")).toBe("false");
		type(input, "line [0-2] of");
		await flushFrames();
		expect(count.textContent).toBe("No matches");
		toggle.click();
		await flushFrames();
		expect(toggle.getAttribute("aria-pressed")).toBe("true");
		expect(count.textContent).toBe("1 of 3");
		type(input, "line [0-");
		await flushFrames();
		expect(input.getAttribute("aria-invalid")).toBe("true");
		expect(count.textContent).toBe("No matches");
		type(input, "line [4]");
		await flushFrames();
		expect(input.hasAttribute("aria-invalid")).toBe(false);
		expect(count.textContent).toBe("1 of 1");
	});

	it("ignores case for a query without capitals and not for one with a capital", async () => {
		const { input, count } = mount(["Error one", "error two"]);
		type(input, "error");
		await flushFrames();
		expect(count.textContent).toBe("1 of 2");
		type(input, "Error");
		await flushFrames();
		expect(count.textContent).toBe("1 of 1");
	});

	it("finds text in a session that has no block marks", async () => {
		const core = createTerminalCore({ columns: 40, scrollback: 1000, rows: 5 });
		const host = document.createElement("div");
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setFont(font);
		for (let index = 0; index < 12; index += 1) core.feed(encoder.encode(`hello ${index}\r\n`));
		const bar = createFindBar({
			core,
			renderer: renderer as unknown as BlockRenderer,
			host: { scrollToBlock: () => undefined, invalidate: (range) => renderer.invalidate(range), afterRepaint: (listener) => renderer.onPaint(listener) },
			strings: defaultStrings,
		});
		bar.mount(host);
		bar.open();
		const input = host.querySelector<HTMLInputElement>("input[data-terminal-find-input]")!;
		mounted = { core, host, renderer, bar, input, count: host.querySelector<HTMLElement>("[data-terminal-find-count]")!, scrolled: vi.fn() };
		type(input, "hello");
		await flushFrames();
		expect(mounted.count.textContent).toBe("1 of 12");
	});
});
```

- [ ] **Step 2: Add the string key everywhere a `TerminalStrings` is built**

`ts/core/src/types.ts`: in the `TerminalStrings` type replace the line `	findMatchCount: string;` (line 199) with

```ts
	findMatchCount: string;
	findRegexLabel: string;
```

and in `defaultStrings` replace `	findMatchCount: "%1 of %2",` (line 223) with

```ts
	findMatchCount: "%1 of %2",
	findRegexLabel: "Use regular expression",
```

`ts/renderer-dom/src/palette.test.ts` and `ts/renderer-dom/src/jump-to-bottom.test.ts`: in each, replace the line `	findMatchCount: "%1 of %2",` (line 22) with

```ts
	findMatchCount: "%1 of %2",
	findRegexLabel: "Regex",
```

`frontend/src/renderer/components/BlockTerminal.tsx`: replace the line (514)

```tsx
			findMatchCount: t("blocks.findMatchCount", { defaultValue: "%1 of %2" }),
```

with

```tsx
			findMatchCount: t("blocks.findMatchCount", { defaultValue: "%1 of %2" }),
			findRegexLabel: t("blocks.findRegexLabel", { defaultValue: "Use regular expression" }),
```

- [ ] **Step 3: Run the new tests and watch them fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npx tsc -b ts/core && (cd ts/renderer-dom && npx vitest run src/find-bar.incremental.test.ts 2>&1 | grep -E "Test Files|Tests |FIND_STEP_BUDGET|findStep|FAIL" | head -8)
```
Expected: `Test Files  1 failed (1)` — either a module-load error naming `FIND_STEP_BUDGET` (the old bar imports a constant the core no longer exports) or `Tests  6 failed (6)` (the old bar calls `core.findStep`, which no longer exists). Either is the red state.

- [ ] **Step 4: Rewrite `ts/renderer-dom/src/find-bar.ts`**

Replace the whole file with:

```ts
import {
	FIND_UPDATE_BUDGET_BYTES,
	type BlockId,
	type BlockRenderer,
	type FindMatch,
	type FindUpdate,
	type RowRange,
	type TerminalCore,
	type TerminalStrings,
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

export type FindBarOptions = Readonly<{
	core: TerminalCore;
	renderer: BlockRenderer;
	host: FindBarHost;
	strings: TerminalStrings;
}>;

export type FindBar = Readonly<{
	mount(container: HTMLElement): void;
	open(): void;
	close(): void;
	dispose(): void;
}>;

type Session = {
	readonly id: number;
	results: readonly FindMatch[];
	rows: ReadonlySet<number>;
	current: number;
	loaded: boolean;
};

export function createFindBar(options: FindBarOptions): FindBar {
	const { core, host, strings } = options;
	let container: HTMLElement | null = null;
	let bar: HTMLElement | null = null;
	let input: HTMLInputElement | null = null;
	let countNode: HTMLElement | null = null;
	let session: Session | null = null;
	let regex = false;
	let invalid = false;
	let rafHandle: number | null = null;
	let repaintOff: (() => void) | null = null;
	let previousFocus: HTMLElement | null = null;

	const cancelRaf = (): void => {
		if (rafHandle !== null && typeof cancelAnimationFrame === "function") {
			cancelAnimationFrame(rafHandle);
		}
		rafHandle = null;
	};

	const renderCount = (): void => {
		if (!countNode) return;
		if (invalid) {
			countNode.textContent = strings.searchNoMatches;
			return;
		}
		if (!session) {
			countNode.textContent = "";
			return;
		}
		const total = session.results.length;
		if (total === 0) {
			countNode.textContent = strings.searchNoMatches;
			return;
		}
		countNode.textContent = strings.findMatchCount
			.replace("%1", String(session.current + 1))
			.replace("%2", String(total));
	};

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

	const stopSession = (): void => {
		cancelRaf();
		if (session) {
			try {
				core.findCancel(session.id);
			} catch {
				void 0;
			}
			session = null;
		}
	};

	const indexNear = (results: readonly FindMatch[], anchor: FindMatch | undefined): number => {
		if (!anchor || results.length === 0) return 0;
		let low = 0;
		let high = results.length;
		while (low < high) {
			const mid = (low + high) >> 1;
			const hit = results[mid]!;
			if (hit.row < anchor.row || (hit.row === anchor.row && hit.startByte < anchor.startByte)) {
				low = mid + 1;
			} else {
				high = mid;
			}
		}
		return Math.min(low, results.length - 1);
	};

	const rowsOf = (results: readonly FindMatch[]): Set<number> => {
		const rows = new Set<number>();
		for (const hit of results) {
			for (let row = hit.row; row <= hit.endRow; row += 1) rows.add(row);
		}
		return rows;
	};

	const refresh = (active: Session): void => {
		const anchor = active.loaded ? active.results[active.current] : undefined;
		const results = core.findResults(active.id);
		active.results = results;
		active.rows = rowsOf(results);
		active.current = indexNear(results, anchor);
		active.loaded = true;
	};

	const pump = (): void => {
		rafHandle = null;
		const active = session;
		if (!active) return;
		let update: FindUpdate;
		try {
			update = core.findUpdate(active.id, FIND_UPDATE_BUDGET_BYTES);
			if (!active.loaded || update.added > 0 || update.removed > 0) {
				refresh(active);
				applyHighlights();
				renderCount();
			}
		} catch {
			stopSession();
			clearMarks();
			renderCount();
			return;
		}
		if (!update.complete) schedulePump();
	};

	const schedulePump = (): void => {
		if (rafHandle !== null) return;
		rafHandle = requestAnimationFrame(pump);
	};

	const openSession = (query: string): void => {
		stopSession();
		invalid = false;
		input?.removeAttribute("aria-invalid");
		if (query === "") {
			clearMarks();
			renderCount();
			return;
		}
		let id: number;
		try {
			id = core.findOpen(query, regex);
		} catch {
			invalid = true;
			input?.setAttribute("aria-invalid", "true");
			clearMarks();
			renderCount();
			return;
		}
		session = { id, results: [], rows: new Set(), current: 0, loaded: false };
		schedulePump();
	};

	const walk = (delta: number): void => {
		const active = session;
		if (!active) return;
		const total = active.results.length;
		if (total === 0) return;
		active.current = (active.current + delta + total) % total;
		const match = active.results[active.current]!;
		if (!host.scrollToRow?.(match.row, "center")) {
			host.scrollToBlock(match.blockId, "center");
		}
		applyHighlights();
		renderCount();
	};

	const ensureBar = (): HTMLElement => {
		if (bar) return bar;
		const node = document.createElement("div");
		node.className = CLASS_BAR;
		node.setAttribute(ATTR_BAR, "");
		const label = document.createElement("label");
		label.className = "terminal-find-label";
		label.setAttribute("aria-label", strings.findLabel);
		const field = document.createElement("input");
		field.type = "text";
		field.className = CLASS_INPUT;
		field.setAttribute(ATTR_INPUT, "");
		field.placeholder = strings.findPlaceholder;
		field.setAttribute("aria-label", strings.findLabel);
		field.spellcheck = false;
		field.autocomplete = "off";
		field.addEventListener("input", () => {
			openSession(field.value);
		});
		field.addEventListener("keydown", (event) => {
			if (event.key === "Enter") {
				event.preventDefault();
				walk(event.shiftKey ? -1 : 1);
			} else if (event.key === "Escape") {
				event.preventDefault();
				close();
			}
		});
		const toggle = document.createElement("button");
		toggle.type = "button";
		toggle.className = CLASS_REGEX;
		toggle.setAttribute(ATTR_REGEX, "");
		toggle.setAttribute("aria-label", strings.findRegexLabel);
		toggle.setAttribute("aria-pressed", String(regex));
		toggle.title = strings.findRegexLabel;
		toggle.textContent = ".*";
		toggle.addEventListener("mousedown", (event) => event.preventDefault());
		toggle.addEventListener("click", () => {
			regex = !regex;
			toggle.setAttribute("aria-pressed", String(regex));
			openSession(field.value);
			field.focus();
		});
		const counter = document.createElement("span");
		counter.className = CLASS_COUNT;
		counter.setAttribute(ATTR_COUNT, "");
		counter.setAttribute("aria-live", "polite");
		label.append(field);
		node.append(label, toggle, counter);
		bar = node;
		input = field;
		countNode = counter;
		return node;
	};

	function open(): void {
		if (!container) return;
		previousFocus = document.activeElement as HTMLElement | null;
		const node = ensureBar();
		if (node.parentElement !== container) {
			container.append(node);
		}
		bar = node;
		if (repaintOff === null) {
			repaintOff = host.afterRepaint(() => {
				applyHighlights();
				if (session) schedulePump();
			});
		}
		if (input) {
			input.value = "";
			input.removeAttribute("aria-invalid");
			input.focus();
		}
		invalid = false;
		stopSession();
		renderCount();
	}

	function close(): void {
		if (!container) return;
		stopSession();
		invalid = false;
		clearMarks();
		if (bar && bar.parentElement === container) {
			container.removeChild(bar);
		}
		bar = null;
		input = null;
		countNode = null;
		if (previousFocus && previousFocus.focus) {
			previousFocus.focus();
		}
		previousFocus = null;
	}

	function mount(target: HTMLElement): void {
		container = target;
	}

	function dispose(): void {
		stopSession();
		clearMarks();
		if (repaintOff) {
			repaintOff();
			repaintOff = null;
		}
		if (bar && container && bar.parentElement === container) {
			container.removeChild(bar);
		}
		bar = null;
		input = null;
		countNode = null;
		container = null;
		previousFocus = null;
	}

	return { mount, open, close, dispose };
}
```

What changed against the old bar, for the reviewer: no per-repaint `decodeBlocks` and no per-hit `querySelector` (`refreshBlocks`/`findBlockById`/`rowNodeFor`/`isRowVisible` are gone); the unused `queryBeforeEdit` variable is gone; `stopSession` also cancels the pending frame; the regex flag survives close/open, the query does not (as before).

- [ ] **Step 5: Style the toggle**

In **both** `ts/renderer-dom/src/styles.css` and `ts/renderer-dom/src/styles.ts`, find the block (line 507 in each)

```css
.terminal-find-input:focus-visible {
	border-color: var(--terminal-block-header-foreground);
}
```

and insert directly after its closing `}` line, keeping one blank line before and after, exactly this (identical in both files — `styles-parity.test.ts` compares them byte for byte):

```css

.terminal-find-regex {
	font: inherit;
	font-size: 11px;
	line-height: 1;
	color: var(--terminal-block-header-foreground);
	background: transparent;
	border: 1px solid transparent;
	border-radius: 3px;
	padding: 2px 4px;
	cursor: default;
	opacity: 0.7;
}

.terminal-find-regex[aria-pressed="true"] {
	background: var(--terminal-background);
	border-color: var(--terminal-block-border);
	opacity: 1;
}
```

(The bar stays package-styled from its existing `--terminal-*` variables, like the input beside it; nothing here is an Operator design decision.)

- [ ] **Step 6: Give the bar row scrolling in `TerminalSurface`**

`ts/react/src/TerminalSurface.tsx` line 177: replace

```tsx
				scrollToBlock: (id, align) => renderer.scrollToBlock(id, align),
				invalidate: (range) => renderer.invalidate(range),
```

with

```tsx
				scrollToBlock: (id, align) => renderer.scrollToBlock(id, align),
				scrollToRow: (row, align) => renderer.scrollToRow(row, align),
				invalidate: (range) => renderer.invalidate(range),
```

- [ ] **Step 7: Build and run the new bar tests**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build:ts && (cd ts/renderer-dom && npx vitest run src/find-bar.incremental.test.ts src/find-bar.test.ts src/styles-parity.test.ts 2>&1 | grep -E "Test Files|Tests ")
```
Expected: `build:ts` prints no `error`; `Test Files  3 passed (3)`; `Tests  N passed` with no failures (the 8 existing find-bar tests keep passing unchanged).

- [ ] **Step 8: Run every TS suite and the boundary check**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && for p in core renderer-dom editor completions react; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Test Files|Tests "); done && npm run check:boundaries && wc -l ts/renderer-dom/src/find-bar.ts ts/renderer-dom/src/styles.ts ts/renderer-dom/src/styles.css
```
Expected: all five suites pass (renderer-dom = Task 0 count + 7); `boundary check passed`; `351 …find-bar.ts`, `594 …styles.ts`, `581 …styles.css`.

- [ ] **Step 9: Frontend type check and the BlockTerminal tests**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx tsc --noEmit -p . && npx vitest run --config vite.renderer.config.ts src/renderer/components/BlockTerminal.test.tsx 2>&1 | grep -E "Test Files|Tests "
```
Expected: `tsc` prints nothing; `Test Files  1 passed`. If `npm ci` failed in Task 0, write "frontend tsc/tests: not run — <reason>".

- [ ] **Step 10: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/ts/renderer-dom/src/find-bar.ts packages/terminal/ts/renderer-dom/src/find-bar.incremental.test.ts packages/terminal/ts/core/src/types.ts packages/terminal/ts/renderer-dom/src/palette.test.ts packages/terminal/ts/renderer-dom/src/jump-to-bottom.test.ts packages/terminal/ts/renderer-dom/src/styles.css packages/terminal/ts/renderer-dom/src/styles.ts packages/terminal/ts/react/src/TerminalSurface.tsx frontend/src/renderer/components/BlockTerminal.tsx && git commit -m "feat(terminal): find bar keeps up with streaming output

The bar updates its session on every paint, refetches results only when
hits were added or removed, keeps the current hit anchored by stable
row, scrolls to the hit's row, and gets a regex toggle. Smart case comes
from the core.

<Co-Authored-By trailer from your harness>"
```

---

### Task 5: Perf check — update vs rescan on the 60k-row fixture, and find-500k

**Files:**
- Create: `packages/terminal/bench/find-update.mjs`
- Modify: `packages/terminal/package.json` (scripts)

**Interfaces:**
- Consumes: `ts/core/dist` (built in Task 4 Step 7) and `ts/core/wasm/vt_core_bg.wasm`.
- Produces: `npm run bench:find-update -- [query]` printing one JSON line per pair.

- [ ] **Step 1: Write the script**

Create `packages/terminal/bench/find-update.mjs`:

```js
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { createTerminalCore, initTerminalCore } from "../ts/core/dist/index.js";
import { loadFixture } from "./agent-session/fixtures.mjs";

const QUERY = process.argv[2] ?? "12";
const PAIRS = 3;
const TAIL_BYTES = 64 * 1024;

const wasm = await readFile(fileURLToPath(new URL("../ts/core/wasm/vt_core_bg.wasm", import.meta.url)));
await initTerminalCore(wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength));
const { recording, sizes } = await loadFixture("claude-long-50k");
const { cols, rows } = sizes[0];

function loadedCore() {
	const core = createTerminalCore({ columns: cols, rows, limits: { rows: 200_000, bytes: 128 * 1024 * 1024 } });
	core.setAgentTuiMode(true);
	core.setGraphemeClusters(true);
	core.feed(recording.subarray(0, recording.length - TAIL_BYTES));
	return core;
}

function rescan(core) {
	const started = performance.now();
	const id = core.findOpen(QUERY, false);
	while (!core.findUpdate(id).complete) {}
	const hits = core.findResults(id).length;
	core.findCancel(id);
	return { ms: performance.now() - started, hits };
}

function update(core, id) {
	const started = performance.now();
	core.findUpdate(id);
	const hits = core.findResults(id).length;
	return { ms: performance.now() - started, hits };
}

for (let pair = 0; pair < PAIRS; pair += 1) {
	const core = loadedCore();
	const id = core.findOpen(QUERY, false);
	while (!core.findUpdate(id).complete) {}
	const scannedBefore = core.findHistoryBytesScanned(id);
	core.feed(recording.subarray(recording.length - TAIL_BYTES));
	const updateFirst = pair % 2 === 0;
	const first = updateFirst ? update(core, id) : rescan(core);
	const second = updateFirst ? rescan(core) : update(core, id);
	const incremental = updateFirst ? first : second;
	const full = updateFirst ? second : first;
	const snapshot = core.snapshot();
	console.log(JSON.stringify({
		pair,
		order: updateFirst ? "update,rescan" : "rescan,update",
		historyRows: snapshot.historyRows,
		updateMs: Number(incremental.ms.toFixed(2)),
		rescanMs: Number(full.ms.toFixed(2)),
		updateHits: incremental.hits,
		rescanHits: full.hits,
		historyBytesScanned: scannedBefore,
		scannedByUpdate: core.findHistoryBytesScanned(id) - scannedBefore,
	}));
	core.findCancel(id);
	core.dispose();
}
```

"Before" is the cost of the rescan the old bar needed to show new output (a fresh session, full scan — the old `FindCursor` itself cannot be timed on this fixture because it finds nothing in a markless core); "after" is one `findUpdate` + `findResults` on the live session. Order alternates across the three pairs (`TERMINAL.md` §4.26, A/B rule). The cross-check is mechanical rather than a trace: `updateHits` must equal `rescanHits` and `scannedByUpdate` must be only the newly settled bytes.

- [ ] **Step 2: Register the script**

In `packages/terminal/package.json`, replace

```json
		"bench:soak": "node ./bench/agent-session/soak.mjs"
```

with

```json
		"bench:soak": "node ./bench/agent-session/soak.mjs",
		"bench:find-update": "node ./bench/find-update.mjs"
```

- [ ] **Step 3: Run it**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:find-update
```
Expected: three JSON lines with `order` alternating `update,rescan` / `rescan,update` / `update,rescan`, `historyRows` 60097, `updateHits === rescanHits` on every line, `historyBytesScanned` ≈ 341367 and `scannedByUpdate` in the low thousands. Author's machine: `updateMs` 1.59/1.98/0.52 against `rescanMs` 2.26/2.39/2.69 with 3,200 hits (most of an update's time is the results export). Copy the three lines verbatim into the report. If `updateHits !== rescanHits` on any line, stop: that is a bug in Task 1.

- [ ] **Step 4: Run the find-500k scenario (budget and sensitivity gate)**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:terminal -- --renderer dom --scenario find-500k && node -e 'const fs=require("fs");const f=fs.readdirSync("bench/results").filter(n=>n.endsWith("-dom.json")).sort().pop();const s=JSON.parse(fs.readFileSync("bench/results/"+f,"utf8")).scenarios["find-500k"];console.log(f,JSON.stringify({p95:s.p95,median:s.median,sensitivityRatio:s.sensitivityRatio,sensitivityP95:s.sensitivityP95}))'
```
Expected: `wrote bench/results/<stamp>-dom.json`, then a line with `p95` ≤ 100 and `sensitivityRatio` ≥ 1.5 (`bench/gate.mjs:61-72`). Author's machine: `p95` 30.3 ms, `sensitivityRatio` 2.03. `bench/results/` is not committed. If Playwright is unavailable: "find-500k: not run — <reason>".

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && git add bench/find-update.mjs package.json && git commit -m "bench(terminal): time a find update against a rescan on claude-long-50k

<Co-Authored-By trailer from your harness>"
```

---

### Task 6: Host mirror wasm, pty-host tests, daemon build

**Files:**
- Rebuild: `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`

**Interfaces:** none new. `vt-host` does not call find, but it links `vt-core`, and the binary changes when `find.rs` changes.

- [ ] **Step 1: Rebuild and copy**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo build --release -p vt-host --target wasm32-unknown-unknown && sha256sum target/wasm32-unknown-unknown/release/vt_host.wasm && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && ls -l ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
```
Expected: a hash different from Task 0 Step 6's first hash (the author measured 316,867 → 316,814 bytes in one directory). If it is identical, write "vt_host.wasm unchanged by this plan (hash <h>)" in the report, run `git checkout -- backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`, and skip Steps 3–4's commit.

- [ ] **Step 2: pty-host Go tests**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && go test ./internal/adapters/runtime/ptyhost/... 2>&1 | tail -15
```
Expected: every package `ok`. The only accepted failure is the pre-existing `TestProcessEnvironmentLetsOverridesWin` (`TERMINAL.md` §5 and §8); name it if it appears. If Go is unavailable: "pty-host Go tests: not run — <reason>".

- [ ] **Step 3: Daemon build**

```bash
cd "$(git rev-parse --show-toplevel)" && npm --prefix frontend run build:daemon 2>&1 | tail -5
```
Expected: the script ends without error and `frontend/daemon/opr` exists (`ls -l frontend/daemon/opr`). It is a local artifact, not committed. If it fails for a reason unrelated to this plan (missing platform SDK), record "daemon build: not run — <exact error>"; the reviewer rebuilds locally.

- [ ] **Step 4: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && git commit -m "build(terminal): rebuild vt_host.wasm for the find session change

<Co-Authored-By trailer from your harness>"
```

---

### Task 7: Full verification gates

**Files:** none changed.

- [ ] **Step 1: Rust**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test 2>&1 | grep -E "^test result|FAILED|panicked" | sort | uniq -c
```
Expected: no warnings, every line `test result: ok.`, no `FAILED`/`panicked`.

- [ ] **Step 2: Both wasm builds and the TS suites**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor completions react; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Test Files|Tests "); done && npm run check:boundaries
```
Expected: `build-wasm: … ready`; no `error` from `build:ts`; all suites pass; `boundary check passed`, `no ownership timers found`.

- [ ] **Step 3: Feel gate against this environment's base pixels**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && rm -rf bench/agent-session/baselines && cp -R /tmp/plan2-feel-base bench/agent-session/baselines && npm run bench:feel; status=$?; git checkout -- bench/agent-session/baselines && git clean -fd -- bench/agent-session/baselines >/dev/null; git status --short bench/agent-session/baselines; echo "bench:feel exit $status"
```
Expected: `PASS feel gate: zero pixel diff` (what the author got with this plan's code against pixels recorded from the unmodified tree), `bench:feel exit 0`, and `git status --short` prints nothing (committed baselines restored). Any `DIFF` is a real pixel change from this plan — stop and investigate (the find bar is closed in every feel screenshot, so none is expected). If Task 0 Step 7 was not run: "bench:feel: not run — <reason>".

- [ ] **Step 4: Selection, agent gate, agent scroll**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:selection 2>&1 | tail -2 && npm run bench:agent:gate 2>&1 | tail -3 && npm run bench:agent:scroll 2>&1 | tail -3
```
Expected: `PASS selection survived 21 repaints` (the count may differ by one; it must say PASS); the agent gate ends with `PASS agent-session gate`; the scroll gate prints JSON lines in which `covered` equals `total`, the trim phase's `before` and `after` rows are equal, and the width phase's `before` equals `after` (author: `60134/60134`, trim `25031`→`25031`, width `30066`→`30066`). Copy the lines into the report. `bench:agent:gate` also runs a Go test in `backend/` for its reopen row (`TERMINAL.md` §3 rule 1 exemption); without Go, record which row could not run.

- [ ] **Step 5: Affordances**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && for action in hover hint redact; do npm run bench:affordances -- --action $action 2>&1 | tail -2; done
```
Expected: each run exits 0 and reports where it wrote its side-by-side screenshots (they are recorded, never diffed; do not commit them).

- [ ] **Step 6: No commit.** Nothing changes in this task. `git status --short` must show nothing except ignored/untracked bench output you did not create by hand; do not add `bench/results/`.

---

### Task 8: Docs

**Files:**
- Modify: `packages/terminal/CHANGELOG.md` (top of "Unreleased")
- Modify: `packages/terminal/README.md:11-18`
- Modify: `TERMINAL.md:253-254` (§3 rule 2), before `:834` (new §4.28), after `:834` (§5 bullet)
- Modify: `docs/terminal/2026-09-19-terminal-reference-survey.md:50`, `:60`, `:77`, `:97`, `:628`, `:1523`, `:2490`
- Modify: `docs/terminal/2026-09-24-not-done-plain-language.md:23`, `:26`

- [ ] **Step 1: CHANGELOG**

In `packages/terminal/CHANGELOG.md`, directly under `## Unreleased` and its blank line, insert (replace `<U1>`, `<R1>` … with the three `updateMs`/`rescanMs` pairs and `<P95>`/`<RATIO>` with the find-500k numbers you measured in Task 5; if a measurement was not run, write "not run: <reason>" in its place):

```markdown
- vt-core/vt-wasm/core/renderer-dom/react: find keeps up. `FindSession` replaces `FindCursor`: `TerminalCore::find_update(&mut session, budget_bytes)` scans settled history once from a `scanned_to` content offset and never again, re-searches the unsettled tail and the live screen only when `generation()` changed, and `find_results` resolves hits (content byte ranges) to stable rows through the row index, so a trim drops only the trimmed hits and a rewrap needs no rescan. A soft-wrapped line is one line to the search; a hard row break is never crossed. Smart case (Alacritty `alacritty_terminal/src/term/search.rs:39-40`): a query without a capital is case-insensitive, for literals and regexes. TS: `findUpdate(id, budgetBytes = FIND_UPDATE_BUDGET_BYTES)` → `{ added, removed, complete }`, `findResults(id)` → `{ blockId, row, endRow, startByte, endByte }` (six words per hit), `findHistoryBytesScanned(id)`; `findStep`, `findIsComplete` and `FIND_STEP_BUDGET` are removed and `findCancel` forgets the session. The find bar updates on every paint while open (new matches appear without retyping), refetches results only when hits were added or removed, keeps the current hit anchored by (stable row, byte), scrolls to the hit's row (`DomBlockRenderer.scrollToRow`, `FindBarHost.scrollToRow`), and has a `.*` regex toggle (`TerminalStrings.findRegexLabel`; an unparseable pattern shows "No matches" with `aria-invalid`). Fixed on the way: the old walker searched only blocks whose every row was in scrollback, so it found nothing in a pane without OSC 133 marks (every Claude Code pane) and nothing still on the screen. Measured on `claude-long-50k` (60,097 history rows, 341,367 history bytes; `npm run bench:find-update`, order alternated): update <U1>/<U2>/<U3> ms against a rescan of <R1>/<R2>/<R3> ms, same hit count. `find-500k`: p95 <P95> ms, sensitivity <RATIO>×. Both wasm artifacts and the daemon must be rebuilt.
```

- [ ] **Step 2: README**

In `packages/terminal/README.md` replace lines 11-18 (the `- **Find.**` bullet) with (fill `<P95>` from Task 5):

```markdown
- **Find.** `createFindBar({ core, renderer, host, strings })` returns a
  `FindBar` handle. Cmd/Ctrl+F opens the bar; typing opens a find
  session; Enter walks forward, Shift+Enter walks backward, Escape
  closes and restores focus. The session lives in the core and is held
  only as a `u32` id in JS: `core.findUpdate(id)` scans history once, in
  `FIND_UPDATE_BUDGET_BYTES` steps, then only what is new, and the bar
  calls it on every paint so new output is searched as it arrives.
  Lowercase queries ignore case; the `.*` button switches to regular
  expressions. Cancellation is `core.findCancel(id)`. The bench gate:
  **<P95>ms p95** to the first hit in a 500k-row scrollback, under the
  100ms ceiling.
```

- [ ] **Step 3: `TERMINAL.md` §3 rule 2**

Replace lines 253-254

```markdown
2. **Match Warp, cite Warp.** Rendering/behaviour decisions quote the Warp file
   and line they mirror (see the comments already in `styles.css`, `screen.rs`).
```

with

```markdown
2. **Match Warp, cite Warp.** Rendering/behaviour decisions quote the Warp file
   and line they mirror (see the comments already in `styles.css`, `screen.rs`).
   Find cites two MIT/Apache references for behaviour only, no code adapted:
   Ghostty `src/terminal/search/active.zig:11-19` (re-search only what can
   change) and Alacritty `alacritty_terminal/src/term/search.rs:39-40` (smart
   case).
```

- [ ] **Step 4: `TERMINAL.md` §4.28 and the §5 gap**

Replace the heading line `## 5. Known gaps (not bugs, decisions pending)` and the blank line after it with:

```markdown
### 4.28 Find found nothing in Claude Code panes and never kept up — Plan 2
- Symptom: in a Claude Code pane the find bar said "No matches" for text on
  the screen; in a shell it found only commands whose output had scrolled
  entirely into scrollback; a match printed after the query was typed never
  appeared.
- Cause: `FindCursor` walked `BlockGrid` blocks and searched a block only when
  every row of it was completed history (`block_byte_range` returned `None`
  otherwise). A pane without OSC 133 marks — every Claude Code pane — has an
  empty `BlockGrid` (its one block is synthesised only at export,
  `grid.rs` `export_blocks`), so there was nothing to walk. Each query
  scanned once and stopped; the bar decoded every block and ran two
  `querySelector` calls per hit on every repaint.
- Now: `FindSession` (`crates/vt-core/src/find.rs`) searches rows, not
  blocks. Settled history — completed rows up to the last one that ends a
  line — is scanned once, oldest first, in `FIND_UPDATE_BUDGET_BYTES`
  (1 MiB) steps, then only from `scanned_to`. Hits are content byte ranges:
  a trim drops those below the first row, a rewrap only changes the rows
  they resolve to in `find_results`, a history prepend (attach replay)
  restarts the scan. The unsettled tail (a soft-wrapped last history row)
  plus the live screen is re-searched when `generation()` changed, so a
  match across the scrollback/screen boundary is one hit. A soft-wrapped
  line is one line to the search; a hard break is a `\n` the query cannot
  cross (a match that would cross is searched again inside its own line).
  Literal queries use `memchr` when case-sensitive and an escaped regex
  (`regex-syntax`'s meta-character set) when not. The bar calls
  `findUpdate` after every paint while open, refetches results only when
  hits were added or removed, marks rendered rows from a set of hit rows,
  re-anchors the current hit by (stable row, byte), and scrolls to the
  hit's row with `DomBlockRenderer.scrollToRow`. Next/previous is an index
  step through sorted results, so Alacritty's directional DFAs
  (survey §2.6) were not needed.
- Guards: `crates/vt-core/tests/find_session.rs`, the `find.rs` unit tests,
  `ts/core/src/find.test.ts`, `ts/renderer-dom/src/find-bar.incremental.test.ts`,
  `dom-block-renderer.scroll.test.ts` "scrollToRow",
  `npm run bench:terminal -- --renderer dom --scenario find-500k`,
  `npm run bench:find-update`.

## 5. Known gaps (not bugs, decisions pending)

- **Find exports every hit on every change.** `findResults` copies all hits
  out of wasm whenever an update adds or removes one; while Claude streams, a
  query with hundreds of thousands of hits (a single letter) pays that per
  paint. Hits are still row classes, not decorations (survey §1.8, Plan 5),
  and there is no host `onResultsChanged` (survey §3.12).
```

- [ ] **Step 5: Survey status lines**

In `docs/terminal/2026-09-19-terminal-reference-survey.md`:

Line 60, replace the row with:

```markdown
| §1.7 | Done | Plan 2 — `FindSession` on the core: settled history scanned once from `scanned_to` and never again; the unsettled tail and the live screen re-searched only when the generation changes; hits re-resolve through the row index after a trim or rewrap. Also fixed: panes without OSC 133 marks (Claude Code) and rows still on the screen were never searched. |
```

Line 77, replace the row with:

```markdown
| §2.6 | Partial | Plan 2 — smart case (Alacritty `search.rs:39-40`) for literals and regexes, and a regex toggle in the find bar. Next/previous is an index step through the session's sorted results, so directional DFAs were not needed. Not done: `bracket_search`, `semantic_search_*`. |
```

Line 97, replace the row with:

```markdown
| §3.12 | Partial | Plan 2 — the find bar updates on every paint through `findUpdate` (new matches appear without retyping; history is not rescanned) and keeps the current hit anchored by stable row. Not done: hits as decorations (still row classes, §1.8) and a host `onResultsChanged`. |
```

Line 628, replace with:

```markdown
> **Status: Done.** Plan 2 — `FindSession` on the core: settled history scanned once from `scanned_to`, the unsettled tail and the live screen re-searched only when the generation changes, hits re-resolved through the row index. Also fixed: markless (Claude Code) panes and on-screen rows were never searched.
```

Line 1523, replace with:

```markdown
> **Status: Partial.** Plan 2 — smart case and a regex toggle; next/previous walks sorted results, so no directional DFAs. Not done: `bracket_search`, `semantic_search_*`.
```

Line 2490, replace with:

```markdown
> **Status: Partial.** Plan 2 — re-search on every paint through `findUpdate`, current hit anchored by stable row. Not done: hits as decorations (still row classes, §1.8) and `onResultsChanged`.
```

Line 50 (the summary sentence): the counts move by done +1, partial +2, not done −3. If the line reads `36 done, 17 partial, 26 not done`, make it `37 done, 19 partial, 23 not done`; if another plan already changed it, apply the same +1 / +2 / −3 to the numbers there. Leave the rest of the sentence as is.

Check:

```bash
cd "$(git rev-parse --show-toplevel)" && grep -n "^| §1.7 \|^| §2.6 \|^| §3.12 " docs/terminal/2026-09-19-terminal-reference-survey.md && grep -c "Status: Not done" docs/terminal/2026-09-19-terminal-reference-survey.md && grep -c "Status: Partial" docs/terminal/2026-09-19-terminal-reference-survey.md && grep -c "Status: Done" docs/terminal/2026-09-19-terminal-reference-survey.md
```
Expected: the three rows show Done / Partial / Partial, and the three counts equal the not done / partial / done numbers you wrote on line 50.

- [ ] **Step 6: Plain-language items 1 and 2**

In `docs/terminal/2026-09-24-not-done-plain-language.md`, after line 23 (`   again. *If done:* matches appear as new output arrives.`) insert:

```markdown
   **Done (Plan 2):** matches appear while Claude is still writing, in
   Claude Code panes too — before, the find bar found nothing there.
```

and after the line `   "next/previous" jumps are fast even in huge output.` (line 26 before your insertion) insert:

```markdown
   **Done (Plan 2):** a lowercase search ignores case, a `.*` button
   switches to patterns, and next/previous steps through the list already
   found.
```

- [ ] **Step 7: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/CHANGELOG.md packages/terminal/README.md TERMINAL.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/terminal/2026-09-24-not-done-plain-language.md && git commit -m "docs(terminal): find keeps up — changelog, TERMINAL.md 4.28, survey status

<Co-Authored-By trailer from your harness>"
```

---

### Task 9: Push and report

**Files:** none.

- [ ] **Step 1: Push the branch (do not merge, do not open a PR unless asked)**

```bash
cd "$(git rev-parse --show-toplevel)" && git status --short && git log --oneline origin/development..HEAD && git push -u origin terminal/plan-2-search
```
Expected: `git status --short` prints nothing; the log shows the commits of Tasks 1–6 and 8 (seven commits, six if Task 6 found `vt_host.wasm` unchanged); the push ends with `branch 'terminal/plan-2-search' set up to track 'origin/terminal/plan-2-search'`.

- [ ] **Step 2: Completion report**

Reply with, in this order:
1. Branch name and the `git log --oneline origin/development..HEAD` output.
2. Every gate with its result, each either **passed** with the command's last output line(s) copied verbatim, or **not run** with the exact reason: `cargo fmt --check`, `cargo clippy`, `cargo test`, `npm run build:wasm -- --force`, `npm run build:ts`, the five vitest suites (counts), `npm run check:boundaries`, frontend `tsc` + `BlockTerminal.test.tsx`, `bench:feel` (against the Task 0 recording), `bench:selection`, `bench:agent:gate`, `bench:agent:scroll`, `bench:affordances` ×3, `bench:terminal … find-500k` (p95, sensitivity), `bench:find-update` (three JSON lines), `vt_host.wasm` hash before/after, pty-host `go test`, `build:daemon`.
3. Any line-number drift you found against this plan, and anything you changed beyond it (with the reason).
4. What was not verified here and is left to the reviewer: the real-app check — open a Claude Code pane in Operator (`npm run tauri:dev` with a scrubbed environment, `RUN_APP_COMMANDS.md`), press Cmd+F while Claude is streaming, type a word that is about to appear, and confirm the count grows without retyping, Enter/Shift+Enter stay on the chosen hit while output streams, `error` finds `Error`, and the `.*` toggle works; restart the daemon and the app first so both wasm builds are live (`TERMINAL.md` §3 rule 5).
