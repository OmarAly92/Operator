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
