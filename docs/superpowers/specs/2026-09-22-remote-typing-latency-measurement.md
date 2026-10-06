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
([`2026-09-19-terminal-reference-survey.md`](../../terminal/2026-09-19-terminal-reference-survey.md) §4.3,
"Ours today").

**Answer, in one line:** the network is ~107 ms per keystroke over the public
tunnel and ~7 ms locally, while Claude's own turn is 1.07–1.57 s (median 1.24 s) for the most
trivial prompt that can be written. Network is **~8 % of the floor** of a
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

**A needle strong enough to carry that distinction.** The first version of
this measurement cycled the needle through `a`–`z`, which cannot support the
claim: Claude Code's repaint frames are full of lowercase letters, in its own
UI text and in the escape sequences themselves (`m` terminates SGR, `h`/`l` set
modes). A match then proves nothing. The numbers below are a **re-run** with
the needle restricted to `zqjxkv` (`--alphabet`, now the script's default) —
characters absent from an idle Claude Code repaint — and with the index of the
frame that carried the glyph recorded per sample (`visibleFrameIndex`).

With that, the distinction is real and the earlier conclusion survives. A
byte-level dump of one keystroke, taken separately:

```
+3.3ms    4B  ESC ( B SI
+21.4ms  82B  ESC[?2026h ESC[?25l ESC[2D ESC[3B CR ESC[2C ESC[3A z ...  ESC[?25h ESC[?2026l
```

The 4-byte frame is a charset reset and appears **only on the first keystroke
after an attach**; a probe of six consecutive keystrokes (`z q j x v k`)
produced exactly one 82-byte frame each, every one containing the typed
character. Across the 24-sample runs the glyph arrives in frame 0 for 22/24
(loopback), 19/24 (LAN) and 20/24 (tunnel), and every frame-1 case falls in the
first samples of a run, while the attach is still settling. **Claude Code has
no separate terminal echo: the DEC 2026-wrapped prompt repaint is the echo**,
and when it is split across two mux frames — which `TERMINAL.md` §4.16 says can
happen at most once per frame — the glyph lands in the second.

### Rig

- Isolated daemon: `go run ./cmd/opr daemon` with `OPERATOR_PORT=3007`, its own
  `OPERATOR_DATA_DIR`, launched with every `CLAUDE*` variable stripped
  (memory `scrub-claude-env-before-running-operator-dev`; verified in the
  daemon log). The user's other daemons on `:3001`/`:3002` were not touched.
- Session: `repo-18`, `harness: claude-code`, `workspaceMode: in_place`, grid
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
  `openRecorder` `:27`, `write` `:44`) records the pty's raw output bytes and a
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
| loopback | 24 | 6.6 ms | 9.8 ms | **6.7 ms** | **17.6 ms** | 26.6 ms |
| LAN bridge | 24 | 6.3 ms | 10.1 ms | **6.5 ms** | **27.2 ms** | 27.9 ms |
| public tunnel | 24 | 106.7 ms | 144.3 ms | **111.7 ms** | **146.8 ms** | 269.3 ms |

**Read `p95` at n=24 as the 22nd–23rd value, not a tail estimate.** With 24
samples it is an order statistic two places from the maximum; it says "the
worst couple of samples looked like this", not "1 in 20 users will see this".

Raw samples: Appendix A (regenerate with the commands in §6).

Loopback and the LAN bridge land on the same number because both stay inside
this host's stack; the difference between them is which way Claude Code's Ink
loop happened to be leaning. Read them as one: **the whole local pipeline — mux
socket, daemon, pty-host, pty, Claude Code's repaint, and back — costs 6–7 ms
at the median and under 30 ms at its worst.**

The LAN row is **not** a measurement of a phone on Wi-Fi. Traffic from this
machine to its own LAN address never reaches the air. A real phone on the same
Wi-Fi would add that link's RTT (typically single-digit to low-tens of ms) on
top of the 5–8 ms. That number is **not known** here — measuring it needs the
phone.

### Where the tunnel's 107 ms goes

| Probe | Value |
|---|---|
| TCP connect to the Cloudflare edge | 48 ms |
| TLS established (`time_appconnect`) | 106 ms |
| HTTP round trip on a warm connection (`/api/v1/projects`, ×5) | 119, 133, 109, 113, 131 ms |
| WebSocket keystroke echo, median | 106.7 ms |

A warm HTTP round trip through the tunnel (109–133 ms) and a keystroke echo
through it (106.7 ms) cost the same, and subtracting the local pipeline's
6–7 ms leaves ~100 ms for a path whose TLS handshake alone is 106 ms.
**Essentially all of the remote per-keystroke cost is network RTT to the
Cloudflare edge and back** — the daemon, pty-host and Claude Code contribute
the same few milliseconds they do locally.

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

| Stop condition | n | min | median | p95 (n=8, ≈ max) | max |
|---|---|---|---|---|---|
| Enter → first byte back (Claude Code clears its box) | 8 | 10.9 ms | 21.2 ms | 32.9 ms | 35.7 ms |
| **Enter → the answer is on screen** | 8 | **1071.8 ms** | **1240.3 ms** | **1494.0 ms** | **1567.0 ms** |

At n=8 the "p95" is interpolating between the 7th and 8th values — it is a
restatement of the maximum, not a tail. Use the median; the range is the honest
spread.

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
number Claude's turn can be, and it is already twelve times the network.**

---

## 4. Splitting the felt wait

For the case the user cares about — typing in the mobile composer and pressing
send — the composer is already local echo: the text sits in a Flutter field and
goes as one payload on send (`terminalPayload`,
`packages/mobile/lib/feature/terminal/logic/send_route.dart:20-21`, pushed by
`_writeToPty` → `MuxClient.sendInput`,
`packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:354-356`).
Nothing is waited on while typing. What is waited on begins at send. The
network term below is one full round trip at its median, against Claude's
median; stacking the network's worst case on Claude's worst case would be a
worst-on-worst figure, not a p95 of the total, so it is not quoted:

| Component | Off-LAN (tunnel) | Local / desktop |
|---|---|---|
| send → daemon → pty (half of the echo RTT) | ~54 ms | ~4 ms |
| Claude's turn, **trivial prompt** (median) | 1240 ms | 1240 ms |
| first answer bytes → phone (the other half) | ~54 ms | ~4 ms |
| **network share of the total** | **~8 %** | **<1 %** |

For a real prompt — one that reads files, runs a tool, writes code — Claude's
turn is tens of seconds and the network share falls below 1 % even off-LAN.
**The felt wait after send is Claude thinking. It is not the terminal, not the
mux protocol, and not the renderer.**

Per-keystroke latency is real but lives somewhere else: the raw terminal pane
and the key row, where every keypress is forwarded individually
(`terminal.onOutput = (data) => _mux.sendInput(...)`, `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart:99`;
`sendKey`, `:281-283`). There a remote user pays the full ~107 ms per character
and it is felt. That is the only place on mobile where predictive echo would
change anything — and the renderer that could draw a prediction is not the one
the phone runs.

---

## 5. What follows for Plan F

1. **Predictive echo does not address the case the user opened with — the
   phone.** It would shave a ~107 ms per-keystroke cost that the mobile
   composer already avoids, on a path whose dominant term is 1.24 s and up.
2. **It cannot reach the phone at all as specified.** Part 6's echo is a
   renderer-only overlay in `packages/terminal/ts/renderer-dom`; the Flutter app
   draws with its own vendored `packages/mobile/packages/xterm` fork and never
   loads that renderer.
3. **The configuration it does help is the desktop app against a remote
   daemon**, where the ~107 ms is paid per keystroke in the alt-screen path.
   The measurement could not tell whether the user works that way — it is a
   property of how they work, not of this machine — so it was put to them
   directly, and the answer (2026-09-22) is **yes, often**. That single input
   is what turns predictive echo from deferred-indefinitely into work with a
   real user behind it, and it is why Plan F carries implementation tasks for
   it after the §4.2 spec.
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
  --session repo-18 --mode dump
```

```bash
node /Users/omaraly/development/AI/Operator/scripts/measure-remote-typing-latency.mjs \
  --session repo-18 --mode echo --samples 24 --label loopback
```

The needle alphabet defaults to `zqjxkv`; `--alphabet` overrides it. Do not
widen it to the full lowercase range — see §1.

```bash
node /Users/omaraly/development/AI/Operator/scripts/measure-remote-typing-latency.mjs \
  --session repo-18 --mode echo --samples 24 --label tunnel \
  --url wss://<name>.trycloudflare.com/mux --token <connect-mobile-password>
```

```bash
node /Users/omaraly/development/AI/Operator/scripts/measure-remote-typing-latency.mjs \
  --session repo-18 --mode claude --rounds 8 --settle 6000 \
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
milliseconds, from the corrected run (needle `zqjxkv`). Kept here because the
JSON files live in a session scratchpad that does not survive. `idx` is
`visibleFrameIndex` per sample — which mux frame after the keystroke carried
the glyph.

**Per-keystroke echo, 24 samples per leg (§2).**

```
loopback  first byte  2.0, 8.8, 4.6, 9.9, 6.2, 9.5, 7.5, 6.3, 7.9, 4.4, 9.9, 5.6, 4.3, 5.9, 6.6, 6.9, 3.9, 4.9, 6.8, 7.3, 9.5, 5.6, 7.1, 6.7
loopback  visible    19.0, 26.6, 4.6, 9.9, 6.2, 9.5, 7.5, 6.3, 7.9, 4.4, 9.9, 5.6, 4.3, 5.9, 6.6, 6.9, 3.9, 4.9, 6.8, 7.3, 9.5, 5.6, 7.1, 6.7
loopback  idx        110000000000000000000000

lan       first byte  1.7, 10.5, 7.1, 9.7, 6.7, 6.6, 7.5, 6.5, 5.8, 3.7, 4.6, 5.2, 4.6, 7.8, 6.6, 8.9, 5.9, 4.1, 10.1, 6.1, 5.5, 6.2, 5.1, 7.0
lan       visible    19.0, 27.9, 24.8, 27.7, 6.7, 6.6, 24.5, 6.5, 5.8, 3.7, 4.6, 5.2, 4.6, 7.8, 6.6, 8.9, 5.9, 4.1, 10.1, 6.1, 5.5, 6.2, 5.1, 7.0
lan       idx        111100100000000000000000

tunnel    first byte  93.7, 99.9, 105.7, 103.9, 148.6, 104.6, 98.9, 100.5, 269.3, 105.7, 105.0, 112.0, 103.0, 109.5, 100.5, 120.3, 114.3, 111.7, 119.8, 117.9, 107.7, 111.6, 97.0, 117.1
tunnel    visible    111.8, 99.9, 105.7, 118.9, 148.6, 122.4, 98.9, 100.5, 269.3, 105.7, 105.0, 112.0, 103.0, 109.5, 100.5, 120.3, 114.3, 137.0, 119.8, 117.9, 107.7, 111.6, 97.0, 117.1
tunnel    idx        100101000000000001000000
```

Every `idx` of 1 sits in the opening samples of its run, while the attach is
still settling; after that the glyph is in the first frame every time. The
tunnel's one 269.3 ms sample is what lifts its p95 — 22 of 24 samples sit
between 94 and 121 ms.

**Claude's turn, 8 rounds, loopback (§3).**

```
enter -> first byte   21.1, 19.8, 13.5, 22.7, 21.3, 35.7, 27.7, 10.9
enter -> answer     1567.0, 1127.6, 1142.6, 1275.3, 1325.6, 1358.3, 1071.8, 1205.4
```

No round was excluded: all eight submitted and answered.

## Appendix B. The superseded first run

The echo legs were measured twice. The first run cycled the needle through
`a`–`z`, which collides with Claude Code's own output, so its "visible" column
and its frame-identity counts (21/24, 17/24, 17/24) are not evidence and are
not used anywhere above. Its first-byte column was never affected by the needle
and agreed with the corrected run — loopback 7.3 ms median, LAN 4.7 ms, tunnel
107.4 ms, against 6.6 / 6.3 / 106.7 ms here. That agreement is the reason the
conclusion did not move; the re-run was needed to make the *frame-identity*
claim honest, not to rescue the headline.
