# Flutter mobile port — design

**Date:** 2026-08-12
**Status:** approved design, pending implementation plan
**Scope:** replace the Expo/React Native app in `packages/mobile` with a Flutter app at full parity

## Context

`packages/mobile` is an Expo/React Native thin client for the Operator daemon: ~19,000 lines
across 138 TypeScript files and 17 routes. It runs no agents itself — it talks to the daemon
over the LAN or Tailscale via REST, one multiplexed WebSocket, and SSE for chat.

This design replaces it with a Flutter app that reproduces its behavior and its visual design,
built to the conventions in the `flutter-knowledge` skill, mirroring the core layer of
`~/development/projects/dont_say`.

### Decisions taken

| Decision | Choice |
|---|---|
| Spec granularity | One spec covering the whole app |
| Tests | All 37 RN test files mirrored |
| Core layer | Mirrored from `dont_say/lib/core` |
| Skin | `dont_say`'s mechanism, Operator's tokens |
| Placement | Flutter at `packages/mobile`; RN moves to `packages/mobile_rn` until M6 |
| Subsystem scope | Terminal, push, voice, telemetry all in scope |
| Sequencing | Walking skeleton, logic-and-tests first within each slice |
| Terminal renderer | `xterm.dart`, with a defined fallback to `webview_flutter` + xterm.js |

### Non-goals

- No behavior changes. Where current behavior looks wrong, it is ported as-is and raised separately.
- No `drift`. The app is a thin client with nothing relational to cache. If that changes,
  the `drift-local-database` skill governs that layer — it is not to be improvised.
- No new features, no redesign, no screens that do not exist today.

## Architecture

Flutter project at `packages/mobile`, pubspec name `operator_mobile`. `lib/core/` mirrors
`dont_say`. Features live under `lib/feature/<feature>/` per the conventions, with presentation
directories suffixed `_screen`.

The RN app's 17 routes collapse into 11 features, grouped by which piece of daemon state they
own rather than by screen:

| Feature | Covers |
|---|---|
| `pairing` | QR scan, manual connect, `ServerConfig` persistence, ping |
| `onboarding` | first-run gate ahead of pairing |
| `sessions` | Kanban tab: session list, cards, kill/restore/resume |
| `pull_request` | PRs tab: summaries, failing checks, conflicts, merge |
| `orchestrator` | orchestrator tab: links, launch |
| `spawn` | new-session flow, agent and project pickers |
| `chat` | timeline, SSE stream, composer, attachments, voice, elicitation |
| `terminal` | TUI session and shell over the mux socket |
| `preview` | in-app preview browser |
| `notification` | list, mark-read, push registration and permission status |
| `settings` | daemon settings, theme picker, agent picker, project switcher |

Two things are cross-cutting and live in `core/`, not in a feature:

- **`MuxClient`** — the Kanban board depends on the same socket as the terminal for session
  patches. Nesting it under `terminal/` would make the board's liveness depend on a feature it
  has no business knowing about.
- **Telemetry** — used from every feature.

Both are registered as lazy singletons in `service_locator`, in a `_coreSetup()` method; each
feature gets its own `_<feature>FeatureSetup()`.

`chat` is the largest feature (29 files in RN) and is expected to stay largest.

## Data layer

### `ServerConfig` is the spine

Every data source needs the paired host, port and secret, and the API base URL is unknown until
pairing completes. `pairing` owns `ServerConfig` — host, `httpPort`, `secure`, `password` —
persisted with `flutter_secure_storage` for the password and `shared_preferences` for the rest.

A `ServerConfigStore` singleton holds the current config, and a Dio interceptor stamps the base
URL and `Authorization` header per request. Data sources never see it. This is the one expected
deviation from `dont_say`'s core, which assumes a compile-time host.

### Response envelope

The daemon does not use the `GlobalResponse` `data` key. `/projects` returns `{projects: [...]}`
directly, so every parse is `GlobalResponse.fromJson(response.data, withDataKey: false)`.

Errors are a locked envelope: `{error, code, message, requestId}`.

- `code` is machine-readable (e.g. `SESSION_AWAITING_DECISION`) and the UI branches on it.
- `requestId` correlates a client failure with daemon logs.

`core/error_handling/dio_error_handler` maps both onto `ServerFailure` rather than flattening to
a message string. Discarding `requestId` is a regression, not a simplification.

### Two load-bearing behaviors

**12-second request timeout.** Set as Dio's `connectTimeout` and `receiveTimeout`. Over Tailscale
a sleeping host otherwise hangs for the OS TCP timeout (75–120s), freezing Kill, send, and the
poll loop.

**Sequential auth probing.** The daemon locks a device out for a minute after 5 failed auths.
The session repository probes `/sessions` alone before fanning out to other calls, because a
stale password otherwise burns 4 failures per poll tick and arms the lockout before the user can
re-pair. Converting this to `Future.wait` reintroduces the bug silently, so a mirrored test pins
the call order.

### Shapes

- ~12 models as `XModel` in `data/model/`, **all fields nullable**, `fromJson` performing the
  wire→domain mapping the RN client does inline (`mapProjectKind` and equivalents).
- ~20 params classes in `data/model/params/`, **one per method**, never shared even where fields
  overlap: `SpawnSessionParams`, `LaunchOrchestratorParams`, `RegisterPushDeviceParams`,
  `GetNotificationsParams`, and so on.
- 11 data sources: abstract + `Imp` over `ApiConsumer`, catching nothing, letting `Failure` bubble.
- 11 repositories returning `FutureResult<GlobalResponse<T>>` gated on `NetworkStatus`, offline
  short-circuiting to `ServerFailure.noNetwork()`.
- Parameterized paths get static methods on `EndPoints` (`EndPoints.sessionPr(sessionId)`).
  Interpolating at the call site is forbidden.

## Skin and typography

### Mechanism, mirrored

`AppSkin` abstract class, `const LightSkin()` / `const DarkSkin()`, `SkinScope` `InheritedWidget`
with the `context.skin` extension, `SkinCubit` holding the skin and persisting through
`CacheHelper`, and `AppThemes.fromSkin(skin)` building `ThemeData`. `dont_say`'s cubit already
handles system/light/dark with an OS-brightness fallback — the same three modes
`ThemeProvider.tsx` supports, so the theme picker maps one-to-one.

### Tokens, from Operator

The 32 tokens in `packages/mobile_rn/lib/theme.ts`, keeping their existing names so Dart getters
grep directly against the RN source during the port:

`bgBase`, `bgSide`, `bgColumn`, `bgSurface`, `bgElevated`, `bgElevatedHover`, `bgSubtle`;
`textPrimary`, `textSecondary`, `textTertiary`, `textFaint`; `borderSubtle`, `borderDefault`,
`borderStrong`; `blue`, `orange`, `amber`, `red`, `purple`, `green`; `tintBlue`, `tintOrange`,
`tintAmber`, `tintRed`, `tintGreen`, `tintPurple`; `onAccent`, `scrim`, `accent`, `accentTint`,
`attention`.

That is 31 `Color` getters — `fontMono` is a font family and belongs to `AppTextStyle`.

The state hues carry meaning and must not be renamed to generic roles:

> blue = the conductor · orange = a working agent · amber = needs your input · red = failing ·
> green = passed · purple = merged

`dont_say`'s ~126 skin members are its own finance domain (`categoryFood`, `income`,
`heroGradient`). They are not carried over. A thin derived layer is added on top of the 31 base
tokens — `appBarBackground => bgSurface`, `navBarBackground => bgSurface`,
`textFieldFill => bgElevated` — but only for getters with a real call site.

Values are lifted verbatim from both palettes, with one mechanical conversion: `theme.ts` mixes
hex (`#0a0b0d`) with `rgba(255,255,255,0.04)` for subtle surfaces and every border. Those become
full 8-digit ARGB (`Color(0x0AFFFFFF)`). Transcription bugs hide here, so the skin test asserts
known pairs.

### Typography

The RN app has no scale; components inline `fontSize`/`fontWeight`. Measured usage:

- sizes: 11 (57 uses), 12 (40), 13 (39), 10 (29), 15 (21), 17 (10), 14 (10), 9 (8), 8 (6),
  16 (5), with one-offs at 19, 24, 26, 32
- weights: 700 (54), 600 (39), 800 (6), 500 (5)

`AppTextStyle` therefore provides `style9`–`style17` in Regular/Medium/SemiBold/Bold plus the
large one-offs, following `dont_say`'s `style<Size><Weight>` naming, and a parallel
`mono<Size><Weight>` set for the `fontMono` call sites (PR numbers, diff counts, terminal chrome).

Sizes 8–13 dominating is a real property of a dense, information-first phone UI. Rounding up to a
conventional Material scale would visibly change the design being preserved.

Feature code never imports `flutter_screenutil`. Spacing, padding and radii take raw ints.

## Realtime

### Mux socket

One WebSocket multiplexing three channels, ported protocol-for-protocol from `mux.ts`:

- `subscribe` — topics `sessions`, `notifications`
- `terminal` — `open` (with `role: "secondary"`), `data` (base64), `resize`, `close`
- `system` — ping heartbeat on an interval

Auto-reconnect with backoff from 1s, and the client tracks which terminals *should* be open so it
can re-open them after a reconnect.

In Dart: a `MuxClient` singleton over `web_socket_channel` exposing broadcast streams —
`Stream<SessionPatch>`, `Stream<NotificationEvent>`, and a per-handle `Stream<Uint8List>` for
terminal output. Cubits subscribe; nothing else touches the socket.

### SSE

Chat streams conversation events over SSE. `sse.ts` is hand-rolled — `takeSseFrames` (pull
complete frames, preserve an incomplete tail) and `parseSseFrame` — and its three tests encode
field experience that must survive the port:

- proxies send **CRLF** frame boundaries
- older daemons omit `seq`, so the SSE `id:` is the fallback
- malformed `data` is dropped, not thrown

Dart has no `EventSource` on mobile, so these port as pure functions over a
`ResponseType.stream` Dio response, with their tests mirrored before the implementation.

## Terminal

Renderer is `xterm.dart`. The spike is the first task of M4 and is bounded to a throwaway
prototype that renders a live shell and nothing else — no feature integration, no state
management, deleted once the decision is made. It passes only if all four criteria hold,
measured against current behavior:

1. **Gesture parity** — scroll, and pinch-zoom between shrink-to-fit overview and 1:1
2. **PTY fit negotiation** — report the phone's natural grid so the daemon can size the PTY when
   the phone is the sole viewer; scale-to-fit when a desktop viewer owns the authoritative size
3. **Output bursts** stay smooth under a fast-scrolling build log
4. **Selection and copy** work

If any criterion fails, the fallback is `webview_flutter` + xterm.js, porting the existing
injected CSS/JS from `TerminalSessionScreen.tsx` (1,529 lines, much of it working around the
WebView: disabling `.xterm-screen` touch handling, hiding the WebView scrollbar so fit math is
not off by a column, `proposeDimensions` measurement).

Either way the transport, mux client and resize negotiation are identical. The seam is a
`TerminalView` widget contract, so taking the fallback swaps one widget, not the feature.

## Testing

All 37 RN test files are mirrored. "Mirror" means equivalent behavioral coverage — 1:1 where the
logic is platform-neutral, adapted where the test targets an Expo API with a different Flutter
counterpart. Cubits get `bloc_test`; pure logic gets plain unit tests. The `flutter-testing`
skill governs layout and mocking and is invoked before the first test is written.

| RN test file | Dart destination | Note |
|---|---|---|
| `agentPicker.test.ts` | `test/feature/spawn/logic/agent_picker_test.dart` | 1:1 |
| `agentsView.test.ts` | `test/feature/sessions/logic/agents_view_test.dart` | 1:1 |
| `appInfo.test.ts` | `test/core/utils/app_info_test.dart` | adapted — `package_info_plus` |
| `cameraLens.test.ts` | `test/feature/pairing/logic/camera_lens_test.dart` | adapted — `mobile_scanner` |
| `chat/ChatMarkdown.test.ts` | `test/feature/chat/logic/chat_markdown_test.dart` | 1:1 |
| `chat/ansi.test.ts` | `test/feature/chat/logic/ansi_test.dart` | 1:1 |
| `chat/composerSuggestions.test.ts` | `test/feature/chat/logic/composer_suggestions_test.dart` | 1:1 |
| `chat/conversationAction.test.ts` | `test/feature/chat/logic/conversation_action_test.dart` | 1:1 |
| `chat/conversationChrome.test.ts` | `test/feature/chat/logic/conversation_chrome_test.dart` | 1:1 |
| `chat/elicitationModel.test.ts` | `test/feature/chat/logic/elicitation_model_test.dart` | 1:1 |
| `chat/snapshot.test.ts` | `test/feature/chat/logic/snapshot_test.dart` | 1:1 |
| `chat/sse.test.ts` | `test/feature/chat/data/sse_test.dart` | 1:1 |
| `chat/syntaxHighlight.test.ts` | `test/feature/chat/logic/syntax_highlight_test.dart` | 1:1 |
| `chat/timelineModel.test.ts` | `test/feature/chat/logic/timeline_model_test.dart` | 1:1 |
| `chatError.test.ts` | `test/feature/chat/logic/chat_error_test.dart` | 1:1 |
| `chatModeApi.test.ts` | `test/feature/chat/data/chat_mode_api_test.dart` | 1:1 |
| `connectionError.test.ts` | `test/core/error_handling/connection_error_test.dart` | 1:1 |
| `disconnect.test.ts` | `test/feature/pairing/logic/disconnect_test.dart` | 1:1 |
| `githubLink.test.ts` | `test/feature/pull_request/logic/github_link_test.dart` | 1:1 |
| `harnessLogo.test.ts` | `test/core/utils/harness_logo_test.dart` | 1:1 |
| `notificationView.test.ts` | `test/feature/notification/logic/notification_view_test.dart` | 1:1 |
| `onboarding.test.ts` | `test/feature/onboarding/logic/onboarding_test.dart` | 1:1 |
| `orchestratorView.test.ts` | `test/feature/orchestrator/logic/orchestrator_view_test.dart` | 1:1 |
| `prView.test.ts` | `test/feature/pull_request/logic/pr_view_test.dart` | 1:1 |
| `pushStatus.test.ts` | `test/feature/notification/logic/push_status_test.dart` | 1:1 |
| `session/keyboardInset.test.ts` | `test/feature/chat/logic/keyboard_inset_test.dart` | adapted — `MediaQuery.viewInsets` |
| `session/sendRoute.test.ts` | `test/feature/sessions/logic/send_route_test.dart` | 1:1 |
| `sessionStatus.test.ts` | `test/feature/sessions/logic/session_status_test.dart` | 1:1 |
| `sheetResult.test.ts` | `test/core/utils/sheet_result_test.dart` | 1:1 |
| `telemetry/context.test.ts` | `test/core/telemetry/context_test.dart` | 1:1 |
| `telemetry/dailyActive.test.ts` | `test/core/telemetry/daily_active_test.dart` | 1:1 |
| `telemetry/rateLimit.test.ts` | `test/core/telemetry/rate_limit_test.dart` | 1:1 |
| `telemetry/sanitize.test.ts` | `test/core/telemetry/sanitize_test.dart` | 1:1 |
| `telemetry/telemetry.test.ts` | `test/core/telemetry/telemetry_test.dart` | adapted — `posthog_flutter` |
| `theme.test.ts` | `test/core/app_themes/skin_test.dart` | extended — pins ARGB conversions |
| `themePreference.test.ts` | `test/core/app_themes/skin_cubit_test.dart` | `bloc_test` |
| `voice/deviceProvider.test.ts` | `test/feature/chat/voice/device_provider_test.dart` | adapted — `speech_to_text` |

Verification after every change: `flutter analyze` clean, `flutter test` green. The app is not
run or built as part of implementation.

## Build order

| # | Milestone | Done when |
|---|---|---|
| M0 | `git mv packages/mobile packages/mobile_rn` with its CI disabled; Flutter project at `packages/mobile`; `lib/core` mirrored; skin and `AppTextStyle`; DI; router; CI switched to `flutter analyze` / `flutter test` | Skin tests green |
| M1 | Walking skeleton: pairing (QR + manual) → sessions → Kanban | Runs against a real daemon on a real phone |
| M2 | Breadth on the spine: PRs, orchestrator, spawn, settings | Four tabs live |
| M3 | Chat: timeline, SSE, composer, attachments, elicitation | Chat session usable end to end |
| M4 | Terminal: spike against the four criteria, then build | Shell usable, or fallback taken |
| M5 | Push, voice, telemetry, preview, deep links | Device registers for push and receives one; dictation fills the composer; preview opens a session URL; a deep link resolves to its screen |
| M6 | Parity sweep; `packages/mobile_rn` deleted | All 37 ledger rows accounted for |

Within each milestone, any module with RN tests is ported logic-and-test first, before the screen
that consumes it.

`packages/mobile_rn` stays on disk until M6 so the port reads from the source rather than from
`git show`. Its `mobile.yml` workflow is disabled at M0 so a frozen tree cannot fail CI.

## Risks

**Terminal.** The largest unknown, which is why it has explicit fallback criteria rather than an
assumed outcome. `TerminalSessionScreen.tsx` is 1,529 lines of hand-tuned mobile behavior.

**Push.** Needs a Firebase project, `google-services.json`, and APNs keys — credentials only the
repository owner can create. The `pushStatus` logic and its tests port cleanly; the native setup
is the cost and it blocks M5 until those credentials exist.

**Telemetry.** The desktop app now ships no PostHog key (commit `8ec08116e`), so mobile telemetry
collects nothing until a project key is configured. The sanitize/rate-limit/daily-active logic is
still ported and tested — it is the code that decides what would be sent.

**No mobile client during the port.** In-place replacement means there is no shipping phone app
between M0 and M1. The milestone order minimizes that window by making M1 a genuinely usable
slice rather than a scaffold.

**Core churn.** The walking skeleton grows `lib/core` just-in-time, so M2 and M3 will push back on
decisions M1 made. This is accepted in exchange for a running app early.
