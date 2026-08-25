# Tauri port: release gates and follow-ups

**Recorded:** 2026-08-25  
**Status:** the code port is implemented; public release approval is blocked  
**Source:** `docs/superpowers/plans/2026-08-20-tauri-port.md`

## Meaning of "implemented"

The Electron shell has been replaced by Tauri and the local macOS implementation has broad automated coverage. That does not make the port release-ready. The Phase 0 decision in `docs/benchmarks/tauri-port-baseline.md` remains `stop-port`, several required behaviors are intentionally fail-closed, and binding native evidence does not yet exist on all three operating systems.

Do not mark this file complete, flip Phase 0 to `continue`, or publish a Tauri release until every release blocker below has evidence attached to the same commit and artifact set.

## Release blockers

- [ ] Produce trusted Phase 0 evidence on macOS, Windows, and Linux from authorized native runners. Configure `frontend/scripts/phase0-release-trust.json`, restore or replace the retired triggerless `.github/workflows/tauri-phase0.yml` producer, aggregate the signed evidence, and reach the plan's `continue` or explicitly approved `linux-canvas` decision.
- [ ] Implement and verify the project-owned updater apply path. `updates_install` currently returns `APPLY_DEFERRED_MESSAGE`; a staged download is not an installed update. Keep all temporary, staged, rollback, and recovery data under the resolved Operator state root.
- [ ] Implement real OS notification activation so clicking a native toast focuses Operator and opens the correct session or PR. The renderer event route exists, but production UNUserNotificationCenter and WinRT activation delivery does not.
- [ ] Add a Tauri-capable `benchmark-shell.mjs` producer and record binding, same-workload Electron-versus-Tauri measurements. Required evidence includes warm and first launch, idle memory, CPU, terminal-open latency, terminal throughput, sustained output, input latency, reconnect correctness, resource cleanup, artifact/download size, and installed footprint. Measure the standalone managed browser separately from the shell.
- [ ] Run WebdriverIO against real packaged Tauri binaries on Windows and Linux. The macOS native suite is not cross-platform proof.
- [ ] Run the standalone `agent-browser` lifecycle and policy acceptance matrix on macOS, Windows, and Linux, including install, launch, isolation, screenshots, teardown, and rejected escape flags.
- [ ] Run signed install, upgrade, downgrade, interrupted-download recovery, Electron-to-Tauri migration, and rollback E2E on all three operating systems. macOS verification must use the repository verification scripts and real signing/notarization material.
- [ ] Fix and rerun the Darwin `audit:tauri-state` shutdown-timeout case, then prove that daemon state, Tauri webview state, updater data, browser profiles, terminal drops, and temporary files stay under `~/.operator` or the explicit override on all three systems.
- [ ] Make the release conductor fail closed. Artifact publication and feed publication must depend on Phase 0 approval, strict artifact verification, signed updater E2E, native acceptance, and the release blockers above; advisory gates must not allow a public release to publish.
- [ ] Separate feature-build compilation from signing. PR-controlled code must run in an unprivileged job with no updater, Apple, Windows, Linux, or repository-write credentials; sign only an attested immutable artifact in a trusted base-branch job that executes no PR code. Fork approvals must never expose production identities.
- [ ] Obtain explicit product sign-off for decorated native titlebars on macOS and Windows, or implement and verify the coordinated drag-region/titlebar migration before release.
- [ ] Add and verify the schedule-triggered nightly producer before advertising or enabling nightly releases.

## Correctness follow-ups

- [ ] Separate automatic-preview open completion from acknowledgement completion. Missing trusted API-base, non-2xx, and transport failures must retry only the acknowledgement, never reopen a browser that already opened successfully.
- [ ] Add a real native E2E assertion that distinguishes live terminal mux output from browser-preview/demo text. A review on 2026-08-25 found that `TerminalPane` used the Electron-only `window.operator` check and rendered screenshot text in every Tauri session; the code regression is fixed, but the native test must protect the actual stream boundary.
- [ ] Harden the parity and Electron-absence checks: constrain status vocabulary, reject invented archived rows, scan backend/scripts/E2E surfaces where applicable, and remove vestigial Tauri-port test environment switches.
- [ ] Harden Phase 0 scripts and evidence validation: Windows environment mirroring, PowerShell whitespace handling, terminal-open production, route/evidence graph checks, recursive raw-JSON and credential sweeps, and exact signed-payload binding.
- [ ] Investigate and harden the Tauri relocation-lock timing test. A loaded whole-suite run failed `contended_second_instance_declines_without_touching_either_bundle` once; the exact test subsequently passed five consecutive isolated runs, so this remains reliability debt rather than a reproduced product failure.

## Updater and packaging follow-ups

- [ ] Wire the shell-side GitHub release and escalation transports, or retain the current stopped transports with explicit non-gating product sign-off. The implementation brief is `.superpowers/sdd/2026-08-20-tauri-port/followup-github-transports-brief.md`.
- [ ] Add chunked/streaming HTTP downloads with bounded memory, cancellation, timeout, and partial-file recovery coverage.
- [ ] Add production-key mismatch tests, startup failure signaling, escalation race coverage, and time-zone boundary coverage.
- [ ] Strengthen artifact verification on Windows and Linux with embedded-version checks, alias/feed topology checks, uploaded gate ledgers, recursive secret scans, and signed metadata/payload binding.
- [ ] Make `npm run verify:tauri-artifacts` either self-contained for a documented staged distribution directory or update the final plan/checklist command to pass the required `--dist`, platform, architecture, mode, and trust arguments.

## Native shell and runtime follow-ups

- [ ] Verify full menu, shortcut, tray, startup-theme, overlay, clipboard, directory chooser, mailto/external-link, and fullscreen behavior on each native platform. Cover shortcut-registration retries, tray locale persistence, notification icons, and URL authority edge cases.
- [ ] Split audit and benchmark command permissions from the normal production capability, and keep a restrictive CSP enforced by both the packaged shell configuration and the renderer build.
- [ ] Tighten standalone browser cancellation during install, stat-before-screenshot handling, timing-bound tests, and unused state-root options. Keep browser execution policy closed and profiles isolated per session.
- [ ] Remove or bound stale relocation staging after an abandoned migration and close the daemon shutdown/start supervision window.
- [ ] Decide whether a first TUI-to-Chat switch should import provider visual history and whether in-flight tool calls can ever be portable. These require provider identity/deduplication and execution-transfer contracts, not a renderer-only change.

## Performance, test, and tooling debt

- [ ] Narrow the route-bundle xterm exemption, correct possible CSS total double counting, use path-safe containment checks in heap tooling, validate benchmark arguments consistently, and avoid permanently caching rejected lazy telemetry/terminal imports.
- [ ] Upload native E2E failure artifacts and benchmark JSON, remove dead E2E environment knobs, eliminate reload races, and exercise release rather than debug binaries where the plan requires production behavior.
- [ ] Make the Phase 0 workflow and evidence parsers fail when required producers disappear instead of allowing retired or stale workflow bodies to pass absence checks.

## Deliberately deferred product scope

- The embedded in-app Browser panel remains deferred and is not a release blocker for this port. Its product scope, capability losses, and open questions are tracked in [`browser-panel-webview.md`](browser-panel-webview.md).
- Shell-owned GitHub transports are non-gating only while the stopped implementation fails closed and channel behavior remains available through the approved feed path.
- Reconstructing terminal screen history as structured Chat messages and transferring currently executing tools are separate product designs, not hidden Tauri parity work.

## Completion evidence

When the blockers are resolved, attach:

- the exact source commit and artifact hashes;
- the Phase 0 aggregate and trust verification output;
- macOS, Windows, and Linux native E2E reports;
- signed updater install/migration reports;
- performance result JSON and threshold decision;
- artifact size and installed-footprint comparison;
- the final release-conductor gate output.

Only then update `docs/STATUS.md` and `docs/benchmarks/tauri-port-baseline.md` from `stop-port` to the evidence-backed decision.
