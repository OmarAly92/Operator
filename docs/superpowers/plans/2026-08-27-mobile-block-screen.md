# Mobile Block Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the phone a readable session view that has no terminal grid — a scrolling list of blocks assembled from the daemon's normalized block-event stream — reachable by a toggle beside the existing raw terminal.

**Architecture:** Plan 1 already captures, redacts, persists and live-publishes block events (`ch: "blocks"` on `/mux`). This plan adds the one missing daemon read path (a REST endpoint for the persisted log), teaches the Flutter `MuxClient` the `blocks` channel, adds a `feature/blocks/` package holding the wire model, a pure assembly function, a cubit and the widgets, and makes the existing `TerminalCubit` attach to the PTY **lazily** so that showing Blocks genuinely leaves the terminal channel.

**Tech Stack:** Go 1.x + chi + sqlc (daemon); Flutter 3.44.5, flutter_bloc (Cubit only), equatable, get_it, mocktail, fake_async (mobile).

**Spec:** `docs/superpowers/specs/2026-08-27-session-blocks-design.md` — spec steps 2 (mobile mux), 3 (shared block model and assembly, hook adapter), 4 (mobile block screen and the Raw toggle).

**Depends on:** Plan 1, `docs/superpowers/plans/2026-08-27-block-pipeline-backend.md`, merged at `0a84b7f49`. Everything it produced is on `master` already; do not re-implement any of it.

---

## Global Constraints

Copied from `CLAUDE.md`, `AGENTS.md` and the spec's "Conventions a plan must not violate". Every task's requirements implicitly include this section.

- **No code comments.** `/Users/omaraly/.claude/CLAUDE.md` says "don't make comments". The Go files in this repo comment heavily and you should match *that* file's density when editing Go; first-party Dart in `packages/mobile/lib` is near-comment-free and new Dart must stay that way. Where this plan's Dart snippets carry no comments, that is deliberate — do not add any.
- **Cubit only.** Never `Bloc` with events.
- **No `freezed`, `json_serializable`, `drift` or `build_runner`** in first-party Dart. Models are hand-written with **all fields nullable** and `fromJson` doing the wire→domain mapping.
- **Static-only classes are `sealed class X`.**
- **One params class per method**, under `data/model/params/`, never shared between methods.
- **Parameterized paths get static methods on `EndPoints`.** Interpolating a path at a call site is forbidden.
- **Feature code never imports `flutter_screenutil`.** Spacing, padding and radii take raw ints.
- **User-facing copy is inline English.** There is no `LocaleKeys` catalogue for product copy.
- **Navigation is `Navigator.of(context)` with `RoutesStrings` names.**
- **Theming is `AppSkin` through `context.skin`**; type is `AppTextStyle.style<Size><Weight>` and the parallel `mono*` set. Never hard-code a `Color` or a `TextStyle(fontSize: …)`.
- **Do not "optimize" two documented behaviours:** the 12-second Dio `connectTimeout`/`receiveTimeout` in `dio_consumer.dart`, and the sequential auth probing in `sessions_remote_data_source.dart`.
- **App state resolves under `~/.operator` only.**
- **Never edit `backend/internal/storage/sqlite/gen/` by hand.** This plan touches no queries or migrations, so `npm run sqlc` should not be needed.
- **`AppText` defaults to `maxLines: 1` with ellipsis.** For any block body you must pass `maxLines` explicitly or use a plain `Text` — this is the single most likely way to ship an invisible bug in this plan.
- **Every widget test must wrap its tree in `ScreenUtilInit(designSize: const Size(390, 844), …)`.** `AppTextStyle` resolves its sizes through `flutter_screenutil`'s `.spMin` (`app_text_style.dart:7`), so a widget test that renders any `AppTextStyle` without that wrapper throws. This is the one place `flutter_screenutil` appears — feature code still must never import it, only tests and `core/app_themes/` do. `TerminalHarness.pump` (`terminal_harness.dart:117`) already does it and is the model.

## Verification gates

- **Backend (Task 1 only):** from the repo root, `npm run lint` (runs `go test ./...` plus golangci-lint v2.12.2). During the task, `cd backend && go test ./internal/httpd/controllers/ -run Block -v`. Task 1 changes the REST surface, so it must also run `npm run api` from the repo root, which regenerates `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts`. Commit both regenerated files.
- **Mobile (Tasks 2–7):** from `packages/mobile`, `flutter analyze` must print exactly `No issues found!`, and `flutter test` must be green. CI (`.github/workflows/mobile-flutter.yml`) pins Flutter **3.44.5** and runs exactly those two.
- Single-file / single-test runs during a task: `flutter test test/path/to/file_test.dart`, `flutter test --plain-name 'substring of name'`.
- Native code is covered by neither gate; this plan touches no `ios/`, `android/`, or vendored package platform code.

## Existing test harnesses — use these, do not write a second one

- **HTTP controllers.** Build a server with
  `httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{…}, httpd.ControlDeps{}))`.
  Issue requests with `doRequest`, at `backend/internal/httpd/controllers/projects_test.go:522`, signature
  `(t *testing.T, srv *httptest.Server, method, path, body string) ([]byte, int, http.Header)`.
  Task 1 extends `newBlockEventsTestServer` at `backend/internal/httpd/controllers/sessions_block_events_test.go:34` rather than adding a new server helper.
- **Mux manager (Go).** `newFakeConn()` (no arguments) and `recv(t, c, ch, typ string, d time.Duration) serverMsg`, both in `backend/internal/terminal/manager_test.go`. Drive a connection with `go m.Serve(ctx, conn)` then `conn.in <- clientMsg{…}`. `Serve` reads on its own goroutine, so anything published immediately after a subscribe frame races — **poll `m.blockSubscriberCount(sessionID)` before asserting**, never `sleep`.
- **Mux client (Dart).** `_FakeMuxSocket` and `_StubSource` in `packages/mobile/test/core/mux/mux_client_test.dart`. They are private to that file; Task 2's tests go in that same file so they can reuse them.
- **Mobile terminal.** `packages/mobile/test/feature/terminal/terminal_harness.dart`. Task 7 extends it; it must not be forked.

## The shared fixture contract

`testdata/blocks/` at the **repo root** holds the event-stream fixtures both clients assert against. Plan 1 landed three signal→record fixtures there (`hook_stream_basic.json`, `hook_stream_unknown_event.json`, `hook_stream_secrets.json`) which the Go suite reads. Task 4 of this plan adds four **record→block** fixtures which the Dart suite reads and which plan 3 (desktop) will assert against unchanged.

A failing fixture is **never** fixed by editing the fixture.

From `packages/mobile`, the repo root is `../..`, so a Dart test opens `File('../../testdata/blocks/assembly_turn.json')`.

## Known gaps this plan deliberately does not close

State them in the final report; do not silently expand scope to fix them.

- **Virtualization, height caching, append anchoring under load, sticky headers, block-boundary navigation** are spec step 6 / plan 4. Task 6 here ships a plain `ListView.builder` with a simple pinned-to-bottom rule. That is correct but not fast, which is exactly the ordering the spec asks for: "blocks are correct before they are fast."
- **Block actions (copy, re-run, collapse), selection and find** are plan 6.
- **Shell blocks** are plan 7; a `shellOnly` terminal therefore has no Blocks mode at all in this plan and must default to Raw.
- **Transcript enrichment** is plan 8. `tui` block bodies here are what the hook reported, truncated at 16 KiB by the daemon.
- **The two-client grid-arbitration test is plan 3's.** The spec calls for a test that a desktop in Blocks and a phone in Raw makes the phone the sole sizer. That needs both clients, so it lands with the desktop plan. What this plan pins is the half it owns: a phone in Blocks holds no attachment and reports no size.
- **Permission blocks are rich and notifying, not actionable** (Phase A). No approve/deny control. Acting on one means switching to Raw.
- **`ErrorType` and `HookVersion`** are on the wire model but the daemon never populates them (`ports.ActivitySignal` carries neither). Parse them; render nothing from them.
- **Switching Blocks → Raw → Blocks re-attaches the PTY.** The daemon's own comment at `backend/internal/terminal/manager.go:42` — "the runtime owns the session (screen, scrollback, modes), and every fresh attach gets its full handshake + repaint" — is why this is safe. The Dart `Terminal` object survives the toggle because `TerminalCubit` is not disposed.

---

## File Structure

### Backend (Task 1 only)

| File | Responsibility |
| --- | --- |
| `backend/internal/httpd/controllers/sessions.go` | Add `BlockEventHistory` interface, `BlockHistory` field, `listBlockEvents` handler, one route |
| `backend/internal/httpd/controllers/dto.go` | `ListSessionBlockEventsResponse`, `BlockEventView`, `BlockRedactedSpanView`, `blockEventViews` |
| `backend/internal/httpd/api.go` | `BlockHistory` on `APIDeps`, passed to the controller literal |
| `backend/internal/daemon/daemon.go` | Wire the same `*blockevent.Service` into `BlockHistory` |
| `backend/internal/httpd/apispec/specgen/build.go` | `sessionBlocksQuery` + one operation entry |
| `backend/internal/terminal/protocol.go` | `msgUnsubscribe` constant |
| `backend/internal/terminal/manager.go` | Handle the unsubscribe frame in `handleBlockSubscribe` |
| `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts` | Regenerated by `npm run api` — never hand-edited |

### Mobile

| File | Responsibility |
| --- | --- |
| `lib/core/mux/mux_client.dart` | `blocks` channel: `BlockEventEnvelope`, `blockEvents` stream, subscribe/unsubscribe, resubscribe on reconnect |
| `lib/feature/blocks/data/model/block_event_model.dart` | The wire record, all fields nullable |
| `lib/feature/blocks/data/model/params/get_session_blocks_params.dart` | Query params for the one history call |
| `lib/feature/blocks/data/data_source/blocks_remote_data_source.dart` | The REST call |
| `lib/feature/blocks/data/repository/blocks_repository.dart` | Network guard + `Result` wrapping |
| `lib/feature/blocks/logic/session_block.dart` | `SessionBlock`, `BlockKind`, `BlockStatus` — the shared block model |
| `lib/feature/blocks/logic/block_assembly.dart` | `assembleBlocks`, `resolveStranded` — pure, no Flutter imports |
| `lib/feature/blocks/logic/block_harnesses.dart` | Which harnesses have hook coverage |
| `lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart` + `blocks_state.dart` | Subscribe, history, merge by seq, bounded window, reconnect refetch |
| `lib/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart` + `session_view_state.dart` | Blocks-vs-Raw for one screen |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart` | The list, its states, pinned-to-bottom rule |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart` | One block |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart` | Status colour, shared by card and future callers |
| `lib/core/api/api_request_helpers/end_points.dart` | `sessionBlocks(String)` |
| `lib/core/utils/service_locator.dart` | `_blocksFeatureSetup()` |
| `lib/core/app_routes/app_router.dart` | Provide `SessionViewCubit` and `BlocksCubit` on the terminal route |
| `lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart` | Lazy `attach()`/`detach()` |
| `lib/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart` | The toggle; branch on view mode |
| `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart` | Becomes stateful so it can attach/detach |

### Fixtures (Task 4)

`testdata/blocks/assembly_turn.json`, `assembly_permission.json`, `assembly_out_of_order.json`, `assembly_truncation.json`.

---

## Task 1: Block-event history endpoint and a mux unsubscribe frame

**Why:** `blockevent.Service.History` exists (`backend/internal/service/blockevent/service.go:106`) but nothing HTTP calls it, so a phone that joins mid-session or drops its socket sees only what arrives next. The spec requires "a dropped socket refetches the persisted log by sequence." The unsubscribe frame is folded in here because plan 1's protocol has subscribe with no counterpart, which would leave the daemon pushing every session a phone ever opened down that socket forever.

**Files:**
- Modify: `backend/internal/httpd/controllers/sessions.go` (interface block near :120, `SessionsController` fields near :150, `Register` near :184, new handler beside `listAgentSwitches` at :1089)
- Modify: `backend/internal/httpd/controllers/dto.go` (beside `ListAgentSwitchesResponse` at :248)
- Modify: `backend/internal/httpd/api.go:35` and `:100`
- Modify: `backend/internal/daemon/daemon.go:413`
- Modify: `backend/internal/httpd/apispec/specgen/build.go` (near the `interface-transition` entries at :1644)
- Modify: `backend/internal/terminal/protocol.go:35`, `backend/internal/terminal/manager.go:539`
- Test: `backend/internal/httpd/controllers/sessions_block_events_test.go`, `backend/internal/terminal/manager_test.go`
- Regenerated: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`

**Interfaces:**
- Consumes: `blockeventsvc.Record` (`backend/internal/service/blockevent/types.go:18`), `redact.Span` (`backend/internal/redact/redact.go:20`), `(*blockevent.Service).History(ctx, domain.SessionID, afterSeq int64, limit int) ([]Record, error)`.
- Produces, for Task 3: `GET /api/v1/sessions/{sessionId}/blocks?afterSeq=<int64>&limit=<int>` returning `200 {"blocks":[BlockEventView…]}` ascending by `seq`; `404` with code `SESSION_NOT_FOUND` is **not** produced (the log is keyed by id alone and an unknown id returns an empty list); `501` when `BlockHistory` is nil. `BlockEventView` JSON keys are exactly: `seq`, `sessionId`, `sourceId`, `kind`, `rawEvent`, `harness`, `toolName`, `toolUseId`, `text`, `redactedSpans` (`[{start,end}]`), `errorType`, `hookVersion`, `truncatedLines`, `createdAt` (RFC3339).
- Produces, for Task 2: client frame `{"ch":"blocks","id":"<sessionId>","type":"unsubscribe"}` removes that subscription.

- [ ] **Step 1: Write the failing controller test**

Append to `backend/internal/httpd/controllers/sessions_block_events_test.go`:

```go
type fakeBlockEventHistory struct {
	recs       []blockeventsvc.Record
	err        error
	gotSession domain.SessionID
	gotAfter   int64
	gotLimit   int
}

func (f *fakeBlockEventHistory) History(_ context.Context, id domain.SessionID, afterSeq int64, limit int) ([]blockeventsvc.Record, error) {
	f.gotSession = id
	f.gotAfter = afterSeq
	f.gotLimit = limit
	return f.recs, f.err
}

func newBlockHistoryTestServer(t *testing.T, hist *fakeBlockEventHistory) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	deps := httpd.APIDeps{
		Activity:   noopActivityRecorder{},
		UsageHooks: noopUsageHookRecorder{},
	}
	if hist != nil {
		deps.BlockHistory = hist
	}
	srv := httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, deps, httpd.ControlDeps{}))
	t.Cleanup(srv.Close)
	return srv
}

func TestListBlockEventsReturnsPersistedLog(t *testing.T) {
	created := time.Date(2026, 8, 27, 10, 0, 0, 0, time.UTC)
	hist := &fakeBlockEventHistory{recs: []blockeventsvc.Record{{
		Seq:            7,
		SessionID:      "s-1",
		SourceID:       "tu-1",
		Kind:           domain.BlockEventToolComplete,
		Harness:        "claude-code",
		ToolName:       "Bash",
		ToolUseID:      "tu-1",
		Text:           "token=[redacted]",
		RedactedSpans:  []redact.Span{{Start: 6, End: 16}},
		TruncatedLines: 3,
		CreatedAt:      created,
	}}}
	srv := newBlockHistoryTestServer(t, hist)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks?afterSeq=4&limit=50", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", status, body)
	}
	var got controllers.ListSessionBlockEventsResponse
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got.Blocks) != 1 {
		t.Fatalf("blocks = %d, want 1", len(got.Blocks))
	}
	b := got.Blocks[0]
	if b.Seq != 7 || b.Kind != string(domain.BlockEventToolComplete) || b.ToolUseID != "tu-1" {
		t.Errorf("view = %+v, want seq 7 / tool_complete / tu-1", b)
	}
	if b.TruncatedLines != 3 {
		t.Errorf("truncatedLines = %d, want 3 — the drop count must survive the view", b.TruncatedLines)
	}
	if len(b.RedactedSpans) != 1 || b.RedactedSpans[0].Start != 6 || b.RedactedSpans[0].End != 16 {
		t.Errorf("redactedSpans = %+v, want [{6 16}]", b.RedactedSpans)
	}
	if hist.gotSession != "s-1" || hist.gotAfter != 4 || hist.gotLimit != 50 {
		t.Errorf("history args = (%q, %d, %d), want (s-1, 4, 50)", hist.gotSession, hist.gotAfter, hist.gotLimit)
	}
}

func TestListBlockEventsDefaultsCursorAndLimit(t *testing.T) {
	hist := &fakeBlockEventHistory{}
	srv := newBlockHistoryTestServer(t, hist)

	_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if hist.gotAfter != 0 || hist.gotLimit != 0 {
		t.Errorf("defaults = (%d, %d), want (0, 0) so the service picks its own bound", hist.gotAfter, hist.gotLimit)
	}
}

func TestListBlockEventsRejectsBadQuery(t *testing.T) {
	srv := newBlockHistoryTestServer(t, &fakeBlockEventHistory{})

	for _, q := range []string{"?afterSeq=abc", "?limit=abc", "?afterSeq=-1", "?limit=0", "?limit=100000"} {
		_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks"+q, "")
		if status != http.StatusBadRequest {
			t.Errorf("%s: status = %d, want 400", q, status)
		}
	}
}

func TestListBlockEventsWithoutServiceIsNotImplemented(t *testing.T) {
	srv := newBlockHistoryTestServer(t, nil)

	_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks", "")
	if status != http.StatusNotImplemented {
		t.Errorf("status = %d, want 501", status)
	}
}

func TestListBlockEventsSurfacesServiceFailure(t *testing.T) {
	srv := newBlockHistoryTestServer(t, &fakeBlockEventHistory{err: context.DeadlineExceeded})

	_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks", "")
	if status < 500 {
		t.Errorf("status = %d, want a 5xx", status)
	}
}
```

Add whatever of `encoding/json`, `net/http`, `time`, `github.com/OmarAly92/operator/backend/internal/httpd/controllers`, `github.com/OmarAly92/operator/backend/internal/redact`, and `blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"` the file does not already import.

- [ ] **Step 2: Run it and watch it fail**

```bash
cd backend && go test ./internal/httpd/controllers/ -run TestListBlockEvents -v
```

Expected: compile failure — `deps.BlockHistory` undefined, `controllers.ListSessionBlockEventsResponse` undefined.

- [ ] **Step 3: Add the DTOs**

In `backend/internal/httpd/controllers/dto.go`, immediately after `ListAgentSwitchesResponse` (:250-252):

```go
// BlockRedactedSpanView marks where a secret was masked in BlockEventView.Text.
// Offsets index the masked text, not the original, so a client can highlight the
// mask without ever having seen what it replaced.
type BlockRedactedSpanView struct {
	Start int `json:"start"`
	End   int `json:"end"`
}

// BlockEventView is one normalized, redacted block event as served to clients.
// It mirrors blockevent.Record deliberately rather than aliasing it: the wire
// shape is part of the API contract and must not drift when the service's
// internal record gains a field.
type BlockEventView struct {
	Seq            int64                   `json:"seq"`
	SessionID      string                  `json:"sessionId"`
	SourceID       string                  `json:"sourceId,omitempty"`
	Kind           string                  `json:"kind"`
	RawEvent       string                  `json:"rawEvent,omitempty"`
	Harness        string                  `json:"harness,omitempty"`
	ToolName       string                  `json:"toolName,omitempty"`
	ToolUseID      string                  `json:"toolUseId,omitempty"`
	Text           string                  `json:"text,omitempty"`
	RedactedSpans  []BlockRedactedSpanView `json:"redactedSpans,omitempty"`
	ErrorType      string                  `json:"errorType,omitempty"`
	HookVersion    string                  `json:"hookVersion,omitempty"`
	TruncatedLines int                     `json:"truncatedLines,omitempty"`
	CreatedAt      time.Time               `json:"createdAt"`
}

// ListSessionBlockEventsResponse is the body of
// GET /api/v1/sessions/{sessionId}/blocks.
type ListSessionBlockEventsResponse struct {
	Blocks []BlockEventView `json:"blocks"`
}

func blockEventViews(recs []blockeventsvc.Record) []BlockEventView {
	views := make([]BlockEventView, 0, len(recs))
	for _, rec := range recs {
		spans := make([]BlockRedactedSpanView, 0, len(rec.RedactedSpans))
		for _, s := range rec.RedactedSpans {
			spans = append(spans, BlockRedactedSpanView{Start: s.Start, End: s.End})
		}
		if len(spans) == 0 {
			spans = nil
		}
		views = append(views, BlockEventView{
			Seq:            rec.Seq,
			SessionID:      rec.SessionID,
			SourceID:       rec.SourceID,
			Kind:           string(rec.Kind),
			RawEvent:       rec.RawEvent,
			Harness:        rec.Harness,
			ToolName:       rec.ToolName,
			ToolUseID:      rec.ToolUseID,
			Text:           rec.Text,
			RedactedSpans:  spans,
			ErrorType:      rec.ErrorType,
			HookVersion:    rec.HookVersion,
			TruncatedLines: rec.TruncatedLines,
			CreatedAt:      rec.CreatedAt,
		})
	}
	return views
}
```

Add `blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"` and `"time"` to `dto.go`'s imports if absent.

- [ ] **Step 4: Add the controller interface, field, route and handler**

In `backend/internal/httpd/controllers/sessions.go`, immediately after the `BlockEventRecorder` interface (:123-125):

```go
// BlockEventHistory reads a session's persisted block-event log. It is separate
// from BlockEventRecorder so a build that records without serving history — or a
// test fake that only needs one half — stays valid.
type BlockEventHistory interface {
	History(ctx context.Context, sessionID domain.SessionID, afterSeq int64, limit int) ([]blockeventsvc.Record, error)
}
```

Add the field to the `SessionsController` struct, beside `BlockEvents` (:152):

```go
	BlockHistory  BlockEventHistory
```

Add the route in `Register`, immediately after the `agent-switches` lines (:183):

```go
	r.Get("/sessions/{sessionId}/blocks", c.listBlockEvents)
```

Add the handler immediately after `listAgentSwitches` (ends :1100):

```go
// maxBlockEventPage bounds one history page. It matches the daemon's per-session
// retention (blockevent.NewService(store, termMgr, 500) in daemon.go) so a
// client can ask for everything that exists in one call and no more.
const maxBlockEventPage = 500

func (c *SessionsController) listBlockEvents(w http.ResponseWriter, r *http.Request) {
	if c.BlockHistory == nil {
		apispec.NotImplemented(w, r, "GET", "/api/v1/sessions/{sessionId}/blocks")
		return
	}
	afterSeq, err := parseNonNegativeQuery(r, "afterSeq")
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_QUERY", err.Error(), nil)
		return
	}
	limit, err := parseNonNegativeQuery(r, "limit")
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_QUERY", err.Error(), nil)
		return
	}
	if r.URL.Query().Has("limit") && (limit < 1 || limit > maxBlockEventPage) {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_QUERY", "limit must be between 1 and 500", nil)
		return
	}
	recs, err := c.BlockHistory.History(r.Context(), sessionID(r), afterSeq, int(limit))
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ListSessionBlockEventsResponse{Blocks: blockEventViews(recs)})
}

func parseNonNegativeQuery(r *http.Request, key string) (int64, error) {
	raw := strings.TrimSpace(r.URL.Query().Get(key))
	if raw == "" {
		return 0, nil
	}
	n, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || n < 0 {
		return 0, fmt.Errorf("%s must be a non-negative integer", key)
	}
	return n, nil
}
```

`strconv`, `strings`, `fmt`, `net/http` are already imported by `sessions.go` (see :14-22). Add `blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"` if absent.

- [ ] **Step 5: Wire the dependency**

`backend/internal/httpd/api.go` — add to `APIDeps` beside `BlockEvents` (:35):

```go
	// BlockHistory serves the persisted block-event log. Nil answers 501 rather
	// than an empty list, so a client can tell "no blocks yet" from "this daemon
	// cannot serve them".
	BlockHistory       controllers.BlockEventHistory
```

and to the controller literal beside `BlockEvents: deps.BlockEvents,` (:100):

```go
			BlockHistory:  deps.BlockHistory,
```

`backend/internal/daemon/daemon.go` — beside `BlockEvents: blockEvents,` (:413):

```go
		BlockHistory:       blockEvents,
```

`blockEvents` is the `*blockevent.Service` built at `daemon.go:145`; it already has both `Record` and `History`, so one value satisfies both interfaces.

- [ ] **Step 6: Run the controller tests**

```bash
cd backend && go test ./internal/httpd/controllers/ -run TestListBlockEvents -v
```

Expected: all five PASS.

- [ ] **Step 7: Run the route/spec parity test and watch it fail**

```bash
cd backend && go test ./internal/httpd/apispec/ -run TestRouteSpecParity -v
```

Expected: FAIL — `mounted route GET /api/v1/sessions/{sessionId}/blocks has no OpenAPI operation`. `TestRouteSpecParity` (`backend/internal/httpd/apispec/parity_test.go:22`) asserts mounted routes and spec operations are 1:1, which is why the spec entry is not optional.

- [ ] **Step 8: Declare the operation**

In `backend/internal/httpd/apispec/specgen/build.go`, add the query container next to the existing `conversationSnapshotQuery` (:490) — an unexported local struct needs no entry in the `typeNameOverrides` map, exactly as `conversationSnapshotQuery` and `eventsQuery` (:1197) do not:

```go
type sessionBlocksQuery struct {
	AfterSeq *int64 `query:"afterSeq,omitempty" minimum:"0" description:"Return events with seq greater than this cursor. Omit to read from the start of the retained log."`
	Limit    *int64 `query:"limit,omitempty" minimum:"1" maximum:"500" description:"Maximum events to return. Defaults to the daemon's per-session retention."`
}
```

and the operation entry immediately after the `cancelSessionInterfaceTransition` entry (ends :1680):

```go
		{
			method: http.MethodGet, path: "/api/v1/sessions/{sessionId}/blocks", id: "listSessionBlockEvents", tag: "sessions",
			summary:    "Read a session's retained, redacted block-event log",
			pathParams: []any{controllers.SessionIDParam{}, sessionBlocksQuery{}},
			resps: []respUnit{
				{http.StatusOK, controllers.ListSessionBlockEventsResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
				{http.StatusNotImplemented, envelope.APIError{}},
			},
		},
```

- [ ] **Step 9: Regenerate the spec and the frontend types**

```bash
npm run api
```

Run it from the repo root. It regenerates `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts`. **Predicted disagreement:** the generator names schemas from the Go type, so expect `ControllersListSessionBlockEventsResponse` → `ListSessionBlockEventsResponse`, `ControllersBlockEventView` → `BlockEventView` and `ControllersBlockRedactedSpanView` → `BlockRedactedSpanView` to appear in the generated YAML. If generation errors with an ambiguous or colliding schema name, add the mapping to the `typeNameOverrides` map at `build.go:212` in the same style as its neighbours; do not rename the Go type.

- [ ] **Step 10: Re-run parity**

```bash
cd backend && go test ./internal/httpd/apispec/ -v
```

Expected: PASS.

- [ ] **Step 11: Write the failing mux unsubscribe test**

The block-channel tests live in `backend/internal/terminal/blocks_test.go`, **not** `manager_test.go`. That file already has the poll helper this test needs — `waitForBlockSubscriber(t, m, id)` at `blocks_test.go:96`, which waits for **at least one** subscriber. Unsubscribe needs the opposite wait, so add a sibling helper; do not change the existing one.

Append to `backend/internal/terminal/blocks_test.go`:

```go
func TestBlockUnsubscribeStopsDelivery(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "s-1"}
	waitForBlockSubscriber(t, m, "s-1")

	m.PublishBlockEvent("s-1", blockeventsvc.Record{Seq: 1, SessionID: "s-1"})
	if msg := recv(t, conn, chBlocks, msgBlock, 2*time.Second); msg.Block == nil || msg.Block.Seq != 1 {
		t.Fatalf("first block = %+v, want seq 1", msg.Block)
	}

	conn.in <- clientMsg{Ch: chBlocks, Type: msgUnsubscribe, ID: "s-1"}
	waitForNoBlockSubscriber(t, m, "s-1")

	m.PublishBlockEvent("s-1", blockeventsvc.Record{Seq: 2, SessionID: "s-1"})

	select {
	case got := <-conn.out:
		if got.Ch == chBlocks {
			t.Fatalf("received %+v after unsubscribe, want nothing", got)
		}
	case <-time.After(200 * time.Millisecond):
	}
}

func TestBlockUnsubscribeBeforeSubscribeIsHarmless(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chBlocks, Type: msgUnsubscribe, ID: "s-1"}
	conn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "s-1"}
	waitForBlockSubscriber(t, m, "s-1")

	m.PublishBlockEvent("s-1", blockeventsvc.Record{Seq: 1, SessionID: "s-1"})
	if msg := recv(t, conn, chBlocks, msgBlock, 2*time.Second); msg.Block == nil {
		t.Fatal("subscribe after a stray unsubscribe delivered nothing")
	}
}

func waitForNoBlockSubscriber(t *testing.T, m *Manager, id string) {
	t.Helper()
	deadline := time.After(2 * time.Second)
	for {
		if m.blockSubscriberCount(id) == 0 {
			return
		}
		select {
		case <-deadline:
			t.Fatalf("block subscriber for %q never went away", id)
		case <-time.After(5 * time.Millisecond):
		}
	}
}
```

`fakeSource` and `fakeSpawner` are in `backend/internal/terminal/fakes_test.go`; `newFakeConn` and `recv` are in `manager_test.go` at :25 and :57. Every import this needs is already at the top of `blocks_test.go`.

- [ ] **Step 12: Run it and watch it fail**

```bash
cd backend && go test ./internal/terminal/ -run TestBlockUnsubscribe -race -v
```

Expected: compile failure — `msgUnsubscribe` is undefined. Once the constant exists but the handler does not, the failure moves to the final `select`: the unsubscribe frame is ignored, so seq 2 is still delivered.

- [ ] **Step 13: Implement unsubscribe**

`backend/internal/terminal/protocol.go`, in the client-message block (:28-35):

```go
	msgUnsubscribe = "unsubscribe" // ch "blocks"
```

`backend/internal/terminal/manager.go`, replace `handleBlockSubscribe` (:539-549) with:

```go
func (c *connState) handleBlockSubscribe(msg clientMsg) {
	if msg.ID == "" {
		return
	}
	switch msg.Type {
	case msgSubscribe:
		c.mu.Lock()
		if c.blockSubs == nil {
			c.blockSubs = map[string]struct{}{}
		}
		c.blockSubs[msg.ID] = struct{}{}
		c.mu.Unlock()
	case msgUnsubscribe:
		c.mu.Lock()
		delete(c.blockSubs, msg.ID)
		c.mu.Unlock()
	}
}
```

`delete` on a nil map is a no-op, so the unsubscribe-before-subscribe case needs no guard.

- [ ] **Step 14: Run the terminal tests under -race**

```bash
cd backend && go test ./internal/terminal/ -race -count=1
```

Expected: `ok`. Run the whole package, not just the new test — `PublishBlockEvent` and `blockSubscriberCount` both walk `m.conns` and the existing suite is what proves the locking still holds.

- [ ] **Step 15: Full backend gate**

```bash
npm run lint
```

From the repo root. Expected: 0 issues, all Go tests green.

- [ ] **Step 16: Commit**

```bash
git add backend/internal/httpd backend/internal/terminal backend/internal/daemon frontend/src/api/schema.ts
git commit -m "feat(backend): serve the block-event log and accept a blocks unsubscribe"
```

---

## Task 2: The `blocks` channel in the Flutter mux client

**Why:** `MuxClient` (`packages/mobile/lib/core/mux/mux_client.dart`) knows `sessions`, `terminal`, `subscribe` and `system`. It drops `ch: "blocks"` frames on the floor at `_onMessage` (:154-186) because nothing matches. `MuxClient` lives in `core/mux/`, not under a feature, deliberately — see `CLAUDE.md`: the Kanban board depends on the same socket, so nesting it under a feature would make the board's liveness depend on a feature it has no business knowing about. Keep it there.

**Files:**
- Modify: `packages/mobile/lib/core/mux/mux_client.dart`
- Test: `packages/mobile/test/core/mux/mux_client_test.dart`

**Interfaces:**
- Consumes: the daemon frame `{"ch":"blocks","id":"<sessionId>","type":"block","block":{…}}` from Task 1's plan-1 predecessor, and Task 1's `{"ch":"blocks","id":"…","type":"unsubscribe"}`.
- Produces, for Task 5:
  - `Stream<BlockEventEnvelope> get blockEvents` on `MuxClient`
  - `final class BlockEventEnvelope extends Equatable { const BlockEventEnvelope(this.sessionId, this.block); final String sessionId; final Map<String, dynamic> block; }`
  - `void subscribeBlocks(String sessionId)`
  - `void unsubscribeBlocks(String sessionId)`

**Design note the implementer must not "improve":** `blockEvents` carries the **raw decoded JSON map**, not a typed model. `core/` must not import `feature/`, and `BlockEventModel` lives in `feature/blocks/` (Task 3). The cubit does the parse. This mirrors how `sessionPatches` is the one exception — `SessionPatch` lives in `core/mux/` because it is the socket's own shape — and blocks are not.

- [ ] **Step 1: Write the failing tests**

Append these to the `group('MuxClient', …)` in `packages/mobile/test/core/mux/mux_client_test.dart`. They reuse `_FakeMuxSocket` and `_StubSource` already in that file (:12 and :62).

```dart
    test('subscribes to a session\'s blocks and surfaces its events', () {
      fakeAsync((async) {
        late _FakeMuxSocket socket;
        final client = MuxClient(_source, connect: (_, _) => socket = _FakeMuxSocket());
        client.connect();
        async.flushMicrotasks();

        final seen = <BlockEventEnvelope>[];
        client.blockEvents.listen(seen.add);
        client.subscribeBlocks('s-1');
        async.flushMicrotasks();

        expect(
          socket.sent.map((raw) => jsonDecode(raw)),
          contains({'ch': 'blocks', 'id': 's-1', 'type': 'subscribe'}),
        );

        socket.pushMessage({
          'ch': 'blocks',
          'id': 's-1',
          'type': 'block',
          'block': {'seq': 7, 'sessionId': 's-1', 'kind': 'tool_complete', 'toolName': 'Bash'},
        });
        async.flushMicrotasks();

        expect(seen, hasLength(1));
        expect(seen.single.sessionId, 's-1');
        expect(seen.single.block['seq'], 7);
        expect(seen.single.block['toolName'], 'Bash');
        client.disconnect();
      });
    });

    test('re-subscribes every block session after a reconnect', () {
      fakeAsync((async) {
        final sockets = <_FakeMuxSocket>[];
        final client = MuxClient(_source, connect: (_, _) {
          final socket = _FakeMuxSocket();
          sockets.add(socket);
          return socket;
        });
        client.connect();
        async.flushMicrotasks();

        client.subscribeBlocks('s-1');
        client.subscribeBlocks('s-2');
        async.flushMicrotasks();

        sockets.first.closeFromServer();
        async.elapse(const Duration(milliseconds: MuxBackoff.initialMs));
        async.flushMicrotasks();

        final resent = sockets.last.sent.map((raw) => jsonDecode(raw)).toList();
        expect(resent, contains({'ch': 'blocks', 'id': 's-1', 'type': 'subscribe'}));
        expect(resent, contains({'ch': 'blocks', 'id': 's-2', 'type': 'subscribe'}));
        client.disconnect();
      });
    });

    test('unsubscribing tells the daemon and survives a reconnect', () {
      fakeAsync((async) {
        final sockets = <_FakeMuxSocket>[];
        final client = MuxClient(_source, connect: (_, _) {
          final socket = _FakeMuxSocket();
          sockets.add(socket);
          return socket;
        });
        client.connect();
        async.flushMicrotasks();

        client.subscribeBlocks('s-1');
        client.unsubscribeBlocks('s-1');
        async.flushMicrotasks();

        expect(
          sockets.first.sent.map((raw) => jsonDecode(raw)),
          contains({'ch': 'blocks', 'id': 's-1', 'type': 'unsubscribe'}),
        );

        sockets.first.closeFromServer();
        async.elapse(const Duration(milliseconds: MuxBackoff.initialMs));
        async.flushMicrotasks();

        final resent = sockets.last.sent.map((raw) => jsonDecode(raw)).toList();
        expect(
          resent.any((frame) => frame is Map && frame['ch'] == 'blocks'),
          isFalse,
          reason: 'an unsubscribed session must not come back on reconnect',
        );
        client.disconnect();
      });
    });

    test('ignores a blocks frame with no payload', () {
      fakeAsync((async) {
        late _FakeMuxSocket socket;
        final client = MuxClient(_source, connect: (_, _) => socket = _FakeMuxSocket());
        client.connect();
        async.flushMicrotasks();

        final seen = <BlockEventEnvelope>[];
        client.blockEvents.listen(seen.add);
        client.subscribeBlocks('s-1');
        socket.pushMessage({'ch': 'blocks', 'id': 's-1', 'type': 'block'});
        socket.pushMessage({'ch': 'blocks', 'id': 's-1', 'type': 'block', 'block': 'not-a-map'});
        async.flushMicrotasks();

        expect(seen, isEmpty);
        client.disconnect();
      });
    });
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd packages/mobile && flutter test test/core/mux/mux_client_test.dart
```

Expected: compile failure — `BlockEventEnvelope`, `blockEvents`, `subscribeBlocks`, `unsubscribeBlocks` are undefined.

- [ ] **Step 3: Implement the channel**

In `packages/mobile/lib/core/mux/mux_client.dart`, add the envelope after the `TerminalResizeEvent` class (ends :51):

```dart
final class BlockEventEnvelope extends Equatable {
  const BlockEventEnvelope(this.sessionId, this.block);

  final String sessionId;
  final Map<String, dynamic> block;

  @override
  List<Object?> get props => [sessionId, block];
}
```

Add the controller and getter beside `_terminalEventsController` (:65) and `terminalEvents` (:69):

```dart
  final _blockEventsController = StreamController<BlockEventEnvelope>.broadcast();
```

```dart
  Stream<BlockEventEnvelope> get blockEvents => _blockEventsController.stream;
```

Add the subscription set beside `_openTerminals` (:78):

```dart
  final Set<String> _blockSessions = {};
```

In `_open()`, immediately after the `for (final entry in _openTerminals.entries)` loop (:138-140) and before the ping timer (:142):

```dart
    for (final sessionId in _blockSessions) {
      _send({'ch': 'blocks', 'id': sessionId, 'type': 'subscribe'});
    }
```

In `_onMessage`, after the `if (ch == 'terminal')` block (ends :185):

```dart
    if (ch == 'blocks' && type == 'block') {
      final block = msg['block'];
      if (block is Map<String, dynamic>) {
        _blockEventsController.add(BlockEventEnvelope(msg['id'] as String? ?? '', block));
      }
    }
```

Add the two methods beside `closeTerminal` (:229-232):

```dart
  void subscribeBlocks(String sessionId) {
    _blockSessions.add(sessionId);
    _send({'ch': 'blocks', 'id': sessionId, 'type': 'subscribe'});
  }

  void unsubscribeBlocks(String sessionId) {
    _blockSessions.remove(sessionId);
    _send({'ch': 'blocks', 'id': sessionId, 'type': 'unsubscribe'});
  }
```

- [ ] **Step 4: Run the tests**

```bash
cd packages/mobile && flutter test test/core/mux/mux_client_test.dart
```

Expected: PASS, including the pre-existing tests in that file.

- [ ] **Step 5: Gate**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: `No issues found!` and a green suite.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib/core/mux/mux_client.dart packages/mobile/test/core/mux/mux_client_test.dart
git commit -m "feat(mobile): carry the mux blocks channel"
```

---

## Task 3: Blocks data layer — model, params, data source, repository

**Why:** The cubit needs the persisted log over REST and a typed record for both the REST body and the socket payload. One model serves both, because Task 1's `BlockEventView` and `blockevent.Record`'s JSON tags are the same shape by construction.

**Files:**
- Create: `packages/mobile/lib/feature/blocks/data/model/block_event_model.dart`
- Create: `packages/mobile/lib/feature/blocks/data/model/params/get_session_blocks_params.dart`
- Create: `packages/mobile/lib/feature/blocks/data/data_source/blocks_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/blocks/data/repository/blocks_repository.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Test: `packages/mobile/test/feature/blocks/data/block_event_model_test.dart`
- Test: `packages/mobile/test/feature/blocks/data/blocks_repository_test.dart`

**Interfaces:**
- Consumes: Task 1's `GET /api/v1/sessions/{sessionId}/blocks`; `ApiConsumer` (`lib/core/api/api_request_helpers/api_consumer.dart:6`); `GlobalResponse` (`lib/core/api/models/global_response.dart:17`); `Result`/`FutureResult` (`lib/core/helpers/result/result.dart:3`); `NetworkStatus`.
- Produces, for Tasks 4 and 5:
  - `BlockEventModel` with nullable fields `seq, sessionId, sourceId, kind, rawEvent, harness, toolName, toolUseId, text, redactedSpans, errorType, hookVersion, truncatedLines, createdAt` (`createdAt` is `String?`, kept raw exactly as `ShellTerminalModel.createdAt` does at `shell_terminal_model.dart:16`), plus `BlockEventModel.fromJson(Map<String, dynamic>)` and `static List<BlockEventModel> listFromJson(Map<String, dynamic>)`.
  - `BlockRedactedSpanModel` with `int? start, int? end`.
  - `GetSessionBlocksParams({int? afterSeq, int? limit})` with `Map<String, dynamic> toJson()` that **omits null keys**.
  - `abstract class BlocksRepository { FutureResult<List<BlockEventModel>> getSessionBlocks(String sessionId, GetSessionBlocksParams params); }`

**Convention reminders for this task:** every field nullable, hand-written `fromJson`, `Equatable`, one params class for the one method, and the endpoint as a static method on `EndPoints` — never interpolated at the call site.

- [ ] **Step 1: Write the failing model test**

Create `packages/mobile/test/feature/blocks/data/block_event_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';

void main() {
  test('parses a full record', () {
    final model = BlockEventModel.fromJson(const {
      'seq': 7,
      'sessionId': 's-1',
      'sourceId': 'tu-1',
      'kind': 'tool_complete',
      'harness': 'claude-code',
      'toolName': 'Bash',
      'toolUseId': 'tu-1',
      'text': 'token=[redacted]',
      'redactedSpans': [
        {'start': 6, 'end': 16},
      ],
      'truncatedLines': 3,
      'createdAt': '2026-08-27T10:00:00Z',
    });

    expect(model.seq, 7);
    expect(model.kind, 'tool_complete');
    expect(model.toolUseId, 'tu-1');
    expect(model.truncatedLines, 3);
    expect(model.redactedSpans, hasLength(1));
    expect(model.redactedSpans!.single.start, 6);
    expect(model.redactedSpans!.single.end, 16);
    expect(model.createdAt, '2026-08-27T10:00:00Z');
  });

  test('parses a record whose optional fields are all absent', () {
    final model = BlockEventModel.fromJson(const {'seq': 1, 'kind': 'stop'});

    expect(model.seq, 1);
    expect(model.kind, 'stop');
    expect(model.toolName, isNull);
    expect(model.redactedSpans, isNull);
    expect(model.truncatedLines, isNull);
  });

  test('carries an unknown kind through with its raw event name', () {
    final model = BlockEventModel.fromJson(const {
      'seq': 2,
      'kind': 'unknown',
      'rawEvent': 'some-future-hook',
    });

    expect(model.kind, 'unknown');
    expect(model.rawEvent, 'some-future-hook');
  });

  test('reads the blocks envelope', () {
    final models = BlockEventModel.listFromJson(const {
      'blocks': [
        {'seq': 1, 'kind': 'prompt_submit'},
        {'seq': 2, 'kind': 'stop'},
      ],
    });

    expect(models.map((m) => m.seq), [1, 2]);
  });

  test('an absent blocks envelope is an empty list, not a crash', () {
    expect(BlockEventModel.listFromJson(const {}), isEmpty);
  });

  test('params omit the keys the caller did not set', () {
    expect(const GetSessionBlocksParams().toJson(), isEmpty);
    expect(const GetSessionBlocksParams(afterSeq: 4).toJson(), {'afterSeq': 4});
    expect(
      const GetSessionBlocksParams(afterSeq: 4, limit: 50).toJson(),
      {'afterSeq': 4, 'limit': 50},
    );
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd packages/mobile && flutter test test/feature/blocks/data/block_event_model_test.dart
```

Expected: compile failure — the files do not exist.

- [ ] **Step 3: Write the model and params**

`packages/mobile/lib/feature/blocks/data/model/block_event_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class BlockRedactedSpanModel extends Equatable {
  final int? start;
  final int? end;

  const BlockRedactedSpanModel({this.start, this.end});

  factory BlockRedactedSpanModel.fromJson(Map<String, dynamic> json) => BlockRedactedSpanModel(
    start: (json['start'] as num?)?.toInt(),
    end: (json['end'] as num?)?.toInt(),
  );

  @override
  List<Object?> get props => [start, end];
}

class BlockEventModel extends Equatable {
  final int? seq;
  final String? sessionId;
  final String? sourceId;
  final String? kind;
  final String? rawEvent;
  final String? harness;
  final String? toolName;
  final String? toolUseId;
  final String? text;
  final List<BlockRedactedSpanModel>? redactedSpans;
  final String? errorType;
  final String? hookVersion;
  final int? truncatedLines;
  final String? createdAt;

  const BlockEventModel({
    this.seq,
    this.sessionId,
    this.sourceId,
    this.kind,
    this.rawEvent,
    this.harness,
    this.toolName,
    this.toolUseId,
    this.text,
    this.redactedSpans,
    this.errorType,
    this.hookVersion,
    this.truncatedLines,
    this.createdAt,
  });

  factory BlockEventModel.fromJson(Map<String, dynamic> json) {
    final spans = json['redactedSpans'] as List<dynamic>?;
    return BlockEventModel(
      seq: (json['seq'] as num?)?.toInt(),
      sessionId: json['sessionId'] as String?,
      sourceId: json['sourceId'] as String?,
      kind: json['kind'] as String?,
      rawEvent: json['rawEvent'] as String?,
      harness: json['harness'] as String?,
      toolName: json['toolName'] as String?,
      toolUseId: json['toolUseId'] as String?,
      text: json['text'] as String?,
      redactedSpans: spans
          ?.map((span) => BlockRedactedSpanModel.fromJson(span as Map<String, dynamic>))
          .toList(),
      errorType: json['errorType'] as String?,
      hookVersion: json['hookVersion'] as String?,
      truncatedLines: (json['truncatedLines'] as num?)?.toInt(),
      createdAt: json['createdAt'] as String?,
    );
  }

  static List<BlockEventModel> listFromJson(Map<String, dynamic> json) =>
      (json['blocks'] as List<dynamic>? ?? [])
          .map((block) => BlockEventModel.fromJson(block as Map<String, dynamic>))
          .toList();

  @override
  List<Object?> get props => [
    seq,
    sessionId,
    sourceId,
    kind,
    rawEvent,
    harness,
    toolName,
    toolUseId,
    text,
    redactedSpans,
    errorType,
    hookVersion,
    truncatedLines,
    createdAt,
  ];
}
```

`packages/mobile/lib/feature/blocks/data/model/params/get_session_blocks_params.dart`:

```dart
import 'package:equatable/equatable.dart';

class GetSessionBlocksParams extends Equatable {
  final int? afterSeq;
  final int? limit;

  const GetSessionBlocksParams({this.afterSeq, this.limit});

  Map<String, dynamic> toJson() => {
    if (afterSeq != null) 'afterSeq': afterSeq,
    if (limit != null) 'limit': limit,
  };

  @override
  List<Object?> get props => [afterSeq, limit];
}
```

- [ ] **Step 4: Run the model test**

```bash
cd packages/mobile && flutter test test/feature/blocks/data/block_event_model_test.dart
```

Expected: PASS.

- [ ] **Step 5: Write the failing repository test**

Create `packages/mobile/test/feature/blocks/data/blocks_repository_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';

class _MockDataSource extends Mock implements BlocksRemoteDataSource {}

class _OnlineNetwork implements NetworkStatus {
  @override
  Future<bool> get isConnected async => true;
}

class _OfflineNetwork implements NetworkStatus {
  @override
  Future<bool> get isConnected async => false;
}

void main() {
  setUpAll(() => registerFallbackValue(const GetSessionBlocksParams()));

  test('the endpoint encodes the session id', () {
    expect(EndPoints.sessionBlocks('a b/c'), '/api/v1/sessions/a%20b%2Fc/blocks');
  });

  test('returns the parsed log', () async {
    final source = _MockDataSource();
    when(() => source.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => const [BlockEventModel(seq: 1, kind: 'stop')],
    );
    final repository = BlocksRepositoryImp(source, _OnlineNetwork());

    final result = await repository.getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 4));

    expect(result.isSuccess, isTrue);
    expect(result.getOrDefault(const []).single.seq, 1);
    verify(() => source.getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 4))).called(1);
  });

  test('fails without a network instead of calling the daemon', () async {
    final source = _MockDataSource();
    final repository = BlocksRepositoryImp(source, _OfflineNetwork());

    final result = await repository.getSessionBlocks('s-1', const GetSessionBlocksParams());

    expect(result.isFailure, isTrue);
    verifyNever(() => source.getSessionBlocks(any(), any()));
  });

  test('surfaces a data-source failure as a Result failure', () async {
    final source = _MockDataSource();
    when(() => source.getSessionBlocks(any(), any())).thenThrow(
      ServerFailure(error: 'boom', message: 'boom', statusCode: 500),
    );
    final repository = BlocksRepositoryImp(source, _OnlineNetwork());

    final result = await repository.getSessionBlocks('s-1', const GetSessionBlocksParams());

    expect(result.isFailure, isTrue);
  });
}
```

Two things this test depends on, both verified against the current source so you do not have to guess:

- `ServerFailure` is at `packages/mobile/lib/core/error_handling/failures/server_failure.dart:3`. Its default constructor **requires** a positional-named `error` — `ServerFailure({StackTrace? stacktrace, required Object error, super.message = '', super.statusCode, …})` — which is why the test passes `error: 'boom'`. It also logs through `AppLogger` on construction, which is noise in test output and not a failure. `ServerFailure.noNetwork()` at :19 is the one the repository returns offline.
- `NetworkStatus` (`packages/mobile/lib/core/helpers/network/network_status.dart:5`) declares exactly one member, `Future<bool> get isConnected`, so the two hand-written stubs above are complete. Do not change `NetworkStatus` and do not reach for its real implementation, which pings `EndPoints.health`.

- [ ] **Step 6: Run it and watch it fail**

```bash
cd packages/mobile && flutter test test/feature/blocks/data/blocks_repository_test.dart
```

Expected: compile failure — `EndPoints.sessionBlocks`, `BlocksRemoteDataSource`, `BlocksRepositoryImp` undefined.

- [ ] **Step 7: Add the endpoint**

In `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`, beside `sessionSend` (:49):

```dart
  static String sessionBlocks(String sessionId) => '${_session(sessionId)}/blocks';
```

`_session` (:59) already does `Uri.encodeComponent`, which is what makes the encoding test pass.

- [ ] **Step 8: Write the data source and repository**

`packages/mobile/lib/feature/blocks/data/data_source/blocks_remote_data_source.dart`:

```dart
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';

abstract class BlocksRemoteDataSource {
  Future<List<BlockEventModel>> getSessionBlocks(String sessionId, GetSessionBlocksParams params);
}

class BlocksRemoteDataSourceImp implements BlocksRemoteDataSource {
  final ApiConsumer _apiConsumer;

  BlocksRemoteDataSourceImp(this._apiConsumer);

  @override
  Future<List<BlockEventModel>> getSessionBlocks(
    String sessionId,
    GetSessionBlocksParams params,
  ) async {
    final response = await _apiConsumer.get(
      EndPoints.sessionBlocks(sessionId),
      queryParameters: params.toJson(),
    );
    final parsed = GlobalResponse<List<BlockEventModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: BlockEventModel.listFromJson,
    );
    return parsed.data ?? const [];
  }
}
```

`withDataKey: false` is mandatory: the daemon does not use `GlobalResponse`'s `data` key — `/blocks` returns `{"blocks":[…]}` directly, exactly as `/projects` returns `{projects: […]}`.

`packages/mobile/lib/feature/blocks/data/repository/blocks_repository.dart`:

```dart
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';

abstract class BlocksRepository {
  FutureResult<List<BlockEventModel>> getSessionBlocks(
    String sessionId,
    GetSessionBlocksParams params,
  );
}

class BlocksRepositoryImp implements BlocksRepository {
  BlocksRepositoryImp(this._remoteDataSource, this._network);

  final BlocksRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<List<BlockEventModel>> getSessionBlocks(
    String sessionId,
    GetSessionBlocksParams params,
  ) => _guard(() => _remoteDataSource.getSessionBlocks(sessionId, params));

  Future<Result<T, Failure>> _guard<T>(Future<T> Function() action) async {
    if (await _network.isConnected) {
      try {
        return Result.success(await action());
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }
}
```

- [ ] **Step 9: Register in the service locator**

In `packages/mobile/lib/core/utils/service_locator.dart`, add a setup method beside `_terminalFeatureSetup()` (:210):

```dart
  static void _blocksFeatureSetup() {
    sl.registerLazySingleton<BlocksRepository>(
      () => BlocksRepositoryImp(sl<BlocksRemoteDataSource>(), sl<NetworkStatus>()),
    );
    sl.registerLazySingleton<BlocksRemoteDataSource>(
      () => BlocksRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }
```

Call it from `init()` immediately after the terminal feature's setup call, and add the two imports. Task 5 adds the `BlocksCubit` registration to this same method.

- [ ] **Step 10: Run the repository test**

```bash
cd packages/mobile && flutter test test/feature/blocks/data/
```

Expected: PASS.

- [ ] **Step 11: Gate**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: `No issues found!` and green.

- [ ] **Step 12: Commit**

```bash
git add packages/mobile/lib/feature/blocks packages/mobile/lib/core/api/api_request_helpers/end_points.dart packages/mobile/lib/core/utils/service_locator.dart packages/mobile/test/feature/blocks
git commit -m "feat(mobile): add the blocks data layer"
```

---

## Task 4: The shared block model and assembly

**Why:** This is the heart of the plan and the piece plan 3 (desktop) will re-implement in TypeScript against the same fixtures. It is **pure Dart** — no Flutter, no cubit, no I/O — so it is cheap to test exhaustively, which is the only defence against the two blind spots that let bugs through plan 1: async ordering and non-ASCII input.

**Files:**
- Create: `packages/mobile/lib/feature/blocks/logic/session_block.dart`
- Create: `packages/mobile/lib/feature/blocks/logic/block_assembly.dart`
- Create: `packages/mobile/lib/feature/blocks/logic/block_harnesses.dart`
- Create: `testdata/blocks/assembly_turn.json`
- Create: `testdata/blocks/assembly_permission.json`
- Create: `testdata/blocks/assembly_out_of_order.json`
- Create: `testdata/blocks/assembly_truncation.json`
- Test: `packages/mobile/test/feature/blocks/logic/block_assembly_test.dart`
- Test: `packages/mobile/test/feature/blocks/logic/block_assembly_fixtures_test.dart`

**Interfaces:**
- Consumes: `BlockEventModel` from Task 3.
- Produces, for Tasks 5, 6 and 7, and for plan 3's TypeScript port:
  - `enum BlockKind { prompt, assistant, tool, permission, notice }`
  - `enum BlockStatus { running, ok, failed, blocked }`
  - `class SessionBlock extends Equatable` with fields `String id`, `int firstSeq`, `int lastSeq`, `BlockKind kind`, `BlockStatus status`, `String title`, `String body`, `String? toolName`, `int truncatedLines`, `bool redacted`, `String? createdAt`, and `SessionBlock copyWith({BlockStatus? status, String? body, int? lastSeq, int? truncatedLines, bool? redacted})`
  - `List<SessionBlock> assembleBlocks(Iterable<BlockEventModel> events)`
  - `List<SessionBlock> resolveStranded(List<SessionBlock> blocks, String reason)`
  - `sealed class BlockHarnesses { static const Set<String> supported = {'claude-code', 'grok', 'codex'}; static bool covers(String? harness); }`

### The assembly rules, exactly

`assembleBlocks` sorts by `seq` ascending first — **it must never assume input order**, because live socket events and a REST history page interleave. Events with a null `seq` are dropped. A `seq` already consumed in this call is dropped, so merging history with live overlap is idempotent.

Then, per event, keyed off `kind`:

| `kind` | Effect |
| --- | --- |
| `session_start` | New `notice` block, status `ok`, title `Session started`, body `text` |
| `prompt_submit` | New `prompt` block, status **`running`**, title `Prompt`, body `text` |
| `tool_complete` | Correlate on `sourceId`. Existing block with that key → set status `ok`, replace `body` with `text`, bump `lastSeq`. No match → new `tool` block, status `ok`, title `toolName` (or `Tool`), body `text` |
| `permission_request` | Correlate on `sourceId` → new `permission` block, status **`blocked`**, title `Permission requested`, body = `toolName` and `text` joined by a newline when both are present |
| `permission_replied` | Correlate on `sourceId` → set that block's status to `ok`. **No match → no block at all**, because a reply with nothing to reply to is not information |
| `stop` | Resolve the most recent `running` `prompt` block to `ok`; then, if `text` is non-empty, append a new `assistant` block, status `ok`, title `Assistant` |
| `stop_failure` | Resolve the most recent `running` `prompt` block to **`failed`**; then, if `text` is non-empty, append a new `assistant` block, status **`failed`** |
| `question_asked` | New `notice` block, status **`blocked`**, title `Waiting on you`, body `text` |
| `idle_prompt` | **Dropped.** Per the spec: "IdlePrompt … is evidence of idleness rather than aliveness." A block per idle tick would flood the list and say nothing |
| `unknown` / anything else | New `notice` block, status `ok`, title = `rawEvent` when non-empty else `Event`, body `text` |

Correlation key: `sourceId` when non-empty, else `toolUseId` when non-empty, else there is no key and the event gets its own block. Block `id` is `'seq-<seq>'` for uncorrelated blocks and `'src-<key>'` for correlated ones — **never a generated UUID**. The spec is explicit: "The id is minted at the source, never by a consumer. … A consumer that invents ids cannot deduplicate on reconnect, cannot correlate a `tool_complete` with its `prompt_submit`, and cannot let two clients agree on what they are looking at."

`truncatedLines` and `redacted` come straight off the event (`truncatedLines ?? 0`, `redactedSpans` non-null and non-empty). When a `tool_complete` updates an existing block, both are taken from the updating event, not merged.

`resolveStranded(blocks, reason)` maps every block whose status is `running` or `blocked` to status `failed` with `body` set to `reason`, and returns the rest unchanged. The invariant it enforces is the spec's: "no block spins forever."

- [ ] **Step 1: Write the fixtures**

`testdata/blocks/assembly_turn.json`:

```json
{
  "records": [
    { "seq": 1, "sessionId": "s-1", "kind": "session_start", "harness": "claude-code" },
    { "seq": 2, "sessionId": "s-1", "kind": "prompt_submit", "text": "run the tests" },
    { "seq": 3, "sessionId": "s-1", "kind": "tool_complete", "sourceId": "tu-1", "toolUseId": "tu-1", "toolName": "Bash", "text": "ok 42 tests" },
    { "seq": 4, "sessionId": "s-1", "kind": "idle_prompt" },
    { "seq": 5, "sessionId": "s-1", "kind": "stop", "text": "all green" }
  ],
  "expected": [
    { "id": "seq-1", "kind": "notice", "status": "ok", "title": "Session started", "body": "" },
    { "id": "seq-2", "kind": "prompt", "status": "ok", "title": "Prompt", "body": "run the tests" },
    { "id": "src-tu-1", "kind": "tool", "status": "ok", "title": "Bash", "body": "ok 42 tests" },
    { "id": "seq-5", "kind": "assistant", "status": "ok", "title": "Assistant", "body": "all green" }
  ]
}
```

`testdata/blocks/assembly_permission.json`:

```json
{
  "records": [
    { "seq": 1, "sessionId": "s-1", "kind": "prompt_submit", "text": "delete the branch" },
    { "seq": 2, "sessionId": "s-1", "kind": "permission_request", "sourceId": "pr-1", "toolName": "Bash", "text": "git branch -D feat/x" },
    { "seq": 3, "sessionId": "s-1", "kind": "permission_replied", "sourceId": "pr-1" },
    { "seq": 4, "sessionId": "s-1", "kind": "stop_failure", "text": "refused" }
  ],
  "expected": [
    { "id": "seq-1", "kind": "prompt", "status": "failed", "title": "Prompt", "body": "delete the branch" },
    { "id": "src-pr-1", "kind": "permission", "status": "ok", "title": "Permission requested", "body": "Bash\ngit branch -D feat/x" },
    { "id": "seq-4", "kind": "assistant", "status": "failed", "title": "Assistant", "body": "refused" }
  ]
}
```

`testdata/blocks/assembly_out_of_order.json` — the same turn as `assembly_turn.json`, shuffled, with a duplicate. It must assemble identically, which is the property that makes the history/live merge safe:

```json
{
  "records": [
    { "seq": 5, "sessionId": "s-1", "kind": "stop", "text": "all green" },
    { "seq": 2, "sessionId": "s-1", "kind": "prompt_submit", "text": "run the tests" },
    { "seq": 3, "sessionId": "s-1", "kind": "tool_complete", "sourceId": "tu-1", "toolUseId": "tu-1", "toolName": "Bash", "text": "ok 42 tests" },
    { "seq": 1, "sessionId": "s-1", "kind": "session_start", "harness": "claude-code" },
    { "seq": 3, "sessionId": "s-1", "kind": "tool_complete", "sourceId": "tu-1", "toolUseId": "tu-1", "toolName": "Bash", "text": "ok 42 tests" },
    { "seq": 4, "sessionId": "s-1", "kind": "idle_prompt" }
  ],
  "expected": [
    { "id": "seq-1", "kind": "notice", "status": "ok", "title": "Session started", "body": "" },
    { "id": "seq-2", "kind": "prompt", "status": "ok", "title": "Prompt", "body": "run the tests" },
    { "id": "src-tu-1", "kind": "tool", "status": "ok", "title": "Bash", "body": "ok 42 tests" },
    { "id": "seq-5", "kind": "assistant", "status": "ok", "title": "Assistant", "body": "all green" }
  ]
}
```

`testdata/blocks/assembly_truncation.json` — truncation and redaction survive assembly, and an unrecognized event degrades to a notice rather than vanishing:

```json
{
  "records": [
    { "seq": 1, "sessionId": "s-1", "kind": "tool_complete", "sourceId": "tu-9", "toolName": "Read", "text": "AWS_KEY=[redacted]\nline two", "redactedSpans": [{ "start": 8, "end": 18 }], "truncatedLines": 4212 },
    { "seq": 2, "sessionId": "s-1", "kind": "unknown", "rawEvent": "some-future-hook", "text": "hello" },
    { "seq": 3, "sessionId": "s-1", "kind": "permission_replied", "sourceId": "never-requested" }
  ],
  "expected": [
    { "id": "src-tu-9", "kind": "tool", "status": "ok", "title": "Read", "body": "AWS_KEY=[redacted]\nline two", "truncatedLines": 4212, "redacted": true },
    { "id": "seq-2", "kind": "notice", "status": "ok", "title": "some-future-hook", "body": "hello" }
  ]
}
```

- [ ] **Step 2: Write the failing unit tests**

Create `packages/mobile/test/feature/blocks/logic/block_assembly_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/block_assembly.dart';
import 'package:operator_mobile/feature/blocks/logic/block_harnesses.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

BlockEventModel _event(
  int seq,
  String kind, {
  String? sourceId,
  String? toolName,
  String? toolUseId,
  String? text,
  String? rawEvent,
  int? truncatedLines,
  List<BlockRedactedSpanModel>? spans,
}) => BlockEventModel(
  seq: seq,
  sessionId: 's-1',
  kind: kind,
  sourceId: sourceId,
  toolName: toolName,
  toolUseId: toolUseId,
  text: text,
  rawEvent: rawEvent,
  truncatedLines: truncatedLines,
  redactedSpans: spans,
);

void main() {
  group('assembleBlocks', () {
    test('a prompt is running until its stop arrives', () {
      final open = assembleBlocks([_event(1, 'prompt_submit', text: 'go')]);
      expect(open.single.status, BlockStatus.running);

      final closed = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'stop', text: 'done'),
      ]);
      expect(closed.first.status, BlockStatus.ok);
      expect(closed.last.kind, BlockKind.assistant);
      expect(closed.last.body, 'done');
    });

    test('stop_failure fails the open prompt and its assistant block', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'stop_failure', text: 'crashed'),
      ]);

      expect(blocks.first.status, BlockStatus.failed);
      expect(blocks.last.status, BlockStatus.failed);
    });

    test('a stop with no text resolves the prompt without adding a block', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'stop'),
      ]);

      expect(blocks, hasLength(1));
      expect(blocks.single.status, BlockStatus.ok);
    });

    test('a stop with no open prompt still records the assistant text', () {
      final blocks = assembleBlocks([_event(1, 'stop', text: 'orphan')]);

      expect(blocks.single.kind, BlockKind.assistant);
      expect(blocks.single.body, 'orphan');
    });

    test('only the most recent open prompt is resolved', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'first'),
        _event(2, 'prompt_submit', text: 'second'),
        _event(3, 'stop', text: 'done'),
      ]);

      expect(blocks[0].status, BlockStatus.running);
      expect(blocks[1].status, BlockStatus.ok);
    });

    test('a tool_complete correlates on sourceId rather than creating a twin', () {
      final blocks = assembleBlocks([
        _event(1, 'permission_request', sourceId: 'k', toolName: 'Bash', text: 'rm -rf'),
        _event(2, 'permission_replied', sourceId: 'k'),
      ]);

      expect(blocks, hasLength(1));
      expect(blocks.single.id, 'src-k');
      expect(blocks.single.status, BlockStatus.ok);
    });

    test('toolUseId is the fallback correlation key', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_complete', toolUseId: 'tu-2', toolName: 'Bash', text: 'a'),
        _event(2, 'tool_complete', toolUseId: 'tu-2', toolName: 'Bash', text: 'b'),
      ]);

      expect(blocks, hasLength(1));
      expect(blocks.single.body, 'b');
      expect(blocks.single.lastSeq, 2);
    });

    test('uncorrelated events each get their own block', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_complete', toolName: 'Bash', text: 'a'),
        _event(2, 'tool_complete', toolName: 'Bash', text: 'b'),
      ]);

      expect(blocks.map((b) => b.id), ['seq-1', 'seq-2']);
    });

    test('idle_prompt produces nothing', () {
      expect(assembleBlocks([_event(1, 'idle_prompt')]), isEmpty);
    });

    test('a permission_replied with nothing to reply to produces nothing', () {
      expect(assembleBlocks([_event(1, 'permission_replied', sourceId: 'ghost')]), isEmpty);
    });

    test('an unknown kind degrades to a notice titled by its raw event', () {
      final blocks = assembleBlocks([
        _event(1, 'unknown', rawEvent: 'future-hook', text: 'body'),
      ]);

      expect(blocks.single.kind, BlockKind.notice);
      expect(blocks.single.title, 'future-hook');
      expect(blocks.single.body, 'body');
    });

    test('an unknown kind with no raw event still renders', () {
      expect(assembleBlocks([_event(1, 'unknown')]).single.title, 'Event');
    });

    test('input order does not matter and duplicate seqs are dropped', () {
      final ordered = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'tool_complete', sourceId: 'k', toolName: 'Bash', text: 'out'),
        _event(3, 'stop', text: 'done'),
      ]);
      final shuffled = assembleBlocks([
        _event(3, 'stop', text: 'done'),
        _event(2, 'tool_complete', sourceId: 'k', toolName: 'Bash', text: 'out'),
        _event(2, 'tool_complete', sourceId: 'k', toolName: 'Bash', text: 'out'),
        _event(1, 'prompt_submit', text: 'go'),
      ]);

      expect(shuffled, ordered);
    });

    test('an event with no seq is dropped rather than crashing', () {
      expect(assembleBlocks([const BlockEventModel(kind: 'stop', text: 'x')]), isEmpty);
    });

    test('truncation and redaction ride along', () {
      final blocks = assembleBlocks([
        _event(
          1,
          'tool_complete',
          sourceId: 'k',
          toolName: 'Read',
          text: 'k=[redacted]',
          truncatedLines: 900,
          spans: const [BlockRedactedSpanModel(start: 2, end: 12)],
        ),
      ]);

      expect(blocks.single.truncatedLines, 900);
      expect(blocks.single.redacted, isTrue);
    });

    test('multi-byte text survives assembly unchanged', () {
      final blocks = assembleBlocks([_event(1, 'stop', text: 'héllo → 世界 🎉')]);

      expect(blocks.single.body, 'héllo → 世界 🎉');
    });

    test('a tool_complete with no name is still readable', () {
      expect(assembleBlocks([_event(1, 'tool_complete', text: 'x')]).single.title, 'Tool');
    });
  });

  group('resolveStranded', () {
    test('running and blocked become failed with the stated reason', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'permission_request', sourceId: 'k', toolName: 'Bash'),
        _event(3, 'tool_complete', sourceId: 'done', toolName: 'Bash', text: 'fine'),
      ]);

      final resolved = resolveStranded(blocks, 'Session exited');

      expect(resolved[0].status, BlockStatus.failed);
      expect(resolved[0].body, 'Session exited');
      expect(resolved[1].status, BlockStatus.failed);
      expect(resolved[2].status, BlockStatus.ok);
      expect(resolved[2].body, 'fine');
    });

    test('is a no-op when nothing is stranded', () {
      final blocks = assembleBlocks([_event(1, 'stop', text: 'done')]);

      expect(resolveStranded(blocks, 'Session exited'), blocks);
    });
  });

  group('BlockHarnesses', () {
    test('covers the harnesses with registered mappers', () {
      expect(BlockHarnesses.covers('claude-code'), isTrue);
      expect(BlockHarnesses.covers('grok'), isTrue);
      expect(BlockHarnesses.covers('codex'), isTrue);
    });

    test('does not cover an unknown or absent harness', () {
      expect(BlockHarnesses.covers('aider'), isFalse);
      expect(BlockHarnesses.covers(null), isFalse);
      expect(BlockHarnesses.covers(''), isFalse);
    });
  });
}
```

- [ ] **Step 3: Write the failing fixture test**

Create `packages/mobile/test/feature/blocks/logic/block_assembly_fixtures_test.dart`. This is the test that keeps Dart and TypeScript honest — plan 3 will add a mirror of it.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/block_assembly.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

const _fixtures = [
  'assembly_turn',
  'assembly_permission',
  'assembly_out_of_order',
  'assembly_truncation',
];

void main() {
  for (final name in _fixtures) {
    test('$name assembles as the shared fixture says', () {
      final file = File('../../testdata/blocks/$name.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'the shared fixture is missing; never fix a failing fixture by editing it',
      );

      final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final records = (fixture['records'] as List<dynamic>)
          .map((raw) => BlockEventModel.fromJson(raw as Map<String, dynamic>))
          .toList();
      final expected = (fixture['expected'] as List<dynamic>).cast<Map<String, dynamic>>();

      final blocks = assembleBlocks(records);

      expect(blocks, hasLength(expected.length), reason: 'block count for $name');
      for (var i = 0; i < expected.length; i++) {
        final want = expected[i];
        final got = blocks[i];
        expect(got.id, want['id'], reason: '$name block $i id');
        expect(got.kind.name, want['kind'], reason: '$name block $i kind');
        expect(got.status.name, want['status'], reason: '$name block $i status');
        expect(got.title, want['title'], reason: '$name block $i title');
        expect(got.body, want['body'] ?? '', reason: '$name block $i body');
        expect(got.truncatedLines, want['truncatedLines'] ?? 0, reason: '$name block $i truncatedLines');
        expect(got.redacted, want['redacted'] ?? false, reason: '$name block $i redacted');
      }
    });
  }
}
```

The relative path is correct because `flutter test` runs with the working directory set to the package root, `packages/mobile`, so `../..` is the repo root.

- [ ] **Step 4: Run both and watch them fail**

```bash
cd packages/mobile && flutter test test/feature/blocks/logic/
```

Expected: compile failure — `assembleBlocks`, `resolveStranded`, `SessionBlock`, `BlockKind`, `BlockStatus`, `BlockHarnesses` are undefined.

- [ ] **Step 5: Write the model**

`packages/mobile/lib/feature/blocks/logic/session_block.dart`:

```dart
import 'package:equatable/equatable.dart';

enum BlockKind { prompt, assistant, tool, permission, notice }

enum BlockStatus { running, ok, failed, blocked }

class SessionBlock extends Equatable {
  const SessionBlock({
    required this.id,
    required this.firstSeq,
    required this.lastSeq,
    required this.kind,
    required this.status,
    required this.title,
    required this.body,
    this.toolName,
    this.truncatedLines = 0,
    this.redacted = false,
    this.createdAt,
  });

  final String id;
  final int firstSeq;
  final int lastSeq;
  final BlockKind kind;
  final BlockStatus status;
  final String title;
  final String body;
  final String? toolName;
  final int truncatedLines;
  final bool redacted;
  final String? createdAt;

  SessionBlock copyWith({
    BlockStatus? status,
    String? body,
    int? lastSeq,
    int? truncatedLines,
    bool? redacted,
    String? createdAt,
  }) => SessionBlock(
    id: id,
    firstSeq: firstSeq,
    lastSeq: lastSeq ?? this.lastSeq,
    kind: kind,
    status: status ?? this.status,
    title: title,
    body: body ?? this.body,
    toolName: toolName,
    truncatedLines: truncatedLines ?? this.truncatedLines,
    redacted: redacted ?? this.redacted,
    createdAt: createdAt ?? this.createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    firstSeq,
    lastSeq,
    kind,
    status,
    title,
    body,
    toolName,
    truncatedLines,
    redacted,
    createdAt,
  ];
}
```

`packages/mobile/lib/feature/blocks/logic/block_harnesses.dart`:

```dart
sealed class BlockHarnesses {
  static const Set<String> supported = {'claude-code', 'grok', 'codex'};

  static bool covers(String? harness) => harness != null && supported.contains(harness);
}
```

The three names mirror `backend/internal/adapters/agent/blockdispatch/dispatch.go:43`. If a mapper is added there, add it here; there is no runtime handshake that discovers this.

- [ ] **Step 6: Write the assembly**

`packages/mobile/lib/feature/blocks/logic/block_assembly.dart`:

```dart
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

List<SessionBlock> assembleBlocks(Iterable<BlockEventModel> events) {
  final ordered = events.where((event) => event.seq != null).toList()
    ..sort((a, b) => a.seq!.compareTo(b.seq!));

  final blocks = <SessionBlock>[];
  final indexById = <String, int>{};
  final consumed = <int>{};

  for (final event in ordered) {
    final seq = event.seq!;
    if (!consumed.add(seq)) continue;

    final key = _correlationKey(event);
    final text = event.text ?? '';

    switch (event.kind) {
      case 'idle_prompt':
        continue;

      case 'session_start':
        _append(blocks, indexById, _create(event, key, BlockKind.notice, BlockStatus.ok, 'Session started', text));

      case 'prompt_submit':
        _append(blocks, indexById, _create(event, key, BlockKind.prompt, BlockStatus.running, 'Prompt', text));

      case 'tool_complete':
        final at = key == null ? null : indexById['src-$key'];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(
            status: BlockStatus.ok,
            body: text,
            lastSeq: seq,
            truncatedLines: event.truncatedLines ?? 0,
            redacted: _isRedacted(event),
          );
        } else {
          _append(
            blocks,
            indexById,
            _create(event, key, BlockKind.tool, BlockStatus.ok, event.toolName ?? 'Tool', text),
          );
        }

      case 'permission_request':
        final body = [
          if ((event.toolName ?? '').isNotEmpty) event.toolName!,
          if (text.isNotEmpty) text,
        ].join('\n');
        _append(
          blocks,
          indexById,
          _create(event, key, BlockKind.permission, BlockStatus.blocked, 'Permission requested', body),
        );

      case 'permission_replied':
        final at = key == null ? null : indexById['src-$key'];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(status: BlockStatus.ok, lastSeq: seq);
        }

      case 'stop':
      case 'stop_failure':
        final failed = event.kind == 'stop_failure';
        final at = _lastRunningPrompt(blocks);
        if (at != null) {
          blocks[at] = blocks[at].copyWith(
            status: failed ? BlockStatus.failed : BlockStatus.ok,
            lastSeq: seq,
          );
        }
        if (text.isNotEmpty) {
          _append(
            blocks,
            indexById,
            _create(
              event,
              key,
              BlockKind.assistant,
              failed ? BlockStatus.failed : BlockStatus.ok,
              'Assistant',
              text,
            ),
          );
        }

      default:
        final raw = event.rawEvent ?? '';
        _append(
          blocks,
          indexById,
          _create(event, key, BlockKind.notice, BlockStatus.ok, raw.isNotEmpty ? raw : 'Event', text),
        );
    }
  }

  return blocks;
}

List<SessionBlock> resolveStranded(List<SessionBlock> blocks, String reason) => blocks
    .map(
      (block) => block.status == BlockStatus.running || block.status == BlockStatus.blocked
          ? block.copyWith(status: BlockStatus.failed, body: reason)
          : block,
    )
    .toList();

String? _correlationKey(BlockEventModel event) {
  final source = event.sourceId ?? '';
  if (source.isNotEmpty) return source;
  final toolUse = event.toolUseId ?? '';
  return toolUse.isNotEmpty ? toolUse : null;
}

bool _isRedacted(BlockEventModel event) => (event.redactedSpans ?? const []).isNotEmpty;

SessionBlock _create(
  BlockEventModel event,
  String? key,
  BlockKind kind,
  BlockStatus status,
  String title,
  String body,
) {
  final correlated = key != null && _correlates(event.kind);
  return SessionBlock(
    id: correlated ? 'src-$key' : 'seq-${event.seq}',
    firstSeq: event.seq!,
    lastSeq: event.seq!,
    kind: kind,
    status: status,
    title: title,
    body: body,
    toolName: event.toolName,
    truncatedLines: event.truncatedLines ?? 0,
    redacted: _isRedacted(event),
    createdAt: event.createdAt,
  );
}

bool _correlates(String? kind) =>
    kind == 'tool_complete' || kind == 'permission_request' || kind == 'permission_replied';

void _append(List<SessionBlock> blocks, Map<String, int> indexById, SessionBlock block) {
  indexById[block.id] = blocks.length;
  blocks.add(block);
}

int? _lastRunningPrompt(List<SessionBlock> blocks) {
  for (var i = blocks.length - 1; i >= 0; i--) {
    if (blocks[i].kind == BlockKind.prompt && blocks[i].status == BlockStatus.running) return i;
  }
  return null;
}
```

- [ ] **Step 7: Run both test files**

```bash
cd packages/mobile && flutter test test/feature/blocks/logic/
```

Expected: PASS. If the fixture test fails, **fix `block_assembly.dart`, not the fixture.**

- [ ] **Step 8: Gate**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: `No issues found!` and green. `flutter analyze` will complain if any `switch` case falls through without a body — Dart 3 switch statements do not fall through, and the `case 'stop': case 'stop_failure':` pair above shares one body legally because the first case is empty.

- [ ] **Step 9: Commit**

```bash
git add packages/mobile/lib/feature/blocks/logic packages/mobile/test/feature/blocks/logic testdata/blocks
git commit -m "feat(mobile): assemble block events into the shared block model"
```

---

## Task 5: `BlocksCubit` — subscribe, backfill, merge, bound, resolve

**Why:** This is where the two failure modes that survived plan 1's review live: **async ordering** (a live event arriving before, during, or after the history fetch) and **reconnect** (a dropped socket must refetch by sequence, not start over). Both are pinned by tests here rather than left to review.

**The ordering rule, and why it is not what it looks like.** The cubit subscribes to the socket **before** it fetches history, not after. Fetching first would leave a window in which an event is published, missed by the not-yet-existing subscription, and absent from the already-returned page. Because every event is merged into a `SplayTreeMap<int, BlockEventModel>` keyed by `seq`, arrival order is irrelevant and duplicates are free — which is what makes subscribing first safe rather than merely early.

**Files:**
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/blocks_state.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_cubit_test.dart`

**Interfaces:**
- Consumes: `MuxClient.blockEvents`, `.status`, `.sessionPatches`, `.subscribeBlocks`, `.unsubscribeBlocks` (Task 2); `BlocksRepository.getSessionBlocks` and `GetSessionBlocksParams` (Task 3); `assembleBlocks`, `resolveStranded`, `BlockHarnesses` (Task 4).
- Produces, for Tasks 6 and 7:
  - `class BlocksCubit extends Cubit<BlocksState>` with constructor `BlocksCubit(MuxClient mux, BlocksRepository repository, String sessionId, {String? harness})`
  - public mutable fields `List<SessionBlock> blocks`, `bool loading`, `String? error`, `bool supported`
  - `Future<void> refresh()`
  - states `BlocksInitialState`, `BlocksReadyState(int revision)`, `BlocksUnsupportedState(String? harness)`
- `const int kBlockWindow = 400;`

**State shape:** mirror `TerminalCubit` (`terminal_cubit.dart:98-117`) — public mutable fields plus `BlocksReadyState(++_revision)` to trigger rebuilds. This is the established pattern in this package and consistency beats purity; do not invent an immutable state class here.

- [ ] **Step 1: Write the failing cubit tests**

Create `packages/mobile/test/feature/blocks/presentation/blocks_cubit_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';

class _MockMux extends Mock implements MuxClient {}

class _MockRepository extends Mock implements BlocksRepository {}

Map<String, dynamic> _wire(int seq, String kind, {String? text, String? sourceId, String? toolName}) => {
  'seq': seq,
  'sessionId': 's-1',
  'kind': kind,
  if (text != null) 'text': text,
  if (sourceId != null) 'sourceId': sourceId,
  if (toolName != null) 'toolName': toolName,
};

void main() {
  late _MockMux mux;
  late _MockRepository repository;
  late StreamController<BlockEventEnvelope> events;
  late StreamController<MuxStatus> statuses;
  late StreamController<List<SessionPatch>> patches;

  setUpAll(() => registerFallbackValue(const GetSessionBlocksParams()));

  setUp(() {
    mux = _MockMux();
    repository = _MockRepository();
    events = StreamController<BlockEventEnvelope>.broadcast();
    statuses = StreamController<MuxStatus>.broadcast();
    patches = StreamController<List<SessionPatch>>.broadcast();
    when(() => mux.blockEvents).thenAnswer((_) => events.stream);
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    when(() => mux.sessionPatches).thenAnswer((_) => patches.stream);
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => mux.subscribeBlocks(any())).thenReturn(null);
    when(() => mux.unsubscribeBlocks(any())).thenReturn(null);
    when(() => repository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
  });

  tearDown(() async {
    await events.close();
    await statuses.close();
    await patches.close();
  });

  BlocksCubit build({String? harness = 'claude-code'}) =>
      BlocksCubit(mux, repository, 's-1', harness: harness);

  test('subscribes before it fetches history', () async {
    final order = <String>[];
    when(() => mux.subscribeBlocks(any())).thenAnswer((_) {
      order.add('subscribe');
      return null;
    });
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer((_) async {
      order.add('history');
      return Result.success(const <BlockEventModel>[]);
    });

    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    expect(order, ['subscribe', 'history']);
    await cubit.close();
  });

  test('an event that lands before history is not lost or duplicated', () async {
    final gate = Completer<void>();
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer((_) async {
      await gate.future;
      return Result.success([
        BlockEventModel.fromJson(_wire(1, 'prompt_submit', text: 'go')),
        BlockEventModel.fromJson(_wire(2, 'stop', text: 'done')),
      ]);
    });

    final cubit = build();
    events.add(BlockEventEnvelope('s-1', _wire(2, 'stop', text: 'done')));
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.map((b) => b.id), ['seq-1', 'seq-2']);
    await cubit.close();
  });

  test('ignores events for another session', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    events.add(BlockEventEnvelope('s-2', _wire(1, 'stop', text: 'other')));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks, isEmpty);
    await cubit.close();
  });

  test('refetches from the highest seq it holds after a reconnect', () async {
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([BlockEventModel.fromJson(_wire(9, 'stop', text: 'done'))]),
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    statuses.add(MuxStatus.closed);
    statuses.add(MuxStatus.open);
    await Future<void>.delayed(Duration.zero);

    final captured = verify(() => repository.getSessionBlocks('s-1', captureAny()))
        .captured
        .cast<GetSessionBlocksParams>();
    expect(captured.first.afterSeq, isNull);
    expect(captured.last.afterSeq, 9);
    await cubit.close();
  });

  test('re-subscribes after a reconnect', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    statuses.add(MuxStatus.closed);
    statuses.add(MuxStatus.open);
    await Future<void>.delayed(Duration.zero);

    verify(() => mux.subscribeBlocks('s-1')).called(2);
    await cubit.close();
  });

  test('keeps at most kBlockWindow events, dropping the oldest', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    for (var seq = 1; seq <= kBlockWindow + 10; seq++) {
      events.add(BlockEventEnvelope('s-1', _wire(seq, 'stop', text: 'line $seq')));
    }
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks, hasLength(kBlockWindow));
    expect(cubit.blocks.first.body, 'line 11');
    expect(cubit.blocks.last.body, 'line ${kBlockWindow + 10}');
    await cubit.close();
  });

  test('an exited session leaves no block spinning', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    events.add(BlockEventEnvelope('s-1', _wire(1, 'prompt_submit', text: 'go')));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.blocks.single.status, BlockStatus.running);

    patches.add(const [
      SessionPatch(
        id: 's-1',
        status: 'terminated',
        activity: 'exited',
        attentionLevel: 'none',
        lastActivityAt: '2026-08-27T10:00:00Z',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.single.status, BlockStatus.failed);
    expect(cubit.blocks.single.body, isNotEmpty);
    await cubit.close();
  });

  test('a patch for another session does not strand this one', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    events.add(BlockEventEnvelope('s-1', _wire(1, 'prompt_submit', text: 'go')));
    patches.add(const [
      SessionPatch(
        id: 's-2',
        status: 'terminated',
        activity: 'exited',
        attentionLevel: 'none',
        lastActivityAt: '2026-08-27T10:00:00Z',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.single.status, BlockStatus.running);
    await cubit.close();
  });

  test('surfaces a history failure without discarding live events', () async {
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'boom', message: 'boom')),
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.error, isNotNull);

    events.add(BlockEventEnvelope('s-1', _wire(1, 'stop', text: 'live')));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.single.body, 'live');
    await cubit.close();
  });

  test('an uncovered harness never touches the socket', () async {
    final cubit = build(harness: 'aider');
    await Future<void>.delayed(Duration.zero);

    expect(cubit.supported, isFalse);
    expect(cubit.state, isA<BlocksUnsupportedState>());
    verifyNever(() => mux.subscribeBlocks(any()));
    verifyNever(() => repository.getSessionBlocks(any(), any()));
    await cubit.close();
  });

  test('unsubscribes on close', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await cubit.close();

    verify(() => mux.unsubscribeBlocks('s-1')).called(1);
  });
}
```

Add `import 'package:operator_mobile/core/error_handling/failures/failure.dart';` for `ServerFailure`.

- [ ] **Step 2: Run them and watch them fail**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_cubit_test.dart
```

Expected: compile failure — `BlocksCubit`, `kBlockWindow`, `BlocksUnsupportedState` undefined.

- [ ] **Step 3: Write the state**

`packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/blocks_state.dart`:

```dart
part of 'blocks_cubit.dart';

sealed class BlocksState extends Equatable {
  const BlocksState();

  @override
  List<Object?> get props => [];
}

final class BlocksInitialState extends BlocksState {
  const BlocksInitialState();
}

final class BlocksReadyState extends BlocksState {
  const BlocksReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}

final class BlocksUnsupportedState extends BlocksState {
  const BlocksUnsupportedState(this.harness);

  final String? harness;

  @override
  List<Object?> get props => [harness];
}
```

- [ ] **Step 4: Write the cubit**

`packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart`:

```dart
import 'dart:async';
import 'dart:collection';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/block_assembly.dart';
import 'package:operator_mobile/feature/blocks/logic/block_harnesses.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

part 'blocks_state.dart';

const int kBlockWindow = 400;

const String kSessionEndedReason = 'Session ended before this finished';

class BlocksCubit extends Cubit<BlocksState> {
  BlocksCubit(this._mux, this._repository, this.sessionId, {this.harness})
    : supported = BlockHarnesses.covers(harness),
      super(const BlocksInitialState()) {
    if (!supported) {
      emit(BlocksUnsupportedState(harness));
      return;
    }
    _eventsSub = _mux.blockEvents.where((event) => event.sessionId == sessionId).listen(_onLive);
    _statusSub = _mux.status.listen(_onStatus);
    _patchesSub = _mux.sessionPatches.listen(_onPatches);
    _mux.subscribeBlocks(sessionId);
    unawaited(refresh());
  }

  final MuxClient _mux;
  final BlocksRepository _repository;
  final String sessionId;
  final String? harness;
  final bool supported;

  List<SessionBlock> blocks = const [];
  bool loading = false;
  String? error;

  final SplayTreeMap<int, BlockEventModel> _events = SplayTreeMap<int, BlockEventModel>();
  bool _ended = false;
  int _revision = 0;

  StreamSubscription<BlockEventEnvelope>? _eventsSub;
  StreamSubscription<MuxStatus>? _statusSub;
  StreamSubscription<List<SessionPatch>>? _patchesSub;

  int? get _highestSeq => _events.isEmpty ? null : _events.lastKey();

  Future<void> refresh() async {
    loading = true;
    _emit();
    final result = await _repository.getSessionBlocks(
      sessionId,
      GetSessionBlocksParams(afterSeq: _highestSeq),
    );
    result.when(
      onSuccess: (records) {
        error = null;
        for (final record in records) {
          _merge(record);
        }
      },
      onFailure: (failure) => error = failure.message.isEmpty
          ? 'Could not load this session\'s blocks'
          : failure.message,
    );
    loading = false;
    _rebuild();
  }

  void _onLive(BlockEventEnvelope envelope) {
    _merge(BlockEventModel.fromJson(envelope.block));
    _rebuild();
  }

  void _onStatus(MuxStatus status) {
    if (status != MuxStatus.open) return;
    _mux.subscribeBlocks(sessionId);
    unawaited(refresh());
  }

  void _onPatches(List<SessionPatch> patches) {
    for (final patch in patches) {
      if (patch.id != sessionId) continue;
      final ended = patch.activity == 'exited' || patch.status == 'terminated';
      if (ended != _ended) {
        _ended = ended;
        _rebuild();
      }
      return;
    }
  }

  void _merge(BlockEventModel record) {
    final seq = record.seq;
    if (seq == null) return;
    _events[seq] = record;
    while (_events.length > kBlockWindow) {
      _events.remove(_events.firstKey());
    }
  }

  void _rebuild() {
    final assembled = assembleBlocks(_events.values);
    blocks = _ended ? resolveStranded(assembled, kSessionEndedReason) : assembled;
    _emit();
  }

  void _emit() {
    if (isClosed) return;
    emit(BlocksReadyState(++_revision));
  }

  @override
  Future<void> close() {
    unawaited(_eventsSub?.cancel());
    unawaited(_statusSub?.cancel());
    unawaited(_patchesSub?.cancel());
    if (supported) _mux.unsubscribeBlocks(sessionId);
    return super.close();
  }
}
```

Two details that the tests above will catch if you change them:

- `_onStatus` re-subscribes **and** refetches on every transition to `MuxStatus.open`. `MuxClient` already replays its own `_blockSessions` set on reconnect, so the explicit `subscribeBlocks` here is redundant on the wire but harmless, and it is what makes the cubit correct when it is constructed while the socket is already down.
- `refresh()` passes `afterSeq: _highestSeq`, which is `null` on the first call and the highest held sequence afterwards. That is the spec's "a dropped socket refetches the persisted log by sequence".

- [ ] **Step 5: Register the cubit**

In `packages/mobile/lib/core/utils/service_locator.dart`, add to `_blocksFeatureSetup()` from Task 3, above the repository registration:

```dart
    sl.registerFactoryParam<BlocksCubit, String, String?>(
      (sessionId, harness) =>
          BlocksCubit(sl<MuxClient>(), sl<BlocksRepository>(), sessionId, harness: harness),
    );
```

- [ ] **Step 6: Run the cubit tests**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_cubit_test.dart
```

Expected: PASS, all twelve.

- [ ] **Step 7: Gate**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: `No issues found!` and green.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib/feature/blocks packages/mobile/lib/core/utils/service_locator.dart packages/mobile/test/feature/blocks
git commit -m "feat(mobile): stream and backfill session blocks"
```

---

## Task 6: The block widgets

**Why:** A block list has no columns and no rows — that is the whole reason the phone becomes readable. Everything here reflows to the device width at the skin's own type sizes.

**Files:**
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_body_test.dart`

**Interfaces:**
- Consumes: `SessionBlock`, `BlockKind`, `BlockStatus` (Task 4); `BlocksCubit`, `BlocksState` (Task 5); `context.skin`, `AppTextStyle`, `AppText`.
- Produces, for Task 7: `class BlocksBody extends StatefulWidget { const BlocksBody({super.key}); }` — it reads `BlocksCubit` from context and renders every state itself, so Task 7 places it and nothing else. It is stateful only because it owns a `ScrollController` for the pinned-to-bottom rule.

**Design rules, from `DESIGN.md` and the spec:**
- `AppSkin` tokens only. Status colour: `running` → `skin.blue`, `ok` → `skin.green`, `failed` → `skin.red`, `blocked` → `skin.amber`.
- Block bodies are monospace (`AppTextStyle.mono12Regular`); titles are `AppTextStyle.style12SemiBold`.
- **`AppText` defaults to one line with an ellipsis.** Block bodies must use a plain `Text` with `softWrap: true` — using `AppText` for a body is the bug this plan warns about twice.
- Truncation is **visible**, never silent: a block with `truncatedLines > 0` renders a footer line. This mirrors Warp's `TRUNCATION_MESSAGE` and `num_lines_truncated()`.
- Redaction is **visible**: a block with `redacted == true` renders a marker. The spec: "an invisible redaction is its own bug when someone is debugging."
- No per-block input field. Blocks are output only; the screen keeps the one composer it already has.
- This ships a plain `ListView.builder` plus a pinned-to-bottom rule. Virtualization with a measured-height cache, append anchoring while scrolled up, and sticky headers are plan 4. Do not start them here.

- [ ] **Step 1: Write the failing widget tests**

Create `packages/mobile/test/feature/blocks/presentation/blocks_body_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart';

class _MockBlocksCubit extends MockCubit<BlocksState> implements BlocksCubit {}

SessionBlock _block({
  String id = 'seq-1',
  BlockKind kind = BlockKind.tool,
  BlockStatus status = BlockStatus.ok,
  String title = 'Bash',
  String body = 'ok',
  int truncatedLines = 0,
  bool redacted = false,
}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: kind,
  status: status,
  title: title,
  body: body,
  truncatedLines: truncatedLines,
  redacted: redacted,
);

Future<void> _pump(WidgetTester tester, _MockBlocksCubit cubit) => tester.pumpWidget(
  SkinScope(
    skin: const DarkSkin(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        home: Scaffold(
          body: BlocProvider<BlocksCubit>.value(
            value: cubit,
            child: const SizedBox(width: 400, height: 700, child: BlocksBody()),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  late _MockBlocksCubit cubit;

  setUp(() {
    cubit = _MockBlocksCubit();
    when(() => cubit.state).thenReturn(const BlocksReadyState(1));
    when(() => cubit.supported).thenReturn(true);
    when(() => cubit.harness).thenReturn('claude-code');
    when(() => cubit.blocks).thenReturn(const []);
    when(() => cubit.loading).thenReturn(false);
    when(() => cubit.error).thenReturn(null);
    when(() => cubit.refresh()).thenAnswer((_) async {});
  });

  testWidgets('renders one card per block', (tester) async {
    when(() => cubit.blocks).thenReturn([
      _block(id: 'seq-1', kind: BlockKind.prompt, title: 'Prompt', body: 'run the tests'),
      _block(id: 'src-tu-1', title: 'Bash', body: 'ok 42 tests'),
    ]);

    await _pump(tester, cubit);

    expect(find.byType(BlockCard), findsNWidgets(2));
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('run the tests'), findsOneWidget);
    expect(find.text('ok 42 tests'), findsOneWidget);
  });

  testWidgets('a long body wraps instead of being clipped to one line', (tester) async {
    final long = List.filled(40, 'wrapping').join(' ');
    when(() => cubit.blocks).thenReturn([_block(body: long)]);

    await _pump(tester, cubit);

    final text = tester.widget<Text>(find.text(long));
    expect(text.maxLines, isNull, reason: 'a block body must not be capped to one line');
    expect(text.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('says how much was dropped rather than dropping it silently', (tester) async {
    when(() => cubit.blocks).thenReturn([_block(truncatedLines: 4212)]);

    await _pump(tester, cubit);

    expect(find.textContaining('4212'), findsOneWidget);
    expect(find.textContaining('truncated'), findsOneWidget);
  });

  testWidgets('marks a block that had secrets removed', (tester) async {
    when(() => cubit.blocks).thenReturn([_block(redacted: true)]);

    await _pump(tester, cubit);

    expect(find.textContaining('redacted'), findsOneWidget);
  });

  testWidgets('shows a permission request as blocked and names the tool', (tester) async {
    when(() => cubit.blocks).thenReturn([
      _block(
        id: 'src-pr-1',
        kind: BlockKind.permission,
        status: BlockStatus.blocked,
        title: 'Permission requested',
        body: 'Bash\ngit branch -D feat/x',
      ),
    ]);

    await _pump(tester, cubit);

    expect(find.text('Permission requested'), findsOneWidget);
    expect(find.textContaining('git branch -D feat/x'), findsOneWidget);
  });

  testWidgets('says blocks are unavailable for an uncovered harness', (tester) async {
    when(() => cubit.state).thenReturn(const BlocksUnsupportedState('aider'));
    when(() => cubit.supported).thenReturn(false);
    when(() => cubit.harness).thenReturn('aider');

    await _pump(tester, cubit);

    expect(find.textContaining('aider'), findsOneWidget);
    expect(find.byType(BlockCard), findsNothing);
  });

  testWidgets('an empty covered session says so instead of showing nothing', (tester) async {
    await _pump(tester, cubit);

    expect(find.byType(BlockCard), findsNothing);
    expect(find.textContaining('No blocks yet'), findsOneWidget);
  });

  testWidgets('surfaces a load failure and offers a retry', (tester) async {
    when(() => cubit.error).thenReturn('offline');

    await _pump(tester, cubit);

    expect(find.textContaining('offline'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    verify(() => cubit.refresh()).called(1);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_body_test.dart
```

Expected: compile failure — `BlockCard` and `BlocksBody` do not exist.

- [ ] **Step 3: Write the status dot**

`packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

Color blockStatusColor(AppSkin skin, BlockStatus status) => switch (status) {
  BlockStatus.running => skin.blue,
  BlockStatus.ok => skin.green,
  BlockStatus.failed => skin.red,
  BlockStatus.blocked => skin.amber,
};

class BlockStatusDot extends StatelessWidget {
  const BlockStatusDot({super.key, required this.status});

  final BlockStatus status;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(
      color: blockStatusColor(context.skin, status),
      shape: BoxShape.circle,
    ),
  );
}
```

- [ ] **Step 4: Write the card**

`packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart';

class BlockCard extends StatelessWidget {
  const BlockCard({super.key, required this.block});

  final SessionBlock block;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: skin.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: skin.borderSubtle)),
            ),
            child: Row(
              children: [
                BlockStatusDot(status: block.status),
                const SizedBox(width: 8),
                Expanded(
                  child: AppText(
                    block.title,
                    style: AppTextStyle.style12SemiBold.copyWith(color: skin.textPrimary),
                  ),
                ),
                AppText(
                  _kindLabel(block.kind),
                  style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
                ),
              ],
            ),
          ),
          if (block.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Text(
                block.body,
                softWrap: true,
                style: AppTextStyle.mono12Regular.copyWith(color: skin.textSecondary),
              ),
            ),
          if (block.redacted)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: AppText(
                'Secrets were redacted from this output',
                style: AppTextStyle.style10Regular.copyWith(color: skin.amber),
              ),
            ),
          if (block.truncatedLines > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: AppText(
                '...(truncated)... ${block.truncatedLines} more lines — open Raw for the rest',
                style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
                maxLines: 2,
              ),
            ),
        ],
      ),
    );
  }

  String _kindLabel(BlockKind kind) => switch (kind) {
    BlockKind.prompt => 'you',
    BlockKind.assistant => 'agent',
    BlockKind.tool => 'tool',
    BlockKind.permission => 'permission',
    BlockKind.notice => 'notice',
  };
}
```

- [ ] **Step 5: Write the body**

`packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

class BlocksBody extends StatefulWidget {
  const BlocksBody({super.key});

  @override
  State<BlocksBody> createState() => _BlocksBodyState();
}

class _BlocksBodyState extends State<BlocksBody> {
  final ScrollController _controller = ScrollController();

  bool get _pinned {
    if (!_controller.hasClients) return true;
    return _controller.position.pixels >= _controller.position.maxScrollExtent - 24;
  }

  void _followTail() {
    if (!_controller.hasClients) return;
    _controller.jumpTo(_controller.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<BlocksCubit, BlocksState>(
      builder: (context, state) {
        final cubit = context.read<BlocksCubit>();

        if (state is BlocksUnsupportedState) {
          return _notice(
            context,
            'Blocks are unavailable for ${state.harness ?? 'this agent'}. Use the raw terminal instead.',
          );
        }

        final error = cubit.error;
        if (error != null && cubit.blocks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(
                  error,
                  style: AppTextStyle.style12Regular.copyWith(color: skin.attention),
                  maxLines: 3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                TextButton(onPressed: cubit.refresh, child: const Text('Retry')),
              ],
            ),
          );
        }

        if (cubit.blocks.isEmpty) {
          return _notice(
            context,
            cubit.loading ? 'Loading blocks...' : 'No blocks yet. They appear as the agent works.',
          );
        }

        final pinned = _pinned;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (pinned && mounted) _followTail();
        });

        return ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: cubit.blocks.length,
          itemBuilder: (context, index) {
            final block = cubit.blocks[index];
            return BlockCard(key: ValueKey(block.id), block: block);
          },
        );
      },
    );
  }

  Widget _notice(BuildContext context, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: AppText(
        message,
        style: AppTextStyle.style12Regular.copyWith(color: context.skin.textTertiary),
        maxLines: 4,
        textAlign: TextAlign.center,
      ),
    ),
  );
}
```

`ValueKey(block.id)` is what makes a `tool_complete` updating an existing block reuse its element instead of rebuilding the list — the id being source-minted is what makes that key stable.

- [ ] **Step 6: Run the widget tests**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_body_test.dart
```

Expected: PASS. If `find.textContaining('redacted')` matches twice, it is because the fixture body also contains the word — change the test's block body, not the widget's copy.

- [ ] **Step 7: Gate**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: `No issues found!` and green.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib/feature/blocks/presentation packages/mobile/test/feature/blocks/presentation
git commit -m "feat(mobile): render session blocks"
```

---

## Task 7: Lazy PTY attach, the Raw toggle, and wiring it up

**Why this is the load-bearing task.** The spec's claim that this fixes the phone rests on one sentence: *"in Blocks the client does not join the terminal channel, so it reports no size and appears in no `members` map."* Today `TerminalCubit`'s constructor calls `_mux.openTerminal(args.id, …)` at `terminal_cubit.dart:85`, so merely building the screen joins the channel and starts reporting a grid. Until that is lazy, showing Blocks changes nothing about grid arbitration and the phone still fights the desktop for the PTY's columns and rows.

**What "lazy" means precisely:** `TerminalCubit` may be constructed, subscribed and read from without ever touching the terminal channel. Only `attach()` joins; only `detach()` leaves. `TerminalBody` — the widget that exists exactly when Raw is on screen — owns both calls.

**Files:**
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/raw_terminal_pane.dart`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart:74-98`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart:51`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/session_view_state.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart:95-117`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Modify: `packages/mobile/test/feature/terminal/terminal_harness.dart`
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_screen_test.dart`
- Test: `packages/mobile/test/feature/blocks/presentation/session_view_test.dart`

**Interfaces:**
- Consumes: `TerminalArgs` (`terminal_cubit.dart:24`), `BlocksCubit`/`BlocksBody` (Tasks 5–6), `BlockHarnesses.covers` (Task 4).
- Produces:
  - On `TerminalCubit`: `bool attached`, `void attach()`, `void detach()`. `attach()` is idempotent; `detach()` on a detached cubit is a no-op.
  - `enum SessionViewMode { blocks, raw }`
  - `class SessionViewCubit extends Cubit<SessionViewState>` with `SessionViewCubit(SessionViewMode initial)`, `SessionViewMode get mode`, `void toggle()`
  - `SessionViewMode defaultViewMode(TerminalArgs args)` — `raw` when `args.shellOnly`, else `blocks` when `BlockHarnesses.covers(args.harness)`, else `raw`

**The default, and why it is not "blocks always".** `shellOnly` panes are worktree shells; shell blocks are plan 7, so a shell has nothing to show and must open in Raw. A harness with no registered mapper has no blocks either — it opens in Raw and the Blocks side says why. That satisfies the spec's "Absence is visible, never a silently empty list" without ever opening on an empty screen.

- [ ] **Step 1: Write the failing lazy-attach tests**

Create `packages/mobile/test/feature/blocks/presentation/session_view_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

import '../../terminal/terminal_harness.dart';

void main() {
  group('defaultViewMode', () {
    test('a worktree shell opens raw because shell blocks do not exist yet', () {
      expect(
        defaultViewMode(const TerminalArgs(id: 'h-1', sessionId: 's-1', title: 'Shell', shellOnly: true)),
        SessionViewMode.raw,
      );
    });

    test('a covered harness opens in blocks', () {
      expect(
        defaultViewMode(const TerminalArgs(id: 's-1', sessionId: 's-1', title: 'S', harness: 'claude-code')),
        SessionViewMode.blocks,
      );
    });

    test('an uncovered or unknown harness opens raw', () {
      expect(
        defaultViewMode(const TerminalArgs(id: 's-1', sessionId: 's-1', title: 'S', harness: 'aider')),
        SessionViewMode.raw,
      );
      expect(
        defaultViewMode(const TerminalArgs(id: 's-1', sessionId: 's-1', title: 'S')),
        SessionViewMode.raw,
      );
    });
  });

  group('SessionViewCubit', () {
    test('toggles between the two modes', () {
      final cubit = SessionViewCubit(SessionViewMode.blocks);

      expect(cubit.mode, SessionViewMode.blocks);
      cubit.toggle();
      expect(cubit.mode, SessionViewMode.raw);
      cubit.toggle();
      expect(cubit.mode, SessionViewMode.blocks);
      cubit.close();
    });
  });

  group('TerminalCubit attach', () {
    late TerminalHarness harness;

    setUp(() => harness = TerminalHarness()..start());
    tearDown(() => harness.dispose());

    test('constructing the cubit does not join the terminal channel', () {
      verifyNever(() => harness.mux.openTerminal(any(), projectId: any(named: 'projectId')));
      expect(harness.cubit.attached, isFalse);
    });

    test('attach joins once, however many times it is called', () {
      harness.cubit.attach();
      harness.cubit.attach();

      verify(() => harness.mux.openTerminal('s-1', projectId: null)).called(1);
      expect(harness.cubit.attached, isTrue);
    });

    test('detach leaves, and a second detach is a no-op', () {
      harness.cubit.attach();
      harness.cubit.detach();
      harness.cubit.detach();

      verify(() => harness.mux.closeTerminal('s-1', projectId: null)).called(1);
      expect(harness.cubit.attached, isFalse);
    });

    test('a detached cubit reports no grid, so it cannot drive arbitration', () {
      harness.cubit.reportFit(const TerminalGrid(80, 24));

      verifyNever(() => harness.mux.resize(any(), any(), any(), projectId: any(named: 'projectId')));
    });

    test('an attached cubit does report its grid', () {
      harness.cubit.attach();
      harness.cubit.reportFit(const TerminalGrid(80, 24));

      verify(() => harness.mux.resize('s-1', 80, 24, projectId: null)).called(1);
    });

    test('a detached cubit does not write keystrokes to a PTY it does not hold', () {
      harness.cubit.sendKey('q');

      verifyNever(() => harness.mux.sendInput(any(), any(), projectId: any(named: 'projectId')));
    });

    test('closing a detached cubit does not close a terminal it never opened', () async {
      await harness.cubit.close();

      verifyNever(() => harness.mux.closeTerminal(any(), projectId: any(named: 'projectId')));
    });
  });
}
```

`TerminalGrid` is `packages/mobile/lib/feature/terminal/logic/terminal_fit.dart:6`, constructed positionally as `TerminalGrid(cols, rows)` — verified, so `TerminalGrid(80, 24)` above is 80 columns by 24 rows. `terminal_cubit.dart` does not re-export it, which is why the test imports `terminal_fit.dart` directly.

`flutter analyze` treats an unused import as an issue, and the gate demands `No issues found!` — so import exactly this list and nothing more.

The last test calls `harness.cubit.close()` and then `harness.dispose()` closes it again; `Cubit.close()` is idempotent, but if the suite complains, drop the `tearDown` for that one test by constructing a local harness.

- [ ] **Step 2: Run it and watch it fail**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/session_view_test.dart
```

Expected: compile failure on `SessionViewCubit`/`defaultViewMode`, and — once those exist — a failure on the very first `TerminalCubit` test, because the constructor still calls `openTerminal`.

- [ ] **Step 3: Make the attach lazy**

In `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart`:

Delete line 85, `_mux.openTerminal(args.id, projectId: args.projectId);`, from the constructor body. Leave every other constructor line untouched — the status read, the `onOutput` wiring, the mouse handler, the two subscriptions and the `_emit()` all stay.

Add the field beside `authoritative` (:100):

```dart
  bool attached = false;
```

Add the two methods immediately before `reportFit` (:155):

```dart
  void attach() {
    if (attached) return;
    attached = true;
    _mux.openTerminal(args.id, projectId: args.projectId);
    final fit = _lastFit;
    if (fit != null) _mux.resize(args.id, fit.cols, fit.rows, projectId: args.projectId);
    _emit();
  }

  void detach() {
    if (!attached) return;
    attached = false;
    _reopenTimer?.cancel();
    _mux.closeTerminal(args.id, projectId: args.projectId);
    _emit();
  }
```

Guard the three methods that assume a held PTY. `reportFit` (:155) becomes:

```dart
  void reportFit(TerminalGrid fit) {
    if (_lastFit == fit) return;
    _lastFit = fit;
    if (!attached) return;
    _mux.resize(args.id, fit.cols, fit.rows, projectId: args.projectId);
    if (authoritative) return;
    grid = fit;
    terminal.resize(fit.cols, fit.rows);
    _emit();
  }
```

`_lastFit` is recorded before the guard on purpose: the fit the surface measured while detached is the one `attach()` replays.

`sendKey` (:165) becomes:

```dart
  void sendKey(String sequence) {
    if (!attached) return;
    _mux.sendInput(args.id, sequence, projectId: args.projectId);
  }
```

`_writeToPty` (:230) gains the same guard on its first line:

```dart
  bool _writeToPty(String text) {
    if (!attached || status != MuxStatus.open) return false;
    _mux.sendInput(args.id, terminalPayload(text), projectId: args.projectId);
    return true;
  }
```

`_reopen` (:272) becomes:

```dart
  void _reopen() {
    if (!attached) return;
    _mux.openTerminal(args.id, projectId: args.projectId);
    final fit = _lastFit;
    if (fit != null) _mux.resize(args.id, fit.cols, fit.rows, projectId: args.projectId);
  }
```

And `close()` (:278) stops closing a terminal it may never have opened:

```dart
  @override
  Future<void> close() {
    _reopenTimer?.cancel();
    unawaited(_statusSub?.cancel());
    unawaited(_eventsSub?.cancel());
    if (attached) _mux.closeTerminal(args.id, projectId: args.projectId);
    composer.dispose();
    return super.close();
  }
```

Note `terminal.onOutput` (:81) still writes to the mux directly. It fires only from the `xterm` widget, which exists only inside `TerminalSurface`, which mounts only in Raw — so it cannot fire while detached. Leave it alone rather than adding a fourth guard.

- [ ] **Step 4: Write the view cubit**

`packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/session_view_state.dart`:

```dart
part of 'session_view_cubit.dart';

sealed class SessionViewState extends Equatable {
  const SessionViewState();

  @override
  List<Object?> get props => [];
}

final class SessionViewReadyState extends SessionViewState {
  const SessionViewReadyState(this.mode);

  final SessionViewMode mode;

  @override
  List<Object?> get props => [mode];
}
```

`packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/feature/blocks/logic/block_harnesses.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

part 'session_view_state.dart';

enum SessionViewMode { blocks, raw }

SessionViewMode defaultViewMode(TerminalArgs args) {
  if (args.shellOnly) return SessionViewMode.raw;
  return BlockHarnesses.covers(args.harness) ? SessionViewMode.blocks : SessionViewMode.raw;
}

class SessionViewCubit extends Cubit<SessionViewState> {
  SessionViewCubit(SessionViewMode initial) : super(SessionViewReadyState(initial));

  SessionViewMode get mode => (state as SessionViewReadyState).mode;

  void toggle() => emit(
    SessionViewReadyState(mode == SessionViewMode.blocks ? SessionViewMode.raw : SessionViewMode.blocks),
  );
}
```

- [ ] **Step 5: Extract the raw pane, which is the thing that attaches**

The screen keeps **one composer in both modes** — the spec is explicit: "Blocks are output only. One composer per screen, as in Warp. In `tui` it sends keystrokes through the existing route." So the status bar, the banner, and the composer stay put; only the middle of the screen swaps, and only the middle is what holds a PTY.

Create `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/raw_terminal_pane.dart` with the `Stack` currently inlined in `TerminalBody` at :74-88, plus the attach lifecycle:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_overlay.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_dead_overlay.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_surface.dart';

class RawTerminalPane extends StatefulWidget {
  const RawTerminalPane({super.key});

  @override
  State<RawTerminalPane> createState() => _RawTerminalPaneState();
}

class _RawTerminalPaneState extends State<RawTerminalPane> {
  late final TerminalCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<TerminalCubit>();
    _cubit.attach();
  }

  @override
  void dispose() {
    _cubit.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(child: TerminalSurface()),
      if (context.read<TerminalCubit>().notFound)
        const Positioned.fill(child: TerminalDeadOverlay()),
      BlocBuilder<InterfaceSwitchCubit, InterfaceSwitchState>(
        buildWhen: (previous, current) => current is InterfaceSwitchReadyState,
        builder: (context, _) => context.read<InterfaceSwitchCubit>().active
            ? const Positioned.fill(child: InterfaceSwitchOverlay())
            : const Positioned.fill(child: SizedBox.shrink()),
      ),
    ],
  );
}
```

The cubit is captured in `initState` rather than read in `dispose`: by the time `dispose` runs the element is being unmounted, and caching the reference is the pattern that is safe regardless of teardown order.

- [ ] **Step 6: Branch the middle of `TerminalBody`, and add the toggle**

In `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart`, `TerminalBody` **stays a `StatelessWidget`** and keeps `_confirmKill`, the status bar, the banner and the dock exactly as they are. Two edits:

Replace the `Expanded(child: Stack(…))` at :74-88 with:

```dart
              Expanded(
                child: BlocBuilder<SessionViewCubit, SessionViewState>(
                  builder: (context, _) =>
                      context.read<SessionViewCubit>().mode == SessionViewMode.raw
                      ? const RawTerminalPane()
                      : const BlocksBody(),
                ),
              ),
```

and replace the dock's `children: [TerminalKeyRow(), TerminalComposer()]` at :97 with a version that hides the key row over blocks — those keys drive a PTY this mode does not hold:

```dart
                child: BlocBuilder<SessionViewCubit, SessionViewState>(
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (context.read<SessionViewCubit>().mode == SessionViewMode.raw)
                        const TerminalKeyRow(),
                      const TerminalComposer(),
                    ],
                  ),
                ),
```

The `BlocBuilder` here is not decoration. The enclosing `BlocBuilder<TerminalCubit, TerminalState>` at :45 rebuilds on terminal state only, so without its own listener the key row would keep its old visibility after a mode toggle — a bug that looks like the toggle "sometimes not working". The `Expanded` above needs its own for the same reason.

Drop the now-unused imports of `interface_switch_cubit.dart`, `interface_switch_overlay.dart`, `terminal_dead_overlay.dart` and `terminal_surface.dart` from `terminal_body.dart` — `flutter analyze` will name each one if you miss it — and add imports for `RawTerminalPane`, `BlocksBody` and `SessionViewCubit`.

**The composer while detached, stated plainly.** `TerminalComposer` calls `TerminalCubit.send()` (:183). For a non-shell session `sendTarget` is `SendTarget.agent` (:78), so a send goes over REST via `sendSessionMessage` and works untouched in Blocks. If it falls back to the terminal route, `_writeToPty` now returns `false` while detached and the user sees the existing `kTerminalUnavailableNotice` banner rather than a silently swallowed message. That is the correct outcome: there is no PTY to write to.

- [ ] **Step 6b: Add the toggle to the app bar**

In `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart`, add to `actions` (:51) ahead of `TerminalPreviewGlobe`:

```dart
            if (!args.shellOnly)
              BlocBuilder<SessionViewCubit, SessionViewState>(
                builder: (context, state) {
                  final blocks = context.read<SessionViewCubit>().mode == SessionViewMode.blocks;
                  return Semantics(
                    button: true,
                    label: blocks ? 'Show raw terminal' : 'Show blocks',
                    child: IconButton(
                      onPressed: context.read<SessionViewCubit>().toggle,
                      icon: Icon(
                        blocks ? Icons.terminal : Icons.view_agenda_outlined,
                        size: 18,
                        color: context.skin.blue,
                      ),
                    ),
                  );
                },
              ),
```

`body: const TerminalBody(),` at :69 does **not** change. Leave `final args = context.read<TerminalCubit>().args;` at :41 as it is — reading the cubit no longer joins the terminal channel, which is the entire point of Step 3.

**The trade-off, stated rather than hidden:** flipping to Blocks unmounts `RawTerminalPane`, which detaches the PTY; flipping back re-attaches and the daemon repaints. `TerminalCubit` and its `Terminal` object survive, so nothing about the session is lost, but the visible scrollback is whatever the repaint produces. This is not avoidable — the spec requires Blocks to hold no terminal attachment, and an attachment is what a grid report is.

- [ ] **Step 7: Wire the route**

In `packages/mobile/lib/core/app_routes/app_router.dart`, in the `RoutesStrings.terminal` case (:95-117), add two providers to the `MultiBlocProvider`, after the existing `TerminalCubit` provider (:102):

```dart
              BlocProvider<SessionViewCubit>(
                create: (_) => sl<SessionViewCubit>(param1: terminalArgs),
              ),
              if (!terminalArgs.shellOnly)
                BlocProvider<BlocksCubit>(
                  create: (_) => sl<BlocksCubit>(
                    param1: terminalArgs.sessionId,
                    param2: terminalArgs.harness,
                  ),
                ),
```

`BlocProvider(create:)` is lazy, so `BlocksCubit` is not constructed — and does not subscribe or fetch — until `BlocksBody` first reads it. A `shellOnly` route provides no `BlocksCubit` at all, which is safe because `defaultViewMode` pins a shell to Raw and the toggle is hidden for shells.

In `packages/mobile/lib/core/utils/service_locator.dart`, add to `_blocksFeatureSetup()`:

```dart
    sl.registerFactoryParam<SessionViewCubit, TerminalArgs, void>(
      (args, _) => SessionViewCubit(defaultViewMode(args)),
    );
```

- [ ] **Step 8: Extend the terminal harness**

`packages/mobile/test/feature/terminal/terminal_harness.dart` gains a `SessionViewCubit` and a `BlocksCubit` so a pumped `TerminalScreen` finds both.

**Provide both with `BlocProvider.value`, not through `sl`.** The existing `VoiceInputCubit` and `PreviewCubit` registrations are guarded by `if (!sl.isRegistered<…>())` (:65, :70) and survive across every test in the run — which is fine for them because their closures capture nothing from the harness instance. A `BlocksCubit` factory would capture *this* harness's `mux`, so the first harness's mock would be handed to every later one and the toggle tests would verify against a mux nobody is driving. Build it per-harness instead.

Add beside the other mocks (:23-32):

```dart
class MockBlocksRepository extends Mock implements BlocksRepository {}
```

Add the fields beside `cubit` (:62):

```dart
  late SessionViewCubit viewCubit;
  late BlocksCubit blocksCubit;
```

Add the stream controllers beside `statuses` and `events` (:59-60):

```dart
  final StreamController<BlockEventEnvelope> blockEvents =
      StreamController<BlockEventEnvelope>.broadcast();
  final StreamController<List<SessionPatch>> sessionPatches =
      StreamController<List<SessionPatch>>.broadcast();
```

Add these mux stubs to the existing block at :84-90:

```dart
    when(() => mux.blockEvents).thenAnswer((_) => blockEvents.stream);
    when(() => mux.sessionPatches).thenAnswer((_) => sessionPatches.stream);
    when(() => mux.subscribeBlocks(any())).thenReturn(null);
    when(() => mux.unsubscribeBlocks(any())).thenReturn(null);
```

At the top of `start()`, beside the other guards:

```dart
    registerFallbackValue(const GetSessionBlocksParams());
```

After `cubit = TerminalCubit(…)` (ends :114), build the two new cubits:

```dart
    final blocksRepository = MockBlocksRepository();
    when(() => blocksRepository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));

    viewCubit = SessionViewCubit(defaultViewMode(cubit.args));
    blocksCubit = BlocksCubit(mux, blocksRepository, cubit.args.sessionId, harness: harness);
```

Add both to `pump`'s providers (:126-131):

```dart
                  BlocProvider<SessionViewCubit>.value(value: viewCubit),
                  BlocProvider<BlocksCubit>.value(value: blocksCubit),
```

Close them in `dispose` (:143-147), before the existing closes:

```dart
    await viewCubit.close();
    await blocksCubit.close();
    await blockEvents.close();
    await sessionPatches.close();
```

Add the imports the harness now needs: `dart:async` is already there (:1); add `package:operator_mobile/core/mux/session_patch.dart`, `…/feature/blocks/data/model/block_event_model.dart`, `…/feature/blocks/data/model/params/get_session_blocks_params.dart`, `…/feature/blocks/data/repository/blocks_repository.dart`, `…/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart`, and `…/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart`. `Result` and `mocktail` are already imported (:11, :8).

**Why the existing terminal screen tests keep passing:** `TerminalHarness.start()` builds `TerminalArgs(id: 's-1', sessionId: 's-1', title: 'Session', harness: harness)` with `harness` defaulting to `null` (:113), so `defaultViewMode` returns `raw` and every existing test still lands on `RawTerminalPane` and its `TerminalSurface`. Do not change that default — a test that wants Blocks passes `harness: 'claude-code'`.

- [ ] **Step 9: Add the screen-level tests**

Append to `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_screen_test.dart`:

```dart
  testWidgets('a covered harness opens in blocks and never joins the terminal channel', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(harness: 'claude-code');
    await harness.pump(tester, const TerminalScreen());

    expect(find.byType(BlocksBody), findsOneWidget);
    expect(find.byType(TerminalSurface), findsNothing);
    verifyNever(() => harness.mux.openTerminal(any(), projectId: any(named: 'projectId')));
    verifyNever(() => harness.mux.resize(any(), any(), any(), projectId: any(named: 'projectId')));
  });

  testWidgets('the toggle swaps to raw, which is what joins the channel', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(harness: 'claude-code');
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Show raw terminal'));
    await tester.pumpAndSettle();

    expect(find.byType(TerminalSurface), findsOneWidget);
    verify(() => harness.mux.openTerminal('s-1', projectId: null)).called(1);
  });

  testWidgets('toggling back to blocks leaves the terminal channel again', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(harness: 'claude-code');
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Show raw terminal'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Show blocks'));
    await tester.pumpAndSettle();

    expect(find.byType(BlocksBody), findsOneWidget);
    verify(() => harness.mux.closeTerminal('s-1', projectId: null)).called(1);
  });

  testWidgets('a worktree shell has no blocks toggle and opens raw', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
    await harness.pump(tester, const TerminalScreen());

    expect(find.byType(TerminalSurface), findsOneWidget);
    expect(find.bySemanticsLabel('Show blocks'), findsNothing);
    expect(find.bySemanticsLabel('Show raw terminal'), findsNothing);
  });
```

Import `BlocksBody`.

- [ ] **Step 10: Run the terminal and blocks suites**

```bash
cd packages/mobile && flutter test test/feature/terminal/ test/feature/blocks/
```

Expected: PASS, including every pre-existing terminal screen test.

- [ ] **Step 11: Full mobile gate**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: `No issues found!` and the whole suite green.

- [ ] **Step 12: Backend gate, because Task 1 touched it**

```bash
npm run lint
```

From the repo root. Expected: 0 issues.

- [ ] **Step 13: Commit**

```bash
git add packages/mobile
git commit -m "feat(mobile): show session blocks with a raw terminal toggle"
```

---

## Wrap-up

- [ ] **Confirm the phone no longer sizes the grid.** The claim this plan exists to deliver is that a phone in Blocks reports no grid. Three tests pin it: `'a detached cubit reports no grid, so it cannot drive arbitration'` (Task 7 Step 1), `'a covered harness opens in blocks and never joins the terminal channel'` and `'toggling back to blocks leaves the terminal channel again'` (Task 7 Step 9). If any of those is weakened during implementation, the plan has not been delivered.

- [ ] **Report the known gaps** from the section at the top of this plan — virtualization, block actions, shell blocks, transcript enrichment, actionable permissions, and the re-attach-on-toggle trade-off — as remaining work, not as omissions.

- [ ] **Confirm the spec's plan index still points here.** Row 2 of the table in `docs/superpowers/specs/2026-08-27-session-blocks-design.md` should read `2026-08-27-mobile-block-screen.md` / `written`. It was set when this plan was written; if a merge lost it, restore it.

- [ ] **Note for plan 3 (desktop).** The four `testdata/blocks/assembly_*.json` fixtures are the contract. Plan 3's TypeScript assembly asserts against the same files, unchanged. If the desktop port needs a rule this plan did not specify, the rule is added here and both suites re-run — the fixture is never edited to match one client.
