# Tauri updater stability — design

**Date:** 2026-08-26
**Status:** proposed design
**Program:** `docs/superpowers/specs/2026-08-26-tauri-stabilization-program-design.md`
**Owns:** updater plugin registration, restart/install behavior, and staged-download recovery.

## Outcome

Operator can check a signed feed without panicking, download and remember a verified update, restart into that update, prove the new application is healthy, and roll back an interrupted or unhealthy apply. Updater-owned downloads, transactions, backups, and recovery markers stay beneath the configured Operator state root.

The existing renderer commands and update status model remain compatible. A user who clicks “Restart & install” receives a deterministic result or an actionable error; the UI never discards an install failure.

## Scope

This design covers:

- registration and configuration of `tauri-plugin-updater` for real packaged feed checks;
- durable staged-update discovery and validation after restart;
- a project-owned apply helper and transaction protocol;
- platform-specific apply, restart, health confirmation, and rollback;
- renderer install progress and recovery UX;
- packaged, signed integration tests on macOS, Windows, and Linux.

Replacing whole-artifact in-memory downloads with bounded streaming remains outside this bug program. The implementation must preserve a clean boundary so the later transport hardening can replace the downloader without changing the transaction or UI contracts.

## Decisions

| Concern | Decision |
|---|---|
| Feed client | Register the pinned Tauri updater plugin and use it only through the existing Rust feed abstraction. |
| Apply path | Do not call the plugin's default install path. Use an Operator-owned helper because plugin installation uses OS temp/cache locations and cannot satisfy the state-root invariant. |
| Durable owner | Rust owns download/apply transactions; daemon settings still own channel and user preferences. |
| Staging root | `<operator-state-root>/updater`, derived once from the same resolved state root used by the shell. |
| Restart helper | Bundle a small signed `operator-updater` helper built from this repository. It accepts only a validated transaction identifier and state-root path. |
| Health proof | The new desktop process confirms shell initialization, daemon readiness, and version match before the transaction commits. |
| Recovery | Startup inspects durable transactions before normal update polling and either resumes, confirms, rolls back, or quarantines them. |
| Concurrency | Exactly one download/apply transaction may be active. Read-only status requests may run concurrently. |

## Architecture

```text
React update UI
      │ Tauri commands/events
      ▼
Rust UpdateEngine
  feed check through registered plugin
  signature and metadata validation
  durable transaction state
      │ one-shot apply request
      ▼
Bundled operator-updater helper
  wait for desktop exit
  verify request and staged bytes again
  platform apply + restart
  rollback on apply/startup failure
      │
      ▼
New Operator process
  recover transaction
  verify running version
  wait for daemon readiness
  write health acknowledgement
```

The helper is not a general process launcher, archive extractor, or privileged command bridge. Its accepted operation is fixed at compile time and constrained to a transaction already created beneath the updater root.

## Feed-check safety

The normal Tauri builder registers `tauri_plugin_updater::Builder` before any updater command can resolve `UpdaterExt`. Development, production, and explicit E2E configurations use the same registration path. Feed endpoints, platform target, current version, timeout, and compiled public key are configured through reviewed application configuration rather than renderer input.

The feed abstraction converts plugin failures and panics-at-boundary into stable updater errors. The process-wide panic hook must never be the normal response to an unavailable updater state. A real-app integration test constructs the production builder, resolves the plugin-managed state, and checks a local signed manifest.

Development builds without configured endpoints return a typed `updater_unavailable` status. They do not attempt production network access and do not crash.

## Durable layout

```text
<state-root>/updater/
  lock
  transactions/
    <transaction-id>/
      transaction.json
      artifact.part
      artifact.bin
      payload/
      backup/
      helper-request.json
      helper-result.json
      health.json
  quarantine/
  logs/
```

All paths are constructed from a validated opaque transaction ID. The engine rejects traversal, absolute paths, symlinked transaction roots, hard-linked payloads where detectable, unsupported file types, and any resolved path outside the updater root.

`transaction.json` is written atomically and contains:

- schema version and transaction ID;
- source channel and feed URL origin;
- current and target semantic versions;
- platform, architecture, and package kind;
- artifact URL, declared size, actual size, and SHA-256;
- updater signature and public-key identifier;
- application identity and expected installed target;
- source release identifier;
- state and state-transition timestamp;
- retry count and last stable error code;
- previous installation version and backup description;
- health deadline.

Private signing keys, access tokens, arbitrary environment variables, and user-supplied shell commands are never stored.

## Transaction state machine

```text
available
   │ download
   ▼
downloading ──failure──> failed
   │ verified artifact
   ▼
staged
   │ user confirms restart
   ▼
prepared
   │ helper owns apply
   ▼
applying ──apply failure──> rollback_pending
   │ new app launched
   ▼
awaiting_health ──timeout/version failure──> rollback_pending
   │ health acknowledgement
   ▼
committed

rollback_pending ──successful restore──> rolled_back
rollback_pending ──restore failure─────> recovery_required
```

Every transition is persisted before its external side effect. Repeating a transition after a crash is idempotent. Illegal backward transitions fail closed and preserve evidence for recovery.

Only `staged`, `prepared`, `applying`, `awaiting_health`, `rollback_pending`, and `recovery_required` survive as active startup work. Committed, rolled-back, failed, and quarantined transactions are retained for a bounded diagnostic period and then pruned.

## Download and staged-state rehydration

The existing downloader writes `artifact.part`, verifies declared size and cryptographic signature, fsyncs it, and atomically renames it to `artifact.bin` before marking the transaction `staged`.

On every desktop start, before update polling:

1. acquire the updater lock;
2. enumerate transaction directories without following links;
3. parse supported schema versions with bounded file sizes;
4. validate application identity, platform, architecture, channel, target version, artifact size, digest, and updater signature using the compiled public key;
5. confirm that recorded paths remain beneath the updater root;
6. choose the single newest valid active transaction;
7. quarantine invalid or conflicting transactions with a stable reason;
8. restore the valid staged update into engine state and emit its status.

A valid staged transaction prevents a duplicate download. A different update version supersedes an older staged transaction only through an explicit transition that first retires the old transaction. A downgrade is allowed only when the existing channel/pin policy authorizes it and the user explicitly confirms the version change.

## Apply authorization

The renderer supplies no filesystem path, executable, installer arguments, target version, or command line. It requests installation of the engine's current staged transaction.

The engine revalidates the artifact and transaction, confirms there is no active terminal/session shutdown conflict under the existing application policy, writes `helper-request.json`, and starts the bundled helper with:

- the canonical state-root path;
- the opaque transaction ID;
- the parent desktop PID;
- a random one-time nonce whose digest is in the transaction.

The helper validates its own executable location and application identity, opens the transaction without following links, checks the nonce, re-verifies metadata, digest, updater signature, target identity, and source version, then waits for the parent process to exit. It rejects extra arguments and ignores inherited environment paths for target selection.

## Platform apply drivers

### macOS

The macOS artifact contains the signed and notarized `Operator.app`. Preparation expands it beneath the transaction payload directory using trusted Rust/library logic or a fixed system tool invocation with no shell interpolation. The helper verifies bundle identifier, version, architecture, code signature, designated requirement, notarization assessment, and updater signature.

The helper creates a backup within the transaction, atomically exchanges or renames the installed bundle on the same volume, and launches the new bundle. If a direct atomic exchange is unavailable, it uses a journaled sequence whose every rename is recoverable. It never stages in `/tmp`.

On failed launch or health timeout, it restores the previous bundle, verifies it, and relaunches it. The existing first-install DMG and permanent Electron compatibility zip remain separate release artifacts.

### Windows

The Windows artifact is an Authenticode-signed NSIS update package. The helper verifies updater signature, PE signature chain, subject/publisher identity, timestamp, product identity, version, and architecture before execution.

The transaction caches the previously installed signed package or a verified rollback payload beneath `backup`. The helper invokes the trusted installer through a fixed argument vector for per-user installation and waits for its result. It rejects elevation or target-directory overrides supplied by artifact metadata.

After install it launches the expected Operator executable from the validated installation location. On failure or health timeout it invokes the verified previous package through the fixed rollback path. A rollback that requires user elevation surfaces `recovery_required` with an exact recovery action and preserves the previous signed package.

### Linux

The driver is selected from the recorded installation kind, never merely from which file exists.

- **AppImage:** verify updater signature and executable identity, preserve the prior AppImage under `backup`, atomically replace on the same filesystem, restore on failure, and relaunch.
- **deb:** verify updater signature, Debian package metadata, package name, version, architecture, and configured package-signing trust. Apply through a fixed package-manager invocation with normal desktop authorization. Cache the prior signed package for rollback.
- **rpm:** verify updater signature, RPM metadata, package name, version, architecture, and repository/package signature. Apply through a fixed package-manager invocation with normal desktop authorization. Cache the prior signed package for rollback.

For deb/rpm, denial of authorization leaves the transaction staged and the current app installed. A package-manager failure enters rollback recovery without deleting the cached previous package. Arbitrary maintainer-script behavior is not accepted from unsigned/untrusted packages; release verification must establish package trust before the feed can reference them.

## New-process health contract

The helper launches the new desktop with a transaction ID and nonce reference, not with secrets. The new process:

1. validates the transaction and confirms its running application version equals the target;
2. completes Tauri shell initialization and creates the main window;
3. starts or attaches to the authoritative daemon;
4. waits for daemon readiness and a successful version-compatible API call;
5. atomically writes `health.json` and notifies the helper.

The health deadline is bounded and platform-aware. Renderer route load alone is insufficient; daemon readiness alone is insufficient. The helper commits only after both shell and daemon checks pass.

If the new process crashes, reports the wrong version, cannot reach a healthy daemon before the deadline, or writes an invalid acknowledgement, the helper rolls back. After rollback, the old version reports a non-dismissed recovery notification with the failed target version and stable reason.

## Startup recovery

Startup recovery runs before background update checks:

- `downloading` with a valid partial file returns to resumable/failed download handling already supported by storage;
- `staged` rehydrates the install button without redownload;
- `prepared` before parent exit returns to staged when the helper never acquired ownership;
- `applying` with no helper result invokes platform inspection and chooses resume or rollback;
- `awaiting_health` lets the running target acknowledge or rolls back at deadline;
- `rollback_pending` resumes rollback;
- `recovery_required` blocks further updates and presents exact manual recovery instructions.

The engine never silently deletes the only previous-version recovery payload. Cleanup occurs after a committed health result and a bounded grace period.

## Renderer behavior

The existing update surfaces display the same engine state. “Restart & install” is enabled only for a valid `staged` transaction and while no apply is active.

Click handling awaits the command and maps stable errors to UI:

- confirmation or authorization declined: remain staged;
- validation failed: quarantine and offer redownload;
- application busy: preserve staged update and offer retry;
- apply or rollback failure: show persistent recovery state;
- helper started: show restarting state and stop accepting duplicate clicks.

The sidebar and settings surfaces use one shared action/controller so they cannot diverge. Rejected promises are always handled. Status survives renderer remount because Rust owns the transaction.

## Error model

At minimum, stable codes distinguish:

- `updater_unavailable`;
- `feed_invalid`;
- `signature_invalid`;
- `artifact_mismatch`;
- `staged_state_invalid`;
- `update_in_progress`;
- `apply_not_authorized`;
- `apply_failed`;
- `health_timeout`;
- `rollback_failed`;
- `recovery_required`.

Messages identify the safe next action without exposing full feed URLs, local usernames, tokens, or private filesystem details.

## Tests

### Rust unit and contract tests

- production Tauri builder has updater plugin state;
- legal and illegal state transitions;
- atomic metadata writes and recovery after each transition;
- staged rehydration, duplicate prevention, conflict selection, quarantine, and pruning;
- path traversal, link escape, mismatched identity/version/architecture/channel, size/digest/signature failure;
- one active transaction under concurrent requests;
- helper request/response authentication and idempotency;
- UI command errors preserve stable codes.

### Renderer tests

- both install buttons await and render success/failure;
- repeated clicks cannot spawn multiple helpers;
- remount reads durable status;
- declined authorization stays staged;
- recovery-required state remains visible and actionable.

### Packaged platform tests

Each OS runs a local HTTPS or loopback fixture serving a real manifest signed by a test updater key compiled into the test app. The test performs:

1. check without panic;
2. download and signature verification;
3. process restart before install and staged rehydration without redownload;
4. upgrade install and health commit;
5. authorized downgrade and health commit;
6. interruption at each persisted apply phase;
7. new-version startup failure and automatic rollback;
8. corrupt staged artifact rejection;
9. wrong updater key rejection;
10. state-root audit proving no updater write outside the configured root.

Windows additionally proves Authenticode before install. macOS proves code signing and notarization policy. Linux covers AppImage and native package formats used by the release channel on their native runners.

## Expected file surface

Implementation is expected to touch:

- `frontend/src-tauri/src/lib.rs` and `frontend/src-tauri/src/updater/`;
- a new tightly scoped updater-helper Rust binary/crate under `frontend/src-tauri/`;
- Tauri bundle resources and capabilities needed only for the helper protocol;
- renderer update action/state components and their tests;
- updater artifact preparation and packaged E2E fixtures;
- release packaging only where required to bundle and sign the helper.

No updater logic moves into the Go daemon, and no renderer filesystem or process capability is added.

## Acceptance criteria

1. A packaged production builder performs a signed manifest check without panic.
2. Restarting after download restores the verified staged update and performs no duplicate download.
3. “Restart & install” completes a signed upgrade on macOS, Windows, and Linux and reports every failure.
4. A bad target launch or missed health deadline restores the previous working version where automatic rollback is supported, otherwise enters a preserved and actionable recovery state.
5. Upgrade, authorized downgrade, interruption, recovery, and rollback tests pass for the supported package kinds.
6. The helper cannot apply an arbitrary path, command, unsigned artifact, wrong product, wrong architecture, or transaction outside the updater root.
7. State-audit tests observe no updater-owned write outside the configured Operator state root.
8. Normal development without a feed remains non-fatal.
9. Existing update preference, channel, telemetry, and status behavior remains compatible.

## Out of scope

Bounded streaming, download cancellation, disk-space reservation, and wider updater transport hardening remain separate work. This design must not claim final release approval; the trusted atomic release design owns publication gates.
