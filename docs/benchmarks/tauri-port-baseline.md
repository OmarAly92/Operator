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
