# Mobile chat bugs

Audit of the `packages/mobile` chat lifecycle, 2026-09-03. Triggered by a
reported hang: the desktop renders an agent response while mobile sits on a
loading state forever.

The reported symptom is real, reproducible from the code, and **deterministic
rather than flaky**. It is caused by C1 below. Everything else is what the same
audit turned up in the surrounding lifecycle.

Severity is "what does the user lose", not "how hard is the fix":

- **Critical** — the timeline stops updating; the session appears hung.
- **High** — wrong data, wasted work, or a failure the user cannot see.
- **Medium** — correctness holes that need specific conditions to bite.

---

## The shape of the problem

One fact explains most of this list. **A mobile chat screen runs two independent
cubits, each holding its own SSE connection to the same `/api/v1/events`
stream:**

| | `ChatCubit` | `ConversationBlocksCubit` |
|---|---|---|
| Renders | chrome: composer, banners, settings, live-turn bar | **the timeline itself** |
| Cursor passed as `after` | persisted CDC seq (correct) | conversation `latestSequence` (**wrong space**) |
| Filters by `sessionId` | yes | no |
| Debounces refresh | 120 ms | no |
| Guards against out-of-order responses | `_refreshGeneration` | none |
| Reconnects when the stream dies | yes, capped backoff | **no — errors are swallowed** |
| Refreshed on app resume | yes | **no** |

The column that is wrong in almost every row is the one that draws the agent's
response. `ChatCubit` was ported carefully from `useConversation.ts`;
`ConversationBlocksCubit` was written later for the session-blocks work and
re-implemented the same stream lifecycle without the hard-won parts.

**The single most valuable change in this document is to stop having two
implementations.** See "Recommended architecture" at the end.

---

## Critical

### C1 — The timeline's event stream is silenced by a sequence-space confusion

`ConversationBlocksCubit._subscribe()` opens the event stream with
`after: _latestSeq`, and `_latestSeq` is assigned from
`snapshot.latestSequence`.

These are two unrelated counters:

- `ConversationRecord.LatestSequence` (`backend/internal/domain/conversation.go:148`)
  — *"the highest sequence handed out **in this conversation**"*. Per-conversation
  item ordering. A chat with 400 messages and activities has `latestSequence`
  around 400.
- `cdc.Event.Seq` (`backend/internal/cdc/event.go:39`) — the **global**
  `change_log` sequence for the whole daemon, which is what `/events?after=`
  means.

The backend then applies that number as a global cursor
(`backend/internal/httpd/events.go`):

```go
sentSeq := after
// replay:
c.Source.EventsAfter(ctx, *sentSeq, eventsReplayBatch)
// live:
if e.Seq <= *sentSeq { return nil }   // silently drop
```

So whenever `conversation.latestSequence >= change_log.seq`, **the timeline's
stream delivers nothing at all** — no replay, no live events — until the global
CDC log happens to overtake the conversation's item counter. On a daemon that
has not churned much, that is the normal case, and it never recovers within the
session.

The timeline then stays frozen on its pre-turn snapshot, which still says the
turn is running. That renders as a permanent loading state. This is exactly the
failure the desktop transport documents in a comment it earned the hard way
(`frontend/src/renderer/lib/event-transport.ts:63`):

> Do not mistake the payload for the entire event: doing so refreshes the
> sidebar but leaves a Chat timeline frozen on its pre-turn snapshot.

Desktop is immune because `new EventSource(.../api/v1/events)` passes no `after`
at all, so the daemon starts it at 0.

**Best approach.** Delete the cursor from this cubit rather than fixing its
value. It should not own a cursor at all — see the recommended architecture.
As an isolated fix, subscribe with `after: 0` and let the shared transport own
the real CDC cursor. Never derive a CDC cursor from conversation data.

**Guard against regression.** The two sequence spaces are both bare `int`/`int64`
and so are mutually assignable, which is what let this through. Give the CDC
cursor its own type (an extension type over `int` in Dart) so the compiler
rejects passing a conversation sequence where a CDC sequence is required. Without
that, this bug class comes back.

---

### C2 — The timeline never reconnects

```dart
_eventSub = _eventDataSource.stream(...).listen(
  _onEvent,
  onError: (Object _, StackTrace _) {},   // swallowed
  cancelOnError: false,
);
```

No `onDone`. No reconnect. No backoff. When the stream ends — for any reason:
network change, daemon restart, Tailscale re-handshake, a reaped idle socket —
the timeline is dead for the remaining life of the screen, silently. The user
must back out of the session and re-enter.

`ChatCubit._scheduleReconnect` already implements the correct behavior with
1s→15s capped backoff. This cubit has none of it.

**Best approach.** Do not copy `_scheduleReconnect` into a second place. Move
both cubits onto one shared transport that owns reconnection (see below).

---

### C3 — The timeline is not refreshed when the app returns to the foreground

`chat_body.dart:70` handles `AppLifecycleState.resumed` by calling
`context.read<ChatCubit>().onResumed()` and nothing else.
`ConversationBlocksCubit` is never told.

iOS and Android suspend the Dart isolate while backgrounded; the SSE socket does
not survive. On resume the chrome refreshes and the timeline does not, so
backgrounding and reopening the app — the obvious user recovery — **does not
clear the hang**. Combined with C2, nothing does.

**Best approach.** Resume must refresh every surface that depends on the stream.
With a shared transport this becomes one call that reconnects and triggers one
refetch, instead of a list of cubits that must each be remembered.

---

### C4 — The CDC event stream has no keepalive

`backend/internal/httpd/events.go` writes bytes only when a CDC event occurs.
An agent thinking for 40 seconds produces a completely silent socket.

Mobile cannot detect that. `chat_event_data_source.dart:39` sets
`receiveTimeout: Duration.zero`, which is correct — you cannot apply a receive
timeout to a long-lived stream — but it means a connection reaped by cellular
NAT or Tailscale produces no error and no `onDone`. `ChatCubit._streaming` stays
`true`, so `_startEvents()` early-returns forever and the zombie socket is never
replaced. `ConversationBlocksCubit` has no recovery at all (C2).

The fix already exists in this codebase, three files away. The workspace-events
SSE endpoint (`backend/internal/httpd/controllers/sessions.go:602`) does it
correctly:

```go
keepAlive := time.NewTicker(15 * time.Second)
defer keepAlive.Stop()
...
case <-keepAlive.C:
    if _, err := fmt.Fprint(w, ": keepalive\n\n"); err != nil { return }
    flusher.Flush()
```

The CDC endpoint never received the same treatment.

**Best approach.** Add the identical 15s comment-frame ticker to
`EventsController.stream`. It is a server-side write, so it also detects a dead
peer and lets the handler exit. On the client, treat "no bytes for 2 keepalive
intervals" as a dead stream and reconnect — a watchdog timer reset on every
received chunk, which works precisely because the server now guarantees traffic.

Comment frames (`: keepalive`) are already handled correctly by the client:
`parseSseFrame` returns `null` for a frame with no `data:` line.

---

## High

### H1 — A dead stream is invisible

Desktop has `frontend/src/renderer/lib/events-connection.ts`, a small store
driving an "events offline" indicator, set from four places in the transport.
Mobile has no equivalent.

This is why the bug cost a debugging session instead of being self-evident: a
frozen stream and a thinking agent render identically. The user has no way to
tell "the agent is working" from "this screen stopped receiving updates".

**Best approach.** Port the connection-state concept: `connected` /
`reconnecting` / `offline`, exposed by the shared transport and rendered as a
thin banner. A stale timeline must say it is stale. This is a correctness
requirement on a phone, where the transport genuinely does drop constantly —
not a nicety.

### H2 — Two SSE connections per chat screen

`ChatCubit` and `ConversationBlocksCubit` are both provided by
`session_route_screen.dart` and each opens its own `/events` stream. Every CDC
event therefore triggers **two** `getConversationPage` calls for the same
session, and the daemon carries two subscribers per open chat.

Each subscriber has its own `eventsLiveBuffer` of 1024 and its own replay loop.

**Best approach.** One connection per daemon for the whole app, fanned out
in-process. This is the same argument that put `MuxClient` in `core/mux/`
rather than under `terminal/`.

### H3 — The timeline refetches on other sessions' events

```dart
if (!event.touchesConversation) return;   // no sessionId check
await _fetch();
```

`ChatCubit._onEvent` correctly gates on `event.sessionId != sessionId`.
`ConversationBlocksCubit` does not. Any conversation event anywhere on the
daemon causes this session to refetch a 200-item page.

With several active sessions this is a refetch storm on a phone, on cellular,
against the sequential-auth-probing constraint documented in `AGENTS.md`.

**Best approach.** Filter by `sessionId` before fetching. With a shared
transport this is free: subscribers ask for one session's events.

### H4 — Concurrent refetches can apply out of order

`_onEvent` awaits `_fetch()` with no debounce, no in-flight coalescing and no
generation counter. A burst of events starts overlapping requests; whichever
returns last wins, so **an older snapshot can overwrite a newer one**.

`ChatCubit` guards this properly with `_refreshGeneration` and a 120 ms debounce
(and `_paginationGeneration` for `loadOlder`). `ConversationBlocksCubit` has
neither.

This produces a distinct symptom worth naming: a timeline that briefly shows the
new response and then reverts to the older state.

**Best approach.** Debounce, then a generation guard that drops any response
that is not from the newest request. Copy the `ChatCubit` shape exactly.

### H5 — The CDC cursor is committed before the refresh it triggers

```dart
if (event.seq > _cursor) {
  _cursor = event.seq;
  unawaited(CacheHelper.save(_cursorKey, _cursor));   // persisted immediately
}
...
_refreshTimer = Timer(_refreshDebounce, () => unawaited(refresh()));  // 120 ms later
```

The cursor is durable; the refresh it schedules is not. If the app is suspended
or killed in that window — routine on iOS — the persisted cursor claims the
event was consumed while the snapshot was never refetched. On next launch,
`after: cursor` skips its replay.

Result: staleness that **survives a restart** and persists until some later
event for that session arrives.

**Best approach.** Advance the durable cursor only after the refresh that
consumes it succeeds. Keep the in-memory cursor ahead for stream continuity, but
persist the *acknowledged* position, not the *received* one.

### H6 — SSE is a single point of failure with no fallback

There is no polling anywhere in the chat timeline path. The only things that
call `refresh()` are a CDC event, a user action, and app resume. When the stream
is down, the chat is frozen indefinitely with no self-healing.

Note that catalogs — models, config options, skills, workspace — *are* polled on
5/60/30 second timers. The conversation itself, the one thing that must be live,
is the only surface with no safety net.

**Best approach.** A slow reconciliation poll (~30 s) while a turn is active,
and none while idle. It costs almost nothing, converts every class of
stream failure from "hung forever" into "up to 30 s late", and is the standard
belt-and-braces for a phone client whose transport is genuinely unreliable.

---

## Medium

### M1 — Null-id turns collapse into one entry

`conversation_pages.dart`:

```dart
turns[turn.id ?? ''] = turn;
```

Every turn with a null id maps to the key `''`, so they overwrite each other and
all but the last disappear from the merged snapshot.

`ConversationBlocksCubit._mergeOlderPage` does this correctly — it skips
null-id entries with `if (turn.id != null)`. The two merge implementations
disagree.

**Best approach.** Skip null-id records rather than assigning them a shared key,
matching the blocks cubit. Better: make the id non-nullable at the parse
boundary and drop records without one, since a turn with no id cannot be
addressed by any action anyway.

### M2 — Null-id items collapse into one entry

Same defect in `conversation_item_model.dart`:

```dart
String get itemKey => 'message:${id ?? ''}';     // line 60
String get itemKey => 'activity:${id ?? ''}';    // line 126
```

Used as the dedup key in `mergeConversationPages`. All null-id messages collapse
to `message:`.

**Best approach.** As M1. If a fallback key is genuinely needed, key on
`sequence`, which is what actually orders these records.

### M3 — Turns are ordered by lexicographic string comparison of timestamps

```dart
..sort((left, right) => (left.requestedAt ?? '').compareTo(right.requestedAt ?? ''))
```

In both `conversation_pages.dart` and `ConversationBlocksCubit._mergeOlderPage`.
String comparison of ISO-8601 is only correct when every value shares one
format, one precision and one timezone offset. `+02:00` sorts before `Z`
regardless of actual instant, and fractional-second precision differences
reorder equal times.

Also note null timestamps sort to the front, ahead of everything real.

**Best approach.** Parse to `DateTime` and compare instants, with a stable
secondary key (turn id) for ties. If turns are guaranteed to carry a monotonic
sequence, prefer that over timestamps entirely.

### M4 — `_startEvents()` cannot replace a zombie stream

```dart
void _startEvents() {
  if (_streaming || unavailable != null || snapshot == null) return;
```

`_streaming` records intent ("we want a stream"), not liveness ("bytes are
arriving"). Once it is `true`, every later call is a no-op — including the one
on the resume path — even when the underlying socket is long dead.

**Best approach.** Separate intent from liveness. `_startEvents` should ensure a
*healthy* stream: if the watchdog from C4 says the current one is stale, tear it
down and reopen rather than returning early.

### M5 — A persisted CDC cursor is never invalidated

`_cursorKey` is `chatEventCursor(host, httpPort, sessionId)`. It survives daemon
restarts. If the daemon's `change_log` is ever reset, recreated, or restored
from an earlier state, its sequence restarts below the persisted cursor and
`if e.Seq <= *sentSeq` drops everything. Permanent silence, cleared only by
reinstalling the app or re-pairing to a different port.

**Best approach.** Have the daemon expose a log identity (a boot/epoch id)
alongside `seq`, and discard a persisted cursor whose epoch does not match.
Cheaply, and worth doing regardless: treat "asked for `after: N`, received
nothing within one keepalive interval, and the conversation is mid-turn" as a
reason to retry from 0 once.

### M6 — `events()` bypasses the network guard

`ChatRepositoryImp.events` goes straight to the data source while every other
method runs through `_guard`'s `NetworkStatus.isConnected` check. Probably
deliberate — a stream should attempt to connect and let reconnection handle
failure — but it is undocumented and reads as an oversight.

**Best approach.** Leave the behavior, add a one-line comment stating that
streams intentionally skip the connectivity gate because reconnection is their
error path.

---

## Not bugs, but load-bearing — do not "fix" these

- **`receiveTimeout: Duration.zero` on the SSE request.** Correct. The 12 s
  timeout `AGENTS.md` documents as load-bearing must not apply to a long-lived
  stream. The answer to a silent stream is the C4 watchdog, not a receive
  timeout.
- **Sequential auth probing in `sessions_remote_data_source.dart`.** Documented
  in `AGENTS.md`; a test pins the call order. H2 and H3 make this worse by
  multiplying request volume, which is another reason to fix them.

---

## Recommended architecture

Fixing these bugs one by one would leave the structural cause in place: **two
hand-written SSE lifecycles that must be kept in agreement, and are not.** Every
Critical and High finding above is a place where the second one diverged from
the first.

The codebase already contains the right answer to this exact problem. From
`CLAUDE.md`:

> **`MuxClient` lives in `core/mux/`, not under `terminal/`.** The Kanban board
> depends on the same socket for session patches, so nesting it under a feature
> would make the board's liveness depend on a feature it has no business
> knowing about.

The argument transfers without modification. `ChatCubit` and
`ConversationBlocksCubit` depend on the same CDC stream; today its ownership is
nested inside each of them twice.

**Introduce `core/events/ConversationEventBus`** as the SSE counterpart to
`MuxClient`:

- **One connection per daemon**, not per cubit or per screen (fixes H2).
- **Owns the CDC cursor** — one cursor, correctly typed, persisted on
  acknowledgement rather than receipt (fixes C1, H5, M5).
- **Owns reconnection**: capped backoff, plus the keepalive watchdog from C4
  (fixes C2, C4, M4).
- **Owns liveness state**, exposed as a stream the UI can render (fixes H1).
- **Fans out per session** as broadcast streams, so a subscriber receives only
  its own session's events (fixes H3).
- **Refetch-on-reconnect** built into the contract, matching desktop's
  `onopen` behavior, so a subscriber cannot forget it (fixes C3).

Cubits then subscribe and refetch. They stop owning transport entirely, exactly
as they already do for the WebSocket.

Backend work is small and separable: the keepalive ticker in `events.go` (C4),
and optionally a log epoch on the event envelope (M5).

### Suggested order

1. **C4 backend keepalive** — smallest change, unblocks the client watchdog, no
   client coupling.
2. **C1** — the reported bug. Fixable in isolation and worth landing early, but
   write it as "this cubit owns no cursor", which is the direction step 4 goes.
3. **C2 + C3** — restores recovery so the hang stops being terminal.
4. **`ConversationEventBus`** — absorbs C1/C2/C3 properly and takes H1–H3, H5,
   M4, M5 with it.
5. **H4, H6, M1–M3** — independent of the above; each is a small contained fix
   with a direct unit test.

### Testing

`test/feature/chat/presentation/chat_screen/logic/chat_cubit_stream_test.dart`
already exists and is the right home for the stream-lifecycle tests. Each of
C1–C4 and H3–H5 is expressible as a failing test against a fake event source
before any fix lands:

- C1: assert the subscribe cursor is never derived from `snapshot.latestSequence`.
- C2: a stream that closes without error results in a new subscription.
- C3: a resume signal refetches the timeline, not only the chrome.
- C4: no bytes for two keepalive intervals tears down and reopens.
- H3: an event for a different `sessionId` triggers no fetch.
- H4: an older in-flight response never overwrites a newer snapshot.
- H5: the persisted cursor does not advance when the refresh it triggered never ran.

`flutter analyze` must report "No issues found!" and `flutter test` must pass;
those two are the CI gate (`.github/workflows/mobile-flutter.yml`, Flutter 3.44.5).

---

## Related, out of scope for this document

- **No markdown rendering on mobile.** Assistant replies render as flat
  `mono12Regular` text (`block_card.dart:60`). No markdown, fenced code,
  syntax highlighting, diffs or ANSI. There is no markdown or highlighting
  package in `pubspec.yaml` and no first-party implementation. Belongs to the
  chat redesign, not to this bug list.
- **`docs/mobile-parity-ledger.md` rows 91–99 are stale.** They describe
  `chat_timeline.dart`, `chat_markdown.dart`, `markdown_blocks.dart`,
  `syntax_highlight.dart`, `ansi.dart`, `plan_card.dart`, `approval_card.dart`,
  `file_change_list.dart` and others as shipped ports. None of those files
  exist; the session-blocks work replaced that design. The ledger is the
  designated answer to "was this ever ported?", so these rows actively mislead.
