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

## Task 19 renderer startup and retained-memory probes (local, non-binding)

Task 19 added two measurement producers for the renderer startup and retained-memory work. Both are local diagnostic probes with their own schemas; they are not binding results under the sampling rules above and never substitute for the gates in the table.

`frontend/scripts/route-bundle-report.mjs --label before|after` builds the renderer with a Vite manifest into a scratch directory, resolves the initial-route graph for the board (the HTML entry closure plus the `_shell` layout and board route chains, following static imports only), sums parsed JS/CSS bytes, and rejects forbidden eager edges from that graph to terminal/chat/diff/settings modules when they are not required for board paint. A chunk whose heavy dependency moved behind a dynamic-import edge keeps its source-derived name without being a violation. Exit code is 0 with zero violations and 2 when violations exist; the report is written to `perf/results/route-graph/<label>.json`. Manifest ids are repo-relative by construction and reports refuse absolute or home-directory paths.

`frontend/scripts/heap-summary.mjs --label before|after [--probe all|empty-board|terminal-disposal]` launches a locally built Tauri shell against an isolated state root and samples the POSIX process tree via `ps`. The empty-board probe waits for daemon readiness, idles (default 20 seconds locally; binding idle-memory stays at the 60-second rule above), and reports shell+webview tree bytes excluding the Go daemon subtree alongside daemon bytes separately. The terminal-disposal probe serves the `perf/terminal` harness on the dev URL with a `disposal` scenario that mounts a fresh xterm surface per cycle, feeds it synthetic output (default 2 MiB), disposes it, and acknowledges disposal over loopback HTTP; the probe samples full-shell-tree RSS after each acknowledgement and records retention deltas against a pre-mount baseline. Results land under `perf/results/heap/<label>-<probe>.json`.

Honest scope of these probes as of 2026-08-24, darwin/arm64: the Tauri binary used is `target/debug/operator`, which loads its dev URL, so renderer bytes match a production Vite build but the Rust side is a debug build (`buildKind: "debug-devurl"`); memory is process-tree RSS from `ps`, not an in-webview JS heap reading, because WKWebView exposes no heap endpoint to this harness; warm-start p50/p95 and first-run comparisons for the Tauri webview stay unobservable here because WKWebView has no automation channel on macOS, so those remain native-runner work, and `scripts/benchmark-shell.mjs` still supports only the Electron shell. Binding comparisons continue to require like-for-like signed release builds per the sections above.

