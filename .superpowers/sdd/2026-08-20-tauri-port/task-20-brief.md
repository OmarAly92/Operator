### Task 20: Add three-platform Tauri E2E and parity gates

**Files:**
- Create: `frontend/e2e-tauri/wdio.conf.ts`
- Create: `frontend/e2e-tauri/desktop.e2e.ts`
- Create: `frontend/tsconfig.e2e-tauri.json`
- Create: `.github/workflows/tauri-webdriver.yml`
- Modify: `frontend/src-tauri/Cargo.toml`
- Modify: `frontend/src-tauri/src/lib.rs`
- Modify: `frontend/package.json`
- Modify: `frontend/package-lock.json`
- Modify: `frontend/perf/parity-ledger.json`

**Interfaces:**
- Produces `npm run test:e2e:tauri` using the embedded provider from `@wdio/tauri-service` 1.3.0 and WebDriverIO 9.30.0 on macOS, Windows, and Linux.
- Compiles `tauri-plugin-wdio` 1.3.0 and `tauri-plugin-wdio-webdriver` 1.3.0 only behind an `e2e` Cargo feature. Normal development and production builds do not register or expose the embedded driver.
- Produces a native matrix plus ledger status proving each non-browser behavior through E2E or a named lower-level contract test.

- [ ] **Step 1: Write the initially failing E2E**

Launch an `e2e`-feature Tauri build through the embedded provider; wait for daemon ready; create/open a project and session; verify terminal mux round trip; change and persist UI/update/keybinding/migration settings; use chooser, clipboard, shortcut, notification, tray, and dropped file seams; run automatic and manual external preview; execute standalone browser actions; restart the app; verify persistence and marker resolution. Add a build-contract test proving the embedded driver is absent from a normal production build.

- [ ] **Step 2: Run the failure**

```bash
cd frontend
npm run test:e2e:tauri
```

Expected: FAIL until the runner and complete Tauri surface are wired.

- [ ] **Step 3: Implement native CI**

Pin `@wdio/tauri-service` 1.3.0, `@wdio/cli`, `@wdio/local-runner`, and `@wdio/mocha-framework` 9.30.0, `@wdio/spec-reporter` 9.29.1, and both Rust WDIO plugins 1.3.0. Set `driverProvider: "embedded"`. Use native GitHub runners and Xvfb plus the WebKitGTK runtime on Linux; no external platform driver or paid provider is required. Upload logs, screenshots, benchmark JSON, and app-under-test artifacts on failure without uploading `~/.operator` data. Keep renderer Playwright jobs unchanged.

- [ ] **Step 4: Close the parity ledger and commit**

```bash
cd frontend
npm run test:e2e:tauri
npm run test:e2e:renderer
npm run check:desktop-parity
git add e2e-tauri tsconfig.e2e-tauri.json src-tauri/Cargo.toml src-tauri/src/lib.rs package.json package-lock.json perf/parity-ledger.json ../.github/workflows/tauri-webdriver.yml
git commit -m "test: gate tauri parity on three platforms"
```

