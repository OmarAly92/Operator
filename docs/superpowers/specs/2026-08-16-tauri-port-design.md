# Replacing Electron with Tauri — design

**Date:** 2026-08-16
**Revised:** 2026-08-21
**Status:** approved design, implementation gated by Phase 0
**Scope:** replace the Electron desktop shell in `frontend/` with Tauri on macOS, Windows, and Linux while preserving every product capability except the explicitly deferred embedded Browser panel.

## Goals and order of precedence

The port has four goals:

1. Preserve the in-app terminal and make its measured throughput and input latency no worse than Electron.
2. Reduce cold-start time and idle shell memory substantially.
3. Reduce signed download size and installed footprint substantially.
4. Preserve every current desktop, daemon, CLI, and mobile behavior except the embedded Browser panel capabilities listed in `docs/todo/browser-panel-webview.md`.

When goals conflict, terminal correctness and functional parity win. The port stops rather than shipping a smaller application that loses a supported agent, update channel, CLI flow, or desktop integration.

## Current system

The desktop shell is Electron 33 with React 19 and Electron Forge. Phase 0 establishes repeatable per-platform startup, memory, terminal, and artifact baselines before any comparison is accepted.

Changing shells does not remove the React renderer or its heap. Renderer profiling and route-level loading remain a required workstream.

The packaged application also contains three non-shell runtimes that must be counted in every size measurement:

- the Go daemon built by `frontend/scripts/build-daemon.mjs`;
- `agent-browser` 0.33.1 prepared by `frontend/scripts/prepare-agent-browser.mjs`;
- the existing ACP runtime prepared by `frontend/scripts/build-acp-runtime.mjs`, including Node 22.23.2 and `@agentclientprotocol/claude-agent-acp`.

The ACP runtime is current product functionality. This port preserves it. Removing or rewriting it is a separate project and cannot be used to make the Tauri size result look smaller.

## Decisions

| Concern | Decision |
|---|---|
| Platforms | macOS, Windows, and Linux retain release parity. |
| Shell | Tauri 2 with a thin Rust layer for native and lifecycle responsibilities. |
| Renderer | Keep React, TanStack Router, and the existing daemon REST/SSE/terminal-mux transports. |
| Terminal | Keep `@xterm/xterm` and the Go PTY → mux WebSocket → xterm path. |
| Embedded Browser panel | Remove and defer it. Do not recreate it during this port. |
| User preview | `opr preview` updates the session preview target; the running desktop observes the revision and automatically opens a validated HTTP(S) URL in the default browser. The inspector also offers a reopen action. |
| Agent automation | Replace the Electron `WebContents` CDP bridge with an isolated standalone Chromium managed by the Go daemon through the packaged `agent-browser` binary. |
| Browser engine delivery | Discover an installed compatible Chrome, Edge, or Chromium first. If none is usable, install the pinned agent-browser managed browser on first automation use beneath `~/.operator/browser-engine`. Do not bundle Chromium in the base application and do not write to the default agent-browser home. |
| ACP runtime | Preserve the packaged Node 22.23.2 ACP runtime and pass its Tauri resource path to the daemon. Do not add another Node runtime. |
| Product state | Extend the existing daemon `app_settings` source of truth for shared preferences. Shell-native installation facts remain Rust-owned. |
| Rollout | Electron and Tauri coexist in development until signed Tauri artifacts pass parity and the last Electron release can migrate through the published compatibility feed. Existing `~/.operator` durable data remains usable. |

The managed browser download is part of browser automation, not the application artifact. Report both base installed footprint and post-browser-install footprint so the size result remains honest.

## Phase 0 kill gates

No product port begins until a minimal Tauri spike passes all of these gates on every supported platform.

### Webview state location

All application state must remain beneath `~/.operator` or the existing Operator overrides. The spike must inventory filesystem writes made by the Tauri application and its webview after first launch, navigation, local/session storage, cookies, cache activity, crash handling, and shutdown.

Tauri's [`WebviewWindowBuilder::data_directory`](https://docs.rs/tauri/2.11.5/tauri/webview/struct.WebviewWindowBuilder.html#method.data_directory) is not a portable substitute for Electron's `userData` override: WKWebView does not support it, and [`data_store_identifier`](https://docs.rs/tauri/2.11.5/tauri/webview/struct.WebviewWindowBuilder.html#method.data_store_identifier) is available only on macOS 14 and newer. The spike must prove a supported implementation that keeps the required data under the Operator root on the project's minimum macOS version. If it cannot, the decision is `stop-port`; implementation may not weaken the repository's state-location rule.

### Daemon origin boundary

The packaged renderer origin is `tauri://localhost` on macOS/Linux and `http://tauri.localhost` on Windows. Keep Tauri's [`use_https_scheme`](https://docs.rs/tauri/2.11.5/tauri/webview/struct.WebviewWindowBuilder.html#method.use_https_scheme) disabled: its HTTPS custom scheme blocks mixed HTTP content, including the existing loopback daemon transport. The daemon must allow only those exact Tauri production origins plus the existing trusted Electron development origin while dual-shell development continues. It must continue rejecting `null`, `*`, non-loopback HTTP(S) origins, and lookalike localhost names before handlers execute.

### Real terminal

The spike mounts the production `XtermTerminal` against a live daemon mux. It does not add a file-based production route; it uses a separate benchmark Vite entry.

Run Electron and Tauri on WKWebView, WebView2, and WebKitGTK. On Linux measure with `WEBKIT_DISABLE_COMPOSITING_MODE` both unset and set to `1`.

### Standalone agent automation

Current automation is not standalone: `frontend/src/main/agent-browser-runtime.ts` sets `AGENT_BROWSER_CDP` to a bridge whose targets are Electron `WebContents`. The spike must instead prove all currently supported public browser actions using a standalone isolated browser with no Electron process.

The spike must prove:

- installed-browser discovery and pinned managed-browser installation;
- browser files, profiles, sockets, screenshots, downloads, and runtime markers stay beneath `~/.operator`;
- independent Operator sessions do not share browser profiles, tabs, cookies, sockets, or results;
- command allowlists, forbidden flags, output limits, timeouts, cancellation, content boundaries, and teardown remain enforced;
- `open`, `snapshot`, `click`, `console`, `errors`, `screenshot`, tabs, and session destruction work on all three platforms;
- first-use download failure produces a stable actionable error and does not partially activate a runtime.

### Packaging feasibility

Produce feasibility bundles containing the renderer, Go daemon, `agent-browser`, and the ACP runtime. Preserve `dev.operator.desktop`, `Operator.app`, executable name `operator`, and the existing version-free download aliases. Verify Tauri can create macOS app/dmg, Windows NSIS, and Linux AppImage/deb/rpm targets. Prove minisign-compatible updater signing and verify the RPM target rather than assuming it works.

Use locally test-signed candidate artifacts to prove that the last published Electron release can migrate to Tauri on all three platforms while retaining `~/.operator`. Test the existing Electron updater protocol, including the permanent macOS zip and `latest-mac.yml`. If direct replacement is impossible on a platform, Phase 0 must prove a signed Electron bridge release that performs the handoff safely before implementation can continue.

Phase 0 ends with exactly one decision:

- `continue` — all gates pass;
- `linux-canvas` — only Linux WebGL fails, canvas passes every terminal criterion;
- `drop-platform` — requires an explicit scope change from the user;
- `stop-port` — any hard state, automation, terminal, or packaging invariant cannot be met.

Only `continue` or `linux-canvas` permits product implementation.

## Measured acceptance contract

Every result records commit, dirty-tree flag, build profile, platform and architecture, OS version, CPU, logical cores, physical memory, webview/runtime version, renderer kind, display scale, scenario configuration, warmup count, sample count, samples, median, p95, and units. Private paths, environment values, process IDs, terminal contents, and credentials are never recorded.

Use at least 3 warmups and 10 measured samples for cold start and terminal scenarios. Memory uses 5 launches, sampled after 60 seconds of idle stability. Compare like-for-like signed release builds on the same machine.

| Area | Binding bar |
|---|---|
| Terminal open | From open action to interactive prompt, Tauri median is at most 75% of Electron and p95 at most 90%. |
| Terminal throughput | Tauri median is at least Electron median for `vtebench` and the fixed large-output scenario. |
| Terminal input latency | Tauri p95 input-to-render latency is no worse than Electron p95. |
| Terminal reconnect | Tauri p95 disconnect-to-interactive latency is no worse than Electron p95. |
| Active terminal resources | At the fixed steady-state terminal scenario, process-tree memory and CPU time per completed workload are no worse than Electron. |
| Terminal correctness | No regression in full-screen TUI redraw, glyph width, resize, selection, scrollback, reconnect, or renderer recovery. |
| Renderer | WebGL on macOS and Windows. Linux canvas is allowed only by the Phase 0 decision and only when all terminal bars pass. |
| Warm start | Tauri p50 from process launch to interactive board is at most 70% of Electron p50, and p95 is at most 75%. |
| First-run start | Record separately through daemon start and readiness; Tauri must be faster than Electron at both p50 and p95. |
| Idle shell memory | Tauri shell plus webview process-tree memory is at most 60% of Electron shell process-tree memory. The daemon, ACP runtime, and managed browser are reported separately. |
| Base signed download | Each primary update artifact, including daemon, `agent-browser`, and ACP runtime, is at most 100 MiB and at most 70% of its Electron counterpart. |
| Base installed footprint | Tauri application footprint is at most 60% of the Electron application footprint on the same platform. |
| Managed browser footprint | Report separately after first browser installation; it does not count as base application size and may not be hidden from the final report. |
| Functional parity | Every item in the parity ledger passes except the exact Browser-panel exceptions in the deferred record. |

If an absolute and relative size gate conflict, both must pass unless this design is explicitly revised with checked-in measurements.

## Architecture

```text
Tauri shell (Rust)
  window, menu, tray, shortcuts, notifications, clipboard, dialogs
  external URL opening, updater engine, daemon supervision
  install marker, macOS relocation, dropped-file staging
          │ Tauri commands and events
React renderer
          │ REST + SSE + terminal mux WebSocket
Go daemon
  sessions, settings, update preference state, migration state
  import scanning, telemetry bootstrap, preview revisions
  standalone agent-browser lifecycle and command policy
          │
SQLite + adapters + packaged sidecars
```

Rust remains thin, but native installation facts stay in Rust because the daemon cannot discover the enclosing macOS bundle reliably. Shared user preferences stay in Go because desktop, mobile, and CLI consumers require one source of truth.

## Complete Electron parity ledger

The implementation plan carries a machine-readable ledger mapping every preload method and every direct renderer import from `frontend/src/main/`. Electron deletion is blocked until all non-browser rows have a Tauri or daemon implementation and all browser rows are listed in the deferred record.

| Namespace | Disposition |
|---|---|
| `app` | Version, directory chooser, and external open → Rust. Import scan and ancestor repository check → loopback-only Go developer routes. Shortcut events → Rust. |
| `terminal` | Dropped-file staging → Rust under `~/.operator/terminal-drops`, with byte limits and cleanup. Terminal bytes remain outside Tauri commands. |
| `window`, `menu`, `tray`, `clipboard`, `notifications`, `theme` | Rust with exact capability grants and platform tests. |
| `daemon` | Rust supervisor preserving current status and ownership semantics. |
| `telemetry` | Go bootstrap endpoint using daemon configuration and the existing telemetry install ID. |
| `uiSettings`, `updateSettings`, `keybindings` | Existing Go settings service and `app_settings` table, extended by migration `0088`. |
| `appState` migration block | Go settings service. |
| install marker fields | Rust writes `~/.operator/app-state.json` atomically on every launch; `opr start` remains a read-only consumer. |
| `updates`, `featureBuilds` | Tauri updater engine in Rust; channel, feature pin, and opt-in state from Go. Preserve status and telemetry events. |
| `browser` | Embedded panel methods are deleted and recorded in the deferred file. Public agent browser REST actions move to Go standalone automation. |

## Shared settings and loopback controls

Add fields to the existing singleton `app_settings` table with migration `0088`; do not create a parallel `desktop_preferences` table. The settings API remains under `/api/v1/settings` so desktop and mobile read the same values.

Folder import scanning and ancestor-repository detection operate on arbitrary local paths and are not mobile application APIs. Register them beneath `/api/v1/dev`, which the LAN listener already blocks. Do not add them under a LAN-visible `/api/v1/desktop` prefix.

Legacy `ui-settings.json`, `update-settings.json`, `keybindings.json`, and the migration block from `app-state.json` are imported exactly once. Corrupt files fall back to validated defaults without blocking startup. Import success is recorded durably so stale files cannot overwrite newer SQLite values.

## App marker, relocation, and `opr start`

Rust preserves the existing `app-state.json` schema and atomic-write behavior. On first creation it captures `installedAt` and `installSource`; later launches preserve them while refreshing `appPath`, `version`, and `lastReconciledAt`.

On macOS, port the current relocation decision exactly:

- stay when already in an Applications folder;
- relocate only when no installed bundle exists or it is strictly older;
- hand off when an equal-or-newer installed bundle exists;
- never overwrite when either version is unreadable.

`backend/internal/cli/start.go` learns Tauri executable and artifact names without weakening marker validation or known-location fallback behavior.

## External preview

The daemon preview target remains durable session state. Migration `0089` adds a durable opened revision. A valid new preview revision emits through the existing event stream. The running Tauri renderer opens HTTP(S) targets through the Rust opener and acknowledges the exact revision only after the opener succeeds. Pending revisions survive an app restart; acknowledged revisions do not reopen on rerender or later launches. The inspector also exposes a manual reopen action that does not change the automatic-open revision.

Workspace-relative Markdown/HTML preview routes remain daemon-owned. `clear` removes the target and never opens a browser. Invalid or non-HTTP(S) external URLs are rejected by the native opener. Agent automation may navigate its isolated browser to the same URL, but it does not attach to or control the user's personal default-browser profile.

## Standalone agent-browser ownership

The Go daemon replaces `backend/internal/browserruntime.Broker` with an adapter that launches the packaged `agent-browser` process directly. It preserves the public browser API and session capability checks while changing the reported transport to `agent-browser-standalone`.

The adapter owns two roots:

- `~/.operator/browser-engine` for the pinned managed Chromium installation shared read-only across sessions;
- `~/.operator/browser-runtime/<daemon-run>/<session>` for isolated configuration, profile, socket, screenshot, download, and ownership files.

The adapter passes a minimal allowlisted environment. It never exposes the user's normal home, shell credentials, cloud credentials, proxy credentials, or default browser profile. Managed installation is serialized and checksum/version verified. Partial downloads are removed. Session teardown closes the native runtime and removes only the validated owned session directory.

## Tauri native security

Pin Tauri and plugin versions in both npm and Cargo manifests. Grant capabilities per command; do not grant blanket filesystem, shell, process, or HTTP access. The renderer continues to use browser `fetch` and WebSocket directly for the loopback daemon, protected by the daemon origin allowlist.

Dropped files are staged beneath the Operator state root, not a worktree. Sanitize the basename, reject files above the documented limit, use collision-resistant names, write atomically, and prune old staged files on startup. The terminal receives only the returned staged path.

## Packaging, signing, and updating

Preserve the single-publisher rule and every existing channel behavior: `latest`, `nightly`, and `pr<N>`, first-run opt-in, feature pinning, pin clearing, downgrade behavior, automatic-failure status suppression, update telemetry, and return-home behavior.

Updater downloads, temporary archives, staged state, and recovery markers stay beneath `~/.operator/updater` or the Operator override. If the pinned updater plugin cannot honor that boundary on a platform, use a verified project-owned download/apply path or stop the port; OS-default temporary or app-data directories are not acceptable product state.

macOS continues publishing both DMG and zip. The signed app is archived with `ditto`; both zip and DMG are verified with `frontend/scripts/verify-mac-artifact.sh`. Tauri updater archives and signatures are additional artifacts, not replacements for the required zip or permanent `latest-mac.yml` compatibility feed.

Windows ships NSIS and performs a real signed update test. Linux ships AppImage, deb, and rpm only after each format is built and inspected on its native runner. Stable, nightly, and `pr<N>` releases publish Tauri feeds plus the compatibility YAML feeds still consumed by installed Electron builds. The existing version-free aliases for `opr start` and the landing page remain unchanged. Feeds reject missing signatures, wrong architecture, wrong channel, invalid versions, insecure production URLs, and private-key material.

## Renderer performance workstream

TanStack Router already has `autoCodeSplitting: true`; do not claim code splitting as a new optimization without a bundle graph proving a remaining eager dependency. Profile the empty board first, then change only measured eager imports or retained objects.

Required checks:

- initial route graph and transferred/parsed JavaScript;
- empty-board heap retainers;
- terminal disposal after session close;
- Motion usage by rendered route;
- board interaction and terminal readiness markers.

Every optimization records before and after measurements and must preserve renderer tests and visual behavior.

## Testing and deletion gates

Three-platform native CI starts with the Phase 0 scaffold. Renderer Playwright coverage continues. Tauri shell E2E uses WebdriverIO's embedded provider on macOS, Windows, and Linux, plus Rust/Go contract tests for behavior WebDriver cannot observe reliably. The embedded driver plugins compile and register only in explicit E2E builds and are absent from normal development and production artifacts.

The Flutter mobile client remains in the release gate. Its authenticated opt-in LAN connection and API behavior must continue passing while new desktop-only routes remain unreachable from the LAN listener.

Electron removal is the last phase and requires all of the following:

- Phase 0 decision permits implementation;
- signed install and update tests pass on all three platforms;
- every non-browser parity-ledger row passes;
- browser automation works without Electron;
- no renderer source imports from `frontend/src/main/`;
- production manifests contain no Electron, Forge, electron-updater, or Electron maker dependency;
- benchmark gates pass on checked-in results;
- the only removed behavior matches `docs/todo/browser-panel-webview.md`.

## Phases

| Phase | Content |
|---|---|
| 0 | Baselines; pinned Tauri scaffold; state-location and CORS proof; real terminal; standalone browser automation; RPM and updater-signing feasibility; explicit continue/stop decision. |
| 1 | Rust daemon supervisor, shell-neutral bridge, early three-platform CI. |
| 2 | Existing Go settings extension, one-time legacy import, loopback import utilities, telemetry bootstrap. |
| 3 | App marker, macOS relocation, native desktop integrations, dropped-file staging. |
| 4 | Production standalone agent-browser adapter; external preview; embedded panel removal. |
| 5 | Update domain, feeds, packaging, signing, notarization, and update E2E. |
| 6 | Measured renderer performance work. |
| 7 | Native E2E, parity audit, Electron deletion, CLI/bootstrap documentation, final release gates. |

The port is a large rewrite of the desktop shell and distribution pipeline. The plan intentionally uses small review gates so Subagent-Driven Development cannot hide a parity loss inside a broad final deletion.
