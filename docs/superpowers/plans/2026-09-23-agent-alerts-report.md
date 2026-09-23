# Agent alerts — implementation report

**Date:** 2026-09-23
**Branch:** `agent-alerts` (worktree `../Operator-agent-alerts`), from `development` at `27901630a`
**Plan:** `docs/superpowers/plans/2026-09-23-agent-alerts.md` · **Spec:** `docs/superpowers/specs/2026-09-23-agent-alerts-design.md`
**Process:** subagent-driven development — a fresh implementer per task, a fresh reviewer per task, scoped re-review per fix round, one whole-branch review, then real-device verification.

## Open items (read first)

- **V4 — the phone app never tells the daemon it is open.** With Operator open on the iPhone (notification permission Allowed, relaunched, both LAN and tunnel pairing), the daemon kept sending ntfy (`GET /api/v1/phone-alerts` `lastDelivery` advanced at 19:15:22, 19:18:21, 19:55:38, 19:56:49) and the app showed no local notification of its own. The daemon side is proven: a Python client subscribed on `/mux` through the LAN listener (19:19:03) and through the cloudflared tunnel (19:47) received the `notification` frame and ntfy was skipped both times. Not the cause: lazy socket (the terminal was opened first, 19:55). A test through the real `MuxClient` + `PhoneAlertsRuntime` passes (`b866d1477`), so the fault is on the device path, not yet found. Next lead: `local_alert_sink.dart:40-41` gates everything on `IOSFlutterLocalNotificationsPlugin.checkPermissions()?.isEnabled`; if that returns null/false on iOS 27 the app never subscribes (Task 10 ruling: no subscription without permission). Needs a profile build with logging on the device.
- **Check 5 (Connect Mobile off → no ntfy) was not run on the device.** Covered only by `push` gate tests.
- **Check 2** was answered "Focused; both toasted" (a toast for the session on screen), then the user said "no its working like spec lets move on". Not independently confirmed.
- **ntfy on iOS shows lock-screen banners only while the phone is locked**; unlocked, messages go straight to ntfy's list (user, 19:26). ntfy/iOS behavior; with V4 fixed the in-app notification covers "app open", but "unlocked, Operator not open" gets no banner.
- **Owner sign-off needed:** Mac notification authorization is requested at launch, not at first use (spec §5.3 says first use).
- **Open question:** `claude agents` background sessions may only emit `agent_completed` (no Stop); after fix I1 they get no `turn_finished`. Not known from the code.

## Task 0 — device checks (spec §3, commit `d7740b1a2`)

1. UNUserNotificationCenter from an ad-hoc app: passed after the user enabled UNProbe in System Settings (first run `auth granted=false … Code=1 "Notifications are not allowed"`; then `auth granted=true`, `clicked id=probe-1`). Approach A kept. **Later correction (V2):** the check compared only `Signature=adhoc`/`TeamIdentifier`; local Operator builds were *linker*-signed, which macOS never registers — fixed in `86ba0acd6`.
2. Esc does not fire Stop: `scratch-37` stayed `active` 40 s after Esc.
3. ntfy is free; `ntfy://ntfy.sh/<topic>` did not open a subscribe screen (topic added with "+"); a `Click: aomobile://…` opened Operator; arrived instantly while locked.
4. 20 × `200`, no `429`.

## Per task

Gates at the end of the branch (Task 12 run at `8f4dcc32b`, later fixes re-gated per area): backend `go test -race ./...` 139 packages ok; frontend typecheck + e2e typecheck ok, vitest 158 files / 1601 tests; tauri `cargo test` 241; mobile `flutter analyze` "No issues found!", `flutter test` 1356.

| Task | Commits | Review outcome |
|---|---|---|
| 1 types, quiet, dedupe | `27b0355fe`, `35a31150a` | Fix round: frontend typecheck red (`quiet` missing in literals), reconcile real-store test, safe down migration (0117 Down failed on resolved-unread + open pair) |
| 2 lifecycle emission | `06c1afe8e`, `f4e0e408f` | Fix round: `MarkSpawned` left `agent_exited` open → next crash swallowed |
| 3 3-second rule | `72c539707`, `c3017e7a9` | Fix round: added doc comment removed; recency wired before lifecycle goroutines |
| 4 mux `notifications` | `b9c62a71b` | Approved |
| 5 alert topic | `52853e25f` | Approved |
| 6 ntfy + routes, Expo removed | `6d576223a` | Approved |
| 7 macOS UN toasts | `59624c9a9` | Approved |
| 8 renderer + Settings | `cf51c9462`, `d2bada7bd` | Fix round: unhandled denied `show`, split-pane visibility tested through the real layout store, rewritten comments |
| 9 push removal, `operator://` | `9c43620a1` | Approved |
| 10 phone local notifications | `9138b4c12`, `aae6633e6` | Fix round: viewed session only set on the terminal route; single-slot stack |
| 11 phone alerts settings | `72b13c719` | Approved |
| 12 docs + gates | `8f4dcc32b` | — |

Deviations recorded by implementers (file:line in `.superpowers` task reports, summarized): migration ledger entry for 117 (`migrate_burned_versions_test.go`); `invoke` adaptation in `tauri-bridge.ts`; Tauri commands registered only where `notification_show` is (lib.rs has three `generate_handler!` lists, not two); `Priority` header added (spec lists it, plan omitted it); non-ASCII ntfy titles RFC 2047-encoded; Android POST_NOTIFICATIONS request and core-library desugaring (plugin requirements); flutter_local_notifications resolved 22.3.1.

## Rulings made during execution

- P1 Task 10 map assertions use `contains(equals(...))`.
- P2 Task 5: restore pin kept plus a test that non-password writes keep the claimed topic.
- P3 negative tests for Kill (incl. reaper race), cleanup, relaunch, switch, rollback, `/clear`, resume through the real session manager.
- P4 wrapper `process-exited` counts as the agent leaving on its own, gated like the reaper.
- P5/Task 11 subscribe copies the bare topic, opens ntfy via `ntfy://`, App Store only if that fails; `ntfyDeepLink: false`.
- P6 toast errors surface the permission state; dev selects the plugin (unit test).
- P7 ntfy Priority: needs_input `high`, others `default`.
- P8 relative "last delivered" text; comments of deleted code removed.
- P9 every push reference in mobile tests removed.
- P10a `turn_finished` resolved on any move into `active`; P10b dedupe on unresolved for every type; P10c `SetDomain` through `mobilebridge.Update`.
- Task 10: no `notifications` subscription while phone notification permission is denied (ntfy keeps delivering).
- M5 (final review): the tiny subscribe/broadcast race that can lose a phone alert on both channels is accepted.
- Authorization at launch kept (needs owner sign-off, above).

## Whole-branch review (`a3e22f8c8`, opus) and fix wave (`3d95a3f57`..`8326cef63`)

Verdict "with fixes"; all five Review Focus scenarios held. Fixed and re-reviewed: I1 `turn_finished` no longer fires on Claude `notification` idle (idle_prompt after Esc, `agent_completed`); I2 phone Settings shows load/subscribe/test failures; M1 rollback comments restored; M2 corrupt mobile config self-heals; M3 no-bundle-id binaries use the plugin; M4 covered session screens are not "viewed"; M6 PR alerts open the PRs tab; M7 unpaired test is not a failed delivery; hub-drop and config-load warnings; bounded probe loop. Deferred minors triaged "can wait" are listed in the ledger (test hygiene, `lastSent` never pruned, 12 s ntfy-outage block, cold-launch click, etc.).

## Real-device verification (spec §8), 2026-09-23

Setup: isolated packaged build copied to `~/Applications/Operator Alerts Test/` (bypasses the `/Applications` hand-off, `relocation.rs:147-150`), re-identified `dev.operator.desktop.alertstest` and bundle-signed (two copies sharing `dev.operator.desktop` made toast clicks launch the installed app), `OPERATOR_DATA_DIR=~/.operator-alerts-test/data`, port 3021; project `repo`, Claude sessions `alerts-a1` (repo-18), `alerts-a2` (repo-21), `alerts-a3` (repo-22); prompts sent over `/mux`; iPhone app built and installed with `flutter install --release`.

1. **Background tab finishes → toast + click opens it: PASS.** User: "Both, with sound"; click "Test app, alerts-a2". Turns faster than 3 s are quiet by design (observed `quiet: true` 1 s after input).
2. **Session visible in a focused pane → no toast: NOT CONFIRMED** (see open items).
3. **Locked iPhone → ntfy alert; tap opens the session: PASS after fix V3.** Delivery: ntfy.sh poll shows `alerts-a2 finished | finished | operator://session/repo-21`, priority 3, no private text. Tap first showed "Something went wrong" over the correct session (V3), fixed in `c3d0b1250`.
4. **App open → one local notification, no ntfy: FAIL (V4).**
5. **Connect Mobile off → no ntfy: NOT RUN.**
6. **Kill → no exited; kill -9 → one exited: PASS.** `POST /sessions/repo-18/kill` → terminated, no `agent_exited`; `kill -9` of repo-22's claude → one `alerts-a3 exited` (16:20:28Z), ntfy ok; user: "a3 exited only".
7. **Two turns in a row → two alerts: PASS.** 8 `turn_finished` rows for repo-21, all unread, each resolved at the next prompt.
8. **Daemon restart → phone still gets alerts without re-subscribing: PASS.** New daemon pid, `{"enabled":true,"claimed":true}`, topic unchanged, 19:21:43 alert on the same topic and in ntfy's list (user screenshot).

Bugs found on the device and fixed (each reviewed): **V1** Settings had no way out of `not_determined` (`848aa81cd`); **V2** local/debug macOS builds were only linker-signed so macOS never registered Operator for notifications — `bundle.macOS.signingIdentity: "-"` (`86ba0acd6`; CI releases were already bundle-signed); **V3** a deep link was handled twice (Flutter's built-in deep linking also pushed `/repo-21`) — disabled on iOS and Android (`c3d0b1250`). **V4** open (above).
