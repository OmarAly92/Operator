### Task 21: Delete Electron only after every replacement passes

**Files:**
- Create: `frontend/scripts/no-electron.test.mjs`
- Delete: `frontend/src/main.ts`
- Delete: `frontend/src/preload.ts`
- Delete: `frontend/src/preload.test.ts`
- Delete: `frontend/src/annotate-preload.ts`
- Delete: `frontend/src/annotate-preload.test.ts`
- Delete: `frontend/src/main/`
- Delete: `frontend/src/shared/browser-annotation-overlay.ts`
- Delete: `frontend/src/shared/browser-annotation-overlay.test.ts`
- Delete: `frontend/src/shared/browser-annotations.ts`
- Delete: `frontend/src/shared/browser-annotations.test.ts`
- Delete: `frontend/src/shared/browser-tabs.ts`
- Delete: `frontend/src/shared/daemon-attach.ts`
- Delete: `frontend/src/shared/daemon-attach.test.ts`
- Delete: `frontend/src/shared/daemon-discovery.ts`
- Delete: `frontend/src/shared/daemon-discovery.test.ts`
- Delete: `frontend/src/shared/daemon-launch.ts`
- Delete: `frontend/src/shared/daemon-launch.test.ts`
- Delete: `frontend/src/shared/daemon-takeover.ts`
- Delete: `frontend/src/shared/daemon-takeover.test.ts`
- Delete: `frontend/src/shared/shell-env.ts`
- Delete: `frontend/src/shared/shell-env.test.ts`
- Delete: `frontend/forge.config.ts`
- Delete: `frontend/vite.main.config.ts`
- Delete: `frontend/vite.preload.config.ts`
- Delete: `frontend/makers/`
- Delete: `backend/internal/browserruntime/`
- Modify: `frontend/playwright.config.ts`
- Modify: `frontend/vite.renderer.config.ts`
- Modify: `frontend/e2e/`
- Modify: `frontend/src/renderer/`
- Modify: `frontend/package.json`
- Modify: `frontend/package-lock.json`
- Modify: `frontend/perf/parity-ledger.json`

**Interfaces:**
- Produces a production dependency graph with no Electron, Forge, electron-updater, Electron maker, preload, Electron broker, or renderer import from `src/main/`.
- Keeps daemon, agent-browser, ACP runtime, renderer, Tauri, Playwright renderer tests, and all generated API artifacts.

- [ ] **Step 1: Write the failing absence test**

Reject Electron packages/scripts/configs, `electron` imports, `../../main/` renderer imports, browser broker symbols/environment variables, `app://renderer`, `VITE_NO_ELECTRON`, and stale build/workflow references. Require Tauri build/dev/publish scripts, `VITE_RENDERER_PREVIEW` for renderer-only fixtures, and all three sidecar resource entries.

- [ ] **Step 2: Run and confirm failure**

```bash
cd frontend
node --test scripts/no-electron.test.mjs
```

Expected: FAIL while Electron remains.

- [ ] **Step 3: Remove only proven-dead code and packages**

Run non-interactive `npm uninstall` for Electron, Electron Forge, electron-updater, and Electron-only makers after verifying each has no surviving consumer. Remove the Go broker only after standalone browser lifecycle is wired into session teardown and tests. Rename renderer-only development/test mode from `VITE_NO_ELECTRON` to `VITE_RENDERER_PREVIEW` and update its fake bridge, preview-data checks, Playwright configuration, and Vite proxy without changing fixture behavior.

- [ ] **Step 4: Verify and commit**

```bash
cd frontend
node --test scripts/no-electron.test.mjs
npm run typecheck
npm run typecheck:e2e
npm run test:e2e:renderer
npm run test:e2e:tauri
npm run tauri:build
npm run check:desktop-parity
cd ../backend && go test ./...
git add ../frontend internal/browserruntime
git commit -m "feat(desktop): remove electron after tauri parity"
```

