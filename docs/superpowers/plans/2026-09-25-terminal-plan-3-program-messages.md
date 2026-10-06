# Terminal Plan 3 — Messages from programs (title, notifications, size reports, caps) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **If the superpowers skills are unavailable in your environment, run the same process by hand:** for each task dispatch one fresh implementer subagent with only that task's text (plus Global Constraints), then one spec-compliance review subagent and one code-quality review subagent on that task's commit, fix what they find, and only then start the next task; after the last task run one whole-branch review subagent over `git diff origin/development...HEAD`.

**Goal:** Claude Code's live terminal title shows on its board card and in its pane header (spinner glyph stripped, even when the pane was never opened), a program's own notification (OSC 9 / 777 / 99) becomes a desktop toast when its pane is not on screen, the pty-host mirror answers XTWINOPS 14/16/18, mode 2048 and OSC 10/11 from the pane's real cell size and colours, the title stack is capped at 4,096, and OSC 22 changes the mouse pointer.

**Architecture:** `vt-core` parses and stores every program message in both of its dispatchers' vocabulary (`OscKind`), queues replies through the reply queue the Claude Code probes already use (`Parser::push_reply`, answered only by the mirror), and exposes title/pointer/notifications to both wasm builds. The pty-host (Operator code) strips the title, and pushes only changed titles and each notification to "watcher" connections; the daemon's runtime keeps one watch per live terminal in memory and fans events out on a new mux channel, `programs`; the renderer keeps a titles store (card + pane header) and turns notifications into toasts unless the terminal is on screen in a focused window. The pane sends its cell size (device pixels) and theme colours to the mirror through a new `appearance` terminal frame.

**Tech Stack:** Rust 1.96.0 (`vt-core`, `vt-wasm` + wasm-bindgen 0.2.127, `vt-host` C ABI), Go 1.25 (pty-host, daemon, wazero), TypeScript/React 19 + Vitest (package and renderer), Playwright benches.

**Spec:** `docs/terminal/2026-09-24-terminal-roadmap-design.md` "Plan 3 — Messages from programs" and "Rules every plan obeys"; survey `docs/terminal/2026-09-19-terminal-reference-survey.md` §1.15, §1.16, §2.14; `TERMINAL.md` (all of it, §2 export checklist, §3 product independence, §6 verify-and-ship); agent alerts `docs/superpowers/specs/2026-09-23-agent-alerts-design.md` (D2, §5.3, §5.5).

**Branch:** `terminal/plan-3-program-messages` from `origin/development` (written against `5185f35be`). Push it; never merge.

**Shared files other wave-2 plans may also touch (the reviewer merges):** `packages/terminal/crates/vt-core/src/parser.rs`, `parser/perform.rs`, `history.rs`, `lib.rs`; `packages/terminal/crates/vt-host/src/lib.rs`; `packages/terminal/crates/vt-wasm/src/lib.rs`; `packages/terminal/ts/core/src/terminal-core.ts`, `index-browser.ts`; `packages/terminal/ts/react/src/TerminalSurface.tsx`, `index.ts`; `packages/terminal/ts/renderer-dom/src/styles.css`, `styles.ts`, `styles-parity.test.ts`; `backend/internal/adapters/runtime/ptyhost/host.go`, `proto.go`, `runtime.go`, `vtwasm/assets/vt_host.wasm`; `backend/internal/terminal/manager.go`, `protocol.go`, `attachment.go`; `frontend/src/renderer/lib/terminal-mux.ts`, `hooks/useTerminalSession.ts`, `components/BlockTerminal.tsx`, `components/SessionsBoard.tsx`, `components/split/SplitPane.tsx`, `components/split/SplitWorkspace.tsx`, `routes/_shell.tsx`, `i18n/en.json`; `TERMINAL.md`, `packages/terminal/CHANGELOG.md`, the survey and the plain-language doc. The binary `vt_host.wasm` always conflicts between plans: resolve by rebuilding it from the merged Rust (`TERMINAL.md` §6), never by picking a side.

## Global Constraints

- **No code comments in new code** (user's global instruction, `TERMINAL.md` §3.3). Existing comments may be corrected, never added to.
- **Commits:** explicit paths only (`git add <path> …`); never `git add -A`, `git add .`, `git commit -a` or `git stash`. Never commit to `development` or `master`, never merge, never force-push. Every commit message ends with the trailer `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- **`packages/terminal` stays product-independent** (`TERMINAL.md` §3.1): no Operator concept, path or default under `crates/` or `ts/`. The title stripping, "only when not on screen", toast wording and on-screen rule are Operator decisions and live in `backend/` and `frontend/`.
- **No file under `packages/terminal` over 600 lines** (`npm run check:boundaries`, `scripts/check-boundaries.mjs:43`). New logic therefore lives in new files (`program.rs`, `parser/program.rs`, `vt-wasm/src/program.rs`, `vt-host/src/program.rs`, `program-messages.ts`, `use-program-messages.ts`).
- **Licences:** never copy Kitty (GPL-3.0) or Warp (AGPL-3.0) code — OSC 99 here is written from kitty's protocol description only. Ghostty (MIT) and Alacritty (Apache-2.0/MIT) are followed for **behaviour only** in this plan; no code is adapted, so no attribution file is added. Cite `file:line` or write "not known".
- **Frontend copy** goes in `frontend/src/renderer/i18n/en.json` and is read with `t()`.
- **A `vt-core` change rebuilds both wasm artifacts** (`npm run build:wasm -- --force` for the renderer; `cargo build --release -p vt-host --target wasm32-unknown-unknown` then copy to `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` and commit it) and runs the pty-host Go tests (`TERMINAL.md` §6).
- **Backend:** hexagonal boundaries (`AGENTS.md`); nothing derived is stored — the title lives in pty-host and daemon memory only, never SQLite. `npm run api` must show no drift (no DTO changes are planned).
- **Feel baselines:** `npm run bench:feel` is compared against pixels recorded **in this environment on the unmodified tree** (Task 0 Step 7); never commit re-recorded baselines. This plan changes no pixels (the new CSS resolves to `cursor: default` unless a program sets a shape).
- **Every listener, subscription, watcher and socket added has a teardown test** (wave-1 review found a leak the plan missed). The tests are named in each task.
- **If a tool is unavailable** (Playwright download blocked, Go missing), write `not run: <exact reason>` for that gate in the completion report; do not fake output.
- New `TERMINAL.md` entry for this plan: **§4.30** (4.27–4.29 exist; wave 2 uses 4.30–4.33).

## Review Focus

1. **A Claude session whose pane was never opened, and a daemon restart with live sessions.** The card must still show the title. The runtime opens its watch on `Create`, `Attach` and every successful `IsAlive` probe (the reaper probes every session every ~5 s), so after a restart titles return within one reaper tick. Pinned by `TestAWatchThatDropsIsRestartedByTheNextLiveProbe` and `TestTheProgramWatchDeliversStrippedTitlesAndNotifications` (Task 5).
2. **"Relaunch in a cleared session" / account switch (in-place respawn) and Restart terminal.** The old task title must not linger on the card. Pinned by `TestResetProgramTellsWatchersTheTitleIsGone` (Task 4, respawn path), `TestStoppingTheProgramWatchClosesItAndClearsTheTitle` (Task 5, Destroy path) and `a_process_boundary_clears_the_title_stack_and_pointer` (Task 1, the renderer core).
3. **A program that floods OSC 9 or pushes titles forever.** Memory stays bounded: 16 pending notifications per core, 4,096 stacked titles, 1,024-byte titles, and a watcher that stops reading is skipped instead of growing a queue. Pinned by `pending_notifications_are_capped_and_the_oldest_is_dropped`, `the_title_stack_stops_growing_at_its_cap_and_drops_the_oldest`, `a_title_is_capped_at_the_byte_limit_on_a_character_boundary` (Task 1).
4. **The pane on screen but the window not focused (user in another app).** A notification then toasts — the same rule agent alerts use (D2). Pinned by "ignores a program notification while its terminal is on screen in a focused window" (Task 7), which also checks the unfocused case.
5. **Malformed input:** invalid UTF-8 and control characters in a title, OSC 9 ConEmu sub-commands (progress `9;4`) that are not notifications, OSC 777 without `notify`, OSC 99 encoded parts, unknown OSC 22 names, `OSC 10;#ff0000` (a set, not a query). Each is ignored or cleaned, never shown raw. Pinned by the Task 1 tests of the same names and `setting_a_dynamic_colour_is_ignored`.

---

## Facts checked while writing this plan (2026-09-25, `origin/development` @ `5185f35be`)

- **The reply path.** Operator already answers Claude Code's probes from the pty-host mirror: `Parser::push_reply` (`crates/vt-core/src/parser.rs:353-360`, capped at `MAX_QUERY_REPLY_BYTES = 4096`, `:35`) queues only when `set_answers_queries(true)` (`:345`), which `vt_new` sets (`crates/vt-host/src/lib.rs:39`); `vt_take_query_replies` (`lib.rs:113`) → Go `Parser.TakeQueryReplies` (`backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go:150`) → `host.deliver` takes them under `h.mu` (`host.go:631`) and writes them to the pty after unlocking (`host.go:636`). The renderer core never answers. OSC 10/11, XTWINOPS and 2048 replies use exactly this path.
- **Both dispatchers:** `Parser::osc_dispatch` (`crates/vt-core/src/parser/perform.rs:89-99`) and `ScreenPerform::osc_dispatch` (`crates/vt-core/src/history.rs:152-158`) handle only OSC 8 today; `csi_dispatch` (`perform.rs:26-76`) has no `t`. OSC 133/7000 marks are decoded separately by `terminal_marks` and are untouched.
- **vte caps OSC at 1,024 raw bytes and 16 parameters:** `vte` is built with `default-features = false` (`packages/terminal/Cargo.toml:18`), so `osc_raw` is a fixed `ArrayVec` of `MAX_OSC_RAW = 1024` (`vte-0.15.0/src/lib.rs:46,55-64`); `MAX_OSC_PARAMS = 16` (`:45`).
- **Fixtures** (`packages/terminal/bench/agent-session/fixtures/*/recording`, counted with a Python regex over the raw bytes): `claude-long-50k` 1,047 `OSC 0` (all BEL-terminated), 0 OSC 1/2/9/10/11/22/99/777, 0 `CSI … t`; `claude-spinner-10s` 16 `OSC 0`; `claude-markdown-reply` 20 `OSC 0` and **one `CSI 16 t`** (Claude Code v2.1.280 asks for the cell size in pixels). Every title starts with `◐ `, `◑ ` or `✳ ` (`◒`/`◓` do not occur). `claude-long-50k` ends on `✳ Number list 1 to 3000`, `claude-markdown-reply` on `✳ Greeting helpers`, `claude-spinner-10s` on `◑ Multiplication verification session`. Stripped, `claude-long-50k` has two distinct titles (`Claude Code`, `Number list 1 to 3000`). Whether Claude Code emits OSC 9/777 under some notification setting: **not known** — no fixture contains one.
- **`HostCapabilities.notify?(title, body)`** is at `packages/terminal/ts/core/src/types.ts:263` and has no caller.
- **Agent alerts:** persisted notifications need a session and project (`backend/internal/domain/notification.go:146-148`) and a type allowed by a SQLite `CHECK` (`backend/internal/storage/sqlite/migrations/0117_notification_alerts.sql:8-9`); standalone shell terminals have neither session nor project (`backend/internal/service/shellterm/types.go:1-14`). The desktop half of agent alerts is `operatorBridge.notifications.show` (UNUserNotificationCenter on packaged macOS, `frontend/src-tauri`, spec §5.3) with the "on screen in a focused window" rule (`frontend/src/renderer/lib/notifications.ts:258-265`, `components/NotificationCenter.tsx:110-112`). An unknown `type` string toasts without a dock bounce (`frontend/src-tauri/src/notification_policy.rs:11-12,135-140`).
- **Where terminals are visible:** `SplitWorkspace.tsx:84-98` already derives the active tab of every pane (for `visibleTerminalKindBySession`); `ShellTerminalsView.tsx:37-45` shows one active standalone shell. A worker's runtime handle id is the session id (`session_manager/manager.go:692-693`, `agent_switching.go:487-489`); the renderer reads it as `session.terminalHandleId` (`TerminalPane.tsx:153`).
- **The daemon has no long-lived connection to a pty-host.** Probes and RPCs dial per call (`ptyhost/client.go:31-36`); health is kept in `Runtime` memory and pushed through `WatchTerminalHealth` (`ptyhost/health.go:9-61`) to `terminal/health.go`. Every new connection to a host is registered as a terminal client and gets an attach replay (`host.go:755-850`), so a watcher needs its own first frame to opt out.
- **Line counts near the 600 cap:** `vt-core/src/lib.rs` 572, `parser.rs` 524, `vt-host/src/lib.rs` 558, `vt-wasm/src/lib.rs` 561, `ts/core/src/terminal-core.ts` 564, `renderer-dom/src/styles.ts` 594, `dom-block-renderer.ts` 591.
- **Author's proof run:** every code block in Tasks 1-9 was built and tested in a scratch copy of `5185f35be` on macOS before this plan was written: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` (0 warnings), `cargo test` (all ok), both wasm builds, `go test ./...` (all ok), `go test -race` on `ptyhost` and `terminal`, `golangci-lint` 2.12.2 on the touched packages (`0 issues.`), `go generate ./internal/httpd/apispec/...` (no drift), package vitest (core 87, renderer-dom 915, react 127 tests), renderer vitest (168 files / 1,690 tests), `tsc --noEmit`, eslint (0 errors), `check:boundaries`. Benches were not run by the author.

## Design decisions (made for this plan, with evidence)

1. **Single source of truth is the pty-host mirror.** The card must work without a pane (user decision 1) and a notification must reach you when the pane is unloaded (the retained cache unloads panes after 30 min, `TERMINAL.md` §5). So the mirror parses, the daemon relays, and Operator ignores the renderer core's own `notify`/`onTitle` (a loaded pane would otherwise notify twice). The package still calls `notify` and `onTitle` for other hosts.
2. **A watcher connection, not polling.** The daemon opens one `MsgWatchReq` connection per live host (in memory, re-opened by the reaper's probes). Polling the 5 s status probe would delay titles by up to 5 s and adds to a probe that already renders a full replay (`TERMINAL.md` §5 "Every liveness probe renders a full attach replay").
3. **Strip and rate-limit in the pty-host.** `domain.TerminalDisplayTitle` runs where the title is born, and only a changed stripped title leaves the host: 1,047 raw titles on `claude-long-50k` become 3 events.
4. **Titles are pushed on a new mux channel `programs`, not stored or put on `/api/v1/events`.** That SSE stream is the CDC change log with resume ids (`backend/internal/cdc/event.go:1-11`); a title is not a durable fact. Subscribing sends a snapshot, so a renderer that connects late or reconnects is complete.
5. **Program notifications are desktop toasts through the agent-alerts toast path, decided in the renderer, not persisted notification rows.** Rows need a session and project and a type allowed by the table's `CHECK` (facts above), which standalone shells cannot give, and "ignored while on screen" (user decision 2) needs pane visibility that only the renderer knows. Consequence, stated in `TERMINAL.md` §5: no bell entry and no phone alert (ntfy) for program notifications. The on-screen rule is the agent-alerts one (visible pane in a visible, focused window).
6. **Pixel size and colours come from the pane (`appearance` frame), last writer wins.** The mirror has no geometry of its own. Cell size in device pixels (native terminals report backing pixels; Ghostty `cell_size_px`). Before any pane has sent an appearance, 14/16 t, 2048 and OSC 10/11 stay unanswered (Ghostty also answers 14/16/2048 only with a known size, `stream_terminal.zig:259-264,1435-1437`); 18 t is always answered.
7. **Pointer shape is applied with a CSS custom property** on the surface (`--terminal-pointer-shape`) and one token in the existing `.terminal-block, .terminal-alt-surface` rule, so no renderer-dom file grows and link hover (two-class selector) still shows the hand.

## File map

| File | Change | Responsibility |
|---|---|---|
| `packages/terminal/crates/vt-core/src/program.rs`, `program/pointer.rs` | create | `ProgramState`, `OscKind`, OSC 0/2/9/777/99/10/11/22 handling, stack, size reports, `TerminalCore` API |
| `packages/terminal/crates/vt-core/src/parser/program.rs` | create | Parser glue: OSC entry, XTWINOPS, mode 2048 reports |
| `packages/terminal/crates/vt-core/src/parser.rs`, `parser/perform.rs`, `parser/blocks.rs`, `history.rs`, `lib.rs` | modify | wiring, DECRQM 2048, resize report, boundary reset, history dispatcher in step |
| `packages/terminal/crates/vt-core/tests/program_messages.rs`, `program_replies.rs` | create | 30 + 13 tests incl. the `claude-long-50k` fixture |
| `packages/terminal/crates/vt-wasm/src/program.rs`, `lib.rs`, `tests/program_exports.rs` | create/modify | renderer wasm exports |
| `packages/terminal/ts/core/src/program-messages.ts` (+test), `terminal-core.ts`, `index-browser.ts` | create/modify | TS program messages, `notify` seam |
| `packages/terminal/ts/react/src/use-program-messages.ts`, `TerminalSurface.tsx` (+`TerminalSurface.program.test.tsx`), `index.ts` | create/modify | pointer shape, `onTitle`, cell size on `onGeometry` |
| `packages/terminal/ts/renderer-dom/src/styles.css`, `styles.ts`, `styles-parity.test.ts` | modify | `cursor: var(--terminal-pointer-shape, default)` |
| `packages/terminal/crates/vt-host/src/program.rs`, `lib.rs` | create/modify | mirror C ABI |
| `backend/internal/adapters/runtime/ptyhost/vtwasm/program.go` (+test), `assets/vt_host.wasm` | create/rebuild | Go wasm bindings |
| `backend/internal/domain/terminal_title.go` (+test) | create | display title rule |
| `backend/internal/adapters/runtime/ptyhost/program.go` (+test), `proto.go`, `host.go`, `respawn.go` | create/modify | watcher connections, appearance, 2048 on resize |
| `backend/internal/ports/terminal_program.go` | create | program events and appearance ports |
| `backend/internal/adapters/runtime/ptyhost/program_watch.go` (+test), `runtime.go`, `attach.go` | create/modify | daemon-side watches, titles, stream appearance |
| `backend/internal/terminal/programs.go` (+test), `protocol.go`, `manager.go`, `attachment.go` | create/modify | `programs` channel, `appearance` frame |
| `frontend/src/renderer/lib/terminal-mux.ts` (+`terminal-mux.programs.test.ts`) | modify | client side of both |
| `frontend/src/renderer/lib/terminal-titles.ts`, `on-screen-terminals.ts`, `program-feed.ts`, `terminal-appearance.ts` (+tests) | create | titles store, on-screen claims, feed + toasts, appearance math |
| `frontend/src/renderer/components/ProgramRuntime.tsx` (+test), `routes/_shell.tsx`, `test/shell-new-session-shortcut.test.tsx` | create/modify | always-mounted runtime |
| `frontend/src/renderer/components/split/SplitWorkspace.tsx`, `ShellTerminalsView.tsx` (+2 tests) | modify | claim on-screen terminals |
| `frontend/src/renderer/hooks/useTerminalSession.ts`, `components/BlockTerminal.tsx` (+tests) | modify | send appearance |
| `frontend/src/renderer/components/SessionsBoard.tsx`, `split/SplitPane.tsx` (+tests), `i18n/en.json` | modify | card and pane-header title |
| `TERMINAL.md`, `packages/terminal/CHANGELOG.md`, survey, plain-language doc | modify | docs (Task 11) |


---

### Task 0: Branch, toolchains, baselines

**Files:** none committed. A temporary feel-baseline recording is made and the committed baselines are restored in Step 7.

**Interfaces:** Produces the branch and the baseline numbers every later task and Task 10 compare against.

- [ ] **Step 1: Create the branch**

```bash
git fetch origin && git checkout -b terminal/plan-3-program-messages origin/development && git log -1 --oneline
```
Expected: the tip of `origin/development` (`5185f35be` when this plan was written; a later commit is fine). If a file this plan edits no longer contains a quoted "find" text at the stated line, locate it with `grep -n` and use that; record the drift in the completion report. If a quoted text is missing entirely because another plan merged first, stop and report rather than improvising.

- [ ] **Step 2: Read before coding**

Read `TERMINAL.md` end to end, `packages/terminal/CHANGELOG.md` "Unreleased", the roadmap section named in the header, survey §1.15, §1.16, §2.14, and `AGENTS.md`. Do not start Task 1 before this.

- [ ] **Step 3: Rust toolchain and wasm-bindgen**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && rustup show active-toolchain && rustc --version && rustup target list --installed
```
Expected: `1.96.0-…` active (from `rust-toolchain.toml`), `rustc 1.96.0 (…)`, `wasm32-unknown-unknown` listed. If the target is missing: `rustup target add wasm32-unknown-unknown --toolchain 1.96.0`.

```bash
wasm-bindgen --version || cargo install wasm-bindgen-cli --version 0.2.127 --locked; wasm-bindgen --version
```
Expected: `wasm-bindgen 0.2.127` exactly (`scripts/build-wasm.mjs` refuses any other).

- [ ] **Step 4: Node, Go, Playwright (with the workarounds that worked in wave 1)**

```bash
node --version && npm --version && (go version || echo "go missing")
```
Expected: Node 20+; `go version go1.25.x`. If Go is missing or its download is blocked, let the module proxy fetch the toolchain `backend/go.mod` names:
```bash
cd "$(git rev-parse --show-toplevel)/backend" && GOTOOLCHAIN=auto go version
```
and prefix every later `go …` command in this plan with `GOTOOLCHAIN=auto` in the same shell command. If that fails too, record `Go: not run — <exact error>`; the Go steps become not-run.

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm ci && npx playwright install chromium; echo "playwright exit $?"
```
If the Playwright CDN is blocked (HTTP 403) but a Chromium is preinstalled under `/opt/pw-browsers`, point the revision directories this Playwright version expects at it, **outside the repo**:
```bash
ls /opt/pw-browsers; node -e "const r=require('playwright-core/lib/server/registry/index');console.log(r.registry.findExecutable('chromium').executablePath())" 2>/dev/null
```
The second command prints the path Playwright wants (e.g. `/opt/pw-browsers/chromium-1223/chrome-linux/chrome`). If that path does not exist but another `chromium-*` (or `chromium_headless_shell-*`) directory does, create the expected directory as a symlink to the existing one, e.g. `ln -s /opt/pw-browsers/chromium-1208 /opt/pw-browsers/chromium-1223` (and the same for `chromium_headless_shell-*` if its path is the one printed), with `PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers` exported for every bench command. If no Chromium is available at all, record `Playwright: not run — <exact error>`; every bench step becomes not-run with that reason.

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npm ci
```
Expected: `added … packages`.

- [ ] **Step 5: Baseline gates on the unmodified tree**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo fmt --check && cargo clippy --all-targets -- -D warnings 2>&1 | grep -cE "^(warning|error)"; cargo test 2>&1 | grep -E "FAILED|panicked"; npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor completions react; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Test Files|Tests "); done && npm run check:boundaries
```
Expected: `0`, no `FAILED`/`panicked`, five passing suites (record the counts), `boundary check passed`, `no ownership timers found (5 files scanned)`.

```bash
cd "$(git rev-parse --show-toplevel)/backend" && go test ./... 2>&1 | grep -E "^(FAIL|ok)" | grep -c ok; go test ./... 2>&1 | grep -E "^--- FAIL|^FAIL" | head
cd "$(git rev-parse --show-toplevel)/frontend" && npx vitest run --config vite.renderer.config.ts 2>&1 | grep -E "Test Files|Tests "
```
Expected: record the counts. Any failure here is pre-existing (for example `TestProcessEnvironmentLetsOverridesWin`, `TERMINAL.md` §5) and must be named in the report, not fixed.

- [ ] **Step 6: Baseline host wasm hash**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo build --release -p vt-host --target wasm32-unknown-unknown && sha256sum target/wasm32-unknown-unknown/release/vt_host.wasm
```
Record it; Task 3 must produce a different hash.

- [ ] **Step 7: Record feel baselines for this environment, then restore the committed ones**

The committed `bench/agent-session/baselines/` match only the machine they were recorded on. Record this environment's pixels on the unmodified tree into `/tmp` and restore the committed files:

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:feel -- --record && rm -rf /tmp/plan3-feel-base && cp -R bench/agent-session/baselines /tmp/plan3-feel-base && git checkout -- bench/agent-session/baselines && git clean -fd -- bench/agent-session/baselines >/dev/null; git status --short bench/agent-session/baselines
```
Expected: `recorded feel baselines`; the final `git status --short` prints nothing. If Playwright is unavailable, record `bench:feel: not run — <reason>`.

- [ ] **Step 8: No commit** — nothing to commit in Task 0.


---

### Task 1: vt-core — titles, title stack, notifications, pointer shape, size and colour replies

**Files:**
- Create: `packages/terminal/crates/vt-core/src/program.rs` (state + OSC classification + `TerminalCore` API), `packages/terminal/crates/vt-core/src/program/pointer.rs` (OSC 22 name table), `packages/terminal/crates/vt-core/src/parser/program.rs` (Parser glue: OSC, XTWINOPS, mode 2048)
- Modify: `packages/terminal/crates/vt-core/src/parser.rs:4,64,100,328,388,441`, `packages/terminal/crates/vt-core/src/parser/perform.rs:64,89-99`, `packages/terminal/crates/vt-core/src/parser/blocks.rs:40`, `packages/terminal/crates/vt-core/src/history.rs:153`, `packages/terminal/crates/vt-core/src/lib.rs:18`
- Test: `packages/terminal/crates/vt-core/tests/program_messages.rs`, `packages/terminal/crates/vt-core/tests/program_replies.rs`

**Interfaces:**
- Consumes: nothing new. Uses the existing reply queue `Parser::push_reply` (`parser.rs:353-360`, only fills when `set_answers_queries(true)`, i.e. the pty-host mirror) and `Parser::resize` (`parser.rs:424`).
- Produces (all on `vt_core::TerminalCore`): `title(&self) -> &str`, `pointer_shape(&self) -> &'static str` (a CSS cursor keyword or `""`), `program_generation(&self) -> u64` (bumps when the title or pointer changes or a notification is queued), `title_stack_depth(&self) -> usize`, `take_notifications(&mut self) -> Vec<vt_core::program::ProgramNotification>` (`{ title: String, body: String }`), `set_cell_pixels(&mut self, width: u32, height: u32)` (0 in either = unknown), `set_default_colors(&mut self, foreground: Option<u32>, background: Option<u32>)` (`0xRRGGBB`). Constants in `vt_core::program`: `MAX_TITLE_BYTES = 1024`, `TITLE_STACK_MAX_DEPTH = 4096`, `MAX_PENDING_NOTIFICATIONS = 16`, `MAX_NOTIFICATION_TITLE_BYTES = 1024`, `MAX_NOTIFICATION_BODY_BYTES = 2048`; `vt_core::program::{OscKind, pointer_shape_css}`.

Behaviour (decided; the tests pin every line):
- OSC 0 and OSC 2 set the title (params after the first are re-joined with `;`); OSC 1 (icon name) is ignored. Control characters are dropped, invalid UTF-8 becomes U+FFFD, the title is cut at 1,024 bytes on a character boundary (Ghostty's cap, `src/terminal/stream_terminal.zig:1467-1476`; vte itself stops an OSC at 1,024 raw bytes because `vte` is built without `std`, `Cargo.toml:18` + `vte-0.15.0/src/lib.rs:46`). An empty title clears it.
- `CSI 22 ; Ps t` pushes the current title and `CSI 23 ; Ps t` pops it for `Ps` absent, 0 or 2 (1 = icon only, ignored). At 4,096 entries a push drops the oldest (Alacritty `alacritty_terminal/src/term/mod.rs:42,2235-2248`, behaviour only). A pop on an empty stack changes nothing.
- OSC 9 is a notification with an empty title and the rest as body, **except** ConEmu commands: a first field of 1-12 digits-only (`9;4;…` progress, `9;1;…` sleep, …) is ignored (Ghostty `src/terminal/osc/parsers/osc9.zig:6-60`). OSC 777 `notify;title;body` (Ghostty `rxvt_extension.zig`). OSC 99 (kitty, behaviour from kitty's protocol doc only — GPL code is never read or copied): metadata `i` id, `d=0` more parts coming, `p=title|body`; `e=1` (base64) and any other `p` are ignored; a new id drops an unfinished one. An empty title and body raises nothing. At most 16 pending notifications; the oldest is dropped.
- OSC 22 records a pointer shape: a CSS cursor keyword or an xterm/X11 name mapped to one (the table follows Ghostty `src/terminal/mouse.zig:100-150`, behaviour only; names are the W3C `cursor` keywords and X11 cursor-font names); unknown names are ignored, an empty OSC 22 resets to the default.
- OSC 10/11 `?` queries are answered only by a core that answers queries (the mirror) and only once a colour is set: `OSC 10;rgb:rrrr/gggg/bbbb` with each 8-bit channel doubled, terminated like the query (BEL or ST) — Ghostty's reply form (`stream_terminal.zig:2881-2887` tests). `OSC 10;?;?` answers 10 then 11. Setting a colour is ignored.
- `CSI 18 t` → `CSI 8 ; rows ; cols t`; `CSI 14 t` → `CSI 4 ; rows*cellH ; cols*cellW t`; `CSI 16 t` → `CSI 6 ; cellH ; cellW t`; 14/16 only when the cell size is known; mode 2048 (`CSI ? 2048 h`) reports `CSI 48 ; rows ; cols ; rows*cellH ; cols*cellW t` at once when enabled, on every `resize`, and when the cell size changes — and only with a known cell size (Ghostty `src/terminal/size_report.zig:5-80`, `stream_terminal.zig:256-280,1456-1464,1602-1605`). DECRQM reports 2048.
- A process boundary (`OSC 7000;v=1;boundary=…`) clears the title, the stack, the pointer shape and mode 2048.
- The history receiver (`history.rs`, bytes inside an attach history chunk) classifies with the same `OscKind` and handles only hyperlinks: past output never changes the live title, raises a notification or sends a reply.

- [ ] **Step 1: Write the failing tests**

Create `packages/terminal/crates/vt-core/tests/program_messages.rs` with exactly this content:

```rust
use vt_core::program::{
    pointer_shape_css, ProgramNotification, MAX_PENDING_NOTIFICATIONS, MAX_TITLE_BYTES,
    TITLE_STACK_MAX_DEPTH,
};
use vt_core::TerminalCore;

fn core() -> TerminalCore {
    TerminalCore::new(80, 1_000).expect("core")
}

fn note(title: &str, body: &str) -> ProgramNotification {
    ProgramNotification {
        title: title.to_string(),
        body: body.to_string(),
    }
}

#[test]
fn osc_0_and_osc_2_set_the_title_and_the_latest_wins() {
    let mut core = core();
    assert_eq!(core.title(), "");
    core.feed(b"\x1b]0;first\x07");
    assert_eq!(core.title(), "first");
    core.feed(b"\x1b]2;second\x1b\\");
    assert_eq!(core.title(), "second");
}

#[test]
fn a_title_keeps_its_semicolons() {
    let mut core = core();
    core.feed(b"\x1b]2;a;b;c\x07");
    assert_eq!(core.title(), "a;b;c");
}

#[test]
fn an_empty_title_clears_it() {
    let mut core = core();
    core.feed(b"\x1b]2;busy\x07\x1b]2;\x07");
    assert_eq!(core.title(), "");
}

#[test]
fn osc_1_icon_name_leaves_the_title_alone() {
    let mut core = core();
    core.feed(b"\x1b]2;kept\x07\x1b]1;icon\x07");
    assert_eq!(core.title(), "kept");
}

#[test]
fn a_title_drops_control_characters_and_survives_invalid_utf8() {
    let mut core = core();
    core.feed(b"\x1b]2;a\x7fb\xffc\x07");
    assert_eq!(core.title(), "ab\u{fffd}c");
}

#[test]
fn a_title_is_capped_at_the_byte_limit_on_a_character_boundary() {
    let mut core = core();
    let mut sequence = b"\x1b]2;".to_vec();
    sequence.extend("é".repeat(MAX_TITLE_BYTES).as_bytes());
    sequence.push(0x07);
    core.feed(&sequence);
    assert!(core.title().len() <= MAX_TITLE_BYTES);
    assert!(core.title().chars().all(|ch| ch == 'é' || ch == '\u{fffd}'));
}

#[test]
fn a_title_split_across_feeds_lands_once_complete() {
    let mut core = core();
    core.feed(b"\x1b]0;half");
    assert_eq!(core.title(), "");
    core.feed(b" done\x07");
    assert_eq!(core.title(), "half done");
}

#[test]
fn the_program_generation_moves_only_when_something_changed() {
    let mut core = core();
    let start = core.program_generation();
    core.feed(b"\x1b]2;same\x07");
    let once = core.program_generation();
    assert_ne!(once, start);
    core.feed(b"\x1b]2;same\x07");
    assert_eq!(core.program_generation(), once);
    core.feed(b"plain text\r\n");
    assert_eq!(core.program_generation(), once);
}

#[test]
fn xtwinops_22_and_23_push_and_pop_the_title() {
    let mut core = core();
    core.feed(b"\x1b]2;outer\x07\x1b[22;0t\x1b]2;inner\x07");
    assert_eq!(core.title(), "inner");
    core.feed(b"\x1b[23;0t");
    assert_eq!(core.title(), "outer");
    core.feed(b"\x1b[22t\x1b]2;again\x07\x1b[23;2t");
    assert_eq!(core.title(), "outer");
}

#[test]
fn a_pop_on_an_empty_stack_changes_nothing() {
    let mut core = core();
    core.feed(b"\x1b]2;alone\x07\x1b[23;0t");
    assert_eq!(core.title(), "alone");
    assert_eq!(core.title_stack_depth(), 0);
}

#[test]
fn the_icon_only_push_is_ignored() {
    let mut core = core();
    core.feed(b"\x1b]2;title\x07\x1b[22;1t");
    assert_eq!(core.title_stack_depth(), 0);
}

#[test]
fn the_title_stack_stops_growing_at_its_cap_and_drops_the_oldest() {
    let mut core = core();
    core.feed(b"\x1b]2;oldest\x07\x1b[22;0t");
    for index in 0..TITLE_STACK_MAX_DEPTH + 10 {
        core.feed(format!("\x1b]2;t{index}\x07\x1b[22;0t").as_bytes());
    }
    assert_eq!(core.title_stack_depth(), TITLE_STACK_MAX_DEPTH);
    for _ in 0..TITLE_STACK_MAX_DEPTH {
        core.feed(b"\x1b[23;0t");
    }
    assert_eq!(core.title_stack_depth(), 0);
    assert_ne!(core.title(), "oldest");
    assert_eq!(core.title(), "t10");
}

#[test]
fn osc_9_raises_a_notification_with_its_text_as_the_body() {
    let mut core = core();
    core.feed(b"\x1b]9;build done\x07");
    assert_eq!(core.take_notifications(), vec![note("", "build done")]);
    assert!(core.take_notifications().is_empty());
}

#[test]
fn osc_9_keeps_semicolons_in_the_body() {
    let mut core = core();
    core.feed(b"\x1b]9;a;b\x1b\\");
    assert_eq!(core.take_notifications(), vec![note("", "a;b")]);
}

#[test]
fn osc_9_conemu_commands_are_not_notifications() {
    let mut core = core();
    core.feed(b"\x1b]9;4;1;50\x07\x1b]9;1;100\x07\x1b]9;12\x07\x1b]9;9;/tmp\x07");
    assert!(core.take_notifications().is_empty());
    core.feed(b"\x1b]9;13 is a message\x07");
    assert_eq!(core.take_notifications(), vec![note("", "13 is a message")]);
}

#[test]
fn an_empty_osc_9_raises_nothing() {
    let mut core = core();
    core.feed(b"\x1b]9;\x07\x1b]9\x07");
    assert!(core.take_notifications().is_empty());
}

#[test]
fn osc_777_notify_carries_a_title_and_a_body() {
    let mut core = core();
    core.feed(b"\x1b]777;notify;Build;finished;ok\x07");
    assert_eq!(
        core.take_notifications(),
        vec![note("Build", "finished;ok")]
    );
}

#[test]
fn osc_777_without_notify_or_a_title_is_ignored() {
    let mut core = core();
    core.feed(b"\x1b]777;preexec\x07\x1b]777;notify\x07\x1b]777;other;a;b\x07");
    assert!(core.take_notifications().is_empty());
}

#[test]
fn osc_99_single_part_is_a_title() {
    let mut core = core();
    core.feed(b"\x1b]99;;Hello\x1b\\");
    assert_eq!(core.take_notifications(), vec![note("Hello", "")]);
}

#[test]
fn osc_99_collects_title_and_body_across_parts_of_one_id() {
    let mut core = core();
    core.feed(b"\x1b]99;i=1:d=0;Title\x1b\\");
    assert!(core.take_notifications().is_empty());
    core.feed(b"\x1b]99;i=1:d=0:p=body;Body \x1b\\");
    core.feed(b"\x1b]99;i=1:p=body;text\x1b\\");
    assert_eq!(core.take_notifications(), vec![note("Title", "Body text")]);
}

#[test]
fn osc_99_a_new_id_drops_the_unfinished_one() {
    let mut core = core();
    core.feed(b"\x1b]99;i=1:d=0;Lost\x1b\\\x1b]99;i=2;Kept\x1b\\");
    assert_eq!(core.take_notifications(), vec![note("Kept", "")]);
}

#[test]
fn osc_99_encoded_and_unknown_payload_types_are_ignored() {
    let mut core = core();
    core.feed(b"\x1b]99;e=1;SGVsbG8=\x1b\\\x1b]99;p=icon;x\x1b\\\x1b]99;p=?;\x1b\\");
    assert!(core.take_notifications().is_empty());
}

#[test]
fn pending_notifications_are_capped_and_the_oldest_is_dropped() {
    let mut core = core();
    for index in 0..MAX_PENDING_NOTIFICATIONS + 3 {
        core.feed(format!("\x1b]9;n{index}\x07").as_bytes());
    }
    let taken = core.take_notifications();
    assert_eq!(taken.len(), MAX_PENDING_NOTIFICATIONS);
    assert_eq!(taken[0], note("", "n3"));
}

#[test]
fn osc_22_records_a_css_pointer_shape() {
    let mut core = core();
    core.feed(b"\x1b]22;pointer\x07");
    assert_eq!(core.pointer_shape(), "pointer");
    core.feed(b"\x1b]22;xterm\x07");
    assert_eq!(core.pointer_shape(), "text");
}

#[test]
fn osc_22_ignores_an_unknown_shape_and_an_empty_one_resets() {
    let mut core = core();
    core.feed(b"\x1b]22;crosshair\x07\x1b]22;nonsense\x07");
    assert_eq!(core.pointer_shape(), "crosshair");
    core.feed(b"\x1b]22;\x07");
    assert_eq!(core.pointer_shape(), "");
}

#[test]
fn every_css_and_x11_pointer_name_maps_to_a_css_keyword() {
    assert_eq!(pointer_shape_css("left_ptr"), Some("default"));
    assert_eq!(pointer_shape_css("fleur"), Some("all-scroll"));
    assert_eq!(pointer_shape_css("zoom-out"), Some("zoom-out"));
    assert_eq!(pointer_shape_css("Pointer"), None);
}

#[test]
fn a_process_boundary_clears_the_title_stack_and_pointer() {
    let mut core = core();
    core.feed(b"\x1b]2;old\x07\x1b[22;0t\x1b]22;wait\x07");
    core.feed(b"\x1b]7000;v=1;boundary=0\x07");
    assert_eq!(core.title(), "");
    assert_eq!(core.title_stack_depth(), 0);
    assert_eq!(core.pointer_shape(), "");
}

#[test]
fn a_history_chunk_never_changes_the_title_or_raises_a_notification() {
    let mut core = core();
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\live\r\n");
    core.feed(b"\x1b]2;live title\x07");
    core.feed(b"\x1b]7000;v=1;history=998,2\x1b\\");
    core.feed(b"\x1b]2;old title\x07one\r\n\x1b]9;old\x07\x1b]22;wait\x07two\r\n");
    assert_eq!(core.first_stable_row(), 998);
    assert_eq!(core.title(), "live title");
    assert!(core.take_notifications().is_empty());
    assert_eq!(core.pointer_shape(), "");
}

#[test]
fn a_title_inside_a_sync_block_lands_when_the_block_flushes() {
    let mut core = core();
    core.feed_at(b"\x1b[?2026h\x1b]0;framed\x07", 0);
    assert_eq!(core.title(), "");
    core.feed_at(b"\x1b[?2026l", 1);
    assert_eq!(core.title(), "framed");
}

#[test]
fn the_claude_code_recording_ends_on_its_idle_title() {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../bench/agent-session/fixtures/claude-long-50k/recording"
    );
    let recording = std::fs::read(path).expect("recording");
    let mut core = TerminalCore::new(120, 10_000).expect("core");
    core.resize(120, 40);
    core.set_agent_tui_mode(true);
    let start = core.program_generation();
    core.feed(&recording);
    assert_eq!(core.title(), "\u{2733} Number list 1 to 3000");
    assert_eq!(core.program_generation().wrapping_sub(start), 1_047);
    assert!(core.take_notifications().is_empty());
}
```

Create `packages/terminal/crates/vt-core/tests/program_replies.rs` with exactly this content:

```rust
use vt_core::TerminalCore;

fn answering(columns: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::new(columns, 1_000).expect("core");
    core.resize(columns, rows);
    core.set_answers_queries(true);
    core.take_query_replies();
    core
}

#[test]
fn xtwinops_18_reports_the_grid_in_cells() {
    let mut core = answering(100, 30);
    core.feed(b"\x1b[18t");
    assert_eq!(core.take_query_replies(), b"\x1b[8;30;100t");
}

#[test]
fn xtwinops_14_and_16_report_pixels_once_the_cell_size_is_known() {
    let mut core = answering(100, 30);
    core.feed(b"\x1b[14t\x1b[16t");
    assert!(
        core.take_query_replies().is_empty(),
        "no cell size, no pixel answer"
    );
    core.set_cell_pixels(9, 18);
    core.feed(b"\x1b[14t\x1b[16t");
    assert_eq!(
        core.take_query_replies(),
        b"\x1b[4;540;900t\x1b[6;18;9t".as_slice()
    );
}

#[test]
fn a_zero_cell_size_forgets_the_pixels() {
    let mut core = answering(80, 24);
    core.set_cell_pixels(8, 16);
    core.set_cell_pixels(0, 16);
    core.feed(b"\x1b[16t");
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn unknown_xtwinops_are_not_answered() {
    let mut core = answering(80, 24);
    core.set_cell_pixels(8, 16);
    core.feed(b"\x1b[11t\x1b[13t\x1b[19t\x1b[21t\x1b[t");
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn a_core_that_does_not_answer_queries_sends_no_size_report() {
    let mut core = TerminalCore::new(80, 1_000).expect("core");
    core.set_cell_pixels(8, 16);
    core.feed(b"\x1b[18t\x1b[16t\x1b[?2048h\x1b]10;?\x07");
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn mode_2048_reports_at_once_when_enabled_and_on_every_resize() {
    let mut core = answering(80, 24);
    core.set_cell_pixels(8, 16);
    core.feed(b"\x1b[?2048h");
    assert_eq!(core.take_query_replies(), b"\x1b[48;24;80;384;640t");
    core.resize(100, 30);
    assert_eq!(core.take_query_replies(), b"\x1b[48;30;100;480;800t");
    core.set_cell_pixels(10, 20);
    assert_eq!(core.take_query_replies(), b"\x1b[48;30;100;600;1000t");
    core.set_cell_pixels(10, 20);
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn mode_2048_stays_quiet_once_reset_and_without_a_cell_size() {
    let mut core = answering(80, 24);
    core.feed(b"\x1b[?2048h");
    assert!(core.take_query_replies().is_empty());
    core.feed(b"\x1b[?2048l");
    core.set_cell_pixels(8, 16);
    core.resize(90, 20);
    assert!(core.take_query_replies().is_empty());
}

#[test]
fn decrqm_reports_mode_2048() {
    let mut core = answering(80, 24);
    core.feed(b"\x1b[?2048$p");
    assert_eq!(core.take_query_replies(), b"\x1b[?2048;2$y");
    core.feed(b"\x1b[?2048h\x1b[?2048$p");
    assert_eq!(core.take_query_replies(), b"\x1b[?2048;1$y");
}

#[test]
fn osc_10_and_11_queries_answer_from_the_default_colours() {
    let mut core = answering(80, 24);
    core.feed(b"\x1b]10;?\x07\x1b]11;?\x1b\\");
    assert!(core.take_query_replies().is_empty(), "no theme, no answer");
    core.set_default_colors(Some(0xd8dee9), Some(0x0a0b0d));
    core.feed(b"\x1b]10;?\x07");
    assert_eq!(core.take_query_replies(), b"\x1b]10;rgb:d8d8/dede/e9e9\x07");
    core.feed(b"\x1b]11;?\x1b\\");
    assert_eq!(
        core.take_query_replies(),
        b"\x1b]11;rgb:0a0a/0b0b/0d0d\x1b\\"
    );
}

#[test]
fn one_osc_10_can_ask_for_foreground_and_background() {
    let mut core = answering(80, 24);
    core.set_default_colors(Some(0xffffff), Some(0x000000));
    core.feed(b"\x1b]10;?;?\x07");
    assert_eq!(
        core.take_query_replies(),
        b"\x1b]10;rgb:ffff/ffff/ffff\x07\x1b]11;rgb:0000/0000/0000\x07".as_slice()
    );
}

#[test]
fn setting_a_dynamic_colour_is_ignored() {
    let mut core = answering(80, 24);
    core.set_default_colors(Some(0xffffff), Some(0x000000));
    core.feed(b"\x1b]10;#ff0000\x07\x1b]11;rgb:00/00/ff\x07\x1b]10;?\x07");
    assert_eq!(core.take_query_replies(), b"\x1b]10;rgb:ffff/ffff/ffff\x07");
}

#[test]
fn a_cleared_colour_is_no_longer_answered() {
    let mut core = answering(80, 24);
    core.set_default_colors(Some(0xffffff), Some(0x000000));
    core.set_default_colors(None, Some(0x000000));
    core.feed(b"\x1b]10;?\x07\x1b]11;?\x07");
    assert_eq!(core.take_query_replies(), b"\x1b]11;rgb:0000/0000/0000\x07");
}

#[test]
fn the_claude_code_cell_size_probe_is_answered() {
    let mut core = answering(120, 40);
    core.set_cell_pixels(8, 17);
    core.feed(b"\x1b[16t");
    assert_eq!(core.take_query_replies(), b"\x1b[6;17;8t");
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo test -p vt-core --test program_messages --test program_replies 2>&1 | tail -5
```
Expected: compile errors such as `unresolved import vt_core::program` and `no method named title found for struct TerminalCore`.

- [ ] **Step 3: Implement**

Create `packages/terminal/crates/vt-core/src/program.rs` with exactly this content:

```rust
use std::collections::VecDeque;

mod pointer;

pub use pointer::pointer_shape_css;

pub const MAX_TITLE_BYTES: usize = 1024;
pub const TITLE_STACK_MAX_DEPTH: usize = 4096;
pub const MAX_PENDING_NOTIFICATIONS: usize = 16;
pub const MAX_NOTIFICATION_TITLE_BYTES: usize = 1024;
pub const MAX_NOTIFICATION_BODY_BYTES: usize = 2048;
const CONEMU_MAX_COMMAND: u8 = 12;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProgramNotification {
    pub title: String,
    pub body: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OscKind {
    Hyperlink,
    Title,
    IconName,
    Notification,
    RxvtExtension,
    KittyNotification,
    DynamicColor,
    PointerShape,
    Other,
}

impl OscKind {
    pub fn of(params: &[&[u8]]) -> Self {
        match params.first().copied() {
            Some(b"8") => Self::Hyperlink,
            Some(b"0") | Some(b"2") => Self::Title,
            Some(b"1") => Self::IconName,
            Some(b"9") => Self::Notification,
            Some(b"777") => Self::RxvtExtension,
            Some(b"99") => Self::KittyNotification,
            Some(b"10") | Some(b"11") => Self::DynamicColor,
            Some(b"22") => Self::PointerShape,
            _ => Self::Other,
        }
    }
}

#[derive(Debug, Default)]
struct KittyPending {
    id: String,
    title: String,
    body: String,
}

#[derive(Debug, Default)]
pub struct ProgramState {
    title: String,
    title_stack: VecDeque<String>,
    pointer_shape: &'static str,
    notifications: VecDeque<ProgramNotification>,
    kitty: Option<KittyPending>,
    generation: u64,
    cell_pixels: Option<(u32, u32)>,
    foreground: Option<u32>,
    background: Option<u32>,
    in_band_resize: bool,
}

impl ProgramState {
    pub fn title(&self) -> &str {
        &self.title
    }

    pub fn pointer_shape(&self) -> &'static str {
        self.pointer_shape
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    pub fn title_stack_depth(&self) -> usize {
        self.title_stack.len()
    }

    pub fn in_band_resize(&self) -> bool {
        self.in_band_resize
    }

    pub fn take_notifications(&mut self) -> Vec<ProgramNotification> {
        self.notifications.drain(..).collect()
    }

    pub fn osc(&mut self, params: &[&[u8]], bell_terminated: bool) -> Option<Vec<u8>> {
        match OscKind::of(params) {
            OscKind::Title => {
                self.set_title(joined(&params[1..]));
                None
            }
            OscKind::Notification => {
                self.osc9(&params[1..]);
                None
            }
            OscKind::RxvtExtension => {
                self.osc777(&params[1..]);
                None
            }
            OscKind::KittyNotification => {
                self.osc99(&params[1..]);
                None
            }
            OscKind::PointerShape => {
                self.osc22(&params[1..]);
                None
            }
            OscKind::DynamicColor => self.color_reply(params, bell_terminated),
            OscKind::Hyperlink | OscKind::IconName | OscKind::Other => None,
        }
    }

    pub fn set_title(&mut self, raw: Vec<u8>) {
        let title = clean_text(&raw, MAX_TITLE_BYTES);
        if title != self.title {
            self.title = title;
            self.bump();
        }
    }

    pub fn push_title(&mut self) {
        if self.title_stack.len() >= TITLE_STACK_MAX_DEPTH {
            self.title_stack.pop_front();
        }
        self.title_stack.push_back(self.title.clone());
    }

    pub fn pop_title(&mut self) {
        if let Some(title) = self.title_stack.pop_back() {
            if title != self.title {
                self.title = title;
                self.bump();
            }
        }
    }

    pub fn reset_for_new_process(&mut self) {
        let changed = !self.title.is_empty() || !self.pointer_shape.is_empty();
        self.title.clear();
        self.title_stack.clear();
        self.pointer_shape = "";
        self.kitty = None;
        self.in_band_resize = false;
        if changed {
            self.bump();
        }
    }

    pub fn set_cell_pixels(&mut self, width: u32, height: u32) -> bool {
        let next = (width > 0 && height > 0).then_some((width, height));
        let changed = next != self.cell_pixels;
        self.cell_pixels = next;
        changed
    }

    pub fn set_default_colors(&mut self, foreground: Option<u32>, background: Option<u32>) {
        self.foreground = foreground.map(|rgb| rgb & 0x00ff_ffff);
        self.background = background.map(|rgb| rgb & 0x00ff_ffff);
    }

    pub fn set_in_band_resize(&mut self, on: bool) {
        self.in_band_resize = on;
    }

    pub fn size_report(&self, kind: u16, columns: usize, rows: usize) -> Option<Vec<u8>> {
        match kind {
            14 => {
                let (width, height) = self.cell_pixels?;
                Some(
                    format!(
                        "\x1b[4;{};{}t",
                        rows as u64 * u64::from(height),
                        columns as u64 * u64::from(width)
                    )
                    .into_bytes(),
                )
            }
            16 => {
                let (width, height) = self.cell_pixels?;
                Some(format!("\x1b[6;{height};{width}t").into_bytes())
            }
            18 => Some(format!("\x1b[8;{rows};{columns}t").into_bytes()),
            _ => None,
        }
    }

    pub fn in_band_report(&self, columns: usize, rows: usize) -> Option<Vec<u8>> {
        if !self.in_band_resize {
            return None;
        }
        let (width, height) = self.cell_pixels?;
        Some(
            format!(
                "\x1b[48;{rows};{columns};{};{}t",
                rows as u64 * u64::from(height),
                columns as u64 * u64::from(width)
            )
            .into_bytes(),
        )
    }

    fn bump(&mut self) {
        self.generation = self.generation.wrapping_add(1);
    }

    fn notify(&mut self, title: String, body: String) {
        if title.is_empty() && body.is_empty() {
            return;
        }
        if self.notifications.len() >= MAX_PENDING_NOTIFICATIONS {
            self.notifications.pop_front();
        }
        self.notifications
            .push_back(ProgramNotification { title, body });
        self.bump();
    }

    fn osc9(&mut self, payload: &[&[u8]]) {
        if payload
            .first()
            .is_some_and(|first| is_conemu_command(first))
        {
            return;
        }
        let body = clean_text(&joined(payload), MAX_NOTIFICATION_BODY_BYTES);
        self.notify(String::new(), body);
    }

    fn osc777(&mut self, payload: &[&[u8]]) {
        let [extension, title, body @ ..] = payload else {
            return;
        };
        if *extension != b"notify" {
            return;
        }
        let title = clean_text(title, MAX_NOTIFICATION_TITLE_BYTES);
        let body = clean_text(&joined(body), MAX_NOTIFICATION_BODY_BYTES);
        self.notify(title, body);
    }

    fn osc99(&mut self, payload: &[&[u8]]) {
        let Some((metadata, text)) = payload.split_first() else {
            return;
        };
        let mut id = String::new();
        let mut done = true;
        let mut into_body = false;
        for pair in metadata.split(|byte| *byte == b':') {
            let Some(equals) = pair.iter().position(|byte| *byte == b'=') else {
                continue;
            };
            let (key, value) = (&pair[..equals], &pair[equals + 1..]);
            match key {
                b"i" => id = clean_text(value, 256),
                b"d" => done = value != b"0",
                b"e" if value == b"1" => return,
                b"p" => match value {
                    b"title" => into_body = false,
                    b"body" => into_body = true,
                    _ => return,
                },
                _ => {}
            }
        }
        let pending = match self.kitty.take() {
            Some(pending) if pending.id == id => pending,
            _ => KittyPending {
                id,
                ..KittyPending::default()
            },
        };
        let mut pending = pending;
        let text = String::from_utf8_lossy(&joined(text)).into_owned();
        if into_body {
            append_capped(&mut pending.body, &text, MAX_NOTIFICATION_BODY_BYTES);
        } else {
            append_capped(&mut pending.title, &text, MAX_NOTIFICATION_TITLE_BYTES);
        }
        if done {
            let title = clean_text(pending.title.as_bytes(), MAX_NOTIFICATION_TITLE_BYTES);
            let body = clean_text(pending.body.as_bytes(), MAX_NOTIFICATION_BODY_BYTES);
            self.notify(title, body);
        } else {
            self.kitty = Some(pending);
        }
    }

    fn osc22(&mut self, payload: &[&[u8]]) {
        let name = joined(payload);
        let next = if name.is_empty() {
            ""
        } else {
            match std::str::from_utf8(&name).ok().and_then(pointer_shape_css) {
                Some(css) => css,
                None => return,
            }
        };
        if next != self.pointer_shape {
            self.pointer_shape = next;
            self.bump();
        }
    }

    fn color_reply(&self, params: &[&[u8]], bell_terminated: bool) -> Option<Vec<u8>> {
        let first: u16 = std::str::from_utf8(params.first()?).ok()?.parse().ok()?;
        let mut reply = Vec::new();
        for (index, param) in params[1..].iter().enumerate() {
            if *param != b"?" {
                continue;
            }
            let slot = first + index as u16;
            let rgb = match slot {
                10 => self.foreground,
                11 => self.background,
                _ => None,
            };
            let Some(rgb) = rgb else {
                continue;
            };
            let (r, g, b) = ((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff);
            reply.extend_from_slice(
                format!("\x1b]{slot};rgb:{r:02x}{r:02x}/{g:02x}{g:02x}/{b:02x}{b:02x}").as_bytes(),
            );
            reply.extend_from_slice(if bell_terminated { b"\x07" } else { b"\x1b\\" });
        }
        (!reply.is_empty()).then_some(reply)
    }
}

fn is_conemu_command(first: &[u8]) -> bool {
    !first.is_empty()
        && first.len() <= 2
        && first.iter().all(u8::is_ascii_digit)
        && std::str::from_utf8(first)
            .ok()
            .and_then(|digits| digits.parse::<u8>().ok())
            .is_some_and(|command| (1..=CONEMU_MAX_COMMAND).contains(&command))
}

fn joined(parts: &[&[u8]]) -> Vec<u8> {
    let mut out = Vec::new();
    for (index, part) in parts.iter().enumerate() {
        if index > 0 {
            out.push(b';');
        }
        out.extend_from_slice(part);
    }
    out
}

fn clean_text(raw: &[u8], cap: usize) -> String {
    let decoded = String::from_utf8_lossy(raw);
    let mut out = String::new();
    for ch in decoded.chars().filter(|ch| !ch.is_control()) {
        if out.len() + ch.len_utf8() > cap {
            break;
        }
        out.push(ch);
    }
    out
}

fn append_capped(target: &mut String, text: &str, cap: usize) {
    for ch in text.chars() {
        if target.len() + ch.len_utf8() > cap {
            return;
        }
        target.push(ch);
    }
}

impl crate::TerminalCore {
    pub fn title(&self) -> &str {
        self.parser.program().title()
    }

    pub fn pointer_shape(&self) -> &'static str {
        self.parser.program().pointer_shape()
    }

    pub fn program_generation(&self) -> u64 {
        self.parser.program().generation()
    }

    pub fn title_stack_depth(&self) -> usize {
        self.parser.program().title_stack_depth()
    }

    pub fn take_notifications(&mut self) -> Vec<ProgramNotification> {
        self.parser.program_mut().take_notifications()
    }

    pub fn set_cell_pixels(&mut self, width: u32, height: u32) {
        if self.parser.program_mut().set_cell_pixels(width, height) {
            self.parser.send_in_band_report();
        }
    }

    pub fn set_default_colors(&mut self, foreground: Option<u32>, background: Option<u32>) {
        self.parser
            .program_mut()
            .set_default_colors(foreground, background);
    }
}
```

Create `packages/terminal/crates/vt-core/src/program/pointer.rs` with exactly this content:

```rust
const CSS_SHAPES: [&str; 34] = [
    "default",
    "context-menu",
    "help",
    "pointer",
    "progress",
    "wait",
    "cell",
    "crosshair",
    "text",
    "vertical-text",
    "alias",
    "copy",
    "move",
    "no-drop",
    "not-allowed",
    "grab",
    "grabbing",
    "all-scroll",
    "col-resize",
    "row-resize",
    "n-resize",
    "e-resize",
    "s-resize",
    "w-resize",
    "ne-resize",
    "nw-resize",
    "se-resize",
    "sw-resize",
    "ew-resize",
    "ns-resize",
    "nesw-resize",
    "nwse-resize",
    "zoom-in",
    "zoom-out",
];

const X11_SHAPES: [(&str, &str); 22] = [
    ("left_ptr", "default"),
    ("question_arrow", "help"),
    ("hand", "pointer"),
    ("left_ptr_watch", "progress"),
    ("watch", "wait"),
    ("cross", "crosshair"),
    ("xterm", "text"),
    ("dnd-link", "alias"),
    ("dnd-copy", "copy"),
    ("dnd-move", "move"),
    ("dnd-no-drop", "no-drop"),
    ("crossed_circle", "not-allowed"),
    ("hand1", "grab"),
    ("right_side", "e-resize"),
    ("top_side", "n-resize"),
    ("top_right_corner", "ne-resize"),
    ("top_left_corner", "nw-resize"),
    ("bottom_side", "s-resize"),
    ("bottom_right_corner", "se-resize"),
    ("bottom_left_corner", "sw-resize"),
    ("left_side", "w-resize"),
    ("fleur", "all-scroll"),
];

pub fn pointer_shape_css(name: &str) -> Option<&'static str> {
    if let Some(css) = CSS_SHAPES.iter().find(|css| **css == name) {
        return Some(css);
    }
    X11_SHAPES
        .iter()
        .find(|(x11, _)| *x11 == name)
        .map(|(_, css)| *css)
}
```

Create `packages/terminal/crates/vt-core/src/parser/program.rs` with exactly this content:

```rust
use vte::Params;

use super::Parser;
use crate::program::ProgramState;

impl Parser {
    pub(crate) fn program(&self) -> &ProgramState {
        &self.program
    }

    pub(crate) fn program_mut(&mut self) -> &mut ProgramState {
        &mut self.program
    }

    pub(crate) fn program_osc(&mut self, params: &[&[u8]], bell_terminated: bool) {
        if let Some(reply) = self.program.osc(params, bell_terminated) {
            self.push_reply(&reply);
        }
    }

    pub(crate) fn xtwinops(&mut self, params: &Params) {
        let mut groups = params.iter();
        let kind = groups.next().and_then(|g| g.first().copied()).unwrap_or(0);
        let which = groups.next().and_then(|g| g.first().copied()).unwrap_or(0);
        match kind {
            22 if which != 1 => self.program.push_title(),
            23 if which != 1 => self.program.pop_title(),
            14 | 16 | 18 => {
                if let Some(reply) = self
                    .program
                    .size_report(kind, self.width, self.screen.rows())
                {
                    self.push_reply(&reply);
                }
            }
            _ => {}
        }
    }

    pub(crate) fn note_in_band_resize_mode(&mut self, set: bool) {
        self.program.set_in_band_resize(set);
        if set {
            self.send_in_band_report();
        }
    }

    pub(crate) fn send_in_band_report(&mut self) {
        if let Some(reply) = self.program.in_band_report(self.width, self.screen.rows()) {
            self.push_reply(&reply);
        }
    }
}
```

Edit 1 of 6 in `packages/terminal/crates/vt-core/src/parser.rs` — find this text (starts at line 2 of the unmodified file):

```rust
mod colour;
mod history;
mod perform;

pub(crate) use colour::read_extended_colour;

```

replace it with:

```rust
mod colour;
mod history;
mod perform;
mod program;

pub(crate) use colour::read_extended_colour;

```

Edit 2 of 6 in `packages/terminal/crates/vt-core/src/parser.rs` — find this text (starts at line 62 of the unmodified file):

```rust
    last_width: usize,
    width_mode: WidthMode,
    hyperlinks: HyperlinkRegistry,
    #[cfg(feature = "trace")]
    pub(crate) trace: crate::trace::Trace,
}
```

replace it with:

```rust
    last_width: usize,
    width_mode: WidthMode,
    hyperlinks: HyperlinkRegistry,
    program: crate::program::ProgramState,
    #[cfg(feature = "trace")]
    pub(crate) trace: crate::trace::Trace,
}
```

Edit 3 of 6 in `packages/terminal/crates/vt-core/src/parser.rs` — find this text (starts at line 98 of the unmodified file):

```rust
            last_width: width,
            width_mode: WidthMode::default(),
            hyperlinks: HyperlinkRegistry::default(),
            #[cfg(feature = "trace")]
            trace: Default::default(),
        }
```

replace it with:

```rust
            last_width: width,
            width_mode: WidthMode::default(),
            hyperlinks: HyperlinkRegistry::default(),
            program: crate::program::ProgramState::default(),
            #[cfg(feature = "trace")]
            trace: Default::default(),
        }
```

Edit 4 of 6 in `packages/terminal/crates/vt-core/src/parser.rs` — find this text (starts at line 326 of the unmodified file):

```rust
                self.focus_reporting = set;
                return;
            }
            1000 => 0b001,
            1002 => 0b010,
            1003 => 0b100,
```

replace it with:

```rust
                self.focus_reporting = set;
                return;
            }
            2048 => {
                self.note_in_band_resize_mode(set);
                return;
            }
            1000 => 0b001,
            1002 => 0b010,
            1003 => 0b100,
```

Edit 5 of 6 in `packages/terminal/crates/vt-core/src/parser.rs` — find this text (starts at line 386 of the unmodified file):

```rust
            1049 => self.alt.is_some(),
            2004 => self.bracketed_paste,
            2026 => false,
            _ => return 0,
        };
        if set {
```

replace it with:

```rust
            1049 => self.alt.is_some(),
            2004 => self.bracketed_paste,
            2026 => false,
            2048 => self.program.in_band_resize(),
            _ => return 0,
        };
        if set {
```

Edit 6 of 6 in `packages/terminal/crates/vt-core/src/parser.rs` — find this text (starts at line 439 of the unmodified file):

```rust
        }
        self.grid
            .clamp_to_rows(self.rows.completed().len() + self.screen.rows());
    }

    pub(crate) fn commit_evicted(&mut self) {
```

replace it with:

```rust
        }
        self.grid
            .clamp_to_rows(self.rows.completed().len() + self.screen.rows());
        self.send_in_band_report();
    }

    pub(crate) fn commit_evicted(&mut self) {
```

Edit 1 of 2 in `packages/terminal/crates/vt-core/src/parser/perform.rs` — find this text (starts at line 62 of the unmodified file):

```rust
            self.answer_xtversion();
            return;
        }
        if intermediates.first() == Some(&b'?') && matches!(c, 'h' | 'l') {
            let set = c == 'h';
            for group in params.iter() {
```

replace it with:

```rust
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
```

Edit 2 of 2 in `packages/terminal/crates/vt-core/src/parser/perform.rs` — find this text (starts at line 86 of the unmodified file):

```rust
        self.active_screen_mut().esc(byte);
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], _bell_terminated: bool) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Osc(
            params.iter().map(|p| p.to_vec()).collect(),
        ));
        if params.first().copied() == Some(b"8".as_slice()) {
            let id = crate::hyperlink::parse_osc8(&params[1..])
                .and_then(|link| self.hyperlinks.intern(link));
            self.pending_style.link = id.unwrap_or(0);
        }
    }
}
```

replace it with:

```rust
        self.active_screen_mut().esc(byte);
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], bell_terminated: bool) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Osc(
            params.iter().map(|p| p.to_vec()).collect(),
        ));
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

Edit 1 of 1 in `packages/terminal/crates/vt-core/src/parser/blocks.rs` — find this text (starts at line 38 of the unmodified file):

```rust
        self.grid.sync_next_row(self.rows.completed().len());
        self.pending_style = CellStyle::DEFAULT;
        self.sync_erase_background();
    }

    fn materialize_uncovered_rows(
```

replace it with:

```rust
        self.grid.sync_next_row(self.rows.completed().len());
        self.pending_style = CellStyle::DEFAULT;
        self.sync_erase_background();
        self.program.reset_for_new_process();
    }

    fn materialize_uncovered_rows(
```

Edit 1 of 1 in `packages/terminal/crates/vt-core/src/history.rs` — find this text (starts at line 150 of the unmodified file):

```rust
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], _bell_terminated: bool) {
        if params.first().copied() == Some(b"8".as_slice()) {
            let id =
                crate::hyperlink::parse_osc8(&params[1..]).and_then(|link| self.links.intern(link));
            self.style.link = id.unwrap_or(0);
```

replace it with:

```rust
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], _bell_terminated: bool) {
        if crate::program::OscKind::of(params) == crate::program::OscKind::Hyperlink {
            let id =
                crate::hyperlink::parse_osc8(&params[1..]).and_then(|link| self.links.intern(link));
            self.style.link = id.unwrap_or(0);
```

Edit 1 of 1 in `packages/terminal/crates/vt-core/src/lib.rs` — find this text (starts at line 16 of the unmodified file):

```rust
pub mod limits;
mod line_editor;
pub mod parser;
pub mod row_index;
mod screen;
mod scrollback;
```

replace it with:

```rust
pub mod limits;
mod line_editor;
pub mod parser;
pub mod program;
pub mod row_index;
mod screen;
mod scrollback;
```

- [ ] **Step 4: Run the new tests**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo test -p vt-core --test program_messages --test program_replies 2>&1 | grep -E "^test result"
```
Expected: `test result: ok. 30 passed` and `test result: ok. 13 passed`.

- [ ] **Step 5: Whole crate, fmt, clippy, line cap**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo fmt && cargo clippy --all-targets -- -D warnings 2>&1 | grep -cE "^(warning|error)" ; cargo test -p vt-core 2>&1 | grep -E "FAILED|panicked" ; wc -l crates/vt-core/src/parser.rs crates/vt-core/src/lib.rs crates/vt-core/src/program.rs && npm run check:boundaries
```
Expected: `0` from the clippy count, no `FAILED`/`panicked` lines, every file under 600 lines (`parser.rs` 533, `lib.rs` 573, `program.rs` 413), `boundary check passed`. If `cargo fmt` reflows a file differently from this plan, keep fmt's version.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/crates/vt-core/tests/program_messages.rs \
  packages/terminal/crates/vt-core/tests/program_replies.rs \
  packages/terminal/crates/vt-core/src/program.rs \
  packages/terminal/crates/vt-core/src/program/pointer.rs \
  packages/terminal/crates/vt-core/src/parser/program.rs \
  packages/terminal/crates/vt-core/src/parser.rs \
  packages/terminal/crates/vt-core/src/parser/perform.rs \
  packages/terminal/crates/vt-core/src/parser/blocks.rs \
  packages/terminal/crates/vt-core/src/history.rs \
  packages/terminal/crates/vt-core/src/lib.rs
git commit -m "feat(vt-core): titles, title stack, program notifications, pointer shape, size and colour replies" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
Expected: the commit succeeds; `git status --short` lists nothing this task touched (feel baselines, `ts/core/wasm` and `dist` are ignored or restored). Never `git add -A`, `git commit -a` or `git stash`.

---

### Task 2: vt-wasm exports, `TerminalCore` program messages, pointer shape and cell size in the React surface

**Files:**
- Create: `packages/terminal/crates/vt-wasm/src/program.rs`, `packages/terminal/ts/core/src/program-messages.ts`, `packages/terminal/ts/react/src/use-program-messages.ts`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs:1,7`, `packages/terminal/ts/core/src/terminal-core.ts:13,77,80,119,179,473,523`, `packages/terminal/ts/core/src/index-browser.ts:73`, `packages/terminal/ts/react/src/TerminalSurface.tsx:30,43,87,109,289,371`, `packages/terminal/ts/react/src/index.ts:1`, `packages/terminal/ts/renderer-dom/src/styles.css:204`, `packages/terminal/ts/renderer-dom/src/styles.ts:204`, `packages/terminal/ts/renderer-dom/src/styles-parity.test.ts:112`
- Test: `packages/terminal/crates/vt-wasm/tests/program_exports.rs`, `packages/terminal/ts/core/src/program-messages.test.ts`, `packages/terminal/ts/react/src/TerminalSurface.program.test.tsx`

**Interfaces:**
- Consumes: Task 1's `TerminalCore::{program_generation, title, pointer_shape, take_notifications}`.
- Produces: wasm methods `program_generation(): number`, `title(): string`, `pointer_shape(): string`, `take_notifications(): string[]` (flat `[title0, body0, title1, body1, …]`); Rust `vt_wasm::flatten_notifications`. TS: `TerminalCore.title(): string`, `TerminalCore.pointerShape(): string`, `TerminalCore.onProgramMessage(listener: ProgramMessageListener): () => void`; exported `ProgramMessages`, `ProgramMessageEvent` (`{kind:"title",title}` | `{kind:"pointer",shape}` | `{kind:"notification",notification:{title,body}}`), `ProgramMessageListener`, `ProgramMessageSource`, `ProgramNotification`. The core calls the existing `HostCapabilities.notify?(title, body)` (`ts/core/src/types.ts:263`, which had no caller) for every notification it parses. React: `TerminalSurfaceProps.onTitle?: (title: string) => void`; `onGeometry?: (columns, rows, cell?: CellSize) => void` where `CellSize = Readonly<{ width: number; height: number }>` in CSS pixels (existing two-argument callers keep working); exported `POINTER_SHAPE_PROPERTY = "--terminal-pointer-shape"`, set on the `.terminal-surface` element while a program asks for a shape. CSS: `.terminal-block, .terminal-alt-surface { cursor: var(--terminal-pointer-shape, default) }` — a link hover (`.terminal-link-hover …`, two classes) still wins. No pixel changes: the default is still the arrow.
- Operator does **not** pass `notify` to its core and does not use `onTitle` (the daemon's mirror is the single source of both, Tasks 4-9); both are for other hosts of the package.

- [ ] **Step 1: Write the failing tests**

Create `packages/terminal/crates/vt-wasm/tests/program_exports.rs` with exactly this content:

```rust
use vt_core::program::ProgramNotification;
use vt_wasm::flatten_notifications;
use vt_wasm::WasmTerminalCore;

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
```

Create `packages/terminal/ts/core/src/program-messages.test.ts` with exactly this content:

```ts
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore, initTerminalCore, ProgramMessages, type HostCapabilities, type ProgramMessageEvent } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

const encode = (text: string) => new TextEncoder().encode(text);

function hostWith(notify?: HostCapabilities["notify"]): HostCapabilities {
	return {
		writeClipboard: async () => undefined,
		readClipboard: async () => "",
		openLink: async () => undefined,
		...(notify ? { notify } : {}),
	};
}

describe("ProgramMessages", () => {
	it("reads nothing while the generation is unchanged", () => {
		const source = {
			program_generation: vi.fn(() => 0),
			title: vi.fn(() => ""),
			pointer_shape: vi.fn(() => ""),
			take_notifications: vi.fn(() => [] as string[]),
		};
		const program = new ProgramMessages(source, hostWith());
		program.poll();
		expect(source.title).not.toHaveBeenCalled();
		expect(source.take_notifications).not.toHaveBeenCalled();
	});

	it("emits a title, a pointer shape and each notification once", () => {
		let generation = 0;
		let notifications: string[] = [];
		const source = {
			program_generation: () => generation,
			title: () => "◐ Working",
			pointer_shape: () => "pointer",
			take_notifications: () => {
				const taken = notifications;
				notifications = [];
				return taken;
			},
		};
		const notify = vi.fn();
		const program = new ProgramMessages(source, hostWith(notify));
		const events: ProgramMessageEvent[] = [];
		program.onMessage((event) => events.push(event));
		generation = 1;
		notifications = ["Build", "done", "", "second"];
		program.poll();
		program.poll();
		expect(events).toEqual([
			{ kind: "title", title: "◐ Working" },
			{ kind: "pointer", shape: "pointer" },
			{ kind: "notification", notification: { title: "Build", body: "done" } },
			{ kind: "notification", notification: { title: "", body: "second" } },
		]);
		expect(notify.mock.calls).toEqual([
			["Build", "done"],
			["", "second"],
		]);
		expect(program.title()).toBe("◐ Working");
		expect(program.pointerShape()).toBe("pointer");
	});

	it("stops calling a listener once it unsubscribes or the messages are disposed", () => {
		let generation = 0;
		let title = "";
		const source = {
			program_generation: () => generation,
			title: () => title,
			pointer_shape: () => "",
			take_notifications: () => [] as string[],
		};
		const program = new ProgramMessages(source, hostWith());
		const kept = vi.fn();
		const dropped = vi.fn();
		program.onMessage(kept);
		const off = program.onMessage(dropped);
		off();
		generation = 1;
		title = "one";
		program.poll();
		expect(dropped).not.toHaveBeenCalled();
		expect(kept).toHaveBeenCalledTimes(1);
		program.dispose();
		generation = 2;
		title = "two";
		program.poll();
		expect(kept).toHaveBeenCalledTimes(1);
	});
});

describe("TerminalCore program messages", () => {
	it("follows OSC 0/2 titles and OSC 22 pointer shapes", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		const events: ProgramMessageEvent[] = [];
		const off = core.onProgramMessage((event) => events.push(event));
		core.feed(encode("\x1b]0;✳ Claude Code\x07\x1b]22;xterm\x07"));
		expect(core.title()).toBe("✳ Claude Code");
		expect(core.pointerShape()).toBe("text");
		expect(events).toEqual([
			{ kind: "title", title: "✳ Claude Code" },
			{ kind: "pointer", shape: "text" },
		]);
		off();
		core.dispose();
	});

	it("hands OSC 9, 777 and 99 notifications to the host notify seam", () => {
		const notify = vi.fn();
		const core = createTerminalCore({ columns: 40, scrollback: 100, host: hostWith(notify) });
		core.feed(encode("\x1b]9;hello\x07\x1b]777;notify;Build;done\x07\x1b]99;;Kitty\x1b\\"));
		expect(notify.mock.calls).toEqual([
			["", "hello"],
			["Build", "done"],
			["Kitty", ""],
		]);
		core.dispose();
	});

	it("sees a title that arrives inside a sync block when a tick flushes it", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		const titles: string[] = [];
		core.onProgramMessage((event) => {
			if (event.kind === "title") titles.push(event.title);
		});
		core.feed(encode("\x1b[?2026h\x1b]2;framed\x07"));
		expect(titles).toEqual([]);
		core.tick(Date.now() + 1_000);
		expect(titles).toEqual(["framed"]);
		core.dispose();
	});

	it("never answers a size or colour query from the renderer core", () => {
		const core = createTerminalCore({ columns: 40, scrollback: 100 });
		core.feed(encode("\x1b[18t\x1b]10;?\x07"));
		expect(core.title()).toBe("");
		core.dispose();
	});
});
```

Create `packages/terminal/ts/react/src/TerminalSurface.program.test.tsx` with exactly this content:

```tsx
import { cleanup, render, within } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "@operator/terminal-renderer-dom";
import { POINTER_SHAPE_PROPERTY, TerminalSurface } from "./index";
import { feed, font, ignoreRaw, ignoreSend, loadWasm, setHostSize, theme } from "./surface-harness";

beforeAll(loadWasm);
afterEach(cleanup);

function mount(onTitle?: (title: string) => void, onGeometry?: (columns: number, rows: number, cell?: { width: number; height: number }) => void) {
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	const result = render(
		<TerminalSurface
			core={core}
			theme={theme}
			font={font}
			altScreenActive={false}
			onSend={ignoreSend}
			onSendRaw={ignoreRaw}
			onTitle={onTitle}
			onGeometry={onGeometry}
		/>,
	);
	const host = within(result.container).getByTestId("terminal-block-list").parentElement as HTMLElement;
	const surface = host.parentElement as HTMLElement;
	return { core, host, surface, ...result };
}

describe("TerminalSurface program messages", () => {
	it("applies the program's pointer shape to the surface and clears it on reset", () => {
		const { core, surface } = mount();
		feed(core, "\x1b]22;pointer\x07");
		expect(surface.style.getPropertyValue(POINTER_SHAPE_PROPERTY)).toBe("pointer");
		feed(core, "\x1b]22;\x07");
		expect(surface.style.getPropertyValue(POINTER_SHAPE_PROPERTY)).toBe("");
	});

	it("tells the host each new title", () => {
		const onTitle = vi.fn();
		const { core } = mount(onTitle);
		feed(core, "\x1b]0;\u25d0 Working\x07");
		feed(core, "\x1b]0;\u25d0 Working\x07");
		feed(core, "\x1b]2;done\x07");
		expect(onTitle.mock.calls).toEqual([["\u25d0 Working"], ["done"]]);
	});

	it("stops listening to the core once unmounted", () => {
		const onTitle = vi.fn();
		const { core, surface, unmount } = mount(onTitle);
		feed(core, "\x1b]22;wait\x07");
		unmount();
		expect(surface.style.getPropertyValue(POINTER_SHAPE_PROPERTY)).toBe("");
		feed(core, "\x1b]2;after\x07");
		expect(onTitle).not.toHaveBeenCalled();
	});

	it("reports the measured cell size with the grid", () => {
		const measure = vi.spyOn(DomBlockRenderer.prototype, "measure").mockReturnValue({ cellWidth: 8, cellHeight: 16 });
		const onGeometry = vi.fn();
		const { host } = mount(undefined, onGeometry);
		setHostSize(host, 816, 416);
		expect(onGeometry).toHaveBeenLastCalledWith(98, 23, { width: 8, height: 16 });
		measure.mockRestore();
	});
});
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo test -p vt-wasm --test program_exports 2>&1 | tail -3; (cd ts/core && npx vitest run src/program-messages.test.ts 2>&1 | tail -4)
```
Expected: `unresolved import vt_wasm::flatten_notifications` from cargo; vitest fails (`ProgramMessages` is not exported / `core.onProgramMessage is not a function`).

- [ ] **Step 3: Implement**

Create `packages/terminal/crates/vt-wasm/src/program.rs` with exactly this content:

```rust
use vt_core::program::ProgramNotification;
use wasm_bindgen::prelude::*;

use crate::WasmTerminalCore;

pub fn flatten_notifications(notifications: Vec<ProgramNotification>) -> Vec<String> {
    notifications
        .into_iter()
        .flat_map(|notification| [notification.title, notification.body])
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
}
```

Create `packages/terminal/ts/core/src/program-messages.ts` with exactly this content:

```ts
import type { HostCapabilities } from "./types.js";

export type ProgramNotification = Readonly<{ title: string; body: string }>;

export type ProgramMessageEvent =
	| Readonly<{ kind: "title"; title: string }>
	| Readonly<{ kind: "pointer"; shape: string }>
	| Readonly<{ kind: "notification"; notification: ProgramNotification }>;

export type ProgramMessageListener = (event: ProgramMessageEvent) => void;

export type ProgramMessageSource = {
	program_generation(): number;
	title(): string;
	pointer_shape(): string;
	take_notifications(): string[];
};

export class ProgramMessages {
	private readonly source: ProgramMessageSource;
	private readonly host: HostCapabilities;
	private readonly listeners = new Set<ProgramMessageListener>();
	private generation = 0;
	private currentTitle = "";
	private currentPointer = "";

	constructor(source: ProgramMessageSource, host: HostCapabilities) {
		this.source = source;
		this.host = host;
	}

	title(): string {
		return this.currentTitle;
	}

	pointerShape(): string {
		return this.currentPointer;
	}

	onMessage(listener: ProgramMessageListener): () => void {
		this.listeners.add(listener);
		return () => {
			this.listeners.delete(listener);
		};
	}

	poll(): void {
		const generation = this.source.program_generation();
		if (generation === this.generation) return;
		this.generation = generation;
		const title = this.source.title();
		if (title !== this.currentTitle) {
			this.currentTitle = title;
			this.emit({ kind: "title", title });
		}
		const shape = this.source.pointer_shape();
		if (shape !== this.currentPointer) {
			this.currentPointer = shape;
			this.emit({ kind: "pointer", shape });
		}
		const flat = this.source.take_notifications();
		for (let index = 0; index + 1 < flat.length; index += 2) {
			const notification = { title: flat[index]!, body: flat[index + 1]! };
			this.host.notify?.(notification.title, notification.body);
			this.emit({ kind: "notification", notification });
		}
	}

	dispose(): void {
		this.listeners.clear();
	}

	private emit(event: ProgramMessageEvent): void {
		for (const listener of [...this.listeners]) listener(event);
	}
}
```

Create `packages/terminal/ts/react/src/use-program-messages.ts` with exactly this content:

```ts
import { useLayoutEffect, type RefObject } from "react";
import type { TerminalCore } from "@operator/terminal-core";

export const POINTER_SHAPE_PROPERTY = "--terminal-pointer-shape";

export function useProgramMessages(
	core: TerminalCore,
	surfaceRef: RefObject<HTMLElement | null>,
	onTitleRef: RefObject<((title: string) => void) | undefined>,
): void {
	useLayoutEffect(() => {
		const surface = surfaceRef.current;
		const apply = (shape: string) => {
			if (!surface) return;
			if (shape) surface.style.setProperty(POINTER_SHAPE_PROPERTY, shape);
			else surface.style.removeProperty(POINTER_SHAPE_PROPERTY);
		};
		apply(core.pointerShape());
		const off = core.onProgramMessage((event) => {
			if (event.kind === "pointer") apply(event.shape);
			else if (event.kind === "title") onTitleRef.current?.(event.title);
		});
		return () => {
			off();
			surface?.style.removeProperty(POINTER_SHAPE_PROPERTY);
		};
	}, [core, surfaceRef, onTitleRef]);
}
```

Edit 1 of 1 in `packages/terminal/crates/vt-wasm/src/lib.rs` — find this text (starts at line 1 of the unmodified file):

```rust
mod export;

use std::collections::HashMap;

use vt_core::{FindQuery, FindSession, TerminalCore};
use wasm_bindgen::prelude::*;

pub use export::{
    checked_u32_from_u64, ExportBuffers, ExportError, BLOCK_RECORD_WORDS, CELL_SPAN_WORDS,
    COMPACTION_DIVISOR, FIND_MATCH_WORDS, STYLE_RUN_WORDS,
```

replace it with:

```rust
mod export;
mod program;

use std::collections::HashMap;

use vt_core::{FindQuery, FindSession, TerminalCore};
use wasm_bindgen::prelude::*;

pub use program::flatten_notifications;

pub use export::{
    checked_u32_from_u64, ExportBuffers, ExportError, BLOCK_RECORD_WORDS, CELL_SPAN_WORDS,
    COMPACTION_DIVISOR, FIND_MATCH_WORDS, STYLE_RUN_WORDS,
```

Edit 1 of 6 in `packages/terminal/ts/core/src/terminal-core.ts` — find this text (starts at line 11 of the unmodified file):

```ts
	type WasmInput,
} from "./wasm-runtime.js";
import { snapshotLogicalLines, type LogicalLine } from "./logical-lines.js";
import type {
	BlockId,
	ChangeListener,
```

replace it with:

```ts
	type WasmInput,
} from "./wasm-runtime.js";
import { snapshotLogicalLines, type LogicalLine } from "./logical-lines.js";
import { ProgramMessages, type ProgramMessageListener } from "./program-messages.js";
import type {
	BlockId,
	ChangeListener,
```

Edit 2 of 6 in `packages/terminal/ts/core/src/terminal-core.ts` — find this text (starts at line 75 of the unmodified file):

```ts
	private readonly rowEventListeners = new Set<RowEventListener>();
	private readonly decoder = new TextDecoder("utf-8", { fatal: true });
	private readonly linkUris = new Map<number, string>();

	constructor(inner: WasmTerminalCore, host: HostCapabilities) {
		this.inner = inner;
		this.completions = new CompletionDispatcher(
			() => decodeBlocks(this.snapshot()).at(-1)?.cwd ?? "",
			host,
```

replace it with:

```ts
	private readonly rowEventListeners = new Set<RowEventListener>();
	private readonly decoder = new TextDecoder("utf-8", { fatal: true });
	private readonly linkUris = new Map<number, string>();
	private readonly program: ProgramMessages;

	constructor(inner: WasmTerminalCore, host: HostCapabilities) {
		this.inner = inner;
		this.program = new ProgramMessages(inner, host);
		this.completions = new CompletionDispatcher(
			() => decodeBlocks(this.snapshot()).at(-1)?.cwd ?? "",
			host,
```

Edit 3 of 6 in `packages/terminal/ts/core/src/terminal-core.ts` — find this text (starts at line 117 of the unmodified file):

```ts
			return;
		}
		this.inner.feed(bytes, Date.now());
		if (!this.notifyIfChanged() && this.inner.synchronized_output()) {
			this.notifyAll();
		}
```

replace it with:

```ts
			return;
		}
		this.inner.feed(bytes, Date.now());
		this.program.poll();
		if (!this.notifyIfChanged() && this.inner.synchronized_output()) {
			this.notifyAll();
		}
```

Edit 4 of 6 in `packages/terminal/ts/core/src/terminal-core.ts` — find this text (starts at line 177 of the unmodified file):

```ts
		if (!this.inner.tick(nowMs)) {
			return false;
		}
		this.notifyIfChanged();
		return true;
	}
```

replace it with:

```ts
		if (!this.inner.tick(nowMs)) {
			return false;
		}
		this.program.poll();
		this.notifyIfChanged();
		return true;
	}
```

Edit 5 of 6 in `packages/terminal/ts/core/src/terminal-core.ts` — find this text (starts at line 471 of the unmodified file):

```ts
		return this.inner.block_bookmarked(idLo, idHi);
	}

	lineEditorState(): LineEditorState {
		return LINE_EDITOR_STATES[this.snapshot().lineEditorState] ?? "unknown";
	}
```

replace it with:

```ts
		return this.inner.block_bookmarked(idLo, idHi);
	}

	title(): string {
		return this.program.title();
	}

	pointerShape(): string {
		return this.program.pointerShape();
	}

	onProgramMessage(listener: ProgramMessageListener): () => void {
		return this.program.onMessage(listener);
	}

	lineEditorState(): LineEditorState {
		return LINE_EDITOR_STATES[this.snapshot().lineEditorState] ?? "unknown";
	}
```

Edit 6 of 6 in `packages/terminal/ts/core/src/terminal-core.ts` — find this text (starts at line 521 of the unmodified file):

```ts
		}
		this.disposed = true;
		this.completions.dispose();
		this.listeners.clear();
		this.backlog = [];
		this.backlogBytes = 0;
```

replace it with:

```ts
		}
		this.disposed = true;
		this.completions.dispose();
		this.program.dispose();
		this.listeners.clear();
		this.backlog = [];
		this.backlogBytes = 0;
```

Edit 1 of 1 in `packages/terminal/ts/core/src/index-browser.ts` — find this text (starts at line 71 of the unmodified file):

```ts
} from "./style-runs.js";
export { CELL_SPAN_WORDS } from "./cell-spans.js";
export { joinLogicalLine, type LogicalLine } from "./logical-lines.js";
export {
	FEED_BUDGET_MS,
	FEED_SLICE_BYTES,
```

replace it with:

```ts
} from "./style-runs.js";
export { CELL_SPAN_WORDS } from "./cell-spans.js";
export { joinLogicalLine, type LogicalLine } from "./logical-lines.js";
export {
	ProgramMessages,
	type ProgramMessageEvent,
	type ProgramMessageListener,
	type ProgramMessageSource,
	type ProgramNotification,
} from "./program-messages.js";
export {
	FEED_BUDGET_MS,
	FEED_SLICE_BYTES,
```

Edit 1 of 6 in `packages/terminal/ts/react/src/TerminalSurface.tsx` — find this text (starts at line 28 of the unmodified file):

```tsx
import { AltScreenSlot } from "./AltScreenSlot.js";
import { isMacPlatform } from "./surface-geometry.js";
import { useSurfaceInput } from "./use-surface-input.js";

export interface TerminalSurfaceProps {
	core: TerminalCore;
```

replace it with:

```tsx
import { AltScreenSlot } from "./AltScreenSlot.js";
import { isMacPlatform } from "./surface-geometry.js";
import { useSurfaceInput } from "./use-surface-input.js";
import { useProgramMessages } from "./use-program-messages.js";

export type CellSize = Readonly<{ width: number; height: number }>;

export interface TerminalSurfaceProps {
	core: TerminalCore;
```

Edit 2 of 6 in `packages/terminal/ts/react/src/TerminalSurface.tsx` — find this text (starts at line 40 of the unmodified file):

```tsx
	strings?: TerminalStrings;
	onSend(text: string): void;
	onSendRaw(data: string): void;
	onGeometry?: (columns: number, rows: number) => void;
	/**
	 * Bump to force the surface to re-derive its grid from the live box.
	 *
```

replace it with:

```tsx
	strings?: TerminalStrings;
	onSend(text: string): void;
	onSendRaw(data: string): void;
	onGeometry?: (columns: number, rows: number, cell?: CellSize) => void;
	onTitle?: (title: string) => void;
	/**
	 * Bump to force the surface to re-derive its grid from the live box.
	 *
```

Edit 3 of 6 in `packages/terminal/ts/react/src/TerminalSurface.tsx` — find this text (starts at line 85 of the unmodified file):

```tsx
	onSend,
	onSendRaw,
	onGeometry,
	onPaint,
	onBlockFinished,
	onHint,
```

replace it with:

```tsx
	onSend,
	onSendRaw,
	onGeometry,
	onTitle,
	onPaint,
	onBlockFinished,
	onHint,
```

Edit 4 of 6 in `packages/terminal/ts/react/src/TerminalSurface.tsx` — find this text (starts at line 107 of the unmodified file):

```tsx
	onHintRef.current = onHint;
	const onDraftChangeRef = useRef(onDraftChange);
	onDraftChangeRef.current = onDraftChange;
	const visibleRef = useRef(visible);
	visibleRef.current = visible;
	const findBarRef = useRef<FindBar | null>(null);
```

replace it with:

```tsx
	onHintRef.current = onHint;
	const onDraftChangeRef = useRef(onDraftChange);
	onDraftChangeRef.current = onDraftChange;
	const onTitleRef = useRef(onTitle);
	onTitleRef.current = onTitle;
	const visibleRef = useRef(visible);
	visibleRef.current = visible;
	const findBarRef = useRef<FindBar | null>(null);
```

Edit 5 of 6 in `packages/terminal/ts/react/src/TerminalSurface.tsx` — find this text (starts at line 286 of the unmodified file):

```tsx
			gridRowsRef.current = rows;
			if (changed) renderer.selectionClear();
			core.resize(columns, rows);
			onGeometry?.(columns, rows);
		};
		apply(true);
		if (typeof ResizeObserver !== "function") {
```

replace it with:

```tsx
			gridRowsRef.current = rows;
			if (changed) renderer.selectionClear();
			core.resize(columns, rows);
			onGeometry?.(columns, rows, { width: cellWidth, height: cellHeight });
		};
		apply(true);
		if (typeof ResizeObserver !== "function") {
```

Edit 6 of 6 in `packages/terminal/ts/react/src/TerminalSurface.tsx` — find this text (starts at line 369 of the unmodified file):

```tsx
		};
	}, [altActive, core, onSendRaw]);

	useSurfaceInput(
		{ hostRef, editorHostRef, surfaceRef, rendererRef, compositionRef, gridColumnsRef, gridRowsRef, hostCapsRef, onHintRef },
		core,
```

replace it with:

```tsx
		};
	}, [altActive, core, onSendRaw]);

	useProgramMessages(core, surfaceRef, onTitleRef);

	useSurfaceInput(
		{ hostRef, editorHostRef, surfaceRef, rendererRef, compositionRef, gridColumnsRef, gridRowsRef, hostCapsRef, onHintRef },
		core,
```

Edit 1 of 1 in `packages/terminal/ts/react/src/index.ts` — find this text (starts at line 1 of the unmodified file):

```ts
export { TerminalSurface, type TerminalSurfaceProps } from "./TerminalSurface.js";
export { AltScreenSlot, type AltScreenSlotProps } from "./AltScreenSlot.js";
export { createCompositionTarget, type CompositionTarget } from "@operator/terminal-core";
export {
```

replace it with:

```ts
export { TerminalSurface, type CellSize, type TerminalSurfaceProps } from "./TerminalSurface.js";
export { POINTER_SHAPE_PROPERTY } from "./use-program-messages.js";
export { AltScreenSlot, type AltScreenSlotProps } from "./AltScreenSlot.js";
export { createCompositionTarget, type CompositionTarget } from "@operator/terminal-core";
export {
```

Edit 1 of 1 in `packages/terminal/ts/renderer-dom/src/styles.css` — find this text (starts at line 201 of the unmodified file):

```css
.terminal-alt-surface {
	-webkit-user-select: none;
	user-select: none;
	cursor: default;
}

/* The hand appears only while a link is under the pointer, the way Warp swaps
```

replace it with:

```css
.terminal-alt-surface {
	-webkit-user-select: none;
	user-select: none;
	cursor: var(--terminal-pointer-shape, default);
}

/* The hand appears only while a link is under the pointer, the way Warp swaps
```

Edit 1 of 1 in `packages/terminal/ts/renderer-dom/src/styles.ts` — find this text (starts at line 201 of the unmodified file):

```ts
.terminal-alt-surface {
	-webkit-user-select: none;
	user-select: none;
	cursor: default;
}

/* The hand appears only while a link is under the pointer, the way Warp swaps
```

replace it with:

```ts
.terminal-alt-surface {
	-webkit-user-select: none;
	user-select: none;
	cursor: var(--terminal-pointer-shape, default);
}

/* The hand appears only while a link is under the pointer, the way Warp swaps
```

Edit 1 of 1 in `packages/terminal/ts/renderer-dom/src/styles-parity.test.ts` — find this text (starts at line 109 of the unmodified file):

```ts
			terminalStyles.indexOf("}", terminalStyles.indexOf(".terminal-block,")),
		);
		expect(block).toContain(".terminal-alt-surface");
		expect(block).toContain("cursor: default");
		expect(block).not.toContain("cursor: text");
	});

```

replace it with:

```ts
			terminalStyles.indexOf("}", terminalStyles.indexOf(".terminal-block,")),
		);
		expect(block).toContain(".terminal-alt-surface");
		expect(block).toContain("cursor: var(--terminal-pointer-shape, default)");
		expect(block).not.toContain("cursor: text");
	});

```

`styles.css` and `styles.ts` must stay byte-identical in that block (`styles-parity.test.ts:8-12`); both files keep their line counts (594 for `styles.ts`, under the 600 cap).

- [ ] **Step 4: Rebuild the renderer wasm and TS, run the three suites**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo test -p vt-wasm 2>&1 | grep -E "FAILED|panicked|test result: ok. 2 passed" ; npm run build:wasm -- --force && grep -c "take_notifications(): string\[\]" ts/core/wasm/vt_core.d.ts && npm run build:ts && for p in core renderer-dom react; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Test Files|Tests "); done && npm run check:boundaries && wc -l ts/core/src/terminal-core.ts ts/react/src/TerminalSurface.tsx
```
Expected: `test result: ok. 2 passed` and no `FAILED`; `1`; every suite `passed` with no failures (author: core 9 files / 87 tests, renderer-dom 56 / 915, react 12 / 127); `boundary check passed`; `terminal-core.ts` 582 lines, `TerminalSurface.tsx` 443.

- [ ] **Step 5: Commit** (`ts/core/wasm` and `dist` are gitignored and are not added)

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/crates/vt-wasm/src/program.rs \
  packages/terminal/crates/vt-wasm/tests/program_exports.rs \
  packages/terminal/ts/core/src/program-messages.ts \
  packages/terminal/ts/core/src/program-messages.test.ts \
  packages/terminal/ts/react/src/use-program-messages.ts \
  packages/terminal/ts/react/src/TerminalSurface.program.test.tsx \
  packages/terminal/crates/vt-wasm/src/lib.rs \
  packages/terminal/ts/core/src/terminal-core.ts \
  packages/terminal/ts/core/src/index-browser.ts \
  packages/terminal/ts/react/src/TerminalSurface.tsx \
  packages/terminal/ts/react/src/index.ts \
  packages/terminal/ts/renderer-dom/src/styles.css \
  packages/terminal/ts/renderer-dom/src/styles.ts \
  packages/terminal/ts/renderer-dom/src/styles-parity.test.ts
git commit -m "feat(terminal): expose program titles, notifications and pointer shape to hosts" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
Expected: the commit succeeds; `git status --short` lists nothing this task touched (feel baselines, `ts/core/wasm` and `dist` are ignored or restored). Never `git add -A`, `git commit -a` or `git stash`.

---

### Task 3: the pty-host mirror's wasm exports (vt-host C ABI + Go `vtwasm`)

**Files:**
- Create: `packages/terminal/crates/vt-host/src/program.rs`, `backend/internal/adapters/runtime/ptyhost/vtwasm/program.go`
- Modify: `packages/terminal/crates/vt-host/src/lib.rs:1` (a `mod program;` line; `lib.rs` is 558 lines, so the exports live in their own file), `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm` (rebuilt binary)
- Test: `backend/internal/adapters/runtime/ptyhost/vtwasm/program_test.go`

**Interfaces:**
- Consumes: Task 1's `TerminalCore` API.
- Produces: C ABI `vt_program_generation(handle) -> u32`, `vt_title(handle, out_ptr, out_cap) -> u32` (bytes written, 0 = empty, `RENDER_ERR`/`RENDER_TOO_BIG` as elsewhere), `vt_take_notifications(handle, out_ptr, out_cap) -> u32` (records `u32le title_len, title, u32le body_len, body`, whole records only), `vt_set_cell_pixels(handle, width, height)`, `vt_set_default_colors(handle, fg, bg)` (`0x01RRGGBB` = known colour, `0` = unknown). Go on `*vtwasm.Parser`: `ProgramGeneration() (uint32, error)`, `Title() (string, error)`, `TakeNotifications() ([]vtwasm.Notification, error)` with `Notification{Title, Body string}`, `SetCellPixels(width, height uint32) error`, `SetDefaultColors(foreground, background int32) error` (`-1` = unknown). Replies still leave through the existing `TakeQueryReplies` (`vtwasm.go:150`).

- [ ] **Step 1: Write the failing Go test**

Create `backend/internal/adapters/runtime/ptyhost/vtwasm/program_test.go` with exactly this content:

```go
package vtwasm

import (
	"bytes"
	"path/filepath"
	"reflect"
	"testing"
)

func TestTitleFollowsTheLatestOSC2(t *testing.T) {
	p := newTestParser(t, 80, 24)
	title, err := p.Title()
	if err != nil || title != "" {
		t.Fatalf("fresh title = %q, %v; want empty", title, err)
	}
	before, _ := p.ProgramGeneration()
	feed(t, p, "\x1b]0;◐ Working\x07\x1b]2;✳ Idle\x1b\\")
	title, err = p.Title()
	if err != nil || title != "✳ Idle" {
		t.Fatalf("title = %q, %v", title, err)
	}
	after, _ := p.ProgramGeneration()
	if after-before != 2 {
		t.Fatalf("generation moved %d, want 2", after-before)
	}
}

func TestNotificationsAreTakenOnceInOrder(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "\x1b]9;hello\x07\x1b]777;notify;Build;done\x07\x1b]99;;Kitty\x1b\\")
	got, err := p.TakeNotifications()
	if err != nil {
		t.Fatalf("take: %v", err)
	}
	want := []Notification{{Title: "", Body: "hello"}, {Title: "Build", Body: "done"}, {Title: "Kitty", Body: ""}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("notifications = %#v, want %#v", got, want)
	}
	again, err := p.TakeNotifications()
	if err != nil || len(again) != 0 {
		t.Fatalf("second take = %#v, %v; want none", again, err)
	}
}

func TestTheMirrorAnswersSizeAndColourQueries(t *testing.T) {
	p := newTestParser(t, 100, 30)
	if _, err := p.TakeQueryReplies(); err != nil {
		t.Fatalf("drain: %v", err)
	}
	feed(t, p, "\x1b[18t\x1b[16t\x1b]11;?\x07")
	replies, _ := p.TakeQueryReplies()
	if !bytes.Equal(replies, []byte("\x1b[8;30;100t")) {
		t.Fatalf("replies before appearance = %q", replies)
	}
	if err := p.SetCellPixels(9, 18); err != nil {
		t.Fatalf("cell pixels: %v", err)
	}
	if err := p.SetDefaultColors(0xd8dee9, 0x0a0b0d); err != nil {
		t.Fatalf("colours: %v", err)
	}
	feed(t, p, "\x1b[14t\x1b[16t\x1b]10;?\x07\x1b]11;?\x1b\\")
	replies, _ = p.TakeQueryReplies()
	want := "\x1b[4;540;900t\x1b[6;18;9t\x1b]10;rgb:d8d8/dede/e9e9\x07\x1b]11;rgb:0a0a/0b0b/0d0d\x1b\\"
	if string(replies) != want {
		t.Fatalf("replies = %q, want %q", replies, want)
	}
	if err := p.SetDefaultColors(-1, -1); err != nil {
		t.Fatalf("clear colours: %v", err)
	}
	feed(t, p, "\x1b]10;?\x07")
	if replies, _ := p.TakeQueryReplies(); len(replies) != 0 {
		t.Fatalf("cleared colours still answered: %q", replies)
	}
}

func TestMode2048ReportsOnResize(t *testing.T) {
	p := newTestParser(t, 80, 24)
	if err := p.SetCellPixels(8, 16); err != nil {
		t.Fatalf("cell pixels: %v", err)
	}
	_, _ = p.TakeQueryReplies()
	feed(t, p, "\x1b[?2048h")
	if replies, _ := p.TakeQueryReplies(); string(replies) != "\x1b[48;24;80;384;640t" {
		t.Fatalf("enable report = %q", replies)
	}
	if err := p.Resize(100, 30); err != nil {
		t.Fatalf("resize: %v", err)
	}
	if replies, _ := p.TakeQueryReplies(); string(replies) != "\x1b[48;30;100;480;800t" {
		t.Fatalf("resize report = %q", replies)
	}
}

func TestTheClaudeRecordingEndsOnItsIdleTitle(t *testing.T) {
	fixture := filepath.Join("..", "..", "..", "..", "..", "..", "packages", "terminal", "bench", "agent-session", "fixtures", "claude-long-50k")
	recording, sizes := readAgentFixture(t, fixture)
	p := feedAgentFixture(t, recording, sizes, productMirrorLimits)
	defer p.Close()
	title, err := p.Title()
	if err != nil {
		t.Fatalf("title: %v", err)
	}
	if title != "✳ Number list 1 to 3000" {
		t.Fatalf("final title = %q", title)
	}
	notes, err := p.TakeNotifications()
	if err != nil || len(notes) != 0 {
		t.Fatalf("notifications = %#v, %v; want none", notes, err)
	}
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && go test ./internal/adapters/runtime/ptyhost/vtwasm/ -run 'Title|Notification|Mirror|Mode2048|ClaudeRecording' -count=1 2>&1 | tail -3
```
Expected: build failure `p.Title undefined (type *Parser has no field or method Title)`.

- [ ] **Step 3: Implement**

Create `packages/terminal/crates/vt-host/src/program.rs` with exactly this content:

```rust
use crate::{CORES, RENDER_ERR, RENDER_TOO_BIG};

const KNOWN_COLOR: u32 = 0x0100_0000;

fn write_out(bytes: &[u8], out_ptr: u32, out_cap: u32) -> u32 {
    if bytes.len() > out_cap as usize {
        return RENDER_TOO_BIG;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr as *mut u8, bytes.len());
    }
    bytes.len() as u32
}

fn color(word: u32) -> Option<u32> {
    (word & KNOWN_COLOR != 0).then_some(word & 0x00ff_ffff)
}

#[no_mangle]
pub extern "C" fn vt_program_generation(handle: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => core.program_generation() as u32,
        None => 0,
    })
}

#[no_mangle]
pub extern "C" fn vt_title(handle: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => write_out(core.title().as_bytes(), out_ptr, out_cap),
        None => RENDER_ERR,
    })
}

#[no_mangle]
pub extern "C" fn vt_take_notifications(handle: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| {
        let mut cores = c.borrow_mut();
        let Some(core) = cores.get_mut(&handle) else {
            return RENDER_ERR;
        };
        let mut encoded = Vec::new();
        for notification in core.take_notifications() {
            let mut record = Vec::new();
            for part in [notification.title.as_bytes(), notification.body.as_bytes()] {
                record.extend_from_slice(&(part.len() as u32).to_le_bytes());
                record.extend_from_slice(part);
            }
            if encoded.len() + record.len() > out_cap as usize {
                break;
            }
            encoded.extend_from_slice(&record);
        }
        write_out(&encoded, out_ptr, out_cap)
    })
}

#[no_mangle]
pub extern "C" fn vt_set_cell_pixels(handle: u32, width: u32, height: u32) {
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.set_cell_pixels(width, height);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_set_default_colors(handle: u32, foreground: u32, background: u32) {
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.set_default_colors(color(foreground), color(background));
        }
    });
}
```

Edit 1 of 1 in `packages/terminal/crates/vt-host/src/lib.rs` — find this text (starts at line 1 of the unmodified file):

```rust
mod block_marks;
mod sgr;

use std::cell::RefCell;
```

replace it with:

```rust
mod block_marks;
mod program;
mod sgr;

use std::cell::RefCell;
```

Create `backend/internal/adapters/runtime/ptyhost/vtwasm/program.go` with exactly this content:

```go
package vtwasm

import (
	"encoding/binary"
	"fmt"
)

type Notification struct {
	Title string
	Body  string
}

const (
	titleBufferBytes        = 4096
	notificationBufferBytes = 64 << 10
	knownColor              = 0x0100_0000
)

func (p *Parser) ProgramGeneration() (uint32, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_program_generation").Call(p.ctx, uint64(p.handle))
	if err != nil {
		return 0, fmt.Errorf("vtwasm: program_generation: %w", err)
	}
	return uint32(res[0]), nil
}

func (p *Parser) Title() (string, error) {
	raw, err := p.readOut("vt_title", titleBufferBytes)
	return string(raw), err
}

func (p *Parser) TakeNotifications() ([]Notification, error) {
	raw, err := p.readOut("vt_take_notifications", notificationBufferBytes)
	if err != nil {
		return nil, err
	}
	var out []Notification
	for len(raw) > 0 {
		title, rest, ok := lengthPrefixed(raw)
		if !ok {
			return out, fmt.Errorf("vtwasm: truncated notification title")
		}
		body, rest, ok := lengthPrefixed(rest)
		if !ok {
			return out, fmt.Errorf("vtwasm: truncated notification body")
		}
		out = append(out, Notification{Title: string(title), Body: string(body)})
		raw = rest
	}
	return out, nil
}

func (p *Parser) SetCellPixels(width, height uint32) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if _, err := p.module.ExportedFunction("vt_set_cell_pixels").Call(p.ctx, uint64(p.handle), uint64(width), uint64(height)); err != nil {
		return fmt.Errorf("vtwasm: set_cell_pixels: %w", err)
	}
	return nil
}

func (p *Parser) SetDefaultColors(foreground, background int32) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if _, err := p.module.ExportedFunction("vt_set_default_colors").Call(p.ctx, uint64(p.handle), colorWord(foreground), colorWord(background)); err != nil {
		return fmt.Errorf("vtwasm: set_default_colors: %w", err)
	}
	return nil
}

func colorWord(rgb int32) uint64 {
	if rgb < 0 {
		return 0
	}
	return uint64(uint32(rgb)&0x00ff_ffff) | knownColor
}

func lengthPrefixed(raw []byte) ([]byte, []byte, bool) {
	if len(raw) < 4 {
		return nil, nil, false
	}
	n := binary.LittleEndian.Uint32(raw[:4])
	if uint64(len(raw)-4) < uint64(n) {
		return nil, nil, false
	}
	return raw[4 : 4+n], raw[4+n:], true
}

func (p *Parser) readOut(fn string, capacity uint32) ([]byte, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, uint64(capacity))
	if err != nil {
		return nil, fmt.Errorf("vtwasm: alloc %s buffer: %w", fn, err)
	}
	out := uint32(res[0])
	defer func() { _, _ = p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), uint64(capacity)) }()
	res, err = p.module.ExportedFunction(fn).Call(p.ctx, uint64(p.handle), uint64(out), uint64(capacity))
	if err != nil {
		return nil, fmt.Errorf("vtwasm: %s: %w", fn, err)
	}
	switch written := uint32(res[0]); written {
	case 0:
		return nil, nil
	case renderErr, renderTooBig:
		return nil, fmt.Errorf("vtwasm: %s failed for handle %d", fn, p.handle)
	default:
		bytes, ok := p.module.Memory().Read(out, written)
		if !ok {
			return nil, fmt.Errorf("vtwasm: read %d bytes at %d out of range", written, out)
		}
		return append([]byte(nil), bytes...), nil
	}
}
```

- [ ] **Step 4: Rebuild the host wasm into the backend asset and run the Go tests**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo clippy --all-targets -- -D warnings 2>&1 | grep -cE "^(warning|error)"; cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && cd ../../backend && gofmt -l internal/adapters/runtime/ptyhost/ && go test ./internal/adapters/runtime/ptyhost/vtwasm/ -count=1 2>&1 | tail -2
```
Expected: `0`; `gofmt -l` prints nothing; `ok  	github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm`. (The new fixture test reads `packages/terminal/bench/agent-session/fixtures/claude-long-50k`, committed in the repo.)

- [ ] **Step 5: Commit** (the binary is committed on purpose — `TERMINAL.md` §6)

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/crates/vt-host/src/program.rs \
  packages/terminal/crates/vt-host/src/lib.rs \
  backend/internal/adapters/runtime/ptyhost/vtwasm/program.go \
  backend/internal/adapters/runtime/ptyhost/vtwasm/program_test.go \
  backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm
git commit -m "feat(ptyhost): mirror exports for titles, notifications, cell size and colours" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
Expected: the commit succeeds; `git status --short` lists nothing this task touched (feel baselines, `ts/core/wasm` and `dist` are ignored or restored). Never `git add -A`, `git commit -a` or `git stash`.

---

### Task 4: the display title rule and the pty-host watcher connection

**Files:**
- Create: `backend/internal/domain/terminal_title.go`, `backend/internal/adapters/runtime/ptyhost/program.go`
- Modify: `backend/internal/adapters/runtime/ptyhost/proto.go:32,87`, `backend/internal/adapters/runtime/ptyhost/host.go:72,230,350,414,631,673,807,1145`, `backend/internal/adapters/runtime/ptyhost/respawn.go:82`
- Test: `backend/internal/domain/terminal_title_test.go`, `backend/internal/adapters/runtime/ptyhost/program_test.go`

**Interfaces:**
- Consumes: Task 3's `vtwasm.Parser` methods.
- Produces:
  - `domain.TerminalDisplayTitle(raw string) string`: trims leading space; if the title starts with a run of characters that are neither letters, digits nor spaces **followed by one space**, that run and the space are removed; the result is trimmed. `"◐ Number list"` → `"Number list"`, `"✳ "` → `""`, `"~/dev"` unchanged, `"1. first"` unchanged (user decision 1).
  - Protocol (`proto.go`): `MsgWatchReq = 0x12` (client → host, empty: this connection wants program events only), `MsgProgramEvent = 0x13` (host → watcher, JSON `ProgramEventPayload{Kind, Title, Body}` with `Kind` `ProgramEventTitle = "title"` or `ProgramEventNotification = "notification"`), `MsgAppearance = 0x14` (client → host, JSON `AppearancePayload{CellWidth, CellHeight int; Foreground, Background string}` — pixels and `#rrggbb`).
  - Host behaviour: a connection whose first frame is `MsgWatchReq` is registered in `host.watchers`, gets the current display title at once, and afterwards only program events — no replay, no terminal bytes, never counted for the grid or flow control. After every batch the mirror parses (`deliver`, `host.go:631`) and after the sync deadline tick (`tickParser`), `publishProgramLocked` checks the mirror's program generation and sends a title event **only when the stripped title changed** (Claude changes the raw title ~10 times a second while the spinner turns; `claude-long-50k` has 1,047 raw titles but 2 distinct stripped ones) and one event per notification. A watcher more than `maxQueuedClientBytes` behind is skipped, not blocked. `shutdown` closes watchers. `MsgAppearance` sets the mirror's colours and cell pixels (remembered and re-applied after a respawn) and writes any reply it causes (a mode-2048 report) to the pty; a grid change in `applyLargestLocked` writes the 2048 report the resize produces. A respawn (`respawn.go`) resets the program state and tells watchers the title is empty.

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/domain/terminal_title_test.go` with exactly this content:

```go
package domain

import "testing"

func TestTerminalDisplayTitle(t *testing.T) {
	cases := []struct {
		raw  string
		want string
	}{
		{"◐ Number list 1 to 3000", "Number list 1 to 3000"},
		{"◑ Number list 1 to 3000", "Number list 1 to 3000"},
		{"◒ Fixing tests", "Fixing tests"},
		{"◓ Fixing tests", "Fixing tests"},
		{"✳ Claude Code", "Claude Code"},
		{"✳️ Emoji spinner", "Emoji spinner"},
		{"⠋ Braille spinner", "Braille spinner"},
		{"** two symbols", "two symbols"},
		{"✳ ", ""},
		{"✳", "✳"},
		{"", ""},
		{"   ", ""},
		{"~/dev/operator", "~/dev/operator"},
		{"vim main.go", "vim main.go"},
		{"1. first", "1. first"},
		{"◐  double space", "double space"},
		{"  ◐ padded  ", "padded"},
		{"◐ ◑ nested", "◑ nested"},
	}
	for _, tc := range cases {
		if got := TerminalDisplayTitle(tc.raw); got != tc.want {
			t.Errorf("TerminalDisplayTitle(%q) = %q, want %q", tc.raw, got, tc.want)
		}
	}
}
```

Create `backend/internal/adapters/runtime/ptyhost/program_test.go` with exactly this content:

```go
package ptyhost

import (
	"encoding/json"
	"testing"
	"time"
)

func newWatcher(t *testing.T, addr string) *testClient {
	t.Helper()
	w := newTestClient(t, addr)
	if err := w.send(MsgWatchReq, nil); err != nil {
		t.Fatalf("send watch: %v", err)
	}
	return w
}

func readProgramEvent(t *testing.T, c *testClient) ProgramEventPayload {
	t.Helper()
	typ, payload := c.readFrame(t)
	if typ != MsgProgramEvent {
		t.Fatalf("frame type 0x%02x, want MsgProgramEvent (payload %q)", typ, payload)
	}
	var event ProgramEventPayload
	if err := json.Unmarshal(payload, &event); err != nil {
		t.Fatalf("decode program event: %v", err)
	}
	return event
}

func expectNoFrame(t *testing.T, c *testClient, within time.Duration) {
	t.Helper()
	select {
	case frame, ok := <-c.frameC:
		if ok {
			t.Fatalf("unexpected frame type 0x%02x payload %q", frame.typ, frame.payload)
		}
	case <-time.After(within):
	}
}

func readPTYInput(t *testing.T, f *serveFixture, want string) {
	t.Helper()
	got := make([]byte, 0, len(want))
	buf := make([]byte, 256)
	deadline := time.After(2 * time.Second)
	for len(got) < len(want) {
		readC := make(chan int, 1)
		go func() {
			n, _ := f.pty.ReadInput(buf)
			readC <- n
		}()
		select {
		case n := <-readC:
			got = append(got, buf[:n]...)
		case <-deadline:
			t.Fatalf("pty input = %q, want %q", got, want)
		}
	}
	if string(got) != want {
		t.Fatalf("pty input = %q, want %q", got, want)
	}
}

func sendAppearance(t *testing.T, c *testClient, appearance AppearancePayload) {
	t.Helper()
	payload, _ := json.Marshal(appearance)
	if err := c.send(MsgAppearance, payload); err != nil {
		t.Fatalf("send appearance: %v", err)
	}
	if err := c.send(MsgStatusReq, nil); err != nil {
		t.Fatalf("send status: %v", err)
	}
	for {
		if typ, _ := c.readFrame(t); typ == MsgStatusRes {
			return
		}
	}
}

func watcherCount(f *serveFixture) int {
	f.host.mu.Lock()
	defer f.host.mu.Unlock()
	return len(f.host.watchers)
}

func TestAWatcherGetsTheCurrentTitleThenEachStrippedChange(t *testing.T) {
	f := startServeParsed(t, 901, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()

	if event := readProgramEvent(t, w); event.Kind != ProgramEventTitle || event.Title != "" {
		t.Fatalf("first event = %+v, want an empty title", event)
	}
	writeOutput(t, f, "\x1b]0;◐ Number list\x07")
	if event := readProgramEvent(t, w); event.Kind != ProgramEventTitle || event.Title != "Number list" {
		t.Fatalf("event = %+v, want the stripped title", event)
	}
	writeOutput(t, f, "\x1b]0;◑ Number list\x07")
	writeOutput(t, f, "\x1b]0;✳ Number list done\x07")
	if event := readProgramEvent(t, w); event.Title != "Number list done" {
		t.Fatalf("event = %+v, want only the next distinct stripped title", event)
	}
}

func TestAWatcherThatJoinsLateGetsTheTitleAlreadyShown(t *testing.T) {
	f := startServeParsed(t, 902, 80, 24)
	defer f.cancel()
	first := newWatcher(t, f.addr)
	defer first.close()
	readProgramEvent(t, first)
	writeOutput(t, f, "\x1b]2;◐ Refactor\x07")
	readProgramEvent(t, first)

	late := newWatcher(t, f.addr)
	defer late.close()
	if event := readProgramEvent(t, late); event.Title != "Refactor" {
		t.Fatalf("late watcher first event = %+v", event)
	}
}

func TestAWatcherGetsProgramNotifications(t *testing.T) {
	f := startServeParsed(t, 903, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()
	readProgramEvent(t, w)

	writeOutput(t, f, "\x1b]9;hello\x07\x1b]777;notify;Build;done\x07")
	first := readProgramEvent(t, w)
	second := readProgramEvent(t, w)
	if first != (ProgramEventPayload{Kind: ProgramEventNotification, Body: "hello"}) {
		t.Fatalf("first notification = %+v", first)
	}
	if second != (ProgramEventPayload{Kind: ProgramEventNotification, Title: "Build", Body: "done"}) {
		t.Fatalf("second notification = %+v", second)
	}
}

func TestAWatcherGetsNoTerminalBytes(t *testing.T) {
	f := startServeParsed(t, 904, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()
	readProgramEvent(t, w)

	writeOutput(t, f, "plain output\r\n")
	expectNoFrame(t, w, 150*time.Millisecond)
}

func TestAClosedWatcherIsForgotten(t *testing.T) {
	f := startServeParsed(t, 905, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	readProgramEvent(t, w)
	if got := watcherCount(f); got != 1 {
		t.Fatalf("watchers = %d, want 1", got)
	}
	w.close()
	deadline := time.Now().Add(2 * time.Second)
	for watcherCount(f) != 0 {
		if time.Now().After(deadline) {
			t.Fatalf("watcher still registered after close")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestShutdownClosesEveryWatcher(t *testing.T) {
	f := startServeParsed(t, 906, 80, 24)
	w := newWatcher(t, f.addr)
	readProgramEvent(t, w)
	f.cancel()
	f.waitDone(t)
	select {
	case _, ok := <-w.frameC:
		if ok {
			t.Fatal("watcher received a frame instead of a close")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("watcher connection was not closed by shutdown")
	}
	if got := watcherCount(f); got != 0 {
		t.Fatalf("watchers after shutdown = %d, want 0", got)
	}
}

func TestResetProgramTellsWatchersTheTitleIsGone(t *testing.T) {
	f := startServeParsed(t, 907, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()
	readProgramEvent(t, w)
	writeOutput(t, f, "\x1b]2;◐ Old task\x07")
	readProgramEvent(t, w)

	f.host.mu.Lock()
	f.host.resetProgramLocked()
	f.host.mu.Unlock()
	if event := readProgramEvent(t, w); event.Kind != ProgramEventTitle || event.Title != "" {
		t.Fatalf("event after reset = %+v, want an empty title", event)
	}
}

func TestAppearanceAnswersPixelAndColourQueriesOnThePty(t *testing.T) {
	f := startServeParsed(t, 908, 80, 24)
	defer f.cancel()
	c := newTestClient(t, f.addr)
	defer c.close()
	syncResize(t, c, 80, 24)

	sendAppearance(t, c, AppearancePayload{CellWidth: 9, CellHeight: 18, Foreground: "#ffffff", Background: "#1d2022"})
	writeOutput(t, f, "\x1b[16t\x1b]11;?\x07")
	readPTYInput(t, f, "\x1b[6;18;9t\x1b]11;rgb:1d1d/2020/2222\x07")
}

func TestMode2048ReportsReachThePtyOnEnableAndOnResize(t *testing.T) {
	f := startServeParsed(t, 909, 80, 24)
	defer f.cancel()
	c := newTestClient(t, f.addr)
	defer c.close()
	syncResize(t, c, 80, 24)

	sendAppearance(t, c, AppearancePayload{CellWidth: 8, CellHeight: 16})
	writeOutput(t, f, "\x1b[?2048h")
	readPTYInput(t, f, "\x1b[48;24;80;384;640t")

	resize, _ := json.Marshal(ResizePayload{Cols: 100, Rows: 30})
	if err := c.send(MsgResize, resize); err != nil {
		t.Fatalf("send resize: %v", err)
	}
	readPTYInput(t, f, "\x1b[48;30;100;480;800t")
}

func TestParseHexColor(t *testing.T) {
	cases := map[string]int32{"#1d2022": 0x1d2022, "#FFFFFF": 0xffffff, " #000000 ": 0, "": -1, "#fff": -1, "red": -1, "#gggggg": -1}
	for input, want := range cases {
		if got := parseHexColor(input); got != want {
			t.Errorf("parseHexColor(%q) = %d, want %d", input, got, want)
		}
	}
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && go test ./internal/domain/ -run TestTerminalDisplayTitle -count=1 2>&1 | tail -2; go test ./internal/adapters/runtime/ptyhost/ -run 'Watcher|ResetProgram|Appearance|Mode2048|ParseHex' -count=1 2>&1 | tail -2
```
Expected: `undefined: TerminalDisplayTitle`; `undefined: MsgWatchReq` (build failed).

- [ ] **Step 3: Implement**

Create `backend/internal/domain/terminal_title.go` with exactly this content:

```go
package domain

import (
	"strings"
	"unicode"
)

func TerminalDisplayTitle(raw string) string {
	runes := []rune(strings.TrimLeftFunc(raw, unicode.IsSpace))
	lead := 0
	for lead < len(runes) && !unicode.IsLetter(runes[lead]) && !unicode.IsDigit(runes[lead]) && !unicode.IsSpace(runes[lead]) {
		lead++
	}
	if lead > 0 && lead < len(runes) && runes[lead] == ' ' {
		runes = runes[lead+1:]
	}
	return strings.TrimSpace(string(runes))
}
```

Create `backend/internal/adapters/runtime/ptyhost/program.go` with exactly this content:

```go
package ptyhost

import (
	"encoding/json"
	"net"
	"strconv"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

const maxAppearancePixels = 4096

func programFrame(event ProgramEventPayload) []byte {
	payload, _ := json.Marshal(event)
	frame, _ := EncodeMessage(MsgProgramEvent, payload)
	return frame
}

func (h *host) serveWatcher(conn net.Conn, cs *clientState, buf []byte) {
	h.mu.Lock()
	h.watchers[conn] = cs
	cs.enqueue(programFrame(ProgramEventPayload{Kind: ProgramEventTitle, Title: h.shownTitle}))
	h.mu.Unlock()
	go h.runWriter(conn, cs)
	defer func() {
		cs.closeOut()
		h.mu.Lock()
		delete(h.watchers, conn)
		h.mu.Unlock()
		_ = conn.Close()
	}()
	for {
		if _, err := conn.Read(buf); err != nil {
			return
		}
	}
}

func (h *host) publishProgramLocked() {
	if h.parser == nil {
		return
	}
	generation, err := h.parser.ProgramGeneration()
	if err != nil || generation == h.programGen {
		return
	}
	h.programGen = generation
	var events []ProgramEventPayload
	if raw, err := h.parser.Title(); err == nil {
		if shown := domain.TerminalDisplayTitle(raw); shown != h.shownTitle {
			h.shownTitle = shown
			events = append(events, ProgramEventPayload{Kind: ProgramEventTitle, Title: shown})
		}
	}
	if notes, err := h.parser.TakeNotifications(); err == nil {
		for _, note := range notes {
			events = append(events, ProgramEventPayload{Kind: ProgramEventNotification, Title: note.Title, Body: note.Body})
		}
	}
	for _, event := range events {
		h.sendWatchersLocked(programFrame(event))
	}
}

func (h *host) sendWatchersLocked(frame []byte) {
	for _, cs := range h.watchers {
		if cs.queuedBytes() > maxQueuedClientBytes {
			continue
		}
		cs.enqueue(frame)
	}
}

func (h *host) resetProgramLocked() {
	h.programGen = 0
	if h.parser != nil && h.appearance != nil {
		applyAppearance(h.parser, *h.appearance)
	}
	if h.shownTitle == "" {
		return
	}
	h.shownTitle = ""
	h.sendWatchersLocked(programFrame(ProgramEventPayload{Kind: ProgramEventTitle}))
}

func (h *host) handleAppearance(payload []byte) {
	var appearance AppearancePayload
	if err := json.Unmarshal(payload, &appearance); err != nil {
		return
	}
	h.mu.Lock()
	h.appearance = &appearance
	var replies []byte
	if h.parser != nil {
		applyAppearance(h.parser, appearance)
		replies = h.takeQueryRepliesLocked()
	}
	pty := h.pty
	h.mu.Unlock()
	if len(replies) > 0 {
		_, _ = pty.Write(replies)
	}
}

func applyAppearance(parser interface {
	SetDefaultColors(foreground, background int32) error
	SetCellPixels(width, height uint32) error
}, appearance AppearancePayload) {
	_ = parser.SetDefaultColors(parseHexColor(appearance.Foreground), parseHexColor(appearance.Background))
	_ = parser.SetCellPixels(clampPixels(appearance.CellWidth), clampPixels(appearance.CellHeight))
}

func clampPixels(value int) uint32 {
	if value <= 0 {
		return 0
	}
	return uint32(min(value, maxAppearancePixels))
}

func parseHexColor(value string) int32 {
	hex, ok := strings.CutPrefix(strings.TrimSpace(value), "#")
	if !ok || len(hex) != 6 {
		return -1
	}
	rgb, err := strconv.ParseUint(hex, 16, 32)
	if err != nil {
		return -1
	}
	return int32(rgb)
}

func (cs *clientState) queuedBytes() int {
	cs.outMu.Lock()
	defer cs.outMu.Unlock()
	return cs.outBytes
}
```

Edit 1 of 2 in `backend/internal/adapters/runtime/ptyhost/proto.go` — find this text (starts at line 30 of the unmodified file):

```go
	MsgRespawnReq      byte = 0x0F // client -> host: JSON {cwd, shell, launchCmd, launchId}
	MsgRespawnRes      byte = 0x10 // host -> client: JSON {ok, pid?, error?}
	MsgAck             byte = 0x11 // client -> host: JSON {bytes}
)

// JSON payload structs shared with later tasks (kept minimal).
```

replace it with:

```go
	MsgRespawnReq      byte = 0x0F // client -> host: JSON {cwd, shell, launchCmd, launchId}
	MsgRespawnRes      byte = 0x10 // host -> client: JSON {ok, pid?, error?}
	MsgAck             byte = 0x11 // client -> host: JSON {bytes}
	MsgWatchReq        byte = 0x12
	MsgProgramEvent    byte = 0x13
	MsgAppearance      byte = 0x14
)

// JSON payload structs shared with later tasks (kept minimal).
```

Edit 2 of 2 in `backend/internal/adapters/runtime/ptyhost/proto.go` — find this text (starts at line 85 of the unmodified file):

```go
	Bytes int `json:"bytes"`
}

const frameHeaderBytes = 5

// EncodeMessage encodes a single frame into the binary protocol format.
```

replace it with:

```go
	Bytes int `json:"bytes"`
}

const (
	ProgramEventTitle        = "title"
	ProgramEventNotification = "notification"
)

type ProgramEventPayload struct {
	Kind  string `json:"kind"`
	Title string `json:"title"`
	Body  string `json:"body,omitempty"`
}

type AppearancePayload struct {
	CellWidth  int    `json:"cellWidth,omitempty"`
	CellHeight int    `json:"cellHeight,omitempty"`
	Foreground string `json:"foreground,omitempty"`
	Background string `json:"background,omitempty"`
}

const frameHeaderBytes = 5

// EncodeMessage encodes a single frame into the binary protocol format.
```

Edit 1 of 8 in `backend/internal/adapters/runtime/ptyhost/host.go` — find this text (starts at line 70 of the unmodified file):

```go
		cfg:       cfg,
		ctx:       ctx,
		clients:   make(map[net.Conn]*clientState),
		shutdownC: make(chan struct{}),
		capture:   &captureSink{},
		pty:       cfg.PTY,
```

replace it with:

```go
		cfg:       cfg,
		ctx:       ctx,
		clients:   make(map[net.Conn]*clientState),
		watchers:  make(map[net.Conn]*clientState),
		shutdownC: make(chan struct{}),
		capture:   &captureSink{},
		pty:       cfg.PTY,
```

Edit 2 of 8 in `backend/internal/adapters/runtime/ptyhost/host.go` — find this text (starts at line 228 of the unmodified file):

```go
	fedBytes       uint64
	persistMu      sync.Mutex
	persistedBytes uint64
}

// runWriter drains one client's outbound queue, blocking on each conn.Write
```

replace it with:

```go
	fedBytes       uint64
	persistMu      sync.Mutex
	persistedBytes uint64

	watchers   map[net.Conn]*clientState
	programGen uint32
	shownTitle string
	appearance *AppearancePayload
}

// runWriter drains one client's outbound queue, blocking on each conn.Write
```

Edit 3 of 8 in `backend/internal/adapters/runtime/ptyhost/host.go` — find this text (starts at line 348 of the unmodified file):

```go
	_ = h.pty.Resize(bestCols, bestRows)
	if h.parser != nil {
		_ = h.parser.Resize(uint32(bestCols), uint32(bestRows))
	}
	h.recorder.resize(bestCols, bestRows)
}
```

replace it with:

```go
	_ = h.pty.Resize(bestCols, bestRows)
	if h.parser != nil {
		_ = h.parser.Resize(uint32(bestCols), uint32(bestRows))
		if replies := h.takeQueryRepliesLocked(); len(replies) > 0 {
			go func(pty ptyConn) { _, _ = pty.Write(replies) }(h.pty)
		}
	}
	h.recorder.resize(bestCols, bestRows)
}
```

Edit 4 of 8 in `backend/internal/adapters/runtime/ptyhost/host.go` — find this text (starts at line 412 of the unmodified file):

```go
			states = append(states, cs)
		}
		h.clients = make(map[net.Conn]*clientState)
		h.mu.Unlock()
		// Closing a conn does not wake a writer parked on an empty queue, and
		// a deliver parked in awaitCapacity would never be signalled either.
```

replace it with:

```go
			states = append(states, cs)
		}
		h.clients = make(map[net.Conn]*clientState)
		for c, cs := range h.watchers {
			_ = c.Close()
			states = append(states, cs)
		}
		h.watchers = make(map[net.Conn]*clientState)
		h.mu.Unlock()
		// Closing a conn does not wake a writer parked on an empty queue, and
		// a deliver parked in awaitCapacity would never be signalled either.
```

Edit 5 of 8 in `backend/internal/adapters/runtime/ptyhost/host.go` — find this text (starts at line 629 of the unmodified file):

```go
	h.fedBytes += uint64(len(batch))
	inSync := h.parserInSyncLocked()
	replies := h.takeQueryRepliesLocked()
	pty := h.pty
	h.mu.Unlock()

```

replace it with:

```go
	h.fedBytes += uint64(len(batch))
	inSync := h.parserInSyncLocked()
	replies := h.takeQueryRepliesLocked()
	h.publishProgramLocked()
	pty := h.pty
	h.mu.Unlock()

```

Edit 6 of 8 in `backend/internal/adapters/runtime/ptyhost/host.go` — find this text (starts at line 671 of the unmodified file):

```go
func (h *host) tickParser() {
	if parser := h.currentParser(); parser != nil {
		_, _ = parser.Tick(time.Now().UnixMilli())
	}
}

```

replace it with:

```go
func (h *host) tickParser() {
	if parser := h.currentParser(); parser != nil {
		_, _ = parser.Tick(time.Now().UnixMilli())
		h.mu.Lock()
		h.publishProgramLocked()
		h.mu.Unlock()
	}
}

```

Edit 7 of 8 in `backend/internal/adapters/runtime/ptyhost/host.go` — find this text (starts at line 805 of the unmodified file):

```go
		_ = conn.Close()
		return
	}

	// Phase 2: apply the grid, render the replay, and join the broadcast set
	// under a SINGLE h.mu hold. deliver() takes h.mu and feeds the parser
```

replace it with:

```go
		_ = conn.Close()
		return
	}
	if opening == nil && len(deferred) > 0 && deferred[0].typ == MsgWatchReq {
		h.serveWatcher(conn, cs, buf)
		return
	}

	// Phase 2: apply the grid, render the replay, and join the broadcast set
	// under a SINGLE h.mu hold. deliver() takes h.mu and feeds the parser
```

Edit 8 of 8 in `backend/internal/adapters/runtime/ptyhost/host.go` — find this text (starts at line 1143 of the unmodified file):

```go
	case MsgRespawnReq:
		h.handleRespawn(conn, payload)

	case MsgAck:
		var ack AckPayload
		if err := json.Unmarshal(payload, &ack); err != nil || ack.Bytes < 0 {
```

replace it with:

```go
	case MsgRespawnReq:
		h.handleRespawn(conn, payload)

	case MsgAppearance:
		h.handleAppearance(payload)

	case MsgAck:
		var ack AckPayload
		if err := json.Unmarshal(payload, &ack); err != nil || ack.Bytes < 0 {
```

Edit 1 of 1 in `backend/internal/adapters/runtime/ptyhost/respawn.go` — find this text (starts at line 80 of the unmodified file):

```go
	h.mu.Lock()
	h.pty = pty
	h.parser = newParser
	h.curCols, h.curRows = 0, 0
	h.applyLargestLocked(nil)
	h.pumpDone = make(chan struct{})
```

replace it with:

```go
	h.mu.Lock()
	h.pty = pty
	h.parser = newParser
	h.resetProgramLocked()
	h.curCols, h.curRows = 0, 0
	h.applyLargestLocked(nil)
	h.pumpDone = make(chan struct{})
```

- [ ] **Step 4: Run the package tests (with the race detector)**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && gofmt -l internal/ && go vet ./internal/domain/ ./internal/adapters/runtime/ptyhost/ && go test ./internal/domain/ -count=1 2>&1 | tail -1 && for i in 1 2 3; do go test -race ./internal/adapters/runtime/ptyhost/ -run 'Watcher|ResetProgram|Appearance|Mode2048|ParseHex' -count=1 2>&1 | tail -1; done && go test -race ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -3
```
Expected: `gofmt -l` prints nothing; `ok` lines for domain, three `ok` lines for the new tests, and `ok` for `ptyhost`, `ptyregistry`, `vtwasm` (the whole package takes ~100 s under `-race`). If only `TestProcessEnvironmentLetsOverridesWin` fails, it is the pre-existing failure `TERMINAL.md` §5 names — record it and continue.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add backend/internal/domain/terminal_title.go \
  backend/internal/domain/terminal_title_test.go \
  backend/internal/adapters/runtime/ptyhost/program.go \
  backend/internal/adapters/runtime/ptyhost/program_test.go \
  backend/internal/adapters/runtime/ptyhost/proto.go \
  backend/internal/adapters/runtime/ptyhost/host.go \
  backend/internal/adapters/runtime/ptyhost/respawn.go
git commit -m "feat(ptyhost): watcher connections carry stripped titles and program notifications" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
Expected: the commit succeeds; `git status --short` lists nothing this task touched (feel baselines, `ts/core/wasm` and `dist` are ignored or restored). Never `git add -A`, `git commit -a` or `git stash`.

---

### Task 5: the daemon's runtime keeps one watch per live terminal

**Files:**
- Create: `backend/internal/ports/terminal_program.go`, `backend/internal/adapters/runtime/ptyhost/program_watch.go`
- Modify: `backend/internal/adapters/runtime/ptyhost/runtime.go:59,77,124,177,292`, `backend/internal/adapters/runtime/ptyhost/attach.go:39`
- Test: `backend/internal/adapters/runtime/ptyhost/program_watch_test.go`

**Interfaces:**
- Consumes: Task 4's `MsgWatchReq`/`MsgProgramEvent`/`ProgramEventPayload`/`MsgAppearance`/`AppearancePayload`.
- Produces (`ports`): `TerminalProgramEvent{Kind TerminalProgramEventKind; Title, Body string}` with kinds `TerminalProgramTitle = "title"`, `TerminalProgramNotification = "notification"`; `TerminalProgramReader` interface `TerminalTitles() map[string]string` + `WatchTerminalPrograms(fn func(handleID string, event TerminalProgramEvent)) (stop func())`; `TerminalAppearance{CellWidth, CellHeight int; Foreground, Background string}`; `AppearanceSetter` interface `SetAppearance(TerminalAppearance) error`. `*ptyhost.Runtime` implements `TerminalProgramReader`; the attach stream (`*loopbackStream`) implements `AppearanceSetter`.
- Watch lifecycle (in-memory only — nothing is written to SQLite; AGENTS.md "Do not store derived/display session status"): started by `Create`, by `IsAlive` when the host answered (the reaper probes every session every ~5 s, `observe/reaper`, so after a daemon restart every live session's watch is back within one reaper tick, and a dropped watch is re-opened), and by `Attach` (shell terminals are never probed). Idempotent per handle. Stopped by `Destroy`, which also clears the handle's title and tells listeners (an empty title event). Titles live in `Runtime.titles` and are read at subscribe time (`TerminalTitles`).

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/adapters/runtime/ptyhost/program_watch_test.go` with exactly this content:

```go
package ptyhost

import (
	"context"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type programRecorder struct {
	mu     sync.Mutex
	events []programRecord
}

type programRecord struct {
	id    string
	event ports.TerminalProgramEvent
}

func (p *programRecorder) record(id string, event ports.TerminalProgramEvent) {
	p.mu.Lock()
	p.events = append(p.events, programRecord{id: id, event: event})
	p.mu.Unlock()
}

func (p *programRecorder) waitFor(t *testing.T, want programRecord) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for {
		p.mu.Lock()
		for _, got := range p.events {
			if reflect.DeepEqual(got, want) {
				p.mu.Unlock()
				return
			}
		}
		seen := append([]programRecord(nil), p.events...)
		p.mu.Unlock()
		if time.Now().After(deadline) {
			t.Fatalf("never saw %+v; saw %+v", want, seen)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func (p *programRecorder) count() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.events)
}

func watchedRuntime(t *testing.T, id string, f *serveFixture) (*Runtime, *programRecorder) {
	t.Helper()
	isolateRegistry(t)
	rt := New(Options{})
	sess := &hostSession{addr: f.addr, pid: livePID()}
	rt.sessions[id] = sess
	rec := &programRecorder{}
	stop := rt.WatchTerminalPrograms(rec.record)
	t.Cleanup(stop)
	t.Cleanup(func() { rt.stopProgramWatch(id) })
	rt.ensureProgramWatch(id, sess)
	waitWatchers(t, f, 1)
	return rt, rec
}

func waitWatchers(t *testing.T, f *serveFixture, want int) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for watcherCount(f) != want {
		if time.Now().After(deadline) {
			t.Fatalf("host watchers = %d, want %d", watcherCount(f), want)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestTheProgramWatchDeliversStrippedTitlesAndNotifications(t *testing.T) {
	f := startServeParsed(t, 921, 80, 24)
	defer f.cancel()
	rt, rec := watchedRuntime(t, "sess-a", f)

	writeOutput(t, f, "\x1b]0;◐ Number list 1 to 3000\x07\x1b]9;done\x07")
	rec.waitFor(t, programRecord{id: "sess-a", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "Number list 1 to 3000"}})
	rec.waitFor(t, programRecord{id: "sess-a", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramNotification, Body: "done"}})
	if got := rt.TerminalTitles(); !reflect.DeepEqual(got, map[string]string{"sess-a": "Number list 1 to 3000"}) {
		t.Fatalf("titles = %v", got)
	}
}

func TestStoppingTheProgramWatchClosesItAndClearsTheTitle(t *testing.T) {
	f := startServeParsed(t, 922, 80, 24)
	defer f.cancel()
	rt, rec := watchedRuntime(t, "sess-b", f)
	writeOutput(t, f, "\x1b]2;◐ Task\x07")
	rec.waitFor(t, programRecord{id: "sess-b", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "Task"}})

	rt.stopProgramWatch("sess-b")
	waitWatchers(t, f, 0)
	rec.waitFor(t, programRecord{id: "sess-b", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle}})
	if got := rt.TerminalTitles(); len(got) != 0 {
		t.Fatalf("titles after stop = %v, want none", got)
	}
	rt.programMu.Lock()
	_, running := rt.programWatches["sess-b"]
	rt.programMu.Unlock()
	if running {
		t.Fatal("stopped watch is still registered")
	}
}

func TestEnsuringAWatchTwiceOpensOneConnection(t *testing.T) {
	f := startServeParsed(t, 923, 80, 24)
	defer f.cancel()
	rt, _ := watchedRuntime(t, "sess-c", f)
	rt.mu.Lock()
	sess := rt.sessions["sess-c"]
	rt.mu.Unlock()
	rt.ensureProgramWatch("sess-c", sess)
	rt.ensureProgramWatch("sess-c", sess)
	time.Sleep(50 * time.Millisecond)
	if got := watcherCount(f); got != 1 {
		t.Fatalf("host watchers = %d, want 1", got)
	}
}

func TestAnUnsubscribedListenerHearsNothing(t *testing.T) {
	f := startServeParsed(t, 924, 80, 24)
	defer f.cancel()
	rt, rec := watchedRuntime(t, "sess-d", f)
	late := &programRecorder{}
	stop := rt.WatchTerminalPrograms(late.record)
	stop()
	writeOutput(t, f, "\x1b]2;◐ After\x07")
	rec.waitFor(t, programRecord{id: "sess-d", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "After"}})
	if got := late.count(); got != 0 {
		t.Fatalf("unsubscribed listener got %d events", got)
	}
	rt.programMu.Lock()
	listeners := len(rt.programListeners)
	rt.programMu.Unlock()
	if listeners != 1 {
		t.Fatalf("listeners = %d, want 1", listeners)
	}
}

func TestAWatchThatDropsIsRestartedByTheNextLiveProbe(t *testing.T) {
	f := startServeParsed(t, 925, 80, 24)
	defer f.cancel()
	rt, rec := watchedRuntime(t, "sess-e", f)
	f.host.mu.Lock()
	for conn := range f.host.watchers {
		_ = conn.Close()
	}
	f.host.mu.Unlock()
	waitWatchers(t, f, 0)
	deadline := time.Now().Add(2 * time.Second)
	for {
		rt.programMu.Lock()
		_, running := rt.programWatches["sess-e"]
		rt.programMu.Unlock()
		if !running {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("dropped watch never unregistered")
		}
		time.Sleep(5 * time.Millisecond)
	}

	alive, err := rt.IsAlive(context.Background(), ports.RuntimeHandle{ID: "sess-e"})
	if err != nil || !alive {
		t.Fatalf("IsAlive = %v, %v", alive, err)
	}
	waitWatchers(t, f, 1)
	writeOutput(t, f, "\x1b]2;◐ Back\x07")
	rec.waitFor(t, programRecord{id: "sess-e", event: ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "Back"}})
}

func TestAStreamSendsItsAppearanceToTheHost(t *testing.T) {
	f := startServeParsed(t, 926, 80, 24)
	defer f.cancel()
	isolateRegistry(t)
	rt := New(Options{})
	rt.sessions["sess-f"] = &hostSession{addr: f.addr, pid: livePID()}
	t.Cleanup(func() { rt.stopProgramWatch("sess-f") })
	stream, err := rt.Attach(context.Background(), ports.RuntimeHandle{ID: "sess-f"}, 24, 80)
	if err != nil {
		t.Fatalf("attach: %v", err)
	}
	defer stream.Close()
	setter, ok := stream.(ports.AppearanceSetter)
	if !ok {
		t.Fatal("the loopback stream does not accept an appearance")
	}
	if err := setter.SetAppearance(ports.TerminalAppearance{CellWidth: 7, CellHeight: 15}); err != nil {
		t.Fatalf("set appearance: %v", err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for {
		f.host.mu.Lock()
		appearance := f.host.appearance
		f.host.mu.Unlock()
		if appearance != nil {
			if appearance.CellWidth != 7 || appearance.CellHeight != 15 {
				t.Fatalf("host appearance = %+v", *appearance)
			}
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("host never received the appearance")
		}
		time.Sleep(5 * time.Millisecond)
	}
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && go test ./internal/adapters/runtime/ptyhost/ -run 'ProgramWatch|EnsuringAWatch|Unsubscribed|WatchThatDrops|StreamSendsItsAppearance' -count=1 2>&1 | tail -2
```
Expected: build failure `rt.WatchTerminalPrograms undefined`.

- [ ] **Step 3: Implement**

Create `backend/internal/ports/terminal_program.go` with exactly this content:

```go
package ports

type TerminalProgramEventKind string

const (
	TerminalProgramTitle        TerminalProgramEventKind = "title"
	TerminalProgramNotification TerminalProgramEventKind = "notification"
)

type TerminalProgramEvent struct {
	Kind  TerminalProgramEventKind
	Title string
	Body  string
}

type TerminalProgramReader interface {
	TerminalTitles() map[string]string
	WatchTerminalPrograms(fn func(handleID string, event TerminalProgramEvent)) (stop func())
}

type TerminalAppearance struct {
	CellWidth  int
	CellHeight int
	Foreground string
	Background string
}

type AppearanceSetter interface {
	SetAppearance(appearance TerminalAppearance) error
}
```

Create `backend/internal/adapters/runtime/ptyhost/program_watch.go` with exactly this content:

```go
package ptyhost

import (
	"encoding/json"
	"net"
	"sync"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var _ ports.TerminalProgramReader = (*Runtime)(nil)

type programWatch struct {
	mu      sync.Mutex
	conn    net.Conn
	stopped bool
	done    chan struct{}
}

func (w *programWatch) stop() {
	w.mu.Lock()
	w.stopped = true
	conn := w.conn
	w.mu.Unlock()
	if conn != nil {
		_ = conn.Close()
	}
}

func (w *programWatch) attach(conn net.Conn) bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.stopped {
		return false
	}
	w.conn = conn
	return true
}

func (r *Runtime) ensureProgramWatch(id string, sess *hostSession) {
	if sess == nil || sess.addr == "" {
		return
	}
	r.programMu.Lock()
	if _, running := r.programWatches[id]; running {
		r.programMu.Unlock()
		return
	}
	w := &programWatch{done: make(chan struct{})}
	r.programWatches[id] = w
	r.programMu.Unlock()
	go r.runProgramWatch(id, sess.addr, w)
}

func (r *Runtime) runProgramWatch(id, addr string, w *programWatch) {
	defer close(w.done)
	defer func() {
		r.programMu.Lock()
		if r.programWatches[id] == w {
			delete(r.programWatches, id)
		}
		r.programMu.Unlock()
	}()
	conn, err := dialHost(addr, dialTimeout)
	if err != nil {
		return
	}
	if !w.attach(conn) {
		_ = conn.Close()
		return
	}
	defer func() { _ = conn.Close() }()
	frame, _ := EncodeMessage(MsgWatchReq, nil)
	if _, err := conn.Write(frame); err != nil {
		return
	}
	parser := NewMessageParser(func(msgType byte, payload []byte) {
		if msgType != MsgProgramEvent {
			return
		}
		var event ProgramEventPayload
		if json.Unmarshal(payload, &event) == nil {
			r.recordProgramEvent(id, event)
		}
	})
	buf := make([]byte, 4096)
	for {
		n, err := conn.Read(buf)
		if n > 0 {
			parser.Feed(buf[:n])
		}
		if err != nil {
			return
		}
	}
}

func (r *Runtime) stopProgramWatch(id string) {
	r.programMu.Lock()
	w := r.programWatches[id]
	delete(r.programWatches, id)
	r.programMu.Unlock()
	if w != nil {
		w.stop()
		<-w.done
	}
	r.recordProgramEvent(id, ProgramEventPayload{Kind: ProgramEventTitle})
}

func (r *Runtime) recordProgramEvent(id string, event ProgramEventPayload) {
	var out ports.TerminalProgramEvent
	switch event.Kind {
	case ProgramEventTitle:
		r.programMu.Lock()
		if r.titles[id] == event.Title {
			r.programMu.Unlock()
			return
		}
		if event.Title == "" {
			delete(r.titles, id)
		} else {
			r.titles[id] = event.Title
		}
		r.programMu.Unlock()
		out = ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: event.Title}
	case ProgramEventNotification:
		out = ports.TerminalProgramEvent{Kind: ports.TerminalProgramNotification, Title: event.Title, Body: event.Body}
	default:
		return
	}
	r.programMu.Lock()
	listeners := make([]func(string, ports.TerminalProgramEvent), 0, len(r.programListeners))
	for _, fn := range r.programListeners {
		listeners = append(listeners, fn)
	}
	r.programMu.Unlock()
	for _, fn := range listeners {
		fn(id, out)
	}
}

func (r *Runtime) TerminalTitles() map[string]string {
	r.programMu.Lock()
	defer r.programMu.Unlock()
	titles := make(map[string]string, len(r.titles))
	for id, title := range r.titles {
		titles[id] = title
	}
	return titles
}

func (r *Runtime) WatchTerminalPrograms(fn func(handleID string, event ports.TerminalProgramEvent)) func() {
	r.programMu.Lock()
	id := r.nextProgramListener
	r.nextProgramListener++
	r.programListeners[id] = fn
	r.programMu.Unlock()
	return func() {
		r.programMu.Lock()
		delete(r.programListeners, id)
		r.programMu.Unlock()
	}
}

func (s *loopbackStream) SetAppearance(appearance ports.TerminalAppearance) error {
	payload, err := json.Marshal(AppearancePayload{
		CellWidth:  appearance.CellWidth,
		CellHeight: appearance.CellHeight,
		Foreground: appearance.Foreground,
		Background: appearance.Background,
	})
	if err != nil {
		return err
	}
	frame, err := EncodeMessage(MsgAppearance, payload)
	if err != nil {
		return err
	}
	_, err = s.conn.Write(frame)
	return err
}

var _ ports.AppearanceSetter = (*loopbackStream)(nil)
```

Edit 1 of 5 in `backend/internal/adapters/runtime/ptyhost/runtime.go` — find this text (starts at line 57 of the unmodified file):

```go
	watchMu     sync.Mutex
	watchers    map[int]func(string, ports.TerminalHealth)
	nextWatcher int
}

// New creates a Runtime with the given options.
```

replace it with:

```go
	watchMu     sync.Mutex
	watchers    map[int]func(string, ports.TerminalHealth)
	nextWatcher int

	programMu           sync.Mutex
	programWatches      map[string]*programWatch
	titles              map[string]string
	programListeners    map[int]func(string, ports.TerminalProgramEvent)
	nextProgramListener int
}

// New creates a Runtime with the given options.
```

Edit 2 of 5 in `backend/internal/adapters/runtime/ptyhost/runtime.go` — find this text (starts at line 75 of the unmodified file):

```go
		probeTimeout:  isAliveTimeout,
		sessions:      make(map[string]*hostSession),
		watchers:      make(map[int]func(string, ports.TerminalHealth)),
	}
}

```

replace it with:

```go
		probeTimeout:  isAliveTimeout,
		sessions:      make(map[string]*hostSession),
		watchers:      make(map[int]func(string, ports.TerminalHealth)),

		programWatches:   make(map[string]*programWatch),
		titles:           make(map[string]string),
		programListeners: make(map[int]func(string, ports.TerminalProgramEvent)),
	}
}

```

Edit 3 of 5 in `backend/internal/adapters/runtime/ptyhost/runtime.go` — find this text (starts at line 122 of the unmodified file):

```go
	r.mu.Lock()
	r.sessions[id] = sess
	r.mu.Unlock()

	// Register in B2 registry for daemon-restart recovery (best-effort).
	// launchID is read from the local, not sess: the session is public the
```

replace it with:

```go
	r.mu.Lock()
	r.sessions[id] = sess
	r.mu.Unlock()
	r.ensureProgramWatch(id, sess)

	// Register in B2 registry for daemon-restart recovery (best-effort).
	// launchID is read from the local, not sess: the session is public the
```

Edit 4 of 5 in `backend/internal/adapters/runtime/ptyhost/runtime.go` — find this text (starts at line 175 of the unmodified file):

```go
	wasHung := sess.failedProbes >= hungAfterFailedProbes
	delete(r.sessions, handle.ID)
	r.mu.Unlock()
	if wasHung {
		r.notifyHealth(handle.ID, ports.TerminalHealthy)
	}
```

replace it with:

```go
	wasHung := sess.failedProbes >= hungAfterFailedProbes
	delete(r.sessions, handle.ID)
	r.mu.Unlock()
	r.stopProgramWatch(handle.ID)
	if wasHung {
		r.notifyHealth(handle.ID, ports.TerminalHealthy)
	}
```

Edit 5 of 5 in `backend/internal/adapters/runtime/ptyhost/runtime.go` — find this text (starts at line 290 of the unmodified file):

```go
	}
	_, alive, err := clientStatusWithin(sess.addr, r.probeTimeout)
	r.recordProbe(handle.ID, sess, err)
	return alive, err
}

```

replace it with:

```go
	}
	_, alive, err := clientStatusWithin(sess.addr, r.probeTimeout)
	r.recordProbe(handle.ID, sess, err)
	if alive {
		r.ensureProgramWatch(handle.ID, sess)
	}
	return alive, err
}

```

Edit 1 of 1 in `backend/internal/adapters/runtime/ptyhost/attach.go` — find this text (starts at line 37 of the unmodified file):

```go
	if err != nil {
		return nil, fmt.Errorf("ptyhost: dial host for %q: %w", handle.ID, err)
	}

	// The birth resize is handshaken synchronously, on the bare conn, before
	// any pipe exists. It is also what the host waits for before it renders
```

replace it with:

```go
	if err != nil {
		return nil, fmt.Errorf("ptyhost: dial host for %q: %w", handle.ID, err)
	}
	r.ensureProgramWatch(handle.ID, sess)

	// The birth resize is handshaken synchronously, on the bare conn, before
	// any pipe exists. It is also what the host waits for before it renders
```

- [ ] **Step 4: Run**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && gofmt -l internal/ && go vet ./internal/ports/ ./internal/adapters/runtime/... && go test -race ./internal/adapters/runtime/ptyhost/ -run 'ProgramWatch|EnsuringAWatch|Unsubscribed|WatchThatDrops|StreamSendsItsAppearance' -count=3 2>&1 | tail -1 && go test ./internal/adapters/runtime/... -count=1 2>&1 | tail -4
```
Expected: nothing from `gofmt -l`; `ok` for the new tests (3 runs); `ok` for `ptyhost`, `ptyregistry`, `vtwasm`, `runtimeselect` (and `parity` if it has tests).

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add backend/internal/ports/terminal_program.go \
  backend/internal/adapters/runtime/ptyhost/program_watch.go \
  backend/internal/adapters/runtime/ptyhost/program_watch_test.go \
  backend/internal/adapters/runtime/ptyhost/runtime.go \
  backend/internal/adapters/runtime/ptyhost/attach.go
git commit -m "feat(runtime): watch every live pty-host for program titles and notifications" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
Expected: the commit succeeds; `git status --short` lists nothing this task touched (feel baselines, `ts/core/wasm` and `dist` are ignored or restored). Never `git add -A`, `git commit -a` or `git stash`.

---

### Task 6: the mux `programs` channel and `appearance` frames

**Files:**
- Create: `backend/internal/terminal/programs.go`
- Modify: `backend/internal/terminal/protocol.go:28,40,57,94,117`, `backend/internal/terminal/manager.go:78,149,200,406,418,451`, `backend/internal/terminal/attachment.go:64,317,326`
- Test: `backend/internal/terminal/programs_test.go`

**Interfaces:**
- Consumes: Task 5's `ports.TerminalProgramReader` (type-asserted on the manager's `src`, exactly like `ports.TerminalHealthReader` in `terminal/health.go:5-11`) and `ports.AppearanceSetter`.
- Produces the wire protocol the renderer uses:
  - `ch:"programs"`: client `{type:"subscribe"}` / `{type:"unsubscribe"}`; server `{ch:"programs", type:"title", id:<handleId>, title}` (an absent `title` means empty) and `{ch:"programs", type:"notification", id, title, body}`. A first subscribe on a connection sends one `title` frame per known non-empty title; a repeated subscribe sends nothing.
  - `ch:"terminal"`, client `{type:"appearance", id, cellWidth, cellHeight, foreground, background}` → the attachment remembers it, applies it to its stream when the stream accepts one, and re-applies it on every re-attach (`setPTY`). Unknown ids are ignored.
  - `Manager.Close` stops the program watch.
- No OpenAPI change: the mux protocol is not in the spec (`npm run api` must still show no drift — Task 10).

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/terminal/programs_test.go` with exactly this content:

```go
package terminal

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type programSource struct {
	*fakeSource
	mu        sync.Mutex
	titles    map[string]string
	listeners []func(string, ports.TerminalProgramEvent)
	stopped   bool
}

func newProgramSource(src *fakeSource) *programSource {
	return &programSource{fakeSource: src, titles: map[string]string{}}
}

func (s *programSource) TerminalTitles() map[string]string {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make(map[string]string, len(s.titles))
	for id, title := range s.titles {
		out[id] = title
	}
	return out
}

func (s *programSource) WatchTerminalPrograms(fn func(string, ports.TerminalProgramEvent)) func() {
	s.mu.Lock()
	s.listeners = append(s.listeners, fn)
	s.mu.Unlock()
	return func() {
		s.mu.Lock()
		s.stopped = true
		s.listeners = nil
		s.mu.Unlock()
	}
}

func (s *programSource) emit(id string, event ports.TerminalProgramEvent) {
	s.mu.Lock()
	if event.Kind == ports.TerminalProgramTitle {
		s.titles[id] = event.Title
	}
	listeners := append([]func(string, ports.TerminalProgramEvent){}, s.listeners...)
	s.mu.Unlock()
	for _, fn := range listeners {
		fn(id, event)
	}
}

func (s *programSource) watchStopped() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.stopped
}

func assertNoProgramFrame(t *testing.T, c *fakeConn, d time.Duration) {
	t.Helper()
	deadline := time.After(d)
	for {
		select {
		case m := <-c.out:
			if m.Ch == chPrograms {
				t.Fatalf("unexpected program frame %+v", m)
			}
		case <-deadline:
			return
		}
	}
}

func subscribePrograms(t *testing.T, mgr *Manager, c *fakeConn) {
	t.Helper()
	c.in <- clientMsg{Ch: chPrograms, Type: msgSubscribe}
	eventually(t, time.Second, func() bool {
		mgr.mu.Lock()
		defer mgr.mu.Unlock()
		for conn := range mgr.conns {
			conn.mu.Lock()
			subscribed := conn.programsSubscribed
			conn.mu.Unlock()
			if subscribed {
				return true
			}
		}
		return false
	})
}

func TestProgramEventsReachOnlySubscribedConnections(t *testing.T) {
	src := newProgramSource(&fakeSource{alive: true})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	subscribed := serveConn(t, mgr, false)
	other := serveConn(t, mgr, false)
	subscribePrograms(t, mgr, subscribed)

	src.emit("sess-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "Number list"})
	title := recv(t, subscribed, chPrograms, msgTitle, time.Second)
	if title.ID != "sess-1" || title.Title != "Number list" {
		t.Fatalf("title frame = %+v", title)
	}
	src.emit("sess-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramNotification, Title: "Build", Body: "done"})
	note := recv(t, subscribed, chPrograms, msgNotification, time.Second)
	if note.ID != "sess-1" || note.Title != "Build" || note.Body != "done" {
		t.Fatalf("notification frame = %+v", note)
	}
	assertNoProgramFrame(t, other, 100*time.Millisecond)
}

func TestSubscribingToProgramsSendsEveryKnownTitle(t *testing.T) {
	src := newProgramSource(&fakeSource{alive: true})
	src.titles["sess-1"] = "Refactor"
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := serveConn(t, mgr, false)
	conn.in <- clientMsg{Ch: chPrograms, Type: msgSubscribe}
	got := recv(t, conn, chPrograms, msgTitle, time.Second)
	if got.ID != "sess-1" || got.Title != "Refactor" {
		t.Fatalf("snapshot frame = %+v", got)
	}
	conn.in <- clientMsg{Ch: chPrograms, Type: msgSubscribe}
	assertNoProgramFrame(t, conn, 100*time.Millisecond)
}

func TestUnsubscribingFromProgramsStopsTheFrames(t *testing.T) {
	src := newProgramSource(&fakeSource{alive: true})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := serveConn(t, mgr, false)
	subscribePrograms(t, mgr, conn)
	conn.in <- clientMsg{Ch: chPrograms, Type: msgUnsubscribe}
	eventually(t, time.Second, func() bool {
		mgr.mu.Lock()
		defer mgr.mu.Unlock()
		for c := range mgr.conns {
			c.mu.Lock()
			subscribed := c.programsSubscribed
			c.mu.Unlock()
			if subscribed {
				return false
			}
		}
		return true
	})
	src.emit("sess-1", ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: "ignored"})
	assertNoProgramFrame(t, conn, 100*time.Millisecond)
}

func TestClosingTheManagerStopsTheProgramWatch(t *testing.T) {
	src := newProgramSource(&fakeSource{alive: true})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	if src.watchStopped() {
		t.Fatal("watch stopped before Close")
	}
	mgr.Close()
	if !src.watchStopped() {
		t.Fatal("Close left the program watch running")
	}
}

type appearancePTY struct {
	*fakePTY
	mu      sync.Mutex
	applied []ports.TerminalAppearance
}

func (p *appearancePTY) SetAppearance(appearance ports.TerminalAppearance) error {
	p.mu.Lock()
	p.applied = append(p.applied, appearance)
	p.mu.Unlock()
	return nil
}

func (p *appearancePTY) appearances() []ports.TerminalAppearance {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]ports.TerminalAppearance(nil), p.applied...)
}

func TestAppearanceReachesTheStreamAndIsReappliedOnReattach(t *testing.T) {
	first := &appearancePTY{fakePTY: newFakePTY()}
	second := &appearancePTY{fakePTY: newFakePTY()}
	streams := []*appearancePTY{first, second}
	var mu sync.Mutex
	next := 0
	src := &fakeSource{alive: true}
	src.attachFn = func(context.Context, uint16, uint16) (ports.Stream, error) {
		mu.Lock()
		defer mu.Unlock()
		if next < len(streams) {
			stream := streams[next]
			next++
			return stream, nil
		}
		return newFakePTY(), nil
	}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := serveConn(t, mgr, false)
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen, Cols: 80, Rows: 24}
	recv(t, conn, chTerminal, msgOpened, time.Second)

	want := ports.TerminalAppearance{CellWidth: 16, CellHeight: 34, Foreground: "#ffffff", Background: "#1d2022"}
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgAppearance, CellWidth: 16, CellHeight: 34, Foreground: "#ffffff", Background: "#1d2022"}
	eventually(t, time.Second, func() bool {
		got := first.appearances()
		return len(got) == 1 && got[0] == want
	})

	_ = first.Close()
	eventually(t, 3*time.Second, func() bool {
		got := second.appearances()
		return len(got) == 1 && got[0] == want
	})
}

func TestAppearanceForAnUnknownTerminalIsIgnored(t *testing.T) {
	src := &fakeSource{alive: true}
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	conn := serveConn(t, mgr, false)
	conn.in <- clientMsg{Ch: chTerminal, ID: "missing", Type: msgAppearance, CellWidth: 8, CellHeight: 16}
	conn.in <- clientMsg{Ch: chSystem, Type: msgPing}
	recv(t, conn, chSystem, msgPong, time.Second)
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && go test ./internal/terminal/ -run 'Program|Appearance' -count=1 2>&1 | tail -2
```
Expected: build failure `undefined: chPrograms`.

- [ ] **Step 3: Implement**

Create `backend/internal/terminal/programs.go` with exactly this content:

```go
package terminal

import "github.com/OmarAly92/operator/backend/internal/ports"

func (m *Manager) startProgramWatch() {
	reader, ok := m.src.(ports.TerminalProgramReader)
	if !ok {
		return
	}
	m.stopProgramWatch = reader.WatchTerminalPrograms(m.publishProgramEvent)
}

func (m *Manager) terminalTitles() map[string]string {
	reader, ok := m.src.(ports.TerminalProgramReader)
	if !ok {
		return nil
	}
	return reader.TerminalTitles()
}

func programFrame(handleID string, event ports.TerminalProgramEvent) serverMsg {
	if event.Kind == ports.TerminalProgramNotification {
		return serverMsg{Ch: chPrograms, ID: handleID, Type: msgNotification, Title: event.Title, Body: event.Body}
	}
	return serverMsg{Ch: chPrograms, ID: handleID, Type: msgTitle, Title: event.Title}
}

func (m *Manager) publishProgramEvent(handleID string, event ports.TerminalProgramEvent) {
	frame := programFrame(handleID, event)
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

func (c *connState) handlePrograms(msg clientMsg) {
	switch msg.Type {
	case msgSubscribe:
		c.mu.Lock()
		already := c.programsSubscribed
		c.programsSubscribed = true
		c.mu.Unlock()
		if already {
			return
		}
		for id, title := range c.mgr.terminalTitles() {
			c.enqueue(programFrame(id, ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: title}))
		}
	case msgUnsubscribe:
		c.mu.Lock()
		c.programsSubscribed = false
		c.mu.Unlock()
	}
}

func appearanceOf(msg clientMsg) ports.TerminalAppearance {
	return ports.TerminalAppearance{
		CellWidth:  msg.CellWidth,
		CellHeight: msg.CellHeight,
		Foreground: msg.Foreground,
		Background: msg.Background,
	}
}

func (a *attachment) setAppearance(appearance ports.TerminalAppearance) error {
	a.mu.Lock()
	a.appearance = &appearance
	pty := a.pty
	a.mu.Unlock()
	return applyAppearance(pty, appearance)
}

func applyAppearance(pty ports.Stream, appearance ports.TerminalAppearance) error {
	setter, ok := pty.(ports.AppearanceSetter)
	if !ok {
		return nil
	}
	return setter.SetAppearance(appearance)
}
```

Edit 1 of 5 in `backend/internal/terminal/protocol.go` — find this text (starts at line 26 of the unmodified file):

```go
	chBlocks    = "blocks"

	chNotifications = "notifications"
)

// client message types (ch "terminal" unless noted).
```

replace it with:

```go
	chBlocks    = "blocks"

	chNotifications = "notifications"
	chPrograms      = "programs"
)

// client message types (ch "terminal" unless noted).
```

Edit 2 of 5 in `backend/internal/terminal/protocol.go` — find this text (starts at line 38 of the unmodified file):

```go
	msgSubscribe   = "subscribe"   // ch "subscribe"
	msgUnsubscribe = "unsubscribe" // ch "blocks"
	msgPing        = "ping"        // ch "system"
)

// server message types.
```

replace it with:

```go
	msgSubscribe   = "subscribe"   // ch "subscribe"
	msgUnsubscribe = "unsubscribe" // ch "blocks"
	msgPing        = "ping"        // ch "system"
	msgAppearance  = "appearance"
)

// server message types.
```

Edit 3 of 5 in `backend/internal/terminal/protocol.go` — find this text (starts at line 55 of the unmodified file):

```go
	// render the exact grid the PTY is using instead of their own fitted size.

	msgNotification = "notification"
)

// Client roles for a terminal open. A single PTY has one grid; when several
```

replace it with:

```go
	// render the exact grid the PTY is using instead of their own fitted size.

	msgNotification = "notification"
	msgTitle        = "title"
)

// Client roles for a terminal open. A single PTY has one grid; when several
```

Edit 4 of 5 in `backend/internal/terminal/protocol.go` — find this text (starts at line 92 of the unmodified file):

```go
	// it understands the runtime's history marks.
	Bytes   int  `json:"bytes,omitempty"`
	History bool `json:"history,omitempty"`
}

// serverMsg is one outbound frame.
```

replace it with:

```go
	// it understands the runtime's history marks.
	Bytes   int  `json:"bytes,omitempty"`
	History bool `json:"history,omitempty"`

	CellWidth  int    `json:"cellWidth,omitempty"`
	CellHeight int    `json:"cellHeight,omitempty"`
	Foreground string `json:"foreground,omitempty"`
	Background string `json:"background,omitempty"`
}

// serverMsg is one outbound frame.
```

Edit 5 of 5 in `backend/internal/terminal/protocol.go` — find this text (starts at line 115 of the unmodified file):

```go
	TerminalBlock *terminalBlockFrame `json:"terminalBlock,omitempty"`

	Notification *notificationFrame `json:"notification,omitempty"`
}

type notificationFrame struct {
```

replace it with:

```go
	TerminalBlock *terminalBlockFrame `json:"terminalBlock,omitempty"`

	Notification *notificationFrame `json:"notification,omitempty"`

	Title string `json:"title,omitempty"`
	Body  string `json:"body,omitempty"`
}

type notificationFrame struct {
```

Edit 1 of 6 in `backend/internal/terminal/manager.go` — find this text (starts at line 76 of the unmodified file):

```go
	stopNotificationFeed func()

	stopHealthWatch func()
}

// sharedTerm tracks every client currently viewing one terminal id (one PTY) so
```

replace it with:

```go
	stopNotificationFeed func()

	stopHealthWatch func()

	stopProgramWatch func()
}

// sharedTerm tracks every client currently viewing one terminal id (one PTY) so
```

Edit 2 of 6 in `backend/internal/terminal/manager.go` — find this text (starts at line 147 of the unmodified file):

```go
	}
	m.startNotificationFeed()
	m.startHealthWatch()
	return m
}

```

replace it with:

```go
	}
	m.startNotificationFeed()
	m.startHealthWatch()
	m.startProgramWatch()
	return m
}

```

Edit 3 of 6 in `backend/internal/terminal/manager.go` — find this text (starts at line 198 of the unmodified file):

```go
	if m.stopHealthWatch != nil {
		m.stopHealthWatch()
	}
	m.mu.Lock()
	if m.closed {
		m.mu.Unlock()
```

replace it with:

```go
	if m.stopHealthWatch != nil {
		m.stopHealthWatch()
	}
	if m.stopProgramWatch != nil {
		m.stopProgramWatch()
	}
	m.mu.Lock()
	if m.closed {
		m.mu.Unlock()
```

Edit 4 of 6 in `backend/internal/terminal/manager.go` — find this text (starts at line 404 of the unmodified file):

```go

	remote                  bool
	notificationsSubscribed bool
}

func (c *connState) handle(msg clientMsg) {
```

replace it with:

```go

	remote                  bool
	notificationsSubscribed bool
	programsSubscribed      bool
}

func (c *connState) handle(msg clientMsg) {
```

Edit 5 of 6 in `backend/internal/terminal/manager.go` — find this text (starts at line 416 of the unmodified file):

```go
		c.handleBlockSubscribe(msg)
	case chNotifications:
		c.handleNotifications(msg)
	case chSystem:
		if msg.Type == msgPing {
			c.enqueue(serverMsg{Ch: chSystem, Type: msgPong})
```

replace it with:

```go
		c.handleBlockSubscribe(msg)
	case chNotifications:
		c.handleNotifications(msg)
	case chPrograms:
		c.handlePrograms(msg)
	case chSystem:
		if msg.Type == msgPing {
			c.enqueue(serverMsg{Ch: chSystem, Type: msgPong})
```

Edit 6 of 6 in `backend/internal/terminal/manager.go` — find this text (starts at line 449 of the unmodified file):

```go
		c.mgr.updateTerminalSize(msg.ID, c, msg.Cols, msg.Rows, msg.Force)
	case msgClose:
		c.closeTerminal(msg.ID)
	case msgAck:
		if msg.Bytes <= 0 {
			return
```

replace it with:

```go
		c.mgr.updateTerminalSize(msg.ID, c, msg.Cols, msg.Rows, msg.Force)
	case msgClose:
		c.closeTerminal(msg.ID)
	case msgAppearance:
		if a := c.lookup(msg.ID); a != nil {
			_ = a.setAppearance(appearanceOf(msg))
		}
	case msgAck:
		if msg.Bytes <= 0 {
			return
```

Edit 1 of 3 in `backend/internal/terminal/attachment.go` — find this text (starts at line 62 of the unmodified file):

```go
	cancel       context.CancelFunc
	rows         uint16 // last size the client asked for; re-applied on every attach
	cols         uint16
	closed       bool
	exited       bool
	opened       bool
```

replace it with:

```go
	cancel       context.CancelFunc
	rows         uint16 // last size the client asked for; re-applied on every attach
	cols         uint16
	appearance   *ports.TerminalAppearance
	closed       bool
	exited       bool
	opened       bool
```

Edit 2 of 3 in `backend/internal/terminal/attachment.go` — find this text (starts at line 315 of the unmodified file):

```go
	a.pty = p
	a.inputReady = false
	rows, cols := a.rows, a.cols
	shouldOpen := !a.opened
	if shouldOpen {
		a.opened = true
```

replace it with:

```go
	a.pty = p
	a.inputReady = false
	rows, cols := a.rows, a.cols
	appearance := a.appearance
	shouldOpen := !a.opened
	if shouldOpen {
		a.opened = true
```

Edit 3 of 3 in `backend/internal/terminal/attachment.go` — find this text (starts at line 324 of the unmodified file):

```go
	if rows > 0 && cols > 0 {
		_ = p.Resize(rows, cols)
	}
	if shouldOpen && onOpen != nil {
		onOpen()
	}
```

replace it with:

```go
	if rows > 0 && cols > 0 {
		_ = p.Resize(rows, cols)
	}
	if appearance != nil {
		_ = applyAppearance(p, *appearance)
	}
	if shouldOpen && onOpen != nil {
		onOpen()
	}
```

- [ ] **Step 4: Run**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && gofmt -l internal/ && go vet ./internal/terminal/ && go test -race ./internal/terminal/ -run 'Program|Appearance' -count=3 2>&1 | tail -1 && go test -race ./internal/terminal/ -count=1 2>&1 | tail -1
```
Expected: nothing from `gofmt -l`; two `ok  	github.com/OmarAly92/operator/backend/internal/terminal` lines.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add backend/internal/terminal/programs.go \
  backend/internal/terminal/programs_test.go \
  backend/internal/terminal/protocol.go \
  backend/internal/terminal/manager.go \
  backend/internal/terminal/attachment.go
git commit -m "feat(terminal): programs mux channel and per-attachment appearance" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
Expected: the commit succeeds; `git status --short` lists nothing this task touched (feel baselines, `ts/core/wasm` and `dist` are ignored or restored). Never `git add -A`, `git commit -a` or `git stash`.

---

### Task 7: the renderer's program feed — titles store, on-screen terminals, notifications

**Files:**
- Create: `frontend/src/renderer/lib/terminal-titles.ts`, `frontend/src/renderer/lib/on-screen-terminals.ts`, `frontend/src/renderer/lib/program-feed.ts`, `frontend/src/renderer/components/ProgramRuntime.tsx`
- Modify: `frontend/src/renderer/lib/terminal-mux.ts:14,32,34,112,139,170,212,276,310,318,322,449`, `frontend/src/renderer/routes/_shell.tsx:8,552`, `frontend/src/renderer/test/shell-new-session-shortcut.test.tsx:153`, `frontend/src/renderer/components/split/SplitWorkspace.tsx:24,101`, `frontend/src/renderer/components/ShellTerminalsView.tsx:11,64`, `frontend/src/renderer/i18n/en.json:924`
- Test: `frontend/src/renderer/lib/terminal-mux.programs.test.ts`, `frontend/src/renderer/lib/terminal-titles.test.tsx`, `frontend/src/renderer/lib/on-screen-terminals.test.ts`, `frontend/src/renderer/lib/program-feed.test.ts`, `frontend/src/renderer/components/ProgramRuntime.test.tsx`, `frontend/src/renderer/components/split/SplitWorkspaceOnScreenTerminals.test.tsx`, `frontend/src/renderer/components/ShellTerminalsView.onscreen.test.tsx`

**Interfaces:**
- Consumes: Task 6's wire protocol.
- Produces:
  - `terminal-mux.ts`: types `TerminalAppearance`, `ProgramNotification`; frame helpers `appearanceFrame`, `programsSubscribeFrame`, `programsUnsubscribeFrame`; optional `TerminalMux` members `appearance?(id, appearance)`, `onProgramTitle?(listener: (handleId, title) => void): () => void`, `onProgramNotification?(listener: (handleId, {title, body}) => void): () => void` (optional so the existing test fakes of `TerminalMux` still type-check). `createTerminalMux` subscribes on the first program listener and unsubscribes after the last; the pool lease forwards and releases them.
  - `terminal-titles.ts`: `setTerminalTitle(handleId, title)`, `clearTerminalTitles()`, `terminalTitle(handleId?)`, `subscribeTerminalTitles(listener)`, `terminalTitleListenerCount()`, hook `useTerminalTitle(handleId?: string): string`.
  - `on-screen-terminals.ts`: `claimOnScreenTerminals(handleIds): () => void`, `terminalShownInAPane(handleId)`, `isTerminalOnScreen(handleId)` = shown in a pane **and** `document.visibilityState === "visible"` **and** `document.hasFocus()` — the same "on screen in a focused Operator window" rule agent alerts use (`lib/notifications.ts` `shouldToast`, spec 2026-09-23-agent-alerts-design.md D2). `SplitWorkspace` claims the terminal of each pane's **active** tab (session → `session.terminalHandleId`, shell/reviewer → `tab.handleId`); `ShellTerminalsView` claims its active shell.
  - `program-feed.ts`: `connectProgramFeed(createMux, { onTitle, onNotification, onReset }): () => void` (own mux socket; on close: reset titles and reconnect after 1 s, doubling to 30 s), `programToast(event, fallbackTitle, sequence)` → `{ id: "program:<handleId>:<n>", title, body?, type: "program" }`, `programToastHandle(id)`.
  - `ProgramRuntime` (mounted beside `NotificationRuntime` in `routes/_shell.tsx`): feeds the titles store; for a notification whose terminal is on screen it does nothing (user decision 2); otherwise it shows a toast through `operatorBridge.notifications.show` — the agent-alerts desktop path (UNUserNotificationCenter on a packaged macOS build, spec §5.3) — titled by the program's title, else the session's or shell's name, else "Terminal". Clicking a program toast opens its session (`useNavigateToSession`).
  - i18n keys: `terminal.programNotificationFallback` ("Terminal"), `terminal.programTitleAria` ("Terminal title: {{title}}") — the second is used in Task 9.

- [ ] **Step 1: Write the failing tests**

Create `frontend/src/renderer/lib/terminal-mux.programs.test.ts` with exactly this content:

```ts
import { afterEach, describe, expect, it } from "vitest";
import {
	appearanceFrame,
	createTerminalMux,
	createTerminalMuxPool,
	programsSubscribeFrame,
	programsUnsubscribeFrame,
} from "./terminal-mux";

class FakeSocket {
	static OPEN = 1;
	static instances: FakeSocket[] = [];
	readyState = 0;
	sent: string[] = [];
	private listeners: Record<string, ((ev: unknown) => void)[]> = {};
	constructor(public url: string) {
		FakeSocket.instances.push(this);
	}
	addEventListener(type: string, cb: (ev: unknown) => void) {
		(this.listeners[type] ??= []).push(cb);
	}
	send(frame: string) {
		this.sent.push(frame);
	}
	close() {}
	emitOpen() {
		this.readyState = FakeSocket.OPEN;
		this.listeners.open?.forEach((cb) => cb({}));
	}
	emitMessage(data: string) {
		this.listeners.message?.forEach((cb) => cb({ data }));
	}
	frames(): Array<Record<string, unknown>> {
		return this.sent.map((frame) => JSON.parse(frame) as Record<string, unknown>);
	}
}

const socketImpl = FakeSocket as unknown as typeof WebSocket;

afterEach(() => {
	FakeSocket.instances = [];
});

describe("program frames", () => {
	it("encodes an appearance frame for one terminal", () => {
		expect(
			JSON.parse(appearanceFrame("h1", { cellWidth: 16, cellHeight: 34, foreground: "#ffffff", background: "#1d2022" })),
		).toEqual({ ch: "terminal", type: "appearance", id: "h1", cellWidth: 16, cellHeight: 34, foreground: "#ffffff", background: "#1d2022" });
	});

	it("encodes the programs subscribe and unsubscribe frames", () => {
		expect(JSON.parse(programsSubscribeFrame())).toEqual({ ch: "programs", type: "subscribe" });
		expect(JSON.parse(programsUnsubscribeFrame())).toEqual({ ch: "programs", type: "unsubscribe" });
	});
});

describe("createTerminalMux programs channel", () => {
	it("subscribes once for the first listener and unsubscribes after the last", () => {
		const mux = createTerminalMux("ws://x/mux", socketImpl);
		const socket = FakeSocket.instances.at(-1)!;
		socket.emitOpen();
		const offTitle = mux.onProgramTitle!(() => undefined);
		const offNote = mux.onProgramNotification!(() => undefined);
		expect(socket.frames()).toEqual([{ ch: "programs", type: "subscribe" }]);
		offTitle();
		expect(socket.frames()).toHaveLength(1);
		offNote();
		offNote();
		expect(socket.frames()).toEqual([
			{ ch: "programs", type: "subscribe" },
			{ ch: "programs", type: "unsubscribe" },
		]);
	});

	it("routes title and notification frames with their terminal id", () => {
		const mux = createTerminalMux("ws://x/mux", socketImpl);
		const socket = FakeSocket.instances.at(-1)!;
		socket.emitOpen();
		const titles: Array<[string, string]> = [];
		const notes: Array<[string, { title: string; body: string }]> = [];
		mux.onProgramTitle!((id, title) => titles.push([id, title]));
		mux.onProgramNotification!((id, note) => notes.push([id, note]));
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "title", id: "h1", title: "Number list" }));
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "title", id: "h1" }));
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "notification", id: "h2", body: "hello" }));
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "title", title: "no id" }));
		expect(titles).toEqual([
			["h1", "Number list"],
			["h1", ""],
		]);
		expect(notes).toEqual([["h2", { title: "", body: "hello" }]]);
	});

	it("sends an appearance frame for a terminal", () => {
		const mux = createTerminalMux("ws://x/mux", socketImpl);
		const socket = FakeSocket.instances.at(-1)!;
		socket.emitOpen();
		mux.appearance!("h1", { cellWidth: 8, cellHeight: 17, foreground: "#ffffff", background: "#000000" });
		expect(socket.frames()).toEqual([
			{ ch: "terminal", type: "appearance", id: "h1", cellWidth: 8, cellHeight: 17, foreground: "#ffffff", background: "#000000" },
		]);
	});
});

describe("createTerminalMuxPool programs channel", () => {
	it("stops delivering program frames to a disposed lease and unsubscribes", () => {
		const pool = createTerminalMuxPool(() => createTerminalMux("ws://x/mux", socketImpl));
		const lease = pool.acquire();
		const socket = FakeSocket.instances.at(-1)!;
		socket.emitOpen();
		const titles: string[] = [];
		lease.onProgramTitle!((_id, title) => titles.push(title));
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "title", id: "h1", title: "one" }));
		lease.dispose();
		socket.emitMessage(JSON.stringify({ ch: "programs", type: "title", id: "h1", title: "two" }));
		expect(titles).toEqual(["one"]);
		pool.dispose();
	});
});
```

Create `frontend/src/renderer/lib/terminal-titles.test.tsx` with exactly this content:

```tsx
import { act, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
	clearTerminalTitles,
	setTerminalTitle,
	subscribeTerminalTitles,
	terminalTitle,
	terminalTitleListenerCount,
	useTerminalTitle,
} from "./terminal-titles";

afterEach(() => clearTerminalTitles());

function Title({ handleId }: { handleId?: string }) {
	return <span data-testid="title">{useTerminalTitle(handleId)}</span>;
}

describe("terminal titles", () => {
	it("stores a trimmed title per terminal and forgets an empty one", () => {
		setTerminalTitle("h1", "  Number list  ");
		expect(terminalTitle("h1")).toBe("Number list");
		setTerminalTitle("h1", "");
		expect(terminalTitle("h1")).toBe("");
		expect(terminalTitle(undefined)).toBe("");
	});

	it("notifies only when a title actually changes", () => {
		const listener = vi.fn();
		const off = subscribeTerminalTitles(listener);
		setTerminalTitle("h1", "a");
		setTerminalTitle("h1", "a");
		setTerminalTitle("h1", " a ");
		clearTerminalTitles();
		clearTerminalTitles();
		expect(listener).toHaveBeenCalledTimes(2);
		off();
		setTerminalTitle("h1", "b");
		expect(listener).toHaveBeenCalledTimes(2);
	});

	it("re-renders a component when its terminal's title changes and releases its listener on unmount", () => {
		const before = terminalTitleListenerCount();
		const { unmount } = render(<Title handleId="h1" />);
		expect(screen.getByTestId("title")).toHaveTextContent("");
		act(() => setTerminalTitle("h1", "Refactor"));
		expect(screen.getByTestId("title")).toHaveTextContent("Refactor");
		act(() => setTerminalTitle("h2", "Other"));
		expect(screen.getByTestId("title")).toHaveTextContent("Refactor");
		unmount();
		expect(terminalTitleListenerCount()).toBe(before);
	});
});
```

Create `frontend/src/renderer/lib/on-screen-terminals.test.ts` with exactly this content:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import { claimOnScreenTerminals, isTerminalOnScreen, terminalShownInAPane } from "./on-screen-terminals";

afterEach(() => vi.restoreAllMocks());

function focusedAndVisible(visible: DocumentVisibilityState, focused: boolean) {
	vi.spyOn(document, "visibilityState", "get").mockReturnValue(visible);
	vi.spyOn(document, "hasFocus").mockReturnValue(focused);
}

describe("on-screen terminals", () => {
	it("counts a terminal as shown while any claim holds it and forgets it on release", () => {
		const releaseA = claimOnScreenTerminals(["h1", "h2"]);
		const releaseB = claimOnScreenTerminals(["h2"]);
		expect(terminalShownInAPane("h1")).toBe(true);
		releaseA();
		expect(terminalShownInAPane("h1")).toBe(false);
		expect(terminalShownInAPane("h2")).toBe(true);
		releaseB();
		expect(terminalShownInAPane("h2")).toBe(false);
	});

	it("is on screen only in a visible, focused window", () => {
		const release = claimOnScreenTerminals(["h1"]);
		focusedAndVisible("visible", true);
		expect(isTerminalOnScreen("h1")).toBe(true);
		expect(isTerminalOnScreen("h9")).toBe(false);
		vi.restoreAllMocks();
		focusedAndVisible("visible", false);
		expect(isTerminalOnScreen("h1")).toBe(false);
		vi.restoreAllMocks();
		focusedAndVisible("hidden", true);
		expect(isTerminalOnScreen("h1")).toBe(false);
		release();
	});
});
```

Create `frontend/src/renderer/lib/program-feed.test.ts` with exactly this content:

```ts
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
	connectProgramFeed,
	PROGRAM_FEED_RETRY_BASE_MS,
	programToast,
	programToastHandle,
	type ProgramNotificationEvent,
} from "./program-feed";
import type { MuxConnectionState, ProgramNotification, TerminalMux } from "./terminal-mux";

type FakeProgramMux = {
	mux: TerminalMux;
	disposed: boolean;
	titleListeners: Set<(handleId: string, title: string) => void>;
	noteListeners: Set<(handleId: string, note: ProgramNotification) => void>;
	connection: Set<(state: MuxConnectionState) => void>;
};

function fakeMux(): FakeProgramMux {
	const fake: FakeProgramMux = {
		disposed: false,
		titleListeners: new Set(),
		noteListeners: new Set(),
		connection: new Set(),
		mux: {} as TerminalMux,
	};
	fake.mux = {
		open: () => undefined,
		sendInput: () => undefined,
		resize: () => undefined,
		close: () => undefined,
		ack: () => undefined,
		onData: () => () => undefined,
		onExit: () => () => undefined,
		onOpened: () => () => undefined,
		onError: () => () => undefined,
		onHealth: () => () => undefined,
		subscribeBlocks: () => undefined,
		unsubscribeBlocks: () => undefined,
		onBlock: () => () => undefined,
		onTerminalBlock: () => () => undefined,
		onProgramTitle: (listener) => {
			fake.titleListeners.add(listener);
			return () => fake.titleListeners.delete(listener);
		},
		onProgramNotification: (listener) => {
			fake.noteListeners.add(listener);
			return () => fake.noteListeners.delete(listener);
		},
		onConnectionChange: (listener) => {
			fake.connection.add(listener);
			return () => fake.connection.delete(listener);
		},
		dispose: () => {
			fake.disposed = true;
		},
	};
	return fake;
}

function handlers() {
	return { onTitle: vi.fn(), onNotification: vi.fn(), onReset: vi.fn() };
}

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe("connectProgramFeed", () => {
	it("forwards titles and notifications with their terminal id", () => {
		const muxes: FakeProgramMux[] = [];
		const h = handlers();
		const stop = connectProgramFeed(() => {
			const fake = fakeMux();
			muxes.push(fake);
			return fake.mux;
		}, h);
		muxes[0].titleListeners.forEach((listener) => listener("h1", "Number list"));
		muxes[0].noteListeners.forEach((listener) => listener("h1", { title: "", body: "hello" }));
		expect(h.onTitle).toHaveBeenCalledWith("h1", "Number list");
		expect(h.onNotification).toHaveBeenCalledWith({ handleId: "h1", title: "", body: "hello" });
		stop();
	});

	it("resets and reconnects with backoff after the socket closes", () => {
		const muxes: FakeProgramMux[] = [];
		const h = handlers();
		const stop = connectProgramFeed(() => {
			const fake = fakeMux();
			muxes.push(fake);
			return fake.mux;
		}, h);
		muxes[0].connection.forEach((listener) => listener("closed"));
		expect(h.onReset).toHaveBeenCalledTimes(1);
		expect(muxes[0].disposed).toBe(true);
		expect(muxes[0].titleListeners.size).toBe(0);
		expect(muxes).toHaveLength(1);
		vi.advanceTimersByTime(PROGRAM_FEED_RETRY_BASE_MS);
		expect(muxes).toHaveLength(2);
		muxes[1].connection.forEach((listener) => listener("closed"));
		vi.advanceTimersByTime(PROGRAM_FEED_RETRY_BASE_MS);
		expect(muxes).toHaveLength(2);
		vi.advanceTimersByTime(PROGRAM_FEED_RETRY_BASE_MS);
		expect(muxes).toHaveLength(3);
		stop();
	});

	it("releases every listener, disposes the socket and cancels a pending retry when stopped", () => {
		const muxes: FakeProgramMux[] = [];
		const h = handlers();
		const stop = connectProgramFeed(() => {
			const fake = fakeMux();
			muxes.push(fake);
			return fake.mux;
		}, h);
		const first = muxes[0];
		stop();
		expect(first.disposed).toBe(true);
		expect(first.titleListeners.size).toBe(0);
		expect(first.noteListeners.size).toBe(0);
		expect(first.connection.size).toBe(0);
		expect(h.onReset).toHaveBeenCalledTimes(1);

		const again = handlers();
		const stopAgain = connectProgramFeed(() => {
			const fake = fakeMux();
			muxes.push(fake);
			return fake.mux;
		}, again);
		muxes[1].connection.forEach((listener) => listener("closed"));
		stopAgain();
		vi.advanceTimersByTime(PROGRAM_FEED_RETRY_BASE_MS * 60);
		expect(muxes).toHaveLength(2);
	});
});

describe("program toasts", () => {
	const event = (overrides: Partial<ProgramNotificationEvent> = {}): ProgramNotificationEvent => ({
		handleId: "h1",
		title: "",
		body: "hello",
		...overrides,
	});

	it("uses the program's title, else the fallback, and drops an empty body", () => {
		expect(programToast(event({ title: "Build" }), "fix the tests", 1)).toEqual({ id: "program:h1:1", title: "Build", body: "hello", type: "program" });
		expect(programToast(event(), "fix the tests", 2)).toEqual({ id: "program:h1:2", title: "fix the tests", body: "hello", type: "program" });
		expect(programToast(event({ title: "Done", body: "  " }), "x", 3)).toEqual({ id: "program:h1:3", title: "Done", type: "program" });
	});

	it("reads the terminal id back out of a program toast id only", () => {
		expect(programToastHandle("program:h1:7")).toBe("h1");
		expect(programToastHandle("program:shellterm-ab:cd:2")).toBe("shellterm-ab:cd");
		expect(programToastHandle("ntf_1")).toBeNull();
		expect(programToastHandle("program:")).toBeNull();
	});
});
```

Create `frontend/src/renderer/components/ProgramRuntime.test.tsx` with exactly this content:

```tsx
import { act, render } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { MuxConnectionState, ProgramNotification, TerminalMux } from "../lib/terminal-mux";
import type { WorkspaceSession, WorkspaceSummary } from "../types/workspace";

const { navigateMock, showMock, clickListeners } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	showMock: vi.fn(),
	clickListeners: new Set<(id: string) => void>(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));

vi.mock("../lib/bridge", () => ({
	operatorBridge: {
		notifications: {
			show: showMock,
			onClick: (listener: (id: string) => void) => {
				clickListeners.add(listener);
				return () => clickListeners.delete(listener);
			},
		},
	},
}));

const session: WorkspaceSession = {
	id: "sess-1",
	terminalHandleId: "handle-1",
	workspaceId: "proj-1",
	workspaceName: "demo",
	title: "fix the tests",
	provider: "claude-code",
	branch: "main",
	status: "working",
	updatedAt: "now",
	prs: [],
};
const workspaces: WorkspaceSummary[] = [{ id: "proj-1", name: "demo", path: "/p", sessions: [session] }];

vi.mock("../hooks/useWorkspaceQuery", () => ({ useWorkspaceQuery: () => ({ data: workspaces }) }));
vi.mock("../hooks/useShellTerminals", () => ({
	useShellTerminals: () => ({
		data: [{ handleId: "shell-1", workingDir: "/p", title: "zsh", createdAt: "now" }],
	}),
}));

import { claimOnScreenTerminals } from "../lib/on-screen-terminals";
import { clearTerminalTitles, terminalTitle } from "../lib/terminal-titles";
import { ProgramRuntime, programTargets } from "./ProgramRuntime";

type Fake = {
	mux: TerminalMux;
	disposed: boolean;
	titles: Set<(handleId: string, title: string) => void>;
	notes: Set<(handleId: string, note: ProgramNotification) => void>;
	connection: Set<(state: MuxConnectionState) => void>;
};

function fakeMux(): Fake {
	const fake: Fake = { disposed: false, titles: new Set(), notes: new Set(), connection: new Set(), mux: {} as TerminalMux };
	fake.mux = {
		open: () => undefined,
		sendInput: () => undefined,
		resize: () => undefined,
		close: () => undefined,
		ack: () => undefined,
		onData: () => () => undefined,
		onExit: () => () => undefined,
		onOpened: () => () => undefined,
		onError: () => () => undefined,
		onHealth: () => () => undefined,
		subscribeBlocks: () => undefined,
		unsubscribeBlocks: () => undefined,
		onBlock: () => () => undefined,
		onTerminalBlock: () => () => undefined,
		onProgramTitle: (listener) => {
			fake.titles.add(listener);
			return () => fake.titles.delete(listener);
		},
		onProgramNotification: (listener) => {
			fake.notes.add(listener);
			return () => fake.notes.delete(listener);
		},
		onConnectionChange: (listener) => {
			fake.connection.add(listener);
			return () => fake.connection.delete(listener);
		},
		dispose: () => {
			fake.disposed = true;
		},
	};
	return fake;
}

function mount() {
	const fakes: Fake[] = [];
	const createMux = () => {
		const fake = fakeMux();
		fakes.push(fake);
		return fake.mux;
	};
	const view = render(<ProgramRuntime createMux={createMux} />);
	return { fakes, ...view };
}

beforeEach(() => {
	showMock.mockReset().mockResolvedValue(undefined);
	navigateMock.mockReset();
	vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible");
	vi.spyOn(document, "hasFocus").mockReturnValue(true);
});

afterEach(() => {
	clearTerminalTitles();
	vi.restoreAllMocks();
});

describe("programTargets", () => {
	it("labels a session terminal with its session and a shell with its tab title", () => {
		const targets = programTargets(workspaces, [{ handleId: "shell-1", sessionId: "sess-1", projectId: "proj-1", workingDir: "/p", title: "zsh", createdAt: "now" }]);
		expect(targets.get("handle-1")).toEqual({ label: "fix the tests", sessionId: "sess-1", projectId: "proj-1" });
		expect(targets.get("shell-1")).toEqual({ label: "zsh", sessionId: "sess-1", projectId: "proj-1" });
	});
});

describe("ProgramRuntime", () => {
	it("keeps the title store in step with the daemon's program feed", () => {
		const { fakes } = mount();
		act(() => fakes[0].titles.forEach((listener) => listener("handle-1", "Number list 1 to 3000")));
		expect(terminalTitle("handle-1")).toBe("Number list 1 to 3000");
		act(() => fakes[0].titles.forEach((listener) => listener("handle-1", "")));
		expect(terminalTitle("handle-1")).toBe("");
	});

	it("toasts a program notification for a terminal that is not on screen, titled by its session", () => {
		const { fakes } = mount();
		act(() => fakes[0].notes.forEach((listener) => listener("handle-1", { title: "", body: "hello" })));
		expect(showMock).toHaveBeenCalledWith({ id: "program:handle-1:1", title: "fix the tests", body: "hello", type: "program" });
	});

	it("ignores a program notification while its terminal is on screen in a focused window", () => {
		const release = claimOnScreenTerminals(["handle-1"]);
		const { fakes } = mount();
		act(() => fakes[0].notes.forEach((listener) => listener("handle-1", { title: "", body: "hello" })));
		expect(showMock).not.toHaveBeenCalled();
		vi.spyOn(document, "hasFocus").mockReturnValue(false);
		act(() => fakes[0].notes.forEach((listener) => listener("handle-1", { title: "", body: "again" })));
		expect(showMock).toHaveBeenCalledTimes(1);
		release();
	});

	it("falls back to a generic title for a terminal it cannot name", () => {
		const { fakes } = mount();
		act(() => fakes[0].notes.forEach((listener) => listener("unknown", { title: "", body: "hi" })));
		expect(showMock).toHaveBeenCalledWith(expect.objectContaining({ title: "Terminal", body: "hi" }));
	});

	it("opens the session when its program toast is clicked", () => {
		mount();
		act(() => clickListeners.forEach((listener) => listener("program:handle-1:4")));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "proj-1", sessionId: "sess-1" },
		});
		act(() => clickListeners.forEach((listener) => listener("ntf_other")));
		expect(navigateMock).toHaveBeenCalledTimes(1);
	});

	it("closes the feed and removes its click listener when unmounted", () => {
		const { fakes, unmount } = mount();
		const clicksBefore = clickListeners.size;
		unmount();
		expect(fakes[0].disposed).toBe(true);
		expect(fakes[0].titles.size).toBe(0);
		expect(fakes[0].notes.size).toBe(0);
		expect(clickListeners.size).toBe(clicksBefore - 1);
	});
});
```

Create `frontend/src/renderer/components/split/SplitWorkspaceOnScreenTerminals.test.tsx` with exactly this content:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { terminalShownInAPane } from "../../lib/on-screen-terminals";
import { EMPTY_LAYOUT } from "../../lib/split-layout";
import { useSplitLayoutStore } from "../../stores/split-layout-store";
import type { WorkspaceSession, WorkspaceSummary } from "../../types/workspace";
import { SplitWorkspace } from "./SplitWorkspace";

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => vi.fn() }));
vi.mock("../../lib/shell-context", () => ({ useShell: () => ({ daemonStatus: { state: "ready" } }) }));
vi.mock("../../hooks/useShellTerminals", () => ({
	useShellTerminals: () => ({
		data: [{ handleId: "shell-x", sessionId: "x", workingDir: "/p1", title: "zsh", createdAt: "now" }],
		isSuccess: true,
	}),
	useCloseShellTerminal: () => ({ mutate: vi.fn() }),
	useOpenShellTerminal: () => ({ mutate: vi.fn(), isPending: false }),
	useRenameShellTerminal: () => ({ mutate: vi.fn() }),
}));
vi.mock("../../hooks/useSessionReviewer", () => ({
	useSessionReviewer: () => ({ reviewer: undefined, settled: true }),
}));
vi.mock("./SplitPane", () => ({ SplitPane: () => <div /> }));
vi.mock("../ui/resizable", () => ({
	ResizablePanelGroup: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
	ResizablePanel: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
	ResizableHandle: () => <div />,
}));
vi.mock("../../lib/bridge", () => ({
	operatorBridge: {
		app: {
			onCloseShellTerminalShortcut: () => () => undefined,
			setCloseShellTerminalShortcutEnabled: () => undefined,
			onPreviousTabShortcut: () => () => undefined,
			onNextTabShortcut: () => () => undefined,
		},
	},
}));

function makeSession(id: string): WorkspaceSession {
	return {
		id,
		terminalHandleId: `handle-${id}`,
		workspaceId: "proj-1",
		workspaceName: "proj-1",
		title: `session:${id}`,
		provider: "claude-code",
		branch: `opr/${id}`,
		status: "working",
		updatedAt: "2026-06-10T00:00:00Z",
		prs: [],
	};
}

const workspaces: WorkspaceSummary[] = [
	{ id: "proj-1", name: "proj-1", path: "/p1", sessions: [makeSession("x"), makeSession("y")] },
];

vi.mock("../../hooks/useWorkspaceQuery", () => ({
	useWorkspaceQuery: () => ({ data: workspaces, isSuccess: true }),
}));

describe("SplitWorkspace on-screen terminals", () => {
	beforeEach(() => {
		useSplitLayoutStore.setState({ layout: EMPTY_LAYOUT, dismissedReviewers: [] });
		window.localStorage.clear();
	});

	it("claims the terminal of every pane's active tab, not a background tab, and releases them on unmount", () => {
		useSplitLayoutStore.getState().openTab({ kind: "session", sessionId: "x" });
		const paneId = useSplitLayoutStore.getState().layout.focusedPaneId as string;
		useSplitLayoutStore.getState().splitPane({ kind: "shell", handleId: "shell-x", sessionId: "x" }, paneId, "right");
		useSplitLayoutStore.getState().insertTabAfter({ kind: "session", sessionId: "y" }, { kind: "shell", handleId: "shell-x", sessionId: "x" });

		const { unmount } = render(
			<QueryClientProvider client={new QueryClient()}>
				<SplitWorkspace routeSessionId="x" />
			</QueryClientProvider>,
		);

		expect(terminalShownInAPane("handle-x")).toBe(true);
		expect(terminalShownInAPane("shell-x")).toBe(true);
		expect(terminalShownInAPane("handle-y")).toBe(false);
		unmount();
		expect(terminalShownInAPane("handle-x")).toBe(false);
		expect(terminalShownInAPane("shell-x")).toBe(false);
	});
});
```

Create `frontend/src/renderer/components/ShellTerminalsView.onscreen.test.tsx` with exactly this content:

```tsx
import { render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { terminalShownInAPane } from "../lib/on-screen-terminals";
import { useUiStore } from "../stores/ui-store";
import { ShellTerminalsView } from "./ShellTerminalsView";

vi.mock("../hooks/useShellTerminals", () => ({
	useCloseShellTerminal: () => ({ mutate: vi.fn() }),
	useRenameShellTerminal: () => ({ mutate: vi.fn() }),
	useShellTerminals: () => ({ data: [{ handleId: "shell-a", workingDir: "/tmp", title: "zsh", createdAt: "now" }] }),
}));

vi.mock("../lib/shell-context", () => ({
	useShell: () => ({ daemonStatus: { state: "ready" } }),
}));

vi.mock("./TerminalPane", () => ({ TerminalPane: () => <div>terminal body</div> }));

describe("ShellTerminalsView on-screen terminal", () => {
	it("claims the active shell while shown and releases it on unmount", () => {
		useUiStore.getState().setActiveShellTerminal("shell-a");
		const { unmount } = render(<ShellTerminalsView />);
		expect(terminalShownInAPane("shell-a")).toBe(true);
		unmount();
		expect(terminalShownInAPane("shell-a")).toBe(false);
	});
});
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx vitest run --config vite.renderer.config.ts src/renderer/lib/terminal-mux.programs src/renderer/lib/terminal-titles src/renderer/lib/on-screen src/renderer/lib/program-feed src/renderer/components/ProgramRuntime src/renderer/components/split/SplitWorkspaceOnScreen src/renderer/components/ShellTerminalsView.onscreen 2>&1 | tail -4
```
Expected: all seven files fail (missing modules / exports).

- [ ] **Step 3: Implement**

Create `frontend/src/renderer/lib/terminal-titles.ts` with exactly this content:

```ts
import { useSyncExternalStore } from "react";

const titles = new Map<string, string>();
const listeners = new Set<() => void>();

function notify(): void {
	for (const listener of [...listeners]) listener();
}

export function setTerminalTitle(handleId: string, title: string): void {
	const next = title.trim();
	if ((titles.get(handleId) ?? "") === next) return;
	if (next) titles.set(handleId, next);
	else titles.delete(handleId);
	notify();
}

export function clearTerminalTitles(): void {
	if (titles.size === 0) return;
	titles.clear();
	notify();
}

export function terminalTitle(handleId: string | undefined): string {
	return handleId ? (titles.get(handleId) ?? "") : "";
}

export function terminalTitleListenerCount(): number {
	return listeners.size;
}

export function subscribeTerminalTitles(listener: () => void): () => void {
	listeners.add(listener);
	return () => {
		listeners.delete(listener);
	};
}

export function useTerminalTitle(handleId: string | undefined): string {
	return useSyncExternalStore(
		subscribeTerminalTitles,
		() => terminalTitle(handleId),
		() => "",
	);
}
```

Create `frontend/src/renderer/lib/on-screen-terminals.ts` with exactly this content:

```ts
const claims = new Map<symbol, ReadonlySet<string>>();

export function claimOnScreenTerminals(handleIds: Iterable<string>): () => void {
	const key = Symbol("on-screen-terminals");
	claims.set(key, new Set(handleIds));
	return () => {
		claims.delete(key);
	};
}

export function terminalShownInAPane(handleId: string): boolean {
	for (const handles of claims.values()) {
		if (handles.has(handleId)) return true;
	}
	return false;
}

export function isTerminalOnScreen(handleId: string): boolean {
	if (typeof document === "undefined") return false;
	if (document.visibilityState !== "visible" || !document.hasFocus()) return false;
	return terminalShownInAPane(handleId);
}
```

Create `frontend/src/renderer/lib/program-feed.ts` with exactly this content:

```ts
import type { ProgramNotification, TerminalMux } from "./terminal-mux";

export const PROGRAM_FEED_RETRY_BASE_MS = 1_000;
export const PROGRAM_FEED_RETRY_MAX_MS = 30_000;
export const PROGRAM_TOAST_PREFIX = "program:";

export type ProgramNotificationEvent = Readonly<{ handleId: string } & ProgramNotification>;

export type ProgramFeedHandlers = Readonly<{
	onTitle: (handleId: string, title: string) => void;
	onNotification: (event: ProgramNotificationEvent) => void;
	onReset: () => void;
}>;

export type ProgramToast = Readonly<{ id: string; title: string; body?: string; type: "program" }>;

export function connectProgramFeed(createMux: () => TerminalMux, handlers: ProgramFeedHandlers): () => void {
	let disposed = false;
	let attempts = 0;
	let retryTimer: ReturnType<typeof setTimeout> | undefined;
	let current: { mux: TerminalMux; release: Array<() => void> } | null = null;

	const teardown = () => {
		const active = current;
		if (!active) return;
		current = null;
		for (const release of active.release) release();
		active.mux.dispose();
	};

	const connect = () => {
		if (disposed) return;
		const mux = createMux();
		const release: Array<() => void> = [];
		current = { mux, release };
		const offTitle = mux.onProgramTitle?.((handleId, title) => handlers.onTitle(handleId, title));
		if (offTitle) release.push(offTitle);
		const offNotification = mux.onProgramNotification?.((handleId, notification) =>
			handlers.onNotification({ handleId, ...notification }),
		);
		if (offNotification) release.push(offNotification);
		release.push(
			mux.onConnectionChange((state) => {
				if (state === "open") {
					attempts = 0;
					return;
				}
				if (current?.mux !== mux) return;
				teardown();
				handlers.onReset();
				const delay = Math.min(PROGRAM_FEED_RETRY_BASE_MS * 2 ** attempts, PROGRAM_FEED_RETRY_MAX_MS);
				attempts += 1;
				retryTimer = setTimeout(() => {
					retryTimer = undefined;
					connect();
				}, delay);
			}),
		);
	};

	connect();
	return () => {
		disposed = true;
		if (retryTimer) clearTimeout(retryTimer);
		retryTimer = undefined;
		teardown();
		handlers.onReset();
	};
}

export function programToast(event: ProgramNotificationEvent, fallbackTitle: string, sequence: number): ProgramToast {
	const title = event.title.trim() || fallbackTitle;
	const body = event.body.trim();
	return {
		id: `${PROGRAM_TOAST_PREFIX}${event.handleId}:${sequence}`,
		title,
		...(body ? { body } : {}),
		type: "program",
	};
}

export function programToastHandle(id: string): string | null {
	if (!id.startsWith(PROGRAM_TOAST_PREFIX)) return null;
	const rest = id.slice(PROGRAM_TOAST_PREFIX.length);
	const cut = rest.lastIndexOf(":");
	return cut > 0 ? rest.slice(0, cut) : null;
}
```

Create `frontend/src/renderer/components/ProgramRuntime.tsx` with exactly this content:

```tsx
import { useEffect, useMemo, useRef } from "react";
import { useTranslation } from "react-i18next";
import { useShellTerminals, type ShellTerminal } from "../hooks/useShellTerminals";
import { useWorkspaceQuery } from "../hooks/useWorkspaceQuery";
import { getApiBaseUrl } from "../lib/api-client";
import { operatorBridge } from "../lib/bridge";
import { useNavigateToSession } from "../lib/navigate-to-session";
import { isTerminalOnScreen } from "../lib/on-screen-terminals";
import { connectProgramFeed, programToast, programToastHandle } from "../lib/program-feed";
import { createTerminalMux, muxUrlFromApiBase, type TerminalMux } from "../lib/terminal-mux";
import { clearTerminalTitles, setTerminalTitle } from "../lib/terminal-titles";
import type { WorkspaceSummary } from "../types/workspace";

export type ProgramTarget = Readonly<{ label: string; sessionId?: string; projectId?: string }>;

export function programTargets(
	workspaces: readonly WorkspaceSummary[] | undefined,
	shells: readonly ShellTerminal[] | undefined,
): Map<string, ProgramTarget> {
	const targets = new Map<string, ProgramTarget>();
	for (const workspace of workspaces ?? []) {
		for (const session of workspace.sessions) {
			if (!session.terminalHandleId) continue;
			targets.set(session.terminalHandleId, {
				label: session.title,
				sessionId: session.id,
				projectId: session.workspaceId,
			});
		}
	}
	for (const shell of shells ?? []) {
		targets.set(shell.handleId, { label: shell.title, sessionId: shell.sessionId, projectId: shell.projectId });
	}
	return targets;
}

function defaultCreateMux(): TerminalMux {
	return createTerminalMux(muxUrlFromApiBase(getApiBaseUrl()));
}

export function ProgramRuntime({ createMux = defaultCreateMux }: { createMux?: () => TerminalMux }) {
	const { t } = useTranslation();
	const { data: workspaces } = useWorkspaceQuery();
	const { data: shells } = useShellTerminals();
	const navigateToSession = useNavigateToSession();
	const targets = useMemo(() => programTargets(workspaces, shells), [workspaces, shells]);
	const targetsRef = useRef(targets);
	targetsRef.current = targets;
	const translateRef = useRef(t);
	translateRef.current = t;
	const createMuxRef = useRef(createMux);

	useEffect(() => {
		let sequence = 0;
		return connectProgramFeed(() => createMuxRef.current(), {
			onTitle: setTerminalTitle,
			onReset: clearTerminalTitles,
			onNotification: (event) => {
				if (isTerminalOnScreen(event.handleId)) return;
				sequence += 1;
				const fallback = targetsRef.current.get(event.handleId)?.label || translateRef.current("terminal.programNotificationFallback");
				void operatorBridge.notifications.show(programToast(event, fallback, sequence)).catch((error: unknown) => {
					console.warn("Unable to show program notification", error);
				});
			},
		});
	}, []);

	useEffect(
		() =>
			operatorBridge.notifications.onClick((id) => {
				const handleId = programToastHandle(id);
				if (!handleId) return;
				const target = targetsRef.current.get(handleId);
				if (target?.sessionId) navigateToSession(target.projectId, target.sessionId);
			}),
		[navigateToSession],
	);

	return null;
}
```

Edit 1 of 10 in `frontend/src/renderer/lib/terminal-mux.ts` — find this text (starts at line 12 of the unmodified file):

```ts
//   ch "blocks"   — normalized session block events
//     client → subscribe{id} | unsubscribe{id}
//     server → block{id,block}
//
// The renderer connects directly to the loopback daemon (same host/port as the
// REST API, path `/mux`); it is not proxied through the shell.
```

replace it with:

```ts
//   ch "blocks"   — normalized session block events
//     client → subscribe{id} | unsubscribe{id}
//     server → block{id,block}
//   ch "programs" — titles and notifications the programs in every terminal send
//     client → subscribe | unsubscribe
//     server → title{id,title} | notification{id,title,body}
//
// The renderer connects directly to the loopback daemon (same host/port as the
// REST API, path `/mux`); it is not proxied through the shell.
```

Edit 2 of 10 in `frontend/src/renderer/lib/terminal-mux.ts` — find this text (starts at line 30 of the unmodified file):

```ts
	block?: unknown;
	blockType?: string;
	terminalBlock?: unknown;
};

export type TerminalBlockFrame = {
	sourceId: string;
	sessionId?: string;
```

replace it with:

```ts
	block?: unknown;
	blockType?: string;
	terminalBlock?: unknown;
	title?: string;
	body?: string;
};

export type TerminalAppearance = Readonly<{
	cellWidth: number;
	cellHeight: number;
	foreground: string;
	background: string;
}>;

export type ProgramNotification = Readonly<{ title: string; body: string }>;

export type TerminalBlockFrame = {
	sourceId: string;
	sessionId?: string;
```

Edit 3 of 10 in `frontend/src/renderer/lib/terminal-mux.ts` — find this text (starts at line 110 of the unmodified file):

```ts
	return JSON.stringify({ ch: "blocks", type: "unsubscribe", id: handleId, blockType: "terminal_block" });
}

function pingFrame(): string {
	return JSON.stringify({ ch: "system", type: "ping" });
}
```

replace it with:

```ts
	return JSON.stringify({ ch: "blocks", type: "unsubscribe", id: handleId, blockType: "terminal_block" });
}

export function appearanceFrame(id: string, appearance: TerminalAppearance): string {
	return JSON.stringify({ ch: "terminal", type: "appearance", id, ...appearance });
}

export function programsSubscribeFrame(): string {
	return JSON.stringify({ ch: "programs", type: "subscribe" });
}

export function programsUnsubscribeFrame(): string {
	return JSON.stringify({ ch: "programs", type: "unsubscribe" });
}

function pingFrame(): string {
	return JSON.stringify({ ch: "system", type: "ping" });
}
```

Edit 4 of 10 in `frontend/src/renderer/lib/terminal-mux.ts` — find this text (starts at line 137 of the unmodified file):

```ts
type HealthListener = (health: TerminalHealth) => void;
type BlockListener = (block: BlockEventView) => void;
type TerminalBlockListener = (block: TerminalBlockFrame) => void;

export type MuxConnectionState = "open" | "closed";
type ConnectionListener = (state: MuxConnectionState) => void;
```

replace it with:

```ts
type HealthListener = (health: TerminalHealth) => void;
type BlockListener = (block: BlockEventView) => void;
type TerminalBlockListener = (block: TerminalBlockFrame) => void;
type ProgramTitleListener = (handleId: string, title: string) => void;
type ProgramNotificationListener = (handleId: string, notification: ProgramNotification) => void;

export type MuxConnectionState = "open" | "closed";
type ConnectionListener = (state: MuxConnectionState) => void;
```

Edit 5 of 10 in `frontend/src/renderer/lib/terminal-mux.ts` — find this text (starts at line 168 of the unmodified file):

```ts
	/** Server `block` frames for one session id. */
	onBlock: (sessionId: string, listener: BlockListener) => () => void;
	onTerminalBlock: (handleId: string, listener: TerminalBlockListener) => () => void;
	/** Socket-level state: "open" on connect, "closed" on close or socket error. */
	onConnectionChange: (listener: ConnectionListener) => () => void;
	/** Close the socket and drop all listeners. */
```

replace it with:

```ts
	/** Server `block` frames for one session id. */
	onBlock: (sessionId: string, listener: BlockListener) => () => void;
	onTerminalBlock: (handleId: string, listener: TerminalBlockListener) => () => void;
	appearance?: (id: string, appearance: TerminalAppearance) => void;
	onProgramTitle?: (listener: ProgramTitleListener) => () => void;
	onProgramNotification?: (listener: ProgramNotificationListener) => () => void;
	/** Socket-level state: "open" on connect, "closed" on close or socket error. */
	onConnectionChange: (listener: ConnectionListener) => () => void;
	/** Close the socket and drop all listeners. */
```

Edit 6 of 10 in `frontend/src/renderer/lib/terminal-mux.ts` — find this text (starts at line 210 of the unmodified file):

```ts
	const healthListeners = new Map<string, Set<HealthListener>>();
	const blockListeners = new Map<string, Set<BlockListener>>();
	const terminalBlockListeners = new Map<string, Set<TerminalBlockListener>>();
	const connectionListeners = new Set<ConnectionListener>();
	let connectionState: MuxConnectionState | undefined;
	let pingTimer: ReturnType<typeof setInterval> | undefined;
```

replace it with:

```ts
	const healthListeners = new Map<string, Set<HealthListener>>();
	const blockListeners = new Map<string, Set<BlockListener>>();
	const terminalBlockListeners = new Map<string, Set<TerminalBlockListener>>();
	const programTitleListeners = new Set<ProgramTitleListener>();
	const programNotificationListeners = new Set<ProgramNotificationListener>();
	const connectionListeners = new Set<ConnectionListener>();
	let connectionState: MuxConnectionState | undefined;
	let pingTimer: ReturnType<typeof setInterval> | undefined;
```

Edit 7 of 10 in `frontend/src/renderer/lib/terminal-mux.ts` — find this text (starts at line 274 of the unmodified file):

```ts
			blockListeners.get(frame.id)?.forEach((listener) => listener(block as BlockEventView));
			return;
		}
		if (frame.ch !== "terminal") return;
		if (frame.type === "error") {
			const message = frame.error ?? "unknown terminal error";
```

replace it with:

```ts
			blockListeners.get(frame.id)?.forEach((listener) => listener(block as BlockEventView));
			return;
		}
		if (frame.ch === "programs") {
			if (frame.id === undefined) return;
			const handleId = frame.id;
			if (frame.type === "title") {
				const title = frame.title ?? "";
				programTitleListeners.forEach((listener) => listener(handleId, title));
			} else if (frame.type === "notification") {
				const notification = { title: frame.title ?? "", body: frame.body ?? "" };
				programNotificationListeners.forEach((listener) => listener(handleId, notification));
			}
			return;
		}
		if (frame.ch !== "terminal") return;
		if (frame.type === "error") {
			const message = frame.error ?? "unknown terminal error";
```

Edit 8 of 10 in `frontend/src/renderer/lib/terminal-mux.ts` — find this text (starts at line 308 of the unmodified file):

```ts
		healthListeners.clear();
		blockListeners.clear();
		terminalBlockListeners.clear();
		connectionListeners.clear();
		try {
			socket.close();
```

replace it with:

```ts
		healthListeners.clear();
		blockListeners.clear();
		terminalBlockListeners.clear();
		programTitleListeners.clear();
		programNotificationListeners.clear();
		connectionListeners.clear();
		try {
			socket.close();
```

Edit 9 of 10 in `frontend/src/renderer/lib/terminal-mux.ts` — find this text (starts at line 316 of the unmodified file):

```ts
		}
	};

	return {
		open: (id, cols, rows, history) => {
			send(openFrame(id, cols, rows, history));
		},
		sendInput: (id, input) => {
			const bytes = encoder.encode(input);
			send(dataFrame(id, bytes));
```

replace it with:

```ts
		}
	};

	const programListenerCount = () => programTitleListeners.size + programNotificationListeners.size;
	const addProgramListener = <T>(set: Set<T>, listener: T): (() => void) => {
		if (programListenerCount() === 0) send(programsSubscribeFrame());
		set.add(listener);
		return () => {
			if (!set.delete(listener) || programListenerCount() > 0) return;
			send(programsUnsubscribeFrame());
		};
	};

	return {
		open: (id, cols, rows, history) => {
			send(openFrame(id, cols, rows, history));
		},
		appearance: (id, appearance) => {
			send(appearanceFrame(id, appearance));
		},
		onProgramTitle: (listener) => addProgramListener(programTitleListeners, listener),
		onProgramNotification: (listener) => addProgramListener(programNotificationListeners, listener),
		sendInput: (id, input) => {
			const bytes = encoder.encode(input);
			send(dataFrame(id, bytes));
```

Edit 10 of 10 in `frontend/src/renderer/lib/terminal-mux.ts` — find this text (starts at line 447 of the unmodified file):

```ts
			open: (id, cols, rows, history) => {
				if (!released && !connection.closed && !connection.disposed) connection.mux.open(id, cols, rows, history);
			},
			sendInput: (id, input) => {
				if (!released && !connection.closed && !connection.disposed) connection.mux.sendInput(id, input);
			},
```

replace it with:

```ts
			open: (id, cols, rows, history) => {
				if (!released && !connection.closed && !connection.disposed) connection.mux.open(id, cols, rows, history);
			},
			appearance: (id, appearance) => {
				if (!released && !connection.closed && !connection.disposed) connection.mux.appearance?.(id, appearance);
			},
			onProgramTitle: (listener) =>
				subscribe(() => connection.mux.onProgramTitle?.(listener) ?? (() => undefined)),
			onProgramNotification: (listener) =>
				subscribe(() => connection.mux.onProgramNotification?.(listener) ?? (() => undefined)),
			sendInput: (id, input) => {
				if (!released && !connection.closed && !connection.disposed) connection.mux.sendInput(id, input);
			},
```

Edit 1 of 2 in `frontend/src/renderer/routes/_shell.tsx` — find this text (starts at line 6 of the unmodified file):

```tsx
import { CenterPanelShell } from "../components/CenterPanelShell";
import { DaemonFailureBanner } from "../components/DaemonFailureBanner";
import { NotificationCenter, NotificationRuntime } from "../components/NotificationCenter";
import { TrayRuntime } from "../components/TrayRuntime";
import { GlobalNewTaskDialog } from "../components/GlobalNewTaskDialog";
import { SettingsDialog } from "../components/SettingsDialog";
```

replace it with:

```tsx
import { CenterPanelShell } from "../components/CenterPanelShell";
import { DaemonFailureBanner } from "../components/DaemonFailureBanner";
import { NotificationCenter, NotificationRuntime } from "../components/NotificationCenter";
import { ProgramRuntime } from "../components/ProgramRuntime";
import { TrayRuntime } from "../components/TrayRuntime";
import { GlobalNewTaskDialog } from "../components/GlobalNewTaskDialog";
import { SettingsDialog } from "../components/SettingsDialog";
```

Edit 2 of 2 in `frontend/src/renderer/routes/_shell.tsx` — find this text (starts at line 550 of the unmodified file):

```tsx
				    ready daemon because the answer is read from shared settings. */}
				{daemonStatus.state === "ready" && <UpdateOptInPrompt />}
				<NotificationRuntime />
				<TrayRuntime />
				<GlobalNewTaskDialog />
				<SettingsDialog />
```

replace it with:

```tsx
				    ready daemon because the answer is read from shared settings. */}
				{daemonStatus.state === "ready" && <UpdateOptInPrompt />}
				<NotificationRuntime />
				<ProgramRuntime />
				<TrayRuntime />
				<GlobalNewTaskDialog />
				<SettingsDialog />
```

Edit 1 of 1 in `frontend/src/renderer/test/shell-new-session-shortcut.test.tsx` — find this text (starts at line 151 of the unmodified file):

```tsx
}));

vi.mock("../components/NotificationCenter", () => ({ NotificationRuntime: () => null, NotificationCenter: () => null }));
vi.mock("../hooks/useCommandPaletteEnabled", () => ({ useCommandPaletteEnabled: () => true }));
vi.mock("../components/CommandPalette", () => ({ CommandPalette: () => null }));
vi.mock("../components/OrchestratorReplacementDialog", () => ({ OrchestratorReplacementDialog: () => null }));
```

replace it with:

```tsx
}));

vi.mock("../components/NotificationCenter", () => ({ NotificationRuntime: () => null, NotificationCenter: () => null }));
vi.mock("../components/ProgramRuntime", () => ({ ProgramRuntime: () => null }));
vi.mock("../hooks/useCommandPaletteEnabled", () => ({ useCommandPaletteEnabled: () => true }));
vi.mock("../components/CommandPalette", () => ({ CommandPalette: () => null }));
vi.mock("../components/OrchestratorReplacementDialog", () => ({ OrchestratorReplacementDialog: () => null }));
```

Edit 1 of 2 in `frontend/src/renderer/components/split/SplitWorkspace.tsx` — find this text (starts at line 22 of the unmodified file):

```tsx
} from "../../hooks/useShellTerminals";
import { useWorkspaceQuery } from "../../hooks/useWorkspaceQuery";
import { operatorBridge } from "../../lib/bridge";
import { useShell } from "../../lib/shell-context";
import { useResolvedTheme, useUiStore } from "../../stores/ui-store";
import type { TerminalTarget } from "../../types/terminal";
```

replace it with:

```tsx
} from "../../hooks/useShellTerminals";
import { useWorkspaceQuery } from "../../hooks/useWorkspaceQuery";
import { operatorBridge } from "../../lib/bridge";
import { claimOnScreenTerminals } from "../../lib/on-screen-terminals";
import { useShell } from "../../lib/shell-context";
import { useResolvedTheme, useUiStore } from "../../stores/ui-store";
import type { TerminalTarget } from "../../types/terminal";
```

Edit 2 of 2 in `frontend/src/renderer/components/split/SplitWorkspace.tsx` — find this text (starts at line 99 of the unmodified file):

```tsx
		};
	}, [clearVisibleTerminalKind, layout, setVisibleTerminalKind]);

	useEffect(() => {
		const pendingShell = pendingShellRef.current;
		if (!pendingShell || !shells.has(pendingShell.handleId)) return;
```

replace it with:

```tsx
		};
	}, [clearVisibleTerminalKind, layout, setVisibleTerminalKind]);

	useEffect(() => {
		const handles: string[] = [];
		for (const pane of listPanes(layout.root)) {
			const tab = activeTabOf(pane);
			if (tab.kind !== "session") {
				handles.push(tab.handleId);
				continue;
			}
			const handleId = sessions.get(tab.sessionId)?.terminalHandleId;
			if (handleId) handles.push(handleId);
		}
		return claimOnScreenTerminals(handles);
	}, [layout, sessions]);

	useEffect(() => {
		const pendingShell = pendingShellRef.current;
		if (!pendingShell || !shells.has(pendingShell.handleId)) return;
```

Edit 1 of 2 in `frontend/src/renderer/components/ShellTerminalsView.tsx` — find this text (starts at line 9 of the unmodified file):

```tsx
import { isMacPlatform, windowDragRegion } from "../lib/platform";
import { cn } from "../lib/utils";
import { handleTerminalTabListKeyDown } from "../lib/terminal-tabs";
import { useResolvedTheme, useUiStore } from "../stores/ui-store";
import { ShellTerminalTab } from "./ShellTerminalTab";
import { TerminalPane } from "./TerminalPane";
```

replace it with:

```tsx
import { isMacPlatform, windowDragRegion } from "../lib/platform";
import { cn } from "../lib/utils";
import { handleTerminalTabListKeyDown } from "../lib/terminal-tabs";
import { claimOnScreenTerminals } from "../lib/on-screen-terminals";
import { useResolvedTheme, useUiStore } from "../stores/ui-store";
import { ShellTerminalTab } from "./ShellTerminalTab";
import { TerminalPane } from "./TerminalPane";
```

Edit 2 of 2 in `frontend/src/renderer/components/ShellTerminalsView.tsx` — find this text (starts at line 62 of the unmodified file):

```tsx
		if (!active) setActiveShellTerminal(shellTerminals[0].handleId);
	}, [shellTerminals, active, activeHandleId, setActiveShellTerminal]);

	useEffect(
		() =>
			operatorBridge.app.onCloseShellTerminalShortcut(() => {
```

replace it with:

```tsx
		if (!active) setActiveShellTerminal(shellTerminals[0].handleId);
	}, [shellTerminals, active, activeHandleId, setActiveShellTerminal]);

	const activeShellHandleId = active?.handleId;
	useEffect(
		() => (activeShellHandleId ? claimOnScreenTerminals([activeShellHandleId]) : undefined),
		[activeShellHandleId],
	);

	useEffect(
		() =>
			operatorBridge.app.onCloseShellTerminalShortcut(() => {
```

Edit 1 of 1 in `frontend/src/renderer/i18n/en.json` — find this text (starts at line 922 of the unmodified file):

```json
	"terminal.pasteReasonControl": "It contains control characters (shown as ^ below) that act like key presses.",
	"terminal.pasteReasonNewline": "It has more than one line, so each line may run as a command.",
	"terminal.pasteReasonPasteEnd": "It contains an end-of-paste sequence that can make the rest run as typed commands.",
	"terminal.claudeAccount": "Claude account",
	"terminal.relaunchCleared": "Relaunch in a cleared session",
	"terminal.relaunchClearedBody": "This stops {{agent}} and starts it again with an empty conversation. The current context is discarded and cannot be recovered.",
```

replace it with:

```json
	"terminal.pasteReasonControl": "It contains control characters (shown as ^ below) that act like key presses.",
	"terminal.pasteReasonNewline": "It has more than one line, so each line may run as a command.",
	"terminal.pasteReasonPasteEnd": "It contains an end-of-paste sequence that can make the rest run as typed commands.",
	"terminal.programNotificationFallback": "Terminal",
	"terminal.programTitleAria": "Terminal title: {{title}}",
	"terminal.claudeAccount": "Claude account",
	"terminal.relaunchCleared": "Relaunch in a cleared session",
	"terminal.relaunchClearedBody": "This stops {{agent}} and starts it again with an empty conversation. The current context is discarded and cannot be recovered.",
```

- [ ] **Step 4: Run the new tests, then the whole renderer suite, typecheck and lint**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build:ts >/dev/null && cd ../../frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/terminal-mux src/renderer/lib/terminal-titles src/renderer/lib/on-screen src/renderer/lib/program-feed src/renderer/components/ProgramRuntime src/renderer/components/split/SplitWorkspaceOnScreen src/renderer/components/ShellTerminalsView 2>&1 | grep -E "Test Files|Tests " && npx tsc --noEmit -p . && npx eslint src 2>&1 | grep -E "problems|error" | tail -2
```
Expected: `Test Files  9 passed (9)` and `Tests  53 passed (53)` (the seven new files plus the existing `terminal-mux.test.ts` and `ShellTerminalsView.test.tsx`), no `tsc` output, and `(0 errors, …)` from eslint. `shell-new-session-shortcut.test.tsx` needs the `ProgramRuntime` mock added above; without it, 21 tests fail on `operatorBridge.notifications` being undefined.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add frontend/src/renderer/lib/terminal-mux.programs.test.ts \
  frontend/src/renderer/lib/terminal-titles.ts \
  frontend/src/renderer/lib/terminal-titles.test.tsx \
  frontend/src/renderer/lib/on-screen-terminals.ts \
  frontend/src/renderer/lib/on-screen-terminals.test.ts \
  frontend/src/renderer/lib/program-feed.ts \
  frontend/src/renderer/lib/program-feed.test.ts \
  frontend/src/renderer/components/ProgramRuntime.tsx \
  frontend/src/renderer/components/ProgramRuntime.test.tsx \
  frontend/src/renderer/components/split/SplitWorkspaceOnScreenTerminals.test.tsx \
  frontend/src/renderer/components/ShellTerminalsView.onscreen.test.tsx \
  frontend/src/renderer/lib/terminal-mux.ts \
  frontend/src/renderer/routes/_shell.tsx \
  frontend/src/renderer/test/shell-new-session-shortcut.test.tsx \
  frontend/src/renderer/components/split/SplitWorkspace.tsx \
  frontend/src/renderer/components/ShellTerminalsView.tsx \
  frontend/src/renderer/i18n/en.json
git commit -m "feat(renderer): program feed, terminal titles store and program notifications when a pane is not on screen" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
Expected: the commit succeeds; `git status --short` lists nothing this task touched (feel baselines, `ts/core/wasm` and `dist` are ignored or restored). Never `git add -A`, `git commit -a` or `git stash`.

---

### Task 8: the pane sends its cell size and colours to the mirror

**Files:**
- Create: `frontend/src/renderer/lib/terminal-appearance.ts`
- Modify: `frontend/src/renderer/hooks/useTerminalSession.ts:20,210,635,1004`, `frontend/src/renderer/components/BlockTerminal.tsx:8,25,40,260-277,430`
- Test: `frontend/src/renderer/lib/terminal-appearance.test.ts`, `frontend/src/renderer/hooks/useTerminalSession.test.tsx:5,30,63,77,299`, `frontend/src/renderer/components/BlockTerminal.test.tsx:27,169,288,357,384,914`

**Interfaces:**
- Consumes: Task 2's `onGeometry(columns, rows, cell)` and `CellSize`; Task 7's `TerminalAppearance` and `TerminalMux.appearance`.
- Produces: `terminalAppearance(cell: CellSize, colors: {foreground, background}, devicePixelRatio): TerminalAppearance` (device pixels, rounded; a ratio ≤ 0 or NaN counts as 1); `BlockTerminalTransport.appearance?(appearance)`; `useTerminalSession`'s transport gains `appearance(appearance)`, which remembers the value, sends it while attached and re-sends it on every `opened`. `BlockTerminal` sends one when the surface first reports a cell size and whenever the cell size or the terminal colours change (`warpDarkTheme.foreground`, the chosen terminal background — `lib/terminal-background.ts`). Why device pixels: native terminals report backing-store pixels (Ghostty's `cell_size_px`); nothing in Operator draws images, so this only matters to programs that ask.

- [ ] **Step 1: Write the failing tests**

Create `frontend/src/renderer/lib/terminal-appearance.test.ts` with exactly this content:

```ts
import { describe, expect, it } from "vitest";
import { terminalAppearance } from "./terminal-appearance";

describe("terminalAppearance", () => {
	const colors = { foreground: "#ffffff", background: "#1d2022" };

	it("reports the cell in device pixels, rounded", () => {
		expect(terminalAppearance({ width: 8.4, height: 16.8 }, colors, 2)).toEqual({
			cellWidth: 17,
			cellHeight: 34,
			foreground: "#ffffff",
			background: "#1d2022",
		});
	});

	it("treats a missing or nonsensical pixel ratio as 1", () => {
		expect(terminalAppearance({ width: 8, height: 17 }, colors, 0)).toMatchObject({ cellWidth: 8, cellHeight: 17 });
		expect(terminalAppearance({ width: 8, height: 17 }, colors, Number.NaN)).toMatchObject({ cellWidth: 8, cellHeight: 17 });
	});
});
```

Edit 1 of 5 in `frontend/src/renderer/hooks/useTerminalSession.test.tsx` — find this text (starts at line 2 of the unmodified file):

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { MuxConnectionState, TerminalHealth, TerminalMux } from "../lib/terminal-mux";
import type { WorkspaceSession } from "../types/workspace";
import { useTerminalSession, type AttachableTerminal } from "./useTerminalSession";
import { workspaceQueryKey } from "./useWorkspaceQuery";
```

replace it with:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { MuxConnectionState, TerminalAppearance, TerminalHealth, TerminalMux } from "../lib/terminal-mux";
import type { WorkspaceSession } from "../types/workspace";
import { useTerminalSession, type AttachableTerminal } from "./useTerminalSession";
import { workspaceQueryKey } from "./useWorkspaceQuery";
```

Edit 2 of 5 in `frontend/src/renderer/hooks/useTerminalSession.test.tsx` — find this text (starts at line 28 of the unmodified file):

```tsx
	inputs: Array<[string, string]>;
	closes: string[];
	acks: number[];
	events: string[];
	disposed: boolean;
	emitData(id: string, text: string): void;
```

replace it with:

```tsx
	inputs: Array<[string, string]>;
	closes: string[];
	acks: number[];
	appearances: Array<[string, TerminalAppearance]>;
	events: string[];
	disposed: boolean;
	emitData(id: string, text: string): void;
```

Edit 3 of 5 in `frontend/src/renderer/hooks/useTerminalSession.test.tsx` — find this text (starts at line 61 of the unmodified file):

```tsx
		inputs: [],
		closes: [],
		acks: [],
		events: [],
		disposed: false,
		mux: {
```

replace it with:

```tsx
		inputs: [],
		closes: [],
		acks: [],
		appearances: [],
		events: [],
		disposed: false,
		mux: {
```

Edit 4 of 5 in `frontend/src/renderer/hooks/useTerminalSession.test.tsx` — find this text (starts at line 75 of the unmodified file):

```tsx
				fake.events.push(`close:${id}`);
			},
			ack: (_id, bytes) => fake.acks.push(bytes),
			onData: (id, listener) => subscribe(data, id, listener),
			onExit: (id, listener) => subscribe(exit, id, listener),
			onOpened: (id, listener) => subscribe(opened, id, listener),
```

replace it with:

```tsx
				fake.events.push(`close:${id}`);
			},
			ack: (_id, bytes) => fake.acks.push(bytes),
			appearance: (id, appearance) => fake.appearances.push([id, appearance]),
			onData: (id, listener) => subscribe(data, id, listener),
			onExit: (id, listener) => subscribe(exit, id, listener),
			onOpened: (id, listener) => subscribe(opened, id, listener),
```

Edit 5 of 5 in `frontend/src/renderer/hooks/useTerminalSession.test.tsx` — find this text (starts at line 297 of the unmodified file):

```tsx
		expect(muxes[0].acks).toEqual([6_000, 10_000]);
	});

	it("stays idle when the session has no terminal handle", () => {
		const { view, muxes } = setup({ attachedSession: { ...session, terminalHandleId: undefined } });
		expect(view.result.current.state).toBe("idle");
```

replace it with:

```tsx
		expect(muxes[0].acks).toEqual([6_000, 10_000]);
	});

	it("sends the terminal's appearance once attached and again on every reopen", () => {
		const appearance: TerminalAppearance = { cellWidth: 16, cellHeight: 34, foreground: "#ffffff", background: "#1d2022" };
		const { view, muxes } = setup();
		act(() => view.result.current.transport.appearance(appearance));
		expect(muxes[0].appearances).toEqual([]);
		act(() => muxes[0].emitOpened("handle-1"));
		expect(muxes[0].appearances).toEqual([["handle-1", appearance]]);
		const next: TerminalAppearance = { ...appearance, cellWidth: 18 };
		act(() => view.result.current.transport.appearance(next));
		expect(muxes[0].appearances).toEqual([
			["handle-1", appearance],
			["handle-1", next],
		]);
		act(() => muxes[0].emitOpened("handle-1"));
		expect(muxes[0].appearances.at(-1)).toEqual(["handle-1", next]);
	});

	it("stays idle when the session has no terminal handle", () => {
		const { view, muxes } = setup({ attachedSession: { ...session, terminalHandleId: undefined } });
		expect(view.result.current.state).toBe("idle");
```

Edit 1 of 6 in `frontend/src/renderer/components/BlockTerminal.test.tsx` — find this text (starts at line 24 of the unmodified file):

```tsx
		altScreenSurfaceProvided: false,
		altScreen: null as unknown,
		core: undefined as MockCore | undefined,
		emitGeometry: undefined as ((columns: number, rows: number) => void) | undefined,
		coreOverrides: undefined as Partial<MockCore> | undefined,
		host: undefined as
			| {
```

replace it with:

```tsx
		altScreenSurfaceProvided: false,
		altScreen: null as unknown,
		core: undefined as MockCore | undefined,
		emitGeometry: undefined as ((columns: number, rows: number, cell?: { width: number; height: number }) => void) | undefined,
		coreOverrides: undefined as Partial<MockCore> | undefined,
		host: undefined as
			| {
```

Edit 2 of 6 in `frontend/src/renderer/components/BlockTerminal.test.tsx` — find this text (starts at line 166 of the unmodified file):

```tsx
			strings?: Record<string, string>;
			onSend?: (text: string) => void;
			onSendRaw?: (data: string) => void;
			onGeometry?: (columns: number, rows: number) => void;
			onHint?: (hint: { ruleId: string; text: string; path?: string; line?: number }) => void;
			onBlockFinished?: (event: {
				id: string;
```

replace it with:

```tsx
			strings?: Record<string, string>;
			onSend?: (text: string) => void;
			onSendRaw?: (data: string) => void;
			onGeometry?: (columns: number, rows: number, cell?: { width: number; height: number }) => void;
			onHint?: (hint: { ruleId: string; text: string; path?: string; line?: number }) => void;
			onBlockFinished?: (event: {
				id: string;
```

Edit 3 of 6 in `frontend/src/renderer/components/BlockTerminal.test.tsx` — find this text (starts at line 286 of the unmodified file):

```tsx
import { BlockTerminal, type BlockTerminalHistoryBlock } from "./BlockTerminal";
import { terminalPredictiveEchoThresholdMs } from "../lib/terminal-predictive-echo";
import { useUiStore } from "../stores/ui-store";
import { operatorBridge } from "../lib/bridge";
import { openLinkInSystemBrowser } from "../lib/external-link-policy";

```

replace it with:

```tsx
import { BlockTerminal, type BlockTerminalHistoryBlock } from "./BlockTerminal";
import { terminalPredictiveEchoThresholdMs } from "../lib/terminal-predictive-echo";
import { useUiStore } from "../stores/ui-store";
import { terminalBackgroundColor } from "../lib/terminal-background";
import { operatorBridge } from "../lib/bridge";
import { openLinkInSystemBrowser } from "../lib/external-link-policy";

```

Edit 4 of 6 in `frontend/src/renderer/components/BlockTerminal.test.tsx` — find this text (starts at line 355 of the unmodified file):

```tsx
			return () => {};
		},
		resize: vi.fn(),
		dispose: vi.fn(),
	};
	render(
```

replace it with:

```tsx
			return () => {};
		},
		resize: vi.fn(),
		appearance: vi.fn(),
		dispose: vi.fn(),
	};
	render(
```

Edit 5 of 6 in `frontend/src/renderer/components/BlockTerminal.test.tsx` — find this text (starts at line 381 of the unmodified file):

```tsx
			return typeof value === "function" ? (value as (...a: unknown[]) => unknown).bind(c) : value;
		},
	});
	return { core: proxy };
}

beforeEach(() => {
```

replace it with:

```tsx
			return typeof value === "function" ? (value as (...a: unknown[]) => unknown).bind(c) : value;
		},
	});
	return { core: proxy, transport };
}

beforeEach(() => {
```

Edit 6 of 6 in `frontend/src/renderer/components/BlockTerminal.test.tsx` — find this text (starts at line 912 of the unmodified file):

```tsx
		await expect(answer).resolves.toBe(false);
	});
});
```

replace it with:

```tsx
		await expect(answer).resolves.toBe(false);
	});
});

describe("BlockTerminal appearance", () => {
	it("sends nothing until the surface has measured a cell", async () => {
		const { transport } = renderTerminal();
		await waitFor(() => expect(mockState.emitGeometry).toBeDefined());
		expect(transport.appearance).not.toHaveBeenCalled();
	});

	it("sends the cell size in device pixels and the terminal's colours once the surface measures", async () => {
		const { transport } = renderTerminal();
		await waitFor(() => expect(mockState.emitGeometry).toBeDefined());
		act(() => mockState.emitGeometry?.(80, 24, { width: 8.4, height: 16.8 }));
		expect(transport.appearance).toHaveBeenLastCalledWith({
			cellWidth: 8,
			cellHeight: 17,
			foreground: "#ffffff",
			background: terminalBackgroundColor(useUiStore.getState().terminalBackground),
		});
	});
});

```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx vitest run --config vite.renderer.config.ts src/renderer/lib/terminal-appearance src/renderer/hooks/useTerminalSession.test src/renderer/components/BlockTerminal.test 2>&1 | grep -E "FAIL|Tests " | head -6
```
Expected: `terminal-appearance.test.ts` fails to import; `useTerminalSession.test.tsx` "sends the terminal's appearance…" fails (`transport.appearance is not a function`); `BlockTerminal.test.tsx` "sends the cell size in device pixels…" fails (not called).

- [ ] **Step 3: Implement**

Create `frontend/src/renderer/lib/terminal-appearance.ts` with exactly this content:

```ts
import type { CellSize } from "@operator/terminal-react";
import type { TerminalAppearance } from "./terminal-mux";

export type TerminalColors = Readonly<{ foreground: string; background: string }>;

export function terminalAppearance(cell: CellSize, colors: TerminalColors, devicePixelRatio: number): TerminalAppearance {
	const scale = Number.isFinite(devicePixelRatio) && devicePixelRatio > 0 ? devicePixelRatio : 1;
	return {
		cellWidth: Math.round(cell.width * scale),
		cellHeight: Math.round(cell.height * scale),
		foreground: colors.foreground,
		background: colors.background,
	};
}
```

Edit 1 of 4 in `frontend/src/renderer/hooks/useTerminalSession.ts` — find this text (starts at line 17 of the unmodified file):

```ts
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { getApiBaseUrl } from "../lib/api-client";
import { captureRendererEvent } from "../lib/telemetry";
import { createTerminalMux, muxUrlFromApiBase, type TerminalHealth, type TerminalMux } from "../lib/terminal-mux";
import { sessionIsActive, type WorkspaceSession } from "../types/workspace";
import { workspaceQueryKey } from "./useWorkspaceQuery";

```

replace it with:

```ts
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { getApiBaseUrl } from "../lib/api-client";
import { captureRendererEvent } from "../lib/telemetry";
import {
	createTerminalMux,
	muxUrlFromApiBase,
	type TerminalAppearance,
	type TerminalHealth,
	type TerminalMux,
} from "../lib/terminal-mux";
import { sessionIsActive, type WorkspaceSession } from "../types/workspace";
import { workspaceQueryKey } from "./useWorkspaceQuery";

```

Edit 2 of 4 in `frontend/src/renderer/hooks/useTerminalSession.ts` — find this text (starts at line 208 of the unmodified file):

```ts
		// computed height and width are the literal "100%", which FitAddon parses
		// as 100px and turns into a 12-column proposal of nothing.
		surfaceGeometry: null as { cols: number; rows: number } | null,
		attempts: 0,
		generation: 0,
		inputReady: false,
```

replace it with:

```ts
		// computed height and width are the literal "100%", which FitAddon parses
		// as 100px and turns into a 12-column proposal of nothing.
		surfaceGeometry: null as { cols: number; rows: number } | null,
		appearance: null as TerminalAppearance | null,
		attempts: 0,
		generation: 0,
		inputReady: false,
```

Edit 3 of 4 in `frontend/src/renderer/hooks/useTerminalSession.ts` — find this text (starts at line 633 of the unmodified file):

```ts
				r.attempts = 0;
				setError(undefined);
				transition("attached");
				const measured = r.surfaceGeometry;
				if (measured) {
					const published = r.lastPublishedGrid;
```

replace it with:

```ts
				r.attempts = 0;
				setError(undefined);
				transition("attached");
				if (r.appearance) mux.appearance?.(handle, r.appearance);
				const measured = r.surfaceGeometry;
				if (measured) {
					const published = r.lastPublishedGrid;
```

Edit 4 of 4 in `frontend/src/renderer/hooks/useTerminalSession.ts` — find this text (starts at line 1002 of the unmodified file):

```ts
				if (!r.inputReady) return;
				publishGrid(cols, rows);
			},
			dispose: () => {
				const r = runtime.current;
				if (!r.mux || !r.handle) return;
```

replace it with:

```ts
				if (!r.inputReady) return;
				publishGrid(cols, rows);
			},
			appearance: (appearance: TerminalAppearance) => {
				const r = runtime.current;
				r.appearance = appearance;
				if (!r.mux || !r.handle || !r.inputReady) return;
				r.mux.appearance?.(r.handle, appearance);
			},
			dispose: () => {
				const r = runtime.current;
				if (!r.mux || !r.handle) return;
```

Edit 1 of 6 in `frontend/src/renderer/components/BlockTerminal.tsx` — find this text (starts at line 6 of the unmodified file):

```tsx
	createTerminalCore,
	initTerminalCoreFromUrl,
	warpDarkTheme,
	type FontConfig,
	type HostCapabilities,
	type TerminalCore,
```

replace it with:

```tsx
	createTerminalCore,
	initTerminalCoreFromUrl,
	warpDarkTheme,
	type CellSize,
	type FontConfig,
	type HostCapabilities,
	type TerminalCore,
```

Edit 2 of 6 in `frontend/src/renderer/components/BlockTerminal.tsx` — find this text (starts at line 23 of the unmodified file):

```tsx
import { fetchRedactionPatterns, redactionPatternsQueryKey } from "../lib/redaction-patterns";
import { externalEditorLabel } from "../lib/open-files-in";
import { usePasteConfirm } from "../hooks/usePasteConfirm";

export type BlockTerminalClipboard = {
	writeText: (text: string) => Promise<void>;
```

replace it with:

```tsx
import { fetchRedactionPatterns, redactionPatternsQueryKey } from "../lib/redaction-patterns";
import { externalEditorLabel } from "../lib/open-files-in";
import { usePasteConfirm } from "../hooks/usePasteConfirm";
import type { TerminalAppearance } from "../lib/terminal-mux";
import { terminalAppearance, type TerminalColors } from "../lib/terminal-appearance";

export type BlockTerminalClipboard = {
	writeText: (text: string) => Promise<void>;
```

Edit 3 of 6 in `frontend/src/renderer/components/BlockTerminal.tsx` — find this text (starts at line 38 of the unmodified file):

```tsx
	write: (data: Uint8Array) => void;
	onData: (listener: (bytes: Uint8Array) => void) => () => void;
	resize?: (cols: number, rows: number) => void;
	dispose?: () => void;
};

```

replace it with:

```tsx
	write: (data: Uint8Array) => void;
	onData: (listener: (bytes: Uint8Array) => void) => () => void;
	resize?: (cols: number, rows: number) => void;
	appearance?: (appearance: TerminalAppearance) => void;
	dispose?: () => void;
};

```

Edit 4 of 6 in `frontend/src/renderer/components/BlockTerminal.tsx` — find this text (starts at line 257 of the unmodified file):

```tsx
	const onSendRaw = useCallback((data: string) => {
		transportRef.current.write(new TextEncoder().encode(data));
	}, []);
	const onGeometry = useCallback((columns: number, rows: number) => {
		if (recordsSpawnGridRef.current) rememberPaneGrid(columns, rows);
		transportRef.current.resize?.(columns, rows);
		// TerminalSurface resizes the core immediately before reporting, so the
		// core is correctly sized by the time this runs and the held bytes can be
		// parsed against the grid they were written for.
```

replace it with:

```tsx
	const onSendRaw = useCallback((data: string) => {
		transportRef.current.write(new TextEncoder().encode(data));
	}, []);
	const cellSizeRef = useRef<CellSize | null>(null);
	const terminalColorsRef = useRef<TerminalColors | null>(null);
	const publishAppearance = useCallback(() => {
		const cell = cellSizeRef.current;
		const colors = terminalColorsRef.current;
		if (!cell || !colors) return;
		transportRef.current.appearance?.(terminalAppearance(cell, colors, window.devicePixelRatio));
	}, []);
	const onGeometry = useCallback((columns: number, rows: number, cell?: CellSize) => {
		if (recordsSpawnGridRef.current) rememberPaneGrid(columns, rows);
		transportRef.current.resize?.(columns, rows);
		if (cell) {
			cellSizeRef.current = cell;
			publishAppearance();
		}
		// TerminalSurface resizes the core immediately before reporting, so the
		// core is correctly sized by the time this runs and the held bytes can be
		// parsed against the grid they were written for.
```

Edit 5 of 6 in `frontend/src/renderer/components/BlockTerminal.tsx` — find this text (starts at line 274 of the unmodified file):

```tsx
			feedToCore(core, bytes, historyIdsRef.current);
		}
		reportReplayPainted();
	}, [reportReplayPainted]);

	useEffect(() => {
		if (!core) return;
```

replace it with:

```tsx
			feedToCore(core, bytes, historyIdsRef.current);
		}
		reportReplayPainted();
	}, [publishAppearance, reportReplayPainted]);

	useEffect(() => {
		if (!core) return;
```

Edit 6 of 6 in `frontend/src/renderer/components/BlockTerminal.tsx` — find this text (starts at line 428 of the unmodified file):

```tsx
		document.documentElement.style.setProperty("--terminal-background", resolvedTheme.background);
	}, [resolvedTheme.background]);

	const redactSecrets = useUiStore((state) => state.terminalSecretRedaction);
	const { data: patterns } = useQuery({
		queryKey: redactionPatternsQueryKey,
```

replace it with:

```tsx
		document.documentElement.style.setProperty("--terminal-background", resolvedTheme.background);
	}, [resolvedTheme.background]);

	useEffect(() => {
		terminalColorsRef.current = { foreground: resolvedTheme.foreground, background: resolvedTheme.background };
		publishAppearance();
	}, [publishAppearance, resolvedTheme.background, resolvedTheme.foreground]);

	const redactSecrets = useUiStore((state) => state.terminalSecretRedaction);
	const { data: patterns } = useQuery({
		queryKey: redactionPatternsQueryKey,
```

- [ ] **Step 4: Run**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx vitest run --config vite.renderer.config.ts src/renderer/lib/terminal-appearance src/renderer/hooks/useTerminalSession.test src/renderer/components/BlockTerminal.test 2>&1 | grep -E "Test Files|Tests " && npx tsc --noEmit -p . && npx eslint src 2>&1 | grep -E "problems" | tail -1
```
Expected: `Test Files  3 passed (3)`; no `tsc` output; `(0 errors, …)`.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add frontend/src/renderer/lib/terminal-appearance.ts \
  frontend/src/renderer/lib/terminal-appearance.test.ts \
  frontend/src/renderer/hooks/useTerminalSession.ts \
  frontend/src/renderer/hooks/useTerminalSession.test.tsx \
  frontend/src/renderer/components/BlockTerminal.tsx \
  frontend/src/renderer/components/BlockTerminal.test.tsx
git commit -m "feat(renderer): send the pane's cell size and colours so the mirror can answer size and colour queries" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
Expected: the commit succeeds; `git status --short` lists nothing this task touched (feel baselines, `ts/core/wasm` and `dist` are ignored or restored). Never `git add -A`, `git commit -a` or `git stash`.

---

### Task 9: the title on the session card and in the pane header

**Files:**
- Modify: `frontend/src/renderer/components/SessionsBoard.tsx:57,741,861`, `frontend/src/renderer/components/split/SplitPane.tsx:13,76,104`
- Test: `frontend/src/renderer/components/SessionsBoard.test.tsx:6,463`, `frontend/src/renderer/components/split/SplitPane.test.tsx:2,4,8,29,77,91`

**Interfaces:**
- Consumes: Task 7's `useTerminalTitle` and `terminal.programTitleAria`.
- Produces: on the board's `SessionCard`, directly under the session name, `<div data-testid="board-terminal-title">` in `text-2xs text-muted-foreground`, truncated to one line, with the full title as tooltip and "Terminal title: …" as its accessible name, clearing the same corner controls the name clears (`cornerControlPadding`); in the split pane's header, `<span data-testid="pane-terminal-title">` between the tab strip and the pane actions, `text-micro text-muted-foreground`, at most 40 % of the header, truncated, following the pane's **active** tab. Nothing renders when the title is empty (user decision 1). Styling uses only the tokens the surrounding card and header already use (DESIGN.md "clone agent-orchestrator" banner: no new colours, sizes or components).

- [ ] **Step 1: Write the failing tests**

Edit 1 of 2 in `frontend/src/renderer/components/SessionsBoard.test.tsx` — find this text (starts at line 4 of the unmodified file):

```tsx
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { WorkspaceSession, WorkspaceSummary } from "../types/workspace";
import { rememberPaneGrid, resetPaneGridForTests } from "../lib/pane-grid";

const {
	navigateMock,
```

replace it with:

```tsx
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { WorkspaceSession, WorkspaceSummary } from "../types/workspace";
import { rememberPaneGrid, resetPaneGridForTests } from "../lib/pane-grid";
import { clearTerminalTitles, setTerminalTitle } from "../lib/terminal-titles";

const {
	navigateMock,
```

Edit 2 of 2 in `frontend/src/renderer/components/SessionsBoard.test.tsx` — find this text (starts at line 461 of the unmodified file):

```tsx
	// The agent's own report (Operator MCP session_report) explains the card:
	// the question it is waiting on shows under the status, and the daemon's
	// status reason is the status label's tooltip.
	it("shows the agent's reported reason and the status reason on the card", () => {
		workspaceQueryMock.mockReturnValue({
			data: [
```

replace it with:

```tsx
	// The agent's own report (Operator MCP session_report) explains the card:
	// the question it is waiting on shows under the status, and the daemon's
	// status reason is the status label's tooltip.
	it("shows the terminal's live title under the session name and nothing when it has none", () => {
		workspaceQueryMock.mockReturnValue({
			data: [
				workspaceWithSessions([
					boardSession({ id: "s-titled", title: "titled-card-task", status: "working", terminalHandleId: "h-titled" }),
					boardSession({ id: "s-untitled", title: "untitled-card-task", status: "idle", terminalHandleId: "h-untitled" }),
				]),
			],
			isError: false,
			isSuccess: true,
		});
		act(() => setTerminalTitle("h-titled", "Number list 1 to 3000"));
		renderBoard("p1");
		const titled = screen.getByText("titled-card-task").closest('[data-testid="board-session-card"]') as HTMLElement;
		const line = within(titled).getByTestId("board-terminal-title");
		expect(line).toHaveTextContent("Number list 1 to 3000");
		expect(line).toHaveAttribute("title", "Number list 1 to 3000");
		expect(line).toHaveAccessibleName("Terminal title: Number list 1 to 3000");
		act(() => setTerminalTitle("h-titled", "Refactor the parser"));
		expect(within(titled).getByTestId("board-terminal-title")).toHaveTextContent("Refactor the parser");
		const untitled = screen.getByText("untitled-card-task").closest('[data-testid="board-session-card"]') as HTMLElement;
		expect(within(untitled).queryByTestId("board-terminal-title")).toBeNull();
		act(() => setTerminalTitle("h-titled", ""));
		expect(within(titled).queryByTestId("board-terminal-title")).toBeNull();
		act(() => clearTerminalTitles());
	});

	it("shows the agent's reported reason and the status reason on the card", () => {
		workspaceQueryMock.mockReturnValue({
			data: [
```

Edit 1 of 4 in `frontend/src/renderer/components/split/SplitPane.test.tsx` — find this text (starts at line 1 of the unmodified file):

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen } from "@testing-library/react";
import type { ComponentProps } from "react";
import { describe, expect, it, vi } from "vitest";
import type { Pane } from "../../lib/split-layout";
import type { ShellTerminal } from "../../hooks/useShellTerminals";
import type { WorkspaceSession } from "../../types/workspace";
import { TooltipProvider } from "../ui/tooltip";
import { SplitPane } from "./SplitPane";

vi.mock("./PaneTerminal", async (importOriginal) => {
```

replace it with:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen } from "@testing-library/react";
import type { ComponentProps } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Pane } from "../../lib/split-layout";
import type { ShellTerminal } from "../../hooks/useShellTerminals";
import type { WorkspaceSession } from "../../types/workspace";
import { TooltipProvider } from "../ui/tooltip";
import { clearTerminalTitles, setTerminalTitle } from "../../lib/terminal-titles";
import { SplitPane } from "./SplitPane";

vi.mock("./PaneTerminal", async (importOriginal) => {
```

Edit 2 of 4 in `frontend/src/renderer/components/split/SplitPane.test.tsx` — find this text (starts at line 27 of the unmodified file):

```tsx
	workspaceId: "p",
	workspaceName: "app",
	title: "alpha",
	provider: "claude-code",
	status: "working",
	updatedAt: "2026-09-22T00:00:00Z",
```

replace it with:

```tsx
	workspaceId: "p",
	workspaceName: "app",
	title: "alpha",
	terminalHandleId: "ha",
	provider: "claude-code",
	status: "working",
	updatedAt: "2026-09-22T00:00:00Z",
```

Edit 3 of 4 in `frontend/src/renderer/components/split/SplitPane.test.tsx` — find this text (starts at line 75 of the unmodified file):

```tsx
	return render(paneTree(overrides));
}

describe("SplitPane", () => {
	it("focuses on pointer down, renders the ring only when asked, and closes the pane", () => {
		const onFocus = vi.fn();
```

replace it with:

```tsx
	return render(paneTree(overrides));
}

afterEach(() => clearTerminalTitles());

describe("SplitPane", () => {
	it("focuses on pointer down, renders the ring only when asked, and closes the pane", () => {
		const onFocus = vi.fn();
```

Edit 4 of 4 in `frontend/src/renderer/components/split/SplitPane.test.tsx` — find this text (starts at line 89 of the unmodified file):

```tsx
		expect(onClosePane).toHaveBeenCalled();
	});

	it("hands the active tab's target to the terminal", () => {
		renderPane({ pane: { ...basePane, activeTab: 1 } });
		expect(screen.getByTestId("pane-terminal")).toHaveAttribute("data-target", "shell");
```

replace it with:

```tsx
		expect(onClosePane).toHaveBeenCalled();
	});

	it("shows the active tab's terminal title in the pane header", () => {
		act(() => {
			setTerminalTitle("ha", "Number list 1 to 3000");
			setTerminalTitle("h1", "vim main.go");
		});
		const { rerender } = renderPane();
		const title = screen.getByTestId("pane-terminal-title");
		expect(title).toHaveTextContent("Number list 1 to 3000");
		expect(title).toHaveAccessibleName("Terminal title: Number list 1 to 3000");
		rerender(paneTree({ pane: { ...basePane, activeTab: 1 } }));
		expect(screen.getByTestId("pane-terminal-title")).toHaveTextContent("vim main.go");
		act(() => setTerminalTitle("h1", ""));
		expect(screen.queryByTestId("pane-terminal-title")).toBeNull();
	});

	it("hands the active tab's target to the terminal", () => {
		renderPane({ pane: { ...basePane, activeTab: 1 } });
		expect(screen.getByTestId("pane-terminal")).toHaveAttribute("data-target", "shell");
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx vitest run --config vite.renderer.config.ts src/renderer/components/SessionsBoard.test src/renderer/components/split/SplitPane.test 2>&1 | grep -E "FAIL|Tests "
```
Expected: the two new tests fail (`Unable to find an element by: [data-testid="board-terminal-title"]` / `pane-terminal-title`).

- [ ] **Step 3: Implement**

Edit 1 of 3 in `frontend/src/renderer/components/SessionsBoard.tsx` — find this text (starts at line 55 of the unmodified file):

```tsx
import { TicketBadge } from "./tickets/TicketBadge";
import { ArchiveTicketItem } from "./tickets/ArchiveTicketItem";
import { useShellMaybe } from "../lib/shell-context";
import { dotGlow } from "../theme/effects";
import { useTicketsQuery } from "../hooks/useTicketsQuery";
import { isTicketInArchive } from "../lib/ticket-presentation";
```

replace it with:

```tsx
import { TicketBadge } from "./tickets/TicketBadge";
import { ArchiveTicketItem } from "./tickets/ArchiveTicketItem";
import { useShellMaybe } from "../lib/shell-context";
import { useTerminalTitle } from "../lib/terminal-titles";
import { dotGlow } from "../theme/effects";
import { useTicketsQuery } from "../hooks/useTicketsQuery";
import { isTicketInArchive } from "../lib/ticket-presentation";
```

Edit 2 of 3 in `frontend/src/renderer/components/SessionsBoard.tsx` — find this text (starts at line 739 of the unmodified file):

```tsx
			: "";
	const showLocation = showBranch || location !== "";
	const prSummaries = sessionPRDisplaySummaries(session, useSessionScmSummary(session.id).data);
	const termination = useTerminateSessionState(session.id);
	const showTerminate = interactive && session.isTerminated !== true && onTerminate;
	// Same action as the sidebar row's: the daemon owns where the session lives,
```

replace it with:

```tsx
			: "";
	const showLocation = showBranch || location !== "";
	const prSummaries = sessionPRDisplaySummaries(session, useSessionScmSummary(session.id).data);
	const terminalTitle = useTerminalTitle(session.terminalHandleId);
	const termination = useTerminateSessionState(session.id);
	const showTerminate = interactive && session.isTerminated !== true && onTerminate;
	// Same action as the sidebar row's: the daemon owns where the session lives,
```

Edit 3 of 3 in `frontend/src/renderer/components/SessionsBoard.tsx` — find this text (starts at line 859 of the unmodified file):

```tsx
					>
						{session.title}
					</div>
					{showLocation && (
						<div className="mt-1 flex min-w-0 items-center gap-1 font-mono text-micro leading-normal text-passive">
							{showBranch && (
```

replace it with:

```tsx
					>
						{session.title}
					</div>
					{terminalTitle ? (
						<div
							aria-label={t("terminal.programTitleAria", { title: terminalTitle })}
							className={cn("mt-0.5 truncate text-2xs leading-snug text-muted-foreground", cornerControlPadding)}
							data-testid="board-terminal-title"
							title={terminalTitle}
						>
							{terminalTitle}
						</div>
					) : null}
					{showLocation && (
						<div className="mt-1 flex min-w-0 items-center gap-1 font-mono text-micro leading-normal text-passive">
							{showBranch && (
```

Edit 1 of 3 in `frontend/src/renderer/components/split/SplitPane.tsx` — find this text (starts at line 11 of the unmodified file):

```tsx
import { PaneTabStrip } from "./PaneTabStrip";
import { PaneTerminal, terminalTargetForTab } from "./PaneTerminal";
import { registerPaneElement } from "./pane-registry";

const isMac = isMacPlatform();
const isLinux = isLinuxPlatform();
```

replace it with:

```tsx
import { PaneTabStrip } from "./PaneTabStrip";
import { PaneTerminal, terminalTargetForTab } from "./PaneTerminal";
import { registerPaneElement } from "./pane-registry";
import { useTerminalTitle } from "../../lib/terminal-titles";

const isMac = isMacPlatform();
const isLinux = isLinuxPlatform();
```

Edit 2 of 3 in `frontend/src/renderer/components/split/SplitPane.tsx` — find this text (starts at line 74 of the unmodified file):

```tsx
	const sessionId = tabSessionId(tab);
	const session = sessionId ? props.sessions.get(sessionId) : undefined;
	const shell = tab.kind === "shell" ? props.shells.get(tab.handleId) : undefined;
	return (
		<section
			ref={(element) => registerPaneElement(props.pane.id, "pane", element)}
```

replace it with:

```tsx
	const sessionId = tabSessionId(tab);
	const session = sessionId ? props.sessions.get(sessionId) : undefined;
	const shell = tab.kind === "shell" ? props.shells.get(tab.handleId) : undefined;
	const paneTitle = useTerminalTitle(tab.kind === "session" ? session?.terminalHandleId : tab.handleId);
	return (
		<section
			ref={(element) => registerPaneElement(props.pane.id, "pane", element)}
```

Edit 3 of 3 in `frontend/src/renderer/components/split/SplitPane.tsx` — find this text (starts at line 102 of the unmodified file):

```tsx
					sessions={props.sessions}
					shells={props.shells}
				/>
				<div className="ml-auto flex shrink-0 items-center gap-1.5 px-3">
					{session ? <PaneSessionActions session={session} onFocus={props.onFocus} /> : null}
					<TopbarButton
```

replace it with:

```tsx
					sessions={props.sessions}
					shells={props.shells}
				/>
				{paneTitle ? (
					<span
						aria-label={t("terminal.programTitleAria", { title: paneTitle })}
						className="min-w-0 max-w-[40%] shrink truncate self-center pl-3 text-micro text-muted-foreground"
						data-testid="pane-terminal-title"
						title={paneTitle}
					>
						{paneTitle}
					</span>
				) : null}
				<div className="ml-auto flex shrink-0 items-center gap-1.5 px-3">
					{session ? <PaneSessionActions session={session} onFocus={props.onFocus} /> : null}
					<TopbarButton
```

- [ ] **Step 4: Run, then the whole renderer suite**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx vitest run --config vite.renderer.config.ts src/renderer/components/SessionsBoard.test src/renderer/components/split/SplitPane.test 2>&1 | grep -E "Test Files|Tests " && npx vitest run --config vite.renderer.config.ts 2>&1 | grep -E "Test Files|Tests |FAIL" && npx tsc --noEmit -p . && npx eslint src 2>&1 | grep -E "problems" | tail -1
```
Expected: `Test Files  2 passed (2)`; then the full suite with no `FAIL` (author: `Test Files  168 passed (168)`, `Tests  1690 passed (1690)`); no `tsc` output; `(0 errors, …)`.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add frontend/src/renderer/components/SessionsBoard.tsx \
  frontend/src/renderer/components/SessionsBoard.test.tsx \
  frontend/src/renderer/components/split/SplitPane.tsx \
  frontend/src/renderer/components/split/SplitPane.test.tsx
git commit -m "feat(renderer): show the program's live title on the session card and the pane header" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```
Expected: the commit succeeds; `git status --short` lists nothing this task touched (feel baselines, `ts/core/wasm` and `dist` are ignored or restored). Never `git add -A`, `git commit -a` or `git stash`.

---

### Task 10: Gates — every suite, both wasm builds, the benches

**Files:** none changed. Every gate's last line (or `not run: <reason>`) goes into the completion report verbatim.

- [ ] **Step 1: Rust**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo fmt --check && echo FMT-OK; cargo clippy --all-targets -- -D warnings 2>&1 | grep -cE "^(warning|error)"; cargo test 2>&1 | grep -E "FAILED|panicked"; cargo test 2>&1 | grep -c "^test result: ok"
```
Expected: `FMT-OK`, `0`, no `FAILED`/`panicked` lines, and a count of `ok` result lines.

- [ ] **Step 2: Both wasm builds are current**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && cargo build --release -p vt-host --target wasm32-unknown-unknown && cmp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && echo HOST-WASM-CURRENT && sha256sum target/wasm32-unknown-unknown/release/vt_host.wasm && npm run build:wasm -- --force && npm run build:ts && echo RENDERER-WASM-OK
```
Expected: `HOST-WASM-CURRENT`, a hash different from Task 0 Step 6, `build-wasm: … ready`, `RENDERER-WASM-OK`. If `cmp` differs, copy the fresh build over the asset and commit it as `chore(ptyhost): rebuild vt_host.wasm` with the trailer.

- [ ] **Step 3: TS package suites and boundaries**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && for p in core renderer-dom editor completions react; do (cd ts/$p && npx vitest run 2>&1 | grep -E "Test Files|Tests "); done && npm run check:boundaries
```
Expected: every suite passes; each count is Task 0's plus this plan's additions (core +1 file / +7 tests, react +1 / +4); `boundary check passed`.

- [ ] **Step 4: Go**

```bash
cd "$(git rev-parse --show-toplevel)/backend" && go build ./... && go vet ./... && go test ./... 2>&1 | grep -E "^--- FAIL|^FAIL" ; go test -race ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... 2>&1 | tail -4 && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs 2>&1 | tail -2
```
Expected: no `FAIL` lines beyond those recorded in Task 0; `ok` lines for `ptyhost`, `ptyregistry`, `vtwasm`, `terminal`; `0 issues.`

- [ ] **Step 5: API drift**

```bash
cd "$(git rev-parse --show-toplevel)" && npm run api && git status --short backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts && cd backend && go test ./internal/httpd/... 2>&1 | tail -3
```
Expected: `git status --short` prints nothing (no DTO changed), and the httpd packages report `ok`.

- [ ] **Step 6: Frontend**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx tsc --noEmit -p . && echo TSC-OK && npm run lint 2>&1 | grep -E "problems" | tail -1 && npx vitest run --config vite.renderer.config.ts 2>&1 | grep -E "Test Files|Tests |FAIL"
```
Expected: `TSC-OK`; `(0 errors, …)`; no `FAIL`, file and test counts = Task 0's plus the 8 files and 32 tests this plan adds (author: 168 files / 1,690 tests).

- [ ] **Step 7: Feel gate against this environment's own baseline**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && rm -rf bench/agent-session/baselines && cp -R /tmp/plan3-feel-base bench/agent-session/baselines && npm run bench:feel; status=$?; git checkout -- bench/agent-session/baselines && git clean -fd -- bench/agent-session/baselines >/dev/null; git status --short bench/agent-session/baselines; echo "bench:feel exit $status"
```
Expected: `PASS feel gate: zero pixel diff`, an empty `git status`, `bench:feel exit 0`. The committed baselines are never replaced.

- [ ] **Step 8: The other benches**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:selection 2>&1 | tail -2; npm run bench:agent:gate 2>&1 | tail -3; npm run bench:agent:scroll 2>&1 | tail -3; for a in hover hint redact; do npm run bench:affordances -- --action $a 2>&1 | tail -1; done; git status --short bench/
```
Expected: each ends with its PASS line (`bench:affordances` only records side-by-sides, never fails on pixels); `git status --short bench/` prints nothing, or only files these runs regenerate that are not part of this plan — restore those with `git checkout -- <path>` and never commit them.

- [ ] **Step 9: Daemon build**

```bash
cd "$(git rev-parse --show-toplevel)" && npm --prefix frontend run build:daemon 2>&1 | tail -2
```
Expected: the daemon builds to `frontend/daemon/opr`. On Linux without the desktop toolchain this may be unsupported — record `not run: <reason>`.

---

### Task 11: Docs

**Files:**
- Modify: `packages/terminal/CHANGELOG.md` (top of "Unreleased", after line 3), `TERMINAL.md` (new §4.30 before `## 5. Known gaps (not bugs, decisions pending)`, line 941; three new bullets at the end of §5, before the `---` above `## 6.`, line 1297), `docs/terminal/2026-09-19-terminal-reference-survey.md` (count sentence line 50, table rows lines 68, 69, 85, status lines 989, 1054, 1875), `docs/terminal/2026-09-24-not-done-plain-language.md` (lines 7, 123-127, 129, 134-135)

- [ ] **Step 1: CHANGELOG** — insert as the first bullet under `## Unreleased`:

```markdown
- vt-core/vt-wasm/vt-host/core/react/renderer-dom: messages from programs (roadmap Plan 3, survey §1.15, §1.16, §2.14). OSC 0/2 set `TerminalCore::title()` (control characters dropped, capped at 1,024 bytes like Ghostty); `CSI 22/23 ; 0|2 t` push and pop it on a stack capped at 4,096 that drops the oldest (Alacritty `term/mod.rs:42,2235-2248`, behaviour only). OSC 9 (ConEmu sub-commands 1-12 excluded), OSC 777 `notify` and OSC 99 (single- and multi-part, plain text) queue `ProgramNotification`s (at most 16) for `take_notifications()`; OSC 22 records a CSS pointer shape (`pointer_shape()`, X11 names mapped). A core that answers queries (the pty-host mirror) now also answers `CSI 14/16/18 t`, mode 2048 (report on enable, on resize and on a cell-size change; DECRQM 2048) once `set_cell_pixels` is known, and `OSC 10/11 ; ?` once `set_default_colors` is known. A process boundary clears the title, stack, pointer and 2048. History chunks never change the title or raise notifications. TS: `TerminalCore.title()`, `pointerShape()`, `onProgramMessage()`, and the core calls `HostCapabilities.notify` for each notification; `TerminalSurface` sets `--terminal-pointer-shape` on the surface, takes `onTitle`, and passes the measured cell size as `onGeometry`'s third argument. `.terminal-block, .terminal-alt-surface` use `cursor: var(--terminal-pointer-shape, default)` — no pixel change. Both wasm artifacts and the daemon must be rebuilt.
```

- [ ] **Step 2: `TERMINAL.md` §4.30** — insert this block immediately before the line `## 5. Known gaps (not bugs, decisions pending)`:

```markdown
### 4.30 Messages from programs: title, notifications, size and colour replies — roadmap Plan 3
- Symptom: Claude Code sets its window title about ten times a second (`claude-long-50k`: 1,047 `OSC 0`) and Operator showed none of it; a program's own "done" notification (OSC 9/777/99) went nowhere; `CSI 16 t` (sent by Claude Code v2.1.280, `claude-markdown-reply`), `CSI 14/18 t`, mode 2048 and `OSC 10/11 ; ?` went unanswered; OSC 22 was ignored.
- Now: `vt-core` `program.rs` holds the title, a title stack capped at 4,096, up to 16 pending notifications and a pointer shape; both OSC dispatchers classify through `OscKind` and the history receiver handles only hyperlinks, so replayed history never changes the title or notifies. Replies use the same queue as the XTVERSION/DECRQM/DA1 answers (§4.16): only the mirror answers. The mirror learns the cell size (device pixels) and colours from the pane's `appearance` mux frame (last writer wins; nothing is answered for 14/16/2048/10/11 before one arrives). The pty-host strips a leading glyph+space (`domain.TerminalDisplayTitle`) and pushes only a changed stripped title, plus every notification, to **watcher** connections (`MsgWatchReq`, `MsgProgramEvent`); the daemon's runtime keeps one watch per live host in memory (opened by `Create`, `Attach` and each successful reaper probe; closed by `Destroy`) and the terminal mux relays on `ch:"programs"` with a snapshot on subscribe. The renderer's `ProgramRuntime` feeds `useTerminalTitle` (session card under the name, pane header) and shows a program notification as a desktop toast only when its terminal is not on screen in a focused window (agent-alerts rule D2); the pointer shape is the surface's `--terminal-pointer-shape`.
- Guards: `vt-core/tests/program_messages.rs`, `program_replies.rs`; `vt-wasm/tests/program_exports.rs`; `ts/core/src/program-messages.test.ts`; `ts/react/src/TerminalSurface.program.test.tsx`; `vtwasm/program_test.go`; `ptyhost/program_test.go`, `program_watch_test.go`; `domain/terminal_title_test.go`; `terminal/programs_test.go`; renderer `terminal-mux.programs.test.ts`, `terminal-titles.test.tsx`, `on-screen-terminals.test.ts`, `program-feed.test.ts`, `ProgramRuntime.test.tsx`, `SplitWorkspaceOnScreenTerminals.test.tsx`, `ShellTerminalsView.onscreen.test.tsx`, `terminal-appearance.test.ts`, and the new cases in `SessionsBoard.test.tsx`, `SplitPane.test.tsx`, `BlockTerminal.test.tsx`, `useTerminalSession.test.tsx`.
- References, behaviour only (no code adapted, so no attribution file): Ghostty `src/terminal/size_report.zig:5-80`, `stream_terminal.zig:256-280,1456-1476,1602-1605`, `osc/parsers/osc9.zig`, `rxvt_extension.zig`, `mouse.zig:100-150`; Alacritty `alacritty_terminal/src/term/mod.rs:42-48,2235-2248`; kitty's desktop-notification protocol description (no kitty code read).
```

- [ ] **Step 3: `TERMINAL.md` §5** — append these bullets at the end of §5 (after the "What a parked pane still costs" bullet, before `---`):

```markdown
- **Program notifications are desktop toasts only.** They are not notification rows: those need a session and project and a type the table's `CHECK` allows (`migrations/0117_notification_alerts.sql:8-9`), which standalone shells cannot give. So no bell entry and no phone alert (ntfy) for OSC 9/777/99, and nothing is shown while Operator's window is closed. A notification the child sends before the daemon's watch connects (the first milliseconds of a host) is dropped.
- **Size and colour answers wait for a pane.** The mirror answers `CSI 14/16 t`, mode 2048 and `OSC 10/11` only after a pane has sent its cell size and colours; a Claude Code session started while no pane is open gets no answer to its startup `CSI 16 t`. With several panes on one terminal, the last to send wins.
- **The title is not in the attach replay.** A renderer core that reattaches has an empty `title()` until the program sets it again; Operator reads the title from the daemon, so nothing visible depends on it.
```

- [ ] **Step 4: Survey** — in `docs/terminal/2026-09-19-terminal-reference-survey.md`:
  - Replace the §1.15 table row (line 68) with: `| §1.15 | Done | Plan E — OSC 8 and hover links. Roadmap Plan 3 — OSC 0/2 title (card and pane header in Operator), OSC 9/777/99 notifications (toast when the pane is not on screen), OSC 10/11 replies from the pane's colours, OSC 22 pointer shape. |`
  - Replace the §1.16 row (line 69) with: `| §1.16 | Done | Roadmap Plan 3 — the mirror answers XTWINOPS 14/16/18 \`t\` and mode 2048 from the grid and the pane's cell size (device pixels). Coalescing was already adequate (\`RESIZE_DEBOUNCE_MS\` = 100). |`
  - Replace the §2.14 row (line 85) with: `| §2.14 | Done | Roadmap Plan 3 — title stack capped at 4,096 (oldest dropped), pending notifications at 16, titles at 1,024 bytes. There is no keyboard-mode stack to cap. The grapheme byte cap (256) was already in place. |`
  - Replace each entry's `> **Status: …**` line (lines 989, 1054, 1875) with `> **Status: Done.**` followed by the same text as its table row.
  - Recount and fix the count sentence on line 50:
    ```bash
    cd "$(git rev-parse --show-toplevel)" && awk -F'|' '/^\| §/ {gsub(/ /,"",$3); print $3}' docs/terminal/2026-09-19-terminal-reference-survey.md | sort | uniq -c
    ```
    Expected on an otherwise unchanged survey: `42 Done`, `1 N/A`, `19 Notdone`, `1 Notneeded`, `7 Notpursued`, `18 Partial`; write those numbers into the sentence ("… 42 done, 18 partial, 19 not done, 7 not pursued, 1 not needed, 1 n/a") and append `"Roadmap Plan 3" is the program-messages plan (docs/superpowers/plans/2026-09-25-terminal-plan-3-program-messages.md).` Parallel plans edit this sentence too; use the numbers the command prints on your branch.

- [ ] **Step 5: Plain-language doc** — in `docs/terminal/2026-09-24-not-done-plain-language.md`:
  - Replace items 19 and 20 (lines 123-127) with:
    ```markdown
    19. **Safety caps (§2.14) — done (2026-09-25, roadmap Plan 3).** Programs can
        push window titles onto a stack; it now stops at 4,096 and drops the
        oldest, so a runaway program cannot grow memory.
    20. **Reporting the window size (§1.16) — done (2026-09-25, roadmap Plan 3).**
        A program that asks how big the window or a character cell is, in cells
        or pixels, now gets an answer (Claude Code asks for the cell size).
    ```
  - Replace the "Window title and other messages from programs" bullet (lines 134-135) with:
    ```markdown
    - **Window title and other messages from programs — done (2026-09-25,
      roadmap Plan 3):** what Claude says it is doing shows under the session
      name on the board and in the pane header; a program's own "done"
      notification pops up when that pane is not on screen.
    ```
  - Update the counts in line 7 ("the 17 marked **Partial**" → 16, and add "items 19 and 20 have since been done, roadmap Plan 3") and the heading on line 129 ("The 17 partly done items" → "The 16 partly done items"). If a parallel plan already changed these numbers, adjust from the numbers you find.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add packages/terminal/CHANGELOG.md TERMINAL.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/terminal/2026-09-24-not-done-plain-language.md
git commit -m "docs(terminal): messages from programs (roadmap Plan 3)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git status --short
```

---

### Task 12: Push and report

- [ ] **Step 1: Whole-branch review** — dispatch one review subagent over `git diff origin/development...HEAD` with this plan's Global Constraints and Review Focus; fix what it finds (new commits, same trailer), re-running the affected Task 10 gates.

- [ ] **Step 2: Push, do not merge**

```bash
cd "$(git rev-parse --show-toplevel)" && git push -u origin terminal/plan-3-program-messages && git log --oneline origin/development..HEAD
```
Expected: the push succeeds; the log shows the task commits. Do not open a merge, do not push to `development` or `master`.

- [ ] **Step 3: Completion report** (reply text, not a file). Include:
  1. Branch, head commit, and `git log --oneline origin/development..HEAD`.
  2. Every Task 10 gate with its quoted final output line, or `not run: <reason>`; the Task 0 baseline counts beside the final ones; the Task 0 and Task 10 `vt_host.wasm` hashes.
  3. Any line-number drift or deviation from this plan, and why.
  4. **Real-app checklist for the reviewer** (the cloud session cannot run the desktop app; write "not run: no desktop" for each):
     - Rebuild the daemon (`npm --prefix frontend run build:daemon`), restart the daemon **and** the app (old pty-hosts keep their old wasm — `TERMINAL.md` §3.5), start a new Claude Code session and give it a task. While it works, the board card shows Claude's task title under the session name (no `◐`/`✳` glyph) and the same title appears in the pane header; it updates when Claude starts a new task and is gone after "Relaunch in a cleared session" until Claude sets a new one.
     - Close the app window's pane for that session (open another session) and check the card still updates.
     - Open a shell from the session card ("Open terminal"), run `sleep 5; printf '\e]9;hello\a'` in it and within five seconds switch that pane to another tab: a desktop notification titled with the shell's name and body "hello" appears. Run the same command and stay on the shell (window focused): nothing appears. Run it again and switch to another app: it appears (the window is not focused).
     - In a shell pane: `printf '\e[18t'; read -rs -t1 -d t r; echo "$r"` prints `^[[8;<rows>;<cols>`; `printf '\e]11;?\a'; read -rs -t1 -d $'\a' r; echo "$r" | od -c | head -2` shows `]11;rgb:1d1d/2020/2222` (the charcoal background); `printf '\e]22;pointer\a'` turns the pointer over the transcript into a hand and `printf '\e]22;\a'` restores the arrow.

