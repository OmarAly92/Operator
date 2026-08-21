# Benchmark provenance and accounting fix report

## Outcome

Binding Electron artifact, startup, and idle-memory evidence now requires the same verified signed-artifact preflight plus a detached Ed25519 release attestation. Unattested shell runs always use `local-installed-unattested-non-binding`; `OPERATOR_BENCH_BUILD_PROFILE` cannot promote them. Artifact and binding shell results take the source commit from the signed attestation rather than the current checkout.

Idle memory now reads the daemon PID only from the isolated run file during sampling, removes that PID and all descendants from the shell/webview tree, and publishes a separate `idle-daemon-memory` result. Neither result stores a PID.

No binding benchmark result was generated. Existing releases do not provide the required release attestation inputs, so the harness refuses binding evidence for them.

## Release attestation contract

The release publisher must provide:

- `OPERATOR_BENCH_RELEASE_ATTESTATION`: a JSON file with exactly `schemaVersion`, `artifactSha256`, `applicationVersion`, `architecture`, `sourceCommit`, and `publisherIdentity`.
- `OPERATOR_BENCH_RELEASE_ATTESTATION_SIGNATURE`: a detached Ed25519 signature over the exact JSON bytes.
- `OPERATOR_BENCH_ATTESTATION_PUBLIC_KEY`: the Ed25519 public key.
- `OPERATOR_BENCH_EXPECTED_ATTESTATION_KEY_SHA256`: the trusted SHA-256 fingerprint of the public key's SPKI representation, supplied by the authorized native runner.

The harness verifies the key type and fingerprint, signature, exact schema, signed artifact SHA-256 digest, application version, runtime architecture, full source commit, and publisher identity observed from the native artifact signature. The existing trusted macOS Team ID, Windows certificate identity/thumbprint, Linux GPG fingerprint, native signature checks, installed payload binding, and exact component/runtime pins remain required. Windows and Linux installed-tree binding still fail closed.

Binding result metadata uses the attested `sourceCommit`, sets `dirty` to false for the publisher-attested release, retains `signed-release-attested`, and records only sanitized attestation metadata under `scenarioConfiguration.releaseAttestation`. No path, key material, environment value, signature bytes, PID, or credential is published.

## Files changed

- `frontend/scripts/benchmark-artifact.mjs`
  - Requires and cryptographically verifies the release attestation before measurements are returned or files are written.
  - Validates artifact digest, application version, runtime architecture, native publisher identity, and source commit.
  - Populates artifact result provenance from the attestation instead of checkout Git metadata.
- `frontend/scripts/benchmark-shell.mjs`
  - Derives binding provenance only through artifact preflight.
  - Forces arbitrary/local executables to the explicit non-binding profile regardless of requested build profile.
  - Rejects a configured executable that differs from the executable bound to verified installed-artifact inputs.
  - Splits shell/webview and daemon-subtree memory and publishes them atomically.
- `frontend/scripts/benchmark-result.mjs`
  - Requires five samples for the separate `idle-daemon-memory` scenario.
- `frontend/scripts/benchmark-result.test.mjs`
  - Adds real Ed25519 signing/verification fixtures and regression coverage for profile refusal, digest mismatch, source-commit tampering, valid attestation acceptance, and daemon-subtree exclusion.

## RED-GREEN evidence

The focused RED command was:

```text
node --test --test-name-pattern='idle-memory accounting excludes|unattested shell executables|release attestation rejects|release attestation accepts' scripts/benchmark-result.test.mjs
```

It exited 1 with four selected failures: `processTreeMemoryFromPosixTable`, `resolveShellBenchmarkProvenance`, and `validateReleaseAttestation` did not exist.

After the minimal production implementation, the same focused command exited 0 with 4/4 passing. After separating the two tamper scenarios and applying the real cryptographic preflight path, the complete benchmark suite exited 0 with 51/51 passing.

## Verification

Run from `frontend/`:

```text
node --check scripts/benchmark-result.mjs
node --check scripts/benchmark-shell.mjs
node --check scripts/benchmark-terminal.mjs
node --check scripts/benchmark-artifact.mjs
node --check scripts/benchmark-result.test.mjs
npx biome check scripts/benchmark-result.mjs scripts/benchmark-shell.mjs scripts/benchmark-artifact.mjs scripts/benchmark-result.test.mjs
node --test scripts/benchmark-result.test.mjs
npm run typecheck
npm run check:desktop-parity
```

Observed results before the final commit: all syntax and Biome checks exited 0; benchmark tests passed 51/51; TypeScript exited 0; the desktop parity ledger covered 108 entries.

## Concerns

- Release engineering must create the six-field attestation after producing each signed artifact, sign its exact bytes with the trusted Ed25519 key, and configure the public-key fingerprint on authorized native benchmark runners. Existing release artifacts without this sidecar cannot produce binding evidence.
- macOS remains the only platform with a proven signed-container-to-installed-tree binding path. Windows and Linux binding artifact and shell evidence continue to refuse until their installed payload can be cryptographically bound to the signed container.
- The packaged daemon must still report a non-`dev` semantic version equal to the installed application version before binding preflight can succeed.
