# Relaunch Agent Fresh — Design

**Date:** 2026-09-12
**Status:** Approved design, not yet implemented
**Goal:** Give the session agent tab a right-click menu that kills the running TUI and relaunches it on a clean conversation, replacing the hand gesture of Ctrl-C'ing out of the pane and restarting by hand.

## 1. Problem

Right-clicking an agent tab in the session pane produces the WKWebView default
menu — Back, Reload, Inspect Element. `SessionPaneTab`
(`frontend/src/renderer/components/CenterPane.tsx:384`) binds no
`onContextMenu`, so the webview's own menu wins. Nothing about that menu is
useful inside the app.

The gesture it should offer is one users already perform by hand: abandon the
agent's current conversation and start it again clean. Today that means typing
`/clear`, Ctrl-C'ing twice out of the TUI, and waiting for a relaunch — or
killing the session outright and losing the worktree.

No daemon operation does this. The two adjacent ones both refuse:

- **`ResumeAgentWithMode`** (`backend/internal/session_manager/manager.go:1351`)
  rejects a live agent — `rec.Activity.State != domain.ActivityExited` returns
  `ErrAgentNotExited` (`:1366`). It also *prefers native resume*, which is the
  opposite of clearing.
- **`Kill`** (`backend/internal/session_manager/manager.go:1068`) is a full
  session teardown: it stops the preview, destroys the browser, and unwinds
  workspace rows. It does not restart anything.

## 2. The Claude Code trap

The naive implementation is wrong, and wrong silently. Blanking
`SessionMetadata.AgentSessionID` does **not** produce a clean conversation for
Claude Code:

- `GetRestoreCommand` falls back to a UUID derived deterministically from the
  Operator session id when the metadata id is empty
  (`backend/internal/adapters/agent/claudecode/claudecode.go:258`–`:261`).
- `GetLaunchCommand` pins that same derived UUID via `--session-id`
  (`backend/internal/adapters/agent/claudecode/claudecode.go:179`–`:180`).

So a relaunch that merely clears the stored id hands Claude Code the identity of
the transcript just abandoned, and the old conversation comes straight back.

The mechanism to avoid this already exists and is already in use by agent
switching:

- `LaunchConfig.NativeSessionID` (`backend/internal/ports/agent.go:386`)
  overrides the derivation with a caller-assigned id.
- `ContinuationCapabilities.FreshNativeSessionID`
  (`backend/internal/ports/agent_continuation.go:23`) reports which adapters
  accept a caller-assigned id for a *fresh* conversation; its absence is
  deliberately treated as unsupported rather than assumed
  (`backend/internal/ports/agent_continuation.go:27`–`:29`).
- Agent switching mints fresh native ids through exactly this pair
  (`backend/internal/session_manager/agent_switching.go:784`, `:816`).

Relaunch-fresh reuses that machinery. It invents no new identity handling.

## 3. Scope

Two menu items on the session's own agent tab — orchestrator and worker:

1. **Relaunch in a cleared session.** No native resume, no prompt replay. The
   agent comes back with its system prompt only.
2. **Relaunch and replay the task.** Fresh conversation, but the worker's saved
   task prompt is re-delivered. Shown only when a saved prompt exists, so
   orchestrators never see it.

Both kill the running agent process and both confirm first.

**The reviewer tab is excluded, for a structural reason.** `reviewerTerminal` is
`{ handleId: string; harness: string }`
(`frontend/src/renderer/components/CenterPane.tsx:33`) — a runtime handle, not a
session. The relaunch endpoint is keyed by `sessionId`, so the reviewer tab has
nothing to send. Reviewers have their own lifecycle surface
(`/sessions/{sessionId}/reviews/restore`, `/reviews/kill`, `/reviews/switch` —
`backend/internal/httpd/controllers/reviews.go:103`–`:105`), and extending
relaunch to them means designing against that subsystem instead. Deferred.

Out of scope: any change to `Kill`, to `RestoreWithMode`, or to the terminal
renderer. `TERMINAL.md`'s verify recipe does not apply — no code under
`packages/terminal` or the pty-host is touched.

## 4. Backend

### 4.1 `relaunchPolicy`

`relaunchSessionWithPolicy` (`backend/internal/session_manager/manager.go:1394`)
is already named for a policy it does not yet take. Add one:

```go
type relaunchPolicy struct {
	forceFresh bool
	keepPrompt bool
}
```

`relaunchSession` passes the zero value, preserving today's behavior for
restore and resume exactly.

When `forceFresh` is set, the argv branch at
`backend/internal/session_manager/manager.go:1430` changes:

- Skip `restoreArgv` — and therefore `GetRestoreCommand` — entirely. This is
  required, not merely tidier, for the reason in section 2.
- Call `freshLaunchArgv(..., allowPromptless: true)` against a copy of
  `rec.Metadata` with `AgentSessionID` blanked, and `Prompt` blanked unless
  `keepPrompt`.
- When the adapter reports `FreshNativeSessionIDCallerAssigned`, mint a new
  native session id and pass it as `LaunchConfig.NativeSessionID`.

Blanking `AgentSessionID` on the copy also disables the switched-continuation
handoff carry-over for free: `systemPromptForNativeRestore` returns its input
unchanged when the native id is empty
(`backend/internal/session_manager/agent_switching.go:855`–`:858`). That is
correct — a handoff artifact describes a conversation being discarded.

`MarkSpawned`'s metadata (`backend/internal/session_manager/manager.go:1475`)
must carry the blanked `AgentSessionID`, not `rec.Metadata.AgentSessionID`, so
the discarded native id is not re-persisted. The provider's lifecycle hooks
record the new one.

With `keepPrompt` set, `freshLaunchArgv` returns `RestoreModeSavedPrompt`
(`backend/internal/session_manager/manager.go:3433`–`:3435`) and the existing
after-start delivery branch (`backend/internal/session_manager/manager.go:1484`)
replays the task. No new delivery code.

### 4.2 `RelaunchAgentFresh`

A method beside `ResumeAgentWithMode`, same body, with these differences:

- No `ActivityExited` guard. A live agent is the expected input.
- Keeps the `ErrTerminated` and `ErrIncompleteHandle` guards unchanged.
- Passes `relaunchPolicy{forceFresh: true, keepPrompt: …}`.

The process kill needs no new code. `restartRuntime`
(`backend/internal/session_manager/manager.go:1510`) already probes liveness and
either calls `ports.RuntimeRestarter.Restart` — which the pty-host implements
(`backend/internal/adapters/runtime/ptyhost/runtime.go:23`) — or destroys and
recreates. Reusing the existing runtime handle keeps the pane's terminal
identity, so the user's tab does not move.

### 4.3 Concurrency

A new `agentOperationRelaunch` kind in
`backend/internal/session_manager/session_input.go:16`, acquired via
`beginAgentOperation`. This makes relaunch mutually exclusive with switch, kill,
resume, retire and restore, and drains in-flight pane writes before the process
is replaced — the same protection every other exclusive operation gets.

### 4.4 Service and HTTP

`Service.RelaunchAgent` mirroring `Service.ResumeAgent`
(`backend/internal/service/session/service.go:548`), returning the same outcome
shape. No new sentinel errors: every failure mode is already mapped by
`toAPIError` (`backend/internal/service/session/service.go:845`).

`POST /api/v1/sessions/{sessionId}/relaunch-agent`, registered beside
`resume-agent` (`backend/internal/httpd/controllers/sessions.go:205`), handler
mirroring `resumeAgent` (`:1090`). Request body `{"keepPrompt": bool}`,
defaulting false. Response reuses the `ResumeAgentResponse` shape
(`backend/internal/httpd/controllers/dto.go:592`) under a new type name. OpenAPI
entry beside `backend/internal/httpd/apispec/openapi.yaml:2963`.

### 4.5 `hasSavedPrompt`

The saved task prompt lives on `SessionMetadata`
(`backend/internal/domain/session.go:37`), which is not serialized to the wire.
The renderer therefore cannot tell whether the replay item applies.

Add a computed boolean `hasSavedPrompt` to `SessionView`
(`backend/internal/httpd/controllers/dto.go:141`), set in `sessionView()`. One
field. Without it the replay item is a button that fails on click with
`SESSION_NOT_RESUMABLE`; with it, the item is simply absent.

Orchestrators are promptless by design
(`backend/internal/session_manager/manager.go:3402`), so this is false for them.

## 5. Frontend

### 5.1 Menu

Wrap `SessionPaneTab`'s outer `<span>`
(`frontend/src/renderer/components/CenterPane.tsx:390`) in
`ContextMenuTrigger asChild`, following the project-row precedent at
`frontend/src/renderer/components/Sidebar.tsx:567`. Radix's `contextmenu`
`preventDefault` is what suppresses the WKWebView menu.

Items, from `frontend/src/renderer/components/ui/context-menu.tsx`:

- *Relaunch in a cleared session* — enabled whenever the session is live.
- *Relaunch and replay the task* — rendered only when `hasSavedPrompt`.

Each opens `ConfirmDialog`
(`frontend/src/renderer/components/ConfirmDialog.tsx`) before firing. Both kill
a running agent and discard its conversation; neither is undoable.

### 5.2 Client

`useRelaunchAgent`, a mutation hook beside
`frontend/src/renderer/hooks/useSwitchAgent.ts`, invalidating
`workspaceQueryKey` on success. The path is added to the `apiClient` allowlist
at `frontend/src/renderer/lib/api-client.ts:89`.

Copy is inline via `t()` keys in the renderer's translation catalogue,
matching the surrounding `terminal.*` keys.

## 6. Testing

**Manager** (`backend/internal/session_manager/manager_test.go`):

- Forced-fresh argv contains no resume flag and carries a `--session-id`
  distinct from `claudeSessionUUID(sessionID)`. This is the regression guarding
  section 2 and is the single most important test in the change.
- A live, non-exited agent is accepted where `ResumeAgentWithMode` returns
  `ErrAgentNotExited`.
- `keepPrompt: false` blanks the prompt and yields `RestoreModeFresh`;
  `keepPrompt: true` yields `RestoreModeSavedPrompt`.
- The persisted metadata after relaunch does not carry the pre-relaunch
  `AgentSessionID`.
- A concurrent switch is rejected while a relaunch holds the operation lock.

**Controller** (existing sessions controller tests): 200 body shape, and the
409 mapping for a terminated session.

**Renderer** (`frontend/src/renderer/components/CenterPane.test.tsx`):
right-click opens the menu and the WKWebView default menu is suppressed; the
replay item is absent for an orchestrator;
confirm-then-fire posts to the endpoint exactly once.

## 7. Risks

**A harness with no continuation capability.** Adapters that do not implement
`AgentContinuationCapabilityProvider` are treated as provider-assigned, so no
`NativeSessionID` is passed and the provider picks its own identity. For those
harnesses "cleared" depends on the provider not auto-resuming. This is the same
assumption agent switching already makes, and no worse.

**A stale saved prompt.** `keepPrompt` replays whatever prompt is on the record,
which for a long-running worker may be far behind the actual task. This is
identical to what `restore` does today for a terminated worker, so it introduces
no new surprise.
