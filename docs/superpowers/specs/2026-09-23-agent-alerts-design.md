# Agent alerts: turn finished, needs input, agent exited — on the Mac and the phone

**Date:** 2026-09-23
**Decision owner:** Omar Aly
**Status:** approved design, not yet implemented
**Scope:** `backend/`, `frontend/` (renderer and `src-tauri`), `packages/mobile`

## 1. Why

The most frequent event in the user's day is "the agent finished its turn, go
look". Operator is silent for it: a finished turn maps to `idle`
(`backend/internal/adapters/agent/claudecode/activity.go:39`) and the only
session notification fires on entering the needs-input family
(`backend/internal/lifecycle/manager.go:657`). The notification kinds are
`needs_input`, `ready_to_merge`, `pr_merged`, `pr_closed_unmerged` and nothing
else (`backend/internal/domain/notification.go:11-20`).

What exists does not reach the user either:

- On macOS the toast goes through `tauri-plugin-notification` 2.3.3, which
  calls `notify-rust` on the deprecated NSUserNotification API, posts as
  `com.apple.Terminal` in dev, and discards every error
  (`tauri-plugin-notification-2.3.3/src/desktop.rs:208-218`,
  `let _ = notification.show()`). On 2026-09-22 the user ran the shell-block
  toast test and nothing appeared. `defaults read com.apple.ncprefs apps` has no
  entry for Operator on this Mac, so macOS has never registered it as a
  notification sender. The installed app is ad-hoc signed
  (`codesign -dv`: `Signature=adhoc`, `TeamIdentifier=not set`).
- Clicking a toast cannot open anything: `route_click` is called only from a
  test (`frontend/src-tauri/src/notification_policy.rs:178`). The renderer
  already listens for the click (`NotificationCenter.tsx:136`).
- Every toast is dropped while the Operator window is focused
  (`notification_policy.rs:25`), so a session finishing in another tab or split
  pane is silent while the user works in Operator.
- The phone never alerts. The daemon runs an Expo push dispatcher
  (`backend/internal/daemon/daemon.go:383`, `internal/push/`) inherited from the
  deleted React Native app, and the Flutter client's only token source is
  `UnconfiguredPushTokenSource`
  (`packages/mobile/lib/feature/notification/logic/push_token_source.dart:19`),
  so no device ever registers.

## 2. Decisions (made in conversation, 2026-09-23)

| # | Decision |
|---|---|
| D1 | Alert on three events: **turn finished**, **needs input** (existing), **agent exited**. CI failure and merge conflict alerts were considered and dropped. Existing `ready_to_merge`, `pr_merged`, `pr_closed_unmerged` stay as they are. |
| D2 | Mac: toast **unless that exact session is on screen in a focused Operator window**. |
| D3 | Phone, app not running: **ntfy** via the public `ntfy.sh` server and the free ntfy iOS app. No Firebase project, no APNs key, no Apple Developer account. |
| D4 | Phone, Operator app open: the app raises its **own local notification**, skipping the session being viewed. |
| D5 | The phone gets every alert the Mac gets ("always both"), **only while Connect Mobile is on and a phone is paired**. Paired means paired, not "socket open": a locked phone still gets ntfy. |
| D6 | ntfy messages carry the session display name and the event only, never terminal output or assistant text. |
| D7 | macOS toasts move to **UNUserNotificationCenter** through `objc2`, gated by a step-0 check on the installed ad-hoc build. Fallback if Apple refuses: keep the plugin and add a click path through `mac-notification-sys` (approach B). |
| D8 | The phone sender sits behind an interface so a direct-APNs sender can replace ntfy later if a paid Apple account appears. Nothing else changes when that happens. |
| D9 | Delete the Expo push path and the Flutter push scaffolding; rename the mobile deep-link scheme `aomobile` to `operator`. Breaking changes and data resets are free ([[operator-has-no-users-yet]]). |

Why not a daemon-to-phone channel of our own: iOS suspends a backgrounded app
within seconds and closes its sockets, and only APNs can wake it or show a
remote notification. APNs needs a paid Apple Developer membership and a push
entitlement, which Operator does not have (`docs/STATUS.md`, "macOS signing and
notarization"). ntfy.sh is free ("As long as you don't abuse it, it'll be
available and free of charge", ntfy FAQ) and its iOS app receives instantly for
topics on ntfy.sh because ntfy.sh owns the APNs connection.

## 3. Step 0 — checks on real devices before feature code

Each result is written into this section before Task 1 starts. A failed check
changes the plan as stated; nothing is built on an unverified assumption.

1. **UNUserNotificationCenter from the installed ad-hoc app.** Build a release
   bundle, install to `/Applications`, request authorization, post one
   notification, click it. Record: prompt shown, toast shown, delegate
   `didReceiveNotificationResponse` called with the id. *If any fails, use
   approach B (D7) and record why.*
2. **Stop on interrupt.** Start Claude Code under Operator, send a long prompt,
   press Esc. Record whether `opr hooks claude-code stop` fires (the hooks log
   under the data dir). *Either result keeps §4.4's keystroke rule; this only
   records whether it is load-bearing.* The comment at `activity.go:39-43` says
   it fires; that claim is unverified.
3. **ntfy on the user's iPhone.** Install ntfy from the App Store (confirm it is
   free). Record: whether `ntfy://ntfy.sh/<topic>` opens the subscribe screen;
   whether a message sent with `Click: operator://session/<id>` opens Operator
   on tap (after the scheme rename, or test with `aomobile://` first).
4. **ntfy.sh limits.** Send 20 messages in quick succession to a throwaway
   topic; record any `429`. The published default is 60 burst then one per
   10 s (ntfy FAQ); a daily cap on ntfy.sh is not documented — "not known"
   until observed.

## 4. Events

### 4.1 Turn finished (new type `turn_finished`)

- Fires in lifecycle when a live, non-terminated session transitions
  `active → idle`. That transition is Claude's `stop` hook
  (`activity.go:39`); `SubagentStop` does not map to an activity state and does
  not fire it.
- One per turn. The next `user-prompt-submit` resolves the open
  `turn_finished` for that session, the same way leaving the needs-input family
  resolves `needs_input` (`manager.go:668`, `needsInputResolutions`).
- Title `"<display name> finished"`. Body on the Mac and in the app: the first
  ~120 characters of the session's `LatestAssistantUpdate` (captured from the
  Stop hook, `backend/internal/cli/hooks.go:196-221`, capped at 16 KiB). Body
  on ntfy: none (D6).

### 4.2 Needs input (existing `needs_input`)

Trigger unchanged (`manager.go:657`). It now also reaches the phone and obeys
§4.4.

### 4.3 Agent exited (new type `agent_exited`)

- Fires when a session enters `exited` **without** a user action causing it:
  - `session-end` with reason `logout`, `prompt_input_exit` or `other`
    (`activity.go:97-108`; `clear` and `resume` already map to no state);
  - the reaper observing runtime alive / workload dead
    (`lifecycle/manager.go:429-436`);
  - the reaper terminating a runtime that is clearly dead
    (`lifecycle/manager.go:455-466`).
- Only those two sources may emit it: the activity signal path and
  `ApplyRuntimeObservation` (`lifecycle/manager.go:413`). `MarkTerminated`
  (`lifecycle/manager.go:1097`) never emits it. `MarkTerminated` has ten callers
  (`session_manager/manager.go:968,1087,1105,1123,1462,1585,1649,1653,2050`,
  `lifecycle/reactions.go:545`) covering Kill, cleanup, relaunch, the startup
  reconcile after a reboot, and terminate-on-merge; none of them is the agent
  leaving on its own.
- **Race:** Kill and agent switch stop the process before `MarkTerminated`, so
  the reaper can observe "workload dead" first. The first branch of
  `ApplyRuntimeObservation` (`:429-436`) does not check
  `sessionMutationInProgress`, unlike the terminate branch (`:440`). The
  session manager must register the mutation before it stops the process, and
  the observation must not emit `agent_exited` while one is in progress. The
  plan gives Kill, cleanup, relaunch, agent switch, rollback, `/clear` and
  `resume` a negative test each, including this race.
- Title `"<display name> exited"`.

### 4.4 Suppression

Applied in this order; the first match suppresses on the channel named.

| Rule | Mac toast | Phone in-app | ntfy |
|---|---|---|---|
| The user wrote input to this session's terminal within the last 3 s (`terminal.Manager.lastInputAt`, `internal/terminal/manager.go:175`) | suppress | suppress | suppress |
| This session is visible in any pane of a focused Operator window | suppress | — | — |
| The Operator app on the phone is in the foreground and connected | — | shows (unless viewing that session) | suppress |
| The phone app is viewing this session | — | suppress | — |
| Connect Mobile off, or no paired phone | — | — | suppress |
| An ntfy message for this session was sent under 10 s ago | — | — | suppress (coalesced) |

The 3-second rule covers Esc and a typed `/exit`: the user is at that session.
The in-app bell (persisted notification history) is never suppressed.

## 5. Components

### 5.1 Daemon — events (`internal/lifecycle`, `internal/domain`, `internal/notify`)

- Add `NotificationTurnFinished` and `NotificationAgentExited` to
  `domain/notification.go`, their `Valid` cases, and enrichment in
  `notify/enrich.go`.
- Emit intents from lifecycle at the transitions in §4.1 and §4.3, and add
  `turn_finished` resolution on the next prompt.
- The 3-second rule is evaluated where the intent is created, through a small
  port (`LastInputAt(sessionID) time.Time`) implemented by the terminal manager,
  so lifecycle does not import `internal/terminal`. The suppressed intent is
  still persisted for the bell but marked `quiet`, and neither the renderer nor
  the phone sender alerts on a quiet notification. The plan decides whether
  `quiet` is a column or an event attribute; it must be visible on the SSE
  payload the renderer reads (`notifications/stream`).

### 5.2 Daemon — phone alerts (`internal/push`, `internal/mobilebridge`)

- `push.Dispatcher` keeps its shape: an additive `notify.Hub` subscriber that
  cannot stall a notification insert (`internal/push/dispatcher.go:60-110`).
  The Expo `Sender`, receipts sweep, `DeviceStore` and `mobilebridge`
  `pushdevices.go` are deleted.
- New interface `PhoneSender { Send(ctx, Alert) error }` with one
  implementation, `NtfySender`: `POST https://ntfy.sh/<topic>` with headers
  `Title`, `Tags`, `Priority`, `Click: operator://session/<id>`. Body is the
  event word only (D6). 5 s timeout, one retry after 2 s, no retry after that.
- The dispatcher sends only when: Connect Mobile is on
  (`LANManager.Running()`), a phone is paired (the password hash is set), no
  foreground phone connection exists (§5.4), the notification is not `quiet`,
  and the per-session 10 s coalescing window has passed.
- Topic: 32 random URL-safe characters, generated when Connect Mobile is first
  enabled, stored in `mobilebridge.State` (`internal/mobilebridge/config.go`),
  regenerated on every password rotation
  (`internal/httpd/controllers/mobile.go:263-274`), returned to the paired
  phone by an authenticated route.
- Every attempt records `{at, ok, error}` in memory (last 20) and the latest
  is exposed on the mobile status route for both Settings screens. Test route:
  `POST /api/v1/mobile/alerts/test` sends one message and returns the result
  synchronously.
- Delete `/api/v1/push/devices` (`internal/httpd/controllers/push.go`) and its
  OpenAPI entries; regenerate the spec and TS types (`npm run api`).

### 5.3 Desktop — Mac toasts (`frontend/src-tauri`)

- New `mac_notifications` module on `objc2` (the crate family is already
  pinned at `=0.3.2`, `frontend/src-tauri/Cargo.toml:46-47`; add the matching
  `objc2-user-notifications`). It requests authorization at first use, posts
  with the notification id as the request identifier and the default sound,
  and installs a `UNUserNotificationCenterDelegate` whose
  `didReceiveNotificationResponse` calls `route_click(id)`; `route_click`
  focuses the main window and emits `notifications:click`
  (`notification_policy.rs:54-57`). `willPresentNotification` returns banner +
  sound so a toast also shows while the app is frontmost (D2 needs it).
- `show_plan` stops dropping everything on focus: the renderer decides (§5.5).
  Attention (dock bounce) keeps its current types.
- Dev (`tauri::is_dev()`, not a bundle) keeps the plugin path; UNUserNotificationCenter
  requires a bundle identity.
- New commands: `notification_permission_status` (authorized / denied /
  not determined) and `notification_open_settings` (opens System Settings →
  Notifications). Windows and Linux keep the plugin.
- If step 0 check 1 fails: approach B instead of this section, recorded in §3.

### 5.4 Daemon — phone presence (`internal/terminal`, `internal/httpd`)

- The LAN listener marks its requests (request-context value set in
  `LANManager`'s handler chain, `internal/httpd/lan_listener.go`), so the mux
  knows a connection came from the phone.
- New mux client frame `presence {state: "foreground" | "background"}`. The
  phone sends it on connect and on every `AppLifecycleState` change. The
  terminal manager exposes `PhoneForeground() bool`: true while any
  LAN-origin connection's last presence is `foreground`.
- A connection that closes counts as background. The dispatcher reads this at
  send time.

### 5.5 Desktop — renderer (`frontend/src/renderer`)

- `suppressToastForWatchedSession` (`lib/notifications.ts:274-281`) today
  suppresses only `needs_input` and only for one session. It becomes: skip if
  `notification.quiet`, else skip if the session is in the set of sessions
  rendered in any split pane's active tab **and** the document is visible and
  focused. The split-view layout store supplies the set; the single
  `getVisibleAgentSessionId` is replaced.
- Click: `NotificationCenter.tsx:136` already routes a clicked id; verify it
  opens the session for the new types.
- Settings → Notifications: Mac permission state with an "Open System
  Settings" button when denied; "Send test notification"; the phone status line
  from §5.2 ("On for your paired phone · last delivered 2 min ago" / "Last
  attempt failed: <error>" / "Off — Connect Mobile is off").
- The shell block-finished toast (`BlockTerminal.tsx:614-624`) rides the same
  native path and needs no change.

### 5.6 Mobile (`packages/mobile`)

- Add `flutter_local_notifications`. On a notification event from the
  existing stream while the app is foregrounded, show a local notification
  unless the session is the one on screen or the notification is `quiet`.
  Tapping routes through `resolveDeepLink` to `session/<id>`.
- Send the `presence` frame (§5.4) from `MuxClient` on connect and on
  lifecycle changes.
- Settings → Phone alerts, per saved desktop: "Install ntfy" (App Store link),
  "Subscribe" (opens `ntfy://ntfy.sh/<topic>` if step 0 check 3 passed,
  otherwise copies the topic URL and opens ntfy), "Send test" with the result,
  and the last-delivery status.
- Delete `push_registrar.dart`, `push_registration.dart`, `push_status.dart`,
  `push_token_source.dart`, `register_push_device_params.dart`, the push
  endpoints in `end_points.dart:12,18`, the Settings push switch, and their
  tests. Remove the "Push" entry from CLAUDE.md's "Deliberately unwired"
  section and describe ntfy instead.
- Rename `kDeepLinkScheme` to `operator`
  (`lib/core/deep_link/deep_link_target.dart`), `Info.plist:97`,
  `AndroidManifest.xml`, and the two deep-link tests.

## 6. Error handling

- ntfy unreachable, `429`, or non-2xx: record the error, no further retry,
  never block or delay persistence. The status line shows it.
- macOS permission denied: the toast command returns the state instead of
  swallowing it; Settings shows "Off in System Settings".
- Topic missing (Connect Mobile never enabled): the sender is inert; the phone
  Settings screen says pairing is required.
- Phone offline while foreground presence is stale: a closed socket clears
  presence, so ntfy resumes as soon as the daemon sees the close. A socket that
  dies without a close frame is caught by the mux heartbeat
  (`internal/terminal/manager.go:357`, `heartbeatLoop`, interval
  `defaultHeartbeat`); the plan must state the
  heartbeat's timeout as the worst-case window where ntfy is wrongly skipped.

## 7. Testing

Every rule gets a positive and a negative test.

- **Lifecycle (Go):** `active → idle` emits one `turn_finished`; the next
  prompt resolves it; `idle → idle` emits nothing. Each §4.3 trigger emits
  `agent_exited`; Kill, cleanup, relaunch, agent switch, rollback, `/clear`
  and `resume` emit nothing. Input 1 s before the transition marks it quiet;
  input 4 s before does not.
- **Dispatcher (Go, fake HTTP server):** sends only with Connect Mobile on and
  a paired phone; skips when `PhoneForeground()`; skips `quiet`; coalesces
  within 10 s and sends again after; records failures with the error; the
  request body and headers contain no assistant text; the topic changes on
  password rotation; the test route returns the real result.
- **Presence (Go):** a LAN-origin connection with `foreground` sets
  `PhoneForeground()`; loopback connections never do; close clears it.
- **Rust:** `route_click` focuses and emits the id; `show_plan` no longer
  drops on focus; the dev fallback selects the plugin.
- **Renderer (Vitest):** toast suppressed when the session is in any visible
  pane and the window is focused; shown when it is in a background tab or
  another project; `quiet` never toasts.
- **Mobile (flutter test):** local notification skipped for the viewed
  session and for `quiet`; shown otherwise; `operator://session/<id>` resolves;
  presence frames on lifecycle changes; Settings states.
- Gates: `go test -race ./...` in `backend/`, `npm run typecheck` and the
  renderer tests in `frontend/`, `cargo test` in `frontend/src-tauri`,
  `flutter analyze` and `flutter test` in `packages/mobile`.

## 8. Real-app verification before merge

Done by the implementing session on real devices, with evidence in the report:

1. Installed build (release bundle in `/Applications`): a session in a
   background tab finishes a turn → one toast with sound; clicking it opens
   that session.
2. Same session visible in a focused pane → no toast; the bell still lists it.
3. iPhone locked, Connect Mobile on → ntfy alert arrives; tapping opens
   Operator on that session.
4. Operator app open on the phone → one local notification, no ntfy duplicate.
5. Connect Mobile off → no ntfy message (fake-server log or ntfy topic web view
   shows none).
6. Kill a session → no "exited" alert anywhere; `kill -9` the agent process →
   one "exited" alert.

## 9. Out of scope

- The planner/implementer hand-off and report-back (the other suggestion from
  2026-09-23) — the user wants to design it separately for reliability.
- CI failure and merge conflict alerts (dropped, D1).
- A self-hosted ntfy server or direct APNs (D8 leaves the seam).
- Windows and Linux toast click activation; they keep the plugin.
