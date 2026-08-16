# Mobile parity ledger

**Date:** 2026-08-16
**Status:** the accounting that closed the Flutter mobile port

`packages/mobile` replaced an Expo/React Native app of 99 source files and 37 test files. This
ledger records where each one went. It exists because `packages/mobile_rn` was deleted at M6 —
without it, the port's decisions would survive only in `git show`.

A destination of `OMITTED` means the file has no Dart counterpart **on purpose**, and the note says
why. An omission is one of three things: the platform makes it unnecessary, the behavior belongs to
a subsystem deliberately left for later, or it is Expo plumbing with no product meaning.

`packages/mobile/test/parity_ledger_test.dart` verifies this document against both trees. It was
deleted with the RN tree at M6; the tables below are its final output.

## Source files

| RN source | Dart destination | Note |
|---|---|---|
| `lib/config.ts` | `lib/core/api/server_config.dart` | `ServerConfig` plus `normalizeServerHost`, `httpBase`, `muxUrl`, `isConfigured`. The `useServerConfig` hook becomes `ServerConfigStore`; the AsyncStorage→SecureStore password migration is not ported because no Flutter build ever wrote a password to `shared_preferences`. |
| `lib/api.ts` | `lib/core/api/api_request_helpers/end_points.dart` | The path catalogue. The 674 lines of fetch wrappers are the 11 `*_remote_data_source.dart` files; `ApiError` is `ServerFailure`. |
| `lib/mux.ts` | `lib/core/mux/mux_client.dart` | Protocol-for-protocol, with `mux_socket.dart` and `mux_backoff.dart` splitting out the transport and the retry curve. |
| `lib/connectionError.ts` | `lib/core/error_handling/connection_error.dart` | 1:1. |
| `lib/chatError.ts` | `lib/core/error_handling/chat_preflight.dart` | Renamed on the way: the module is about preflight codes, not chat errors generally. `isChatPreflightError` became `isChatPreflightFailure` because it takes a `Failure`, not an `Error`. |
| `lib/agentError.ts` | `lib/core/error_handling/connection_error.dart` | Its whole body is one call to `describeConnectionFailure(classifyConnectionFailure(status))`. In Dart that composition is at the call site; a one-line indirection whose only reason for existing in RN was reading `Platform.OS` outside a pure module carries nothing over. |
| `lib/theme.ts` | `lib/core/app_themes/colors/app_skin.dart` | The 31 tokens, with `light_skin.dart` / `dark_skin.dart` holding the values and `terminal_palette.dart` the terminal's own palette. |
| `lib/themePreference.ts` | `lib/core/app_themes/colors/theme_preference.dart` | 1:1. |
| `lib/themeStore.ts` | `lib/core/app_themes/colors/logic/skin_cubit.dart` | Persistence through `CacheHelper`. |
| `lib/ThemeProvider.tsx` | `lib/core/app_themes/colors/skin_scope.dart` | `SkinScope` `InheritedWidget` plus the `context.skin` extension. |
| `lib/appInfo.ts` | `lib/core/utils/app_info.dart` | Adapted — `package_info_plus`. |
| `lib/haptics.ts` | `lib/core/utils/haptics.dart` | The same five verbs. `tap` and `select` reach Flutter's `HapticFeedback`; `success`, `warning` and `error` reach a first-party `operator/haptics` channel, because Flutter exposes no notification-feedback API. |
| `lib/useTabScrollToTop.ts` | `lib/core/app_routes/home_shell.dart` | The shell owns the four controllers and animates the active tab's list to zero when its tab is re-tapped. |
| `lib/sheetResult.ts` | OMITTED | Structurally unnecessary. It exists only because an Expo Router route cannot be handed an `onSelect` callback, so the opener parks the closure in a module-level map and passes a key as a route param. Flutter's `Navigator.push<T>` returns a `Future<T>`, so the sheet's result comes back to the caller directly. The three route builders (`projectSheetRoute`, `agentSheetRoute`, `connectSheetRoute`) are the three `showModalBottomSheet` call sites in `core/widgets/pickers/`. |
| `lib/ui.tsx` | `lib/core/widgets` | `Pill`→`app_pill.dart`, `Card`→`app_container.dart`, `Button`→`primary_button.dart`, `EmptyState`→`app_empty_state.dart`, `SettingsGroup`→`settings_group.dart`, `ScreenHeader`/`HeaderIconButton`→`global_appbar.dart`, `SheetScreen`/`SheetHeader`→`app_dialog.dart`. `Dot`, `StatusBadge`, `Chip`, `SectionHeader`, `SettingsRow`, `SettingsToggle`, `NumberedStep` and `IconButton` live with their single consumer rather than in `core/`. |
| `lib/telemetry/config.ts` | `lib/core/telemetry/runtime.dart` | `TelemetryConfig`, reading `String.fromEnvironment` instead of `process.env`. |
| `lib/telemetry/context.ts` | `lib/core/telemetry/context.dart` | 1:1. |
| `lib/telemetry/dailyActive.ts` | `lib/core/telemetry/daily_active.dart` | 1:1. |
| `lib/telemetry/events.ts` | `lib/core/telemetry/events.dart` | 1:1, closed vocabulary preserved. |
| `lib/telemetry/rateLimit.ts` | `lib/core/telemetry/rate_limit.dart` | 1:1 apart from `mergeRateState`, which fixes a restart bug in the RN version — see "Divergences" below. |
| `lib/telemetry/runtime.ts` | `lib/core/telemetry/runtime.dart` | `TelemetryRuntime`. |
| `lib/telemetry/sanitize.ts` | `lib/core/telemetry/sanitize.dart` | 1:1. |
| `lib/telemetry/telemetry.ts` | `lib/core/telemetry/telemetry.dart` | The sink is the abstract `MobileTelemetryClient`. No PostHog SDK is wired — see "What outlives the port". |
| `lib/TelemetryManager.tsx` | `lib/main.dart` | `TelemetryRuntime.init` at startup and `AppLifecycleListener(onResume:)` for the daily-active ping. |
| `lib/pairing.ts` | `lib/feature/pairing/logic/pairing_payload.dart` | QR payload parse. |
| `lib/cameraLens.ts` | `lib/feature/pairing/logic/camera_lens.dart` | Adapted — `mobile_scanner` instead of `expo-camera`. |
| `lib/disconnect.ts` | `lib/feature/pairing/logic/disconnect.dart` | 1:1. |
| `lib/ManualConnectSheet.tsx` | `lib/feature/pairing/presentation/manual_connect_screen/ui/widgets/manual_connect_body.dart` | A sheet in RN, a screen in Dart — `Navigator.push` returns the result, so it needs no `sheetResult` key. Its logic is `manual_connect_cubit.dart`. |
| `app/pair.tsx` | `lib/feature/pairing/presentation/pairing_scan_screen/ui/widgets/pairing_scan_body.dart` | With `camera_permission_gate.dart` and `connection_failure_banner.dart`. |
| `app/sheets/connect.tsx` | `lib/feature/pairing/presentation/manual_connect_screen/ui/manual_connect_screen.dart` | The route wrapper; see `sheetResult.ts` for why the sheet-route indirection is gone. |
| `lib/onboarding.ts` | `lib/feature/onboarding/logic/onboarding.dart` | 1:1. |
| `lib/onboardingStore.ts` | `lib/feature/onboarding/logic/onboarding.dart` | Persistence collapsed into the same file; it is one `CacheHelper` key. |
| `lib/OnboardingGate.tsx` | `lib/main.dart` | The gate is the `initialRoute` computation in `main`. |
| `app/onboarding.tsx` | `lib/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart` | With `onboarding_step.dart` for `ui.tsx`'s `NumberedStep`. |
| `lib/store.tsx` | `lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart` | The board poll, its sequential auth probe, and the unread-count tick. `ConnStatus` is `SessionsState`; the React context is the cubit. |
| `lib/sessionStatus.ts` | `lib/feature/sessions/logic/session_status.dart` | 1:1, with `status_visual.dart` holding the hue mapping. |
| `lib/agentsView.ts` | `lib/feature/sessions/logic/agents_view.dart` | 1:1. |
| `lib/harnessLogo.ts` | `lib/feature/sessions/logic/harness_logo.dart` | 1:1. Filed under `sessions` rather than the spec's `core/utils` because the board is its only consumer. |
| `lib/harnessLogoAssets.ts` | `lib/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart` | The asset map is the widget's lookup; the SVGs are `packages/mobile/assets`. |
| `lib/AgentLogo.tsx` | `lib/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart` | `flutter_svg`. |
| `lib/SessionCard.tsx` | `lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart` | With `session_section_header.dart` and `sessions_stats_row.dart` for the `SectionList` chrome. |
| `app/(tabs)/index.tsx` | `lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart` | The Kanban tab, plus `session_actions_sheet.dart` for kill/restore/resume. |
| `app/session/[id].tsx` | `lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart` | The chat-or-terminal fork. |
