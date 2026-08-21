# State-confinement audit fix report

## Status

DONE_WITH_CONCERNS

The transient-state false-negative is fixed in the Node audit and covered by a real child-process regression. The local native audit was attempted after rebuilding the current shared-worktree Tauri executable, but the shutdown phase timed out before the renderer completion marker was written. The Node audit suite, syntax and Biome checks, and relevant Rust tests pass.

## Root cause

The audit took a snapshot before launch and began settled polling only after the child exited. A new Operator-owned path in a configured OS state target could therefore be created and removed entirely between those snapshots. Neither settled snapshot retained evidence that the path had existed.

## Implementation

- Added continuous observation around each shutdown and crash child process.
- Retained a union of observed created or changed paths and merged it into the settled post-exit snapshot before confinement evaluation.
- Kept the existing settled snapshot polling unchanged for delayed native writes after process exit.
- Used recursive filesystem events only for the configured Operator root and already identified Operator/Tauri-owned subtrees.
- Used shallow filesystem events for configured OS app-data/cache roots and retained only Operator/Tauri-owned path events.
- Used exact-file stat watchers for the three macOS cookie candidates so the protected `~/Library/Cookies` parent is neither enumerated nor watched broadly.
- Monitored missing target ancestors without enumerating them and failed closed if a required target appeared without continuous descendant coverage.
- Closed directory and exact-file watchers on success, expected crash, timeout, spawn failure, setup failure, and observation failure.
- Left `.github/workflows/tauri-phase0.yml` unchanged because it already runs the state regression suite and live audit on macOS, Windows, and Linux.

## TDD evidence

Initial RED:

```text
node --test scripts/audit-tauri-state.test.mjs
SyntaxError: The requested module './audit-tauri-state.mjs' does not provide an export named 'auditPhase'
exit 1
```

The new regression launches a real Node child. The child creates `dev.operator.desktop` in a configured shallow OS-state fixture, waits while running, removes it before exit, and writes its completion marker beneath the allowed root.

Mutation RED after implementation removed the observed-path union from confinement evaluation:

```text
node --test --test-name-pattern='transient out-of-root' scripts/audit-tauri-state.test.mjs
not ok 1 - a transient out-of-root Operator write while the child runs fails the audit
error: Missing expected rejection.
exit 1
```

Restoring the observed-path union returned the focused regression and full suite to GREEN.

The first local native audit with directory watching for exact cookie candidates also produced a useful RED:

```text
Error: EPERM: operation not permitted, watch '/Users/omaraly/Library/Cookies'
exit 1
```

Replacing that protected-parent watch with exact-file stat watchers removed the `EPERM` failure without enumerating or traversing the protected directory.

## Final verification

```text
cd frontend
npm run test:tauri-state
node --check scripts/audit-tauri-state.mjs
node --check scripts/audit-tauri-state.test.mjs
npm exec -- biome check scripts/audit-tauri-state.mjs scripts/audit-tauri-state.test.mjs
cargo test --manifest-path src-tauri/Cargo.toml
git diff --check -- scripts/audit-tauri-state.mjs scripts/audit-tauri-state.test.mjs
```

Exit `0`. Node state tests passed `15/15`. Rust tests passed `9/9`. Syntax, Biome, and diff checks were clean.

The regression suite proves:

- a transient out-of-root Operator-owned path fails confinement;
- an allowed-root transient path remains accepted;
- directory and exact-file watchers close on success, crash, timeout, and spawn failure;
- audit setup fails closed when a required directory watcher cannot be established;
- delayed post-exit state remains covered by settled polling;
- exact macOS cookie candidates remain auditable without protected-parent enumeration.

## Local native audit concern

The live audit was run twice after the cookie watcher correction, including once after `cargo build --manifest-path src-tauri/Cargo.toml`. Both runs passed observer setup but timed out in the shutdown phase after 30 seconds:

```text
Error: shutdown phase timed out
```

The isolated root contained reparented WebKit/cache state but no `renderer-shutdown-complete` marker. Running the debug executable directly in shutdown audit mode also remained open until interrupted. Relevant Rust tests pass, and the native renderer/audit command implementation is outside this fix track's owned files, so no Rust change was made. This local native-runtime failure must be resolved or shown to be environment-specific before Phase 0 state evidence can be accepted.

No native Windows, Linux, or minimum-version macOS execution was performed locally. The existing workflow remains the source of those platform runs, not evidence that they passed.

## Scope

Only these paths are included in the fix commit:

```text
frontend/scripts/audit-tauri-state.mjs
frontend/scripts/audit-tauri-state.test.mjs
.superpowers/sdd/2026-08-20-tauri-port/fix-state-audit-report.md
```

No generated `frontend/src-tauri/gen` or `frontend/src-tauri/target` path is staged or committed.
