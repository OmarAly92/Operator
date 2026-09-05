# The queued-send spike

**Question.** If a client sends a message to a session while its agent is mid-turn
(active) or mid-render, does the harness's own composer queue it intact so it submits
when the turn ends, or is it lost/garbled? Does the daemon's send path currently gate
on "active" at all, and should it?

**Environment.** Live daemon at `http://127.0.0.1:3002`, dev data dir `~/.operator/dev/data`.
Three sessions were available: `scratch-1` (claude-code, idle, off-limits — real unsent
draft), `scratch-2` (claude-code, `activity.state: blocked` / `status: needs_input`),
`scratch-3` (codex, idle, safe to use). No `opr` CLI was on PATH; all interaction was
via `curl` against the HTTP API and a throwaway Go program
(`backend/tmp_panecap/main.go`, deleted before commit — see step-by-step evidence
below) that called `ptyhost.Runtime.GetOutput` / `SendInput` directly, the same
technique Task 4 used for pane fixtures.

## Finding 0: the ordinary `/send` route does not currently gate on "active" for any harness

Before running the harness probes, I read `backend/internal/sessionguard/guard.go`.
The route the daemon actually uses for `POST /api/v1/sessions/{id}/send` is
`Manager.send` → `m.messenger.DeliverWithPostWrite`, which is `Guard.Deliver`'s policy:

```go
// guard.go:147
func (g *Guard) Deliver(ctx context.Context, id domain.SessionID, msg string) (Outcome, error) {
	return g.send(ctx, id, msg, func(rec domain.SessionRecord) (Outcome, bool) {
		return SuppressedAwaitingUser, rec.Activity.State == domain.ActivityBlocked
	})
}
```

This refuses **only** when `Activity.State == ActivityBlocked` (a pending permission/
decision dialog). It does **not** refuse when `Activity.State == ActivityActive`. This
was confirmed empirically below: sends to an actively-working Codex session returned
HTTP 200, not 409, for every harness tested. The stricter "active" gate
(`SuppressedBusy` unless `steersActiveTurn(harness)`) exists only in
`Guard.CoordinationUnderMutation` / `Guard.NudgeCoordination`, which are used for
**Operator-initiated** coordination writes during agent-switch mutations — a different
code path from ordinary client-originated `/send`, and out of this task's scope (the
task is about a client sending a message, not the daemon's own coordination nudges).

**Consequence for Task 11's premise:** there is no per-harness "idle gate on send" in
the client-facing path to relax. The daemon already lets a client's message through to
the pty while the agent is active, for every harness; whether that message survives
depends entirely on the harness's own composer, which is exactly what the rest of this
spike measures.

## Finding 1: Codex — single message sent while active

**Setup.** `scratch-3` given a task to keep it busy:

```bash
curl -s -X POST http://127.0.0.1:3002/api/v1/sessions/scratch-3/send \
  -H 'Content-Type: application/json' -d '{"message":"probe-auth-check"}'
# -> {"ok":true,...}  HTTP 200
```

Pane confirmed active:

```
› probe-auth-check


◦ Working (4s • esc to interrupt)
```

**Probe.** Sent a second message via the same route while active:

```bash
curl -s -w '\nHTTP_STATUS:%{http_code}\n' -X POST \
  http://127.0.0.1:3002/api/v1/sessions/scratch-3/send \
  -H 'Content-Type: application/json' -d '{"message":"queued message one codex"}'
```

Result: `{"ok":true,"sessionId":"scratch-3","message":"queued message one codex"}` —
**HTTP 200, not refused.**

Pane after the first turn completed:

```
• Ran probe-auth-check
  └ zsh:1: command not found: probe-auth-check

⚠ Heads up, you have less than 25% of your 5h limit left. Run /status
  for a breakdown.

────────────────────────────────────────────────────────────────────────

• probe-auth-check was not found as a shell command.

────────────────────────────────────────────────────────────────────────


› queued message one codex


• Received: queued message one codex.
```

**Answers to the four questions:**
- Does the text appear in the composer? Yes, verbatim, as a new `›` line.
- Does it submit when the turn ends? Yes — it appears as a submitted user turn
  immediately after the first turn's completion banner.
- Does a `prompt_submit`-equivalent effect fire? Yes — the agent produced a distinct
  reply ("Received: queued message one codex.") addressed to it specifically.
- Transcript evidence: confirmed in
  `~/.codex/sessions/2026/09/05/rollout-2026-09-05T05-58-39-...jsonl` as a
  `response_item`/`message`/`role: user` entry.

**Verdict: queue holds intact for a single message sent during an active turn.**

## Finding 2: Codex — adversarial case, five sequential HTTP sends during mid-render

**Setup.** Gave `scratch-3` a longer task with visible scrolling tool output:

```bash
curl -s -X POST http://127.0.0.1:3002/api/v1/sessions/scratch-3/send \
  -H 'Content-Type: application/json' \
  -d '{"message":"Run: for i in 1 2 3 4 5 6 7 8; do echo tick-$i; sleep 2; done"}'
```

While `Working (12s...) · 1 background terminal running`, fired 5 sends in a row via
the same serialized HTTP route:

```bash
for i in 1 2 3 4 5; do
  curl -s -w " [HTTP:%{http_code}]\n" -X POST \
    http://127.0.0.1:3002/api/v1/sessions/scratch-3/send \
    -H 'Content-Type: application/json' -d "{\"message\":\"adversarial-codex-$i\"}"
done
```

All 5 returned `HTTP:200`. Pane captured immediately after (mid-render, tool still
running):

```
• Working (12s • esc to interrupt) · 1 background terminal running · /p…

• Messages to be submitted after next tool call (press esc to interrupt
  and send immediately)
  ↳ adversarial-codex-1
  ↳ adversarial-codex-2
  ↳ adversarial-codex-3
  ↳ adversarial-codex-4
  ↳ adversarial-codex-5
```

This is Codex's own harness UI explicitly confirming a queue: all 5 messages held
intact, in original order, none garbled or interleaved.

Pane after the tool call completed:

```
› adversarial-codex-1



› adversarial-codex-2



› adversarial-codex-3



› adversarial-codex-4



› adversarial-codex-5


• Ran for i in 1 2 3 4 5 6 7 8; do echo tick-$i; sleep 2; done
  └ tick-2
    tick-3
    … +3 lines (ctrl + t to view transcript)
    tick-7
    tick-8

────────────────────────────────────────────────────────────────────────

• Command completed successfully through tick-8.
```

All 5 texts landed intact and in order — no loss, no garbling, no interleaving at the
byte/text level. However, cross-checking the native transcript
(`~/.codex/sessions/2026/09/05/rollout-2026-09-05T05-58-39-...jsonl`) shows something
worth flagging: all 5 were appended as separate `UserMessage` response items **inside
the same turn** (`turn_id: 01a07027-52f8-7f91-9725-bd04a725576b`) as the original
command, and the model's single reply after finishing the tool call
("Command completed successfully through `tick-8`.") did **not** individually address
any of the 5 queued messages — it only reported on the original shell command's
outcome. Contrast this with Finding 1, where a single queued message got its own
distinct reply. So: **delivery and ordering are reliable even under a 5-message burst,
but the model's per-message acknowledgment is not** — Codex flushes a burst of queued
input into the model's context as one batch, and the model may choose to respond to
only the most salient item (here, the original task) rather than each queued line.
This is a model-behavior nuance, not evidence of the harness dropping or corrupting
text.

## Finding 3: Codex — true adversarial case, concurrent unserialized pty writes

The sequential-HTTP-send tests above go through the daemon's own write lease
(`Guard.sendThen` → `lease.AcquireSessionInput`), which serializes writes even when the
gate itself does not block on "active". To test whether the harness's composer is safe
against genuinely concurrent, unserialized writes (bypassing the daemon's lease
entirely, as a raw `SendInput` call to `ptyhost.Runtime` would), I fired 5 concurrent
raw pty writes at once while `scratch-3` was mid-render:

```bash
for i in 1 2 3 4 5; do
  ./tmp_panecap send scratch-3 "raw-pty-concurrent-$i" &   # each appends \r
done
wait
```

Pane immediately after:

```
› raw-pty-concurrent-3
  raw-pty-concurrent-2
  raw-pty-concurrent-5
  raw-pty-concurrent-4
```

**Message 1 is missing entirely, and the remaining four are out of order** (3, 2, 5,
4). After the turn completed, the composer still held this same scrambled, unsubmitted
draft — it never got cleaned up or resubmitted correctly:

```
› raw-pty-concurrent-3
  raw-pty-concurrent-2
  raw-pty-concurrent-5
  raw-pty-concurrent-4
```

**This is genuine data loss and reordering.** It shows that Codex's composer (like
any pty-backed TUI) is not safe against concurrent unserialized writers — the
daemon's own write lease (`AcquireSessionInput`, serializing one write at a time) is
what makes the sequential-HTTP-send results in Finding 2 reliable. This is important
evidence **against** ever bypassing the daemon's lease for a "faster" send path, and
confirms the lease must stay in place regardless of what a per-harness policy decides
about the "active" activity-state check.

(The composer draft left by this test was cleaned up with a raw `Ctrl+U` — `\x15` —
sent directly to the pty, confirmed by a follow-up capture showing the composer back
at its idle placeholder. `scratch-3` was left idle, matching the state it was found
in.)

## Finding 4: Claude Code — could not be safely tested live

Per the task's explicit instructions, `scratch-1` was never touched. `scratch-2` was
the only other claude-code session available. Before sending anything to it, I read
its pane (`GetOutput`, 60 lines):

```
❯ Use the AskUserQuestion tool to ask me which colour I prefer, options
  red green blue

⏺ User declined to answer questions
  ⎿  · Which colour do you prefer? (Red / Green / Blue)

✻ Baked for 3s · done 5:53 AM

────────────────────────────────────────────────────────────────────────
❯ 
────────────────────────────────────────────────────────────────────────
  ⏸ manual mode on · ? for shortcuts · ← for agents
```

The pane shows an empty composer with no visible pending dialog box — it looks idle.
To confirm before touching it, I attempted a real send through the ordinary HTTP route
(the same route Findings 1-3 already prove is not gated on "active"):

```bash
curl -s -w '\nHTTP_STATUS:%{http_code}\n' -X POST \
  http://127.0.0.1:3002/api/v1/sessions/scratch-2/send \
  -H 'Content-Type: application/json' \
  -d '{"message":"Run the bash command: sleep 18 && echo done-sleep-claude"}'
```

Result:

```json
{"error":"conflict","code":"SESSION_AWAITING_DECISION","message":"Session is paused on a permission decision; answer it in the session terminal first","requestId":"..."}
```

`HTTP_STATUS:409`. The daemon's own activity tracking considers this session
genuinely `ActivityBlocked`, even though the rendered pane shows no obvious dialog box
— i.e. whatever state "manual mode on" left the session in is exactly the ambiguous,
ungessable case the task's live-environment notes warned about. Per the explicit
instruction ("if you're unsure, just use `scratch-3` for your live tests instead and
note in your findings that `scratch-2` was left alone due to its ambiguous blocked
state"), I did **not** force it — no Escape, no raw pty write, no further probing. I
left `scratch-2` exactly as found (still `blocked`/`needs_input`, unchanged) and
performed **no live Claude Code probe**.

**Claude Code could not be safely or fully tested in this environment.** This spike
makes no claim about Claude Code's composer-queueing behavior — the finding is
"untested," not "unsafe" or "safe." A re-run needs either a genuinely idle
claude-code session, or an explicit human decision to force-clear `scratch-2`'s
pending state first.

## Recommendation per harness

- **Codex:** No code change needed. The ordinary `/send` route (`Guard.Deliver`)
  already does not refuse on `ActivityActive` for any harness — it only refuses on
  `ActivityBlocked`. Codex's own composer reliably queues a message sent during an
  active/mid-render turn, delivers it intact, and submits it once the turn ends
  (confirmed for one message with an individual model reply, and for a burst of five
  with intact ordering but batched model attention). Since there is no active-only
  gate on the client-facing send path to loosen, `harnessNudgeSafe`/`steersActiveTurn`
  do not need a new Codex-specific predicate for this purpose — that machinery is for
  Operator-initiated coordination writes during mutations, a separate concern from
  client sends. Do **not** build a "fast path" that bypasses the daemon's write lease
  (`AcquireSessionInput`) — Finding 3 shows concurrent unserialized writes lose and
  reorder text even in Codex's own composer; the lease's serialization, not the
  activity-state gate, is what makes queued sends reliable.
- **Claude Code:** Untested. `scratch-1` was off-limits and `scratch-2` was in a
  genuinely ambiguous blocked state (confirmed by the daemon itself via a real 409,
  not merely a stale label) that the task's own rules said not to force. No claim is
  made about whether Claude Code's composer queues intact during an active turn. No
  code change made for Claude Code. Recommend re-running this half of the spike when
  a safely-idle claude-code session is available.

## Code change

**None.** `backend/internal/session_manager/manager.go` and
`backend/internal/sessionguard/guard.go` are unchanged. Reasoning: for Codex, there is
no existing active-state gate on the client-facing send path to relax (Finding 0), so
"relaxing the gate" is not an available fix — the queueing behavior we wanted to
confirm already gets exercised by the current code, and evidence backs it. For Claude
Code, evidence is incomplete (Finding 4), and the task's own instructions are explicit
that incomplete evidence must not be guessed into a code change.
