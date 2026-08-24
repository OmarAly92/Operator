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

