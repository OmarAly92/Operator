# Tauri trusted atomic release pipeline — design

**Date:** 2026-08-26
**Status:** proposed design
**Program:** `docs/superpowers/specs/2026-08-26-tauri-stabilization-program-design.md`
**Owns:** partial public stable releases, updater-key/native-signing trust, and contradictory completion records.

## Outcome

A stable Tauri release is invisible to users until one trusted conductor proves that every required artifact was built from one source commit, carries the required native and updater trust, passed the declared acceptance gates, and matches one complete inventory. Publication has one visibility transition: a complete verified draft becomes public.

The pipeline fails closed while the binding port decision remains `stop-port` or required cross-platform evidence is absent. Completing the pipeline implementation does not itself authorize a release.

## Release invariants

1. No matrix build or signer has repository-release write permission.
2. No parallel job creates a public release, moves a stable tag, changes a feed, or updates a version-free alias.
3. Stable source is an exact commit reachable from the protected `master` branch and has a consistent version across required manifests.
4. All candidate artifacts remain private until all gates pass.
5. Every artifact is identified by SHA-256, platform, architecture, package kind, version, channel, source commit, and producing run.
6. Every updater signature is tested against the exact public key compiled into the corresponding application.
7. Native signing and trust verification are fatal for every format that claims native trust.
8. Native acceptance, compatibility, and binding Phase 0 decisions apply to the exact artifact digests being published.
9. Exactly one conductor holds `contents: write` and the protected publication environment.
10. A failed run cannot expose a partial release or mutate the current stable feed.

## Pipeline architecture

```text
Trusted release request
  validate master SHA + version + clean policy
                 │
                 ▼
Unprivileged platform builds
  no release environment, contents read
  unsigned candidate + build manifest + provenance
                 │
                 ▼
Isolated platform signers
  scoped credentials, no repository write
  signed artifacts + signing records
                 │
                 ▼
Artifact verification and updater-key binding
                 │
                 ▼
Signed native acceptance + compatibility + Phase 0 evidence gates
                 │
                 ▼
Single trusted conductor
  reconstruct and verify complete inventory
  create private draft, upload, remote-verify
  publish once
```

Build, signing, testing, and publication are separate authorities. They may live in one workflow DAG if permissions and environments remain separate, but a job cannot accumulate these roles.

## Release request and admission

The stable workflow starts only through an explicit trusted dispatch or protected tag/release mechanism from the default branch. Pull-request triggers never enter the signing/publishing DAG.

Admission verifies:

- requested commit is a full immutable SHA;
- GitHub reports it reachable from protected `master`;
- no disallowed dirty/generated drift exists in a clean checkout;
- application version is valid, stable, non-prerelease, and consistent across Go/frontend/Tauri/package metadata governed by current repository policy;
- the release tag and version do not already exist publicly;
- the same source/version has no conflicting in-progress conductor;
- required toolchain/action references are immutable and approved;
- the binding port-decision input is present and structurally valid.

A workflow concurrency group keyed by stable channel and version uses `cancel-in-progress: false`. A second publisher waits or fails; it never cancels a conductor during publication.

## Unprivileged platform builds

macOS, Windows, and Linux build jobs have `contents: read`, no protected release environment, and no signing secrets. They use locked dependencies and canonical preparation commands for the daemon, browser runtime, and ACP runtime.

Each job outputs private CI artifacts:

- unsigned or ad-hoc candidate payloads suitable for the platform signer;
- effective Tauri configuration with secret fields removed;
- compiled updater public-key identifier and a build-generated challenge interface/evidence hook;
- normalized resource inventory and digests;
- source/build provenance and SBOM where already supported;
- expected release artifact inventory for that platform.

The manifest uses normalized allowlisted relative paths and rejects traversal, links, devices, duplicates, and undeclared files. Build jobs do not create GitHub releases.

## Platform signing stages

Each signer runs on the native platform where required, uses an isolated protected environment, receives only that platform's credentials, and has no repository-write token.

### macOS

The signer signs the application and bundled helper/sidecars, applies hardened-runtime entitlements, notarizes required deliverables, staples where applicable, and creates the zip with `ditto`. It builds both the DMG and permanent zip/update artifacts required by current users.

Verification uses `frontend/scripts/verify-mac-artifact.sh` and therefore includes strict `codesign`, verbose Gatekeeper assessment, and stapler validation. Extracting a verification copy uses `ditto`, never plain `unzip`.

### Windows

The signer applies Authenticode to the Operator executable, updater helper, every PE executable shipped inside the installer, and the NSIS installer. It uses a trusted timestamp service through the approved signing provider.

Verification is fatal and runs on Windows. It validates signature status, certificate chain, expected publisher subject/thumbprint, timestamp, product identity, and signatures after installer extraction where feasible. Missing, unknown, test, expired-without-valid-timestamp, or wrong-publisher signatures fail the stage.

### Linux

The signer produces:

- updater/minisign signatures for the update payloads;
- an embedded GPG package signature for RPM, verified with `rpm -K` against the release keyring;
- a detached OpenPGP signature for deb, verified against the release keyring;
- a detached OpenPGP signature for AppImage, verified against the release keyring.

Checks are fatal. A warning-only Authenticode, RPM, deb, AppImage, or updater-trust result cannot be converted to success by a workflow input.

### Credential handling

Signers use short-lived/OIDC-backed credentials where providers allow it. Imported keychains, certificates, and GPG homes are created in isolated job storage and removed in unconditional cleanup. Logs and artifacts expose only public certificate/key identifiers.

## Updater key-binding proof

Comparing environment variable names or signature shape is insufficient. Each signed application must prove it accepts signatures from the private key used for its feed and rejects a different key.

For each platform/architecture candidate:

1. the build emits a random, non-secret challenge and the app's compiled updater-key identifier through a reviewed test interface available only in explicit release-verification mode;
2. the signer signs a synthetic manifest/artifact fixture containing that challenge with the channel's updater private key;
3. it also supplies a fixture signed by an unrelated test key;
4. a production-capability build of the signed app checks both fixtures through the real registered updater feed client;
5. acceptance requires the release fixture to succeed and the unrelated fixture to fail with `signature_invalid`;
6. the evidence record binds results to application digest, compiled key identifier, challenge digest, platform, architecture, source commit, and signer run.

The private key never enters the application test job. The signed fixtures are public verification material. The checked-in channel trust policy maps stable, nightly, and feature feeds to their permitted updater key identifiers. It may deliberately share a trust root when cross-channel updates require it, but every candidate must compile the exact key permitted for its channel and prove the corresponding private-key binding. A candidate compiled with an unlisted or wrong-channel key fails stable admission.

## Signed artifact verification

A trusted verifier reconstructs one canonical release inventory from signer manifests. It rejects:

- missing required platform/architecture/package roles;
- extra undeclared assets;
- duplicate normalized names;
- mismatched versions, channels, commits, application identities, or architectures;
- digest changes between build, signing, testing, and conductor download;
- missing native signatures or nonfatal trust output;
- updater feeds with insecure production URLs, wrong targets, invalid semantic versions, missing sizes/signatures, or private-key material;
- compatibility feeds that omit required Electron-to-Tauri migration assets;
- macOS inventory without both DMG and permanent zip/`latest-mac.yml` support.

The canonical manifest is deterministic and hashable. Every downstream gate references its digest.

## Acceptance and evidence gates

Before publication the DAG requires successful records for the exact canonical manifest:

- platform-native artifact verification;
- updater-key binding on every candidate;
- signed install/update/restart/rollback acceptance required by the updater design;
- cross-platform native application acceptance required by the binding Tauri design;
- Electron-to-Tauri compatibility where the installed legacy population still requires it;
- state-root confinement evidence;
- parity ledger with no uncovered non-Browser behavior;
- binding Phase 0/performance decision of `continue` or `linux-canvas` for the exact release commit/artifact set;
- mobile/daemon compatibility gates required by the repository.

Evidence schemas contain source commit, canonical manifest digest, individual artifact digests, platform/architecture, producer workflow identity, result, and timestamps. Evidence from local runs, another commit, another artifact set, an E2E-driver binary, or an untrusted producer does not satisfy a stable gate.

Native signed acceptance and binding performance evidence are still tracked as deferred work because they require authorized real-platform runs. This pipeline repair consumes those records and remains safely blocked until they exist.

## Single conductor and atomic visibility

The conductor is the only job with `contents: write` and the stable publication environment. It runs trusted default-branch scripts against private artifacts and does not execute candidate applications.

It performs:

1. revalidate admission, evidence signatures/producers, and canonical inventory;
2. download every private artifact by immutable run/artifact identity;
3. recompute every digest and native/updater verification available without executing candidates;
4. create a draft GitHub release for the new immutable tag/version;
5. upload the entire allowlisted inventory, including updater and compatibility feeds;
6. query the GitHub API and verify remote asset names, counts, sizes, and downloaded digests;
7. verify release notes and channel metadata contain the same source and manifest identity;
8. switch the complete draft to public exactly once;
9. verify the public release inventory and `latest` resolution;
10. write the publication record.

The tag is not moved from an existing release. Existing assets are not overwritten. Version-free download URLs resolve through the newly published complete release rather than being independently mutated by matrix jobs.

If repository hosting cannot guarantee that draft assets and feeds become visible together, the conductor publishes a signed top-level release manifest last and clients accept a release only when that manifest references the complete immutable inventory. The current stable feed remains unchanged until that commit point.

## Failure and retry semantics

- A build, signing, verification, or evidence failure creates no GitHub release.
- A conductor failure before visibility leaves a private draft for bounded diagnosis or deletes it through an explicit safe cleanup step; current stable remains untouched.
- A remote inventory mismatch keeps the draft private.
- A publication API failure is reconciled by querying release visibility and inventory before retrying.
- If publication succeeded but final observation failed, a retry recognizes the exact already-public immutable inventory and records success; it does not republish.
- A conflicting public tag/version or digest mismatch stops for human investigation.
- There is no automatic force-delete, tag move, or replacement of public stable bytes.

## Completion and release-status records

The old port progress record is corrected to distinguish three facts:

```text
implementation sequence: ended
release readiness: blocked
binding decision: stop-port
```

It must not say or imply that all binding native, signed-update, cross-platform, and performance acceptance passed. The current `docs/STATUS.md`, benchmark decision record, port plan, and progress record cross-link to the authoritative decision and use consistent wording.

Release tooling ignores narrative “complete” text as authority. It reads a machine-validated decision/evidence record that names the exact commit and canonical artifact manifest. Only `continue` or `linux-canvas` can admit publication. Changing that record requires the evidence producer and review defined by the original Tauri port design.

An implementation-plan completion can truthfully say “release pipeline implementation complete; stable publication remains blocked by missing binding evidence.”

## Workflow policy tests

Repository tests parse stable-release workflows and fail when:

- a matrix/build/signer/test job has `contents: write`;
- more than one job can create, edit, publish, or upload to a GitHub release;
- the conductor can run without every required signer, verifier, evidence, and inventory job;
- a public non-draft release is created before remote inventory verification;
- native trust checks are warning-only or guarded by permissive inputs;
- updater signing and compiled-key proof are absent;
- `pull_request` can reach stable secrets or publication;
- mutable action tags or PR-controlled local actions run in a trusted job;
- concurrency permits two stable conductors for the same version/channel.

Fixture DAG tests cover one failed matrix leg, one missing platform artifact, wrong updater private key, wrong compiled public key, unsigned Windows binary, bad RPM signature, missing macOS zip, stale Phase 0 evidence, mismatched source commit, conductor cancellation, and idempotent observation after a successful publish.

GitHub API publication tests use a fake service and assert that no public transition occurs before the complete verified inventory.

## Expected file surface

Implementation is expected to touch:

- `.github/workflows/frontend-release.yml` and trusted reusable release workflows if split;
- release manifest, feed, native verification, and workflow-policy scripts/tests under `frontend/scripts/`;
- explicit updater-key-binding verification hooks/tests;
- evidence schemas and release documentation;
- `.superpowers/sdd/2026-08-20-tauri-port/progress.md`, `docs/STATUS.md`, and relevant benchmark/status cross-links.

It does not publish, sign with production credentials, change a release tag, or alter the current `stop-port` decision during ordinary implementation.

## Acceptance criteria

1. No platform leg can make a stable release public or mutate a stable feed.
2. Exactly one protected conductor has repository-release write authority.
3. A missing or failed platform, trust check, updater-key proof, acceptance record, or binding decision prevents draft publication.
4. Windows Authenticode and Linux package trust checks are fatal; macOS retains strict signed/notarized verification.
5. The real signed application accepts a fixture from its configured updater key and rejects an unrelated key on every supported platform/architecture.
6. The conductor publishes only a complete remotely reverified inventory and has an idempotent reconciliation path.
7. Failure before the visibility transition leaves the current public stable release and feeds unchanged.
8. Completion/status documents accurately say the implementation sequence ended while release readiness remains blocked under `stop-port`.
9. Workflow policy tests, feed/artifact tests, verification scripts, docs checks, and `git diff --check` pass.

## Out of scope

This design does not generate missing authorized Phase 0 measurements or signed native acceptance evidence, designate a human release conductor, or perform a real production publish. It makes those inputs mandatory and trustworthy when they are later supplied.
