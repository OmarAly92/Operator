# Task 18 Report: Build signed feeds and platform artifacts

Status: DONE_WITH_CONCERNS

Base: d60397a0f (clean tree). All work strictly UNCOMMITTED per the controller
override of the brief's Step 5 git block — nothing staged, added, or committed.
`git rm desktop-testing.yml` was briefly staged by accident and immediately
unstaged (`git reset HEAD`); the deletion is an unstaged working-tree change.

## What was implemented

### Feed builder — `frontend/scripts/tauri-feed.mjs` (new)

Dependency-free ESM (house style) generating BOTH feed families from one dist
dir:

- Tauri v2 updater JSON `<channel>.json`: `{version, notes, pub_date,
  platforms}`, platforms keyed `darwin-aarch64`, `darwin-x86_64`,
  `linux-x86_64`, `windows-x86_64`, each entry carrying the archive filename
  and its base64 minisign `.sig` blob. Serialization is deterministic (fixed
  key order, canonical alphabetical platform order, 2-space JSON, trailing
  newline).
- Electron-compatibility YAML via delegation to `feed.mjs generateFeeds(...,
  { blockmap: false })`: `latest.yml/latest-mac.yml/latest-linux.yml` (+nightly*/
  pr<N>* equivalents), pointing the installed fleet at this release's ditto zip /
  NSIS exe / AppImage. No `.blockmap` sidecars anywhere on the Tauri path — full
  downloads only, same reasoning as #3267 decision 4; default behavior of
  `feed.mjs generateFeeds` is unchanged for any other caller.

Refusals implemented (each with a dedicated test): invalid semver (strict,
leading-zero rejection), channel/version disagreement, wrong OS/architecture
(arm64 Windows exe maps to nothing rather than silently to x64), cross-channel
assets (nightly/pr tokens on foreign channels), insecure production URLs
(non-https outside loopback without explicit allowInsecure), duplicate
platforms, missing `.sig` sidecars, private-key material (secret-shaped
signatures AND private-key-named files in the dist dir), feature channels
writing latest*/nightly* manifests (#2270 class, enforced again post-write).
Version-free aliases are skipped as feed inputs while a versioned archive
carrying a DIFFERENT version still refuses the build. macOS permanence:
every selected mac updater archive must have its arch-matching ditto zip beside
it or generation fails, so latest-mac.yml can never lose its target.

CLI: `node scripts/tauri-feed.mjs <dir> <version> <channel>
[--release-date <iso>] [--important] [--notes <text>]`; npm script `feed:tauri`.

### `frontend/src-tauri/tauri.release.conf.json` (new)

Build-time overlay passed as `tauri build --config src-tauri/tauri.release.conf.json`
(npm script `tauri:release`). Sets `bundle.createUpdaterArtifacts: true`,
declares the required `plugins.updater` config (empty pubkey placeholder — the
operational public key arrives at build time as a second inline `--config` JSON
overlay built from `$OPERATOR_UPDATER_PUBLIC_KEY`; discovered empirically that
the CLI refuses createUpdaterArtifacts without plugins.updater existing, and
refuses to sign with an undecodable pubkey), and bakes the production feed base
URL under `plugins.operator-updates.feedBaseUrl`.

### Engine wiring (ruling 1) — `src/updater/mod.rs`

- `resolve_feed_base_url(env_override, plugins)`: runtime env
  OPERATOR_UPDATER_FEED_URL wins (dev/test/E2E harness), then the baked release
  config value read from `app.config().plugins`, else None (fail closed at
  check time, unchanged). `open_shell_engine` now resolves through it, so
  packaged shells no longer depend on the runtime env var.
- `spawn_updater_timers` now runs ONE immediate `run_hourly_tick()` at shell
  boot before arming the hourly loop — Electron's launch-time check parity and
  the mechanism that lets the E2E harness drive real updates headlessly
  (enable updates over loopback PATCH, relaunch, the launch check fires).
- New tests (4): env-over-baked precedence, empty-env falls through to baked,
  absent/empty/mistyped baked values yield None, and a file-level pin reading
  tauri.release.conf.json itself (createUpdaterArtifacts true, updater plugin
  config present, https production base URL).

### Packaging + verification scripts

- `frontend/scripts/package-tauri-mac-zip.sh` (new): archives the signed .app
  with EXACTLY `ditto -c -k --sequesterRsrc --keepParent` (AGENTS.md rule;
  flags documented as non-negotiable), prints sha256+bytes, refuses
  non-.app inputs and outputs inside the bundle. npm script
  `package:tauri-mac-zip`.
- `frontend/scripts/verify-tauri-artifacts.sh` (new): the fail-closed pre-
  release gate (npm script `verify:tauri-artifacts`). PASS/FAIL/GATE ledger
  printed in full and optionally written as JSON (`--emit-gates`). FAIL =
  structural violation, exits 1. GATE = honestly unverifiable here, recorded
  BY NAME, never skipped; `--strict-trust` turns gates into failures for
  signed CI. `--mode testing` downgrades updater-archive/.sig requirements to
  gates (unsigned testing builds legitimately lack them). darwin inspection
  covers the .app, the ditto zip (ditto -x -k), the updater archive (tar),
  and the DMG (hdiutil mount) — checking daemon, agent-browser, ACP runtime,
  icon, executable and Info.plist version INSIDE every package form. win32
  checks NSIS presence/arch token/sig shape/PE machine type; linux checks
  AppImage/deb/rpm presence, sig shape, dpkg-deb/rpm content listing.
  Delegated trust checks call `scripts/verify-mac-artifact.sh` directly.

- `frontend/scripts/verify-mac-artifact.sh` (modified): now also accepts the
  Tauri updater archive (`*.app.tar.gz`), extracting with `tar -xzf` — the
  updater plugin's own restore path — and reusing the same single-app
  collection + codesign/spctl/stapler trio. The zip path (ditto -x -k, never
  unzip) is untouched; spctl assessment types unchanged.

### E2E harness — `scripts/e2e-mac-update.mjs` / `.test.mjs` (ported to Tauri)

The Electron sentinel machinery (app.asar probe for
OPERATOR_E2E_UPDATE_SENTINEL, update-settings.json seeding) is replaced by the
real Tauri flow: launch packaged app with OPERATOR_RUN_FILE/OPERATOR_DATA_DIR,
wait for daemon liveness via running.json + loopback /healthz, enable updates
through `PATCH /api/v1/settings/updates` (exact Go payload shape, unit-pinned),
relaunch so the launch-time check fires against the real feed, then poll the
engine's durable staging record `<state-root>/updater/staged/<version>/meta.json`
— written only after minisign verification. `--expect-stage-only` (workflow
default while apply is pending) stops at staging proof; full mode additionally
asserts the quit-swap and relaunch liveness once the verified apply path lands.
New flags: `--expect-stage-only`, `--feed-url` (https-or-loopback validated).
Both test files were converted from vitest to the house node:test pattern —
required because the brief's gates run them under `node --test`, under which
the vitest-based versions fail even at HEAD (verified before conversion).

### Workflow ports (old → new)

| Old workflow | New content |
| --- | --- |
| frontend-release.yml | Tauri stable release: 4-leg matrix + macos-15-intel leg, signing setup action, `npm run tauri:release -- --config $UPDATER_PUBKEY_OVERLAY_JSON`, notarytool+stapler, ditto zip cut, per-platform collection, verify-tauri-artifacts, publish to v<version>, version-free aliases (--clobber), advisory e2e-gate pod job preserved verbatim, publish-feed runs tauri-feed.mjs → latest.json + latest*.yml |
| feature-release.yml | Same guard (quota/PR validation/version compute via contents API), Tauri build legs incl. release-intel x64, verify step, pr<N>.json + pr<N>*.yml generation, latest*/nightly* rejection guard EXTENDED to *.json, delete-prior-release + marker annotation preserved |
| testing-build.yml | The single unsigned testing pipeline (tag 0.0.0-testing-* + dispatch): all three OSes, base config build (no updater artifacts without key), collect + verify-tauri-artifacts --mode testing, NSIS smoke-install preserved, deb/rpm content listing added |
| desktop-testing.yml | DELETED (unstaged deletion). It was already disabled (push trigger commented out) and duplicating it as a second Tauri pipeline would itself be a stale parallel workflow; testing-build.yml is the survivor. Documented in its header comment and docs |
| build-artifacts.yml | Unsigned dispatchable conductor build at pinned ref/version: stamping kept, base-config build, structural verify, aliases + dmg + deb/rpm artifacts, per-platform sha256 digest fragments merged into digests.json, gates ledger uploaded. Header documents that macOS identity/notarization and updater-archive signing now happen conductor-side downstream |
| mac-update-e2e.yml | Post-release monitoring (unchanged posture): baseline alias download, verify-mac-artifact.sh, Tauri-bundle check replaces the asar sentinel probe, e2e-mac-update.mjs with mode input (stage-only default), baked-feed assertion now greps the compiled binary for the production endpoint instead of app-update.yml |
| release-latest-guard.yml | Required assets now include latest.json + all three compat YAMLs + zip/exe/AppImage aliases; additionally downloads latest.json and asserts all four platform keys present with non-empty signatures |

No stale parallel Electron build path remains in any workflow; forge makers/
publisher are referenced nowhere in .github/workflows.

## RED evidence (Steps 1-2, captured before implementation)

```
node --test scripts/tauri-feed.test.mjs
  -> ERR_MODULE_NOT_FOUND: Cannot find module '.../scripts/tauri-feed.mjs'
node --test scripts/feed.test.mjs
  -> # pass 10 # fail 1
     not ok: "generateFeeds blockmap:false writes no sidecars anywhere
     (Tauri migration baseline)" (2 !== 0 blockmap calls)
node --test scripts/e2e-mac-update.test.mjs
  -> SyntaxError: The requested module './e2e-mac-update.mjs' does not provide
     an export named 'patchUpdateSettings'
Rust: cargo test --locked updater::tests::baked
  -> error[E0425]: cannot find function `resolve_feed_base_url` in module `super`
```

Disclosure per the Task 14 convention: after conversion, the pre-existing
behavioral assertions in feed.test.mjs / e2e-mac-update.test.mjs were green at
RED; only the new expectations failed. The Rust resolver tests were compile-fail
RED.

## GREEN evidence (exact outputs)

```
cd frontend
node --test scripts/tauri-feed.test.mjs scripts/feed.test.mjs \
     scripts/e2e-mac-update.test.mjs
  -> # tests 44 # pass 44 # fail 0   (tauri-feed 21, feed 11, e2e-mac 12)
all other node --test suites under frontend/scripts/: every non-vitest suite
  passes (agent-browser-phase0 28, audit-tauri-state 17, benchmark-result 67,
  check-parity-ledger 15, phase0-aggregate 3, phase0-decision 48,
  phase0-legacy-update 12, phase0-platform-summary 12, phase0-updater-signing 1)
the seven vitest-based script suites (blockmap, build-acp-runtime-helpers,
  feature-channel-resolution, feature-version, go-version, nightly-version,
  verify-mac-artifact) fail under `node --test` AT HEAD TOO (they import vitest)
  and pass under their own runner:
  npx vitest run ... -> Test Files 7 passed, Tests 56 passed
npm run typecheck            -> tsc --noEmit clean
npm run check:desktop-parity -> Desktop parity ledger covers 101 entries.
npm run verify:tauri-artifacts -- --dist <local pipeline dist>
  -> 23 passed, 0 failed, 4 gated; exit 0 (gates recorded by name)

cd frontend/src-tauri
cargo fmt --check            -> clean
cargo clippy --locked --all-targets -- -D warnings -> Finished, 0 warnings
cargo test --locked          -> test result: ok. 213 passed; 0 failed
                              (209 pre-existing + 4 new); Cargo.lock UNTOUCHED
load-sensitivity: cargo test --locked updater isolated rerun x3
  -> ok. 56 passed; 0 failed, three consecutive runs
cargo build --locked         -> Finished `dev` profile

YAML validity of every touched workflow (js-yaml parse):
  build-artifacts.yml OK (build,digests)      testing-build.yml OK (build)
  frontend-release.yml OK (release,release-intel,e2e-gate,publish-feed)
  feature-release.yml OK (guard,release,release-intel,publish-feed)
  mac-update-e2e.yml OK (update-e2e)          release-latest-guard.yml OK
```

## Local build exercise (honest record)

Commands actually run locally on macOS (arm64), all unsigned/ad-hoc as expected:

```
npx tauri signer generate -w /tmp/t18key --password "" --ci   (ephemeral; the
  private half was destroyed after the exercise and never entered the repo)
npm run build:daemon && npm run browser-runtime:prepare -- --quiet \
  && npm run build:acp-runtime                                -> PREBUILDS_OK
TAURI_SIGNING_PRIVATE_KEY=... OPERATOR_UPDATER_PUBLIC_KEY=... \
  npm run tauri:release -- --debug --config '{"plugins":{"updater":{"pubkey":"..."}}}'
  -> EXIT 0; produced Operator.app, Operator.app.tar.gz + .sig,
     Operator_0.10.3_aarch64.dmg
./scripts/package-tauri-mac-zip.sh <app> /tmp/t18dist/operator-darwin-arm64-0.10.3.zip
  -> ditto archive 85,194,849 bytes, sha256 d2b068a5...
node scripts/tauri-feed.mjs /tmp/t18dist 0.10.3 latest --release-date ...
  -> latest.json (real embedded signature) + latest-mac.yml
verifyFixture() from phase0-updater-signing.mjs against the real archive/sig/key
  -> CRYPTO_VERIFY_OK
./scripts/verify-tauri-artifacts.sh --dist /tmp/t18dist --expect-version 0.10.3
  -> 23 structural PASSes incl. daemon+agent-browser+acp-runtime found INSIDE
     zip, tar.gz and mounted dmg; trust gates recorded by name
```

Two real defects found BY this exercise and fixed in-loop: (a) empty pubkey
placeholder passes config parse but fails signing decode — hence the inline
pubkey overlay in every signed workflow step; (b) genuine Tauri signatures
contain the comment words "signature from tauri secret key", which the first
private-key heuristic false-positived on — replaced with exact encrypted-
secret-key/PEM markers plus strict packet structure (74-byte ED packet).

## Local-vs-external gate ledger

| Gate | Status | Where proven / why external |
| --- | --- | --- |
| Feed generation + all refusal rules (semver, sig, arch, channel, URL, dupes, sidecars, keys, cross-channel) | LOCAL GREEN | 21 tauri-feed tests; real-artifact CLI run above |
| Compat YAML generation, permanent latest-mac.yml, no blockmaps on Tauri path | LOCAL GREEN | 11 feed tests + real latest-mac.yml output |
| ditto zip packaging (exact flags) | LOCAL GREEN | package script run on real bundle |
| Updater archive minisign signing + crypto verification | LOCAL GREEN (ephemeral key) | CRYPTO_VERIFY_OK above |
| Package resource inspection (daemon/agent-browser/ACP/icons) for app+zip+tar.gz+dmg | LOCAL GREEN | verifier: 23 structural PASSes |
| macOS code identity + notarization + staple | EXTERNAL GATE | requires Apple Developer ID secrets + notarytool; recorded by name by verify-mac-artifact trio under --strict-trust in signed CI |
| Windows NSIS build + silent-install smoke + Authenticode | EXTERNAL GATE | no local Windows runner/toolchain; testing-build.yml runs the smoke, release workflow records Authenticode evidence; verifier emits named gates when run off-host |
| Linux AppImage/deb/rpm builds + dpkg-deb/rpm content inspection + rpm -K signature | EXTERNAL GATE (builds+inspection) / EXTERNAL GATE (rpm -K) | ubuntu runner steps authored in testing-build.yml/build-artifacts.yml/frontend-release.yml; rpm key import lives with signing infra |
| Real signed update E2E: latest, nightly, feature-pin downgrade, return-home, pin-clearing, Tauri→Tauri install swap, Electron→Tauri migration | EXTERNAL GATE | needs published signed feeds + signed installs on native runners; stage-only harness mode + launch-check wiring landed so mac-update-e2e.yml is executable the moment apply lands; full-install mode asserted there |
| updates_install verified APPLY path | RECORDED STOP (Task 17) carried forward — SPAWNED follow-up, see ruling 2 |

## The three carried rulings

1. **Production feed base URL baked** — IMPLEMENTED. `tauri.release.conf.json`
   carries plugins.operator-updates.feedBaseUrl =
   https://github.com/OmarAly92/operator/releases/latest/download/;
   `resolve_feed_base_url` prefers runtime env, falls back to the baked value,
   else fails closed. Pinned by Rust tests reading the conf file itself and by
   a node:test asserting the file equals PRODUCTION_FEED_BASE_URL.
2. **Project-owned verified APPLY path** — SPAWNED as
   `.superpowers/sdd/2026-08-20-tauri-port/followup-verified-apply-brief.md`.
   Rationale: Task 17's boundary stop was independently verified against the
   vendored plugin source; replacing install_inner per-platform means writing an
   installer/swapper whose Windows NSIS handoff and Linux AppImage replacement
   cannot be honestly tested outside native runners, and whose macOS path
   interacts with identity/notarization/quarantine. A half-tested swapper is a
   worse release risk than the current fail-closed stop (staged builds remain
   verified on disk; updates_install surfaces the deferral message). This keeps
   Task 17's RELEASE-GATING deferral attached to a concrete owner brief.
3. **GitHub HTTPS transports shell-side** — SPAWNED as
   `.superpowers/sdd/2026-08-20-tauri-port/followup-github-transports-brief.md`.
   Rationale: Task 17 deliberately kept reqwest out "without a native-runner
   mandate" — overturning that accepted TLS-surface ruling belongs to its own
   review gate; honest verification of the new dependency tree requires
   three-platform cargo gates this task cannot run locally. The seams
   (ReleasesSource/EscalationFeeds) are already shaped for it; degradation
   behavior remains exactly Electron-unreachable-GitHub until then.

## Self-review findings (found and fixed in-loop)

1. selectUpdaterArchives originally SKIPPED version-mismatched archives
   silently while my own test demanded a throw — tightened to refuse any
   updater archive carrying a different version string, while version-FREE
   aliases are skipped (they share the dist dir by design).
2. First private-key heuristic rejected EVERY genuine Tauri signature ("secret
   key" appears in the signer's own comment) — caught by running the REAL
   pipeline, not by unit tests; replaced with exact markers + strict packet
   structure, plus a regression fixture carrying the real comment.
3. buildTauriFeed validated URLs without threading allowInsecure, which would
   have broken loopback dev feeds; fixed.
4. package-tauri-mac-zip.sh inner-path refusal compared relative paths and did
   NOT trigger (`Operator.app/x.zip` got written inside the bundle); now both
   sides resolve to absolute paths before comparison.
5. Dead scaffolding removed from tauri-feed.mjs after refactors
   (channelTokenOf, duplicate doc block, duplicated secret-key scan).
6. Workflow patch typo UPDATER_PUBKEY_OVERLY_JSON corrected to OVERLAY before
   final YAML validation.
7. desktop-testing.yml deletion briefly STAGED via `git rm`; immediately reset —
   tree carries it as an unstaged deletion.

## Concerns for reviewer adjudication

1. Launch-time automatic check added to spawn_updater_timers (one immediate
   run_hourly_tick at boot). Justified as Electron initAutoUpdates parity and
   required for any headless update E2E, but it IS a production-behavior change
   to Task 17's reviewed engine. Coverage rides on the existing automatic-check
   tests (the property is timing-based against real timers; no isolated test).
   Reviewer may prefer reverting to hourly-only and driving E2E another way.
2. plugins.updater.pubkey ships EMPTY in the tracked conf and is supplied at
   build time via inline --config JSON overlay from $OPERATOR_UPDATER_PUBLIC_KEY
   (empirically: empty passes config parse, fails only at signing decode; the
   engine itself never reads plugin config). If the reviewer prefers, the
   operational public key can be committed into the conf instead once generated.
3. desktop-testing.yml DELETED rather than ported — reading of "no stale
   parallel workflows"; it was disabled at HEAD. Reverting to a stub is trivial
   if the reviewer wants the file present.
4. nightly has NO schedule workflow in this branch (inherited state; old doc
   referenced frontend-nightly.yml which does not exist here). Nightly feeds are
   fully supported by tooling (--important, channel validation); the schedule
   workflow itself is out of this task's file contract.
5. e2e-mac-update.mjs relaunch flow uses `spawn(...).unref()` with inherited
   stdio; first-launch daemon readiness is polled via run-file + /healthz. Not
   executed locally (needs a packaged installed app + real feed) — the harness's
   pure surface is unit-tested, execution lands with the external-gate runs.
6. verify-tauri-artifacts.sh deb/rpm member checks grep listing text for
   "daemon"/"agent-browser"/"acp-runtime" substrings (paths vary across layout
   changes); stricter path pinning can be tightened on native-runner evidence.

## Fix report round 1

All seven Important findings fixed. Nothing staged or committed; tree remains
working-tree-only on top of d60397a0f. No new dependencies; generated output
untouched.

### SA1 — private-key scan naming bypass (`frontend/scripts/tauri-feed.mjs`)

TDD. RED first: three new tests added to `frontend/scripts/tauri-feed.test.mjs`
("assertNoPrivateKeyMaterial refuses an innocently named minisign secret key"
with a `signing_key` fixture shaped exactly like `tauri signer generate -w`
output, "refuses comment-stripped secret-key packets by structure", and
integration-level "generateFeeds refuses to run while a signing_key sits in the
dist"). RED run: `node --test scripts/tauri-feed.test.mjs` →
`# tests 24 # pass 21 # fail 3` with exactly those three `not ok`.

Fix (`tauri-feed.mjs:185-268`): the exact material markers now live in a shared
`PRIVATE_KEY_MATERIAL` const reused by `validateSignature` (both its throws —
no behavior change there) and the new scanner; new exported
`looksLikePrivateKeyMaterial(text)` adds strict packet structure — an
`untrusted comment:` line followed by base64 whose decoded packet carries the
minisign SECRET-key algorithm tag `RS` (signatures are tagged `ED`, so genuine
`.sig` files never trip it). `assertNoPrivateKeyMaterial` now content-scans
EVERY regular file in the dist via a bounded 64 KiB prefix read
(`openSync/readSync/closeSync`, latin1 decode so ASCII markers survive), skips
nothing by name except non-regular entries (directories have no content to
scan), and additionally reads suspiciously NAMED files (`PRIVATE_KEY_NAME`)
in FULL. Read/stat failures refuse the build rather than skip. The loose
"secret key" comment heuristic was NOT reintroduced.

GREEN: `node --test scripts/tauri-feed.test.mjs scripts/feed.test.mjs
scripts/e2e-mac-update.test.mjs` → `# tests 47 # pass 47 # fail 0`
(tauri-feed 24 incl. the three new, feed 11, e2e-mac 12). Extra sanity run:
clean scan of a dist holding a 100 MB exe + real-shaped sig completed in 1 ms
(bounded prefix); key material placed deep (>64 KiB) inside a `.key`-named file
is still caught by the suspicious-name full read.

### SA2 — licenses never inspected (`frontend/scripts/verify-tauri-artifacts.sh`)

- `check_bundle_resources` (line ~176) now requires license notices inside every
  mac package form it inspects (.app, ditto zip, updater archive, DMG):
  `find Resources -maxdepth 2 -name 'LICENSE*' -type f`; absent → structural
  FAIL ("bundles no licenses"), present → PASS naming the first notice found.
- win32 NSIS block: installer is listed with 7z/7zz when available and must
  show license notices (FAIL closed if absent); when no listing tool exists on
  the host the gap is recorded as a named GATE ("nsis installer license
  notices unverified here") — never silent.
- linux deb member loop extended with `"LICENSE"` (dpkg-deb -c listing); rpm
  listing hoisted into `$RPM_LISTING` and a second check requires a LICENSE
  path (`rpm -qlp`). Header doc block updated to include licenses.

Evidence (real runs of the modified script on this macOS host against a
synthetic four-form dist: ditto zip via the canonical flags, tar.gz updater
archive + minisign-blob .sig, hdiutil DMG, all carrying
agent-browser/LICENSE-*):
- positive: `./scripts/verify-tauri-artifacts.sh --dist <fixture> --platform
  darwin --expect-version 0.10.4` → `== summary: 26 passed, 0 failed, 4 gated`,
  exit 0, with `bundles licenses (agent-browser/LICENSE-agent-browser)` PASS on
  updater archive, zip AND dmg.
- negative (licenses stripped from the zip's app only): same command →
  `FAIL: operator-darwin-arm64-0.10.4.zip bundles no licenses (license notices
  are required in every base artifact)` among 4 failures, exit 1.
- `bash -n scripts/verify-tauri-artifacts.sh` → clean.

### WB1 — strict-trust gate armed on the four signed-CI invocations

`--strict-trust` added at exactly: `frontend-release.yml:162` (release matrix
leg) and `frontend-release.yml:309` (release-intel leg), `feature-release.yml:360`
(release matrix leg) and `feature-release.yml:480` (release-intel leg). The two
unsigned `--mode testing` invocations (testing-build.yml:91,
build-artifacts.yml:142) are untouched. grep over .github/workflows shows
exactly four `--strict-trust` occurrences, matching the step names' claim.

### WB2 — impossible baked-feed assertion fixed

`mac-update-e2e.yml` "Verify the updated app bakes the production feed base
URL": grep target changed from the runtime concatenation
`releases/latest/download/latest.json` (never contiguous in the binary — the
engine joins baked base URL + channel manifest at runtime) to the baked base
URL alone `github.com/OmarAly92/operator/releases/latest/download/`, with the
step comment stating why the concatenation must not be asserted again.

### WB3 — blocking enforcement restored

The "Enforce gate (blocking mode, opt-in)" step was restored into
frontend-release.yml's e2e-gate job (after "Publish opr-stable-gate check"),
byte-identical to `git show d60397a0f:.github/workflows/frontend-release.yml`
(diff of the extracted step blocks: identical): same `if` on
`always() && vars.OPERATOR_GATE_BLOCKING == 'true' &&
steps.gate.outputs.classification == 'app_failed'`, same ::error + exit 1.
Adaptation needed: none (job/step ids unchanged in the port).

### WB4 — digests.json covers every collected artifact class

`build-artifacts.yml` "Digest collected artifacts" now walks ALL collected
classes — `dist-artifact/operator-*` (zip/exe/AppImage aliases),
`dist-deb/*`, `dist-rpm/*`, `dist-macos-extra/*` (dmg) — via nullglob array,
fails loudly when nothing was collected, and writes one
`dist-artifact/$PLATFORM.digest.json` per leg as before. Also restored the
deleted "Upload digest" step (`digest-${{ matrix.platform }}`) without which
the digests job's `pattern: digest-*` download had nothing to merge — the
regression went deeper than the loop's coverage. Validated by js-yaml parse
(see below); the fragment→merge contract matches HEAD's original workflow.

### WB5 — toolchain pin actually selected

One mechanism everywhere: job-level env `RUSTUP_TOOLCHAIN: "1.96.0"` added to
all six jobs that install the pinned toolchain — frontend-release.yml `release`
+ `release-intel`, feature-release.yml `release` + `release-intel`,
testing-build.yml `build`, build-artifacts.yml `build` (grep count: 2+2+1+1).
This selects 1.96.0 for EVERY cargo/rustc invocation in the job including the
nested `npm run tauri:*` cargo shells, independent of step order; the existing
`rustup toolchain install 1.96.0 --profile minimal` steps are unchanged (the
explicit-toolchain install is unaffected by the override). mac-update-e2e.yml
has no rustup site (it builds nothing); tauri-phase0.yml is outside this task's
finding list and untouched.

### Round-1 verification commands actually run

```
cd frontend
node --test scripts/tauri-feed.test.mjs            (RED, before fix)
  -> not ok 10 innocently named / not ok 11 comment-stripped / not ok 12
     generateFeeds signing_key ; # tests 24 # pass 21 # fail 3
node --test scripts/tauri-feed.test.mjs scripts/feed.test.mjs \
     scripts/e2e-mac-update.test.mjs               (GREEN, after fix)
  -> ok 10/11/12 ... ; # tests 47 # pass 47 # fail 0 # cancelled 0
bash -n scripts/verify-tauri-artifacts.sh          -> clean
verify-tauri-artifacts.sh --dist <synthetic 4-form mac dist> ...
  -> positive: 26 passed 0 failed 4 gated, exit 0 (licenses PASS x3 forms)
  -> negative (license-less zip form): 7 passed 4 failed, exit 1
     ("...zip bundles no licenses")
js-yaml parse of every touched workflow:
  frontend-release.yml OK (jobs: release,release-intel,e2e-gate,publish-feed)
  feature-release.yml OK (jobs: guard,release,release-intel,publish-feed)
  testing-build.yml OK (jobs: build)
  build-artifacts.yml OK (jobs: build,digests)
  mac-update-e2e.yml OK (jobs: update-e2e)
```

Untouched by design: vitest suites (no vitest subject modified),
tauri-phase0.yml, release-latest-guard.yml, desktop-testing.yml deletion, all
parked minor findings, `frontend/src-tauri/gen|target`.

## Fix report round 2

NB1 + INTEL fixed per the controller's three-tier ruling. Nothing staged or
committed; HEAD still d60397a0f.

### The three-tier gate model (`frontend/scripts/verify-tauri-artifacts.sh`)

Header doc block and usage() rewritten to define the tiers explicitly:

- **FAIL** — structural violation OR a trust check attempted-and-failed here.
  Still exits 1.
- **GATE** — unverifiable without CONDUCTOR-HELD material even on a fully
  equipped CI host: Authenticode validation evidence, NSIS silent-smoke
  install, NSIS payload license listing, rpm -K against the conductor key,
  macOS trust tooling absent. Recorded BY NAME; NEVER fatal, including under
  --strict-trust (rationale documented: in-workflow trust OPERATIONS — signtool,
  notarytool/stapler steps — already fail their own workflow steps naturally).
- **SCOPE-SKIP** (new) — artifact-class absence caused by matrix topology;
  printed as `INFO (out of declared scope, no ledger row): ...`, never a PASS/
  GATE/FAIL row, excluded from --emit-gates JSON.

Terminal rule changed (`verify-tauri-artifacts.sh` end): the blanket
"--strict-trust with N unresolved gates → exit 1" is GONE. Exit 1 now means
FAILURES only — and a FAILED delegated macOS codesign/spctl/staple trio lands
in FAILURES under --strict-trust (pre-existing inline rule in
mac_trust_checks, now commented as the ONE strict-fatal trust check), which is
exactly what preserves WB1's intent. gate() message reworded to "conductor-side
material needed, recorded".

### INTEL + NB1 scoping: new `--arch` option

- `--arch arm64|x64` (repeatable via comma list) parsed after --platform
  validation; invalid tokens exit 2 with usage. Sets SCOPED=1 + ARCH_LIST;
  `in_scope <arch>` treats unscoped as everything-in-scope.
- darwin updater archives are now a per-arch loop over `mac_updater_globs`
  (arm64 → *aarch64*/*arm64*; x64 → *darwin-x64*/*x86_64*): out-of-scope arch →
  scope_skip INFO line; in-scope absent → testing-gate / release-fail as
  before, EXCEPT unscoped x64 keeps its legacy lenient GATE ("Intel leg builds
  on its own runner") for byte-compatible local behavior.
- ditto zip / dmg: SCOPED runs demand one zip + one dmg PER DECLARED arch
  (per-arch globs incl. versioned names + aliases); UNSCOPED runs keep the old
  single-glob code verbatim (legacy messages intact). Trust targets collected
  into TRUST_TARGETS[] from app/zip/dmg actually inspected.
- win32/linux sections unchanged structurally — they are inherently
  single-arch; scoping there is declarative.
- One deliberate round-2 softening inside NB1's mandate (a signed win leg must
  be able to go green): my round-1 NSIS license check could structural-fail a
  good installer on fragile `7z l` payload parsing. It is now tier-2: confirmed
  listing WITH license entries → PASS; no listing tool OR listing surfacing no
  license entries → named GATE pointing at the conductor's smoke-install
  evidence. deb/rpm license checks stay structural FAILs (dpkg-deb -c / rpm
  -qlp listings are exact-path tools, verified reliable).

### Workflow scope flags (four signed legs keep --strict-trust)

- frontend-release.yml matrix verify step (~:160) and feature-release.yml
  matrix verify step (~:360): `--arch "$(uname -m | sed 's/x86_64/x64/')"` —
  resolves to arm64 on the macos arm64 runner, x64 on windows/linux/intel;
  comment states the corrected strict-trust semantics and the topology
  rationale.
- frontend-release.yml release-intel (~:320) and feature-release.yml
  release-intel (~:491): explicit `--platform darwin --arch x64`.
- Unsigned testing runs untouched (judged: their collection steps produce
  gates-only absences — e.g. testing-build's darwin leg legitimately ships no
  updater archives — and --mode testing rows are never fatal; scoping would be
  churn).

### docs

frontend/docs/desktop-release.md verifier paragraph rewritten to the
three-tier model, the --arch flag, and the precise --strict-trust meaning
(gates non-fatal; failing mac seal trio fatal).

### Round-2 validation (real outputs)

Synthetic dists rebuilt in /tmp/t18-r2 (arm64-full, x64-full, license-less-zip
arm64 variant); a shadowed PATH (1205-entry fakebin lacking
codesign/spctl/stapler/xcrun) simulates a CI host without macOS trust tooling.

```
bash -n scripts/verify-tauri-artifacts.sh            -> clean
--arch bogus                                         -> "must be a comma-separated
                                                        list drawn from: arm64, x64", exit 2

(1) SCOPED POSITIVE under --strict-trust (codesign-shadowed host):
  ./scripts/verify-tauri-artifacts.sh --dist dist-arm64 --platform darwin \
    --arch arm64 --strict-trust --expect-version 0.10.4 --emit-gates g.json
  -> EXIT=0; "== summary: 26 passed, 0 failed, 3 gated"; conductor gates
     recorded by name (unpacked-.app-absent + 2x "macOS trust tooling
     unavailable ... (conductor-side evidence)"); NO x64 gate row anywhere;
     x64 classes printed as "INFO (out of declared scope, no ledger row)";
     emitted JSON findings = {gate x3} and grep -c x64 g.json -> 0.

(2) REAL TRUST FAILURE under --strict-trust (real PATH, unsigned fixture):
  same command without PATH shadow
  -> EXIT=1; FAIL "--strict-trust: operator-darwin-arm64-0.10.4.zip failed
     seal/notarization/staple" (+ .dmg twin); summary "26 passed, 2 failed,
     3 gated"; "FAILED (2 failure(s); includes trust checks attempted and
     failed here)". Strict trust CAN still fail a release.

(3) UNSCOPED DEFAULT UNCHANGED:
  ./scripts/verify-tauri-artifacts.sh --dist dist-arm64 --expect-version 0.10.4
  -> EXIT=0; "== summary: 26 passed, 0 failed, 4 gated" — identical shape to
     the round-1 run INCLUDING the legacy "GATE: no mac x64 updater archive in
     dist (Intel leg builds on its own runner)" row and zero INFO lines.

(INTEL pair) x64-only dist:
  unscoped release mode   -> EXIT=1, "FAIL: no mac arm64 updater archive"
                             (the reported defect reproduced)
  --platform darwin --arch x64 --strict-trust (shadowed PATH)
                          -> EXIT=0; x64 updater REQUIRED+inspected, zip/dmg
                             "(x64)" inspected, arm64 classes INFO-skipped;
                             26 passed / 0 failed / 3 gated

(scoped structural negative) license-less zip form, scoped strict:
  -> EXIT=1 with "operator-darwin-arm64-0.10.4.zip bundles no licenses ..."
     among the FAILs — scoping weakens nothing structural.

js-yaml parse of touched workflows:
  frontend-release.yml OK (jobs: release,release-intel,e2e-gate,publish-feed)
  feature-release.yml OK (jobs: guard,release,release-intel,publish-feed)
Parsed step commands verified post-parse: both matrix legs resolve to
"... --strict-trust --arch \"$(uname -m | sed 's/x86_64/x64/')\" --expect-
version ... --emit-gates artifact-gates.json"; both intel legs contain
"--platform darwin --arch x64".

No collateral damage: node --test scripts/tauri-feed.test.mjs
scripts/feed.test.mjs scripts/e2e-mac-update.test.mjs
  -> # tests 47 # pass 47 # fail 0 # cancelled 0
```

Tree state after round 2: nothing staged, nothing committed; temp fixtures
removed.

## Fix report round 3

BUILD fixed per the controller ruling. Nothing staged or committed; HEAD still
d60397a0f. Release-workflow invocations untouched this round (grep: --arch/
--strict-trust sites identical to round 2; `--expect-aliases` and
`--extra-dist` appear in build-artifacts.yml ONLY).

### `--extra-dist <dir>` (repeatable) — sibling collection dirs

`frontend/scripts/verify-tauri-artifacts.sh`:
- New helper `find_across_dists <glob>...`: searches the primary --dist first,
  then each extra dir in declaration order; sets FIND_DIR/FIND_NAME on a hit,
  returns 1 only when a class is absent from ALL declared dirs (the callers'
  cue to fail). Declared dirs are validated at parse time — an empty argument
  or a non-existent dir exits 2 with usage (a typo'd sibling is caller error,
  not an empty dir).
- Every class-absence check now routes through it BEFORE failing: mac updater
  archives (per arch), ditto zips + dmgs (both unscoped-legacy and scoped
  branches), win32 NSIS exe, linux AppImage/deb/rpm. A class found in an extra
  dir is inspected THERE with full checks exactly as if primary — inspectors
  (`inspect_mac_zip` / `inspect_updater_archive` / `inspect_dmg`,
  `check_sig_sidecar`, new `require_file_in`) all take `<dir> <name>` now.
- Provenance is visible in the ledger: rows for sibling-resident artifacts
  carry a ` [from dist-macos-extra]`-style suffix (`from_suffix`). Trust-trio
  targets include sibling-resident zip/dmg.
- Composes with --arch scoping unchanged (scoped darwin loops consult extras
  per declared arch; out-of-scope classes still INFO-skip).

### `--expect-aliases` — opt-in version-free alias layout

The filename version grep (`ls -1 | grep -c "$EXPECT_VERSION"`) is skipped in
alias layout with a named PASS note: "version-free alias layout; filename
version check skipped (--expect-aliases), version asserted via embedded bundle
metadata". Embedded-metadata assertions remain FULLY active: the
CFBundleShortVersionString vs --expect-version equality inside
check_bundle_resources still runs on every inspected bundle form regardless of
the flag (no exe/AppImage metadata checks exist in the script, so none needed
preserving). Header doc block and usage() document both flags.

### build-artifacts.yml verify step

Now passes `--expect-aliases`, `--extra-dist dist-macos-extra`,
`--extra-dist dist-deb`, `--extra-dist dist-rpm`, and `--arch "$(uname -m |
sed 's/x86_64/x64/')"` (round-2 convention: arm64/x64 per matrix runner),
keeping `--mode testing` and `--emit-gates artifact-gates-<platform>.json`
unchanged. Comment explains why each flag matches the collection contract.

### Round-3 validation (real outputs)

Fixtures mirrored the BUILD topology exactly: alias-only
`dist-artifact/operator-darwin-arm64.zip` + sibling
`dist-macos-extra/operator-darwin-arm64.dmg` (+ empty dist-deb/dist-rpm), a
license-less variant, a versioned flat dist (release-style control), and a
linux-leg layout (AppImage primary, deb/rpm siblings).

```
bash -n scripts/verify-tauri-artifacts.sh -> clean
js-yaml parse build-artifacts.yml         -> OK (jobs: build,digests); parsed
  verify step renders the exact intended command incl. both --extra-dist
  flags, --expect-aliases, --arch expression, --mode testing kept

(1) POSITIVE (BUILD topology):
  verify-tauri-artifacts.sh --dist .../dist-artifact \
    --extra-dist .../dist-macos-extra --extra-dist .../dist-deb \
    --extra-dist .../dist-rpm --platform darwin --arch arm64 \
    --mode testing --expect-aliases --expect-version 0.10.4
  -> EXIT=0; "17 passed, 0 failed, 4 gated";
     "PASS: version-free alias layout; filename version check skipped
      (--expect-aliases), version asserted via embedded bundle metadata";
     dmg fully inspected FROM THE EXTRA DIR: "mac dmg (arm64) present
     (operator-darwin-arm64.dmg) [from dist-macos-extra]" + daemon/
     agent-browser/acp-runtime/licenses/executable/icon/version PASSes all
     carrying "[from dist-macos-extra]"; embedded version asserted (both forms
     "reports version 0.10.4"); x64 classes INFO-skipped.

(2) NEGATIVE (inspection still bites): license-less variant, same flags
  -> EXIT=1; FAILs on BOTH forms including
     "operator-darwin-arm64.dmg [from dist-macos-extra] bundles no licenses"
     ("13 passed, 4 failed, 4 gated").

(3) RELEASE PATH UNAFFECTED:
  versioned flat dist WITHOUT --expect-aliases ->
    "PASS: artifacts carry version 0.10.4", EXIT=0 (17 passed / 4 gated)
  alias-only dist WITHOUT the flag ->
    "FAIL: no artifact name in ... mentions 0.10.4", EXIT=1
    (the reported BUILD defect reproduced verbatim)
  unscoped no-flag run -> EXIT=0 (legacy shape preserved)

(4) LINUX LEG TOPOLOGY spot-check (--platform linux, deb/rpm as siblings):
  -> EXIT=0; "linux deb present (operator-linux-x64.deb) [from dist-deb]",
     "linux rpm present (operator-linux-x64.rpm) [from dist-rpm]";
     dpkg-deb/rpm absent on this macOS host -> their content checks recorded
     as named GATEs (on ubuntu runners they run structurally, unchanged).

Edge cases: nonexistent --extra-dir refused exit 2 ("is not an existing
directory"); missing --extra-dist value refused exit 2; a first-pass bug where
the validation loop iterated a phantom empty element when NO --extra-dist was
passed was caught by scenario (3a) exiting 2 and fixed (loop guarded on array
length).

No collateral damage: node --test scripts/tauri-feed.test.mjs scripts/feed.test.mjs
scripts/e2e-mac-update.test.mjs -> # tests 47 # pass 47 # fail 0 # cancelled 0
```

Tree state after round 3: nothing staged, nothing committed; temp fixtures
removed.
