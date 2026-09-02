# TODO after removing tmux

Open work left behind by the tmux → pty-host cutover (plan:
`docs/superpowers/plans/2026-09-01-tmux-free-pty-runtime.md`). Gate 1 (parity)
passed 11/11. Gate 2 (benchmarks) was **closed on partial evidence by explicit
decision on 2026-09-02**, not because the numbers came in. This file is the
record of what was not proven and what was given up.

## 1. The scroll A/B was never run against tmux

`scroll-latency` is the benchmark that represents the original complaint, and it
has no tmux number. Two independent reasons, and fixing the first does not fix
the second.

**tmux structurally cannot produce the measurement.** The scenario sends one SGR
wheel report (`\x1b[<64;1;1M`) and waits for an alt-screen responder in the pane
to echo `__OPERATOR_SCROLL_RESPONSE__`. The tmux adapter set `mouse on` per
session, so tmux consumed the wheel itself and entered copy-mode — an absorbing
state. The report never reached the PTY application, no marker was ever echoed,
and the harness hung at iteration 1 until timeout. Confirmed on two runs; while
stalled, `tmux display -p '#{alternate_on} #{pane_in_mode}'` read `1 1` and the
responder was healthy in the pane. Cancelling copy-mode by hand did not rescue
the run, because the harness never retries a scroll it already dispatched.

**The metric is vsync-quantized at its floor.** ptyhost measured p50 and p95 of
exactly **17.000 ms** — one 60 Hz frame, identical to its own input-latency, with
zero variance. Even with tmux measurable, the instrument can show tmux worse but
cannot resolve how much better ptyhost is.

**To actually settle it:** redefine the scroll acknowledgement as *wheel
dispatched → next frame painted* rather than waiting for an application-level
marker. That is what a user perceives as jank, and both runtimes can produce it.
Doing so requires a tmux to compare against, which this cutover deleted — so it
would mean benchmarking against a tagged pre-cutover commit.

## 2. Benchmark scenarios that never ran

| Scenario | Status | Cause |
|---|---|---|
| `vtebench` | not run, both runtimes | the workload shells out to a `vtebench` binary (`frontend/perf/terminal/harness.tsx:149`) that is not installed and has no brew formula |
| `reconnect` | stalls, both runtimes | one `/mux` upgrade lands, then nothing for 20+ min with zero attached clients. Not a runtime difference. Also leaves the spec's open question about a rendered ring snapshot unanswered |
| `cpu-time`, `active-memory` | **fix implemented (2026-09-02), not end-to-end verified** | both wait on `waitForTauriDaemon(stateRoot)` / `readDaemonProcessId(stateRoot)` (`frontend/scripts/benchmark-terminal.mjs`), but `frontend/src-tauri/src/lib.rs`'s setup skips the auto-start (`if audit_mode.is_none() && !terminal_benchmark`) under `OPERATOR_TAURI_TERMINAL_BENCHMARK=1` — deliberately: benchmark mode registers `daemon_start` as an invokable command instead, the same pattern audit mode uses, so the harness page is expected to start it explicitly. It never did. Fixed by having `frontend/perf/terminal/main.tsx` call the new `startTauriDaemonForScenario` (`frontend/perf/terminal/runtime.ts`), which invokes `daemon_start` for exactly the `cpu-time`/`active-memory` scenarios that need it. Unit-tested (`runtime.test.ts`) and the terminal-perf Vite build is clean, but not run against a live Tauri harness — that needs an actual desktop session to launch the app and confirm `running.json` appears, which this pass did not have. Ruled out a port collision earlier by re-running on `OPERATOR_PORT=3055` — identical failure, consistent with this being the real cause. |

## 3. What the evidence that *did* land actually shows

Not a scroll number, but it points the same way and is worth keeping:

- **`large-output`.** On the identical 16 MiB workload, tmux emitted ~332 KB of
  extra bytes (≈2%, deterministic over 3 runs: 17,109,653 / 17,099,773 /
  17,100,707 against an expected 16,777,216). That exceeds the harness's 64 KiB
  tolerance, so `assertObservedOutputBytes` throws and no tmux result is written
  at all. ptyhost came in at 16,778,226 — over by 1,010 bytes, or 0.006%. The
  excess is tmux's redraw injection, the same mechanism behind the scroll jank.
- **`input-latency`: no regression.** ptyhost p50 17 / p95 18 against tmux p50 17
  / p95 17. Both are one frame; the 1 ms is quantization, not signal.

## 4. Test coverage deleted with the adapter

Three integration tests exercised real behaviour through a real tmux server and
had no ptyhost equivalent, so they were deleted rather than ported:

- `internal/terminal/attachment_integration_test.go` — attached a real PTY to a
  real tmux pane, asserted output streams back and that killing the session stops
  the stream.
- `internal/observe/activity/observer_integration_test.go` — drove real pane
  output through the observer into SQLite.
- `internal/integration/shell_blocks_tmux_test.go` — shell blocks over tmux.

Porting them means spawning a real `opr pty-host` binary, which
`backend/internal/adapters/runtime/parity/parity_test.go` already does via
`realHostSpawner` — that helper is the starting point. Until then the closest
live coverage is the parity package (`TestCaptureSupervisorAgainstPtyHost`) and
the ptyhost unit suite.

**PORTED (2026-09-02).** All three restored against a real `opr pty-host`, using
a new shared helper, `backend/internal/testsupport/realpty/`, that factors the
build-once/spawn/READY-handshake shape out of parity's `realHostSpawner` so it
doesn't require the `parity` build tag or tmux. Porting them surfaced three
real bugs, not test-harness artifacts — each reproduced deterministically,
verified failing without its fix, and (for the first two) fixed and verified
passing:

1. **`defaultSpawnHost`/`realHostSpawner` never reaped the detached pty-host
   process.** `cmd.Start()` with no `cmd.Wait()` anywhere leaves a zombie for
   the daemon's lifetime once the process exits, and `pidAlive`'s `kill(pid,
   0)` still reports a zombie as alive — so `Destroy` could spuriously report
   `"pty-host pid %d is still alive after teardown"` for a process that had
   already exited. Fixed in `ptyhost/spawn_unix.go` (and the test-only
   spawner in `realpty`) by reaping in a background goroutine right after
   `Start()`. Regression: `TestDefaultSpawnHostReapsExitedProcess`
   (`ptyhost/spawn_unix_test.go`).
2. **`Attach` deadlocked on any session with existing scrollback.** The host
   always sends the ring snapshot as the first `MsgTerminalData` frame before
   answering anything else, and `loopbackStream.pump()` wrote that frame
   straight into an unbuffered `io.Pipe` — which blocks until `Read` drains
   it, and nothing reads the returned `Stream` until `Attach` itself returns.
   Any real attach (every one passes a birth size) to a session that had
   already produced output hung for `attachResizeAckTimeout` (5s) and then
   failed. This is plausibly part of what this file's §2 called "reconnect
   stalls." Fixed in `ptyhost/attach.go` by decoupling pump's parsing from
   the pipe write via an internal queue + forwarder goroutine, so a pending
   large write never blocks pump from processing the status reply behind it.
   Regression: `TestAttachWithScrollbackAndSizeDoesNotDeadlock`
   (`ptyhost/attach_test.go`).
3. **`captureSink.write` blocked `deliver()`, the pump loop's own hot path,
   whenever the capture subprocess didn't drain fast enough.** Same shape as
   #2, one level up: `write()` wrote straight to the capture tee's stdin pipe
   from inside `deliver()`, so a stalled or slow consumer stalled ring
   append and client broadcast for the entire session, not just capture.
   Fixed the same way (queue + forwarder goroutine in `ptyhost/capture.go`);
   regression `TestCaptureBackpressureDoesNotStallDelivery`
   (`ptyhost/capture_test.go`). This measurably improved (from 150s+ hang to
   a clean, fast failure) but did not fully resolve the fourth bug below.
4. **UNRESOLVED — `handleConn` writes the ring snapshot to every new
   connection, under `h.mu`, before its own read loop ever runs.** Every
   one-shot client RPC (`SendMessage`, `SendInput`, `Interrupt`, ...) dials,
   writes its own frame, and closes without ever reading a reply. Once the
   ring snapshot exceeds the OS socket buffer, the server's write blocks —
   which blocks `h.mu` for the whole session, and means this connection's own
   read loop, which would have parsed its input frame, never starts. The
   input is silently dropped, not delayed. Reproduced deterministically with
   ~4MB of ring content and no shell involved:
   `TestSnapshotWriteOnOneShotConnDoesNotDropInput`
   (`ptyhost/host_test.go`, `t.Skip`'d, verified failing when un-skipped).
   `TestShellBlocksBoundedJournalRecordsGapAndRecovers`
   (`integration/shell_blocks_tmux_test.go`) hits this for real with a 10MB
   fill and is `t.Skip`'d with the same explanation; the other six
   `TestShellBlocks*` tests pass. Left unfixed: the correct fix has to stop
   serializing an unbounded write ahead of a connection's own reads without
   reintroducing the duplicate-replay race `handleConn`'s current locking was
   already written to prevent (see its own comment) — a genuine concurrency
   change to hot-path connection handling that needs dedicated review, not a
   fix bundled into an unrelated task.

`internal/daemon/session_id_claim_integration_test.go` was **ported**, not
deleted — see below.

## 5. Carried over deliberately

- **Session-id claim probe.** Deleting tmux removed the only implementation of
  `ports.SessionIDClaimChecker`, which would have left `sessionIDClaimProbe`
  returning nil forever and reopened the "database hands out an id a live
  process still holds" bug on a fresh install or reset data dir. `ptyhost`
  now implements it in `backend/internal/adapters/runtime/ptyhost/claim.go`,
  backed by the on-disk pty-host registry (which prunes dead PIDs), and the
  integration test was rewritten against it.
- **`ptyexec` was kept.** The plan said to delete it if nothing else used it.
  After the tmux adapter went, `internal/httpd/terminal_mux_test.go` still spawns
  through `ptyexec.Spawn`, so it stays.

## 6. Capability queries have no answerer

With tmux gone, nothing answers terminal capability queries (XTVERSION, Primary
DA) when no client is attached: xterm.js answers them but only while attached,
and `vt-core` never does. tmux always did, because it *was* the emulator on the
agent's PTY. Deferred on evidence rather than assumption — ConPTY has shipped on
Windows with exactly this behaviour and nothing has traced back to it. If it ever
bites, the passive parser already sees the query, so the fix stays off the hot
path. Recorded in
`docs/superpowers/specs/2026-09-01-tmux-free-pty-runtime-design.md`.

## 7. Found while landing this, worth knowing

- **Attach replayed a whole batch twice.** `deliver()` appended to the scrollback
  ring and broadcast to clients under two different locks, so a client connecting
  in that window received the batch in its snapshot *and* again live — up to a
  full `readBufferSize` of duplicated output at the moment of attach. Both halves
  now happen under one `h.mu` hold, matching what `handleConn` already did for
  snapshot-and-register. Reproduced at ~1% (4 failures / 400 runs) before the fix
  and 0 / 400 after.
- **`Ring.Snapshot()` deliberately excludes the in-progress partial line**, so a
  client attaching mid-line sees nothing of it until the next newline. This
  mirrors the original TypeScript implementation and was left as-is, but it means
  output with no newlines is invisible to a fresh attach. Worth revisiting if a
  user ever reports a blank pane on attach under a long-running progress line.

## 8. OPEN: the attach and capture queues are unbounded

**Status: known regression, not yet fixed. This is the highest-value item in
this file.**

Fixing the attach deadlock (see below) replaced two direct, blocking writes with
unbounded in-memory queues, and that silently removed end-to-end back-pressure
from the terminal hot path.

The chain used to be load-bearing. `pump` wrote each payload straight into an
unbuffered `io.Pipe`; that write blocked until `Read` drained it, so `pump`
stopped reading the socket, the TCP receive buffer filled, the host's
`broadcastLocked` blocked on `conn.Write`, `deliver` blocked behind it, the host
stopped reading the PTY, and the child process finally blocked on write. A
`yes`-style flood throttled itself all the way back to the process producing it.

Now `pump` never stops reading: it copies every `MsgTerminalData` payload onto
`loopbackStream.dataQ`, which has no bound. A client that stalls — a suspended
laptop, a slow network, a wedged renderer — makes the daemon accumulate the
entire output stream in memory. `captureSink.write` has the identical shape one
level up: `deliver()` no longer blocks, so a stalled `opr pane-capture`
subprocess grows `captureSink.queue` without limit.

The comment on `pump` currently claims the design "still blocks until Read drains
it, preserving back-pressure and order." Ordering is preserved. Back-pressure
toward the *host* is not, and that was the half that bounded memory.

**The fix is structural and cheaper than bounding the queues.** Do the
resize/status round-trip synchronously on the connection *before* starting
`pump`. The pipe is then not involved during the handshake at all, `pump` keeps
its blocking direct write and full back-pressure, and the only thing needing a
buffer is the ring snapshot — already capped at `MaxOutputLines = 1000`. That
also removes the reason `forwardData` exists. `TestAttachWithScrollbackAndSizeDoesNotDeadlock`
already covers the deadlock any replacement has to keep fixing; it was verified
to fail without the current fix, so it is a real guard.

Root cause worth recording: the deadlock itself was introduced earlier in the
same cutover by `awaitApplied`, added to close a genuine resize race. It blocks
`Attach` on a status reply that can only arrive after the snapshot has been
drained by a reader that does not exist until `Attach` returns. Every real attach
passes a birth size, so every session with prior output hung. The parity suite
missed it because those sessions start with an empty ring.

## 9. Plan steps still unchecked

Five GUI/manual verification steps in the plan (lines 785, 1119, 1689, 1831,
1840) were deferred for want of a display session and remain unchecked.
