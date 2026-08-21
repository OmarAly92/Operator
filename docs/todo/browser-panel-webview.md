# Future: rebuild the browser panel on the OS webview

**Recorded:** 2026-08-16
**Status:** deferred, not scheduled
**Context:** `docs/superpowers/specs/2026-08-16-tauri-port-design.md`

## What this records

The Tauri base port defers the embedded browser panel (the inspector rail's Browser tab, and the
in-window target of `opr preview`) and, with it, the Electron implementation it depends on:
`frontend/src/main/browser-view-host.ts`, 2,079 lines built on Electron `WebContentsView`.

The approved future disposition is Task 16: remove the embedded panel from the Tauri base port and
replace it with two daemon-side paths — automatic external preview, and agent-facing automation in
the standalone browser owned by the Go daemon.

**Nothing here has shipped yet.** The embedded Electron Browser panel still exists in the desktop
app today, and neither replacement path is implemented. This page is a decision record for the
approved Task 16 disposition, not a change log.

## Why the embedded panel is removed rather than ported

The panel is not ported to the OS webview target (WKWebView / WebKitGTK / WebView2) because it
depends on Chromium APIs that target does not have:

| Capability | Electron API | OS webview |
|---|---|---|
| Network capture for agents | `webContents.debugger` + CDP `Network.enable` | none |
| Annotation snapshots | `capturePage()` | none cross-platform |
| Per-tab storage isolation | `partition:` | none |
| Popup interception | `setWindowOpenHandler` | none |
| In-window embedding | `WebContentsView` + synced bounds | partial, platform-divergent |

Keeping full parity would require embedding a separate Chromium-class runtime or accepting the
capability losses above. Either choice conflicts with this port's size and parity goals.

## Approved future disposition

Two deliberately separate paths replace the panel. Both are approved and implemented by later
tasks, not by the base port:

- **Automatic external preview (Task 16).** The daemon exposes `previewUrl`, `previewRevision`, and
  `previewOpenedRevision` on session updates. The desktop client preserves the daemon-owned preview
  target, opens each new revision once in the user's default browser through the validated HTTP(S)
  opener, and acknowledges it over a loopback-only route. The session inspector also keeps a manual
  reopen action that never changes the automatic-open acknowledgement.
- **Standalone agent automation (Task 15).** Agent-facing browsing uses the packaged
  `agent-browser` command against an isolated standalone Chromium owned by the Go daemon. It does
  not attach to the user's default-browser profile. Operator discovers an installed compatible
  browser first and otherwise installs the pinned managed browser beneath `~/.operator/browser-engine`
  on first automation use. Because it is separate from the base application, it is installed only
  on demand and measured separately.

Neither path exists today. `agent-browser` still receives `AGENT_BROWSER_CDP` for a bridge whose
targets are Electron `WebContents`; it is not already independent of the embedded panel. Task 15
must pass the standalone-browser Phase 0 gate before that bridge is deleted, and Task 16 removes
the embedded panel's renderer consumers before Task 21 deletes the now-dead Electron code.

Until Task 16 lands, the visible preview and the agent-controlled target remain coupled inside the
embedded panel. User preview and agent automation become separate windows only after it ships.

## If we rebuild it

Scope it to what the OS webview can actually do, and do not try to recover the CDP features.

**In scope:** a child webview in the main window, navigation (back/forward/reload/stop),
address bar, tabs, bounds synced to the panel layout.

**Out of scope, permanently:** panel-owned network capture, `capturePage` annotation, per-tab
partitions, and popup interception. Standalone agent automation retains its own console,
network, screenshot, and tab commands, but those results are not rendered as a native panel.

**Open questions to answer first:**

1. Does Tauri's multi-webview support cover child webviews with synced bounds on all three
   platforms, or only on some?
2. Can the annotation flow be rebuilt with an injected script instead of `capturePage`,
   accepting DOM-based capture instead of a real screenshot?
3. Is the panel worth it once `agent-browser` handles agent browsing — i.e. is the value
   convenience, or capability? If it is only convenience, this may never be worth building.

Answer 3 before 1 and 2.
