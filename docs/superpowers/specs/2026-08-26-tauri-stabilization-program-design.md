# Tauri stabilization program — design index

**Date:** 2026-08-26
**Status:** proposed design
**Source audit:** `docs/todo/tauri-port-bugs-and-deferred.md`
**Revalidated against:** `3b88fc61482e00e6083e3ebf46c0b3a77bd8db81` on `master`
**Scope:** close the 17 unchecked Tauri port bugs without pulling the separately listed deferred work into this program.

## Purpose

The Tauri port has a working application surface, but it is not ready to be treated as release-safe. The remaining defects cross security, updates, renderer startup, native integrations, state confinement, CI evidence, and publication. Fixing them as one implementation plan would create unsafe sequencing and make reviews too broad.

This program divides the work into five independently reviewable designs. Every open bug has one owning design. Shared files may be touched by more than one implementation plan, but responsibility for behavior is not duplicated.

## Binding priorities

1. Remove the feature-release credential exposure before running or extending feature releases.
2. Make update checking non-fatal before exercising packaged update flows.
3. Implement update installation and recovery before any release workflow can claim update acceptance.
4. Make CI evidence, parity evidence, and release gates fail closed.
5. Publish a stable release only from a single trusted conductor after every required artifact and gate belongs to the same commit and artifact set.

Functional parity, terminal correctness, state confinement, and update trust take precedence over speed of delivery. A blocked release remains private; the program never weakens a gate to make a release pass.

## Designs

| Design | Owned bugs | Required outcome |
|---|---:|---|
| `2026-08-26-tauri-feature-release-security-design.md` | 1 | PR-controlled code cannot access signing identities, write-capable repository credentials, or trusted publisher execution. |
| `2026-08-26-tauri-updater-stability-design.md` | 3 | Update check, download, restart/install, recovery, and rollback work without panic and keep Operator-owned updater state under the configured state root. |
| `2026-08-26-tauri-renderer-native-stability-design.md` | 6 | Startup hydration, notification activation, tray policy, preview acknowledgement, and terminal key handling are deterministic and tested. |
| `2026-08-26-tauri-ci-confinement-parity-design.md` | 4 | Native CI reaches packaged tests, browser aliases obey confinement, parity evidence is meaningful, and the retired workflow is cleanly removed. |
| `2026-08-26-tauri-trusted-atomic-release-design.md` | 3 | Stable releases remain private until signed artifacts, updater trust, native acceptance, and binding release evidence all pass. |

The 17 bugs are counted as 1 + 3 + 6 + 4 + 3. Deferred entries in the audit remain outside these totals.

## Bug ownership

| Audit bug | Owner |
|---|---|
| Feature-release jobs expose signing identities and repository-write access to PR code | Feature-release security |
| Packaged update check can panic | Updater stability |
| Update installation is exposed but absent | Updater stability |
| Completed update downloads are forgotten after restart | Updater stability |
| Persisted locale hydration races daemon startup | Renderer/native stability |
| Persisted shortcut hydration races daemon startup | Renderer/native stability |
| Native notification clicks cannot activate or navigate Operator | Renderer/native stability |
| Stable packaged macOS builds create a tray against policy | Renderer/native stability |
| Preview acknowledgement failures lose acknowledgement or open duplicate tabs | Renderer/native stability |
| Shift+Enter sends an agent-specific sequence in plain shells | Renderer/native stability |
| WebDriver CI omits the browser runtime resource | CI/confinement/parity |
| Browser runtime creates socket aliases outside the Operator root | CI/confinement/parity |
| Parity checker accepts meaningless status and evidence | CI/confinement/parity |
| Retired Phase 0 workflow is invalid instead of disabled | CI/confinement/parity |
| Stable releases can become public while incomplete | Trusted atomic release |
| Updater key binding and Windows/Linux native trust are not proven | Trusted atomic release |
| Completion records contradict binding acceptance criteria | Trusted atomic release |

## Program dependency order

```text
Feature-release containment
          │
          ├──────────────┐
          ▼              ▼
Updater stability   Renderer/native stability
          │              │
          └──────┬───────┘
                 ▼
       CI, confinement, parity
                 │
                 ▼
       Trusted atomic release
```

The updater and renderer/native workstreams may be implemented in parallel after containment. CI/confinement/parity can begin in parallel where files do not overlap, but its final ledger corrections depend on the relevant product behavior existing. Trusted publication is last because it consumes the outputs and evidence produced by all preceding workstreams.

## Shared invariants

- The loopback daemon remains bound to `127.0.0.1` and remains the owner of product and session behavior.
- The Tauri shell stays a thin native supervisor and integration surface.
- All application-owned state, including webview, updater, browser runtime, terminal, and recovery state, stays beneath the resolved Operator state root.
- No PR-controlled code executes with signing secrets, protected release environments, or repository-write credentials.
- No release becomes public until the complete artifact set and its checks pass.
- The renderer never treats a transient daemon-startup failure as an authoritative persisted default.
- Terminal input behavior is selected by pane capability, not globally assumed from one agent TUI.
- Evidence refers to the exact tested commit and artifact digests.
- Unsupported behavior is marked unsupported or blocked; it is never represented as covered.
- The embedded in-app Browser panel remains outside this program.

## Cross-design interfaces

### State root

Every design uses the same resolved state root from the existing Operator configuration. A component receives an explicit resolved path; it does not independently infer `~/.operator`, use an OS application-data default, or fall back to `/tmp`.

### Release evidence identity

Every native build, test, signing, and publication output carries:

- source commit SHA;
- platform, architecture, and packaging target;
- immutable artifact SHA-256;
- workflow run and job identity;
- channel and version;
- dirty-tree status for local evidence;
- signing identity or updater key identifier where applicable.

The final conductor accepts only records for one source commit, version, channel, and declared artifact inventory.

### Errors and telemetry

New failure paths use stable machine-readable codes and actionable user messages. Logs and telemetry must not include updater private keys, signing material, repository tokens, full local paths, terminal contents, notification bodies, or preview URLs with secrets.

### Completion state

Each implementation plan may report its scoped work complete after its acceptance criteria pass. The Tauri port as a release remains blocked until the binding Phase 0 and release criteria pass. Finishing all five plans does not by itself authorize changing `stop-port`.

## Program acceptance

The bug program is complete only when:

1. All 17 audit entries are checked with a commit and test/evidence reference.
2. Each of the five designs has a passing implementation review and a final cross-design review.
3. Normal backend, renderer, Rust, capability, state-audit, parity, and native packaged checks pass.
4. Feature and stable release workflow policy tests prove untrusted/trusted separation.
5. No checked-in documentation claims release approval while the binding decision is `stop-port`.
6. The deferred section remains intact and accurately distinguishes later hardening or evidence work from bugs fixed by this program.

## Out of scope

This program does not implement the embedded Browser panel, produce the final performance benchmark corpus, make feature/nightly services a product promise, replace updater downloads with streaming, redesign titlebars, solve TUI-to-Chat history transfer, or complete unrelated benchmark-tooling debt. Those items remain tracked under the audit's deferred section.
