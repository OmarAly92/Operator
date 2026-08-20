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

Keeping full parity would require embedding a separate Chromium-class runtime or accepting the
capability losses above. Either choice conflicts with this port's size and parity goals. The
standalone automation browser is therefore installed only on demand and measured separately
from the base application.

## What replaced it

Two deliberately separate paths replace the panel:

- `opr preview` keeps the daemon-owned preview target. The running desktop observes a new
  preview revision, validates the target, and opens it in the user's default browser. The
  session inspector also provides a manual reopen action.
- Agent-facing browsing uses the packaged `agent-browser` command against an isolated
  standalone Chromium owned by the Go daemon. It does not attach to the user's default-browser
  profile. Operator discovers an installed compatible browser first and otherwise installs the
  pinned managed browser beneath `~/.operator/browser-engine` on first automation use.

This is a real architecture change. Today `agent-browser` receives `AGENT_BROWSER_CDP` for a
bridge whose targets are Electron `WebContents`; it is not already independent of the embedded
panel. The Tauri port must pass the standalone-browser Phase 0 gate before deleting that bridge.

What is lost is the in-window panel and the coupling between the visible preview and the
agent-controlled target. User preview and agent automation continue as separate windows.

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
