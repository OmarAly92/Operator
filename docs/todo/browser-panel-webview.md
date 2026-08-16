# Future: rebuild the browser panel on the OS webview

**Recorded:** 2026-08-16
**Status:** deferred, not scheduled
**Context:** `docs/superpowers/specs/2026-08-16-tauri-port-design.md`

## What was removed and why

The Tauri port removes the embedded browser panel (the inspector rail's Browser tab, and the
in-window target of `opr preview`). It was `frontend/src/main/browser-view-host.ts`, 2,079
lines built on Electron `WebContentsView`.

It was removed rather than ported because it depends on Chromium APIs that WKWebView and
WebKitGTK do not have:

| Capability | Electron API | OS webview |
|---|---|---|
| Network capture for agents | `webContents.debugger` + CDP `Network.enable` | none |
| Annotation snapshots | `capturePage()` | none cross-platform |
| Per-tab storage isolation | `partition:` | none |
| Popup interception | `setWindowOpenHandler` | none |
| In-window embedding | `WebContentsView` + synced bounds | partial, platform-divergent |

Keeping it would have meant shipping a Chromium — the 242 MB the port exists to remove.

## What replaced it

Agent-facing browsing is unaffected: `agent-browser` (vercel-labs, 12 MB) is already a
separate browser process driven over CDP, orchestrated by the Go daemon. `opr preview` opens
and drives the user's real browser.

What is actually lost is the *in-window* panel: browsing beside the session instead of in
another application.

## If we rebuild it

Scope it to what the OS webview can actually do, and do not try to recover the CDP features.

**In scope:** a child webview in the main window, navigation (back/forward/reload/stop),
address bar, tabs, bounds synced to the panel layout.

**Out of scope, permanently:** network capture, `capturePage` annotation, per-tab partitions,
popup interception. If an agent needs those, it uses `agent-browser`, which is the right tool
and already exists.

**Open questions to answer first:**

1. Does Tauri's multi-webview support cover child webviews with synced bounds on all three
   platforms, or only on some?
2. Can the annotation flow be rebuilt with an injected script instead of `capturePage`,
   accepting DOM-based capture instead of a real screenshot?
3. Is the panel worth it once `agent-browser` handles agent browsing — i.e. is the value
   convenience, or capability? If it is only convenience, this may never be worth building.

Answer 3 before 1 and 2.
