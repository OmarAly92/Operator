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
| `lib/prView.ts` | `lib/feature/pull_request/logic/pr_view.dart` | 1:1 — `prLifecycle`, `mergeReasonLabel`, the headline atom and the badge row. |
| `lib/PRCard.tsx` | `lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pr_card.dart` | 1:1. Neither app has a merge action; the daemon's `prMerge` endpoint is reachable from `pull_request_repository.dart` but no UI calls it, in either tree. |
| `lib/usePRSummaries.ts` | `lib/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart` | The fan-out and its per-session summary cache. |
| `lib/githubLink.ts` | `lib/feature/pull_request/logic/github_link.dart` | 1:1. |
| `lib/openGitHub.ts` | `lib/feature/pull_request/logic/open_github.dart` | Adapted — `url_launcher`. |
| `lib/ProjectSwitcher.tsx` | `lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/project_switcher.dart` | |
| `lib/ProjectPickerSheet.tsx` | `lib/core/widgets/pickers/project_picker_sheet.dart` | In `core/` because the PR tab, the spawn screen and settings all open it. |
| `app/sheets/project.tsx` | `lib/core/widgets/pickers/project_picker_sheet.dart` | The route wrapper collapses into the sheet — `showModalBottomSheet` returns the choice. |
| `app/(tabs)/prs.tsx` | `lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pull_requests_body.dart` | Including the open/merged/all filter and its counts. |
| `lib/orchestratorView.ts` | `lib/feature/orchestrator/logic/orchestrator_view.dart` | 1:1. |
| `app/(tabs)/orchestrator.tsx` | `lib/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_body.dart` | With `orchestrator_card.dart`. |
| `lib/agentPicker.ts` | `lib/feature/spawn/logic/agent_picker.dart` | 1:1. |
| `lib/AgentPickerSheet.tsx` | `lib/core/widgets/pickers/agent_picker_sheet.dart` | In `core/` — spawn and the chat settings sheet both open it. |
| `app/sheets/agent.tsx` | `lib/core/widgets/pickers/agent_picker_sheet.dart` | Route wrapper collapsed, as above. |
| `app/spawn.tsx` | `lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart` | |
| `lib/ThemePickerSheet.tsx` | `lib/core/widgets/pickers/theme_picker_sheet.dart` | |
| `app/sheets/theme.tsx` | `lib/core/widgets/pickers/theme_picker_sheet.dart` | Route wrapper collapsed, as above. |
| `app/(tabs)/settings.tsx` | `lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart` | Daemon settings, theme picker, agent picker, project switcher, the notifications section and disconnect. |
| `lib/chat/api.ts` | `lib/feature/chat/data/data_source/chat_remote_data_source.dart` | Every conversation call. The catalogue calls (`models`, `skills`, `config-options`) are `chat_catalog_model.dart`. |
| `lib/chat/types.ts` | `lib/feature/chat/data/model/conversation_item_model.dart` | With `conversation_turn_model.dart`, `activity_detail_model.dart`, `chat_attachment_model.dart` and `workspace_paths_model.dart`. |
| `lib/chat/sse.ts` | `lib/feature/chat/data/sse.dart` | `takeSseFrames` and `parseSseFrame` as pure functions over a `ResponseType.stream` Dio response. CRLF boundaries, the `id:` fallback for daemons with no `seq`, and dropping malformed `data` all survive. |
| `lib/chat/snapshot.ts` | `lib/feature/chat/data/model/conversation_snapshot_model.dart` | 1:1. |
| `lib/chat/timelineModel.ts` | `lib/feature/chat/logic/timeline_model.dart` | 1:1. |
| `lib/chat/conversationChrome.ts` | `lib/feature/chat/logic/conversation_chrome.dart` | 1:1. |
| `lib/chat/conversationErrors.ts` | `lib/feature/chat/logic/conversation_errors.dart` | 1:1. |
| `lib/chat/elicitationModel.ts` | `lib/feature/chat/logic/elicitation_model.dart` | 1:1. |
| `lib/chat/composerSuggestions.ts` | `lib/feature/chat/logic/composer_suggestions.dart` | 1:1. |
| `lib/chat/markdownBlocks.ts` | `lib/feature/chat/logic/markdown_blocks.dart` | 1:1. |
| `lib/chat/syntaxHighlight.ts` | `lib/feature/chat/logic/syntax_highlight.dart` | 1:1. |
| `lib/chat/ansi.ts` | `lib/feature/chat/logic/ansi.dart` | 1:1. |
| `lib/chat/useConversation.ts` | `lib/feature/chat/presentation/chat_screen/logic/chat_cubit.dart` | The stream lifecycle, reconnect, optimistic send and the pending-request set. Paging is `conversation_pages.dart`. |
| `lib/chat/ChatSessionScreen.tsx` | `lib/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart` | With `chat_meta_bar.dart`, `conversation_banners.dart`, `conversation_menu_sheet.dart` and `conversation_map_sheet.dart`. `MenuRow` is inside the menu sheet. |
| `lib/chat/ChatTimeline.tsx` | `lib/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart` | Split by item type: `timeline_item.dart`, `activity_row.dart`, `activity_run.dart`, `activity_meta.dart`, `turn_summary.dart`, `live_turn_bar.dart`, `plan_card.dart`, `approval_card.dart`, `user_input_card.dart`, `file_change_list.dart`, `inline_banner.dart`, `chat_atoms.dart`. |
| `lib/chat/ChatComposer.tsx` | `lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart` | With `suggestion_sheet.dart`; attachment picking is `logic/attachment_picker.dart`. |
| `lib/chat/ChatMarkdown.tsx` | `lib/feature/chat/presentation/chat_screen/ui/widgets/chat_markdown.dart` | |
| `lib/chat/HighlightedCodeText.tsx` | `lib/feature/chat/presentation/chat_screen/ui/widgets/highlighted_code_text.dart` | |
| `lib/chat/ChatSettingsModal.tsx` | `lib/feature/chat/presentation/chat_screen/ui/widgets/chat_settings_sheet.dart` | Model, mode and config-option pickers. |
| `lib/voice/types.ts` | `lib/feature/chat/voice/voice_types.dart` | 1:1. |
| `lib/voice/deviceProvider.ts` | `lib/feature/chat/voice/device_provider.dart` | Behind the `SpeechRecognizer` seam in `speech_recognizer.dart`. The coding-vocabulary bias, the two iOS audio-session configurations and the Android silence extras are ported via the vendored fork in `packages/mobile/packages/speech_to_text` — pub's `speech_to_text` exposed none of the three, so M6 Tasks 13–17 forked and extended it. |
| `lib/voice/useVoiceInput.ts` | `lib/feature/chat/voice/logic/voice_input_cubit.dart` | Push-to-talk and latched, with the same state machine. |
| `lib/voice/MicKey.tsx` | `lib/feature/chat/voice/ui/mic_key.dart` | With `voice_strip.dart` for the transcript strip. |
| `lib/session/TerminalSessionScreen.tsx` | `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart` | Split by concern: `terminal_surface.dart` (the `xterm.dart` view), `terminal_status_bar.dart`, `terminal_composer.dart`, `terminal_dead_overlay.dart`, `terminal_preview_globe.dart`, `interface_switch_overlay.dart`, `interface_switch_sheet.dart`. The injected CSS/JS that made a WebView usable has no counterpart — the spike passed on `xterm.dart`, so the fallback was never taken. |
| `lib/session/keys.ts` | `lib/feature/terminal/logic/keys.dart` | 1:1. |
| `lib/session/KeyRow.tsx` | `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart` | |
| `lib/session/Composer.tsx` | `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart` | |
| `lib/session/sendRoute.ts` | `lib/feature/terminal/logic/send_route.dart` | 1:1. Filed under `terminal` rather than the spec's `sessions` because the terminal composer is its only consumer. |
| `lib/session/keyboardInset.ts` | `lib/feature/chat/logic/keyboard_inset.dart` | Adapted — `MediaQuery.viewInsets`. |
| `lib/session/useInterfaceTransition.ts` | `lib/feature/terminal/logic/interface_transition.dart` | With `interface_switch_cubit.dart` driving it. |
| `app/shell/[handleId].tsx` | `lib/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart` | |
| `app/preview/[id].tsx` | `lib/feature/preview/presentation/preview_screen/ui/widgets/preview_body.dart` | With `preview_browser.dart` wrapping `webview_flutter`, and `logic/preview_url.dart` for `mobileReachablePreviewURL`. |
| `lib/notificationView.ts` | `lib/feature/notification/logic/notification_view.dart` | 1:1, except `notificationTarget` percent-encodes the session id — see "Divergences". |
| `lib/pushStatus.ts` | `lib/feature/notification/logic/push_status.dart` | 1:1, with two enum names changed for the Flutter runtime (`notPaired`, `notConfigured`). |
| `lib/push.ts` | `lib/feature/notification/logic/push_registration.dart` | The registration decision and its bookkeeping, behind the `PushTokenSource` seam in `push_token_source.dart`. **No FCM/APNs SDK is wired** — see "What outlives the port". |
| `lib/PushManager.tsx` | `lib/feature/notification/logic/push_registrar.dart` | |
| `app/notifications.tsx` | `lib/feature/notification/presentation/notifications_screen/ui/widgets/notifications_body.dart` | With `notification_row.dart` and `notification_bell.dart`. |
| `app/_layout.tsx` | `lib/main.dart` | Providers, the deep-link listener and the navigator key. |
| `app/(tabs)/_layout.tsx` | `lib/core/app_routes/home_shell.dart` | The four-tab bar, its `tabPress` selection haptic, and the re-tap-to-scroll-to-top gesture. |

## Test files

The spec's ledger named a destination for each of the 37 RN test files. Five landed elsewhere; the
column below is where they actually are, and the note says why it moved.

| RN test | Dart test | Note |
|---|---|---|
| `lib/agentPicker.test.ts` | `test/feature/spawn/logic/agent_picker_test.dart` | 1:1. |
| `lib/agentsView.test.ts` | `test/feature/sessions/logic/agents_view_test.dart` | 1:1. |
| `lib/appInfo.test.ts` | `test/core/utils/app_info_test.dart` | Adapted — `package_info_plus`. |
| `lib/cameraLens.test.ts` | `test/feature/pairing/logic/camera_lens_test.dart` | Adapted — `mobile_scanner`. |
| `lib/chat/ChatMarkdown.test.ts` | `test/feature/chat/logic/chat_markdown_test.dart` | 1:1. |
| `lib/chat/ansi.test.ts` | `test/feature/chat/logic/ansi_test.dart` | 1:1. |
| `lib/chat/composerSuggestions.test.ts` | `test/feature/chat/logic/composer_suggestions_test.dart` | 1:1. |
| `lib/chat/conversationAction.test.ts` | `test/feature/chat/logic/conversation_action_test.dart` | 1:1. |
| `lib/chat/conversationChrome.test.ts` | `test/feature/chat/logic/conversation_chrome_test.dart` | 1:1. |
| `lib/chat/elicitationModel.test.ts` | `test/feature/chat/logic/elicitation_model_test.dart` | 1:1. |
| `lib/chat/snapshot.test.ts` | `test/feature/chat/logic/snapshot_test.dart` | 1:1. |
| `lib/chat/sse.test.ts` | `test/feature/chat/data/sse_test.dart` | 1:1 — CRLF frames, the `id:` fallback and dropping malformed `data`. |
| `lib/chat/syntaxHighlight.test.ts` | `test/feature/chat/logic/syntax_highlight_test.dart` | 1:1. |
| `lib/chat/timelineModel.test.ts` | `test/feature/chat/logic/timeline_model_test.dart` | 1:1. |
| `lib/chatError.test.ts` | `test/core/error_handling/chat_preflight_test.dart` | **Moved.** The spec predicted `feature/chat/logic/chat_error_test.dart`; the module is a `Failure` classifier used by spawn and orchestrator as well as chat, so it is core. |
| `lib/chatModeApi.test.ts` | `test/feature/chat/data/data_source/chat_remote_data_source_test.dart` | **Moved.** The spec predicted `feature/chat/data/chat_mode_api_test.dart`; there is no separate mode API in Dart — the calls are methods on the chat data source, and `test/feature/chat/presentation/chat_screen/ui/chat_sheets_test.dart` covers the picker that drives them. |
| `lib/connectionError.test.ts` | `test/core/error_handling/connection_error_test.dart` | 1:1. |
| `lib/disconnect.test.ts` | `test/feature/pairing/logic/disconnect_test.dart` | 1:1. |
| `lib/githubLink.test.ts` | `test/feature/pull_request/logic/github_link_test.dart` | 1:1. |
| `lib/harnessLogo.test.ts` | `test/feature/sessions/logic/harness_logo_test.dart` | **Moved.** The spec predicted `core/utils/`; the board is the only consumer, so it lives with it. |
| `lib/notificationView.test.ts` | `test/feature/notification/logic/notification_view_test.dart` | 1:1. |
| `lib/onboarding.test.ts` | `test/feature/onboarding/logic/onboarding_test.dart` | 1:1. |
| `lib/orchestratorView.test.ts` | `test/feature/orchestrator/logic/orchestrator_view_test.dart` | 1:1. |
| `lib/prView.test.ts` | `test/feature/pull_request/logic/pr_view_test.dart` | 1:1. |
| `lib/pushStatus.test.ts` | `test/feature/notification/logic/push_status_test.dart` | 1:1, two enum names changed. |
| `lib/session/keyboardInset.test.ts` | `test/feature/chat/logic/keyboard_inset_test.dart` | Adapted — `MediaQuery.viewInsets`. |
| `lib/session/sendRoute.test.ts` | `test/feature/terminal/logic/send_route_test.dart` | **Moved.** The spec predicted `feature/sessions/`; the terminal composer is the only consumer. |
| `lib/sessionStatus.test.ts` | `test/feature/sessions/logic/session_status_test.dart` | 1:1. |
| `lib/sheetResult.test.ts` | OMITTED | **The only dropped row, and the module it covers is dropped with it.** It tests parking and releasing a callback in a module-level map — a mechanism `Navigator.push<T>`'s return value makes unnecessary. There is no Dart code to cover. The behavior it protected (a sheet dismissed without a choice must not leak its closure) is a property of the framework here, not of our code. |
| `lib/telemetry/context.test.ts` | `test/core/telemetry/context_test.dart` | 1:1, plus a wire-key assertion. |
| `lib/telemetry/dailyActive.test.ts` | `test/core/telemetry/daily_active_test.dart` | 1:1. |
| `lib/telemetry/rateLimit.test.ts` | `test/core/telemetry/rate_limit_test.dart` | 1:1, plus the restart case in "Divergences". |
| `lib/telemetry/sanitize.test.ts` | `test/core/telemetry/sanitize_test.dart` | 1:1, plus a `CountRule` case Dart can express and TypeScript could not. |
| `lib/telemetry/telemetry.test.ts` | `test/core/telemetry/telemetry_test.dart` | Adapted — the sink is the abstract `MobileTelemetryClient`. |
| `lib/theme.test.ts` | `test/core/app_themes/skin_test.dart` | Extended — pins the `rgba()`→8-digit-ARGB conversions. |
| `lib/themePreference.test.ts` | `test/core/app_themes/skin_cubit_test.dart` | `bloc_test`. |
| `lib/voice/deviceProvider.test.ts` | `test/feature/chat/voice/device_provider_test.dart` | Adapted — the vendored `speech_to_text`. |

**36 ported, 1 dropped with its module, 37 accounted for.**

## Open gaps

Behaviors the sweep found in the RN tree with no Dart counterpart. Each is closed before the RN tree
is deleted.

| Gap | RN source | Status |
|---|---|---|
| Haptic feedback | `lib/haptics.ts` and 65 call sites | Closed — M6 Tasks 7–10 |
| Re-tapping the active tab scrolls it to the top | `lib/useTabScrollToTop.ts`, all four tabs | Closed — M6 Task 11 |
| `build_mode` can never report `simulator` | `lib/telemetry/context.ts` vs `lib/main.dart:33` | Closed — M6 Task 12 |
| Coding-vocabulary bias, the two iOS audio sessions, the Android silence extras | `lib/voice/deviceProvider.ts` | Closed — M6 Tasks 13–17 |

## Divergences from RN

The port's rule was "ported as-is; where the RN behavior looks wrong, port it and raise it
separately". These are the places the Dart deliberately does something else.

| Where | What differs | Why |
|---|---|---|
| `core/telemetry/rate_limit.dart` — `mergeRateState` | RN (`lib/telemetry/rateLimit.ts`) takes `Math.max` of `minuteStart` and `minuteCount` independently, so a restart can pair a fresh minute window with the previous minute's count and immediately report a name as capped. The Dart takes the whole newer minute window and keeps only `dayCount` as a max. | The RN form under-reports events after a restart. The daily ceiling — the real backstop — still uses `max`. **The same bug should be raised against `rateLimit.ts` and against the desktop sink if it shares the shape (`backend/internal/adapters/telemetry/ratelimit.go`).** |
| `feature/notification/logic/notification_view.dart` — `notificationTarget` | RN interpolates the session id raw; the Dart percent-encodes it. | The Dart consumer (`resolveDeepLinkPath`) decodes, so producer and consumer have to agree. RN's Expo Router consumed the raw path, so RN was self-consistent — this is port-local, not an RN bug. |
| `core/utils/haptics.dart` — `success`/`warning`/`error` on Android | `expo-haptics` maps notification feedback to Android's own patterns; the Dart uses `VibrationEffect` predefined effects, and `success` and `error` currently share `EFFECT_DOUBLE_CLICK`. | Android has no notification-feedback API. iOS is exact; Android is the closest stock approximation. If the two ever need to be distinguishable by feel, that is a waveform, not a predefined effect. |
| `feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_sheet.dart` — no haptic on "Stop and switch" | An M6 Task 10 pass initially wired `Haptics.warning()` there, attributed (per the plan's own mapping table) to `TerminalSessionScreen.tsx:1052`. Reading that line showed it belongs to the *kill*-confirmation dialog (already correctly wired in `terminal_body.dart`'s `_confirmKill`), not this sheet — RN's actual `requestInterfaceSwitch` confirmation (`TerminalSessionScreen.tsx:964-989`) has no haptics call at all. | The invented haptic was removed to keep strict parity — RN really does leave this one silent. |

## What outlives the port

Work that is deliberately not done, recorded so it is not rediscovered as a bug.

| Item | Why it is not done | What it needs |
|---|---|---|
| The PostHog sink behind `MobileTelemetryClient` | No project key exists — the desktop app dropped its own in `8ec08116e`, so a wired SDK would send nothing. Everything in front of the sink is built and tested: the sanitizer, the rate limiter, the daily-active tracker, the closed event vocabulary and the context builder. | A project key, then one file implementing `MobileTelemetryClient` over `posthog_flutter` and one line in `main.dart` passing it to `TelemetryRuntime.init`. |
| FCM/APNs push registration | A Firebase project, `google-services.json` and an APNs key are credentials only the repository owner can create. The decision logic is built and tested behind the `PushTokenSource` seam: `push_registrar.dart`, `push_registration.dart`, `push_status.dart`. Settings shows the switch and its state. | The credentials, then a `PushTokenSource` implementation over `firebase_messaging` and a tap handler routing through `DeepLinkService`. |
| A `feature_used {feature: merge}` capture | Not a gap. Neither app has a merge action — `lib/PRCard.tsx` and `app/(tabs)/prs.tsx` never called the endpoint. The allowlist keeps `merge` in its closed vocabulary so the event needs no schema change if a button ever lands. | A merge button, which would be a new feature, not a port. |
| The `speech_to_text` fork's upstream drift | `packages/mobile/packages/speech_to_text` is pinned at 7.4.0 with four changed files (`SpeechListenOptions`, the method-channel argument map, `SpeechToTextPlugin.swift`, `SpeechToTextPlugin.kt`), plus its sibling `speech_to_text_platform_interface` (`speech_to_text_platform_interface.dart`, `method_channel_speech_to_text.dart`). | On upgrade, re-apply the diff described in `packages/speech_to_text/FORK.md`. |
| `setupRecognizerIntent`'s Android result cache does not track the two new listen options | Its existing `previousXxx`-field cache (added upstream, before the fork) skips rebuilding the recognizer intent when language/partialResults/listenMode/pauseFor are unchanged from the previous call — it was never widened to also key on `contextualStrings`/`possiblyCompleteSilence`. Inert today because this app's only caller (`speech_recognizer.dart`) always passes the same constant vocabulary and the same `10000`ms value on every call. | If a future caller ever varies either value between calls, add them to the cache-invalidation check in `SpeechToTextPlugin.kt`'s `setupRecognizerIntent`. |

## Native configuration inherited from `app.json`

The RN app kept its native configuration in `app.json`. When that stopped being the source of
truth, three settings had to be restated in the Flutter project (`0548efe28`):

- `android:usesCleartextTraffic="true"` and the `INTERNET` permission in the **main** manifest —
  only the debug and profile manifests declared `INTERNET`, so a release build could not open a
  socket to the daemon.
- `NSAllowsLocalNetworking` and `NSLocalNetworkUsageDescription` in `ios/Runner/Info.plist` —
  without them App Transport Security blocks plain HTTP to a LAN address, and iOS 14+ refuses local
  network access entirely.
- `VIBRATE` on Android, added at M6 with the haptics channel.

## Build environment fixes M6 turned up

None of these are RN-parity gaps — they are pre-existing checkout/toolchain issues that no
milestone before M6 had triggered, because M6 was the first to run `flutter build ios` and
`flutter build apk` rather than only `flutter analyze`/`flutter test`.

- `ios/Runner/HapticsPlugin.swift` (M6 Task 7) existed on disk but was never added to
  `ios/Runner.xcodeproj/project.pbxproj`'s Sources build phase, so no iOS build had ever actually
  compiled it. Fixed at Task 15, the first task to run `flutter build ios`.
- `android/app/build.gradle.kts` compiled against Flutter's bundled default `compileSdk` (36),
  which two pre-existing dependencies (`flutter_secure_storage`, `permission_handler_android`)
  outgrew — they now require 37. No Android build had succeeded on this checkout since
  scaffolding. Fixed at Task 16 by hardcoding `compileSdk = 37`, the first task to run
  `flutter build apk`.
