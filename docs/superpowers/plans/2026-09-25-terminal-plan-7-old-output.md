# Terminal Plan 7 — Very Old Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **If the superpowers skills are not installed in your environment, run the same process by hand:** one fresh implementer subagent per task (give it the task text, Global Constraints and Review Focus), then one spec-compliance review subagent and one code-quality review subagent per task, fix what they find, and after the last task one whole-branch review subagent over `git diff origin/development...HEAD`.

**Goal:** rows the pty-host mirror evicts past its 200,000-row / 128 MiB cap are kept, as SGR-styled text, in a 32 MiB cold ring per terminal, and a pane whose oldest row still has older rows behind it shows **Load older output** at the top of its scrollback; clicking it fetches up to 2,048 rows over the existing attach stream and prepends them as history rows.

**Architecture:** `vt-core` gains a byte-capped `ColdRing` that `Parser::trim_to` fills (serialising each trimmed row with the same SGR writer the replay and history chunks use, moved from `vt-host` into `vt-core::style_sgr`), an `older_chunk(before, max_rows, max_bytes)` that answers with an ordinary `OSC 7000;v=1;history=<first>,<count>;cols=<n>` chunk, and an `older_mark()` (`OSC 7000;v=1;older=<floor>`). The receiving core sizes its scratch screen to the chunk's `cols=` so a row wider than the pane lands whole, marks such rows stale so the existing lazy rewrap re-lays them at the pane's width, records the last `older=` floor, and no longer trims on a feed that committed no live rows (so loaded rows survive until the next live row). The pty-host sends the floor after the attach history (or after the frame for a client without history) and answers a new `MsgOlderReq{before}` on the requesting connection's stream; the daemon forwards a new mux frame `{ch:"terminal",type:"older",id,before}`; the renderer package owns the button (`mountLoadOlder`, string `TerminalStrings.loadOlderOutput`) and asks the host through a new optional seam `HostCapabilities.loadOlderOutput(beforeStableRow)`, which Operator implements with its mux transport.

**Tech Stack:** Rust 1.96.0 (`vt-core`, `vt-host`, `vt-wasm`, `terminal-marks`), wasm32 + wasm-bindgen 0.2.127, Go (pty-host, wazero, daemon mux), TypeScript (vitest/jsdom), React.

**Spec:** `docs/terminal/2026-09-24-terminal-roadmap-design.md` "Plan 7 — Very old output (§5.8)" and "Rules every plan obeys"; survey `docs/terminal/2026-09-19-terminal-reference-survey.md` §5.8 (and §1.13). The user's fixed decisions for this plan (2026-09-25) override the roadmap where they differ: the ring size is a **constant** (32 MiB per terminal), not a setting; the ring is not compressed.

**Shared files other wave-2 plans also touch** (expect merge conflicts; the reviewer resolves them after merge): `packages/terminal/crates/vt-core/src/lib.rs` (Plan 3 OSC dispatch), `crates/vt-core/src/history.rs` (Plan 3), `crates/vt-core/src/parser.rs`, `crates/marks/src/{event,scanner}.rs`, `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` (**binary: Plan 3 rebuilds it too — after merging both, rebuild it once from the merged tree, never pick one side**), `packages/terminal/ts/core/src/types.ts` (`TerminalStrings`, `HostCapabilities`; Plan 5 may add strings), `packages/terminal/ts/react/src/TerminalSurface.tsx` (Plan 5 marks), `packages/terminal/ts/renderer-dom/src/index.ts`, `frontend/src/renderer/components/BlockTerminal.tsx`, `packages/terminal/CHANGELOG.md`, `TERMINAL.md`, the survey and the plain-language doc. After merge, `crates/vt-core/src/lib.rs` must still be ≤ 600 lines (this plan leaves it at 580).

## Global Constraints

- Work on branch `terminal/plan-7-old-output` created from `origin/development` (`5185f35be` when this plan was written). Never commit to `development` or `master`, never merge, never force-push.
- Commits name explicit paths only: `git add <path> …`. Never `git add -A`, `git add .`, `git commit -a` or `git stash`.
- Every commit message ends with the trailer line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- No comments in new code (Rust, Go, TS, tests). Moving existing code may drop a comment that would become false; do not add any.
- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no Operator name, path or concept under `crates/` or `ts/`. The 32 MiB constant lives in Operator's Go (`mirror_limits.go`), not in the package.
- No file under `packages/terminal` may exceed 600 lines (`npm run check:boundaries`).
- Kitty is GPL-3.0: **clean-room only**. Do not open, read or copy any Kitty source. The behaviour this plan implements is the survey §5.8 description (rows falling off the cap serialised as styled text into a byte-capped ring). No code is adapted from any reference, so no attribution file is needed.
- Specs, docs and the completion report cite `file:line` or write "not known". Numbers in docs come from runs you did in this environment, quoted.
- A `vt-core` change is not live until **both** wasm artifacts are rebuilt (`TERMINAL.md` §6): the renderer's (`npm run build:wasm -- --force`, gitignored) and the host mirror's (`cargo build --release -p vt-host --target wasm32-unknown-unknown`, copied to `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`, **committed**), then the pty-host Go tests.
- Feel baselines: record a baseline of the **unmodified** tree in Task 0 in this environment and compare against it. Never commit re-recorded baselines (`packages/terminal/bench/agent-session/baselines/**`). `npm run bench:affordances` rewrites committed PNGs — restore them with `git checkout -- packages/terminal/bench/agent-session/baselines` after every run.
- This plan changes no pixels: the button is only in the DOM when a host provides `loadOlderOutput` **and** a floor mark has arrived, which never happens in the bench harness. `bench:feel` must stay at zero diff against the Task 0 baseline.
- New `TERMINAL.md` section number: **§4.33**.
- Tool gaps are reported, not hidden: when a command cannot run, write `not run: <reason>` in the completion report.

## Review Focus

1. **A load while output is streaming.** The answer is labelled to end at the pane's first stable row at click time; live rows that arrive first make the pane trim, and the chunk no longer abuts, so `Parser::apply_history_chunk` drops it silently. Expected: nothing breaks, the floor mark still clears the pending state and the button comes back. Pinned by `TerminalSurface.older.test.tsx` (pending clears on the mark) and `loaded_rows_stay_until_the_next_committed_row`; documented in `TERMINAL.md` §5.
2. **Loaded rows vs the pane's own cap.** Loaded rows are over the renderer's cap on purpose; the next feed that commits a live row trims back to 200,000 rows and drops them first, and the button reappears. Pinned by `loaded_rows_stay_until_the_next_committed_row` (Rust) and `reappears once the pane's own cap trims the loaded rows again` (renderer-dom).
3. **A cold row wider than the pane** (the window was narrowed after the row was evicted). It must land whole and rewrap on view, never be clipped or wrap inside the receiver's scratch screen. Pinned by `a_wide_chunk_lands_whole_in_a_narrow_pane_and_rewraps_when_touched`.
4. **Prepending into a core that has already trimmed.** `Content::drop_before` frees whole 4 KiB chunks only, so the first retained row may start inside a live chunk; a prepend then left a gap (`RowsNotContiguous`). Found while proving this plan; fixed by `Content::trim_front_to` and pinned by the content unit tests plus four integration tests that panicked before the fix.
5. **Memory.** The ring counts payload + 8 bytes per row against its cap and reserves the full cap once, on the first spilled row, so the wasm heap grows by ~1.2× the cap, not 2× (measured: 77.6 MB with a full ring vs 36.0 MB without, and 101.2 MB before the reserve). Pinned by `the_byte_count_never_passes_the_cap` (also asserts capacity == cap) and the Go `TestTheColdRingNeverPassesItsCap`.

---

## Design decisions (each one decided; evidence in brackets)

- **Where rows go:** the ring lives in `Parser` and is filled in `Parser::trim_to` (`crates/vt-core/src/parser/history.rs:86-111` on `5185f35be`), the single place scrollback rows are dropped for both the row and the byte cap. Rows are serialised with the replay/history writer (`write_styled_row_with`, today `crates/vt-host/src/sgr.rs:12-46`), moved verbatim into `vt-core::style_sgr` so there is one writer; each row carries its indent as leading spaces, exactly as `vt_history_chunk` writes it (`crates/vt-host/src/lib.rs:494-513`). OSC 8 links travel as their URI, so they re-intern in the receiving core. Block marks (`id=`/`cmd=`/`exit=`) are **not** kept: loaded rows are plain history rows.
- **Ring layout:** one `VecDeque<u8>` of row bytes plus a `VecDeque<(u32 len, u16 cols)>`; `bytes() = data + 8 × rows` must stay ≤ cap; the oldest rows are popped **before** pushing so the buffer never passes the cap, and the full cap is reserved on the first push. A row larger than the cap empties the ring. A gap in stable rows (a history prepend into the mirror, `adopt_origin`) restarts the ring at the new front, so `ring.end == trimmed_total` always holds while the ring is non-empty. [Measured before the reserve: 101,187,584 bytes wasm with a full ring; after: 77,594,624; without a ring 35,979,264.]
- **Size:** `32 << 20` bytes, a Go constant `mirrorColdRingBytes` in `backend/internal/adapters/runtime/ptyhost/mirror_limits.go`, carried by a new `vtwasm.Limits.ColdRingBytes` field; zero disables the ring (every existing test fixture). Not a setting (user decision).
- **Not persisted** (Plan 4's `persist.go` is unchanged): the saved file is capped at `persistMaxBytes = 4 << 20` (`persist.go:23`) and holds only the newest 20 history chunks (`persist.go:22`); cold rows are older than 200,000 rows, so they could never fit, and writing up to 32 MiB every 60 s (`persist.go:21`) would be disk churn for rows the saved file already cannot reach. After a crash-restore the ring starts empty; its floor equals the restored front, so no button shows.
- **What a click fetches:** one chunk of up to `OLDER_CHUNK_ROWS = 2_048` rows, bounded by a 1 MiB byte budget (the Go render buffer, `vtwasm.go:190`) and a cell budget of `2_048 × 128` cells for the receiver's scratch screen (`ScreenGrid::new(rows + 1, cols)`, `crates/vt-core/src/history.rs:50`), newest rows first. **One** chunk per click, not four 512-row chunks: every applied history chunk marks the renderer's export full (`parser/history.rs:69`), and a full export at 200k rows costs ~0.9-1.0 s, so four chunks drained over two frames paid it twice. [Measured in Task 8's method: host side 0.57 ms for 2,048 rows from a full ring, 0.99 ms from the mirror's own history on `claude-long-50k`; renderer feed of the 245 KB answer 20.8-32.2 ms, then one full re-export 885.7-948.4 ms, the same order as a first full export of 200k rows (918.3-1,051.1 ms).]
- **Addressing:** stable rows. The pane asks for rows before its own first stable row; the mirror answers from its own history if that row is newer than the mirror's front (pane ahead), otherwise from the ring. The chunk is labelled so it ends exactly at the requested row, which is what `Parser::apply_history_chunk` requires (`parser/history.rs:28`). With one client at one width the two row spaces are identical; when the mirror ran at a different width than the pane (a larger phone or desktop attached, a resize while rows were being evicted) the seam can repeat or skip rows — documented in `TERMINAL.md` §5, not fixed.
- **Wide rows:** the chunk mark carries `cols=<n>` (the widest row, measured as max(scalar, grapheme) width + indent); the receiver sizes its scratch screen to `max(pane cols, n)` (capped by `MAX_DIMENSION = 1000`, `screen.rs:14`) and marks the prepended rows stale at `n` so `touch_rows`/the export window rewraps them (`row_index.rs` stale runs). Never clipped.
- **Transport:** the existing attach stream (in-band, like the attach history chunks). New pty-host message `MsgOlderReq = 0x12` with JSON `{"before":N}` on the client's own connection; the answer is one `MsgTerminalData` frame `chunk + older-mark` queued to that connection only and counted in `delivered` (flow control). New optional port `ports.OlderOutputRequester{RequestOlder(before uint64) error}` implemented by `loopbackStream`, asserted like `ports.FlowControlled`. New mux client frame `older` (`before` > 0).
- **Knowing that older rows exist:** in-band mark `OSC 7000;v=1;older=<floor>` = the oldest stable row the mirror can serve (ring front, or the mirror's front when the ring is empty). Sent (only when the ring is enabled) after the last attach-history chunk, after the frame for a sized client that did not ask for history, and at the end of every older answer. The core records it (`TerminalCore::older_state() -> OlderState { floor, marks }`, `marks` counts every mark so the button can tell an answer arrived even when the floor did not move). No floor = no button, so an old daemon or a host without a ring never shows it.
- **Renderer cap (decision 3):** the renderer core keeps its limits. `TerminalCore::feed_raw` now trims only when the feed committed a live row (`Parser::committed_rows`), so loaded rows stay until the next live row (or a resize, which still trims); they are then the first rows trimmed, and the button comes back because the pane's front is again above the floor.
- **Button:** `ts/renderer-dom/src/load-older.ts`, framework-free like `jump-to-bottom.ts`: an absolutely positioned `<button data-terminal-load-older>` appended to the scroll container, so it sits at the top of the scrollback and scrolls away with it. Visible iff the host can load, the alternate screen is off, a floor is known and `floor < firstStableRow`, and no request is pending. Click → `load(firstStableRow)` and hide; a pending request clears when `marks` or `firstStableRow` changes, or after `LOAD_OLDER_RETRY_MS = 10_000`. `TerminalSurface` mounts it after the find bar, updates it on every `renderer.onPaint`, relabels it from `strings`, and disposes it (listener, timer, node) before the renderer. The scroll position stays put because `ScrollTracker` anchors to a stable row (`TERMINAL.md` §4.18); `dom-block-renderer.older.test.ts` proves the anchored row does not move.
- **Seam:** `HostCapabilities.loadOlderOutput?(beforeStableRow: number): void` (fire-and-forget; the rows arrive on the byte stream). Operator: `useTerminalSession`'s transport gains `requestOlder(before)` (ignored unless attached, `before > 0`), `BlockTerminalTransport.requestOlder?`, and `BlockTerminal` sets `host.loadOlderOutput` only when the transport has it; string `t("blocks.loadOlderOutput", { defaultValue: "Load older output" })` (no i18n JSON edit, matching `jumpToBottom`).
## File map

| File | Task | Responsibility |
|---|---|---|
| `packages/terminal/crates/marks/src/{event.rs,scanner.rs}`, `tests/vectors.rs` | 1 | `HistoryChunk.cols`, `OlderFloor(u64)` |
| `packages/terminal/crates/vt-core/src/cold_ring.rs` (new) | 1 | the byte-capped ring |
| `packages/terminal/crates/vt-core/src/parser/cold.rs` (new) | 1 | spill on trim, serialise a row, serve older rows |
| `packages/terminal/crates/vt-core/src/older.rs` (new) | 1 | `TerminalCore` API: ring config, stats, floor, mark, chunk; `OlderState` |
| `packages/terminal/crates/vt-core/src/style_sgr.rs` (moved from `vt-host/src/sgr.rs`) | 1 | the one SGR row writer |
| `packages/terminal/crates/vt-core/src/{lib.rs,parser.rs,parser/history.rs,history.rs,content.rs,row_index.rs,event_bridge.rs}` | 1 | wiring, trim gating, wide/stale prepend, content front trim |
| `packages/terminal/crates/vt-core/tests/cold_ring.rs` (new) | 1 | behaviour tests |
| `packages/terminal/crates/vt-host/src/{lib.rs,older.rs}` | 1, 2 | C-ABI exports |
| `backend/internal/adapters/runtime/ptyhost/vtwasm/{vtwasm.go,older.go,older_test.go}`, `assets/vt_host.wasm` | 2 | Go wrapper |
| `backend/internal/adapters/runtime/ptyhost/{proto.go,mirror_limits.go,host.go,attach.go,older.go,older_test.go,attach_replay_test.go}` | 3 | host protocol |
| `backend/internal/ports/outbound.go`, `backend/internal/terminal/{protocol.go,manager.go,attachment.go,fakes_test.go,manager_test.go}` | 4 | daemon mux |
| `packages/terminal/crates/vt-wasm/src/lib.rs`, `ts/core/src/{types.ts,index-browser.ts,terminal-core.ts,older-output.test.ts}`, `ts/renderer-dom/src/{jump-to-bottom,palette}.test.ts` | 5 | renderer core API, string, seam |
| `packages/terminal/ts/renderer-dom/src/{load-older.ts,load-older.test.ts,index.ts,dom-block-renderer.older.test.ts}`, `ts/react/src/{TerminalSurface.tsx,TerminalSurface.older.test.tsx}` | 6 | button |
| `frontend/src/renderer/{lib/terminal-mux.ts,lib/terminal-mux.test.ts,hooks/useTerminalSession.ts,hooks/useTerminalSession.test.tsx,components/BlockTerminal.tsx,components/BlockTerminal.test.tsx,components/TerminalPane.test.tsx}` | 7 | Operator seam |
| `backend/internal/adapters/runtime/ptyhost/vtwasm/older_report_test.go`, `docs/superpowers/specs/2026-09-25-old-output-measurement.md` | 8 | measurement |
| `packages/terminal/CHANGELOG.md`, `TERMINAL.md`, survey, plain-language doc | 10 | docs |

Line counts after this plan (all ≤ 600): `vt-core/src/lib.rs` 580, `vt-core/src/parser.rs` 534, `vt-host/src/lib.rs` 558, `vt-wasm/src/lib.rs` 572, `ts/core/src/terminal-core.ts` 573, `ts/react/src/TerminalSurface.tsx` 454.

---

### Task 0: Branch, toolchains, baselines

**Files:** none committed.

- [ ] **Step 1: Branch**

```bash
export REPO="$(git rev-parse --show-toplevel)"
cd "$REPO" && git fetch origin && git checkout -b terminal/plan-7-old-output origin/development
git log --oneline -1
```
Expected: the first line of `origin/development` (it was `5185f35be test: stop two timing races under load` when this plan was written; if it moved, the patches below still apply with `--recount` as long as the quoted context is unchanged — if a hunk does not apply, apply it by hand from its context lines and note it in the report).

- [ ] **Step 2: Toolchains** (each command, then its expected output)

```bash
cd "$REPO/packages/terminal" && rustup show active-toolchain && rustup target list --installed | grep wasm32
```
Expected: `1.96.0-…` and `wasm32-unknown-unknown` (from `rust-toolchain.toml`; `rustup` installs them on first use).

```bash
wasm-bindgen --version || cargo install wasm-bindgen-cli --version 0.2.127 --locked
wasm-bindgen --version
```
Expected: `wasm-bindgen 0.2.127` exactly (`scripts/build-wasm.mjs` refuses any other).

```bash
cd "$REPO/backend" && GOTOOLCHAIN=auto go version
```
Expected: a Go version satisfying `backend/go.mod`. If direct downloads are blocked, `GOTOOLCHAIN=auto` fetches the toolchain through the module proxy; export `GOTOOLCHAIN=auto` for the whole session.

```bash
golangci-lint --version || GOTOOLCHAIN=auto go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest
```
Expected: a v2 version (`backend/.golangci.yml` is `version: "2"`). If it cannot be installed: `not run: golangci-lint unavailable` in the report.

```bash
cd "$REPO/packages/terminal" && npm ci --no-audit --no-fund
cd "$REPO/frontend" && npm ci --no-audit --no-fund
cd "$REPO/packages/terminal" && npx playwright install chromium
```
If `playwright install` fails with HTTP 403 (CDN blocked): find the preinstalled Chromium (`ls /opt/pw-browsers`), read the revision directory names Playwright wants from the error message (`chromium-<rev>`, `chromium_headless_shell-<rev>`), and symlink each wanted directory name under `/opt/pw-browsers` to the preinstalled one of the same kind (outside the repository), e.g. `ln -s /opt/pw-browsers/chromium-<have> /opt/pw-browsers/chromium-<want>`, then `export PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers`. Never commit anything for this.

- [ ] **Step 3: Baselines of the unmodified tree**

```bash
cd "$REPO/packages/terminal" && cargo test 2>&1 | grep -E "test result" | grep -v " 0 failed" ; echo "rust-baseline-done"
npm run build:wasm -- --force && npm run build:ts
for p in core renderer-dom react editor; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  "); done
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... 2>&1 | tail -5
cd "$REPO/frontend" && npx vitest run 2>&1 | grep -E "Test Files|Tests  "
```
Expected: no Rust line other than `0 failed`; every vitest line `passed`; Go `ok`. Record the counts. `TestProcessEnvironmentLetsOverridesWin` in `ptyhost` is a known pre-existing failure (`TERMINAL.md` §5); if it fails here, it is not yours.

```bash
cd "$REPO/packages/terminal" && npm run bench:feel -- --record
git -C "$REPO" status --short packages/terminal/bench/agent-session/baselines | head
```
The re-recorded PNGs are this machine's baseline. **Leave them unstaged for the whole branch** (never `git add` that directory); every later `npm run bench:feel` compares against them. Task 11 restores them with `git checkout`.

---
### Task 1: vt-core cold ring, older chunks, floor mark, wide prepend

**Files:**
- Create: `packages/terminal/crates/vt-core/tests/cold_ring.rs`, `packages/terminal/crates/vt-core/src/cold_ring.rs`, `packages/terminal/crates/vt-core/src/parser/cold.rs`, `packages/terminal/crates/vt-core/src/older.rs`
- Move: `packages/terminal/crates/vt-host/src/sgr.rs` → `packages/terminal/crates/vt-core/src/style_sgr.rs`
- Modify: `packages/terminal/crates/marks/src/event.rs:39-42`, `packages/terminal/crates/marks/src/scanner.rs:174-218` (+ tests), `packages/terminal/crates/marks/tests/vectors.rs:74`, `packages/terminal/crates/vt-core/src/{lib.rs,parser.rs,parser/history.rs,history.rs,content.rs,row_index.rs,event_bridge.rs}`, `packages/terminal/crates/vt-host/src/lib.rs:1-9`

**Interfaces:**
- Produces (Rust, `vt_core`): `TerminalCore::set_cold_ring_bytes(&mut self, cap: usize)`, `cold_stats(&self) -> ColdStats { rows, bytes, cap, first_stable_row }`, `cold_floor(&self) -> Option<u64>`, `older_mark(&self) -> Option<Vec<u8>>`, `older_chunk(&self, before: u64, max_rows: usize, max_bytes: usize) -> Option<OlderChunk { first_stable_row: u64, rows: usize, bytes: Vec<u8> }>`, `older_state(&self) -> OlderState { floor: Option<u64>, marks: u32 }`; constants `vt_core::OLDER_CHUNK_ROWS = 2_048`, `vt_core::older::OLDER_CELL_BUDGET = 2_048 * 128`; module `vt_core::style_sgr::{write_styled_row, write_styled_row_with}`.
- Produces (marks): `MarkEvent::HistoryChunk { first_stable_row, rows, cols: Option<usize> }`, `MarkEvent::OlderFloor(u64)`.
- Wire formats: chunk `ESC ] 7000;v=1;history=<first>,<count>;cols=<n> ESC \` then `<count>` rows each ending `\r\n`; floor `ESC ] 7000;v=1;older=<floor> ESC \`.

- [ ] **Step 1: Write the failing integration tests**

Create `packages/terminal/crates/vt-core/tests/cold_ring.rs` with exactly this content:

```bash
mkdir -p "$REPO/packages/terminal/crates/vt-core/tests"
cat > "$REPO/packages/terminal/crates/vt-core/tests/cold_ring.rs" <<'PLAN7_EOF'
mod common;

use vt_core::{CellStyle, Limits, TerminalCore, OLDER_CHUNK_ROWS};

const RING: usize = 1 << 20;
const OUT: usize = 1 << 20;

fn mirror(cols: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::with_limits(
        cols,
        Limits {
            rows,
            bytes: usize::MAX,
        },
    )
    .expect("core");
    core.set_reflow_on_resize(false);
    core.resize(cols, 3);
    core.set_cold_ring_bytes(RING);
    core
}

fn pane(cols: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::with_limits(
        cols,
        Limits {
            rows,
            bytes: usize::MAX,
        },
    )
    .expect("core");
    core.resize(cols, 3);
    core.set_grapheme_clusters(true);
    core
}

fn texts(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().expect("snapshot");
    let mut rows: Vec<String> = (0..snapshot.row_count())
        .map(|index| snapshot.row_text(index).to_string())
        .collect();
    while rows.last().is_some_and(|row| row.is_empty()) {
        rows.pop();
    }
    rows
}

fn styles(core: &TerminalCore, row: usize) -> Vec<(u32, CellStyle)> {
    core.snapshot()
        .expect("snapshot")
        .row_style_pairs(row)
        .to_vec()
}

fn numbered(count: usize) -> Vec<u8> {
    let mut out = Vec::new();
    for index in 0..count {
        if index % 3 == 0 {
            out.extend_from_slice(format!("\x1b[31;1mrow {index:05}\x1b[0m plain\r\n").as_bytes());
        } else {
            out.extend_from_slice(format!("row {index:05} plain\r\n").as_bytes());
        }
    }
    out
}

fn load_all_older(source: &TerminalCore, target: &mut TerminalCore) {
    loop {
        let before = target.first_stable_row();
        let Some(chunk) = source.older_chunk(before, OLDER_CHUNK_ROWS, OUT) else {
            break;
        };
        target.feed(&chunk.bytes);
        if target.first_stable_row() != chunk.first_stable_row {
            break;
        }
    }
    target.feed(&source.older_mark().expect("ring is on"));
}

#[test]
fn evicted_rows_land_in_the_ring_in_order_with_their_styles() {
    let mut core = mirror(40, 10);
    core.feed(&numbered(30));
    let stats = core.cold_stats();
    assert_eq!(
        core.first_stable_row(),
        stats.first_stable_row + stats.rows as u64
    );
    assert_eq!(stats.first_stable_row, 0);
    let chunk = core
        .older_chunk(core.first_stable_row(), OLDER_CHUNK_ROWS, OUT)
        .expect("older rows exist");
    let text = String::from_utf8(chunk.bytes).expect("utf-8");
    let first = text.find("row 00000").expect("oldest row present");
    let second = text.find("row 00001").expect("second row present");
    let last = text
        .find(&format!("row {:05}", stats.rows - 1))
        .expect("newest evicted row present");
    assert!(first < second && second < last, "{text:?}");
    assert!(
        text.contains("\x1b[0m\x1b[1;31mrow 00000\x1b[0m plain"),
        "{text:?}"
    );
    assert_eq!(chunk.first_stable_row, 0);
    assert_eq!(chunk.rows, stats.rows);
    common::check(&core);
}

#[test]
fn the_ring_never_grows_past_its_cap_and_drops_the_oldest() {
    let cap = 4 * 1024;
    let mut core = TerminalCore::with_limits(
        40,
        Limits {
            rows: 20,
            bytes: usize::MAX,
        },
    )
    .expect("core");
    core.resize(40, 3);
    core.set_cold_ring_bytes(cap);
    for index in 0..2_000 {
        core.feed(format!("line {index:05}\r\n").as_bytes());
        let stats = core.cold_stats();
        assert!(stats.bytes <= cap, "{stats:?}");
    }
    let stats = core.cold_stats();
    assert!(stats.first_stable_row > 0, "{stats:?}");
    assert_eq!(core.cold_floor(), Some(stats.first_stable_row));
    assert_eq!(
        stats.first_stable_row + stats.rows as u64,
        core.first_stable_row()
    );
    let chunk = core
        .older_chunk(core.first_stable_row(), OLDER_CHUNK_ROWS, OUT)
        .expect("rows");
    let text = String::from_utf8(chunk.bytes).expect("utf-8");
    assert!(!text.contains("line 00000"), "the oldest row was dropped");
}

#[test]
fn a_chunk_reads_rows_oldest_to_newest_ending_at_before() {
    let mut core = mirror(40, 10);
    core.feed(&numbered(40));
    let chunk = core.older_chunk(20, 5, OUT).expect("rows 15..20");
    assert_eq!(chunk.first_stable_row, 15);
    assert_eq!(chunk.rows, 5);
    let text = String::from_utf8(chunk.bytes).expect("utf-8");
    assert!(
        text.starts_with("\x1b]7000;v=1;history=15,5;cols=15\x1b\\"),
        "{text:?}"
    );
    let order: Vec<usize> = (15..20)
        .map(|index| text.find(&format!("row {index:05}")).expect("row"))
        .collect();
    assert!(order.windows(2).all(|pair| pair[0] < pair[1]), "{text:?}");
    assert_eq!(text.matches("\r\n").count(), 5);
}

#[test]
fn nothing_older_than_the_floor_returns_no_chunk() {
    let mut core = mirror(40, 10);
    core.feed(&numbered(30));
    let floor = core.cold_floor().expect("ring is on");
    assert!(core.older_chunk(floor, OLDER_CHUNK_ROWS, OUT).is_none());
    assert_eq!(
        core.older_mark().expect("ring is on"),
        format!("\x1b]7000;v=1;older={floor}\x1b\\").into_bytes()
    );
}

#[test]
fn a_core_without_a_ring_offers_nothing_older() {
    let mut core = TerminalCore::new(40, 10).expect("core");
    core.feed(&numbered(30));
    assert_eq!(core.cold_floor(), None);
    assert_eq!(core.older_mark(), None);
    assert!(core
        .older_chunk(core.first_stable_row(), OLDER_CHUNK_ROWS, OUT)
        .is_none());
}

#[test]
fn evicted_rows_load_back_with_their_text_and_styles() {
    let bytes = numbered(120);
    let mut reference = TerminalCore::new(40, 10_000).expect("core");
    reference.resize(40, 3);
    reference.feed(&bytes);
    let mut source = mirror(40, 50);
    source.feed(&bytes);
    let mut target = pane(40, 50);
    target.feed(&bytes);
    assert_eq!(target.first_stable_row(), source.first_stable_row());
    let before = target.first_stable_row() as usize;

    load_all_older(&source, &mut target);

    assert_eq!(target.first_stable_row(), 0);
    assert_eq!(texts(&target), texts(&reference));
    for row in 0..before {
        assert_eq!(styles(&target, row), styles(&reference, row), "row {row}");
    }
    assert_eq!(target.older_state().floor, Some(0));
    common::check(&target);
}

#[test]
fn wide_characters_and_graphemes_survive_the_ring() {
    let lines = [
        "漢字かな交じり文",
        "family 👨‍👩‍👧 heart ❤️ flag 🇪🇬",
        "e\u{301}cole café",
        "plain ascii",
    ];
    let mut bytes = Vec::new();
    for line in lines {
        bytes.extend_from_slice(format!("{line}\r\n").as_bytes());
    }
    bytes.extend_from_slice(&numbered(20));
    let mut source = mirror(60, 10);
    source.feed(&bytes);
    let mut target = pane(60, 10);
    target.feed(&bytes);
    load_all_older(&source, &mut target);
    let rows = texts(&target);
    for (index, line) in lines.iter().enumerate() {
        assert_eq!(rows[index], *line);
    }
    common::check(&target);
}

#[test]
fn a_wide_chunk_lands_whole_in_a_narrow_pane_and_rewraps_when_touched() {
    let long = "abcdefghij".repeat(6);
    let mut bytes = Vec::new();
    for index in 0..40 {
        bytes.extend_from_slice(format!("{index:02}{long}\r\n").as_bytes());
    }
    let mut source = mirror(80, 20);
    source.feed(&bytes);
    let chunk = source
        .older_chunk(source.first_stable_row(), 4, OUT)
        .expect("rows");
    assert!(String::from_utf8_lossy(&chunk.bytes).contains(";cols=62\x1b\\"));

    let mut target = pane(20, 10_000);
    target.feed(b"\x1b]7000;v=1;origin=");
    target.feed(format!("{}\x1b\\", source.first_stable_row()).as_bytes());
    target.feed(b"live\r\n");
    target.feed(&chunk.bytes);
    assert_eq!(target.first_stable_row(), chunk.first_stable_row);
    let snapshot = target.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0).len(), 62);
    assert!(target.stale_row_count() >= 4);

    target.touch_rows(0..usize::MAX);
    assert_eq!(target.stale_row_count(), 0);
    let joined: String = texts(&target)
        .iter()
        .take_while(|row| *row != "live")
        .cloned()
        .collect();
    let expected: String = (chunk.first_stable_row..chunk.first_stable_row + 4)
        .map(|index| format!("{index:02}{long}"))
        .collect();
    assert_eq!(joined, expected);
    common::check(&target);
}

#[test]
fn loaded_rows_stay_until_the_next_committed_row() {
    let bytes = numbered(100);
    let mut source = mirror(40, 50);
    source.feed(&bytes);
    let mut target = pane(40, 50);
    target.feed(&bytes);
    let front = target.first_stable_row();
    let chunk = source
        .older_chunk(front, OLDER_CHUNK_ROWS, OUT)
        .expect("rows");
    target.feed(&chunk.bytes);
    assert_eq!(target.first_stable_row(), front - chunk.rows as u64);
    target.feed(b"typing");
    assert_eq!(target.first_stable_row(), front - chunk.rows as u64);
    target.feed(b"\r\n");
    assert!(
        target.first_stable_row() > front,
        "the next committed row trims back to the cap"
    );
    assert_eq!(target.memory_stats().rows, 49);
    common::check(&target);
}

#[test]
fn an_older_mark_records_the_floor_and_counts_every_mark() {
    let mut core = pane(40, 50);
    assert_eq!(core.older_state().floor, None);
    assert_eq!(core.older_state().marks, 0);
    core.feed(b"\x1b]7000;v=1;older=12\x1b\\");
    core.feed(b"\x1b]7000;v=1;older=12\x1b\\");
    assert_eq!(core.older_state().floor, Some(12));
    assert_eq!(core.older_state().marks, 2);
    assert!(texts(&core).is_empty(), "the mark prints nothing");
}

#[test]
fn a_history_prepend_restarts_the_ring_at_the_new_front() {
    let mut core = mirror(40, 1_000);
    core.feed(b"\x1b]7000;v=1;origin=500\x1b\\live\r\n");
    core.feed(b"\x1b]7000;v=1;history=498,2\x1b\\one\r\ntwo\r\n");
    assert_eq!(core.first_stable_row(), 498);
    assert_eq!(core.cold_floor(), Some(498));
    assert_eq!(core.cold_stats().rows, 0);
}

#[test]
fn rows_the_mirror_still_holds_are_served_when_the_pane_is_ahead() {
    let mut source = mirror(40, 100);
    source.feed(&numbered(30));
    assert_eq!(source.first_stable_row(), 0);
    let chunk = source.older_chunk(10, 4, OUT).expect("history rows 6..10");
    assert_eq!(chunk.first_stable_row, 6);
    let text = String::from_utf8(chunk.bytes).expect("utf-8");
    assert!(
        text.contains("row 00006") && text.contains("row 00009"),
        "{text:?}"
    );
    assert!(!text.contains("row 00010"), "{text:?}");
}

#[test]
fn a_chunk_keeps_to_its_byte_budget_newest_rows_first() {
    let mut core = mirror(40, 10);
    core.feed(&numbered(60));
    let before = core.first_stable_row();
    let chunk = core
        .older_chunk(before, OLDER_CHUNK_ROWS, 200)
        .expect("rows");
    assert!(chunk.bytes.len() <= 200, "{}", chunk.bytes.len());
    assert!(chunk.rows < 20);
    assert_eq!(chunk.first_stable_row + chunk.rows as u64, before);
}

#[test]
fn a_chunk_of_very_wide_rows_keeps_the_receivers_screen_small() {
    let mut core = mirror(1000, 10);
    let row = "w".repeat(1000);
    for _ in 0..600 {
        core.feed(format!("{row}\r\n").as_bytes());
    }
    let chunk = core
        .older_chunk(core.first_stable_row(), OLDER_CHUNK_ROWS, 4 << 20)
        .expect("rows");
    assert!(chunk.rows * 1000 <= vt_core::older::OLDER_CELL_BUDGET);
    assert!(chunk.rows >= 100);
}

#[test]
fn a_hyperlink_in_an_evicted_row_still_resolves_after_loading() {
    let mut bytes =
        b"see \x1b]8;;https://example.com/doc\x1b\\the docs\x1b]8;;\x1b\\ now\r\n".to_vec();
    bytes.extend_from_slice(&numbered(20));
    let mut source = mirror(40, 10);
    source.feed(&bytes);
    let mut target = pane(40, 10);
    target.feed(&bytes);
    load_all_older(&source, &mut target);
    let snapshot = target.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "see the docs now");
    let link = snapshot
        .row_style_pairs(0)
        .iter()
        .map(|(_, style)| style.link)
        .find(|link| *link != 0)
        .expect("a linked run");
    assert_eq!(snapshot.link_uri(link), Some("https://example.com/doc"));
}
PLAN7_EOF
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test cold_ring 2>&1 | tail -5
```
Expected: compile errors such as `no method named `set_cold_ring_bytes` found for struct `TerminalCore`` and `unresolved import `vt_core::OLDER_CHUNK_ROWS``.

- [ ] **Step 3: marks crate — `cols=` on history chunks and the `older=` floor event**

Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t1-marks.patch <<'PLAN7_PATCH'
diff --git a/packages/terminal/crates/marks/src/event.rs b/packages/terminal/crates/marks/src/event.rs
index d360b2376..b031dd981 100644
--- a/packages/terminal/crates/marks/src/event.rs
+++ b/packages/terminal/crates/marks/src/event.rs
@@ -39,7 +39,9 @@ pub enum MarkEvent {
     HistoryChunk {
         first_stable_row: u64,
         rows: usize,
+        cols: Option<usize>,
     },
+    OlderFloor(u64),
 }
 
 /// Stateful byte-level decoder. It survives across `feed` calls so a mark
diff --git a/packages/terminal/crates/marks/src/scanner.rs b/packages/terminal/crates/marks/src/scanner.rs
index 0b81fa00b..11130e7ab 100644
--- a/packages/terminal/crates/marks/src/scanner.rs
+++ b/packages/terminal/crates/marks/src/scanner.rs
@@ -172,6 +172,8 @@ fn extension_events(fields: ExtensionFields) -> Vec<MarkEvent> {
     let mut replay_ready = false;
     let mut origin: Option<u64> = None;
     let mut history: Option<(u64, usize)> = None;
+    let mut cols: Option<usize> = None;
+    let mut older: Option<u64> = None;
     for (key, value) in fields.pairs {
         match key.as_str() {
             "input-ready" => ready = true,
@@ -179,6 +181,8 @@ fn extension_events(fields: ExtensionFields) -> Vec<MarkEvent> {
             "ready" => replay_ready = value == "1",
             "origin" => origin = value.parse::<u64>().ok(),
             "history" => history = parse_history(&value),
+            "cols" => cols = value.parse::<usize>().ok().filter(|cols| *cols > 0),
+            "older" => older = value.parse::<u64>().ok(),
             _ => {
                 if key != "v" {
                     has_extension_field = true;
@@ -205,8 +209,12 @@ fn extension_events(fields: ExtensionFields) -> Vec<MarkEvent> {
         out.push(MarkEvent::HistoryChunk {
             first_stable_row,
             rows,
+            cols,
         });
     }
+    if let Some(floor) = older {
+        out.push(MarkEvent::OlderFloor(floor));
+    }
     out
 }
 
@@ -313,7 +321,8 @@ mod tests {
             events,
             vec![MarkEvent::HistoryChunk {
                 first_stable_row: 4096,
-                rows: 512
+                rows: 512,
+                cols: None
             }]
         );
     }
@@ -351,8 +360,69 @@ mod tests {
             events_only(s.feed(b"ory=7,3\x1b\\")),
             vec![MarkEvent::HistoryChunk {
                 first_stable_row: 7,
-                rows: 3
+                rows: 3,
+                cols: None
+            }]
+        );
+    }
+
+    #[test]
+    fn a_history_mark_carries_the_width_its_rows_need() {
+        let mut s = Scanner::new();
+        let events = events_only(s.feed(b"\x1b]7000;v=1;history=10,2;cols=180\x1b\\"));
+        assert_eq!(
+            events,
+            vec![MarkEvent::HistoryChunk {
+                first_stable_row: 10,
+                rows: 2,
+                cols: Some(180)
             }]
         );
     }
+
+    #[test]
+    fn a_zero_or_malformed_width_is_no_width() {
+        let mut s = Scanner::new();
+        for mark in [
+            b"\x1b]7000;v=1;history=10,2;cols=0\x1b\\".as_slice(),
+            b"\x1b]7000;v=1;history=10,2;cols=wide\x1b\\".as_slice(),
+        ] {
+            assert_eq!(
+                events_only(s.feed(mark)),
+                vec![MarkEvent::HistoryChunk {
+                    first_stable_row: 10,
+                    rows: 2,
+                    cols: None
+                }]
+            );
+        }
+    }
+
+    #[test]
+    fn an_older_mark_decodes_to_the_older_floor() {
+        let mut s = Scanner::new();
+        let events = events_only(s.feed(b"\x1b]7000;v=1;older=4096\x1b\\"));
+        assert_eq!(events, vec![MarkEvent::OlderFloor(4096)]);
+    }
+
+    #[test]
+    fn a_malformed_older_mark_emits_nothing() {
+        let mut s = Scanner::new();
+        assert_eq!(
+            events_only(s.feed(b"\x1b]7000;v=1;older=soon\x1b\\")),
+            vec![]
+        );
+    }
+
+    #[test]
+    fn older_and_cols_are_not_block_metadata() {
+        let mut s = Scanner::new();
+        let events = events_only(s.feed(b"\x1b]7000;v=1;older=3;cols=9\x1b\\"));
+        assert!(
+            !events
+                .iter()
+                .any(|event| matches!(event, MarkEvent::Extension(_))),
+            "older and cols must not reach the block grid as meta fields: {events:?}"
+        );
+    }
 }
diff --git a/packages/terminal/crates/marks/tests/vectors.rs b/packages/terminal/crates/marks/tests/vectors.rs
index b73cade1d..a03f02c7e 100644
--- a/packages/terminal/crates/marks/tests/vectors.rs
+++ b/packages/terminal/crates/marks/tests/vectors.rs
@@ -72,6 +72,7 @@ fn event_kind_tier(ev: &MarkEvent) -> (String, MarkTier) {
         MarkEvent::ReplayOrigin(_) => ("replay_origin".to_string(), MarkTier::Extension),
         MarkEvent::ReplayReady => ("replay_ready".to_string(), MarkTier::Extension),
         MarkEvent::HistoryChunk { .. } => ("history_chunk".to_string(), MarkTier::Extension),
+        MarkEvent::OlderFloor(_) => ("older_floor".to_string(), MarkTier::Extension),
     }
 }
 
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t1-marks.patch
```

- [ ] **Step 4: Move the SGR writer into vt-core**

```bash
cd "$REPO" && git mv packages/terminal/crates/vt-host/src/sgr.rs packages/terminal/crates/vt-core/src/style_sgr.rs
```
Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t1-style-sgr.patch <<'PLAN7_PATCH'
diff --git a/packages/terminal/crates/vt-core/src/style_sgr.rs b/packages/terminal/crates/vt-core/src/style_sgr.rs
--- a/packages/terminal/crates/vt-core/src/style_sgr.rs
+++ b/packages/terminal/crates/vt-core/src/style_sgr.rs
@@ -1,6 +1,6 @@
-use vt_core::{Attrs, CellStyle, StyleCode};
+use crate::style::{Attrs, CellStyle, StyleCode};
 
-pub(crate) fn write_styled_row<'a>(
+pub fn write_styled_row<'a>(
     text: &mut String,
     row_bytes: &[u8],
     pairs: &[(u32, CellStyle)],
@@ -9,7 +9,7 @@
     write_styled_row_with(text, row_bytes, pairs, link_uri, "\n");
 }
 
-pub(crate) fn write_styled_row_with<'a>(
+pub fn write_styled_row_with<'a>(
     text: &mut String,
     row_bytes: &[u8],
     pairs: &[(u32, CellStyle)],
@@ -45,9 +45,6 @@
     text.push_str(terminator);
 }
 
-// Mirrors the bit layout in vt-core's `style.rs` (`TAG_INDEXED`/`TAG_RGB`,
-// neither exported) since only `StyleCode`'s public accessors cross the
-// crate boundary.
 const TAG_INDEXED: u32 = 0x0100_0000;
 const TAG_RGB: u32 = 0x0200_0000;
 
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t1-style-sgr.patch
```
Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t1-vthost.patch <<'PLAN7_PATCH'
diff --git a/packages/terminal/crates/vt-host/src/lib.rs b/packages/terminal/crates/vt-host/src/lib.rs
--- a/packages/terminal/crates/vt-host/src/lib.rs
+++ b/packages/terminal/crates/vt-host/src/lib.rs
@@ -1,12 +1,11 @@
 mod block_marks;
-mod sgr;
 
 use std::cell::RefCell;
 use std::collections::HashMap;
 use vt_core::{CellStyle, TerminalCore};
 
 use block_marks::{write_block_close, write_block_open};
-use sgr::{write_styled_row, write_styled_row_with};
+use vt_core::style_sgr::{write_styled_row, write_styled_row_with};
 
 thread_local! {
     static CORES: RefCell<HashMap<u32, TerminalCore>> = RefCell::new(HashMap::new());
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t1-vthost.patch
```

- [ ] **Step 5: The ring**

Create `packages/terminal/crates/vt-core/src/cold_ring.rs` with exactly this content:

```bash
mkdir -p "$REPO/packages/terminal/crates/vt-core/src"
cat > "$REPO/packages/terminal/crates/vt-core/src/cold_ring.rs" <<'PLAN7_EOF'
use std::collections::VecDeque;
use std::ops::Range;

pub const COLD_ROW_OVERHEAD_BYTES: usize = std::mem::size_of::<(u32, u16)>();

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ColdRow {
    pub bytes: Vec<u8>,
    pub cols: usize,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ColdStats {
    pub rows: usize,
    pub bytes: usize,
    pub cap: usize,
    pub first_stable_row: u64,
}

#[derive(Debug, Default)]
pub struct ColdRing {
    cap: usize,
    data: VecDeque<u8>,
    rows: VecDeque<(u32, u16)>,
    first_stable: u64,
}

impl ColdRing {
    pub fn new(cap: usize, first_stable: u64) -> Self {
        Self {
            cap,
            data: VecDeque::new(),
            rows: VecDeque::new(),
            first_stable,
        }
    }

    pub fn is_enabled(&self) -> bool {
        self.cap > 0
    }

    pub fn len(&self) -> usize {
        self.rows.len()
    }

    pub fn is_empty(&self) -> bool {
        self.rows.is_empty()
    }

    pub fn bytes(&self) -> usize {
        self.data.len() + COLD_ROW_OVERHEAD_BYTES * self.rows.len()
    }

    pub fn first_stable(&self) -> u64 {
        self.first_stable
    }

    pub fn end_stable(&self) -> u64 {
        self.first_stable + self.rows.len() as u64
    }

    pub fn stats(&self) -> ColdStats {
        ColdStats {
            rows: self.rows.len(),
            bytes: self.bytes(),
            cap: self.cap,
            first_stable_row: self.first_stable,
        }
    }

    pub fn reset_at(&mut self, stable: u64) {
        self.data.clear();
        self.rows.clear();
        self.first_stable = stable;
    }

    pub fn push(&mut self, stable: u64, row: &ColdRow) {
        if !self.is_enabled() {
            return;
        }
        if stable != self.end_stable() {
            self.reset_at(stable);
        }
        let need = row.bytes.len() + COLD_ROW_OVERHEAD_BYTES;
        if need > self.cap {
            self.reset_at(stable + 1);
            return;
        }
        while self.bytes() + need > self.cap {
            self.pop_front();
        }
        if self.data.capacity() == 0 {
            self.data.reserve_exact(self.cap);
        }
        self.data.extend(row.bytes.iter());
        let cols = u16::try_from(row.cols).unwrap_or(u16::MAX);
        self.rows.push_back((row.bytes.len() as u32, cols));
    }

    fn pop_front(&mut self) {
        if let Some((len, _)) = self.rows.pop_front() {
            self.data.drain(..len as usize);
            self.first_stable += 1;
        }
    }

    pub fn rows(&self, range: Range<u64>) -> Vec<ColdRow> {
        let lo = range.start.max(self.first_stable);
        let hi = range.end.min(self.end_stable());
        if hi <= lo {
            return Vec::new();
        }
        let skip = (lo - self.first_stable) as usize;
        let take = (hi - lo) as usize;
        let mut offset: usize = self
            .rows
            .iter()
            .take(skip)
            .map(|(len, _)| *len as usize)
            .sum();
        let mut out = Vec::with_capacity(take);
        for (len, cols) in self.rows.iter().skip(skip).take(take) {
            let end = offset + *len as usize;
            out.push(ColdRow {
                bytes: self.data.range(offset..end).copied().collect(),
                cols: usize::from(*cols),
            });
            offset = end;
        }
        out
    }

    #[cfg(test)]
    pub(crate) fn data_capacity(&self) -> usize {
        self.data.capacity()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(text: &str) -> ColdRow {
        ColdRow {
            bytes: text.as_bytes().to_vec(),
            cols: text.chars().count(),
        }
    }

    fn texts(rows: &[ColdRow]) -> Vec<String> {
        rows.iter()
            .map(|row| String::from_utf8(row.bytes.clone()).unwrap())
            .collect()
    }

    #[test]
    fn a_ring_with_no_cap_keeps_nothing() {
        let mut ring = ColdRing::new(0, 0);
        ring.push(0, &row("a"));
        assert!(ring.is_empty());
        assert_eq!(ring.bytes(), 0);
    }

    #[test]
    fn rows_come_back_oldest_first_by_stable_row() {
        let mut ring = ColdRing::new(1024, 10);
        for (index, text) in ["ten", "eleven", "twelve"].iter().enumerate() {
            ring.push(10 + index as u64, &row(text));
        }
        assert_eq!(ring.first_stable(), 10);
        assert_eq!(ring.end_stable(), 13);
        assert_eq!(texts(&ring.rows(10..13)), ["ten", "eleven", "twelve"]);
        assert_eq!(texts(&ring.rows(11..12)), ["eleven"]);
        assert_eq!(texts(&ring.rows(0..11)), ["ten"]);
        assert!(ring.rows(13..20).is_empty());
    }

    #[test]
    fn the_oldest_rows_go_first_when_the_cap_is_reached() {
        let per_row = 4 + COLD_ROW_OVERHEAD_BYTES;
        let mut ring = ColdRing::new(per_row * 3, 0);
        for index in 0..5u64 {
            ring.push(index, &row(&format!("r{index:03}")));
        }
        assert_eq!(ring.len(), 3);
        assert_eq!(ring.first_stable(), 2);
        assert_eq!(texts(&ring.rows(0..5)), ["r002", "r003", "r004"]);
        assert!(ring.bytes() <= per_row * 3);
    }

    #[test]
    fn the_byte_count_never_passes_the_cap() {
        let cap = 64 * 1024;
        let mut ring = ColdRing::new(cap, 0);
        for index in 0..20_000u64 {
            let text = "x".repeat((index % 97) as usize);
            ring.push(index, &row(&text));
            assert!(
                ring.bytes() <= cap,
                "{} > {cap} at row {index}",
                ring.bytes()
            );
        }
        assert_eq!(ring.data_capacity(), cap);
    }

    #[test]
    fn a_row_larger_than_the_cap_empties_the_ring() {
        let mut ring = ColdRing::new(16, 0);
        ring.push(0, &row("ab"));
        ring.push(1, &row(&"z".repeat(64)));
        assert!(ring.is_empty());
        assert_eq!(ring.first_stable(), 2);
        ring.push(2, &row("cd"));
        assert_eq!(texts(&ring.rows(0..3)), ["cd"]);
    }

    #[test]
    fn a_gap_in_stable_rows_restarts_the_ring() {
        let mut ring = ColdRing::new(1024, 0);
        ring.push(0, &row("zero"));
        ring.push(5, &row("five"));
        assert_eq!(ring.first_stable(), 5);
        assert_eq!(texts(&ring.rows(0..10)), ["five"]);
    }

    #[test]
    fn a_row_keeps_the_width_it_needs() {
        let mut ring = ColdRing::new(1024, 0);
        ring.push(
            0,
            &ColdRow {
                bytes: b"wide".to_vec(),
                cols: 180,
            },
        );
        assert_eq!(ring.rows(0..1)[0].cols, 180);
    }
}
PLAN7_EOF
```

- [ ] **Step 6: Parser side — spill on trim, serve older rows**

Create `packages/terminal/crates/vt-core/src/parser/cold.rs` with exactly this content:

```bash
mkdir -p "$REPO/packages/terminal/crates/vt-core/src/parser"
cat > "$REPO/packages/terminal/crates/vt-core/src/parser/cold.rs" <<'PLAN7_EOF'
use crate::cold_ring::{ColdRing, ColdRow, ColdStats};
use crate::row_index::RowRange;
use crate::width::{clusters, WidthMode};

use super::Parser;

impl Parser {
    pub fn set_cold_ring_bytes(&mut self, cap: usize) {
        self.cold = ColdRing::new(cap, self.trimmed_total);
    }

    pub fn cold_stats(&self) -> ColdStats {
        self.cold.stats()
    }

    pub fn cold_floor(&self) -> Option<u64> {
        if !self.cold.is_enabled() {
            return None;
        }
        if self.cold.is_empty() {
            Some(self.trimmed_total)
        } else {
            Some(self.cold.first_stable())
        }
    }

    pub(crate) fn reset_cold_ring(&mut self) {
        self.cold.reset_at(self.trimmed_total);
    }

    pub(crate) fn spill_to_cold(&mut self, first_stable: u64, count: usize) {
        if !self.cold.is_enabled() {
            return;
        }
        for index in 0..count {
            let Some(range) = self.rows.completed().get(index) else {
                return;
            };
            let row = self.cold_row(range);
            self.cold.push(first_stable + index as u64, &row);
        }
    }

    pub(crate) fn older_rows(&self, before: u64, max_rows: usize) -> Vec<ColdRow> {
        let front = self.trimmed_total;
        let completed = self.rows.completed();
        let bound = before.min(front + completed.len() as u64);
        if bound > front {
            let hi = (bound - front) as usize;
            let lo = hi.saturating_sub(max_rows);
            return (lo..hi)
                .filter_map(|index| completed.get(index))
                .map(|range| self.cold_row(range))
                .collect();
        }
        let hi = before.min(self.cold.end_stable());
        self.cold.rows(hi.saturating_sub(max_rows as u64)..hi)
    }

    fn cold_row(&self, range: &RowRange) -> ColdRow {
        let bytes = self.content.copy_range(range.start, range.end);
        let pairs = if bytes.is_empty() {
            Vec::new()
        } else {
            self.styles.runs(range.start, range.end)
        };
        let indent = usize::from(range.indent);
        let text = std::str::from_utf8(&bytes).unwrap_or("");
        let mut out = String::with_capacity(indent + bytes.len() + 8);
        out.extend(std::iter::repeat_n(' ', indent));
        let links = &self.hyperlinks;
        crate::style_sgr::write_styled_row_with(&mut out, &bytes, &pairs, &|id| links.uri(id), "");
        ColdRow {
            bytes: out.into_bytes(),
            cols: indent + text_cols(text),
        }
    }
}

fn text_cols(text: &str) -> usize {
    if text.is_ascii() {
        return text.len();
    }
    let width = |mode| clusters(text, mode).iter().map(|c| c.width).sum::<usize>();
    width(WidthMode::Scalar).max(width(WidthMode::Grapheme))
}
PLAN7_EOF
```
Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t1-parser.patch <<'PLAN7_PATCH'
diff --git a/packages/terminal/crates/vt-core/src/content.rs b/packages/terminal/crates/vt-core/src/content.rs
index cf7d8130d..d9329f0cf 100644
--- a/packages/terminal/crates/vt-core/src/content.rs
+++ b/packages/terminal/crates/vt-core/src/content.rs
@@ -115,6 +115,17 @@ impl Content {
         }
     }
 
+    pub fn trim_front_to(&mut self, offset: u64) {
+        self.drop_before(offset);
+        if let Some(front) = self.chunks.front_mut() {
+            if front.start < offset {
+                let cut = ((offset - front.start) as usize).min(front.bytes.len());
+                front.bytes.drain(..cut);
+                front.start += cut as u64;
+            }
+        }
+    }
+
     pub fn resident_bytes(&self) -> usize {
         self.chunks.iter().map(|chunk| chunk.bytes.len()).sum()
     }
@@ -194,4 +205,27 @@ mod tests {
         assert_eq!(c.start_offset(), 1024);
         assert_eq!(c.copy_range(1024, 1025), b"z");
     }
+
+    #[test]
+    fn trim_front_to_cuts_into_the_front_chunk_so_a_prepend_abuts_the_first_row() {
+        let mut c = Content::with_base(1024);
+        for _ in 0..10 {
+            c.push_char("x");
+        }
+        c.trim_front_to(1030);
+        assert_eq!(c.start_offset(), 1030);
+        assert_eq!(c.resident_bytes(), 4);
+        let start = c.prepend(b"ab");
+        assert_eq!(start, 1028);
+        assert_eq!(c.copy_range(1028, 1034), b"abxxxx");
+    }
+
+    #[test]
+    fn trim_front_to_below_the_start_changes_nothing() {
+        let mut c = Content::with_base(1024);
+        c.push_char("q");
+        c.trim_front_to(1000);
+        assert_eq!(c.start_offset(), 1024);
+        assert_eq!(c.copy_range(1024, 1025), b"q");
+    }
 }
diff --git a/packages/terminal/crates/vt-core/src/parser.rs b/packages/terminal/crates/vt-core/src/parser.rs
index 880aba138..34f046e87 100644
--- a/packages/terminal/crates/vt-core/src/parser.rs
+++ b/packages/terminal/crates/vt-core/src/parser.rs
@@ -1,4 +1,5 @@
 mod blocks;
+mod cold;
 mod colour;
 mod history;
 mod perform;
@@ -62,6 +63,8 @@ pub(crate) struct Parser {
     last_width: usize,
     width_mode: WidthMode,
     hyperlinks: HyperlinkRegistry,
+    cold: crate::cold_ring::ColdRing,
+    committed_rows: u64,
     #[cfg(feature = "trace")]
     pub(crate) trace: crate::trace::Trace,
 }
@@ -98,6 +101,8 @@ impl Parser {
             last_width: width,
             width_mode: WidthMode::default(),
             hyperlinks: HyperlinkRegistry::default(),
+            cold: crate::cold_ring::ColdRing::default(),
+            committed_rows: 0,
             #[cfg(feature = "trace")]
             trace: Default::default(),
         }
@@ -453,6 +458,7 @@ impl Parser {
                 &mut self.rows,
                 &mut self.styles,
             );
+            self.committed_rows += 1;
             self.grid.note_row_completed();
         }
         if std::mem::take(&mut self.rewrap_pending) {
@@ -502,6 +508,10 @@ impl Parser {
         self.note_mutation();
     }
 
+    pub(crate) fn committed_rows(&self) -> u64 {
+        self.committed_rows
+    }
+
     pub fn stale_row_count(&self) -> usize {
         self.rows.stale_runs().iter().map(|run| run.len).sum()
     }
diff --git a/packages/terminal/crates/vt-core/src/parser/history.rs b/packages/terminal/crates/vt-core/src/parser/history.rs
index 2a8ddc550..10d248962 100644
--- a/packages/terminal/crates/vt-core/src/parser/history.rs
+++ b/packages/terminal/crates/vt-core/src/parser/history.rs
@@ -14,6 +14,7 @@ impl Parser {
             return false;
         }
         self.trimmed_total = origin;
+        self.reset_cold_ring();
         self.grid.advance_origin(origin as usize);
         self.note_mutation();
         true
@@ -34,6 +35,12 @@ impl Parser {
             bytes.extend_from_slice(&row.bytes);
             lengths.push(row.bytes.len() as u64);
         }
+        let head = self
+            .rows
+            .completed()
+            .front()
+            .map_or(self.rows.open_start(), |row| row.start);
+        self.content.trim_front_to(head);
         let base = self.content.prepend(&bytes);
         let mut runs: Vec<(u64, CellStyle)> = Vec::new();
         let mut ranges = Vec::with_capacity(rows.len());
@@ -54,6 +61,7 @@ impl Parser {
         let count = ranges.len();
         self.rows.prepend(ranges);
         self.trimmed_total = first_stable_row;
+        self.reset_cold_ring();
         self.grid.retreat_origin(count);
         let history_blocks: Vec<Block> = blocks
             .into_iter()
@@ -83,6 +91,10 @@ impl Parser {
         }
     }
 
+    pub(crate) fn mark_history_stale(&mut self, rows: usize, cut_at: usize) {
+        self.rows.mark_stale(0, rows, cut_at);
+    }
+
     pub fn trim_to(&mut self, limits: Limits) -> usize {
         let before = self.rows.completed().len();
         loop {
@@ -93,6 +105,9 @@ impl Parser {
                 break;
             }
             let keep = if over_rows { limits.rows } else { completed };
+            let spilled = (completed + 1).saturating_sub(keep).min(completed);
+            let first = self.trimmed_total + (before - completed) as u64;
+            self.spill_to_cold(first, spilled);
             let Some(new_start) = self.rows.trim_to(keep) else {
                 break;
             };
diff --git a/packages/terminal/crates/vt-core/src/row_index.rs b/packages/terminal/crates/vt-core/src/row_index.rs
index 96be7448a..506feb4bc 100644
--- a/packages/terminal/crates/vt-core/src/row_index.rs
+++ b/packages/terminal/crates/vt-core/src/row_index.rs
@@ -154,7 +154,7 @@ impl RowIndex {
     // the width the touch used, so a later width change has to re-mark it.
     // Extending from the last run alone reaches the tail and skips the middle,
     // which then stays cut at that intermediate width forever.
-    fn mark_stale(&mut self, start: usize, end: usize, cols: usize) {
+    pub(crate) fn mark_stale(&mut self, start: usize, end: usize, cols: usize) {
         if end <= start {
             return;
         }
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t1-parser.patch
```

The `content.rs` hunk adds `Content::trim_front_to` and two unit tests. Why it exists: `Content::drop_before` (`content.rs:98-107`) frees whole 4 KiB chunks only, so after a trim the first retained row can start inside a chunk that still holds trimmed bytes; `prepend` allocates below `start_offset()` (the chunk start), which left a gap between the prepended rows and the first retained row, and `verify_integrity` panicked with `RowsNotContiguous` in four of the new tests. `apply_history_chunk` now cuts the content front to the first retained row before prepending.

- [ ] **Step 7: TerminalCore API and receiver wiring**

Create `packages/terminal/crates/vt-core/src/older.rs` with exactly this content:

```bash
mkdir -p "$REPO/packages/terminal/crates/vt-core/src"
cat > "$REPO/packages/terminal/crates/vt-core/src/older.rs" <<'PLAN7_EOF'
use crate::cold_ring::ColdStats;
use crate::TerminalCore;

pub const OLDER_CHUNK_ROWS: usize = 2_048;

pub const OLDER_CELL_BUDGET: usize = OLDER_CHUNK_ROWS * 128;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct OlderState {
    pub floor: Option<u64>,
    pub marks: u32,
}

impl OlderState {
    pub(crate) fn note(&mut self, floor: u64) {
        self.floor = Some(floor);
        self.marks = self.marks.wrapping_add(1);
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OlderChunk {
    pub first_stable_row: u64,
    pub rows: usize,
    pub bytes: Vec<u8>,
}

impl TerminalCore {
    pub fn set_cold_ring_bytes(&mut self, cap: usize) {
        self.parser.set_cold_ring_bytes(cap);
    }

    pub fn cold_stats(&self) -> ColdStats {
        self.parser.cold_stats()
    }

    pub fn cold_floor(&self) -> Option<u64> {
        self.parser.cold_floor()
    }

    pub fn older_mark(&self) -> Option<Vec<u8>> {
        let floor = self.parser.cold_floor()?;
        Some(format!("\x1b]7000;v=1;older={floor}\x1b\\").into_bytes())
    }

    pub fn older_chunk(
        &self,
        before: u64,
        max_rows: usize,
        max_bytes: usize,
    ) -> Option<OlderChunk> {
        let rows = self.parser.older_rows(before, max_rows.max(1));
        let mut taken = 0usize;
        let mut cols = 1usize;
        let mut size = 64usize;
        let limit = usize::try_from(before).unwrap_or(usize::MAX);
        for row in rows.iter().rev().take(limit) {
            let next_cols = cols.max(row.cols);
            let next_size = size + row.bytes.len() + 2;
            if next_size > max_bytes || (taken > 0 && (taken + 1) * next_cols > OLDER_CELL_BUDGET) {
                break;
            }
            taken += 1;
            cols = next_cols;
            size = next_size;
        }
        if taken == 0 {
            return None;
        }
        let first_stable_row = before - taken as u64;
        let mut bytes = Vec::with_capacity(size);
        bytes.extend_from_slice(
            format!("\x1b]7000;v=1;history={first_stable_row},{taken};cols={cols}\x1b\\")
                .as_bytes(),
        );
        for row in &rows[rows.len() - taken..] {
            bytes.extend_from_slice(&row.bytes);
            bytes.extend_from_slice(b"\r\n");
        }
        Some(OlderChunk {
            first_stable_row,
            rows: taken,
            bytes,
        })
    }

    pub fn older_state(&self) -> OlderState {
        self.older
    }
}
PLAN7_EOF
```
Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t1-core.patch <<'PLAN7_PATCH'
diff --git a/packages/terminal/crates/vt-core/src/event_bridge.rs b/packages/terminal/crates/vt-core/src/event_bridge.rs
index ed29b8bfe..ebc9b879b 100644
--- a/packages/terminal/crates/vt-core/src/event_bridge.rs
+++ b/packages/terminal/crates/vt-core/src/event_bridge.rs
@@ -41,7 +41,10 @@ pub(crate) fn apply_event(parser: &mut Parser, alt: &mut AltScreen, event: MarkE
             }
         }
         MarkEvent::InputReady | MarkEvent::InputReleased => {}
-        MarkEvent::ReplayOrigin(_) | MarkEvent::ReplayReady | MarkEvent::HistoryChunk { .. } => {}
+        MarkEvent::ReplayOrigin(_)
+        | MarkEvent::ReplayReady
+        | MarkEvent::HistoryChunk { .. }
+        | MarkEvent::OlderFloor(_) => {}
         MarkEvent::AltScreenEnter => {
             alt.set(true);
         }
diff --git a/packages/terminal/crates/vt-core/src/history.rs b/packages/terminal/crates/vt-core/src/history.rs
index c388b68b2..2cc890894 100644
--- a/packages/terminal/crates/vt-core/src/history.rs
+++ b/packages/terminal/crates/vt-core/src/history.rs
@@ -17,6 +17,7 @@ struct OpenBlock {
 pub(crate) struct HistoryReceiver {
     first_stable_row: u64,
     wanted: usize,
+    cols: usize,
     seen_rows: usize,
     vte: VteParser,
     screen: Option<ScreenGrid>,
@@ -32,6 +33,7 @@ impl HistoryReceiver {
         Self {
             first_stable_row: 0,
             wanted: 0,
+            cols: 0,
             seen_rows: 0,
             vte: VteParser::new(),
             screen: None,
@@ -49,6 +51,7 @@ impl HistoryReceiver {
 
     pub fn begin(&mut self, first_stable_row: u64, rows: usize, cols: usize, mode: WidthMode) {
         let mut screen = ScreenGrid::new(rows.max(1) + 1, cols.max(1));
+        self.cols = screen.cols();
         screen.set_records_eviction(false);
         screen.set_width_mode(mode);
         self.first_stable_row = first_stable_row;
@@ -90,7 +93,7 @@ impl HistoryReceiver {
         consumed
     }
 
-    pub fn take(&mut self) -> Option<(u64, Vec<HistoryRow>, Vec<HistoryBlock>)> {
+    pub fn take(&mut self) -> Option<(u64, Vec<HistoryRow>, Vec<HistoryBlock>, usize)> {
         if !self.done {
             return None;
         }
@@ -111,10 +114,27 @@ impl HistoryReceiver {
             self.first_stable_row,
             rows,
             std::mem::take(&mut self.blocks),
+            self.cols,
         ))
     }
 }
 
+impl crate::TerminalCore {
+    pub(crate) fn drain_history(&mut self) {
+        if let Some((first_stable_row, rows, blocks, cols)) = self.history.take() {
+            let count = rows.len();
+            if self
+                .parser
+                .apply_history_chunk(first_stable_row, rows, blocks)
+                && cols > self.parser.columns()
+            {
+                self.parser.mark_history_stale(count, cols);
+            }
+            self.debug_check();
+        }
+    }
+}
+
 struct ScreenPerform<'a> {
     screen: &'a mut ScreenGrid,
     style: &'a mut CellStyle,
diff --git a/packages/terminal/crates/vt-core/src/lib.rs b/packages/terminal/crates/vt-core/src/lib.rs
index 62a17963d..1adc1bce1 100644
--- a/packages/terminal/crates/vt-core/src/lib.rs
+++ b/packages/terminal/crates/vt-core/src/lib.rs
@@ -5,6 +5,7 @@ pub mod block;
 pub mod block_grid;
 pub mod block_selection;
 pub mod block_tree;
+pub mod cold_ring;
 pub mod content;
 pub mod delta;
 pub mod event_bridge;
@@ -15,12 +16,14 @@ pub mod hyperlink;
 pub mod integrity;
 pub mod limits;
 mod line_editor;
+pub mod older;
 pub mod parser;
 pub mod row_index;
 mod screen;
 mod scrollback;
 mod sgr;
 pub mod style;
+pub mod style_sgr;
 pub mod sync;
 #[cfg(feature = "trace")]
 pub mod trace;
@@ -35,6 +38,7 @@ pub use block::{Block, BlockId, BlockMeta, BlockRecord, BlockSource, BlockState,
 pub use block_grid::BlockGrid;
 pub use block_selection::{BlockSelection, SelectionPoint};
 pub use block_tree::{BlockSummary, BlockTree};
+pub use cold_ring::{ColdRow, ColdStats};
 pub use delta::{Delta, DeltaKind};
 pub use find::{FindMatch, FindQuery, FindSession, FindUpdate};
 pub use grid::{CellSpan, ExportedRow};
@@ -42,6 +46,7 @@ pub use hyperlink::{Hyperlink, HyperlinkRegistry, LinkId};
 pub use integrity::IntegrityError;
 pub use limits::{Limits, MemoryStats};
 pub use line_editor::LineEditorState;
+pub use older::{OlderChunk, OlderState, OLDER_CHUNK_ROWS};
 pub use parser::{HistoryBlock, HistoryRow};
 pub use style::{Attrs, CellStyle, StyleCode};
 pub use width::{clusters, Cluster, WidthMode};
@@ -76,6 +81,7 @@ pub struct TerminalCore {
     now_ms: u64,
     history: history::HistoryReceiver,
     replay_ready: bool,
+    older: OlderState,
 }
 
 impl TerminalCore {
@@ -103,6 +109,7 @@ impl TerminalCore {
             now_ms: 0,
             history: history::HistoryReceiver::new(),
             replay_ready: false,
+            older: OlderState::default(),
         })
     }
 
@@ -204,6 +211,7 @@ impl TerminalCore {
     }
 
     fn feed_raw(&mut self, bytes: &[u8]) {
+        let committed = self.parser.committed_rows();
         self.parser.set_clock(self.now_ms);
         let mut bytes = bytes;
         if self.history.is_active() {
@@ -244,11 +252,17 @@ impl TerminalCore {
                     parsed = upto;
                     continue;
                 }
+                MarkEvent::OlderFloor(floor) => {
+                    self.older.note(floor);
+                    parsed = upto;
+                    continue;
+                }
                 MarkEvent::HistoryChunk {
                     first_stable_row,
                     rows,
+                    cols,
                 } => {
-                    let cols = self.parser.columns();
+                    let cols = self.parser.columns().max(cols.unwrap_or(0));
                     self.history
                         .begin(first_stable_row, rows, cols, self.parser.width_mode());
                     let rest = &bytes[upto..];
@@ -284,19 +298,13 @@ impl TerminalCore {
         }
         self.parser.note_output();
         self.parser.commit_evicted();
-        self.parser.trim_to(self.limits);
+        if self.parser.committed_rows() != committed {
+            self.parser.trim_to(self.limits);
+        }
         self.parser.note_mutation();
         self.debug_check();
     }
 
-    fn drain_history(&mut self) {
-        if let Some((first_stable_row, rows, blocks)) = self.history.take() {
-            self.parser
-                .apply_history_chunk(first_stable_row, rows, blocks);
-            self.debug_check();
-        }
-    }
-
     fn advance_vte(&mut self, bytes: &[u8]) {
         #[cfg(feature = "trace")]
         {
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t1-core.patch
```

What the `lib.rs` hunks do: register `cold_ring`, `older`, `style_sgr`; add `older: OlderState`; handle `MarkEvent::OlderFloor` like `ReplayReady` (consume, no bytes printed); size the history receiver to `max(pane cols, cols=)`; trim only when this feed committed a live row; move `drain_history` into `history.rs` (so `lib.rs` stays at 580 lines) where it now marks a chunk wider than the pane stale at the chunk's width.

- [ ] **Step 8: Run the tests**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test cold_ring 2>&1 | grep "test result"
cargo test -p terminal-marks 2>&1 | grep "test result"
cargo test -p vt-core --lib 2>&1 | grep "test result"
cargo test 2>&1 | grep -E "FAILED|panicked" ; echo "full-suite-checked"
cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
wc -l crates/vt-core/src/lib.rs crates/vt-host/src/lib.rs
```
Expected: `test result: ok. 15 passed` (cold_ring), `test result: ok. 24 passed` then `ok. 6 passed` then `ok. 0 passed` (marks: lib, vectors, doc), `test result: ok. 91 passed` for `vt-core --lib` (82 on the Task 0 tree + 7 ring unit tests + 2 content unit tests), no FAILED/panicked lines, `cargo fmt --check` silent, clippy ends with `Finished` and no warnings; `580 …/lib.rs`, `557 …/vt-host/src/lib.rs`.

- [ ] **Step 9: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/marks/src/event.rs \
  packages/terminal/crates/marks/src/scanner.rs \
  packages/terminal/crates/marks/tests/vectors.rs \
  packages/terminal/crates/vt-core/src/cold_ring.rs \
  packages/terminal/crates/vt-core/src/older.rs \
  packages/terminal/crates/vt-core/src/parser/cold.rs \
  packages/terminal/crates/vt-core/src/style_sgr.rs \
  packages/terminal/crates/vt-host/src/sgr.rs \
  packages/terminal/crates/vt-host/src/lib.rs \
  packages/terminal/crates/vt-core/src/lib.rs \
  packages/terminal/crates/vt-core/src/parser.rs \
  packages/terminal/crates/vt-core/src/parser/history.rs \
  packages/terminal/crates/vt-core/src/history.rs \
  packages/terminal/crates/vt-core/src/content.rs \
  packages/terminal/crates/vt-core/src/row_index.rs \
  packages/terminal/crates/vt-core/src/event_bridge.rs \
  packages/terminal/crates/vt-core/tests/cold_ring.rs
git commit -m "vt-core: keep rows evicted past the cap in a cold ring and serve them as history chunks" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: vt-host exports and the Go vtwasm wrapper

**Files:**
- Create: `packages/terminal/crates/vt-host/src/older.rs`, `backend/internal/adapters/runtime/ptyhost/vtwasm/older.go`, `backend/internal/adapters/runtime/ptyhost/vtwasm/older_test.go`
- Modify: `packages/terminal/crates/vt-host/src/lib.rs:1`, `backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go:33-36,57-62,65-93`, `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` (rebuilt, committed)

**Interfaces:**
- Consumes: Task 1's `TerminalCore` API.
- Produces (wasm C-ABI): `vt_set_cold_ring(handle, bytes)`, `vt_cold_stats(handle, out_ptr) -> 1|0` (20 bytes LE: rows u32, bytes u32, cap u32, first_stable_row u64), `vt_older_chunk(handle, before: u64, max_rows, out_ptr, out_cap, next_ptr) -> len | 0 | RENDER_ERR | RENDER_TOO_BIG` (writes the chunk's first stable row to `next_ptr`), `vt_older_mark(handle, out_ptr, out_cap) -> len | 0`.
- Produces (Go): `vtwasm.Limits.ColdRingBytes uint32`; `vtwasm.OlderChunkRows = 2048`; `(*Parser).ColdStats() (ColdStats, error)`, `(*Parser).OlderChunk(before uint64, maxRows int) (chunk string, next uint64, ok bool, err error)`, `(*Parser).OlderMark() (string, error)` ("" when the ring is disabled); unexported `(*Parser).readStruct(fn string, size uint32) ([]byte, error)` now shared by `MemoryStats`.

- [ ] **Step 1: Failing Go tests**

Create `backend/internal/adapters/runtime/ptyhost/vtwasm/older_test.go` with exactly this content:

```bash
mkdir -p "$REPO/backend/internal/adapters/runtime/ptyhost/vtwasm"
cat > "$REPO/backend/internal/adapters/runtime/ptyhost/vtwasm/older_test.go" <<'PLAN7_EOF'
package vtwasm

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

func newRingParser(t *testing.T, cols, rows, keep, ring uint32) *Parser {
	t.Helper()
	p, err := New(context.Background(), Module, cols, rows, Limits{Rows: keep, Bytes: 0xffffffff, ColdRingBytes: ring})
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	t.Cleanup(func() { _ = p.Close() })
	return p
}

func feedRows(t *testing.T, p *Parser, from, to int) {
	t.Helper()
	var b strings.Builder
	for i := from; i < to; i++ {
		fmt.Fprintf(&b, "row %06d\r\n", i)
		if b.Len() > 32<<10 {
			feed(t, p, b.String())
			b.Reset()
		}
	}
	feed(t, p, b.String())
}

func TestEvictedRowsReachTheColdRingAndComeBackAsAChunk(t *testing.T) {
	p := newRingParser(t, 40, 3, 50, 1<<20)
	feedRows(t, p, 0, 200)
	stats, err := p.ColdStats()
	if err != nil {
		t.Fatalf("cold stats: %v", err)
	}
	if stats.FirstStableRow != 0 || stats.Rows == 0 || stats.Cap != 1<<20 {
		t.Fatalf("cold stats = %+v", stats)
	}
	mark, err := p.OlderMark()
	if err != nil || mark != "\x1b]7000;v=1;older=0\x1b\\" {
		t.Fatalf("older mark = %q, %v", mark, err)
	}
	front := stats.FirstStableRow + uint64(stats.Rows)
	chunk, next, ok, err := p.OlderChunk(front, HistoryChunkRows)
	if err != nil || !ok {
		t.Fatalf("older chunk: ok=%v err=%v", ok, err)
	}
	if next != 0 {
		t.Fatalf("next = %d, want 0", next)
	}
	want := fmt.Sprintf("\x1b]7000;v=1;history=0,%d;cols=10\x1b\\", stats.Rows)
	if !strings.HasPrefix(chunk, want) {
		t.Fatalf("chunk starts %q, want %q", chunk[:min(len(chunk), 60)], want)
	}
	if !strings.Contains(chunk, "row 000000") || strings.Index(chunk, "row 000000") > strings.Index(chunk, "row 000001") {
		t.Fatalf("rows missing or out of order: %q", chunk[:min(len(chunk), 200)])
	}
	if _, _, ok, err := p.OlderChunk(0, HistoryChunkRows); ok || err != nil {
		t.Fatalf("a chunk below the floor: ok=%v err=%v", ok, err)
	}
}

func TestAParserWithoutARingOffersNothingOlder(t *testing.T) {
	p := newTestParser(t, 40, 3)
	feedRows(t, p, 0, 2000)
	mark, err := p.OlderMark()
	if err != nil || mark != "" {
		t.Fatalf("older mark = %q, %v", mark, err)
	}
	stats, err := p.ColdStats()
	if err != nil || stats.Rows != 0 || stats.Cap != 0 {
		t.Fatalf("cold stats = %+v, %v", stats, err)
	}
}

func TestTheColdRingNeverPassesItsCap(t *testing.T) {
	const ring = 64 << 10
	p := newRingParser(t, 40, 3, 100, ring)
	for batch := 0; batch < 40; batch++ {
		feedRows(t, p, batch*500, (batch+1)*500)
		stats, err := p.ColdStats()
		if err != nil {
			t.Fatalf("cold stats: %v", err)
		}
		if stats.Bytes > ring {
			t.Fatalf("ring holds %d bytes past its %d cap", stats.Bytes, ring)
		}
	}
	stats, _ := p.ColdStats()
	if stats.FirstStableRow == 0 {
		t.Fatalf("the oldest rows were never dropped: %+v", stats)
	}
}
PLAN7_EOF
```

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/vtwasm/ -run 'Evicted|WithoutARing|ColdRing' 2>&1 | tail -3
```
Expected: build failure `unknown field ColdRingBytes in struct literal of type Limits` / `p.ColdStats undefined`.

- [ ] **Step 2: vt-host exports**

Create `packages/terminal/crates/vt-host/src/older.rs` with exactly this content:

```bash
mkdir -p "$REPO/packages/terminal/crates/vt-host/src"
cat > "$REPO/packages/terminal/crates/vt-host/src/older.rs" <<'PLAN7_EOF'
use crate::{CORES, RENDER_ERR, RENDER_TOO_BIG};

#[no_mangle]
pub extern "C" fn vt_set_cold_ring(handle: u32, bytes: u32) {
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.set_cold_ring_bytes(bytes as usize);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_cold_stats(handle: u32, out_ptr: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => {
            let stats = core.cold_stats();
            let mut out = [0u8; 20];
            out[0..4].copy_from_slice(&(stats.rows as u32).to_le_bytes());
            out[4..8].copy_from_slice(&(stats.bytes as u32).to_le_bytes());
            out[8..12].copy_from_slice(&(stats.cap as u32).to_le_bytes());
            out[12..20].copy_from_slice(&stats.first_stable_row.to_le_bytes());
            unsafe {
                std::ptr::copy_nonoverlapping(out.as_ptr(), out_ptr as *mut u8, out.len());
            }
            1
        }
        None => 0,
    })
}

#[no_mangle]
pub extern "C" fn vt_older_chunk(
    handle: u32,
    before: u64,
    max_rows: u32,
    out_ptr: u32,
    out_cap: u32,
    next_ptr: u32,
) -> u32 {
    CORES.with(|c| {
        let cores = c.borrow();
        let Some(core) = cores.get(&handle) else {
            return RENDER_ERR;
        };
        let Some(chunk) = core.older_chunk(before, max_rows as usize, out_cap as usize) else {
            return 0;
        };
        if chunk.bytes.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(
                chunk.bytes.as_ptr(),
                out_ptr as *mut u8,
                chunk.bytes.len(),
            );
            std::ptr::copy_nonoverlapping(
                chunk.first_stable_row.to_le_bytes().as_ptr(),
                next_ptr as *mut u8,
                8,
            );
        }
        chunk.bytes.len() as u32
    })
}

#[no_mangle]
pub extern "C" fn vt_older_mark(handle: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| {
        let cores = c.borrow();
        let Some(core) = cores.get(&handle) else {
            return RENDER_ERR;
        };
        let Some(mark) = core.older_mark() else {
            return 0;
        };
        if mark.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(mark.as_ptr(), out_ptr as *mut u8, mark.len());
        }
        mark.len() as u32
    })
}
PLAN7_EOF
```
Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t2-vthost.patch <<'PLAN7_PATCH'
diff --git a/packages/terminal/crates/vt-host/src/lib.rs b/packages/terminal/crates/vt-host/src/lib.rs
--- a/packages/terminal/crates/vt-host/src/lib.rs
+++ b/packages/terminal/crates/vt-host/src/lib.rs
@@ -1,4 +1,5 @@
 mod block_marks;
+mod older;
 
 use std::cell::RefCell;
 use std::collections::HashMap;
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t2-vthost.patch
```

- [ ] **Step 3: Go wrapper**

Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t2-vtwasm.patch <<'PLAN7_PATCH'
diff --git a/backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go b/backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go
index 67716859a..b35638b6d 100644
--- a/backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go
+++ b/backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go
@@ -31,8 +31,9 @@ type Parser struct {
 const TerminalIdentity = "Operator"
 
 type Limits struct {
-	Rows  uint32
-	Bytes uint32
+	Rows          uint32
+	Bytes         uint32
+	ColdRingBytes uint32
 }
 
 type MemoryStats struct {
@@ -59,37 +60,51 @@ func New(ctx context.Context, wasmModule []byte, cols, rows uint32, limits Limit
 		_ = rt.Close(ctx)
 		return nil, err
 	}
+	if limits.ColdRingBytes > 0 {
+		if _, err := mod.ExportedFunction("vt_set_cold_ring").Call(ctx, uint64(p.handle), uint64(limits.ColdRingBytes)); err != nil {
+			_ = rt.Close(ctx)
+			return nil, fmt.Errorf("vtwasm: set_cold_ring: %w", err)
+		}
+	}
 	return p, nil
 }
 
 const memoryStatsBytes = 16
 
 func (p *Parser) MemoryStats() (MemoryStats, error) {
+	raw, err := p.readStruct("vt_memory_stats", memoryStatsBytes)
+	if err != nil {
+		return MemoryStats{}, err
+	}
+	return MemoryStats{
+		ContentBytes: binary.LittleEndian.Uint32(raw[0:4]),
+		StyleEntries: binary.LittleEndian.Uint32(raw[4:8]),
+		Rows:         binary.LittleEndian.Uint32(raw[8:12]),
+		Blocks:       binary.LittleEndian.Uint32(raw[12:16]),
+	}, nil
+}
+
+func (p *Parser) readStruct(fn string, size uint32) ([]byte, error) {
 	p.mu.Lock()
 	defer p.mu.Unlock()
-	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, memoryStatsBytes)
+	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, uint64(size))
 	if err != nil {
-		return MemoryStats{}, fmt.Errorf("vtwasm: alloc stats: %w", err)
+		return nil, fmt.Errorf("vtwasm: alloc %s: %w", fn, err)
 	}
 	out := uint32(res[0])
-	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), memoryStatsBytes) }()
-	res, err = p.module.ExportedFunction("vt_memory_stats").Call(p.ctx, uint64(p.handle), uint64(out))
+	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), uint64(size)) }()
+	res, err = p.module.ExportedFunction(fn).Call(p.ctx, uint64(p.handle), uint64(out))
 	if err != nil {
-		return MemoryStats{}, fmt.Errorf("vtwasm: memory_stats: %w", err)
+		return nil, fmt.Errorf("vtwasm: %s: %w", fn, err)
 	}
 	if res[0] != 1 {
-		return MemoryStats{}, fmt.Errorf("vtwasm: memory_stats failed for handle %d", p.handle)
+		return nil, fmt.Errorf("vtwasm: %s failed for handle %d", fn, p.handle)
 	}
-	raw, ok := p.module.Memory().Read(out, memoryStatsBytes)
+	raw, ok := p.module.Memory().Read(out, size)
 	if !ok {
-		return MemoryStats{}, fmt.Errorf("vtwasm: read stats out of range")
+		return nil, fmt.Errorf("vtwasm: read %s out of range", fn)
 	}
-	return MemoryStats{
-		ContentBytes: binary.LittleEndian.Uint32(raw[0:4]),
-		StyleEntries: binary.LittleEndian.Uint32(raw[4:8]),
-		Rows:         binary.LittleEndian.Uint32(raw[8:12]),
-		Blocks:       binary.LittleEndian.Uint32(raw[12:16]),
-	}, nil
+	return append([]byte(nil), raw...), nil
 }
 
 func (p *Parser) setTerminalIdentity(name string) error {
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t2-vtwasm.patch
```
Create `backend/internal/adapters/runtime/ptyhost/vtwasm/older.go` with exactly this content:

```bash
mkdir -p "$REPO/backend/internal/adapters/runtime/ptyhost/vtwasm"
cat > "$REPO/backend/internal/adapters/runtime/ptyhost/vtwasm/older.go" <<'PLAN7_EOF'
package vtwasm

import (
	"encoding/binary"
	"fmt"
)

const OlderChunkRows = 2048

type ColdStats struct {
	Rows           uint32
	Bytes          uint32
	Cap            uint32
	FirstStableRow uint64
}

const coldStatsBytes = 20

func (p *Parser) ColdStats() (ColdStats, error) {
	raw, err := p.readStruct("vt_cold_stats", coldStatsBytes)
	if err != nil {
		return ColdStats{}, err
	}
	return ColdStats{
		Rows:           binary.LittleEndian.Uint32(raw[0:4]),
		Bytes:          binary.LittleEndian.Uint32(raw[4:8]),
		Cap:            binary.LittleEndian.Uint32(raw[8:12]),
		FirstStableRow: binary.LittleEndian.Uint64(raw[12:20]),
	}, nil
}

func (p *Parser) OlderChunk(before uint64, maxRows int) (string, uint64, bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, renderBufferBytes)
	if err != nil {
		return "", 0, false, fmt.Errorf("vtwasm: alloc older buffer: %w", err)
	}
	out := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), renderBufferBytes) }()
	res, err = p.module.ExportedFunction("vt_alloc").Call(p.ctx, historyNextBytes)
	if err != nil {
		return "", 0, false, fmt.Errorf("vtwasm: alloc older cursor: %w", err)
	}
	next := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(next), historyNextBytes) }()

	res, err = p.module.ExportedFunction("vt_older_chunk").
		Call(p.ctx, uint64(p.handle), before, uint64(maxRows), uint64(out), renderBufferBytes, uint64(next))
	if err != nil {
		return "", 0, false, fmt.Errorf("vtwasm: older_chunk: %w", err)
	}
	switch written := uint32(res[0]); written {
	case 0:
		return "", 0, false, nil
	case renderErr:
		return "", 0, false, fmt.Errorf("vtwasm: older_chunk failed for handle %d", p.handle)
	case renderTooBig:
		return "", 0, false, fmt.Errorf("vtwasm: older_chunk exceeds %d bytes", renderBufferBytes)
	default:
		body, ok := p.module.Memory().Read(out, written)
		if !ok {
			return "", 0, false, fmt.Errorf("vtwasm: read %d bytes at %d out of range", written, out)
		}
		cursor, ok := p.module.Memory().Read(next, historyNextBytes)
		if !ok {
			return "", 0, false, fmt.Errorf("vtwasm: read older cursor out of range")
		}
		return string(body), binary.LittleEndian.Uint64(cursor), true, nil
	}
}

const olderMarkBytes = 64

func (p *Parser) OlderMark() (string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, olderMarkBytes)
	if err != nil {
		return "", fmt.Errorf("vtwasm: alloc older mark: %w", err)
	}
	out := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), olderMarkBytes) }()
	res, err = p.module.ExportedFunction("vt_older_mark").Call(p.ctx, uint64(p.handle), uint64(out), olderMarkBytes)
	if err != nil {
		return "", fmt.Errorf("vtwasm: older_mark: %w", err)
	}
	switch written := uint32(res[0]); written {
	case 0:
		return "", nil
	case renderErr, renderTooBig:
		return "", fmt.Errorf("vtwasm: older_mark failed for handle %d", p.handle)
	default:
		body, ok := p.module.Memory().Read(out, written)
		if !ok {
			return "", fmt.Errorf("vtwasm: read older mark out of range")
		}
		return string(body), nil
	}
}
PLAN7_EOF
```

- [ ] **Step 4: Rebuild the host wasm and run**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo build --release -p vt-host --target wasm32-unknown-unknown
cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
cd "$REPO/backend" && gofmt -l internal/adapters/runtime/ptyhost
go test ./internal/adapters/runtime/ptyhost/vtwasm/ -count=1 2>&1 | tail -2
go vet ./internal/adapters/runtime/ptyhost/vtwasm/ && golangci-lint run ./internal/adapters/runtime/ptyhost/vtwasm/... 2>&1 | tail -1
```
Expected: clippy clean; `gofmt -l` prints nothing; `ok  	github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm`; `0 issues.` (Without the `readStruct` refactor `dupl` flags `ColdStats` against `MemoryStats`.)

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-host/src/older.rs \
  packages/terminal/crates/vt-host/src/lib.rs \
  backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go \
  backend/internal/adapters/runtime/ptyhost/vtwasm/older.go \
  backend/internal/adapters/runtime/ptyhost/vtwasm/older_test.go \
  backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
git commit -m "vt-host: export the cold ring, older chunks and the older floor to the Go mirror" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: pty-host — the older request, the floor mark, a 32 MiB ring per terminal

**Files:**
- Create: `backend/internal/adapters/runtime/ptyhost/older.go`, `backend/internal/adapters/runtime/ptyhost/older_test.go`
- Modify: `backend/internal/adapters/runtime/ptyhost/proto.go:31,86`, `mirror_limits.go:5`, `host.go:873-876` (`go h.streamHistory`), `host.go:1006-1008` (`if !ok { return }` in `streamHistory`), `host.go:1146-1147` (`case MsgRespawnReq`), `attach.go:211` (before `// writeResize`), `attach_replay_test.go:21-28` (helper split)

**Interfaces:**
- Consumes: Task 2's `vtwasm` API.
- Produces: `MsgOlderReq byte = 0x12`, `type OlderReq struct { Before uint64 \`json:"before"\` }`; `(*loopbackStream).RequestOlder(before uint64) error`; host methods `serveOlder(conn, before)`, `sendOlderMark(cs)`, `queueOlder(cs, payload)`; test helper `startServeWithLimits(t, pid, cols, rows int, limits vtwasm.Limits) *serveFixture`.

- [ ] **Step 1: Failing tests** (the helper split in `attach_replay_test.go` is test-only and goes in now)

Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t3-tests.patch <<'PLAN7_PATCH'
diff --git a/backend/internal/adapters/runtime/ptyhost/attach_replay_test.go b/backend/internal/adapters/runtime/ptyhost/attach_replay_test.go
index 8bf9963a5..89cd1f0fa 100644
--- a/backend/internal/adapters/runtime/ptyhost/attach_replay_test.go
+++ b/backend/internal/adapters/runtime/ptyhost/attach_replay_test.go
@@ -19,12 +19,17 @@ const readyMark = "\x1b]7000;v=1;ready=1\x1b\\"
 // session always has. The parser's grid — not the output ring — is what a
 // connecting client is replayed from.
 func startServeParsed(t *testing.T, pid, cols, rows int) *serveFixture {
+	t.Helper()
+	return startServeWithLimits(t, pid, cols, rows, vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
+}
+
+func startServeWithLimits(t *testing.T, pid, cols, rows int, limits vtwasm.Limits) *serveFixture {
 	t.Helper()
 	ln, err := net.Listen("tcp", "127.0.0.1:0")
 	if err != nil {
 		t.Fatalf("listen: %v", err)
 	}
-	parser, err := vtwasm.New(context.Background(), vtwasm.Module, uint32(cols), uint32(rows), vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
+	parser, err := vtwasm.New(context.Background(), vtwasm.Module, uint32(cols), uint32(rows), limits)
 	if err != nil {
 		t.Fatalf("new parser: %v", err)
 	}
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t3-tests.patch
```
Create `backend/internal/adapters/runtime/ptyhost/older_test.go` with exactly this content:

```bash
mkdir -p "$REPO/backend/internal/adapters/runtime/ptyhost"
cat > "$REPO/backend/internal/adapters/runtime/ptyhost/older_test.go" <<'PLAN7_EOF'
package ptyhost

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

var ringLimits = vtwasm.Limits{Rows: 50, Bytes: 0xffffffff, ColdRingBytes: 1 << 20}

func readStreamUntil(t *testing.T, c *testClient, want string) string {
	t.Helper()
	var stream strings.Builder
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) && !strings.Contains(stream.String(), want) {
		typ, payload := c.readFrame(t)
		if typ == MsgTerminalData {
			stream.Write(payload)
		}
	}
	if !strings.Contains(stream.String(), want) {
		t.Fatalf("stream never carried %q:\n%q", want, stream.String())
	}
	return stream.String()
}

func requestOlder(t *testing.T, c *testClient, before uint64) {
	t.Helper()
	payload, err := json.Marshal(OlderReq{Before: before})
	if err != nil {
		t.Fatalf("marshal older request: %v", err)
	}
	if err := c.send(MsgOlderReq, payload); err != nil {
		t.Fatalf("send older request: %v", err)
	}
}

func fillPastTheCap(t *testing.T, f *serveFixture, rows int) {
	t.Helper()
	for i := 0; i < rows; i++ {
		writeOutput(t, f, fmt.Sprintf("row %05d\r\n", i))
	}
	waitForParsedOutput(t, f, fmt.Sprintf("row %05d", rows-1))
}

func TestAHistoryStreamEndsWithTheOlderFloor(t *testing.T) {
	f := startServeWithLimits(t, 760, 20, 4, ringLimits)
	defer f.cancel()
	fillPastTheCap(t, f, 300)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResizeWithHistory(t, c, 20, 4, true)

	stream := readStreamUntil(t, c, "\x1b]7000;v=1;older=")
	mark := strings.LastIndex(stream, "\x1b]7000;v=1;older=0\x1b\\")
	if mark < 0 {
		t.Fatalf("the floor mark is not older=0:\n%q", stream)
	}
	if last := strings.LastIndex(stream, "\x1b]7000;v=1;history="); last > mark {
		t.Fatalf("a history chunk followed the floor mark:\n%q", stream)
	}
}

func TestAClientWithoutHistoryGetsTheOlderFloorAfterItsFrame(t *testing.T) {
	f := startServeWithLimits(t, 761, 20, 4, ringLimits)
	defer f.cancel()
	fillPastTheCap(t, f, 300)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 20, 4)

	stream := readStreamUntil(t, c, "\x1b]7000;v=1;older=0\x1b\\")
	if strings.Index(stream, readyMark) > strings.Index(stream, "older=") {
		t.Fatalf("the floor mark came before the frame:\n%q", stream)
	}
	if strings.Contains(stream, "history=") {
		t.Fatalf("a client that did not opt in was sent history:\n%q", stream)
	}
}

func TestAHostWithoutARingSendsNoOlderFloor(t *testing.T) {
	f := startServeParsed(t, 762, 20, 4)
	defer f.cancel()
	fillPastTheCap(t, f, 60)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 20, 4)
	_ = readReplay(t, c)
	writeOutput(t, f, "live after attach\r\n")
	stream := readStreamUntil(t, c, "live after attach")
	if strings.Contains(stream, "older=") {
		t.Fatalf("a host without a ring sent a floor mark:\n%q", stream)
	}
}

func TestAnOlderRequestFetchesEvictedRowsOverTheLiveStream(t *testing.T) {
	f := startServeWithLimits(t, 763, 20, 4, ringLimits)
	defer f.cancel()
	fillPastTheCap(t, f, 300)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResizeWithHistory(t, c, 20, 4, true)
	stream := readStreamUntil(t, c, "\x1b]7000;v=1;older=")

	cold, err := f.host.currentParser().ColdStats()
	if err != nil {
		t.Fatalf("cold stats: %v", err)
	}
	front := cold.FirstStableRow + uint64(cold.Rows)
	requestOlder(t, c, front)
	answer := readStreamUntil(t, c, "\x1b]7000;v=1;older=0\x1b\\")
	if !strings.Contains(answer, fmt.Sprintf("\x1b]7000;v=1;history=0,%d;cols=9\x1b\\", cold.Rows)) {
		t.Fatalf("the answer does not carry every evicted row:\n%q", answer)
	}
	stream += answer

	receiver, err := vtwasm.New(context.Background(), vtwasm.Module, 20, 4, vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new receiver: %v", err)
	}
	defer receiver.Close()
	if err := receiver.Feed([]byte(stream)); err != nil {
		t.Fatalf("feed: %v", err)
	}
	rendered, err := receiver.RenderTail(200_000)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	rows := strings.Split(strings.TrimRight(rendered, "\n"), "\n")
	if rows[0] != "row 00000" {
		t.Fatalf("the evicted rows were not prepended; first rows = %q", rows[:min(len(rows), 3)])
	}
	if !strings.Contains(rows[len(rows)-1], "row 00299") && !strings.Contains(rendered, "row 00299") {
		t.Fatalf("the live rows are missing:\n%q", rendered)
	}
}

func TestAnOlderRequestBelowTheFloorAnswersWithTheFloorAlone(t *testing.T) {
	f := startServeWithLimits(t, 764, 20, 4, ringLimits)
	defer f.cancel()
	fillPastTheCap(t, f, 300)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 20, 4)
	_ = readStreamUntil(t, c, "\x1b]7000;v=1;older=0\x1b\\")

	requestOlder(t, c, 0)
	answer := readStreamUntil(t, c, "\x1b]7000;v=1;older=0\x1b\\")
	if strings.Contains(answer, "history=") {
		t.Fatalf("nothing is older than row 0, yet a chunk came back:\n%q", answer)
	}
}

func TestRequestOlderWritesOneOlderFrame(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	s := &loopbackStream{conn: client}
	got := make(chan []byte, 1)
	go func() {
		parser := NewMessageParser(func(msgType byte, payload []byte) {
			if msgType == MsgOlderReq {
				got <- payload
			}
		})
		buf := make([]byte, 256)
		n, _ := server.Read(buf)
		parser.Feed(buf[:n])
	}()
	if err := s.RequestOlder(4096); err != nil {
		t.Fatalf("request older: %v", err)
	}
	select {
	case payload := <-got:
		if string(payload) != `{"before":4096}` {
			t.Fatalf("payload = %s", payload)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("no older request frame")
	}
}
PLAN7_EOF
```

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ -run 'Older|RequestOlder' 2>&1 | tail -3
```
Expected: build failure `undefined: OlderReq` / `undefined: MsgOlderReq` / `s.RequestOlder undefined`.

- [ ] **Step 2: Implement**

Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t3-impl.patch <<'PLAN7_PATCH'
diff --git a/backend/internal/adapters/runtime/ptyhost/attach.go b/backend/internal/adapters/runtime/ptyhost/attach.go
index e268651ea..cd6271156 100644
--- a/backend/internal/adapters/runtime/ptyhost/attach.go
+++ b/backend/internal/adapters/runtime/ptyhost/attach.go
@@ -209,6 +209,19 @@ func (s *loopbackStream) Ack(consumed uint64) error {
 	return err
 }
 
+func (s *loopbackStream) RequestOlder(before uint64) error {
+	payload, err := json.Marshal(OlderReq{Before: before})
+	if err != nil {
+		return err
+	}
+	frame, err := EncodeMessage(MsgOlderReq, payload)
+	if err != nil {
+		return err
+	}
+	_, err = s.conn.Write(frame)
+	return err
+}
+
 // writeResize encodes and sends one MsgResize frame.
 func writeResize(w io.Writer, rows, cols uint16) error {
 	return writeResizeWithHistory(w, rows, cols, false)
diff --git a/backend/internal/adapters/runtime/ptyhost/host.go b/backend/internal/adapters/runtime/ptyhost/host.go
index a7c8489bc..7e91029e2 100644
--- a/backend/internal/adapters/runtime/ptyhost/host.go
+++ b/backend/internal/adapters/runtime/ptyhost/host.go
@@ -873,6 +873,8 @@ func (h *host) handleConn(conn net.Conn) {
 
 	if cs.wantsHistory {
 		go h.streamHistory(cs, origin)
+	} else if opening != nil {
+		h.sendOlderMark(cs)
 	}
 
 	defer func() {
@@ -1002,6 +1004,7 @@ func (h *host) streamHistory(cs *clientState, before uint64) {
 			return
 		}
 		if !ok {
+			h.sendOlderMark(cs)
 			return
 		}
 		frame, err := EncodeMessage(MsgTerminalData, []byte(chunk))
@@ -1143,6 +1146,12 @@ func (h *host) handleClientMsg(conn net.Conn, msgType byte, payload []byte) {
 	case MsgRespawnReq:
 		h.handleRespawn(conn, payload)
 
+	case MsgOlderReq:
+		var req OlderReq
+		if err := json.Unmarshal(payload, &req); err == nil {
+			h.serveOlder(conn, req.Before)
+		}
+
 	case MsgAck:
 		var ack AckPayload
 		if err := json.Unmarshal(payload, &ack); err != nil || ack.Bytes < 0 {
diff --git a/backend/internal/adapters/runtime/ptyhost/mirror_limits.go b/backend/internal/adapters/runtime/ptyhost/mirror_limits.go
index 71a6dc2b5..afd6b297c 100644
--- a/backend/internal/adapters/runtime/ptyhost/mirror_limits.go
+++ b/backend/internal/adapters/runtime/ptyhost/mirror_limits.go
@@ -2,4 +2,6 @@ package ptyhost
 
 import "github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
 
-var mirrorLimits = vtwasm.Limits{Rows: 200_000, Bytes: 128 << 20}
+const mirrorColdRingBytes = 32 << 20
+
+var mirrorLimits = vtwasm.Limits{Rows: 200_000, Bytes: 128 << 20, ColdRingBytes: mirrorColdRingBytes}
diff --git a/backend/internal/adapters/runtime/ptyhost/proto.go b/backend/internal/adapters/runtime/ptyhost/proto.go
index ea5f53292..a4eae034a 100644
--- a/backend/internal/adapters/runtime/ptyhost/proto.go
+++ b/backend/internal/adapters/runtime/ptyhost/proto.go
@@ -30,6 +30,7 @@ const (
 	MsgRespawnReq      byte = 0x0F // client -> host: JSON {cwd, shell, launchCmd, launchId}
 	MsgRespawnRes      byte = 0x10 // host -> client: JSON {ok, pid?, error?}
 	MsgAck             byte = 0x11 // client -> host: JSON {bytes}
+	MsgOlderReq        byte = 0x12
 )
 
 // JSON payload structs shared with later tasks (kept minimal).
@@ -85,6 +86,10 @@ type AckPayload struct {
 	Bytes int `json:"bytes"`
 }
 
+type OlderReq struct {
+	Before uint64 `json:"before"`
+}
+
 const frameHeaderBytes = 5
 
 // EncodeMessage encodes a single frame into the binary protocol format.
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t3-impl.patch
```
Create `backend/internal/adapters/runtime/ptyhost/older.go` with exactly this content:

```bash
mkdir -p "$REPO/backend/internal/adapters/runtime/ptyhost"
cat > "$REPO/backend/internal/adapters/runtime/ptyhost/older.go" <<'PLAN7_EOF'
package ptyhost

import (
	"net"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

func (h *host) serveOlder(conn net.Conn, before uint64) {
	h.mu.Lock()
	cs := h.clients[conn]
	h.mu.Unlock()
	parser := h.currentParser()
	if cs == nil || parser == nil {
		return
	}
	chunk, _, _, err := parser.OlderChunk(before, vtwasm.OlderChunkRows)
	if err != nil {
		h.logf("older output: %v", err)
	}
	mark, err := parser.OlderMark()
	if err != nil {
		h.logf("older output mark: %v", err)
	}
	h.queueOlder(cs, []byte(chunk+mark))
}

func (h *host) sendOlderMark(cs *clientState) {
	parser := h.currentParser()
	if parser == nil {
		return
	}
	mark, err := parser.OlderMark()
	if err != nil {
		h.logf("older output mark: %v", err)
		return
	}
	h.queueOlder(cs, []byte(mark))
}

func (h *host) queueOlder(cs *clientState, payload []byte) {
	if len(payload) == 0 {
		return
	}
	frame, err := EncodeMessage(MsgTerminalData, payload)
	if err != nil {
		h.logf("encode older output: %v", err)
		return
	}
	h.mu.Lock()
	cs.enqueue(frame)
	cs.delivered += len(payload)
	h.mu.Unlock()
}
PLAN7_EOF
```

Why `opening != nil` gates the mark for a client without history: short-lived RPC connections (`clientRequestText`, status probes) never send a resize, and must not be sent a mark they never read. `serveOlder` runs on the connection's read goroutine, off `h.mu`; the parser has its own mutex; the frame is queued under `h.mu` behind whatever live batches are already queued, exactly like `streamHistory`'s chunks (`host.go:1015-1018`).

- [ ] **Step 3: Run**

```bash
cd "$REPO/backend" && gofmt -l internal/adapters/runtime/ptyhost
go test ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -3
go vet ./internal/adapters/runtime/ptyhost/... && golangci-lint run ./internal/adapters/runtime/ptyhost/... 2>&1 | tail -1
```
Expected: no gofmt output; three `ok` lines (`ptyhost`, `ptyregistry`, `vtwasm`; `TestProcessEnvironmentLetsOverridesWin` may fail only if it failed in Task 0); `0 issues.`

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add backend/internal/adapters/runtime/ptyhost/proto.go \
  backend/internal/adapters/runtime/ptyhost/mirror_limits.go \
  backend/internal/adapters/runtime/ptyhost/host.go \
  backend/internal/adapters/runtime/ptyhost/attach.go \
  backend/internal/adapters/runtime/ptyhost/older.go \
  backend/internal/adapters/runtime/ptyhost/older_test.go \
  backend/internal/adapters/runtime/ptyhost/attach_replay_test.go
git commit -m "ptyhost: answer older-output requests from the mirror's cold ring and report the floor" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Daemon mux — forward `older` frames to the attach stream

**Files:**
- Modify: `backend/internal/ports/outbound.go:193-195` (after `FlowControlled`), `backend/internal/terminal/protocol.go:40,93-94`, `backend/internal/terminal/manager.go:452-458`, `backend/internal/terminal/attachment.go:295` (after `ack`), `backend/internal/terminal/fakes_test.go:159-181`, `backend/internal/terminal/manager_test.go:880`

**Interfaces:**
- Consumes: Task 3's `(*loopbackStream).RequestOlder`.
- Produces: `ports.OlderOutputRequester interface { RequestOlder(before uint64) error }`; client frame `{"ch":"terminal","type":"older","id":<handle>,"before":<n>}` (`msgOlder = "older"`, `clientMsg.Before uint64`); `(*attachment).requestOlder(before uint64) error` (no-op without a stream or without the capability); a frame with `before == 0` is ignored.

- [ ] **Step 1: Failing tests**

Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t4-tests.patch <<'PLAN7_PATCH'
diff --git a/backend/internal/terminal/fakes_test.go b/backend/internal/terminal/fakes_test.go
index 81799c99c..25c9239a0 100644
--- a/backend/internal/terminal/fakes_test.go
+++ b/backend/internal/terminal/fakes_test.go
@@ -160,6 +160,7 @@ type flowControlledFakePTY struct {
 	*fakePTY
 	mu    sync.Mutex
 	acked uint64
+	older []uint64
 }
 
 func newFlowControlledFakePTY() *flowControlledFakePTY {
@@ -173,6 +174,19 @@ func (p *flowControlledFakePTY) Ack(bytes uint64) error {
 	return nil
 }
 
+func (p *flowControlledFakePTY) RequestOlder(before uint64) error {
+	p.mu.Lock()
+	p.older = append(p.older, before)
+	p.mu.Unlock()
+	return nil
+}
+
+func (p *flowControlledFakePTY) olderRequests() []uint64 {
+	p.mu.Lock()
+	defer p.mu.Unlock()
+	return append([]uint64(nil), p.older...)
+}
+
 func (p *flowControlledFakePTY) ackedBytes() uint64 {
 	p.mu.Lock()
 	defer p.mu.Unlock()
diff --git a/backend/internal/terminal/manager_test.go b/backend/internal/terminal/manager_test.go
index e67194f7a..3de9bc8ce 100644
--- a/backend/internal/terminal/manager_test.go
+++ b/backend/internal/terminal/manager_test.go
@@ -899,6 +899,51 @@ func TestTerminalAckReachesTheStream(t *testing.T) {
 	eventually(t, time.Second, func() bool { return pty.ackedBytes() == 5000 })
 }
 
+func TestTerminalOlderRequestReachesTheStream(t *testing.T) {
+	pty := newFlowControlledFakePTY()
+	src := &fakeSource{alive: true, attachFn: func(ctx context.Context, rows, cols uint16) (ports.Stream, error) {
+		return pty, nil
+	}}
+	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
+	defer mgr.Close()
+
+	conn := newFakeConn()
+	ctx, cancel := context.WithCancel(context.Background())
+	defer cancel()
+	go mgr.Serve(ctx, conn)
+
+	conn.in <- clientMsg{Ch: chTerminal, ID: "pane-5", Type: msgOpen}
+	recv(t, conn, chTerminal, msgOpened, time.Second)
+
+	conn.in <- clientMsg{Ch: chTerminal, ID: "pane-5", Type: msgOlder}
+	conn.in <- clientMsg{Ch: chTerminal, ID: "pane-5", Type: msgOlder, Before: 4096}
+
+	eventually(t, time.Second, func() bool { return len(pty.olderRequests()) == 1 })
+	if got := pty.olderRequests(); got[0] != 4096 {
+		t.Fatalf("older requests = %v, want [4096]", got)
+	}
+}
+
+func TestTerminalOlderRequestOnAStreamWithoutTheCapabilityIsIgnored(t *testing.T) {
+	pty := newFakePTY()
+	src := &fakeSource{alive: true, spawner: &fakeSpawner{ptys: []*fakePTY{pty}}}
+	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
+	defer mgr.Close()
+
+	conn := newFakeConn()
+	ctx, cancel := context.WithCancel(context.Background())
+	defer cancel()
+	go mgr.Serve(ctx, conn)
+
+	conn.in <- clientMsg{Ch: chTerminal, ID: "pane-6", Type: msgOpen}
+	recv(t, conn, chTerminal, msgOpened, time.Second)
+
+	conn.in <- clientMsg{Ch: chTerminal, ID: "pane-6", Type: msgOlder, Before: 10}
+	conn.in <- clientMsg{Ch: chTerminal, ID: "pane-6", Type: msgData, Data: base64.StdEncoding.EncodeToString([]byte("y"))}
+
+	eventually(t, time.Second, func() bool { return string(pty.writtenBytes()) == "y" })
+}
+
 // The desktop declares that it can read history chunks; the daemon forwards
 // that to the runtime, which is what makes the pty-host stream scrollback.
 func TestTerminalOpenForwardsTheHistoryOptIn(t *testing.T) {
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t4-tests.patch
```

```bash
cd "$REPO/backend" && go test ./internal/terminal/ -run Older 2>&1 | tail -3
```
Expected: `undefined: msgOlder` and `unknown field Before in struct literal of type clientMsg`.

- [ ] **Step 2: Implement**

Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t4-impl.patch <<'PLAN7_PATCH'
diff --git a/backend/internal/ports/outbound.go b/backend/internal/ports/outbound.go
index 27e879f33..71d5c49d9 100644
--- a/backend/internal/ports/outbound.go
+++ b/backend/internal/ports/outbound.go
@@ -194,6 +194,10 @@ type FlowControlled interface {
 	Ack(bytes uint64) error
 }
 
+type OlderOutputRequester interface {
+	RequestOlder(before uint64) error
+}
+
 // Attacher opens a fresh attach Stream for a session handle, sized rows x cols from
 // birth (0 means size not yet known). ctx cancellation must terminate the stream.
 type Attacher interface {
diff --git a/backend/internal/terminal/attachment.go b/backend/internal/terminal/attachment.go
index a190a54ef..2d18729b0 100644
--- a/backend/internal/terminal/attachment.go
+++ b/backend/internal/terminal/attachment.go
@@ -293,6 +293,20 @@ func (a *attachment) ack(bytes uint64) error {
 	return flow.Ack(bytes)
 }
 
+func (a *attachment) requestOlder(before uint64) error {
+	a.mu.Lock()
+	pty := a.pty
+	a.mu.Unlock()
+	if pty == nil {
+		return nil
+	}
+	older, ok := pty.(ports.OlderOutputRequester)
+	if !ok {
+		return nil
+	}
+	return older.RequestOlder(before)
+}
+
 // size returns the client's last requested grid (zero before the first
 // open/resize recorded one). The attach path reads it so the Stream starts at
 // the client's grid instead of the kernel default.
diff --git a/backend/internal/terminal/manager.go b/backend/internal/terminal/manager.go
index 5064ed15d..d8ccdaefa 100644
--- a/backend/internal/terminal/manager.go
+++ b/backend/internal/terminal/manager.go
@@ -456,6 +456,13 @@ func (c *connState) handleTerminal(msg clientMsg) {
 		if a := c.lookup(msg.ID); a != nil {
 			_ = a.ack(uint64(msg.Bytes))
 		}
+	case msgOlder:
+		if msg.Before == 0 {
+			return
+		}
+		if a := c.lookup(msg.ID); a != nil {
+			_ = a.requestOlder(msg.Before)
+		}
 	}
 }
 
diff --git a/backend/internal/terminal/protocol.go b/backend/internal/terminal/protocol.go
index 2d9cf69ae..e861da5a5 100644
--- a/backend/internal/terminal/protocol.go
+++ b/backend/internal/terminal/protocol.go
@@ -38,6 +38,7 @@ const (
 	msgSubscribe   = "subscribe"   // ch "subscribe"
 	msgUnsubscribe = "unsubscribe" // ch "blocks"
 	msgPing        = "ping"        // ch "system"
+	msgOlder       = "older"
 )
 
 // server message types.
@@ -92,6 +93,8 @@ type clientMsg struct {
 	// it understands the runtime's history marks.
 	Bytes   int  `json:"bytes,omitempty"`
 	History bool `json:"history,omitempty"`
+
+	Before uint64 `json:"before,omitempty"`
 }
 
 // serverMsg is one outbound frame.
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t4-impl.patch
```

`msgOlder` goes last in the const block: placed before the commented lines it breaks gofmt's comment alignment (golangci-lint `goimports` reported it).

- [ ] **Step 3: Run**

```bash
cd "$REPO/backend" && gofmt -l internal/terminal internal/ports
go test ./internal/terminal/ ./internal/ports/... -count=1 2>&1 | tail -3
go vet ./internal/terminal/ ./internal/ports/ && golangci-lint run ./internal/terminal/... ./internal/ports/... 2>&1 | tail -1
```
Expected: nothing from gofmt; `ok  	github.com/OmarAly92/operator/backend/internal/terminal`; `0 issues.`

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add backend/internal/ports/outbound.go \
  backend/internal/terminal/protocol.go \
  backend/internal/terminal/manager.go \
  backend/internal/terminal/attachment.go \
  backend/internal/terminal/fakes_test.go \
  backend/internal/terminal/manager_test.go
git commit -m "terminal: forward the mux older frame to the pane's attach stream" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Renderer core — floor getters, `olderOutput()`, the string and the seam

**Files:**
- Create: `packages/terminal/ts/core/src/older-output.test.ts`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs:91-93` (after `replay_ready`), `packages/terminal/ts/core/src/types.ts:127,211,236,269`, `packages/terminal/ts/core/src/index-browser.ts:22`, `packages/terminal/ts/core/src/terminal-core.ts:22,199`, `packages/terminal/ts/renderer-dom/src/jump-to-bottom.test.ts:27`, `packages/terminal/ts/renderer-dom/src/palette.test.ts:27`

**Interfaces:**
- Consumes: Task 1's `TerminalCore::older_state()`.
- Produces (wasm-bindgen): `WasmTerminalCore.older_floor() -> f64` (-1 = none), `older_marks() -> u32`. (TS): `type OlderOutput = Readonly<{ floor: number | null; marks: number }>`; `TerminalCore.olderOutput(): OlderOutput` (`{ floor: null, marks: 0 }` once disposed); `TerminalStrings.loadOlderOutput` (default `"Load older output"`); `HostCapabilities.loadOlderOutput?(beforeStableRow: number): void`.
- Note: after this task `frontend` typecheck fails until Task 7 adds `loadOlderOutput` to `BlockTerminal`'s strings object. That is expected; Task 7 closes it.

- [ ] **Step 1: Failing test**

Create `packages/terminal/ts/core/src/older-output.test.ts` with exactly this content:

```bash
mkdir -p "$REPO/packages/terminal/ts/core/src"
cat > "$REPO/packages/terminal/ts/core/src/older-output.test.ts" <<'PLAN7_EOF'
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore, type TerminalCore } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function rowTexts(core: TerminalCore): string[] {
	const snapshot = core.snapshot();
	const rows: string[] = [];
	for (let index = 0; index < snapshot.rows.length / 2; index += 1) {
		rows.push(decoder.decode(snapshot.content.subarray(snapshot.rows[index * 2]!, snapshot.rows[index * 2 + 1]!)));
	}
	while (rows.length > 0 && rows.at(-1) === "") rows.pop();
	return rows;
}

describe("olderOutput", () => {
	it("reports no floor until a mark arrives", () => {
		const core = createTerminalCore({ columns: 20, rows: 4, limits: { rows: 100, bytes: 1 << 20 } });
		expect(core.olderOutput()).toEqual({ floor: null, marks: 0 });
		core.feed(encoder.encode("\x1b]7000;v=1;older=7\x1b\\"));
		expect(core.olderOutput()).toEqual({ floor: 7, marks: 1 });
		core.feed(encoder.encode("\x1b]7000;v=1;older=7\x1b\\"));
		expect(core.olderOutput()).toEqual({ floor: 7, marks: 2 });
		core.dispose();
	});

	it("prepends a chunk of older rows above a core that has trimmed", () => {
		const core = createTerminalCore({ columns: 20, rows: 3, limits: { rows: 10, bytes: 1 << 20 } });
		for (let index = 0; index < 30; index += 1) core.feed(encoder.encode(`live ${index}\r\n`));
		const front = core.snapshot().firstStableRow;
		expect(front).toBeGreaterThan(2);
		core.feed(
			encoder.encode(
				`\x1b]7000;v=1;history=${front - 2},2;cols=30\x1b\\\x1b[0m\x1b[31mold one\x1b[0m\r\n\x1b[0mold two\x1b[0m\r\n\x1b]7000;v=1;older=0\x1b\\`,
			),
		);
		expect(core.snapshot().firstStableRow).toBe(front - 2);
		expect(rowTexts(core).slice(0, 2)).toEqual(["old one", "old two"]);
		expect(core.olderOutput().floor).toBe(0);
		core.dispose();
	});

	it("reads no floor from a disposed core", () => {
		const core = createTerminalCore({ columns: 20, rows: 3, limits: { rows: 10, bytes: 1 << 20 } });
		core.feed(encoder.encode("\x1b]7000;v=1;older=3\x1b\\"));
		core.dispose();
		expect(core.olderOutput()).toEqual({ floor: null, marks: 0 });
	});
});
PLAN7_EOF
```

```bash
cd "$REPO/packages/terminal/ts/core" && npx vitest run src/older-output.test.ts 2>&1 | tail -4
```
Expected: FAIL, `core.olderOutput is not a function`.

- [ ] **Step 2: Implement**

Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t5-impl.patch <<'PLAN7_PATCH'
diff --git a/packages/terminal/crates/vt-wasm/src/lib.rs b/packages/terminal/crates/vt-wasm/src/lib.rs
index f58c05342..eb13fa97c 100644
--- a/packages/terminal/crates/vt-wasm/src/lib.rs
+++ b/packages/terminal/crates/vt-wasm/src/lib.rs
@@ -92,6 +92,17 @@ impl WasmTerminalCore {
         self.core.replay_ready()
     }
 
+    pub fn older_floor(&self) -> f64 {
+        self.core
+            .older_state()
+            .floor
+            .map_or(-1.0, |floor| floor as f64)
+    }
+
+    pub fn older_marks(&self) -> u32 {
+        self.core.older_state().marks
+    }
+
     pub fn resize(&mut self, columns: usize, rows: usize) -> Result<(), JsError> {
         self.core.resize(columns, rows);
         Ok(())
diff --git a/packages/terminal/ts/core/src/index-browser.ts b/packages/terminal/ts/core/src/index-browser.ts
index a87998398..57f2aa2c2 100644
--- a/packages/terminal/ts/core/src/index-browser.ts
+++ b/packages/terminal/ts/core/src/index-browser.ts
@@ -20,6 +20,7 @@ export type {
 	HistoryStore,
 	LineEditorState,
 	MemoryStats,
+	OlderOutput,
 	PaletteCommand,
 	PasteUnsafeReason,
 	PathCandidate,
diff --git a/packages/terminal/ts/core/src/terminal-core.ts b/packages/terminal/ts/core/src/terminal-core.ts
index cd8c80258..46b730c67 100644
--- a/packages/terminal/ts/core/src/terminal-core.ts
+++ b/packages/terminal/ts/core/src/terminal-core.ts
@@ -20,6 +20,7 @@ import type {
 	HostCapabilities,
 	LineEditorState,
 	MemoryStats,
+	OlderOutput,
 	RowEvent,
 	RowEventListener,
 	RowRange,
@@ -196,6 +197,14 @@ export class TerminalCore {
 		return this.inner.replay_ready();
 	}
 
+	olderOutput(): OlderOutput {
+		if (this.disposed) {
+			return { floor: null, marks: 0 };
+		}
+		const floor = this.inner.older_floor();
+		return { floor: floor < 0 ? null : floor, marks: this.inner.older_marks() };
+	}
+
 	private notifyIfChanged(): boolean {
 		const generation = this.inner.generation();
 		if (generation === this.lastNotifiedGeneration) {
diff --git a/packages/terminal/ts/core/src/types.ts b/packages/terminal/ts/core/src/types.ts
index bbfd736f6..d386515d7 100644
--- a/packages/terminal/ts/core/src/types.ts
+++ b/packages/terminal/ts/core/src/types.ts
@@ -126,6 +126,8 @@ export type AltScreenView = Readonly<{
 
 export type TerminalLimits = Readonly<{ rows: number; bytes: number }>;
 
+export type OlderOutput = Readonly<{ floor: number | null; marks: number }>;
+
 export type MemoryStats = Readonly<{
 	contentBytes: number;
 	styleEntries: number;
@@ -209,6 +211,7 @@ export type TerminalStrings = Readonly<{
 	paletteLabel: string;
 	paletteNoMatches: string;
 	jumpToBottom: string;
+	loadOlderOutput: string;
 }>;
 
 export const defaultStrings: TerminalStrings = Object.freeze({
@@ -234,6 +237,7 @@ export const defaultStrings: TerminalStrings = Object.freeze({
 	paletteLabel: "Command palette",
 	paletteNoMatches: "No matching commands",
 	jumpToBottom: "Jump to bottom",
+	loadOlderOutput: "Load older output",
 });
 
 export type PaletteCommand = Readonly<{
@@ -267,6 +271,7 @@ export type HostCapabilities = Readonly<{
 	secretPatterns?: readonly SecretPattern[];
 	predictiveEcho?: Readonly<{ thresholdMs: number }>;
 	confirmPaste?(preview: string, reason: PasteUnsafeReason): Promise<boolean>;
+	loadOlderOutput?(beforeStableRow: number): void;
 }>;
 
 export type HistoryStore = {
diff --git a/packages/terminal/ts/renderer-dom/src/jump-to-bottom.test.ts b/packages/terminal/ts/renderer-dom/src/jump-to-bottom.test.ts
index 0a981a6aa..aa8c4b463 100644
--- a/packages/terminal/ts/renderer-dom/src/jump-to-bottom.test.ts
+++ b/packages/terminal/ts/renderer-dom/src/jump-to-bottom.test.ts
@@ -25,6 +25,7 @@ const STRINGS: TerminalStrings = {
 	paletteLabel: "Command palette",
 	paletteNoMatches: "No matching commands",
 	jumpToBottom: "Jump to bottom",
+	loadOlderOutput: "Load older output",
 };
 
 function makeBlock(id: string, command: string, rowCount: number): BlockView {
diff --git a/packages/terminal/ts/renderer-dom/src/palette.test.ts b/packages/terminal/ts/renderer-dom/src/palette.test.ts
index 6066888b2..ae673cd1c 100644
--- a/packages/terminal/ts/renderer-dom/src/palette.test.ts
+++ b/packages/terminal/ts/renderer-dom/src/palette.test.ts
@@ -25,6 +25,7 @@ const STRINGS: TerminalStrings = {
 	paletteLabel: "Command palette",
 	paletteNoMatches: "No matching commands",
 	jumpToBottom: "Jump to bottom",
+	loadOlderOutput: "Load older output",
 };
 
 function key(init: Partial<KeyboardEventInit> & { key: string }): KeyboardEvent {
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t5-impl.patch
```

- [ ] **Step 3: Rebuild and run**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
npm run build:wasm -- --force && npm run build:ts
(cd ts/core && npx vitest run 2>&1 | grep -E "Test Files|Tests  ")
(cd ts/renderer-dom && npx vitest run 2>&1 | grep -E "Test Files|Tests  ")
wc -l crates/vt-wasm/src/lib.rs ts/core/src/terminal-core.ts
```
Expected: `build-wasm: vt_core.js, vt_core.d.ts, vt_core_bg.wasm, vt_core_bg.wasm.d.ts ready`; `tsc -b` silent; core `Tests  83 passed` (80 on the Task 0 tree + 3), renderer-dom all passed; `572` and `573`.

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-wasm/src/lib.rs \
  packages/terminal/ts/core/src/types.ts \
  packages/terminal/ts/core/src/index-browser.ts \
  packages/terminal/ts/core/src/terminal-core.ts \
  packages/terminal/ts/core/src/older-output.test.ts \
  packages/terminal/ts/renderer-dom/src/jump-to-bottom.test.ts \
  packages/terminal/ts/renderer-dom/src/palette.test.ts
git commit -m "core: read the older-output floor and add the loadOlderOutput string and host seam" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: The Load older output button

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/load-older.ts`, `load-older.test.ts`, `dom-block-renderer.older.test.ts`, `packages/terminal/ts/react/src/TerminalSurface.older.test.tsx`
- Modify: `packages/terminal/ts/renderer-dom/src/index.ts:17`, `packages/terminal/ts/react/src/TerminalSurface.tsx:4-12` (imports), `:114` (refs), `:187` (after `findBar.mount(blockHost);`), `:199-205` (refs + cleanup), `:246-248` (strings effect)

**Interfaces:**
- Consumes: Task 5's `OlderOutput`, `TerminalCore.olderOutput()`, `TerminalStrings.loadOlderOutput`, `HostCapabilities.loadOlderOutput`.
- Produces (`@operator/terminal-renderer-dom`): `mountLoadOlder(options: LoadOlderOptions): LoadOlder`; `LoadOlderOptions = { container; source: LoadOlderSource; strings: TerminalStrings; load(beforeStableRow: number): void }`; `LoadOlderSource = { canLoad(): boolean; firstStableRow(): number; altScreenActive(): boolean; olderOutput(): OlderOutput }`; `LoadOlder = { update(); setStrings(strings); dispose(); isButtonVisible(): boolean }`; `LOAD_OLDER_RETRY_MS = 10_000`. DOM: `<button type="button" class="terminal-load-older" data-terminal-load-older>`.

- [ ] **Step 1: Failing tests**

Create `packages/terminal/ts/renderer-dom/src/load-older.test.ts` with exactly this content:

```bash
mkdir -p "$REPO/packages/terminal/ts/renderer-dom/src"
cat > "$REPO/packages/terminal/ts/renderer-dom/src/load-older.test.ts" <<'PLAN7_EOF'
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { defaultStrings, type OlderOutput } from "@operator/terminal-core";
import { LOAD_OLDER_RETRY_MS, mountLoadOlder, type LoadOlder } from "./load-older";

type Fake = { front: number; alt: boolean; canLoad: boolean; older: OlderOutput };

function harness(initial: Partial<Fake> = {}) {
	const state: Fake = { front: 0, alt: false, canLoad: true, older: { floor: null, marks: 0 }, ...initial };
	const container = document.createElement("div");
	document.body.append(container);
	const load = vi.fn<(before: number) => void>();
	const handle: LoadOlder = mountLoadOlder({
		container,
		source: {
			canLoad: () => state.canLoad,
			firstStableRow: () => state.front,
			altScreenActive: () => state.alt,
			olderOutput: () => state.older,
		},
		strings: { ...defaultStrings, loadOlderOutput: "Load older output" },
		load,
	});
	const button = () => container.querySelector<HTMLButtonElement>("[data-terminal-load-older]");
	return { state, container, load, handle, button };
}

describe("mountLoadOlder", () => {
	beforeEach(() => {
		vi.useFakeTimers();
	});

	afterEach(() => {
		vi.useRealTimers();
		document.body.replaceChildren();
	});

	it("shows nothing until the host has reported a floor", () => {
		const h = harness({ front: 500 });
		expect(h.button()).toBeNull();
		expect(h.handle.isButtonVisible()).toBe(false);
	});

	it("shows the button only while rows older than the pane exist", () => {
		const h = harness({ front: 500, older: { floor: 500, marks: 1 } });
		expect(h.button()).toBeNull();
		h.state.older = { floor: 200, marks: 2 };
		h.handle.update();
		expect(h.button()?.textContent).toBe("Load older output");
		expect(h.button()?.title).toBe("Load older output");
	});

	it("shows nothing when the host has no way to load", () => {
		const h = harness({ front: 500, canLoad: false, older: { floor: 0, marks: 1 } });
		expect(h.button()).toBeNull();
		h.state.canLoad = true;
		h.handle.update();
		expect(h.button()).not.toBeNull();
	});

	it("relabels the button when the host's strings change", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		h.handle.setStrings({ ...defaultStrings, loadOlderOutput: "Ältere Ausgabe laden" });
		expect(h.button()?.textContent).toBe("Ältere Ausgabe laden");
		expect(h.button()?.title).toBe("Ältere Ausgabe laden");
	});

	it("hides the button on the alternate screen", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		expect(h.button()).not.toBeNull();
		h.state.alt = true;
		h.handle.update();
		expect(h.button()).toBeNull();
	});

	it("asks for the rows above the pane's first row and waits for the answer", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		h.button()!.click();
		expect(h.load).toHaveBeenCalledWith(500);
		expect(h.button()).toBeNull();
		h.button()?.click();
		expect(h.load).toHaveBeenCalledTimes(1);
		h.state.front = 0;
		h.state.older = { floor: 0, marks: 2 };
		h.handle.update();
		expect(h.button()).toBeNull();
	});

	it("comes back when the answer leaves older rows still to load", () => {
		const h = harness({ front: 5000, older: { floor: 0, marks: 1 } });
		h.button()!.click();
		h.state.front = 2952;
		h.state.older = { floor: 0, marks: 2 };
		h.handle.update();
		expect(h.button()).not.toBeNull();
		h.button()!.click();
		expect(h.load).toHaveBeenLastCalledWith(2952);
	});

	it("disappears when the answer says nothing older is left", () => {
		const h = harness({ front: 500, older: { floor: 100, marks: 1 } });
		h.button()!.click();
		h.state.older = { floor: 500, marks: 2 };
		h.handle.update();
		expect(h.button()).toBeNull();
	});

	it("reappears once the pane's own cap trims the loaded rows again", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		h.button()!.click();
		h.state.front = 0;
		h.state.older = { floor: 0, marks: 2 };
		h.handle.update();
		expect(h.button()).toBeNull();
		h.state.front = 501;
		h.handle.update();
		expect(h.button()).not.toBeNull();
	});

	it("offers the button again when no answer arrives", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		h.button()!.click();
		expect(h.button()).toBeNull();
		vi.advanceTimersByTime(LOAD_OLDER_RETRY_MS);
		expect(h.button()).not.toBeNull();
	});

	it("removes the button, its listener and its timer on dispose", () => {
		const h = harness({ front: 500, older: { floor: 0, marks: 1 } });
		const button = h.button()!;
		const removeListener = vi.spyOn(button, "removeEventListener");
		button.click();
		expect(vi.getTimerCount()).toBe(1);
		h.handle.dispose();
		expect(vi.getTimerCount()).toBe(0);
		expect(removeListener).toHaveBeenCalledWith("click", expect.any(Function));
		expect(h.container.querySelector("[data-terminal-load-older]")).toBeNull();
		h.state.front = 900;
		h.handle.update();
		expect(h.container.querySelector("[data-terminal-load-older]")).toBeNull();
		button.click();
		expect(h.load).toHaveBeenCalledTimes(1);
	});
});
PLAN7_EOF
```
Create `packages/terminal/ts/renderer-dom/src/dom-block-renderer.older.test.ts` with exactly this content:

```bash
mkdir -p "$REPO/packages/terminal/ts/renderer-dom/src"
cat > "$REPO/packages/terminal/ts/renderer-dom/src/dom-block-renderer.older.test.ts" <<'PLAN7_EOF'
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "./index";
import { feed, flushRepaint, font, loadedCore } from "./renderer-harness";

beforeAll(async () => {
	await loadedCore();
});

function scrollable(): HTMLElement {
	const container = document.createElement("div");
	Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
	Object.defineProperty(container, "scrollHeight", { value: 100_000, configurable: true });
	Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
	return container;
}

describe("older rows prepended at the top of scrollback", () => {
	it("keep the row under the top edge where it was", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 20, limits: { rows: 60, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 100; i += 1) feed(core, `line ${i}\r\n`);
		const front = core.snapshot().firstStableRow;
		expect(front).toBeGreaterThan(3);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		const rowHeight = renderer.measure().cellHeight;
		container.scrollTop = Math.round(rowHeight * 2);
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const anchor = renderer.scrollAnchor()!;
		const textBefore = container.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)?.textContent;
		const before = container.scrollTop;

		feed(
			core,
			`\x1b]7000;v=1;history=${front - 3},3;cols=5\x1b\\old a\r\nold b\r\nold c\r\n\x1b]7000;v=1;older=0\x1b\\`,
		);
		await flushRepaint();

		expect(core.snapshot().firstStableRow).toBe(front - 3);
		expect(renderer.scrollAnchor()).toEqual(anchor);
		expect(container.scrollTop).toBeCloseTo(before + 3 * rowHeight, 3);
		expect(container.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)?.textContent).toBe(textBefore);
		renderer.dispose();
	});
});
PLAN7_EOF
```
Create `packages/terminal/ts/react/src/TerminalSurface.older.test.tsx` with exactly this content:

```bash
mkdir -p "$REPO/packages/terminal/ts/react/src"
cat > "$REPO/packages/terminal/ts/react/src/TerminalSurface.older.test.tsx" <<'PLAN7_EOF'
import { act } from "@testing-library/react";
import { beforeAll, describe, expect, it, vi } from "vitest";
import type { HostCapabilities } from "@operator/terminal-core";
import { feed, flushRepaint, loadWasm, renderSurface } from "./surface-harness";

beforeAll(async () => {
	await loadWasm();
});

function hostWith(loadOlderOutput?: (before: number) => void): HostCapabilities {
	return {
		writeClipboard: async () => undefined,
		readClipboard: async () => "",
		openLink: async () => undefined,
		...(loadOlderOutput ? { loadOlderOutput } : {}),
	};
}

async function paint(): Promise<void> {
	await act(async () => {
		await flushRepaint();
		await flushRepaint();
	});
}

const button = (host: HTMLElement) => host.querySelector<HTMLButtonElement>("[data-terminal-load-older]");

function trimmedPast(core: ReturnType<typeof renderSurface>["core"]): number {
	for (let i = 0; i < 150; i += 1) feed(core, `line ${i}\r\n`);
	return core.snapshot().firstStableRow;
}

describe("TerminalSurface load older output", () => {
	it("offers the button once the host reports older rows and asks for the rows above the first one", async () => {
		const load = vi.fn<(before: number) => void>();
		const { core, host, unmount } = renderSurface({ host: hostWith(load) });
		const front = trimmedPast(core);
		await paint();
		expect(button(host)).toBeNull();

		feed(core, "\x1b]7000;v=1;older=0\x1b\\");
		await paint();
		expect(button(host)?.textContent).toBe("Load older output");

		act(() => button(host)!.click());
		expect(load).toHaveBeenCalledWith(front);
		expect(button(host)).toBeNull();

		feed(
			core,
			`\x1b]7000;v=1;history=${front - 2},2;cols=8\x1b\\older 1\r\nolder 2\r\n\x1b]7000;v=1;older=${front - 2}\x1b\\`,
		);
		await paint();
		expect(core.snapshot().firstStableRow).toBe(front - 2);
		expect(button(host)).toBeNull();
		unmount();
	});

	it("never offers the button to a host that cannot load", async () => {
		const { core, host, unmount } = renderSurface({ host: hostWith() });
		trimmedPast(core);
		feed(core, "\x1b]7000;v=1;older=0\x1b\\");
		await paint();
		expect(button(host)).toBeNull();
		unmount();
	});

	it("takes the button away when the surface unmounts", async () => {
		const load = vi.fn<(before: number) => void>();
		const { core, host, unmount } = renderSurface({ host: hostWith(load) });
		trimmedPast(core);
		feed(core, "\x1b]7000;v=1;older=0\x1b\\");
		await paint();
		const shown = button(host)!;
		unmount();
		expect(host.contains(shown)).toBe(false);
		shown.click();
		expect(load).not.toHaveBeenCalled();
	});
});
PLAN7_EOF
```

```bash
cd "$REPO/packages/terminal/ts/renderer-dom" && npx vitest run src/load-older.test.ts src/dom-block-renderer.older.test.ts 2>&1 | tail -5
```
Expected: `load-older.test.ts` fails (`Failed to resolve import "./load-older"`); `dom-block-renderer.older.test.ts` already passes — it proves the existing stable-row anchor keeps the view still across a prepend, and must keep passing.

- [ ] **Step 2: Implement the button**

Create `packages/terminal/ts/renderer-dom/src/load-older.ts` with exactly this content:

```bash
mkdir -p "$REPO/packages/terminal/ts/renderer-dom/src"
cat > "$REPO/packages/terminal/ts/renderer-dom/src/load-older.ts" <<'PLAN7_EOF'
import type { OlderOutput, TerminalStrings } from "@operator/terminal-core";

const CLASS_BUTTON = "terminal-load-older";
const ATTR_BUTTON = "data-terminal-load-older";

export const LOAD_OLDER_RETRY_MS = 10_000;

export type LoadOlderSource = Readonly<{
	canLoad(): boolean;
	firstStableRow(): number;
	altScreenActive(): boolean;
	olderOutput(): OlderOutput;
}>;

export type LoadOlderOptions = Readonly<{
	container: HTMLElement;
	source: LoadOlderSource;
	strings: TerminalStrings;
	load(beforeStableRow: number): void;
}>;

export type LoadOlder = Readonly<{
	update(): void;
	setStrings(strings: TerminalStrings): void;
	dispose(): void;
	isButtonVisible(): boolean;
}>;

type Pending = { marks: number; front: number };

export function mountLoadOlder(options: LoadOlderOptions): LoadOlder {
	const { container, source, load } = options;
	let pending: Pending | null = null;
	let retryTimer: ReturnType<typeof setTimeout> | null = null;
	let disposed = false;

	const button = document.createElement("button");
	button.type = "button";
	button.className = CLASS_BUTTON;
	button.setAttribute(ATTR_BUTTON, "");
	button.style.position = "absolute";
	button.style.top = "8px";
	button.style.left = "50%";
	button.style.transform = "translateX(-50%)";
	button.style.zIndex = "10";
	button.style.padding = "2px 10px";
	button.style.borderRadius = "4px";
	button.style.border = "1px solid var(--terminal-block-border, currentColor)";
	button.style.background = "var(--terminal-block-background, transparent)";
	button.style.color = "var(--terminal-block-header-foreground, inherit)";
	button.style.font = "12px var(--terminal-font-family, ui-monospace, monospace)";
	button.style.cursor = "pointer";

	const setStrings = (strings: TerminalStrings): void => {
		button.textContent = strings.loadOlderOutput;
		button.title = strings.loadOlderOutput;
	};
	setStrings(options.strings);

	const clearRetry = (): void => {
		if (retryTimer !== null) clearTimeout(retryTimer);
		retryTimer = null;
	};

	const available = (): boolean => {
		if (!source.canLoad() || source.altScreenActive()) return false;
		const { floor } = source.olderOutput();
		return floor !== null && floor < source.firstStableRow();
	};

	const settlePending = (): void => {
		if (!pending) return;
		if (source.olderOutput().marks !== pending.marks || source.firstStableRow() !== pending.front) {
			pending = null;
			clearRetry();
		}
	};

	const update = (): void => {
		if (disposed) return;
		settlePending();
		const show = pending === null && available();
		const shown = button.parentElement === container;
		if (show && !shown) container.append(button);
		else if (!show && shown) button.remove();
	};

	const onClick = (event: MouseEvent): void => {
		event.preventDefault();
		event.stopPropagation();
		if (pending || !available()) return;
		const front = source.firstStableRow();
		pending = { marks: source.olderOutput().marks, front };
		clearRetry();
		retryTimer = setTimeout(() => {
			retryTimer = null;
			pending = null;
			update();
		}, LOAD_OLDER_RETRY_MS);
		update();
		load(front);
	};

	button.addEventListener("click", onClick);
	update();

	return {
		update,
		setStrings,
		dispose: () => {
			if (disposed) return;
			disposed = true;
			clearRetry();
			button.removeEventListener("click", onClick);
			button.remove();
			pending = null;
		},
		isButtonVisible: () => button.parentElement === container,
	};
}
PLAN7_EOF
```
Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t6-impl.patch <<'PLAN7_PATCH'
diff --git a/packages/terminal/ts/react/src/TerminalSurface.tsx b/packages/terminal/ts/react/src/TerminalSurface.tsx
index de74aa923..d4c709229 100644
--- a/packages/terminal/ts/react/src/TerminalSurface.tsx
+++ b/packages/terminal/ts/react/src/TerminalSurface.tsx
@@ -5,11 +5,13 @@ import {
 	createPathProvider,
 	DEFAULT_LINK_PROVIDERS,
 	DomBlockRenderer,
+	mountLoadOlder,
 	RERUN_EVENT,
 	resolveFeatures,
 	type BlockFinishedEvent,
 	type FindBar,
 	type HintEvent,
+	type LoadOlder,
 	type RendererFeatures,
 } from "@operator/terminal-renderer-dom";
 import { isCopyChord } from "./selection-gesture.js";
@@ -110,6 +112,7 @@ export function TerminalSurface({
 	const visibleRef = useRef(visible);
 	visibleRef.current = visible;
 	const findBarRef = useRef<FindBar | null>(null);
+	const loadOlderRef = useRef<LoadOlder | null>(null);
 	const gridColumnsRef = useRef(0);
 	const gridRowsRef = useRef(0);
 	const compositionRef = useRef<CompositionTarget | null>(null);
@@ -186,6 +189,18 @@ export function TerminalSurface({
 			strings,
 		});
 		findBar.mount(blockHost);
+		const loadOlder = mountLoadOlder({
+			container: blockHost,
+			source: {
+				canLoad: () => hostCapsRef.current?.loadOlderOutput !== undefined,
+				firstStableRow: () => core.snapshot().firstStableRow,
+				altScreenActive: () => core.snapshot().altScreen !== null,
+				olderOutput: () => core.olderOutput(),
+			},
+			strings,
+			load: (before) => hostCapsRef.current?.loadOlderOutput?.(before),
+		});
+		const offOlder = renderer.onPaint(() => loadOlder.update());
 		const onRerun = (event: Event) => {
 			const blockId = (event as CustomEvent<{ blockId?: string }>).detail?.blockId;
 			if (!blockId) return;
@@ -200,6 +215,7 @@ export function TerminalSurface({
 		rendererRef.current = renderer;
 		editorRef.current = editor;
 		findBarRef.current = findBar;
+		loadOlderRef.current = loadOlder;
 		editor.setVisible(visibleRef.current !== false);
 		applyLinkProviders();
 		applyPredictiveEchoRef.current();
@@ -207,6 +223,9 @@ export function TerminalSurface({
 			blockHost.removeEventListener(RERUN_EVENT, onRerun);
 			offPaint();
 			offFinished();
+			offOlder();
+			loadOlder.dispose();
+			loadOlderRef.current = null;
 			findBar.dispose();
 			editor.dispose();
 			renderer.predictionsClear();
@@ -247,6 +266,7 @@ export function TerminalSurface({
 
 	useLayoutEffect(() => {
 		editorRef.current?.setStrings(strings);
+		loadOlderRef.current?.setStrings(strings);
 	}, [strings]);
 
 	useLayoutEffect(() => {
diff --git a/packages/terminal/ts/renderer-dom/src/index.ts b/packages/terminal/ts/renderer-dom/src/index.ts
index d240850cb..5537a226f 100644
--- a/packages/terminal/ts/renderer-dom/src/index.ts
+++ b/packages/terminal/ts/renderer-dom/src/index.ts
@@ -15,4 +15,5 @@ export { styleCodeToCssVar } from "./style-code.js";
 export { terminalStyles } from "./styles.js";
 export { createFindBar, type FindBar, type FindBarHost, type FindBarOptions } from "./find-bar.js";
 export { mountJumpToBottom, type JumpToBottom, type JumpToBottomOptions } from "./jump-to-bottom.js";
+export { LOAD_OLDER_RETRY_MS, mountLoadOlder, type LoadOlder, type LoadOlderOptions, type LoadOlderSource } from "./load-older.js";
 export { mountPalette, type Palette, type PaletteHost, type PaletteOptions } from "./palette.js";
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t6-impl.patch
```

Teardown order in `TerminalSurface`'s cleanup: the paint listener is removed (`offOlder()`) and the button disposed (click listener, retry timer, node) before the find bar, editor and renderer, so no update runs against a disposed core.

- [ ] **Step 3: Run**

```bash
cd "$REPO/packages/terminal" && npm run build:ts
for p in core renderer-dom react editor; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Test Files|Tests  "); done
npm run check:boundaries 2>&1 | tail -2
```
Expected: `tsc -b` silent; all passed (renderer-dom +12 tests: 11 in `load-older.test.ts`, 1 in `dom-block-renderer.older.test.ts`; react +3); `boundary check passed`.

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add packages/terminal/ts/renderer-dom/src/load-older.ts \
  packages/terminal/ts/renderer-dom/src/load-older.test.ts \
  packages/terminal/ts/renderer-dom/src/dom-block-renderer.older.test.ts \
  packages/terminal/ts/renderer-dom/src/index.ts \
  packages/terminal/ts/react/src/TerminalSurface.tsx \
  packages/terminal/ts/react/src/TerminalSurface.older.test.tsx
git commit -m "renderer-dom/react: offer Load older output at the top of scrollback" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Operator seam — mux frame, transport, BlockTerminal host

**Files:**
- Modify: `frontend/src/renderer/lib/terminal-mux.ts:9,93-95,152,333-335,461-463`, `frontend/src/renderer/hooks/useTerminalSession.ts:1004` (in `transport`), `frontend/src/renderer/components/BlockTerminal.tsx:40-41,488-490,526`, tests `lib/terminal-mux.test.ts`, `hooks/useTerminalSession.test.tsx`, `components/BlockTerminal.test.tsx`, `components/TerminalPane.test.tsx:69`

**Interfaces:**
- Consumes: Task 4's mux frame, Task 5's `HostCapabilities.loadOlderOutput` and string.
- Produces: `olderFrame(id, before): string`; `TerminalMux.requestOlder(id, before)` (pool leases drop it after release); transport `requestOlder(before)` (ignored before `opened`, after detach, and for `before <= 0`); `BlockTerminalTransport.requestOlder?`; `host.loadOlderOutput` present only when the transport has `requestOlder`.

- [ ] **Step 1: Failing tests**

Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t7-tests.patch <<'PLAN7_PATCH'
diff --git a/frontend/src/renderer/components/BlockTerminal.test.tsx b/frontend/src/renderer/components/BlockTerminal.test.tsx
index 72665dd8b..a76f872af 100644
--- a/frontend/src/renderer/components/BlockTerminal.test.tsx
+++ b/frontend/src/renderer/components/BlockTerminal.test.tsx
@@ -38,6 +38,7 @@ const mockState = vi.hoisted(() => {
 					secretPatterns?: readonly { source: string; flags?: string }[];
 					predictiveEcho?: Readonly<{ thresholdMs: number }>;
 					confirmPaste?: (preview: string, reason: "newline" | "control" | "paste-end") => Promise<boolean>;
+					loadOlderOutput?: (before: number) => void;
 				}
 			| undefined,
 		onHint: undefined as ((hint: { ruleId: string; text: string; path?: string; line?: number }) => void) | undefined,
@@ -162,6 +163,7 @@ vi.mock("@operator/terminal-react", () => {
 				secretPatterns?: readonly { source: string; flags?: string }[];
 				predictiveEcho?: Readonly<{ thresholdMs: number }>;
 				confirmPaste?: (preview: string, reason: "newline" | "control" | "paste-end") => Promise<boolean>;
+				loadOlderOutput?: (before: number) => void;
 			};
 			strings?: Record<string, string>;
 			onSend?: (text: string) => void;
@@ -343,6 +345,7 @@ function renderTerminal(
 		focusToken?: number;
 		visible?: boolean;
 		workspacePath?: string;
+		requestOlder?: (before: number) => void;
 	} = {},
 ) {
 	const localListeners: Array<(bytes: Uint8Array) => void> = [];
@@ -356,6 +359,7 @@ function renderTerminal(
 		},
 		resize: vi.fn(),
 		dispose: vi.fn(),
+		...(options.requestOlder ? { requestOlder: options.requestOlder } : {}),
 	};
 	render(
 		<QueryClientProvider client={new QueryClient()}>
@@ -912,3 +916,20 @@ describe("BlockTerminal paste confirm", () => {
 		await expect(answer).resolves.toBe(false);
 	});
 });
+
+describe("BlockTerminal load older output", () => {
+	it("hands the surface a loader that asks the transport for the rows above a stable row", async () => {
+		const requestOlder = vi.fn();
+		renderTerminal({ requestOlder });
+		await waitFor(() => expect(mockState.host?.loadOlderOutput).toBeTypeOf("function"));
+		mockState.host!.loadOlderOutput!(4096);
+		expect(requestOlder).toHaveBeenCalledWith(4096);
+		expect(mockState.strings?.loadOlderOutput).toBe("Load older output");
+	});
+
+	it("offers no loader when the transport cannot fetch older output", async () => {
+		renderTerminal();
+		await waitFor(() => expect(mockState.host?.confirmPaste).toBeTypeOf("function"));
+		expect(mockState.host?.loadOlderOutput).toBeUndefined();
+	});
+});
diff --git a/frontend/src/renderer/components/TerminalPane.test.tsx b/frontend/src/renderer/components/TerminalPane.test.tsx
index e2d91784f..83b1cf430 100644
--- a/frontend/src/renderer/components/TerminalPane.test.tsx
+++ b/frontend/src/renderer/components/TerminalPane.test.tsx
@@ -67,6 +67,7 @@ vi.mock("../lib/terminal-mux", async (importOriginal) => {
 		resize: () => undefined,
 		close: () => undefined,
 		ack: () => undefined,
+		requestOlder: () => undefined,
 		onData: () => () => undefined,
 		onExit: () => () => undefined,
 		onOpened: () => () => undefined,
diff --git a/frontend/src/renderer/hooks/useTerminalSession.test.tsx b/frontend/src/renderer/hooks/useTerminalSession.test.tsx
index a99eb8102..59ba8372d 100644
--- a/frontend/src/renderer/hooks/useTerminalSession.test.tsx
+++ b/frontend/src/renderer/hooks/useTerminalSession.test.tsx
@@ -28,6 +28,7 @@ type FakeMux = {
 	inputs: Array<[string, string]>;
 	closes: string[];
 	acks: number[];
+	olders: Array<[string, number]>;
 	events: string[];
 	disposed: boolean;
 	emitData(id: string, text: string): void;
@@ -61,6 +62,7 @@ function createFakeMux(): FakeMux {
 		inputs: [],
 		closes: [],
 		acks: [],
+		olders: [],
 		events: [],
 		disposed: false,
 		mux: {
@@ -75,6 +77,7 @@ function createFakeMux(): FakeMux {
 				fake.events.push(`close:${id}`);
 			},
 			ack: (_id, bytes) => fake.acks.push(bytes),
+			requestOlder: (id, before) => fake.olders.push([id, before]),
 			onData: (id, listener) => subscribe(data, id, listener),
 			onExit: (id, listener) => subscribe(exit, id, listener),
 			onOpened: (id, listener) => subscribe(opened, id, listener),
@@ -283,6 +286,19 @@ describe("useTerminalSession", () => {
 		expect(view.result.current.state).toBe("attached");
 	});
 
+	it("asks the mux for older output only while attached", () => {
+		const { view, muxes, detach } = setup();
+		act(() => view.result.current.transport.requestOlder(4096));
+		expect(muxes[0].olders).toEqual([]);
+		act(() => muxes[0].emitOpened("handle-1"));
+		act(() => view.result.current.transport.requestOlder(0));
+		act(() => view.result.current.transport.requestOlder(4096));
+		expect(muxes[0].olders).toEqual([["handle-1", 4096]]);
+		detach();
+		act(() => view.result.current.transport.requestOlder(2048));
+		expect(muxes[0].olders).toEqual([["handle-1", 4096]]);
+	});
+
 	it("acks the transport every 5,000 bytes", () => {
 		const { muxes } = setup();
 		act(() => muxes[0].emitOpened("handle-1"));
diff --git a/frontend/src/renderer/lib/terminal-mux.test.ts b/frontend/src/renderer/lib/terminal-mux.test.ts
index 698edb1b4..457fd14d7 100644
--- a/frontend/src/renderer/lib/terminal-mux.test.ts
+++ b/frontend/src/renderer/lib/terminal-mux.test.ts
@@ -7,6 +7,7 @@ import {
 	createTerminalMuxPool,
 	dataFrame,
 	muxUrlFromApiBase,
+	olderFrame,
 	openFrame,
 	resizeFrame,
 } from "./terminal-mux";
@@ -44,6 +45,15 @@ describe("terminal-mux framing", () => {
 		expect(JSON.parse(closeFrame("s"))).toEqual({ ch: "terminal", type: "close", id: "s" });
 	});
 
+	it("asks for the rows above a stable row in an older frame", () => {
+		expect(JSON.parse(olderFrame("sess-1", 4096))).toEqual({
+			ch: "terminal",
+			type: "older",
+			id: "sess-1",
+			before: 4096,
+		});
+	});
+
 	it("derives the ws mux url from the http api base (root path, not /api/v1)", () => {
 		expect(muxUrlFromApiBase("http://127.0.0.1:4317")).toBe("ws://127.0.0.1:4317/mux");
 		expect(muxUrlFromApiBase("https://host:8443/")).toBe("wss://host:8443/mux");
@@ -425,6 +435,22 @@ describe("createTerminalMuxPool", () => {
 		keeper.dispose();
 	});
 
+	it("a lease forwards an older request and drops it once released", () => {
+		const pool = createTerminalMuxPool(() =>
+			createTerminalMux("ws://x/mux", FakeSocket as unknown as typeof WebSocket),
+		);
+		const lease = pool.acquire();
+		const keeper = pool.acquire();
+		const socket = FakeSocket.instances.at(-1)!;
+		socket.emitOpen();
+		lease.requestOlder("s-1", 512);
+		lease.dispose();
+		lease.requestOlder("s-1", 256);
+		const olders = socket.sent.map((frame) => JSON.parse(frame)).filter((frame) => frame.type === "older");
+		expect(olders).toEqual([{ ch: "terminal", type: "older", id: "s-1", before: 512 }]);
+		keeper.dispose();
+	});
+
 	it("a lease forwards blocks subscribe and stops after it is disposed", () => {
 		const pool = createTerminalMuxPool(() =>
 			createTerminalMux("ws://x/mux", FakeSocket as unknown as typeof WebSocket),
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t7-tests.patch
```

```bash
cd "$REPO/frontend" && npx vitest run src/renderer/lib/terminal-mux.test.ts src/renderer/hooks/useTerminalSession.test.tsx src/renderer/components/BlockTerminal.test.tsx 2>&1 | grep -E "Tests  |FAIL" | head
```
Expected: failures — `olderFrame` is not exported, `transport.requestOlder is not a function`, `mockState.host.loadOlderOutput` undefined.

- [ ] **Step 2: Implement**

Apply this patch (hunk headers carry the verified line numbers on `origin/development` @ `5185f35be`; the ` ` and `-` lines are the exact text to find if you ever have to apply a hunk by hand):

```bash
cat > /tmp/t7-impl.patch <<'PLAN7_PATCH'
diff --git a/frontend/src/renderer/components/BlockTerminal.tsx b/frontend/src/renderer/components/BlockTerminal.tsx
index 531478cca..fa5564883 100644
--- a/frontend/src/renderer/components/BlockTerminal.tsx
+++ b/frontend/src/renderer/components/BlockTerminal.tsx
@@ -38,6 +38,7 @@ export type BlockTerminalTransport = {
 	write: (data: Uint8Array) => void;
 	onData: (listener: (bytes: Uint8Array) => void) => () => void;
 	resize?: (cols: number, rows: number) => void;
+	requestOlder?: (before: number) => void;
 	dispose?: () => void;
 };
 
@@ -489,8 +490,11 @@ export function BlockTerminal({
 			secretPatterns,
 			...(predictiveThresholdMs === undefined ? {} : { predictiveEcho: { thresholdMs: predictiveThresholdMs } }),
 			confirmPaste,
+			...(transport.requestOlder
+				? { loadOlderOutput: (before: number) => transportRef.current.requestOlder?.(before) }
+				: {}),
 		}),
-		[clipboard, workspacePath, secretPatterns, predictiveThresholdMs, openFile, confirmPaste],
+		[clipboard, workspacePath, secretPatterns, predictiveThresholdMs, openFile, confirmPaste, transport.requestOlder],
 	);
 
 	const strings = useMemo<TerminalStrings>(
@@ -524,6 +528,7 @@ export function BlockTerminal({
 				defaultValue: "No matching commands",
 			}),
 			jumpToBottom: t("blocks.jumpToBottom", { defaultValue: "Jump to bottom" }),
+			loadOlderOutput: t("blocks.loadOlderOutput", { defaultValue: "Load older output" }),
 			shellBlocksUnavailable: t("blocks.shellBlocksUnavailable", {
 				defaultValue: "Shell blocks are unavailable in this terminal.",
 			}),
diff --git a/frontend/src/renderer/hooks/useTerminalSession.ts b/frontend/src/renderer/hooks/useTerminalSession.ts
index edd6e7b2f..417928be4 100644
--- a/frontend/src/renderer/hooks/useTerminalSession.ts
+++ b/frontend/src/renderer/hooks/useTerminalSession.ts
@@ -995,6 +995,11 @@ export function useTerminalSession(session: WorkspaceSession | undefined, option
 					r.byteListeners.delete(listener);
 				};
 			},
+			requestOlder: (before: number) => {
+				const r = runtime.current;
+				if (!r.mux || !r.handle || !r.inputReady || before <= 0) return;
+				r.mux.requestOlder(r.handle, before);
+			},
 			resize: (cols: number, rows: number) => {
 				const r = runtime.current;
 				if (cols <= 0 || rows <= 0) return;
diff --git a/frontend/src/renderer/lib/terminal-mux.ts b/frontend/src/renderer/lib/terminal-mux.ts
index c5a61fd9d..9cb8363f5 100644
--- a/frontend/src/renderer/lib/terminal-mux.ts
+++ b/frontend/src/renderer/lib/terminal-mux.ts
@@ -6,7 +6,7 @@
 // raw JSON string cannot represent.
 //
 //   ch "terminal" — per-pane byte stream keyed by an opaque runtime handle id
-//     client → open{id,cols,rows} | data{id,data} | resize{id,cols,rows,force?} | close{id}
+//     client → open{id,cols,rows} | data{id,data} | resize{id,cols,rows,force?} | close{id} | older{id,before}
 //     server → opened{id} | data{id,data} | exited{id} | error{id?,error} | health{id,health}
 //   ch "system"   — ping/pong liveness
 //   ch "blocks"   — normalized session block events
@@ -94,6 +94,10 @@ export function ackFrame(id: string, bytes: number): string {
 	return JSON.stringify({ ch: "terminal", type: "ack", id, bytes });
 }
 
+export function olderFrame(id: string, before: number): string {
+	return JSON.stringify({ ch: "terminal", type: "older", id, before });
+}
+
 export function blocksSubscribeFrame(sessionId: string): string {
 	return JSON.stringify({ ch: "blocks", type: "subscribe", id: sessionId });
 }
@@ -150,6 +154,7 @@ export type TerminalMux = {
 	resize: (id: string, cols: number, rows: number, force?: boolean) => void;
 	close: (id: string) => void;
 	ack: (id: string, bytes: number) => void;
+	requestOlder: (id: string, before: number) => void;
 	onData: (id: string, listener: DataListener) => () => void;
 	onExit: (id: string, listener: ExitListener) => () => void;
 	/** Server ack that the pane is attached; the output replay follows it. */
@@ -333,6 +338,9 @@ export function createTerminalMux(url: string, WebSocketImpl: typeof WebSocket =
 		ack: (id, bytes) => {
 			send(ackFrame(id, bytes));
 		},
+		requestOlder: (id, before) => {
+			send(olderFrame(id, before));
+		},
 		onData: (id, listener) => subscribeById(dataListeners, id, listener),
 		onExit: (id, listener) => subscribeById(exitListeners, id, listener),
 		onOpened: (id, listener) => subscribeById(openedListeners, id, listener),
@@ -461,6 +469,9 @@ export function createTerminalMuxPool(createMux: () => TerminalMux): TerminalMux
 			ack: (id, bytes) => {
 				if (!released && !connection.closed && !connection.disposed) connection.mux.ack(id, bytes);
 			},
+			requestOlder: (id, before) => {
+				if (!released && !connection.closed && !connection.disposed) connection.mux.requestOlder(id, before);
+			},
 			onData: (id, listener) => subscribe(() => connection.mux.onData(id, listener)),
 			onExit: (id, listener) => subscribe(() => connection.mux.onExit(id, listener)),
 			onOpened: (id, listener) => subscribe(() => connection.mux.onOpened(id, listener)),
PLAN7_PATCH
cd "$REPO" && git apply --recount /tmp/t7-impl.patch
```

- [ ] **Step 3: Run**

```bash
cd "$REPO/packages/terminal" && npm run build
cd "$REPO/frontend" && npx tsc --noEmit -p . && echo typecheck-ok
npx eslint src/renderer/lib/terminal-mux.ts src/renderer/lib/terminal-mux.test.ts src/renderer/hooks/useTerminalSession.ts src/renderer/hooks/useTerminalSession.test.tsx src/renderer/components/BlockTerminal.tsx src/renderer/components/BlockTerminal.test.tsx src/renderer/components/TerminalPane.test.tsx 2>&1 | tail -1
npx vitest run 2>&1 | grep -E "Test Files|Tests  "
```
Expected: `typecheck-ok`; eslint `✖ 17 problems (0 errors, 17 warnings)` — the same 17 warnings these files have on `5185f35be` (verified), none new; all vitest files passed (Task 0 count + 5 tests).

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add frontend/src/renderer/lib/terminal-mux.ts \
  frontend/src/renderer/lib/terminal-mux.test.ts \
  frontend/src/renderer/hooks/useTerminalSession.ts \
  frontend/src/renderer/hooks/useTerminalSession.test.tsx \
  frontend/src/renderer/components/BlockTerminal.tsx \
  frontend/src/renderer/components/BlockTerminal.test.tsx \
  frontend/src/renderer/components/TerminalPane.test.tsx
git commit -m "frontend: load older terminal output through the mux" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Measure memory, click cost and feed overhead

**Files:**
- Create: `backend/internal/adapters/runtime/ptyhost/vtwasm/older_report_test.go` (skipped unless `OPERATOR_OLDER_REPORT` is set), `docs/superpowers/specs/2026-09-25-old-output-measurement.md`
- Not committed: `$TMPDIR/renderer-click.mjs`

- [ ] **Step 1: The Go report test**

Create `backend/internal/adapters/runtime/ptyhost/vtwasm/older_report_test.go` with exactly this content:

```bash
mkdir -p "$REPO/backend/internal/adapters/runtime/ptyhost/vtwasm"
cat > "$REPO/backend/internal/adapters/runtime/ptyhost/vtwasm/older_report_test.go" <<'PLAN7_EOF'
package vtwasm

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"
)

const reportColdRingBytes = 32 << 20

func syntheticRows(from, to int) []byte {
	var b strings.Builder
	for i := from; i < to; i++ {
		if i%5 == 0 {
			fmt.Fprintf(&b, "\x1b[32mrow %06d\x1b[0m lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore\r\n", i)
		} else {
			fmt.Fprintf(&b, "row %06d lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore\r\n", i)
		}
	}
	return []byte(b.String())
}

func feedTimed(t *testing.T, p *Parser, payload []byte) time.Duration {
	t.Helper()
	start := time.Now()
	for offset := 0; offset < len(payload); offset += 64 << 10 {
		end := min(offset+64<<10, len(payload))
		if err := p.Feed(payload[offset:end]); err != nil {
			t.Fatalf("feed: %v", err)
		}
	}
	return time.Since(start)
}

func timeOneClick(t *testing.T, p *Parser, before uint64) (elapsed time.Duration, rows, bytes int) {
	t.Helper()
	start := time.Now()
	chunk, next, ok, err := p.OlderChunk(before, OlderChunkRows)
	if err != nil {
		t.Fatalf("older chunk: %v", err)
	}
	mark, err := p.OlderMark()
	if err != nil {
		t.Fatalf("older mark: %v", err)
	}
	elapsed = time.Since(start)
	if !ok {
		return elapsed, 0, 0
	}
	if out := os.Getenv("OPERATOR_OLDER_ANSWER_OUT"); out != "" {
		if _, statErr := os.Stat(out); statErr != nil {
			if err := os.WriteFile(out, []byte(chunk+mark), 0o600); err != nil {
				t.Fatalf("write answer: %v", err)
			}
		}
	}
	return elapsed, int(before - next), len(chunk)
}

func TestOlderOutputReport(t *testing.T) {
	if os.Getenv("OPERATOR_OLDER_REPORT") == "" {
		t.Skip("set OPERATOR_OLDER_REPORT=1 to measure the cold ring")
	}
	limits := productMirrorLimits
	limits.ColdRingBytes = reportColdRingBytes
	payload := syntheticRows(0, 520_000)

	withRing, err := New(context.Background(), Module, 120, 40, limits)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	defer withRing.Close()
	ringFeed := feedTimed(t, withRing, payload)

	withoutRing, err := New(context.Background(), Module, 120, 40, productMirrorLimits)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	defer withoutRing.Close()
	plainFeed := feedTimed(t, withoutRing, payload)

	cold, err := withRing.ColdStats()
	if err != nil {
		t.Fatalf("cold stats: %v", err)
	}
	stats, err := withRing.MemoryStats()
	if err != nil {
		t.Fatalf("memory stats: %v", err)
	}
	if cold.Bytes > reportColdRingBytes {
		t.Errorf("ring holds %d bytes past its %d cap", cold.Bytes, reportColdRingBytes)
	}
	if cold.FirstStableRow == 0 {
		t.Errorf("the ring never filled: %+v", cold)
	}
	front := cold.FirstStableRow + uint64(cold.Rows)
	clickRing, clickRows, clickBytes := timeOneClick(t, withRing, front)
	clickDeep, _, _ := timeOneClick(t, withRing, cold.FirstStableRow+OlderChunkRows)

	report := map[string]any{
		"feedMB":               float64(len(payload)) / (1 << 20),
		"feedMsWithRing":       ringFeed.Milliseconds(),
		"feedMsWithoutRing":    plainFeed.Milliseconds(),
		"wasmBytesWithRing":    withRing.module.Memory().Size(),
		"wasmBytesWithoutRing": withoutRing.module.Memory().Size(),
		"coreRows":             stats.Rows,
		"coreContentBytes":     stats.ContentBytes,
		"ringRows":             cold.Rows,
		"ringBytes":            cold.Bytes,
		"ringFirstStableRow":   cold.FirstStableRow,
		"clickRows":            clickRows,
		"clickBytes":           clickBytes,
		"clickMsNewestRing":    float64(clickRing.Microseconds()) / 1000,
		"clickMsOldestRing":    float64(clickDeep.Microseconds()) / 1000,
	}

	if fixture := os.Getenv("OPERATOR_AGENT_FIXTURE"); fixture != "" {
		recording, sizes := readAgentFixture(t, fixture)
		spill := Limits{Rows: 10_000, Bytes: 128 << 20, ColdRingBytes: reportColdRingBytes}
		p := feedAgentFixture(t, recording, sizes, spill)
		defer p.Close()
		fixtureCold, err := p.ColdStats()
		if err != nil {
			t.Fatalf("fixture cold stats: %v", err)
		}
		click, rows, bytes := timeOneClick(t, p, fixtureCold.FirstStableRow+uint64(fixtureCold.Rows))
		capped := feedAgentFixture(t, recording, sizes, limits)
		defer capped.Close()
		cappedStats, err := capped.MemoryStats()
		if err != nil {
			t.Fatalf("fixture memory stats: %v", err)
		}
		cappedCold, _ := capped.ColdStats()
		ahead, aheadRows, _ := timeOneClick(t, capped, cappedCold.FirstStableRow+uint64(cappedStats.Rows))
		report["fixtureRingRows"] = fixtureCold.Rows
		report["fixtureRingBytes"] = fixtureCold.Bytes
		report["fixtureClickRows"] = rows
		report["fixtureClickBytes"] = bytes
		report["fixtureClickMsRing"] = float64(click.Microseconds()) / 1000
		report["fixtureHistoryRows"] = cappedStats.Rows
		report["fixtureClickRowsFromHistory"] = aheadRows
		report["fixtureClickMsFromHistory"] = float64(ahead.Microseconds()) / 1000
	}
	encoded, _ := json.Marshal(report)
	t.Logf("OLDER-REPORT %s", encoded)
}
PLAN7_EOF
```

- [ ] **Step 2: Run it twice (on a full ring: 520,000 synthetic 110-character rows, every fifth coloured; and on `claude-long-50k`)**

```bash
cd "$REPO/backend/internal/adapters/runtime/ptyhost" && rm -f "$TMPDIR/older-answer.bin"
for run in 1 2; do OPERATOR_OLDER_REPORT=1 OPERATOR_OLDER_ANSWER_OUT="$TMPDIR/older-answer.bin" \
  OPERATOR_AGENT_FIXTURE="$REPO/packages/terminal/bench/agent-session/fixtures/claude-long-50k" \
  go test ./vtwasm/ -run TestOlderOutputReport -count=1 -v -timeout 20m 2>&1 | grep OLDER-REPORT; done
```
Expected shape (numbers from the machine this plan was proven on, for comparison, not as targets): `"ringBytes":33554386` (≤ 33,554,432 — the test fails otherwise), `"ringRows":266728`, `"ringFirstStableRow":53234`, `"coreRows":199999`, `"wasmBytesWithRing":77594624`, `"wasmBytesWithoutRing":35979264`, `"clickRows":2048`, `"clickBytes":245395`, `"clickMsNewestRing":0.567`, `"feedMsWithRing":3679`, `"feedMsWithoutRing":3706` (two runs gave +6 % and -1 %: inside noise), `"fixtureRingRows":50098`, `"fixtureRingBytes":1092308`, `"fixtureClickMsRing":0.506`, `"fixtureHistoryRows":60097`, `"fixtureClickMsFromHistory":0.993`.

- [ ] **Step 3: Renderer side of one click** (not committed)

```bash
cat > "$TMPDIR/renderer-click.mjs" <<'PLAN7_EOF'
import { readFile } from "node:fs/promises";
const root = process.argv[2];
const answerPath = process.argv[3];
const { createTerminalCore, initTerminalCore } = await import(`${root}/ts/core/dist/index.js`);
const wasm = await readFile(`${root}/ts/core/wasm/vt_core_bg.wasm`);
await initTerminalCore(wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength));
const core = createTerminalCore({ columns: 120, rows: 40, limits: { rows: 200_000, bytes: 128 * 1024 * 1024 } });
core.setGraphemeClusters(true);
const enc = new TextEncoder();
let batch = "";
for (let i = 0; i < 520_000; i += 1) {
	const tail = " lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore\r\n";
	batch += i % 5 === 0 ? `\x1b[32mrow ${String(i).padStart(6, "0")}\x1b[0m${tail}` : `row ${String(i).padStart(6, "0")}${tail}`;
	if (batch.length > 64 * 1024) { core.feed(enc.encode(batch)); batch = ""; }
}
core.feed(enc.encode(batch));
const f0 = performance.now();
core.snapshot();
const firstSnapshotMs = +(performance.now() - f0).toFixed(2);
const front = core.snapshot().firstStableRow;
const answer = await readFile(answerPath);
const t0 = performance.now();
core.feed(new Uint8Array(answer));
const t1 = performance.now();
const snap = core.snapshot();
const t2 = performance.now();
console.log(JSON.stringify({ firstSnapshotMs, front, after: snap.firstStableRow, historyRows: snap.historyRows, feedMs: +(t1 - t0).toFixed(2), snapshotMs: +(t2 - t1).toFixed(2), answerBytes: answer.length, older: core.olderOutput() }));
PLAN7_EOF
cd "$REPO/packages/terminal" && npm run build:ts && for run in 1 2; do node "$TMPDIR/renderer-click.mjs" "$PWD" "$TMPDIR/older-answer.bin"; done
```
Expected: `"after"` = `"front" - 2048` (the answer was accepted: on the proving machine `front` 319962, `after` 317914, `historyRows` 202047); `feedMs` tens of ms (20.8/32.2); `snapshotMs` ≈ `firstSnapshotMs` (885.7/948.4 vs 918.3/1051.1): the click's cost is one full re-export of the renderer's scrollback, not the chunk.

- [ ] **Step 4: Write the measurement note**

Create `docs/superpowers/specs/2026-09-25-old-output-measurement.md` with: date, machine (`uname -a`, CPU if known), branch and commit; the two command blocks above; a table of every field from both Go runs and both renderer runs, quoted; and these conclusions, rewritten with your numbers: (1) a full 32 MiB ring costs the mirror ≈ 1.2× its cap in wasm memory (with-ring minus without-ring, ÷ 33,554,432), never more than cap in payload (`ringBytes`); (2) the host side of a click is under a few ms; (3) the renderer side is one full re-export of the pane's scrollback per click — this is why a click is ONE 2,048-row chunk and not four 512-row chunks (each applied chunk forces a full export); (4) feed throughput with the ring on is within noise of off. If any expectation above is not met (the answer rejected, `ringBytes` over the cap, wasm with ring above 2× the cap over without), stop and report it instead of writing the conclusion.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add backend/internal/adapters/runtime/ptyhost/vtwasm/older_report_test.go \
  docs/superpowers/specs/2026-09-25-old-output-measurement.md
git commit -m "ptyhost: measure the cold ring's memory and a Load older output click" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Gates

**Files:** none (fixes found here go in a commit naming the files touched).

Run every command; paste each result into the report (Task 11). A gate that cannot run in this environment is `not run: <reason>`.

- [ ] **Step 1: Rust and both wasm builds**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1 && cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
git -C "$REPO" status --short backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
npm run build:wasm -- --force && npm run build:ts
```
Expected: no FAILED/panicked; the asset is unchanged from Task 2's commit (empty `git status` line). If it changed, a later task altered vt-core without rebuilding — commit the rebuilt asset (`git add backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`).

- [ ] **Step 2: TS suites and boundaries**

```bash
cd "$REPO/packages/terminal" && for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Test Files|Tests  "); done
npm run check:boundaries 2>&1 | tail -2
```

- [ ] **Step 3: Go**

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... ./internal/ports/... -count=1 2>&1 | tail -6
go vet ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... ./internal/ports/...
golangci-lint run ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... ./internal/ports/... 2>&1 | tail -1
```

- [ ] **Step 4: Frontend**

```bash
cd "$REPO/frontend" && npx tsc --noEmit -p . && npm run lint 2>&1 | tail -2 && npx vitest run 2>&1 | grep -E "Test Files|Tests  "
```
Expected: lint `0 errors` (warnings as on Task 0's tree).

- [ ] **Step 5: Playwright benches**

```bash
cd "$REPO/packages/terminal" && npm run bench:feel 2>&1 | tail -5
npm run bench:selection 2>&1 | tail -3
npm run bench:agent:gate 2>&1 | tail -5
npm run bench:agent:scroll 2>&1 | tail -5
npm run bench:affordances -- --action hover 2>&1 | tail -3; git -C "$REPO" checkout -- packages/terminal/bench/agent-session/baselines
```
Expected: `bench:feel` zero pixel diff against the Task 0 baseline (the button never renders in the harness: no host `loadOlderOutput`, no floor mark); the other three pass. After `git checkout` the baselines are back to the committed ones — re-run Task 0's `npm run bench:feel -- --record` only if you still need to compare again.

- [ ] **Step 6: Daemon binary**

```bash
cd "$REPO" && npm --prefix frontend run build:daemon 2>&1 | tail -2
```
Expected: builds `frontend/daemon/opr`. If the environment cannot build it: `not run: <reason>`.

---

### Task 10: Docs

**Files:** `packages/terminal/CHANGELOG.md`, `TERMINAL.md`, `docs/terminal/2026-09-19-terminal-reference-survey.md`, `docs/terminal/2026-09-24-not-done-plain-language.md`

Write the text below, replacing every number in `⟨…⟩` with the value you measured in Task 8 (quote the source file of each).

- [ ] **Step 1: CHANGELOG** — add as the first bullet under `## Unreleased` (`packages/terminal/CHANGELOG.md:3`):

```markdown
- vt-core/vt-host/core/renderer-dom/react: very old output (roadmap Plan 7, survey §5.8). A core given `set_cold_ring_bytes(cap)` keeps every row `trim_to` drops, serialised with the replay writer (now `vt_core::style_sgr`, moved from `vt-host`), in a byte-capped ring (payload + 8 bytes per row ≤ cap; oldest dropped; the cap is reserved once on the first spilled row). `older_chunk(before, max_rows, max_bytes)` answers with an ordinary history chunk ending at `before`, from the core's own history when `before` is newer than its front, else from the ring, carrying `cols=<n>` (its widest row); `older_mark()` is `OSC 7000;v=1;older=<floor>`. A receiving core sizes its history screen to `cols=`, marks a chunk wider than itself stale so the lazy rewrap re-lays it, records the floor (`older_state()`, TS `olderOutput()`), and now trims only on a feed that committed a live row, so loaded rows stay until the next one. `Content::trim_front_to` fixes a prepend into a core that had already trimmed, which left a gap before the first retained row (`RowsNotContiguous`). `mountLoadOlder` draws **Load older output** (`TerminalStrings.loadOlderOutput`) at the top of the scrollback when `HostCapabilities.loadOlderOutput` exists and the floor is below the pane's first row; `TerminalSurface` wires it. Operator's mirror keeps 32 MiB per terminal: ⟨wasm with a full ring⟩ vs ⟨without⟩; a click fetches ≤ 2,048 rows in ⟨host ms⟩ and costs the renderer one full re-export (⟨ms⟩ at 200k rows). Both wasm artifacts and the daemon must be rebuilt.
```

- [ ] **Step 2: TERMINAL.md**

(a) §1 pipeline (`TERMINAL.md:27-29`): after the `vtwasm/` lines add

```text
   │                     Rows the mirror trims past its cap go, as styled text, to a
   │                     32 MiB cold ring (mirror_limits.go); MsgOlderReq answers
   │                     "Load older output" from it on the asking connection (§4.33)
```

(b) §2 `Limits` bullet (`TERMINAL.md:180-191`): append one sentence: "The mirror also keeps a cold ring of trimmed rows (`Limits.ColdRingBytes`, 32 MiB in `mirrorLimits`); the renderer core has none (§4.33)."

(c) New section before `## 5. Known gaps` (`TERMINAL.md:941`):

```markdown
### 4.33 Output older than the row cap was dropped — roadmap Plan 7
- Symptom: past 200,000 rows (or 128 MiB) the oldest output was gone for good,
  in the pane and in the mirror (`Parser::trim_to` dropped it).
- Now: the pty-host mirror keeps trimmed rows as SGR text in a 32 MiB cold ring
  (`crates/vt-core/src/cold_ring.rs`, filled in `parser/history.rs` `trim_to`
  through `parser/cold.rs`). The mirror sends `OSC 7000;v=1;older=<floor>` after
  the attach history (or after the frame for a sized client without history) and
  at the end of every older answer. The pane shows **Load older output**
  (`ts/renderer-dom/src/load-older.ts`) when a floor below its first stable row is
  known and the host implements `HostCapabilities.loadOlderOutput`; a click sends
  mux `older{before}` → `MsgOlderReq` → one history chunk of ≤ 2,048 rows
  (`older_chunk`) plus the floor, in-band on that client's stream. The chunk
  carries `cols=` so a row wider than the pane lands whole and rewraps lazily.
  Loaded rows sit above the renderer's cap until the next live row trims them.
- Not persisted: the saved history (§4.29) is 4 MiB and 20 chunks; cold rows are
  older than anything it can hold.
- Measured (`docs/superpowers/specs/2026-09-25-old-output-measurement.md`): ⟨…⟩.
- Guards: `crates/vt-core/tests/cold_ring.rs`, `cold_ring.rs`/`content.rs` unit
  tests, marks `scanner.rs` older/cols tests, `vtwasm/older_test.go`,
  `ptyhost/older_test.go`, `terminal/manager_test.go` "Older", 
  `ts/core/src/older-output.test.ts`, `load-older.test.ts`,
  `dom-block-renderer.older.test.ts`, `TerminalSurface.older.test.tsx`,
  frontend `terminal-mux.test.ts`, `useTerminalSession.test.tsx`,
  `BlockTerminal.test.tsx` "load older output".
```

(d) §5 Known gaps — add these bullets after "Saved history is bounded" (`TERMINAL.md:1228-1233`):

```markdown
- **A Load older output click re-exports the whole scrollback once.**
  `apply_history_chunk` marks the export full (`parser/history.rs`), so a click
  at 200k rows costs ⟨ms⟩ of renderer time (the 2,048-row feed itself ⟨ms⟩).
  Every attach-history chunk pays the same. The fix is an incremental front
  prepend in `ExportBuffers` (`vt-wasm/src/export.rs`, 599 lines: split first).
- **Loaded rows do not survive new output.** The renderer keeps its cap; the next
  committed live row trims the loaded rows first and the button returns. A load
  whose answer arrives after live rows made the pane trim is rejected silently
  (the chunk no longer abuts) and the button returns.
- **The seam between loaded rows and the pane is exact only at one width.** Rows
  are addressed by stable row; pane and mirror count the same rows only when they
  ran at the same width and saw the same resizes. Otherwise a few rows can repeat
  or be skipped at the seam. Loaded rows carry no block marks and no `wrapped` flag.
- **A cold row larger than the 1 MiB answer buffer** (a very long row of heavily
  styled or linked text) cannot be loaded; the load stops at it.
```

- [ ] **Step 3: Survey** (`docs/terminal/2026-09-19-terminal-reference-survey.md`)

Line 118 (table row) becomes:
`| §5.8 | Done | Roadmap Plan 7 (2026-09-25) — the pty-host mirror keeps rows trimmed past the cap as SGR text in a 32 MiB cold ring; the pane's Load older output fetches ≤ 2,048 rows as a history chunk. Plan C — lazy rewrap for cold scrollback (`HOT_ROWS = 2_000`). Fixed segments were already ours (`Content` is chunked). |`
Line 3402 (status under the heading) becomes:
`> **Status: Done.** Roadmap Plan 7 (2026-09-25) — cold ring in the pty-host mirror (32 MiB, not persisted) and Load older output in the pane (`TERMINAL.md` §4.33). Plan C — lazy rewrap for cold scrollback.`
Then recount and fix the sentence at line 50:

```bash
cd "$REPO" && awk -F'|' '/^\| §/ {gsub(/ /,"",$3); print $3}' docs/terminal/2026-09-19-terminal-reference-survey.md | sort | uniq -c
```
On `5185f35be` it printed 39 Done, 1 N/A, 21 Notdone, 1 Notneeded, 7 Notpursued, 19 Partial; after this change expect Done +1 and Partial −1 relative to whatever your tree had (other plans may have moved it). Write the new counts into the "Every entry below carries a **Status** line…" sentence and add: `"Roadmap Plan 7" is the very-old-output plan (`docs/superpowers/plans/2026-09-25-terminal-plan-7-old-output.md`).`

- [ ] **Step 4: Plain-language doc** (`docs/terminal/2026-09-24-not-done-plain-language.md:138-139`) — replace the bullet with:

```markdown
- **Very old output (built 2026-09-25, roadmap Plan 7):** past 200,000 lines
  the oldest text is no longer lost: the helper keeps up to 32 MB of it per
  terminal, and scrolling to the top shows **Load older output**, which brings
  back about 2,000 earlier lines per click. Still missing: loaded lines leave
  again as soon as new output arrives, the old text is not kept across a crash
  or a restart of the helper, and each click briefly pauses a very long pane
  (§5.8).
```

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/CHANGELOG.md \
  TERMINAL.md \
  docs/terminal/2026-09-19-terminal-reference-survey.md \
  docs/terminal/2026-09-24-not-done-plain-language.md
git commit -m "docs: very old output — TERMINAL.md §4.33, changelog, survey §5.8, plain-language list" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 11: Push and report (do not merge)

- [ ] **Step 1: Clean up and check the branch**

```bash
cd "$REPO" && git checkout -- packages/terminal/bench/agent-session/baselines
git status --short
git log --oneline origin/development..HEAD
```
Expected: `git status` shows nothing tracked as modified (untracked build output under gitignored paths only); 8 commits (Tasks 1-8 and 10, plus any Task 9 fix).

- [ ] **Step 2: Push**

```bash
cd "$REPO" && git push -u origin terminal/plan-7-old-output
```
Do not open a PR unless asked, do not merge.

- [ ] **Step 3: Completion report** (your final message) containing:
1. Every gate from Tasks 1-9 with its quoted last lines, or `not run: <reason>`.
2. The Task 8 numbers (both Go runs, both renderer runs) and the path of the measurement note.
3. Any hunk you had to apply by hand, and why.
4. The shared-file list from this plan's header, and the reminder: after merging with Plan 3, rebuild `vt_host.wasm` from the merged tree and re-run `go test ./internal/adapters/runtime/ptyhost/...`; keep `vt-core/src/lib.rs` ≤ 600 lines.
5. **Real-app checklist** for the reviewer (cannot be done in a cloud session: `not run: no desktop app`):
   - rebuild both wasm artifacts and the daemon (`TERMINAL.md` §6), restart the daemon and the app;
   - open a shell pane, run `seq 1 400000`, wait for the prompt;
   - scroll to the top: the first row is about `200001`, and **Load older output** is at the top;
   - click it: the view does not jump; scroll up: rows ending just below the previous first row (about `198000`…`200000`) are there; the button is at the top again;
   - click until the button disappears (the ring holds far more than 400,000 short rows, so it stops at `1`);
   - type `echo hi` and Enter: the loaded rows are trimmed; scroll to the top: the button is back;
   - optional: narrow the window before `seq`, widen it after, and check a loaded long line is whole.
