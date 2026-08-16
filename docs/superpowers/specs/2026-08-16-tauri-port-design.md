# Replacing Electron with Tauri — design

**Date:** 2026-08-16
**Status:** draft design, pending review
**Scope:** replace the Electron desktop shell in `frontend/` with Tauri, on macOS, Windows
and Linux

## Context

The desktop shell is Electron 33 driven by Electron Forge. Measured on a dev instance with an
**empty board and zero active sessions** — the idle floor, not a loaded app:

```
 61.1 MB  Electron main
 28.2 MB  GPU process
 20.9 MB  network utility
118.3 MB  renderer  ← the React app
 28.2 MB  renderer (second)
─────────
256.7 MB  resident, 5 processes
+57.3 MB  Go daemon (3 processes) — independent of the shell
```

On disk, `node_modules/electron/dist` is **242 MB**. The `agent-browser` binary is 12 MB and
the Go daemon ~30 MB; both ship regardless of shell.

The shell's own code is substantial:

| Area | Lines | Notes |
|---|---|---|
| `src/main.ts` | 1,961 | window, menu, IPC registration |
| `src/main/browser-view-host.ts` | 2,079 | embedded Chromium browser panel |
| `src/main/auto-updater.ts` | 924 | channels, feature builds, downgrade |
| `src/main/agent-browser-runtime.ts` | 926 | spawns + drives the `agent-browser` binary |
| `src/main/agent-browser-cdp-bridge.ts` | 422 | CDP bridge |
| remaining `src/main/*.ts` | ~2,900 | tray, settings, relocation, escalation, shortcuts |
| `src/preload.ts` | 351 | **17 namespaces, 78 exposed methods**, 43 IPC handlers |

### What the port is for

Bundle size, resident memory, startup time, and general smoothness — in that order of
confidence that Tauri delivers them. Approximately 110 MB of the 257 MB is shell overhead
(main + GPU + utility) that a Tauri shell reclaims. Install size goes from ~250 MB to roughly
~60 MB once the daemon and `agent-browser` are counted.

**The 118 MB renderer does not improve by changing shells.** It is React 19 + TanStack Router
+ Radix + Framer Motion + xterm holding the same objects, and WKWebView will hold
approximately the same ones. "Smooth and fast" therefore requires a renderer workstream that
is not the port; it is specified below and is not optional.

Those are the port's *goals*. Its binding *constraint* is the in-app terminal, which must not
regress on any platform — stated as the highest priority of the project. Where a goal and
that constraint conflict, the constraint wins. See "The terminal".

### Decisions taken

| Decision | Choice |
|---|---|
| Platforms | macOS + Windows + Linux — full parity with today |
| Shell logic | Thin Rust shell, daemon-adjacent logic moves to Go |
| Embedded browser panel | **Removed.** Drive the user's real browser via `agent-browser` |
| Panel follow-up | Record an OS-webview rebuild as a future todo, do not build it now |
| Rollout | Clean replacement. The app has no users; no migration or updater continuity needed |
| Node sidecar | Rejected — shipping a Node runtime defeats the size goal |
| **Terminal** | **The port's primary constraint.** `xterm.js` retained; no Rust emulator. See "The terminal" |

### Non-goals

- No feature work. The port reproduces current behaviour except where a decision above
  removes it.
- No redesign. See `2026-08-16-appskin-theming-design.md`, which is independent of this work.
- No new platforms.

## The decision that shapes everything: the browser panel

`browser-view-host.ts` is built on Chromium APIs with no equivalent in WKWebView or
WebKitGTK:

| Used today | Tauri equivalent |
|---|---|
| `webContents.debugger.attach("1.3")` + `Network.enable` (`:1693`, `:1726`) | none |
| `capturePage()` for annotation snapshots (`:956`) | none cross-platform |
| per-tab `partition:` storage isolation (`:468`) | none |
| `setWindowOpenHandler` popup interception (`:1511`) | none |
| `WebContentsView` embedding with synced bounds | partial, platform-divergent |

Keeping the panel means shipping a Chromium, which is the 242 MB the port exists to delete.
The panel is therefore **removed**, and the capability it provided is relocated:
`agent-browser` (vercel-labs, 12 MB) is already a separate browser process driven over CDP,
so agent-facing browsing continues to work unchanged. What is lost is the *in-window* panel —
`opr preview` opens and drives the user's real browser instead.

This deletes 2,079 lines and the port's single hardest subsystem. A future rebuild on the OS
webview (navigation and tabs only, no CDP) is recorded in `docs/todo/browser-panel-webview.md`
and is explicitly out of scope.

## Architecture: thin shell, fat daemon

Rust owns only what must be native. Everything else moves into the Go daemon, where it
becomes reachable by the Flutter mobile client for free — `packages/mobile` already proves
the daemon-centric model works over REST + WebSocket.

```
┌───────────────────────────────────────────────┐
│ Tauri shell (Rust)                            │
│  window · menu · tray · global shortcuts      │
│  notifications · clipboard · dialogs          │
│  external-open · updater · daemon supervisor  │
└───────────────┬───────────────────────────────┘
                │ tauri commands (thin)
┌───────────────▼───────────────────────────────┐
│ Renderer (React) — unchanged                  │
└───────────────┬───────────────────────────────┘
                │ REST + WebSocket + SSE
┌───────────────▼───────────────────────────────┐
│ Go daemon — settings, app-state, keybindings, │
│ folder scan, relocation, telemetry,           │
│ agent-browser orchestration                   │
│                  ▲                            │
│                  └── packages/mobile (Flutter)│
└───────────────────────────────────────────────┘
```

Rust surface lands around 1,500–2,000 lines rather than the ~5,000 a 1:1 port would need, and
the logic that moves to Go arrives in a language that already has a test suite here.

### IPC disposition — 17 namespaces, 78 methods

| Namespace | Methods | Disposition |
|---|---|---|
| `app` | 5 + 11 shortcut listeners | `getVersion`/`chooseDirectory`/`openExternal` → Rust; `scanImportFolder`/`checkAncestorRepo` → **Go**; shortcut listeners → Rust accelerators |
| `daemon` | 5 | **Rust** — the supervisor owns the child process; cannot move |
| `window` | 3 | **Rust** |
| `menu` | 2 | **Rust** |
| `tray` | 2 | **Rust** |
| `clipboard` | 2 | **Rust** (`tauri-plugin-clipboard-manager`) |
| `notifications` | 4 | **Rust** — badge handling is per-platform |
| `updates` / `featureBuilds` | 8 | **Rust** (`tauri-plugin-updater`); channel state → Go |
| `theme` | 2 | **Rust** for the native colour-scheme hint; the skin itself is renderer state |
| `terminal` | 1 | **Rust** (file drop into the session cwd) |
| `uiSettings` | 2 | **Go** — shared with mobile |
| `updateSettings` | 2 | **Go** |
| `keybindings` | 2 | **Go** — shared with mobile |
| `appState` | 2 | **Go** |
| `telemetry` | 1 | **Go** |
| `browser` | 22 | **Deleted.** Agent browsing → Go-orchestrated `agent-browser` |

The 22-method `browser` namespace is the largest in the preload and it disappears entirely —
the clearest evidence that the panel decision is what makes this port tractable.

### Daemon supervision

`daemon-owner.ts`, `supervisor-link.ts` and the `running.json` handshake port to Rust
essentially unchanged in shape: spawn the binary, own its lifetime, write the run file, poll
health, expose status to the renderer. This is the one subsystem where Rust is a clear
improvement over Node — process supervision, signal handling and cleanup on abnormal exit are
all better served.

**`~/.operator` remains the only state location.** The hard rule in `AGENTS.md` and
`CLAUDE.md` applies to Tauri exactly as it applied to Electron: the webview's data directory
must be pinned under `~/.operator` (Tauri's equivalent of `frontend/src/main.ts`'s `userData`
override), never an OS-default app-data path.

## The terminal — the port's primary constraint

**Stated priority: the in-app terminal matters more than anything else in this port.** It is
therefore not a risk to be checked but a constraint the design is built around, and the
acceptance criteria below gate the whole project.

### What the port does and does not change

The terminal's data path does not involve the shell at all:

```
Go daemon (creack/pty, internal/adapters/runtime/ptyexec/)
      │  WebSocket mux
      ▼
renderer — xterm.js (@xterm/xterm 5.5)
```

The renderer attaches over `lib/terminal-mux.ts` to the same multiplexed socket
`packages/mobile` uses. The Electron main process never sees a terminal byte, so **the port
changes exactly one variable: which browser engine executes xterm.js.** No IPC, no transport,
no emulator, no PTY code moves.

### Package decision: xterm.js stays

| Option | Verdict |
|---|---|
| **`@xterm/xterm` + WebGL/canvas addons (today)** | **Keep.** Industry standard; `XtermTerminal.tsx` is 1,004 lines of resolved edge cases — async font metrics, fit stabilization, WebGL atlas warm-up transients, macOS overlay-scrollbar reservation, tmux SGR scroll path, context-loss recovery |
| `alacritty_terminal` / `wezterm-term` in Rust | **Reject.** These are emulator state machines; the daemon already is one, and mobile shares it. A Rust emulator would parse the mux stream only to hand cells back to the webview for drawing — a process hop and an emulator fork for zero rendering gain. Native terminal speed comes from native rendering, which cannot composite into a webview |
| hterm or a custom canvas renderer | **Reject.** Older, DOM-based, and re-litigates every bug already solved in `XtermTerminal.tsx` |

The renderer ladder already implemented at `XtermTerminal.tsx:78-101` is the right one and is
retained unchanged: **WebGL → canvas → fail loudly.** The DOM renderer stays excluded because
it does not rasterize box-drawing glyphs onto the cell grid, which visibly breaks TUIs.

### Known hazard: WebKitGTK compositing

Tauri applications commonly set `WEBKIT_DISABLE_COMPOSITING_MODE=1` to work around WebKitGTK
rendering defects. That flag disables GPU compositing and would drop the terminal to the
canvas renderer on Linux. Whether Operator needs the flag, and what it costs when set, is a
phase 0 measurement — not an assumption in either direction.

### Acceptance criteria

Measured against the current Electron build as the baseline, on each of the three engines
(WKWebView, WebView2, WebKitGTK):

| Criterion | Bar |
|---|---|
| Throughput — `vtebench` (Alacritty's benchmark suite) and a large `cat` | ≥ 90% of the Electron baseline |
| Full-screen TUI redraw — `vim`, `htop`, an agent TUI | No visible tearing or dropped frames at the app's default grid size |
| Glyph correctness | Box-drawing, powerline, emoji, and CJK width render identically to baseline |
| Scrollback + selection | Smooth over the app's configured scrollback limit |
| Font-metric stability | No mis-counted cols/rows on open or resize — the class of bug `XtermTerminal.tsx:643-690` exists to prevent |
| Renderer landed on | WebGL on macOS and Windows. Linux may land on canvas only if it still meets the throughput bar |

**These criteria are the phase 0 kill gate.** If an engine cannot meet them, the options are
to drop that platform, accept canvas rendering there, or abandon the port — decided with
numbers in hand, in week one.

## The renderer workstream

Not optional, and not caused by the port — but the port is worthless for "smooth and fast"
without it. A 118 MB idle renderer is the largest single memory consumer in the app and it
survives the shell swap intact.

1. **Profile before cutting.** Heap snapshot on an empty board; identify what holds 118 MB.
2. **Route-level code splitting.** TanStack Router supports lazy routes; the board should not
   pay for the terminal, chat, diff viewer and settings on first paint.
3. **Audit Framer Motion.** `motion` is a heavy dependency; measure what it buys against CSS
   transitions for the cases actually used.
4. **xterm lifecycle.** Confirm terminals are disposed, not merely hidden, when sessions close.
5. **Measure cold start end to end.** Current perceived startup includes the daemon handshake
   (`DaemonStartupLoader`), not just Chromium boot — the shell may not be the bottleneck.

Each item is verified by a before/after number, not by inspection.

## Packaging, signing, updating

This is roughly a third of the project and it is rebuilt from zero. Today's pipeline is
mature: signed + notarized + stapled DMG (with a separately sealed dmg container), NSIS for
Windows, AppImage + deb + rpm for Linux, GitHub publisher, and `latest`/`nightly` channels
plus per-PR `pr<N>` feature-build channels with `allowDowngrade`.

| Concern | Electron today | Tauri |
|---|---|---|
| macOS | Forge + `osxSign`, notarize, custom `maker-dmg` seal | `tauri build`, same Apple identities, DMG resealing to re-verify |
| Windows | custom `maker-nsis` | Tauri NSIS target |
| Linux | `maker-appimage` + deb + rpm | Tauri AppImage + deb; **rpm needs verification** |
| Update manifest | `latest-*.yml` (electron-updater) | `latest.json` + **minisign** keys |
| Channels | `latest` / `nightly` / `pr<N>` | No native concept — **must be rebuilt** by hand over the updater plugin |

The channel system is the piece most likely to be underestimated: `auto-updater.ts` is 924
lines and `mac-update-e2e.yml` exists specifically to guard it. Having no users removes the
*migration* risk entirely, but not the *rebuild* cost.

## Testing

`test:e2e` drives Electron through Playwright, and `test:e2e:renderer` drives `dev:web`.

- **Renderer E2E survives.** `dev:web` is shell-agnostic; `@T0|@P0` keeps running unchanged.
- **Shell E2E does not.** Playwright cannot drive WKWebView or WebKitGTK. Replacement is
  `tauri-driver` over WebDriver, which is meaningfully less capable — expect to lose coverage
  and to compensate with Rust unit tests around the supervisor, updater and settings paths.
- **Go tests gain.** Everything that moves to the daemon becomes testable in Go, which is a
  net improvement over the current Vitest-with-Electron-mocks arrangement.

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **xterm on WebKitGTK** — the WebGL addon degrades or breaks; the terminal is the stated priority of the port | **Highest** | Acceptance criteria in "The terminal"; measured in phase 0. This is the kill criterion. Partly mitigated already: the WebGL→canvas ladder ships today |
| Channel/updater rebuild underestimated | High | Scope it as its own phase with its own plan |
| Three webview engines, three behaviours | High | CI matrix from phase 1; no "works on my Mac" merges |
| Renderer work doesn't land and the app feels the same | High | Numbers before and after, per item |
| Rust learning curve on a 3-platform shell | Medium | Thin-shell architecture is partly chosen to minimise exposure |
| rpm target unsupported by Tauri | Medium | Verify in phase 0; fall back to packaging rpm separately |
| Losing the browser panel is missed in practice | Medium | Decision taken with eyes open; todo file records the rebuild path |

### Phase 0 is a kill gate

Before any port work: build a bare Tauri window on all three platforms, mount the app's real
`XtermTerminal` component against a live daemon mux socket, and evaluate every row of the
acceptance criteria in "The terminal" — **WebKitGTK especially, and with
`WEBKIT_DISABLE_COMPOSITING_MODE` measured both on and off.** Use the app's own component
rather than a bare xterm instance; the 1,004 lines of font-metric and fit handling are
exactly what a naive prototype would omit and then rediscover in month three. Also verify the
rpm target and minisign signing.

If an engine cannot meet the bar, the options are: drop that platform, accept canvas
rendering there, or abandon the port. That question must be answered in week one. No other
work starts until it is.

## Phasing

| Phase | Content |
|---|---|
| **0** | Feasibility gate: the real `XtermTerminal` against a live mux on all three webviews, scored against the terminal acceptance criteria; rpm target; minisign. Kill criteria evaluated |
| **1** | Tauri shell with window + menu + daemon supervisor; renderer boots and reaches the daemon |
| **2** | Move `uiSettings`, `updateSettings`, `keybindings`, `appState`, `telemetry`, folder scan, relocation into Go; mobile picks them up free |
| **3** | Native surface in Rust: tray, notifications, shortcuts, clipboard, dialogs, external-open |
| **4** | Remove the browser panel; reroute `opr preview` and agent browsing through `agent-browser` |
| **5** | Packaging + signing on three platforms; updater and channels rebuilt |
| **6** | Renderer performance workstream |
| **7** | Delete `frontend/src/main*`, Forge config and Electron deps; E2E moved to `tauri-driver` |

Phases 1–4 are individually shippable to a dev build. Phase 7 is the point of no return and
should not begin until phase 5 has produced a signed artifact on all three platforms.
