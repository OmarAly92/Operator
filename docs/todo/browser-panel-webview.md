# Future: rebuild the browser panel on the OS webview

**Recorded:** 2026-08-16
**Updated:** 2026-08-24 (Task 16 shipped; Task 21 deleted the remaining Electron implementation)
**Status:** deferred, not scheduled
**Context:** `docs/superpowers/specs/2026-08-16-tauri-port-design.md`

## What this records

The Tauri port removed the embedded browser panel (the inspector rail's Browser tab, and the
in-window target of `opr preview`) instead of porting it to the OS webview target. The renderer
side is gone as of Task 16, and Task 21 deleted the Electron-only implementation it depended on —
`frontend/src/main/browser-view-host.ts`, the `preload.browser` namespace, and the Go
`internal/browserruntime` broker that served it.

Two daemon-side paths replace the panel:

- **Automatic external preview (Task 16, shipped).** The daemon persists a durable
  `preview_opened_revision` per session (`0089_preview_open_ack.sql`). A validated HTTP(S)
  preview target opens once per new revision in the user's default browser through the existing
  `open_external` opener command, then acknowledges it over the loopback-only route
  `POST /internal/desktop/sessions/{id}/preview-opened`. Acknowledged revisions never re-open
  after a restart or rerender; pending ones do. Manual reopen from the session inspector opens
  externally and never touches the acknowledgement.
- **Standalone agent automation (Task 15, shipped).** Agent-facing browsing uses the packaged
  `agent-browser` command against an isolated standalone Chromium owned by the Go daemon,
  separate from the user's default browser.

## What was deliberately dropped with the panel

| Capability | Disposition |
|---|---|
| In-window page rendering | Dropped — previews open in the user's default browser |
| Tabs, address bar, back/forward/reload controls | Dropped with the panel |
| DevTools toggle inside the app | Dropped — use the browser's own tools |
| Annotation capture (`capturePage` snapshots sent to the agent) | Dropped; agents screenshot via the standalone browser instead |
| Native composition overlay handling | Dropped — no native view is composited over the window |
| Agent-browser activity glow / unseen indicator on the Browser tab | Dropped with the tab |

`opr preview start/status/stop/clear`, relative-file previews, the preview-server lifecycle, and
the daemon preview routes are preserved unchanged; only where the target renders changed.

## Why the embedded panel was removed rather than ported

The panel was not ported to the OS webview target (WKWebView / WebKitGTK / WebView2) because it
depends on Chromium APIs that target does not have:

| Capability | Electron API | OS webview |
|---|---|---|
| Network capture for agents | `webContents.debugger` + CDP `Network.enable` | none |
| Annotation snapshots | `capturePage()` | none cross-platform |
| Per-tab storage isolation | `partition:` | none |
| Popup interception | `setWindowOpenHandler` | none |
| In-window embedding | `WebContentsView` + synced bounds | partial, platform-divergent |

Keeping full parity would have required embedding a separate Chromium-class runtime or accepting
the capability losses above. Either choice conflicted with this port's size and parity goals.

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
