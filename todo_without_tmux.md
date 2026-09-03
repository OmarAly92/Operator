# TODO after removing tmux

Open work left behind by the tmux → pty-host cutover (plan:
`docs/superpowers/plans/2026-09-01-tmux-free-pty-runtime.md`). Gate 1 (parity)
passed 11/11. Gate 2 (benchmarks) was **closed on partial evidence by explicit
decision on 2026-09-02**, not because the numbers came in. This file is the
record of what was not proven and what was given up.

## 1. The scroll A/B was never run against tmux

**RETIRED (2026-09-03).** `scroll-latency` has been removed from the benchmark suite
entirely — the scenario, the harness's alternate-screen responder machinery, the
`REQUIRED_SAMPLES`/`REQUIRED_WARMUPS` entries, and the CLI's scenario set. Two reasons,
both already recorded below: the metric is vsync-quantized at its floor (ptyhost
measured p50 = p95 = exactly 17.000ms, one 60Hz frame, zero variance), so the
instrument could show a runtime worse but could never resolve how much better ptyhost
is; and the only thing it would have been compared against, tmux, no longer exists in
this codebase. What stands in its place is the user's confirmation, 2026-09-02, that
scroll is good in real use — the thing this benchmark was a proxy for. The historical
record below (why it was never run, what the numbers meant) is kept as-is; the
`darwin-arm64-tauri-scroll-latency-runtime-ptyhost.json` result file is kept too, as
recorded evidence, not a live fixture.

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

**Confirmed good in real use, 2026-09-02.** The user, using the terminal daily after
the cutover, reports the scroll is good. That is the thing this benchmark was a proxy
for, so what remains below is a **missing measurement, not a suspected regression** —
nobody should read this section as an open scroll bug.

**To actually settle it numerically:** redefine the scroll acknowledgement as *wheel
dispatched → next frame painted* rather than waiting for an application-level
marker. That is what a user perceives as jank, and both runtimes can produce it.
Doing so requires a tmux to compare against, which this cutover deleted — so it
would mean benchmarking against a tagged pre-cutover commit.

## 2. Benchmark scenarios that never ran

**Harness runnable again (2026-09-03).** Phase 7 deleted `frontend/perf/terminal/`
and `frontend/vite.terminal-perf.config.ts` along with xterm, which left
`benchmark-terminal.mjs` pointing at paths that no longer existed — the runner could
not execute at all, regardless of the fixes below. The harness has been rebuilt
against the package renderer (`@operator/terminal-core` + `@operator/terminal-renderer-dom`'s
`DomBlockRenderer`, not xterm), so the pipeline runs again. That is a necessary
precondition for re-running these scenarios, not the re-run itself — the fixes below
still need actual measured evidence, which this pass did not collect.

| Scenario | Status | Cause |
|---|---|---|
| `vtebench` | not run, both runtimes | the workload shells out to a `vtebench` binary (`frontend/perf/terminal/harness.tsx`) that is not installed and has no brew formula |
| `reconnect` | **fixed 2026-09-02**, not yet re-run | `forceDisconnect` called `mux.dispose()`, which is deliberately silent: it clears `connectionListeners` before closing the socket, so `setConnectionState` early-returns and the `"closed"` transition never arrives. That transition is what bumps `attachmentGeneration`, so the attach effect never re-ran, nothing re-attached, and the run stalled at the first sample — matching the observed "one `/mux` upgrade, then zero attached clients". `forceDisconnect` now bumps the generation itself. The pre-existing unit test missed it because it emitted `"closed"` straight onto a fake mux, bypassing `dispose()`; the new test drives the real `operator:terminal-benchmark-reconnect` event and fails without the fix. Still leaves the spec's open question about a rendered ring snapshot unanswered until the scenario is actually run |
| `cpu-time`, `active-memory` | **fix completed 2026-09-02**, not end-to-end verified | Two defects, both now fixed. (1) Benchmark mode deliberately skips the daemon auto-start (`if audit_mode.is_none() && !terminal_benchmark`) and registers `daemon_start` as an invokable command instead, but the harness page never called it — `frontend/perf/terminal/main.tsx` now calls `startTauriDaemonForScenario`, gated to exactly these two scenarios. (2) That fix could not have worked on its own: the benchmark window runs under the `terminal-benchmark` capability, which granted only `allow-terminal-benchmark-runtime-identity`, so the `daemon_start` invoke would have been denied by Tauri's capability system — `allow-daemon-start` is granted to the `main` window only, in `phase0.json`. The capability now grants it, pinned by a Rust test that fails when the permission is removed. Still needs a desktop session to confirm `running.json` appears end to end. A port collision was ruled out earlier by re-running on `OPERATOR_PORT=3055` |

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
verified failing without its fix, then fixed and verified passing. The fourth,
found while fixing the third, was left open at the time and was fixed on
2026-09-02:

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
4. **RESOLVED (2026-09-02) — `handleConn` wrote the ring snapshot to every new
   connection, under `h.mu`, before its own read loop ever ran.** Every
   one-shot client RPC (`SendMessage`, `SendInput`, `Interrupt`, ...) dials,
   writes its own frame, and closes without ever reading a reply. Once the
   ring snapshot exceeded the OS socket buffer the server's write blocked —
   which blocked `h.mu` for the whole session, and meant this connection's own
   read loop, which would have parsed its input frame, never started. The
   input was silently dropped, not delayed. Confirmed from a goroutine dump,
   both halves at once: `handleConn` parked in `conn.Write` at `host.go:432`
   with ~3.9MB pending while holding `h.mu`, and `deliver` parked on
   `sync.Mutex.Lock` at `host.go:336`.

   **Fix: a per-client outbound queue drained by a dedicated writer
   goroutine** — the upgrade path the old `ponytail:` comment on `handleConn`
   already named. Every frame the host sends a client (snapshot, live
   broadcast, per-connection replies) is queued by `clientState.enqueue`
   instead of written inline; `runWriter` does the blocking `conn.Write` on
   its own goroutine, and `dropClient` is now the single place the write path
   retires a connection. `handleConn` reaches its read loop immediately.

   The duplicate-replay race that the old locking existed to prevent is
   intact: the ring snapshot is still taken, queued, and the conn still
   registered under a **single** `h.mu` hold, and `deliver` still appends to
   the ring and queues to every client under that same hold. Ordering is
   unchanged because the queue is per-client FIFO — the snapshot is queued
   first, anything broadcast afterwards lands behind it — so a client can
   still neither see a batch twice nor miss one. Only the blocking write moved
   off the lock. `TestScrollbackLiveOrdering_NoDrop` still covers this.

   Back-pressure is preserved rather than traded away, which is the mistake
   §8 records. `enqueue` cannot block (it runs under `h.mu`), so `deliver`
   parks in `awaitCapacity` *after* releasing the lock, once a client's
   backlog passes `maxQueuedClientBytes` (four read buffers, matching
   `maxQueuedCaptureBytes`). That stalls `pumpPTY`, stops the PTY being read,
   and lets the child throttle itself — the same chain, minus the frozen lock.
   A batch can overshoot the cap by one batch, and that is the asserted bound.

   Three tests, each verified to fail without the fix:
   `TestSnapshotWriteOnOneShotConnDoesNotDropInput` (un-skipped; fails if the
   snapshot is written inline again), `TestWedgedClientDoesNotBlockOtherClients`
   (a client that never reads must not block another client's status RPC,
   which goes through `currentPTY()` and so takes `h.mu`), and
   `TestClientQueueIsBounded` (with the cap disabled the queue reached 16MB
   against a 1.25MB limit). `TestShellBlocksBoundedJournalRecordsGapAndRecovers`
   (`integration/shell_blocks_tmux_test.go`) is **un-skipped and passing** —
   it was the real-world 10MB-fill case that surfaced this.

   Not changed, and worth knowing: a wedged client still eventually stalls
   session output, now after a bounded 1.25MB instead of immediately. That is
   the intended back-pressure semantics, not a defect. Bounding *how long*
   deliver waits on a dead client would be a behaviour change beyond this fix.

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
- **`ptyexec` was kept, then deleted (2026-09-02).** The plan said to delete it
  if nothing else used it. After the tmux adapter went its only caller was
  `internal/httpd/terminal_mux_test.go`, so it stayed. It is now gone: that
  test's one need — a real PTY behind a `ports.Stream` — moved to
  `spawnTestPTY` in `internal/httpd/pty_spawn_test.go`, a `!windows` test-only
  helper that cannot be reached from production code. `terminal_mux_test.go`
  carries the same build tag instead of skipping on Windows at runtime, since
  both of its tests already did. `creack/pty` and `go-pty` stay in `go.mod`:
  `ptyhost` uses them (`host_pty_unix.go`, `host_conpty_windows.go`).

  Dropped with the package, deliberately, because they described attach-client
  semantics that no longer exist: the SIGWINCH re-assert after `Setsize` (for
  an attach client that re-reads the tty and re-reports its grid) and the
  Windows ConPTY spawner. The idempotent SIGTERM→SIGKILL `Close` was kept —
  the run loop and `attachment.close` both call `Close` on the same stream, and
  a second concurrent `cmd.Wait` blocks forever.

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

## 8. RESOLVED: the attach and capture queues are no longer unbounded

**Fixed 2026-09-02.** Kept here because the reasoning is the reason the code
looks the way it does.

The attach deadlock fix had replaced two direct, blocking writes with unbounded
in-memory queues, and that silently removed end-to-end back-pressure from the
terminal hot path. The chain is load-bearing: `pump` writes each payload into an
unbuffered `io.Pipe`, that write blocks until `Read` drains it, so `pump` stops
reading the socket, the host's send buffer fills, the host stops reading the
PTY, and the child finally blocks on write. A `yes`-style flood throttles itself
all the way back to the process producing it. With an unbounded queue in the
middle, `pump` never stops reading and a stalled client — a suspended laptop, a
wedged renderer — would make the daemon accumulate the entire session in memory.

**Attach: the queue is gone entirely.** The birth resize is now handshaken
synchronously on the bare conn, in `attachHandshake`, *before* any pipe exists —
send `MsgResize`, send `MsgStatusReq`, then read the conn directly under a
5s deadline until `MsgStatusRes` arrives. Frames seen while waiting (the
scrollback snapshot, plus anything the child emitted in that window) are handed
to `pump` to replay ahead of live output, so ordering is unchanged, and they are
bounded: the snapshot is capped at `MaxOutputLines` and live output can only
accumulate for one loopback round-trip. `pump` is back to a direct blocking
write, so back-pressure is whole again, and `forwardData` no longer exists.

Root cause worth recording: the deadlock was introduced earlier in the same
cutover by `awaitApplied`, added to close a genuine resize race. It blocked
`Attach` on a status reply that could only arrive after the snapshot had been
drained by a reader that did not exist until `Attach` returned. Every real
attach passes a birth size, so every session with prior output hung. The parity
suite missed it because those sessions start with an empty ring.

**Capture: the queue stays, but bounded.** `captureSink.write` cannot simply go
back to a direct write — a slow `opr pane-capture` (disk stall, segment
rotation) would stall `pumpPTY` itself, freezing ring append and client
broadcast for the whole session. So the forwarder goroutine remains, capped at
`maxQueuedCaptureBytes` (four read buffers); past the cap `write` blocks. That
absorbs a hiccup but makes a *stopped* consumer apply back-pressure at a fixed
memory cost instead of growing without limit.

Both fixes are pinned by tests verified to fail without them:
`TestAttachAppliesResizeBeforeReturning` fails if the handshake is reduced to a
fire-and-forget resize, `TestAttachWithScrollbackAndSizeDoesNotDeadlock` fails if
`pump` writes the snapshot before the handshake runs, and
`TestCaptureQueueIsBounded` fails if the cap is removed.

## 9. Plan steps still unchecked

Five GUI/manual verification steps in the plan (lines 785, 1119, 1689, 1831,
1840) were deferred for want of a display session and remain unchecked.

## 10. The `input-latency` gate has not caught up with the §9.5 decision

**Done 2026-09-03.** `gate.mjs` now takes an optional `allowance` field alongside
`factor`; `input-latency`'s rule is `{ scenario: "input-latency", compare: "at-most",
factor: 1, allowance: 20 }` and the threshold computes as `theirs * (rule.factor ?? 1)
+ (rule.allowance ?? 0)`. The printed row shows the allowance breakdown, e.g.
`<= 29.00 (xterm 9.00 + 20.00)`.

**Decided 2026-09-02, not yet implemented.** Spec §9.5's open trade — the 60Hz paint
cap fixed the agent-pane jank and cost `input-latency` its gate — was ruled on by the
user in favour of **option 2, amend the contract**, on the evidence that typing feels
fine in real use. The cap stays. What changes is what the gate asks for.

The new contract, now written into §9.4: `input-latency` p95 must be **≤ the recorded
xterm baseline + one 60Hz frame + 3.3ms tolerance**, i.e. `baseline + 20.0ms`. Against
the 9.00ms baseline that is a 29.00ms ceiling, and the measured 24.80ms sits 4.2ms
inside it. The allowance is not slack: with the cap, an echoed byte waits for the next
frame like any other PTY byte, so exactly one frame is the structural cost, and the
measured +15.8ms delta is consistent with one.

**Why the code does not yet do this.** `packages/terminal/bench/gate.mjs:39` is

```js
{ scenario: "input-latency", compare: "at-most", factor: 1 },
```

and the comparison at `:74` computes `threshold = theirs * rule.factor` — multiplicative.
The new rule is additive, so a factor cannot express it. Multiplying instead would need
`factor: 3.22`, which encodes nothing meaningful and would silently scale with any future
baseline change.

**The work:**

1. Add an optional `allowance` (milliseconds) beside `factor` in `RULES`, and make the
   threshold `theirs * (rule.factor ?? 1) + (rule.allowance ?? 0)`.
2. Set `{ scenario: "input-latency", compare: "at-most", factor: 1, allowance: 20 }`.
3. Make the printed row show the allowance, so a reader sees `<= 29.00 (xterm 9.00 + 20.00)`
   rather than an unexplained ceiling.
4. Re-run `npm --prefix packages/terminal run bench:gate` and confirm the suite is
   **fully green** — this is the first time it will be since phase 4, so check every
   scenario, not just this one.

**Do not** use this as a template for widening other gates. The 3.3ms is measurement
noise and the 16.7ms is the cost of one named mechanism. If something later adds a second
frame, remove the frame; do not widen the allowance.

## 11. Open after Phase 7 and the harness restore (2026-09-03)

Three things carried out of the 2026-09-02/03 work. None blocks anything; all
three are cases where the only remaining proof needs a machine, not a change.

### 11.1 Phase 7's GUI verification was never done

Every by-hand step in
`docs/superpowers/plans/2026-09-02-warp-terminal-phase-7-retirement.md` (Tasks 5,
7 and 9) is still unchecked: the executor had no display session, and neither did
the review. Phase 7's accept criteria require these explicitly — *"verified by
running them, not by unit tests alone."*

This is not paperwork. **Two of the three bugs found after the suites were green
were ones only a GUI pass catches**, and one of them — every line-editor render
blurring the composition textarea, so five keystrokes reached the editor once
(`27ef88c90`) — was reported by the user as "so slow to write anything", not by
any test.

What to run:

- **htop** — click a column header to sort, then move the mouse around *without*
  clicking. The second half specifically exercises `4b5acf7ec`, which stopped
  reporting buttonless motion to programs that never set `?1003`.
- **vim** — drag to select.
- **A plain shell, nothing running** — scroll, and confirm the block list still
  scrolls natively. Pinned by a unit test, but that test is the only guard and the
  benchmark cannot see it (§1).
- **CJK through an IME** — the composition target moved in the DOM twice.
- **The Focus Terminal shortcut**, and **Ctrl+K** reaching the shell rather than
  opening the palette.

### 11.2 `bench:terminal` has still never run

The harness is rebuilt and the runner's dead path is gone, but nothing has driven
it end to end. It now reaches `OPERATOR_BENCH_DAEMON_URL is required`, which is
the expected next gate — progress, not proof. Until someone runs it against a live
paired daemon and a desktop session, §2's `reconnect` fix and its
`cpu-time`/`active-memory` fix stay unverified, exactly as §2 says.

```bash
npm --prefix frontend run bench:terminal -- --shell tauri --scenario reconnect
```

`--shell tauri` is mandatory; the electron path attaches to an already-running
daemon and cannot select a runtime.

**Decide one thing before recording numbers.** The harness mounts
`createTerminalCore` + `DomBlockRenderer` directly rather than `TerminalSurface`,
because at the time the surface did not expose `onPaint`. It does now
(`8edaf829c`). Switching the harness would start including React and the line
editor in the measurement, which is closer to what users run but moves the numbers
and breaks comparability with anything recorded before. Switch and re-baseline in
the same run, or stay put deliberately — but do not switch after recording.

### 11.3 `find-500k` has never been measured

`bench:gate` exits non-zero on it — `MISSING`, not `FAIL`. The scenario and its
budget arrived with Phase 5; no result file in `packages/terminal/bench/results/`
has ever carried it, so this predates the tmux work and is not the gate change in
§10. It needs a real browser bench run. Until then `bench:gate` reports 4 of 5
green and one unmeasured, which is worth knowing before reading a red exit code as
a regression.

## 12. `fish.test.mjs` over-asserted on fish's own OSC 133 — fixed 2026-09-03

Found while repairing six unrelated red CI jobs. `.github/workflows/terminal.yml`
installs `fish` via `apt-get`, giving Ubuntu's packaged **3.7.0**; two tests
asserted on `\x1b]133;A` / `133;D;<code>` / `133;A;click_events=1`, which
`fish.fish` never emits — those come from fish's *own* native OSC 133, a 4.0
feature. Operator's protocol is OSC 7000 and works fine on 3.7.0, which the
failing test itself proved by passing its `cmd=` assertions before reaching the
133 ones.

Resolved by gating only the fish-4-only assertions behind a parsed major
version, leaving every OSC 7000 assertion live on all versions, and splitting
the native-133 prompt-mark check into its own test that skips on old fish. No
CI infra change, no product change, no loss of coverage of our own code.
Verified 5/5 with nothing skipped on Homebrew fish 4.8.1.

This was masked until now: the same CI job (`package`) always failed earlier on
the rustfmt/clippy component-install bug, before its steps ever reached
`node --test … fish.test.mjs`.

## 13. The Tauri WebDriver e2e suite is parked on Windows

Found 2026-09-03 while repairing CI. `.github/workflows/tauri-webdriver.yml`
ran a three-OS matrix, but its `build.rs` panicked on every platform before
compiling anything (`resource path ../agent-browser doesn't exist` — the
workflow never ran `browser-runtime:prepare`), so **the Windows leg had never
once executed**. Fixing that exposed the real state of Windows support, in
three layers:

1. **The shell did not compile on Windows or Linux.** `RunEvent::Reopen` is a
   macOS-only variant matched without a `cfg` guard, and windows-sys 0.61 turned
   `HWND` from a tuple struct into a type alias. Both fixed; all three platforms
   compile. This was a *product* bug — `frontend-release.yml` builds all three
   and `tauri.conf.json` bundles nsis/deb/rpm/appimage, so the release pipeline
   was broken too, not just this gate.
2. **The runner died silently on Windows.** `e2e-tauri-run.mjs` spawned
   `npx.cmd`, which Node's CVE-2024-27980 fix rejects; `spawnSync` returned a
   null status that fell through `run.status ?? 1`, exiting 1 with no output.
   Fixed by spawning `@wdio/cli`'s bin through node. The same defect in
   `wdio.conf.ts`'s `onPrepare` (vite dev server) is fixed too.
3. **Still open — the embedded WebDriver never yields a session on Windows.**
   Both specs fail immediately with `No "browserName" defined in capabilities
   nor hostname or port found!` even though `wdio.conf.ts:98` sets
   `browserName: "tauri"`. That message means `@wdio/tauri-service` never
   rewrote the capabilities into a hostname/port, i.e. the driver inside the app
   did not come up. Not diagnosed further.

macOS and Linux are green and prove the same contract, so the matrix now runs
those two and Windows is dropped rather than left permanently red. To pick this
up: restore `windows-latest` to the matrix in `tauri-webdriver.yml` and start by
getting `tauri-plugin-wdio-webdriver`'s server to report its port on Windows —
run the built `operator.exe` with the `e2e` feature by hand and check whether it
is listening at all before touching the wdio side.
