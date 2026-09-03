# Mobile Chat Stream Lifecycle Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the mobile chat timeline reliably reflect a live agent turn, by fixing the four defects that let its event stream go permanently silent, then consolidating two divergent SSE lifecycles into one shared transport.

**Architecture:** A mobile chat screen currently runs two cubits that each open their own SSE connection to `/api/v1/events`. `ChatCubit` (chrome) does it correctly; `ConversationBlocksCubit` (the timeline) re-implemented the same lifecycle and lost the cursor, the filtering, the debounce, the ordering guard and the reconnect. Phase 1 fixes the four hang-causing defects in place. Phase 2 replaces both hand-written lifecycles with a single `core/events/ConversationEventBus`, mirroring the precedent that already puts `MuxClient` in `core/mux/`.

**Tech Stack:** Go 1.25.7 (`backend/`, chi router, SQLite CDC `change_log`), Flutter 3.44.5 / Dart 3 (`packages/mobile`, flutter_bloc Cubit, Dio, mocktail, bloc_test).

**Spec:** [`docs/mobile-chat-bugs.md`](../../mobile-chat-bugs.md) — the audit this plan implements. Bug IDs (C1–C4, H1–H6, M1–M6) below refer to that document. Read it first; it explains *why* each of these is a bug, which this plan does not repeat.

## Global Constraints

- **No code comments unless they explain something non-obvious.** This repo's owner has a standing instruction against decorative comments. The comments included in this plan's code blocks are load-bearing (they record a constraint someone would otherwise undo) — keep those, add no others.
- **Mobile CI gate:** `flutter analyze` must print `No issues found!` and `flutter test` must pass. Run both from `packages/mobile`. CI pins Flutter **3.44.5** (`.github/workflows/mobile-flutter.yml`).
- **Backend gate:** `go test ./...` and `go test -race ./...` from `backend/`. Lint is golangci-lint v2.12.2 via `npm run lint` at the repo root.
- **`openapi.yaml` is generated.** Never hand-edit `backend/internal/httpd/apispec/openapi.yaml`. Change `backend/internal/httpd/apispec/specgen/build.go`, then run `go generate ./...` from `backend/`. `TestRouteSpecParity` fails the build if the spec and the routes disagree.
- **Cubit only, never `Bloc` with events.** Static-only classes are `sealed class X`. No `freezed`, no `json_serializable` in first-party mobile code.
- **Do not "optimize" two documented behaviors** (`AGENTS.md`): the 12-second `connectTimeout`/`receiveTimeout` in `dio_consumer.dart`, and the sequential auth probing in `sessions_remote_data_source.dart`. The `receiveTimeout: Duration.zero` override on the SSE request specifically is also correct and must stay — Task 3 adds a watchdog precisely because a receive timeout cannot be used here.
- **Scope discipline.** This plan fixes C1–C4 plus H3/H4 (which are unavoidable side effects of touching the same method) and, in Phase 2, H1/H2/H5/M4/M5. It does **not** touch H6, M1, M2, M3, M6, markdown rendering, or the parity ledger. Do not fold those in.

## Correction to the audit document

`docs/mobile-chat-bugs.md` suggests fixing C1 by subscribing with `after: 0`. **That is wrong for mobile and this plan does not do it.** The `change_log` table has no trimming or retention anywhere in `backend/internal/storage/sqlite/`, so it grows unboundedly for the life of a daemon. `after=0` therefore replays the entire history in 512-row batches on every connect — acceptable for desktop on localhost, not for a phone on cellular.

Instead, Task 2 adds a `fromLatest=true` query parameter so a client that refetches its own state on every event can start at the log head and replay nothing. Update the C1 section of the audit doc in Task 2's commit.

## File structure

**Backend (Go)**

| File | Responsibility | Change |
|---|---|---|
| `backend/internal/httpd/events.go` | the CDC SSE handler | keepalive ticker (T1); `fromLatest` start cursor (T2) |
| `backend/internal/httpd/events_test.go` | its tests | new tests for both |
| `backend/internal/httpd/apispec/specgen/build.go` | generated-spec source of truth | `eventsQuery.FromLatest` (T2) |

**Mobile — Phase 1**

| File | Responsibility | Change |
|---|---|---|
| `lib/core/events/cdc_cursor.dart` | **new.** The CDC cursor as a type, so a conversation sequence cannot be passed where a CDC sequence is required | created (T4) |
| `lib/feature/chat/data/data_source/chat_event_data_source.dart` | opens and parses the SSE stream | staleness watchdog (T3); `CdcCursor` parameter (T4) |
| `lib/feature/chat/data/repository/chat_repository.dart` | repository seam | `CdcCursor` parameter (T4) |
| `.../blocks_screen/logic/conversation_blocks_cubit.dart` | **the timeline** | stop deriving a cursor (T4); reconnect, filter, debounce, generation guard (T5); `onResumed` (T6) |
| `.../chat_screen/logic/chat_cubit.dart` | chrome | `CdcCursor` call site (T4) |
| `.../chat_screen/ui/widgets/chat_body.dart` | screen shell | resume also refreshes the timeline (T6) |

**Mobile — Phase 2**

| File | Responsibility | Change |
|---|---|---|
| `lib/core/events/conversation_event_bus.dart` | **new.** One SSE connection per daemon; owns cursor, reconnection, liveness, per-session fan-out | created (T7) |
| `lib/core/events/event_stream_status.dart` | **new.** The liveness enum | created (T7) |
| `lib/core/utils/service_locator.dart` | DI | register the bus (T7); rewire both cubits (T8) |
| both cubits | consumers | subscribe to the bus, stop owning transport (T8) |
| `.../chat_screen/ui/widgets/chat_stream_banner.dart` | **new.** Renders "not receiving updates" | created (T9) |

---

# Phase 1 — Stop the hang

Tasks 1–6 are independently shippable and fix the reported bug. Phase 2 then deletes some of the Phase 1 reconnect code and replaces it with the shared bus. **This is deliberate, not an oversight** — Phase 1 is hours of work that makes chat usable, Phase 2 is the refactor that stops the divergence recurring. Do not try to skip Phase 1 to "save" the work.

---

### Task 1: Keepalive on the CDC event stream (C4, server half)

The handler writes bytes only when a CDC event occurs, so an idle stream is a completely silent socket that NAT and Tailscale reap without either side noticing. The workspace-events endpoint at `backend/internal/httpd/controllers/sessions.go:602` already solves this correctly; copy that shape.

**Files:**
- Modify: `backend/internal/httpd/events.go`
- Test: `backend/internal/httpd/events_test.go`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the stream emits `: keepalive\n\n` every `eventsKeepAlive` (15s default) when otherwise idle. Task 3's client watchdog depends on this guarantee.

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/httpd/events_test.go`:

```go
type idleEventSource struct{ head int64 }

func (*idleEventSource) EventsAfter(context.Context, int64, int) ([]cdc.Event, error) {
	return nil, nil
}

func (s *idleEventSource) LatestSeq(context.Context) (int64, error) { return s.head, nil }

func TestEventsStreamWritesKeepAliveWhenIdle(t *testing.T) {
	previous := eventsKeepAlive
	eventsKeepAlive = 20 * time.Millisecond
	t.Cleanup(func() { eventsKeepAlive = previous })

	live := &fakeEventSubscriber{}
	router := NewRouterWithControl(config.Config{}, discardLogger(), nil, APIDeps{
		CDC:    &idleEventSource{},
		Events: live,
	}, ControlDeps{})
	ts := httptest.NewServer(router)
	defer ts.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, ts.URL+"/api/v1/events?after=0", nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("GET /api/v1/events: %v", err)
	}
	defer resp.Body.Close()

	reader := bufio.NewReader(resp.Body)
	line, err := reader.ReadString('\n')
	if err != nil {
		t.Fatalf("read keepalive: %v", err)
	}
	if line != ": keepalive\n" {
		t.Fatalf("first line = %q, want %q", line, ": keepalive\n")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && go test ./internal/httpd/ -run TestEventsStreamWritesKeepAliveWhenIdle -v`

Expected: FAIL — `undefined: eventsKeepAlive`.

- [ ] **Step 3: Implement the keepalive**

In `backend/internal/httpd/events.go`, add `"time"` to the import block, then add below the existing `const` block:

```go
// eventsKeepAlive is how often an otherwise idle stream writes a comment frame.
// Without it the socket carries zero bytes between CDC events, which cellular
// NAT and Tailscale reap silently — the client cannot use a receive timeout on
// a long-lived stream, so server traffic is the only liveness signal it has.
// Overridden in tests.
var eventsKeepAlive = 15 * time.Second
```

Replace the final `for` loop in `stream` with:

```go
	keepAlive := time.NewTicker(eventsKeepAlive)
	defer keepAlive.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case e := <-live:
			if err := writeSSEEvent(w, flusher, e, &sentSeq); err != nil {
				return
			}
		case <-keepAlive.C:
			if _, err := fmt.Fprint(w, ": keepalive\n\n"); err != nil {
				return
			}
			flusher.Flush()
		}
	}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && go test ./internal/httpd/ -run TestEvents -v`

Expected: PASS, including the pre-existing `TestEventsStreamSubscribesBeforeReplayAndDrainsBufferedLive` and `TestEventsStreamRejectsInvalidAfter`.

- [ ] **Step 5: Run the full backend suite with the race detector**

Run: `cd backend && go test -race ./internal/httpd/...`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/httpd/events.go backend/internal/httpd/events_test.go
git commit -m "fix(events): keep the CDC SSE stream alive while idle

An idle CDC stream carried zero bytes, so cellular NAT and Tailscale
reaped it silently and neither end noticed. Mobile cannot apply a
receive timeout to a long-lived stream, which left the chat timeline
frozen behind a dead socket. The workspace-events endpoint already
writes a 15s comment frame; the CDC endpoint now does the same.

Refs C4 in docs/mobile-chat-bugs.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `fromLatest` start cursor (C1, server half)

`change_log` is never trimmed, so `after=0` replays the daemon's entire history. A client that refetches its own snapshot on every event needs none of that history — it needs only live events. Give it a way to say so.

**Files:**
- Modify: `backend/internal/httpd/events.go`
- Modify: `backend/internal/httpd/apispec/specgen/build.go:1235-1237`
- Modify: `backend/internal/httpd/apispec/openapi.yaml` (generated — do not hand-edit)
- Modify: `docs/mobile-chat-bugs.md`
- Test: `backend/internal/httpd/events_test.go`

**Interfaces:**
- Consumes: `idleEventSource` from Task 1.
- Produces: `GET /api/v1/events?fromLatest=true` starts at the current log head and replays nothing. An explicit `after` always wins. Task 4's `CdcCursorLatest` emits exactly this query parameter.

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/httpd/events_test.go`:

```go
type headEventSource struct {
	mu        sync.Mutex
	askedFrom int64
	head      int64
}

func (s *headEventSource) EventsAfter(_ context.Context, after int64, _ int) ([]cdc.Event, error) {
	s.mu.Lock()
	s.askedFrom = after
	s.mu.Unlock()
	return nil, nil
}

func (s *headEventSource) LatestSeq(context.Context) (int64, error) { return s.head, nil }

func (s *headEventSource) replayCursor() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.askedFrom
}

func TestEventsStreamFromLatestStartsAtHead(t *testing.T) {
	live := &fakeEventSubscriber{}
	src := &headEventSource{head: 41}
	router := NewRouterWithControl(config.Config{}, discardLogger(), nil, APIDeps{
		CDC:    src,
		Events: live,
	}, ControlDeps{})
	ts := httptest.NewServer(router)
	defer ts.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, ts.URL+"/api/v1/events?fromLatest=true", nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("GET /api/v1/events: %v", err)
	}
	defer resp.Body.Close()

	go func() {
		for i := 0; i < 50; i++ {
			live.publish(testCDCEvent(42))
			time.Sleep(10 * time.Millisecond)
		}
	}()

	ids := readSSEIDs(t, resp.Body, 1)
	if got, want := strings.Join(ids, ","), "42"; got != want {
		t.Fatalf("ids = %s, want %s", got, want)
	}
	if got := src.replayCursor(); got != 41 {
		t.Fatalf("replay cursor = %d, want 41 (the log head)", got)
	}
}

func TestEventsStreamExplicitAfterBeatsFromLatest(t *testing.T) {
	live := &fakeEventSubscriber{}
	src := &headEventSource{head: 41}
	router := NewRouterWithControl(config.Config{}, discardLogger(), nil, APIDeps{
		CDC:    src,
		Events: live,
	}, ControlDeps{})
	ts := httptest.NewServer(router)
	defer ts.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, ts.URL+"/api/v1/events?after=7&fromLatest=true", nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("GET /api/v1/events: %v", err)
	}
	defer resp.Body.Close()

	go func() {
		for i := 0; i < 50; i++ {
			live.publish(testCDCEvent(42))
			time.Sleep(10 * time.Millisecond)
		}
	}()

	readSSEIDs(t, resp.Body, 1)
	if got := src.replayCursor(); got != 7 {
		t.Fatalf("replay cursor = %d, want 7 (the explicit after)", got)
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/httpd/ -run 'TestEventsStream(FromLatest|ExplicitAfter)' -v`

Expected: FAIL — `replay cursor = 0, want 41`.

- [ ] **Step 3: Implement the start cursor**

In `backend/internal/httpd/events.go`, immediately after the existing `after, err := parseEventsAfter(r)` error block in `stream`, insert:

```go
	// change_log is never trimmed, so after=0 means replaying the daemon's whole
	// history. A client that refetches its own snapshot on every event wants
	// live events only; fromLatest lets it start at the head and skip the
	// replay. An explicit after is a real resume point, so it always wins.
	if r.URL.Query().Get("after") == "" && r.URL.Query().Get("fromLatest") == "true" {
		head, headErr := c.Source.LatestSeq(r.Context())
		if headErr != nil {
			envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "EVENTS_HEAD_UNAVAILABLE",
				"Could not resolve the current event log head", nil)
			return
		}
		after = head
	}
```

- [ ] **Step 4: Declare the parameter in the spec source**

In `backend/internal/httpd/apispec/specgen/build.go`, replace the `eventsQuery` struct at line 1235:

```go
type eventsQuery struct {
	After      *int64 `query:"after,omitempty" minimum:"0" description:"Replay events with seq greater than this cursor. When omitted, clients may send Last-Event-ID instead."`
	FromLatest *bool  `query:"fromLatest,omitempty" description:"Start at the current log head and replay nothing. Ignored when after is present."`
}
```

- [ ] **Step 5: Regenerate the OpenAPI document**

Run: `cd backend && go generate ./...`

Expected: `backend/internal/httpd/apispec/openapi.yaml` now lists a `fromLatest` query parameter under `/api/v1/events`. Verify with:

`git diff --stat backend/internal/httpd/apispec/openapi.yaml`

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd backend && go test ./internal/httpd/...`

Expected: PASS, including `TestRouteSpecParity`.

- [ ] **Step 7: Correct the audit document**

In `docs/mobile-chat-bugs.md`, in the C1 section, replace the paragraph beginning "**Best approach.** Delete the cursor from this cubit" with:

```markdown
**Best approach.** Delete the cursor from this cubit rather than fixing its
value. It should not own a cursor at all — see the recommended architecture.
Because `change_log` is never trimmed, `after=0` is **not** an acceptable
substitute: it replays the daemon's entire history on every connect. Subscribe
with `fromLatest=true` instead, which starts at the log head and replays
nothing — correct for a client that refetches its own snapshot on every event.
```

- [ ] **Step 8: Commit**

```bash
git add backend/internal/httpd/events.go backend/internal/httpd/events_test.go \
        backend/internal/httpd/apispec/specgen/build.go \
        backend/internal/httpd/apispec/openapi.yaml \
        docs/mobile-chat-bugs.md
git commit -m "feat(events): let a client start the CDC stream at the log head

change_log has no retention, so after=0 replays the daemon's entire
history on every connect. A client that refetches its own snapshot per
event needs live events only. fromLatest=true starts at the head and
replays nothing; an explicit after still wins.

Refs C1 in docs/mobile-chat-bugs.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Staleness watchdog on the client stream (C4, client half)

With Task 1 shipped, the server guarantees traffic every 15s. The client can now treat silence as death — which it previously could not detect at all, because `receiveTimeout: Duration.zero` (correctly) disables Dio's own timeout for a long-lived stream.

**Files:**
- Modify: `packages/mobile/lib/feature/chat/data/data_source/chat_event_data_source.dart`
- Test: `packages/mobile/test/feature/chat/data/data_source/chat_event_data_source_test.dart`

**Interfaces:**
- Consumes: Task 1's keepalive guarantee.
- Produces: `ChatEventDataSourceImp(ApiConsumer, {Duration staleAfter})`, default `kEventStreamStaleAfter` (35s). When no bytes arrive within `staleAfter`, the returned stream emits `StaleEventStreamException` and then closes. Tasks 5 and 7 rely on that error to trigger reconnection.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `packages/mobile/test/feature/chat/data/data_source/chat_event_data_source_test.dart`:

```dart
  test('errors and closes when the server stops sending anything', () async {
    final source = ChatEventDataSourceImp(
      apiConsumer,
      staleAfter: const Duration(milliseconds: 40),
    );
    final errors = <Object>[];
    var closed = false;

    source.stream(after: 0, cancelToken: CancelToken()).listen(
      (_) {},
      onError: errors.add,
      onDone: () => closed = true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(errors.single, isA<StaleEventStreamException>());
    expect(closed, isTrue);
  });

  test('a keepalive comment frame keeps the stream alive', () async {
    final source = ChatEventDataSourceImp(
      apiConsumer,
      staleAfter: const Duration(milliseconds: 60),
    );
    final errors = <Object>[];

    source
        .stream(after: 0, cancelToken: CancelToken())
        .listen((_) {}, onError: errors.add);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    chunks.add(bytes(': keepalive\n\n'));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(errors, isEmpty);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/chat/data/data_source/chat_event_data_source_test.dart`

Expected: FAIL — no named parameter `staleAfter`, and `StaleEventStreamException` is undefined.

- [ ] **Step 3: Implement the watchdog**

In `packages/mobile/lib/feature/chat/data/data_source/chat_event_data_source.dart`, add above `abstract class ChatEventDataSource`:

```dart
const Duration kEventStreamStaleAfter = Duration(seconds: 35);

class StaleEventStreamException implements Exception {
  const StaleEventStreamException(this.silentFor);

  final Duration silentFor;

  @override
  String toString() =>
      'StaleEventStreamException: no server traffic for $silentFor';
}
```

Replace the `ChatEventDataSourceImp` constructor and field block with:

```dart
  ChatEventDataSourceImp(
    this._apiConsumer, {
    Duration staleAfter = kEventStreamStaleAfter,
  }) : _staleAfter = staleAfter;

  final ApiConsumer _apiConsumer;
  final Duration _staleAfter;
```

Inside `stream`, declare alongside the other locals:

```dart
    Timer? staleTimer;
```

Add these two closures immediately before `Future<void> start() async {`:

```dart
    void stopStaleTimer() {
      staleTimer?.cancel();
      staleTimer = null;
    }

    // The server guarantees a comment frame every 15s (see events.go), so
    // silence past this window means the socket is dead. Dio cannot tell us:
    // receiveTimeout must stay disabled on a long-lived stream.
    void markAlive() {
      staleTimer?.cancel();
      staleTimer = Timer(_staleAfter, () {
        if (canceled) return;
        controller.addError(
          StaleEventStreamException(_staleAfter),
          StackTrace.current,
        );
        unawaited(subscription?.cancel());
        subscription = null;
        if (!controller.isClosed) unawaited(controller.close());
      });
    }
```

In the `listen` chunk handler, make `markAlive()` the first statement:

```dart
              (chunk) {
                markAlive();
                buffer += chunk;
                final split = takeSseFrames(buffer);
                buffer = split.remainder;
                for (final frame in split.frames) {
                  final event = parseSseFrame(frame);
                  if (event != null) controller.add(event);
                }
              },
```

In the same `listen` call, add `stopStaleTimer()` to both handlers:

```dart
              onError: (Object error, StackTrace stackTrace) {
                stopStaleTimer();
                if (!canceled) controller.addError(error, stackTrace);
              },
              onDone: () {
                stopStaleTimer();
                if (!canceled) controller.close();
              },
```

Immediately after the `subscription = ... .listen(...)` statement and before the `if (canceled)` block, start the clock:

```dart
        markAlive();
```

In the `catch` block of `start()`, add `stopStaleTimer();` as the first statement. In the controller's `onCancel`, add `stopStaleTimer();` as the first statement.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/chat/data/data_source/chat_event_data_source_test.dart`

Expected: PASS, including the four pre-existing tests in that file.

- [ ] **Step 5: Verify the analyzer is clean**

Run: `cd packages/mobile && flutter analyze`

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib/feature/chat/data/data_source/chat_event_data_source.dart \
        packages/mobile/test/feature/chat/data/data_source/chat_event_data_source_test.dart
git commit -m "fix(chat): detect a silently dead event stream

receiveTimeout must stay disabled on a long-lived SSE stream, so a
connection reaped by NAT produced no error and no onDone — the client
held a zombie socket forever. Now that the server guarantees a comment
frame every 15s, silence past 35s is a reliable death signal.

Refs C4 in docs/mobile-chat-bugs.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Make the CDC cursor a type, and stop deriving it from conversation data (C1, client half)

This is the reported bug. `ConversationBlocksCubit` passes `snapshot.latestSequence` — a **per-conversation item counter** — as `after`, which the endpoint reads as the **global `change_log` sequence**. Both are plain integers, so nothing objected. Fixing the value alone would leave the next person free to reintroduce it; give the cursor a type so the compiler refuses.

**Files:**
- Create: `packages/mobile/lib/core/events/cdc_cursor.dart`
- Modify: `packages/mobile/lib/feature/chat/data/data_source/chat_event_data_source.dart`
- Modify: `packages/mobile/lib/feature/chat/data/repository/chat_repository.dart`
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/logic/chat_cubit.dart:434`
- Modify: `.../blocks_screen/logic/conversation_blocks_cubit.dart`
- Create: `packages/mobile/test/core/events/cdc_cursor_test.dart`
- Modify: `packages/mobile/test/feature/chat/data/data_source/chat_event_data_source_test.dart`

**Interfaces:**
- Consumes: Task 2's `fromLatest=true`; Task 3's `staleAfter` constructor.
- Produces:
  - `sealed class CdcCursor` with `const CdcCursor.at(int seq)`, `const CdcCursor.latest()`, and `Map<String, dynamic> get queryParameters`.
  - `ChatEventDataSource.stream({required CdcCursor after, required CancelToken cancelToken})`.
  - `ChatRepository.events({required CdcCursor after, required CancelToken cancelToken})`.
  - Task 7's bus consumes both.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/core/events/cdc_cursor_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/events/cdc_cursor.dart';

void main() {
  test('a positioned cursor asks the daemon to replay after that seq', () {
    expect(const CdcCursor.at(7).queryParameters, {'after': 7});
  });

  test('a positioned cursor never asks for a negative seq', () {
    expect(const CdcCursor.at(-4).queryParameters, {'after': 0});
  });

  test('the latest cursor asks for the head instead of a replay', () {
    expect(const CdcCursor.latest().queryParameters, {'fromLatest': true});
  });

  test('the latest cursor never sends an after parameter', () {
    expect(const CdcCursor.latest().queryParameters.containsKey('after'), isFalse);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/events/cdc_cursor_test.dart`

Expected: FAIL — `Target of URI doesn't exist: 'package:operator_mobile/core/events/cdc_cursor.dart'`.

- [ ] **Step 3: Create the cursor type**

Create `packages/mobile/lib/core/events/cdc_cursor.dart`:

```dart
/// Where a CDC event stream starts.
///
/// The daemon's `change_log` sequence and a conversation's `latestSequence` are
/// unrelated counters that are both plain integers. Passing the second where the
/// first belongs silences the stream permanently, because the endpoint drops
/// every event at or below the cursor it is given. This type exists so that
/// mistake cannot compile.
sealed class CdcCursor {
  const CdcCursor();

  const factory CdcCursor.at(int seq) = CdcCursorAt;

  const factory CdcCursor.latest() = CdcCursorLatest;

  Map<String, dynamic> get queryParameters;
}

final class CdcCursorAt extends CdcCursor {
  const CdcCursorAt(this.seq);

  final int seq;

  @override
  Map<String, dynamic> get queryParameters => {'after': seq < 0 ? 0 : seq};
}

final class CdcCursorLatest extends CdcCursor {
  const CdcCursorLatest();

  @override
  Map<String, dynamic> get queryParameters => const {'fromLatest': true};
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/core/events/cdc_cursor_test.dart`

Expected: PASS (4 tests).

- [ ] **Step 5: Thread the type through the data source**

In `chat_event_data_source.dart`, add the import:

```dart
import 'package:operator_mobile/core/events/cdc_cursor.dart';
```

Remove the now-unused `import 'dart:math';`. Change the abstract signature and the implementation signature to take `required CdcCursor after`, and replace the `queryParameters` argument in the `_apiConsumer.get` call:

```dart
          queryParameters: after.queryParameters,
```

- [ ] **Step 6: Thread the type through the repository**

In `chat_repository.dart`, add the same import, then change both the abstract declaration and the `ChatRepositoryImp` override of `events` to take `required CdcCursor after`. The body is unchanged.

- [ ] **Step 7: Fix the two call sites**

In `chat_cubit.dart`, add the import and change the `_openEventStream` call:

```dart
    _eventSub = _repository
        .events(after: CdcCursor.at(_cursor), cancelToken: cancelToken)
```

In `conversation_blocks_cubit.dart`, add the import and replace `_subscribe` in full:

```dart
  void _subscribe() {
    if (_disposed) return;
    final cancelToken = CancelToken();
    _eventCancel = cancelToken;
    _eventSub = _eventDataSource
        .stream(after: _streamCursor(), cancelToken: cancelToken)
        .listen(
          _onEvent,
          onError: (Object _, StackTrace _) {},
          cancelOnError: false,
        );
  }

  // The conversation's latestSequence is not a CDC sequence. This cubit refetches
  // the whole snapshot on every event, so it wants live events and no replay;
  // after a reconnect it resumes from the last CDC seq it actually saw.
  CdcCursor _streamCursor() =>
      _cdcSeq == null ? const CdcCursor.latest() : CdcCursor.at(_cdcSeq!);
```

Replace the `int _latestSeq = 0;` field with:

```dart
  int? _cdcSeq;
```

In `_applySnapshot`, delete these two lines entirely:

```dart
    final latest = snapshot.latestSequence;
    if (latest > _latestSeq) _latestSeq = latest;
```

Replace `_onEvent` with:

```dart
  Future<void> _onEvent(ConversationEventModel event) async {
    if (_disposed) return;
    final seq = event.seq;
    if (_cdcSeq == null || seq > _cdcSeq!) _cdcSeq = seq;
    if (!event.touchesConversation) return;
    await _fetch();
  }
```

- [ ] **Step 8: Update the existing data source tests to the new signature**

In `test/feature/chat/data/data_source/chat_event_data_source_test.dart`, add the import for `cdc_cursor.dart`, then change every `stream(after: N, ...)` call:

- `after: 7` becomes `after: const CdcCursor.at(7)`
- `after: -4` becomes `after: const CdcCursor.at(-4)`
- `after: 0` becomes `after: const CdcCursor.at(0)` (three occurrences, including the two tests added in Task 3)

The existing expectations `{'after': 7}` and `{'after': 0}` remain correct and unchanged.

- [ ] **Step 9: Run the full mobile suite**

Run: `cd packages/mobile && flutter test`

Expected: PASS. If `chat_cubit_stream_test.dart` fails to compile, it stubs `repository.events` with an `int` matcher — change that stub's named argument type to `any(named: 'after')` so it matches any `CdcCursor`.

- [ ] **Step 10: Verify the analyzer is clean**

Run: `cd packages/mobile && flutter analyze`

Expected: `No issues found!`

- [ ] **Step 11: Commit**

```bash
git add packages/mobile/lib/core/events/cdc_cursor.dart \
        packages/mobile/test/core/events/cdc_cursor_test.dart \
        packages/mobile/lib/feature/chat/data/data_source/chat_event_data_source.dart \
        packages/mobile/lib/feature/chat/data/repository/chat_repository.dart \
        packages/mobile/lib/feature/chat/presentation/chat_screen/logic/chat_cubit.dart \
        packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart \
        packages/mobile/test/feature/chat/data/data_source/chat_event_data_source_test.dart
git commit -m "fix(chat): stop deriving the CDC cursor from conversation data

ConversationBlocksCubit subscribed with snapshot.latestSequence, a
per-conversation item counter, where the endpoint expects the global
change_log sequence. Whenever the former exceeded the latter — normal for
any conversation with history — the daemon dropped every event and the
timeline froze on its pre-turn snapshot, which still reads as a running
turn. That is the reported permanent loading state.

CdcCursor makes the two sequence spaces distinct types so the mistake
cannot compile again. The timeline now subscribes from the log head and
resumes from the last CDC seq it actually observed.

Refs C1 in docs/mobile-chat-bugs.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Reconnect, session filter, debounce and ordering guard for the timeline (C2, H3, H4)

`ConversationBlocksCubit` swallows stream errors into an empty `onError` and has no `onDone`, so one dropped connection kills the timeline for the life of the screen. It also refetches on **every** event from **every** session with no debounce and no ordering guard, so bursts produce overlapping requests whose responses can land out of order.

**Files:**
- Modify: `.../blocks_screen/logic/conversation_blocks_cubit.dart`
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit_stream_test.dart` (create)

**Interfaces:**
- Consumes: Task 4's `CdcCursor` and `_cdcSeq`; Task 3's `StaleEventStreamException`.
- Produces: `ConversationBlocksCubit(ChatRepository, ChatEventDataSource, String sessionId, {Duration refreshDebounce, Duration reconnectMin, Duration reconnectMax})`. Task 8 removes all of it again in favour of the bus.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit_stream_test.dart`:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/events/cdc_cursor.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart';

class _MockChatRepository extends Mock implements ChatRepository {}

class _MockEventDataSource extends Mock implements ChatEventDataSource {}

class _FakeCancelToken extends Fake implements CancelToken {}

void main() {
  late _MockChatRepository repository;
  late _MockEventDataSource eventSource;
  late List<StreamController<ConversationEventModel>> opened;
  late int fetches;

  setUpAll(() {
    registerFallbackValue(_FakeCancelToken());
    registerFallbackValue(const CdcCursor.latest());
  });

  setUp(() {
    repository = _MockChatRepository();
    eventSource = _MockEventDataSource();
    opened = [];
    fetches = 0;

    when(
      () => repository.getConversationPage('w-1', beforeSequence: null),
    ).thenAnswer((_) async {
      fetches += 1;
      return Result.success(
        GlobalResponse(
          data: const ConversationSnapshotModel(
            conversationId: 'c-1',
            sessionId: 'w-1',
            harness: 'codex',
            controllerState: 'ready',
            latestSequence: 400,
          ),
        ),
      );
    });

    when(
      () => eventSource.stream(
        after: any(named: 'after'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) {
      final controller = StreamController<ConversationEventModel>();
      opened.add(controller);
      return controller.stream;
    });
  });

  ConversationBlocksCubit build() => ConversationBlocksCubit(
    repository,
    eventSource,
    'w-1',
    refreshDebounce: const Duration(milliseconds: 10),
    reconnectMin: const Duration(milliseconds: 10),
    reconnectMax: const Duration(milliseconds: 20),
  );

  ConversationEventModel event(int seq, String sessionId) =>
      ConversationEventModel(
        seq: seq,
        sessionId: sessionId,
        type: 'conversation_updated',
        payload: const {'conversationId': 'c-1'},
      );

  test('reopens the stream after it closes', () async {
    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(opened, hasLength(1));

    await opened.first.close();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(opened, hasLength(2));
    await cubit.close();
  });

  test('reopens the stream after a staleness error', () async {
    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    opened.first.addError(
      const StaleEventStreamException(Duration(seconds: 35)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(opened.length, greaterThan(1));
    await cubit.close();
  });

  test('ignores events belonging to another session', () async {
    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final before = fetches;

    opened.first.add(event(500, 'w-2'));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(fetches, before);
    await cubit.close();
  });

  test('collapses an event burst into a single refetch', () async {
    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final before = fetches;

    for (var seq = 500; seq < 510; seq++) {
      opened.first.add(event(seq, 'w-1'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(fetches, before + 1);
    await cubit.close();
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit_stream_test.dart`

Expected: FAIL — no named parameters `refreshDebounce` / `reconnectMin` / `reconnectMax`.

- [ ] **Step 3: Add the constructor parameters and fields**

In `conversation_blocks_cubit.dart`, replace the constructor with:

```dart
  ConversationBlocksCubit(
    this._repository,
    this._eventDataSource,
    this.sessionId, {
    Duration refreshDebounce = const Duration(milliseconds: 120),
    Duration reconnectMin = const Duration(seconds: 1),
    Duration reconnectMax = const Duration(seconds: 15),
  }) : _refreshDebounce = refreshDebounce,
       _reconnectMin = reconnectMin,
       _reconnectMax = reconnectMax,
       super(const ConversationBlocksInitialState()) {
    unawaited(_initialFetch());
  }
```

Add alongside the existing fields:

```dart
  final Duration _refreshDebounce;
  final Duration _reconnectMin;
  final Duration _reconnectMax;

  Timer? _refreshTimer;
  Timer? _reconnectTimer;
  Duration _reconnectDelay = Duration.zero;
  int _fetchGeneration = 0;
```

- [ ] **Step 4: Implement reconnect, filtering, debounce and the ordering guard**

Replace `_subscribe` (as written in Task 4) with:

```dart
  void _subscribe() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_eventSub?.cancel());
    _eventCancel?.cancel('resubscribing');

    final cancelToken = CancelToken();
    _eventCancel = cancelToken;
    _eventSub = _eventDataSource
        .stream(after: _streamCursor(), cancelToken: cancelToken)
        .listen(
          _onEvent,
          onError: (Object _, StackTrace _) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    unawaited(_eventSub?.cancel());
    _eventSub = null;
    if (_reconnectDelay == Duration.zero) _reconnectDelay = _reconnectMin;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, _subscribe);
    final next = _reconnectDelay * 2;
    _reconnectDelay = next > _reconnectMax ? _reconnectMax : next;
  }
```

Replace `_onEvent` with:

```dart
  void _onEvent(ConversationEventModel event) {
    if (_disposed) return;
    _reconnectDelay = _reconnectMin;
    final seq = event.seq;
    if (_cdcSeq == null || seq > _cdcSeq!) _cdcSeq = seq;
    if (event.sessionId != sessionId || !event.touchesConversation) return;

    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () => unawaited(_fetch()));
  }
```

Replace `_fetch` with a generation-guarded version:

```dart
  Future<void> _fetch({int? beforeSequence}) async {
    final generation = ++_fetchGeneration;
    final result = await _repository.getConversationPage(
      sessionId,
      beforeSequence: beforeSequence,
    );
    if (_disposed) return;
    // A burst of events can leave several page requests in flight. Applying a
    // response that is no longer the newest would move the timeline backwards.
    if (beforeSequence == null && generation != _fetchGeneration) return;
    result.when(
      onSuccess: (response) {
        final data = response.data;
        if (data == null) {
          _applyEmptyResponse(beforeSequence: beforeSequence);
          return;
        }
        _applySnapshot(data, beforeSequence: beforeSequence);
      },
      onFailure: (failure) =>
          _applyFailure(failure, beforeSequence: beforeSequence),
    );
  }
```

Replace `close` with:

```dart
  @override
  Future<void> close() {
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_eventSub?.cancel());
    _eventSub = null;
    _eventCancel?.cancel('cubit closed');
    _eventCancel = null;
    return super.close();
  }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit_stream_test.dart`

Expected: PASS (4 tests).

- [ ] **Step 6: Run the full mobile suite and the analyzer**

Run: `cd packages/mobile && flutter test && flutter analyze`

Expected: all tests PASS, `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart \
        packages/mobile/test/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit_stream_test.dart
git commit -m "fix(chat): make the timeline stream recover and stop over-fetching

The timeline swallowed stream errors into an empty onError with no
onDone, so a single dropped connection killed it for the life of the
screen. It also refetched a 200-item page on every event from every
session, with no debounce and no ordering guard, so bursts produced
overlapping requests whose responses could land out of order and move
the timeline backwards.

Refs C2, H3, H4 in docs/mobile-chat-bugs.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Refresh the timeline when the app returns to the foreground (C3)

`chat_body.dart` handles `AppLifecycleState.resumed` by calling `ChatCubit.onResumed()` and nothing else, so the chrome refreshes and the timeline does not. Both platforms suspend the isolate while backgrounded and the socket does not survive, which is why backgrounding and reopening — the obvious user recovery — does not clear the hang.

**Files:**
- Modify: `.../blocks_screen/logic/conversation_blocks_cubit.dart`
- Modify: `.../chat_screen/ui/widgets/chat_body.dart:70-74`
- Test: `.../conversation_blocks_cubit_stream_test.dart`

**Interfaces:**
- Consumes: Task 5's `_subscribe` and `_fetch`.
- Produces: `ConversationBlocksCubit.onResumed()` — resubscribes and refetches without flashing a loading state.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `conversation_blocks_cubit_stream_test.dart`:

```dart
  test('resuming reopens the stream and refetches without a loading flash', () async {
    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final before = fetches;
    final loadingStates = <bool>[];
    final sub = cubit.stream.listen((state) {
      if (state is ConversationBlocksReadyState) loadingStates.add(state.isLoading);
    });

    await cubit.onResumed();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(opened.length, greaterThan(1));
    expect(fetches, greaterThan(before));
    expect(loadingStates, isNot(contains(true)));
    await sub.cancel();
    await cubit.close();
  });
```

Add this import at the top of the file:

```dart
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_state.dart';
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit_stream_test.dart --plain-name 'resuming reopens'`

Expected: FAIL — `The method 'onResumed' isn't defined`.

- [ ] **Step 3: Add `onResumed` to the cubit**

In `conversation_blocks_cubit.dart`, add immediately above `Future<void> loadOlder()`:

```dart
  // Both platforms suspend the isolate while backgrounded and the socket does
  // not survive it, so resume must rebuild the stream, not only refetch. No
  // loading flag: the timeline already has content worth keeping on screen.
  Future<void> onResumed() async {
    if (_disposed) return;
    _reconnectDelay = _reconnectMin;
    _subscribe();
    await _fetch();
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit_stream_test.dart`

Expected: PASS (5 tests).

- [ ] **Step 5: Call it from the screen**

In `chat_body.dart`, add these imports:

```dart
import 'dart:async';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart';
```

Replace `didChangeAppLifecycleState`:

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<ChatCubit>().onResumed();
      unawaited(context.read<ConversationBlocksCubit>().onResumed());
    }
  }
```

- [ ] **Step 6: Run the full mobile suite and the analyzer**

Run: `cd packages/mobile && flutter test && flutter analyze`

Expected: all tests PASS, `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart \
        packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart \
        packages/mobile/test/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit_stream_test.dart
git commit -m "fix(chat): refresh the timeline when the app returns to the foreground

Resume refreshed the chrome and left the timeline on a socket that did
not survive suspension, so backgrounding and reopening the app — the
obvious user recovery — did not clear a frozen timeline.

Refs C3 in docs/mobile-chat-bugs.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

**Phase 1 checkpoint.** The reported bug is fixed and the timeline recovers from connection loss. Verify by hand against a real daemon before starting Phase 2: open a chat session on the phone, send a prompt that takes 30+ seconds, and confirm the response appears without touching the app. Then background the app mid-turn, wait 60 seconds, and reopen — the timeline must catch up.

---

# Phase 2 — One transport

Two hand-written SSE lifecycles that must be kept in agreement, and are not, is the structural cause of every Phase 1 defect. This phase gives the CDC stream one owner, exactly as `MuxClient` owns the WebSocket for `terminal` and the Kanban board.

**A design consequence worth stating up front:** the bus holds its cursor **in memory only**. It starts every app launch at `CdcCursor.latest()` and every subscriber fetches a fresh snapshot on subscribe. Nothing is lost, and a cursor that is never durable can never be stale, can never be ahead of a reset log, and can never be committed before the refresh it triggers. That deletes H5 and M5 by construction rather than fixing them.

---

### Task 7: `ConversationEventBus`

**Files:**
- Create: `packages/mobile/lib/core/events/event_stream_status.dart`
- Create: `packages/mobile/lib/core/events/conversation_event_bus.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart:92-95`
- Test: `packages/mobile/test/core/events/conversation_event_bus_test.dart` (create)

**Interfaces:**
- Consumes: `ChatEventDataSource.stream({required CdcCursor after, required CancelToken cancelToken})` (Task 4); `StaleEventStreamException` (Task 3).
- Produces:
  - `enum EventStreamStatus { connecting, connected, reconnecting }`
  - `ConversationEventBus(ChatEventDataSource, {Duration reconnectMin, Duration reconnectMax})`
  - `Stream<EventStreamStatus> get status`, `EventStreamStatus get currentStatus`
  - `Stream<ConversationEventModel> eventsFor(String sessionId)` — broadcast, filtered to that session and to `touchesConversation`
  - `Stream<void> get reconnects` — fires once after each successful (re)connection, so subscribers refetch to cover the gap
  - `void connect()`, `Future<void> disconnect()`, `void onResumed()`

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/core/events/conversation_event_bus_test.dart`:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/events/cdc_cursor.dart';
import 'package:operator_mobile/core/events/conversation_event_bus.dart';
import 'package:operator_mobile/core/events/event_stream_status.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

class _MockEventDataSource extends Mock implements ChatEventDataSource {}

class _FakeCancelToken extends Fake implements CancelToken {}

void main() {
  late _MockEventDataSource source;
  late List<StreamController<ConversationEventModel>> opened;
  late List<CdcCursor> cursors;

  setUpAll(() {
    registerFallbackValue(_FakeCancelToken());
    registerFallbackValue(const CdcCursor.latest());
  });

  setUp(() {
    source = _MockEventDataSource();
    opened = [];
    cursors = [];
    when(
      () => source.stream(
        after: any(named: 'after'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((invocation) {
      cursors.add(invocation.namedArguments[#after] as CdcCursor);
      final controller = StreamController<ConversationEventModel>();
      opened.add(controller);
      return controller.stream;
    });
  });

  ConversationEventBus build() => ConversationEventBus(
    source,
    reconnectMin: const Duration(milliseconds: 10),
    reconnectMax: const Duration(milliseconds: 20),
  );

  ConversationEventModel event(int seq, String sessionId) =>
      ConversationEventModel(
        seq: seq,
        sessionId: sessionId,
        type: 'conversation_updated',
        payload: const {'conversationId': 'c-1'},
      );

  test('opens exactly one stream for many subscribers', () async {
    final bus = build();
    bus.eventsFor('w-1').listen((_) {});
    bus.eventsFor('w-2').listen((_) {});
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(opened, hasLength(1));
    await bus.disconnect();
  });

  test('starts at the log head and resumes from the last seq seen', () async {
    final bus = build();
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(cursors.single, isA<CdcCursorLatest>());

    opened.first.add(event(90, 'w-1'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await opened.first.close();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(cursors.last, isA<CdcCursorAt>());
    expect((cursors.last as CdcCursorAt).seq, 90);
    await bus.disconnect();
  });

  test('routes an event only to its own session', () async {
    final bus = build();
    final one = <int>[];
    final two = <int>[];
    bus.eventsFor('w-1').listen((e) => one.add(e.seq));
    bus.eventsFor('w-2').listen((e) => two.add(e.seq));
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    opened.first.add(event(91, 'w-1'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(one, [91]);
    expect(two, isEmpty);
    await bus.disconnect();
  });

  test('reports connecting then connected, and reconnecting on loss', () async {
    final bus = build();
    final seen = <EventStreamStatus>[];
    bus.status.listen(seen.add);
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    opened.first.addError(
      const StaleEventStreamException(Duration(seconds: 35)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(seen.first, EventStreamStatus.connecting);
    expect(seen, contains(EventStreamStatus.connected));
    expect(seen, contains(EventStreamStatus.reconnecting));
    await bus.disconnect();
  });

  test('signals a reconnect so subscribers can cover the gap', () async {
    final bus = build();
    var reconnects = 0;
    bus.reconnects.listen((_) => reconnects += 1);
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(reconnects, 1);

    await opened.first.close();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(reconnects, 2);
    await bus.disconnect();
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/events/conversation_event_bus_test.dart`

Expected: FAIL — `Target of URI doesn't exist: '.../conversation_event_bus.dart'`.

- [ ] **Step 3: Create the status enum**

Create `packages/mobile/lib/core/events/event_stream_status.dart`:

```dart
/// Liveness of the daemon's CDC event stream.
///
/// A phone loses this connection constantly, and a stale timeline is
/// indistinguishable from a working agent unless the UI can say which it is.
enum EventStreamStatus { connecting, connected, reconnecting }
```

- [ ] **Step 4: Create the bus**

Create `packages/mobile/lib/core/events/conversation_event_bus.dart`:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:operator_mobile/core/events/cdc_cursor.dart';
import 'package:operator_mobile/core/events/event_stream_status.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

/// One CDC event stream for the whole app, fanned out per session.
///
/// This is the SSE counterpart to `MuxClient` and lives in `core/` for the same
/// reason: the chat chrome and the timeline both depend on it, so neither
/// feature can own it. It holds the cursor, the reconnection policy and the
/// liveness signal, and subscribers hold none of those.
///
/// The cursor is deliberately in-memory only. Every subscriber refetches its own
/// snapshot when it subscribes and again on [reconnects], so replaying history
/// across app launches buys nothing — and a cursor that is never durable can
/// never be stale, ahead of a reset log, or persisted before the refresh that
/// consumes it.
class ConversationEventBus {
  ConversationEventBus(
    this._source, {
    Duration reconnectMin = const Duration(seconds: 1),
    Duration reconnectMax = const Duration(seconds: 15),
  }) : _reconnectMin = reconnectMin,
       _reconnectMax = reconnectMax;

  final ChatEventDataSource _source;
  final Duration _reconnectMin;
  final Duration _reconnectMax;

  final _statusController = StreamController<EventStreamStatus>.broadcast();
  final _eventsController = StreamController<ConversationEventModel>.broadcast();
  final _reconnectsController = StreamController<void>.broadcast();

  Stream<EventStreamStatus> get status => _statusController.stream;
  Stream<void> get reconnects => _reconnectsController.stream;

  EventStreamStatus _currentStatus = EventStreamStatus.connecting;
  EventStreamStatus get currentStatus => _currentStatus;

  StreamSubscription<ConversationEventModel>? _sub;
  CancelToken? _cancel;
  Timer? _reconnectTimer;
  Duration _reconnectDelay = Duration.zero;
  int? _cdcSeq;
  bool _wanted = false;

  Stream<ConversationEventModel> eventsFor(String sessionId) => _eventsController
      .stream
      .where(
        (event) => event.sessionId == sessionId && event.touchesConversation,
      );

  void connect() {
    if (_wanted && _sub != null) return;
    _wanted = true;
    _reconnectDelay = _reconnectMin;
    _open();
  }

  void onResumed() {
    if (!_wanted) return connect();
    _reconnectDelay = _reconnectMin;
    _open();
  }

  Future<void> disconnect() async {
    _wanted = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    _cancel?.cancel('bus disconnected');
    _cancel = null;
  }

  void _setStatus(EventStreamStatus next) {
    _currentStatus = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  void _open() {
    if (!_wanted) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_sub?.cancel());
    _sub = null;
    _cancel?.cancel('reopening');

    _setStatus(EventStreamStatus.connecting);
    final cancelToken = CancelToken();
    _cancel = cancelToken;
    _sub = _source
        .stream(after: _cursor(), cancelToken: cancelToken)
        .listen(
          _onEvent,
          onError: (Object _, StackTrace _) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
    _setStatus(EventStreamStatus.connected);
    if (!_reconnectsController.isClosed) _reconnectsController.add(null);
  }

  CdcCursor _cursor() =>
      _cdcSeq == null ? const CdcCursor.latest() : CdcCursor.at(_cdcSeq!);

  void _onEvent(ConversationEventModel event) {
    _reconnectDelay = _reconnectMin;
    final seq = event.seq;
    if (_cdcSeq == null || seq > _cdcSeq!) _cdcSeq = seq;
    if (!_eventsController.isClosed) _eventsController.add(event);
  }

  void _scheduleReconnect() {
    unawaited(_sub?.cancel());
    _sub = null;
    if (!_wanted) return;
    _setStatus(EventStreamStatus.reconnecting);
    if (_reconnectDelay == Duration.zero) _reconnectDelay = _reconnectMin;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, _open);
    final next = _reconnectDelay * 2;
    _reconnectDelay = next > _reconnectMax ? _reconnectMax : next;
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/core/events/conversation_event_bus_test.dart`

Expected: PASS (5 tests).

- [ ] **Step 6: Register the bus**

In `packages/mobile/lib/core/utils/service_locator.dart`, add the import for `conversation_event_bus.dart`, then add immediately below the existing `MuxClient` registration at line 92:

```dart
    sl.registerLazySingleton<ConversationEventBus>(
      () => ConversationEventBus(sl<ChatEventDataSource>()),
    );
```

`ChatEventDataSource` is registered in `_chatFeatureSetup`; `get_it` resolves lazy singletons on demand, so registration order does not matter.

- [ ] **Step 7: Run the full suite and the analyzer**

Run: `cd packages/mobile && flutter test && flutter analyze`

Expected: all tests PASS, `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib/core/events/event_stream_status.dart \
        packages/mobile/lib/core/events/conversation_event_bus.dart \
        packages/mobile/lib/core/utils/service_locator.dart \
        packages/mobile/test/core/events/conversation_event_bus_test.dart
git commit -m "feat(core): add ConversationEventBus, one CDC stream for the app

The SSE counterpart to MuxClient, in core/ for the same reason: the chat
chrome and the timeline both depend on it, so neither feature can own it.
It holds the cursor, the reconnection policy and the liveness signal.

The cursor is in-memory only and starts at the log head. Subscribers
refetch on subscribe and on every reconnect, so replay across launches
buys nothing — and a cursor that is never durable cannot be stale, ahead
of a reset log, or committed before the refresh it triggers.

Refs H1, H2, H5, M5 in docs/mobile-chat-bugs.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Move both cubits onto the bus (H2, H5, M4)

**Files:**
- Modify: `.../chat_screen/logic/chat_cubit.dart`
- Modify: `.../blocks_screen/logic/conversation_blocks_cubit.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart:193-213, 246-251`
- Modify: `packages/mobile/lib/core/helpers/cache/cache_keys.dart:12`
- Modify: `.../chat_cubit_stream_test.dart`, `.../conversation_blocks_cubit_stream_test.dart`

**Interfaces:**
- Consumes: everything Task 7 produces.
- Produces: `ChatCubit(ChatRepository, String sessionId, {required ConversationEventBus eventBus, ...})` — the `configStore` parameter is gone. `ConversationBlocksCubit(ChatRepository, ConversationEventBus, String sessionId, {Duration refreshDebounce})` — the reconnect parameters are gone.

- [ ] **Step 1: Rewrite the timeline cubit's transport**

In `conversation_blocks_cubit.dart`:

Replace the `ChatEventDataSource` field and constructor parameter with `ConversationEventBus`, and delete `reconnectMin` / `reconnectMax`:

```dart
  ConversationBlocksCubit(
    this._repository,
    this._eventBus,
    this.sessionId, {
    Duration refreshDebounce = const Duration(milliseconds: 120),
  }) : _refreshDebounce = refreshDebounce,
       super(const ConversationBlocksInitialState()) {
    unawaited(_initialFetch());
  }

  final ConversationEventBus _eventBus;
```

Delete these fields: `_eventCancel`, `_reconnectTimer`, `_reconnectDelay`, `_reconnectMin`, `_reconnectMax`, `_cdcSeq`. Add:

```dart
  StreamSubscription<void>? _reconnectSub;
```

Change `_eventSub`'s type to `StreamSubscription<ConversationEventModel>?` (unchanged) and replace `_subscribe`, `_scheduleReconnect` and `_streamCursor` with a single method:

```dart
  void _subscribe() {
    if (_disposed) return;
    _eventBus.connect();
    _eventSub ??= _eventBus.eventsFor(sessionId).listen(_onEvent);
    // Events emitted while the stream was down were never delivered; refetch
    // once on every (re)connection to cover the gap.
    _reconnectSub ??= _eventBus.reconnects.listen((_) => unawaited(_fetch()));
  }
```

Replace `_onEvent` with:

```dart
  void _onEvent(ConversationEventModel _) {
    if (_disposed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () => unawaited(_fetch()));
  }
```

The bus already filters by session and by `touchesConversation`, so this method does neither.

Replace `onResumed`:

```dart
  Future<void> onResumed() async {
    if (_disposed) return;
    _eventBus.onResumed();
    await _fetch();
  }
```

Replace `close`:

```dart
  @override
  Future<void> close() {
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    unawaited(_eventSub?.cancel());
    _eventSub = null;
    unawaited(_reconnectSub?.cancel());
    _reconnectSub = null;
    return super.close();
  }
```

Note the bus is a lazy singleton shared by every screen, so the cubit must never call `disconnect()`.

- [ ] **Step 2: Rewrite the chrome cubit's transport**

In `chat_cubit.dart`:

Delete the `_configStore`, `_reconnectMin`, `_reconnectMax` fields and their constructor parameters, and add `required ConversationEventBus eventBus` (stored as `_eventBus`) to both the factory and the private constructor. Delete these fields: `_eventCancel`, `_reconnectTimer`, `_reconnectDelay`, `_cursor`. Add:

```dart
  StreamSubscription<void>? _reconnectSub;
```

Replace `_startEvents`, `_openEventStream`, `_scheduleReconnect`, `_stopEvents` and `_cursorKey` with:

```dart
  void _startEvents() {
    if (unavailable != null || snapshot == null) return;
    _streaming = true;
    _eventBus.connect();
    _eventSub ??= _eventBus.eventsFor(sessionId).listen(_onEvent);
    _reconnectSub ??= _eventBus.reconnects.listen((_) => unawaited(refresh()));
  }

  void _onEvent(ConversationEventModel _) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () => unawaited(refresh()));
  }

  void _stopEvents() {
    _streaming = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    unawaited(_eventSub?.cancel());
    _eventSub = null;
    unawaited(_reconnectSub?.cancel());
    _reconnectSub = null;
  }
```

Replace `onResumed`:

```dart
  Future<void> onResumed() async {
    _eventBus.onResumed();
    await refresh();
  }
```

Delete the now-unused imports for `server_config_store.dart`, `cache_helper.dart` and `cdc_cursor.dart`, and remove the `events` method from `ChatRepository` and `ChatRepositoryImp` — the bus is the only caller of the data source now. Delete `CacheKeys.chatEventCursor` from `cache_keys.dart`.

`_startEvents` no longer early-returns on `_streaming`, which is what made a zombie stream unreplaceable (M4); the bus is idempotent, so calling it repeatedly is safe.

- [ ] **Step 3: Rewire dependency injection**

In `service_locator.dart`, replace the `ChatCubit` registration:

```dart
    sl.registerFactoryParam<ChatCubit, String, void>(
      (sessionId, _) => ChatCubit(
        sl<ChatRepository>(),
        sessionId,
        eventBus: sl<ConversationEventBus>(),
      ),
    );
```

and the `ConversationBlocksCubit` registration:

```dart
    sl.registerFactoryParam<ConversationBlocksCubit, String, void>(
      (sessionId, _) => ConversationBlocksCubit(
        sl<ChatRepository>(),
        sl<ConversationEventBus>(),
        sessionId,
      ),
    );
```

- [ ] **Step 4: Update both cubit test files**

In `conversation_blocks_cubit_stream_test.dart`, replace `_MockEventDataSource` with a real bus over a mock data source, so the tests still exercise the transport end to end:

```dart
ConversationBlocksCubit build() => ConversationBlocksCubit(
  repository,
  ConversationEventBus(
    eventSource,
    reconnectMin: const Duration(milliseconds: 10),
    reconnectMax: const Duration(milliseconds: 20),
  ),
  'w-1',
  refreshDebounce: const Duration(milliseconds: 10),
);
```

Add the import for `conversation_event_bus.dart`. All five existing assertions stay valid.

In `chat_cubit_stream_test.dart`, delete the `_MockConfigStore` and its `when(() => configStore.current)` stub, delete the `repository.events` stub, and construct the cubit with `eventBus: ConversationEventBus(eventSource, ...)` over a mock `ChatEventDataSource` built the same way as above.

- [ ] **Step 5: Run the full suite and the analyzer**

Run: `cd packages/mobile && flutter test && flutter analyze`

Expected: all tests PASS, `No issues found!`. Any remaining analyzer error will be an unused import left behind by the deletions above — remove it.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "refactor(chat): move both cubits onto ConversationEventBus

A chat screen opened two SSE connections to the same endpoint and
refetched the same conversation twice per event. Both cubits now share
one connection and own no transport, which is what let the two
lifecycles drift apart in the first place.

Drops the persisted cursor with it: the bus starts at the log head and
subscribers refetch on every reconnect, so a cursor can no longer be
committed before the refresh it triggers, nor outlive a reset log.

Refs H2, H5, M4 in docs/mobile-chat-bugs.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Show the user when updates have stopped (H1)

A frozen timeline and a thinking agent look identical. Desktop has an "events offline" indicator (`frontend/src/renderer/lib/events-connection.ts`); mobile has nothing, which is why this bug class costs a debugging session instead of being self-evident.

**Files:**
- Create: `.../chat_screen/ui/widgets/chat_stream_banner.dart`
- Modify: `.../chat_screen/ui/widgets/chat_body.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_stream_banner_test.dart` (create)

**Interfaces:**
- Consumes: `ConversationEventBus.status`, `EventStreamStatus`.
- Produces: `ChatStreamBanner` — a `StatelessWidget` that renders nothing while connected and a warning row while reconnecting.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_stream_banner_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/events/event_stream_status.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_stream_banner.dart';

void main() {
  late StreamController<EventStreamStatus> status;

  setUp(() => status = StreamController<EventStreamStatus>.broadcast());
  tearDown(() => status.close());

  Widget host() => MaterialApp(
    home: SkinScope(
      skin: const DarkSkin(),
      child: Scaffold(
        body: ChatStreamBanner(
          status: status.stream,
          initial: EventStreamStatus.connected,
        ),
      ),
    ),
  );

  testWidgets('shows nothing while connected', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.textContaining('updates'), findsNothing);
  });

  testWidgets('warns while reconnecting', (tester) async {
    await tester.pumpWidget(host());
    status.add(EventStreamStatus.reconnecting);
    await tester.pump();
    expect(find.text('Not receiving updates — reconnecting'), findsOneWidget);
  });

  testWidgets('clears the warning once reconnected', (tester) async {
    await tester.pumpWidget(host());
    status.add(EventStreamStatus.reconnecting);
    await tester.pump();
    status.add(EventStreamStatus.connected);
    await tester.pump();
    expect(find.textContaining('updates'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/chat/presentation/chat_screen/ui/chat_stream_banner_test.dart`

Expected: FAIL — `chat_stream_banner.dart` does not exist.

- [ ] **Step 3: Create the banner**

Create `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_stream_banner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/events/event_stream_status.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class ChatStreamBanner extends StatelessWidget {
  const ChatStreamBanner({
    super.key,
    required this.status,
    required this.initial,
  });

  final Stream<EventStreamStatus> status;
  final EventStreamStatus initial;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return StreamBuilder<EventStreamStatus>(
      stream: status,
      initialData: initial,
      builder: (context, snapshot) {
        if (snapshot.data != EventStreamStatus.reconnecting) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: skin.bgSubtle,
          child: AppText(
            'Not receiving updates — reconnecting',
            style: AppTextStyle.style11Regular.copyWith(color: skin.amber),
          ),
        );
      },
    );
  }
}
```

`bgSubtle`, `amber` and `style11Regular` are all existing tokens (`lib/core/app_themes/colors/app_skin.dart:43,85` and `lib/core/app_themes/text_style/app_text_style.dart:28`). Do not introduce new ones.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/chat/presentation/chat_screen/ui/chat_stream_banner_test.dart`

Expected: PASS (3 tests).

- [ ] **Step 5: Mount it in the chat screen**

In `chat_body.dart`, add the imports for `chat_stream_banner.dart`, `conversation_event_bus.dart` and `event_stream_status.dart`, then insert the banner directly above the existing block list in the body's `Column`:

```dart
        ChatStreamBanner(
          status: sl<ConversationEventBus>().status,
          initial: sl<ConversationEventBus>().currentStatus,
        ),
```

`sl` is already imported in this file via `core/utils/service_locator.dart`.

- [ ] **Step 6: Run the full suite and the analyzer**

Run: `cd packages/mobile && flutter test && flutter analyze`

Expected: all tests PASS, `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_stream_banner.dart \
        packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart \
        packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_stream_banner_test.dart
git commit -m "feat(chat): tell the user when the timeline stops receiving updates

A frozen timeline and a thinking agent rendered identically, which is why
a dead stream read as a permanent loading state rather than an error.
Desktop has had an events-offline indicator for this; mobile now does too.

Refs H1 in docs/mobile-chat-bugs.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `cd backend && go test ./... && go test -race ./...` — PASS
- [ ] `cd packages/mobile && flutter analyze` — `No issues found!`
- [ ] `cd packages/mobile && flutter test` — PASS
- [ ] `npm run lint` from the repo root — PASS
- [ ] Manual, against a real daemon over Tailscale:
  - Send a prompt that takes 30+ seconds. The response appears without interaction.
  - Background the app mid-turn for 60 seconds, then reopen. The timeline catches up.
  - Kill the daemon mid-turn. The banner reads "Not receiving updates — reconnecting". Restart it; the banner clears and the timeline catches up without leaving the screen.
  - Open two chat sessions and confirm — via the daemon's logs or a proxy — that only one `/api/v1/events` connection exists.

## Out of scope — do not fold in

`H6` (no polling fallback), `M1`/`M2` (null-id collapse in `mergeConversationPages` and `itemKey`), `M3` (lexicographic timestamp ordering), `M6` (the `events` network-guard comment, now moot since Task 8 deletes that method), markdown rendering, and the stale parity-ledger rows. Each is described in `docs/mobile-chat-bugs.md` and belongs to its own change.
