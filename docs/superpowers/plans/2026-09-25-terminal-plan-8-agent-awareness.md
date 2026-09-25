# Terminal Plan 8 — Agent Awareness in the Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **If the superpowers skills are not installed in your environment, run the process by hand:** one fresh implementer subagent per task (give it the task text, Global Constraints and Review Focus), then one spec-compliance review subagent and one code-quality review subagent per task, fix what they find, and after the last task one whole-branch review subagent over `git diff origin/development...HEAD`.

**Goal:** `packages/terminal` learns three product-independent things about an agent running in a pane: in-band agent events (`OSC 777 ; agent-state ; v=1 ; state=… ST`) parsed by `vt-core` and surfaced as `TerminalCore.onAgentEvent`; an idle/prompt detector (`TerminalCore.agentActivity()` / `onAgentActivity`, states `active | pollingForIdle | idle | prompting`); and `TerminalCore.readBlockOutput(id, { compact: true })`, which strips spinner lines and repeated redraws.

**Architecture:** `vt-core` gets an `agent` module: `ProgramState::osc777` (Plan 3's dispatcher, `crates/vt-core/src/program.rs:238`) routes the `agent-state` extension to an `AgentChannel` that parses, dedupes and queues events (cap 16); history chunks and older answers never reach it (they bypass vte, `lib.rs` `feed_raw`), and a replay frame between an adopted `origin=` mark and `ready=` is silenced. `vt-core` also counts live bytes that reach vte (`live_output_bytes`), excluding the replay frame, history rows and gated answers. `vt-wasm` exports both; `ts/core` polls events after every feed/tick (keyed on the program generation) and runs a timer-driven activity monitor over the live byte counter and the cursor line (VS Code's high-confidence prompt patterns, ported under MIT). `readBlockOutput` joins a block's logical lines from the snapshot and, with `compact`, trims, drops spinner lines, collapses blank runs and back-to-back repeats and drops frames of ≥ 3 lines redrawn within the last 256 lines. **Operator consumes none of this yet** (user decision 2026-09-25): it keeps its local `opr` hooks and `opr mcp` `session_report`; the in-band channel exists for future SSH/remote agents and for other hosts of the package.

**Tech Stack:** Rust 1.96.0 (`vt-core`, `vt-wasm`, `vt-host`), wasm32 + wasm-bindgen 0.2.127, Go 1.25 (pty-host `vtwasm` guard test only), TypeScript 5.9 + vitest 4.1.8.

**Spec:** `docs/terminal/2026-09-24-terminal-roadmap-design.md` "Plan 8 — Agent awareness in the terminal (§7.1, §6.9)" and "Rules every plan obeys"; survey `docs/terminal/2026-09-19-terminal-reference-survey.md` §7.1 and §6.9. The user's fixed decisions for this plan (2026-09-25) override the roadmap where they differ: **terminal package part only**; Operator does not change how it decides agent state; no remote/SSH wiring; no Operator code consumes the new APIs.

**Tree this plan was written and proven against:** `origin/development` @ `ce4941652` ("chore(terminal): rebuild the mirror wasm, pin the boundary floor reset in TS, document the Plan 7 review fixes"). Every code block below was built and tested in a scratch worktree of that commit on 2026-09-25 (macOS arm64): `cargo test` all green, `cargo clippy --all-targets -- -D warnings` clean, ts/core 164 tests, renderer-dom 985, react 134, editor 175, completions 109, `check:boundaries` pass, pty-host Go tests `ok`, `bench:agent:gate` PASS, `bench:agent:scroll` full coverage, `bench:feel` zero pixel diff.

## Global Constraints

- Branch `terminal/plan-8-agent-awareness` from `origin/development`. Never commit to `development` or `master`, never merge, never force-push.
- Commits name explicit paths only: `git add <path> …`. Never `git add -A`, `git add .`, `git commit -a` or `git stash`.
- Every commit message ends with the trailer line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- No comments in new code (Rust, Go, TS, tests). The single exception is the MIT licence header that `ts/core/src/input-patterns.ts` must carry because it ports VS Code code (the same header `ts/renderer-dom/src/link-parsing.ts` carries).
- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no Operator name, path or concept under `crates/`, `ts/` or `protocol/`. That is why the wire name is `agent-state`, not `operator-agent`.
- **Warp is AGPL-3.0: clean-room only.** Do not open, read or copy any Warp file. The wire format here is ours; only the survey's prose description of Warp's behaviour (§7.1) informed it.
- **VS Code is MIT:** `input-patterns.ts` ports `detectsHighConfidenceInputPattern` verbatim with `LICENSE-VSCODE-MIT` and an attribution file beside it; the idle timing follows VS Code's behaviour without copying code.
- No file under `packages/terminal` may exceed 600 lines (`npm run check:boundaries`). After this plan: `crates/vt-core/src/lib.rs` 585 (was 597), `crates/vt-core/src/program.rs` 429, `crates/vt-wasm/src/lib.rs` 581 (unchanged count), `ts/core/src/terminal-core.ts` 593 (was 598).
- A `vt-core` change is not live until **both** wasm artifacts are rebuilt (`TERMINAL.md` §6): the renderer's (`npm run build:wasm -- --force`, gitignored) and the host mirror's (`cargo build --release -p vt-host --target wasm32-unknown-unknown`, copied to `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`, **committed**), then the pty-host Go tests.
- This plan changes no pixels and no renderer code. `bench:feel` must stay at zero diff against the Task 0 baseline recorded in this environment. Never commit re-recorded baselines (`packages/terminal/bench/agent-session/baselines/**`); `bench:feel -- --record` and `bench:affordances` rewrite committed PNGs — restore with `git checkout -- packages/terminal/bench/agent-session/baselines` (and `git clean -fdq packages/terminal/bench/agent-session/baselines`).
- New `TERMINAL.md` section number: **§4.34**.
- Specs, docs and the completion report cite `file:line` or write "not known". Numbers in docs are the ones measured below or re-measured by you, quoted with where they came from.
- Tool gaps are reported, not hidden: when a command cannot run, write `not run: <reason>` in the completion report. `bench:selection` sends Meta+C, which Linux Chromium does not treat as copy: on Linux record `not run: Linux copy chord`, not a failure.

## Review Focus

1. **A reopened pane must not replay agent state.** The attach replay frame, history chunks and "Load older output" answers carry old bytes; none may raise an agent event or flip activity to `active`. Pinned by `agent_events.rs` `a_history_chunk_never_raises_an_agent_event`, `an_older_answer_split_byte_by_byte_never_raises_an_agent_event`, `an_event_in_the_replay_frame_is_ignored_and_live_events_after_ready_fire`, `live_output_counts_live_bytes_only`; TS `agent-events.test.ts` "never fires for the replay frame, a history chunk or an older answer"; `agent-activity.test.ts` "counts live output only…".
2. **An event split anywhere across PTY reads, or with an older answer landing inside it.** Expected: exactly one event, the same as whole. Pinned by `every_vector_case_split_byte_by_byte_yields_the_same_events`, `an_older_answer_landing_inside_a_live_event_keeps_the_live_event`, and the TS byte-by-byte vector test.
3. **A hostile or broken sender:** oversized payloads (vte silently truncates an OSC at 1,024 bytes, `vte-0.15.0/src/lib.rs:46`, `no-std` build), bad percent escapes, repeated keys, a flood of 10,000 events. Expected: ignored or capped, never a partial event, never unbounded memory. Pinned by the vector cases `payload-filling-the-1024-byte-osc-buffer-ignored`, `malformed-percent-escape-ignored`, `repeated-key-ignored`, `a_flood_keeps_only_the_newest_pending_events`, `a_flood_of_identical_events_queues_one`, TS "keeps only the newest sixteen events…".
4. **A hidden window.** WebKit throttles timers and the renderer's drain to about once a second (`TERMINAL.md` §4.25), so a streaming agent is parsed in one-second bursts. Expected: never `idle` while output keeps arriving. Pinned by `agent-activity.test.ts` "never reports idle while output arrives once a second…" (it does report `pollingForIdle` between bursts; documented in `TERMINAL.md` §5).
5. **`compact` must not eat real output.** Twenty identical 3,000-line turns (`claude-long-50k`) must all survive; a repeat of only two lines, or one farther back than 256 lines, is kept. Pinned by `block-output.test.ts` "claude-long-50k: compact keeps all twenty turns…" and `compact-output.test.ts` "keeps a repeat of only two lines and a repeat beyond the lookback".

---

## Design decisions (each one decided; evidence in brackets)

- **Wire format (ours):** `OSC 777 ; agent-state ; v=1 ; state=<working|waiting|idle|done> [; detail=<percent-encoded UTF-8>] (ST | BEL)`. OSC 777 is the rxvt-unicode extension OSC that Plan 3 already classifies as `OscKind::RxvtExtension` and dispatches to `ProgramState::osc777` (`crates/vt-core/src/program.rs:40,105-108,238-248`), which today reads only the `notify` extension; `agent-state` is a second extension name, checked first, so a `notify` payload can never parse as an agent event and vice versa [vector `notify-is-not-an-agent-event`, test `a_notify_beside_an_agent_event_still_notifies_and_neither_leaks_into_the_other`]. The name is product-neutral (§3.1), not the brief's example `operator-agent`.
- **Grammar:** fields after the extension are `key=value`, any order, one leading space tolerated (as OSC 7000, `protocol/SPEC.md` §4.1), empty fields ignored, unknown keys ignored (forward compatibility). `v` must be exactly `1` (a higher version is ignored whole, as `SPEC.md` §4.2); `state` must be one of the four; a field without `=` or a repeated key rejects the event (no "which one wins" ambiguity). `detail` is strictly percent-decoded (a `%` without two hex digits rejects the event), decoded as lossy UTF-8, stripped of control characters and truncated to 256 bytes on a character boundary with Plan 3's `clean_text` (`program.rs:360`).
- **Size cap = vte's buffer:** vt-core builds vte with `default-features = false` (`packages/terminal/Cargo.toml:18`), so the OSC payload buffer is an `ArrayVec` of `MAX_OSC_RAW = 1024` bytes that silently drops further bytes (`vte-0.15.0/src/lib.rs:46,62,427`). A payload of 1,024 bytes or more is therefore indistinguishable from a truncated one and is ignored (`MAX_AGENT_OSC_BYTES = 1024`); 1,023 is accepted [vectors `payload-of-1023-bytes-accepted`, `payload-filling-the-1024-byte-osc-buffer-ignored`; the first draft's "> 1024 after the extension" check never fired because vte had already truncated — found by that vector]. vte keeps at most 16 parameters (`MAX_OSC_PARAMS`, `lib.rs:45`): fields after the 14th are never seen; `SPEC.md` says so.
- **Rate:** identical consecutive `(state, detail)` pairs are dropped; a different detail with the same state is a new event; a process-boundary mark (`OSC 7000;v=1;boundary=`) forgets the last event (`ProgramState::reset_for_new_process`, called from `parser/blocks.rs:41`). Pending events are capped at `MAX_PENDING_AGENT_EVENTS = 16`, oldest dropped (the same cap and policy as Plan 3's notifications, `program.rs:9,219-221`). Each queued event bumps the program generation, which is how the TS side knows to drain without a wasm call per feed.
- **Never from loading or replaying output:** history chunks (attach history and older answers) are consumed by the `HistoryReceiver`, whose `osc_dispatch` handles only hyperlinks (`crates/vt-core/src/history.rs:172-176`), and their framing marks are held out of vte by `AnswerGate` (`answer_gate.rs`, Plan 7) — so no code is needed for them, only tests. The attach **replay frame** does go through vte, so `AgentChannel` is silenced from an adopted `origin=` mark until `ready=` (`lib.rs` `feed_raw`, the `ReplayOrigin` / `ReplayReady` arms). An `origin=` mark that is not adopted (rows already exist) silences nothing [test `an_origin_mark_after_rows_exist_does_not_silence_events`]. The pty-host never writes an agent event into a replay: `vt_replay` re-renders text only.
- **Where the detector lives: `ts/core`.** It needs only the core's live byte counter, the snapshot's cursor line and a clock — no DOM — so any host that has a `TerminalCore` gets it (renderer-dom would tie it to a mounted view). API: `agentActivity(): AgentActivityState` (evaluated now), `onAgentActivity(listener): () => void`. The monitor runs a `setTimeout` only while it has a listener and only until it reaches `idle`; the last teardown and `dispose()` cancel it.
- **Detector states and timing (VS Code, MIT, behaviour):** VS Code polls at `MinPollingDuration = 500` ms doubling each poll and calls a terminal idle after `MinIdleEvents = 2` consecutive polls with no data (`vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/monitoring/types.ts:45-52`, `outputMonitor.ts` `_waitForIdle`), i.e. two quiet intervals of 500 and 1,000 ms. Ours is time-based on the same numbers: live output in the last `ACTIVITY_POLLING_AFTER_MS = 500` ms → `active`; quiet ≥ 500 ms and the cursor line matches a high-confidence prompt → `prompting`; quiet 500–1,499 ms → `pollingForIdle`; quiet ≥ `ACTIVITY_IDLE_AFTER_MS = 1500` ms → `idle`. A fresh core with no output is `idle`. The prompt patterns are VS Code's `detectsHighConfidenceInputPattern` (nine regexes, verbatim). Its broader `: `/`? ` rules are not ported: VS Code uses them only when it knows the command is running (`outputMonitor.ts` `detectsLikelyInputRequiredPattern` doc comment), which this package cannot know.
- **Activity signal = live bytes, not the generation:** `vt-core` counts bytes handed to vte after `AnswerGate` filtering (`advance_vte`), skipping the replay window, and resets the count when a fresh core adopts a replay origin (so the `origin=` mark's own bytes do not count). History rows never reach vte. The TS core reads the counter after every feed and tick. The generation would have counted history chunks, resizes and replays as "output".
- **Cursor line:** the snapshot row under the cursor (the alternate screen's when it is active), padded with spaces to the cursor column so VS Code's "trailing space after the question" patterns can match. Columns are counted in code points, not cells — an approximation on rows with wide characters (documented).
- **Measured on the three Claude Code recordings (2026-09-25, this plan's scratch run):** the recordings carry no timestamps, so the test replays one frame every 100 ms — a frame is each DEC 2026 block (`ESC[?2026l`-terminated) for `claude-spinner-10s` (120 frames) and `claude-markdown-reply` (157), and each title write (`ESC]0;`) for `claude-long-50k` (1,048; it has no DEC 2026). Result: exactly one `active` report at the first frame and none other while frames arrive; `pollingForIdle` 500 ms and `idle` 1,500 ms after the last byte — spinner: last byte 11,900 ms → 12,400 → 13,400; markdown: 15,600 → 16,100 → 17,100; long: 104,700 → 105,200 → 106,200. `prompting`: 0 of 1,325 frame boundaries (Claude Code's idle `❯ ` line does not match). `claude-markdown-reply` and `claude-long-50k` end on the `✳` title with the `❯` prompt, so "idle at the ✳ prompt" holds 1.5 s after their last byte; `claude-spinner-10s` ends mid-turn (title `◑`) and reads `idle` 1.5 s after the recording stops only because no further bytes exist. How long real Claude Code pauses between frames while working is **not known** (no timestamps); any pause under 500 ms stays `active`.
- **`readBlockOutput` did not exist.** The brief says "find the existing readBlockOutput API": there is none in `packages/terminal` (only prose mentions in `TERMINAL.md:1266` and the survey); the nearest thing is the `BlockTextSource.output(id)` interface of `ts/renderer-dom/src/block-actions.ts:10-13`, which nothing in the package implements. This plan adds `TerminalCore.readBlockOutput(id: BlockId, options?: { compact?: boolean; maxLines?: number }): string | null` in `ts/core` (null for an unknown block or a disposed core): the block's rows `[firstRow, firstRow + rowCount)` joined as logical lines (`snapshotLogicalLines`, so a soft-wrapped line is one line), `\n`-separated, trailing blank lines dropped. Redaction (`secretPatterns`) is a renderer concern and is not applied here (documented).
- **`compact: true`:** every line `trimEnd`; drop spinner status lines (`/^\s*[⠀-⣿·✢✳✶✻✽◐-◓]\s+\S.*(?:…|\.\.\.)/u` — a braille or Claude Code spinner glyph, a space, text, and an ellipsis; Claude's finished line `✻ Baked for 11s · done` has no ellipsis and stays); collapse blank runs to one and drop leading/trailing blanks; drop a line equal to the previous line; drop a run that repeats a run of ≥ `COMPACT_MIN_REDRAW_LINES = 3` non-blank lines starting within the last `COMPACT_REDRAW_LOOKBACK = 256` kept lines (a repainted frame). `maxLines` (integer ≥ 3, else `RangeError`) keeps the head and tail around `… N lines omitted …` and applies with or without `compact`. It is lossy by design and opt-in.
- **Measured compact (same scratch run):** `claude-spinner-10s` 25 → 24 lines (the live `✽ Flambéing… (13s · still thinking…)` line); `claude-markdown-reply` in agent-TUI mode 83 → 80, and without agent-TUI mode (a host that does not know the pane is an agent: every resize scrolls the frame into history) 101 → 88 lines, the banner from 4 copies to 1; `claude-long-50k` 60,134 → 60,134 lines (404,287 → 402,206 characters, trailing spaces only) — all 60,000 number lines of its twenty turns kept, 24.9–30.5 ms per call in node on the planning Mac.
- **Operator:** nothing wired. The pty-host mirror (which runs the same vt-core) parses the events into its capped queue and drops them; `publishProgramLocked` (`backend/internal/adapters/runtime/ptyhost/program.go:44-72`) publishes only a changed title and notifications, so an agent event's generation bump sends watchers nothing [Go guard `TestAnAgentEventIsNeitherATitleNorANotificationInTheMirror`]. Future SSH work would drain `take_agent_events` in the mirror or `onAgentEvent` in the renderer.
- **File splits to stay under 600 lines:** `crates/vt-core/src/lib.rs` moves its six terminal-mode getters (`application_cursor_keys` … `mouse_tracking_level`, `lib.rs:568-590`) verbatim into a new `crates/vt-core/src/core_modes.rs`; `ts/core/src/terminal-core.ts` moves `budgetNow`, `validateEvenLength`, `validateMultipleOf`, `parseBlockId` (`terminal-core.ts:569-597`) and the find-result decode loop (`:426-439`) into a new `ts/core/src/core-checks.ts`.

## File map

| File | Task | Responsibility |
|---|---|---|
| `packages/terminal/protocol/agent-vectors/make-agent-vectors.py`, `agent-state.json` (new) | 1 | the vector table and its generator |
| `packages/terminal/crates/vt-core/src/agent.rs` (new) | 1 | `AgentState`, `AgentEvent`, `AgentChannel`, `parse_agent_fields`, `TerminalCore::take_agent_events` / `live_output_bytes` |
| `packages/terminal/crates/vt-core/src/core_modes.rs` (new) | 1 | the six mode getters moved out of `lib.rs` |
| `packages/terminal/crates/vt-core/src/program.rs` | 1 | `agent` field, `agent()`/`agent_mut()`, route `agent-state`, reset on boundary, `clean_text` `pub(crate)` |
| `packages/terminal/crates/vt-core/src/lib.rs` | 1 | modules, `live_output` counter, replay window |
| `packages/terminal/crates/vt-core/tests/agent_events.rs` (new) | 1 | behaviour tests |
| `packages/terminal/protocol/SPEC.md`, `protocol/README.md` | 1 | normative §10 and the index row |
| `packages/terminal/crates/vt-wasm/src/{program.rs,lib.rs}`, `tests/program_exports.rs` | 2 | wasm exports |
| `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`, `vtwasm/program_test.go` | 2 | rebuilt mirror, Go guard |
| `packages/terminal/ts/core/src/{core-checks.ts,agent-events.ts,agent-events.test.ts}` (new), `terminal-core.ts`, `index-browser.ts` | 3 | `onAgentEvent` |
| `packages/terminal/ts/core/src/{input-patterns.ts,LICENSE-VSCODE-MIT,VSCODE-INPUT-PATTERNS-ATTRIBUTION.md,agent-activity.ts,agent-activity.test.ts}` (new), `terminal-core.ts`, `index-browser.ts` | 4 | the detector |
| `packages/terminal/ts/core/src/{compact-output.ts,compact-output.test.ts,block-output.ts,block-output.test.ts}` (new), `terminal-core.ts`, `index-browser.ts` | 5 | `readBlockOutput` |
| `packages/terminal/CHANGELOG.md`, `TERMINAL.md`, survey, plain-language doc | 7 | docs |

---

### Task 0: Branch, toolchains, baselines

**Files:** none committed.

- [ ] **Step 1: Branch**

```bash
export REPO="$(git rev-parse --show-toplevel)"
cd "$REPO" && git fetch origin && git checkout -b terminal/plan-8-agent-awareness origin/development
git log --oneline -1
```
Expected: `ce4941652 chore(terminal): rebuild the mirror wasm, pin the boundary floor reset in TS, document the Plan 7 review fixes` (or a later commit; if later, every edit below quotes the text it replaces — apply by that text, and if a quoted text is not found, stop and report the file and quote).

- [ ] **Step 2: Toolchains** (each command, then its expected output)

```bash
cd "$REPO/packages/terminal" && rustup show active-toolchain && rustup target list --installed | grep wasm32
```
Expected: `1.96.0-…` and `wasm32-unknown-unknown` (`rust-toolchain.toml` pins both; `rustup` installs them on first use).

```bash
wasm-bindgen --version || cargo install wasm-bindgen-cli --version 0.2.127 --locked
wasm-bindgen --version
```
Expected: `wasm-bindgen 0.2.127` exactly (`scripts/build-wasm.mjs:22` refuses any other).

```bash
export GOTOOLCHAIN=auto
cd "$REPO/backend" && go version
```
Expected: a version ≥ `go1.25.7` (`backend/go.mod:3`). Direct toolchain downloads may be blocked; `GOTOOLCHAIN=auto` fetches through the module proxy. Keep `GOTOOLCHAIN=auto` exported for the whole session.

```bash
cd "$REPO/packages/terminal" && npm ci --no-audit --no-fund
cd "$REPO/frontend" && npm ci --no-audit --no-fund
cd "$REPO/packages/terminal" && npx playwright install chromium
```
If `playwright install` fails with HTTP 403 (CDN blocked): `ls /opt/pw-browsers`, read the directory names Playwright wants from the error (`chromium-<rev>`, `chromium_headless_shell-<rev>`), and symlink each wanted name under `/opt/pw-browsers` to the preinstalled directory of the same kind (outside the repository), e.g. `ln -s /opt/pw-browsers/chromium-<have> /opt/pw-browsers/chromium-<want>`; then `export PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers`. Never commit anything for this.

- [ ] **Step 3: Baselines of the unmodified tree**

```bash
cd "$REPO/packages/terminal" && cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-baseline-done
npm run build:wasm -- --force && npm run build:ts
for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  "); done
npm run check:boundaries 2>&1 | tail -2
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/... 2>&1 | tail -3
```
Expected (planning run): no FAILED/panicked line; `Tests  101 passed (101)` (core), `985` (renderer-dom), `134` (react), `175` (editor), `109` (completions); `boundary check passed`; three `ok` lines. Record your counts. `TestProcessEnvironmentLetsOverridesWin` in `ptyhost` is a known pre-existing failure (`TERMINAL.md` §5); if it fails here it is not yours.

```bash
cd "$REPO/packages/terminal" && npm run bench:feel -- --record 2>&1 | tail -2
rm -rf "$HOME/plan8-feel-baseline" && cp -R bench/agent-session/baselines "$HOME/plan8-feel-baseline"
git -C "$REPO" checkout -- packages/terminal/bench/agent-session/baselines && git -C "$REPO" clean -fdq packages/terminal/bench/agent-session/baselines
git -C "$REPO" status --short
```
Expected: `recorded feel baselines`; then a clean `git status`. `$HOME/plan8-feel-baseline` is this machine's picture of the unmodified tree; Task 6 compares against it. (Committed baselines were recorded on the owner's Mac and do not reproduce on Linux.)

```bash
cd "$REPO/packages/terminal" && npm run bench:agent:gate 2>&1 | tail -1
```
Expected: `PASS agent-session gate` (unmodified tree; if it fails here, record it as pre-existing).

---

### Task 1: vt-core agent events, live output counter, protocol §10

**Files:**
- Create: `packages/terminal/protocol/agent-vectors/make-agent-vectors.py`, `packages/terminal/protocol/agent-vectors/agent-state.json` (generated), `packages/terminal/crates/vt-core/tests/agent_events.rs`, `packages/terminal/crates/vt-core/src/agent.rs`, `packages/terminal/crates/vt-core/src/core_modes.rs`
- Modify: `packages/terminal/crates/vt-core/src/program.rs:67,91-93,152,238-244,360`, `packages/terminal/crates/vt-core/src/lib.rs:1,10,88,117,250-258,321,564-591`, `packages/terminal/protocol/SPEC.md` (append §10), `packages/terminal/protocol/README.md:10-14`

**Interfaces:**
- Produces (Rust, `vt_core::agent`): `AGENT_EXTENSION: &[u8] = b"agent-state"`, `MAX_AGENT_OSC_BYTES = 1024`, `MAX_AGENT_DETAIL_BYTES = 256`, `MAX_PENDING_AGENT_EVENTS = 16`; `enum AgentState { Working, Waiting, Idle, Done }` with `parse(&[u8]) -> Option<Self>` and `as_str(self) -> &'static str` (`"working"|"waiting"|"idle"|"done"`); `struct AgentEvent { pub state: AgentState, pub detail: String }`; `struct AgentChannel` with `osc(&mut self, fields: &[&[u8]]) -> bool` (true = queued), `take()`, `replaying()`, `set_replaying(bool)`, `reset_for_new_process()`; `parse_agent_fields(&[&[u8]]) -> Option<AgentEvent>`.
- Produces (`vt_core::TerminalCore`): `take_agent_events(&mut self) -> Vec<AgentEvent>`, `live_output_bytes(&self) -> u64`.
- Produces (`vt_core::program::ProgramState`): `agent(&self) -> &AgentChannel`, `agent_mut(&mut self) -> &mut AgentChannel`; `pub(crate) fn clean_text`.

- [ ] **Step 1: Write the vector generator and generate the vectors**

Create `packages/terminal/protocol/agent-vectors/make-agent-vectors.py` with exactly this content:

```python
import json
import pathlib

E = "\u001b]777;agent-state;"
BEL = "\u0007"
ST = "\u001b\\"

cases = [
    ("minimal-bel", E + "v=1;state=working" + BEL, [("working", "")]),
    ("st-terminator-with-detail", E + "v=1;state=waiting;detail=Allow%20Bash%3F" + ST, [("waiting", "Allow Bash?")]),
    ("every-state-in-order", E + "v=1;state=working" + BEL + E + "v=1;state=waiting" + BEL + E + "v=1;state=idle" + BEL + E + "v=1;state=done" + BEL, [("working", ""), ("waiting", ""), ("idle", ""), ("done", "")]),
    ("identical-consecutive-events-collapse", E + "v=1;state=working" + BEL + "text" + E + "v=1;state=working" + BEL, [("working", "")]),
    ("same-state-new-detail-is-a-new-event", E + "v=1;state=working;detail=Read" + BEL + E + "v=1;state=working;detail=Edit" + BEL, [("working", "Read"), ("working", "Edit")]),
    ("a-state-returning-after-another-fires-again", E + "v=1;state=working" + BEL + E + "v=1;state=done" + BEL + E + "v=1;state=working" + BEL, [("working", ""), ("done", ""), ("working", "")]),
    ("fields-in-any-order-with-a-space-after-the-separator", E + "state=done; v=1" + BEL, [("done", "")]),
    ("unknown-key-ignored", E + "v=1;state=idle;session=42" + BEL, [("idle", "")]),
    ("empty-trailing-field-ignored", E + "v=1;state=idle;" + BEL, [("idle", "")]),
    ("higher-version-ignored", E + "v=2;state=working" + BEL, []),
    ("missing-version-ignored", E + "state=working" + BEL, []),
    ("missing-state-ignored", E + "v=1;detail=x" + BEL, []),
    ("unknown-state-ignored", E + "v=1;state=paused" + BEL, []),
    ("repeated-key-ignored", E + "v=1;state=working;state=done" + BEL, []),
    ("field-without-equals-ignored", E + "v=1;state=working;oops" + BEL, []),
    ("malformed-percent-escape-ignored", E + "v=1;state=working;detail=100%" + BEL, []),
    ("detail-decodes-utf8-and-drops-control-characters", E + "v=1;state=done;detail=caf%C3%A9%0A%1Bok" + BEL, [("done", "caféok")]),
    ("detail-capped-at-256-bytes", E + "v=1;state=working;detail=" + "a" * 300 + BEL, [("working", "a" * 256)]),
    ("payload-of-1023-bytes-accepted", E + "v=1;state=working;x=" + "c" * 987 + BEL, [("working", "")]),
    ("payload-filling-the-1024-byte-osc-buffer-ignored", E + "v=1;state=working;x=" + "b" * 1100 + BEL, []),
    ("extension-name-is-case-sensitive", "\u001b]777;Agent-State;v=1;state=working" + BEL, []),
    ("notify-is-not-an-agent-event", "\u001b]777;notify;Build;done" + BEL, []),
    ("other-osc-numbers-are-not-agent-events", "\u001b]7000;agent-state;v=1;state=working" + BEL + "\u001b]9;agent-state;v=1;state=working" + BEL, []),
    ("an-ignored-event-does-not-break-the-next-one", E + "v=9;state=working" + BEL + E + "v=1;state=idle" + BEL, [("idle", "")]),
]

doc = {
    "name": "agent-state",
    "description": "OSC 777 ; agent-state ; v=1 ; state=<working|waiting|idle|done> [; detail=<percent-encoded UTF-8>] (BEL | ST). Each case is fed to a fresh core; events lists what take_agent_events returns, in order.",
    "cases": [
        {"name": name, "input": data, "events": [{"state": state, "detail": detail} for state, detail in events]}
        for name, data, events in cases
    ],
}

out = pathlib.Path(__file__).resolve().parent / "agent-state.json"
out.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(out)
```

Run:
```bash
cd "$REPO/packages/terminal/protocol/agent-vectors" && python3 make-agent-vectors.py && sha256sum agent-state.json && grep -c '"name"' agent-state.json
```
Expected: the path of `agent-state.json`, then `1bfbabd2e5d216eaab8cb7b249c397254291a1ff0125862e635f75796edacacc  agent-state.json`, then `25` (24 cases plus the file's own name). On macOS use `shasum -a 256`.

- [ ] **Step 2: Write the failing integration tests**

Create `packages/terminal/crates/vt-core/tests/agent_events.rs` with exactly this content:

```rust
use vt_core::agent::{AgentEvent, AgentState, MAX_PENDING_AGENT_EVENTS};
use vt_core::program::ProgramNotification;
use vt_core::TerminalCore;

const VECTORS: &str = include_str!("../../../protocol/agent-vectors/agent-state.json");

struct Case {
    name: String,
    input: Vec<u8>,
    events: Vec<(String, String)>,
}

fn cases() -> Vec<Case> {
    let doc: serde_json::Value = serde_json::from_str(VECTORS).expect("vector file is JSON");
    doc["cases"]
        .as_array()
        .expect("cases")
        .iter()
        .map(|case| Case {
            name: case["name"].as_str().expect("name").to_string(),
            input: case["input"].as_str().expect("input").as_bytes().to_vec(),
            events: case["events"]
                .as_array()
                .expect("events")
                .iter()
                .map(|event| {
                    (
                        event["state"].as_str().expect("state").to_string(),
                        event["detail"].as_str().expect("detail").to_string(),
                    )
                })
                .collect(),
        })
        .collect()
}

fn core() -> TerminalCore {
    TerminalCore::new(80, 1_000).expect("core")
}

fn pairs(events: Vec<AgentEvent>) -> Vec<(String, String)> {
    events
        .into_iter()
        .map(|event| (event.state.as_str().to_string(), event.detail))
        .collect()
}

fn event(state: AgentState, detail: &str) -> AgentEvent {
    AgentEvent {
        state,
        detail: detail.to_string(),
    }
}

#[test]
fn every_vector_case_yields_its_events() {
    let cases = cases();
    assert!(cases.len() >= 20, "expected the full vector table");
    for case in cases {
        let mut core = core();
        core.feed(&case.input);
        assert_eq!(
            pairs(core.take_agent_events()),
            case.events,
            "{}",
            case.name
        );
    }
}

#[test]
fn every_vector_case_split_byte_by_byte_yields_the_same_events() {
    for case in cases() {
        let mut core = core();
        for byte in &case.input {
            core.feed(std::slice::from_ref(byte));
        }
        assert_eq!(
            pairs(core.take_agent_events()),
            case.events,
            "{}",
            case.name
        );
    }
}

#[test]
fn events_are_taken_once() {
    let mut core = core();
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(core.take_agent_events().len(), 1);
    assert!(core.take_agent_events().is_empty());
}

#[test]
fn an_agent_event_bumps_the_program_generation_and_a_duplicate_does_not() {
    let mut core = core();
    let start = core.program_generation();
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(core.program_generation().wrapping_sub(start), 1);
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(core.program_generation().wrapping_sub(start), 1);
}

#[test]
fn a_notify_beside_an_agent_event_still_notifies_and_neither_leaks_into_the_other() {
    let mut core = core();
    core.feed(b"\x1b]777;notify;Build;done\x07\x1b]777;agent-state;v=1;state=done\x07");
    assert_eq!(
        core.take_notifications(),
        vec![ProgramNotification {
            title: "Build".to_string(),
            body: "done".to_string(),
        }]
    );
    assert_eq!(core.take_agent_events(), vec![event(AgentState::Done, "")]);
}

#[test]
fn an_agent_event_prints_nothing() {
    let mut core = core();
    core.feed(b"a\x1b]777;agent-state;v=1;state=idle;detail=hidden\x07b");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.row_text(0), "ab");
}

#[test]
fn a_flood_keeps_only_the_newest_pending_events() {
    let mut core = core();
    for index in 0..10_000 {
        let state = if index % 2 == 0 { "working" } else { "waiting" };
        core.feed(format!("\x1b]777;agent-state;v=1;state={state};detail={index}\x07").as_bytes());
    }
    let events = core.take_agent_events();
    assert_eq!(events.len(), MAX_PENDING_AGENT_EVENTS);
    assert_eq!(events.last(), Some(&event(AgentState::Waiting, "9999")));
    assert_eq!(events[0], event(AgentState::Working, "9984"));
}

#[test]
fn a_flood_of_identical_events_queues_one() {
    let mut core = core();
    for _ in 0..10_000 {
        core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    }
    assert_eq!(
        core.take_agent_events(),
        vec![event(AgentState::Working, "")]
    );
}

#[test]
fn a_process_boundary_lets_the_same_state_fire_again() {
    let mut core = core();
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    core.feed(b"\x1b]7000;v=1;boundary=0\x07");
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(
        core.take_agent_events(),
        vec![
            event(AgentState::Working, ""),
            event(AgentState::Working, "")
        ]
    );
}

#[test]
fn an_event_inside_a_sync_block_lands_when_the_block_flushes() {
    let mut core = core();
    core.feed_at(b"\x1b[?2026h\x1b]777;agent-state;v=1;state=working\x07", 0);
    assert!(core.take_agent_events().is_empty());
    core.feed_at(b"\x1b[?2026l", 1);
    assert_eq!(
        core.take_agent_events(),
        vec![event(AgentState::Working, "")]
    );
}

#[test]
fn a_history_chunk_never_raises_an_agent_event() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\\x1b]7000;v=1;ready=1\x1b\\live\r\n");
    core.feed(b"\x1b]7000;v=1;history=998,2\x1b\\");
    core.feed(b"\x1b]777;agent-state;v=1;state=waiting\x07one\r\ntwo\x1b]777;agent-state;v=1;state=done\x07\r\n");
    assert_eq!(core.first_stable_row(), 998);
    assert!(core.take_agent_events().is_empty());
}

#[test]
fn an_older_answer_split_byte_by_byte_never_raises_an_agent_event() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\\x1b]7000;v=1;ready=1\x1b\\live\r\n");
    let answer = b"\x1b]7000;v=1;history=998,2;cols=80\x1b\\\x1b]777;agent-state;v=1;state=working\x07one\r\ntwo\r\n\x1b]7000;v=1;older=998\x1b\\";
    for byte in answer {
        core.feed(std::slice::from_ref(byte));
    }
    assert_eq!(core.first_stable_row(), 998);
    assert!(core.take_agent_events().is_empty());
    core.feed(b"\x1b]777;agent-state;v=1;state=idle\x07");
    assert_eq!(core.take_agent_events(), vec![event(AgentState::Idle, "")]);
}

#[test]
fn an_older_answer_landing_inside_a_live_event_keeps_the_live_event() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\\x1b]7000;v=1;ready=1\x1b\\live\r\n");
    core.feed(b"\x1b]777;agent-sta");
    core.feed(
        b"\x1b]7000;v=1;history=998,2;cols=80\x1b\\one\r\ntwo\r\n\x1b]7000;v=1;older=998\x1b\\",
    );
    core.feed(b"te;v=1;state=waiting\x07");
    assert_eq!(core.first_stable_row(), 998);
    assert_eq!(
        core.take_agent_events(),
        vec![event(AgentState::Waiting, "")]
    );
}

#[test]
fn an_event_in_the_replay_frame_is_ignored_and_live_events_after_ready_fire() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\");
    core.feed(b"frame\x1b]777;agent-state;v=1;state=working\x07\r\n");
    assert!(core.take_agent_events().is_empty());
    core.feed(b"\x1b]7000;v=1;ready=1\x1b\\");
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(
        core.take_agent_events(),
        vec![event(AgentState::Working, "")]
    );
}

#[test]
fn an_origin_mark_after_rows_exist_does_not_silence_events() {
    let mut core = core();
    core.feed(b"live\r\n\x1b]7000;v=1;origin=9999\x1b\\");
    core.feed(b"\x1b]777;agent-state;v=1;state=working\x07");
    assert_eq!(
        core.take_agent_events(),
        vec![event(AgentState::Working, "")]
    );
}

#[test]
fn live_output_counts_live_bytes_only() {
    let mut fresh = core();
    assert_eq!(fresh.live_output_bytes(), 0);
    fresh.feed(b"abc");
    assert_eq!(fresh.live_output_bytes(), 3);

    let mut reopened = core();
    reopened.feed(b"\x1b]7000;v=1;origin=1000\x1b\\frame\r\n");
    assert_eq!(reopened.live_output_bytes(), 0);
    reopened.feed(b"\x1b]7000;v=1;ready=1\x1b\\");
    assert_eq!(reopened.live_output_bytes(), 0);
    reopened.feed(b"\x1b]7000;v=1;history=998,2\x1b\\one\r\ntwo\r\n");
    assert_eq!(reopened.first_stable_row(), 998);
    assert_eq!(reopened.live_output_bytes(), 0);
    reopened.feed(b"\x1b]7000;v=1;older=998\x1b\\");
    assert_eq!(reopened.live_output_bytes(), 0);
    reopened.feed(b"xy");
    assert_eq!(reopened.live_output_bytes(), 2);
}

#[test]
fn the_claude_code_recordings_carry_no_agent_event() {
    for name in [
        "claude-spinner-10s",
        "claude-long-50k",
        "claude-markdown-reply",
    ] {
        let path = format!(
            "{}/../../bench/agent-session/fixtures/{name}/recording",
            env!("CARGO_MANIFEST_DIR")
        );
        let recording = std::fs::read(path).expect("recording");
        let mut core = TerminalCore::new(120, 200_000).expect("core");
        core.set_agent_tui_mode(true);
        core.feed(&recording);
        assert!(core.take_agent_events().is_empty(), "{name}");
        assert_eq!(core.live_output_bytes(), recording.len() as u64, "{name}");
    }
}
```

- [ ] **Step 3: Run them to see them fail**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test agent_events 2>&1 | grep -E "^error" | head -3
```
Expected: `error[E0432]: unresolved import `vt_core::agent`` (the module does not exist yet).

- [ ] **Step 4: Create the agent module**

Create `packages/terminal/crates/vt-core/src/agent.rs` with exactly this content:

```rust
use std::collections::VecDeque;

pub const AGENT_EXTENSION: &[u8] = b"agent-state";
pub const MAX_AGENT_OSC_BYTES: usize = 1024;
pub const MAX_AGENT_DETAIL_BYTES: usize = 256;
pub const MAX_PENDING_AGENT_EVENTS: usize = 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentState {
    Working,
    Waiting,
    Idle,
    Done,
}

impl AgentState {
    pub fn parse(raw: &[u8]) -> Option<Self> {
        match raw {
            b"working" => Some(Self::Working),
            b"waiting" => Some(Self::Waiting),
            b"idle" => Some(Self::Idle),
            b"done" => Some(Self::Done),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Working => "working",
            Self::Waiting => "waiting",
            Self::Idle => "idle",
            Self::Done => "done",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentEvent {
    pub state: AgentState,
    pub detail: String,
}

#[derive(Debug, Default)]
pub struct AgentChannel {
    pending: VecDeque<AgentEvent>,
    last: Option<AgentEvent>,
    replaying: bool,
}

impl AgentChannel {
    pub fn osc(&mut self, fields: &[&[u8]]) -> bool {
        if self.replaying {
            return false;
        }
        let Some(event) = parse_agent_fields(fields) else {
            return false;
        };
        if self.last.as_ref() == Some(&event) {
            return false;
        }
        self.last = Some(event.clone());
        if self.pending.len() >= MAX_PENDING_AGENT_EVENTS {
            self.pending.pop_front();
        }
        self.pending.push_back(event);
        true
    }

    pub fn take(&mut self) -> Vec<AgentEvent> {
        self.pending.drain(..).collect()
    }

    pub fn replaying(&self) -> bool {
        self.replaying
    }

    pub fn set_replaying(&mut self, on: bool) {
        self.replaying = on;
    }

    pub fn reset_for_new_process(&mut self) {
        self.last = None;
    }
}

pub fn parse_agent_fields(fields: &[&[u8]]) -> Option<AgentEvent> {
    let raw_len = b"777;".len()
        + AGENT_EXTENSION.len()
        + fields.iter().map(|field| field.len() + 1).sum::<usize>();
    if raw_len >= MAX_AGENT_OSC_BYTES {
        return None;
    }
    let mut version: Option<&[u8]> = None;
    let mut state: Option<&[u8]> = None;
    let mut detail: Option<&[u8]> = None;
    for field in fields {
        let field = field.strip_prefix(b" ").unwrap_or(field);
        if field.is_empty() {
            continue;
        }
        let equals = field.iter().position(|byte| *byte == b'=')?;
        let (key, value) = (&field[..equals], &field[equals + 1..]);
        let slot = match key {
            b"v" => &mut version,
            b"state" => &mut state,
            b"detail" => &mut detail,
            _ => continue,
        };
        if slot.is_some() {
            return None;
        }
        *slot = Some(value);
    }
    if version? != b"1" {
        return None;
    }
    let state = AgentState::parse(state?)?;
    let detail = match detail {
        Some(raw) => {
            crate::program::clean_text(&percent_decode_strict(raw)?, MAX_AGENT_DETAIL_BYTES)
        }
        None => String::new(),
    };
    Some(AgentEvent { state, detail })
}

fn percent_decode_strict(raw: &[u8]) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(raw.len());
    let mut index = 0;
    while index < raw.len() {
        if raw[index] == b'%' {
            let high = hex(*raw.get(index + 1)?)?;
            let low = hex(*raw.get(index + 2)?)?;
            out.push(high * 16 + low);
            index += 3;
        } else {
            out.push(raw[index]);
            index += 1;
        }
    }
    Some(out)
}

fn hex(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

impl crate::TerminalCore {
    pub fn take_agent_events(&mut self) -> Vec<AgentEvent> {
        self.parser.program_mut().agent_mut().take()
    }

    pub fn live_output_bytes(&self) -> u64 {
        self.live_output
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_minimal_event_parses() {
        let event = parse_agent_fields(&[b"v=1", b"state=working"]).expect("event");
        assert_eq!(event.state, AgentState::Working);
        assert_eq!(event.detail, "");
    }

    #[test]
    fn fields_parse_in_any_order_with_one_leading_space_and_unknown_keys() {
        let event = parse_agent_fields(&[b"state=done", b" x-future=1", b" v=1"]).expect("event");
        assert_eq!(event.state, AgentState::Done);
    }

    #[test]
    fn a_repeated_key_or_a_field_without_equals_rejects_the_event() {
        assert!(parse_agent_fields(&[b"v=1", b"state=idle", b"state=done"]).is_none());
        assert!(parse_agent_fields(&[b"v=1", b"state=idle", b"bare"]).is_none());
    }

    #[test]
    fn a_bad_percent_escape_rejects_the_event() {
        assert!(parse_agent_fields(&[b"v=1", b"state=idle", b"detail=50%"]).is_none());
        assert!(parse_agent_fields(&[b"v=1", b"state=idle", b"detail=%zz"]).is_none());
    }

    #[test]
    fn a_payload_that_fills_the_osc_buffer_is_treated_as_truncated() {
        let fits = format!("x={}", "a".repeat(MAX_AGENT_OSC_BYTES - 36 - 1));
        assert!(parse_agent_fields(&[b"v=1", b"state=working", fits.as_bytes()]).is_some());
        let full = format!("x={}", "a".repeat(MAX_AGENT_OSC_BYTES - 36));
        assert!(parse_agent_fields(&[b"v=1", b"state=working", full.as_bytes()]).is_none());
    }

    #[test]
    fn identical_consecutive_events_are_queued_once_and_the_queue_is_capped() {
        let mut channel = AgentChannel::default();
        assert!(channel.osc(&[b"v=1", b"state=working"]));
        assert!(!channel.osc(&[b"v=1", b"state=working"]));
        assert!(channel.osc(&[b"v=1", b"state=working", b"detail=a"]));
        assert_eq!(channel.take().len(), 2);
        for index in 0..(MAX_PENDING_AGENT_EVENTS + 4) {
            let detail = format!("detail={index}");
            channel.osc(&[b"v=1", b"state=working", detail.as_bytes()]);
        }
        let taken = channel.take();
        assert_eq!(taken.len(), MAX_PENDING_AGENT_EVENTS);
        assert_eq!(taken[0].detail, "4");
    }
}
```

- [ ] **Step 5: Route `agent-state` in `program.rs`**

In `packages/terminal/crates/vt-core/src/program.rs`:

(a) Line 67-68, replace
```rust
    in_band_resize: bool,
}
```
(the end of `pub struct ProgramState`) with
```rust
    in_band_resize: bool,
    agent: crate::agent::AgentChannel,
}
```

(b) Lines 91-93, replace
```rust
    pub fn take_notifications(&mut self) -> Vec<ProgramNotification> {
        self.notifications.drain(..).collect()
    }
```
with
```rust
    pub fn take_notifications(&mut self) -> Vec<ProgramNotification> {
        self.notifications.drain(..).collect()
    }

    pub fn agent(&self) -> &crate::agent::AgentChannel {
        &self.agent
    }

    pub fn agent_mut(&mut self) -> &mut crate::agent::AgentChannel {
        &mut self.agent
    }
```
(The other `take_notifications` at line 398 is inside `impl crate::TerminalCore` and returns `self.parser.program_mut().take_notifications()`; do not touch it.)

(c) Line 152 (inside `reset_for_new_process`), replace
```rust
        self.in_band_resize = false;
        if changed {
```
with
```rust
        self.in_band_resize = false;
        self.agent.reset_for_new_process();
        if changed {
```

(d) Lines 238-241, replace
```rust
    fn osc777(&mut self, payload: &[&[u8]]) {
        let [extension, title, body @ ..] = payload else {
```
with
```rust
    fn osc777(&mut self, payload: &[&[u8]]) {
        if payload.first() == Some(&crate::agent::AGENT_EXTENSION) {
            if self.agent.osc(&payload[1..]) {
                self.bump();
            }
            return;
        }
        let [extension, title, body @ ..] = payload else {
```

(e) Line 360, replace `fn clean_text(raw: &[u8], cap: usize) -> String {` with `pub(crate) fn clean_text(raw: &[u8], cap: usize) -> String {`.

- [ ] **Step 6: Wire `lib.rs` and move the mode getters**

In `packages/terminal/crates/vt-core/src/lib.rs`:

(a) Line 1: replace `pub mod alt;` with
```rust
pub mod agent;
pub mod alt;
```

(b) Line 10: replace `pub mod content;` with
```rust
pub mod content;
mod core_modes;
```

(c) Lines 87-89 (end of `pub struct TerminalCore`), replace
```rust
    replay_ready: bool,
    older: OlderState,
}
```
with
```rust
    replay_ready: bool,
    older: OlderState,
    live_output: u64,
}
```

(d) Lines 117-118 (end of `with_limits`' struct literal), replace
```rust
            older: OlderState::default(),
        })
```
with
```rust
            older: OlderState::default(),
            live_output: 0,
        })
```

(e) Lines 250-259 (in `feed_raw`), replace
```rust
                MarkEvent::ReplayOrigin(origin) => {
                    self.parser.adopt_origin(origin);
                    parsed = upto;
                    continue;
                }
                MarkEvent::ReplayReady => {
                    self.replay_ready = true;
                    parsed = upto;
                    continue;
                }
```
with
```rust
                MarkEvent::ReplayOrigin(origin) => {
                    let adopted = self.parser.adopt_origin(origin);
                    if adopted {
                        self.live_output = 0;
                    }
                    self.parser.program_mut().agent_mut().set_replaying(adopted);
                    parsed = upto;
                    continue;
                }
                MarkEvent::ReplayReady => {
                    self.replay_ready = true;
                    self.parser.program_mut().agent_mut().set_replaying(false);
                    parsed = upto;
                    continue;
                }
```

(f) Line 321 (first line of `advance_vte`), replace
```rust
        let bytes: &[u8] = &self.answer_gate.filter(bytes);
```
with
```rust
        let bytes: &[u8] = &self.answer_gate.filter(bytes);
        if !self.parser.program().agent().replaying() {
            self.live_output = self.live_output.wrapping_add(bytes.len() as u64);
        }
```

(g) Lines 564-591, replace
```rust
    pub fn alt_grid(&self) -> Option<&alt::AltGrid> {
        self.parser.alt()
    }

    pub fn application_cursor_keys(&self) -> bool {
        self.parser.app_cursor()
    }

    pub fn sgr_mouse(&self) -> bool {
        self.parser.sgr_mouse()
    }

    pub fn bracketed_paste(&self) -> bool {
        self.parser.bracketed_paste()
    }

    pub fn focus_reporting(&self) -> bool {
        self.parser.focus_reporting()
    }

    pub fn mouse_tracking(&self) -> bool {
        self.parser.mouse_tracking()
    }

    pub fn mouse_tracking_level(&self) -> u8 {
        self.parser.mouse_tracking_level()
    }
}
```
with
```rust
    pub fn alt_grid(&self) -> Option<&alt::AltGrid> {
        self.parser.alt()
    }
}
```

Create `packages/terminal/crates/vt-core/src/core_modes.rs` with exactly this content:

```rust
impl crate::TerminalCore {
    pub fn application_cursor_keys(&self) -> bool {
        self.parser.app_cursor()
    }

    pub fn sgr_mouse(&self) -> bool {
        self.parser.sgr_mouse()
    }

    pub fn bracketed_paste(&self) -> bool {
        self.parser.bracketed_paste()
    }

    pub fn focus_reporting(&self) -> bool {
        self.parser.focus_reporting()
    }

    pub fn mouse_tracking(&self) -> bool {
        self.parser.mouse_tracking()
    }

    pub fn mouse_tracking_level(&self) -> u8 {
        self.parser.mouse_tracking_level()
    }
}
```

- [ ] **Step 7: Run the tests to see them pass, then the whole workspace**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test agent_events 2>&1 | grep "test result"
cargo test -p vt-core --lib agent 2>&1 | grep "test result"
cargo fmt && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
wc -l crates/vt-core/src/lib.rs crates/vt-core/src/program.rs crates/vt-core/src/agent.rs crates/vt-core/src/core_modes.rs
```
Expected: `test result: ok. 17 passed; 0 failed`, `test result: ok. 6 passed; 0 failed` (plus "97 filtered out" or similar), `Finished …` from clippy, only `rust-done`, and `585`, `429`, `215`, `25` lines. `tests/program_messages.rs::the_claude_code_recording_ends_on_its_idle_title` still expects 1,047 generation bumps — it must pass unchanged (the recordings contain no agent event).

- [ ] **Step 8: Document the wire format**

Append to `packages/terminal/protocol/SPEC.md` (after the last line of §9, which ends "…is the regression for this."):

```markdown
## 10. Agent state — OSC 777 `agent-state`

Status: normative for `vt-core` from roadmap Plan 8 (2026-09-25). This is not a
block-lifecycle mark: `crates/marks` and `go/marks` never see it and the
vectors under `vectors/` do not cover it. `vt-core` parses it
(`crates/vt-core/src/agent.rs`) and `@operator/terminal-core` surfaces it as
`TerminalCore.onAgentEvent`. Its vectors are `agent-vectors/agent-state.json`,
generated by `agent-vectors/make-agent-vectors.py`.

A program (an agent, or a hook the agent runs) writes this sequence to its
terminal to say what it is doing. Because the bytes travel with the rest of
the output, the report reaches the terminal wherever the program runs —
over SSH, inside a container — with no side channel.

### 10.1 Encoding

```
OSC 777 ; agent-state ; v=1 ; state=<state> [; detail=<value>] (ST | BEL)
```

- `777` is the rxvt-unicode extension OSC. `agent-state` is the extension
  name: exact bytes, case-sensitive. The same OSC with the `notify` extension
  remains a desktop notification; no other extension name is read.
- After the extension name come `key=value` fields separated by `;`, in any
  order. A single ASCII space immediately after a separator is ignored. An
  empty field (for example after a trailing `;`) is ignored. Unknown keys are
  ignored.
- `v` is REQUIRED and MUST be exactly `1`. Any other value: the sequence is
  ignored in its entirety.
- `state` is REQUIRED and MUST be one of the values in §10.2, lower case.
  Any other value: ignored.
- `detail` is OPTIONAL: percent-encoded UTF-8 (RFC 3986 §2.1). A `%` not
  followed by two hex digits: the sequence is ignored. After decoding,
  invalid UTF-8 becomes U+FFFD, control characters are removed and the text
  is cut to 256 bytes on a character boundary.
- A field without `=`, or a key given twice: the sequence is ignored.
- Size: the payload (from `777` to the byte before the terminator) MUST be
  shorter than 1,024 bytes. `vt-core`'s parser keeps at most 1,024 payload
  bytes and drops the rest, so a payload of 1,024 bytes or more is treated as
  truncated and ignored. It also keeps at most 16 parameters: a field after
  the 14th is never seen. Senders MUST stay within both.
- `ST` and `BEL` are both accepted (§3.2).

### 10.2 States

The state is the sender's claim; the terminal does not check it.

| `state` | Meaning |
| --- | --- |
| `working` | the agent is doing something on its own |
| `waiting` | the agent needs the user (a permission prompt, a question) |
| `idle` | the agent is at its prompt, ready for the next instruction |
| `done` | the agent finished the task it was given |

### 10.3 Delivery

- Two consecutive sequences with the same `state` and `detail` deliver one
  event. The same state with a different `detail` is a new event. A
  process-boundary mark (`OSC 7000;v=1;boundary=…`) forgets the last event,
  so a new process's first report is always delivered.
- At most 16 events wait to be taken; when a 17th arrives the oldest is
  dropped.
- Output that is loaded or replayed never delivers an event: rows of a
  history chunk (`history=`, including "load older output" answers) and the
  attach replay frame, from an adopted `origin=` mark to the `ready=` mark.
- Inside a DEC 2026 synchronized-output block the event is delivered when
  the block is parsed.
- The sequence prints nothing.

### 10.4 Example

```sh
printf '\033]777;agent-state;v=1;state=waiting;detail=Allow%%20Bash%%3F\033\\'
```

delivers `{ state: "waiting", detail: "Allow Bash?" }`.
```

In `packages/terminal/protocol/README.md`, in the "Contents" table, after the row that starts `` | `vectors/*.json` `` add:

```markdown
| `agent-vectors/agent-state.json` | Vectors for `SPEC.md` §10 (`OSC 777 ; agent-state`), read by `vt-core`'s `tests/agent_events.rs` and `ts/core`'s `agent-events.test.ts`, not by the mark decoders. Generated by `make-agent-vectors.py` beside it. |
```

- [ ] **Step 9: Commit**

```bash
cd "$REPO" && git add packages/terminal/protocol/agent-vectors/make-agent-vectors.py \
  packages/terminal/protocol/agent-vectors/agent-state.json \
  packages/terminal/protocol/SPEC.md packages/terminal/protocol/README.md \
  packages/terminal/crates/vt-core/src/agent.rs packages/terminal/crates/vt-core/src/core_modes.rs \
  packages/terminal/crates/vt-core/src/program.rs packages/terminal/crates/vt-core/src/lib.rs \
  packages/terminal/crates/vt-core/tests/agent_events.rs
git commit -m "feat(vt-core): parse OSC 777 agent-state events and count live output" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: vt-wasm exports, both wasm builds, mirror guard

**Files:**
- Modify: `packages/terminal/crates/vt-wasm/src/program.rs` (whole file), `packages/terminal/crates/vt-wasm/src/lib.rs:10`, `packages/terminal/crates/vt-wasm/tests/program_exports.rs` (whole file), `backend/internal/adapters/runtime/ptyhost/vtwasm/program_test.go` (imports + one test), `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` (rebuilt)

**Interfaces:**
- Consumes: `TerminalCore::take_agent_events`, `live_output_bytes`, `AgentEvent`, `AgentState::as_str` (Task 1).
- Produces (wasm-bindgen, TS names identical): `WasmTerminalCore.take_agent_events(): string[]` (flat `[state, detail, state, detail, …]`), `WasmTerminalCore.live_output_bytes(): number`; Rust `vt_wasm::flatten_agent_events(Vec<AgentEvent>) -> Vec<String>`.

- [ ] **Step 1: Write the failing tests**

Replace the whole of `packages/terminal/crates/vt-wasm/tests/program_exports.rs` with:

```rust
use vt_core::agent::{AgentEvent, AgentState};
use vt_core::program::ProgramNotification;
use vt_wasm::WasmTerminalCore;
use vt_wasm::{flatten_agent_events, flatten_notifications};

#[test]
fn notifications_flatten_to_title_body_pairs_in_order() {
    let flat = flatten_notifications(vec![
        ProgramNotification {
            title: "Build".to_string(),
            body: "done".to_string(),
        },
        ProgramNotification {
            title: String::new(),
            body: "second".to_string(),
        },
    ]);
    assert_eq!(flat, vec!["Build", "done", "", "second"]);
}

#[test]
fn the_wasm_core_exposes_title_pointer_and_notifications() {
    let Ok(mut core) = WasmTerminalCore::new(80, 1_000, 1 << 20) else {
        panic!("core");
    };
    let start = core.program_generation();
    assert!(core
        .feed(
            b"\x1b]0;\xe2\x97\x90 Working\x07\x1b]22;pointer\x07\x1b]9;hi\x07",
            0.0
        )
        .is_ok());
    assert_eq!(core.title(), "\u{25d0} Working");
    assert_eq!(core.pointer_shape(), "pointer");
    assert_eq!(core.take_notifications(), vec!["", "hi"]);
    assert!(core.take_notifications().is_empty());
    assert_eq!(core.program_generation().wrapping_sub(start), 3);
}

#[test]
fn agent_events_flatten_to_state_detail_pairs_in_order() {
    let flat = flatten_agent_events(vec![
        AgentEvent {
            state: AgentState::Waiting,
            detail: "Allow Bash?".to_string(),
        },
        AgentEvent {
            state: AgentState::Done,
            detail: String::new(),
        },
    ]);
    assert_eq!(flat, vec!["waiting", "Allow Bash?", "done", ""]);
}

#[test]
fn the_wasm_core_exposes_agent_events_and_live_output() {
    let Ok(mut core) = WasmTerminalCore::new(80, 1_000, 1 << 20) else {
        panic!("core");
    };
    let start = core.program_generation();
    let bytes = b"ab\x1b]777;agent-state;v=1;state=working;detail=Read\x07";
    assert!(core.feed(bytes, 0.0).is_ok());
    assert_eq!(core.take_agent_events(), vec!["working", "Read"]);
    assert!(core.take_agent_events().is_empty());
    assert_eq!(core.program_generation().wrapping_sub(start), 1);
    assert_eq!(core.live_output_bytes(), bytes.len() as f64);
}
```

- [ ] **Step 2: Run to see them fail**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-wasm --test program_exports 2>&1 | grep -E "^error" | head -3
```
Expected: `error[E0432]: unresolved import` naming `flatten_agent_events`.

- [ ] **Step 3: Implement the exports**

Replace the whole of `packages/terminal/crates/vt-wasm/src/program.rs` with:

```rust
use vt_core::agent::AgentEvent;
use vt_core::program::ProgramNotification;
use wasm_bindgen::prelude::*;

use crate::WasmTerminalCore;

pub fn flatten_notifications(notifications: Vec<ProgramNotification>) -> Vec<String> {
    notifications
        .into_iter()
        .flat_map(|notification| [notification.title, notification.body])
        .collect()
}

pub fn flatten_agent_events(events: Vec<AgentEvent>) -> Vec<String> {
    events
        .into_iter()
        .flat_map(|event| [event.state.as_str().to_string(), event.detail])
        .collect()
}

#[wasm_bindgen]
impl WasmTerminalCore {
    pub fn program_generation(&self) -> u32 {
        self.core.program_generation() as u32
    }

    pub fn title(&self) -> String {
        self.core.title().to_string()
    }

    pub fn pointer_shape(&self) -> String {
        self.core.pointer_shape().to_string()
    }

    pub fn take_notifications(&mut self) -> Vec<String> {
        flatten_notifications(self.core.take_notifications())
    }

    pub fn take_agent_events(&mut self) -> Vec<String> {
        flatten_agent_events(self.core.take_agent_events())
    }

    pub fn live_output_bytes(&self) -> f64 {
        self.core.live_output_bytes() as f64
    }
}
```

In `packages/terminal/crates/vt-wasm/src/lib.rs` line 10, replace `pub use program::flatten_notifications;` with `pub use program::{flatten_agent_events, flatten_notifications};`.

- [ ] **Step 4: Run to see them pass**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo test -p vt-wasm --test program_exports 2>&1 | grep "test result"
```
Expected: `test result: ok. 4 passed; 0 failed`.

- [ ] **Step 5: Rebuild both wasm artifacts**

```bash
cd "$REPO/packages/terminal" && npm run build:wasm -- --force 2>&1 | tail -1
grep -c "take_agent_events\|live_output_bytes" ts/core/wasm/vt_core.d.ts
cargo build --release -p vt-host --target wasm32-unknown-unknown 2>&1 | tail -1
cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
git -C "$REPO" status --short backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
```
Expected: `build-wasm: vt_core.js, vt_core.d.ts, vt_core_bg.wasm, vt_core_bg.wasm.d.ts ready`; a count ≥ 2; `Finished …`; ` M backend/…/vt_host.wasm` (planning build: 360,836 → 364,410 bytes on macOS; your size may differ by toolchain host).

- [ ] **Step 6: Mirror guard test (Go)**

In `backend/internal/adapters/runtime/ptyhost/vtwasm/program_test.go`, replace the import block
```go
import (
	"bytes"
	"path/filepath"
	"reflect"
	"testing"
)
```
with
```go
import (
	"bytes"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)
```
and append at the end of the file:

```go
func TestAnAgentEventIsNeitherATitleNorANotificationInTheMirror(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "\x1b]2;kept\x07\x1b]777;agent-state;v=1;state=waiting;detail=Allow%20Bash%3F\x07after")
	title, err := p.Title()
	if err != nil || title != "kept" {
		t.Fatalf("title = %q, %v; want kept", title, err)
	}
	notes, err := p.TakeNotifications()
	if err != nil || len(notes) != 0 {
		t.Fatalf("notifications = %#v, %v; want none", notes, err)
	}
	text, err := p.RenderTail(5)
	if err != nil || !strings.Contains(text, "after") || strings.Contains(text, "agent-state") {
		t.Fatalf("output = %q, %v; want only the text around the event", text, err)
	}
}
```

This test passes on the old mirror too (the old core ignored every OSC 777 extension other than `notify`); it is a guard that the new core keeps agent events out of the mirror's title and notification stream, which `publishProgramLocked` (`ptyhost/program.go:44-72`) forwards to Operator.

```bash
cd "$REPO/backend" && gofmt -l internal/adapters/runtime/ptyhost/vtwasm
go test ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -3
```
Expected: no gofmt output; three `ok` lines (`ptyhost`, `ptyhost/ptyregistry`, `ptyhost/vtwasm`).

- [ ] **Step 7: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-wasm/src/program.rs packages/terminal/crates/vt-wasm/src/lib.rs \
  packages/terminal/crates/vt-wasm/tests/program_exports.rs \
  backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm \
  backend/internal/adapters/runtime/ptyhost/vtwasm/program_test.go
git commit -m "feat(vt-wasm): export agent events and the live output counter; rebuild the mirror wasm" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `TerminalCore.onAgentEvent` in ts/core

**Files:**
- Create: `packages/terminal/ts/core/src/core-checks.ts`, `packages/terminal/ts/core/src/agent-events.ts`, `packages/terminal/ts/core/src/agent-events.test.ts`
- Modify: `packages/terminal/ts/core/src/terminal-core.ts:14,80-84,123-124,185-187,426-439,496-498,557-558,569-597`, `packages/terminal/ts/core/src/index-browser.ts:83`

**Interfaces:**
- Consumes: `WasmTerminalCore.take_agent_events()`, `program_generation()` (Task 2).
- Produces: `type AgentState = "working" | "waiting" | "idle" | "done"`; `type AgentEvent = Readonly<{ state: AgentState; detail: string }>`; `type AgentEventListener = (event: AgentEvent) => void`; `class AgentEvents { constructor(source: AgentEventSource); onEvent(listener): () => void; poll(): void; dispose(): void }`; `TerminalCore.onAgentEvent(listener: AgentEventListener): () => void`. `core-checks.ts` exports `budgetNow`, `validateEvenLength`, `validateMultipleOf`, `parseBlockId`, `decodeFindMatches(view: Uint32Array, words: number): FindMatch[]`.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/core/src/agent-events.test.ts` with exactly this content:

```ts
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { AgentEvents, createTerminalCore, initTerminalCore, type AgentEvent } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

const encoder = new TextEncoder();

type VectorCase = { name: string; input: string; events: AgentEvent[] };

async function vectorCases(): Promise<VectorCase[]> {
	const raw = await readFile(fileURLToPath(new URL("../../../protocol/agent-vectors/agent-state.json", import.meta.url)), "utf8");
	return (JSON.parse(raw) as { cases: VectorCase[] }).cases;
}

function core() {
	return createTerminalCore({ columns: 80, rows: 24, limits: { rows: 1000, bytes: 1 << 20 } });
}

function collect(target: ReturnType<typeof core>): AgentEvent[] {
	const events: AgentEvent[] = [];
	target.onAgentEvent((event) => events.push(event));
	return events;
}

describe("AgentEvents", () => {
	it("reads nothing while the program generation is unchanged", () => {
		const source = { program_generation: vi.fn(() => 0), take_agent_events: vi.fn(() => [] as string[]) };
		new AgentEvents(source).poll();
		expect(source.take_agent_events).not.toHaveBeenCalled();
	});

	it("emits each state and detail pair once and skips a state it does not know", () => {
		let generation = 0;
		let pending: string[] = [];
		const source = {
			program_generation: () => generation,
			take_agent_events: () => {
				const taken = pending;
				pending = [];
				return taken;
			},
		};
		const events = new AgentEvents(source);
		const seen: AgentEvent[] = [];
		events.onEvent((event) => seen.push(event));
		generation = 1;
		pending = ["working", "Read", "paused", "", "done", ""];
		events.poll();
		events.poll();
		expect(seen).toEqual([
			{ state: "working", detail: "Read" },
			{ state: "done", detail: "" },
		]);
	});

	it("stops delivering to a listener after its teardown and after dispose", () => {
		let generation = 0;
		const source = { program_generation: () => generation, take_agent_events: () => ["idle", ""] };
		const events = new AgentEvents(source);
		const first = vi.fn();
		const second = vi.fn();
		const stop = events.onEvent(first);
		events.onEvent(second);
		stop();
		generation = 1;
		events.poll();
		expect(first).not.toHaveBeenCalled();
		expect(second).toHaveBeenCalledTimes(1);
		events.dispose();
		generation = 2;
		events.poll();
		expect(second).toHaveBeenCalledTimes(1);
	});
});

describe("TerminalCore.onAgentEvent", () => {
	it("yields every vector case's events, whole and split byte by byte", async () => {
		const cases = await vectorCases();
		expect(cases.length).toBeGreaterThanOrEqual(20);
		for (const vector of cases) {
			const whole = core();
			const wholeEvents = collect(whole);
			whole.feed(encoder.encode(vector.input));
			expect(wholeEvents, vector.name).toEqual(vector.events);
			whole.dispose();
			const split = core();
			const splitEvents = collect(split);
			for (const byte of encoder.encode(vector.input)) split.feed(Uint8Array.of(byte));
			expect(splitEvents, vector.name).toEqual(vector.events);
			split.dispose();
		}
	});

	it("delivers events parsed from the backlog by drain", () => {
		const target = core();
		const events = collect(target);
		target.enqueue(encoder.encode("\x1b]777;agent-state;v=1;state=waiting;detail=Allow%20Bash%3F\x07"));
		expect(events).toEqual([]);
		target.drain();
		expect(events).toEqual([{ state: "waiting", detail: "Allow Bash?" }]);
		target.dispose();
	});

	it("delivers an event held in a sync block when tick passes its deadline", () => {
		const target = core();
		const events = collect(target);
		target.feed(encoder.encode("\x1b[?2026h\x1b]777;agent-state;v=1;state=working\x07"));
		expect(events).toEqual([]);
		target.tick(Date.now() + 1_000);
		expect(events).toEqual([{ state: "working", detail: "" }]);
		target.dispose();
	});

	it("does not replay an event to a listener that subscribes after it", () => {
		const target = core();
		target.feed(encoder.encode("\x1b]777;agent-state;v=1;state=done\x07"));
		const late = collect(target);
		target.feed(encoder.encode("plain output"));
		expect(late).toEqual([]);
		target.dispose();
	});

	it("stops delivering after the listener's teardown and after dispose", () => {
		const target = core();
		const listener = vi.fn();
		const stop = target.onAgentEvent(listener);
		target.feed(encoder.encode("\x1b]777;agent-state;v=1;state=working\x07"));
		stop();
		target.feed(encoder.encode("\x1b]777;agent-state;v=1;state=done\x07"));
		expect(listener).toHaveBeenCalledTimes(1);
		const kept = vi.fn();
		target.onAgentEvent(kept);
		target.dispose();
		target.feed(encoder.encode("\x1b]777;agent-state;v=1;state=idle\x07"));
		expect(kept).not.toHaveBeenCalled();
	});

	it("never fires for the replay frame, a history chunk or an older answer", () => {
		const target = core();
		const events = collect(target);
		target.feed(encoder.encode("\x1b]7000;v=1;origin=1000\x1b\\frame\x1b]777;agent-state;v=1;state=working\x07\r\n"));
		target.feed(encoder.encode("\x1b]7000;v=1;ready=1\x1b\\"));
		target.feed(encoder.encode("\x1b]7000;v=1;history=998,2\x1b\\\x1b]777;agent-state;v=1;state=waiting\x07one\r\ntwo\r\n"));
		const answer = encoder.encode(
			"\x1b]7000;v=1;history=996,2;cols=80\x1b\\\x1b]777;agent-state;v=1;state=done\x07three\r\nfour\r\n\x1b]7000;v=1;older=996\x1b\\",
		);
		for (const byte of answer) target.feed(Uint8Array.of(byte));
		expect(target.snapshot().firstStableRow).toBe(996);
		expect(events).toEqual([]);
		target.feed(encoder.encode("\x1b]777;agent-state;v=1;state=idle\x07"));
		expect(events).toEqual([{ state: "idle", detail: "" }]);
		target.dispose();
	});

	it("keeps only the newest sixteen events of a flood fed in one call", () => {
		const target = core();
		const events = collect(target);
		let flood = "";
		for (let index = 0; index < 1_000; index += 1) flood += `\x1b]777;agent-state;v=1;state=working;detail=${index}\x07`;
		target.feed(encoder.encode(flood));
		expect(events).toHaveLength(16);
		expect(events[0]).toEqual({ state: "working", detail: "984" });
		expect(events.at(-1)).toEqual({ state: "working", detail: "999" });
		target.dispose();
	});
});
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd "$REPO/packages/terminal/ts/core" && npx vitest run src/agent-events.test.ts 2>&1 | tail -4
```
Expected: FAIL — `AgentEvents` is not exported / `target.onAgentEvent is not a function`.

- [ ] **Step 3: Create `agent-events.ts` and `core-checks.ts`**

Create `packages/terminal/ts/core/src/agent-events.ts`:

```ts
export type AgentState = "working" | "waiting" | "idle" | "done";

export type AgentEvent = Readonly<{ state: AgentState; detail: string }>;

export type AgentEventListener = (event: AgentEvent) => void;

export type AgentEventSource = {
	program_generation(): number;
	take_agent_events(): string[];
};

const STATES: ReadonlySet<string> = new Set<AgentState>(["working", "waiting", "idle", "done"]);

export class AgentEvents {
	private readonly source: AgentEventSource;
	private readonly listeners = new Set<AgentEventListener>();
	private generation = 0;

	constructor(source: AgentEventSource) {
		this.source = source;
	}

	onEvent(listener: AgentEventListener): () => void {
		this.listeners.add(listener);
		return () => {
			this.listeners.delete(listener);
		};
	}

	poll(): void {
		const generation = this.source.program_generation();
		if (generation === this.generation) return;
		this.generation = generation;
		const flat = this.source.take_agent_events();
		for (let index = 0; index + 1 < flat.length; index += 2) {
			const state = flat[index]!;
			if (!STATES.has(state)) continue;
			const event: AgentEvent = { state: state as AgentState, detail: flat[index + 1]! };
			for (const listener of [...this.listeners]) listener(event);
		}
	}

	dispose(): void {
		this.listeners.clear();
	}
}
```

Create `packages/terminal/ts/core/src/core-checks.ts` (the four helpers move here verbatim from the bottom of `terminal-core.ts`, plus the find-result decode loop):

```ts
import type { BlockId, FindMatch } from "./types.js";

export function budgetNow(): number {
	return typeof performance !== "undefined" ? performance.now() : Date.now();
}

export function validateEvenLength(name: string, length: number): void {
	if (length % 2 !== 0) {
		throw new Error(`${name} length ${length} is not even`);
	}
}

export function validateMultipleOf(name: string, length: number, words: number): void {
	if (length % words !== 0) {
		throw new Error(`${name} length ${length} is not a multiple of ${words}`);
	}
}

export function parseBlockId(id: BlockId): [number, number] {
	const separator = id.indexOf(":");
	if (separator < 0) {
		throw new Error(`block id ${id} is not in hi:lo form`);
	}
	const hi = Number.parseInt(id.slice(0, separator), 10);
	const lo = Number.parseInt(id.slice(separator + 1), 10);
	if (!Number.isFinite(hi) || !Number.isFinite(lo)) {
		throw new Error(`block id ${id} is not numeric`);
	}
	return [lo, hi];
}

export function decodeFindMatches(view: Uint32Array, words: number): FindMatch[] {
	const matches: FindMatch[] = [];
	for (let base = 0; base + words <= view.length; base += words) {
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
```

- [ ] **Step 4: Wire `terminal-core.ts`**

In `packages/terminal/ts/core/src/terminal-core.ts` make these replacements (each quoted text occurs exactly once):

(1) Replace
```ts
import { ProgramMessages, type ProgramMessageListener } from "./program-messages.js";
```
with
```ts
import { ProgramMessages, type ProgramMessageListener } from "./program-messages.js";
import { AgentEvents, type AgentEventListener } from "./agent-events.js";
import { budgetNow, decodeFindMatches, parseBlockId, validateEvenLength, validateMultipleOf } from "./core-checks.js";
```

(2) Replace
```ts
	private readonly program: ProgramMessages;

	constructor(inner: WasmTerminalCore, host: HostCapabilities) {
		this.inner = inner;
		this.program = new ProgramMessages(inner, host);
```
with
```ts
	private readonly program: ProgramMessages;
	private readonly agentEvents: AgentEvents;

	constructor(inner: WasmTerminalCore, host: HostCapabilities) {
		this.inner = inner;
		this.program = new ProgramMessages(inner, host);
		this.agentEvents = new AgentEvents(inner);
```

(3) Replace
```ts
		this.inner.feed(bytes, Date.now());
		this.program.poll();
```
with
```ts
		this.inner.feed(bytes, Date.now());
		this.program.poll();
		this.agentEvents.poll();
```

(4) Replace
```ts
		this.program.poll();
		this.notifyIfChanged();
		return true;
```
with
```ts
		this.program.poll();
		this.agentEvents.poll();
		this.notifyIfChanged();
		return true;
```

(5) Replace
```ts
	onProgramMessage(listener: ProgramMessageListener): () => void {
		return this.program.onMessage(listener);
	}
```
with
```ts
	onProgramMessage(listener: ProgramMessageListener): () => void {
		return this.program.onMessage(listener);
	}

	onAgentEvent(listener: AgentEventListener): () => void {
		return this.agentEvents.onEvent(listener);
	}
```

(6) Replace
```ts
		this.program.dispose();
		this.listeners.clear();
```
with
```ts
		this.program.dispose();
		this.agentEvents.dispose();
		this.listeners.clear();
```

(7) Replace
```ts
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
```
with
```ts
		return decodeFindMatches(u32View(memory, ptr, len), FIND_MATCH_WORDS);
	}
```

Then delete the four helper functions at the bottom of the file — everything from the line `function budgetNow(): number {` (line 569) down to, but not including, the last line `export type { WasmInput };`. The file must end:

```ts
		this.inner.free();
	}
}

export type { WasmInput };
```

- [ ] **Step 5: Export from the package**

In `packages/terminal/ts/core/src/index-browser.ts`, replace
```ts
export {
	FEED_BUDGET_MS,
```
with
```ts
export {
	AgentEvents,
	type AgentEvent,
	type AgentEventListener,
	type AgentEventSource,
	type AgentState,
} from "./agent-events.js";
export {
	FEED_BUDGET_MS,
```

- [ ] **Step 6: Run to see it pass, and the whole core suite**

```bash
cd "$REPO/packages/terminal/ts/core" && npx vitest run src/agent-events.test.ts 2>&1 | grep -E "Tests  "
npx vitest run 2>&1 | grep -E "Tests  "
npx tsc -p . --noEmit && echo tsc-ok
wc -l src/terminal-core.ts
```
Expected: `Tests  10 passed (10)`; `Tests  111 passed (111)`; `tsc-ok`; `567 src/terminal-core.ts`.

- [ ] **Step 7: Commit**

```bash
cd "$REPO" && git add packages/terminal/ts/core/src/agent-events.ts packages/terminal/ts/core/src/agent-events.test.ts \
  packages/terminal/ts/core/src/core-checks.ts packages/terminal/ts/core/src/terminal-core.ts \
  packages/terminal/ts/core/src/index-browser.ts
git commit -m "feat(terminal-core): onAgentEvent delivers OSC 777 agent-state events" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: The idle/prompt detector — `agentActivity()` / `onAgentActivity`

**Files:**
- Create: `packages/terminal/ts/core/src/input-patterns.ts`, `packages/terminal/ts/core/src/LICENSE-VSCODE-MIT` (copy), `packages/terminal/ts/core/src/VSCODE-INPUT-PATTERNS-ATTRIBUTION.md`, `packages/terminal/ts/core/src/agent-activity.ts`, `packages/terminal/ts/core/src/agent-activity.test.ts`
- Modify: `packages/terminal/ts/core/src/terminal-core.ts` (after Task 3), `packages/terminal/ts/core/src/index-browser.ts`

**Interfaces:**
- Consumes: `WasmTerminalCore.live_output_bytes()` (Task 2); `TerminalCore` fields `agentEvents`, `onAgentEvent` (Task 3).
- Produces: `type AgentActivityState = "active" | "pollingForIdle" | "idle" | "prompting"`; `type AgentActivityListener = (state: AgentActivityState) => void`; `ACTIVITY_POLLING_AFTER_MS = 500`, `ACTIVITY_IDLE_AFTER_MS = 1500`; `type AgentActivitySource = Readonly<{ liveOutputBytes(): number; cursorLine(): string; now(): number }>`; `class AgentActivityMonitor { constructor(source); state(); onChange(listener): () => void; observe(); dispose() }`; `cursorLineText(snapshot: TerminalSnapshot, decoder: TextDecoder): string`; `detectsHighConfidenceInputPattern(cursorLine: string): boolean`; `TerminalCore.agentActivity(): AgentActivityState`, `TerminalCore.onAgentActivity(listener): () => void`.

- [ ] **Step 1: Write the failing test**

Create `packages/terminal/ts/core/src/agent-activity.test.ts` with exactly this content:

```ts
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
	ACTIVITY_IDLE_AFTER_MS,
	ACTIVITY_POLLING_AFTER_MS,
	AgentActivityMonitor,
	createTerminalCore,
	cursorLineText,
	detectsHighConfidenceInputPattern,
	initTerminalCore,
	type AgentActivityState,
	type TerminalCore,
} from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

beforeEach(() => {
	vi.useFakeTimers({ now: 1_000_000 });
});

afterEach(() => {
	vi.useRealTimers();
});

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const FRAME_MS = 100;
const ESU = encoder.encode("\x1b[?2026l");
const TITLE = encoder.encode("\x1b]0;");

type Size = { offset: number; cols: number; rows: number };

async function fixture(name: string): Promise<{ recording: Uint8Array; sizes: Size[] }> {
	const dir = new URL(`../../../bench/agent-session/fixtures/${name}/`, import.meta.url);
	const recording = new Uint8Array(await readFile(fileURLToPath(new URL("recording", dir))));
	const sizes = JSON.parse(await readFile(fileURLToPath(new URL("size.json", dir)), "utf8")) as Size[];
	return { recording, sizes };
}

function endsAfter(recording: Uint8Array, needle: Uint8Array, before: boolean): number[] {
	const ends: number[] = [];
	outer: for (let index = 0; index + needle.length <= recording.length; index += 1) {
		for (let k = 0; k < needle.length; k += 1) if (recording[index + k] !== needle[k]) continue outer;
		const end = before ? index : index + needle.length;
		if (end > 0) ends.push(end);
	}
	return ends;
}

function frameEnds(recording: Uint8Array): number[] {
	const synced = endsAfter(recording, ESU, false);
	const ends = synced.length > 0 ? synced : endsAfter(recording, TITLE, true);
	if (ends.at(-1) !== recording.length) ends.push(recording.length);
	return ends;
}

function fakeSource(line = "") {
	let bytes = 0;
	const source = {
		cursorLine: vi.fn(() => line),
		liveOutputBytes: () => bytes,
		now: () => Date.now(),
		setLine: (next: string) => {
			line = next;
		},
		write: (count: number) => {
			bytes += count;
		},
	};
	return source;
}

describe("detectsHighConfidenceInputPattern", () => {
	it.each([
		"Overwrite existing file? (y/n) ",
		"Continue? [Y/n] ",
		"Proceed (yes/no) ",
		"Ok to proceed? (y) ",
		"package name: (demo) ",
		"(END)",
		"[sudo] password for dev:",
		"Press any key to continue",
		"? Pick a color \u276f ",
	])("matches %j", (line) => {
		expect(detectsHighConfidenceInputPattern(line)).toBe(true);
	});

	it.each([
		"\u276f\u00a0",
		"\u276f ",
		"$ ",
		"\u279c  repo git:(main) ",
		"Last Command: ",
		"\u273b Baked for 11s \u00b7 done 6:13 PM",
		"  \u23f5\u23f5 auto mode on (shift+tab to cycle) \u00b7 \u2190 for agents",
	])("does not match %j", (line) => {
		expect(detectsHighConfidenceInputPattern(line)).toBe(false);
	});
});

describe("AgentActivityMonitor", () => {
	it("starts idle before any output", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		expect(monitor.state()).toBe("idle");
	});

	it("goes active on output, polling for idle after 500 ms, idle after 1500 ms", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		const seen: Array<[AgentActivityState, number]> = [];
		const start = Date.now();
		monitor.onChange((state) => seen.push([state, Date.now() - start]));
		source.write(10);
		monitor.observe();
		vi.advanceTimersByTime(5_000);
		expect(seen).toEqual([
			["active", 0],
			["pollingForIdle", ACTIVITY_POLLING_AFTER_MS],
			["idle", ACTIVITY_IDLE_AFTER_MS],
		]);
		expect(vi.getTimerCount()).toBe(0);
	});

	it("stays active while output keeps arriving within the polling window", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		const seen: AgentActivityState[] = [];
		monitor.onChange((state) => seen.push(state));
		for (let frame = 0; frame < 50; frame += 1) {
			source.write(1);
			monitor.observe();
			vi.advanceTimersByTime(ACTIVITY_POLLING_AFTER_MS - 1);
		}
		expect(seen).toEqual(["active"]);
		expect(monitor.state()).toBe("active");
	});

	it("never reports idle while output arrives once a second, as a hidden window drains it", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		const seen: AgentActivityState[] = [];
		monitor.onChange((state) => seen.push(state));
		for (let second = 0; second < 30; second += 1) {
			source.write(1);
			monitor.observe();
			vi.advanceTimersByTime(1_000);
		}
		expect(seen).not.toContain("idle");
		expect(seen.filter((state) => state === "pollingForIdle")).toHaveLength(30);
	});

	it("reports prompting once quiet when the cursor line asks a question, and goes active on the answer", () => {
		const source = fakeSource("Overwrite? (y/n) ");
		const monitor = new AgentActivityMonitor(source);
		const seen: AgentActivityState[] = [];
		monitor.onChange((state) => seen.push(state));
		source.write(5);
		monitor.observe();
		vi.advanceTimersByTime(3_000);
		expect(seen).toEqual(["active", "prompting"]);
		source.setLine("Overwrite? (y/n) y");
		source.write(1);
		monitor.observe();
		vi.advanceTimersByTime(3_000);
		expect(seen).toEqual(["active", "prompting", "active", "pollingForIdle", "idle"]);
	});

	it("never reads the cursor line while output is active", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		source.write(1);
		monitor.observe();
		source.cursorLine.mockClear();
		expect(monitor.state()).toBe("active");
		expect(source.cursorLine).not.toHaveBeenCalled();
	});

	it("keeps no timer without a listener, and the last teardown cancels it", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		source.write(1);
		monitor.observe();
		expect(vi.getTimerCount()).toBe(0);
		const first = vi.fn();
		const second = vi.fn();
		const stopFirst = monitor.onChange(first);
		const stopSecond = monitor.onChange(second);
		expect(vi.getTimerCount()).toBe(1);
		stopFirst();
		expect(vi.getTimerCount()).toBe(1);
		stopSecond();
		expect(vi.getTimerCount()).toBe(0);
		vi.advanceTimersByTime(5_000);
		expect(first).not.toHaveBeenCalled();
		expect(second).not.toHaveBeenCalled();
	});

	it("dispose cancels the timer and silences every listener", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		const listener = vi.fn();
		monitor.onChange(listener);
		source.write(1);
		monitor.observe();
		listener.mockClear();
		monitor.dispose();
		expect(vi.getTimerCount()).toBe(0);
		source.write(1);
		monitor.observe();
		vi.advanceTimersByTime(5_000);
		expect(listener).not.toHaveBeenCalled();
	});
});

describe("TerminalCore agent activity", () => {
	function core(columns = 120, rows = 40): TerminalCore {
		const target = createTerminalCore({ columns, rows, limits: { rows: 200_000, bytes: 128 * 1024 * 1024 } });
		target.setAgentTuiMode(true);
		return target;
	}

	it("counts live output only: the replay frame, a history chunk and an older answer stay idle", () => {
		const target = core(80, 24);
		const seen: AgentActivityState[] = [];
		target.onAgentActivity((state) => seen.push(state));
		target.feed(encoder.encode("\x1b]7000;v=1;origin=1000\x1b\\frame\r\n\x1b]7000;v=1;ready=1\x1b\\"));
		target.feed(encoder.encode("\x1b]7000;v=1;history=998,2\x1b\\one\r\ntwo\r\n"));
		target.feed(encoder.encode("\x1b]7000;v=1;history=996,2;cols=80\x1b\\three\r\nfour\r\n\x1b]7000;v=1;older=996\x1b\\"));
		expect(target.snapshot().firstStableRow).toBe(996);
		expect(seen).toEqual([]);
		expect(target.agentActivity()).toBe("idle");
		target.feed(encoder.encode("live"));
		expect(seen).toEqual(["active"]);
		target.dispose();
	});

	it("stops reporting after the listener's teardown and after dispose", () => {
		const target = core(80, 24);
		const listener = vi.fn();
		const stop = target.onAgentActivity(listener);
		target.feed(encoder.encode("a"));
		expect(listener).toHaveBeenCalledTimes(1);
		stop();
		vi.advanceTimersByTime(5_000);
		expect(listener).toHaveBeenCalledTimes(1);
		const kept = vi.fn();
		target.onAgentActivity(kept);
		target.feed(encoder.encode("b"));
		kept.mockClear();
		target.dispose();
		expect(vi.getTimerCount()).toBe(0);
		vi.advanceTimersByTime(5_000);
		target.feed(encoder.encode("c"));
		expect(kept).not.toHaveBeenCalled();
	});

	it("reports prompting for a y/n question at the cursor", () => {
		const target = core(80, 24);
		target.feed(encoder.encode("Overwrite greet.py? (y/n) "));
		vi.advanceTimersByTime(ACTIVITY_POLLING_AFTER_MS);
		expect(target.agentActivity()).toBe("prompting");
		target.dispose();
	});

	it.each([
		["claude-spinner-10s", 120],
		["claude-markdown-reply", 157],
		["claude-long-50k", 1048],
	] as const)(
		"%s: active for all %i frames at a 100 ms cadence, idle 1500 ms after the last byte, never prompting",
		async (name, frames) => {
			const { recording, sizes } = await fixture(name);
			const target = core(sizes[0]!.cols, sizes[0]!.rows);
			const start = Date.now();
			const seen: Array<[AgentActivityState, number]> = [];
			target.onAgentActivity((state) => seen.push([state, Date.now() - start]));
			let fed = 0;
			let prompts = 0;
			let nextSize = 1;
			const ends = frameEnds(recording);
			for (const end of ends) {
				while (nextSize < sizes.length && sizes[nextSize]!.offset <= end) {
					const size = sizes[nextSize]!;
					target.feed(recording.subarray(fed, size.offset));
					fed = size.offset;
					target.resize(size.cols, size.rows);
					nextSize += 1;
				}
				target.feed(recording.subarray(fed, end));
				fed = end;
				if (detectsHighConfidenceInputPattern(cursorLineText(target.snapshot(), decoder))) prompts += 1;
				vi.advanceTimersByTime(FRAME_MS);
			}
			const last = (ends.length - 1) * FRAME_MS;
			vi.advanceTimersByTime(ACTIVITY_IDLE_AFTER_MS);
			expect(ends).toHaveLength(frames);
			expect(prompts).toBe(0);
			expect(seen).toEqual([
				["active", 0],
				["pollingForIdle", last + ACTIVITY_POLLING_AFTER_MS],
				["idle", last + ACTIVITY_IDLE_AFTER_MS],
			]);
			target.dispose();
		},
	);
});
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd "$REPO/packages/terminal/ts/core" && npx vitest run src/agent-activity.test.ts 2>&1 | tail -4
```
Expected: FAIL — `AgentActivityMonitor` / `detectsHighConfidenceInputPattern` not exported.

- [ ] **Step 3: Port the prompt patterns (MIT) with their licence and attribution**

```bash
cd "$REPO/packages/terminal/ts/core/src" && cp ../../renderer-dom/src/LICENSE-VSCODE-MIT LICENSE-VSCODE-MIT && head -3 LICENSE-VSCODE-MIT
```
Expected: `MIT License`, a blank line, `Copyright (c) 2015 - present Microsoft Corporation`.

Create `packages/terminal/ts/core/src/input-patterns.ts` with exactly this content (the header is the licence notice the port must keep; the nine expressions are VS Code's, verbatim, in VS Code's order):

```ts
/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE-VSCODE-MIT beside this file.
 *--------------------------------------------------------------------------------------------*/

const HIGH_CONFIDENCE_INPUT_PATTERNS: readonly RegExp[] = [
	/\s*(?:\[[^\]]\][^\[]*)+(?:\(default is\s+"[^"]+"\):)?\s+$/,
	/(?:\(|\[)\s*(?:y(?:es)?\s*\/\s*n(?:o)?|n(?:o)?\s*\/\s*y(?:es)?)\s*(?:\]|\))\s+$/i,
	/[?:]\s*(?:\(|\[)?\s*y(?:es)?\s*\/\s*n(?:o)?\s*(?:\]|\))?\s+$/i,
	/\(y\) +$/i,
	/:\s+\([^)]*\) +$/,
	/\(END\)$/,
	/password(?: for [^:]+)?:\s*$/i,
	/press a(?:ny)? key/i,
	/^(?:\s|\x1b\[[0-9;]*m)*\?.*[\u203a\u276f\u25b8\u25b6]\s*$/,
];

export function detectsHighConfidenceInputPattern(cursorLine: string): boolean {
	return HIGH_CONFIDENCE_INPUT_PATTERNS.some((pattern) => pattern.test(cursorLine));
}
```

Create `packages/terminal/ts/core/src/VSCODE-INPUT-PATTERNS-ATTRIBUTION.md`:

```markdown
# Input patterns

`input-patterns.ts` ports `detectsHighConfidenceInputPattern` from
`src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/monitoring/outputMonitor.ts`
in Visual Studio Code (https://github.com/microsoft/vscode, commit `d3c24c3`),
used under the MIT licence (`LICENSE-VSCODE-MIT` beside this file).

Changes made in the port, and nothing else:

- The nine regular expressions are kept verbatim, in the same order, in a
  module-level array instead of an array literal built on every call.
- VS Code's explanatory comments above each expression are not carried over.
- The broader `detectsLikelyInputRequiredPattern` rules (a bare `: ` or `? `
  at the end of the line) are not ported: VS Code applies them only when it
  knows the command is still running, and this package cannot know that.

The idle timing in `agent-activity.ts` follows the behaviour of VS Code's
`OutputMonitor._waitForIdle` and `PollingConsts` (`MinPollingDuration = 500`,
`MinIdleEvents = 2`, first two polling intervals 500 ms and 1,000 ms) but is
written for this package; no code from those functions is copied.
```

- [ ] **Step 4: Create the monitor**

Create `packages/terminal/ts/core/src/agent-activity.ts`:

```ts
import { detectsHighConfidenceInputPattern } from "./input-patterns.js";
import type { TerminalSnapshot } from "./types.js";

export type AgentActivityState = "active" | "pollingForIdle" | "idle" | "prompting";

export type AgentActivityListener = (state: AgentActivityState) => void;

export const ACTIVITY_POLLING_AFTER_MS = 500;

export const ACTIVITY_IDLE_AFTER_MS = 1500;

export type AgentActivitySource = Readonly<{
	liveOutputBytes(): number;
	cursorLine(): string;
	now(): number;
}>;

export class AgentActivityMonitor {
	private readonly source: AgentActivitySource;
	private readonly listeners = new Set<AgentActivityListener>();
	private lastOutputBytes = 0;
	private lastOutputAt = Number.NEGATIVE_INFINITY;
	private reported: AgentActivityState;
	private timer: ReturnType<typeof setTimeout> | null = null;
	private disposed = false;

	constructor(source: AgentActivitySource) {
		this.source = source;
		this.lastOutputBytes = source.liveOutputBytes();
		this.reported = this.evaluate(source.now());
	}

	state(): AgentActivityState {
		return this.evaluate(this.source.now());
	}

	onChange(listener: AgentActivityListener): () => void {
		this.listeners.add(listener);
		this.reported = this.evaluate(this.source.now());
		this.schedule();
		return () => {
			this.listeners.delete(listener);
			if (this.listeners.size === 0) this.cancel();
		};
	}

	observe(): void {
		if (this.disposed) return;
		const bytes = this.source.liveOutputBytes();
		if (bytes === this.lastOutputBytes) return;
		this.lastOutputBytes = bytes;
		this.lastOutputAt = this.source.now();
		this.report("active");
		this.schedule();
	}

	dispose(): void {
		this.disposed = true;
		this.cancel();
		this.listeners.clear();
	}

	private evaluate(now: number): AgentActivityState {
		const quiet = now - this.lastOutputAt;
		if (quiet < ACTIVITY_POLLING_AFTER_MS) return "active";
		if (detectsHighConfidenceInputPattern(this.source.cursorLine())) return "prompting";
		return quiet < ACTIVITY_IDLE_AFTER_MS ? "pollingForIdle" : "idle";
	}

	private report(state: AgentActivityState): void {
		if (state === this.reported) return;
		this.reported = state;
		for (const listener of [...this.listeners]) listener(state);
	}

	private schedule(): void {
		if (this.disposed || this.timer !== null || this.listeners.size === 0) return;
		const now = this.source.now();
		const quiet = now - this.lastOutputAt;
		const due =
			quiet < ACTIVITY_POLLING_AFTER_MS
				? ACTIVITY_POLLING_AFTER_MS - quiet
				: quiet < ACTIVITY_IDLE_AFTER_MS
					? ACTIVITY_IDLE_AFTER_MS - quiet
					: null;
		if (due === null) return;
		this.timer = setTimeout(() => {
			this.timer = null;
			if (this.disposed) return;
			this.report(this.evaluate(this.source.now()));
			this.schedule();
		}, due);
	}

	private cancel(): void {
		if (this.timer === null) return;
		clearTimeout(this.timer);
		this.timer = null;
	}
}

export function cursorLineText(snapshot: TerminalSnapshot, decoder: TextDecoder): string {
	const alt = snapshot.altScreen;
	const content = alt ? alt.content : snapshot.content;
	const ranges = alt ? alt.rowRanges : snapshot.rows;
	const row = alt ? alt.cursorRow : snapshot.cursorRow;
	const column = alt ? alt.cursorColumn : snapshot.cursorColumn;
	const start = ranges[row * 2];
	const end = ranges[row * 2 + 1];
	const text = start === undefined || end === undefined || end <= start ? "" : decoder.decode(content.subarray(start, end));
	const width = [...text].length;
	return width < column ? text + " ".repeat(column - width) : text;
}
```

- [ ] **Step 5: Wire `terminal-core.ts`**

In `packages/terminal/ts/core/src/terminal-core.ts` (as left by Task 3) make these replacements (each quoted text occurs exactly once):

(1) Replace
```ts
import { AgentEvents, type AgentEventListener } from "./agent-events.js";
```
with
```ts
import { AgentEvents, type AgentEventListener } from "./agent-events.js";
import { AgentActivityMonitor, cursorLineText, type AgentActivityListener, type AgentActivityState } from "./agent-activity.js";
```

(2) Replace
```ts
	private readonly agentEvents: AgentEvents;
```
with
```ts
	private readonly agentEvents: AgentEvents;
	private readonly activity: AgentActivityMonitor;
```

(3) Replace
```ts
		this.agentEvents = new AgentEvents(inner);
```
with
```ts
		this.agentEvents = new AgentEvents(inner);
		this.activity = new AgentActivityMonitor({
			liveOutputBytes: () => (this.disposed ? 0 : this.inner.live_output_bytes()),
			cursorLine: () => (this.disposed ? "" : cursorLineText(this.snapshot(), this.decoder)),
			now: () => Date.now(),
		});
```

(4) Replace
```ts
		this.inner.feed(bytes, Date.now());
		this.program.poll();
		this.agentEvents.poll();
```
with
```ts
		this.inner.feed(bytes, Date.now());
		this.program.poll();
		this.agentEvents.poll();
		this.activity.observe();
```

(5) Replace
```ts
		this.agentEvents.poll();
		this.notifyIfChanged();
		return true;
```
with
```ts
		this.agentEvents.poll();
		this.activity.observe();
		this.notifyIfChanged();
		return true;
```

(6) Replace
```ts
	onAgentEvent(listener: AgentEventListener): () => void {
		return this.agentEvents.onEvent(listener);
	}
```
with
```ts
	onAgentEvent(listener: AgentEventListener): () => void {
		return this.agentEvents.onEvent(listener);
	}

	agentActivity(): AgentActivityState {
		return this.activity.state();
	}

	onAgentActivity(listener: AgentActivityListener): () => void {
		return this.activity.onChange(listener);
	}
```

(7) Replace
```ts
		this.agentEvents.dispose();
```
with
```ts
		this.agentEvents.dispose();
		this.activity.dispose();
```

- [ ] **Step 6: Export from the package**

In `packages/terminal/ts/core/src/index-browser.ts`, replace
```ts
export {
	FEED_BUDGET_MS,
```
with
```ts
export {
	ACTIVITY_IDLE_AFTER_MS,
	ACTIVITY_POLLING_AFTER_MS,
	AgentActivityMonitor,
	cursorLineText,
	type AgentActivityListener,
	type AgentActivitySource,
	type AgentActivityState,
} from "./agent-activity.js";
export { detectsHighConfidenceInputPattern } from "./input-patterns.js";
export {
	FEED_BUDGET_MS,
```

- [ ] **Step 7: Run to see it pass**

```bash
cd "$REPO/packages/terminal/ts/core" && npx vitest run src/agent-activity.test.ts 2>&1 | grep -E "Tests  "
npx vitest run 2>&1 | grep -E "Tests  "
npx tsc -p . --noEmit && echo tsc-ok
wc -l src/terminal-core.ts
cd "$REPO/packages/terminal" && npm run check:boundaries 2>&1 | tail -2
```
Expected: `Tests  30 passed (30)`; `Tests  141 passed (141)`; `tsc-ok`; `585 src/terminal-core.ts`; `boundary check passed`. The three fixture tests assert the timings in the design decisions (120 / 157 / 1,048 frames, `pollingForIdle` at last byte + 500 ms, `idle` at + 1,500 ms, no prompt at any frame boundary).

- [ ] **Step 8: Commit**

```bash
cd "$REPO" && git add packages/terminal/ts/core/src/input-patterns.ts packages/terminal/ts/core/src/LICENSE-VSCODE-MIT \
  packages/terminal/ts/core/src/VSCODE-INPUT-PATTERNS-ATTRIBUTION.md \
  packages/terminal/ts/core/src/agent-activity.ts packages/terminal/ts/core/src/agent-activity.test.ts \
  packages/terminal/ts/core/src/terminal-core.ts packages/terminal/ts/core/src/index-browser.ts
git commit -m "feat(terminal-core): agent activity detector (active, polling for idle, idle, prompting)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: `readBlockOutput(id, { compact, maxLines })`

**Files:**
- Create: `packages/terminal/ts/core/src/compact-output.ts`, `compact-output.test.ts`, `block-output.ts`, `block-output.test.ts` (all under `packages/terminal/ts/core/src/`)
- Modify: `packages/terminal/ts/core/src/terminal-core.ts` (after Task 4), `packages/terminal/ts/core/src/index-browser.ts`

**Interfaces:**
- Consumes: `snapshotLogicalLines` (`ts/core/src/logical-lines.ts:15`), `decodeBlocks` (`blocks.ts:12`), `BlockView`.
- Produces: `COMPACT_REDRAW_LOOKBACK = 256`, `COMPACT_MIN_REDRAW_LINES = 3`, `isSpinnerLine(line): boolean`, `compactLines(lines: readonly string[]): string[]`, `capLines(lines: readonly string[], maxLines: number): string[]`; `type BlockOutputOptions = Readonly<{ compact?: boolean; maxLines?: number }>`; `blockOutputText(snapshot, block, decoder, options?): string`; `TerminalCore.readBlockOutput(id: BlockId, options?: BlockOutputOptions): string | null`.

- [ ] **Step 1: Write the failing tests**

Create `packages/terminal/ts/core/src/compact-output.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { capLines, COMPACT_REDRAW_LOOKBACK, compactLines, isSpinnerLine } from "./index";

describe("isSpinnerLine", () => {
	it.each([
		"\u273d Flamb\u00e9ing\u2026 (13s \u00b7 still thinking with high effort)",
		"\u00b7 Thinking\u2026",
		"  \u280b Installing dependencies...",
		"\u25d0 Loading\u2026",
	])("recognises %j", (line) => {
		expect(isSpinnerLine(line)).toBe(true);
	});

	it.each([
		"\u273b Baked for 11s \u00b7 done 6:13 PM",
		"- Installing dependencies...",
		"* item one\u2026",
		"Thinking\u2026",
		"\u273b",
	])("leaves %j", (line) => {
		expect(isSpinnerLine(line)).toBe(false);
	});
});

describe("compactLines", () => {
	it("trims trailing spaces, collapses blank runs and drops leading and trailing blanks", () => {
		expect(compactLines(["", "a   ", "", "", "b", "", ""])).toEqual(["a", "", "b"]);
	});

	it("drops spinner status lines", () => {
		expect(compactLines(["\u273d Working\u2026 (3s)", "result", "\u273b Worked for 3s"])).toEqual(["result", "\u273b Worked for 3s"]);
	});

	it("collapses a line repeated back to back", () => {
		expect(compactLines(["banner", "banner", "body"])).toEqual(["banner", "body"]);
	});

	it("drops a redrawn frame of three or more lines seen within the lookback", () => {
		const frame = ["\u256d\u2500\u2500\u2500\u256e", "\u2502 > \u2502", "\u2570\u2500\u2500\u2500\u256f"];
		expect(compactLines([...frame, "between", ...frame, "after"])).toEqual([...frame, "between", "after"]);
	});

	it("keeps a repeat of only two lines and a repeat beyond the lookback", () => {
		expect(compactLines(["a", "b", "x", "a", "b"])).toEqual(["a", "b", "x", "a", "b"]);
		const block = ["one", "two", "three"];
		const filler = Array.from({ length: COMPACT_REDRAW_LOOKBACK }, (_, index) => `filler ${index}`);
		expect(compactLines([...block, ...filler, ...block])).toEqual([...block, ...filler, ...block]);
	});

	it("does not count blank lines toward a redrawn frame", () => {
		expect(compactLines(["a", "", "b", "x", "a", "", "b"])).toEqual(["a", "", "b", "x", "a", "", "b"]);
	});
});

describe("capLines", () => {
	it("keeps the head and the tail around one marker line", () => {
		const lines = Array.from({ length: 10 }, (_, index) => `line ${index}`);
		expect(capLines(lines, 5)).toEqual(["line 0", "line 1", "\u2026 6 lines omitted \u2026", "line 8", "line 9"]);
		expect(capLines(lines, 10)).toEqual(lines);
	});

	it("rejects a cap below three lines or not an integer", () => {
		expect(() => capLines(["a"], 2)).toThrow(RangeError);
		expect(() => capLines(["a"], 3.5)).toThrow(RangeError);
	});
});
```

Create `packages/terminal/ts/core/src/block-output.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, decodeBlocks, initTerminalCore, type TerminalCore } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

const encoder = new TextEncoder();

type Size = { offset: number; cols: number; rows: number };

async function replay(name: string, agentTui: boolean): Promise<TerminalCore> {
	const dir = new URL(`../../../bench/agent-session/fixtures/${name}/`, import.meta.url);
	const recording = new Uint8Array(await readFile(fileURLToPath(new URL("recording", dir))));
	const sizes = JSON.parse(await readFile(fileURLToPath(new URL("size.json", dir)), "utf8")) as Size[];
	const core = createTerminalCore({
		columns: sizes[0]!.cols,
		rows: sizes[0]!.rows,
		limits: { rows: 200_000, bytes: 128 * 1024 * 1024 },
	});
	core.setAgentTuiMode(agentTui);
	let fed = 0;
	for (const size of sizes.slice(1)) {
		core.feed(recording.subarray(fed, size.offset));
		fed = size.offset;
		core.resize(size.cols, size.rows);
	}
	core.feed(recording.subarray(fed));
	return core;
}

function lastBlockId(core: TerminalCore): string {
	return decodeBlocks(core.snapshot()).at(-1)!.id;
}

function count(lines: string[], line: string): number {
	return lines.filter((candidate) => candidate === line).length;
}

describe("readBlockOutput", () => {
	it("returns null for an unknown block and after dispose", () => {
		const core = createTerminalCore({ columns: 20, rows: 5, limits: { rows: 100, bytes: 1 << 20 } });
		core.feed(encoder.encode("hello"));
		expect(core.readBlockOutput("9:9")).toBeNull();
		const id = lastBlockId(core);
		core.dispose();
		expect(core.readBlockOutput(id)).toBeNull();
	});

	it("reads a shell block's rows, joins a soft-wrapped line and drops trailing blank rows", () => {
		const core = createTerminalCore({ columns: 10, rows: 6, limits: { rows: 100, bytes: 1 << 20 } });
		core.feed(encoder.encode("\x1b]133;A\x07$ \x1b]133;B\x07echo\x1b]133;C\x07\r\nabcdefghijklmnopqrstuvwxy\r\nend\r\n\x1b]133;D;0\x07"));
		const block = decodeBlocks(core.snapshot()).find((view) => view.state === "finished")!;
		expect(core.readBlockOutput(block.id)).toBe("$ echo\nabcdefghijklmnopqrstuvwxy\nend");
		core.dispose();
	});

	it("caps the lines with a marker when maxLines is given", () => {
		const core = createTerminalCore({ columns: 20, rows: 30, limits: { rows: 100, bytes: 1 << 20 } });
		for (let index = 0; index < 20; index += 1) core.feed(encoder.encode(`row ${index}\r\n`));
		expect(core.readBlockOutput(lastBlockId(core), { maxLines: 5 })).toBe("row 0\nrow 1\n\u2026 16 lines omitted \u2026\nrow 18\nrow 19");
		core.dispose();
	});

	it("claude-spinner-10s: compact drops the live spinner line and keeps the prompt", async () => {
		const core = await replay("claude-spinner-10s", true);
		const id = lastBlockId(core);
		const raw = core.readBlockOutput(id)!.split("\n");
		const compact = core.readBlockOutput(id, { compact: true })!.split("\n");
		expect(raw.some((line) => line.includes("Flamb\u00e9ing\u2026"))).toBe(true);
		expect(compact.some((line) => line.includes("Flamb\u00e9ing\u2026"))).toBe(false);
		expect(compact.some((line) => line.startsWith("\u276f Do all of the following"))).toBe(true);
		expect(raw).toHaveLength(25);
		expect(compact).toHaveLength(24);
		core.dispose();
	});

	it("claude-markdown-reply without agent mode: compact keeps one banner of the three the resizes pushed", async () => {
		const core = await replay("claude-markdown-reply", false);
		const id = lastBlockId(core);
		const raw = core.readBlockOutput(id)!.split("\n");
		const compact = core.readBlockOutput(id, { compact: true })!.split("\n");
		const banner = raw[0]!;
		expect(banner.endsWith("Claude Code v2.1.280")).toBe(true);
		expect(count(raw, banner)).toBe(4);
		expect(count(compact, banner)).toBe(1);
		expect(compact.some((line) => line.startsWith("\u23fa I updated greet.py"))).toBe(true);
		expect(raw).toHaveLength(101);
		expect(compact).toHaveLength(88);
		core.dispose();
	});

	it("claude-long-50k: compact keeps all twenty turns of 3,000 numbers", async () => {
		const core = await replay("claude-long-50k", true);
		const id = lastBlockId(core);
		const compact = core.readBlockOutput(id, { compact: true })!.split("\n");
		expect(compact.filter((line) => /^(?:\u23fa | {2})\d+$/.test(line))).toHaveLength(60_000);
		expect(compact.filter((line) => line.startsWith("\u273b ") && line.includes(" \u00b7 done "))).toHaveLength(20);
		core.dispose();
	});
});
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$REPO/packages/terminal/ts/core" && npx vitest run src/compact-output.test.ts src/block-output.test.ts 2>&1 | tail -4
```
Expected: FAIL — `compactLines`/`isSpinnerLine` not exported, `core.readBlockOutput is not a function`.

- [ ] **Step 3: Implement**

Create `packages/terminal/ts/core/src/compact-output.ts`:

```ts
export const COMPACT_REDRAW_LOOKBACK = 256;

export const COMPACT_MIN_REDRAW_LINES = 3;

const SPINNER_LINE = /^\s*[\u2800-\u28ff\u00b7\u2722\u2733\u2736\u273b\u273d\u25d0-\u25d3]\s+\S.*(?:\u2026|\.\.\.)/u;

export function isSpinnerLine(line: string): boolean {
	return SPINNER_LINE.test(line);
}

export function compactLines(lines: readonly string[]): string[] {
	const normalized: string[] = [];
	for (const raw of lines) {
		const line = raw.trimEnd();
		if (isSpinnerLine(line)) continue;
		if (line === "" && (normalized.length === 0 || normalized.at(-1) === "")) continue;
		if (line !== "" && normalized.at(-1) === line) continue;
		normalized.push(line);
	}
	const kept: string[] = [];
	const seen = new Map<string, number[]>();
	let index = 0;
	while (index < normalized.length) {
		const line = normalized[index]!;
		const repeated = line === "" ? 0 : repeatedRun(normalized, index, kept, seen.get(line));
		if (repeated > 0) {
			index += repeated;
			continue;
		}
		if (line !== "") {
			const positions = seen.get(line);
			if (positions) positions.push(kept.length);
			else seen.set(line, [kept.length]);
		}
		kept.push(line);
		index += 1;
	}
	while (kept.at(-1) === "") kept.pop();
	return kept;
}

function repeatedRun(lines: readonly string[], at: number, kept: readonly string[], positions: readonly number[] | undefined): number {
	if (!positions) return 0;
	const floor = kept.length - COMPACT_REDRAW_LOOKBACK;
	let best = 0;
	for (let slot = positions.length - 1; slot >= 0; slot -= 1) {
		const start = positions[slot]!;
		if (start < floor) break;
		let length = 0;
		let visible = 0;
		while (at + length < lines.length && start + length < kept.length && lines[at + length] === kept[start + length]) {
			if (lines[at + length] !== "") visible += 1;
			length += 1;
		}
		if (visible >= COMPACT_MIN_REDRAW_LINES && length > best) best = length;
	}
	return best;
}

export function capLines(lines: readonly string[], maxLines: number): string[] {
	if (!Number.isInteger(maxLines) || maxLines < 3) {
		throw new RangeError(`maxLines must be an integer of at least 3, got ${maxLines}`);
	}
	if (lines.length <= maxLines) return [...lines];
	const head = Math.ceil((maxLines - 1) / 2);
	const tail = maxLines - 1 - head;
	const omitted = lines.length - head - tail;
	return [...lines.slice(0, head), `\u2026 ${omitted} lines omitted \u2026`, ...lines.slice(lines.length - tail)];
}
```

Create `packages/terminal/ts/core/src/block-output.ts`:

```ts
import { capLines, compactLines } from "./compact-output.js";
import { snapshotLogicalLines } from "./logical-lines.js";
import type { BlockView, TerminalSnapshot } from "./types.js";

export type BlockOutputOptions = Readonly<{ compact?: boolean; maxLines?: number }>;

export function blockOutputText(
	snapshot: TerminalSnapshot,
	block: BlockView,
	decoder: TextDecoder,
	options: BlockOutputOptions = {},
): string {
	const range = { start: block.firstRow, end: block.firstRow + block.rowCount };
	let lines = snapshotLogicalLines(snapshot, range, decoder).map((line) => line.text);
	if (options.compact) {
		lines = compactLines(lines);
	} else {
		while (lines.length > 0 && lines.at(-1)!.trim() === "") lines.pop();
	}
	if (options.maxLines !== undefined) lines = capLines(lines, options.maxLines);
	return lines.join("\n");
}
```

In `packages/terminal/ts/core/src/terminal-core.ts` (as left by Task 4):

(1) Replace
```ts
import { AgentActivityMonitor, cursorLineText, type AgentActivityListener, type AgentActivityState } from "./agent-activity.js";
```
with
```ts
import { AgentActivityMonitor, cursorLineText, type AgentActivityListener, type AgentActivityState } from "./agent-activity.js";
import { blockOutputText, type BlockOutputOptions } from "./block-output.js";
```

(2) Replace
```ts
	onAgentActivity(listener: AgentActivityListener): () => void {
		return this.activity.onChange(listener);
	}
```
with
```ts
	onAgentActivity(listener: AgentActivityListener): () => void {
		return this.activity.onChange(listener);
	}

	readBlockOutput(id: BlockId, options: BlockOutputOptions = {}): string | null {
		if (this.disposed) return null;
		const snapshot = this.snapshot();
		const block = decodeBlocks(snapshot).find((view) => view.id === id);
		return block ? blockOutputText(snapshot, block, this.decoder, options) : null;
	}
```

In `packages/terminal/ts/core/src/index-browser.ts`, replace
```ts
export {
	FEED_BUDGET_MS,
```
with
```ts
export {
	COMPACT_MIN_REDRAW_LINES,
	COMPACT_REDRAW_LOOKBACK,
	capLines,
	compactLines,
	isSpinnerLine,
} from "./compact-output.js";
export { blockOutputText, type BlockOutputOptions } from "./block-output.js";
export {
	FEED_BUDGET_MS,
```

- [ ] **Step 4: Run to see them pass**

```bash
cd "$REPO/packages/terminal/ts/core" && npx vitest run src/compact-output.test.ts src/block-output.test.ts 2>&1 | grep -E "Tests  "
npx vitest run 2>&1 | grep -E "Tests  "
npx tsc -p . --noEmit && echo tsc-ok
wc -l src/terminal-core.ts src/index-browser.ts
```
Expected: `Tests  23 passed (23)`; `Tests  164 passed (164)`; `tsc-ok`; `593 src/terminal-core.ts`, `122 src/index-browser.ts`.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/ts/core/src/compact-output.ts packages/terminal/ts/core/src/compact-output.test.ts \
  packages/terminal/ts/core/src/block-output.ts packages/terminal/ts/core/src/block-output.test.ts \
  packages/terminal/ts/core/src/terminal-core.ts packages/terminal/ts/core/src/index-browser.ts
git commit -m "feat(terminal-core): readBlockOutput with a compact mode that drops spinner lines and redrawn frames" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Gates

**Files:** none (a fix found here goes in a commit naming the files it touches).

Run every command; paste each result into the report (Task 8). A gate that cannot run here is `not run: <reason>`.

- [ ] **Step 1: Rust and both wasm builds**

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1 && cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
git -C "$REPO" status --short backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
npm run build:wasm -- --force 2>&1 | tail -1 && npm run build:ts 2>&1 | tail -1
```
Expected: `Finished …`, only `rust-done`; an empty `git status` line (the asset equals Task 2's commit — if it changed, a later task altered vt-core without rebuilding: commit the rebuilt asset); `build-wasm: … ready`.

- [ ] **Step 2: TS suites and boundaries**

```bash
cd "$REPO/packages/terminal" && for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  "); done
npm run check:boundaries 2>&1 | tail -2
```
Expected (planning run): core `164 passed`, renderer-dom `985`, react `134`, editor `175`, completions `109` (the last four unchanged from Task 0); `boundary check passed`.

- [ ] **Step 3: Go**

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -3
go vet ./internal/adapters/runtime/ptyhost/...
```
Expected: three `ok` lines; no vet output.

- [ ] **Step 4: Frontend type check** (the frontend imports `@operator/terminal-core`; nothing in it changes)

```bash
cd "$REPO/frontend" && npx tsc --noEmit -p . && echo frontend-tsc-ok
```

- [ ] **Step 5: Playwright benches**

```bash
cd "$REPO/packages/terminal" && cp -R "$HOME/plan8-feel-baseline/." bench/agent-session/baselines/ && npm run bench:feel 2>&1 | tail -2
git -C "$REPO" checkout -- packages/terminal/bench/agent-session/baselines && git -C "$REPO" clean -fdq packages/terminal/bench/agent-session/baselines
npm run bench:agent:gate 2>&1 | tail -1
npm run bench:agent:scroll 2>&1 | tail -3 | cut -c1-200
npm run bench:selection 2>&1 | tail -3
npm run bench:affordances -- --action hover 2>&1 | tail -2
git -C "$REPO" checkout -- packages/terminal/bench/agent-session/baselines && git -C "$REPO" clean -fdq packages/terminal/bench/agent-session/baselines
git -C "$REPO" status --short
```
Expected: `PASS feel gate: zero pixel diff` (against the Task 0 recording; nothing here paints); `PASS agent-session gate`; three JSON lines from the scroll gate with `"covered"` equal to `"total"` (planning run: `"total":60134,"covered":60134`) and exit 0; `bench:selection` passes on macOS — on Linux write `not run: Linux copy chord`; affordances writes screenshots (never diffed); final `git status` clean.

- [ ] **Step 6: Daemon binary**

```bash
cd "$REPO" && npm --prefix frontend run build:daemon 2>&1 | tail -2
```
Expected: builds `frontend/daemon/opr` (it embeds the rebuilt `vt_host.wasm`). If the environment cannot build it: `not run: <reason>`.

---

### Task 7: Docs

**Files:** `packages/terminal/CHANGELOG.md`, `TERMINAL.md`, `docs/terminal/2026-09-19-terminal-reference-survey.md`, `docs/terminal/2026-09-24-not-done-plain-language.md`

- [ ] **Step 1: CHANGELOG** — insert as the first bullet under `## Unreleased` (`packages/terminal/CHANGELOG.md:3`, i.e. a new line 5 before the bullet that starts `- vt-core/marks: Load older output review fixes`):

```markdown
- vt-core/vt-wasm/core: agent awareness (roadmap Plan 8, survey §7.1 and §6.9). `vt-core` parses `OSC 777 ; agent-state ; v=1 ; state=<working|waiting|idle|done> [; detail=<percent-encoded UTF-8>] ST` (our wire format, `protocol/SPEC.md` §10, vectors `protocol/agent-vectors/agent-state.json`) into `take_agent_events()`: identical consecutive events collapse, at most 16 wait (oldest dropped), a payload that fills vte's 1,024-byte OSC buffer, a bad percent escape, a repeated key or a version other than 1 is ignored, `detail` is cut to 256 bytes; history chunks, older answers and the attach replay frame (adopted `origin=` to `ready=`) never deliver one; OSC 777 `notify` is unchanged. `live_output_bytes()` counts bytes that reach the live parser (not history rows, gated answers or the replay frame). TS: `TerminalCore.onAgentEvent(listener)`; `agentActivity()` / `onAgentActivity(listener)` report `active` (live output in the last 500 ms), `pollingForIdle`, `idle` (quiet 1,500 ms) or `prompting` (quiet and the cursor line matches VS Code's `detectsHighConfidenceInputPattern`, ported under MIT in `input-patterns.ts`); on the three Claude Code recordings replayed one frame per 100 ms: `active` throughout, `idle` 1,500 ms after the last byte, never `prompting`. `readBlockOutput(id, { compact, maxLines })` returns a block's logical lines; `compact` trims them, drops spinner status lines, blank runs, back-to-back repeats and frames of ≥ 3 lines redrawn within 256 lines (`claude-markdown-reply` without agent-TUI mode 101 → 88 lines; all 60,000 number lines of `claude-long-50k` kept). `vt-core` `lib.rs` moves its mode getters to `core_modes.rs` and `terminal-core.ts` its helpers to `core-checks.ts` (600-line limit). Operator consumes none of this yet. Both wasm artifacts and the daemon must be rebuilt.
```

- [ ] **Step 2: TERMINAL.md**

(a) §3 rule 2 (`TERMINAL.md:262-269`): after the sentence ending "Kitty's marks are GPL-3.0 and were not read." append (same paragraph):

```text
   Agent activity (§4.34) ports VS Code's `detectsHighConfidenceInputPattern`
   (MIT; `ts/core/src/input-patterns.ts`, `VSCODE-INPUT-PATTERNS-ATTRIBUTION.md`
   and `LICENSE-VSCODE-MIT` beside it) and follows VS Code's idle polling
   behaviour without copying code; the in-band agent events are our own wire
   format (`protocol/SPEC.md` §10), written from the survey's description of
   Warp's (§7.1; AGPL-3.0, no Warp file read).
```

(b) New section after §4.33 — insert before the line `## 5. Known gaps (not bugs, decisions pending)` (`TERMINAL.md:1177`):

```markdown
### 4.34 Agents could not tell the terminal what they were doing — roadmap Plan 8
- Before: agent state reached Operator only out of band (`opr` hooks over
  loopback HTTP, `opr mcp` `session_report`), so nothing worked for an agent
  whose hooks cannot reach the daemon (SSH, a container), and no host of the
  package could tell that an agent was idle or asking a question.
- In-band events: `OSC 777 ; agent-state ; v=1 ; state=… [; detail=…] ST`
  (`protocol/SPEC.md` §10). Plan 3's dispatcher (`program.rs` `osc777`) sends
  the `agent-state` extension to `AgentChannel` (`crates/vt-core/src/agent.rs`)
  before its `notify` check, so the two can never be confused. Parsing is
  strict (exact `v=1`, known state, no repeated key, strict percent-decoding);
  a payload of 1,024 bytes or more is ignored because vte's `no-std` OSC buffer
  (`MAX_OSC_RAW = 1024`) has already cut it. Identical consecutive events
  collapse; 16 wait at most; a process boundary forgets the last one; each
  queued event bumps the program generation, which `ts/core`'s `AgentEvents`
  polls after every feed and tick (`TerminalCore.onAgentEvent`).
- Never from loaded or replayed output — the Plan 3/7 rule: history chunk rows
  (attach history, older answers) go to the `HistoryReceiver`, whose
  `osc_dispatch` only interns hyperlinks, and their marks are held back by
  `AnswerGate`; the attach replay frame does reach vte, so `AgentChannel` is
  silenced from an adopted `origin=` mark to `ready=` (`lib.rs` `feed_raw`).
- Activity: `vt-core` counts bytes handed to vte outside the replay window
  (`live_output_bytes`, reset when a fresh core adopts a replay origin).
  `AgentActivityMonitor` (`ts/core/src/agent-activity.ts`) turns it into
  `active` (output in the last 500 ms), `pollingForIdle`, `idle` (1,500 ms
  quiet) or `prompting` (quiet and the cursor line matches VS Code's
  high-confidence prompt patterns, `input-patterns.ts`) — VS Code's
  500 ms / two-idle-polls behaviour (`chatAgentTools/.../monitoring/types.ts`
  `PollingConsts`) as a clock. The timer runs only while someone listens and
  stops at `idle`.
- `readBlockOutput(id, { compact, maxLines })`: a block's logical lines;
  `compact` drops spinner status lines (a spinner glyph, text, an ellipsis),
  blank runs, back-to-back repeats and any run of ≥ 3 non-blank lines that
  repeats one within the last 256 kept lines (a repainted frame). Lossy by
  design and opt-in; redaction is not applied (renderer only).
- Measured (planning run, 2026-09-25): the Claude Code recordings replayed one
  frame per 100 ms (120, 157 and 1,048 frames) are `active` throughout and
  `idle` 1,500 ms after the last byte, `prompting` at none of 1,325 frame
  boundaries; compact keeps all 60,000 number lines of `claude-long-50k`
  (24.9–30.5 ms per call) and cuts `claude-markdown-reply` without agent-TUI
  mode from 101 to 88 lines.
- Operator: nothing consumes these yet (user decision 2026-09-25). The mirror
  parses the events into its capped queue and drops them;
  `publishProgramLocked` (`ptyhost/program.go`) publishes only titles and
  notifications.
- References: VS Code (MIT) — `detectsHighConfidenceInputPattern` ported
  verbatim (`VSCODE-INPUT-PATTERNS-ATTRIBUTION.md`), polling behaviour
  followed. Warp (AGPL-3.0) — not read; the survey's description (§7.1) only.
- Guards: `crates/vt-core/tests/agent_events.rs` (vectors whole and byte by
  byte, history chunk, older answer byte by byte and inside a live event,
  replay frame, flood, boundary, sync block, live byte counter, recordings),
  `agent.rs` unit tests, `vt-wasm/tests/program_exports.rs`,
  `vtwasm/program_test.go` `TestAnAgentEventIsNeitherATitleNorANotificationInTheMirror`,
  `ts/core/src/agent-events.test.ts`, `agent-activity.test.ts` (incl. the three
  recordings and a hidden window's one-second drains), `compact-output.test.ts`,
  `block-output.test.ts`.
```

(c) §5 Known gaps — append after the last bullet of §5 ("**Typing ahead covers zsh only.** …", ending "…so a non-ASCII `cmd=`/`cwd=` from bash is wrong.", `TERMINAL.md:1562-1566`), before the `---` line:

```markdown
- **Nothing emits or consumes agent events yet** (§4.34). Operator keeps its
  local hooks; the in-band channel waits for remote agents. A sender must keep
  each sequence under 1,024 bytes and 14 fields (vte limits).
- **A replay that never sends `ready=` silences agent events** on that core
  until a later `ready=`: the window opens at an adopted `origin=` mark. The
  pty-host always sends both (§4.19).
- **Agent activity flickers in a hidden window.** WebKit throttles the drain
  and the monitor's timer to about once a second (§4.25), so a streaming agent
  reads `active` → `pollingForIdle` between bursts; it never reaches `idle`
  while bursts keep coming (1,500 ms threshold).
- **The prompt check counts code points, not cells**, when it pads the cursor
  line to the cursor column; on a row with wide characters the padding is
  short and a "trailing space" prompt pattern can miss.
- **`readBlockOutput` ignores redaction** (`secretPatterns` is applied by the
  renderer's text sources only) and `compact` is lossy: a legitimately
  repeated run of three or more lines within 256 lines is dropped.
```

- [ ] **Step 3: Survey** (`docs/terminal/2026-09-19-terminal-reference-survey.md`)

Line 129 (table row) — replace the whole line starting `| §6.9 | Not done |` with:

```text
| §6.9 | Partial | Roadmap Plan 8 (2026-09-25) — `ts/core` has `agentActivity()`/`onAgentActivity` (active / pollingForIdle / idle / prompting from live output, 500 ms / 1,500 ms, VS Code's high-confidence prompt patterns) and `readBlockOutput(id, { compact, maxLines })` (spinner lines and redrawn frames dropped). Not done: Operator does not consume either; no tool surface (run/get-output/send), no user-input tracking while prompting, no per-command compressors. |
```

Line 132 (table row) — replace the whole line starting `| §7.1 | Not done |` with:

```text
| §7.1 | Partial | Roadmap Plan 8 (2026-09-25) — `vt-core` parses `OSC 777 ; agent-state ; v=1 ; state=… [; detail=…]` (our format, `protocol/SPEC.md` §10) into `onAgentEvent`, never from history, older answers or the replay frame; Plan 3 already parses OSC 777 `notify` and OSC 9. Not done: nothing emits it (Operator's hooks stay out of band, loopback HTTP) and Operator consumes none; remote/SSH agents are future work. |
```

Line 3911 (status under the §6.9 heading) — replace the line starting `> **Status: Not done.** No idle/prompt state machine` with:

```text
> **Status: Partial.** Roadmap Plan 8 (2026-09-25) — the idle/prompt detector (`TerminalCore.agentActivity()`/`onAgentActivity`) and `readBlockOutput({ compact })` are in `ts/core` (`TERMINAL.md` §4.34). Operator does not consume them; its board state still comes from `opr mcp` (`2e54a6bfb`) and the daemon (`0cd094f12`).
```

Line 4053 (status under the §7.1 heading) — replace the line starting `> **Status: Not done.** A non-goal of the agent-TUI spec.` with:

```text
> **Status: Partial.** Roadmap Plan 8 (2026-09-25) — an in-band agent-state channel over OSC 777 (`protocol/SPEC.md` §10, `TERMINAL.md` §4.34) parsed by `vt-core` and surfaced by `ts/core`; Plan 3 parses OSC 777 `notify` and OSC 9. Agent events still reach the daemon out of band (hooks, `opr mcp` `session_report`, the transcript's interrupt marker); nothing emits or consumes the in-band channel yet.
```

Then recount:

```bash
cd "$REPO" && awk -F'|' '/^\| §/ {gsub(/ /,"",$3); print $3}' docs/terminal/2026-09-19-terminal-reference-survey.md | sort | uniq -c
```
On `ce4941652` before this change it printed `45 Done, 1 N/A, 17 Notdone, 1 Notneeded, 7 Notpursued, 17 Partial`; after it, expect `45 Done, 1 N/A, 15 Notdone, 1 Notneeded, 7 Notpursued, 19 Partial` (if your base moved, Not done −2 and Partial +2 relative to it). Write your counts into the sentence at line 50 ("Every entry below carries a **Status** line … : 45 done, 17 partial, 17 not done, …") and append to that sentence: `"Roadmap Plan 8" is the agent-awareness plan (`docs/superpowers/plans/2026-09-25-terminal-plan-8-agent-awareness.md`).`

- [ ] **Step 4: Plain-language doc** (`docs/terminal/2026-09-24-not-done-plain-language.md:108-116`) — replace items 14 and 15 (from the line starting `14. **Agents telling the terminal` through the line ending `with the noise stripped out.`) with:

```markdown
14. **Agents telling the terminal what they're doing (§7.1).** *Partly done
    (roadmap Plan 8, 2026-09-25):* the terminal now understands a short
    in-band message an agent can print ("working", "needs you", "idle",
    "done"), which would also travel over SSH. Operator doesn't use it yet —
    it still learns Claude's state from its own side channel on your machine.
15. **The terminal noticing an agent is idle or waiting (§6.9).** *Partly
    done (roadmap Plan 8, 2026-09-25):* the terminal package can now tell
    "busy", "went quiet", "idle" and "asking a yes/no question" on its own,
    and can hand over a block's output with spinner lines and repeated
    redraws stripped out. Operator doesn't use either yet.
```

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/CHANGELOG.md TERMINAL.md \
  docs/terminal/2026-09-19-terminal-reference-survey.md \
  docs/terminal/2026-09-24-not-done-plain-language.md
git commit -m "docs: agent awareness — TERMINAL.md §4.34, changelog, survey §6.9/§7.1, plain-language list" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Push and report (do not merge)

- [ ] **Step 1: Check the branch**

```bash
cd "$REPO" && git status --short && git log --oneline origin/development..HEAD
```
Expected: clean status; 6 commits (Tasks 1, 2, 3, 4, 5, 7) plus any Task 6 fix.

- [ ] **Step 2: Push**

```bash
cd "$REPO" && git push -u origin terminal/plan-8-agent-awareness
```
Do not open a PR unless asked. Do not merge.

- [ ] **Step 3: Completion report** (your final message) containing:
1. Every gate from Tasks 0-6 with its quoted last lines, or `not run: <reason>`.
2. The detector timings the Task 4 fixture tests asserted (frames, last byte, `pollingForIdle`, `idle`) and the compact line counts the Task 5 tests asserted — as numbers.
3. Any quoted edit text that was not found as written, and what you did.
4. The statement: **Operator does not consume these APIs yet** — no `frontend/` or `backend/` code other than the rebuilt `vt_host.wasm` and one Go guard test changed; they are for future SSH/remote agents and other hosts.
5. Real-app checklist: **none — nothing user-visible.** No renderer, Operator or pixel change; the daemon only needs the rebuilt mirror wasm, which behaves identically for Operator (agent events are dropped in the mirror). A reviewer who wants to see it can run, in any pane of a rebuilt app, `printf '\033]777;agent-state;v=1;state=waiting;detail=hello\033\\'` and observe that nothing prints.
