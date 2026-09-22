# Remote typing latency — what the wait is actually made of

**Date:** 2026-09-22
**Measured by:** an Operator session on the user's machine, against a real daemon
**Why:** Plan F (Part 6 of
[`2026-09-19-agent-tui-experience-design.md`](2026-09-19-agent-tui-experience-design.md))
proposes predictive local echo. Before building it, the question the survey
itself left open had to be answered with numbers: in the user's real case —
typing on the phone and having it reach the Claude Code TUI — how much of the
felt wait is the network, and how much is Claude thinking? The survey says so
explicitly: "the typical RTT: not known — measure"
([`2026-09-19-terminal-reference-survey.md`](2026-09-19-terminal-reference-survey.md) §4.3,
"Ours today").

**Answer, in one line:** the network is ~107 ms per keystroke over the public
tunnel and ~7 ms locally, while Claude's own turn is 1.07–1.57 s (median 1.24 s) for the most
trivial prompt that can be written. Network is **~8 % of the floor** (~15 % at p95) of a
send→answer wait and less than that for any real prompt. Predictive echo
cannot touch the part the user waits on.

---

## 1. What was measured, and where the clock ran

Three legs, all driven from this machine through the daemon's own mux
WebSocket — automation cannot click the Tauri window, so the standing approach
in this repo is to drive the daemon API and `/mux` directly (memory
`verify-operator-desktop-through-daemon-api-and-mux`).

| Leg | Transport | What it stands for |
|---|---|---|
| **loopback** | `ws://127.0.0.1:3007/mux` | the desktop app against its own local daemon |
| **LAN bridge** | `ws://192.168.1.2:54889/mux` + `Authorization: Bearer` | the phone on the same Wi-Fi, through the Connect Mobile listener |
| **public tunnel** | `wss://<name>.trycloudflare.com/mux` + bearer | the phone off-LAN, through the daemon's tunnel provider |

The clock is `performance.now()` in the measuring client, started at the
instant the keystroke is handed to `WebSocket.send` and stopped when the frame
carrying the answer arrives. Both ends of every interval are in the same
process, so there is no clock skew in any number here.

Two stop conditions are recorded per keystroke, which is the distinction the
task asked for:

- **first byte** — the first `{ch:"terminal", type:"data"}` frame of any kind
  after the send. This is "the bytes echoing it come back": network + daemon +
  pty + Claude Code's reaction.
- **visible** — the first frame whose payload actually contains the typed
  character. This is "the TUI's prompt shows it".

**These are the same frame in most samples** (loopback 21/24, LAN 17/24,
tunnel 17/24; median extra 0.0 ms in all three). Claude Code has no separate
terminal echo: the prompt repaint *is* the echo. When they differ, the glyph
lands in a follow-up frame within about 35 ms.

### Rig

- Isolated daemon: `go run ./cmd/opr daemon` with `OPERATOR_PORT=3007`, its own
  `OPERATOR_DATA_DIR`, launched with every `CLAUDE*` variable stripped
  (memory `scrub-claude-env-before-running-operator-dev`; verified in the
  daemon log). The user's other daemons on `:3001`/`:3002` were not touched.
- Session: `repo-17`, `harness: claude-code`, `workspaceMode: in_place`, grid
  120×40, against a throwaway git repo in the session scratchpad. Claude Code
  v2.1.273, Sonnet 5 with medium effort, Claude Max.
- Script: [`scripts/measure-remote-typing-latency.mjs`](../../../scripts/measure-remote-typing-latency.mjs),
  committed with this document. Zero dependencies on the loopback leg (Node 22's
  global `WebSocket`); the authenticated legs use `ws` from `frontend/node_modules`
  because the global `WebSocket` cannot set an `Authorization` header, which is
  the only way the LAN listener authenticates
  (`backend/internal/httpd/auth.go:123-129` `bearerToken`, `:158-168`
  `connectionToken` — there is no `?token=` query fallback).

### Instrumentation already in the tree, and why it was not enough

- `OPERATOR_PTY_RECORD` (`backend/internal/adapters/runtime/ptyhost/record.go:10`,
  `openRecorder` `:27`, `write` `:42`) records the pty's raw output bytes and a
  `[{offset, cols, rows}]` sidecar. It carries **no timestamps** (`recorder`
  has `written int64` and no clock field), so it can reproduce a stream but
  cannot time one. It is the fixture recorder, not a latency probe.
- `packages/terminal/bench/agent-session/run.mjs` and `session-api.test.mjs`
  drive the renderer harness over a Vite page against recorded fixtures, not a
  live daemon; `session-api.test.mjs` only asserts that `main.ts` exports the
  Plan B probe names. Neither opens a socket to a daemon.

So a new script was needed. It lives in `scripts/` rather than
`packages/terminal/bench/` because it talks to Operator's daemon, its mux
protocol and its mobile bridge — `packages/terminal` stays product-independent
(`TERMINAL.md` §3.1) and the `bench/` exemption is narrow.

---

## 2. Per-keystroke echo (send → the character is on screen)

24 samples per leg. One printable character sent per sample, with the pane
quiet for 1.2 s before and after, and a backspace between samples.

| Leg | n | first byte median | first byte p95 | **visible median** | **visible p95** | visible max |
|---|---|---|---|---|---|---|
| loopback | 24 | 7.3 ms | 14.4 ms | **7.7 ms** | **27.7 ms** | 29.4 ms |
| LAN bridge | 24 | 4.7 ms | 8.5 ms | **6.3 ms** | **23.6 ms** | 24.8 ms |
| public tunnel | 24 | 107.4 ms | 234.2 ms | **114.9 ms** | **253.3 ms** | 336.5 ms |

Raw samples: Appendix A (regenerate with the commands in §6).

The LAN bridge being *faster* than loopback is not a paradox and not noise in
the network: both stay inside this host's stack, and the two runs differ mostly
in how busy Claude Code's Ink loop was at the time. Read them as one number:
**the whole local pipeline — mux socket, daemon, pty-host, pty, Claude Code's
repaint, and back — costs 5–8 ms at the median and under 30 ms at p95.**

The LAN row is **not** a measurement of a phone on Wi-Fi. Traffic from this
machine to its own LAN address never reaches the air. A real phone on the same
Wi-Fi would add that link's RTT (typically single-digit to low-tens of ms) on
top of the 5–8 ms. That number is **not known** here — measuring it needs the
phone.

### Where the tunnel's 107 ms goes

| Probe | Value |
|---|---|
| TCP connect to the Cloudflare edge | 117 ms |
| TLS to first byte (`time_appconnect`) | 221 ms |
| HTTP round trip on a warm connection (`/api/v1/projects`, ×6) | 119, 133, 120, 134, 135 ms |
| WebSocket keystroke echo, median | 107 ms |

A warm HTTP round trip through the tunnel and a keystroke echo through the
tunnel cost the same. Subtracting the local pipeline's 5–8 ms leaves ~100 ms,
and one TCP handshake to the edge is 117 ms. **Essentially all of the remote
per-keystroke cost is network RTT to the Cloudflare edge and back** — the
daemon, pty-host and Claude Code contribute the same few milliseconds they do
locally.

### Tailscale: not measured, and why

Tailscale is **not installed on this machine** (`which tailscale` → not found;
no `/Applications/Tailscale.app`). The daemon's own remote path today is the
tunnel provider behind Connect Mobile, and its ngrok leg refused to start
because the user's reserved endpoint was already online from another running
daemon (`ERR_NGROK_334`, surfaced as `fallbackReason`); its cloudflared
fallback then reported `no tunnel provider available`. The tunnel leg above was
therefore taken through a cloudflared quick tunnel started by hand against the
same authenticated Connect Mobile listener — the same provider the daemon falls
back to since 2026-09-20 (memory
`ngrok-needs-plain-http-isp-quota-page-breaks-it`), over the same code path the
phone uses.

The Tailscale figure itself is **not known**. What can be said is that
Tailscale between two devices on the same Wi-Fi is direct after NAT traversal
and so lands near the LAN number, while a relayed (DERP) connection or a
different network lands near or above the tunnel's ~107 ms. Either way the
conclusion in §4 does not move, because it does not turn on the size of the
network term.

---

## 3. Claude's own turn (Enter → the answer is on screen)

The prompt was typed, the pane allowed to go quiet, and the clock started at
the `\r`. Two stops: the first byte back (Claude Code clearing its input box —
a purely local repaint) and the frame containing the answer text. The answer
token is lowercase and the prompt's is uppercase, so the echo of the user's own
message cannot be mistaken for the answer.

The prompt is the cheapest one that can be written — *"Reply with the single
word MANGOES<i> in lowercase and nothing else"*. This is a **floor** on Claude's
contribution, not a typical value.

| Stop condition | n | min | median | p95 | max |
|---|---|---|---|---|---|
| Enter → first byte back (Claude Code clears its box) | 8 | 10.9 ms | 21.2 ms | 32.9 ms | 35.7 ms |
| **Enter → the answer is on screen** | 8 | **1071.8 ms** | **1240.3 ms** | **1494.0 ms** | **1567.0 ms** |

Every one of the eight rounds submitted and answered. Claude Code's own
per-turn labels in the transcript agree with the measurement — "Crunched for
1s", "Cooked for 1s", "Sautéed for 1s" beside each answer.

The 21 ms first byte is a local repaint, not a response: pressing Enter makes
Claude Code redraw its input box, which costs about three times a single
keystroke's 7 ms because it repaints more of the frame. It is not Claude
answering, which is the point of measuring the two separately — **a "first byte
after Enter" metric would have reported 21 ms and been wrong by a factor of 59.**

Raw samples: Appendix A.

### Why this is a floor and not a typical value

The prompt is one sentence and the answer is one word: no tool call, no file
read, no thinking block. Any prompt a user actually sends — read this, change
that, run the tests — takes Claude tens of seconds. **1.24 s is the smallest
number Claude's turn can be, and it is already ten times the network.**

---

## 4. Splitting the felt wait

For the case the user cares about — typing in the mobile composer and pressing
send — the composer is already local echo: the text sits in a Flutter field and
goes as one payload on send (`terminalPayload`,
`packages/mobile/lib/feature/terminal/logic/send_route.dart:20-21`, pushed by
`_writeToPty` → `MuxClient.sendInput`,
`packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:354-356`).
Nothing is waited on while typing. What is waited on begins at send:

| Component | Off-LAN (tunnel) | Local / desktop |
|---|---|---|
| send → daemon → pty (half of the echo RTT) | ~54 ms | ~4 ms |
| Claude's turn, **trivial prompt** (median) | 1240 ms | 1240 ms |
| first answer bytes → phone (the other half) | ~54 ms | ~4 ms |
| **network share of the total** | **~8 % (median), ~15 % (p95)** | **<1 %** |

For a real prompt — one that reads files, runs a tool, writes code — Claude's
turn is tens of seconds and the network share falls below 1 % even off-LAN.
**The felt wait after send is Claude thinking. It is not the terminal, not the
mux protocol, and not the renderer.**

Per-keystroke latency is real but lives somewhere else: the raw terminal pane
and the key row, where every keypress is forwarded individually
(`terminal.onOutput = (data) => _mux.sendInput(...)`, `terminal_cubit.dart:99`;
`sendKey`, `:281-283`). There a remote user pays the full ~107 ms per character
and it is felt. That is the only place on mobile where predictive echo would
change anything — and the renderer that could draw a prediction is not the one
the phone runs.

---

## 5. What follows for Plan F

1. **Predictive echo does not address the user's case.** It would shave a
   ~107 ms per-keystroke cost that the composer already avoids, on a path whose
   dominant term is 1.24 s and up.
2. **It cannot reach the phone at all as specified.** Part 6's echo is a
   renderer-only overlay in `packages/terminal/ts/renderer-dom`; the Flutter app
   draws with its own vendored `packages/mobile/packages/xterm` fork and never
   loads that renderer.
3. **The one configuration it would help is the desktop app against a remote
   daemon**, where the ~107 ms is paid per keystroke in the alt-screen path.
   Whether the user works that way is **not known** — it is not observable from
   this machine's configuration, and must be answered by the user, not assumed.
4. **Survey §4.2 is what would actually change the phone's experience** — one
   model of record on the server, rows pulled by `(stable row, generation)`,
   the `xterm` fork deleted, and the phone inheriting every affordance Plans D
   and E built. It also happens to be the only way predictive echo could ever
   reach the phone.

Plan F's shape follows from this and is written in
[`../plans/2026-09-22-agent-tui-plan-f-remote-typing.md`](../plans/2026-09-22-agent-tui-plan-f-remote-typing.md).

---

## 6. Reproducing this

All commands from `/Users/omaraly/development/AI/Operator`, with the daemon
started as in §1.

```bash
node /Users/omaraly/development/AI/Operator/scripts/measure-remote-typing-latency.mjs \
  --session repo-17 --mode dump
```

```bash
node /Users/omaraly/development/AI/Operator/scripts/measure-remote-typing-latency.mjs \
  --session repo-17 --mode echo --samples 24 --label loopback
```

```bash
node /Users/omaraly/development/AI/Operator/scripts/measure-remote-typing-latency.mjs \
  --session repo-17 --mode echo --samples 24 --label tunnel \
  --url wss://<name>.trycloudflare.com/mux --token <connect-mobile-password>
```

```bash
node /Users/omaraly/development/AI/Operator/scripts/measure-remote-typing-latency.mjs \
  --session repo-17 --mode claude --rounds 8 --settle 6000 \
  --marker PLUMS --expect plums
```

### Traps found while taking these numbers, for whoever repeats them

- **Two measuring clients on one session corrupt each other.** The first
  `--mode claude` run overlapped with an echo run; the echo run's letters and
  backspaces landed inside Claude Code's prompt box, three prompts stacked up
  as one multi-line message, and the `\r` inserted a newline instead of
  submitting. Run one client at a time; `--mode dump` is read-only and safe
  alongside.
- **Writing the prompt as one chunk makes Claude Code swallow the Enter — this
  is the trap that cost the most time.** After the session's first submit, a
  prompt written to the pty in a single mux frame and followed by `\r` had its
  `\r` inserted as a newline instead of submitting; prompts stacked up in the
  composer as one growing multi-line message and every round after the first
  timed out. Waiting longer does not fix it: a 12 s settle plus a quiet wait
  still lost 7 of 8 rounds. It is Claude Code's paste detection — a burst of
  characters arriving together is a paste, and a `\r` inside the paste window
  is a literal newline. **Typing the prompt one character at a time with a
  35 ms gap** (`--type-delay`, the script's default) fixed it completely:
  8 of 8 rounds submitted and answered. A round whose Enter is still swallowed
  shows up as `answerMs: null` and is excluded from the statistics rather than
  counted as a slow answer.
- **The tunnel leg needs a header, not a query parameter.** See §1.

---

## Appendix A. Raw samples

Every number the tables above are computed from, in the order taken,
milliseconds. Kept here because the JSON files live in a session scratchpad
that does not survive.

**Per-keystroke echo, 24 samples per leg (§2).**

```
loopback  first byte  2.1, 12.5, 11.6, 4.9, 5.5, 7.3, 7.1, 8.2, 14.8, 6.0, 10.2, 9.2, 10.0, 8.2, 15.5, 9.0, 8.1, 5.2, 7.3, 6.2, 6.5, 5.8, 3.9, 6.7
loopback  visible    19.4, 29.4, 29.2, 4.9, 5.5, 7.3, 7.1, 8.2, 14.8, 6.0, 10.2, 9.2, 10.0, 8.2, 15.5, 9.0, 8.1, 5.2, 7.3, 6.2, 6.5, 5.8, 3.9, 6.7

lan       first byte  3.1, 6.2, 6.1, 5.8, 4.7, 4.7, 3.1, 12.8, 8.7, 4.4, 4.5, 3.1, 5.2, 4.0, 4.4, 6.0, 7.9, 2.3, 6.6, 4.6, 7.1, 4.7, 2.5, 4.7
lan       visible    23.7, 23.3, 24.8, 23.0, 4.7, 4.7, 22.2, 12.8, 8.7, 4.4, 4.5, 3.1, 22.8, 4.0, 4.4, 6.0, 7.9, 21.3, 6.6, 4.6, 7.1, 4.7, 2.5, 4.7

tunnel    first byte  108.6, 106.6, 107.7, 110.1, 107.5, 116.9, 100.0, 98.9, 98.4, 102.6, 125.2, 126.6, 336.5, 114.4, 106.1, 252.5, 99.7, 130.2, 107.2, 128.2, 103.3, 102.7, 103.9, 94.0
tunnel    visible    118.9, 106.6, 117.5, 110.1, 107.5, 116.9, 100.0, 98.9, 98.4, 135.0, 125.2, 126.6, 336.5, 114.4, 106.1, 274.1, 99.7, 130.3, 116.1, 128.2, 103.3, 102.7, 103.9, 115.4
```

The tunnel's two outliers (336.5 ms and 252.5 ms) are what drives its p95;
21 of 24 samples sit between 94 and 131 ms.

**Claude's turn, 8 rounds, loopback (§3).**

```
enter -> first byte   21.1, 19.8, 13.5, 22.7, 21.3, 35.7, 27.7, 10.9
enter -> answer     1567.0, 1127.6, 1142.6, 1275.3, 1325.6, 1358.3, 1071.8, 1205.4
```

No round was excluded: all eight submitted and answered.
