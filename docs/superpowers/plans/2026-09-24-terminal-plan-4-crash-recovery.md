# Terminal Plan 4 — Crash Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A session terminal whose pty-host stops answering is noticed within ~15 s, the pane says "This terminal stopped responding." with a **Restart terminal** button, and a pty-host that dies no longer takes the terminal's history with it.

**Architecture:** Part A (hung detection, independently shippable): the pty-host runtime adapter counts consecutive failed liveness probes per host (the reaper already probes every live session every 5 s); at 3 in a row the host is `hung`, the terminal mux pushes a `health` frame to the panes viewing it, and the pane offers Restart, which calls a new `POST /api/v1/sessions/{id}/restart-terminal` that force-stops the host (`Runtime.Destroy`, which SIGKILLs a stopped process) and relaunches the agent in a fresh host through the existing relaunch path. Part B (history persistence): every pty-host writes its mirror's attach replay (frame + newest 20 history chunks, ≤ 4 MiB) to `~/.operator/pty-host-history/<session>.vt` every 60 s when it changed and on shutdown; a host created for a relaunched session feeds that file into its fresh mirror before the child's first byte, followed by the respawn process-boundary mark, so every attach replays the old history above the new process.

**Tech Stack:** Go 1.25 (backend daemon, pty-host, wazero-hosted `vt_host.wasm` mirror), React 19 + TypeScript + vitest (renderer), OpenAPI code-first generation (`npm run api`).

**Spec:** `docs/terminal/2026-09-24-terminal-roadmap-design.md` — "Plan 4 — Crash recovery (§6.3)" and "Rules every plan obeys"; survey entry `docs/terminal/2026-09-19-terminal-reference-survey.md` §6.3. Read `TERMINAL.md` end to end before Task 2.

**Parts:** Tasks 0–6 are **Part A** (hung detection + Restart terminal) and ship on their own. Tasks 7–8 are **Part B** (history persistence). Task 9 is docs, Task 10 the final gates and push. If Part B hits a blocker, stop after Task 6, do Task 9 for Part A only, and report Part B as not done with the reason.

## Global Constraints

- Branch: `terminal/plan-4-crash-recovery`, created from `origin/development`. Push it; **do not merge**, do not open a PR unless asked.
- **No comments in new code** (user's global rule, `TERMINAL.md` §3.3). Existing comments may be corrected only when they become false (Task 6 corrects one: the frame list at the top of `terminal-mux.ts`).
- Commit with explicit paths only: `git add <path> <path> …`. Never `git add -A`, `git add .`, `git commit -a`, or `git stash`.
- Every commit message ends with the line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Conventional prefixes (`feat:`, `test:`, `docs:`).
- Docs and reports cite `file:line` or write "not known". Never count from a piped listing without saying which command produced the number.
- Never copy Kitty (GPL-3) or Warp (AGPL-3) code. VS Code (MIT) is followed for **behaviour only** (a 5 s heartbeat that marks the pty host unresponsive, survey §6.3 citing `vscode/src/vs/platform/terminal/common/terminal.ts:461-470`); no VS Code code is adapted, so no attribution file is added.
- `packages/terminal` is not touched by this plan. If you find yourself editing it, stop: the plan is wrong.
- Do not store derived status (`AGENTS.md`, "Hard rules"): `hung` lives only in the daemon's memory; it is never written to SQLite.
- Never auto-kill a hung host: only the user's Restart terminal action stops it.
- Line numbers below were verified at commit `20bf1e58c` on `development`. If a number has drifted, find the place by the quoted anchor text — the anchors are exact.
- Use absolute paths in commands. The repo root is written `$REPO` below; set it once per shell: `export REPO="$(git rev-parse --show-toplevel)"`.
- When a tool or runtime is unavailable in the cloud session, do not improvise: record `not run: <reason>` for that gate and continue.

## Review Focus

1. **A busy host, not a hung one.** A pty-host that is merely slow for one probe (a status probe renders a full attach replay under the host lock, `host.go:851`, measured ~24 ms per call at 60k rows with `claude-long-50k`) must never be called hung. Pinned by `TestSlowProbesBetweenAnswersNeverMarkAHostHung` (Task 2): only 3 *consecutive* failed probes count.
2. **A host that wakes up (SIGCONT) before the user clicks.** The pane must drop the hung strip by itself. Pinned by `TestAHungHostThatAnswersAgainIsHealthy` (Task 2) and `TestServePushesAHungTerminalToItsViewersOnly` (Task 3, the `ok` frame).
3. **A pane opened after the host already hung.** It must be told at once, not after the next state change. Pinned by `TestServeTellsANewViewerOfAHungTerminalAtOnce` (Task 3) and the frontend test "reconnects after a restart even when the hung attachment already exited" (Task 6).
4. **A reused session id picking up someone else's history.** A fresh session (spawn, shell, reviewer) must never be seeded from a stale file. Pinned by `TestCreateDropsAStaleHistoryForAFreshSession` (Task 8); a relaunch keeps it: `TestCreateKeepsTheHistoryOfARestoredSession`, `TestRelaunchedHostsRestoreTheirHistory`.
5. **Disk growth.** One file per terminal ever opened would grow forever. Per-file cap pinned by `TestAPersistedHistoryStaysUnderItsByteCap`; files of gone hosts older than 7 days removed by `TestPruneHistoryRemovesOnlyOldFilesOfGoneHosts` (Task 7).

Real-app items no unit test can pin (the reviewer runs them locally, Task 10 lists them): the pane after a restart receives the new host's replay into its existing renderer core, exactly as after **Restore** today (`TerminalPane.tsx:156` keys a worker pane's cache by handle id, and the handle id is unchanged), so check for duplicated rows; and what the board shows (nothing new — see "Decisions" below).

## Decisions (made here, with evidence — do not revisit)

| # | Decision | Evidence |
|---|---|---|
| D1 | Hung = **3 consecutive failed liveness probes** of the same host, counted in the pty-host runtime adapter (`Runtime.IsAlive`). No new probe loop. | The reaper already probes every non-terminated session every `DefaultTickInterval = 5 * time.Second` (`backend/internal/observe/reaper/reaper.go:20`, wired with no Tick override at `backend/internal/daemon/lifecycle_wiring.go:64`) through `IsAlive` (`reaper.go:205`). A SIGSTOPped host still accepts TCP (kernel backlog) and never answers, so `clientStatus` fails on its 2 s read deadline (`client.go:26,267`) and returns a transient error (`client.go:319-321`). Lifecycle deliberately ignores `ProbeFailed` (`ports/runtime_observations.go:13-14`; `lifecycle/manager.go:472-520` only acts on `ProbeDead` or workload death) and `AGENTS.md` forbids storing derived status, so the count cannot live in lifecycle. A second heartbeat loop would double the per-probe replay render (`host.go:851`). Time to hung: 3 ticks × 5 s (+ up to 2 s per timed-out probe) ≈ 12–17 s. |
| D2 | Only **session** terminals are detected. Standalone shells and reviewer terminals are not probed and never show the hung strip. | The reaper iterates session rows only (`reaper.go:143-166`, `handleFromRecord` reads `Metadata.RuntimeHandleID`, `reaper.go:243-248`). Restart is a session operation. Recorded as a known gap in `TERMINAL.md` §5 (Task 9). |
| D3 | The daemon pushes health on the existing mux: a new server frame `{"ch":"terminal","id":<handle>,"type":"health","health":"hung"|"ok"}` to every connection viewing that handle, and once on `open` when the handle is already hung. | Panes already learn per-terminal state from `ch:"terminal"` frames (`terminal/protocol.go:44-57`; `frontend/src/renderer/lib/terminal-mux.ts:272-289`). The mobile client ignores unknown `terminal` types (`packages/mobile/lib/core/mux/mux_client.dart:230-250`), so it needs no change. |
| D4 | Restart terminal = `Runtime.Destroy(handle)` then the existing `relaunchSession(..., &handle, grid)` (native resume where the harness supports it). New route `POST /api/v1/sessions/{sessionId}/restart-terminal` with optional body `{cols, rows}`. | The roadmap says "restart through the existing respawn path (`respawn.go`)". That path cannot work for a hung host: `respawn.go` runs *inside* the host (`handleRespawn`, `respawn.go:27`), which is the stopped process, and `restartRuntime` fails first because `IsAlive` returns a transient error (`session_manager/manager.go:1482-1487`). `Destroy` already force-kills a host that ignores the graceful kill: kill frame, 500 ms wait, then `process.Kill()` (SIGKILL works on a stopped process) and a second wait (`runtime.go:131-169`). After it, `IsAlive` resolves nothing and returns `(false, nil)` (`runtime.go:270-273`), so `restartRuntime` falls through to `Create` with the same session id (`manager.go:1502`), i.e. the same handle id, so the mux terminal id is unchanged. |
| D5 | The restart holds the session's exclusive-operation lock (`beginAgentOperation`) for its whole duration. | While the old host is gone the reaper sees `ProbeDead`; `SessionMutationInProgress` makes lifecycle skip termination (`lifecycle/manager.go:502-504`, `session_manager/session_input.go:69-73`). |
| D6 | The board is **not** changed. The session's own pane is where the state shows. | Showing `hung` on the board needs a read-time runtime join in `SessionView` (`httpd/controllers/sessions.go:2110`), a new API field and a push trigger (the board refreshes on CDC/SSE events, and `hung` is not a DB change). Deferred; listed in `TERMINAL.md` §5 by Task 9. |
| D7 | Persisted history = the exact bytes a history-opted-in client receives on attach: `vt_replay` frame (`Replay(MaxOutputLines)`) then history chunks newest→oldest, at most **20 chunks** (20 × 512 = 10,240 rows) and **4 MiB**, file header `OPRVT1\n`. Seeding = `Feed(file)` then `Feed(respawnBoundary(0, false))` into the fresh mirror, then discard query replies. | Measured read-only 2026-09-24 on `claude-long-50k` (60,097 mirror rows, `go test -run TestAgentSessionReplayReport` with `OPERATOR_AGENT_FIXTURE`, plus an overlay test): frame 17,318 B; full history 116 chunks / 937,856 B but **2.73 s** to render (each `vt_history_chunk` snapshots the whole core, `packages/terminal/crates/vt-host/src/lib.rs:470`, ~23 ms per chunk); 20 chunks = 179,607 B in **491 ms**; 1 chunk 52 ms. At a 60 s interval 20 chunks cost < 1 % of a core on the largest recorded session. Feeding frame + chunks + boundary into a fresh mirror reconstructs every row and puts new output after it (overlay experiment: 3,000 lines, all present, new child output last). The reconstruction path is the one `TestAgentSessionReplayReport` already uses (`vtwasm/agent_session_test.go:151-164`). |
| D8 | Interval **60 s**, only when the mirror was fed since the last write, plus one write on graceful shutdown. Writes are atomic (`<id>.vt.tmp` then rename). File location `~/.operator/pty-host-history/<session>.vt`. | Same home-dir convention as the host's own logs (`host_main.go:192-200`, `~/.operator/pty-host-logs`) and the registry (`ptyregistry/registry.go:30-36`). A SIGKILLed or SIGSTOPped host loses at most the last minute. |
| D9 | The daemon decides who may read a file: `ports.RuntimeConfig.RestoreHistory`. `Runtime.Create` deletes the session's file unless `RestoreHistory` is true; only the session manager's relaunch path (`relaunchSessionWithPolicy`, used by restore, resume, relaunch and restart-terminal) sets it. `Create` also prunes files older than 7 days whose host is not in the live registry. The host always seeds when a file exists. | Session ids can be reused after a database reset (`daemon/lifecycle_wiring.go:190-194` explains why ids outlive the DB). Keeping the decision in the daemon avoids changing the `hostSpawner` signature (`spawn.go:18`; `grep -rn "env map\[string\]string, cols, rows int" backend/internal` matches 11 lines in 8 files, spawners and the `newPTY` it feeds). |

---

## File map

**Part A**
- Create `backend/internal/ports/terminal_health.go` — `TerminalHealth`, `TerminalHealthReader`.
- Create `backend/internal/adapters/runtime/ptyhost/health.go` — probe counting, watchers.
- Create `backend/internal/adapters/runtime/ptyhost/health_test.go`.
- Modify `backend/internal/adapters/runtime/ptyhost/client.go:251-267` — `clientStatusWithin`.
- Modify `backend/internal/adapters/runtime/ptyhost/runtime.go:29-33,44-54,57-71,161-163,269-275`.
- Create `backend/internal/terminal/health.go`, `backend/internal/terminal/health_test.go`.
- Modify `backend/internal/terminal/protocol.go:51,107`, `backend/internal/terminal/manager.go:75,146-147,191-194,514`.
- Modify `backend/internal/session_manager/session_input.go:21`, `backend/internal/session_manager/manager.go:1322` (insert before).
- Create `backend/internal/session_manager/restart_terminal_test.go`.
- Modify `backend/internal/service/session/service.go:61,384`, `backend/internal/service/session/service_test.go:1194,1236,1789`.
- Modify `backend/internal/httpd/controllers/dto.go:613`, `backend/internal/httpd/controllers/sessions.go:91,227,1092-1097,1211`, `backend/internal/httpd/controllers/sessions_test.go:86,263,2611`.
- Modify `backend/internal/httpd/apispec/specgen/build.go:214,1776-1789`; regenerate `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts`.
- Modify `frontend/src/renderer/lib/terminal-mux.ts`, `frontend/src/renderer/lib/terminal-mux.test.ts`.
- Modify `frontend/src/renderer/hooks/useTerminalSession.ts`, `frontend/src/renderer/hooks/useTerminalSession.test.tsx`.
- Create `frontend/src/renderer/hooks/useRestartTerminal.ts`.
- Modify `frontend/src/renderer/components/TerminalPane.tsx`, `frontend/src/renderer/components/TerminalPane.test.tsx`.
- Modify `frontend/src/renderer/i18n/en.json:942`, `frontend/src/renderer/lib/api-client.ts:100`.

**Part B**
- Create `backend/internal/adapters/runtime/ptyhost/persist.go`, `persist_test.go`, `persist_runtime_test.go`.
- Modify `backend/internal/adapters/runtime/ptyhost/host.go:48-51,221-223,350,386-389,618`, `host_main.go:170-179`, `runtime.go:95-98`.
- Modify `backend/internal/ports/outbound.go:131-133`, `backend/internal/session_manager/manager.go:1424-1431`, append to `restart_terminal_test.go`.

**Docs**
- Create `docs/superpowers/specs/2026-09-24-crash-recovery-measurement.md` (Task 1, completed in Task 9).
- Modify `TERMINAL.md` (§1 diagram, new §4.29, §5 bullets), `docs/terminal/2026-09-19-terminal-reference-survey.md:123,3672`, `docs/terminal/2026-09-24-not-done-plain-language.md:132-136,152`.

---

### Task 0: Branch, toolchain and baselines

**Files:** none changed.

- [ ] **Step 1: Create the branch**

```bash
cd "$(git rev-parse --show-toplevel)" && export REPO="$(pwd)"
git fetch origin && git checkout -b terminal/plan-4-crash-recovery origin/development
git log -1 --oneline
```
Expected: `Switched to a new branch 'terminal/plan-4-crash-recovery'` and one commit line.

- [ ] **Step 2: Check the Go toolchain**

```bash
grep -E '^go ' "$REPO/backend/go.mod"; go version
```
Expected: `go 1.25.7` and a `go1.25.x` (or newer) toolchain. If `go` is older than 1.25, run `go install golang.org/dl/go1.25.7@latest && go1.25.7 download` and use `go1.25.7` in place of `go` for the rest of the plan; if that is impossible, every Go gate is `not run: no Go 1.25 toolchain`.

- [ ] **Step 3: Backend baseline (record, do not fix)**

```bash
mkdir -p "$HOME/plan4-evidence"
cd "$REPO/backend" && go build ./... && go vet ./...
cd "$REPO/backend" && go test ./... 2>&1 | tee "$HOME/plan4-evidence/baseline-go-test.txt" | grep -E '^(FAIL|ok)' | grep '^FAIL' || echo "no failing packages"
cd "$REPO/backend" && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs 2>&1 | tail -3
```
Expected: build and vet print nothing; the test line prints failing packages or `no failing packages` (keep the list: later gates compare against it; `TERMINAL.md` §8 notes `TestProcessEnvironmentLetsOverridesWin` as a historical pre-existing failure); lint ends with `0 issues.`.

- [ ] **Step 4: Frontend toolchain and baseline**

The renderer typecheck and tests first build `packages/terminal`, which needs Rust 1.96.0 with the `wasm32-unknown-unknown` target and `wasm-bindgen-cli` 0.2.127 (`.github/workflows/frontend.yml:34-47`).

```bash
node --version
rustup toolchain install 1.96.0 --profile minimal --target wasm32-unknown-unknown
cargo install wasm-bindgen-cli --version 0.2.127 --locked
cd "$REPO" && npm ci
cd "$REPO/packages/terminal" && npm ci
cd "$REPO/frontend" && npm ci
cd "$REPO/frontend" && npm run typecheck 2>&1 | tail -3
cd "$REPO/frontend" && npx vitest run --config vite.renderer.config.ts src/renderer/components/TerminalPane.test.tsx src/renderer/hooks/useTerminalSession.test.tsx src/renderer/lib/terminal-mux.test.ts 2>&1 | tail -5
```
Expected: node ≥ 22 (CI uses 24); typecheck exits 0; vitest `Test Files  3 passed (3)`. If the Rust/wasm install fails, the typecheck gate becomes `not run: <error line>` for the whole plan, but still run the three targeted vitest files (they do not import `@operator/terminal-*`) and record their result.

---

### Task 1: Reproduce and measure before changing anything

**Files:**
- Create: `docs/superpowers/specs/2026-09-24-crash-recovery-measurement.md`

This needs a running daemon and, for the session half, an agent CLI. In a cloud session it may not be runnable; then record `not run: <reason>` in the note and move on — the reviewer repeats it locally on the desktop app.

- [ ] **Step 1: Build and start an isolated daemon**

```bash
export REPRO="$(mktemp -d)"
cd "$REPO/backend" && go build -o "$REPRO/opr" ./cmd/opr
for v in $(env | grep -oE '^CLAUDE[A-Z_]*'); do unset "$v"; done
OPERATOR_PORT=3102 OPERATOR_DATA_DIR="$REPRO/data" OPERATOR_RUN_FILE="$REPRO/running.json" \
  nohup "$REPRO/opr" daemon > "$REPRO/daemon.log" 2>&1 &
echo $! > "$REPRO/daemon.pid"
curl --retry 30 --retry-connrefused --retry-delay 1 -sf http://127.0.0.1:3102/healthz && echo " daemon up"
```
Expected: `daemon up`. (`opr daemon` is the hidden daemon command, `backend/internal/cli/root.go:315-325`; the pty-host is `opr pty-host`, so the daemon must be the built `opr` binary, not `go run .`.)

- [ ] **Step 2: Write the mux watcher**

```bash
cat > "$REPRO/mux-watch.mjs" <<'EOF'
const [, , url, id, seconds] = process.argv;
const ws = new WebSocket(url);
const t0 = Date.now();
ws.onopen = () => ws.send(JSON.stringify({ ch: "terminal", type: "open", id, cols: 100, rows: 30 }));
ws.onmessage = (event) => {
	const frame = JSON.parse(event.data);
	if (frame.ch !== "terminal") return;
	const detail = frame.type === "data" ? `${Buffer.from(frame.data, "base64").length} bytes` : (frame.error ?? frame.health ?? "");
	console.log(`${((Date.now() - t0) / 1000).toFixed(1)}s ${frame.type} ${detail}`);
};
setTimeout(() => {
	ws.close();
	process.exit(0);
}, Number(seconds) * 1000);
EOF
```

- [ ] **Step 3: Start a session (or record why not)**

```bash
mkdir -p "$REPRO/repo" && git -C "$REPRO/repo" init -q && git -C "$REPRO/repo" commit -q --allow-empty -m init
curl -s -X POST http://127.0.0.1:3102/api/v1/projects -H 'content-type: application/json' \
  -d "{\"path\":\"$REPRO/repo\",\"projectId\":\"repro\"}" | head -c 300; echo
curl -s -X POST http://127.0.0.1:3102/api/v1/sessions -H 'content-type: application/json' \
  -d '{"projectId":"repro","harness":"claude-code","prompt":"Reply with the word ready and wait."}' | tee "$REPRO/spawn.json" | head -c 400; echo
export SID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["session"]["id"])' "$REPRO/spawn.json")"; echo "SID=$SID"
```
Expected: a session id. If the spawn body is an error (no `claude` binary, not logged in), write the body into the note and skip to Step 6 (shell terminal only).

- [ ] **Step 4: Find the pty-host pid**

The registry is `~/.operator/windows-pty-hosts.json` (`ptyregistry/registry.go:27-36`; it is under `$HOME`, not `OPERATOR_DATA_DIR`).

```bash
export HOSTPID="$(python3 -c 'import json,os,sys;print([e["ptyHostPid"] for e in json.load(open(os.path.expanduser("~/.operator/windows-pty-hosts.json"))) if e["sessionId"]==sys.argv[1]][0])' "$SID")"
echo "HOSTPID=$HOSTPID"; ps -o pid,stat,command -p "$HOSTPID"
```
Expected: one `opr pty-host … <SID> …` process.

- [ ] **Step 5: SIGSTOP, observe 40 s, SIGCONT; then SIGKILL, observe**

```bash
node "$REPRO/mux-watch.mjs" ws://127.0.0.1:3102/mux "$SID" 45 > "$REPRO/stop-mux.txt" &
kill -STOP "$HOSTPID"; date +%T
timeout 40 tail -n 0 -f "$REPRO/daemon.log" > "$REPRO/stop-daemon.txt" || true
curl -s "http://127.0.0.1:3102/api/v1/sessions/$SID" > "$REPRO/stop-session.json"
kill -CONT "$HOSTPID"
cat "$REPRO/stop-mux.txt"; grep -iE 'probe|pty|terminal|reaper' "$REPRO/stop-daemon.txt" | head -20
python3 -c 'import json,sys;s=json.load(open(sys.argv[1]))["session"];print(s["status"],s.get("activity"),s["isTerminated"])' "$REPRO/stop-session.json"

node "$REPRO/mux-watch.mjs" ws://127.0.0.1:3102/mux "$SID" 30 > "$REPRO/kill-mux.txt" &
kill -KILL "$HOSTPID"; date +%T
timeout 30 tail -n 0 -f "$REPRO/daemon.log" > "$REPRO/kill-daemon.txt" || true
curl -s "http://127.0.0.1:3102/api/v1/sessions/$SID" > "$REPRO/kill-session.json"
cat "$REPRO/kill-mux.txt"; grep -iE 'probe|pty|terminal|reaper|terminat' "$REPRO/kill-daemon.txt" | head -20
python3 -c 'import json,sys;s=json.load(open(sys.argv[1]))["session"];print(s["status"],s.get("activity"),s["isTerminated"])' "$REPRO/kill-session.json"
```
Record every printed line in the note. What to expect before this plan (predicted from code, to be confirmed): SIGSTOP — the open pane gets no `exited`, no `error`, just silence; the reaper logs probe failures only at debug level (`reaper.go:214`), so the log likely shows nothing; the session stays live. SIGKILL — the attachment's read ends, `IsAlive` is refused → `exited` frame; after the 60 s recent-activity window the reaper terminates the session (`lifecycle/runtime.go:25-28`).

- [ ] **Step 6: Shell terminal (runs without an agent CLI)**

```bash
curl -s -X POST http://127.0.0.1:3102/api/v1/shell-terminals -H 'content-type: application/json' -d '{}' | tee "$REPRO/shell.json"; echo
export SHID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["shellTerminal"]["handleId"])' "$REPRO/shell.json")"
export SHPID="$(python3 -c 'import json,os,sys;print([e["ptyHostPid"] for e in json.load(open(os.path.expanduser("~/.operator/windows-pty-hosts.json"))) if e["sessionId"]==sys.argv[1]][0])' "$SHID")"
node "$REPRO/mux-watch.mjs" ws://127.0.0.1:3102/mux "$SHID" 25 > "$REPRO/shell-stop-mux.txt" &
kill -STOP "$SHPID"; timeout 25 tail -n 0 -f "$REPRO/daemon.log" > "$REPRO/shell-stop-daemon.txt" || true
kill -CONT "$SHPID"; cat "$REPRO/shell-stop-mux.txt"
```

- [ ] **Step 7: Stop everything**

```bash
kill "$(cat "$REPRO/daemon.pid")"
for p in $(pgrep -f "opr pty-host" || true); do ps -o command= -p "$p" | grep -q "$REPRO" && kill -KILL "$p"; done
pgrep -fl "$REPRO/opr" || echo "clean"
```
Expected: `clean`. (Hosts outlive the daemon by design; the loop kills only this run's hosts. Their registry entries are pruned automatically once their pids are gone, `ptyregistry/registry.go:146-160`.)

- [ ] **Step 8: Write the measurement note**

Create `docs/superpowers/specs/2026-09-24-crash-recovery-measurement.md` with this content, replacing every `<…>` with what Steps 1–7 printed, or with `not run: <reason>`:

```markdown
# Crash recovery — measurement (roadmap Plan 4)

**Date:** 2026-09-24. **Branch:** `terminal/plan-4-crash-recovery`. **Plan:** `docs/superpowers/plans/2026-09-24-terminal-plan-4-crash-recovery.md`.

## Before (Task 1)

Environment: <cloud Linux / macOS>, daemon `opr daemon` on 127.0.0.1:3102, isolated `OPERATOR_DATA_DIR`.

| Case | What the open pane received (mux frames) | Daemon log | `GET /sessions/<id>` (status, activity, isTerminated) |
|---|---|---|---|
| Session host SIGSTOP, 40 s | <…> | <…> | <…> |
| Session host SIGKILL, 30 s | <…> | <…> | <…> |
| Shell host SIGSTOP, 25 s | <…> | <…> | n/a (no session row) |

What the desktop pane and board show in each case: not known from this run (no desktop app in this session); the reviewer fills this in locally.

## Replay size and cost (read-only, 2026-09-24, `claude-long-50k`)

- Mirror rows at the product cap: 60,097. Attach frame (`Replay(1000)`): 17,318 bytes. Full history: 116 chunks, 937,856 bytes, 2,734 ms.
- Newest 20 chunks + frame: 179,607 bytes in 491 ms; 1 chunk + frame: 25,540 bytes in 52 ms. One `Replay(1000)` at 60k rows: ~24 ms.
- Command: `OPERATOR_AGENT_FIXTURE=$REPO/packages/terminal/bench/agent-session/fixtures/claude-long-50k go test ./internal/adapters/runtime/ptyhost/vtwasm/ -run TestAgentSessionReplayReport -v -count=1` (run from `backend/`).

## After (Task 10)

<filled by Task 10>
```

- [ ] **Step 9: Commit**

```bash
cd "$REPO" && git add docs/superpowers/specs/2026-09-24-crash-recovery-measurement.md
git commit -m "docs(terminal): measure a hung and a killed pty-host before crash recovery

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: The runtime marks a host hung after 3 failed probes (Part A)

**Files:**
- Create: `backend/internal/ports/terminal_health.go`
- Create: `backend/internal/adapters/runtime/ptyhost/health.go`
- Create: `backend/internal/adapters/runtime/ptyhost/health_test.go`
- Modify: `backend/internal/adapters/runtime/ptyhost/client.go:251-267`
- Modify: `backend/internal/adapters/runtime/ptyhost/runtime.go:29-33,44-54,57-71,161-163,269-275`

**Interfaces:**
- Produces (package `ports`): `type TerminalHealth string`; `const TerminalHealthy TerminalHealth = "ok"`; `const TerminalHung TerminalHealth = "hung"`; `type TerminalHealthReader interface { TerminalHealth(handle RuntimeHandle) TerminalHealth; WatchTerminalHealth(fn func(handleID string, health TerminalHealth)) (stop func()) }`.
- Produces (package `ptyhost`): `*Runtime` implements `ports.TerminalHealthReader`; `const hungAfterFailedProbes = 3`; `func clientStatusWithin(addr string, timeout time.Duration) (StatusPayload, bool, error)`; `Runtime.probeTimeout time.Duration` (default `isAliveTimeout`, 2 s).

- [ ] **Step 1: Write the port**

Create `backend/internal/ports/terminal_health.go`:

```go
package ports

type TerminalHealth string

const (
	TerminalHealthy TerminalHealth = "ok"
	TerminalHung    TerminalHealth = "hung"
)

type TerminalHealthReader interface {
	TerminalHealth(handle RuntimeHandle) TerminalHealth
	WatchTerminalHealth(fn func(handleID string, health TerminalHealth)) (stop func())
}
```

- [ ] **Step 2: Write the failing tests**

Create `backend/internal/adapters/runtime/ptyhost/health_test.go`:

```go
package ptyhost

import (
	"context"
	"net"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type healthEvent struct {
	id     string
	health ports.TerminalHealth
}

type healthRecorder struct {
	mu     sync.Mutex
	events []healthEvent
}

func (h *healthRecorder) record(id string, health ports.TerminalHealth) {
	h.mu.Lock()
	h.events = append(h.events, healthEvent{id: id, health: health})
	h.mu.Unlock()
}

func (h *healthRecorder) snapshot() []healthEvent {
	h.mu.Lock()
	defer h.mu.Unlock()
	return append([]healthEvent(nil), h.events...)
}

func silentHost(t *testing.T) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	var mu sync.Mutex
	var conns []net.Conn
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			mu.Lock()
			conns = append(conns, c)
			mu.Unlock()
		}
	}()
	t.Cleanup(func() {
		_ = ln.Close()
		mu.Lock()
		for _, c := range conns {
			_ = c.Close()
		}
		mu.Unlock()
	})
	return ln.Addr().String()
}

const silentProbeTimeout = 50 * time.Millisecond

func probingRuntime(t *testing.T, id, addr string) (*Runtime, *healthRecorder) {
	t.Helper()
	isolateRegistry(t)
	rt := New(Options{})
	rt.probeTimeout = silentProbeTimeout
	rt.sessions[id] = &hostSession{addr: addr, pid: livePID()}
	rec := &healthRecorder{}
	stop := rt.WatchTerminalHealth(rec.record)
	t.Cleanup(stop)
	return rt, rec
}

func probeAt(t *testing.T, rt *Runtime, id, addr string, timeout time.Duration) (bool, error) {
	t.Helper()
	rt.mu.Lock()
	rt.sessions[id].addr = addr
	rt.mu.Unlock()
	rt.probeTimeout = timeout
	return rt.IsAlive(context.Background(), ports.RuntimeHandle{ID: id})
}

func TestAHostThatStopsAnsweringIsHungAfterThreeFailedProbesNotBefore(t *testing.T) {
	silent := silentHost(t)
	rt, rec := probingRuntime(t, "stuck", silent)
	handle := ports.RuntimeHandle{ID: "stuck"}
	for i := 1; i <= 2; i++ {
		if _, err := probeAt(t, rt, "stuck", silent, silentProbeTimeout); err == nil {
			t.Fatalf("probe %d of a silent host returned no error", i)
		}
		if got := rt.TerminalHealth(handle); got != ports.TerminalHealthy {
			t.Fatalf("after %d failed probes health = %q, want %q", i, got, ports.TerminalHealthy)
		}
	}
	if events := rec.snapshot(); len(events) != 0 {
		t.Fatalf("health events before the third failed probe = %v, want none", events)
	}
	if _, err := probeAt(t, rt, "stuck", silent, silentProbeTimeout); err == nil {
		t.Fatal("third probe of a silent host returned no error")
	}
	if got := rt.TerminalHealth(handle); got != ports.TerminalHung {
		t.Fatalf("after 3 failed probes health = %q, want %q", got, ports.TerminalHung)
	}
	want := []healthEvent{{id: "stuck", health: ports.TerminalHung}}
	if events := rec.snapshot(); !reflect.DeepEqual(events, want) {
		t.Fatalf("health events = %v, want %v", events, want)
	}
	if _, err := probeAt(t, rt, "stuck", silent, silentProbeTimeout); err == nil {
		t.Fatal("fourth probe of a silent host returned no error")
	}
	if events := rec.snapshot(); !reflect.DeepEqual(events, want) {
		t.Fatalf("a fourth failed probe announced again: %v", events)
	}
}

func TestAHungHostThatAnswersAgainIsHealthy(t *testing.T) {
	silent := silentHost(t)
	rt, rec := probingRuntime(t, "stuck", silent)
	for range hungAfterFailedProbes {
		_, _ = probeAt(t, rt, "stuck", silent, silentProbeTimeout)
	}
	live := startServe(t, 4101)
	defer live.cancel()
	alive, err := probeAt(t, rt, "stuck", live.addr, isAliveTimeout)
	if err != nil || !alive {
		t.Fatalf("probe of the answering host = (%v, %v), want (true, nil)", alive, err)
	}
	if got := rt.TerminalHealth(ports.RuntimeHandle{ID: "stuck"}); got != ports.TerminalHealthy {
		t.Fatalf("health after an answered probe = %q, want %q", got, ports.TerminalHealthy)
	}
	want := []healthEvent{{id: "stuck", health: ports.TerminalHung}, {id: "stuck", health: ports.TerminalHealthy}}
	if events := rec.snapshot(); !reflect.DeepEqual(events, want) {
		t.Fatalf("health events = %v, want %v", events, want)
	}
}

func TestSlowProbesBetweenAnswersNeverMarkAHostHung(t *testing.T) {
	silent := silentHost(t)
	rt, rec := probingRuntime(t, "slow", silent)
	live := startServe(t, 4102)
	defer live.cancel()
	sequence := []string{silent, silent, live.addr, silent, silent, live.addr, silent}
	for i, addr := range sequence {
		timeout := silentProbeTimeout
		if addr == live.addr {
			timeout = isAliveTimeout
		}
		_, _ = probeAt(t, rt, "slow", addr, timeout)
		if got := rt.TerminalHealth(ports.RuntimeHandle{ID: "slow"}); got != ports.TerminalHealthy {
			t.Fatalf("after probe %d health = %q, want %q", i+1, got, ports.TerminalHealthy)
		}
	}
	if events := rec.snapshot(); len(events) != 0 {
		t.Fatalf("health events = %v, want none", events)
	}
}

func TestARefusedHostIsGoneNotHung(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	refused := ln.Addr().String()
	_ = ln.Close()
	rt, rec := probingRuntime(t, "gone", refused)
	for i := 1; i <= hungAfterFailedProbes+1; i++ {
		alive, err := probeAt(t, rt, "gone", refused, silentProbeTimeout)
		if alive || err != nil {
			t.Fatalf("probe %d of a refused host = (%v, %v), want (false, nil)", i, alive, err)
		}
	}
	if got := rt.TerminalHealth(ports.RuntimeHandle{ID: "gone"}); got != ports.TerminalHealthy {
		t.Fatalf("health of a refused host = %q, want %q", got, ports.TerminalHealthy)
	}
	if events := rec.snapshot(); len(events) != 0 {
		t.Fatalf("health events = %v, want none", events)
	}
}

func TestDestroyingAHungHostAnnouncesItHealthy(t *testing.T) {
	silent := silentHost(t)
	rt, rec := probingRuntime(t, "stuck", silent)
	for range hungAfterFailedProbes {
		_, _ = probeAt(t, rt, "stuck", silent, silentProbeTimeout)
	}
	rt.killHost = func(string) error { return nil }
	rt.pidIsAlive = func(int) bool { return false }
	if err := rt.Destroy(context.Background(), ports.RuntimeHandle{ID: "stuck"}); err != nil {
		t.Fatalf("Destroy: %v", err)
	}
	if got := rt.TerminalHealth(ports.RuntimeHandle{ID: "stuck"}); got != ports.TerminalHealthy {
		t.Fatalf("health after Destroy = %q, want %q", got, ports.TerminalHealthy)
	}
	want := []healthEvent{{id: "stuck", health: ports.TerminalHung}, {id: "stuck", health: ports.TerminalHealthy}}
	if events := rec.snapshot(); !reflect.DeepEqual(events, want) {
		t.Fatalf("health events = %v, want %v", events, want)
	}
}

func TestAStoppedHealthWatcherHearsNothing(t *testing.T) {
	isolateRegistry(t)
	silent := silentHost(t)
	rt := New(Options{})
	rt.sessions["stuck"] = &hostSession{addr: silent, pid: livePID()}
	rec := &healthRecorder{}
	stop := rt.WatchTerminalHealth(rec.record)
	stop()
	for range hungAfterFailedProbes {
		_, _ = probeAt(t, rt, "stuck", silent, silentProbeTimeout)
	}
	if got := rt.TerminalHealth(ports.RuntimeHandle{ID: "stuck"}); got != ports.TerminalHung {
		t.Fatalf("health = %q, want %q", got, ports.TerminalHung)
	}
	if events := rec.snapshot(); len(events) != 0 {
		t.Fatalf("a stopped watcher heard %v", events)
	}
}
```

- [ ] **Step 3: Run the tests to see them fail**

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ -run 'Hung|Health|Slow|Refused' -count=1 2>&1 | tail -5
```
Expected: `FAIL … [build failed]` with `rt.probeTimeout undefined` / `rt.WatchTerminalHealth undefined` / `undefined: hungAfterFailedProbes`.

- [ ] **Step 4: Split the status probe's timeout out of `clientStatus`**

In `backend/internal/adapters/runtime/ptyhost/client.go`, replace (lines 251-252):

```go
func clientStatus(addr string) (status StatusPayload, hostAlive bool, transientErr error) {
	conn, err := dialHost(addr, isAliveTimeout)
```
with:
```go
func clientStatus(addr string) (status StatusPayload, hostAlive bool, transientErr error) {
	return clientStatusWithin(addr, isAliveTimeout)
}

func clientStatusWithin(addr string, timeout time.Duration) (status StatusPayload, hostAlive bool, transientErr error) {
	conn, err := dialHost(addr, timeout)
```
and, a few lines further down in the same function (old line 267), replace:
```go
	_ = conn.SetDeadline(time.Now().Add(isAliveTimeout))

	statusReqFrame, _ := EncodeMessage(MsgStatusReq, nil) // nil payload, never overflows
```
with:
```go
	_ = conn.SetDeadline(time.Now().Add(timeout))

	statusReqFrame, _ := EncodeMessage(MsgStatusReq, nil) // nil payload, never overflows
```
(`clientKill` at line 411 also uses `isAliveTimeout`; leave it.)

- [ ] **Step 5: Add probe counting to the runtime**

In `backend/internal/adapters/runtime/ptyhost/runtime.go`:

Replace the `hostSession` struct (lines 29-33):
```go
type hostSession struct {
	addr     string
	pid      int
	launchID string
}
```
with:
```go
type hostSession struct {
	addr         string
	pid          int
	launchID     string
	failedProbes int
}
```

Replace (lines 49-54):
```go
	destroyWait   time.Duration
	destroyPoll   time.Duration

	mu       sync.Mutex
	sessions map[string]*hostSession // sessionID -> live session
}
```
with:
```go
	destroyWait   time.Duration
	destroyPoll   time.Duration
	probeTimeout  time.Duration

	mu       sync.Mutex
	sessions map[string]*hostSession // sessionID -> live session

	watchMu     sync.Mutex
	watchers    map[int]func(string, ports.TerminalHealth)
	nextWatcher int
}
```

Replace (lines 68-70):
```go
		destroyPoll:   25 * time.Millisecond,
		sessions:      make(map[string]*hostSession),
	}
```
with:
```go
		destroyPoll:   25 * time.Millisecond,
		probeTimeout:  isAliveTimeout,
		sessions:      make(map[string]*hostSession),
		watchers:      make(map[int]func(string, ports.TerminalHealth)),
	}
```

In `Destroy`, replace (lines 161-165):
```go
	r.mu.Lock()
	delete(r.sessions, handle.ID)
	r.mu.Unlock()

	if err := ptyregistry.Unregister(handle.ID); err != nil {
```
with:
```go
	r.mu.Lock()
	wasHung := sess.failedProbes >= hungAfterFailedProbes
	delete(r.sessions, handle.ID)
	r.mu.Unlock()
	if wasHung {
		r.notifyHealth(handle.ID, ports.TerminalHealthy)
	}

	if err := ptyregistry.Unregister(handle.ID); err != nil {
```

In `IsAlive`, replace (lines 272-274):
```go
		return false, nil // no in-memory entry, no registry entry -> definitively gone
	}
	return clientIsAlive(sess.addr)
}
```
with:
```go
		return false, nil // no in-memory entry, no registry entry -> definitively gone
	}
	_, alive, err := clientStatusWithin(sess.addr, r.probeTimeout)
	r.recordProbe(handle.ID, sess, err)
	return alive, err
}
```

Create `backend/internal/adapters/runtime/ptyhost/health.go`:

```go
package ptyhost

import "github.com/OmarAly92/operator/backend/internal/ports"

const hungAfterFailedProbes = 3

var _ ports.TerminalHealthReader = (*Runtime)(nil)

func (r *Runtime) TerminalHealth(handle ports.RuntimeHandle) ports.TerminalHealth {
	r.mu.Lock()
	defer r.mu.Unlock()
	if sess := r.sessions[handle.ID]; sess != nil && sess.failedProbes >= hungAfterFailedProbes {
		return ports.TerminalHung
	}
	return ports.TerminalHealthy
}

func (r *Runtime) WatchTerminalHealth(fn func(handleID string, health ports.TerminalHealth)) func() {
	r.watchMu.Lock()
	id := r.nextWatcher
	r.nextWatcher++
	r.watchers[id] = fn
	r.watchMu.Unlock()
	return func() {
		r.watchMu.Lock()
		delete(r.watchers, id)
		r.watchMu.Unlock()
	}
}

func (r *Runtime) recordProbe(handleID string, sess *hostSession, probeErr error) {
	r.mu.Lock()
	wasHung := sess.failedProbes >= hungAfterFailedProbes
	if probeErr != nil {
		sess.failedProbes++
	} else {
		sess.failedProbes = 0
	}
	isHung := sess.failedProbes >= hungAfterFailedProbes
	r.mu.Unlock()
	if wasHung == isHung {
		return
	}
	if isHung {
		r.notifyHealth(handleID, ports.TerminalHung)
		return
	}
	r.notifyHealth(handleID, ports.TerminalHealthy)
}

func (r *Runtime) notifyHealth(handleID string, health ports.TerminalHealth) {
	r.watchMu.Lock()
	fns := make([]func(string, ports.TerminalHealth), 0, len(r.watchers))
	for _, fn := range r.watchers {
		fns = append(fns, fn)
	}
	r.watchMu.Unlock()
	for _, fn := range fns {
		fn(handleID, health)
	}
}
```

- [ ] **Step 6: Run the tests to see them pass**

```bash
cd "$REPO/backend" && gofmt -l internal/ports internal/adapters/runtime/ptyhost
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ -run 'Hung|Health|Slow|Refused|IsAlive' -count=1 -race -v 2>&1 | grep -E '^(--- |ok|FAIL)'
```
Expected: `gofmt -l` prints nothing; 10 `--- PASS` lines (the six new tests plus `TestIsAlive_TrueWhileServing_FalseAfterClose`, `TestIsAlive_FalseForUnknownSession`, `TestClientIsAlive_TrueAndFalse`, `TestIsAlive_RefusedIsGone_TimeoutIsTransient`), then `ok`.

- [ ] **Step 7: Run the whole package**

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -4
```
Expected: `ok` for `ptyhost`, `ptyhost/ptyregistry`, `ptyhost/vtwasm` (or only the failures already in the Task 0 baseline).

- [ ] **Step 8: Commit**

```bash
cd "$REPO" && git add backend/internal/ports/terminal_health.go backend/internal/adapters/runtime/ptyhost/health.go backend/internal/adapters/runtime/ptyhost/health_test.go backend/internal/adapters/runtime/ptyhost/client.go backend/internal/adapters/runtime/ptyhost/runtime.go
git commit -m "feat(ptyhost): mark a pty-host hung after three failed liveness probes

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: The mux tells the panes (Part A)

**Files:**
- Create: `backend/internal/terminal/health.go`
- Create: `backend/internal/terminal/health_test.go`
- Modify: `backend/internal/terminal/protocol.go:51,107`
- Modify: `backend/internal/terminal/manager.go:75,146-147,191-194,514`

**Interfaces:**
- Consumes: `ports.TerminalHealthReader`, `ports.TerminalHealthy`, `ports.TerminalHung` (Task 2).
- Produces: server frame `serverMsg{Ch: "terminal", ID: <handle>, Type: "health", Health: "hung"|"ok"}`; `func healthFrame(handleID string, health ports.TerminalHealth) serverMsg`; `(*Manager).publishHealth`, `(*Manager).terminalHealth`.

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/terminal/health_test.go`:

```go
package terminal

import (
	"context"
	"encoding/base64"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type healthSource struct {
	*fakeSource
	mu       sync.Mutex
	health   map[string]ports.TerminalHealth
	watchers []func(string, ports.TerminalHealth)
	stopped  bool
}

func newHealthSource(src *fakeSource) *healthSource {
	return &healthSource{fakeSource: src, health: map[string]ports.TerminalHealth{}}
}

func (s *healthSource) TerminalHealth(handle ports.RuntimeHandle) ports.TerminalHealth {
	s.mu.Lock()
	defer s.mu.Unlock()
	if health, ok := s.health[handle.ID]; ok {
		return health
	}
	return ports.TerminalHealthy
}

func (s *healthSource) WatchTerminalHealth(fn func(string, ports.TerminalHealth)) func() {
	s.mu.Lock()
	s.watchers = append(s.watchers, fn)
	s.mu.Unlock()
	return func() {
		s.mu.Lock()
		s.stopped = true
		s.mu.Unlock()
	}
}

func (s *healthSource) set(id string, health ports.TerminalHealth) {
	s.mu.Lock()
	s.health[id] = health
	watchers := make([]func(string, ports.TerminalHealth), len(s.watchers))
	copy(watchers, s.watchers)
	s.mu.Unlock()
	for _, fn := range watchers {
		fn(id, health)
	}
}

func (s *healthSource) watchStopped() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.stopped
}

func awaitFrames(t *testing.T, c *fakeConn, d time.Duration, done func(serverMsg) bool) []serverMsg {
	t.Helper()
	deadline := time.After(d)
	var seen []serverMsg
	for {
		select {
		case m := <-c.out:
			seen = append(seen, m)
			if done(m) {
				return seen
			}
		case <-deadline:
			t.Fatalf("condition not met within %s; frames seen: %+v", d, seen)
			return nil
		}
	}
}

func assertNoHealthFrame(t *testing.T, c *fakeConn, d time.Duration) {
	t.Helper()
	deadline := time.After(d)
	for {
		select {
		case m := <-c.out:
			if m.Type == msgHealth {
				t.Fatalf("unexpected health frame %+v", m)
			}
		case <-deadline:
			return
		}
	}
}

func isHealth(id, health string) func(serverMsg) bool {
	return func(m serverMsg) bool {
		return m.Ch == chTerminal && m.Type == msgHealth && m.ID == id && m.Health == health
	}
}

func TestServePushesAHungTerminalToItsViewersOnly(t *testing.T) {
	src := newHealthSource(&fakeSource{alive: true, spawner: &fakeSpawner{}})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	viewer := newFakeConn()
	go mgr.Serve(ctx, viewer)
	viewer.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, viewer, chTerminal, msgOpened, time.Second)

	bystander := newFakeConn()
	go mgr.Serve(ctx, bystander)
	bystander.in <- clientMsg{Ch: chTerminal, ID: "t2", Type: msgOpen}
	recv(t, bystander, chTerminal, msgOpened, time.Second)

	src.set("t1", ports.TerminalHung)
	awaitFrames(t, viewer, time.Second, isHealth("t1", "hung"))
	assertNoHealthFrame(t, bystander, 100*time.Millisecond)

	src.set("t1", ports.TerminalHealthy)
	awaitFrames(t, viewer, time.Second, isHealth("t1", "ok"))
}

func TestServeTellsANewViewerOfAHungTerminalAtOnce(t *testing.T) {
	src := newHealthSource(&fakeSource{alive: true, spawner: &fakeSpawner{}})
	src.health["t1"] = ports.TerminalHung
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	conn := newFakeConn()
	go mgr.Serve(ctx, conn)
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	awaitFrames(t, conn, time.Second, isHealth("t1", "hung"))
}

func TestServeKeepsTheClientAttachedAcrossAHostRestart(t *testing.T) {
	before := newFakePTY()
	after := newFakePTY()
	src := newHealthSource(&fakeSource{alive: true, spawner: &fakeSpawner{ptys: []*fakePTY{before, after}}})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	defer mgr.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	conn := newFakeConn()
	go mgr.Serve(ctx, conn)
	conn.in <- clientMsg{Ch: chTerminal, ID: "t1", Type: msgOpen}
	recv(t, conn, chTerminal, msgOpened, time.Second)

	src.set("t1", ports.TerminalHung)
	awaitFrames(t, conn, time.Second, isHealth("t1", "hung"))

	_ = before.Close()
	src.set("t1", ports.TerminalHealthy)
	after.push([]byte("after restart"))
	seen := awaitFrames(t, conn, 3*time.Second, func(m serverMsg) bool {
		if m.Type != msgData {
			return false
		}
		got, _ := base64.StdEncoding.DecodeString(m.Data)
		return string(got) == "after restart"
	})
	sawHealthy := false
	for _, m := range seen {
		if m.Type == msgExited {
			t.Fatalf("the client was told the terminal exited during a host restart: %+v", seen)
		}
		if isHealth("t1", "ok")(m) {
			sawHealthy = true
		}
	}
	if !sawHealthy {
		t.Fatalf("the client never heard the restarted host is healthy: %+v", seen)
	}
}

func TestManagerCloseStopsTheHealthWatch(t *testing.T) {
	src := newHealthSource(&fakeSource{alive: true, spawner: &fakeSpawner{}})
	mgr := NewManager(src, nil, testLogger(), WithHeartbeat(0))
	mgr.Close()
	if !src.watchStopped() {
		t.Fatal("Close left the runtime health watch running")
	}
}
```

- [ ] **Step 2: Run to see them fail**

```bash
cd "$REPO/backend" && go test ./internal/terminal/ -run 'Health|Hung|HostRestart' -count=1 2>&1 | tail -5
```
Expected: `[build failed]` with `undefined: msgHealth` and `m.Health undefined`.

- [ ] **Step 3: Add the frame to the protocol**

In `backend/internal/terminal/protocol.go`, replace (line 51):
```go
	msgBlock      = "block"    // ch "blocks"
```
with:
```go
	msgBlock      = "block"    // ch "blocks"
	msgHealth     = "health"
```
and replace (lines 107-108):
```go
	Error   string         `json:"error,omitempty"`
	Session *sessionUpdate `json:"session,omitempty"`
```
with:
```go
	Error   string         `json:"error,omitempty"`
	Health  string         `json:"health,omitempty"`
	Session *sessionUpdate `json:"session,omitempty"`
```

- [ ] **Step 4: Watch the runtime and publish**

Create `backend/internal/terminal/health.go`:

```go
package terminal

import "github.com/OmarAly92/operator/backend/internal/ports"

func (m *Manager) startHealthWatch() {
	reader, ok := m.src.(ports.TerminalHealthReader)
	if !ok {
		return
	}
	m.stopHealthWatch = reader.WatchTerminalHealth(m.publishHealth)
}

func (m *Manager) publishHealth(handleID string, health ports.TerminalHealth) {
	if health == ports.TerminalHung {
		m.log.Warn("terminal host stopped responding", "id", handleID)
	} else {
		m.log.Info("terminal host is responding again", "id", handleID)
	}
	m.sharedMu.Lock()
	var conns []*connState
	if s := m.shared[handleID]; s != nil {
		conns = make([]*connState, 0, len(s.members))
		for c := range s.members {
			conns = append(conns, c)
		}
	}
	m.sharedMu.Unlock()
	for _, c := range conns {
		c.enqueue(healthFrame(handleID, health))
	}
}

func (m *Manager) terminalHealth(handleID string) ports.TerminalHealth {
	reader, ok := m.src.(ports.TerminalHealthReader)
	if !ok {
		return ports.TerminalHealthy
	}
	return reader.TerminalHealth(ports.RuntimeHandle{ID: handleID})
}

func healthFrame(handleID string, health ports.TerminalHealth) serverMsg {
	return serverMsg{Ch: chTerminal, ID: handleID, Type: msgHealth, Health: string(health)}
}
```

In `backend/internal/terminal/manager.go`:

Replace (lines 74-76):
```go
	notificationFeed     NotificationFeed
	stopNotificationFeed func()
}
```
with:
```go
	notificationFeed     NotificationFeed
	stopNotificationFeed func()

	stopHealthWatch func()
}
```

Replace (lines 146-148):
```go
	m.startNotificationFeed()
	return m
}
```
with:
```go
	m.startNotificationFeed()
	m.startHealthWatch()
	return m
}
```

In `Close`, replace (lines 192-195):
```go
	if m.stopNotificationFeed != nil {
		m.stopNotificationFeed()
	}
	m.mu.Lock()
```
with:
```go
	if m.stopNotificationFeed != nil {
		m.stopNotificationFeed()
	}
	if m.stopHealthWatch != nil {
		m.stopHealthWatch()
	}
	m.mu.Lock()
```

In `openTerminal`, replace (line 514):
```go
	c.mgr.joinTerminal(id, c, a, cols, rows, role != roleSecondary)
```
with:
```go
	c.mgr.joinTerminal(id, c, a, cols, rows, role != roleSecondary)
	if c.mgr.terminalHealth(id) == ports.TerminalHung {
		c.enqueue(healthFrame(id, ports.TerminalHung))
	}
```

- [ ] **Step 5: Run to see them pass, then the whole package**

```bash
cd "$REPO/backend" && gofmt -l internal/terminal
cd "$REPO/backend" && go test ./internal/terminal/ -run 'Health|Hung|HostRestart' -count=1 -race -v 2>&1 | grep -E '^(--- |ok|FAIL)'
cd "$REPO/backend" && go test ./internal/terminal/... ./internal/daemon/... -count=1 2>&1 | tail -4
```
Expected: no gofmt output; 4 `--- PASS`, `ok`; then `ok` for `internal/terminal` and `internal/daemon`.

- [ ] **Step 6: Commit**

```bash
cd "$REPO" && git add backend/internal/terminal/health.go backend/internal/terminal/health_test.go backend/internal/terminal/protocol.go backend/internal/terminal/manager.go
git commit -m "feat(terminal): push a hung pty-host to the panes viewing it

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Restart a hung terminal in the session manager (Part A)

**Files:**
- Modify: `backend/internal/session_manager/session_input.go:21`
- Modify: `backend/internal/session_manager/manager.go` (insert before line 1322, `// relaunchPolicy selects how a relaunch rebuilds the agent's conversation.`)
- Create: `backend/internal/session_manager/restart_terminal_test.go`

**Interfaces:**
- Produces: `func (m *Manager) RestartTerminal(ctx context.Context, id domain.SessionID, grid ports.PaneGrid) (RestoreResult, error)`. Errors: `ErrNotFound`, `ErrTerminated`, `ErrIncompleteHandle`, `ErrSwitchInProgress` (any exclusive operation in progress, the same mapping `Kill`/`RestoreWithMode`/`RelaunchAgentFresh` use, `manager.go:1052-1054`), or the wrapped `Destroy` error.

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/session_manager/restart_terminal_test.go`:

```go
package sessionmanager

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func newHungTerminalManager(t *testing.T, runtime *fakeRuntime) (*Manager, *fakeStore) {
	t.Helper()
	agent := supervisedLaunchAgent{launchArgvAgent{argv: []string{"codex", "resume", "agent-x"}}}
	m, st, _ := newExitedResumeManager(t, runtime, agent)
	rec := st.sessions["mer-1"]
	rec.Activity.State = domain.ActivityIdle
	st.sessions["mer-1"] = rec
	return m, st
}

func TestRestartTerminal_StopsTheHungHostAndStartsAFreshOne(t *testing.T) {
	runtime := &fakeRuntime{aliveByHandle: map[string]bool{"pty-mer-1": true}, aliveErr: errors.New("read tcp 127.0.0.1:1: i/o timeout")}
	runtime.onDestroy = func(int, ports.RuntimeHandle) { runtime.aliveErr = nil }
	m, st := newHungTerminalManager(t, runtime)

	result, err := m.RestartTerminal(ctx, "mer-1", ports.PaneGrid{Cols: 132, Rows: 43})
	if err != nil {
		t.Fatalf("RestartTerminal: %v", err)
	}
	if !reflect.DeepEqual(runtime.destroyedIDs, []string{"pty-mer-1"}) || runtime.created != 1 {
		t.Fatalf("runtime lifecycle: destroyed=%v created=%d, want the hung host destroyed and one fresh host", runtime.destroyedIDs, runtime.created)
	}
	if runtime.lastCfg.Cols != 132 || runtime.lastCfg.Rows != 43 {
		t.Fatalf("fresh host grid = %dx%d, want 132x43", runtime.lastCfg.Cols, runtime.lastCfg.Rows)
	}
	got := st.sessions["mer-1"]
	if got.IsTerminated {
		t.Fatalf("restart terminated the session: %+v", got)
	}
	if got.Metadata.RuntimeHandleID != "h1" || got.Metadata.RuntimeLaunchID != "launch-new" {
		t.Fatalf("restarted metadata = %+v, want the fresh host's handle and launch", got.Metadata)
	}
	if result.Mode != RestoreModeNative {
		t.Fatalf("restart mode = %q, want native", result.Mode)
	}
}

func TestRestartTerminal_RejectsATerminatedSession(t *testing.T) {
	runtime := &fakeRuntime{aliveByHandle: map[string]bool{"pty-mer-1": true}}
	m, st := newHungTerminalManager(t, runtime)
	rec := st.sessions["mer-1"]
	rec.IsTerminated = true
	st.sessions["mer-1"] = rec

	if _, err := m.RestartTerminal(ctx, "mer-1", ports.PaneGrid{}); !errors.Is(err, ErrTerminated) {
		t.Fatalf("restart of a terminated session = %v, want ErrTerminated", err)
	}
	if runtime.destroyed != 0 || runtime.created != 0 {
		t.Fatalf("a rejected restart touched the runtime: destroyed=%d created=%d", runtime.destroyed, runtime.created)
	}
}

func TestRestartTerminal_KeepsTheSessionWhenTheHostCannotBeStopped(t *testing.T) {
	runtime := &fakeRuntime{
		aliveByHandle: map[string]bool{"pty-mer-1": true},
		destroyErr:    errors.New("ptyhost: pty-host pid 42 is still alive after teardown"),
	}
	m, st := newHungTerminalManager(t, runtime)

	_, err := m.RestartTerminal(ctx, "mer-1", ports.PaneGrid{})
	if err == nil || !strings.Contains(err.Error(), "still alive") {
		t.Fatalf("restart error = %v, want the teardown failure", err)
	}
	if runtime.created != 0 {
		t.Fatalf("created %d hosts after the old one could not be stopped", runtime.created)
	}
	got := st.sessions["mer-1"]
	if got.IsTerminated || got.Metadata.RuntimeHandleID != "pty-mer-1" || got.Metadata.RuntimeLaunchID != "launch-old" {
		t.Fatalf("a failed restart changed the session: %+v", got)
	}
}

func TestRestartTerminal_RejectsAConcurrentOperation(t *testing.T) {
	entered := make(chan struct{})
	release := make(chan struct{})
	runtime := &fakeRuntime{aliveByHandle: map[string]bool{"pty-mer-1": true}}
	runtime.onDestroy = func(int, ports.RuntimeHandle) {
		close(entered)
		<-release
	}
	m, _ := newHungTerminalManager(t, runtime)

	firstDone := make(chan error, 1)
	go func() {
		_, err := m.RestartTerminal(ctx, "mer-1", ports.PaneGrid{})
		firstDone <- err
	}()
	<-entered
	if !m.SessionMutationInProgress("mer-1") {
		t.Fatal("a restart in progress must suppress observation-driven termination")
	}
	if _, err := m.RestartTerminal(ctx, "mer-1", ports.PaneGrid{}); !errors.Is(err, ErrSwitchInProgress) {
		t.Fatalf("concurrent restart = %v, want ErrSwitchInProgress", err)
	}
	close(release)
	if err := <-firstDone; err != nil {
		t.Fatalf("first restart: %v", err)
	}
}
```

- [ ] **Step 2: Run to see them fail**

```bash
cd "$REPO/backend" && go test ./internal/session_manager/ -run RestartTerminal -count=1 2>&1 | tail -3
```
Expected: `[build failed]`, `m.RestartTerminal undefined`.

- [ ] **Step 3: Implement**

In `backend/internal/session_manager/session_input.go`, replace (lines 21-22):
```go
	agentOperationRelaunch agentOperationKind = "relaunch"
)
```
with:
```go
	agentOperationRelaunch agentOperationKind = "relaunch"

	agentOperationRestartTerminal agentOperationKind = "restart-terminal"
)
```

In `backend/internal/session_manager/manager.go`, replace the line (1322):
```go
// relaunchPolicy selects how a relaunch rebuilds the agent's conversation.
```
with:
```go
func (m *Manager) RestartTerminal(ctx context.Context, id domain.SessionID, grid ports.PaneGrid) (RestoreResult, error) {
	if err := m.beginAgentOperation(ctx, id, agentOperationRestartTerminal); err != nil {
		if errors.Is(err, errAgentOperationInProgress) {
			err = ErrSwitchInProgress
		}
		return RestoreResult{}, fmt.Errorf("restart terminal %s: %w", id, err)
	}
	defer m.endAgentOperation(id, agentOperationRestartTerminal)

	rec, ok, err := m.store.GetSession(ctx, id)
	if err != nil {
		return RestoreResult{}, fmt.Errorf("restart terminal %s: %w", id, err)
	}
	if !ok {
		return RestoreResult{}, fmt.Errorf("restart terminal %s: %w", id, ErrNotFound)
	}
	if rec.IsTerminated {
		return RestoreResult{}, fmt.Errorf("restart terminal %s: %w", id, ErrTerminated)
	}
	project, err := m.loadProject(ctx, rec.ProjectID)
	if err != nil {
		return RestoreResult{}, fmt.Errorf("restart terminal %s: %w", id, err)
	}
	meta := rec.Metadata
	if meta.WorkspacePath == "" ||
		(meta.Branch == "" && project.Kind.WithDefault() != domain.ProjectKindScratch) ||
		meta.RuntimeHandleID == "" {
		return RestoreResult{}, fmt.Errorf("restart terminal %s: %w", id, ErrIncompleteHandle)
	}
	handle := ports.RuntimeHandle{ID: meta.RuntimeHandleID}
	if err := m.runtime.Destroy(ctx, handle); err != nil {
		return RestoreResult{}, fmt.Errorf("restart terminal %s: stop the unresponsive terminal: %w", id, err)
	}
	ws := ports.WorkspaceInfo{
		Path:      meta.WorkspacePath,
		Branch:    meta.Branch,
		SessionID: rec.ID,
		ProjectID: rec.ProjectID,
		Mode:      meta.WorkspaceMode,
	}
	return m.relaunchSession(ctx, "restart terminal", rec, project, ws, &handle, grid)
}

// relaunchPolicy selects how a relaunch rebuilds the agent's conversation.
```

- [ ] **Step 4: Run to see them pass, then the package**

```bash
cd "$REPO/backend" && gofmt -l internal/session_manager
cd "$REPO/backend" && go test ./internal/session_manager/ -run RestartTerminal -count=1 -race -v 2>&1 | grep -E '^(--- |ok|FAIL)'
cd "$REPO/backend" && go test ./internal/session_manager/ -count=1 2>&1 | tail -2
```
Expected: no gofmt output; 4 `--- PASS`; `ok`.

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add backend/internal/session_manager/session_input.go backend/internal/session_manager/manager.go backend/internal/session_manager/restart_terminal_test.go
git commit -m "feat(session): restart a session's unresponsive terminal in a fresh pty-host

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: `POST /api/v1/sessions/{sessionId}/restart-terminal` (Part A)

**Files:**
- Modify: `backend/internal/service/session/service.go:61,384`
- Modify: `backend/internal/service/session/service_test.go:1194,1236,1789`
- Modify: `backend/internal/httpd/controllers/dto.go:613`
- Modify: `backend/internal/httpd/controllers/sessions.go:91,227,1092-1097,1211`
- Modify: `backend/internal/httpd/controllers/sessions_test.go:86,263,2611`
- Modify: `backend/internal/httpd/apispec/specgen/build.go:214,1788`
- Regenerate: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`
- Modify: `frontend/src/renderer/lib/api-client.ts:100`

**Interfaces:**
- Consumes: `(*sessionmanager.Manager).RestartTerminal` (Task 4).
- Produces: `(*sessionsvc.Service).RestartTerminal(ctx, id, grid ports.PaneGrid) (ResumeAgentOutcome, error)`; `controllers.RestartTerminalRequest{Cols, Rows int}`; `controllers.RestartTerminalResponse{OK bool; SessionID domain.SessionID; RestartMode sessionsvc.RestoreModeView; Session SessionView}` (JSON `ok`, `sessionId`, `restartMode`, `session`); operation id `restartSessionTerminal`; TS path `"/api/v1/sessions/{sessionId}/restart-terminal"` with body `{cols?: number; rows?: number}`.

- [ ] **Step 1: Write the failing service tests**

In `backend/internal/service/session/service_test.go`, replace (lines 1194-1195):
```go
	restoreResult      sessionmanager.RestoreResult
}
```
with (the blank line keeps gofmt from realigning the fields above):
```go
	restoreResult      sessionmanager.RestoreResult

	restartedTerminals  []domain.SessionID
	restartTerminalGrid ports.PaneGrid
}
```

Replace (line 1236):
```go
func (f *fakeCommander) ResumeAgentWithMode(_ context.Context, id domain.SessionID) (sessionmanager.RestoreResult, error) {
```
with:
```go
func (f *fakeCommander) RestartTerminal(_ context.Context, id domain.SessionID, grid ports.PaneGrid) (sessionmanager.RestoreResult, error) {
	f.restartedTerminals = append(f.restartedTerminals, id)
	f.restartTerminalGrid = grid
	if f.restoreErr != nil {
		return sessionmanager.RestoreResult{}, f.restoreErr
	}
	return f.restoreResult, nil
}
func (f *fakeCommander) ResumeAgentWithMode(_ context.Context, id domain.SessionID) (sessionmanager.RestoreResult, error) {
```

Replace (line 1789):
```go
func TestDelegateTaskPassesAttachmentsToSpawnConfig(t *testing.T) {
```
with:
```go
func TestRestartTerminalForwardsTheGridAndMapsTheMode(t *testing.T) {
	st := newFakeStore()
	rec := domain.SessionRecord{
		ID:        "mer-1",
		ProjectID: "mer",
		Harness:   domain.HarnessCodex,
		Activity:  domain.Activity{State: domain.ActivityIdle},
	}
	fc := &fakeCommander{
		restoreResult: sessionmanager.RestoreResult{
			Session: rec,
			Mode:    sessionmanager.RestoreModeNative,
		},
	}
	svc := &Service{manager: fc, store: st}

	got, err := svc.RestartTerminal(context.Background(), "mer-1", ports.PaneGrid{Cols: 132, Rows: 43})
	if err != nil {
		t.Fatalf("RestartTerminal: %v", err)
	}
	if got.Session.ID != "mer-1" || got.Mode != RestoreModeViewNative {
		t.Fatalf("restart outcome = %+v", got)
	}
	if len(fc.restartedTerminals) != 1 || fc.restartedTerminals[0] != "mer-1" {
		t.Fatalf("restarted = %v, want [mer-1]", fc.restartedTerminals)
	}
	if fc.restartTerminalGrid != (ports.PaneGrid{Cols: 132, Rows: 43}) {
		t.Fatalf("grid = %+v, want 132x43", fc.restartTerminalGrid)
	}
}

func TestRestartTerminalMapsATerminatedSessionToAConflict(t *testing.T) {
	fc := &fakeCommander{restoreErr: fmt.Errorf("restart terminal mer-1: %w", sessionmanager.ErrTerminated)}
	svc := &Service{manager: fc, store: newFakeStore()}

	_, err := svc.RestartTerminal(context.Background(), "mer-1", ports.PaneGrid{})
	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Code != "SESSION_TERMINATED" {
		t.Fatalf("restart of a terminated session = %v, want SESSION_TERMINATED", err)
	}
}

func TestDelegateTaskPassesAttachmentsToSpawnConfig(t *testing.T) {
```
(`errors`, `fmt`, `apierr`, `ports` are already imported by this file, lines 6-19.)

- [ ] **Step 2: Write the failing controller tests**

In `backend/internal/httpd/controllers/sessions_test.go`, replace (lines 86-87):
```go
	handoffSource           domain.AgentGenerationID
}
```
with:
```go
	handoffSource           domain.AgentGenerationID

	restartTerminalErr  error
	restartTerminalGrid ports.PaneGrid
}
```

Replace (line 263):
```go
func (f *fakeSessionService) RelaunchAgent(_ context.Context, id domain.SessionID, cfg sessionmanager.RelaunchAgentConfig) (sessionsvc.ResumeAgentOutcome, error) {
```
with:
```go
func (f *fakeSessionService) RestartTerminal(_ context.Context, id domain.SessionID, grid ports.PaneGrid) (sessionsvc.ResumeAgentOutcome, error) {
	f.restartTerminalGrid = grid
	if f.restartTerminalErr != nil {
		return sessionsvc.ResumeAgentOutcome{}, f.restartTerminalErr
	}
	s := f.sessions[id]
	s.ID = id
	return sessionsvc.ResumeAgentOutcome{Session: s, Mode: sessionsvc.RestoreModeView("native")}, nil
}

func (f *fakeSessionService) RelaunchAgent(_ context.Context, id domain.SessionID, cfg sessionmanager.RelaunchAgentConfig) (sessionsvc.ResumeAgentOutcome, error) {
```

Replace (line 2611):
```go
func TestRelaunchAgent(t *testing.T) {
```
with:
```go
func TestRestartTerminal(t *testing.T) {
	t.Run("forwards the pane grid and reports the restart mode", func(t *testing.T) {
		svc := newFakeSessionService()
		srv := newSessionTestServer(t, svc)
		body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/restart-terminal", `{"cols":132,"rows":43}`)
		if status != http.StatusOK {
			t.Fatalf("restart = %d, want 200; body=%s", status, body)
		}
		var got struct {
			OK          bool   `json:"ok"`
			SessionID   string `json:"sessionId"`
			RestartMode string `json:"restartMode"`
		}
		mustJSON(t, body, &got)
		if !got.OK || got.SessionID != "opr-1" || got.RestartMode != "native" {
			t.Fatalf("restart response = %#v", got)
		}
		if svc.restartTerminalGrid != (ports.PaneGrid{Cols: 132, Rows: 43}) {
			t.Fatalf("grid forwarded as %+v, want 132x43", svc.restartTerminalGrid)
		}
	})

	t.Run("accepts an empty body", func(t *testing.T) {
		svc := newFakeSessionService()
		srv := newSessionTestServer(t, svc)
		body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/restart-terminal", "")
		if status != http.StatusOK {
			t.Fatalf("restart = %d, want 200; body=%s", status, body)
		}
		if svc.restartTerminalGrid != (ports.PaneGrid{}) {
			t.Fatalf("grid = %+v, want zero", svc.restartTerminalGrid)
		}
	})

	t.Run("surfaces a typed conflict", func(t *testing.T) {
		svc := newFakeSessionService()
		svc.restartTerminalErr = apierr.Conflict("SESSION_TERMINATED", "Session is terminated", nil)
		srv := newSessionTestServer(t, svc)
		body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/restart-terminal", "")
		if status != http.StatusConflict || !strings.Contains(string(body), "SESSION_TERMINATED") {
			t.Fatalf("terminated restart = %d body=%s", status, body)
		}
	})

	t.Run("rejects a malformed body", func(t *testing.T) {
		svc := newFakeSessionService()
		srv := newSessionTestServer(t, svc)
		body, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/opr-1/restart-terminal", `{`)
		if status != http.StatusBadRequest || !strings.Contains(string(body), "INVALID_JSON") {
			t.Fatalf("malformed restart = %d body=%s", status, body)
		}
	})
}

func TestRelaunchAgent(t *testing.T) {
```

- [ ] **Step 3: Run to see them fail**

```bash
cd "$REPO/backend" && go test ./internal/service/session/ ./internal/httpd/controllers/ -run 'RestartTerminal' -count=1 2>&1 | tail -6
```
Expected: `[build failed]` in both (`svc.RestartTerminal undefined`; in controllers the fake compiles but the route test gets 404/405 — either way FAIL).

- [ ] **Step 4: Implement the service method**

In `backend/internal/service/session/service.go`, replace (line 61):
```go
	RelaunchAgentFresh(ctx context.Context, id domain.SessionID, cfg sessionmanager.RelaunchAgentConfig) (sessionmanager.RestoreResult, error)
```
with:
```go
	RelaunchAgentFresh(ctx context.Context, id domain.SessionID, cfg sessionmanager.RelaunchAgentConfig) (sessionmanager.RestoreResult, error)
	RestartTerminal(ctx context.Context, id domain.SessionID, grid ports.PaneGrid) (sessionmanager.RestoreResult, error)
```
and replace (line 384):
```go
func restoreModeView(mode sessionmanager.RestoreMode) RestoreModeView {
```
with:
```go
func (s *Service) RestartTerminal(ctx context.Context, id domain.SessionID, grid ports.PaneGrid) (ResumeAgentOutcome, error) {
	res, err := s.manager.RestartTerminal(ctx, id, grid)
	if err != nil {
		return ResumeAgentOutcome{}, toAPIError(err)
	}
	session, err := s.toSession(ctx, res.Session)
	if err != nil {
		return ResumeAgentOutcome{}, err
	}
	return ResumeAgentOutcome{Session: session, Mode: restoreModeView(res.Mode)}, nil
}

func restoreModeView(mode sessionmanager.RestoreMode) RestoreModeView {
```

- [ ] **Step 5: Implement the DTOs, handler and route**

In `backend/internal/httpd/controllers/dto.go`, replace (line 613):
```go
// KillSessionResponse is the body of POST /api/v1/sessions/{sessionId}/kill.
```
with:
```go
type RestartTerminalRequest struct {
	Cols int `json:"cols,omitempty" description:"Columns of the terminal pane that shows the session, so the fresh pty is born at that width. Omit when unknown." minimum:"1" maximum:"1000"`
	Rows int `json:"rows,omitempty" description:"Rows of the terminal pane that shows the session; see cols." minimum:"1" maximum:"1000"`
}

type RestartTerminalResponse struct {
	OK          bool                       `json:"ok"`
	SessionID   domain.SessionID           `json:"sessionId"`
	RestartMode sessionsvc.RestoreModeView `json:"restartMode" enum:"native,saved_prompt,fresh"`
	Session     SessionView                `json:"session"`
}

// KillSessionResponse is the body of POST /api/v1/sessions/{sessionId}/kill.
```

In `backend/internal/httpd/controllers/sessions.go`:

Replace (line 91):
```go
	RelaunchAgent(ctx context.Context, id domain.SessionID, cfg sessionmanager.RelaunchAgentConfig) (sessionsvc.ResumeAgentOutcome, error)
```
with:
```go
	RelaunchAgent(ctx context.Context, id domain.SessionID, cfg sessionmanager.RelaunchAgentConfig) (sessionsvc.ResumeAgentOutcome, error)
	RestartTerminal(ctx context.Context, id domain.SessionID, grid ports.PaneGrid) (sessionsvc.ResumeAgentOutcome, error)
```

Replace (line 227):
```go
	r.Post("/sessions/{sessionId}/relaunch-agent", c.relaunchAgent)
```
with:
```go
	r.Post("/sessions/{sessionId}/relaunch-agent", c.relaunchAgent)
	r.Post("/sessions/{sessionId}/restart-terminal", c.restartTerminal)
```

In `restore` (lines 1092-1098), replace:
```go
	var in RestoreSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil && !errors.Is(err, io.EOF) {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return
	}
	out, err := c.Svc.Restore(r.Context(), sessionID(r), ports.PaneGrid{Cols: in.Cols, Rows: in.Rows})
	if err != nil {
```
with:
```go
	grid, ok := decodePaneGrid(w, r)
	if !ok {
		return
	}
	out, err := c.Svc.Restore(r.Context(), sessionID(r), grid)
	if err != nil {
```
(The shared decoder exists so the new handler is not a copy of `restore`; the repo's `dupl` linter, threshold 140, `backend/.golangci.yml`, would otherwise be at risk.)

Replace (line 1211):
```go
func (c *SessionsController) switchAgent(w http.ResponseWriter, r *http.Request) {
```
with:
```go
func (c *SessionsController) restartTerminal(w http.ResponseWriter, r *http.Request) {
	if c.Svc == nil {
		apispec.NotImplemented(w, r, "POST", "/api/v1/sessions/{sessionId}/restart-terminal")
		return
	}
	grid, ok := decodePaneGrid(w, r)
	if !ok {
		return
	}
	out, err := c.Svc.RestartTerminal(r.Context(), sessionID(r), grid)
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, RestartTerminalResponse{
		OK:          true,
		SessionID:   sessionID(r),
		RestartMode: out.Mode,
		Session:     sessionView(out.Session),
	})
}

func decodePaneGrid(w http.ResponseWriter, r *http.Request) (ports.PaneGrid, bool) {
	var in RestoreSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil && !errors.Is(err, io.EOF) {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_JSON", "Invalid JSON body", nil)
		return ports.PaneGrid{}, false
	}
	return ports.PaneGrid{Cols: in.Cols, Rows: in.Rows}, true
}

func (c *SessionsController) switchAgent(w http.ResponseWriter, r *http.Request) {
```

- [ ] **Step 6: Register the operation in the spec builder**

In `backend/internal/httpd/apispec/specgen/build.go`, replace (line 214):
```go
	"ControllersResumeAgentResponse":                "ResumeAgentResponse",
```
with:
```go
	"ControllersResumeAgentResponse":                "ResumeAgentResponse",
	"ControllersRestartTerminalRequest":             "RestartTerminalRequest",
	"ControllersRestartTerminalResponse":            "RestartTerminalResponse",
```

Then find the operation entry whose `path` is `"/api/v1/sessions/{sessionId}/relaunch-agent"` (lines 1775-1788). Directly after its closing `},` (line 1788, the line before the entry for `/switch-agent`), insert:
```go
		{
			method: http.MethodPost, path: "/api/v1/sessions/{sessionId}/restart-terminal", id: "restartSessionTerminal", tag: "sessions",
			summary:         "Stop a session's unresponsive terminal host and resume the agent in a fresh one",
			pathParams:      []any{controllers.SessionIDParam{}},
			reqBody:         controllers.RestartTerminalRequest{},
			optionalReqBody: true,
			resps: []respUnit{
				{http.StatusOK, controllers.RestartTerminalResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusNotFound, envelope.APIError{}},
				{http.StatusConflict, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
```

- [ ] **Step 7: Regenerate the spec and the TS schema**

```bash
cd "$REPO" && npm run api 2>&1 | tail -3
cd "$REPO" && git diff --stat -- backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
grep -n 'restart-terminal\|RestartTerminalResponse:' "$REPO/backend/internal/httpd/apispec/openapi.yaml" | head
```
Expected: `npm run api` ends with `openapi-typescript 7.4.4` and a `→ frontend/src/api/schema.ts` line; the diff stat shows both files changed (about +90 lines in `openapi.yaml`, about +100 in `schema.ts`); grep shows the path `/api/v1/sessions/{sessionId}/restart-terminal:` and the schema. If `npm run api` cannot run (`openapi-typescript` missing), run `cd "$REPO/backend" && go generate ./internal/httpd/apispec/...` for the YAML and record `schema.ts: not run: <reason>`; the frontend task then cannot typecheck its POST path — stop and report.

- [ ] **Step 8: Keep the renderer's route list in sync**

In `frontend/src/renderer/lib/api-client.ts`, replace (line 100):
```ts
	"/api/v1/sessions/{sessionId}/relaunch-agent",
```
with:
```ts
	"/api/v1/sessions/{sessionId}/relaunch-agent",
	"/api/v1/sessions/{sessionId}/restart-terminal",
```

- [ ] **Step 9: Run the tests**

```bash
cd "$REPO/backend" && gofmt -l internal/service internal/httpd
cd "$REPO/backend" && go test ./internal/service/session/ ./internal/httpd/... ./internal/cli/... -count=1 2>&1 | grep -E '^(ok|FAIL|---)'
```
Expected: no gofmt output; `ok` for `service/session`, `httpd`, `httpd/apispec` (spec drift + route/spec parity), `httpd/apispec/specgen`, `httpd/controllers`, `cli`.

- [ ] **Step 10: Commit**

```bash
cd "$REPO" && git add backend/internal/service/session/service.go backend/internal/service/session/service_test.go backend/internal/httpd/controllers/dto.go backend/internal/httpd/controllers/sessions.go backend/internal/httpd/controllers/sessions_test.go backend/internal/httpd/apispec/specgen/build.go backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts frontend/src/renderer/lib/api-client.ts
git commit -m "feat(api): restart a session's unresponsive terminal

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: The pane says it stopped responding and offers Restart (Part A)

**Files:**
- Modify: `frontend/src/renderer/lib/terminal-mux.ts`, `frontend/src/renderer/lib/terminal-mux.test.ts`
- Modify: `frontend/src/renderer/hooks/useTerminalSession.ts`, `frontend/src/renderer/hooks/useTerminalSession.test.tsx`
- Create: `frontend/src/renderer/hooks/useRestartTerminal.ts`
- Modify: `frontend/src/renderer/components/TerminalPane.tsx`, `frontend/src/renderer/components/TerminalPane.test.tsx`
- Modify: `frontend/src/renderer/i18n/en.json:942`

**Interfaces:**
- Consumes: server frame `{ch:"terminal", id, type:"health", health:"hung"|"ok"}` (Task 3); `POST /api/v1/sessions/{sessionId}/restart-terminal` (Task 5).
- Produces: `export type TerminalHealth = "ok" | "hung"` and `TerminalMux.onHealth(id, listener) => () => void` in `terminal-mux.ts`; `useTerminalSession(...)` now also returns `health: TerminalHealth` and `reconnectAfterRestart: () => void`; `useRestartTerminal(): (sessionId: string) => Promise<{status:"success"} | {status:"error"; message:string}>`.

Design (DESIGN.md banner: clone agent-orchestrator, shadcn primitives): the strip reuses the existing `TerminalEndedStrip` layout classes (`TerminalPane.tsx:1262-1270`) and the shadcn `Button` (`components/ui/button.tsx`, `variant="outline" size="sm"`) with the same `RotateCcw` icon the Restore button uses. The hung strip replaces the ended strip while shown.

- [ ] **Step 1: Failing mux tests**

In `frontend/src/renderer/lib/terminal-mux.test.ts`, replace:
```ts
	it("routes a pane error frame to that pane's error listener only", () => {
```
with:
```ts
	it("routes a health frame to that pane's health listener only", () => {
		const mux = createTerminalMux("ws://x/mux", FakeSocket as unknown as typeof WebSocket);
		const socket = FakeSocket.instances.at(-1)!;
		socket.emitOpen();
		const seen: string[] = [];
		const other: string[] = [];
		mux.onHealth("s", (health) => seen.push(health));
		mux.onHealth("other", (health) => other.push(health));
		socket.emitMessage(JSON.stringify({ ch: "terminal", id: "s", type: "health", health: "hung" }));
		socket.emitMessage(JSON.stringify({ ch: "terminal", id: "s", type: "health", health: "ok" }));
		socket.emitMessage(JSON.stringify({ ch: "terminal", id: "s", type: "health", health: "unknown-value" }));
		expect(seen).toEqual(["hung", "ok", "ok"]);
		expect(other).toEqual([]);
	});

	it("routes a pane error frame to that pane's error listener only", () => {
```
and replace:
```ts
	it("a lease forwards blocks subscribe and stops after it is disposed", () => {
```
with:
```ts
	it("a lease stops delivering health frames after it is disposed", () => {
		const pool = createTerminalMuxPool(() =>
			createTerminalMux("ws://x/mux", FakeSocket as unknown as typeof WebSocket),
		);
		const lease = pool.acquire();
		const keeper = pool.acquire();
		const socket = FakeSocket.instances[0];
		socket.emitOpen();
		const seen: string[] = [];
		lease.onHealth("s", (health) => seen.push(health));
		socket.emitMessage(JSON.stringify({ ch: "terminal", id: "s", type: "health", health: "hung" }));
		lease.dispose();
		socket.emitMessage(JSON.stringify({ ch: "terminal", id: "s", type: "health", health: "ok" }));
		expect(seen).toEqual(["hung"]);
		keeper.dispose();
	});

	it("a lease forwards blocks subscribe and stops after it is disposed", () => {
```

- [ ] **Step 2: Failing hook tests**

In `frontend/src/renderer/hooks/useTerminalSession.test.tsx`:

Replace (line 5):
```ts
import type { MuxConnectionState, TerminalMux } from "../lib/terminal-mux";
```
with:
```ts
import type { MuxConnectionState, TerminalHealth, TerminalMux } from "../lib/terminal-mux";
```
Replace:
```ts
	emitError(id: string, message: string): void;
	emitConnection(state: MuxConnectionState): void;
};
```
with:
```ts
	emitError(id: string, message: string): void;
	emitHealth(id: string, health: TerminalHealth): void;
	emitConnection(state: MuxConnectionState): void;
};
```
Replace:
```ts
	const error = new Map<string, Set<(message: string) => void>>();
	const connection
```
with:
```ts
	const error = new Map<string, Set<(message: string) => void>>();
	const health = new Map<string, Set<(next: TerminalHealth) => void>>();
	const connection
```
Replace:
```ts
			onError: (id, listener) => subscribe(error, id, listener),
			subscribeBlocks
```
with:
```ts
			onError: (id, listener) => subscribe(error, id, listener),
			onHealth: (id, listener) => subscribe(health, id, listener),
			subscribeBlocks
```
Replace:
```ts
		emitError: (id, message) => error.get(id)?.forEach((listener) => listener(message)),
```
with:
```ts
		emitError: (id, message) => error.get(id)?.forEach((listener) => listener(message)),
		emitHealth: (id, next) => health.get(id)?.forEach((listener) => listener(next)),
```
Replace (line 236):
```ts
describe("useTerminalSession", () => {
```
with:
```ts
describe("useTerminalSession", () => {
	it("reports a hung terminal from the daemon and reconnects fresh after a restart", () => {
		const { view, muxes } = setup();
		act(() => muxes[0].emitOpened("handle-1"));
		expect(view.result.current.health).toBe("ok");
		act(() => muxes[0].emitHealth("other-handle", "hung"));
		expect(view.result.current.health).toBe("ok");
		act(() => muxes[0].emitHealth("handle-1", "hung"));
		expect(view.result.current.health).toBe("hung");

		act(() => view.result.current.reconnectAfterRestart());

		expect(view.result.current.health).toBe("ok");
		expect(view.result.current.state).toBe("connecting");
		expect(muxes).toHaveLength(2);
		expect(muxes[0].closes).toEqual(["handle-1"]);
		expect(muxes[0].disposed).toBe(true);
		expect(muxes[1].opens.map(([id]) => id)).toEqual(["handle-1"]);
		act(() => muxes[0].emitHealth("handle-1", "hung"));
		expect(view.result.current.health).toBe("ok");
	});

	it("reconnects after a restart even when the hung attachment already exited", () => {
		const { view, muxes } = setup();
		act(() => muxes[0].emitHealth("handle-1", "hung"));
		act(() => muxes[0].emitExit("handle-1"));
		expect(view.result.current.state).toBe("exited");
		expect(view.result.current.health).toBe("hung");

		act(() => view.result.current.reconnectAfterRestart());

		expect(view.result.current.state).toBe("connecting");
		expect(view.result.current.health).toBe("ok");
		expect(muxes).toHaveLength(2);
		expect(muxes[1].opens.map(([id]) => id)).toEqual(["handle-1"]);
	});

```

- [ ] **Step 3: Failing pane tests**

In `frontend/src/renderer/components/TerminalPane.test.tsx`:

Replace:
```ts
	attachmentMounts,
	attachmentUnmounts,
} = vi.hoisted(
```
with:
```ts
	attachmentMounts,
	attachmentUnmounts,
	terminalHealth,
	reconnectAfterRestartMock,
} = vi.hoisted(
```
Replace:
```ts
		attachmentMounts: { value: 0 },
		attachmentUnmounts: { value: 0 },
	}),
);
```
with:
```ts
		attachmentMounts: { value: 0 },
		attachmentUnmounts: { value: 0 },
		terminalHealth: { value: "ok" as "ok" | "hung" },
		reconnectAfterRestartMock: vi.fn(),
	}),
);
```
Replace (in the `fakeMux` inside `vi.mock("../lib/terminal-mux", …)`):
```ts
		onError: () => () => undefined,
		subscribeBlocks: () => undefined,
```
with:
```ts
		onError: () => () => undefined,
		onHealth: () => () => undefined,
		subscribeBlocks: () => undefined,
```
Replace (in the `vi.mock("../hooks/useTerminalSession", …)` return value):
```ts
			state: terminalState.value,
			error: terminalError.value,
			replaySettled: replaySettled.value,
```
with:
```ts
			state: terminalState.value,
			error: terminalError.value,
			health: terminalHealth.value,
			reconnectAfterRestart: reconnectAfterRestartMock,
			replaySettled: replaySettled.value,
```
Replace (in `beforeEach`):
```ts
	terminalError.value = undefined;
	terminalState.value = "idle";
```
with:
```ts
	terminalError.value = undefined;
	terminalState.value = "idle";
	terminalHealth.value = "ok";
	reconnectAfterRestartMock.mockClear();
```
Replace (line 1244):
```ts
describe("terminal restore", () => {
```
with:
```ts
describe("terminal not responding", () => {
	it("tells the user a hung terminal stopped responding and offers a restart", () => {
		terminalState.value = "attached";
		terminalHealth.value = "hung";
		const view = renderPane({ ...worker, terminalHandleId: "term-1" });
		try {
			expect(screen.getByText("This terminal stopped responding.")).toBeInTheDocument();
			expect(screen.getByText("Stops whatever is running in this terminal and resumes the agent in a new one")).toBeInTheDocument();
			expect(screen.getByRole("button", { name: "Restart terminal" })).toBeEnabled();
			expect(screen.queryByText("Terminal ended")).not.toBeInTheDocument();
		} finally {
			view.restore();
		}
	});

	it("restarts the terminal through the daemon and reconnects the pane", async () => {
		terminalState.value = "exited";
		terminalHealth.value = "hung";
		rememberPaneGrid(132, 43);
		const view = renderPane({ ...worker, terminalHandleId: "term-1" });
		const invalidate = vi.spyOn(view.queryClient, "invalidateQueries").mockResolvedValue(undefined);
		try {
			await userEvent.click(screen.getByRole("button", { name: "Restart terminal" }));

			await waitFor(() =>
				expect(postMock).toHaveBeenCalledWith("/api/v1/sessions/{sessionId}/restart-terminal", {
					params: { path: { sessionId: "sess-1" } },
					body: { cols: 132, rows: 43 },
				}),
			);
			await waitFor(() => expect(reconnectAfterRestartMock).toHaveBeenCalledTimes(1));
			expect(invalidate).toHaveBeenCalledWith({ queryKey: ["workspaces"] });
		} finally {
			view.restore();
		}
	});

	it("keeps the pane as it is and shows the error when the restart fails", async () => {
		terminalState.value = "attached";
		terminalHealth.value = "hung";
		postMock.mockResolvedValue({ error: { code: "SESSION_TERMINATED", message: "Session is terminated" } });
		const view = renderPane({ ...worker, terminalHandleId: "term-1" });
		try {
			await userEvent.click(screen.getByRole("button", { name: "Restart terminal" }));

			expect(await screen.findByText("Unable to restart terminal")).toBeInTheDocument();
			expect(reconnectAfterRestartMock).not.toHaveBeenCalled();
			expect(screen.getByRole("button", { name: "Restart terminal" })).toBeEnabled();
		} finally {
			view.restore();
		}
	});

	it("offers no restart on a terminated session", () => {
		terminalState.value = "attached";
		terminalHealth.value = "hung";
		const view = renderPane({ ...worker, status: "terminated", terminalHandleId: "term-1" });
		try {
			expect(screen.queryByRole("button", { name: "Restart terminal" })).not.toBeInTheDocument();
		} finally {
			view.restore();
		}
	});
});

describe("terminal restore", () => {
```

- [ ] **Step 4: Run to see them fail**

```bash
cd "$REPO/frontend" && npx vitest run --config vite.renderer.config.ts src/renderer/lib/terminal-mux.test.ts src/renderer/hooks/useTerminalSession.test.tsx src/renderer/components/TerminalPane.test.tsx 2>&1 | tail -8
```
Expected: failures such as `mux.onHealth is not a function`, `expected undefined to be 'ok'`, and `Unable to find … "This terminal stopped responding."`.

- [ ] **Step 5: Implement `onHealth` in the mux client**

In `frontend/src/renderer/lib/terminal-mux.ts` make these exact replacements:

1. The frame list comment (line 10) becomes false; correct it:
```ts
//     server → opened{id} | data{id,data} | exited{id} | error{id?,error}
```
→
```ts
//     server → opened{id} | data{id,data} | exited{id} | error{id?,error} | health{id,health}
```
2. In `type ServerFrame`:
```ts
	error?: string;
	block?: unknown;
```
→
```ts
	error?: string;
	health?: string;
	block?: unknown;
```
3.
```ts
type ErrorListener = (message: string) => void;
```
→
```ts
type ErrorListener = (message: string) => void;
export type TerminalHealth = "ok" | "hung";
type HealthListener = (health: TerminalHealth) => void;
```
4. In `export type TerminalMux`:
```ts
	onError: (id: string, listener: ErrorListener) => () => void;
	/** Ask the daemon to push this session's normalized block events. */
```
→
```ts
	onError: (id: string, listener: ErrorListener) => () => void;
	onHealth: (id: string, listener: HealthListener) => () => void;
	/** Ask the daemon to push this session's normalized block events. */
```
5.
```ts
	const errorListeners = new Map<string, Set<ErrorListener>>();
	const blockListeners = new Map<string, Set<BlockListener>>();
```
→
```ts
	const errorListeners = new Map<string, Set<ErrorListener>>();
	const healthListeners = new Map<string, Set<HealthListener>>();
	const blockListeners = new Map<string, Set<BlockListener>>();
```
6.
```ts
		} else if (frame.type === "opened") {
			openedListeners.get(frame.id)?.forEach((listener) => listener());
		}
```
→
```ts
		} else if (frame.type === "opened") {
			openedListeners.get(frame.id)?.forEach((listener) => listener());
		} else if (frame.type === "health") {
			const health: TerminalHealth = frame.health === "hung" ? "hung" : "ok";
			healthListeners.get(frame.id)?.forEach((listener) => listener(health));
		}
```
7.
```ts
		errorListeners.clear();
		blockListeners.clear();
```
→
```ts
		errorListeners.clear();
		healthListeners.clear();
		blockListeners.clear();
```
8.
```ts
		onError: (id, listener) => subscribeById(errorListeners, id, listener),
		subscribeBlocks: (sessionId) => {
			send(blocksSubscribeFrame(sessionId));
```
→
```ts
		onError: (id, listener) => subscribeById(errorListeners, id, listener),
		onHealth: (id, listener) => subscribeById(healthListeners, id, listener),
		subscribeBlocks: (sessionId) => {
			send(blocksSubscribeFrame(sessionId));
```
9. In the pool lease:
```ts
			onError: (id, listener) => subscribe(() => connection.mux.onError(id, listener)),
```
→
```ts
			onError: (id, listener) => subscribe(() => connection.mux.onError(id, listener)),
			onHealth: (id, listener) => subscribe(() => connection.mux.onHealth(id, listener)),
```

- [ ] **Step 6: Implement `health` and `reconnectAfterRestart` in the hook**

In `frontend/src/renderer/hooks/useTerminalSession.ts`:

1. Line 20:
```ts
import { createTerminalMux, muxUrlFromApiBase, type TerminalMux } from "../lib/terminal-mux";
```
→
```ts
import { createTerminalMux, muxUrlFromApiBase, type TerminalHealth, type TerminalMux } from "../lib/terminal-mux";
```
2. Line 172:
```ts
	const [replaySettled, setReplaySettled] = useState(true);
```
→
```ts
	const [replaySettled, setReplaySettled] = useState(true);
	const [health, setHealth] = useState<TerminalHealth>("ok");
```
3. In `connect` (lines 430-432):
```ts
		teardownMux();

		const mux = (optionsRef.current.createMux ?? defaultCreateMux)();
```
→
```ts
		teardownMux();
		setHealth("ok");

		const mux = (optionsRef.current.createMux ?? defaultCreateMux)();
```
4. In `connect`'s `r.disposers.push(...)` list, directly before the `onConnectionChange` registration:
```ts
			mux.onConnectionChange((connectionState) => {
```
→
```ts
			mux.onHealth(handle, (next) => {
				if (!isCurrentAttachment(generation, handle, mux)) return;
				setHealth(next);
			}),
			mux.onConnectionChange((connectionState) => {
```
5. Line 1008:
```ts
	const onReplayReady = useCallback(() => {
```
→
```ts
	const reconnectAfterRestart = useCallback(() => {
		const r = runtime.current;
		setHealth("ok");
		if (r.detached || !r.terminal || !r.handle) return;
		if (optionsRef.current.daemonReady) {
			transition("connecting");
			connect();
		} else {
			transition("reattaching");
		}
	}, [connect, transition]);

	const onReplayReady = useCallback(() => {
```
6. Line 1015:
```ts
	return { attach, state, error, replaySettled, syncVisibleSize, transport, onReplayReady };
```
→
```ts
	return {
		attach,
		state,
		error,
		health,
		replaySettled,
		syncVisibleSize,
		transport,
		onReplayReady,
		reconnectAfterRestart,
	};
```

`reconnectAfterRestart` always opens a fresh attachment (`connect()` tears the old one down and sends `close` first, `useTerminalSession.ts:335-380`), so it works whether the daemon's old attachment already reported `exited` or silently re-attached to the new host.

- [ ] **Step 7: Add the restart hook**

Create `frontend/src/renderer/hooks/useRestartTerminal.ts`:

```ts
import { useCallback } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { paneGridBody } from "../lib/pane-grid";
import { workspaceQueryKey } from "./useWorkspaceQuery";

export type RestartTerminalResult = { status: "success" } | { status: "error"; message: string };

export function useRestartTerminal(): (sessionId: string) => Promise<RestartTerminalResult> {
	const queryClient = useQueryClient();

	return useCallback(
		async (sessionId: string) => {
			try {
				const { error } = await apiClient.POST("/api/v1/sessions/{sessionId}/restart-terminal", {
					params: { path: { sessionId } },
					body: paneGridBody(),
				});
				if (error) {
					return { status: "error", message: apiErrorMessage(error, "Unable to restart terminal") };
				}
				await queryClient.invalidateQueries({ queryKey: workspaceQueryKey });
				return { status: "success" };
			} catch (err) {
				return {
					status: "error",
					message: err instanceof Error ? err.message : "Unable to restart terminal",
				};
			}
		},
		[queryClient],
	);
}
```

- [ ] **Step 8: Copy**

In `frontend/src/renderer/i18n/en.json`, replace (line 942):
```json
	"terminal.restoreToContinue": "Restore the session to attach a live terminal and continue writing.",
```
with:
```json
	"terminal.restoreToContinue": "Restore the session to attach a live terminal and continue writing.",
	"terminal.hungTitle": "Terminal not responding",
	"terminal.hungMessage": "This terminal stopped responding.",
	"terminal.restartTerminal": "Restart terminal",
	"terminal.restartTerminalHint": "Stops whatever is running in this terminal and resumes the agent in a new one",
	"terminal.unableRestartTerminal": "Unable to restart terminal",
```
(`terminal.unableRestartTerminal` mirrors `terminal.unableRestore`; the hook's inline English fallback matches `useRestoreSession.ts`, which does the same.)

- [ ] **Step 9: The hung strip in the pane**

In `frontend/src/renderer/components/TerminalPane.tsx`:

1. Line 43:
```tsx
import { useRestoreSession } from "../hooks/useRestoreSession";
```
→
```tsx
import { useRestoreSession } from "../hooks/useRestoreSession";
import { useRestartTerminal } from "../hooks/useRestartTerminal";
```
2. Line 49:
```tsx
import { TerminalAttachment } from "./TerminalAttachment";
```
→
```tsx
import { TerminalAttachment } from "./TerminalAttachment";
import { Button } from "./ui/button";
```
3. Lines 1006-1007:
```tsx
	const restoreSessionById = useRestoreSession();
	// A shell pane has no session, so it hands the hook its handle directly
```
→
```tsx
	const restoreSessionById = useRestoreSession();
	const restartTerminalById = useRestartTerminal();
	const [isRestartingTerminal, setIsRestartingTerminal] = useState(false);
	const [restartTerminalError, setRestartTerminalError] = useState<string | undefined>();
	// A shell pane has no session, so it hands the hook its handle directly
```
4. Lines 1013-1021:
```tsx
	const { attach, state, error, replaySettled, transport, onReplayReady } = useTerminalSession(attachSession, {
		coverInitialReplay: terminalTarget?.kind !== "reviewer",
		createMux,
		daemonReady,
		enabled: !isShellTarget || !shellBlocks.isLoading,
		inputDisabled,
		isVisible,
		shellTerminalHandleId,
	});
```
→
```tsx
	const { attach, state, error, health, replaySettled, transport, onReplayReady, reconnectAfterRestart } =
		useTerminalSession(attachSession, {
			coverInitialReplay: terminalTarget?.kind !== "reviewer",
			createMux,
			daemonReady,
			enabled: !isShellTarget || !shellBlocks.isLoading,
			inputDisabled,
			isVisible,
			shellTerminalHandleId,
		});
```
5. Lines 1066-1067:
```tsx
		session !== undefined &&
		!isSessionActive;
```
→
```tsx
		session !== undefined &&
		!isSessionActive;
	const canRestartTerminal =
		terminalTarget?.kind !== "reviewer" &&
		terminalTarget?.kind !== "shell" &&
		session !== undefined &&
		isSessionActive;
```
6. Lines 1108-1113:
```tsx
	useEffect(() => {
		return () => {
			detachRef.current?.();
			detachRef.current = undefined;
		};
	}, []);
```
→
```tsx
	const restartTerminal = useCallback(async () => {
		if (!session?.id || !canRestartTerminal || isRestartingTerminal) return;
		setIsRestartingTerminal(true);
		setRestartTerminalError(undefined);
		try {
			const result = await restartTerminalById(session.id);
			if (result.status === "error") {
				setRestartTerminalError(result.message);
				return;
			}
			reconnectAfterRestart();
		} finally {
			setIsRestartingTerminal(false);
		}
	}, [canRestartTerminal, isRestartingTerminal, reconnectAfterRestart, restartTerminalById, session?.id]);

	useEffect(() => {
		return () => {
			detachRef.current?.();
			detachRef.current = undefined;
		};
	}, []);
```
7. Line 1132:
```tsx
	const showEndedState = state === "exited" || canRestoreSession;
```
→
```tsx
	const showHungState = health === "hung" && canRestartTerminal;
	const showEndedState = !showHungState && (state === "exited" || canRestoreSession);
```
8. Lines 1137-1138:
```tsx
		<div className="terminal-pane-surface flex h-full min-h-0 flex-col" data-testid="session-terminal">
			{showEndedState && (
```
→
```tsx
		<div className="terminal-pane-surface flex h-full min-h-0 flex-col" data-testid="session-terminal">
			{showHungState && (
				<TerminalHungStrip
					error={restartTerminalError}
					isRestarting={isRestartingTerminal}
					onRestart={restartTerminal}
				/>
			)}
			{showEndedState && (
```
9. Line 1245:
```tsx
type TerminalEndedStripProps = {
```
→
```tsx
type TerminalHungStripProps = {
	error?: string;
	isRestarting: boolean;
	onRestart: () => void;
};

function TerminalHungStrip({ error, isRestarting, onRestart }: TerminalHungStripProps) {
	const { t } = useTranslation();
	return (
		<div className="shrink-0 border-b border-border bg-surface/80 px-4 py-2" data-testid="terminal-hung-strip">
			<div className="flex min-h-control-board items-center gap-3">
				<div className="min-w-0 flex-1">
					<div className="font-mono text-caption font-medium uppercase tracking-wide-md text-muted-foreground">
						{t("terminal.hungTitle")}
					</div>
					<div className="mt-0.5 truncate text-xs text-muted-foreground">{t("terminal.hungMessage")}</div>
					<div className="mt-0.5 text-xs text-muted-foreground">{t("terminal.restartTerminalHint")}</div>
				</div>
				{error && <div className="max-w-content-max truncate text-xs text-destructive">{error}</div>}
				<Button
					variant="outline"
					size="sm"
					title={t("terminal.restartTerminalHint")}
					disabled={isRestarting}
					onClick={onRestart}
				>
					<RotateCcw className={cn("size-icon-base", isRestarting && "animate-spin")} aria-hidden="true" />
					{t("terminal.restartTerminal")}
				</Button>
			</div>
		</div>
	);
}

type TerminalEndedStripProps = {
```

- [ ] **Step 10: Run the three suites, typecheck and lint**

```bash
cd "$REPO/frontend" && npx vitest run --config vite.renderer.config.ts src/renderer/lib/terminal-mux.test.ts src/renderer/hooks/useTerminalSession.test.tsx src/renderer/components/TerminalPane.test.tsx src/renderer/lib/api-client.test.ts src/renderer/i18n 2>&1 | tail -6
cd "$REPO/frontend" && npm run typecheck 2>&1 | tail -3
cd "$REPO/frontend" && npx eslint src/renderer/components/TerminalPane.tsx src/renderer/components/TerminalPane.test.tsx src/renderer/hooks/useTerminalSession.ts src/renderer/hooks/useTerminalSession.test.tsx src/renderer/hooks/useRestartTerminal.ts src/renderer/lib/terminal-mux.ts src/renderer/lib/terminal-mux.test.ts src/renderer/lib/api-client.ts 2>&1 | tail -2
```
Expected: vitest `Test Files  5 passed (5)` (terminal-mux 27 tests, useTerminalSession 69, TerminalPane 59, plus `api-client.test.ts` and `i18n/instance.test.ts`); typecheck exits 0 (or `not run` per Task 0); eslint `✖ 23 problems (0 errors, 23 warnings)` — the same 23 warnings these files carry on `development` (checked 2026-09-24), **0 errors**.

- [ ] **Step 11: Commit**

```bash
cd "$REPO" && git add frontend/src/renderer/lib/terminal-mux.ts frontend/src/renderer/lib/terminal-mux.test.ts frontend/src/renderer/hooks/useTerminalSession.ts frontend/src/renderer/hooks/useTerminalSession.test.tsx frontend/src/renderer/hooks/useRestartTerminal.ts frontend/src/renderer/components/TerminalPane.tsx frontend/src/renderer/components/TerminalPane.test.tsx frontend/src/renderer/i18n/en.json
git commit -m "feat(renderer): tell the user a terminal stopped responding and offer a restart

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

**Part A is complete and shippable here.**

---

### Task 7: The pty-host saves its history (Part B)

**Files:**
- Create: `backend/internal/adapters/runtime/ptyhost/persist.go`
- Create: `backend/internal/adapters/runtime/ptyhost/persist_test.go`
- Modify: `backend/internal/adapters/runtime/ptyhost/host.go:48-51,221-223,350,386-389,618`

**Interfaces:**
- Consumes: `vtwasm.Parser.{Feed, Replay, HistoryChunk, TouchHistory, TakeQueryReplies}` (`vtwasm/vtwasm.go`), `respawnBoundary` (`respawn.go:16-22`), `host.replayFrameLocked` (`host.go:911`), `MaxOutputLines` (`ring.go:9`), `frameHeaderBytes` (`proto.go:88`), `ptyregistry.List` (`ptyregistry/registry.go:146`).
- Produces: `ServeConfig.HistoryPath string`, `ServeConfig.PersistInterval time.Duration`, `ServeConfig.HistoryMaxBytes int` (0 = 4 MiB); constants `historyMagic = "OPRVT1\n"`, `persistInterval = 60 * time.Second`, `persistHistoryChunks = 20`, `persistMaxBytes = 4 << 20`, `historyRetention = 7 * 24 * time.Hour`; functions `historyDir() (string, error)`, `historyPath(sessionID string) (string, error)`, `writeHistoryFile(path string, data []byte) error`, `removeHistory(sessionID string) error`, `pruneHistory(now time.Time, live func(string) bool) error`, `pruneStaleHistory(now time.Time, creating string)`, `seedMirror(parser *vtwasm.Parser, path string) (bool, error)`, `prepareHistory(sessionID string, parser *vtwasm.Parser) string`; methods `(*host).persistHistory()`, `(*host).runHistoryPersist()`, `(*host).historySnapshot() []byte`.

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/adapters/runtime/ptyhost/persist_test.go`:

```go
package ptyhost

import (
	"bytes"
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

func newMirror(t *testing.T, cols, rows int) *vtwasm.Parser {
	t.Helper()
	parser, err := vtwasm.New(context.Background(), vtwasm.Module, uint32(cols), uint32(rows), vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	t.Cleanup(func() { _ = parser.Close() })
	return parser
}

func startServeWithHistory(t *testing.T, pid, cols, rows int, parser *vtwasm.Parser, path string, interval time.Duration, maxBytes int) *serveFixture {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	pty := newFakePTY(pid)
	ring := NewRing()
	ctx, cancel := context.WithCancel(context.Background())
	h := newHost(ctx, ServeConfig{
		SessionID:       fmt.Sprintf("test-%d", pid),
		Listener:        ln,
		PTY:             pty,
		Ring:            ring,
		Parser:          parser,
		InitialCols:     cols,
		InitialRows:     rows,
		HistoryPath:     path,
		PersistInterval: interval,
		HistoryMaxBytes: maxBytes,
	})
	done := make(chan error, 1)
	go func() {
		done <- h.run(ctx)
	}()
	t.Cleanup(cancel)
	return &serveFixture{pty: pty, ring: ring, ln: ln, addr: ln.Addr().String(), cancel: cancel, done: done, host: h}
}

func waitForHistoryFile(t *testing.T, path, want string) []byte {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		data, err := os.ReadFile(path)
		if err == nil && bytes.Contains(data, []byte(want)) {
			return data
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("history file %s never contained %q", path, want)
	return nil
}

func renderedRows(t *testing.T, stream string, cols, rows int) []string {
	t.Helper()
	mirror := newMirror(t, cols, rows)
	if err := mirror.Feed([]byte(stream)); err != nil {
		t.Fatalf("feed: %v", err)
	}
	rendered, err := mirror.RenderTail(200_000)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	return strings.Split(strings.TrimRight(rendered, "\n"), "\n")
}

func TestAPeriodicallyPersistedHistoryReopensInAFreshHost(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sess.vt")
	first := startServeWithHistory(t, 4201, 20, 4, newMirror(t, 20, 4), path, 20*time.Millisecond, 0)
	for i := 0; i < 1500; i++ {
		writeOutput(t, first, fmt.Sprintf("old %04d\r\n", i))
	}
	waitForParsedOutput(t, first, "old 1499")
	crashed := waitForHistoryFile(t, path, "old 1499")
	saved := filepath.Join(dir, "saved.vt")
	if err := os.WriteFile(saved, crashed, 0o600); err != nil {
		t.Fatalf("copy the file the host left behind: %v", err)
	}
	first.cancel()
	first.waitDone(t)

	parser := newMirror(t, 20, 4)
	seeded, err := seedMirror(parser, saved)
	if err != nil || !seeded {
		t.Fatalf("seedMirror = (%v, %v), want (true, nil)", seeded, err)
	}
	second := startServeWithHistory(t, 4202, 20, 4, parser, filepath.Join(dir, "second.vt"), 0, 0)
	writeOutput(t, second, "new child\r\n")
	waitForParsedOutput(t, second, "new child")

	c := newTestClient(t, second.addr)
	defer c.close()
	sendResizeWithHistory(t, c, 20, 4, true)
	stream := ""
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) && !strings.Contains(stream, "old 0000") {
		typ, payload := c.readFrame(t)
		if typ == MsgTerminalData {
			stream += string(payload)
		}
	}
	rows := renderedRows(t, stream, 20, 4)
	if !strings.Contains(rows[0], "old 0000") {
		t.Fatalf("the reopened pane does not start with the oldest saved row; first row = %q", rows[0])
	}
	joined := strings.Join(rows, "\n")
	oldest := strings.Index(joined, "old 1499")
	newest := strings.Index(joined, "new child")
	if oldest < 0 || newest < 0 || oldest > newest {
		t.Fatalf("want the saved history above the new child's output; rows:\n%s", joined)
	}
}

func TestAPersistedHistoryStaysUnderItsByteCap(t *testing.T) {
	const limit = 40 << 10
	path := filepath.Join(t.TempDir(), "sess.vt")
	f := startServeWithHistory(t, 4203, 80, 24, newMirror(t, 80, 24), path, 0, limit)
	for i := 0; i < 3000; i++ {
		writeOutput(t, f, fmt.Sprintf("line %04d\r\n", i))
	}
	waitForParsedOutput(t, f, "line 2999")
	f.host.persistHistory()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read history: %v", err)
	}
	if len(data) > limit {
		t.Fatalf("history file is %d bytes, over the %d-byte cap", len(data), limit)
	}
	if !bytes.HasPrefix(data, []byte(historyMagic)) {
		t.Fatalf("history file does not start with %q", historyMagic)
	}
	if !bytes.Contains(data, []byte("line 2999")) {
		t.Fatal("the cap dropped the newest row")
	}
	if bytes.Contains(data, []byte("line 0000")) {
		t.Fatal("the cap kept the oldest row; it must drop the oldest history first")
	}
}

func TestPersistWritesOnlyWhenTheMirrorChanged(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sess.vt")
	f := startServeWithHistory(t, 4204, 20, 4, newMirror(t, 20, 4), path, 0, 0)
	writeOutput(t, f, "first\r\n")
	waitForParsedOutput(t, f, "first")
	f.host.persistHistory()
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("first persist wrote nothing: %v", err)
	}
	if err := os.Remove(path); err != nil {
		t.Fatalf("remove: %v", err)
	}
	f.host.persistHistory()
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("persist rewrote an unchanged mirror (stat err = %v)", err)
	}
	writeOutput(t, f, "second\r\n")
	waitForParsedOutput(t, f, "second")
	f.host.persistHistory()
	waitForHistoryFile(t, path, "second")
}

func TestShutdownPersistsTheLatestHistory(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sess.vt")
	f := startServeWithHistory(t, 4205, 20, 4, newMirror(t, 20, 4), path, 0, 0)
	writeOutput(t, f, "last words\r\n")
	waitForParsedOutput(t, f, "last words")
	f.cancel()
	f.waitDone(t)
	waitForHistoryFile(t, path, "last words")
}

func TestSeedMirrorWithoutAFileIsANoOp(t *testing.T) {
	parser := newMirror(t, 20, 4)
	seeded, err := seedMirror(parser, filepath.Join(t.TempDir(), "missing.vt"))
	if seeded || err != nil {
		t.Fatalf("seedMirror(missing) = (%v, %v), want (false, nil)", seeded, err)
	}
}

func TestSeedMirrorRejectsAFileWithoutTheHeader(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sess.vt")
	if err := os.WriteFile(path, []byte("not a history file\r\n"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	parser := newMirror(t, 20, 4)
	seeded, err := seedMirror(parser, path)
	if seeded || err == nil {
		t.Fatalf("seedMirror(no header) = (%v, %v), want (false, error)", seeded, err)
	}
	tail, err := parser.RenderTail(10)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if strings.Contains(tail, "not a history file") {
		t.Fatalf("a file without the header reached the mirror: %q", tail)
	}
}

func TestPrepareHistorySeedsTheMirrorFromTheSessionFile(t *testing.T) {
	isolateRegistry(t)
	path, err := historyPath("sess-seed")
	if err != nil {
		t.Fatalf("historyPath: %v", err)
	}
	if err := writeHistoryFile(path, []byte(historyMagic+"hello from before\r\n")); err != nil {
		t.Fatalf("write history: %v", err)
	}
	parser := newMirror(t, 40, 5)
	if got := prepareHistory("sess-seed", parser); got != path {
		t.Fatalf("prepareHistory path = %q, want %q", got, path)
	}
	tail, err := parser.RenderTail(10)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if !strings.Contains(tail, "hello from before") {
		t.Fatalf("the mirror was not seeded; tail = %q", tail)
	}
	if got := prepareHistory("sess-seed", nil); got != "" {
		t.Fatalf("prepareHistory without a parser = %q, want no persistence", got)
	}
}

func TestPruneHistoryRemovesOnlyOldFilesOfGoneHosts(t *testing.T) {
	isolateRegistry(t)
	dir, err := historyDir()
	if err != nil {
		t.Fatalf("historyDir: %v", err)
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	now := time.Now()
	old := now.Add(-historyRetention - time.Hour)
	files := map[string]time.Time{
		"gone-old.vt":     old,
		"live-old.vt":     old,
		"gone-new.vt":     now,
		"gone-old.vt.tmp": old,
		"notes.txt":       old,
	}
	for name, mtime := range files {
		full := filepath.Join(dir, name)
		if err := os.WriteFile(full, []byte(historyMagic), 0o600); err != nil {
			t.Fatalf("write %s: %v", name, err)
		}
		if err := os.Chtimes(full, mtime, mtime); err != nil {
			t.Fatalf("chtimes %s: %v", name, err)
		}
	}
	if err := pruneHistory(now, func(id string) bool { return id == "live-old" }); err != nil {
		t.Fatalf("pruneHistory: %v", err)
	}
	for name, wantKept := range map[string]bool{
		"gone-old.vt":     false,
		"gone-old.vt.tmp": false,
		"live-old.vt":     true,
		"gone-new.vt":     true,
		"notes.txt":       true,
	} {
		_, err := os.Stat(filepath.Join(dir, name))
		if kept := err == nil; kept != wantKept {
			t.Fatalf("%s kept = %v, want %v", name, kept, wantKept)
		}
	}
}
```

(`writeOutput`, `waitForParsedOutput`, `sendResizeWithHistory` are in `attach_replay_test.go:53,290,155`; `newTestClient`, `readFrame`, `serveFixture.waitDone` in `host_test.go:123-250`; `isolateRegistry` in `runtime_test.go:234`.)

- [ ] **Step 2: Run to see them fail**

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ -run 'Persist|Seed|PrepareHistory|Prune|ShutdownPersists' -count=1 2>&1 | tail -4
```
Expected: `[build failed]` with `unknown field HistoryPath in struct literal of type ServeConfig` and `undefined: seedMirror`.

- [ ] **Step 3: Implement persistence**

Create `backend/internal/adapters/runtime/ptyhost/persist.go`:

```go
package ptyhost

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/ptyregistry"
	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

const (
	historyMagic         = "OPRVT1\n"
	historyDirName       = "pty-host-history"
	historyFileSuffix    = ".vt"
	historyTempSuffix    = ".vt.tmp"
	persistInterval      = 60 * time.Second
	persistHistoryChunks = 20
	persistMaxBytes      = 4 << 20
	historyRetention     = 7 * 24 * time.Hour
)

func historyDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".operator", historyDirName), nil
}

func historyPath(sessionID string) (string, error) {
	dir, err := historyDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, sessionID+historyFileSuffix), nil
}

func writeHistoryFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	tmp := strings.TrimSuffix(path, historyFileSuffix) + historyTempSuffix
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func removeHistory(sessionID string) error {
	path, err := historyPath(sessionID)
	if err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func pruneHistory(now time.Time, live func(sessionID string) bool) error {
	dir, err := historyDir()
	if err != nil {
		return err
	}
	entries, err := os.ReadDir(dir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, entry := range entries {
		name := entry.Name()
		id, ok := strings.CutSuffix(name, historyTempSuffix)
		if !ok {
			id, ok = strings.CutSuffix(name, historyFileSuffix)
		}
		if !ok || live(id) {
			continue
		}
		info, err := entry.Info()
		if err != nil || now.Sub(info.ModTime()) < historyRetention {
			continue
		}
		_ = os.Remove(filepath.Join(dir, name))
	}
	return nil
}

func pruneStaleHistory(now time.Time, creating string) {
	entries, err := ptyregistry.List()
	if err != nil {
		return
	}
	keep := make(map[string]bool, len(entries)+1)
	keep[creating] = true
	for _, entry := range entries {
		keep[entry.SessionID] = true
	}
	_ = pruneHistory(now, func(sessionID string) bool { return keep[sessionID] })
}

func seedMirror(parser *vtwasm.Parser, path string) (bool, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if !bytes.HasPrefix(data, []byte(historyMagic)) {
		return false, errors.New("ptyhost: history file has no OPRVT1 header")
	}
	if err := parser.Feed(data[len(historyMagic):]); err != nil {
		return false, err
	}
	if err := parser.Feed(respawnBoundary(0, false)); err != nil {
		return false, err
	}
	if _, err := parser.TakeQueryReplies(); err != nil {
		return false, err
	}
	return true, nil
}

func prepareHistory(sessionID string, parser *vtwasm.Parser) string {
	if parser == nil {
		return ""
	}
	path, err := historyPath(sessionID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "pty-host [%s]: history path: %v\n", sessionID, err)
		return ""
	}
	if _, err := seedMirror(parser, path); err != nil {
		fmt.Fprintf(os.Stderr, "pty-host [%s]: seed history: %v\n", sessionID, err)
	}
	return path
}

func (h *host) historyMaxBytes() int {
	if h.cfg.HistoryMaxBytes > 0 {
		return h.cfg.HistoryMaxBytes
	}
	return persistMaxBytes
}

func (h *host) historySnapshot() []byte {
	parser := h.currentParser()
	if parser == nil {
		return nil
	}
	if err := parser.TouchHistory(); err != nil {
		h.logf("rewrap history for persistence: %v", err)
	}
	h.mu.Lock()
	frame, origin := h.replayFrameLocked()
	h.mu.Unlock()
	if frame == nil {
		return nil
	}
	limit := h.historyMaxBytes()
	payload := frame[frameHeaderBytes:]
	if len(historyMagic)+len(payload) > limit {
		return nil
	}
	out := make([]byte, 0, len(historyMagic)+len(payload))
	out = append(out, historyMagic...)
	out = append(out, payload...)
	if origin == vtwasm.HistoryBefore {
		return out
	}
	before := origin
	for range persistHistoryChunks {
		chunk, next, ok, err := parser.HistoryChunk(before, MaxOutputLines, vtwasm.HistoryChunkRows)
		if err != nil {
			h.logf("persist history chunk: %v", err)
			break
		}
		if !ok || len(out)+len(chunk) > limit {
			break
		}
		out = append(out, chunk...)
		before = next
	}
	return out
}

func (h *host) persistHistory() {
	if h.cfg.HistoryPath == "" {
		return
	}
	h.persistMu.Lock()
	defer h.persistMu.Unlock()
	h.respawnMu.Lock()
	defer h.respawnMu.Unlock()
	h.mu.Lock()
	fed := h.fedBytes
	h.mu.Unlock()
	if fed == h.persistedBytes {
		return
	}
	snapshot := h.historySnapshot()
	if snapshot == nil {
		return
	}
	if err := writeHistoryFile(h.cfg.HistoryPath, snapshot); err != nil {
		h.logf("persist history: %v", err)
		return
	}
	h.persistedBytes = fed
}

func (h *host) runHistoryPersist() {
	if h.cfg.HistoryPath == "" || h.cfg.PersistInterval <= 0 {
		return
	}
	ticker := time.NewTicker(h.cfg.PersistInterval)
	defer ticker.Stop()
	for {
		select {
		case <-h.shutdownC:
			return
		case <-ticker.C:
			h.persistHistory()
		}
	}
}
```

Why these locks: `persistMu` serialises the ticker and the shutdown write; `respawnMu` keeps a respawn (`respawn.go:28`, which closes and replaces the parser) from racing a snapshot; the lock order `respawnMu → h.mu` is the one `handleRespawn` already uses. The frame and its origin come from one `replayFrameLocked` call under `h.mu`, so the first chunk abuts the frame's origin exactly (`TERMINAL.md` §4.21), and `TouchHistory` runs first so cold rows are not clipped (§4.20).

In `backend/internal/adapters/runtime/ptyhost/host.go`:

1. Lines 48-51:
```go
	InitialRows int
	Recorder    *recorder
}
```
→
```go
	InitialRows int
	Recorder    *recorder

	HistoryPath     string
	PersistInterval time.Duration
	HistoryMaxBytes int
}
```
2. Lines 221-223:
```go
	readCond   *sync.Cond
	readParked bool
}
```
→
```go
	readCond   *sync.Cond
	readParked bool

	fedBytes       uint64
	persistMu      sync.Mutex
	persistedBytes uint64
}
```
3. In `run` (line 350):
```go
	go h.pumpPTY()
```
→
```go
	go h.pumpPTY()
	go h.runHistoryPersist()
```
4. In `shutdown` (lines 386-389):
```go
		close(h.shutdownC)
		h.mu.Lock()
		h.readCond.Broadcast()
		h.mu.Unlock()
```
→
```go
		close(h.shutdownC)
		h.mu.Lock()
		h.readCond.Broadcast()
		h.mu.Unlock()
		h.persistHistory()
```
5. In `deliver` (line 618):
```go
	h.feedParserLocked(batch)
	inSync := h.parserInSyncLocked()
```
→
```go
	h.feedParserLocked(batch)
	h.fedBytes += uint64(len(batch))
	inSync := h.parserInSyncLocked()
```

- [ ] **Step 4: Run to see them pass, with the race detector, then the package**

```bash
cd "$REPO/backend" && gofmt -l internal/adapters/runtime/ptyhost
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ -run 'Persist|Seed|PrepareHistory|Prune|ShutdownPersists' -count=1 -race -v 2>&1 | grep -E '^(--- |ok|FAIL)'
cd "$REPO/backend" && go test -race ./internal/adapters/runtime/ptyhost/... -count=1 2>&1 | tail -4
```
Expected: no gofmt output; 8 `--- PASS` (the round trip takes ~9 s under `-race`); then `ok` for the three packages (the whole `ptyhost` package takes ~70 s under `-race`).

- [ ] **Step 5: Commit**

```bash
cd "$REPO" && git add backend/internal/adapters/runtime/ptyhost/persist.go backend/internal/adapters/runtime/ptyhost/persist_test.go backend/internal/adapters/runtime/ptyhost/host.go
git commit -m "feat(ptyhost): save the mirror's history to disk every minute and on shutdown

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: A relaunched host replays the saved history (Part B)

**Files:**
- Modify: `backend/internal/adapters/runtime/ptyhost/host_main.go:170-179`
- Modify: `backend/internal/adapters/runtime/ptyhost/runtime.go` (the `Create` reservation, lines 95-98 at `20bf1e58c`)
- Modify: `backend/internal/ports/outbound.go:131-133`
- Modify: `backend/internal/session_manager/manager.go:1424-1431`
- Create: `backend/internal/adapters/runtime/ptyhost/persist_runtime_test.go`
- Modify: `backend/internal/session_manager/restart_terminal_test.go` (append)

**Interfaces:**
- Consumes: `prepareHistory`, `persistInterval`, `removeHistory`, `pruneStaleHistory`, `writeHistoryFile`, `historyPath`, `historyMagic` (Task 7); `newHungTerminalManager` (Task 4).
- Produces: `ports.RuntimeConfig.RestoreHistory bool`.

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/adapters/runtime/ptyhost/persist_runtime_test.go`:

```go
package ptyhost

import (
	"context"
	"os"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func seedHistoryFile(t *testing.T, sessionID string) string {
	t.Helper()
	path, err := historyPath(sessionID)
	if err != nil {
		t.Fatalf("historyPath: %v", err)
	}
	if err := writeHistoryFile(path, []byte(historyMagic+"from an earlier host\r\n")); err != nil {
		t.Fatalf("write history: %v", err)
	}
	return path
}

func TestCreateDropsAStaleHistoryForAFreshSession(t *testing.T) {
	isolateRegistry(t)
	path := seedHistoryFile(t, "sess-fresh")
	hosts := map[string]*inProcHost{}
	rt := New(Options{Spawner: fakeSpawnerFor(t, hosts, livePID())})
	if _, err := rt.Create(context.Background(), ports.RuntimeConfig{
		SessionID:     domain.SessionID("sess-fresh"),
		WorkspacePath: t.TempDir(),
		Argv:          []string{"sh"},
	}); err != nil {
		t.Fatalf("Create: %v", err)
	}
	defer hosts["sess-fresh"].cleanup(t)
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("a fresh session kept another host's history (stat err = %v)", err)
	}
}

func TestCreateKeepsTheHistoryOfARestoredSession(t *testing.T) {
	isolateRegistry(t)
	path := seedHistoryFile(t, "sess-restored")
	hosts := map[string]*inProcHost{}
	rt := New(Options{Spawner: fakeSpawnerFor(t, hosts, livePID())})
	if _, err := rt.Create(context.Background(), ports.RuntimeConfig{
		SessionID:      domain.SessionID("sess-restored"),
		WorkspacePath:  t.TempDir(),
		Argv:           []string{"sh"},
		RestoreHistory: true,
	}); err != nil {
		t.Fatalf("Create: %v", err)
	}
	defer hosts["sess-restored"].cleanup(t)
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("a restored session lost its history before its host could read it: %v", err)
	}
}
```

Append to `backend/internal/session_manager/restart_terminal_test.go`:

```go

func TestRelaunchedHostsRestoreTheirHistory(t *testing.T) {
	runtime := &fakeRuntime{aliveByHandle: map[string]bool{"pty-mer-1": true}, aliveErr: errors.New("read tcp 127.0.0.1:1: i/o timeout")}
	runtime.onDestroy = func(int, ports.RuntimeHandle) { runtime.aliveErr = nil }
	m, _ := newHungTerminalManager(t, runtime)

	if _, err := m.RestartTerminal(ctx, "mer-1", ports.PaneGrid{}); err != nil {
		t.Fatalf("RestartTerminal: %v", err)
	}
	if !runtime.lastCfg.RestoreHistory {
		t.Fatal("a relaunched host must replay the history its predecessor saved")
	}
}
```

- [ ] **Step 2: Run to see them fail**

```bash
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ ./internal/session_manager/ -run 'CreateDropsAStale|CreateKeepsTheHistory|RelaunchedHostsRestore' -count=1 2>&1 | tail -4
```
Expected: `[build failed]`, `unknown field RestoreHistory in struct literal of type ports.RuntimeConfig`.

- [ ] **Step 3: Add the flag and set it on every relaunch**

In `backend/internal/ports/outbound.go`, replace (lines 131-133):
```go
	Cols int
	Rows int
}
```
(the end of `type RuntimeConfig struct`) with:
```go
	Cols int
	Rows int

	RestoreHistory bool
}
```

In `backend/internal/session_manager/manager.go`, replace (lines 1424-1431):
```go
	runtimeCfg := ports.RuntimeConfig{
		SessionID:     rec.ID,
		WorkspacePath: ws.Path,
		Argv:          argv,
		Env:           env,
		Cols:          grid.Cols,
		Rows:          grid.Rows,
	}
```
with:
```go
	runtimeCfg := ports.RuntimeConfig{
		SessionID:      rec.ID,
		WorkspacePath:  ws.Path,
		Argv:           argv,
		Env:            env,
		Cols:           grid.Cols,
		Rows:           grid.Rows,
		RestoreHistory: true,
	}
```
(Only this constructor, inside `relaunchSessionWithPolicy`, sets it. The spawn path `manager.go:691`, the agent switch `agent_switching.go:487`, the reviewer launcher `review/launcher.go:432` and shell terminals `service/shellterm/service.go:135` leave it false on purpose: they start new terminals.)

- [ ] **Step 4: The runtime decides; the host seeds**

In `backend/internal/adapters/runtime/ptyhost/runtime.go`, in `Create`, replace:
```go
	r.sessions[id] = nil
	r.mu.Unlock()

	addr, pid, err := r.spawner(ctx, id, cfg.WorkspacePath, cfg.Argv, cfg.Env, cfg.Cols, cfg.Rows)
```
with:
```go
	r.sessions[id] = nil
	r.mu.Unlock()

	if !cfg.RestoreHistory {
		_ = removeHistory(id)
	}
	pruneStaleHistory(time.Now(), id)

	addr, pid, err := r.spawner(ctx, id, cfg.WorkspacePath, cfg.Argv, cfg.Env, cfg.Cols, cfg.Rows)
```

In `backend/internal/adapters/runtime/ptyhost/host_main.go`, replace (lines 170-179):
```go
	cfg := ServeConfig{
		SessionID:   sessionID,
		Listener:    ln,
		PTY:         pty,
		Ring:        ring,
		Parser:      parser,
		InitialCols: parsed.cols,
		InitialRows: parsed.rows,
		Recorder:    recorderFromEnv(sessionID, parsed.cols, parsed.rows),
	}
```
with:
```go
	cfg := ServeConfig{
		SessionID:       sessionID,
		Listener:        ln,
		PTY:             pty,
		Ring:            ring,
		Parser:          parser,
		InitialCols:     parsed.cols,
		InitialRows:     parsed.rows,
		Recorder:        recorderFromEnv(sessionID, parsed.cols, parsed.rows),
		HistoryPath:     prepareHistory(sessionID, parser),
		PersistInterval: persistInterval,
	}
```
`prepareHistory` runs after `newPTY` has started the child (`host_main.go:133`) but before `Serve` starts the pump (`host.go:350`), so the child's first bytes wait in the pty buffer and land after the seeded history and its boundary mark.

- [ ] **Step 5: Run to see them pass; run everything touched**

```bash
cd "$REPO/backend" && gofmt -l internal/ports internal/session_manager internal/adapters/runtime/ptyhost
cd "$REPO/backend" && go test ./internal/adapters/runtime/ptyhost/ ./internal/session_manager/ -run 'CreateDropsAStale|CreateKeepsTheHistory|RelaunchedHostsRestore|RestartTerminal' -count=1 -v 2>&1 | grep -E '^(--- |ok|FAIL)'
cd "$REPO/backend" && go build ./... && go test ./internal/adapters/runtime/... ./internal/session_manager/... ./internal/service/... ./internal/review/... ./internal/terminal/... -count=1 2>&1 | grep -E '^(ok|FAIL)'
```
Expected: no gofmt output; 7 `--- PASS`; every package `ok` (or only failures already in the Task 0 baseline).

- [ ] **Step 6: Commit**

```bash
cd "$REPO" && git add backend/internal/ports/outbound.go backend/internal/session_manager/manager.go backend/internal/session_manager/restart_terminal_test.go backend/internal/adapters/runtime/ptyhost/runtime.go backend/internal/adapters/runtime/ptyhost/host_main.go backend/internal/adapters/runtime/ptyhost/persist_runtime_test.go
git commit -m "feat(ptyhost): replay a relaunched session's saved history into its new host

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Docs

**Files:**
- Modify: `TERMINAL.md` (§1 diagram line 22, new §4.29 after §4.26 ending at line 832, §5 list)
- Modify: `docs/terminal/2026-09-19-terminal-reference-survey.md:123,3672`
- Modify: `docs/terminal/2026-09-24-not-done-plain-language.md:132-136,152`

- [ ] **Step 1: `TERMINAL.md` §1 — the pipeline**

Replace (line 22):
```
   ├─ ring.go            raw output ring for late attachers
```
with:
```
   ├─ ring.go            raw output ring for late attachers
   ├─ persist.go         every 60 s (when changed) and on shutdown, writes the attach
   │                     replay (frame + newest 20 history chunks, ≤ 4 MiB) to
   │                     ~/.operator/pty-host-history/<id>.vt; a host created for a
   │                     relaunched session seeds its mirror from it (§4.29)
```

- [ ] **Step 2: `TERMINAL.md` §4.29**

Insert immediately before the line `## 5. Known gaps (not bugs, decisions pending)` (line 834), keeping one blank line before it:

```markdown
### 4.29 A hung pty-host froze its pane; a dead one lost its history — roadmap Plan 4
- Symptom: a pty-host that stopped answering (SIGSTOP, or wedged) left its pane
  frozen with no message, and nothing offered a way out short of restarting the
  daemon and the app. A pty-host that died took the terminal's history with it:
  the mirror and the ring live only in host memory.
- Cause: the reaper records a timed-out probe as `ProbeFailed`
  (`observe/reaper/reaper.go:205-215`) and lifecycle ignores it by design
  (`ports/runtime_observations.go:13-14`), so nothing ever concluded "hung";
  and nothing wrote the mirror anywhere.
- Now: `ptyhost.Runtime` counts consecutive failed `IsAlive` probes per host;
  at `hungAfterFailedProbes` (3, i.e. ~12–17 s at the reaper's 5 s tick) the
  host is hung, the terminal mux sends `{"type":"health","health":"hung"}` on
  `ch:"terminal"` to the panes viewing it (and to a pane that opens it later),
  and the pane shows "This terminal stopped responding." with **Restart
  terminal**. Restart is `POST /api/v1/sessions/{id}/restart-terminal`:
  `Runtime.Destroy` (SIGKILL after 500 ms, which reaches a stopped process)
  then the normal relaunch into a fresh host under the same handle id. It is
  never automatic. `respawn.go` cannot do this: it runs inside the hung host.
  Every host also saves its attach replay to `~/.operator/pty-host-history/`
  (`persist.go`); `Runtime.Create` deletes a session's file unless
  `RuntimeConfig.RestoreHistory` (set only by the session manager's relaunch
  path), and prunes files of gone hosts older than 7 days; the new host feeds
  the file and a process-boundary mark into its mirror before the child's
  first byte, so every attach replays the old history above the new process.
- Measured: `claude-long-50k` (60k rows) — frame 17 KB, newest 20 chunks
  180 KB in 491 ms; all 116 chunks would be 938 KB in 2.7 s, because every
  `vt_history_chunk` snapshots the whole core (`vt-host/src/lib.rs:470`).
  `docs/superpowers/specs/2026-09-24-crash-recovery-measurement.md`.
- Guards: `ptyhost/health_test.go` (hung after 3 not before, recovery, slow
  once, refused is gone, destroy clears), `terminal/health_test.go` (viewers
  only, new viewer told at once, client stays attached across a restart),
  `session_manager/restart_terminal_test.go`, controller `TestRestartTerminal`,
  `ptyhost/persist_test.go` (round trip after a crash, byte cap, write only on
  change, shutdown write, header, prune), `persist_runtime_test.go`,
  `TerminalPane.test.tsx` "terminal not responding",
  `useTerminalSession.test.tsx` health tests.
```

- [ ] **Step 3: `TERMINAL.md` §5 — known gaps**

Insert these bullets immediately before the line starting `- **What a parked pane still costs.**` (line 1100):

```markdown
- **Hung detection covers session terminals only, and the board shows
  nothing.** The reaper probes session rows (`reaper.go:143-166`), so a
  standalone shell or a reviewer terminal is never marked hung; the hung state
  lives in daemon memory and reaches only the pane (`ch:"terminal"` health
  frames). A board badge needs a read-time runtime join in `SessionView` and a
  push trigger; not built (roadmap Plan 4, decision D6).
- **Every liveness probe renders a full attach replay.** A status probe is a
  new connection, and `handleConn` renders `replayFrameLocked` under `h.mu`
  for it before answering (`host.go:851`), ~24 ms at 60k rows. The reaper
  pays it every 5 s per session. Skipping the replay for a connection whose
  first frame is not a resize is the fix if it ever shows.
- **After Restart terminal the pane keeps its renderer core.** A worker pane's
  cache key is its handle id (`TerminalPane.tsx:156`), which a restart keeps,
  so the new host's replay lands on the existing core — the same path as
  Restore. Check for duplicated rows in the real app; a fix belongs with the
  Restore path.
- **Saved history is bounded.** Frame plus the newest 10,240 history rows,
  ≤ 4 MiB, written at most once a minute: a crash loses up to the last minute,
  and older rows of a very long session are not saved. An in-place respawn
  ("Relaunch in a cleared session") replaces the mirror, so the next save
  holds only the new process. Files of hosts that are gone are deleted after
  7 days, the next time any terminal is created.
```

- [ ] **Step 4: Survey status**

In `docs/terminal/2026-09-19-terminal-reference-survey.md`, replace the table row (line 123):
```
| §6.3 | Partial | Plan C — replay with block marks and flow-control acks. Not done: resize-aware ring, a pty-host heartbeat (the 15 s WebSocket heartbeat to mux clients predates the survey), mirror persistence across restarts. |
```
with:
```
| §6.3 | Partial | Plan C — replay with block marks and flow-control acks. Roadmap Plan 4 (2026-09-24) — a pty-host that fails 3 reaper probes in a row is marked hung and its pane offers Restart terminal; the mirror's attach replay is saved every 60 s and replayed into the next host for a relaunched session. Not done: resize-aware ring. |
```
and replace the status line under `### 6.3` (line 3672):
```
> **Status: Partial.** Plan C — replay with block marks and flow-control acks. Not done: resize-aware ring, a pty-host heartbeat (the 15 s WebSocket heartbeat to mux clients predates the survey), mirror persistence across restarts.
```
with:
```
> **Status: Partial.** Plan C — replay with block marks and flow-control acks. Roadmap Plan 4 (2026-09-24) — hung pty-host detection (3 consecutive failed reaper probes, `ptyhost/health.go`) with Restart terminal, and mirror persistence across a host's death (`ptyhost/persist.go`). Not done: resize-aware ring.
```
Then confirm the counts at line 50 are unchanged (§6.3 stays Partial):
```bash
awk -F'|' '/^\| §[0-9]/ {gsub(/^ +| +$/,"",$3); print $3}' "$REPO/docs/terminal/2026-09-19-terminal-reference-survey.md" | sort | uniq -c
```
Expected: `36 Done`, `1 N/A`, `26 Not done`, `1 Not needed`, `7 Not pursued`, `17 Partial` — matching "36 done, 17 partial, 26 not done, 7 not pursued, 1 not needed, 1 n/a" on line 50, which is left as is.

- [ ] **Step 5: Plain-language doc**

In `docs/terminal/2026-09-24-not-done-plain-language.md`, replace (lines 132-136):
```
- **Crash recovery:** if the helper process that runs a terminal hangs,
  nothing notices or restarts it, and if it dies (or the Mac reboots) the
  terminal's history is lost because it is never saved to disk (§6.3).
  Terminals do survive a daemon or app restart: the helper outlives the
  daemon and is found again.
```
with:
```
- **Crash recovery (built 2026-09-24, roadmap Plan 4):** if the helper
  process that runs a session's terminal stops answering for about 15
  seconds, the terminal says "This terminal stopped responding." and offers
  **Restart terminal**, which stops the stuck helper and resumes the agent in
  a new one. If a helper dies (or the Mac reboots), its recent history, up to
  about 11,000 lines, was saved to disk once a minute and comes back when the
  session is restored. Still missing: the board does not show a stuck
  terminal, shells are not checked, and a replay is not redrawn at the sizes
  the output was produced at (§6.3).
```
and replace (line 152):
```
- **Crash recovery (partial list):** a stuck terminal fixes itself.
```
with:
```
- **Crash recovery (partial list):** a stuck terminal is noticed and restarts
  with one click; built 2026-09-24 (roadmap Plan 4).
```

- [ ] **Step 6: Commit**

```bash
cd "$REPO" && git add TERMINAL.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/terminal/2026-09-24-not-done-plain-language.md
git commit -m "docs(terminal): record crash recovery (roadmap Plan 4)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: Final gates, push, completion report

**Files:**
- Modify: `docs/superpowers/specs/2026-09-24-crash-recovery-measurement.md` ("After" section)

- [ ] **Step 1: Backend gates**

```bash
cd "$REPO/backend" && test -z "$(gofmt -l .)" && echo "gofmt clean"
cd "$REPO/backend" && go build ./... && go vet ./... && echo "build+vet ok"
cd "$REPO/backend" && go test ./... 2>&1 | tee "$HOME/plan4-evidence/final-go-test.txt" | grep '^FAIL' || echo "no failing packages"
cd "$REPO/backend" && go test -race ./internal/adapters/runtime/ptyhost/... ./internal/terminal/... ./internal/session_manager/... ./internal/service/session/... ./internal/httpd/... -count=1 2>&1 | grep -E '^(ok|FAIL)'
cd "$REPO/backend" && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs 2>&1 | tail -3
```
Expected: `gofmt clean`; `build+vet ok`; `no failing packages` or exactly the Task 0 baseline list (diff it: `diff <(grep '^FAIL' "$HOME/plan4-evidence/baseline-go-test.txt") <(grep '^FAIL' "$HOME/plan4-evidence/final-go-test.txt")` prints nothing); every `-race` package `ok`; lint `0 issues.`.

- [ ] **Step 2: API drift gate**

```bash
cd "$REPO" && npm run api >/dev/null 2>&1 && git status --short backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
```
Expected: no output (the committed artifacts equal a fresh generation).

- [ ] **Step 3: Frontend gates**

```bash
cd "$REPO/frontend" && npm run typecheck 2>&1 | tail -2
cd "$REPO/frontend" && npx vitest run 2>&1 | tail -6
cd "$REPO/frontend" && npm run lint 2>&1 | tail -2
```
Expected: typecheck exits 0; full vitest suite passes (compare with a `development` run if anything fails: `git stash` is forbidden — use a scratch worktree: `git worktree add "$HOME/plan4-base" origin/development` and run the same command there, then `git worktree remove "$HOME/plan4-base"`); lint `0 errors`. Record `not run: <reason>` for any gate the Task 0 toolchain could not support. `packages/terminal` suites and benches: **not run — not touched by this plan** (roadmap rule: benches for plans that touch rendering).

- [ ] **Step 4: Measurement note "After" section**

Replace `<filled by Task 10>` in `docs/superpowers/specs/2026-09-24-crash-recovery-measurement.md` with:

```markdown
Cloud session: repeat Task 1 Steps 1–7 with the branch's `opr` if a daemon can run; record the same table. Expected: SIGSTOP — within ~17 s the daemon logs `terminal host stopped responding id=<SID>` and the open pane receives a `health hung` frame; `POST /api/v1/sessions/<SID>/restart-terminal` returns 200 and the pane receives `exited` or new `data`; `~/.operator/pty-host-history/<SID>.vt` exists after the first minute of output. Results: <… or not run: reason>.

Local, by the reviewer (desktop app, `npm run tauri:dev` with the scrubbed env):
1. Open a Claude session, produce output, wait 70 s; `ls -l ~/.operator/pty-host-history/` shows `<id>.vt`.
2. `kill -STOP <pty-host pid>` (pid from `~/.operator/windows-pty-hosts.json`); within ~17 s the pane shows "This terminal stopped responding." with Restart terminal; `kill -CONT` instead → the strip goes away by itself.
3. STOP again, click Restart terminal → the pane reconnects to a new host, Claude resumes the conversation, the old output is still above it; note whether any rows are duplicated (TERMINAL.md §5, restart bullet).
4. `kill -KILL <pty-host pid>`; after the session shows as ended, click Restore → the pane shows the saved history above the new process.
Results: <…>
```

- [ ] **Step 5: Commit and push**

```bash
cd "$REPO" && git add docs/superpowers/specs/2026-09-24-crash-recovery-measurement.md
git commit -m "docs(terminal): crash recovery after-measurement plan and results

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git push -u origin terminal/plan-4-crash-recovery
git log --oneline origin/development..HEAD
```
Expected: the push succeeds; the log lists 10 commits (Tasks 1–10). Do not merge.

- [ ] **Step 6: Completion report**

Reply with, in this order:
1. Branch and head commit; the commit list.
2. Every gate from Steps 1–3 with its last output lines, or `not run: <reason>`.
3. Task 1's before-table (or `not run: <reason>`), and the cloud "After" results.
4. Anything that deviated from this plan, with the file:line and why.
5. The local real-app checklist from Step 4 for the reviewer, unchanged.
