# Tauri native CI, state confinement, and parity evidence — design

**Date:** 2026-08-26
**Status:** proposed design
**Program:** `docs/superpowers/specs/2026-08-26-tauri-stabilization-program-design.md`
**Owns:** WebDriver resource preparation, browser socket-alias confinement, parity-ledger validation, and retirement of the invalid Phase 0 workflow.

## Outcome

Three-platform native CI reaches the tests it claims to run, standalone browser runtime paths obey the Operator state-root contract, and the parity ledger can no longer label absent behavior as covered by supplying an arbitrary string. Obsolete Phase 0 jobs are either moved to valid owners or removed; no invalid workflow remains in `.github/workflows`.

This design repairs evidence infrastructure. It does not convert ordinary native CI into the final signed cross-platform acceptance run; that later release evidence remains a separate binding gate.

## Part 1: native WebDriver CI

### Required resource graph

Every normal-shell or E2E-shell Tauri build uses the same preflight resource contract:

1. install locked frontend dependencies;
2. build the Go daemon resource;
3. prepare the pinned standalone `agent-browser` resource;
4. build the ACP runtime resource;
5. validate that every path declared in `tauri.conf.json` exists with the expected type and platform name;
6. build the selected Tauri feature set.

The WebDriver workflow currently omits step 3. The repair uses the canonical `npm run browser-runtime:prepare` script rather than reproducing its implementation in YAML.

### Shared resource validator

Add a script that reads the effective Tauri configuration and validates declared resources before Cargo/Tauri compilation. It reports all missing resources in one failure with stable relative names. It rejects symlink escapes outside the checkout for build inputs and does not inspect user home state.

Local `tauri:dev`, `tauri:build`, native CI, and release workflows call the same preparation/validation commands. The validation command is read-only after preparation and has unit fixtures for macOS, Windows, Linux, missing resources, wrong file type, and path escape.

### Workflow behavior

For each of macOS, Windows, and Linux, `tauri-webdriver.yml` must:

- use explicit read-only permissions;
- use locked toolchains and `npm ci`;
- prepare all three packaged resources before both the normal and E2E builds;
- prove the WebDriver plugin is absent from the normal binary and present only in the explicit E2E binary;
- typecheck the E2E suite;
- start the embedded driver and run the native suite;
- use a fresh `OPERATOR_DATA_DIR` and `OPERATOR_RUN_FILE` beneath the runner's test workspace;
- upload logs, screenshots, daemon output, state-audit summary, and build-contract diagnostics on failure;
- fail when expected failure artifacts cannot be collected due to an earlier harness bug.

The workflow reaches the E2E runner on all three platforms in a required branch-protection run. A successful Tauri compile alone is not a successful native job.

### Native CI evidence record

Each job writes a small JSON summary containing source commit, runner image, OS/architecture, normal binary digest, E2E binary digest, resource manifest digest, executed suite IDs, result, and artifact name. It contains no environment values or full user paths.

These records can be referenced by the parity evidence catalog, but they are not final signed-release evidence because E2E builds contain an explicit test-only driver.

## Part 2: browser runtime socket confinement

### Current purpose of aliases

Unix-domain socket address limits can be shorter than a session's full state-root path. The current adapter creates a short alias under `/tmp`, which keeps sockets short but violates the repository rule that all application state stays beneath the Operator root.

The fix preserves short aliases without creating a global exception.

### Layout

The resolved browser runtime receives one explicit `StateRoot`. It derives:

```text
<state-root>/browser-runtime/
  runs/<daemon-run>/<session>/...
  aliases/<short-run-id>/<short-session-id> -> validated owned run directory
  alias-owners/<alias-id>.json
```

The `aliases` component name may be shortened if needed, but it remains under the resolved state root. Alias identifiers are fixed-length lowercase encoded values derived from random ownership IDs, not user/project/session names. The symlink target also remains under the state root.

The adapter does not default to `/tmp`, `os.TempDir`, the process working directory, or an OS app-data location. Tests and callers must pass the same state root used by daemon configuration. `OPERATOR_DATA_DIR` remains the supported way to select a shorter root.

### Socket path budget

At startup the adapter computes the maximum encoded socket path using the platform's effective Unix-socket limit with a safety margin. It validates the alias root before starting a managed browser.

If the configured Operator root itself is too long to permit a safe alias, startup returns `browser_runtime_socket_path_too_long` with the measured required maximum and an instruction to choose a shorter `OPERATOR_DATA_DIR`. It does not fall back outside the root.

Non-Unix transports skip alias creation and still keep runtime ownership files beneath the state root.

### Ownership and cleanup

Creating an alias requires:

- an exclusive ownership record written atomically;
- a source runtime directory owned by the current daemon run;
- canonical containment of the target beneath `browser-runtime/runs`;
- absence of a conflicting alias or a stale alias proven safe to reclaim.

Cleanup validates the ownership record and both canonical paths before unlinking. It removes only the alias and owned empty parent. It never recursively removes a resolved symlink target through the alias path.

The startup scavenger examines only the configured alias root, bounds its work, validates schema and daemon ownership, retains live aliases, and removes stale aliases whose owners are proven dead by the existing conservative lifecycle rules. Unknown or malformed entries are quarantined or reported rather than followed.

Crash recovery and concurrent session tests prove that aliases do not collide, leak between sessions, or survive past safe cleanup.

### State audit

The Tauri state audit creates an isolated Operator root and snapshots relevant filesystem locations before and after browser preparation, browser launch, command execution, and shutdown. It asserts:

- every new browser engine/runtime/profile/socket/alias/ownership path is under the isolated root;
- no `opr-br-*` or replacement alias appears under system temp directories;
- teardown removes session aliases and leaves only allowed shared engine cache;
- forced process termination is cleaned by the next bounded scavenger;
- an intentionally long state root fails with the stable typed error and writes no fallback alias.

The audit uses platform-specific observation roots without recording unrelated filesystem contents in artifacts.

## Part 3: enforceable parity ledger

### Ledger schema

Every live bridge row has:

```json
{
  "source": "bridge.namespace",
  "member": "method",
  "disposition": "human-readable intended behavior",
  "owner": "tauri | go | renderer",
  "task": 1,
  "status": "covered",
  "evidence": ["stable-evidence-id"],
  "exception": null
}
```

Allowed status values are:

- `covered` for implemented behavior with resolvable evidence;
- `deferred` only for the exact Browser-panel entries and exact checked-in exception record.

No arbitrary status string, `planned`, `partial`, or `external:<text>` is accepted. A missing live feature cannot pass the checker. During implementation its row makes the parity gate fail until valid evidence lands.

Archived Electron inventory rows retain a distinct schema identifying their historical disposition; they cannot masquerade as live coverage. The checker continues rejecting stale, missing, duplicate, or reintroduced Electron inventory.

### Evidence catalog

Create `frontend/perf/parity-evidence.json` as a normalized registry. Each stable ID declares:

- evidence kind: `unit`, `contract`, `renderer-e2e`, `native-e2e`, or `trusted-external`;
- owning suite identifier from an allowlisted suite registry;
- checked-in test/contract path and exact test selector where applicable;
- covered platforms;
- whether a normal production build or explicit test build is exercised;
- for trusted external records, the checked-in record path, schema, source commit, artifact digests, and trusted producer identity.

The ledger references IDs only. The checker verifies that every ID exists, paths remain within the repository, referenced files exist, test selectors are present, platform names are valid, and trusted-external records match their schema. It rejects evidence paths under ignored output or local temporary directories.

CI maps suite identifiers to reviewed commands. It does not execute arbitrary command strings from the JSON catalog.

### Minimum evidence policy

Risk-sensitive surfaces have minimum evidence classes enforced by the checker:

| Surface | Minimum evidence |
|---|---|
| Pure renderer mapping | Unit or contract plus normal renderer suite |
| Daemon REST/SSE behavior | Go contract/integration test |
| Native command without user activation | Rust contract plus renderer bridge test |
| Native shortcut/menu/tray integration | Native E2E on supported platforms plus unit policy tests |
| Notification click | Packaged or production-capability native activation E2E on macOS and Windows |
| Update check | Real production-builder plugin integration with signed test manifest |
| Update install | Signed install/restart/rollback evidence on every supported platform/package kind claimed |
| State confinement | State-audit evidence on every supported platform |

Evidence can exceed the minimum. A unit test that only invokes an abstraction cannot satisfy an operating-system activation or install claim.

### Correcting existing false claims

`bridge.notifications/onClick` and `bridge.updates/install` remain failing/uncovered until the renderer/native and updater designs provide their required evidence. Their current free-form external claims are removed. When the implementations land, the rows reference the new real evidence IDs.

The checker has fixtures proving that nonempty nonsense status, missing evidence, nonexistent paths, mismatched test selectors, insufficient evidence class, local output paths, and a deferred non-Browser row all fail.

## Part 4: retire the invalid Phase 0 workflow

`.github/workflows/tauri-phase0.yml` is deleted after its still-valid jobs have named owners. An invalid workflow with jobs but no trigger is not an accepted retirement mechanism.

The migration mapping is:

| Retired job | New owner |
|---|---|
| updater-signing fixture | Updater/release verification test suite and trusted release workflow |
| state-boundary | State-audit job in native Tauri CI |
| agent-browser-probe | Browser adapter integration/state-confinement suite |
| terminal benchmark | Benchmark workflow/documented manual evidence producer; it remains non-binding until authorized evidence exists |
| packaging feasibility | Platform release build verification |
| legacy Electron migration fixtures | Dedicated compatibility job in the trusted stable-release workflow until the binding port design formally retires legacy migration support |

Before deletion, implementation identifies every job and records its destination. Tests/scripts that still have a caller are retained. Dead scripts are not deleted as drive-by cleanup; they are listed for a later focused cleanup if no current workflow owns them.

The docs index points to current workflows and does not tell agents to run the retired file.

## Failure behavior

- Missing build resources fail before Cargo compilation with a complete resource report.
- A native job that never starts WebDriver fails; it cannot report success from build-contract steps alone.
- An overlong state root fails browser startup safely without a `/tmp` fallback.
- Invalid alias ownership prevents cleanup and emits a diagnostic; it does not delete uncertain paths.
- Missing or insufficient parity evidence fails the parity gate.
- A removed Phase 0 check without a recorded new owner fails a migration-map test or documentation review.

## Expected file surface

Implementation is expected to touch:

- `.github/workflows/tauri-webdriver.yml` and the workflows receiving retained Phase 0 checks;
- deletion of `.github/workflows/tauri-phase0.yml` after migration;
- `frontend/package.json` and resource validation scripts/tests;
- `backend/internal/adapters/agentbrowser/` runtime, configuration, and cleanup tests;
- `frontend/scripts/audit-tauri-state.mjs` and tests;
- `frontend/scripts/check-parity-ledger.mjs`, its tests, the ledger, and the new evidence catalog;
- documentation indexes that reference native or Phase 0 gates.

Application APIs and renderer UX do not change in this design.

## Acceptance criteria

1. macOS, Windows, and Linux WebDriver jobs prepare the browser runtime and reach/pass the native E2E suite.
2. Normal binaries exclude the E2E driver and explicit E2E binaries include it.
3. No browser runtime alias or ownership marker is created outside the configured Operator state root.
4. Overlong state roots fail with a stable actionable error and no fallback state.
5. Crash, concurrency, containment, and cleanup tests pass for browser aliases.
6. Parity status uses a closed vocabulary and every covered live row has resolvable sufficient evidence.
7. Notification click and update install cannot be certified by abstract/free-form evidence.
8. The invalid Phase 0 workflow is removed and each retained check has a valid current owner.
9. Workflow lint, native CI, state audit, parity checker/tests, backend tests, and `git diff --check` pass.

## Out of scope

This design does not produce final signed packaged acceptance, binding performance measurements, or broader benchmark-tool cleanup. It makes the infrastructure truthful and runnable so those later evidence runs can be trusted.
