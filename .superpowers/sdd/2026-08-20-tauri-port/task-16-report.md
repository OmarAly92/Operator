# Task 16 Report: Remove embedded Browser panel, implement automatic external preview

Status: DONE_WITH_CONCERNS (see Concerns)

## Files

### Created
- backend/internal/storage/sqlite/migrations/0089_preview_open_ack.sql
- backend/internal/httpd/desktop_preview.go
- backend/internal/httpd/desktop_preview_test.go
- frontend/src/renderer/hooks/useExternalPreview.ts
- frontend/src/renderer/hooks/useExternalPreview.test.tsx
- frontend/src/renderer/lib/preview-url.ts

### Deleted
- frontend/src/renderer/components/BrowserPanel.tsx (+ .test.tsx)
- frontend/src/renderer/components/BrowserTabsRail.tsx
- frontend/src/renderer/hooks/useBrowserView.ts (+ .test.tsx)
- frontend/src/renderer/hooks/useSessionBrowserLink.ts
- frontend/src/renderer/lib/browser-tab-label.ts (orphaned helper whose only importer was BrowserTabsRail)

### Modified (backend)
- internal/storage/sqlite/queries/sessions.sql: preview_opened_revision added to GetSession /
  ListSessionsByProject / ListAllSessions SELECT lists, InsertSession columns+values (37 -> 38),
  UpdateSession SET; new MarkSessionPreviewOpened :execrows query guarded by
  `WHERE id = ? AND preview_revision = ? AND preview_opened_revision < ?`.
- internal/storage/sqlite/store/session_store.go: row/insert/update mapping of PreviewOpenedRevision;
  new MarkSessionPreviewOpened store method (writeMu-guarded).
- internal/domain/session.go: SessionMetadata.PreviewOpenedRevision int64 json:"previewOpenedRevision,omitempty".
- internal/service/session/service.go: Store interface gains MarkSessionPreviewOpened;
  new AckPreviewOpened(ctx, id, revision): 404 SESSION_NOT_FOUND unknown session,
  409 PREVIEW_ACK_REJECTED when revision != current preview_revision (stale OR future) or when the
  guarded UPDATE applied zero rows after a concurrent change, no-op success when revision <= opened.
- internal/service/session/service_test.go: fakeStore SetSessionPreviewURL now bumps revision
  (mirrors production SQL) + fake MarkSessionPreviewOpened; 6 new tests.
- internal/httpd/dto.go + controllers/sessions.go: SessionView.PreviewOpenedRevision curated wire field.
- internal/httpd/api.go: APIDeps.DesktopPreview DesktopPreviewService (nil keeps route unmounted).
- internal/httpd/router.go: mountDesktopPreview(r, deps.DesktopPreview).
- internal/daemon/daemon.go: DesktopPreview: sessionSvc wiring.
- internal/httpd/lan_listener_test.go: blocked-path list gains the new route (LAN 404 pin).
- internal/storage/sqlite/migrate_burned_versions_test.go: shippedMigrations[89].
- internal/cli/preview.go: Short/Long/clear copy now say validated HTTP(S) targets open once in the
  default browser; examples preserved. preview_test.go help test asserts "default browser" present.

### Generated (regenerated, not hand-edited)
- backend/internal/storage/sqlite/gen/{models.go,sessions.sql.go} via `npm run sqlc` (byte-stable on rerun).
- backend/internal/httpd/apispec/openapi.yaml via `go generate ./...`: exactly one addition,
  Session schema gains `previewOpenedRevision` int64 (3 lines).
- frontend/src/api/schema.ts via `npm run api:ts`.

### Modified (frontend)
- src/shared/operator-bridge.ts: browser namespace + browser type imports + BrowserBoundsInput /
  BrowserNavigateInput / OperatorBridgeWithoutBrowser removed; new ExternalPreviewOpenInput type and
  required `preview.openExternalPreview(input)` namespace member.
- src/renderer/lib/tauri-bridge.ts: implements preview.openExternalPreview = strict HTTP(S) validation
  (isAllowedPreviewUrl) -> invoke("open_external", {url}) (native.rs EXISTING general opener) ->
  postPreviewOpenedAck() POST to loopback /internal/desktop/sessions/{id}/preview-opened behind
  hasTrustedApiBaseUrl(); ack failure is warn-and-swallow so an unacked revision legitimately
  re-opens later (pending-survives-restart semantics); return type now OperatorBridge.
- src/renderer/lib/preview-url.ts: TS mirror of native.rs is_allowed_preview_url (HTTP(S) scheme +
  non-empty authority, backslash rejected) - shared by bridge auto-open path and hook manual reopen.
- src/renderer/lib/bridge.ts: browser-preview fallback loses browser block, gains preview block
  (window.open based, dev-web only).
- src/renderer/hooks/useExternalPreview.ts: once-per-(revision,target) consumed map keyed by session;
  skips acknowledged revisions (revision <= previewOpenedRevision), empty targets (clear opens
  nothing), invalid schemes, terminated sessions; falls back to app.openExternal + explicit ack fetch
  when shell lacks a preview namespace; retryable error state + retry(); manual reopen(target)
  validates strict HTTP(S), invokes app.openExternal only, never acknowledges.
- src/renderer/components/SessionInspector.tsx: tabs are Summary|Files; all panel props removed;
  new PreviewSection (URL, Reopen in browser action, retryable error + Retry) fed by SessionView.
- src/renderer/components/SessionView.tsx: BrowserPanel/useBrowserView/useBrowserAnnotationQueue,
  pop-out overlay, reveal/glow/unseen effects all removed; wires useExternalPreview into inspector.
- src/renderer/stores/ui-store.ts: InspectorView = "summary" | "files"; previewKey,
  browserContentRevealed, browserUnseen state and their setters removed.
- src/renderer/hooks/useWorkspaceQuery.ts: maps previewOpenedRevision through to WorkspaceSession.
- src/renderer/types/workspace.ts: previewOpenedRevision?: number documented field.
- src/renderer/components/TerminalPane.tsx + chat/SessionChatSurface.tsx: deleted
  useSessionBrowserLink replaced by validated external open (isWebLink guard ->
  openLinkInSystemBrowser); links open externally for every session kind.
- src/renderer/test/setup.ts: window.operator stub swaps browser block for preview block.
- src/renderer/i18n/*.json (8 locales): +inspector.preview, +inspector.reopenPreview,
  +inspector.retryPreview (appended, original ordering/formatting preserved).
- src/renderer/components/chat/SessionChatSurface.test.tsx, TerminalPane.test.tsx,
  ShellTopbar.test.tsx, lib/bridge.test.ts: updated to the new contract.
- src/renderer/i18n/renderer-coverage.test.ts: BrowserPanel approvedLiterals entry removed.
- perf/parity-ledger.json: two renderer entries removed (101 entries remain).

### Docs
- docs/todo/browser-panel-webview.md rewritten truthfully: Task 16 disposition shipped, explicit
  dropped-capability table (tabs/devtools/annotations/native composition/glow), Electron remnants
  called out as alive until Task 21, preserved CLI/server/file-preview behavior stated.

## RED evidence (captured before implementation)

Frontend (`npx vitest run --config vite.renderer.config.ts` on the three gate files):

1. useExternalPreview.test.tsx: `Error: Failed to resolve import "./useExternalPreview" from
   "src/renderer/hooks/useExternalPreview.test.tsx". Does the file exist?` -> Test Files 2 failed,
   Tests no tests (module did not exist).
2. SessionInspector.test.tsx: 4 failed | 68 passed:
   - keeps every embedded browser control absent from the inspector (Browser tab still rendered)
   - exposes Summary and Files as inspector tabs (got ["Summary","Browser","Files"])
   - offers the manual preview reopen action without embedded panel chrome (no such button)
   - surfaces a retryable external-preview failure beside the reopen action (no such button)
3. SessionView.test.tsx: 3 failed | 39 passed, each
   `expected undefined to match object { sessionId: 'sess-1', ... }` because SessionView still drove
   useBrowserView and never fed the preview facts anywhere:
   - feeds the session's preview facts into external preview handling
   - treats a merged terminated session as terminated for external preview
   - does not auto-open a terminated session's stale preview through the external opener

Backend:

4. internal/service/session: build failure - `r.Metadata.PreviewOpenedRevision undefined (type
   domain.SessionMetadata has no field or method PreviewOpenedRevision)`,
   `(&Service{...}).AckPreviewOpened undefined (type *Service has no field or method AckPreviewOpened)`.
5. internal/httpd/desktop_preview_test.go: vet/build failure - `undefined: DesktopPreviewService`
   (route + interface not yet implemented). The LAN-absence test compiles only once that symbol
   exists; it pins isLANControlBlockedPath("/internal/...") which was already satisfied by the
   existing /internal/ prefix block, so it is a regression pin (GREEN from birth), noted here for honesty.
6. cli: TestPreview_HelpIncludesExamples initially failed after the copy change until the wording kept
   "default browser" on one line; final version asserts the required phrase.

## GREEN evidence

Go (cd backend):
- go build ./... : OK
- go vet ./... : OK
- go test ./internal/service/session ./internal/httpd/... ./internal/cli ./internal/storage/sqlite/... :
  all ok. New tests green: service AckPreviewOpened x6 (records current revision, idempotent repeat,
  stale+future rejection with code PREVIEW_ACK_REJECTED and untouched stored value, unknown session,
  survives-restart scenario incl. second pending revision ack after "restart"),
  httpd DesktopPreviewOpened x7 (advance to exact current revision 200 {sessionId,revision},
  idempotent repeat 200, stale 409 + future 409 with PREVIEW_ACK_REJECTED envelope code,
  unknown session 404, missing revision 400, non-numeric revision 400, route 404 on a real bound
  0.0.0.0 LAN listener with valid auth and spoofed Host), lan_listener_test blocked list extended.

sqlc: `npm run sqlc` re-run twice; git status shows only gen/models.go + gen/sessions.sql.go modified
(intended); byte-stable regeneration, zero unintended diff.

OpenAPI/schema: openapi.yaml diff is exactly +3 lines (previewOpenedRevision int64 under Session);
apispec parity test (TestBuild_MatchesEmbedded) green; frontend schema.ts regenerated via npm run api:ts.

Frontend (cd frontend):
- npm run typecheck : clean (covers src/main.ts + src/preload.ts too - Electron keeps compiling).
- npm run check:desktop-parity : "Desktop parity ledger covers 101 entries."
- Gate trio vitest run (useExternalPreview.test.tsx + SessionInspector.test.tsx + SessionView.test.tsx):
  Test Files 3 passed (3), Tests 125 passed (125).
- Related suites run together: bridge.test, tauri-bridge.test, external-link-policy.test,
  useWorkspaceQuery.test, TerminalPane.test, SessionChatSurface.test, ShellTopbar.test,
  i18n instance + renderer-coverage: Test Files 9 passed, Tests 120 passed.
- Full suite (vitest run over everything): 2164 passed | 5 failed | 1 skipped; the 16 failing FILES /
  5 failing TESTS are all pre-existing environmental noise in this working copy: scripts/*.test.mjs
  bundle node:test built-ins vitest cannot load (they are run by `node --test`, see package.json),
  and src/landing/** fails on missing optional landing deps (e.g. cheerio is not in package.json at
  all). None of those files are touched by this task (git status confirms) and none import anything
  this task changed.

## Parity ledger delta summary

Removed exactly two entries (their files are deleted):
- {"source":"renderer/components/BrowserTabsRail.tsx","member":"../../main/browser-view-host", ...}
- {"source":"renderer/hooks/useBrowserView.ts","member":"../../main/browser-view-host", ...}

Kept as the ONLY remaining exceptions (all disposition "deferred", exception
docs/todo/browser-panel-webview.md, owner/task null):
- main/browser-view-host.ts (Electron-only, still imported by src/main.ts until Task 21)
- all 22 preload.browser.* members (Electron preload keeps compiling per task constraints)

103 -> 101 entries; check:desktop-parity green. Note: scripts/check-parity-ledger.mjs still lists the
two removed renderer paths in its hardcoded deferredBrowserEntries set; harmless (the set only
constrains entries present in the ledger) and left untouched to keep the diff surface minimal -
Task 21 can prune it.

## Behavior notes / design decisions

- Ack semantics: "advances ONLY to the exact current revision" is enforced twice - by the service
  comparing against the freshly read record AND by the SQL guard
  `WHERE preview_revision = ? AND preview_opened_revision < ?`, so a concurrent `opr preview` between
  read and write cannot let a stale ack win. Idempotent repeat of the current revision returns 200
  without writing. Stale and future revisions share code PREVIEW_ACK_REJECTED (409).
- CDC: migration 0089 recreates sessions_cdc_update verbatim from 0085 plus preview_opened_revision
  in both WHEN and payload, so acknowledgements fan out like every other session fact and a second
  window/renderer converges. Down migration restores the 0085 trigger and drops the column.
- Renderer auto-open decision: opens iff target non-empty, strict HTTP(S) valid, revision > max(
  previewOpenedRevision, last locally consumed revision), session not terminated. Clear (empty target,
  bumped revision) consumes locally, opens nothing, acknowledges nothing. Legacy daemons without a
  revision fall back to URL-change triggering.
- Bridge layering: Tauri path = validate -> open_external (existing general opener command; mailto
  allowed there but preview validation rejects it before invoke) -> ack after success. Shells without
  a preview namespace (interim Electron preload until Task 21, dev web) = validate -> app.openExternal
  -> explicit ack fetch from the hook. Ack failures warn but do not error: an unacked revision
  re-opens later by design rather than wedging the UI.
- Manual reopen lives in SessionInspector Summary (Preview section: URL + "Reopen in browser", plus
  retryable error + Retry when the automatic open failed). It never POSTs the acknowledgement.

## Self-review findings (found and fixed during the pass)

1. useWorkspaceQuery.ts dropped unknown fields while mapping REST sessions to WorkspaceSession -
   previewOpenedRevision would never have reached the hook in production. Added to the mapping.
2. First locale edit reformatted all 8 i18n JSON files (json.dump reorder); reverted via git checkout
   and re-applied by appending keys only - final diff is +3 lines per file, original ordering kept.
3. First parity-ledger rewrite changed every line's spacing; redone with separators=(",",":") so the
   diff is exactly the two removed lines.
4. go generate ./... also regenerated codexproto/protocol.gen.go because this machine has codex-cli
   0.147.0 vs the repo-pinned 0.146.0 source; that file was reverted - not part of this task.
5. SessionView.tsx python surgery briefly removed the shell-terminal publish effect, files handlers and
   showChatSurface derivation along with the browser effects; restored and verified by the retained
   terminal/tab-strip tests (42 SessionView tests green).

## Concerns

1. Ack fan-out: every preview-opened acknowledgement now emits a session_updated CDC event to all
   listeners (desktop + mobile). Volume is one event per user-visible preview open (not per poll), but
   it is the one deliberate amplification this task adds. Alternative was no CDC propagation, leaving
   second windows stale until their next REST refetch.
2. Manual reopen UI surface is intentionally small: a Preview section in the inspector Summary with
   Reopen / Retry. The old panel's affordances (tabs bar, devtools, annotations, pop-out) have no
   replacement by design; if reviewers want reopen surfaced elsewhere (e.g. chat link context menu),
   that is a follow-up.
3. Terminal/chat web links now open in the OS browser for ALL sessions (orchestrator and terminated
   included) instead of only active workers. This matches external-preview semantics; the previous
   worker-only gating existed because the panel lived inside the worker inspector.
4. scripts/check-parity-ledger.mjs keeps two now-inert entries in its hardcoded deferred set (see
   ledger delta note).
5. The interim Electron shell (until Task 21) has no bridge.preview namespace, so its automatic open
   path goes through the hook fallback (app.openExternal + hook-side ack fetch) rather than the Tauri
   bridge; behavior is equivalent but the code path differs per shell.
6. Full-suite run shows 16 pre-existing failing files (node:test scripts + landing sub-app deps);
   verified untouched by this diff and failing for environmental reasons, not rerun-dismissed.

## No commits

No git add, commit, push, or stash was performed. Everything is left UNCOMMITTED in the working tree
of /Users/omaraly/development/AI/Operator-tauri (branch codex/tauri-port) for central controller
review. The only working-tree state predating this task: .superpowers/sdd/2026-08-20-tauri-port/progress.md
(already modified before start) and untracked frontend/src-tauri/{gen,target} artifacts.

---

# Fix Round 1 (review findings C1, I1, I2)

## C1 — ack query never persisted (Critical) — FIXED

backend/internal/storage/sqlite/store/session_store.go: the MarkSessionPreviewOpened call site built
gen.MarkSessionPreviewOpenedParams without `PreviewOpenedRevision_2`, which binds positionally to the
`preview_opened_revision < ?` forward-only guard and stayed at Go zero value 0. Since the column is
NOT NULL DEFAULT 0, every UPDATE matched zero rows, so every acknowledgement — valid ones included —
came back applied=false and surfaced as 409 PREVIEW_ACK_REJECTED; acknowledged targets would have
re-opened forever. Fix sets `PreviewOpenedRevision_2: revision`.

Covering test (I1): backend/internal/storage/sqlite/store/session_store_test.go
TestMarkSessionPreviewOpenedAdvancesOnlyToCurrentRevision — real migrated temp SQLite DB via
sqlitetest.MustOpen(t), two published preview targets (revision=2), then asserts against the ACTUAL
:execrows SQL: stale (1) and future (3) acknowledgements match zero rows, the current-revision
acknowledgement updates exactly one row, an idempotent repeat matches zero rows again, and a final
GetSession reads back preview_opened_revision=2 with preview_revision untouched at 2.

TDD sequence recorded:
- RED (before the fix): `--- FAIL: TestMarkSessionPreviewOpenedAdvancesOnlyToCurrentRevision ...
  session_store_test.go:123: acknowledgement of the current revision matched zero rows, want one row
  updated` — reproduces C1 exactly.
- GREEN (after setting PreviewOpenedRevision_2): `--- PASS ... (0.14s)`.

## I2 — orphaned i18n keys — FIXED

Deleted from ALL EIGHT locale files (en, de, es, fr, ja, ko, pt-BR, zh-CN): the complete `browser.*`
block plus inspector.browser / inspector.browserInCenter / inspector.returnToPanel. Per-file removals:
54 keys in en/de/ja/ko/zh-CN, 55 in es/fr/pt-BR (the extra one is locale-specific plural or alias
variant of the same orphaned block). Verified zero remaining consumers anywhere under frontend/src
before deleting (grep over t()/appI18n.t() call sites). Deletions are line-level only — original key
ordering and tab formatting preserved; all files re-parse as valid JSON.

Note: this changes the fix-round diff beyond "only C1 + test" by exactly what I2 mandates; no parked
minors were touched.

## Gates re-run (exact outputs)

cd backend && go build ./... && go vet ./... && go test ./internal/storage/sqlite/... ./internal/service/session ./internal/httpd/... :
  ok  github.com/OmarAly92/operator/backend/internal/storage/sqlite        3.806s
  ok  github.com/OmarAly92/operator/backend/internal/storage/sqlite/store   1.966s
  ok  github.com/OmarAly92/operator/backend/internal/service/session       (cached)
  ok  github.com/OmarAly92/operator/backend/internal/httpd                 (cached)
  ok  github.com/OmarAly92/operator/backend/internal/httpd/controllers     (cached)
  ok  github.com/OmarAly92/operator/backend/internal/httpd/apispec{,/specgen} (cached)
  (build and vet silent = success)

cd frontend && vitest run --config vite.renderer.config.ts useExternalPreview.test.tsx
SessionInspector.test.tsx SessionView.test.tsx renderer-coverage.test.ts :
  Test Files  4 passed (4)
  Tests       126 passed (126)

npm run typecheck : clean (tsc --noEmit, no output).
npm run check:desktop-parity : Desktop parity ledger covers 101 entries.
Extra covering run for the locale edits: i18n instance.test + renderer-coverage.test :
  Test Files 2 passed, Tests 13 passed.

Still fully uncommitted: no git add/commit/push performed in this round.
