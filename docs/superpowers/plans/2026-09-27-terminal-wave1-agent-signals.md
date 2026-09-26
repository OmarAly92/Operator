# Agent Signals in Operator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Operator shows working / needs you / done for any command-line agent, from the terminal screen as well as from hooks: the pty-host reads every session's screen (pane open or not), the daemon turns that into a debounced screen reading, merges it with hook state under a rule that never lets the screen override a fresh hook, raises one needs-you alert per question, and (phase B) puts the question text and a compact "what the agent just did" summary into the notification body. Measured on new timed recordings of real Claude Code and Codex sessions, with the false-alarm, missed-question, duplicate-alert and flicker counts written down.

**Architecture:** The screen classifier that today lives only in `packages/terminal/ts/core` (VS Code's prompt patterns over the cursor line, `ts/core/src/input-patterns.ts:6-20`, `agent-activity.ts:66-71`) moves into `vt-core` (`crates/vt-core/src/activity.rs`), so the renderer core and the pty-host mirror run the same code; the TS monitor keeps its timer and asks the core. The pty-host (`backend/internal/adapters/runtime/ptyhost`), which feeds every byte of every session into its mirror from spawn (`host.go:623-653`) and is watched by the daemon from spawn (`runtime.go:139`, `program_watch.go:40-58`), gets an activity clock and publishes `active` / `idle` / `prompting` transitions with the screen tail over the existing program-event watch. A new daemon observer (`backend/internal/observe/screen`) classifies each transition with the agent adapter (Claude Code and Codex dialog readers, a new Claude composer detector), debounces it, and calls the lifecycle reducer's `ApplyActivitySignal` with a screen reading; the reducer applies the pure merge rule `domain.MergeScreenReading` against an in-memory time of the last hook, so notifications, CDC patches, the board, the desktop bell and the phone all keep flowing through the one write path they use today (`lifecycle/manager.go:547-767`).

**Tech Stack:** Rust 1.96 (`vt-core`, `vt-wasm`, `vt-host`; `regex-automata` 0.4, already a `vt-core` dependency, `crates/vt-core/Cargo.toml:14`), wasm32 + wasm-bindgen 0.2.127, Go 1.25 (pty-host, `vtwasm` over wazero, lifecycle, observers, notify, push), TypeScript 5.9 + vitest 4.1.8, Python 3 (recording driver). No frontend or mobile source changes.

**Spec:** docs/terminal/2026-09-27-terminal-wishlist.md (item 2) and survey §6.9, §7.1

## Global Constraints

- Branch `terminal/wave1-agent-signals` from `development` in a scratch worktree (`git worktree add ../Operator-wave1-signals -b terminal/wave1-agent-signals development`). Never commit to `development` or `master`, never merge, never force-push. Never `git stash` in the shared checkout (memory: concurrent sessions commit there).
- Commits name explicit paths only: `git add <path> …`. Never `git add -A`, `git add .`, `git commit -a`.
- Every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- No comments in new code (Rust, Go, TS, Python, tests), per the user's global instruction and `TERMINAL.md` §3.3. The single exception is the MIT licence header `crates/vt-core/src/activity/input_patterns.rs` must carry because it ports VS Code code (the same header `ts/core/src/input-patterns.ts:1-4` carries today).
- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): nothing under `crates/`, `ts/` or `protocol/` names Operator, a harness, "hook", "board" or "session". The package learns only generic things: a cursor-line prompt check, an activity classification by quiet time, a compact tail of the output. Agent knowledge (Claude Code and Codex screens) stays in `backend/internal/adapters/agent/*`.
- No file under `packages/terminal` may exceed 600 lines, `.rs` and `.go` included (`scripts/check-boundaries.mjs:19-42`). Current counts that matter: `crates/vt-core/src/lib.rs` 597, `crates/vt-wasm/src/lib.rs` 581, `ts/core/src/terminal-core.ts` 599. This plan adds one line to `vt-core/src/lib.rs` (598), two to `vt-wasm/src/lib.rs` in Phase A (583; Phase B's longer `pub use` line is split by rustfmt, still under 595), and removes one from `terminal-core.ts` (598).
- A `vt-core` change is live only after **both** wasm artifacts are rebuilt (`TERMINAL.md` §3.5, §6): the renderer's (`npm run build:wasm -- --force`, gitignored) and the mirror's (`cargo build --release -p vt-host --target wasm32-unknown-unknown`, copied to `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`, **committed**). Old pty-host processes keep their old code for the life of the session (`TERMINAL.md` §3.5).
- Backend follows `AGENTS.md`: domain vocabulary and pure rules in `backend/internal/domain`, contracts in `backend/internal/ports`, adapters under `backend/internal/adapters`, the reducer in `backend/internal/lifecycle`, pollers/observers in `backend/internal/observe`. Status stays derived at read time (`AGENTS.md` "Do not store derived/display session status"): this plan stores no new column; the hook-freshness time and the last alerted question are memory-only in the lifecycle manager, like `flights` (`lifecycle/manager.go:161-163`).
- No API DTO change, so no `npm run api`. No frontend source change and no `packages/mobile` change: the board reads `status`/`activity` (`frontend/src/renderer/components/SessionsBoard.tsx:728-730`), the phone card reads `status` (`packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart:41`), and both already follow activity changes through CDC (`backend/internal/cdc/poller.go:13`, trigger `migrations/0118_session_agent_report.sql:16-41`). Another session has uncommitted work in `packages/mobile`; do not touch it.
- **Bodies reach the phone on both paths, masked and clean (Open Decision 2, decided 2026-09-27).** The question text (needs-you) and the compact summary (finished) go into the notification body, which the mux `notifications` channel and the in-app list already show (`internal/terminal/notifications.go:44-53` copies `rec.Body` into the frame; `packages/mobile/lib/core/notifications/phone_alerts_runtime.dart:66-70` passes `n.body` to `local_alert_sink.dart:47-51`), **and** into the ntfy message (Task 18), replacing today's one word (`push/alerts.go:197-198`). This reverses the agent-alerts spec's D6 (`docs/superpowers/specs/2026-09-23-agent-alerts-design.md:51`) and the test that pinned it, `TestAlertsSendsWhenPairedAndBackgrounded` (`push/alerts_test.go:55-68`, "alert leaked the notification body"), which Task 18 rewrites. Before any agent-supplied text leaves the daemon it goes through one cleaner, `redact.Clean` (new, Task 17): terminal escape sequences (CSI, OSC, two-byte ESC), every other control rune (`unicode.IsControl`: C0, DEL, C1) and bidi controls (`unicode.Bidi_Control`) are removed, invalid UTF-8 is dropped, then the daemon's secret masking `redact.Text` (`backend/internal/redact/redact.go:51-92`, built-in patterns `:36-43` plus the user's `redact-patterns.txt`, loaded at `daemon/daemon.go:149`) runs — **before** truncation, so a cut can never leave half a secret unmasked. `notify/enrich.go` applies it to the hook's `AssistantUpdate`, the agent report reason and the screen text (the in-app channel and the stored row); `push/alerts.go` applies it again at the third-party boundary and caps the message at ntfy's 4,096-byte message limit (ntfy docs, <https://docs.ntfy.sh/publish/>: "If a message is greater than the maximum message size (4,096 bytes) or consists of non UTF-8 characters, the ntfy server will … send the message as an attachment file"; our sender has no cap today, `push/ntfy.go:54-80`). PR notifications keep sending one word on ntfy (their bodies carry PR titles, `notify/enrich.go:68-86`, and `TestAlertsPRTypesNeverCarryThePRTitle`, `alerts_test.go:125-134`, keeps PR text off ntfy). No `packages/mobile` change: the local notification shows `body` already, and the ntfy notification is drawn by the separate ntfy app from the message (Operator has no ntfy client code; `packages/mobile/lib/feature/settings/presentation/settings_screen/logic/phone_alerts_cubit.dart:35-49` only copies the topic).
- Recordings are real bytes from real agents. Never re-record or edit an existing golden or fixture (`bench/agent-session/fixtures/*`, `crates/vt-core/tests/ref/*`); new recordings go in a new directory, `packages/terminal/bench/agent-session/signals/`, which `listFixtures()` does not scan (`bench/agent-session/fixtures.mjs:6-13`), so `bench:feel`, `bench:agent:gate` and `bench:agent:scroll` baselines are untouched.
- Running `claude` from inside a Claude session: scrub every `CLAUDE*` variable first (memory: a dev shell launched from a Claude session makes agents skip transcripts): `env $(env | awk -F= '/^CLAUDE/ {printf "-u %s ", $1}') claude …`.
- Never stop the user's `tauri:dev` without asking (memory: its process group takes the pty-hosts and live turns). The real-app checks use an isolated dev daemon on `127.0.0.1:3002`.
- Tool gaps are reported, not hidden: a command that cannot run is written `not run: <reason>` in the completion report. `TestProcessEnvironmentLetsOverridesWin` in `ptyhost` is a known pre-existing failure (`TERMINAL.md` §8).
- Evidence rule for docs written by this plan: cite `file:line` or write "not known"; numbers are the ones the harness printed.
- New `TERMINAL.md` section number: **§4.52**.

## Review Focus

1. **A pause is not a question, and not "done" either: an agent quietly thinking for 40 s with no output.** Expected: never needs-you; for an agent whose adapter can positively read its idle composer (Claude Code, Codex) the card stays working because their spinners keep printing (`crates/vt-core/tests/ref/claude_spinner_10s/screen.txt`: `✽ Flambéing… (13s · still thinking…)` and `esc to interrupt`); for an agent with no adapter detector the screen may call it settled only after `ScreenQuietSettle = 60 s` of silence, so a 40 s pause changes nothing. Pinned by Task 11 `TestDebouncerAFortySecondSilenceIsNotSettledWithoutADetector`, Task 3 `a_question_needs_a_prompt_on_the_cursor_line_not_just_silence`, and the harness recording `shell-pause` (Task 13, `sleep 40` then a real `read -p` question).
2. **A hook arriving after the screen already said needs-you (and a hook that should have arrived and did not).** Expected: a later `permission-request` hook on an already-blocked session is a same-state no-op (no second alert); a delayed `pre-tool-use` hook that moves the card to working wins (it is fresh), and when the screen re-asserts the same question once the hook is stale the card goes back to needs-you **without** a second alert; a missed `Stop` hook is corrected by the screen within 40 s. Pinned by Task 9 `TestScreen_LateHookAfterScreenQuestionAlertsOnce`, `TestScreen_FreshHookBlocksDemotionUntilStale`, Task 12 `TestObserverReassertsAConfirmedReadingThatAHookOverrode`, and the harness `missed-stop` mode (Task 13).
3. **A reconnect or relaunch replaying old output.** Expected: no activity event, no `active`, no alert. The renderer's replay never reaches the mirror; a relaunched pty-host seeds its mirror from the persisted replay (`persist.go:113-134`), whose bytes are outside `live_output_bytes` (`TERMINAL.md` §4.34), and the activity clock takes its baseline after the seed. A daemon restart re-reads the current state from a watcher that joins late, which is the same reading, not a new one. Pinned by Task 6 `TestASeededHostPublishesNoActivity`, `TestALateActivityWatcherGetsTheCurrentStateOnce`, Task 11 `TestDebouncerTheSameQuestionAfterARepaintIsNotNew`, Task 9 `TestScreen_SameStateScreenSignalIsANoOp`.
4. **The pane is closed while a question appears.** Expected: the needs-you alert fires anyway. Detection runs in the pty-host mirror, whose program watch the daemon opens at spawn and the reaper re-opens every 5 s through `IsAlive` (`runtime.go:139,336`), not in the renderer. Pinned by Task 6 `TestActivityIsPublishedWithNoAttachedClient` and Task 12 `TestObserverRaisesAQuestionForASessionNobodyIsViewing`.
5. **Two questions in quick succession, and a repaint of one question.** Expected: two alerts for two different questions, one alert for one question however often it repaints (a resize repaints Claude Code's dialog, `TERMINAL.md` §4.8). The debouncer needs an `active` that lasts 3 s to call it working, compares a whitespace-normalised identity of the question, and inserts a working reading between two different questions so the reducer resolves the first and alerts the second. Pinned by Task 11 `TestDebouncerTwoDifferentQuestionsAreTwoDecisions`, `TestDebouncerARepaintBurstDoesNotLeaveTheQuestion`, and the harness recording `claude-two-permissions` (a resize during the first question; Task 13 requires exactly one alert per asking interval).
6. **A question or summary containing a secret, an escape sequence or a control character.** Expected: the secret is masked (`[redacted]`) before the body is stored, before the mux `notifications` frame and before ntfy; masking runs before the 120-rune cut so a secret straddling the cut is masked whole; escape sequences, control runes and bidi overrides are gone; the ntfy message is valid UTF-8 and at most 4,096 bytes. Pinned by Task 17 `TestCleanMasksSecretsAndStripsEscapesAndControls`, `TestEnrichMasksAndCleansAgentTextBeforeItLeaves`, `TestEnrichMasksBeforeTruncating`, and Task 18 `TestAlertsMaskSecretsAndStripControlsInTheBody`, `TestAlertsCapTheBodyAtNtfysMessageLimit`.

---

## Design (each decision made; evidence in brackets)

### Phases and the tree

**Phases.** This plan has 21 tasks in two phases. **Phase A (Tasks 0-14)** ships on its own: screen detection in the pty-host, the merge rule, the observer, board/pane/phone status and needs-you alerts, and the measurement harness. **Phase B (Tasks 15-20)** adds the compact summaries and question text to notification bodies (masked and cleaned), sends them to ntfy as well, and fixes phone-alert coalescing; it depends on Phase A and changes `vt-core` again (both wasm artifacts are rebuilt twice, once per phase). Merge Phase A before starting Phase B (memory: land a milestone before planning the next).

**Tree this plan was written against:** `development` @ `611254eb3` ("docs(terminal): survey status marks, checked against the tree after the real-app run"). The code blocks below were written from the tree and have **not** been built in a scratch worktree; every step has a failing-test-first check, so a block that does not compile shows up at its own step. If an edit's quoted text is not found, stop and report the file and the quote.

### What exists today

- **Screen logic is TS-only.** `AgentActivityMonitor` (`packages/terminal/ts/core/src/agent-activity.ts:21-104`) reports `active | pollingForIdle | idle | prompting` from the live byte counter and `detectsHighConfidenceInputPattern(cursorLine)` (`input-patterns.ts:18-20`); `cursorLineText` (`agent-activity.ts:106-124`) builds the cursor line from a snapshot; `compactLines`/`capLines` are in `compact-output.ts:13-71`. `vt-core` only counts live bytes (`crates/vt-core/src/agent.rs:158-160`, `lib.rs:339-343`). Operator consumes none of it (`TERMINAL.md` §4.34; no use in `frontend/src`).
- **The mirror sees everything, always.** `deliver` feeds each PTY batch into the `vtwasm.Parser` after the broadcast and publishes program events (`host.go:623-653`); the daemon opens one watch connection per session at spawn and keeps it alive through the reaper's `IsAlive` probe (`runtime.go:139,336`, `program_watch.go:40-117`) and fans events to listeners (`program_watch.go:119-173`); the only listener is the mux `programs` channel (`internal/terminal/programs.go:5-40`). There is no parser clock while the PTY is quiet: the pump's timer is armed only while output is pending (`host.go:481-566`).
- **Status is derived from `activity_state`** (`domain/activity.go:20-26`) at read time (`service/session/status.go:27`): `active`→working, `waiting_input`/`blocked`→needs_input. Hooks post `sessions/{id}/activity` (`cli/hooks.go:284-352`, `controllers/sessions.go:260,1928-1979`) into `lifecycle.Manager.ApplyActivitySignal` (`lifecycle/manager.go:547`), which fences by launch and revision (`:623-635`), applies tool/blocked precedence (`:926-1060`), writes on change (`:716`), and raises a needs-input notification on entering the family, turn-finished on active→idle, agent-exited on exit (`:737-760`).
- **A screen check on hooks already exists, slowly.** `observe/activity/observer.go` polls every 30 s and, for adapters that implement `ports.TerminalActivityDetector` (Codex `codex/terminal_activity.go:13-37`, Muse), corrects a session that has been `active` for 2 minutes (`observer.go:15-17,103-150`). Claude Code has no detector.
- **Agents.** Claude Code and Codex both post hooks, including `PermissionRequest` (`claudecode/hooks.go:38-46`, `codex/hooks.go:71-74`); aider, pi and auggie post none (subagent survey of `adapters/agent/*`, `activitydispatch/dispatch.go:32-56`). Claude Code's and Codex's dialogs are already read from the screen for answering them (`claudecode/dialog.go:14-45,91-103`, `codex/dialog.go:10-34`, `terminalui/menu.go:12-44`).
- **Notifications** are one row per open (session, type) (`migrations/0117_notification_alerts.sql:42`, `notify/manager.go:76`); bodies come from `notify/enrich.go:61-97` (needs-input: agent-report reason or a fixed sentence; turn-finished: the hook's `latestAssistantUpdate`); the phone gets them through the mux `notifications` channel (`internal/terminal/notifications.go:28-67`) and ntfy, which sends the title and one word and coalesces per session for 10 s (`push/alerts.go:17,150-181,197-209`).
- **Recordings** have no timestamps: `record-pty.py` and the pty-host recorder write `recording` + `size.json` only (`bench/agent-session/record-pty.py:25-82`, `ptyhost/record.go:10-73`). The three fixtures are Claude Code (`claude-long-50k`, `claude-markdown-reply`, `claude-spinner-10s`); there is no Codex recording and none with a question.

### Where detection runs: the pty-host mirror

It is the only place that sees every byte of every session from spawn whether or not a pane, window or phone is attached (`host.go:623-653`; watch opened at `runtime.go:139`). The renderer's monitor runs only while a pane is mounted. The daemon's own 30 s poller re-renders the screen on a timer and would need a much shorter tick to be quick. So: **vt-core gets the classifier; the pty-host runs it on a 250 ms clock and on every feed; the daemon observer adds agent knowledge, debounce and the merge.**

### vt-core owns the classifier (shared by the renderer and the mirror)

- `TerminalCore::cursor_line_text()` — the cursor's row on the active screen, cells from column 0 to the later of the last non-space cell and the cursor column, wide-character continuation cells skipped (the same text `cursorLineText` produces, `agent-activity.ts:106-124`).
- `TerminalCore::cursor_line_prompts()` — the line editor does not own the line (`agent-activity.ts:67`, `TERMINAL.md` §4.34) and the cursor line matches VS Code's nine high-confidence patterns, ported to `regex-automata` (`activity/input_patterns.rs`).
- `TerminalCore::agent_activity(quiet_ms: Option<u64>) -> AgentActivity` — the same four states and thresholds as `agent-activity.ts:10-14,66-71`: quiet < 500 ms `Active`; else `Prompting` when the cursor line prompts; else `PollingForIdle` below 1,500 ms, `Idle` from 1,500 ms. The caller owns the clock (when the live byte counter last moved), exactly as the TS monitor does (`agent-activity.ts:48-55`): the counter's replay/OSC accounting (`live_output.rs:1-30`) stays untouched.
- The TS monitor keeps its timer and listeners and asks the core `prompting()`; `input-patterns.ts` becomes a wrapper over the wasm export; `cursorLineText` is removed (its padding test moves to Rust).
- Phase B: `compact_lines`, `cap_lines`, `is_spinner_line` port `compact-output.ts` to `activity/compact.rs`, and `TerminalCore::tail_output(rows, compact, max_lines)` returns the compact logical lines of the newest rows; the TS `compactLines`/`capLines`/`isSpinnerLine` become wrappers.

### The pty-host publishes transitions, not a stream

`vtwasm.ActivityClock.Step(parser, now, pokedAt)` reads `LiveOutputBytes`; a change more than 250 ms after the last client keystroke or resize (`inputEchoWindow`) restarts the quiet time (typing echo and a resize repaint are not the agent working — VS Code tracks the same, `_userInputtedSinceIdleDetected`, survey §6.9); `AgentActivity(quiet)` gives the state; `PollingForIdle` is never published; the first publish waits for the first counted output. On a change the host sends `MsgProgramEvent{kind:"activity", activity, seq, atMs, tail (40 rows), cursorLine}` — and in Phase B `summary` — only to watchers that asked (`MsgWatchReq` payload `{"activity":true}`), so the renderer's programs channel and the existing watcher tests never see it. A watcher that joins late gets the last activity frame. Respawn and seeding re-baseline the clock.

### The daemon observer reads, debounces, re-asserts

`observe/screen` subscribes through `ports.TerminalProgramReader`, maps the handle to a session, and:

1. **Classifies** (`Classify`): `active` → working; `idle`/`prompting` → the adapter's `ports.TerminalQuestionReader` first (Claude Code: its dialog reader minus the model picker; Codex: the last numbered `›` menu, no `esc to interrupt`, not the model picker) → question; then `ports.TerminalActivityDetector` (Codex's existing one; a new Claude Code one: the `❯` composer between rule lines and no `esc to interrupt`, evidence `claude-markdown-reply` and `claude-spinner-10s` final screens below) → settled (`idle`) or waiting (`waiting_input`), `!ok` → no reading; generic `prompting` counts as a question only for an agent with no question reader; an agent with no detector → settled after 60 s.
   Final screens (rendered with the built `ts/core` from the committed fixtures on 2026-09-27): `claude-markdown-reply` ends `✻ Baked for 11s · done 6:13 PM` / `────` / `❯` / `────` / `⏵⏵ auto mode on (shift+tab to cycle) · ← for agents`; `claude-spinner-10s` ends `✽ Flambéing… (13s · still thinking with high effort)` / … / `❯` / `────` / `⏵⏵ auto mode on (shift+tab to cycle) · esc to interrupt · ← for agents`.
2. **Debounces** (`Debouncer`): working must hold 3 s (`ScreenActiveConfirm`), a question 1 s (`ScreenQuestionConfirm`), a detector-confirmed settle 2 s (`ScreenSettleConfirm`), an unconfirmed settle 60 s (`ScreenQuietSettle`); a reading equal to the last emitted one (same reading and identity) cancels whatever is pending; two different questions with output between them emit working, then the new question.
3. **Applies** through `ApplyActivitySignal` with `ScreenReading`, `ScreenIdentity`, `ScreenText`, `ExpectedUpdatedAt` and `LaunchID`, skipping when the stored state already matches.
4. **Re-asserts** the last confirmed reading every 5 s while the stored state disagrees, so a refusal because a hook was fresh turns into a correction once the hook is stale.

### The merge rule (domain, pure) and where it runs (lifecycle)

`domain.MergeScreenReading(current, reading, lastHookAt, now)`: the screen never changes `exited`; a reading equal to the current state is a no-op; **while a hook reported within `HookFreshWindow = 30 s`, the screen may only escalate `active` to `blocked` on a question** (a question drawn after the hook's `active` is newer information, not a contradiction — Open Decision 1) and never demotes; **once the hook is stale, or for an agent that never posts hooks, the screen reading wins**. `lastHookAt` is stamped in `ApplyActivitySignal` for every valid non-screen signal that passes the launch and revision fences. Screen signals never set `FirstSignalAt`, so the `no_signal` diagnostic for broken hooks survives (`service/session/status.go:61`). A screen `working`/`settled`/`waiting` counts as proof the dialog closed in the blocked-precedence branch (`manager.go:1025-1041`), like `EventDialogAbsent`. One alert per question: a needs-input intent is skipped when the screen question's identity equals the last one alerted for the session within 2 minutes; the memory clears when the session goes idle.

### Consumers

- **Board (desktop):** unchanged components; `status` follows `activity_state` through CDC; an agent without hooks now leaves `idle` for working/needs_input/idle. Needs-you cards go to the needs-you column by the existing `attentionZone` (`frontend/src/renderer/lib/session-presentation.ts:210-235`).
- **Desktop pane:** nothing new; the activity kind is filtered out of the mux `programs` channel so `ProgramRuntime.tsx` never sees it.
- **Phone:** card status via CDC patches; alerts via the existing needs-input/turn-finished notifications on the mux `notifications` channel and ntfy; Phase B bodies carry the question and the summary, masked and cleaned by `redact.Clean`, on the mux channel, in the in-app list and in the ntfy message (capped at 4,096 bytes).
- **OSC 777 agent-state (later):** out of scope. The design does not block it: an in-band `agent-state` event is a fourth input to the same observer (a `ScreenReading` from `vt_take_agent_events` in the same watch frame), and `MergeScreenReading` already ranks it below fresh hooks.

## File Structure

| File | Task | Responsibility |
|---|---|---|
| `packages/terminal/bench/agent-session/record-pty.py` | 1 | also write `timing.json` |
| `packages/terminal/bench/agent-session/record-scenario.py` (new) | 1 | drive a real agent through a scenario; write recording, size, timing, truth |
| `packages/terminal/bench/agent-session/fixtures.mjs`, `fixtures.test.mjs` | 1 | `listSignals`/`loadSignal`, layout checks |
| `backend/internal/adapters/runtime/ptyhost/record.go`, `record_test.go` | 1 | `<id>.timing.jsonl` beside the recording |
| `packages/terminal/bench/agent-session/signals/scenarios/*.json` (new) | 2 | the seven scenarios |
| `packages/terminal/bench/agent-session/signals/<name>/{recording,size.json,timing.json,truth.json}` (new) | 2 | the recordings |
| `packages/terminal/crates/vt-core/src/activity.rs`, `activity/input_patterns.rs`, `activity/LICENSE-VSCODE-MIT`, `activity/VSCODE-INPUT-PATTERNS-ATTRIBUTION.md` (new/moved) | 3 | classifier |
| `packages/terminal/crates/vt-core/src/lib.rs` | 3 | `pub mod activity;` |
| `packages/terminal/crates/vt-core/tests/agent_activity.rs` (new) | 3 | behaviour tests |
| `packages/terminal/crates/vt-wasm/src/agent.rs` (new), `src/lib.rs`, `tests/agent_exports.rs` (new) | 4, 15 | wasm exports |
| `packages/terminal/ts/core/src/{agent-activity.ts,input-patterns.ts,terminal-core.ts,index-browser.ts,agent-activity.test.ts}` | 4 | TS monitor asks the core |
| `packages/terminal/crates/vt-host/src/activity.rs` (new), `src/lib.rs`, `src/program.rs` | 5, 16 | C-ABI exports |
| `backend/internal/adapters/runtime/ptyhost/vtwasm/activity.go`, `activity_test.go` (new), `assets/vt_host.wasm` | 5, 16 | Go wrapper, `ActivityClock` |
| `backend/internal/adapters/runtime/ptyhost/activity.go`, `activity_test.go` (new), `host.go`, `program.go`, `proto.go` | 6, 16 | publisher |
| `backend/internal/ports/terminal_program.go`, `backend/internal/adapters/runtime/ptyhost/program_watch.go`, `program_watch_test.go`, `backend/internal/terminal/programs.go`, `programs_test.go` | 7 | event plumbing |
| `backend/internal/domain/screen_reading.go`, `screen_reading_test.go` (new) | 8 | merge rule |
| `backend/internal/ports/runtime_observations.go`, `backend/internal/lifecycle/manager.go`, `screen_signal_test.go` (new) | 9 | reducer |
| `backend/internal/ports/agent.go`, `adapters/agent/terminalui/question.go` (new), `claudecode/terminal_activity.go` (new), `claudecode/question.go` (new), `codex/question.go` (new), tests, `observe/activity/observer_test.go` | 10 | agent readers |
| `backend/internal/observe/screen/{classify.go,debounce.go}` + tests (new) | 11 | reading + debounce |
| `backend/internal/observe/screen/observer.go`, `observer_test.go` (new), `backend/internal/daemon/lifecycle_wiring.go` | 12 | wiring |
| `backend/internal/observe/screen/recordings_test.go` (new) | 13 | measurement harness |
| `TERMINAL.md`, `packages/terminal/CHANGELOG.md`, survey | 14, 20 | docs |
| `packages/terminal/crates/vt-core/src/activity/compact.rs` (new), `ts/core/src/compact-output.ts`, tests | 15 | compact port |
| `backend/internal/ports/agent.go`, `claudecode/summary.go`, `codex/summary.go`, `terminalui/summary.go` (new), `observe/screen/classify.go`, `ports/notifications.go`, `lifecycle/manager.go`, `notify/enrich.go`, tests | 17 | bodies |
| `backend/internal/redact/clean.go`, `clean_test.go` (new) | 17 | strip escapes/controls, then mask secrets |
| `backend/internal/push/alerts.go`, `alerts_test.go`, `ntfy.go` | 18 | masked body in the ntfy message, 4,096-byte cap |
| `backend/internal/push/alerts.go`, `alerts_test.go` | 19 | coalescing |
| `docs/superpowers/specs/2026-09-23-agent-alerts-design.md` (D6) | 20 | record that D6 is superseded |

---
# Phase A — screen detection, merge, board and needs-you alerts

### Task 0: Worktree, toolchains, baselines

**Files:** none committed.

**Interfaces:** none.

- [ ] **Step 1: Worktree**

```bash
cd /Users/omaraly/development/AI/Operator && git fetch origin
git worktree add ../Operator-wave1-signals -b terminal/wave1-agent-signals development
export REPO=/Users/omaraly/development/AI/Operator-wave1-signals
cd "$REPO" && git log --oneline -1
```
Expected: `611254eb3 docs(terminal): survey status marks, …` or a later commit on `development`.

- [ ] **Step 2: Toolchains**

```bash
cd "$REPO/packages/terminal" && rustup show active-toolchain && rustup target list --installed | grep wasm32
wasm-bindgen --version
export GOTOOLCHAIN=auto && cd "$REPO/backend" && go version
cd "$REPO/packages/terminal" && npm ci --no-audit --no-fund && cd "$REPO/frontend" && npm ci --no-audit --no-fund
codex --version && env $(env | awk -F= '/^CLAUDE/ {printf "-u %s ", $1}') claude --version
```
Expected: `1.96.0-…`, `wasm32-unknown-unknown`, `wasm-bindgen 0.2.127` (`scripts/build-wasm.mjs` refuses any other), a Go ≥ `go1.25`, `codex-cli 0.157.1` (or later; write the version down), `2.1.280 (Claude Code)` (or later; write it down).

- [ ] **Step 3: Baselines of the unmodified tree** (record every count)

```bash
cd "$REPO/packages/terminal" && cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
npm run build:wasm -- --force && npm run build:ts
for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  "); done
npm run check:boundaries 2>&1 | tail -1
node --test ./bench/agent-session/fixtures.test.mjs 2>&1 | tail -3
npm run bench:agent:gate 2>&1 | tail -1
cd "$REPO/backend" && go test ./... 2>&1 | grep -v "^ok" | head -20
cd "$REPO/frontend" && npm run typecheck 2>&1 | tail -1 && npm run test 2>&1 | tail -3
```
Expected: no FAILED line; five `Tests  N passed` lines; `boundary check passed`; fixtures tests pass; `PASS agent-session gate`; Go prints only `TestProcessEnvironmentLetsOverridesWin` if anything; frontend typecheck and tests pass. Anything else failing is pre-existing: write it down and do not fix it.

---

### Task 1: Timed recordings and a scenario driver

**Files:**
- Modify: `packages/terminal/bench/agent-session/record-pty.py:25-82` (timing), `packages/terminal/bench/agent-session/fixtures.mjs:1-37` (signals loader), `packages/terminal/bench/agent-session/fixtures.test.mjs:1-50` (append a test), `backend/internal/adapters/runtime/ptyhost/record.go:17-104` (timing file), `backend/internal/adapters/runtime/ptyhost/record_test.go` (append a test)
- Create: `packages/terminal/bench/agent-session/record-scenario.py`, `packages/terminal/bench/agent-session/signals/.gitkeep`

**Interfaces:**
- Produces: `timing.json` = JSON array of `[offset, ms]` pairs, one per PTY read, `offset` the byte offset where that read starts, `ms` milliseconds since the recording started; strictly increasing offsets, non-decreasing `ms`, first pair `[0, t0]`.
- Produces: `truth.json` = `{ "harness": "claude-code" | "codex" | "", "agentVersion": string, "command": [string], "intervals": [{ "from": ms, "to": ms, "state": "working" | "asking" | "settled", "question"?: string }], "inputs": [ms] }` — intervals contiguous and covering `[0, end]`; `inputs` every time the driver wrote to the PTY or resized it.
- Produces (JS): `SIGNALS_DIR`, `listSignals(): string[]`, `loadSignal(name): Promise<{ name, recording: Uint8Array, sizes, timing: number[][], truth }>` in `fixtures.mjs`.
- Produces (Go, pty-host recorder): `<dir>/<sessionID>.timing.jsonl`, one `[offset,ms]` line per batch.

- [ ] **Step 1: Failing JS test for the signals layout**

Append to `packages/terminal/bench/agent-session/fixtures.test.mjs`:

```js
import { SIGNALS_DIR, listSignals, loadSignal } from "./fixtures.mjs";

test("every signal recording has timing and truth that cover it", async () => {
	assert.ok(existsSync(SIGNALS_DIR), "signals directory exists");
	for (const name of listSignals()) {
		const signal = await loadSignal(name);
		assert.ok(signal.recording.length > 0, `${name}: empty recording`);
		assert.equal(signal.sizes[0].offset, 0, `${name}: first size at 0`);
		assert.ok(signal.timing.length > 0, `${name}: no timing`);
		assert.equal(signal.timing[0][0], 0, `${name}: first read at offset 0`);
		for (let index = 1; index < signal.timing.length; index += 1) {
			assert.ok(signal.timing[index][0] > signal.timing[index - 1][0], `${name}: offsets increase at ${index}`);
			assert.ok(signal.timing[index][1] >= signal.timing[index - 1][1], `${name}: time never goes back at ${index}`);
			assert.ok(signal.timing[index][0] < signal.recording.length, `${name}: offset past the recording`);
		}
		const intervals = signal.truth.intervals;
		assert.ok(intervals.length > 0, `${name}: no truth intervals`);
		assert.equal(intervals[0].from, 0, `${name}: truth starts at 0`);
		for (let index = 0; index < intervals.length; index += 1) {
			assert.ok(["working", "asking", "settled"].includes(intervals[index].state), `${name}: state ${intervals[index].state}`);
			assert.ok(intervals[index].to > intervals[index].from, `${name}: empty interval ${index}`);
			if (index > 0) assert.equal(intervals[index].from, intervals[index - 1].to, `${name}: gap before interval ${index}`);
		}
		assert.ok(["claude-code", "codex", ""].includes(signal.truth.harness), `${name}: harness`);
		assert.ok(!listFixtures().includes(name), `${name} must not also be a fixture`);
	}
});
```

- [ ] **Step 2: Run it, expect failure**

```bash
cd "$REPO/packages/terminal" && node --test ./bench/agent-session/fixtures.test.mjs 2>&1 | tail -5
```
Expected: a `SyntaxError` / `does not provide an export named 'SIGNALS_DIR'`.

- [ ] **Step 3: Loader**

Append to `packages/terminal/bench/agent-session/fixtures.mjs`:

```js
export const SIGNALS_DIR = fileURLToPath(new URL("./signals/", import.meta.url));

export function listSignals() {
	return readdirSync(SIGNALS_DIR, { withFileTypes: true })
		.filter((entry) => entry.isDirectory() && entry.name !== "scenarios")
		.map((entry) => entry.name)
		.sort();
}

export async function loadSignal(name) {
	const dir = join(SIGNALS_DIR, name);
	const recording = new Uint8Array(await readFile(join(dir, "recording")));
	const sizes = JSON.parse(await readFile(join(dir, "size.json"), "utf8"));
	const timing = JSON.parse(await readFile(join(dir, "timing.json"), "utf8"));
	const truth = JSON.parse(await readFile(join(dir, "truth.json"), "utf8"));
	if (!Array.isArray(sizes) || !Array.isArray(timing)) throw new Error(`${name}: size.json and timing.json must be JSON arrays`);
	return { name, recording, sizes, timing, truth };
}
```

Create the empty directory marker:

```bash
mkdir -p "$REPO/packages/terminal/bench/agent-session/signals/scenarios" && : > "$REPO/packages/terminal/bench/agent-session/signals/.gitkeep"
```

- [ ] **Step 4: Timing in `record-pty.py`**

In `packages/terminal/bench/agent-session/record-pty.py`, add `import time` to the imports, and replace

```python
    recording = open(os.path.join(args.out, "recording"), "wb")
    sizes = [{"offset": 0, "cols": args.cols, "rows": args.rows}]
    written = 0
```
with
```python
    recording = open(os.path.join(args.out, "recording"), "wb")
    sizes = [{"offset": 0, "cols": args.cols, "rows": args.rows}]
    timing = []
    started = time.monotonic()
    written = 0
```
replace
```python
                recording.write(data)
                recording.flush()
                written += len(data)
```
with
```python
                timing.append([written, int((time.monotonic() - started) * 1000)])
                recording.write(data)
                recording.flush()
                written += len(data)
```
and replace
```python
        recording.close()
        write_sizes()
```
with
```python
        recording.close()
        write_sizes()
        with open(os.path.join(args.out, "timing.json"), "w") as handle:
            json.dump(timing, handle)
```
(`written` is read inside `on_winch` as a closure over the enclosing variable; the existing code already does that, `record-pty.py:44-55`.)

- [ ] **Step 5: The scenario driver**

Create `packages/terminal/bench/agent-session/record-scenario.py`:

```python
#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import pty
import re
import select
import signal
import struct
import sys
import termios
import time

ESCAPE = re.compile(rb"\x1b\[[0-9;?>=]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][0-9A-Za-z]|\x1b[=>78DEHMNOZc]")
FORWARD = re.compile(rb"\x1b\[([0-9]*)C")


def plain(data):
    spaced = FORWARD.sub(lambda match: b" " * int(match.group(1) or b"1"), data)
    return ESCAPE.sub(b"", spaced).replace(b"\r", b"\n").decode("utf-8", "replace")


def set_winsize(fd, cols, rows):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


class Session:
    def __init__(self, command, cols, rows):
        self.started = time.monotonic()
        self.pid, self.master = pty.fork()
        if self.pid == 0:
            os.execvp(command[0], command)
        set_winsize(self.master, cols, rows)
        self.recording = bytearray()
        self.timing = []
        self.sizes = [{"offset": 0, "cols": cols, "rows": rows}]
        self.inputs = []
        self.intervals = []
        self.current = {"from": 0, "state": "working"}
        self.last_output_ms = 0
        self.closed = False

    def now(self):
        return int((time.monotonic() - self.started) * 1000)

    def pump(self, seconds):
        deadline = time.monotonic() + seconds
        while not self.closed:
            left = deadline - time.monotonic()
            if left <= 0:
                return
            ready, _, _ = select.select([self.master], [], [], left)
            if not ready:
                return
            try:
                data = os.read(self.master, 65536)
            except OSError:
                data = b""
            if not data:
                self.closed = True
                return
            at = self.now()
            self.timing.append([len(self.recording), at])
            self.recording.extend(data)
            self.last_output_ms = at
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()

    def write(self, text):
        os.write(self.master, text.encode("utf-8"))
        self.inputs.append(self.now())

    def begin(self, at, state, question=None):
        self.current["to"] = at
        if self.current["to"] > self.current["from"]:
            self.intervals.append(self.current)
        self.current = {"from": at, "state": state}
        if question:
            self.current["question"] = question

    def expect(self, pattern, raw, timeout):
        regex = re.compile(pattern.encode("utf-8") if raw else pattern)
        since = len(self.recording)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and not self.closed:
            self.pump(0.05)
            window = bytes(self.recording[since:])
            if (regex.search(window) if raw else regex.search(plain(window))):
                return self.now()
        tail = plain(bytes(self.recording[-4000:]))
        raise SystemExit(f"expect {pattern!r} timed out after {timeout}s; screen text:\n{tail}")

    def expect_quiet(self, seconds, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and not self.closed:
            self.pump(0.25)
            if self.now() - self.last_output_ms >= seconds * 1000:
                return self.last_output_ms
        raise SystemExit(f"expect_quiet {seconds}s timed out after {timeout}s")

    def resize(self, cols, rows):
        set_winsize(self.master, cols, rows)
        self.sizes.append({"offset": len(self.recording), "cols": cols, "rows": rows})
        self.inputs.append(self.now())
        os.kill(self.pid, signal.SIGWINCH)


def run(session, steps):
    for step in steps:
        kind = step["type"]
        if kind == "text":
            session.write(step["text"])
            session.pump(step.get("settle", 0.6))
        elif kind == "submit":
            session.write("\r")
            session.begin(session.now(), "working")
            session.pump(0.2)
        elif kind == "answer":
            session.write(step["keys"])
            session.begin(session.now(), "working")
            session.pump(0.2)
        elif kind == "expect":
            at = session.expect(step["pattern"], step.get("raw", False), step.get("timeout", 300))
            session.begin(at, step["state"], step.get("question"))
        elif kind == "expect_quiet":
            at = session.expect_quiet(step["seconds"], step.get("timeout", 900))
            session.begin(at, step["state"])
        elif kind == "wait":
            session.pump(step["seconds"])
        elif kind == "resize":
            session.resize(step["cols"], step["rows"])
            session.pump(0.2)
        else:
            raise SystemExit(f"unknown step type {kind!r}")


def main():
    parser = argparse.ArgumentParser(description="record an agent scenario with timing and ground truth")
    parser.add_argument("--out", required=True)
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--cols", type=int, default=120)
    parser.add_argument("--rows", type=int, default=40)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = [part for part in args.command if part != "--"]
    if not command:
        parser.error("command is required")
    with open(args.scenario) as handle:
        scenario = json.load(handle)
    session = Session(command, args.cols, args.rows)
    try:
        run(session, scenario["steps"])
        session.pump(scenario.get("tail_seconds", 2))
    finally:
        end = max(session.now(), session.last_output_ms + 1)
        session.begin(end, session.current["state"])
        if not session.closed:
            os.kill(session.pid, signal.SIGHUP)
        try:
            os.waitpid(session.pid, 0)
        except ChildProcessError:
            pass
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "recording"), "wb") as handle:
        handle.write(bytes(session.recording))
    with open(os.path.join(args.out, "size.json"), "w") as handle:
        json.dump(session.sizes, handle)
    with open(os.path.join(args.out, "timing.json"), "w") as handle:
        json.dump(session.timing, handle)
    truth = {
        "harness": scenario["harness"],
        "agentVersion": scenario.get("agentVersion", ""),
        "command": command,
        "intervals": session.intervals,
        "inputs": session.inputs,
    }
    with open(os.path.join(args.out, "truth.json"), "w") as handle:
        json.dump(truth, handle, indent=1, ensure_ascii=False)
        handle.write("\n")


if __name__ == "__main__":
    main()
```

Notes for the implementer (not code): `expect` searches only output received after the step began, so a question that is still in scrollback does not match the next `expect`; a timeout prints the stripped screen and exits non-zero, and the four files are written only after a clean run (the `finally` block only stops the child), so a wrong pattern never produces silent truth.

- [ ] **Step 6: Driver smoke test (throwaway, not committed)**

```bash
SCRATCH=/private/tmp/claude-501/-Users-omaraly-development-AI-Operator/82bbcd8b-e64f-470c-92e3-6c4278144a31/scratchpad
cat > "$SCRATCH/smoke.json" <<'EOF'
{"harness": "", "steps": [
 {"type": "expect", "pattern": "ready", "state": "settled", "timeout": 10},
 {"type": "text", "text": "y"},
 {"type": "submit"},
 {"type": "expect", "pattern": "got y", "state": "settled", "timeout": 10}
]}
EOF
python3 "$REPO/packages/terminal/bench/agent-session/record-scenario.py" --out "$SCRATCH/smoke" --scenario "$SCRATCH/smoke.json" -- bash --noprofile --norc -c 'echo ready; read a; echo "got $a"; sleep 1' > /dev/null
python3 -c "import json;t=json.load(open('$SCRATCH/smoke/truth.json'));print([i['state'] for i in t['intervals']], len(t['inputs']))"
```
Expected: `['working', 'settled', 'working', 'settled'] 2` (boot, at the `ready` prompt, after Enter, after `got y`).

- [ ] **Step 7: Failing Go test for the pty-host recorder's timing**

Append to `backend/internal/adapters/runtime/ptyhost/record_test.go`:

```go
func TestRecorderWritesOneTimingLinePerBatch(t *testing.T) {
	dir := t.TempDir()
	r, err := openRecorder(dir, "sess-timing", 80, 24)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	r.write([]byte("first"))
	r.write([]byte("second!"))
	if err := r.close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	raw, err := os.ReadFile(filepath.Join(dir, "sess-timing.timing.jsonl"))
	if err != nil {
		t.Fatalf("read timing: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
	if len(lines) != 2 {
		t.Fatalf("timing lines = %q, want 2", lines)
	}
	var first, second [2]int64
	if err := json.Unmarshal([]byte(lines[0]), &first); err != nil {
		t.Fatalf("line 0: %v", err)
	}
	if err := json.Unmarshal([]byte(lines[1]), &second); err != nil {
		t.Fatalf("line 1: %v", err)
	}
	if first[0] != 0 || second[0] != 5 || second[1] < first[1] {
		t.Fatalf("timing = %v %v, want offsets 0 and 5 with time not going back", first, second)
	}
}
```
(Add `encoding/json`, `os`, `path/filepath`, `strings` to the test file's imports if missing.)

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ -run TestRecorderWritesOneTimingLinePerBatch 2>&1 | tail -3
```
Expected: FAIL, `read timing: open …sess-timing.timing.jsonl: no such file or directory`.

- [ ] **Step 8: Recorder timing**

In `backend/internal/adapters/runtime/ptyhost/record.go`: add `"fmt"` and `"time"` to the imports; add two fields to `recorder` after `recording *os.File`:

```go
	timing    *os.File
	started   time.Time
```
In `openRecorder`, after the `recording` file opens and before `r := &recorder{`:

```go
	timing, err := os.OpenFile(filepath.Join(dir, sessionID+".timing.jsonl"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		_ = recording.Close()
		return nil, err
	}
```
and set `timing: timing, started: time.Now(),` in the literal. In `write`, before `n, err := r.recording.Write(batch)`:

```go
	if _, err := fmt.Fprintf(r.timing, "[%d,%d]\n", r.written, time.Since(r.started).Milliseconds()); err != nil {
		r.err = err
		return
	}
```
In `close`, before `if err := r.recording.Close()`:

```go
	if err := r.timing.Close(); err != nil && r.err == nil {
		r.err = err
	}
```

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ -run 'TestRecorder' 2>&1 | tail -3
cd "$REPO/packages/terminal" && node --test ./bench/agent-session/fixtures.test.mjs 2>&1 | tail -3
```
Expected: `ok`; the JS suite passes (no signal recordings yet, the loop is empty).

Update `RUN_APP_COMMANDS.md:69-72` (the `OPERATOR_PTY_RECORD` paragraph): add one sentence, "It also writes `<id>.timing.jsonl` (`[offset,ms]` per batch); `jq -cs . < <id>.timing.jsonl > timing.json` gives the fixture layout."

- [ ] **Step 9: Commit**

```bash
cd "$REPO" && git add packages/terminal/bench/agent-session/record-pty.py packages/terminal/bench/agent-session/record-scenario.py packages/terminal/bench/agent-session/fixtures.mjs packages/terminal/bench/agent-session/fixtures.test.mjs packages/terminal/bench/agent-session/signals/.gitkeep backend/internal/adapters/runtime/ptyhost/record.go backend/internal/adapters/runtime/ptyhost/record_test.go RUN_APP_COMMANDS.md
git commit -m "test(terminal): timed recordings and a scenario driver with ground truth

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Record real Claude Code, Codex and shell sessions

**Files:**
- Create: `packages/terminal/bench/agent-session/signals/scenarios/{claude-permission,claude-question,claude-two-permissions,claude-think,codex-approval,codex-think,shell-pause}.json`, and one directory per scenario under `packages/terminal/bench/agent-session/signals/` holding `recording`, `size.json`, `timing.json`, `truth.json`.

**Interfaces:**
- Consumes: `record-scenario.py` (Task 1).
- Produces: seven signal recordings; `truth.json.harness` is `claude-code` for the four Claude ones, `codex` for the two Codex ones, `""` for `shell-pause`.

This task drives real agents and spends real tokens. Run each agent in a throwaway git repository under the scratchpad, never in the Operator checkout. Claude Code runs with `--permission-mode default` so its permission dialogs appear (the committed fixtures show `⏵⏵ auto mode on`, `claude-spinner-10s` final screen, which skips them).

- [ ] **Step 1: Scratch repositories**

```bash
SCRATCH=/private/tmp/claude-501/-Users-omaraly-development-AI-Operator/82bbcd8b-e64f-470c-92e3-6c4278144a31/scratchpad
for d in claude codex; do rm -rf "$SCRATCH/signal-$d" && mkdir -p "$SCRATCH/signal-$d" && (cd "$SCRATCH/signal-$d" && git init -q && echo "# demo" > README.md && git add README.md && git -c user.email=demo@example.invalid -c user.name=demo commit -qm init); done
codex --help | grep -E -- "--ask-for-approval|--sandbox|-c, --config" 
```
Expected: the help lines for `-a/--ask-for-approval`, `-s/--sandbox` and `-c/--config`. If a flag is named differently in this Codex version, use the printed name in Step 3 and write it into the scenario's `truth.json` `command` (the driver records the command line verbatim).

- [ ] **Step 2: Scenario files**

Create each file under `packages/terminal/bench/agent-session/signals/scenarios/`:

`claude-permission.json`
```json
{"harness": "claude-code", "agentVersion": "2.1.280", "steps": [
 {"type": "expect", "pattern": "\\? for shortcuts", "state": "settled", "timeout": 90},
 {"type": "text", "text": "Use the Bash tool to run `ls -la` in this directory, then tell me how many entries it printed."},
 {"type": "submit"},
 {"type": "expect", "pattern": "Do you want to proceed\\?", "state": "asking", "question": "Bash ls -la", "timeout": 180},
 {"type": "wait", "seconds": 6},
 {"type": "answer", "keys": "\r"},
 {"type": "expect_quiet", "seconds": 8, "state": "settled", "timeout": 300}
]}
```

`claude-question.json`
```json
{"harness": "claude-code", "agentVersion": "2.1.280", "steps": [
 {"type": "expect", "pattern": "\\? for shortcuts", "state": "settled", "timeout": 90},
 {"type": "text", "text": "Use the AskUserQuestion tool to ask me whether I prefer tabs or spaces, then reply with only my answer."},
 {"type": "submit"},
 {"type": "expect", "pattern": "Enter to select", "state": "asking", "question": "tabs or spaces", "timeout": 180},
 {"type": "wait", "seconds": 6},
 {"type": "answer", "keys": "\r"},
 {"type": "expect_quiet", "seconds": 8, "state": "settled", "timeout": 300}
]}
```

`claude-two-permissions.json`
```json
{"harness": "claude-code", "agentVersion": "2.1.280", "steps": [
 {"type": "expect", "pattern": "\\? for shortcuts", "state": "settled", "timeout": 90},
 {"type": "text", "text": "Run these as two separate Bash tool calls, one after the other: `echo first-call` and then `echo second-call`. Do not combine them."},
 {"type": "submit"},
 {"type": "expect", "pattern": "Do you want to proceed\\?", "state": "asking", "question": "echo first-call", "timeout": 180},
 {"type": "wait", "seconds": 3},
 {"type": "resize", "cols": 100, "rows": 40},
 {"type": "wait", "seconds": 4},
 {"type": "answer", "keys": "\r"},
 {"type": "expect", "pattern": "Do you want to proceed\\?", "state": "asking", "question": "echo second-call", "timeout": 180},
 {"type": "wait", "seconds": 5},
 {"type": "answer", "keys": "\r"},
 {"type": "expect_quiet", "seconds": 8, "state": "settled", "timeout": 300}
]}
```

`claude-think.json` (the prompt of the committed `claude-spinner-10s`, left to run to the end: a long thinking turn with only the spinner moving)
```json
{"harness": "claude-code", "agentVersion": "2.1.280", "steps": [
 {"type": "expect", "pattern": "\\? for shortcuts", "state": "settled", "timeout": 90},
 {"type": "text", "text": "Do all of the following entirely in your head, without any tools: multiply 8763541 by 9236741, then multiply 5647213 by 3298471. For each one, compute it two different ways and confirm both ways agree. When both are verified, reply with only the two final products, one per line."},
 {"type": "submit"},
 {"type": "expect_quiet", "seconds": 8, "state": "settled", "timeout": 900}
]}
```

`codex-approval.json`
```json
{"harness": "codex", "agentVersion": "0.157.1", "steps": [
 {"type": "expect_quiet", "seconds": 5, "state": "settled", "timeout": 90},
 {"type": "text", "text": "Run the shell command `touch approved.txt` and then tell me it is done."},
 {"type": "submit"},
 {"type": "expect", "pattern": "(?i)(yes, proceed|approve|allow command|run this command)", "state": "asking", "question": "touch approved.txt", "timeout": 180},
 {"type": "wait", "seconds": 6},
 {"type": "answer", "keys": "\r"},
 {"type": "expect_quiet", "seconds": 8, "state": "settled", "timeout": 300}
]}
```

`codex-think.json`
```json
{"harness": "codex", "agentVersion": "0.157.1", "steps": [
 {"type": "expect_quiet", "seconds": 5, "state": "settled", "timeout": 90},
 {"type": "text", "text": "Without running any commands or reading any files, explain in about 300 words how inserting a key into a B-tree works, including node splits."},
 {"type": "submit"},
 {"type": "expect_quiet", "seconds": 8, "state": "settled", "timeout": 600}
]}
```

`shell-pause.json` (no agent: a 40 s silence while working, then a real question)
```json
{"harness": "", "agentVersion": "bash", "steps": [
 {"type": "expect", "pattern": "Overwrite build\\.log\\? \\(y/n\\)", "state": "asking", "question": "Overwrite build.log", "timeout": 90},
 {"type": "wait", "seconds": 6},
 {"type": "answer", "keys": "y\r"},
 {"type": "expect", "pattern": "all done", "state": "settled", "timeout": 30}
]}
```

- [ ] **Step 3: Record** (one command per scenario; watch it in the terminal; the driver echoes the agent's output)

```bash
cd "$REPO/packages/terminal/bench/agent-session"
SIG="$REPO/packages/terminal/bench/agent-session/signals"
SCRUB=$(env | awk -F= '/^CLAUDE/ {printf "-u %s ", $1}')
for name in claude-permission claude-question claude-two-permissions claude-think; do
  (cd "$SCRATCH/signal-claude" && git checkout -q -- . && git clean -qfd && python3 "$REPO/packages/terminal/bench/agent-session/record-scenario.py" --out "$SIG/$name" --scenario "$SIG/scenarios/$name.json" -- env $SCRUB claude --permission-mode default)
done
for name in codex-approval codex-think; do
  (cd "$SCRATCH/signal-codex" && git checkout -q -- . && git clean -qfd && python3 "$REPO/packages/terminal/bench/agent-session/record-scenario.py" --out "$SIG/$name" --scenario "$SIG/scenarios/$name.json" -- codex -a untrusted -s read-only -c "projects={\"$SCRATCH/signal-codex\"={trust_level=\"trusted\"}}")
done
python3 "$REPO/packages/terminal/bench/agent-session/record-scenario.py" --out "$SIG/shell-pause" --scenario "$SIG/scenarios/shell-pause.json" -- bash --noprofile --norc -c 'echo "building"; sleep 40; echo "wrote build.log"; sleep 2; read -p "Overwrite build.log? (y/n) " a; echo "answered $a"; sleep 1; echo "all done"; sleep 1'
```
Expected: each run exits 0 and leaves four files in `signals/<name>/`. If an `expect` times out, the driver prints the stripped screen: fix the pattern in that scenario file from what it printed (for example the real wording of Codex's approval prompt) and re-run that scenario; never hand-edit `truth.json` or the recording. For `shell-pause` the first interval is `working` for the whole 40 s silence by construction.

- [ ] **Step 4: Check each recording before committing**

```bash
cd "$SIG" && for d in */; do n=${d%/}; [ "$n" = scenarios ] && continue
  printf '%s bytes=%s reads=%s ' "$n" "$(wc -c < $n/recording)" "$(python3 -c "import json;print(len(json.load(open('$n/timing.json'))))")"
  python3 -c "import json;t=json.load(open('$n/truth.json'));print(' '.join(f\"{i['state']}:{(i['to']-i['from'])/1000:.1f}s\" for i in t['intervals']))"
  grep -a -E -c '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|sk-[A-Za-z0-9_-]{16,}' "$n/recording"
done
cd "$REPO/packages/terminal" && node --test ./bench/agent-session/fixtures.test.mjs 2>&1 | tail -3
```
Expected: every recording has at least one `asking` interval except `claude-think` and `codex-think`; `claude-two-permissions` has exactly two; `shell-pause` starts with `working:4x.xs`; the address/key count prints `0` for every recording (if not, re-record in a directory and account that do not show it; never edit bytes); the JS suite passes. Write the interval lines into the completion report.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/bench/agent-session/signals
git commit -m "test(terminal): timed Claude Code, Codex and shell recordings with ground truth for agent signals

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 3: vt-core owns the cursor-line prompt check and the activity classification

**Files:**
- Create: `packages/terminal/crates/vt-core/src/activity.rs`, `packages/terminal/crates/vt-core/src/activity/input_patterns.rs`, `packages/terminal/crates/vt-core/tests/agent_activity.rs`
- Move (git mv): `packages/terminal/ts/core/src/LICENSE-VSCODE-MIT` → `packages/terminal/crates/vt-core/src/activity/LICENSE-VSCODE-MIT`; `packages/terminal/ts/core/src/VSCODE-INPUT-PATTERNS-ATTRIBUTION.md` → `packages/terminal/crates/vt-core/src/activity/VSCODE-INPUT-PATTERNS-ATTRIBUTION.md`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs:1` (one module line, 597 → 598)

**Interfaces:**
- Produces (Rust, `vt_core::activity`): `ACTIVITY_POLLING_AFTER_MS: u64 = 500`, `ACTIVITY_IDLE_AFTER_MS: u64 = 1_500`; `enum AgentActivity { Active, PollingForIdle, Idle, Prompting }` with `wire(self) -> u32` (0, 1, 2, 3).
- Produces (Rust, `vt_core::activity::input_patterns`): `detects_high_confidence_input_pattern(cursor_line: &str) -> bool`.
- Produces (`vt_core::TerminalCore`): `cursor_line_text(&self) -> String`, `cursor_line_prompts(&self) -> bool`, `agent_activity(&self, quiet_ms: Option<u64>) -> AgentActivity` (`None` = no output yet).

- [ ] **Step 1: Failing tests**

Create `packages/terminal/crates/vt-core/tests/agent_activity.rs`:

```rust
use vt_core::activity::input_patterns::detects_high_confidence_input_pattern;
use vt_core::activity::{AgentActivity, ACTIVITY_IDLE_AFTER_MS, ACTIVITY_POLLING_AFTER_MS};
use vt_core::TerminalCore;

fn core() -> TerminalCore {
    let mut core = TerminalCore::new(80, 1_000).expect("core");
    core.resize(80, 24);
    core
}

#[test]
fn the_vscode_patterns_match_what_they_matched_in_typescript() {
    for line in [
        "Overwrite existing file? (y/n) ",
        "Continue? [Y/n] ",
        "Proceed (yes/no) ",
        "Ok to proceed? (y) ",
        "package name: (demo) ",
        "(END)",
        "[sudo] password for dev:",
        "Press any key to continue",
        "? Pick a color ❯ ",
        "[~] $ ",
    ] {
        assert!(detects_high_confidence_input_pattern(line), "{line:?} should match");
    }
    for line in [
        "❯ ",
        "❯\u{a0}",
        "$ ",
        "➜  repo git:(main) ",
        "Last Command: ",
        "✻ Baked for 11s · done 6:13 PM",
        "  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents",
    ] {
        assert!(!detects_high_confidence_input_pattern(line), "{line:?} should not match");
    }
}

#[test]
fn the_cursor_line_is_padded_in_cells_to_the_cursor() {
    let mut core = core();
    core.feed("继续吗 [y/n]".as_bytes());
    assert_eq!(core.cursor_line_text(), "继续吗 [y/n]");
    core.feed(b"\x1b[2C");
    assert_eq!(core.cursor_line_text(), "继续吗 [y/n]  ");
}

#[test]
fn the_cursor_line_of_the_alternate_screen_is_read_while_it_is_active() {
    let mut core = core();
    core.feed(b"primary\r\n\x1b[?1049hContinue? [Y/n] ");
    assert_eq!(core.cursor_line_text(), "Continue? [Y/n] ");
    assert!(core.cursor_line_prompts());
}

#[test]
fn activity_follows_the_quiet_time() {
    let mut core = core();
    core.feed(b"working on it");
    assert_eq!(core.agent_activity(Some(0)), AgentActivity::Active);
    assert_eq!(core.agent_activity(Some(ACTIVITY_POLLING_AFTER_MS - 1)), AgentActivity::Active);
    assert_eq!(core.agent_activity(Some(ACTIVITY_POLLING_AFTER_MS)), AgentActivity::PollingForIdle);
    assert_eq!(core.agent_activity(Some(ACTIVITY_IDLE_AFTER_MS - 1)), AgentActivity::PollingForIdle);
    assert_eq!(core.agent_activity(Some(ACTIVITY_IDLE_AFTER_MS)), AgentActivity::Idle);
    assert_eq!(core.agent_activity(None), AgentActivity::Idle);
}

#[test]
fn a_question_needs_a_prompt_on_the_cursor_line_not_just_silence() {
    let mut core = core();
    core.feed(b"compiling crate 12 of 40");
    assert_eq!(core.agent_activity(Some(40_000)), AgentActivity::Idle);
    core.feed(b"\r\nOverwrite greet.py? (y/n) ");
    assert_eq!(core.agent_activity(Some(100)), AgentActivity::Active);
    assert_eq!(core.agent_activity(Some(ACTIVITY_POLLING_AFTER_MS)), AgentActivity::Prompting);
    assert_eq!(core.agent_activity(Some(60_000)), AgentActivity::Prompting);
}

#[test]
fn a_prompt_the_shell_line_editor_owns_is_not_a_question() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;input-ready=1\x07[~] $ ");
    assert!(!core.cursor_line_prompts());
    assert_eq!(core.agent_activity(Some(ACTIVITY_POLLING_AFTER_MS)), AgentActivity::PollingForIdle);
    core.feed(b"\x1b]7000;v=1;input-released=1\x07\r\nOverwrite greet.py? (y/n) ");
    assert!(core.cursor_line_prompts());
}

#[test]
fn the_wire_values_are_stable() {
    assert_eq!(AgentActivity::Active.wire(), 0);
    assert_eq!(AgentActivity::PollingForIdle.wire(), 1);
    assert_eq!(AgentActivity::Idle.wire(), 2);
    assert_eq!(AgentActivity::Prompting.wire(), 3);
}

fn fixture(name: &str) -> (Vec<u8>, Vec<(usize, usize, usize)>) {
    let dir = format!("{}/../../bench/agent-session/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    let recording = std::fs::read(format!("{dir}/recording")).expect("recording");
    let sizes: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(format!("{dir}/size.json")).expect("size.json")).expect("json");
    let sizes = sizes
        .as_array()
        .expect("array")
        .iter()
        .map(|size| {
            (
                size["offset"].as_u64().expect("offset") as usize,
                size["cols"].as_u64().expect("cols") as usize,
                size["rows"].as_u64().expect("rows") as usize,
            )
        })
        .collect();
    (recording, sizes)
}

#[test]
fn no_frame_of_the_claude_code_recordings_prompts() {
    const ESU: &[u8] = b"\x1b[?2026l";
    for name in ["claude-spinner-10s", "claude-markdown-reply", "claude-long-50k"] {
        let (recording, sizes) = fixture(name);
        let mut core = TerminalCore::new(sizes[0].1, 200_000).expect("core");
        core.resize(sizes[0].1, sizes[0].2);
        let mut ends: Vec<usize> = recording
            .windows(ESU.len())
            .enumerate()
            .filter(|(_, window)| *window == ESU)
            .map(|(at, _)| at + ESU.len())
            .collect();
        ends.push(recording.len());
        let mut fed = 0;
        let mut next = 1;
        let mut prompts = 0;
        for end in ends {
            while next < sizes.len() && sizes[next].0 <= end {
                core.feed(&recording[fed..sizes[next].0]);
                fed = sizes[next].0;
                core.resize(sizes[next].1, sizes[next].2);
                next += 1;
            }
            core.feed(&recording[fed..end]);
            fed = end;
            if core.cursor_line_prompts() {
                prompts += 1;
            }
        }
        assert_eq!(prompts, 0, "{name}");
    }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test agent_activity 2>&1 | tail -5
```
Expected: `error[E0432]: unresolved import vt_core::activity`.

- [ ] **Step 3: Implementation**

Move the attribution files and add the module:

```bash
cd "$REPO/packages/terminal" && mkdir -p crates/vt-core/src/activity
git mv ts/core/src/LICENSE-VSCODE-MIT crates/vt-core/src/activity/LICENSE-VSCODE-MIT
git mv ts/core/src/VSCODE-INPUT-PATTERNS-ATTRIBUTION.md crates/vt-core/src/activity/VSCODE-INPUT-PATTERNS-ATTRIBUTION.md
```
In `VSCODE-INPUT-PATTERNS-ATTRIBUTION.md` replace `` `input-patterns.ts` ports `` with `` `input_patterns.rs` ports ``; replace `- The nine regular expressions are kept verbatim, in the same order, in a\n  module-level array instead of an array literal built on every call.` with `- The nine regular expressions are kept in the same order, compiled once with\n  \`regex-automata\`; the JavaScript \`i\` flag is written as \`(?i)\`.`; and replace `The idle timing in \`agent-activity.ts\`` with ``The idle timing in `activity.rs` (and `ts/core/src/agent-activity.ts`)``.

In `packages/terminal/crates/vt-core/src/lib.rs` replace line 1 `pub mod agent;` with:

```rust
pub mod activity;
pub mod agent;
```

Create `packages/terminal/crates/vt-core/src/activity/input_patterns.rs`:

```rust
/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE-VSCODE-MIT beside this file.
 *--------------------------------------------------------------------------------------------*/

use regex_automata::meta::Regex;
use std::sync::OnceLock;

const HIGH_CONFIDENCE_INPUT_PATTERNS: [&str; 9] = [
    r#"\s*(?:\[[^\]]\][^\[]*)+(?:\(default is\s+"[^"]+"\):)?\s+$"#,
    r"(?i)(?:\(|\[)\s*(?:y(?:es)?\s*/\s*n(?:o)?|n(?:o)?\s*/\s*y(?:es)?)\s*(?:\]|\))\s+$",
    r"(?i)[?:]\s*(?:\(|\[)?\s*y(?:es)?\s*/\s*n(?:o)?\s*(?:\]|\))?\s+$",
    r"(?i)\(y\) +$",
    r":\s+\([^)]*\) +$",
    r"\(END\)$",
    r"(?i)password(?: for [^:]+)?:\s*$",
    r"(?i)press a(?:ny)? key",
    r"^(?:\s|\x1b\[[0-9;]*m)*\?.*[›❯▸▶]\s*$",
];

fn patterns() -> &'static [Regex] {
    static PATTERNS: OnceLock<Vec<Regex>> = OnceLock::new();
    PATTERNS.get_or_init(|| {
        HIGH_CONFIDENCE_INPUT_PATTERNS
            .iter()
            .map(|pattern| Regex::new(pattern).expect("input pattern compiles"))
            .collect()
    })
}

pub fn detects_high_confidence_input_pattern(cursor_line: &str) -> bool {
    patterns().iter().any(|pattern| pattern.is_match(cursor_line))
}
```

Create `packages/terminal/crates/vt-core/src/activity.rs`:

```rust
pub mod input_patterns;

use crate::{LineEditorState, TerminalCore};

pub const ACTIVITY_POLLING_AFTER_MS: u64 = 500;
pub const ACTIVITY_IDLE_AFTER_MS: u64 = 1_500;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AgentActivity {
    Active,
    PollingForIdle,
    Idle,
    Prompting,
}

impl AgentActivity {
    pub fn wire(self) -> u32 {
        match self {
            AgentActivity::Active => 0,
            AgentActivity::PollingForIdle => 1,
            AgentActivity::Idle => 2,
            AgentActivity::Prompting => 3,
        }
    }
}

impl TerminalCore {
    pub fn agent_activity(&self, quiet_ms: Option<u64>) -> AgentActivity {
        let quiet = quiet_ms.unwrap_or(u64::MAX);
        if quiet < ACTIVITY_POLLING_AFTER_MS {
            return AgentActivity::Active;
        }
        if self.cursor_line_prompts() {
            return AgentActivity::Prompting;
        }
        if quiet < ACTIVITY_IDLE_AFTER_MS {
            AgentActivity::PollingForIdle
        } else {
            AgentActivity::Idle
        }
    }

    pub fn cursor_line_prompts(&self) -> bool {
        !matches!(self.line_editor_state(), LineEditorState::Owned)
            && input_patterns::detects_high_confidence_input_pattern(&self.cursor_line_text())
    }

    pub fn cursor_line_text(&self) -> String {
        let screen = match self.parser.alt() {
            Some(alt) => alt,
            None => self.parser.screen(),
        };
        let (row, column) = screen.cursor();
        let columns = screen.cols();
        let last = (0..columns).rev().find(|&col| {
            screen
                .cell_ref(row, col)
                .is_some_and(|cell| !matches!(cell.ch, ' ' | '\0'))
        });
        let end = last.map_or(0, |col| col + 1).max(column).min(columns);
        let mut out = String::new();
        let mut buffer = [0u8; 4];
        for col in 0..end {
            match screen.cell_ref(row, col) {
                Some(cell) if cell.ch == '\0' => {}
                Some(cell) => out.push_str(cell.text(&mut buffer)),
                None => out.push(' '),
            }
        }
        out
    }
}
```
(`self.parser`, `ScreenGrid::cell_ref` (`screen.rs:283`, `pub(crate)`) and `Cell::ch`/`text` (`screen.rs:33,62`) are reachable because `activity` is a child module of the crate root, as `agent.rs:153-161` reaches `self.parser`.)

- [ ] **Step 4: Run, expect pass; lint; size**

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test agent_activity 2>&1 | tail -3
cargo fmt && cargo clippy --all-targets -- -D warnings 2>&1 | tail -2 && cargo test -p vt-core 2>&1 | grep -E "FAILED|panicked"; wc -l crates/vt-core/src/lib.rs
```
Expected: `test result: ok. 8 passed`; clippy clean; no FAILED line; `598 crates/vt-core/src/lib.rs`.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-core/src/activity.rs packages/terminal/crates/vt-core/src/activity packages/terminal/crates/vt-core/src/lib.rs packages/terminal/crates/vt-core/tests/agent_activity.rs
git status --short packages/terminal | grep -E 'LICENSE-VSCODE-MIT|VSCODE-INPUT'
git commit -m "feat(vt-core): cursor-line prompt check and agent activity classification in the core

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
The `git status` line must print two `R` rows (`ts/core/src/LICENSE-VSCODE-MIT -> crates/vt-core/src/activity/LICENSE-VSCODE-MIT` and the attribution file), staged by the `git mv` in Step 3.

---

### Task 4: The renderer core asks vt-core (one classifier for both copies)

**Files:**
- Create: `packages/terminal/crates/vt-wasm/src/agent.rs`, `packages/terminal/crates/vt-wasm/tests/agent_exports.rs`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs:1-10` (module + re-export, 581 → 583); `packages/terminal/ts/core/src/input-patterns.ts:1-20` (whole file); `packages/terminal/ts/core/src/agent-activity.ts:1-143` (source shape, drop `cursorLineText`/`cellWidth`); `packages/terminal/ts/core/src/terminal-core.ts:17,93-98` (599 → 598); `packages/terminal/ts/core/src/index-browser.ts:90-99`; `packages/terminal/ts/core/src/agent-activity.test.ts:1-430`

**Interfaces:**
- Produces (wasm-bindgen): free function `detects_high_confidence_input_pattern(line: &str) -> bool`; method `WasmTerminalCore::cursor_line_prompts(&self) -> bool`.
- Produces (TS): `type AgentActivitySource = Readonly<{ liveOutputBytes(): number; prompting(): boolean; now(): number }>` (was `cursorLine()` + optional `lineEditorOwnsLine()`); `detectsHighConfidenceInputPattern(line: string): boolean` unchanged in name, now needs `initTerminalCore` first. Removed: `cursorLineText`.

- [ ] **Step 1: Failing Rust test**

Create `packages/terminal/crates/vt-wasm/tests/agent_exports.rs`:

```rust
use vt_wasm::{detects_high_confidence_input_pattern, WasmTerminalCore};

#[test]
fn the_wasm_core_reports_a_question_at_the_cursor() {
    let Ok(mut core) = WasmTerminalCore::new(80, 1_000, 1 << 20) else {
        panic!("core");
    };
    assert!(core.resize(80, 24).is_ok());
    assert!(core.feed(b"Overwrite greet.py? (y/n) ", 0.0).is_ok());
    assert!(core.cursor_line_prompts());
    assert!(detects_high_confidence_input_pattern("Continue? [Y/n] "));
    assert!(!detects_high_confidence_input_pattern("❯ "));
}
```

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-wasm --test agent_exports 2>&1 | tail -3
```
Expected: `error[E0432]: unresolved import vt_wasm::detects_high_confidence_input_pattern`.

- [ ] **Step 2: wasm exports**

Create `packages/terminal/crates/vt-wasm/src/agent.rs`:

```rust
use wasm_bindgen::prelude::*;

use crate::WasmTerminalCore;

#[wasm_bindgen]
pub fn detects_high_confidence_input_pattern(line: &str) -> bool {
    vt_core::activity::input_patterns::detects_high_confidence_input_pattern(line)
}

#[wasm_bindgen]
impl WasmTerminalCore {
    pub fn cursor_line_prompts(&self) -> bool {
        self.core.cursor_line_prompts()
    }
}
```
In `packages/terminal/crates/vt-wasm/src/lib.rs` replace `mod export;` (line 1) with `mod agent;\nmod export;`, and replace `pub use program::{flatten_agent_events, flatten_notifications};` with:

```rust
pub use agent::detects_high_confidence_input_pattern;
pub use program::{flatten_agent_events, flatten_notifications};
```

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-wasm --test agent_exports 2>&1 | tail -3 && wc -l crates/vt-wasm/src/lib.rs
```
Expected: `test result: ok. 1 passed`; `583`.

- [ ] **Step 3: Failing TS test changes**

In `packages/terminal/ts/core/src/agent-activity.test.ts`:
- In the import list (lines 4-14) delete `cursorLineText,`.
- Replace the whole `fakeSource` function (lines 62-81) with:

```ts
function fakeSource(line = "") {
	let bytes = 0;
	let owned = false;
	const source = {
		prompting: vi.fn(() => !owned && detectsHighConfidenceInputPattern(line)),
		liveOutputBytes: () => bytes,
		now: () => Date.now(),
		setOwned: (next: boolean) => {
			owned = next;
		},
		setLine: (next: string) => {
			line = next;
		},
		write: (count: number) => {
			bytes += count;
		},
	};
	return source;
}
```
- Replace the test "never reads the cursor line while output is active" (lines 179-187) with:

```ts
	it("never checks for a prompt while output is active", () => {
		const source = fakeSource();
		const monitor = new AgentActivityMonitor(source);
		source.write(1);
		monitor.observe();
		source.prompting.mockClear();
		expect(monitor.state()).toBe("active");
		expect(source.prompting).not.toHaveBeenCalled();
	});
```
- Replace the test "pads the cursor line in cells, so a wide-character line gets no false trailing space" (lines 345-358) with:

```ts
	it("a wide-character question prompts only once the cursor leaves a trailing space after it", () => {
		const target = core(80, 24);
		target.feed(encoder.encode("继续吗 [y/n]"));
		vi.advanceTimersByTime(ACTIVITY_POLLING_AFTER_MS);
		expect(target.agentActivity()).toBe("pollingForIdle");
		target.feed(encoder.encode("\x1b[2C"));
		vi.advanceTimersByTime(ACTIVITY_POLLING_AFTER_MS);
		expect(target.agentActivity()).toBe("prompting");
		target.dispose();
	});
```
- In the recordings test (lines 389-428) delete the line `let prompts = 0;`, the line `if (detectsHighConfidenceInputPattern(cursorLineText(target.snapshot(), decoder))) prompts += 1;` and the line `expect(prompts).toBe(0);` (the same check now runs per frame in Rust, Task 3 `no_frame_of_the_claude_code_recordings_prompts`), and change the title's `, never prompting` to nothing.
- If `decoder` (line 32) is now unused, delete that line.

```bash
cd "$REPO/packages/terminal" && npm run build:wasm -- --force >/dev/null && cd ts/core && npx vitest run src/agent-activity.test.ts 2>&1 | tail -5
```
Expected: FAIL — TypeScript/vitest reports the monitor calling `source.cursorLine` (not a function) in the fake-source tests.

- [ ] **Step 4: TS implementation**

Replace `packages/terminal/ts/core/src/input-patterns.ts` with:

```ts
import { detects_high_confidence_input_pattern } from "../wasm/vt_core.js";

export function detectsHighConfidenceInputPattern(cursorLine: string): boolean {
	return detects_high_confidence_input_pattern(cursorLine);
}
```

In `packages/terminal/ts/core/src/agent-activity.ts`:
- Replace lines 1-4 (the four imports) with `import { callEach, throwFailures } from "./listener-failures.js";`.
- Replace the `AgentActivitySource` type (lines 16-21) with:

```ts
export type AgentActivitySource = Readonly<{
	liveOutputBytes(): number;
	prompting(): boolean;
	now(): number;
}>;
```
- In `evaluate` replace `if (!this.source.lineEditorOwnsLine?.() && detectsHighConfidenceInputPattern(this.source.cursorLine())) return "prompting";` with `if (this.source.prompting()) return "prompting";`.
- Delete `cursorLineText` and `cellWidth` (lines 106-143).

In `packages/terminal/ts/core/src/terminal-core.ts`:
- Line 17: replace `import { AgentActivityMonitor, cursorLineText, type AgentActivityListener, type AgentActivityState } from "./agent-activity.js";` with `import { AgentActivityMonitor, type AgentActivityListener, type AgentActivityState } from "./agent-activity.js";`.
- Replace lines 93-98:

```ts
		this.activity = new AgentActivityMonitor({
			liveOutputBytes: () => (this.disposed ? 0 : this.inner.live_output_bytes()),
			cursorLine: () => (this.disposed ? "" : cursorLineText(this.snapshot(), this.decoder)),
			lineEditorOwnsLine: () => !this.disposed && LINE_EDITOR_STATES[this.snapshot().lineEditorState] === "owned",
			now: () => Date.now(),
		});
```
with
```ts
		this.activity = new AgentActivityMonitor({
			liveOutputBytes: () => (this.disposed ? 0 : this.inner.live_output_bytes()),
			prompting: () => !this.disposed && this.inner.cursor_line_prompts(),
			now: () => Date.now(),
		});
```

In `packages/terminal/ts/core/src/index-browser.ts` delete the line `	cursorLineText,` inside the `./agent-activity.js` export block (line 94).

- [ ] **Step 5: Run, expect pass; the whole package**

```bash
cd "$REPO/packages/terminal" && grep -rn "cursorLineText\|lineEditorOwnsLine" ts --include=*.ts | grep -v node_modules
npm run build:ts && for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  |FAIL"); done
npm run check:boundaries 2>&1 | tail -1 && wc -l ts/core/src/terminal-core.ts
cargo fmt && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
```
Expected: the grep prints nothing; every package's `Tests  N passed` with the Task 0 counts (core unchanged in number: 3 tests renamed/rewritten, none added or removed); `boundary check passed`; `598 ts/core/src/terminal-core.ts`; clippy clean.

- [ ] **Step 6: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-wasm/src/agent.rs packages/terminal/crates/vt-wasm/src/lib.rs packages/terminal/crates/vt-wasm/tests/agent_exports.rs packages/terminal/ts/core/src/input-patterns.ts packages/terminal/ts/core/src/agent-activity.ts packages/terminal/ts/core/src/terminal-core.ts packages/terminal/ts/core/src/index-browser.ts packages/terminal/ts/core/src/agent-activity.test.ts
git commit -m "refactor(terminal): the TS activity monitor asks vt-core whether the cursor line prompts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The mirror exports activity; Go wrapper and `ActivityClock`

**Files:**
- Create: `packages/terminal/crates/vt-host/src/activity.rs`, `backend/internal/adapters/runtime/ptyhost/vtwasm/activity.go`, `backend/internal/adapters/runtime/ptyhost/vtwasm/activity_test.go`
- Modify: `packages/terminal/crates/vt-host/src/lib.rs:1-5` (module), `packages/terminal/crates/vt-host/src/program.rs:5-14` (`write_out` becomes `pub(crate)`), `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` (rebuilt)

**Interfaces:**
- Produces (C ABI): `vt_live_output_bytes(handle) -> u64`; `vt_agent_activity(handle, quiet_ms: u64) -> u32` (`u64::MAX` = no output yet; `RENDER_ERR` for a bad handle); `vt_cursor_line(handle, out_ptr, out_cap) -> u32`.
- Produces (Go, `vtwasm`): `type AgentActivity uint32` with `ActivityActive`, `ActivityPollingForIdle`, `ActivityIdle`, `ActivityPrompting` and `String() string` (`"active"`, `"pollingForIdle"`, `"idle"`, `"prompting"`); `(*Parser).LiveOutputBytes() (uint64, error)`; `(*Parser).AgentActivity(quietMs int64) (AgentActivity, error)` (negative = no output yet); `(*Parser).CursorLine() (string, error)`; `const InputEchoWindow = 250 * time.Millisecond`; `type ActivityClock struct`; `NewActivityClock(p *Parser) ActivityClock`; `(*ActivityClock).Step(p *Parser, now, pokedAt time.Time) (AgentActivity, bool, error)`.

- [ ] **Step 1: Failing Go tests**

Create `backend/internal/adapters/runtime/ptyhost/vtwasm/activity_test.go`:

```go
package vtwasm

import (
	"testing"
	"time"
)

func TestTheMirrorClassifiesQuietAndQuestions(t *testing.T) {
	p := newTestParser(t, 80, 24)
	before, err := p.LiveOutputBytes()
	if err != nil {
		t.Fatalf("live bytes: %v", err)
	}
	feed(t, p, "Overwrite greet.py? (y/n) ")
	after, _ := p.LiveOutputBytes()
	if after <= before {
		t.Fatalf("live bytes did not move: %d -> %d", before, after)
	}
	for _, tc := range []struct {
		quiet int64
		want  AgentActivity
	}{{0, ActivityActive}, {499, ActivityActive}, {500, ActivityPrompting}, {-1, ActivityPrompting}} {
		got, err := p.AgentActivity(tc.quiet)
		if err != nil || got != tc.want {
			t.Fatalf("AgentActivity(%d) = %v, %v; want %v", tc.quiet, got, err, tc.want)
		}
	}
	line, err := p.CursorLine()
	if err != nil || line != "Overwrite greet.py? (y/n) " {
		t.Fatalf("cursor line = %q, %v", line, err)
	}
}

func TestTheActivityClockPublishesTransitionsOnly(t *testing.T) {
	p := newTestParser(t, 80, 24)
	clock := NewActivityClock(p)
	start := time.Unix(1_800_000_000, 0)
	if _, changed, _ := clock.Step(p, start, time.Time{}); changed {
		t.Fatal("a clock with no output published")
	}
	feed(t, p, "working")
	state, changed, err := clock.Step(p, start.Add(10*time.Millisecond), time.Time{})
	if err != nil || !changed || state != ActivityActive {
		t.Fatalf("first output = %v %v %v, want active", state, changed, err)
	}
	if _, changed, _ := clock.Step(p, start.Add(700*time.Millisecond), time.Time{}); changed {
		t.Fatal("pollingForIdle was published")
	}
	state, changed, _ = clock.Step(p, start.Add(1600*time.Millisecond), time.Time{})
	if !changed || state != ActivityIdle {
		t.Fatalf("after 1.5 s quiet = %v %v, want idle", state, changed)
	}
	if _, changed, _ := clock.Step(p, start.Add(5*time.Second), time.Time{}); changed {
		t.Fatal("idle was published twice")
	}
}

func TestTheActivityClockIgnoresTypingEcho(t *testing.T) {
	p := newTestParser(t, 80, 24)
	clock := NewActivityClock(p)
	start := time.Unix(1_800_000_000, 0)
	feed(t, p, "x")
	if _, changed, _ := clock.Step(p, start.Add(50*time.Millisecond), start); changed {
		t.Fatal("echo within 250 ms of a keystroke counted as activity")
	}
	feed(t, p, "agent output")
	state, changed, _ := clock.Step(p, start.Add(400*time.Millisecond), start)
	if !changed || state != ActivityActive {
		t.Fatalf("output after the echo window = %v %v, want active", state, changed)
	}
}

func TestANewClockTakesItsBaselineFromTheParser(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "bytes before the clock existed")
	clock := NewActivityClock(p)
	if _, changed, _ := clock.Step(p, time.Unix(1_800_000_000, 0), time.Time{}); changed {
		t.Fatal("bytes fed before the clock was made counted as new output")
	}
}
```

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/vtwasm/ -run 'Activity|Mirror' 2>&1 | tail -3
```
Expected: build failure, `p.LiveOutputBytes undefined`.

- [ ] **Step 2: vt-host exports**

In `packages/terminal/crates/vt-host/src/program.rs` change `fn write_out(` to `pub(crate) fn write_out(`.

Create `packages/terminal/crates/vt-host/src/activity.rs`:

```rust
use crate::program::write_out;
use crate::{CORES, RENDER_ERR};

#[no_mangle]
pub extern "C" fn vt_live_output_bytes(handle: u32) -> u64 {
    CORES.with(|c| c.borrow().get(&handle).map_or(0, |core| core.live_output_bytes()))
}

#[no_mangle]
pub extern "C" fn vt_agent_activity(handle: u32, quiet_ms: u64) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => core
            .agent_activity((quiet_ms != u64::MAX).then_some(quiet_ms))
            .wire(),
        None => RENDER_ERR,
    })
}

#[no_mangle]
pub extern "C" fn vt_cursor_line(handle: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => write_out(core.cursor_line_text().as_bytes(), out_ptr, out_cap),
        None => RENDER_ERR,
    })
}
```
In `packages/terminal/crates/vt-host/src/lib.rs` replace `mod block_marks;` (line 1) with `mod activity;\nmod block_marks;`.

- [ ] **Step 3: Go wrapper**

Create `backend/internal/adapters/runtime/ptyhost/vtwasm/activity.go`:

```go
package vtwasm

import (
	"fmt"
	"math"
	"time"
)

type AgentActivity uint32

const (
	ActivityActive AgentActivity = iota
	ActivityPollingForIdle
	ActivityIdle
	ActivityPrompting
)

func (a AgentActivity) String() string {
	switch a {
	case ActivityActive:
		return "active"
	case ActivityPollingForIdle:
		return "pollingForIdle"
	case ActivityIdle:
		return "idle"
	case ActivityPrompting:
		return "prompting"
	default:
		return "unknown"
	}
}

const (
	cursorLineBufferBytes = 4096
	InputEchoWindow       = 250 * time.Millisecond
)

func (p *Parser) callLocked(name string, args ...uint64) (uint64, error) {
	fn := p.module.ExportedFunction(name)
	if fn == nil {
		return 0, fmt.Errorf("vtwasm: %s is not exported", name)
	}
	res, err := fn.Call(p.ctx, args...)
	if err != nil {
		return 0, fmt.Errorf("vtwasm: %s: %w", name, err)
	}
	return res[0], nil
}

func (p *Parser) LiveOutputBytes() (uint64, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.callLocked("vt_live_output_bytes", uint64(p.handle))
}

func (p *Parser) AgentActivity(quietMs int64) (AgentActivity, error) {
	quiet := uint64(math.MaxUint64)
	if quietMs >= 0 {
		quiet = uint64(quietMs)
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	raw, err := p.callLocked("vt_agent_activity", uint64(p.handle), quiet)
	if err != nil {
		return ActivityIdle, err
	}
	if uint32(raw) == renderErr {
		return ActivityIdle, fmt.Errorf("vtwasm: agent_activity failed for handle %d", p.handle)
	}
	return AgentActivity(uint32(raw)), nil
}

func (p *Parser) CursorLine() (string, error) {
	raw, err := p.readOut("vt_cursor_line", cursorLineBufferBytes)
	return string(raw), err
}

type ActivityClock struct {
	bytes     uint64
	lastAt    time.Time
	started   bool
	published bool
	shown     AgentActivity
}

func NewActivityClock(p *Parser) ActivityClock {
	bytes, _ := p.LiveOutputBytes()
	return ActivityClock{bytes: bytes}
}

func (c *ActivityClock) Step(p *Parser, now, pokedAt time.Time) (AgentActivity, bool, error) {
	bytes, err := p.LiveOutputBytes()
	if err != nil {
		return c.shown, false, err
	}
	if bytes != c.bytes {
		c.bytes = bytes
		if pokedAt.IsZero() || now.Sub(pokedAt) >= InputEchoWindow {
			c.lastAt = now
			c.started = true
		}
	}
	if !c.started {
		return c.shown, false, nil
	}
	state, err := p.AgentActivity(now.Sub(c.lastAt).Milliseconds())
	if err != nil {
		return c.shown, false, err
	}
	if state == ActivityPollingForIdle || (c.published && state == c.shown) {
		return c.shown, false, nil
	}
	c.shown = state
	c.published = true
	return state, true, nil
}
```

- [ ] **Step 4: Rebuild the mirror wasm; run**

```bash
cd "$REPO/packages/terminal" && cargo fmt && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1
cargo build --release -p vt-host --target wasm32-unknown-unknown 2>&1 | tail -1
cp target/wasm32-unknown-unknown/release/vt_host.wasm "$REPO/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm"
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/vtwasm/ 2>&1 | tail -2 && go vet ./internal/adapters/runtime/ptyhost/... 2>&1 | tail -1
```
Expected: clippy clean; `Finished release`; `ok  …/vtwasm`; vet silent.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-host/src/activity.rs packages/terminal/crates/vt-host/src/lib.rs packages/terminal/crates/vt-host/src/program.rs backend/internal/adapters/runtime/ptyhost/vtwasm/activity.go backend/internal/adapters/runtime/ptyhost/vtwasm/activity_test.go backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
git commit -m "feat(vt-host): export live output, agent activity and the cursor line to the Go mirror

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 6: The pty-host publishes activity transitions to watchers that ask

**Files:**
- Create: `backend/internal/adapters/runtime/ptyhost/activity.go`, `backend/internal/adapters/runtime/ptyhost/activity_test.go`
- Modify: `backend/internal/adapters/runtime/ptyhost/proto.go:92-101` (kind + fields); `backend/internal/adapters/runtime/ptyhost/host.go:94-130` (`clientState.wantsActivity`), `:191-247` (host fields), `:68-82` (`newHost`), `:360` (resize poke), `:371-375` (`run`), `:653` (`deliver`), `:840-842` (watch dispatch), `:1076-1080` (input poke); `backend/internal/adapters/runtime/ptyhost/program.go:25-33` (`serveWatcher`), `:96-99` (`resetProgramLocked`)

**Interfaces:**
- Consumes: `vtwasm.ActivityClock`, `NewActivityClock`, `(*Parser).RenderTail`, `(*Parser).CursorLine` (Task 5).
- Produces (wire): `ProgramEventActivity = "activity"`; `ProgramEventPayload` gains `Activity string json:"activity,omitempty"`, `Seq uint64 json:"seq,omitempty"`, `AtMs int64 json:"atMs,omitempty"`, `Tail string json:"tail,omitempty"`, `CursorLine string json:"cursorLine,omitempty"`; `MsgWatchReq` payload `WatchPayload{Activity bool json:"activity,omitempty"}` (empty payload = today's watcher, no activity).
- Produces (host): `var activityTick = 250 * time.Millisecond`, `const activityTailRows = 40`.

- [ ] **Step 1: Failing tests**

Create `backend/internal/adapters/runtime/ptyhost/activity_test.go`:

```go
package ptyhost

import (
	"context"
	"fmt"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

func fastActivityTick(t *testing.T) {
	t.Helper()
	previous := activityTick
	activityTick = 20 * time.Millisecond
	t.Cleanup(func() { activityTick = previous })
}

func newActivityWatcher(t *testing.T, addr string) *testClient {
	t.Helper()
	w := newTestClient(t, addr)
	if err := w.send(MsgWatchReq, []byte(`{"activity":true}`)); err != nil {
		t.Fatalf("send watch: %v", err)
	}
	return w
}

func readActivity(t *testing.T, c *testClient, within time.Duration) ProgramEventPayload {
	t.Helper()
	deadline := time.After(within)
	for {
		select {
		case frame, ok := <-c.frameC:
			if !ok {
				t.Fatal("watcher closed")
			}
			if frame.typ != MsgProgramEvent {
				continue
			}
			event := decodeProgramEvent(t, frame.payload)
			if event.Kind == ProgramEventActivity {
				return event
			}
		case <-deadline:
			t.Fatalf("no activity event within %v", within)
		}
	}
}

func expectNoActivity(t *testing.T, c *testClient, within time.Duration) {
	t.Helper()
	deadline := time.After(within)
	for {
		select {
		case frame, ok := <-c.frameC:
			if !ok {
				return
			}
			if frame.typ == MsgProgramEvent && decodeProgramEvent(t, frame.payload).Kind == ProgramEventActivity {
				t.Fatalf("unexpected activity event %q", frame.payload)
			}
		case <-deadline:
			return
		}
	}
}

func TestActivityIsPublishedWithNoAttachedClient(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 941, 80, 24)
	defer f.cancel()
	w := newActivityWatcher(t, f.addr)
	defer w.close()
	writeOutput(t, f, "building the index\r\n")
	if event := readActivity(t, w, 2*time.Second); event.Activity != "active" || event.Tail != "" || event.Seq != 1 {
		t.Fatalf("first event = %+v, want active with no tail", event)
	}
	event := readActivity(t, w, 3*time.Second)
	if event.Activity != "idle" || !strings.Contains(event.Tail, "building the index") || event.Seq != 2 || event.AtMs == 0 {
		t.Fatalf("second event = %+v, want idle with the screen tail", event)
	}
}

func TestAQuestionIsPublishedAsPromptingWithItsCursorLine(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 942, 80, 24)
	defer f.cancel()
	w := newActivityWatcher(t, f.addr)
	defer w.close()
	writeOutput(t, f, "Overwrite build.log? (y/n) ")
	readActivity(t, w, 2*time.Second)
	event := readActivity(t, w, 2*time.Second)
	if event.Activity != "prompting" || event.CursorLine != "Overwrite build.log? (y/n) " {
		t.Fatalf("event = %+v, want prompting with the cursor line", event)
	}
}

func TestAPlainWatcherGetsNoActivity(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 943, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()
	readProgramEvent(t, w)
	writeOutput(t, f, "output\r\n")
	expectNoFrame(t, w, 2*time.Second)
}

func TestALateActivityWatcherGetsTheCurrentStateOnce(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 944, 80, 24)
	defer f.cancel()
	first := newActivityWatcher(t, f.addr)
	defer first.close()
	writeOutput(t, f, "done for now\r\n")
	readActivity(t, first, 2*time.Second)
	idle := readActivity(t, first, 3*time.Second)
	late := newActivityWatcher(t, f.addr)
	defer late.close()
	if event := readActivity(t, late, time.Second); event.Seq != idle.Seq || event.Activity != "idle" {
		t.Fatalf("late watcher got %+v, want the idle event %d", event, idle.Seq)
	}
	expectNoActivity(t, late, 600*time.Millisecond)
}

func TestTypingEchoIsNotActivity(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 945, 80, 24)
	defer f.cancel()
	w := newActivityWatcher(t, f.addr)
	defer w.close()
	f.host.handleClientMsg(nil, MsgTerminalInput, []byte("x"))
	writeOutput(t, f, "x")
	expectNoActivity(t, w, time.Second)
}

func TestASeededHostPublishesNoActivity(t *testing.T) {
	fastActivityTick(t)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	parser, err := vtwasm.New(context.Background(), vtwasm.Module, 80, 24, vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	t.Cleanup(func() { _ = parser.Close() })
	if err := parser.Feed([]byte("output from before the relaunch\r\n" + string(respawnBoundary(0, false)))); err != nil {
		t.Fatalf("seed: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	h := newHost(ctx, ServeConfig{SessionID: fmt.Sprintf("test-%d", 946), Listener: ln, PTY: newFakePTY(946), Ring: NewRing(), Parser: parser, InitialCols: 80, InitialRows: 24})
	go func() { _ = h.run(ctx) }()
	w := newActivityWatcher(t, ln.Addr().String())
	defer w.close()
	expectNoActivity(t, w, 2*time.Second)
}
```
Add a helper next to `readProgramEvent` in `program_test.go`'s style, at the end of `activity_test.go`:

```go
func decodeProgramEvent(t *testing.T, payload []byte) ProgramEventPayload {
	t.Helper()
	var event ProgramEventPayload
	if err := json.Unmarshal(payload, &event); err != nil {
		t.Fatalf("decode program event: %v", err)
	}
	return event
}
```
(and add `"encoding/json"` to the imports).

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ -run 'Activity|Seeded|Echo|PlainWatcher' 2>&1 | tail -3
```
Expected: build failure, `undefined: activityTick` / `ProgramEventActivity`.

- [ ] **Step 2: Wire format**

In `backend/internal/adapters/runtime/ptyhost/proto.go` replace

```go
const (
	ProgramEventTitle        = "title"
	ProgramEventNotification = "notification"
)

type ProgramEventPayload struct {
	Kind  string `json:"kind"`
	Title string `json:"title"`
	Body  string `json:"body,omitempty"`
}
```
with
```go
const (
	ProgramEventTitle        = "title"
	ProgramEventNotification = "notification"
	ProgramEventActivity     = "activity"
)

type ProgramEventPayload struct {
	Kind       string `json:"kind"`
	Title      string `json:"title"`
	Body       string `json:"body,omitempty"`
	Activity   string `json:"activity,omitempty"`
	Seq        uint64 `json:"seq,omitempty"`
	AtMs       int64  `json:"atMs,omitempty"`
	Tail       string `json:"tail,omitempty"`
	CursorLine string `json:"cursorLine,omitempty"`
}

type WatchPayload struct {
	Activity bool `json:"activity,omitempty"`
}
```

- [ ] **Step 3: Publisher**

Create `backend/internal/adapters/runtime/ptyhost/activity.go`:

```go
package ptyhost

import (
	"encoding/json"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

var activityTick = 250 * time.Millisecond

const activityTailRows = 40

func (h *host) runActivityClock() {
	ticker := time.NewTicker(activityTick)
	defer ticker.Stop()
	for {
		select {
		case <-h.shutdownC:
			return
		case now := <-ticker.C:
			h.mu.Lock()
			h.publishActivityLocked(now)
			h.mu.Unlock()
		}
	}
}

func (h *host) publishActivityLocked(now time.Time) {
	if h.parser == nil {
		return
	}
	state, changed, err := h.activity.Step(h.parser, now, h.pokedAt)
	if err != nil || !changed {
		return
	}
	h.activitySeq++
	event := ProgramEventPayload{Kind: ProgramEventActivity, Activity: state.String(), Seq: h.activitySeq, AtMs: now.UnixMilli()}
	if state != vtwasm.ActivityActive {
		event.Tail, _ = h.parser.RenderTail(activityTailRows)
		event.CursorLine, _ = h.parser.CursorLine()
	}
	h.activityFrame = programFrame(event)
	for _, cs := range h.watchers {
		if cs.wantsActivity && cs.queuedBytes() <= maxQueuedClientBytes {
			cs.enqueue(h.activityFrame)
		}
	}
}

func (h *host) resetActivityLocked() {
	h.activityFrame = nil
	h.activity = vtwasm.ActivityClock{}
	if h.parser != nil {
		h.activity = vtwasm.NewActivityClock(h.parser)
	}
}

func wantsActivity(payload []byte) bool {
	var watch WatchPayload
	return len(payload) > 0 && json.Unmarshal(payload, &watch) == nil && watch.Activity
}
```

In `host.go`:
- `clientState` (lines 94-130): add `wantsActivity bool` after `wantsHistory bool`.
- `host` struct: after `appearance        *AppearancePayload` add

```go
	activity      vtwasm.ActivityClock
	activitySeq   uint64
	activityFrame []byte
	pokedAt       time.Time
```
- `newHost` (lines 68-82): after `h.readCond = sync.NewCond(&h.mu)` add

```go
	if cfg.Parser != nil {
		h.activity = vtwasm.NewActivityClock(cfg.Parser)
	}
```
- `applyLargestLocked`: after `_ = h.pty.Resize(bestCols, bestRows)` (line 360) add `h.pokedAt = time.Now()`.
- `run` (line 374): after `go h.runHistoryPersist()` add `go h.runActivityClock()`.
- `deliver` (line 653): after `h.publishProgramLocked()` add `h.publishActivityLocked(time.Now())`.
- line 841: replace `h.serveWatcher(conn, cs, buf)` with `h.serveWatcher(conn, cs, buf, deferred[0].payload)`.
- `handleClientMsg`, `case MsgTerminalInput:` (lines 1076-1080): replace with

```go
	case MsgTerminalInput:
		h.mu.Lock()
		h.pokedAt = time.Now()
		h.mu.Unlock()
		pty := h.currentPTY()
		if _, alive := pty.ExitCode(); !alive {
			_, _ = pty.Write(payload)
		}
```

In `program.go`:
- replace the start of `serveWatcher` (lines 25-29)

```go
func (h *host) serveWatcher(conn net.Conn, cs *clientState, buf []byte) {
	h.mu.Lock()
	h.watchers[conn] = cs
	cs.enqueue(programFrame(ProgramEventPayload{Kind: ProgramEventTitle, Title: h.shownTitle}))
	h.mu.Unlock()
```
with
```go
func (h *host) serveWatcher(conn net.Conn, cs *clientState, buf []byte, payload []byte) {
	cs.wantsActivity = wantsActivity(payload)
	h.mu.Lock()
	h.watchers[conn] = cs
	cs.enqueue(programFrame(ProgramEventPayload{Kind: ProgramEventTitle, Title: h.shownTitle}))
	if cs.wantsActivity && h.activityFrame != nil {
		cs.enqueue(h.activityFrame)
	}
	h.mu.Unlock()
```
- `resetProgramLocked` (line 96): after `h.programGen = 0` add `h.resetActivityLocked()` (respawn calls it after swapping in the new parser, `respawn.go:81-84`, and with `h.parser = nil` on a failed respawn, `respawn.go:73-75`).

- [ ] **Step 4: Run, expect pass; the package**

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ -run 'Activity|Seeded|Echo|PlainWatcher' -count=3 2>&1 | tail -2
go test -race ./internal/adapters/runtime/ptyhost/... 2>&1 | tail -4
```
Expected: `ok` three times over; the race run is `ok` except the pre-existing `TestProcessEnvironmentLetsOverridesWin`.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add backend/internal/adapters/runtime/ptyhost/activity.go backend/internal/adapters/runtime/ptyhost/activity_test.go backend/internal/adapters/runtime/ptyhost/proto.go backend/internal/adapters/runtime/ptyhost/host.go backend/internal/adapters/runtime/ptyhost/program.go
git commit -m "feat(pty-host): publish agent activity transitions with the screen tail to watchers that ask

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Activity events reach the daemon, and only the daemon

**Files:**
- Modify: `backend/internal/ports/terminal_program.go:1-19`; `backend/internal/adapters/runtime/ptyhost/program_watch.go:82` (watch payload), `:119-144` (`recordProgramEvent`); `backend/internal/adapters/runtime/ptyhost/program_watch_test.go` (append); `backend/internal/terminal/programs.go:21-56`; `backend/internal/terminal/programs_test.go` (append)

**Interfaces:**
- Produces (ports): `TerminalProgramActivity TerminalProgramEventKind = "activity"`; `type TerminalActivity string` with `TerminalActivityActive = "active"`, `TerminalActivityIdle = "idle"`, `TerminalActivityPrompting = "prompting"`; `TerminalProgramEvent` gains `Activity TerminalActivity`, `At time.Time`, `Tail string`, `CursorLine string`.
- Produces (terminal): `programFrame(handleID string, event ports.TerminalProgramEvent) (serverMsg, bool)` — false for any kind the renderer does not show.

- [ ] **Step 1: Failing tests**

Append to `backend/internal/adapters/runtime/ptyhost/program_watch_test.go`:

```go
func TestTheProgramWatchAsksForActivityAndDeliversIt(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 923, 80, 24)
	defer f.cancel()
	_, rec := watchedRuntime(t, "sess-act", f)
	writeOutput(t, f, "Overwrite build.log? (y/n) ")
	deadline := time.Now().Add(3 * time.Second)
	for {
		rec.mu.Lock()
		var got *ports.TerminalProgramEvent
		for _, record := range rec.events {
			if record.id == "sess-act" && record.event.Kind == ports.TerminalProgramActivity && record.event.Activity == ports.TerminalActivityPrompting {
				event := record.event
				got = &event
			}
		}
		rec.mu.Unlock()
		if got != nil {
			if got.CursorLine != "Overwrite build.log? (y/n) " || got.At.IsZero() || !strings.Contains(got.Tail, "Overwrite build.log?") {
				t.Fatalf("activity event = %+v", *got)
			}
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("no prompting activity reached the runtime listeners")
		}
		time.Sleep(10 * time.Millisecond)
	}
}
```
(Add `"strings"` to that file's imports.)

Append to `backend/internal/terminal/programs_test.go`:

```go
func TestActivityEventsNeverReachTheProgramsChannel(t *testing.T) {
	src := newProgramSource(&fakeSource{alive: true})
	src.titles["sess-1"] = "Refactor"
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := serveConn(t, mgr, false)
	subscribePrograms(t, mgr, conn)
	recv(t, conn, chPrograms, msgTitle, time.Second)
	src.emit("sess-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, Tail: "screen"})
	assertNoProgramFrame(t, conn, 200*time.Millisecond)
}
```

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ -run TestTheProgramWatchAsksForActivity ./internal/terminal/ -run TestActivityEventsNeverReach 2>&1 | tail -4
```
Expected: build failure, `undefined: ports.TerminalProgramActivity`.

- [ ] **Step 2: Ports**

Replace `backend/internal/ports/terminal_program.go:1-14` (package clause through the `TerminalProgramEvent` struct) with:

```go
package ports

import "time"

type TerminalProgramEventKind string

const (
	TerminalProgramTitle        TerminalProgramEventKind = "title"
	TerminalProgramNotification TerminalProgramEventKind = "notification"
	TerminalProgramActivity     TerminalProgramEventKind = "activity"
)

type TerminalActivity string

const (
	TerminalActivityActive    TerminalActivity = "active"
	TerminalActivityIdle      TerminalActivity = "idle"
	TerminalActivityPrompting TerminalActivity = "prompting"
)

type TerminalProgramEvent struct {
	Kind       TerminalProgramEventKind
	Title      string
	Body       string
	Activity   TerminalActivity
	At         time.Time
	Tail       string
	CursorLine string
}
```

- [ ] **Step 3: Runtime and mux**

In `program_watch.go` replace `frame, _ := EncodeMessage(MsgWatchReq, nil)` with `frame, _ := EncodeMessage(MsgWatchReq, []byte(`{"activity":true}`))`, add `"time"` to the imports, and in `recordProgramEvent` add before `default:`:

```go
	case ProgramEventActivity:
		out = ports.TerminalProgramEvent{
			Kind:       ports.TerminalProgramActivity,
			Activity:   ports.TerminalActivity(event.Activity),
			At:         time.UnixMilli(event.AtMs),
			Tail:       event.Tail,
			CursorLine: event.CursorLine,
		}
```

In `backend/internal/terminal/programs.go` replace `programFrame` and `publishProgramEvent` (lines 21-40) with:

```go
func programFrame(handleID string, event ports.TerminalProgramEvent) (serverMsg, bool) {
	switch event.Kind {
	case ports.TerminalProgramNotification:
		return serverMsg{Ch: chPrograms, ID: handleID, Type: msgNotification, Title: event.Title, Body: event.Body}, true
	case ports.TerminalProgramTitle:
		return serverMsg{Ch: chPrograms, ID: handleID, Type: msgTitle, Title: event.Title}, true
	default:
		return serverMsg{}, false
	}
}

func (m *Manager) publishProgramEvent(handleID string, event ports.TerminalProgramEvent) {
	frame, ok := programFrame(handleID, event)
	if !ok {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	for c := range m.conns {
		c.mu.Lock()
		subscribed := c.programsSubscribed && !c.closed
		c.mu.Unlock()
		if subscribed {
			c.enqueue(frame)
		}
	}
}
```
and in `handlePrograms` replace `c.enqueue(programFrame(id, ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: title}))` with

```go
			frame, _ := programFrame(id, ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: title})
			c.enqueue(frame)
```

- [ ] **Step 4: Run, expect pass**

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... ./internal/ports/... 2>&1 | grep -v "^ok" | tail -5
```
Expected: nothing but the known `TestProcessEnvironmentLetsOverridesWin` line, if any.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add backend/internal/ports/terminal_program.go backend/internal/adapters/runtime/ptyhost/program_watch.go backend/internal/adapters/runtime/ptyhost/program_watch_test.go backend/internal/terminal/programs.go backend/internal/terminal/programs_test.go
git commit -m "feat(daemon): deliver pty-host activity events to program listeners, never to the renderer channel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The merge rule, as a pure domain function

**Files:**
- Create: `backend/internal/domain/screen_reading.go`, `backend/internal/domain/screen_reading_test.go`

**Interfaces:**
- Produces: `type ScreenReading string` with `ScreenWorking = "working"`, `ScreenQuestion = "question"`, `ScreenWaiting = "waiting"`, `ScreenSettled = "settled"`; `(ScreenReading) State() (ActivityState, bool)`; `const HookFreshWindow = 30 * time.Second`; `func MergeScreenReading(current ActivityState, reading ScreenReading, lastHookAt, now time.Time) (ActivityState, bool)`.

- [ ] **Step 1: Failing test**

Create `backend/internal/domain/screen_reading_test.go`:

```go
package domain

import (
	"testing"
	"time"
)

func TestMergeScreenReading(t *testing.T) {
	now := time.Date(2026, 9, 27, 12, 0, 0, 0, time.UTC)
	fresh := now.Add(-10 * time.Second)
	stale := now.Add(-HookFreshWindow)
	var never time.Time
	for _, tc := range []struct {
		name     string
		current  ActivityState
		reading  ScreenReading
		hook     time.Time
		want     ActivityState
		apply    bool
	}{
		{"no hooks: working", ActivityIdle, ScreenWorking, never, ActivityActive, true},
		{"no hooks: question", ActivityActive, ScreenQuestion, never, ActivityBlocked, true},
		{"no hooks: settled", ActivityActive, ScreenSettled, never, ActivityIdle, true},
		{"no hooks: waiting", ActivityActive, ScreenWaiting, never, ActivityWaitingInput, true},
		{"same state is a no-op", ActivityBlocked, ScreenQuestion, never, ActivityBlocked, false},
		{"exited never changes", ActivityExited, ScreenWorking, never, ActivityExited, false},
		{"unknown reading", ActivityIdle, ScreenReading("maybe"), never, ActivityIdle, false},
		{"fresh hook: no demotion to idle", ActivityActive, ScreenSettled, fresh, ActivityActive, false},
		{"fresh hook: no promotion to working", ActivityIdle, ScreenWorking, fresh, ActivityIdle, false},
		{"fresh hook: blocked is not cleared", ActivityBlocked, ScreenWorking, fresh, ActivityBlocked, false},
		{"fresh hook: a question after active fills the gap", ActivityActive, ScreenQuestion, fresh, ActivityBlocked, true},
		{"fresh hook: waiting is not escalated", ActivityWaitingInput, ScreenQuestion, fresh, ActivityWaitingInput, false},
		{"stale hook: settled corrects active", ActivityActive, ScreenSettled, stale, ActivityIdle, true},
		{"stale hook: working clears blocked", ActivityBlocked, ScreenWorking, stale, ActivityActive, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, apply := MergeScreenReading(tc.current, tc.reading, tc.hook, now)
			if got != tc.want || apply != tc.apply {
				t.Fatalf("MergeScreenReading(%s, %s) = (%s, %v), want (%s, %v)", tc.current, tc.reading, got, apply, tc.want, tc.apply)
			}
		})
	}
}
```

```bash
cd "$REPO/backend" && go test ./internal/domain/ -run TestMergeScreenReading 2>&1 | tail -3
```
Expected: build failure, `undefined: ScreenReading`.

- [ ] **Step 2: Implementation**

Create `backend/internal/domain/screen_reading.go`:

```go
package domain

import "time"

type ScreenReading string

const (
	ScreenWorking  ScreenReading = "working"
	ScreenQuestion ScreenReading = "question"
	ScreenWaiting  ScreenReading = "waiting"
	ScreenSettled  ScreenReading = "settled"
)

const HookFreshWindow = 30 * time.Second

func (r ScreenReading) State() (ActivityState, bool) {
	switch r {
	case ScreenWorking:
		return ActivityActive, true
	case ScreenQuestion:
		return ActivityBlocked, true
	case ScreenWaiting:
		return ActivityWaitingInput, true
	case ScreenSettled:
		return ActivityIdle, true
	default:
		return "", false
	}
}

func MergeScreenReading(current ActivityState, reading ScreenReading, lastHookAt, now time.Time) (ActivityState, bool) {
	target, ok := reading.State()
	if !ok || current == ActivityExited || target == current {
		return current, false
	}
	if !lastHookAt.IsZero() && now.Sub(lastHookAt) < HookFreshWindow {
		if reading == ScreenQuestion && current == ActivityActive {
			return target, true
		}
		return current, false
	}
	return target, true
}
```

- [ ] **Step 3: Run, expect pass**

```bash
cd "$REPO/backend" && go test ./internal/domain/ 2>&1 | tail -1
```
Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add backend/internal/domain/screen_reading.go backend/internal/domain/screen_reading_test.go
git commit -m "feat(domain): the rule that merges a screen reading with hook state

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: The lifecycle reducer applies screen readings under the merge rule

**Files:**
- Create: `backend/internal/lifecycle/screen_signal_test.go`
- Modify: `backend/internal/ports/runtime_observations.go:29-33` (event names), `:47-86` (`ActivitySignal` fields); `backend/internal/lifecycle/manager.go:155-163` (fields), `:216-230` (`New`), `:618-621` (terminated cleanup), `:631-635` (merge after the revision fence), `:716-718` (`FirstSignalAt`), `:737-743` (one alert per question), `:1028` (screen clears a blocked dialog)

**Interfaces:**
- Consumes: `domain.MergeScreenReading`, `domain.HookFreshWindow` (Task 8).
- Produces (ports): `EventScreenWorking = "screen-working"`, `EventScreenQuestion = "screen-question"`, `EventScreenWaiting = "screen-waiting"`, `EventScreenSettled = "screen-settled"`; `func IsScreenEvent(event string) bool` (the `screen-` and the existing observer's `terminal-` prefixes, `observe/activity/observer.go:136-139`); `func ScreenEvent(reading domain.ScreenReading) string`; `ActivitySignal` gains `ScreenReading domain.ScreenReading`, `ScreenIdentity string`, `ScreenText string`.
- Produces (lifecycle, memory-only): `hookAt map[domain.SessionID]time.Time`, `alerted map[domain.SessionID]alertedQuestion`; `const questionRealertAfter = 2 * time.Minute`.

- [ ] **Step 1: Failing tests**

Create `backend/internal/lifecycle/screen_signal_test.go`:

```go
package lifecycle

import (
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func screenSignal(reading domain.ScreenReading, identity string) ports.ActivitySignal {
	return ports.ActivitySignal{Valid: true, Event: ports.ScreenEvent(reading), ScreenReading: reading, ScreenIdentity: identity, ScreenText: identity}
}

func movableClock(m *Manager, start time.Time) *time.Time {
	current := start
	m.clock = func() time.Time { return current }
	return &current
}

func TestScreen_QuestionWithoutHooksBlocksAndAlertsOnce(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityActive)
	movableClock(m, now)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenQuestion, "Allow rm? 1. Yes 2. No")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityBlocked {
		t.Fatalf("state = %q, want blocked", got)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("needs_input intents = %+v, want one", got)
	}
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenQuestion, "Allow rm? 1. Yes 2. No")); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("a repeated reading alerted again: %+v", got)
	}
}

func TestScreen_FreshHookBlocksDemotionUntilStale(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityIdle)
	clock := movableClock(m, now)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "pre-tool-use", ToolName: "Bash", ToolUseID: "t1"}); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(10 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenSettled, "")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityActive {
		t.Fatalf("a fresh hook was overridden: state = %q", got)
	}
	*clock = now.Add(domain.HookFreshWindow + time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenSettled, "")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityIdle {
		t.Fatalf("a stale hook was not corrected: state = %q", got)
	}
	if got := intentsOf(sink, domain.NotificationTurnFinished); len(got) != 1 {
		t.Fatalf("turn_finished intents = %+v, want one for the corrected turn", got)
	}
}

func TestScreen_LateHookAfterScreenQuestionAlertsOnce(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityActive)
	clock := movableClock(m, now)
	question := screenSignal(domain.ScreenQuestion, "Bash echo first Do you want to proceed? 1. Yes 2. No")
	if err := m.ApplyActivitySignal(ctx, "mer-1", question); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityBlocked, Event: "permission-request", ToolName: "Bash"}); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(2 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit"}); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityActive {
		t.Fatalf("a fresh hook lost: state = %q", got)
	}
	*clock = now.Add(2*time.Second + domain.HookFreshWindow)
	if err := m.ApplyActivitySignal(ctx, "mer-1", question); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityBlocked {
		t.Fatalf("the re-asserted question did not apply: state = %q", got)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("one question alerted %d times: %+v", len(got), got)
	}
}

func TestScreen_ADifferentQuestionAlertsAgain(t *testing.T) {
	m, _, sink, now := alertManager(t, domain.ActivityActive)
	clock := movableClock(m, now)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenQuestion, "first")); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(5 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenWorking, "")); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(9 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenQuestion, "second")); err != nil {
		t.Fatal(err)
	}
	if got := intentsOf(sink, domain.NotificationNeedsInput); len(got) != 2 {
		t.Fatalf("two questions gave %d alerts", len(got))
	}
	if got := resolutionsOf(sink, domain.NotificationNeedsInput); len(got) != 1 {
		t.Fatalf("the first question was not resolved: %+v", got)
	}
}

func TestScreen_SignalsNeverSetFirstSignalAt(t *testing.T) {
	m, st, _, now := alertManager(t, domain.ActivityIdle)
	movableClock(m, now)
	rec := st.sessions["mer-1"]
	rec.FirstSignalAt = time.Time{}
	st.sessions["mer-1"] = rec
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenWorking, "")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"]; got.Activity.State != domain.ActivityActive || !got.FirstSignalAt.IsZero() {
		t.Fatalf("session = %+v, want active with no first signal", got)
	}
}

func TestScreen_SameStateScreenSignalIsANoOp(t *testing.T) {
	m, st, sink, now := alertManager(t, domain.ActivityBlocked)
	movableClock(m, now)
	before := st.sessions["mer-1"]
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenQuestion, "q")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"]; !got.UpdatedAt.Equal(before.UpdatedAt) || len(sink.intents) != 0 {
		t.Fatalf("a same-state reading wrote %+v and intents %+v", got, sink.intents)
	}
}

func TestScreen_SettledClearsAStaleBlockedDialog(t *testing.T) {
	m, st, _, now := alertManager(t, domain.ActivityBlocked)
	movableClock(m, now)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenSettled, "")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityIdle {
		t.Fatalf("state = %q, want idle", got)
	}
}

func TestScreen_NeverResurrectsAnExitedAgent(t *testing.T) {
	m, st, _, now := alertManager(t, domain.ActivityExited)
	movableClock(m, now)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenWorking, "")); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Activity.State; got != domain.ActivityExited {
		t.Fatalf("state = %q, want exited", got)
	}
}
```

```bash
cd "$REPO/backend" && go test ./internal/lifecycle/ -run TestScreen_ 2>&1 | tail -3
```
Expected: build failure, `undefined: ports.ScreenEvent` / `unknown field ScreenReading`.

- [ ] **Step 2: Ports**

In `backend/internal/ports/runtime_observations.go` after `const EventUserInterrupt = "user-interrupt"` (line 33) add:

```go
const (
	EventScreenWorking  = "screen-working"
	EventScreenQuestion = "screen-question"
	EventScreenWaiting  = "screen-waiting"
	EventScreenSettled  = "screen-settled"
)

func ScreenEvent(reading domain.ScreenReading) string {
	return "screen-" + string(reading)
}

func IsScreenEvent(event string) bool {
	return strings.HasPrefix(event, "screen-") || strings.HasPrefix(event, "terminal-")
}
```
(add `"strings"` to the imports), and inside `ActivitySignal`, after `InteractionID string` (line 85), add:

```go
	ScreenReading  domain.ScreenReading
	ScreenIdentity string
	ScreenText     string
```

- [ ] **Step 3: Reducer**

In `backend/internal/lifecycle/manager.go`:
- After `flights map[domain.SessionID]*toolFlight` (line 163) add

```go
	hookAt  map[domain.SessionID]time.Time
	alerted map[domain.SessionID]alertedQuestion
```
and before `const quietInputWindow = 3 * time.Second` (line 188) add

```go
type alertedQuestion struct {
	identity string
	at       time.Time
}

const questionRealertAfter = 2 * time.Minute
```
- In `New`, after `flights:         map[domain.SessionID]*toolFlight{},` add

```go
		hookAt:          map[domain.SessionID]time.Time{},
		alerted:         map[domain.SessionID]alertedQuestion{},
```
- In `ApplyActivitySignal`, the terminated branch (lines 618-621): after `delete(m.flights, id)` add `delete(m.hookAt, id)` and `delete(m.alerted, id)`.
- After the revision fence (the block ending at line 635, `if !s.ExpectedUpdatedAt.IsZero() && … return nil }`) insert:

```go
	if s.Valid && s.ScreenReading != "" {
		merged, apply := domain.MergeScreenReading(rec.Activity.State, s.ScreenReading, m.hookAt[id], now)
		if !apply {
			m.mu.Unlock()
			return nil
		}
		s.State = merged
	} else if s.Valid && !ports.IsScreenEvent(s.Event) {
		m.hookAt[id] = now
	}
```
- Replace `if next.FirstSignalAt.IsZero() {` (line 716) with `if next.FirstSignalAt.IsZero() && s.ScreenReading == "" {`.
- Replace

```go
	case !rec.Activity.State.NeedsInput() && next.Activity.State.NeedsInput() && !next.IsTerminated:
		intent = m.sessionIntent(domain.NotificationNeedsInput, next)
```
with
```go
	case !rec.Activity.State.NeedsInput() && next.Activity.State.NeedsInput() && !next.IsTerminated:
		if !m.alertedRecently(id, s.ScreenIdentity, now) {
			intent = m.sessionIntent(domain.NotificationNeedsInput, next)
		}
		if s.ScreenIdentity != "" {
			m.alerted[id] = alertedQuestion{identity: s.ScreenIdentity, at: now}
		}
```
and immediately after the `switch { … }` that picks `intent` (before `resolutions := sessionResolutions(rec, next, now)`) add

```go
	if next.Activity.State == domain.ActivityIdle {
		delete(m.alerted, id)
	}
```
- Add the helper after `sessionIntent` (line ~466):

```go
func (m *Manager) alertedRecently(id domain.SessionID, identity string, now time.Time) bool {
	if identity == "" {
		return false
	}
	last, ok := m.alerted[id]
	return ok && last.identity == identity && now.Sub(last.at) < questionRealertAfter
}
```
- In `applyToolPrecedenceLocked`, replace `case isTurnBoundaryEvent(s.Event), s.Event == ports.EventDialogAbsent:` (line 1028) with

```go
		case isTurnBoundaryEvent(s.Event), s.Event == ports.EventDialogAbsent,
			s.Event == ports.EventScreenWorking, s.Event == ports.EventScreenSettled, s.Event == ports.EventScreenWaiting:
```
(The needs-input switch runs while `m.mu` is held, `manager.go:737-760`, so the `alerted` map is guarded like `flights`.)

- [ ] **Step 4: Run, expect pass; the reducer's whole suite**

```bash
cd "$REPO/backend" && go test ./internal/lifecycle/ -run TestScreen_ -v 2>&1 | grep -E "^(--- |ok|FAIL)"
go test -race ./internal/lifecycle/... ./internal/ports/... 2>&1 | tail -3
```
Expected: eight `--- PASS: TestScreen_…`; the lifecycle suite `ok` (every existing test still passes: hooks stamp `hookAt` and nothing else changes for them).

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add backend/internal/ports/runtime_observations.go backend/internal/lifecycle/manager.go backend/internal/lifecycle/screen_signal_test.go
git commit -m "feat(lifecycle): apply screen readings under the hook-first merge rule, one alert per question

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 10: Agent screen readers — questions for Claude Code and Codex, idle for Claude Code

**Files:**
- Create: `backend/internal/adapters/agent/terminalui/question.go`, `question_test.go`; `backend/internal/adapters/agent/claudecode/question.go`, `terminal_activity.go`, `question_test.go`; `backend/internal/adapters/agent/codex/question.go`, `question_test.go`
- Modify: `backend/internal/ports/agent.go:218-222` (after `TerminalDialogReader`); `backend/internal/observe/activity/observer_test.go:158-176` (the "other harness" test used Claude Code, which now has a detector)

**Interfaces:**
- Produces (ports): `type TerminalQuestion struct { Text string; Identity string }`; `type TerminalQuestionReader interface { ReadQuestion(pane string) (TerminalQuestion, bool) }`.
- Produces (terminalui): `LastNumberedMenu(lines []string, marker string) (ports.Menu, int, bool)` (the menu that starts at the last row numbered `1.`; its index); `Question(context []string, menu ports.Menu) ports.TerminalQuestion` (`Text` = the last three non-rule context lines joined with ` · `; `Identity` = context and rows joined and whitespace-collapsed, so a rewrap gives the same identity).
- Produces: `(*claudecode.Plugin).ReadQuestion`, `(*claudecode.Plugin).DetectTerminalActivity` (idle only when the `❯` composer sits under a rule line, no `esc to interrupt` in the last 12 lines, and no dialog is open), `(*codex.Plugin).ReadQuestion`.
- Side effect to know: Claude Code now implements `ports.TerminalActivityDetector`, so the existing 30 s poller also corrects a Claude Code session stuck `active` for 2 minutes with an idle composer (`observe/activity/observer.go:117-119`) — the "check on hooks" the wishlist asks for, on the old path too.

- [ ] **Step 1: Failing tests**

Create `backend/internal/adapters/agent/terminalui/question_test.go`:

```go
package terminalui

import (
	"testing"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func TestLastNumberedMenuSkipsNumberedTextAboveTheLiveMenu(t *testing.T) {
	lines := []string{"Plan:", "1. Read the file", "2. Edit it", "Allow command?", "› 1. Yes, proceed", "2. No"}
	menu, start, ok := LastNumberedMenu(lines, "›")
	if !ok || start != 4 || len(menu.Rows) != 2 || menu.Selected != 0 {
		t.Fatalf("menu = %+v start=%d ok=%v", menu, start, ok)
	}
}

func TestQuestionIdentityIgnoresHowTheTextWrapped(t *testing.T) {
	menu := ports.Menu{Rows: []string{"1. Yes", "2. No"}, Selected: 0}
	wide := Question([]string{"Bash command", "rm -rf build dist node_modules", "Do you want to proceed?"}, menu)
	narrow := Question([]string{"Bash command", "rm -rf build dist", "node_modules", "Do you want to proceed?"}, menu)
	if wide.Identity != narrow.Identity {
		t.Fatalf("identities differ:\n%q\n%q", wide.Identity, narrow.Identity)
	}
	if wide.Text != "Bash command · rm -rf build dist node_modules · Do you want to proceed?" {
		t.Fatalf("text = %q", wide.Text)
	}
}

func TestQuestionTextSkipsRuleLines(t *testing.T) {
	got := Question([]string{"Which colour do you prefer?", "────────"}, ports.Menu{Rows: []string{"1. Red", "2. Blue"}})
	if got.Text != "Which colour do you prefer?" {
		t.Fatalf("text = %q", got.Text)
	}
}
```

Create `backend/internal/adapters/agent/claudecode/question_test.go`:

```go
package claudecode

import (
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const claudeWorkingPane = "✽ Flambéing… (13s · still thinking with high effort)\n" +
	"────────────────────────────────────────\n❯ \n────────────────────────────────────────\n" +
	"  ⏵⏵ auto mode on (shift+tab to cycle) · esc to interrupt · ← for agents\n"

func TestReadQuestionReadsPermissionAndQuestionDialogs(t *testing.T) {
	p := &Plugin{}
	permission, ok := p.ReadQuestion(readPane(t, "claudecode_permission.txt"))
	if !ok || !strings.Contains(permission.Text, "Do you want to create fixture-probe.txt?") || permission.Identity == "" {
		t.Fatalf("permission = %+v, %v", permission, ok)
	}
	question, ok := p.ReadQuestion(readPane(t, "claudecode_question.txt"))
	if !ok || !strings.Contains(question.Text, "Which colour do you prefer?") {
		t.Fatalf("question = %+v, %v", question, ok)
	}
	for _, name := range []string{"claudecode_model_picker.txt", "claudecode_idle.txt"} {
		if got, ok := p.ReadQuestion(readPane(t, name)); ok {
			t.Fatalf("%s read as a question: %+v", name, got)
		}
	}
}

func TestDetectTerminalActivityReadsTheComposer(t *testing.T) {
	p := &Plugin{}
	if state, ok := p.DetectTerminalActivity(readPane(t, "claudecode_idle.txt")); !ok || state != domain.ActivityIdle {
		t.Fatalf("idle pane = (%q, %v), want idle", state, ok)
	}
	if state, ok := p.DetectTerminalActivity(claudeWorkingPane); ok {
		t.Fatalf("working pane = (%q, %v), want no reading", state, ok)
	}
	for _, name := range []string{"claudecode_permission.txt", "claudecode_question.txt"} {
		if state, ok := p.DetectTerminalActivity(readPane(t, name)); ok {
			t.Fatalf("%s = (%q, %v), want no reading while a dialog is open", name, state, ok)
		}
	}
}
```

Create `backend/internal/adapters/agent/codex/question_test.go`:

```go
package codex

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadQuestionReadsAnApprovalPicker(t *testing.T) {
	pane := "• Running touch approved.txt\nAllow command `touch approved.txt`?\n› 1. Approve once\n  2. Deny\nPress enter to confirm or esc to go back\n"
	got, ok := (&Plugin{}).ReadQuestion(pane)
	if !ok || got.Text != "• Running touch approved.txt · Allow command `touch approved.txt`?" || got.Identity == "" {
		t.Fatalf("ReadQuestion = %+v, %v", got, ok)
	}
}

func TestReadQuestionIgnoresTheComposerTheModelPickerAndWork(t *testing.T) {
	for _, name := range []string{"codex_idle.txt", "codex_model_picker.txt"} {
		raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "testdata", "panes", name))
		if err != nil {
			t.Fatalf("read %s: %v", name, err)
		}
		if got, ok := (&Plugin{}).ReadQuestion(string(raw)); ok {
			t.Fatalf("%s read as a question: %+v", name, got)
		}
	}
	working := "Allow command?\n› 1. Approve once\n  2. Deny\n• Working (3s • esc to interrupt)\n"
	if got, ok := (&Plugin{}).ReadQuestion(working); ok {
		t.Fatalf("a working screen read as a question: %+v", got)
	}
}
```
(`codex_model_picker.txt` has `Select Model and Effort` above its numbered menu: evidence `codex/dialog.go:21-23`.)

In `backend/internal/observe/activity/observer_test.go` `TestPollLeavesOtherHarnessesUntouched` (lines 158-176): replace `activeSession(now, domain.HarnessClaudeCode)` with `activeSession(now, domain.HarnessAider)` and `fakeAgents{domain.HarnessClaudeCode: claudecode.New()}` with `fakeAgents{domain.HarnessAider: aider.New()}`; replace the `claudecode` import with `"github.com/OmarAly92/operator/backend/internal/adapters/agent/aider"` if `claudecode` is no longer used in the file (grep first).

```bash
cd "$REPO/backend" && go test ./internal/adapters/agent/terminalui/ ./internal/adapters/agent/claudecode/ ./internal/adapters/agent/codex/ 2>&1 | tail -5
```
Expected: build failures, `undefined: LastNumberedMenu`, `p.ReadQuestion undefined`.

- [ ] **Step 2: Implementation**

In `backend/internal/ports/agent.go`, after the `TerminalDialogReader` interface (line 222) add:

```go
type TerminalQuestion struct {
	Text     string
	Identity string
}

type TerminalQuestionReader interface {
	ReadQuestion(pane string) (TerminalQuestion, bool)
}
```

Create `backend/internal/adapters/agent/terminalui/question.go`:

```go
package terminalui

import (
	"strings"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

func LastNumberedMenu(lines []string, marker string) (ports.Menu, int, bool) {
	for i := len(lines) - 1; i >= 0; i-- {
		row := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(lines[i]), marker))
		if !strings.HasPrefix(row, "1. ") {
			continue
		}
		menu, ok := ReadNumberedMenu(lines[i:], marker)
		return menu, i, ok
	}
	return ports.Menu{}, -1, false
}

func Question(context []string, menu ports.Menu) ports.TerminalQuestion {
	var text []string
	for _, line := range context {
		line = strings.TrimSpace(line)
		if line == "" || strings.Trim(line, "─━═╌┄│╭╮╰╯ ") == "" {
			continue
		}
		text = append(text, line)
	}
	text = text[max(0, len(text)-3):]
	parts := append(append([]string{}, context...), menu.Rows...)
	return ports.TerminalQuestion{
		Text:     strings.Join(text, " · "),
		Identity: strings.Join(strings.Fields(strings.Join(parts, " ")), " "),
	}
}
```
(In the wrap test the `Text` of `wide` keeps three lines; `narrow` has four, so its `Text` differs — only `Identity` must be wrap-insensitive.)

Create `backend/internal/adapters/agent/claudecode/question.go`:

```go
package claudecode

import (
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (p *Plugin) ReadQuestion(pane string) (ports.TerminalQuestion, bool) {
	dialog, ok := p.ReadDialog(pane)
	if !ok || dialog.Kind == ports.DialogModel {
		return ports.TerminalQuestion{}, false
	}
	lines := paneLines(pane)
	_, start, ok := terminalui.LastNumberedMenu(lines, "❯")
	if !ok {
		return ports.TerminalQuestion{}, false
	}
	return terminalui.Question(lines[max(0, start-6):start], dialog.Menu), true
}

var _ ports.TerminalQuestionReader = (*Plugin)(nil)
```

Create `backend/internal/adapters/agent/claudecode/terminal_activity.go`:

```go
package claudecode

import (
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (p *Plugin) DetectTerminalActivity(output string) (domain.ActivityState, bool) {
	lines := paneLines(output)
	tail := lines[max(0, len(lines)-12):]
	composer := false
	for i, line := range tail {
		if strings.Contains(strings.ToLower(line), "esc to interrupt") {
			return "", false
		}
		if i > 0 && strings.HasPrefix(line, "❯") && isRuleLine(tail[i-1]) {
			composer = true
		}
	}
	if !composer {
		return "", false
	}
	if _, open := p.ReadDialog(output); open {
		return "", false
	}
	return domain.ActivityIdle, true
}

func isRuleLine(line string) bool {
	return line != "" && strings.Trim(line, "─") == ""
}

var _ ports.TerminalActivityDetector = (*Plugin)(nil)
```

Create `backend/internal/adapters/agent/codex/question.go`:

```go
package codex

import (
	"strings"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (p *Plugin) ReadQuestion(pane string) (ports.TerminalQuestion, bool) {
	lines := terminalLines(pane)
	lines = lines[max(0, len(lines)-24):]
	for _, line := range lines {
		if strings.Contains(strings.ToLower(line), "esc to interrupt") || line == "Select Model and Effort" {
			return ports.TerminalQuestion{}, false
		}
	}
	menu, start, ok := terminalui.LastNumberedMenu(lines, "›")
	if !ok {
		return ports.TerminalQuestion{}, false
	}
	return terminalui.Question(lines[max(0, start-6):start], menu), true
}

var _ ports.TerminalQuestionReader = (*Plugin)(nil)
```

- [ ] **Step 3: Run, expect pass; everything that uses the adapters**

```bash
cd "$REPO/backend" && go test ./internal/adapters/agent/... ./internal/observe/... ./internal/session_manager/... ./internal/adapters/runtime/parity/... 2>&1 | grep -v "^ok" | tail -8
```
Expected: no output (all `ok`). If a session-manager test that drives Claude Code's prompt readiness changes behaviour because Claude Code now has a detector (`ports/agent.go:170-176` says an authoritative idle detection takes precedence over readiness patterns), read the failure: the detector must answer idle only at an idle composer; fix the detector with a failing test from that test's pane, not the other test.

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add backend/internal/ports/agent.go backend/internal/adapters/agent/terminalui/question.go backend/internal/adapters/agent/terminalui/question_test.go backend/internal/adapters/agent/claudecode/question.go backend/internal/adapters/agent/claudecode/terminal_activity.go backend/internal/adapters/agent/claudecode/question_test.go backend/internal/adapters/agent/codex/question.go backend/internal/adapters/agent/codex/question_test.go backend/internal/observe/activity/observer_test.go
git commit -m "feat(agents): read Claude Code and Codex questions and Claude Code's idle composer from the screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Screen readings and the debouncer (pure)

**Files:**
- Create: `backend/internal/observe/screen/classify.go`, `classify_test.go`, `debounce.go`, `debounce_test.go`

**Interfaces:**
- Consumes: `ports.TerminalProgramEvent` (Task 7), `ports.TerminalQuestionReader` (Task 10), `ports.TerminalActivityDetector` (`ports/agent.go:179-181`), `domain.ScreenReading` (Task 8).
- Produces: `ScreenActiveConfirm = 3 * time.Second`, `ScreenQuestionConfirm = time.Second`, `ScreenSettleConfirm = 2 * time.Second`, `ScreenQuietSettle = 60 * time.Second`; `type Observation struct { Reading domain.ScreenReading; Identity, Text string; Confirm time.Duration }`; `type Decision struct { Reading domain.ScreenReading; Identity, Text string }`; `func Classify(agent any, event ports.TerminalProgramEvent) Observation`; `type Debouncer struct` with `Observe(obs Observation, at time.Time) []Decision` and `Due(now time.Time) []Decision`.

- [ ] **Step 1: Failing tests**

Create `backend/internal/observe/screen/debounce_test.go`:

```go
package screen

import (
	"reflect"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

var t0 = time.Date(2026, 9, 27, 12, 0, 0, 0, time.UTC)

func working() Observation {
	return Observation{Reading: domain.ScreenWorking, Confirm: ScreenActiveConfirm}
}

func question(identity string) Observation {
	return Observation{Reading: domain.ScreenQuestion, Identity: identity, Text: identity, Confirm: ScreenQuestionConfirm}
}

func settled(confirm time.Duration) Observation {
	return Observation{Reading: domain.ScreenSettled, Confirm: confirm}
}

func readings(decisions []Decision) []domain.ScreenReading {
	var out []domain.ScreenReading
	for _, d := range decisions {
		out = append(out, d.Reading)
	}
	return out
}

func TestDebouncerConfirmsAfterEachHoldTime(t *testing.T) {
	var d Debouncer
	if got := d.Observe(working(), t0); got != nil {
		t.Fatalf("working confirmed at once: %+v", got)
	}
	if got := d.Due(t0.Add(ScreenActiveConfirm - time.Millisecond)); got != nil {
		t.Fatalf("working confirmed early: %+v", got)
	}
	if got := readings(d.Due(t0.Add(ScreenActiveConfirm))); !reflect.DeepEqual(got, []domain.ScreenReading{domain.ScreenWorking}) {
		t.Fatalf("working = %v", got)
	}
	d.Observe(question("q"), t0.Add(10*time.Second))
	if got := readings(d.Due(t0.Add(11 * time.Second))); !reflect.DeepEqual(got, []domain.ScreenReading{domain.ScreenQuestion}) {
		t.Fatalf("question = %v", got)
	}
}

func TestDebouncerARepaintBurstDoesNotLeaveTheQuestion(t *testing.T) {
	var d Debouncer
	d.Observe(question("q"), t0)
	d.Due(t0.Add(time.Second))
	d.Observe(working(), t0.Add(5*time.Second))
	if got := d.Observe(question("q"), t0.Add(6500*time.Millisecond)); got != nil {
		t.Fatalf("a repaint changed the reading: %+v", got)
	}
	if got := d.Due(t0.Add(time.Minute)); got != nil {
		t.Fatalf("a repaint left a pending reading: %+v", got)
	}
}

func TestDebouncerTheSameQuestionAfterARepaintIsNotNew(t *testing.T) {
	var d Debouncer
	d.Observe(question("q"), t0)
	first := d.Due(t0.Add(time.Second))
	d.Observe(working(), t0.Add(2*time.Second))
	d.Observe(question("q"), t0.Add(3*time.Second))
	if len(first) != 1 || d.Due(t0.Add(10*time.Second)) != nil {
		t.Fatalf("first=%+v and a second decision for the same question", first)
	}
}

func TestDebouncerTwoDifferentQuestionsAreTwoDecisions(t *testing.T) {
	var d Debouncer
	d.Observe(question("first"), t0)
	d.Due(t0.Add(time.Second))
	d.Observe(working(), t0.Add(5*time.Second))
	d.Observe(question("second"), t0.Add(6*time.Second))
	got := d.Due(t0.Add(7 * time.Second))
	want := []Decision{{Reading: domain.ScreenWorking}, {Reading: domain.ScreenQuestion, Identity: "second", Text: "second"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("decisions = %+v, want %+v", got, want)
	}
}

func TestDebouncerAFortySecondSilenceIsNotSettledWithoutADetector(t *testing.T) {
	var d Debouncer
	d.Observe(working(), t0)
	d.Due(t0.Add(ScreenActiveConfirm))
	d.Observe(settled(ScreenQuietSettle), t0.Add(5*time.Second))
	if got := d.Due(t0.Add(45 * time.Second)); got != nil {
		t.Fatalf("a 40 s silence settled: %+v", got)
	}
	d.Observe(working(), t0.Add(45*time.Second))
	if got := d.Due(t0.Add(5 * time.Minute)); got != nil {
		t.Fatalf("output after the silence left a decision: %+v", got)
	}
}

func TestDebouncerLeavingAnAnsweredQuestionSettlesQuickly(t *testing.T) {
	var d Debouncer
	d.Observe(question("q"), t0)
	d.Due(t0.Add(time.Second))
	d.Observe(settled(ScreenQuietSettle), t0.Add(4*time.Second))
	if got := readings(d.Due(t0.Add(4*time.Second + ScreenSettleConfirm))); !reflect.DeepEqual(got, []domain.ScreenReading{domain.ScreenSettled}) {
		t.Fatalf("after the question went away = %v, want settled within %v", got, ScreenSettleConfirm)
	}
}

func TestDebouncerAnUnreadableScreenCancelsWhatWasPending(t *testing.T) {
	var d Debouncer
	d.Observe(settled(ScreenSettleConfirm), t0)
	d.Observe(Observation{}, t0.Add(time.Second))
	if got := d.Due(t0.Add(time.Minute)); got != nil {
		t.Fatalf("pending reading survived an unreadable screen: %+v", got)
	}
}
```

Create `backend/internal/observe/screen/classify_test.go`:

```go
package screen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/codex"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func pane(t *testing.T, name string) string {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "testdata", "panes", name))
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	return string(raw)
}

func activity(state ports.TerminalActivity, tail, cursor string) ports.TerminalProgramEvent {
	return ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: state, Tail: tail, CursorLine: cursor}
}

func TestClassify(t *testing.T) {
	claude := claudecode.New()
	for _, tc := range []struct {
		name    string
		agent   any
		event   ports.TerminalProgramEvent
		reading domain.ScreenReading
		confirm time.Duration
		text    string
	}{
		{"output is working", claude, activity(ports.TerminalActivityActive, "", ""), domain.ScreenWorking, ScreenActiveConfirm, ""},
		{"a Claude Code permission dialog", claude, activity(ports.TerminalActivityIdle, pane(t, "claudecode_permission.txt"), ""), domain.ScreenQuestion, ScreenQuestionConfirm, "Do you want to create fixture-probe.txt?"},
		{"a Claude Code idle composer", claude, activity(ports.TerminalActivityIdle, pane(t, "claudecode_idle.txt"), ""), domain.ScreenSettled, ScreenSettleConfirm, ""},
		{"Claude Code ignores a y/n typed into its composer", claude, activity(ports.TerminalActivityPrompting, pane(t, "claudecode_idle.txt"), "❯ ok? (y/n) "), domain.ScreenSettled, ScreenSettleConfirm, ""},
		{"a Codex approval picker", codex.New(), activity(ports.TerminalActivityIdle, "Allow command?\n› 1. Approve once\n  2. Deny\n", ""), domain.ScreenQuestion, ScreenQuestionConfirm, "Allow command?"},
		{"a Codex idle composer", codex.New(), activity(ports.TerminalActivityIdle, pane(t, "codex_idle.txt"), ""), domain.ScreenSettled, ScreenSettleConfirm, ""},
		{"no adapter: a prompt at the cursor", nil, activity(ports.TerminalActivityPrompting, "Overwrite build.log? (y/n) ", "Overwrite build.log? (y/n) "), domain.ScreenQuestion, ScreenQuestionConfirm, "Overwrite build.log? (y/n)"},
		{"no adapter: quiet is settled only after a minute", nil, activity(ports.TerminalActivityIdle, "compiling", ""), domain.ScreenSettled, ScreenQuietSettle, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := Classify(tc.agent, tc.event)
			if got.Reading != tc.reading || got.Confirm != tc.confirm || !strings.Contains(got.Text, tc.text) {
				t.Fatalf("Classify = %+v, want %s after %v with text %q", got, tc.reading, tc.confirm, tc.text)
			}
		})
	}
	if got := Classify(claude, activity(ports.TerminalActivityIdle, "✽ Thinking… (3s)\n  esc to interrupt\n", "")); got.Reading != "" {
		t.Fatalf("a working Claude Code screen read as %+v", got)
	}
	if got := Classify(claude, ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "x"}); got.Reading != "" {
		t.Fatalf("a title read as %+v", got)
	}
}
```

```bash
cd "$REPO/backend" && go test ./internal/observe/screen/ 2>&1 | tail -3
```
Expected: build failure, `undefined: Debouncer` / `undefined: Classify`.

- [ ] **Step 2: Implementation**

Create `backend/internal/observe/screen/debounce.go`:

```go
package screen

import (
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type Observation struct {
	Reading  domain.ScreenReading
	Identity string
	Text     string
	Confirm  time.Duration
}

type Decision struct {
	Reading  domain.ScreenReading
	Identity string
	Text     string
}

type Debouncer struct {
	pending   *Observation
	pendingAt time.Time
	applied   *Decision
	sawActive bool
}

func (d *Debouncer) Observe(obs Observation, at time.Time) []Decision {
	if obs.Reading == "" {
		d.pending = nil
		return nil
	}
	if obs.Reading == domain.ScreenWorking {
		d.sawActive = true
	}
	if d.applied != nil && d.applied.Reading == obs.Reading && d.applied.Identity == obs.Identity {
		d.pending = nil
		if obs.Reading != domain.ScreenWorking {
			d.sawActive = false
		}
		return nil
	}
	if d.applied != nil && d.applied.Reading == domain.ScreenQuestion && obs.Reading == domain.ScreenSettled && obs.Confirm > ScreenSettleConfirm {
		obs.Confirm = ScreenSettleConfirm
	}
	if d.pending == nil || d.pending.Reading != obs.Reading || d.pending.Identity != obs.Identity {
		pending := obs
		d.pending = &pending
		d.pendingAt = at
	}
	return d.Due(at)
}

func (d *Debouncer) Due(now time.Time) []Decision {
	if d.pending == nil || now.Sub(d.pendingAt) < d.pending.Confirm {
		return nil
	}
	obs := *d.pending
	d.pending = nil
	var out []Decision
	if obs.Reading == domain.ScreenQuestion && d.applied != nil && d.applied.Reading == domain.ScreenQuestion && d.sawActive {
		out = append(out, Decision{Reading: domain.ScreenWorking})
	}
	decision := Decision{Reading: obs.Reading, Identity: obs.Identity, Text: obs.Text}
	out = append(out, decision)
	d.applied = &decision
	if obs.Reading != domain.ScreenWorking {
		d.sawActive = false
	}
	return out
}
```

Create `backend/internal/observe/screen/classify.go`:

```go
package screen

import (
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

const (
	ScreenActiveConfirm   = 3 * time.Second
	ScreenQuestionConfirm = time.Second
	ScreenSettleConfirm   = 2 * time.Second
	ScreenQuietSettle     = 60 * time.Second
)

func Classify(agent any, event ports.TerminalProgramEvent) Observation {
	if event.Kind != ports.TerminalProgramActivity {
		return Observation{}
	}
	switch event.Activity {
	case ports.TerminalActivityActive:
		return Observation{Reading: domain.ScreenWorking, Confirm: ScreenActiveConfirm}
	case ports.TerminalActivityIdle, ports.TerminalActivityPrompting:
	default:
		return Observation{}
	}
	if reader, ok := agent.(ports.TerminalQuestionReader); ok {
		if question, ok := reader.ReadQuestion(event.Tail); ok {
			return Observation{Reading: domain.ScreenQuestion, Identity: question.Identity, Text: question.Text, Confirm: ScreenQuestionConfirm}
		}
	} else if event.Activity == ports.TerminalActivityPrompting {
		line := strings.TrimSpace(event.CursorLine)
		return Observation{Reading: domain.ScreenQuestion, Identity: strings.Join(strings.Fields(line), " "), Text: line, Confirm: ScreenQuestionConfirm}
	}
	detector, ok := agent.(ports.TerminalActivityDetector)
	if !ok {
		return Observation{Reading: domain.ScreenSettled, Confirm: ScreenQuietSettle}
	}
	state, ok := detector.DetectTerminalActivity(event.Tail)
	if !ok {
		return Observation{}
	}
	switch state {
	case domain.ActivityIdle:
		return Observation{Reading: domain.ScreenSettled, Confirm: ScreenSettleConfirm}
	case domain.ActivityWaitingInput:
		return Observation{Reading: domain.ScreenWaiting, Confirm: ScreenSettleConfirm}
	case domain.ActivityActive:
		return Observation{Reading: domain.ScreenWorking, Confirm: ScreenActiveConfirm}
	default:
		return Observation{}
	}
}
```

- [ ] **Step 3: Run, expect pass**

```bash
cd "$REPO/backend" && go test ./internal/observe/screen/ -v 2>&1 | grep -E "^(--- |ok|FAIL)"
```
Expected: every `--- PASS`, `ok`.

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add backend/internal/observe/screen/classify.go backend/internal/observe/screen/classify_test.go backend/internal/observe/screen/debounce.go backend/internal/observe/screen/debounce_test.go
git commit -m "feat(observe): classify pty-host activity with the agent adapter and debounce it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: The screen observer, wired into the daemon

**Files:**
- Create: `backend/internal/observe/screen/observer.go`, `backend/internal/observe/screen/observer_test.go`
- Modify: `backend/internal/daemon/lifecycle_wiring.go:23` (import), `:44-51` (`lifecycleStack.screenDone`), `:57-71` (start it), `:98-110` (`Stop` waits for it)

**Interfaces:**
- Consumes: `Classify`, `Debouncer` (Task 11); `ports.TerminalProgramReader.WatchTerminalPrograms` (`ports/terminal_program.go`); `ports.AgentResolver` (`ports/agent.go:277-279`); `lifecycle.Manager.ApplyActivitySignal` (Task 9); store `ListAllSessions`/`GetSession` (`storage/sqlite/store/session_store.go:367,388`).
- Produces: `screen.New(sessions sessionSource, sink activitySink, programs programSource, agents ports.AgentResolver, cfg Config) *Observer`; `(*Observer).Start(ctx) <-chan struct{}`; `(*Observer).Enqueue(handleID string, event ports.TerminalProgramEvent)`; `(*Observer).Drain(ctx)`; `(*Observer).Step(ctx, now time.Time)`; `type Config struct { Clock func() time.Time; Logger *slog.Logger }`.

- [ ] **Step 1: Failing tests**

Create `backend/internal/observe/screen/observer_test.go`:

```go
package screen

import (
	"context"
	"io"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakeSessions struct {
	mu   sync.Mutex
	rows map[domain.SessionID]domain.SessionRecord
}

func (f *fakeSessions) ListAllSessions(context.Context) ([]domain.SessionRecord, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []domain.SessionRecord
	for _, rec := range f.rows {
		out = append(out, rec)
	}
	return out, nil
}

func (f *fakeSessions) GetSession(_ context.Context, id domain.SessionID) (domain.SessionRecord, bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	rec, ok := f.rows[id]
	return rec, ok, nil
}

func (f *fakeSessions) setState(id domain.SessionID, state domain.ActivityState) {
	f.mu.Lock()
	defer f.mu.Unlock()
	rec := f.rows[id]
	rec.Activity.State = state
	rec.UpdatedAt = rec.UpdatedAt.Add(time.Second)
	f.rows[id] = rec
}

type fakeSink struct {
	sessions *fakeSessions
	signals  []ports.ActivitySignal
}

func (f *fakeSink) ApplyActivitySignal(_ context.Context, id domain.SessionID, s ports.ActivitySignal) error {
	f.signals = append(f.signals, s)
	f.sessions.setState(id, s.State)
	return nil
}

type fakePrograms struct{ fn func(string, ports.TerminalProgramEvent) }

func (f *fakePrograms) WatchTerminalPrograms(fn func(string, ports.TerminalProgramEvent)) func() {
	f.fn = fn
	return func() { f.fn = nil }
}

type agents map[domain.AgentHarness]ports.Agent

func (a agents) Agent(h domain.AgentHarness) (ports.Agent, bool) {
	agent, ok := a[h]
	return agent, ok
}

func observerFixture(t *testing.T, state domain.ActivityState) (*Observer, *fakeSessions, *fakeSink) {
	t.Helper()
	sessions := &fakeSessions{rows: map[domain.SessionID]domain.SessionRecord{
		"opr-1": {
			ID: "opr-1", Harness: domain.HarnessClaudeCode,
			Activity:  domain.Activity{State: state, LastActivityAt: t0.Add(-time.Minute)},
			UpdatedAt: t0.Add(-time.Minute),
			Metadata:  domain.SessionMetadata{RuntimeHandleID: "handle-1", RuntimeLaunchID: "launch-1"},
		},
	}}
	sink := &fakeSink{sessions: sessions}
	o := New(sessions, sink, &fakePrograms{}, agents{domain.HarnessClaudeCode: claudecode.New()},
		Config{Clock: func() time.Time { return t0 }, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	return o, sessions, sink
}

func TestObserverRaisesAQuestionForASessionNobodyIsViewing(t *testing.T) {
	o, sessions, sink := observerFixture(t, domain.ActivityActive)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(ScreenQuestionConfirm))
	if len(sink.signals) != 1 {
		t.Fatalf("signals = %+v, want one", sink.signals)
	}
	got := sink.signals[0]
	if got.Event != ports.EventScreenQuestion || got.ScreenReading != domain.ScreenQuestion || got.State != domain.ActivityBlocked ||
		got.LaunchID != "launch-1" || !got.ExpectedUpdatedAt.Equal(t0.Add(-time.Minute)) || got.ScreenIdentity == "" {
		t.Fatalf("signal = %+v", got)
	}
	if rec, _, _ := sessions.GetSession(context.Background(), "opr-1"); rec.Activity.State != domain.ActivityBlocked {
		t.Fatalf("state = %q", rec.Activity.State)
	}
}

func TestObserverIgnoresTitlesAndUnknownHandles(t *testing.T) {
	o, _, sink := observerFixture(t, domain.ActivityActive)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "x"})
	o.Enqueue("handle-404", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityActive, At: t0})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(time.Minute))
	if len(sink.signals) != 0 {
		t.Fatalf("signals = %+v, want none", sink.signals)
	}
}

func TestObserverSkipsAReadingTheSessionAlreadyHas(t *testing.T) {
	o, _, sink := observerFixture(t, domain.ActivityBlocked)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(time.Minute))
	if len(sink.signals) != 0 {
		t.Fatalf("signals = %+v, want none", sink.signals)
	}
}

func TestObserverReassertsAConfirmedReadingThatAHookOverrode(t *testing.T) {
	o, sessions, sink := observerFixture(t, domain.ActivityActive)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(ScreenQuestionConfirm))
	sessions.setState("opr-1", domain.ActivityActive)
	o.Step(context.Background(), t0.Add(ScreenQuestionConfirm+2*time.Second))
	if len(sink.signals) != 1 {
		t.Fatalf("re-asserted before the interval: %+v", sink.signals)
	}
	o.Step(context.Background(), t0.Add(ScreenQuestionConfirm+reassertEvery))
	if len(sink.signals) != 2 || sink.signals[1].ScreenIdentity != sink.signals[0].ScreenIdentity {
		t.Fatalf("signals = %+v, want the same question re-asserted once", sink.signals)
	}
}

func TestObserverForgetsATerminatedSession(t *testing.T) {
	o, sessions, sink := observerFixture(t, domain.ActivityActive)
	o.Enqueue("handle-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivityIdle, At: t0, Tail: pane(t, "claudecode_permission.txt")})
	o.Drain(context.Background())
	o.Step(context.Background(), t0.Add(ScreenQuestionConfirm))
	sessions.mu.Lock()
	rec := sessions.rows["opr-1"]
	rec.IsTerminated = true
	rec.Activity.State = domain.ActivityExited
	sessions.rows["opr-1"] = rec
	sessions.mu.Unlock()
	o.Step(context.Background(), t0.Add(time.Minute))
	if len(sink.signals) != 1 || len(o.tracked) != 0 {
		t.Fatalf("signals=%d tracked=%d, want 1 and 0", len(sink.signals), len(o.tracked))
	}
}
```

```bash
cd "$REPO/backend" && go test ./internal/observe/screen/ -run TestObserver 2>&1 | tail -3
```
Expected: build failure, `undefined: New` / `undefined: Config`.

- [ ] **Step 2: Observer**

Create `backend/internal/observe/screen/observer.go`:

```go
package screen

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

const (
	stepEvery     = 250 * time.Millisecond
	reassertEvery = 5 * time.Second
	maxQueued     = 32
)

type sessionSource interface {
	ListAllSessions(ctx context.Context) ([]domain.SessionRecord, error)
	GetSession(ctx context.Context, id domain.SessionID) (domain.SessionRecord, bool, error)
}

type activitySink interface {
	ApplyActivitySignal(ctx context.Context, id domain.SessionID, signal ports.ActivitySignal) error
}

type programSource interface {
	WatchTerminalPrograms(fn func(handleID string, event ports.TerminalProgramEvent)) (stop func())
}

type Config struct {
	Clock  func() time.Time
	Logger *slog.Logger
}

type tracked struct {
	session    domain.SessionID
	harness    domain.AgentHarness
	debouncer  Debouncer
	confirmed  *Decision
	reassertAt time.Time
}

type Observer struct {
	sessions sessionSource
	sink     activitySink
	programs programSource
	agents   ports.AgentResolver
	clock    func() time.Time
	logger   *slog.Logger

	mu     sync.Mutex
	queued map[string][]ports.TerminalProgramEvent
	wake   chan struct{}

	tracked map[string]*tracked
}

func New(sessions sessionSource, sink activitySink, programs programSource, agents ports.AgentResolver, cfg Config) *Observer {
	o := &Observer{
		sessions: sessions,
		sink:     sink,
		programs: programs,
		agents:   agents,
		clock:    cfg.Clock,
		logger:   cfg.Logger,
		queued:   map[string][]ports.TerminalProgramEvent{},
		wake:     make(chan struct{}, 1),
		tracked:  map[string]*tracked{},
	}
	if o.clock == nil {
		o.clock = func() time.Time { return time.Now().UTC() }
	}
	if o.logger == nil {
		o.logger = slog.Default()
	}
	return o
}

func (o *Observer) Start(ctx context.Context) <-chan struct{} {
	done := make(chan struct{})
	stop := o.programs.WatchTerminalPrograms(o.Enqueue)
	go func() {
		defer close(done)
		defer stop()
		ticker := time.NewTicker(stepEvery)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-o.wake:
				o.Drain(ctx)
			case <-ticker.C:
				o.Drain(ctx)
				o.Step(ctx, o.clock())
			}
		}
	}()
	return done
}

func (o *Observer) Enqueue(handleID string, event ports.TerminalProgramEvent) {
	if event.Kind != ports.TerminalProgramActivity {
		return
	}
	o.mu.Lock()
	queue := append(o.queued[handleID], event)
	if len(queue) > maxQueued {
		queue = queue[len(queue)-maxQueued:]
	}
	o.queued[handleID] = queue
	o.mu.Unlock()
	select {
	case o.wake <- struct{}{}:
	default:
	}
}

func (o *Observer) Drain(ctx context.Context) {
	o.mu.Lock()
	queued := o.queued
	o.queued = map[string][]ports.TerminalProgramEvent{}
	o.mu.Unlock()
	for handleID, events := range queued {
		t := o.track(ctx, handleID)
		if t == nil {
			continue
		}
		agent := o.agentFor(t.harness)
		for _, event := range events {
			at := event.At
			if at.IsZero() {
				at = o.clock()
			}
			o.apply(ctx, t, t.debouncer.Observe(Classify(agent, event), at))
		}
	}
}

func (o *Observer) Step(ctx context.Context, now time.Time) {
	for handleID, t := range o.tracked {
		o.apply(ctx, t, t.debouncer.Due(now))
		if t.confirmed == nil || now.Before(t.reassertAt) {
			continue
		}
		t.reassertAt = now.Add(reassertEvery)
		rec, ok, err := o.sessions.GetSession(ctx, t.session)
		if err != nil {
			continue
		}
		if !ok || rec.IsTerminated {
			delete(o.tracked, handleID)
			continue
		}
		o.send(ctx, t, rec, *t.confirmed)
	}
}

func (o *Observer) apply(ctx context.Context, t *tracked, decisions []Decision) {
	for _, decision := range decisions {
		confirmed := decision
		t.confirmed = &confirmed
		t.reassertAt = o.clock().Add(reassertEvery)
		rec, ok, err := o.sessions.GetSession(ctx, t.session)
		if err != nil || !ok || rec.IsTerminated {
			continue
		}
		o.send(ctx, t, rec, decision)
	}
}

func (o *Observer) send(ctx context.Context, t *tracked, rec domain.SessionRecord, decision Decision) {
	t.harness = rec.Harness
	target, ok := decision.Reading.State()
	if !ok || rec.Activity.State == target {
		return
	}
	err := o.sink.ApplyActivitySignal(ctx, rec.ID, ports.ActivitySignal{
		Valid:             true,
		State:             target,
		Timestamp:         o.clock(),
		ExpectedUpdatedAt: rec.UpdatedAt,
		Event:             ports.ScreenEvent(decision.Reading),
		LaunchID:          rec.Metadata.RuntimeLaunchID,
		ScreenReading:     decision.Reading,
		ScreenIdentity:    decision.Identity,
		ScreenText:        decision.Text,
	})
	if err != nil {
		o.logger.Error("screen observer: apply failed", "session", rec.ID, "reading", decision.Reading, "err", err)
	}
}

func (o *Observer) track(ctx context.Context, handleID string) *tracked {
	if t, ok := o.tracked[handleID]; ok {
		return t
	}
	sessions, err := o.sessions.ListAllSessions(ctx)
	if err != nil {
		o.logger.Debug("screen observer: sessions unavailable", "err", err)
		return nil
	}
	for _, rec := range sessions {
		if rec.Metadata.RuntimeHandleID == handleID && !rec.IsTerminated {
			t := &tracked{session: rec.ID, harness: rec.Harness}
			o.tracked[handleID] = t
			return t
		}
	}
	return nil
}

func (o *Observer) agentFor(harness domain.AgentHarness) any {
	if o.agents == nil {
		return nil
	}
	agent, ok := o.agents.Agent(harness)
	if !ok {
		return nil
	}
	return agent
}
```
(`Drain` and `Step` run only on the observer's goroutine, so `tracked` needs no lock; `Enqueue` runs on the runtime's watch goroutine and only touches `queued` under `mu`.)

- [ ] **Step 3: Daemon wiring**

In `backend/internal/daemon/lifecycle_wiring.go`:
- after the `activityobserver` import (line 23) add `screenobserver "github.com/OmarAly92/operator/backend/internal/observe/screen"`;
- in `lifecycleStack`, after `activityDone  <-chan struct{}` add `screenDone    <-chan struct{}`;
- replace

```go
	return &lifecycleStack{
		LCM:           lcm,
		runtimeReaper: rp,
		reaperDone:    rp.Start(ctx),
		activityDone:  activityPoller.Start(ctx),
	}
```
with
```go
	stack := &lifecycleStack{
		LCM:           lcm,
		runtimeReaper: rp,
		reaperDone:    rp.Start(ctx),
		activityDone:  activityPoller.Start(ctx),
	}
	if programs, ok := runtime.(ports.TerminalProgramReader); ok {
		stack.screenDone = screenobserver.New(store, lcm, programs, agents, screenobserver.Config{Logger: logger}).Start(ctx)
	}
	return stack
```
- in `Stop`, after the `activityDone` wait add

```go
	if l.screenDone != nil {
		<-l.screenDone
	}
```

- [ ] **Step 4: Run, expect pass**

```bash
cd "$REPO/backend" && go test -race ./internal/observe/... ./internal/daemon/... 2>&1 | grep -v "^ok" | tail -5
```
Expected: no output. `daemon/wiring_test.go:555` starts the stack with a real `ptyhost.Runtime`, so it exercises the new goroutine's start and stop.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add backend/internal/observe/screen/observer.go backend/internal/observe/screen/observer_test.go backend/internal/daemon/lifecycle_wiring.go
git commit -m "feat(daemon): screen observer turns pty-host activity into debounced lifecycle signals

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 13: Measure on the recordings — false alarms, missed questions, duplicates, flicker, correction time

**Files:**
- Create: `backend/internal/observe/screen/recordings_test.go`

**Interfaces:**
- Consumes: the seven signal recordings (Task 2), `vtwasm.New`/`FeedAt`/`Resize`/`RenderTail`/`CursorLine`/`NewActivityClock` (Tasks 5), `Classify`/`Debouncer` (Task 11), `domain.MergeScreenReading` (Task 8), the lifecycle alert rule (Task 9: an alert on entering the needs-input family, skipped for the same screen question within 2 minutes).
- Produces: `TestAgentSignalsOnRecordings`, which replays each recording at its recorded timing through the same pipeline the pty-host and the observer run (250 ms clock, typing and resize pokes from `truth.inputs`) and, per recording and mode, logs and checks:
  - `false` — alerts outside an `asking` interval. **Threshold 0**, every mode.
  - `dup` — alerts beyond the first inside one `asking` interval. **Threshold 0**, every mode.
  - `missed` — `asking` intervals of at least 4 s that are not needs-input 4 s after they start. **Threshold 0** in `hookless` mode.
  - `flips` — state changes inside a truth interval, after a grace of 5 s from its start (65 s for a `settled` interval of an agent with no detector), to a state other than the interval's own. **Threshold 0** in `hookless` and `hooks` modes.
  - `screen` — changes the screen made while hooks were timely. **Threshold 0** in `hooks` mode.
  - `correction` — the longest time from a `settled` interval's start to the card reading idle when every `Stop` hook is lost. **Threshold 40 s** in `missed-stop` mode.
- Modes: `hookless` (no hooks at all — the aider/pi/auggie case and the pure screen path); `hooks` (a hook 300 ms after each truth boundary: working→active, asking→blocked, settled→idle); `missed-stop` (the same without the settled hooks). The two hook modes run only for `claude-code` and `codex` recordings.

- [ ] **Step 1: The harness (the failing test is its thresholds on the real recordings)**

Create `backend/internal/observe/screen/recordings_test.go`:

```go
package screen

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/codex"
	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type truthInterval struct {
	From     int64  `json:"from"`
	To       int64  `json:"to"`
	State    string `json:"state"`
	Question string `json:"question"`
}

type signalTruth struct {
	Harness   string          `json:"harness"`
	Intervals []truthInterval `json:"intervals"`
	Inputs    []int64         `json:"inputs"`
}

type signalSize struct {
	Offset int    `json:"offset"`
	Cols   uint32 `json:"cols"`
	Rows   uint32 `json:"rows"`
}

type signalRecording struct {
	name      string
	recording []byte
	sizes     []signalSize
	timing    [][2]int64
	truth     signalTruth
}

type simMode string

const (
	modeHookless   simMode = "hookless"
	modeHooks      simMode = "hooks"
	modeMissedStop simMode = "missed-stop"
)

const (
	simTickMs          = 250
	simTailMs          = 90_000
	hookDelayMs        = 300
	flickerGraceMs     = 5_000
	quietGraceMs       = 65_000
	missedBudgetMs     = 4_000
	correctionBudgetMs = 40_000
)

type simTransition struct {
	at     int64
	to     domain.ActivityState
	alert  bool
	screen bool
}

type simHook struct {
	at    int64
	state domain.ActivityState
}

type simulator struct {
	state      domain.ActivityState
	lastHookAt time.Time
	alerted    string
	alertedAt  time.Time
	out        []simTransition
}

func (s *simulator) set(ms int64, at time.Time, to domain.ActivityState, screen bool, identity string) {
	if to == s.state {
		return
	}
	alert := false
	if !s.state.NeedsInput() && to.NeedsInput() {
		alert = identity == "" || identity != s.alerted || at.Sub(s.alertedAt) >= 2*time.Minute
		if identity != "" {
			s.alerted, s.alertedAt = identity, at
		}
	}
	if to == domain.ActivityIdle {
		s.alerted = ""
	}
	s.out = append(s.out, simTransition{at: ms, to: to, alert: alert, screen: screen})
	s.state = to
}

func signalsDir() string {
	return filepath.Join("..", "..", "..", "..", "packages", "terminal", "bench", "agent-session", "signals")
}

func readJSON(t *testing.T, path string, into any) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if err := json.Unmarshal(raw, into); err != nil {
		t.Fatalf("decode %s: %v", path, err)
	}
}

func loadSignals(t *testing.T) []signalRecording {
	t.Helper()
	entries, err := os.ReadDir(signalsDir())
	if err != nil {
		t.Fatalf("signals: %v", err)
	}
	var out []signalRecording
	for _, entry := range entries {
		if !entry.IsDir() || entry.Name() == "scenarios" {
			continue
		}
		dir := filepath.Join(signalsDir(), entry.Name())
		rec := signalRecording{name: entry.Name()}
		raw, err := os.ReadFile(filepath.Join(dir, "recording"))
		if err != nil {
			t.Fatalf("read %s: %v", entry.Name(), err)
		}
		rec.recording = raw
		readJSON(t, filepath.Join(dir, "size.json"), &rec.sizes)
		readJSON(t, filepath.Join(dir, "timing.json"), &rec.timing)
		readJSON(t, filepath.Join(dir, "truth.json"), &rec.truth)
		out = append(out, rec)
	}
	if len(out) == 0 {
		t.Fatal("no signal recordings (Task 2 records them)")
	}
	return out
}

func signalAgent(harness string) any {
	switch harness {
	case "claude-code":
		return claudecode.New()
	case "codex":
		return codex.New()
	default:
		return nil
	}
}

func simHooks(truth signalTruth, mode simMode) []simHook {
	if mode == modeHookless || truth.Harness == "" {
		return nil
	}
	var out []simHook
	for _, interval := range truth.Intervals {
		switch interval.State {
		case "working":
			out = append(out, simHook{interval.From + hookDelayMs, domain.ActivityActive})
		case "asking":
			out = append(out, simHook{interval.From + hookDelayMs, domain.ActivityBlocked})
		case "settled":
			if mode != modeMissedStop {
				out = append(out, simHook{interval.From + hookDelayMs, domain.ActivityIdle})
			}
		}
	}
	return out
}

func simulate(t *testing.T, rec signalRecording, mode simMode) []simTransition {
	t.Helper()
	p, err := vtwasm.New(context.Background(), vtwasm.Module, rec.sizes[0].Cols, rec.sizes[0].Rows, vtwasm.Limits{Rows: 200_000, Bytes: 128 << 20})
	if err != nil {
		t.Fatalf("parser: %v", err)
	}
	defer p.Close()
	agent := signalAgent(rec.truth.Harness)
	base := time.Date(2026, 9, 27, 0, 0, 0, 0, time.UTC)
	at := func(ms int64) time.Time { return base.Add(time.Duration(ms) * time.Millisecond) }
	clock := vtwasm.NewActivityClock(p)
	var debouncer Debouncer
	var confirmed *Decision
	var reassertAt int64
	sim := &simulator{state: domain.ActivityIdle}
	hooks := simHooks(rec.truth, mode)
	inputs := append([]int64(nil), rec.truth.Inputs...)
	var pokedAt time.Time
	decide := func(ms int64, decisions []Decision) {
		for _, d := range decisions {
			decision := d
			confirmed = &decision
			reassertAt = ms + reassertEvery.Milliseconds()
			if merged, ok := domain.MergeScreenReading(sim.state, d.Reading, sim.lastHookAt, at(ms)); ok {
				sim.set(ms, at(ms), merged, true, d.Identity)
			}
		}
	}
	step := func(ms int64) {
		for len(inputs) > 0 && inputs[0] <= ms {
			pokedAt = at(inputs[0])
			inputs = inputs[1:]
		}
		for len(hooks) > 0 && hooks[0].at <= ms {
			sim.lastHookAt = at(hooks[0].at)
			sim.set(hooks[0].at, at(hooks[0].at), hooks[0].state, false, "")
			hooks = hooks[1:]
		}
		state, changed, err := clock.Step(p, at(ms), pokedAt)
		if err != nil {
			t.Fatalf("clock: %v", err)
		}
		if changed {
			event := ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivity(state.String()), At: at(ms)}
			if state != vtwasm.ActivityActive {
				event.Tail, _ = p.RenderTail(40)
				event.CursorLine, _ = p.CursorLine()
			}
			decide(ms, debouncer.Observe(Classify(agent, event), at(ms)))
		}
		decide(ms, debouncer.Due(at(ms)))
		if confirmed != nil && ms >= reassertAt {
			reassertAt = ms + reassertEvery.Milliseconds()
			if merged, ok := domain.MergeScreenReading(sim.state, confirmed.Reading, sim.lastHookAt, at(ms)); ok {
				sim.set(ms, at(ms), merged, true, confirmed.Identity)
			}
		}
	}
	next := 1
	var ticked int64
	for i, entry := range rec.timing {
		offset, ms := int(entry[0]), entry[1]
		for ; ticked+simTickMs < ms; ticked += simTickMs {
			step(ticked + simTickMs)
		}
		end := len(rec.recording)
		if i+1 < len(rec.timing) {
			end = int(rec.timing[i+1][0])
		}
		for offset < end {
			stop := end
			if next < len(rec.sizes) && rec.sizes[next].Offset >= offset && rec.sizes[next].Offset < stop {
				stop = rec.sizes[next].Offset
			}
			if stop > offset {
				if err := p.FeedAt(rec.recording[offset:stop], at(ms).UnixMilli()); err != nil {
					t.Fatalf("feed: %v", err)
				}
				offset = stop
			}
			if next < len(rec.sizes) && rec.sizes[next].Offset == offset {
				if err := p.Resize(rec.sizes[next].Cols, rec.sizes[next].Rows); err != nil {
					t.Fatalf("resize: %v", err)
				}
				next++
			}
		}
		step(ms)
	}
	last := rec.timing[len(rec.timing)-1][1]
	for ms := ticked + simTickMs; ms <= last+simTailMs; ms += simTickMs {
		step(ms)
	}
	return sim.out
}

func expectedState(state string) domain.ActivityState {
	switch state {
	case "working":
		return domain.ActivityActive
	case "asking":
		return domain.ActivityBlocked
	default:
		return domain.ActivityIdle
	}
}

func stateAt(transitions []simTransition, ms int64) domain.ActivityState {
	state := domain.ActivityIdle
	for _, tr := range transitions {
		if tr.at > ms {
			break
		}
		state = tr.to
	}
	return state
}

type signalMetrics struct {
	alerts, falseAlerts, duplicates, missed, flips, screen int
	correctionMs                                          int64
}

func measure(rec signalRecording, mode simMode, transitions []simTransition) signalMetrics {
	intervals := append([]truthInterval(nil), rec.truth.Intervals...)
	intervals[len(intervals)-1].To += simTailMs
	var m signalMetrics
	perAsking := map[int]int{}
	for _, tr := range transitions {
		if tr.screen {
			m.screen++
		}
		if !tr.alert {
			continue
		}
		m.alerts++
		asking := -1
		for i, interval := range intervals {
			if interval.State == "asking" && tr.at >= interval.From && tr.at <= interval.To {
				asking = i
			}
		}
		if asking < 0 {
			m.falseAlerts++
		} else {
			perAsking[asking]++
		}
	}
	for _, n := range perAsking {
		m.duplicates += max(0, n-1)
	}
	noDetector := signalAgent(rec.truth.Harness) == nil
	for i, interval := range intervals {
		grace := int64(flickerGraceMs)
		if interval.State == "settled" && noDetector {
			grace = quietGraceMs
		}
		for _, tr := range transitions {
			if tr.at > interval.From+grace && tr.at < interval.To && tr.to != expectedState(interval.State) {
				m.flips++
			}
		}
		if interval.State == "asking" && interval.To-interval.From >= missedBudgetMs && !stateAt(transitions, interval.From+missedBudgetMs).NeedsInput() {
			m.missed++
		}
		if interval.State == "settled" && i > 0 {
			latency := interval.To - interval.From
			for ms := interval.From; ms <= interval.To; ms += simTickMs {
				if stateAt(transitions, ms) == domain.ActivityIdle {
					latency = ms - interval.From
					break
				}
			}
			m.correctionMs = max(m.correctionMs, latency)
		}
	}
	return m
}

func TestAgentSignalsOnRecordings(t *testing.T) {
	for _, rec := range loadSignals(t) {
		modes := []simMode{modeHookless}
		if rec.truth.Harness != "" {
			modes = append(modes, modeHooks, modeMissedStop)
		}
		for _, mode := range modes {
			m := measure(rec, mode, simulate(t, rec, mode))
			t.Logf("%-24s %-11s alerts=%d false=%d dup=%d missed=%d flips=%d screen=%d correction=%dms",
				rec.name, mode, m.alerts, m.falseAlerts, m.duplicates, m.missed, m.flips, m.screen, m.correctionMs)
			if m.falseAlerts != 0 || m.duplicates != 0 {
				t.Errorf("%s/%s: %d false and %d duplicate alerts", rec.name, mode, m.falseAlerts, m.duplicates)
			}
			if mode == modeHookless && m.missed != 0 {
				t.Errorf("%s/%s: %d questions missed", rec.name, mode, m.missed)
			}
			if mode != modeMissedStop && m.flips != 0 {
				t.Errorf("%s/%s: %d flips", rec.name, mode, m.flips)
			}
			if mode == modeHooks && m.screen != 0 {
				t.Errorf("%s/%s: the screen changed %d states while hooks were timely", rec.name, mode, m.screen)
			}
			if mode == modeMissedStop && m.correctionMs > correctionBudgetMs {
				t.Errorf("%s/%s: a lost Stop hook took %d ms to correct", rec.name, mode, m.correctionMs)
			}
		}
	}
}
```

- [ ] **Step 2: Run on the recordings**

```bash
cd "$REPO/backend" && go test ./internal/observe/screen/ -run TestAgentSignalsOnRecordings -v 2>&1 | grep -E "alerts=|FAIL|ok|Error|--- " | tee /private/tmp/claude-501/-Users-omaraly-development-AI-Operator/82bbcd8b-e64f-470c-92e3-6c4278144a31/scratchpad/signal-measurements.txt
```
Expected: one `alerts=` line per recording and mode (7 hookless + 6 hooks + 6 missed-stop = 19 lines) and `--- PASS`. `claude-two-permissions/hookless` must read `alerts=2`; every other hookless recording with a question `alerts=1`; `claude-think` and `codex-think` `alerts=0`; `shell-pause/hookless` `alerts=1 flips=0`.

**If a threshold fails, it is a finding, not a harness bug.** Do not loosen a threshold, change a hold time, or edit `truth.json` to pass. Instead: print the screen at the failing moment (add a temporary `t.Logf("%q", event.Tail)` in `step`, never committed), decide which layer is wrong (the adapter reader, the classifier or the debouncer), add a failing unit test to that layer's test file with the offending screen text (Task 10 or 11 tests), fix it, and re-run. If the recording shows an agent behaviour this design cannot read (for example a Codex approval prompt that is not a numbered `›` menu), stop and report it with the screen text; that is an open decision for the user, not something to guess around.

- [ ] **Step 3: Commit (with the measured table in the message)**

```bash
cd "$REPO" && git add backend/internal/observe/screen/recordings_test.go
git commit -F - <<'MSG'
test(observe): measure agent signals on real Claude Code, Codex and shell recordings

<paste the 19 alerts= lines from signal-measurements.txt here>

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
```

---

### Task 14: Phase A — docs, all gates, real-app check

**Files:**
- Modify: `TERMINAL.md:268-275` (§3.2 attribution path), `TERMINAL.md` (new §4.52 after §4.50, line 1986), `TERMINAL.md:1253,1296` (`input-patterns.ts` mentions); `packages/terminal/CHANGELOG.md` (Unreleased); `docs/terminal/2026-09-19-terminal-reference-survey.md` (§6.9 and §7.1 status lines); `docs/STATUS.md` (Backend, In flight)

**Interfaces:** none.

- [ ] **Step 1: TERMINAL.md**

- §3.2 (line 272): replace ``(MIT; `ts/core/src/input-patterns.ts`, `VSCODE-INPUT-PATTERNS-ATTRIBUTION.md` `` … with ``(MIT; `crates/vt-core/src/activity/input_patterns.rs`, `VSCODE-INPUT-PATTERNS-ATTRIBUTION.md` and `LICENSE-VSCODE-MIT` beside it)`` keeping the rest of the sentence.
- §4.34: replace ``high-confidence prompt patterns, `input-patterns.ts`)`` with ``high-confidence prompt patterns, now in `vt-core` `activity/input_patterns.rs`, §4.52)`` and add one bullet at its end: "Operator consumes the classifier since wave 1 (§4.52); the TS monitor asks the core (`WasmTerminalCore::cursor_line_prompts`)."
- Add §4.52 after §4.50:

```markdown
### 4.52 Operator's status came only from hooks — wave 1, agent signals
- Before: a card's working / needs-you / done came only from agent hooks (`lifecycle/manager.go:547`), a missed hook left it stale until the next one (the 30 s poller corrected only Codex and Muse after 2 minutes, `observe/activity/observer.go:15-17`), and agents without hooks (aider, pi, auggie) were always idle.
- Classifier in vt-core, shared: `TerminalCore::cursor_line_text`, `cursor_line_prompts`, `agent_activity(quiet_ms)` (`crates/vt-core/src/activity.rs`; VS Code's patterns in `activity/input_patterns.rs`). The renderer's `AgentActivityMonitor` asks the core; the mirror exports `vt_live_output_bytes`, `vt_agent_activity`, `vt_cursor_line`.
- Detection runs in the pty-host (every byte, pane open or not): `vtwasm.ActivityClock` on a 250 ms tick and every feed; typing echo and resize repaints within 250 ms of a keystroke or resize are not activity; `PollingForIdle` is not published; transitions go to watchers that ask (`MsgWatchReq {"activity":true}`) with a 40-row tail and the cursor line; a late watcher gets the last one; seeding and respawn re-baseline.
- Daemon: `observe/screen` classifies with the adapter (`TerminalQuestionReader` for Claude Code and Codex, Claude Code's new composer detector), debounces (working 3 s, question 1 s, settle 2 s, unconfirmed settle 60 s, leaving an answered question 2 s), re-asserts every 5 s, and calls `ApplyActivitySignal` with a screen reading. `domain.MergeScreenReading`: a hook within 30 s wins except a question drawn after its `active`; stale or absent hooks lose. One alert per question identity per 2 minutes. Screen signals never set `FirstSignalAt`.
- Measured (Task 13, `backend/internal/observe/screen/recordings_test.go`, recordings in `packages/terminal/bench/agent-session/signals/`): <the 19 lines from the Task 13 commit message>.
- Guards: `crates/vt-core/tests/agent_activity.rs`, `vt-wasm/tests/agent_exports.rs`, `vtwasm/activity_test.go`, `ptyhost/activity_test.go`, `program_watch_test.go` `TestTheProgramWatchAsksForActivityAndDeliversIt`, `terminal/programs_test.go` `TestActivityEventsNeverReachTheProgramsChannel`, `domain/screen_reading_test.go`, `lifecycle/screen_signal_test.go`, `terminalui/question_test.go`, `claudecode/question_test.go`, `codex/question_test.go`, `observe/screen/{classify,debounce,observer,recordings}_test.go`.
```

- [ ] **Step 2: CHANGELOG, survey, STATUS**

Add under `## Unreleased` in `packages/terminal/CHANGELOG.md`:

```markdown
- vt-core: the agent classifier moved from `ts/core` into the core: `TerminalCore::cursor_line_text`, `cursor_line_prompts` (VS Code's high-confidence patterns, now `crates/vt-core/src/activity/input_patterns.rs`) and `agent_activity(quiet_ms)`. vt-host exports `vt_live_output_bytes`, `vt_agent_activity` and `vt_cursor_line`; vt-wasm exports `detects_high_confidence_input_pattern` and `cursor_line_prompts`. ts/core: `AgentActivitySource` is now `{ liveOutputBytes, prompting, now }` (was `cursorLine` and `lineEditorOwnsLine`), `cursorLineText` is removed, and `detectsHighConfidenceInputPattern` needs `initTerminalCore` first (breaking). Operator uses it for agent status (`TERMINAL.md` §4.52). Both wasm artifacts and the daemon must be rebuilt.
```
In the survey, §6.9's status line: replace "Operator does not consume them; its board state still comes from `opr mcp` (`2e54a6bfb`) and the daemon (`0cd094f12`)." with "Operator consumes the classifier through the pty-host mirror since wave 1 (`TERMINAL.md` §4.52); compact summaries land in wave 1 phase B." §7.1: append to its status line "The daemon's screen observer (`backend/internal/observe/screen`) is where an in-band agent-state event would enter; nothing emits one yet."
In `docs/STATUS.md` under "In flight / not yet a runtime feature" add: "Agent signals (wave 1 phase A, branch `terminal/wave1-agent-signals`): card status from the terminal screen for any agent, hooks first; `TERMINAL.md` §4.52."

- [ ] **Step 3: All gates** (absolute paths; record every count)

```bash
cd "$REPO/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1 && cargo test 2>&1 | grep -E "FAILED|panicked"; echo rust-done
cargo build --release -p vt-host --target wasm32-unknown-unknown 2>&1 | tail -1 && cp target/wasm32-unknown-unknown/release/vt_host.wasm "$REPO/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm" && git -C "$REPO" status --short backend/internal/adapters/runtime/ptyhost/vtwasm/assets/
npm run build:wasm -- --force && npm run build:ts
for p in core renderer-dom react editor completions; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Tests  |FAIL"); done
npm run check:boundaries 2>&1 | tail -1
node --test ./bench/agent-session/fixtures.test.mjs 2>&1 | tail -2
npm run bench:agent:gate 2>&1 | tail -1
cd "$REPO/backend" && go vet ./... && go test ./... 2>&1 | grep -v "^ok" | tail -10 && go test -race ./internal/observe/... ./internal/lifecycle/... ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... 2>&1 | grep -v "^ok" | tail -5
cd "$REPO" && npm run lint 2>&1 | tail -3
cd "$REPO/frontend" && npm run typecheck 2>&1 | tail -1 && npm run test 2>&1 | tail -3
```
Expected: fmt/clippy clean; no FAILED; the rebuilt `vt_host.wasm` is byte-identical to the one committed in Task 5 (empty `git status`), else commit it with the docs; every vitest package passes; `boundary check passed`; fixtures pass; `PASS agent-session gate`; `go vet` silent; only the known `TestProcessEnvironmentLetsOverridesWin`; lint clean; frontend typecheck and tests pass (no frontend change). `flutter analyze`/`flutter test`: not run — no `packages/mobile` change in this plan.

- [ ] **Step 4: Real-app check (phase A)** — per memory, through the daemon API on `127.0.0.1:3002` and `/mux`, never by clicking the Tauri window. **Ask the user before starting**: a running `tauri:dev` owns 3002/5173 and stopping it kills live sessions.

1. Build and launch the isolated dev app from the worktree with the scrubbed environment: `cd "$REPO/frontend" && env $(env | awk -F= '/^CLAUDE/ {printf "-u %s ", $1}') npm run tauri:dev` (it rebuilds `packages/terminal` and supervises a daemon built from this branch). Confirm `curl -s http://127.0.0.1:3002/healthz`.
2. Spawn Claude Code through the API and **never open its pane**: `curl -s -X POST http://127.0.0.1:3002/api/v1/sessions -H 'content-type: application/json' -d '{"projectId":"<a project id from GET /api/v1/projects>","harness":"claude-code","prompt":"Use the AskUserQuestion tool to ask me whether I prefer tabs or spaces, then reply with only my answer."}'`.
3. Poll `GET /api/v1/sessions/<id>` every 500 ms (a 20-line Python loop printing `activity.state` and `status` with timestamps). Expected: `working` → `needs_input` while the question is shown; `GET /api/v1/notifications` has exactly one open `needs_input` row for the session.
4. Answer through `/mux` (`{"ch":"terminal","id":"<handle>","type":"open","cols":120,"rows":40}` then a base64 `data` frame with `\r`, per the memory recipe). Expected: `working`, then `idle`; exactly one `turn_finished` row.
5. **The screen path end to end** — force a stale hook: while Claude sits idle at its composer, `curl -s -X POST http://127.0.0.1:3002/api/v1/sessions/<id>/activity -H 'content-type: application/json' -d '{"state":"active","event":"pre-tool-use","toolName":"Bash","toolUseId":"fake-1","launchId":"<metadata.runtimeLaunchId from GET>"}'`. Expected: status `working` at once, then back to `idle` within 40 s (hook fresh 30 s, settle 2 s, re-assert 5 s) with no user action — only the screen can do that. Record the seconds.
6. Resize storm: open the session's terminal on `/mux` at 120×40, then send `resize` 80×24 and 120×40 five times while Claude shows a new AskUserQuestion dialog. Expected: still exactly one `needs_input` row for that question.
7. Renderer: headless Playwright against the Vite renderer on `http://127.0.0.1:5173/#/…` (memory: 127.0.0.1, not localhost; hash routes) — screenshot the board with the session's card in the needs-you column during step 3. Attach the screenshot path to the report.
8. Restart the dev daemon (only with the user's OK) and confirm no new notification row appears for a session already needing input.
Write each step's observed result (times, counts) into the completion report; anything not run is `not run: <reason>`.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add TERMINAL.md packages/terminal/CHANGELOG.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/STATUS.md
git commit -m "docs(terminal): agent signals wave 1 phase A (§4.52), changelog, survey and status

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**Phase A boundary.** Phase A ships here: hand the branch back for the whole-branch review and merge before Phase B.

---
# Phase B — "what the agent just did" in notifications, and phone-alert coalescing

Starts from `development` after Phase A is merged: `git worktree add ../Operator-wave1-signals-b -b terminal/wave1-agent-signals-b development` and `export REPO=/Users/omaraly/development/AI/Operator-wave1-signals-b`; re-run Task 0 Step 3 for fresh baselines.

### Task 15: vt-core owns output compaction and a compact tail

**Files:**
- Create: `packages/terminal/crates/vt-core/src/activity/compact.rs`, `packages/terminal/crates/vt-core/tests/agent_compact.rs`
- Modify: `packages/terminal/crates/vt-core/src/activity.rs` (line 1: `pub mod compact;`); `packages/terminal/crates/vt-wasm/src/agent.rs` (three exports), `packages/terminal/crates/vt-wasm/src/lib.rs` (the `pub use agent::…` line); `packages/terminal/ts/core/src/compact-output.ts:1-71` (whole file); `packages/terminal/ts/core/src/compact-output.test.ts:1-2` (wasm init)

**Interfaces:**
- Produces (Rust, `vt_core::activity::compact`): `COMPACT_REDRAW_LOOKBACK: usize = 256`, `COMPACT_MIN_REDRAW_LINES: usize = 3`, `is_spinner_line(&str) -> bool`, `compact_lines<S: AsRef<str>>(&[S]) -> Vec<String>`, `cap_lines<S: AsRef<str>>(&[S], max_lines: usize) -> Vec<String>` — a line-for-line port of `compact-output.ts:1-71`.
- Produces (`TerminalCore`): `tail_output(&self, rows: usize, compact: bool, max_lines: usize) -> String` — the newest `rows` rows (the alternate screen's rows while it is active) joined into logical lines at soft wraps (as `snapshotLogicalLines`, `ts/core/src/logical-lines.ts:15-35`), compacted or with trailing blank lines dropped, capped, `\n`-joined.
- Produces (wasm-bindgen): `is_spinner_line(line: &str) -> bool`, `compact_lines_text(text: &str) -> String`, `cap_lines_text(text: &str, max_lines: u32) -> String` (lines are `\n`-joined across the boundary; a logical line never holds `\n`).
- TS: `isSpinnerLine`, `compactLines`, `capLines` keep their signatures and now need `initTerminalCore` first.

- [ ] **Step 1: Failing Rust tests** (the TS cases, `compact-output.test.ts:1-84`, as Rust)

Create `packages/terminal/crates/vt-core/tests/agent_compact.rs`:

```rust
use vt_core::activity::compact::{cap_lines, compact_lines, is_spinner_line, COMPACT_REDRAW_LOOKBACK};
use vt_core::TerminalCore;

fn strings(lines: &[&str]) -> Vec<String> {
    lines.iter().map(|line| line.to_string()).collect()
}

#[test]
fn spinner_lines_are_recognised_and_finished_lines_are_not() {
    for line in ["✽ Flambéing… (13s · still thinking with high effort)", "· Thinking…", "  ⠋ Installing dependencies...", "◐ Loading…"] {
        assert!(is_spinner_line(line), "{line:?}");
    }
    for line in ["✻ Baked for 11s · done 6:13 PM", "- Installing dependencies...", "* item one…", "Thinking…", "✻", "· Linking... done in 3.2s", "⠿ Container db  Started... healthy"] {
        assert!(!is_spinner_line(line), "{line:?}");
    }
}

#[test]
fn compact_lines_matches_the_typescript_cases() {
    assert_eq!(compact_lines(&["", "a   ", "", "", "b", "", ""]), strings(&["a", "", "b"]));
    assert_eq!(compact_lines(&["✽ Working… (3s)", "result", "✻ Worked for 3s"]), strings(&["result", "✻ Worked for 3s"]));
    assert_eq!(compact_lines(&["banner", "banner", "body"]), strings(&["banner", "body"]));
    let frame = ["╭───╮", "│ > │", "╰───╯"];
    let separated: Vec<&str> = frame.iter().copied().chain(["between"]).chain(frame).chain(["after"]).collect();
    assert_eq!(compact_lines(&separated), strings(&separated));
    assert_eq!(compact_lines(&["a", "b", "x", "a", "b"]), strings(&["a", "b", "x", "a", "b"]));
    let filler: Vec<String> = (0..COMPACT_REDRAW_LOOKBACK).map(|index| format!("filler {index}")).collect();
    let mut far: Vec<String> = strings(&["one", "two", "three"]);
    far.extend(filler);
    far.extend(strings(&["one", "two", "three"]));
    assert_eq!(compact_lines(&far), far);
    let steps = ["test a", "setup", "run", "teardown", "test b", "setup", "run", "teardown"];
    assert_eq!(compact_lines(&steps), strings(&steps));
    let redrawn: Vec<&str> = frame.iter().copied().chain(frame).chain(frame).chain(["after"]).collect();
    assert_eq!(compact_lines(&redrawn), strings(&["╭───╮", "│ > │", "╰───╯", "after"]));
    assert_eq!(compact_lines(&["a", "", "b", "x", "a", "", "b"]), strings(&["a", "", "b", "x", "a", "", "b"]));
}

#[test]
fn cap_lines_keeps_the_head_and_the_tail_around_one_marker() {
    let lines: Vec<String> = (0..10).map(|index| format!("line {index}")).collect();
    assert_eq!(cap_lines(&lines, 5), strings(&["line 0", "line 1", "… 6 lines omitted …", "line 8", "line 9"]));
    assert_eq!(cap_lines(&lines, 10), lines);
    assert!(cap_lines(&lines, 0).is_empty());
    assert_eq!(cap_lines(&lines, 1), strings(&["… 10 lines omitted …"]));
    assert_eq!(cap_lines(&lines, 2), strings(&["line 0", "… 9 lines omitted …"]));
}

#[test]
fn the_tail_is_the_newest_logical_lines_compacted_and_capped() {
    let mut core = TerminalCore::new(20, 1_000).expect("core");
    core.resize(20, 10);
    core.feed(b"first line\r\n");
    core.feed(b"a line long enough to wrap twice here\r\n");
    core.feed("✽ Working… (3s)\r\n".as_bytes());
    core.feed(b"last line\r\n");
    assert_eq!(core.tail_output(100, true, 10), "first line\na line long enough to wrap twice here\nlast line");
    assert_eq!(core.tail_output(100, true, 2), "first line\n… 2 lines omitted …");
    assert_eq!(core.tail_output(1, false, 10), "");
}
```

```bash
cd "$REPO/packages/terminal" && cargo test -p vt-core --test agent_compact 2>&1 | tail -3
```
Expected: `error[E0432]: unresolved import vt_core::activity::compact`.

- [ ] **Step 2: Rust implementation**

In `packages/terminal/crates/vt-core/src/activity.rs` replace `pub mod input_patterns;` with `pub mod compact;\npub mod input_patterns;`.

Create `packages/terminal/crates/vt-core/src/activity/compact.rs`:

```rust
use regex_automata::meta::Regex;
use std::collections::HashMap;
use std::sync::OnceLock;

use crate::TerminalCore;

pub const COMPACT_REDRAW_LOOKBACK: usize = 256;
pub const COMPACT_MIN_REDRAW_LINES: usize = 3;

fn spinner() -> &'static Regex {
    static SPINNER: OnceLock<Regex> = OnceLock::new();
    SPINNER.get_or_init(|| {
        Regex::new(r"^\s*[⠀-⣿·✢✳✶✻✽◐-◓]\s+\S[^…]*?(?:…|\.\.\.)(?:\s+\([^()]*\))?$")
            .expect("spinner pattern compiles")
    })
}

pub fn is_spinner_line(line: &str) -> bool {
    spinner().is_match(line)
}

pub fn compact_lines<S: AsRef<str>>(lines: &[S]) -> Vec<String> {
    let mut normalized: Vec<String> = Vec::new();
    for raw in lines {
        let line = raw.as_ref().trim_end();
        if is_spinner_line(line) {
            continue;
        }
        if line.is_empty() && normalized.last().is_none_or(|last| last.is_empty()) {
            continue;
        }
        if !line.is_empty() && normalized.last().is_some_and(|last| last == line) {
            continue;
        }
        normalized.push(line.to_string());
    }
    let mut kept: Vec<String> = Vec::new();
    let mut seen: HashMap<String, Vec<usize>> = HashMap::new();
    let mut index = 0;
    while index < normalized.len() {
        let line = normalized[index].clone();
        let repeated = if line.is_empty() {
            0
        } else {
            repeated_run(&normalized, index, &kept, seen.get(&line))
        };
        if repeated > 0 {
            index += repeated;
            continue;
        }
        if !line.is_empty() {
            seen.entry(line.clone()).or_default().push(kept.len());
        }
        kept.push(line);
        index += 1;
    }
    while kept.last().is_some_and(|line| line.is_empty()) {
        kept.pop();
    }
    kept
}

fn repeated_run(lines: &[String], at: usize, kept: &[String], positions: Option<&Vec<usize>>) -> usize {
    let Some(positions) = positions else {
        return 0;
    };
    let floor = kept.len().saturating_sub(COMPACT_REDRAW_LOOKBACK);
    let mut best = 0;
    for &start in positions.iter().rev() {
        if start < floor {
            break;
        }
        let length = kept.len() - start;
        if length <= best || at + length > lines.len() {
            continue;
        }
        let mut visible = 0;
        let mut offset = 0;
        while offset < length && lines[at + offset] == kept[start + offset] {
            if !lines[at + offset].is_empty() {
                visible += 1;
            }
            offset += 1;
        }
        if offset == length && visible >= COMPACT_MIN_REDRAW_LINES {
            best = length;
        }
    }
    best
}

pub fn cap_lines<S: AsRef<str>>(lines: &[S], max_lines: usize) -> Vec<String> {
    if max_lines == 0 {
        return Vec::new();
    }
    let owned = || lines.iter().map(|line| line.as_ref().to_string());
    if lines.len() <= max_lines {
        return owned().collect();
    }
    let head = (max_lines - 1).div_ceil(2);
    let tail = max_lines - 1 - head;
    let omitted = lines.len() - head - tail;
    let mut out: Vec<String> = owned().take(head).collect();
    out.push(format!("… {omitted} lines omitted …"));
    out.extend(owned().skip(lines.len() - tail));
    out
}

impl TerminalCore {
    pub fn tail_output(&self, rows: usize, compact: bool, max_lines: usize) -> String {
        let Ok(snapshot) = self.snapshot() else {
            return String::new();
        };
        let mut lines: Vec<String> = Vec::new();
        if let Some(alt) = &snapshot.alt {
            let skip = alt.row_ranges.len().saturating_sub(rows);
            for (start, end) in alt.row_ranges.iter().skip(skip) {
                lines.push(String::from_utf8_lossy(&alt.content[*start as usize..*end as usize]).into_owned());
            }
        } else {
            let total = snapshot.row_count();
            let mut first = total.saturating_sub(rows);
            while first > 0 && snapshot.row_wrapped(first - 1) {
                first -= 1;
            }
            let mut line = String::new();
            for index in first..total {
                line.push_str(snapshot.row_text(index));
                if !(snapshot.row_wrapped(index) && index + 1 < total) {
                    lines.push(std::mem::take(&mut line));
                }
            }
        }
        let lines = if compact {
            compact_lines(&lines)
        } else {
            while lines.last().is_some_and(|line| line.trim().is_empty()) {
                lines.pop();
            }
            lines
        };
        cap_lines(&lines, max_lines).join("\n")
    }
}
```

- [ ] **Step 3: wasm exports and TS wrappers (failing TS first)**

In `packages/terminal/ts/core/src/compact-output.test.ts` replace lines 1-2 with:

```ts
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { capLines, COMPACT_REDRAW_LOOKBACK, compactLines, initTerminalCore, isSpinnerLine } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	await initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
});
```

Append to `packages/terminal/crates/vt-wasm/src/agent.rs`:

```rust
#[wasm_bindgen]
pub fn is_spinner_line(line: &str) -> bool {
    vt_core::activity::compact::is_spinner_line(line)
}

#[wasm_bindgen]
pub fn compact_lines_text(text: &str) -> String {
    let lines: Vec<&str> = text.split('\n').collect();
    vt_core::activity::compact::compact_lines(&lines).join("\n")
}

#[wasm_bindgen]
pub fn cap_lines_text(text: &str, max_lines: u32) -> String {
    let lines: Vec<&str> = text.split('\n').collect();
    vt_core::activity::compact::cap_lines(&lines, max_lines as usize).join("\n")
}
```
In `packages/terminal/crates/vt-wasm/src/lib.rs` replace `pub use agent::detects_high_confidence_input_pattern;` with `pub use agent::{cap_lines_text, compact_lines_text, detects_high_confidence_input_pattern, is_spinner_line};`.

Replace `packages/terminal/ts/core/src/compact-output.ts` with:

```ts
import { cap_lines_text, compact_lines_text, is_spinner_line } from "../wasm/vt_core.js";

export const COMPACT_REDRAW_LOOKBACK = 256;

export const COMPACT_MIN_REDRAW_LINES = 3;

export function isSpinnerLine(line: string): boolean {
	return is_spinner_line(line);
}

export function compactLines(lines: readonly string[]): string[] {
	const text = compact_lines_text(lines.join("\n"));
	return text === "" ? [] : text.split("\n");
}

export function capLines(lines: readonly string[], maxLines: number): string[] {
	if (Number.isNaN(maxLines)) throw new RangeError("maxLines must be a number, got NaN");
	const cap = Math.floor(maxLines);
	if (cap <= 0) return [];
	if (lines.length <= cap) return [...lines];
	return cap_lines_text(lines.join("\n"), cap).split("\n");
}
```

- [ ] **Step 4: Run, expect pass**

```bash
cd "$REPO/packages/terminal" && cargo fmt && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1 && cargo test -p vt-core --test agent_compact 2>&1 | tail -2
npm run build:wasm -- --force && npm run build:ts && (cd ts/core && npx vitest run 2>&1 | grep -E "Tests  |FAIL") && npm run check:boundaries 2>&1 | tail -1
```
Expected: clippy clean; `4 passed`; ts/core passes with its Task 0 count (compact, block-output and the `claude-long-50k` twenty-turn test included, `TERMINAL.md` §4.34); `boundary check passed`.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-core/src/activity.rs packages/terminal/crates/vt-core/src/activity/compact.rs packages/terminal/crates/vt-core/tests/agent_compact.rs packages/terminal/crates/vt-wasm/src/agent.rs packages/terminal/crates/vt-wasm/src/lib.rs packages/terminal/ts/core/src/compact-output.ts packages/terminal/ts/core/src/compact-output.test.ts
git commit -m "refactor(terminal): output compaction and a compact tail live in vt-core

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: The pty-host sends a compact summary with each settled or prompting transition

**Files:**
- Modify: `packages/terminal/crates/vt-host/src/activity.rs` (export); `backend/internal/adapters/runtime/ptyhost/vtwasm/activity.go` (`TailOutput`), `activity_test.go`; `backend/internal/adapters/runtime/ptyhost/proto.go` (`Summary`); `backend/internal/adapters/runtime/ptyhost/activity.go` (fill it), `activity_test.go`; `backend/internal/ports/terminal_program.go` (`Summary`); `backend/internal/adapters/runtime/ptyhost/program_watch.go` (map it); `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`

**Interfaces:**
- Produces (C ABI): `vt_tail_output(handle, rows, max_lines, out_ptr, out_cap) -> u32` (compact on).
- Produces (Go): `(*Parser).TailOutput(rows, maxLines int) (string, error)`; `ProgramEventPayload.Summary string json:"summary,omitempty"`; `ports.TerminalProgramEvent.Summary string`; host constants `activitySummaryRows = 200`, `activitySummaryLines = 40`.

- [ ] **Step 1: Failing tests**

Append to `backend/internal/adapters/runtime/ptyhost/vtwasm/activity_test.go`:

```go
func TestTailOutputIsTheCompactNewestLines(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "built 3 crates\r\n✽ Compiling… (2s)\r\nall tests passed\r\n")
	got, err := p.TailOutput(200, 40)
	if err != nil || got != "built 3 crates\nall tests passed" {
		t.Fatalf("tail = %q, %v", got, err)
	}
}
```
Append to `backend/internal/adapters/runtime/ptyhost/activity_test.go`:

```go
func TestASettledTransitionCarriesACompactSummary(t *testing.T) {
	fastActivityTick(t)
	f := startServeParsed(t, 947, 80, 24)
	defer f.cancel()
	w := newActivityWatcher(t, f.addr)
	defer w.close()
	writeOutput(t, f, "edited greet.py\r\n✽ Thinking… (1s)\r\nall 42 tests pass\r\n")
	readActivity(t, w, 2*time.Second)
	event := readActivity(t, w, 3*time.Second)
	if event.Activity != "idle" || event.Summary != "edited greet.py\nall 42 tests pass" {
		t.Fatalf("event = %+v, want a compact summary", event)
	}
}
```

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/... -run 'TailOutput|CompactSummary' 2>&1 | tail -3
```
Expected: build failure, `p.TailOutput undefined`.

- [ ] **Step 2: Implementation**

Append to `packages/terminal/crates/vt-host/src/activity.rs`:

```rust
#[no_mangle]
pub extern "C" fn vt_tail_output(handle: u32, rows: u32, max_lines: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => write_out(
            core.tail_output(rows as usize, true, max_lines as usize).as_bytes(),
            out_ptr,
            out_cap,
        ),
        None => RENDER_ERR,
    })
}
```
Append to `backend/internal/adapters/runtime/ptyhost/vtwasm/activity.go`:

```go
const tailOutputBufferBytes = 256 << 10

func (p *Parser) TailOutput(rows, maxLines int) (string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	out, err := p.callLocked("vt_alloc", tailOutputBufferBytes)
	if err != nil {
		return "", err
	}
	defer func() { _, _ = p.callLocked("vt_free", out, tailOutputBufferBytes) }()
	raw, err := p.callLocked("vt_tail_output", uint64(p.handle), uint64(rows), uint64(maxLines), out, tailOutputBufferBytes)
	if err != nil {
		return "", err
	}
	switch written := uint32(raw); written {
	case 0:
		return "", nil
	case renderErr, renderTooBig:
		return "", fmt.Errorf("vtwasm: tail_output failed for handle %d", p.handle)
	default:
		bytes, ok := p.module.Memory().Read(uint32(out), written)
		if !ok {
			return "", fmt.Errorf("vtwasm: read %d bytes at %d out of range", written, out)
		}
		return string(bytes), nil
	}
}
```
In `proto.go` add `Summary    string `json:"summary,omitempty"`` after `CursorLine` in `ProgramEventPayload`. In `ptyhost/activity.go` add `activitySummaryRows = 200` and `activitySummaryLines = 40` to a `const (…)` block with `activityTailRows`, and inside `if state != vtwasm.ActivityActive {` add `event.Summary, _ = h.parser.TailOutput(activitySummaryRows, activitySummaryLines)`. In `ports/terminal_program.go` add `Summary    string` after `CursorLine`. In `program_watch.go` add `Summary:    event.Summary,` to the activity case.

- [ ] **Step 3: Rebuild the mirror wasm; run**

```bash
cd "$REPO/packages/terminal" && cargo fmt && cargo clippy --all-targets -- -D warnings 2>&1 | tail -1 && cargo build --release -p vt-host --target wasm32-unknown-unknown 2>&1 | tail -1
cp target/wasm32-unknown-unknown/release/vt_host.wasm "$REPO/backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm"
cd "$REPO/backend" && go test -race ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... 2>&1 | grep -v "^ok" | tail -3
```
Expected: clean; only the known `TestProcessEnvironmentLetsOverridesWin`, if anything.

Measure the cost once (not committed): time `p.TailOutput(200, 40)` after feeding `packages/terminal/bench/agent-session/fixtures/claude-long-50k/recording` (60,000 lines) in a scratch test; write the milliseconds into the completion report. The call snapshots the whole core, as `vt_render` already does for every `GetOutput` (`vt-host/src/lib.rs:229-266`); it runs once per settled/prompting transition, not per byte.

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add packages/terminal/crates/vt-host/src/activity.rs backend/internal/adapters/runtime/ptyhost/vtwasm/activity.go backend/internal/adapters/runtime/ptyhost/vtwasm/activity_test.go backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm backend/internal/adapters/runtime/ptyhost/proto.go backend/internal/adapters/runtime/ptyhost/activity.go backend/internal/adapters/runtime/ptyhost/activity_test.go backend/internal/ports/terminal_program.go backend/internal/adapters/runtime/ptyhost/program_watch.go
git commit -m "feat(pty-host): send a compact summary of the newest output with each settled transition

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 17: Question text and turn summaries in notification bodies

**Files:**
- Create: `backend/internal/adapters/agent/terminalui/summary.go`, `summary_test.go`; `backend/internal/adapters/agent/claudecode/summary.go`, `summary_test.go`; `backend/internal/adapters/agent/codex/summary.go`, `summary_test.go`; `backend/internal/redact/clean.go`, `clean_test.go`
- Modify: `backend/internal/ports/agent.go` (after `TerminalQuestionReader`); `backend/internal/observe/screen/classify.go` (settled text), `classify_test.go`; `backend/internal/ports/notifications.go:12-33` (`ScreenText`); `backend/internal/lifecycle/manager.go` (the two intents in `ApplyActivitySignal`), `screen_signal_test.go`; `backend/internal/notify/enrich.go:3-8,61-97`, `enrich_test.go`

**Interfaces:**
- Produces (ports): `type TerminalSummaryReader interface { ReadTurnSummary(summary string) (string, bool) }`; `NotificationIntent.ScreenText string`.
- Produces (terminalui): `TurnSummary(lines []string, maxLines int) string` — drops rule/box-only lines and blank lines, keeps the last `maxLines`, `\n`-joined.
- Produces: `(*claudecode.Plugin).ReadTurnSummary` (cuts at the composer's rule line, drops the `✻ … for …` turn footer and the `⏺ `/`⎿ ` markers); `(*codex.Plugin).ReadTurnSummary` (cuts at the last `›` composer line).
- Produces (observe/screen): a settled or waiting `Observation.Text` = the adapter's summary, else `terminalui`-free default `defaultTurnSummary` (the last 6 non-rule lines).
- Produces (redact): `Clean(s string) string` — drops invalid UTF-8, removes terminal escape sequences (OSC `ESC ] … BEL|ST`, CSI `ESC [ … final`, and the other `ESC` sequences, intermediates `0x20-0x2F` then one final byte, such as `ESC 7` and `ESC ( B`), every other control rune except `\n` and `\t` (`unicode.IsControl`) and bidi controls (`unicode.Bidi_Control`), then returns `Text(s).Text` (`redact/redact.go:51`), so masking sees the text a reader will see.
- Bodies (`notify/enrich.go`): needs-input = agent-report reason, else the screen question, else the fixed sentence; turn-finished = the hook's assistant text, else the screen summary, else the fixed sentence; every agent-supplied text goes through `agentText` = `summarize(redact.Clean(text), 120)` — masked before the cut, so the stored row, the mux `notifications` frame (`internal/terminal/notifications.go:44-53`) and ntfy (Task 18) all carry the masked, clean text. Today's `enrich` masks nothing (`notify/enrich.go:61-106` has no `redact` call; the only `redact.Text` callers are the block-event service, slash output and hand-off, `service/blockevent/service.go:71,129,217-219`, `session_manager/slash_output.go:50`, `session_manager/handoff_artifact.go:114`).

- [ ] **Step 1: Failing tests**

Create `backend/internal/adapters/agent/terminalui/summary_test.go`:

```go
package terminalui

import "testing"

func TestTurnSummaryKeepsTheLastLinesWithoutRules(t *testing.T) {
	lines := []string{"one", "", "────", "two", "╭──╮", "three", "four"}
	if got := TurnSummary(lines, 3); got != "two\nthree\nfour" {
		t.Fatalf("summary = %q", got)
	}
}
```
Create `backend/internal/adapters/agent/claudecode/summary_test.go`:

```go
package claudecode

import "testing"

func TestReadTurnSummaryStopsAtTheComposerAndDropsTheTurnFooter(t *testing.T) {
	summary := "⏺ Updated greet.py to print a farewell.\n  git diff --stat:\n   greet.py | 7 ++++++-\n✻ Baked for 11s · done 6:13 PM\n────────\n❯\n────────\n  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok || got != "Updated greet.py to print a farewell.\ngit diff --stat:\ngreet.py | 7 ++++++-" {
		t.Fatalf("summary = %q, %v", got, ok)
	}
}
```
Create `backend/internal/adapters/agent/codex/summary_test.go`:

```go
package codex

import "testing"

func TestReadTurnSummaryStopsAtTheComposer(t *testing.T) {
	summary := "• Created approved.txt.\n────────\n› Improve documentation in @filename\n  gpt-5.6-luna medium · ~/demo"
	got, ok := (&Plugin{}).ReadTurnSummary(summary)
	if !ok || got != "• Created approved.txt." {
		t.Fatalf("summary = %q, %v", got, ok)
	}
}
```
Append to `backend/internal/observe/screen/classify_test.go`:

```go
func TestClassifySettledCarriesTheTurnSummary(t *testing.T) {
	event := activity(ports.TerminalActivityIdle, pane(t, "claudecode_idle.txt"), "")
	event.Summary = "⏺ Done: 42 tests pass.\n✻ Brewed for 21s · done 5:42 AM\n────\n❯\n────"
	if got := Classify(claudecode.New(), event); got.Reading != domain.ScreenSettled || got.Text != "Done: 42 tests pass." {
		t.Fatalf("Classify = %+v", got)
	}
	plain := activity(ports.TerminalActivityIdle, "compiling", "")
	plain.Summary = "step 1\n────\nstep 2"
	if got := Classify(nil, plain); got.Text != "step 1\nstep 2" {
		t.Fatalf("default summary = %q", got.Text)
	}
}
```
Append to `backend/internal/lifecycle/screen_signal_test.go`:

```go
func TestScreen_IntentsCarryTheScreenText(t *testing.T) {
	m, _, sink, now := alertManager(t, domain.ActivityActive)
	clock := movableClock(m, now)
	question := screenSignal(domain.ScreenQuestion, "q")
	question.ScreenText = "Allow command `rm -rf build`?"
	if err := m.ApplyActivitySignal(ctx, "mer-1", question); err != nil {
		t.Fatal(err)
	}
	*clock = now.Add(5 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", screenSignal(domain.ScreenWorking, "")); err != nil {
		t.Fatal(err)
	}
	settledSignal := screenSignal(domain.ScreenSettled, "")
	settledSignal.ScreenText = "Removed build/."
	*clock = now.Add(10 * time.Second)
	if err := m.ApplyActivitySignal(ctx, "mer-1", settledSignal); err != nil {
		t.Fatal(err)
	}
	needs := intentsOf(sink, domain.NotificationNeedsInput)
	done := intentsOf(sink, domain.NotificationTurnFinished)
	if len(needs) != 1 || needs[0].ScreenText != "Allow command `rm -rf build`?" || len(done) != 1 || done[0].ScreenText != "Removed build/." {
		t.Fatalf("needs=%+v done=%+v", needs, done)
	}
}
```
Append to `backend/internal/notify/enrich_test.go`:

```go
func TestEnrichUsesScreenTextWhenTheHookGaveNone(t *testing.T) {
	t.Parallel()
	needs, err := enrich(Intent{Type: domain.NotificationNeedsInput, SessionID: "s", ProjectID: "p", ScreenText: "Allow command `rm -rf build`?", CreatedAt: time.Now()})
	if err != nil || needs.Body != "Allow command `rm -rf build`?" {
		t.Fatalf("needs body = %q, %v", needs.Body, err)
	}
	done, err := enrich(Intent{Type: domain.NotificationTurnFinished, SessionID: "s", ProjectID: "p", ScreenText: "Removed build/.\nAll tests pass.", CreatedAt: time.Now()})
	if err != nil || done.Body != "Removed build/. All tests pass." {
		t.Fatalf("done body = %q, %v", done.Body, err)
	}
	hook, _ := enrich(Intent{Type: domain.NotificationTurnFinished, SessionID: "s", ProjectID: "p", AssistantUpdate: "From the hook.", ScreenText: "From the screen.", CreatedAt: time.Now()})
	if hook.Body != "From the hook." {
		t.Fatalf("the hook's text lost to the screen: %q", hook.Body)
	}
}

func TestEnrichMasksAndCleansAgentTextBeforeItLeaves(t *testing.T) {
	t.Parallel()
	question, err := enrich(Intent{Type: domain.NotificationNeedsInput, SessionID: "s", ProjectID: "p", ScreenText: "Allow \x1b[1mcurl -H 'Authorization: Bearer abcdefghijklmnop1234'\x1b[0m?", CreatedAt: time.Now()})
	if err != nil || question.Body != "Allow curl -H 'Authorization: Bearer [redacted]'?" {
		t.Fatalf("question body = %q, %v", question.Body, err)
	}
	reason, _ := enrich(Intent{Type: domain.NotificationNeedsInput, SessionID: "s", ProjectID: "p", AgentReportReason: "Paste the token: abcdefgh12345678\x07", CreatedAt: time.Now()})
	if reason.Body != "Paste the token: [redacted]" {
		t.Fatalf("reason body = %q", reason.Body)
	}
	done, _ := enrich(Intent{Type: domain.NotificationTurnFinished, SessionID: "s", ProjectID: "p", AssistantUpdate: "Set the key to sk-abcdefghijklmnopqrstuvwxyz and pushed.\n\x1b[32mdone\x1b[0m", CreatedAt: time.Now()})
	if done.Body != "Set the key to [redacted] and pushed. done" {
		t.Fatalf("done body = %q", done.Body)
	}
}

func TestEnrichMasksBeforeTruncating(t *testing.T) {
	t.Parallel()
	text := strings.Repeat("x ", 55) + "sk-" + strings.Repeat("a", 30) + " tail"
	rec, err := enrich(Intent{Type: domain.NotificationTurnFinished, SessionID: "s", ProjectID: "p", ScreenText: text, CreatedAt: time.Now()})
	if want := strings.Repeat("x ", 55) + "[redacted]…"; err != nil || rec.Body != want {
		t.Fatalf("body = %q, want %q (%v)", rec.Body, want, err)
	}
}
```
Create `backend/internal/redact/clean_test.go`:

```go
package redact

import "testing"

func TestCleanMasksSecretsAndStripsEscapesAndControls(t *testing.T) {
	for _, tc := range []struct {
		in   string
		want string
	}{
		{"Run \x1b[31mcurl -H 'Authorization: Bearer abcdefghijklmnop1234'\x1b[0m\x1b]0;title\x07 now?\x07‮\x00\n\tnext\xff", "Run curl -H 'Authorization: Bearer [redacted]' now?\n\tnext"},
		{"key sk-abcdefghijklmnopqrstuvwxyz‮ end\x9b", "key [redacted] end"},
		{"\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\ \x1b7saved\x1b8", "link saved"},
		{"plain text stays", "plain text stays"},
		{"", ""},
	} {
		if got := Clean(tc.in); got != tc.want {
			t.Fatalf("Clean(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
```

```bash
cd "$REPO/backend" && go test ./internal/adapters/agent/... ./internal/observe/screen/ ./internal/lifecycle/ ./internal/notify/ ./internal/redact/ 2>&1 | grep -E "FAIL|undefined|unknown field" | head -8
```
Expected: build failures naming `TurnSummary`, `ReadTurnSummary`, `Summary`, `ScreenText`, `Clean`.

- [ ] **Step 2: Implementation**

`backend/internal/ports/agent.go`, after `TerminalQuestionReader`:

```go
type TerminalSummaryReader interface {
	ReadTurnSummary(summary string) (string, bool)
}
```
`backend/internal/ports/notifications.go`: after `AgentReportReason string` add `ScreenText string`.

Create `backend/internal/adapters/agent/terminalui/summary.go`:

```go
package terminalui

import "strings"

func TurnSummary(lines []string, maxLines int) string {
	var kept []string
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.Trim(line, "─━═╌┄│╭╮╰╯ ") == "" {
			continue
		}
		kept = append(kept, line)
	}
	return strings.Join(kept[max(0, len(kept)-maxLines):], "\n")
}
```
Create `backend/internal/adapters/agent/claudecode/summary.go`:

```go
package claudecode

import (
	"regexp"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

var claudeTurnFooter = regexp.MustCompile(`^✻ \S+ for \S+`)

func (p *Plugin) ReadTurnSummary(summary string) (string, bool) {
	lines := strings.Split(summary, "\n")
	for i := len(lines) - 1; i > 0; i-- {
		if strings.HasPrefix(strings.TrimSpace(lines[i]), "❯") && isRuleLine(strings.TrimSpace(lines[i-1])) {
			lines = lines[:i-1]
			break
		}
	}
	var kept []string
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if claudeTurnFooter.MatchString(line) {
			continue
		}
		line = strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(line, "⏺"), "⎿"))
		kept = append(kept, line)
	}
	text := terminalui.TurnSummary(kept, 6)
	return text, text != ""
}

var _ ports.TerminalSummaryReader = (*Plugin)(nil)
```
Create `backend/internal/adapters/agent/codex/summary.go`:

```go
package codex

import (
	"strings"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/terminalui"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (p *Plugin) ReadTurnSummary(summary string) (string, bool) {
	lines := strings.Split(summary, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.HasPrefix(strings.TrimSpace(lines[i]), "›") {
			lines = lines[:i]
			break
		}
	}
	text := terminalui.TurnSummary(lines, 6)
	return text, text != ""
}

var _ ports.TerminalSummaryReader = (*Plugin)(nil)
```
In `backend/internal/observe/screen/classify.go` replace the detector switch's two settled returns

```go
	case domain.ActivityIdle:
		return Observation{Reading: domain.ScreenSettled, Confirm: ScreenSettleConfirm}
	case domain.ActivityWaitingInput:
		return Observation{Reading: domain.ScreenWaiting, Confirm: ScreenSettleConfirm}
```
with
```go
	case domain.ActivityIdle:
		return Observation{Reading: domain.ScreenSettled, Text: turnSummary(agent, event.Summary), Confirm: ScreenSettleConfirm}
	case domain.ActivityWaitingInput:
		return Observation{Reading: domain.ScreenWaiting, Text: turnSummary(agent, event.Summary), Confirm: ScreenSettleConfirm}
```
replace `return Observation{Reading: domain.ScreenSettled, Confirm: ScreenQuietSettle}` with `return Observation{Reading: domain.ScreenSettled, Text: turnSummary(agent, event.Summary), Confirm: ScreenQuietSettle}`, and add:

```go
func turnSummary(agent any, summary string) string {
	if reader, ok := agent.(ports.TerminalSummaryReader); ok {
		text, _ := reader.ReadTurnSummary(summary)
		return text
	}
	return defaultTurnSummary(summary)
}

func defaultTurnSummary(summary string) string {
	var kept []string
	for _, line := range strings.Split(summary, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.Trim(line, "─━═╌┄│╭╮╰╯ ") == "" {
			continue
		}
		kept = append(kept, line)
	}
	return strings.Join(kept[max(0, len(kept)-6):], "\n")
}
```
(A settled decision's `Identity` stays empty, so a new summary for the same settled reading is not a new decision: the debouncer compares reading and identity, `debounce.go`.)

In `backend/internal/lifecycle/manager.go` `ApplyActivitySignal`: in the needs-input case, after `intent = m.sessionIntent(domain.NotificationNeedsInput, next)` add `intent.ScreenText = s.ScreenText`; replace `intent = m.sessionIntent(domain.NotificationTurnFinished, next)` with

```go
			intent = m.sessionIntent(domain.NotificationTurnFinished, next)
			intent.ScreenText = s.ScreenText
```
Create `backend/internal/redact/clean.go`:

```go
package redact

import (
	"regexp"
	"strings"
	"unicode"
)

var terminalEscape = regexp.MustCompile(`\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b\[[0-?]*[ -/]*[@-~]|\x1b[ -/]*[0-~]`)

func Clean(s string) string {
	s = strings.ToValidUTF8(s, "")
	s = terminalEscape.ReplaceAllString(s, "")
	s = strings.Map(func(r rune) rune {
		if r == '\n' || r == '\t' {
			return r
		}
		if unicode.IsControl(r) || unicode.Is(unicode.Bidi_Control, r) {
			return -1
		}
		return r
	}, s)
	return Text(s).Text
}
```
(The expressions and every expected string in `clean_test.go`, `TestEnrichMasksAndCleansAgentTextBeforeItLeaves` and `TestEnrichMasksBeforeTruncating` were checked on 2026-09-27 against a copy of `redact/redact.go` in a scratch module; they print exactly the wanted values.)

In `backend/internal/notify/enrich.go` add `"github.com/OmarAly92/operator/backend/internal/redact"` to the imports (lines 3-8) and add below `summarize`:

```go
func agentText(text string) string {
	return summarize(redact.Clean(text), turnSummaryRunes)
}
```
In `bodyForIntent`, replace the needs-input case's body

```go
		if reason := summarize(intent.AgentReportReason, turnSummaryRunes); reason != "" {
			return reason
		}
		return "Your agent is waiting on you to continue."
```
with
```go
		if reason := agentText(intent.AgentReportReason); reason != "" {
			return reason
		}
		if question := agentText(intent.ScreenText); question != "" {
			return question
		}
		return "Your agent is waiting on you to continue."
```
and the turn-finished case's

```go
		if summary := summarize(intent.AssistantUpdate, turnSummaryRunes); summary != "" {
			return summary
		}
		return "Your agent finished its turn."
```
with
```go
		if summary := agentText(intent.AssistantUpdate); summary != "" {
			return summary
		}
		if summary := agentText(intent.ScreenText); summary != "" {
			return summary
		}
		return "Your agent finished its turn."
```
`TestEnrichTurnFinished` (`notify/enrich_test.go:56-72`, 200 × `a` capped to 120 runes plus `…`) keeps passing: `a` runs match no pattern in `redact.go:36-43`.

- [ ] **Step 3: Run, expect pass**

```bash
cd "$REPO/backend" && go test ./internal/adapters/agent/... ./internal/observe/... ./internal/lifecycle/... ./internal/notify/... ./internal/redact/... ./internal/push/... 2>&1 | grep -v "^ok" | tail -5
go test ./internal/observe/screen/ -run TestAgentSignalsOnRecordings -v 2>&1 | grep -E "alerts=|--- "
```
Expected: no output from the first; the recordings table unchanged from Phase A (summaries do not change readings or identities).

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add backend/internal/redact/clean.go backend/internal/redact/clean_test.go backend/internal/ports/agent.go backend/internal/ports/notifications.go backend/internal/adapters/agent/terminalui/summary.go backend/internal/adapters/agent/terminalui/summary_test.go backend/internal/adapters/agent/claudecode/summary.go backend/internal/adapters/agent/claudecode/summary_test.go backend/internal/adapters/agent/codex/summary.go backend/internal/adapters/agent/codex/summary_test.go backend/internal/observe/screen/classify.go backend/internal/observe/screen/classify_test.go backend/internal/lifecycle/manager.go backend/internal/lifecycle/screen_signal_test.go backend/internal/notify/enrich.go backend/internal/notify/enrich_test.go
git commit -m "feat(notify): the question and a compact turn summary from the screen fill empty notification bodies, masked and cleaned

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 18: Phone alerts through ntfy carry the masked question and summary

**Files:**
- Modify: `backend/internal/push/ntfy.go:13-19` (`ntfyMessageBytes`); `backend/internal/push/alerts.go:3-14` (imports), `:197-210` (`alertFor`, new `phoneMessage` and `truncateBytes`); `backend/internal/push/alerts_test.go:3-14` (import `unicode/utf8`), `:55-68` (`TestAlertsSendsWhenPairedAndBackgrounded`, rewritten), `:125-134` (`TestAlertsPRTypesNeverCarryThePRTitle`, one more condition), two new tests appended

**Interfaces:**
- Produces (push): `ntfyMessageBytes = 4096` — ntfy's maximum message size; a larger or non-UTF-8 body is turned into an attachment by the server (<https://docs.ntfy.sh/publish/>, checked 2026-09-27; see Global Constraints for the quote). Today `NtfySender.post` sends `alert.Message` as the raw request body with no cap (`push/ntfy.go:57`).
- Produces: `phoneMessage(rec domain.NotificationRecord) string` — for `needs_input` and `turn_finished`, the record's body passed through `redact.Clean` again (the body was already cleaned by `notify/enrich.go`, Task 17; this is the last point before a third-party server, so it does not trust its caller), whitespace-collapsed to one line, capped at `ntfyMessageBytes` on a rune boundary with a trailing `…`; an empty result falls back to the event word. Every other type keeps the event word (`alerts.go:212-229`): PR bodies carry PR titles (`notify/enrich.go:68-86`) and agent-exited has a fixed sentence.
- Consumes: `redact.Clean` (Task 17).
- Mobile: no change. The in-app local notification already shows `body` (`packages/mobile/lib/core/notifications/phone_alerts_runtime.dart:66-70` → `local_alert_sink.dart:47-51`, `title` and `body` passed to `FlutterLocalNotificationsPlugin.show`); the ntfy notification is drawn by the ntfy app from the message, and Operator has no ntfy client code (`phone_alerts_cubit.dart:35-49` only copies the topic). The in-app body is capped at 120 runes by `enrich`, so it is never near the ntfy cap; the cap guards any longer body a later change might produce.

- [ ] **Step 1: Failing tests**

In `backend/internal/push/alerts_test.go` add `"unicode/utf8"` to the imports and replace `TestAlertsSendsWhenPairedAndBackgrounded` (`:55-68`) with:

```go
func TestAlertsSendsWhenPairedAndBackgrounded(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "operator-4"))
	if len(sender.sent) != 1 || sender.topics[0] != paired.AlertTopic {
		t.Fatalf("sent=%+v topics=%v", sender.sent, sender.topics)
	}
	got := sender.sent[0]
	if got.Title != "operator-4 finished" || got.Message != "Implemented X in /secret/path.go" || got.Click != "operator://session/operator-4" {
		t.Fatalf("alert = %+v, want the notification body as the message", got)
	}
}
```
In `TestAlertsPRTypesNeverCarryThePRTitle` (`:125-134`) replace `if len(sender.sent) != 1 || strings.Contains(sender.sent[0].Title, "Secret") {` with `if len(sender.sent) != 1 || strings.Contains(sender.sent[0].Title, "Secret") || sender.sent[0].Message != "ready to merge" {`.

Append:

```go
func TestAlertsMaskSecretsAndStripControlsInTheBody(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	rec := record(domain.NotificationNeedsInput, "s1")
	rec.Body = "Run \x1b[31mcurl -H 'Authorization: Bearer abcdefghijklmnop1234'\x1b[0m with password=hunter2hunter2?\x07\nnext line"
	a.dispatch(context.Background(), rec)
	if len(sender.sent) != 1 || sender.sent[0].Message != "Run curl -H 'Authorization: Bearer [redacted]' with password=[redacted] next line" {
		t.Fatalf("sent = %+v", sender.sent)
	}
	a.dispatch(context.Background(), record(domain.NotificationAgentExited, "s2"))
	if len(sender.sent) != 2 || sender.sent[1].Message != "exited" {
		t.Fatalf("exited alert = %+v, want the event word", sender.sent)
	}
	blank := record(domain.NotificationTurnFinished, "s3")
	blank.Body = "\x1b[0m\x07 "
	a.dispatch(context.Background(), blank)
	if len(sender.sent) != 3 || sender.sent[2].Message != "finished" {
		t.Fatalf("blank body alert = %+v, want the event word", sender.sent)
	}
}

func TestAlertsCapTheBodyAtNtfysMessageLimit(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	rec := record(domain.NotificationTurnFinished, "s1")
	rec.Body = strings.Repeat("é", ntfyMessageBytes)
	a.dispatch(context.Background(), rec)
	if len(sender.sent) != 1 {
		t.Fatalf("sent %d, want 1", len(sender.sent))
	}
	msg := sender.sent[0].Message
	if len(msg) > ntfyMessageBytes || !utf8.ValidString(msg) || !strings.HasPrefix(msg, "éé") || !strings.HasSuffix(msg, "…") {
		t.Fatalf("message is %d bytes, valid UTF-8 %v, want at most %d ending in …", len(msg), utf8.ValidString(msg), ntfyMessageBytes)
	}
}
```

```bash
cd "$REPO/backend" && go test ./internal/push/ 2>&1 | tail -3
```
Expected: build failure, `undefined: ntfyMessageBytes`.

- [ ] **Step 2: Implementation**

In `backend/internal/push/ntfy.go` add `ntfyMessageBytes  = 4096` to the `const (…)` block (`:13-19`).

In `backend/internal/push/alerts.go` add `"strings"` and `"unicode/utf8"` to the standard-library imports and `"github.com/OmarAly92/operator/backend/internal/redact"` to the module imports; in `alertFor` replace `alert := Alert{Title: rec.Title, Message: eventWord(rec.Type), Priority: PriorityDefault}` with `alert := Alert{Title: rec.Title, Message: phoneMessage(rec), Priority: PriorityDefault}`; and add after `alertFor`:

```go
func phoneMessage(rec domain.NotificationRecord) string {
	if rec.Type != domain.NotificationNeedsInput && rec.Type != domain.NotificationTurnFinished {
		return eventWord(rec.Type)
	}
	body := strings.Join(strings.Fields(redact.Clean(rec.Body)), " ")
	if body == "" {
		return eventWord(rec.Type)
	}
	return truncateBytes(body, ntfyMessageBytes)
}

func truncateBytes(text string, limit int) string {
	if len(text) <= limit {
		return text
	}
	cut := limit - len("…")
	for cut > 0 && !utf8.RuneStart(text[cut]) {
		cut--
	}
	return text[:cut] + "…"
}
```
(Checked on 2026-09-27 in a scratch module against a copy of `redact/redact.go`: the masking test's body becomes exactly the wanted message, and 4,096 × `é` becomes a 4,095-byte valid message ending in `…`.)

- [ ] **Step 3: Run, expect pass; commit**

```bash
cd "$REPO/backend" && go test -race ./internal/push/... ./internal/notify/... ./internal/redact/... 2>&1 | tail -3
cd "$REPO" && git add backend/internal/push/ntfy.go backend/internal/push/alerts.go backend/internal/push/alerts_test.go
git commit -m "feat(push): ntfy phone alerts carry the masked question and turn summary, capped at 4096 bytes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Expected: three `ok` lines.

---

### Task 19: A needs-you phone alert is never swallowed by a different alert

**Files:**
- Modify: `backend/internal/push/alerts.go` (`lastSent` field, `NewAlerts`, the coalescing check in `dispatch`; at `611254eb3` lines `:62`, `:66-77`, `:169-173`, shifted down by Task 18's three import lines); `backend/internal/push/alerts_test.go` (`TestAlertsCoalescePerSessionForTenSeconds`, `:100-113` at `611254eb3`, shifted by Task 18)

**Interfaces:**
- Produces: `type alertKey struct { session domain.SessionID; typ domain.NotificationType }`; coalescing is per session **and type** for 10 s (`coalesceWindow`, `alerts.go:17`). The ntfy message is Task 18's masked body; Task 18's `TestAlertsSendsWhenPairedAndBackgrounded`, `TestAlertsMaskSecretsAndStripControlsInTheBody` and `TestAlertsCapTheBodyAtNtfysMessageLimit` keep passing unchanged.

- [ ] **Step 1: Failing test**

Replace `TestAlertsCoalescePerSessionForTenSeconds` with:

```go
func TestAlertsCoalescePerSessionAndTypeForTenSeconds(t *testing.T) {
	a, sender, now := setup(t, paired, true, false)
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "s1"))
	a.dispatch(context.Background(), record(domain.NotificationNeedsInput, "s1"))
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "s2"))
	if len(sender.sent) != 3 {
		t.Fatalf("sent %d, want 3 (a needs-you alert is not swallowed by a finished one)", len(sender.sent))
	}
	a.dispatch(context.Background(), record(domain.NotificationNeedsInput, "s1"))
	if len(sender.sent) != 3 {
		t.Fatalf("sent %d, want the second needs-you inside the window coalesced", len(sender.sent))
	}
	*now = now.Add(11 * time.Second)
	a.dispatch(context.Background(), record(domain.NotificationNeedsInput, "s1"))
	if len(sender.sent) != 4 {
		t.Fatalf("sent %d after the window, want 4", len(sender.sent))
	}
}
```

```bash
cd "$REPO/backend" && go test ./internal/push/ -run TestAlertsCoalesce 2>&1 | tail -3
```
Expected: FAIL, `sent 2, want 3`.

- [ ] **Step 2: Implementation**

In `alerts.go`: add `type alertKey struct { session domain.SessionID; typ domain.NotificationType }`; change the field to `lastSent   map[alertKey]time.Time`; in `NewAlerts` `lastSent: map[alertKey]time.Time{}`; in `dispatch` replace

```go
	if last, ok := a.lastSent[rec.SessionID]; ok && now.Sub(last) < coalesceWindow {
		a.mu.Unlock()
		return
	}
	a.lastSent[rec.SessionID] = now
```
with
```go
	key := alertKey{session: rec.SessionID, typ: rec.Type}
	if last, ok := a.lastSent[key]; ok && now.Sub(last) < coalesceWindow {
		a.mu.Unlock()
		return
	}
	a.lastSent[key] = now
```

- [ ] **Step 3: Run, expect pass; commit**

```bash
cd "$REPO/backend" && go test -race ./internal/push/... 2>&1 | tail -1
cd "$REPO" && git add backend/internal/push/alerts.go backend/internal/push/alerts_test.go
git commit -m "fix(push): coalesce phone alerts per session and type so a needs-you alert is never swallowed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Expected: `ok`.

---

### Task 20: Phase B — docs, all gates, real-app check

**Files:**
- Modify: `TERMINAL.md` (§4.52, add a "Phase B" bullet; §4.34 `readBlockOutput` bullet: "compaction now in `vt-core` `activity/compact.rs`"), `packages/terminal/CHANGELOG.md`, `docs/terminal/2026-09-19-terminal-reference-survey.md` (§6.9 status), `docs/STATUS.md`, `docs/superpowers/specs/2026-09-23-agent-alerts-design.md:51,244-245` (D6 and the NtfySender body line)

**Interfaces:** none.

- [ ] **Step 1: Docs**

TERMINAL.md §4.52, new last bullet: "Phase B: `TerminalCore::tail_output` (`activity/compact.rs`, the TS compaction ported and shared) gives each settled/prompting transition a 40-line compact summary of the newest 200 rows; adapters trim it (`ReadTurnSummary`: Claude Code cuts at its composer and drops the `✻ … for …` footer, Codex cuts at `›`); a notification body is the hook's text, else the screen's question or summary, else the fixed sentence (`notify/enrich.go`), every agent-supplied text passed through `redact.Clean` (`backend/internal/redact/clean.go`: escape sequences, control runes and bidi controls removed, then `redact.Text` masks secrets, before the 120-rune cut). ntfy carries the same body for needs-you and finished alerts (decided by the user 2026-09-27, reversing the agent-alerts spec's D6), cleaned and masked again in `push/alerts.go` `phoneMessage` and capped at ntfy's 4,096-byte message limit (larger bodies would arrive as an attachment, <https://docs.ntfy.sh/publish/>); PR alerts keep one word. Phone alerts coalesce per session and type. Guards: `redact/clean_test.go`, `notify/enrich_test.go` `TestEnrichMasksAndCleansAgentTextBeforeItLeaves` and `TestEnrichMasksBeforeTruncating`, `push/alerts_test.go` `TestAlertsSendsWhenPairedAndBackgrounded`, `TestAlertsMaskSecretsAndStripControlsInTheBody`, `TestAlertsCapTheBodyAtNtfysMessageLimit`, `TestAlertsCoalescePerSessionAndTypeForTenSeconds`."
CHANGELOG (Unreleased): "vt-core: output compaction (`compact_lines`, `cap_lines`, `is_spinner_line`) moved from `ts/core` and `TerminalCore::tail_output(rows, compact, max_lines)` added; vt-host exports `vt_tail_output`; `ts/core` `compactLines`/`capLines`/`isSpinnerLine` wrap the wasm exports and need `initTerminalCore` first (breaking). Both wasm artifacts and the daemon must be rebuilt."
Survey §6.9 status: "compact summaries feed Operator's notifications since wave 1 phase B (`TERMINAL.md` §4.52)." STATUS.md: update the Phase A line to name phase B and add "phone alerts through ntfy carry the masked question or summary".
In `docs/superpowers/specs/2026-09-23-agent-alerts-design.md` replace the D6 row (line 51) with `| D6 | ntfy messages carry the session display name and the event only, never terminal output or assistant text. **Superseded 2026-09-27 by the user:** needs-you and finished alerts carry the notification body (the question or the turn summary), cleaned and secret-masked by \`redact.Clean\` and capped at 4,096 bytes; PR alerts keep the event word (agent signals wave 1 phase B, \`TERMINAL.md\` §4.52). |`, and in the `NtfySender` bullet (lines 244-245) replace "Body is the\n  event word only (D6)." with "Body is the\n  event word for PR alerts and the masked notification body for needs-you and finished alerts (D6, superseded 2026-09-27)."

- [ ] **Step 2: All gates** — repeat Task 14 Step 3 exactly (both wasm builds, vitest per package, `check:boundaries`, `bench:agent:gate`, `go vet`, `go test ./...`, the race subset plus `./internal/push/... ./internal/notify/... ./internal/redact/...`, `npm run lint`, frontend typecheck and tests). `flutter analyze`/`flutter test`: not run — no `packages/mobile` change.

- [ ] **Step 3: Real-app check (phase B)** — same isolated daemon and rules as Task 14 Step 4 (ask first).
1. Claude Code AskUserQuestion with the pane closed: the open `needs_input` row's `body` in `GET /api/v1/notifications` names the question (not "Your agent is waiting on you to continue.") when the agent report is empty.
2. A turn that ends with the Stop hook lost (Task 14 Step 4.5's fake `pre-tool-use` hook, then wait): the `turn_finished` body is the screen summary of the reply, without spinner lines, the composer or the `✻ … for …` footer.
3. Phone via the mux `notifications` channel (Python `websockets` client subscribed as the mobile app does, `mux_client.dart:390-398`): the `notification` frame's `body` equals the row's body.
4. ntfy (ask the user first: this sends one question, one summary and one masked fake secret to ntfy.sh; the daemon has no ntfy server override, `daemon/daemon.go:366` passes `push.DefaultNtfyServer`). With Connect Mobile on and a claimed topic (`POST /api/v1/phone-alerts/subscribe` with the pairing password, which returns the topic, `httpd/controllers/phone_alerts.go:27`; `GET /api/v1/phone-alerts` then shows `claimed: true`, `phone_alerts_lan_test.go:128-132,186`) and no foreground `notifications` subscription, read what ntfy.sh actually stored with `curl -s "https://ntfy.sh/<topic>/json?poll=1&since=10m"` (ntfy's poll API, <https://docs.ntfy.sh/subscribe/api/>): (a) the needs-you question from step 1 is the `message` of a `high`-priority entry and equals the row's body; (b) the finished summary from step 2 is the `message` of the next entry; (c) prompt Claude Code "Print the line `password=hunter2hunter2` and then use AskUserQuestion to ask me whether to keep it" and confirm the row's body, the mux frame's body and the ntfy `message` show `password=[redacted]` and none contains `hunter2hunter2` (a fake value, never a real secret); (d) a needs-input right after a finished alert for the same session is delivered (not coalesced).
5. The phone (ask the user; iOS ntfy banners show only when the phone is locked, per memory): with the phone locked, the ntfy banner shows the question text for a needs-you alert and the summary for a finished alert. Ask the user what the banner shows and write their answer into the report.
6. The in-app local notification (Operator open in the background on the phone, mux `notifications` subscribed): its body is the same text (`phone_alerts_runtime.dart:66-70`). Ask the user to confirm on the phone; `not run: <reason>` if no phone is paired.
Record results; anything not run is `not run: <reason>`.

- [ ] **Step 4: Commit**

```bash
cd "$REPO" && git add TERMINAL.md packages/terminal/CHANGELOG.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/STATUS.md docs/superpowers/specs/2026-09-23-agent-alerts-design.md
git commit -m "docs(terminal): agent signals wave 1 phase B (§4.52), changelog, survey, status and the ntfy body decision

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Open decisions for the user

1. **May the screen raise needs-you while a hook is fresh?** This plan says yes in one case only: a question drawn on screen after the hook's own `active` (`MergeScreenReading`, fresh branch). It fills a gap when a `PermissionRequest` hook is lost, and cannot contradict the hook (the hook said "working", which was true when it was sent). If "never overrides a fresh hook" is meant strictly, delete that branch and its test row; a lost permission hook is then noticed 30 s later instead of about 2 s later.
2. **Terminal text to ntfy.sh.** Bodies (question text, turn summaries) reach the phone through the mux channel and the in-app list only. Sending them through ntfy.sh (a third-party server) would give the locked phone the summary too; today's test (`push/alerts_test.go:55-68`) forbids it on purpose. Say so if the summary should go to ntfy, and whether it should be opt-in in Settings → Phone alerts.
3. **An agent with no hooks and no adapter detector (aider, pi, auggie) is called settled only after 60 s of silence.** That keeps a quiet thinker from flipping to "done", but a real "done" shows 60 s late. Recording one of these agents (none is installed on this machine: `which aider` found nothing) would let the number be measured instead of chosen.
4. **Hook freshness is memory-only.** After a daemon restart nothing is fresh, so for up to 30 s the screen may correct a hook-reported state without waiting. A durable `activity_source`/`hook_at` column would avoid that at the cost of a migration.

## Risks

- **Codex's approval prompt shape is unverified.** `codex.ReadQuestion` assumes a numbered `›` menu (the existing test pane, `codex/terminal_activity_test.go:24-27`, not a recording). Task 2's `codex-approval` recording is the check; if Codex 0.157 draws something else, Task 13 fails with a missed question and the reader needs the real screen.
- **Claude Code's footer text drives two readers.** `esc to interrupt` (working) and the `✻ … for …` footer come from 2.1.260–2.1.280 screens (`crates/vt-core/tests/ref/claude_spinner_10s/screen.txt`, `backend/testdata/panes/claudecode_idle.txt`). A Claude Code release that renames them makes the composer detector return no reading (safe: no false alarm, only no screen correction). Task 13's recordings pin the version; re-record when Claude Code changes its footer.
- **The mirror runs scalar width, the renderer grapheme width** (`TERMINAL.md` §5). The cursor-line padding can differ by a cell on emoji sequences, so a prompt ending in such a sequence could match in one copy and not the other. Only the mirror drives Operator's status.
- **CPU per session.** Every pty-host now wakes every 250 ms and calls `vt_live_output_bytes` (and, when quiet ≥ 500 ms, `vt_agent_activity`, which builds the cursor line). A full snapshot happens only on a settled/prompting transition (`RenderTail`, phase B `TailOutput`). Not measured here; the real-app check should note CPU of an idle pty-host (`ps -o %cpu`) before and after.
- **Old pty-hosts keep old code.** Sessions started before the daemon rebuild publish no activity until relaunched (`TERMINAL.md` §3.5); their cards behave as today.
- **Question identity under truncation.** The identity is whitespace-collapsed so a rewrap gives the same identity (Task 10 test), but a UI that truncates a long line with `…` at a narrower width would give a different identity, and a resize during a question would then read as a second question (a second alert). Claude Code's dialogs wrap rather than truncate (`backend/testdata/panes/claudecode_permission.txt`, row 2); `claude-two-permissions` resizes during its first question so Task 13 `dup` catches it if that changes.
- **Harness fidelity.** The recordings have no keystroke-accurate typing (the driver sends text at once) and the hook timing in `hooks`/`missed-stop` modes is synthetic (300 ms after each truth boundary). The measured counts are for these recordings and these assumptions; they are not a proof for every agent release.

## Self-review

- **Spec coverage (wishlist item 2):** status for any agent — Tasks 3–12 (screen path; `hookless` mode in Task 13 is the no-hook case). Quicker needs-you on card and phone — screen question confirmed ~1.5–2.5 s after it is drawn (Task 11 hold times), through the existing notification path (Task 9); phone coalescing fixed (Task 18). Check on hooks / no stale card — merge rule and re-assert (Tasks 8, 9, 12), missed-stop measurement (Task 13), Claude Code detector also feeding the old poller (Task 10). Clean summaries — Tasks 15–17. OSC 777 later — out of scope; entry point named in the Design and §4.52. Requirements: no false alarms (Task 13 `false`=0, Review Focus 1), no flicker (`flips`=0, Review Focus 5), hooks first (Task 8 table, Task 13 `screen`=0 in `hooks` mode), one alert per question (Task 9 alerted identity, Task 13 `dup`=0), measured with the count written down (Task 13 table into the commit and §4.52), pane closed (Review Focus 4).
- **Placeholders:** the only fill-ins are measured numbers the harness prints (Task 13 Step 3 message, §4.52 "Measured"), a project id read from `GET /api/v1/projects`, and a launch id read from `GET /sessions/<id>` in the real-app steps. Scenario regexes that may not match an agent's real wording fail loudly and print the screen (Task 2 Step 3), rather than guessing.
- **Type consistency:** `ScreenReading` values and `State()` (Task 8) are the ones `Classify`/`Debouncer` (Task 11), the observer (Task 12), the lifecycle (Task 9) and the harness (Task 13) use; `ports.TerminalActivity*` strings equal `vtwasm.AgentActivity.String()` for the three published states (Tasks 5, 7); `ports.ScreenEvent(r)` yields exactly `EventScreenWorking/Question/Waiting/Settled`; the wire names `activity`, `seq`, `atMs`, `tail`, `cursorLine`, `summary` match between `ProgramEventPayload` and `recordProgramEvent`.
- **Review focus:** each of the five failure modes names its tests, and each test is written out in its owning task (Tasks 3, 6, 9, 11, 12, 13).
