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
   **Result (2026-09-23): passed — approach A (UNUserNotificationCenter) stands.**
   Probe `UNProbe.app` (bundle id `dev.operator.unprobe`), `codesign -dv`:
   `Signature=adhoc`, `TeamIdentifier=not set`, installed in `/Applications`.
   The first attempt came back denied even though the user reported clicking
   Allow: `auth granted=false error=Optional(Error Domain=UNErrorDomain Code=1
   "Notifications are not allowed for this application" ...)`. UNProbe was
   listed in System Settings → Notifications; after the user switched it on
   and the probe was relaunched: `auth granted=true error=nil`, `add error=nil`,
   the banner showed, and clicking it logged `clicked id=probe-1`. Consequence:
   the permission can land in "denied" on first run, so the Settings
   "Open System Settings" path (§5.3, §5.5) is load-bearing, not cosmetic.
2. **Stop on interrupt.** Start Claude Code under Operator, send a long prompt,
   press Esc. Record whether `opr hooks claude-code stop` fires (the hooks log
   under the data dir). *Either result keeps §4.4's keystroke rule; this only
   records whether it is load-bearing.* The comment at `activity.go:39-43` says
   it fires; that claim is unverified.
   **Result (2026-09-23): Esc does not fire Stop.** Installed Operator, daemon
   on 127.0.0.1:3001, `/api/v1/events` watched. Session `scratch-37`: created
   10:29:31Z, `session_updated` with `"activity":"active"` at 10:29:32.556Z;
   the user sent the counting prompt and pressed Esc after a few lines. No
   further `session_updated` arrived, and 40 s later `GET
   /api/v1/sessions/scratch-37` still returned `{'state': 'active',
   'lastActivityAt': '2026-09-23T10:29:32.556162Z'}`. The comment at
   `activity.go:39-43` is wrong for Esc: an interrupted turn stays `active`,
   so no `turn_finished` is emitted for it and the 3-second rule is not what
   silences Esc. It still covers a typed `/exit`.
3. **ntfy on the user's iPhone.** Install ntfy from the App Store (confirm it is
   free). Record: whether `ntfy://ntfy.sh/<topic>` opens the subscribe screen;
   whether a message sent with `Click: operator://session/<id>` opens Operator
   on tap (after the scheme rename, or test with `aomobile://` first).
   **Result (2026-09-23): ntfy is free; `ntfy://` did not subscribe; custom
   `Click` works.** The user installed ntfy (free). The `ntfy://ntfy.sh/<topic>`
   link did not open a subscribe screen; the user subscribed with "+" (default
   server, "Use another server" off). `curl -H "Title: operator-4 finished"
   -H "Tags: white_check_mark" -H "Click: aomobile://session/operator-4" -d
   finished https://ntfy.sh/<topic>` returned `"event":"message"` with
   `"click":"aomobile://session/operator-4"`; with the phone locked the user
   reported it "arrived instant", and tapping it opened the Operator app.
   Consequence: Task 11 registers the cubit with `ntfyDeepLink: false`
   (copy the topic, open ntfy).
4. **ntfy.sh limits.** Send 20 messages in quick succession to a throwaway
   topic; record any `429`. The published default is 60 burst then one per
   10 s (ntfy FAQ); a daily cap on ntfy.sh is not documented — "not known"
   until observed.
   **Result (2026-09-23): 20 × `200`, no `429`.** `for i in $(seq 1 20); do curl
   ... -d "burst $i" https://ntfy.sh/<throwaway topic>; done | sort | uniq -c`
   printed `20 200`. The 10 s per-session coalescing stays.

## 4. Events

### 4.1 Turn finished (new type `turn_finished`)

- Fires in lifecycle when a live, non-terminated session transitions
  `active → idle`. That transition is Claude's `stop` hook
  (`activity.go:39`); `SubagentStop` does not map to an activity state and does
  not fire it.
- Not while the session manager holds an agent operation on the session
  (`SessionMutationInProgress`, `session_manager/session_input.go:69`): an agent
  switch's internal hand-off turn ends with a Stop the user never asked for.
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
    (`lifecycle/manager.go:429-436`) — an agent crash or `kill -9` of the
    agent process.
- The reaper's other branch, terminating a session whose whole runtime is dead
  (`lifecycle/manager.go:455-466`), does **not** alert. A dead runtime means
  the pty host is gone, which after a reboot is true of every session at once;
  alerting there would flood the user with one "exited" per session at boot.
- Only those two sources may emit it: the activity signal path and the first
  branch of `ApplyRuntimeObservation` (`lifecycle/manager.go:413`). `MarkTerminated`
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

### 4.5 Duplicate suppression must not swallow repeat alerts (existing bug)

`CreateNotification` skips an insert, and therefore the publish every alert
path hangs off, while an "open" row with the same `(session, type, pr_url)`
exists (`storage/sqlite/store/notification_store.go:21-31`). "Open" is
`status = 'unread' OR resolved_at IS NULL`
(`storage/sqlite/queries/notifications.sql:109-116`, index
`migrations/0041_notification_resolution.sql:21-23`). A needs-input row is
resolved when the user answers but stays `unread` until the bell panel is
opened, so every later needs-input for that session is silently dropped until
then. The same rule would drop every `turn_finished` after a session's first.

Fix: for types that carry a resolution (`needs_input`, `ready_to_merge`,
`turn_finished`, `agent_exited`) "open" means `resolved_at IS NULL` only; a
resolved row never blocks a new one. For one-shot facts (`pr_merged`,
`pr_closed_unmerged`) the existing `unread OR unresolved` rule stays, because
the SCM observer re-observes the same merge on every poll. `NeedsResolution()`
returns true for `turn_finished` and `agent_exited`. `agent_exited` is resolved
when the session leaves `exited` or is terminated, and the boot-time reconcile
(`ReconcileResolvedNotifications`) resolves stranded `turn_finished` and
`agent_exited` rows the same way it already does for `needs_input`.

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
  (`LANManager.Running()`), a phone has **claimed** the current topic (below),
  no phone holds a foreground `notifications` subscription (§5.4), the
  notification is not `quiet`, and the per-session 10 s coalescing window has
  passed.
- Topic: 32 random URL-safe characters, stored in `mobilebridge.State`
  (`internal/mobilebridge/config.go`) as `alertTopic`, with `alertTopicClaimed`.
  A new topic is generated, unclaimed, every time `enableWithPassword` sets a
  new password (`internal/httpd/controllers/mobile.go:209-253`: enable,
  regenerate, and the tunnel's upgrade to a long password). Boot restore
  (`internal/daemon/mobile_restore.go`) keeps the persisted topic.
  `enableWithPassword` starts from the loaded state instead of a fresh
  `State{}` so `alertTopic` and `ngrokDomain` survive a rotation's write.
- "A phone is paired" means the topic is claimed: the phone calls
  `POST /api/v1/phone-alerts/subscribe` (LAN-authenticated) to receive the
  topic, which marks it claimed. A rotation unclaims it, so a phone that no
  longer knows the password never receives alerts.
- Routes live under `/api/v1/phone-alerts`, not `/api/v1/mobile`: the LAN
  listener 404s every `/api/v1/mobile` path (`internal/httpd/lan_listener.go:60-67`),
  and the phone must reach these. `GET /api/v1/phone-alerts` returns
  `{enabled, claimed, lastDelivery}` (no topic). `POST /api/v1/phone-alerts/subscribe`
  returns `{topic, server}` and claims. `POST /api/v1/phone-alerts/test` sends one
  message through the same gate minus the foreground check and returns the
  result synchronously.
- Every attempt records `{at, ok, error}` in memory (last 20); the latest is
  `lastDelivery` on the GET route, read by both Settings screens.
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

### 5.4 Daemon — live notifications to the phone (`internal/terminal`, `internal/httpd`)

The phone has no live notification feed today: its list polls REST every 30 s
(`notifications_cubit.dart:20-26`). The mux socket it already holds carries
one more channel.

- New mux channel `notifications`. Client frames `subscribe` / `unsubscribe`;
  server frame `notification` carrying `{id, sessionId, projectId, type,
  title, body, quiet, createdAt}` for every `NotificationCreated` hub event.
  The terminal manager takes the hub through an option
  (`WithNotificationFeed`) and fans each event out to subscribed connections.
- The phone subscribes when the app is in the foreground and unsubscribes when
  it is not (§5.6). The daemon's "phone app is open" check is
  `PhoneForeground()`: some connection that arrived through the LAN listener
  holds a `notifications` subscription. The LAN listener marks its requests
  with a context value (`LANManager`'s handler chain,
  `internal/httpd/lan_listener.go:36-45`); the mux handler passes it into
  `Serve`. Loopback connections never count.
- A closed connection drops its subscription immediately; a socket that dies
  without a close is dropped by the mux heartbeat.

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

- Add `flutter_local_notifications`. `MuxClient` exposes the §5.4
  `notifications` channel as a stream plus `subscribeNotifications()` /
  `unsubscribeNotifications()`, and re-sends the subscription on reconnect the
  way it re-sends block subscriptions (`mux_client.dart:173-178`).
- `_OperatorAppState`'s `AppLifecycleListener` (`lib/main.dart:80`)
  subscribes on resume/show and unsubscribes on hide/pause.
- While subscribed, each `notification` frame raises a local notification
  unless it is `quiet` or its session is the one on screen (a
  `ViewedSession` notifier set by the terminal route). Tapping routes through
  `DeepLinkService.handle` to `operator://session/<id>`.
- `notificationTarget` (`lib/feature/notification/logic/notification_view.dart:47-50`)
  sends only `needs_input` to the session; `turn_finished` and `agent_exited`
  must go there too, and `notificationVisual` gets entries for both.
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
- Phone offline while its foreground subscription is stale: a closed socket
  clears it, so ntfy resumes as soon as the daemon sees the close. A socket that
  dies without a close frame is caught by the mux heartbeat
  (`internal/terminal/manager.go:727-740`: a 15 s tick, `defaultHeartbeat`, and
  a ping that times out after another 15 s). Worst case, ntfy is wrongly
  skipped for about 30 s after the phone drops off the network without closing
  the socket.

## 7. Testing

Every rule gets a positive and a negative test.

- **Lifecycle (Go):** `active → idle` emits one `turn_finished`; the next
  prompt resolves it; `idle → idle` emits nothing. Each §4.3 trigger emits
  `agent_exited`; Kill, cleanup, relaunch, agent switch, rollback, `/clear`
  and `resume` emit nothing. Input 1 s before the transition marks it quiet;
  input 4 s before does not.
- **Dispatcher (Go, fake HTTP server):** sends only with Connect Mobile on and
  a claimed topic; skips when `PhoneForeground()`; skips `quiet`; coalesces
  within 10 s and sends again after; records failures with the error; the
  request body and headers contain no assistant text; the topic changes on
  password rotation; the test route returns the real result.
- **Live feed (Go):** a subscribed connection receives each created
  notification once; an unsubscribed one receives none; a LAN-origin
  subscription sets `PhoneForeground()`, a loopback one never does, and close
  or unsubscribe clears it.
- **Store (Go):** a resolved-but-unread `needs_input` or `turn_finished` does
  not block a new one; an unresolved one does; an unread `pr_merged` still
  blocks a duplicate.
- **Rust:** `route_click` focuses and emits the id; `show_plan` no longer
  drops on focus; the dev fallback selects the plugin.
- **Renderer (Vitest):** toast suppressed when the session is in any visible
  pane and the window is focused; shown when it is in a background tab or
  another project; `quiet` never toasts.
- **Mobile (flutter test):** local notification skipped for the viewed
  session and for `quiet`; shown otherwise; `operator://session/<id>` resolves;
  subscribe/unsubscribe on lifecycle changes and on reconnect; Settings states.
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
