# Tauri Feature-Release Security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the credential-exposing feature-release workflow with an untrusted candidate build, trusted platform packaging, isolated updater signing, unprivileged acceptance, and one atomic publisher.

**Architecture:** A `pull_request` workflow compiles PR code with a read-only token and uploads a canonical, attested candidate archive. A default-branch `workflow_run` validates that immutable candidate, then protected platform jobs use trusted base-branch tooling to package the already-built payload without executing PR code. One separate protected job applies the production updater signature to the complete fixed inventory. Secretless acceptance jobs verify the signed outputs, and one protected publisher creates a complete draft release, remotely verifies it, and makes it public once.

**Tech Stack:** GitHub Actions, Node.js 24, Node built-in test runner, `yaml` 2.9.0, `tar` 7.5.16, Tauri CLI 2.11.4, Rust 1.96.0, Go toolchain from `backend/go.mod`, GitHub CLI attestation/release APIs, minisign-compatible Tauri updater signatures, Apple codesigning and notarization.

**Spec:** `docs/superpowers/specs/2026-08-26-tauri-feature-release-security-design.md`

## Global Constraints

- The implementation starts from `master` in an isolated worktree created with `superpowers:using-git-worktrees`.
- Treat all PR source, lockfiles, lifecycle scripts, local actions, configuration, workflow outputs, archives, and candidate bytes as malicious.
- The untrusted candidate workflow has no environment, no secret reference, no self-hosted runner, and no repository-write permission.
- `contents: read`, `id-token: write`, and `attestations: write` are the only permissions permitted in the same-repository candidate workflow. Fork permissions may be downgraded by GitHub and fork candidates remain unsigned.
- A trusted job checks out only `${{ github.sha }}`, the default-branch commit that loaded the trusted `workflow_run`; it never checks out `workflow_run.head_sha`, a PR ref, or an artifact-supplied ref.
- Trusted jobs install dependencies from the trusted checkout with `npm ci --ignore-scripts`.
- Candidate archives contain regular files and directories only. Reject absolute paths, `..`, links, devices, sockets, duplicate normalized paths, oversized entries, and undeclared roots before extraction.
- The same-repository PR must still be open, still have label `operator:feature-release`, still point at the candidate head SHA, and target `master` at trusted admission time.
- Every publishable candidate includes `darwin-aarch64`, `darwin-x86_64`, `windows-x86_64`, and `linux-x86_64`. Partial platform selection is removed because it conflicts with atomic publication.
- Only the `publish` job in the feature-release workflow has `contents: write`. Build, admission, bundling, signing, and acceptance jobs cannot create, edit, upload to, or delete a release. The separate cleanup workflow has narrowly tested deletion authority and never checks out or executes repository or PR content.
- Signing secrets exist only in `feature-sign-macos` or `feature-sign-updater`. The publisher receives no signing secret.
- Use the repository variable `OPERATOR_UPDATER_PUBLIC_KEY`; it is public verification material, not a secret. Its fingerprint must match the checked-in channel trust-policy record.
- Keep stable/nightly/feature updater-key sharing compatible with the checked-in trust policy. Do not invent a new channel key or break feature-pin updates in this plan.
- Keep `pr<N>.json` and `pr<N>*.yml`; reject `latest*` and `nightly*` output.
- Preserve the five-live-feature-release quota, seven-day expiry, one active release per PR, feature metadata marker, and existing version format `<base>-pr<N>.<UTCts>+<sha>`.
- Do not execute a candidate application, installer, package hook, script, or binary in an admission, signer, or publisher job. Only secretless acceptance jobs may execute signed candidates.
- Do not perform a real production signing or publish while implementing or testing this plan. Use ephemeral updater keys, synthetic archives, and a fake release API.
- Do not add application runtime behavior or expand the frozen npm distribution path.
- Do not add source-code comments; keep intent in names, tests, and the operator documentation.
- Do not include unrelated dirty worktree changes in any task commit.

## Required protected environments

Repository administration must configure these before the new trusted workflow can run successfully:

| Environment | Required reviewers | Secrets | Permissions used by workflow |
|---|---|---|---|
| `feature-sign-macos` | At least one release reviewer | `CSC_LINK`, `CSC_KEY_PASSWORD`, `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, `APPLE_SIGNING_IDENTITY` | `contents: read`, `actions: read` |
| `feature-sign-updater` | At least one release reviewer | `TAURI_SIGNING_PRIVATE_KEY`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | `contents: read`, `actions: read` |
| `feature-publish` | At least one release reviewer | none | `contents: write`, `actions: read` |

Environment branch policy must permit only the protected default branch. Execution must stop after the repository changes and report an operational blocker if these environment names or secrets are unavailable; it must not reuse the broad `release` environment as a shortcut.

## Approved immutable action pins

The implementation uses these reviewed commits, resolved on 2026-08-26. The workflow-policy checker rejects tags such as `@v4` and any unlisted action.

| Action | Commit |
|---|---|
| `actions/checkout` | `11d5960a326750d5838078e36cf38b85af677262` |
| `actions/setup-node` | `49933ea5288caeca8642d1e84afbd3f7d6820020` |
| `actions/setup-go` | `40f1582b2485089dde7abd97c1529aa768e1baff` |
| `actions/upload-artifact` | `ea165f8d65b6e75b540449e92b4886f43607fa02` |
| `actions/download-artifact` | `d3f86a106a0bac45b974a628896c90dbdf5c8093` |
| `actions/attest-build-provenance` | `e8998f949152b193b063cb0ec769d69d929409be` |
| `apple-actions/import-codesign-certs` | `63fff01cd422d4b7b855d40ca1e9d34d2de9427d` |

## Planned file structure

| Path | Responsibility |
|---|---|
| `.github/workflows/feature-candidate.yml` | Untrusted PR candidate compilation and provenance only. |
| `.github/workflows/feature-release.yml` | Trusted admission, platform bundling, isolated updater signing, acceptance, and single-publisher DAG. |
| `.github/workflows/feature-release-cleanup.yml` | Base-branch-only deletion of closed/expired `pr<N>` releases. |
| `.github/workflows/frontend.yml` | Required CI execution of the feature-release security tests when workflow or script boundaries change. |
| `.github/actions/macos-signing-setup/action.yml` | Trusted macOS credential import with its external action pinned by commit. |
| `frontend/scripts/feature-release/workflow-policy.mjs` | Static trust-boundary and workflow-DAG validator. |
| `frontend/scripts/feature-release/archive.mjs` | Deterministic candidate archive creation, inspection, safe extraction, and path limits. |
| `frontend/scripts/feature-release/manifest.mjs` | Canonical candidate, platform, and signed manifest schemas, hashing, identity validation, and merge rules. |
| `frontend/scripts/feature-release/candidate-cli.mjs` | Candidate workflow CLI for packing the allowlisted payload and writing a manifest. |
| `frontend/scripts/feature-release/admission.mjs` | Pure PR/run/manifest/attestation/quota admission policy. |
| `frontend/scripts/feature-release/admission-cli.mjs` | Read-only GitHub API and `gh attestation verify` adapter that writes `admission.json`. |
| `frontend/scripts/feature-release/bundle.mjs` | Stages one validated candidate and invokes trusted platform bundling without the updater private key. |
| `frontend/scripts/feature-release/updater-sign.mjs` | Dedicated updater signer for the fixed cross-platform updater artifact inventory. |
| `frontend/scripts/feature-release/acceptance.mjs` | Secretless signed-artifact, native-gate, updater-signature, and identity evidence. |
| `frontend/scripts/feature-release/publication.mjs` | Canonical publication plan, fakeable GitHub release client, remote digest verification, and idempotent draft publication. |
| `frontend/scripts/feature-release/publication-cli.mjs` | Publisher-only CLI using `gh` through fixed `execFile` argument vectors. |
| `frontend/scripts/feature-release/*.test.mjs` | Unit, adversarial, and dry-run integration coverage. |
| `frontend/scripts/feature-release/fixtures/` | Malicious workflow, manifest, archive, and publication fixtures. |
| `frontend/scripts/updater-signature.mjs` | Shared minisign-compatible updater signature verification extracted from Phase 0 tooling. |
| `frontend/docs/desktop-release.md` | New label request flow, trust boundaries, required environments, recovery, and audit evidence. |
| `docs/development.md` | Developer-facing feature-channel workflow pointer. |
| `docs/todo/tauri-port-bugs-and-deferred.md` | P0 bug closure record after all scoped gates pass. |

---

### Task 1: Contain the unsafe workflow immediately

**Files:**
- Create: `frontend/scripts/feature-release/workflow-policy.mjs`
- Create: `frontend/scripts/feature-release/workflow-policy.test.mjs`
- Modify: `frontend/package.json`
- Modify: `frontend/package-lock.json`
- Replace temporarily: `.github/workflows/feature-release.yml`
- Modify: `.github/workflows/frontend.yml`

**Interfaces:**
- Produces: `validateNoMixedTrust(workflow, path): string[]`.
- Produces: `npm run check:feature-release-policy` and `npm run test:feature-release-security`.
- The temporary workflow remains intentionally unavailable until Task 9 replaces it with the trusted DAG.

- [ ] **Step 1: Write the failing mixed-trust test**

```js
import assert from "node:assert/strict";
import test from "node:test";
import { parse } from "yaml";
import { validateNoMixedTrust } from "./workflow-policy.mjs";

test("rejects a job that checks out PR code while holding release authority", () => {
	const workflow = parse(`
permissions:
  contents: write
jobs:
  release:
    environment: release
    steps:
      - uses: actions/checkout@v4
        with:
          ref: \${{ needs.guard.outputs.headSha }}
      - run: npm ci
        env:
          KEY: \${{ secrets.TAURI_SIGNING_PRIVATE_KEY }}
`);
	assert.deepEqual(validateNoMixedTrust(workflow, "feature-release.yml"), [
		"feature-release.yml: job release combines PR-controlled execution with environment release, contents:write, secrets",
	]);
});
```

- [ ] **Step 2: Run the focused test and confirm failure**

```bash
cd frontend
node --test scripts/feature-release/workflow-policy.test.mjs
```

Expected: FAIL because `workflow-policy.mjs` does not exist.

- [ ] **Step 3: Pin the YAML parser and register the commands**

```bash
cd frontend
npm install --save-dev --save-exact yaml@2.9.0
```

Add these exact scripts to `frontend/package.json`:

```json
{
	"check:feature-release-policy": "node ./scripts/feature-release/workflow-policy.mjs ../.github/workflows",
	"test:feature-release-security": "node --test ./scripts/feature-release/*.test.mjs"
}
```

- [ ] **Step 4: Implement the minimal mixed-trust detector**

```js
function stringsBelow(value, output = []) {
	if (typeof value === "string") output.push(value);
	else if (Array.isArray(value)) value.forEach((item) => stringsBelow(item, output));
	else if (value && typeof value === "object") Object.values(value).forEach((item) => stringsBelow(item, output));
	return output;
}

export function validateNoMixedTrust(workflow, path) {
	const errors = [];
	for (const [jobName, job] of Object.entries(workflow.jobs ?? {})) {
		const text = stringsBelow(job).join("\n");
		const executesPr = /headSha|pull_request\.head|refs\/pull|npm ci|tauri:release/.test(text);
		const powers = [];
		if (job.environment) powers.push(`environment ${typeof job.environment === "string" ? job.environment : job.environment.name}`);
		if ((job.permissions?.contents ?? workflow.permissions?.contents) === "write") powers.push("contents:write");
		if (/\$\{\{\s*secrets\./.test(text)) powers.push("secrets");
		if (executesPr && powers.length > 0) errors.push(`${path}: job ${jobName} combines PR-controlled execution with ${powers.join(", ")}`);
	}
	return errors;
}
```

The CLI parses YAML with duplicate-key rejection, runs this detector over `feature-candidate.yml`, `feature-release.yml`, and `feature-release-cleanup.yml` when present, prints one error per line, and exits 1 on any error.

- [ ] **Step 5: Replace the exposed workflow with a fail-closed containment workflow**

```yaml
name: Desktop feature release

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  contained:
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "Feature releases are temporarily contained while trusted signing is deployed."
          exit 1
```

The file must contain no environment, checkout, local action, secret expression, updater key, Apple credential, release command, or write permission.

- [ ] **Step 6: Make the security suite required by frontend CI**

Add `.github/workflows/feature-*.yml` and `.github/actions/macos-signing-setup/action.yml` to `frontend.yml` path filters. Add this step after `npm ci`:

```yaml
      - name: Verify feature-release trust boundaries
        run: npm run test:feature-release-security && npm run check:feature-release-policy
```

- [ ] **Step 7: Verify and create the independently mergeable containment commit**

```bash
cd frontend
node --test scripts/feature-release/workflow-policy.test.mjs
npm run check:feature-release-policy
git diff --check
git add package.json package-lock.json scripts/feature-release/workflow-policy.mjs scripts/feature-release/workflow-policy.test.mjs ../.github/workflows/feature-release.yml ../.github/workflows/frontend.yml
git commit -m "security: contain unsafe feature release workflow"
```

Expected: tests pass, policy output is empty, and the commit contains no unrelated backend/session-manager changes.

### Task 2: Define canonical candidate archives and manifests

**Files:**
- Create: `frontend/scripts/feature-release/archive.mjs`
- Create: `frontend/scripts/feature-release/archive.test.mjs`
- Create: `frontend/scripts/feature-release/manifest.mjs`
- Create: `frontend/scripts/feature-release/manifest.test.mjs`
- Create: `frontend/scripts/feature-release/candidate-cli.mjs`
- Create: `frontend/scripts/feature-release/fixtures/manifest-path-traversal.json`
- Modify: `frontend/package.json`
- Modify: `frontend/package-lock.json`

**Interfaces:**
- Produces: `createCandidateArchive({ sourceRoot, entries, outputPath }): Promise<ArchiveRecord>`.
- Produces: `inspectCandidateArchive({ archivePath, limits }): Promise<ArchiveInventory>`.
- Produces: `extractCandidateArchive({ archivePath, destination, limits }): Promise<ArchiveInventory>`.
- Produces: `createCandidateManifest({ identity, target, toolchains, artifact }): CandidateManifest`.
- Produces: `verifyCandidateManifest({ manifest, artifactRoot, expected }): Promise<CandidateManifest>`.
- Candidate schema name: `operator.feature-candidate.v1`.

- [ ] **Step 1: Pin the archive implementation**

```bash
cd frontend
npm install --save-dev --save-exact tar@7.5.16
```

- [ ] **Step 2: Write failing archive boundary tests**

```js
test("rejects links and traversal before extraction", async () => {
	const root = await fixtureRoot();
	await symlink("../../outside", join(root, "dist", "escape"));
	await assert.rejects(
		createCandidateArchive({ sourceRoot: root, entries: ["dist"], outputPath: join(root, "candidate.tgz") }),
		/error candidate entry type: dist\/escape/,
	);
	await assert.rejects(
		extractCandidateArchive({ archivePath: traversalFixture, destination: join(root, "extract"), limits: TEST_LIMITS }),
		/candidate archive path escapes root/,
	);
});

test("creates a deterministic regular-file inventory", async () => {
	const record = await createCandidateArchive({ sourceRoot, entries: ALLOWED_ENTRIES, outputPath });
	assert.equal(record.mediaType, "application/gzip");
	assert.match(record.sha256, /^[0-9a-f]{64}$/);
	assert.deepEqual(record.roots, ["agent-browser", "daemon", "dist", "resources", "src-tauri"]);
});
```

- [ ] **Step 3: Write failing manifest validation tests**

```js
test("rejects a fork and changed artifact digest", async () => {
	const valid = candidateManifest();
	await assert.rejects(
		verifyCandidateManifest({ manifest: { ...valid, identity: { ...valid.identity, headRepository: "attacker/fork" } }, artifactRoot, expected }),
		/head repository does not match trusted repository/,
	);
	await assert.rejects(
		verifyCandidateManifest({ manifest: { ...valid, artifact: { ...valid.artifact, sha256: "0".repeat(64) } }, artifactRoot, expected }),
		/candidate artifact digest mismatch/,
	);
});
```

- [ ] **Step 4: Implement archive validation before extraction**

Use `lstat` while packing and `tar.list` while inspecting. Normalize every archive name with POSIX separators. Apply these exact limits:

```js
export const CANDIDATE_LIMITS = Object.freeze({
	maxEntries: 20000,
	maxEntryBytes: 512 * 1024 * 1024,
	maxTotalBytes: 2 * 1024 * 1024 * 1024,
});

export const CANDIDATE_ROOTS = Object.freeze([
	"agent-browser",
	"daemon",
	"dist",
	"resources/acp-runtime",
	"src-tauri/target/release/operator",
	"src-tauri/target/release/operator.exe",
]);
```

Reject NULs, backslashes inside archive names, drive prefixes, leading slash, empty segments, `.`/`..`, entries outside the allowlist, duplicates after normalization, types other than `File` and `Directory`, and totals beyond the limits. Extract only after a complete successful inspection, then walk the destination with `lstat` and recheck containment and types.

- [ ] **Step 5: Implement and freeze the candidate manifest schema**

```js
export const FEATURE_CANDIDATE_SCHEMA = "operator.feature-candidate.v1";
export const REQUIRED_TARGETS = Object.freeze([
	"darwin-aarch64",
	"darwin-x86_64",
	"linux-x86_64",
	"windows-x86_64",
]);

export const TARGETS = Object.freeze({
	"darwin-aarch64": { name: "darwin-aarch64", platform: "darwin", arch: "aarch64", runner: "macos-latest" },
	"darwin-x86_64": { name: "darwin-x86_64", platform: "darwin", arch: "x86_64", runner: "macos-15-intel" },
	"linux-x86_64": { name: "linux-x86_64", platform: "linux", arch: "x86_64", runner: "ubuntu-latest" },
	"windows-x86_64": { name: "windows-x86_64", platform: "windows", arch: "x86_64", runner: "windows-latest" },
});

export function createCandidateManifest({ identity, target, toolchains, artifact }) {
	return {
		schema: FEATURE_CANDIDATE_SCHEMA,
		identity: {
			repository: identity.repository,
			pr: Number(identity.pr),
			baseRef: identity.baseRef,
			baseSha: identity.baseSha,
			headRepository: identity.headRepository,
			headSha: identity.headSha,
			workflowRunId: String(identity.workflowRunId),
			workflowRunAttempt: Number(identity.workflowRunAttempt),
			version: identity.version,
			channel: `pr${Number(identity.pr)}`,
		},
		target,
		toolchains,
		artifact,
	};
}
```

Validation requires full 40-character lowercase SHAs, positive integer PR/run/attempt values, `baseRef === "master"`, `channel === "pr<N>"`, valid feature semver, a target object exactly equal to `TARGETS[target.name]`, a plain artifact basename, bounded size, and an on-disk SHA-256 match. Serialize with recursively sorted object keys and one trailing newline.

- [ ] **Step 6: Implement the candidate CLI**

The exact command is:

```bash
node scripts/feature-release/candidate-cli.mjs pack \
  --checkout-root . \
  --archive "$RUNNER_TEMP/operator-feature-${TARGET}.tar.gz" \
  --manifest "$RUNNER_TEMP/operator-feature-${TARGET}.json" \
  --identity-json "$RUNNER_TEMP/identity.json" \
  --target "$TARGET"
```

`candidate-cli.mjs` accepts only the `pack` subcommand and those five flags, discovers the platform-specific `operator`/`operator.exe`, requires every other candidate root, writes the archive, hashes it, writes the canonical manifest, and prints only the two output basenames and digests.

- [ ] **Step 7: Run the focused suite and commit**

```bash
cd frontend
node --test scripts/feature-release/archive.test.mjs scripts/feature-release/manifest.test.mjs
npm run test:feature-release-security
git diff --check
git add package.json package-lock.json scripts/feature-release/archive.mjs scripts/feature-release/archive.test.mjs scripts/feature-release/manifest.mjs scripts/feature-release/manifest.test.mjs scripts/feature-release/candidate-cli.mjs scripts/feature-release/fixtures
git commit -m "security: define feature candidate artifact contract"
```

### Task 3: Add the untrusted PR candidate workflow

**Files:**
- Create: `.github/workflows/feature-candidate.yml`
- Modify: `frontend/scripts/feature-release/workflow-policy.mjs`
- Modify: `frontend/scripts/feature-release/workflow-policy.test.mjs`
- Modify: `.github/workflows/frontend.yml`

**Interfaces:**
- Consumes: `candidate-cli.mjs pack`, `computeFeatureVersion`, repository variable `OPERATOR_UPDATER_PUBLIC_KEY`.
- Produces: four artifacts named `feature-candidate-<target>-<run-id>-<attempt>` containing one `.tar.gz` and one `.json`.
- Produces provenance for both files on same-repository PRs.

- [ ] **Step 1: Write failing untrusted-workflow policy tests**

```js
test("candidate workflow is untrusted and action-pinned", async () => {
	const workflow = await readWorkflow("feature-candidate.yml");
	assert.deepEqual(validateCandidateWorkflow(workflow), []);
});

test("candidate policy rejects a secret, environment, local action, mutable action, self-hosted runner, and write scope", () => {
	for (const mutation of candidateEscalationMutations()) {
		assert.ok(validateCandidateWorkflow(mutation.workflow).some((error) => error.includes(mutation.expected)));
	}
});
```

- [ ] **Step 2: Run the test and confirm failure**

```bash
cd frontend
node --test scripts/feature-release/workflow-policy.test.mjs
```

Expected: FAIL because `feature-candidate.yml` and `validateCandidateWorkflow` do not exist.

- [ ] **Step 3: Implement the candidate workflow trigger and permissions**

Use this exact outer contract:

```yaml
name: Desktop feature candidate

on:
  pull_request:
    types: [labeled, synchronize, reopened]

permissions:
  contents: read
  id-token: write
  attestations: write

jobs:
  build:
    if: contains(github.event.pull_request.labels.*.name, 'operator:feature-release')
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: macos-latest
            target: darwin-aarch64
          - os: macos-15-intel
            target: darwin-x86_64
          - os: windows-latest
            target: windows-x86_64
          - os: ubuntu-latest
            target: linux-x86_64
    runs-on: ${{ matrix.os }}
```

Do not add a protected environment or `workflow_dispatch` to this file.

- [ ] **Step 4: Implement the secretless build sequence**

All external actions use the approved commit pins. The job:

1. checks out `${{ github.event.pull_request.head.sha }}`;
2. installs Node 24, Go from `backend/go.mod`, and Rust 1.96.0;
3. runs `npm ci` in `frontend`, allowing PR lifecycle/build scripts only in this untrusted job;
4. runs `npm run build:daemon`, `npm run browser-runtime:prepare -- --quiet`, and `npm run build:acp-runtime`;
5. computes the feature version with `node scripts/feature-version.mjs` and stamps `frontend/package.json`;
6. runs `npm run tauri:release -- --no-bundle --config "$PUBLIC_KEY_OVERLAY"` so it compiles but does not package/sign;
7. writes `identity.json` from GitHub-owned event fields and fixed toolchain queries;
8. runs `candidate-cli.mjs pack`;
9. uploads the archive and manifest with seven-day retention;
10. attests both files only when `head.repo.full_name == github.repository`.

The overlay contains only the public key and no updater private material:

```bash
PUBLIC_KEY_OVERLAY="{\"plugins\":{\"updater\":{\"pubkey\":$(node -p 'JSON.stringify(process.env.OPERATOR_UPDATER_PUBLIC_KEY)')}}}"
npm run tauri:release -- --no-bundle --config "$PUBLIC_KEY_OVERLAY"
```

Pass `OPERATOR_UPDATER_PUBLIC_KEY` only from `${{ vars.OPERATOR_UPDATER_PUBLIC_KEY }}`. Never interpolate PR title, body, label text, branch name, or manifest values into a shell program.

- [ ] **Step 5: Implement exact candidate policy rules**

`validateCandidateWorkflow` requires:

- the exact trigger and label gate;
- GitHub-hosted runner literals from the four-target matrix;
- only `contents: read`, `id-token: write`, and `attestations: write`;
- no `environment`, `secrets.*`, `pull_request_target`, `workflow_run`, `workflow_dispatch`, `repository_dispatch`, local action, release/tag command, `gh release`, or updater-private-key name;
- every external `uses` reference in the approved pin table;
- attestation guarded to the same repository;
- upload retention exactly seven days.

- [ ] **Step 6: Run policy and unit tests**

```bash
cd frontend
npm run test:feature-release-security
npm run check:feature-release-policy
```

Expected: PASS. The contained `feature-release.yml` remains fail-closed; the new candidate workflow is permitted.

- [ ] **Step 7: Commit the untrusted boundary**

From the repository root:

```bash
git diff --check
git add .github/workflows/feature-candidate.yml .github/workflows/frontend.yml frontend/scripts/feature-release/workflow-policy.mjs frontend/scripts/feature-release/workflow-policy.test.mjs
git commit -m "ci: build feature candidates without release credentials"
```

### Task 4: Implement trusted admission without signing access

**Files:**
- Create: `frontend/scripts/feature-release/admission.mjs`
- Create: `frontend/scripts/feature-release/admission.test.mjs`
- Create: `frontend/scripts/feature-release/admission-cli.mjs`
- Create: `frontend/scripts/feature-release/admission-cli.test.mjs`
- Create: `frontend/scripts/feature-release/fixtures/attestation-valid.json`
- Create: `frontend/scripts/feature-release/fixtures/attestation-wrong-source.json`
- Modify: `frontend/scripts/feature-release/manifest.mjs`
- Modify: `frontend/scripts/feature-release/manifest.test.mjs`

**Interfaces:**
- Produces: `validateAdmission({ event, pullRequest, manifests, attestations, releases, trustedRepository, trustedSha }): AdmissionRecord`.
- Produces: `mergeCandidateManifests(manifests): CandidateSet`.
- Produces schema: `operator.feature-admission.v1`.
- `admission-cli.mjs` performs read-only GitHub API/attestation calls and writes `admission.json`; signer jobs consume only that file and its digest.

- [ ] **Step 1: Write failing pure admission tests**

```js
test("admits one complete current same-repository candidate set", () => {
	const record = validateAdmission(validAdmissionInput());
	assert.equal(record.schema, "operator.feature-admission.v1");
	assert.equal(record.pr, 2270);
	assert.equal(record.headSha, "a".repeat(40));
	assert.deepEqual(record.targets.map((target) => target.name), REQUIRED_TARGETS);
	assert.match(record.candidateSetDigest, /^[0-9a-f]{64}$/);
});

test("rejects fork, stale head, closed PR, missing label, missing target, failed run, and mismatched attestation", () => {
	for (const mutation of admissionRejections()) {
		assert.throws(() => validateAdmission(mutation.input), new RegExp(mutation.expected));
	}
});
```

Include separate cases for a manifest-supplied PR number that disagrees with the GitHub event, an artifact from another run attempt, a base other than `master`, more than five active releases, and an existing same-version release with a different candidate-set digest.

- [ ] **Step 2: Run the focused test**

```bash
cd frontend
node --test scripts/feature-release/admission.test.mjs
```

Expected: FAIL because the admission module does not exist.

- [ ] **Step 3: Implement candidate-set merging**

```js
export function mergeCandidateManifests(manifests) {
	const sorted = [...manifests].sort((left, right) => left.target.name.localeCompare(right.target.name));
	assertExactTargets(sorted.map((manifest) => manifest.target.name));
	const identity = canonicalJson(sorted[0].identity);
	for (const manifest of sorted.slice(1)) {
		if (canonicalJson(manifest.identity) !== identity) throw new Error("candidate manifests disagree on release identity");
	}
	return {
		identity: sorted[0].identity,
		targets: sorted.map((manifest) => ({
			name: manifest.target.name,
			artifact: manifest.artifact,
			manifestSha256: sha256(canonicalJson(manifest)),
		})),
	};
}
```

`assertExactTargets` rejects missing, extra, and duplicate targets. `canonicalJson` recursively sorts object keys; it does not preserve attacker-controlled property order.

- [ ] **Step 4: Implement the admission record**

The function verifies these GitHub-owned facts before reading manifest claims:

```js
export function assertGitHubAdmissionFacts({ event, pullRequest, trustedRepository }) {
	const run = event.workflow_run;
	if (run.name !== "Desktop feature candidate") throw new Error("unexpected candidate workflow");
	if (run.event !== "pull_request" || run.conclusion !== "success") throw new Error("candidate workflow did not complete successfully");
	if (pullRequest.state !== "open") throw new Error("pull request is not open");
	if (pullRequest.head.repo.full_name !== trustedRepository) throw new Error("fork candidates cannot enter trusted signing");
	if (pullRequest.head.sha !== run.head_sha) throw new Error("candidate head is no longer current");
	if (pullRequest.base.ref !== "master") throw new Error("candidate base branch is not master");
	if (!pullRequest.labels.some(({ name }) => name === "operator:feature-release")) throw new Error("feature release label is absent");
}
```

Then compare every manifest identity to the event, PR, run ID, run attempt, repository, head SHA, base SHA/ref, version, and channel. Require one successful attestation verification result per archive and manifest, with GitHub OIDC issuer, the Operator repository, candidate workflow identity, source digest equal to the head SHA, GitHub-hosted runner, and matching subject digest.

The returned record contains only normalized identities, digests, target names, artifact IDs, version/tag/channel, trusted default-branch SHA, quota result, and admission timestamp. It contains no title, body, branch name, token, environment, local path, or arbitrary workflow output.

- [ ] **Step 5: Implement a read-only GitHub adapter**

Use `execFile` with fixed argument arrays; do not use a shell:

```js
export async function verifyAttestation({ file, repository, headSha, execFileImpl = execFileAsync }) {
	const { stdout } = await execFileImpl("gh", [
		"attestation", "verify", file,
		"--repo", repository,
		"--signer-workflow", `${repository}/.github/workflows/feature-candidate.yml`,
		"--source-digest", headSha,
		"--deny-self-hosted-runners",
		"--format", "json",
	]);
	return JSON.parse(stdout);
}
```

The CLI reads `GITHUB_EVENT_PATH`, obtains the PR with `gh api "repos/${repository}/pulls/${pr}"` after validating `repository` and `pr`, lists releases read-only for quota/conflict checks, downloads the triggering run's four candidate artifacts by immutable run ID, validates all files, writes canonical `admission.json`, and appends only `pr`, `head_sha`, `version`, `tag`, `channel`, `candidate_set_digest`, and `trusted_sha` to `GITHUB_OUTPUT`.

- [ ] **Step 6: Test command construction and hostile API responses**

```js
test("CLI pins attestation identity and never calls a write endpoint", async () => {
	const calls = [];
	await runAdmissionCli(validCliInput({ execFileImpl: captureCalls(calls) }));
	assert.ok(calls.some((call) => call.args.includes("--deny-self-hosted-runners")));
	assert.ok(calls.every((call) => !["POST", "PATCH", "PUT", "DELETE"].includes(httpMethod(call.args))));
});
```

Also reject malformed JSON, absent `workflow_run.pull_requests`, multiple associated PRs, attestation output with an unexpected certificate identity, and release metadata with a conflicting immutable marker.

- [ ] **Step 7: Run and commit**

```bash
cd frontend
node --test scripts/feature-release/admission.test.mjs scripts/feature-release/admission-cli.test.mjs scripts/feature-release/manifest.test.mjs
npm run test:feature-release-security
git diff --check
git add scripts/feature-release/admission.mjs scripts/feature-release/admission.test.mjs scripts/feature-release/admission-cli.mjs scripts/feature-release/admission-cli.test.mjs scripts/feature-release/manifest.mjs scripts/feature-release/manifest.test.mjs scripts/feature-release/fixtures
git commit -m "security: validate feature candidates before signing"
```

### Task 5: Bundle platform candidates with trusted base-branch tooling

**Files:**
- Create: `frontend/scripts/feature-release/bundle.mjs`
- Create: `frontend/scripts/feature-release/bundle.test.mjs`
- Create: `frontend/scripts/feature-release/channel-trust.mjs`
- Create: `frontend/scripts/feature-release/channel-trust.test.mjs`
- Create: `frontend/scripts/feature-release/channel-trust.json`
- Modify: `frontend/scripts/feature-release/manifest.mjs`
- Modify: `frontend/scripts/feature-release/manifest.test.mjs`
- Modify: `.github/actions/macos-signing-setup/action.yml`

**Interfaces:**
- Produces: `stageValidatedCandidate({ archivePath, manifest, trustedFrontendRoot, stagingRoot }): Promise<StagedCandidate>`.
- Produces: `createBundleOverlay({ version, updaterPublicKey }): object`.
- Produces: `runTrustedBundle({ staged, trustedFrontendRoot, target, overlay, environment, execFileImpl }): Promise<PlatformManifest>`.
- Produces schema: `operator.feature-platform.v1`.
- Produces: `validateChannelTrust({ channel, publicKey, policy }): { keyId, fingerprint }`.

- [ ] **Step 1: Read and record the current public updater trust root**

Use the GitHub API only to read the public repository variable:

```bash
gh variable get OPERATOR_UPDATER_PUBLIC_KEY --repo OmarAly92/operator > "$RUNNER_TEMP/operator-updater-public.key"
cd frontend
node scripts/feature-release/channel-trust.mjs fingerprint \
  --public-key "$RUNNER_TEMP/operator-updater-public.key" \
  --channel feature \
  --output scripts/feature-release/channel-trust.json
```

Validate the generated file against this exact JSON-schema fragment:

```json
{
	"type": "object",
	"required": ["schema", "channels"],
	"properties": {
		"schema": { "const": "operator.feature-channel-trust.v1" },
		"channels": {
			"type": "object",
			"required": ["feature"],
			"properties": {
				"feature": {
					"type": "object",
					"required": ["keyId", "publicKeySha256"],
					"properties": {
						"keyId": { "const": "operator-updater" },
						"publicKeySha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" }
					}
				}
			}
		}
	}
}
```

The command computes the actual 64-character digest; do not type an invented key or digest. If the public variable cannot be read, stop and report the operational prerequisite instead of weakening validation.

- [ ] **Step 2: Write failing staging and execution-boundary tests**

```js
test("stages only allowlisted payload roots and never executes candidate bytes", async () => {
	const calls = [];
	const staged = await stageValidatedCandidate(validStageInput());
	await runTrustedBundle({ ...validBundleInput(staged), execFileImpl: captureCalls(calls) });
	const tauriCalls = calls.filter(({ args }) => args[0] === trustedTauriCliPath);
	assert.deepEqual(tauriCalls.map(({ args }) => args.slice(1, 3)), [
		["signer", "generate"],
		["bundle", "--ci"],
	]);
	assert.ok(calls.every((call) => !call.file.includes("candidate-stage")));
});

test("rejects the wrong public key and environment leakage", async () => {
	assert.throws(() => validateChannelTrust({ channel: "feature", publicKey: otherKey, policy }), /public key fingerprint is not allowed/);
	await assert.rejects(runTrustedBundle({ ...input, environment: { ...input.environment, AWS_SECRET_ACCESS_KEY: "x" } }), /environment key is not allowed/);
});
```

- [ ] **Step 3: Implement safe staging into a fresh trusted checkout**

Extract to a new empty directory beneath `RUNNER_TEMP`, revalidate the tree, then copy exactly:

```js
export const STAGED_PATHS = Object.freeze({
	"agent-browser": "agent-browser",
	"daemon": "daemon",
	"dist": "dist",
	"resources/acp-runtime": "resources/acp-runtime",
	"src-tauri/target/release/operator": "src-tauri/target/release/operator",
	"src-tauri/target/release/operator.exe": "src-tauri/target/release/operator.exe",
});
```

Require the correct binary suffix for the target and reject both binaries being present. Remove only the generated destination paths in the fresh CI checkout, verify each destination remains beneath `trustedFrontendRoot`, copy without following links, and compare the staged tree inventory to the archive inventory.

- [ ] **Step 4: Implement the trusted bundle overlay and command**

```js
export function createBundleOverlay({ version, updaterPublicKey }) {
	return {
		version: version.split("+")[0],
		build: { beforeBuildCommand: "", beforeBundleCommand: "", frontendDist: "../dist" },
		bundle: { createUpdaterArtifacts: true },
		plugins: { updater: { pubkey: updaterPublicKey.trim() } },
	};
}
```

Invoke the pinned trusted CLI without a shell:

```js
await execFileImpl(process.execPath, [
	tauriCliPath,
	"bundle",
	"--ci",
	"--config", "src-tauri/tauri.release.conf.json",
	"--config", JSON.stringify(overlay),
], {
	cwd: trustedFrontendRoot,
	env: pickAllowedEnvironment(environment, target),
});
```

The allowed caller-provided environment is exactly `PATH`, `CI`, `RUNNER_TEMP`, `RUSTUP_TOOLCHAIN`, and `OPERATOR_UPDATER_PUBLIC_KEY`, plus `APPLE_API_KEY`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, and `APPLE_SIGNING_IDENTITY` only for macOS. The CLI constructs a fresh object by selecting those names from `process.env`; it does not pass the runner environment through. Reject caller-provided `TAURI_SIGNING_PRIVATE_KEY` and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` explicitly.

Tauri requires a signing key while producing updater archives. `runTrustedBundle` therefore creates a random password and an ephemeral packaging key beneath a fresh `RUNNER_TEMP` directory by invoking the trusted CLI as `signer generate --ci --write-keys <path> --password <random>`. It injects that key only into the `tauri bundle` child environment, deletes the key directory in `finally`, and discards every generated `.sig` file before inventorying output. Tests prove the ephemeral public key differs from the checked-in production trust root and that no ephemeral key or signature reaches the platform artifact. The function does not invoke `npm`, Cargo, a candidate binary, an installer, or a package hook.

- [ ] **Step 5: Create and verify the platform manifest**

After `tauri bundle`, run trusted `scripts/verify-tauri-artifacts.sh --dist <bundle-output> --platform <darwin|win32|linux> --arch <arm64|x64> --expect-version <version-without-build-metadata> --mode release --strict-trust --emit-gates <gates.json>`, substituting values only from the fixed target table and validated admission record. On macOS also invoke `scripts/verify-mac-artifact.sh` separately on the generated `.app.tar.gz`, ditto-created zip, and DMG.

`createPlatformManifest` hashes an allowlisted `dist` inventory and records:

```js
const platformManifest = Object.freeze({
	schema: "operator.feature-platform.v1",
	trustedSha,
	headSha,
	pr,
	version,
	channel,
	target: candidateManifest.target,
	candidateArchiveSha256,
	candidateSetDigest,
	updaterPublicKeySha256,
	platformEnvironment,
	artifactGatesSha256,
	artifacts: [{ role, path, mediaType, size, sha256 }],
});
```

Paths are plain basenames and roles are selected from a target-specific fixed inventory. The inventory includes the unsigned updater archive required by `tauri-feed.mjs`: `.app.tar.gz` for macOS, `.exe` for Windows, and `.AppImage` for Linux. Missing, extra, or duplicate platform artifacts fail. The manifest contains no updater `.sig` and cannot claim updater signing.

- [ ] **Step 6: Pin the macOS credential-import action**

Change `.github/actions/macos-signing-setup/action.yml` to use:

```yaml
- uses: apple-actions/import-codesign-certs@63fff01cd422d4b7b855d40ca1e9d34d2de9427d
```

Update its description from Electron/Forge language to Tauri bundle signing. Do not make the composite action available to the untrusted candidate workflow.

- [ ] **Step 7: Run focused tests and commit**

```bash
cd frontend
node --test scripts/feature-release/bundle.test.mjs scripts/feature-release/channel-trust.test.mjs scripts/feature-release/manifest.test.mjs
npm run test:feature-release-security
git diff --check
git add scripts/feature-release/bundle.mjs scripts/feature-release/bundle.test.mjs scripts/feature-release/channel-trust.mjs scripts/feature-release/channel-trust.test.mjs scripts/feature-release/channel-trust.json scripts/feature-release/manifest.mjs scripts/feature-release/manifest.test.mjs ../.github/actions/macos-signing-setup/action.yml
git commit -m "security: bundle feature candidates with trusted tooling"
```

### Task 6: Sign updater artifacts in one isolated protected job

**Files:**
- Create: `frontend/scripts/updater-signature.mjs`
- Create: `frontend/scripts/updater-signature.test.mjs`
- Create: `frontend/scripts/feature-release/updater-sign.mjs`
- Create: `frontend/scripts/feature-release/updater-sign.test.mjs`
- Modify: `frontend/scripts/phase0-updater-signing.mjs`
- Modify: `frontend/scripts/phase0-updater-signing.test.mjs`
- Modify: `frontend/scripts/feature-release/manifest.mjs`
- Modify: `frontend/scripts/feature-release/manifest.test.mjs`

**Interfaces:**
- Produces: `verifyTauriUpdaterSignature({ artifactPath, signaturePath, publicKey }): Promise<true>`.
- Produces: `fingerprintUpdaterPublicKey(publicKey): string`.
- Produces: `signUpdaterSet({ admission, platformManifests, artifactRoots, outputRoot, publicKey, policy, environment, trustedFrontendRoot, execFileImpl }): Promise<SignedSet>`.
- Produces schema: `operator.feature-signed.v1`, exactly one manifest for each required target.

- [ ] **Step 1: Extract and prove the shared updater-signature verifier**

Move decoding, packet-length checks, Ed25519 key construction, artifact Blake2b digest verification, trusted-comment verification, and fingerprinting from `phase0-updater-signing.mjs` into `updater-signature.mjs`. Preserve existing Phase 0 exports by importing the shared functions; do not duplicate cryptographic parsing.

Write a real ephemeral-key test:

```js
test("accepts the configured key and rejects an unrelated key", async () => {
	const releaseKey = await ephemeralKeypair();
	const unrelatedKey = await ephemeralKeypair();
	await signFixture({ artifactPath, privateKeyPath: releaseKey.privateKeyPath });
	await assert.doesNotReject(verifyTauriUpdaterSignature({ artifactPath, signaturePath: `${artifactPath}.sig`, publicKey: releaseKey.publicKey }));
	await assert.rejects(
		verifyTauriUpdaterSignature({ artifactPath, signaturePath: `${artifactPath}.sig`, publicKey: unrelatedKey.publicKey }),
		/signature is invalid/,
	);
});
```

- [ ] **Step 2: Write failing isolated-signer tests**

```js
test("signs the fixed four-target updater inventory with the trusted CLI", async () => {
	const calls = [];
	const signedSet = await signUpdaterSet({ ...validSigningInput(), execFileImpl: captureCalls(calls) });
	assert.deepEqual(signedSet.manifests.map(({ target }) => target), REQUIRED_TARGETS);
	assert.equal(calls.length, REQUIRED_TARGETS.length);
	assert.ok(calls.every(({ file, args }) =>
		file === process.execPath &&
		args[0] === trustedTauriCliPath &&
		args[1] === "signer" &&
		args[2] === "sign"
	));
});

test("rejects missing targets and any native signing credential", async () => {
	await assert.rejects(signUpdaterSet(missingLinuxInput()), /missing platform linux-x86_64/);
	await assert.rejects(signUpdaterSet(inputWithEnvironment({ CSC_LINK: "x" })), /environment key is not allowed/);
});
```

Also fail on extra/duplicate targets, mixed PR/head/trusted SHA/version/channel/candidate-set digest, wrong platform-manifest schema, changed artifact bytes, undeclared files, an existing `.sig`, a private-key marker anywhere under the artifact roots, and a public-key fingerprint not allowed for the feature channel.

- [ ] **Step 3: Implement the fixed-inventory signing boundary**

Validate all four `operator.feature-platform.v1` manifests before accessing the key. Select exactly one updater input per target using the same rules as `tauri-feed.mjs`. Copy only those declared regular files into a fresh signing directory, re-hash them, and invoke the trusted CLI without a shell:

```js
await execFileImpl(process.execPath, [
	tauriCliPath,
	"signer",
	"sign",
	artifactPath,
], {
	cwd: trustedFrontendRoot,
	env: pickSigningEnvironment(environment),
});
```

`pickSigningEnvironment` creates a fresh object containing only `PATH`, `CI`, `RUNNER_TEMP`, `TAURI_SIGNING_PRIVATE_KEY`, and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`. Reject every other key, including all Apple, Windows, Linux, npm, GitHub, AWS, and shell-profile credentials. Verify each generated `.sig` immediately with `OPERATOR_UPDATER_PUBLIC_KEY`; this proves the protected private key matches the checked-in feature-channel trust record. The signer never runs a candidate binary, installer, package hook, `npm`, Cargo, a shell, or a release API.

- [ ] **Step 4: Emit secret-free per-target manifests**

Each signed manifest binds the platform manifest and records only public identities and digests:

```js
const signedManifest = Object.freeze({
	schema: "operator.feature-signed.v1",
	trustedSha,
	headSha,
	pr,
	version,
	channel,
	target,
	candidateSetDigest,
	platformManifestSha256,
	updaterPublicKeySha256,
	artifacts: [{ role, path, mediaType, size, sha256, signaturePath, signatureSha256 }],
});
```

Copy the declared native packages from the validated platform root unchanged into `outputRoot/<target>`, add only the verified `.sig` sidecar for its updater artifact, and compare the final inventory against the signed manifest. Return `{ manifests, targetRoots }`, where `targetRoots` maps each fixed target to that directory. Scan names and bounded file contents for private-key material before upload. No secret value, secret-derived environment dump, absolute runner path, or ephemeral platform-packaging signature may appear in output.

- [ ] **Step 5: Run the real crypto and signer suites**

```bash
cd frontend
node --test scripts/updater-signature.test.mjs scripts/phase0-updater-signing.test.mjs scripts/feature-release/updater-sign.test.mjs scripts/feature-release/manifest.test.mjs
npm run test:feature-release-security
git diff --check
```

Expected: Phase 0 remains compatible, all four synthetic updater artifacts are signed with one ephemeral release key, the configured public key accepts every signature, an unrelated key rejects every signature, and no test uses a production key.

- [ ] **Step 6: Commit**

```bash
git add frontend/scripts/updater-signature.mjs frontend/scripts/updater-signature.test.mjs frontend/scripts/phase0-updater-signing.mjs frontend/scripts/phase0-updater-signing.test.mjs frontend/scripts/feature-release/updater-sign.mjs frontend/scripts/feature-release/updater-sign.test.mjs frontend/scripts/feature-release/manifest.mjs frontend/scripts/feature-release/manifest.test.mjs
git commit -m "security: isolate feature updater signing"
```

### Task 7: Produce secretless signed-artifact acceptance evidence

**Files:**
- Create: `frontend/scripts/feature-release/acceptance.mjs`
- Create: `frontend/scripts/feature-release/acceptance.test.mjs`

**Interfaces:**
- Produces: `createAcceptanceRecord({ admission, signedManifest, artifactRoot, publicKey, nativeVerification }): Promise<AcceptanceRecord>`.
- Produces schema: `operator.feature-acceptance.v1`.

- [ ] **Step 1: Write failing acceptance-record tests**

```js
test("acceptance binds one signed target to admission, native gates, and updater trust", async () => {
	const input = validAcceptanceInput();
	const record = await createAcceptanceRecord(input);
	assert.equal(record.schema, "operator.feature-acceptance.v1");
	assert.equal(record.candidateSetDigest, input.admission.candidateSetDigest);
	assert.equal(record.updaterKeyAccepted, true);
	assert.equal(record.unrelatedKeyRejected, true);
	assert.deepEqual(record.nativeGateFailures, []);
});
```

Reject a changed artifact after signing, wrong target/version/channel/head/trusted SHA, warning-only failed native gate, missing `.sig`, public-key fingerprint mismatch, private-key marker, and acceptance generated on a different artifact inventory.

- [ ] **Step 2: Implement acceptance without secret access**

For every updater artifact selected by `tauri-feed.mjs`, require the adjacent `.sig` and verify it with the configured public key. Generate an ephemeral unrelated keypair beneath a fresh test directory, prove the release signature fails under that public key, and remove the entire key directory in `finally`.

Re-run target-native verification in the acceptance runner. The record contains only digests, public certificate/key identifiers, gate names/results, platform metadata, source identities, and timestamps. It never contains a private key, token, full runner path, or artifact contents.

- [ ] **Step 3: Verify both the shared crypto path and acceptance**

```bash
cd frontend
node --test scripts/updater-signature.test.mjs scripts/phase0-updater-signing.test.mjs scripts/feature-release/acceptance.test.mjs
npm run test:feature-release-security
```

Expected: the existing Phase 0 signing flow still passes, a real ephemeral signature is accepted by the right key, and the unrelated key is rejected.

- [ ] **Step 4: Commit**

From the repository root:

```bash
git diff --check
git add frontend/scripts/feature-release/acceptance.mjs frontend/scripts/feature-release/acceptance.test.mjs
git commit -m "test: prove feature artifact signing without secrets"
```

### Task 8: Implement an atomic, idempotent feature publisher

**Files:**
- Create: `frontend/scripts/feature-release/publication.mjs`
- Create: `frontend/scripts/feature-release/publication.test.mjs`
- Create: `frontend/scripts/feature-release/publication-cli.mjs`
- Create: `frontend/scripts/feature-release/publication-cli.test.mjs`

**Interfaces:**
- Produces: `createPublicationPlan({ admission, signedManifests, acceptanceRecords, feedArtifacts, pullRequestTitle }): PublicationPlan`.
- Produces: `publishFeatureRelease({ plan, artifactRoot, client }): Promise<PublicationResult>`.
- Produces: `createGhReleaseClient({ repository, token, execFileImpl }): ReleaseClient`.
- Publication schema: `operator.feature-publication.v1`.
- Release client methods: `findByTag`, `listFeatureReleases`, `createDraft`, `uploadAsset`, `listAssets`, `downloadAsset`, `publishDraft`, `getRelease`, and `deleteFeatureRelease`.

- [ ] **Step 1: Write failing publication-plan tests**

```js
test("requires one accepted signed manifest for every target", () => {
	assert.throws(
		() => createPublicationPlan({ ...validPlanInput(), acceptanceRecords: validPlanInput().acceptanceRecords.slice(1) }),
		/missing accepted target darwin-aarch64/,
	);
});

test("rejects stable or nightly feed names", () => {
	assert.throws(
		() => createPublicationPlan({ ...validPlanInput(), feedArtifacts: [{ path: "latest.json" }] }),
		/forbidden feature feed name/,
	);
});
```

Also reject mixed trusted/head SHAs, candidate-set digests, PRs, versions, channels, updater keys, duplicate asset names, missing compatibility feeds, missing permanent macOS zip/DMG, private-key markers, and extra undeclared assets.

- [ ] **Step 2: Implement deterministic publication planning**

Derive `baseVersion` with the existing `parseFeatureBuild(version).base` and reject a null parse or a PR mismatch. The plan contains:

```js
const publicationPlan = Object.freeze({
	schema: "operator.feature-publication.v1",
	repository,
	pr,
	headSha,
	trustedSha,
	version,
	baseVersion,
	tag,
	channel,
	candidateSetDigest,
	inventoryDigest,
	title,
	body,
	assets: [{ role, name, size, sha256, sourceArtifact }],
	acceptanceDigests,
});
```

Before hashing the final inventory, generate `feature-release-audit.json` from the admission digest, signed-manifest digests, acceptance digests, updater public-key identifier, source/trusted SHAs, and expected asset inventory. Include that report as a release asset so the trusted run's non-secret audit record is attached before visibility.

Sort assets by name and compute `inventoryDigest` from canonical JSON. Generate exactly one machine marker with code, never shell interpolation:

```js
const marker = `<!-- opr-feature-build: ${JSON.stringify({
	pr,
	base: baseVersion,
	sha: headSha.slice(0, 7),
	slug: "",
	candidateSetDigest,
	inventoryDigest,
})} -->`;
```

The title is `[feature] PR #<N>` plus a sanitized title fetched again by the trusted publisher. The title is passed as one API argument and never interpreted by a shell.

- [ ] **Step 3: Write failing transactional publisher tests**

```js
test("never makes a partial release public", async () => {
	const client = fakeReleaseClient({ failUploadAt: 3 });
	await assert.rejects(publishFeatureRelease({ plan, artifactRoot, client }), /upload failed/);
	assert.equal(client.release.draft, true);
	assert.equal(client.calls.some((call) => call.method === "publishDraft"), false);
});

test("reconciles an already-published identical inventory", async () => {
	const client = fakeReleaseClient({ existingPublicPlan: plan });
	const result = await publishFeatureRelease({ plan, artifactRoot, client });
	assert.equal(result.status, "already_published");
	assert.equal(client.uploadCount, 0);
});
```

Cover remote size/digest mismatch, conflicting tag, conflicting marker, cancelled upload, feed-generation failure, draft reuse with exact inventory, more than five projected live feature releases, two live releases for another PR, and failure while observing a publication that actually succeeded.

- [ ] **Step 4: Implement the visibility transaction**

`publishFeatureRelease` performs exactly:

1. hash every local asset and compare to the plan;
2. query the tag;
3. return `already_published` only for an exact public inventory/marker match;
4. fail on any conflicting public release;
5. list all feature releases, fail on malformed/conflicting markers, and prove the projected post-retirement live count is at most five with one release for this PR;
6. create or reconcile one private draft;
7. upload the complete allowlisted inventory without clobbering;
8. list remote assets and compare name/count/size;
9. download every remote asset to a fresh verification directory and recompute SHA-256;
10. repeat the live-release/quota query immediately before visibility;
11. call `publishDraft` once;
12. fetch the public release and verify the marker/inventory again;
13. write `publication-record.json` atomically for workflow retention;
14. delete older prereleases for the same PR only when their tag and parsed marker both match that PR.

No failure handler deletes or moves an existing public tag. A private conflicting draft remains private and returns a stable error for manual inspection. If the new release is public but retiring an older matching feature release fails, return `published_cleanup_pending`; the scheduled cleanup retries it without changing the new release.

- [ ] **Step 5: Implement the shell-free GitHub client**

```js
function createGhReleaseClient({ repository, token, execFileImpl = execFileAsync }) {
	async function gh(args) {
		const { stdout } = await execFileImpl("gh", args, {
			env: { PATH: process.env.PATH, GH_TOKEN: token },
			maxBuffer: 16 * 1024 * 1024,
		});
		return stdout;
	}
	return releaseClientFromGh({ repository, gh });
}
```

Create the draft with `gh release create <tag> --draft --prerelease --latest=false --target <head-sha> --title <title> --notes-file <file> --repo <repository>`. Upload each asset separately with `gh release upload <tag> <file> --repo <repository>` and never pass `--clobber`. Use `gh api --method PATCH repos/<repository>/releases/<id> -F draft=false -F prerelease=true` only for the visibility transition. Use `gh release delete <tag> --cleanup-tag --yes --repo <repository>` only for older releases already proven to match the same PR marker. Every argument is a separate `execFile` array element; never build a command string. The client accepts only a repository matching `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$` and a tag/version already validated by the plan.

- [ ] **Step 6: Run tests and commit**

```bash
cd frontend
node --test scripts/feature-release/publication.test.mjs scripts/feature-release/publication-cli.test.mjs
npm run test:feature-release-security
git diff --check
git add scripts/feature-release/publication.mjs scripts/feature-release/publication.test.mjs scripts/feature-release/publication-cli.mjs scripts/feature-release/publication-cli.test.mjs
git commit -m "security: publish complete feature releases atomically"
```

### Task 9: Replace containment with the trusted release DAG

**Files:**
- Replace: `.github/workflows/feature-release.yml`
- Modify: `frontend/scripts/feature-release/workflow-policy.mjs`
- Modify: `frontend/scripts/feature-release/workflow-policy.test.mjs`
- Modify: `.github/workflows/frontend.yml`

**Interfaces:**
- Consumes: the completed workflow named `Desktop feature candidate`.
- Produces jobs: `admit`, four `bundle-*` jobs, `sign-updater`, four `accept-*` jobs, and `publish`.
- Produces private Actions artifacts for admission, platform packages, updater-signed targets, acceptance records, and publication records.
- The only public state transition is `publish` under `feature-publish`.

- [ ] **Step 1: Write failing final-DAG policy tests**

```js
test("trusted release workflow has one publisher and no PR checkout", async () => {
	const workflow = await readWorkflow("feature-release.yml");
	assert.deepEqual(validateTrustedReleaseWorkflow(workflow), []);
});

test("publisher depends on every privileged producer and acceptance gate", async () => {
	const workflow = await readWorkflow("feature-release.yml");
	const needs = new Set(arrayify(workflow.jobs.publish.needs));
	assert.deepEqual(needs, new Set([
		"admit",
		"bundle-darwin-aarch64", "bundle-darwin-x86_64", "bundle-windows-x86_64", "bundle-linux-x86_64",
		"sign-updater",
		"accept-darwin-aarch64", "accept-darwin-x86_64", "accept-windows-x86_64", "accept-linux-x86_64",
	]));
});
```

Mutations must fail when a bundler or updater signer gains `contents: write`, a candidate head is checked out, a trusted job runs `npm ci` without `--ignore-scripts`, an updater key reaches a platform bundler, Apple credentials reach a non-macOS job, acceptance gains a secret/environment, publisher loses one dependency, two jobs invoke release mutation, an action uses a tag, or `always()` allows publication after a failed dependency.

- [ ] **Step 2: Define the trusted workflow boundary**

Use this exact outer contract:

```yaml
name: Desktop feature release

on:
  workflow_run:
    workflows: [Desktop feature candidate]
    types: [completed]

permissions:
  contents: read
  actions: read

concurrency:
  group: feature-release-pr-${{ github.event.workflow_run.pull_requests[0].number || github.event.workflow_run.id }}
  cancel-in-progress: false
```

Do not add `pull_request`, `pull_request_target`, `workflow_call`, `repository_dispatch`, or a permissive `workflow_dispatch` path.

- [ ] **Step 3: Implement `admit` with no protected environment**

The job checks out only `${{ github.sha }}` with pinned `actions/checkout`, sets up Node 24, runs `npm ci --ignore-scripts`, and invokes:

```bash
node scripts/feature-release/admission-cli.mjs \
  --event "$GITHUB_EVENT_PATH" \
  --repository "$GITHUB_REPOSITORY" \
  --trusted-sha "$GITHUB_SHA" \
  --work-dir "$RUNNER_TEMP/feature-admission" \
  --output "$RUNNER_TEMP/feature-admission/admission.json" \
  --github-output "$GITHUB_OUTPUT"
```

Pass `GH_TOKEN: ${{ github.token }}` at step scope. Upload `admission.json` with pinned `actions/upload-artifact`, name `feature-admission-${{ github.event.workflow_run.id }}`, retention seven days. The job has no environment, no `secrets.*`, and no write permission.

- [ ] **Step 4: Implement four explicit platform-bundling jobs**

Use job IDs and environments:

| Job | Runner | Environment | Target |
|---|---|---|---|
| `bundle-darwin-aarch64` | `macos-latest` | `feature-sign-macos` | `darwin-aarch64` |
| `bundle-darwin-x86_64` | `macos-15-intel` | `feature-sign-macos` | `darwin-x86_64` |
| `bundle-windows-x86_64` | `windows-latest` | none | `windows-x86_64` |
| `bundle-linux-x86_64` | `ubuntu-latest` | none | `linux-x86_64` |

Every bundler:

1. `needs: admit`;
2. has `contents: read` and `actions: read` only;
3. checks out `${{ github.sha }}` using the approved checkout commit;
4. installs Node 24 and `npm ci --ignore-scripts` from the trusted checkout;
5. installs Go/Rust/platform packaging prerequisites from fixed trusted workflow steps;
6. downloads the exact candidate artifact from `${{ github.event.workflow_run.id }}` and exact admission artifact from the current run;
7. revalidates manifest, archive, attestation identity, candidate-set digest, and admission digest;
8. calls `bundle.mjs` for its fixed target;
9. uploads unsigned-updater platform artifacts, gates, and `operator.feature-platform.v1` manifest as `feature-platform-<target>-<candidate-set-digest>`;
10. removes imported keychains/key files in `if: always()` cleanup.

macOS bundlers call only the trusted local action from the `${{ github.sha }}` checkout and use the `feature-sign-macos` credentials for Apple signing/notarization. Windows/Linux bundlers receive no protected environment or signing secret; the existing feature channel has no Windows/Linux native-signing identity. They still run strict package and architecture gates, while adding new native identities remains owned by the later trusted-release implementation. No bundler receives the updater key or a `GH_TOKEN` beyond the read-only token required for cross-run artifact download.

- [ ] **Step 5: Implement the single isolated updater signer**

`sign-updater`:

- needs `admit` and all four `bundle-*` jobs;
- runs on `ubuntu-latest` because Tauri `signer sign` signs arbitrary bytes without executing or packaging them;
- uses `environment: feature-sign-updater`;
- has `contents: read`, `actions: read`, no release mutation, and only the two updater secrets;
- checks out `${{ github.sha }}`, runs `npm ci --ignore-scripts`, and downloads exact admission/platform artifacts from the current run;
- invokes `updater-sign.mjs` once across the fixed four-target inventory;
- uploads one private artifact per target as `feature-signed-<target>-<candidate-set-digest>`, each containing native packages, its updater signature, and `operator.feature-signed.v1`;
- removes the signing workspace in `if: always()` cleanup.

The job never imports Apple credentials, calls a platform packager, executes candidate bytes, or calls GitHub release APIs.

- [ ] **Step 6: Implement four secretless acceptance jobs**

Each `accept-<target>`:

- needs `sign-updater` and `admit`;
- runs on the same native platform class;
- has `contents: read`, `actions: read`, no environment, and no secret expression;
- checks out `${{ github.sha }}` and uses `npm ci --ignore-scripts`;
- downloads admission and its exact signed artifact;
- calls `acceptance.mjs` with the repository public key variable;
- uploads `acceptance.json` as `feature-acceptance-<target>-<candidate-set-digest>`.

The job must not import signing credentials. This plan's acceptance is deliberately limited to signed-artifact, updater-signature, and native-gate verification; packaged update execution is owned by the updater-stability spec.

- [ ] **Step 7: Implement the single publisher**

The `publish` job:

- directly needs `admit`, all four platform bundlers, `sign-updater`, and all four acceptance jobs;
- has no `if: always()`;
- has job-level `concurrency: { group: feature-release-publisher, cancel-in-progress: false }` so quota and one-live-release decisions cannot race across PRs;
- uses `environment: feature-publish`;
- has `contents: write` and `actions: read` only;
- checks out `${{ github.sha }}` and runs `npm ci --ignore-scripts`;
- downloads admission, all signed artifacts, and all acceptance records from the current run;
- recomputes all digests and runs `tauri-feed.mjs` from the trusted checkout for `pr<N>`;
- runs `publication-cli.mjs plan`, validates the plan, then runs `publication-cli.mjs publish`;
- uploads the non-secret publication record to the workflow run after success.

No other job contains `gh release`, release API mutation, `contents: write`, `feature-publish`, or a GitHub token with write authority.

- [ ] **Step 8: Complete exact workflow-policy validation**

`validateTrustedReleaseWorkflow` enforces:

- exact `workflow_run` producer and `completed` type;
- `cancel-in-progress: false`;
- exact job IDs, runners, environments, permissions, and `needs` graph;
- the publisher's global non-cancelling concurrency group;
- checkout ref `${{ github.sha }}` in every trusted job;
- `npm ci --ignore-scripts` in every trusted job;
- no PR head/ref string, candidate execution, local action outside macOS bundlers, or unpinned external action;
- no secret in admission, acceptance, or publisher;
- Apple secret names limited to the two macOS bundlers and updater secret names limited to `sign-updater`;
- only publisher has release mutation text and `contents: write`;
- all private artifacts have seven-day retention and collision-resistant names containing immutable identities.

- [ ] **Step 9: Verify actual workflow files**

```bash
cd frontend
node --test scripts/feature-release/workflow-policy.test.mjs
npm run check:feature-release-policy
npm run test:feature-release-security
```

Expected: both actual workflows pass; every malicious mutation fails with the expected policy error.

- [ ] **Step 10: Commit the trusted workflow DAG**

From the repository root:

```bash
git diff --check
git add .github/workflows/feature-release.yml .github/workflows/frontend.yml frontend/scripts/feature-release/workflow-policy.mjs frontend/scripts/feature-release/workflow-policy.test.mjs
git commit -m "ci: separate trusted feature signing and publication"
```

### Task 10: Harden retirement and update operator documentation

**Files:**
- Modify: `.github/workflows/feature-release-cleanup.yml`
- Modify: `frontend/scripts/feature-release/workflow-policy.mjs`
- Modify: `frontend/scripts/feature-release/workflow-policy.test.mjs`
- Modify: `frontend/docs/desktop-release.md`
- Modify: `docs/development.md`

**Interfaces:**
- Cleanup may delete only feature prereleases matching both the `pr<N>` tag pattern and Operator metadata marker.
- Documentation makes label request, trust separation, protected environments, private staging, failure recovery, quota, and expiry authoritative.

- [ ] **Step 1: Write failing cleanup-policy tests**

```js
test("cleanup is base-branch controlled and never executes PR content", async () => {
	const workflow = await readWorkflow("feature-release-cleanup.yml");
	assert.deepEqual(validateFeatureCleanupWorkflow(workflow), []);
});

test("cleanup policy rejects pull_request with write permission", async () => {
	const workflow = await readWorkflow("feature-release-cleanup.yml");
	workflow.on = { pull_request: { types: ["closed"] } };
	assert.match(validateFeatureCleanupWorkflow(workflow).join("\n"), /must use pull_request_target for base-branch workflow code/);
});
```

- [ ] **Step 2: Move immediate cleanup to the base-branch event boundary**

Use:

```yaml
on:
  pull_request_target:
    types: [closed]
  schedule:
    - cron: "0 12 * * *"
```

The close job reads only `github.event.pull_request.number`. It never checks out code, invokes a local action, reads PR title/body/branch, executes an artifact, or accepts an override. Both cleanup jobs may have `contents: write`, but their commands can only delete tags matching `^v.*-pr[0-9]+\.` whose prerelease body contains the exact `opr-feature-build` marker with the same PR.

Do not use the previous behavior that deletes on tag pattern alone when the marker is absent. Unknown releases survive and produce a warning for manual inspection.

- [ ] **Step 3: Make cleanup failure explicit**

Remove `|| true` from release deletion. Paginate GitHub API results, validate every returned tag again before deletion, and print only tag/PR/published timestamp. A failed deletion fails the job; it does not broaden the match or touch stable/nightly releases.

- [ ] **Step 4: Rewrite the feature-release runbook**

Replace the old `workflow_dispatch`, `platforms`, `slug`, `allow_fork`, and “approver inspects PR before exposing secrets” instructions with:

1. a maintainer adds `operator:feature-release` to an open same-repository PR;
2. `Desktop feature candidate` builds four unsigned candidates with no secrets;
3. protected macOS bundlers and the isolated updater signer revalidate the exact head and require their scoped environment approvals;
4. secretless native jobs verify the updater-signed artifacts;
5. one protected publisher exposes a complete prerelease;
6. removing the label stops future candidates; closing the PR or seven-day expiry retires its releases.

Document the three environment names and exact secret placement from this plan. Explain that fork builds may compile unsigned but admission rejects them, and that partial-platform feature releases are no longer supported.

Document recovery:

- failed candidate: fix/re-run PR at a new head;
- rejected admission: restore same-repository/open/current-head/label conditions;
- bundler/signer/acceptance failure: rerun the failed trusted job after diagnosis without publishing;
- publisher failure before visibility: inspect/reconcile the private draft with the same inventory digest;
- conflicting public tag: stop for release-conductor review; never clobber.

- [ ] **Step 5: Update the development pointer**

Keep the channel description in `docs/development.md`, but link release operators to the updated runbook and state that only signed same-repository candidates can appear in `pr<N>` feeds.

- [ ] **Step 6: Verify docs and cleanup policy, then commit**

```bash
cd frontend
node --test scripts/feature-release/workflow-policy.test.mjs
npm run check:feature-release-policy
rg -n "allow_fork|platforms.*mac,win,linux|Actions > Desktop feature release > Run workflow" docs/desktop-release.md ../docs/development.md
git diff --check
```

Expected: policy passes and `rg` prints no stale operator instruction.

From the repository root:

```bash
git add .github/workflows/feature-release-cleanup.yml frontend/scripts/feature-release/workflow-policy.mjs frontend/scripts/feature-release/workflow-policy.test.mjs frontend/docs/desktop-release.md docs/development.md
git commit -m "docs: explain trusted feature release flow"
```

### Task 11: Run the adversarial dry run and close the P0 audit entry

**Files:**
- Create: `frontend/scripts/feature-release/security-integration.test.mjs`
- Create: `frontend/scripts/feature-release/fixtures/workflow-mixed-trust.yml`
- Create: `frontend/scripts/feature-release/fixtures/workflow-fork-override.yml`
- Create: `frontend/scripts/feature-release/fixtures/workflow-local-action.yml`
- Modify: `docs/todo/tauri-port-bugs-and-deferred.md`

**Interfaces:**
- The integration test runs candidate archive → manifest → admission → trusted staging/bundle adapter → isolated ephemeral updater signing → acceptance → fake draft publication without GitHub writes or production credentials.
- The audit entry is checked only after every command below passes.

- [ ] **Step 1: Write the end-to-end synthetic success test**

```js
test("same-repository candidate reaches one atomic publication", async () => {
	const candidate = await createSyntheticCandidate({ pr: 2270, targets: REQUIRED_TARGETS });
	const admission = validateAdmission(await syntheticAdmissionInput(candidate));
	const platforms = await createSyntheticPlatformSet({ candidate, admission });
	const releaseKey = await ephemeralKeypair();
	const signedSet = await signUpdaterSet({
		admission,
		platformManifests: platforms.manifests,
		artifactRoots: platforms.targetRoots,
		outputRoot: candidate.signedRoot,
		publicKey: releaseKey.publicKey,
		policy: featurePolicyFor(releaseKey.publicKey),
		environment: signingEnvironmentFor(releaseKey),
		trustedFrontendRoot,
		execFileImpl,
	});
	const accepted = await Promise.all(signedSet.manifests.map((signedManifest) => createAcceptanceRecord({
		admission,
		signedManifest,
		artifactRoot: signedSet.targetRoots.get(signedManifest.target),
		publicKey: releaseKey.publicKey,
		nativeVerification: platforms.nativeVerificationByTarget.get(signedManifest.target),
	})));
	const plan = createPublicationPlan({
		admission,
		signedManifests: signedSet.manifests,
		acceptanceRecords: accepted,
		feedArtifacts: featureFeeds(2270),
		pullRequestTitle: "Harden feature release",
	});
	const client = fakeReleaseClient();
	const result = await publishFeatureRelease({ plan, artifactRoot: candidate.root, client });
	assert.equal(result.status, "published");
	assert.equal(client.publicTransitions, 1);
	assert.equal(client.release.assets.length, plan.assets.length);
});
```

The synthetic platform adapter copies bytes and emits structurally valid test gates; it must be named as fake native evidence and can never satisfy a real workflow record. The updater signatures are real Tauri signatures made with a temporary key that is deleted in test cleanup.

- [ ] **Step 2: Add the full malicious fixture wave**

Assert rejection for:

- dependency/local-action workflow replacement plus secret/write authority;
- fork admission even when manifest says the canonical repository;
- mutable external action tag;
- candidate archive absolute path, traversal, duplicate normalization, symlink, device, socket, oversized entry, and undeclared root;
- manifest output injection, inconsistent PR/head/run/target/version, digest change, and extra artifact;
- attestation from another repository/workflow/source digest/self-hosted runner;
- trusted job PR checkout or candidate command execution;
- wrong updater public key and leaked private-key marker;
- missing platform/signer/acceptance target;
- stable/nightly feed name;
- partial upload, remote digest mismatch, conflicting tag, and repeated publication.

Every fixture test asserts the stable error substring and that `publicTransitions === 0` on failure.

Generate malicious tar archives inside the test's fresh temporary directory with the pinned `tar` library using test-only `preservePaths` and symlink inputs. Do not commit opaque binary archive fixtures.

- [ ] **Step 3: Run all focused tests**

```bash
cd frontend
npm run test:feature-release-security
npm run check:feature-release-policy
node --test scripts/updater-signature.test.mjs scripts/phase0-updater-signing.test.mjs
node --test scripts/tauri-feed.test.mjs scripts/feed.test.mjs
```

Expected: all pass with no production secret and no network write.

- [ ] **Step 4: Run repository-level verification**

```bash
cd frontend
npm run typecheck
npm run check:desktop-parity
cd ..
npm run lint
npx @redwoodjs/agent-ci run --all
git diff --check
```

Expected: all required local/CI-equivalent checks pass. If Docker is unavailable for the local workflow runner, record that exact environment limitation and require GitHub CI before merge; do not describe the workflow as verified by that unavailable command.

- [ ] **Step 5: Inspect the workflow trust boundary manually**

```bash
rg -n "secrets\.|contents: write|environment:|actions/checkout|npm ci|tauri:release|tauri bundle|gh release|pull_request_target|allow_fork" .github/workflows/feature-candidate.yml .github/workflows/feature-release.yml .github/workflows/feature-release-cleanup.yml .github/actions/macos-signing-setup/action.yml
```

Confirm from the output:

- candidate has no secrets/environment/write/release mutation;
- admission has no secrets/environment/write;
- macOS bundlers and the updater signer have only their scoped protected environments and no write;
- Windows/Linux bundlers have no environment or secret;
- acceptance has no secrets/environment/write;
- publisher alone has `feature-publish` and `contents: write`;
- cleanup uses `pull_request_target` without checkout and only deletion authority;
- no external action reference uses a tag.

- [ ] **Step 6: Obtain two-stage review**

Use `superpowers:requesting-code-review` for:

1. specification compliance against `2026-08-26-tauri-feature-release-security-design.md`;
2. security/code/test quality over the complete branch diff.

Fix every Critical or Important finding, rerun the focused and repository-level verification, and repeat the scoped review for the fix wave.

- [ ] **Step 7: Mark only the P0 bug fixed**

Change the P0 entry in `docs/todo/tauri-port-bugs-and-deferred.md` to checked and append a concise closure statement naming:

- `feature-candidate.yml` untrusted boundary;
- `feature-release.yml` trusted workflow-run admission and single publisher;
- workflow-policy and adversarial integration suites;
- the four target records and environment contract;
- the date 2026-08-26.

Do not check any updater, renderer, CI/confinement/parity, or stable-release bug from the other four specs.

- [ ] **Step 8: Commit the final evidence and audit update**

From the repository root:

```bash
git add frontend/scripts/feature-release/security-integration.test.mjs frontend/scripts/feature-release/fixtures docs/todo/tauri-port-bugs-and-deferred.md
git commit -m "test: prove feature release trust separation"
git status --short
git log --oneline --decorate -12
```

Expected: only intentional pre-existing user changes remain unstaged, and the branch contains eleven reviewable commits or fewer if a reviewer explicitly approved folding a fix into its owning task.

## Spec coverage map

| Specification requirement | Plan owner |
|---|---|
| Immediate credential/write containment | Task 1 |
| Canonical manifest, safe paths, link/type/size rejection | Task 2 |
| Untrusted exact-head build, read-only token, no environment/secrets, immutable action pins | Tasks 1 and 3 |
| Same-repository/open/current-head/base/label admission and fork rejection | Task 4 |
| Artifact attestation and immutable run/digest binding | Tasks 3 and 4 |
| Trusted base-branch tooling and no candidate execution in a privileged job | Tasks 5 and 6 |
| Scoped platform environments, isolated updater signing, and updater-key trust policy | Tasks 5, 6, and 9 |
| Secretless signature/native acceptance evidence | Task 7 |
| Fixed inventory, `pr<N>` feed isolation, private staging, remote verification, idempotency | Task 8 |
| One `contents: write` publisher after every bundler, signer, and acceptance gate | Task 9 |
| Cleanup, quota, expiry, one-live-release behavior | Tasks 4 and 10 |
| Workflow-policy attack classes and malicious fixtures | Tasks 1, 3, 9, and 11 |
| Audit record, runbook, failure/recovery behavior | Tasks 8, 10, and 11 |
| No public partial release on failure | Tasks 8, 9, and 11 |

## Completion boundary

This plan is complete when the P0 feature-release audit entry is checked with passing evidence and no feature release can expose PR code to signing/repository-write authority. Completion does not authorize a production publish and does not close the stable-release, updater, renderer/native, or CI/confinement/parity bugs owned by the other stabilization specs.
