# Tauri port performance baseline

This document fixes the measurement contract used to compare Electron and Tauri. Results are valid only when they come from like-for-like signed release builds on the same machine. Measurements must cover macOS, Windows, and Linux; Linux records compositing enabled and `WEBKIT_DISABLE_COMPOSITING_MODE=1` separately.

## Sampling and accounting

Cold-start and terminal scenarios use 3 warmups followed by 10 measured samples. Memory scenarios use 5 independent launches and sample at the 60-second idle-stability point.

Startup duration begins at process spawn. Warm start ends at the interactive-board mark. First-run startup is reported separately and ends only after daemon start and readiness. Terminal open begins with the open action and ends at an interactive prompt. Terminal completion comes from a timestamp-only renderer acknowledgement, never from bytes written to the PTY.

Memory is the RSS or working set of the full process tree, not only the parent shell process. Idle shell accounting includes the shell and webview tree while reporting the Go daemon, ACP runtime, and managed browser separately. Active-terminal accounting records full process-tree memory at the fixed steady-state scenario and CPU time per completed fixed workload.

Artifact measurements include the Go daemon, packaged `agent-browser`, and the existing Node 22.23.2 ACP runtime in both Electron and Tauri base packages. The primary signed update artifact and installed application footprint are base measurements. The managed browser installed on first automation use is measured and reported separately as the post-browser-install footprint; it is never included in or hidden by the base result.

## Required result metadata

Every result uses these exact top-level JSON keys: `schemaVersion`, `shell`, `scenario`, `commit`, `dirty`, `buildProfile`, `platform`, `architecture`, `osVersion`, `cpu`, `logicalCores`, `physicalMemory`, `webviewRuntimeVersion`, `rendererKind`, `displayScale`, `scenarioConfiguration`, `warmups`, `sampleCount`, `samples`, `median`, `p95`, and `unit`.

`warmups` and `sampleCount` are integer counts, `samples` is the measured numeric sample array, and `unit` applies to `samples`, `median`, and `p95`. `webviewRuntimeVersion` identifies the Electron/Chromium or Tauri/OS-webview runtime used for the result. `scenarioConfiguration` contains only the sanitized inputs that define the measured scenario.

Results must not contain private paths, environment values, process IDs, terminal contents, credentials, or output paths outside `frontend/perf/results`.

## Binding gates

| Area | Required result |
|---|---|
| Terminal open | Tauri median is at most 75% of Electron median and Tauri p95 is at most 90% of Electron p95. |
| Terminal throughput | Tauri median is at least the Electron median for both `vtebench` and the fixed large-output scenario. |
| Terminal input latency | Tauri p95 input-to-render latency is no worse than Electron p95. |
| Terminal reconnect | Tauri p95 disconnect-to-interactive latency is no worse than Electron p95. |
| Active terminal resources | Full process-tree memory and CPU time per completed fixed workload are no worse than Electron. |
| Terminal correctness | Full-screen TUI redraw, glyph width, resize, selection, scrollback, reconnect, and renderer recovery have no regression. |
| Renderer | WebGL is required on macOS and Windows. Linux canvas is permitted only by a Phase 0 `linux-canvas` decision and only if every terminal gate passes. |
| Warm start | Tauri p50 is at most 70% of Electron p50 and Tauri p95 is at most 75% of Electron p95. |
| First-run start | Tauri is faster than Electron at both p50 and p95 through daemon readiness. |
| Idle shell memory | Tauri shell plus webview full process-tree memory is at most 60% of Electron. |
| Base signed download | Every primary Tauri update artifact is at most 100 MiB and at most 70% of its Electron counterpart. |
| Base installed footprint | Tauri is at most 60% of the Electron installed application footprint. |
| Managed browser footprint | Report the post-install footprint separately from the base application. |
| Functional parity | Every ledger entry passes except exact exceptions linked to `docs/todo/browser-panel-webview.md`. |

Both the absolute and relative artifact-size limits are binding. A Phase 0 result of `continue` or `linux-canvas` is required before product port work begins.

## Evidence provenance

Binding artifact evidence requires repository-pinned release publisher identities and an attestation-key fingerprint in `frontend/scripts/phase0-release-trust.json`; caller-provided environment values cannot replace those anchors. The checked-in anchor remains deliberately unconfigured until the designated release conductor supplies the real macOS Team ID, Windows certificate identity and thumbprint, Linux GPG fingerprint, and attestation-key fingerprint. Artifact measurements fail closed until then and retain the signed statement, detached signature, public key, and verified digest needed for independent review.

Platform summaries are derived by `frontend/scripts/phase0-platform-summary.mjs` from retained raw artifacts — validated benchmark results, state-audit output, per-mode browser probe records, recorded migration observations, CORS probe evidence, and updater material whose signature is re-verified against the retained fixture bytes before any summary is written. Every consumed file is bound by a recomputed SHA-256 manifest inside the summary; missing, unvalidated, or internally inconsistent inputs refuse the write and name each gap. The producer accepts only binding-scoped results whose commit matches the workflow commit, derives Linux Tauri metrics from the full `WEBKIT_DISABLE_COMPOSITING_MODE` on/off pair (worse-of-pair), and reports `compositingPairObserved` for the decision to enforce.

Large-output results fail closed unless every measured workload reported its observed byte count within the configured output plus bounded shell overhead. Browser evidence must carry one record per concurrently active mode (system and managed), each proving isolation while running, guaranteed teardown with post-close verification, removal of the isolated state root, presence of its own cookie marker, and cross-mode cookie isolation between the two sessions. Migration evidence is compiled by `phase0-legacy-update.mjs --record` from machine-written exercise observations of locally built fixtures; incomplete exercises record truthful failure reasons instead of success claims.

The Phase 0 decision accepts only CI-aggregated evidence tied to one full source commit and one workflow run. Every terminal metric must identify binding evidence, report an exact positive required and observed workload count, and prove successful completion. Native release, updater, migration, CORS-probe, and three-platform terminal evidence are still external runner requirements; their absence keeps the decision at `stop-port`.

## Phase 0 decision

Decision: `stop-port`

Timestamp: 2026-08-23T18:13:04.302Z

Reasons:
- missing evidence file: perf/results/phase0-evidence.json or perf/results/evidence.json
- missing platform evidence: darwin
- missing platform evidence: win32
- missing platform evidence: linux
- missing application identity evidence
- missing updater-signing evidence

