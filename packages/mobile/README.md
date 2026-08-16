# operator_mobile

A Flutter thin client for the Operator daemon. It talks to a paired daemon over
HTTP/SSE the same way the desktop renderer does, rather than embedding any
orchestration logic of its own.

This package is the Flutter port of the mobile app. The previous React Native
implementation was frozen at `packages/mobile_rn` as the reference the port
was built from, then deleted at milestone M6 once every file in it was
accounted for — see `docs/mobile-parity-ledger.md` for where each one went.
This package has been the only mobile client since M6.

## Status: the port is complete (M0–M6)

Eleven features over a shared `lib/core`:

- `pairing` / `onboarding` — QR scan (`mobile_scanner`) and manual
  host/port/password entry, both verifying against the daemon before saving,
  behind a first-run gate decided in `main.dart` before `runApp`.
- `sessions` — the Kanban board (`SessionsCubit`: an 8s REST poll layered with
  live `MuxClient` session patches), cards, stats that jump to their section,
  and a long-press sheet for kill/restore/resume.
- `pull_request` / `orchestrator` / `spawn` / `settings` — the other three tabs
  and the new-session flow.
- `chat` — timeline, SSE stream, composer, attachments and elicitation.
- `terminal` — TUI and shell over the mux socket, rendered with a vendored
  `xterm.dart`.
- `preview` / `notification` — the in-app preview browser, notification history
  and the push switch.

Cross-cutting: `core/mux` (the WebSocket multiplexer both the board and the
terminal depend on), `core/telemetry`, `core/deep_link`, and `chat/voice` for
dictation.

Two subsystems deliberately outlive the port and are **not** wired: the PostHog
sink (no project key exists) and FCM/APNs push registration (needs credentials).
The decision logic for both is built and tested behind its seam. See
`docs/mobile-parity-ledger.md` for those, for every divergence from the
React Native original, and for where each of its 99 source files went.

Per-milestone plans are in `docs/superpowers/plans/2026-08-*-flutter-mobile-port-*.md`.

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
