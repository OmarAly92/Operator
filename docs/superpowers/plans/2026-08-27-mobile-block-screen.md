# Mobile Block Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the phone a readable session view that has no terminal grid — a scrolling list of blocks assembled from the daemon's normalized block-event stream — reachable by a toggle beside the existing raw terminal.

**Architecture:** Plan 1 already captures, redacts, persists and live-publishes block events (`ch: "blocks"` on `/mux`). This plan adds the one missing daemon read path (a REST endpoint for the persisted log), teaches the Flutter `MuxClient` the `blocks` channel, adds a `feature/blocks/` package holding the wire model, a pure assembly function, a cubit and the widgets, and makes the existing `TerminalCubit` attach to the PTY **lazily** so that showing Blocks genuinely leaves the terminal channel.

**Tech Stack:** Go 1.x + chi + sqlc (daemon); Flutter 3.44.5, flutter_bloc (Cubit only), equatable, get_it, mocktail, fake_async (mobile).

**Spec:** `docs/superpowers/specs/2026-08-27-session-blocks-design.md` — spec steps 2 (mobile mux), 3 (shared block model and assembly, hook adapter), 4 (mobile block screen and the Raw toggle).

**Depends on:** Plan 1, `docs/superpowers/plans/2026-08-27-block-pipeline-backend.md`, merged at `0a84b7f49`. Everything it produced is on `master` already; do not re-implement any of it.

**This plan also closes what plan 1 left open.** Plan 1 delivered capture, redaction, persistence and live publication, but five things the spec's steps 1 and 2 require were either parked or never wired. Tasks 1 through 5 close them, in dependency order, before any Flutter code is written:

| Gap | Effect if left open | Task |
| --- | --- | --- |
| No REST read path for the persisted log | A client joining mid-session or recovering from a dropped socket sees only what arrives next | 1 |
| A `blocks` subscribe with no counterpart | The daemon pushes every session a phone ever opened down that socket for the life of the connection | 1 |
| The harness never reaches `blockdispatch` reliably | **Every grok event, and every claude-code event without usage metadata, records `kind: "unknown"`** — the block list becomes a list of generic notices | 2 |
| `toolInput`, `errorType`, `hookVersion` unpopulated | Permission blocks cannot say what was asked; a failed tool is indistinguishable from a successful one; there is no forward-compatibility signal | 2, 3 |
| No backward page query | The client's bounded window drops old blocks with no way to get them back | 4 |
| Redaction patterns not user-extensible | A house token shape Operator does not know still reaches the phone and sqlite | 5 |

The third row is the one that matters most: it is not a missing feature, it is a defect that makes plan 2's UI wrong in the ordinary case. Read Task 2 before starting anything.

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

- **Backend (Tasks 1-5):** from the repo root, `npm run lint` (runs `go test ./...` plus golangci-lint v2.12.2). During a task, `cd backend && go test ./internal/<pkg>/ -race -v`.
- **Anything touching the REST surface** — Tasks 1, 2 and 4 — must also run `npm run api` from the repo root, which regenerates `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts`. Commit both.
- **Anything touching `queries/` or `migrations/`** — Tasks 2 and 4 — must run `npm run sqlc` from the repo root. **Never hand-edit `backend/internal/storage/sqlite/gen/`.**
- **Mobile (Tasks 6–11):** from `packages/mobile`, `flutter analyze` must print exactly `No issues found!`, and `flutter test` must be green. CI (`.github/workflows/mobile-flutter.yml`) pins Flutter **3.44.5** and runs exactly those two.
- Single-file / single-test runs during a task: `flutter test test/path/to/file_test.dart`, `flutter test --plain-name 'substring of name'`.
- Native code is covered by neither gate; this plan touches no `ios/`, `android/`, or vendored package platform code.

## Existing test harnesses — use these, do not write a second one

- **HTTP controllers.** Build a server with
  `httptest.NewServer(httpd.NewRouterWithControl(config.Config{}, log, nil, httpd.APIDeps{…}, httpd.ControlDeps{}))`.
  Issue requests with `doRequest`, at `backend/internal/httpd/controllers/projects_test.go:522`, signature
  `(t *testing.T, srv *httptest.Server, method, path, body string) ([]byte, int, http.Header)`.
  Task 1 extends `newBlockEventsTestServer` at `backend/internal/httpd/controllers/sessions_block_events_test.go:34` rather than adding a new server helper.
- **Mux manager (Go).** `newFakeConn()` (no arguments) and `recv(t, c, ch, typ string, d time.Duration) serverMsg`, both in `backend/internal/terminal/manager_test.go`. Drive a connection with `go m.Serve(ctx, conn)` then `conn.in <- clientMsg{…}`. `Serve` reads on its own goroutine, so anything published immediately after a subscribe frame races — **poll `m.blockSubscriberCount(sessionID)` before asserting**, never `sleep`.
- **Mux client (Dart).** `_FakeMuxSocket` and `_StubSource` in `packages/mobile/test/core/mux/mux_client_test.dart`. They are private to that file; Task 6's tests go in that same file so they can reuse them.
- **Mobile terminal.** `packages/mobile/test/feature/terminal/terminal_harness.dart`. Task 11 extends it; it must not be forked.

## The shared fixture contract

`testdata/blocks/` at the **repo root** holds the event-stream fixtures both clients assert against. Plan 1 landed three signal→record fixtures there (`hook_stream_basic.json`, `hook_stream_unknown_event.json`, `hook_stream_secrets.json`) which the Go suite reads. Task 3 adds a fourth (`hook_stream_tool_failure.json`), and Task 8 adds six **record→block** fixtures (`assembly_*.json`) which the Dart suite reads and which plan 3 (desktop) will assert against unchanged.

**The prefix decides which suite owns a file.** `hook_stream_*.json` are signal-to-record fixtures asserted by Go (`backend/internal/service/blockevent/fixtures_test.go`); `assembly_*.json` are record-to-block fixtures asserted by Dart here and by TypeScript in plan 3. Plan 1's Go test currently claims **every** file in the directory and must be narrowed to its prefix before any `assembly_*` file is added — Task 8 does this as its first step, and skipping it fails the backend suite.

A failing fixture is **never** fixed by editing the fixture.

From `packages/mobile`, the repo root is `../..`, so a Dart test opens `File('../../testdata/blocks/assembly_turn.json')`.

## Known gaps this plan deliberately does not close

State them in the final report; do not silently expand scope to fix them.

- **Virtualization, height caching, append anchoring under load, sticky headers, block-boundary navigation** are spec step 6 / plan 4. Task 10 here ships a plain `ListView.builder` with a simple pinned-to-bottom rule. That is correct but not fast, which is exactly the ordering the spec asks for: "blocks are correct before they are fast."
- **Block actions (copy, re-run, collapse), selection and find** are plan 6.
- **Shell blocks** are plan 7; a `shellOnly` terminal therefore has no Blocks mode at all in this plan and must default to Raw.
- **Transcript enrichment** is plan 8. `tui` block bodies here are what the hook reported, truncated at 16 KiB by the daemon and, for the tool-input preview, at 2 KiB by the CLI.
- **`ErrorType` carries one value, `tool_failed`.** Task 3 sets it from the event name. Richer error taxonomy — which tool, which failure class — needs the native payload's error object, which no harness in this repo exposes uniformly. One value is enough to make `BlockStatus.failed` reachable, which is the requirement.
- **Redaction patterns are loaded once, at daemon start.** Editing `~/.operator/redact-patterns.txt` needs a daemon restart. Watching the file is not worth a file watcher on the hook path.
- **The two-client grid-arbitration test is plan 3's.** The spec calls for a test that a desktop in Blocks and a phone in Raw makes the phone the sole sizer. That needs both clients, so it lands with the desktop plan. What this plan pins is the half it owns: a phone in Blocks holds no attachment and reports no size.
- **Permission blocks are rich and notifying, not actionable** (Phase A). No approve/deny control. Acting on one means switching to Raw.
- **Redaction spans are marked, not rendered inline.** A block that had a secret removed shows a marker; highlighting the exact span inside the body needs the selection machinery of plan 6. The mask itself is visible in the text either way, which is what the spec requires.
- **Switching Blocks → Raw → Blocks re-attaches the PTY.** The daemon's own comment at `backend/internal/terminal/manager.go:42` — "the runtime owns the session (screen, scrollback, modes), and every fresh attach gets its full handshake + repaint" — is why this is safe. The Dart `Terminal` object survives the toggle because `TerminalCubit` is not disposed.

---

## File Structure

### Backend (Tasks 1-5)

| File | Responsibility |
| --- | --- |
| `backend/internal/httpd/controllers/sessions.go` | Add `BlockEventHistory` interface, `BlockHistory` field, `listBlockEvents` handler, one route |
| `backend/internal/httpd/controllers/dto.go` | `ListSessionBlockEventsResponse`, `BlockEventView`, `BlockRedactedSpanView`, `blockEventViews` |
| `backend/internal/httpd/api.go` | `BlockHistory` on `APIDeps`, passed to the controller literal |
| `backend/internal/daemon/daemon.go` | Wire the same `*blockevent.Service` into `BlockHistory` |
| `backend/internal/httpd/apispec/specgen/build.go` | `sessionBlocksQuery` + one operation entry |
| `backend/internal/terminal/protocol.go` | `msgUnsubscribe` constant |
| `backend/internal/terminal/manager.go` | Handle the unsubscribe frame in `handleBlockSubscribe` |
| `backend/internal/cli/hooks.go` | Send `harness`, `toolInput`, `hookVersion` from every hook |
| `backend/internal/ports/runtime_observations.go` | `ActivitySignal.Harness`, `.ToolInput`, `.HookVersion` |
| `backend/internal/adapters/agent/blockdispatch/dispatch.go` | `Decision` — a handler that can drop and can report a failure, not just rename |
| `backend/internal/service/blockevent/service.go`, `types.go` | Honour the decision; redact and carry the tool input; `HistoryBefore` |
| `backend/internal/storage/sqlite/migrations/0091_block_event_tool_input.sql` | One new column |
| `backend/internal/storage/sqlite/queries/block_events.sql`, `store/block_event_store.go` | `tool_input`, and the backward page query |
| `backend/internal/redact/userpatterns.go` | Load the user's own secret shapes from the data dir |
| `backend/internal/service/blockevent/fixtures_test.go` | Narrowed to `hook_stream_*`, and asserts `errorType` |
| `testdata/blocks/hook_stream_tool_failure.json` | Pins the failed-tool mapping for both clients |
| `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`, `backend/internal/storage/sqlite/gen/` | Regenerated by `npm run api` and `npm run sqlc` — never hand-edited |

### Mobile

| File | Responsibility |
| --- | --- |
| `lib/core/mux/mux_client.dart` | `blocks` channel: `BlockEventEnvelope`, `blockEvents` stream, subscribe/unsubscribe, resubscribe on reconnect |
| `lib/feature/blocks/data/model/block_event_model.dart` | The wire record, all fields nullable |
| `lib/feature/blocks/data/model/params/get_session_blocks_params.dart` | Query params: `afterSeq` forward, `beforeSeq` backward, `limit` |
| `lib/feature/blocks/data/data_source/blocks_remote_data_source.dart` | The REST call |
| `lib/feature/blocks/data/repository/blocks_repository.dart` | Network guard + `Result` wrapping |
| `lib/feature/blocks/logic/session_block.dart` | `SessionBlock`, `BlockKind`, `BlockStatus` — the shared block model |
| `lib/feature/blocks/logic/block_assembly.dart` | `assembleBlocks`, `resolveStranded` — pure, no Flutter imports |
| `lib/feature/blocks/logic/block_harnesses.dart` | Which harnesses have hook coverage |
| `lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart` + `blocks_state.dart` | Subscribe, backfill, merge by seq, bounded growable window, backward paging, reconnect refetch |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart` | The list, its states, pinned-to-bottom rule, load-older control |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart` | One block |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart` | Status colour, shared by card and future callers |
| `lib/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart` + `session_view_state.dart` | Blocks-vs-Raw for one screen |
| `lib/feature/terminal/presentation/terminal_screen/ui/widgets/raw_terminal_pane.dart` | The raw surface, and the only thing that holds a PTY |
| `lib/core/api/api_request_helpers/end_points.dart` | `sessionBlocks(String)` |
| `lib/core/utils/service_locator.dart` | `_blocksFeatureSetup()` |
| `lib/core/app_routes/app_router.dart` | Provide `SessionViewCubit` and `BlocksCubit` on the terminal route |
| `lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart` | Lazy `attach()`/`detach()` |
| `lib/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart` | The toggle; branch on view mode |
| `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart` | Becomes stateful so it can attach/detach |

### Fixtures (Task 8)

`testdata/blocks/assembly_turn.json`, `assembly_permission.json`, `assembly_out_of_order.json`, `assembly_truncation.json`, `assembly_tool_failure.json`, `assembly_question.json`.

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
- Produces, for Task 7: `GET /api/v1/sessions/{sessionId}/blocks?afterSeq=<int64>&limit=<int>` returning `200 {"blocks":[BlockEventView…]}` ascending by `seq`; `404` with code `SESSION_NOT_FOUND` is **not** produced (the log is keyed by id alone and an unknown id returns an empty list); `501` when `BlockHistory` is nil. `BlockEventView` JSON keys are exactly: `seq`, `sessionId`, `sourceId`, `kind`, `rawEvent`, `harness`, `toolName`, `toolUseId`, `text`, `redactedSpans` (`[{start,end}]`), `errorType`, `hookVersion`, `truncatedLines`, `createdAt` (RFC3339).
- Produces, for Task 6: client frame `{"ch":"blocks","id":"<sessionId>","type":"unsubscribe"}` removes that subscription.

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

## Task 2: Carry the harness and the rich hook fields end-to-end

**Why this is first among the gap-closing tasks: without it, plan 2's UI is wrong in the common case.** `blockdispatch.Map(harness, event)` returns `BlockEventUnknown` for an unregistered harness (`dispatch.go:51-56`). The harness reaching it is derived in `sessions.go:1329-1332` from `in.Usage.Harness` alone — and `Usage` is built by `hookUsageMetadata` (`internal/cli/hooks.go:136`), which returns **nil** for any harness other than claude-code and codex, and **also nil** for those two when the native payload happens to carry no `transcript_path`, `model` or `agent_id`. So:

- Every **grok** hook records `kind: "unknown"`, although `blockdispatch.Mappers` has a grok entry.
- Every **claude-code** hook whose payload lacks usage metadata — `user-prompt-submit` among them — records `kind: "unknown"` too.

The `agent` token is right there in `runHook` (`internal/cli/hooks.go:288-311`); it is simply never sent as a field of its own. The result is a block list of generic notices instead of prompts, tools and stops. Plan 1 shipped this; plan 2 cannot render correctly around it.

**Why plan 1's tests are green anyway, which is the lesson here.** `TestSharedFixtures` (`backend/internal/service/blockevent/fixtures_test.go:33`) calls `svc.Record(ctx, "s-1", fixture.Harness, ...)` — it passes the harness in **directly**, bypassing the controller that has to derive it. Every layer was tested in isolation and every layer passed; the seam between them was never exercised. The controller test in Step 7 below closes that specific hole, and it is the one assertion in this task that must not be dropped.

The same request is the right place to close the three record fields the spec's step 1 lists that nothing populates. The spec's agent-event capture is: "session id, monotonic sequence, event name, tool name, tool use id, **tool input preview**, text, **error type**, harness, **hook schema version**, timestamp." `Record` reserves `ErrorType` and `HookVersion` (`types.go:29-33`) and has no tool-input field at all.

**Scope boundary:** this task moves data. Deriving `ErrorType` and acting on it is Task 3; do not do it here.

**Files:**
- Modify: `backend/internal/cli/hooks.go` (:43-54 request struct, :91-103 `activityMeta`, :288-311 request assembly)
- Modify: `backend/internal/httpd/controllers/dto.go:787-798`
- Modify: `backend/internal/ports/runtime_observations.go:41-67`
- Modify: `backend/internal/httpd/controllers/sessions.go:1306-1333`
- Modify: `backend/internal/service/blockevent/service.go:72-86`
- Modify: `backend/internal/storage/sqlite/queries/block_events.sql`, `backend/internal/storage/sqlite/store/block_event_store.go`, and a new migration
- Test: `backend/internal/cli/hooks_test.go`, `backend/internal/httpd/controllers/sessions_block_events_test.go`, `backend/internal/service/blockevent/service_test.go`, `backend/internal/storage/sqlite/store/block_event_store_test.go`
- Regenerated: `backend/internal/storage/sqlite/gen/`, `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`

**Interfaces:**
- Produces, for Task 3: `ports.ActivitySignal.Harness`, `.ToolInput`, `.HookVersion` (all `string`).
- Produces, for Task 7: `BlockEventView.toolInput` (`string`, `omitempty`) and a `hookVersion` that is actually populated.
- Produces, on the wire: `POST /api/v1/sessions/{id}/activity` accepts `harness`, `toolInput`, `hookVersion`.

**The hook schema version, defined rather than hand-waved.** There is no version field in any native agent payload — claude-code and codex do not emit one. The producer that *does* know its own contract is Operator's own `opr hooks`, so the CLI stamps it: `hookVersion: "1"`. That is exactly the case the spec's error handling describes — "a hook schema version newer than the daemon understands is recorded and surfaced; known fields still parse" — because the failure mode in this repo is a user whose `opr` binary is newer than the daemon it reports to. Do not invent a per-harness version scheme.

**Bounding the tool input.** `toolInput` is a *preview*, not the whole input: a `Write` tool's input is an entire file. Cap it at **2 KiB** in the CLI, before it ever leaves the machine, and cap it again in the controller. It goes through `redact.Text` in the service like every other text field, because a tool input is one of the likeliest places for a credential to appear.

- [ ] **Step 1: Write the failing CLI test**

Append to `backend/internal/cli/hooks_test.go`. Read the file's existing hook tests first — they already build a `commandContext` with a fake HTTP server and decode the posted `setActivityAPIRequest`; reuse that harness and match its style exactly rather than inventing a second one. The assertions to add:

```go
func TestRunHookSendsHarnessForEveryAgent(t *testing.T) {
	for _, agent := range []string{"claude-code", "codex", "grok"} {
		t.Run(agent, func(t *testing.T) {
			req := postActivityForTest(t, agent, "user-prompt-submit", []byte(`{"prompt":"go"}`))
			if req.Harness != agent {
				t.Fatalf("harness = %q, want %q — an unset harness makes every block kind unknown", req.Harness, agent)
			}
		})
	}
}

func TestRunHookStampsItsSchemaVersion(t *testing.T) {
	req := postActivityForTest(t, "claude-code", "stop", []byte(`{}`))
	if req.HookVersion != hookSchemaVersion {
		t.Fatalf("hookVersion = %q, want %q", req.HookVersion, hookSchemaVersion)
	}
}

func TestRunHookSendsATruncatedToolInputPreview(t *testing.T) {
	payload := []byte(`{"tool_name":"Bash","tool_use_id":"tu-1","tool_input":{"command":"ls -la"}}`)
	req := postActivityForTest(t, "claude-code", "post-tool-use", payload)
	if !strings.Contains(req.ToolInput, "ls -la") {
		t.Fatalf("toolInput = %q, want it to carry the command", req.ToolInput)
	}

	big := `{"tool_name":"Write","tool_input":{"content":"` + strings.Repeat("x", 8<<10) + `"}}`
	req = postActivityForTest(t, "claude-code", "post-tool-use", []byte(big))
	if len(req.ToolInput) > maxHookToolInputLen {
		t.Fatalf("toolInput = %d bytes, want at most %d", len(req.ToolInput), maxHookToolInputLen)
	}
	if len(req.ToolInput) == 0 {
		t.Fatal("an oversized tool input was dropped entirely, want a truncated preview")
	}
}

func TestRunHookToolInputSurvivesAMissingField(t *testing.T) {
	req := postActivityForTest(t, "claude-code", "post-tool-use", []byte(`{"tool_name":"Bash"}`))
	if req.ToolInput != "" {
		t.Fatalf("toolInput = %q, want empty when the payload carries none", req.ToolInput)
	}
}
```

`postActivityForTest(t, agent, event, payload) setActivityAPIRequest` is a helper you write **once** at the bottom of the test file, wrapping whatever server-and-context setup the neighbouring tests already use. If an equivalent helper already exists there under another name, use it and delete this one — do not add a second.

- [ ] **Step 2: Run it and watch it fail**

```bash
cd backend && go test ./internal/cli/ -run TestRunHook -v
```

Expected: compile failure on `req.Harness`, `req.HookVersion`, `req.ToolInput`, `hookSchemaVersion`, `maxHookToolInputLen`.

- [ ] **Step 3: Send the fields from the CLI**

In `backend/internal/cli/hooks.go`, add beside `maxHookInteractionLen` (:80-82):

```go
// hookSchemaVersion is the version of the activity body this CLI emits. The
// daemon records it so a report from an `opr` newer than the daemon is visible
// as a version rather than as silently missing fields.
const hookSchemaVersion = "1"

// maxHookToolInputLen bounds the tool-input preview. A Write tool's input is a
// whole file; this is a preview for a block header, not a copy of the input.
const maxHookToolInputLen = 2 << 10
```

Add the three fields to `setActivityAPIRequest` (:43-54):

```go
	Harness     string `json:"harness,omitempty"`
	ToolInput   string `json:"toolInput,omitempty"`
	HookVersion string `json:"hookVersion,omitempty"`
```

Widen `activityMeta` (:91-103) to lift the input too, keeping its existing over-length rejection for the two ids and *truncating* rather than rejecting the preview:

```go
func activityMeta(payload []byte) (toolName, toolUseID, toolInput string) {
	var p struct {
		ToolName  string          `json:"tool_name"`
		ToolUseID string          `json:"tool_use_id"`
		ToolInput json.RawMessage `json:"tool_input"`
	}
	_ = json.Unmarshal(payload, &p)
	if len(p.ToolName) > maxActivityMetaLen {
		p.ToolName = ""
	}
	if len(p.ToolUseID) > maxActivityMetaLen {
		p.ToolUseID = ""
	}
	return p.ToolName, p.ToolUseID, capHookText(string(p.ToolInput), maxHookToolInputLen)
}
```

`json.RawMessage` keeps the input as its original JSON regardless of whether the agent sends an object, a string or an array — decoding into a typed shape would drop everything that does not match. `capHookText` at `internal/cli/hooks.go:215` is the existing helper — verified: it trims, sanitizes control characters, and when over the limit splices `[... truncated by Operator ...]` into the **middle**, keeping a head and a tail. That is the same shape as Warp's `TRUNCATION_MESSAGE`, and it is why the oversized-input test above asserts the preview is non-empty rather than asserting a prefix.

**The preview is a display string, not JSON.** Sanitizing and middle-splicing a JSON object produces something that no longer parses. That is intentional: the field exists so a permission block can show what the agent asked to do. No client may `jsonDecode` it, and Task 8's assembly treats it as opaque text.

Update the two call sites of `activityMeta` — `runHook` at :295 and `runReviewHook` if it calls it — to the three-value form, and add the fields to the request at :302-312:

```go
	toolName, toolUseID, toolInput := activityMeta(payload)
```

```go
		Harness:               agent,
		ToolInput:             toolInput,
		HookVersion:           hookSchemaVersion,
```

`agent` is `runHook`'s own parameter and is already validated upstream — the function returns early for an unknown agent at :290-292.

- [ ] **Step 4: Run the CLI tests**

```bash
cd backend && go test ./internal/cli/ -run TestRunHook -v
```

Expected: PASS.

- [ ] **Step 5: Widen the daemon's request DTO and signal**

`backend/internal/httpd/controllers/dto.go`, in `SetActivityRequest` (:787-798):

```go
	Harness               string             `json:"harness,omitempty" description:"Agent token from opr hooks <agent> <event>. Authoritative for block-event mapping; the usage block's harness is only a fallback for older CLIs."`
	ToolInput             string             `json:"toolInput,omitempty" maxLength:"2048" description:"Preview of the native tool input, for tool-use and permission hook events."`
	HookVersion           string             `json:"hookVersion,omitempty" description:"Schema version of the body the reporting opr CLI emits."`
```

`backend/internal/ports/runtime_observations.go`, in `ActivitySignal` (:41-67):

```go
	// Harness is the agent token the hook reported itself under. It is what
	// blockdispatch keys on; an empty harness maps every event to unknown.
	Harness string
	// ToolInput is a bounded preview of the native tool input. It is redacted
	// before it is persisted or transmitted, like every other text field.
	ToolInput string
	// HookVersion is the reporting CLI's body-schema version.
	HookVersion string
```

Nothing existing reads these, so no other implementation of any port changes.

- [ ] **Step 6: Populate them in the controller**

In `backend/internal/httpd/controllers/sessions.go`, add to the `ports.ActivitySignal` literal (:1306-1317):

```go
		Harness:               capActivityMeta(domain.SanitizeControlChars(strings.TrimSpace(in.Harness))),
		ToolInput:             capActivityText(domain.SanitizeControlChars(in.ToolInput), 2<<10),
		HookVersion:           capActivityMeta(domain.SanitizeControlChars(strings.TrimSpace(in.HookVersion))),
```

and replace the harness derivation at :1328-1333 so the explicit field wins and `Usage` stays a fallback for a CLI older than Task 2:

```go
	if c.BlockEvents != nil && sig.Event != "" {
		harness := sig.Harness
		if harness == "" && in.Usage != nil {
			harness = capActivityMeta(domain.SanitizeControlChars(strings.TrimSpace(string(in.Usage.Harness))))
		}
		if err := c.BlockEvents.Record(r.Context(), sessionID(r), harness, sig); err != nil {
```

Leave the rest of that block — the `slog` warn and its arguments — exactly as it is.

`capActivityMeta` and `capActivityText` already exist in this file; find them before writing this step and match their signatures.

- [ ] **Step 7: Write the failing controller, store and service tests**

**The controller test first — it is the one that would have caught this.** Append to `backend/internal/httpd/controllers/sessions_block_events_test.go`, extending the existing `fakeBlockEventRecorder` at :18 with a `gotHarness string` field set inside its `Record` method:

```go
func TestActivityPassesTheReportedHarnessToBlockEvents(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	body := `{"state":"active","event":"user-prompt-submit","harness":"grok","latestUserPrompt":"go"}`
	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-1/activity", body)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.gotHarness != "grok" {
		t.Fatalf("harness = %q, want grok — without it every block kind is unknown", rec.gotHarness)
	}
}

func TestActivityFallsBackToTheUsageHarness(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	body := `{"state":"active","event":"stop","usage":{"harness":"claude-code","transcriptPath":"/tmp/t.jsonl"}}`
	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-1/activity", body)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.gotHarness != "claude-code" {
		t.Fatalf("harness = %q, want claude-code — an opr older than this task sends it only here", rec.gotHarness)
	}
}

func TestActivityPrefersTheExplicitHarnessOverUsage(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	body := `{"state":"active","event":"stop","harness":"grok","usage":{"harness":"claude-code","transcriptPath":"/tmp/t.jsonl"}}`
	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-1/activity", body)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.gotHarness != "grok" {
		t.Fatalf("harness = %q, want grok — the explicit field is authoritative", rec.gotHarness)
	}
}

func TestActivityCarriesTheToolInputAndHookVersion(t *testing.T) {
	rec := &fakeBlockEventRecorder{}
	srv := newBlockEventsTestServer(t, rec)

	body := `{"state":"active","event":"post-tool-use","harness":"claude-code","toolName":"Bash","toolInput":"{"command":"ls"}","hookVersion":"1"}`
	_, status, _ := doRequest(t, srv, http.MethodPost, "/api/v1/sessions/s-1/activity", body)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if rec.gotSignal.ToolInput == "" || rec.gotSignal.HookVersion != "1" {
		t.Fatalf("signal = %+v, want the tool input and hook version carried through", rec.gotSignal)
	}
}
```

`fakeBlockEventRecorder` at `sessions_block_events_test.go:18` **already has** `gotID`, `gotHarness`, `gotSignal`, `calls` and `err`, and its `Record` already assigns all of them — verified. These four tests need no change to the fake at all; they only need `newBlockEventsTestServer`, which is right below it at :34.

Now the persistence and service tests.

The record gains a column, so the store round-trip is what proves it. Append to `backend/internal/storage/sqlite/store/block_event_store_test.go`, using `newTestStore(t)` at `backend/internal/storage/sqlite/store/store_test.go:18` — do **not** write a second store helper:

```go
func TestBlockEventStoreRoundTripsToolInputAndHookVersion(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
		SessionID:   "s-1",
		Kind:        domain.BlockEventToolComplete,
		Harness:     "claude-code",
		ToolName:    "Bash",
		ToolInput:   `{"command":"ls"}`,
		HookVersion: "1",
		CreatedAt:   time.Now().UTC(),
	}); err != nil {
		t.Fatalf("insert: %v", err)
	}

	got, err := s.SelectBlockEventsBySession(ctx, "s-1", 0, 100)
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("rows = %d, want 1", len(got))
	}
	if got[0].ToolInput != `{"command":"ls"}` || got[0].HookVersion != "1" {
		t.Errorf("row = %+v, want the tool input and hook version to survive the round trip", got[0])
	}
}
```

Append to `backend/internal/service/blockevent/service_test.go`:

```go
func TestRecordRedactsTheToolInput(t *testing.T) {
	store := &fakeStore{}
	svc := NewService(store, nil, 500)

	if err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{
		Event:       "post-tool-use",
		ToolName:    "Bash",
		ToolInput:   `{"command":"curl -H 'Authorization: Bearer abcdefghijklmnopqrstuvwxyz'"}`,
		HookVersion: "1",
	}); err != nil {
		t.Fatalf("record: %v", err)
	}

	rec := store.inserted[0]
	if strings.Contains(rec.ToolInput, "abcdefghijklmnopqrstuvwxyz") {
		t.Fatal("a bearer token reached the store inside the tool input")
	}
	if !strings.Contains(rec.ToolInput, "[redacted]") {
		t.Errorf("toolInput = %q, want a visible mask", rec.ToolInput)
	}
	if rec.HookVersion != "1" {
		t.Errorf("hookVersion = %q, want 1", rec.HookVersion)
	}
}

func TestRecordUsesTheReportedHarness(t *testing.T) {
	store := &fakeStore{}
	svc := NewService(store, nil, 500)

	if err := svc.Record(context.Background(), "s-1", "grok", ports.ActivitySignal{
		Event: "user-prompt-submit",
	}); err != nil {
		t.Fatalf("record: %v", err)
	}

	if got := store.inserted[0].Kind; got != domain.BlockEventPromptSubmit {
		t.Fatalf("kind = %q, want prompt_submit — grok has a mapper and must not fall through to unknown", got)
	}
}
```

`fakeStore` is the fake plan 1 left in `service_test.go`; read it and use its real name and field names rather than the ones guessed here.

- [ ] **Step 8: Run them and watch them fail**

```bash
cd backend && go test ./internal/storage/sqlite/store/ ./internal/service/blockevent/ -run 'BlockEvent|Record' -v
```

Expected: compile failure — `Record.ToolInput` does not exist.

- [ ] **Step 9: Add the column and the field**

Create the next migration in `backend/internal/storage/sqlite/migrations/`. The highest existing migration is `0090_block_events.sql`, so this is `0091_block_event_tool_input.sql`. Follow `0090`'s goose annotation style exactly:

```sql
-- Migration 0091: bounded preview of the native tool input.
--
-- 0090 recorded which tool ran but not what it was asked to do, which is the
-- half a permission block needs to be worth reading.

-- +goose Up
-- +goose StatementBegin
ALTER TABLE block_events ADD COLUMN tool_input TEXT NOT NULL DEFAULT '';
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE block_events DROP COLUMN tool_input;
-- +goose StatementEnd
```

`hook_version` and `error_type` are already columns — verified at `0090_block_events.sql:20-21`. Plan 1 created them and left them unwritten; this task fills `hook_version`, Task 3 fills `error_type`. Neither needs a migration.

Add `ToolInput string` to `Record` in `backend/internal/service/blockevent/types.go`, beside `Text` (:27), with the tag `json:"toolInput,omitempty"`, and delete the "persisted but not yet populated" note above `ErrorType`/`HookVersion` — after this task it is no longer true of `HookVersion`. Reword it to name `ErrorType` alone, which Task 3 then closes.

Update `backend/internal/storage/sqlite/queries/block_events.sql` so the insert and both selects carry `tool_input`, then:

```bash
npm run sqlc
```

from the repo root. **Never hand-edit `backend/internal/storage/sqlite/gen/`.** Then update `backend/internal/storage/sqlite/store/block_event_store.go` to map the new column in both directions, following exactly how it maps `text` today.

In `backend/internal/service/blockevent/service.go`, redact the tool input alongside the text and put both on the record (:65-83):

```go
	redacted := redact.Text(text)
	redactedInput := redact.Text(sig.ToolInput)
```

```go
		ToolInput:      redactedInput.Text,
		HookVersion:    sig.HookVersion,
```

The tool input's own redaction spans are deliberately **not** carried on the record: `RedactedSpans` indexes `Text`, and a second span list indexing a second string is a wire shape both clients would have to learn for a preview that is one line in a block header. The mask is still visible in the text itself, which is what the spec requires.

- [ ] **Step 10: Surface it on the read path**

Add `ToolInput string \`json:"toolInput,omitempty"\`` to `BlockEventView` in `backend/internal/httpd/controllers/dto.go` (the type Task 1 created), beside `Text`, and map it in `blockEventViews`. Add `Block.ToolInput` to nothing in `backend/internal/terminal/` — the mux frame carries the whole `Record` by value (`protocol.go:91`), so the socket picks the field up with no change.

- [ ] **Step 11: Run everything this touched**

```bash
cd backend && go test ./internal/cli/ ./internal/storage/sqlite/store/ ./internal/service/blockevent/ ./internal/httpd/controllers/ ./internal/terminal/ -race -count=1
```

Expected: `ok` for all five.

- [ ] **Step 12: Regenerate the API surface and gate**

```bash
npm run api
```

then, from the repo root:

```bash
npm run lint
```

Expected: 0 issues.

- [ ] **Step 13: Commit**

```bash
git add backend frontend/src/api/schema.ts
git commit -m "fix(backend): report the harness, tool input and hook version from every hook"
```

---

## Task 3: Per-harness handlers, and a failed tool that says so

**Why:** two gaps, one seam.

**The visible one.** `blockdispatch` maps both `post-tool-use` and `post-tool-use-failure` to `domain.BlockEventToolComplete` (`dispatch.go:28-29`) and nothing carries the difference. A tool that failed and a tool that succeeded produce byte-identical records, so **the block list can never show a failed tool** — even though `BlockStatus.failed` is in the shared model and the widgets render it. `Record.ErrorType` exists for exactly this and is never set.

**The structural one.** The spec asks for more than renaming: *"Per-harness handlers, not just parsers. Warp's `CLIAgentSessionHandler` can parse, filter and transform per agent, not merely rename events. Operator's derivers are parse-only today; the same seam is needed so a harness that emits a duplicate or a useless event can drop it at its own boundary rather than polluting the shared vocabulary."* `MapFunc` is `func(event string) (domain.BlockEventKind, bool)` — it can rename and it can fail, but it cannot **drop**.

**Files:**
- Modify: `backend/internal/adapters/agent/blockdispatch/dispatch.go`
- Modify: `backend/internal/service/blockevent/service.go`
- Modify: `backend/internal/service/blockevent/types.go`
- Test: `backend/internal/adapters/agent/blockdispatch/dispatch_test.go`, `backend/internal/service/blockevent/service_test.go`
- Modify: `testdata/blocks/hook_stream_basic.json` **only if** the Go fixture test's expectations change shape; prefer a new fixture over editing an existing one

**Interfaces:**
- Consumes: `ports.ActivitySignal.Harness` (Task 2).
- Produces, for Task 8: a `Record` whose `ErrorType` is non-empty exactly when the harness reported a failure, and no record at all for an event a harness chose to drop.
- Produces:
  - `type Decision struct { Kind domain.BlockEventKind; ErrorType string; Known bool; Drop bool }`
  - `type MapFunc func(event string) Decision`
  - `func Map(harness, event string) Decision`

**Do not change** which events each harness recognizes beyond adding the failure's error type. Widening the vocabulary is not this task.

- [ ] **Step 1: Write the failing dispatch tests**

Replace the table-driven test in `backend/internal/adapters/agent/blockdispatch/dispatch_test.go` — read it first and keep its structure, changing only the assertions to the `Decision` shape:

```go
func TestMapReportsAToolFailure(t *testing.T) {
	got := Map("claude-code", "post-tool-use-failure")
	if got.Kind != domain.BlockEventToolComplete {
		t.Fatalf("kind = %q, want tool_complete", got.Kind)
	}
	if got.ErrorType == "" {
		t.Fatal("errorType is empty — a failed tool is indistinguishable from a successful one")
	}
	if got.Drop {
		t.Fatal("a tool failure must not be dropped")
	}
}

func TestMapLeavesASuccessfulToolWithoutAnError(t *testing.T) {
	if got := Map("claude-code", "post-tool-use"); got.ErrorType != "" {
		t.Fatalf("errorType = %q, want empty", got.ErrorType)
	}
}

func TestMapCanDropAnEventAtTheHarnessBoundary(t *testing.T) {
	Mappers["drop-test"] = func(event string) Decision {
		if event == "noise" {
			return Decision{Drop: true}
		}
		return Decision{Kind: domain.BlockEventStop, Known: true}
	}
	t.Cleanup(func() { delete(Mappers, "drop-test") })

	if got := Map("drop-test", "noise"); !got.Drop {
		t.Fatal("a harness must be able to drop its own useless event")
	}
	if got := Map("drop-test", "done"); got.Drop || got.Kind != domain.BlockEventStop {
		t.Fatalf("decision = %+v, want a kept stop", got)
	}
}

func TestMapOnAnUnregisteredHarnessIsUnknownAndKept(t *testing.T) {
	got := Map("aider", "stop")
	if got.Known || got.Drop || got.Kind != domain.BlockEventUnknown {
		t.Fatalf("decision = %+v, want an unknown, kept event", got)
	}
}

func TestMapOnAnUnregisteredEventIsUnknownAndKept(t *testing.T) {
	got := Map("claude-code", "some-future-hook")
	if got.Known || got.Drop || got.Kind != domain.BlockEventUnknown {
		t.Fatalf("decision = %+v, want an unknown, kept event", got)
	}
}
```

Mutating the package-level `Mappers` map in a test is acceptable here **only** because the cleanup removes the entry and `go test` runs one package's tests in one process; do not add `t.Parallel()` to these.

- [ ] **Step 2: Run them and watch them fail**

```bash
cd backend && go test ./internal/adapters/agent/blockdispatch/ -v
```

Expected: compile failure — `Decision` undefined, `Map` returns two values.

- [ ] **Step 3: Rewrite the dispatcher**

Replace the body of `backend/internal/adapters/agent/blockdispatch/dispatch.go` below the package comment with:

```go
import "github.com/OmarAly92/operator/backend/internal/domain"

// Decision is one harness handler's verdict on one native event. Drop is what
// separates a handler from a parser: a harness that emits a duplicate or a
// useless event suppresses it at its own boundary instead of pushing it into
// the shared vocabulary. Known=false means the name was not recognized and the
// caller must carry the raw name through on the record.
type Decision struct {
	Kind      domain.BlockEventKind
	ErrorType string
	Known     bool
	Drop      bool
}

// MapFunc resolves one harness's native hook name.
type MapFunc func(event string) Decision

type rule struct {
	kind      domain.BlockEventKind
	errorType string
}

func fromTable(table map[string]rule) MapFunc {
	return func(event string) Decision {
		r, found := table[event]
		if !found {
			return Decision{Kind: domain.BlockEventUnknown}
		}
		return Decision{Kind: r.kind, ErrorType: r.errorType, Known: true}
	}
}

var claudeCodeEvents = map[string]rule{
	"session-start":         {kind: domain.BlockEventSessionStart},
	"user-prompt-submit":    {kind: domain.BlockEventPromptSubmit},
	"post-tool-use":         {kind: domain.BlockEventToolComplete},
	"post-tool-use-failure": {kind: domain.BlockEventToolComplete, errorType: "tool_failed"},
	"permission-request":    {kind: domain.BlockEventPermissionRequest},
	"stop":                  {kind: domain.BlockEventStop},
	"notification":          {kind: domain.BlockEventQuestionAsked},
}

var codexEvents = map[string]rule{
	"session-start":      {kind: domain.BlockEventSessionStart},
	"user-prompt-submit": {kind: domain.BlockEventPromptSubmit},
	"permission-request": {kind: domain.BlockEventPermissionRequest},
	"stop":               {kind: domain.BlockEventStop},
}

// Mappers is keyed by the agent token in `opr hooks <agent> <event>`.
var Mappers = map[string]MapFunc{
	"claude-code": fromTable(claudeCodeEvents),
	"grok":        fromTable(claudeCodeEvents),
	"codex":       fromTable(codexEvents),
}

// Map resolves harness and event. An unregistered harness yields an unknown,
// kept decision so the caller can record the event without inventing a kind.
func Map(harness, event string) Decision {
	mapper, found := Mappers[harness]
	if !found {
		return Decision{Kind: domain.BlockEventUnknown}
	}
	return mapper(event)
}
```

Keep the existing package comment at the top of the file verbatim; it still describes the package correctly.

- [ ] **Step 4: Write the failing service tests**

Append to `backend/internal/service/blockevent/service_test.go`:

```go
func TestRecordCarriesTheErrorType(t *testing.T) {
	store := &fakeStore{}
	svc := NewService(store, nil, 500)

	if err := svc.Record(context.Background(), "s-1", "claude-code", ports.ActivitySignal{
		Event:    "post-tool-use-failure",
		ToolName: "Bash",
	}); err != nil {
		t.Fatalf("record: %v", err)
	}

	rec := store.inserted[0]
	if rec.Kind != domain.BlockEventToolComplete {
		t.Fatalf("kind = %q, want tool_complete", rec.Kind)
	}
	if rec.ErrorType == "" {
		t.Fatal("errorType is empty — the block will render a failed tool as ok")
	}
}

func TestRecordDropsWhatAHarnessSuppresses(t *testing.T) {
	blockdispatch.Mappers["drop-test"] = func(event string) blockdispatch.Decision {
		return blockdispatch.Decision{Drop: true}
	}
	t.Cleanup(func() { delete(blockdispatch.Mappers, "drop-test") })

	store := &fakeStore{}
	svc := NewService(store, nil, 500)

	if err := svc.Record(context.Background(), "s-1", "drop-test", ports.ActivitySignal{
		Event: "noise",
	}); err != nil {
		t.Fatalf("record: %v", err)
	}

	if len(store.inserted) != 0 {
		t.Fatalf("inserted %d rows, want 0 — a dropped event must not be persisted", len(store.inserted))
	}
}

func TestRecordDoesNotPublishADroppedEvent(t *testing.T) {
	blockdispatch.Mappers["drop-test-2"] = func(event string) blockdispatch.Decision {
		return blockdispatch.Decision{Drop: true}
	}
	t.Cleanup(func() { delete(blockdispatch.Mappers, "drop-test-2") })

	store := &fakeStore{}
	pub := &fakePublisher{}
	svc := NewService(store, pub, 500)

	if err := svc.Record(context.Background(), "s-1", "drop-test-2", ports.ActivitySignal{Event: "noise"}); err != nil {
		t.Fatalf("record: %v", err)
	}

	if len(pub.published) != 0 {
		t.Fatal("a dropped event was published to live clients")
	}
}
```

`fakeStore` is at `backend/internal/service/blockevent/service_test.go:14` and `fakePublisher` at :36 — both already exist. Use them; do not add a third fake. Check `fakeStore`'s actual field name for recorded rows before writing the assertions above: this plan assumes `inserted`, and the compiler will tell you at once if it is called something else. `fakeStore` also gains the `SelectBlockEventsBeforeSeq` method in Task 4, so expect that task back in this file.

- [ ] **Step 5: Run them and watch them fail**

```bash
cd backend && go test ./internal/service/blockevent/ -race -v
```

Expected: compile failure — `blockdispatch.Map` returns one value now, so `service.go:50` no longer compiles.

- [ ] **Step 6: Honour the decision in the service**

In `backend/internal/service/blockevent/service.go`, replace the mapping line (:50) and the `RawEvent` assignment (:84-86):

```go
	decision := blockdispatch.Map(harness, sig.Event)
	if decision.Drop {
		return nil
	}
```

Set `Kind: decision.Kind` and `ErrorType: decision.ErrorType` in the `Record` literal, and:

```go
	if !decision.Known {
		rec.RawEvent = sig.Event
	}
```

The drop returns `nil`, not an error: a suppressed event is a success, and the controller's `slog` warn at `sessions.go:1334` must not fire for it.

`ErrorType` on the record is now populated, so delete the remaining "persisted but not yet populated" note in `types.go` entirely — after this task both reserved fields are live.

- [ ] **Step 7: Pin the failure through the shared fixture mechanism**

The behaviour this task adds must be visible in `testdata/blocks/`, because that directory is the contract plan 3 reads. Add the expectation field to `fixtureFile` in `backend/internal/service/blockevent/fixtures_test.go:22-30`:

```go
		ErrorType          string `json:"errorType"`
```

and the assertion inside the per-record loop (:70-86), beside the `RawEvent` check:

```go
				if got.ErrorType != want.ErrorType {
					t.Errorf("record %d ErrorType = %q, want %q", i, got.ErrorType, want.ErrorType)
				}
```

Then create `testdata/blocks/hook_stream_tool_failure.json` — a **new** fixture, not an edit to an existing one:

```json
{
  "harness": "claude-code",
  "signals": [
    { "event": "post-tool-use", "toolName": "Bash", "toolUseId": "tu-ok" },
    { "event": "post-tool-use-failure", "toolName": "Bash", "toolUseId": "tu-bad" }
  ],
  "expected": [
    { "kind": "tool_complete", "toolName": "Bash", "toolUseId": "tu-ok", "sourceId": "tu-ok" },
    { "kind": "tool_complete", "toolName": "Bash", "toolUseId": "tu-bad", "sourceId": "tu-bad", "errorType": "tool_failed" }
  ]
}
```

The three fixtures plan 1 landed carry no `errorType`, so the new field decodes as `""` for them and their assertions are unchanged.

- [ ] **Step 8: Run everything downstream of the signature change**

```bash
cd backend && go test ./internal/adapters/agent/blockdispatch/ ./internal/service/blockevent/ ./internal/httpd/controllers/ -race -count=1
```

Expected: `ok`, including the four fixtures.

- [ ] **Step 9: Gate**

```bash
npm run lint
```

Expected: 0 issues.

- [ ] **Step 10: Commit**

```bash
git add backend testdata/blocks
git commit -m "feat(backend): let harness handlers drop events and report tool failures"
```

---

## Task 4: Page older blocks back by sequence

**Why:** the spec's memory rule is two-sided — *"the client holds a bounded window of blocks and **pages older ones back from the persisted log by sequence**. Assembly must therefore work on a window, not on the whole history."* Task 9 gives the client the bounded window. Nothing gives it the way back: `SelectBlockEventsBySession` reads **ascending after** a cursor, so a client holding the newest 400 of 500 retained events has no query that returns the older 100. Without this the window is not a window, it is a guillotine.

**Files:**
- Modify: `backend/internal/storage/sqlite/queries/block_events.sql`
- Modify: `backend/internal/storage/sqlite/store/block_event_store.go`
- Modify: `backend/internal/service/blockevent/service.go`, `types.go`
- Modify: `backend/internal/httpd/controllers/sessions.go` (Task 1's `listBlockEvents`)
- Modify: `backend/internal/httpd/apispec/specgen/build.go` (Task 1's `sessionBlocksQuery`)
- Test: `backend/internal/storage/sqlite/store/block_event_store_test.go`, `backend/internal/httpd/controllers/sessions_block_events_test.go`
- Regenerated: `backend/internal/storage/sqlite/gen/`, `openapi.yaml`, `frontend/src/api/schema.ts`

**Interfaces:**
- Produces, for Tasks 7 and 9: `GET /api/v1/sessions/{sessionId}/blocks?beforeSeq=<int64>&limit=<int>`, returning the `limit` events **immediately older** than `beforeSeq`, still in **ascending** order so the client can merge them without reversing.
- Produces: `Store.SelectBlockEventsBeforeSeq(ctx, sessionID string, beforeSeq int64, limit int) ([]Record, error)` on the `Store` interface (`types.go:39-43`), and `(*Service).HistoryBefore(ctx, domain.SessionID, beforeSeq int64, limit int) ([]Record, error)`.

**`afterSeq` and `beforeSeq` are mutually exclusive.** Sending both is a `400`, not a silent precedence rule — a caller that sends both does not know what it wants and guessing for it hides the bug.

- [ ] **Step 1: Write the failing store test**

Append to `backend/internal/storage/sqlite/store/block_event_store_test.go`, using `newTestStore(t)`:

```go
func TestSelectBlockEventsBeforeSeqReadsBackwardsInForwardOrder(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	for i := 0; i < 6; i++ {
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: "s-1",
			Kind:      domain.BlockEventStop,
			Text:      fmt.Sprintf("line %d", i),
			CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert %d: %v", i, err)
		}
	}

	all, err := s.SelectBlockEventsBySession(ctx, "s-1", 0, 100)
	if err != nil {
		t.Fatalf("select all: %v", err)
	}
	if len(all) != 6 {
		t.Fatalf("rows = %d, want 6", len(all))
	}

	older, err := s.SelectBlockEventsBeforeSeq(ctx, "s-1", all[4].Seq, 2)
	if err != nil {
		t.Fatalf("select before: %v", err)
	}
	if len(older) != 2 {
		t.Fatalf("rows = %d, want 2", len(older))
	}
	if older[0].Seq != all[2].Seq || older[1].Seq != all[3].Seq {
		t.Errorf("seqs = %d,%d, want %d,%d — the page must be the two immediately older, ascending",
			older[0].Seq, older[1].Seq, all[2].Seq, all[3].Seq)
	}
}

func TestSelectBlockEventsBeforeSeqAtTheStartIsEmpty(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	seq, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
		SessionID: "s-1",
		Kind:      domain.BlockEventStop,
		CreatedAt: time.Now().UTC(),
	})
	if err != nil {
		t.Fatalf("insert: %v", err)
	}

	older, err := s.SelectBlockEventsBeforeSeq(ctx, "s-1", seq, 10)
	if err != nil {
		t.Fatalf("select before: %v", err)
	}
	if len(older) != 0 {
		t.Fatalf("rows = %d, want 0 at the start of the log", len(older))
	}
}

func TestSelectBlockEventsBeforeSeqIsScopedToOneSession(t *testing.T) {
	ctx := context.Background()
	s := newTestStore(t)

	for _, id := range []string{"s-1", "s-2", "s-1"} {
		if _, err := s.InsertBlockEvent(ctx, blockeventsvc.Record{
			SessionID: id,
			Kind:      domain.BlockEventStop,
			CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("insert %s: %v", id, err)
		}
	}

	all, err := s.SelectBlockEventsBySession(ctx, "s-1", 0, 100)
	if err != nil {
		t.Fatalf("select: %v", err)
	}
	older, err := s.SelectBlockEventsBeforeSeq(ctx, "s-1", all[1].Seq, 10)
	if err != nil {
		t.Fatalf("select before: %v", err)
	}
	for _, rec := range older {
		if rec.SessionID != "s-1" {
			t.Fatalf("row from %q leaked into s-1's page", rec.SessionID)
		}
	}
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd backend && go test ./internal/storage/sqlite/store/ -run BeforeSeq -v
```

Expected: compile failure — `SelectBlockEventsBeforeSeq` undefined.

- [ ] **Step 3: Add the query**

Append to `backend/internal/storage/sqlite/queries/block_events.sql`. The inner ordering is `DESC` to take the *nearest* older rows; the outer wrapper flips them back to ascending so every caller sees one ordering:

```sql
-- name: SelectBlockEventsBeforeSeq :many
SELECT * FROM (
  SELECT seq, session_id, source_id, kind, raw_event, harness, tool_name, tool_use_id,
         text, redacted_spans, tool_input, error_type, hook_version, truncated_lines, created_at
  FROM block_events
  WHERE session_id = ? AND seq < ?
  ORDER BY seq DESC
  LIMIT ?
) ORDER BY seq ASC;
```

**Match the column list to what `0090_block_events.sql` and Task 2's migration actually define** — read both before writing this, and copy the list from the existing `SelectBlockEventsBySession` query in the same file rather than trusting the list above. Then:

```bash
npm run sqlc
```

from the repo root, and add the wrapper to `backend/internal/storage/sqlite/store/block_event_store.go` following exactly how `SelectBlockEventsBySession` (:50) maps its rows.

Add the method to the `Store` interface in `backend/internal/service/blockevent/types.go` (:39-43):

```go
	SelectBlockEventsBeforeSeq(ctx context.Context, sessionID string, beforeSeq int64, limit int) ([]Record, error)
```

Every fake implementing `Store` in the test files must gain the method too — `go build ./...` will name each one.

Add the service method beside `History` in `backend/internal/service/blockevent/service.go` (:106):

```go
// HistoryBefore returns the events immediately older than beforeSeq, ascending,
// so a client whose window has slid forward can page backwards into what it
// dropped instead of losing it.
func (s *Service) HistoryBefore(ctx context.Context, sessionID domain.SessionID, beforeSeq int64, limit int) ([]Record, error) {
	if limit <= 0 || limit > s.retain {
		limit = s.retain
	}
	return s.store.SelectBlockEventsBeforeSeq(ctx, string(sessionID), beforeSeq, limit)
}
```

- [ ] **Step 4: Run the store tests**

```bash
cd backend && go test ./internal/storage/sqlite/store/ -run BeforeSeq -v
```

Expected: PASS.

- [ ] **Step 5: Write the failing controller tests**

Append to `backend/internal/httpd/controllers/sessions_block_events_test.go`, extending the `fakeBlockEventHistory` Task 1 created with a `HistoryBefore` method and a `gotBefore` field:

```go
func TestListBlockEventsPagesBackwards(t *testing.T) {
	hist := &fakeBlockEventHistory{recs: []blockeventsvc.Record{{Seq: 3, SessionID: "s-1", Kind: domain.BlockEventStop}}}
	srv := newBlockHistoryTestServer(t, hist)

	body, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks?beforeSeq=9&limit=2", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", status, body)
	}
	if hist.gotBefore != 9 || hist.gotLimit != 2 {
		t.Errorf("historyBefore args = (%d, %d), want (9, 2)", hist.gotBefore, hist.gotLimit)
	}
	if hist.gotAfter != 0 {
		t.Error("the forward query ran too — beforeSeq must take the backward path only")
	}
}

func TestListBlockEventsRejectsBothCursors(t *testing.T) {
	srv := newBlockHistoryTestServer(t, &fakeBlockEventHistory{})

	_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks?afterSeq=1&beforeSeq=9", "")
	if status != http.StatusBadRequest {
		t.Errorf("status = %d, want 400 — a caller sending both cursors does not know what it wants", status)
	}
}

func TestListBlockEventsRejectsABadBeforeCursor(t *testing.T) {
	srv := newBlockHistoryTestServer(t, &fakeBlockEventHistory{})

	for _, q := range []string{"?beforeSeq=abc", "?beforeSeq=-1", "?beforeSeq=0"} {
		_, status, _ := doRequest(t, srv, http.MethodGet, "/api/v1/sessions/s-1/blocks"+q, "")
		if status != http.StatusBadRequest {
			t.Errorf("%s: status = %d, want 400", q, status)
		}
	}
}
```

`beforeSeq=0` is a `400` because sequences start at 1 and "everything older than 0" is not a question with an answer.

- [ ] **Step 6: Route the backward query**

Extend the `BlockEventHistory` interface in `backend/internal/httpd/controllers/sessions.go`:

```go
	HistoryBefore(ctx context.Context, sessionID domain.SessionID, beforeSeq int64, limit int) ([]blockeventsvc.Record, error)
```

and branch in `listBlockEvents`, after the existing `limit` validation and before the `History` call:

```go
	beforeSeq, err := parseNonNegativeQuery(r, "beforeSeq")
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_QUERY", err.Error(), nil)
		return
	}
	hasBefore := r.URL.Query().Has("beforeSeq")
	if hasBefore && r.URL.Query().Has("afterSeq") {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_QUERY", "afterSeq and beforeSeq are mutually exclusive", nil)
		return
	}
	if hasBefore && beforeSeq < 1 {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "bad_request", "INVALID_QUERY", "beforeSeq must be a positive sequence", nil)
		return
	}

	var recs []blockeventsvc.Record
	if hasBefore {
		recs, err = c.BlockHistory.HistoryBefore(r.Context(), sessionID(r), beforeSeq, int(limit))
	} else {
		recs, err = c.BlockHistory.History(r.Context(), sessionID(r), afterSeq, int(limit))
	}
	if err != nil {
		envelope.WriteError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, ListSessionBlockEventsResponse{Blocks: blockEventViews(recs)})
```

replacing Task 1's single `History` call and its error handling. `parseNonNegativeQuery` already exists from Task 1.

Add the field to `sessionBlocksQuery` in `backend/internal/httpd/apispec/specgen/build.go`:

```go
	BeforeSeq *int64 `query:"beforeSeq,omitempty" minimum:"1" description:"Return the events immediately older than this sequence, ascending. Mutually exclusive with afterSeq."`
```

- [ ] **Step 7: Regenerate and run**

```bash
npm run api
```

```bash
cd backend && go test ./internal/httpd/ ./internal/httpd/controllers/ ./internal/storage/sqlite/store/ ./internal/service/blockevent/ -race -count=1
```

Expected: `ok`, including `TestRouteSpecParity` — the path is unchanged, so only the query schema moves.

- [ ] **Step 8: Gate**

```bash
npm run lint
```

Expected: 0 issues.

- [ ] **Step 9: Commit**

```bash
git add backend frontend/src/api/schema.ts
git commit -m "feat(backend): page the block log backwards by sequence"
```

---

## Task 5: User-extensible redaction patterns

**Why:** the spec's redaction requirements are four, and plan 1 shipped three. Missing: *"A default pattern set, **extensible by the user**. No enterprise tier here."* `redact.patterns` (`backend/internal/redact/redact.go:31`) is a fixed package-level `var`. A user whose organization has a token shape Operator does not know — an internal service key, a bespoke session cookie — has no way to stop it being pushed to a phone and written to sqlite.

**The minimal implementation that actually satisfies it.** No config schema change, no settings UI: one file at `<dataDir>/redact-patterns.txt`, one Go regexp per line, `#` comments and blank lines ignored. It is read **once at daemon start** and merged after the defaults. An unreadable file is not an error — redaction still runs with the defaults. An invalid line is skipped and logged, because failing daemon boot over a typo in an optional file is the wrong trade.

**This must resolve under `~/.operator`.** `AGENTS.md`'s hard rule and `CLAUDE.md`'s restatement: all app state resolves under `~/.operator`, overridable by `OPERATOR_DATA_DIR`. Take the directory from `cfg.DataDir`, which is already what `daemon.go` threads everywhere. Never call `os.UserConfigDir` or any OS-default app-data path.

**Files:**
- Modify: `backend/internal/redact/redact.go`
- Create: `backend/internal/redact/userpatterns.go`
- Modify: `backend/internal/daemon/daemon.go` (beside the `blockevent.NewService` call at :145)
- Test: `backend/internal/redact/userpatterns_test.go`

**Interfaces:**
- Produces: `func LoadUserPatterns(dataDir string, log *slog.Logger) int` — compiles and installs the user's patterns, returning how many were installed. Safe to call once at boot; **not** safe to call concurrently with `Text`, which is why it is called before any hook can arrive.

**Do not make `Text` read the file.** Recompiling regexes per event, on the hook path, for a file that changes once a release, is the wrong shape. Boot-time load is the whole feature.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/redact/userpatterns_test.go`:

```go
package redact

import (
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writePatterns(t *testing.T, body string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, userPatternsFile), []byte(body), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	return dir
}

func discardLog() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func restoreDefaults(t *testing.T) {
	t.Helper()
	saved := patterns
	t.Cleanup(func() { patterns = saved })
}

func TestLoadUserPatternsRedactsAHouseTokenShape(t *testing.T) {
	restoreDefaults(t)
	dir := writePatterns(t, "# our internal keys\nACME-[A-Z0-9]{12}\n")

	if n := LoadUserPatterns(dir, discardLog()); n != 1 {
		t.Fatalf("installed = %d, want 1", n)
	}

	got := Text("key ACME-ABCD1234EFGH here")
	if strings.Contains(got.Text, "ACME-ABCD1234EFGH") {
		t.Fatalf("text = %q, want the house token masked", got.Text)
	}
	if len(got.Spans) != 1 {
		t.Errorf("spans = %+v, want one marked removal", got.Spans)
	}
}

func TestLoadUserPatternsKeepsTheDefaults(t *testing.T) {
	restoreDefaults(t)
	dir := writePatterns(t, "ACME-[A-Z0-9]{12}\n")
	LoadUserPatterns(dir, discardLog())

	if got := Text("AKIAIOSFODNN7EXAMPLE"); !strings.Contains(got.Text, mask) {
		t.Fatalf("text = %q, want the built-in AWS pattern still applied", got.Text)
	}
}

func TestLoadUserPatternsSkipsCommentsAndBlanks(t *testing.T) {
	restoreDefaults(t)
	dir := writePatterns(t, "\n# a comment\n\n   \nACME-[A-Z0-9]{12}\n")

	if n := LoadUserPatterns(dir, discardLog()); n != 1 {
		t.Fatalf("installed = %d, want 1", n)
	}
}

func TestLoadUserPatternsSkipsAnInvalidLineWithoutFailing(t *testing.T) {
	restoreDefaults(t)
	dir := writePatterns(t, "ACME-[A-Z0-9]{12}\n(unclosed\n")

	if n := LoadUserPatterns(dir, discardLog()); n != 1 {
		t.Fatalf("installed = %d, want 1 — a bad line is skipped, not fatal", n)
	}
	if got := Text("key ACME-ABCD1234EFGH"); strings.Contains(got.Text, "ACME-ABCD1234EFGH") {
		t.Error("the valid line was not installed alongside the invalid one")
	}
}

func TestLoadUserPatternsWithNoFileIsSilentAndHarmless(t *testing.T) {
	restoreDefaults(t)

	if n := LoadUserPatterns(t.TempDir(), discardLog()); n != 0 {
		t.Fatalf("installed = %d, want 0", n)
	}
	if got := Text("AKIAIOSFODNN7EXAMPLE"); !strings.Contains(got.Text, mask) {
		t.Fatal("the defaults stopped working when there was no user file")
	}
}

func TestLoadUserPatternsIgnoresAnAbsentDataDir(t *testing.T) {
	restoreDefaults(t)

	if n := LoadUserPatterns("", discardLog()); n != 0 {
		t.Fatalf("installed = %d, want 0", n)
	}
}

func TestLoadUserPatternsBoundsTheFile(t *testing.T) {
	restoreDefaults(t)
	line := "ACME-[A-Z0-9]{12}\n"
	dir := writePatterns(t, strings.Repeat(line, maxUserPatterns+50))

	if n := LoadUserPatterns(dir, discardLog()); n != maxUserPatterns {
		t.Fatalf("installed = %d, want the cap of %d", n, maxUserPatterns)
	}
}
```

The `restoreDefaults` helper is not optional: `LoadUserPatterns` mutates a package-level `var`, and without the restore one test's patterns leak into the next.

- [ ] **Step 2: Run it and watch it fail**

```bash
cd backend && go test ./internal/redact/ -v
```

Expected: compile failure — `LoadUserPatterns`, `userPatternsFile`, `maxUserPatterns` undefined.

- [ ] **Step 3: Implement it**

Create `backend/internal/redact/userpatterns.go`:

```go
package redact

import (
	"bufio"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// userPatternsFile is read from the daemon's data dir, which resolves under
// ~/.operator. Operator writes no app state anywhere else.
const userPatternsFile = "redact-patterns.txt"

// maxUserPatterns bounds how many extra expressions are installed. Every
// pattern runs over every block's text on the hook path, so an unbounded file
// would be a way to make the daemon slow by editing a text file.
const maxUserPatterns = 64

// maxUserPatternsBytes bounds the file itself, so a stray huge file is not read
// into memory line by line before the count cap can apply.
const maxUserPatternsBytes = 64 << 10

// LoadUserPatterns merges the user's own secret shapes after the built-in set
// and returns how many were installed. A missing or unreadable file leaves the
// defaults in place: redaction degrading to the defaults is acceptable, and
// refusing to boot over a typo in an optional file is not.
//
// It mutates package state and must be called once, at start, before any text
// is redacted.
func LoadUserPatterns(dataDir string, log *slog.Logger) int {
	if strings.TrimSpace(dataDir) == "" {
		return 0
	}
	path := filepath.Join(dataDir, userPatternsFile)
	info, err := os.Stat(path)
	if err != nil || info.IsDir() || info.Size() > maxUserPatternsBytes {
		return 0
	}
	file, err := os.Open(path)
	if err != nil {
		return 0
	}
	defer func() { _ = file.Close() }()

	installed := 0
	scanner := bufio.NewScanner(file)
	for scanner.Scan() && installed < maxUserPatterns {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		re, err := regexp.Compile(line)
		if err != nil {
			if log != nil {
				log.Warn("skipping invalid redaction pattern", "file", path, "pattern", line, "error", err)
			}
			continue
		}
		patterns = append(patterns, re)
		installed++
	}
	return installed
}
```

In `backend/internal/redact/redact.go`, no change is needed — `patterns` is already a package-level `var` slice that `Text` ranges over. Confirm that is true before assuming it; if `Text` closes over a compiled combination instead, rebuild that here.

- [ ] **Step 4: Run the tests**

```bash
cd backend && go test ./internal/redact/ -v
```

Expected: PASS.

- [ ] **Step 5: Load it at boot**

In `backend/internal/daemon/daemon.go`, immediately **before** the `blockevent.NewService(store, termMgr, 500)` call at :145 — before, because after it a hook could already be redacting with the defaults:

```go
	if n := redact.LoadUserPatterns(cfg.DataDir, log); n > 0 {
		log.Info("loaded user redaction patterns", "count", n)
	}
```

Add the `redact` import. Use whatever the surrounding code calls the config value and the logger — read the lines around :145 and match them; `cfg.DataDir` and `log` are the names used elsewhere in this file, but confirm rather than assume.

- [ ] **Step 6: Gate**

```bash
npm run lint
```

Expected: 0 issues.

- [ ] **Step 7: Commit**

```bash
git add backend
git commit -m "feat(backend): let the user extend the redaction pattern set"
```

---

## Task 6: The `blocks` channel in the Flutter mux client

**Why:** `MuxClient` (`packages/mobile/lib/core/mux/mux_client.dart`) knows `sessions`, `terminal`, `subscribe` and `system`. It drops `ch: "blocks"` frames on the floor at `_onMessage` (:154-186) because nothing matches. `MuxClient` lives in `core/mux/`, not under a feature, deliberately — see `CLAUDE.md`: the Kanban board depends on the same socket, so nesting it under a feature would make the board's liveness depend on a feature it has no business knowing about. Keep it there.

**Files:**
- Modify: `packages/mobile/lib/core/mux/mux_client.dart`
- Test: `packages/mobile/test/core/mux/mux_client_test.dart`

**Interfaces:**
- Consumes: the daemon frame `{"ch":"blocks","id":"<sessionId>","type":"block","block":{…}}` from Task 1's plan-1 predecessor, and Task 1's `{"ch":"blocks","id":"…","type":"unsubscribe"}`.
- Produces, for Task 9:
  - `Stream<BlockEventEnvelope> get blockEvents` on `MuxClient`
  - `final class BlockEventEnvelope extends Equatable { const BlockEventEnvelope(this.sessionId, this.block); final String sessionId; final Map<String, dynamic> block; }`
  - `void subscribeBlocks(String sessionId)`
  - `void unsubscribeBlocks(String sessionId)`

**Design note the implementer must not "improve":** `blockEvents` carries the **raw decoded JSON map**, not a typed model. `core/` must not import `feature/`, and `BlockEventModel` lives in `feature/blocks/` (Task 7). The cubit does the parse. This mirrors how `sessionPatches` is the one exception — `SessionPatch` lives in `core/mux/` because it is the socket's own shape — and blocks are not.

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

## Task 7: Blocks data layer — model, params, data source, repository

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
- Consumes: the endpoint as Tasks 1 and 4 leave it — `GET /api/v1/sessions/{sessionId}/blocks?afterSeq=|beforeSeq=&limit=` — and the record as Tasks 2 and 3 leave it, with `toolInput` and a populated `errorType` and `hookVersion`; `ApiConsumer` (`lib/core/api/api_request_helpers/api_consumer.dart:6`); `GlobalResponse` (`lib/core/api/models/global_response.dart:17`); `Result`/`FutureResult` (`lib/core/helpers/result/result.dart:3`); `NetworkStatus`.
- Produces, for Tasks 8 and 9:
  - `BlockEventModel` with nullable fields `seq, sessionId, sourceId, kind, rawEvent, harness, toolName, toolUseId, text, toolInput, redactedSpans, errorType, hookVersion, truncatedLines, createdAt` (`createdAt` is `String?`, kept raw exactly as `ShellTerminalModel.createdAt` does at `shell_terminal_model.dart:16`), plus `BlockEventModel.fromJson(Map<String, dynamic>)` and `static List<BlockEventModel> listFromJson(Map<String, dynamic>)`.
  - `BlockRedactedSpanModel` with `int? start, int? end`.
  - `GetSessionBlocksParams({int? afterSeq, int? beforeSeq, int? limit})` with `Map<String, dynamic> toJson()` that **omits null keys**.
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
      'toolInput': '{"command":"ls -la"}',
      'errorType': 'tool_failed',
      'hookVersion': '1',
      'redactedSpans': [
        {'start': 6, 'end': 16},
      ],
      'truncatedLines': 3,
      'createdAt': '2026-08-27T10:00:00Z',
    });

    expect(model.seq, 7);
    expect(model.kind, 'tool_complete');
    expect(model.toolUseId, 'tu-1');
    expect(model.toolInput, '{"command":"ls -la"}');
    expect(model.errorType, 'tool_failed');
    expect(model.hookVersion, '1');
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
    expect(model.toolInput, isNull);
    expect(model.errorType, isNull);
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
    expect(
      const GetSessionBlocksParams(beforeSeq: 9, limit: 50).toJson(),
      {'beforeSeq': 9, 'limit': 50},
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
  final String? toolInput;
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
    this.toolInput,
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
      toolInput: json['toolInput'] as String?,
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
    toolInput,
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
  final int? beforeSeq;
  final int? limit;

  const GetSessionBlocksParams({this.afterSeq, this.beforeSeq, this.limit});

  Map<String, dynamic> toJson() => {
    if (afterSeq != null) 'afterSeq': afterSeq,
    if (beforeSeq != null) 'beforeSeq': beforeSeq,
    if (limit != null) 'limit': limit,
  };

  @override
  List<Object?> get props => [afterSeq, beforeSeq, limit];
}
```

`afterSeq` and `beforeSeq` are mutually exclusive on the wire — Task 4's endpoint answers `400` when both are set. Nothing in this class enforces that; Task 9 is the only caller and it sets exactly one.

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

Call it from `init()` immediately after the terminal feature's setup call, and add the two imports. Task 9 adds the `BlocksCubit` registration to this same method.

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

## Task 8: The shared block model and assembly

**Why:** This is the heart of the plan and the piece plan 3 (desktop) will re-implement in TypeScript against the same fixtures. It is **pure Dart** — no Flutter, no cubit, no I/O — so it is cheap to test exhaustively, which is the only defence against the two blind spots that let bugs through plan 1: async ordering and non-ASCII input.

**Files:**
- Create: `packages/mobile/lib/feature/blocks/logic/session_block.dart`
- Create: `packages/mobile/lib/feature/blocks/logic/block_assembly.dart`
- Create: `packages/mobile/lib/feature/blocks/logic/block_harnesses.dart`
- Create: `testdata/blocks/assembly_turn.json`
- Create: `testdata/blocks/assembly_permission.json`
- Create: `testdata/blocks/assembly_out_of_order.json`
- Create: `testdata/blocks/assembly_truncation.json`
- Create: `testdata/blocks/assembly_tool_failure.json`
- Create: `testdata/blocks/assembly_question.json`
- Test: `packages/mobile/test/feature/blocks/logic/block_assembly_test.dart`
- Test: `packages/mobile/test/feature/blocks/logic/block_assembly_fixtures_test.dart`

**Interfaces:**
- Consumes: `BlockEventModel` from Task 7.
- Produces, for Tasks 9, 10 and 11, and for plan 3's TypeScript port:
  - `enum BlockKind { prompt, assistant, tool, permission, notice }`
  - `enum BlockStatus { running, ok, failed, blocked }`
  - `class SessionBlock extends Equatable` with fields `String id`, `int firstSeq`, `int lastSeq`, `BlockKind kind`, `BlockStatus status`, `String title`, `String body`, `String? toolName`, `String? errorType`, `int truncatedLines`, `bool redacted`, `String? createdAt`, and `SessionBlock copyWith({BlockStatus? status, String? body, int? lastSeq, String? errorType, int? truncatedLines, bool? redacted, String? createdAt})`
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
| `tool_complete` | Correlate on `sourceId`. Status is **`failed` when `errorType` is non-empty**, `ok` otherwise. Existing block with that key → set that status, replace `body`, bump `lastSeq`, carry `errorType`. No match → new `tool` block, title `toolName` (or `Tool`) |
| `permission_request` | Correlate on `sourceId` → new `permission` block, status **`blocked`**, title `Permission requested`, body = `toolName` then `toolInput` (falling back to `text` when there is no input), joined by newlines, empty parts omitted |
| `permission_replied` | Correlate on `sourceId` → set that block's status to `ok`. **No match → no block at all**, because a reply with nothing to reply to is not information |
| `stop` | Resolve the most recent `running` `prompt` block to `ok`; then, if `text` is non-empty, append a new `assistant` block, status `ok`, title `Assistant` |
| `stop_failure` | Resolve the most recent `running` `prompt` block to **`failed`**; then, if `text` is non-empty, append a new `assistant` block, status **`failed`** |
| `question_asked` | New `notice` block, status **`blocked`**, title `Waiting on you`, body `text` |
| `idle_prompt` | **Dropped.** Per the spec: "IdlePrompt … is evidence of idleness rather than aliveness." A block per idle tick would flood the list and say nothing |
| `unknown` / anything else | New `notice` block, status `ok`, title = `rawEvent` when non-empty else `Event`, body `text` |

Correlation key: `sourceId` when non-empty, else `toolUseId` when non-empty, else there is no key and the event gets its own block. Block `id` is `'seq-<seq>'` for uncorrelated blocks and `'src-<key>'` for correlated ones — **never a generated UUID**. The spec is explicit: "The id is minted at the source, never by a consumer. … A consumer that invents ids cannot deduplicate on reconnect, cannot correlate a `tool_complete` with its `prompt_submit`, and cannot let two clients agree on what they are looking at."

`truncatedLines` and `redacted` come straight off the event (`truncatedLines ?? 0`, `redactedSpans` non-null and non-empty). When a `tool_complete` updates an existing block, both are taken from the updating event, not merged.

**A tool block's body is its input, then its result.** `tool_complete` carries `toolInput` (what the agent asked for) and `text` (what came back). Both are shown, input first, separated by a blank line, with empty parts omitted. A tool block that showed only the result would not say what ran.

**`errorType` is what makes a failed tool visible.** Task 3 sets it to `tool_failed` for `post-tool-use-failure`. Without it every tool renders `ok` and `BlockStatus.failed` is unreachable from a tool. The assembly must not infer failure any other way — no scanning the body for the word "error", which is exactly the kind of scraping this whole design exists to avoid.

`resolveStranded(blocks, reason)` maps every block whose status is `running` or `blocked` to status `failed` with `body` set to `reason`, and returns the rest unchanged. The invariant it enforces is the spec's: "no block spins forever."

### First, a collision that will break the backend suite

`TestSharedFixtures` (`backend/internal/service/blockevent/fixtures_test.go:33`) does `os.ReadDir` over **every file** in `testdata/blocks/` and decodes each as a signal-to-record fixture. The record-to-block fixtures below have a different shape — `records` instead of `signals`, and an `expected` whose entries describe blocks rather than records. Dropped in as-is they decode to zero signals and a non-empty `expected`, and the Go test fails with `produced 0 records, fixture expects 4`.

Fix the Go test to select what it owns, in this task, **before** adding a fixture. In `fixtures_test.go`, skip files that are not its own, ahead of the `t.Run` so a skipped file does not show up as a passing subtest:

```go
	const hookFixturePrefix = "hook_stream_"
	seen := 0
	for _, entry := range entries {
		if !strings.HasPrefix(entry.Name(), hookFixturePrefix) {
			continue
		}
		seen++
```

and replace the existing emptiness guard at :38-40 with one that counts what actually ran, placed after the loop:

```go
	if seen == 0 {
		t.Fatal("no hook_stream_* fixtures found; the clients have nothing to agree with")
	}
```

Add `"strings"` to that file's imports. Then run `cd backend && go test ./internal/service/blockevent/ -run TestSharedFixtures -v` and confirm it still exercises the `hook_stream_*` fixtures **before** you write a single JSON file below.

This makes the prefix load-bearing: `hook_stream_*` is asserted by Go, `assembly_*` by Dart, and plan 3 will assert the same `assembly_*` files from TypeScript. Neither suite may claim the whole directory again.

- [ ] **Step 1: Fix the fixture-directory collision, then write the fixtures**

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
    { "seq": 2, "sessionId": "s-1", "kind": "permission_request", "sourceId": "pr-1", "toolName": "Bash", "toolInput": "git branch -D feat/x" },
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

`testdata/blocks/assembly_tool_failure.json` — the case plan 1 made unrenderable: a tool that failed, and a tool input that is shown alongside its result. This fixture is the reason Tasks 2 and 3 exist:

```json
{
  "records": [
    { "seq": 1, "sessionId": "s-1", "kind": "prompt_submit", "text": "run the migration" },
    { "seq": 2, "sessionId": "s-1", "kind": "tool_complete", "sourceId": "tu-a", "toolName": "Bash", "toolInput": "{\"command\":\"goose up\"}", "text": "applied 0091", "hookVersion": "1" },
    { "seq": 3, "sessionId": "s-1", "kind": "tool_complete", "sourceId": "tu-b", "toolName": "Bash", "toolInput": "{\"command\":\"goose up\"}", "text": "no such table", "errorType": "tool_failed", "hookVersion": "1" },
    { "seq": 4, "sessionId": "s-1", "kind": "stop_failure", "text": "migration failed" }
  ],
  "expected": [
    { "id": "seq-1", "kind": "prompt", "status": "failed", "title": "Prompt", "body": "run the migration" },
    { "id": "src-tu-a", "kind": "tool", "status": "ok", "title": "Bash", "body": "{\"command\":\"goose up\"}\n\napplied 0091" },
    { "id": "src-tu-b", "kind": "tool", "status": "failed", "title": "Bash", "body": "{\"command\":\"goose up\"}\n\nno such table", "errorType": "tool_failed" },
    { "id": "seq-4", "kind": "assistant", "status": "failed", "title": "Assistant", "body": "migration failed" }
  ]
}
```

`testdata/blocks/assembly_question.json` — a question is the session asking *you* something, so it is blocked, not a benign notice. Without its own case it falls through to `default:` and renders `ok` with the title `Event`, and `resolveStranded` then leaves it pending forever because it only flips `running` and `blocked`:

```json
{
  "records": [
    { "seq": 1, "sessionId": "s-1", "kind": "prompt_submit", "text": "rename the branch" },
    { "seq": 2, "sessionId": "s-1", "kind": "question_asked", "text": "Which branch should I rename?" },
    { "seq": 3, "sessionId": "s-1", "kind": "idle_prompt" }
  ],
  "expected": [
    { "id": "seq-1", "kind": "prompt", "status": "running", "title": "Prompt", "body": "rename the branch" },
    { "id": "seq-2", "kind": "notice", "status": "blocked", "title": "Waiting on you", "body": "Which branch should I rename?" }
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
  String? toolInput,
  String? errorType,
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
  toolInput: toolInput,
  errorType: errorType,
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

    test('an errorType is what makes a tool block fail', () {
      final ok = assembleBlocks([_event(1, 'tool_complete', toolName: 'Bash', text: 'done')]);
      expect(ok.single.status, BlockStatus.ok);

      final failed = assembleBlocks([
        _event(1, 'tool_complete', toolName: 'Bash', text: 'no such file', errorType: 'tool_failed'),
      ]);
      expect(failed.single.status, BlockStatus.failed);
      expect(failed.single.errorType, 'tool_failed');
    });

    test('a correlated failure flips an already-ok block', () {
      final blocks = assembleBlocks([
        _event(1, 'permission_request', sourceId: 'k', toolName: 'Bash', toolInput: 'rm -rf /'),
        _event(2, 'permission_replied', sourceId: 'k'),
        _event(3, 'tool_complete', sourceId: 'k', toolName: 'Bash', text: 'denied', errorType: 'tool_failed'),
      ]);

      expect(blocks, hasLength(1));
      expect(blocks.single.status, BlockStatus.failed);
    });

    test('a tool block shows what ran before what came back', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_complete', toolName: 'Bash', toolInput: '{"command":"ls"}', text: 'a.txt'),
      ]);

      expect(blocks.single.body, '{"command":"ls"}\n\na.txt');
    });

    test('a tool block with only a result omits the blank separator', () {
      expect(
        assembleBlocks([_event(1, 'tool_complete', toolName: 'Bash', text: 'a.txt')]).single.body,
        'a.txt',
      );
    });

    test('a permission block names the tool and its input', () {
      final blocks = assembleBlocks([
        _event(1, 'permission_request', sourceId: 'p', toolName: 'Bash', toolInput: 'git push --force'),
      ]);

      expect(blocks.single.body, 'Bash\ngit push --force');
    });

    test('a permission block falls back to text when there is no input', () {
      final blocks = assembleBlocks([
        _event(1, 'permission_request', sourceId: 'p', toolName: 'Bash', text: 'wants to run something'),
      ]);

      expect(blocks.single.body, 'Bash\nwants to run something');
    });

    test('the tool input is opaque text and is never parsed', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_complete', toolName: 'Write', toolInput: '{"content":"a[... truncated by Operator ...]b"'),
      ]);

      expect(blocks.single.body, contains('truncated by Operator'));
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
  'assembly_tool_failure',
  'assembly_question',
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
        expect(got.errorType ?? '', want['errorType'] ?? '', reason: '$name block $i errorType');
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
    this.errorType,
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
  final String? errorType;
  final int truncatedLines;
  final bool redacted;
  final String? createdAt;

  SessionBlock copyWith({
    BlockStatus? status,
    String? body,
    int? lastSeq,
    String? errorType,
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
    errorType: errorType ?? this.errorType,
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
    errorType,
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
        final failed = (event.errorType ?? '').isNotEmpty;
        final status = failed ? BlockStatus.failed : BlockStatus.ok;
        final body = _join([event.toolInput ?? '', text], '\n\n');
        final at = key == null ? null : indexById['src-$key'];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(
            status: status,
            body: body,
            lastSeq: seq,
            errorType: event.errorType,
            truncatedLines: event.truncatedLines ?? 0,
            redacted: _isRedacted(event),
          );
        } else {
          _append(
            blocks,
            indexById,
            _create(event, key, BlockKind.tool, status, event.toolName ?? 'Tool', body),
          );
        }

      case 'permission_request':
        final detail = (event.toolInput ?? '').isNotEmpty ? event.toolInput! : text;
        final body = _join([event.toolName ?? '', detail], '\n');
        _append(
          blocks,
          indexById,
          _create(event, key, BlockKind.permission, BlockStatus.blocked, 'Permission requested', body),
        );

      case 'question_asked':
        _append(
          blocks,
          indexById,
          _create(event, key, BlockKind.notice, BlockStatus.blocked, 'Waiting on you', text),
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

String _join(List<String> parts, String separator) =>
    parts.where((part) => part.isNotEmpty).join(separator);

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
    errorType: event.errorType,
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

## Task 9: `BlocksCubit` — subscribe, backfill, merge, bound, resolve

**Why:** This is where the two failure modes that survived plan 1's review live: **async ordering** (a live event arriving before, during, or after the history fetch) and **reconnect** (a dropped socket must refetch by sequence, not start over). Both are pinned by tests here rather than left to review.

**Why backward paging is part of this task and not a later one.** The window below holds at most `kBlockWindow` events and drops the oldest as new ones arrive. Without `loadOlder`, that is not a window, it is a guillotine: a block scrolled past is gone from the app for good even though the daemon still has it. The spec's memory rule is explicit that both halves exist — "the client holds a bounded window of blocks and **pages older ones back from the persisted log by sequence**". Task 4 built the query; this is its only caller.

**The ordering rule, and why it is not what it looks like.** The cubit subscribes to the socket **before** it fetches history, not after. Fetching first would leave a window in which an event is published, missed by the not-yet-existing subscription, and absent from the already-returned page. Because every event is merged into a `SplayTreeMap<int, BlockEventModel>` keyed by `seq`, arrival order is irrelevant and duplicates are free — which is what makes subscribing first safe rather than merely early.

**Files:**
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/blocks_state.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_cubit_test.dart`

**Interfaces:**
- Consumes: `MuxClient.blockEvents`, `.status`, `.sessionPatches`, `.subscribeBlocks`, `.unsubscribeBlocks` (Task 6); `BlocksRepository.getSessionBlocks` and `GetSessionBlocksParams` (Task 7); `assembleBlocks`, `resolveStranded`, `BlockHarnesses` (Task 8).
- Produces, for Tasks 10 and 11:
  - `class BlocksCubit extends Cubit<BlocksState>` with constructor `BlocksCubit(MuxClient mux, BlocksRepository repository, String sessionId, {String? harness})`
  - public mutable fields `List<SessionBlock> blocks`, `bool loading`, `bool loadingOlder`, `bool hasOlder`, `String? error`, `bool supported`
  - `Future<void> refresh()` — forward, from the highest sequence held
  - `Future<void> loadOlder()` — backward, from the lowest sequence held
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

  test('pages backwards from the lowest sequence it holds', () async {
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([
        BlockEventModel.fromJson(_wire(20, 'stop', text: 'newest')),
      ]),
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([
        BlockEventModel.fromJson(_wire(18, 'stop', text: 'older')),
      ]),
    );
    await cubit.loadOlder();

    final captured = verify(() => repository.getSessionBlocks('s-1', captureAny()))
        .captured
        .cast<GetSessionBlocksParams>();
    expect(captured.last.beforeSeq, 20);
    expect(captured.last.afterSeq, isNull, reason: 'the endpoint rejects both cursors');
    expect(cubit.blocks.map((b) => b.body), ['older', 'newest']);
    await cubit.close();
  });

  test('an empty backward page means there is nothing older', () async {
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([BlockEventModel.fromJson(_wire(5, 'stop', text: 'a'))]),
    );
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.hasOlder, isTrue);

    when(() => repository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
    await cubit.loadOlder();

    expect(cubit.hasOlder, isFalse);
    await cubit.close();
  });

  test('loadOlder does nothing before anything is held', () async {
    when(() => repository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    clearInteractions(repository);

    await cubit.loadOlder();

    verifyNever(() => repository.getSessionBlocks(any(), any()));
    await cubit.close();
  });

  test('a second loadOlder while one is in flight is ignored', () async {
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([BlockEventModel.fromJson(_wire(9, 'stop', text: 'a'))]),
    );
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    clearInteractions(repository);

    final gate = Completer<void>();
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer((_) async {
      await gate.future;
      return Result.success(const <BlockEventModel>[]);
    });

    final first = cubit.loadOlder();
    final second = cubit.loadOlder();
    gate.complete();
    await first;
    await second;

    verify(() => repository.getSessionBlocks(any(), any())).called(1);
    await cubit.close();
  });

  test('paging older back does not immediately re-trim it away', () async {
    when(() => repository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    for (var seq = 101; seq <= 100 + kBlockWindow; seq++) {
      events.add(BlockEventEnvelope('s-1', _wire(seq, 'stop', text: 'line $seq')));
    }
    await Future<void>.delayed(Duration.zero);
    expect(cubit.blocks, hasLength(kBlockWindow));

    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([BlockEventModel.fromJson(_wire(100, 'stop', text: 'older'))]),
    );
    await cubit.loadOlder();

    expect(
      cubit.blocks.first.body,
      'older',
      reason: 'a page fetched backwards must not be evicted by the same window that dropped it',
    );
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
import 'dart:math';

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

const int kBlockPage = 100;

const int kBlockMaxWindow = 1200;

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
  bool loadingOlder = false;
  bool hasOlder = true;
  String? error;

  final SplayTreeMap<int, BlockEventModel> _events = SplayTreeMap<int, BlockEventModel>();
  bool _ended = false;
  int _revision = 0;
  int _capacity = kBlockWindow;

  StreamSubscription<BlockEventEnvelope>? _eventsSub;
  StreamSubscription<MuxStatus>? _statusSub;
  StreamSubscription<List<SessionPatch>>? _patchesSub;

  int? get _highestSeq => _events.isEmpty ? null : _events.lastKey();

  int? get _lowestSeq => _events.isEmpty ? null : _events.firstKey();

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

  Future<void> loadOlder() async {
    if (loadingOlder || !hasOlder) return;
    final before = _lowestSeq;
    if (before == null) return;

    final headroom = kBlockMaxWindow - _capacity;
    if (headroom <= 0) {
      hasOlder = false;
      _emit();
      return;
    }

    loadingOlder = true;
    _emit();
    final result = await _repository.getSessionBlocks(
      sessionId,
      GetSessionBlocksParams(beforeSeq: before, limit: min(kBlockPage, headroom)),
    );
    result.when(
      onSuccess: (records) {
        error = null;
        if (records.isEmpty) {
          hasOlder = false;
        } else {
          _capacity = min(kBlockMaxWindow, _capacity + records.length);
          for (final record in records) {
            _merge(record);
          }
        }
      },
      onFailure: (failure) => error = failure.message.isEmpty
          ? 'Could not load older blocks'
          : failure.message,
    );
    loadingOlder = false;
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
    while (_events.length > _capacity) {
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
- **A full window retires the control; it never asks for a page it would then evict.** `_merge` trims from the *bottom*, and a backward page *is* the bottom — so once `_capacity` reaches `kBlockMaxWindow`, an unguarded `loadOlder` fetches 100 records, inserts them, and immediately evicts exactly those 100. Nothing changes, `hasOlder` stays true, and "Load older blocks" becomes a button that does nothing forever. The headroom guard is what prevents that: no headroom means `hasOlder = false` and no request at all, and a partial headroom caps `limit` so every record fetched can actually be held. Two tests pin it.
- **`_capacity` grows only when the user pages back, and never past `kBlockMaxWindow`.** Trimming against a fixed `kBlockWindow` would evict a backward page the instant it arrived — you would tap "older", see it flash, and watch it vanish. Growing the window by exactly what was fetched is what makes `loadOlder` mean anything, and the ceiling is what keeps a long session from turning the phone's memory into the daemon's retention. One test pins each half.
- `loadOlder` sets **`beforeSeq` only**. Task 4's endpoint answers `400` when both cursors are present, so a call that set both would fail at runtime and pass every unit test that mocked the repository. That is why the test asserts `afterSeq` is null rather than only asserting `beforeSeq`.

- [ ] **Step 5: Register the cubit**

In `packages/mobile/lib/core/utils/service_locator.dart`, add to `_blocksFeatureSetup()` from Task 7, above the repository registration:

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

## Task 10: The block widgets

**Why:** A block list has no columns and no rows — that is the whole reason the phone becomes readable. Everything here reflows to the device width at the skin's own type sizes.

**Files:**
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_body_test.dart`

**Interfaces:**
- Consumes: `SessionBlock`, `BlockKind`, `BlockStatus`, `SessionBlock.errorType` (Task 8); `BlocksCubit` with `blocks`, `loading`, `loadingOlder`, `hasOlder`, `error`, `refresh()`, `loadOlder()` (Task 9); `context.skin`, `AppTextStyle`, `AppText`.
- Produces, for Task 11: `class BlocksBody extends StatefulWidget { const BlocksBody({super.key}); }` — it reads `BlocksCubit` from context and renders every state itself, so Task 11 places it and nothing else. It is stateful only because it owns a `ScrollController` for the pinned-to-bottom rule.

**Design rules, from `DESIGN.md` and the spec:**
- `AppSkin` tokens only. Status colour: `running` → `skin.blue`, `ok` → `skin.green`, `failed` → `skin.red`, `blocked` → `skin.amber`.
- Block bodies are monospace (`AppTextStyle.mono12Regular`); titles are `AppTextStyle.style12SemiBold`.
- **`AppText` defaults to one line with an ellipsis.** Block bodies must use a plain `Text` with `softWrap: true` — using `AppText` for a body is the bug this plan warns about twice.
- Truncation is **visible**, never silent: a block with `truncatedLines > 0` renders a footer line. This mirrors Warp's `TRUNCATION_MESSAGE` and `num_lines_truncated()`.
- Redaction is **visible**: a block with `redacted == true` renders a marker. The spec: "an invisible redaction is its own bug when someone is debugging."
- No per-block input field. Blocks are output only; the screen keeps the one composer it already has.
- **Paging back is an explicit tap, not an on-scroll trigger.** A scroll-to-top auto-fetch fights the pinned-to-bottom rule and fires during the height corrections that plan 4 will introduce. A button says what it does and cannot fire twice.
- A failed tool is `BlockStatus.failed`, which `blockStatusColor` already paints `skin.red`. `errorType` needs no separate label in this plan — the status and the body say it. Do not add a badge for it.
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
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart';

class _MockBlocksCubit extends MockCubit<BlocksState> implements BlocksCubit {}

SessionBlock _block({
  String id = 'seq-1',
  BlockKind kind = BlockKind.tool,
  BlockStatus status = BlockStatus.ok,
  String title = 'Bash',
  String body = 'ok',
  String? errorType,
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
  errorType: errorType,
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
    when(() => cubit.loadingOlder).thenReturn(false);
    when(() => cubit.hasOlder).thenReturn(false);
    when(() => cubit.error).thenReturn(null);
    when(() => cubit.refresh()).thenAnswer((_) async {});
    when(() => cubit.loadOlder()).thenAnswer((_) async {});
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

  testWidgets('a failed tool is visibly failed', (tester) async {
    when(() => cubit.blocks).thenReturn([
      _block(status: BlockStatus.failed, errorType: 'tool_failed', body: 'no such table'),
    ]);

    await _pump(tester, cubit);

    final dot = tester.widget<BlockStatusDot>(find.byType(BlockStatusDot));
    expect(dot.status, BlockStatus.failed);
    expect(find.textContaining('no such table'), findsOneWidget);
  });

  testWidgets('offers to load older blocks only when there are some', (tester) async {
    when(() => cubit.blocks).thenReturn([_block()]);
    when(() => cubit.hasOlder).thenReturn(true);

    await _pump(tester, cubit);
    expect(find.text('Load older blocks'), findsOneWidget);

    await tester.tap(find.text('Load older blocks'));
    await tester.pump();
    verify(() => cubit.loadOlder()).called(1);
  });

  testWidgets('hides the older control once the log is exhausted', (tester) async {
    when(() => cubit.blocks).thenReturn([_block()]);
    when(() => cubit.hasOlder).thenReturn(false);

    await _pump(tester, cubit);

    expect(find.text('Load older blocks'), findsNothing);
  });

  testWidgets('shows progress instead of the control while paging back', (tester) async {
    when(() => cubit.blocks).thenReturn([_block()]);
    when(() => cubit.hasOlder).thenReturn(true);
    when(() => cubit.loadingOlder).thenReturn(true);

    await _pump(tester, cubit);

    expect(find.text('Load older blocks'), findsNothing);
    expect(find.textContaining('Loading older'), findsOneWidget);
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

        final header = cubit.loadingOlder || cubit.hasOlder;

        return ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: cubit.blocks.length + (header ? 1 : 0),
          itemBuilder: (context, index) {
            if (header && index == 0) {
              if (cubit.loadingOlder) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: AppText(
                    'Loading older blocks...',
                    style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return Center(
                child: TextButton(
                  onPressed: cubit.loadOlder,
                  child: const Text('Load older blocks'),
                ),
              );
            }
            final block = cubit.blocks[index - (header ? 1 : 0)];
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

## Task 11: Lazy PTY attach, the Raw toggle, and wiring it up

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
- Consumes: `TerminalArgs` (`terminal_cubit.dart:24`), `BlocksCubit`/`BlocksBody` (Tasks 9–10), `BlockHarnesses.covers` (Task 8).
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

- [ ] **Step 7: Add the toggle to the app bar**

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

- [ ] **Step 8: Wire the route**

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

- [ ] **Step 9: Extend the terminal harness**

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

- [ ] **Step 10: Add the screen-level tests**

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

- [ ] **Step 11: Run the terminal and blocks suites**

```bash
cd packages/mobile && flutter test test/feature/terminal/ test/feature/blocks/
```

Expected: PASS, including every pre-existing terminal screen test.

- [ ] **Step 12: Full mobile gate**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: `No issues found!` and the whole suite green.

- [ ] **Step 13: Backend gate, because Task 1 touched it**

```bash
npm run lint
```

From the repo root. Expected: 0 issues.

- [ ] **Step 14: Commit**

```bash
git add packages/mobile
git commit -m "feat(mobile): show session blocks with a raw terminal toggle"
```

---

## Wrap-up

- [ ] **Confirm the phone no longer sizes the grid.** The claim this plan exists to deliver is that a phone in Blocks reports no grid. Three tests pin it: `'a detached cubit reports no grid, so it cannot drive arbitration'` (Task 11 Step 1), `'a covered harness opens in blocks and never joins the terminal channel'` and `'toggling back to blocks leaves the terminal channel again'` (Task 11 Step 9). If any of those is weakened during implementation, the plan has not been delivered.

- [ ] **Confirm plan 1's gaps are actually closed.** Six rows in the table at the top of this plan. The cheapest end-to-end check is one real session: with a claude-code session running, `GET /api/v1/sessions/<id>/blocks` must return records whose `kind` is `prompt_submit` / `tool_complete` / `stop` — **not** `unknown`. A response full of `unknown` means Task 2 did not land, and every downstream task will look like it works while rendering the wrong thing.

- [ ] **Report the known gaps** from the section at the top of this plan — virtualization, block actions, shell blocks, transcript enrichment, actionable permissions, the single `errorType` value, restart-to-reload redaction patterns, and the re-attach-on-toggle trade-off — as remaining work, not as omissions.

- [ ] **Confirm the spec's plan index still points here.** Row 2 of the table in `docs/superpowers/specs/2026-08-27-session-blocks-design.md` should read `2026-08-27-mobile-block-screen.md` / `written`. It was set when this plan was written; if a merge lost it, restore it.

- [ ] **Note for plan 3 (desktop).** The six `testdata/blocks/assembly_*.json` fixtures are the contract. Plan 3's TypeScript assembly asserts against the same files, unchanged. If the desktop port needs a rule this plan did not specify, the rule is added here and both suites re-run — the fixture is never edited to match one client.
