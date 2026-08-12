# Flutter Mobile Port — M1 (Walking Skeleton) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A walking skeleton that runs against a real daemon on a real phone: pair (QR or manual)
→ land on the sessions Kanban board → see live session cards → kill/restore a session.

**Architecture:** Three new features (`pairing`, `onboarding`, `sessions`) land
under `lib/feature/`, following the layering M0 established (`data/` → `presentation/<screen>_screen/`).
`MuxClient` lands in `core/mux/` as a cross-cutting singleton, per the spec: the Kanban board and
the future terminal (M4) both depend on it for live session patches. Bootstrap in `main.dart`
decides synchronously between the onboarding route and the sessions route — no mounted "gate"
widget, unlike the RN reference, because Flutter's `initialRoute` is picked before `runApp` rather
than redirected-to after an async router mounts.

**Tech Stack:** Everything from M0, plus `mobile_scanner` (QR), `web_socket_channel` (mux socket),
`permission_handler` (camera permission / open-settings), `fake_async` (dev-only, mux reconnect
timing tests).

## Global Constraints

- Source spec: `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`.
- Source of truth for RN behavior: `packages/mobile_rn/` (frozen reference). Quoted verbatim
  throughout this plan; file paths below are relative to `packages/mobile_rn/` unless stated
  otherwise.
- Conventions are the `flutter-knowledge` skill. Where the mirrored RN source contradicts it, the
  skill wins. Invoke `flutter-testing` before the first test file, exactly as M0 did.
- Cubit only — never `Bloc` with events. Static-only classes are `sealed class X`. No comments
  except non-obvious business rules. Single quotes, `const` constructors, full 8-digit hex colors,
  `final` locals. No `flutter_screenutil` extensions outside `AppTextStyle`. No `drift`, no
  `freezed`, no `json_serializable`, no `build_runner`.
- Verification after every task: `flutter analyze` clean and `flutter test` green. New dependency
  versions below were verified conflict-free against the exact `packages/mobile/pubspec.yaml` this
  plan starts from (`flutter pub add <name>`, `flutter analyze`, `flutter test`, then reverted) —
  do not re-litigate the versions, add them as pinned.
- Package name is `operator_mobile`; imports are `package:operator_mobile/...`.
- All app state resolves under `~/.operator` — unaffected by this milestone, called out per
  `AGENTS.md`'s hard rule for completeness.

### New dependencies (pinned, verified conflict-free)

```yaml
dependencies:
  mobile_scanner: ^7.4.0
  web_socket_channel: ^3.0.3
  permission_handler: ^13.0.1

dev_dependencies:
  fake_async: ^1.3.3
```

### Deliberate deviations from the RN reference

The design's non-goal is "no behavior changes... ported as-is," but six places in this milestone
have a concrete engineering reason to depart from `mobile_rn`'s exact shape. Each is called out
again at its task; this table is the index.

| RN source | What it does | Why M1 departs |
|---|---|---|
| `lib/sheetResult.ts` | Parks a callback in a module-level `Map`, passes its key as a route **string** param, the opened route looks it up. | Exists only because Expo Router's file-based routes take serializable URL params — a callback can't ride in a URL. Flutter's `Navigator.push<T>()` returns a value to its caller natively, in-process. `ManualConnectScreen` pops `true`/`false`; the caller `await`s it. Not ported. |
| `lib/cameraLens.ts` (`pickNormalLens`) | Fuzzy-matches `AVCaptureDevice.localizedName` strings to avoid expo-camera's default virtual "Triple Camera" (whose widest lens is 0.5x ultra-wide). | `mobile_scanner`'s `MobileScannerController` takes a **typed** `lensType: CameraLensType.normal` — the exact problem RN's string heuristic works around is solved by the plugin's own enum. Ported as pure logic per the spec's test-mirroring ledger (Task 7), but the scan screen (Task 10) wires `CameraLensType.normal` directly, not `pickNormalLens`'s output. |
| `lib/disconnect.ts`, `lib/appInfo.ts` | "Forget server" and the About/build-info section. | Both are `app/(tabs)/settings.tsx`-only call sites (verified: `grep -rl forgetServer` / `bugReportBody` finds only `settings.tsx`). `settings` is an M2 feature; M1 ships no Settings tab. Deferred to M2, not ported now. |
| `lib/session/sendRoute.ts` | Decides whether a chat message re-routes to the terminal when the daemon answers `409 SESSION_AWAITING_DECISION`. | Its only call site is `lib/chat/ChatSessionScreen.tsx`'s composer. M1 ships no session-detail screen at all (`chat` is M3, `terminal` is M4) — there is no message composer anywhere in this milestone to route. Deferred to M3, where its consumer actually lands. |
| Spec's "sequential auth probing" forward-note (`m0.md`, "What M0 deliberately does not include") | `getSessions()` probes `/sessions` alone, then fans out to `/orchestrators` + `/projects` via `Promise.all`, so a bad password burns 1 failed auth per tick instead of 3. | M1's Kanban board needs **only** `GET /api/v1/sessions` — `SessionCard`'s project label is `shortLabel(session.projectId)` (the raw id, not `/projects`' friendly name), and M1 ships no project switcher or orchestrator tab to consume the other two calls. Fetching them now would be fetch-and-discard dead code. The single-call case trivially satisfies "probe alone" (there is nothing to fan out to). The ordering discipline becomes actionable — and gets its test — in M2, when the project switcher and orchestrator tab add the second and third call. This plan does not build it early. |
| `lib/sessionStatus.ts` (`attentionOf`'s server-trust branch), `s.attentionLevel` field | Trusts a server-provided `attentionLevel` before falling back to its own switch. | `backend/internal/domain/session.go`'s `Session`/`SessionRecord` structs have no `attentionLevel` JSON field, confirmed by reading them, and RN's own `mapSession()` never sets one. The branch can never fire against this daemon. `SessionModel` (Task 13) has no `attentionLevel` field and `attentionOf` implements only the fallback switch. |

Two additions to `core/` beyond `MuxClient` are also new, both because two features need the exact
same logic identically, not because either owns it:

- `core/error_handling/connection_error.dart` — connection-failure classification, used by both
  `pairing` (a failed pair attempt) and `sessions` (the board's error empty state uses the same
  vocabulary). Already the spec's own placement — see the test-mirroring ledger's
  `connectionError.test.ts` → `test/core/error_handling/connection_error_test.dart` row.
- A per-request `ServerConfig` override on `ApiConsumer`/`DioConsumer`/`ServerConfigInterceptor`
  (Task 7). Pairing must verify a **candidate** config before it is saved, but the interceptor
  normally stamps the base URL from `ServerConfigStore.current` — the already-paired config, which
  is `null` on a first pairing. Without this, verifying a first-time pairing would always fail
  before the request is even sent.

---

### Task 1: M1 dependencies and native camera permission

**Files:**
- Modify: `packages/mobile/pubspec.yaml`
- Modify: `packages/mobile/ios/Runner/Info.plist`
- Modify: `packages/mobile/android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: nothing.
- Produces: `mobile_scanner`, `web_socket_channel`, `permission_handler` importable; camera usable
  on both platforms once the OS permission prompt is answered.

- [ ] **Step 1: Add the dependencies**

```bash
cd packages/mobile
flutter pub add mobile_scanner:^7.4.0 web_socket_channel:^3.0.3 permission_handler:^13.0.1
flutter pub add dev:fake_async:^1.3.3
```

- [ ] **Step 2: Add the iOS camera usage string**

In `packages/mobile/ios/Runner/Info.plist`, add before the closing `</dict>` (after
`UISupportedInterfaceOrientations~ipad`'s `</array>`):

```xml
	<key>NSCameraUsageDescription</key>
	<string>Operator uses your camera to scan the pairing QR code shown by Connect Mobile.</string>
```

- [ ] **Step 3: Add the Android camera permission**

In `packages/mobile/android/app/src/main/AndroidManifest.xml`, add as the first child of
`<manifest>`, before `<application`:

```xml
    <uses-permission android:name="android.permission.CAMERA"/>
```

- [ ] **Step 4: Verify**

```bash
flutter analyze
flutter test
```

Expected: analyze clean, all existing M0 tests still passing (no new tests yet — this task only
adds dependencies and permission declarations).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(mobile): add M1 dependencies and camera permission"
```

---

### Task 2: ConnectionFailure classification

**Files:**
- Create: `packages/mobile/lib/core/error_handling/connection_error.dart`
- Test: `packages/mobile/test/core/error_handling/connection_error_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum ConnectionFailure { notOprQr, unreachable, auth, rateLimited, serverError }`
  - `ConnectionFailure classifyConnectionFailure(int? status)`
  - `bool shouldKeepPolling(int? status)`
  - `bool isLocalNetworkHost(String host)`
  - `class ConnectionErrorCopy { final String title; final String message; final bool showLocalNetworkHint; }`
  - `ConnectionErrorCopy describeConnectionFailure(ConnectionFailure reason, {required String host, required String port, required TargetPlatform platform})`
  - `const String kLocalNetworkHint`

Ported 1:1 from `lib/connectionError.ts` (full source quoted in this plan's research — the daemon
returns 401/403 for a bad password, 429 for the 5-failed-auth lockout; see
`backend/internal/httpd/auth.go`). `describeConnectionFailure`'s `platform` param takes Flutter's
`TargetPlatform` rather than RN's string union — compare against `TargetPlatform.iOS` for the
Local Network hint gate, matching RN's `platform === "ios"`.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/error_handling/connection_error_test.dart` (ported from
`connectionError.test.ts`):

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';

void main() {
  group('classifyConnectionFailure', () {
    test('treats no answer as unreachable', () {
      expect(classifyConnectionFailure(null), ConnectionFailure.unreachable);
    });

    test('maps 401 and 403 to auth', () {
      expect(classifyConnectionFailure(401), ConnectionFailure.auth);
      expect(classifyConnectionFailure(403), ConnectionFailure.auth);
    });

    test('maps 429 to rateLimited', () {
      expect(classifyConnectionFailure(429), ConnectionFailure.rateLimited);
    });

    test('maps any other status to serverError', () {
      expect(classifyConnectionFailure(500), ConnectionFailure.serverError);
      expect(classifyConnectionFailure(404), ConnectionFailure.serverError);
    });
  });

  group('isLocalNetworkHost', () {
    test('accepts the RFC1918 ranges', () {
      expect(isLocalNetworkHost('10.0.0.4'), isTrue);
      expect(isLocalNetworkHost('192.168.1.5'), isTrue);
      expect(isLocalNetworkHost('172.16.0.1'), isTrue);
      expect(isLocalNetworkHost('172.31.255.254'), isTrue);
    });

    test('rejects addresses just outside the 172.16/12 block', () {
      expect(isLocalNetworkHost('172.15.0.1'), isFalse);
      expect(isLocalNetworkHost('172.32.0.1'), isFalse);
    });

    test('accepts loopback, link-local, and mDNS names', () {
      expect(isLocalNetworkHost('127.0.0.1'), isTrue);
      expect(isLocalNetworkHost('169.254.1.1'), isTrue);
      expect(isLocalNetworkHost('localhost'), isTrue);
      expect(isLocalNetworkHost('my-pc.local'), isTrue);
    });

    test('rejects the Tailscale CGNAT range and public hosts', () {
      expect(isLocalNetworkHost('100.101.102.103'), isFalse);
      expect(isLocalNetworkHost('my-pc.tail1234.ts.net'), isFalse);
      expect(isLocalNetworkHost('203.0.113.7'), isFalse);
    });

    test('ignores surrounding whitespace and case', () {
      expect(isLocalNetworkHost('  My-PC.Local  '), isTrue);
    });

    test('rejects an empty host', () {
      expect(isLocalNetworkHost(''), isFalse);
      expect(isLocalNetworkHost('   '), isFalse);
    });
  });

  group('describeConnectionFailure', () {
    test('names the scanned address when nothing answered', () {
      final d = describeConnectionFailure(
        ConnectionFailure.unreachable,
        host: '192.168.1.5',
        port: '3011',
        platform: TargetPlatform.iOS,
      );
      expect(d.message, contains('192.168.1.5:3011'));
      expect(d.message, contains('same Wi-Fi'));
    });

    test('blames the password, not the network, on auth', () {
      final d = describeConnectionFailure(
        ConnectionFailure.auth,
        host: '192.168.1.5',
        port: '3011',
        platform: TargetPlatform.iOS,
      );
      expect(d.message, contains('rotated'));
      expect(d.message, isNot(contains('Wi-Fi')));
      expect(d.showLocalNetworkHint, isFalse);
    });

    test('gives every cause a distinct, non-empty title', () {
      final titles = ConnectionFailure.values
          .map((r) => describeConnectionFailure(r, host: '192.168.1.5', port: '3011', platform: TargetPlatform.iOS).title)
          .toList();
      expect(titles.every((t) => t.isNotEmpty), isTrue);
      expect(titles.toSet().length, titles.length);
      expect(
        describeConnectionFailure(ConnectionFailure.auth, host: '', port: '', platform: TargetPlatform.iOS).title,
        isNot(contains('disconnected')),
      );
      expect(
        describeConnectionFailure(ConnectionFailure.unreachable, host: '', port: '', platform: TargetPlatform.iOS).title,
        contains('disconnected'),
      );
    });

    test('explains the lockout on rateLimited, and that it clears itself', () {
      final d = describeConnectionFailure(ConnectionFailure.rateLimited, host: '', port: '', platform: TargetPlatform.iOS);
      expect(d.message, contains('locked this device out'));
      expect(d.message, contains('about a minute'));
    });

    test('points at the desktop logs on a server error', () {
      final d = describeConnectionFailure(ConnectionFailure.serverError, host: '', port: '', platform: TargetPlatform.iOS);
      expect(d.message, contains('Operator logs'));
    });

    test('rejects a non-Operator QR code without mentioning the network', () {
      final d = describeConnectionFailure(ConnectionFailure.notOprQr, host: '', port: '', platform: TargetPlatform.iOS);
      expect(d.message, contains("isn't an Operator pairing code"));
      expect(d.showLocalNetworkHint, isFalse);
    });

    group('the iOS Local Network hint', () {
      test('shows for an unreachable LAN host on iOS', () {
        final d = describeConnectionFailure(
          ConnectionFailure.unreachable,
          host: '192.168.1.5',
          port: '3011',
          platform: TargetPlatform.iOS,
        );
        expect(d.showLocalNetworkHint, isTrue);
      });

      test('does not show on Android, which has no such prompt', () {
        final d = describeConnectionFailure(
          ConnectionFailure.unreachable,
          host: '192.168.1.5',
          port: '3011',
          platform: TargetPlatform.android,
        );
        expect(d.showLocalNetworkHint, isFalse);
      });

      test('does not show for a Tailscale host', () {
        final d = describeConnectionFailure(
          ConnectionFailure.unreachable,
          host: '100.101.102.103',
          port: '3011',
          platform: TargetPlatform.iOS,
        );
        expect(d.showLocalNetworkHint, isFalse);
      });

      test('does not show when the server answered', () {
        final d = describeConnectionFailure(
          ConnectionFailure.auth,
          host: '192.168.1.5',
          port: '3011',
          platform: TargetPlatform.iOS,
        );
        expect(d.showLocalNetworkHint, isFalse);
      });
    });
  });

  group('shouldKeepPolling', () {
    test('stops on rejection', () {
      expect(shouldKeepPolling(401), isFalse);
      expect(shouldKeepPolling(403), isFalse);
      expect(shouldKeepPolling(429), isFalse);
    });

    test('keeps going on transient failures', () {
      expect(shouldKeepPolling(null), isTrue);
      expect(shouldKeepPolling(500), isTrue);
      expect(shouldKeepPolling(502), isTrue);
      expect(shouldKeepPolling(404), isTrue);
    });

    test('catches 403', () {
      expect(shouldKeepPolling(403), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/error_handling/connection_error_test.dart`
Expected: FAIL — `connection_error.dart` does not exist.

- [ ] **Step 3: Implement it**

`packages/mobile/lib/core/error_handling/connection_error.dart`:

```dart
import 'package:flutter/foundation.dart';

enum ConnectionFailure { notOprQr, unreachable, auth, rateLimited, serverError }

ConnectionFailure classifyConnectionFailure(int? status) {
  if (status == null) return ConnectionFailure.unreachable;
  if (status == 401 || status == 403) return ConnectionFailure.auth;
  if (status == 429) return ConnectionFailure.rateLimited;
  return ConnectionFailure.serverError;
}

bool shouldKeepPolling(int? status) {
  final failure = classifyConnectionFailure(status);
  return failure != ConnectionFailure.auth && failure != ConnectionFailure.rateLimited;
}

bool isLocalNetworkHost(String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty) return false;
  if (h == 'localhost' || h.endsWith('.local')) return true;
  final match = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
  if (match == null) return false;
  final a = int.parse(match.group(1)!);
  final b = int.parse(match.group(2)!);
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 169 && b == 254) return true;
  if (a == 127) return true;
  return false;
}

class ConnectionErrorCopy {
  const ConnectionErrorCopy({required this.title, required this.message, required this.showLocalNetworkHint});

  final String title;
  final String message;
  final bool showLocalNetworkHint;
}

ConnectionErrorCopy describeConnectionFailure(
  ConnectionFailure reason, {
  required String host,
  required String port,
  required TargetPlatform platform,
}) {
  final showLocalNetworkHint =
      reason == ConnectionFailure.unreachable && platform == TargetPlatform.iOS && isLocalNetworkHost(host);

  switch (reason) {
    case ConnectionFailure.notOprQr:
      return const ConnectionErrorCopy(
        title: 'Not an Operator pairing code',
        message: "That QR code isn't an Operator pairing code.",
        showLocalNetworkHint: false,
      );
    case ConnectionFailure.unreachable:
      return ConnectionErrorCopy(
        title: 'Your desktop disconnected',
        message: 'Reached nothing at $host:$port. '
            'Is Connect Mobile still on, and is your phone on the same Wi-Fi?',
        showLocalNetworkHint: showLocalNetworkHint,
      );
    case ConnectionFailure.auth:
      return const ConnectionErrorCopy(
        title: 'Your desktop rejected the password',
        message: 'That password was rotated. Re-scan the code on your computer.',
        showLocalNetworkHint: false,
      );
    case ConnectionFailure.rateLimited:
      return const ConnectionErrorCopy(
        title: 'Too many attempts',
        message: 'Your computer locked this device out after too many failed attempts. '
            "It clears on its own in about a minute — check the password, then try again.",
        showLocalNetworkHint: false,
      );
    case ConnectionFailure.serverError:
      return ConnectionErrorCopy(
        title: 'Your desktop returned an error',
        message: '$host:$port answered, but with an error. Check the Operator logs on your computer.',
        showLocalNetworkHint: false,
      );
  }
}

const String kLocalNetworkHint =
    'If you denied the Local Network prompt, enable it in Settings › Privacy & Security › Local Network › Operator.';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/core/error_handling/connection_error_test.dart`
Expected: PASS, all groups.

- [ ] **Step 5: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): port connection-failure classification"
```

---



### Task 3: Core widgets — AppTextField and AppDialog

**Files:**
- Create: `packages/mobile/lib/core/widgets/main_widgets/app_text_field.dart`
- Create: `packages/mobile/lib/core/widgets/dialog/app_dialog.dart`
- Test: `packages/mobile/test/core/widgets/app_text_field_test.dart`
- Test: `packages/mobile/test/core/widgets/app_dialog_test.dart`

**Interfaces:**
- Consumes: `context.skin` (M0 Task 11), `AppTextStyle` (M0 Task 10), `AppText` (M0 Task 12).
- Produces: `AppTextField({required controller, label, hintText, obscureText, keyboardType,
  textInputAction, onChanged, autocorrect, enabled})`; `AppDialog.confirm(context, {required
  title, required message, required confirmLabel, cancelLabel = 'Cancel', destructive = false}) →
  Future<bool>`.

Neither existed in M0's core widget set (M0 shipped no forms and no destructive-confirm flow).
`AppTextField` is first needed by the manual-connect form (Task 10); `AppDialog` is first needed
by the Kanban board's kill confirmation (Task 18) — mirroring RN's `Alert.alert` destructive-style
kill confirmation in `TerminalSessionScreen.tsx`.

- [ ] **Step 1: Write the failing AppTextField test**

`packages/mobile/test/core/widgets/app_text_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';

void main() {
  testWidgets('renders its label and reflects typed text in the controller', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: Scaffold(
            body: AppTextField(controller: controller, label: 'HOST', hintText: '192.168.1.5'),
          ),
        ),
      ),
    );

    expect(find.text('HOST'), findsOneWidget);
    expect(find.text('192.168.1.5'), findsNothing);

    await tester.enterText(find.byType(TextField), '10.0.0.5');
    expect(controller.text, '10.0.0.5');
  });

  testWidgets('obscures text when obscureText is set', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: Scaffold(body: AppTextField(controller: controller, obscureText: true)),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/widgets/app_text_field_test.dart`
Expected: FAIL — `app_text_field.dart` does not exist.

- [ ] **Step 3: Implement AppTextField**

`packages/mobile/lib/core/widgets/main_widgets/app_text_field.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.autocorrect = true,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final bool autocorrect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          AppText(label!, style: AppTextStyle.style12SemiBold.copyWith(color: skin.textSecondary)),
          const VerticalSpace(6),
        ],
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onChanged: onChanged,
          autocorrect: autocorrect,
          enabled: enabled,
          style: AppTextStyle.style15Regular.copyWith(color: skin.textPrimary),
          cursorColor: skin.accent,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: AppTextStyle.style15Regular.copyWith(color: skin.textFaint),
            filled: true,
            fillColor: skin.bgElevated,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: skin.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: skin.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: skin.accent),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/core/widgets/app_text_field_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 5: Write the failing AppDialog test**

`packages/mobile/test/core/widgets/app_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';

void main() {
  Future<bool?> pumpAndConfirm(WidgetTester tester, {required bool tapConfirm}) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: AppScaffold(
            body: Builder(
              builder: (context) => PrimaryButton(
                text: 'Kill',
                onPressed: () async {
                  result = await AppDialog.confirm(
                    context,
                    title: 'Kill session?',
                    message: 'This stops proj-1.',
                    confirmLabel: 'Kill',
                    destructive: true,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Kill').first);
    await tester.pumpAndSettle();
    expect(find.text('Kill session?'), findsOneWidget);
    expect(find.text('This stops proj-1.'), findsOneWidget);

    await tester.tap(find.text(tapConfirm ? 'Kill' : 'Cancel').last);
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('resolves true when confirmed', (tester) async {
    expect(await pumpAndConfirm(tester, tapConfirm: true), isTrue);
  });

  testWidgets('resolves false when cancelled', (tester) async {
    expect(await pumpAndConfirm(tester, tapConfirm: false), isFalse);
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `flutter test test/core/widgets/app_dialog_test.dart`
Expected: FAIL — `app_dialog.dart` does not exist.

- [ ] **Step 7: Implement AppDialog**

`packages/mobile/lib/core/widgets/dialog/app_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

sealed class AppDialog {
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final skin = context.skin;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: skin.bgElevated,
        title: AppText(title, style: AppTextStyle.style16SemiBold, maxLines: 2),
        content: AppText(
          message,
          style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: AppText(cancelLabel, style: AppTextStyle.style14Medium.copyWith(color: skin.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: AppText(
              confirmLabel,
              style: AppTextStyle.style14SemiBold.copyWith(color: destructive ? skin.red : skin.accent),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
```

- [ ] **Step 8: Run it to verify it passes**

Run: `flutter test test/core/widgets/app_dialog_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 9: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add AppTextField and AppDialog core widgets"
```

---

### Task 4: MuxSocket, SessionPatch, and the reconnect backoff

**Files:**
- Create: `packages/mobile/lib/core/mux/mux_socket.dart`
- Create: `packages/mobile/lib/core/mux/session_patch.dart`
- Create: `packages/mobile/lib/core/mux/mux_backoff.dart`
- Test: `packages/mobile/test/core/mux/session_patch_test.dart`
- Test: `packages/mobile/test/core/mux/mux_backoff_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `abstract class MuxSocket { Future<void> get ready; Stream<dynamic> get messages; void send(String data); Future<void> close(); }`
  - `class IOMuxSocket implements MuxSocket` with `factory IOMuxSocket.connect(Uri uri, Map<String, String> headers)`
  - `class SessionPatch extends Equatable` with `id`, `status`, `activity` (nullable), `attentionLevel`, `lastActivityAt`, and `SessionPatch.fromJson`
  - `sealed class MuxBackoff { static const int initialMs = 1000; static const int maxMs = 15000; static int next(int currentMs); }`

`MuxSocket` is deliberately narrower than `package:web_socket_channel`'s `WebSocketChannel`
interface — it exposes only the three operations `MuxClient` (Task 5) actually uses. This is what
makes `MuxClient` unit-testable without a real socket: a test fake only has to implement three
members, not `WebSocketChannel`'s full `StreamChannel` contract (`sink`, `stream`, `protocol`,
`closeCode`, `closeReason`, ...). `IOMuxSocket` is the production adapter over
`IOWebSocketChannel.connect`, verified present in `web_socket_channel: 3.0.3`'s `lib/io.dart`.

Protocol source: `lib/mux.ts` in `packages/mobile_rn` (full contents already quoted in this
project's research; message shapes and reconnect timing below are transcribed from it verbatim).
Backoff: starts at 1000ms, doubles on every failed/closed connection, caps at 15000ms, resets to
1000ms on every successful open — see `mux.ts`'s `private backoff = 1000` and `scheduleReconnect()`.

- [ ] **Step 1: Write the failing MuxBackoff test**

`packages/mobile/test/core/mux/mux_backoff_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/mux/mux_backoff.dart';

void main() {
  group('MuxBackoff', () {
    test('starts at one second', () {
      expect(MuxBackoff.initialMs, 1000);
    });

    test('doubles on every step', () {
      expect(MuxBackoff.next(1000), 2000);
      expect(MuxBackoff.next(2000), 4000);
      expect(MuxBackoff.next(4000), 8000);
    });

    test('caps at fifteen seconds', () {
      expect(MuxBackoff.next(8000), 15000);
      expect(MuxBackoff.next(15000), 15000);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/mux/mux_backoff_test.dart`
Expected: FAIL — `mux_backoff.dart` does not exist.

- [ ] **Step 3: Implement MuxBackoff**

`packages/mobile/lib/core/mux/mux_backoff.dart`:

```dart
import 'dart:math' as math;

sealed class MuxBackoff {
  static const int initialMs = 1000;
  static const int maxMs = 15000;

  static int next(int currentMs) => math.min(currentMs * 2, maxMs);
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/core/mux/mux_backoff_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Write the failing SessionPatch test**

`packages/mobile/test/core/mux/session_patch_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';

void main() {
  test('parses a mux sessions-snapshot entry', () {
    final patch = SessionPatch.fromJson({
      'id': 'proj-7',
      'status': 'working',
      'activity': 'active',
      'attentionLevel': 'working',
      'lastActivityAt': '2026-08-12T10:00:00Z',
    });

    expect(patch.id, 'proj-7');
    expect(patch.status, 'working');
    expect(patch.activity, 'active');
    expect(patch.attentionLevel, 'working');
    expect(patch.lastActivityAt, '2026-08-12T10:00:00Z');
  });

  test('tolerates a null activity', () {
    final patch = SessionPatch.fromJson({
      'id': 'proj-7',
      'status': 'idle',
      'activity': null,
      'attentionLevel': 'working',
      'lastActivityAt': '2026-08-12T10:00:00Z',
    });

    expect(patch.activity, isNull);
  });

  test('two patches with the same fields are equal', () {
    Map<String, dynamic> json() => {
      'id': 'proj-7',
      'status': 'working',
      'activity': 'active',
      'attentionLevel': 'working',
      'lastActivityAt': '2026-08-12T10:00:00Z',
    };
    expect(SessionPatch.fromJson(json()), SessionPatch.fromJson(json()));
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `flutter test test/core/mux/session_patch_test.dart`
Expected: FAIL — `session_patch.dart` does not exist.

- [ ] **Step 7: Implement SessionPatch and MuxSocket**

`packages/mobile/lib/core/mux/session_patch.dart`:

```dart
import 'package:equatable/equatable.dart';

class SessionPatch extends Equatable {
  const SessionPatch({
    required this.id,
    required this.status,
    required this.activity,
    required this.attentionLevel,
    required this.lastActivityAt,
  });

  final String id;
  final String status;
  final String? activity;
  final String attentionLevel;
  final String lastActivityAt;

  factory SessionPatch.fromJson(Map<String, dynamic> json) => SessionPatch(
    id: json['id'] as String,
    status: json['status'] as String,
    activity: json['activity'] as String?,
    attentionLevel: json['attentionLevel'] as String,
    lastActivityAt: json['lastActivityAt'] as String,
  );

  @override
  List<Object?> get props => [id, status, activity, attentionLevel, lastActivityAt];
}
```

`packages/mobile/lib/core/mux/mux_socket.dart`:

```dart
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

abstract class MuxSocket {
  Future<void> get ready;
  Stream<dynamic> get messages;
  void send(String data);
  Future<void> close();
}

class IOMuxSocket implements MuxSocket {
  IOMuxSocket(this._channel);

  factory IOMuxSocket.connect(Uri uri, Map<String, String> headers) =>
      IOMuxSocket(IOWebSocketChannel.connect(uri, headers: headers));

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get messages => _channel.stream;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.sink.close();
}
```

- [ ] **Step 8: Run it to verify it passes**

Run: `flutter test test/core/mux/session_patch_test.dart`
Expected: PASS, 3 tests. `mux_socket.dart` has no test of its own — `IOMuxSocket` is a thin adapter
exercised indirectly through `MuxClient`'s tests (Task 5) via the fake `MuxSocket` they inject.

- [ ] **Step 9: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add MuxSocket, SessionPatch, and the reconnect backoff"
```

---

### Task 5: MuxClient

**Files:**
- Create: `packages/mobile/lib/core/mux/mux_client.dart`
- Test: `packages/mobile/test/core/mux/mux_client_test.dart`

**Interfaces:**
- Consumes: `MuxSocket`, `IOMuxSocket` (Task 4), `SessionPatch` (Task 4), `MuxBackoff` (Task 4),
  `ServerConfig` (M0 Task 5).
- Produces:
  - `enum MuxStatus { connecting, open, closed, error }`
  - `sealed class TerminalEvent { final String id; }` with `TerminalDataEvent(id, Uint8List bytes)`,
    `TerminalOpenedEvent(id)`, `TerminalExitedEvent(id, int code)`, `TerminalErrorEvent(id, String message)`,
    `TerminalResizeEvent(id, int cols, int rows)`
  - `class MuxClient { MuxClient(ServerConfig cfg, {MuxSocket Function(Uri, Map<String,String>)? connect}); Stream<MuxStatus> get status; Stream<List<SessionPatch>> get sessionPatches; Stream<TerminalEvent> get terminalEvents; void connect(); void subscribeSessions(); void openTerminal(String id, {String? projectId}); void sendInput(String id, String data, {String? projectId}); void resize(String id, int cols, int rows, {String? projectId}); void closeTerminal(String id, {String? projectId}); Future<void> disconnect(); }`

Ported from `lib/mux.ts` (`packages/mobile_rn`), protocol-for-protocol. Three deliberate Dart
adaptations, all mechanical:

- RN hand-rolls base64/UTF-8 codecs because Hermes doesn't guarantee `atob`/`btoa`. Dart's
  `dart:convert` (`base64Encode`, `base64Decode`, `utf8`) are the direct, built-in equivalent — no
  hand-rolling needed.
- RN exposes a `Handlers` callback-object; this Dart port exposes broadcast `Stream`s instead, per
  the spec's explicit shape ("Dart: a MuxClient singleton over web_socket_channel exposing
  broadcast streams").
- The `Origin: http://localhost` pin exists because the daemon's CORS guard 403s any non-loopback
  Origin before the WS upgrade, and RN's WebSocket auto-sets Origin to the phone's LAN address.
  `IOWebSocketChannel.connect`'s `headers` map carries the same pin on Dart/`dart:io`.

Not built yet in M1: nothing consumes `terminalEvents`, `openTerminal`, `sendInput`, `resize`, or
`closeTerminal` until the M4 terminal feature. They are still built now, correctly, because the
protocol is fully specified in the spec's Realtime section and `MuxClient` is a cross-cutting
singleton the Kanban board (this milestone) and the terminal (M4) both depend on — building half
the protocol now and the other half in M4 would mean either an incompatible re-cut of this file
later or an M4 task that can't independently test against the real wire shape.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/mux/mux_client_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/mux/mux_backoff.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/mux_socket.dart';

class _FakeMuxSocket implements MuxSocket {
  final _incoming = StreamController<dynamic>.broadcast();
  final List<String> sent = [];
  bool closed = false;

  @override
  Future<void> get ready => Future.value();

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }

  void pushMessage(Map<String, dynamic> message) => _incoming.add(jsonEncode(message));

  void closeFromServer() => _incoming.close();
}

const _config = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12');

void main() {
  group('MuxClient', () {
    test('pins the loopback Origin and the auth header on connect', () {
      Uri? capturedUri;
      Map<String, String>? capturedHeaders;
      final client = MuxClient(
        _config,
        connect: (uri, headers) {
          capturedUri = uri;
          capturedHeaders = headers;
          return _FakeMuxSocket();
        },
      );

      client.connect();

      expect(capturedUri, Uri.parse('ws://10.0.0.5:3011/mux'));
      expect(capturedHeaders?['Origin'], 'http://localhost');
      expect(capturedHeaders?['Authorization'], 'Bearer secret12');
    });

    test('decodes a sessions snapshot into SessionPatch', () async {
      late _FakeMuxSocket socket;
      final client = MuxClient(_config, connect: (_, __) => socket = _FakeMuxSocket());
      client.connect();
      await Future<void>.delayed(Duration.zero);

      final patches = <List<dynamic>>[];
      client.sessionPatches.listen(patches.add);

      socket.pushMessage({
        'ch': 'sessions',
        'type': 'snapshot',
        'sessions': [
          {'id': 'proj-1', 'status': 'working', 'activity': 'active', 'attentionLevel': 'working', 'lastActivityAt': 't'},
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(patches, hasLength(1));
      expect(patches.first, hasLength(1));
      expect((patches.first.first as dynamic).id, 'proj-1');
    });

    test('decodes base64 terminal data', () async {
      late _FakeMuxSocket socket;
      final client = MuxClient(_config, connect: (_, __) => socket = _FakeMuxSocket());
      client.connect();
      await Future<void>.delayed(Duration.zero);

      final events = <dynamic>[];
      client.terminalEvents.listen(events.add);

      socket.pushMessage({'ch': 'terminal', 'id': 's1', 'type': 'data', 'data': base64Encode(utf8.encode('hi'))});
      await Future<void>.delayed(Duration.zero);

      final event = events.single as TerminalDataEvent;
      expect(event.id, 's1');
      expect(utf8.decode(event.bytes), 'hi');
    });

    test('sendInput base64-encodes the payload', () async {
      late _FakeMuxSocket socket;
      final client = MuxClient(_config, connect: (_, __) => socket = _FakeMuxSocket());
      client.connect();
      await Future<void>.delayed(Duration.zero);

      client.sendInput('s1', 'ls -la', projectId: 'p1');

      final sent = jsonDecode(socket.sent.last) as Map<String, dynamic>;
      expect(sent['ch'], 'terminal');
      expect(sent['type'], 'data');
      expect(sent['data'], base64Encode(utf8.encode('ls -la')));
      expect(sent['projectId'], 'p1');
    });

    test('re-subscribes and re-opens tracked terminals after a reconnect, with doubling backoff', () {
      fakeAsync((async) {
        var connectCount = 0;
        final sockets = <_FakeMuxSocket>[];
        final client = MuxClient(
          _config,
          connect: (_, __) {
            connectCount++;
            final socket = _FakeMuxSocket();
            sockets.add(socket);
            return socket;
          },
        );

        client.connect();
        async.flushMicrotasks();
        expect(connectCount, 1);

        client.subscribeSessions();
        client.openTerminal('s1', projectId: 'p1');
        expect(sockets[0].sent, hasLength(2));

        sockets[0].closeFromServer();
        async.elapse(Duration(milliseconds: MuxBackoff.initialMs - 1));
        expect(connectCount, 1, reason: 'reconnect not due yet');

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(connectCount, 2);

        final replayed = sockets[1].sent.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
        expect(replayed.any((m) => m['ch'] == 'subscribe'), isTrue);
        expect(replayed.any((m) => m['ch'] == 'terminal' && m['id'] == 's1' && m['type'] == 'open'), isTrue);

        sockets[1].closeFromServer();
        async.elapse(const Duration(milliseconds: 2000));
        async.flushMicrotasks();
        expect(connectCount, 3);

        client.disconnect();
      });
    });

    test('sends a ping every 20 seconds while connected', () {
      fakeAsync((async) {
        late _FakeMuxSocket socket;
        final client = MuxClient(_config, connect: (_, __) => socket = _FakeMuxSocket());
        client.connect();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 20));
        final pings = socket.sent.map((s) => jsonDecode(s) as Map<String, dynamic>).where((m) => m['ch'] == 'system');
        expect(pings, hasLength(1));

        client.disconnect();
      });
    });

    test('disconnect suppresses the reconnect', () {
      fakeAsync((async) {
        var connectCount = 0;
        late _FakeMuxSocket socket;
        final client = MuxClient(
          _config,
          connect: (_, __) {
            connectCount++;
            return socket = _FakeMuxSocket();
          },
        );
        client.connect();
        async.flushMicrotasks();
        expect(connectCount, 1);

        client.disconnect();
        socket.closeFromServer();
        async.elapse(const Duration(seconds: 20));
        expect(connectCount, 1);
      });
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/mux/mux_client_test.dart`
Expected: FAIL — `mux_client.dart` does not exist.

- [ ] **Step 3: Implement MuxClient**

`packages/mobile/lib/core/mux/mux_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/mux/mux_backoff.dart';
import 'package:operator_mobile/core/mux/mux_socket.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';

enum MuxStatus { connecting, open, closed, error }

sealed class TerminalEvent extends Equatable {
  const TerminalEvent(this.id);
  final String id;
}

final class TerminalDataEvent extends TerminalEvent {
  const TerminalDataEvent(super.id, this.bytes);
  final Uint8List bytes;
  @override
  List<Object?> get props => [id, bytes];
}

final class TerminalOpenedEvent extends TerminalEvent {
  const TerminalOpenedEvent(super.id);
  @override
  List<Object?> get props => [id];
}

final class TerminalExitedEvent extends TerminalEvent {
  const TerminalExitedEvent(super.id, this.code);
  final int code;
  @override
  List<Object?> get props => [id, code];
}

final class TerminalErrorEvent extends TerminalEvent {
  const TerminalErrorEvent(super.id, this.message);
  final String message;
  @override
  List<Object?> get props => [id, message];
}

final class TerminalResizeEvent extends TerminalEvent {
  const TerminalResizeEvent(super.id, this.cols, this.rows);
  final int cols;
  final int rows;
  @override
  List<Object?> get props => [id, cols, rows];
}

/// One WebSocket multiplexing session-status snapshots and per-session
/// terminal I/O. Auto-reconnects with backoff. See `lib/mux.ts` in
/// `packages/mobile_rn` for the RN reference this mirrors.
class MuxClient {
  MuxClient(this._cfg, {MuxSocket Function(Uri uri, Map<String, String> headers)? connect})
    : _connect = connect ?? IOMuxSocket.connect;

  final ServerConfig _cfg;
  final MuxSocket Function(Uri uri, Map<String, String> headers) _connect;

  final _statusController = StreamController<MuxStatus>.broadcast();
  final _sessionPatchesController = StreamController<List<SessionPatch>>.broadcast();
  final _terminalEventsController = StreamController<TerminalEvent>.broadcast();

  Stream<MuxStatus> get status => _statusController.stream;
  Stream<List<SessionPatch>> get sessionPatches => _sessionPatchesController.stream;
  Stream<TerminalEvent> get terminalEvents => _terminalEventsController.stream;

  MuxSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  bool _isOpen = false;
  bool _closedByUser = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _backoffMs = MuxBackoff.initialMs;
  final Map<String, String?> _openTerminals = {};
  bool _subscribed = false;

  void connect() {
    _closedByUser = false;
    unawaited(_open());
  }

  Future<void> _open() async {
    _statusController.add(MuxStatus.connecting);
    final uri = Uri.parse('${_cfg.wsBase}/mux');
    final headers = {
      'Origin': 'http://localhost',
      if (_cfg.password.isNotEmpty) 'Authorization': 'Bearer ${_cfg.password}',
    };

    final socket = _connect(uri, headers);
    _socket = socket;

    try {
      await socket.ready;
    } catch (_) {
      _statusController.add(MuxStatus.error);
      _scheduleReconnect();
      return;
    }

    _sub = socket.messages.listen(
      _onMessage,
      onError: (Object _) => _statusController.add(MuxStatus.error),
      onDone: _onClosed,
    );

    _isOpen = true;
    _backoffMs = MuxBackoff.initialMs;
    _statusController.add(MuxStatus.open);

    if (_subscribed) _send({'ch': 'subscribe', 'topics': ['sessions', 'notifications']});
    for (final entry in _openTerminals.entries) {
      _send({'ch': 'terminal', 'id': entry.key, 'type': 'open', 'projectId': entry.value, 'role': 'secondary'});
    }

    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) => _send({'ch': 'system', 'type': 'ping'}));
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final ch = msg['ch'] as String?;
    final type = msg['type'] as String?;

    if (ch == 'sessions' && type == 'snapshot') {
      final rawSessions = msg['sessions'] as List<dynamic>? ?? [];
      _sessionPatchesController.add(
        rawSessions.map((s) => SessionPatch.fromJson(s as Map<String, dynamic>)).toList(),
      );
      return;
    }

    if (ch == 'terminal') {
      final id = msg['id'] as String? ?? '';
      switch (type) {
        case 'data':
          _terminalEventsController.add(TerminalDataEvent(id, base64Decode(msg['data'] as String? ?? '')));
        case 'opened':
          _terminalEventsController.add(TerminalOpenedEvent(id));
        case 'exited':
          _terminalEventsController.add(TerminalExitedEvent(id, (msg['code'] as num?)?.toInt() ?? 0));
        case 'error':
          _terminalEventsController.add(
            TerminalErrorEvent(id, (msg['error'] ?? msg['message'] ?? 'terminal error') as String),
          );
        case 'resize':
          final cols = msg['cols'];
          final rows = msg['rows'];
          if (cols is num && rows is num && cols > 0 && rows > 0) {
            _terminalEventsController.add(TerminalResizeEvent(id, cols.toInt(), rows.toInt()));
          }
      }
    }
  }

  void _onClosed() {
    _isOpen = false;
    _clearPing();
    _statusController.add(MuxStatus.closed);
    if (!_closedByUser) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closedByUser) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _backoffMs), () => unawaited(_open()));
    _backoffMs = MuxBackoff.next(_backoffMs);
  }

  void _clearPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _send(Map<String, dynamic> obj) {
    if (_isOpen) _socket?.send(jsonEncode(obj));
  }

  void subscribeSessions() {
    _subscribed = true;
    _send({'ch': 'subscribe', 'topics': ['sessions', 'notifications']});
  }

  void openTerminal(String id, {String? projectId}) {
    _openTerminals[id] = projectId;
    _send({'ch': 'terminal', 'id': id, 'type': 'open', 'projectId': projectId, 'role': 'secondary'});
  }

  void sendInput(String id, String data, {String? projectId}) {
    _send({'ch': 'terminal', 'id': id, 'type': 'data', 'data': base64Encode(utf8.encode(data)), 'projectId': projectId});
  }

  void resize(String id, int cols, int rows, {String? projectId}) {
    _send({'ch': 'terminal', 'id': id, 'type': 'resize', 'cols': cols, 'rows': rows, 'projectId': projectId});
  }

  void closeTerminal(String id, {String? projectId}) {
    _openTerminals.remove(id);
    _send({'ch': 'terminal', 'id': id, 'type': 'close', 'projectId': projectId});
  }

  Future<void> disconnect() async {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _clearPing();
    _isOpen = false;
    await _sub?.cancel();
    await _socket?.close();
    _socket = null;
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/core/mux/mux_client_test.dart`
Expected: PASS, all 7 tests.

- [ ] **Step 5: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add MuxClient over the mux WebSocket protocol"
```

---

### Task 6: Per-request ServerConfig override, for verifying a candidate pairing

**Files:**
- Modify: `packages/mobile/lib/core/api/interceptors/server_config_interceptor.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/api_consumer.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart`
- Modify: `packages/mobile/test/core/api/server_config_interceptor_test.dart`

**Interfaces:**
- Consumes: `ServerConfigSource`, `ServerConfigInterceptor` (M0 Task 6).
- Produces: `ServerConfigInterceptor` honors `RequestOptions.extra['pairingTarget']` (a `ServerConfig`)
  ahead of `ServerConfigSource.current`; `ApiConsumer.get<T>` gains an `Options? options` parameter
  (the other three verbs already have one).

`ServerConfigInterceptor` stamps the base URL and `Authorization` header from
`ServerConfigStore.current` — the already-paired config. Pairing (Task 8) must verify a
**candidate** config before it is saved, and on a first-ever pairing `current` is `null`. Without
an override, `PairingRemoteDataSource.ping` would always hit the "No paired Operator server"
branch before the request is even sent, so first-time pairing could never succeed.

- [ ] **Step 1: Add the failing test to the existing interceptor test file**

Add this test to `packages/mobile/test/core/api/server_config_interceptor_test.dart`, inside the
existing `group('ServerConfigInterceptor', ...)`:

```dart
    test('a pairingTarget extra overrides the paired config', () {
      final interceptor = ServerConfigInterceptor(_StubStore(null));
      final target = const ServerConfig(host: '10.0.0.9', httpPort: '3011', secure: false, password: 'candidate');
      final options = RequestOptions(path: '/api/v1/sessions', extra: {'pairingTarget': target});
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.baseUrl, 'http://10.0.0.9:3011');
      expect(options.headers['Authorization'], 'Bearer candidate');
    });

    test('the paired config wins when no pairingTarget extra is set', () {
      final interceptor = ServerConfigInterceptor(
        _StubStore(const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'paired')),
      );
      final options = RequestOptions(path: '/api/v1/sessions');
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], 'Bearer paired');
    });
```

- [ ] **Step 2: Run it to verify the new tests fail**

Run: `flutter test test/core/api/server_config_interceptor_test.dart`
Expected: FAIL — the `pairingTarget` override test fails because `options.baseUrl` is empty (the
interceptor throws or falls through to `_source.current`, which is `null`, so it throws
`DioException` instead of stamping the candidate).

- [ ] **Step 3: Implement the override**

In `packages/mobile/lib/core/api/interceptors/server_config_interceptor.dart`, change `onRequest`:

```dart
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final override = options.extra['pairingTarget'] as ServerConfig?;
    final config = override ?? _source.current;
    if (config == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        message: 'No paired Operator server',
      );
    }

    options.baseUrl = config.httpBase;
    options.headers['Authorization'] = 'Bearer ${config.password}';
    handler.next(options);
  }
```

- [ ] **Step 4: Add `options` to ApiConsumer.get and thread it through DioConsumer**

In `packages/mobile/lib/core/api/api_request_helpers/api_consumer.dart`, add an `Options? options`
parameter to `get<T>`, matching the shape `post<T>` already has:

```dart
  Future<Response> get<T>(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(Map<String, dynamic>)? errorFromJsonT,
  });
```

In `packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart`, thread it through:

```dart
  @override
  Future<Response> get<T>(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(Map<String, dynamic>)? errorFromJsonT,
  }) async {
    try {
      return await client.get(path, queryParameters: queryParameters, data: body, options: options);
    } on DioException catch (error) {
      throw handleDioError(error);
    }
  }
```

- [ ] **Step 5: Run it to verify it passes**

Run: `flutter test test/core/api/server_config_interceptor_test.dart`
Expected: PASS, all 4 tests (2 from M0, 2 new).

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): allow a per-request ServerConfig override for pairing verification"
```

---

### Task 7: Pairing pure logic — QR payload parsing and camera lens selection

**Files:**
- Create: `packages/mobile/lib/feature/pairing/logic/pairing_payload.dart`
- Create: `packages/mobile/lib/feature/pairing/logic/camera_lens.dart`
- Test: `packages/mobile/test/feature/pairing/logic/pairing_payload_test.dart`
- Test: `packages/mobile/test/feature/pairing/logic/camera_lens_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class PairingPayload extends Equatable { final String host; final String port; final String password; }`
  - `PairingPayload? parsePairingPayload(String raw)`
  - `const String kNormalLens = 'Back Camera';`
  - `String? pickNormalLens(List<String> lenses)`

`parsePairingPayload` ports `lib/pairing.ts`'s `parsePairingPayload` (no RN test exists for it —
the RN app never had automated coverage here; this is new coverage, not a mirrored test). QR
payload contract, unchanged: `{"v":1,"host":"...","port":"...","password":"..."}` — `v` must equal
`1`, `host` a non-empty string, `port` a string or number, `password` optional (empty string when
absent, for back-compat with host+port-only codes).

`pickNormalLens` ports `lib/cameraLens.ts` 1:1, mirrored per the spec's test-mirroring ledger. Per
this plan's Global Constraints deviation table, it is **not** wired into the scan screen (Task 11)
— `mobile_scanner`'s `MobileScannerController(lensType: CameraLensType.normal)` already solves the
problem this heuristic works around, with a typed API rather than a fuzzy string match. It is
ported for parity of test coverage and because it is cheap, self-contained, and specified in full
by the RN source.

- [ ] **Step 1: Write the failing PairingPayload test**

`packages/mobile/test/feature/pairing/logic/pairing_payload_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/pairing/logic/pairing_payload.dart';

void main() {
  group('parsePairingPayload', () {
    test('parses a full payload', () {
      final payload = parsePairingPayload('{"v":1,"host":"10.0.0.5","port":"3011","password":"secret12"}');
      expect(payload, const PairingPayload(host: '10.0.0.5', port: '3011', password: 'secret12'));
    });

    test('accepts a numeric port', () {
      final payload = parsePairingPayload('{"v":1,"host":"10.0.0.5","port":3011}');
      expect(payload?.port, '3011');
      expect(payload?.password, '');
    });

    test('rejects a wrong or missing version', () {
      expect(parsePairingPayload('{"v":2,"host":"10.0.0.5","port":"3011"}'), isNull);
      expect(parsePairingPayload('{"host":"10.0.0.5","port":"3011"}'), isNull);
    });

    test('rejects an empty or missing host', () {
      expect(parsePairingPayload('{"v":1,"host":"","port":"3011"}'), isNull);
      expect(parsePairingPayload('{"v":1,"port":"3011"}'), isNull);
    });

    test('rejects a missing or wrongly-typed port', () {
      expect(parsePairingPayload('{"v":1,"host":"10.0.0.5"}'), isNull);
      expect(parsePairingPayload('{"v":1,"host":"10.0.0.5","port":true}'), isNull);
    });

    test('rejects malformed JSON and non-object payloads', () {
      expect(parsePairingPayload('not json'), isNull);
      expect(parsePairingPayload('"a string"'), isNull);
      expect(parsePairingPayload('[1,2,3]'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/pairing/logic/pairing_payload_test.dart`
Expected: FAIL — `pairing_payload.dart` does not exist.

- [ ] **Step 3: Implement PairingPayload**

`packages/mobile/lib/feature/pairing/logic/pairing_payload.dart`:

```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';

class PairingPayload extends Equatable {
  const PairingPayload({required this.host, required this.port, required this.password});

  final String host;
  final String port;
  final String password;

  @override
  List<Object?> get props => [host, port, password];
}

PairingPayload? parsePairingPayload(String raw) {
  dynamic parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return null;
  }

  if (parsed is! Map<String, dynamic>) return null;
  if (parsed['v'] != 1) return null;

  final host = parsed['host'];
  if (host is! String || host.isEmpty) return null;

  final port = parsed['port'];
  if (port is! String && port is! num) return null;

  final password = parsed['password'];
  return PairingPayload(host: host, port: port.toString(), password: password is String ? password : '');
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/pairing/logic/pairing_payload_test.dart`
Expected: PASS, all 6 tests.

- [ ] **Step 5: Write the failing camera lens test**

`packages/mobile/test/feature/pairing/logic/camera_lens_test.dart` (ported from
`cameraLens.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/pairing/logic/camera_lens.dart';

void main() {
  const triple = ['Back Camera', 'Back Dual Wide Camera', 'Back Telephoto Camera', 'Back Triple Camera', 'Back Ultra Wide Camera'];

  group('pickNormalLens', () {
    test('picks the plain 1x lens over the ultra-wide and the virtual devices', () {
      expect(pickNormalLens(triple), kNormalLens);
    });

    test('picks it on a dual-camera phone too', () {
      expect(pickNormalLens(['Back Camera', 'Back Dual Wide Camera', 'Back Ultra Wide Camera']), kNormalLens);
    });

    test('picks it on a single-camera phone', () {
      expect(pickNormalLens(['Back Camera']), kNormalLens);
    });

    test('returns null for an empty list', () {
      expect(pickNormalLens(const []), isNull);
    });

    test('returns null when every lens is a specialised optic', () {
      expect(pickNormalLens(['Back Ultra Wide Camera', 'Back Triple Camera']), isNull);
    });

    group('non-English devices, where the exact name will not match', () {
      test('prefers the unqualified lens by name length', () {
        final german = ['Rückkamera', 'Ultraweitwinkel-Rückkamera', 'Tele-Rückkamera'];
        expect(pickNormalLens(german), 'Rückkamera');
      });

      test('still drops virtual devices in other locales', () {
        final fr = ['Appareil arrière', 'Appareil arrière triple', 'Appareil arrière ultra grand-angle'];
        expect(pickNormalLens(fr), 'Appareil arrière');
      });
    });
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `flutter test test/feature/pairing/logic/camera_lens_test.dart`
Expected: FAIL — `camera_lens.dart` does not exist.

- [ ] **Step 7: Implement pickNormalLens**

`packages/mobile/lib/feature/pairing/logic/camera_lens.dart`:

```dart
const String kNormalLens = 'Back Camera';

const List<String> _qualifiers = [
  'ultra', 'telephoto', 'dual', 'triple', 'lidar', 'truedepth', 'continuity', 'desk',
];

String? pickNormalLens(List<String> lenses) {
  if (lenses.contains(kNormalLens)) return kNormalLens;

  final plain = lenses.where((lens) {
    final lower = lens.toLowerCase();
    return !_qualifiers.any(lower.contains);
  }).toList()
    ..sort((a, b) => a.length.compareTo(b.length));

  return plain.isEmpty ? null : plain.first;
}
```

- [ ] **Step 8: Run it to verify it passes**

Run: `flutter test test/feature/pairing/logic/camera_lens_test.dart`
Expected: PASS, all 7 tests.

- [ ] **Step 9: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add pairing QR payload parsing and camera lens selection"
```

---

### Task 8: Pairing data source and repository

**Files:**
- Create: `packages/mobile/lib/feature/pairing/data/data_source/pairing_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/pairing/data/repository/pairing_repository.dart`
- Test: `packages/mobile/test/feature/pairing/data/data_source/pairing_remote_data_source_test.dart`
- Test: `packages/mobile/test/feature/pairing/data/repository/pairing_repository_test.dart`

**Interfaces:**
- Consumes: `ApiConsumer` (M0 Task 6, extended Task 6 above), `ServerConfig`, `ServerConfigStore`
  (M0 Task 5), `EndPoints.sessions` (M0 Task 6), `Failure` (M0 Task 3), `FutureResult`/`Result`
  (M0 Task 3).
- Produces:
  - `abstract class PairingRemoteDataSource { Future<void> ping(ServerConfig target); }` + `PairingRemoteDataSourceImp`
  - `abstract class PairingRepository { FutureResult<bool> verifyAndConnect(ServerConfig target); }` + `PairingRepositoryImp`

`verifyAndConnect` is **not** gated on `NetworkStatus`, unlike the convention's usual repository
shape. `NetworkStatusImp.isConnected` (M0 Task 7) reflects reachability of the **already-paired**
daemon and returns `false` outright when nothing is paired yet (`_configSource.current == null`).
Gating pairing's own first-connection attempt on that check would make every first-time pairing
report "offline" before the request is ever sent. `ping` deliberately does not wrap its response in
`GlobalResponse` either — the pairing screens only care whether the request succeeded or threw, the
same shape as `NetworkStatusImp.isConnected`, not a data fetch.

Save-after-verify (not before) matches RN's `ManualConnectSheet.connect()` comment: verifying
first avoids persisting a candidate config the daemon just rejected.

- [ ] **Step 1: Write the failing data source test**

`packages/mobile/test/feature/pairing/data/data_source/pairing_remote_data_source_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/server_failure.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

const _target = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12');

void main() {
  late _MockApiConsumer api;
  late PairingRemoteDataSourceImp dataSource;

  setUp(() {
    api = _MockApiConsumer();
    dataSource = PairingRemoteDataSourceImp(api);
  });

  test('pings /sessions with the candidate config as a pairingTarget override', () async {
    when(() => api.get(any(), options: any(named: 'options'))).thenAnswer(
      (_) async => Response<dynamic>(requestOptions: RequestOptions(path: EndPoints.sessions), statusCode: 200),
    );

    await dataSource.ping(_target);

    final captured = verify(() => api.get(EndPoints.sessions, options: captureAny(named: 'options'))).captured;
    final options = captured.single as Options;
    expect(options.extra?['pairingTarget'], _target);
  });

  test('lets a Failure bubble uncaught', () {
    when(() => api.get(any(), options: any(named: 'options'))).thenThrow(ServerFailure.noNetwork());

    expect(() => dataSource.ping(_target), throwsA(isA<ServerFailure>()));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/pairing/data/data_source/pairing_remote_data_source_test.dart`
Expected: FAIL — `pairing_remote_data_source.dart` does not exist.

- [ ] **Step 3: Implement PairingRemoteDataSource**

`packages/mobile/lib/feature/pairing/data/data_source/pairing_remote_data_source.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config.dart';

abstract class PairingRemoteDataSource {
  Future<void> ping(ServerConfig target);
}

class PairingRemoteDataSourceImp implements PairingRemoteDataSource {
  PairingRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<void> ping(ServerConfig target) async {
    await _apiConsumer.get(EndPoints.sessions, options: Options(extra: {'pairingTarget': target}));
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/pairing/data/data_source/pairing_remote_data_source_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 5: Write the failing repository test**

`packages/mobile/test/feature/pairing/data/repository/pairing_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/server_failure.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';

class _MockPairingRemoteDataSource extends Mock implements PairingRemoteDataSource {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

const _target = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12');

void main() {
  late _MockPairingRemoteDataSource dataSource;
  late _MockServerConfigStore store;
  late PairingRepositoryImp repository;

  setUp(() {
    dataSource = _MockPairingRemoteDataSource();
    store = _MockServerConfigStore();
    repository = PairingRepositoryImp(dataSource, store);
  });

  test('saves the config only after the ping succeeds', () async {
    when(() => dataSource.ping(_target)).thenAnswer((_) async {});
    when(() => store.save(_target)).thenAnswer((_) async {});

    final result = await repository.verifyAndConnect(_target);

    expect(result.isSuccess, isTrue);
    verifyInOrder([() => dataSource.ping(_target), () => store.save(_target)]);
  });

  test('does not save when the ping fails', () async {
    final failure = ServerFailure.noNetwork();
    when(() => dataSource.ping(_target)).thenThrow(failure);

    final result = await repository.verifyAndConnect(_target);

    expect(result.isFailure, isTrue);
    verifyNever(() => store.save(any()));
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `flutter test test/feature/pairing/data/repository/pairing_repository_test.dart`
Expected: FAIL — `pairing_repository.dart` does not exist.

- [ ] **Step 7: Implement PairingRepository**

`packages/mobile/lib/feature/pairing/data/repository/pairing_repository.dart`:

```dart
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';

abstract class PairingRepository {
  FutureResult<bool> verifyAndConnect(ServerConfig target);
}

class PairingRepositoryImp implements PairingRepository {
  PairingRepositoryImp(this._remoteDataSource, this._serverConfigStore);

  final PairingRemoteDataSource _remoteDataSource;
  final ServerConfigStore _serverConfigStore;

  @override
  FutureResult<bool> verifyAndConnect(ServerConfig target) async {
    try {
      await _remoteDataSource.ping(target);
      await _serverConfigStore.save(target);
      return Result.success(true);
    } on Failure catch (error) {
      return Result.failure(error);
    }
  }
}
```

- [ ] **Step 8: Run it to verify it passes**

Run: `flutter test test/feature/pairing/data/repository/pairing_repository_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 9: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add the pairing data source and repository"
```

---

### Task 9: PairingScanCubit

**Files:**
- Create: `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart`
- Create: `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_state.dart`
- Test: `packages/mobile/test/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit_test.dart`

**Interfaces:**
- Consumes: `PairingRepository` (Task 8), `ServerConfigStore` (M0 Task 5), `parsePairingPayload`
  (Task 7), `classifyConnectionFailure`/`describeConnectionFailure` (Task 2).
- Produces: `PairingScanCubit(PairingRepository, ServerConfigStore, {required bool fromOnboarding})`
  with `Future<void> onScan(String raw, TargetPlatform platform)`; `sealed class PairingScanState`
  with `PairingScanInitialState`, `VerifyLoadingState`, `VerifySuccessState`,
  `VerifyFailureState(ConnectionErrorCopy copy)`.

Mirrors `app/pair.tsx`'s `onScan`/`verify` flow: a scanned payload that already fell through
`parsePairingPayload` shows the `notOprQr` copy; a valid payload carries over the currently-paired
`secure`/`password` when the QR omits a password (RN: `password: parsed.password || cfg.password`).
`_scanned` guards against `onDetect` firing repeatedly for the same frame while a verify is
in-flight, matching RN's `scanned.current` ref; it resets on failure so a second scan can retry.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/server_failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';

class _MockPairingRepository extends Mock implements PairingRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ServerConfig(host: '', httpPort: '', secure: false, password: ''));
  });

  late _MockPairingRepository repository;
  late _MockServerConfigStore store;

  setUp(() {
    repository = _MockPairingRepository();
    store = _MockServerConfigStore();
    when(() => store.current).thenReturn(null);
  });

  blocTest<PairingScanCubit, PairingScanState>(
    'rejects a non-Operator QR code without calling the repository',
    build: () => PairingScanCubit(repository, store, fromOnboarding: false),
    act: (cubit) => cubit.onScan('not json', TargetPlatform.iOS),
    expect: () => [isA<VerifyFailureState>()],
    verify: (_) => verifyNever(() => repository.verifyAndConnect(any())),
  );

  blocTest<PairingScanCubit, PairingScanState>(
    'verifies a valid payload and emits success',
    build: () {
      when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(true));
      return PairingScanCubit(repository, store, fromOnboarding: false);
    },
    act: (cubit) => cubit.onScan('{"v":1,"host":"10.0.0.5","port":"3011","password":"secret12"}', TargetPlatform.iOS),
    expect: () => [isA<VerifyLoadingState>(), isA<VerifySuccessState>()],
  );

  blocTest<PairingScanCubit, PairingScanState>(
    'carries over the currently-paired password when the QR omits one',
    build: () {
      when(() => store.current).thenReturn(
        const ServerConfig(host: 'old-host', httpPort: '3011', secure: true, password: 'old-pass'),
      );
      when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(true));
      return PairingScanCubit(repository, store, fromOnboarding: false);
    },
    act: (cubit) => cubit.onScan('{"v":1,"host":"10.0.0.5","port":"3011"}', TargetPlatform.iOS),
    verify: (_) {
      final captured = verify(() => repository.verifyAndConnect(captureAny())).captured;
      final target = captured.single as ServerConfig;
      expect(target.password, 'old-pass');
      expect(target.secure, isTrue);
    },
  );

  blocTest<PairingScanCubit, PairingScanState>(
    'emits a failure copy and allows retrying after a rejected password',
    build: () {
      when(() => repository.verifyAndConnect(any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401)),
      );
      return PairingScanCubit(repository, store, fromOnboarding: false);
    },
    act: (cubit) async {
      await cubit.onScan('{"v":1,"host":"10.0.0.5","port":"3011","password":"wrong"}', TargetPlatform.iOS);
      await cubit.onScan('{"v":1,"host":"10.0.0.5","port":"3011","password":"right"}', TargetPlatform.iOS);
    },
    verify: (_) => verify(() => repository.verifyAndConnect(any())).called(2),
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit_test.dart`
Expected: FAIL — `pairing_scan_cubit.dart` does not exist.

- [ ] **Step 3: Implement PairingScanState**

`packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_state.dart`:

```dart
part of 'pairing_scan_cubit.dart';

sealed class PairingScanState extends Equatable {
  const PairingScanState();

  @override
  List<Object?> get props => [];
}

final class PairingScanInitialState extends PairingScanState {
  const PairingScanInitialState();
}

final class VerifyLoadingState extends PairingScanState {
  const VerifyLoadingState();
}

final class VerifySuccessState extends PairingScanState {
  const VerifySuccessState();
}

final class VerifyFailureState extends PairingScanState {
  const VerifyFailureState(this.copy);

  final ConnectionErrorCopy copy;

  @override
  List<Object?> get props => [copy];
}
```

- [ ] **Step 4: Implement PairingScanCubit**

`packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/logic/pairing_payload.dart';

part 'pairing_scan_state.dart';

class PairingScanCubit extends Cubit<PairingScanState> {
  PairingScanCubit(this._repository, this._serverConfigStore, {required this.fromOnboarding})
    : super(const PairingScanInitialState());

  final PairingRepository _repository;
  final ServerConfigStore _serverConfigStore;
  final bool fromOnboarding;

  bool _scanned = false;

  Future<void> onScan(String raw, TargetPlatform platform) async {
    if (_scanned || state is VerifyLoadingState) return;

    final parsed = parsePairingPayload(raw);
    if (parsed == null) {
      emit(VerifyFailureState(describeConnectionFailure(ConnectionFailure.notOprQr, host: '', port: '', platform: platform)));
      return;
    }

    _scanned = true;
    final current = _serverConfigStore.current;
    final target = ServerConfig(
      host: parsed.host,
      httpPort: parsed.port,
      secure: current?.secure ?? false,
      password: parsed.password.isNotEmpty ? parsed.password : (current?.password ?? ''),
    );

    emit(const VerifyLoadingState());
    final result = await _repository.verifyAndConnect(target);
    result.when(
      onSuccess: (_) => emit(const VerifySuccessState()),
      onFailure: (failure) {
        _scanned = false;
        emit(
          VerifyFailureState(
            describeConnectionFailure(
              classifyConnectionFailure(failure.statusCode),
              host: target.host,
              port: target.httpPort,
              platform: platform,
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Run it to verify it passes**

Run: `flutter test test/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit_test.dart`
Expected: PASS, all 4 tests.

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add PairingScanCubit"
```

---

### Task 10: Pairing scan screen

**Files:**
- Create: `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/pairing_scan_screen.dart`
- Create: `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/widgets/pairing_scan_body.dart`
- Create: `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/widgets/camera_permission_gate.dart`
- Create: `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/widgets/connection_failure_banner.dart`
- Test: `packages/mobile/test/feature/pairing/presentation/pairing_scan_screen/ui/connection_failure_banner_test.dart`

**Interfaces:**
- Consumes: `PairingScanCubit`/`PairingScanState` (Task 9), `AppScaffold`/`GlobalAppbar`/`AppLoader`
  (M0 Task 12), `ConnectionErrorCopy` (Task 2), `mobile_scanner`'s `MobileScanner`/
  `MobileScannerController`/`Barcode`/`MobileScannerException`, `permission_handler`'s
  `openAppSettings()`.
- Produces: `PairingScanScreen` (routed as `RoutesStrings.pairingScan`).

Camera lens: `MobileScannerController(lensType: CameraLensType.normal)` — see Task 7's note; this
is the integration point that supersedes `pickNormalLens`. Only the `ConnectionFailureBanner`
widget is unit-tested here — `MobileScanner`'s camera preview needs a real platform camera and is
exercised by this milestone's final manual-verification task (Task 20), not `flutter test`.

- [ ] **Step 1: Write the failing banner test**

`packages/mobile/test/feature/pairing/presentation/pairing_scan_screen/ui/connection_failure_banner_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/connection_failure_banner.dart';

void main() {
  testWidgets('renders the title and message, and shows the Local Network hint when set', (tester) async {
    const copy = ConnectionErrorCopy(
      title: 'Your desktop disconnected',
      message: 'Reached nothing at 192.168.1.5:3011.',
      showLocalNetworkHint: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: Scaffold(body: ConnectionFailureBanner(copy: copy)),
        ),
      ),
    );

    expect(find.text('Your desktop disconnected'), findsOneWidget);
    expect(find.text('Reached nothing at 192.168.1.5:3011.'), findsOneWidget);
    expect(find.textContaining('Local Network'), findsOneWidget);
  });

  testWidgets('omits the hint when not set', (tester) async {
    const copy = ConnectionErrorCopy(title: 'Too many attempts', message: 'Wait a minute.', showLocalNetworkHint: false);

    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: Scaffold(body: ConnectionFailureBanner(copy: copy)),
        ),
      ),
    );

    expect(find.textContaining('Local Network'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/pairing/presentation/pairing_scan_screen/ui/connection_failure_banner_test.dart`
Expected: FAIL — `connection_failure_banner.dart` does not exist.

- [ ] **Step 3: Implement ConnectionFailureBanner**

`packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/widgets/connection_failure_banner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class ConnectionFailureBanner extends StatelessWidget {
  const ConnectionFailureBanner({super.key, required this.copy});

  final ConnectionErrorCopy copy;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppContainer(
      backgroundColor: skin.tintRed,
      border: Border.all(color: skin.red),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText(copy.title, style: AppTextStyle.style13SemiBold.copyWith(color: skin.red), maxLines: 2),
          const VerticalSpace(4),
          AppText(copy.message, style: AppTextStyle.style12Regular.copyWith(color: skin.textPrimary), maxLines: 4),
          if (copy.showLocalNetworkHint) ...[
            const VerticalSpace(8),
            AppText(kLocalNetworkHint, style: AppTextStyle.style11Regular.copyWith(color: skin.textSecondary), maxLines: 4),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/pairing/presentation/pairing_scan_screen/ui/connection_failure_banner_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 5: Implement CameraPermissionGate**

`packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/widgets/camera_permission_gate.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraPermissionGate extends StatelessWidget {
  const CameraPermissionGate({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined, color: skin.textSecondary, size: 40),
            const VerticalSpace(14),
            AppText(
              'Operator needs your camera to scan the pairing QR code.',
              style: AppTextStyle.style14Regular.copyWith(color: skin.textPrimary),
              textAlign: TextAlign.center,
              maxLines: 3,
            ),
            const VerticalSpace(20),
            PrimaryButton(text: 'Open Settings', onPressed: openAppSettings),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Implement the body and screen**

`packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/widgets/pairing_scan_body.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/camera_permission_gate.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/connection_failure_banner.dart';

class PairingScanBody extends StatefulWidget {
  const PairingScanBody({super.key});

  @override
  State<PairingScanBody> createState() => _PairingScanBodyState();
}

class _PairingScanBodyState extends State<PairingScanBody> {
  final _controller = MobileScannerController(lensType: CameraLensType.normal);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;
    context.read<PairingScanCubit>().onScan(raw, Theme.of(context).platform);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, exception) => exception.errorCode == MobileScannerErrorCode.permissionDenied
              ? const CameraPermissionGate()
              : const CameraPermissionGate(),
        ),
        BlocBuilder<PairingScanCubit, PairingScanState>(
          buildWhen: (previous, current) => current is VerifyLoadingState || current is VerifyFailureState || current is PairingScanInitialState,
          builder: (context, state) {
            if (state is VerifyLoadingState) {
              return ColoredBox(color: skin.scrim, child: const AppLoader.center());
            }
            if (state is VerifyFailureState) {
              return Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConnectionFailureBanner(copy: state.copy),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}
```

`packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/ui/pairing_scan_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/pairing_scan_body.dart';

class PairingScanScreen extends StatelessWidget {
  const PairingScanScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocListener<PairingScanCubit, PairingScanState>(
    listener: (context, state) {
      if (state is! VerifySuccessState) return;
      final fromOnboarding = context.read<PairingScanCubit>().fromOnboarding;
      if (fromOnboarding) {
        Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.sessions, (_) => false);
      } else {
        Navigator.of(context).pop();
      }
    },
    child: const AppScaffold(
      appBar: GlobalAppbar.sub(titleText: 'Scan pairing code'),
      body: PairingScanBody(),
    ),
  );
}
```

`errorBuilder` in `PairingScanBody` intentionally routes every `MobileScannerException` to
`CameraPermissionGate` for M1 — the only failure mode a fresh install can hit here is a denied or
not-yet-granted camera permission; other `MobileScannerErrorCode`s (unsupported hardware, already
in use) are out of scope for a walking skeleton and would need their own copy.

- [ ] **Step 7: Wire the manual-connect entry point (implemented fully in Task 11)**

Add a "Enter manually" text button to `PairingScanBody`, above the `BlocBuilder`'s failure banner,
that calls `Navigator.pushNamed(context, RoutesStrings.manualConnect)`. Leave this as the one
forward reference in this task — Task 11 builds the route it targets.

- [ ] **Step 8: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add the pairing QR scan screen"
```

---

### Task 11: ManualConnectCubit and the manual connect screen

**Files:**
- Create: `packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart`
- Create: `packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_state.dart`
- Create: `packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/ui/manual_connect_screen.dart`
- Create: `packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/ui/widgets/manual_connect_body.dart`
- Test: `packages/mobile/test/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit_test.dart`

**Interfaces:**
- Consumes: `PairingRepository` (Task 8), `ServerConfigStore` (M0 Task 5), `AppTextField`/`AppDialog`
  (Task 3), `ConnectionFailureBanner` (Task 10).
- Produces: `ManualConnectCubit(PairingRepository, ServerConfigStore)` with `hostController`,
  `portController`, `passwordController`, `bool get secure`, `void setSecure(bool)`,
  `Future<void> connect(TargetPlatform platform)`; `ManualConnectScreen` (routed as
  `RoutesStrings.manualConnect`, pops `true` on success).

Prefills from the currently-paired config, matching `ManualConnectSheet`'s `useEffect(() =>
{ loadConfig().then(setCfg) }, [])` — in Flutter, `ServerConfigStore` is already loaded at
bootstrap (M0's `main.dart`), so the cubit reads `serverConfigStore.current` synchronously in its
constructor's initializer list rather than an async effect. Verifies before saving, same as
`PairingRepository.verifyAndConnect` (Task 8) already does — this cubit does not persist anything
itself.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/server_failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';

class _MockPairingRepository extends Mock implements PairingRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ServerConfig(host: '', httpPort: '', secure: false, password: ''));
  });

  late _MockPairingRepository repository;
  late _MockServerConfigStore store;

  setUp(() {
    repository = _MockPairingRepository();
    store = _MockServerConfigStore();
  });

  blocTest<ManualConnectCubit, ManualConnectState>(
    'prefills from the currently-paired config',
    build: () {
      when(() => store.current).thenReturn(
        const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: true, password: 'secret12'),
      );
      return ManualConnectCubit(repository, store);
    },
    verify: (cubit) {
      expect(cubit.hostController.text, '10.0.0.5');
      expect(cubit.portController.text, '3011');
      expect(cubit.passwordController.text, 'secret12');
      expect(cubit.secure, isTrue);
    },
  );

  blocTest<ManualConnectCubit, ManualConnectState>(
    'defaults to port 3011 and secure off with nothing paired',
    build: () {
      when(() => store.current).thenReturn(null);
      return ManualConnectCubit(repository, store);
    },
    verify: (cubit) {
      expect(cubit.portController.text, '3011');
      expect(cubit.secure, isFalse);
    },
  );

  blocTest<ManualConnectCubit, ManualConnectState>(
    'trims the host and verifies before emitting success',
    build: () {
      when(() => store.current).thenReturn(null);
      when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(true));
      return ManualConnectCubit(repository, store);
    },
    act: (cubit) {
      cubit.hostController.text = '  10.0.0.9  ';
      cubit.portController.text = '3011';
      return cubit.connect(TargetPlatform.iOS);
    },
    expect: () => [isA<ConnectLoadingState>(), isA<ConnectSuccessState>()],
    verify: (_) {
      final captured = verify(() => repository.verifyAndConnect(captureAny())).captured;
      expect((captured.single as ServerConfig).host, '10.0.0.9');
    },
  );

  blocTest<ManualConnectCubit, ManualConnectState>(
    'emits a connection-failure copy when verification fails',
    build: () {
      when(() => store.current).thenReturn(null);
      when(() => repository.verifyAndConnect(any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401)),
      );
      return ManualConnectCubit(repository, store);
    },
    act: (cubit) {
      cubit.hostController.text = '10.0.0.9';
      cubit.portController.text = '3011';
      return cubit.connect(TargetPlatform.iOS);
    },
    expect: () => [isA<ConnectLoadingState>(), isA<ConnectFailureState>()],
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit_test.dart`
Expected: FAIL — `manual_connect_cubit.dart` does not exist.

- [ ] **Step 3: Implement ManualConnectState**

`packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_state.dart`:

```dart
part of 'manual_connect_cubit.dart';

sealed class ManualConnectState extends Equatable {
  const ManualConnectState();

  @override
  List<Object?> get props => [];
}

final class ManualConnectInitialState extends ManualConnectState {
  const ManualConnectInitialState();
}

final class SecureToggledState extends ManualConnectState {
  const SecureToggledState(this.secure);

  final bool secure;

  @override
  List<Object?> get props => [secure];
}

final class ConnectLoadingState extends ManualConnectState {
  const ConnectLoadingState();
}

final class ConnectSuccessState extends ManualConnectState {
  const ConnectSuccessState();
}

final class ConnectFailureState extends ManualConnectState {
  const ConnectFailureState(this.copy);

  final ConnectionErrorCopy copy;

  @override
  List<Object?> get props => [copy];
}
```

- [ ] **Step 4: Implement ManualConnectCubit**

`packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';

part 'manual_connect_state.dart';

class ManualConnectCubit extends Cubit<ManualConnectState> {
  ManualConnectCubit(this._repository, ServerConfigStore serverConfigStore)
    : hostController = TextEditingController(text: serverConfigStore.current?.host ?? ''),
      portController = TextEditingController(text: serverConfigStore.current?.httpPort ?? '3011'),
      passwordController = TextEditingController(text: serverConfigStore.current?.password ?? ''),
      _secure = serverConfigStore.current?.secure ?? false,
      super(const ManualConnectInitialState());

  final PairingRepository _repository;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController passwordController;
  bool _secure;

  bool get secure => _secure;

  void setSecure(bool value) {
    _secure = value;
    emit(SecureToggledState(value));
  }

  Future<void> connect(TargetPlatform platform) async {
    emit(const ConnectLoadingState());
    final target = ServerConfig(
      host: hostController.text.trim(),
      httpPort: portController.text.trim(),
      secure: _secure,
      password: passwordController.text,
    );
    final result = await _repository.verifyAndConnect(target);
    result.when(
      onSuccess: (_) => emit(const ConnectSuccessState()),
      onFailure: (failure) => emit(
        ConnectFailureState(
          describeConnectionFailure(
            classifyConnectionFailure(failure.statusCode),
            host: target.host,
            port: target.httpPort,
            platform: platform,
          ),
        ),
      ),
    );
  }

  @override
  Future<void> close() {
    hostController.dispose();
    portController.dispose();
    passwordController.dispose();
    return super.close();
  }
}
```

- [ ] **Step 5: Run it to verify it passes**

Run: `flutter test test/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit_test.dart`
Expected: PASS, all 4 tests.

- [ ] **Step 6: Build the screen**

`packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/ui/widgets/manual_connect_body.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/connection_failure_banner.dart';

class ManualConnectBody extends StatelessWidget {
  const ManualConnectBody({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ManualConnectCubit>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(controller: cubit.hostController, label: 'HOST', keyboardType: TextInputType.url),
          const VerticalSpace(14),
          AppTextField(controller: cubit.portController, label: 'API PORT', keyboardType: TextInputType.number),
          const VerticalSpace(14),
          AppTextField(controller: cubit.passwordController, label: 'PASSWORD', obscureText: true),
          const VerticalSpace(14),
          BlocBuilder<ManualConnectCubit, ManualConnectState>(
            buildWhen: (previous, current) => current is SecureToggledState,
            builder: (context, state) => Row(
              children: [
                Switch(value: cubit.secure, onChanged: cubit.setSecure, activeColor: context.skin.accent),
                const HorizontalSpace(8),
                const AppText('Use TLS (https/wss)'),
              ],
            ),
          ),
          const VerticalSpace(20),
          BlocBuilder<ManualConnectCubit, ManualConnectState>(
            buildWhen: (previous, current) => current is ConnectFailureState,
            builder: (context, state) => state is ConnectFailureState
                ? Padding(padding: const EdgeInsets.only(bottom: 16), child: ConnectionFailureBanner(copy: state.copy))
                : const SizedBox.shrink(),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: cubit.hostController,
            builder: (context, value, _) => BlocBuilder<ManualConnectCubit, ManualConnectState>(
              buildWhen: (previous, current) => current is ConnectLoadingState || current is ConnectFailureState,
              builder: (context, state) => PrimaryButton.expand(
                text: 'Connect',
                isLoading: state is ConnectLoadingState,
                onPressed: value.text.trim().isEmpty ? null : () => cubit.connect(Theme.of(context).platform),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

`packages/mobile/lib/feature/pairing/presentation/manual_connect_screen/ui/manual_connect_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/ui/widgets/manual_connect_body.dart';

class ManualConnectScreen extends StatelessWidget {
  const ManualConnectScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocListener<ManualConnectCubit, ManualConnectState>(
    listener: (context, state) {
      if (state is ConnectSuccessState) Navigator.of(context).pop(true);
    },
    child: const AppScaffold(
      appBar: GlobalAppbar.sub(titleText: 'Connect manually'),
      body: ManualConnectBody(),
    ),
  );
}
```

- [ ] **Step 7: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add ManualConnectCubit and the manual connect screen"
```

---

### Task 12: Onboarding — the first-run gate

**Files:**
- Create: `packages/mobile/lib/feature/onboarding/logic/onboarding.dart`
- Create: `packages/mobile/lib/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart`
- Create: `packages/mobile/lib/feature/onboarding/presentation/onboarding_screen/ui/widgets/onboarding_step.dart`
- Modify: `packages/mobile/lib/core/helpers/cache/cache_keys.dart`
- Create asset: `packages/mobile/assets/images/mascot.png` (copied from `packages/mobile_rn/assets/mascot.png`)
- Modify: `packages/mobile/pubspec.yaml`
- Test: `packages/mobile/test/feature/onboarding/logic/onboarding_test.dart`

**Interfaces:**
- Consumes: `CacheHelper`/`CacheKeys` (M0 Task 11), `RoutesStrings` (Task 13), `AppScaffold`/
  `AppText`/`PrimaryButton` (M0 Task 12).
- Produces: `bool shouldOnboard({required bool? configured, required bool? skipped})`;
  `OnboardingScreen` (routed as `RoutesStrings.onboarding`, `PopScope(canPop: false, ...)` — the
  gesture-disabled-back equivalent of RN's `gestureEnabled: false`).

`shouldOnboard` is ported 1:1 from `lib/onboarding.ts` (full `onboarding.test.ts` mirrored below —
7 cases, unchanged). Unlike RN's `OnboardingGate.tsx` — a headless component mounted at the router
root that watches navigation state and redirects once ready — Flutter's `initialRoute` is decided
**before** `runApp`, in `main.dart` (Task 19), by calling `shouldOnboard` directly with the values
`ServerConfigStore.current != null` and the persisted skip flag already available at that point. No
mounted gate widget, no "wait for navigation to be ready" dance: RN needs that dance only because
Expo Router mounts its navigator asynchronously and `OnboardingGate` has to wait for
`useRootNavigationState()?.key` before it may call `router.replace`.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/onboarding/logic/onboarding_test.dart` (ported from `onboarding.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/onboarding/logic/onboarding.dart';

void main() {
  group('shouldOnboard', () {
    test('onboards a fresh install', () {
      expect(shouldOnboard(configured: false, skipped: false), isTrue);
    });

    test('does not onboard once a server is configured', () {
      expect(shouldOnboard(configured: true, skipped: false), isFalse);
    });

    test('does not onboard after the user skipped', () {
      expect(shouldOnboard(configured: false, skipped: true), isFalse);
    });

    test('does not onboard when configured and skipped', () {
      expect(shouldOnboard(configured: true, skipped: true), isFalse);
    });

    test('waits while the config is still loading', () {
      expect(shouldOnboard(configured: null, skipped: false), isFalse);
    });

    test('waits while the skip flag is still loading', () {
      expect(shouldOnboard(configured: false, skipped: null), isFalse);
    });

    test('waits while both are still loading', () {
      expect(shouldOnboard(configured: null, skipped: null), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/onboarding/logic/onboarding_test.dart`
Expected: FAIL — `onboarding.dart` does not exist.

- [ ] **Step 3: Implement shouldOnboard**

`packages/mobile/lib/feature/onboarding/logic/onboarding.dart`:

```dart
bool shouldOnboard({required bool? configured, required bool? skipped}) {
  if (configured == null || skipped == null) return false;
  return !configured && !skipped;
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/onboarding/logic/onboarding_test.dart`
Expected: PASS, all 7 tests.

- [ ] **Step 5: Add the onboarding-skipped cache key**

In `packages/mobile/lib/core/helpers/cache/cache_keys.dart`, add:

```dart
  static const String onboardingSkipped = 'opr.onboardingSkipped';
```

- [ ] **Step 6: Copy the mascot asset and declare it**

```bash
mkdir -p packages/mobile/assets/images
cp packages/mobile_rn/assets/mascot.png packages/mobile/assets/images/mascot.png
```

In `packages/mobile/pubspec.yaml`, under `flutter: assets:`, add:

```yaml
    - assets/images/
```

- [ ] **Step 7: Build the welcome screen**

`packages/mobile/lib/feature/onboarding/presentation/onboarding_screen/ui/widgets/onboarding_step.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class OnboardingStep extends StatelessWidget {
  const OnboardingStep({super.key, required this.n, required this.title, required this.hint});

  final int n;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: skin.tintBlue,
            child: AppText('$n', style: AppTextStyle.style12SemiBold.copyWith(color: skin.blue)),
          ),
          const HorizontalSpace(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(title, style: AppTextStyle.style14SemiBold, maxLines: 2),
                const VerticalSpace(2),
                AppText(hint, style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary), maxLines: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

`packages/mobile/lib/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/onboarding/presentation/onboarding_screen/ui/widgets/onboarding_step.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  Future<void> _skip(BuildContext context) async {
    await CacheHelper.save(CacheKeys.onboardingSkipped, true);
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.sessions, (_) => false);
  }

  void _pair(BuildContext context) {
    Navigator.of(context).pushNamed(RoutesStrings.pairingScan, arguments: {'fromOnboarding': true});
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return PopScope(
      canPop: false,
      child: AppScaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset('assets/images/mascot.png', width: 28, height: 28),
                    const HorizontalSpace(8),
                    const AppText('Operator', style: AppTextStyle.style15SemiBold),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _skip(context),
                      child: AppText('Skip', style: AppTextStyle.style13Medium.copyWith(color: skin.textSecondary)),
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const VerticalSpace(24),
                        AppText('Connect your desktop', style: AppTextStyle.style24Bold, maxLines: 2),
                        const VerticalSpace(10),
                        AppText(
                          'Pair with Operator on your computer to check on your agents, jump into any '
                          'terminal, and drive work from your phone.',
                          style: AppTextStyle.style14Regular.copyWith(color: skin.textSecondary),
                          maxLines: 4,
                        ),
                        const VerticalSpace(20),
                        PrimaryButton(text: 'Pair Desktop', onPressed: () => _pair(context)),
                        const VerticalSpace(36),
                        AppText(
                          'HOW IT WORKS',
                          style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary),
                        ),
                        const VerticalSpace(14),
                        const OnboardingStep(
                          n: 1,
                          title: 'Open Operator on your computer',
                          hint: 'Go to Settings → Connect Mobile and turn it on.',
                        ),
                        const OnboardingStep(
                          n: 2,
                          title: 'Scan the code',
                          hint: 'Tap Pair Desktop above and point at the QR code on your screen.',
                        ),
                        const OnboardingStep(
                          n: 3,
                          title: "You're connected",
                          hint: 'Your sessions appear here, and you can drive them from your phone.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add the onboarding gate logic and welcome screen"
```

---

### Task 13: Session models, status, and attention logic

**Files:**
- Create: `packages/mobile/lib/feature/sessions/data/model/session_model.dart`
- Create: `packages/mobile/lib/feature/sessions/data/model/session_pr_model.dart`
- Create: `packages/mobile/lib/feature/sessions/logic/session_status.dart`
- Test: `packages/mobile/test/feature/sessions/logic/session_status_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class SessionModel extends Equatable` — all fields nullable: `id, projectId, kind, status,
    activity, harness, mode, branch, issueId, displayName, createdAt, updatedAt, previewUrl,
    isTerminated, prs (List<SessionPrModel>?)`; `SessionModel.fromJson(Map<String, dynamic>)`.
  - `class SessionPrModel extends Equatable` — `url, number, state, ci, review, mergeable (bool?),
    reviewComments (bool?)`; `SessionPrModel.fromJson(Map<String, dynamic>)`.
  - `enum AttentionLevel { merge, respond, review, pending, working, done }`
  - `bool isTerminalStatus(String? status)`
  - `String sessionTitle(SessionModel session)`
  - `AttentionLevel attentionOf(SessionModel session)`

Two deliberate departures from `lib/sessionStatus.ts` / `lib/api.ts`'s `DashboardSession`, both
evidence-based against the real Go daemon this app talks to
(`backend/internal/domain/session.go`, `backend/internal/httpd/controllers/dto.go`):

- **No `attentionLevel` field, no server-trust branch.** RN's `attentionOf` checks
  `s.attentionLevel` before falling back to its own switch — but `domain.Session` has no such JSON
  field today (confirmed by reading the struct), and RN's own `mapSession()` never sets one either.
  The branch can never fire against this daemon. Porting a dead branch is porting a bug surface
  with no coverage; this port implements only the fallback switch, which is what actually runs.
- **`sessionTitle` drops `issueTitle`/`userPrompt`/`summary` from its candidate list.** RN's own
  `mapSession()` hardcodes all three to `null` (the Go daemon doesn't send them) — so of RN's
  5-candidate list (`displayName, issueId, issueTitle, userPrompt, summary`), only the first two
  are ever non-null in practice. `SessionModel` therefore has no `issueTitle`/`userPrompt`/`summary`
  fields at all, and `sessionTitle` checks only `displayName` then `issueId`.

`SessionPrModel.mergeable` is the wire `mergeability` string enum
(`unknown|mergeable|conflicting|blocked|unstable`) collapsed to a bool exactly as RN's `mapPR`
does (`{ mergeable: pr.mergeability === "mergeable" }`) — but stored as a plain field rather than a
nested object, since nothing downstream in M1 needs the richer RN shape (`ciPassing`, `approved`,
`noConflicts`, `blockers` were never populated by `mapPR` either). `ci`/`review` are kept as the
raw wire strings (`"failing"`, `"changes_requested"`, ...) rather than RN's re-narrowed
`ciStatus`/`reviewDecision` — the Go daemon's own enums already use those exact strings
(`domain.CIState`, `domain.ReviewDecision`), so `attentionOf` compares against them directly with
no intermediate mapping.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/sessions/logic/session_status_test.dart` (ported from
`sessionStatus.test.ts`, adjusted for the two deviations above):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';

SessionModel session({
  String? id = 'proj-7',
  String? displayName,
  String? status,
  String? issueId,
  List<SessionPrModel>? prs,
}) => SessionModel(
  id: id,
  projectId: 'proj',
  displayName: displayName,
  status: status,
  issueId: issueId,
  prs: prs,
);

void main() {
  group('sessionTitle', () {
    test('prefers displayName, then issueId', () {
      expect(sessionTitle(session(displayName: 'Fix auth', issueId: 'Operator-12')), 'Fix auth');
      expect(sessionTitle(session(issueId: 'Operator-12')), 'Operator-12');
    });

    test('falls back to the id when nothing is named', () {
      expect(sessionTitle(session()), 'proj-7');
    });

    test('treats a whitespace-only name as absent', () {
      expect(sessionTitle(session(displayName: '   ')), 'proj-7');
      expect(sessionTitle(session(displayName: '\t\n', issueId: 'Operator-12')), 'Operator-12');
    });

    test('trims a name that has content', () {
      expect(sessionTitle(session(displayName: '  Fix auth  ')), 'Fix auth');
    });

    test('never returns blank', () {
      for (final s in [session(), session(displayName: ' '), session(displayName: ' ', issueId: ' ')]) {
        expect(sessionTitle(s).isNotEmpty, isTrue);
      }
    });
  });

  group('isTerminalStatus', () {
    test('recognises the terminal set', () {
      for (final s in ['killed', 'terminated', 'done', 'cleanup', 'errored', 'merged']) {
        expect(isTerminalStatus(s), isTrue);
      }
    });

    test('is false for live and missing statuses', () {
      expect(isTerminalStatus('working'), isFalse);
      expect(isTerminalStatus(null), isFalse);
      expect(isTerminalStatus(''), isFalse);
    });
  });

  group('attentionOf', () {
    test('maps terminal statuses to done', () {
      expect(attentionOf(session(status: 'merged')), AttentionLevel.done);
      expect(attentionOf(session(status: 'killed')), AttentionLevel.done);
    });

    test('maps a mergeable PR to merge', () {
      final s = session(prs: [const SessionPrModel(url: 'u', number: 1, mergeable: true)]);
      expect(attentionOf(s), AttentionLevel.merge);
    });

    test('maps blocked statuses to respond', () {
      expect(attentionOf(session(status: 'needs_input')), AttentionLevel.respond);
      expect(attentionOf(session(status: 'stuck')), AttentionLevel.respond);
    });

    test('maps failing CI and requested changes to review', () {
      expect(attentionOf(session(status: 'ci_failed')), AttentionLevel.review);
      final s = session(prs: [const SessionPrModel(url: 'u', number: 1, ci: 'failing')]);
      expect(attentionOf(s), AttentionLevel.review);
    });

    test('defaults to working', () {
      expect(attentionOf(session()), AttentionLevel.working);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/sessions/logic/session_status_test.dart`
Expected: FAIL — none of the three files exist yet.

- [ ] **Step 3: Implement SessionPrModel**

`packages/mobile/lib/feature/sessions/data/model/session_pr_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class SessionPrModel extends Equatable {
  const SessionPrModel({
    this.url,
    this.number,
    this.state,
    this.ci,
    this.review,
    this.mergeable,
    this.reviewComments,
  });

  final String? url;
  final int? number;
  final String? state;
  final String? ci;
  final String? review;
  final bool? mergeable;
  final bool? reviewComments;

  factory SessionPrModel.fromJson(Map<String, dynamic> json) => SessionPrModel(
    url: json['url'] as String?,
    number: json['number'] as int?,
    state: json['state'] as String?,
    ci: json['ci'] as String?,
    review: json['review'] as String?,
    mergeable: json['mergeability'] == 'mergeable',
    reviewComments: json['reviewComments'] as bool?,
  );

  @override
  List<Object?> get props => [url, number, state, ci, review, mergeable, reviewComments];
}
```

- [ ] **Step 4: Implement SessionModel**

`packages/mobile/lib/feature/sessions/data/model/session_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';

class SessionModel extends Equatable {
  const SessionModel({
    this.id,
    this.projectId,
    this.kind,
    this.status,
    this.activity,
    this.harness,
    this.mode,
    this.branch,
    this.issueId,
    this.displayName,
    this.createdAt,
    this.updatedAt,
    this.previewUrl,
    this.isTerminated,
    this.prs,
  });

  final String? id;
  final String? projectId;
  final String? kind;
  final String? status;
  final String? activity;
  final String? harness;
  final String? mode;
  final String? branch;
  final String? issueId;
  final String? displayName;
  final String? createdAt;
  final String? updatedAt;
  final String? previewUrl;
  final bool? isTerminated;
  final List<SessionPrModel>? prs;

  static String? _activityString(dynamic raw) {
    if (raw is String) return raw.isEmpty ? null : raw;
    if (raw is Map<String, dynamic> && raw['state'] is String) {
      final state = raw['state'] as String;
      return state.isEmpty ? null : state;
    }
    return null;
  }

  factory SessionModel.fromJson(Map<String, dynamic> json) => SessionModel(
    id: json['id'] as String?,
    projectId: json['projectId'] as String?,
    kind: json['kind'] as String?,
    status: json['status'] as String?,
    activity: _activityString(json['activity']),
    harness: json['harness'] as String?,
    mode: json['mode'] as String?,
    branch: json['branch'] as String?,
    issueId: json['issueId'] as String?,
    displayName: json['displayName'] as String?,
    createdAt: json['createdAt'] as String?,
    updatedAt: json['updatedAt'] as String?,
    previewUrl: json['previewUrl'] as String?,
    isTerminated: json['isTerminated'] as bool?,
    prs: (json['prs'] as List<dynamic>?)
        ?.map((pr) => SessionPrModel.fromJson(pr as Map<String, dynamic>))
        .toList(),
  );

  @override
  List<Object?> get props => [
    id, projectId, kind, status, activity, harness, mode, branch, issueId,
    displayName, createdAt, updatedAt, previewUrl, isTerminated, prs,
  ];
}
```

- [ ] **Step 5: Implement session_status.dart**

`packages/mobile/lib/feature/sessions/logic/session_status.dart`:

```dart
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

const Set<String> _terminalStatuses = {'killed', 'terminated', 'done', 'cleanup', 'errored', 'merged'};

bool isTerminalStatus(String? status) => status != null && _terminalStatuses.contains(status);

String sessionTitle(SessionModel session) {
  for (final candidate in [session.displayName, session.issueId]) {
    final trimmed = candidate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return session.id?.trim() ?? '';
}

enum AttentionLevel { merge, respond, review, pending, working, done }

AttentionLevel attentionOf(SessionModel session) {
  final pr = session.prs?.isNotEmpty == true ? session.prs!.first : null;

  if (session.status == 'merged' || session.status == 'done' || isTerminalStatus(session.status)) {
    return AttentionLevel.done;
  }
  if ((pr?.mergeable ?? false) || session.status == 'mergeable' || session.status == 'approved') {
    return AttentionLevel.merge;
  }
  if (session.status == 'needs_input' || session.status == 'stuck' || session.status == 'errored') {
    return AttentionLevel.respond;
  }
  if (pr?.ci == 'failing' ||
      pr?.review == 'changes_requested' ||
      session.status == 'ci_failed' ||
      session.status == 'changes_requested') {
    return AttentionLevel.review;
  }
  if (session.status == 'pr_open' || session.status == 'review_pending') {
    return AttentionLevel.pending;
  }
  return AttentionLevel.working;
}
```

- [ ] **Step 6: Run it to verify it passes**

Run: `flutter test test/feature/sessions/logic/session_status_test.dart`
Expected: PASS, all 14 tests.

- [ ] **Step 7: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add session models and status/attention logic"
```

---

### Task 14: Board zoning and PR line logic

**Files:**
- Create: `packages/mobile/lib/feature/sessions/logic/agents_view.dart`
- Test: `packages/mobile/test/feature/sessions/logic/agents_view_test.dart`

**Interfaces:**
- Consumes: `SessionModel`, `SessionPrModel` (Task 13), `attentionOf`, `AttentionLevel` (Task 13),
  `context.skin`/`AppSkin` (M0 Task 9).
- Produces:
  - `enum BoardZone { working, action, pending, merge }` (declared in this exact order — it is the
    board's left-to-right column order)
  - `BoardZone boardZoneOf(SessionModel session)`
  - `class ZoneMeta { final String label; final Color color; }`; `ZoneMeta zoneMeta(AppSkin skin, BoardZone zone)`
  - `bool isArchived(SessionModel session)`
  - `class BoardSection { final BoardZone zone; final String label; final Color color; final List<SessionModel> sessions; }`
  - `class GroupedSessions { final List<BoardSection> sections; final List<SessionModel> archived; }`
  - `GroupedSessions groupSessions(AppSkin skin, List<SessionModel> sessions)`
  - `bool showBranch(String? branch, String title)`
  - `String? trackerIssueId(String? issueId)`
  - `enum Tone { neutral, passive, success, warning, error }`
  - `String prLifecycle(SessionPrModel pr)`
  - `class PrLineSummary { final String text; final Tone tone; }`; `PrLineSummary? prLine(SessionModel session)`

Ported from `lib/agentsView.ts` and the tone/lifecycle pieces of `lib/prView.ts`, mirrored by
`agentsView.test.ts` (full ledger row: `1:1`). `attentionOf`'s `AttentionLevel` (Task 13) has no
`action` value — Task 13 established that RN's `attentionOf` can never actually return `"action"`
against the real daemon (only a server-provided `attentionLevel` field could produce it, and that
field never arrives) — so `boardZoneOf`'s switch folds only `respond` and `review` into
`BoardZone.action`, one case fewer than RN's.

`prLifecycle` is simpler than RN's version for a reason established in Task 13: RN reconstructs
`draft` from a separate `isDraft` flag because its `mapPR` collapsed the wire's `state: "draft"`
into `state: "open"` up front. `SessionPrModel.state` keeps the raw wire value, so `"draft"` is
already there — no reconstruction needed.

`prLine`'s RN source also falls back to a singular `session.pr` field when `prs` is empty
(`session.prs?.length ? session.prs : session.pr ? [session.pr] : []`) — `SessionModel` has no `pr`
field (Task 13: RN's own `mapSession()` always sets `pr: prs[0] ?? null`, so the two fields never
disagree; keeping only `prs` drops a field that could never diverge from it). The RN test that
exercises this fallback path is not portable as written and is omitted below, noted at the test.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/sessions/logic/agents_view_test.dart` (ported from
`agentsView.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';
import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';

const _dark = DarkSkin();
const _light = LightSkin();

SessionModel session({
  String? id = 'proj-1',
  String? status,
  bool? isTerminated,
  String? updatedAt,
  List<SessionPrModel>? prs,
}) => SessionModel(id: id, projectId: 'proj', status: status, isTerminated: isTerminated, updatedAt: updatedAt, prs: prs);

SessionPrModel pr({int number = 1, String state = 'open'}) => SessionPrModel(url: '', number: number, state: state);

void main() {
  group('boardZoneOf', () {
    test('declares the four columns in desktop\'s order', () {
      expect(BoardZone.values, [BoardZone.working, BoardZone.action, BoardZone.pending, BoardZone.merge]);
    });

    test('folds review and respond into action', () {
      expect(boardZoneOf(session(status: 'needs_input')), BoardZone.action);
      expect(boardZoneOf(session(status: 'stuck')), BoardZone.action);
      expect(boardZoneOf(session(status: 'ci_failed')), BoardZone.action);
      expect(boardZoneOf(session(status: 'changes_requested')), BoardZone.action);
    });

    test('maps the remaining zones straight through', () {
      expect(boardZoneOf(session(status: 'mergeable')), BoardZone.merge);
      expect(boardZoneOf(session(status: 'approved')), BoardZone.merge);
      expect(boardZoneOf(session(status: 'pr_open')), BoardZone.pending);
      expect(boardZoneOf(session(status: 'review_pending')), BoardZone.pending);
      expect(boardZoneOf(session(status: 'working')), BoardZone.working);
      expect(boardZoneOf(session(status: 'idle')), BoardZone.working);
    });
  });

  group('zoneMeta', () {
    test('uses desktop\'s labels', () {
      expect(BoardZone.values.map((z) => zoneMeta(_dark, z).label), ['Working', 'Needs you', 'In review', 'Ready to merge']);
    });

    test('takes its colours from the passed skin', () {
      expect(zoneMeta(_light, BoardZone.merge).color, isNot(zoneMeta(_dark, BoardZone.merge).color));
    });
  });

  group('isArchived', () {
    test('archives a terminated runtime', () {
      expect(isArchived(session(isTerminated: true)), isTrue);
      expect(isArchived(session(status: 'terminated')), isTrue);
    });

    test('keeps a merged session whose runtime is still alive', () {
      expect(isArchived(session(status: 'merged')), isFalse);
      expect(isArchived(session(status: 'done')), isFalse);
    });

    test('keeps ordinary live sessions', () {
      expect(isArchived(session(status: 'working')), isFalse);
      expect(isArchived(session()), isFalse);
    });
  });

  group('groupSessions', () {
    test('splits the board from the archive', () {
      final result = groupSessions(_dark, [
        session(id: 'a', status: 'working'),
        session(id: 'b', status: 'needs_input'),
        session(id: 'z', isTerminated: true),
      ]);
      expect(result.sections.map((s) => s.zone), [BoardZone.working, BoardZone.action]);
      expect(result.archived.map((s) => s.id), ['z']);
    });

    test('drops empty zones rather than rendering empty headers', () {
      final result = groupSessions(_dark, [session(status: 'working')]);
      expect(result.sections, hasLength(1));
      expect(result.sections.first.label, 'Working');
    });

    test('keeps sections in desktop\'s order regardless of input order', () {
      final result = groupSessions(_dark, [
        session(id: 'm', status: 'mergeable'),
        session(id: 'w', status: 'working'),
        session(id: 'p', status: 'pr_open'),
      ]);
      expect(result.sections.map((s) => s.zone), [BoardZone.working, BoardZone.pending, BoardZone.merge]);
    });

    test('sorts the archive newest first', () {
      final result = groupSessions(_dark, [
        session(id: 'old', isTerminated: true, updatedAt: '2026-01-01T00:00:00Z'),
        session(id: 'new', isTerminated: true, updatedAt: '2026-07-01T00:00:00Z'),
      ]);
      expect(result.archived.map((s) => s.id), ['new', 'old']);
    });

    test('returns nothing for an empty board', () {
      final result = groupSessions(_dark, const []);
      expect(result.sections, isEmpty);
      expect(result.archived, isEmpty);
    });
  });

  group('showBranch', () {
    test('shows a branch that adds information', () {
      expect(showBranch('fix/auth-timeouts', 'Fix auth timeouts on refresh'), isTrue);
    });

    test('hides a branch that merely repeats the title', () {
      expect(showBranch('fix/auth-timeouts', 'auth timeouts'), isFalse);
      expect(showBranch('feat/add-login', 'Add Login'), isFalse);
    });

    test('keeps Operator worktree branches, named session or not', () {
      expect(showBranch('opr/operator-mo-17/root', 'mobile-ui-revamp'), isTrue);
      expect(showBranch('opr/meetyou-2/chat-experience', 'chat-ux'), isTrue);
      expect(showBranch('opr/meetyou-7/root', 'meetyou-7'), isTrue);
      expect(showBranch('opr/precision-market-19/root', 'precision-market-19'), isTrue);
    });

    test('hides an absent branch', () {
      expect(showBranch(null, 't'), isFalse);
      expect(showBranch('  ', 't'), isFalse);
    });
  });

  group('prLine', () {
    test('renders nothing when there is no PR', () {
      expect(prLine(session()), isNull);
      expect(prLine(session(prs: const [])), isNull);
    });

    test('ignores placeholder PRs with no real number', () {
      expect(prLine(session(prs: [pr(number: 0)])), isNull);
    });

    test('groups by lifecycle, the way the desktop board card does', () {
      final line = prLine(session(prs: [pr(number: 12), pr(number: 13)]));
      expect(line?.text, 'PR #12, #13 open');
    });

    test('keeps separate lifecycles apart', () {
      final line = prLine(session(prs: [pr(number: 12), pr(number: 9, state: 'merged')]));
      expect(line?.text, 'PR #12 open · #9 merged');
    });

    test('takes its tone from the worst lifecycle present', () {
      expect(prLine(session(prs: [pr(number: 1, state: 'closed')]))?.tone, Tone.error);
      expect(prLine(session(prs: [pr(number: 1)]))?.tone, Tone.success);
    });
  });

  group('trackerIssueId', () {
    test('keeps a provider-prefixed tracker reference', () {
      expect(trackerIssueId('github:123'), 'github:123');
    });

    test('rejects the free text a manually created session carries', () {
      expect(trackerIssueId('onboarding'), isNull);
      expect(trackerIssueId('say hi back to me'), isNull);
    });

    test('rejects an absent or blank id', () {
      expect(trackerIssueId(null), isNull);
      expect(trackerIssueId('   '), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/sessions/logic/agents_view_test.dart`
Expected: FAIL — `agents_view.dart` does not exist.

- [ ] **Step 3: Implement agents_view.dart**

`packages/mobile/lib/feature/sessions/logic/agents_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';

enum BoardZone { working, action, pending, merge }

BoardZone boardZoneOf(SessionModel session) {
  switch (attentionOf(session)) {
    case AttentionLevel.merge:
      return BoardZone.merge;
    case AttentionLevel.pending:
      return BoardZone.pending;
    case AttentionLevel.respond:
    case AttentionLevel.review:
      return BoardZone.action;
    case AttentionLevel.working:
    case AttentionLevel.done:
      return BoardZone.working;
  }
}

class ZoneMeta {
  const ZoneMeta({required this.label, required this.color});
  final String label;
  final Color color;
}

ZoneMeta zoneMeta(AppSkin skin, BoardZone zone) {
  switch (zone) {
    case BoardZone.merge:
      return ZoneMeta(label: 'Ready to merge', color: skin.green);
    case BoardZone.action:
      return ZoneMeta(label: 'Needs you', color: skin.amber);
    case BoardZone.pending:
      return ZoneMeta(label: 'In review', color: skin.textTertiary);
    case BoardZone.working:
      return ZoneMeta(label: 'Working', color: skin.orange);
  }
}

bool isArchived(SessionModel session) => session.isTerminated == true || session.status == 'terminated';

class BoardSection {
  const BoardSection({required this.zone, required this.label, required this.color, required this.sessions});
  final BoardZone zone;
  final String label;
  final Color color;
  final List<SessionModel> sessions;
}

class GroupedSessions {
  const GroupedSessions({required this.sections, required this.archived});
  final List<BoardSection> sections;
  final List<SessionModel> archived;
}

GroupedSessions groupSessions(AppSkin skin, List<SessionModel> sessions) {
  final live = <SessionModel>[];
  final archived = <SessionModel>[];
  for (final s in sessions) {
    (isArchived(s) ? archived : live).add(s);
  }

  final byZone = <BoardZone, List<SessionModel>>{};
  for (final s in live) {
    byZone.putIfAbsent(boardZoneOf(s), () => []).add(s);
  }

  final sections = BoardZone.values.where((z) => byZone[z]?.isNotEmpty == true).map((z) {
    final meta = zoneMeta(skin, z);
    return BoardSection(zone: z, label: meta.label, color: meta.color, sessions: byZone[z]!);
  }).toList();

  archived.sort((a, b) => (b.updatedAt ?? '').compareTo(a.updatedAt ?? ''));
  return GroupedSessions(sections: sections, archived: archived);
}

bool showBranch(String? branch, String title) {
  final b = branch?.trim();
  if (b == null || b.isEmpty) return false;

  String normalize(String v) => v
      .toLowerCase()
      .replaceFirst(RegExp(r'^(feat|fix|chore|refactor|session)/'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

  return normalize(b) != normalize(title);
}

const List<String> _trackerProviderPrefixes = ['github:'];

String? trackerIssueId(String? issueId) {
  final id = issueId?.trim();
  if (id == null || id.isEmpty) return null;
  return _trackerProviderPrefixes.any(id.startsWith) ? id : null;
}

enum Tone { neutral, passive, success, warning, error }

String prLifecycle(SessionPrModel pr) {
  if (pr.state == 'merged') return 'merged';
  if (pr.state == 'closed') return 'closed';
  if (pr.state == 'draft') return 'draft';
  return 'open';
}

class PrLineSummary {
  const PrLineSummary({required this.text, required this.tone});
  final String text;
  final Tone tone;
}

PrLineSummary? prLine(SessionModel session) {
  final real = (session.prs ?? []).where((pr) => (pr.number ?? 0) > 0).toList();
  if (real.isEmpty) return null;

  final groups = <String, List<int>>{};
  for (final pr in real) {
    groups.putIfAbsent(prLifecycle(pr), () => []).add(pr.number!);
  }

  final parts = groups.entries.map((e) => '${e.value.map((n) => '#$n').join(', ')} ${e.key}');
  final lifecycles = groups.keys.toSet();
  final tone = lifecycles.contains('closed')
      ? Tone.error
      : lifecycles.contains('open')
          ? Tone.success
          : lifecycles.contains('merged')
              ? Tone.neutral
              : Tone.passive;

  return PrLineSummary(text: 'PR ${parts.join(' · ')}', tone: tone);
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/sessions/logic/agents_view_test.dart`
Expected: PASS, all 22 tests.

- [ ] **Step 5: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add board zoning and PR line logic"
```

---

### Task 15: Agent harness logo registry and AgentLogo widget

**Files:**
- Create: `packages/mobile/lib/feature/sessions/logic/harness_logo.dart`
- Create: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart`
- Create asset dir: `packages/mobile/assets/agents/` (24 PNGs, copied from `packages/mobile_rn/assets/agents/`)
- Modify: `packages/mobile/pubspec.yaml`
- Test: `packages/mobile/test/feature/sessions/logic/harness_logo_test.dart`

**Interfaces:**
- Consumes: `context.skin` (M0 Task 11).
- Produces:
  - `enum BackdropPolarity { neutral, needsDark, needsLight }`
  - `const Set<String> kLogoKeys` (24 entries)
  - `String logoKey(String? harness)`
  - `bool hasLogo(String? harness)`
  - `BackdropPolarity backdropFor(String? harness)`
  - `String harnessInitial(String? harness)`
  - `AgentLogo({required String? harness, required double size})`

Ported 1:1 from `lib/harnessLogo.ts`, mirrored by `harnessLogo.test.ts`. The measured
needs-dark/needs-light backdrop sets are transcribed verbatim — they are contrast measurements
against the real assets, not something to re-derive.

- [ ] **Step 1: Copy the agent assets and declare them**

```bash
mkdir -p packages/mobile/assets/agents
cp packages/mobile_rn/assets/agents/*.png packages/mobile/assets/agents/
ls packages/mobile/assets/agents | wc -l   # expect 24
```

In `packages/mobile/pubspec.yaml`, under `flutter: assets:`, add:

```yaml
    - assets/agents/
```

- [ ] **Step 2: Write the failing test**

`packages/mobile/test/feature/sessions/logic/harness_logo_test.dart` (ported from
`harnessLogo.test.ts`):

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/logic/harness_logo.dart';

const _allHarnesses = [
  'claude-code', 'codex', 'aider', 'opencode', 'grok', 'droid', 'amp', 'agy',
  'crush', 'cursor', 'qwen', 'copilot', 'goose', 'auggie', 'continue', 'devin',
  'cline', 'kimi', 'muse', 'kiro', 'kilocode', 'vibe', 'pi', 'autohand', 'fake',
];
const _noAsset = ['fake'];

void main() {
  group('logo registry', () {
    test('has a mark for every harness that ships one', () {
      for (final h in _allHarnesses.where((h) => !_noAsset.contains(h))) {
        expect(hasLogo(h), isTrue, reason: h);
      }
    });

    test('has no mark for the harnesses that ship none', () {
      for (final h in _noAsset) {
        expect(hasLogo(h), isFalse, reason: h);
      }
    });

    test('does not claim a mark for an unknown harness', () {
      expect(hasLogo('some-new-agent'), isFalse);
      expect(hasLogo(null), isFalse);
      expect(hasLogo('  '), isFalse);
    });

    test('is case- and whitespace-insensitive', () {
      expect(hasLogo('Claude-Code'), isTrue);
      expect(hasLogo(' codex '), isTrue);
    });

    test('matches the asset directory exactly', () {
      final dir = Directory('assets/agents');
      final onDisk = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path.split(Platform.pathSeparator).last)
          .where((name) => name.endsWith('.png'))
          .map((name) => name.substring(0, name.length - 4))
          .toList()
        ..sort();
      final expected = kLogoKeys.toList()..sort();
      expect(onDisk, expected);
    });
  });

  group('backdropFor', () {
    test('puts a dark chip behind marks that vanish on a light card', () {
      for (final h in ['opencode', 'cursor', 'cline', 'continue', 'grok', 'copilot']) {
        expect(backdropFor(h), BackdropPolarity.needsDark, reason: h);
      }
    });

    test('puts a light chip behind marks that vanish on a dark card', () {
      for (final h in ['kilocode', 'goose', 'devin', 'droid', 'pi', 'kimi']) {
        expect(backdropFor(h), BackdropPolarity.needsLight, reason: h);
      }
    });

    test('leaves colourful marks bare', () {
      for (final h in ['claude-code', 'codex', 'amp', 'qwen', 'vibe', 'aider', 'crush', 'muse', 'kiro']) {
        expect(backdropFor(h), BackdropPolarity.neutral, reason: h);
      }
    });

    test('treats an unknown or missing harness as neutral', () {
      expect(backdropFor('some-new-agent'), BackdropPolarity.neutral);
      expect(backdropFor(null), BackdropPolarity.neutral);
    });
  });

  group('harnessInitial', () {
    test('gives the uppercase initial', () {
      expect(harnessInitial('unknown-agent'), 'U');
      expect(harnessInitial('fake'), 'F');
    });

    test('falls back to a question mark rather than rendering nothing', () {
      expect(harnessInitial(''), '?');
      expect(harnessInitial('   '), '?');
      expect(harnessInitial(null), '?');
    });
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/feature/sessions/logic/harness_logo_test.dart`
Expected: FAIL — `harness_logo.dart` does not exist.

- [ ] **Step 4: Implement harness_logo.dart**

`packages/mobile/lib/feature/sessions/logic/harness_logo.dart`:

```dart
enum BackdropPolarity { neutral, needsDark, needsLight }

const Set<String> kLogoKeys = {
  'agy', 'aider', 'amp', 'auggie', 'autohand', 'claude-code', 'cline', 'codex',
  'continue', 'copilot', 'crush', 'cursor', 'devin', 'droid', 'goose', 'grok',
  'kilocode', 'kimi', 'kiro', 'muse', 'opencode', 'pi', 'qwen', 'vibe',
};

String logoKey(String? harness) => harness?.trim().toLowerCase() ?? '';

bool hasLogo(String? harness) => kLogoKeys.contains(logoKey(harness));

const Set<String> _needsDarkBackdrop = {'opencode', 'cursor', 'cline', 'continue', 'grok', 'copilot'};
const Set<String> _needsLightBackdrop = {'kilocode', 'goose', 'devin', 'droid', 'pi', 'kimi'};

BackdropPolarity backdropFor(String? harness) {
  final key = logoKey(harness);
  if (key.isEmpty) return BackdropPolarity.neutral;
  if (_needsDarkBackdrop.contains(key)) return BackdropPolarity.needsDark;
  if (_needsLightBackdrop.contains(key)) return BackdropPolarity.needsLight;
  return BackdropPolarity.neutral;
}

String harnessInitial(String? harness) {
  final key = harness?.trim();
  if (key == null || key.isEmpty) return '?';
  return key[0].toUpperCase();
}
```

- [ ] **Step 5: Run it to verify it passes**

Run: `flutter test test/feature/sessions/logic/harness_logo_test.dart`
Expected: PASS, all 12 tests.

- [ ] **Step 6: Implement AgentLogo**

`packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/sessions/logic/harness_logo.dart';

class AgentLogo extends StatelessWidget {
  const AgentLogo({super.key, required this.harness, required this.size});

  final String? harness;
  final double size;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    if (!hasLogo(harness)) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: skin.bgElevated,
        child: AppText(harnessInitial(harness), style: AppTextStyle.style11SemiBold.copyWith(color: skin.textSecondary)),
      );
    }

    final backdrop = backdropFor(harness);
    final backdropColor = switch (backdrop) {
      BackdropPolarity.needsDark => Colors.black,
      BackdropPolarity.needsLight => Colors.white,
      BackdropPolarity.neutral => null,
    };

    final image = Image.asset('assets/agents/${logoKey(harness)}.png', width: size, height: size, fit: BoxFit.contain);

    if (backdropColor == null) return image;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(color: backdropColor, borderRadius: BorderRadius.circular(size * 0.2)),
      child: image,
    );
  }
}
```

- [ ] **Step 7: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add the harness logo registry and AgentLogo widget"
```

---

### Task 16: Sessions data source and repository

**Files:**
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Create: `packages/mobile/lib/feature/sessions/data/data_source/sessions_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/sessions/data/repository/sessions_repository.dart`
- Test: `packages/mobile/test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart`
- Test: `packages/mobile/test/feature/sessions/data/repository/sessions_repository_test.dart`

**Interfaces:**
- Consumes: `SessionModel` (Task 13), `ApiConsumer`, `NetworkStatus` (M0), `GlobalResponse` (M0
  Task 4), `Result`/`FutureResult` (M0 Task 3).
- Produces:
  - `EndPoints.sessionKill(String id)`, `EndPoints.sessionRestore(String id)`
  - `abstract class SessionsRemoteDataSource { Future<GlobalResponse<List<SessionModel>>> getSessions(); Future<void> kill(String id); Future<void> restore(String id); }` + `SessionsRemoteDataSourceImp`
  - `abstract class SessionsRepository { FutureResult<GlobalResponse<List<SessionModel>>> getSessions(); FutureResult<bool> kill(String id); FutureResult<bool> restore(String id); }` + `SessionsRepositoryImp`

Per this plan's Global Constraints deviation table, `getSessions()` fetches **only**
`GET /api/v1/sessions` — no `/orchestrators`, no `/projects` — filtering out `kind == "orchestrator"`
client-side, matching RN's `rawSessions.filter((s) => s.kind !== "orchestrator")`. Gated on
`NetworkStatus`, unlike `PairingRepository` (Task 8): by the time this repository is reachable, a
config is already paired, so `NetworkStatus.isConnected`'s reachability check is meaningful here.

- [ ] **Step 1: Add the two new EndPoints**

In `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`, add:

```dart
  static String sessionKill(String sessionId) => '/api/v1/sessions/$sessionId/kill';
  static String sessionRestore(String sessionId) => '/api/v1/sessions/$sessionId/restore';
```

- [ ] **Step 2: Write the failing data source test**

`packages/mobile/test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

Response<dynamic> _response(Map<String, dynamic> body) =>
    Response<dynamic>(requestOptions: RequestOptions(path: EndPoints.sessions), statusCode: 200, data: body);

void main() {
  late _MockApiConsumer api;
  late SessionsRemoteDataSourceImp dataSource;

  setUp(() {
    api = _MockApiConsumer();
    dataSource = SessionsRemoteDataSourceImp(api);
  });

  test('parses the bare sessions payload and drops orchestrator-kind sessions', () async {
    when(() => api.get(EndPoints.sessions)).thenAnswer(
      (_) async => _response({
        'sessions': [
          {'id': 'proj-1', 'kind': 'worker', 'status': 'working'},
          {'id': 'proj-conductor', 'kind': 'orchestrator', 'status': 'working'},
        ],
      }),
    );

    final result = await dataSource.getSessions();

    expect(result.data, hasLength(1));
    expect(result.data!.single.id, 'proj-1');
  });

  test('kill posts to the session kill endpoint', () async {
    when(() => api.post(EndPoints.sessionKill('proj-1'))).thenAnswer((_) async => _response(const {}));
    await dataSource.kill('proj-1');
    verify(() => api.post(EndPoints.sessionKill('proj-1'))).called(1);
  });

  test('restore posts to the session restore endpoint', () async {
    when(() => api.post(EndPoints.sessionRestore('proj-1'))).thenAnswer((_) async => _response(const {}));
    await dataSource.restore('proj-1');
    verify(() => api.post(EndPoints.sessionRestore('proj-1'))).called(1);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart`
Expected: FAIL — `sessions_remote_data_source.dart` does not exist.

- [ ] **Step 4: Implement SessionsRemoteDataSource**

`packages/mobile/lib/feature/sessions/data/data_source/sessions_remote_data_source.dart`:

```dart
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

abstract class SessionsRemoteDataSource {
  Future<GlobalResponse<List<SessionModel>>> getSessions();
  Future<void> kill(String id);
  Future<void> restore(String id);
}

class SessionsRemoteDataSourceImp implements SessionsRemoteDataSource {
  SessionsRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<List<SessionModel>>> getSessions() async {
    final response = await _apiConsumer.get(EndPoints.sessions);
    return GlobalResponse<List<SessionModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => (json['sessions'] as List<dynamic>)
          .map((s) => SessionModel.fromJson(s as Map<String, dynamic>))
          .where((s) => s.kind != 'orchestrator')
          .toList(),
    );
  }

  @override
  Future<void> kill(String id) async {
    await _apiConsumer.post(EndPoints.sessionKill(id));
  }

  @override
  Future<void> restore(String id) async {
    await _apiConsumer.post(EndPoints.sessionRestore(id));
  }
}
```

- [ ] **Step 5: Run it to verify it passes**

Run: `flutter test test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart`
Expected: PASS, all 3 tests.

- [ ] **Step 6: Write the failing repository test**

`packages/mobile/test/feature/sessions/data/repository/sessions_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/server_failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';

class _MockSessionsRemoteDataSource extends Mock implements SessionsRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

void main() {
  late _MockSessionsRemoteDataSource dataSource;
  late _MockNetworkStatus network;
  late SessionsRepositoryImp repository;

  setUp(() {
    dataSource = _MockSessionsRemoteDataSource();
    network = _MockNetworkStatus();
    repository = SessionsRepositoryImp(dataSource, network);
  });

  test('fails fast with noNetwork when the daemon is unreachable', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);

    final result = await repository.getSessions();

    expect(result.isFailure, isTrue);
    verifyNever(() => dataSource.getSessions());
  });

  test('returns the sessions list on success', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.getSessions()).thenAnswer(
      (_) async => const GlobalResponse<List<SessionModel>>(data: [SessionModel(id: 'proj-1')]),
    );

    final result = await repository.getSessions();

    expect(result.isSuccess, isTrue);
    result.when(onSuccess: (r) => expect(r.data!.single.id, 'proj-1'), onFailure: (_) => fail('expected success'));
  });

  test('kill and restore propagate a Failure', () async {
    when(() => network.isConnected).thenAnswer((_) async => true);
    when(() => dataSource.kill('proj-1')).thenThrow(ServerFailure.noNetwork());

    final result = await repository.kill('proj-1');

    expect(result.isFailure, isTrue);
  });
}
```

- [ ] **Step 7: Run it to verify it fails**

Run: `flutter test test/feature/sessions/data/repository/sessions_repository_test.dart`
Expected: FAIL — `sessions_repository.dart` does not exist.

- [ ] **Step 8: Implement SessionsRepository**

`packages/mobile/lib/feature/sessions/data/repository/sessions_repository.dart`:

```dart
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/error_handling/failures/server_failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

abstract class SessionsRepository {
  FutureResult<GlobalResponse<List<SessionModel>>> getSessions();
  FutureResult<bool> kill(String id);
  FutureResult<bool> restore(String id);
}

class SessionsRepositoryImp implements SessionsRepository {
  SessionsRepositoryImp(this._remoteDataSource, this._network);

  final SessionsRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<List<SessionModel>>> getSessions() async {
    if (await _network.isConnected) {
      try {
        return Result.success(await _remoteDataSource.getSessions());
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  @override
  FutureResult<bool> kill(String id) async {
    if (await _network.isConnected) {
      try {
        await _remoteDataSource.kill(id);
        return Result.success(true);
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  @override
  FutureResult<bool> restore(String id) async {
    if (await _network.isConnected) {
      try {
        await _remoteDataSource.restore(id);
        return Result.success(true);
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }
}
```

- [ ] **Step 9: Run it to verify it passes**

Run: `flutter test test/feature/sessions/data/repository/sessions_repository_test.dart`
Expected: PASS, all 3 tests.

- [ ] **Step 10: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add the sessions data source and repository"
```

---

### Task 17: SessionsCubit

**Files:**
- Create: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart`
- Create: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_state.dart`
- Test: `packages/mobile/test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`

**Interfaces:**
- Consumes: `SessionsRepository` (Task 16), `MuxClient`/`SessionPatch` (Tasks 4–5),
  `shouldKeepPolling` (Task 2).
- Produces: `SessionsCubit(SessionsRepository, MuxClient)` with `List<SessionModel> sessions`,
  `Future<void> refresh()`, `Future<void> kill(String id)`, `Future<void> restore(String id)`;
  `sealed class SessionsState` with `SessionsInitialState`, `GetSessionsLoadingState`,
  `GetSessionsSuccessState`, `GetSessionsFailureState(Failure)`, `KillFailureState(Failure)`,
  `RestoreFailureState(Failure)`.

Two update channels, matching the spec's stated purpose for `MuxClient` ("the Kanban board...
depend[s] on it for live session patches") layered on top of RN's own 8-second REST poll
(`POLL_INTERVAL_MS` in `lib/store.tsx`) for reliability: an `8s` `Timer.periodic` re-fetches the
full list (mirrors RN precisely), and a `MuxClient.sessionPatches` subscription merges partial
patches (`status`, `activity`, `lastActivityAt`) into the held list between poll ticks, for a
snappier board than polling alone. RN's own board never wires `subscribeSessions`/`onSessions` (its
only consumer today is `TerminalSessionScreen.tsx`) — this cubit does, deliberately, per the
spec's architecture rather than RN's current incidental wiring.

The auth-lockout stop-polling rule ports RN's `fetchAll` return value (`store.tsx`): a poll tick
that fails with a status `shouldKeepPolling` rejects (401/403/429) cancels the timer outright,
rather than continuing to hammer a bad password into the daemon's 5-failed-auth lockout.

Kill/Restore re-fetch on success (no optimistic local mutation — matches RN's `kill`/`restore` in
`store.tsx`, both of which call `fetchAll()` after the REST call rather than mutating state
locally) and emit a dedicated failure state on failure, for the action sheet (Task 19) to surface.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`:

```dart
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/server_failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;
  late StreamController<List<SessionPatch>> patchesController;

  setUp(() {
    repository = _MockSessionsRepository();
    mux = _MockMuxClient();
    patchesController = StreamController<List<SessionPatch>>.broadcast();
    when(() => mux.sessionPatches).thenAnswer((_) => patchesController.stream);
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
  });

  tearDown(() => patchesController.close());

  blocTest<SessionsCubit, SessionsState>(
    'fetches sessions on construction and connects mux',
    build: () {
      when(() => repository.getSessions()).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: [SessionModel(id: 'proj-1', status: 'working')])),
      );
      return SessionsCubit(repository, mux);
    },
    expect: () => [isA<GetSessionsLoadingState>(), isA<GetSessionsSuccessState>()],
    verify: (cubit) {
      expect(cubit.sessions.single.id, 'proj-1');
      verify(() => mux.connect()).called(1);
      verify(() => mux.subscribeSessions()).called(1);
    },
  );

  blocTest<SessionsCubit, SessionsState>(
    'merges a mux patch into the held sessions',
    build: () {
      when(() => repository.getSessions()).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: [SessionModel(id: 'proj-1', status: 'working')])),
      );
      return SessionsCubit(repository, mux);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      patchesController.add([
        const SessionPatch(id: 'proj-1', status: 'needs_input', activity: 'blocked', attentionLevel: 'respond', lastActivityAt: 't2'),
      ]);
      await Future<void>.delayed(Duration.zero);
    },
    verify: (cubit) {
      expect(cubit.sessions.single.status, 'needs_input');
      expect(cubit.sessions.single.updatedAt, 't2');
    },
  );

  blocTest<SessionsCubit, SessionsState>(
    'kill re-fetches on success',
    build: () {
      when(() => repository.getSessions()).thenAnswer((_) async => Result.success(GlobalResponse(data: [])));
      when(() => repository.kill('proj-1')).thenAnswer((_) async => Result.success(true));
      return SessionsCubit(repository, mux);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      await cubit.kill('proj-1');
    },
    verify: (_) => verify(() => repository.getSessions()).called(2),
  );

  blocTest<SessionsCubit, SessionsState>(
    'kill emits KillFailureState without re-fetching on failure',
    build: () {
      when(() => repository.getSessions()).thenAnswer((_) async => Result.success(GlobalResponse(data: [])));
      when(() => repository.kill('proj-1')).thenAnswer((_) async => Result.failure(ServerFailure.noNetwork()));
      return SessionsCubit(repository, mux);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      await cubit.kill('proj-1');
    },
    skip: 2,
    expect: () => [isA<KillFailureState>()],
    verify: (_) => verify(() => repository.getSessions()).called(1),
  );

  test('stops polling after an auth failure instead of retrying every 8s', () {
    fakeAsync((async) {
      var callCount = 0;
      when(() => repository.getSessions()).thenAnswer((_) async {
        callCount++;
        return Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401));
      });

      final cubit = SessionsCubit(repository, mux);
      async.flushMicrotasks();
      expect(callCount, 1);

      async.elapse(const Duration(seconds: 24));
      expect(callCount, 1, reason: 'polling stopped after the auth failure');

      cubit.close();
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`
Expected: FAIL — `sessions_cubit.dart` does not exist.

- [ ] **Step 3: Implement SessionsState**

`packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_state.dart`:

```dart
part of 'sessions_cubit.dart';

sealed class SessionsState extends Equatable {
  const SessionsState();

  @override
  List<Object?> get props => [];
}

final class SessionsInitialState extends SessionsState {
  const SessionsInitialState();
}

final class GetSessionsLoadingState extends SessionsState {
  const GetSessionsLoadingState();
}

final class GetSessionsSuccessState extends SessionsState {
  const GetSessionsSuccessState();
}

final class GetSessionsFailureState extends SessionsState {
  const GetSessionsFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

final class KillFailureState extends SessionsState {
  const KillFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

final class RestoreFailureState extends SessionsState {
  const RestoreFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}
```

- [ ] **Step 4: Implement SessionsCubit**

`packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';

part 'sessions_state.dart';

class SessionsCubit extends Cubit<SessionsState> {
  SessionsCubit(this._repository, this._muxClient) : super(const SessionsInitialState()) {
    _muxSub = _muxClient.sessionPatches.listen(_applyPatches);
    _muxClient.connect();
    _muxClient.subscribeSessions();
    unawaited(_tick());
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => unawaited(_tick()));
  }

  final SessionsRepository _repository;
  final MuxClient _muxClient;

  List<SessionModel> sessions = [];

  Timer? _pollTimer;
  StreamSubscription<List<SessionPatch>>? _muxSub;
  bool _stopped = false;

  Future<void> _tick() async {
    if (_stopped) return;
    emit(const GetSessionsLoadingState());
    final result = await _repository.getSessions();
    result.when(
      onSuccess: (response) {
        sessions = response.data ?? [];
        emit(const GetSessionsSuccessState());
      },
      onFailure: (failure) {
        emit(GetSessionsFailureState(failure));
        if (!shouldKeepPolling(failure.statusCode)) {
          _stopped = true;
          _pollTimer?.cancel();
        }
      },
    );
  }

  Future<void> refresh() => _tick();

  void _applyPatches(List<SessionPatch> patches) {
    if (patches.isEmpty) return;
    final byId = {for (final patch in patches) patch.id: patch};
    sessions = sessions
        .map(
          (s) => byId[s.id] == null
              ? s
              : SessionModel(
                  id: s.id,
                  projectId: s.projectId,
                  kind: s.kind,
                  status: byId[s.id]!.status,
                  activity: byId[s.id]!.activity,
                  harness: s.harness,
                  mode: s.mode,
                  branch: s.branch,
                  issueId: s.issueId,
                  displayName: s.displayName,
                  createdAt: s.createdAt,
                  updatedAt: byId[s.id]!.lastActivityAt,
                  previewUrl: s.previewUrl,
                  isTerminated: s.isTerminated,
                  prs: s.prs,
                ),
        )
        .toList();
    emit(const GetSessionsSuccessState());
  }

  Future<void> kill(String id) async {
    final result = await _repository.kill(id);
    result.when(onSuccess: (_) => _tick(), onFailure: (failure) => emit(KillFailureState(failure)));
  }

  Future<void> restore(String id) async {
    final result = await _repository.restore(id);
    result.when(onSuccess: (_) => _tick(), onFailure: (failure) => emit(RestoreFailureState(failure)));
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    unawaited(_muxSub?.cancel());
    return super.close();
  }
}
```

- [ ] **Step 5: Run it to verify it passes**

Run: `flutter test test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`
Expected: PASS, all 6 tests.

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add SessionsCubit with polling and live mux patches"
```

---

### Task 18: Status visuals, relative time, and the SessionCard widget

**Files:**
- Create: `packages/mobile/lib/feature/sessions/logic/status_visual.dart`
- Create: `packages/mobile/lib/core/utils/relative_time.dart`
- Create: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart`
- Test: `packages/mobile/test/feature/sessions/logic/status_visual_test.dart`
- Test: `packages/mobile/test/core/utils/relative_time_test.dart`
- Test: `packages/mobile/test/feature/sessions/presentation/sessions_screen/ui/session_card_test.dart`

**Interfaces:**
- Consumes: `SessionModel` (Task 13), `sessionTitle`/`isTerminalStatus` (Task 13), `showBranch`/
  `trackerIssueId`/`prLine`/`Tone` (Task 14), `AgentLogo` (Task 15), `AppSkin` (M0 Task 9),
  `AppText`/`AppTextStyle` (M0).
- Produces: `class StatusVisual { final Color color; final String label; final bool breathing; }`;
  `StatusVisual statusVisual(AppSkin skin, String? status)`; `String relativeTime(String? iso, {DateTime? now})`;
  `SessionCard({required SessionModel session, required bool showProject, required VoidCallback onTap, required VoidCallback onLongPress})`.

`statusVisual` ports the full switch in `lib/theme.ts` (lines 251–325 of the RN source — every
`SessionStatus` value the Go daemon's `domain.Session.Status` enum can carry, confirmed against
`backend/internal/domain/status.go`). No RN test file covers it directly (`theme.test.ts` covers
only the skin token values, already ported in M0); this task adds new coverage rather than mirroring
an existing one.

`relativeTime` lands in `core/utils/`, not under `sessions`, because it has two call sites in the
RN app — `SessionCard.tsx` (this milestone) and `app/notifications.tsx` (the `notification`
feature, M5) — the same two-features-need-it-identically test that put `connection_error.dart` and
`MuxClient` in `core/`. Its RN home, `lib/notificationView.ts`, also exports `notificationVisual`
and `notificationTarget`, which are genuinely notification-only; **this task ports only the
`relativeTime` third of that module and its ledger row** (`notificationView.test.ts` →
`test/feature/notification/logic/notification_view_test.dart`). M5 ports the other two thirds into
the `notification` feature and should not re-port `relativeTime` — it will already be in `core/`.

`SessionCard` takes primitive callbacks (`onTap`, `onLongPress`) rather than reading a cubit
directly, per the "leaf/item widget" rule — it is reused unchanged by both a live board card and
(later) any other list that renders a session. `onLongPress` opens the kill/restore action sheet
(Task 19) — RN has no equivalent gesture on `SessionCard` because RN hosts kill/restore inside the
session detail screen, which does not exist until M3/M4; see the note under Task 19.

- [ ] **Step 1: Write the failing status_visual test**

`packages/mobile/test/feature/sessions/logic/status_visual_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/feature/sessions/logic/status_visual.dart';

const _skin = DarkSkin();

void main() {
  group('statusVisual', () {
    test('marks a working session as breathing', () {
      final v = statusVisual(_skin, 'working');
      expect(v.label, 'Working');
      expect(v.color, _skin.orange);
      expect(v.breathing, isTrue);
    });

    test('marks needs_input distinctly from working', () {
      final v = statusVisual(_skin, 'needs_input');
      expect(v.label, 'Needs input');
      expect(v.color, _skin.amber);
      expect(v.breathing, isFalse);
    });

    test('marks a killed or terminated session as terminated', () {
      expect(statusVisual(_skin, 'killed').label, 'Terminated');
      expect(statusVisual(_skin, 'terminated').label, 'Terminated');
      expect(statusVisual(_skin, 'killed').color, _skin.textFaint);
    });

    test('marks merged as done and green', () {
      final v = statusVisual(_skin, 'merged');
      expect(v.label, 'Merged');
      expect(v.color, _skin.green);
    });

    test('falls back to the raw status string for an unrecognised value', () {
      expect(statusVisual(_skin, 'made_up_status').label, 'made_up_status');
      expect(statusVisual(_skin, null).label, 'unknown');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/sessions/logic/status_visual_test.dart`
Expected: FAIL — `status_visual.dart` does not exist.

- [ ] **Step 3: Implement status_visual.dart**

`packages/mobile/lib/feature/sessions/logic/status_visual.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

class StatusVisual {
  const StatusVisual({required this.color, required this.label, this.breathing = false});

  final Color color;
  final String label;
  final bool breathing;
}

StatusVisual statusVisual(AppSkin skin, String? status) {
  switch (status) {
    case 'spawning':
      return StatusVisual(color: skin.blue, label: 'Starting');
    case 'working':
      return StatusVisual(color: skin.orange, label: 'Working', breathing: true);
    case 'detecting':
      return StatusVisual(color: skin.orange, label: 'Detecting', breathing: true);
    case 'needs_input':
      return StatusVisual(color: skin.amber, label: 'Needs input');
    case 'changes_requested':
      return StatusVisual(color: skin.amber, label: 'Changes req.');
    case 'stuck':
      return StatusVisual(color: skin.red, label: 'Stuck');
    case 'errored':
      return StatusVisual(color: skin.red, label: 'Crashed');
    case 'ci_failed':
      return StatusVisual(color: skin.red, label: 'CI failed');
    case 'pr_open':
      return StatusVisual(color: skin.textSecondary, label: 'PR open');
    case 'review_pending':
      return StatusVisual(color: skin.textSecondary, label: 'In review');
    case 'approved':
      return StatusVisual(color: skin.green, label: 'Approved');
    case 'mergeable':
      return StatusVisual(color: skin.green, label: 'Mergeable');
    case 'merged':
      return StatusVisual(color: skin.green, label: 'Merged');
    case 'done':
      return StatusVisual(color: skin.green, label: 'Done');
    case 'idle':
      return StatusVisual(color: skin.textTertiary, label: 'Idle');
    case 'no_signal':
      return StatusVisual(color: skin.textTertiary, label: 'No signal');
    case 'exited':
      return StatusVisual(color: skin.red, label: 'Exited');
    case 'draft':
      return StatusVisual(color: skin.textSecondary, label: 'Draft PR');
    case 'unknown':
      return StatusVisual(color: skin.textTertiary, label: 'Unknown');
    case 'cleanup':
      return StatusVisual(color: skin.textTertiary, label: 'Cleanup');
    case 'killed':
    case 'terminated':
      return StatusVisual(color: skin.textFaint, label: 'Terminated');
    default:
      return StatusVisual(color: skin.textTertiary, label: status ?? 'unknown');
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/sessions/logic/status_visual_test.dart`
Expected: PASS, all 5 tests.

- [ ] **Step 5: Write the failing relative_time test**

`packages/mobile/test/core/utils/relative_time_test.dart` (ported from the `relativeTime` group of
`notificationView.test.ts` — the only third of that file M1 ports; see this task's preamble):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/relative_time.dart';

void main() {
  final now = DateTime.parse('2026-07-30T12:00:00Z');
  String ago(Duration d) => now.subtract(d).toIso8601String();

  group('relativeTime', () {
    test('collapses anything under a minute to now', () {
      expect(relativeTime(ago(const Duration(seconds: 5)), now: now), 'now');
    });

    test('steps through minutes, hours, days and weeks', () {
      expect(relativeTime(ago(const Duration(minutes: 3)), now: now), '3m');
      expect(relativeTime(ago(const Duration(hours: 4)), now: now), '4h');
      expect(relativeTime(ago(const Duration(days: 2)), now: now), '2d');
      expect(relativeTime(ago(const Duration(days: 20)), now: now), '2w');
    });

    test('clamps a future timestamp to now rather than going negative', () {
      expect(relativeTime(ago(const Duration(seconds: -30)), now: now), 'now');
    });

    test('returns empty for an unparseable or missing timestamp', () {
      expect(relativeTime('not-a-date', now: now), '');
      expect(relativeTime(null, now: now), '');
    });
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `flutter test test/core/utils/relative_time_test.dart`
Expected: FAIL — `relative_time.dart` does not exist.

- [ ] **Step 7: Implement relativeTime**

`packages/mobile/lib/core/utils/relative_time.dart`:

```dart
String relativeTime(String? iso, {DateTime? now}) {
  if (iso == null) return '';
  final then = DateTime.tryParse(iso);
  if (then == null) return '';

  final seconds = (now ?? DateTime.now()).difference(then).inSeconds;
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

RN clamps with `Math.max(0, ...)` before bucketing; here a negative `seconds` is already below 60,
so it falls into the `'now'` branch without an explicit clamp — the future-timestamp test above
pins that.

- [ ] **Step 8: Run it to verify it passes**

Run: `flutter test test/core/utils/relative_time_test.dart`
Expected: PASS, all 4 tests.

- [ ] **Step 9: Write the failing SessionCard test**

`packages/mobile/test/feature/sessions/presentation/sessions_screen/ui/session_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart';

void main() {
  testWidgets('renders title, status, PR line, and relative time, and reports taps', (tester) async {
    var tapped = false;
    var longPressed = false;
    final session = SessionModel(
      id: 'proj-1',
      projectId: 'proj',
      displayName: 'Fix auth',
      status: 'working',
      branch: 'fix/auth-timeouts',
      updatedAt: DateTime.now().subtract(const Duration(minutes: 3)).toIso8601String(),
      prs: const [SessionPrModel(url: 'u', number: 12, state: 'open')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: Scaffold(
            body: SessionCard(
              session: session,
              showProject: true,
              onTap: () => tapped = true,
              onLongPress: () => longPressed = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Fix auth'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('PR #12 open'), findsOneWidget);
    expect(find.text('3m'), findsOneWidget);

    await tester.tap(find.byType(SessionCard));
    expect(tapped, isTrue);

    await tester.longPress(find.byType(SessionCard));
    expect(longPressed, isTrue);
  });

  testWidgets('renders no timestamp when the session has never reported one', (tester) async {
    const session = SessionModel(id: 'proj-1', projectId: 'proj', displayName: 'Fix auth', status: 'working');

    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: Scaffold(
            body: SessionCard(session: session, showProject: true, onTap: () {}, onLongPress: () {}),
          ),
        ),
      ),
    );

    expect(find.text('Fix auth'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });
}
```

- [ ] **Step 10: Run it to verify it fails**

Run: `flutter test test/feature/sessions/presentation/sessions_screen/ui/session_card_test.dart`
Expected: FAIL — `session_card.dart` does not exist.

- [ ] **Step 11: Implement SessionCard**

`packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/relative_time.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/logic/status_visual.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';

class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.showProject,
    required this.onTap,
    required this.onLongPress,
  });

  final SessionModel session;
  final bool showProject;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final visual = statusVisual(skin, session.status);
    final title = sessionTitle(session);
    final branch = showBranch(session.branch, title) ? session.branch : null;
    final issue = trackerIssueId(session.issueId);
    final prs = prLine(session);
    final when = relativeTime(session.updatedAt);

    return AppContainer(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: GestureDetector(
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AgentLogo(harness: session.harness, size: 20),
                const HorizontalSpace(9),
                Expanded(child: AppText(title, style: AppTextStyle.style15SemiBold, maxLines: 2)),
                if (showProject && session.projectId != null)
                  AppText(session.projectId!, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
              ],
            ),
            if (branch != null || issue != null) ...[
              const VerticalSpace(6),
              Padding(
                padding: const EdgeInsets.only(left: 29),
                child: Row(
                  children: [
                    if (branch != null)
                      Expanded(
                        child: AppText(branch, style: AppTextStyle.mono11Regular.copyWith(color: skin.textFaint)),
                      ),
                    if (issue != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: skin.tintBlue, borderRadius: BorderRadius.circular(5)),
                        child: AppText(issue, style: AppTextStyle.mono10Regular.copyWith(color: skin.blue)),
                      ),
                  ],
                ),
              ),
            ],
            const VerticalSpace(10),
            Container(height: 1, color: skin.borderSubtle),
            const VerticalSpace(8),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: visual.color, shape: BoxShape.circle),
                ),
                const HorizontalSpace(6),
                Expanded(
                  child: AppText(visual.label, style: AppTextStyle.style12SemiBold.copyWith(color: visual.color)),
                ),
                if (when.isNotEmpty)
                  AppText(when, style: AppTextStyle.mono11Regular.copyWith(color: skin.textFaint)),
              ],
            ),
            if (prs != null) ...[
              const VerticalSpace(5),
              AppText(prs.text, style: AppTextStyle.mono11Regular.copyWith(color: skin.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 12: Run it to verify it passes**

Run: `flutter test test/feature/sessions/presentation/sessions_screen/ui/session_card_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 13: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add status visuals, relative time, and the SessionCard widget"
```

---

### Task 19: Kanban board screen and the session actions sheet

**Files:**
- Create: `packages/mobile/lib/core/utils/extensions.dart`
- Create: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart`
- Create: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart`
- Create: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_stats_row.dart`
- Create: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_section_header.dart`
- Create: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_actions_sheet.dart`
- Test: `packages/mobile/test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart`

**Interfaces:**
- Consumes: `SessionsCubit`/`SessionsState` (Task 17), `groupSessions`/`BoardSection` (Task 14),
  `attentionOf`/`AttentionLevel` (Task 13), `SessionCard` (Task 18), `AppDialog` (Task 3),
  `AppLoader`/`AppErrorWidget`/`AppScaffold`/`GlobalAppbar` (M0 Task 12).
- Produces: `extension SnackBarContext on BuildContext { void showSnackBar(String message); }`;
  `SessionsScreen` (routed as `RoutesStrings.sessions`); `SessionActionsSheet`.

Trims from RN's `app/(tabs)/index.tsx`, each because the feature it belongs to has not landed yet:
no notifications bell (M5 `notification`), no spawn FAB (M2 `spawn`), no project switcher (M2
`spawn`/`settings` introduce the first project picker — `SessionCard`'s project label is always
shown, matching RN's `showProject={activeProjectId === "all"}` with no switcher to ever flip it to
`false`), and the archive section has no collapse toggle (always expanded when non-empty — RN's
collapsed-by-default strip is a small polish detail, not a walking-skeleton requirement). The stats
row, pull-to-refresh, and empty/error states are kept — they are load-bearing for verifying M1
against a real daemon.

**Kill/restore live on a long-press action sheet from the card**, not inside a session-detail
screen. RN hosts these inside `TerminalSessionScreen.tsx`/`ChatSessionScreen.tsx`
(`lib/session/TerminalSessionScreen.tsx`'s `confirmKill`/`onRestore`), which do not exist until M3
(chat) and M4 (terminal). The design's M1 feature table explicitly scopes "kill/restore/resume" to
this milestone's `sessions` feature, so this sheet is new UI surface, not a straight port — it
mirrors RN's actual *behavior* (native destructive confirm on kill via `AppDialog.confirm`, no
confirm on restore, matching `TerminalSessionScreen.tsx`'s `confirmKill`/`onRestore`) using a
mechanism M1 can build without the screens RN hangs it from. "Resume" (`resumeSessionAgent`, chat
mode's live-agent restart) is **not** included — RN's own `terminated` distinction for it is
computed from conversation/thread state the board does not have; it lands with the `chat` feature
in M3. Tapping a card is a no-op for M1 (`onTap: () {}`) — there is no session-detail screen to
navigate to yet.

- [ ] **Step 1: Add the snackbar extension**

`packages/mobile/lib/core/utils/extensions.dart`:

```dart
import 'package:flutter/material.dart';

extension SnackBarContext on BuildContext {
  void showSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(SnackBar(content: Text(message)));
  }
}
```

- [ ] **Step 2: Write the failing SessionsBody test**

`packages/mobile/test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

void main() {
  testWidgets('groups sessions into their board sections with a stat header', (tester) async {
    final repository = _MockSessionsRepository();
    final mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => repository.getSessions()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: [
          SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
          SessionModel(id: 'b', projectId: 'proj', displayName: 'Needs you', status: 'needs_input'),
        ]),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: BlocProvider(
            create: (_) => SessionsCubit(repository, mux),
            child: const Scaffold(body: SessionsBody()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Working one'), findsOneWidget);
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Working'), findsWidgets);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart`
Expected: FAIL — the widget files do not exist.

- [ ] **Step 4: Implement the small section widgets**

`packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_section_header.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class SessionSectionHeader extends StatelessWidget {
  const SessionSectionHeader({super.key, required this.label, required this.color, required this.count});

  final String label;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
    child: Row(
      children: [
        AppText(label.toUpperCase(), style: AppTextStyle.style11SemiBold.copyWith(color: color)),
        const SizedBox(width: 6),
        AppText('$count', style: AppTextStyle.mono11Regular.copyWith(color: color)),
      ],
    ),
  );
}
```

`packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_stats_row.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class SessionsStatsRow extends StatelessWidget {
  const SessionsStatsRow({super.key, required this.working, required this.needsYou, required this.mergeable});

  final int working;
  final int needsYou;
  final int mergeable;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    Widget stat(int n, String label, Color color) => Expanded(
      child: AppContainer(
        backgroundColor: skin.bgElevated,
        border: Border.all(color: skin.borderSubtle),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText('$n', style: AppTextStyle.mono24Bold.copyWith(color: n > 0 ? color : skin.textFaint)),
            AppText(label, style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary)),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          stat(working, 'working', skin.orange),
          const HorizontalSpace(10),
          stat(needsYou, 'need you', skin.amber),
          const HorizontalSpace(10),
          stat(mergeable, 'mergeable', skin.green),
        ],
      ),
    );
  }
}
```

`AppTextStyle.mono24Bold` does not exist in M0's set (M0 built `mono10`–`mono13` only, using its
private `_monoStyle(size, weight)` helper). Add one more getter to
`packages/mobile/lib/core/app_themes/text_style/app_text_style.dart`, directly below the existing
`mono13Bold` line:

```dart
  static TextStyle get mono24Bold => _monoStyle(24, FontWeightHelper.bold);
```

- [ ] **Step 5: Implement SessionActionsSheet**

`packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/session_actions_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

Future<void> showSessionActionsSheet(BuildContext context, SessionModel session) {
  final cubit = context.read<SessionsCubit>();
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => BlocProvider.value(value: cubit, child: SessionActionsSheet(session: session)),
  );
}

class SessionActionsSheet extends StatelessWidget {
  const SessionActionsSheet({super.key, required this.session});

  final SessionModel session;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final terminated = session.isTerminated == true || session.status == 'terminated';
    final cubit = context.read<SessionsCubit>();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: AppText(sessionTitle(session), style: AppTextStyle.style14SemiBold),
            subtitle: AppText(session.id ?? '', style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
          ),
          if (terminated)
            ListTile(
              leading: Icon(Icons.replay, color: skin.accent),
              title: const AppText('Restore'),
              onTap: () {
                Navigator.of(context).pop();
                cubit.restore(session.id!);
              },
            )
          else
            ListTile(
              leading: Icon(Icons.stop_circle_outlined, color: skin.red),
              title: AppText('Kill', style: AppTextStyle.style14Regular.copyWith(color: skin.red)),
              onTap: () async {
                final confirmed = await AppDialog.confirm(
                  context,
                  title: 'Kill session?',
                  message: 'This stops ${session.id}.',
                  confirmLabel: 'Kill',
                  destructive: true,
                );
                if (!context.mounted) return;
                Navigator.of(context).pop();
                if (confirmed) cubit.kill(session.id!);
              },
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Implement SessionsBody**

`packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/failure_widgets/app_error_widget.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_actions_sheet.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_section_header.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_stats_row.dart';

class SessionsBody extends StatelessWidget {
  const SessionsBody({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SessionsCubit>();
    final skin = context.skin;

    return BlocBuilder<SessionsCubit, SessionsState>(
      buildWhen: (previous, current) =>
          current is GetSessionsLoadingState || current is GetSessionsSuccessState || current is GetSessionsFailureState,
      builder: (context, state) {
        if (cubit.sessions.isEmpty && state is GetSessionsLoadingState) {
          return const AppLoader.center();
        }
        if (cubit.sessions.isEmpty && state is GetSessionsFailureState) {
          return AppErrorWidget(failure: state.failure, onPressed: cubit.refresh);
        }

        final grouped = groupSessions(skin, cubit.sessions);
        var working = 0;
        var needsYou = 0;
        var mergeable = 0;
        for (final session in cubit.sessions) {
          switch (attentionOf(session)) {
            case AttentionLevel.working:
              working++;
            case AttentionLevel.respond:
              needsYou++;
            case AttentionLevel.merge:
              mergeable++;
            case AttentionLevel.review:
            case AttentionLevel.pending:
            case AttentionLevel.done:
              break;
          }
        }

        void openActions(SessionModel session) => showSessionActionsSheet(context, session);

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              SessionsStatsRow(working: working, needsYou: needsYou, mergeable: mergeable),
              for (final section in grouped.sections) ...[
                SessionSectionHeader(label: section.label, color: section.color, count: section.sessions.length),
                for (final session in section.sessions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SessionCard(
                      session: session,
                      showProject: true,
                      onTap: () {},
                      onLongPress: () => openActions(session),
                    ),
                  ),
              ],
              if (grouped.archived.isNotEmpty) ...[
                SessionSectionHeader(label: 'Archive', color: skin.textFaint, count: grouped.archived.length),
                for (final session in grouped.archived)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SessionCard(
                      session: session,
                      showProject: true,
                      onTap: () {},
                      onLongPress: () => openActions(session),
                    ),
                  ),
              ],
              if (grouped.sections.isEmpty && grouped.archived.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: AppText('No active agents')),
                ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 7: Implement the screen**

`packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart';

class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocListener<SessionsCubit, SessionsState>(
    listener: (context, state) {
      if (state is KillFailureState) context.showSnackBar('Kill failed: ${state.failure.message}');
      if (state is RestoreFailureState) context.showSnackBar('Restore failed: ${state.failure.message}');
    },
    child: const AppScaffold(
      appBar: GlobalAppbar.main(titleText: 'Agents'),
      body: SessionsBody(),
    ),
  );
}
```

- [ ] **Step 8: Run it to verify it passes**

Run: `flutter test test/feature/sessions/presentation/sessions_screen/ui/sessions_body_test.dart`
Expected: PASS, 1 test.

- [ ] **Step 9: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): add the Kanban board screen and session actions sheet"
```

---

### Task 20: Wire DI, routing, and bootstrap end-to-end

**Files:**
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Modify: `packages/mobile/lib/core/app_routes/routes_strings.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart`
- Modify: `packages/mobile/lib/main.dart`
- Test: `packages/mobile/test/core/utils/service_locator_test.dart` (extend)
- Test: `packages/mobile/test/core/app_routes/app_router_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–19.
- Produces: a fully routable app — `main.dart` decides `onboarding` vs `sessions` as the entry
  route by calling `shouldOnboard` directly (Task 12's note: no mounted gate widget).

MuxClient is registered as a lazy singleton built from `ServerConfigStore.current` on first
resolution — safe because nothing resolves `sl<MuxClient>()` before a config exists (the only
consumer in M1, `SessionsCubit`, is only ever constructed on a route reachable after pairing).
**Known M1 gap, deferred to M2:** because GetIt lazy singletons build once and cache, a user who
disconnects and re-pairs to a *different* host later would get a `MuxClient` still bound to the
old `ServerConfig` — there is no disconnect/re-pair flow in M1 to exercise this. M2, which adds
Settings' disconnect action, should either re-register `MuxClient` on re-pair or change its
constructor to take a `ServerConfigSource` and read `.current` per connection attempt (mirroring
how `ServerConfigInterceptor` already does this) — do not silently carry the gap further without
addressing it there.

- [ ] **Step 1: Extend the service locator test**

Add to `packages/mobile/test/core/utils/service_locator_test.dart`'s existing test file:

```dart
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
```

and inside `main()`, extend `setUp` to persist a paired config before `ServiceLocator.init()`
(`MuxClient`'s lazy build needs `ServerConfigStore.current` to be non-null the first time it's
resolved) and add:

```dart
  test('resolves the pairing and sessions singletons', () async {
    await sl<ServerConfigStore>().save(
      const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12'),
    );
    expect(sl<PairingRepository>(), isA<PairingRepository>());
    expect(sl<SessionsRepository>(), isA<SessionsRepository>());
    expect(sl<MuxClient>(), isA<MuxClient>());
  });
```

(Import `ServerConfig` alongside `ServerConfigStore` at the top of the test file, matching the
existing import style.)

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/utils/service_locator_test.dart`
Expected: FAIL — `PairingRepository`/`SessionsRepository`/`MuxClient` are not registered.

- [ ] **Step 3: Register the new singletons and factories**

In `packages/mobile/lib/core/utils/service_locator.dart`, add to `_coreSetup()`:

```dart
    sl.registerLazySingleton<MuxClient>(() => MuxClient(sl<ServerConfigStore>().current!));
```

Add two new methods, called from `init()` after `_coreSetup()`:

```dart
  static void _pairingFeatureSetup() {
    sl.registerFactoryParam<PairingScanCubit, bool, void>(
      (fromOnboarding, _) => PairingScanCubit(sl<PairingRepository>(), sl<ServerConfigStore>(), fromOnboarding: fromOnboarding),
    );
    sl.registerFactory<ManualConnectCubit>(() => ManualConnectCubit(sl<PairingRepository>(), sl<ServerConfigStore>()));

    sl.registerLazySingleton<PairingRepository>(
      () => PairingRepositoryImp(sl<PairingRemoteDataSource>(), sl<ServerConfigStore>()),
    );
    sl.registerLazySingleton<PairingRemoteDataSource>(() => PairingRemoteDataSourceImp(sl<ApiConsumer>()));
  }

  static void _sessionsFeatureSetup() {
    sl.registerFactory<SessionsCubit>(() => SessionsCubit(sl<SessionsRepository>(), sl<MuxClient>()));

    sl.registerLazySingleton<SessionsRepository>(
      () => SessionsRepositoryImp(sl<SessionsRemoteDataSource>(), sl<NetworkStatus>()),
    );
    sl.registerLazySingleton<SessionsRemoteDataSource>(() => SessionsRemoteDataSourceImp(sl<ApiConsumer>()));
  }
```

Call both from `init()`:

```dart
  static Future<void> init() async {
    await _coreSetup();
    _pairingFeatureSetup();
    _sessionsFeatureSetup();
  }
```

Add the corresponding imports at the top of the file for `MuxClient`, `PairingScanCubit`,
`ManualConnectCubit`, `PairingRepository`/`PairingRepositoryImp`,
`PairingRemoteDataSource`/`PairingRemoteDataSourceImp`, `SessionsCubit`,
`SessionsRepository`/`SessionsRepositoryImp`, `SessionsRemoteDataSource`/`SessionsRemoteDataSourceImp`.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/core/utils/service_locator_test.dart`
Expected: PASS, all tests (M0's 2 plus this task's 1).

- [ ] **Step 5: Update RoutesStrings**

Replace the contents of `packages/mobile/lib/core/app_routes/routes_strings.dart`:

```dart
sealed class RoutesStrings {
  static const String onboarding = '/onboarding';
  static const String pairingScan = '/pair';
  static const String manualConnect = '/pair/manual';
  static const String sessions = '/sessions';
}
```

`splash` is removed — `main.dart` (Step 7) now computes the entry route directly rather than
routing through an intermediate placeholder.

- [ ] **Step 6: Write the failing AppRouter test**

`PairingScanScreen` starts a real `MobileScannerController` (a platform channel with no plugin
registered in `flutter test`) and `SessionsScreen`'s `SessionsCubit` opens a real network
connection and mux socket the instant it is constructed (Task 17) — actually pumping either into a
widget tree via `tester.pumpWidget` would trip both a missing-platform-channel exception and
`AGENTS.md`'s "no network calls in tests" rule. This test never pumps a route's widget into the
tree at all, so neither risk applies: `MaterialPageRoute.builder` is a plain function, and calling
it just constructs a widget object — `BlocProvider`'s `create` callback (which is where
`sl<SessionsCubit>()` actually runs) is lazy and only invoked once Flutter mounts the widget, which
`pumpWidget` never happens here. `Fake` (from `mocktail`, already a dependency) stands in for the
unused `BuildContext` argument.

`packages/mobile/test/core/app_routes/app_router_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_routes/app_router.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart';

class _FakeBuildContext extends Fake implements BuildContext {}

void main() {
  Widget builtWidgetFor(String routeName, {Object? arguments}) {
    final route = AppRouter.generateRoute(RouteSettings(name: routeName, arguments: arguments)) as MaterialPageRoute;
    return route.builder(_FakeBuildContext());
  }

  test('routes onboarding directly to its screen', () {
    expect(builtWidgetFor(RoutesStrings.onboarding), isA<OnboardingScreen>());
  });

  test('routes pairing scan, manual connect, and sessions through a BlocProvider', () {
    expect(builtWidgetFor(RoutesStrings.pairingScan, arguments: {'fromOnboarding': true}), isA<BlocProvider>());
    expect(builtWidgetFor(RoutesStrings.manualConnect), isA<BlocProvider>());
    expect(builtWidgetFor(RoutesStrings.sessions), isA<BlocProvider>());
  });

  test('falls through to the error widget for an unknown route', () {
    expect(builtWidgetFor('/nowhere'), isA<AppScaffold>());
  });
}
```

- [ ] **Step 7: Run it to verify it fails**

Run: `flutter test test/core/app_routes/app_router_test.dart`
Expected: FAIL — `AppRouter` has no cases for the new route names yet (falls through to `default`).

- [ ] **Step 8: Wire the routes**

Replace `packages/mobile/lib/core/app_routes/app_router.dart`'s `generateRoute` body:

```dart
sealed class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RoutesStrings.onboarding:
        return MaterialPageRoute(builder: (context) => const OnboardingScreen(), settings: settings);

      case RoutesStrings.pairingScan:
        final args = settings.arguments as Map<String, dynamic>?;
        final fromOnboarding = args?['fromOnboarding'] as bool? ?? false;
        return MaterialPageRoute(
          builder: (context) => BlocProvider(
            create: (_) => sl<PairingScanCubit>(param1: fromOnboarding),
            child: const PairingScanScreen(),
          ),
          settings: settings,
        );

      case RoutesStrings.manualConnect:
        return MaterialPageRoute(
          builder: (context) => BlocProvider(create: (_) => sl<ManualConnectCubit>(), child: const ManualConnectScreen()),
          settings: settings,
        );

      case RoutesStrings.sessions:
        return MaterialPageRoute(
          builder: (context) => BlocProvider(create: (_) => sl<SessionsCubit>(), child: const SessionsScreen()),
          settings: settings,
        );

      default:
        return MaterialPageRoute(
          builder: (context) => const AppScaffold(appBar: GlobalAppbar.sub(), body: AppErrorWidget()),
          settings: settings,
        );
    }
  }
}
```

Add imports for `flutter_bloc`, `sl`, and each new screen/cubit referenced above.

- [ ] **Step 9: Run it to verify it passes**

Run: `flutter test test/core/app_routes/app_router_test.dart`
Expected: PASS.

- [ ] **Step 10: Wire main.dart's entry route**

In `packages/mobile/lib/main.dart`, replace the body of `main()` from `await
sl<ServerConfigStore>().load();` through `runApp(...)`:

```dart
  await sl<ServerConfigStore>().load();

  final configured = sl<ServerConfigStore>().current != null;
  final skipped = (CacheHelper.get(CacheKeys.onboardingSkipped) as bool?) ?? false;
  final initialRoute = shouldOnboard(configured: configured, skipped: skipped)
      ? RoutesStrings.onboarding
      : RoutesStrings.sessions;

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: OperatorApp(initialRoute: initialRoute),
    ),
  );
```

`OperatorApp` gains a required `initialRoute` parameter, passed straight through to
`MaterialApp.initialRoute` in place of the hardcoded `RoutesStrings.splash`. Add the import for
`shouldOnboard` (Task 12).

- [ ] **Step 11: Verify and commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "feat(mobile): wire DI, routing, and the onboarding/sessions bootstrap"
```

---

### Task 21: Manual verification against a real daemon, and close out M1

**Files:**
- Modify: `packages/mobile/README.md`
- Modify: `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`

**Interfaces:**
- Consumes: Tasks 1–20.
- Produces: M1 signed off against its actual "done when" bar — "runs against a real daemon on a
  real phone" — which none of the automated tests in Tasks 1–20 exercise. `flutter test` proves the
  logic; only running the app proves pairing, polling, and kill/restore work end to end.

Unlike M0 ("Skeleton", verified by `flutter analyze`/`flutter test` alone, never run), M1 ships the
first screens a person actually uses. This task is the manual verification pass the spec's M1 row
requires and M0 explicitly did not need — do not mark M1 done on green tests alone.

- [ ] **Step 1: Run the full automated gate**

```bash
cd packages/mobile
flutter analyze
flutter test
```

Expected: analyze clean; every test from Tasks 1–20 passing.

- [ ] **Step 2: Start a real daemon with Connect Mobile enabled**

```bash
cd backend
go run ./cmd/opr start
```

Then, from the desktop app (or `opr` CLI — see `docs/cli/README.md`), enable **Connect Mobile** to
open the LAN listener (`AGENTS.md`'s hard rule: opt-in, `0.0.0.0`, bearer-password
`authMiddleware`, never the loopback-gated control routes). Note the paired host (the machine's
LAN IP or `.local` name), port, and password/QR it displays — this is the target Task 8's
`PairingRepository` verifies against.

- [ ] **Step 3: Run the app against it**

Manual-connect path (works on a simulator — no camera needed):

```bash
cd packages/mobile
flutter run
```

On first launch: confirm the onboarding welcome screen appears (fresh install, nothing paired).
Tap "Enter manually" from the pairing scan screen, fill in the host/port/password from Step 2,
toggle TLS only if Connect Mobile is serving TLS, and tap Connect. Confirm:

- A wrong password shows the "Your desktop rejected the password" copy (Task 2/10), not a generic
  error.
- A correct password lands on the sessions Kanban board.
- The board's stats row and section headers reflect whatever sessions already exist on that
  daemon (spawn one from the desktop app or `opr spawn` beforehand if the daemon is empty — M1
  ships no spawn flow, per this plan's Global Constraints).
- Pull-to-refresh works.
- Long-pressing a live session card opens the actions sheet; Kill asks for confirmation and the
  session disappears from its zone (moves to Archive) after confirming; Restore (on an archived
  session) does not ask for confirmation and the session returns to a live zone.

QR path (needs a physical device with a camera — an iOS Simulator has none):

```bash
flutter run -d <physical-device-id>
```

Scan the QR Connect Mobile displays. Confirm the scan verifies, saves, and lands on the same
Kanban board as the manual path. If no physical device is available for this session, note that
explicitly in the task's completion notes — do not claim QR pairing was verified when it was not.

- [ ] **Step 4: Confirm the reconnect/backoff behaves under a real network drop**

With the app on the sessions board, disable Wi-Fi or stop the daemon for a few seconds, then
restore it. Confirm the board's next poll (within 8s) picks the connection back up without a
manual restart of the app — this is `SessionsCubit`'s poll loop (Task 17) recovering, not
`MuxClient` (M1 doesn't render mux connection status anywhere yet — only the REST poll surfaces
recovery visibly in this milestone).

- [ ] **Step 5: Write the README**

`packages/mobile/README.md`: what the app is, current milestone (M1 — pairing, onboarding,
sessions Kanban), that `packages/mobile_rn` remains the frozen RN reference until M6, how to run
`flutter analyze`/`flutter test`, and the manual-verification steps above (host/port/password setup
via Connect Mobile) for anyone who needs to re-verify a future change against a real daemon.

- [ ] **Step 6: Mark M1 done in the spec**

In `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`'s build-order table, add
`— done <date>` to the M1 row, matching the M0 row's existing style.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs(mobile): close out M1"
```

---

## What M1 deliberately does not include

- `pull_request`, `orchestrator`, `spawn`, `settings` — M2. This means no PR tab, no orchestrator
  tab, no new-session flow, no project switcher, no notifications bell, and no "forget server"
  disconnect action (`lib/disconnect.ts`/`disconnect.test.ts` — settings-only call site, verified).
- `chat`, `terminal` — M3 and M4. No session-detail screen; kill/restore is reachable from a
  long-press action sheet on the Kanban board instead (see Task 19's note). "Resume" a live but
  stopped agent (`resumeSessionAgent`) is chat-mode-specific and lands with `chat` in M3.
  `lib/session/sendRoute.ts`/`sendRoute.test.ts` (REST-vs-terminal message routing) has no
  consumer until the chat composer exists — deferred to M3 alongside it (Global Constraints
  deviation table).
- Push, voice, telemetry, preview, deep links — M5.
- `appInfo.ts`/`appInfo.test.ts` (About/build-info) — Settings-only call site (verified), deferred
  to M2 alongside Settings itself.
- `lib/sheetResult.ts` — Expo-Router-specific route-param plumbing with no Flutter equivalent
  need; `Navigator.push<T>()` returns results natively. Not ported (Global Constraints deviation
  table).
- The camera-lens string heuristic (`pickNormalLens`) is ported for test-ledger parity but not
  wired into the scan screen — `mobile_scanner`'s typed `CameraLensType.normal` supersedes it
  (Global Constraints deviation table).
- The sequential-auth-probing discipline the M0 plan's own closing note flagged as M1's
  responsibility is **not** implemented in M1 — traced precisely (Global Constraints deviation
  table) to a single-endpoint fetch (`GET /api/v1/sessions` only) that has nothing to sequence
  against yet. It becomes actionable, and gets its test, in M2 when the project switcher and
  orchestrator tab add the second and third call to what `SessionsRepository.getSessions()` fetches.
- Archive collapse/expand, the notifications badge on the board header, and pixel-exact RN spacing
  — trimmed as noted in Task 19; none affect whether M1 runs correctly against a real daemon.
