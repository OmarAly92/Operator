# Task 17 Report: Rebuild update state, feature channels, and updater events

Status: DONE_WITH_CONCERNS (all gates green; the concerns below are recorded stops and
deferrals that need controller awareness, not defects)

Base: e5e2969e (clean tree, Task 16 commit). All work strictly UNCOMMITTED per the
override of the brief's Step 4 git block — nothing staged, added, or committed.
`frontend/src-tauri/gen/` untouched; `target/` only written by gate runs.

## What was implemented

### `updater/status.rs` (new)

Renderer-wire types ported from `shared/update-settings.ts` / `shared/update-telemetry.ts`:
`UpdateState` (kebab-case serialization, incl. `"not-available"`), `UpdateStatus`
(camelCase fields `requestId`/`stagedAt`, all optional fields omitted when None — pinned
byte-shape by test), `UpdatePhase`, `UpdateTrigger`, `UpdateFailureCategory`
(snake_case), `UpdateOutcome`, and the three telemetry event names. Ported
`update_failure_category` substring bucketing (network/signature/permission/disk_space/
not_found/not_supported/unknown) plus outcome builders for failed/downloaded/unsupported.

### `updater/escalation.rs` (new)

Pure port of `main/escalation-evaluator.ts`: latest escalates at >=48h staged; nightly
escalates on the feed's important flag OR when the running version semver-lt the latest
stable (pre-release ordering makes `0.10.4-nightly.x < 0.10.4`; unparseable versions
never escalate). Also defines `EscalationFeeds`, the trait seam for the two read-only
release-feed probes (latest-stable version, nightly important flag).

### `updater/channel.rs` (new)

Channel domain ported from `update-settings.ts` + `feature-builds.ts`: `Channel`,
`ActiveChannel` (Latest | Nightly | Feature(pr)), `FeaturePin`, `UpdateSettings` with
daemon-matching coercion (`coerce_settings`: unknown channel -> latest, pin kept only
for positive integers), `active_channel()` resolution. Feed URL selection
(`select_feed_url`): latest.json / nightly.json / pr<N>.json under a base URL; HTTPS is
mandatory for packaged shells — loopback HTTP is allowed ONLY unpackaged (dev), any
other http or unparseable base is rejected. `validate_public_key` accepts exactly a
minisign public-key packet (comment line + base64 line decoding to a 42-byte packet
whose algorithm bytes are "Ed"); secret-key-shaped material is specifically rejected as
`PrivateKeyMaterial`, everything else malformed. Feature-build machinery:
`parse_feature_build` (regex-equivalent scan for `-pr<N>.<12 digits>` with optional
leading v), GitHub release deserialization, marker parsing
(`<!-- opr-feature-build: {...} -->` with JSON-number pr + string base required),
`collect_feature_builds` (prerelease + marker + published within 7 days + PR open,
grouped to newest build per PR, sorted newest-first; errors only when the releases list
fetch fails; per-PR open-state probe errors KEEP the build, matching Electron's
resilience), `list_feature_builds` (degrades to []), `reconcile_feature_pin` (clears a
retired pin preserving home channel; fetch failure keeps the pin). `ReleasesSource` is
the injected transport trait.

### `updater/storage.rs` (new)

`UpdaterStorage` owns every updater byte beneath `<state-root>/updater`
(`UPDATER_STATE_DIR_NAME = "updater"`; subdirs `staged/` + `tmp/`, both created by
`open`, root canonicalized once). Download protocol: `begin_download` writes an intent
record (`partial.json`: version, url, started-at) BEFORE artifact bytes exist;
`complete_download` writes `update.bin` then `meta.json` via temp-file-plus-rename
inside the same version dir and clears the intent — an interrupted download is exactly
"intent present without completion", discoverable via `pending_downloads()`;
`prune_partials` drops stale intents past the 7-day window; `remove_staged` deletes one
version directory. Version names are validated against `[A-Za-z0-9._+-]+` without a
leading dot (traversal like `../x` and dotfiles refused before any path is built).
`ensure_inside` canonicalizes candidate paths and refuses anything that does not resolve
inside the canonical updater root — symlink escapes included.

### `updater/mod.rs` (new) — engine, seams, production glue, commands

`UpdaterEngine<C: FeedClient>` is the serialized state machine. One fair tokio
operation lock serializes automatic-check / manual-check / manual-download /
settings-write / return-home, mirroring Electron's `updaterOperationQueue`. EngineState
carries lastStatus, independentRevision, active operation + request id, phase,
pendingVersion, the automatic-check snapshot (status + revision captured when the
checking status broadcasts during an automatic check), staged-update record (version,
stagedAt, escalated, owning request id), scheduler flags. Behaviors ported:

- start(): read settings through the SettingsSource seam; reconcile pin;
  disabled -> stop scheduling and report false; enabled -> auto-download check.
  Settings-read failures log ("auto-update check failed") without touching the UI and
  the hourly tick retries later (shouldSchedule stays true).
- Status stream: checking broadcast captures the suppression snapshot during automatic
  checks; available stores pendingVersion and rebroadcasts the enriched downloaded
  status when the feed reports the already-staged version; not-available follows up
  with the staged row so the restart row survives channel switches; download progress
  clamps to 0..=100; every owned broadcast attaches the active request id and,
  for automatic checks, never advances the independent baseline.
- Failure handling splits Electron's two paths exactly: event-style failures emit
  failure TELEMETRY first (phase/trigger/pendingVersion retained even when the UI is
  suppressed) and, for automatic checks, restore the prior status only if the
  independent revision is unchanged since the snapshot; promise-rejection style errors
  broadcast error statuses WITHOUT telemetry. Manifest-404 detection (404 + `.yml`
  boundary) produces the two verbatim friendly messages ("Couldn't check for updates —"
  / "Download failed —") with staged restores preferred over error rows.
- Staging: verified bytes land in storage; stagedAt/escalated=false recorded; the
  completed automatic download advances the independent baseline (snapshot cleared);
  escalation evaluates immediately after download.
- Escalation tick: no-op without a staged build; skips while downloading; probes feeds
  only on the nightly channel; rebroadcasts the enriched downloaded status.
- Retirement tick (30 min cadence): coalesces behind an in-flight poll, runs as a
  settings-write op, clears a retired pin ONLY against a fresh re-read that still holds
  the same pin (compare-and-set ports both Electron concurrency tests).
- returnHome: single serialized op; reads persisted truth, clears the pin THROUGH THE
  SETTINGS WRITE BEFORE resolving the home-channel feed, then checks; no-op write when
  nothing pinned; unpackaged shells get unsupported without touching settings.
- apply_settings (renderer push after a successful Go PATCH): arms/disarms the hourly
  scheduler without local writes.
- install_update(): RECORDED STOP — always returns APPLY_DEFERRED_MESSAGE (see
  Boundary decision below).
- Timers: spawn_updater_timers arms hourly / 30-min / 30-min loops with
  MissedTickBehavior::Skip; in-flight coalescing lives inside the engine ticks.

Production glue (same file): `PluginFeedClient` wraps the PINNED
`tauri-plugin-updater = "=2.10.1"` (already exact-pinned in Cargo.toml; npm API NOT
consumed anywhere, so no npm dep was added). Its `check()` builds an Updater from the
endpoint + compiled-in key (`UpdaterBuilder::endpoints().pubkey().build()`) and its
`download()` streams through the plugin's minisign verification into memory. Both are
disk-write-free by construction (plugin source cited below); the plugin is never asked
to install in this task. `DaemonSettingsSource` reads/writes the daemon's
`/api/v1/settings` (+ PATCH `/api/v1/settings/updates`) over loopback HTTP using the
supervisor's probe pattern (5s timeouts, full-record replace semantics — a pin is
cleared by omitting `feature`, matching Go's coerce+replace store). `StoppedReleasesSource`
and `StoppedEscalationFeeds` are recorded stops (see Concerns). `WindowStatusSink`
emits ONLY via `app.emit_to("main", "updates:status" | "updates:telemetry", payload)`.
`open_shell_engine` wires everything beneath `<state-root>/updater` with
`EngineConfig { packaged, app_version, feed_base_url: env OPERATOR_UPDATER_FEED_URL,
public_key: COMPILED_UPDATER_PUBLIC_KEY }`; `COMPILED_UPDATER_PUBLIC_KEY` comes from
`option_env!("OPERATOR_UPDATER_PUBLIC_KEY")` at compile time (never a runtime key file)
and an empty key fails closed at check time.

### Shell wiring (`lib.rs`, `build.rs`, capabilities)

- Eight commands registered ONLY in the normal-mode invoke_handler (audit and
  terminal-benchmark branches unchanged): updates_status, updates_check,
  updates_return_home, updates_download, updates_install, feature_builds_list,
  feature_builds_active, updates_apply_settings.
- build.rs lists all eight so tauri-build generated one allow/deny TOML pair each under
  permissions/autogenerated/ (8 new tracked files); capabilities/default.json grants
  exactly one allow-* per command, still scoped to window "main"; phase0 surfaces rely
  on handler absence to fail closed (Task C ruling precedent).
- `updater_temp_dir(state_root)` extends state_environment: TMPDIR on macOS/Linux,
  TMP+TEMP on Windows now resolve to `<state-root>/updater/tmp`. Stamping still runs
  AFTER the process_env snapshot / original_home capture (Tasks 7/12 ordering) and the
  pre-stamped snapshot still feeds DaemonManager, so the spawned daemon never inherits
  the repointed temp dir. The pinned `state_root_reparents_platform_state` test was
  updated for the new entries and additionally asserts the updater temp path lives
  beneath `<state-root>/updater`.

### Renderer bridge + ledger

- tauri-bridge.ts keeps the shared OperatorBridge contract unchanged; updateSettings.get/set
  now fire-and-forget `updates_apply_settings {settings}` after reading from or
  PATCHing Go (keybindings_apply dual-write pattern), so enabling/disabling auto-updates
  arms or disarms the shell scheduler immediately without a relaunch.
- updates.* methods already invoked the new command names; arg shapes verified against
  Tauri camelCase mapping ({requestId} -> request_id).
- perf/parity-ledger.json required NO edit: every Task-17 row (auto-updater.ts,
  escalation-evaluator.ts, feature-builds.ts, preload.updates.*, preload.featureBuilds.*)
  already exists as owner=tauri/task=17 and `check:desktop-parity` passes at 101 entries
  (Task 14 precedent).

## RED evidence (Steps 1-2, captured before implementation)

All six module files were written first as typed stubs whose bodies were `todo!("...")`;
the crate compiled and every behavior test failed at runtime:

```
cargo test --locked updater
test result: FAILED. 1 passed; 47 failed; 0 ignored; 0 measured; 157 filtered out

verbatim failures included:
thread '...unpackaged_shell_reports_unsupported...' panicked at src/updater/storage.rs:81:9:
  not yet implemented: UpdaterStorage::open
thread '...channel_selects_latest_and_nightly_feed_urls' panicked ... todo!()
```

The single passing test at RED was `status_serializes_the_renderer_wire_shape`, which
exercises only serde derives (declarative wire types, no logic); disclosed per the
Task 14 counting convention. The 47-test failure list was captured verbatim during the
run (active_feature_reporting, apply_settings_arms_and_disarms, all five
automatic_error/suppression tests, both escalation evaluator cases, channel URL +
HTTPS cases, storage open/stage/interrupt/prune/refusal/symlink cases, all seven
feature-listing/reconcile cases, return-home pair, request-id/concurrency pair,
manifest-404 quartet, unsupported, scheduler pair, coalescing, settings-read-retry,
install-stop, active-feature, nightly/latest escalation timers).

## GREEN evidence

```
cd frontend/src-tauri
cargo fmt --check                                  -> clean (FMT_OK)
cargo clippy --locked --all-targets -- -D warnings -> Finished, zero warnings
cargo test --locked                                -> test result: ok. 205 passed; 0 failed
                                                     (157 pre-existing + 48 updater)
cargo build --locked                               -> Finished `dev` profile
git status Cargo.lock                              -> UNCHANGED (zero lockfile churn)

load-sensitivity protocol: `cargo test --locked updater` rerun x3 isolated
  -> ok. 48 passed; 0 failed   (three consecutive green runs)

cd frontend
npm run typecheck            -> tsc --noEmit clean
npm run check:desktop-parity -> Desktop parity ledger covers 101 entries.
npx vitest run --config vite.renderer.config.ts \
  src/renderer/lib/tauri-bridge.test.ts src/renderer/lib/bridge.test.ts
                             -> Test Files 2 passed; Tests 36 passed (36)
```

## State-root boundary proof (spec mandate)

Mandate: prove the plugin's download/temp/recovery writes stay beneath
`<state-root>/updater`, else replace that piece project-owned OR stop it with the exact
reason. Findings against the pinned plugin's actual source
(`~/.cargo/registry/src/.../tauri-plugin-updater-2.10.1/src/updater.rs`):

1. `Update::download()` (lines ~652-722): streams response chunks into an in-memory
   `Vec<u8>`, verifies the minisign signature in memory, returns bytes. ZERO disk writes.
2. `check()` fetches and parses the feed JSON in memory. ZERO disk writes.
3. `install_inner()`: macOS extracts the tar.gz into `tempfile::Builder...tempdir()`
   plus a `tauri_current_app` backup tempdir (both `std::env::temp_dir()`); Windows
   writes installers via `write_to_temp` -> `make_temp_dir()` -> `env::temp_dir()`;
   Linux AppImage candidates are `[env::temp_dir(), dirs::cache_dir(), extract-path
   parent]`. NONE of these destinations is configurable — there is no API in 2.10.1 to
   point installer/recovery writes at an arbitrary directory.

Decision (mandate branch 2, recorded stop for APPLY; branch 1 for download/stage):

- CHECK + DOWNLOAD: kept on the plugin (in-memory only) and therefore already inside
  the boundary trivially — no plugin byte touches disk.
- STAGING: project-owned (`updater/storage.rs`). Every write site in this task's code
  is `storage.rs::write_atomic` / intent+meta writers, all constructing paths from the
  canonical `<state-root>/updater` root; tests pin staging location, atomicity (no
  temporaries left), traversal refusal, dotfile refusal, outside-root refusal, and
  symlink-escape refusal. Grep-level claim: the only `fs::write|rename|remove` calls in
  `src/updater/` live in storage.rs and only ever touch root-derived paths.
- ENV BACKSTOP: `state_environment` now stamps TMPDIR (unix) / TMP+TEMP (windows) to
  `<state-root>/updater/tmp`, so ANY incidental `tempfile`/`env::temp_dir()` consumer
  in-process — including every macOS/Windows plugin install path should Task 18 call
  it — lands inside `<state-root>/updater/tmp` by construction. Pinned by the updated
  `state_root_reparents_platform_state`.
- APPLY: STOPPED. Reason recorded verbatim in APPLY_DEFERRED_MESSAGE returned by
  updates_install: "update installation is deferred to the packaging task: the pinned
  updater plugin writes installer and recovery files to OS-default temp and cache
  directories that are not configurable". Residual per-platform notes for Task 18:
  (a) Linux AppImage swap falls back beside the AppImage when neither TMPDIR nor
  XDG_CACHE_HOME share its device — same-device rename is a kernel requirement;
  (b) Windows `dirs::cache_dir()` fallbacks resolve Known-Folder LocalAppData that no
  env var redirects; both are moot while install is stopped but must be answered
  before Task 18 wires apply.

## Self-review findings (found and fixed in-loop)

1. Fake transport used LIFO pops initially — several state-machine tests silently
   consumed the wrong queued response; converted to FIFO and re-verified each flow.
2. Automatic-suppression snapshot was captured in begin(); Electron captures it when
   the checking status broadcasts during an automatic check — moved to match, which is
   what makes "no checking event -> no restore" semantics reproducible.
3. Retirement tick skipped end() on error paths, leaving active_op stuck; wrapped the
   body so end() always runs.
4. download_now took the release slot BEFORE acquiring the operation lock, so a queued
   second download could spuriously report "nothing ready"; slot take moved inside the
   serialized section.
5. Feed base URLs now normalized through tauri::Url join (trailing-slash safe);
   packaged loopback HTTP explicitly rejected (production strictness).
6. Replaced hand-rolled base64 decode of key packets with the pinned `base64 =0.22.1`
   engine after the manual decoder disagreed on edge padding.

## Concerns (for reviewer adjudication)

1. RECORDED STOP — updates_install: always errors with APPLY_DEFERRED_MESSAGE; the
   sidebar "Restart to finish updating" row will surface that error in packaged builds
   until Task 18 lands a boundary-honoring apply. Downloaded builds remain staged and
   verified on disk under <state-root>/updater/staged/<version>/.
2. RECORDED STOP — GitHub HTTPS transports: StoppedReleasesSource returns Err (list ->
   [] picker; reconcile KEEPS pins, never wrongly clears) and StoppedEscalationFeeds
   degrades to no-important/no-stable (exactly Electron's unreachable-GitHub behavior,
   so latest still escalates on its 48h rule). Consequence: feature-pin auto-clearing
   and nightly stable-backfill escalation stay inert until the transport lands; adding
   reqwest as a direct dependency was deliberately rejected to avoid widening the
   pinned TLS surface without a native-runner mandate. Owner: Task 18.
3. FEED BASE URL: read from OPERATOR_UPDATER_FEED_URL at runtime; nothing bakes a
   production default yet, so packaged shells without the env fail closed ("no update
   feed is configured"). Baking belongs to Task 18's feed packaging.
4. First-run opt-in policy (ensure_update_prefs equivalent) is implemented and tested
   as first_run_settings but has NO invocation site: Go settings always exist post-
   migration, so the "file absent" trigger is gone and the prompt belongs to renderer
   onboarding. Until a caller exists, new users simply start disabled (safe default).
5. Manual-check autoDownload parity nuance: Electron fired update-downloaded during a
   MANUAL check only via its autoInstallOnAppQuit/download split; here downloads happen
   on explicit updates.download (or automatic checks). The renderer's own auto-progress
   chain (available -> download(requestId) -> install) drives the identical UX.
6. Windows/Linux cross-compiles remain unverified locally (no C toolchains), same
   standing caveat as Tasks 14/15; platform-gated code is cfg-light (state_environment
   windows arm, TMP/TEMP stamping) and mirrors reviewed patterns.

## Files changed

Created:
- frontend/src-tauri/src/updater/mod.rs (engine, seams, production glue, commands)
- frontend/src-tauri/src/updater/channel.rs
- frontend/src-tauri/src/updater/status.rs
- frontend/src-tauri/src/updater/escalation.rs
- frontend/src-tauri/src/updater/storage.rs
- frontend/src-tauri/src/updater/tests.rs (48 tests)
- frontend/src-tauri/permissions/autogenerated/{updates_status,updates_check,
  updates_return_home,updates_download,updates_install,updates_apply_settings,
  feature_builds_list,feature_builds_active}.toml (8 autogenerated)

Modified:
- frontend/src-tauri/src/lib.rs (module, updater_temp_dir + TMPDIR/TMP/TEMP stamping,
  managed UpdaterShell + engine construction + timer spawn, normal-mode handler list,
  updated pinned env test)
- frontend/src-tauri/build.rs (8 command names)
- frontend/src-tauri/capabilities/default.json (8 allow-* grants)
- frontend/src/renderer/lib/tauri-bridge.ts (updates_apply_settings dual-write)

Untouched by design: Cargo.toml (plugin already exact-pinned =2.10.1), Cargo.lock,
package.json/package-lock.json (npm API unused), perf/parity-ledger.json (rows pre-exist),
tauri.conf.json, audit/benchmark surfaces.

## Git attestation

No `git add`, `git commit`, or `git stash` was executed at any point. Working tree at
report time contains exactly the files above as unstaged modifications/untracked files
plus the controller's pre-existing progress.md edit.

## Fix round 1

Review verdict addressed: SPEC ❌ / QUALITY NOT APPROVED (0C/3I/7M). Concern-1 recorded
stop independently verified TRUE against the vendored plugin source and ACCEPTED by
ruling — untouched this round. Parked minors untouched. Three Importants fixed TDD-first:

### I1 — downgrade parity (Electron allowDowngrade=true)

- New pure seam `channel::feed_offers_candidate(current, candidate)`: semver-inequality
  (build-metadata-insensitive via `semver::Version` PartialEq), string fallback for
  unparseable input. Any feed-offered candidate that is not the running version is
  surfaced — older versions included — so return-home from a pr<N>/nightly build can
  never strand the user on Ok(None); equal versions still report not-available.
- `PluginFeedClient::check` now sets `.version_comparator(|current, candidate| ...)
  .build()` on the pinned plugin's UpdaterBuilder (plugin default was strict
  `candidate > current`, which silently refused downgrades).
- Covering tests: `feed_offers_candidate_permits_downgrades_and_rejects_equality`
  (older -> true, equal -> false, newer -> true, nightly-of-same-base -> its stable
  offered) and `return_home_to_an_older_home_channel_still_offers_it` (running 2.0.0,
  pinned pr2270, home feed offers 1.9.9 -> final status Available(1.9.9) with the home
  request id). The engine pass-through flow test was green alongside RED (disclosed per
  Task 14 convention); the comparator unit test was genuinely red at todo!.

### I2 — interrupted-download recovery reachable in production

- `perform_download` now calls `storage.begin_download(version, feed_url, now)` BEFORE
  streaming; a failed download leaves the intent in place (that record IS the
  interruption marker), a completed one clears it via complete_download.
- New `recover_interrupted(storage, now_ms, max_age_ms) -> RecoverySummary {pruned,
  pending}` consumed by `open_shell_engine` right after opening `<state-root>/updater`,
  logging both sweep results ("pruned N stale interrupted update download(s)" / "N
  interrupted update download(s) will restart from the feed").
- Covering tests: `failed_real_download_records_recovery_intent` drives the REAL
  manual_check -> download_now(failed) production path and asserts one pending intent
  (version + latest.json URL) plus the visible Error status — RED pre-fix because no
  intent existed; `recover_sweeps_stale_intents_and_reports_pending` pins prune-vs-keep
  (stale past PARTIAL_MAX_AGE_MS pruned, fresh kept, summary exact).

### I3 — download progress through engine state

- State mutation + emission moved into a cloneable `Broadcast { state:
  Arc<Mutex<EngineState>>, sink }` handle; the engine delegates its five primitives
  (with_state/begin/end/broadcast/broadcast_owned) so every existing call site is
  unchanged. The download-progress closure now captures a Broadcast clone and emits via
  `broadcast_owned`, so mid-download statuses carry the owning request id, respect the
  automatic-suppression ownership rules, and keep `updates_status` live — which also
  makes the escalation tick's "skip while downloading" guard real instead of dead.
- Replaced the untestable `mark_downloading_for_test` injection with
  `download_progress_broadcasts_through_engine_state_and_gates_escalation`: stage
  2.1.0, then stream 2.2.0 behind a gated fake transport; asserts (a) engine.status()
  itself reaches Downloading{30} during the stream (RED pre-fix: stayed Available),
  and (b) an escalation tick fired mid-stream cannot flip the row back to the stale
  staged build (RED pre-fix: it rebroadcast 2.1.0 escalated). After gate release the
  newer build stages. FakeClient gained a second deterministic gate
  (`hold_first_download` holds exactly the second download after emitting its planned
  percent).

### RED evidence (captured before implementation)

```
cargo test --locked updater
test result: FAILED. 48 passed; 4 failed; 0 ignored; 0 measured; 157 filtered out
  updater::tests::feed_offers_candidate_permits_downgrades_and_rejects_equality ... FAILED
  updater::tests::failed_real_download_records_recovery_intent ................... FAILED
  updater::tests::recover_sweeps_stale_intents_and_reports_pending ............... FAILED
  updater::tests::download_progress_broadcasts_through_engine_state_and_gates_
    escalation .................................................................... FAILED
(return_home_to_an_older_home_channel_still_offers_it: green alongside RED, disclosed)
```

### GREEN evidence (gates, exact outputs)

```
cd frontend/src-tauri && cargo fmt --check                 -> clean (FMT_OK)
cargo clippy --locked --all-targets -- -D warnings         -> Finished `dev` profile ... (0 warnings)
cargo test --locked                                        -> test result: ok. 209 passed; 0 failed;
                                                              0 ignored; 0 measured; 0 filtered out
                                                              (+ two empty integration binaries ok)
cargo build --locked                                       -> Finished `dev` profile target(s)
cd .. && npm run typecheck                                 -> tsc --noEmit clean
npm run check:desktop-parity                               -> Desktop parity ledger covers 101 entries.
git status Cargo.lock                                      -> unchanged; git diff --cached empty

Load-sensitivity: `cargo test --locked updater` isolated rerun x3 ->
  ok. 52 passed; 0 failed (three consecutive runs, includes both gated concurrency tests)
```

Net test delta: 48 -> 52 updater tests (5 added, 1 removed: mark_downloading_for_test
injection test replaced). Still fully UNCOMMITTED: nothing staged, HEAD e5e2969e9.
