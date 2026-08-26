# Tauri feature-release security — design

**Date:** 2026-08-26
**Status:** approved design
**Program:** `docs/superpowers/specs/2026-08-26-tauri-stabilization-program-design.md`
**Owns:** the P0 feature-release credential and repository-write exposure.

## Outcome

Feature builds remain available for trusted same-repository pull requests, but PR-controlled source, dependencies, scripts, actions, and artifacts never execute with signing identities, a protected release environment, or repository-write credentials.

Fork pull requests may receive an unsigned CI build if existing repository policy permits it. They cannot receive an Operator-signed or published feature release.

## Threat model

The untrusted input is everything mutable by a pull request:

- source files and build configuration;
- dependency manifests, lockfiles, lifecycle scripts, build scripts, and generated code;
- local actions checked out from the PR;
- Tauri configuration and bundle hooks;
- artifact names, manifests, symlinks, archives, and nested paths;
- workflow outputs derived by PR code;
- pull-request labels, title, body, and branch name.

The protected assets are:

- Apple signing certificates, keychain passwords, notarization credentials, and team identity;
- updater private signing keys and passwords;
- Windows code-signing identities;
- Linux package-signing identities;
- tokens with release, contents-write, actions-write, or environment access;
- the GitHub release namespace, feature feeds, and version-free aliases;
- trusted workflow scripts and policy definitions from the base branch.

The design assumes malicious PR code can fully control every byte produced by the untrusted build. Artifact attestation proves which untrusted job produced bytes; it does not make those bytes safe to execute.

## Security invariants

1. An untrusted job has `contents: read` at most and no protected environment.
2. An untrusted job receives no repository, organization, signing, deployment, or release secret.
3. A trusted job never checks out or executes the PR tree.
4. A trusted job never runs binaries, scripts, package hooks, or local actions extracted from an untrusted artifact.
5. The trusted signer uses scripts from the reviewed default branch at a pinned commit.
6. The trusted signer verifies pull-request identity, source SHA, repository ownership, approval state, and artifact attestation itself.
7. Fork-origin builds cannot enter the trusted signing path.
8. Updater-key access follows the checked-in channel trust policy and is available only inside the isolated signer; PR and publisher jobs never receive it.
9. Signing and publication are separate permissions; the publisher uploads only an allowlisted, verified inventory.
10. A failure leaves no public or partially updated feature release.

## Workflow architecture

```text
Pull request event
      │
      ▼
Untrusted build workflow
  read-only token, no environment, no secrets
  checkout exact PR SHA
  build unsigned candidates
  create canonical manifest + provenance
      │ immutable artifact ID + attestation
      ▼
Protected dispatch / environment approval
      │
      ▼
Trusted signer workflow from default branch
  validate PR and immutable inputs
  inspect without executing
  platform-sign and package using trusted tooling
  verify signatures and inventory
      │ signed private staging artifacts
      ▼
Trusted feature publisher
  verify all platform records
  publish pr<N> atomically
```

The workflows may be separate reusable workflows or separate jobs with provable trust boundaries. A single job that changes permissions or receives secrets after building PR code is forbidden because its process, workspace, and generated files are already compromised.

## Untrusted build stage

### Trigger and identity

The build runs on `pull_request` using the exact head SHA supplied by GitHub. It records base SHA, head SHA, PR number, head repository full name, platform, architecture, and workflow run identity.

It does not use `pull_request_target`. It does not inherit repository secrets. Workflow permissions are declared explicitly, with `contents: read` and no write scopes.

### Execution boundary

The job may install dependencies and execute the PR's build because that is the purpose of the untrusted stage. It must not:

- reference a protected environment;
- use persistent self-hosted runners carrying production credentials;
- invoke a local action as a trusted policy decision;
- write releases, tags, checks outside the minimum GitHub-provided PR reporting behavior, or repository contents;
- obtain an updater private key;
- sign with an Operator release identity.

Third-party actions are pinned to immutable commit SHAs. Local build actions from the PR are treated as arbitrary PR code and remain confined to this stage.

### Output contract

The stage uploads unsigned candidates and a canonical manifest. The manifest contains a sorted allowlisted set of relative paths with:

- artifact role;
- platform and architecture;
- media type;
- byte size;
- SHA-256;
- source commit and PR number;
- build workflow run and job identity;
- channel `pr<N>`;
- toolchain lock identifiers.

Paths must be normalized, relative, unique, free of traversal, and reject absolute paths, links, devices, sockets, and duplicate normalized names. Archives are not trusted to define destination paths.

GitHub artifact attestation binds the manifest digest and uploaded artifacts to the untrusted workflow identity. The artifact retention window is bounded.

## Trusted admission stage

### Entry conditions

The trusted workflow is defined and loaded from the default branch. It starts only through an approved workflow dispatch or protected environment after the untrusted run is complete.

Before accessing signing material it independently queries GitHub and proves:

- the PR exists and is still open;
- the head repository is the Operator repository, not a fork;
- the head SHA exactly matches the requested build SHA;
- the base branch is an allowed protected branch;
- the untrusted workflow conclusion is successful;
- the actor and approval satisfy repository policy;
- the artifact attestation issuer, repository, workflow, commit, and run match expected values;
- no existing release for the channel points at a different source SHA under the same immutable feature version.

The previous `allow_fork` path is removed. No input can override the same-repository check.

### Artifact handling

The trusted stage downloads into a fresh isolated directory and treats all bytes as data. It verifies the manifest before extracting any archive. Extraction uses a safe library or tool with explicit path and type validation.

The trusted stage may inspect formats, metadata, and hashes. It may sign declared executable/package payloads with platform-native tools. It never runs the candidate application, installer, package hook, shell file, JavaScript, binary, or PR-provided verification utility.

All orchestration scripts, packaging transforms, allowlists, and verification logic come from the pinned trusted checkout. Dependency installation for trusted tooling uses the trusted lockfile and disables lifecycle scripts unless a reviewed tool explicitly requires them.

### Signing isolation

Each platform signer receives only the signing material needed for its platform and the checked-in channel trust policy. If feature, nightly, and stable feeds deliberately share an updater trust root for cross-channel compatibility, only the isolated updater signer receives that shared private key. Apple, Windows, Linux, and updater signers use dedicated protected environments with scoped approvals.

Signing credentials exist only during the signing step, are masked, and are removed from temporary keychains or agents in an unconditional cleanup step. Logs expose only non-secret key identifiers or certificate fingerprints.

## Feature publication

Signed outputs are first stored privately as workflow artifacts or a draft release. A feature release becomes public only after all required platform signers report success for the same PR head SHA and manifest lineage.

After signing, an unprivileged acceptance job with no secrets or repository-write permission may execute the signed candidate in an ephemeral environment. It proves the candidate accepts a feature manifest fixture signed by the configured updater key and rejects a fixture signed by an unrelated key. The signer creates the fixtures; the acceptance job never receives the private key. Its evidence binds the candidate digest, source SHA, channel, and public-key identifier.

The publisher:

1. reads a fixed artifact inventory from trusted policy;
2. verifies each digest and native signature;
3. verifies the updater-key binding evidence for each candidate and verifies every feed signature against the trust policy;
4. generates feeds using trusted base-branch code;
5. verifies feed URLs, version, channel, architecture, signature, and digest;
6. creates or updates one `pr<N>` release;
7. uploads to private staging;
8. verifies the remote inventory;
9. exposes the release and feed only after the inventory is complete.

The publisher has `contents: write`; build and signer jobs do not. Publication is idempotent for the same immutable source and artifact digests. A conflicting rerun fails rather than replacing already published bytes silently.

## Failure and cleanup behavior

- An untrusted build failure produces no signing request.
- Admission failure produces no signer credential access.
- A signer failure leaves private artifacts and a failed run for diagnosis.
- A publisher failure keeps the release draft/private and does not update the feature feed or version-free alias.
- Cleanup removes temporary keychains and local signing state even after cancellation.
- Retention policies delete expired private feature candidates without touching stable releases.

No automated rollback republishes earlier artifacts under a new digest. Recovery reruns the trusted conductor against the same immutable inputs or starts a new build.

## Workflow policy tests

Add a repository-owned validator that parses the effective feature workflows and fails when:

- a PR-code job has a protected environment, secrets, or write permission;
- a trusted job checks out a PR ref or head SHA;
- a trusted job uses a local action from the untrusted checkout;
- a job both executes untrusted build steps and holds signing or publication authority;
- a fork override reaches signing;
- an action uses a mutable tag instead of an approved immutable reference;
- the publisher can run before every required signer and verification job;
- more than one job can make the release public or update the feed.

Fixtures include a malicious PR workflow/configuration that attempts dependency lifecycle exfiltration, local-action replacement, artifact path traversal, output injection, symlink escape, and fork admission. The expected result is confinement to the untrusted job and rejection at trusted admission.

The tests validate workflow structure; a dry-run test validates manifest and artifact admission using synthetic signed fixtures without production credentials.

## Observability and audit record

Every trusted run emits a machine-readable report containing admission checks, source identity, artifact digests, signing certificate identifiers, updater public-key identifier, publication inventory, and final release visibility. It excludes secrets and sensitive local paths.

The report is retained with the workflow run and attached to the feature release after publication. Repository audit logs must be sufficient to identify who approved the protected environment and which workflow run published the release.

## Expected file surface

Implementation is expected to modify:

- `.github/workflows/feature-release.yml` or replace it with explicitly named untrusted-build and trusted-publish workflows;
- trusted scripts under `frontend/scripts/` for manifest validation, artifact verification, and feature-feed generation;
- workflow-policy tests under the existing script test conventions;
- feature release documentation that currently describes the old single-job trust model.

It must not modify application runtime behavior or expand the npm package's role.

## Acceptance criteria

1. PR code builds with no secrets, protected environment, or write permission.
2. The trusted signer checks out only reviewed base-branch tooling and never executes candidate bytes.
3. Fork PRs are mechanically unable to obtain a signed feature release.
4. Platform signing roles, updater signing, acceptance, and publication are separate at the workflow boundary; any deliberately shared updater key is confined to its protected signer.
5. Malicious fixture tests fail closed for every listed attack class.
6. A successful same-repository fixture produces a complete, verified, atomic `pr<N>` release through the trusted path.
7. Any failed platform signer or verifier leaves no public partial release and no updated feed.
8. Exactly one publisher has repository-write permission for feature publication.
9. Workflow lint, policy tests, artifact tests, and `git diff --check` pass.

## Out of scope

This design does not make feature listing, pin retirement, or escalation transports a product promise. It secures the existing feature-build pipeline. Stable release publication is owned by the trusted atomic release design.
