### Task 16: Remove the embedded Browser panel and implement automatic external preview

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0089_preview_open_ack.sql`
- Create: `backend/internal/httpd/desktop_preview.go`
- Create: `backend/internal/httpd/desktop_preview_test.go`
- Modify: `backend/internal/storage/sqlite/queries/sessions.sql`
- Modify: `backend/internal/storage/sqlite/store/session_store.go`
- Modify: `backend/internal/service/session/service.go`
- Modify: `backend/internal/service/session/service_test.go`
- Modify: `backend/internal/domain/session.go`
- Modify: `backend/internal/httpd/router.go`
- Modify: `backend/internal/cli/preview.go`
- Modify: `backend/internal/cli/preview_test.go`
- Delete: `frontend/src/renderer/components/BrowserPanel.tsx`
- Delete: `frontend/src/renderer/components/BrowserPanel.test.tsx`
- Delete: `frontend/src/renderer/components/BrowserTabsRail.tsx`
- Delete: `frontend/src/renderer/hooks/useBrowserView.ts`
- Delete: `frontend/src/renderer/hooks/useBrowserView.test.tsx`
- Delete: `frontend/src/renderer/hooks/useSessionBrowserLink.ts`
- Create: `frontend/src/renderer/hooks/useExternalPreview.ts`
- Create: `frontend/src/renderer/hooks/useExternalPreview.test.tsx`
- Modify: `frontend/src/renderer/components/SessionInspector.tsx`
- Modify: `frontend/src/renderer/components/SessionInspector.test.tsx`
- Modify: `frontend/src/renderer/components/SessionView.tsx`
- Modify: `frontend/src/renderer/components/SessionView.test.tsx`
- Modify: `frontend/src/shared/operator-bridge.ts`
- Modify: `frontend/src/renderer/lib/tauri-bridge.ts`
- Modify: `frontend/src/renderer/test/setup.ts`
- Modify: `frontend/perf/parity-ledger.json`
- Modify: `docs/todo/browser-panel-webview.md`

**Interfaces:**
- Consumes `previewUrl`, `previewRevision`, and `previewOpenedRevision` from session updates.
- Produces automatic once-per-revision `openExternalPreview(url)` and loopback-only `POST /internal/desktop/sessions/{id}/preview-opened` with `{revision}`. The handler advances only to the exact current revision and is idempotent.
- A manual reopen supports only validated HTTP(S) targets and never changes the automatic-open acknowledgement.

- [ ] **Step 1: Write failing preview tests**

Assert a new non-empty revision auto-opens once, a pending revision opens after restart, acknowledged revisions do not reopen after restart or rerender, a later revision opens, acknowledgement happens only after native opener success, stale/future acknowledgements fail safely, the internal route is absent on LAN, manual reopen always invokes the opener without acknowledging, clear opens nothing, invalid schemes are rejected, opener failure surfaces a retryable UI message, and every embedded browser/tab/devtools/annotation/native-composition control is absent.

- [ ] **Step 2: Run the failures**

```bash
cd frontend
npx vitest run --config vite.renderer.config.ts src/renderer/hooks/useExternalPreview.test.tsx src/renderer/components/SessionInspector.test.tsx src/renderer/components/SessionView.test.tsx
cd ../backend && go test ./internal/service/session ./internal/httpd -run 'PreviewOpened|DesktopPreview|LAN'
```

Expected: FAIL while the embedded panel remains.

- [ ] **Step 3: Delete only deferred behavior**

Add `preview_opened_revision` through migration `0089`, sqlc queries, domain mapping, session service, CDC payloads, and the loopback-only acknowledgement handler. Remove renderer panel state and bridge calls. Preserve daemon preview routes, preview server lifecycle, relative file previews, `opr preview start/status/stop/clear`, and standalone agent browser API. Update CLI help and examples to say validated targets open in the default browser. Update the ledger so only documented panel members are exceptions.

- [ ] **Step 4: Verify user and agent paths and commit**

```bash
npm run sqlc
cd frontend
npx vitest run --config vite.renderer.config.ts src/renderer/hooks/useExternalPreview.test.tsx src/renderer/components/SessionInspector.test.tsx src/renderer/components/SessionView.test.tsx
npm run typecheck
npm run check:desktop-parity
cd ../backend && go test ./internal/cli ./internal/service/session ./internal/service/browser ./internal/httpd ./internal/httpd/controllers -run 'Preview|Browser|LAN'
git add internal/domain internal/storage/sqlite internal/service/session internal/httpd internal/cli/preview.go internal/cli/preview_test.go ../frontend/src/renderer ../frontend/perf/parity-ledger.json ../docs/todo/browser-panel-webview.md
git commit -m "feat(preview): replace embedded panel with external preview"
```

