# Flutter Mobile Port — M6 (Parity sweep and RN retirement) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Account for every file in the frozen RN tree — either a Dart destination or a written
reason it has none — fix the behavioral gaps that accounting exposes, and then delete
`packages/mobile_rn` and its workflow. When M6 lands, `packages/mobile` is the only mobile client
and nothing about the port is remembered only in a reviewer's head.

**Architecture:** Three phases. Phase 1 builds a permanent ledger at `docs/mobile-parity-ledger.md`
mapping all 99 RN source files and all 37 spec test rows to a destination or a documented omission,
kept honest by a test that parses the ledger and fails when a cited path does not exist or an RN
file is missing a row. Phase 2 closes the four gaps already confirmed plus anything Phase 1 adds:
haptics (a `Haptics` seam over a new `operator/haptics` method channel, because Flutter's
`HapticFeedback` has no notification-feedback equivalent), active-tab scroll-to-top, real
simulator detection for `build_mode`, and the voice capabilities `speech_to_text` cannot express —
recovered by vendoring the package the way `packages/xterm` already is. Phase 3 deletes the RN tree
and records what deliberately outlives the port.

**Tech Stack:** Everything from M5, plus `device_info_plus 12.1.0` (simulator detection) and two
vendored workspace packages, `packages/speech_to_text` and `packages/speech_to_text_platform_interface`,
forked from pub 7.4.0 / 2.4.0. `posthog_flutter` and the Firebase trio are **not** added — see
"What M6 deliberately does not include".

**Spec:** `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`

## Global Constraints

- Source spec: `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`. M6 is its last
  row: "Parity sweep; `packages/mobile_rn` deleted — all 37 ledger rows accounted for."
- Source of truth for RN behavior: `packages/mobile_rn/` (frozen). Paths in this plan are relative
  to `packages/mobile_rn/` when they end in `.ts`/`.tsx`, and to `packages/mobile/` when they end
  in `.dart`. **Phase 3 deletes the RN tree — every task that needs to read it is in Phase 1 or 2.**
- Conventions are the `flutter-knowledge` skill. Invoke `flutter-testing` before the first test
  file, exactly as M0–M5 did.
- Cubit only — never `Bloc` with events. Static-only classes are `sealed class X`. **No comments**
  except non-obvious business rules. Single quotes, `const` constructors, full 8-digit hex colors,
  `final` locals. No `flutter_screenutil` extensions outside `AppTextStyle`. No `drift`, no
  `freezed`, no `json_serializable`, no `build_runner` — **in first-party code**. The vendored
  `speech_to_text` ships its own checked-in `.g.dart` files; those stay as they are and are never
  regenerated (see Task 13).
- User-facing copy is inline English. Do not introduce `LocaleKeys` for product copy.
- Navigation is `Navigator.of(context)` with `RoutesStrings` names.
- Verification after every task: `flutter analyze` clean and `flutter test` green, both from
  `packages/mobile`.
- **Baseline this plan starts from: `flutter analyze` → "No issues found!", `flutter test` →
  1001/1001 green** (measured on `master` at commit `0548efe28`, 2026-08-16). Every task's expected
  count is baseline-plus-its-own; never let the suite shrink.
- Package name is `operator_mobile`; imports are `package:operator_mobile/...`.
- All app state resolves under `~/.operator`. Unaffected by M6, restated per `AGENTS.md`'s hard rule.

### Four rules M5 paid for in wasted time

1. **`Result.when` is an extension method.** Every library that calls `.when(...)` needs its own
   direct `import 'package:operator_mobile/core/helpers/result/result.dart';`.
2. **Check every new type name against the packages the file imports.** M6's risky file is
   `core/utils/haptics.dart`: `package:flutter/services.dart` already exports `HapticFeedback`.
   The class in this plan is named `Haptics` and never `HapticFeedback` — do not rename it.
3. **Never call `emit`/`setState` synchronously from a layout callback.** Task 11 adds scroll
   controllers driven from a `ValueNotifier` listener; it schedules its work, it does not emit
   during layout.
4. **A cubit with private duration fields needs the factory + `required this._field` pattern.**
   M6 adds no new cubits, so this only matters if Phase 1 turns one up.

---

## Baseline: M5 is on `master`

M5 merged as `949a31d7e`, with `0548efe28` on top fixing the Android/iOS release-networking gap
that M5 recorded as M6 work. Confirm before starting:

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: "No issues found!" and "All tests passed!" at 1001 tests.

## What M6 inherits, and what it decides

M5's "What M5 leaves for later milestones" table hands seven items to M6. Their disposition,
decided before this plan was written:

| Inherited item | M6's decision |
|---|---|
| The Android release `INTERNET` permission and `usesCleartextTraffic` | **Already done** in `0548efe28`, along with the iOS ATS and local-network strings. Task 18 records it in the ledger. |
| Deleting `packages/mobile_rn` | **Task 19.** |
| Haptics on mic press, send, kill, restore, mark-all-read | **Tasks 7–10.** The sweep found 65 RN call sites, not five. |
| Simulator detection for `build_mode` | **Task 12.** `main.dart:33` hardcodes `isPhysicalDevice: true`, so `build_mode` can only ever report `device`. |
| The coding-vocabulary bias, the two iOS audio-session categories, the Android silence extras | **Tasks 13–17**, by vendoring and extending the package. |
| Wiring `posthog_flutter` behind `MobileTelemetryClient` | **Deliberately not done.** See below. |
| A `feature_used {feature: merge}` capture, once the PR list grows a merge action | **Closed as parity, not a gap.** RN has no merge affordance either — `lib/PRCard.tsx` and `app/(tabs)/prs.tsx` contain no merge call. Adding one to the Flutter app would be a new feature, which the spec's non-goals forbid. Task 18 records this. |

### What M6 deliberately does not include

| Left out | Why | Where it goes |
|---|---|---|
| `posthog_flutter` behind `MobileTelemetryClient` | No project key exists (`8ec08116e`), so a wired SDK sends nothing. The seam, the sanitizer, the rate limiter, the daily-active tracker and the allowlist all exist and are tested — the SDK is the last inch, and adding a dependency, its native config and its privacy surface for zero behavior is a bad trade. | A one-file task whenever a key exists. Recorded in the ledger by Task 18. |
| FCM/APNs push registration (M5's blocked Task 22) | It needs a Firebase project, `google-services.json` and an APNs key — credentials only the repository owner can create. It is a self-contained subsystem, not a parity gap: `push_registrar.dart`, `push_status.dart`, `push_registration.dart` and `push_token_source.dart` all exist and are tested behind the `PushTokenSource` seam. Blocking the RN tree's deletion on a credential is the wrong dependency. | Its own milestone. Recorded in the ledger by Task 18. |
| A PR merge button | Neither app has one. | Nowhere — it is not a gap. |
| Re-running M0–M5's device QA | M6 changes haptics, voice and tab scrolling. Only those get a device pass. | Milestone verification. |

---

## File structure

**Phase 1 — the ledger**

| File | Responsibility |
|---|---|
| `docs/mobile-parity-ledger.md` (create) | Permanent. Two tables: 99 RN source rows, 37 spec test rows. Outlives `mobile_rn`, so it is the only place the port's decisions survive deletion. |
| `packages/mobile/test/parity_ledger_test.dart` (create) | Parses the ledger and fails if a cited Dart path does not exist, if an RN file has no row, or if a row is duplicated. Deleted by Task 19 along with the RN tree. |

**Phase 2 — the gaps**

| File | Responsibility |
|---|---|
| `lib/core/utils/haptics.dart` (create) | The five-verb seam: `tap`, `select`, `success`, `warning`, `error`. Delegates to `HapticFeedback` where Flutter has an equivalent and to the `operator/haptics` channel where it does not. |
| `ios/Runner/HapticsPlugin.swift` (create) | `UINotificationFeedbackGenerator` for success/warning/error. |
| `android/app/src/main/kotlin/.../HapticsPlugin.kt` (create) | `VibrationEffect` predefined effects for the same three. |
| `lib/core/app_routes/home_shell.dart` (modify) | Owns the four tab scroll controllers and the re-tap signal. |
| Four `*_body.dart` files (modify) | Attach the controller their tab owns. |
| `lib/main.dart` (modify) | Real `isPhysicalDevice` from `device_info_plus`. |
| `packages/speech_to_text/` and `packages/speech_to_text_platform_interface/` (vendor) | Forks carrying `contextualStrings`, the iOS audio-session config and the Android biasing extras. |
| `lib/feature/chat/voice/speech_recognizer.dart` (modify) | Passes the three new options through the existing seam. |
| `lib/feature/chat/voice/device_provider.dart` (modify) | `kCodingVocabulary` and the push/latched session split. |

**Phase 3 — retirement**

| File | Responsibility |
|---|---|
| `packages/mobile_rn/` (delete) | 99 source files, 37 test files, `node_modules`, `patches`. |
| `.github/workflows/mobile.yml` (delete) | Typechecks a tree that will not exist. |
| `docs/mobile-parity-ledger.md` (modify) | Gains the "what outlives the port" section. |
| `AGENTS.md`, `docs/STATUS.md`, `CLAUDE.md` (modify, as found) | Any surviving `mobile_rn` reference. |

---

# Phase 1 — The ledger

The ledger is what earns the deletion. Without it, deleting `mobile_rn` throws away the only record
of which RN behaviors were ported, which were replaced by a Flutter-native equivalent, and which
were deliberately dropped. A reviewer six months from now asking "was `sheetResult.ts` ever ported?"
must get an answer from the repository, not from `git show`.

The ledger is also a test. Task 1 writes the parser first, so every later row is verified rather
than asserted.

### Task 1: The ledger's test, and its first rows

**Files:**
- Create: `docs/mobile-parity-ledger.md`
- Test: `packages/mobile/test/parity_ledger_test.dart`

**Interfaces:**
- Produces: the ledger's row format, which Tasks 2–6 follow exactly. A source row is
  `| <rn path> | <dart path or the literal word OMITTED> | <note> |`. The test keys on the first
  two columns and ignores the third.

The ledger lives at the repository root's `docs/`, not under `packages/mobile/`, because it
documents a relationship between two packages and must survive one of them being deleted.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/parity_ledger_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _ledgerPath = '../../docs/mobile-parity-ledger.md';
const String _rnRoot = '../mobile_rn';

final RegExp _sourceRow = RegExp(r'^\|\s*`([^`]+)`\s*\|\s*(?:`([^`]+)`|OMITTED)\s*\|');

List<String> _rnSourceFiles() {
  final root = Directory(_rnRoot);
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path.replaceFirst('$_rnRoot/', ''))
      .where((path) => path.startsWith('lib/') || path.startsWith('app/'))
      .where((path) => path.endsWith('.ts') || path.endsWith('.tsx'))
      .where((path) => !path.endsWith('.test.ts') && !path.endsWith('.test.tsx'))
      .toList()
    ..sort();
}

Map<String, String?> _ledgerRows() {
  final rows = <String, String?>{};
  for (final line in File(_ledgerPath).readAsLinesSync()) {
    final match = _sourceRow.firstMatch(line.trim());
    if (match == null) continue;
    final source = match.group(1)!;
    expect(rows.containsKey(source), isFalse, reason: '$source has more than one ledger row');
    rows[source] = match.group(2);
  }
  return rows;
}

void main() {
  group('parity ledger', () {
    test('has exactly one row per RN source file', () {
      final rows = _ledgerRows();
      final missing = _rnSourceFiles().where((path) => !rows.containsKey(path)).toList();
      expect(missing, isEmpty, reason: 'RN files with no ledger row:\n${missing.join('\n')}');
    });

    test('cites no RN file that does not exist', () {
      final sources = _rnSourceFiles().toSet();
      final stale = _ledgerRows().keys.where((path) => !sources.contains(path)).toList();
      expect(stale, isEmpty, reason: 'ledger rows for files that are gone:\n${stale.join('\n')}');
    });

    test('every cited Dart destination exists', () {
      final broken = <String>[];
      _ledgerRows().forEach((source, destination) {
        if (destination == null) return;
        if (!File(destination).existsSync() && !Directory(destination).existsSync()) {
          broken.add('$source -> $destination');
        }
      });
      expect(broken, isEmpty, reason: 'destinations that do not exist:\n${broken.join('\n')}');
    });
  });
}
```

The paths are relative because `flutter test` runs with the package root as its working directory.
`OMITTED` is spelled in capitals with no backticks so the regex cannot confuse it with a path.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/parity_ledger_test.dart`
Expected: FAIL — `Cannot open file` for `../../docs/mobile-parity-ledger.md`.

- [ ] **Step 3: Create the ledger with its header and the core-layer rows**

Create `docs/mobile-parity-ledger.md`:

````markdown
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
| `lib/config.ts` | `packages/mobile/lib/core/api/server_config.dart` | `ServerConfig` plus `normalizeServerHost`, `httpBase`, `muxUrl`, `isConfigured`. The `useServerConfig` hook becomes `ServerConfigStore`; the AsyncStorage→SecureStore password migration is not ported because no Flutter build ever wrote a password to `shared_preferences`. |
| `lib/api.ts` | `packages/mobile/lib/core/api/api_request_helpers/end_points.dart` | The path catalogue. The 674 lines of fetch wrappers are the 11 `*_remote_data_source.dart` files; `ApiError` is `ServerFailure`. |
| `lib/mux.ts` | `packages/mobile/lib/core/mux/mux_client.dart` | Protocol-for-protocol, with `mux_socket.dart` and `mux_backoff.dart` splitting out the transport and the retry curve. |
| `lib/connectionError.ts` | `packages/mobile/lib/core/error_handling/connection_error.dart` | 1:1. |
| `lib/chatError.ts` | `packages/mobile/lib/core/error_handling/chat_preflight.dart` | Renamed on the way: the module is about preflight codes, not chat errors generally. `isChatPreflightError` became `isChatPreflightFailure` because it takes a `Failure`, not an `Error`. |
| `lib/agentError.ts` | `packages/mobile/lib/core/error_handling/connection_error.dart` | Its whole body is one call to `describeConnectionFailure(classifyConnectionFailure(status))`. In Dart that composition is at the call site; a one-line indirection whose only reason for existing in RN was reading `Platform.OS` outside a pure module carries nothing over. |
| `lib/theme.ts` | `packages/mobile/lib/core/app_themes/colors/app_skin.dart` | The 31 tokens, with `light_skin.dart` / `dark_skin.dart` holding the values and `terminal_palette.dart` the terminal's own palette. |
| `lib/themePreference.ts` | `packages/mobile/lib/core/app_themes/colors/theme_preference.dart` | 1:1. |
| `lib/themeStore.ts` | `packages/mobile/lib/core/app_themes/colors/logic/skin_cubit.dart` | Persistence through `CacheHelper`. |
| `lib/ThemeProvider.tsx` | `packages/mobile/lib/core/app_themes/colors/skin_scope.dart` | `SkinScope` `InheritedWidget` plus the `context.skin` extension. |
| `lib/appInfo.ts` | `packages/mobile/lib/core/utils/app_info.dart` | Adapted — `package_info_plus`. |
| `lib/haptics.ts` | `packages/mobile/lib/core/utils/haptics.dart` | The same five verbs. `tap` and `select` reach Flutter's `HapticFeedback`; `success`, `warning` and `error` reach a first-party `operator/haptics` channel, because Flutter exposes no notification-feedback API. |
| `lib/useTabScrollToTop.ts` | `packages/mobile/lib/core/app_routes/home_shell.dart` | The shell owns the four controllers and animates the active tab's list to zero when its tab is re-tapped. |
| `lib/sheetResult.ts` | OMITTED | Structurally unnecessary. It exists only because an Expo Router route cannot be handed an `onSelect` callback, so the opener parks the closure in a module-level map and passes a key as a route param. Flutter's `Navigator.push<T>` returns a `Future<T>`, so the sheet's result comes back to the caller directly. The three route builders (`projectSheetRoute`, `agentSheetRoute`, `connectSheetRoute`) are the three `showModalBottomSheet` call sites in `core/widgets/pickers/`. |
| `lib/ui.tsx` | `packages/mobile/lib/core/widgets` | `Pill`→`app_pill.dart`, `Card`→`app_container.dart`, `Button`→`primary_button.dart`, `EmptyState`→`app_empty_state.dart`, `SettingsGroup`→`settings_group.dart`, `ScreenHeader`/`HeaderIconButton`→`global_appbar.dart`, `SheetScreen`/`SheetHeader`→`app_dialog.dart`. `Dot`, `StatusBadge`, `Chip`, `SectionHeader`, `SettingsRow`, `SettingsToggle`, `NumberedStep` and `IconButton` live with their single consumer rather than in `core/`. |
| `lib/telemetry/config.ts` | `packages/mobile/lib/core/telemetry/runtime.dart` | `TelemetryConfig`, reading `String.fromEnvironment` instead of `process.env`. |
| `lib/telemetry/context.ts` | `packages/mobile/lib/core/telemetry/context.dart` | 1:1. |
| `lib/telemetry/dailyActive.ts` | `packages/mobile/lib/core/telemetry/daily_active.dart` | 1:1. |
| `lib/telemetry/events.ts` | `packages/mobile/lib/core/telemetry/events.dart` | 1:1, closed vocabulary preserved. |
| `lib/telemetry/rateLimit.ts` | `packages/mobile/lib/core/telemetry/rate_limit.dart` | 1:1 apart from `mergeRateState`, which fixes a restart bug in the RN version — see "Divergences" below. |
| `lib/telemetry/runtime.ts` | `packages/mobile/lib/core/telemetry/runtime.dart` | `TelemetryRuntime`. |
| `lib/telemetry/sanitize.ts` | `packages/mobile/lib/core/telemetry/sanitize.dart` | 1:1. |
| `lib/telemetry/telemetry.ts` | `packages/mobile/lib/core/telemetry/telemetry.dart` | The sink is the abstract `MobileTelemetryClient`. No PostHog SDK is wired — see "What outlives the port". |
| `lib/TelemetryManager.tsx` | `packages/mobile/lib/main.dart` | `TelemetryRuntime.init` at startup and `AppLifecycleListener(onResume:)` for the daily-active ping. |
````

The remaining tables are added by Tasks 2–6. Leave the file ending after the last row above; the
test only checks the rows that are present against the RN files that exist, so it stays red until
Task 6 and green from then on.

- [ ] **Step 4: Run the test to verify the shape is right**

Run: `cd packages/mobile && flutter test test/parity_ledger_test.dart`
Expected: the "cites no RN file that does not exist" and "every cited Dart destination exists"
tests PASS; "has exactly one row per RN source file" FAILS listing the ~75 files Tasks 2–6 cover.
That is the correct state — the ledger is incomplete, and the test says exactly which rows are
missing.

If either of the other two tests fails, a path above is wrong. Fix it now: those two are the ones
that catch transcription errors.

- [ ] **Step 5: Commit**

```bash
git add docs/mobile-parity-ledger.md packages/mobile/test/parity_ledger_test.dart
git commit -m "docs(mobile): start the parity ledger, with a test that keeps it honest"
```

---

### Task 2: Ledger rows — pairing, onboarding, sessions

**Files:**
- Modify: `docs/mobile-parity-ledger.md`

**Interfaces:**
- Consumes: the row format and the table opened by Task 1.
- Produces: nothing new. Rows append to the same table.

Read each RN file before writing its row. A row asserting a destination that does not implement the
behavior is worse than no row — it launders a gap into a checkmark. Where the Dart file only
partly covers the RN file, say so in the note; where it covers something the RN file did not, that
belongs in "Divergences", not the note.

- [ ] **Step 1: Read the RN files this task covers**

```bash
cd packages/mobile_rn && wc -l lib/pairing.ts lib/cameraLens.ts lib/disconnect.ts lib/ManualConnectSheet.tsx lib/onboarding.ts lib/onboardingStore.ts lib/OnboardingGate.tsx lib/store.tsx lib/sessionStatus.ts lib/agentsView.ts lib/harnessLogo.ts lib/harnessLogoAssets.ts lib/AgentLogo.tsx lib/SessionCard.tsx app/pair.tsx app/onboarding.tsx 'app/(tabs)/index.tsx' app/session/\[id\].tsx
```

- [ ] **Step 2: Append the rows**

Append to the source table in `docs/mobile-parity-ledger.md`:

```markdown
| `lib/pairing.ts` | `packages/mobile/lib/feature/pairing/logic/pairing_payload.dart` | QR payload parse. |
| `lib/cameraLens.ts` | `packages/mobile/lib/feature/pairing/logic/camera_lens.dart` | Adapted — `mobile_scanner` instead of `expo-camera`. |
| `lib/disconnect.ts` | `packages/mobile/lib/feature/pairing/logic/disconnect.dart` | 1:1. |
| `lib/ManualConnectSheet.tsx` | `packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/ui/widgets/manual_connect_body.dart` | A sheet in RN, a screen in Dart — `Navigator.push` returns the result, so it needs no `sheetResult` key. Its logic is `manual_connect_cubit.dart`. |
| `app/pair.tsx` | `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/widgets/pairing_scan_body.dart` | With `camera_permission_gate.dart` and `connection_failure_banner.dart`. |
| `app/sheets/connect.tsx` | `packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/ui/manual_connect_screen.dart` | The route wrapper; see `sheetResult.ts` for why the sheet-route indirection is gone. |
| `lib/onboarding.ts` | `packages/mobile/lib/feature/onboarding/logic/onboarding.dart` | 1:1. |
| `lib/onboardingStore.ts` | `packages/mobile/lib/feature/onboarding/logic/onboarding.dart` | Persistence collapsed into the same file; it is one `CacheHelper` key. |
| `lib/OnboardingGate.tsx` | `packages/mobile/lib/main.dart` | The gate is the `initialRoute` computation in `main`. |
| `app/onboarding.tsx` | `packages/mobile/lib/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart` | With `onboarding_step.dart` for `ui.tsx`'s `NumberedStep`. |
| `lib/store.tsx` | `packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart` | The board poll, its sequential auth probe, and the unread-count tick. `ConnStatus` is `SessionsState`; the React context is the cubit. |
| `lib/sessionStatus.ts` | `packages/mobile/lib/feature/sessions/logic/session_status.dart` | 1:1, with `status_visual.dart` holding the hue mapping. |
| `lib/agentsView.ts` | `packages/mobile/lib/feature/sessions/logic/agents_view.dart` | 1:1. |
| `lib/harnessLogo.ts` | `packages/mobile/lib/feature/sessions/logic/harness_logo.dart` | 1:1. Filed under `sessions` rather than the spec's `core/utils` because the board is its only consumer. |
| `lib/harnessLogoAssets.ts` | `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart` | The asset map is the widget's lookup; the SVGs are `packages/mobile/assets`. |
| `lib/AgentLogo.tsx` | `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart` | `flutter_svg`. |
| `lib/SessionCard.tsx` | `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart` | With `session_section_header.dart` and `sessions_stats_row.dart` for the `SectionList` chrome. |
| `app/(tabs)/index.tsx` | `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart` | The Kanban tab, plus `session_actions_sheet.dart` for kill/restore/resume. |
| `app/session/[id].tsx` | `packages/mobile/lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart` | The chat-or-terminal fork. |
```

- [ ] **Step 3: Run the test**

Run: `cd packages/mobile && flutter test test/parity_ledger_test.dart`
Expected: "cites no RN file that does not exist" and "every cited Dart destination exists" PASS;
the one-row-per-file test still FAILS with a shorter list.

- [ ] **Step 4: Commit**

```bash
git add docs/mobile-parity-ledger.md
git commit -m "docs(mobile): ledger rows for pairing, onboarding and sessions"
```

---

### Task 3: Ledger rows — pull_request, orchestrator, spawn, settings

**Files:**
- Modify: `docs/mobile-parity-ledger.md`

- [ ] **Step 1: Read the RN files this task covers**

```bash
cd packages/mobile_rn && wc -l lib/prView.ts lib/PRCard.tsx lib/usePRSummaries.ts lib/githubLink.ts lib/openGitHub.ts lib/ProjectSwitcher.tsx lib/ProjectPickerSheet.tsx lib/orchestratorView.ts lib/agentPicker.ts lib/AgentPickerSheet.tsx lib/ThemePickerSheet.tsx 'app/(tabs)/prs.tsx' 'app/(tabs)/orchestrator.tsx' 'app/(tabs)/settings.tsx' app/spawn.tsx app/sheets/agent.tsx app/sheets/project.tsx app/sheets/theme.tsx
```

- [ ] **Step 2: Append the rows**

```markdown
| `lib/prView.ts` | `packages/mobile/lib/feature/pull_request/logic/pr_view.dart` | 1:1 — `prLifecycle`, `mergeReasonLabel`, the headline atom and the badge row. |
| `lib/PRCard.tsx` | `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pr_card.dart` | 1:1. Neither app has a merge action; the daemon's `prMerge` endpoint is reachable from `pull_request_repository.dart` but no UI calls it, in either tree. |
| `lib/usePRSummaries.ts` | `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart` | The fan-out and its per-session summary cache. |
| `lib/githubLink.ts` | `packages/mobile/lib/feature/pull_request/logic/github_link.dart` | 1:1. |
| `lib/openGitHub.ts` | `packages/mobile/lib/feature/pull_request/logic/open_github.dart` | Adapted — `url_launcher`. |
| `lib/ProjectSwitcher.tsx` | `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/project_switcher.dart` | |
| `lib/ProjectPickerSheet.tsx` | `packages/mobile/lib/core/widgets/pickers/project_picker_sheet.dart` | In `core/` because the PR tab, the spawn screen and settings all open it. |
| `app/sheets/project.tsx` | `packages/mobile/lib/core/widgets/pickers/project_picker_sheet.dart` | The route wrapper collapses into the sheet — `showModalBottomSheet` returns the choice. |
| `app/(tabs)/prs.tsx` | `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pull_requests_body.dart` | Including the open/merged/all filter and its counts. |
| `lib/orchestratorView.ts` | `packages/mobile/lib/feature/orchestrator/logic/orchestrator_view.dart` | 1:1. |
| `app/(tabs)/orchestrator.tsx` | `packages/mobile/lib/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_body.dart` | With `orchestrator_card.dart`. |
| `lib/agentPicker.ts` | `packages/mobile/lib/feature/spawn/logic/agent_picker.dart` | 1:1. |
| `lib/AgentPickerSheet.tsx` | `packages/mobile/lib/core/widgets/pickers/agent_picker_sheet.dart` | In `core/` — spawn and the chat settings sheet both open it. |
| `app/sheets/agent.tsx` | `packages/mobile/lib/core/widgets/pickers/agent_picker_sheet.dart` | Route wrapper collapsed, as above. |
| `app/spawn.tsx` | `packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart` | |
| `lib/ThemePickerSheet.tsx` | `packages/mobile/lib/core/widgets/pickers/theme_picker_sheet.dart` | |
| `app/sheets/theme.tsx` | `packages/mobile/lib/core/widgets/pickers/theme_picker_sheet.dart` | Route wrapper collapsed, as above. |
| `app/(tabs)/settings.tsx` | `packages/mobile/lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart` | Daemon settings, theme picker, agent picker, project switcher, the notifications section and disconnect. |
```

- [ ] **Step 3: Run the test**

Run: `cd packages/mobile && flutter test test/parity_ledger_test.dart`
Expected: the two path tests PASS; the completeness test FAILS with a shorter list.

- [ ] **Step 4: Commit**

```bash
git add docs/mobile-parity-ledger.md
git commit -m "docs(mobile): ledger rows for PRs, orchestrator, spawn and settings"
```

---

### Task 4: Ledger rows — chat and voice

**Files:**
- Modify: `docs/mobile-parity-ledger.md`

`chat` is the largest feature in both trees, so this task is the one most likely to turn up a real
gap. Read `useConversation.ts` and `ChatTimeline.tsx` in full before writing their rows — between
them they hold the streaming state machine and every timeline item type.

- [ ] **Step 1: Read the RN files this task covers**

```bash
cd packages/mobile_rn && wc -l lib/chat/*.ts lib/chat/*.tsx lib/voice/*.ts lib/voice/*.tsx
```

- [ ] **Step 2: Append the rows**

```markdown
| `lib/chat/api.ts` | `packages/mobile/lib/feature/chat/data/data_source/chat_remote_data_source.dart` | Every conversation call. The catalogue calls (`models`, `skills`, `config-options`) are `chat_catalog_model.dart`. |
| `lib/chat/types.ts` | `packages/mobile/lib/feature/chat/data/model/conversation_item_model.dart` | With `conversation_turn_model.dart`, `activity_detail_model.dart`, `chat_attachment_model.dart` and `workspace_paths_model.dart`. |
| `lib/chat/sse.ts` | `packages/mobile/lib/feature/chat/data/sse.dart` | `takeSseFrames` and `parseSseFrame` as pure functions over a `ResponseType.stream` Dio response. CRLF boundaries, the `id:` fallback for daemons with no `seq`, and dropping malformed `data` all survive. |
| `lib/chat/snapshot.ts` | `packages/mobile/lib/feature/chat/data/model/conversation_snapshot_model.dart` | 1:1. |
| `lib/chat/timelineModel.ts` | `packages/mobile/lib/feature/chat/logic/timeline_model.dart` | 1:1. |
| `lib/chat/conversationChrome.ts` | `packages/mobile/lib/feature/chat/logic/conversation_chrome.dart` | 1:1. |
| `lib/chat/conversationErrors.ts` | `packages/mobile/lib/feature/chat/logic/conversation_errors.dart` | 1:1. |
| `lib/chat/elicitationModel.ts` | `packages/mobile/lib/feature/chat/logic/elicitation_model.dart` | 1:1. |
| `lib/chat/composerSuggestions.ts` | `packages/mobile/lib/feature/chat/logic/composer_suggestions.dart` | 1:1. |
| `lib/chat/markdownBlocks.ts` | `packages/mobile/lib/feature/chat/logic/markdown_blocks.dart` | 1:1. |
| `lib/chat/syntaxHighlight.ts` | `packages/mobile/lib/feature/chat/logic/syntax_highlight.dart` | 1:1. |
| `lib/chat/ansi.ts` | `packages/mobile/lib/feature/chat/logic/ansi.dart` | 1:1. |
| `lib/chat/useConversation.ts` | `packages/mobile/lib/feature/chat/presentation/chat_screen/logic/chat_cubit.dart` | The stream lifecycle, reconnect, optimistic send and the pending-request set. Paging is `conversation_pages.dart`. |
| `lib/chat/ChatSessionScreen.tsx` | `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart` | With `chat_meta_bar.dart`, `conversation_banners.dart`, `conversation_menu_sheet.dart` and `conversation_map_sheet.dart`. `MenuRow` is inside the menu sheet. |
| `lib/chat/ChatTimeline.tsx` | `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart` | Split by item type: `timeline_item.dart`, `activity_row.dart`, `activity_run.dart`, `activity_meta.dart`, `turn_summary.dart`, `live_turn_bar.dart`, `plan_card.dart`, `approval_card.dart`, `user_input_card.dart`, `file_change_list.dart`, `inline_banner.dart`, `chat_atoms.dart`. |
| `lib/chat/ChatComposer.tsx` | `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart` | With `suggestion_sheet.dart`; attachment picking is `logic/attachment_picker.dart`. |
| `lib/chat/ChatMarkdown.tsx` | `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_markdown.dart` | |
| `lib/chat/HighlightedCodeText.tsx` | `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/highlighted_code_text.dart` | |
| `lib/chat/ChatSettingsModal.tsx` | `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_settings_sheet.dart` | Model, mode and config-option pickers. |
| `lib/voice/types.ts` | `packages/mobile/lib/feature/chat/voice/voice_types.dart` | 1:1. |
| `lib/voice/deviceProvider.ts` | `packages/mobile/lib/feature/chat/voice/device_provider.dart` | Behind the `SpeechRecognizer` seam in `speech_recognizer.dart`. The coding-vocabulary bias, the two iOS audio-session configurations and the Android silence extras needed the vendored fork in `packages/mobile/packages/speech_to_text` — pub's `speech_to_text` exposes none of the three. |
| `lib/voice/useVoiceInput.ts` | `packages/mobile/lib/feature/chat/voice/logic/voice_input_cubit.dart` | Push-to-talk and latched, with the same state machine. |
| `lib/voice/MicKey.tsx` | `packages/mobile/lib/feature/chat/voice/ui/mic_key.dart` | With `voice_strip.dart` for the transcript strip. |
```

- [ ] **Step 3: Run the test**

Run: `cd packages/mobile && flutter test test/parity_ledger_test.dart`
Expected: the two path tests PASS; the completeness test FAILS with a shorter list.

- [ ] **Step 4: Commit**

```bash
git add docs/mobile-parity-ledger.md
git commit -m "docs(mobile): ledger rows for chat and voice"
```

---

### Task 5: Ledger rows — terminal, preview, notification, and the app shell

**Files:**
- Modify: `docs/mobile-parity-ledger.md`

`lib/session/TerminalSessionScreen.tsx` is 1,529 lines and holds the terminal, the preview globe and
the interface switch. Its row cites several Dart files; make sure each one exists before writing it.

- [ ] **Step 1: Read the RN files this task covers**

```bash
cd packages/mobile_rn && wc -l lib/session/*.ts lib/session/*.tsx lib/push.ts lib/pushStatus.ts lib/PushManager.tsx lib/notificationView.ts app/notifications.tsx app/preview/\[id\].tsx app/shell/\[handleId\].tsx app/_layout.tsx 'app/(tabs)/_layout.tsx'
```

- [ ] **Step 2: Append the rows**

```markdown
| `lib/session/TerminalSessionScreen.tsx` | `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart` | Split by concern: `terminal_surface.dart` (the `xterm.dart` view), `terminal_status_bar.dart`, `terminal_composer.dart`, `terminal_dead_overlay.dart`, `terminal_preview_globe.dart`, `interface_switch_overlay.dart`, `interface_switch_sheet.dart`. The injected CSS/JS that made a WebView usable has no counterpart — the spike passed on `xterm.dart`, so the fallback was never taken. |
| `lib/session/keys.ts` | `packages/mobile/lib/feature/terminal/logic/keys.dart` | 1:1. |
| `lib/session/KeyRow.tsx` | `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart` | |
| `lib/session/Composer.tsx` | `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart` | |
| `lib/session/sendRoute.ts` | `packages/mobile/lib/feature/terminal/logic/send_route.dart` | 1:1. Filed under `terminal` rather than the spec's `sessions` because the terminal composer is its only consumer. |
| `lib/session/keyboardInset.ts` | `packages/mobile/lib/feature/chat/logic/keyboard_inset.dart` | Adapted — `MediaQuery.viewInsets`. |
| `lib/session/useInterfaceTransition.ts` | `packages/mobile/lib/feature/terminal/logic/interface_transition.dart` | With `interface_switch_cubit.dart` driving it. |
| `app/shell/[handleId].tsx` | `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart` | |
| `app/preview/[id].tsx` | `packages/mobile/lib/feature/preview/presentation/preview_screen/ui/widgets/preview_body.dart` | With `preview_browser.dart` wrapping `webview_flutter`, and `logic/preview_url.dart` for `mobileReachablePreviewURL`. |
| `lib/notificationView.ts` | `packages/mobile/lib/feature/notification/logic/notification_view.dart` | 1:1, except `notificationTarget` percent-encodes the session id — see "Divergences". |
| `lib/pushStatus.ts` | `packages/mobile/lib/feature/notification/logic/push_status.dart` | 1:1, with two enum names changed for the Flutter runtime (`notPaired`, `notConfigured`). |
| `lib/push.ts` | `packages/mobile/lib/feature/notification/logic/push_registration.dart` | The registration decision and its bookkeeping, behind the `PushTokenSource` seam in `push_token_source.dart`. **No FCM/APNs SDK is wired** — see "What outlives the port". |
| `lib/PushManager.tsx` | `packages/mobile/lib/feature/notification/logic/push_registrar.dart` | |
| `app/notifications.tsx` | `packages/mobile/lib/feature/notification/presentation/notifications_screen/ui/widgets/notifications_body.dart` | With `notification_row.dart` and `notification_bell.dart`. |
| `app/_layout.tsx` | `packages/mobile/lib/main.dart` | Providers, the deep-link listener and the navigator key. |
| `app/(tabs)/_layout.tsx` | `packages/mobile/lib/core/app_routes/home_shell.dart` | The four-tab bar, its `tabPress` selection haptic, and the re-tap-to-scroll-to-top gesture. |
```

- [ ] **Step 3: Run the test**

Run: `cd packages/mobile && flutter test test/parity_ledger_test.dart`
Expected: **all three tests PASS.** Every RN source file now has exactly one row.

If the completeness test still fails, the listed files are ones this plan did not anticipate. Add a
row for each — reading the file first — and note in the commit message that the sweep found files
beyond the plan's inventory.

- [ ] **Step 4: Commit**

```bash
git add docs/mobile-parity-ledger.md
git commit -m "docs(mobile): ledger rows for terminal, preview, notifications and the shell"
```

---

### Task 6: The test ledger, and the gap list

**Files:**
- Modify: `docs/mobile-parity-ledger.md`
- Test: `packages/mobile/test/parity_ledger_test.dart`

**Interfaces:**
- Produces: the "Open gaps" section, which is Phase 2's task list. Tasks 7–17 close the four
  entries this plan already knows about; anything else this task finds gets appended there and
  triaged before Task 19.

This closes the spec's 37-row accounting. Five rows landed somewhere other than the spec predicted;
the spec is not wrong so much as written before the code existed, and the ledger records where they
actually are.

- [ ] **Step 1: Extend the test to cover the test table**

Add to `packages/mobile/test/parity_ledger_test.dart`, inside `main()`:

```dart
  group('test ledger', () {
    final RegExp testRow = RegExp(r'^\|\s*`(lib/[^`]+\.test\.ts)`\s*\|\s*(?:`([^`]+)`|OMITTED)\s*\|');

    Map<String, String?> rows() {
      final parsed = <String, String?>{};
      for (final line in File(_ledgerPath).readAsLinesSync()) {
        final match = testRow.firstMatch(line.trim());
        if (match == null) continue;
        parsed[match.group(1)!] = match.group(2);
      }
      return parsed;
    }

    test('has one row per RN test file', () {
      final files = Directory(_rnRoot)
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path.replaceFirst('$_rnRoot/', ''))
          .where((path) => path.endsWith('.test.ts'))
          .toList();
      expect(files.length, 37);
      final missing = files.where((path) => !rows().containsKey(path)).toList();
      expect(missing, isEmpty, reason: 'RN tests with no ledger row:\n${missing.join('\n')}');
    });

    test('every cited Dart test exists', () {
      final broken = <String>[];
      rows().forEach((source, destination) {
        if (destination == null) return;
        if (!File(destination).existsSync()) broken.add('$source -> $destination');
      });
      expect(broken, isEmpty, reason: 'destinations that do not exist:\n${broken.join('\n')}');
    });
  });
```

The source-row regex from Task 1 requires a backticked path in column one and will also match these
rows — that is why the test-row regex anchors on `.test.ts`, and why the test table is placed
**after** the source table under its own heading. The source-table checks ignore extra rows whose
first column is not an RN source file, because `_rnSourceFiles()` excludes `.test.ts`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/parity_ledger_test.dart`
Expected: FAIL — `expect(files.length, 37)` passes, then "RN tests with no ledger row" lists all 37.

- [ ] **Step 3: Append the test table**

Append to `docs/mobile-parity-ledger.md`:

```markdown
## Test files

The spec's ledger named a destination for each of the 37 RN test files. Five landed elsewhere; the
column below is where they actually are, and the note says why it moved.

| RN test | Dart test | Note |
|---|---|---|
| `lib/agentPicker.test.ts` | `packages/mobile/test/feature/spawn/logic/agent_picker_test.dart` | 1:1. |
| `lib/agentsView.test.ts` | `packages/mobile/test/feature/sessions/logic/agents_view_test.dart` | 1:1. |
| `lib/appInfo.test.ts` | `packages/mobile/test/core/utils/app_info_test.dart` | Adapted — `package_info_plus`. |
| `lib/cameraLens.test.ts` | `packages/mobile/test/feature/pairing/logic/camera_lens_test.dart` | Adapted — `mobile_scanner`. |
| `lib/chat/ChatMarkdown.test.ts` | `packages/mobile/test/feature/chat/logic/chat_markdown_test.dart` | 1:1. |
| `lib/chat/ansi.test.ts` | `packages/mobile/test/feature/chat/logic/ansi_test.dart` | 1:1. |
| `lib/chat/composerSuggestions.test.ts` | `packages/mobile/test/feature/chat/logic/composer_suggestions_test.dart` | 1:1. |
| `lib/chat/conversationAction.test.ts` | `packages/mobile/test/feature/chat/logic/conversation_action_test.dart` | 1:1. |
| `lib/chat/conversationChrome.test.ts` | `packages/mobile/test/feature/chat/logic/conversation_chrome_test.dart` | 1:1. |
| `lib/chat/elicitationModel.test.ts` | `packages/mobile/test/feature/chat/logic/elicitation_model_test.dart` | 1:1. |
| `lib/chat/snapshot.test.ts` | `packages/mobile/test/feature/chat/logic/snapshot_test.dart` | 1:1. |
| `lib/chat/sse.test.ts` | `packages/mobile/test/feature/chat/data/sse_test.dart` | 1:1 — CRLF frames, the `id:` fallback and dropping malformed `data`. |
| `lib/chat/syntaxHighlight.test.ts` | `packages/mobile/test/feature/chat/logic/syntax_highlight_test.dart` | 1:1. |
| `lib/chat/timelineModel.test.ts` | `packages/mobile/test/feature/chat/logic/timeline_model_test.dart` | 1:1. |
| `lib/chatError.test.ts` | `packages/mobile/test/core/error_handling/chat_preflight_test.dart` | **Moved.** The spec predicted `feature/chat/logic/chat_error_test.dart`; the module is a `Failure` classifier used by spawn and orchestrator as well as chat, so it is core. |
| `lib/chatModeApi.test.ts` | `packages/mobile/test/feature/chat/data/data_source/chat_remote_data_source_test.dart` | **Moved.** The spec predicted `feature/chat/data/chat_mode_api_test.dart`; there is no separate mode API in Dart — the calls are methods on the chat data source, and `test/feature/chat/presentation/chat_screen/ui/chat_sheets_test.dart` covers the picker that drives them. |
| `lib/connectionError.test.ts` | `packages/mobile/test/core/error_handling/connection_error_test.dart` | 1:1. |
| `lib/disconnect.test.ts` | `packages/mobile/test/feature/pairing/logic/disconnect_test.dart` | 1:1. |
| `lib/githubLink.test.ts` | `packages/mobile/test/feature/pull_request/logic/github_link_test.dart` | 1:1. |
| `lib/harnessLogo.test.ts` | `packages/mobile/test/feature/sessions/logic/harness_logo_test.dart` | **Moved.** The spec predicted `core/utils/`; the board is the only consumer, so it lives with it. |
| `lib/notificationView.test.ts` | `packages/mobile/test/feature/notification/logic/notification_view_test.dart` | 1:1. |
| `lib/onboarding.test.ts` | `packages/mobile/test/feature/onboarding/logic/onboarding_test.dart` | 1:1. |
| `lib/orchestratorView.test.ts` | `packages/mobile/test/feature/orchestrator/logic/orchestrator_view_test.dart` | 1:1. |
| `lib/prView.test.ts` | `packages/mobile/test/feature/pull_request/logic/pr_view_test.dart` | 1:1. |
| `lib/pushStatus.test.ts` | `packages/mobile/test/feature/notification/logic/push_status_test.dart` | 1:1, two enum names changed. |
| `lib/session/keyboardInset.test.ts` | `packages/mobile/test/feature/chat/logic/keyboard_inset_test.dart` | Adapted — `MediaQuery.viewInsets`. |
| `lib/session/sendRoute.test.ts` | `packages/mobile/test/feature/terminal/logic/send_route_test.dart` | **Moved.** The spec predicted `feature/sessions/`; the terminal composer is the only consumer. |
| `lib/sessionStatus.test.ts` | `packages/mobile/test/feature/sessions/logic/session_status_test.dart` | 1:1. |
| `lib/sheetResult.test.ts` | OMITTED | **The only dropped row, and the module it covers is dropped with it.** It tests parking and releasing a callback in a module-level map — a mechanism `Navigator.push<T>`'s return value makes unnecessary. There is no Dart code to cover. The behavior it protected (a sheet dismissed without a choice must not leak its closure) is a property of the framework here, not of our code. |
| `lib/telemetry/context.test.ts` | `packages/mobile/test/core/telemetry/context_test.dart` | 1:1, plus a wire-key assertion. |
| `lib/telemetry/dailyActive.test.ts` | `packages/mobile/test/core/telemetry/daily_active_test.dart` | 1:1. |
| `lib/telemetry/rateLimit.test.ts` | `packages/mobile/test/core/telemetry/rate_limit_test.dart` | 1:1, plus the restart case in "Divergences". |
| `lib/telemetry/sanitize.test.ts` | `packages/mobile/test/core/telemetry/sanitize_test.dart` | 1:1, plus a `CountRule` case Dart can express and TypeScript could not. |
| `lib/telemetry/telemetry.test.ts` | `packages/mobile/test/core/telemetry/telemetry_test.dart` | Adapted — the sink is the abstract `MobileTelemetryClient`. |
| `lib/theme.test.ts` | `packages/mobile/test/core/app_themes/skin_test.dart` | Extended — pins the `rgba()`→8-digit-ARGB conversions. |
| `lib/themePreference.test.ts` | `packages/mobile/test/core/app_themes/skin_cubit_test.dart` | `bloc_test`. |
| `lib/voice/deviceProvider.test.ts` | `packages/mobile/test/feature/chat/voice/device_provider_test.dart` | Adapted — the vendored `speech_to_text`. |

**36 ported, 1 dropped with its module, 37 accounted for.**

## Open gaps

Behaviors the sweep found in the RN tree with no Dart counterpart. Each is closed before the RN tree
is deleted.

| Gap | RN source | Status |
|---|---|---|
| Haptic feedback | `lib/haptics.ts` and 65 call sites | Closed by M6 Tasks 7–10 |
| Re-tapping the active tab scrolls it to the top | `lib/useTabScrollToTop.ts`, all four tabs | Closed by M6 Task 11 |
| `build_mode` can never report `simulator` | `lib/telemetry/context.ts` vs `lib/main.dart:33` | Closed by M6 Task 12 |
| Coding-vocabulary bias, the two iOS audio sessions, the Android silence extras | `lib/voice/deviceProvider.ts` | Closed by M6 Tasks 13–17 |
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/parity_ledger_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Verify the whole suite**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1006/1006 green.

- [ ] **Step 6: Commit**

```bash
git add docs/mobile-parity-ledger.md packages/mobile/test/parity_ledger_test.dart
git commit -m "docs(mobile): close the 37-row test ledger and list the open gaps"
```

---

# Phase 2 — Close the gaps

### Task 7: The `Haptics` seam and its platform channel

**Files:**
- Create: `lib/core/utils/haptics.dart`
- Create: `ios/Runner/HapticsPlugin.swift`
- Create: `android/app/src/main/kotlin/com/example/mobile/HapticsPlugin.kt`
- Modify: `ios/Runner/AppDelegate.swift`
- Modify: `android/app/src/main/kotlin/com/example/mobile/MainActivity.kt`
- Test: `test/core/utils/haptics_test.dart`

**Interfaces:**
- Produces: `sealed class Haptics` with `static void tap()`, `select()`, `success()`, `warning()`,
  `error()`, and `@visibleForTesting static void setChannelForTest(MethodChannel? channel)`.
  Tasks 8–10 call only the five verbs.

Flutter's `HapticFeedback` covers two of the five: `lightImpact()` is RN's `tap`, `selectionClick()`
is `select`. It has no counterpart for `notificationAsync` — iOS's `UINotificationFeedbackGenerator`
produces a three-pulse pattern that `lightImpact` does not, and the difference is the point: `error`
must not feel like `tap`. So `success`, `warning` and `error` go over a first-party channel.

Every call is fire-and-forget, exactly as RN's `run()` swallows rejections: a device with no haptic
engine must never throw into a press handler.

- [ ] **Step 1: Confirm the Android package name before writing the Kotlin path**

Run: `cd packages/mobile && cat android/app/src/main/AndroidManifest.xml | grep -n 'package\|applicationId' ; find android/app/src/main/kotlin -name '*.kt'`

Use whatever package directory `MainActivity.kt` already lives in. The paths in this task say
`com/example/mobile/`; if the tree says otherwise, use the tree's.

- [ ] **Step 2: Write the failing test**

Create `test/core/utils/haptics_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> platform = <MethodCall>[];
  final List<MethodCall> notification = <MethodCall>[];

  setUp(() {
    platform.clear();
    notification.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platform.add(call);
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(Haptics.channelName),
      (call) async {
        notification.add(call);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(Haptics.channelName), null);
  });

  group('Haptics', () {
    test('tap is a light impact on the framework channel', () async {
      Haptics.tap();
      await Future<void>.delayed(Duration.zero);
      expect(platform.single.method, 'HapticFeedback.vibrate');
      expect(platform.single.arguments, 'HapticFeedbackType.lightImpact');
      expect(notification, isEmpty);
    });

    test('select is a selection click on the framework channel', () async {
      Haptics.select();
      await Future<void>.delayed(Duration.zero);
      expect(platform.single.arguments, 'HapticFeedbackType.selectionClick');
      expect(notification, isEmpty);
    });

    test('success, warning and error go to the notification channel by name', () async {
      Haptics.success();
      Haptics.warning();
      Haptics.error();
      await Future<void>.delayed(Duration.zero);
      expect(notification.map((call) => call.method), ['notify', 'notify', 'notify']);
      expect(
        notification.map((call) => call.arguments),
        ['success', 'warning', 'error'],
      );
      expect(platform, isEmpty);
    });

    test('a channel that throws does not throw into the caller', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(Haptics.channelName),
        (call) async => throw PlatformException(code: 'unavailable'),
      );
      expect(Haptics.error, returnsNormally);
      await Future<void>.delayed(Duration.zero);
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/utils/haptics_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:operator_mobile/core/utils/haptics.dart'`.

- [ ] **Step 4: Write the Dart seam**

Create `lib/core/utils/haptics.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

sealed class Haptics {
  static const String channelName = 'operator/haptics';
  static const MethodChannel _channel = MethodChannel(channelName);

  static void tap() => _fire(HapticFeedback.lightImpact());

  static void select() => _fire(HapticFeedback.selectionClick());

  static void success() => _notify('success');

  static void warning() => _notify('warning');

  static void error() => _notify('error');

  static void _notify(String kind) => _fire(_channel.invokeMethod<void>('notify', kind));

  static void _fire(Future<void> call) {
    unawaited(call.catchError((Object error, StackTrace stack) {
      if (kDebugMode) debugPrint('haptics: $error');
    }));
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/core/utils/haptics_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 6: Write the iOS side**

Create `ios/Runner/HapticsPlugin.swift`:

```swift
import Flutter
import UIKit

enum HapticsPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "operator/haptics", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "notify", let kind = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let type: UINotificationFeedbackGenerator.FeedbackType
      switch kind {
      case "success": type = .success
      case "warning": type = .warning
      case "error": type = .error
      default:
        result(FlutterError(code: "bad_arg", message: "unknown kind \(kind)", details: nil))
        return
      }
      let generator = UINotificationFeedbackGenerator()
      generator.prepare()
      generator.notificationOccurred(type)
      result(nil)
    }
  }
}
```

Modify `ios/Runner/AppDelegate.swift` — inside `application(_:didFinishLaunchingWithOptions:)`,
after `GeneratedPluginRegistrant.register(with: self)`:

```swift
    if let registrar = self.registrar(forPlugin: "HapticsPlugin") {
      HapticsPlugin.register(with: registrar)
    }
```

- [ ] **Step 7: Write the Android side**

Create `android/app/src/main/kotlin/com/example/mobile/HapticsPlugin.kt`:

```kotlin
package com.example.mobile

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object HapticsPlugin {
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "operator/haptics").setMethodCallHandler { call, result ->
            if (call.method != "notify") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            // Android has no notification-feedback API. The predefined effects are the
            // closest stock patterns: DOUBLE_CLICK reads as an affirmative, HEAVY_CLICK
            // as a caution, and TICK-then-HEAVY as a rejection.
            val effect = when (call.arguments as? String) {
                "success" -> VibrationEffect.EFFECT_DOUBLE_CLICK
                "warning" -> VibrationEffect.EFFECT_HEAVY_CLICK
                "error" -> VibrationEffect.EFFECT_DOUBLE_CLICK
                else -> {
                    result.error("bad_arg", "unknown kind ${call.arguments}", null)
                    return@setMethodCallHandler
                }
            }
            vibrator(context)?.takeIf { it.hasVibrator() }?.let { device ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    device.vibrate(VibrationEffect.createPredefined(effect))
                }
            }
            result.success(null)
        }
    }

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
}
```

Modify `android/app/src/main/kotlin/com/example/mobile/MainActivity.kt` to register it:

```kotlin
package com.example.mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        HapticsPlugin.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
```

Add the permission to `android/app/src/main/AndroidManifest.xml`, next to the existing
`uses-permission` lines:

```xml
    <uses-permission android:name="android.permission.VIBRATE"/>
```

- [ ] **Step 8: Verify**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1010/1010 green.

- [ ] **Step 9: Commit**

```bash
git add packages/mobile/lib/core/utils/haptics.dart packages/mobile/test/core/utils/haptics_test.dart packages/mobile/ios packages/mobile/android
git commit -m "feat(mobile): add the haptics seam and its notification-feedback channel"
```

---

### Task 8: Wire haptics into the shared widgets and the tab bar

**Files:**
- Modify: `lib/core/widgets/main_widgets/app_pill.dart`
- Modify: `lib/core/widgets/main_widgets/app_container.dart`
- Modify: `lib/core/widgets/main_widgets/primary_button.dart`
- Modify: `lib/core/widgets/main_widgets/global_appbar.dart`
- Modify: `lib/core/widgets/pickers/agent_picker_sheet.dart`
- Modify: `lib/core/widgets/pickers/project_picker_sheet.dart`
- Modify: `lib/core/widgets/pickers/theme_picker_sheet.dart`
- Modify: `lib/core/app_routes/home_shell.dart`
- Test: `test/core/utils/haptics_call_sites_test.dart`

**Interfaces:**
- Consumes: `Haptics.tap/select/success/warning/error` from Task 7.

Doing the shared widgets first covers the majority of RN's 65 call sites in eight files, because
RN's `ui.tsx` centralised the same way. The mapping, from the RN line to the verb:

| RN | Verb | Dart |
|---|---|---|
| `ui.tsx:88` (`Pill`) | `select` | `app_pill.dart` |
| `ui.tsx:155` (`Card`) | `tap` | `app_container.dart` |
| `ui.tsx:198` (`HeaderIconButton`) | `tap` | `global_appbar.dart` |
| `ui.tsx:300–301` (`Button`) | `warning` if danger, else `tap` | `primary_button.dart` |
| `ui.tsx:602–603` (`IconButton`) | `warning` if destructive, else `tap` | `global_appbar.dart` |
| `AgentPickerSheet.tsx:65` | `tap` | `agent_picker_sheet.dart` (refresh) |
| `AgentPickerSheet.tsx:98` | `select` | `agent_picker_sheet.dart` (choose) |
| `ProjectPickerSheet.tsx:38` | `select` | `project_picker_sheet.dart` |
| `ThemePickerSheet.tsx:41` | `select` | `theme_picker_sheet.dart` |
| `app/(tabs)/_layout.tsx:12` | `select` | `home_shell.dart` (`onTap`) |

`PrimaryButton` has no danger flag today. Add `this.isDestructive = false` next to `isLoading` and
branch on it, so the call sites in Tasks 9–10 that need `warning` can ask for it.

- [ ] **Step 1: Write the failing test**

Create `test/core/utils/haptics_call_sites_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> fired = <String>[];

  setUp(() {
    fired.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') fired.add('${call.arguments}');
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(Haptics.channelName),
      (call) async {
        fired.add('${call.arguments}');
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(Haptics.channelName), null);
  });

  Widget host(Widget child) => SkinScope(
        skin: const DarkSkin(),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  group('PrimaryButton haptics', () {
    testWidgets('a normal press taps', (tester) async {
      await tester.pumpWidget(host(PrimaryButton(text: 'Go', onPressed: () {})));
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(fired, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('a destructive press warns instead', (tester) async {
      await tester.pumpWidget(
        host(PrimaryButton(text: 'Kill', isDestructive: true, onPressed: () {})),
      );
      await tester.tap(find.text('Kill'));
      await tester.pump();
      expect(fired, ['warning']);
    });

    testWidgets('a disabled button fires nothing', (tester) async {
      await tester.pumpWidget(host(const PrimaryButton(text: 'Go', onPressed: null)));
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(fired, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/utils/haptics_call_sites_test.dart`
Expected: FAIL — `No named parameter with the name 'isDestructive'`.

- [ ] **Step 3: Add the flag and the feedback to `PrimaryButton`**

In `lib/core/widgets/main_widgets/primary_button.dart`, add `this.isDestructive = false` to both
constructors, add the field beside `isLoading`, and add the import plus a wrapped handler:

```dart
import 'package:operator_mobile/core/utils/haptics.dart';
```

```dart
  final bool isDestructive;

  void Function()? get _onPressed {
    final handler = onPressed;
    if (handler == null) return null;
    return () {
      if (isDestructive) {
        Haptics.warning();
      } else {
        Haptics.tap();
      }
      handler();
    };
  }
```

Then replace both `onPressed: isLoading ? () {} : onPressed,` occurrences with
`onPressed: isLoading ? () {} : _onPressed,`. A `null` `onPressed` still disables the button, so the
disabled case fires nothing without a special branch.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/core/utils/haptics_call_sites_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Wire the remaining seven files**

Each is the same shape: import `Haptics`, and call the verb from the table at the top of this task
as the first statement of the existing handler, before the callback it already invokes.

- `app_pill.dart` — `Haptics.select()` in `onTap`, only when `onTap != null`.
- `app_container.dart` — `Haptics.tap()` in its press handler, only when the container is tappable.
- `global_appbar.dart` — `Haptics.tap()` in the icon-button handlers; for any that take a
  `isDestructive`/`destructive` flag, `Haptics.warning()` instead.
- `agent_picker_sheet.dart` — `Haptics.tap()` on refresh, `Haptics.select()` on choosing an agent.
- `project_picker_sheet.dart` — `Haptics.select()` on choosing a project.
- `theme_picker_sheet.dart` — `Haptics.select()` on choosing a theme.
- `home_shell.dart` — `Haptics.select()` as the first line of the `BottomNavigationBar` `onTap`,
  matching RN's `screenListeners={{ tabPress: () => haptics.select() }}`. It fires on every tab
  press, including a re-tap of the active tab.

- [ ] **Step 6: Verify**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1013/1013 green.

If a widget test elsewhere now fails on an unmocked channel, mock it in that test's `setUp` the way
`haptics_call_sites_test.dart` does — do not remove the haptic to make the test pass.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib/core packages/mobile/test/core
git commit -m "feat(mobile): haptics on the shared widgets, pickers and tab bar"
```

---

### Task 9: Wire haptics into sessions, spawn, pairing, settings, orchestrator and notifications

**Files:**
- Modify: `lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart`
- Modify: `lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_actions_sheet.dart`
- Modify: `lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart`
- Modify: `lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart`
- Modify: `lib/feature/pairing/presentation/manual_connect_screen/ui/widgets/manual_connect_body.dart`
- Modify: `lib/feature/pairing/presentation/pairing_scan_screen/ui/widgets/pairing_scan_body.dart`
- Modify: `lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart`
- Modify: `lib/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_body.dart`
- Modify: `lib/feature/notification/presentation/notifications_screen/ui/widgets/notifications_body.dart`
- Modify: `lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pull_requests_body.dart`

**Interfaces:**
- Consumes: `Haptics` from Task 7, `PrimaryButton.isDestructive` from Task 8.

The mapping, from RN line to Dart target:

| RN | Verb | Dart |
|---|---|---|
| `SessionCard.tsx:47` | `tap` | `session_card.dart` — opening a session |
| `app/(tabs)/index.tsx:82` | `select` | `sessions_body.dart` — the filter row |
| `app/(tabs)/index.tsx:89` | `tap` | `sessions_body.dart` — pull-to-refresh |
| `app/(tabs)/index.tsx:190, 210` | `tap` | `session_actions_sheet.dart` — the action rows |
| `app/spawn.tsx:110` | `success` | `spawn_body.dart` — spawn succeeded |
| `app/spawn.tsx:95, 126` | `error` | `spawn_body.dart` — spawn failed, and the agent-catalog fetch failed |
| `app/spawn.tsx:235` | `select` | `spawn_body.dart` — the mode/option rows |
| `app/sheets/agent.tsx:51, 53` | `success` / `error` | `spawn_body.dart` — the agent refresh result |
| `ManualConnectSheet.tsx:55, 58` | `success` / `warning` | `manual_connect_body.dart` — connect succeeded / failed |
| `app/pair.tsx:105, 108` | `success` / `warning` | `pairing_scan_body.dart` — same two outcomes after a scan |
| `app/(tabs)/settings.tsx:147, 150` | `success` / `error` | `settings_body.dart` — saving daemon settings |
| `app/(tabs)/settings.tsx:227` | `tap` | `settings_body.dart` — the push toggle press |
| `app/(tabs)/settings.tsx:232, 234` | `success` / `error` | `settings_body.dart` — push registration result |
| `app/(tabs)/prs.tsx:61` | `tap` | `pull_requests_body.dart` — pull-to-refresh |
| `app/(tabs)/orchestrator.tsx:39` | `tap` | `orchestrator_body.dart` — pull-to-refresh |
| `app/(tabs)/orchestrator.tsx:129` | `select` | `orchestrator_body.dart` — picking an orchestrator |
| `app/(tabs)/orchestrator.tsx:140` | `error` | `orchestrator_body.dart` — launch failed |
| `app/notifications.tsx:90` | `tap` | `notifications_body.dart` — mark all read |

A pull-to-refresh haptic fires when the gesture commits, which for a `RefreshIndicator` means the
first line of the `onRefresh` callback — not on drag start.

- [ ] **Step 1: Write the failing test**

Append to `test/core/utils/haptics_call_sites_test.dart`, inside `main()`, a group covering the two
outcome verbs on the pairing screen, which is the highest-value case (it is the only place a user
gets feedback that a wrong password failed):

`ManualConnectCubit` emits `ConnectSuccessState` and `ConnectFailureState(ConnectionErrorCopy)`
(`manual_connect_state.dart`). The body listens to both, so the test drives the cubit's stream
rather than the network:

```dart
  group('manual connect haptics', () {
    testWidgets('a successful connect reports success', (tester) async {
      final cubit = MockManualConnectCubit();
      whenListen(
        cubit,
        Stream<ManualConnectState>.fromIterable([const ConnectSuccessState()]),
        initialState: const ManualConnectInitialState(),
      );
      await tester.pumpWidget(host(
        BlocProvider<ManualConnectCubit>.value(value: cubit, child: const ManualConnectBody()),
      ));
      await tester.pump();
      expect(fired, ['success']);
    });

    testWidgets('a failed connect warns', (tester) async {
      final cubit = MockManualConnectCubit();
      whenListen(
        cubit,
        Stream<ManualConnectState>.fromIterable([
          ConnectFailureState(describeConnectionFailure(
            ConnectionFailure.unauthorized,
            host: 'h',
            port: '3011',
            platformOs: 'ios',
          )),
        ]),
        initialState: const ManualConnectInitialState(),
      );
      await tester.pumpWidget(host(
        BlocProvider<ManualConnectCubit>.value(value: cubit, child: const ManualConnectBody()),
      ));
      await tester.pump();
      expect(fired, ['warning']);
    });
  });
```

`MockManualConnectCubit` is `class MockManualConnectCubit extends MockCubit<ManualConnectState>
implements ManualConnectCubit {}` — the pattern
`test/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit_test.dart`
already uses. Confirm `describeConnectionFailure`'s exact parameter names in
`lib/core/error_handling/connection_error.dart` before running; use whatever it declares.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/utils/haptics_call_sites_test.dart`
Expected: FAIL — `fired` is empty.

- [ ] **Step 3: Wire the call sites**

Work down the table above. In each file: import `Haptics`, then add the verb as the first statement
of the handler or the first statement of the state branch that corresponds to the RN line. For the
outcome verbs (`success`, `warning`, `error`) the trigger is the cubit state the screen already
listens to, not the button press — RN fires them after the await resolves, and firing on the press
instead would buzz before the daemon has answered.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/core/utils/haptics_call_sites_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1015/1015 green.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib/feature packages/mobile/test/core
git commit -m "feat(mobile): haptics on the board, spawn, pairing, settings and orchestrator"
```

---

### Task 10: Wire haptics into chat, terminal and voice

**Files:**
- Modify: `lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart`
- Modify: `lib/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart`
- Modify: `lib/feature/chat/presentation/chat_screen/ui/widgets/chat_markdown.dart`
- Modify: `lib/feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart`
- Modify: `lib/feature/chat/presentation/chat_screen/ui/widgets/chat_settings_sheet.dart`
- Modify: `lib/feature/chat/presentation/chat_screen/ui/widgets/approval_card.dart`
- Modify: `lib/feature/chat/voice/ui/mic_key.dart`
- Modify: `lib/feature/chat/voice/logic/voice_input_cubit.dart`
- Modify: `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart`
- Modify: `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart`
- Modify: `lib/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_sheet.dart`

The mapping:

| RN | Verb | Dart |
|---|---|---|
| `ChatComposer.tsx:98, 101` | `success` / `error` | `chat_composer.dart` — send succeeded / failed |
| `ChatComposer.tsx:222` | `tap` | `chat_composer.dart` — the composer icon buttons |
| `ChatTimeline.tsx:203, 393, 722` | `success` | `chat_timeline.dart` — copy response, long-press copy patch, long-press copy output |
| `ChatTimeline.tsx:718` | `tap` | `approval_card.dart` — an approval/elicitation action |
| `ChatMarkdown.tsx:95` | `success` | `chat_markdown.dart` — copy a code block |
| `ChatMarkdown.tsx:126` | `error` | `chat_markdown.dart` — a link that failed to open |
| `ChatSessionScreen.tsx:363` | `tap` | `conversation_menu_sheet.dart` — a menu row |
| `ChatSettingsModal.tsx:92` | `select` | `chat_settings_sheet.dart` — a radio choice |
| `MicKey.tsx:107` | `tap` | `mic_key.dart` — press-in |
| `useVoiceInput.ts:159` | `select` | `voice_input_cubit.dart` — the recogniser went live |
| `useVoiceInput.ts:230` | `tap` | `voice_input_cubit.dart` — latch toggled |
| `TerminalSessionScreen.tsx:871, 884, 892, 927, 1040` | `success` | `terminal_body.dart` — copy, paste, and the interface-transition completions |
| `TerminalSessionScreen.tsx:875, 897, 1043` | `error` | `terminal_body.dart` — the matching failures |
| `TerminalSessionScreen.tsx:940` | `tap` | `terminal_key_row.dart` — a special key |
| `TerminalSessionScreen.tsx:1052` | `warning` | `interface_switch_sheet.dart` — confirming a destructive switch |

`voice_input_cubit.dart` is the one non-widget in the list. Firing from the cubit is correct here —
RN fires from `useVoiceInput`, and the signal is "the microphone is live", which the UI learns about
only by watching the same state. Keep it out of `emit`: fire before the `emit` call, not inside a
listener.

- [ ] **Step 1: Write the failing test**

Append a group to `test/core/utils/haptics_call_sites_test.dart` covering the voice cubit, using
`test/feature/chat/voice/voice_input_cubit_test.dart`'s existing fake recogniser:

`VoiceInputCubit` takes a `VoiceProvider` and three injected durations
(`voice_input_cubit_test.dart` builds it that way). Reuse that file's `_FakeProvider` by copying it
into this test — it is 30 lines and copying keeps the two suites independent:

The two cubit-level haptics are precisely the two in `useVoiceInput.ts`: `select` when the mic
actually goes live (`:157–159` — the `starting`→`recording` transition, "the cue to start talking"),
and `tap` when a double-tap latches (`:230`). The press-in `tap` is `MicKey`'s, not the cubit's, so
this test must not expect it.

```dart
  group('voice haptics', () {
    test('the microphone going live selects', () async {
      final provider = FakeVoiceProvider();
      final cubit = buildCubit(provider);

      cubit.pressIn();
      await Future<void>.delayed(Duration.zero);
      expect(fired, isEmpty);

      provider.callbacks!.onStart();
      await Future<void>.delayed(Duration.zero);
      expect(fired, ['HapticFeedbackType.selectionClick']);

      await cubit.close();
    });

    test('latching on a double tap taps', () {
      fakeAsync((async) {
        final provider = FakeVoiceProvider();
        final cubit = buildCubit(provider);

        cubit.pressIn();
        cubit.pressOut();
        async.elapse(const Duration(milliseconds: 20));
        cubit.pressIn();
        async.flushMicrotasks();

        expect(fired, ['HapticFeedbackType.lightImpact']);
        cubit.close();
      });
    });
  });
```

`FakeVoiceProvider` is `voice_input_cubit_test.dart`'s `_FakeProvider`, renamed because it is
public here; `buildCubit` is that file's `build()` helper, which supplies the three injected
durations. The double-tap test needs `fake_async` because the latch decision runs on the
`doubleTapWindow` timer — follow the elapse pattern `voice_input_cubit_test.dart` already uses for
its own latch cases, including its exact threshold values.

Confirm the callback that signals "the microphone is live" in `voice_types.dart` before running —
the plan writes `onStart()`; use whatever `VoiceCallbacks` declares, and put `Haptics.select()` in
the cubit's handler for it, at the same `starting`→`recording` guard RN uses.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/utils/haptics_call_sites_test.dart`
Expected: FAIL — `fired` is empty.

- [ ] **Step 3: Wire the call sites**

Work down the table. Same rule as Task 9: press verbs go in the gesture handler, outcome verbs go in
the state branch after the await resolves.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/core/utils/haptics_call_sites_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1017/1017 green.

- [ ] **Step 6: Mark the gap closed**

In `docs/mobile-parity-ledger.md`, change the "Haptic feedback" row's status to
`Closed — M6 Tasks 7–10`.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib/feature packages/mobile/test/core docs/mobile-parity-ledger.md
git commit -m "feat(mobile): haptics on chat, terminal and voice"
```

---

### Task 11: Re-tapping the active tab scrolls it to the top

**Files:**
- Modify: `lib/core/app_routes/home_shell.dart`
- Modify: `lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart:60`
- Modify: `lib/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_body.dart:98`
- Modify: `lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pull_requests_body.dart:58`
- Modify: `lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart:193`
- Test: `test/core/app_routes/home_shell_test.dart` (extend)

**Interfaces:**
- Produces: `HomeShell.controllerFor(int tab)` returning the `ScrollController` that tab's list
  attaches to. Nothing outside the four bodies calls it.

RN gets this from `@react-navigation/native`'s `useScrollToTop`, which fires only when the pressed
tab is already focused. Flutter's `BottomNavigationBar` calls `onTap` for every press including a
re-tap, so the shell compares the pressed index with the current one.

All four bodies use a bare `ListView` with no controller today, so this is additive.

- [ ] **Step 1: Write the failing test**

Add to `test/core/app_routes/home_shell_test.dart`:

```dart
  testWidgets('re-tapping the active tab scrolls its list to the top', (tester) async {
    await tester.pumpWidget(hostedShell());
    await tester.pumpAndSettle();

    final controller = HomeShell.controllerFor(0);
    expect(controller.hasClients, isTrue);

    controller.jumpTo(400);
    await tester.pump();
    expect(controller.offset, 400);

    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('tapping a different tab switches without scrolling the old one', (tester) async {
    await tester.pumpWidget(hostedShell());
    await tester.pumpAndSettle();

    final agents = HomeShell.controllerFor(0);
    agents.jumpTo(400);
    await tester.pump();

    await tester.tap(find.text('PRs'));
    await tester.pumpAndSettle();

    expect(HomeShell.selectedTab.value, 2);
    expect(agents.offset, 400);
  });
```

`hostedShell()` is the existing helper in that file — reuse it. If the board's list is too short to
scroll in the test environment, seed the sessions cubit with enough rows that it is; follow the
seeding `test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart` already does.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/app_routes/home_shell_test.dart`
Expected: FAIL — `The method 'controllerFor' isn't defined for the type 'HomeShell'`.

- [ ] **Step 3: Give the shell the controllers**

In `lib/core/app_routes/home_shell.dart`, add beside `selectedTab`:

```dart
  static final List<ScrollController> _controllers = List<ScrollController>.generate(
    4,
    (_) => ScrollController(),
  );

  static ScrollController controllerFor(int tab) => _controllers[tab];
```

and replace the `onTap` handler:

```dart
        onTap: (next) {
          Haptics.select();
          if (next == HomeShell.selectedTab.value) {
            final controller = HomeShell.controllerFor(next);
            if (controller.hasClients && controller.offset > 0) {
              controller.animateTo(
                0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            }
            return;
          }
          HomeShell.selectedTab.value = next;
        },
```

The controllers are static and live as long as the shell's tabs do, which is the whole app session —
an `IndexedStack` keeps all four alive. Do not dispose them in `_HomeShellState.dispose`: the state
can rebuild while the controllers' lists stay mounted, and disposing a controller with clients
throws.

`Haptics.select()` is already there from Task 8. Keep it before the re-tap branch so a re-tap still
gives feedback, matching RN, where `tabPress` fires regardless.

- [ ] **Step 4: Attach the controllers**

In each of the four bodies, pass the controller to the existing `ListView`:

- `sessions_body.dart:60` → `controller: HomeShell.controllerFor(0),`
- `orchestrator_body.dart:98` → `controller: HomeShell.controllerFor(1),`
- `pull_requests_body.dart:58` → `controller: HomeShell.controllerFor(2),`
- `settings_body.dart:193` → `controller: HomeShell.controllerFor(3),`

The indices are the order of `HomeShell`'s `IndexedStack` children: Agents, Orchestrator, PRs,
Settings. Each body imports `package:operator_mobile/core/app_routes/home_shell.dart`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/core/app_routes/home_shell_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1019/1019 green.

A body widget test that mounts a body outside the shell will now attach a controller that no other
list uses — harmless. If one fails because two lists share a controller, the test is mounting two
bodies at once; give the second its own `ScrollController` in the test rather than changing the
production code.

- [ ] **Step 7: Mark the gap closed and commit**

In `docs/mobile-parity-ledger.md`, set the scroll-to-top row's status to `Closed — M6 Task 11`.

```bash
git add packages/mobile/lib packages/mobile/test docs/mobile-parity-ledger.md
git commit -m "feat(mobile): re-tapping the active tab scrolls it to the top"
```

---

### Task 12: `build_mode` can report `simulator` again

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/main.dart:33`
- Create: `lib/core/utils/device_kind.dart`
- Test: `test/core/utils/device_kind_test.dart`

**Interfaces:**
- Produces: `Future<bool> isPhysicalDevice()` in `lib/core/utils/device_kind.dart`.

`buildMobileContext` already maps `isPhysicalDevice: false` to `build_mode: 'simulator'` and is
tested. The gap is one hardcoded `true` at the only call site, which makes the `simulator` branch
unreachable in a real build — so every simulator run pollutes device counts.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:`, after `package_info_plus: ^10.2.1`:

```yaml
  device_info_plus: ^12.1.0
```

Run: `cd packages/mobile && flutter pub get`
Expected: resolves cleanly. If it conflicts, pin the highest version that resolves and record the
pinned version in this task's commit message.

- [ ] **Step 2: Write the failing test**

Create `test/core/utils/device_kind_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/device_kind.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isPhysicalDevice', () {
    test('reports false when the platform plugin is unavailable', () async {
      expect(await isPhysicalDevice(), isFalse);
    });
  });
}
```

A unit test has no platform plugin, so the call throws a `MissingPluginException` and the function's
fallback decides the answer. `false` is the right fallback: an environment that cannot answer is not
a device, and over-reporting `device` is the bug being fixed.

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/utils/device_kind_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 4: Write the implementation**

Create `lib/core/utils/device_kind.dart`:

```dart
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

Future<bool> isPhysicalDevice() async {
  final plugin = DeviceInfoPlugin();
  try {
    if (Platform.isIOS) return (await plugin.iosInfo).isPhysicalDevice;
    if (Platform.isAndroid) return (await plugin.androidInfo).isPhysicalDevice;
    return false;
  } catch (_) {
    return false;
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/core/utils/device_kind_test.dart`
Expected: PASS, 1 test.

- [ ] **Step 6: Use it**

In `lib/main.dart`, add the import and replace line 33's `isPhysicalDevice: true,`:

```dart
import 'package:operator_mobile/core/utils/device_kind.dart';
```

```dart
  final physical = await isPhysicalDevice();
  TelemetryRuntime.init(
    context: TelemetryContextInput(
      platformOs: Platform.operatingSystem,
      isPhysicalDevice: physical,
      dev: kDebugMode,
      appVersion: packageInfo.version,
    ),
  );
```

Put the `await` next to the existing `await PackageInfo.fromPlatform()` so startup pays for one
round of plugin calls, not two in sequence at different points.

- [ ] **Step 7: Verify**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1020/1020 green.

- [ ] **Step 8: Mark the gap closed and commit**

In `docs/mobile-parity-ledger.md`, set the `build_mode` row's status to `Closed — M6 Task 12`.

```bash
git add packages/mobile/lib packages/mobile/test packages/mobile/pubspec.yaml packages/mobile/pubspec.lock docs/mobile-parity-ledger.md
git commit -m "fix(mobile): report the real device kind so build_mode can say simulator"
```

---

### Task 13: Vendor `speech_to_text`, with no behavior change

**Files:**
- Create: `packages/speech_to_text/` (from pub 7.4.0)
- Create: `packages/speech_to_text_platform_interface/` (from pub 2.4.0)
- Modify: `pubspec.yaml`
- Create: `packages/speech_to_text/FORK.md`

**Interfaces:**
- Produces: two workspace packages resolved by path instead of from pub. No API change yet.

The three capabilities RN had live in the packages' native code and in `SpeechListenOptions`, which
is declared in `speech_to_text_platform_interface`, not in `speech_to_text`. Both must be vendored:
the options class and the method-channel argument map are in the interface package, the Swift and
Kotlin plugins are in the implementation package.

`packages/mobile/packages/xterm` is the precedent — 94 tracked files, `resolution: workspace`, a
bare dependency line. Follow it exactly.

This task changes no behavior. Splitting the copy from the feature work means the "did vendoring
break anything?" question gets its own green suite before any code is edited.

- [ ] **Step 1: Copy both packages in**

```bash
cd packages/mobile
cp -R ~/.pub-cache/hosted/pub.dev/speech_to_text-7.4.0 packages/speech_to_text
cp -R ~/.pub-cache/hosted/pub.dev/speech_to_text_platform_interface-2.4.0 packages/speech_to_text_platform_interface
chmod -R u+w packages/speech_to_text packages/speech_to_text_platform_interface
rm -rf packages/speech_to_text/example
```

The pub cache is read-only, hence the `chmod`. The bundled `example/` is a full Flutter app and
would be picked up by the workspace — delete it.

- [ ] **Step 2: Make them workspace members**

In `packages/speech_to_text/pubspec.yaml`, add `resolution: workspace` under `version:`, and change
its dependency on the interface to a bare `speech_to_text_platform_interface:`. Do the same to
`packages/speech_to_text_platform_interface/pubspec.yaml` (add `resolution: workspace`).

In `packages/mobile/pubspec.yaml`, extend the workspace list and un-version the dependency:

```yaml
workspace:
  - packages/xterm
  - packages/speech_to_text
  - packages/speech_to_text_platform_interface
```

```yaml
  speech_to_text:
```

- [ ] **Step 3: Record why the fork exists**

Create `packages/mobile/packages/speech_to_text/FORK.md`:

```markdown
# Why this package is vendored

Forked from `speech_to_text` 7.4.0 and `speech_to_text_platform_interface` 2.4.0 at M6 of the
Flutter mobile port, to recover three capabilities the published packages do not expose and the
RN app depended on:

- `contextualStrings` — biases the recogniser toward coding vocabulary ("git", not "get"; "npm",
  not "MPM"). iOS maps it to `SFSpeechRecognitionRequest.contextualStrings`, Android to
  `RecognizerIntent.EXTRA_BIASING_STRINGS`.
- The iOS audio-session configuration — push-to-talk wants the cheapest session that can capture
  (`.record`, no options, `.default` mode), latched dictation wants a Bluetooth-capable one
  (`.playAndRecord` with `.allowBluetooth` and `.defaultToSpeaker`, `.measurement` mode). The
  session cannot change mid-recording, so the mode is fixed at start. Measured warm-up difference
  is about 1.1s, dominated by Bluetooth HFP route negotiation.
- `EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS` on Android. The package already
  derives `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS` from `pauseFor`, but not this one,
  and both are needed to stop Android ending the session while the user is still thinking.

Changes are confined to `SpeechListenOptions`, the method-channel argument map,
`SpeechToTextPlugin.swift` and `SpeechToTextPlugin.kt`. Everything else is upstream 7.4.0 / 2.4.0
verbatim, including the checked-in `.g.dart` files — **do not run `build_runner` here.** The
repository bans generated code in first-party sources; these files are upstream artifacts and are
kept as shipped.

Upstream: https://github.com/csdcorp/speech_to_text
```

- [ ] **Step 4: Resolve and verify nothing moved**

Run: `cd packages/mobile && flutter pub get && flutter analyze && flutter test`
Expected: resolves, "No issues found!", 1020/1020 green — the same count as Task 12.

If `flutter analyze` reports issues inside the vendored packages, they are upstream's, not yours.
Add an `analysis_options.yaml` exclude for `packages/speech_to_text*/**` rather than editing
upstream code — the fork's diff must stay small enough to re-apply on an upgrade.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/packages/speech_to_text packages/mobile/packages/speech_to_text_platform_interface packages/mobile/pubspec.yaml packages/mobile/pubspec.lock packages/mobile/analysis_options.yaml
git commit -m "build(mobile): vendor speech_to_text and its platform interface"
```

---

### Task 14: Carry the three options through the Dart side of the fork

**Files:**
- Modify: `packages/speech_to_text_platform_interface/lib/speech_to_text_platform_interface.dart`
- Modify: `packages/speech_to_text_platform_interface/lib/method_channel_speech_to_text.dart`
- Test: `packages/mobile/test/feature/chat/voice/speech_listen_options_test.dart`

**Interfaces:**
- Produces: three new `SpeechListenOptions` fields —
  `List<String> contextualStrings` (default `const []`),
  `IosAudioSession? iosAudioSession`,
  `int? androidPossiblyCompleteSilenceMillis` —
  and the matching `listenParams` keys `contextualStrings`, `iosAudioCategory`,
  `iosAudioCategoryOptions`, `iosAudioMode`, `possiblyCompleteSilence`.
  Task 15 reads the iOS keys, Task 16 reads the Android ones, Task 17 sets them.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/chat/voice/speech_listen_options_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (call) async {
        calls.add(call);
        return true;
      },
    );
  });

  group('SpeechListenOptions', () {
    test('defaults send an empty vocabulary and no session override', () async {
      await SpeechToTextPlatform.instance.listen(options: SpeechListenOptions());
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['contextualStrings'], isEmpty);
      expect(args['iosAudioCategory'], isNull);
      expect(args['possiblyCompleteSilence'], isNull);
    });

    test('carries the vocabulary, the session and the Android silence extra', () async {
      await SpeechToTextPlatform.instance.listen(
        options: SpeechListenOptions(
          contextualStrings: const ['git', 'npm'],
          iosAudioSession: const IosAudioSession(
            category: 'playAndRecord',
            categoryOptions: ['allowBluetooth', 'defaultToSpeaker'],
            mode: 'measurement',
          ),
          androidPossiblyCompleteSilenceMillis: 10000,
        ),
      );
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['contextualStrings'], ['git', 'npm']);
      expect(args['iosAudioCategory'], 'playAndRecord');
      expect(args['iosAudioCategoryOptions'], ['allowBluetooth', 'defaultToSpeaker']);
      expect(args['iosAudioMode'], 'measurement');
      expect(args['possiblyCompleteSilence'], 10000);
    });

    test('copyWith preserves the three new fields', () {
      final base = SpeechListenOptions(
        contextualStrings: const ['git'],
        iosAudioSession: const IosAudioSession(category: 'record', categoryOptions: [], mode: 'default'),
        androidPossiblyCompleteSilenceMillis: 10000,
      );
      final copy = base.copyWith(partialResults: false);
      expect(copy.contextualStrings, ['git']);
      expect(copy.iosAudioSession?.category, 'record');
      expect(copy.androidPossiblyCompleteSilenceMillis, 10000);
    });
  });
}
```

The channel name is upstream's — confirm it in `method_channel_speech_to_text.dart` before running,
and use whatever that file declares.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/chat/voice/speech_listen_options_test.dart`
Expected: FAIL — `The named parameter 'contextualStrings' isn't defined`.

- [ ] **Step 3: Add the option type and the fields**

In `packages/speech_to_text_platform_interface/lib/speech_to_text_platform_interface.dart`, above
`class SpeechListenOptions`:

```dart
/// The iOS audio session a listen call should run under. The session cannot be
/// changed mid-recording, so the choice is fixed when listening starts: a
/// capture-only session activates fast, a Bluetooth-capable one is worth its
/// slower activation for a long hands-free phrase.
class IosAudioSession {
  const IosAudioSession({
    required this.category,
    required this.categoryOptions,
    required this.mode,
  });

  final String category;
  final List<String> categoryOptions;
  final String mode;
}
```

Add the three fields to `SpeechListenOptions`, its constructor and its `copyWith`, following the
shape of the fields already there:

```dart
  final List<String> contextualStrings;
  final IosAudioSession? iosAudioSession;
  final int? androidPossiblyCompleteSilenceMillis;
```

with constructor defaults `this.contextualStrings = const []`, `this.iosAudioSession = null`,
`this.androidPossiblyCompleteSilenceMillis = null`, and `copyWith` parameters
`List<String>? contextualStrings`, `IosAudioSession? iosAudioSession`,
`int? androidPossiblyCompleteSilenceMillis` forwarded with `?? this.<field>`.

- [ ] **Step 4: Add the channel arguments**

In `packages/speech_to_text_platform_interface/lib/method_channel_speech_to_text.dart`, extend
`listenParams`:

```dart
      "contextualStrings": options?.contextualStrings ?? const <String>[],
      "iosAudioCategory": options?.iosAudioSession?.category,
      "iosAudioCategoryOptions": options?.iosAudioSession?.categoryOptions,
      "iosAudioMode": options?.iosAudioSession?.mode,
      "possiblyCompleteSilence": options?.androidPossiblyCompleteSilenceMillis,
```

Null values ride the channel as null, which the native sides in Tasks 15 and 16 read as "keep
upstream's behavior". That is what makes this change safe for anyone calling `listen` without the
new options.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/chat/voice/speech_listen_options_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 6: Verify**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1023/1023 green.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/packages/speech_to_text_platform_interface packages/mobile/test/feature/chat/voice/speech_listen_options_test.dart
git commit -m "feat(mobile): carry contextual strings, the iOS session and the Android silence extra through the speech channel"
```

---

### Task 15: The iOS half of the fork

**Files:**
- Modify: `packages/speech_to_text/darwin/speech_to_text/Sources/speech_to_text/SpeechToTextPlugin.swift`

**Interfaces:**
- Consumes: the `contextualStrings`, `iosAudioCategory`, `iosAudioCategoryOptions` and
  `iosAudioMode` channel keys from Task 14.

Swift is not covered by `flutter test`. Verification is a build plus a device check, so this task
ends by building for the simulator rather than by a unit test — and the behavior itself is confirmed
in the milestone's device pass.

- [ ] **Step 1: Read the three sites you are changing**

```bash
cd packages/mobile/packages/speech_to_text/darwin/speech_to_text/Sources/speech_to_text
grep -n 'case SwiftSpeechToTextMethods.listen.rawValue' -A 40 SpeechToTextPlugin.swift
grep -n 'setCategory' -B 6 -A 12 SpeechToTextPlugin.swift
grep -n 'currentRequest = SFSpeechAudioBufferRecognitionRequest' -A 30 SpeechToTextPlugin.swift
```

The three sites are: the argument parse in the `listen` case (~line 145), the `setCategory` call
that configures the session (~line 520), and the request construction where `addsPunctuation` is
already set (~lines 551–574).

- [ ] **Step 2: Parse the new arguments**

In the `listen` case, after the existing `guard let ... enableHaptics` block, add:

```swift
      let contextualStrings = argsArr["contextualStrings"] as? [String] ?? []
      let audioCategory = argsArr["iosAudioCategory"] as? String
      let audioCategoryOptions = argsArr["iosAudioCategoryOptions"] as? [String] ?? []
      let audioMode = argsArr["iosAudioMode"] as? String
```

These are read outside the `guard` on purpose: a caller that omits them must still work, so they
are optional with defaults rather than required arguments.

Thread all four through to whatever private method the case calls (upstream's `listenForSpeech`)
by adding them as parameters with the same defaults.

- [ ] **Step 3: Honour the requested session**

At the `setCategory` call, replace the hardcoded configuration with the requested one, falling back
to upstream's when the caller sent nothing:

```swift
        let requestedCategory: AVAudioSession.Category? = {
          switch audioCategory {
          case "record": return .record
          case "playAndRecord": return .playAndRecord
          default: return nil
          }
        }()
        let requestedOptions: AVAudioSession.CategoryOptions = audioCategoryOptions.reduce(into: []) {
          partial, name in
          switch name {
          case "allowBluetooth": partial.insert(.allowBluetooth)
          case "defaultToSpeaker": partial.insert(.defaultToSpeaker)
          case "duckOthers": partial.insert(.duckOthers)
          case "mixWithOthers": partial.insert(.mixWithOthers)
          default: break
          }
        }
        let requestedMode: AVAudioSession.Mode? = {
          switch audioMode {
          case "measurement": return .measurement
          case "default": return .default
          default: return nil
          }
        }()

        if let category = requestedCategory {
          try self.audioSession.setCategory(
            category, mode: requestedMode ?? .default, options: requestedOptions)
        } else {
          // upstream's original setCategory call, unchanged
        }
```

Keep upstream's original call verbatim in the `else` branch — do not delete it. An upgrade three
versions from now has to be able to see what the fork changed and what it left alone.

- [ ] **Step 4: Set the contextual strings**

Where `currentRequest` is built, beside the existing `addsPunctuation` line:

```swift
      if !contextualStrings.isEmpty {
        currentRequest.contextualStrings = contextualStrings
      }
```

- [ ] **Step 5: Build for the simulator**

Run: `cd packages/mobile && flutter build ios --simulator --debug`
Expected: the build succeeds. This is the only compile check Swift gets — `flutter analyze` does
not read it.

If the build fails on a Swift 6 concurrency diagnostic in the vendored file, fix it in the
vendored file; do not disable the check for the whole target.

- [ ] **Step 6: Verify the Dart suite is untouched**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1023/1023 green.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/packages/speech_to_text/darwin
git commit -m "feat(mobile): honour contextual strings and the requested audio session on iOS"
```

---

### Task 16: The Android half of the fork

**Files:**
- Modify: `packages/speech_to_text/android/src/main/kotlin/com/csdcorp/speech_to_text/SpeechToTextPlugin.kt`

**Interfaces:**
- Consumes: the `contextualStrings` and `possiblyCompleteSilence` channel keys from Task 14.

Android needs less than iOS did. The package already derives
`EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS` from `pauseFor` (`SpeechToTextPlugin.kt:693`),
so the Dart already reproduces half of RN's intent through the existing `pauseFor: 10s`. Only the
biasing strings and the second silence extra are missing.

- [ ] **Step 1: Read the two sites you are changing**

```bash
cd packages/mobile/packages/speech_to_text/android/src/main/kotlin/com/csdcorp/speech_to_text
grep -n 'fun setupRecognizerIntent' -A 50 SpeechToTextPlugin.kt
grep -n 'setupRecognizerIntent(' SpeechToTextPlugin.kt
```

- [ ] **Step 2: Widen the intent builder**

Add two parameters to `setupRecognizerIntent`, defaulted so the two existing call sites (lines ~298
and ~650) keep compiling unchanged:

```kotlin
    private fun setupRecognizerIntent(
        languageTag: String,
        partialResults: Boolean,
        listenMode: ListenMode,
        onDevice: Boolean,
        pauseFor: Int?,
        contextualStrings: List<String> = emptyList(),
        possiblyCompleteSilence: Int? = null
    ) {
```

Inside the `Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply { ... }` block, beside the
existing `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS` line:

```kotlin
                        possiblyCompleteSilence?.let {
                            putExtra(
                                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                                it
                            )
                        }
                        // EXTRA_BIASING_STRINGS is API 33+. Below that the recogniser simply
                        // ignores the extra, so there is nothing to fall back to.
                        if (contextualStrings.isNotEmpty() &&
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                        ) {
                            putExtra(
                                RecognizerIntent.EXTRA_BIASING_STRINGS,
                                ArrayList(contextualStrings)
                            )
                        }
```

- [ ] **Step 3: Read the arguments and pass them down**

Where the plugin parses the `listen` call's arguments (the site that already reads `pauseFor`), add:

```kotlin
        val contextualStrings = call.argument<List<String>>("contextualStrings") ?: emptyList()
        val possiblyCompleteSilence = call.argument<Int>("possiblyCompleteSilence")
```

and pass both into the `setupRecognizerIntent` call at line ~298. Leave the call at ~650 (the
locale-details path) on its defaults — it is not a user-facing listen.

- [ ] **Step 4: Build for Android**

Run: `cd packages/mobile && flutter build apk --debug`
Expected: the build succeeds.

- [ ] **Step 5: Verify the Dart suite is untouched**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1023/1023 green.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/packages/speech_to_text/android
git commit -m "feat(mobile): bias the recogniser and widen the silence window on Android"
```

---

### Task 17: Restore the coding vocabulary and the two audio sessions

**Files:**
- Modify: `lib/feature/chat/voice/speech_recognizer.dart`
- Modify: `lib/feature/chat/voice/device_provider.dart`
- Test: `test/feature/chat/voice/device_provider_test.dart` (extend)

**Interfaces:**
- Consumes: `SpeechListenOptions.contextualStrings`, `.iosAudioSession`,
  `.androidPossiblyCompleteSilenceMillis` from Task 14.
- Produces: `SpeechRecognizer.listen` gains `required bool longForm`, and
  `const List<String> kCodingVocabulary` is exported from `device_provider.dart`.

This is the task that makes the previous four visible. `longForm` is the latched/push distinction
the UI already tracks — M5 kept it in the gesture logic but it stopped changing the audio session
when `speech_to_text` could not express one. It changes it again now.

- [ ] **Step 1: Write the failing test**

Add to `test/feature/chat/voice/device_provider_test.dart`:

```dart
  group('listen options', () {
    test('push-to-talk asks for the cheapest capture session', () async {
      final recognizer = SpeechToTextRecognizer(fake);
      await recognizer.listen(
        onResult: (_) {},
        pauseFor: const Duration(seconds: 10),
        listenFor: const Duration(seconds: 60),
        longForm: false,
      );
      final options = fake.lastOptions!;
      expect(options.iosAudioSession?.category, 'record');
      expect(options.iosAudioSession?.categoryOptions, isEmpty);
      expect(options.iosAudioSession?.mode, 'default');
    });

    test('latched dictation asks for a Bluetooth-capable session', () async {
      final recognizer = SpeechToTextRecognizer(fake);
      await recognizer.listen(
        onResult: (_) {},
        pauseFor: const Duration(seconds: 10),
        listenFor: const Duration(seconds: 60),
        longForm: true,
      );
      final options = fake.lastOptions!;
      expect(options.iosAudioSession?.category, 'playAndRecord');
      expect(options.iosAudioSession?.categoryOptions, ['allowBluetooth', 'defaultToSpeaker']);
      expect(options.iosAudioSession?.mode, 'measurement');
    });

    test('both modes bias the recogniser and widen the Android silence window', () async {
      final recognizer = SpeechToTextRecognizer(fake);
      await recognizer.listen(
        onResult: (_) {},
        pauseFor: const Duration(seconds: 10),
        listenFor: const Duration(seconds: 60),
        longForm: false,
      );
      expect(fake.lastOptions!.contextualStrings, kCodingVocabulary);
      expect(fake.lastOptions!.contextualStrings, contains('git'));
      expect(fake.lastOptions!.contextualStrings, contains('npm'));
      expect(fake.lastOptions!.androidPossiblyCompleteSilenceMillis, 10000);
    });
  });
```

The file's existing fake needs to record the options it was handed. If it does not already, give it
a `SpeechListenOptions? lastOptions` field assigned in its `listen` override.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/feature/chat/voice/device_provider_test.dart`
Expected: FAIL — `The named parameter 'longForm' isn't defined`.

- [ ] **Step 3: Add the vocabulary**

In `lib/feature/chat/voice/device_provider.dart`, at the top level — all 25 words from
`packages/mobile_rn/lib/voice/deviceProvider.ts:19–44`, verbatim and in the same order:

```dart
/// Biases the recogniser toward words that show up constantly in agent prompts
/// and would otherwise come back mangled ("get" for "git", "MPM" for "npm").
const List<String> kCodingVocabulary = [
  'git',
  'npm',
  'repo',
  'commit',
  'rebase',
  'branch',
  'merge',
  'PR',
  'diff',
  'refactor',
  'TypeScript',
  'JavaScript',
  'Go',
  'React',
  'Expo',
  'JSON',
  'API',
  'CLI',
  'daemon',
  'worktree',
  'regex',
  'localhost',
  'stack trace',
  'lint',
  'typecheck',
];
```

`'Expo'` is carried over deliberately. The spec's non-goal is explicit — behavior is ported as-is
and anything that looks wrong is raised separately — and this list is a recognition hint, not
product copy, so a stale word costs a negligible amount of bias and nothing else. Raise dropping it
(and adding `'Flutter'` and `'Dart'`) as a follow-up rather than deciding it inside the port.

- [ ] **Step 4: Widen the seam and pass the options**

In `lib/feature/chat/voice/speech_recognizer.dart`, add `required bool longForm` to the abstract
`listen` and to `SpeechToTextRecognizer.listen`, and extend the `SpeechListenOptions`:

```dart
    listenOptions: SpeechListenOptions(
      partialResults: true,
      autoPunctuation: true,
      cancelOnError: false,
      localeId: localeId,
      pauseFor: pauseFor,
      listenFor: listenFor,
      contextualStrings: kCodingVocabulary,
      androidPossiblyCompleteSilenceMillis: 10000,
      iosAudioSession: longForm
          ? const IosAudioSession(
              category: 'playAndRecord',
              categoryOptions: ['allowBluetooth', 'defaultToSpeaker'],
              mode: 'measurement',
            )
          : const IosAudioSession(
              category: 'record',
              categoryOptions: [],
              mode: 'default',
            ),
    ),
```

Import `kCodingVocabulary` from `device_provider.dart` and `IosAudioSession` from
`package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart`.

- [ ] **Step 5: Derive `longForm` from the mode the provider is already given**

`VoiceInputCubit` does not call `SpeechRecognizer` — it calls `VoiceProvider.start(callbacks,
{mode})`, and `DeviceVoiceProvider` (`device_provider.dart:82`) is what holds the recognizer and
calls `_recognizer.listen(...)` at line 141. The mode is therefore already at the right place, and
**no cubit change is needed**. At line 141, add:

```dart
        longForm: mode == VoiceMode.latched,
```

This matches RN, where `longForm` in `deviceProvider.ts:371` is likewise derived inside the
provider rather than threaded down from the hook.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/chat/voice`
Expected: PASS, 3 new tests plus the existing voice tests.

- [ ] **Step 7: Verify**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1026/1026 green.

- [ ] **Step 8: Update the ledger and commit**

In `docs/mobile-parity-ledger.md`, set the voice row's status to `Closed — M6 Tasks 13–17`, and
correct `lib/voice/deviceProvider.ts`'s note: the three capabilities are now ported, not lost.

```bash
git add packages/mobile/lib packages/mobile/test docs/mobile-parity-ledger.md
git commit -m "feat(mobile): restore the coding vocabulary and the two dictation audio sessions"
```

---

# Phase 3 — Retire the RN tree

### Task 18: Confirm the sweep, and record what outlives the port

**Files:**
- Modify: `docs/mobile-parity-ledger.md`

Nothing is deleted until the ledger is green and every gap it lists is closed. This task is the gate.

- [ ] **Step 1: Confirm the ledger is complete and green**

Run: `cd packages/mobile && flutter test test/parity_ledger_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 2: Confirm every gap is closed**

Read the "Open gaps" table. Every status must read `Closed — M6 Task N`. If Tasks 2–6 added a gap
this plan did not anticipate, it is either closed now or moved to the "What outlives the port"
section below with a written reason — it does not stay open while the RN tree is deleted.

- [ ] **Step 3: Add the closing sections**

Append to `docs/mobile-parity-ledger.md`:

```markdown
## Divergences from RN

The port's rule was "ported as-is; where the RN behavior looks wrong, port it and raise it
separately". These are the places the Dart deliberately does something else.

| Where | What differs | Why |
|---|---|---|
| `core/telemetry/rate_limit.dart` — `mergeRateState` | RN (`lib/telemetry/rateLimit.ts`) takes `Math.max` of `minuteStart` and `minuteCount` independently, so a restart can pair a fresh minute window with the previous minute's count and immediately report a name as capped. The Dart takes the whole newer minute window and keeps only `dayCount` as a max. | The RN form under-reports events after a restart. The daily ceiling — the real backstop — still uses `max`. **The same bug should be raised against `rateLimit.ts` and against the desktop sink if it shares the shape (`backend/internal/adapters/telemetry/ratelimit.go`).** |
| `feature/notification/logic/notification_view.dart` — `notificationTarget` | RN interpolates the session id raw; the Dart percent-encodes it. | The Dart consumer (`resolveDeepLinkPath`) decodes, so producer and consumer have to agree. RN's Expo Router consumed the raw path, so RN was self-consistent — this is port-local, not an RN bug. |
| `core/utils/haptics.dart` — `success`/`warning`/`error` on Android | `expo-haptics` maps notification feedback to Android's own patterns; the Dart uses `VibrationEffect` predefined effects, and `success` and `error` currently share `EFFECT_DOUBLE_CLICK`. | Android has no notification-feedback API. iOS is exact; Android is the closest stock approximation. If the two ever need to be distinguishable by feel, that is a waveform, not a predefined effect. |

## What outlives the port

Work that is deliberately not done, recorded so it is not rediscovered as a bug.

| Item | Why it is not done | What it needs |
|---|---|---|
| The PostHog sink behind `MobileTelemetryClient` | No project key exists — the desktop app dropped its own in `8ec08116e`, so a wired SDK would send nothing. Everything in front of the sink is built and tested: the sanitizer, the rate limiter, the daily-active tracker, the closed event vocabulary and the context builder. | A project key, then one file implementing `MobileTelemetryClient` over `posthog_flutter` and one line in `main.dart` passing it to `TelemetryRuntime.init`. |
| FCM/APNs push registration | A Firebase project, `google-services.json` and an APNs key are credentials only the repository owner can create. The decision logic is built and tested behind the `PushTokenSource` seam: `push_registrar.dart`, `push_registration.dart`, `push_status.dart`. Settings shows the switch and its state. | The credentials, then a `PushTokenSource` implementation over `firebase_messaging` and a tap handler routing through `DeepLinkService`. |
| A `feature_used {feature: merge}` capture | Not a gap. Neither app has a merge action — `lib/PRCard.tsx` and `app/(tabs)/prs.tsx` never called the endpoint. The allowlist keeps `merge` in its closed vocabulary so the event needs no schema change if a button ever lands. | A merge button, which would be a new feature, not a port. |
| The `speech_to_text` fork's upstream drift | `packages/mobile/packages/speech_to_text` is pinned at 7.4.0 with four changed files. | On upgrade, re-apply the diff described in `packages/speech_to_text/FORK.md`. |

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
```

- [ ] **Step 4: Verify**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1026/1026 green.

- [ ] **Step 5: Commit**

```bash
git add docs/mobile-parity-ledger.md
git commit -m "docs(mobile): close the parity sweep and record what outlives the port"
```

---

### Task 19: Delete `packages/mobile_rn`

**Files:**
- Delete: `packages/mobile_rn/`
- Delete: `.github/workflows/mobile.yml`
- Delete: `packages/mobile/test/parity_ledger_test.dart`
- Modify: `docs/mobile-parity-ledger.md`
- Modify: any file still referencing `mobile_rn`

This is the irreversible step, which is why it comes after the ledger is green and the gaps are
closed. Everything the RN tree knew is now either in `packages/mobile` or written down.

- [ ] **Step 1: Confirm nothing outside the ledger depends on it**

```bash
cd /Users/omaraly/development/AI/Operator
grep -rl "mobile_rn" --exclude-dir=node_modules --exclude-dir=.git . | sort
```

Expected: `docs/mobile-parity-ledger.md`, `.github/workflows/mobile.yml`,
`packages/mobile/test/parity_ledger_test.dart`, this plan, and the M0–M5 plans. Anything else —
a script, a CI job, `AGENTS.md`, `docs/STATUS.md`, a `package.json` workspace entry — is a real
reference and must be updated in Step 3.

Historical plans (`docs/superpowers/plans/2026-08-*`) are records of what was true when they were
written. Do not edit them.

- [ ] **Step 2: Delete the tree, its workflow and its test**

```bash
cd /Users/omaraly/development/AI/Operator
git rm -r --quiet packages/mobile_rn
git rm --quiet .github/workflows/mobile.yml
git rm --quiet packages/mobile/test/parity_ledger_test.dart
```

The ledger test goes with the tree it verified: with `mobile_rn` gone it can only fail, and its
final output is the tables it leaves behind.

- [ ] **Step 3: Update the surviving references**

In `docs/mobile-parity-ledger.md`, the header already says the test "was deleted with the RN tree at
M6" — confirm that sentence reads correctly in the past tense now that it is true.

Update any file Step 1 turned up. At minimum check `AGENTS.md` and `docs/STATUS.md` for a
`packages/mobile_rn` row in a package table or a "the RN app is frozen at `packages/mobile_rn`"
sentence, and replace it with a pointer to `docs/mobile-parity-ledger.md`.

- [ ] **Step 4: Verify**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", **1021/1021 green** — 1026 minus the 5 ledger tests.

This is the one point in the port where the suite is allowed to shrink, and only by exactly those
five. Any other drop means something depended on the RN tree.

Run: `grep -rn "mobile_rn" --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=plans .`
Expected: no hits outside `docs/mobile-parity-ledger.md`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(mobile): delete the frozen React Native app

The Flutter client at packages/mobile has been the only shipping mobile app
since M1. Every file in the RN tree is accounted for in
docs/mobile-parity-ledger.md — a destination, or a written reason it has none —
and the four behavioral gaps the sweep found are closed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 20: Milestone verification

**Files:** none

- [ ] **Step 1: The suite**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: "No issues found!", 1021/1021 green.

- [ ] **Step 2: Both release builds**

```bash
cd packages/mobile && flutter build apk --release
```

```bash
cd packages/mobile && flutter build ios --release --no-codesign
```

Expected: both succeed. M6 is the first milestone to touch native code in both trees (the haptics
plugins and the vendored speech fork), so a debug build passing is not enough.

- [ ] **Step 3: The device pass**

On a real phone against a real daemon, verify only what M6 changed:

- **Haptics** — a card press, a filter pill, and a tab press each feel different; a failed connect
  buzzes differently from a successful one; killing a session from the actions sheet warns rather
  than taps.
- **Scroll to top** — scroll the Agents board down, tap the Agents tab, and it returns to the top;
  tapping a different tab switches without moving the board.
- **Dictation** — hold the mic and say "git rebase the branch and open a PR"; the transcript keeps
  the coding words rather than mangling them. Double-tap to latch, and a Bluetooth headset's mic
  carries the audio; in push-to-talk the built-in mic is used and the key feels immediate.
- **Telemetry** — nothing is sent, by design. On a simulator, confirm the context would report
  `build_mode: simulator`; this is checked by reading `buildMobileContext`'s input, not by a
  network call.

- [ ] **Step 4: Confirm the milestone**

M6 is done when:

- `flutter analyze` → "No issues found!"
- `flutter test` → 1021/1021 green
- both release builds succeed
- `docs/mobile-parity-ledger.md` has a row for every RN file the port started with, no open gaps,
  and a written reason for each of the two subsystems that outlive it
- `packages/mobile_rn` does not exist, and nothing outside the ledger mentions it

At that point the spec's build order is complete: M0 through M6, and `packages/mobile` is the
mobile client.

---

## Execution order and what can be parallelised

- Tasks 1 → 6 are a chain: each appends to the table Task 1 opened, and Task 6's test builds on
  Task 1's parser.
- Task 7 blocks Tasks 8, 9 and 10. Tasks 8 → 9 → 10 are independent of each other once Task 7 and
  Task 8's `isDestructive` flag exist, but they touch overlapping directories, so running them in
  sequence avoids merge noise.
- Task 11 needs Task 8 only because both edit `home_shell.dart`.
- Task 12 is independent of everything and can run at any point after the baseline.
- Tasks 13 → 14 → (15 ‖ 16) → 17 are a chain, except that 15 and 16 are genuinely parallel — one
  touches Swift, the other Kotlin.
- Task 18 needs Tasks 1–17. Task 19 needs Task 18. Task 20 needs Task 19.

A reviewer can gate this as four units: the ledger (1–6), haptics (7–10), the small fixes (11–12),
the voice fork (13–17), and the retirement (18–20).
