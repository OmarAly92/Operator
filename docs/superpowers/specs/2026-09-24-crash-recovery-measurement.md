# Crash recovery — measurement (roadmap Plan 4)

**Date:** 2026-09-24. **Branch:** `terminal/plan-4-crash-recovery`. **Plan:** `docs/superpowers/plans/2026-09-24-terminal-plan-4-crash-recovery.md`.

## Before (Task 1)

Environment: cloud Linux sandbox (Debian, kernel 6.18.44-fc-v37), daemon `opr daemon` built from this branch (`go build -o $REPRO/opr ./cmd/opr`, exit 0) on 127.0.0.1:3102, isolated `OPERATOR_DATA_DIR=$REPRO/data`, `OPERATOR_RUN_FILE=$REPRO/running.json`. All `CLAUDE*` env vars were unset in the daemon's shell before launch. A real `claude` CLI was present (`/opt/node22/bin/claude`) and a session spawned successfully, so the session-terminal case ran for real rather than being skipped.

Session used: `repro-1` (harness `claude-code`, spawned via `POST /api/v1/sessions` against a throwaway `git init` repo). Its pty-host was pid 2455, found in `~/.operator/windows-pty-hosts.json` matching `sessionId: "repro-1"`. Shell terminal used: `shellterm-62169ab4692ccc12`, pty-host pid 5685, found in the same registry file (the shell terminal's `handleId` is stored under the registry's `sessionId` key).

| Case | What the open pane received (mux frames) | Daemon log | `GET /sessions/<id>` (status, activity, isTerminated) |
|---|---|---|---|
| Session host SIGSTOP, 40 s | `0.0s resize`, `0.0s opened`, `0.0s data 2949 bytes`, `0.0s data 3483 bytes`, then silence for the rest of the 40 s window — no `exited`, no `error`, no `health` frame (no health frame exists yet pre-Plan-4) | 8 lines, all `level=DEBUG msg="reaper: probe error reported as failed fact" session=repro-1 err="read tcp ...: i/o timeout"`, one every 5 s from 20:32:32 to 20:33:07 (the reaper's `DefaultTickInterval`), no other terminal/pty/reaper lines | `idle`, `activity: {state: idle, lastActivityAt: 2026-09-24T20:32:15Z}` (unchanged from before the stop), `isTerminated: false` — the session stayed live and its recorded activity state did not move, confirming D1's premise that the SIGSTOPped host is invisible above the reaper's debug-level probe log |
| Session host SIGKILL, 30 s | `0.0s resize`, `0.0s opened`, `0.0s data 4572 bytes`, then `1.1s exited` — the mux pushed an `exited` frame 1.1 s after the SIGKILL | 0 matching lines in the 30 s tail (`grep -iE 'probe\|pty\|terminal\|reaper\|terminat'` found nothing — the log filled with other daemon activity in that window but none matched these terms) | `terminated`, `activity: {state: exited, lastActivityAt: 2026-09-24T20:33:20Z}`, `isTerminated: true` — the session was terminated essentially immediately (well under the ~60 s recent-activity window the plan's code-reading prediction expected; the actual behavior on this build is faster than predicted, presumably because the closed TCP connection from the killed host resolves `IsAlive` synchronously rather than waiting out an activity window) |
| Shell host SIGSTOP, 25 s | `0.0s resize`, `0.0s opened`, `0.0s data 5 bytes`, then silence for the rest of the 25 s window | 0 matching lines (`grep -iE 'probe\|pty\|terminal\|reaper\|shellterm'` found nothing in the 25 s tail) — confirms D2: the reaper only iterates session rows, so a shell terminal's pty-host is never probed and its hang produces no reaper log activity at all | n/a (no session row) |

What the desktop pane and board show in each case: not known from this run (no desktop app in this session); the reviewer fills this in locally.

## Replay size and cost (read-only, 2026-09-24, `claude-long-50k`)

- Mirror rows at the product cap: 60,097. Attach frame (`Replay(1000)`): 17,318 bytes. Full history: 116 chunks, 937,856 bytes, 2,734 ms.
- Newest 20 chunks + frame: 179,607 bytes in 491 ms; 1 chunk + frame: 25,540 bytes in 52 ms. One `Replay(1000)` at 60k rows: ~24 ms.
- Command: `OPERATOR_AGENT_FIXTURE=$REPO/packages/terminal/bench/agent-session/fixtures/claude-long-50k go test ./internal/adapters/runtime/ptyhost/vtwasm/ -run TestAgentSessionReplayReport -v -count=1` (run from `backend/`). Not re-run in this session; carried forward from the plan's own D7 measurement, cited here as read-only reference data, not re-verified.

## After (Task 10)

<filled by Task 10>
