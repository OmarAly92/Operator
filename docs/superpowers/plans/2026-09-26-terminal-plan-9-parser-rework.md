# Terminal Plan 9 — Parser Rework: Typed Dispatch, Fast Path, Row Flags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **If the superpowers skills are not installed in your environment, run the process by hand:** one fresh implementer subagent per task (give it the task text, Global Constraints, Review Focus and Design decisions), then one spec-compliance review subagent and one code-quality review subagent per task, fix what they find, and after the last task one whole-branch review subagent over `git diff origin/development...HEAD`. **If there is no subagent tool either, say so in your report, implement task by task yourself, and after each task review its diff against the task text before moving on.**

**Goal:** Make `vt-core` parse faster without changing one observable byte of behaviour: decide (with evidence) whether dispatch can move to `vte::ansi::Handler`, add a printable-run fast path and a bounded ring of unknown sequences, and make erase/insert on a row cheap — each part kept only if a before/after measurement shows it is faster beyond noise.

**Architecture:** A differential safety net comes first: `tests/parser_goldens.rs` replays every recording (46 Alacritty-derived `tests/ref` dirs, the 3 Claude Code fixtures, 4 deterministic synthetic streams) through 4 core configurations and compares a digest of everything observable (rows, styles, cell spans, wrapped flags, blocks, links, cursor, alt screen, modes, title, notifications, agent events, query replies, every per-feed `Delta`) against golden files generated on the **unmodified** tree. Part A is decided by a scratch spike outside the repository: `vte::ansi::Processor` cannot express seven things vt-core relies on and forces three behaviour changes, so dispatch stays on `vte::Perform` (docs only). Part B buffers printable ASCII between control sequences and writes it a row segment at a time, skips the grapheme join for ASCII after ASCII, removes the join's per-character allocation, and records unhandled CSI/ESC/DCS/OSC in a 64-entry ring. Part C replaces cell-by-cell erase/insert/delete with slice fills and rotations; row flags are built as a patch, measured, and (expected) discarded.

**Tech Stack:** Rust 1.96.0 (`vt-core`, `vt-wasm`, `vt-host`; `vte =0.15.0`, `default-features = false`), wasm32 + wasm-bindgen 0.2.127, Node (for the wasm throughput cross-check), Go 1.25 (pty-host tests only), TypeScript 5.9 + vitest 4.1.8 (unchanged suites), Playwright (benches).

**Spec:** `docs/terminal/2026-09-24-terminal-roadmap-design.md` "Plan 9 — Parser rework: typed dispatch, fast path, row flags (§2.2, §1.11, §1.12)" and "Rules every plan obeys"; survey `docs/terminal/2026-09-19-terminal-reference-survey.md` §2.2, §1.11, §1.12, §2.14; `TERMINAL.md` end to end (every §4 entry is a regression guard; §4.16, §4.22, §4.30, §4.33, §4.34 are the parser-adjacent ones; §6 is the ship recipe).

**Tree this plan was written and proven against:** `origin/development` @ `585c0e68d` ("fix(terminal): one throwing program-message listener no longer drops the rest"). Every code block below was built and tested in scratch worktrees of that commit on 2026-09-25/26 (macOS arm64, Rust 1.96.0): each task's end state `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` and `cargo test` green; the goldens generated on the unmodified tree pass unchanged after every task; renderer wasm + `ts/core` 179, `renderer-dom` 985, `react` 134, `editor` 175, `completions` 109 tests; `check:boundaries` pass; pty-host Go tests `ok` with the rebuilt `vt_host.wasm`; `bench:feel` zero pixel diff against a baseline recorded on the unmodified tree; `bench:agent:gate` PASS; `bench:agent:scroll` full coverage (60,134 of 60,134); `bench:selection` PASS (macOS).

## Global Constraints

- Branch `terminal/plan-9-parser-rework` from `origin/development`. Never commit to `development` or `master`, never merge, never force-push.
- Commits name explicit paths only: `git add <path> …`. Never `git add -A`, `git add .`, `git commit -a` or `git stash`.
- Every commit message ends with the trailer line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- No comments in new code (Rust, JS, tests). Moving an existing comment with its code (Task 3) is not new code.
- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no Operator name, path or concept under `crates/`, `ts/`, `bench/` code or test data. That is why the goldens use the terminal identity `GoldenTerm`, not `Operator`.
- Licences: Alacritty/`vte` (Apache-2.0/MIT) and Ghostty (MIT) are read for **behaviour only** in this plan — no code is adapted, so no attribution file is added. Kitty (GPL-3.0) and Warp (AGPL-3.0) are not read at all.
- **Three separable parts.** Part A = Task 2, Part B = Tasks 3–6, Part C = Tasks 7–9. Each part ends with Gate set G green and its own commits. **If a later part hits a blocker (a gate that fails and cannot be fixed inside the part, a quoted edit text that is not found, a measurement that rejects the part), stop that part, leave its commits out (or revert them with `git revert`), and report; earlier parts stand.**
- **Behaviour must not change.** `tests/parser_goldens.rs` and its `tests/goldens/*.golden` files are generated **once**, in Task 1, on the unmodified tree, and are never regenerated on this branch. If a golden fails after a change, the change is wrong — fix the code, never the golden. Every existing test (`tests/ref` screens and styles, the integrity proptest, every file under `crates/vt-core/tests`) must pass unmodified.
- No file under `packages/terminal` may exceed 600 lines (`npm run check:boundaries`). Planned sizes: `crates/vt-core/src/screen.rs` 547 → 444 (Task 3) → 448, `src/screen/print.rs` new 109 → 173, `src/parser.rs` 543 → 549, `src/parser/perform.rs` 108 → 135, `src/parser/unknown.rs` new 143, `src/lib.rs` 590 → 593, `src/screen/edit.rs` 154 → 155, `crates/vt-wasm/src/program.rs` 46 → 54.
- A `vt-core` change is not live until **both** wasm artifacts are rebuilt (`TERMINAL.md` §6): the renderer's (`npm run build:wasm -- --force`, gitignored) and the host mirror's (`cargo build --release -p vt-host --target wasm32-unknown-unknown`, copied to `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`, **committed** at the end of each code part), then the pty-host Go tests.
- This plan changes no pixels. `bench:feel` must stay at zero diff against the Task 0 baseline recorded in **this** environment (committed baselines were recorded on the owner's Mac and do not reproduce on Linux). Never commit re-recorded baselines (`packages/terminal/bench/agent-session/baselines/**`); `bench:feel -- --record` and `bench:affordances` rewrite committed PNGs — restore with `git checkout -- packages/terminal/bench/agent-session/baselines && git clean -fdq packages/terminal/bench/agent-session/baselines`.
- New `TERMINAL.md` section number: **§4.35**.
- Docs and the report cite `file:line` or write "not known". Every number written into a doc is one you measured on this branch, quoted with where it came from; the planning numbers in this plan are for comparison only.
- Tool gaps are reported, not hidden: when a command cannot run, write `not run: <reason>` in the report. `bench:selection` sends Meta+C, which Linux Chromium does not treat as copy: on Linux record `not run: Linux copy chord`, not a failure.
- Cloud environment notes (from earlier waves): Playwright's CDN may answer 403 — symlink the pinned revision directory names under `/opt/pw-browsers` to the preinstalled Chromium (Task 0 Step 2). Go: `export GOTOOLCHAIN=auto`; for `build:daemon` put the downloaded `go1.25.7` (or newer) first on `PATH`. No reference repositories are available; if you want to read one, clone it outside the repository at the commit the survey cites: `git clone https://github.com/ghostty-org/ghostty && git -C ghostty checkout b32f20f3e` (Ghostty, 2026-09-18), `git clone https://github.com/alacritty/alacritty && git -C alacritty checkout d692748d` (Alacritty, 2026-08-31), `git clone --branch v0.15.0 --depth 1 https://github.com/alacritty/vte` (the `vte` that `Cargo.lock` pins). You do not need to: every fact used is quoted below with its `file:line`, and the exact vte 0.15.0 sources are in `~/.cargo/registry/src/*/vte-0.15.0/` after the first `cargo build`.

## Review Focus

1. **A printable run right before a mark or an alternate-screen switch.** `feed_raw` applies mark events (OSC 133/7000, `?1049h/l`) between `advance_vte` calls (`crates/vt-core/src/lib.rs:245-323`); Part B buffers printable bytes inside the parser, so a run that is still buffered when an event applies would land after it (in the wrong block, or on the alternate screen). Expected: the run lands first, exactly as before. Pinned by `print_run.rs` `a_run_right_before_a_boundary_mark_lands_in_the_block_the_mark_closes`, `a_run_right_before_the_alternate_screen_opens_stays_on_the_primary_screen`, every golden with an alternate screen (`alt_reset`, `saved_cursor`, `saved_cursor_alt`, `tmux_git_log`, `tmux_htop`, `vim_*`, `wrapline_alt_toggle`) or marks (`synthetic-malformed`: OSC 133 A/B/C/D) in the byte-by-byte `renderer-odd`/`agent-odd` configurations.
2. **Grapheme joins at the edge of the fast path.** An ASCII letter can extend a cluster only when the previous cluster ends in a `Prepend` scalar (UAX #29 GB9b, e.g. U+0600); ASCII after an ASCII cell never can. Expected: `\u{600}a` stays one 2-cell cluster and `b` starts a new one, identical to the unmodified tree. Pinned by `print_run.rs` `an_ascii_letter_after_a_prepend_mark_joins_it_and_the_next_letter_does_not`, the 512-case proptest `an_ascii_run_lands_exactly_where_printing_it_one_char_at_a_time_does` (wide, combining, ZWJ, flags, Hangul, VS16, DEL, `U+0600` mixed with ASCII, at 1–11 columns, both width modes, any start column), and `synthetic-unicode-mix`.
3. **Sequences split anywhere across PTY reads and malformed or oversized sequences.** Expected: the same screen, styles, replies and events as a whole feed; an oversized OSC is cut by vte's 1,024-byte buffer as before; a 40-parameter CSI is truncated as before. Pinned by the `renderer-odd` and `agent-odd` golden configurations (feeds of 1, 3, 7, 64, 509, 4,093 bytes in turn), `synthetic-malformed` (3,000-byte title and URI, 40 params, 3 intermediates, `CSI > 4;2 m`, unterminated OSC, DCS/APC/SOS/PM, CAN/SUB mid-CSI, huge numbers, unterminated DEC 2026 block), `print_run.rs` `a_run_split_at_every_byte_matches_the_run_fed_whole` and `invalid_utf8_inside_a_run_prints_a_replacement_character`, `unknown_sequences.rs` `a_sequence_split_byte_by_byte_is_recorded_once` and `an_oversized_sequence_is_cut_and_marked_as_overflowing`.
4. **The unknown-sequence ring must never keep a secret or grow.** OSC 52 carries clipboard contents; a hostile program can send millions of distinct sequences. Expected: an OSC is recorded by its number only, text is capped at 48 bytes, the ring at 64 entries (oldest dropped, a repeat moves to the newest end with its count). Pinned by `unknown_sequences.rs` `escape_dcs_and_other_osc_sequences_are_recorded_without_their_payload`, `the_ring_keeps_the_newest_distinct_sequences_up_to_its_cap`.
5. **Erase/insert on a row with the erase background, a wide character or a combined cell.** Expected: identical cells, styles, `wrapped` flag (cleared only when the edit reaches the last column, as `ScreenGrid::set` does today, `crates/vt-core/src/screen.rs:292-294`) and dirty rows. Pinned by `bulk_edits.rs` (all six tests pass on the unmodified tree too) and `synthetic-edits-styled` (20,000 random edits with styles, links, wide and combined text at 40×12).

---

## Design decisions (each one decided; evidence in brackets)

### Part A — `vte::ansi::Handler` is measured and **not adopted**

Evidence, gathered with a scratch crate outside the repository (Task 2 reproduces it; source lines are `vte-0.15.0/src/ansi.rs` unless noted):

- **The `ansi` module needs a feature, not `std`.** `vte-0.15.0/Cargo.toml` `[features]`: `ansi = ["log", "cursor-icon", "bitflags"]`, `std = ["memchr/std"]`. A crate with `vte = { version = "=0.15.0", default-features = false, features = ["ansi"] }` builds for the host and for `wasm32-unknown-unknown` [spike]. The survey's §2.2 proposal ("`std` is required by `ansi`") is false. vt-core must stay `no-std` for vte: §4.34's 1,024-byte OSC limit (`vte-0.15.0/src/lib.rs:46` `MAX_OSC_RAW`) is the no-std `ArrayVec` buffer, which `std` would replace with an unbounded `Vec` (`lib.rs:61-64`).
- **Seven things vt-core relies on reach no `Handler` method** (the `Processor` owns its `vte::Parser` and its `Performer` is private, `ansi.rs:425`, so an unhandled sequence cannot be passed on to a second dispatcher — there is no partial adoption):
  1. `CSI > 0 q` XTVERSION — only `('q', [b' '])` DECSCUSR exists (`:1711`); Claude Code's DEC 2026 probe depends on the answer (`TERMINAL.md` §4.16).
  2. `CSI 16 t` — the `('t', [])` arm handles 14, 18, 22, 23 only (`:1739-1745`); Claude Code sends 16 (§4.30).
  3. OSC 9, 99, 777 (`notify` and `agent-state`), 1, 133, 7000 — `osc_dispatch` (`:1329-1525`) handles 0/2, 4, 8, 10–12, 22, 50, 52, 104, 110–112; everything else goes to `unhandled`, which only logs (`:1523`). Notifications (§4.30) and agent events (§4.34) would be lost.
  4. `OSC 8 ;` with no URI part — `b"8" if params.len() > 2` (`:1393`) ignores it; vt-core closes the link (`hyperlink.rs:54-60` returns `None`, `perform.rs:99-102` sets `link = 0`).
  5. SGR 53/55 overline — no arm in `attrs_from_sgr_parameters` (`:1831-1918`), so the attribute Plan D exports is dropped.
  6. Raw parameters — the `trace` feature records every CSI's params (`trace.rs:6-19`) and Part B's unknown ring needs the raw sequence; `Handler` receives decoded values only.
  7. DECRQM for several modes — `('p', [b'?', b'$'])` passes only the first mode (`:1707-1710`); vt-core answers every mode (`parser.rs:411-422`).
- **Three behaviour changes would be forced:** SGR 21 becomes `CancelBold` (`:1849`) instead of double underline (`sgr.rs:57`); `38;5;300` is rejected (`u8::try_from`, `:1930-1938`) instead of clamped to 255 (`parser/colour.rs:64-66`); `4:6` becomes `Underline` (`[4, ..]`, `:1843`) instead of no underline (`sgr.rs:49`). And three new behaviours arrive uninvited: `CSI b` REP is executed by the `Performer` itself through `handler.input` (`:1562-1570`), which changes `tests/ref/csi_rep`'s screen; `ESC Z` becomes `identify_terminal(None)` (`:1808`), a new DA1 answer; `ESC # 8` becomes `decaln` (`:1814`), which changes `tests/ref/decaln_reset`. Each breaks the rule "`tests/ref` unchanged".
- **Memory:** `Processor::new()` allocates its DEC 2026 buffer eagerly: `SyncState::default` is `Vec::with_capacity(SYNC_BUFFER_SIZE)` (`:261-264`), `SYNC_BUFFER_SIZE = 0x20_0000` (`:39`) — 2,097,152 bytes per core [spike, counting allocator], paid by every renderer pane and every pty-host mirror, on top of vt-core's own `SyncBuffer` (§4.16), which must stay because it is driven by the feed clock (`now_ms`), survives resizes and interleaves with mark events; `Processor`'s is driven by a `Timeout` trait with no clock input.
- **Decision:** keep `impl vte::Perform for Parser`. Part A changes no code; it records the evidence (`TERMINAL.md` §4.35, survey §2.2 → **Not pursued**, plain-language item 18). Net effect of adopting would be more code (a `Handler` impl plus a second raw `Perform` for OSC/XTVERSION/XTWINOPS/DECRQM/trace, over two parsers) and lost behaviour — a net loss, per the brief's own criterion.

### Part B — printable runs and the unknown-sequence ring

- **Where the per-character cost was** (planning profile, `sample` on the release example): in grapheme mode (the renderer's default, `TERMINAL.md` §2 "Width mode") every printed character went through `ScreenGrid::join_previous`, which copied the previous cell's text into a new `String` (`screen.rs:472` `.to_string()`) and then built a second `String` to segment (`width.rs:51-54`) — two allocations per character. Everything else (`set` with a ring-modulo per cell, `mark_dirty`, `raise_max_cursor_row`, `UnicodeWidthChar::width`) is per character in both modes.
- **Three changes, all behaviour-preserving:**
  1. `joins_previous` builds the joined text in a 64-byte stack buffer (heap only past 64 bytes) and `join_previous` passes the cell's text by reference (no `.to_string()`).
  2. `ScreenGrid::print` takes a fast path for a printable ASCII character (`' '..='~'`) when no wrap is pending and the previous cell is plain ASCII (or there is none, or the mode is scalar): write the cell, advance, mark dirty — exactly what the slow path does for such a character, minus the width lookup and the join check. Why it is exact: an ASCII scalar is never `Extend`, `ZWJ`, `SpacingMark`, `Extended_Pictographic`, `Regional_Indicator`, Hangul or `InCB` Consonant, and never `Prepend`, so by UAX #29 it joins the previous cluster only after a `Prepend` scalar (GB9b); a plain ASCII previous cell ends in ASCII, so it never joins — the same answer `joins_previous` gives (`width.rs:48`: both ASCII → `false`).
  3. The parser buffers printable ASCII (`Parser.run: Vec<u8>`) and flushes it before every other callback (`execute`, `csi_dispatch`, `esc_dispatch`, `osc_dispatch`) and at the end of every `advance_vte` (`lib.rs`), so nothing else ever observes the screen with bytes pending — marks, alternate-screen switches, sync flushes and snapshots all happen between `advance_vte` calls. `ScreenGrid::print_ascii_run` prints the first byte through `print` (which handles the `Prepend` case and a pending wrap) and writes the rest a row segment at a time: one ring lookup, one slice write, one dirty mark per segment. Non-ASCII characters still go one by one through `print`. The `trace` feature still records one `Print` per character.
- **Why not Ghostty's shape** (`src/terminal/stream.zig:599-720`, a SIMD UTF-8 decode of the whole printable run before dispatch): vte owns the byte loop and calls `print(char)` per character (`vte-0.15.0/src/lib.rs:722-729` `ground_dispatch`); decoding ahead of vte would need vte's ground state, which it does not expose (the same reason `AnswerGate` exists, §4.33). Buffering the callbacks gets the batching without touching vte.
- **The ring** (`crates/vt-core/src/parser/unknown.rs`): 64 entries (`UNKNOWN_SEQUENCES_CAP`), each `{ text, count }`, text capped at 48 bytes (`UNKNOWN_TEXT_BYTES`); a repeat increments its count and moves to the newest end; a new entry past the cap drops the oldest. Recorded: a CSI no dispatcher handled (`ScreenGrid::csi` and `Parser::xtwinops` now return whether they handled it), a DEC private mode set/reset naming a mode outside `{1, 25, 1000, 1002, 1003, 1004, 1006, 1049, 2004, 2026, 2048}`, an ESC other than `7 8 D E M c \` without intermediates, any DCS (vt-core handles none), and an OSC whose number is not handled by vt-core or by the marks decoder (`7`, `133`, `7000`) — as `OSC <number>` only, never its payload (OSC 52 carries clipboard data). A CSI that vte truncated (`ignore`) is recorded with an `overflow ` prefix even when it was dispatched. Text uses vte's view: an omitted parameter reads `0` (`CSI ?0u`). SOS/PM/APC strings reach no callback in vte and cannot be recorded. Exposed for debugging only: `TerminalCore::unknown_sequences()` / `clear_unknown_sequences()` and `WasmTerminalCore.unknown_sequences()` (`"<count> <text>"` strings); nothing in `ts/` or Operator reads it. On the three Claude Code recordings it holds exactly `CSI <0u`, `CSI >4;2m`, `CSI >4m`, `CSI >5u`, `CSI ?0u`, `CSI ?2031h`, `CSI ?2031l`, `ESC (B` [test `the_claude_code_recordings_leave_eight_unhandled_sequences`].
- **File split first:** `screen.rs` is 547 lines; the fast path adds ~65. Task 3 moves the print path (`print`, `previous_cell`, `cell_width_at`, `join_previous`, `attach_zerowidth`, `screen.rs:417-517`) verbatim into `src/screen/print.rs`.

### Part C — bulk erase/insert, and row flags measured

- `ScreenGrid::erase_in_display` (modes 0/1 on the cursor row), `erase_in_line` (modes 0/1), `insert_chars`, `delete_chars` and `erase_chars` (`screen/edit.rs:4-115`) write one cell at a time through `set` and, for insert/delete, clone each moved cell. Two private helpers replace the loops: `fill_cells(row, from, to)` (one slice `fill` with the erase cell; clear `wrapped` iff `to == cols`, as the per-cell `set` did at the last column; one dirty mark, none for an empty span) and `shift_cells(row, from, to, by)` (`rotate_right`/`rotate_left` of the row slice — no clones; clear `wrapped`; mark dirty). Claude Code never sends ICH/DCH/ECH (`claude-long-50k`: 0 `@`, 0 `P`, 0 `X`; 32,808 `K`), so the gain is for shells and full-screen programs.
- **Row flags** (Ghostty `src/terminal/page.zig:2020-2058`, behaviour only): a per-row `row_flags: Vec<u8>` with `ROW_STYLED` and `ROW_GRAPHEME`, false positives allowed, never false negatives, and a plain-row fast path in `scrollback::commit_row` (the eviction path, which the planning profile showed is the largest remaining cost when output scrolls) that skips per-cell style and text work. `hyperlink` needs no flag (the link id rides in `CellStyle.link`, so `ROW_STYLED` covers it); `wrapped` stays its own vector (merging it buys nothing measurable). Built as a patch in Task 8, measured, and kept only if faster beyond noise. **Planning measurement: no gain** (claude-long-50k scalar 79.42–80.04 → 78.05–78.25 MB/s, grapheme 48.03–48.57 → 47.74–47.94; ascii-heavy −1–2 %; edit-heavy equal) — expected outcome: discarded, documented. The prototype also found a real bug on its way (a chunk longer than `CHUNK_SIZE` after a history prepend underflowed `CHUNK_SIZE - len`; caught by `older_seams.rs`), fixed in the patch with `saturating_sub`.

### Measurement method (Parts B and C)

- **Workloads** (`crates/vt-core/examples/parse_throughput.rs`, release build, 120×40, `Limits::DEFAULT`, 64 KiB feeds, median of 7 runs per line): `claude-long-50k` (7,915,950 bytes), `ascii-heavy` (16 MiB synthetic, lines of 0–159 printable ASCII with an SGR every ~40 characters), `edit-heavy` (16 MiB synthetic Ink-style redraws: 20 rows of `CR EL2 text CHA 30 <one of DCH/ICH/ECH/EL1/EL0/EL2> CUD`, then two newlines), each in grapheme mode (renderer) and scalar mode (mirror). **Cross-check in the shipped runtime:** `bench/parse-throughput.mjs` loads the renderer wasm (`ts/core/wasm`) into Node's V8 and feeds `claude-long-50k` the same way — this is the code that runs in the pane; a Chrome performance trace would attribute the same time to the same `feed` call, so the Node run is the trace-equivalent for a parse-only change.
- **A/B:** 3 pairs, alternated (control first, candidate first, control first), each run printing one median per line. Control = the Task 1 commit built in a separate worktree (`$HOME/plan9-control`); candidate = the branch.
- **Verdict per workload line** (6 lines native + 2 wasm): *faster beyond noise* = the candidate's lowest of 3 medians is above the control's highest; *slower beyond noise* = the candidate's highest is below the control's lowest **and** by more than 3 % of the control's middle median. `ab-verdict.mjs` (Task 1 Step 6, kept outside the repository) prints these.
- **Keep rules:** Part B is kept if `claude-long-50k grapheme` (native) and `wasm claude-long-50k grapheme` are both faster beyond noise and no line is slower beyond noise. Part C's bulk edits are kept if `edit-heavy grapheme` and `edit-heavy scalar` are both faster beyond noise and no line is slower beyond noise. Row flags are kept only if a `claude-long-50k` line (native, either mode) is faster beyond noise and no line is slower beyond noise.
- **Planning numbers (macOS arm64, 2026-09-25/26; yours will differ, record yours):**

  | line | control (Task 1) | Part B | Part B + bulk edits |
  |---|---|---|---|
  | claude-long-50k grapheme | 29.51–30.42 | 46.43–46.89 | 43.09–44.75 vs B 42.00–46.01 (noisy session) |
  | claude-long-50k scalar | 73.07–74.05 | 74.50–75.60 | 70.03–73.13 vs B 68.10–73.61 |
  | ascii-heavy grapheme | 22.85–23.35 | 54.54–56.14 | 48.94–50.16 vs B 47.81–53.61 |
  | ascii-heavy scalar | 47.84–48.01 | 54.12–55.99 | 49.05–51.32 vs B 49.58–53.86 |
  | edit-heavy grapheme | 29.86–30.03 | 75.65–77.32 | 82.58–83.04 vs B 72.41–74.40 |
  | edit-heavy scalar | 62.27–62.92 | 76.20–77.29 | 82.85–82.87 vs B 71.97–74.63 |
  | wasm claude-long-50k grapheme | 28.15–28.39 | 33.09–33.42 | 31.52–31.86 vs B 30.75–31.54 |
  | wasm claude-long-50k scalar | 50.92–51.13 | 52.39–53.05 | 50.63–51.27 vs B 48.60–51.81 |

  (MB/s, ranges are the three medians of each side.) Part B: every line faster beyond noise. Bulk edits: `edit-heavy` +11–12 % beyond noise, every other line inside noise.

## File map

| File | Task | Responsibility |
|---|---|---|
| `packages/terminal/crates/vt-core/tests/parser_goldens.rs`, `tests/golden_support/{mod.rs,synthetic.rs}` (new) | 1 | the differential harness: replay, digest, synthetic streams |
| `packages/terminal/crates/vt-core/tests/goldens/*.golden` (new, 53 files, generated) | 1 | the unmodified tree's digests |
| `packages/terminal/crates/vt-core/examples/parse_throughput.rs`, `packages/terminal/bench/parse-throughput.mjs` (new) | 1 | native and wasm throughput |
| `TERMINAL.md`, survey, plain-language doc | 2, 6, 9 | §4.35 and status lines, one part at a time |
| `packages/terminal/crates/vt-core/src/screen.rs`, `src/screen/print.rs` (new) | 3, 4 | print path moved, then the fast path |
| `packages/terminal/crates/vt-core/src/{width.rs,parser.rs,lib.rs,parser/perform.rs}`, `tests/print_run.rs` (new) | 4 | run buffer, allocation-free join |
| `packages/terminal/crates/vt-core/src/parser/unknown.rs` (new), `parser/{perform.rs,program.rs}`, `screen/dispatch.rs`, `parser.rs`, `lib.rs`, `tests/unknown_sequences.rs` (new); `crates/vt-wasm/src/program.rs`, `tests/program_exports.rs` | 5 | the ring |
| `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`, `packages/terminal/CHANGELOG.md` | 6, 9 | rebuilt mirror, changelog |
| `packages/terminal/crates/vt-core/src/screen/edit.rs`, `tests/bulk_edits.rs` (new) | 7 | bulk erase/insert |
| (patch applied and discarded unless kept) `src/{content.rs,parser.rs,screen.rs,scrollback.rs,screen/{edit,print,resize}.rs}` | 8 | row flags experiment |

---

## Gate set G (run at the end of every part; each command, then what it must print)

- [ ] **G1 Rust**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
cargo test -p vt-core --features trace --test integrity 2>&1 | grep "test result"
cargo test --release -p vt-core --test parser_goldens 2>&1 | grep "test result"
```
Expected: `Finished …` from clippy; only `rust-done` (no FAILED/panicked line); `test result: ok. 8 passed` (the `trace` build); `test result: ok. 1 passed` (goldens, release — the debug run is inside `cargo test`).

- [ ] **G2 Both wasm builds**

```bash
cd "$REPO/packages/terminal" && cargo build --release -p vt-host --target wasm32-unknown-unknown
cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
npm run build:wasm -- --force 2>&1 | tail -1 && npm run build:ts 2>&1 | tail -1
git -C "$REPO" status --short backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
```
Expected: `build-wasm: vt_core.js, vt_core.d.ts, vt_core_bg.wasm, vt_core_bg.wasm.d.ts ready`. The status line shows ` M …vt_host.wasm` after a part that changed vt-core — commit it in that part. After a part that changed no Rust source (Part A, or a Part C whose code was all discarded) the rebuilt bytes can still differ from the committed asset (the release wasm embeds dependency source paths from the build machine): run G4 with it, then restore it with `git -C "$REPO" checkout -- backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` and do not commit it.

- [ ] **G3 TS suites, boundaries, node tests**

```bash
cd "$REPO/packages/terminal" && for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  "); done
npm run check:boundaries 2>&1 | tail -2
node --test ./scripts/browser-types.test.mjs ./scripts/spawn-recipe-package.test.mjs ./bench/agent-session/fixtures.test.mjs ./bench/agent-session/session-api.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"
```
Expected: the same five `Tests  N passed (N)` counts as Task 0 (planning: 179, 985, 134, 175, 109); `boundary check passed`; `ℹ pass 7`, `ℹ fail 0`.

- [ ] **G4 Go**

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -3
go vet ./internal/adapters/runtime/ptyhost/...
```
Expected: three `ok` lines; no vet output. `TestProcessEnvironmentLetsOverridesWin` is a known pre-existing failure (`TERMINAL.md` §5); if it fails in Task 0 too, it is not yours.

- [ ] **G5 Frontend type check**

```bash
cd "$REPO/frontend" && npx tsc --noEmit -p . && echo frontend-tsc-ok
```

- [ ] **G6 Playwright benches**

```bash
cd "$REPO/packages/terminal" && cp -R "$HOME/plan9-feel-baseline/." bench/agent-session/baselines/ && npm run bench:feel 2>&1 | tail -2
git -C "$REPO" checkout -- packages/terminal/bench/agent-session/baselines && git -C "$REPO" clean -fdq packages/terminal/bench/agent-session/baselines
npm run bench:agent:gate 2>&1 | tail -1
npm run bench:agent:scroll 2>&1 | tail -3 | cut -c1-200
npm run bench:selection 2>&1 | tail -2
npm run bench:affordances -- --action hover 2>&1 | tail -2
git -C "$REPO" checkout -- packages/terminal/bench/agent-session/baselines && git -C "$REPO" clean -fdq packages/terminal/bench/agent-session/baselines
git -C "$REPO" status --short
```
Expected: `PASS feel gate: zero pixel diff`; `PASS agent-session gate`; three JSON lines from the scroll gate, the first with `"total":60134,"covered":60134` (planning run), exit 0; `bench:selection` `PASS selection survived 21 repaints` on macOS — on Linux write `not run: Linux copy chord`; affordances writes screenshots (never diffed); the final `git status` shows only what this part is about to commit (nothing under `bench/agent-session/baselines`).

- [ ] **G7 Daemon binary**

```bash
cd "$REPO" && npm --prefix frontend run build:daemon 2>&1 | tail -2
```
Expected: builds `frontend/daemon/opr` (it embeds `vt_host.wasm`). If the environment cannot build it: `not run: <reason>`.

---
### Task 0: Branch, toolchains, baselines

**Files:** none committed.

**Interfaces:**
- Consumes: nothing.
- Produces: `$REPO` (exported), the branch, `$HOME/plan9-feel-baseline/` (this machine's `bench:feel` picture of the unmodified tree), your Task 0 test counts.

- [ ] **Step 1: Branch**

```bash
export REPO="$(git rev-parse --show-toplevel)"
cd "$REPO" && git fetch origin && git checkout -b terminal/plan-9-parser-rework origin/development
git log --oneline -1
```
Expected: `585c0e68d fix(terminal): one throwing program-message listener no longer drops the rest` (or a later commit; if later, every edit below quotes the text it replaces — apply it by that text, and if a quoted text is not found, stop and report the file and the quote).

- [ ] **Step 2: Toolchains**

```bash
cd "$REPO/packages/terminal" && rustup show active-toolchain && rustup target list --installed | grep wasm32
```
Expected: `1.96.0-…` and `wasm32-unknown-unknown` (`rust-toolchain.toml` pins both).

```bash
wasm-bindgen --version || cargo install wasm-bindgen-cli --version 0.2.127 --locked
wasm-bindgen --version
```
Expected: `wasm-bindgen 0.2.127` exactly (`scripts/build-wasm.mjs:22` refuses any other).

```bash
export GOTOOLCHAIN=auto
cd "$REPO/backend" && go version
node --version
```
Expected: a Go version ≥ `go1.25.7` (`backend/go.mod`); any Node ≥ 20. Keep `GOTOOLCHAIN=auto` exported for the whole session.

```bash
cd "$REPO/packages/terminal" && npm ci --no-audit --no-fund
cd "$REPO/frontend" && npm ci --no-audit --no-fund
cd "$REPO/packages/terminal" && npx playwright install chromium
```
If `playwright install` fails with HTTP 403 (CDN blocked): `ls /opt/pw-browsers`, read the directory names Playwright wants from the error (`chromium-<rev>`, `chromium_headless_shell-<rev>`), and symlink each wanted name under `/opt/pw-browsers` to the preinstalled directory of the same kind, e.g. `ln -s /opt/pw-browsers/chromium-<have> /opt/pw-browsers/chromium-<want>`; then `export PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers`. Never commit anything for this.

- [ ] **Step 3: Baselines of the unmodified tree**

```bash
cd "$REPO/packages/terminal" && cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-baseline-done
npm run build:wasm -- --force 2>&1 | tail -1 && npm run build:ts 2>&1 | tail -1
for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  "); done
npm run check:boundaries 2>&1 | tail -2
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -3
```
Expected (planning run): no FAILED/panicked line; `Tests  179 passed (179)` (core), `985`, `134`, `175`, `109`; `boundary check passed`; three `ok` lines. Record your counts — G3 compares against them.

```bash
cd "$REPO/packages/terminal" && npm run bench:feel -- --record 2>&1 | tail -1
rm -rf "$HOME/plan9-feel-baseline" && cp -R bench/agent-session/baselines "$HOME/plan9-feel-baseline"
git -C "$REPO" checkout -- packages/terminal/bench/agent-session/baselines && git -C "$REPO" clean -fdq packages/terminal/bench/agent-session/baselines
npm run bench:agent:gate 2>&1 | tail -1
git -C "$REPO" status --short
```
Expected: `recorded feel baselines`; `PASS agent-session gate` (if it fails here, record it as pre-existing); an empty `git status`.

---

### Task 1: Safety net — parser goldens and throughput tools

**Files:**
- Create: `packages/terminal/crates/vt-core/tests/golden_support/mod.rs`
- Create: `packages/terminal/crates/vt-core/tests/golden_support/synthetic.rs`
- Create: `packages/terminal/crates/vt-core/tests/parser_goldens.rs`
- Create (generated): `packages/terminal/crates/vt-core/tests/goldens/*.golden` (53 files)
- Create: `packages/terminal/crates/vt-core/examples/parse_throughput.rs`
- Create: `packages/terminal/bench/parse-throughput.mjs`
- Outside the repository (never committed): `$HOME/ab-verdict.mjs`, `$HOME/plan9-snapshot.sh`, `$HOME/plan9-ab.sh`, `$HOME/plan9-bin/control`, `$HOME/plan9-wasm/control/`

**Interfaces:**
- Consumes: the public `vt_core::TerminalCore` API only (`with_limits`, `resize`, `set_grapheme_clusters`, `set_answers_queries`, `set_terminal_identity`, `set_cell_pixels`, `set_default_colors`, `set_reflow_on_resize`, `set_cold_ring_bytes`, `set_agent_tui_mode`, `feed_at`, `tick`, `take_delta`, `take_query_replies`, `take_notifications`, `take_agent_events`, `take_typeahead`, `snapshot`, `alt_snapshot`, the mode getters, `title`, `pointer_shape`, `title_stack_depth`, `live_output_bytes`, `older_state`, `synchronized_output`, `pending_sync_bytes`, `verify_integrity`); the renderer wasm's `WasmTerminalCore` (`new`, `resize`, `setGraphemeClusters`, `feed`, `free`).
- Produces: `cargo test -p vt-core --test parser_goldens` (the behaviour gate for every later task); `cargo run --release -p vt-core --example parse_throughput -- <label>` printing `<label> <workload> <grapheme|scalar> <x.xx> MB/s` for `claude-long-50k`, `ascii-heavy`, `edit-heavy`; `node bench/parse-throughput.mjs <label> [<wasm dir>]` printing `<label> wasm claude-long-50k <mode> <x.xx> MB/s`; `$HOME/plan9-snapshot.sh <name>` and `$HOME/plan9-ab.sh <control> <candidate> <log>`.

- [ ] **Step 1: Write the digest harness**

Create `packages/terminal/crates/vt-core/tests/golden_support/mod.rs`:

```rust
pub mod synthetic;

use vt_core::{Limits, TerminalCore};

pub const ROW_GROUP: usize = 500;
pub const ODD_CHUNKS: [usize; 6] = [1, 3, 7, 64, 509, 4093];
pub const EVEN_CHUNK: usize = 4096;
pub const CLOCK_STEP_MS: u64 = 7;

#[derive(Clone, Copy)]
pub struct Config {
    pub name: &'static str,
    pub graphemes: bool,
    pub agent_tui: bool,
    pub mirror: bool,
    pub odd_chunks: bool,
}

pub const CONFIGS: [Config; 4] = [
    Config {
        name: "renderer",
        graphemes: true,
        agent_tui: false,
        mirror: false,
        odd_chunks: false,
    },
    Config {
        name: "renderer-odd",
        graphemes: true,
        agent_tui: false,
        mirror: false,
        odd_chunks: true,
    },
    Config {
        name: "mirror",
        graphemes: false,
        agent_tui: false,
        mirror: true,
        odd_chunks: false,
    },
    Config {
        name: "agent-odd",
        graphemes: false,
        agent_tui: true,
        mirror: false,
        odd_chunks: true,
    },
];

#[derive(Clone, Copy)]
pub struct Size {
    pub offset: usize,
    pub cols: usize,
    pub rows: usize,
}

pub struct Fnv(u64);

impl Fnv {
    pub fn new() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }

    pub fn write(&mut self, bytes: &[u8]) {
        for byte in bytes {
            self.0 ^= u64::from(*byte);
            self.0 = self.0.wrapping_mul(0x0100_0000_01b3);
        }
    }

    pub fn write_str(&mut self, text: &str) {
        self.write(text.as_bytes());
        self.write(&[0xff]);
    }

    pub fn finish(&self) -> String {
        format!("{:016x}", self.0)
    }
}

struct Stream {
    deltas: Fnv,
    replies: Vec<u8>,
    notifications: Vec<String>,
    agent_events: Vec<String>,
    typeahead: Vec<String>,
    feeds: usize,
}

fn new_core(first: Size, config: &Config) -> TerminalCore {
    let limits = if config.mirror {
        Limits {
            rows: 20_000,
            bytes: 256 * 1024,
        }
    } else {
        Limits::DEFAULT
    };
    let mut core = TerminalCore::with_limits(first.cols, limits).expect("core");
    core.resize(first.cols, first.rows);
    core.set_grapheme_clusters(config.graphemes);
    core.set_answers_queries(true);
    core.set_terminal_identity("GoldenTerm");
    core.set_cell_pixels(9, 18);
    core.set_default_colors(Some(0x00dd_dddd), Some(0x0011_1111));
    if config.mirror {
        core.set_reflow_on_resize(false);
        core.set_cold_ring_bytes(1 << 20);
    }
    if config.agent_tui {
        core.set_agent_tui_mode(true);
    }
    core
}

fn drain(core: &mut TerminalCore, stream: &mut Stream) {
    let delta = core.take_delta();
    stream.deltas.write_str(&format!("{delta:?}"));
    stream.replies.extend(core.take_query_replies());
    for note in core.take_notifications() {
        stream.notifications.push(format!("{note:?}"));
    }
    for event in core.take_agent_events() {
        stream.agent_events.push(format!("{event:?}"));
    }
    if let Some(text) = core.take_typeahead() {
        stream.typeahead.push(text);
    }
}

fn feed_range(core: &mut TerminalCore, bytes: &[u8], config: &Config, stream: &mut Stream) {
    let mut at = 0usize;
    while at < bytes.len() {
        let step = if config.odd_chunks {
            ODD_CHUNKS[stream.feeds % ODD_CHUNKS.len()]
        } else {
            EVEN_CHUNK
        };
        let end = (at + step).min(bytes.len());
        stream.feeds += 1;
        core.feed_at(&bytes[at..end], stream.feeds as u64 * CLOCK_STEP_MS);
        drain(core, stream);
        at = end;
    }
}

pub fn replay(recording: &[u8], sizes: &[Size], config: &Config) -> Vec<String> {
    let first = sizes[0];
    let mut core = new_core(first, config);
    let mut stream = Stream {
        deltas: Fnv::new(),
        replies: Vec::new(),
        notifications: Vec::new(),
        agent_events: Vec::new(),
        typeahead: Vec::new(),
        feeds: 0,
    };
    let mut fed = 0usize;
    for size in sizes.iter().skip(1) {
        let upto = size.offset.min(recording.len());
        if upto > fed {
            feed_range(&mut core, &recording[fed..upto], config, &mut stream);
            fed = upto;
        }
        core.resize(size.cols, size.rows);
        drain(&mut core, &mut stream);
    }
    if fed < recording.len() {
        feed_range(&mut core, &recording[fed..], config, &mut stream);
    }
    let tick_at = (stream.feeds as u64 + 1) * CLOCK_STEP_MS + 1_000;
    core.tick(tick_at);
    drain(&mut core, &mut stream);
    core.verify_integrity().expect("integrity");
    digest(&core, &stream, config)
}

fn digest(core: &TerminalCore, stream: &Stream, config: &Config) -> Vec<String> {
    let name = config.name;
    let snapshot = core.snapshot().expect("snapshot");
    let mut lines = Vec::new();
    let rows = snapshot.row_count();
    lines.push(format!("{name} rows {rows}"));
    let mut group = 0usize;
    while group * ROW_GROUP < rows {
        let mut text = Fnv::new();
        let mut styles = Fnv::new();
        let mut spans = Fnv::new();
        for row in group * ROW_GROUP..((group + 1) * ROW_GROUP).min(rows) {
            text.write_str(&format!(
                "{}|{}|{}",
                snapshot.row_indent(row),
                snapshot.row_wrapped(row),
                snapshot.row_text(row)
            ));
            styles.write_str(&format!("{:?}", snapshot.row_style_pairs(row)));
            spans.write_str(&format!("{:?}", snapshot.row_cell_spans(row)));
        }
        lines.push(format!(
            "{name} rows[{}..] text {} styles {} spans {}",
            group * ROW_GROUP,
            text.finish(),
            styles.finish(),
            spans.finish()
        ));
        group += 1;
    }
    let mut blocks = Fnv::new();
    blocks.write_str(&format!("{:?}", snapshot.blocks));
    blocks.write(&snapshot.block_text);
    lines.push(format!(
        "{name} blocks {} {}",
        snapshot.blocks.len(),
        blocks.finish()
    ));
    let mut links = Fnv::new();
    links.write_str(&format!("{:?}", snapshot.link_ranges));
    links.write(&snapshot.link_text);
    lines.push(format!("{name} links {}", links.finish()));
    lines.push(format!(
        "{name} cursor {} {} {} history {} first_stable {} editor {}",
        snapshot.cursor_row,
        snapshot.cursor_col,
        snapshot.cursor_visible,
        snapshot.history_rows,
        snapshot.first_stable_row,
        snapshot.line_editor_state
    ));
    let alt = match core.alt_snapshot() {
        None => "none".to_string(),
        Some(alt) => {
            let mut hash = Fnv::new();
            hash.write(&alt.content);
            hash.write_str(&format!(
                "{:?}{:?}{:?}{:?}{:?}{} {} {}",
                alt.row_ranges,
                alt.run_ranges,
                alt.style_pairs,
                alt.span_ranges,
                alt.cell_spans,
                alt.cursor_row,
                alt.cursor_col,
                alt.cursor_visible
            ));
            format!("{}x{} {}", alt.cols, alt.rows, hash.finish())
        }
    };
    lines.push(format!("{name} alt {alt}"));
    lines.push(format!(
        "{name} modes app_cursor={} sgr_mouse={} paste={} focus={} mouse={} sync={} pending_sync={}",
        core.application_cursor_keys(),
        core.sgr_mouse(),
        core.bracketed_paste(),
        core.focus_reporting(),
        core.mouse_tracking_level(),
        core.synchronized_output(),
        core.pending_sync_bytes().len()
    ));
    lines.push(format!(
        "{name} program title={:?} pointer={:?} stack={} live_output={} older={:?}",
        core.title(),
        core.pointer_shape(),
        core.title_stack_depth(),
        core.live_output_bytes(),
        core.older_state()
    ));
    lines.push(format!(
        "{name} replies {:?}",
        String::from_utf8_lossy(&stream.replies)
    ));
    let mut notes = Fnv::new();
    for note in &stream.notifications {
        notes.write_str(note);
    }
    lines.push(format!(
        "{name} notifications {} {}",
        stream.notifications.len(),
        notes.finish()
    ));
    let mut events = Fnv::new();
    for event in &stream.agent_events {
        events.write_str(event);
    }
    lines.push(format!(
        "{name} agent_events {} {}",
        stream.agent_events.len(),
        events.finish()
    ));
    lines.push(format!("{name} typeahead {:?}", stream.typeahead));
    lines.push(format!(
        "{name} deltas {} {}",
        stream.feeds,
        stream.deltas.finish()
    ));
    lines
}
```

Create `packages/terminal/crates/vt-core/tests/golden_support/synthetic.rs`:

```rust
use super::Size;

pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        Self(seed | 1)
    }

    pub fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }

    pub fn below(&mut self, bound: usize) -> usize {
        (self.next() % bound as u64) as usize
    }

    pub fn pick<'a>(&mut self, items: &[&'a [u8]]) -> &'a [u8] {
        items[self.below(items.len())]
    }
}

pub struct Synthetic {
    pub name: &'static str,
    pub bytes: Vec<u8>,
    pub sizes: Vec<Size>,
}

const STYLES: [&[u8]; 10] = [
    b"\x1b[0m",
    b"\x1b[1;32m",
    b"\x1b[38;5;123m",
    b"\x1b[48;2;10;20;30m",
    b"\x1b[3;4:3;58;5;9m",
    b"\x1b[7m",
    b"\x1b[2;53m",
    b"\x1b[39;49m",
    b"\x1b[22;23;24m",
    b"\x1b[m",
];

pub fn ascii_heavy(total: usize) -> Vec<u8> {
    let mut rng = Rng::new(0x9e37_79b9_7f4a_7c15);
    let mut out = Vec::with_capacity(total + 256);
    while out.len() < total {
        let len = rng.below(200);
        for _ in 0..len {
            match rng.below(40) {
                0 => out.extend_from_slice(rng.pick(&STYLES)),
                1 => out.push(b'\t'),
                2 => out.extend_from_slice(b"\x1b[K"),
                _ => out.push(b' ' + rng.below(95) as u8),
            }
        }
        out.extend_from_slice(b"\r\n");
    }
    out
}

const UNICODE: [&[u8]; 16] = [
    "é".as_bytes(),
    "中文".as_bytes(),
    "e\u{301}".as_bytes(),
    "👍🏽".as_bytes(),
    "👨‍👩‍👧".as_bytes(),
    "🇪🇬".as_bytes(),
    "\u{600}a".as_bytes(),
    "\u{200b}".as_bytes(),
    "❤\u{fe0f}".as_bytes(),
    b"\xff",
    b"\xc3",
    b"\x80\x80",
    "\u{9b}".as_bytes(),
    b"plain ascii ",
    "\u{1100}\u{1161}\u{11a8}".as_bytes(),
    "abc".as_bytes(),
];

pub fn unicode_mix(total: usize) -> Vec<u8> {
    let mut rng = Rng::new(0x1234_5678_9abc_def1);
    let mut out = Vec::with_capacity(total + 256);
    while out.len() < total {
        out.extend_from_slice(rng.pick(&UNICODE));
        match rng.below(12) {
            0 => out.extend_from_slice(b"\r\n"),
            1 => out.extend_from_slice(rng.pick(&STYLES)),
            2 => out.extend_from_slice(b"\x1b[3D"),
            _ => {}
        }
    }
    out
}

pub fn malformed() -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(b"start\r\n");
    out.extend_from_slice(b"\x1b]0;");
    out.extend(std::iter::repeat_n(b't', 3000));
    out.extend_from_slice(b"\x07after title\r\n");
    out.extend_from_slice(b"\x1b]8;;https://example.com/");
    out.extend(std::iter::repeat_n(b'u', 3000));
    out.extend_from_slice(b"\x1b\\long link\x1b]8;;\x1b\\\r\n");
    out.extend_from_slice(b"\x1b]8;id=a;https://a.example\x1b\\linked\x1b]8;\x1b\\ tail\r\n");
    out.extend_from_slice(b"\x1b[");
    for index in 1..=40 {
        out.extend_from_slice(format!("{index};").as_bytes());
    }
    out.extend_from_slice(b"mforty params\r\n");
    out.extend_from_slice(b"\x1b[?$>p three intermediates\r\n");
    out.extend_from_slice(b"\x1b[>4;2mnot sgr\x1b[?4mnot sgr either\r\n");
    out.extend_from_slice(b"\x1b]0;unterminated\x1b[31mred after unterminated osc\x1b[0m\r\n");
    out.extend_from_slice(
        b"\x1bP1$qm\x1b\\dcs\x1b_apc payload\x1b\\\x1bXsos\x1b\\\x1b^pm\x1b\\\r\n",
    );
    out.extend_from_slice(b"\x1b[3\x18Xcan\x1b[4\x1aYsub\r\n");
    out.extend_from_slice(b"\x1b[99999999999A\x1b[0;0H\x1b[65535;65535H\x1b[H");
    out.extend_from_slice(b"\x1b]777;agent-state;v=1;state=working;detail=x\x07");
    out.extend_from_slice(b"\x1b]777;notify;Title;Body\x07\x1b]9;nine\x07\x1b]99;;kitty\x1b\\");
    out.extend_from_slice(
        b"\x1b]10;?\x07\x1b]11;?\x1b\\\x1b[16t\x1b[14t\x1b[18t\x1b[22;0t\x1b[22;1t\x1b[23;0t",
    );
    out.extend_from_slice(
        b"\x1b[>0q\x1b[c\x1b[0c\x1b[>c\x1b[?2026;1;25;9999$p\x1b[?2048h\x1b[?2048l",
    );
    out.extend_from_slice(b"\x1bZ\x1b#8\x1b(0lqk\x1b(Bf\x1b[3b\r\n");
    out.extend_from_slice(b"\x1b]22;pointer\x07\x1b]22;text\x07\x1b]1;icon\x07\x1b]2;two\x07");
    out.extend_from_slice(b"\x1b[?1;1000;1002;1006;1004;2004h\x1b[?25;1l\x1b[?25h");
    out.extend_from_slice(
        b"\x1b]133;A\x07$ \x1b]133;B\x07ls\r\n\x1b]133;C\x07out\r\n\x1b]133;D;0\x07",
    );
    out.extend_from_slice(b"\x1b[?2026hsync body\r\n\x1b[?2026l");
    out.extend_from_slice(b"\x1b[?2026hunterminated sync");
    out
}

const EDITS: [&[u8]; 22] = [
    b"\x1b[3@",
    b"\x1b[2P",
    b"\x1b[5X",
    b"\x1b[K",
    b"\x1b[1K",
    b"\x1b[2K",
    b"\x1b[J",
    b"\x1b[1J",
    b"\x1b[2L",
    b"\x1b[M",
    b"\x1b[S",
    b"\x1b[2T",
    b"\x1b[3;9r",
    b"\x1b[r",
    b"\x1b[5;7H",
    b"\x1b[A",
    b"\x1b[2B",
    b"\x1b[10G",
    b"\x1bM",
    b"\x1b7\x1b[H\x1b8",
    b"\r\n",
    b"\x1b[2J",
];

const TEXT: [&[u8]; 8] = [
    b"plain words here",
    "wide 中文字".as_bytes(),
    "combining e\u{301}\u{302}".as_bytes(),
    "emoji 👍🏽 ok".as_bytes(),
    b"\x1b]8;;https://x.example\x1b\\link\x1b]8;;\x1b\\",
    b"0123456789abcdefghijklmnopqrstuvwxyz",
    b"\ttabbed",
    b"x",
];

pub fn edits_styled(steps: usize) -> Vec<u8> {
    let mut rng = Rng::new(0x0bad_cafe_f00d_d00d);
    let mut out = Vec::new();
    for _ in 0..steps {
        match rng.below(3) {
            0 => out.extend_from_slice(rng.pick(&STYLES)),
            1 => out.extend_from_slice(rng.pick(&TEXT)),
            _ => out.extend_from_slice(rng.pick(&EDITS)),
        }
    }
    out
}

pub fn all() -> Vec<Synthetic> {
    let single = |cols, rows| {
        vec![Size {
            offset: 0,
            cols,
            rows,
        }]
    };
    let ascii = ascii_heavy(256 * 1024);
    let ascii_len = ascii.len();
    vec![
        Synthetic {
            name: "synthetic-ascii-heavy",
            bytes: ascii,
            sizes: vec![
                Size {
                    offset: 0,
                    cols: 80,
                    rows: 24,
                },
                Size {
                    offset: ascii_len / 2,
                    cols: 61,
                    rows: 30,
                },
            ],
        },
        Synthetic {
            name: "synthetic-unicode-mix",
            bytes: unicode_mix(64 * 1024),
            sizes: single(20, 10),
        },
        Synthetic {
            name: "synthetic-malformed",
            bytes: malformed(),
            sizes: single(40, 12),
        },
        Synthetic {
            name: "synthetic-edits-styled",
            bytes: edits_styled(20_000),
            sizes: single(40, 12),
        },
    ]
}
```

Create `packages/terminal/crates/vt-core/tests/parser_goldens.rs`:

```rust
mod golden_support;

use std::fs;
use std::path::{Path, PathBuf};

use golden_support::{replay, synthetic, Size, CONFIGS};

fn manifest() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn read_sizes(path: &Path) -> Vec<Size> {
    let raw = fs::read_to_string(path).expect("size.json");
    let values: Vec<serde_json::Value> = serde_json::from_str(&raw).expect("size.json array");
    values
        .iter()
        .map(|value| Size {
            offset: value["offset"].as_u64().expect("offset") as usize,
            cols: value["cols"].as_u64().expect("cols") as usize,
            rows: value["rows"].as_u64().expect("rows") as usize,
        })
        .collect()
}

fn recordings() -> Vec<(String, Vec<u8>, Vec<Size>)> {
    let mut out = Vec::new();
    let mut dirs: Vec<(String, PathBuf)> = Vec::new();
    for base in [
        manifest().join("tests/ref"),
        manifest().join("../../bench/agent-session/fixtures"),
    ] {
        for entry in fs::read_dir(&base).expect("recording dir") {
            let path = entry.expect("entry").path();
            if path.join("recording").is_file() && path.join("size.json").is_file() {
                let name = path.file_name().unwrap().to_string_lossy().into_owned();
                dirs.push((name, path));
            }
        }
    }
    dirs.sort();
    for (name, path) in dirs {
        let bytes = fs::read(path.join("recording")).expect("recording");
        out.push((name, bytes, read_sizes(&path.join("size.json"))));
    }
    for item in synthetic::all() {
        out.push((item.name.to_string(), item.bytes, item.sizes));
    }
    out
}

fn golden_path(name: &str) -> PathBuf {
    manifest()
        .join("tests/goldens")
        .join(format!("{name}.golden"))
}

#[test]
fn every_recording_matches_the_goldens_recorded_before_the_parser_rework() {
    let update = std::env::var_os("UPDATE_GOLDENS").is_some();
    let mut failures = Vec::new();
    let sources = recordings();
    assert!(sources.len() >= 53, "found {} recordings", sources.len());
    for (name, bytes, sizes) in sources {
        let mut lines = Vec::new();
        for config in CONFIGS.iter() {
            lines.extend(replay(&bytes, &sizes, config));
        }
        let got = lines.join("\n") + "\n";
        let path = golden_path(&name);
        if update {
            fs::write(&path, &got).expect("write golden");
            continue;
        }
        let want = fs::read_to_string(&path).unwrap_or_else(|_| {
            panic!(
                "{} missing (UPDATE_GOLDENS=1 on the unmodified tree)",
                path.display()
            )
        });
        if got != want {
            let first = got
                .lines()
                .zip(want.lines())
                .find(|(g, w)| g != w)
                .map(|(g, w)| format!("got  {g}\nwant {w}"))
                .unwrap_or_else(|| "line count differs".to_string());
            failures.push(format!("{name}:\n{first}"));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n\n"));
}
```

- [ ] **Step 2: Run it before any golden exists — it must fail**

```bash
cd "$REPO/packages/terminal" && mkdir -p crates/vt-core/tests/goldens && cargo test --release -p vt-core --test parser_goldens 2>&1 | grep -E "missing|test result"
```
Expected: a panic naming `…/tests/goldens/alt_reset.golden missing (UPDATE_GOLDENS=1 on the unmodified tree)` and `test result: FAILED. 0 passed; 1 failed`.

- [ ] **Step 3: Generate the goldens on the unmodified tree, then prove they are deterministic**

```bash
cd "$REPO/packages/terminal" && git -C "$REPO" status --short packages/terminal/crates/vt-core/src
UPDATE_GOLDENS=1 cargo test --release -p vt-core --test parser_goldens 2>&1 | grep "test result"
ls crates/vt-core/tests/goldens | wc -l
cargo test --release -p vt-core --test parser_goldens 2>&1 | grep "test result"
cargo test -p vt-core --test parser_goldens 2>&1 | grep "test result"
grep -E "^renderer (rows |replies|deltas)|^mirror rows " crates/vt-core/tests/goldens/claude-long-50k.golden
grep -rl "Operator" crates/vt-core/tests/goldens | wc -l
```
Expected: the first command prints nothing (no source file is modified — the goldens must describe the unmodified parser); `test result: ok. 1 passed` three times (update, release, debug — debug takes ~20 s); `53`; and, identical on the planning Mac (a difference here is not a failure — the goldens are yours — but report it):

```text
renderer rows 60137
renderer replies "\u{1b}P>|GoldenTerm\u{1b}\\\u{1b}[?62;22c\u{1b}P>|GoldenTerm\u{1b}\\\u{1b}[?62;22c"
renderer deltas 1933 9227ea55fa4f9b65
mirror rows 20039
```
and `0` (no product name in test data).

- [ ] **Step 4: The throughput example and the wasm cross-check**

Create `packages/terminal/crates/vt-core/examples/parse_throughput.rs`:

```rust
use std::path::PathBuf;
use std::time::Instant;

use vt_core::{Limits, TerminalCore};

const RUNS: usize = 7;
const CHUNK: usize = 64 << 10;
const ASCII_BYTES: usize = 16 << 20;

fn ascii_stream(total: usize) -> Vec<u8> {
    let styles: [&[u8]; 4] = [b"\x1b[1;32m", b"\x1b[0m", b"\x1b[38;5;208m", b"\x1b[39m"];
    let mut state = 0x9e37_79b9_7f4a_7c15u64;
    let mut next = move || {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        state
    };
    let mut out = Vec::with_capacity(total + 256);
    while out.len() < total {
        let len = (next() % 160) as usize;
        for _ in 0..len {
            if next() % 40 == 0 {
                out.extend_from_slice(styles[(next() % 4) as usize]);
            } else {
                out.push(b' ' + (next() % 95) as u8);
            }
        }
        out.extend_from_slice(b"\r\n");
    }
    out
}

fn edit_stream(total: usize) -> Vec<u8> {
    let styles: [&[u8]; 3] = [b"\x1b[1;36m", b"\x1b[0m", b"\x1b[2m"];
    let edits: [&[u8]; 6] = [
        b"\x1b[5P", b"\x1b[3@", b"\x1b[4X", b"\x1b[1K", b"\x1b[K", b"\x1b[2K",
    ];
    let mut state = 0x0bad_cafe_f00d_d00du64;
    let mut next = move || {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        state
    };
    let mut out = Vec::with_capacity(total + 4096);
    while out.len() < total {
        out.extend_from_slice(b"\x1b[20A");
        for _ in 0..20 {
            out.extend_from_slice(b"\r\x1b[2K");
            out.extend_from_slice(styles[(next() % 3) as usize]);
            for _ in 0..(next() % 110) {
                out.push(b'a' + (next() % 26) as u8);
            }
            out.extend_from_slice(b"\x1b[0m\x1b[30G");
            out.extend_from_slice(edits[(next() % 6) as usize]);
            out.extend_from_slice(b"\x1b[B");
        }
        out.extend_from_slice(b"\r\n\r\n");
    }
    out
}

fn mb_per_second(bytes: &[u8], graphemes: bool) -> f64 {
    let mut core = TerminalCore::with_limits(120, Limits::DEFAULT).expect("core");
    core.resize(120, 40);
    core.set_grapheme_clusters(graphemes);
    let start = Instant::now();
    for chunk in bytes.chunks(CHUNK) {
        core.feed(chunk);
    }
    let seconds = start.elapsed().as_secs_f64();
    bytes.len() as f64 / (1024.0 * 1024.0) / seconds
}

fn median(mut values: Vec<f64>) -> f64 {
    values.sort_by(|a, b| a.partial_cmp(b).expect("finite"));
    values[values.len() / 2]
}

fn main() {
    let label = std::env::args().nth(1).unwrap_or_else(|| "run".to_string());
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bench/agent-session/fixtures/claude-long-50k/recording");
    let claude = std::fs::read(&fixture).expect("claude-long-50k recording");
    let ascii = ascii_stream(ASCII_BYTES);
    let edits = edit_stream(ASCII_BYTES);
    for (name, bytes) in [
        ("claude-long-50k", &claude),
        ("ascii-heavy", &ascii),
        ("edit-heavy", &edits),
    ] {
        for (mode, graphemes) in [("grapheme", true), ("scalar", false)] {
            let samples: Vec<f64> = (0..RUNS).map(|_| mb_per_second(bytes, graphemes)).collect();
            println!("{label} {name} {mode} {:.2} MB/s", median(samples));
        }
    }
}
```

Create `packages/terminal/bench/parse-throughput.mjs`:

```js
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const benchDir = path.dirname(fileURLToPath(import.meta.url));
const label = process.argv[2] ?? "run";
const wasmDir = path.resolve(process.argv[3] ?? path.join(benchDir, "..", "ts", "core", "wasm"));
const RUNS = 7;
const CHUNK = 64 * 1024;

const glue = await import(pathToFileURL(path.join(wasmDir, "vt_core.js")).href);
glue.initSync({ module: readFileSync(path.join(wasmDir, "vt_core_bg.wasm")) });

const recording = readFileSync(path.join(benchDir, "agent-session", "fixtures", "claude-long-50k", "recording"));

function mbPerSecond(graphemes) {
	const core = new glue.WasmTerminalCore(120, 200_000, 128 * 1024 * 1024);
	core.resize(120, 40);
	core.setGraphemeClusters(graphemes);
	const start = performance.now();
	for (let at = 0; at < recording.length; at += CHUNK) {
		core.feed(recording.subarray(at, Math.min(at + CHUNK, recording.length)), 0);
	}
	const seconds = (performance.now() - start) / 1000;
	core.free();
	return recording.length / (1024 * 1024) / seconds;
}

for (const [mode, graphemes] of [["grapheme", true], ["scalar", false]]) {
	const samples = [];
	for (let run = 0; run < RUNS; run += 1) samples.push(mbPerSecond(graphemes));
	samples.sort((a, b) => a - b);
	console.log(`${label} wasm claude-long-50k ${mode} ${samples[Math.floor(RUNS / 2)].toFixed(2)} MB/s`);
}
```

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo run --release -p vt-core --example parse_throughput -- smoke
node bench/parse-throughput.mjs smoke
npm run check:boundaries 2>&1 | tail -2
```
Expected: `Finished …`; six `smoke <workload> <mode> <x.xx> MB/s` lines (planning: claude-long-50k grapheme ≈30, scalar ≈73, ascii-heavy ≈23/≈48, edit-heavy ≈30/≈62) and two `smoke wasm claude-long-50k …` lines (≈28, ≈51) — the renderer wasm from Task 0 is in `ts/core/wasm`; `boundary check passed`.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-core/tests/golden_support/mod.rs \
  packages/terminal/crates/vt-core/tests/golden_support/synthetic.rs \
  packages/terminal/crates/vt-core/tests/parser_goldens.rs \
  packages/terminal/crates/vt-core/tests/goldens \
  packages/terminal/crates/vt-core/examples/parse_throughput.rs \
  packages/terminal/bench/parse-throughput.mjs
git commit -m "test(terminal): parser goldens and throughput tools before the parser rework" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
Expected: one commit; a clean status.

- [ ] **Step 6: A/B helpers and the control snapshot (outside the repository, never committed)**

```bash
cat > "$HOME/ab-verdict.mjs" <<'EOF'
import { readFileSync } from "node:fs";

const [file, control, candidate] = process.argv.slice(2);
const lines = readFileSync(file, "utf8").split("\n").filter((line) => line.endsWith(" MB/s"));
const groups = new Map();
for (const line of lines) {
	const words = line.split(" ");
	const label = words[0];
	const value = Number(words[words.length - 2]);
	const key = words.slice(1, -2).join(" ");
	if (!groups.has(key)) groups.set(key, { [control]: [], [candidate]: [] });
	if (label === control || label === candidate) groups.get(key)[label].push(value);
}
for (const [key, sides] of groups) {
	const a = sides[control].sort((x, y) => x - y);
	const b = sides[candidate].sort((x, y) => x - y);
	if (a.length !== 3 || b.length !== 3) {
		console.log(`${key}: need 3 runs per side, have ${a.length} and ${b.length}`);
		continue;
	}
	const middle = a[1];
	let verdict = "noise";
	if (b[0] > a[2]) verdict = "faster";
	else if (b[2] < a[0] && (a[0] - b[2]) / middle > 0.03) verdict = "slower";
	const change = (((b[1] - a[1]) / a[1]) * 100).toFixed(1);
	console.log(`${key}: ${control} ${a[0].toFixed(2)}-${a[2].toFixed(2)} ${candidate} ${b[0].toFixed(2)}-${b[2].toFixed(2)} (${change}% median) ${verdict}`);
}
EOF
cat > "$HOME/plan9-snapshot.sh" <<'EOF'
set -euo pipefail
name="$1"
cd "$REPO/packages/terminal"
cargo build --release -p vt-core --example parse_throughput
mkdir -p "$HOME/plan9-bin" "$HOME/plan9-wasm"
cp target/release/examples/parse_throughput "$HOME/plan9-bin/$name"
npm run build:wasm -- --force
rm -rf "$HOME/plan9-wasm/$name"
cp -R ts/core/wasm "$HOME/plan9-wasm/$name"
echo "snapshot $name ready"
EOF
cat > "$HOME/plan9-ab.sh" <<'EOF'
set -euo pipefail
control="$1"
candidate="$2"
log="$3"
: > "$log"
for pair in 1 2 3; do
  if [ "$pair" = 2 ]; then order="$candidate $control"; else order="$control $candidate"; fi
  for side in $order; do
    "$HOME/plan9-bin/$side" "$side" >> "$log"
    node "$REPO/packages/terminal/bench/parse-throughput.mjs" "$side" "$HOME/plan9-wasm/$side" >> "$log"
  done
done
node "$HOME/ab-verdict.mjs" "$log" "$control" "$candidate"
EOF
bash "$HOME/plan9-snapshot.sh" control 2>&1 | tail -1
```
Expected: `snapshot control ready`. `control` is the Task 1 commit: the parser is unmodified. (Each A/B run below takes about 5 minutes.)

---

### Task 2: Part A — measure `vte::ansi::Handler`, decide, record

**Files:**
- Outside the repository (never committed): `$HOME/plan9-ansi-spike/`
- Modify: `TERMINAL.md` (new §4.35), `docs/terminal/2026-09-19-terminal-reference-survey.md` (§2.2 row and status line, count sentence), `docs/terminal/2026-09-24-not-done-plain-language.md` (item 18)

**Interfaces:**
- Consumes: `vte =0.15.0` from crates.io with `features = ["ansi"]`.
- Produces: the Part A decision (**not adopted**) and `TERMINAL.md` §4.35, which Tasks 6 and 9 extend.

- [ ] **Step 1: Build the spike**

```bash
mkdir -p "$HOME/plan9-ansi-spike/src" && cd "$HOME/plan9-ansi-spike"
cat > Cargo.toml <<'EOF'
[package]
name = "ansi-spike"
version = "0.1.0"
edition = "2021"

[dependencies]
vte = { version = "=0.15.0", default-features = false, features = ["ansi"] }

[workspace]
EOF
cat > rust-toolchain.toml <<'EOF'
[toolchain]
channel = "1.96.0"
targets = ["wasm32-unknown-unknown"]
EOF
cat > src/main.rs <<'EOF'
use core::time::Duration;
use vte::ansi::{Attr, Handler, Hyperlink, PrivateMode, Processor, Timeout};

#[derive(Default)]
struct Inert;

impl Timeout for Inert {
    fn set_timeout(&mut self, _: Duration) {}
    fn clear_timeout(&mut self) {}
    fn pending_timeout(&self) -> bool {
        false
    }
}

#[derive(Default)]
struct Log(Vec<String>);

impl Handler for Log {
    fn input(&mut self, c: char) {
        self.0.push(format!("input {c:?}"));
    }
    fn terminal_attribute(&mut self, attr: Attr) {
        self.0.push(format!("attr {attr:?}"));
    }
    fn identify_terminal(&mut self, i: Option<char>) {
        self.0.push(format!("identify {i:?}"));
    }
    fn report_private_mode(&mut self, m: PrivateMode) {
        self.0.push(format!("report_private_mode {}", m.raw()));
    }
    fn set_private_mode(&mut self, m: PrivateMode) {
        self.0.push(format!("set_private_mode {}", m.raw()));
    }
    fn unset_private_mode(&mut self, m: PrivateMode) {
        self.0.push(format!("unset_private_mode {}", m.raw()));
    }
    fn push_title(&mut self) {
        self.0.push("push_title".into());
    }
    fn text_area_size_pixels(&mut self) {
        self.0.push("text_area_size_pixels".into());
    }
    fn text_area_size_chars(&mut self) {
        self.0.push("text_area_size_chars".into());
    }
    fn set_title(&mut self, t: Option<String>) {
        self.0.push(format!("set_title {t:?}"));
    }
    fn set_hyperlink(&mut self, l: Option<Hyperlink>) {
        self.0.push(format!("set_hyperlink {:?}", l.map(|l| l.uri)));
    }
    fn decaln(&mut self) {
        self.0.push("decaln".into());
    }
}

fn run(label: &str, bytes: &[u8]) {
    let mut processor: Processor<Inert> = Processor::new();
    let mut log = Log::default();
    processor.advance(&mut log, bytes);
    println!("{label}: {:?}", log.0);
}

fn main() {
    run("CSI > 0 q (XTVERSION)", b"\x1b[>0q");
    run("CSI 16 t", b"\x1b[16t");
    run("CSI 22;1 t", b"\x1b[22;1t");
    run("SGR 53", b"\x1b[53m");
    run("SGR 21", b"\x1b[21m");
    run("SGR 38;5;300", b"\x1b[38;5;300m");
    run("SGR 4:6", b"\x1b[4:6m");
    run("OSC 9", b"\x1b]9;done\x07");
    run("OSC 777 notify", b"\x1b]777;notify;t;b\x07");
    run("OSC 777 agent-state", b"\x1b]777;agent-state;v=1;state=idle\x07");
    run("OSC 99", b"\x1b]99;;hi\x07");
    run("OSC 133;A", b"\x1b]133;A\x07");
    run("OSC 1 icon", b"\x1b]1;icon\x07");
    run("OSC 8 two params", b"\x1b]8;\x07");
    run("CSI b (REP)", b"f\x1b[3b");
    run("ESC Z", b"\x1bZ");
    run("ESC # 8", b"\x1b#8");
    run("DECRQM two modes", b"\x1b[?1;2026$p");
    run("CSI ? 25 ; 1 l", b"\x1b[?25;1l");
    println!("Processor::new heap bytes: {}", processor_heap());
}

mod alloc_count {
    use std::alloc::{GlobalAlloc, Layout, System};
    use std::sync::atomic::{AtomicUsize, Ordering};
    pub static BYTES: AtomicUsize = AtomicUsize::new(0);
    pub struct Counting;
    unsafe impl GlobalAlloc for Counting {
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            BYTES.fetch_add(layout.size(), Ordering::Relaxed);
            unsafe { System.alloc(layout) }
        }
        unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
            unsafe { System.dealloc(ptr, layout) }
        }
    }
}

#[global_allocator]
static GLOBAL: alloc_count::Counting = alloc_count::Counting;

pub fn processor_heap() -> usize {
    let before = alloc_count::BYTES.load(std::sync::atomic::Ordering::Relaxed);
    let processor: Processor<Inert> = Processor::new();
    let after = alloc_count::BYTES.load(std::sync::atomic::Ordering::Relaxed);
    drop(processor);
    after - before
}
EOF
cargo run -q
cargo build -q --target wasm32-unknown-unknown && echo wasm32-no-std-ok
```

- [ ] **Step 2: Compare with the expected output**

Expected, exactly:

```text
CSI > 0 q (XTVERSION): []
CSI 16 t: []
CSI 22;1 t: ["push_title"]
SGR 53: []
SGR 21: ["attr CancelBold"]
SGR 38;5;300: []
SGR 4:6: ["attr Underline"]
OSC 9: []
OSC 777 notify: []
OSC 777 agent-state: []
OSC 99: []
OSC 133;A: []
OSC 1 icon: []
OSC 8 two params: []
CSI b (REP): ["input 'f'", "input 'f'", "input 'f'", "input 'f'"]
ESC Z: ["identify None"]
ESC # 8: ["decaln"]
DECRQM two modes: ["report_private_mode 1"]
CSI ? 25 ; 1 l: ["unset_private_mode 25", "unset_private_mode 1"]
Processor::new heap bytes: 2097152
wasm32-no-std-ok
```

What each line means for vt-core (the evidence of the Design decisions, Part A): no `Handler` call for XTVERSION, `CSI 16 t`, OSC 9/777/99/133/1 and `OSC 8 ;` (vt-core answers or handles every one: `tests/query_replies.rs`, `program_replies.rs`, `program_messages.rs`, `agent_events.rs`, `osc8.rs`); `22;1 t` pushes the title (vt-core ignores an icon-only push, `parser/program.rs:26`); SGR 53 dropped, 21 cancel-bold, `38;5;300` dropped, `4:6` underline (vt-core: overline, double underline, index 255, no underline — `sgr.rs:49,57,69`, `parser/colour.rs:64-66`); REP printed four `f`, `ESC Z` identified, `ESC # 8` DECALN (all three new behaviour); DECRQM reported one mode of two; `Processor::new` took 2,097,152 bytes. If your output differs in any line, **stop Part A**: report the difference and skip to Task 3 (Part A adds no code, so nothing needs reverting).

- [ ] **Step 3: `TERMINAL.md` §4.35** — insert the block below, followed by one blank line, immediately before the line `## 5. Known gaps (not bugs, decisions pending)` (`TERMINAL.md:1277`; the line above it is blank and the one above that is the last line of §4.34, ending `` `compact-output.test.ts` (whole-line spinner, separated runs, `maxLines`). ``):

```markdown
### 4.35 The parser rework — roadmap Plan 9
- **Part A: `vte::ansi::Handler` measured, not adopted (2026-09-26).** A
  scratch crate fed vte 0.15's `ansi::Processor` the sequences vt-core relies
  on. XTVERSION (`CSI > 0 q`), `CSI 16 t`, OSC 9/99/777/1/133/7000 and a bare
  `OSC 8 ;` reach no `Handler` method; SGR 53/55 are dropped, SGR 21 becomes
  cancel-bold, `38;5;300` is rejected, `4:6` becomes an underline; DECRQM
  passes one mode; `CSI b` (REP), `ESC Z` (DA1) and `ESC # 8` (DECALN) would
  start doing something, which changes `tests/ref/csi_rep` and
  `decaln_reset`; and `Processor::new` allocates a 2 MiB sync buffer per core
  (`vte-0.15.0/src/ansi.rs:39,261-264`). The `Processor` owns its parser and
  its `Performer` is private (`ansi.rs:425`), so nothing can be handled half
  by `Handler` and half by us. Dispatch stays on `vte::Perform`
  (`crates/vt-core/src/parser/perform.rs`). The `ansi` feature does not need
  `std` (vte's `Cargo.toml`: `ansi = ["log", "cursor-icon", "bitflags"]`), and
  vt-core must keep vte without `std`: the 1,024-byte OSC cap of §4.34 is the
  no-std buffer (`vte-0.15.0/src/lib.rs:46`).
- Guard for the whole plan: `crates/vt-core/tests/parser_goldens.rs` replays
  the 46 `tests/ref` recordings, the 3 Claude Code fixtures and 4 synthetic
  streams (`tests/golden_support/synthetic.rs`) in four configurations
  (renderer: grapheme mode, 4 KiB feeds; renderer with feeds of 1, 3, 7, 64,
  509 and 4,093 bytes in turn; mirror: scalar, no reflow, 20,000 rows /
  256 KiB, cold ring; agent-TUI mode with the odd feeds) and compares a
  digest of rows, styles, cell spans, wrapped flags, blocks, links, cursor,
  alternate screen, modes, title, notifications, agent events, query replies
  and every per-feed `Delta` with `tests/goldens/*.golden`, generated on the
  tree before the rework (`UPDATE_GOLDENS=1`). Regenerate only for a
  deliberate behaviour change, and name it in the commit.
```

- [ ] **Step 4: Survey** (`docs/terminal/2026-09-19-terminal-reference-survey.md`)

Line 73 — replace the whole line starting `| §2.2 | Not done |` with:

```text
| §2.2 | Not pursued | Roadmap Plan 9 (2026-09-26) measured `vte::ansi::Handler`: XTVERSION, `CSI 16 t`, OSC 9/99/777/133/7000 and raw parameters reach no method, SGR 21/53/`38;5;300`/`4:6` decode differently, REP/`ESC Z`/`ESC # 8` start doing something, and `Processor::new` allocates 2 MiB per core; there is no partial adoption (`TERMINAL.md` §4.35). The `ansi` feature does not need `std`. |
```

Line 1297 (the status under the §2.2 heading) — replace the line starting `> **Status: Not done.** \`Parser\` still implements` with:

```text
> **Status: Not pursued.** Roadmap Plan 9 (2026-09-26) — measured with a scratch crate: vte 0.15's `ansi::Processor` cannot express XTVERSION, `CSI 16 t`, OSC 9/99/777/133/7000, a bare `OSC 8 ;`, multi-mode DECRQM or raw parameters (the `trace` feature, the unknown-sequence ring), decodes SGR 21/53/`38;5;300`/`4:6` differently, would start executing REP, `ESC Z` and `ESC # 8` (changing two `tests/ref` screens), and allocates a 2 MiB sync buffer per core (`vte-0.15.0/src/ansi.rs:39,261-264`); its `Performer` is private (`:425`), so no sequence can be handed back. Dispatch stays on `vte::Perform` (`TERMINAL.md` §4.35). The proposal's "`std` is required by `ansi`" is wrong: `ansi = ["log", "cursor-icon", "bitflags"]` builds without `std`.
```

Recount:

```bash
cd "$REPO" && awk -F'|' '/^\| §/ {gsub(/ /,"",$3); print $3}' docs/terminal/2026-09-19-terminal-reference-survey.md | sort | uniq -c
```
Expected: `45 Done`, `1 N/A`, `14 Notdone`, `1 Notneeded`, `8 Notpursued`, `19 Partial` (on `585c0e68d` before this change: 45, 1, 15, 1, 7, 19). In line 50, replace `45 done, 19 partial, 15 not done, 7 not pursued, 1 not needed, 1 n/a` with your counts in the same words (`45 done, 19 partial, 14 not done, 8 not pursued, 1 not needed, 1 n/a`), and append to the end of line 50: ` "Roadmap Plan 9" is the parser-rework plan (\`docs/superpowers/plans/2026-09-26-terminal-plan-9-parser-rework.md\`).`

- [ ] **Step 5: Plain-language doc** (`docs/terminal/2026-09-24-not-done-plain-language.md:128-131`) — replace item 18 (from the line starting `18. **Tidier code for control codes (§2.2).**` through the line ending `from unusual programs.`) with:

```markdown
18. **Tidier code for control codes (§2.2) — tried and dropped (2026-09-26,
    roadmap Plan 9).** The standard library we checked cannot answer the
    questions Claude Code asks at startup, drops program notifications and
    would change how some colours and codes behave, so the terminal keeps its
    own reader. A new safety net now checks that no future change to that
    reader alters anything on screen.
```

- [ ] **Step 6: Gate set G, then commit**

Run G1–G7. No source file changed, so every result must equal Task 0's; if G2 shows `vt_host.wasm` modified, restore it as G2 says (the Part A commit is docs only).

```bash
cd "$REPO" && git add TERMINAL.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/terminal/2026-09-24-not-done-plain-language.md
git commit -m "docs(terminal): Plan 9 Part A — vte::ansi::Handler measured, not adopted (TERMINAL.md §4.35, survey §2.2)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---
### Task 3: Part B — move the print path into `screen/print.rs`

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/screen.rs` (lines 2-3, 9-12, 417-518)
- Create: `packages/terminal/crates/vt-core/src/screen/print.rs`

**Interfaces:**
- Consumes: nothing new.
- Produces: `src/screen/print.rs` holding `ScreenGrid::print` (still `pub`), `previous_cell`, `cell_width_at`, `join_previous`, `attach_zerowidth` (private, verbatim). A child module of `screen`, so it reads `ScreenGrid`'s private fields and private methods (`set`, `mark_dirty`, `raise_max_cursor_row`, `set_row_wrapped`, `phys_start`, `cell_ref`) exactly as `screen/edit.rs` does.

This is a pure move: no behaviour change, so the test for it is the unchanged suite plus the goldens.

- [ ] **Step 1: Check the lines you are about to move**

```bash
cd "$REPO/packages/terminal/crates/vt-core" && sed -n '417p;516,519p' src/screen.rs
```
Expected, exactly:

```text
    pub fn print(&mut self, ch: char, style: CellStyle) {
        self.mark_dirty(row);
    }

    pub fn row_text(&self, row: usize) -> String {
```
If not, stop and report (the base moved).

- [ ] **Step 2: Create `src/screen/print.rs` from those lines, then delete them from `screen.rs`**

```bash
cd "$REPO/packages/terminal/crates/vt-core" && {
  printf 'use unicode_width::UnicodeWidthChar;\n\nuse crate::screen::{Cell, ScreenGrid};\nuse crate::style::CellStyle;\nuse crate::width::{self, WidthMode};\n\nimpl ScreenGrid {\n'
  sed -n '417,517p' src/screen.rs
  printf '}\n'
} > src/screen/print.rs
sed -i.bak '417,518d' src/screen.rs && rm src/screen.rs.bak
```

The resulting `src/screen/print.rs` must be exactly:

```rust
use unicode_width::UnicodeWidthChar;

use crate::screen::{Cell, ScreenGrid};
use crate::style::CellStyle;
use crate::width::{self, WidthMode};

impl ScreenGrid {
    pub fn print(&mut self, ch: char, style: CellStyle) {
        if self.width_mode == WidthMode::Grapheme && self.join_previous(ch, style) {
            return;
        }
        let width = UnicodeWidthChar::width(ch).unwrap_or(0);
        if width == 0 {
            self.attach_zerowidth(ch);
            return;
        }
        if self.pending_wrap || self.col + width > self.cols {
            self.set_row_wrapped(self.row, true);
            self.carriage_return();
            self.line_feed();
        }
        self.raise_max_cursor_row(self.row);
        self.set(self.row, self.col, Cell::new(ch, style));
        for offset in 1..width {
            self.set(self.row, self.col + offset, Cell::new('\0', style));
        }
        self.col += width;
        if self.col >= self.cols {
            self.col = self.cols - 1;
            self.pending_wrap = true;
        }
    }

    fn previous_cell(&self) -> Option<(usize, usize)> {
        let mut col = self.col;
        if !self.pending_wrap {
            col = col.checked_sub(1)?;
        }
        if self
            .cell_ref(self.row, col)
            .is_some_and(|cell| cell.ch == '\0')
        {
            col = col.checked_sub(1)?;
        }
        (self.row < self.rows && col < self.cols).then_some((self.row, col))
    }

    fn cell_width_at(&self, row: usize, col: usize) -> usize {
        1 + (col + 1..self.cols)
            .take_while(|next| {
                self.cell_ref(row, *next)
                    .is_some_and(|cell| cell.ch == '\0')
            })
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

    /// Attaches a zero-width scalar to the cell that owns it. Warp resolves the
    /// same target at `grid/ansi_handler.rs:201-215`: the column before the
    /// cursor unless a wrap is pending, stepping back once more off a
    /// wide-character spacer so the scalar lands on the base cell.
    fn attach_zerowidth(&mut self, ch: char) {
        let mut col = self.col;
        if !self.pending_wrap {
            col = col.saturating_sub(1);
        }
        if self
            .cell_ref(self.row, col)
            .is_some_and(|cell| cell.ch == '\0')
        {
            col = col.saturating_sub(1);
        }
        let row = self.row;
        self.raise_max_cursor_row(row);
        if row >= self.rows || col >= self.cols {
            return;
        }
        let index = self.phys_start(row) + col;
        self.cells[index].append_scalar(ch);
        self.mark_dirty(row);
    }
}
```

- [ ] **Step 3: Fix `screen.rs`'s module list and imports**

In `packages/terminal/crates/vt-core/src/screen.rs`, replace (lines 2-3)

```rust
mod edit;
mod resize;
```
with
```rust
mod edit;
mod print;
mod resize;
```
and replace (lines 9-12)
```rust
use unicode_width::UnicodeWidthChar;

use crate::style::{CellStyle, StyleCode};
use crate::width::{self, WidthMode};
```
with
```rust
use crate::style::{CellStyle, StyleCode};
use crate::width::WidthMode;
```

- [ ] **Step 4: Verify**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
wc -l crates/vt-core/src/screen.rs crates/vt-core/src/screen/print.rs
```
Expected: `Finished …`; only `rust-done`; `444 …screen.rs`, `109 …print.rs`.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-core/src/screen.rs packages/terminal/crates/vt-core/src/screen/print.rs
git commit -m "refactor(vt-core): move the print path into screen/print.rs" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Part B — printable runs, the ASCII fast path, an allocation-free join

**Files:**
- Create: `packages/terminal/crates/vt-core/tests/print_run.rs`
- Modify (replace whole file): `packages/terminal/crates/vt-core/src/screen/print.rs`, `packages/terminal/crates/vt-core/src/parser/perform.rs`
- Modify: `packages/terminal/crates/vt-core/src/screen.rs` (`Cell`, before `is_blank`, line 68), `src/width.rs:51-52`, `src/parser.rs:69,108`, `src/lib.rs:350-353`

**Interfaces:**
- Consumes: Task 3's `src/screen/print.rs`.
- Produces: `pub fn ScreenGrid::print_ascii_run(&mut self, run: &[u8], style: CellStyle)` (precondition: every byte in `0x20..=0x7e`), `pub(crate) fn Cell::is_plain_ascii(&self) -> bool`, `pub(crate) fn Parser::flush_run(&mut self)` and the field `Parser.run: Vec<u8>` (Task 5 adds a field after it and rewrites `perform.rs` again).

- [ ] **Step 1: Write the tests**

Create `packages/terminal/crates/vt-core/tests/print_run.rs`:

```rust
use proptest::prelude::*;
use vt_core::testing::ScreenGrid;
use vt_core::{CellStyle, StyleCode, TerminalCore, WidthMode};

const SPECIALS: [&str; 10] = [
    "\u{4e2d}",
    "e\u{301}",
    "\u{1f44d}\u{1f3fd}",
    "\u{1f468}\u{200d}\u{1f469}",
    "\u{600}",
    "\u{7f}",
    "\u{fe0f}",
    "\u{1f1ea}\u{1f1ec}",
    "\u{200b}",
    "\u{1100}\u{1161}",
];

fn grid(rows: usize, cols: usize, mode: WidthMode) -> ScreenGrid {
    let mut grid = ScreenGrid::new(rows, cols);
    grid.set_width_mode(mode);
    grid
}

#[derive(Debug, PartialEq)]
struct GridState {
    cells: Vec<String>,
    cursor: (usize, usize),
    wrapped: Vec<bool>,
    content_rows: usize,
    dirty: Vec<usize>,
}

fn state(grid: &mut ScreenGrid) -> GridState {
    let mut cells = Vec::new();
    let mut buffer = [0u8; 4];
    for row in 0..grid.rows() {
        for col in 0..grid.cols() {
            let cell = grid.cell(row, col);
            cells.push(format!("{}|{:?}", cell.text(&mut buffer), cell.style));
        }
    }
    GridState {
        cells,
        cursor: grid.cursor(),
        wrapped: (0..grid.rows()).map(|row| grid.row_wrapped(row)).collect(),
        content_rows: grid.content_rows(),
        dirty: grid.take_dirty(),
    }
}

fn per_char(grid: &mut ScreenGrid, text: &str, style: CellStyle) {
    for ch in text.chars() {
        grid.print(ch, style);
    }
}

fn by_runs(grid: &mut ScreenGrid, text: &str, style: CellStyle) {
    let mut run = Vec::new();
    for ch in text.chars() {
        if matches!(ch, ' '..='~') {
            run.push(ch as u8);
            continue;
        }
        grid.print_ascii_run(&run, style);
        run.clear();
        grid.print(ch, style);
    }
    grid.print_ascii_run(&run, style);
}

fn segment() -> impl Strategy<Value = String> {
    prop_oneof![
        "[ -~]{0,30}",
        (0..SPECIALS.len()).prop_map(|index| SPECIALS[index].to_string()),
    ]
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 512, ..ProptestConfig::default() })]

    #[test]
    fn an_ascii_run_lands_exactly_where_printing_it_one_char_at_a_time_does(
        rows in 1usize..6,
        cols in 1usize..12,
        graphemes in any::<bool>(),
        start_col in 0usize..12,
        segments in prop::collection::vec(segment(), 1..12),
    ) {
        let mode = if graphemes { WidthMode::Grapheme } else { WidthMode::Scalar };
        let text: String = segments.concat();
        let style = CellStyle::new(StyleCode::ansi(2), StyleCode::DEFAULT_BACKGROUND);
        let mut one = grid(rows, cols, mode);
        let mut runs = grid(rows, cols, mode);
        one.move_to(0, start_col);
        runs.move_to(0, start_col);
        per_char(&mut one, &text, style);
        by_runs(&mut runs, &text, style);
        prop_assert_eq!(state(&mut one), state(&mut runs));
    }
}

fn screen_text(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().expect("snapshot");
    (0..snapshot.row_count())
        .map(|row| snapshot.row_text(row).to_string())
        .collect()
}

fn core(cols: usize, graphemes: bool) -> TerminalCore {
    let mut core = TerminalCore::new(cols, 100).expect("core");
    core.resize(cols, 5);
    core.set_grapheme_clusters(graphemes);
    core
}

#[test]
fn an_ascii_letter_after_a_prepend_mark_joins_it_and_the_next_letter_does_not() {
    let mut core = core(10, true);
    core.feed("\u{600}ab".as_bytes());
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "\u{600}ab");
    let spans: Vec<(u32, u32, u8)> = snapshot
        .row_cell_spans(0)
        .iter()
        .map(|span| (span.start, span.end, span.width))
        .collect();
    assert_eq!(spans, vec![(0, 3, 2)]);
    assert_eq!(snapshot.cursor_col, 3);
}

#[test]
fn a_run_split_at_every_byte_matches_the_run_fed_whole() {
    let input = "plain \x1b[31mred\x1b[0m wide \u{4e2d}\u{6587} e\u{301} tail that wraps past the edge\r\nnext";
    for graphemes in [false, true] {
        let mut whole = core(12, graphemes);
        whole.feed(input.as_bytes());
        let mut split = core(12, graphemes);
        for byte in input.as_bytes() {
            split.feed(std::slice::from_ref(byte));
        }
        assert_eq!(screen_text(&whole), screen_text(&split));
        let (a, b) = (whole.snapshot().expect("a"), split.snapshot().expect("b"));
        assert_eq!((a.cursor_row, a.cursor_col), (b.cursor_row, b.cursor_col));
        for row in 0..a.row_count() {
            assert_eq!(a.row_style_pairs(row), b.row_style_pairs(row));
            assert_eq!(a.row_wrapped(row), b.row_wrapped(row));
        }
    }
}

#[test]
fn a_run_takes_the_style_in_force_when_it_was_printed() {
    let mut core = core(20, true);
    core.feed(b"ab\x1b[1mcd\x1b[0mef");
    let snapshot = core.snapshot().expect("snapshot");
    let pairs = snapshot.row_style_pairs(0);
    assert_eq!(pairs.len(), 3);
    assert_eq!(pairs[0].0, 2);
    assert!(pairs[1].1.fg.is_bold());
    assert_eq!(pairs[1].0, 4);
    assert!(!pairs[2].1.fg.is_bold());
}

#[test]
fn a_run_that_reaches_the_last_column_wraps_only_when_the_next_character_arrives() {
    let mut core = core(4, false);
    core.feed(b"abcd");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(screen_text(&core), vec!["abcd".to_string()]);
    assert_eq!((snapshot.cursor_row, snapshot.cursor_col), (0, 3));
    core.feed(b"e");
    assert_eq!(
        screen_text(&core),
        vec!["abcd".to_string(), "e".to_string()]
    );
    assert!(core.snapshot().expect("snapshot").row_wrapped(0));
}

#[test]
fn invalid_utf8_inside_a_run_prints_a_replacement_character() {
    let mut core = core(20, true);
    core.feed(b"ab\xffcd");
    assert_eq!(screen_text(&core), vec!["ab\u{fffd}cd".to_string()]);
    let mut split = self::core(20, true);
    split.feed(b"ab\xe4\xb8");
    split.feed(b"\xadcd");
    assert_eq!(screen_text(&split), vec!["ab\u{4e2d}cd".to_string()]);
}

#[test]
fn a_delete_byte_inside_a_run_is_still_not_a_cell() {
    let mut core = core(20, false);
    core.feed(b"ab\x7fcd");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.cursor_col, 4);
}

#[test]
fn a_run_right_before_a_boundary_mark_lands_in_the_block_the_mark_closes() {
    let mut core = core(20, false);
    core.feed(b"hello\x1b]7000;v=1;boundary=0\x07next");
    assert_eq!(
        screen_text(&core),
        vec!["hello".to_string(), "next".to_string()]
    );
    let snapshot = core.snapshot().expect("snapshot");
    let blocks: Vec<(u32, u32)> = snapshot
        .blocks
        .iter()
        .map(|block| (block.first_row, block.row_count))
        .collect();
    assert_eq!(blocks, vec![(0, 1), (1, 1)]);
}

#[test]
fn a_run_right_before_the_alternate_screen_opens_stays_on_the_primary_screen() {
    let mut core = core(20, false);
    core.feed(b"abc\x1b[?1049hdef");
    assert_eq!(
        core.alt_grid()
            .map(|grid| grid.row_text(0).trim_end().to_string()),
        Some("def".to_string())
    );
    assert_eq!(core.snapshot().expect("snapshot").row_text(0), "abc");
    core.feed(b"\x1b[?1049lghi");
    assert_eq!(screen_text(&core), vec!["abcghi".to_string()]);
}
```

- [ ] **Step 2: Run them — they must fail to compile**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test print_run 2>&1 | grep -E "^error" | head -3
```
Expected: `error[E0599]: no method named \`print_ascii_run\` found for mutable reference \`&mut AltGrid\` in the current scope` (twice; `AltGrid` is `ScreenGrid`'s public alias). The eight tests that use only `TerminalCore` pass on the unmodified tree too — they pin today's behaviour; the proptest is the one that needs the new method.

- [ ] **Step 3: Implement**

Replace the whole of `packages/terminal/crates/vt-core/src/screen/print.rs` with:

```rust
use unicode_width::UnicodeWidthChar;

use crate::screen::{Cell, ScreenGrid};
use crate::style::CellStyle;
use crate::width::{self, WidthMode};

fn printable_ascii(ch: char) -> bool {
    matches!(ch, ' '..='~')
}

impl ScreenGrid {
    pub fn print(&mut self, ch: char, style: CellStyle) {
        if printable_ascii(ch) && !self.pending_wrap && self.ascii_starts_a_cluster() {
            self.put_ascii(ch, style);
            return;
        }
        if self.width_mode == WidthMode::Grapheme && self.join_previous(ch, style) {
            return;
        }
        let width = UnicodeWidthChar::width(ch).unwrap_or(0);
        if width == 0 {
            self.attach_zerowidth(ch);
            return;
        }
        if self.pending_wrap || self.col + width > self.cols {
            self.set_row_wrapped(self.row, true);
            self.carriage_return();
            self.line_feed();
        }
        self.raise_max_cursor_row(self.row);
        self.set(self.row, self.col, Cell::new(ch, style));
        for offset in 1..width {
            self.set(self.row, self.col + offset, Cell::new('\0', style));
        }
        self.col += width;
        if self.col >= self.cols {
            self.col = self.cols - 1;
            self.pending_wrap = true;
        }
    }

    pub fn print_ascii_run(&mut self, run: &[u8], style: CellStyle) {
        let Some((first, rest)) = run.split_first() else {
            return;
        };
        self.print(char::from(*first), style);
        let mut at = 0;
        while at < rest.len() {
            if self.pending_wrap {
                self.set_row_wrapped(self.row, true);
                self.carriage_return();
                self.line_feed();
            }
            let row = self.row;
            self.raise_max_cursor_row(row);
            let take = (self.cols - self.col).min(rest.len() - at);
            let start = self.phys_start(row) + self.col;
            for (cell, byte) in self.cells[start..start + take]
                .iter_mut()
                .zip(&rest[at..at + take])
            {
                *cell = Cell::new(char::from(*byte), style);
            }
            self.col += take;
            at += take;
            if self.col == self.cols {
                self.set_row_wrapped(row, false);
                self.col = self.cols - 1;
                self.pending_wrap = true;
            }
            self.mark_dirty(row);
        }
    }

    fn put_ascii(&mut self, ch: char, style: CellStyle) {
        let row = self.row;
        self.raise_max_cursor_row(row);
        let index = self.phys_start(row) + self.col;
        self.cells[index] = Cell::new(ch, style);
        if self.col + 1 == self.cols {
            self.set_row_wrapped(row, false);
            self.pending_wrap = true;
        } else {
            self.col += 1;
        }
        self.mark_dirty(row);
    }

    fn ascii_starts_a_cluster(&self) -> bool {
        if self.width_mode == WidthMode::Scalar {
            return true;
        }
        match self.previous_cell() {
            None => true,
            Some((row, col)) => self.cells[self.phys_start(row) + col].is_plain_ascii(),
        }
    }

    fn previous_cell(&self) -> Option<(usize, usize)> {
        let mut col = self.col;
        if !self.pending_wrap {
            col = col.checked_sub(1)?;
        }
        if self
            .cell_ref(self.row, col)
            .is_some_and(|cell| cell.ch == '\0')
        {
            col = col.checked_sub(1)?;
        }
        (self.row < self.rows && col < self.cols).then_some((self.row, col))
    }

    fn cell_width_at(&self, row: usize, col: usize) -> usize {
        1 + (col + 1..self.cols)
            .take_while(|next| {
                self.cell_ref(row, *next)
                    .is_some_and(|cell| cell.ch == '\0')
            })
            .count()
    }

    fn join_previous(&mut self, ch: char, style: CellStyle) -> bool {
        let Some((row, col)) = self.previous_cell() else {
            return false;
        };
        let index = self.phys_start(row) + col;
        let mut buffer = [0u8; 4];
        if !width::joins_previous(self.cells[index].text(&mut buffer), ch) {
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

    /// Attaches a zero-width scalar to the cell that owns it. Warp resolves the
    /// same target at `grid/ansi_handler.rs:201-215`: the column before the
    /// cursor unless a wrap is pending, stepping back once more off a
    /// wide-character spacer so the scalar lands on the base cell.
    fn attach_zerowidth(&mut self, ch: char) {
        let mut col = self.col;
        if !self.pending_wrap {
            col = col.saturating_sub(1);
        }
        if self
            .cell_ref(self.row, col)
            .is_some_and(|cell| cell.ch == '\0')
        {
            col = col.saturating_sub(1);
        }
        let row = self.row;
        self.raise_max_cursor_row(row);
        if row >= self.rows || col >= self.cols {
            return;
        }
        let index = self.phys_start(row) + col;
        self.cells[index].append_scalar(ch);
        self.mark_dirty(row);
    }
}
```

In `packages/terminal/crates/vt-core/src/screen.rs`, inside `impl Cell`, replace (line 68)

```rust
    pub fn is_blank(&self) -> bool {
```
with
```rust
    pub(crate) fn is_plain_ascii(&self) -> bool {
        self.ch.is_ascii() && self.extra.is_none()
    }

    pub fn is_blank(&self) -> bool {
```

In `packages/terminal/crates/vt-core/src/width.rs`, inside `joins_previous`, replace (lines 51-52)

```rust
    let mut joined = String::with_capacity(previous.len() + ch.len_utf8());
    joined.push_str(previous);
```
with
```rust
    let total = previous.len() + ch.len_utf8();
    let mut stack = [0u8; 64];
    if total <= stack.len() {
        stack[..previous.len()].copy_from_slice(previous.as_bytes());
        ch.encode_utf8(&mut stack[previous.len()..total]);
        let joined = std::str::from_utf8(&stack[..total]).expect("two strs joined are utf-8");
        return joined.graphemes(true).nth(1).is_none();
    }
    let mut joined = String::with_capacity(total);
    joined.push_str(previous);
```

In `packages/terminal/crates/vt-core/src/parser.rs`, replace (lines 69-70)

```rust
    committed_rows: u64,
    #[cfg(feature = "trace")]
```
with
```rust
    committed_rows: u64,
    run: Vec<u8>,
    #[cfg(feature = "trace")]
```
and replace (lines 108-109)
```rust
            committed_rows: 0,
            #[cfg(feature = "trace")]
```
with
```rust
            committed_rows: 0,
            run: Vec::new(),
            #[cfg(feature = "trace")]
```

In `packages/terminal/crates/vt-core/src/lib.rs`, at the end of `advance_vte`, replace (lines 350-353)

```rust
            self.vte.advance(&mut self.parser, bytes);
            self.fed_total += bytes.len() as u64;
        }
    }
```
with
```rust
            self.vte.advance(&mut self.parser, bytes);
            self.fed_total += bytes.len() as u64;
        }
        self.parser.flush_run();
    }
```

Replace the whole of `packages/terminal/crates/vt-core/src/parser/perform.rs` with:

```rust
use vte::{Params, Perform};

use super::Parser;

impl Parser {
    pub(crate) fn flush_run(&mut self) {
        if self.run.is_empty() {
            return;
        }
        let style = self.pending_style.resolved();
        let run = std::mem::take(&mut self.run);
        self.active_screen_mut().print_ascii_run(&run, style);
        self.run = run;
        self.run.clear();
    }
}

impl Perform for Parser {
    fn print(&mut self, c: char) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Print(c));
        if matches!(c, ' '..='~') {
            self.run.push(c as u8);
            return;
        }
        self.flush_run();
        let style = self.pending_style.resolved();
        self.active_screen_mut().print(c, style);
    }

    fn execute(&mut self, byte: u8) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Execute(byte));
        self.flush_run();
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
        self.flush_run();
        if c == 'm' && intermediates.is_empty() {
            self.apply_sgr(params);
            return;
        }
        if intermediates == b"?$" && c == 'p' {
            self.answer_decrqm(params);
            return;
        }
        if intermediates.is_empty()
            && c == 'c'
            && params
                .iter()
                .next()
                .and_then(|g| g.first().copied())
                .unwrap_or(0)
                == 0
        {
            self.push_reply(b"\x1b[?62;22c");
            return;
        }
        if intermediates == b">"
            && c == 'q'
            && params
                .iter()
                .next()
                .and_then(|g| g.first().copied())
                .unwrap_or(0)
                == 0
        {
            self.answer_xtversion();
            return;
        }
        if intermediates.is_empty() && c == 't' {
            self.xtwinops(params);
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
        self.trace.record(crate::trace::TraceAction::Esc {
            intermediates: intermediates.to_vec(),
            byte,
        });
        #[cfg(not(feature = "trace"))]
        let _ = intermediates;
        self.flush_run();
        self.active_screen_mut().esc(byte);
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], bell_terminated: bool) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Osc(
            params.iter().map(|p| p.to_vec()).collect(),
        ));
        self.flush_run();
        match crate::program::OscKind::of(params) {
            crate::program::OscKind::Hyperlink => {
                let id = crate::hyperlink::parse_osc8(&params[1..])
                    .and_then(|link| self.hyperlinks.intern(link));
                self.pending_style.link = id.unwrap_or(0);
            }
            crate::program::OscKind::Other | crate::program::OscKind::IconName => {}
            _ => self.program_osc(params, bell_terminated),
        }
    }
}
```

- [ ] **Step 4: Verify — tests, goldens, the whole suite**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo test -p vt-core --test print_run 2>&1 | grep "test result"
cargo test --release -p vt-core --test parser_goldens 2>&1 | grep "test result"
cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
cargo test -p vt-core --features trace --test integrity 2>&1 | grep "test result"
wc -l crates/vt-core/src/screen.rs crates/vt-core/src/screen/print.rs crates/vt-core/src/parser.rs crates/vt-core/src/parser/perform.rs crates/vt-core/src/lib.rs
```
Expected: `Finished …`; `test result: ok. 9 passed`; `test result: ok. 1 passed`; only `rust-done`; `test result: ok. 8 passed` (the `trace` build still records one `print` per character); line counts `448`, `173`, `545`, `130`, `591`. If the goldens fail, the message names the recording and the first differing digest line — the fast path changed behaviour; fix the code (never the golden). A proptest failure writes `crates/vt-core/tests/print_run.proptest-regressions`; do not commit that file.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-core/src/screen/print.rs packages/terminal/crates/vt-core/src/screen.rs \
  packages/terminal/crates/vt-core/src/width.rs packages/terminal/crates/vt-core/src/parser.rs \
  packages/terminal/crates/vt-core/src/lib.rs packages/terminal/crates/vt-core/src/parser/perform.rs \
  packages/terminal/crates/vt-core/tests/print_run.rs
git commit -m "perf(vt-core): print printable ASCII runs a row segment at a time; the grapheme join no longer allocates" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Part B — the unknown-sequence ring

**Files:**
- Create: `packages/terminal/crates/vt-core/src/parser/unknown.rs`, `packages/terminal/crates/vt-core/tests/unknown_sequences.rs`
- Modify (replace whole file): `packages/terminal/crates/vt-core/src/parser/perform.rs`
- Modify: `packages/terminal/crates/vt-core/src/parser.rs:6-8,70-71,110-111`, `src/lib.rs:56`, `src/parser/program.rs:21,27-28,33-38`, `src/screen/dispatch.rs:15-26,67-71`, `packages/terminal/crates/vt-wasm/src/program.rs:43-46`, `packages/terminal/crates/vt-wasm/tests/program_exports.rs` (append)

**Interfaces:**
- Consumes: Task 4's `Parser.run`, `Parser::flush_run`.
- Produces: `pub struct vt_core::UnknownSequence { pub text: String, pub count: u32 }`, `pub const vt_core::UNKNOWN_SEQUENCES_CAP: usize = 64`, `pub const vt_core::UNKNOWN_TEXT_BYTES: usize = 48`, `TerminalCore::unknown_sequences(&self) -> Vec<UnknownSequence>` (oldest first), `TerminalCore::clear_unknown_sequences(&mut self)`, `WasmTerminalCore::unknown_sequences(&self) -> Vec<String>` (`"<count> <text>"`); `ScreenGrid::csi` and `Parser::xtwinops` now return `bool` (handled).

- [ ] **Step 1: Write the tests**

Create `packages/terminal/crates/vt-core/tests/unknown_sequences.rs`:

```rust
use std::path::PathBuf;

use vt_core::{TerminalCore, UnknownSequence, UNKNOWN_SEQUENCES_CAP, UNKNOWN_TEXT_BYTES};

fn core() -> TerminalCore {
    let mut core = TerminalCore::new(40, 100).expect("core");
    core.resize(40, 10);
    core
}

fn texts(core: &TerminalCore) -> Vec<(String, u32)> {
    core.unknown_sequences()
        .into_iter()
        .map(|UnknownSequence { text, count }| (text, count))
        .collect()
}

#[test]
fn sequences_the_terminal_handles_are_not_recorded() {
    let mut core = core();
    core.feed(
        b"plain\x1b[1;31;4:3;58;5;9mstyled\x1b[0m\r\n\x1b[2;3H\x1b[K\x1b[2J\x1b[5@\x1b[3P\x1b[4X",
    );
    core.feed(b"\x1b[A\x1b[B\x1b[C\x1b[D\x1b[E\x1b[F\x1b[G\x1b[d\x1b[2L\x1b[M\x1b[S\x1b[T\x1b[2;5r\x1b[r\x1b[s\x1b[u");
    core.feed(b"\x1b[c\x1b[>q\x1b[?2026$p\x1b[14t\x1b[16t\x1b[18t\x1b[22;0t\x1b[23;0t\x1b[22;1t");
    core.feed(
        b"\x1b[?1h\x1b[?25l\x1b[?25h\x1b[?1000;1002;1003;1004;1006;2004h\x1b[?2048h\x1b[?2048l",
    );
    core.feed(b"\x1b[?2026h\x1b[?2026l\x1b[?1049h\x1b[?1049l\x1b7\x1b8\x1bD\x1bE\x1bM\x1bc");
    core.feed(b"\x1b]0;title\x07\x1b]2;title\x1b\\\x1b]1;icon\x07\x1b]8;;https://a.example\x1b\\x\x1b]8;;\x1b\\");
    core.feed(b"\x1b]9;note\x07\x1b]777;notify;t;b\x07\x1b]99;;k\x1b\\\x1b]10;?\x07\x1b]11;?\x07\x1b]22;text\x07");
    core.feed(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]7;file://h/tmp\x07\x1b]7000;v=1;cmd=ls\x07");
    assert_eq!(texts(&core), Vec::<(String, u32)>::new());
}

#[test]
fn an_unhandled_private_sequence_is_recorded_with_how_often_it_came() {
    let mut core = core();
    core.feed(b"\x1b[>1u\x1b[?u\x1b[>1u\x1b[>4;2m");
    assert_eq!(
        texts(&core),
        vec![
            ("CSI ?0u".to_string(), 1),
            ("CSI >1u".to_string(), 2),
            ("CSI >4;2m".to_string(), 1),
        ]
    );
}

#[test]
fn a_private_mode_set_is_recorded_only_when_it_names_an_unknown_mode() {
    let mut core = core();
    core.feed(b"\x1b[?25;1h\x1b[?25;7727h\x1b[?47l");
    assert_eq!(
        texts(&core),
        vec![
            ("CSI ?25;7727h".to_string(), 1),
            ("CSI ?47l".to_string(), 1)
        ]
    );
}

#[test]
fn escape_dcs_and_other_osc_sequences_are_recorded_without_their_payload() {
    let mut core = core();
    core.feed(b"\x1b(0\x1b#8\x1b=\x1bP+q544e\x1b\\\x1b]52;c;U0VDUkVU\x07\x1b]1337;SetMark\x07");
    let got = texts(&core);
    assert_eq!(
        got,
        vec![
            ("ESC (0".to_string(), 1),
            ("ESC #8".to_string(), 1),
            ("ESC =".to_string(), 1),
            ("DCS +0q".to_string(), 1),
            ("OSC 52".to_string(), 1),
            ("OSC 1337".to_string(), 1),
        ]
    );
    assert!(got.iter().all(|(text, _)| !text.contains("U0VD")));
}

#[test]
fn a_sequence_split_byte_by_byte_is_recorded_once() {
    let mut core = core();
    for byte in b"ab\x1b[>1ucd\x1b]52;c;x\x07" {
        core.feed(std::slice::from_ref(byte));
    }
    assert_eq!(
        texts(&core),
        vec![("CSI >1u".to_string(), 1), ("OSC 52".to_string(), 1)]
    );
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "abcd");
}

#[test]
fn the_ring_keeps_the_newest_distinct_sequences_up_to_its_cap() {
    let mut core = core();
    for index in 0..UNKNOWN_SEQUENCES_CAP + 6 {
        core.feed(format!("\x1b[>{index}u").as_bytes());
    }
    let got = texts(&core);
    assert_eq!(got.len(), UNKNOWN_SEQUENCES_CAP);
    assert_eq!(got[0].0, "CSI >6u");
    assert_eq!(
        got.last().map(|entry| entry.0.clone()),
        Some(format!("CSI >{}u", UNKNOWN_SEQUENCES_CAP + 5))
    );
    core.feed(b"\x1b[>6u");
    assert_eq!(texts(&core).last(), Some(&("CSI >6u".to_string(), 2)));
}

#[test]
fn an_oversized_sequence_is_cut_and_marked_as_overflowing() {
    let mut core = core();
    let mut long = b"\x1b[".to_vec();
    for index in 0..40 {
        long.extend_from_slice(format!("{index};").as_bytes());
    }
    long.extend_from_slice(b"99z");
    core.feed(&long);
    let got = texts(&core);
    assert_eq!(got.len(), 1);
    assert!(got[0].0.starts_with("overflow CSI 0;1;2;"), "{}", got[0].0);
    assert_eq!(got[0].0.len(), UNKNOWN_TEXT_BYTES);
}

#[test]
fn clearing_empties_the_ring() {
    let mut core = core();
    core.feed(b"\x1b[>1u");
    core.clear_unknown_sequences();
    assert!(core.unknown_sequences().is_empty());
}

#[test]
fn the_claude_code_recordings_leave_eight_unhandled_sequences() {
    let fixtures =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../bench/agent-session/fixtures");
    let mut seen = Vec::new();
    for name in [
        "claude-spinner-10s",
        "claude-markdown-reply",
        "claude-long-50k",
    ] {
        let bytes = std::fs::read(fixtures.join(name).join("recording")).expect("recording");
        let mut core = TerminalCore::new(120, 200_000).expect("core");
        core.resize(120, 40);
        core.feed(&bytes);
        for entry in core.unknown_sequences() {
            if !seen.contains(&entry.text) {
                seen.push(entry.text);
            }
        }
    }
    seen.sort();
    assert_eq!(
        seen,
        vec![
            "CSI <0u",
            "CSI >4;2m",
            "CSI >4m",
            "CSI >5u",
            "CSI ?0u",
            "CSI ?2031h",
            "CSI ?2031l",
            "ESC (B",
        ]
    );
}
```

Append to `packages/terminal/crates/vt-wasm/tests/program_exports.rs` (after its last test, which ends with `assert_eq!(core.live_output_bytes(), bytes.len() as f64);` and `}`):

```rust

#[test]
fn the_wasm_core_lists_unknown_sequences_with_their_counts() {
    let Ok(mut core) = WasmTerminalCore::new(80, 1_000, 1 << 20) else {
        panic!("core");
    };
    assert!(core.feed(b"\x1b[>1u\x1b[>1u\x1b(0\x1b[31m", 0.0).is_ok());
    assert_eq!(core.unknown_sequences(), vec!["2 CSI >1u", "1 ESC (0"]);
}
```

- [ ] **Step 2: Run them — they must fail to compile**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test unknown_sequences 2>&1 | grep -E "^error" | head -2
```
Expected: `error[E0432]: unresolved imports \`vt_core::UnknownSequence\`, \`vt_core::UNKNOWN_SEQUENCES_CAP\`, \`vt_core::UNKNOWN_TEXT_BYTES\`` and two `E0599` lines for `unknown_sequences` / `clear_unknown_sequences`.

- [ ] **Step 3: Implement**

Create `packages/terminal/crates/vt-core/src/parser/unknown.rs`:

```rust
use std::collections::VecDeque;
use std::fmt::Write;

use vte::Params;

use super::Parser;

pub const UNKNOWN_SEQUENCES_CAP: usize = 64;
pub const UNKNOWN_TEXT_BYTES: usize = 48;
const OSC_PREFIX_BYTES: usize = 16;
const KNOWN_PRIVATE_MODES: [u16; 11] =
    [1, 25, 1000, 1002, 1003, 1004, 1006, 1049, 2004, 2026, 2048];
const KNOWN_ESC_FINALS: &[u8] = b"78DEMc\\";
const MARK_OSCS: [&[u8]; 3] = [b"7", b"133", b"7000"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnknownSequence {
    pub text: String,
    pub count: u32,
}

#[derive(Debug, Default)]
pub(crate) struct UnknownRing {
    entries: VecDeque<UnknownSequence>,
}

impl UnknownRing {
    fn note(&mut self, text: String) {
        if let Some(index) = self.entries.iter().position(|entry| entry.text == text) {
            if let Some(mut entry) = self.entries.remove(index) {
                entry.count = entry.count.saturating_add(1);
                self.entries.push_back(entry);
            }
            return;
        }
        if self.entries.len() == UNKNOWN_SEQUENCES_CAP {
            self.entries.pop_front();
        }
        self.entries.push_back(UnknownSequence { text, count: 1 });
    }
}

pub(crate) fn private_modes_known(params: &Params) -> bool {
    params.iter().all(|group| {
        group
            .first()
            .is_none_or(|mode| KNOWN_PRIVATE_MODES.contains(mode))
    })
}

fn capped(mut text: String) -> String {
    if text.len() > UNKNOWN_TEXT_BYTES {
        let mut end = UNKNOWN_TEXT_BYTES;
        while !text.is_char_boundary(end) {
            end -= 1;
        }
        text.truncate(end);
    }
    text
}

fn sequence_text(
    kind: &str,
    params: &Params,
    intermediates: &[u8],
    ignore: bool,
    action: char,
) -> String {
    let mut text = String::new();
    if ignore {
        text.push_str("overflow ");
    }
    text.push_str(kind);
    text.push(' ');
    text.extend(intermediates.iter().map(|byte| char::from(*byte)));
    for (index, group) in params.iter().enumerate() {
        if index > 0 {
            text.push(';');
        }
        for (sub, value) in group.iter().enumerate() {
            if sub > 0 {
                text.push(':');
            }
            let _ = write!(text, "{value}");
        }
    }
    text.push(action);
    capped(text)
}

impl Parser {
    pub(crate) fn note_unknown_csi(
        &mut self,
        params: &Params,
        intermediates: &[u8],
        ignore: bool,
        action: char,
    ) {
        self.unknown
            .note(sequence_text("CSI", params, intermediates, ignore, action));
    }

    pub(crate) fn note_unknown_dcs(
        &mut self,
        params: &Params,
        intermediates: &[u8],
        ignore: bool,
        action: char,
    ) {
        self.unknown
            .note(sequence_text("DCS", params, intermediates, ignore, action));
    }

    pub(crate) fn note_esc(&mut self, intermediates: &[u8], byte: u8) {
        if intermediates.is_empty() && KNOWN_ESC_FINALS.contains(&byte) {
            return;
        }
        let mut text = String::from("ESC ");
        text.extend(intermediates.iter().map(|byte| char::from(*byte)));
        text.push(char::from(byte));
        self.unknown.note(capped(text));
    }

    pub(crate) fn note_other_osc(&mut self, params: &[&[u8]]) {
        let first = params.first().copied().unwrap_or_default();
        if MARK_OSCS.contains(&first) {
            return;
        }
        let prefix = &first[..first.len().min(OSC_PREFIX_BYTES)];
        self.unknown
            .note(capped(format!("OSC {}", String::from_utf8_lossy(prefix))));
    }
}

impl crate::TerminalCore {
    pub fn unknown_sequences(&self) -> Vec<UnknownSequence> {
        self.parser.unknown.entries.iter().cloned().collect()
    }

    pub fn clear_unknown_sequences(&mut self) {
        self.parser.unknown.entries.clear();
    }
}
```

In `packages/terminal/crates/vt-core/src/parser.rs`, replace (lines 6-8)

```rust
mod program;

pub(crate) use colour::read_extended_colour;
```
with
```rust
mod program;
mod unknown;

pub(crate) use colour::read_extended_colour;
pub use unknown::{UnknownSequence, UNKNOWN_SEQUENCES_CAP, UNKNOWN_TEXT_BYTES};
```
then replace (lines 70-71 in the Task 4 file, 72-73 after the replacement above)
```rust
    run: Vec<u8>,
    #[cfg(feature = "trace")]
```
with
```rust
    run: Vec<u8>,
    unknown: unknown::UnknownRing,
    #[cfg(feature = "trace")]
```
and replace
```rust
            run: Vec::new(),
            #[cfg(feature = "trace")]
```
with
```rust
            run: Vec::new(),
            unknown: unknown::UnknownRing::default(),
            #[cfg(feature = "trace")]
```

In `packages/terminal/crates/vt-core/src/lib.rs`, replace (line 56)

```rust
pub use parser::{HistoryBlock, HistoryRow};
```
with
```rust
pub use parser::{
    HistoryBlock, HistoryRow, UnknownSequence, UNKNOWN_SEQUENCES_CAP, UNKNOWN_TEXT_BYTES,
};
```

In `packages/terminal/crates/vt-core/src/parser/program.rs`, replace (line 21)

```rust
    pub(crate) fn xtwinops(&mut self, params: &Params) {
```
with
```rust
    pub(crate) fn xtwinops(&mut self, params: &Params) -> bool {
```
replace (lines 27-28)
```rust
            23 if which != 1 => self.program.pop_title(),
            14 | 16 | 18 => {
```
with
```rust
            23 if which != 1 => self.program.pop_title(),
            22 | 23 => {}
            14 | 16 | 18 => {
```
and replace (lines 33-38 in the unedited file, 34-39 after the replacement above)
```rust
                    self.push_reply(&reply);
                }
            }
            _ => {}
        }
    }
```
with
```rust
                    self.push_reply(&reply);
                }
            }
            _ => return false,
        }
        true
    }
```

In `packages/terminal/crates/vt-core/src/screen/dispatch.rs`, replace (lines 15-26)

```rust
    pub(crate) fn csi(&mut self, params: &Params, intermediates: &[u8], c: char) {
        if intermediates.first() == Some(&b'?') {
            match (param(params, 0, 0), c) {
                (25, 'h') => self.set_cursor_visible(true),
                (25, 'l') => self.set_cursor_visible(false),
                _ => {}
            }
            return;
        }
        if !intermediates.is_empty() {
            return;
        }
```
with
```rust
    pub(crate) fn csi(&mut self, params: &Params, intermediates: &[u8], c: char) -> bool {
        if intermediates.first() == Some(&b'?') {
            match (param(params, 0, 0), c) {
                (25, 'h') => self.set_cursor_visible(true),
                (25, 'l') => self.set_cursor_visible(false),
                _ => return false,
            }
            return true;
        }
        if !intermediates.is_empty() {
            return false;
        }
```
and replace (lines 67-71)
```rust
            's' => self.save_cursor(),
            'u' => self.restore_cursor(),
            _ => {}
        }
    }
```
with
```rust
            's' => self.save_cursor(),
            'u' => self.restore_cursor(),
            _ => return false,
        }
        true
    }
```
(The history receiver's own `Perform`, `crates/vt-core/src/history.rs:164`, calls `self.screen.csi(…);` as a statement and ignores the new `bool` — leave it.)

Replace the whole of `packages/terminal/crates/vt-core/src/parser/perform.rs` with:

```rust
use vte::{Params, Perform};

use super::unknown::private_modes_known;
use super::Parser;
use crate::program::OscKind;

fn first_param(params: &Params) -> u16 {
    params
        .iter()
        .next()
        .and_then(|group| group.first().copied())
        .unwrap_or(0)
}

impl Parser {
    pub(crate) fn flush_run(&mut self) {
        if self.run.is_empty() {
            return;
        }
        let style = self.pending_style.resolved();
        let run = std::mem::take(&mut self.run);
        self.active_screen_mut().print_ascii_run(&run, style);
        self.run = run;
        self.run.clear();
    }

    fn dispatch_csi(&mut self, params: &Params, intermediates: &[u8], c: char) -> bool {
        if c == 'm' && intermediates.is_empty() {
            self.apply_sgr(params);
            return true;
        }
        if intermediates == b"?$" && c == 'p' {
            self.answer_decrqm(params);
            return true;
        }
        if intermediates.is_empty() && c == 'c' && first_param(params) == 0 {
            self.push_reply(b"\x1b[?62;22c");
            return true;
        }
        if intermediates == b">" && c == 'q' && first_param(params) == 0 {
            self.answer_xtversion();
            return true;
        }
        if intermediates.is_empty() && c == 't' {
            return self.xtwinops(params);
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
            self.active_screen_mut().csi(params, intermediates, c);
            return private_modes_known(params);
        }
        self.active_screen_mut().csi(params, intermediates, c)
    }
}

impl Perform for Parser {
    fn print(&mut self, c: char) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Print(c));
        if matches!(c, ' '..='~') {
            self.run.push(c as u8);
            return;
        }
        self.flush_run();
        let style = self.pending_style.resolved();
        self.active_screen_mut().print(c, style);
    }

    fn execute(&mut self, byte: u8) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Execute(byte));
        self.flush_run();
        let screen = self.active_screen_mut();
        match byte {
            0x08 => screen.move_by(0, -1),
            0x09 => screen.tab(),
            0x0A..=0x0C => screen.line_feed(),
            0x0D => screen.carriage_return(),
            _ => {}
        }
    }

    fn hook(&mut self, params: &Params, intermediates: &[u8], ignore: bool, action: char) {
        self.note_unknown_dcs(params, intermediates, ignore, action);
    }

    fn csi_dispatch(&mut self, params: &Params, intermediates: &[u8], ignore: bool, c: char) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Csi {
            params: params.iter().map(|group| group.to_vec()).collect(),
            intermediates: intermediates.to_vec(),
            action: c,
        });
        self.flush_run();
        if !self.dispatch_csi(params, intermediates, c) || ignore {
            self.note_unknown_csi(params, intermediates, ignore, c);
        }
    }

    fn esc_dispatch(&mut self, intermediates: &[u8], _ignore: bool, byte: u8) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Esc {
            intermediates: intermediates.to_vec(),
            byte,
        });
        self.flush_run();
        self.active_screen_mut().esc(byte);
        self.note_esc(intermediates, byte);
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], bell_terminated: bool) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Osc(
            params.iter().map(|p| p.to_vec()).collect(),
        ));
        self.flush_run();
        match OscKind::of(params) {
            OscKind::Hyperlink => {
                let id = crate::hyperlink::parse_osc8(&params[1..])
                    .and_then(|link| self.hyperlinks.intern(link));
                self.pending_style.link = id.unwrap_or(0);
            }
            OscKind::IconName => {}
            OscKind::Other => self.note_other_osc(params),
            _ => self.program_osc(params, bell_terminated),
        }
    }
}
```

In `packages/terminal/crates/vt-wasm/src/program.rs`, replace (lines 43-46)

```rust
    pub fn live_output_bytes(&self) -> f64 {
        self.core.live_output_bytes() as f64
    }
}
```
with
```rust
    pub fn live_output_bytes(&self) -> f64 {
        self.core.live_output_bytes() as f64
    }

    pub fn unknown_sequences(&self) -> Vec<String> {
        self.core
            .unknown_sequences()
            .into_iter()
            .map(|entry| format!("{} {}", entry.count, entry.text))
            .collect()
    }
}
```

- [ ] **Step 4: Verify**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo test -p vt-core --test unknown_sequences 2>&1 | grep "test result"
cargo test -p vt-wasm --test program_exports 2>&1 | grep "test result"
cargo test --release -p vt-core --test parser_goldens 2>&1 | grep "test result"
cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
wc -l crates/vt-core/src/parser.rs crates/vt-core/src/parser/perform.rs crates/vt-core/src/parser/unknown.rs crates/vt-core/src/lib.rs crates/vt-wasm/src/program.rs
```
Expected: `Finished …`; `test result: ok. 9 passed`; `test result: ok. 5 passed`; `test result: ok. 1 passed`; only `rust-done`; `549`, `135`, `143`, `593`, `54`. The goldens prove the dispatch refactor (`dispatch_csi` returning whether it handled a sequence) changed nothing observable, including §4.22 (`CSI > 4;2 m` never reaches SGR — `synthetic-malformed` carries it, and `tests/sgr_attributes.rs` still passes).

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-core/src/parser/unknown.rs packages/terminal/crates/vt-core/src/parser/perform.rs \
  packages/terminal/crates/vt-core/src/parser.rs packages/terminal/crates/vt-core/src/lib.rs \
  packages/terminal/crates/vt-core/src/parser/program.rs packages/terminal/crates/vt-core/src/screen/dispatch.rs \
  packages/terminal/crates/vt-core/tests/unknown_sequences.rs \
  packages/terminal/crates/vt-wasm/src/program.rs packages/terminal/crates/vt-wasm/tests/program_exports.rs
git commit -m "feat(vt-core): keep the last 64 unhandled sequences for debugging (unknown_sequences)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Part B — measure, decide, gates, mirror wasm, docs

**Files:**
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` (rebuilt), `packages/terminal/CHANGELOG.md`, `TERMINAL.md` (§4.35, §5), `docs/terminal/2026-09-19-terminal-reference-survey.md` (§1.11 row and status, count sentence), `docs/terminal/2026-09-24-not-done-plain-language.md` (item 16, intro)

**Interfaces:**
- Consumes: `$HOME/plan9-snapshot.sh`, `$HOME/plan9-ab.sh`, snapshot `control` (Task 1).
- Produces: snapshot `partB` (Task 7's control); the Part B verdict.

- [ ] **Step 1: Snapshot the candidate**

```bash
bash "$HOME/plan9-snapshot.sh" partB 2>&1 | tail -1
```
Expected: `snapshot partB ready`.

- [ ] **Step 2: A/B against the unmodified parser**

```bash
bash "$HOME/plan9-ab.sh" control partB "$HOME/plan9-ab-partB.log"
```
Expected: eight verdict lines (planning run, all `faster`):

```text
ascii-heavy grapheme: control 22.85-23.35 partB 54.54-56.14 (141.8% median) faster
ascii-heavy scalar: control 47.84-48.01 partB 54.12-55.99 (16.2% median) faster
claude-long-50k grapheme: control 29.51-30.42 partB 46.43-46.89 (57.7% median) faster
claude-long-50k scalar: control 73.07-74.05 partB 74.50-75.60 (2.2% median) faster
edit-heavy grapheme: control 29.86-30.03 partB 75.65-77.32 (157.8% median) faster
edit-heavy scalar: control 62.27-62.92 partB 76.20-77.29 (22.9% median) faster
wasm claude-long-50k grapheme: control 28.15-28.39 partB 33.09-33.42 (17.9% median) faster
wasm claude-long-50k scalar: control 50.92-51.13 partB 52.39-53.05 (3.3% median) faster
```

- [ ] **Step 3: Decide (Design decisions, "Keep rules")**

Keep Part B if `claude-long-50k grapheme` and `wasm claude-long-50k grapheme` both read `faster` and no line reads `slower`. Otherwise stop Part B: `git revert --no-edit <Task 5 commit> <Task 4 commit>` (Task 5's `perform.rs` is built on Task 4's run buffer, so they go together; Task 3's pure move stays), write the decision and all eight lines into the report, skip Steps 4–6, and continue with Part C using `control` wherever Tasks 7–9 say `partB` (Part C edits only `screen/edit.rs`, which Tasks 4–5 do not touch; Task 8's patch will then not apply — skip Task 8 and say so). Record the decision and all eight lines in the report either way.

- [ ] **Step 4: Gate set G** (G1–G7). G2 rebuilds `vt_host.wasm`: its status line must show ` M …vt_host.wasm`.

- [ ] **Step 5: Docs**

(a) `packages/terminal/CHANGELOG.md` — insert as the first bullet under `## Unreleased` (a new line 5, before the bullet starting `- vt-core/marks/core: Plan 8 review fixes.`):

```markdown
- vt-core/vt-wasm: parser fast path (roadmap Plan 9 Part B, survey §1.11). Printable ASCII is buffered between control sequences and written a row segment at a time (`ScreenGrid::print_ascii_run`), ASCII after an ASCII cell skips the width lookup and the grapheme join, and the join no longer allocates. Nothing observable changes (`tests/parser_goldens.rs`: 53 recordings × 4 configurations, goldens from the tree before). `TerminalCore::unknown_sequences()` / `clear_unknown_sequences()` and `WasmTerminalCore.unknown_sequences()` keep the newest 64 distinct CSI/ESC/DCS/OSC that nothing handled (OSC by number only, text ≤ 48 bytes), for debugging. `ScreenGrid::csi` and `Parser::xtwinops` report whether they handled a sequence. `src/screen.rs`'s print path moved to `src/screen/print.rs`. Both wasm artifacts and the daemon must be rebuilt.
```

(b) `TERMINAL.md` §4.35 — append after the bullet that starts `- Guard for the whole plan:` (i.e. directly before the blank line that precedes `## 5. Known gaps (not bugs, decisions pending)`):

```markdown
- **Part B: printable runs and unknown sequences.** The parser buffers
  printable ASCII between control sequences (`Parser.run`, flushed before
  every other callback and at the end of every `advance_vte`, so a mark, an
  alternate-screen switch or a sync flush never sees bytes pending) and
  `ScreenGrid::print_ascii_run` (`crates/vt-core/src/screen/print.rs`) writes
  it a row segment at a time; `ScreenGrid::print` skips the width lookup and
  the grapheme join for ASCII after an ASCII cell (an ASCII scalar joins a
  cluster only after a `Prepend`, UAX #29 GB9b); `joins_previous` no longer
  allocates (`width.rs`). Ghostty's run decode (`src/terminal/stream.zig:599-720`)
  is the idea, not the code: vte owns the byte loop, so the batching happens
  on its `print` callbacks. `TerminalCore::unknown_sequences()` keeps the
  newest 64 distinct CSI/ESC/DCS/OSC that nothing handled
  (`parser/unknown.rs`; an OSC by its number only, never its payload; text
  ≤ 48 bytes; debugging only, also `WasmTerminalCore.unknown_sequences()`).
  The three Claude Code recordings leave `CSI <0u`, `CSI >4;2m`, `CSI >4m`,
  `CSI >5u`, `CSI ?0u`, `CSI ?2031h/l` and `ESC (B` in it.
- Part B measured (`examples/parse_throughput.rs` and
  `bench/parse-throughput.mjs`, 3 alternated pairs, medians of 7, MB/s):
```
followed by one indented line per verdict line of Step 2, verbatim (8 lines, each starting `  - `), and a last indented line `  - Environment: <output of \`uname -sm\`>, <CPU model>` (Linux: `lscpu | grep 'Model name'`; macOS: `sysctl -n machdep.cpu.brand_string`). Then:
```markdown
- Guards (Part B): `tests/print_run.rs` (a 512-case proptest against
  one-character-at-a-time printing, the `Prepend` join, runs split at every
  byte, a run before a boundary mark and before the alternate screen,
  invalid UTF-8, DEL), `tests/unknown_sequences.rs`, `vt-wasm`
  `program_exports.rs` `the_wasm_core_lists_unknown_sequences_with_their_counts`,
  and the goldens.
```

(c) `TERMINAL.md` §5 — append after the last §5 bullet (the one starting `- **\`readBlockOutput\` ignores redaction**` and ending `line between the copies is kept (\`claude-markdown-reply\`, §4.34).`), before the `---` line:

```markdown
- **Unknown sequences are recorded, not reported** (§4.35). Only code reads
  the ring (`TerminalCore::unknown_sequences()`, or
  `WasmTerminalCore.unknown_sequences()` from a devtools console); the
  pty-host mirror's ring is never read, and SOS/PM/APC strings reach no vte
  callback, so they are not recorded at all.
- **The history receiver prints one character at a time.** History chunks and
  older answers go through `crates/vt-core/src/history.rs`'s own `Perform`,
  which gets `ScreenGrid::print`'s ASCII fast path but not the run buffer.
```

(d) Survey — line 64: replace the whole line starting `| §1.11 | Not done |` with:

```text
| §1.11 | Done | Roadmap Plan 9 — printable ASCII is buffered between control sequences and written a row segment at a time (`ScreenGrid::print_ascii_run`), ASCII after ASCII skips the grapheme join, the join no longer allocates; `TerminalCore::unknown_sequences()` keeps the newest 64 distinct unhandled CSI/ESC/DCS/OSC (OSC by number only). vte still decodes UTF-8 per character (no SIMD). Measured in `TERMINAL.md` §4.35. |
```
Line 816 (status under the §1.11 heading): replace the line starting `> **Status: Not done.** \`print\` is still per character` with:
```text
> **Status: Done.** Roadmap Plan 9 — `Parser.run` buffers printable ASCII between control sequences and `ScreenGrid::print_ascii_run` writes it a row segment at a time; `ScreenGrid::print` skips the join for ASCII after ASCII; `joins_previous` is allocation-free; the unknown-sequence ring is `TerminalCore::unknown_sequences()` (64 entries, debugging only). Before/after numbers: `TERMINAL.md` §4.35.
```
Recount with the `awk` command of Task 2 Step 4: expect `46 Done`, `1 N/A`, `13 Notdone`, `1 Notneeded`, `8 Notpursued`, `19 Partial`, and put those numbers into line 50 in the same words (`46 done, 19 partial, 13 not done, 8 not pursued, 1 not needed, 1 n/a`).

(e) Plain-language doc — replace item 16 (from the line starting `16. **Faster text processing (§1.11).**` through the line ending `terminal doesn't understand are logged so they can be fixed.`) with:
```markdown
16. **Faster text processing (§1.11) — done (roadmap Plan 9).** Plain text
    is now written a stretch at a time instead of one character at a time;
    Claude Code's long output is read about half again as fast in the
    terminal's own measurements. Codes the terminal doesn't understand are
    kept in a short list developers can read.
```
If your Step 2 `claude-long-50k grapheme` median change is below +30 %, replace "about half again as fast" with "noticeably faster" and keep the rest.

- [ ] **Step 6: Commit**

```bash
cd "$REPO" && git add backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
git commit -m "chore(terminal): rebuild the mirror wasm for the Plan 9 parser fast path" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git add packages/terminal/CHANGELOG.md TERMINAL.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/terminal/2026-09-24-not-done-plain-language.md
git commit -m "docs(terminal): Plan 9 Part B — printable runs and unknown sequences (TERMINAL.md §4.35, survey §1.11)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
Expected: two commits; a clean status.

---
### Task 7: Part C — erase, insert and delete a row slice at a time

**Files:**
- Create: `packages/terminal/crates/vt-core/tests/bulk_edits.rs`
- Modify (replace whole file): `packages/terminal/crates/vt-core/src/screen/edit.rs`

**Interfaces:**
- Consumes: `ScreenGrid`'s private `phys_start`, `erased_cell`, `set_row_wrapped`, `mark_dirty`, `cells`, `cols()` (child module access, as today).
- Produces: private `fill_cells(&mut self, row: usize, from: usize, to: usize)` and `shift_cells(&mut self, row: usize, from: usize, to: usize, by: isize)` in `screen/edit.rs`; the public edit methods keep their signatures.

- [ ] **Step 1: Write the tests**

Create `packages/terminal/crates/vt-core/tests/bulk_edits.rs`:

```rust
use vt_core::testing::ScreenGrid;
use vt_core::{CellStyle, StyleCode};

fn grid_with(text: &str, cols: usize) -> ScreenGrid {
    let mut grid = ScreenGrid::new(3, cols);
    for ch in text.chars() {
        grid.print(ch, CellStyle::DEFAULT);
    }
    grid.take_dirty();
    grid
}

fn row(grid: &ScreenGrid, row: usize) -> String {
    (0..grid.cols())
        .map(|col| match grid.cell(row, col).ch {
            '\0' => '_',
            ch => ch,
        })
        .collect()
}

#[test]
fn insert_shifts_right_and_fills_the_gap_with_the_erase_background() {
    let mut grid = grid_with("abcdef", 8);
    grid.set_erase_background(StyleCode::indexed(1));
    grid.move_to(0, 1);
    grid.insert_chars(2);
    assert_eq!(row(&grid, 0), "a  bcdef");
    assert_eq!(grid.cell(0, 1).style.bg, StyleCode::indexed(1));
    assert_eq!(grid.cell(0, 2).style.bg, StyleCode::indexed(1));
    assert_eq!(grid.cell(0, 3).style.bg, StyleCode::DEFAULT_BACKGROUND);
    assert_eq!(grid.take_dirty(), vec![0]);
}

#[test]
fn delete_shifts_left_clamps_its_count_and_fills_the_tail() {
    let mut grid = grid_with("abcdef", 8);
    grid.move_to(0, 2);
    grid.delete_chars(3);
    assert_eq!(row(&grid, 0), "abf     ");
    grid.delete_chars(99);
    assert_eq!(row(&grid, 0), "ab      ");
    assert_eq!(grid.take_dirty(), vec![0]);
}

#[test]
fn erase_chars_and_erase_in_line_touch_only_their_span() {
    let mut grid = grid_with("abcdefgh", 8);
    grid.move_to(0, 2);
    grid.erase_chars(2);
    assert_eq!(row(&grid, 0), "ab  efgh");
    grid.move_to(0, 5);
    grid.erase_in_line(1);
    assert_eq!(row(&grid, 0), "      gh");
    grid.move_to(0, 7);
    grid.erase_in_line(0);
    assert_eq!(row(&grid, 0), "      g ");
}

#[test]
fn a_wrapped_row_stays_wrapped_until_an_edit_reaches_its_last_column() {
    let mut grid = grid_with("abcdef", 4);
    assert!(grid.row_wrapped(0));
    grid.move_to(0, 0);
    grid.erase_chars(1);
    assert!(grid.row_wrapped(0));
    grid.erase_in_line(1);
    assert!(grid.row_wrapped(0));
    grid.move_to(0, 1);
    grid.erase_in_line(0);
    assert!(!grid.row_wrapped(0));
    let mut inserted = grid_with("abcdef", 4);
    inserted.move_to(0, 0);
    inserted.insert_chars(1);
    assert!(!inserted.row_wrapped(0));
    let mut deleted = grid_with("abcdef", 4);
    deleted.move_to(0, 0);
    deleted.delete_chars(1);
    assert!(!deleted.row_wrapped(0));
}

#[test]
fn a_wide_character_moves_with_its_spacer() {
    let mut grid = grid_with("a\u{4e2d}b", 6);
    assert_eq!(row(&grid, 0), "a\u{4e2d}_b  ");
    grid.move_to(0, 0);
    grid.delete_chars(1);
    assert_eq!(row(&grid, 0), "\u{4e2d}_b   ");
    grid.insert_chars(2);
    assert_eq!(row(&grid, 0), "  \u{4e2d}_b ");
}

#[test]
fn a_combined_cell_survives_a_shift_whole() {
    let mut grid = grid_with("xe\u{301}y", 6);
    grid.move_to(0, 0);
    grid.delete_chars(1);
    let mut buffer = [0u8; 4];
    assert_eq!(grid.cell(0, 0).text(&mut buffer), "e\u{301}");
    grid.insert_chars(3);
    assert_eq!(grid.cell(0, 3).text(&mut buffer), "e\u{301}");
    assert_eq!(grid.cell(0, 4).ch, 'y');
}
```

- [ ] **Step 2: Run them on the current code — they must pass**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test bulk_edits 2>&1 | grep "test result"
```
Expected: `test result: ok. 6 passed`. These pin today's per-cell behaviour (erase background, `wrapped` cleared only when an edit reaches the last column, wide characters moving with their spacer, combined cells moving whole, dirty rows) so the rewrite below is checked against it; together with `synthetic-edits-styled` in the goldens they are this task's red/green.

- [ ] **Step 3: Implement**

Replace the whole of `packages/terminal/crates/vt-core/src/screen/edit.rs` with:

```rust
use crate::screen::{ClearPolicy, ScreenGrid};

impl ScreenGrid {
    fn fill_cells(&mut self, row: usize, from: usize, to: usize) {
        if from >= to {
            return;
        }
        let start = self.phys_start(row);
        let blank = self.erased_cell();
        self.cells[start + from..start + to].fill(blank);
        if to == self.cols() {
            self.set_row_wrapped(row, false);
        }
        self.mark_dirty(row);
    }

    fn shift_cells(&mut self, row: usize, from: usize, to: usize, by: isize) {
        let start = self.phys_start(row);
        let span = &mut self.cells[start + from..start + to];
        if by > 0 {
            span.rotate_right(by.unsigned_abs());
        } else {
            span.rotate_left(by.unsigned_abs());
        }
        self.set_row_wrapped(row, false);
        self.mark_dirty(row);
    }

    pub fn erase_in_display(&mut self, mode: u16) {
        let (row, col) = self.cursor();
        let rows = self.rows();
        let cols = self.cols();
        match mode {
            0 => {
                self.fill_cells(row, col, cols);
                for r in (row + 1)..rows {
                    self.blank_row(r);
                }
            }
            1 => {
                for r in 0..row {
                    self.blank_row(r);
                }
                self.fill_cells(row, 0, col + 1);
            }
            2 => match self.clear_policy {
                ClearPolicy::Scroll => {
                    self.scroll_up(self.frame_rows());
                    self.max_cursor_row = 0;
                }
                ClearPolicy::ClearInPlace => {
                    for r in 0..rows {
                        self.blank_row(r);
                    }
                    self.max_cursor_row = 0;
                }
            },
            _ => {
                for r in 0..rows {
                    self.blank_row(r);
                }
            }
        }
    }

    pub fn evict_frame(&mut self) {
        let frame = self.frame_rows();
        let (top, bottom) = (self.scroll_top, self.scroll_bottom);
        self.scroll_top = 0;
        self.scroll_bottom = self.rows() - 1;
        self.scroll_up(frame);
        self.scroll_top = top;
        self.scroll_bottom = bottom;
        self.max_cursor_row = 0;
        self.move_to(0, 0);
        self.pending_wrap = false;
    }

    pub fn erase_in_line(&mut self, mode: u16) {
        let (row, col) = self.cursor();
        let cols = self.cols();
        match mode {
            0 => self.fill_cells(row, col, cols),
            1 => self.fill_cells(row, 0, col + 1),
            _ => self.blank_row(row),
        }
    }

    pub fn insert_chars(&mut self, count: usize) {
        let (row, col) = self.cursor();
        let cols = self.cols();
        let count = count.min(cols - col);
        if count == 0 {
            return;
        }
        self.shift_cells(row, col, cols, count as isize);
        self.fill_cells(row, col, col + count);
    }

    pub fn delete_chars(&mut self, count: usize) {
        let (row, col) = self.cursor();
        let cols = self.cols();
        let count = count.min(cols - col);
        if count == 0 {
            return;
        }
        self.shift_cells(row, col, cols, -(count as isize));
        self.fill_cells(row, cols - count, cols);
    }

    pub fn erase_chars(&mut self, count: usize) {
        let (row, col) = self.cursor();
        let cols = self.cols();
        let count = count.min(cols - col);
        self.fill_cells(row, col, col + count);
    }

    pub fn insert_lines(&mut self, count: usize) {
        let row = self.cursor().0;
        if row < self.scroll_top || row > self.scroll_bottom {
            return;
        }
        let room = self.scroll_bottom - row + 1;
        let count = count.min(room);
        if count == 0 {
            return;
        }
        for r in ((row + count)..=self.scroll_bottom).rev() {
            self.copy_row(r - count, r);
        }
        for r in row..(row + count) {
            self.blank_row(r);
        }
    }

    pub fn delete_lines(&mut self, count: usize) {
        let row = self.cursor().0;
        if row < self.scroll_top || row > self.scroll_bottom {
            return;
        }
        let room = self.scroll_bottom - row + 1;
        let count = count.min(room);
        if count == 0 {
            return;
        }
        if count < room {
            for r in row..=(self.scroll_bottom - count) {
                self.copy_row(r + count, r);
            }
        }
        for r in (self.scroll_bottom + 1 - count)..=self.scroll_bottom {
            self.blank_row(r);
        }
    }
}
```

- [ ] **Step 4: Verify**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo test -p vt-core --test bulk_edits 2>&1 | grep "test result"
cargo test --release -p vt-core --test parser_goldens 2>&1 | grep "test result"
cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
wc -l crates/vt-core/src/screen/edit.rs
```
Expected: `Finished …`; `test result: ok. 6 passed`; `test result: ok. 1 passed`; only `rust-done`; `155`.

- [ ] **Step 5: Measure against Part B and decide**

```bash
bash "$HOME/plan9-snapshot.sh" partC 2>&1 | tail -1
bash "$HOME/plan9-ab.sh" partB partC "$HOME/plan9-ab-partC.log"
```
Expected (planning run; the session was noisy, so every line but `edit-heavy` read `noise`):

```text
ascii-heavy grapheme: partB 47.81-53.61 partC 48.94-50.16 (-2.4% median) noise
ascii-heavy scalar: partB 49.58-53.86 partC 49.05-51.32 (-3.9% median) noise
claude-long-50k grapheme: partB 42.00-46.01 partC 43.09-44.75 (-0.0% median) noise
claude-long-50k scalar: partB 68.10-73.61 partC 70.03-73.13 (4.2% median) noise
edit-heavy grapheme: partB 72.41-74.40 partC 82.58-83.04 (12.5% median) faster
edit-heavy scalar: partB 71.97-74.63 partC 82.85-82.87 (11.1% median) faster
wasm claude-long-50k grapheme: partB 30.75-31.54 partC 31.52-31.86 (2.8% median) noise
wasm claude-long-50k scalar: partB 48.60-51.81 partC 50.63-51.27 (2.2% median) noise
```
Keep if both `edit-heavy` lines read `faster` and no line reads `slower`. If not kept: `git checkout -- packages/terminal/crates/vt-core/src/screen/edit.rs`, still commit `bulk_edits.rs` alone (it pins behaviour either way), write the eight lines into the report, and continue with Task 8 using `partB` in place of `partC`.

- [ ] **Step 6: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-core/src/screen/edit.rs packages/terminal/crates/vt-core/tests/bulk_edits.rs
git commit -m "perf(vt-core): erase, insert and delete a row slice at a time" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
(If Step 5 rejected the rewrite, `git add` only the test and use the message `test(vt-core): pin erase, insert and delete behaviour`.)

---

### Task 8: Part C — row flags, measure and decide

**Files:**
- Outside the repository: `$HOME/plan9-row-flags.patch`
- Modify only if kept: `packages/terminal/crates/vt-core/src/{content.rs,parser.rs,screen.rs,scrollback.rs}`, `src/screen/{edit.rs,print.rs,resize.rs}`

**Interfaces:**
- Consumes: the Task 7 tree (`partC` snapshot).
- Produces: a verdict; code only if kept. If kept: `EvictedRow.plain: bool`, `pub(crate) const ROW_STYLED: u8 = 1`, `ROW_GRAPHEME: u8 = 2`, `pub(crate) fn cell_flags(cell: &Cell) -> u8`, `ScreenGrid::note_row_flags(&mut self, row: usize, flags: u8)`, `scrollback::commit_row(cells, wrapped, plain, content, rows, styles)`, `Content::push_text(&mut self, text: &str)`.

What the patch does (Design decisions, Part C): a per-row `row_flags: Vec<u8>` (false positives allowed, never false negatives), set on every cell write (`set`, `put_ascii`, `print_ascii_run`, `fill_cells`, a grapheme append), reset by `blank_row`, rotated with the rows, carried through `resize_cells`; an evicted row with no flag is committed by `commit_plain_row` (one style call, one text push; `Content::push_text` splits at `CHUNK_SIZE` exactly as per-character `push_char` does and uses `saturating_sub` because a prepended history chunk can be longer than `CHUNK_SIZE`).

- [ ] **Step 1: Write the patch file** (exactly; it applies to the Task 7 tree)

```bash
cat > "$HOME/plan9-row-flags.patch" <<'EOF'
--- a/packages/terminal/crates/vt-core/src/content.rs
+++ b/packages/terminal/crates/vt-core/src/content.rs
@@ -80,6 +80,36 @@
         let chunk = self.chunks.back_mut().expect("chunk just created");
         chunk.bytes.extend_from_slice(bytes);
         self.next_offset += bytes_len as u64;
+    }
+
+    pub fn push_text(&mut self, text: &str) {
+        if !text.is_ascii() {
+            let mut buffer = [0u8; 4];
+            for ch in text.chars() {
+                self.push_char(ch.encode_utf8(&mut buffer));
+            }
+            return;
+        }
+        let mut bytes = text.as_bytes();
+        while !bytes.is_empty() {
+            let room = self
+                .chunks
+                .back()
+                .map_or(0, |chunk| CHUNK_SIZE.saturating_sub(chunk.bytes.len()));
+            if room == 0 {
+                self.chunks.push_back(Chunk {
+                    start: self.next_offset,
+                    bytes: Vec::new(),
+                });
+                continue;
+            }
+            let take = room.min(bytes.len());
+            if let Some(chunk) = self.chunks.back_mut() {
+                chunk.bytes.extend_from_slice(&bytes[..take]);
+            }
+            self.next_offset += take as u64;
+            bytes = &bytes[take..];
+        }
     }
 
     pub fn copy_range(&self, start: u64, end: u64) -> Vec<u8> {
--- a/packages/terminal/crates/vt-core/src/parser.rs
+++ b/packages/terminal/crates/vt-core/src/parser.rs
@@ -469,6 +469,7 @@
             crate::scrollback::commit_row(
                 &row.cells,
                 row.wrapped,
+                row.plain,
                 &mut self.content,
                 &mut self.rows,
                 &mut self.styles,
--- a/packages/terminal/crates/vt-core/src/screen.rs
+++ b/packages/terminal/crates/vt-core/src/screen.rs
@@ -89,6 +89,24 @@
 pub struct EvictedRow {
     pub cells: Vec<Cell>,
     pub wrapped: bool,
+    pub plain: bool,
+}
+
+pub(crate) const ROW_STYLED: u8 = 1;
+pub(crate) const ROW_GRAPHEME: u8 = 2;
+
+pub(crate) fn cell_flags(cell: &Cell) -> u8 {
+    let styled = if cell.style == CellStyle::DEFAULT {
+        0
+    } else {
+        ROW_STYLED
+    };
+    let grapheme = if cell.extra.is_some() {
+        ROW_GRAPHEME
+    } else {
+        0
+    };
+    styled | grapheme
 }
 
 pub struct ScreenGrid {
@@ -96,6 +114,7 @@
     cols: usize,
     cells: Vec<Cell>,
     wrapped: Vec<bool>,
+    row_flags: Vec<u8>,
     first: usize,
     row: usize,
     max_cursor_row: usize,
@@ -127,6 +146,7 @@
             cols,
             cells: vec![Cell::BLANK; rows * cols],
             wrapped: vec![false; rows],
+            row_flags: vec![0; rows],
             first: 0,
             row: 0,
             max_cursor_row: 0,
@@ -182,11 +202,19 @@
         self.evicted.push(EvictedRow {
             cells: self.cells[start..start + self.cols].to_vec(),
             wrapped: self.wrapped[self.phys_row(row)],
+            plain: self.row_flags[self.phys_row(row)] == 0,
         });
     }
 
     pub fn row_wrapped(&self, row: usize) -> bool {
         row < self.rows && self.wrapped[self.phys_row(row)]
+    }
+
+    fn note_row_flags(&mut self, row: usize, flags: u8) {
+        if row < self.rows && flags != 0 {
+            let index = self.phys_row(row);
+            self.row_flags[index] |= flags;
+        }
     }
 
     fn set_row_wrapped(&mut self, row: usize, wrapped: bool) {
@@ -291,6 +319,7 @@
             return;
         }
         let index = self.phys_start(row) + col;
+        self.note_row_flags(row, cell_flags(&cell));
         self.cells[index] = cell;
         if col + 1 == self.cols {
             self.set_row_wrapped(row, false);
@@ -304,6 +333,8 @@
         }
         let start = self.phys_start(row);
         let blank = self.erased_cell();
+        let index = self.phys_row(row);
+        self.row_flags[index] = cell_flags(&blank);
         self.cells[start..start + self.cols].fill(blank);
         self.set_row_wrapped(row, false);
         self.mark_dirty(row);
@@ -329,6 +360,7 @@
             let shift = self.first * self.cols;
             self.cells.rotate_left(shift);
             self.wrapped.rotate_left(self.first);
+            self.row_flags.rotate_left(self.first);
             self.first = 0;
         }
     }
@@ -348,6 +380,7 @@
         let end = (self.scroll_bottom + 1) * self.cols;
         self.cells[start..end].rotate_left(count * self.cols);
         self.wrapped[self.scroll_top..=self.scroll_bottom].rotate_left(count);
+        self.row_flags[self.scroll_top..=self.scroll_bottom].rotate_left(count);
     }
 
     pub(crate) fn rotate_region_down(&mut self, count: usize) {
@@ -361,6 +394,7 @@
         let end = (self.scroll_bottom + 1) * self.cols;
         self.cells[start..end].rotate_right(count * self.cols);
         self.wrapped[self.scroll_top..=self.scroll_bottom].rotate_right(count);
+        self.row_flags[self.scroll_top..=self.scroll_bottom].rotate_right(count);
     }
 
     pub(crate) fn copy_row(&mut self, from: usize, to: usize) {
@@ -436,6 +470,7 @@
         self.mark_all_dirty();
         self.cells.fill(Cell::BLANK);
         self.wrapped.fill(false);
+        self.row_flags.fill(0);
         self.row = 0;
         self.max_cursor_row = 0;
         self.col = 0;
--- a/packages/terminal/crates/vt-core/src/scrollback.rs
+++ b/packages/terminal/crates/vt-core/src/scrollback.rs
@@ -7,10 +7,15 @@
 pub(crate) fn commit_row(
     cells: &[Cell],
     wrapped: bool,
+    plain: bool,
     content: &mut Content,
     rows: &mut RowIndex,
     styles: &mut AttributeMap<CellStyle>,
 ) {
+    if plain {
+        commit_plain_row(cells, wrapped, content, rows, styles);
+        return;
+    }
     let width = if wrapped {
         cells.len()
     } else {
@@ -27,6 +32,33 @@
         let mut buffer = [0u8; 4];
         content.push_char(cell.text(&mut buffer));
     }
+    rows.complete_row(content.end_offset(), wrapped);
+}
+
+fn commit_plain_row(
+    cells: &[Cell],
+    wrapped: bool,
+    content: &mut Content,
+    rows: &mut RowIndex,
+    styles: &mut AttributeMap<CellStyle>,
+) {
+    let width = if wrapped {
+        cells.len()
+    } else {
+        cells
+            .iter()
+            .rposition(|cell| !matches!(cell.ch, ' ' | '\0'))
+            .map_or(0, |index| index + 1)
+    };
+    if width > 0 {
+        styles.set_from(content.end_offset(), CellStyle::DEFAULT);
+    }
+    let text: String = cells[..width]
+        .iter()
+        .map(|cell| cell.ch)
+        .filter(|ch| *ch != '\0')
+        .collect();
+    content.push_text(&text);
     rows.complete_row(content.end_offset(), wrapped);
 }
 
@@ -55,7 +87,7 @@
         let mut content = Content::new();
         let mut rows = RowIndex::new(0);
         let mut styles = AttributeMap::new(CellStyle::DEFAULT);
-        commit_row(cells, wrapped, &mut content, &mut rows, &mut styles);
+        commit_row(cells, wrapped, false, &mut content, &mut rows, &mut styles);
         (content, rows, styles)
     }
 
--- a/packages/terminal/crates/vt-core/src/screen/edit.rs
+++ b/packages/terminal/crates/vt-core/src/screen/edit.rs
@@ -1,4 +1,4 @@
-use crate::screen::{ClearPolicy, ScreenGrid};
+use crate::screen::{cell_flags, ClearPolicy, ScreenGrid};
 
 impl ScreenGrid {
     fn fill_cells(&mut self, row: usize, from: usize, to: usize) {
@@ -7,6 +7,7 @@
         }
         let start = self.phys_start(row);
         let blank = self.erased_cell();
+        self.note_row_flags(row, cell_flags(&blank));
         self.cells[start + from..start + to].fill(blank);
         if to == self.cols() {
             self.set_row_wrapped(row, false);
--- a/packages/terminal/crates/vt-core/src/screen/print.rs
+++ b/packages/terminal/crates/vt-core/src/screen/print.rs
@@ -1,6 +1,6 @@
 use unicode_width::UnicodeWidthChar;
 
-use crate::screen::{Cell, ScreenGrid};
+use crate::screen::{Cell, ScreenGrid, ROW_GRAPHEME, ROW_STYLED};
 use crate::style::CellStyle;
 use crate::width::{self, WidthMode};
 
@@ -54,6 +54,9 @@
             let row = self.row;
             self.raise_max_cursor_row(row);
             let take = (self.cols - self.col).min(rest.len() - at);
+            if style != CellStyle::DEFAULT {
+                self.note_row_flags(row, ROW_STYLED);
+            }
             let start = self.phys_start(row) + self.col;
             for (cell, byte) in self.cells[start..start + take]
                 .iter_mut()
@@ -76,6 +79,9 @@
         let row = self.row;
         self.raise_max_cursor_row(row);
         let index = self.phys_start(row) + self.col;
+        if style != CellStyle::DEFAULT {
+            self.note_row_flags(row, ROW_STYLED);
+        }
         self.cells[index] = Cell::new(ch, style);
         if self.col + 1 == self.cols {
             self.set_row_wrapped(row, false);
@@ -130,6 +136,7 @@
         }
         let old_width = self.cell_width_at(row, col);
         self.cells[index].append_scalar(ch);
+        self.note_row_flags(row, ROW_GRAPHEME);
         let new_width = width::cluster_width(self.cells[index].text(&mut buffer));
         if new_width > old_width && col + 1 < self.cols {
             self.set(row, col + 1, Cell::new('\0', style));
@@ -168,6 +175,7 @@
         }
         let index = self.phys_start(row) + col;
         self.cells[index].append_scalar(ch);
+        self.note_row_flags(row, ROW_GRAPHEME);
         self.mark_dirty(row);
     }
 }
--- a/packages/terminal/crates/vt-core/src/screen/resize.rs
+++ b/packages/terminal/crates/vt-core/src/screen/resize.rs
@@ -22,6 +22,7 @@
     fn reset_cells(&mut self, rows: usize, cols: usize) {
         self.cells = vec![Cell::BLANK; rows * cols];
         self.wrapped = vec![false; rows];
+        self.row_flags = vec![0; rows];
         self.dirty = vec![true; rows];
         self.first = 0;
         self.rows = rows;
@@ -58,14 +59,17 @@
         }
         let mut next = vec![Cell::BLANK; rows * cols];
         let mut wrapped = vec![false; rows];
+        let mut row_flags = vec![0; rows];
         for row in 0..rows.min(self.rows - dropped) {
             for col in 0..cols.min(self.cols) {
                 next[row * cols + col] = self.cells[self.phys_start(row + dropped) + col].clone();
             }
             wrapped[row] = cols == self.cols && self.row_wrapped(row + dropped);
+            row_flags[row] = self.row_flags[self.phys_row(row + dropped)];
         }
         self.cells = next;
         self.wrapped = wrapped;
+        self.row_flags = row_flags;
         self.dirty = vec![true; rows];
         self.first = 0;
         self.rows = rows;
EOF
cd "$REPO" && git apply --check "$HOME/plan9-row-flags.patch" && git apply "$HOME/plan9-row-flags.patch" && git status --short
```
Expected: seven ` M` lines (`content.rs`, `parser.rs`, `screen.rs`, `scrollback.rs`, `screen/edit.rs`, `screen/print.rs`, `screen/resize.rs`). If `git apply --check` fails (Task 7 was rejected, or your files differ), apply each hunk by hand from the patch text and report that you did.

- [ ] **Step 2: Verify behaviour is unchanged**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo test --release -p vt-core --test parser_goldens 2>&1 | grep "test result"
cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
```
Expected: `Finished …`; `test result: ok. 1 passed`; only `rust-done`.

- [ ] **Step 3: Measure against Task 7**

```bash
bash "$HOME/plan9-snapshot.sh" flags 2>&1 | tail -1
bash "$HOME/plan9-ab.sh" partC flags "$HOME/plan9-ab-flags.log"
```
Planning run (native lines; the wasm lines were not measured for this variant):

```text
ascii-heavy grapheme: partC 54.95-55.61 flags 54.04-54.82 (-1.7% median) noise
ascii-heavy scalar: partC 55.56-55.84 flags 54.87-54.93 (-1.5% median) noise
claude-long-50k grapheme: partC 48.03-48.57 flags 47.74-47.94 (-0.6% median) noise
claude-long-50k scalar: partC 79.42-80.04 flags 78.05-78.25 (-2.4% median) noise
edit-heavy grapheme: partC 88.13-88.92 flags 88.37-88.59 (0.1% median) noise
edit-heavy scalar: partC 88.41-88.93 flags 88.15-88.66 (-0.3% median) noise
```

- [ ] **Step 4: Decide**

Keep only if a native `claude-long-50k` line reads `faster` and no line reads `slower`. **Expected: not kept.** Then:

```bash
cd "$REPO" && git apply -R "$HOME/plan9-row-flags.patch" && git status --short
```
Expected: a clean status (nothing to commit in this task). Write the eight verdict lines into the report.

If kept (not expected): commit the seven files with the message `perf(vt-core): commit plain rows without per-cell style work (row flags)` and the trailer, and use the "kept" texts in Task 9. No new test file: the goldens (the `mirror` configuration trims by rows and bytes and fills the cold ring), `older_seams.rs` (history prepends) and `bulk_edits.rs` cover every path the patch touches.

---

### Task 9: Part C — gates, mirror wasm, docs

**Files:**
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` (rebuilt), `packages/terminal/CHANGELOG.md`, `TERMINAL.md` (§4.35), `docs/terminal/2026-09-19-terminal-reference-survey.md` (§1.12 row and status, §2.14 row and status, count sentence), `docs/terminal/2026-09-24-not-done-plain-language.md` (items 17, 19, intro)

**Interfaces:**
- Consumes: the verdicts of Tasks 7 and 8.
- Produces: the finished branch.

- [ ] **Step 1: Gate set G** (G1–G7). If Task 7 or 8 committed code, G2's ` M …vt_host.wasm` is committed in Step 3; otherwise restore the asset as G2 says and skip that commit.

- [ ] **Step 2: Docs** (texts for the expected outcome: bulk edits kept, row flags not kept; the alternatives follow each text)

(a) `packages/terminal/CHANGELOG.md` — insert as the first bullet under `## Unreleased` (before the Part B bullet of Task 6):

```markdown
- vt-core: erase/insert/delete a row slice at a time (roadmap Plan 9 Part C, survey §1.12). `ScreenGrid` erases (`EL`/`ED` on the cursor row, `ECH`) with one slice fill and inserts/deletes characters (`ICH`/`DCH`) with one slice rotation instead of cell by cell; nothing observable changes (`tests/bulk_edits.rs`, the goldens). Row flags (`styled`, `grapheme`) with a plain-row commit path were built and measured with no gain, and are not applied (`TERMINAL.md` §4.35). Both wasm artifacts and the daemon must be rebuilt.
```
If Task 7 was rejected, write this bullet instead:
```markdown
- vt-core: tests pin erase/insert/delete behaviour (`tests/bulk_edits.rs`). Plan 9 Part C measured slice-at-a-time edits and row flags; neither was faster beyond noise and neither is applied (`TERMINAL.md` §4.35).
```

(b) `TERMINAL.md` §4.35 — append after the `- Guards (Part B): …` bullet (directly before the blank line that precedes `## 5. Known gaps (not bugs, decisions pending)`):

```markdown
- **Part C: erase and insert on a row.** `screen/edit.rs` erases with one
  slice `fill` of the erase cell and inserts/deletes characters with one
  `rotate_right`/`rotate_left` of the row slice (`fill_cells`,
  `shift_cells`); `wrapped` is cleared exactly when the per-cell `set` used
  to clear it (an edit that reaches the last column, every ICH/DCH), and an
  empty span marks nothing dirty. Claude Code sends no ICH/DCH/ECH
  (`claude-long-50k`: 0 `@`, 0 `P`, 0 `X`, 32,808 `K`), so the gain is for
  shells and full-screen programs. **Row flags** after Ghostty
  (`src/terminal/page.zig:2020-2058`, behaviour only): a per-row
  `styled`/`grapheme` flag and a plain-row commit path in
  `scrollback::commit_row` were built and measured — no line faster beyond
  noise (numbers below) — so they are not applied.
  `hyperlink` would need no flag (the link id rides in `CellStyle.link`) and
  `wrapped` stays its own vector. The prototype's one bug (a prepended
  history chunk longer than `CHUNK_SIZE` underflowed a subtraction) was
  caught by `tests/older_seams.rs`.
- Part C measured (same method as Part B; bulk edits against Part B, then
  row flags against bulk edits):
```
followed by one indented `  - ` line per verdict line of Task 7 Step 5 and of Task 8 Step 3, verbatim, and the environment line as in Task 6. Then:
```markdown
- Guards (Part C): `tests/bulk_edits.rs` (passes on the tree before Part C
  too), `synthetic-edits-styled` in the goldens.
```
(Alternatives: if Task 7 was rejected, replace the first sentence of the Part C bullet with "Slice-at-a-time erase/insert (`fill_cells`, `shift_cells`) was built and measured — not faster beyond noise — and is not applied; `tests/bulk_edits.rs` pins the per-cell behaviour." If row flags were kept, replace "were built and measured — no line faster beyond noise (numbers below) — so they are not applied" with "are applied (`screen.rs` `row_flags`, `scrollback.rs` `commit_plain_row`, `content.rs` `push_text`)" and quote your numbers.)

(c) Survey — line 65: replace the whole line starting `| §1.12 | Not done |` with:

```text
| §1.12 | Not pursued | Roadmap Plan 9 — erase/insert/delete now fill and rotate a row slice instead of writing cell by cell (`screen/edit.rs`); the row flags themselves (`styled`, `grapheme`, a plain-row commit path) were built and measured with no gain and are not applied (`TERMINAL.md` §4.35). `hyperlink` needs no flag (the link id is in the style); `wrapped` stays its own vector. |
```
Line 868 (status under the §1.12 heading): replace the line starting `> **Status: Not done.** No \`RowFlags\`` with:
```text
> **Status: Not pursued.** Roadmap Plan 9 — the per-cell erase/insert/delete loops became slice fills and rotations (`fill_cells`, `shift_cells`); `RowFlags` (`styled`, `grapheme`) with a plain-row commit path were prototyped and measured: no workload faster beyond noise, so not applied. Numbers: `TERMINAL.md` §4.35.
```
(If row flags were kept: status `Done` and "applied" in both texts; the recount then gives `47 Done`, `8 Notpursued`.)

Line 85: replace the whole line starting `| §2.14 | Done |` with:
```text
| §2.14 | Done | Roadmap Plan 3 — title stack capped at 4,096 (oldest dropped), pending notifications at 16, titles at 1,024 bytes. There is no keyboard-mode stack to cap. The grapheme byte cap (256) was already in place. Roadmap Plan 9 did not adopt `vte::ansi::Handler` (§2.2), so the caps stay in `program.rs`. |
```
Line 1875 (status under the §2.14 heading): replace the line starting `> **Status: Done.** Roadmap Plan 3 — title stack capped at 4,096` with:
```text
> **Status: Done.** Roadmap Plan 3 — title stack capped at 4,096 (oldest dropped), pending notifications at 16, titles at 1,024 bytes. There is no keyboard-mode stack to cap. The grapheme byte cap (256) was already in place. Unchanged by roadmap Plan 9: `vte::ansi::Handler` was not adopted (§2.2), so the caps stay where Plan 3 put them (`crates/vt-core/src/program.rs:7-9`).
```
Recount with the `awk` command of Task 2 Step 4: expect `46 Done`, `1 N/A`, `12 Notdone`, `1 Notneeded`, `9 Notpursued`, `19 Partial`, and put those numbers into line 50 in the same words (`46 done, 19 partial, 12 not done, 9 not pursued, 1 not needed, 1 n/a`).

(d) Plain-language doc — replace item 17 (from the line starting `17. **Faster line edits (§1.12).**` through the line ending `*If done:* erasing and inserting in plain rows gets quicker.`) with:
```markdown
17. **Faster line edits (§1.12) — done differently (roadmap Plan 9).**
    Erasing and inserting text in a line now moves the whole stretch at
    once. The "nothing fancy on this row" markers were tried as well and
    made no difference, so they were left out.
```
If Task 7 was rejected, use instead:
```markdown
17. **Faster line edits (§1.12) — tried and dropped (roadmap Plan 9).**
    Neither moving whole stretches at once nor the row markers made a
    measurable difference.
```

Replace item 19's first line `19. **Safety caps (§2.14) — done (2026-09-25, roadmap Plan 3).** Programs can` with `19. **Safety caps (§2.14) — done (2026-09-25, roadmap Plan 3; unchanged by Plan 9).** Programs can`.

In the intro paragraph (lines 6-9), replace `items 19 and 20 have since been done, roadmap Plan 3); the 16 marked` with `items 19 and 20 have since been done, roadmap Plan 3; item 16 has been done and items 17 and 18 decided, roadmap Plan 9); the 16 marked`.

- [ ] **Step 3: Commit**

```bash
cd "$REPO" && git add backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
git commit -m "chore(terminal): rebuild the mirror wasm for Plan 9 Part C" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git add packages/terminal/CHANGELOG.md TERMINAL.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/terminal/2026-09-24-not-done-plain-language.md
git commit -m "docs(terminal): Plan 9 Part C — slice edits, row flags measured (TERMINAL.md §4.35, survey §1.12, §2.14)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
(Skip the first commit if `vt_host.wasm` is unchanged.) Expected: a clean status.

---

### Task 10: Clean up, push, report (do not merge)

- [ ] **Step 1: Check the branch and remove the scratch files**

```bash
cd "$REPO" && git status --short && git log --oneline origin/development..HEAD
ls packages/terminal/crates/vt-core/tests/*.proptest-regressions 2>/dev/null
rm -rf "$HOME/plan9-ansi-spike" "$HOME/plan9-bin" "$HOME/plan9-wasm" "$HOME/plan9-feel-baseline"
```
Expected: clean status; the commits of Tasks 1, 2, 3, 4, 5, 6 (two), 7, 9 (one or two), plus any gate fix; `integrity.proptest-regressions` only (it is committed already; no new `print_run.proptest-regressions` — if one exists, a proptest failed at some point: report its contents and delete it). Keep `$HOME/plan9-ab-*.log` until the report is written.

- [ ] **Step 2: Push**

```bash
cd "$REPO" && git push -u origin terminal/plan-9-parser-rework
```
Do not open a PR unless asked. Do not merge.

- [ ] **Step 3: Completion report** (your final message) containing:
1. The Part A decision and whether the spike output matched Task 2 Step 2 line for line.
2. Every gate of every G run (Tasks 2, 6, 9) with its quoted last lines, or `not run: <reason>`.
3. The verdict lines of Task 6 Step 2, Task 7 Step 5 and Task 8 Step 3, with the environment line, and each keep/discard decision.
4. The Task 1 Step 3 golden sample lines, and whether they matched the planning Mac's.
5. Any quoted edit text that was not found as written, and what you did.
6. Real-app checklist: nothing user-visible should change. After `npm run tauri:dev` (or the rebuilt daemon + app), open a Claude Code session and a zsh pane: (a) Claude's banner, spinner, markdown reply and a long streamed answer look exactly as before; (b) in zsh, `printf 'abc\e[3D\e[2@XY\e[K\n'`, `vim` (open, edit, quit), `htop` (quit with `q`) and `seq 1 200000` render as before; (c) optional — whether a pane's `TerminalCore` can be reached from the renderer's devtools console in Operator is not known; if it can, its wasm object's `unknown_sequences()` returns a short list such as `["1 CSI >4;2m", …]` (the ring itself is covered by tests); (d) typing, selection and copy still work. Restart the daemon and the app after the rebuild (`TERMINAL.md` §3.5).
