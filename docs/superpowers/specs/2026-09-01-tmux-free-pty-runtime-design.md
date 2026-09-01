# A tmux-free PTY runtime — one host, on every platform

Status: proposed
Date: 2026-09-01
Scope: `backend/internal/adapters/runtime/*`, `backend/internal/cli`,
`backend/internal/ports`, `packages/terminal/crates`, `frontend/perf`

Operator runs every session inside tmux and streams a `tmux attach-session`
client's repaint instead of the agent's own bytes. That second emulator is why
the terminal does not scroll like Warp. This replaces it with the pty-host
runtime that already ships on Windows, generalized to every platform, with a
**passive** VT parser beside the data path rather than inside it.

## Problem

Scrolling in Operator's terminal steps and lags. Investigation on 2026-09-01
isolated the cause by elimination, and the eliminations matter as much as the
conclusion because each one closes off a tempting fix:

- **Not the renderer.** Handing the alternate screen to xterm
  (`VITE_ALT_SCREEN_SURFACE=xterm`, `BlockTerminal.tsx:60`) feels identical to
  the `packages/terminal` DOM grid. Two unrelated renderers, one feel.
- **Not the wheel math.** Warp's pixels→lines conversion
  (`app/src/terminal/model/alt_screen.rs:139`) is the same accumulate-and-truncate
  as ours: add the delta, take whole lines, keep the fraction.
- **Not the transport, and not the daemon.** The decisive A/B was run in Warp
  itself. `claude` on a bare PTY scrolls smoothly. The same `claude`, in the same
  Warp, inside `tmux` with `mouse on`, scrolls exactly like Operator. One
  variable changed.

tmux does not relay output. It parses the agent's escape stream into its own
screen model and re-renders the pane for each attached client on its own event
loop. The agent's efficient scroll-region updates are re-derived as line
rewrites, and the client's paint is paced by tmux rather than by the agent.
Every client inherits this, Warp included.

Operator makes it worse than a plain `tmux attach` would: `Attach`
(`tmux.go:738`) spawns the tmux client under a PTY via `ptyexec`, so the bytes
that reach the renderer are a terminal emulator's rendering of a terminal
emulator's rendering.

### The second bug this uncovered

Windows already runs without tmux, through `conpty`, and answers `GetOutput`
from a raw byte ring (`conpty/ring.go`) — the last N newline-split chunks with
ANSI preserved. tmux answers the same call with a **rendered** pane
(`capture-pane`). For a full-screen TUI that repaints in place with cursor
addressing, those are unrelated strings.

Six call sites read that text to make decisions: activity detection
(`observe/activity/observer.go:126`), agent handoff (`agent_switching.go:295`,
plus the styled read in `composerIsEmpty` at `agent_switching.go:1493`),
message-delivery readiness (`message_delivery.go:76`), the review launcher
(`launcher.go:463`), the stale-idle transition proof
(`interface_transition.go:567`), and the spawn prompt-readiness poll
(`manager.go:3616`). `service/terminalcapture/supervisor.go` additionally
consumes `CaptureState`/`StartCapture`/`StopCapture`, tolerating
`ErrCaptureUnsupported` on Windows today — capture starts actually working on
all platforms after this change. They behave differently per platform today.
Nobody is watching Windows closely enough to have noticed. Unifying the runtime
fixes this as a side effect, and this design treats it as a requirement rather
than a bonus.

## Goals

1. The agent's bytes reach the renderer untransformed. This is the scroll fix and
   everything else is subordinate to it.
2. One runtime on every platform. Delete the tmux adapter and the per-OS
   behavioral split with it.
3. `GetOutput` / `CaptureState` return rendered-screen semantics everywhere,
   matching what `capture-pane` returns today on Unix.
4. No UX regression: detached lifetime, reattach after daemon or app restart,
   several clients at once, resize, restart-in-place, kill.
5. Keep `CGO_ENABLED=0` cross-compilation (`packages/build-binaries.sh:33`, and
   four CI workflows). Four platform binaries built from one machine is an asset,
   not an accident.

## Non-goals

- Making alternate-screen scrolling *continuous*. A full-screen TUI owns its own
  viewport; one row per wheel report is the floor in every terminal, Warp
  included. Fractional-pixel scrolling is only available in the normal-buffer
  blocks view, which is a separate surface.
- Preserving existing sessions across the cutover. Operator is pre-release with
  no users; sessions are disposable and break-changes are explicitly acceptable.
- Reimplementing tmux features Operator never used: windows, panes, splits,
  copy-mode, its config language.

## Decisions

Settled with the user before drafting:

| Question | Decision |
|---|---|
| Scope | All session types — agents, shell terminals, review launches. tmux deleted, not kept as a fallback. |
| Parser | `vt-core` compiled to WASM, executed in Go by `wazero` (pure Go, no cgo). |
| Done criteria | Perf-harness parity against tmux, plus a new scroll-latency scenario. Cutover gated on both. |

The parser decision is the load-bearing one. The alternatives were a second VT
implementation in Go (two emulators to keep in sync, and the drift is silent) or
cgo to `vt-core` (loses `CGO_ENABLED=0`). WASM keeps exactly one implementation —
the same code the renderer already trusts — while preserving the build pipeline.
It carries a performance risk that is gated below rather than assumed away.

## Architecture

```
agent PTY
   │  greedy read, ≤256KB per wakeup, until WouldBlock
   ▼
 host ──┬─► raw broadcast ─┬─► attached clients   (coalesced at 60Hz)  ← HOT PATH
        │                  ├─► scrollback ring    (replayed on attach)
        │                  └─► capture pipe       (when armed)
        └─► vt-core/wasm parser (batched, ≤64KB per slice)  ← queries only
```

**The hot path is a read and a fan-out write.** No parse, no re-render, no
transformation between the agent and the screen. That single property is the
entire fix; every other decision here is in service of not compromising it.

**The parser is passive.** It sits beside the path, never in it. It may lag the
screen by milliseconds because nothing user-facing reads it — only `GetOutput`,
`CaptureState` and activity detection do. This is the distinction from tmux,
which puts its emulator between the agent and every client.

**Process model — keep conpty's.** One detached `opr pty-host` per session,
owning the PTY, exposing it over a loopback socket, recorded in `ptyregistry` so
the daemon recovers sessions after a restart (`conpty/runtime.go:293`). Same
durability tmux provided: survives daemon restart and app quit, does not survive
reboot.

**Package shape.** `conpty` generalizes to `ptyhost`. `host.go` is already
cross-platform by construction — only `conptyConn` is Windows-tagged behind the
`ptyConn` interface (`host.go:21`). The Unix implementation is a `creack/pty`
conn behind that same seam; `creack/pty` is already a dependency
(`backend/go.mod:12`) and `ptyexec` already uses it.

### Borrowed from Warp

Warp's PTY loop answers the throughput questions this design would otherwise
guess at. Four patterns, adopted with their constants — with one honest caveat
up front: Warp itself parses **on** the hot path (`parse_bytes` runs under the
terminal lock inside the read loop), and its raw-bytes broadcast is emitted from
*inside* the emulator after processing (`terminal_model.rs:3287`). Warp gets
away with it because its emulator is in-process and fast. This design is
*more* decoupled than Warp's — the broadcast happens before any parsing — so
Warp's numbers are a floor, not a ceiling.

**Greedy drain with bounded work** (`crates/warp_terminal/src/local_tty/event_loop.rs:26,30`):

```rust
const READ_BUFFER_SIZE: usize = 0x4_0000;  // 256KB read buffer / accumulate watermark
const MAX_LOCKED_READ:  usize = 0x1_0000;  // 64KB max processed under lock
```

Read until `WouldBlock`; when the terminal lock is contended, keep accumulating
instead of blocking, up to the 256KB watermark; yield after 64KB processed so a
firehose (`yes`) cannot starve the loop. The host adopts both bounds. Note the
current conpty pump is a naive one-`Read`-one-broadcast loop with a 32KB buffer
(`host.go:180`) and a 4KB per-client buffer (`host.go:282`) — rebuilding it to
this shape is explicit work, not something the rename inherits.

**Coalesced wakeups** (`app/src/terminal/view.rs:613`): `MAX_WAKEUPS_PER_SECOND =
60`, throttling redraw notification independently of parsing. The host applies
this to *client writes*, with one UX refinement: coalescing must only engage
under load. A lone keystroke echo flushes immediately; the 16ms window arms only
when a flush already happened within the last frame. Adding a fixed 16ms to
interactive echo latency would trade the exact UX this design exists to win.
This matters for the phone client's battery as much as for throughput.

**Raw bytes as a broadcast, consumers subscribe** (`crates/warp_terminal/src/event_listener.rs:26`):
`pty_reads_tx: async_broadcast::Sender<Arc<Vec<u8>>>`, with the allocation
skipped entirely when nobody is subscribed. Warp fans out to a throughput
recorder, a byte recorder, and the shared-session viewer this way. The host uses
the same shape, but taps it *before* the parser rather than after.

**Recording taps the raw broadcast, not the emulator's output**
(`app/src/terminal/recorder.rs:143`; `local_tty/recorder.rs` is the
throughput-metrics sibling). `StartCapture` does the same.

## Components

### `ptyhost` host process

Owns the PTY, the ring, the parser and the client set. Responsibilities:

- **Read loop** — greedy drain per the constants above, replacing the current
  single-read pump.
- **Client fan-out** — raw bytes, coalesced at 60Hz under load, immediate when
  idle, one buffer shared across clients.
- **Scrollback ring** — retained for replay on attach. The ring stays raw; the
  parser is what provides rendered semantics. Cleared on respawn, matching
  `respawn-pane -k`'s blank pane.
- **Passive parser** — a `wazero` module instance holding `vt-core`, fed bounded
  slices, answering screen queries. It must track the PTY's size: `vt-core`
  defaults to 24 rows and only learns its true height via `resize`, so every
  `applyLargestLocked` outcome is mirrored into the parser or the rendered grid
  is wrong from the first session.
- **Sizing policy** — already implemented as `applyLargestLocked`
  (`host.go:95`), and better reasoned than tmux's: it picks the largest client
  *by area* and matches that client exactly, rather than taking a per-axis max
  that would synthesize a grid no client actually has. The comment works the
  example — a 120x30 desktop plus a 55x48 phone must not become a phantom
  120x48. Nothing to build here; it replaces `window-size largest`
  (`commands.go:56`) as-is.
- **Respawn** — kill the child, exec a replacement, keep the socket, ring,
  registry entry and handle. This is `respawn-pane -k` (`commands.go:21`), which
  agent switching depends on.
- **Capture pipe** — spawn the capture argv and tee raw output to its stdin,
  replacing `pipe-pane`.

### Protocol additions

Existing frame layout is unchanged: `[1-byte type][4-byte BE length][payload]`
(`conpty/proto.go`). Existing messages `0x01`–`0x08` keep their meanings. New:

| Type | Direction | Payload | Purpose |
|---|---|---|---|
| `MsgRespawnReq` | client → host | JSON `{cwd, shell, launchCmd, launchId}` | Restart-in-place |
| `MsgRespawnRes` | host → client | JSON `{ok, pid, error?}` | Result |
| `MsgCaptureStartReq` | client → host | JSON `{argv}` | Arm the capture pipe |
| `MsgCaptureStopReq` | client → host | empty | Disarm |
| `MsgCaptureStateReq` | client → host | empty | Query |
| `MsgCaptureStateRes` | host → client | JSON `{pipeOpen, alternateOn}` | `PaneCaptureState` |
| `MsgStyledOutputReq` | client → host | JSON `{lines}` | `GetStyledOutput` |
| `MsgStyledOutputRes` | host → client | UTF-8 text with SGR preserved | Result |

`MsgGetOutputReq` keeps its type but changes meaning: answered from the parser's
rendered grid rather than `Ring.Tail` (`ring.go:71`). That is the fix for the
platform divergence, and it is a behavior change on Windows.

### Capability matrix

What each runtime implements today, and where the new one lands:

| Capability | tmux | conpty today | ptyhost |
|---|---|---|---|
| Create / Destroy / IsAlive | ✅ | ✅ | ✅ inherited |
| Attach (multi-client) | ✅ | ✅ | ✅ inherited |
| SendInput / SendMessage / Interrupt | ✅ | ✅ | ✅ inherited |
| Registry recovery after daemon restart | ✅ (named sessions) | ✅ (`ptyregistry`) | ✅ inherited |
| `GetOutput` — **rendered** | ✅ | ❌ raw ring | ✅ **new**, via parser |
| `GetStyledOutput` | ✅ | ❌ absent | ✅ **new** |
| `PaneCapturer` (3 methods) | ✅ | ❌ `ErrCaptureUnsupported` | ✅ **new** |
| `RuntimeRestarter` | ✅ `respawn-pane` | ❌ absent | ✅ **new** |
| Multi-client sizing policy | ✅ `window-size largest` | ✅ `applyLargestLocked` | ✅ inherited |
| External debug attach | ✅ `tmux attach` | ❌ | ✅ **new**, `opr attach` |

Both `GetStyledOutput` and `RuntimeRestarter` are optional interfaces consumed
via type assertion (`agent_switching.go:1493`, `manager.go:1768`), so Windows
silently takes degraded paths today. Four rows of this table are gaps that must close
before tmux can be deleted, and they are the bulk of the work: rendered
`GetOutput`, styled output, pane capture, and respawn.

### `opr attach <session>`

A hidden CLI that dials a session's loopback host, puts the terminal in raw mode
and pipes both directions. Replaces `tmux attach -t <session>` for debugging, and
is strictly better for that purpose: it exercises the same path the app uses
rather than a second client with different flags. `opr pty-host`
(`cli/ptyhost.go`) is the precedent.

## Verification

Two gates, because they answer different questions.

**Gate 1 — behavioral parity.** The parser must render what tmux renders.

- The existing corpus first: `packages/terminal/protocol/alt-vectors`
  (`htop-frame`, `vim-open`, `less-page`, `less-back`) and `redraw-vectors`
  (`agent-cli-idle`). These exist precisely because this rendering is hard.
- Then a differential harness: drive real sessions, and for each, diff
  `ptyhost.GetOutput` against `tmux capture-pane` on the same byte stream.
  Disagreement is a bug in the parser or in the vectors, and either way it must
  be resolved before cutover.
- Then the four decision sites (activity, handoff, delivery, review) exercised
  against both runtimes with identical agent output.

**Gate 2 — performance.** `frontend/perf/scenarios.json` already defines
`vtebench`, `large-output`, `input-latency`, `reconnect`, `cpu-time` and
`active-memory`, all over `daemon-terminal-mux`. Run each against both runtimes.
One trap must be dismantled first: the harness deliberately strips `OPERATOR_*`
from the child environment (`benchmark-result.mjs`,
`BINDING_ENVIRONMENT_PREFIXES`), so a naive `OPERATOR_RUNTIME=ptyhost` prefix
silently benchmarks tmux twice — the variable must be added to the tauri
spawner's `controlled` allowlist, and every run needs the mandatory
`--shell tauri` flag (the electron path attaches to an already-running daemon,
where env on the bench command cannot select the runtime at all).

- `input-latency`, `cpu-time`, `active-memory`: must not regress.
- `vtebench`, `large-output`: expected to improve (an emulator leaves the path);
  a regression means the wasm parser is on the hot path by accident, which is the
  precise failure this design exists to prevent.
- **New scenario `scroll-latency`**: wheel report in → painted frame out, p50 and
  p95, on an alternate-screen agent session. This is the metric that represents
  the user's actual complaint, and no other scenario captures it. Cutover
  requires beating tmux here decisively.

## Risks

**WASM per-byte overhead — gated, not assumed.** Feeding `large-output`'s 16MB
through `wazero` may be too slow even batched. **Before any other work**, spike
this: `vt-core` in `wazero`, fed 16MB in 64KB slices, measured against the same
bytes through the native Rust core. If throughput is unacceptable, the fallback
is a Go emulator held to the same vectors, and that decision belongs at the start
of the work rather than the middle. Note that today's `vt-wasm` crate is
`wasm-bindgen` (JS glue), so this needs a sibling crate exposing a plain C-ABI
wasm export — small, but real, and part of the spike.

**Parser correctness is silent when wrong.** A subtly wrong grid makes
`GetOutput` misread agent state; sessions then behave strangely with no crash and
no log. This is why Gate 1 is a differential harness against tmux rather than a
unit test suite — the oracle has to be the thing being replaced, while it is
still there to ask.

**Memory per session.** A `wazero` instance plus a grid, per host process, times
17+ concurrent sessions. `active-memory` covers it; the mitigation if it bites is
a shared parser in the daemon rather than one per host, at the cost of the
"screen exists with no client attached" property.

**Loss of tmux's maturity.** Decades of edge cases in resize-during-output, wide
characters, reflow. Partially mitigated: `vt-core` already handles these for the
renderer and is pinned by the alt/redraw conformance vectors. (Note the fuzz
harness at `packages/terminal/fuzz` covers the OSC marks decoder, not `vt-core`
— extending it to fuzz `vt-core::feed` is cheap and worth doing during Gate 1.)

**Detached host dies on Unix the moment it logs after the daemon exits.** The
host keeps writing diagnostics to stderr after startup, and the daemon holds the
other end of that pipe. Once the daemon exits, the next stderr write gets EPIPE,
and the Go runtime kills a process on EPIPE to fd 1/2. Windows has no SIGPIPE,
which is why conpty never hit this. The host must re-point stdout/stderr at a
log file under the session's data dir (or `/dev/null`) right after printing
`READY`, or `Setsid` durability is a fiction on the platforms that matter most.

**CI needs a Rust toolchain for the Go release builds.** Embedding
`vt_host.wasm` means `packages/build-binaries.sh` and the four release workflows
must install `rustup` + the `wasm32-unknown-unknown` target before the Go build.
The single-machine cross-compile story survives — wasm is
platform-independent, one artifact serves all four binaries — but the workflow
files change and that work is part of the plan, not a surprise.

## Deliberate deferrals

Pre-release, no users, sessions disposable — these are decisions, not oversights:

- **No auth on the loopback socket.** Any local process can connect to a host
  and inject input (`host_main.go` says so itself). A per-session token in the
  registry file is the known upgrade; deferred until the product has users whose
  local machines are not their own.
- **No reboot hygiene.** After a reboot, `ptyregistry` entries point at dead
  PIDs and sockets; recovery just fails and the session is respawned fresh.
  Stale-entry GC can come later.
- **Nobody answers terminal capability queries with no client attached.** tmux
  was itself the emulator on the agent's PTY, so it always answered XTVERSION
  (`CSI > q`) and Primary DA (`CSI c`). With tmux gone the emulator is the
  renderer: xterm.js answers those on the alternate-screen surface, but only
  while a client is attached, and `vt-core` does not answer at all. A TUI that
  blocks on a DA reply in a detached session would therefore wait. Deferred on
  evidence rather than assumption: `conpty` has shipped on Windows with exactly
  this behaviour and no report has traced to it. The fix, if it ever bites, is
  cheap and stays off the hot path — the passive parser already sees the query,
  so it can queue a reply for the host to write to the PTY's input side.

## Rollout

1. **Spike the wasm parser throughput.** Decide WASM vs Go emulator on numbers.
   Everything downstream assumes this answer.
2. Rename `conpty` → `ptyhost`; add the Unix `ptyConn` via `creack/pty`.
3. **Rebuild the read loop** — greedy drain, bounded processing, load-only
   coalescing. This is the performance half of the fix and it is its own step.
4. Add the parser (fed after broadcast, resized with the PTY) and switch
   `GetOutput` to rendered output. Gate 1 on vectors.
5. Close the capability gaps: styled output, capture, respawn, sizing policy.
6. `opr attach`.
7. Add the `scroll-latency` scenario; run both gates against both runtimes.
8. Flip `runtimeselect.New` to return `ptyhost` on all platforms.
9. Delete the tmux adapter, its tests, and the tmux dependency from docs and
   packaging. Verify no `tmux` references remain outside history.

Steps 2–6 are independently landable behind `runtimeselect`, which keeps the tree
green throughout and makes the cutover a one-line change that can be reverted.

## Open questions

- Does the daemon need the parser for sessions with no client attached, or only
  on demand? Always-on preserves tmux semantics exactly; on-demand (replay the
  ring through a fresh parser per query) trades query latency for steady-state
  cost. The spike's numbers decide, with the bias toward always-on: activity
  detection and delivery-readiness poll continuously, and making every poll pay
  a replay is the worse UX unless memory forces it.
- Should the scrollback ring stay raw, or become a rendered snapshot? Raw is
  correct for attach replay (the renderer wants bytes). A rendered snapshot
  might serve reconnect better. Defer until the existing `reconnect` scenario is
  measured against both runtimes.
