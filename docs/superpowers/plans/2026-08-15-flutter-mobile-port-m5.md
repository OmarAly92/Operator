# Flutter Mobile Port — M5 (Push, voice, telemetry, preview, deep links) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The five cross-cutting subsystems the milestones so far deferred: telemetry that decides what
*would* be sent, the whole `notification` feature (history list, mark-read, the push switch and its
state machine), dictation that fills either composer, the session preview browser behind the globe,
and `aomobile://` deep links that resolve to a screen. Everything that does not need Firebase/APNs
credentials lands first and stands on its own; the native push edge is one clearly-marked blocked
task at the end.

**Architecture:** One new feature (`lib/feature/notification/`), one new core subsystem
(`lib/core/telemetry/`), one new sub-package inside chat (`lib/feature/chat/voice/`), one small new
feature (`lib/feature/preview/`), and one core service (`lib/core/deep_link/`). Every platform SDK
sits behind a narrow Dart seam — `MobileTelemetryClient`, `SpeechRecognizer`, `PushTokenSource`,
`AppLinkSource` — so the decision logic is pure, unit-tested, and lands without the SDK. Only the
last task constructs Firebase.

**Tech Stack:** Everything from M4, plus `speech_to_text 7.4.0` (dictation), `app_links 7.2.1` (deep
links) and `webview_flutter 4.14.1` (preview browser). `firebase_core 4.13.0`,
`firebase_messaging 16.5.0` and `flutter_local_notifications 22.3.0` are pinned here but only added
by the final, credential-gated task. `posthog_flutter 5.36.2` is deliberately **not** added — see
"What M5 deliberately does not include".

**Spec:** `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`

## Global Constraints

- Source spec: `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`.
- Source of truth for RN behavior: `packages/mobile_rn/` (frozen reference). File paths below are
  relative to `packages/mobile_rn/` unless stated otherwise. The RN files this milestone ports are
  `lib/telemetry/*` (13 files), `lib/notificationView.ts`, `lib/pushStatus.ts`, `lib/push.ts`,
  `lib/PushManager.tsx`, `lib/TelemetryManager.tsx`, `app/notifications.tsx`, the Notifications
  section of `app/(tabs)/settings.tsx`, `lib/voice/*` (4 files), `app/preview/[id].tsx`, the preview
  half of `lib/session/TerminalSessionScreen.tsx` (lines 586–617, 756–780, 936–950, 1267–1295), and
  `getPreview` / `mobileReachablePreviewURL` / the push + notification calls in `lib/api.ts`
  (lines 366–390, 451–525).
- Conventions are the `flutter-knowledge` skill. Where the mirrored RN source contradicts it, the
  skill wins. Invoke `flutter-testing` before the first test file, exactly as M0–M4 did.
- Cubit only — never `Bloc` with events. Static-only classes are `sealed class X`. **No comments**
  except non-obvious business rules. Single quotes, `const` constructors, full 8-digit hex colors,
  `final` locals. No `flutter_screenutil` extensions outside `AppTextStyle`. No `drift`, no
  `freezed`, no `json_serializable`, no `build_runner`.
- **User-facing copy is inline English**, as in M0–M4. This app has no `LocaleKeys` catalogue for
  product copy; do not introduce `easy_localization` keys for the strings in this plan.
- Navigation is `Navigator.of(context)` with `RoutesStrings` names — the codebase's established
  form (`app_router.dart`, `chat_body.dart`); do not introduce a `context.pushNamed` extension here.
- Verification after every task: `flutter analyze` clean and `flutter test` green, both run from
  `packages/mobile`. The app is not run or built as part of implementation.
- **Baseline this plan starts from: `flutter analyze` → "No issues found!", `flutter test` →
  772/772 green** (measured on `master` at commit `9b5edd53a`, 2026-08-15). Every task's expected
  count is baseline-plus-its-own; never let the suite shrink.
- Package name is `operator_mobile`; imports are `package:operator_mobile/...`.
- All app state resolves under `~/.operator` — unaffected by this milestone, called out per
  `AGENTS.md`'s hard rule for completeness.

### Five rules M4 paid for in wasted time

1. **`Result.when` is an extension method.** Every library that calls `.when(...)` needs its own
   direct `import 'package:operator_mobile/core/helpers/result/result.dart';`. A transitive import
   through the repository does not bring the extension into scope.
2. **Check every new type name against the packages the file imports.** M4 hit a real collision
   between the app's `TerminalState` and xterm's and needed a `hide`. In M5 the risky files are
   `device_provider.dart` (imports `speech_to_text`, which exports `SpeechToText`, `LocaleName`,
   `SpeechRecognitionResult`, `SpeechRecognitionError`, `SpeechListenOptions`, `ListenMode`) and the
   final push task (`flutter_local_notifications` exports `Importance`, `Priority`,
   `NotificationResponse`; `firebase_messaging` exports `RemoteMessage`, `NotificationSettings`,
   `AuthorizationStatus`). Names chosen in this plan avoid all of those — do not rename them.
3. **Never call `emit`/`setState` synchronously from a layout callback.** The preview and voice work
   both add `LayoutBuilder`-adjacent code paths; schedule the emit instead.
4. **Do not wrap a widget in `GestureDetector(onScale*)` when a child needs long-press or drag.**
   The mic key uses `Listener`-free plain `GestureDetector(onTapDown/onTapUp/onTapCancel)`, which is
   safe; do not "upgrade" it to a scale recognizer.
5. **A cubit with private duration fields needs the factory + `required this._field` pattern**
   (`ChatCubit`, `InterfaceSwitchCubit`, `TerminalCubit` are the precedents), or
   `prefer_initializing_formals` breaks the analyze-clean invariant. `NotificationsCubit`,
   `PreviewCubit` and `VoiceInputCubit` all take injected durations, so all three use it.

## Baseline: M4 is on `master`

M4 was merged into `master` on 2026-08-15 (`9b5edd53a fix(mobile): restore an analyze-clean tree for
the terminal cubits`). The merged tree verifies clean:

```bash
cd packages/mobile && flutter analyze && flutter test
```

"No issues found!" and 772/772 green. M5 branches from that commit (the
`superpowers:using-git-worktrees` skill creates the isolated workspace).

`packages/mobile/packages/xterm` remains a local pub-workspace member with its two local patches, and
`analysis_options.yaml` still excludes `packages/**`. Nothing in M5 touches either — do not propose
swapping the vendored xterm for a pub.dev release.

## The credential blocker, and how this plan is structured around it

The spec says push:

> Needs a Firebase project, `google-services.json`, and APNs keys — credentials only the repository
> owner can create … the native setup is the cost and it blocks M5 until those credentials exist.

**Confirmed with the repository owner on 2026-08-15: none of the three exist yet.**

So the plan is ordered so that every credential-free task lands independently, and everything that
needs credentials is isolated into **Task 22**, the last task, marked BLOCKED. Concretely:

| Subsystem | Credential-free? | Where |
|---|---|---|
| Telemetry vocabulary, sanitize, context, rate limit, daily-active, facade, call sites | Yes | Tasks 1–6 |
| Notification presentation logic, push-toggle state machine | Yes | Tasks 7–8 |
| Notification list/mark-read data layer, cubit, screen, badge | Yes | Tasks 9–11 |
| Push registration bookkeeping (persisted registration, daemon switch, pending-unregister retry) | Yes — the FCM token is behind `PushTokenSource` | Task 12 |
| The Settings push switch | Yes — ships with `UnconfiguredPushTokenSource` | Task 13 |
| Voice | Yes | Tasks 14–16 |
| Preview | Yes | Tasks 17–19 |
| Deep links | Yes | Tasks 20–21 |
| Firebase/APNs native config + `FirebasePushTokenSource` + tray-tap routing | **No — BLOCKED** | Task 22 |

**What is untestable until the credentials exist, stated plainly:**

- No device can mint a push token, so the milestone's "device registers for push and receives one"
  criterion cannot be demonstrated. Tasks 1–21 satisfy every *other* M5 done-when clause.
- With Tasks 1–21 landed, the Settings switch is honest rather than broken: `UnconfiguredPushTokenSource`
  returns `PushRegisterFailure.notConfigured`, so tapping it says "Push isn't configured in this
  build" instead of failing silently or claiming a permission problem.
- `firebase_core`, `firebase_messaging` and `flutter_local_notifications` are **not** added to
  `pubspec.yaml` before Task 22 on purpose: `firebase_core` on Android applies the
  `com.google.gms.google-services` Gradle plugin, which fails the build when `google-services.json`
  is absent. Adding them early would leave a tree that analyzes and tests clean but cannot be built
  on a device — the worst kind of green.
- Everything in Task 22 that *can* be tested without credentials (the mapping from a Firebase token
  and a tray payload onto `PushRegisterResult` / a deep-link target) is tested through the same seam
  the earlier tasks use, so Task 22's own diff is small and mostly configuration.

### The second known gap: no PostHog key

The desktop app ships no PostHog key (commit `8ec08116e`), and RN's `MOBILE_POSTHOG_KEY` is
`process.env.EXPO_PUBLIC_POSTHOG_KEY || ""` — an empty string in every build. `initMobileTelemetry`
returns `null` when the key is empty, so RN's own call sites are already no-ops today.

M5 ports that structure exactly and stops one step short of the SDK: `MobileTelemetryClient` is an
abstract sink, `TelemetryRuntime.init` builds a facade only when a client is supplied, and nothing
supplies one. Every capture in the app therefore resolves to `null?.capture(...)` and sends nothing —
the same behavior as the RN build in the field — while the sanitize / rate-limit / daily-active /
context logic that decides *what would be sent* is fully implemented and tested. Wiring
`posthog_flutter 5.36.2` (verified conflict-free, pinned here) is a one-file M6 task once a project
key exists.

## New dependencies

Verified with `flutter pub add <names> --dry-run` from `packages/mobile` on 2026-08-15. No conflicts,
no downgrades of any existing package; the only shared transitive addition is `json_annotation
4.12.0` (pulled by `speech_to_text`).

**Added by this milestone:**

```yaml
# packages/mobile/pubspec.yaml
dependencies:
  speech_to_text: ^7.4.0        # Task 14 — on-device dictation
  app_links: ^7.2.1             # Task 21 — aomobile:// deep links
  webview_flutter: ^4.14.1      # Task 19 — the preview browser
```

Resolved transitives: `speech_to_text_platform_interface 2.4.0`, `speech_to_text_windows 1.0.1`,
`json_annotation 4.12.0`, `app_links_platform_interface 2.0.4`, `app_links_linux 1.0.3`,
`app_links_web 1.0.4`, `gtk 2.2.0`, `webview_flutter_android 4.14.0`,
`webview_flutter_wkwebview 3.26.0`, `webview_flutter_platform_interface 2.15.1`.

**Pinned but added only by Task 22 (BLOCKED):**

```yaml
  firebase_core: ^4.13.0
  firebase_messaging: ^16.5.0
  flutter_local_notifications: ^22.3.0
```

Resolved transitives for those: `_flutterfire_internals 1.3.76`,
`firebase_core_platform_interface 8.1.0`, `firebase_core_web 3.10.0`,
`firebase_messaging_platform_interface 4.9.3`, `firebase_messaging_web 4.2.4`,
`flutter_local_notifications_platform_interface 12.2.0`, `flutter_local_notifications_linux 8.0.1`,
`flutter_local_notifications_web 1.0.0`, `flutter_local_notifications_windows 3.1.1`,
`timezone 0.11.1`.

**Not added:** `posthog_flutter 5.36.2` (resolves cleanly; deferred by explicit decision — see above).

**Already present and reused:** `permission_handler` (`openAppSettings()` for the blocked-permission
path, the `camera_permission_gate.dart` precedent), `url_launcher`, `package_info_plus`
(telemetry's `app_version`), `shared_preferences` via `CacheHelper` (telemetry storage, rate-limit
state), `flutter_secure_storage` (the push registration blob, which contains the connection
password).

## What M5 deliberately does not include

| Omitted | Why | Lands in |
|---|---|---|
| The `posthog_flutter` client itself | No project key exists (`8ec08116e`), so a wired SDK would send nothing anyway. The sink seam and every decision in front of it land here. | M6 |
| `lib/haptics.ts` call sites (mic press, send, kill, mark-all-read) | No milestone has ported haptics; M1–M4 dropped them at the same call sites. Adding them for the mic alone would be inconsistent, and the spec's ledger has no haptics row. | M6 parity sweep decides |
| A `feature_used {feature: merge}` capture | The PR merge repository method exists (`pull_request_repository.dart:32`) but **no UI calls it yet** — M2 shipped the PR list without a merge action. Wiring telemetry to a call site that does not exist would be a lie in the allowlist. The allowlist keeps `merge` in its closed vocabulary so the event needs no schema change when the button lands. | M6 |
| A live notification badge over the mux `notifications` topic | `MuxClient` already subscribes to the topic (`mux_client.dart:203`) but drops its frames, exactly as RN does — RN polls `/notifications?status=unread&limit=1` from the board tick instead (`store.tsx:170–176`). Ported as a poll; the mux path is not RN behavior. | M6 parity sweep decides |
| The Android release `INTERNET` permission and `usesCleartextTraffic` | `android/app/src/main/AndroidManifest.xml` declares neither; only the debug/profile manifests add `INTERNET`, and RN's `app.json` set `usesCleartextTraffic: true`. A release build cannot reach a plain-HTTP daemon today. Real, pre-existing, and larger than M5 — a release-config task, not a deep-link task. | M6 parity sweep |
| Deleting `packages/mobile_rn` | The port still reads from it. | M6 |

## Deliberate deviations from the RN reference

| RN source | What it does | Why M5 departs |
|---|---|---|
| `lib/telemetry/runtime.ts` constructs `PostHog` from `MOBILE_POSTHOG_KEY` | The SDK edge. | `TelemetryRuntime.init` takes an optional `MobileTelemetryClient`. Production passes none, so `TelemetryRuntime.instance` is `null` and every call site no-ops — identical observable behavior to the keyless RN build, with no SDK dependency. Tests inject a recording fake, so the facade, the rate cap and the daily gate are all covered. |
| `runtime.ts` wraps a throwing call in `trackFeature(feature, run)` | RN's API functions throw on failure. | This codebase's repositories return `Result`, so the outcome is already a branch: `TelemetryRuntime.featureUsed(feature, succeeded: result.isSuccess)` sits beside the existing `result.when(...)`. A wrapper would have to unwrap `Result` to decide, which is strictly worse. |
| `context.ts` reads `Device.isDevice` from `expo-device` | Distinguishes a simulator from a phone for `build_mode`. | Flutter has no equivalent without adding `device_info_plus`, which is not worth a dependency for one string. `runtime.dart` passes `isPhysicalDevice: true`; because `dev` comes from `kDebugMode`, a simulator still reports `dev` in every debug run, and only a release build on a simulator misreports as `device`. The three-way mapping and its test stay, so restoring the signal later is one argument. |
| `lib/telemetry/config.ts` reads `EXPO_PUBLIC_*` env vars, inlined at build time | Expo inlines `process.env.EXPO_PUBLIC_*`. | Dart has `String.fromEnvironment`, which is `const` and read at compile time from `--dart-define`. `TelemetryConfig` uses it for the host, the disabled flag and the disabled-events list, so the kill switches survive the port with the same build-time semantics. |
| `dailyActive.ts` / `runtime.ts` persist through `AsyncStorage` | RN's key-value store. | `CacheHelper` (SharedPreferences) is this app's equivalent and is already initialised in `main()`. `ActiveStorage` stays an abstract seam so the gate's tests are pure; `CacheActiveStorage` is the four-line adapter. |
| `push.ts` mints an **Expo** token via `getExpoPushTokenAsync({projectId})` | Expo's push service proxies to APNs/FCM. | There is no Expo runtime. The token comes from `firebase_messaging`'s `getToken()` (Task 22), behind the `PushTokenSource` seam. The daemon keys devices by token string and takes `platform` in the body, so `POST /push/devices` is unchanged. RN's `no-project-id` reason becomes `PushRegisterFailure.notConfigured` ("this build has no Firebase configuration") — same position in the state machine, accurate wording for the new runtime. |
| `push.ts` persists `{token, host, httpPort, secure, password}` in `SecureStore` | The registration must survive a restart so the *old* daemon can be unregistered. | Same JSON shape under the same key names in `flutter_secure_storage`, which the app already uses for the connection password. The blob contains the password, so it must not go anywhere near `CacheHelper`. |
| `PushManager.tsx` is a headless React component under the root layout | Owns register-on-connect, re-register on foreground, and tray-tap routing. | `PushService` is a plain class in the service locator, driven by an `AppLifecycleListener` in `OperatorApp`. Same three responsibilities, no phantom widget. |
| `deviceProvider.ts` uses `expo-speech-recognition` with `contextualStrings`, `iosCategory` and `androidIntentOptions` | Biases the recogniser toward coding words, and buys a cheap audio session for push-to-talk vs a Bluetooth-capable one for latched. | `speech_to_text 7.4.0` exposes none of the three. The 24-word `CODING_VOCABULARY`, the two `AVAudioSession` categories and the Android intent extras therefore **cannot** be ported — `SpeechListenOptions` carries `partialResults`, `listenFor`, `pauseFor`, `autoPunctuation`, `cancelOnError` and nothing else. `pauseFor: 10s` reproduces `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS: 10000`; `autoPunctuation: true` reproduces `addsPunctuation`. The `push`/`latched` distinction survives in the UI and the gesture logic but no longer changes the audio session, so it is recorded here and in the M6 ledger as a real capability loss, not an oversight. |
| `deviceProvider.ts` banks an Android segment on the `speechstart` event | `onBeginningOfSpeech` is the authoritative Android utterance boundary. | `speech_to_text` does not surface `onBeginningOfSpeech` at all. Android segmentation falls back entirely to the `isSameSegment` partial-rollover heuristic that RN kept as its last resort, plus banking on `finalResult`. The heuristic and both banking rules port 1:1 and keep their tests; the `speechstart` test is replaced by the equivalent no-boundary-announced case. |
| `deviceProvider.ts` listens for `end`, `error`, `start` events | Three separate native listeners. | `speech_to_text` has one status callback (`'listening'`, `'notListening'`, `'done'`) and one error callback. `'listening'` is `start`, `'done'` is `end`. The `SpeechRecognizer` seam normalises them so `DeviceVoiceProvider` keeps RN's exact settle-once semantics, including the 4s post-`stop()` watchdog. |
| `useVoiceInput.ts` is a React hook with refs for gesture phase | Press-in/press-out resolve faster than React re-renders. | `VoiceInputCubit` — the phase lives in a plain field on the cubit, which is the same "authoritative value, not a mirror of the rendered state" property the refs bought, without the mirror. `AppState` becomes an `AppLifecycleListener` owned by the composer, which calls `cubit.onAppBackgrounded()`; the cubit stays framework-free and directly testable. |
| `app/preview/[id].tsx` (a route) **and** the in-terminal overlay in `TerminalSessionScreen.tsx:1267–1295` (a second WebView) | Expo Router gives the chat menu a route; the terminal renders its own overlay so the PTY stays mounted underneath. | One `RoutesStrings.preview` route, reached from both. Pushing a route does not dispose `TerminalCubit` (the terminal route stays in the stack, its PTY attached), so the overlay's only real property is preserved with one WebView instead of two. The globe's green dot still comes from a poll owned by the terminal route. |
| `getPreview` builds the URL from `httpBase(cfg)` in the API module | RN has no repository layer. | `PreviewRepository.getPreview` returns the daemon's `entry` plus the absolute URL, built from `ServerConfigStore.current` — the same "never trust the daemon's own `previewUrl`, which hardcodes `http://` and its request host" rule, now with a test that pins it for a TLS config. |
| The preview `WebView` gets `headers: authHeaders(cfg)` | The daemon's preview route is behind Bearer auth. | `WebViewController.loadRequest(uri, headers: {'Authorization': 'Bearer …'})`. The header is attached **only** when `PreviewModel.authenticated` is true — an external dev-server preview (`mobileReachablePreviewUrl`) must never receive the Operator password, which is exactly why RN carries the `authenticated` flag. |
| `notificationTarget` returns an Expo Router path (`/session/:id`, `/prs`) | Expo addresses screens by path. | The function ports 1:1 and keeps returning those strings, because the same strings are what a push payload carries and what the deep-link resolver consumes. `resolveDeepLink` maps the path onto a `RoutesStrings` name plus arguments, so tray taps and history taps still share one rule — RN's stated reason for the function existing. |
| `app.json` declares `"scheme": "aomobile"` | Expo generates the native intent filter and URL type. | There is no Expo prebuild. Task 21 writes the `CFBundleURLTypes` entry into `ios/Runner/Info.plist` and the `VIEW`/`BROWSABLE` intent filter into `android/app/src/main/AndroidManifest.xml` by hand, both using the same `aomobile` scheme so existing pairing links and daemon-issued URLs keep working. |
| `app/notifications.tsx` holds list state in the screen | React screens own their state. | `NotificationsCubit`, registered as a **lazy singleton** (like `SessionsCubit`) so the Agents-tab bell badge and the history list read one unread count instead of two. |

## Cross-feature imports introduced here, and why

- `core/telemetry` is imported by `pairing`, `onboarding`, `sessions`, `spawn`, `orchestrator` and
  `chat`. It is core precisely because every feature reports through it (spec: "Telemetry — used from
  every feature").
- `notification` imports `ServerConfigStore` (the push toggle needs to know whether a daemon is
  paired) and is imported by `settings` (the Notifications group) and by `sessions` (the bell).
  Nothing in `notification` imports `sessions`.
- `chat/voice` is imported by `chat`'s composer and by `terminal`'s composer. `terminal` already
  imports `chat/logic/keyboard_inset.dart`, so the direction is established; nothing in `chat/voice`
  imports `terminal`.
- `preview` is imported by `terminal` (the globe) and by `chat` (the menu row). Nothing in `preview`
  imports either.
- `core/deep_link` imports `RoutesStrings` and `notification/logic/notification_view.dart` (for
  `notificationTarget`'s path vocabulary). It is imported by `main.dart` only.

## File structure

The seven `core/telemetry/` files keep RN's own filenames (`events`, `sanitize`, `context`,
`rate_limit`, `daily_active`, `telemetry`, `runtime`), which is what makes their tests land on the
exact paths the spec's ledger names.

**New, under `packages/mobile/lib/`:**

| File | Responsibility |
|---|---|
| `core/telemetry/events.dart` | The event vocabulary and the per-event property allowlist — the privacy contract. |
| `core/telemetry/sanitize.dart` | Turns a caller's raw bag into the subset allowed to leave the device. |
| `core/telemetry/context.dart` | The context every event rides with: client, platform, build mode, app version, schema version. |
| `core/telemetry/rate_limit.dart` | Per-event-name rolling-minute and per-UTC-day caps, plus the restart merge. |
| `core/telemetry/daily_active.dart` | The once-per-UTC-day reservation for the active heartbeat, over a storage seam. |
| `core/telemetry/telemetry.dart` | The capture facade: allowlist gate, kill switch, rate cap, sanitizer, `$process_person_profile`. |
| `core/telemetry/runtime.dart` | The process-wide holder, the `CacheHelper` adapters, `TelemetryConfig`, and `featureUsed`. |
| `feature/notification/logic/notification_view.dart` | Icon/colour/label per notification type, tap target, relative stamp. |
| `feature/notification/logic/push_status.dart` | The push state machine collapsed to one switch, and the failure vocabulary. |
| `feature/notification/logic/push_registration.dart` | The persisted registration record and the pending-unregister queue. |
| `feature/notification/logic/push_registrar.dart` | Acquire a token, unregister the old daemon, register the new one, classify what went wrong. |
| `feature/notification/logic/push_token_source.dart` | The seam in front of FCM: availability, permission, `getToken`. Ships unconfigured. |
| `feature/notification/logic/firebase_push_token_source.dart` | **Task 22 (BLOCKED)** — the FCM-backed token source. |
| `feature/notification/logic/push_service.dart` | **Task 22 (BLOCKED)** — register on connect, route tray taps. |
| `feature/notification/data/model/notification_model.dart` | One notification record. |
| `feature/notification/data/model/notification_page_model.dart` | A page: items, next cursor, unread count. |
| `feature/notification/data/model/params/get_notifications_params.dart` | The list query. |
| `feature/notification/data/model/params/mark_notification_read_params.dart` | The `PATCH` body. |
| `feature/notification/data/model/params/register_push_device_params.dart` | The `POST /push/devices` body. |
| `feature/notification/data/data_source/notification_remote_data_source.dart` | The five REST calls. |
| `feature/notification/data/repository/notification_repository.dart` | Network-gated wrappers. |
| `feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart` (+ `notifications_state.dart` part) | List, paging, optimistic mark-read, mark-all, unread poll. |
| `feature/notification/presentation/notifications_screen/ui/notifications_screen.dart` | Scaffold, app bar, "Mark all read", `BlocListener`. |
| `feature/notification/presentation/notifications_screen/ui/widgets/notifications_body.dart` | Loading / empty / error / list. |
| `feature/notification/presentation/notifications_screen/ui/widgets/notification_row.dart` | One row: tile, title, unread dot, stamp, body. |
| `feature/notification/presentation/notifications_screen/ui/widgets/notification_bell.dart` | The Agents-tab bell with its unread badge. |
| `feature/chat/voice/voice_types.dart` | `VoiceState`, `VoiceMode`, `VoiceCallbacks`, `VoiceProvider` — the seam between the mic UI and any recogniser. |
| `feature/chat/voice/speech_recognizer.dart` | The seam in front of `speech_to_text`, normalised to start/result/error/done. |
| `feature/chat/voice/device_provider.dart` | On-device dictation: locale resolution, segment banking, settle-once, the stop watchdog. |
| `feature/chat/voice/logic/voice_input_cubit.dart` (+ `voice_input_state.dart` part) | Permission, recording lifecycle, live partial, hold vs double-tap-to-latch. |
| `feature/chat/voice/ui/mic_key.dart` | The dictation control and its recording pulse. |
| `feature/chat/voice/ui/voice_strip.dart` | The "Keep holding… / Listening…" live-transcript strip. |
| `feature/preview/logic/preview_url.dart` | Loopback rewriting for a phone, and the README filter behind the green dot. |
| `feature/preview/data/model/preview_model.dart` | Entry, absolute URL, whether it needs the Bearer header. |
| `feature/preview/data/data_source/preview_remote_data_source.dart` | `GET /sessions/{id}/preview`. |
| `feature/preview/data/repository/preview_repository.dart` | Network-gated wrapper that builds the absolute URL from the paired config. |
| `feature/preview/presentation/preview_screen/logic/preview_cubit.dart` (+ `preview_state.dart` part) | The 5s detector poll and the "is there something worth showing" rule. |
| `feature/preview/presentation/preview_screen/ui/preview_screen.dart` | Scaffold, app bar, reload action. |
| `feature/preview/presentation/preview_screen/ui/widgets/preview_body.dart` | Loading / empty / error / the browser. |
| `feature/preview/presentation/preview_screen/ui/widgets/preview_browser.dart` | The `WebViewWidget` and its authenticated `loadRequest`. |
| `core/deep_link/deep_link_target.dart` | `aomobile://…` and `/session/:id` → a route name plus arguments. |
| `core/deep_link/deep_link_service.dart` | Cold-start link + link stream → `Navigator`, over an `AppLinkSource` seam. |

**Modified:**

| File | Change |
|---|---|
| `pubspec.yaml` | `speech_to_text`, `app_links`, `webview_flutter` (Tasks 14, 21, 19); the three Firebase/notification packages in Task 22. |
| `core/api/api_request_helpers/end_points.dart` | `notification(id)`, `notificationsReadAll`, `pushDevices`, `pushDevice(token)`, `sessionPreview(id)`, `sessionPreviewFile(id, entry)`. |
| `core/api/api_request_helpers/api_consumer.dart` + `dio_consumer.dart` | `delete` gains `Options? options`, matching `get`/`post`, so an unregister can target the daemon it was registered with. |
| `core/helpers/cache/cache_keys.dart` | `telemetryRateLimit`. (The daily-active key lives with its storage seam in `daily_active.dart`, and the two push keys live in `push_registration.dart` — that blob holds the connection password and goes to secure storage, never `CacheHelper`.) |
| `core/app_routes/routes_strings.dart` | `notifications`, `preview`. |
| `core/app_routes/app_router.dart` | The `/notifications` and `/preview` cases; `NotificationsCubit` added to the sessions route. |
| `core/utils/service_locator.dart` | `_notificationFeatureSetup()`, `_previewFeatureSetup()`, `_voiceSetup()`; `DeepLinkService` and `PushService` in `_coreSetup()`. |
| `main.dart` | `TelemetryRuntime.init`, the daily-active heartbeat on launch and foreground, `navigatorKey`, `DeepLinkService.start()`. |
| `feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart` | Becomes a `StatefulWidget` solely to report `onboarding_started` on mount; reports `onboarding_skipped` on Skip. |
| `feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart` | Reports `paired {method: qr}` and `onboarding_completed`. |
| `feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart` | Reports `paired {method: manual}`. |
| `feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart` | Reports `connected {trigger}`; `kill`/`restore` report `feature_used`. |
| `feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart` | The bell action. |
| `feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart` | `submit` reports `feature_used {feature: spawn}`. |
| `feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart` | `launch` reports `feature_used {feature: conductor}`. |
| `feature/chat/presentation/chat_screen/logic/chat_cubit.dart` | `send` reports `feature_used {feature: send}`. |
| `feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart` | The voice strip and the mic key. |
| `feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart` | The "Open preview" row. |
| `feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart` | Handles the preview menu action. |
| `feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart` | The globe action and its green dot. |
| `feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart` | The voice strip and the mic key. |
| `feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart` | The Notifications group. |
| `core/widgets/main_widgets/settings_group.dart` | `SettingsToggle`, the switch row the group has never needed until now. |
| `ios/Runner/Info.plist` | `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `CFBundleURLTypes`. |
| `android/app/src/main/AndroidManifest.xml` | `RECORD_AUDIO`, the `RECOGNIZE_SPEECH` query, the `aomobile` intent filter. |

---
### Task 1: The telemetry vocabulary and the sanitizer

Ports `lib/telemetry/events.ts` and `lib/telemetry/sanitize.ts`. The allowlist is the privacy
contract: the phone can see session titles, PR titles, project names, terminal output and the
connection password, and none of them may reach a sink. The sanitizer iterates the **allowlist**,
never the caller's payload, so a property nobody registered is dropped rather than forwarded.

**Files:**
- Create: `packages/mobile/lib/core/telemetry/events.dart`
- Create: `packages/mobile/lib/core/telemetry/sanitize.dart`
- Test: `packages/mobile/test/core/telemetry/sanitize_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `MobileEvents.active/paired/connected/onboardingStarted/onboardingCompleted/onboardingSkipped/notificationOpened/featureUsed`
    (`String` constants) and `MobileEvents.allowlist` (`Map<String, Map<String, PropRule>>`).
  - `PropRule` (sealed) with `OneOfRule(List<String> values)`, `FlagRule()`, `CountRule()`.
  - `Map<String, dynamic> sanitizeMobileProperties(String event, Map<String, dynamic>? properties,
    {Map<String, Map<String, PropRule>> allowlist = MobileEvents.allowlist})`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/core/telemetry/sanitize_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/sanitize.dart';

const Map<String, Map<String, PropRule>> _countAllowlist = {
  'opr.v2.test.counted': {'items': CountRule()},
};

void main() {
  test('keeps allowlisted enum values and flags', () {
    expect(
      sanitizeMobileProperties(MobileEvents.paired, {
        'method': 'qr',
        'from_onboarding': true,
      }),
      {'method': 'qr', 'from_onboarding': true},
    );
  });

  test('drops an enum value outside the closed set', () {
    expect(sanitizeMobileProperties(MobileEvents.paired, {'method': 'nfc'}), isEmpty);
  });

  test('drops any unregistered key, so titles and secrets cannot leak', () {
    expect(
      sanitizeMobileProperties(MobileEvents.featureUsed, {
        'feature': 'spawn',
        'outcome': 'succeeded',
        'session_title': 'fix the auth bug in secret-repo',
        'project': 'acme/secret-repo',
        'password': 'hunter2',
        'terminal_tail': r'$ cat .env',
      }),
      {'feature': 'spawn', 'outcome': 'succeeded'},
    );
  });

  test('returns nothing for an unknown event rather than passing the payload through', () {
    expect(sanitizeMobileProperties('opr.v2.mobile_app.not_a_real_event', {'anything': 'x'}), isEmpty);
    expect(sanitizeMobileProperties(MobileEvents.active, null), isEmpty);
  });

  test('keeps a flag only when the value is a real boolean', () {
    expect(
      sanitizeMobileProperties(MobileEvents.notificationOpened, {
        'target': 'session',
        'cold_start': 'yes',
      }),
      {'target': 'session'},
    );
    expect(
      sanitizeMobileProperties(MobileEvents.notificationOpened, {
        'target': 'session',
        'cold_start': true,
      }),
      {'target': 'session', 'cold_start': true},
    );
  });

  test('keeps a non-negative integer count and drops negatives, doubles and strings', () {
    Map<String, dynamic> counted(Object? value) =>
        sanitizeMobileProperties('opr.v2.test.counted', {'items': value}, allowlist: _countAllowlist);

    expect(counted(0), {'items': 0});
    expect(counted(7), {'items': 7});
    expect(counted(-1), isEmpty);
    expect(counted(1.5), isEmpty);
    expect(counted('7'), isEmpty);
  });
}
```

That is **6 tests**.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/telemetry/sanitize_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:operator_mobile/core/telemetry/events.dart'`.

- [ ] **Step 3: Write the vocabulary**

Create `packages/mobile/lib/core/telemetry/events.dart`:

```dart
sealed class PropRule {
  const PropRule();
}

final class OneOfRule extends PropRule {
  const OneOfRule(this.values);

  final List<String> values;
}

final class FlagRule extends PropRule {
  const FlagRule();
}

final class CountRule extends PropRule {
  const CountRule();
}

sealed class MobileEvents {
  static const String active = 'opr.v2.app.active';
  static const String paired = 'opr.v2.mobile_app.paired';
  static const String connected = 'opr.v2.mobile_app.connected';
  static const String onboardingStarted = 'opr.v2.mobile_app.onboarding_started';
  static const String onboardingCompleted = 'opr.v2.mobile_app.onboarding_completed';
  static const String onboardingSkipped = 'opr.v2.mobile_app.onboarding_skipped';
  static const String notificationOpened = 'opr.v2.mobile_app.notification_opened';
  static const String featureUsed = 'opr.v2.mobile_app.feature_used';

  static const Map<String, Map<String, PropRule>> allowlist = {
    active: {},
    paired: {
      'method': OneOfRule(['qr', 'manual']),
      'from_onboarding': FlagRule(),
    },
    connected: {
      'trigger': OneOfRule(['launch', 'reconnect']),
    },
    onboardingStarted: {},
    onboardingCompleted: {},
    onboardingSkipped: {},
    notificationOpened: {
      'target': OneOfRule(['session', 'prs']),
      'cold_start': FlagRule(),
    },
    featureUsed: {
      'feature': OneOfRule(['spawn', 'merge', 'kill', 'restore', 'conductor', 'send']),
      'outcome': OneOfRule(['succeeded', 'failed']),
    },
  };
}
```

- [ ] **Step 4: Write the sanitizer**

Create `packages/mobile/lib/core/telemetry/sanitize.dart`:

```dart
import 'package:operator_mobile/core/telemetry/events.dart';

Map<String, dynamic> sanitizeMobileProperties(
  String event,
  Map<String, dynamic>? properties, {
  Map<String, Map<String, PropRule>> allowlist = MobileEvents.allowlist,
}) {
  final allowed = allowlist[event];
  if (allowed == null) return {};
  final sanitized = <String, dynamic>{};
  if (properties == null) return sanitized;

  for (final rule in allowed.entries) {
    if (!properties.containsKey(rule.key)) continue;
    final value = properties[rule.key];
    final keep = switch (rule.value) {
      OneOfRule(:final values) => value is String && values.contains(value),
      FlagRule() => value is bool,
      CountRule() => value is int && !value.isNegative,
    };
    if (keep) sanitized[rule.key] = value;
  }
  return sanitized;
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/core/telemetry/sanitize_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 6: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 778/778 green.

```bash
git add packages/mobile/lib/core/telemetry packages/mobile/test/core/telemetry
git commit -m "feat(mobile): add the telemetry vocabulary and its sanitizer"
```

---
### Task 2: The telemetry context

Ports `lib/telemetry/context.ts`. This is what lets any metric be split by where it came from, and
it is pure: it takes the platform, device and version as inputs rather than importing them.

One capability is lost in the port and is deliberate: RN reads `Device.isDevice` from `expo-device`
to tell a simulator from a phone. Flutter has no equivalent without adding `device_info_plus`, which
is not worth a dependency for one string, so `runtime.dart` (Task 5) passes `isPhysicalDevice: true`.
Because `dev` comes from `kDebugMode`, a simulator still reports `build_mode: dev` in every debug
run; only a release build on a simulator misreports as `device`. The three-way mapping stays in the
function and keeps its test, so restoring the real signal later is one argument.

**Files:**
- Create: `packages/mobile/lib/core/telemetry/context.dart`
- Test: `packages/mobile/test/core/telemetry/context_test.dart`

**Interfaces:**
- Consumes: `Equatable`.
- Produces: `kMobileTelemetrySchemaVersion` (`int`), `TelemetryContextInput({required String platformOs,
  required bool isPhysicalDevice, required bool dev, required String appVersion})`,
  `TelemetryContext` with `client`, `platform`, `buildMode`, `appVersion`, `schemaVersion` and
  `toJson()`, and `TelemetryContext buildMobileContext(TelemetryContextInput input)`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/core/telemetry/context_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/telemetry/context.dart';

TelemetryContext context({
  String platformOs = 'ios',
  bool isPhysicalDevice = true,
  bool dev = false,
  String appVersion = '1.1.0',
}) => buildMobileContext(
  TelemetryContextInput(
    platformOs: platformOs,
    isPhysicalDevice: isPhysicalDevice,
    dev: dev,
    appVersion: appVersion,
  ),
);

void main() {
  test('tags the native app as client=mobile with the OS platform', () {
    final built = context();

    expect(built.client, 'mobile');
    expect(built.platform, 'ios');
    expect(built.buildMode, 'device');
    expect(built.appVersion, '1.1.0');
    expect(built.schemaVersion, kMobileTelemetrySchemaVersion);
  });

  test('tags the web build as client=mobile-web so it cannot inflate installs', () {
    final built = context(platformOs: 'web', isPhysicalDevice: false);

    expect(built.client, 'mobile-web');
    expect(built.platform, 'web');
  });

  test('distinguishes dev, simulator and device builds', () {
    expect(context(platformOs: 'android', dev: true).buildMode, 'dev');
    expect(context(platformOs: 'android', isPhysicalDevice: false).buildMode, 'simulator');
    expect(context(platformOs: 'android').buildMode, 'device');
  });

  test('falls back to platform=other and version=unknown for junk input', () {
    final built = context(platformOs: 'windows', appVersion: '   ');

    expect(built.platform, 'other');
    expect(built.appVersion, 'unknown');
  });

  test('serialises the wire keys every event rides with', () {
    expect(context().toJson(), {
      'client': 'mobile',
      'platform': 'ios',
      'build_mode': 'device',
      'app_version': '1.1.0',
      'telemetry_schema_version': kMobileTelemetrySchemaVersion,
    });
  });
}
```

That is **5 tests**.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/telemetry/context_test.dart`
Expected: FAIL — `context.dart` does not exist.

- [ ] **Step 3: Write the context**

Create `packages/mobile/lib/core/telemetry/context.dart`:

```dart
import 'package:equatable/equatable.dart';

const int kMobileTelemetrySchemaVersion = 2;

class TelemetryContextInput extends Equatable {
  const TelemetryContextInput({
    required this.platformOs,
    required this.isPhysicalDevice,
    required this.dev,
    required this.appVersion,
  });

  final String platformOs;
  final bool isPhysicalDevice;
  final bool dev;
  final String appVersion;

  @override
  List<Object?> get props => [platformOs, isPhysicalDevice, dev, appVersion];
}

class TelemetryContext extends Equatable {
  const TelemetryContext({
    required this.client,
    required this.platform,
    required this.buildMode,
    required this.appVersion,
    this.schemaVersion = kMobileTelemetrySchemaVersion,
  });

  final String client;
  final String platform;
  final String buildMode;
  final String appVersion;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
    'client': client,
    'platform': platform,
    'build_mode': buildMode,
    'app_version': appVersion,
    'telemetry_schema_version': schemaVersion,
  };

  @override
  List<Object?> get props => [client, platform, buildMode, appVersion, schemaVersion];
}

TelemetryContext buildMobileContext(TelemetryContextInput input) {
  final version = input.appVersion.trim();
  return TelemetryContext(
    client: input.platformOs == 'web' ? 'mobile-web' : 'mobile',
    platform: switch (input.platformOs) {
      'ios' || 'android' || 'web' => input.platformOs,
      _ => 'other',
    },
    buildMode: input.dev
        ? 'dev'
        : input.isPhysicalDevice
        ? 'device'
        : 'simulator',
    appVersion: version.isEmpty ? 'unknown' : version,
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/telemetry/context_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 783/783 green.

```bash
git add packages/mobile/lib/core/telemetry/context.dart packages/mobile/test/core/telemetry/context_test.dart
git commit -m "feat(mobile): add the telemetry context"
```

---
### Task 3: The per-event rate cap

Ports `lib/telemetry/rateLimit.ts`, which mirrors the desktop sink's bounds
(`backend/internal/adapters/telemetry/ratelimit.go`): at most 5 events per name per rolling minute,
200 per name per UTC day. The daily ceiling is the real backstop against a caller wired into a poll
tick; the minute cap smooths a burst. `mergeRateState` exists for one reason — a restart must not
reset the daily ceiling, and the naive spread lets an in-memory count that advanced before the
persisted state loaded overwrite the higher persisted one.

**Files:**
- Create: `packages/mobile/lib/core/telemetry/rate_limit.dart`
- Test: `packages/mobile/test/core/telemetry/rate_limit_test.dart`

**Interfaces:**
- Consumes: `Equatable`.
- Produces: `kEventsPerNamePerMinute` / `kEventsPerNamePerDay` (`int`), `NameWindow({required int
  minuteStart, required int minuteCount, required String day, required int dayCount})` with
  `fromJson`/`toJson`, `typedef RateLimitState = Map<String, NameWindow>`, `RateLimitDecision({required
  bool allowed, required RateLimitState state})`, `RateLimitDecision checkRateLimit(RateLimitState
  state, String name, int nowMs, {int perMinute, int perDay})`, and `RateLimitState
  mergeRateState(RateLimitState persisted, RateLimitState current)`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/core/telemetry/rate_limit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/telemetry/rate_limit.dart';

final int t0 = DateTime.utc(2026, 8, 7, 10).millisecondsSinceEpoch;

const String feature = 'opr.v2.mobile_app.feature_used';

({RateLimitState state, List<bool> results}) run(int count, {RateLimitState start = const {}}) {
  var state = start;
  final results = <bool>[];
  for (var i = 0; i < count; i++) {
    final decision = checkRateLimit(state, feature, t0);
    state = decision.state;
    results.add(decision.allowed);
  }
  return (state: state, results: results);
}

NameWindow window({int minuteStart = 0, int minuteCount = 0, String day = '2026-08-07', int dayCount = 0}) =>
    NameWindow(minuteStart: minuteStart, minuteCount: minuteCount, day: day, dayCount: dayCount);

void main() {
  test('allows up to the per-minute cap, then denies within the same minute', () {
    final outcome = run(kEventsPerNamePerMinute + 3);

    expect(outcome.results.take(kEventsPerNamePerMinute), everyElement(isTrue));
    expect(outcome.results.skip(kEventsPerNamePerMinute), everyElement(isFalse));
  });

  test('reopens the minute window after 60s', () {
    final outcome = run(kEventsPerNamePerMinute);

    expect(checkRateLimit(outcome.state, feature, t0 + 61000).allowed, isTrue);
  });

  test('enforces the daily ceiling across many minute windows', () {
    var state = <String, NameWindow>{};
    var allowed = 0;
    for (var i = 0; i < kEventsPerNamePerDay + 50; i++) {
      final decision = checkRateLimit(state, 'opr.v2.mobile_app.connected', t0 + i * 30000);
      state = decision.state;
      if (decision.allowed) allowed++;
    }

    expect(allowed, kEventsPerNamePerDay);
  });

  test('resets the daily counter on a new UTC day', () {
    var state = <String, NameWindow>{};
    for (var i = 0; i < kEventsPerNamePerDay; i++) {
      state = checkRateLimit(state, 'opr.v2.app.active', t0 + i * 1000).state;
    }

    final capped = checkRateLimit(state, 'opr.v2.app.active', t0 + 5000);
    expect(capped.allowed, isFalse);

    final nextDay = checkRateLimit(
      capped.state,
      'opr.v2.app.active',
      DateTime.utc(2026, 8, 8, 0, 1).millisecondsSinceEpoch,
    );
    expect(nextDay.allowed, isTrue);
  });

  test('caps each event name independently', () {
    var state = <String, NameWindow>{};
    for (var i = 0; i < kEventsPerNamePerMinute; i++) {
      state = checkRateLimit(state, 'a', t0).state;
    }

    expect(checkRateLimit(state, 'a', t0).allowed, isFalse);
    expect(checkRateLimit(state, 'b', t0).allowed, isTrue);
  });

  test('keeps the higher day count for the same day, so a restart cannot reset it', () {
    final merged = mergeRateState(
      {feature: window(dayCount: 199)},
      {feature: window(minuteStart: 1, minuteCount: 1, dayCount: 1)},
    );

    expect(merged[feature]!.dayCount, 199);
  });

  test('drops a persisted entry from an older day', () {
    final merged = mergeRateState(
      {'x': window(day: '2026-08-06', dayCount: 200)},
      {'x': window(minuteCount: 1, dayCount: 1)},
    );

    expect(merged['x']!.dayCount, 1);
  });

  test('carries a persisted name the current session has not touched, and survives a round trip', () {
    final merged = mergeRateState({'y': window(dayCount: 42)}, const {});

    expect(merged['y']!.dayCount, 42);
    expect(NameWindow.fromJson(merged['y']!.toJson()), merged['y']);
  });
}
```

That is **8 tests**. The file deliberately uses the raw `'opr.v2.app.active'` string rather than
importing `MobileEvents`, so the rate cap's tests stay independent of the vocabulary.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/telemetry/rate_limit_test.dart`
Expected: FAIL — `rate_limit.dart` does not exist.

- [ ] **Step 3: Write the rate cap**

Create `packages/mobile/lib/core/telemetry/rate_limit.dart`:

```dart
import 'package:equatable/equatable.dart';

const int kEventsPerNamePerMinute = 5;
const int kEventsPerNamePerDay = 200;

typedef RateLimitState = Map<String, NameWindow>;

class NameWindow extends Equatable {
  const NameWindow({
    required this.minuteStart,
    required this.minuteCount,
    required this.day,
    required this.dayCount,
  });

  final int minuteStart;
  final int minuteCount;
  final String day;
  final int dayCount;

  factory NameWindow.fromJson(Map<String, dynamic> json) => NameWindow(
    minuteStart: (json['minuteStart'] as num?)?.toInt() ?? 0,
    minuteCount: (json['minuteCount'] as num?)?.toInt() ?? 0,
    day: json['day'] as String? ?? '',
    dayCount: (json['dayCount'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'minuteStart': minuteStart,
    'minuteCount': minuteCount,
    'day': day,
    'dayCount': dayCount,
  };

  @override
  List<Object?> get props => [minuteStart, minuteCount, day, dayCount];
}

class RateLimitDecision extends Equatable {
  const RateLimitDecision({required this.allowed, required this.state});

  final bool allowed;
  final RateLimitState state;

  @override
  List<Object?> get props => [allowed, state];
}

String _utcDay(int nowMs) =>
    DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true).toIso8601String().substring(0, 10);

RateLimitDecision checkRateLimit(
  RateLimitState state,
  String name,
  int nowMs, {
  int perMinute = kEventsPerNamePerMinute,
  int perDay = kEventsPerNamePerDay,
}) {
  final previous = state[name];
  final day = _utcDay(nowMs);
  final minuteStart = previous != null && nowMs - previous.minuteStart < 60000
      ? previous.minuteStart
      : nowMs;
  final minuteCount = previous != null && previous.minuteStart == minuteStart
      ? previous.minuteCount
      : 0;
  final dayCount = previous != null && previous.day == day ? previous.dayCount : 0;
  final allowed = minuteCount < perMinute && dayCount < perDay;

  return RateLimitDecision(
    allowed: allowed,
    state: {
      ...state,
      name: NameWindow(
        minuteStart: minuteStart,
        minuteCount: allowed ? minuteCount + 1 : minuteCount,
        day: day,
        dayCount: allowed ? dayCount + 1 : dayCount,
      ),
    },
  );
}

RateLimitState mergeRateState(RateLimitState persisted, RateLimitState current) {
  final merged = {...persisted};
  for (final entry in current.entries) {
    final previous = merged[entry.key];
    if (previous == null || previous.day != entry.value.day) {
      merged[entry.key] = entry.value;
      continue;
    }
    merged[entry.key] = NameWindow(
      day: entry.value.day,
      dayCount: previous.dayCount > entry.value.dayCount ? previous.dayCount : entry.value.dayCount,
      minuteStart: previous.minuteStart > entry.value.minuteStart
          ? previous.minuteStart
          : entry.value.minuteStart,
      minuteCount: previous.minuteCount > entry.value.minuteCount
          ? previous.minuteCount
          : entry.value.minuteCount,
    );
  }
  return merged;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/telemetry/rate_limit_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 791/791 green.

```bash
git add packages/mobile/lib/core/telemetry/rate_limit.dart packages/mobile/test/core/telemetry/rate_limit_test.dart
git commit -m "feat(mobile): add the telemetry per-event rate cap"
```

---
### Task 4: The once-per-UTC-day active gate

Ports `lib/telemetry/dailyActive.ts`. Daily actives is a unique count, so emitting more than once a
day per install buys nothing and only costs events. The gate never throws: a storage failure falls
back to allowing the emit, because under-reporting a returning user is worse than a rare duplicate,
and the duplicate is bounded to one per app start.

**Files:**
- Create: `packages/mobile/lib/core/telemetry/daily_active.dart`
- Test: `packages/mobile/test/core/telemetry/daily_active_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `kActiveStorageKey` (`String`, `'opr.telemetry.activeDay'`), `abstract class ActiveStorage`
  with `Future<String?> getItem(String key)` and `Future<void> setItem(String key, String value)`, and
  `Future<bool> reserveDailyActive(ActiveStorage? storage, DateTime now)`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/core/telemetry/daily_active_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/telemetry/daily_active.dart';

class _MemoryStorage implements ActiveStorage {
  _MemoryStorage([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> getItem(String key) async => values[key];

  @override
  Future<void> setItem(String key, String value) async => values[key] = value;
}

class _ThrowingStorage implements ActiveStorage {
  @override
  Future<String?> getItem(String key) async => throw StateError('keystore locked');

  @override
  Future<void> setItem(String key, String value) async => throw StateError('keystore locked');
}

void main() {
  test('returns true once per UTC day and false for the rest of that day', () async {
    final storage = _MemoryStorage();

    expect(await reserveDailyActive(storage, DateTime.utc(2026, 8, 6, 0, 5)), isTrue);
    expect(await reserveDailyActive(storage, DateTime.utc(2026, 8, 6, 9)), isFalse);
    expect(await reserveDailyActive(storage, DateTime.utc(2026, 8, 6, 23, 59, 59)), isFalse);
    expect(await reserveDailyActive(storage, DateTime.utc(2026, 8, 7)), isTrue);
  });

  test('persists the reserved day', () async {
    final storage = _MemoryStorage();

    await reserveDailyActive(storage, DateTime.utc(2026, 8, 6, 10));

    expect(storage.values[kActiveStorageKey], '2026-08-06');
  });

  test('reads a day already reported by a previous launch as spent', () async {
    final storage = _MemoryStorage({kActiveStorageKey: '2026-08-06'});

    expect(await reserveDailyActive(storage, DateTime.utc(2026, 8, 6, 14)), isFalse);
  });

  test('allows the emit when storage is unavailable', () async {
    expect(await reserveDailyActive(null, DateTime.utc(2026, 8, 6, 10)), isTrue);
  });

  test('allows the emit when storage throws rather than losing the user', () async {
    expect(await reserveDailyActive(_ThrowingStorage(), DateTime.utc(2026, 8, 6, 10)), isTrue);
  });
}
```

That is **5 tests**.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/telemetry/daily_active_test.dart`
Expected: FAIL — `daily_active.dart` does not exist.

- [ ] **Step 3: Write the gate**

Create `packages/mobile/lib/core/telemetry/daily_active.dart`:

```dart
const String kActiveStorageKey = 'opr.telemetry.activeDay';

abstract class ActiveStorage {
  Future<String?> getItem(String key);

  Future<void> setItem(String key, String value);
}

Future<bool> reserveDailyActive(ActiveStorage? storage, DateTime now) async {
  if (storage == null) return true;
  final today = now.toUtc().toIso8601String().substring(0, 10);
  try {
    final stored = await storage.getItem(kActiveStorageKey);
    if (stored == today) return false;
    await storage.setItem(kActiveStorageKey, today);
    return true;
  } catch (_) {
    return true;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/telemetry/daily_active_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 796/796 green.

```bash
git add packages/mobile/lib/core/telemetry/daily_active.dart packages/mobile/test/core/telemetry/daily_active_test.dart
git commit -m "feat(mobile): add the daily-active telemetry gate"
```

---
### Task 5: The capture facade and the runtime holder

Ports `lib/telemetry/telemetry.ts` and `lib/telemetry/runtime.ts`. Everything the app calls goes
through the facade, so the allowlist gate, the build-time kill switch, the rate cap and the sanitizer
are the only paths to a sink. The runtime is the process-wide holder plus the `CacheHelper` adapters.

**This is where the "no PostHog key" decision lands:** `TelemetryRuntime.init` builds a facade only
when it is handed a `MobileTelemetryClient`, and `main.dart` (Task 6) hands it none. `instance` stays
`null`, so every call site is a no-op — the same behavior as the keyless RN build in the field — while
the facade and everything behind it is exercised by tests through a recording fake.

**Files:**
- Create: `packages/mobile/lib/core/telemetry/telemetry.dart`
- Create: `packages/mobile/lib/core/telemetry/runtime.dart`
- Modify: `packages/mobile/lib/core/helpers/cache/cache_keys.dart`
- Test: `packages/mobile/test/core/telemetry/telemetry_test.dart`
- Test: `packages/mobile/test/core/telemetry/runtime_test.dart`

**Interfaces:**
- Consumes: `MobileEvents`, `sanitizeMobileProperties`, `reserveDailyActive`, `ActiveStorage`,
  `checkRateLimit`, `mergeRateState`, `NameWindow`, `RateLimitState`, `buildMobileContext`,
  `TelemetryContextInput`, `CacheHelper`, `CacheKeys`.
- Produces:
  - `abstract class MobileTelemetryClient` with `void capture(String event, Map<String, dynamic>
    properties)` and `void register(Map<String, dynamic> properties)`.
  - `MobileTelemetry(MobileTelemetryClient client, Map<String, dynamic> context, {List<String>
    disabledEvents, bool Function(String event)? allow})` with `void capture(String event,
    [Map<String, dynamic>? properties])` and `Future<void> active(ActiveStorage? storage, [DateTime? now])`.
  - `sealed class TelemetryConfig` with `disabled` and `disabledEvents`.
  - `class CacheActiveStorage implements ActiveStorage`.
  - `sealed class TelemetryRuntime` with `instance`, `init({MobileTelemetryClient? client, required
    TelemetryContextInput context, List<String>? disabledEvents})`, `capture(String event,
    [Map<String, dynamic>? properties])`, `featureUsed(String feature, {required bool succeeded})`,
    `Future<void> active([DateTime? now])` and `reset()`.
  - `CacheKeys.telemetryRateLimit`.

- [ ] **Step 1: Write the failing tests**

Create `packages/mobile/test/core/telemetry/telemetry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/telemetry/daily_active.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/telemetry.dart';

class RecordingClient implements MobileTelemetryClient {
  final List<({String event, Map<String, dynamic> properties})> captures = [];
  final List<Map<String, dynamic>> registrations = [];

  @override
  void capture(String event, Map<String, dynamic> properties) =>
      captures.add((event: event, properties: properties));

  @override
  void register(Map<String, dynamic> properties) => registrations.add(properties);
}

class _MemoryStorage implements ActiveStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> getItem(String key) async => values[key];

  @override
  Future<void> setItem(String key, String value) async => values[key] = value;
}

void main() {
  late RecordingClient client;

  setUp(() => client = RecordingClient());

  test('registers the context as super-properties once on creation', () {
    MobileTelemetry(client, const {'client': 'mobile', 'platform': 'ios'});

    expect(client.registrations, [
      {'client': 'mobile', 'platform': 'ios'},
    ]);
  });

  test('sanitizes properties on capture, dropping anything unregistered', () {
    MobileTelemetry(client, const {}).capture(MobileEvents.featureUsed, {
      'feature': 'spawn',
      'outcome': 'succeeded',
      'session_title': 'leak me',
      'password': 'hunter2',
    });

    expect(client.captures.single.event, MobileEvents.featureUsed);
    expect(client.captures.single.properties, {
      'feature': 'spawn',
      'outcome': 'succeeded',
      r'$process_person_profile': false,
    });
  });

  test('drops an event name that is not in the allowlist', () {
    MobileTelemetry(client, const {}).capture('opr.v2.mobile_app.typo', {'feature': 'spawn'});

    expect(client.captures, isEmpty);
  });

  test('stamps the anonymous-rate flag on every event', () {
    MobileTelemetry(client, const {}).capture(MobileEvents.paired, {'method': 'qr'});

    expect(client.captures.single.properties[r'$process_person_profile'], isFalse);
  });

  test('drops an event named in the build-time kill switch', () {
    final telemetry = MobileTelemetry(
      client,
      const {},
      disabledEvents: const [MobileEvents.connected],
    );

    telemetry.capture(MobileEvents.connected, {'trigger': 'launch'});
    telemetry.capture(MobileEvents.paired, {'method': 'qr'});

    expect(client.captures.map((capture) => capture.event), [MobileEvents.paired]);
  });

  test('drops an event the rate limiter rejects', () {
    var calls = 0;
    final telemetry = MobileTelemetry(client, const {}, allow: (_) => ++calls <= 1);

    telemetry.capture(MobileEvents.paired, {'method': 'qr'});
    telemetry.capture(MobileEvents.paired, {'method': 'qr'});

    expect(client.captures, hasLength(1));
  });

  test('emits the daily active heartbeat once per UTC day', () async {
    final telemetry = MobileTelemetry(client, const {});
    final storage = _MemoryStorage();

    await telemetry.active(storage, DateTime.utc(2026, 8, 6, 1));
    await telemetry.active(storage, DateTime.utc(2026, 8, 6, 20));
    await telemetry.active(storage, DateTime.utc(2026, 8, 7, 0, 1));

    expect(client.captures.map((capture) => capture.event), [
      MobileEvents.active,
      MobileEvents.active,
    ]);
  });

  test('marks the active day in storage', () async {
    final storage = _MemoryStorage();

    await MobileTelemetry(client, const {}).active(storage, DateTime.utc(2026, 8, 6, 1));

    expect(storage.values[kActiveStorageKey], '2026-08-06');
  });
}
```

That is **8 tests**.

Create `packages/mobile/test/core/telemetry/runtime_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/rate_limit.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'telemetry_test.dart' show RecordingClient;

const TelemetryContextInput _context = TelemetryContextInput(
  platformOs: 'ios',
  isPhysicalDevice: true,
  dev: false,
  appVersion: '1.1.0',
);

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    TelemetryRuntime.reset();
  });

  tearDown(TelemetryRuntime.reset);

  test('stays null without a client, and every capture is a no-op', () {
    TelemetryRuntime.init(context: _context);

    expect(TelemetryRuntime.instance, isNull);
    TelemetryRuntime.capture(MobileEvents.paired, {'method': 'qr'});
    TelemetryRuntime.featureUsed('spawn', succeeded: true);
  });

  test('registers the built context and captures through the client it is given', () {
    final client = RecordingClient();

    TelemetryRuntime.init(client: client, context: _context);
    TelemetryRuntime.capture(MobileEvents.paired, {'method': 'qr'});

    expect(client.registrations.single['client'], 'mobile');
    expect(client.registrations.single['app_version'], '1.1.0');
    expect(client.captures.single.event, MobileEvents.paired);
  });

  test('reports both outcomes of a feature', () {
    final client = RecordingClient();
    TelemetryRuntime.init(client: client, context: _context);

    TelemetryRuntime.featureUsed('kill', succeeded: true);
    TelemetryRuntime.featureUsed('kill', succeeded: false);

    expect(client.captures.map((capture) => capture.properties['outcome']), [
      'succeeded',
      'failed',
    ]);
  });

  test('seeds the daily ceiling from persisted state so a restart cannot reset it', () async {
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    SharedPreferences.setMockInitialValues({
      CacheKeys.telemetryRateLimit: jsonEncode({
        MobileEvents.paired: NameWindow(
          minuteStart: 0,
          minuteCount: 0,
          day: today,
          dayCount: kEventsPerNamePerDay,
        ).toJson(),
      }),
    });
    await CacheHelper.init();
    final client = RecordingClient();

    TelemetryRuntime.init(client: client, context: _context);
    TelemetryRuntime.capture(MobileEvents.paired, {'method': 'qr'});

    expect(client.captures, isEmpty);
  });
}
```

That is **4 tests**.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/telemetry/telemetry_test.dart test/core/telemetry/runtime_test.dart`
Expected: FAIL — `telemetry.dart` and `runtime.dart` do not exist.

- [ ] **Step 3: Write the facade**

Create `packages/mobile/lib/core/telemetry/telemetry.dart`:

```dart
import 'package:operator_mobile/core/telemetry/daily_active.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/sanitize.dart';

abstract class MobileTelemetryClient {
  void capture(String event, Map<String, dynamic> properties);

  void register(Map<String, dynamic> properties);
}

bool _allowEverything(String event) => true;

class MobileTelemetry {
  MobileTelemetry(
    this._client,
    Map<String, dynamic> context, {
    List<String> disabledEvents = const [],
    bool Function(String event)? allow,
  }) : _denied = disabledEvents.toSet(),
       _allow = allow ?? _allowEverything {
    _client.register(context);
  }

  final MobileTelemetryClient _client;
  final Set<String> _denied;
  final bool Function(String event) _allow;

  void capture(String event, [Map<String, dynamic>? properties]) {
    if (!MobileEvents.allowlist.containsKey(event)) return;
    if (_denied.contains(event)) return;
    if (!_allow(event)) return;
    _client.capture(event, {
      ...sanitizeMobileProperties(event, properties),
      r'$process_person_profile': false,
    });
  }

  Future<void> active(ActiveStorage? storage, [DateTime? now]) async {
    if (await reserveDailyActive(storage, now ?? DateTime.now())) {
      capture(MobileEvents.active);
    }
  }
}
```

- [ ] **Step 4: Write the runtime holder**

Add to `packages/mobile/lib/core/helpers/cache/cache_keys.dart`, beside the existing members:

```dart
  static const String telemetryRateLimit = 'opr.telemetry.rateLimit';
```

Create `packages/mobile/lib/core/telemetry/runtime.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/telemetry/context.dart';
import 'package:operator_mobile/core/telemetry/daily_active.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/rate_limit.dart';
import 'package:operator_mobile/core/telemetry/telemetry.dart';

export 'package:operator_mobile/core/telemetry/context.dart' show TelemetryContextInput;
export 'package:operator_mobile/core/telemetry/telemetry.dart' show MobileTelemetryClient;

sealed class TelemetryConfig {
  static const bool disabled =
      String.fromEnvironment('OPERATOR_TELEMETRY_DISABLED') == '1';

  static const String _disabledEventsRaw =
      String.fromEnvironment('OPERATOR_TELEMETRY_DISABLED_EVENTS');

  static List<String> get disabledEvents => _disabledEventsRaw
      .split(',')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();
}

class CacheActiveStorage implements ActiveStorage {
  const CacheActiveStorage();

  @override
  Future<String?> getItem(String key) async => CacheHelper.get(key) as String?;

  @override
  Future<void> setItem(String key, String value) => CacheHelper.save(key, value);
}

sealed class TelemetryRuntime {
  static MobileTelemetry? _telemetry;
  static RateLimitState _rateState = {};
  static bool _rateStateLoaded = false;

  static MobileTelemetry? get instance => _telemetry;

  static void init({
    MobileTelemetryClient? client,
    required TelemetryContextInput context,
    List<String>? disabledEvents,
  }) {
    if (_telemetry != null || client == null || TelemetryConfig.disabled) return;
    _loadRateState();
    _telemetry = MobileTelemetry(
      client,
      buildMobileContext(context).toJson(),
      disabledEvents: disabledEvents ?? TelemetryConfig.disabledEvents,
      allow: _allowEvent,
    );
  }

  static void capture(String event, [Map<String, dynamic>? properties]) =>
      _telemetry?.capture(event, properties);

  static void featureUsed(String feature, {required bool succeeded}) => capture(
    MobileEvents.featureUsed,
    {'feature': feature, 'outcome': succeeded ? 'succeeded' : 'failed'},
  );

  static Future<void> active([DateTime? now]) async {
    await _telemetry?.active(const CacheActiveStorage(), now);
  }

  static void reset() {
    _telemetry = null;
    _rateState = {};
    _rateStateLoaded = false;
  }

  static void _loadRateState() {
    if (_rateStateLoaded) return;
    _rateStateLoaded = true;
    final raw = CacheHelper.get(CacheKeys.telemetryRateLimit) as String?;
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _rateState = mergeRateState(
        decoded.map(
          (name, window) => MapEntry(name, NameWindow.fromJson(window as Map<String, dynamic>)),
        ),
        _rateState,
      );
    } catch (_) {
      _rateState = <String, NameWindow>{};
    }
  }

  static bool _allowEvent(String event) {
    final decision = checkRateLimit(
      _rateState,
      event,
      DateTime.now().millisecondsSinceEpoch,
    );
    _rateState = decision.state;
    unawaited(
      CacheHelper.save(
        CacheKeys.telemetryRateLimit,
        jsonEncode(_rateState.map((name, window) => MapEntry(name, window.toJson()))),
      ),
    );
    return decision.allowed;
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/core/telemetry/telemetry_test.dart test/core/telemetry/runtime_test.dart`
Expected: PASS, 12 tests.

- [ ] **Step 6: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 808/808 green.

```bash
git add packages/mobile/lib/core/telemetry packages/mobile/lib/core/helpers/cache/cache_keys.dart packages/mobile/test/core/telemetry
git commit -m "feat(mobile): add the telemetry capture facade and runtime"
```

---
### Task 6: The call sites

Wires every event the vocabulary declares to the place that already knows the outcome. RN's
`trackFeature` wraps a throwing call; this codebase's repositories return `Result`, so the outcome
comes from the `onSuccess`/`onFailure` branch that already exists — `TelemetryRuntime.featureUsed`
instead of a wrapper. `merge` has no UI call site yet (see "What M5 deliberately does not include");
its vocabulary entry stays so the button needs no schema change.

`main.dart` calls `TelemetryRuntime.init` **without a client**, so all of this is inert in a shipped
build until a sink exists. It is still wired now, because wiring it later means touching nine files
again.

**Files:**
- Modify: `packages/mobile/lib/main.dart`
- Modify: `packages/mobile/lib/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart`
- Modify: `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart`
- Modify: `packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart`
- Modify: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart`
- Modify: `packages/mobile/lib/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart`
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/logic/chat_cubit.dart`
- Test: `packages/mobile/test/core/telemetry/call_sites_test.dart`

**Interfaces:**
- Consumes: `TelemetryRuntime`, `MobileEvents`.
- Produces: no new types. `SessionsCubit` gains private `_connectionOpen` / `_everConnected` flags.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/core/telemetry/call_sites_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart';
import 'package:operator_mobile/feature/orchestrator/data/model/params/launch_orchestrator_params.dart';
import 'package:operator_mobile/feature/orchestrator/data/repository/orchestrator_repository.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'telemetry_test.dart' show RecordingClient;

class _MockPairingRepository extends Mock implements PairingRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockSpawnRepository extends Mock implements SpawnRepository {}

class _MockOrchestratorRepository extends Mock implements OrchestratorRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

const ServerConfig _config = ServerConfig(
  host: '10.0.0.5',
  httpPort: '3011',
  secure: false,
  password: 'secret12',
);

final String _qr = jsonEncode({
  'v': 1,
  'host': '10.0.0.5',
  'port': '3011',
  'password': 'secret12',
});

void main() {
  late RecordingClient client;

  setUpAll(() {
    registerFallbackValue(const ServerConfig(host: '', httpPort: '', secure: false, password: ''));
    registerFallbackValue(const LaunchOrchestratorParams(projectId: 'p', clean: false, mode: 'chat'));
    registerFallbackValue(
      const SpawnSessionParams(projectId: 'p', mode: 'chat', prompt: 'x', issueId: 'y', harness: 'codex'),
    );
  });

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    TelemetryRuntime.reset();
    client = RecordingClient();
    TelemetryRuntime.init(
      client: client,
      context: const TelemetryContextInput(
        platformOs: 'ios',
        isPhysicalDevice: true,
        dev: false,
        appVersion: '1.1.0',
      ),
    );
  });

  tearDown(TelemetryRuntime.reset);

  List<String> events() => client.captures.map((capture) => capture.event).toList();

  test('a QR pairing reports paired and completes onboarding', () async {
    final repository = _MockPairingRepository();
    final store = _MockServerConfigStore();
    when(() => store.current).thenReturn(null);
    when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(true));
    final cubit = PairingScanCubit(repository, store, fromOnboarding: true);

    await cubit.onScan(_qr, TargetPlatform.iOS);

    expect(events(), [MobileEvents.paired, MobileEvents.onboardingCompleted]);
    expect(client.captures.first.properties['method'], 'qr');
    expect(client.captures.first.properties['from_onboarding'], isTrue);
    await cubit.close();
  });

  test('a manual connect reports paired with method=manual', () async {
    final repository = _MockPairingRepository();
    final store = _MockServerConfigStore();
    when(() => store.current).thenReturn(_config);
    when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(true));
    final cubit = ManualConnectCubit(repository, store);

    await cubit.connect(TargetPlatform.iOS);

    expect(events(), [MobileEvents.paired]);
    expect(client.captures.single.properties['method'], 'manual');
    await cubit.close();
  });

  testWidgets('the onboarding screen reports started on mount and skipped on Skip', (tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => const MaterialApp(home: OnboardingScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(events(), [MobileEvents.onboardingStarted]);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(events(), [MobileEvents.onboardingStarted, MobileEvents.onboardingSkipped]);
  });

  test('the board reports connected once per open, with launch then reconnect', () async {
    final repository = _MockSessionsRepository();
    final mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    var fail = false;
    when(() => repository.getBoard()).thenAnswer(
      (_) async => fail
          ? Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: 503))
          : Result.success(const GlobalResponse(data: BoardSnapshot())),
    );
    final cubit = SessionsCubit(repository, mux);
    await Future<void>.delayed(Duration.zero);

    fail = true;
    await cubit.refresh();
    fail = false;
    await cubit.refresh();

    expect(events(), [MobileEvents.connected, MobileEvents.connected]);
    expect(
      client.captures.map((capture) => capture.properties['trigger']),
      ['launch', 'reconnect'],
    );
    await cubit.close();
  });

  test('kill and restore report their feature and outcome', () async {
    final repository = _MockSessionsRepository();
    final mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(const GlobalResponse(data: BoardSnapshot())),
    );
    when(() => repository.kill(any())).thenAnswer((_) async => Result.success(true));
    when(() => repository.restore(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'nope', message: 'nope', statusCode: 500)),
    );
    final cubit = SessionsCubit(repository, mux);
    await Future<void>.delayed(Duration.zero);
    client.captures.clear();

    await cubit.kill('s-1');
    await cubit.restore('s-1');

    expect(
      client.captures.where((capture) => capture.event == MobileEvents.featureUsed).map(
        (capture) => '${capture.properties['feature']}:${capture.properties['outcome']}',
      ),
      ['kill:succeeded', 'restore:failed'],
    );
    await cubit.close();
  });

  test('spawning reports feature_used with the spawn feature', () async {
    final repository = _MockSpawnRepository();
    when(() => repository.spawn(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'no', message: 'no', statusCode: 500)),
    );
    final cubit = SpawnCubit(repository)
      ..projectId = 'p-1'
      ..name = 'fix'
      ..prompt = 'do the thing';

    await cubit.submit();

    expect(client.captures.single.properties['feature'], 'spawn');
    expect(client.captures.single.properties['outcome'], 'failed');
    await cubit.close();
  });

  test('launching the conductor reports feature_used with the conductor feature', () async {
    final repository = _MockOrchestratorRepository();
    when(() => repository.launch(any())).thenAnswer(
      (_) async => Result.success(const GlobalResponse<OrchestratorModel>()),
    );
    final cubit = OrchestratorCubit(repository);

    await cubit.launch('p-1', clean: false);

    expect(client.captures.single.properties['feature'], 'conductor');
    expect(client.captures.single.properties['outcome'], 'succeeded');
    await cubit.close();
  });
}
```

That is **7 tests**. The `send` call site is covered separately, because a `ChatCubit` needs the full
catalogue stubbed — append to
`packages/mobile/test/feature/chat/presentation/chat_screen/logic/chat_cubit_actions_test.dart`,
inside its existing `main()`, with these imports added at the top of that file:

```dart
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';

import '../../../../../core/telemetry/telemetry_test.dart' show RecordingClient;
```

```dart
  test('a delivered message reports feature_used with the send feature', () async {
    TelemetryRuntime.reset();
    final client = RecordingClient();
    TelemetryRuntime.init(
      client: client,
      context: const TelemetryContextInput(
        platformOs: 'ios',
        isPhysicalDevice: true,
        dev: false,
        appVersion: '1.1.0',
      ),
    );
    addTearDown(TelemetryRuntime.reset);
    when(() => repository.sendMessage(any(), any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'offline', statusCode: 503)),
    );
    final cubit = build();

    await cubit.send('ship it');

    expect(
      client.captures.where((capture) => capture.event == MobileEvents.featureUsed).single.properties,
      containsPair('feature', 'send'),
    );
    await cubit.close();
  });
```

That is **1 test**. Task 6 adds **8 tests** in total.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/telemetry/call_sites_test.dart test/feature/chat/presentation/chat_screen/logic/chat_cubit_actions_test.dart`
Expected: FAIL — no events are captured (the call sites do not exist yet), and `OnboardingScreen` has
no mount hook.

- [ ] **Step 3: Report pairing and onboarding**

In `pairing_scan_cubit.dart`, add the import and replace the success branch:

```dart
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
```

```dart
      onSuccess: (_) {
        TelemetryRuntime.capture(MobileEvents.paired, {
          'method': 'qr',
          'from_onboarding': fromOnboarding,
        });
        if (fromOnboarding) TelemetryRuntime.capture(MobileEvents.onboardingCompleted);
        emit(const VerifySuccessState());
      },
```

In `manual_connect_cubit.dart`, with the same two imports:

```dart
      onSuccess: (_) {
        TelemetryRuntime.capture(MobileEvents.paired, {'method': 'manual'});
        emit(const ConnectSuccessState());
      },
```

In `onboarding_screen.dart`, turn the screen into a `StatefulWidget` — the one lifecycle hook the
conventions allow a screen to own, because "the user reached onboarding" is a mount fact no cubit
holds — and report both events:

```dart
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  @override
  void initState() {
    super.initState();
    TelemetryRuntime.capture(MobileEvents.onboardingStarted);
  }

  Future<void> _skip(BuildContext context) async {
    TelemetryRuntime.capture(MobileEvents.onboardingSkipped);
    await CacheHelper.save(CacheKeys.onboardingSkipped, true);
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.sessions, (_) => false);
  }

  void _pair(BuildContext context) {
    Navigator.of(context).pushNamed(RoutesStrings.pairingScan, arguments: {'fromOnboarding': true});
  }

  @override
  Widget build(BuildContext context) {
```

The body of `build` is unchanged; only `_skip`/`_pair` move onto the state class and the two
`() => _skip(context)` / `() => _pair(context)` call sites stay as they are.

- [ ] **Step 4: Report the connection and the board's features**

In `sessions_cubit.dart`, add the two imports and two fields, and change `_tick`:

```dart
  bool _connectionOpen = false;
  bool _everConnected = false;
```

```dart
    result.when(
      onSuccess: (response) {
        final board = response.data ?? const BoardSnapshot();
        sessions = board.sessions;
        orchestrators = board.orchestrators;
        projects = board.projects;
        if (!_connectionOpen) {
          _connectionOpen = true;
          TelemetryRuntime.capture(MobileEvents.connected, {
            'trigger': _everConnected ? 'reconnect' : 'launch',
          });
          _everConnected = true;
        }
        _emitSessions();
      },
      onFailure: (failure) {
        _connectionOpen = false;
        emit(GetSessionsFailureState(failure));
        if (!shouldKeepPolling(failure.statusCode)) {
          _stopped = true;
          _pollTimer?.cancel();
        }
      },
    );
```

And both actions:

```dart
  Future<void> kill(String id) async {
    final result = await _repository.kill(id);
    TelemetryRuntime.featureUsed('kill', succeeded: result.isSuccess);
    result.when(onSuccess: (_) => _tick(), onFailure: (failure) => emit(KillFailureState(failure)));
  }

  Future<void> restore(String id) async {
    final result = await _repository.restore(id);
    TelemetryRuntime.featureUsed('restore', succeeded: result.isSuccess);
    result.when(onSuccess: (_) => _tick(), onFailure: (failure) => emit(RestoreFailureState(failure)));
  }
```

- [ ] **Step 5: Report spawn, conductor and send**

All three files need the same two imports as Step 3 and Step 4:

```dart
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
```

(`chat_cubit.dart` uses only `TelemetryRuntime`, so `events.dart` is not needed there.)

In `spawn_cubit.dart`, after the `spawn` call in `submit()`:

```dart
    final result = await _repository.spawn(SpawnSessionParams(
      projectId: project,
      mode: mode,
      prompt: prompt.trim(),
      issueId: name.trim(),
      harness: harness,
    ));
    TelemetryRuntime.featureUsed('spawn', succeeded: result.isSuccess);
```

In `orchestrator_cubit.dart`, after the `launch` call:

```dart
    final result = await _repository.launch(
      LaunchOrchestratorParams(projectId: projectId, clean: clean, mode: mode),
    );
    TelemetryRuntime.featureUsed('conductor', succeeded: result.isSuccess);
```

In `chat_cubit.dart`, in `_deliver`, immediately after the `if (isClosed) return;` that follows the
`sendMessage` await (`chat_cubit.dart:660`):

```dart
    if (isClosed) return;
    TelemetryRuntime.featureUsed('send', succeeded: result.isSuccess);
```

- [ ] **Step 6: Initialise the runtime and the heartbeat**

In `main.dart`, after `await sl<ServerConfigStore>().load();`:

```dart
  final packageInfo = await PackageInfo.fromPlatform();
  TelemetryRuntime.init(
    context: TelemetryContextInput(
      platformOs: Platform.operatingSystem,
      isPhysicalDevice: true,
      dev: kDebugMode,
      appVersion: packageInfo.version,
    ),
  );
  unawaited(TelemetryRuntime.active());
```

with `import 'dart:async';`, `import 'dart:io';`, `import 'package:flutter/foundation.dart';`,
`import 'package:package_info_plus/package_info_plus.dart';` and
`import 'package:operator_mobile/core/telemetry/runtime.dart';`.

Add the foreground heartbeat to `OperatorApp` by converting it to a `StatefulWidget` whose state owns
an `AppLifecycleListener` — the same listener Task 16 and Task 21 hang their own work on, so it is
built once here:

```dart
class OperatorApp extends StatefulWidget {
  const OperatorApp({required this.initialRoute, super.key});

  final String initialRoute;

  @override
  State<OperatorApp> createState() => _OperatorAppState();
}

class _OperatorAppState extends State<OperatorApp> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () => unawaited(TelemetryRuntime.active()),
  );

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider(
```

The rest of `build` is the existing tree with `initialRoute: widget.initialRoute`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/core/telemetry/call_sites_test.dart test/feature/chat/presentation/chat_screen/logic/chat_cubit_actions_test.dart`
Expected: PASS.

- [ ] **Step 8: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 816/816 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): report the mobile telemetry events from their call sites"
```

---
### Task 7: The notification list's presentation rules

Ports `lib/notificationView.ts` — the spec ledger's `notificationView.test.ts` row. Pure, so the
wording and the routing decision are testable, and so tapping an item in history lands exactly where
tapping the same notification in the tray does.

**Files:**
- Create: `packages/mobile/lib/feature/notification/logic/notification_view.dart`
- Test: `packages/mobile/test/feature/notification/logic/notification_view_test.dart`

**Interfaces:**
- Consumes: `AppSkin` (`core/app_themes/colors/app_skin.dart`), `Equatable`, `flutter/material.dart`.
- Produces: `NotificationVisual({required IconData icon, required Color color, required String label})`,
  `NotificationVisual notificationVisual(AppSkin skin, String type)`,
  `String notificationTarget({required String type, String? sessionId})`,
  `String relativeTime(String iso, [DateTime? now])`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/notification/logic/notification_view_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/feature/notification/logic/notification_view.dart';

const DarkSkin skin = DarkSkin();

void main() {
  group('notificationVisual', () {
    test('gives every known type its own label', () {
      final labels = ['needs_input', 'ready_to_merge', 'pr_merged', 'pr_closed_unmerged']
          .map((type) => notificationVisual(skin, type).label)
          .toSet();

      expect(labels, hasLength(4));
    });

    test('keeps the state hues meaningful', () {
      expect(notificationVisual(skin, 'needs_input').color, skin.amber);
      expect(notificationVisual(skin, 'ready_to_merge').color, skin.green);
      expect(notificationVisual(skin, 'pr_merged').color, skin.blue);
      expect(notificationVisual(skin, 'pr_closed_unmerged').color, skin.red);
    });

    test('falls back to a usable label for an unknown or empty type', () {
      expect(notificationVisual(skin, 'something_new').label, 'something_new');
      expect(notificationVisual(skin, '').label, 'Notification');
      expect(notificationVisual(skin, '').color, skin.textTertiary);
    });
  });

  group('notificationTarget', () {
    test('opens the session for a needs_input notification', () {
      expect(notificationTarget(type: 'needs_input', sessionId: 'abc'), '/session/abc');
    });

    test('falls back to the PRs tab when there is no session to open', () {
      expect(notificationTarget(type: 'needs_input', sessionId: ''), '/prs');
      expect(notificationTarget(type: 'needs_input'), '/prs');
    });

    test('sends PR notifications to the PRs tab', () {
      expect(notificationTarget(type: 'ready_to_merge', sessionId: 'abc'), '/prs');
      expect(notificationTarget(type: 'pr_merged', sessionId: 'abc'), '/prs');
    });

    test('sends an unknown or missing type to the PRs tab', () {
      expect(notificationTarget(type: ''), '/prs');
      expect(notificationTarget(type: '', sessionId: 'abc'), '/prs');
      expect(notificationTarget(type: 'something_new', sessionId: 'abc'), '/prs');
    });
  });

  group('relativeTime', () {
    final now = DateTime.utc(2026, 7, 30, 12);
    String ago(Duration age) => now.subtract(age).toIso8601String();

    test('collapses anything under a minute to now', () {
      expect(relativeTime(ago(const Duration(seconds: 5)), now), 'now');
    });

    test('steps through minutes, hours, days and weeks', () {
      expect(relativeTime(ago(const Duration(minutes: 3)), now), '3m');
      expect(relativeTime(ago(const Duration(hours: 4)), now), '4h');
      expect(relativeTime(ago(const Duration(days: 2)), now), '2d');
      expect(relativeTime(ago(const Duration(days: 20)), now), '2w');
    });

    test('does not render a negative age when the clocks disagree', () {
      expect(relativeTime(ago(const Duration(seconds: -30)), now), 'now');
    });

    test('returns nothing for an unparseable timestamp', () {
      expect(relativeTime('not-a-date', now), isEmpty);
    });
  });
}
```

That is **11 tests**.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/notification/logic/notification_view_test.dart`
Expected: FAIL — `notification_view.dart` does not exist.

- [ ] **Step 3: Write the rules**

Create `packages/mobile/lib/feature/notification/logic/notification_view.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

class NotificationVisual extends Equatable {
  const NotificationVisual({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  List<Object?> get props => [icon, color, label];
}

NotificationVisual notificationVisual(AppSkin skin, String type) => switch (type) {
  'needs_input' => NotificationVisual(
    icon: Icons.chat_bubble_outline,
    color: skin.amber,
    label: 'Needs input',
  ),
  'ready_to_merge' => NotificationVisual(
    icon: Icons.merge_outlined,
    color: skin.green,
    label: 'Ready to merge',
  ),
  'pr_merged' => NotificationVisual(
    icon: Icons.merge_outlined,
    color: skin.blue,
    label: 'Merged',
  ),
  'pr_closed_unmerged' => NotificationVisual(
    icon: Icons.cancel_outlined,
    color: skin.red,
    label: 'Closed',
  ),
  _ => NotificationVisual(
    icon: Icons.notifications_none,
    color: skin.textTertiary,
    label: type.isEmpty ? 'Notification' : type,
  ),
};

String notificationTarget({required String type, String? sessionId}) =>
    type == 'needs_input' && (sessionId ?? '').isNotEmpty ? '/session/$sessionId' : '/prs';

String relativeTime(String iso, [DateTime? now]) {
  final then = DateTime.tryParse(iso);
  if (then == null) return '';
  final elapsed = (now ?? DateTime.now()).difference(then);
  final seconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  if (seconds < 60) return 'now';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h';
  final days = hours ~/ 24;
  if (days < 7) return '${days}d';
  return '${days ~/ 7}w';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/feature/notification/logic/notification_view_test.dart`
Expected: PASS, 11 tests.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 827/827 green.

```bash
git add packages/mobile/lib/feature/notification packages/mobile/test/feature/notification
git commit -m "feat(mobile): add the notification list's presentation rules"
```

---
### Task 8: The push switch's state machine

Ports `lib/pushStatus.ts` — the spec ledger's `pushStatus.test.ts` row. Push is one switch in
Settings, so this answers two questions: where does the switch sit, and can the user move it. Two
regressions are pinned by its tests and must survive the port:

1. An unpaired app still holds a config object with an empty host, so `!!config` is truthy. Turning
   the switch on there could only burn the one-shot OS permission prompt and then fail.
2. Reaching the server and being rejected by it is not the same as not reaching it — telling someone
   with a wrong password to "check that Operator is running" sends them to debug the wrong thing.

Two names change from RN, because the runtime changed (see the deviations table): RN's
`"not-configured"` (no daemon paired) becomes `PushRegisterFailure.notPaired`, and RN's
`"no-project-id"` (no EAS project) becomes `PushRegisterFailure.notConfigured` (no Firebase
configuration in this build). Their positions in the state machine are unchanged.

**Files:**
- Create: `packages/mobile/lib/feature/notification/logic/push_status.dart`
- Test: `packages/mobile/test/feature/notification/logic/push_status_test.dart`

**Interfaces:**
- Consumes: `ServerConfig`, `StatusCode`, `Equatable`, `TargetPlatform`.
- Produces:
  - `PushStatus({required bool supported, required bool granted, required bool canAskAgain, required bool registered})`.
  - `PushToggle({required bool value, required bool disabled, required String footer, required bool blocked})`.
  - `bool hasServer(ServerConfig? server)`.
  - `PushToggle describePushToggle(PushStatus? status, ServerConfig? server)`.
  - `enum PushRegisterFailure { unsupported, notPaired, notConfigured, denied, tokenFailed, serverUnreachable, serverAuth, serverRateLimited, serverError }`.
  - `sealed class PushRegisterResult` with `PushRegistered(String token)` and
    `PushNotRegistered(PushRegisterFailure reason, {int? statusCode})`.
  - `PushRegisterFailure classifyServerFailure(int? statusCode)`.
  - `({String title, String message}) describeRegisterFailure(PushRegisterFailure reason, TargetPlatform platform, {int? statusCode})`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/notification/logic/push_status_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/status_code.dart';
import 'package:operator_mobile/feature/notification/logic/push_status.dart';

PushStatus status({
  bool supported = true,
  bool granted = true,
  bool canAskAgain = true,
  bool registered = false,
}) => PushStatus(
  supported: supported,
  granted: granted,
  canAskAgain: canAskAgain,
  registered: registered,
);

ServerConfig config([String host = '192.168.1.5']) =>
    ServerConfig(host: host, httpPort: '3011', secure: false, password: 'secret12');

void main() {
  group('describePushToggle', () {
    test('is off and disabled while the status is still loading', () {
      final toggle = describePushToggle(null, config());

      expect(toggle.value, isFalse);
      expect(toggle.disabled, isTrue);
      expect(toggle.footer, 'Checking…');
    });

    test('is disabled on a simulator, where no token can be minted', () {
      final toggle = describePushToggle(status(supported: false), config());

      expect(toggle.disabled, isTrue);
      expect(toggle.footer, contains('physical device'));
    });

    test('is disabled with no server paired, since there is nothing to register with', () {
      final toggle = describePushToggle(status(registered: true), config(''));

      expect(toggle.value, isFalse);
      expect(toggle.disabled, isTrue);
      expect(toggle.footer, contains('Connect to your Operator server'));
    });

    test('reads on only when permission is granted and the device is registered', () {
      expect(describePushToggle(status(registered: true), config()).value, isTrue);
      expect(describePushToggle(status(), config()).value, isFalse);
      expect(describePushToggle(status(granted: false, registered: true), config()).value, isFalse);
    });

    test('stays interactive when granted but not yet registered', () {
      final toggle = describePushToggle(status(), config());

      expect(toggle.disabled, isFalse);
      expect(toggle.blocked, isFalse);
      expect(toggle.footer, contains("isn't registered"));
    });

    test('offers a normal turn-on when permission has not been asked for yet', () {
      final toggle = describePushToggle(status(granted: false), config());

      expect(toggle.disabled, isFalse);
      expect(toggle.blocked, isFalse);
    });

    test('marks a permanent denial as blocked but leaves the switch tappable', () {
      final toggle = describePushToggle(status(granted: false, canAskAgain: false), config());

      expect(toggle.blocked, isTrue);
      expect(toggle.disabled, isFalse);
      expect(toggle.footer, contains('system settings'));
    });

    test('reports blocked even if a stale registration is still held', () {
      final toggle = describePushToggle(
        status(granted: false, canAskAgain: false, registered: true),
        config(),
      );

      expect(toggle.value, isFalse);
      expect(toggle.blocked, isTrue);
    });
  });

  group('hasServer', () {
    test('treats a missing, empty or whitespace host as no server', () {
      expect(hasServer(null), isFalse);
      expect(hasServer(config('')), isFalse);
      expect(hasServer(config('   ')), isFalse);
    });

    test('treats a real host as a server', () {
      expect(hasServer(config()), isTrue);
    });
  });

  group('classifyServerFailure', () {
    test('reports unreachable when there was no answer at all', () {
      expect(classifyServerFailure(null), PushRegisterFailure.serverUnreachable);
      expect(
        classifyServerFailure(StatusCode.noInternetConnection),
        PushRegisterFailure.serverUnreachable,
      );
      expect(
        classifyServerFailure(StatusCode.connectionTimeout),
        PushRegisterFailure.serverUnreachable,
      );
    });

    test('separates auth rejection, rate limiting and other error statuses', () {
      expect(classifyServerFailure(401), PushRegisterFailure.serverAuth);
      expect(classifyServerFailure(403), PushRegisterFailure.serverAuth);
      expect(classifyServerFailure(429), PushRegisterFailure.serverRateLimited);
      expect(classifyServerFailure(500), PushRegisterFailure.serverError);
      expect(classifyServerFailure(404), PushRegisterFailure.serverError);
    });
  });

  group('describeRegisterFailure', () {
    test('blames the server, not the build, when the daemon is unreachable', () {
      final described = describeRegisterFailure(
        PushRegisterFailure.serverUnreachable,
        TargetPlatform.iOS,
      );

      expect(described.title, contains("Couldn't reach your Operator server"));
      expect('${described.title} ${described.message}', isNot(contains('entitlement')));
    });

    test('explains the missing entitlement only when the token itself failed on iOS', () {
      final described = describeRegisterFailure(
        PushRegisterFailure.tokenFailed,
        TargetPlatform.iOS,
      );

      expect(described.message, contains('entitlement'));
      expect(described.message, contains('TestFlight'));
    });

    test('does not mention iOS entitlements on Android', () {
      final described = describeRegisterFailure(
        PushRegisterFailure.tokenFailed,
        TargetPlatform.android,
      );

      expect(described.message, isNot(contains('entitlement')));
    });

    test('points at system settings when permission was denied', () {
      expect(
        describeRegisterFailure(PushRegisterFailure.denied, TargetPlatform.iOS).message,
        contains('system settings'),
      );
    });

    test('does not claim the server was unreachable when it answered and rejected us', () {
      for (final reason in [
        PushRegisterFailure.serverAuth,
        PushRegisterFailure.serverRateLimited,
        PushRegisterFailure.serverError,
      ]) {
        final described = describeRegisterFailure(reason, TargetPlatform.iOS);
        expect('${described.title} ${described.message}', isNot(contains("Couldn't reach")));
      }
    });

    test('points at the password when the server rejected the credentials', () {
      expect(
        describeRegisterFailure(PushRegisterFailure.serverAuth, TargetPlatform.iOS).message,
        contains('password'),
      );
    });

    test('names the HTTP status when the server errored, and omits it when unknown', () {
      expect(
        describeRegisterFailure(
          PushRegisterFailure.serverError,
          TargetPlatform.iOS,
          statusCode: 500,
        ).message,
        contains('HTTP 500'),
      );
      expect(
        describeRegisterFailure(PushRegisterFailure.serverError, TargetPlatform.iOS).message,
        isNot(contains('HTTP')),
      );
    });

    test('tells an unpaired user to connect rather than blaming the build or network', () {
      final described = describeRegisterFailure(
        PushRegisterFailure.notPaired,
        TargetPlatform.iOS,
      );

      expect(described.title, contains('Connect to your Operator server'));
      expect('${described.title} ${described.message}', isNot(contains('entitlement')));
      expect('${described.title} ${described.message}', isNot(contains("couldn't reach")));
    });

    test('covers the remaining reasons with a usable message', () {
      for (final reason in [PushRegisterFailure.notConfigured, PushRegisterFailure.unsupported]) {
        final described = describeRegisterFailure(reason, TargetPlatform.iOS);
        expect(described.title, isNotEmpty);
        expect(described.message, isNotEmpty);
      }
    });
  });
}
```

That is **21 tests**.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/notification/logic/push_status_test.dart`
Expected: FAIL — `push_status.dart` does not exist.

- [ ] **Step 3: Write the state machine**

Create `packages/mobile/lib/feature/notification/logic/push_status.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:operator_mobile/core/api/server_config.dart';

class PushStatus extends Equatable {
  const PushStatus({
    required this.supported,
    required this.granted,
    required this.canAskAgain,
    required this.registered,
  });

  final bool supported;
  final bool granted;
  final bool canAskAgain;
  final bool registered;

  @override
  List<Object?> get props => [supported, granted, canAskAgain, registered];
}

class PushToggle extends Equatable {
  const PushToggle({
    required this.value,
    required this.disabled,
    required this.footer,
    required this.blocked,
  });

  final bool value;
  final bool disabled;
  final String footer;
  final bool blocked;

  @override
  List<Object?> get props => [value, disabled, footer, blocked];
}

enum PushRegisterFailure {
  unsupported,
  notPaired,
  notConfigured,
  denied,
  tokenFailed,
  serverUnreachable,
  serverAuth,
  serverRateLimited,
  serverError,
}

sealed class PushRegisterResult extends Equatable {
  const PushRegisterResult();
}

final class PushRegistered extends PushRegisterResult {
  const PushRegistered(this.token);

  final String token;

  @override
  List<Object?> get props => [token];
}

final class PushNotRegistered extends PushRegisterResult {
  const PushNotRegistered(this.reason, {this.statusCode});

  final PushRegisterFailure reason;
  final int? statusCode;

  @override
  List<Object?> get props => [reason, statusCode];
}

bool hasServer(ServerConfig? server) => (server?.host.trim() ?? '').isNotEmpty;

PushToggle describePushToggle(PushStatus? status, ServerConfig? server) {
  if (status == null) {
    return const PushToggle(value: false, disabled: true, footer: 'Checking…', blocked: false);
  }
  if (!status.supported) {
    return const PushToggle(
      value: false,
      disabled: true,
      footer: 'Push notifications need a physical device.',
      blocked: false,
    );
  }
  if (!hasServer(server)) {
    return const PushToggle(
      value: false,
      disabled: true,
      footer: 'Connect to your Operator server first — notifications turn on once connected.',
      blocked: false,
    );
  }
  if (!status.granted && !status.canAskAgain) {
    return const PushToggle(
      value: false,
      disabled: false,
      footer: 'Notifications are turned off for Operator in system settings.',
      blocked: true,
    );
  }
  if (status.granted && status.registered) {
    return const PushToggle(
      value: true,
      disabled: false,
      footer: "You'll be alerted when an agent needs you or a PR is ready.",
      blocked: false,
    );
  }
  if (status.granted) {
    return const PushToggle(
      value: false,
      disabled: false,
      footer: "This device isn't registered with your server yet.",
      blocked: false,
    );
  }
  return const PushToggle(
    value: false,
    disabled: false,
    footer: 'Turn on alerts for agents that need input and PR updates.',
    blocked: false,
  );
}

/// A negative status code is this app's marker for a request that never got an
/// answer (see `StatusCode`), which is what RN expressed as an absent status.
PushRegisterFailure classifyServerFailure(int? statusCode) {
  if (statusCode == null || statusCode < 0) return PushRegisterFailure.serverUnreachable;
  if (statusCode == 401 || statusCode == 403) return PushRegisterFailure.serverAuth;
  if (statusCode == 429) return PushRegisterFailure.serverRateLimited;
  return PushRegisterFailure.serverError;
}

({String title, String message}) describeRegisterFailure(
  PushRegisterFailure reason,
  TargetPlatform platform, {
  int? statusCode,
}) => switch (reason) {
  PushRegisterFailure.serverUnreachable => (
    title: "Couldn't reach your Operator server",
    message:
        'Your device is set up for notifications, but we could not reach your server to register '
        'it. Check that Operator is running and your phone is on the same network, then try again.',
  ),
  PushRegisterFailure.serverAuth => (
    title: 'Your Operator server rejected the request',
    message:
        'We reached your server, but it would not accept the connection password. Re-enter it '
        'under Settings → Connect Operator, then try again.',
  ),
  PushRegisterFailure.serverRateLimited => (
    title: 'Too many attempts',
    message:
        'Your Operator server is temporarily refusing new attempts. Wait a minute, then try again.',
  ),
  PushRegisterFailure.serverError => (
    title: "Your Operator server couldn't register this device",
    message:
        'We reached your server, but it returned an error'
        '${statusCode == null ? '' : ' (HTTP $statusCode)'}. '
        'Check the Operator logs on your computer, then try again.',
  ),
  PushRegisterFailure.notPaired => (
    title: 'Connect to your Operator server first',
    message:
        "This app isn't paired with a server yet, so there's nothing to register with. Pair with "
        'your server under Settings → Connect Operator — notifications turn on once connected.',
  ),
  PushRegisterFailure.tokenFailed => (
    title: "This build can't receive push notifications",
    message: platform == TargetPlatform.iOS
        ? 'This iOS build has no push entitlement. Install a build distributed through TestFlight '
              'to receive notifications.'
        : 'The device could not provide a push token for this build.',
  ),
  PushRegisterFailure.denied => (
    title: 'Notifications are turned off',
    message: 'Allow notifications for Operator in your system settings, then try again.',
  ),
  PushRegisterFailure.notConfigured => (
    title: "Push isn't configured in this build",
    message:
        'This build has no Firebase configuration, so it cannot register for notifications.',
  ),
  PushRegisterFailure.unsupported => (
    title: 'Not available on this device',
    message: 'Push notifications only work on a physical device, not a simulator.',
  ),
};
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/feature/notification/logic/push_status_test.dart`
Expected: PASS, 21 tests.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 848/848 green.

```bash
git add packages/mobile/lib/feature/notification/logic/push_status.dart packages/mobile/test/feature/notification/logic/push_status_test.dart
git commit -m "feat(mobile): add the push toggle state machine"
```

---
### Task 9: The notification wire shapes, data source and repository

Ports the notification and push halves of `lib/api.ts` (lines 451–525). Five calls: list, mark one
read, mark all read, register a device, unregister a device.

Two of them must be able to address a daemon that is **not** the current one — unregistering a token
from the daemon it was registered with, after the user has switched (`push.ts:194–201`). The Dio
interceptor already honours an `options.extra['pairingTarget']` override
(`server_config_interceptor.dart:15`), which is exactly that seam; `ApiConsumer.delete` is the only
verb that does not accept `Options`, so this task adds the parameter to match `get`/`post`.

**Files:**
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/api_consumer.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart`
- Create: `packages/mobile/lib/feature/notification/data/model/notification_model.dart`
- Create: `packages/mobile/lib/feature/notification/data/model/notification_page_model.dart`
- Create: `packages/mobile/lib/feature/notification/data/model/params/get_notifications_params.dart`
- Create: `packages/mobile/lib/feature/notification/data/model/params/mark_notification_read_params.dart`
- Create: `packages/mobile/lib/feature/notification/data/model/params/register_push_device_params.dart`
- Create: `packages/mobile/lib/feature/notification/data/data_source/notification_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/notification/data/repository/notification_repository.dart`
- Test: `packages/mobile/test/core/api/end_points_test.dart` (modify)
- Test: `packages/mobile/test/feature/notification/data/model/notification_models_test.dart`
- Test: `packages/mobile/test/feature/notification/data/data_source/notification_remote_data_source_test.dart`
- Test: `packages/mobile/test/feature/notification/data/repository/notification_repository_test.dart`

**Interfaces:**
- Consumes: `ApiConsumer`, `GlobalResponse`, `NetworkStatus`, `ServerConfig`, `Failure`, `Result`.
- Produces:
  - `EndPoints.notification(String id)`, `EndPoints.notificationsReadAll`, `EndPoints.pushDevices`,
    `EndPoints.pushDevice(String token)`.
  - `NotificationModel(id, sessionId, projectId, prUrl, type, title, body, status, createdAt)` with
    `fromJson`; `NotificationPageModel(notifications, nextCursor, unreadCount)` with `fromJson`.
  - `GetNotificationsParams({String? status, int? limit, String? cursor})` with `toJson()`;
    `MarkNotificationReadParams()` with `toJson()`; `RegisterPushDeviceParams({required String token,
    String? platform, String? deviceName})` with `toJson()`.
  - `NotificationRemoteDataSource` / `Imp`: `getNotifications`, `markNotificationRead`,
    `markAllNotificationsRead`, `registerPushDevice(params, {ServerConfig? target})`,
    `unregisterPushDevice(token, {ServerConfig? target})`.
  - `NotificationRepository` / `Imp` with the same five, returning
    `FutureResult<GlobalResponse<NotificationPageModel>>` / `FutureResult<bool>`.
  - `ApiConsumer.delete` gains `Options? options`.

- [ ] **Step 1: Write the failing tests**

Append to `packages/mobile/test/core/api/end_points_test.dart`, inside its existing `main()`:

```dart
  test('builds the notification and push paths', () {
    expect(EndPoints.notifications, '/api/v1/notifications');
    expect(EndPoints.notification('n 1'), '/api/v1/notifications/n%201');
    expect(EndPoints.notificationsReadAll, '/api/v1/notifications/read-all');
    expect(EndPoints.pushDevices, '/api/v1/push/devices');
    expect(EndPoints.pushDevice('ExponentPushToken[a b]'), '/api/v1/push/devices/ExponentPushToken%5Ba%20b%5D');
  });
```

That is **1 test**.

Create `packages/mobile/test/feature/notification/data/model/notification_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/mark_notification_read_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';

void main() {
  test('parses one record and tolerates a record with nothing but an id', () {
    final full = NotificationModel.fromJson(const {
      'id': 'n-1',
      'sessionId': 's-1',
      'projectId': 'p-1',
      'prUrl': 'https://github.com/o/r/pull/7',
      'type': 'needs_input',
      'title': 'Agent needs you',
      'body': 'Approve the plan',
      'status': 'unread',
      'createdAt': '2026-08-15T10:00:00Z',
    });

    expect(full.id, 'n-1');
    expect(full.type, 'needs_input');
    expect(full.status, 'unread');
    expect(NotificationModel.fromJson(const {'id': 'n-2'}).body, isNull);
  });

  test('reads the page envelope, missing keys included', () {
    final page = NotificationPageModel.fromJson(const {
      'notifications': [
        {'id': 'n-1'},
        {'id': 'n-2'},
      ],
      'nextCursor': 'c-2',
      'unreadCount': 3,
    });

    expect(page.notifications.map((item) => item.id), ['n-1', 'n-2']);
    expect(page.nextCursor, 'c-2');
    expect(page.unreadCount, 3);

    final empty = NotificationPageModel.fromJson(const {});
    expect(empty.notifications, isEmpty);
    expect(empty.nextCursor, isNull);
    expect(empty.unreadCount, 0);
  });

  test("serialises exactly the daemon's query and bodies", () {
    expect(
      const GetNotificationsParams(status: 'all', limit: 50, cursor: 'c-1').toJson(),
      {'status': 'all', 'limit': 50, 'cursor': 'c-1'},
    );
    expect(const GetNotificationsParams().toJson(), isEmpty);
    expect(const MarkNotificationReadParams().toJson(), {'status': 'read'});
    expect(
      const RegisterPushDeviceParams(token: 't-1', platform: 'ios', deviceName: 'iPhone').toJson(),
      {'token': 't-1', 'platform': 'ios', 'deviceName': 'iPhone'},
    );
    expect(const RegisterPushDeviceParams(token: 't-1').toJson(), {'token': 't-1'});
  });
}
```

That is **3 tests**.

Create `packages/mobile/test/feature/notification/data/data_source/notification_remote_data_source_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

Response<dynamic> _response(Object? data) =>
    Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: data);

const ServerConfig _oldDaemon = ServerConfig(
  host: '10.0.0.9',
  httpPort: '3011',
  secure: true,
  password: 'old-secret',
);

void main() {
  late _MockApiConsumer apiConsumer;
  late NotificationRemoteDataSource dataSource;

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = NotificationRemoteDataSourceImp(apiConsumer);
  });

  test('lists notifications with the query the daemon expects', () async {
    when(() => apiConsumer.get(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async => _response({
        'notifications': [
          {'id': 'n-1'},
        ],
        'unreadCount': 1,
      }),
    );

    final page = (await dataSource.getNotifications(
      const GetNotificationsParams(status: 'all', limit: 50),
    )).data!;

    expect(page.notifications.single.id, 'n-1');
    verify(
      () => apiConsumer.get(
        EndPoints.notifications,
        queryParameters: {'status': 'all', 'limit': 50},
      ),
    ).called(1);
  });

  test('marks one notification read with a PATCH', () async {
    when(() => apiConsumer.patch(any(), body: any(named: 'body')))
        .thenAnswer((_) async => _response(null));

    await dataSource.markNotificationRead('n-1');

    verify(() => apiConsumer.patch(EndPoints.notification('n-1'), body: {'status': 'read'}))
        .called(1);
  });

  test('marks everything read with a POST', () async {
    when(() => apiConsumer.post(any())).thenAnswer((_) async => _response(null));

    await dataSource.markAllNotificationsRead();

    verify(() => apiConsumer.post(EndPoints.notificationsReadAll)).called(1);
  });

  test('registers a device against the current daemon', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body'), options: any(named: 'options')))
        .thenAnswer((_) async => _response(null));

    await dataSource.registerPushDevice(
      const RegisterPushDeviceParams(token: 't-1', platform: 'ios'),
    );

    final captured = verify(
      () => apiConsumer.post(
        EndPoints.pushDevices,
        body: captureAny(named: 'body'),
        options: captureAny(named: 'options'),
      ),
    ).captured;
    expect(captured.first, {'token': 't-1', 'platform': 'ios'});
    expect((captured.last as Options?)?.extra?['pairingTarget'], isNull);
  });

  test('unregisters a token from the daemon it was registered with', () async {
    when(() => apiConsumer.delete(any(), options: any(named: 'options')))
        .thenAnswer((_) async => _response(null));

    await dataSource.unregisterPushDevice('t-1', target: _oldDaemon);

    final captured = verify(
      () => apiConsumer.delete(EndPoints.pushDevice('t-1'), options: captureAny(named: 'options')),
    ).captured.single as Options;
    expect(captured.extra?['pairingTarget'], _oldDaemon);
  });
}
```

That is **5 tests**.

Create `packages/mobile/test/feature/notification/data/repository/notification_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';

class _MockDataSource extends Mock implements NotificationRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

void main() {
  late _MockDataSource dataSource;
  late _MockNetworkStatus network;
  late NotificationRepository repository;

  setUpAll(() {
    registerFallbackValue(const GetNotificationsParams());
    registerFallbackValue(const RegisterPushDeviceParams(token: 't'));
    registerFallbackValue(
      const ServerConfig(host: 'h', httpPort: '1', secure: false, password: 'p'),
    );
  });

  setUp(() {
    dataSource = _MockDataSource();
    network = _MockNetworkStatus();
    repository = NotificationRepositoryImp(dataSource, network);
  });

  test('short-circuits to noNetwork without calling the data source when offline', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);

    final result = await repository.getNotifications(const GetNotificationsParams());

    expect(result.isFailure, isTrue);
    verifyNever(() => dataSource.getNotifications(any()));
  });

  test('returns the page when the data source succeeds', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getNotifications(any())).thenAnswer(
      (_) async => const GlobalResponse(data: NotificationPageModel(unreadCount: 4)),
    );

    final result = await repository.getNotifications(const GetNotificationsParams());

    late NotificationPageModel page;
    result.when(onSuccess: (response) => page = response.data!, onFailure: (_) {});
    expect(page.unreadCount, 4);
  });

  test('surfaces a data-source failure as a failure result', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getNotifications(any())).thenThrow(
      ServerFailure(error: 'x', message: 'boom', statusCode: 500),
    );

    final result = await repository.getNotifications(const GetNotificationsParams());

    expect(result.isFailure, isTrue);
  });

  test('marks one and all read', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.markNotificationRead(any())).thenAnswer((_) async {});
    when(() => dataSource.markAllNotificationsRead()).thenAnswer((_) async {});

    expect((await repository.markNotificationRead('n-1')).isSuccess, isTrue);
    expect((await repository.markAllNotificationsRead()).isSuccess, isTrue);
  });

  test('registers a device', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(
      () => dataSource.registerPushDevice(any(), target: any(named: 'target')),
    ).thenAnswer((_) async {});

    expect(
      (await repository.registerPushDevice(const RegisterPushDeviceParams(token: 't-1'))).isSuccess,
      isTrue,
    );
  });

  test('unregisters a device from a named daemon', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(
      () => dataSource.unregisterPushDevice(any(), target: any(named: 'target')),
    ).thenAnswer((_) async {});

    const target = ServerConfig(host: 'old', httpPort: '3011', secure: false, password: 'p');
    expect((await repository.unregisterPushDevice('t-1', target: target)).isSuccess, isTrue);
    verify(() => dataSource.unregisterPushDevice('t-1', target: target)).called(1);
  });
}
```

That is **6 tests**. Task 9 adds **15 tests** in total.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/api/end_points_test.dart test/feature/notification`
Expected: FAIL — `notifications/read-all` and the notification data files do not exist.

- [ ] **Step 3: Add the endpoints and widen `delete`**

In `end_points.dart`, beside the existing members:

```dart
  static const String notificationsReadAll = '/api/v1/notifications/read-all';
  static const String pushDevices = '/api/v1/push/devices';

  static String notification(String id) => '$notifications/${Uri.encodeComponent(id)}';
  static String pushDevice(String token) => '$pushDevices/${Uri.encodeComponent(token)}';
```

In `api_consumer.dart`, add `Options? options` to the abstract `delete`:

```dart
  Future<Response> delete<T>(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(Map<String, dynamic>)? errorFromJsonT,
  });
```

and in `dio_consumer.dart`:

```dart
  @override
  Future<Response> delete<T>(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(Map<String, dynamic>)? errorFromJsonT,
  }) async {
    try {
      return await client.delete(
        path,
        queryParameters: queryParameters,
        data: body,
        options: options,
      );
    } on DioException catch (error) {
      throw handleDioError(error);
    }
  }
```

- [ ] **Step 4: Write the models and params**

Create `packages/mobile/lib/feature/notification/data/model/notification_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class NotificationModel extends Equatable {
  const NotificationModel({
    this.id,
    this.sessionId,
    this.projectId,
    this.prUrl,
    this.type,
    this.title,
    this.body,
    this.status,
    this.createdAt,
  });

  final String? id;
  final String? sessionId;
  final String? projectId;
  final String? prUrl;
  final String? type;
  final String? title;
  final String? body;
  final String? status;
  final String? createdAt;

  factory NotificationModel.fromJson(Map<String, dynamic> json) => NotificationModel(
    id: json['id'] as String?,
    sessionId: json['sessionId'] as String?,
    projectId: json['projectId'] as String?,
    prUrl: json['prUrl'] as String?,
    type: json['type'] as String?,
    title: json['title'] as String?,
    body: json['body'] as String?,
    status: json['status'] as String?,
    createdAt: json['createdAt'] as String?,
  );

  NotificationModel copyWith({String? status}) => NotificationModel(
    id: id,
    sessionId: sessionId,
    projectId: projectId,
    prUrl: prUrl,
    type: type,
    title: title,
    body: body,
    status: status ?? this.status,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [id, sessionId, projectId, prUrl, type, title, body, status, createdAt];
}
```

Create `packages/mobile/lib/feature/notification/data/model/notification_page_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';

class NotificationPageModel extends Equatable {
  const NotificationPageModel({
    this.notifications = const [],
    this.nextCursor,
    this.unreadCount = 0,
  });

  final List<NotificationModel> notifications;
  final String? nextCursor;
  final int unreadCount;

  factory NotificationPageModel.fromJson(Map<String, dynamic> json) {
    final cursor = json['nextCursor'];
    return NotificationPageModel(
      notifications: (json['notifications'] as List<dynamic>? ?? [])
          .map((item) => NotificationModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextCursor: cursor is String && cursor.isNotEmpty ? cursor : null,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [notifications, nextCursor, unreadCount];
}
```

Create `packages/mobile/lib/feature/notification/data/model/params/get_notifications_params.dart`:

```dart
import 'package:equatable/equatable.dart';

class GetNotificationsParams extends Equatable {
  const GetNotificationsParams({this.status, this.limit, this.cursor});

  final String? status;
  final int? limit;
  final String? cursor;

  Map<String, dynamic> toJson() => {
    if (status != null) 'status': status,
    if (limit != null) 'limit': limit,
    if (cursor != null) 'cursor': cursor,
  };

  @override
  List<Object?> get props => [status, limit, cursor];
}
```

Create `packages/mobile/lib/feature/notification/data/model/params/mark_notification_read_params.dart`:

```dart
import 'package:equatable/equatable.dart';

class MarkNotificationReadParams extends Equatable {
  const MarkNotificationReadParams();

  Map<String, dynamic> toJson() => {'status': 'read'};

  @override
  List<Object?> get props => [];
}
```

Create `packages/mobile/lib/feature/notification/data/model/params/register_push_device_params.dart`:

```dart
import 'package:equatable/equatable.dart';

class RegisterPushDeviceParams extends Equatable {
  const RegisterPushDeviceParams({required this.token, this.platform, this.deviceName});

  final String token;
  final String? platform;
  final String? deviceName;

  Map<String, dynamic> toJson() => {
    'token': token,
    if (platform != null) 'platform': platform,
    if (deviceName != null) 'deviceName': deviceName,
  };

  @override
  List<Object?> get props => [token, platform, deviceName];
}
```

- [ ] **Step 5: Write the data source**

Create `packages/mobile/lib/feature/notification/data/data_source/notification_remote_data_source.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/mark_notification_read_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';

abstract class NotificationRemoteDataSource {
  Future<GlobalResponse<NotificationPageModel>> getNotifications(GetNotificationsParams params);
  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead();
  Future<void> registerPushDevice(RegisterPushDeviceParams params, {ServerConfig? target});
  Future<void> unregisterPushDevice(String token, {ServerConfig? target});
}

class NotificationRemoteDataSourceImp implements NotificationRemoteDataSource {
  NotificationRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  Options? _target(ServerConfig? target) =>
      target == null ? null : Options(extra: {'pairingTarget': target});

  @override
  Future<GlobalResponse<NotificationPageModel>> getNotifications(
    GetNotificationsParams params,
  ) async {
    final response = await _apiConsumer.get(
      EndPoints.notifications,
      queryParameters: params.toJson(),
    );
    return GlobalResponse<NotificationPageModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: NotificationPageModel.fromJson,
    );
  }

  @override
  Future<void> markNotificationRead(String id) async {
    await _apiConsumer.patch(
      EndPoints.notification(id),
      body: const MarkNotificationReadParams().toJson(),
    );
  }

  @override
  Future<void> markAllNotificationsRead() async {
    await _apiConsumer.post(EndPoints.notificationsReadAll);
  }

  @override
  Future<void> registerPushDevice(
    RegisterPushDeviceParams params, {
    ServerConfig? target,
  }) async {
    await _apiConsumer.post(
      EndPoints.pushDevices,
      body: params.toJson(),
      options: _target(target),
    );
  }

  @override
  Future<void> unregisterPushDevice(String token, {ServerConfig? target}) async {
    await _apiConsumer.delete(EndPoints.pushDevice(token), options: _target(target));
  }
}
```

- [ ] **Step 6: Write the repository**

Create `packages/mobile/lib/feature/notification/data/repository/notification_repository.dart`:

```dart
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';

abstract class NotificationRepository {
  FutureResult<GlobalResponse<NotificationPageModel>> getNotifications(
    GetNotificationsParams params,
  );
  FutureResult<bool> markNotificationRead(String id);
  FutureResult<bool> markAllNotificationsRead();
  FutureResult<bool> registerPushDevice(RegisterPushDeviceParams params, {ServerConfig? target});
  FutureResult<bool> unregisterPushDevice(String token, {ServerConfig? target});
}

class NotificationRepositoryImp implements NotificationRepository {
  NotificationRepositoryImp(this._remoteDataSource, this._network);

  final NotificationRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<NotificationPageModel>> getNotifications(
    GetNotificationsParams params,
  ) => _guard(() => _remoteDataSource.getNotifications(params));

  @override
  FutureResult<bool> markNotificationRead(String id) =>
      _run(() => _remoteDataSource.markNotificationRead(id));

  @override
  FutureResult<bool> markAllNotificationsRead() =>
      _run(_remoteDataSource.markAllNotificationsRead);

  @override
  FutureResult<bool> registerPushDevice(RegisterPushDeviceParams params, {ServerConfig? target}) =>
      _run(() => _remoteDataSource.registerPushDevice(params, target: target));

  @override
  FutureResult<bool> unregisterPushDevice(String token, {ServerConfig? target}) =>
      _run(() => _remoteDataSource.unregisterPushDevice(token, target: target));

  Future<Result<T, Failure>> _guard<T>(Future<T> Function() action) async {
    if (await _network.isConnected) {
      try {
        return Result.success(await action());
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  FutureResult<bool> _run(Future<void> Function() action) => _guard(() async {
    await action();
    return true;
  });
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/core/api/end_points_test.dart test/feature/notification`
Expected: PASS.

- [ ] **Step 8: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 863/863 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the notification and push-device wire shapes"
```

---
### Task 10: `NotificationsCubit`

Ports the state half of `app/notifications.tsx` plus the board's unread poll
(`store.tsx:170–176`). Registered as a **lazy singleton** in Task 11, so the Agents-tab bell and the
history screen read one unread count.

Two behaviors are load-bearing and carry their own tests: paging must not refetch the first page when
`loadMore` runs (RN keys the effect to the config alone, deliberately), and a tap must mark the row
read optimistically — a failed `PATCH` is not worth interrupting navigation over — while a failed
*mark-all* puts the truth back on screen by refetching.

**Files:**
- Create: `packages/mobile/lib/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart`
- Create: `packages/mobile/lib/feature/notification/presentation/notifications_screen/logic/notifications_state.dart`
- Test: `packages/mobile/test/feature/notification/presentation/notifications_screen/logic/notifications_cubit_test.dart`

**Interfaces:**
- Consumes: `NotificationRepository`, `GetNotificationsParams`, `NotificationModel`,
  `NotificationPageModel`, `Result`.
- Produces:
  - `NotificationsCubit(NotificationRepository repository, {Duration unreadPoll = const Duration(seconds: 30)})`
    with fields `items` (`List<NotificationModel>`), `unreadCount`, `loading`, `loadingMore`,
    `refreshing`, `error`, and methods `load()`, `refresh()`, `loadMore()`, `open(NotificationModel)`,
    `markAllRead()`.
  - States: `NotificationsInitialState`, `NotificationsReadyState(int revision)`.
  - `kNotificationPageSize = 50`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/notification/presentation/notifications_screen/logic/notifications_cubit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';

class _MockRepository extends Mock implements NotificationRepository {}

NotificationModel item(String id, {String status = 'unread'}) =>
    NotificationModel(id: id, type: 'needs_input', sessionId: 's-1', status: status);

Result<GlobalResponse<NotificationPageModel>, Failure> page(
  List<NotificationModel> notifications, {
  String? nextCursor,
  int unreadCount = 0,
}) => Result.success(
  GlobalResponse(
    data: NotificationPageModel(
      notifications: notifications,
      nextCursor: nextCursor,
      unreadCount: unreadCount,
    ),
  ),
);

void main() {
  late _MockRepository repository;

  setUpAll(() => registerFallbackValue(const GetNotificationsParams()));

  setUp(() => repository = _MockRepository());

  NotificationsCubit build() =>
      NotificationsCubit(repository, unreadPoll: const Duration(hours: 1));

  test('loads the first page on construction', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1')], unreadCount: 1));
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.items.single.id, 'n-1');
    expect(cubit.unreadCount, 1);
    expect(cubit.loading, isFalse);
    final captured = verify(() => repository.getNotifications(captureAny())).captured.single
        as GetNotificationsParams;
    expect(captured.status, 'all');
    expect(captured.limit, kNotificationPageSize);
    expect(captured.cursor, isNull);
    await cubit.close();
  });

  test('keeps the error message and the empty list when the first load fails', () async {
    when(() => repository.getNotifications(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'down', statusCode: 503)),
    );
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.items, isEmpty);
    expect(cubit.error, 'down');
    expect(cubit.loading, isFalse);
    await cubit.close();
  });

  test('appends the next page and drops ids it already has', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1')], nextCursor: 'c-2', unreadCount: 2));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1'), item('n-2')], unreadCount: 2));
    await cubit.loadMore();

    expect(cubit.items.map((notification) => notification.id), ['n-1', 'n-2']);
    await cubit.close();
  });

  test('does nothing when there is no next cursor', () async {
    when(() => repository.getNotifications(any())).thenAnswer((_) async => page([item('n-1')]));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    clearInteractions(repository);

    await cubit.loadMore();

    verifyNever(() => repository.getNotifications(any()));
    await cubit.close();
  });

  test('refreshing replaces the list rather than appending to it', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1')], nextCursor: 'c-2'));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    when(() => repository.getNotifications(any())).thenAnswer((_) async => page([item('n-9')]));
    await cubit.refresh();

    expect(cubit.items.map((notification) => notification.id), ['n-9']);
    await cubit.close();
  });

  test('opening an unread row marks it read optimistically and decrements the count', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1')], unreadCount: 1));
    when(() => repository.markNotificationRead(any()))
        .thenAnswer((_) async => Result.success(true));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    await cubit.open(cubit.items.single);

    expect(cubit.items.single.status, 'read');
    expect(cubit.unreadCount, 0);
    verify(() => repository.markNotificationRead('n-1')).called(1);
    await cubit.close();
  });

  test('opening a row that is already read does not call the daemon', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1', status: 'read')]));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    await cubit.open(cubit.items.single);

    verifyNever(() => repository.markNotificationRead(any()));
    await cubit.close();
  });

  test('a failed mark-all puts the truth back on screen', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1')], unreadCount: 1));
    when(() => repository.markAllNotificationsRead()).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'nope', statusCode: 500)),
    );
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    await cubit.markAllRead();

    expect(cubit.items.single.status, 'unread');
    expect(cubit.unreadCount, 1);
    await cubit.close();
  });
}
```

That is **8 tests**.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/notification/presentation`
Expected: FAIL — `notifications_cubit.dart` does not exist.

- [ ] **Step 3: Write the state**

Create `packages/mobile/lib/feature/notification/presentation/notifications_screen/logic/notifications_state.dart`:

```dart
part of 'notifications_cubit.dart';

sealed class NotificationsState extends Equatable {
  const NotificationsState();

  @override
  List<Object?> get props => [];
}

final class NotificationsInitialState extends NotificationsState {
  const NotificationsInitialState();
}

final class NotificationsReadyState extends NotificationsState {
  const NotificationsReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
```

- [ ] **Step 4: Write the cubit**

Create `packages/mobile/lib/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';

part 'notifications_state.dart';

const int kNotificationPageSize = 50;

class NotificationsCubit extends Cubit<NotificationsState> {
  factory NotificationsCubit(
    NotificationRepository repository, {
    Duration unreadPoll = const Duration(seconds: 30),
  }) => NotificationsCubit._(repository, unreadPoll: unreadPoll);

  NotificationsCubit._(this._repository, {required Duration unreadPoll})
    : _unreadPoll = unreadPoll,
      super(const NotificationsInitialState()) {
    unawaited(load());
    _timer = Timer.periodic(_unreadPoll, (_) => unawaited(refreshUnread()));
  }

  final NotificationRepository _repository;
  final Duration _unreadPoll;

  List<NotificationModel> items = [];
  int unreadCount = 0;
  bool loading = true;
  bool loadingMore = false;
  bool refreshing = false;
  String? error;

  String? _nextCursor;
  Timer? _timer;
  int _revision = 0;

  void _emit() => emit(NotificationsReadyState(++_revision));

  Future<void> load() => _fetch(reset: true);

  Future<void> refresh() async {
    refreshing = true;
    _emit();
    await _fetch(reset: true);
    refreshing = false;
    _emit();
  }

  Future<void> loadMore() async {
    if (_nextCursor == null || loadingMore) return;
    loadingMore = true;
    _emit();
    await _fetch(reset: false);
    loadingMore = false;
    _emit();
  }

  Future<void> _fetch({required bool reset}) async {
    error = null;
    final result = await _repository.getNotifications(
      GetNotificationsParams(
        status: 'all',
        limit: kNotificationPageSize,
        cursor: reset ? null : _nextCursor,
      ),
    );
    result.when(
      onSuccess: (response) {
        final page = response.data;
        final fetched = page?.notifications ?? const <NotificationModel>[];
        if (reset) {
          items = fetched;
        } else {
          final seen = items.map((notification) => notification.id).toSet();
          items = [...items, ...fetched.where((notification) => !seen.contains(notification.id))];
        }
        _nextCursor = page?.nextCursor;
        unreadCount = page?.unreadCount ?? 0;
      },
      onFailure: (failure) => error = failure.message,
    );
    loading = false;
    _emit();
  }

  /// The badge only needs the count, so it asks for one row rather than a page.
  Future<void> refreshUnread() async {
    final result = await _repository.getNotifications(
      const GetNotificationsParams(status: 'unread', limit: 1),
    );
    result.when(
      onSuccess: (response) => unreadCount = response.data?.unreadCount ?? 0,
      onFailure: (_) {},
    );
    _emit();
  }

  Future<void> open(NotificationModel notification) async {
    final id = notification.id;
    if (id == null || notification.status != 'unread') return;
    items = items
        .map((item) => item.id == id ? item.copyWith(status: 'read') : item)
        .toList();
    unreadCount = unreadCount > 0 ? unreadCount - 1 : 0;
    _emit();
    await _repository.markNotificationRead(id);
  }

  Future<void> markAllRead() async {
    final previousItems = items;
    final previousUnread = unreadCount;
    items = items.map((item) => item.copyWith(status: 'read')).toList();
    unreadCount = 0;
    _emit();

    final result = await _repository.markAllNotificationsRead();
    var failed = false;
    result.when(onSuccess: (_) {}, onFailure: (_) => failed = true);
    if (!failed) return;
    items = previousItems;
    unreadCount = previousUnread;
    _emit();
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/feature/notification/presentation`
Expected: PASS, 8 tests.

- [ ] **Step 6: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 871/871 green.

```bash
git add packages/mobile/lib/feature/notification packages/mobile/test/feature/notification
git commit -m "feat(mobile): add the notifications cubit"
```

---
### Task 11: The notifications screen, its route and the board's bell

Ports `app/notifications.tsx` and the bell in `app/(tabs)/index.tsx:120–127`. The list is the durable
record: push only ever reaches a phone that was reachable at the time, so this is what a user can come
back to.

**Files:**
- Create: `packages/mobile/lib/feature/notification/presentation/notifications_screen/ui/notifications_screen.dart`
- Create: `packages/mobile/lib/feature/notification/presentation/notifications_screen/ui/widgets/notifications_body.dart`
- Create: `packages/mobile/lib/feature/notification/presentation/notifications_screen/ui/widgets/notification_row.dart`
- Create: `packages/mobile/lib/feature/notification/presentation/notifications_screen/ui/widgets/notification_bell.dart`
- Modify: `packages/mobile/lib/core/app_routes/routes_strings.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart`
- Test: `packages/mobile/test/feature/notification/presentation/notifications_screen/ui/notifications_body_test.dart`
- Test: `packages/mobile/test/core/app_routes/app_router_test.dart` (modify)

**Interfaces:**
- Consumes: `NotificationsCubit`, `notificationVisual`, `notificationTarget`, `relativeTime`,
  `AppScaffold`, `GlobalAppbar`, `AppText`, `AppLoader`, `AppInkWell`, `HomeShell.selectedTab`,
  `SessionsCubit`.
- Produces: `RoutesStrings.notifications`, the `/notifications` route case,
  `_notificationFeatureSetup()`, `NotificationsScreen`, `NotificationsBody`, `NotificationRow`,
  `NotificationBell`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/notification/presentation/notifications_screen/ui/notifications_body_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/ui/widgets/notification_bell.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/ui/widgets/notifications_body.dart';

class _MockRepository extends Mock implements NotificationRepository {}

NotificationModel item(String id, {String type = 'needs_input', String status = 'unread'}) =>
    NotificationModel(
      id: id,
      type: type,
      sessionId: 's-1',
      title: 'Agent needs you',
      body: 'Approve the plan',
      status: status,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

void main() {
  late _MockRepository repository;

  setUpAll(() => registerFallbackValue(const GetNotificationsParams()));

  setUp(() => repository = _MockRepository());

  void stubPage(List<NotificationModel> notifications, {int unreadCount = 0}) {
    when(() => repository.getNotifications(any())).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: NotificationPageModel(notifications: notifications, unreadCount: unreadCount),
        ),
      ),
    );
  }

  Future<NotificationsCubit> pump(WidgetTester tester, Widget child) async {
    final cubit = NotificationsCubit(repository, unreadPoll: const Duration(hours: 1));
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<NotificationsCubit>.value(value: cubit, child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(cubit.close);
    return cubit;
  }

  testWidgets('shows each notification with its label, body and stamp', (tester) async {
    stubPage([item('n-1'), item('n-2', type: 'pr_merged', status: 'read')], unreadCount: 1);

    await pump(tester, const NotificationsBody());

    expect(find.text('Agent needs you'), findsNWidgets(2));
    expect(find.text('Approve the plan'), findsNWidgets(2));
    expect(find.text('now'), findsNWidgets(2));
  });

  testWidgets('falls back to the type label when a record has no title', (tester) async {
    stubPage([const NotificationModel(id: 'n-1', type: 'ready_to_merge', status: 'read')]);

    await pump(tester, const NotificationsBody());

    expect(find.text('Ready to merge'), findsOneWidget);
  });

  testWidgets('offers the empty state when nothing has arrived', (tester) async {
    stubPage(const []);

    await pump(tester, const NotificationsBody());

    expect(find.text('Nothing yet'), findsOneWidget);
  });

  testWidgets('reports a load failure without pretending the list is empty', (tester) async {
    when(() => repository.getNotifications(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'down', statusCode: 503)),
    );

    await pump(tester, const NotificationsBody());

    expect(find.text("Couldn't load notifications"), findsOneWidget);
    expect(find.text('down'), findsOneWidget);
  });

  testWidgets('tapping an unread row marks it read', (tester) async {
    stubPage([item('n-1')], unreadCount: 1);
    when(() => repository.markNotificationRead(any()))
        .thenAnswer((_) async => Result.success(true));

    final cubit = await pump(tester, const NotificationsBody());
    await tester.tap(find.text('Agent needs you'));
    await tester.pumpAndSettle();

    expect(cubit.items.single.status, 'read');
  });

  testWidgets('the bell shows the unread count and hides the badge at zero', (tester) async {
    stubPage([item('n-1')], unreadCount: 3);

    final cubit = await pump(tester, const NotificationBell());
    expect(find.text('3'), findsOneWidget);

    cubit.unreadCount = 0;
    await cubit.refreshUnread();
    await tester.pumpAndSettle();

    expect(find.text('3'), findsNothing);
  });
}
```

That is **6 tests**.

Append to `packages/mobile/test/core/app_routes/app_router_test.dart`, inside its existing `main()`:

```dart
  test('routes /notifications to the notifications screen', () {
    final route = AppRouter.generateRoute(const RouteSettings(name: RoutesStrings.notifications));

    expect(route, isA<MaterialPageRoute<dynamic>>());
    expect(route.settings.name, RoutesStrings.notifications);
  });
```

That is **1 test**. Task 11 adds **7 tests** in total.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/feature/notification test/core/app_routes/app_router_test.dart`
Expected: FAIL — the screen widgets and the route do not exist.

- [ ] **Step 3: Write the row**

Create `packages/mobile/lib/feature/notification/presentation/notifications_screen/ui/widgets/notification_row.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/notification/logic/notification_view.dart';

class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.unread,
    required this.onTap,
  });

  final String type;
  final String title;
  final String body;
  final String createdAt;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final visual = notificationVisual(skin, type);
    final stamp = relativeTime(createdAt);

    return AppInkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: skin.bgSubtle,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(visual.icon, size: 15, color: visual.color),
            ),
            const HorizontalSpace(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: AppText(
                          title.isEmpty ? visual.label : title,
                          style: AppTextStyle.style15SemiBold.copyWith(
                            color: unread ? skin.textPrimary : skin.textSecondary,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const HorizontalSpace(7),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: skin.blue, shape: BoxShape.circle),
                        ),
                      ],
                      const Spacer(),
                      if (stamp.isNotEmpty)
                        AppText(
                          stamp,
                          style: AppTextStyle.style12Regular.copyWith(color: skin.textFaint),
                        ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const VerticalSpace(3),
                    AppText(
                      body,
                      style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
                      maxLines: 2,
                    ),
                  ],
                ],
              ),
            ),
            const HorizontalSpace(8),
            Icon(Icons.chevron_right, size: 16, color: skin.textFaint),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write the body and the bell**

Create `packages/mobile/lib/feature/notification/presentation/notifications_screen/ui/widgets/notifications_body.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/logic/notification_view.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/ui/widgets/notification_row.dart';

class NotificationsBody extends StatelessWidget {
  const NotificationsBody({super.key});

  Future<void> _open(BuildContext context, NotificationModel notification) async {
    final cubit = context.read<NotificationsCubit>();
    await cubit.open(notification);
    if (!context.mounted) return;

    final target = notificationTarget(
      type: notification.type ?? '',
      sessionId: notification.sessionId,
    );
    if (target.startsWith('/session/')) {
      Navigator.of(context).pushNamed(
        RoutesStrings.session,
        arguments: {'sessionId': notification.sessionId},
      );
      return;
    }
    HomeShell.selectedTab.value = 2;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<NotificationsCubit, NotificationsState>(
      buildWhen: (previous, current) => current is NotificationsReadyState,
      builder: (context, state) {
        final cubit = context.read<NotificationsCubit>();
        if (cubit.loading) return const Center(child: AppLoader());

        if (cubit.items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cubit.error == null ? Icons.notifications_none : Icons.warning_amber_rounded,
                    size: 24,
                    color: cubit.error == null ? skin.textTertiary : skin.red,
                  ),
                  const VerticalSpace(11),
                  AppText(
                    cubit.error == null ? 'Nothing yet' : "Couldn't load notifications",
                    style: AppTextStyle.style17Bold,
                  ),
                  const VerticalSpace(6),
                  AppText(
                    cubit.error ??
                        'Alerts about agents that need you and PRs that are ready show up here.',
                    style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (notification) {
              final metrics = notification.metrics;
              if (metrics.pixels >= metrics.maxScrollExtent - 200) cubit.loadMore();
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: cubit.items.length + (cubit.loadingMore ? 1 : 0),
              separatorBuilder: (_, _) => Container(
                height: 1,
                margin: const EdgeInsets.only(left: 58),
                color: skin.borderSubtle,
              ),
              itemBuilder: (context, index) {
                if (index >= cubit.items.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: AppLoader()),
                  );
                }
                final notification = cubit.items[index];
                return NotificationRow(
                  type: notification.type ?? '',
                  title: notification.title ?? '',
                  body: notification.body ?? '',
                  createdAt: notification.createdAt ?? '',
                  unread: notification.status == 'unread',
                  onTap: () => _open(context, notification),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
```

Create `packages/mobile/lib/feature/notification/presentation/notifications_screen/ui/widgets/notification_bell.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<NotificationsCubit, NotificationsState>(
      buildWhen: (previous, current) => current is NotificationsReadyState,
      builder: (context, state) {
        final unread = context.read<NotificationsCubit>().unreadCount;
        return Semantics(
          button: true,
          label: 'Notifications',
          child: IconButton(
            onPressed: () => Navigator.of(context).pushNamed(RoutesStrings.notifications),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.notifications_none, size: 20, color: skin.textSecondary),
                if (unread > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: skin.blue,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: AppText(
                        unread > 99 ? '99+' : '$unread',
                        style: AppTextStyle.style10Bold.copyWith(color: skin.onAccent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Write the screen**

Create `packages/mobile/lib/feature/notification/presentation/notifications_screen/ui/notifications_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/ui/widgets/notifications_body.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocListener<NotificationsCubit, NotificationsState>(
    listener: (context, state) {},
    child: AppScaffold(
      appBar: GlobalAppbar.sub(
        titleText: 'Notifications',
        actions: [
          BlocBuilder<NotificationsCubit, NotificationsState>(
            buildWhen: (previous, current) => current is NotificationsReadyState,
            builder: (context, state) {
              final cubit = context.read<NotificationsCubit>();
              if (cubit.unreadCount == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: cubit.markAllRead,
                child: AppText(
                  'Mark all read',
                  style: AppTextStyle.style15SemiBold.copyWith(color: context.skin.blue),
                ),
              );
            },
          ),
        ],
      ),
      body: const NotificationsBody(),
    ),
  );
}
```

- [ ] **Step 6: Route, register and hang the bell**

In `routes_strings.dart`:

```dart
  static const String notifications = '/notifications';
```

In `app_router.dart`, add the case and widen the sessions route:

```dart
      case RoutesStrings.notifications:
        return MaterialPageRoute(
          builder: (context) => BlocProvider.value(
            value: sl<NotificationsCubit>(),
            child: const NotificationsScreen(),
          ),
          settings: settings,
        );
```

```dart
      case RoutesStrings.sessions:
        return MaterialPageRoute(
          builder: (context) => MultiBlocProvider(
            providers: [
              BlocProvider.value(value: sl<SessionsCubit>()),
              BlocProvider.value(value: sl<NotificationsCubit>()),
            ],
            child: const HomeShell(),
          ),
          settings: settings,
        );
```

In `service_locator.dart`, add the call in `init()` and the method:

```dart
  static void _notificationFeatureSetup() {
    sl.registerLazySingleton<NotificationsCubit>(
      () => NotificationsCubit(sl<NotificationRepository>()),
    );

    sl.registerLazySingleton<NotificationRepository>(
      () => NotificationRepositoryImp(sl<NotificationRemoteDataSource>(), sl<NetworkStatus>()),
    );
    sl.registerLazySingleton<NotificationRemoteDataSource>(
      () => NotificationRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }
```

In `sessions_screen.dart`, hang the bell off the existing app bar:

```dart
      appBar: const GlobalAppbar.main(actions: [NotificationBell()]),
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/feature/notification test/core/app_routes/app_router_test.dart`
Expected: PASS.

- [ ] **Step 8: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 878/878 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the notifications screen and the board's bell"
```

---
### Task 12: Push registration bookkeeping

Ports the half of `lib/push.ts` that is **not** the Expo SDK: the persisted registration, the
switch-daemon unregister, and the pending-unregister retry queue. All of it lands now, behind the
`PushTokenSource` seam, and none of it needs a Firebase credential.

The reason this exists at all: persisting the *daemon* alongside the token is what lets the app
unregister from the **right** daemon after a restart or a config change, so an old daemon cannot keep
pushing to a phone that is no longer watching it. If that unregister fails because the old daemon is
unreachable, dropping it would silently leave that push alive — hence the bounded pending queue.

**Files:**
- Create: `packages/mobile/lib/feature/notification/logic/push_token_source.dart`
- Create: `packages/mobile/lib/feature/notification/logic/push_registration.dart`
- Create: `packages/mobile/lib/feature/notification/logic/push_registrar.dart`
- Test: `packages/mobile/test/feature/notification/logic/push_registrar_test.dart`

**Interfaces:**
- Consumes: `NotificationRepository`, `ServerConfigStore`, `ServerConfig`, `FlutterSecureStorage`,
  `PushStatus`, `PushRegisterResult`, `classifyServerFailure`, `Result`, `Failure`.
- Produces:
  - `abstract class PushTokenSource` with `bool get supported`, `Future<PushStatus> permissionStatus()`,
    `Future<bool> requestPermission()`, `Future<String?> getToken()`, `String get platform`,
    `Future<String?> deviceName()`; and `class UnconfiguredPushTokenSource implements PushTokenSource`
    whose `supported` is `false` and whose `getToken` returns `null`.
  - `PushRegistration({required String token, required String host, required String httpPort,
    required bool secure, required String password})` with `fromJson`/`toJson`, `ServerConfig get
    config`, `bool sameDaemon(ServerConfig other)`.
  - `PushRegistrationStore(FlutterSecureStorage storage)` with `load()`, `save()`, `clear()`,
    `pending()`, `queuePending()`, `savePending()` and `kMaxPendingUnregister = 10`.
  - `PushRegistrar(NotificationRepository repository, PushRegistrationStore store, PushTokenSource
    tokens)` with `Future<PushRegisterResult> register(ServerConfig? config, {required bool ask})`,
    `Future<void> unregister()`, `Future<PushStatus> status()`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/notification/logic/push_registrar_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/logic/push_registration.dart';
import 'package:operator_mobile/feature/notification/logic/push_registrar.dart';
import 'package:operator_mobile/feature/notification/logic/push_status.dart';
import 'package:operator_mobile/feature/notification/logic/push_token_source.dart';

class _MockRepository extends Mock implements NotificationRepository {}

class _MemorySecureStorage implements PushSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeTokenSource implements PushTokenSource {
  _FakeTokenSource({this.token = 't-new', this.granted = true, this.supported = true});

  String? token;
  bool granted;

  @override
  final bool supported;

  @override
  String get platform => 'ios';

  @override
  Future<String?> deviceName() async => 'iPhone';

  @override
  Future<String?> getToken() async => token;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<PushStatus> permissionStatus() async => PushStatus(
    supported: supported,
    granted: granted,
    canAskAgain: true,
    registered: false,
  );
}

const ServerConfig current = ServerConfig(
  host: '10.0.0.5',
  httpPort: '3011',
  secure: false,
  password: 'secret12',
);

const ServerConfig other = ServerConfig(
  host: '10.0.0.9',
  httpPort: '3011',
  secure: false,
  password: 'other-secret',
);

const PushRegistration oldRegistration = PushRegistration(
  token: 't-old',
  host: '10.0.0.9',
  httpPort: '3011',
  secure: false,
  password: 'other-secret',
);

void main() {
  late _MockRepository repository;
  late _MemorySecureStorage storage;
  late PushRegistrationStore store;

  setUpAll(() {
    registerFallbackValue(const RegisterPushDeviceParams(token: 't'));
    registerFallbackValue(current);
  });

  setUp(() {
    repository = _MockRepository();
    storage = _MemorySecureStorage();
    store = PushRegistrationStore(storage);
    when(() => repository.registerPushDevice(any(), target: any(named: 'target')))
        .thenAnswer((_) async => Result.success(true));
    when(() => repository.unregisterPushDevice(any(), target: any(named: 'target')))
        .thenAnswer((_) async => Result.success(true));
  });

  PushRegistrar registrar({PushTokenSource? tokens}) =>
      PushRegistrar(repository, store, tokens ?? _FakeTokenSource());

  test('refuses to spend the permission prompt when no daemon is paired', () async {
    final result = await registrar().register(null, ask: true);

    expect(result, const PushNotRegistered(PushRegisterFailure.notPaired));
    verifyNever(() => repository.registerPushDevice(any(), target: any(named: 'target')));
  });

  test('reports unsupported before asking for anything on a device that cannot push', () async {
    final result = await registrar(
      tokens: _FakeTokenSource(supported: false),
    ).register(current, ask: true);

    expect(result, const PushNotRegistered(PushRegisterFailure.unsupported));
  });

  test('reports denied when permission is refused', () async {
    final result = await registrar(
      tokens: _FakeTokenSource(granted: false),
    ).register(current, ask: true);

    expect(result, const PushNotRegistered(PushRegisterFailure.denied));
  });

  test('reports notConfigured when the build cannot mint a token', () async {
    final result = await registrar(
      tokens: _FakeTokenSource(token: null),
    ).register(current, ask: true);

    expect(result, const PushNotRegistered(PushRegisterFailure.notConfigured));
  });

  test('registers the token and persists the daemon it registered with', () async {
    final result = await registrar().register(current, ask: true);

    expect(result, const PushRegistered('t-new'));
    final saved = await store.load();
    expect(saved!.token, 't-new');
    expect(saved.host, '10.0.0.5');
    expect(saved.password, 'secret12');
    final captured = verify(
      () => repository.registerPushDevice(captureAny(), target: any(named: 'target')),
    ).captured.single as RegisterPushDeviceParams;
    expect(captured.toJson(), {'token': 't-new', 'platform': 'ios', 'deviceName': 'iPhone'});
  });

  test('unregisters from the previous daemon before registering with a new one', () async {
    await storage.write(kPushRegistrationKey, jsonEncode(oldRegistration.toJson()));

    await registrar().register(current, ask: true);

    verify(() => repository.unregisterPushDevice('t-old', target: oldRegistration.config))
        .called(1);
  });

  test('does not unregister when the daemon has not changed', () async {
    await registrar().register(current, ask: true);
    clearInteractions(repository);

    await registrar().register(current, ask: true);

    verifyNever(() => repository.unregisterPushDevice(any(), target: any(named: 'target')));
  });

  test('queues an unregister the old daemon refused, and retries it on the next register',
      () async {
    await storage.write(kPushRegistrationKey, jsonEncode(oldRegistration.toJson()));
    when(() => repository.unregisterPushDevice('t-old', target: any(named: 'target'))).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'gone', statusCode: -6)),
    );

    await registrar().register(current, ask: true);
    expect((await store.pending()).single.token, 't-old');

    when(() => repository.unregisterPushDevice('t-old', target: any(named: 'target')))
        .thenAnswer((_) async => Result.success(true));
    await registrar().register(other, ask: true);

    expect(await store.pending(), isEmpty);
  });

  test('classifies a daemon rejection instead of blaming the build', () async {
    when(() => repository.registerPushDevice(any(), target: any(named: 'target'))).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'nope', statusCode: 401)),
    );

    final result = await registrar().register(current, ask: true);

    expect(result, const PushNotRegistered(PushRegisterFailure.serverAuth, statusCode: 401));
    expect(await store.load(), isNull);
  });

  test('unregistering clears the active registration even when the daemon is unreachable',
      () async {
    await registrar().register(current, ask: true);
    when(() => repository.unregisterPushDevice(any(), target: any(named: 'target'))).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'gone', statusCode: -6)),
    );

    await registrar().unregister();

    expect(await store.load(), isNull);
    expect((await store.pending()).single.token, 't-new');
  });
}
```

That is **10 tests**.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/notification/logic/push_registrar_test.dart`
Expected: FAIL — `push_registration.dart`, `push_registrar.dart` and `push_token_source.dart` do not
exist.

- [ ] **Step 3: Write the token seam**

Create `packages/mobile/lib/feature/notification/logic/push_token_source.dart`:

```dart
import 'package:operator_mobile/feature/notification/logic/push_status.dart';

abstract class PushTokenSource {
  bool get supported;

  String get platform;

  Future<PushStatus> permissionStatus();

  Future<bool> requestPermission();

  Future<String?> getToken();

  Future<String?> deviceName();
}

/// The source a build without Firebase configuration ships with: it can answer
/// every question honestly and mints nothing.
class UnconfiguredPushTokenSource implements PushTokenSource {
  const UnconfiguredPushTokenSource();

  @override
  bool get supported => false;

  @override
  String get platform => '';

  @override
  Future<PushStatus> permissionStatus() async => const PushStatus(
    supported: false,
    granted: false,
    canAskAgain: false,
    registered: false,
  );

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> getToken() async => null;

  @override
  Future<String?> deviceName() async => null;
}
```

- [ ] **Step 4: Write the registration record and its store**

Create `packages/mobile/lib/feature/notification/logic/push_registration.dart`:

```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:operator_mobile/core/api/server_config.dart';

const String kPushRegistrationKey = 'opr.pushRegistration';
const String kPushPendingUnregisterKey = 'opr.pushPendingUnregister';
const int kMaxPendingUnregister = 10;

abstract class PushSecureStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterPushSecureStorage implements PushSecureStorage {
  const FlutterPushSecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class PushRegistration extends Equatable {
  const PushRegistration({
    required this.token,
    required this.host,
    required this.httpPort,
    required this.secure,
    required this.password,
  });

  final String token;
  final String host;
  final String httpPort;
  final bool secure;
  final String password;

  factory PushRegistration.fromJson(Map<String, dynamic> json) => PushRegistration(
    token: json['token'] as String? ?? '',
    host: json['host'] as String? ?? '',
    httpPort: json['httpPort'] as String? ?? '',
    secure: json['secure'] as bool? ?? false,
    password: json['password'] as String? ?? '',
  );

  factory PushRegistration.of(String token, ServerConfig config) => PushRegistration(
    token: token,
    host: config.host,
    httpPort: config.httpPort,
    secure: config.secure,
    password: config.password,
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'host': host,
    'httpPort': httpPort,
    'secure': secure,
    'password': password,
  };

  ServerConfig get config =>
      ServerConfig(host: host, httpPort: httpPort, secure: secure, password: password);

  /// Identity is the address, not the credential: a password change is the same
  /// daemon.
  bool sameDaemon(ServerConfig other) =>
      host == other.host && httpPort == other.httpPort && secure == other.secure;

  @override
  List<Object?> get props => [token, host, httpPort, secure, password];
}

class PushRegistrationStore {
  const PushRegistrationStore(this._storage);

  final PushSecureStorage _storage;

  Future<PushRegistration?> load() async {
    final raw = await _storage.read(kPushRegistrationKey);
    if (raw == null) return null;
    try {
      return PushRegistration.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PushRegistration registration) =>
      _storage.write(kPushRegistrationKey, jsonEncode(registration.toJson()));

  Future<void> clear() => _storage.delete(kPushRegistrationKey);

  Future<List<PushRegistration>> pending() async {
    final raw = await _storage.read(kPushPendingUnregisterKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((entry) => PushRegistration.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePending(List<PushRegistration> registrations) async {
    if (registrations.isEmpty) {
      await _storage.delete(kPushPendingUnregisterKey);
      return;
    }
    final bounded = registrations.length > kMaxPendingUnregister
        ? registrations.sublist(registrations.length - kMaxPendingUnregister)
        : registrations;
    await _storage.write(
      kPushPendingUnregisterKey,
      jsonEncode(bounded.map((registration) => registration.toJson()).toList()),
    );
  }

  Future<void> queuePending(PushRegistration registration) async {
    final queued = await pending();
    final duplicate = queued.any(
      (entry) => entry.token == registration.token && entry.sameDaemon(registration.config),
    );
    if (duplicate) return;
    await savePending([...queued, registration]);
  }
}
```

- [ ] **Step 5: Write the registrar**

Create `packages/mobile/lib/feature/notification/logic/push_registrar.dart`:

```dart
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/logic/push_registration.dart';
import 'package:operator_mobile/feature/notification/logic/push_status.dart';
import 'package:operator_mobile/feature/notification/logic/push_token_source.dart';

class PushRegistrar {
  const PushRegistrar(this._repository, this._store, this._tokens);

  final NotificationRepository _repository;
  final PushRegistrationStore _store;
  final PushTokenSource _tokens;

  Future<PushStatus> status() async {
    final permission = await _tokens.permissionStatus();
    final registration = await _store.load();
    return PushStatus(
      supported: permission.supported,
      granted: permission.granted,
      canAskAgain: permission.canAskAgain,
      registered: registration != null,
    );
  }

  Future<PushRegisterResult> register(ServerConfig? config, {required bool ask}) async {
    if (!hasServer(config)) return const PushNotRegistered(PushRegisterFailure.notPaired);
    if (!_tokens.supported) return const PushNotRegistered(PushRegisterFailure.unsupported);

    final permission = await _tokens.permissionStatus();
    final granted = permission.granted ||
        (ask && permission.canAskAgain && await _tokens.requestPermission());
    if (!granted) return const PushNotRegistered(PushRegisterFailure.denied);

    await _flushPending();

    final prior = await _store.load();
    if (prior != null && !prior.sameDaemon(config!)) {
      await _unregisterOrQueue(prior);
    }

    final token = await _tokens.getToken();
    if (token == null || token.isEmpty) {
      return const PushNotRegistered(PushRegisterFailure.notConfigured);
    }

    final result = await _repository.registerPushDevice(
      RegisterPushDeviceParams(
        token: token,
        platform: _tokens.platform,
        deviceName: await _tokens.deviceName(),
      ),
    );

    int? statusCode;
    var failed = false;
    result.when(
      onSuccess: (_) {},
      onFailure: (failure) {
        failed = true;
        statusCode = failure.statusCode;
      },
    );
    if (failed) {
      return PushNotRegistered(classifyServerFailure(statusCode), statusCode: statusCode);
    }

    await _store.save(PushRegistration.of(token, config!));
    return PushRegistered(token);
  }

  /// Clears the active registration first: the device is disconnecting, so it is
  /// no longer registered regardless of whether the call below lands. The retry
  /// is tracked in the pending queue instead.
  Future<void> unregister() async {
    final registration = await _store.load();
    await _store.clear();
    if (registration == null) return;
    await _unregisterOrQueue(registration);
    await _flushPending();
  }

  Future<void> _unregisterOrQueue(PushRegistration registration) async {
    final result = await _repository.unregisterPushDevice(
      registration.token,
      target: registration.config,
    );
    var failed = false;
    result.when(onSuccess: (_) {}, onFailure: (_) => failed = true);
    if (failed) await _store.queuePending(registration);
  }

  Future<void> _flushPending() async {
    final queued = await _store.pending();
    if (queued.isEmpty) return;
    final stillPending = <PushRegistration>[];
    for (final registration in queued) {
      final result = await _repository.unregisterPushDevice(
        registration.token,
        target: registration.config,
      );
      result.when(onSuccess: (_) {}, onFailure: (_) => stillPending.add(registration));
    }
    await _store.savePending(stillPending);
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/feature/notification/logic/push_registrar_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 7: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 888/888 green.

```bash
git add packages/mobile/lib/feature/notification packages/mobile/test/feature/notification
git commit -m "feat(mobile): add push registration bookkeeping behind a token seam"
```

---
### Task 13: The Settings Notifications group

Ports the `NotificationsSection` of `app/(tabs)/settings.tsx:192–256`. Push is one switch plus a
footer that explains where it currently stands, and a History row. Until Task 22 lands, the app is
wired to `UnconfiguredPushTokenSource`, so the switch is disabled and honest rather than broken.

`SettingsGroup` has no switch row yet, so this task adds `SettingsToggle` beside `SettingsRow` — the
same file, the same visual language.

**Files:**
- Modify: `packages/mobile/lib/core/widgets/main_widgets/settings_group.dart`
- Modify: `packages/mobile/lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Test: `packages/mobile/test/feature/settings/presentation/settings_screen/ui/settings_body_test.dart` (modify)

**Interfaces:**
- Consumes: `describePushToggle`, `PushStatus`, `PushRegistrar`, `describeRegisterFailure`,
  `openAppSettings` (permission_handler), `ServerConfigStore`, `AppDialog`, `RoutesStrings.notifications`.
- Produces: `SettingsToggle({required IconData icon, required String label, required bool value,
  required bool disabled, required bool busy, required ValueChanged<bool> onChanged})`, and
  `PushRegistrar` / `PushTokenSource` registrations in the service locator.

- [ ] **Step 1: Write the failing test**

Modify `packages/mobile/test/feature/settings/presentation/settings_screen/ui/settings_body_test.dart`.
It already has `pumpBody(tester, sessionsCubit: ...)`, a `_MockServerConfigStore` and an `sl.reset()`
in `setUp` — this adds a fake token source, a mocked notification repository, the two `sl`
registrations the group reads, and a stub route for History. At the top of the file:

```dart
class _MockNotificationRepository extends Mock implements NotificationRepository {}

class _MemorySecureStorage implements PushSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeTokenSource implements PushTokenSource {
  bool supportedValue = false;
  bool granted = false;

  @override
  bool get supported => supportedValue;

  @override
  String get platform => 'ios';

  @override
  Future<String?> deviceName() async => 'iPhone';

  @override
  Future<String?> getToken() async => 't-1';

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<PushStatus> permissionStatus() async => PushStatus(
    supported: supportedValue,
    granted: granted,
    canAskAgain: true,
    registered: false,
  );
}
```

In `main()`, beside the existing late fields and inside `setUp` after `sl.reset()`:

```dart
  late _MockNotificationRepository notificationRepository;
  late _FakeTokenSource tokenSource;
```
```dart
    notificationRepository = _MockNotificationRepository();
    tokenSource = _FakeTokenSource();
    when(() => notificationRepository.registerPushDevice(any(), target: any(named: 'target')))
        .thenAnswer((_) async => Result.success(true));
    when(() => notificationRepository.unregisterPushDevice(any(), target: any(named: 'target')))
        .thenAnswer((_) async => Result.success(true));
    sl.registerLazySingleton<PushRegistrar>(
      () => PushRegistrar(
        notificationRepository,
        PushRegistrationStore(_MemorySecureStorage()),
        tokenSource,
      ),
    );
```

with `registerFallbackValue(const RegisterPushDeviceParams(token: 't'))` added to a `setUpAll`, and
one more entry in `pumpBody`'s `routes:` map:

```dart
              RoutesStrings.notifications: (_) =>
                  const Scaffold(body: Text('Notifications screen')),
```

Then the five tests, inside the same `main()`:

```dart
  testWidgets('the push switch is off and explains itself with no Firebase configuration', (
    tester,
  ) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    expect(find.text('Agent notifications'), findsOneWidget);
    expect(find.text('Push notifications need a physical device.'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });

  testWidgets('the History row opens the notifications route', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications screen'), findsOneWidget);
  });

  testWidgets('a paired, granted, unregistered device offers a live switch', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);
    tokenSource
      ..supportedValue = true
      ..granted = true;

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    expect(find.text("This device isn't registered with your server yet."), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  });

  testWidgets('turning the switch on registers the device', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);
    tokenSource
      ..supportedValue = true
      ..granted = true;

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    verify(() => notificationRepository.registerPushDevice(any(), target: any(named: 'target')))
        .called(1);
    expect(find.text("You'll be alerted when an agent needs you or a PR is ready."), findsOneWidget);
  });

  testWidgets('a rejected registration explains the server, not the build', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);
    tokenSource
      ..supportedValue = true
      ..granted = true;
    when(() => notificationRepository.registerPushDevice(any(), target: any(named: 'target')))
        .thenAnswer(
          (_) async => Result.failure(ServerFailure(error: 'x', message: 'no', statusCode: 401)),
        );

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Your Operator server rejected the request'), findsOneWidget);
  });
```

That is **5 tests**.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/feature/settings`
Expected: FAIL — there is no Notifications group.

- [ ] **Step 3: Add the switch row**

Append to `packages/mobile/lib/core/widgets/main_widgets/settings_group.dart`:

```dart
class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.disabled = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool disabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 17, color: skin.textSecondary),
            const HorizontalSpace(10),
            Expanded(
              child: AppText(
                label,
                style: AppTextStyle.style15Regular.copyWith(color: skin.textPrimary),
              ),
            ),
            if (busy) ...[const AppLoader(strokeWidth: 2), const HorizontalSpace(10)],
            Switch(
              value: value,
              activeThumbColor: skin.onAccent,
              activeTrackColor: skin.blue,
              onChanged: disabled || busy ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add the group to Settings**

In `settings_body.dart`, add the state, the handler and the group. The state class gains:

```dart
  PushStatus? _pushStatus;
  bool _pushBusy = false;
```

```dart
  Future<void> _refreshPushStatus() async {
    final status = await sl<PushRegistrar>().status();
    if (!mounted) return;
    setState(() => _pushStatus = status);
  }

  Future<void> _togglePush(BuildContext context, bool next) async {
    final toggle = describePushToggle(_pushStatus, sl<ServerConfigStore>().current);
    if (toggle.blocked) {
      final open = await AppDialog.confirm(
        context,
        title: 'Notifications are blocked',
        message: 'Allow notifications for Operator in your system settings, then come back.',
        confirmLabel: 'Open settings',
        cancelLabel: 'Not now',
      );
      if (open) await openAppSettings();
      return;
    }

    setState(() => _pushBusy = true);
    final registrar = sl<PushRegistrar>();
    if (!next) {
      await registrar.unregister();
    } else {
      final result = await registrar.register(sl<ServerConfigStore>().current, ask: true);
      if (result is PushNotRegistered && context.mounted) {
        final described = describeRegisterFailure(
          result.reason,
          Theme.of(context).platform,
          statusCode: result.statusCode,
        );
        await AppDialog.confirm(
          context,
          title: described.title,
          message: described.message,
          confirmLabel: 'OK',
          cancelLabel: 'Close',
        );
      }
    }
    if (!mounted) return;
    setState(() => _pushBusy = false);
    await _refreshPushStatus();
  }
```

`initState` gains `_refreshPushStatus();` beside `_loadBuildInfo();`, and the group goes between the
Theme group and the About group:

```dart
            const VerticalSpace(20),
            Builder(
              builder: (context) {
                final toggle = describePushToggle(_pushStatus, config);
                return SettingsGroup(
                  title: 'Notifications',
                  footer: toggle.footer,
                  children: [
                    SettingsToggle(
                      icon: Icons.notifications_none,
                      label: 'Agent notifications',
                      value: toggle.value,
                      disabled: toggle.disabled,
                      busy: _pushBusy,
                      onChanged: (next) => _togglePush(context, next),
                    ),
                    SettingsRow(
                      icon: Icons.history,
                      label: 'History',
                      onTap: () =>
                          Navigator.of(context).pushNamed(RoutesStrings.notifications),
                    ),
                  ],
                );
              },
            ),
```

- [ ] **Step 5: Register the registrar**

In `service_locator.dart`, inside `_notificationFeatureSetup()`:

```dart
    sl.registerLazySingleton<PushTokenSource>(() => const UnconfiguredPushTokenSource());
    sl.registerLazySingleton<PushRegistrationStore>(
      () => PushRegistrationStore(FlutterPushSecureStorage(sl<FlutterSecureStorage>())),
    );
    sl.registerLazySingleton<PushRegistrar>(
      () => PushRegistrar(
        sl<NotificationRepository>(),
        sl<PushRegistrationStore>(),
        sl<PushTokenSource>(),
      ),
    );
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/feature/settings`
Expected: PASS.

- [ ] **Step 7: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 893/893 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the Settings notifications group"
```

---
### Task 14: On-device dictation

Ports `lib/voice/types.ts` and `lib/voice/deviceProvider.ts` — the spec ledger's
`voice/deviceProvider.test.ts` row, adapted to `speech_to_text`. The provider's whole job is turning a
ragged recogniser stream — several finals, a trailing `done`, errors that are really just silence —
into exactly one outcome, which is why the tests drive that stream by hand through a fake.

Three RN behaviors are load-bearing and must survive:

- **iOS is one cumulative stream, Android is a sequence of segments.** iOS results, `isFinal` ones
  included, restate everything said so far; banking them the way Android's segments are banked is
  what turned a long dictation into "How the How's the system system turning How is the system
  turning?".
- **`done` ends the recording, not a final result.** In continuous mode a final result means "segment
  done", so settling on it silently drops everything said after the user's first pause.
- **A stop that is never acknowledged still delivers.** If the recogniser dies without reporting
  `done`, the 4-second watchdog settles with what was heard, instead of stranding the words behind a
  UI stuck on "recording".

What cannot be ported, per the deviations table: `contextualStrings` (the 24-word coding vocabulary),
the two `AVAudioSession` categories, the Android intent extras, and the `speechstart` utterance
boundary. `speech_to_text` exposes none of them.

**Files:**
- Modify: `packages/mobile/pubspec.yaml`
- Create: `packages/mobile/lib/feature/chat/voice/voice_types.dart`
- Create: `packages/mobile/lib/feature/chat/voice/speech_recognizer.dart`
- Create: `packages/mobile/lib/feature/chat/voice/device_provider.dart`
- Test: `packages/mobile/test/feature/chat/voice/device_provider_test.dart`

**Interfaces:**
- Consumes: `speech_to_text 7.4.0`, `defaultTargetPlatform`.
- Produces:
  - `enum VoiceState { idle, starting, recording, transcribing, denied, unavailable }`,
    `enum VoiceMode { push, latched }`,
    `VoiceCallbacks({required VoidCallback onReady, required void Function(String) onPartial,
    required void Function(String) onFinal, required void Function(String) onError})`,
    `abstract class VoiceProvider` with `bool get available`, `String? get language`,
    `Future<bool> requestPermission()`, `Future<void> start(VoiceCallbacks callbacks, {VoiceMode mode})`,
    `void stop()`, `void abort()`.
  - `SpeechResult(String transcript, {required bool isFinal})`,
    `SpeechFailure(String errorMsg, {required bool permanent})`,
    `abstract class SpeechRecognizer`, `class SpeechToTextRecognizer implements SpeechRecognizer`.
  - `DeviceVoiceProvider(SpeechRecognizer recognizer, {Duration stopGrace, TargetPlatform? platform})`.

- [ ] **Step 1: Add the dependency**

```bash
cd packages/mobile && flutter pub add speech_to_text
```

Expected: `pubspec.yaml` gains `speech_to_text: ^7.4.0`; `flutter pub get` resolves
`speech_to_text 7.4.0`, `speech_to_text_platform_interface 2.4.0`, `speech_to_text_windows 1.0.1`,
`json_annotation 4.12.0` and changes nothing else.

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 893/893 green.

- [ ] **Step 2: Write the failing test**

Create `packages/mobile/test/feature/chat/voice/device_provider_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/voice/device_provider.dart';
import 'package:operator_mobile/feature/chat/voice/speech_recognizer.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

class FakeRecognizer implements SpeechRecognizer {
  FakeRecognizer({this.availableValue = true, this.permission = true});

  bool availableValue;
  bool permission;
  int permissionChecks = 0;
  int listenCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  bool throwOnListen = false;
  List<String> supportedLocales = ['en-US', 'en-GB', 'en-IN'];
  String? systemLocale = 'en-IN';
  ({Duration pauseFor, Duration listenFor, String? localeId})? lastOptions;

  void Function(String status)? _onStatus;
  void Function(SpeechFailure failure)? _onError;
  void Function(SpeechResult result)? _onResult;

  void emitResult(String transcript, {bool isFinal = false}) =>
      _onResult?.call(SpeechResult(transcript, isFinal: isFinal));

  void emitStatus(String status) => _onStatus?.call(status);

  void emitError(String errorMsg, {bool permanent = false}) =>
      _onError?.call(SpeechFailure(errorMsg, permanent: permanent));

  @override
  bool get isAvailable => availableValue;

  @override
  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(SpeechFailure failure)? onError,
  }) async {
    permissionChecks++;
    _onStatus = onStatus;
    _onError = onError;
    return permission;
  }

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<List<String>> localeIds() async => supportedLocales;

  @override
  Future<String?> systemLocaleId() async => systemLocale;

  @override
  Future<void> listen({
    required void Function(SpeechResult result) onResult,
    String? localeId,
    required Duration pauseFor,
    required Duration listenFor,
  }) async {
    listenCalls++;
    if (throwOnListen) throw StateError('mic busy');
    _onResult = onResult;
    lastOptions = (pauseFor: pauseFor, listenFor: listenFor, localeId: localeId);
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> cancel() async => cancelCalls++;
}

class Harness {
  final List<String> partials = [];
  final List<String> finals = [];
  final List<String> errors = [];
  int readies = 0;

  VoiceCallbacks get callbacks => VoiceCallbacks(
    onReady: () => readies++,
    onPartial: partials.add,
    onFinal: finals.add,
    onError: errors.add,
  );
}

const Duration grace = Duration(milliseconds: 30);

void main() {
  late FakeRecognizer recognizer;

  setUp(() => recognizer = FakeRecognizer());

  DeviceVoiceProvider provider({TargetPlatform platform = TargetPlatform.android}) =>
      DeviceVoiceProvider(recognizer, stopGrace: grace, platform: platform);

  Future<(DeviceVoiceProvider, Harness)> started({
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    final voice = provider(platform: platform);
    final harness = Harness();
    await voice.requestPermission();
    await voice.start(harness.callbacks);
    return (voice, harness);
  }

  group('availability and permission', () {
    test('reports unavailable when the device has no recogniser', () async {
      recognizer.availableValue = false;
      final voice = provider();
      await voice.requestPermission();

      expect(voice.available, isFalse);
    });

    test('reports a declined permission rather than throwing', () async {
      recognizer.permission = false;

      expect(await provider().requestPermission(), isFalse);
    });

    test('does not re-ask the recogniser once permission is granted', () async {
      final voice = provider();

      await voice.requestPermission();
      await voice.requestPermission();
      await voice.requestPermission();

      expect(recognizer.permissionChecks, 1);
    });

    test('resolves the recogniser locale against the device locale', () async {
      recognizer.systemLocale = 'en_IN';
      final voice = provider();
      await voice.requestPermission();
      await voice.start(Harness().callbacks);

      expect(voice.language, 'en-IN');
      expect(recognizer.lastOptions?.localeId, 'en-IN');
    });

    test('falls back to the same language in another region, then to en-US', () async {
      recognizer.supportedLocales = ['en-GB', 'fr-FR'];
      recognizer.systemLocale = 'en-AU';
      final first = provider();
      await first.requestPermission();
      await first.start(Harness().callbacks);
      expect(first.language, 'en-GB');

      recognizer.supportedLocales = ['fr-FR'];
      final second = provider();
      await second.requestPermission();
      await second.start(Harness().callbacks);
      expect(second.language, 'en-US');
    });
  });

  group('warm-up', () {
    test('signals readiness only when the recogniser actually starts capturing', () async {
      final (_, harness) = await started();

      expect(harness.readies, 0);

      recognizer.emitStatus(kSpeechListening);
      expect(harness.readies, 1);
    });

    test('does not signal readiness for a session already abandoned', () async {
      final (voice, harness) = await started();

      voice.abort();
      recognizer.emitStatus(kSpeechListening);

      expect(harness.readies, 0);
    });

    test('asks for partial results and a pause window long enough to think in', () async {
      await started();

      expect(recognizer.lastOptions?.pauseFor, const Duration(seconds: 10));
      expect(recognizer.lastOptions?.listenFor.inMinutes, greaterThanOrEqualTo(5));
    });
  });

  group('transcript delivery', () {
    test('streams partials and delivers one final transcript', () async {
      final (_, harness) = await started();

      recognizer.emitResult('add a test');
      recognizer.emitResult('add a test for pairing');
      expect(harness.partials, ['add a test', 'add a test for pairing']);

      recognizer.emitResult('add a test for pairing.', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['add a test for pairing.']);
    });

    test('delivers the transcript exactly once even when done repeats', () async {
      final (_, harness) = await started();

      recognizer.emitResult('ship it', isFinal: true);
      recognizer.emitStatus(kSpeechDone);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['ship it']);
    });

    test('does not end the recording on a final result — the user may still be talking', () async {
      final (_, harness) = await started();

      recognizer.emitResult('open the pull request', isFinal: true);
      expect(harness.finals, isEmpty);

      recognizer.emitResult('and rerun the tests', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['open the pull request and rerun the tests']);
    });

    test('keeps banked segments while a later segment is still forming', () async {
      final (_, harness) = await started();

      recognizer.emitResult('fix the parser', isFinal: true);
      recognizer.emitResult('then');
      expect(harness.partials.last, 'fix the parser then');

      recognizer.emitResult('then commit');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['fix the parser then commit']);
    });

    test('keeps earlier speech when Android rolls over to a new segment with no final', () async {
      final (_, harness) = await started();

      recognizer.emitResult('add a test');
      recognizer.emitResult('add a test for the pairing flow');
      recognizer.emitResult('then run');
      recognizer.emitResult('then run the linter');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['add a test for the pairing flow then run the linter']);
    });

    test('does not treat an in-place revision as a new segment', () async {
      final (_, harness) = await started();

      recognizer.emitResult('add a test');
      recognizer.emitResult('add a test for pairing');
      recognizer.emitResult('add attest for pairing flow');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['add attest for pairing flow']);
    });

    test('does not duplicate a segment that ends with a final result', () async {
      final (_, harness) = await started();

      recognizer.emitResult('open the');
      recognizer.emitResult('open the pull request');
      recognizer.emitResult('open the pull request', isFinal: true);
      recognizer.emitResult('then merge it');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['open the pull request then merge it']);
    });

    test('does not duplicate when iOS emits a cumulative final mid-recording', () async {
      final (_, harness) = await started(platform: TargetPlatform.iOS);

      recognizer.emitResult('how is the system');
      recognizer.emitResult('how is the system turning', isFinal: true);
      recognizer.emitResult('how is the system turning right now');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['how is the system turning right now']);
    });

    test('does not duplicate across several cumulative iOS finals', () async {
      final (_, harness) = await started(platform: TargetPlatform.iOS);

      recognizer.emitResult('open the', isFinal: true);
      recognizer.emitResult('open the pull request', isFinal: true);
      recognizer.emitResult('open the pull request and merge it', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['open the pull request and merge it']);
    });

    test('keeps the live readout cumulative-but-not-doubled on iOS', () async {
      final (_, harness) = await started(platform: TargetPlatform.iOS);

      recognizer.emitResult('ship the');
      recognizer.emitResult('ship the release', isFinal: true);

      expect(harness.partials.last, 'ship the release');
    });

    test('preserves earlier speech across an iOS recognition-task restart', () async {
      final (_, harness) = await started(platform: TargetPlatform.iOS);

      recognizer.emitResult('first half of the sentence');
      recognizer.emitResult('first half of the sentence complete', isFinal: true);
      recognizer.emitResult('second');
      recognizer.emitResult('second half now');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['first half of the sentence complete second half now']);
    });

    test('keeps the words already heard when the session ends without a final result', () async {
      final (_, harness) = await started();

      recognizer.emitResult('run the tests');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['run the tests']);
      expect(harness.errors, isEmpty);
    });

    test('reports an empty transcript rather than an error when nothing was said', () async {
      final (_, harness) = await started();

      recognizer.emitError('error_no_match');

      expect(harness.finals, ['']);
      expect(harness.errors, isEmpty);
    });

    test('trims the transcript', () async {
      final (_, harness) = await started();

      recognizer.emitResult('  hello world  ', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['hello world']);
    });
  });

  group('failures', () {
    test('surfaces a readable message for a real error', () async {
      final (_, harness) = await started();

      recognizer.emitError('error_permission', permanent: true);

      expect(harness.errors.single, contains('permission'));
      expect(harness.finals, isEmpty);
    });

    test('does not emit a transcript after an error', () async {
      final (_, harness) = await started();

      recognizer.emitError('error_audio_error', permanent: true);
      recognizer.emitResult('too late', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, isEmpty);
      expect(harness.errors, hasLength(1));
    });

    test('reports a start failure through onError', () async {
      recognizer.throwOnListen = true;
      final voice = provider();
      final harness = Harness();
      await voice.requestPermission();

      await voice.start(harness.callbacks);

      expect(harness.errors.single, contains('mic busy'));
    });
  });

  group('lifecycle', () {
    test('aborting delivers nothing and drops its callbacks', () async {
      final (voice, harness) = await started();

      voice.abort();
      expect(recognizer.cancelCalls, 1);

      recognizer.emitError('error_request_cancelled');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, isEmpty);
      expect(harness.errors, isEmpty);
    });

    test('does not leave the previous recording attached on restart', () async {
      final voice = provider();
      final first = Harness();
      final second = Harness();
      await voice.requestPermission();

      await voice.start(first.callbacks);
      await voice.start(second.callbacks);
      recognizer.emitResult('second phrase', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(first.finals, isEmpty);
      expect(second.finals, ['second phrase']);
    });

    test('delivers the transcript even if done never arrives after stop', () async {
      final (voice, harness) = await started();

      recognizer.emitResult('deploy to staging');
      voice.stop();
      expect(harness.finals, isEmpty);

      await Future<void>.delayed(grace * 2);

      expect(harness.finals, ['deploy to staging']);
    });

    test('does not double-deliver when done arrives after stop', () async {
      final (voice, harness) = await started();

      recognizer.emitResult('run the linter');
      voice.stop();
      recognizer.emitStatus(kSpeechDone);
      await Future<void>.delayed(grace * 2);

      expect(harness.finals, ['run the linter']);
    });
  });
}
```

That is **29 tests**.

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/feature/chat/voice/device_provider_test.dart`
Expected: FAIL — `voice_types.dart`, `speech_recognizer.dart` and `device_provider.dart` do not exist.

- [ ] **Step 4: Write the voice seam**

Create `packages/mobile/lib/feature/chat/voice/voice_types.dart`:

```dart
import 'package:flutter/foundation.dart';

/// `transcribing` is unreachable for the on-device recogniser, which streams. It
/// exists so a later batch provider needs no UI change.
enum VoiceState { idle, starting, recording, transcribing, denied, unavailable }

/// `push` holds the key; `latched` is double-tap, hands-free until tapped again.
enum VoiceMode { push, latched }

class VoiceCallbacks {
  const VoiceCallbacks({
    required this.onReady,
    required this.onPartial,
    required this.onFinal,
    required this.onError,
  });

  /// The microphone is actually capturing. Anything said before this is lost, so
  /// this — not the return of [VoiceProvider.start] — is when the UI may invite
  /// the user to speak.
  final VoidCallback onReady;
  final void Function(String text) onPartial;
  final void Function(String text) onFinal;
  final void Function(String message) onError;
}

abstract class VoiceProvider {
  bool get available;

  String? get language;

  Future<bool> requestPermission();

  Future<void> start(VoiceCallbacks callbacks, {VoiceMode mode = VoiceMode.push});

  /// Finish and emit a final result.
  void stop();

  /// Discard — no final result.
  void abort();
}
```

Create `packages/mobile/lib/feature/chat/voice/speech_recognizer.dart`:

```dart
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

const String kSpeechListening = SpeechToText.listeningStatus;
const String kSpeechDone = SpeechToText.doneStatus;

class SpeechResult {
  const SpeechResult(this.transcript, {required this.isFinal});

  final String transcript;
  final bool isFinal;
}

class SpeechFailure {
  const SpeechFailure(this.errorMsg, {required this.permanent});

  final String errorMsg;
  final bool permanent;
}

abstract class SpeechRecognizer {
  bool get isAvailable;

  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(SpeechFailure failure)? onError,
  });

  Future<bool> hasPermission();

  Future<List<String>> localeIds();

  Future<String?> systemLocaleId();

  Future<void> listen({
    required void Function(SpeechResult result) onResult,
    String? localeId,
    required Duration pauseFor,
    required Duration listenFor,
  });

  Future<void> stop();

  Future<void> cancel();
}

class SpeechToTextRecognizer implements SpeechRecognizer {
  SpeechToTextRecognizer([SpeechToText? speech]) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  @override
  bool get isAvailable => _speech.isAvailable;

  @override
  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(SpeechFailure failure)? onError,
  }) => _speech.initialize(
    onStatus: onStatus,
    onError: (SpeechRecognitionError error) =>
        onError?.call(SpeechFailure(error.errorMsg, permanent: error.permanent)),
  );

  @override
  Future<bool> hasPermission() => _speech.hasPermission;

  @override
  Future<List<String>> localeIds() async =>
      (await _speech.locales()).map((locale) => locale.localeId).toList();

  @override
  Future<String?> systemLocaleId() async => (await _speech.systemLocale())?.localeId;

  @override
  Future<void> listen({
    required void Function(SpeechResult result) onResult,
    String? localeId,
    required Duration pauseFor,
    required Duration listenFor,
  }) => _speech.listen(
    onResult: (SpeechRecognitionResult result) =>
        onResult(SpeechResult(result.recognizedWords, isFinal: result.finalResult)),
    listenOptions: SpeechListenOptions(
      partialResults: true,
      autoPunctuation: true,
      cancelOnError: false,
      localeId: localeId,
      pauseFor: pauseFor,
      listenFor: listenFor,
    ),
  );

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
```

- [ ] **Step 5: Write the provider**

Create `packages/mobile/lib/feature/chat/voice/device_provider.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:operator_mobile/feature/chat/voice/speech_recognizer.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

/// Long enough that the finger, not a silence timer, decides when a phrase ends —
/// the closest `speech_to_text` gets to RN's continuous mode.
const Duration kVoicePauseFor = Duration(seconds: 10);
const Duration kVoiceListenFor = Duration(minutes: 5);

/// Silence, a stray tap or a deliberate cancel is not a fault: settle normally so
/// anything already transcribed survives.
const Set<String> _silentErrors = {
  'error_no_match',
  'error_speech_timeout',
  'error_request_cancelled',
};

const Map<String, String> _errorMessages = {
  'error_permission':
      'Microphone or speech permission was denied. Enable it in Settings to dictate.',
  'error_speech_recognizer_request_not_authorized':
      'Microphone or speech permission was denied. Enable it in Settings to dictate.',
  'error_speech_recognizer_disabled': 'Speech recognition is unavailable on this device.',
  'error_language_not_supported': 'Speech recognition is not available for this language.',
  'error_language_unavailable': 'Speech recognition is not available for this language.',
  'error_assets_not_installed':
      'This device has no speech recognition assets installed for this language.',
  'error_network': 'Speech recognition needs a network connection and could not reach it.',
  'error_network_timeout': 'Speech recognition needs a network connection and could not reach it.',
  'error_audio_error': 'Could not capture audio from the microphone.',
  'error_listen_failed': 'Could not capture audio from the microphone.',
  'error_speech_recognizer_connection_interrupted': 'Recording was interrupted.',
  'error_speech_recognizer_connection_invalidated': 'Recording was interrupted.',
  'error_busy': 'The speech recogniser is busy. Try again in a moment.',
  'error_speech_recognizer_already_active':
      'The speech recogniser is busy. Try again in a moment.',
  'error_server': 'The speech recognition service could not complete the request.',
  'error_server_disconnected': 'The speech recognition service could not complete the request.',
};

class _VoiceSession {
  _VoiceSession(this.callbacks);

  final VoiceCallbacks callbacks;
  final List<String> finalized = [];
  String partial = '';
  Timer? settleTimer;

  String get transcript =>
      [...finalized, partial].where((part) => part.isNotEmpty).join(' ').trim();
}

/// Within a segment, successive partials restate the whole segment: they grow and
/// revise words in place, so they keep sharing an opening. A partial that shares
/// none belongs to a new segment, so the previous one is finished and must be
/// banked. This is the last-resort boundary detector — `speech_to_text` does not
/// surface Android's `onBeginningOfSpeech`, which RN used as the authoritative one.
bool _isSameSegment(String previous, String next) {
  if (previous.trim().isEmpty) return true;
  final before = previous.trim().toLowerCase();
  final after = next.trim().toLowerCase();
  if (after.startsWith(before) || before.startsWith(after)) return true;
  String firstWord(String value) {
    final space = value.indexOf(' ');
    return space == -1 ? value : value.substring(0, space);
  }

  return firstWord(before) == firstWord(after) && after.length >= before.length;
}

class DeviceVoiceProvider implements VoiceProvider {
  DeviceVoiceProvider(
    this._recognizer, {
    Duration stopGrace = const Duration(seconds: 4),
    TargetPlatform? platform,
  }) : _stopGrace = stopGrace,
       _platform = platform ?? defaultTargetPlatform;

  final SpeechRecognizer _recognizer;
  final Duration _stopGrace;
  final TargetPlatform _platform;

  _VoiceSession? _session;
  bool _granted = false;
  String? _language;

  @override
  bool get available => _recognizer.isAvailable;

  @override
  String? get language => _language;

  /// Sticky once granted: permission can only be revoked from system settings,
  /// which restarts the app, and the round-trip sits directly in front of the
  /// microphone starting.
  @override
  Future<bool> requestPermission() async {
    if (_granted) return true;
    try {
      _granted = await _recognizer.initialize(onStatus: _onStatus, onError: _onError);
      return _granted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start(VoiceCallbacks callbacks, {VoiceMode mode = VoiceMode.push}) async {
    if (_session != null) abort();
    final session = _VoiceSession(callbacks);
    _session = session;

    _language ??= await _resolveLanguage();
    try {
      await _recognizer.listen(
        onResult: (result) => _onResult(session, result),
        localeId: _language,
        pauseFor: kVoicePauseFor,
        listenFor: kVoiceListenFor,
      );
    } catch (error) {
      _fail(error is StateError ? error.message : 'Could not start the microphone.');
    }
  }

  @override
  void stop() {
    final session = _session;
    unawaited(_recognizer.stop());
    if (session == null) return;
    session.settleTimer = Timer(_stopGrace, () {
      if (identical(_session, session)) _settle();
    });
  }

  @override
  void abort() {
    _close();
    unawaited(_recognizer.cancel());
  }

  Future<String> _resolveLanguage() async {
    const fallback = 'en-US';
    String normalize(String value) => value.replaceAll('_', '-').toLowerCase();
    try {
      final device = normalize(await _recognizer.systemLocaleId() ?? fallback);
      final supported = await _recognizer.localeIds();
      for (final locale in supported) {
        if (normalize(locale) == device) return locale;
      }
      final language = device.split('-').first;
      for (final locale in supported) {
        if (normalize(locale).split('-').first == language) return locale;
      }
    } catch (_) {
      return fallback;
    }
    return fallback;
  }

  void _onResult(_VoiceSession session, SpeechResult result) {
    if (!identical(_session, session)) return;
    final transcript = result.transcript;

    // iOS runs ONE recognition task over the whole recording and every result —
    // `isFinal` ones included — restates everything said so far, so banking a
    // final would append the phrase twice. The one case that does bank is a task
    // restart, whose first result shares no opening with what came before.
    if (_platform == TargetPlatform.iOS) {
      if (!_isSameSegment(session.partial, transcript) && session.partial.trim().isNotEmpty) {
        session.finalized.add(session.partial.trim());
      }
      session.partial = transcript;
      session.callbacks.onPartial(session.transcript);
      return;
    }

    if (result.isFinal) {
      if (transcript.trim().isNotEmpty) session.finalized.add(transcript.trim());
      session.partial = '';
    } else {
      if (!_isSameSegment(session.partial, transcript) && session.partial.trim().isNotEmpty) {
        session.finalized.add(session.partial.trim());
      }
      session.partial = transcript;
    }
    session.callbacks.onPartial(session.transcript);
  }

  void _onStatus(String status) {
    final session = _session;
    if (session == null) return;
    if (status == kSpeechListening) {
      session.callbacks.onReady();
      return;
    }
    if (status == kSpeechDone) _settle();
  }

  void _onError(SpeechFailure failure) {
    if (_session == null) return;
    if (_silentErrors.contains(failure.errorMsg)) {
      _settle();
      return;
    }
    _fail(_errorMessages[failure.errorMsg] ?? 'Speech recognition failed.');
  }

  /// An empty string is a legitimate result meaning "nothing was said", which the
  /// caller treats as a no-op rather than an error.
  void _settle() {
    final session = _session;
    if (session == null) return;
    final text = session.transcript;
    _close();
    session.callbacks.onFinal(text);
  }

  void _fail(String message) {
    final session = _session;
    if (session == null) return;
    _close();
    session.callbacks.onError(message);
  }

  void _close() {
    _session?.settleTimer?.cancel();
    _session = null;
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/feature/chat/voice/device_provider_test.dart`
Expected: PASS, 29 tests.

- [ ] **Step 7: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 922/922 green.

```bash
git add packages/mobile/pubspec.yaml packages/mobile/pubspec.lock packages/mobile/lib/feature/chat/voice packages/mobile/test/feature/chat/voice
git commit -m "feat(mobile): add on-device dictation over speech_to_text"
```

---
### Task 15: `VoiceInputCubit`

Ports `lib/voice/useVoiceInput.ts`: permission, the recording lifecycle, the live partial, and the
gesture that distinguishes a hold from a double-tap. It knows nothing about terminals, sessions, or
how the text is eventually sent.

Two rules RN paid for:

- **Do not claim "recording" when `start()` returns.** The mic is still warming up and speech is
  dropped until `onReady` fires; claiming otherwise is what made short holds lose their first words.
- **An ordinary press starts immediately** and is classified on release. Waiting to disambiguate a
  tap from a hold would add to a warm-up that is already the sore point, and almost every press is a
  hold.

**Files:**
- Create: `packages/mobile/lib/feature/chat/voice/logic/voice_input_cubit.dart`
- Create: `packages/mobile/lib/feature/chat/voice/logic/voice_input_state.dart`
- Test: `packages/mobile/test/feature/chat/voice/voice_input_cubit_test.dart`

**Interfaces:**
- Consumes: `VoiceProvider`, `VoiceCallbacks`, `VoiceState`, `VoiceMode`.
- Produces: `VoiceInputCubit(VoiceProvider provider, {required void Function(String text)
  onTranscript, Duration tapThreshold, Duration doubleTapWindow, Duration restartDelay})` with fields
  `phase` (`VoiceState`), `mode` (`VoiceMode`), `partial`, `error`, and methods `pressIn()`,
  `pressOut()`, `onAppBackgrounded()`; states `VoiceInputInitialState`, `VoiceInputReadyState(int
  revision)`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/chat/voice/voice_input_cubit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

class _FakeProvider implements VoiceProvider {
  _FakeProvider({this.availableValue = true, this.permission = true});

  bool availableValue;
  bool permission;
  int starts = 0;
  int stops = 0;
  int aborts = 0;
  VoiceMode? lastMode;
  VoiceCallbacks? callbacks;

  @override
  bool get available => availableValue;

  @override
  String? get language => 'en-US';

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<void> start(VoiceCallbacks callbacks, {VoiceMode mode = VoiceMode.push}) async {
    starts++;
    lastMode = mode;
    this.callbacks = callbacks;
  }

  @override
  void stop() => stops++;

  @override
  void abort() => aborts++;
}

const Duration tapThreshold = Duration(milliseconds: 40);
const Duration doubleTapWindow = Duration(milliseconds: 60);
const Duration restartDelay = Duration(milliseconds: 10);

void main() {
  late _FakeProvider provider;
  late List<String> transcripts;

  setUp(() {
    provider = _FakeProvider();
    transcripts = [];
  });

  VoiceInputCubit build() => VoiceInputCubit(
    provider,
    onTranscript: transcripts.add,
    tapThreshold: tapThreshold,
    doubleTapWindow: doubleTapWindow,
    restartDelay: restartDelay,
  );

  test('reports unavailable when the device has no recogniser', () async {
    provider.availableValue = false;
    final cubit = build();

    expect(cubit.phase, VoiceState.unavailable);
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    expect(provider.starts, 0);
    await cubit.close();
  });

  test('a denied permission moves to denied and explains itself', () async {
    provider.permission = false;
    final cubit = build();

    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.phase, VoiceState.denied);
    expect(cubit.error, contains('Settings'));
    await cubit.close();
  });

  test('a hold starts the recogniser and only claims recording once it is ready', () async {
    final cubit = build();

    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.phase, VoiceState.starting);
    expect(provider.lastMode, VoiceMode.push);

    provider.callbacks!.onReady();
    expect(cubit.phase, VoiceState.recording);
    await cubit.close();
  });

  test('the live partial reaches the cubit and clears when the phrase lands', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    provider.callbacks!.onReady();

    provider.callbacks!.onPartial('ship the release');
    expect(cubit.partial, 'ship the release');

    provider.callbacks!.onFinal('ship the release');
    expect(transcripts, ['ship the release']);
    expect(cubit.partial, isEmpty);
    expect(cubit.phase, VoiceState.idle);
    await cubit.close();
  });

  test('an empty transcript is a no-op, not a send', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    provider.callbacks!.onReady();

    provider.callbacks!.onFinal('');

    expect(transcripts, isEmpty);
    expect(cubit.phase, VoiceState.idle);
    await cubit.close();
  });

  test('an error surfaces and returns to idle', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    provider.callbacks!.onReady();

    provider.callbacks!.onError('Could not capture audio from the microphone.');

    expect(cubit.error, 'Could not capture audio from the microphone.');
    expect(cubit.phase, VoiceState.idle);
    await cubit.close();
  });

  test('releasing before the recogniser is live aborts instead of finalising', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);

    await Future<void>.delayed(tapThreshold * 2);
    cubit.pressOut();

    expect(provider.aborts, 1);
    expect(provider.stops, 0);
    expect(cubit.phase, VoiceState.idle);
    await cubit.close();
  });

  test('a hold longer than the threshold stops and keeps the transcript', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    provider.callbacks!.onReady();

    await Future<void>.delayed(tapThreshold * 2);
    cubit.pressOut();

    expect(provider.stops, 1);
    expect(cubit.phase, VoiceState.recording);
    await cubit.close();
  });

  test('a tap throws away its sliver of audio and opens the double-tap window', () async {
    final cubit = build();

    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    cubit.pressOut();

    expect(provider.aborts, 1);
    expect(cubit.phase, VoiceState.idle);
    await cubit.close();
  });

  test('a second tap latches, and the latched recording ignores the finger', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    cubit.pressOut();

    cubit.pressIn();
    await Future<void>.delayed(restartDelay * 3);

    expect(cubit.mode, VoiceMode.latched);
    expect(provider.lastMode, VoiceMode.latched);

    cubit.pressOut();
    expect(provider.stops, 0);
    await cubit.close();
  });

  test('pressing again while latched stops the recording', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    cubit.pressOut();
    cubit.pressIn();
    await Future<void>.delayed(restartDelay * 3);
    provider.callbacks!.onReady();

    cubit.pressIn();

    expect(provider.stops, 1);
    await cubit.close();
  });

  test('backgrounding the app closes the microphone', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    provider.callbacks!.onReady();

    cubit.onAppBackgrounded();

    expect(provider.aborts, 1);
    expect(cubit.phase, VoiceState.idle);
    expect(cubit.mode, VoiceMode.push);
    await cubit.close();
  });
}
```

That is **12 tests**.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/voice/voice_input_cubit_test.dart`
Expected: FAIL — `voice_input_cubit.dart` does not exist.

- [ ] **Step 3: Write the state**

Create `packages/mobile/lib/feature/chat/voice/logic/voice_input_state.dart`:

```dart
part of 'voice_input_cubit.dart';

sealed class VoiceInputState extends Equatable {
  const VoiceInputState();

  @override
  List<Object?> get props => [];
}

final class VoiceInputInitialState extends VoiceInputState {
  const VoiceInputInitialState();
}

final class VoiceInputReadyState extends VoiceInputState {
  const VoiceInputReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
```

- [ ] **Step 4: Write the cubit**

Create `packages/mobile/lib/feature/chat/voice/logic/voice_input_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

part 'voice_input_state.dart';

class VoiceInputCubit extends Cubit<VoiceInputState> {
  factory VoiceInputCubit(
    VoiceProvider provider, {
    required void Function(String text) onTranscript,
    Duration tapThreshold = const Duration(milliseconds: 250),
    Duration doubleTapWindow = const Duration(milliseconds: 300),
    Duration restartDelay = const Duration(milliseconds: 120),
  }) => VoiceInputCubit._(
    provider,
    onTranscript: onTranscript,
    tapThreshold: tapThreshold,
    doubleTapWindow: doubleTapWindow,
    restartDelay: restartDelay,
  );

  VoiceInputCubit._(
    this._provider, {
    required this.onTranscript,
    required Duration tapThreshold,
    required Duration doubleTapWindow,
    required Duration restartDelay,
  }) : _tapThreshold = tapThreshold,
       _doubleTapWindow = doubleTapWindow,
       _restartDelay = restartDelay,
       super(const VoiceInputInitialState()) {
    if (!_provider.available) phase = VoiceState.unavailable;
  }

  final VoiceProvider _provider;
  final void Function(String text) onTranscript;
  final Duration _tapThreshold;
  final Duration _doubleTapWindow;
  final Duration _restartDelay;

  VoiceState phase = VoiceState.idle;
  VoiceMode mode = VoiceMode.push;
  String partial = '';
  String? error;

  DateTime _pressStart = DateTime.now();
  Timer? _tapWindow;
  Timer? _restart;
  bool _startedLatched = false;
  int _revision = 0;

  void _emit() {
    if (isClosed) return;
    emit(VoiceInputReadyState(++_revision));
  }

  void _setPhase(VoiceState next) {
    phase = next;
    _emit();
  }

  void pressIn() {
    // While latched the key is a stop button: no finger is holding anything, so
    // a press means "I'm done talking".
    if (mode == VoiceMode.latched && phase != VoiceState.idle) {
      _startedLatched = false;
      _finish();
      return;
    }

    // Second tap of a double-tap: go hands-free. The tap's own recording was
    // aborted a moment ago, so give the recogniser time to tear down first.
    if (_tapWindow != null) {
      _tapWindow!.cancel();
      _tapWindow = null;
      _startedLatched = true;
      _restart = Timer(_restartDelay, () => _begin(VoiceMode.latched));
      return;
    }

    _startedLatched = false;
    _pressStart = DateTime.now();
    _begin(VoiceMode.push);
  }

  void pressOut() {
    if (_startedLatched) return;
    if (mode == VoiceMode.latched) return;

    if (DateTime.now().difference(_pressStart) < _tapThreshold) {
      _provider.abort();
      partial = '';
      mode = VoiceMode.push;
      _setPhase(VoiceState.idle);
      _tapWindow = Timer(_doubleTapWindow, () => _tapWindow = null);
      return;
    }

    _finish();
  }

  /// iOS interrupts the audio session on background anyway, and leaving the UI
  /// stuck in `recording` is worse than dropping a phrase the user walked away
  /// from.
  void onAppBackgrounded() {
    if (phase != VoiceState.recording && phase != VoiceState.starting) return;
    _provider.abort();
    mode = VoiceMode.push;
    partial = '';
    _setPhase(VoiceState.idle);
  }

  void _begin(VoiceMode next) {
    if (phase == VoiceState.unavailable ||
        phase == VoiceState.starting ||
        phase == VoiceState.recording) {
      return;
    }
    mode = next;
    error = null;
    partial = '';
    _setPhase(VoiceState.starting);
    unawaited(_run(next));
  }

  Future<void> _run(VoiceMode next) async {
    final granted = await _provider.requestPermission();
    if (isClosed) return;
    if (!granted) {
      error = 'Microphone access is off. Enable it in Settings to dictate.';
      _setPhase(VoiceState.denied);
      return;
    }
    // The finger may have lifted while the permission dialog was up.
    if (phase != VoiceState.starting) return;

    await _provider.start(
      VoiceCallbacks(
        onReady: () {
          if (isClosed || phase != VoiceState.starting) return;
          _setPhase(VoiceState.recording);
        },
        onPartial: (text) {
          if (isClosed) return;
          partial = text;
          _emit();
        },
        onFinal: (text) {
          mode = VoiceMode.push;
          if (isClosed) return;
          partial = '';
          _setPhase(VoiceState.idle);
          if (text.isNotEmpty) onTranscript(text);
        },
        onError: (message) {
          mode = VoiceMode.push;
          if (isClosed) return;
          partial = '';
          error = message;
          _setPhase(VoiceState.idle);
        },
      ),
      mode: next,
    );
  }

  /// Stays in `recording` until the provider settles, so the UI does not flash
  /// idle while the final result is still in flight.
  void _finish() {
    if (phase == VoiceState.starting) {
      _provider.abort();
      partial = '';
      _setPhase(VoiceState.idle);
      return;
    }
    if (phase != VoiceState.recording) return;
    _provider.stop();
  }

  @override
  Future<void> close() {
    _tapWindow?.cancel();
    _restart?.cancel();
    mode = VoiceMode.push;
    _provider.abort();
    return super.close();
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/feature/chat/voice/voice_input_cubit_test.dart`
Expected: PASS, 12 tests.

- [ ] **Step 6: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 934/934 green.

```bash
git add packages/mobile/lib/feature/chat/voice packages/mobile/test/feature/chat/voice
git commit -m "feat(mobile): add the voice input cubit"
```

---
### Task 16: The mic key, the voice strip and both composers

Ports `lib/voice/MicKey.tsx`, the voice strip in `lib/chat/ChatComposer.tsx:202` and the terminal
dock's mic in `lib/session/Composer.tsx:90`. The key is sized to the send button and sits beside it —
dictation is a primary way to talk to an agent from a phone. It is tonal rather than solid, because
two identical solid-blue buttons side by side have no hierarchy; it only goes solid red while it is
actually recording, which is the one moment it should outrank everything on screen. It is **rendered
even when no recogniser exists** — returning nothing there reflows the whole row.

**Files:**
- Create: `packages/mobile/lib/feature/chat/voice/ui/mic_key.dart`
- Create: `packages/mobile/lib/feature/chat/voice/ui/voice_strip.dart`
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Modify: `packages/mobile/ios/Runner/Info.plist`
- Modify: `packages/mobile/android/app/src/main/AndroidManifest.xml`
- Test: `packages/mobile/test/feature/chat/voice/mic_key_test.dart`

**Interfaces:**
- Consumes: `VoiceInputCubit`, `VoiceState`, `VoiceMode`, `sl`.
- Produces: `MicKey`, `VoiceStrip`, `kMicSize`; a `VoiceProvider` lazy singleton and a
  `VoiceInputCubit` factory-param registration keyed on the transcript callback.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/chat/voice/mic_key_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/ui/mic_key.dart';
import 'package:operator_mobile/feature/chat/voice/ui/voice_strip.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

class _FakeProvider implements VoiceProvider {
  _FakeProvider({this.availableValue = true});

  final bool availableValue;
  VoiceCallbacks? callbacks;

  @override
  bool get available => availableValue;

  @override
  String? get language => 'en-US';

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start(VoiceCallbacks callbacks, {VoiceMode mode = VoiceMode.push}) async =>
      this.callbacks = callbacks;

  @override
  void stop() {}

  @override
  void abort() {}
}

void main() {
  late _FakeProvider provider;

  Future<VoiceInputCubit> pump(
    WidgetTester tester, {
    bool available = true,
    List<String>? transcripts,
  }) async {
    provider = _FakeProvider(availableValue: available);
    final cubit = VoiceInputCubit(
      provider,
      onTranscript: (text) => transcripts?.add(text),
      tapThreshold: const Duration(milliseconds: 40),
    );
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<VoiceInputCubit>.value(
                value: cubit,
                child: const Column(children: [VoiceStrip(), MicKey()]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(cubit.close);
    return cubit;
  }

  testWidgets('stays in the row but is inert when dictation is unavailable', (tester) async {
    await pump(tester, available: false);

    expect(find.byType(MicKey), findsOneWidget);
    expect(find.byIcon(Icons.mic_off), findsOneWidget);
    expect(find.bySemanticsLabel('Dictation unavailable on this device'), findsOneWidget);
  });

  testWidgets('holding the key starts a recording and the strip says to keep holding', (
    tester,
  ) async {
    await pump(tester);

    await tester.press(find.byType(MicKey));
    await tester.pump();
    await tester.pump();

    expect(find.text('Keep holding…'), findsOneWidget);
  });

  testWidgets('once recording, the strip shows the live partial and the transcript lands', (
    tester,
  ) async {
    final transcripts = <String>[];
    await pump(tester, transcripts: transcripts);
    await tester.press(find.byType(MicKey));
    await tester.pump();
    await tester.pump();

    provider.callbacks!.onReady();
    provider.callbacks!.onPartial('ship the release');
    await tester.pump();
    expect(find.text('ship the release'), findsOneWidget);

    provider.callbacks!.onFinal('ship the release');
    await tester.pump();
    expect(transcripts, ['ship the release']);
    expect(find.text('ship the release'), findsNothing);
  });

  testWidgets('the strip takes no room while idle', (tester) async {
    await pump(tester);

    expect(find.byType(VoiceStrip), findsOneWidget);
    expect(find.text('Listening…'), findsNothing);
    expect(find.text('Keep holding…'), findsNothing);
  });

  testWidgets('a voice error is shown on the strip', (tester) async {
    await pump(tester);
    await tester.press(find.byType(MicKey));
    await tester.pump();
    await tester.pump();

    provider.callbacks!.onError('Could not capture audio from the microphone.');
    await tester.pump();

    expect(find.text('Could not capture audio from the microphone.'), findsOneWidget);
  });

  testWidgets('a double tap latches, and the key names the stop gesture', (tester) async {
    final cubit = await pump(tester);

    await tester.tap(find.byType(MicKey));
    await tester.pump();
    await tester.press(find.byType(MicKey));
    await tester.pump(const Duration(milliseconds: 200));
    provider.callbacks!.onReady();
    await tester.pump();

    expect(cubit.mode, VoiceMode.latched);
    expect(find.bySemanticsLabel('Stop dictating'), findsOneWidget);
  });

  test('appending a transcript respects what is already typed', () {
    expect(appendTranscript('', 'ship it'), 'ship it');
    expect(appendTranscript('please', 'ship it'), 'please ship it');
    expect(appendTranscript('please ', 'ship it'), 'please ship it');
  });
}
```

That is **7 tests**.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/voice/mic_key_test.dart`
Expected: FAIL — `mic_key.dart` and `voice_strip.dart` do not exist.

- [ ] **Step 3: Write the mic key**

Create `packages/mobile/lib/feature/chat/voice/ui/mic_key.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

/// Matches the send button so the two controls are the same size.
const double kMicSize = 40;

String appendTranscript(String existing, String spoken) =>
    existing.trim().isEmpty ? spoken : '${existing.trimRight()} $spoken';

class MicKey extends StatefulWidget {
  const MicKey({super.key});

  @override
  State<MicKey> createState() => _MicKeyState();
}

class _MicKeyState extends State<MicKey> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Deferred to after the frame: starting or stopping a controller from inside
  /// build is exactly the layout-callback trap M4 hit.
  void _syncPulse(bool live) {
    if (live == _pulse.isAnimating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || live == _pulse.isAnimating) return;
      if (live) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse
          ..stop()
          ..value = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<VoiceInputCubit, VoiceInputState>(
      buildWhen: (previous, current) => current is VoiceInputReadyState,
      builder: (context, state) {
        final cubit = context.read<VoiceInputCubit>();
        final live = cubit.phase == VoiceState.recording || cubit.phase == VoiceState.starting;
        final latched = live && cubit.mode == VoiceMode.latched;
        final denied = cubit.phase == VoiceState.denied;
        final unavailable = cubit.phase == VoiceState.unavailable;
        final disabled = denied || unavailable;
        _syncPulse(live);

        final fill = live
            ? skin.red
            : denied
            ? skin.tintRed
            : unavailable
            ? skin.bgElevated
            : skin.tintBlue;
        final ink = live
            ? skin.textPrimary
            : denied
            ? skin.red
            : unavailable
            ? skin.textFaint
            : skin.blue;

        return SizedBox(
          width: kMicSize,
          height: kMicSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (live)
                FadeTransition(
                  opacity: Tween<double>(begin: 0.45, end: 0).animate(_pulse),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1, end: 1.45).animate(_pulse),
                    child: Container(
                      width: kMicSize,
                      height: kMicSize,
                      decoration: BoxDecoration(
                        color: skin.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              Semantics(
                button: true,
                enabled: !disabled,
                label: unavailable
                    ? 'Dictation unavailable on this device'
                    : latched
                    ? 'Stop dictating'
                    : 'Hold to dictate, or double-tap for hands-free',
                child: GestureDetector(
                  onTapDown: disabled ? null : (_) => cubit.pressIn(),
                  onTapUp: disabled ? null : (_) => cubit.pressOut(),
                  onTapCancel: disabled ? null : cubit.pressOut,
                  child: Container(
                    width: kMicSize,
                    height: kMicSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(12),
                      border: latched
                          ? Border.all(color: skin.textPrimary, width: 2)
                          : unavailable
                          ? Border.all(color: skin.borderSubtle)
                          : null,
                    ),
                    child: Icon(
                      disabled ? Icons.mic_off : Icons.mic,
                      size: 18,
                      color: ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Write the strip**

Create `packages/mobile/lib/feature/chat/voice/ui/voice_strip.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

class VoiceStrip extends StatelessWidget {
  const VoiceStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<VoiceInputCubit, VoiceInputState>(
      buildWhen: (previous, current) => current is VoiceInputReadyState,
      builder: (context, state) {
        final cubit = context.read<VoiceInputCubit>();
        final live = cubit.phase == VoiceState.starting || cubit.phase == VoiceState.recording;
        final error = cubit.error;
        if (!live && error == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(Icons.mic, size: 12, color: skin.red),
              const HorizontalSpace(6),
              Expanded(
                child: AppText(
                  live
                      ? (cubit.partial.isNotEmpty
                            ? cubit.partial
                            : cubit.phase == VoiceState.starting
                            ? 'Keep holding…'
                            : 'Listening…')
                      : error!,
                  style: AppTextStyle.style12Regular.copyWith(
                    color: live ? skin.textSecondary : skin.red,
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Register the provider and the cubit**

In `service_locator.dart`, add `_voiceSetup();` to `init()` and:

```dart
  static void _voiceSetup() {
    sl.registerLazySingleton<VoiceProvider>(
      () => DeviceVoiceProvider(SpeechToTextRecognizer()),
    );
    sl.registerFactoryParam<VoiceInputCubit, void Function(String), void>(
      (onTranscript, _) => VoiceInputCubit(sl<VoiceProvider>(), onTranscript: onTranscript),
    );
  }
```

The provider is a process-wide singleton for the same reason RN's is: it caches the permission grant
and the recogniser warms up once, both of which are wasted if a new provider appears every time a
composer mounts.

- [ ] **Step 6: Wire the chat composer**

In `chat_composer.dart`'s state class, add the cubit, the lifecycle listener and the append:

```dart
  late final VoiceInputCubit _voice = sl<VoiceInputCubit>(param1: _appendTranscript);
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onHide: _voice.onAppBackgrounded,
    onPause: _voice.onAppBackgrounded,
  );

  void _appendTranscript(String spoken) {
    _controller.text = appendTranscript(_controller.text, spoken);
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
  }
```

`initState` touches `_lifecycle` so it is created, and `dispose` runs `_lifecycle.dispose();` and
`unawaited(_voice.close());` before `super.dispose()`.

The returned `Container` becomes `BlocProvider<VoiceInputCubit>.value(value: _voice, child: Container(...))`,
the `VoiceStrip` goes at the top of the dock's `Column` (above the attachment strip, where RN puts
it), and the `MicKey` goes immediately before the send/stop button:

```dart
                      const Spacer(),
                      const MicKey(),
                      const HorizontalSpace(7),
                      if (_turnRunning &&
```

- [ ] **Step 7: Wire the terminal composer**

`TerminalComposer` becomes a `StatefulWidget` for the same reason — it owns a cubit that must be
closed:

```dart
class TerminalComposer extends StatefulWidget {
  const TerminalComposer({super.key});

  @override
  State<TerminalComposer> createState() => _TerminalComposerState();
}

class _TerminalComposerState extends State<TerminalComposer> {
  late final VoiceInputCubit _voice = sl<VoiceInputCubit>(param1: _appendTranscript);
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onHide: _voice.onAppBackgrounded,
    onPause: _voice.onAppBackgrounded,
  );

  void _appendTranscript(String spoken) {
    final composer = context.read<TerminalCubit>().composer;
    composer.text = appendTranscript(composer.text, spoken);
    composer.selection = TextSelection.collapsed(offset: composer.text.length);
  }

  @override
  void initState() {
    super.initState();
    _lifecycle.hashCode;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_voice.close());
    super.dispose();
  }
```

and its `build` returns
`BlocProvider<VoiceInputCubit>.value(value: _voice, child: Column(children: [const VoiceStrip(), <the existing Padding>]))`,
with `const MicKey()` and a `HorizontalSpace(7)` inserted before the Send button in the existing
`Row`.

- [ ] **Step 8: Declare the native permissions**

In `ios/Runner/Info.plist`, beside the existing usage strings:

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>Operator uses the microphone so you can dictate prompts to an agent.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Operator transcribes your speech into prompts for an agent.</string>
```

In `android/app/src/main/AndroidManifest.xml`, beside the existing camera permission and inside the
existing `<queries>` block:

```xml
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
```
```xml
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `flutter test test/feature/chat test/feature/terminal`
Expected: PASS — including the existing composer tests, which must not regress.

- [ ] **Step 10: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 941/941 green.

```bash
git add packages/mobile/lib packages/mobile/test packages/mobile/ios packages/mobile/android
git commit -m "feat(mobile): put the mic key and voice strip in both composers"
```

---
### Task 17: The preview wire shapes and their rules

Ports `getPreview` and `mobileReachablePreviewURL` (`lib/api.ts:366–402`). Two rules carry field
experience and get their own tests:

- **Build the URL from our own base, never the daemon's `previewUrl`,** which hardcodes `http://` and
  its own request host and breaks over a TLS tunnel (`tailscale serve`).
- **A loopback dev-server URL is rewritten to the phone-reachable host, and never receives the
  Operator password.** That is what `authenticated` is for: only the daemon's own
  `/preview/files/...` route is behind Bearer auth.

**Files:**
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Create: `packages/mobile/lib/feature/preview/logic/preview_url.dart`
- Create: `packages/mobile/lib/feature/preview/data/model/preview_model.dart`
- Create: `packages/mobile/lib/feature/preview/data/data_source/preview_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/preview/data/repository/preview_repository.dart`
- Test: `packages/mobile/test/core/api/end_points_test.dart` (modify)
- Test: `packages/mobile/test/feature/preview/logic/preview_url_test.dart`
- Test: `packages/mobile/test/feature/preview/data/preview_data_test.dart`

**Interfaces:**
- Consumes: `ApiConsumer`, `GlobalResponse`, `NetworkStatus`, `ServerConfigStore`, `ServerConfig`.
- Produces:
  - `EndPoints.sessionPreview(String sessionId)`, `EndPoints.sessionPreviewFile(String sessionId, String entry)`.
  - `Uri? mobileReachablePreviewUrl(String? raw, String operatorHost)`,
    `bool previewWorthShowing(String? entry)`, `String normalizePreviewHost(String host)`.
  - `PreviewEntryModel(entry)` and `PreviewModel(entry, url, authenticated)`.
  - `PreviewRemoteDataSource` / `Imp` with `Future<GlobalResponse<PreviewEntryModel>> getPreview(String sessionId)`.
  - `PreviewRepository` / `Imp` with `FutureResult<PreviewModel?> getPreview(String sessionId, {String? previewUrl})`.

- [ ] **Step 1: Write the failing tests**

Append to `packages/mobile/test/core/api/end_points_test.dart`:

```dart
  test('builds the preview paths, escaping every entry segment', () {
    expect(EndPoints.sessionPreview('s-1'), '/api/v1/sessions/s-1/preview');
    expect(
      EndPoints.sessionPreviewFile('s-1', 'dist/my page/index.html'),
      '/api/v1/sessions/s-1/preview/files/dist/my%20page/index.html',
    );
  });
```

That is **1 test**.

Create `packages/mobile/test/feature/preview/logic/preview_url_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/preview/logic/preview_url.dart';

void main() {
  group('mobileReachablePreviewUrl', () {
    test('rewrites a loopback host to the daemon host the phone can reach', () {
      expect(
        mobileReachablePreviewUrl('http://localhost:5173/', '10.0.0.5')?.toString(),
        'http://10.0.0.5:5173/',
      );
      expect(
        mobileReachablePreviewUrl('http://127.0.0.1:3000/app', '10.0.0.5')?.toString(),
        'http://10.0.0.5:3000/app',
      );
    });

    test('brackets an IPv6 daemon host', () {
      expect(
        mobileReachablePreviewUrl('http://localhost:5173/', 'fd7a::1')?.host,
        '[fd7a::1]',
      );
    });

    test('leaves a already-reachable host alone', () {
      expect(
        mobileReachablePreviewUrl('https://preview.example.com/x', '10.0.0.5')?.toString(),
        'https://preview.example.com/x',
      );
    });

    test('refuses anything that is not http or https', () {
      expect(mobileReachablePreviewUrl('file:///etc/passwd', '10.0.0.5'), isNull);
      expect(mobileReachablePreviewUrl('javascript:alert(1)', '10.0.0.5'), isNull);
    });

    test('returns nothing for a missing, empty or unparseable URL', () {
      expect(mobileReachablePreviewUrl(null, '10.0.0.5'), isNull);
      expect(mobileReachablePreviewUrl('', '10.0.0.5'), isNull);
      expect(mobileReachablePreviewUrl('http://localhost:5173/', ''), isNull);
    });
  });

  group('previewWorthShowing', () {
    // The detector's markdown fallback matches a repo README on a fresh
    // checkout, so the globe's dot must not treat that as "the agent made
    // something to look at".
    test('ignores a bare repo README', () {
      expect(previewWorthShowing('README.md'), isFalse);
      expect(previewWorthShowing('docs/readme.markdown'), isFalse);
    });

    test('accepts anything the agent actually produced', () {
      expect(previewWorthShowing('dist/index.html'), isTrue);
      expect(previewWorthShowing('plan.md'), isTrue);
    });

    test('treats a missing entry as nothing to show', () {
      expect(previewWorthShowing(null), isFalse);
      expect(previewWorthShowing('   '), isFalse);
    });
  });

  test('normalizePreviewHost strips a pasted scheme and trailing slashes', () {
    expect(normalizePreviewHost('  http://10.0.0.5/  '), '10.0.0.5');
    expect(normalizePreviewHost('10.0.0.5'), '10.0.0.5');
  });
}
```

That is **9 tests**.

Create `packages/mobile/test/feature/preview/data/preview_data_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/preview/data/data_source/preview_remote_data_source.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

class _MockDataSource extends Mock implements PreviewRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

class _MockConfigStore extends Mock implements ServerConfigStore {}

Response<dynamic> _response(Object? data) =>
    Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: data);

void main() {
  group('data source', () {
    test('reads the entry the detector found', () async {
      final apiConsumer = _MockApiConsumer();
      when(() => apiConsumer.get(any())).thenAnswer(
        (_) async => _response({'entry': ' dist/index.html '}),
      );

      final entry = (await PreviewRemoteDataSourceImp(apiConsumer).getPreview('s-1')).data!;

      expect(entry.entry, 'dist/index.html');
      verify(() => apiConsumer.get(EndPoints.sessionPreview('s-1'))).called(1);
    });

    test('treats a missing entry as an empty one', () async {
      final apiConsumer = _MockApiConsumer();
      when(() => apiConsumer.get(any())).thenAnswer((_) async => _response(const {}));

      expect((await PreviewRemoteDataSourceImp(apiConsumer).getPreview('s-1')).data!.entry, isEmpty);
    });
  });

  group('repository', () {
    late _MockDataSource dataSource;
    late _MockNetworkStatus network;
    late _MockConfigStore configStore;
    late PreviewRepository repository;

    setUp(() {
      dataSource = _MockDataSource();
      network = _MockNetworkStatus();
      configStore = _MockConfigStore();
      repository = PreviewRepositoryImp(dataSource, network, configStore);
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(() => configStore.current).thenReturn(
        const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12'),
      );
    });

    test('builds the URL from our own base, not the daemon report', () async {
      when(() => dataSource.getPreview(any())).thenAnswer(
        (_) async => const GlobalResponse(data: PreviewEntryModel(entry: 'dist/index.html')),
      );

      final result = await repository.getPreview('s-1');

      late PreviewModel? preview;
      result.when(onSuccess: (value) => preview = value, onFailure: (_) {});
      expect(preview!.url, 'http://10.0.0.5:3011/api/v1/sessions/s-1/preview/files/dist/index.html');
      expect(preview!.authenticated, isTrue);
    });

    test('honours the TLS toggle when building the base', () async {
      when(() => configStore.current).thenReturn(
        const ServerConfig(host: 'box.ts.net', httpPort: '443', secure: true, password: 'p'),
      );
      when(() => dataSource.getPreview(any())).thenAnswer(
        (_) async => const GlobalResponse(data: PreviewEntryModel(entry: 'index.html')),
      );

      final result = await repository.getPreview('s-1');

      late PreviewModel? preview;
      result.when(onSuccess: (value) => preview = value, onFailure: (_) {});
      expect(preview!.url, startsWith('https://box.ts.net:443/'));
    });

    test('falls back to a phone-reachable dev server without forwarding auth', () async {
      when(() => dataSource.getPreview(any())).thenAnswer(
        (_) async => const GlobalResponse(data: PreviewEntryModel(entry: '')),
      );

      final result = await repository.getPreview('s-1', previewUrl: 'http://localhost:5173/');

      late PreviewModel? preview;
      result.when(onSuccess: (value) => preview = value, onFailure: (_) {});
      expect(preview!.url, 'http://10.0.0.5:5173/');
      expect(preview!.authenticated, isFalse);
      expect(preview!.entry, '10.0.0.5');
    });

    test('reports no preview at all when there is neither an entry nor a dev server', () async {
      when(() => dataSource.getPreview(any())).thenAnswer(
        (_) async => const GlobalResponse(data: PreviewEntryModel(entry: '')),
      );

      final result = await repository.getPreview('s-1');

      late PreviewModel? preview;
      result.when(onSuccess: (value) => preview = value, onFailure: (_) {});
      expect(preview, isNull);
    });

    test('short-circuits to a failure when offline', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      expect((await repository.getPreview('s-1')).isFailure, isTrue);
      verifyNever(() => dataSource.getPreview(any()));
    });
  });
}
```

That is **7 tests**. Task 17 adds **17 tests** in total.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/api/end_points_test.dart test/feature/preview`
Expected: FAIL — the preview files do not exist.

- [ ] **Step 3: Add the endpoints**

In `end_points.dart`:

```dart
  static String sessionPreview(String sessionId) => '${_session(sessionId)}/preview';

  static String sessionPreviewFile(String sessionId, String entry) =>
      '${sessionPreview(sessionId)}/files/'
      '${entry.split('/').map(Uri.encodeComponent).join('/')}';
```

- [ ] **Step 4: Write the URL rules**

Create `packages/mobile/lib/feature/preview/logic/preview_url.dart`:

```dart
const Set<String> _loopbackHosts = {'localhost', '127.0.0.1', '::1', '[::1]'};

final RegExp _scheme = RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false);
final RegExp _readme = RegExp(r'^readme\.(md|markdown)$', caseSensitive: false);

String normalizePreviewHost(String host) =>
    host.trim().replaceFirst(_scheme, '').replaceAll(RegExp(r'/+$'), '');

/// Rewrites a host-loopback dev-server preview so the phone can reach it, without
/// ever forwarding Operator's connection password to it.
Uri? mobileReachablePreviewUrl(String? raw, String operatorHost) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = Uri.tryParse(raw.trim());
  if (parsed == null) return null;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
  if (!_loopbackHosts.contains(parsed.host)) return parsed;

  final host = normalizePreviewHost(operatorHost);
  if (host.isEmpty) return null;
  return parsed.replace(
    host: host.contains(':') && !host.startsWith('[') ? '[$host]' : host,
  );
}

/// What counts as a live preview: anything the daemon surfaces EXCEPT a repo
/// README, which the detector's markdown fallback always matches on a fresh
/// checkout. Filtering it out keeps the globe's dot meaningful.
bool previewWorthShowing(String? entry) {
  final trimmed = entry?.trim() ?? '';
  if (trimmed.isEmpty) return false;
  return !_readme.hasMatch(trimmed.split('/').last);
}
```

- [ ] **Step 5: Write the models**

Create `packages/mobile/lib/feature/preview/data/model/preview_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class PreviewEntryModel extends Equatable {
  const PreviewEntryModel({this.entry});

  final String? entry;

  factory PreviewEntryModel.fromJson(Map<String, dynamic> json) =>
      PreviewEntryModel(entry: (json['entry'] as String?)?.trim() ?? '');

  @override
  List<Object?> get props => [entry];
}

class PreviewModel extends Equatable {
  const PreviewModel({required this.entry, required this.url, required this.authenticated});

  final String entry;
  final String url;

  /// False for an external dev server, which must never receive the Operator
  /// Bearer token.
  final bool authenticated;

  @override
  List<Object?> get props => [entry, url, authenticated];
}
```

- [ ] **Step 6: Write the data source and repository**

Create `packages/mobile/lib/feature/preview/data/data_source/preview_remote_data_source.dart`:

```dart
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';

abstract class PreviewRemoteDataSource {
  Future<GlobalResponse<PreviewEntryModel>> getPreview(String sessionId);
}

class PreviewRemoteDataSourceImp implements PreviewRemoteDataSource {
  PreviewRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<PreviewEntryModel>> getPreview(String sessionId) async {
    final response = await _apiConsumer.get(EndPoints.sessionPreview(sessionId));
    return GlobalResponse<PreviewEntryModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: PreviewEntryModel.fromJson,
    );
  }
}
```

Create `packages/mobile/lib/feature/preview/data/repository/preview_repository.dart`:

```dart
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/preview/data/data_source/preview_remote_data_source.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/logic/preview_url.dart';

abstract class PreviewRepository {
  FutureResult<PreviewModel?> getPreview(String sessionId, {String? previewUrl});
}

class PreviewRepositoryImp implements PreviewRepository {
  PreviewRepositoryImp(this._remoteDataSource, this._network, this._configStore);

  final PreviewRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;
  final ServerConfigStore _configStore;

  @override
  FutureResult<PreviewModel?> getPreview(String sessionId, {String? previewUrl}) async {
    if (!await _network.isConnected) return Result.failure(ServerFailure.noNetwork());
    try {
      final response = await _remoteDataSource.getPreview(sessionId);
      final entry = response.data?.entry ?? '';
      final config = _configStore.current;

      if (entry.isNotEmpty && config != null) {
        return Result.success(
          PreviewModel(
            entry: entry,
            url: '${config.httpBase}${EndPoints.sessionPreviewFile(sessionId, entry)}',
            authenticated: true,
          ),
        );
      }

      final external = mobileReachablePreviewUrl(previewUrl, config?.host ?? '');
      if (external == null) return Result.success(null);
      return Result.success(
        PreviewModel(entry: external.host, url: external.toString(), authenticated: false),
      );
    } on Failure catch (error) {
      return Result.failure(error);
    }
  }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/core/api/end_points_test.dart test/feature/preview`
Expected: PASS, 17 tests.

- [ ] **Step 8: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 958/958 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the session preview data layer"
```

---
### Task 18: `PreviewCubit`

Ports the poll in `TerminalSessionScreen.tsx:756–780` and `app/preview/[id].tsx:34`. It keeps the
detector's answer current while a session is open, on a 5-second tick, and answers the one question
the globe asks: is there something here worth showing.

The overlay is deliberately **never** auto-opened: the detector falls back to any previewable file, so
popping it open would steal the screen with an unbuilt page.

**Files:**
- Create: `packages/mobile/lib/feature/preview/presentation/preview_screen/logic/preview_cubit.dart`
- Create: `packages/mobile/lib/feature/preview/presentation/preview_screen/logic/preview_state.dart`
- Test: `packages/mobile/test/feature/preview/presentation/preview_screen/logic/preview_cubit_test.dart`

**Interfaces:**
- Consumes: `PreviewRepository`, `PreviewModel`, `previewWorthShowing`, `Result`.
- Produces: `PreviewCubit(PreviewRepository repository, String sessionId, {String? previewUrl,
  Duration poll = const Duration(seconds: 5)})` with fields `preview`, `loading`, `error`, getter
  `hasPreview`, and `Future<void> refresh()`; states `PreviewInitialState`,
  `PreviewReadyState(int revision)`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/preview/presentation/preview_screen/logic/preview_cubit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';

class _MockRepository extends Mock implements PreviewRepository {}

PreviewModel preview(String entry) =>
    PreviewModel(entry: entry, url: 'http://10.0.0.5:3011/x', authenticated: true);

void main() {
  late _MockRepository repository;

  setUp(() => repository = _MockRepository());

  PreviewCubit build({String? previewUrl}) => PreviewCubit(
    repository,
    's-1',
    previewUrl: previewUrl,
    poll: const Duration(milliseconds: 30),
  );

  test('asks the detector as soon as it is built', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(preview('dist/index.html')));
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.preview?.entry, 'dist/index.html');
    expect(cubit.loading, isFalse);
    verify(() => repository.getPreview('s-1', previewUrl: null)).called(1);
    await cubit.close();
  });

  test('passes the session preview URL through so a dev server can be found', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));
    final cubit = build(previewUrl: 'http://localhost:5173/');

    await Future<void>.delayed(Duration.zero);

    verify(() => repository.getPreview('s-1', previewUrl: 'http://localhost:5173/')).called(1);
    await cubit.close();
  });

  test('keeps polling on the tick', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));
    final cubit = build();

    await Future<void>.delayed(const Duration(milliseconds: 80));

    verify(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .called(greaterThan(1));
    await cubit.close();
  });

  test('a bare README is not something worth showing', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(preview('README.md')));
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.preview, isNotNull);
    expect(cubit.hasPreview, isFalse);
    await cubit.close();
  });

  test('a generated page is worth showing', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(preview('dist/index.html')));
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.hasPreview, isTrue);
    await cubit.close();
  });

  test('a transient failure keeps the last good answer and records the message', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(preview('dist/index.html')));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'down', statusCode: 503)),
    );
    await cubit.refresh();

    expect(cubit.preview?.entry, 'dist/index.html');
    expect(cubit.error, 'down');
    await cubit.close();
  });

  test('stops polling once closed', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    clearInteractions(repository);

    await Future<void>.delayed(const Duration(milliseconds: 80));

    verifyNever(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')));
  });
}
```

That is **7 tests**.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/preview/presentation`
Expected: FAIL — `preview_cubit.dart` does not exist.

- [ ] **Step 3: Write the state**

Create `packages/mobile/lib/feature/preview/presentation/preview_screen/logic/preview_state.dart`:

```dart
part of 'preview_cubit.dart';

sealed class PreviewState extends Equatable {
  const PreviewState();

  @override
  List<Object?> get props => [];
}

final class PreviewInitialState extends PreviewState {
  const PreviewInitialState();
}

final class PreviewReadyState extends PreviewState {
  const PreviewReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
```

- [ ] **Step 4: Write the cubit**

Create `packages/mobile/lib/feature/preview/presentation/preview_screen/logic/preview_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/logic/preview_url.dart';

part 'preview_state.dart';

class PreviewCubit extends Cubit<PreviewState> {
  factory PreviewCubit(
    PreviewRepository repository,
    String sessionId, {
    String? previewUrl,
    Duration poll = const Duration(seconds: 5),
  }) => PreviewCubit._(repository, sessionId, previewUrl: previewUrl, poll: poll);

  PreviewCubit._(
    this._repository,
    this.sessionId, {
    required this.previewUrl,
    required Duration poll,
  }) : _poll = poll,
       super(const PreviewInitialState()) {
    unawaited(refresh());
    _timer = Timer.periodic(_poll, (_) => unawaited(refresh()));
  }

  final PreviewRepository _repository;
  final String sessionId;
  final String? previewUrl;
  final Duration _poll;

  PreviewModel? preview;
  bool loading = true;
  String? error;

  Timer? _timer;
  int _revision = 0;

  bool get hasPreview => preview != null && previewWorthShowing(preview!.entry);

  Future<void> refresh() async {
    if (isClosed) return;
    final result = await _repository.getPreview(sessionId, previewUrl: previewUrl);
    if (isClosed) return;
    result.when(
      onSuccess: (value) {
        preview = value;
        error = null;
      },
      // Transient: keep the last good answer on screen rather than blanking the
      // globe every time a poll tick loses the network.
      onFailure: (failure) => error = failure.message,
    );
    loading = false;
    emit(PreviewReadyState(++_revision));
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/feature/preview/presentation`
Expected: PASS, 7 tests.

- [ ] **Step 6: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 965/965 green.

```bash
git add packages/mobile/lib/feature/preview packages/mobile/test/feature/preview
git commit -m "feat(mobile): add the preview cubit"
```

---
### Task 19: The preview browser, the globe and the chat menu row

Ports `app/preview/[id].tsx` and the globe half of `TerminalSessionScreen.tsx` (lines 593–617,
936–950, 1267–1295). One route serves both doors; pushing it leaves the terminal's PTY attached
underneath, which is the only property RN's second WebView bought.

The `WebViewWidget` cannot be built in a widget test (no platform view), so `PreviewBody` takes a
`browserBuilder` that defaults to the real `PreviewBrowser`. Tests pass a stub and assert the URL and
the auth decision that reaches it; the real browser is exercised on a device.

**Files:**
- Modify: `packages/mobile/pubspec.yaml`
- Create: `packages/mobile/lib/feature/preview/presentation/preview_screen/ui/preview_screen.dart`
- Create: `packages/mobile/lib/feature/preview/presentation/preview_screen/ui/widgets/preview_body.dart`
- Create: `packages/mobile/lib/feature/preview/presentation/preview_screen/ui/widgets/preview_browser.dart`
- Modify: `packages/mobile/lib/core/app_routes/routes_strings.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart`
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart`
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart`
- Test: `packages/mobile/test/feature/preview/presentation/preview_screen/ui/preview_body_test.dart`

**Interfaces:**
- Consumes: `PreviewCubit`, `ServerConfigStore`, `webview_flutter 4.14.1`.
- Produces: `RoutesStrings.preview`, the `/preview` route case, `_previewFeatureSetup()`,
  `PreviewScreen`, `PreviewBody({PreviewBrowserBuilder? browserBuilder})`,
  `typedef PreviewBrowserBuilder = Widget Function(PreviewModel preview)`, `PreviewBrowser`,
  `ConversationMenuAction.preview`.

- [ ] **Step 1: Add the dependency**

```bash
cd packages/mobile && flutter pub add webview_flutter
```

Expected: `pubspec.yaml` gains `webview_flutter: ^4.14.1`; `flutter pub get` resolves
`webview_flutter 4.14.1`, `webview_flutter_android 4.14.0`, `webview_flutter_wkwebview 3.26.0`,
`webview_flutter_platform_interface 2.15.1`.

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 965/965 green.

- [ ] **Step 2: Write the failing test**

Create `packages/mobile/test/feature/preview/presentation/preview_screen/ui/preview_body_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/ui/widgets/preview_body.dart';

class _MockRepository extends Mock implements PreviewRepository {}

void main() {
  late _MockRepository repository;
  late List<PreviewModel> rendered;

  setUp(() {
    repository = _MockRepository();
    rendered = [];
  });

  Future<PreviewCubit> pump(WidgetTester tester) async {
    final cubit = PreviewCubit(repository, 's-1', poll: const Duration(hours: 1));
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<PreviewCubit>.value(
                value: cubit,
                child: PreviewBody(
                  browserBuilder: (preview) {
                    rendered.add(preview);
                    return AppText('browser:${preview.url}');
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(cubit.close);
    return cubit;
  }

  testWidgets('waits while the detector is still looking', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return Result.success(null);
      },
    );
    final cubit = PreviewCubit(repository, 's-1', poll: const Duration(hours: 1));
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<PreviewCubit>.value(value: cubit, child: const PreviewBody()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Looking for a session preview…'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await cubit.close();
  });

  testWidgets('explains that nothing has been generated yet', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));

    await pump(tester);

    expect(find.text('No preview yet'), findsOneWidget);
    expect(rendered, isEmpty);
  });

  testWidgets('reports a detector failure instead of an empty screen', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'down', statusCode: 503)),
    );

    await pump(tester);

    expect(find.text('Could not load preview'), findsOneWidget);
    expect(find.text('down'), findsOneWidget);
  });

  testWidgets('checking again re-asks the detector', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));

    await pump(tester);
    clearInteractions(repository);
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();

    verify(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).called(1);
  });

  testWidgets('renders the browser at the resolved URL', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async => Result.success(
        const PreviewModel(
          entry: 'dist/index.html',
          url: 'http://10.0.0.5:3011/api/v1/sessions/s-1/preview/files/dist/index.html',
          authenticated: true,
        ),
      ),
    );

    await pump(tester);

    expect(rendered.single.authenticated, isTrue);
    expect(
      find.text('browser:http://10.0.0.5:3011/api/v1/sessions/s-1/preview/files/dist/index.html'),
      findsOneWidget,
    );
  });

  testWidgets('shows a README preview when asked directly, even though the dot stays off', (
    tester,
  ) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async => Result.success(
        const PreviewModel(entry: 'README.md', url: 'http://10.0.0.5:3011/x', authenticated: true),
      ),
    );

    final cubit = await pump(tester);

    expect(cubit.hasPreview, isFalse);
    expect(rendered, hasLength(1));
  });

  testWidgets('never hands the Bearer header to an external dev server', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async => Result.success(
        const PreviewModel(entry: '10.0.0.5', url: 'http://10.0.0.5:5173/', authenticated: false),
      ),
    );

    await pump(tester);

    expect(rendered.single.authenticated, isFalse);
  });
}
```

That is **7 tests**.

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/feature/preview/presentation/preview_screen/ui`
Expected: FAIL — `preview_body.dart` does not exist.

- [ ] **Step 4: Write the browser**

Create `packages/mobile/lib/feature/preview/presentation/preview_screen/ui/widgets/preview_browser.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PreviewBrowser extends StatefulWidget {
  const PreviewBrowser({super.key, required this.preview, required this.onError});

  final PreviewModel preview;
  final void Function(String message) onError;

  @override
  State<PreviewBrowser> createState() => _PreviewBrowserState();
}

class _PreviewBrowserState extends State<PreviewBrowser> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onWebResourceError: (error) => widget.onError(
          error.description.isEmpty ? 'The preview could not be loaded.' : error.description,
        ),
        onHttpError: (error) => widget.onError(
          'Preview returned HTTP ${error.response?.statusCode ?? 0}.',
        ),
      ),
    );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PreviewBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview.url != widget.preview.url) _load();
  }

  /// The daemon's preview route sits behind the connection password, so without
  /// this header the WebView 401s and renders the JSON error body. An external
  /// dev server is never authenticated and must never see the password.
  void _load() {
    final password = sl<ServerConfigStore>().current?.password ?? '';
    _controller.loadRequest(
      Uri.parse(widget.preview.url),
      headers: widget.preview.authenticated && password.isNotEmpty
          ? {'Authorization': 'Bearer $password'}
          : const {},
    );
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.skin.bgBase,
    child: WebViewWidget(controller: _controller),
  );
}
```

- [ ] **Step 5: Write the body and the screen**

Create `packages/mobile/lib/feature/preview/presentation/preview_screen/ui/widgets/preview_body.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/ui/widgets/preview_browser.dart';

typedef PreviewBrowserBuilder = Widget Function(PreviewModel preview);

class PreviewBody extends StatelessWidget {
  const PreviewBody({super.key, this.browserBuilder});

  final PreviewBrowserBuilder? browserBuilder;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<PreviewCubit, PreviewState>(
      buildWhen: (previous, current) => current is PreviewReadyState,
      builder: (context, state) {
        final cubit = context.read<PreviewCubit>();

        if (cubit.loading) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLoader(),
                const VerticalSpace(11),
                AppText(
                  'Looking for a session preview…',
                  style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
                ),
              ],
            ),
          );
        }

        final preview = cubit.preview;
        if (preview == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cubit.error == null ? Icons.public : Icons.warning_amber_rounded,
                    size: 24,
                    color: cubit.error == null ? skin.textTertiary : skin.red,
                  ),
                  const VerticalSpace(11),
                  AppText(
                    cubit.error == null ? 'No preview yet' : 'Could not load preview',
                    style: AppTextStyle.style17Bold,
                  ),
                  const VerticalSpace(6),
                  AppText(
                    cubit.error ??
                        'Waiting for the agent to generate a page or document. '
                            'This screen keeps checking.',
                    style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                  ),
                  const VerticalSpace(14),
                  PrimaryButton(text: 'Check again', onPressed: cubit.refresh),
                ],
              ),
            ),
          );
        }

        final builder = browserBuilder;
        if (builder != null) return builder(preview);
        return PreviewBrowser(
          preview: preview,
          onError: (message) => context.showSnackBar(message),
        );
      },
    );
  }
}
```

Create `packages/mobile/lib/feature/preview/presentation/preview_screen/ui/preview_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/ui/widgets/preview_body.dart';

class PreviewScreen extends StatelessWidget {
  const PreviewScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => BlocListener<PreviewCubit, PreviewState>(
    listener: (context, state) {},
    child: AppScaffold(
      appBar: GlobalAppbar.sub(
        titleText: title,
        actions: [
          Semantics(
            button: true,
            label: 'Reload preview',
            child: IconButton(
              onPressed: context.read<PreviewCubit>().refresh,
              icon: Icon(Icons.refresh, size: 18, color: context.skin.textSecondary),
            ),
          ),
        ],
      ),
      body: const PreviewBody(),
    ),
  );
}
```

- [ ] **Step 6: Route, register, and open both doors**

In `routes_strings.dart`:

```dart
  static const String preview = '/preview';
```

In `app_router.dart`:

```dart
      case RoutesStrings.preview:
        final args = settings.arguments as Map<String, dynamic>?;
        final sessionId = args?['sessionId'] as String? ?? '';
        return MaterialPageRoute(
          builder: (context) => BlocProvider<PreviewCubit>(
            create: (_) => sl<PreviewCubit>(
              param1: sessionId,
              param2: args?['previewUrl'] as String?,
            ),
            child: PreviewScreen(title: args?['title'] as String? ?? 'Preview'),
          ),
          settings: settings,
        );
```

In `service_locator.dart`, add `_previewFeatureSetup();` to `init()` and:

```dart
  static void _previewFeatureSetup() {
    sl.registerFactoryParam<PreviewCubit, String, String?>(
      (sessionId, previewUrl) =>
          PreviewCubit(sl<PreviewRepository>(), sessionId, previewUrl: previewUrl),
    );

    sl.registerLazySingleton<PreviewRepository>(
      () => PreviewRepositoryImp(
        sl<PreviewRemoteDataSource>(),
        sl<NetworkStatus>(),
        sl<ServerConfigStore>(),
      ),
    );
    sl.registerLazySingleton<PreviewRemoteDataSource>(
      () => PreviewRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }
```

In `terminal_screen.dart`, add the globe beside the existing Chat action. The dot is the poll's
answer, so the screen provides its own `PreviewCubit` for a `tui` session:

```dart
            if (!args.shellOnly)
              BlocProvider<PreviewCubit>(
                create: (_) => sl<PreviewCubit>(param1: args.sessionId, param2: null),
                child: Builder(
                  builder: (context) => BlocBuilder<PreviewCubit, PreviewState>(
                    buildWhen: (previous, current) => current is PreviewReadyState,
                    builder: (context, state) {
                      final ready = context.read<PreviewCubit>().hasPreview;
                      return Semantics(
                        button: true,
                        label: 'Open preview',
                        child: IconButton(
                          onPressed: () => ready
                              ? Navigator.of(context).pushNamed(
                                  RoutesStrings.preview,
                                  arguments: {'sessionId': args.sessionId, 'title': args.title},
                                )
                              : context.showSnackBar(
                                  'No preview yet — waiting for the agent to generate a page '
                                  'or document.',
                                ),
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(Icons.public, size: 18, color: context.skin.textSecondary),
                              if (ready)
                                Positioned(
                                  right: -1,
                                  top: -1,
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: context.skin.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
```

In `conversation_menu_sheet.dart`, add `preview` to `ConversationMenuAction` and a row after
"Conversation map":

```dart
          _MenuRow(
            icon: Icons.public,
            label: 'Open preview',
            hint: 'View a page or document generated in this worktree',
            onTap: () => Navigator.of(
              context,
            ).pop(const ConversationMenuResult(ConversationMenuAction.preview)),
          ),
```

In `chat_body.dart`'s `switch (result.action)`:

```dart
      case ConversationMenuAction.preview:
        Navigator.of(context).pushNamed(
          RoutesStrings.preview,
          arguments: {
            'sessionId': cubit.sessionId,
            'title': snapshot.title ?? 'Preview',
            'previewUrl': widget.previewUrl,
          },
        );
```

`ChatBody` gains a `final String? previewUrl;` constructor field, threaded from `SessionRouteScreen`
where the session's `previewUrl` is already in hand (`session_route_screen.dart` reads the
`SessionModel`). Where the session is unknown, pass `null` — the daemon's own detector still answers.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/feature/preview test/feature/chat test/feature/terminal`
Expected: PASS.

- [ ] **Step 8: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 972/972 green.

```bash
git add packages/mobile/lib packages/mobile/test packages/mobile/pubspec.yaml packages/mobile/pubspec.lock
git commit -m "feat(mobile): add the session preview browser and its two doors"
```

---
### Task 20: The deep-link vocabulary

The pure half of deep linking: a URI (or the path a notification payload carries) becomes a route
name plus arguments. It consumes the exact strings `notificationTarget` produces, so a tray tap and a
history tap cannot disagree — RN's stated reason for that function existing.

**Files:**
- Create: `packages/mobile/lib/core/deep_link/deep_link_target.dart`
- Test: `packages/mobile/test/core/deep_link/deep_link_target_test.dart`

**Interfaces:**
- Consumes: `RoutesStrings`, `TerminalArgs`, `Equatable`.
- Produces: `kDeepLinkScheme` (`'aomobile'`), `DeepLinkTarget({required String route, Map<String,
  dynamic>? arguments, int? tabIndex})`, `DeepLinkTarget? resolveDeepLink(Uri uri)`,
  `DeepLinkTarget? resolveDeepLinkPath(String path)`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/core/deep_link/deep_link_target_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/deep_link/deep_link_target.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

void main() {
  test('opens a session from the scheme, host-form and path-form alike', () {
    for (final link in ['aomobile://session/abc', 'aomobile:///session/abc']) {
      final target = resolveDeepLink(Uri.parse(link));

      expect(target?.route, RoutesStrings.session);
      expect(target?.arguments, {'sessionId': 'abc'});
    }
  });

  test('decodes a session id that needed escaping', () {
    expect(
      resolveDeepLink(Uri.parse('aomobile://session/a%20b'))?.arguments?['sessionId'],
      'a b',
    );
  });

  test('sends prs to the board with the PRs tab selected', () {
    final target = resolveDeepLink(Uri.parse('aomobile://prs'));

    expect(target?.route, RoutesStrings.sessions);
    expect(target?.tabIndex, 2);
  });

  test('opens the notification history', () {
    expect(
      resolveDeepLink(Uri.parse('aomobile://notifications'))?.route,
      RoutesStrings.notifications,
    );
  });

  test('opens a TUI session straight into the terminal', () {
    final target = resolveDeepLink(Uri.parse('aomobile://terminal/abc'));

    expect(target?.route, RoutesStrings.terminal);
    final args = target?.arguments?['args'] as TerminalArgs?;
    expect(args?.id, 'abc');
    expect(args?.sessionId, 'abc');
    expect(args?.shellOnly, isFalse);
  });

  test('refuses a link from another scheme', () {
    expect(resolveDeepLink(Uri.parse('https://example.com/session/abc')), isNull);
  });

  test('refuses a route it does not know, and a session with no id', () {
    expect(resolveDeepLink(Uri.parse('aomobile://settings')), isNull);
    expect(resolveDeepLink(Uri.parse('aomobile://session')), isNull);
    expect(resolveDeepLink(Uri.parse('aomobile://')), isNull);
  });

  test('resolves the internal paths notificationTarget produces', () {
    expect(resolveDeepLinkPath('/session/abc')?.arguments, {'sessionId': 'abc'});
    expect(resolveDeepLinkPath('/prs')?.tabIndex, 2);
    expect(resolveDeepLinkPath('nonsense'), isNull);
  });

  test('is equal for equal links, so a repeated cold-start link is detectable', () {
    expect(
      resolveDeepLink(Uri.parse('aomobile://session/abc')),
      resolveDeepLink(Uri.parse('aomobile://session/abc')),
    );
  });
}
```

That is **9 tests**.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/deep_link`
Expected: FAIL — `deep_link_target.dart` does not exist.

- [ ] **Step 3: Write the resolver**

Create `packages/mobile/lib/core/deep_link/deep_link_target.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

const String kDeepLinkScheme = 'aomobile';

/// The PRs tab's index in `HomeShell`.
const int kPrsTabIndex = 2;

class DeepLinkTarget extends Equatable {
  const DeepLinkTarget({required this.route, this.arguments, this.tabIndex});

  final String route;
  final Map<String, dynamic>? arguments;
  final int? tabIndex;

  @override
  List<Object?> get props => [route, arguments, tabIndex];
}

/// `aomobile://session/abc` parses with `session` as the host, while
/// `aomobile:///session/abc` puts it in the path — both forms reach a phone, so
/// both are flattened to the same segment list.
DeepLinkTarget? resolveDeepLink(Uri uri) {
  if (uri.scheme != kDeepLinkScheme) return null;
  final segments = [
    if (uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments.where((segment) => segment.isNotEmpty),
  ];
  return _resolveSegments(segments);
}

/// The path form `notificationTarget` produces, so a tray tap and a history tap
/// cannot disagree about where a notification leads.
DeepLinkTarget? resolveDeepLinkPath(String path) {
  if (!path.startsWith('/')) return null;
  return _resolveSegments(
    path.split('/').where((segment) => segment.isNotEmpty).toList(),
  );
}

DeepLinkTarget? _resolveSegments(List<String> segments) {
  if (segments.isEmpty) return null;
  final id = segments.length > 1 ? Uri.decodeComponent(segments[1]) : '';

  switch (segments.first) {
    case 'session':
      if (id.isEmpty) return null;
      return DeepLinkTarget(route: RoutesStrings.session, arguments: {'sessionId': id});
    case 'terminal':
      if (id.isEmpty) return null;
      return DeepLinkTarget(
        route: RoutesStrings.terminal,
        arguments: {'args': TerminalArgs(id: id, sessionId: id, title: 'Terminal')},
      );
    case 'prs':
      return const DeepLinkTarget(route: RoutesStrings.sessions, tabIndex: kPrsTabIndex);
    case 'notifications':
      return const DeepLinkTarget(route: RoutesStrings.notifications);
    default:
      return null;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/deep_link`
Expected: PASS, 9 tests.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 981/981 green.

```bash
git add packages/mobile/lib/core/deep_link packages/mobile/test/core/deep_link
git commit -m "feat(mobile): add the deep-link vocabulary"
```

---
### Task 21: Deep-link routing

Wires `app_links` to the navigator, and declares the `aomobile` scheme natively — the work Expo's
`"scheme": "aomobile"` used to generate at prebuild. Cold start and warm links both go through one
resolver, so a link that arrives before the navigator exists is not lost.

**Files:**
- Modify: `packages/mobile/pubspec.yaml`
- Create: `packages/mobile/lib/core/deep_link/deep_link_service.dart`
- Modify: `packages/mobile/lib/main.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Modify: `packages/mobile/ios/Runner/Info.plist`
- Modify: `packages/mobile/android/app/src/main/AndroidManifest.xml`
- Test: `packages/mobile/test/core/deep_link/deep_link_service_test.dart`

**Interfaces:**
- Consumes: `DeepLinkTarget`, `resolveDeepLink`, `HomeShell.selectedTab`, `app_links 7.2.1`.
- Produces: `abstract class AppLinkSource` with `Future<Uri?> initialLink()` and
  `Stream<Uri> get linkStream`; `AppLinksSource implements AppLinkSource`;
  `DeepLinkService(AppLinkSource source, GlobalKey<NavigatorState> navigatorKey)` with
  `Future<void> start()`, `Future<void> dispose()`, and `bool handle(Uri uri)`.

- [ ] **Step 1: Add the dependency**

```bash
cd packages/mobile && flutter pub add app_links
```

Expected: `pubspec.yaml` gains `app_links: ^7.2.1`; `flutter pub get` resolves `app_links 7.2.1`,
`app_links_platform_interface 2.0.4`, `app_links_linux 1.0.3`, `app_links_web 1.0.4`, `gtk 2.2.0`.

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 981/981 green.

- [ ] **Step 2: Write the failing test**

Create `packages/mobile/test/core/deep_link/deep_link_service_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/deep_link/deep_link_service.dart';

class _FakeSource implements AppLinkSource {
  _FakeSource({this.initial});

  Uri? initial;
  final StreamController<Uri> controller = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Stream<Uri> get linkStream => controller.stream;
}

class _RecordingObserver extends NavigatorObserver {
  final List<String?> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route.settings.name);
}

void main() {
  late _FakeSource source;
  late _RecordingObserver observer;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    source = _FakeSource();
    observer = _RecordingObserver();
    navigatorKey = GlobalKey<NavigatorState>();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        initialRoute: RoutesStrings.sessions,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => const SizedBox.shrink(),
          settings: settings,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a cold-start link lands on its screen', (tester) async {
    source.initial = Uri.parse('aomobile://session/abc');
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey);

    await service.start();
    await tester.pumpAndSettle();

    expect(observer.pushed.last, RoutesStrings.session);
    await service.dispose();
  });

  testWidgets('a warm link arriving later lands too', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey);
    await service.start();

    source.controller.add(Uri.parse('aomobile://notifications'));
    await tester.pumpAndSettle();

    expect(observer.pushed.last, RoutesStrings.notifications);
    await service.dispose();
  });

  testWidgets('a prs link selects the PRs tab instead of stacking a route', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey);
    await service.start();
    observer.pushed.clear();

    source.controller.add(Uri.parse('aomobile://prs'));
    await tester.pumpAndSettle();

    expect(HomeShell.selectedTab.value, 2);
    expect(observer.pushed, isEmpty);
    await service.dispose();
  });

  testWidgets('an unknown link is ignored rather than crashing the app', (tester) async {
    await pumpApp(tester);
    final service = DeepLinkService(source, navigatorKey);
    await service.start();
    observer.pushed.clear();

    source.controller.add(Uri.parse('aomobile://settings'));
    source.controller.add(Uri.parse('https://example.com/session/abc'));
    await tester.pumpAndSettle();

    expect(observer.pushed, isEmpty);
    await service.dispose();
  });

  testWidgets('handling before the navigator exists reports that it did nothing', (tester) async {
    final service = DeepLinkService(source, GlobalKey<NavigatorState>());

    expect(service.handle(Uri.parse('aomobile://session/abc')), isFalse);
    await service.dispose();
  });
}
```

That is **5 tests**.

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/core/deep_link/deep_link_service_test.dart`
Expected: FAIL — `deep_link_service.dart` does not exist.

- [ ] **Step 4: Write the service**

Create `packages/mobile/lib/core/deep_link/deep_link_service.dart`:

```dart
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/deep_link/deep_link_target.dart';

abstract class AppLinkSource {
  Future<Uri?> initialLink();

  Stream<Uri> get linkStream;
}

class AppLinksSource implements AppLinkSource {
  AppLinksSource([AppLinks? links]) : _links = links ?? AppLinks();

  final AppLinks _links;

  @override
  Future<Uri?> initialLink() => _links.getInitialLink();

  @override
  Stream<Uri> get linkStream => _links.uriLinkStream;
}

class DeepLinkService {
  DeepLinkService(this._source, this._navigatorKey);

  final AppLinkSource _source;
  final GlobalKey<NavigatorState> _navigatorKey;

  StreamSubscription<Uri>? _subscription;

  /// The cold-start link is read before subscribing: the stream only carries
  /// links that arrive while the app is already alive, so the launch tap would
  /// otherwise be lost.
  Future<void> start() async {
    final initial = await _source.initialLink();
    if (initial != null) handle(initial);
    _subscription = _source.linkStream.listen(handle);
  }

  bool handle(Uri uri) {
    final target = resolveDeepLink(uri);
    if (target == null) return false;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return false;

    final tabIndex = target.tabIndex;
    if (tabIndex != null) {
      HomeShell.selectedTab.value = tabIndex;
      navigator.popUntil((route) => route.isFirst);
      return true;
    }

    navigator.pushNamed(target.route, arguments: target.arguments);
    return true;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
```

- [ ] **Step 5: Start it from the app**

In `service_locator.dart`, inside `_coreSetup()`:

```dart
    sl.registerLazySingleton<GlobalKey<NavigatorState>>(() => GlobalKey<NavigatorState>());
    sl.registerLazySingleton<DeepLinkService>(
      () => DeepLinkService(AppLinksSource(), sl<GlobalKey<NavigatorState>>()),
    );
```

In `main.dart`, give the `MaterialApp` the key and start the service after the first frame — the
navigator does not exist until then:

```dart
                  navigatorKey: sl<GlobalKey<NavigatorState>>(),
```

In `_OperatorAppState.initState`:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(sl<DeepLinkService>().start());
    });
  }
```

- [ ] **Step 6: Declare the scheme natively**

In `ios/Runner/Info.plist`:

```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLName</key>
			<string>dev.operator.mobile</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>aomobile</string>
			</array>
		</dict>
	</array>
```

In `android/app/src/main/AndroidManifest.xml`, inside the `.MainActivity` element, beside the
existing `MAIN`/`LAUNCHER` filter:

```xml
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="aomobile"/>
            </intent-filter>
```

The activity is already `android:launchMode="singleTop"` and `android:exported="true"`, which is what
`app_links` needs to deliver a warm link into the running task.

- [ ] **Step 7: Run the test to verify it passes**

Run: `flutter test test/core/deep_link`
Expected: PASS, 14 tests across both files.

- [ ] **Step 8: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 986/986 green.

```bash
git add packages/mobile/lib packages/mobile/test packages/mobile/ios packages/mobile/android packages/mobile/pubspec.yaml packages/mobile/pubspec.lock
git commit -m "feat(mobile): resolve aomobile deep links to their screens"
```

---
### Task 22 — BLOCKED: Firebase, APNs, and the real push token

**This task cannot start until the repository owner has created:**

1. a Firebase project with an Android app registered under the package id
   `com.example.operator_mobile` (the id in `android/app/build.gradle.kts`) → `google-services.json`;
2. an iOS app registered under the bundle id in `ios/Runner.xcodeproj` → `GoogleService-Info.plist`;
3. an **APNs authentication key** (`.p8`, Key ID, Team ID) uploaded to that Firebase project, plus the
   Push Notifications capability and an `aps-environment` entitlement on the iOS target.

Nothing else in M5 depends on it. Tasks 1–21 leave the app fully functional with
`UnconfiguredPushTokenSource`, whose switch says "Push isn't configured in this build".

**What stays untestable until then:** the milestone's "device registers for push and receives one"
criterion, and only that. The mapping from a Firebase token and a tray payload onto a
`PushRegisterResult` / a `DeepLinkTarget` is tested here through the same seams the earlier tasks use,
so this task's own risk is native configuration, not Dart.

**Files:**
- Modify: `packages/mobile/pubspec.yaml`
- Create: `packages/mobile/lib/feature/notification/logic/firebase_push_token_source.dart`
- Create: `packages/mobile/lib/feature/notification/logic/push_service.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Modify: `packages/mobile/lib/main.dart`
- Modify: `packages/mobile/android/app/build.gradle.kts`, `packages/mobile/android/settings.gradle.kts`
- Add (owner-supplied, git-ignored): `packages/mobile/android/app/google-services.json`,
  `packages/mobile/ios/Runner/GoogleService-Info.plist`
- Test: `packages/mobile/test/feature/notification/logic/push_service_test.dart`

**Interfaces:**
- Consumes: `firebase_core 4.13.0`, `firebase_messaging 16.5.0`, `flutter_local_notifications 22.3.0`,
  `PushTokenSource`, `PushRegistrar`, `DeepLinkService`, `resolveDeepLinkPath`, `notificationTarget`,
  `TelemetryRuntime`.
- Produces: `FirebasePushTokenSource implements PushTokenSource`, `PushService(PushRegistrar
  registrar, DeepLinkService links, {required Stream<Map<String, dynamic>> taps})` with
  `Future<void> start()`, `void onTap(Map<String, dynamic> data, {required bool coldStart})`, and
  `Future<void> onConnected(ServerConfig config)`.

- [ ] **Step 1: Confirm the credentials exist**

Do not start otherwise. Check that `packages/mobile/android/app/google-services.json` and
`packages/mobile/ios/Runner/GoogleService-Info.plist` are present, and that the Firebase console shows
an APNs key for the iOS app. Both files must be added to `.gitignore` — they identify the owner's
project, and the repository has never carried them.

- [ ] **Step 2: Add the dependencies**

```bash
cd packages/mobile && flutter pub add firebase_core firebase_messaging flutter_local_notifications
```

Expected: `firebase_core 4.13.0`, `firebase_messaging 16.5.0`, `flutter_local_notifications 22.3.0`
and the transitives listed in this plan's "New dependencies" section.

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 986/986 green.

- [ ] **Step 3: Write the failing test**

Create `packages/mobile/test/feature/notification/logic/push_service_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/deep_link/deep_link_service.dart';
import 'package:operator_mobile/core/deep_link/deep_link_target.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/feature/notification/logic/push_service.dart';

import '../../../core/telemetry/telemetry_test.dart' show RecordingClient;

class _RecordingLinks extends Mock implements DeepLinkService {}

void main() {
  late StreamController<Map<String, dynamic>> taps;
  late _RecordingLinks links;
  late RecordingClient client;

  setUpAll(() => registerFallbackValue(Uri.parse('aomobile://prs')));

  setUp(() {
    taps = StreamController<Map<String, dynamic>>.broadcast();
    links = _RecordingLinks();
    when(() => links.handle(any())).thenReturn(true);
    TelemetryRuntime.reset();
    client = RecordingClient();
    TelemetryRuntime.init(
      client: client,
      context: const TelemetryContextInput(
        platformOs: 'ios',
        isPhysicalDevice: true,
        dev: false,
        appVersion: '1.1.0',
      ),
    );
  });

  tearDown(() async {
    await taps.close();
    TelemetryRuntime.reset();
  });

  test('a needs_input tap routes to that session', () {
    final service = PushService.forTest(links, taps.stream);

    service.onTap(const {'type': 'needs_input', 'sessionId': 'abc'}, coldStart: true);

    expect(resolveDeepLinkPath('/session/abc')?.route, RoutesStrings.session);
    verify(() => links.handle(Uri.parse('aomobile://session/abc'))).called(1);
  });

  test('every other tap routes to the PRs tab', () {
    final service = PushService.forTest(links, taps.stream);

    service.onTap(const {'type': 'ready_to_merge', 'sessionId': 'abc'}, coldStart: false);
    service.onTap(const {}, coldStart: false);

    verify(() => links.handle(Uri.parse('aomobile://prs'))).called(2);
  });

  test('a tap reports the retention event with its target and cold-start flag', () {
    final service = PushService.forTest(links, taps.stream);

    service.onTap(const {'type': 'needs_input', 'sessionId': 'abc'}, coldStart: true);

    final capture = client.captures.single;
    expect(capture.event, MobileEvents.notificationOpened);
    expect(capture.properties['target'], 'session');
    expect(capture.properties['cold_start'], isTrue);
  });
}
```

That is **3 tests**.

- [ ] **Step 4: Write the token source**

Create `packages/mobile/lib/feature/notification/logic/firebase_push_token_source.dart`:

```dart
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:operator_mobile/feature/notification/logic/push_status.dart';
import 'package:operator_mobile/feature/notification/logic/push_token_source.dart';

class FirebasePushTokenSource implements PushTokenSource {
  FirebasePushTokenSource(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  bool get supported => Platform.isAndroid || Platform.isIOS;

  @override
  String get platform => Platform.isIOS ? 'ios' : 'android';

  @override
  Future<PushStatus> permissionStatus() async {
    final settings = await _messaging.getNotificationSettings();
    return PushStatus(
      supported: supported,
      granted: settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional,
      canAskAgain: settings.authorizationStatus == AuthorizationStatus.notDetermined,
      registered: false,
    );
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// On iOS the APNs token can lag the permission grant by a moment; without it
  /// `getToken` throws rather than returning null, which would read as
  /// `tokenFailed` on a perfectly good build.
  @override
  Future<String?> getToken() async {
    try {
      if (Platform.isIOS && await _messaging.getAPNSToken() == null) return null;
      return await _messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> deviceName() async => Platform.localHostname;
}
```

- [ ] **Step 5: Write the push service**

Create `packages/mobile/lib/feature/notification/logic/push_service.dart`:

```dart
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/deep_link/deep_link_service.dart';
import 'package:operator_mobile/core/deep_link/deep_link_target.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/feature/notification/logic/notification_view.dart';
import 'package:operator_mobile/feature/notification/logic/push_registrar.dart';

/// One high-importance Android channel, so a `needs_input` actually buzzes.
const AndroidNotificationChannel kPushChannel = AndroidNotificationChannel(
  'default',
  'Default',
  importance: Importance.high,
);

class PushService {
  PushService(this._registrar, this._links, this._messaging);

  PushService.forTest(this._links, Stream<Map<String, dynamic>> taps)
    : _registrar = null,
      _messaging = null,
      _testTaps = taps;

  final PushRegistrar? _registrar;
  final DeepLinkService _links;
  final FirebaseMessaging? _messaging;
  Stream<Map<String, dynamic>>? _testTaps;

  StreamSubscription<Map<String, dynamic>>? _subscription;

  Future<void> start() async {
    final messaging = _messaging;
    final taps = _testTaps;
    if (taps != null) {
      _subscription = taps.listen((data) => onTap(data, coldStart: false));
      return;
    }
    if (messaging == null) return;

    final initial = await messaging.getInitialMessage();
    if (initial != null) onTap(initial.data, coldStart: true);
    _subscription = messaging.onMessageOpenedApp
        .map((message) => message.data)
        .listen((data) => onTap(data, coldStart: false));
  }

  /// Registers automatically, so it must never spend the one-shot OS prompt:
  /// `ask: false` re-registers users who already granted permission and leaves
  /// the asking to a tap the user initiated in Settings.
  Future<void> onConnected(ServerConfig config) async {
    await _registrar?.register(config, ask: false);
  }

  /// Reuses the one routing rule so the reported target cannot disagree with
  /// where the tap actually lands.
  void onTap(Map<String, dynamic> data, {required bool coldStart}) {
    final destination = notificationTarget(
      type: data['type'] as String? ?? '',
      sessionId: data['sessionId'] as String?,
    );
    TelemetryRuntime.capture(MobileEvents.notificationOpened, {
      'target': destination.startsWith('/session') ? 'session' : 'prs',
      'cold_start': coldStart,
    });
    _links.handle(Uri.parse('$kDeepLinkScheme:/$destination'));
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
```

- [ ] **Step 6: Wire it up**

In `service_locator.dart`, replace the unconfigured source and register the service:

```dart
    sl.registerLazySingleton<PushTokenSource>(
      () => FirebasePushTokenSource(FirebaseMessaging.instance),
    );
    sl.registerLazySingleton<PushService>(
      () => PushService(sl<PushRegistrar>(), sl<DeepLinkService>(), FirebaseMessaging.instance),
    );
```

In `main.dart`, before `ServiceLocator.init()`:

```dart
  await Firebase.initializeApp();
```

and after the deep-link service starts, in the same post-frame callback:

```dart
      unawaited(sl<PushService>().start());
```

In `sessions_cubit.dart`, the `connected` capture already marks the moment a daemon is reachable;
add the automatic registration beside it:

```dart
          unawaited(sl<PushService>().onConnected(config));
```

reading `config` from `sl<ServerConfigStore>().current` and skipping when it is null.

In `android/app/build.gradle.kts`, apply the Google Services plugin:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}
```

with the matching `id("com.google.gms.google-services") version "4.4.3" apply false` in
`android/settings.gradle.kts`'s `plugins` block.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/feature/notification`
Expected: PASS, 3 new tests.

- [ ] **Step 8: Verify, then check it on a device**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 989/989 green.

On a real phone against a real daemon:
- Settings → Notifications shows the switch enabled; turning it on prompts once and lands on
  "You'll be alerted when an agent needs you or a PR is ready.";
- the daemon's `/push/devices` log shows the device;
- an agent that needs input produces a tray notification, and tapping it opens that session.

```bash
git add packages/mobile/lib packages/mobile/test packages/mobile/android packages/mobile/ios packages/mobile/pubspec.yaml packages/mobile/pubspec.lock packages/mobile/.gitignore
git commit -m "feat(mobile): register for FCM push and route notification taps"
```

---
## Milestone verification

M5 is done when, from `packages/mobile`:

- `flutter analyze` → "No issues found!"
- `flutter test` → **986/986 green with Tasks 1–21** (989/989 once the blocked Task 22 lands)
- On a real phone against a real daemon:
  - **Voice** — holding the mic in the chat composer says "Keep holding…", then "Listening…" once the
    microphone is live; speaking fills the strip and releasing drops the transcript into the composer.
    A double-tap latches hands-free until tapped again. The same works in the terminal dock.
    Backgrounding the app closes the microphone.
  - **Preview** — the terminal's globe lights a green dot once the agent generates a page; tapping it
    opens the page in the in-app browser, and the terminal is still attached when you come back. The
    chat menu's "Open preview" reaches the same screen. A session with only a README shows no dot, and
    the globe explains that nothing has been generated yet.
  - **Notifications** — Settings → Notifications → History lists what the daemon has recorded; tapping
    a `needs_input` row opens that session and clears its unread dot; "Mark all read" empties the
    Agents-tab bell badge.
  - **Deep links** — `xcrun simctl openurl booted aomobile://session/<id>` (or
    `adb shell am start -a android.intent.action.VIEW -d aomobile://prs`) opens that screen, both from
    cold start and while the app is running.
  - **Telemetry** — nothing is sent, by design: no sink is configured. Verified by the suite, not on
    the device.
  - **Push** — only after Task 22: the Settings switch registers the device, the daemon lists it, and
    an agent that needs input produces a tray notification whose tap opens that session.

## Ledger rows closed here

| Spec ledger row | Landed as | Note |
|---|---|---|
| `notificationView.test.ts` | `test/feature/notification/logic/notification_view_test.dart` (Task 7) | 1:1. |
| `pushStatus.test.ts` | `test/feature/notification/logic/push_status_test.dart` (Task 8) | 1:1, with two enum names changed for the new runtime (`notPaired`, `notConfigured`). |
| `telemetry/context.test.ts` | `test/core/telemetry/context_test.dart` (Task 2) | 1:1, plus a wire-key assertion. |
| `telemetry/dailyActive.test.ts` | `test/core/telemetry/daily_active_test.dart` (Task 4) | 1:1. |
| `telemetry/rateLimit.test.ts` | `test/core/telemetry/rate_limit_test.dart` (Task 3) | 1:1. |
| `telemetry/sanitize.test.ts` | `test/core/telemetry/sanitize_test.dart` (Task 1) | 1:1, plus a real `CountRule` case Dart can express and TypeScript could not. |
| `telemetry/telemetry.test.ts` | `test/core/telemetry/telemetry_test.dart` (Task 5) | Adapted — no `posthog_flutter`; the sink is the abstract `MobileTelemetryClient` the SDK would implement. |
| `voice/deviceProvider.test.ts` | `test/feature/chat/voice/device_provider_test.dart` (Task 14) | Adapted — `speech_to_text`. The three audio-session/contextual-strings cases are replaced by one listen-options case, and the `speechstart` case by the no-boundary-announced case, because the package exposes neither. |

That is **8 of the spec's 37 rows**, exactly the set the milestone brief assigns to M5. Every other
test this plan adds (the notification data layer and cubit, the push registrar, the voice input cubit,
the preview layer, the deep-link resolver and service, the telemetry runtime and call sites) has no RN
counterpart — it covers Dart-side behavior RN implemented inside React screens, hooks, or the Expo
SDK.

With M5 landed, **35 of the 37 rows are closed**. The two remaining rows for M6's parity sweep are
`appInfo.test.ts` and `harnessLogo.test.ts`, both closed in M0–M2 — M6 confirms the accounting rather
than adding coverage.

## What M5 leaves for later milestones

| Left open | Milestone |
|---|---|
| Wiring `posthog_flutter 5.36.2` behind `MobileTelemetryClient`, once a project key exists | M6 |
| A `feature_used {feature: merge}` capture, once the PR list grows a merge action | M6 |
| Haptics on the mic press, send, kill, restore and mark-all-read | M6 parity sweep decides |
| Simulator detection for `build_mode` (needs `device_info_plus`) | M6 parity sweep decides |
| The coding-vocabulary bias, the two iOS audio-session categories, and the Android silence-timeout intent extras that `speech_to_text` cannot express | M6 parity sweep decides (a different recogniser package, or a platform channel) |
| The Android release `INTERNET` permission and `usesCleartextTraffic` — neither is in the main manifest today, so a release build cannot reach a plain-HTTP daemon | M6 parity sweep |
| Deleting `packages/mobile_rn` | M6 |

## Divergences from RN introduced while implementing

The spec's non-goal is "ported as-is and raised separately", so anything where the Dart behaves
*better* than the RN source has to be written down, or a later reader comparing the two will read it
as a porting error.

| Where | What differs | Why, and what to do about it |
|---|---|---|
| `core/telemetry/rate_limit.dart` — `mergeRateState` | RN (`lib/telemetry/rateLimit.ts`) takes `Math.max` of `minuteStart` and `minuteCount` **independently**, so a restart can pair a fresh minute window with the previous minute's count and immediately report the name as capped. The Dart takes the whole newer minute window and keeps only `dayCount` as a max. | The RN form under-reports events after a restart. The fix is strictly safer (the daily ceiling — the real backstop — still uses `max`), and it landed with a test. **Raise the same bug against `rateLimit.ts`**, and against the desktop sink if it shares the shape (`backend/internal/adapters/telemetry/ratelimit.go`). |
| `feature/notification/logic/notification_view.dart` — `notificationTarget` | RN interpolates the session id raw; the Dart escapes it with `Uri.encodeComponent`. | The Dart consumer (`resolveDeepLinkPath`) decodes, so producer and consumer have to agree. RN's Expo Router consumed the raw path, so RN is self-consistent — this is a port-local requirement, not an RN bug. |

## Execution order and what can be parallelised

The five subsystems are independent of each other; only these orderings are real:

- Tasks 1 → 5 are a chain (each builds on the previous file), and Task 6 needs Task 5.
- Task 9 needs Task 8's `classifyServerFailure` only at Task 12; Tasks 7 and 8 are independent.
- Task 11 needs Tasks 7, 9 and 10. Task 13 needs Tasks 8, 11 and 12.
- Tasks 15 → 16 need Task 14.
- Tasks 18 → 19 need Task 17.
- Task 21 needs Task 20; Task 20 needs `RoutesStrings.notifications` from Task 11 and
  `RoutesStrings.terminal` from M4.
- Task 22 needs Tasks 12, 20 and 21, plus the credentials.

A reviewer can therefore gate telemetry (1–6), notifications and push bookkeeping (7–13), voice
(14–16), preview (17–19) and deep links (20–21) as five separate review units.
