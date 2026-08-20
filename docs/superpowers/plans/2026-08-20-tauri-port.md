# Tauri Desktop Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Electron with a measurably faster and smaller Tauri desktop shell while preserving every current behavior except the explicitly deferred embedded Browser panel.

**Architecture:** Tauri/Rust owns native UI integration, installation facts, updater execution, and daemon supervision. React keeps its daemon REST/SSE/terminal-mux paths. Shared settings, telemetry bootstrap, import utilities, preview revisions, and standalone agent-browser orchestration live in Go. User preview opens in the default browser; agent automation uses an isolated managed Chromium and never depends on a Tauri or Electron panel.

**Tech Stack:** Tauri 2.11.5, Rust 1.96.0, `@tauri-apps/cli` 2.11.4, `@tauri-apps/api` 2.11.1, React 19, Vite 8, TypeScript 5.6, Go 1.25.7, SQLite/sqlc, xterm.js 5.5, agent-browser 0.33.1, Node 22.23.2 ACP runtime, WebDriverIO Tauri service 1.3.0.

**Spec:** `docs/superpowers/specs/2026-08-16-tauri-port-design.md`

## Global Constraints

- Support macOS, Windows, and Linux. Dropping a platform requires an explicit user decision after Phase 0.
- Do not begin Task 7 unless Task 6 records `continue` or `linux-canvas`.
- Preserve Go PTY → mux WebSocket → `@xterm/xterm`; terminal bytes never pass through Tauri commands.
- Tauri terminal throughput median must be at least Electron median and p95 input latency must be no worse.
- Terminal-open median must be at most 75% of Electron and p95 at most 90%; reconnect p95, active-terminal memory, and fixed-workload CPU time must be no worse.
- Warm-start p50 must be at most 70% of Electron and p95 at most 75%; idle shell memory must be at most 60%.
- Base signed update artifacts must be at most 100 MiB, at most 70% of Electron counterparts, and installed footprint at most 60%.
- Count the Go daemon, agent-browser, and existing Node 22.23.2 ACP runtime in base package measurements.
- Preserve the ACP runtime. Do not add another Node runtime or silently remove Claude ACP chat support.
- Remove only the embedded Browser-panel behavior recorded in `docs/todo/browser-panel-webview.md`.
- Store application, webview, browser-engine, runtime, drop, updater, and crash state under the Operator state root. A failure on macOS is a stop-port gate.
- Keep the primary daemon listener on `127.0.0.1` without auth. Keep the existing opt-in authenticated LAN listener unchanged.
- Preserve Flutter mobile connectivity and API behavior; desktop-only import, telemetry, and preview-ack routes remain unavailable on the LAN listener.
- Permit exact Tauri production origins; never permit CORS `null`, `*`, a non-loopback website, or a lookalike localhost host.
- Extend the existing `app_settings` singleton with migration `0088`; do not create `desktop_preferences`.
- Keep local filesystem scan controls under `/api/v1/dev`, which the LAN listener blocks.
- Pin every added npm and Cargo dependency exactly. Do not use `latest` or an unbounded version range.
- Do not hand-edit sqlc, OpenAPI, or generated TypeScript API output. Run `npm run sqlc` and `npm run api`.
- Preserve the single-publisher rule and verify macOS zip and DMG with `frontend/scripts/verify-mac-artifact.sh`.
- Preserve bundle ID `dev.operator.desktop`, product/bundle name `Operator`, executable name `operator`, existing version-free download aliases, and Electron compatibility feeds needed by installed users.
- Use a fresh implementation subagent for each task and complete both specification and code-quality review before starting the next task.

## Planned file structure

| Path | Responsibility |
|---|---|
| `frontend/src-tauri/` | Pinned Tauri crate, capabilities, native commands, supervisor, updater, app marker, relocation. |
| `frontend/src/shared/operator-bridge.ts` | Shell-neutral renderer contract and shared types. |
| `frontend/src/renderer/lib/tauri-bridge.ts` | Tauri implementation of the bridge. |
| `frontend/perf/terminal/` | Separate Vite benchmark entry; never part of the production route tree. |
| `frontend/perf/results/` | Sanitized per-platform aggregate results. |
| `frontend/scripts/benchmark-*.mjs` | Metadata, cold-start, memory, terminal, artifact, and comparison runners. |
| `frontend/perf/parity-ledger.json` | Machine-checked mapping of every Electron bridge method and renderer main-process import. |
| `backend/internal/adapters/agentbrowser/` | Browser discovery/install, isolated runtime, policy, and process execution. |
| `backend/internal/service/settings/` | Existing shared settings service extended for desktop/mobile preferences and legacy import. |
| `backend/internal/httpd/controllers/dev_desktop.go` | Loopback-only folder scan and ancestor-repository routes under `/api/v1/dev`. |
| `backend/internal/storage/sqlite/migrations/0088_desktop_settings.sql` | New columns on the existing `app_settings` singleton. |
| `.github/workflows/tauri-*.yml` | Phase 0, native checks, packaging, WebDriver, updater E2E, and artifact verification. |

---

### Task 1: Freeze the parity and performance contract

**Files:**
- Create: `frontend/perf/parity-ledger.json`
- Create: `frontend/scripts/check-parity-ledger.mjs`
- Create: `frontend/scripts/check-parity-ledger.test.mjs`
- Create: `docs/benchmarks/tauri-port-baseline.md`
- Modify: `frontend/package.json`

**Interfaces:**
- Consumes: `frontend/src/preload.ts`, renderer imports from `frontend/src/main/`, the design spec, and deferred-browser record.
- Produces: `npm run check:desktop-parity` and a ledger entry `{source, member, disposition, owner, task, exception}` for every Electron method, renderer import, and production module under `frontend/src/main/`.

- [ ] **Step 1: Write the failing ledger tests**

Test that duplicate `source/member` pairs fail, every preload namespace member is present, every renderer `../../main/` import is present, every production module under `src/main/` has a disposition, `exception` is accepted only for deferred Browser-panel entries, and every other entry has a task number and `tauri|go|renderer` owner.

- [ ] **Step 2: Run the test and confirm failure**

```bash
cd frontend
node --test scripts/check-parity-ledger.test.mjs
```

Expected: FAIL because the ledger and checker do not exist.

- [ ] **Step 3: Implement the checker and complete ledger**

Generate the source inventory from `src/preload.ts`, `rg -n 'from "../../main/' src/renderer`, and production modules under `src/main/`. Check the inventory against the JSON ledger without modifying source. Add `"check:desktop-parity": "node ./scripts/check-parity-ledger.mjs"`.

- [ ] **Step 4: Record exact benchmark definitions**

Document the gates from the spec, 3 warmups, 10 measured startup/terminal samples, 5 memory launches, the 60-second idle point, full process-tree accounting, active-terminal memory and workload CPU accounting, base versus managed-browser footprint, and the required metadata fields.

- [ ] **Step 5: Verify and commit**

```bash
cd frontend
node --test scripts/check-parity-ledger.test.mjs
npm run check:desktop-parity
git add package.json perf/parity-ledger.json scripts/check-parity-ledger.mjs scripts/check-parity-ledger.test.mjs ../docs/benchmarks/tauri-port-baseline.md
git commit -m "docs: lock tauri parity and performance contract"
```

### Task 2: Build the repeatable Electron baseline harness

**Files:**
- Create: `frontend/scripts/benchmark-result.mjs`
- Create: `frontend/scripts/benchmark-result.test.mjs`
- Create: `frontend/scripts/benchmark-shell.mjs`
- Create: `frontend/scripts/benchmark-terminal.mjs`
- Create: `frontend/scripts/benchmark-artifact.mjs`
- Create: `frontend/perf/scenarios.json`
- Modify: `frontend/src/renderer/routes/_shell.tsx`
- Modify: `frontend/package.json`

**Interfaces:**
- Produces JSON containing `schemaVersion`, `shell`, `scenario`, `commit`, `dirty`, `buildProfile`, platform metadata, scenario configuration, warmups, samples, `median`, `p95`, and `unit`.
- Produces renderer marks `operator:board-interactive` and `operator:terminal-ready`; marks contain timestamps only.

- [ ] **Step 1: Write failing result tests**

Reject unknown fields, fewer than required samples, non-finite samples, missing hardware/webview metadata, absolute paths, PID-like fields, and result paths outside `perf/results`. Assert median and nearest-rank p95 for a fixed sample vector.

- [ ] **Step 2: Run the tests**

```bash
cd frontend
node --test scripts/benchmark-result.test.mjs
```

Expected: FAIL because the result module is absent.

- [ ] **Step 3: Implement instrumented runners**

Use Playwright's Electron support for launch and renderer marks. Measure warm start from process spawn to `operator:board-interactive`, first-run start through daemon readiness, full Electron process-tree RSS/working set at 60 seconds, signed/download and installed artifact bytes, and terminal scenarios through the real mux. Do not infer rendered completion from bytes written; wait for the terminal harness acknowledgement defined in Task 4.

- [ ] **Step 4: Capture Electron baselines on native runners**

```bash
cd frontend
npm run bench:shell -- --shell electron --scenario warm-start
npm run bench:shell -- --shell electron --scenario first-run
npm run bench:shell -- --shell electron --scenario idle-memory
npm run bench:terminal -- --shell electron --scenario vtebench
npm run bench:terminal -- --shell electron --scenario large-output
npm run bench:artifact -- --shell electron
```

Expected: sanitized results for every supported platform; do not commit single-machine results as three-platform evidence.

- [ ] **Step 5: Verify and commit**

```bash
cd frontend
node --test scripts/benchmark-result.test.mjs
git add package.json scripts/benchmark-*.mjs perf/scenarios.json perf/results src/renderer/routes/_shell.tsx ../docs/benchmarks/tauri-port-baseline.md
git commit -m "test: add honest electron performance baselines"
```

### Task 3: Add the pinned Tauri Phase 0 scaffold and origin boundary

**Files:**
- Create: `frontend/rust-toolchain.toml`
- Create: `frontend/src-tauri/Cargo.toml`
- Create: `frontend/src-tauri/Cargo.lock`
- Create: `frontend/src-tauri/build.rs`
- Create: `frontend/src-tauri/src/lib.rs`
- Create: `frontend/src-tauri/src/main.rs`
- Create: `frontend/src-tauri/tauri.conf.json`
- Create: `frontend/src-tauri/tauri.windows.conf.json`
- Create: `frontend/src-tauri/capabilities/phase0.json`
- Create: `frontend/scripts/audit-tauri-state.mjs`
- Create: `.github/workflows/tauri-phase0.yml`
- Modify: `frontend/package.json`
- Modify: `backend/internal/config/config.go`
- Modify: `backend/internal/config/config_test.go`
- Modify: `backend/internal/httpd/cors_test.go`

**Interfaces:**
- Produces `npm run tauri:dev`, `npm run tauri:build`, and exact allowed origins `tauri://localhost` and `http://tauri.localhost`.
- Pins Rust 1.96.0, `tauri = "=2.11.5"`, `tauri-build = "=2.6.3"`, npm CLI 2.11.4, and API 2.11.1.

- [ ] **Step 1: Write failing Rust state-root and Go CORS tests**

Rust tests require `OPERATOR_DATA_DIR` precedence, separate `~/.operator/dev/tauri` development root, and failure when no safe root resolves. Go tests accept both exact Tauri origins and continue rejecting `null`, `*`, `http://tauri.localhost.evil.example`, `https://tauri.localhost`, and `tauri://evil.example`.

- [ ] **Step 2: Run the focused failures**

```bash
cd frontend/src-tauri && cargo test state_root
cd ../../backend && go test ./internal/config ./internal/httpd -run 'AllowedOrigins|CORS'
```

Expected: FAIL because Tauri origins and crate do not exist.

- [ ] **Step 3: Implement the minimal scaffold**

Keep Windows `useHttpsScheme` false so the renderer can reach the HTTP loopback daemon without mixed-content blocking. Create the application window programmatically only after resolving the state root. Grant only core window/event permissions needed for the spike. Keep Electron commands intact for dual-shell development.

- [ ] **Step 4: Implement and run the state audit**

The audit snapshots the Operator root and known OS app-data/cache locations before and after launch, local/session storage, cookie, cache, crash, and shutdown operations. It fails on any new Operator-owned state outside the allowed root. Run it on all three native CI runners, including the minimum supported macOS version.

- [ ] **Step 5: Verify and commit**

```bash
cd frontend/src-tauri && cargo fmt --check && cargo test
cd ../../backend && go test ./internal/config ./internal/httpd -run 'AllowedOrigins|CORS'
cd ../frontend && npm run typecheck
git add rust-toolchain.toml src-tauri package.json scripts/audit-tauri-state.mjs ../backend/internal/config ../backend/internal/httpd/cors_test.go ../.github/workflows/tauri-phase0.yml
git commit -m "feat(tauri): add phase zero shell and origin boundary"
```

### Task 4: Measure the real terminal in every target webview

**Files:**
- Create: `frontend/perf/terminal/index.html`
- Create: `frontend/perf/terminal/main.tsx`
- Create: `frontend/perf/terminal/harness.tsx`
- Create: `frontend/perf/terminal/harness.test.tsx`
- Create: `frontend/vite.terminal-perf.config.ts`
- Modify: `frontend/src/renderer/components/XtermTerminal.tsx`
- Modify: `frontend/scripts/benchmark-terminal.mjs`

**Interfaces:**
- Consumes a live daemon base URL, session ID, terminal ID, fixed 120×40 grid, and production `XtermTerminal`.
- Emits renderer kind and timestamp-only acknowledgements for first paint, workload completion, resize, reconnect, and disposal.

- [ ] **Step 1: Write the failing harness tests**

Assert the harness mounts the production component, refuses non-loopback daemon URLs, fixes rows/columns and scrollback from `perf/scenarios.json`, reports `webgl|canvas`, never records terminal content, and disposes on unmount.

- [ ] **Step 2: Run the failure**

```bash
cd frontend
npx vitest run --config vite.renderer.config.ts perf/terminal/harness.test.tsx
```

Expected: FAIL because the separate performance entry does not exist.

- [ ] **Step 3: Implement without production routing changes**

Add a renderer-kind and timestamp callback to `XtermTerminal`; do not alter mux transport, parsing, renderer fallback, fit stabilization, or production routes. Build the harness only with `vite.terminal-perf.config.ts`.

- [ ] **Step 4: Run the cross-platform matrix**

Measure open-to-interactive and reconnect latency, `vtebench`, fixed large output, input-to-render p95, active-terminal process-tree memory and workload CPU time, vim, htop, an agent TUI, box drawing, Powerline, emoji, CJK, selection, scrollback, resize, and WebGL context recovery. Run Linux with compositing enabled and disabled.

- [ ] **Step 5: Verify and commit**

```bash
cd frontend
npx vitest run --config vite.renderer.config.ts perf/terminal/harness.test.tsx
npm run bench:terminal -- --shell tauri --scenario vtebench
npm run bench:terminal -- --shell tauri --scenario large-output
git add perf/terminal perf/results vite.terminal-perf.config.ts scripts/benchmark-terminal.mjs src/renderer/components/XtermTerminal.tsx
git commit -m "test: measure production terminal in tauri webviews"
```

### Task 5: Prove standalone agent-browser automation

**Files:**
- Create: `frontend/scripts/agent-browser-phase0.mjs`
- Create: `frontend/scripts/agent-browser-phase0.test.mjs`
- Create: `frontend/perf/browser/scenarios.json`
- Modify: `.github/workflows/tauri-phase0.yml`

**Interfaces:**
- Consumes packaged agent-browser 0.33.1 and an isolated temporary Operator root.
- Produces sanitized pass/fail evidence for system-browser discovery, managed install, session isolation, actions, cleanup, and no-Electron operation.

- [ ] **Step 1: Write failing harness tests**

Mock process execution and test exact environment allowlisting, serialized install, partial-download cleanup, separate session homes, timeout/cancellation, output limits, and rejection of `--cdp`, `--auto-connect`, user profiles, arbitrary executable paths, plugins, proxy credentials, and unsafe startup arguments.

- [ ] **Step 2: Run the failure**

```bash
cd frontend
node --test scripts/agent-browser-phase0.test.mjs
```

Expected: FAIL because the spike harness does not exist.

- [ ] **Step 3: Implement the native probe**

Run `agent-browser doctor --json` with all home/cache/config variables under the temporary Operator root. Test discovered Chrome/Edge/Chromium first. In a separate scenario run `agent-browser install`, locate the managed executable, then execute `open`, `snapshot`, `click`, `console`, `errors`, `screenshot`, tab operations, and `close` without `AGENT_BROWSER_CDP` and with no Electron process.

- [ ] **Step 4: Execute on all native runners**

The workflow uploads only sanitized JSON and screenshots of the controlled fixture page. Network failure and absent-browser cases must return stable codes and leave no active daemon or partial engine directory.

- [ ] **Step 5: Verify and commit**

```bash
cd frontend
node --test scripts/agent-browser-phase0.test.mjs
node scripts/agent-browser-phase0.mjs --mode system
node scripts/agent-browser-phase0.mjs --mode managed
git add scripts/agent-browser-phase0.mjs scripts/agent-browser-phase0.test.mjs perf/browser ../.github/workflows/tauri-phase0.yml
git commit -m "test: prove standalone browser automation"
```

### Task 6: Prove packaging/signing feasibility and apply the kill gate

**Files:**
- Create: `frontend/scripts/phase0-decision.mjs`
- Create: `frontend/scripts/phase0-decision.test.mjs`
- Create: `frontend/scripts/phase0-legacy-update.mjs`
- Create: `frontend/scripts/phase0-legacy-update.test.mjs`
- Create: `frontend/scripts/phase0-updater-signing.mjs`
- Modify: `frontend/src-tauri/tauri.conf.json`
- Modify: `frontend/src-tauri/Cargo.toml`
- Modify: `docs/benchmarks/tauri-port-baseline.md`
- Modify: `.github/workflows/tauri-phase0.yml`

**Interfaces:**
- Consumes state audit, CORS, terminal, browser, artifact, RPM, updater-signing, and Electron-to-Tauri migration evidence for all platforms.
- Produces exactly one `continue|linux-canvas|drop-platform|stop-port` decision with reasons.

- [ ] **Step 1: Write failing decision tests**

Assert missing platform evidence, a state leak, failed standalone automation, macOS/Windows canvas, terminal regression, missing ACP runtime, missing RPM, changed application identity, failed legacy-update migration, or invalid updater signature produces `stop-port`; only the documented Linux canvas exception produces `linux-canvas`.

- [ ] **Step 2: Run the failure**

```bash
cd frontend
node --test scripts/phase0-decision.test.mjs scripts/phase0-legacy-update.test.mjs
```

Expected: FAIL because the decision tool is absent.

- [ ] **Step 3: Build real feasibility bundles**

Bundle daemon, agent-browser, ACP runtime, renderer, and Tauri shell while preserving `dev.operator.desktop`, `Operator.app`, executable `operator`, and current artifact aliases. Build app/dmg on macOS, NSIS on Windows, and AppImage/deb/rpm on Linux. Generate an ephemeral updater keypair in a temporary directory, sign a fixture archive, verify it, and prove no private key enters output or git status. From the last Electron release, exercise direct update into locally test-signed Tauri candidates on every platform. If a platform cannot replace directly, build and prove a signed Electron bridge-release handoff and record it as mandatory rollout work.

- [ ] **Step 4: Record the mechanical decision**

```bash
cd frontend
node scripts/phase0-decision.mjs --results perf/results --write ../docs/benchmarks/tauri-port-baseline.md
```

Expected: exactly one decision. Stop here unless it is `continue` or `linux-canvas`.

- [ ] **Step 5: Verify and commit**

```bash
cd frontend
node --test scripts/phase0-decision.test.mjs scripts/phase0-legacy-update.test.mjs
npm run tauri:build
git add scripts/phase0-*.mjs src-tauri perf/results ../docs/benchmarks/tauri-port-baseline.md ../.github/workflows/tauri-phase0.yml
git commit -m "docs: record tauri phase zero decision"
```

### Task 7: Port daemon supervision and packaged sidecar discovery to Rust

**Files:**
- Create: `frontend/src-tauri/src/daemon/mod.rs`
- Create: `frontend/src-tauri/src/daemon/discovery.rs`
- Create: `frontend/src-tauri/src/daemon/supervisor.rs`
- Create: `frontend/src-tauri/src/daemon/tests.rs`
- Modify: `frontend/src-tauri/src/lib.rs`
- Modify: `frontend/src-tauri/tauri.conf.json`
- Modify: `backend/internal/config/config.go`

**Interfaces:**
- Produces commands `daemon_status`, `daemon_start`, `daemon_stop`, and `daemon_restart` returning the existing `DaemonStatus` JSON shape.
- Passes `OPERATOR_APP_RUN_ID`, `OPERATOR_RUN_FILE`, `OPERATOR_DATA_DIR`, `OPERATOR_ACP_RUNTIME_DIR`, app version, and resource roots to the daemon.

- [ ] **Step 1: Write failing Rust contract tests**

Cover healthy-daemon attachment, stale run file, one-start concurrency, readiness timeout, captured error output, `OPERATOR_KEEP_DAEMON`, supervisor-link reconnection after restart, close behavior, and discovery of daemon, agent-browser, and ACP runtime in dev and packaged layouts.

- [ ] **Step 2: Run the failure**

```bash
cd frontend/src-tauri
cargo test daemon
```

Expected: FAIL because the daemon modules do not exist.

- [ ] **Step 3: Port the exact ownership contract**

Translate behavior from `frontend/src/main/daemon-owner.ts`, `frontend/src/main/supervisor-link.ts`, and the relevant `frontend/src/main.ts` paths. The daemon remains the `running.json` writer. Do not carry the Electron browser-runtime token into the Tauri supervisor. Make the backend's `OPERATOR_APP_RUN_ID` contract shell-neutral without changing its behavior.

- [ ] **Step 4: Verify with real processes and commit**

```bash
cd frontend/src-tauri
cargo test daemon
cd ..
npm run tauri:dev
git add src-tauri ../backend/internal/config/config.go
git commit -m "feat(tauri): supervise daemon and sidecars"
```

Verify attach, start, restart, close/reopen, externally started daemon, and missing-resource errors before committing.

### Task 8: Introduce the shell-neutral bridge and shared type boundary

**Files:**
- Create: `frontend/src/shared/operator-bridge.ts`
- Create: `frontend/src/renderer/lib/tauri-bridge.ts`
- Create: `frontend/src/renderer/lib/bridge.test.ts`
- Modify: `frontend/src/renderer/lib/bridge.ts`
- Modify: `frontend/src/renderer/global.d.ts`
- Modify: `frontend/src/renderer/test/setup.ts`
- Modify: `frontend/src/renderer/lib/api-client.ts`
- Modify: `frontend/e2e/support/fake-bridge.ts`
- Modify: `frontend/perf/parity-ledger.json`

**Interfaces:**
- Produces `OperatorBridge`, `createElectronBridge(window.operator)`, and `createTauriBridge({invoke, listen})`.
- The Tauri bridge contains no `browser` namespace; deferred browser members remain Electron-only until Task 16 removes their consumers.

- [ ] **Step 1: Write failing bridge tests**

Assert Tauri selection from `window.__TAURI_INTERNALS__`, Electron selection during coexistence, browser fallback for `VITE_NO_ELECTRON=1`, identical daemon status subscription/unsubscription, and compile-time ownership of every non-browser shared type.

- [ ] **Step 2: Run the failure**

```bash
cd frontend
npx vitest run --config vite.renderer.config.ts src/renderer/lib/bridge.test.ts
```

Expected: FAIL because renderer types still depend on Electron preload/main modules.

- [ ] **Step 3: Move shared contracts without behavior changes**

Move `DaemonStatus`, migration, UI settings, update settings/status/options/outcome, feature build, import scan, tray, shortcut, and native bridge types to `frontend/src/shared/`. Update preload, renderer, and the renderer-only E2E fake bridge imports. Do not delete Electron implementations.

- [ ] **Step 4: Verify imports and commit**

```bash
cd frontend
npx vitest run --config vite.renderer.config.ts src/renderer/lib/bridge.test.ts
npm run typecheck
npm run typecheck:e2e
npm run check:desktop-parity
git add src/shared src/renderer src/preload.ts e2e/support/fake-bridge.ts perf/parity-ledger.json
git commit -m "refactor(renderer): establish shell neutral desktop bridge"
```

### Task 9: Extend the existing daemon settings source of truth

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0088_desktop_settings.sql`
- Modify: `backend/internal/storage/sqlite/queries/app_settings.sql`
- Modify: `backend/internal/service/settings/service.go`
- Create: `backend/internal/service/settings/service_test.go`
- Modify: `backend/internal/httpd/controllers/settings.go`
- Create: `backend/internal/httpd/controllers/settings_test.go`
- Modify: `backend/internal/httpd/controllers/dto.go`
- Modify: `backend/internal/httpd/apispec/specgen/build.go`
- Modify: `frontend/src/renderer/lib/tauri-bridge.ts`

**Interfaces:**
- Extends `GET /api/v1/settings`.
- Adds `PATCH /api/v1/settings/ui`, `/updates`, `/keybindings`, and `/migration`.
- `0088` adds `ui_locale`, update opt-in/channel/nightly/feature fields, `keybindings_json`, `migration_json`, and `legacy_desktop_imported_at` to singleton `app_settings`.

- [ ] **Step 1: Write failing service and controller tests**

Cover existing `defaultSessionMode`, locale validation/fallback, update channel and PR validation, platform-specific keybinding coercion, migration state transitions, concurrent updates preserving unrelated fields, API error envelopes, and CDC trigger output.

- [ ] **Step 2: Run focused failures**

```bash
cd backend
go test ./internal/service/settings ./internal/httpd/controllers -run 'Settings|Migration|Keybinding|Update'
```

Expected: FAIL because migration `0088` and endpoints do not exist.

- [ ] **Step 3: Implement through existing boundaries**

Keep one `app_settings` row and one settings service. Add SQL queries rather than editing generated files. Preserve the current session-mode API and defaults.

- [ ] **Step 4: Regenerate, verify, and commit**

```bash
npm run sqlc
npm run api
cd backend
go test ./internal/service/settings ./internal/httpd/controllers ./internal/httpd/...
cd ../frontend
npm run typecheck
git add ../backend/internal/storage/sqlite ../backend/internal/service/settings ../backend/internal/httpd src/api/schema.ts src/renderer/lib/tauri-bridge.ts
git commit -m "feat(settings): share desktop preferences through daemon"
```

### Task 10: Import legacy settings once and move local scan controls to Go

**Files:**
- Create: `backend/internal/adapters/projectscan/scan.go`
- Create: `backend/internal/adapters/projectscan/scan_test.go`
- Create: `backend/internal/service/settings/legacy_import.go`
- Create: `backend/internal/service/settings/legacy_import_test.go`
- Create: `backend/internal/httpd/controllers/dev_desktop.go`
- Create: `backend/internal/httpd/controllers/dev_desktop_test.go`
- Modify: `backend/internal/httpd/controllers/dev.go`
- Modify: `backend/internal/httpd/api.go`
- Modify: `backend/internal/daemon/daemon.go`
- Modify: `frontend/src/renderer/lib/tauri-bridge.ts`

**Interfaces:**
- Produces `POST /api/v1/dev/import-scan` and `POST /api/v1/dev/ancestor-repository` on the already LAN-blocked developer prefix.
- Imports `ui-settings.json`, `update-settings.json`, `keybindings.json`, and the `app-state.json` migration block once before serving settings.

- [ ] **Step 1: Write failing boundary tests**

Cover valid, missing, and corrupt legacy files; stale files after import; atomic all-field import; 200-entry scan limit; eight workers; five-second Git timeout; symlink loops; non-repository folders; cancellation; and LAN requests receiving 404 for both new routes.

- [ ] **Step 2: Run the failures**

```bash
cd backend
go test ./internal/service/settings ./internal/adapters/projectscan ./internal/httpd/controllers ./internal/httpd -run 'Legacy|ImportScan|Ancestor|LAN'
```

Expected: FAIL because the adapter and routes do not exist.

- [ ] **Step 3: Port current behavior**

Translate bounded behavior from `frontend/src/main/import-folder-scan.ts` and `frontend/src/main.ts`. Resolve the Operator state root from daemon config. Mark import complete only after the SQLite transaction commits.

- [ ] **Step 4: Verify and commit**

```bash
cd backend
go test ./internal/service/settings ./internal/adapters/projectscan ./internal/httpd/controllers ./internal/httpd
git add internal/adapters/projectscan internal/service/settings internal/httpd internal/daemon/daemon.go ../frontend/src/renderer/lib/tauri-bridge.ts
git commit -m "feat(daemon): import desktop state and own project scans"
```

### Task 11: Move renderer telemetry bootstrap behind the loopback daemon

**Files:**
- Create: `backend/internal/httpd/desktop_telemetry.go`
- Create: `backend/internal/httpd/desktop_telemetry_test.go`
- Modify: `backend/internal/httpd/router.go`
- Modify: `backend/internal/config/config.go`
- Modify: `frontend/src/renderer/lib/tauri-bridge.ts`
- Modify: `frontend/src/renderer/lib/telemetry.ts`

**Interfaces:**
- Produces loopback-only `GET /internal/desktop/telemetry-bootstrap` returning either `null` or `{distinctId, appVersion, platform, disabledEvents}`.
- Reuses the daemon's telemetry install ID and configuration; no second ID file is created.

- [ ] **Step 1: Write failing Go and renderer tests**

Cover packaged/default enablement, development opt-in/out, disabled-event parsing, stable install ID, no bootstrap when disabled, loopback success, LAN 404 through the existing `/internal/` block, and renderer failure degrading to disabled telemetry.

- [ ] **Step 2: Run the failures**

```bash
cd backend && go test ./internal/httpd -run DesktopTelemetry
cd ../frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/telemetry.test.ts
```

Expected: FAIL because the endpoint and Tauri reader do not exist.

- [ ] **Step 3: Implement one source of truth**

Pass app version and packaged/development telemetry intent through Rust supervisor environment. The Go handler reads daemon config and the existing telemetry ID logic. Keep Electron bootstrap operational until deletion.

- [ ] **Step 4: Verify and commit**

```bash
cd backend && go test ./internal/httpd ./internal/adapters/telemetry
cd ../frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/telemetry.test.ts && npm run typecheck
git add ../backend/internal/httpd ../backend/internal/config src/renderer/lib
git commit -m "feat(telemetry): serve desktop bootstrap from daemon"
```

### Task 12: Preserve app-state marker, relocation, and `opr start`

**Files:**
- Create: `frontend/src-tauri/src/app_state.rs`
- Create: `frontend/src-tauri/src/relocation.rs`
- Create: `frontend/src-tauri/src/app_state_tests.rs`
- Modify: `frontend/src-tauri/src/lib.rs`
- Modify: `backend/internal/cli/start.go`
- Modify: `backend/internal/cli/start_test.go`
- Modify: `frontend/perf/parity-ledger.json`

**Interfaces:**
- Rust writes schema-version-2 `~/.operator/app-state.json` atomically on every launch.
- `opr start` discovers Tauri macOS, Windows, and Linux layouts while retaining `Operator.app`, executable `operator`, the existing version-free artifact aliases, marker validation, and known-location fallbacks.

- [ ] **Step 1: Write failing Rust and Go tests**

Cover first-write provenance, sticky `installedAt/installSource`, refreshed path/version/time, preserved migration block, corrupt marker recovery, atomic rename, exact bundle-path resolution, and relocation `stay|relocate|handoff` decisions including unreadable versions. Go tests cover Tauri layouts while locking the existing executable and artifact names on all platforms.

- [ ] **Step 2: Run the failures**

```bash
cd frontend/src-tauri && cargo test app_state && cargo test relocation
cd ../../backend && go test ./internal/cli -run Start
```

Expected: FAIL because Rust marker/relocation modules do not exist.

- [ ] **Step 3: Port behavior without destructive shortcuts**

Mirror `frontend/src/main/app-state.ts` and `frontend/src/main/relocation.ts`. Never overwrite an equal/newer or unreadable `/Applications` bundle. Write the pre-relocation marker when `--installed-via` is present, then refresh after handoff/relocation.

- [ ] **Step 4: Verify and commit**

```bash
cd frontend/src-tauri && cargo test app_state && cargo test relocation
cd ../../backend && go test ./internal/cli -run Start
git add ../frontend/src-tauri ../frontend/perf/parity-ledger.json internal/cli/start.go internal/cli/start_test.go
git commit -m "feat(tauri): preserve install marker and relocation"
```

### Task 13: Port window, menu, theme, and shortcut behavior

**Files:**
- Create: `frontend/src-tauri/src/window.rs`
- Create: `frontend/src-tauri/src/menu.rs`
- Create: `frontend/src-tauri/src/shortcuts.rs`
- Create: `frontend/src-tauri/src/native_contract_tests.rs`
- Modify: `frontend/src-tauri/src/lib.rs`
- Create: `frontend/src-tauri/capabilities/default.json`
- Modify: `frontend/src/renderer/lib/tauri-bridge.ts`
- Modify: `frontend/perf/parity-ledger.json`

**Interfaces:**
- Implements window overlay/fullscreen events, native theme hints, menu actions, shortcut recording suppression, close-terminal enablement, and all eleven shortcut events named in the parity ledger.

- [ ] **Step 1: Write failing policy tests**

Use fake registrars/windows to test accelerator mapping on macOS versus Windows/Linux, conflict reporting, re-registration after settings changes, recording suppression, fullscreen events, overlay colors, and every menu/shortcut event name.

- [ ] **Step 2: Run the failure**

```bash
cd frontend/src-tauri
cargo test native_contract
```

Expected: FAIL because native modules do not exist.

- [ ] **Step 3: Implement exact capabilities and verify**

Pin `tauri-plugin-global-shortcut = "=2.3.2"`. Grant only its register/unregister permissions and required core window/event permissions. Persist shortcut changes through Go before applying them natively.

- [ ] **Step 4: Commit**

```bash
cd frontend/src-tauri && cargo fmt --check && cargo test native_contract
cd .. && npm run typecheck && npm run check:desktop-parity
git add src-tauri src/renderer/lib/tauri-bridge.ts perf/parity-ledger.json
git commit -m "feat(tauri): port window menu and shortcuts"
```

### Task 14: Port dialogs, opener, clipboard, notifications, tray, and file drops

**Files:**
- Create: `frontend/src-tauri/src/native.rs`
- Create: `frontend/src-tauri/src/tray.rs`
- Create: `frontend/src-tauri/src/notification_policy.rs`
- Create: `frontend/src-tauri/src/dropped_files.rs`
- Create: `frontend/src-tauri/src/dropped_files_tests.rs`
- Modify: `frontend/src-tauri/Cargo.toml`
- Modify: `frontend/src-tauri/src/lib.rs`
- Modify: `frontend/src-tauri/capabilities/default.json`
- Modify: `frontend/src/renderer/lib/tauri-bridge.ts`
- Modify: `frontend/perf/parity-ledger.json`

**Interfaces:**
- Implements directory selection, HTTP(S) external open, clipboard read/write, notification/click/badge behavior, notification attention/toast policy, tray attention/open-session behavior, and `saveDroppedFile`.
- Stages dropped files beneath `<state-root>/terminal-drops`; maximum input is 64 MiB and files older than seven days are pruned on startup.

- [ ] **Step 1: Write failing native tests**

Test opener allowlisting, chooser cancellation, Linux primary-selection clipboard behavior where supported, toast/attention suppression and notification ID routing, tray state mapping, filename sanitization, 64-MiB rejection, collision resistance, atomic writes, seven-day pruning, and refusal to delete paths outside the owned drop directory.

- [ ] **Step 2: Run the failure**

```bash
cd frontend/src-tauri
cargo test native && cargo test dropped_files
```

Expected: FAIL because the implementations do not exist.

- [ ] **Step 3: Implement pinned plugins and minimum grants**

Pin dialog 2.7.2, opener 2.5.4, clipboard-manager 2.3.2, and notification 2.3.3 in Cargo and matching npm packages where JavaScript bindings are used. Do not grant filesystem, shell, HTTP, or process wildcards.

- [ ] **Step 4: Verify on every OS and commit**

```bash
cd frontend/src-tauri && cargo fmt --check && cargo test native && cargo test dropped_files
cd .. && npm run typecheck && npm run check:desktop-parity
git add src-tauri src/renderer/lib/tauri-bridge.ts perf/parity-ledger.json package.json package-lock.json
git commit -m "feat(tauri): port desktop native integrations"
```

### Task 15: Implement the production standalone agent-browser adapter

**Files:**
- Create: `backend/internal/adapters/agentbrowser/install.go`
- Create: `backend/internal/adapters/agentbrowser/install_test.go`
- Create: `backend/internal/adapters/agentbrowser/runtime.go`
- Create: `backend/internal/adapters/agentbrowser/runtime_test.go`
- Create: `backend/internal/adapters/agentbrowser/policy.go`
- Create: `backend/internal/adapters/agentbrowser/policy_test.go`
- Create: `backend/internal/service/browser/runtime.go`
- Modify: `backend/internal/service/browser/service.go`
- Modify: `backend/internal/service/browser/service_test.go`
- Modify: `backend/internal/httpd/controllers/browser.go`
- Modify: `backend/internal/httpd/controllers/browser_test.go`
- Modify: `backend/internal/daemon/daemon.go`

**Interfaces:**
- Defines adapter-neutral `RuntimeStatus`, `RuntimeResult`, and `Runtime` contracts in the browser service, then implements `Runtime.Status(sessionID)`, `Runtime.Execute(ctx, sessionID, action, args)`, and `Runtime.DestroySession(ctx, sessionID)` in the standalone adapter. No public controller or service type may import the Electron broker package.
- Reports transport `agent-browser-standalone` and preserves existing capability authorization and public action names.

- [ ] **Step 1: Write failing install, policy, and runtime tests**

Port every applicable case from `frontend/src/main/agent-browser-runtime.test.ts`. Add serialized system-browser discovery/managed install, pinned version validation, partial-install cleanup, per-session roots, environment allowlisting, action-to-native-argument mapping, forbidden flags, count/size/output limits, timeout, cancellation, concurrent sessions, stale-owner scavenging, screenshot limits, and safe teardown.

- [ ] **Step 2: Run the failures**

```bash
cd backend
go test ./internal/adapters/agentbrowser ./internal/service/browser ./internal/httpd/controllers -run 'AgentBrowser|Browser'
```

Expected: FAIL because the adapter does not exist.

- [ ] **Step 3: Implement from Phase 0 evidence**

Use `~/.operator/browser-engine` only for shared managed engine files and `~/.operator/browser-runtime/<run>/<session>` for isolated writable state. Never set `AGENT_BROWSER_CDP`, auto-connect, the user's profile, or the user's home. Keep the Electron broker wired behind the Electron shell only until Task 16 proves API parity.

- [ ] **Step 4: Verify real actions and commit**

```bash
cd backend
go test ./internal/adapters/agentbrowser ./internal/service/browser ./internal/httpd/controllers ./internal/cli
git add internal/adapters/agentbrowser internal/service/browser internal/httpd/controllers/browser.go internal/httpd/controllers/browser_test.go internal/daemon/daemon.go
git commit -m "feat(browser): own standalone automation in daemon"
```

Run the Phase 0 fixture with `open`, `snapshot`, `click`, `console`, `errors`, `screenshot`, tabs, and teardown before committing.

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

### Task 17: Rebuild update state, feature channels, and updater events

**Files:**
- Create: `frontend/src-tauri/src/updater/mod.rs`
- Create: `frontend/src-tauri/src/updater/channel.rs`
- Create: `frontend/src-tauri/src/updater/status.rs`
- Create: `frontend/src-tauri/src/updater/escalation.rs`
- Create: `frontend/src-tauri/src/updater/storage.rs`
- Create: `frontend/src-tauri/src/updater/tests.rs`
- Modify: `frontend/src-tauri/Cargo.toml`
- Modify: `frontend/src-tauri/src/lib.rs`
- Modify: `frontend/src-tauri/capabilities/default.json`
- Modify: `frontend/src/renderer/lib/tauri-bridge.ts`
- Modify: `frontend/perf/parity-ledger.json`

**Interfaces:**
- Implements current `updates` and `featureBuilds` bridge methods, status/telemetry events, staged-update escalation policy, and updater storage beneath `<state-root>/updater`.
- Reads opt-in, `latest|nightly`, nightly acknowledgement, and `pr<N>` feature pin from `/api/v1/settings`.

- [ ] **Step 1: Write failing updater state-machine tests**

Port behavior tests from `frontend/src/main/auto-updater.test.ts`, `feature-builds.test.ts`, and `escalation-evaluator.test.ts`: disabled state, first-run opt-in, manual/automatic checks, automatic failure status suppression with telemetry retained, download/install progress, concurrent request IDs, latest 48-hour escalation, important-nightly and stable-version escalation, downgrade, pin clearing, return-home, channel URL selection, active feature reporting, interrupted-download recovery, and refusal to stage or clean paths outside `<state-root>/updater`.

- [ ] **Step 2: Run the failure**

```bash
cd frontend/src-tauri
cargo test updater
```

Expected: FAIL because the Rust updater state machine does not exist.

- [ ] **Step 3: Implement the pinned updater plugin**

Pin `tauri-plugin-updater = "=2.10.1"` and the matching npm API where used. Compile in only the public verification key. Require HTTPS for production feeds and reject private-key-shaped configuration. Persist settings through Go before changing active channel state. Prove the plugin's download, temporary, and recovery writes remain beneath `<state-root>/updater`; if its built-in path cannot do so, replace it with a project-owned verified download/apply implementation or stop the port.

- [ ] **Step 4: Verify and commit**

```bash
cd frontend/src-tauri && cargo fmt --check && cargo test updater
cd .. && npm run typecheck && npm run check:desktop-parity
git add src-tauri src/renderer/lib/tauri-bridge.ts perf/parity-ledger.json package.json package-lock.json
git commit -m "feat(tauri): rebuild updater state and channels"
```

### Task 18: Build signed feeds and platform artifacts

**Files:**
- Create: `frontend/src-tauri/tauri.release.conf.json`
- Create: `frontend/scripts/tauri-feed.mjs`
- Create: `frontend/scripts/tauri-feed.test.mjs`
- Create: `frontend/scripts/package-tauri-mac-zip.sh`
- Create: `frontend/scripts/verify-tauri-artifacts.sh`
- Modify: `frontend/scripts/feed.mjs`
- Modify: `frontend/scripts/feed.test.mjs`
- Modify: `frontend/scripts/e2e-mac-update.mjs`
- Modify: `frontend/scripts/e2e-mac-update.test.mjs`
- Modify: `frontend/scripts/verify-mac-artifact.sh`
- Modify: `frontend/docs/desktop-release.md`
- Modify: `frontend/package.json`
- Modify: `.github/workflows/build-artifacts.yml`
- Modify: `.github/workflows/desktop-testing.yml`
- Modify: `.github/workflows/testing-build.yml`
- Modify: `.github/workflows/frontend-release.yml`
- Modify: `.github/workflows/feature-release.yml`
- Modify: `.github/workflows/mac-update-e2e.yml`
- Modify: `.github/workflows/release-latest-guard.yml`

**Interfaces:**
- Produces Tauri `latest.json`, `nightly.json`, and `pr<N>.json` feeds plus the stable/nightly/feature Electron-compatibility YAML feeds used by the installed fleet, including permanent `latest-mac.yml`.
- Produces macOS app/dmg/zip/updater archive, Windows NSIS/updater archive, and Linux AppImage/deb/rpm/updater artifacts while preserving `operator-darwin-{arm64,x64}.zip`, `operator-darwin-{arm64,x64}.dmg`, `operator-win32-x64.exe`, `operator-linux-x64.AppImage`, and deb/rpm aliases.
- Every base artifact includes daemon, agent-browser, ACP runtime, licenses, and required icons.

- [ ] **Step 1: Write failing feed tests**

Reject invalid semver, missing signature, wrong OS/architecture, cross-channel assets, insecure production URL, duplicate platform, absent required sidecar, a feature release that writes stable/nightly feeds, and any private-key material. Assert deterministic ordering, correct updater archive selection, compatibility YAML generation, permanent macOS zip/`latest-mac.yml`, and unchanged version-free aliases.

- [ ] **Step 2: Run the failure**

```bash
cd frontend
node --test scripts/tauri-feed.test.mjs
node --test scripts/feed.test.mjs scripts/e2e-mac-update.test.mjs
```

Expected: FAIL because the feed builder does not exist.

- [ ] **Step 3: Implement artifact construction and verification**

Archive the signed macOS app with `ditto -c -k --sequesterRsrc --keepParent`. Keep DMG and zip as release artifacts in addition to Tauri updater archives. Verify both with the existing mac script. Port every existing Electron/Forge release, testing-build, artifact, feature-channel, update-E2E, and latest-release guard workflow to the Tauri commands; do not leave parallel stale workflows. Inspect resources inside every platform package before generating feeds.

- [ ] **Step 4: Run real native update tests**

Test signed latest, nightly, feature-pin downgrade, return-home, and pin-clearing updates. On all three platforms, test both Tauri-to-Tauri updates and the Phase 0 Electron-to-Tauri migration or mandatory bridge-release path. Install NSIS on Windows, update a macOS app copy, and validate Linux package contents and signatures. A designated release conductor remains the only publisher.

- [ ] **Step 5: Verify and commit**

```bash
cd frontend
node --test scripts/tauri-feed.test.mjs
node --test scripts/feed.test.mjs scripts/e2e-mac-update.test.mjs
npm run verify:tauri-artifacts
git add src-tauri/tauri.release.conf.json scripts/tauri-* scripts/feed.mjs scripts/feed.test.mjs scripts/e2e-mac-update.mjs scripts/e2e-mac-update.test.mjs scripts/package-tauri-mac-zip.sh scripts/verify-tauri-artifacts.sh scripts/verify-mac-artifact.sh docs/desktop-release.md package.json ../.github/workflows/build-artifacts.yml ../.github/workflows/desktop-testing.yml ../.github/workflows/testing-build.yml ../.github/workflows/frontend-release.yml ../.github/workflows/feature-release.yml ../.github/workflows/mac-update-e2e.yml ../.github/workflows/release-latest-guard.yml
git commit -m "feat(release): build signed tauri artifacts and feeds"
```

### Task 19: Reduce renderer startup and retained memory from measurements

**Files:**
- Create: `frontend/scripts/route-bundle-report.mjs`
- Create: `frontend/scripts/route-bundle-report.test.mjs`
- Create: `frontend/scripts/heap-summary.mjs`
- Modify: `frontend/src/renderer/routes/`
- Modify: `frontend/src/renderer/components/TerminalPane.tsx`
- Modify: `frontend/src/renderer/components/XtermTerminal.tsx`
- Modify: `docs/benchmarks/tauri-port-baseline.md`

**Interfaces:**
- Produces checked-in initial-route graph, parsed-byte summary, empty-board heap summary, terminal-disposal evidence, and before/after shell results.
- Consumes existing TanStack `autoCodeSplitting: true`; changes only eager edges or retainers proven by reports.

- [ ] **Step 1: Write failing report tests**

Test deterministic Vite manifest parsing, rejection of forbidden eager edges from board entry to terminal/chat/diff/settings when they are not required for board paint, path sanitization, and before/after schema validation.

- [ ] **Step 2: Run the failure and capture before data**

```bash
cd frontend
node --test scripts/route-bundle-report.test.mjs
npm run tauri:build
node scripts/route-bundle-report.mjs --label before
node scripts/heap-summary.mjs --label before
```

Expected: the test initially fails; after the report tool exists, reports reveal actual eager imports/retainers without presuming route splitting is absent.

- [ ] **Step 3: Make only measured changes**

Move proven eager imports behind existing lazy route/component boundaries, dispose closed-session terminal resources, and replace Motion only where traces show startup or retained-memory cost and CSS preserves behavior. Do not combine unrelated visual refactors.

- [ ] **Step 4: Re-measure and commit**

```bash
cd frontend
node --test scripts/route-bundle-report.test.mjs
npm run test:e2e:renderer
npm run bench:shell -- --shell tauri --scenario warm-start
npm run bench:shell -- --shell tauri --scenario idle-memory
node scripts/route-bundle-report.mjs --label after
node scripts/heap-summary.mjs --label after
git add scripts/route-bundle-report* scripts/heap-summary.mjs src/renderer ../docs/benchmarks/tauri-port-baseline.md perf/results
git commit -m "perf(renderer): reduce measured startup and retained memory"
```

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

### Task 22: Run final release gates and update canonical documentation

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `docs/development.md`
- Modify: `docs/STATUS.md`
- Modify: `docs/architecture.md`
- Modify: `docs/telemetry.md`
- Modify: `frontend/docs/desktop-release.md`
- Modify: `docs/benchmarks/tauri-port-baseline.md`

**Interfaces:**
- Produces the canonical Tauri development/release instructions and a checked-in final performance/parity report.
- Does not publish; publication remains a separate designated-conductor action.

- [ ] **Step 1: Update docs from verified commands and artifacts**

Document exact Node/Rust/Go requirements, `npm run tauri:dev`, Phase 0 and benchmark commands, state roots, managed-browser first-use behavior, preserved ACP runtime, external preview behavior, platform artifacts, updater channels, and Electron removal. Remove stale Electron/Forge/browser-panel instructions everywhere except historical/deferred context.

- [ ] **Step 2: Run the complete local and native matrix**

```bash
npm run lint
npm run frontend:typecheck
cd frontend
npm run typecheck
npm run typecheck:e2e
npm run test:e2e:renderer
npm run test:e2e:tauri
npm run check:desktop-parity
node --test scripts/no-electron.test.mjs
npm run tauri:build
npm run verify:tauri-artifacts
cd ../backend
go build ./...
go test ./...
go test -race ./...
go vet ./...
cd ../packages/mobile
flutter analyze
flutter test
cd ../..
npx @redwoodjs/agent-ci run --all
```

Expected: every command succeeds on the relevant native runner; signed install/update flows pass; performance results meet every absolute and relative gate.

- [ ] **Step 3: Validate final state and commit**

```bash
rg -n "Electron|electron-forge|app://renderer|Browser panel|VITE_NO_ELECTRON" AGENTS.md README.md docs frontend/docs frontend/src frontend/package.json .github/workflows
git status --short
git add AGENTS.md README.md docs frontend/docs/desktop-release.md frontend/perf/results
git commit -m "docs: complete tauri desktop migration"
```

Expected: remaining Electron/Browser-panel references are explicitly historical or deferred; no credentials, local run state, browser engine, build output, or benchmark-private metadata is staged.

## Final release checklist

- [ ] Phase 0 decision is `continue` or `linux-canvas`, with all native-runner evidence present.
- [ ] macOS webview and application state comply with the Operator state-root rule.
- [ ] Packaged Tauri origins pass CORS and hostile origins fail before handlers execute.
- [ ] Terminal open, throughput, input, reconnect, active-memory, and workload-CPU gates pass; macOS/Windows use WebGL and Linux matches the recorded decision.
- [ ] Warm/first-run startup, idle shell memory, base download, and installed footprint meet all gates.
- [ ] Base size includes daemon, agent-browser, and ACP runtime; managed-browser footprint is reported separately.
- [ ] Every non-browser parity-ledger row is implemented and tested.
- [ ] `opr preview` automatically opens each new revision and supports manual reopen; clear opens nothing.
- [ ] Standalone browser discovery/install/actions/session teardown work without Electron on every platform.
- [ ] Folder scans and telemetry bootstrap remain unreachable through the LAN listener.
- [ ] Flutter analyze/tests and authenticated mobile connection coverage pass; all desktop-only routes return 404 on LAN.
- [ ] App-state marker, install provenance, relocation/handoff, and `opr start` discovery pass.
- [ ] Latest, nightly, feature, downgrade, return-home, and update telemetry flows pass signed E2E.
- [ ] The last Electron release migrates to Tauri through the compatibility feed or the proven bridge release on every platform without losing `~/.operator` state.
- [ ] macOS zip and DMG, Windows NSIS, and Linux AppImage/deb/rpm verify.
- [ ] No renderer import, package, config, workflow, runtime token, or broker remains from Electron.
- [ ] Exactly one designated publisher performs the eventual release.
