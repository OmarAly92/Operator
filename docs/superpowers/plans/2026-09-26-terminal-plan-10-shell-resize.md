# Terminal Plan 10 — Shell Resize Reflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **If the superpowers skills are not installed in your environment, run the process by hand:** one fresh implementer subagent per task (give it the task text, Global Constraints, Review Focus and Design decisions), then one spec-compliance review subagent and one code-quality review subagent per task, fix what they find, and after the last task one whole-branch review subagent over `git diff origin/development...HEAD`. **If there is no subagent tool either, say so in your report, implement task by task yourself, and after each task review its diff against the task text before moving on.**

**Goal:** In a shell at its prompt, a window resize keeps the prompt where the shell expects it (so the shell's own redraw replaces it instead of leaving a stale copy in scrollback), reflows the output above it, keeps the cursor on its prompt, and pulls scrollback back onto the screen when the window grows — while every other state (a command running, the alternate screen, no shell integration, every Claude Code pane, the pty-host mirror) keeps today's behaviour byte for byte.

**Architecture:** A differential safety net comes first: `tests/resize_goldens.rs` replays 12 seeded streams whose resizes all happen outside an owned prompt (and, for the renderer-free configurations, at one) through the Plan 9 golden harness and stores digests generated on the **unmodified** tree. Then `TerminalCore::resize` passes the line editor state to a new `Parser::resize_for` (`parser/resize.rs`); only when the state is `Owned`, the primary screen is active and the core reflows on resize does it take the new path: `ScreenGrid::resize_keeping_prompt` (`screen/prompt.rs`) sends the rows above the prompt start (the open block's first row) to scrollback — where the existing word-aware rewrap (§4.2–4.4) reflows them — and keeps the prompt rows unrewrapped with the cursor at the same offset (Kitty's behaviour, clean-room; chosen over Ghostty's reflow-and-clear by measuring zsh, bash and fish). `Parser::pull_back` then moves the newest scrollback rows back onto the top of the screen so the prompt keeps its distance from the bottom, but only rows that commit back byte for byte (`Content::truncate_to`, `AttributeMap::truncate_to`, `RowIndex::pop_completed`). Flat and stable row numbers never change, so blocks, find hits, the scroll anchor and the older-output floor are untouched.

**Tech Stack:** Rust 1.96.0 (`vt-core`, `vt-wasm`, `vt-host`), wasm32 + wasm-bindgen 0.2.127, Node ≥ 20 (`node:test` shell tests over tmux), Go ≥ 1.25.7 (pty-host and integration tests only), TypeScript 5.9 + vitest 4.1.8 (unchanged suites), Playwright (benches).

**Spec:** `docs/terminal/2026-09-24-terminal-roadmap-design.md` "Plan 10 — Shell resize reflow (§1.5, §2.4, §5.4)" and "Rules every plan obeys"; survey `docs/terminal/2026-09-19-terminal-reference-survey.md` §1.5, §2.4, §5.4 (and §1.3 for stable rows); `TERMINAL.md` end to end — §2 (model, stable rows, stale runs), §4.1–4.4 (eviction and rewrap), §4.5–4.8 (SIGWINCH, the upstream Claude Code duplicate), §4.10 (resize policy), §4.17–4.21 (integrity, trims, history chunks), §4.28 (find), §4.33 (older output), §4.35 (Plan 9 goldens and the fast-path hazard), §6 (verify and ship).

**Tree this plan was written and proven against:** `origin/development` @ `1763df9e8` ("docs(terminal): add Plan 9's deferred real-app checks"). Every code block below was built and tested in scratch worktrees of that commit on 2026-09-26 (macOS arm64, Rust 1.96.0, Go 1.25.12, Node, tmux 3.6b, zsh 5.9, bash 3.2.57 and 5.3.20, fish 4.8.1): at the end of each task `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` and `cargo test` green; the 53 Plan 9 goldens and the 12 new resize goldens unchanged; renderer wasm + `ts/core` 179, `renderer-dom` 985, `react` 134, `editor` 175, `completions` 109 tests; `check:boundaries` pass; pty-host Go tests `ok` with the rebuilt `vt_host.wasm`; `TestShellBlocks*` `ok` (13.3 s); frontend `tsc` clean; `bench:feel` zero pixel diff against a baseline recorded on the unmodified tree; `bench:agent:gate` PASS; `bench:agent:scroll` 60,134 of 60,134; `bench:selection` PASS (macOS); shell tests zsh 22/22, bash 11/11, fish 7/7.

## Global Constraints

- Branch `terminal/plan-10-shell-resize` from `origin/development`. Never commit to `development` or `master`, never merge, never force-push.
- Commits name explicit paths only: `git add <path> …`. Never `git add -A`, `git add .`, `git commit -a` or `git stash`.
- Every commit message ends with the trailer line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- No comments in new code (Rust, JS, tests).
- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no Operator name, path or concept under `crates/`, `ts/`, `shell/` code or test data.
- Licences: Ghostty (MIT) and Alacritty (Apache-2.0/MIT) are followed for **behaviour only** — no code is adapted, so no attribution file is added. Kitty (GPL-3.0) is **clean-room only**: this plan uses the survey's description of its behaviour (§5.4) and nothing else; do not open Kitty's source. Warp (AGPL-3.0) is not read.
- **Behaviour outside an owned prompt must not change.** `tests/parser_goldens.rs` with its 53 `tests/goldens/*.golden` files and the 12 `tests/goldens/resize-*.golden` files that Task 1 generates on the unmodified tree are never regenerated on this branch. If a golden fails after a change, the change is wrong — fix the code, never the golden. Every existing test must pass unmodified.
- The new path is taken only when **all** hold: the line editor is `Owned` (OSC 7000 `input-ready` seen and no `input-released` or alternate-screen enter since), `Parser.alt` is `None`, the core reflows on resize (`reflow_on_resize`, false in agent-TUI mode and in the pty-host mirror), eviction is recorded and the scroll region is the full screen. Anything else runs today's code unchanged.
- The pty-host mirror (`crates/vt-host`) is **not** changed; it keeps `set_reflow_on_resize(false)` (`crates/vt-host/src/lib.rs:39`), which by the rule above keeps it on today's path. Its `vt_host.wasm` is still rebuilt and committed because vt-core changed.
- No file under `packages/terminal` may exceed 600 lines (`npm run check:boundaries`). Planned sizes: `crates/vt-core/src/lib.rs` 594 → 595, `src/parser.rs` 551 → 531, `src/parser/resize.rs` new 61 → 144, `src/screen/prompt.rs` new 63 → 81, `src/screen.rs` 448 → 449, `src/content.rs` 231 → 270, `src/attribute_map.rs` 173 → 204, `src/row_index.rs` 442 → 453, `src/row_index/tests.rs` 315 → 333, `src/block_grid.rs` 434 → 438, `src/block_grid/tests.rs` 224 → 236, `tests/prompt_resize.rs` new 223 → 448, `tests/prompt_resize_integrity.rs` new 110, `tests/resize_goldens.rs` new 194, `shell/pty.mjs` 79 → 92, `shell/zsh.test.mjs` 320 → 332, `shell/bash.test.mjs` 267 → 278, `shell/fish.test.mjs` 134 → 151.
- A `vt-core` change is not live until **both** wasm artifacts are rebuilt (`TERMINAL.md` §6): the renderer's (`npm run build:wasm -- --force`, gitignored) and the host mirror's (`cargo build --release -p vt-host --target wasm32-unknown-unknown`, copied to `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`, **committed**), then the pty-host Go tests and the `TestShellBlocks*` integration tests.
- This plan changes no pixels in any bench fixture (none contains `input-ready`; Task 0 Step 4 checks). `bench:feel` must stay at zero diff against the Task 0 baseline recorded in **this** environment (the committed baselines were recorded on the owner's Mac). Never commit re-recorded baselines (`packages/terminal/bench/agent-session/baselines/**`); `bench:feel -- --record` and `bench:affordances` rewrite committed PNGs — restore with `git checkout -- packages/terminal/bench/agent-session/baselines && git clean -fdq packages/terminal/bench/agent-session/baselines`.
- Claude Code's one duplicated row after a width change is **upstream** (Claude Code's own SIGWINCH repaint, `TERMINAL.md` §4.8). Do not try to fix it; Claude Code panes run in agent-TUI mode without shell integration and never reach the new path.
- New `TERMINAL.md` section number: **§4.36**.
- Docs and the report cite `file:line` or write "not known". Tool gaps are reported, not hidden: when a command cannot run, write `not run: <reason>`. `bench:selection` sends Meta+C, which Linux Chromium does not treat as copy: on Linux record `not run: Linux copy chord`.
- Cloud environment notes (from earlier waves): Playwright's CDN may answer 403 — symlink the pinned revision directory names under `/opt/pw-browsers` to the preinstalled Chromium (Task 0 Step 2). Go: `export GOTOOLCHAIN=auto`; for `build:daemon` put the downloaded `go1.25.7` (or newer) first on `PATH`. No reference repositories are available and none is needed: every reference fact used is quoted below. If you want to read one anyway, clone outside the repository: `git clone https://github.com/ghostty-org/ghostty && git -C ghostty checkout b32f20f3e` (Ghostty, the commit the survey cites) or `git clone https://github.com/alacritty/alacritty && git -C alacritty checkout d692748d`. Never clone or read Kitty.

## Review Focus

1. **The prompt start is not where the open block says.** The open block's first row can be in scrollback (a prompt taller than the screen), after the cursor (the shell moved up), missing (fish emits `input-ready` before its `133;A`), or re-opened mid-prompt (fish re-emits `133;A` when it repaints). Expected: the kept region is clamped to `[prompt start or cursor row, cursor row]`, and a region that cannot fit the new height falls back to today's path. Pinned by `prompt_resize.rs` `fish_repaints_on_the_next_key_from_the_first_row_of_the_kept_prompt`, `a_prompt_taller_than_the_new_screen_takes_the_old_path`, and `prompt_resize_integrity.rs` (prompts of 0–3 rows, sizes down to 1×1, 32 seeds × 300 steps, `verify_integrity` + cell spans after each step, ≥ 200 resizes at a prompt).
2. **A row pulled back from scrollback must commit again byte for byte.** Hanging indents, word-cut continuation rows, trailing blanks, styles that change inside a cluster, hyperlinks, wide and combining characters, stale (cold) rows. Expected: identical text, style runs, cell spans and wrapped flags after the rows scroll back into scrollback; a row that would differ stops the pull. Pinned by `rows_pulled_back_commit_again_byte_for_byte` (both width modes, SGR 16/truecolor, OSC 8, `中`, `e\u{301}`) and `pull_back_stops_at_a_row_that_cannot_be_restored_exactly`.
3. **A narrower window cutting the kept prompt through a wide character.** Expected: the half-cut character becomes a blank, never a half glyph or a width-2 span on a width-1 cell. Pinned by `a_wide_character_cut_by_a_narrower_prompt_row_is_blanked_whole` and `common::check` (every span ≤ 2 cells, inside its row) in every test.
4. **Claude Code panes and every non-prompt state stay byte-identical.** Expected: `parser_goldens` (53 recordings × 4 configurations) and `resize_goldens` (12 streams) unchanged, `bench:feel` zero pixel diff, `bench:agent:gate` and `bench:agent:scroll` unchanged. Pinned by those, plus `a_resize_while_a_command_runs_still_moves_the_frame_to_scrollback`, `a_resize_on_the_alternate_screen_leaves_the_primary_frame_alone`, `agent_tui_mode_keeps_truncating_in_place_at_a_prompt`.
5. **Things keyed by rows after a pull-back.** Blocks, find hits and the older-output floor address stable rows; a pull-back moves rows between scrollback and screen without renumbering them, and truncates content bytes that a find session had already scanned. Expected: blocks cover the same text, every find hit points at a row containing the needle, the floor and the first stable row are unchanged, and an older-output chunk still lands after every scrollback row was pulled back. Pinned by `blocks_keep_their_text_and_the_open_prompt_block_starts_on_the_prompt`, `find_hits_point_at_their_text_after_rows_are_pulled_back`, `the_older_output_floor_and_first_stable_row_survive_a_prompt_resize`, `an_older_output_chunk_still_lands_after_a_prompt_resize_pulled_every_row_back`.

---

## Design decisions (each one decided; evidence in brackets)

### What the shells do on a resize at their prompt (measured 2026-09-26)

Captured with the repository's own integration scripts (`packages/terminal/shell/{zsh.sh,bash.sh,fish.fish}`, `OPERATOR_TERMINAL_SUPPRESS_PROMPT=0`), under a raw pty (Python `pty.fork`, `TIOCSWINSZ`, `TERM=xterm-256color`) and under tmux 3.6b (`resize-window`, `pipe-pane`), resizing 80×24 → 40×24 → 100×24 → 100×30 → 30×20 at an idle prompt, with and without typed text, single-line and two-line prompts:

| Shell | Bytes written right after the resize | What it assumes |
|---|---|---|
| zsh 5.9 | `\r\r`, then **one cursor-up per row the prompt + buffer occupied at the OLD width, minus one** (`ESC[A`, or `ESC M` under tmux), then `ESC[0m ESC[27m ESC[24m ESC[J`, then the whole prompt and buffer. A 118-column prompt: 80→40 moved up 1 (2 rows at 80), 40→100 moved up 2 (3 rows at 40). | its old rows are still where it drew them, un-rewrapped |
| bash 3.2 / 5.3 | single-line prompt: `\r ESC[K` then up (old rows − 1) (5.3 clears each row on the way up: `\r ESC[K \r ESC[A ESC[K \r …`) and the prompt + buffer; **multi-line prompt: only the last line** (`\r ESC[K` + `line-two $ ` + buffer), no up-move | the same; the lines above the last are left to the terminal |
| fish 4.8.1 | **nothing** on a width change; on a height change only `CSI 6n` and `CSI 0c` queries. On the **next key** it writes `\r`, up (old prompt rows − 1), `\r ESC[K`, a fresh `OSC 133;A`, the prompt and buffer, `ESC[J` (raw pty) — under tmux it only moves up and rewrites the input line | the same, lazily |
| any, prompt suppressed (Operator's shell panes, `backend/internal/service/shellterm/service.go:439` `SuppressPrompt: true`) | zsh `\r ESC[0m ESC[27m ESC[24m ESC[J ESC[K`, bash `\r ESC[K`, fish nothing | — |

All three count their redraw from where they drew the prompt **at the old width**. Replaying the 15 captured zsh/bash sessions through vt-core (4 resizes each): the **unmodified tree ends with 5 copies of a visible prompt** (the original plus one stale copy per resize — the legacy path evicts the prompt into scrollback and resets the cursor to (0,0), so the shell's up-move is clamped and it draws a second prompt), with 0 extra copies when the prompt is suppressed; the **Plan 10 tree ends with exactly one** in every session.

### Decision 1 — keep the prompt rows, do not rewrap or clear them (Kitty's answer, clean-room)

- Ghostty's model (reflow everything, then clear from the last `OSC 133;A` row down, `src/terminal/Screen.zig:2232-2290`) changes the prompt's row count before the shell redraws. zsh and fish then move up by the old count: a **wider** window makes them overshoot into the output above the prompt, and zsh's `ESC[J` erases those output rows; a **narrower** window leaves the first reflowed prompt rows above the redraw as a stale partial prompt; and fish, which does not redraw until the next key, shows a blank prompt meanwhile.
- The survey's description of Kitty (§5.4: copy the current prompt's rows out, rewrap everything else, put them back unwrapped where the shell's SIGWINCH redraw overwrites exactly them) matches what all three shells assume. **Chosen.** Implementation: the rows from the prompt start to the bottom of the cursor's content (`max_cursor_row`) stay on the screen, each cut at the new width (a wide character cut in half becomes a blank) or padded, with the cursor at the same row offset and its column clamped (`pending_wrap` and the saved cursor are dropped, exactly as today's `resize_cells` does, `crates/vt-core/src/screen/resize.rs:78-79`); the rows' `wrapped` flags survive only a height-only resize (`resize.rs:65`). Trailing blank rows below the cursor are dropped first when the new height is too small; if the region still does not fit, today's path runs.
- Known and accepted: bash redraws only the last line of a multi-line prompt, so its earlier lines stay cut at a narrower width (xterm does the same). Not needed: `redraw=` on `OSC 133;A` (survey §1.5 proposal) — no measured shell needs a different treatment. In Operator's own shell panes the prompt is suppressed, so the region is one empty row and the visible change there is small; the fix is for visible prompts (any host with `suppressPrompt: false`, or a user who unsets `OPERATOR_TERMINAL_SUPPRESS_PROMPT`).

### Decision 2 — the rows above the prompt reflow through scrollback, not in place

- The rows above the prompt start are recorded as evicted (the existing `record_eviction`, so every row is committed, blank or not — §4.1) and the width change rewraps them with the existing word-aware, hanging-indent rewrap (`RowIndex::rewrap_hot`, §4.2–4.4). A cell-level in-place reflow (Alacritty's `grow_columns`/`shrink_columns`, `alacritty_terminal/src/grid/resize.rs:101-389`) would cut these rows at the exact column and bring back the "vari|able" cut of §4.3 for the rows still on screen. Their flat row numbers do not change (a row that moves from screen to scrollback keeps its flat index), so no remap is needed beyond the rewrap's own.

### Decision 3 — pull back on growth, only rows that restore exactly

- After the eviction and rewrap, rows are pulled from the end of scrollback onto the top of the screen so the prompt keeps its distance from the bottom: width-only change → as many rows as were above the prompt; growth by n → n more (Alacritty `grow_lines`, `alacritty_terminal/src/grid/resize.rs:43-69`; Ghostty `pull_scrollback`, `src/terminal/PageList.zig:1233-1247`); shrink by n → n fewer, after first dropping blank rows below the prompt (Alacritty `shrink_lines`, `resize.rs:78-99`; Ghostty `trimTrailingBlankRows`, `PageList.zig:3167-3202`) — all behaviour only.
- A row is pulled only if decoding it into cells and committing those cells again (`scrollback::commit_row` into a scratch `Content`/`RowIndex`/`AttributeMap`) gives the **same bytes and the same style runs**, and its `indent` is 0, its clusters all have width ≥ 1, and it is not inside a stale run. The first row that fails stops the pull (a word-cut continuation shorter than the pane, a hanging-indent row, a row whose width exceeds the pane, an unwrapped row ending in a default blank). The pulled rows keep their flat and stable numbers. Content, styles and the row index are truncated at the first pulled row (`Content::truncate_to`, `AttributeMap::truncate_to`, `RowIndex::pop_completed`); a find session then rescans history once (`FindSession::update` resets when the settled end moves back, `crates/vt-core/src/find.rs:183`).
- Not taken: Ghostty's `set_pull_scrollback(false)` for ConPTY hosts. The pty-host mirror is the only core in the pty-host and it is unchanged; whether a Git Bash pane on Windows (ConPTY repaints its own viewport after a resize) looks better or worse is **not known** — recorded in §4.36.

### Decision 4 — where the state comes from

- `TerminalCore::resize` (`crates/vt-core/src/lib.rs:523-532`) already flushes a pending DEC 2026 block first; it now passes `self.line_editor.state()` (read after that flush) to `Parser::resize_for`. `LineEditorState::Owned` is set only by `OSC 7000;v=1;input-ready=1` and cleared by `input-released` and the alternate screen (`crates/vt-core/src/line_editor.rs:30-42`). No Claude Code fixture contains `input-ready` (Task 0 Step 4), and Claude Code panes run in agent-TUI mode (`reflow_on_resize = false`, `crates/vt-core/src/parser.rs:432-439`), so they are excluded twice.
- The prompt start is the open block's first flat row (`BlockGrid::open_block_ref` + `flat_extent`), minus the completed rows, clamped to the cursor row; with no open block it is the cursor row.

### Decision 5 — the mirror stays as it is

`crates/vt-host/src/lib.rs:39` turns reflow off for tmux `capture-pane` semantics; the attach replay (`clip_row`, §4.7) and the history-chunk row space (§4.20–4.21) are built on today's `resize_cells`. The pane and the mirror already number rows differently after any shell width change (`TERMINAL.md` §5, "The seam between loaded rows and the pane is exact only at one width"), so keeping the prompt in the pane adds no new mismatch class. The mirror's `vt_host.wasm` is rebuilt only because vt-core changed; its behaviour is pinned by the `mirror` configuration of both golden sets.

---

## File map

| File | Task | Responsibility |
|---|---|---|
| `packages/terminal/crates/vt-core/tests/resize_goldens.rs` (new), `tests/goldens/resize-*.golden` (new, 12, generated) | 1 | differential net for every non-prompt resize |
| `packages/terminal/crates/vt-core/src/screen/prompt.rs` (new), `src/screen.rs` | 2, 3 | keep the prompt rows; push pulled rows on top |
| `packages/terminal/crates/vt-core/src/parser/resize.rs` (new), `src/parser.rs`, `src/lib.rs` | 2, 3 | `resize` moved, `resize_for`, `resize_at_prompt`, `pull_back`, `row_cells` |
| `packages/terminal/crates/vt-core/src/block_grid.rs`, `src/block_grid/tests.rs` | 2 | `open_block_ref` |
| `packages/terminal/crates/vt-core/src/{content.rs,attribute_map.rs,row_index.rs,row_index/tests.rs}` | 3 | truncate content/styles, pop a completed row |
| `packages/terminal/crates/vt-core/tests/prompt_resize.rs` (new) | 2, 3 | behaviour tests |
| `packages/terminal/crates/vt-core/tests/prompt_resize_integrity.rs` (new) | 4 | seeded integrity sequence |
| `packages/terminal/shell/{pty.mjs,zsh.test.mjs,bash.test.mjs,fish.test.mjs}` | 5 | pin the shells' redraw behaviour the design relies on |
| `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` | 6 | rebuilt mirror |
| `TERMINAL.md`, survey, plain-language doc, roadmap spec, `packages/terminal/CHANGELOG.md` | 7 | §4.36, status lines, real-app checks, changelog |

---

## Gate set G (run in Task 6 and again before the report; each command, then what it must print)

- [ ] **G1 Rust**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
cargo test -p vt-core --features trace --test integrity 2>&1 | grep "test result"
cargo test --release -p vt-core --test parser_goldens --test resize_goldens --test prompt_resize --test prompt_resize_integrity 2>&1 | grep "test result"
cd "$REPO/packages/terminal/crates/vt-core/tests/goldens" && sha256sum -c --quiet "$HOME/plan10-goldens.sha256" && echo goldens-unchanged
```
Expected: `Finished …` from clippy; only `rust-done`; `test result: ok. 8 passed` (the `trace` build); four `test result: ok.` lines, in cargo's order `parser_goldens` 1, `prompt_resize` 20, `prompt_resize_integrity` 1, `resize_goldens` 1 passed; `goldens-unchanged`.

- [ ] **G2 Both wasm builds**

```bash
cd "$REPO/packages/terminal" && cargo build --release -p vt-host --target wasm32-unknown-unknown 2>&1 | tail -1
cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
npm run build:wasm -- --force 2>&1 | tail -1 && npm run build:ts 2>&1 | tail -1
git -C "$REPO" status --short backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
```
Expected: `build-wasm: vt_core.js, vt_core.d.ts, vt_core_bg.wasm, vt_core_bg.wasm.d.ts ready`; the status line shows ` M …vt_host.wasm`.

- [ ] **G3 TS suites, boundaries, node tests**

```bash
cd "$REPO/packages/terminal" && for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  "); done
npm run check:boundaries 2>&1 | tail -2
node --test ./scripts/browser-types.test.mjs ./scripts/spawn-recipe-package.test.mjs ./bench/agent-session/fixtures.test.mjs ./bench/agent-session/session-api.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"
```
Expected: the same five `Tests  N passed (N)` counts as Task 0 (planning: 179, 985, 134, 175, 109 — no TS file changes in this plan); `boundary check passed`; `ℹ pass 7`, `ℹ fail 0`.

- [ ] **G4 Go: pty-host and shell-block integration**

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -3
go vet ./internal/adapters/runtime/ptyhost/...
env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT go test ./internal/integration/ -run 'TestShellBlocks' -count=1 2>&1 | tail -2
```
Expected: three `ok` lines; no vet output; `ok  	github.com/OmarAly92/operator/backend/internal/integration` (≈13 s in planning). `TestProcessEnvironmentLetsOverridesWin` is a known pre-existing failure (`TERMINAL.md` §5); if it also fails in Task 0, it is not yours. If zsh is absent the integration tests skip (`zsh unavailable`): report `integration: skipped — zsh unavailable`.

- [ ] **G5 Frontend type check**

```bash
cd "$REPO/frontend" && npx tsc --noEmit -p . && echo frontend-tsc-ok
```

- [ ] **G6 Playwright benches**

```bash
cd "$REPO/packages/terminal" && cp -R "$HOME/plan10-feel-baseline/." bench/agent-session/baselines/ && npm run bench:feel 2>&1 | tail -2
git -C "$REPO" checkout -- packages/terminal/bench/agent-session/baselines && git -C "$REPO" clean -fdq packages/terminal/bench/agent-session/baselines
npm run bench:agent:gate 2>&1 | tail -1
npm run bench:agent:scroll 2>&1 | tail -3 | cut -c1-200
npm run bench:selection 2>&1 | tail -2
npm run bench:affordances -- --action hover 2>&1 | tail -2
git -C "$REPO" checkout -- packages/terminal/bench/agent-session/baselines && git -C "$REPO" clean -fdq packages/terminal/bench/agent-session/baselines
git -C "$REPO" status --short
```
Expected: `PASS feel gate: zero pixel diff`; `PASS agent-session gate`; three JSON lines from the scroll gate, the first with `"total":60134,"covered":60134` (planning run), exit 0; `bench:selection` `PASS selection survived 21 repaints` on macOS — on Linux write `not run: Linux copy chord`; affordances writes screenshots (never diffed); the final `git status` shows nothing under `bench/agent-session/baselines`.

- [ ] **G7 Daemon binary**

```bash
cd "$REPO" && npm --prefix frontend run build:daemon 2>&1 | tail -2
```
Expected: builds `frontend/daemon/opr` (it embeds `vt_host.wasm`). If the environment cannot build it: `not run: <reason>`.

- [ ] **G8 Real shells**

```bash
cd "$REPO/packages/terminal" && for s in zsh bash fish; do node --test shell/$s.test.mjs 2>&1 | grep -E "^ℹ (pass|fail|skipped)" | tr '\n' ' '; echo " <- $s"; done
```
Expected (planning, macOS): zsh `ℹ pass 22 ℹ fail 0 ℹ skipped 0`, bash `ℹ pass 11 ℹ fail 0 ℹ skipped 0`, fish `ℹ pass 7 ℹ fail 0 ℹ skipped 0`. With fish older than 4.0 the fish tests guarded by `nativeOsc133Skip` (including this plan's) are skipped — report `fish <version>: new fish test skipped (fish < 4)`.

---

### Task 0: Branch, toolchains, baselines

**Files:** none committed.

**Interfaces:**
- Consumes: nothing.
- Produces: `$REPO` (exported), the branch, `$HOME/plan10-feel-baseline/` (this machine's `bench:feel` picture of the unmodified tree), `$HOME/plan10-goldens.sha256` (digests of the 53 Plan 9 goldens, extended in Task 1), your Task 0 test counts.

- [ ] **Step 1: Branch**

```bash
export REPO="$(git rev-parse --show-toplevel)"
cd "$REPO" && git fetch origin && git checkout -b terminal/plan-10-shell-resize origin/development
git log --oneline -1
```
Expected: `1763df9e8 docs(terminal): add Plan 9's deferred real-app checks` (or a later commit; if later, every edit below quotes the text it replaces — apply it by that text, and if a quoted text is not found, stop and report the file and the quote).

- [ ] **Step 2: Toolchains**

```bash
cd "$REPO/packages/terminal" && rustup show active-toolchain && rustup target list --installed | grep wasm32
wasm-bindgen --version || cargo install wasm-bindgen-cli --version 0.2.127 --locked
wasm-bindgen --version
export GOTOOLCHAIN=auto
cd "$REPO/backend" && go version
node --version
```
Expected: `1.96.0-…`, `wasm32-unknown-unknown`, `wasm-bindgen 0.2.127` exactly (`scripts/build-wasm.mjs` refuses any other), a Go version ≥ `go1.25.7`, Node ≥ 20. Keep `GOTOOLCHAIN=auto` exported.

```bash
sudo apt-get update -qq && sudo apt-get install -y -qq zsh bash tmux fish
zsh --version; bash --version | head -1; tmux -V; fish --version
```
If `fish --version` is older than 4.0, try `sudo add-apt-repository -y ppa:fish-shell/release-4 && sudo apt-get update -qq && sudo apt-get install -y -qq fish && fish --version`; if that fails too, keep the old fish and report the new fish test as skipped (G8). Without `sudo`/`apt`, write `not run: no package manager` for the shells you cannot install.

```bash
cd "$REPO/packages/terminal" && npm ci --no-audit --no-fund
cd "$REPO/frontend" && npm ci --no-audit --no-fund
cd "$REPO/packages/terminal" && npx playwright install chromium
```
If `playwright install` fails with HTTP 403 (CDN blocked): `ls /opt/pw-browsers`, read the directory names Playwright wants from the error (`chromium-<rev>`, `chromium_headless_shell-<rev>`), and symlink each wanted name under `/opt/pw-browsers` to the preinstalled directory of the same kind, e.g. `ln -s /opt/pw-browsers/chromium-<have> /opt/pw-browsers/chromium-<want>`; then `export PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers`. Never commit anything for this.

- [ ] **Step 3: Baselines of the unmodified tree**

```bash
cd "$REPO/packages/terminal" && cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-baseline-done
cd "$REPO/packages/terminal/crates/vt-core/tests/goldens" && sha256sum *.golden > "$HOME/plan10-goldens.sha256" && wc -l < "$HOME/plan10-goldens.sha256"
cd "$REPO/packages/terminal" && npm run build:wasm -- --force 2>&1 | tail -1 && npm run build:ts 2>&1 | tail -1
for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  "); done
npm run check:boundaries 2>&1 | tail -2
for s in zsh bash fish; do node --test shell/$s.test.mjs 2>&1 | grep -E "^ℹ (pass|fail|skipped)" | tr '\n' ' '; echo " <- $s"; done
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -3
env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT go test ./internal/integration/ -run 'TestShellBlocks' -count=1 2>&1 | tail -2
```
Expected (planning run): no FAILED/panicked line; `53`; the five vitest counts 179, 985, 134, 175, 109; `boundary check passed`; shells zsh 21, bash 10, fish 6 passing (one fewer each than G8 — the new tests do not exist yet); three `ok` lines; integration `ok`. Record your counts — G3 and G8 compare against them.

```bash
cd "$REPO/packages/terminal" && npm run bench:feel -- --record 2>&1 | tail -1
rm -rf "$HOME/plan10-feel-baseline" && cp -R bench/agent-session/baselines "$HOME/plan10-feel-baseline"
git -C "$REPO" checkout -- packages/terminal/bench/agent-session/baselines && git -C "$REPO" clean -fdq packages/terminal/bench/agent-session/baselines
npm run bench:agent:gate 2>&1 | tail -1
git -C "$REPO" status --short
```
Expected: `recorded feel baselines`; `PASS agent-session gate` (if it fails here, record it as pre-existing); an empty `git status`.

- [ ] **Step 4: Confirm no recorded stream reaches the new path**

```bash
cd "$REPO/packages/terminal" && grep -c "input-ready" bench/agent-session/fixtures/*/recording; grep -rl "input-ready" crates/vt-core/tests/ref | wc -l; grep -c "input-ready" crates/vt-core/tests/golden_support/synthetic.rs
```
Expected: `…/claude-spinner-10s/recording:0`, `…/claude-markdown-reply/recording:0`, `…/claude-long-50k/recording:0`, then `0`, then `0`. (If any is non-zero, stop and report: the goldens would no longer prove "no change".)

---

### Task 1: Differential net — resize goldens generated on the unmodified tree

**Files:**
- Create: `packages/terminal/crates/vt-core/tests/resize_goldens.rs`
- Create (generated): `packages/terminal/crates/vt-core/tests/goldens/resize-{no-integration,running,alt-screen,at-prompt-mirror-agent}-{1,2,3}.golden`

**Interfaces:**
- Consumes: `tests/golden_support/mod.rs` (`replay(&[u8], &[Size], &Config) -> Vec<String>`, `Size { offset, cols, rows }`, `Config { name, graphemes, agent_tui, mirror, odd_chunks }`, `CONFIGS: [Config; 4]`), `golden_support::synthetic::Rng` (`new(seed)`, `below(bound)`, `pick(&[&[u8]])`).
- Produces: the test `resizes_outside_an_owned_prompt_match_the_goldens_recorded_before_prompt_reflow`, which every later task must keep green. Streams: `no-integration` (never `input-ready`: every resize is `Unknown`), `running` (resizes only between `input-released`/`133;C` and `133;D`), `alt-screen` (resizes on the alternate screen and right after leaving it — still `Released`), all in the 4 configurations; `at-prompt-mirror-agent` (resizes at an owned prompt) in the `mirror` and `agent-odd` configurations only, which must not change either.

This task must run **before any source change** — the goldens are the unmodified tree's behaviour.

- [ ] **Step 1: Create the test file**

Create `packages/terminal/crates/vt-core/tests/resize_goldens.rs`:

```rust
#[allow(dead_code)]
mod golden_support;

use std::fs;
use std::path::PathBuf;

use golden_support::synthetic::Rng;
use golden_support::{replay, Config, Size, CONFIGS};

const PROMPT_START: &[u8] = b"\x1b]133;A\x07";
const PROMPT_READY: &[u8] = b"\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07";
const COMMAND_START: &[u8] = b"\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07";
const COMMAND_END: &[u8] = b"\x1b]133;D;0\x07";
const PROMPTS: [&[u8]; 4] = [
    b"~/project $ ",
    b"line-one-of-a-long-prompt-/home/someone/projects/a/b/c/d/e/f\r\nline-two $ ",
    "\u{65e5}\u{672c}\u{8a9e}\u{306e}\u{30d7}\u{30ed}\u{30f3}\u{30d7}\u{30c8} > ".as_bytes(),
    b"",
];
const TEXT: [&[u8]; 12] = [
    b"plain words that wrap when the pane is narrow enough to cut them ",
    "\u{4e2d}\u{6587}\u{5b57}".as_bytes(),
    b"\x1b[1;32mgreen\x1b[0m ",
    b"\x1b[48;5;236m band with a background \x1b[0m",
    b"  - a bullet that hangs its continuation under the text ",
    "e\u{301}".as_bytes(),
    "\u{1f44d}\u{1f3fd}".as_bytes(),
    b"\t",
    b"\x1b[K",
    b"x",
    b"\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\",
    b"0123456789",
];
const SIZES: [(usize, usize); 8] = [
    (80, 24),
    (40, 24),
    (100, 30),
    (30, 12),
    (120, 40),
    (61, 17),
    (7, 5),
    (80, 3),
];

#[derive(Clone, Copy, PartialEq, Eq)]
enum Family {
    NoIntegration,
    Running,
    AltScreen,
    AtPrompt,
}

fn line(rng: &mut Rng, out: &mut Vec<u8>) {
    for _ in 0..rng.below(8) {
        out.extend_from_slice(rng.pick(&TEXT));
    }
    out.extend_from_slice(b"\r\n");
}

fn resize_at(rng: &mut Rng, out: &[u8], sizes: &mut Vec<Size>) {
    let (cols, rows) = SIZES[rng.below(SIZES.len())];
    sizes.push(Size {
        offset: out.len(),
        cols,
        rows,
    });
}

fn prompt(rng: &mut Rng, out: &mut Vec<u8>) {
    out.extend_from_slice(PROMPT_START);
    out.extend_from_slice(PROMPTS[rng.below(PROMPTS.len())]);
    out.extend_from_slice(PROMPT_READY);
}

fn stream(family: Family, seed: u64) -> (Vec<u8>, Vec<Size>) {
    let mut rng = Rng::new(seed);
    let mut out = Vec::new();
    let mut sizes = vec![Size {
        offset: 0,
        cols: 80,
        rows: 24,
    }];
    for _ in 0..24 {
        match family {
            Family::NoIntegration => {
                for _ in 0..rng.below(30) {
                    line(&mut rng, &mut out);
                }
                out.extend_from_slice(b"$ ");
                resize_at(&mut rng, &out, &mut sizes);
            }
            Family::Running => {
                prompt(&mut rng, &mut out);
                out.extend_from_slice(b"echo command");
                out.extend_from_slice(COMMAND_START);
                for _ in 0..rng.below(30) {
                    line(&mut rng, &mut out);
                    if rng.below(6) == 0 {
                        resize_at(&mut rng, &out, &mut sizes);
                    }
                }
                resize_at(&mut rng, &out, &mut sizes);
                out.extend_from_slice(COMMAND_END);
            }
            Family::AltScreen => {
                prompt(&mut rng, &mut out);
                out.extend_from_slice(COMMAND_START);
                out.extend_from_slice(b"\x1b[?1049h\x1b[H\x1b[2J");
                for _ in 0..rng.below(10) {
                    line(&mut rng, &mut out);
                }
                resize_at(&mut rng, &out, &mut sizes);
                out.extend_from_slice(b"\x1b[?1049l");
                resize_at(&mut rng, &out, &mut sizes);
                out.extend_from_slice(COMMAND_END);
            }
            Family::AtPrompt => {
                for _ in 0..rng.below(30) {
                    line(&mut rng, &mut out);
                }
                prompt(&mut rng, &mut out);
                resize_at(&mut rng, &out, &mut sizes);
                out.extend_from_slice(b"\r\x1b[J~/project $ ");
                out.extend_from_slice(COMMAND_START);
                line(&mut rng, &mut out);
                out.extend_from_slice(COMMAND_END);
            }
        }
    }
    (out, sizes)
}

fn configs_for(family: Family) -> Vec<&'static Config> {
    CONFIGS
        .iter()
        .filter(|config| family != Family::AtPrompt || config.mirror || config.agent_tui)
        .collect()
}

fn streams() -> Vec<(String, Family, u64)> {
    let mut out = Vec::new();
    for (name, family) in [
        ("no-integration", Family::NoIntegration),
        ("running", Family::Running),
        ("alt-screen", Family::AltScreen),
        ("at-prompt-mirror-agent", Family::AtPrompt),
    ] {
        for seed in 1..=3u64 {
            out.push((format!("resize-{name}-{seed}"), family, seed * 0x9e37_79b9));
        }
    }
    out
}

fn golden_path(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/goldens")
        .join(format!("{name}.golden"))
}

#[test]
fn resizes_outside_an_owned_prompt_match_the_goldens_recorded_before_prompt_reflow() {
    let update = std::env::var_os("UPDATE_GOLDENS").is_some();
    let mut failures = Vec::new();
    for (name, family, seed) in streams() {
        let (bytes, sizes) = stream(family, seed);
        let mut lines = Vec::new();
        for config in configs_for(family) {
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

- [ ] **Step 2: Generate the goldens on the unmodified tree, then check they are stable**

```bash
cd "$REPO/packages/terminal" && UPDATE_GOLDENS=1 cargo test -p vt-core --test resize_goldens 2>&1 | grep "test result"
cargo test -p vt-core --test resize_goldens 2>&1 | grep "test result"
ls crates/vt-core/tests/goldens/resize-*.golden | wc -l
head -3 crates/vt-core/tests/goldens/resize-running-1.golden
```
Expected: `test result: ok. 1 passed` twice (≈3 s each in a debug build); `12`; three lines starting `renderer rows `, `renderer rows[0..] text `, `renderer rows[500..] text ` (hash values are whatever your run prints).

- [ ] **Step 3: Lint and record their digests**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy -p vt-core --all-targets -- -D warnings 2>&1 | tail -1
cd crates/vt-core/tests/goldens && sha256sum resize-*.golden >> "$HOME/plan10-goldens.sha256" && wc -l < "$HOME/plan10-goldens.sha256"
```
Expected: `Finished …`; `65`.

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-core/tests/resize_goldens.rs packages/terminal/crates/vt-core/tests/goldens/resize-*.golden
git commit -m "$(cat <<'EOF'
test(vt-core): resize goldens for every state outside an owned prompt

Twelve seeded streams replayed through the Plan 9 golden harness, generated
on the tree before the prompt-resize work: resizes without shell
integration, while a command runs and on the alternate screen (all four
configurations), and at an owned prompt in the mirror and agent-TUI
configurations. Roadmap Plan 10 must leave every one unchanged.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Keep the prompt rows on a resize at an owned prompt

**Files:**
- Create: `packages/terminal/crates/vt-core/src/screen/prompt.rs`
- Create: `packages/terminal/crates/vt-core/src/parser/resize.rs`
- Modify: `packages/terminal/crates/vt-core/src/screen.rs:3-4`
- Modify: `packages/terminal/crates/vt-core/src/parser.rs:6-7` and `:445-465` (remove `resize`)
- Modify: `packages/terminal/crates/vt-core/src/lib.rs:528`
- Modify: `packages/terminal/crates/vt-core/src/block_grid.rs:202`
- Modify: `packages/terminal/crates/vt-core/src/block_grid/tests.rs` (append)
- Test: `packages/terminal/crates/vt-core/tests/prompt_resize.rs` (new)

**Interfaces:**
- Consumes: `LineEditorState` (`crate::line_editor`), `ScreenGrid` private helpers visible to child modules (`region_is_full`, `row_is_blank`, `phys_start`, `row_wrapped`, `record_eviction`, fields `reflow_on_resize`, `records_eviction`), `Parser` private items visible to `parser::*` (`mark_full`, fields `width`, `last_width`, `rewrap_pending`, `screen`, `grid`, `rows`, `alt`), `Parser::commit_evicted`, `Parser::send_in_band_report` (`pub(crate)`, `parser/program.rs:49`), `BlockGrid::flat_extent`.
- Produces: `BlockGrid::open_block_ref(&self) -> Option<&Block>`; `ScreenGrid::resize_keeping_prompt(&mut self, rows: usize, cols: usize, prompt_row: Option<usize>) -> Option<usize>` (returns the number of rows wanted above the kept region; `None` = not applicable, nothing changed); `Parser::resize_for(&mut self, columns: usize, rows: usize, editor: LineEditorState)`; `Parser::resize` unchanged in signature and behaviour (moved to `parser/resize.rs`). Task 3 uses the `Option<usize>` for the pull-back.

- [ ] **Step 1: Write the failing tests**

Create `packages/terminal/crates/vt-core/tests/prompt_resize.rs`:

```rust
mod common;

use vt_core::{LineEditorState, TerminalCore};

const READY: &str = "\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07";
const ZSH_REDRAW: &str = "\r\r\x1b[0m\x1b[27m\x1b[24m\x1b[J";

fn core(cols: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::new(cols, 1000).unwrap();
    core.resize(cols, rows);
    core
}

fn prompt(core: &mut TerminalCore, text: &str) {
    core.feed(format!("\x1b]133;A\x07{text}{READY}").as_bytes());
    assert_eq!(core.line_editor_state(), LineEditorState::Owned);
}

fn run(core: &mut TerminalCore, command: &str, output: &str) {
    core.feed(
        format!(
            "{command}\r\n\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07{output}\x1b]133;D;0\x07"
        )
        .as_bytes(),
    );
}

fn texts(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    (0..snapshot.row_count())
        .map(|row| snapshot.row_text(row).trim_end().to_string())
        .collect()
}

fn count(core: &TerminalCore, text: &str) -> usize {
    texts(core).iter().filter(|row| row.contains(text)).count()
}

fn screen_cursor(core: &TerminalCore) -> (usize, usize) {
    let (row, col, _) = core.export_cursor();
    (row - core.history_rows(), col)
}

fn logical_lines(core: &TerminalCore) -> Vec<String> {
    let snapshot = core.snapshot().unwrap();
    let mut lines = vec![String::new()];
    for row in 0..snapshot.row_count() {
        lines.last_mut().unwrap().push_str(snapshot.row_text(row));
        if !snapshot.row_wrapped(row) {
            lines.push(String::new());
        }
    }
    lines
        .iter()
        .map(|line| line.trim_end().to_string())
        .collect()
}

#[test]
fn a_resize_at_a_visible_prompt_leaves_one_prompt_after_the_shell_redraws() {
    let mut core = core(80, 24);
    prompt(&mut core, "~/p $ ");
    run(&mut core, "echo hi", "hi\r\n");
    prompt(&mut core, "~/p $ ");
    core.resize(40, 24);
    core.feed(format!("{ZSH_REDRAW}~/p $ ").as_bytes());
    common::check(&core);
    assert_eq!(
        texts(&core)
            .iter()
            .filter(|row| row.as_str() == "~/p $")
            .count(),
        1
    );
    assert_eq!(count(&core, "~/p $ echo hi"), 1);
    assert_eq!(count(&core, "hi"), 2);
}

#[test]
fn a_narrower_window_keeps_a_two_line_prompt_where_zsh_redraws_it() {
    let first = "a".repeat(60);
    let mut core = core(80, 24);
    prompt(&mut core, "$ ");
    run(&mut core, "echo hi", "hi\r\n");
    prompt(&mut core, &format!("{first}\r\nline-two $ "));
    core.resize(40, 24);
    core.feed(format!("\r\r\x1bM\x1b[J{first}\r\nline-two $ ").as_bytes());
    common::check(&core);
    assert_eq!(count(&core, "line-two $"), 1);
    assert_eq!(count(&core, &"a".repeat(40)), 1);
    assert_eq!(count(&core, "hi"), 2);
    assert_eq!(screen_cursor(&core).1, 11);
}

#[test]
fn a_wider_window_does_not_let_zsh_erase_the_output_above_a_tall_prompt() {
    let long = format!("/{}/ $ ", "d".repeat(92));
    let mut core = core(40, 24);
    prompt(&mut core, "$ ");
    run(&mut core, "echo keep-me", "keep-me\r\n");
    prompt(&mut core, &long);
    core.resize(100, 24);
    core.feed(format!("\r\r\x1b[A\x1b[A\x1b[0m\x1b[J{long}").as_bytes());
    common::check(&core);
    assert_eq!(count(&core, "keep-me"), 2);
    assert_eq!(count(&core, "/ddd"), 1);
    assert!(logical_lines(&core)
        .iter()
        .any(|line| line == long.trim_end()));
}

#[test]
fn bash_redraws_only_the_last_prompt_line_and_the_first_stays_in_place() {
    let first = format!("first-{}", "b".repeat(54));
    let mut core = core(80, 24);
    prompt(&mut core, &format!("{first}\r\nsecond $ "));
    core.resize(40, 24);
    core.feed(b"\r\x1b[Ksecond $ ");
    common::check(&core);
    assert_eq!(count(&core, "second $"), 1);
    assert_eq!(
        texts(&core)
            .iter()
            .filter(|row| row.starts_with("first-"))
            .count(),
        1
    );
    assert!(texts(&core).contains(&first[..40].to_string()));
}

#[test]
fn fish_repaints_on_the_next_key_from_the_first_row_of_the_kept_prompt() {
    let mut core = core(80, 24);
    prompt(&mut core, "line-one-of-the-prompt\r\nline-two $ ls -la");
    core.resize(40, 24);
    assert_eq!(count(&core, "line-two $ ls -la"), 1);
    core.feed(
        b"\r\x1b[A\r\x1b[K\x1b]133;A;click_events=1\x1b\\line-one-of-the-prompt\r\nline-two $ \x1b]133;B\x1b\\ls -lax\x1b[J",
    );
    common::check(&core);
    assert_eq!(count(&core, "line-one-of-the-prompt"), 1);
    assert_eq!(count(&core, "line-two $ ls -lax"), 1);
}

#[test]
fn a_wide_character_cut_by_a_narrower_prompt_row_is_blanked_whole() {
    let mut core = core(80, 24);
    core.set_grapheme_clusters(true);
    prompt(&mut core, "\u{65e5}\u{672c}\u{8a9e} > ");
    core.resize(5, 24);
    common::check(&core);
    let snapshot = core.snapshot().unwrap();
    let row = snapshot.cursor_row as usize;
    assert_eq!(snapshot.row_text(row).trim_end(), "\u{65e5}\u{672c}");
    assert_eq!(screen_cursor(&core), (0, 4));
}

#[test]
fn the_cursor_keeps_its_place_in_the_prompt() {
    let mut core = core(80, 24);
    prompt(&mut core, "~/p $ ls");
    assert_eq!(screen_cursor(&core), (0, 8));
    core.resize(100, 30);
    assert_eq!(screen_cursor(&core), (0, 8));
    core.resize(5, 30);
    assert_eq!(screen_cursor(&core), (0, 4));
    common::check(&core);
}

#[test]
fn a_resize_while_a_command_runs_still_moves_the_frame_to_scrollback() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    core.feed(b"sleep 5\r\n\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07partial output");
    assert_eq!(core.line_editor_state(), LineEditorState::Released);
    let history = core.history_rows();
    core.resize(30, 10);
    common::check(&core);
    assert_eq!(core.history_rows(), history + 2);
    assert_eq!(screen_cursor(&core), (0, 0));
}

#[test]
fn a_resize_on_the_alternate_screen_leaves_the_primary_frame_alone() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    core.feed(b"\x1b[?1049hfull screen");
    assert_eq!(core.line_editor_state(), LineEditorState::Released);
    let history = core.history_rows();
    core.resize(30, 12);
    common::check(&core);
    assert_eq!(core.history_rows(), history);
    let alt = core.alt_grid().expect("alt grid");
    assert_eq!((alt.cols(), alt.rows()), (30, 12));
}

#[test]
fn agent_tui_mode_keeps_truncating_in_place_at_a_prompt() {
    let mut core = core(40, 10);
    core.set_agent_tui_mode(true);
    prompt(&mut core, "$ ");
    run(&mut core, "echo hi", "hi\r\n");
    prompt(&mut core, "$ ");
    let rows = core.snapshot().unwrap().row_count();
    let history = core.history_rows();
    core.resize(20, 10);
    common::check(&core);
    assert_eq!(core.snapshot().unwrap().row_count(), rows);
    assert_eq!(core.history_rows(), history);
}

#[test]
fn a_prompt_taller_than_the_new_screen_takes_the_old_path() {
    let mut core = core(80, 24);
    prompt(&mut core, "$ ");
    run(&mut core, "echo hi", "hi\r\n");
    prompt(&mut core, "one\r\ntwo\r\nthree $ ");
    let history = core.history_rows();
    core.resize(80, 2);
    common::check(&core);
    assert_eq!(core.history_rows(), history + 5);
    assert_eq!(screen_cursor(&core), (0, 0));
}
```

Every redraw these tests feed is a shell's own bytes from the evidence table: `ZSH_REDRAW` is zsh 5.9's `\r\r ESC[0m ESC[27m ESC[24m ESC[J`; the two-line and tall-prompt tests use zsh's up-moves (one `ESC M` for 2 old rows, two `ESC[A` for 3 old rows); the bash test is bash's last-line-only redraw; the fish test is fish 4.8.1's next-key repaint including its fresh `OSC 133;A`.

- [ ] **Step 2: Run them to see the failures**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test prompt_resize 2>&1 | grep -E "^test |test result"
```
Expected: `test result: FAILED. 4 passed; 7 failed`. Passing (they pin today's behaviour and must stay green): `a_resize_while_a_command_runs_still_moves_the_frame_to_scrollback`, `a_resize_on_the_alternate_screen_leaves_the_primary_frame_alone`, `agent_tui_mode_keeps_truncating_in_place_at_a_prompt`, `a_prompt_taller_than_the_new_screen_takes_the_old_path`. Failing: the other seven — e.g. `a_resize_at_a_visible_prompt_leaves_one_prompt_after_the_shell_redraws` with `left: 2, right: 1` (the stale prompt copy), `the_cursor_keeps_its_place_in_the_prompt` with `left: (0, 0), right: (0, 8)`.

- [ ] **Step 3: `BlockGrid::open_block_ref` and its test**

In `packages/terminal/crates/vt-core/src/block_grid.rs`, find (line 202):

```rust
    pub fn has_open_block(&self) -> bool {
```
and insert **before** it:

```rust
    pub fn open_block_ref(&self) -> Option<&Block> {
        self.open.as_ref()
    }

```

Append to the end of `packages/terminal/crates/vt-core/src/block_grid/tests.rs`:

```rust

#[test]
fn open_block_ref_is_the_open_block_and_nothing_after_it_closes() {
    let mut grid = BlockGrid::new();
    assert!(grid.open_block_ref().is_none());
    grid.sync_next_row(3);
    grid.open_block(BlockSource::Osc133);
    let open = grid.open_block_ref().expect("an open block");
    assert_eq!(grid.flat_extent(open).0, 3);
    grid.close_block(Some(0));
    assert!(grid.open_block_ref().is_none());
}
```

- [ ] **Step 4: The screen keeps the prompt rows**

Create `packages/terminal/crates/vt-core/src/screen/prompt.rs`:

```rust
use crate::screen::{clamp_dimension, Cell, ScreenGrid};

impl ScreenGrid {
    pub(crate) fn resize_keeping_prompt(
        &mut self,
        rows: usize,
        cols: usize,
        prompt_row: Option<usize>,
    ) -> Option<usize> {
        let rows = clamp_dimension(rows);
        let cols = clamp_dimension(cols);
        if !self.reflow_on_resize || !self.records_eviction || !self.region_is_full() {
            return None;
        }
        let top = prompt_row.unwrap_or(self.row).min(self.row);
        let mut bottom = self.max_cursor_row.max(self.row);
        while bottom > self.row && bottom - top >= rows && self.row_is_blank(bottom) {
            bottom -= 1;
        }
        let kept = bottom - top + 1;
        if kept > rows {
            return None;
        }
        let trailing = self.rows - 1 - bottom;
        for row in 0..top {
            self.record_eviction(row);
        }
        let width = cols.min(self.cols);
        let mut cells = vec![Cell::BLANK; rows * cols];
        let mut wrapped = vec![false; rows];
        for (offset, flag) in wrapped.iter_mut().enumerate().take(kept) {
            let source = self.phys_start(top + offset);
            let target = offset * cols;
            cells[target..target + width].clone_from_slice(&self.cells[source..source + width]);
            if width < self.cols
                && self.cells[source + width].ch == '\0'
                && self.cells[source + width - 1].ch != '\0'
            {
                cells[target + width - 1] = Cell::BLANK;
            }
            *flag = cols == self.cols && self.row_wrapped(top + offset);
        }
        let wanted = if rows >= self.rows {
            top + (rows - self.rows)
        } else {
            top - top.min((self.rows - rows).saturating_sub(trailing))
        };
        self.cells = cells;
        self.wrapped = wrapped;
        self.dirty = vec![true; rows];
        self.first = 0;
        self.rows = rows;
        self.cols = cols;
        self.scroll_top = 0;
        self.scroll_bottom = rows - 1;
        self.row -= top;
        self.max_cursor_row = bottom - top;
        self.col = self.col.min(cols - 1);
        self.pending_wrap = false;
        self.saved = None;
        Some(wanted.min(rows - kept))
    }
}
```

In `packages/terminal/crates/vt-core/src/screen.rs`, replace (lines 3-4):

```rust
mod print;
mod resize;
```
with:

```rust
mod print;
mod prompt;
mod resize;
```

- [ ] **Step 5: The parser chooses the path**

In `packages/terminal/crates/vt-core/src/parser.rs`, replace (lines 6-7):

```rust
mod program;
mod unknown;
```
with:

```rust
mod program;
mod resize;
mod unknown;
```

and delete this whole function and the blank line after it (lines 445-465), which moves to the new file unchanged in behaviour:

```rust
    pub fn resize(&mut self, columns: usize, rows: usize) {
        self.mark_full();
        if columns != self.width {
            self.rewrap_pending = true;
        }
        self.last_width = self.width;
        self.width = columns;
        if self.alt.is_some() {
            self.screen.resize_without_reflow(rows, columns);
        } else {
            self.screen.resize(rows, columns);
            self.commit_evicted();
        }
        if let Some(alt) = self.alt.as_mut() {
            alt.resize(rows, columns);
        }
        self.grid
            .clamp_to_rows(self.rows.completed().len() + self.screen.rows());
        self.send_in_band_report();
    }

```

Create `packages/terminal/crates/vt-core/src/parser/resize.rs`:

```rust
use crate::line_editor::LineEditorState;

use super::Parser;

impl Parser {
    pub fn resize(&mut self, columns: usize, rows: usize) {
        self.note_width(columns);
        if self.alt.is_some() {
            self.screen.resize_without_reflow(rows, columns);
        } else {
            self.screen.resize(rows, columns);
            self.commit_evicted();
        }
        if let Some(alt) = self.alt.as_mut() {
            alt.resize(rows, columns);
        }
        self.grid
            .clamp_to_rows(self.rows.completed().len() + self.screen.rows());
        self.send_in_band_report();
    }

    pub(crate) fn resize_for(&mut self, columns: usize, rows: usize, editor: LineEditorState) {
        if editor == LineEditorState::Owned
            && self.alt.is_none()
            && self.resize_at_prompt(columns, rows)
        {
            return;
        }
        self.resize(columns, rows);
    }

    fn note_width(&mut self, columns: usize) {
        self.mark_full();
        if columns != self.width {
            self.rewrap_pending = true;
        }
        self.last_width = self.width;
        self.width = columns;
    }

    fn resize_at_prompt(&mut self, columns: usize, rows: usize) -> bool {
        let completed = self.rows.completed().len();
        let prompt_row = self
            .grid
            .open_block_ref()
            .map(|block| self.grid.flat_extent(block).0.saturating_sub(completed));
        if self
            .screen
            .resize_keeping_prompt(rows, columns, prompt_row)
            .is_none()
        {
            return false;
        }
        self.note_width(columns);
        self.commit_evicted();
        self.grid
            .clamp_to_rows(self.rows.completed().len() + self.screen.rows());
        self.send_in_band_report();
        true
    }
}
```

In `packages/terminal/crates/vt-core/src/lib.rs`, replace (line 528, inside `pub fn resize`):

```rust
        self.parser.resize(columns, rows);
```
with:

```rust
        self.parser
            .resize_for(columns, rows, self.line_editor.state());
```

- [ ] **Step 6: Run the tests, lint, and the whole suite**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo test -p vt-core --test prompt_resize 2>&1 | grep "test result"
cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
cd crates/vt-core/tests/goldens && sha256sum -c --quiet "$HOME/plan10-goldens.sha256" && echo goldens-unchanged
wc -l "$REPO/packages/terminal/crates/vt-core/src/lib.rs" "$REPO/packages/terminal/crates/vt-core/src/parser.rs"
```
Expected: `Finished …`; `test result: ok. 11 passed`; only `rust-done` (the goldens tests are inside `cargo test`); `goldens-unchanged`; `595 …lib.rs`, `531 …parser.rs`.

- [ ] **Step 7: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-core/src/screen/prompt.rs packages/terminal/crates/vt-core/src/parser/resize.rs packages/terminal/crates/vt-core/src/screen.rs packages/terminal/crates/vt-core/src/parser.rs packages/terminal/crates/vt-core/src/lib.rs packages/terminal/crates/vt-core/src/block_grid.rs packages/terminal/crates/vt-core/src/block_grid/tests.rs packages/terminal/crates/vt-core/tests/prompt_resize.rs
git commit -m "$(cat <<'EOF'
feat(vt-core): keep the prompt rows for the shell's redraw on a resize

While the shell owns the line, a resize sends the rows above the prompt
start to scrollback (rewrapped there as before) and keeps the prompt rows
unrewrapped with the cursor at the same place, so zsh, bash and fish,
which all move up by the height they drew at the old width, redraw over
them instead of leaving a stale prompt in scrollback. Kitty's behaviour
from the survey's description (clean-room); every other state keeps the
old path (roadmap Plan 10, survey §1.5, §5.4).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Pull scrollback back on growth, only rows that restore exactly

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/content.rs:129` and its `tests` module (`:224`)
- Modify: `packages/terminal/crates/vt-core/src/attribute_map.rs:69` and its `tests` module (`:165`)
- Modify: `packages/terminal/crates/vt-core/src/row_index.rs:434`
- Modify: `packages/terminal/crates/vt-core/src/row_index/tests.rs` (append)
- Modify (whole file): `packages/terminal/crates/vt-core/src/screen/prompt.rs`
- Modify (whole file): `packages/terminal/crates/vt-core/src/parser/resize.rs`
- Test: `packages/terminal/crates/vt-core/tests/prompt_resize.rs` (line 3, append)

**Interfaces:**
- Consumes: Task 2's `resize_keeping_prompt -> Option<usize>` (rows wanted above the kept region); `scrollback::commit_row(&[Cell], bool, &mut Content, &mut RowIndex, &mut AttributeMap<CellStyle>)`; `width::clusters(&str, WidthMode) -> Vec<Cluster { start, end, width }>`; `Cell::new`, `Cell::append_scalar` (`pub(crate)`), `Cell::BLANK`; `RowRange { start, end, wrapped, indent }` (`pub(crate)`, `Clone`).
- Produces: `Content::truncate_to(&mut self, offset: u64)`; `AttributeMap::truncate_to(&mut self, offset: u64)`; `RowIndex::pop_completed(&mut self) -> Option<RowRange>`; `ScreenGrid::push_rows_on_top(&mut self, pulled: Vec<(Vec<Cell>, bool)>)`; private `Parser::pull_back(&mut self, wanted: usize)` and `Parser::row_cells(&self, row: &RowRange) -> Option<Vec<Cell>>`.

- [ ] **Step 1: Write the failing tests**

In `packages/terminal/crates/vt-core/tests/prompt_resize.rs`, replace line 3:

```rust
use vt_core::{LineEditorState, TerminalCore};
```
with:

```rust
use vt_core::{FindQuery, FindSession, LineEditorState, TerminalCore};
```

and append at the end of the file (after the last `}`, with one blank line before):

```rust
#[test]
fn growing_the_window_pulls_the_newest_rows_back_onto_the_screen() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..30).map(|i| format!("line {i}\r\n")).collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    let before = texts(&core);
    let history = core.history_rows();
    assert_eq!(screen_cursor(&core), (9, 2));
    core.resize(40, 16);
    common::check(&core);
    assert_eq!(texts(&core), before);
    assert_eq!(core.history_rows(), history - 6);
    assert_eq!(screen_cursor(&core), (15, 2));
}

#[test]
fn a_narrower_window_keeps_the_prompt_the_same_distance_from_the_bottom() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..30).map(|i| format!("line {i}\r\n")).collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    core.resize(20, 10);
    common::check(&core);
    assert_eq!(screen_cursor(&core), (9, 2));
    assert_eq!(texts(&core).last().unwrap(), "$");
}

#[test]
fn a_shorter_window_pushes_the_rows_above_the_prompt_into_scrollback() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..30).map(|i| format!("line {i}\r\n")).collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    let before = texts(&core);
    let history = core.history_rows();
    core.resize(40, 6);
    common::check(&core);
    assert_eq!(texts(&core), before);
    assert_eq!(core.history_rows(), history + 4);
    assert_eq!(screen_cursor(&core), (5, 2));
}

#[test]
fn pull_back_stops_at_a_row_that_cannot_be_restored_exactly() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let long = "abc de ".repeat(12);
    run(&mut core, "echo", &format!("{long}\r\n"));
    prompt(&mut core, "$ ");
    core.resize(30, 12);
    common::check(&core);
    assert_eq!(screen_cursor(&core), (1, 2));
    assert!(logical_lines(&core).contains(&long.trim_end().to_string()));
}

#[test]
fn rows_pulled_back_commit_again_byte_for_byte() {
    for graphemes in [false, true] {
        let mut core = core(30, 8);
        core.set_grapheme_clusters(graphemes);
        prompt(&mut core, "$ ");
        let mut output = String::new();
        for i in 0..20 {
            output.push_str(&format!(
                "\x1b[3{}m{i} red\x1b[0m \x1b]8;;https://example.com/{i}\x1b\\link\x1b]8;;\x1b\\ \u{4e2d}e\u{301}\x1b[48;2;1;2;3m bg \x1b[0m\r\n",
                i % 8
            ));
        }
        run(&mut core, "paint", &output);
        prompt(&mut core, "$ ");
        core.resize(30, 20);
        common::check(&core);
        assert!(screen_cursor(&core).0 > 7, "rows were pulled back");
        let before = core.snapshot().unwrap();
        core.feed(b"\r\n\x1b]7000;v=1;input-released=1\x07");
        core.feed("\r\n".repeat(30).as_bytes());
        common::check(&core);
        let after = core.snapshot().unwrap();
        for row in 0..before.row_count() - 1 {
            assert_eq!(after.row_text(row), before.row_text(row), "row {row}");
            assert_eq!(
                after.row_style_pairs(row),
                before.row_style_pairs(row),
                "row {row}"
            );
            assert_eq!(
                after.row_cell_spans(row),
                before.row_cell_spans(row),
                "row {row}"
            );
            assert_eq!(after.row_wrapped(row), before.row_wrapped(row), "row {row}");
        }
    }
}

#[test]
fn blocks_keep_their_text_and_the_open_prompt_block_starts_on_the_prompt() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..14).map(|i| format!("out {i}\r\n")).collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    let text_of = |core: &TerminalCore, first: u32, count: u32| -> Vec<String> {
        let snapshot = core.snapshot().unwrap();
        (first..first + count)
            .map(|row| snapshot.row_text(row as usize).trim_end().to_string())
            .collect()
    };
    let before = core.snapshot().unwrap();
    let finished: Vec<(u32, u32)> = before
        .blocks
        .iter()
        .map(|b| (b.first_row, b.row_count))
        .collect();
    let finished_text: Vec<Vec<String>> = finished
        .iter()
        .map(|&(first, count)| text_of(&core, first, count))
        .collect();
    core.resize(40, 16);
    common::check(&core);
    let after = core.snapshot().unwrap();
    for (index, &(first, count)) in finished.iter().enumerate() {
        let block = &after.blocks[index];
        assert_eq!(
            text_of(&core, block.first_row, block.row_count),
            finished_text[index]
        );
        assert_eq!((block.first_row, block.row_count), (first, count));
    }
    let open = after.blocks.last().unwrap();
    assert_eq!(after.row_text(open.first_row as usize).trim_end(), "$");
}

#[test]
fn find_hits_point_at_their_text_after_rows_are_pulled_back() {
    let mut core = core(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..30)
        .map(|i| {
            if i % 3 == 0 {
                format!("needle {i}\r\n")
            } else {
                format!("hay {i}\r\n")
            }
        })
        .collect();
    run(&mut core, "seq", &output);
    prompt(&mut core, "$ ");
    let mut session = FindSession::new(FindQuery::literal("needle"));
    core.find_update(&mut session, usize::MAX);
    let before = core.find_results(&session).len();
    core.resize(40, 18);
    core.find_update(&mut session, usize::MAX);
    let hits = core.find_results(&session);
    assert_eq!(hits.len(), before);
    let snapshot = core.snapshot().unwrap();
    for hit in hits {
        let flat = core.flat_row(hit.row).expect("hit row still exists");
        assert!(snapshot.row_text(flat).contains("needle"), "row {flat}");
    }
}

#[test]
fn the_older_output_floor_and_first_stable_row_survive_a_prompt_resize() {
    let mut core = TerminalCore::with_limits(40, vt_core::Limits::rows_only(20)).unwrap();
    core.resize(40, 10);
    prompt(&mut core, "$ ");
    let output: String = (0..60).map(|i| format!("line {i}\r\n")).collect();
    run(&mut core, "seq", &output);
    core.feed(b"\x1b]7000;v=1;older=3\x07");
    prompt(&mut core, "$ ");
    let first = core.first_stable_row();
    let older = core.older_state();
    core.resize(40, 16);
    common::check(&core);
    assert_eq!(core.first_stable_row(), first);
    assert_eq!(core.older_state(), older);
    core.resize(25, 8);
    common::check(&core);
    assert!(core.first_stable_row() >= first);
}

#[test]
fn an_older_output_chunk_still_lands_after_a_prompt_resize_pulled_every_row_back() {
    let mut mirror = TerminalCore::with_limits(
        40,
        vt_core::Limits {
            rows: 50,
            bytes: usize::MAX,
        },
    )
    .unwrap();
    mirror.set_reflow_on_resize(false);
    mirror.resize(40, 3);
    mirror.set_cold_ring_bytes(1 << 20);
    let numbered: String = (0..200).map(|i| format!("row {i:05}\r\n")).collect();
    mirror.feed(numbered.as_bytes());
    let origin = mirror.first_stable_row();
    let mut pane = TerminalCore::new(40, 10_000).unwrap();
    pane.resize(40, 6);
    pane.feed(format!("\x1b]7000;v=1;origin={origin}\x1b\\").as_bytes());
    prompt(&mut pane, "$ ");
    run(&mut pane, "echo", "one\r\ntwo\r\nthree\r\n");
    prompt(&mut pane, "$ ");
    pane.resize(40, 12);
    common::check(&pane);
    assert_eq!(pane.history_rows(), 0);
    let chunk = mirror
        .older_chunk(origin, 8, 1 << 20)
        .expect("the mirror has older rows");
    pane.feed(&chunk.bytes);
    common::check(&pane);
    assert_eq!(pane.first_stable_row(), origin - 8);
    let rows = texts(&pane);
    let expected: Vec<String> = (origin - 8..origin)
        .map(|row| format!("row {row:05}"))
        .collect();
    assert_eq!(rows[..8].to_vec(), expected);
    assert_eq!(rows.iter().filter(|row| row.as_str() == "three").count(), 1);
}
```

- [ ] **Step 2: Run them to see the failures**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test prompt_resize 2>&1 | grep -E "FAILED|test result"
```
Expected: `test result: FAILED. 13 passed; 7 failed` — the failing ones are `growing_the_window_pulls_the_newest_rows_back_onto_the_screen`, `a_narrower_window_keeps_the_prompt_the_same_distance_from_the_bottom`, `a_shorter_window_pushes_the_rows_above_the_prompt_into_scrollback`, `pull_back_stops_at_a_row_that_cannot_be_restored_exactly`, `rows_pulled_back_commit_again_byte_for_byte`, `the_older_output_floor_and_first_stable_row_survive_a_prompt_resize`, `an_older_output_chunk_still_lands_after_a_prompt_resize_pulled_every_row_back` (for example `left: (0, 2), right: (9, 2)` — the prompt sits at the top of the screen because nothing is pulled back yet). `blocks_keep_their_text_…` and `find_hits_point_at_their_text_…` already pass; they guard the pull-back you are about to add.

- [ ] **Step 3: Truncate content and styles, pop a completed row — with unit tests**

In `packages/terminal/crates/vt-core/src/content.rs`, find (line 129):

```rust
    pub fn resident_bytes(&self) -> usize {
```
and insert **before** it:

```rust
    pub fn truncate_to(&mut self, offset: u64) {
        while self
            .chunks
            .back()
            .is_some_and(|chunk| chunk.start >= offset)
        {
            self.chunks.pop_back();
        }
        if let Some(back) = self.chunks.back_mut() {
            let keep = ((offset - back.start) as usize).min(back.bytes.len());
            back.bytes.truncate(keep);
        }
        self.next_offset = offset;
    }

```

In the same file's `mod tests`, find (line 224 before the insert above, 239 after it):

```rust
    #[test]
    fn trim_front_to_below_the_start_changes_nothing() {
```
and insert **before** it:

```rust
    #[test]
    fn truncate_to_drops_the_tail_and_the_next_push_lands_at_the_cut() {
        let mut c = Content::with_base(1024);
        for _ in 0..(CHUNK_SIZE + 10) {
            c.push_char("x");
        }
        c.truncate_to(1030);
        assert_eq!(c.end_offset(), 1030);
        assert_eq!(c.resident_bytes(), 6);
        c.push_char("y");
        assert_eq!(c.copy_range(1024, 1031), b"xxxxxxy");
    }

    #[test]
    fn truncate_to_the_start_empties_a_prepended_content() {
        let mut c = Content::with_base(1024);
        c.push_char("z");
        let start = c.prepend(b"ab");
        c.truncate_to(start);
        assert_eq!(c.resident_bytes(), 0);
        assert_eq!(c.start_offset(), start);
        assert_eq!(c.end_offset(), start);
    }

```

In `packages/terminal/crates/vt-core/src/attribute_map.rs`, find (line 69):

```rust
    pub fn drop_before(&mut self, offset: u64) {
```
and insert **before** it:

```rust
    pub fn truncate_to(&mut self, offset: u64) {
        let cut = self.ends.split_off(&offset);
        if let Some(value) = cut.values().next() {
            self.tail = *value;
        }
        self.run_start = self.ends.keys().next_back().copied().unwrap_or(0);
    }

```

In the same file's `mod tests`, find:

```rust
    #[test]
    fn prepended_runs_read_back_in_their_own_region() {
```
and insert **before** it:

```rust
    #[test]
    fn truncate_to_keeps_the_value_of_the_last_kept_byte() {
        let mut m = AttributeMap::<u32>::new(0);
        m.set_from(0, 1);
        m.set_from(3, 2);
        m.set_from(7, 0);
        m.truncate_to(5);
        assert_eq!(runs(&m, 0, 5), vec![(3, 1), (5, 2)]);
        m.set_from(5, 4);
        assert_eq!(runs(&m, 0, 8), vec![(3, 1), (5, 2), (8, 4)]);
    }

    #[test]
    fn truncate_to_at_a_run_end_then_the_same_value_extends_it() {
        let mut m = AttributeMap::<u32>::new(0);
        m.set_from(0, 1);
        m.set_from(3, 0);
        m.truncate_to(3);
        assert_eq!(runs(&m, 0, 3), vec![(3, 1)]);
        m.set_from(3, 1);
        assert_eq!(runs(&m, 0, 6), vec![(6, 1)]);
    }

```

Why `truncate_to` is right: `ends[k] = v` means the run that ends at `k` (exclusive) has value `v`; the value of the last kept byte `offset - 1` is the first key `≥ offset`, or `tail` when there is none. The new `run_start` must be the start of the tail run (the last kept key, or 0) so that the next `set_from(offset, …)` inserts a boundary at `offset` instead of recolouring kept bytes (`set_from` only overwrites `tail` when `offset <= run_start`, `attribute_map.rs:38-49`).

In `packages/terminal/crates/vt-core/src/row_index.rs`, find (line 434):

```rust
    fn earliest_retained_start(&self) -> u64 {
```
and insert **before** it:

```rust
    pub(crate) fn pop_completed(&mut self) -> Option<RowRange> {
        let row = self.completed.pop_back()?;
        self.open_start = row.start;
        let len = self.completed.len();
        self.stale.retain_mut(|run| {
            run.len = run.len.min(len.saturating_sub(run.start));
            run.len > 0
        });
        Some(row)
    }

```

Append to the end of `packages/terminal/crates/vt-core/src/row_index/tests.rs`:

```rust

#[test]
fn pop_completed_reopens_the_row_and_shortens_a_stale_run() {
    let mut r = RowIndex::new(0);
    r.complete_row(10, false);
    r.complete_row(20, true);
    r.complete_row(30, false);
    r.mark_stale(1, 3, 80);
    let popped = r.pop_completed().expect("a row");
    assert_eq!((popped.start, popped.end, popped.wrapped), (20, 30, false));
    assert_eq!(r.open_start(), 20);
    assert_eq!(ranges(&r), vec![(0, 10, false), (10, 20, true)]);
    assert_eq!(r.stale_runs().len(), 1);
    assert_eq!((r.stale_runs()[0].start, r.stale_runs()[0].len), (1, 1));
    r.pop_completed();
    assert!(r.stale_runs().is_empty());
    assert_eq!(r.open_start(), 10);
}
```

- [ ] **Step 4: Put pulled rows on top of the screen**

Replace the whole contents of `packages/terminal/crates/vt-core/src/screen/prompt.rs` with:

```rust
use crate::screen::{clamp_dimension, Cell, ScreenGrid};

impl ScreenGrid {
    pub(crate) fn resize_keeping_prompt(
        &mut self,
        rows: usize,
        cols: usize,
        prompt_row: Option<usize>,
    ) -> Option<usize> {
        let rows = clamp_dimension(rows);
        let cols = clamp_dimension(cols);
        if !self.reflow_on_resize || !self.records_eviction || !self.region_is_full() {
            return None;
        }
        let top = prompt_row.unwrap_or(self.row).min(self.row);
        let mut bottom = self.max_cursor_row.max(self.row);
        while bottom > self.row && bottom - top >= rows && self.row_is_blank(bottom) {
            bottom -= 1;
        }
        let kept = bottom - top + 1;
        if kept > rows {
            return None;
        }
        let trailing = self.rows - 1 - bottom;
        for row in 0..top {
            self.record_eviction(row);
        }
        let width = cols.min(self.cols);
        let mut cells = vec![Cell::BLANK; rows * cols];
        let mut wrapped = vec![false; rows];
        for (offset, flag) in wrapped.iter_mut().enumerate().take(kept) {
            let source = self.phys_start(top + offset);
            let target = offset * cols;
            cells[target..target + width].clone_from_slice(&self.cells[source..source + width]);
            if width < self.cols
                && self.cells[source + width].ch == '\0'
                && self.cells[source + width - 1].ch != '\0'
            {
                cells[target + width - 1] = Cell::BLANK;
            }
            *flag = cols == self.cols && self.row_wrapped(top + offset);
        }
        let wanted = if rows >= self.rows {
            top + (rows - self.rows)
        } else {
            top - top.min((self.rows - rows).saturating_sub(trailing))
        };
        self.cells = cells;
        self.wrapped = wrapped;
        self.dirty = vec![true; rows];
        self.first = 0;
        self.rows = rows;
        self.cols = cols;
        self.scroll_top = 0;
        self.scroll_bottom = rows - 1;
        self.row -= top;
        self.max_cursor_row = bottom - top;
        self.col = self.col.min(cols - 1);
        self.pending_wrap = false;
        self.saved = None;
        Some(wanted.min(rows - kept))
    }

    pub(crate) fn push_rows_on_top(&mut self, pulled: Vec<(Vec<Cell>, bool)>) {
        let count = pulled.len();
        if count == 0 || self.max_cursor_row + count >= self.rows {
            return;
        }
        self.materialize();
        let cols = self.cols;
        self.cells.rotate_right(count * cols);
        self.wrapped.rotate_right(count);
        for (index, (cells, wrapped)) in pulled.into_iter().enumerate() {
            self.cells[index * cols..(index + 1) * cols].clone_from_slice(&cells);
            self.wrapped[index] = wrapped;
        }
        self.row += count;
        self.max_cursor_row += count;
        self.mark_all_dirty();
    }
}
```

- [ ] **Step 5: Pull back in the parser**

Replace the whole contents of `packages/terminal/crates/vt-core/src/parser/resize.rs` with:

```rust
use crate::attribute_map::AttributeMap;
use crate::content::Content;
use crate::line_editor::LineEditorState;
use crate::row_index::{RowIndex, RowRange};
use crate::screen::Cell;
use crate::style::CellStyle;
use crate::width::clusters;

use super::Parser;

impl Parser {
    pub fn resize(&mut self, columns: usize, rows: usize) {
        self.note_width(columns);
        if self.alt.is_some() {
            self.screen.resize_without_reflow(rows, columns);
        } else {
            self.screen.resize(rows, columns);
            self.commit_evicted();
        }
        if let Some(alt) = self.alt.as_mut() {
            alt.resize(rows, columns);
        }
        self.grid
            .clamp_to_rows(self.rows.completed().len() + self.screen.rows());
        self.send_in_band_report();
    }

    pub(crate) fn resize_for(&mut self, columns: usize, rows: usize, editor: LineEditorState) {
        if editor == LineEditorState::Owned
            && self.alt.is_none()
            && self.resize_at_prompt(columns, rows)
        {
            return;
        }
        self.resize(columns, rows);
    }

    fn note_width(&mut self, columns: usize) {
        self.mark_full();
        if columns != self.width {
            self.rewrap_pending = true;
        }
        self.last_width = self.width;
        self.width = columns;
    }

    fn resize_at_prompt(&mut self, columns: usize, rows: usize) -> bool {
        let completed = self.rows.completed().len();
        let prompt_row = self
            .grid
            .open_block_ref()
            .map(|block| self.grid.flat_extent(block).0.saturating_sub(completed));
        let Some(wanted) = self.screen.resize_keeping_prompt(rows, columns, prompt_row) else {
            return false;
        };
        self.note_width(columns);
        self.commit_evicted();
        self.pull_back(wanted);
        self.grid
            .clamp_to_rows(self.rows.completed().len() + self.screen.rows());
        self.send_in_band_report();
        true
    }

    fn pull_back(&mut self, wanted: usize) {
        let stale_end = self
            .rows
            .stale_runs()
            .iter()
            .map(|run| run.start + run.len)
            .max()
            .unwrap_or(0);
        let mut pulled = Vec::new();
        while pulled.len() < wanted && self.rows.completed().len() > stale_end {
            let Some(row) = self.rows.completed().back().cloned() else {
                break;
            };
            let Some(cells) = self.row_cells(&row) else {
                break;
            };
            self.rows.pop_completed();
            self.content.truncate_to(row.start);
            self.styles.truncate_to(row.start);
            pulled.push((cells, row.wrapped));
        }
        if pulled.is_empty() {
            return;
        }
        pulled.reverse();
        self.screen.push_rows_on_top(pulled);
        let completed = self.rows.completed().len();
        self.history_exported_rows = self.history_exported_rows.min(completed);
        self.pending_rewritten_from = Some(
            self.pending_rewritten_from
                .unwrap_or(usize::MAX)
                .min(completed),
        );
    }

    fn row_cells(&self, row: &RowRange) -> Option<Vec<Cell>> {
        if row.indent != 0 {
            return None;
        }
        let bytes = self.content.copy_range(row.start, row.end);
        let text = std::str::from_utf8(&bytes).ok()?;
        let runs = self.styles.runs(row.start, row.end);
        let cols = self.screen.cols();
        let mut cells = Vec::with_capacity(cols);
        let mut run = 0usize;
        for cluster in clusters(text, self.width_mode) {
            if cluster.width == 0 {
                return None;
            }
            while runs
                .get(run)
                .is_some_and(|(end, _)| *end as usize <= cluster.start)
            {
                run += 1;
            }
            let style = runs
                .get(run)
                .map_or(CellStyle::DEFAULT, |(_, style)| *style);
            let mut scalars = text[cluster.start..cluster.end].chars();
            let mut cell = Cell::new(scalars.next()?, style);
            for scalar in scalars {
                cell.append_scalar(scalar);
            }
            cells.push(cell);
            for _ in 1..cluster.width.min(2) {
                cells.push(Cell::new('\0', style));
            }
        }
        if cells.len() > cols {
            return None;
        }
        cells.resize(cols, Cell::BLANK);
        let mut content = Content::with_base(0);
        let mut index = RowIndex::new(0);
        let mut styles = AttributeMap::with_base(CellStyle::DEFAULT, 0);
        crate::scrollback::commit_row(&cells, row.wrapped, &mut content, &mut index, &mut styles);
        let end = content.end_offset();
        (content.copy_range(0, end) == bytes && styles.runs(0, end) == runs).then_some(cells)
    }
}
```

What changed against Task 2's file: the imports; `resize_at_prompt` keeps the wanted row count (`let Some(wanted) = … else { return false; }`) and calls `self.pull_back(wanted)` after `commit_evicted()` (so the rows are already rewrapped at the new width when they are tested); and the two new functions `pull_back` and `row_cells`.

- [ ] **Step 6: Run the tests, lint, the whole suite, the goldens**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo test -p vt-core --test prompt_resize 2>&1 | grep "test result"
cargo test -p vt-core --lib -- truncate_to pop_completed open_block_ref 2>&1 | grep "test result"
cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
cd crates/vt-core/tests/goldens && sha256sum -c --quiet "$HOME/plan10-goldens.sha256" && echo goldens-unchanged
```
Expected: `Finished …`; `test result: ok. 20 passed`; `test result: ok. 6 passed` (the five new unit tests and Task 2's `open_block_ref` test); only `rust-done`; `goldens-unchanged`.

- [ ] **Step 7: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-core/src/content.rs packages/terminal/crates/vt-core/src/attribute_map.rs packages/terminal/crates/vt-core/src/row_index.rs packages/terminal/crates/vt-core/src/row_index/tests.rs packages/terminal/crates/vt-core/src/screen/prompt.rs packages/terminal/crates/vt-core/src/parser/resize.rs packages/terminal/crates/vt-core/tests/prompt_resize.rs
git commit -m "$(cat <<'EOF'
feat(vt-core): pull scrollback back onto the screen on a prompt resize

After a resize at an owned prompt, the newest scrollback rows move back
onto the top of the screen so the prompt keeps its distance from the
bottom (Alacritty grow_lines/shrink_lines, Ghostty pull_scrollback;
behaviour only). A row comes back only if committing it again gives the
same bytes and style runs, so nothing is lost or restyled; flat and
stable rows do not move (roadmap Plan 10, survey §2.4).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Seeded integrity sequence

**Files:**
- Test: `packages/terminal/crates/vt-core/tests/prompt_resize_integrity.rs` (new)

**Interfaces:**
- Consumes: `tests/common/mod.rs` `check(&TerminalCore)` (integrity + one wrapped flag per row + every cell span inside its row and ≤ 2 cells), `TerminalCore::{with_limits, resize, feed, set_grapheme_clusters, line_editor_state, verify_integrity}`, `Limits::{rows_only, DEFAULT}`.
- Produces: `every_step_of_a_seeded_prompt_resize_sequence_keeps_the_model_consistent`.

- [ ] **Step 1: Write the test**

Create `packages/terminal/crates/vt-core/tests/prompt_resize_integrity.rs`:

```rust
mod common;

use vt_core::{Limits, LineEditorState, TerminalCore};

struct Rng(u64);

impl Rng {
    fn below(&mut self, bound: usize) -> usize {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        (self.0 % bound as u64) as usize
    }
}

const PROMPTS: [&str; 5] = [
    "$ ",
    "~/a/very/long/working/directory/that/wraps/on/a/narrow/pane $ ",
    "first line of a prompt\r\nsecond $ ",
    "\u{65e5}\u{672c}\u{8a9e}\u{306e}\u{30d7}\u{30ed}\u{30f3}\u{30d7}\u{30c8} > ",
    "",
];

const TEXT: [&str; 10] = [
    "plain words that wrap when the pane is narrow ",
    "\u{4e2d}\u{6587}\u{5b57}",
    "\x1b[1;32mgreen\x1b[0m ",
    "\x1b[48;5;236m band \x1b[0m",
    "  - a bullet that hangs its continuation ",
    "e\u{301}",
    "\u{1f44d}\u{1f3fd}",
    "\t",
    "\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\",
    "0123456789",
];

const SIZES: [(usize, usize); 9] = [
    (80, 24),
    (40, 24),
    (100, 30),
    (30, 12),
    (7, 5),
    (1, 1),
    (2, 3),
    (61, 17),
    (120, 2),
];

fn step(rng: &mut Rng, core: &mut TerminalCore) -> bool {
    let owned = core.line_editor_state() == LineEditorState::Owned;
    match rng.below(10) {
        0 | 1 => {
            let mut line = String::new();
            for _ in 0..rng.below(6) {
                line.push_str(TEXT[rng.below(TEXT.len())]);
            }
            line.push_str("\r\n");
            core.feed(line.as_bytes());
        }
        2 => core.feed(
            format!(
                "\x1b]133;A\x07{}\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07",
                PROMPTS[rng.below(PROMPTS.len())]
            )
            .as_bytes(),
        ),
        3 => core.feed(b"\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07"),
        4 => core.feed(b"\x1b]133;D;0\x07"),
        5 => core.feed(if rng.below(2) == 0 {
            b"\x1b[?1049h\x1b[Hfull"
        } else {
            b"\x1b[?1049l"
        }),
        6 => core.feed(b"\r\r\x1b[A\x1b[J$ typed"),
        7 => core.feed(b"\x1b]7000;v=1;older=2\x07"),
        _ => {
            let (cols, rows) = SIZES[rng.below(SIZES.len())];
            core.resize(cols, rows);
            return owned;
        }
    }
    false
}

#[test]
fn every_step_of_a_seeded_prompt_resize_sequence_keeps_the_model_consistent() {
    let mut owned_resizes = 0usize;
    for seed in 1..=32u64 {
        let mut rng = Rng(seed.wrapping_mul(0x9e37_79b9_7f4a_7c15) | 1);
        let limits = if seed % 4 == 0 {
            Limits::rows_only(30)
        } else {
            Limits::DEFAULT
        };
        let mut core = TerminalCore::with_limits(80, limits).unwrap();
        core.resize(80, 24);
        core.set_grapheme_clusters(seed % 2 == 0);
        for index in 0..300 {
            owned_resizes += usize::from(step(&mut rng, &mut core));
            if let Err(error) = core.verify_integrity() {
                panic!("seed {seed} step {index}: {error:?}");
            }
            common::check(&core);
        }
    }
    assert!(
        owned_resizes >= 200,
        "only {owned_resizes} resizes at a prompt"
    );
}
```

- [ ] **Step 2: Run it (debug and release)**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy -p vt-core --all-targets -- -D warnings 2>&1 | tail -1
cargo test -p vt-core --test prompt_resize_integrity 2>&1 | grep "test result"
cargo test --release -p vt-core --test prompt_resize_integrity 2>&1 | grep "test result"
```
Expected: `Finished …`; `test result: ok. 1 passed` (≈3 s debug) twice. In planning the sequence made 339 resizes at an owned prompt; a heavier local run (3,000 seeds × 400 steps, release) was also clean. If it fails, the panic names the seed and step: reproduce with that seed alone before changing code.

- [ ] **Step 3: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-core/tests/prompt_resize_integrity.rs
git commit -m "$(cat <<'EOF'
test(vt-core): seeded feed/resize/prompt sequences keep the model consistent

32 seeds x 300 steps of output, prompts (0-3 rows, wide text), commands,
the alternate screen, zsh-style redraws, older-output floors and resizes
down to 1x1, in both width modes and with a 30-row cap; integrity and
cell spans checked after every step, at least 200 resizes at a prompt.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Pin the shells' redraw behaviour the design relies on

**Files:**
- Modify: `packages/terminal/shell/pty.mjs:15-31`
- Modify: `packages/terminal/shell/zsh.test.mjs:5` and append
- Modify: `packages/terminal/shell/bash.test.mjs:8` and append
- Modify: `packages/terminal/shell/fish.test.mjs:5` and append

**Interfaces:**
- Consumes: tmux (`new-session -x 120 -y 40`, `pipe-pane`, `send-keys`, and now `resize-window`).
- Produces: `runInPtySegments(command, input, { settleMs, env }) -> string[]` (the output split before every input item that has `resize: [cols, rows]` or `cut: true`); `runInPty` keeps its signature and returns the segments joined.

Why these tests exist: Decision 1 rests on the three shells counting their redraw from the rows they drew at the **old** width. If a shell release changes that, these fail and the decision must be revisited, instead of prompts silently duplicating again.

- [ ] **Step 1: Split the capture at resizes**

In `packages/terminal/shell/pty.mjs`, replace (line 15):

```js
export function runInPty(command, input, { settleMs = 1000, env = {} } = {}) {
```
with:

```js
export function runInPty(command, input, options = {}) {
	return runInPtySegments(command, input, options).join("");
}

export function runInPtySegments(command, input, { settleMs = 1000, env = {} } = {}) {
```

and replace (lines 25-31 before the edit above):

```js
		for (const item of input) {
			const { keys, enter = true, waitMs = settleMs } =
				typeof item === "string" ? { keys: item } : item;
			tmux("send-keys", "-t", session, keys, ...(enter ? ["Enter"] : []));
			sleep(waitMs);
		}
		return readFileSync(raw, "latin1");
```
with:

```js
		const cuts = [];
		for (const item of input) {
			const { keys, enter = true, waitMs = settleMs, resize, cut = false } =
				typeof item === "string" ? { keys: item } : item;
			if (resize || cut) {
				cuts.push(readFileSync(raw, "latin1").length);
			}
			if (resize) {
				tmux("resize-window", "-t", session, "-x", String(resize[0]), "-y", String(resize[1]));
			} else {
				tmux("send-keys", "-t", session, keys, ...(enter ? ["Enter"] : []));
			}
			sleep(waitMs);
		}
		const all = readFileSync(raw, "latin1");
		return [0, ...cuts].map((start, index) => all.slice(start, cuts[index] ?? all.length));
```

- [ ] **Step 2: The three tests**

`packages/terminal/shell/zsh.test.mjs` line 5 — replace:

```js
import { haveTmux, parseOscRecords, runInPty, splitEveryByte } from "./pty.mjs";
```
with:

```js
import { haveTmux, parseOscRecords, runInPty, runInPtySegments, splitEveryByte } from "./pty.mjs";
```
and append:

```js

test("after a width change redraws the prompt from its first row, counted at the old width", { skip: ptySkip }, () => {
	const [, afterResize] = runInPtySegments(
		"zsh -f -i",
		[`source ${bootstrap}`, "PROMPT=$'first-line\\nsecond $ '", { keys: "clear", waitMs: 800 }, { resize: [60, 40] }],
		{ settleMs: 800 },
	);
	const ups = afterResize.match(/\x1bM|\x1b\[1?A/g) ?? [];
	assert.equal(ups.length, 1, JSON.stringify(afterResize));
	assert.ok(afterResize.indexOf("\x1b[J") < afterResize.indexOf("first-line"), JSON.stringify(afterResize));
	assert.match(afterResize, /second \$ /);
});
```

`packages/terminal/shell/bash.test.mjs` line 8 — replace:

```js
import { haveTmux, parseOscRecords, runInPty, splitEveryByte } from "./pty.mjs";
```
with:

```js
import { haveTmux, parseOscRecords, runInPty, runInPtySegments, splitEveryByte } from "./pty.mjs";
```
and append:

```js

test("after a width change redraws only the last prompt line and never moves above it", { skip: ptySkip }, () => {
	const [, afterResize] = runInPtySegments(
		"bash --noprofile --norc -i",
		[`source ${bootstrap}`, "PS1='first-line\\nsecond \\$ '", { keys: "clear", waitMs: 800 }, { resize: [60, 40] }],
		{ settleMs: 800 },
	);
	assert.doesNotMatch(afterResize, /\x1bM|\x1b\[\d*A/, JSON.stringify(afterResize));
	assert.doesNotMatch(afterResize, /first-line/);
	assert.match(afterResize, /second \$ /);
});
```

`packages/terminal/shell/fish.test.mjs` line 5 — replace:

```js
import { parseOscRecords, runInPty, splitEveryByte } from "./pty.mjs";
```
with:

```js
import { parseOscRecords, runInPty, runInPtySegments, splitEveryByte } from "./pty.mjs";
```
and append:

```js

test("after a width change writes nothing until the next key, then moves up by its old prompt height", { skip: fishSkip || nativeOsc133Skip }, () => {
	const [, afterResize, afterKey] = runInPtySegments(
		"fish --no-config --interactive",
		[
			"function fish_prompt; echo first-line; echo -n 'second $ '; end",
			`source ${JSON.stringify(bootstrap)}`,
			{ keys: "clear", waitMs: 800 },
			{ resize: [60, 40] },
			{ keys: "x", enter: false, cut: true },
		],
		{ settleMs: 800 },
	);
	assert.doesNotMatch(afterResize, /first-line|second \$/, JSON.stringify(afterResize));
	const ups = afterKey.match(/\x1bM|\x1b\[1?A/g) ?? [];
	assert.equal(ups.length, 1, JSON.stringify(afterKey));
});
```

(`fish_prompt` is defined **before** `fish.fish` is sourced because the script saves the user's prompt at source time and restores it on every prompt, `shell/fish.fish:7-9,45-48`.)

- [ ] **Step 3: Run the shell suites**

```bash
cd "$REPO/packages/terminal" && for s in zsh bash fish; do node --test shell/$s.test.mjs 2>&1 | grep -E "^ℹ (pass|fail|skipped)" | tr '\n' ' '; echo " <- $s"; done
node --test shell/zsh.test.mjs shell/bash.test.mjs shell/fish.test.mjs 2>&1 | grep -E "width change"
```
Expected: one more passing test per shell than in Task 0 (planning: zsh 22, bash 11, fish 7; 0 failed) and three `✔ after a width change …` lines (fish's is skipped with fish < 4). Verified in planning on zsh 5.9, bash 3.2.57 and 5.3.20, fish 4.8.1, tmux 3.6b. If the bash test fails on your bash, print the segment (`JSON.stringify` is in the message) and stop: report the bytes — do not loosen the assertion.

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add packages/terminal/shell/pty.mjs packages/terminal/shell/zsh.test.mjs packages/terminal/shell/bash.test.mjs packages/terminal/shell/fish.test.mjs
git commit -m "$(cat <<'EOF'
test(shell): pin how zsh, bash and fish redraw their prompt after a resize

zsh moves up by the rows its prompt took at the old width and clears,
bash redraws only its last prompt line, fish writes nothing until the
next key and then moves up by its old height. The prompt-keeping resize
depends on exactly this; runInPtySegments splits a capture at resizes.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Gates, both wasm builds, the mirror asset

**Files:**
- Modify (binary): `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`

**Interfaces:**
- Consumes: everything above.
- Produces: the rebuilt, committed mirror wasm and the gate results for the report.

- [ ] **Step 1: Run G1–G8 in order** (Gate set G above). Every expected line must match. A failure is fixed in the task that owns the code (amend with a new commit, never a regenerated golden or baseline).

- [ ] **Step 2: Commit the mirror wasm**

```bash
cd "$REPO" && git status --short
git add backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
git commit -m "$(cat <<'EOF'
build(pty-host): rebuild vt_host.wasm for the prompt-resize vt-core

The mirror keeps reflow off, so its behaviour is unchanged (both golden
sets' mirror configuration); the binary changes because vt-core did.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```
Expected before the add: ` M backend/…/vt_host.wasm` and nothing else (no baselines, no generated files).

---

### Task 7: Docs — TERMINAL.md, survey, plain-language, roadmap checks, changelog

**Files:**
- Modify: `TERMINAL.md:96-98`, `:411-415`, insert §4.36 before `:1396`
- Modify: `docs/terminal/2026-09-19-terminal-reference-survey.md:48`, `:50`, `:58`, `:75`, `:114`, `:473`, `:1412`, `:3296`
- Modify: `docs/terminal/2026-09-24-not-done-plain-language.md:6-9`, `:61-64`
- Modify: `docs/terminal/2026-09-24-terminal-roadmap-design.md:537-538`
- Modify: `packages/terminal/CHANGELOG.md:4-5`

**Interfaces:** none (docs).

Numbers in these texts come from this plan's tests and planning runs; replace any number you measured differently with yours (the counts in G8 and the resize count in Task 4 Step 2).

- [ ] **Step 1: TERMINAL.md §2 — the shell-mode bullet**

Replace (lines 96-98):

```markdown
  - default ("shell"): `reflow_on_resize = true` → a resize evicts the frame up to
    its last non-blank row into scrollback and restarts the screen; `ESC[2J` scrolls
    the frame into scrollback (`ClearPolicy::Scroll`).
```
with:

```markdown
  - default ("shell"): `reflow_on_resize = true` → a resize evicts the frame up to
    its last non-blank row into scrollback and restarts the screen; `ESC[2J` scrolls
    the frame into scrollback (`ClearPolicy::Scroll`). At a prompt (line editor
    `Owned`) a resize keeps the prompt rows instead and pulls scrollback back (§4.36).
```

- [ ] **Step 2: TERMINAL.md §4.10**

Replace (lines 412-415):

```markdown
- Resizing an agent TUI must not push the pre-resize frame into scrollback
  (`resizing_an_agent_tui_appends_no_frame_to_scrollback`); a shell resize moves
  the frame to scrollback exactly once, never copies it. Height shrink drops rows
  below the cursor first, then from the top (tmux `screen_resize_y`).
```
with:

```markdown
- Resizing an agent TUI must not push the pre-resize frame into scrollback
  (`resizing_an_agent_tui_appends_no_frame_to_scrollback`); a shell resize moves
  the frame to scrollback exactly once, never copies it. Height shrink drops rows
  below the cursor first, then from the top (tmux `screen_resize_y`). At a shell
  prompt the prompt rows stay instead (§4.36); every other state, and the pty-host
  mirror, keeps this policy (`tests/resize_goldens.rs`).
```

- [ ] **Step 3: TERMINAL.md §4.36** — insert before the line `## 5. Known gaps (not bugs, decisions pending)` (line 1396), with one blank line before and after:

```markdown
### 4.36 A shell prompt copied into scrollback on every resize — roadmap Plan 10
- Symptom: with a visible prompt, every resize at the prompt left one stale copy
  of it in scrollback, and a prompt taller than one row left its upper rows too.
  Replaying 15 captured zsh 5.9 / bash 3.2 / bash 5.3 sessions with four resizes
  each ended with 5 copies of the prompt. Operator's own shell panes suppress the
  prompt (`backend/internal/service/shellterm/service.go:439`
  `SuppressPrompt: true`), so there the row is empty and nothing showed.
- Cause: the shell-mode resize evicted the whole frame, prompt included, and
  restarted the screen with the cursor at (0,0). The shells redraw relative to
  where they drew: measured 2026-09-26, zsh moves up by the rows its prompt and
  buffer took at the **old** width minus one, clears (`ESC[J`) and redraws; bash
  redraws only its last prompt line (moving up only within it); fish 4.8.1
  writes nothing on a width change and, on the next key, moves up by its old
  prompt height and repaints. Clamped at row 0, the redraw drew a second prompt.
- Now: while the line editor is `Owned`, on the primary screen, in a core that
  reflows on resize, `Parser::resize_for` (`crates/vt-core/src/parser/resize.rs`)
  keeps the prompt: the rows above the open block's first row go to scrollback
  and rewrap there like any evicted row (§4.2–4.4); the rows from the prompt
  start to the cursor's last row stay unrewrapped — cut at the new width (a wide
  character cut in half becomes a blank) or padded — with the cursor at the same
  row offset and column (`ScreenGrid::resize_keeping_prompt`,
  `crates/vt-core/src/screen/prompt.rs`). Kitty's "keep the current prompt from
  rewrapping" (survey §5.4; GPL-3.0, clean-room from the survey's description,
  not read), chosen over Ghostty's reflow-then-clear (`Screen.zig:2232-2290`,
  behaviour only): a reflowed prompt changes its row count, so the shells'
  old-width up-moves land mid-prompt (narrower) or in the output above it
  (wider — zsh's `ESC[J` then erases output rows), and fish would show a blank
  prompt until the next key. Then `Parser::pull_back` moves the newest
  scrollback rows back onto the top of the screen so the prompt keeps its
  distance from the bottom (Alacritty `grow_lines`/`shrink_lines`, Ghostty
  `pull_scrollback`; behaviour only), but only rows that commit back to the same
  bytes and style runs (`Parser::row_cells` commits them into a scratch buffer
  and compares; `Content::truncate_to`, `AttributeMap::truncate_to`,
  `RowIndex::pop_completed`). Flat and stable row numbers never change, so
  blocks, find hits (a session rescans history once), the scroll anchor and the
  older-output floor are untouched.
- Unchanged: a command running, the alternate screen, no shell integration
  (every Claude Code pane), agent-TUI mode, and the pty-host mirror (reflow off,
  `crates/vt-host/src/lib.rs:39`) take the old path — `tests/resize_goldens.rs`
  (12 streams generated before this change) and `tests/parser_goldens.rs` are
  unchanged and `bench:feel` has zero diff.
- Not covered: bash's upper prompt lines stay cut at a narrower width (bash
  redraws only its last line; xterm behaves the same); a prompt region taller
  than the new screen takes the old path; the pull-back stops at the first row
  that would not restore exactly (a word-cut continuation, a hanging indent, a
  trailing blank), so the prompt can sit higher on the screen than before (not
  visible in the pane); Windows ConPTY repaints its own viewport after a resize
  — whether a Git Bash pane there looks better or worse is not known. The
  pre-existing blank before a wide character that the printer wrapped still
  commits as a space (`abcd中` printed at 5 columns rewraps as `abcd 中`).
- Guards: `crates/vt-core/tests/prompt_resize.rs` (20 tests, built from the
  shells' captured bytes), `tests/prompt_resize_integrity.rs` (32 seeds × 300
  steps, `verify_integrity` and cell spans after every step, ≥ 200 resizes at a
  prompt), `tests/resize_goldens.rs`, `content.rs`/`attribute_map.rs`/`row_index`
  unit tests, `block_grid` `open_block_ref_is_the_open_block_and_nothing_after_it_closes`,
  `shell/{zsh,bash,fish}.test.mjs` "after a width change …".
```

- [ ] **Step 4: Survey — status lines, table rows, count**

In `docs/terminal/2026-09-19-terminal-reference-survey.md`:

Line 48 — replace `## Implementation status (updated 2026-09-25)` with `## Implementation status (updated 2026-09-26)`.

Line 50 — replace `46 done, 19 partial, 12 not done, 9 not pursued, 1 not needed, 1 n/a` with `48 done, 20 partial, 9 not done, 9 not pursued, 1 not needed, 1 n/a`, and at the end of the same line, after `"Roadmap Plan 9" is the parser-rework plan (`docs/superpowers/plans/2026-09-26-terminal-plan-9-parser-rework.md`).`, append ` "Roadmap Plan 10" is the shell-resize plan (`docs/superpowers/plans/2026-09-26-terminal-plan-10-shell-resize.md`).`

Line 58 — replace the row with:

```markdown
| §1.5 | Done | Roadmap Plan 10 — at a prompt (line editor `Owned`) the prompt rows stay unrewrapped for the shell's own redraw, the rows above go to scrollback and rewrap there, and growth pulls back rows that restore exactly (`TERMINAL.md` §4.36). Kitty's answer (§5.4) rather than Ghostty's clear, chosen by measuring zsh, bash and fish. Not taken: `redraw=` on `OSC 133;A` (no measured shell needs it), the mirror (reflow off, unchanged). A running command, the alternate screen and panes without shell integration keep evict-once. |
```

Line 75 — replace the row with:

```markdown
| §2.4 | Partial | Roadmap Plan 10 — at a prompt the cursor keeps its place and growth pulls scrollback rows back onto the screen (only rows that commit back byte for byte). Not done: a cell-level reflow of the live frame with the cursor carried (the rows above the prompt rewrap in scrollback instead), and anywhere but at a prompt. |
```

Line 114 — replace the row with:

```markdown
| §5.4 | Done | Roadmap Plan 10 — the current prompt's rows are kept unrewrapped where the shell's SIGWINCH redraw overwrites them (clean-room from this entry; Kitty not read). |
```

Line 473 — replace `> **Status: Not done.** Shell resize still evicts the frame once (Warp model). A non-goal of the agent-TUI spec.` with:

```markdown
> **Status: Done.** Roadmap Plan 10 (2026-09-26) — at a prompt the prompt rows stay for the shell's redraw, the rows above rewrap in scrollback, growth pulls back rows that restore exactly; Kitty's answer (§5.4) over Ghostty's clear, by measurement (`TERMINAL.md` §4.36). `redraw=` is not parsed and the mirror is unchanged.
```

Line 1412 — replace `> **Status: Not done.** No pull-back on height growth and no cursor-carrying reflow; waits on §1.5. The wide-character-at-the-cut case was already covered.` with:

```markdown
> **Status: Partial.** Roadmap Plan 10 — at a prompt the cursor keeps its place and growth pulls back scrollback rows that restore byte for byte. Not done: a cell-level live-frame reflow with the cursor carried, or anywhere but a prompt. The wide-character-at-the-cut case was already covered.
```

Line 3296 — replace `> **Status: Not done.** Shell resize still evicts the frame; Kitty's exempt-the-prompt option was not taken up. A non-goal of the agent-TUI spec.` with:

```markdown
> **Status: Done.** Roadmap Plan 10 — the prompt rows are kept unrewrapped for the shell's redraw (clean-room; `TERMINAL.md` §4.36).
```

Recount and check the sentence:

```bash
cd "$REPO" && awk -F'|' '/^\| §/ {gsub(/ /,"",$3); print $3}' docs/terminal/2026-09-19-terminal-reference-survey.md | sort | uniq -c
```
Expected: `48 Done`, `1 N/A`, `9 Notdone`, `1 Notneeded`, `9 Notpursued`, `20 Partial` — the numbers in the line-50 sentence must match.

- [ ] **Step 5: Plain-language doc, item 6**

In `docs/terminal/2026-09-24-not-done-plain-language.md`, replace (lines 7-8):

```markdown
into 20 items (items 3, 4 and 5 have since been done, roadmap Plans 5 and 1;
items 19 and 20 have since been done, roadmap Plan 3; item 16 has been done and items 17 and 18 decided, roadmap Plan 9); the 16 marked
```
with:

```markdown
into 20 items (items 3, 4 and 5 have since been done, roadmap Plans 5 and 1;
items 19 and 20 have since been done, roadmap Plan 3; item 16 has been done and items 17 and 18 decided, roadmap Plan 9; item 6 has been done, roadmap Plan 10); the 16 marked
```

and replace (lines 61-64):

```markdown
6. **Resizing without a mess (§1.5, §2.4, §5.4).** Making the window
   narrower or wider can push your current line into the history or wrap it
   oddly. *If done:* the text reflows neatly and your prompt stays where it
   is. Claude Code redraws its own screen, so this mostly affects the shell.
```
with:

```markdown
6. **Resizing without a mess (§1.5, §2.4, §5.4).** Making the window
   narrower or wider can push your current line into the history or wrap it
   oddly. *If done:* the text reflows neatly and your prompt stays where it
   is. Claude Code redraws its own screen, so this mostly affects the shell.
   **Done (roadmap Plan 10):** at a prompt, resizing leaves your prompt where
   the shell redraws it, so no old copy piles up above; the output above it
   reflows, and making the window taller brings older lines back into view.
   While a command runs, and in Claude Code panes, resizing works as before.
   Operator hides the shell's own prompt, so there you mostly see the output
   reflowing.
```

- [ ] **Step 6: Roadmap — real-app checks**

In `docs/terminal/2026-09-24-terminal-roadmap-design.md`, find the line (538):

```markdown
- **Input ordering fix (d1a962b8f):** nothing to click; covered by tests.
```
and insert **before** it:

```markdown
- **Plan 10 — shell resize:** in a zsh pane run
  `unset OPERATOR_TERMINAL_SUPPRESS_PROMPT; PROMPT=$'%~ first line\nsecond $ '`,
  then `seq 1 40`. Drag the window narrower, then wider, then taller: one
  two-line prompt stays at the bottom, the numbers above it reflow, no old prompt
  piles up above, and taller brings earlier numbers back into view. In a bash pane
  (`unset OPERATOR_TERMINAL_SUPPRESS_PROMPT; PS1='\w first\nsecond \$ '`) the same,
  except the first prompt line is cut when narrower (bash redraws only its last
  line). In a fish pane (`set -e OPERATOR_TERMINAL_SUPPRESS_PROMPT`, then press
  Enter) the prompt is redrawn after the next key. With the prompt suppressed
  (the default) resizing at a prompt looks as before. Run `sleep 5` and resize
  while it runs: as before. Resize a Claude Code pane: looks as before (its one
  duplicated row per width change is upstream, `TERMINAL.md` §4.8).
```

- [ ] **Step 7: Changelog**

In `packages/terminal/CHANGELOG.md`, after the line `## Unreleased` and its blank line (lines 3-4), insert as the first entry:

```markdown
- vt-core/shell: a resize at a shell prompt keeps the prompt (roadmap Plan 10, survey §1.5, §2.4, §5.4). While the line editor is `Owned` (OSC 7000 `input-ready`), on the primary screen, in a core that reflows on resize, `TerminalCore::resize` sends the rows above the open block's first row to scrollback (rewrapped there as before) and keeps the prompt rows unrewrapped — cut or padded, a wide character cut in half blanked — with the cursor at the same place, so zsh, bash and fish, which redraw relative to the rows they drew at the old width, overwrite them instead of leaving a stale copy in scrollback (Kitty's behaviour, clean-room from the survey; Ghostty's reflow-and-clear rejected by measurement, `TERMINAL.md` §4.36). Then the newest scrollback rows are pulled back onto the screen so the prompt keeps its distance from the bottom — only rows that commit back to the same bytes and style runs. Row numbers do not change. A command running, the alternate screen, panes without shell integration, agent-TUI mode and the pty-host mirror are unchanged (`tests/resize_goldens.rs`, `tests/parser_goldens.rs`). New: `Content::truncate_to`, `AttributeMap::truncate_to`, `RowIndex::pop_completed`, `BlockGrid::open_block_ref`; `shell/pty.mjs` `runInPtySegments`. Both wasm artifacts and the daemon must be rebuilt.
```

- [ ] **Step 8: Check and commit**

```bash
cd "$REPO" && git diff --stat
git add TERMINAL.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/terminal/2026-09-24-not-done-plain-language.md docs/terminal/2026-09-24-terminal-roadmap-design.md packages/terminal/CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(terminal): shell resize keeps the prompt (TERMINAL.md §4.36)

Records the measured zsh/bash/fish redraw behaviour, the Kitty-over-Ghostty
decision, the exact-restore pull-back, what stays unchanged, and the
real-app checks. Survey §1.5 and §5.4 done, §2.4 partial.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Push and report (do not merge)

**Files:** none.

- [ ] **Step 1: Final gates** — run G1 and G8 once more on the final tree (docs-only since Task 6, so G2–G7 stand).

- [ ] **Step 2: Push**

```bash
cd "$REPO" && git status --short && git log --oneline origin/development..HEAD
git push -u origin terminal/plan-10-shell-resize
```
Expected: a clean status; seven commits (Tasks 1–7; Task 6 is the wasm commit); the push succeeds. Do not open or merge a PR unless asked.

- [ ] **Step 3: Completion report** — reply with:
  1. Branch and the seven commit hashes with subjects.
  2. Every gate G1–G8 with its quoted output line(s), or `not run: <reason>` (e.g. `bench:selection` on Linux, fish < 4, no zsh for the integration tests).
  3. Test counts against Task 0 (vitest five suites, shells, Go).
  4. Deviations from this plan, each with its reason (a quoted text not found, a number that differs).
  5. The real-app checklist for the reviewer (copied from the roadmap entry added in Task 7 Step 6): zsh, bash and fish panes resized narrower, wider and taller at a visible prompt — prompt intact, output reflowed, earlier lines pulled back; resize during `sleep 5` — unchanged; Claude Code pane resized — looks as before.
