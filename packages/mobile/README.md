# operator_mobile

A Flutter thin client for the Operator daemon. It talks to a paired daemon over
HTTP/SSE the same way the desktop renderer does, rather than embedding any
orchestration logic of its own.

This package is the in-progress Flutter port of the mobile app. The previous
React Native implementation is frozen at `packages/mobile_rn` and stays on
disk, untouched, as the reference the port is built from until milestone M6,
when the RN tree is deleted and this package becomes the only mobile client.
`packages/mobile_rn`'s CI workflow is disabled so the frozen tree cannot fail
CI.

## Current milestone: M1 — walking skeleton

M0 shipped `lib/core` only: data layer, error handling, the Operator
skin/theme, a small set of core widgets, and DI/routing/bootstrap.

M1 adds the first screens a person actually uses — pairing (QR + manual) →
onboarding → the sessions Kanban board:

- `feature/pairing` — QR scan (`mobile_scanner`) and manual host/port/password
  entry, both verifying against the daemon before saving.
- `feature/onboarding` — the first-run gate (`shouldOnboard`), decided
  synchronously in `main.dart` before `runApp` rather than by a mounted
  redirect widget.
- `feature/sessions` — the Kanban board (`SessionsCubit`: an 8s REST poll
  layered with live `MuxClient` session patches), session cards, and a
  long-press action sheet for kill/restore.
- `core/mux` — `MuxClient`, the WebSocket multiplexer session-status and
  (future terminal) events flow through.

See `docs/superpowers/plans/2026-08-12-flutter-mobile-port-m1.md` for the
full task-by-task plan and its "What M1 deliberately does not include"
section for scope boundaries (no spawn flow, no project switcher, no
session-detail screen — chat/terminal land in M3/M4).

## Running the gate

```bash
cd packages/mobile
flutter analyze
flutter test
```

Both must be clean/green before any change is considered done.

## Manual verification against a real daemon

Unlike M0, M1 ships user-facing screens, so `flutter analyze`/`flutter test`
alone don't prove the milestone's "done when" bar: *runs against a real
daemon on a real phone*. Re-verify manually whenever pairing, polling, or
kill/restore logic changes:

1. Start a real daemon and enable **Connect Mobile** from the desktop app's
   Settings (or `POST /api/v1/mobile/enable` against the daemon's loopback
   API). Note the host, port, and password/QR it displays.
2. Spawn at least one session on that daemon first — M1 ships no spawn flow
   of its own.
3. `flutter run` against a simulator or device. On first launch, confirm the
   onboarding welcome screen appears.
4. **Manual-connect path** (works on a simulator, no camera needed): tap
   "Enter manually", fill in the host/port/password, and confirm:
   - A wrong password shows the "Your desktop rejected the password" copy,
     not a generic error.
   - A correct password lands on the sessions Kanban board with the stats
     row, section headers, and cards reflecting the daemon's real sessions
     (orchestrator-kind sessions filtered out; terminated sessions grouped
     under Archive).
   - Pull-to-refresh works.
5. **QR path** (needs a physical device — an iOS Simulator has no camera):
   `flutter run -d <physical-device-id>`, scan the QR Connect Mobile
   displays, confirm it verifies, saves, and lands on the same board.
6. Long-press a live session card to open the actions sheet: Kill asks for
   confirmation and the session moves to Archive once confirmed; Restore (on
   an archived session) does not ask for confirmation and the session
   returns to a live zone.
7. With the app on the board, drop the daemon's reachability briefly (stop
   it or disable Wi-Fi) then restore it — confirm the board recovers within
   one poll tick (~8s) without an app restart.

**2026-08-13 pass:** verified against a real daemon (LAN listener at
`192.168.1.6:3011`, real sessions from an existing project) on the iOS
Simulator — fresh install → onboarding, manual-connect pairing (verify then
persist, confirmed via the app's persisted `ServerConfig`), and the sessions
board correctly rendering live daemon data (orchestrator filtered out,
Working/Archive sections, agent logos, status labels, relative timestamps,
continuous live polling observed over several minutes) all confirmed
working end-to-end. The wrong-password copy, the kill/restore long-press
action sheet, a literal network-drop/recovery test, and the QR path on a
physical device were **not** manually re-confirmed in that pass — simulator
touch-injection tooling became unreliable for further interaction, and
physical-device testing was stopped by request before completion. All four
paths are covered by passing, independently code-reviewed automated tests
(`session_actions_sheet` wiring in Task 19's review, `connection_error_test`
for the rejection copy, `sessions_cubit_test`'s fake_async coverage of the
poll/backoff logic). Re-run this section's steps 4–7 by hand before the next
release if stronger manual confidence is needed.
