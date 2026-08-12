# Flutter Mobile Port — M2 (Breadth on the Spine) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four tabs live — Agents (from M1), Orchestrator, PRs, Settings — plus the spawn flow,
all reading a single polled board read-model so a stale password still costs one failed auth
attempt per tick.

**Architecture:** The structural move of this milestone is hoisting the polled daemon state into
**one** store. M1's `SessionsCubit` was a screen cubit that polled `GET /sessions` and owned
`sessions`. M2 extends it to own `projects` and `orchestrators` too, registers it as a **lazy
singleton**, and provides it once above a four-tab shell. Three tabs (Agents, PRs, Orchestrator)
and the spawn flow read that one instance. Four new features land under `lib/feature/`
(`pull_request`, `orchestrator`, `spawn`, `settings`), each logic-and-tests first, then its screen.

**Tech Stack:** Everything from M1, plus `url_launcher` (open a PR in the GitHub app or browser)
and `package_info_plus` (About section's version string).

## Global Constraints

- Source spec: `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`.
- Source of truth for RN behavior: `packages/mobile_rn/` (frozen reference). Quoted verbatim
  throughout this plan; file paths below are relative to `packages/mobile_rn/` unless stated
  otherwise.
- Conventions are the `flutter-knowledge` skill. Where the mirrored RN source contradicts it, the
  skill wins. Invoke `flutter-testing` before the first test file, exactly as M0 and M1 did.
- Cubit only — never `Bloc` with events. Static-only classes are `sealed class X`. **No comments**
  except non-obvious business rules. Single quotes, `const` constructors, full 8-digit hex colors,
  `final` locals. No `flutter_screenutil` extensions outside `AppTextStyle`. No `drift`, no
  `freezed`, no `json_serializable`, no `build_runner`.
- Verification after every task: `flutter analyze` clean and `flutter test` green, both run from
  `packages/mobile`.
- New dependency versions below were verified conflict-free against the exact
  `packages/mobile/pubspec.yaml` this plan starts from (`flutter pub add url_launcher
  package_info_plus`, then `flutter analyze` → "No issues found!", `flutter test` → 191/191 green,
  then reverted). Do not re-litigate the versions — add them as pinned.
- Package name is `operator_mobile`; imports are `package:operator_mobile/...`.
- All app state resolves under `~/.operator` — unaffected by this milestone, called out per
  `AGENTS.md`'s hard rule for completeness.

### New dependencies (pinned, verified conflict-free)

```yaml
dependencies:
  url_launcher: ^6.3.2
  package_info_plus: ^10.2.1
```

### What M2 deliberately does not include

Three screens this milestone's surfaces would naturally link to do not exist yet. Their buttons are
**omitted, not stubbed** — a button that does nothing is worse than no button, and a `TODO` route
is worse than both.

| Omitted | Why | Lands in |
|---|---|---|
| PRCard's "Open session" action, OrchestratorCard's "Open orchestrator" action, and the post-launch / post-spawn jump to a session | Their destination is the session detail screen. `chat` is M3 and `terminal` is M4; M2 ships neither. | M3 / M4 |
| Settings' Notifications section (push toggle) and its "History" row | `notification` and push registration are M5, and push needs Firebase/APNs credentials only the repository owner can create. | M5 |
| The push-unregister step inside `forgetServer` | Same reason. Task 18 ports `forgetServer` with the `try`/`finally` shape intact so M5 adds one line inside the existing `try`. | M5 |

### Deliberate deviations from the RN reference

| RN source | What it does | Why M2 departs |
|---|---|---|
| `lib/store.tsx` (`AppProvider`) | One React context provider polls `/sessions` + `/orchestrators` + `/projects` every 8s and every tab reads it. | Ported as **one lazy-singleton `SessionsCubit`** rather than a new store class. It is the same daemon read-model M1's cubit already polls, returned by one probe-then-fan-out repository call; splitting it per feature would mean splitting `getSessions()`, which is exactly what the sequential-auth-probing rule forbids. See Task 4. |
| `lib/sheetResult.ts` + `app/sheets/*.tsx` | Project / agent / theme pickers are **routes**, with the selection callback parked in a module-level `Map` and its key passed as a URL param. | Already ruled out in M1 for the same reason: Expo Router's routes take serializable params, Flutter's `showModalBottomSheet<T>()` returns a value to its caller in-process. M2's three pickers are modal sheets returning `Future<String?>`, not routes. |
| `lib/api.ts` `getSessions()` fallback `s.pr ? [s.pr] : []` | Falls back to a singular `pr` field when `prs` is empty. | `SessionModel` (M1, Task 13) has no singular `pr` field, because this Go daemon's `mapSession` never populates one — RN's own board mapper only ever sets `prs`. `collectPrs` therefore reads `prs` only. |
| `lib/prView.ts` `collectPRs` key `${owner}/${repo}@${projectId}#${number}` | Includes owner/repo in the dedup key. | `SessionPrModel` has no `owner`/`repo` — the board endpoint never populates them, which is the exact regression RN's own comment documents ("it collapsed to `/#12`"). The key is `${projectId}#${number}`, which is the *fixed* behavior RN's test pins. |
| `lib/appInfo.ts` `BuildInfo` from `expo-constants` | Reads `Constants.expoConfig.version` / `ios.buildNumber` / `android.versionCode`. | `package_info_plus` exposes `version` and `buildNumber` on both platforms from one call. `formatVersion`/`bugReportBody` stay pure and take a `BuildInfo` record, so the lookup is the only adapted part — matching the spec's ledger row (`appInfo.test.ts` → adapted, `package_info_plus`). |
| `lib/prView.ts` `prTitle` first branch (`pr.title?.trim()`) | Prefers the board PR's own title before the caller's fallback. | `SessionPrModel` has no `title` field — the list endpoint never sends one, which is the very regression RN's comment documents ("without this every card in the tab reads 'Pull request #N'"). The board-facts `prTitle` therefore starts at the fallback; the card still prefers a real title when the **rich** summary supplies one (`summary?.title?.trim()` in Task 10), so the rendered behavior matches RN. |
| `lib/sheetResult.ts` → ledger row `test/core/utils/sheet_result_test.dart` | Callback-in-a-Map plumbing for sheet routes. | Not ported, as M1 already decided — Flutter returns sheet results in-process. The ledger row stays open and is closed by M6's parity sweep, which accounts for it as deliberately-not-ported rather than missed. |
| `lib/chatError.ts` → spec ledger row `test/feature/chat/logic/chat_error_test.dart` | Chat-preflight error classification. | Its M2 consumers are **orchestrator launch and spawn**; `chat` does not land until M3. Three features need it identically and none owns it, so it goes to `core/error_handling/chat_preflight.dart` — the same rule M1 applied to `connection_error.dart`. The ledger row is satisfied there; M6's parity sweep accounts for it. |

### Cross-feature imports introduced here, and why

`sessions` gains one import from `pull_request` (Task 6): the board card's PR line and the PRs tab
share one PR lifecycle vocabulary, and the spec assigns the PR domain to `pull_request`. The
alternative was duplicating a lifecycle switch in two features and letting them drift. `Tone` — a
generic presentation enum both need — is promoted to `core/` instead, since neither feature owns it.

---

### Task 1: M2 dependencies and the GitHub URL scheme query

**Files:**
- Modify: `packages/mobile/pubspec.yaml`
- Modify: `packages/mobile/ios/Runner/Info.plist`

**Interfaces:**
- Consumes: nothing.
- Produces: `url_launcher` and `package_info_plus` available to later tasks; iOS able to answer
  `canLaunchUrl(Uri.parse('github://...'))` truthfully.

On iOS, `canLaunchUrl` for a custom scheme always returns `false` unless that scheme is listed in
`LSApplicationQueriesSchemes` — `lib/openGitHub.ts`'s own comment records this ("On iOS
`canOpenURL` also needs "github" listed in LSApplicationQueriesSchemes"). Without the plist entry
Task 7's app-first branch is dead code that silently always falls through to the browser.

- [ ] **Step 1: Add the two dependencies**

In `packages/mobile/pubspec.yaml`, under `dependencies:`, after `permission_handler: ^13.0.1`:

```yaml
  url_launcher: ^6.3.2
  package_info_plus: ^10.2.1
```

- [ ] **Step 2: Declare the `github` scheme on iOS**

In `packages/mobile/ios/Runner/Info.plist`, inside the top-level `<dict>`:

```xml
	<key>LSApplicationQueriesSchemes</key>
	<array>
		<string>github</string>
	</array>
```

- [ ] **Step 3: Resolve and verify**

Run: `flutter pub get && flutter analyze && flutter test`
Expected: dependencies resolve, "No issues found!", 191/191 tests still pass.

- [ ] **Step 4: Commit**

```bash
git add packages/mobile/pubspec.yaml packages/mobile/pubspec.lock packages/mobile/ios/Runner/Info.plist
git commit -m "chore(mobile): add M2 dependencies and the github URL scheme query"
```

---

### Task 2: Shared board shapes — `shortLabel`, `Tone`, `ProjectModel`, `OrchestratorModel`

**Files:**
- Create: `packages/mobile/lib/core/utils/short_label.dart`
- Create: `packages/mobile/lib/core/app_themes/colors/tone.dart`
- Create: `packages/mobile/lib/feature/sessions/data/model/activity_string.dart`
- Create: `packages/mobile/lib/feature/sessions/data/model/project_model.dart`
- Create: `packages/mobile/lib/feature/sessions/data/model/orchestrator_model.dart`
- Modify: `packages/mobile/lib/feature/sessions/data/model/session_model.dart`
- Test: `packages/mobile/test/core/utils/short_label_test.dart`
- Test: `packages/mobile/test/feature/sessions/data/model/board_models_test.dart`

**Interfaces:**
- Consumes: `SessionModel` (M1).
- Produces:
  - `String shortLabel(String value, {int max = 20})`
  - `enum Tone { neutral, passive, success, warning, error }` and
    `Color toneColor(AppSkin skin, Tone tone)`
  - `String? activityString(dynamic raw)`
  - `class ProjectModel extends Equatable` — `id, name, kind, sessionPrefix` (all nullable);
    `ProjectModel.fromJson(Map<String, dynamic>)`
  - `class OrchestratorModel extends Equatable` — `id, projectId, projectName, status, activity,
    harness, mode, updatedAt, hasRuntime, isTerminal` (all nullable);
    `OrchestratorModel.fromJson(Map<String, dynamic> json, {String? projectName})`

`activityString` is extracted from `SessionModel._activityString` verbatim, because `/orchestrators`
returns the same session-shaped payload and `OrchestratorModel` needs the identical wire handling
(the daemon sends `activity` as either a bare string or `{state: "..."}`). `SessionModel` is
rewired to call it; its behavior does not change.

`OrchestratorModel.projectName` is not on the wire — RN's `mapOrchestrator` receives it from the
`/projects` lookup (`nameOf.get(s.projectId) ?? s.projectId`), so `fromJson` takes it as a named
argument and falls back to `projectId`.

- [ ] **Step 1: Write the failing tests**

`packages/mobile/test/core/utils/short_label_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/short_label.dart';

void main() {
  group('shortLabel', () {
    test('leaves a short value untouched', () {
      expect(shortLabel('my-app'), 'my-app');
      expect(shortLabel('12345678901234567890'), '12345678901234567890');
    });

    test('keeps the head and the tail so two projects stay distinguishable', () {
      final a = shortLabel('my-app_98d163a851');
      final b = shortLabel('my-app_11ffffffff');
      expect(a, isNot(b));
    });

    test('middle-truncates to the maximum length', () {
      final got = shortLabel('abcdefghijklmnopqrstuvwxyz');
      expect(got.length, 20);
      expect(got.contains('…'), isTrue);
      expect(got.startsWith('abcdefghij'), isTrue);
      expect(got.endsWith('rstuvwxyz'), isTrue);
    });

    test('honours a caller-supplied maximum', () {
      expect(shortLabel('abcdefghij', max: 5).length, 5);
    });
  });
}
```

`packages/mobile/test/feature/sessions/data/model/board_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/data/model/activity_string.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';

void main() {
  group('activityString', () {
    test('accepts a bare string', () {
      expect(activityString('editing'), 'editing');
    });

    test('reads the state out of an object', () {
      expect(activityString({'state': 'blocked'}), 'blocked');
    });

    test('treats empty and unknown shapes as absent', () {
      expect(activityString(''), isNull);
      expect(activityString({'state': ''}), isNull);
      expect(activityString(null), isNull);
      expect(activityString(7), isNull);
    });
  });

  group('ProjectModel', () {
    test('parses the fields the picker renders', () {
      final project = ProjectModel.fromJson({
        'id': 'my-app_98d163a851',
        'name': 'My App',
        'kind': 'single_repo',
        'sessionPrefix': 'ma',
      });
      expect(project.id, 'my-app_98d163a851');
      expect(project.name, 'My App');
      expect(project.kind, 'single_repo');
      expect(project.sessionPrefix, 'ma');
    });

    test('drops a kind the app does not know', () {
      expect(ProjectModel.fromJson({'id': 'a', 'kind': 'something_new'}).kind, isNull);
      expect(ProjectModel.fromJson({'id': 'a'}).kind, isNull);
    });

    test('keeps every kind the app does know', () {
      for (final kind in ['single_repo', 'workspace', 'scratch']) {
        expect(ProjectModel.fromJson({'id': 'a', 'kind': kind}).kind, kind);
      }
    });
  });

  group('OrchestratorModel', () {
    test('derives both lifecycle flags from isTerminated', () {
      final live = OrchestratorModel.fromJson({'id': 'o1', 'projectId': 'p'});
      expect(live.hasRuntime, isTrue);
      expect(live.isTerminal, isFalse);

      final dead = OrchestratorModel.fromJson({'id': 'o1', 'projectId': 'p', 'isTerminated': true});
      expect(dead.hasRuntime, isFalse);
      expect(dead.isTerminal, isTrue);
    });

    test('takes the project name from the caller and falls back to the id', () {
      expect(
        OrchestratorModel.fromJson({'id': 'o1', 'projectId': 'p'}, projectName: 'My App').projectName,
        'My App',
      );
      expect(OrchestratorModel.fromJson({'id': 'o1', 'projectId': 'p'}).projectName, 'p');
    });

    test('narrows mode to chat or tui', () {
      expect(OrchestratorModel.fromJson({'id': 'o', 'mode': 'chat'}).mode, 'chat');
      expect(OrchestratorModel.fromJson({'id': 'o', 'mode': 'tui'}).mode, 'tui');
      expect(OrchestratorModel.fromJson({'id': 'o'}).mode, 'tui');
    });

    test('unwraps an object-shaped activity', () {
      expect(
        OrchestratorModel.fromJson({'id': 'o', 'activity': {'state': 'blocked'}}).activity,
        'blocked',
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/utils/short_label_test.dart test/feature/sessions/data/model/board_models_test.dart`
Expected: FAIL — the target libraries do not exist yet.

- [ ] **Step 3: Write the implementations**

`packages/mobile/lib/core/utils/short_label.dart`:

```dart
const int _maxLabel = 20;

String shortLabel(String value, {int max = _maxLabel}) {
  if (value.length <= max) return value;
  final keep = max - 1;
  final head = (keep / 2).ceil();
  final tail = (keep / 2).floor();
  return '${value.substring(0, head)}…${value.substring(value.length - tail)}';
}
```

`packages/mobile/lib/core/app_themes/colors/tone.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

enum Tone { neutral, passive, success, warning, error }

Color toneColor(AppSkin skin, Tone tone) {
  switch (tone) {
    case Tone.success:
      return skin.green;
    case Tone.warning:
      return skin.amber;
    case Tone.error:
      return skin.red;
    case Tone.passive:
      return skin.textTertiary;
    case Tone.neutral:
      return skin.textSecondary;
  }
}
```

`packages/mobile/lib/feature/sessions/data/model/activity_string.dart`:

```dart
String? activityString(dynamic raw) {
  if (raw is String) return raw.isEmpty ? null : raw;
  if (raw is Map<String, dynamic> && raw['state'] is String) {
    final state = raw['state'] as String;
    return state.isEmpty ? null : state;
  }
  return null;
}
```

`packages/mobile/lib/feature/sessions/data/model/project_model.dart`:

```dart
import 'package:equatable/equatable.dart';

const Set<String> _knownKinds = {'single_repo', 'workspace', 'scratch'};

class ProjectModel extends Equatable {
  const ProjectModel({this.id, this.name, this.kind, this.sessionPrefix});

  final String? id;
  final String? name;
  final String? kind;
  final String? sessionPrefix;

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    final rawKind = json['kind'];
    return ProjectModel(
      id: json['id'] as String?,
      name: json['name'] as String?,
      kind: rawKind is String && _knownKinds.contains(rawKind) ? rawKind : null,
      sessionPrefix: json['sessionPrefix'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, name, kind, sessionPrefix];
}
```

`packages/mobile/lib/feature/sessions/data/model/orchestrator_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/sessions/data/model/activity_string.dart';

class OrchestratorModel extends Equatable {
  const OrchestratorModel({
    this.id,
    this.projectId,
    this.projectName,
    this.status,
    this.activity,
    this.harness,
    this.mode,
    this.updatedAt,
    this.hasRuntime,
    this.isTerminal,
  });

  final String? id;
  final String? projectId;
  final String? projectName;
  final String? status;
  final String? activity;
  final String? harness;
  final String? mode;
  final String? updatedAt;
  final bool? hasRuntime;
  final bool? isTerminal;

  factory OrchestratorModel.fromJson(Map<String, dynamic> json, {String? projectName}) {
    final isTerminated = json['isTerminated'] as bool? ?? false;
    final projectId = json['projectId'] as String?;
    return OrchestratorModel(
      id: json['id'] as String?,
      projectId: projectId,
      projectName: projectName ?? projectId,
      status: json['status'] as String?,
      activity: activityString(json['activity']),
      harness: json['harness'] as String?,
      mode: json['mode'] == 'chat' ? 'chat' : 'tui',
      updatedAt: json['updatedAt'] as String?,
      hasRuntime: !isTerminated,
      isTerminal: isTerminated,
    );
  }

  @override
  List<Object?> get props => [
    id, projectId, projectName, status, activity, harness, mode, updatedAt, hasRuntime, isTerminal,
  ];
}
```

- [ ] **Step 4: Rewire `SessionModel` onto the shared helper**

In `packages/mobile/lib/feature/sessions/data/model/session_model.dart`, delete the private
`_activityString` static and import the new helper instead:

```dart
import 'package:operator_mobile/feature/sessions/data/model/activity_string.dart';
```

and change the one call site inside `fromJson`:

```dart
    activity: activityString(json['activity']),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/core/utils/short_label_test.dart test/feature/sessions/data/model/board_models_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add shared board shapes, Tone, and shortLabel"
```

---

### Task 3: Sequential auth probing — one board fetch, `/sessions` first

**Files:**
- Create: `packages/mobile/lib/feature/sessions/data/model/board_snapshot.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Modify: `packages/mobile/lib/feature/sessions/data/data_source/sessions_remote_data_source.dart`
- Modify: `packages/mobile/lib/feature/sessions/data/repository/sessions_repository.dart`
- Test: `packages/mobile/test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart`
- Test: `packages/mobile/test/feature/sessions/data/repository/sessions_repository_test.dart`

**Interfaces:**
- Consumes: `SessionModel`, `ProjectModel`, `OrchestratorModel` (Task 2).
- Produces:
  - `class BoardSnapshot extends Equatable` — `sessions (List<SessionModel>)`,
    `orchestrators (List<OrchestratorModel>)`, `projects (List<ProjectModel>)`, all non-null.
  - `SessionsRemoteDataSource.getBoard() → Future<GlobalResponse<BoardSnapshot>>`, replacing
    `getSessions()`.
  - `SessionsRepository.getBoard() → FutureResult<GlobalResponse<BoardSnapshot>>`, replacing
    `getSessions()`.
  - `EndPoints.orchestrators`

This is the spec's **load-bearing** behavior, and M1's plan explicitly deferred it here:

> The ordering discipline becomes actionable — and gets its test — in M2, when the project switcher
> and orchestrator tab add the second and third call.

`GET /sessions` is awaited **alone**. Only once it succeeds do `/orchestrators` and `/projects` go
out together. The daemon locks a device out for a minute after 5 failed auths; fanning all three
out at once would burn 3 failures per 8s tick and arm the lockout before the user could re-pair.
`Future.wait` over all three reintroduces that bug silently, which is why the test below pins the
ordering with a gate rather than merely asserting all three were called.

`/projects` failing degrades to an empty list (RN: `getProjects(cfg).catch(() => [])`) — a daemon
too old to serve it must not blank the board. `/orchestrators` failing propagates.

The orchestrator dedup mirrors `getSessions()` verbatim: the daemon returns every orchestrator
session per project (one per past kill/respawn), so keep one per project, preferring a live one,
else the latest — otherwise the tab shows "Restart" beside a running orchestrator.

- [ ] **Step 1: Write the failing data-source test**

Replace the `getSessions` group in
`packages/mobile/test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart`
with (keep the file's existing `kill`/`restore` groups and its existing imports, adding `dart:async`
and the new model imports):

```dart
  Response<dynamic> jsonResponse(Map<String, dynamic> body) =>
      Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: body);

  group('getBoard', () {
    test('probes /sessions alone before fanning out to the other two', () async {
      final sessionsGate = Completer<Response<dynamic>>();
      final calls = <String>[];

      when(() => apiConsumer.get(any())).thenAnswer((invocation) {
        final path = invocation.positionalArguments.first as String;
        calls.add(path);
        if (path == EndPoints.sessions) return sessionsGate.future;
        return Future.value(jsonResponse({'sessions': <dynamic>[], 'projects': <dynamic>[]}));
      });

      final pending = dataSource.getBoard();
      await Future<void>.delayed(Duration.zero);

      expect(calls, [EndPoints.sessions]);

      sessionsGate.complete(jsonResponse({'sessions': <dynamic>[]}));
      await pending;

      expect(calls.length, 3);
      expect(calls.first, EndPoints.sessions);
      expect(calls.sublist(1).toSet(), {EndPoints.orchestrators, EndPoints.projects});
    });

    test('drops orchestrator-kind rows from the session list', () async {
      when(() => apiConsumer.get(EndPoints.sessions)).thenAnswer(
        (_) async => jsonResponse({
          'sessions': [
            {'id': 'w1', 'projectId': 'p', 'kind': 'worker'},
            {'id': 'o1', 'projectId': 'p', 'kind': 'orchestrator'},
          ],
        }),
      );
      when(() => apiConsumer.get(EndPoints.orchestrators))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.projects))
          .thenAnswer((_) async => jsonResponse({'projects': <dynamic>[]}));

      final board = await dataSource.getBoard();
      expect(board.data!.sessions.map((s) => s.id), ['w1']);
    });

    test('keeps one orchestrator per project, preferring the live one', () async {
      when(() => apiConsumer.get(EndPoints.sessions))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.orchestrators)).thenAnswer(
        (_) async => jsonResponse({
          'sessions': [
            {'id': 'old', 'projectId': 'p', 'isTerminated': true},
            {'id': 'live', 'projectId': 'p'},
          ],
        }),
      );
      when(() => apiConsumer.get(EndPoints.projects))
          .thenAnswer((_) async => jsonResponse({'projects': <dynamic>[]}));

      final board = await dataSource.getBoard();
      expect(board.data!.orchestrators.map((o) => o.id), ['live']);
    });

    test('falls back to the most recent when every orchestrator is terminated', () async {
      when(() => apiConsumer.get(EndPoints.sessions))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.orchestrators)).thenAnswer(
        (_) async => jsonResponse({
          'sessions': [
            {'id': 'older', 'projectId': 'p', 'isTerminated': true},
            {'id': 'newer', 'projectId': 'p', 'isTerminated': true},
          ],
        }),
      );
      when(() => apiConsumer.get(EndPoints.projects))
          .thenAnswer((_) async => jsonResponse({'projects': <dynamic>[]}));

      final board = await dataSource.getBoard();
      expect(board.data!.orchestrators.map((o) => o.id), ['newer']);
    });

    test('labels orchestrators with their project name', () async {
      when(() => apiConsumer.get(EndPoints.sessions))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.orchestrators)).thenAnswer(
        (_) async => jsonResponse({
          'sessions': [{'id': 'o1', 'projectId': 'p'}],
        }),
      );
      when(() => apiConsumer.get(EndPoints.projects)).thenAnswer(
        (_) async => jsonResponse({
          'projects': [{'id': 'p', 'name': 'My App'}],
        }),
      );

      final board = await dataSource.getBoard();
      expect(board.data!.orchestrators.single.projectName, 'My App');
    });

    test('degrades to no projects rather than failing the whole board', () async {
      when(() => apiConsumer.get(EndPoints.sessions))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.orchestrators))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.projects)).thenAnswer((_) async => throw Exception('404'));

      final board = await dataSource.getBoard();
      expect(board.data!.projects, isEmpty);
    });
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/sessions/data/data_source/sessions_remote_data_source_test.dart`
Expected: FAIL — `getBoard` is not defined.

- [ ] **Step 3: Add the endpoint and the snapshot shape**

In `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`, after `sessions`:

```dart
  static const String orchestrators = '/api/v1/orchestrators';
```

`packages/mobile/lib/feature/sessions/data/model/board_snapshot.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

class BoardSnapshot extends Equatable {
  const BoardSnapshot({
    this.sessions = const [],
    this.orchestrators = const [],
    this.projects = const [],
  });

  final List<SessionModel> sessions;
  final List<OrchestratorModel> orchestrators;
  final List<ProjectModel> projects;

  @override
  List<Object?> get props => [sessions, orchestrators, projects];
}
```

- [ ] **Step 4: Rewrite the data source's read**

Replace `getSessions()` in
`packages/mobile/lib/feature/sessions/data/data_source/sessions_remote_data_source.dart`
(the abstract member becomes `Future<GlobalResponse<BoardSnapshot>> getBoard();`):

```dart
  @override
  Future<GlobalResponse<BoardSnapshot>> getBoard() async {
    final sessionsResponse = await _apiConsumer.get(EndPoints.sessions);

    final orchestratorsFuture = _apiConsumer.get(EndPoints.orchestrators);
    final projectsFuture = _fetchProjects();
    final orchestratorsResponse = await orchestratorsFuture;
    final projects = await projectsFuture;

    final nameOf = {
      for (final project in projects)
        if (project.id != null) project.id!: project.name ?? project.id!,
    };

    return GlobalResponse<BoardSnapshot>.fromJson(
      sessionsResponse.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => BoardSnapshot(
        sessions: _rows(json)
            .map(SessionModel.fromJson)
            .where((s) => s.kind != 'orchestrator')
            .toList(),
        orchestrators: _bestPerProject(_rows(orchestratorsResponse.data))
            .map((row) => OrchestratorModel.fromJson(row, projectName: nameOf[row['projectId']]))
            .toList(),
        projects: projects,
      ),
    );
  }

  Future<List<ProjectModel>> _fetchProjects() async {
    try {
      final response = await _apiConsumer.get(EndPoints.projects);
      final body = response.data as Map<String, dynamic>;
      return (body['projects'] as List<dynamic>? ?? const [])
          .map((p) => ProjectModel.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<Map<String, dynamic>> _rows(dynamic body) =>
      ((body as Map<String, dynamic>?)?['sessions'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();

  static List<Map<String, dynamic>> _bestPerProject(List<Map<String, dynamic>> rows) {
    final best = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final projectId = row['projectId'] as String? ?? '';
      final current = best[projectId];
      if (current == null || (current['isTerminated'] as bool? ?? false)) {
        best[projectId] = row;
      }
    }
    return best.values.toList();
  }
```

Add the imports for `BoardSnapshot`, `OrchestratorModel` and `ProjectModel`.

- [ ] **Step 5: Rewrite the repository's read**

In `packages/mobile/lib/feature/sessions/data/repository/sessions_repository.dart`, rename
`getSessions()` to `getBoard()` on both the abstract class and `SessionsRepositoryImp`, changing
the return type to `FutureResult<GlobalResponse<BoardSnapshot>>` and the delegated call to
`_remoteDataSource.getBoard()`. The `kill`/`restore` members are unchanged. Update the repository
test's `getSessions` references to `getBoard` and its stub payloads to return a `BoardSnapshot`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/feature/sessions/data/`
Expected: PASS.

- [ ] **Step 7: Commit**

`SessionsCubit` still calls `getSessions()` and will not compile until Task 4 — run
`flutter analyze` expecting exactly that one class of error, and commit the two tasks' work
together at the end of Task 4 if you prefer a green tree per commit. Otherwise:

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): probe /sessions alone before fanning out to orchestrators and projects"
```

---

### Task 4: `SessionsCubit` becomes the shared board store

**Files:**
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/logic/sessions_state.dart`
- Modify: `packages/mobile/lib/core/helpers/cache/cache_keys.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart`
- Test: `packages/mobile/test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`

**Interfaces:**
- Consumes: `BoardSnapshot`, `SessionsRepository.getBoard()` (Task 3); `MuxClient` (M1).
- Produces, on `SessionsCubit`:
  - `List<SessionModel> sessions`, `List<OrchestratorModel> orchestrators`,
    `List<ProjectModel> projects` — all plain fields, as `sessions` already was in M1.
  - `String activeProjectId` and `const String kAllProjects = 'all'`
  - `List<SessionModel> get visibleSessions`
  - `void setActiveProject(String id)`
  - `Future<void> refresh()` (unchanged name)
  - `CacheKeys.activeProjectId`

The cubit is registered as a **lazy singleton** and provided once above the tab shell. That is the
whole point of Task 3's probing discipline: one poll for the app, not one per tab.

Two consequences the implementer must not miss:

- `app_router.dart`'s sessions route must use `BlocProvider.value`, **not** `BlocProvider(create:)`.
  `create:` closes the bloc when the route pops, which would kill the singleton's poll timer for
  the rest of the app's life.
- `sessions_body.dart` reads `cubit.sessions` today; it must read `cubit.visibleSessions` so the
  project switcher actually scopes the board.

`setActiveProject` emits through `_emitSessions()` — the revision-carrying emit added in M1's
final fix wave — because a filter change must repaint even though `sessions` itself did not change.
Emitting `const GetSessionsSuccessState()` here would be the exact bug that wave fixed.

- [ ] **Step 1: Write the failing tests**

Append to `packages/mobile/test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`
(the file's existing `repository`/`mux` mocks and `patchesController` stay; stub `getBoard` in place
of `getSessions` throughout, returning `Result.success(GlobalResponse(data: BoardSnapshot(...)))`):

```dart
  blocTest<SessionsCubit, SessionsState>(
    'exposes projects and orchestrators from one board fetch',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(
            data: const BoardSnapshot(
              sessions: [SessionModel(id: 'proj-1', projectId: 'p')],
              orchestrators: [OrchestratorModel(id: 'o1', projectId: 'p')],
              projects: [ProjectModel(id: 'p', name: 'My App')],
            ),
          ),
        ),
      );
      return SessionsCubit(repository, mux);
    },
    act: (cubit) => Future<void>.delayed(Duration.zero),
    verify: (cubit) {
      expect(cubit.projects.single.name, 'My App');
      expect(cubit.orchestrators.single.id, 'o1');
      expect(cubit.sessions.single.id, 'proj-1');
    },
  );

  blocTest<SessionsCubit, SessionsState>(
    'scopes visibleSessions to the active project and repaints on the change',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(
            data: const BoardSnapshot(
              sessions: [
                SessionModel(id: 'a', projectId: 'p1'),
                SessionModel(id: 'b', projectId: 'p2'),
              ],
            ),
          ),
        ),
      );
      return SessionsCubit(repository, mux);
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      expect(cubit.visibleSessions.map((s) => s.id), ['a', 'b']);
      cubit.setActiveProject('p2');
    },
    expect: () => [
      isA<GetSessionsLoadingState>(),
      isA<GetSessionsSuccessState>().having((s) => s.revision, 'revision', 1),
      isA<GetSessionsSuccessState>().having((s) => s.revision, 'revision', 2),
    ],
    verify: (cubit) {
      expect(cubit.activeProjectId, 'p2');
      expect(cubit.visibleSessions.map((s) => s.id), ['b']);
    },
  );

  blocTest<SessionsCubit, SessionsState>(
    'defaults to every project',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const BoardSnapshot())),
      );
      return SessionsCubit(repository, mux);
    },
    verify: (cubit) => expect(cubit.activeProjectId, kAllProjects),
  );
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/feature/sessions/presentation/sessions_screen/logic/sessions_cubit_test.dart`
Expected: FAIL — `getBoard`, `projects`, `visibleSessions`, `kAllProjects` are not defined.

- [ ] **Step 3: Add the cache key**

In `packages/mobile/lib/core/helpers/cache/cache_keys.dart`:

```dart
  static const String activeProjectId = 'opr.activeProjectId';
```

- [ ] **Step 4: Extend the cubit**

In `sessions_cubit.dart` — add the imports for `BoardSnapshot`, `OrchestratorModel`,
`ProjectModel` and `CacheHelper`, then:

```dart
const String kAllProjects = 'all';
```

Inside the class, beside the existing `sessions` field:

```dart
  List<OrchestratorModel> orchestrators = [];
  List<ProjectModel> projects = [];
  String activeProjectId = (CacheHelper.get(CacheKeys.activeProjectId) as String?) ?? kAllProjects;

  List<SessionModel> get visibleSessions => activeProjectId == kAllProjects
      ? sessions
      : sessions.where((s) => s.projectId == activeProjectId).toList();

  void setActiveProject(String id) {
    activeProjectId = id;
    CacheHelper.save(CacheKeys.activeProjectId, id);
    _emitSessions();
  }
```

and rewrite `_tick`'s success branch:

```dart
    final result = await _repository.getBoard();
    result.when(
      onSuccess: (response) {
        final board = response.data ?? const BoardSnapshot();
        sessions = board.sessions;
        orchestrators = board.orchestrators;
        projects = board.projects;
        _emitSessions();
      },
```

The `onFailure` branch, the poll timer, `_applyPatches` and `close()` are unchanged.

- [ ] **Step 5: Make it a singleton and stop the router closing it**

In `service_locator.dart`, change the sessions registration:

```dart
    sl.registerLazySingleton<SessionsCubit>(() => SessionsCubit(sl<SessionsRepository>(), sl<MuxClient>()));
```

In `app_router.dart`, the sessions route becomes (its screen is replaced in Task 5; this step only
fixes the provider):

```dart
      case RoutesStrings.sessions:
        return MaterialPageRoute(
          builder: (context) => BlocProvider.value(value: sl<SessionsCubit>(), child: const SessionsScreen()),
          settings: settings,
        );
```

- [ ] **Step 6: Scope the board's list**

In `sessions_body.dart`, replace every `cubit.sessions` read with `cubit.visibleSessions` — the
empty-state guards, the `groupSessions(...)` call, and the stats loop.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): make SessionsCubit the shared board store"
```

---

### Task 5: The four-tab shell

**Files:**
- Create: `packages/mobile/lib/core/app_routes/home_shell.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart`
- Test: `packages/mobile/test/core/app_routes/home_shell_test.dart`

**Interfaces:**
- Consumes: `SessionsCubit` singleton (Task 4).
- Produces: `class HomeShell extends StatefulWidget` — a `Scaffold` with a `BottomNavigationBar`
  over an `IndexedStack` of the four tab bodies, with `SessionsCubit` provided above it via
  `BlocProvider.value`.

The shell owns no daemon state, so it is not a feature under the spec's table — it is navigation
chrome, which is why it lives beside the router rather than under `lib/feature/`.

`IndexedStack`, not a swapped child: each tab keeps its scroll position and its own cubit state
when you leave and come back, which is what `expo-router`'s `<Tabs>` does. `RoutesStrings.sessions`
keeps its `/sessions` value so M1's pairing-success navigation and `main.dart`'s `initialRoute`
need no change — only its destination widget changes.

The three new tab bodies do not exist yet. Build the shell against placeholder bodies in this task
and replace each one in its feature's screen task (10, 14, 20); the test below asserts only the
shell's own behavior, so it stays valid as the bodies land.

The `children` list is deliberately **not** `const` even though every entry is const today: Tasks
14 and 20 pass an `onOpenBoard` closure into two of them, and a `const` list would have to be
un-consted at that point anyway.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/app_routes/home_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;

  setUp(() {
    repository = _MockSessionsRepository();
    mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => repository.getBoard())
        .thenAnswer((_) async => Result.success(GlobalResponse(data: const BoardSnapshot())));
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: BlocProvider(
              create: (_) => SessionsCubit(repository, mux),
              child: const HomeShell(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers all four tabs', (tester) async {
    await pumpShell(tester);

    for (final label in ['Agents', 'Orchestrator', 'PRs', 'Settings']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('opens on the Agents tab', (tester) async {
    await pumpShell(tester);

    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).currentIndex, 0);
  });

  testWidgets('switches tabs on tap', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).currentIndex, 3);
  });

  testWidgets('keeps every tab mounted so each keeps its state', (tester) async {
    await pumpShell(tester);

    expect(find.byType(IndexedStack), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).children.length, 4);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/app_routes/home_shell_test.dart`
Expected: FAIL — `home_shell.dart` does not exist.

- [ ] **Step 3: Write the shell**

`packages/mobile/lib/core/app_routes/home_shell.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: IndexedStack(
        index: _index,
        children: [
          const SessionsScreen(),
          const SizedBox.shrink(),
          const SizedBox.shrink(),
          const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (next) => setState(() => _index = next),
        type: BottomNavigationBarType.fixed,
        backgroundColor: skin.bgSurface,
        selectedItemColor: skin.blue,
        unselectedItemColor: skin.textTertiary,
        selectedLabelStyle: AppTextStyle.style11SemiBold,
        unselectedLabelStyle: AppTextStyle.style11SemiBold,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_motion_outlined), label: 'Agents'),
          BottomNavigationBarItem(icon: Icon(Icons.hub_outlined), label: 'Orchestrator'),
          BottomNavigationBarItem(icon: Icon(Icons.merge_outlined), label: 'PRs'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Route `/sessions` at the shell**

In `app_router.dart`, swap the child widget (the `BlocProvider.value` from Task 4 stays):

```dart
      case RoutesStrings.sessions:
        return MaterialPageRoute(
          builder: (context) => BlocProvider.value(value: sl<SessionsCubit>(), child: const HomeShell()),
          settings: settings,
        );
```

- [ ] **Step 5: Let the sessions screen sit inside the shell**

`SessionsScreen` currently returns an `AppScaffold`; nested inside the shell's `Scaffold` that
would draw a second background and swallow the shell's bottom bar. Change its `AppScaffold` to
`Scaffold` with `backgroundColor: context.skin.bgBase` and keep its `GlobalAppbar.main`, so the
tab keeps its own header while the shell owns the chrome below it.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the four-tab home shell"
```

---

### Task 6: PR presentation vocabulary (`prView.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/pull_request/logic/pr_view.dart`
- Modify: `packages/mobile/lib/feature/sessions/logic/agents_view.dart`
- Test: `packages/mobile/test/feature/pull_request/logic/pr_view_test.dart`

**Interfaces:**
- Consumes: `SessionModel`, `SessionPrModel` (M1); `Tone`/`toneColor` (Task 2); `AppSkin`.
- Produces:
  - `enum PrLifecycle { open, draft, merged, closed }`
  - `PrLifecycle prLifecycleOf(SessionPrModel pr)`
  - `class PrEntry extends Equatable` — `pr (SessionPrModel)`, `session (SessionModel)`
  - `List<PrEntry> collectPrs(List<SessionModel> sessions)`
  - `String prTitle(SessionPrModel pr, [String? fallback])`
  - `String mergeReasonLabel(String reason)`
  - `class PrStatusAtom extends Equatable` — `text (String)`, `tone (Tone)`
  - `PrStatusAtom prSummaryLine(SessionPrModel pr)`
  - `class PrStateVisual` — `label (PrLifecycle)`, `color (Color)`, `tint (Color)`
  - `PrStateVisual stateVisualOf(AppSkin skin, PrLifecycle life)`
  - `PrStateVisual prStateVisual(AppSkin skin, SessionPrModel pr)`
  - `int comparePrs(SessionPrModel a, SessionPrModel b)`
  - `PrLifecycle prLifecycleFromName(String? name)` — the rich summary reports its lifecycle as a
    bare string, and `PrLifecycle.values.byName` **throws** on anything unexpected, so a daemon
    that grows a fifth state would crash the PRs tab. This falls back to `PrLifecycle.open`.

`agents_view.dart` loses its local `enum Tone` and its `String prLifecycle(SessionPrModel)`,
importing both from their new homes. `prLine` keeps its behavior by switching on
`prLifecycleOf(pr).name`, which produces the same four strings it produced before — the board
card's text is unchanged, and its existing test in `agents_view_test.dart` proves it.

RN's `DashboardPR` field names map onto M1's `SessionPrModel` as: `ciStatus`→`ci`,
`reviewDecision`→`review`, `unresolvedThreads` (a count)→`reviewComments` (a bool),
`mergeability.mergeable`→`mergeable` (a bool), `isDraft`→`state == 'draft'`. M1's model keeps the
daemon's own enum strings, so the comparisons below are against the wire values directly.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/pull_request/logic/pr_view_test.dart` (ported from `prView.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/tone.dart';
import 'package:operator_mobile/feature/pull_request/logic/pr_view.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';

SessionPrModel pr({
  int? number = 184,
  String? state = 'open',
  String? ci,
  String? review,
  bool? mergeable,
  bool? reviewComments,
}) => SessionPrModel(
  url: 'https://github.com/o/r/pull/184',
  number: number,
  state: state,
  ci: ci,
  review: review,
  mergeable: mergeable,
  reviewComments: reviewComments,
);

SessionModel session(String projectId, List<SessionPrModel> prs, [String? id]) =>
    SessionModel(id: id ?? '$projectId-1', projectId: projectId, prs: prs);

void main() {
  const skin = DarkSkin();

  group('collectPrs', () {
    test('keeps the same PR number in two different projects', () {
      final got = collectPrs([
        session('alpha', [pr(number: 12)]),
        session('beta', [pr(number: 12)]),
      ]);
      expect(got.map((e) => e.session.projectId), ['alpha', 'beta']);
    });

    test('collapses the same PR seen from two sessions in one project', () {
      final got = collectPrs([
        session('alpha', [pr(number: 12)], 'alpha-1'),
        session('alpha', [pr(number: 12)], 'alpha-2'),
      ]);
      expect(got, hasLength(1));
    });

    test('skips placeholder PRs with no real number', () {
      expect(collectPrs([session('alpha', [pr(number: 0)])]), isEmpty);
      expect(collectPrs([session('alpha', [pr(number: null)])]), isEmpty);
    });

    test('tolerates a session with no PR list at all', () {
      expect(collectPrs([const SessionModel(id: 'a', projectId: 'alpha')]), isEmpty);
    });
  });

  group('prTitle', () {
    test('falls back to the session title when the daemon sent none', () {
      expect(prTitle(pr(), 'Fix auth timeouts on refresh'), 'Fix auth timeouts on refresh');
    });

    test('falls back to the PR number only when there is nothing else', () {
      expect(prTitle(pr()), 'Pull request #184');
      expect(prTitle(pr(), ''), 'Pull request #184');
      expect(prTitle(pr(), '   '), 'Pull request #184');
    });
  });

  group('prLifecycleOf', () {
    test('reports a draft', () {
      expect(prLifecycleOf(pr(state: 'draft')), PrLifecycle.draft);
    });

    test('reports merged and closed', () {
      expect(prLifecycleOf(pr(state: 'merged')), PrLifecycle.merged);
      expect(prLifecycleOf(pr(state: 'closed')), PrLifecycle.closed);
    });

    test('defaults to open', () {
      expect(prLifecycleOf(pr()), PrLifecycle.open);
      expect(prLifecycleOf(pr(state: null)), PrLifecycle.open);
    });
  });

  group('mergeReasonLabel', () {
    test('humanises the reasons desktop knows', () {
      expect(mergeReasonLabel('behind_base'), 'branch behind base');
      expect(mergeReasonLabel('ci_failing'), 'CI failing');
      expect(mergeReasonLabel('changes_requested'), 'changes requested');
      expect(mergeReasonLabel('review_required'), 'review required');
      expect(mergeReasonLabel('blocked_by_provider'), 'provider blocked');
    });

    test('degrades an unknown reason into readable words', () {
      expect(mergeReasonLabel('some_new_reason'), 'some new reason');
    });
  });

  group('prSummaryLine', () {
    test('says only the outcome for a decided PR', () {
      expect(prSummaryLine(pr(state: 'merged', ci: 'failing')).text, 'Merged');
      expect(prSummaryLine(pr(state: 'closed')).text, 'Closed without merging');
    });

    test('leads with the worst problem', () {
      final line = prSummaryLine(pr(ci: 'failing', review: 'changes_requested'));
      expect(line.text.startsWith('CI failing'), isTrue);
      expect(line.tone, Tone.error);
    });

    test('never shows more than two problems', () {
      final line = prSummaryLine(pr(ci: 'failing', review: 'changes_requested', reviewComments: true));
      expect(line.text.split(' · '), hasLength(2));
    });

    test('calls out a PR that is ready to go', () {
      final line = prSummaryLine(pr(review: 'approved', mergeable: true));
      expect(line.text, 'Ready to merge');
      expect(line.tone, Tone.success);
    });

    test('reports a draft as a draft', () {
      expect(prSummaryLine(pr(state: 'draft')).text, 'Draft');
    });

    test('falls back through CI and review before plain open', () {
      expect(prSummaryLine(pr(ci: 'pending')).text, 'CI running');
      expect(prSummaryLine(pr(review: 'pending')).text, 'Awaiting review');
      expect(prSummaryLine(pr()).text, 'Open');
    });

    test('surfaces unresolved comments when there is no formal refusal', () {
      expect(prSummaryLine(pr(reviewComments: true)).text, 'Unresolved comments');
    });
  });

  group('stateVisualOf', () {
    test('gives merged its own hue, distinct from open', () {
      expect(stateVisualOf(skin, PrLifecycle.merged).color, skin.purple);
      expect(stateVisualOf(skin, PrLifecycle.open).color, skin.green);
      expect(stateVisualOf(skin, PrLifecycle.closed).color, skin.red);
      expect(stateVisualOf(skin, PrLifecycle.draft).color, skin.textTertiary);
    });

    test('reads the lifecycle off a board PR', () {
      expect(prStateVisual(skin, pr(state: 'merged')).label, PrLifecycle.merged);
    });
  });

  group('comparePrs', () {
    List<int?> sorted(List<SessionPrModel> list) =>
        ([...list]..sort(comparePrs)).map((p) => p.number).toList();

    test('orders open before draft before merged before closed', () {
      expect(
        sorted([
          pr(number: 1, state: 'closed'),
          pr(number: 2, state: 'merged'),
          pr(number: 3, state: 'draft'),
          pr(number: 4),
        ]),
        [4, 3, 2, 1],
      );
    });

    test('floats a ready-to-merge PR to the top of the open bucket', () {
      expect(sorted([pr(number: 10), pr(number: 2, review: 'approved', mergeable: true)]).first, 2);
    });

    test('puts PRs needing attention above quiet ones', () {
      expect(
        sorted([pr(number: 9), pr(number: 5, review: 'changes_requested'), pr(number: 3, ci: 'failing')]),
        [3, 5, 9],
      );
    });

    test('breaks ties with the newest PR first', () {
      expect(sorted([pr(number: 4), pr(number: 12), pr(number: 7)]), [12, 7, 4]);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/pull_request/logic/pr_view_test.dart`
Expected: FAIL — `pr_view.dart` does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/pull_request/logic/pr_view.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/tone.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';

enum PrLifecycle { open, draft, merged, closed }

PrLifecycle prLifecycleOf(SessionPrModel pr) {
  switch (pr.state) {
    case 'merged':
      return PrLifecycle.merged;
    case 'closed':
      return PrLifecycle.closed;
    case 'draft':
      return PrLifecycle.draft;
    default:
      return PrLifecycle.open;
  }
}

class PrEntry extends Equatable {
  const PrEntry({required this.pr, required this.session});

  final SessionPrModel pr;
  final SessionModel session;

  @override
  List<Object?> get props => [pr, session];
}

List<PrEntry> collectPrs(List<SessionModel> sessions) {
  final seen = <String>{};
  final out = <PrEntry>[];
  for (final session in sessions) {
    for (final pr in session.prs ?? const <SessionPrModel>[]) {
      final number = pr.number ?? 0;
      if (number <= 0) continue;
      if (!seen.add('${session.projectId}#$number')) continue;
      out.add(PrEntry(pr: pr, session: session));
    }
  }
  return out;
}

String prTitle(SessionPrModel pr, [String? fallback]) {
  final backfill = fallback?.trim();
  if (backfill != null && backfill.isNotEmpty) return backfill;
  return 'Pull request #${pr.number}';
}

String mergeReasonLabel(String reason) {
  switch (reason) {
    case 'behind_base':
      return 'branch behind base';
    case 'ci_failing':
      return 'CI failing';
    case 'changes_requested':
      return 'changes requested';
    case 'review_required':
      return 'review required';
    case 'blocked_by_provider':
      return 'provider blocked';
    default:
      return reason.replaceAll('_', ' ');
  }
}

class PrStatusAtom extends Equatable {
  const PrStatusAtom({required this.text, required this.tone});

  final String text;
  final Tone tone;

  @override
  List<Object?> get props => [text, tone];
}

PrStatusAtom prSummaryLine(SessionPrModel pr) {
  final life = prLifecycleOf(pr);
  if (life == PrLifecycle.merged) return const PrStatusAtom(text: 'Merged', tone: Tone.success);
  if (life == PrLifecycle.closed) {
    return const PrStatusAtom(text: 'Closed without merging', tone: Tone.passive);
  }

  final atoms = <PrStatusAtom>[];
  if (pr.ci == 'failing') atoms.add(const PrStatusAtom(text: 'CI failing', tone: Tone.error));
  if (pr.review == 'changes_requested') {
    atoms.add(const PrStatusAtom(text: 'Changes requested', tone: Tone.warning));
  } else if (pr.reviewComments == true) {
    atoms.add(const PrStatusAtom(text: 'Unresolved comments', tone: Tone.warning));
  }

  if (atoms.isEmpty) {
    if (life == PrLifecycle.draft) return const PrStatusAtom(text: 'Draft', tone: Tone.passive);
    if (pr.mergeable == true && pr.review == 'approved') {
      return const PrStatusAtom(text: 'Ready to merge', tone: Tone.success);
    }
    if (pr.ci == 'pending') return const PrStatusAtom(text: 'CI running', tone: Tone.neutral);
    if (pr.review == 'approved') return const PrStatusAtom(text: 'Approved', tone: Tone.success);
    if (pr.review == 'pending') return const PrStatusAtom(text: 'Awaiting review', tone: Tone.neutral);
    return const PrStatusAtom(text: 'Open', tone: Tone.passive);
  }

  final shown = atoms.take(2).toList();
  final tone = shown.any((a) => a.tone == Tone.error) ? Tone.error : Tone.warning;
  return PrStatusAtom(text: shown.map((a) => a.text).join(' · '), tone: tone);
}

class PrStateVisual {
  const PrStateVisual({required this.label, required this.color, required this.tint});

  final PrLifecycle label;
  final Color color;
  final Color tint;
}

PrStateVisual stateVisualOf(AppSkin skin, PrLifecycle life) {
  switch (life) {
    case PrLifecycle.merged:
      return PrStateVisual(label: life, color: skin.purple, tint: skin.tintPurple);
    case PrLifecycle.closed:
      return PrStateVisual(label: life, color: skin.red, tint: skin.tintRed);
    case PrLifecycle.draft:
      return PrStateVisual(label: life, color: skin.textTertiary, tint: skin.bgSubtle);
    case PrLifecycle.open:
      return PrStateVisual(label: life, color: skin.green, tint: skin.tintGreen);
  }
}

PrStateVisual prStateVisual(AppSkin skin, SessionPrModel pr) => stateVisualOf(skin, prLifecycleOf(pr));

PrLifecycle prLifecycleFromName(String? name) {
  for (final life in PrLifecycle.values) {
    if (life.name == name) return life;
  }
  return PrLifecycle.open;
}

const Map<PrLifecycle, int> _lifecycleOrder = {
  PrLifecycle.open: 0,
  PrLifecycle.draft: 1,
  PrLifecycle.merged: 2,
  PrLifecycle.closed: 3,
};

int _openRank(SessionPrModel pr) {
  if (pr.mergeable == true && pr.review == 'approved') return 0;
  if (pr.ci == 'failing') return 1;
  if (pr.review == 'changes_requested' || pr.reviewComments == true) return 2;
  return 3;
}

int comparePrs(SessionPrModel a, SessionPrModel b) {
  final life = _lifecycleOrder[prLifecycleOf(a)]! - _lifecycleOrder[prLifecycleOf(b)]!;
  if (life != 0) return life;
  final rank = _openRank(a) - _openRank(b);
  if (rank != 0) return rank;
  return (b.number ?? 0) - (a.number ?? 0);
}
```

- [ ] **Step 4: Point `agents_view.dart` at the shared vocabulary**

Delete `enum Tone { ... }` and `String prLifecycle(SessionPrModel pr) { ... }` from
`agents_view.dart`, add these imports:

```dart
import 'package:operator_mobile/core/app_themes/colors/tone.dart';
import 'package:operator_mobile/feature/pull_request/logic/pr_view.dart';
```

and change the one grouping line inside `prLine`:

```dart
    groups.putIfAbsent(prLifecycleOf(pr).name, () => []).add(pr.number!);
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green — including `agents_view_test.dart`, which proves
the board card's PR line text did not change.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port the PR presentation vocabulary"
```

---

### Task 7: GitHub deep links (`githubLink.ts` + `openGitHub.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/pull_request/logic/github_link.dart`
- Create: `packages/mobile/lib/feature/pull_request/logic/open_github.dart`
- Test: `packages/mobile/test/feature/pull_request/logic/github_link_test.dart`

**Interfaces:**
- Consumes: `url_launcher` (Task 1).
- Produces:
  - `String? githubAppUrl(String url)`
  - `Future<void> openGitHub(String url)`

The split mirrors RN's: `githubAppUrl` is pure and fully tested; `openGitHub` is the thin
`url_launcher` half, matching how `pushStatus.ts` pairs with `push.ts`. A private repo opened in
the phone's browser shows a login wall, so the app is preferred — but the `github://` scheme is
undocumented, so only the three stable shapes are translated and everything else returns null,
meaning "use the browser".

RN hand-rolls the parse because React Native's `URL` polyfill is incomplete. Dart's `Uri` is
complete, but the port keeps the regex anyway for one reason the tests pin: `Uri.parse` accepts
`notgithub.com` into `host` and a naive `host.endsWith('github.com')` check would match it.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/pull_request/logic/github_link_test.dart` (ported from
`githubLink.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/pull_request/logic/github_link.dart';

void main() {
  group('githubAppUrl', () {
    test('maps a repo URL', () {
      expect(githubAppUrl('https://github.com/OmarAly92/operator'), 'github://repo/OmarAly92/operator');
    });

    test('maps a pull request URL', () {
      expect(githubAppUrl('https://github.com/o/r/pull/184'), 'github://repo/o/r/pull/184');
    });

    test('maps an issue URL', () {
      expect(githubAppUrl('https://github.com/o/r/issues/12'), 'github://repo/o/r/issues/12');
    });

    test('tolerates www, http, trailing slashes and query strings', () {
      expect(githubAppUrl('http://www.github.com/o/r/'), 'github://repo/o/r');
      expect(githubAppUrl('https://github.com/o/r/pull/9?diff=split'), 'github://repo/o/r/pull/9');
      expect(githubAppUrl('  https://github.com/o/r  '), 'github://repo/o/r');
    });

    test('refuses the prefilled new-issue URL', () {
      expect(githubAppUrl('https://github.com/OmarAly92/operator/issues/new?body=hello'), isNull);
      expect(githubAppUrl('https://github.com/o/r/issues/new'), isNull);
    });

    test('refuses non-github hosts', () {
      expect(githubAppUrl('https://gitlab.com/o/r'), isNull);
      expect(githubAppUrl('https://example.com/github.com/o/r'), isNull);
      expect(githubAppUrl('https://notgithub.com/o/r'), isNull);
    });

    test('refuses paths with no repo', () {
      expect(githubAppUrl('https://github.com/'), isNull);
      expect(githubAppUrl('https://github.com/onlyowner'), isNull);
    });

    test('refuses reserved roots that look like owners', () {
      expect(githubAppUrl('https://github.com/settings/profile'), isNull);
      expect(githubAppUrl('https://github.com/orgs/acme'), isNull);
    });

    test('refuses deep paths the app has no stable screen for', () {
      expect(githubAppUrl('https://github.com/o/r/blob/main/README.md'), isNull);
      expect(githubAppUrl('https://github.com/o/r/pull/184/files'), isNull);
      expect(githubAppUrl('https://github.com/o/r/pull/abc'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/pull_request/logic/github_link_test.dart`
Expected: FAIL — `github_link.dart` does not exist.

- [ ] **Step 3: Write the implementations**

`packages/mobile/lib/feature/pull_request/logic/github_link.dart`:

```dart
final RegExp _githubUrl = RegExp(r'^https?://(?:www\.)?github\.com(/[^?#]*)?', caseSensitive: false);
final RegExp _numeric = RegExp(r'^\d+$');

const Set<String> _reservedRoots = {
  'settings', 'orgs', 'organizations', 'notifications', 'explore', 'marketplace', 'pulls',
  'issues', 'search', 'login', 'join', 'about', 'features', 'sponsors', 'apps', 'topics',
  'collections', 'trending', 'new', 'codespaces',
};

List<String>? _segments(String url) {
  final match = _githubUrl.firstMatch(url.trim());
  if (match == null) return null;
  return (match.group(1) ?? '').split('/').where((s) => s.isNotEmpty).toList();
}

String? githubAppUrl(String url) {
  final segments = _segments(url);
  if (segments == null || segments.length < 2) return null;
  final owner = segments.first;
  final repo = segments[1];
  final rest = segments.sublist(2);
  if (owner.startsWith('_') || _reservedRoots.contains(owner.toLowerCase())) return null;
  final base = 'github://repo/$owner/$repo';
  if (rest.isEmpty) return base;
  if (rest.length == 2 && (rest.first == 'pull' || rest.first == 'issues') && _numeric.hasMatch(rest[1])) {
    return '$base/${rest.first}/${rest[1]}';
  }
  return null;
}
```

`packages/mobile/lib/feature/pull_request/logic/open_github.dart`:

```dart
import 'package:operator_mobile/feature/pull_request/logic/github_link.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openGitHub(String url) async {
  final appUrl = githubAppUrl(url);
  if (appUrl != null) {
    try {
      final appUri = Uri.parse(appUrl);
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri);
        return;
      }
    } catch (_) {
      // Falls through to the browser.
    }
  }
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    // Every failure path already reduces to "nothing opened", as in RN.
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port GitHub deep linking"
```

---

### Task 8: The rich PR summary — model, data source, repository

**Files:**
- Create: `packages/mobile/lib/feature/pull_request/data/model/session_pr_summary_model.dart`
- Create: `packages/mobile/lib/feature/pull_request/data/data_source/pull_request_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/pull_request/data/repository/pull_request_repository.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Test: `packages/mobile/test/feature/pull_request/data/data_source/pull_request_remote_data_source_test.dart`
- Test: `packages/mobile/test/feature/pull_request/data/repository/pull_request_repository_test.dart`

**Interfaces:**
- Consumes: `ApiConsumer`, `NetworkStatus`, `GlobalResponse`, `Result` (M0); `mergeReasonLabel`,
  `PrStatusAtom`, `Tone` (Task 6).
- Produces:
  - `class SessionPrSummaryModel extends Equatable` — `url, htmlUrl, number, title, state, repo,
    author, sourceBranch, targetBranch, additions, deletions, changedFiles, ciState, failingChecks
    (List<String>), reviewDecision, hasUnresolvedHumanComments, mergeabilityState, mergeReasons
    (List<String>), updatedAt`; `SessionPrSummaryModel.fromJson(Map<String, dynamic>)`
  - `List<PrStatusAtom> prStatusAtoms(SessionPrSummaryModel rich)` and
    `String? prBlockerLine(SessionPrSummaryModel rich, {int max = 2})` — appended to
    `pr_view.dart`, since they are the same vocabulary read off the richer shape
  - `PullRequestRemoteDataSource.getSessionPr(String sessionId) → Future<GlobalResponse<List<SessionPrSummaryModel>>>`
  - `PullRequestRemoteDataSource.merge(int number) → Future<void>`
  - `PullRequestRepository.getSessionPr(...)` / `.merge(...)` returning `FutureResult<...>`
  - `EndPoints.prMerge(int number)`

RN's `SessionPRSummary` nests `ci`, `review` and `mergeability` objects. This flattens them into
scalar fields plus two string lists, matching how M1's `SessionPrModel` already flattened
`mergeability` into a bool: nothing downstream reads the nesting, and the two lists
(`failingChecks` names, `mergeReasons`) are all `prBlockerLine` needs.

`state` is kept as the raw wire string (`draft|open|merged|closed`); the card maps it through
`prLifecycleFromName` (Task 6), never `PrLifecycle.values.byName`, which throws on an unknown
value.

- [ ] **Step 1: Write the failing data-source test**

`packages/mobile/test/feature/pull_request/data/data_source/pull_request_remote_data_source_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/pull_request/data/data_source/pull_request_remote_data_source.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

void main() {
  late _MockApiConsumer apiConsumer;
  late PullRequestRemoteDataSource dataSource;

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = PullRequestRemoteDataSourceImp(apiConsumer);
  });

  Response<dynamic> jsonResponse(Map<String, dynamic> body) =>
      Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: body);

  test('parses the rich summary the card renders', () async {
    when(() => apiConsumer.get(EndPoints.sessionPr('s1'))).thenAnswer(
      (_) async => jsonResponse({
        'prs': [
          {
            'number': 184,
            'title': 'Fix auth timeouts',
            'state': 'open',
            'repo': 'o/r',
            'author': 'omar',
            'htmlUrl': 'https://github.com/o/r/pull/184',
            'sourceBranch': 'fix/auth',
            'targetBranch': 'main',
            'additions': 12,
            'deletions': 3,
            'changedFiles': 2,
            'ci': {
              'state': 'failing',
              'failingChecks': [{'name': 'go test'}, {'name': 'lint'}],
            },
            'review': {'decision': 'changes_requested', 'hasUnresolvedHumanComments': true},
            'mergeability': {'state': 'conflicting', 'reasons': ['behind_base']},
          },
        ],
      }),
    );

    final summaries = (await dataSource.getSessionPr('s1')).data!;
    final pr = summaries.single;

    expect(pr.number, 184);
    expect(pr.title, 'Fix auth timeouts');
    expect(pr.repo, 'o/r');
    expect(pr.changedFiles, 2);
    expect(pr.ciState, 'failing');
    expect(pr.failingChecks, ['go test', 'lint']);
    expect(pr.reviewDecision, 'changes_requested');
    expect(pr.hasUnresolvedHumanComments, isTrue);
    expect(pr.mergeabilityState, 'conflicting');
    expect(pr.mergeReasons, ['behind_base']);
  });

  test('tolerates a session with no PRs and missing nested objects', () async {
    when(() => apiConsumer.get(EndPoints.sessionPr('s1')))
        .thenAnswer((_) async => jsonResponse({'prs': <dynamic>[]}));
    expect((await dataSource.getSessionPr('s1')).data, isEmpty);

    when(() => apiConsumer.get(EndPoints.sessionPr('s2')))
        .thenAnswer((_) async => jsonResponse({'prs': [{'number': 7}]}));
    final pr = (await dataSource.getSessionPr('s2')).data!.single;
    expect(pr.ciState, isNull);
    expect(pr.failingChecks, isEmpty);
    expect(pr.mergeReasons, isEmpty);
  });

  test('posts a merge for the PR number', () async {
    when(() => apiConsumer.post(any())).thenAnswer(
      (_) async => Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: null),
    );

    await dataSource.merge(184);

    verify(() => apiConsumer.post(EndPoints.prMerge(184))).called(1);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/pull_request/data/`
Expected: FAIL — the data source does not exist.

- [ ] **Step 3: Add the endpoint**

In `end_points.dart`:

```dart
  static String prMerge(int number) => '/api/v1/prs/$number/merge';
```

- [ ] **Step 4: Write the model**

`packages/mobile/lib/feature/pull_request/data/model/session_pr_summary_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class SessionPrSummaryModel extends Equatable {
  const SessionPrSummaryModel({
    this.url,
    this.htmlUrl,
    this.number,
    this.title,
    this.state,
    this.repo,
    this.author,
    this.sourceBranch,
    this.targetBranch,
    this.additions,
    this.deletions,
    this.changedFiles,
    this.ciState,
    this.failingChecks = const [],
    this.reviewDecision,
    this.hasUnresolvedHumanComments,
    this.mergeabilityState,
    this.mergeReasons = const [],
    this.updatedAt,
  });

  final String? url;
  final String? htmlUrl;
  final int? number;
  final String? title;
  final String? state;
  final String? repo;
  final String? author;
  final String? sourceBranch;
  final String? targetBranch;
  final int? additions;
  final int? deletions;
  final int? changedFiles;
  final String? ciState;
  final List<String> failingChecks;
  final String? reviewDecision;
  final bool? hasUnresolvedHumanComments;
  final String? mergeabilityState;
  final List<String> mergeReasons;
  final String? updatedAt;

  factory SessionPrSummaryModel.fromJson(Map<String, dynamic> json) {
    final ci = json['ci'] as Map<String, dynamic>?;
    final review = json['review'] as Map<String, dynamic>?;
    final mergeability = json['mergeability'] as Map<String, dynamic>?;
    return SessionPrSummaryModel(
      url: json['url'] as String?,
      htmlUrl: json['htmlUrl'] as String?,
      number: json['number'] as int?,
      title: json['title'] as String?,
      state: json['state'] as String?,
      repo: json['repo'] as String?,
      author: json['author'] as String?,
      sourceBranch: json['sourceBranch'] as String?,
      targetBranch: json['targetBranch'] as String?,
      additions: json['additions'] as int?,
      deletions: json['deletions'] as int?,
      changedFiles: json['changedFiles'] as int?,
      ciState: ci?['state'] as String?,
      failingChecks: (ci?['failingChecks'] as List<dynamic>? ?? const [])
          .map((c) => (c as Map<String, dynamic>)['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList(),
      reviewDecision: review?['decision'] as String?,
      hasUnresolvedHumanComments: review?['hasUnresolvedHumanComments'] as bool?,
      mergeabilityState: mergeability?['state'] as String?,
      mergeReasons: (mergeability?['reasons'] as List<dynamic>? ?? const []).cast<String>(),
      updatedAt: json['updatedAt'] as String?,
    );
  }

  @override
  List<Object?> get props => [
    url, htmlUrl, number, title, state, repo, author, sourceBranch, targetBranch, additions,
    deletions, changedFiles, ciState, failingChecks, reviewDecision, hasUnresolvedHumanComments,
    mergeabilityState, mergeReasons, updatedAt,
  ];
}
```

- [ ] **Step 5: Write the data source and repository**

`packages/mobile/lib/feature/pull_request/data/data_source/pull_request_remote_data_source.dart`:

```dart
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';

abstract class PullRequestRemoteDataSource {
  Future<GlobalResponse<List<SessionPrSummaryModel>>> getSessionPr(String sessionId);
  Future<void> merge(int number);
}

class PullRequestRemoteDataSourceImp implements PullRequestRemoteDataSource {
  PullRequestRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<List<SessionPrSummaryModel>>> getSessionPr(String sessionId) async {
    final response = await _apiConsumer.get(EndPoints.sessionPr(sessionId));
    return GlobalResponse<List<SessionPrSummaryModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => (json['prs'] as List<dynamic>? ?? const [])
          .map((pr) => SessionPrSummaryModel.fromJson(pr as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<void> merge(int number) async {
    await _apiConsumer.post(EndPoints.prMerge(number));
  }
}
```

`packages/mobile/lib/feature/pull_request/data/repository/pull_request_repository.dart` — the same
`NetworkStatus`-gated shape as `SessionsRepositoryImp`, with `getSessionPr` returning
`FutureResult<GlobalResponse<List<SessionPrSummaryModel>>>` and `merge` returning
`FutureResult<bool>`, both short-circuiting to `ServerFailure.noNetwork()` when offline. Mirror
`sessions_repository_test.dart`'s three cases (success, `Failure` bubbling, offline) in
`pull_request_repository_test.dart`.

- [ ] **Step 6: Append the rich-summary readers to `pr_view.dart`**

```dart
List<PrStatusAtom> prStatusAtoms(SessionPrSummaryModel rich) {
  if (rich.state == 'merged') return const [PrStatusAtom(text: 'Merged', tone: Tone.success)];
  if (rich.state == 'closed') return const [PrStatusAtom(text: 'Closed', tone: Tone.passive)];

  final atoms = <PrStatusAtom>[];

  switch (rich.ciState) {
    case 'passing':
      atoms.add(const PrStatusAtom(text: 'CI passing', tone: Tone.success));
    case 'failing':
      atoms.add(const PrStatusAtom(text: 'CI failing', tone: Tone.error));
    case 'pending':
      atoms.add(const PrStatusAtom(text: 'CI running', tone: Tone.neutral));
  }

  switch (rich.mergeabilityState) {
    case 'mergeable':
      atoms.add(const PrStatusAtom(text: 'Mergeable', tone: Tone.success));
    case 'conflicting':
      atoms.add(const PrStatusAtom(text: 'Conflict', tone: Tone.error));
    case 'blocked':
      atoms.add(const PrStatusAtom(text: 'Blocked', tone: Tone.warning));
    case 'unstable':
      atoms.add(const PrStatusAtom(text: 'Unstable', tone: Tone.warning));
  }

  switch (rich.reviewDecision) {
    case 'approved':
      atoms.add(const PrStatusAtom(text: 'Approved', tone: Tone.success));
    case 'changes_requested':
      atoms.add(const PrStatusAtom(text: 'Changes requested', tone: Tone.warning));
    case 'review_required':
      atoms.add(const PrStatusAtom(text: 'Review pending', tone: Tone.neutral));
    default:
      if (rich.hasUnresolvedHumanComments == true) {
        atoms.add(const PrStatusAtom(text: 'Unresolved comments', tone: Tone.warning));
      }
  }

  return atoms;
}

String? prBlockerLine(SessionPrSummaryModel rich, {int max = 2}) {
  final names = [...rich.failingChecks, ...rich.mergeReasons.map(mergeReasonLabel)];
  if (names.isEmpty) return null;
  final shown = names.take(max).toList();
  final extra = names.length - shown.length;
  return extra > 0 ? '${shown.join(' · ')} +$extra more' : shown.join(' · ');
}
```

Add the `SessionPrSummaryModel` import to `pr_view.dart`.

- [ ] **Step 7: Add the rich-summary cases to `pr_view_test.dart`**

```dart
  group('prStatusAtoms', () {
    SessionPrSummaryModel rich({
      String? state = 'open',
      String? ci,
      String? merge,
      String? review,
      bool? unresolved,
    }) => SessionPrSummaryModel(
      state: state,
      ciState: ci,
      mergeabilityState: merge,
      reviewDecision: review,
      hasUnresolvedHumanComments: unresolved,
    );

    test('collapses a decided PR to one atom', () {
      expect(prStatusAtoms(rich(state: 'merged', ci: 'passing')),
          const [PrStatusAtom(text: 'Merged', tone: Tone.success)]);
      expect(prStatusAtoms(rich(state: 'closed')),
          const [PrStatusAtom(text: 'Closed', tone: Tone.passive)]);
    });

    test('reports CI, merge and review in that order', () {
      final atoms = prStatusAtoms(rich(ci: 'passing', merge: 'mergeable', review: 'approved'));
      expect(atoms.map((a) => a.text), ['CI passing', 'Mergeable', 'Approved']);
    });

    test('omits anything the daemon has not determined', () {
      expect(prStatusAtoms(rich(ci: 'unknown', merge: 'unknown')), isEmpty);
      expect(prStatusAtoms(rich()), isEmpty);
    });

    test('colours failures and blockers correctly', () {
      final atoms = prStatusAtoms(rich(ci: 'failing', merge: 'conflicting', review: 'changes_requested'));
      expect(atoms.map((a) => a.tone), [Tone.error, Tone.error, Tone.warning]);
    });

    test('surfaces unresolved comments when there is no formal decision', () {
      expect(prStatusAtoms(rich(review: 'none', unresolved: true)),
          const [PrStatusAtom(text: 'Unresolved comments', tone: Tone.warning)]);
    });
  });

  group('prBlockerLine', () {
    test('names failing checks and merge reasons together', () {
      expect(
        prBlockerLine(const SessionPrSummaryModel(
          failingChecks: ['go test'],
          mergeReasons: ['behind_base'],
        )),
        'go test · branch behind base',
      );
    });

    test('caps the list and counts the remainder rather than truncating silently', () {
      expect(
        prBlockerLine(const SessionPrSummaryModel(failingChecks: ['a', 'b', 'c', 'd'])),
        'a · b +2 more',
      );
    });

    test('returns nothing when there is nothing blocking', () {
      expect(prBlockerLine(const SessionPrSummaryModel()), isNull);
    });
  });
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 9: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the rich PR summary data layer"
```

---

### Task 9: `PullRequestCubit` — lazily cached summaries

**Files:**
- Create: `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart`
- Create: `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_state.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Test: `packages/mobile/test/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit_test.dart`

**Interfaces:**
- Consumes: `PullRequestRepository` (Task 8).
- Produces:
  - `enum PrFilter { open, merged, all }`
  - `sealed class PullRequestState extends Equatable` with `PullRequestInitialState`,
    `PullRequestReadyState(int revision)`
  - `class PullRequestCubit extends Cubit<PullRequestState>`:
    - `SessionPrSummaryModel? summaryFor(String sessionId, int number)`
    - `Future<void> load(List<String> sessionIds)`
    - `Future<void> reload(List<String> sessionIds)`
    - `PrFilter filter` and `void setFilter(PrFilter next)`
  - `_pullRequestFeatureSetup()` in `ServiceLocator`

This is `usePRSummaries.ts` as a cubit. The behavior that must survive:

- **Fetched once per session, not every poll tick.** The board polls every 8s; re-fetching N PR
  summaries each tick is a real battery and latency cost over Tailscale for data that changes on
  the order of minutes. `load` skips any session already cached or already in flight.
- **`reload` forces a re-fetch**, and is the only thing that does — it is wired to pull-to-refresh.
- **A failed fetch keeps what is on screen.** On error the entry is seeded to an empty list only if
  nothing was cached: blanking cards back to their thin fallback because one request timed out is
  worse than detail that is a few seconds stale.
- **Batched six at a time**, so a screenful loads quickly without opening thirty sockets at once.

`PullRequestReadyState` carries a monotonic `revision` in `props` for the same reason
`GetSessionsSuccessState` does after M1's final fix wave: `BlocBase.emit` drops an equal state, so a
props-less state would silently swallow every repaint after the first.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';
import 'package:operator_mobile/feature/pull_request/data/repository/pull_request_repository.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart';

class _MockPullRequestRepository extends Mock implements PullRequestRepository {}

void main() {
  late _MockPullRequestRepository repository;

  SessionPrSummaryModel summary(int number, String title) =>
      SessionPrSummaryModel(number: number, title: title);

  void stub(String sessionId, List<SessionPrSummaryModel> prs) {
    when(() => repository.getSessionPr(sessionId))
        .thenAnswer((_) async => Result.success(GlobalResponse(data: prs)));
  }

  setUp(() {
    repository = _MockPullRequestRepository();
  });

  test('exposes a loaded summary by session and number', () async {
    stub('s1', [summary(184, 'Fix auth')]);
    final cubit = PullRequestCubit(repository);

    await cubit.load(['s1']);

    expect(cubit.summaryFor('s1', 184)?.title, 'Fix auth');
    expect(cubit.summaryFor('s1', 999), isNull);
    expect(cubit.summaryFor('other', 184), isNull);
    await cubit.close();
  });

  test('fetches each session once across repeated loads', () async {
    stub('s1', [summary(1, 'one')]);
    final cubit = PullRequestCubit(repository);

    await cubit.load(['s1']);
    await cubit.load(['s1']);
    await cubit.load(['s1']);

    verify(() => repository.getSessionPr('s1')).called(1);
    await cubit.close();
  });

  test('reload re-fetches everything', () async {
    stub('s1', [summary(1, 'one')]);
    final cubit = PullRequestCubit(repository);

    await cubit.load(['s1']);
    await cubit.reload(['s1']);

    verify(() => repository.getSessionPr('s1')).called(2);
    await cubit.close();
  });

  test('only fetches sessions it has never seen', () async {
    stub('s1', [summary(1, 'one')]);
    stub('s2', [summary(2, 'two')]);
    final cubit = PullRequestCubit(repository);

    await cubit.load(['s1']);
    await cubit.load(['s1', 's2']);

    verify(() => repository.getSessionPr('s1')).called(1);
    verify(() => repository.getSessionPr('s2')).called(1);
    await cubit.close();
  });

  test('keeps the detail already on screen when a refresh fails', () async {
    stub('s1', [summary(184, 'Fix auth')]);
    final cubit = PullRequestCubit(repository);
    await cubit.load(['s1']);

    when(() => repository.getSessionPr('s1'))
        .thenAnswer((_) async => Result.failure(ServerFailure(error: 'boom', message: 'boom')));
    await cubit.reload(['s1']);

    expect(cubit.summaryFor('s1', 184)?.title, 'Fix auth');
    await cubit.close();
  });

  blocTest<PullRequestCubit, PullRequestState>(
    'emits a distinct state per loaded batch so the list repaints',
    build: () {
      stub('s1', [summary(1, 'one')]);
      return PullRequestCubit(repository);
    },
    act: (cubit) => cubit.load(['s1']),
    expect: () => [isA<PullRequestReadyState>().having((s) => s.revision, 'revision', 1)],
  );

  blocTest<PullRequestCubit, PullRequestState>(
    'emits when the filter changes',
    build: () => PullRequestCubit(repository),
    act: (cubit) => cubit.setFilter(PrFilter.merged),
    expect: () => [isA<PullRequestReadyState>().having((s) => s.revision, 'revision', 1)],
    verify: (cubit) => expect(cubit.filter, PrFilter.merged),
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/pull_request/presentation/`
Expected: FAIL — the cubit does not exist.

- [ ] **Step 3: Write the state and cubit**

`pull_request_state.dart`:

```dart
part of 'pull_request_cubit.dart';

sealed class PullRequestState extends Equatable {
  const PullRequestState();

  @override
  List<Object?> get props => [];
}

final class PullRequestInitialState extends PullRequestState {
  const PullRequestInitialState();
}

final class PullRequestReadyState extends PullRequestState {
  const PullRequestReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
```

`pull_request_cubit.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';
import 'package:operator_mobile/feature/pull_request/data/repository/pull_request_repository.dart';

part 'pull_request_state.dart';

enum PrFilter { open, merged, all }

class PullRequestCubit extends Cubit<PullRequestState> {
  PullRequestCubit(this._repository) : super(const PullRequestInitialState());

  static const int _batchSize = 6;

  final PullRequestRepository _repository;
  final Map<String, List<SessionPrSummaryModel>> _cache = {};
  final Set<String> _inFlight = {};
  int _revision = 0;

  PrFilter filter = PrFilter.open;

  void setFilter(PrFilter next) {
    if (next == filter) return;
    filter = next;
    _bump();
  }

  SessionPrSummaryModel? summaryFor(String sessionId, int number) {
    for (final summary in _cache[sessionId] ?? const <SessionPrSummaryModel>[]) {
      if (summary.number == number) return summary;
    }
    return null;
  }

  Future<void> reload(List<String> sessionIds) => _fetch(sessionIds, force: true);

  Future<void> load(List<String> sessionIds) => _fetch(sessionIds, force: false);

  Future<void> _fetch(List<String> sessionIds, {required bool force}) async {
    final targets = sessionIds
        .where((id) => id.isNotEmpty && !_inFlight.contains(id) && (force || !_cache.containsKey(id)))
        .toSet()
        .toList();
    if (targets.isEmpty) return;
    _inFlight.addAll(targets);

    for (var start = 0; start < targets.length; start += _batchSize) {
      final chunk = targets.skip(start).take(_batchSize).toList();
      await Future.wait(chunk.map(_fetchOne));
      if (isClosed) return;
      _bump();
    }
  }

  Future<void> _fetchOne(String sessionId) async {
    final result = await _repository.getSessionPr(sessionId);
    result.when(
      onSuccess: (response) => _cache[sessionId] = response.data ?? const [],
      onFailure: (_) => _cache.putIfAbsent(sessionId, () => const []),
    );
    _inFlight.remove(sessionId);
  }

  void _bump() => emit(PullRequestReadyState(++_revision));
}
```

- [ ] **Step 4: Register the feature**

In `service_locator.dart`, add `_pullRequestFeatureSetup();` to `init()` and:

```dart
  static void _pullRequestFeatureSetup() {
    sl.registerFactory<PullRequestCubit>(() => PullRequestCubit(sl<PullRequestRepository>()));

    sl.registerLazySingleton<PullRequestRepository>(
      () => PullRequestRepositoryImp(sl<PullRequestRemoteDataSource>(), sl<NetworkStatus>()),
    );
    sl.registerLazySingleton<PullRequestRemoteDataSource>(
      () => PullRequestRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }
```

Extend `test/core/utils/service_locator_test.dart` to assert `PullRequestCubit` and
`PullRequestRepository` resolve.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add PullRequestCubit with lazily cached summaries"
```

---

### Task 10: The PRs tab

**Files:**
- Create: `packages/mobile/lib/core/widgets/pickers/project_picker_sheet.dart`
- Create: `packages/mobile/lib/core/widgets/main_widgets/app_pill.dart`
- Create: `packages/mobile/lib/core/widgets/main_widgets/app_empty_state.dart`
- Create: `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_screen.dart`
- Create: `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pull_requests_body.dart`
- Create: `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pr_card.dart`
- Create: `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/project_switcher.dart`
- Modify: `packages/mobile/lib/core/app_routes/home_shell.dart`
- Test: `packages/mobile/test/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_body_test.dart`
- Test: `packages/mobile/test/feature/pull_request/presentation/pull_requests_screen/ui/pr_card_test.dart`

**Interfaces:**
- Consumes: `SessionsCubit` (Task 4), `PullRequestCubit` (Task 9), `collectPrs`/`comparePrs`/
  `prLifecycleOf`/`prTitle`/`prStatusAtoms`/`prSummaryLine`/`prBlockerLine`/`stateVisualOf`
  (Tasks 6, 8), `openGitHub` (Task 7), `shortLabel`/`toneColor` (Task 2).
- Produces:
  - `Future<String?> showProjectPickerSheet(BuildContext context, {required List<ProjectModel> projects, required String selected, bool includeAll = true, String title = 'Active project', String subtitle = 'Scopes the Agents and PRs tabs.'})`
  - `class AppPill extends StatelessWidget` — `label`, `active`, `onTap`
  - `class AppEmptyState extends StatelessWidget` — `icon`, `title`, `message`, `action`
  - `class PullRequestsScreen`, `PullRequestsBody`, `PrCard`, `ProjectSwitcher`

The picker sheet returns `Future<String?>` — `null` when dismissed — rather than taking an
`onSelect` callback. It lives in `core/widgets/pickers/` because three features open it (PRs tab's
switcher, Settings' active-project row, Spawn's project row), and none of them owns it.

`ProjectSwitcher` renders nothing when there are fewer than two projects: a single-project user
has nothing to switch between, exactly as RN's early return does.

The card renders from the thin board facts first and **appends** the rich lines when they arrive,
so it is never blank and never jumps between two layouts. The "Open session" action RN's card
carries is omitted — see "What M2 deliberately does not include".

- [ ] **Step 1: Write the failing tests**

`packages/mobile/test/feature/pull_request/presentation/pull_requests_screen/ui/pr_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pr_card.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, {SessionPrSummaryModel? summary}) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: Scaffold(
              body: PrCard(
                pr: const SessionPrModel(number: 184, state: 'open', ci: 'failing'),
                session: const SessionModel(
                  id: 's1',
                  projectId: 'my-app_98d163a851',
                  displayName: 'Fix auth timeouts',
                ),
                summary: summary,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders from the thin board facts before the summary arrives', (tester) async {
    await pumpCard(tester);

    expect(find.text('#184'), findsOneWidget);
    expect(find.text('Fix auth timeouts'), findsOneWidget);
    expect(find.text('CI failing'), findsOneWidget);
  });

  testWidgets('middle-truncates a long project id so two projects stay distinguishable', (tester) async {
    await pumpCard(tester);

    expect(find.text('my-app_98d163a851'), findsNothing);
    expect(find.textContaining('…'), findsWidgets);
  });

  testWidgets('appends the rich lines once the summary lands', (tester) async {
    await pumpCard(
      tester,
      summary: const SessionPrSummaryModel(
        number: 184,
        title: 'Fix auth timeouts on refresh',
        state: 'open',
        repo: 'o/r',
        author: 'omar',
        sourceBranch: 'fix/auth',
        targetBranch: 'main',
        additions: 12,
        deletions: 3,
        changedFiles: 2,
        ciState: 'failing',
        failingChecks: ['go test'],
        mergeabilityState: 'conflicting',
        mergeReasons: ['behind_base'],
      ),
    );

    expect(find.text('Fix auth timeouts on refresh'), findsOneWidget);
    expect(find.text('fix/auth → main · omar'), findsOneWidget);
    expect(find.text('2 files'), findsOneWidget);
    expect(find.text('+12'), findsOneWidget);
    expect(find.text('−3'), findsOneWidget);
    expect(find.text('go test · branch behind base'), findsOneWidget);
  });

  testWidgets('offers no session action, because no session screen exists yet', (tester) async {
    await pumpCard(tester);

    expect(find.byTooltip('Open session'), findsNothing);
    expect(find.byTooltip('Open in GitHub'), findsOneWidget);
  });
}
```

`packages/mobile/test/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_body_test.dart`
follows `sessions_body_test.dart`'s established shape: a real `SessionsCubit` and a real
`PullRequestCubit` over mocked repositories, inside nested `BlocProvider`s under `SkinScope` +
`ScreenUtilInit` + `MaterialApp`. Cover:

- a session carrying an open PR renders one card, and the "Open 1" pill reads that count;
- tapping the "Merged" pill hides the open PR and shows a merged one;
- with two projects and the active project set to the second, only that project's PR is listed;
- with no PRs at all, the empty state reads "No pull requests";
- with the board in `GetSessionsFailureState` and nothing cached, the connection-failure copy
  from `describeConnectionFailure` is shown instead of the empty state.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/feature/pull_request/presentation/pull_requests_screen/ui/`
Expected: FAIL — the widgets do not exist.

- [ ] **Step 3: Write the shared widgets**

`app_pill.dart` — a rounded, tappable label using `skin.tintBlue`/`skin.blue` when `active`, and
`skin.bgElevated`/`skin.textTertiary` otherwise, text `AppTextStyle.style12SemiBold`.

`app_empty_state.dart` — a centred column: `Icon(icon, size: 30, color: skin.textFaint)`, the title
in `AppTextStyle.style15SemiBold`, the message in `AppTextStyle.style13Regular` coloured
`skin.textTertiary` with `maxLines: 4` and `textAlign: TextAlign.center`, and an optional `action`
widget below.

`project_picker_sheet.dart`:

```dart
Future<String?> showProjectPickerSheet(
  BuildContext context, {
  required List<ProjectModel> projects,
  required String selected,
  bool includeAll = true,
  String title = 'Active project',
  String subtitle = 'Scopes the Agents and PRs tabs.',
}) {
  final skin = context.skin;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: skin.bgSurface,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          AppText(title, style: AppTextStyle.style17SemiBold),
          const VerticalSpace(4),
          AppText(subtitle, style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary), maxLines: 2),
          const VerticalSpace(8),
          if (includeAll)
            _ProjectOption(
              label: 'All projects',
              icon: Icons.layers_outlined,
              selected: selected == kAllProjects,
              onTap: () => Navigator.of(sheetContext).pop(kAllProjects),
            ),
          for (final project in projects)
            _ProjectOption(
              label: project.name ?? project.id ?? '',
              hint: project.sessionPrefix,
              icon: Icons.folder_outlined,
              selected: selected == project.id,
              onTap: () => Navigator.of(sheetContext).pop(project.id),
            ),
          if (projects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: AppText(
                'No projects yet. Add one from the Operator dashboard on your computer.',
                style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
                maxLines: 3,
              ),
            ),
        ],
      ),
    ),
  );
}
```

with a private `_ProjectOption` row: leading icon tinted `skin.blue` when selected, label
`AppTextStyle.style15Medium`, optional monospace `hint`, and a trailing check when selected.

- [ ] **Step 4: Write the switcher**

`project_switcher.dart` — reads `SessionsCubit`, returns `const SizedBox.shrink()` when
`cubit.projects.length <= 1`, otherwise a row: `'PROJECTS'` in
`AppTextStyle.style13Bold.copyWith(color: skin.textSecondary, letterSpacing: 0.8)`, and a tappable
trigger showing the active project's name (or `'All projects'`) with a chevron. On tap it awaits
`showProjectPickerSheet(...)` and, when the result is non-null and `context.mounted`, calls
`cubit.setActiveProject(result)`. No navigation follows — the list is already on screen, so the
filter applying in place is the whole feedback.

- [ ] **Step 5: Write the card**

`pr_card.dart` — an `AppContainer` with `margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4)`
and `padding: const EdgeInsets.all(12)`.

The lifecycle badge reads from the rich summary when it has arrived and from the board facts
otherwise — the rich summary reports `draft` as a state of its own, while the board facts fold it
into `open` and leave `prLifecycleOf` to recover it:

```dart
    final state = summary != null
        ? stateVisualOf(skin, prLifecycleFromName(summary.state))
        : prStateVisual(skin, pr);
```

Laid out as:

1. an identity row — a `Icons.merge_outlined` glyph tinted `state.color`, `'#${pr.number}'` in
   `AppTextStyle.mono12Bold`, the lifecycle `state.label.name` in
   `AppTextStyle.style12SemiBold.copyWith(color: state.color)`, a spacer, then
   `shortLabel(summary?.repo ?? session.projectId ?? '')` in `AppTextStyle.mono11Regular`;
2. the title — `summary?.title?.trim()` when non-empty, else `prTitle(pr, sessionTitle(session))`,
   `AppTextStyle.style15Medium`, `maxLines: 2`;
3. the meta line, only with a summary — `[sourceBranch, targetBranch].join(' → ')` and `author`
   joined by `' · '`, in `AppTextStyle.mono11Regular` coloured `skin.textTertiary`;
4. the diff row, only when the summary reports any of `changedFiles`/`additions`/`deletions` above
   zero — `'$changedFiles file'`/`'files'`, `'+$additions'` in `skin.green`, `'−$deletions'` in
   `skin.red` (a U+2212 minus, matching RN);
5. a footer row — the atoms (`summary != null ? prStatusAtoms(summary) : [prSummaryLine(pr)]`)
   wrapped and separated by a `'·'`, each coloured `toneColor(skin, atom.tone)`, then an
   `IconButton(icon: Icon(Icons.open_in_new), tooltip: 'Open in GitHub')` calling
   `openGitHub(summary?.htmlUrl ?? summary?.url ?? pr.url ?? '')`;
6. the blocker line when `summary != null && prBlockerLine(summary) != null`, in
   `AppTextStyle.style11Regular` coloured `skin.textTertiary`, `maxLines: 2`.

- [ ] **Step 6: Write the body and screen**

`pull_requests_body.dart` — a `BlocBuilder<SessionsCubit, SessionsState>` wrapping a
`BlocBuilder<PullRequestCubit, PullRequestState>`. Inside:

```dart
    final entries = collectPrs(sessionsCubit.visibleSessions);
    final filtered = entries.where((e) => _inBucket(prCubit.filter, prLifecycleOf(e.pr))).toList()
      ..sort((a, b) => comparePrs(a.pr, b.pr));
    final sessionIds = {for (final entry in filtered) entry.session.id}.whereType<String>().toList();

    WidgetsBinding.instance.addPostFrameCallback((_) => prCubit.load(sessionIds));
```

The fetch is scheduled **after** the frame, not called inline in `build`. `load` emits once its
first batch resolves, and emitting into a `BlocBuilder` that is still building is exactly the
"setState during build" failure — the post-frame callback is what keeps a repaint from re-entering
the build it was triggered from. `load` is idempotent per session (Task 9), so running it on every
build is cheap: after the first pass every id is cached or in flight and it returns immediately.

with

```dart
bool _inBucket(PrFilter filter, PrLifecycle life) {
  if (filter == PrFilter.all) return true;
  if (filter == PrFilter.open) return life == PrLifecycle.open || life == PrLifecycle.draft;
  return life == PrLifecycle.merged;
}
```

Drafts sit in the Open bucket — they are open PRs even though the card labels them "draft".

Above the list: `ProjectSwitcher`, then a row of three `AppPill`s reading
`'Open ${counts.open}'`, `'Merged ${counts.merged}'`, `'All ${counts.all}'` — counts computed over
**all** `entries`, not the filtered list, so the pills report what switching would reveal. Tapping
one calls `prCubit.setFilter(...)`.

The list is a `RefreshIndicator(onRefresh: ...)` over a `ListView`, where refresh awaits both
`prCubit.reload(sessionIds)` and `sessionsCubit.refresh()`.

Empty states: when `filtered` is empty and the board is in `GetSessionsFailureState` with no
sessions, render `AppEmptyState` with `describeConnectionFailure`'s title and message plus a
"Retry" action; otherwise `AppEmptyState(icon: Icons.merge_outlined, title: 'No pull requests', ...)`.

`pull_requests_screen.dart` — a `Scaffold` with `backgroundColor: context.skin.bgBase`,
`GlobalAppbar.main(titleText: 'Pull Requests')`, and `PullRequestsBody` as its body, wrapped in
`BlocProvider(create: (_) => sl<PullRequestCubit>())`.

- [ ] **Step 7: Mount it in the shell**

In `home_shell.dart`, replace the second placeholder — index 2 — with `PullRequestsScreen()`.
(Index 1 is Orchestrator, landing in Task 14.)

- [ ] **Step 8: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 9: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the PRs tab"
```

---

### Task 11: Chat preflight error classification (`chatError.ts` port)

**Files:**
- Create: `packages/mobile/lib/core/error_handling/chat_preflight.dart`
- Test: `packages/mobile/test/core/error_handling/chat_preflight_test.dart`

**Interfaces:**
- Consumes: `Failure` (M0).
- Produces:
  - `bool isChatPreflightFailure(Failure failure)`
  - `String chatErrorCopy(Failure failure)`

Both orchestrator launch (Task 14) and spawn (Task 18) offer "start as Terminal UI instead" when
the daemon refuses a chat session, and both need the same four codes to decide. M1's
`dio_error_handler` already parks the daemon's `code` on `Failure.apiStatus`, so this reads that
field rather than parsing a message string.

`chatErrorCopy` strips the HTTP envelope prefix RN's regex removes (`409 Conflict - `), preserving
the daemon's useful detail. Against this Flutter client the prefix is usually already absent —
`handleDioError` reads `body['message']` directly — so the strip is defensive and the test pins
both shapes.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/error_handling/chat_preflight_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/chat_preflight.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

void main() {
  Failure failure({String? code, String message = 'nope'}) =>
      ServerFailure(error: message, message: message, apiStatus: code, statusCode: 409);

  group('isChatPreflightFailure', () {
    test('recognises every code that means chat cannot start', () {
      for (final code in [
        'SESSION_MODE_UNSUPPORTED',
        'CHAT_DRIVER_UNAVAILABLE',
        'CHAT_DRIVER_INCOMPATIBLE',
        'CHAT_AUTH_REQUIRED',
      ]) {
        expect(isChatPreflightFailure(failure(code: code)), isTrue, reason: code);
      }
    });

    test('is false for any other failure', () {
      expect(isChatPreflightFailure(failure(code: 'SESSION_AWAITING_DECISION')), isFalse);
      expect(isChatPreflightFailure(failure()), isFalse);
    });
  });

  group('chatErrorCopy', () {
    test('keeps the daemon detail as-is when there is no envelope prefix', () {
      expect(chatErrorCopy(failure(message: 'claude-code cannot run Chat')), 'claude-code cannot run Chat');
    });

    test('strips an HTTP envelope prefix', () {
      expect(chatErrorCopy(failure(message: '409 Conflict - claude-code cannot run Chat')),
          'claude-code cannot run Chat');
    });

    test('never returns blank', () {
      expect(chatErrorCopy(failure(message: '')).isNotEmpty, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/error_handling/chat_preflight_test.dart`
Expected: FAIL — `chat_preflight.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

const Set<String> _chatPreflightCodes = {
  'SESSION_MODE_UNSUPPORTED',
  'CHAT_DRIVER_UNAVAILABLE',
  'CHAT_DRIVER_INCOMPATIBLE',
  'CHAT_AUTH_REQUIRED',
};

final RegExp _httpEnvelope = RegExp(r'^\d+\s+[^-]+\s+-\s+');

bool isChatPreflightFailure(Failure failure) =>
    failure.apiStatus != null && _chatPreflightCodes.contains(failure.apiStatus);

String chatErrorCopy(Failure failure) {
  final stripped = failure.message.replaceFirst(_httpEnvelope, '').trim();
  return stripped.isEmpty ? 'Chat is unavailable for this agent.' : stripped;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port chat preflight error classification"
```

---

### Task 12: Orchestrator presentation logic (`orchestratorView.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/orchestrator/logic/orchestrator_view.dart`
- Modify: `packages/mobile/lib/feature/sessions/logic/agents_view.dart`
- Test: `packages/mobile/test/feature/orchestrator/logic/orchestrator_view_test.dart`

**Interfaces:**
- Consumes: `OrchestratorModel` (Task 2), `SessionModel`, `attentionOf`/`AttentionLevel`,
  `statusVisual` (M1), `AppSkin`.
- Produces:
  - `enum OrchestratorState { missing, stopped, running }`
  - `OrchestratorState orchestratorStateOf(OrchestratorModel? link)`
  - `class OrchestratorStatus` — `label (String)`, `color (Color)`, `breathing (bool)`
  - `OrchestratorStatus orchestratorStatus(AppSkin skin, OrchestratorModel? link)`
  - `class LaunchIntent` — `clean (bool)`, `label (String)`, `confirm (bool)`
  - `LaunchIntent launchIntent(OrchestratorState state)`
  - `Map<AttentionLevel, int> zoneCounts(List<SessionModel> sessions)`
  - `List<SessionModel> workersOf(List<SessionModel> sessions, String projectId, OrchestratorModel? link)`
  - `class AttentionMeta` — `label`, `color`, `tint` — and
    `AttentionMeta attentionMeta(AppSkin skin, AttentionLevel level)`, added to `agents_view.dart`
    beside the existing `zoneMeta`

Two behaviors carry the whole file and both have regressions behind them:

- **`orchestratorStateOf` treats a link as stopped only when explicitly flagged.** The daemon
  derives `hasRuntime` and `isTerminal` from one `isTerminated` boolean; a build that omits them
  must not read as dead, or the tab shows "Start" beside a running orchestrator and offers to
  replace it.
- **`launchIntent` sends `clean: true` only when restarting.** `SpawnOrchestrator` treats
  `clean: false` as an idempotent *ensure* — if an active orchestrator exists it returns that one
  and spawns nothing — so "Restart" on a running orchestrator used to send `clean: false` and
  silently do nothing at all. `clean: true` is destructive (every live orchestrator for the project
  is retired and replaced), which is why it, and only it, sets `confirm`.

`attentionMeta` mirrors `attentionMetaFor(t)` from `lib/theme.ts`. RN's map carries an extra
`action` key aliasing `respond`; `AttentionLevel` has no `action` member, so the Dart switch covers
the six real levels and nothing is lost.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/orchestrator/logic/orchestrator_view_test.dart` (ported from
`orchestratorView.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/feature/orchestrator/logic/orchestrator_view.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';

OrchestratorModel link({String? id = 'proj-orchestrator', bool? hasRuntime, bool? isTerminal, String? status}) =>
    OrchestratorModel(
      id: id,
      projectId: 'proj',
      projectName: 'proj',
      status: status,
      hasRuntime: hasRuntime,
      isTerminal: isTerminal,
    );

SessionModel session({String id = 'proj-1', String projectId = 'proj', String? status}) =>
    SessionModel(id: id, projectId: projectId, status: status);

void main() {
  const dark = DarkSkin();
  const light = LightSkin();

  group('orchestratorStateOf', () {
    test('reports missing when there is no link at all', () {
      expect(orchestratorStateOf(null), OrchestratorState.missing);
      expect(orchestratorStateOf(link(id: '')), OrchestratorState.missing);
      expect(orchestratorStateOf(link(id: null)), OrchestratorState.missing);
    });

    test('reports stopped only when explicitly flagged', () {
      expect(orchestratorStateOf(link(hasRuntime: false)), OrchestratorState.stopped);
      expect(orchestratorStateOf(link(isTerminal: true)), OrchestratorState.stopped);
    });

    test('treats a link with neither flag as running', () {
      expect(orchestratorStateOf(link()), OrchestratorState.running);
    });
  });

  group('launchIntent', () {
    test('sends clean:true when restarting a running orchestrator', () {
      final intent = launchIntent(OrchestratorState.running);
      expect(intent.clean, isTrue);
      expect(intent.label.toLowerCase(), contains('restart'));
    });

    test('requires confirmation for the destructive path, and only that path', () {
      expect(launchIntent(OrchestratorState.running).confirm, isTrue);
      expect(launchIntent(OrchestratorState.stopped).confirm, isFalse);
      expect(launchIntent(OrchestratorState.missing).confirm, isFalse);
    });

    test('uses the cheap ensure when there is nothing live to retire', () {
      for (final state in [OrchestratorState.missing, OrchestratorState.stopped]) {
        expect(launchIntent(state).clean, isFalse, reason: state.name);
        expect(launchIntent(state).label.toLowerCase(), contains('start'), reason: state.name);
      }
    });
  });

  group('orchestratorStatus', () {
    test('names the two non-running states without inventing a status', () {
      expect(orchestratorStatus(dark, null).label, 'Not started');
      expect(orchestratorStatus(dark, link(isTerminal: true)).label, 'Stopped');
    });

    test('defers to the shared status vocabulary while running', () {
      expect(orchestratorStatus(dark, link(status: 'working')).label, 'Working');
      expect(orchestratorStatus(dark, link(status: 'needs_input')).label, 'Needs input');
    });

    test('falls back to Online when the daemon sent no status', () {
      expect(orchestratorStatus(dark, link()).label, 'Online');
    });

    test('takes its colours from the passed skin', () {
      expect(
        orchestratorStatus(light, link(status: 'working')).color,
        isNot(orchestratorStatus(dark, link(status: 'working')).color),
      );
    });

    test('only breathes for a live, working orchestrator', () {
      expect(orchestratorStatus(dark, link(status: 'working')).breathing, isTrue);
      expect(orchestratorStatus(dark, link(status: 'idle')).breathing, isFalse);
      expect(orchestratorStatus(dark, null).breathing, isFalse);
    });
  });

  group('workersOf', () {
    test('takes every session in the project', () {
      final all = [session(id: 'a'), session(id: 'b'), session(id: 'x', projectId: 'other')];
      expect(workersOf(all, 'proj', null).map((s) => s.id), ['a', 'b']);
    });

    test('never counts the orchestrator as one of its own workers', () {
      final all = [session(id: 'proj-orchestrator'), session(id: 'a')];
      expect(workersOf(all, 'proj', link()).map((s) => s.id), ['a']);
    });
  });

  group('zoneCounts', () {
    test('buckets by attention zone', () {
      final counts = zoneCounts([
        session(status: 'working'),
        session(status: 'working'),
        session(status: 'needs_input'),
      ]);
      expect(counts[AttentionLevel.working], 2);
      expect(counts[AttentionLevel.respond], 1);
    });

    test('is empty for no sessions', () {
      expect(zoneCounts([]), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/orchestrator/logic/orchestrator_view_test.dart`
Expected: FAIL — `orchestrator_view.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/logic/status_visual.dart';

enum OrchestratorState { missing, stopped, running }

OrchestratorState orchestratorStateOf(OrchestratorModel? link) {
  final id = link?.id;
  if (id == null || id.isEmpty) return OrchestratorState.missing;
  if (link!.hasRuntime == false || link.isTerminal == true) return OrchestratorState.stopped;
  return OrchestratorState.running;
}

class OrchestratorStatus {
  const OrchestratorStatus({required this.label, required this.color, required this.breathing});

  final String label;
  final Color color;
  final bool breathing;
}

OrchestratorStatus orchestratorStatus(AppSkin skin, OrchestratorModel? link) {
  switch (orchestratorStateOf(link)) {
    case OrchestratorState.missing:
      return OrchestratorStatus(label: 'Not started', color: skin.textFaint, breathing: false);
    case OrchestratorState.stopped:
      return OrchestratorStatus(label: 'Stopped', color: skin.textTertiary, breathing: false);
    case OrchestratorState.running:
      final status = link?.status;
      if (status == null || status.isEmpty) {
        return OrchestratorStatus(label: 'Online', color: skin.blue, breathing: false);
      }
      final visual = statusVisual(skin, status);
      return OrchestratorStatus(label: visual.label, color: visual.color, breathing: visual.breathing);
  }
}

class LaunchIntent {
  const LaunchIntent({required this.clean, required this.label, required this.confirm});

  final bool clean;
  final String label;
  final bool confirm;
}

LaunchIntent launchIntent(OrchestratorState state) => state == OrchestratorState.running
    ? const LaunchIntent(clean: true, label: 'Restart orchestrator', confirm: true)
    : const LaunchIntent(clean: false, label: 'Start orchestrator', confirm: false);

Map<AttentionLevel, int> zoneCounts(List<SessionModel> sessions) {
  final counts = <AttentionLevel, int>{};
  for (final session in sessions) {
    final level = attentionOf(session);
    counts[level] = (counts[level] ?? 0) + 1;
  }
  return counts;
}

List<SessionModel> workersOf(List<SessionModel> sessions, String projectId, OrchestratorModel? link) =>
    sessions.where((s) => s.projectId == projectId && s.id != link?.id).toList();
```

- [ ] **Step 4: Add `attentionMeta` to `agents_view.dart`**

```dart
class AttentionMeta {
  const AttentionMeta({required this.label, required this.color, required this.tint});

  final String label;
  final Color color;
  final Color tint;
}

AttentionMeta attentionMeta(AppSkin skin, AttentionLevel level) {
  switch (level) {
    case AttentionLevel.merge:
      return AttentionMeta(label: 'Ready to merge', color: skin.green, tint: skin.tintGreen);
    case AttentionLevel.respond:
      return AttentionMeta(label: 'Needs you', color: skin.amber, tint: skin.tintAmber);
    case AttentionLevel.review:
      return AttentionMeta(label: 'Review', color: skin.red, tint: skin.tintRed);
    case AttentionLevel.pending:
      return AttentionMeta(label: 'In review', color: skin.textTertiary, tint: skin.bgSubtle);
    case AttentionLevel.working:
      return AttentionMeta(label: 'Working', color: skin.orange, tint: skin.tintOrange);
    case AttentionLevel.done:
      return AttentionMeta(label: 'Done', color: skin.textTertiary, tint: skin.bgSubtle);
  }
}
```

Add a case to `agents_view_test.dart` asserting each level's label, so a renamed zone is caught.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port the orchestrator presentation logic"
```

---

### Task 13: Orchestrator launch — params, data source, repository, cubit

**Files:**
- Create: `packages/mobile/lib/feature/orchestrator/data/model/params/launch_orchestrator_params.dart`
- Create: `packages/mobile/lib/feature/orchestrator/data/data_source/orchestrator_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/orchestrator/data/repository/orchestrator_repository.dart`
- Create: `packages/mobile/lib/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart`
- Create: `packages/mobile/lib/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_state.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Test: `packages/mobile/test/feature/orchestrator/data/data_source/orchestrator_remote_data_source_test.dart`
- Test: `packages/mobile/test/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit_test.dart`

**Interfaces:**
- Consumes: `ApiConsumer`, `NetworkStatus`, `EndPoints.orchestrators` (Task 3), `OrchestratorModel`
  (Task 2), `isChatPreflightFailure` (Task 11).
- Produces:
  - `class LaunchOrchestratorParams extends Equatable` — `projectId (String)`, `clean (bool)`,
    `mode (String)`; `Map<String, dynamic> toJson()`
  - `OrchestratorRemoteDataSource.launch(LaunchOrchestratorParams params) → Future<GlobalResponse<OrchestratorModel>>`
  - `OrchestratorRepository.launch(...) → FutureResult<GlobalResponse<OrchestratorModel>>`
  - `sealed class OrchestratorLaunchState` with `OrchestratorInitialState`,
    `LaunchLoadingState(String projectId)`, `LaunchSuccessState(OrchestratorModel link)`,
    `LaunchFailureState(Failure failure, bool chatUnavailable)`
  - `class OrchestratorCubit extends Cubit<OrchestratorLaunchState>` with
    `Future<void> launch(String projectId, {required bool clean, String mode = 'chat'})`

Per the spec, params classes are **one per method and never shared**, so
`LaunchOrchestratorParams` is its own class even though `SpawnSessionParams` (Task 16) overlaps it.

The response's orchestrator is reported back with `hasRuntime: true`/`isTerminal: false` regardless
of what the wire says, matching RN's `launchOrchestrator` — the call just created it, so it is live
by construction, and the board's next poll supplies the authoritative record 8 seconds later.

`LaunchFailureState.chatUnavailable` is `isChatPreflightFailure(failure)` computed once in the
cubit, so the screen (Task 14) can offer "Start Terminal UI" without re-classifying.

- [ ] **Step 1: Write the failing tests**

The data-source test asserts the request body and the response mapping:

```dart
  test('posts the project, clean flag and mode', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/'),
        data: {'orchestrator': {'id': 'o1', 'projectId': 'p', 'mode': 'chat'}},
      ),
    );

    await dataSource.launch(const LaunchOrchestratorParams(projectId: 'p', clean: true, mode: 'chat'));

    final captured = verify(
      () => apiConsumer.post(EndPoints.orchestrators, body: captureAny(named: 'body')),
    ).captured.single as Map<String, dynamic>;
    expect(captured, {'projectId': 'p', 'clean': true, 'mode': 'chat'});
  });

  test('reports the fresh orchestrator as live', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/'),
        data: {'orchestrator': {'id': 'o1', 'projectId': 'p', 'isTerminated': true}},
      ),
    );

    final link = (await dataSource.launch(
      const LaunchOrchestratorParams(projectId: 'p', clean: false, mode: 'chat'),
    )).data!;

    expect(link.id, 'o1');
    expect(link.hasRuntime, isTrue);
    expect(link.isTerminal, isFalse);
  });
```

The cubit test covers the three outcomes:

```dart
  blocTest<OrchestratorCubit, OrchestratorLaunchState>(
    'reports the launched orchestrator',
    build: () {
      when(() => repository.launch(any())).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const OrchestratorModel(id: 'o1'))),
      );
      return OrchestratorCubit(repository);
    },
    act: (cubit) => cubit.launch('p', clean: false),
    expect: () => [
      isA<LaunchLoadingState>().having((s) => s.projectId, 'projectId', 'p'),
      isA<LaunchSuccessState>().having((s) => s.link.id, 'link.id', 'o1'),
    ],
  );

  blocTest<OrchestratorCubit, OrchestratorLaunchState>(
    'flags a chat-preflight refusal so the screen can offer Terminal UI',
    build: () {
      when(() => repository.launch(any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(error: 'x', message: 'no chat driver', apiStatus: 'CHAT_DRIVER_UNAVAILABLE'),
        ),
      );
      return OrchestratorCubit(repository);
    },
    act: (cubit) => cubit.launch('p', clean: false),
    expect: () => [
      isA<LaunchLoadingState>(),
      isA<LaunchFailureState>().having((s) => s.chatUnavailable, 'chatUnavailable', isTrue),
    ],
  );

  blocTest<OrchestratorCubit, OrchestratorLaunchState>(
    'does not offer Terminal UI for an ordinary failure',
    build: () {
      when(() => repository.launch(any()))
          .thenAnswer((_) async => Result.failure(ServerFailure(error: 'x', message: 'boom')));
      return OrchestratorCubit(repository);
    },
    act: (cubit) => cubit.launch('p', clean: false),
    expect: () => [
      isA<LaunchLoadingState>(),
      isA<LaunchFailureState>().having((s) => s.chatUnavailable, 'chatUnavailable', isFalse),
    ],
  );

  test('sends the clean flag it is given', () async {
    when(() => repository.launch(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const OrchestratorModel(id: 'o1'))),
    );
    final cubit = OrchestratorCubit(repository);

    await cubit.launch('p', clean: true);

    final params = verify(() => repository.launch(captureAny())).captured.single
        as LaunchOrchestratorParams;
    expect(params.clean, isTrue);
    expect(params.projectId, 'p');
    await cubit.close();
  });
```

Register the mocktail fallback for the params class in `setUpAll`:

```dart
  setUpAll(() => registerFallbackValue(
      const LaunchOrchestratorParams(projectId: 'p', clean: false, mode: 'chat')));
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/feature/orchestrator/`
Expected: FAIL — the data source and cubit do not exist.

- [ ] **Step 3: Write the params, data source and repository**

```dart
class LaunchOrchestratorParams extends Equatable {
  const LaunchOrchestratorParams({
    required this.projectId,
    required this.clean,
    required this.mode,
  });

  final String projectId;
  final bool clean;
  final String mode;

  Map<String, dynamic> toJson() => {'projectId': projectId, 'clean': clean, 'mode': mode};

  @override
  List<Object?> get props => [projectId, clean, mode];
}
```

```dart
  @override
  Future<GlobalResponse<OrchestratorModel>> launch(LaunchOrchestratorParams params) async {
    final response = await _apiConsumer.post(EndPoints.orchestrators, body: params.toJson());
    return GlobalResponse<OrchestratorModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) {
        final orchestrator = json['orchestrator'] as Map<String, dynamic>? ?? const {};
        return OrchestratorModel.fromJson({
          ...orchestrator,
          'projectId': orchestrator['projectId'] ?? params.projectId,
          'isTerminated': false,
        });
      },
    );
  }
```

The repository is the same `NetworkStatus`-gated shape as the others.

- [ ] **Step 4: Write the state and cubit**

```dart
class OrchestratorCubit extends Cubit<OrchestratorLaunchState> {
  OrchestratorCubit(this._repository) : super(const OrchestratorInitialState());

  final OrchestratorRepository _repository;

  Future<void> launch(String projectId, {required bool clean, String mode = 'chat'}) async {
    emit(LaunchLoadingState(projectId));
    final result = await _repository.launch(
      LaunchOrchestratorParams(projectId: projectId, clean: clean, mode: mode),
    );
    result.when(
      onSuccess: (response) => emit(LaunchSuccessState(response.data ?? const OrchestratorModel())),
      onFailure: (failure) =>
          emit(LaunchFailureState(failure, chatUnavailable: isChatPreflightFailure(failure))),
    );
  }
}
```

- [ ] **Step 5: Register the feature**

Add `_orchestratorFeatureSetup()` to `ServiceLocator.init()`, registering `OrchestratorCubit` as a
factory and the repository/data source as lazy singletons. Extend `service_locator_test.dart`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the orchestrator launch data layer and cubit"
```

---

### Task 14: The Orchestrator tab

**Files:**
- Create: `packages/mobile/lib/feature/orchestrator/presentation/orchestrator_screen/ui/orchestrator_screen.dart`
- Create: `packages/mobile/lib/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_body.dart`
- Create: `packages/mobile/lib/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_card.dart`
- Modify: `packages/mobile/lib/core/app_routes/home_shell.dart`
- Test: `packages/mobile/test/feature/orchestrator/presentation/orchestrator_screen/ui/orchestrator_card_test.dart`
- Test: `packages/mobile/test/feature/orchestrator/presentation/orchestrator_screen/ui/orchestrator_body_test.dart`

**Interfaces:**
- Consumes: `SessionsCubit`, `OrchestratorCubit`, `orchestrator_view.dart`, `attentionMeta`,
  `AppDialog.confirm`, `AgentLogo`, `AppEmptyState`.
- Produces: `OrchestratorScreen`, `OrchestratorBody`, `OrchestratorCard`.

**This tab deliberately ignores the active-project filter.** RN's own comment is explicit: it is
the one cross-project overview, so it lists `cubit.projects` in full and reads `cubit.sessions`,
not `cubit.visibleSessions`. Getting this wrong makes the tab silently show one card.

Tapping a zone pill scopes the board to that project and switches to the Agents tab — the natural
next move after reading "1 needs you". In RN that is `setActiveProject(id)` then `router.navigate("/")`;
here it is `sessionsCubit.setActiveProject(projectId)` plus a callback the shell passes down to
change its tab index, since the tabs are an `IndexedStack` rather than routes.

- [ ] **Step 1: Write the failing card test**

`orchestrator_card_test.dart` — a real `OrchestratorCubit` over a mocked `OrchestratorRepository`
and a real `SessionsCubit` over a mocked `SessionsRepository`, following
`session_actions_sheet_test.dart`'s pattern (`SkinScope` **above** `MaterialApp` so dialog contexts
resolve `context.skin`). Cover:

```dart
  testWidgets('offers Start for a project with no orchestrator', (tester) async {
    await pumpCard(tester, link: null, workers: const []);

    expect(find.text('Start orchestrator'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
  });

  testWidgets('starts without a confirmation', (tester) async {
    await pumpCard(tester, link: null, workers: const []);

    await tester.tap(find.text('Start orchestrator'));
    await tester.pumpAndSettle();

    final params = verify(() => repository.launch(captureAny())).captured.single
        as LaunchOrchestratorParams;
    expect(params.clean, isFalse);
  });

  testWidgets('asks before restarting a running orchestrator', (tester) async {
    await pumpCard(tester, link: const OrchestratorModel(id: 'o1', projectId: 'p'), workers: const []);

    await tester.tap(find.byTooltip('Restart orchestrator'));
    await tester.pumpAndSettle();

    expect(find.text('Restart orchestrator?'), findsOneWidget);
    verifyNever(() => repository.launch(any()));

    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();

    final params = verify(() => repository.launch(captureAny())).captured.single
        as LaunchOrchestratorParams;
    expect(params.clean, isTrue);
  });

  testWidgets('does not restart when the confirmation is declined', (tester) async {
    await pumpCard(tester, link: const OrchestratorModel(id: 'o1', projectId: 'p'), workers: const []);

    await tester.tap(find.byTooltip('Restart orchestrator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repository.launch(any()));
  });

  testWidgets('counts workers and shows a pill per attention zone', (tester) async {
    await pumpCard(
      tester,
      link: const OrchestratorModel(id: 'o1', projectId: 'p'),
      workers: const [
        SessionModel(id: 'a', projectId: 'p', status: 'working'),
        SessionModel(id: 'b', projectId: 'p', status: 'working'),
        SessionModel(id: 'c', projectId: 'p', status: 'needs_input'),
      ],
    );

    expect(find.text('3 workers'), findsOneWidget);
    expect(find.text('Working'), findsWidgets);
    expect(find.text('Needs you'), findsOneWidget);
  });

  testWidgets('says worker in the singular for one', (tester) async {
    await pumpCard(
      tester,
      link: const OrchestratorModel(id: 'o1', projectId: 'p'),
      workers: const [SessionModel(id: 'a', projectId: 'p', status: 'working')],
    );

    expect(find.text('1 worker'), findsOneWidget);
  });

  testWidgets('offers no open action, because no session screen exists yet', (tester) async {
    await pumpCard(tester, link: const OrchestratorModel(id: 'o1', projectId: 'p'), workers: const []);

    expect(find.byTooltip('Open orchestrator'), findsNothing);
  });
```

`orchestrator_body_test.dart` covers the list level:

- every project gets a card **even when the active project is set to one of them** (the
  cross-project rule above);
- with no projects and the board failed, the connection-failure copy shows with a Retry action;
- with no projects and no failure, "No projects" shows.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/feature/orchestrator/presentation/`
Expected: FAIL — the widgets do not exist.

- [ ] **Step 3: Write the card**

`orchestrator_card.dart` — a `StatefulWidget` taking `projectId`, `projectName`,
`link (OrchestratorModel?)`, `workers (List<SessionModel>)`, and `onOpenBoard (VoidCallback)`.

Layout, in an `AppContainer` with the same margins as `PrCard`:

1. a head row — `AgentLogo(harness: link?.harness, size: 26)`, then a column with the project name
   in `AppTextStyle.style15SemiBold` and a status row: a 7pt dot in `status.color`, the
   `status.label` in `AppTextStyle.style12SemiBold.copyWith(color: status.color)`, and
   `'· ${link!.harness}'` in `AppTextStyle.mono12Regular` when the harness is known;
2. a `Wrap` of zone pills when `workers.isNotEmpty`, iterating
   `[AttentionLevel.merge, respond, review, pending, working, done]` and skipping any with a zero
   count — each pill filled `meta.tint`, carrying a 6pt dot in `meta.color`, the count in
   `AppTextStyle.mono12Bold.copyWith(color: meta.color)` and `meta.label` in
   `AppTextStyle.style11SemiBold`, wrapped in a `Semantics(button: true, label: '${count} ${meta.label} in $projectName. Opens the board.')`
   and calling `onOpenBoard` after `sessionsCubit.setActiveProject(projectId)`;
3. a footer row — `'${workers.length} worker${workers.length == 1 ? '' : 's'}'` in
   `AppTextStyle.style12Regular`, then either an `IconButton(tooltip: 'Restart orchestrator')` when
   running, or a filled `'Start orchestrator'` button (`skin.blue` fill, `skin.onAccent` label)
   otherwise. While `LaunchLoadingState` names this project the button reads `'Starting…'` and is
   disabled.

The launch handler:

```dart
  Future<void> _onLaunch() async {
    final intent = launchIntent(orchestratorStateOf(widget.link));
    if (intent.confirm) {
      final confirmed = await AppDialog.confirm(
        context,
        title: 'Restart orchestrator?',
        message: 'The orchestrator for ${widget.projectName} will be retired and replaced with a '
            'fresh one. Its workers keep running.',
        confirmLabel: 'Restart',
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    await context.read<OrchestratorCubit>().launch(widget.projectId, clean: intent.clean);
  }
```

- [ ] **Step 4: Write the body and screen**

`orchestrator_body.dart` — a `BlocListener<OrchestratorCubit, OrchestratorLaunchState>` that, on
`LaunchSuccessState`, calls `sessionsCubit.refresh()` and shows a snackbar
(`'Orchestrator started'`), and on `LaunchFailureState` shows either `chatErrorCopy(failure)` with
a "Start Terminal UI" snackbar action re-launching with `mode: 'tui'` when `chatUnavailable`, or
`describeConnectionFailure`'s title and message otherwise. Its child is a
`BlocBuilder<SessionsCubit, SessionsState>` rendering one `OrchestratorCard` per
`cubit.projects`, with:

```dart
    final link = cubit.orchestrators
        .where((o) => o.projectId == project.id)
        .cast<OrchestratorModel?>()
        .firstWhere((o) => true, orElse: () => null);
```

(or an explicit loop — do not use `firstWhere` without an `orElse`, which throws) and
`workers: workersOf(cubit.sessions, project.id ?? '', link)`.

`orchestrator_screen.dart` — a `Scaffold` with `GlobalAppbar.main(titleText: 'Orchestrator')`,
wrapped in `BlocProvider(create: (_) => sl<OrchestratorCubit>())`, taking an `onOpenBoard`
callback from the shell.

- [ ] **Step 5: Mount it in the shell and let a pill switch tabs**

In `home_shell.dart`, replace the index-1 placeholder with
`OrchestratorScreen(onOpenBoard: () => setState(() => _index = 0))`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the Orchestrator tab"
```

---

### Task 15: Agent catalog ranking (`agentPicker.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/spawn/logic/agent_picker.dart`
- Test: `packages/mobile/test/feature/spawn/logic/agent_picker_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class AgentInfo extends Equatable` — `id (String)`, `label (String)`, `authStatus (String?)`;
    `AgentInfo.fromJson(Map<String, dynamic>)`
  - `class AgentCatalog extends Equatable` — `supported`, `installed`, `authorized`
    (`List<AgentInfo>`, defaulting to const empty); `AgentCatalog.fromJson(Map<String, dynamic>)`
  - `enum AgentAvailability { authorized, authUnknown, needsAuth, needsInstall }`
  - `AgentAvailability availabilityOf(AgentInfo agent, AgentCatalog catalog)`
  - `bool isSelectable(AgentAvailability availability)`
  - `String statusLabel(AgentAvailability availability)`
  - `class RankedAgent extends Equatable` — `id`, `label`, `availability`, `status`, `selectable`
  - `List<RankedAgent> rankAgents(AgentCatalog? catalog)`
  - `String? defaultAgent(List<RankedAgent> ranked)`

The load-bearing rule: **`authUnknown` stays selectable**. The daemon failed to determine
credential state, and refusing on that basis would block a perfectly working agent. Only an
explicit `unauthorized` or a missing install disqualifies.

Ordering is availability rank, then desktop's `DEFAULT_AGENT_PRIORITY`
(`claude-code, codex, cursor, opencode, aider`), then label. Without the priority tier the
authorized group is alphabetical and Aider sorts above Claude Code.

`AgentInfo`/`AgentCatalog` are declared here rather than in `data/model/` because they are what the
ranking logic is *about*, and the spec sequences logic-and-tests before the data layer that feeds
it. Task 16's data source parses straight into them.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/spawn/logic/agent_picker_test.dart` (ported from
`agentPicker.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';

AgentInfo agent(String id, {String? label, String? authStatus}) =>
    AgentInfo(id: id, label: label ?? id, authStatus: authStatus);

AgentCatalog catalog({
  List<AgentInfo> supported = const [],
  List<AgentInfo> installed = const [],
  List<AgentInfo> authorized = const [],
}) => AgentCatalog(supported: supported, installed: installed, authorized: authorized);

void main() {
  group('availabilityOf', () {
    test('reports an agent that is installed and authorized', () {
      final c = catalog(installed: [agent('codex')], authorized: [agent('codex')]);
      expect(availabilityOf(agent('codex'), c), AgentAvailability.authorized);
    });

    test('accepts authStatus as proof of authorization', () {
      final c = catalog(installed: [agent('codex', label: 'Codex', authStatus: 'authorized')]);
      expect(availabilityOf(agent('codex'), c), AgentAvailability.authorized);
    });

    test('reports a missing install', () {
      expect(availabilityOf(agent('goose'), catalog()), AgentAvailability.needsInstall);
    });

    test('reports an explicit refusal as needing auth', () {
      final c = catalog(installed: [agent('cursor', authStatus: 'unauthorized')]);
      expect(availabilityOf(agent('cursor'), c), AgentAvailability.needsAuth);
    });

    test('treats an absent or unknown authStatus as unknown, not unauthorized', () {
      expect(availabilityOf(agent('amp'), catalog(installed: [agent('amp')])),
          AgentAvailability.authUnknown);
      expect(
        availabilityOf(agent('amp'), catalog(installed: [agent('amp', authStatus: 'unknown')])),
        AgentAvailability.authUnknown,
      );
    });
  });

  group('isSelectable', () {
    test('allows an agent whose auth state is unknown', () {
      expect(isSelectable(AgentAvailability.authUnknown), isTrue);
    });

    test('allows an authorized agent', () {
      expect(isSelectable(AgentAvailability.authorized), isTrue);
    });

    test('refuses an uninstalled or explicitly unauthorized agent', () {
      expect(isSelectable(AgentAvailability.needsAuth), isFalse);
      expect(isSelectable(AgentAvailability.needsInstall), isFalse);
    });
  });

  group('statusLabel', () {
    test('says nothing about a healthy agent', () {
      expect(statusLabel(AgentAvailability.authorized), '');
    });

    test('names each problem', () {
      expect(statusLabel(AgentAvailability.authUnknown), 'Auth unknown');
      expect(statusLabel(AgentAvailability.needsAuth), 'Needs auth');
      expect(statusLabel(AgentAvailability.needsInstall), 'Needs install');
    });
  });

  group('rankAgents', () {
    test('orders usable agents above unusable ones', () {
      final c = catalog(
        supported: [agent('goose'), agent('cursor'), agent('amp'), agent('codex')],
        installed: [agent('codex'), agent('cursor', authStatus: 'unauthorized'), agent('amp')],
        authorized: [agent('codex')],
      );
      expect(rankAgents(c).map((a) => a.id), ['codex', 'amp', 'cursor', 'goose']);
    });

    test('breaks ties by priority, not alphabetically', () {
      const ids = ['aider', 'claude-code', 'codex'];
      final c = catalog(
        supported: ids.map(agent).toList(),
        installed: ids.map(agent).toList(),
        authorized: ids.map(agent).toList(),
      );
      expect(rankAgents(c).map((a) => a.id), ['claude-code', 'codex', 'aider']);
    });

    test('falls back to the label for agents outside the priority list', () {
      const ids = ['zed', 'kiro', 'droid'];
      final c = catalog(
        supported: ids.map(agent).toList(),
        installed: ids.map(agent).toList(),
        authorized: ids.map(agent).toList(),
      );
      expect(rankAgents(c).map((a) => a.id), ['droid', 'kiro', 'zed']);
    });

    test('carries the status and selectability onto each row', () {
      final ranked = rankAgents(catalog(supported: [agent('goose')])).single;
      expect(ranked.status, 'Needs install');
      expect(ranked.selectable, isFalse);
    });

    test('returns nothing for an absent catalog', () {
      expect(rankAgents(null), isEmpty);
      expect(rankAgents(catalog()), isEmpty);
    });
  });

  group('defaultAgent', () {
    test('preselects the best usable agent', () {
      final c = catalog(
        supported: [agent('goose'), agent('codex')],
        installed: [agent('codex')],
        authorized: [agent('codex')],
      );
      expect(defaultAgent(rankAgents(c)), 'codex');
    });

    test('preselects nothing when no agent is usable', () {
      final c = catalog(supported: [agent('goose'), agent('aider')]);
      expect(defaultAgent(rankAgents(c)), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/spawn/logic/agent_picker_test.dart`
Expected: FAIL — `agent_picker.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:equatable/equatable.dart';

const List<String> _priority = ['claude-code', 'codex', 'cursor', 'opencode', 'aider'];

class AgentInfo extends Equatable {
  const AgentInfo({required this.id, required this.label, this.authStatus});

  final String id;
  final String label;
  final String? authStatus;

  factory AgentInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    return AgentInfo(
      id: id,
      label: json['label'] as String? ?? id,
      authStatus: json['authStatus'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, label, authStatus];
}

class AgentCatalog extends Equatable {
  const AgentCatalog({
    this.supported = const [],
    this.installed = const [],
    this.authorized = const [],
  });

  final List<AgentInfo> supported;
  final List<AgentInfo> installed;
  final List<AgentInfo> authorized;

  static List<AgentInfo> _agents(dynamic raw) => (raw as List<dynamic>? ?? const [])
      .map((a) => AgentInfo.fromJson(a as Map<String, dynamic>))
      .toList();

  factory AgentCatalog.fromJson(Map<String, dynamic> json) => AgentCatalog(
    supported: _agents(json['supported']),
    installed: _agents(json['installed']),
    authorized: _agents(json['authorized']),
  );

  @override
  List<Object?> get props => [supported, installed, authorized];
}

enum AgentAvailability { authorized, authUnknown, needsAuth, needsInstall }

AgentAvailability availabilityOf(AgentInfo agent, AgentCatalog catalog) {
  AgentInfo? installed;
  for (final candidate in catalog.installed) {
    if (candidate.id == agent.id) installed = candidate;
  }
  if (installed == null) return AgentAvailability.needsInstall;
  final isAuthorized = catalog.authorized.any((a) => a.id == agent.id) ||
      installed.authStatus == 'authorized';
  if (isAuthorized) return AgentAvailability.authorized;
  return installed.authStatus == 'unauthorized'
      ? AgentAvailability.needsAuth
      : AgentAvailability.authUnknown;
}

bool isSelectable(AgentAvailability availability) =>
    availability == AgentAvailability.authorized || availability == AgentAvailability.authUnknown;

String statusLabel(AgentAvailability availability) {
  switch (availability) {
    case AgentAvailability.authUnknown:
      return 'Auth unknown';
    case AgentAvailability.needsAuth:
      return 'Needs auth';
    case AgentAvailability.needsInstall:
      return 'Needs install';
    case AgentAvailability.authorized:
      return '';
  }
}

class RankedAgent extends Equatable {
  const RankedAgent({
    required this.id,
    required this.label,
    required this.availability,
    required this.status,
    required this.selectable,
  });

  final String id;
  final String label;
  final AgentAvailability availability;
  final String status;
  final bool selectable;

  @override
  List<Object?> get props => [id, label, availability, status, selectable];
}

int _priorityOf(String id) {
  final index = _priority.indexOf(id);
  return index == -1 ? _priority.length + 1 : index;
}

List<RankedAgent> rankAgents(AgentCatalog? catalog) {
  if (catalog == null) return const [];
  final ranked = catalog.supported.map((agent) {
    final availability = availabilityOf(agent, catalog);
    return RankedAgent(
      id: agent.id,
      label: agent.label,
      availability: availability,
      status: statusLabel(availability),
      selectable: isSelectable(availability),
    );
  }).toList();

  ranked.sort((a, b) {
    final rank = a.availability.index - b.availability.index;
    if (rank != 0) return rank;
    final priority = _priorityOf(a.id) - _priorityOf(b.id);
    if (priority != 0) return priority;
    return a.label.compareTo(b.label);
  });
  return ranked;
}

String? defaultAgent(List<RankedAgent> ranked) {
  for (final agent in ranked) {
    if (agent.selectable) return agent.id;
  }
  return null;
}
```

`AgentAvailability`'s declaration order **is** the rank order — `authorized, authUnknown,
needsAuth, needsInstall` matches RN's `RANK` map exactly, so `.index` is the rank. Reordering the
enum silently reorders the picker; the "orders usable agents above unusable ones" test is what
catches that.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port agent catalog ranking"
```

---

### Task 16: Spawn data layer — agents, daemon settings, session spawn

**Files:**
- Create: `packages/mobile/lib/feature/spawn/data/model/operator_settings_model.dart`
- Create: `packages/mobile/lib/feature/spawn/data/model/params/spawn_session_params.dart`
- Create: `packages/mobile/lib/feature/spawn/data/data_source/spawn_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/spawn/data/repository/spawn_repository.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Test: `packages/mobile/test/feature/spawn/data/data_source/spawn_remote_data_source_test.dart`
- Test: `packages/mobile/test/feature/spawn/data/repository/spawn_repository_test.dart`

**Interfaces:**
- Consumes: `ApiConsumer`, `NetworkStatus`, `AgentCatalog` (Task 15), `SessionModel` (M1).
- Produces:
  - `class OperatorSettingsModel extends Equatable` — `defaultSessionMode (String)`,
    `chatHarnesses (List<String>)`; `OperatorSettingsModel.fromJson(...)`
  - `class SpawnSessionParams extends Equatable` — `projectId`, `prompt`, `issueId`, `harness`,
    `mode`; `Map<String, dynamic> toJson()`
  - `SpawnRemoteDataSource.getAgents()`, `.refreshAgents()`, `.getSettings()`, `.spawn(params)`
  - `SpawnRepository` mirroring all four, `NetworkStatus`-gated
  - `EndPoints.agentsRefresh`

`OperatorSettingsModel.defaultSessionMode` narrows to `'tui'` only on an exact match, defaulting to
`'chat'` — mobile is chat-first, and RN's `getSettings` does the same. `chatHarnesses` filters
non-strings out of the wire array rather than casting, because an older daemon sending a mixed
array must not crash the spawn screen.

`SpawnSessionParams.toJson()` **omits** null/empty `prompt`, `issueId` and `harness` rather than
sending explicit nulls — RN sends `harness: opts.harness || undefined`, and the daemon treats a
present-but-null harness differently from an absent one (a project's configured default worker
agent only applies when the key is absent). It always sends `kind: 'worker'` and defaults `mode` to
`'chat'`: omitting mode must never make the phone inherit a desktop preference it cannot see.

- [ ] **Step 1: Write the failing data-source test**

Cover, with a mocked `ApiConsumer`:

```dart
  test('parses the three agent lists', () async {
    when(() => apiConsumer.get(EndPoints.agents)).thenAnswer(
      (_) async => jsonResponse({
        'supported': [{'id': 'codex', 'label': 'Codex'}],
        'installed': [{'id': 'codex', 'label': 'Codex', 'authStatus': 'authorized'}],
        'authorized': [{'id': 'codex', 'label': 'Codex'}],
      }),
    );

    final catalog = (await dataSource.getAgents()).data!;
    expect(catalog.supported.single.label, 'Codex');
    expect(catalog.installed.single.authStatus, 'authorized');
    expect(catalog.authorized.single.id, 'codex');
  });

  test('tolerates a daemon that omits the lists entirely', () async {
    when(() => apiConsumer.get(EndPoints.agents)).thenAnswer((_) async => jsonResponse({}));

    final catalog = (await dataSource.getAgents()).data!;
    expect(catalog.supported, isEmpty);
    expect(catalog.installed, isEmpty);
    expect(catalog.authorized, isEmpty);
  });

  test('refreshes the catalog with a POST', () async {
    when(() => apiConsumer.post(EndPoints.agentsRefresh))
        .thenAnswer((_) async => jsonResponse({'supported': <dynamic>[]}));

    await dataSource.refreshAgents();

    verify(() => apiConsumer.post(EndPoints.agentsRefresh)).called(1);
  });

  test('defaults the session mode to chat and keeps only string harnesses', () async {
    when(() => apiConsumer.get(EndPoints.settings)).thenAnswer(
      (_) async => jsonResponse({'chatHarnesses': ['claude-code', 7, null, 'codex']}),
    );

    final settings = (await dataSource.getSettings()).data!;
    expect(settings.defaultSessionMode, 'chat');
    expect(settings.chatHarnesses, ['claude-code', 'codex']);
  });

  test('honours an explicit tui default', () async {
    when(() => apiConsumer.get(EndPoints.settings))
        .thenAnswer((_) async => jsonResponse({'defaultSessionMode': 'tui'}));

    expect((await dataSource.getSettings()).data!.defaultSessionMode, 'tui');
  });

  test('omits the optional spawn fields it was not given', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => jsonResponse({'session': {'id': 's1', 'projectId': 'p'}}));

    await dataSource.spawn(const SpawnSessionParams(projectId: 'p', mode: 'chat'));

    final body = verify(() => apiConsumer.post(EndPoints.sessions, body: captureAny(named: 'body')))
        .captured.single as Map<String, dynamic>;
    expect(body, {'projectId': 'p', 'mode': 'chat', 'kind': 'worker'});
  });

  test('sends every field it was given', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => jsonResponse({'session': {'id': 's1', 'projectId': 'p'}}));

    await dataSource.spawn(const SpawnSessionParams(
      projectId: 'p',
      prompt: 'fix the test',
      issueId: 'flaky login',
      harness: 'codex',
      mode: 'tui',
    ));

    final body = verify(() => apiConsumer.post(EndPoints.sessions, body: captureAny(named: 'body')))
        .captured.single as Map<String, dynamic>;
    expect(body, {
      'projectId': 'p',
      'prompt': 'fix the test',
      'issueId': 'flaky login',
      'harness': 'codex',
      'mode': 'tui',
      'kind': 'worker',
    });
  });

  test('reads the spawned session out of either envelope', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => jsonResponse({'session': {'id': 's1', 'projectId': 'p'}}));
    expect((await dataSource.spawn(const SpawnSessionParams(projectId: 'p', mode: 'chat'))).data!.id, 's1');

    when(() => apiConsumer.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => jsonResponse({'id': 's2', 'projectId': 'p'}));
    expect((await dataSource.spawn(const SpawnSessionParams(projectId: 'p', mode: 'chat'))).data!.id, 's2');
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/spawn/data/`
Expected: FAIL — the data source does not exist.

- [ ] **Step 3: Add the endpoint and write the models**

```dart
  static const String agentsRefresh = '/api/v1/agents/refresh';
```

```dart
class OperatorSettingsModel extends Equatable {
  const OperatorSettingsModel({this.defaultSessionMode = 'chat', this.chatHarnesses = const []});

  final String defaultSessionMode;
  final List<String> chatHarnesses;

  factory OperatorSettingsModel.fromJson(Map<String, dynamic> json) => OperatorSettingsModel(
    defaultSessionMode: json['defaultSessionMode'] == 'tui' ? 'tui' : 'chat',
    chatHarnesses: (json['chatHarnesses'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
  );

  @override
  List<Object?> get props => [defaultSessionMode, chatHarnesses];
}
```

```dart
class SpawnSessionParams extends Equatable {
  const SpawnSessionParams({
    required this.projectId,
    required this.mode,
    this.prompt,
    this.issueId,
    this.harness,
  });

  final String projectId;
  final String mode;
  final String? prompt;
  final String? issueId;
  final String? harness;

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    if (prompt != null && prompt!.isNotEmpty) 'prompt': prompt,
    if (issueId != null && issueId!.isNotEmpty) 'issueId': issueId,
    if (harness != null && harness!.isNotEmpty) 'harness': harness,
    'mode': mode,
    'kind': 'worker',
  };

  @override
  List<Object?> get props => [projectId, mode, prompt, issueId, harness];
}
```

- [ ] **Step 4: Write the data source and repository**

The data source's four methods each wrap `GlobalResponse.fromJson(..., withDataKey: false, ...)`;
`spawn` reads `json['session'] as Map<String, dynamic>? ?? json` before `SessionModel.fromJson`,
which is how RN's `mapSession(data?.session ?? data)` tolerates both envelopes. The repository is
the same `NetworkStatus`-gated shape as the others, with the same three mirrored repository tests.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the spawn data layer"
```

---

### Task 17: `SpawnCubit`

**Files:**
- Create: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart`
- Create: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/logic/spawn_state.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Test: `packages/mobile/test/feature/spawn/presentation/spawn_screen/logic/spawn_cubit_test.dart`

**Interfaces:**
- Consumes: `SpawnRepository` (Task 16), `rankAgents`/`defaultAgent` (Task 15),
  `isChatPreflightFailure` (Task 11).
- Produces:
  - `sealed class SpawnState` with `SpawnInitialState`, `CatalogLoadingState`,
    `CatalogReadyState(int revision)`, `CatalogFailureState(Failure failure)`,
    `SpawnLoadingState`, `SpawnSuccessState(SessionModel session)`,
    `SpawnFailureState(Failure failure, bool chatUnavailable)`,
    `SpawnValidationFailureState(String message)`
  - `class SpawnCubit extends Cubit<SpawnState>` with fields `projectId`, `harness`, `mode`,
    `name`, `prompt`, `agents`, `chatHarnesses`, and methods `loadCatalog()`,
    `refreshCatalog()`, `setProject(String?)`, `setHarness(String)`, `setMode(String)`,
    `submit()`

Three behaviors from `app/spawn.tsx` that the tests pin:

- **The agent list is filtered by mode.** In `chat`, only agents in `settings.chatHarnesses` are
  offered; in `tui`, the whole ranked catalog is. Switching to chat re-picks the default when the
  current harness is not chat-capable, which is what stops the form sitting in an unsubmittable
  state after a mode flip.
- **Validation happens on submit, not by disabling the button.** Desktop's choice, and the better
  one: a disabled button with no explanation is worse than a message naming what is missing.
- **A chat-preflight refusal is flagged** so the screen can offer "Create as Terminal UI instead".

- [ ] **Step 1: Write the failing test**

```dart
  blocTest<SpawnCubit, SpawnState>(
    'offers only chat-capable agents in chat mode',
    build: buildCubit,
    act: (cubit) => cubit.loadCatalog(),
    verify: (cubit) {
      expect(cubit.mode, 'chat');
      expect(cubit.agents.map((a) => a.id), ['claude-code']);
      expect(cubit.harness, 'claude-code');
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'offers the whole catalog in tui mode',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setMode('tui');
    },
    verify: (cubit) => expect(cubit.agents.map((a) => a.id), ['claude-code', 'codex']),
  );

  blocTest<SpawnCubit, SpawnState>(
    're-picks a chat-capable default when switching back to chat',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setMode('tui');
      cubit.setHarness('codex');
      cubit.setMode('chat');
    },
    verify: (cubit) => expect(cubit.harness, 'claude-code'),
  );

  blocTest<SpawnCubit, SpawnState>(
    'reports a catalog fetch failure instead of showing an empty picker',
    build: () {
      when(() => repository.getAgents())
          .thenAnswer((_) async => Result.failure(ServerFailure(error: 'x', message: 'boom')));
      when(() => repository.getSettings()).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const OperatorSettingsModel())),
      );
      return SpawnCubit(repository);
    },
    act: (cubit) => cubit.loadCatalog(),
    expect: () => [isA<CatalogLoadingState>(), isA<CatalogFailureState>()],
  );

  blocTest<SpawnCubit, SpawnState>(
    'refuses to submit without a name and a task',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p');
      cubit.name = '  ';
      cubit.prompt = 'do the thing';
      await cubit.submit();
    },
    verify: (cubit) => verifyNever(() => repository.spawn(any())),
    expect: () => [
      isA<CatalogLoadingState>(),
      isA<CatalogReadyState>(),
      isA<SpawnValidationFailureState>(),
    ],
  );

  blocTest<SpawnCubit, SpawnState>(
    'spawns with the chosen project, agent and mode',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p');
      cubit.name = 'flaky login';
      cubit.prompt = 'fix it';
      await cubit.submit();
    },
    verify: (cubit) {
      final params = verify(() => repository.spawn(captureAny())).captured.single
          as SpawnSessionParams;
      expect(params.projectId, 'p');
      expect(params.issueId, 'flaky login');
      expect(params.prompt, 'fix it');
      expect(params.harness, 'claude-code');
      expect(params.mode, 'chat');
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'flags a chat-preflight refusal so the screen can offer Terminal UI',
    build: () { /* getAgents/getSettings as above; spawn fails with CHAT_DRIVER_UNAVAILABLE */ },
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p');
      cubit.name = 'n';
      cubit.prompt = 'p';
      await cubit.submit();
    },
    verify: (cubit) => expect(
      (cubit.state as SpawnFailureState).chatUnavailable,
      isTrue,
    ),
  );
```

where `buildCubit` stubs `getAgents` with a catalog of `claude-code` and `codex` (both installed
and authorized) and `getSettings` with `chatHarnesses: ['claude-code']`.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/spawn/presentation/`
Expected: FAIL — the cubit does not exist.

- [ ] **Step 3: Write the state and cubit**

`loadCatalog` fetches agents and settings together (`Future.wait`) — unlike the board's probe, both
are one-shot user-initiated reads on a screen the user just opened, not an 8s poll, so they carry
no lockout risk. Its core:

```dart
  Future<void> loadCatalog() async {
    emit(const CatalogLoadingState());
    final results = await Future.wait([_repository.getAgents(), _repository.getSettings()]);
    final agentsResult = results.first as Result<GlobalResponse<AgentCatalog>>;
    final settingsResult = results.last as Result<GlobalResponse<OperatorSettingsModel>>;

    Failure? failure;
    agentsResult.when(
      onSuccess: (response) => _catalog = response.data,
      onFailure: (error) => failure = error,
    );
    settingsResult.when(
      onSuccess: (response) => chatHarnesses = response.data?.chatHarnesses ?? const [],
      onFailure: (error) => failure ??= error,
    );

    if (failure != null) {
      emit(CatalogFailureState(failure!));
      return;
    }
    harness = _pickHarness(harness);
    _bump();
  }

  List<RankedAgent> get agents {
    final ranked = rankAgents(_catalog);
    if (mode != 'chat') return ranked;
    return ranked.where((agent) => chatHarnesses.contains(agent.id)).toList();
  }

  String _pickHarness(String current) =>
      agents.any((agent) => agent.id == current) ? current : (defaultAgent(agents) ?? '');

  void setMode(String next) {
    mode = next;
    harness = _pickHarness(harness);
    _bump();
  }

  Future<void> submit() async {
    if (name.trim().isEmpty || prompt.trim().isEmpty) {
      emit(const SpawnValidationFailureState('Name and task are required.'));
      return;
    }
    final project = projectId;
    if (project == null || project.isEmpty) {
      emit(const SpawnValidationFailureState('Choose a project.'));
      return;
    }
    emit(const SpawnLoadingState());
    final result = await _repository.spawn(SpawnSessionParams(
      projectId: project,
      mode: mode,
      prompt: prompt.trim(),
      issueId: name.trim(),
      harness: harness,
    ));
    result.when(
      onSuccess: (response) => emit(SpawnSuccessState(response.data ?? const SessionModel())),
      onFailure: (failure) =>
          emit(SpawnFailureState(failure, chatUnavailable: isChatPreflightFailure(failure))),
    );
  }
```

`refreshCatalog()` is `loadCatalog()` against `_repository.refreshAgents()` instead of
`getAgents()`, leaving `chatHarnesses` untouched.

- [ ] **Step 4: Register the feature**

Add `_spawnFeatureSetup()` to `ServiceLocator.init()` and extend `service_locator_test.dart`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add SpawnCubit"
```

---

### Task 18: The spawn screen and the agent picker

**Files:**
- Create: `packages/mobile/lib/core/widgets/pickers/agent_picker_sheet.dart`
- Create: `packages/mobile/lib/core/widgets/main_widgets/settings_group.dart`
- Create: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/spawn_screen.dart`
- Create: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart`
- Modify: `packages/mobile/lib/core/app_routes/routes_strings.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart`
- Test: `packages/mobile/test/feature/spawn/presentation/spawn_screen/ui/spawn_body_test.dart`
- Test: `packages/mobile/test/core/widgets/agent_picker_sheet_test.dart`

**Interfaces:**
- Consumes: `SpawnCubit` (Task 17), `SessionsCubit` (Task 4), `showProjectPickerSheet` (Task 10),
  `AgentLogo` (M1).
- Produces:
  - `Future<String?> showAgentPickerSheet(BuildContext context, {required List<RankedAgent> agents, required String selected, required Future<void> Function() onRefresh, bool refreshing = false, String? error})`
  - `class SettingsGroup extends StatelessWidget` — `title`, `footer`, `children`, drawing hairline
    separators **between** rows
  - `class SettingsRow extends StatelessWidget` — `icon`, `label`, `value`, `valueColor`, `leading`,
    `onTap`, `destructive`, `loading`, `disabled`, `trailing`
  - `RoutesStrings.spawn = '/spawn'`
  - `SpawnScreen`, `SpawnBody`

`SettingsGroup`/`SettingsRow` land here rather than in Task 20 because the spawn form is their
first consumer (RN's spawn screen uses the same two components), and Settings reuses them
unchanged. Separators are injected by the group, not drawn by each row — a row cannot know whether
it is the last one.

The agent sheet's rows are **genuinely disabled** when `!agent.selectable`, not merely ignored on
press: RN's previous picker let you tap an unusable agent and silently did nothing. Disabled rows
still render their mark and reason at reduced opacity, so they read as "not yet" rather than
missing. Refresh lives in the sheet rather than on the form, because a stale catalog is something
you discover while looking for an agent that is missing or unauthorised — which is this list.

- [ ] **Step 1: Write the failing tests**

`test/core/widgets/agent_picker_sheet_test.dart`:

```dart
  testWidgets('returns the tapped agent', (tester) async {
    await openSheet(tester, agents: [ranked('codex', selectable: true), ranked('amp', selectable: true)]);

    await tester.tap(find.text('codex'));
    await tester.pumpAndSettle();

    expect(selected, 'codex');
  });

  testWidgets('refuses an unusable agent instead of silently ignoring the tap', (tester) async {
    await openSheet(tester, agents: [ranked('goose', selectable: false, status: 'Needs install')]);

    await tester.tap(find.text('goose'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.text('Needs install'), findsOneWidget);
  });

  testWidgets('reports a catalog error inside the sheet', (tester) async {
    await openSheet(tester, agents: const [], error: 'Your desktop disconnected');

    expect(find.text('Your desktop disconnected'), findsOneWidget);
    expect(find.textContaining('No agents reported'), findsOneWidget);
  });

  testWidgets('refreshes on demand', (tester) async {
    await openSheet(tester, agents: [ranked('codex', selectable: true)]);

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(refreshCalls, 1);
  });
```

`test/feature/spawn/presentation/spawn_screen/ui/spawn_body_test.dart` — a real `SpawnCubit` over a
mocked `SpawnRepository` and a real `SessionsCubit`, covering:

- both mode choices render, `Chat` starts selected, and its hint copy is shown;
- with a chat-only catalog and `tui` selected, the agent row's value changes to the tui default;
- submitting with an empty name shows `'Name and task are required.'` and calls no repository;
- a filled form calls `repository.spawn` once;
- a `CHAT_DRIVER_UNAVAILABLE` failure renders the daemon's detail plus a
  `'Create as Terminal UI instead'` action, and tapping it flips the mode to `tui`;
- when chat mode has no capable agents, the amber warning about installing a Chat-capable agent is
  shown.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/feature/spawn/presentation/spawn_screen/ui/ test/core/widgets/agent_picker_sheet_test.dart`
Expected: FAIL — the widgets do not exist.

- [ ] **Step 3: Write `SettingsGroup` / `SettingsRow`**

`settings_group.dart` — `SettingsGroup` renders an optional uppercased `title`
(`AppTextStyle.style11Bold.copyWith(color: skin.textTertiary, letterSpacing: 1.2)`), a rounded
`skin.bgSurface` body containing `children` interleaved with
`Container(height: 1, color: skin.borderSubtle)`, and an optional `footer`
(`AppTextStyle.style12Regular.copyWith(color: skin.textTertiary)`, `maxLines: 3`).

`SettingsRow` renders a 48pt-min row: optional leading `Icon(icon, size: 17)` tinted
`destructive ? skin.red : skin.textSecondary`, the `label` in `AppTextStyle.style15Regular` tinted
`destructive ? skin.red : skin.textPrimary`, then `trailing` if given, else — in order — an
`AppLoader` when `loading`, the `leading` widget, the `value` in
`AppTextStyle.style13Regular.copyWith(color: valueColor ?? skin.textTertiary)`, and a
`Icons.chevron_right` when `onTap != null`. When `onTap == null` it is a plain `Padding`; otherwise
an `AppInkWell`, disabled when `disabled || loading`.

- [ ] **Step 4: Write the agent sheet**

`agent_picker_sheet.dart` — a `showModalBottomSheet<String>` returning the chosen id, with a header
row carrying the title, subtitle, and a `Refresh` action (an `AppLoader` while `refreshing`), the
error line in `skin.red` when `error != null`, an empty line reading `'No agents reported. Check
that Operator is running on your computer, then refresh.'`, and one row per agent:
`AgentLogo(harness: agent.id, size: 22)`, the label (tinted `skin.blue` when selected), the
`agent.status` tinted `skin.amber` for `authUnknown`/`needsAuth` and `skin.textTertiary` otherwise,
and a trailing check when selected. Unselectable rows are wrapped in
`Opacity(opacity: 0.45, ...)` with a null `onTap`.

Because the sheet owns the refresh but the catalog lives in `SpawnCubit`, the sheet is opened from
a `StatefulBuilder` inside `showModalBottomSheet` so `Refresh` can re-render the list in place
after `onRefresh()` completes.

- [ ] **Step 5: Write the spawn body and screen**

`spawn_body.dart` — a `BlocConsumer<SpawnCubit, SpawnState>` over a scrolling form:

1. the lead paragraph — "Spawn a worker agent. It gets its own isolated workspace, then starts on
   the task you give it.";
2. a `SettingsGroup(footer: 'Agent availability is cached.')` with a **Project** row (value:
   the project's name or `'Choose a project'`, opening `showProjectPickerSheet` with
   `includeAll: false`, `title: 'Project'`, `subtitle: 'Where this agent gets its workspace.'`) and
   an **Agent** row (value: the selected agent's label, `'Loading…'` while
   `CatalogLoadingState`, else `'Choose an agent'`; leading `AgentLogo`), whose tap runs:

```dart
    final chosen = await showAgentPickerSheet(
      context,
      agents: cubit.agents,
      selected: cubit.harness,
      onRefresh: cubit.refreshCatalog,
      error: cubit.state is CatalogFailureState ? 'Could not reach your Operator server' : null,
    );
    if (chosen != null && context.mounted) cubit.setHarness(chosen);
```

3. an `INTERFACE` label over two mode choices — `Chat` / "Native conversation" and
   `Terminal UI` / "Agent's own TUI" — the selected one outlined `skin.blue` and filled
   `skin.tintBlue`, in a `Semantics(container: true)` row;
4. the mode hint, then the amber no-chat-agent warning when
   `cubit.mode == 'chat' && cubit.agents.isEmpty` and the catalog is loaded;
5. `NAME` and `TASK` fields via `AppTextField`, writing `cubit.name` / `cubit.prompt`;
6. the error line, the conditional `'Create as Terminal UI instead'` ghost button, the
   `PrimaryButton.expand(text: 'Spawn agent', isLoading: state is SpawnLoadingState)`, and a
   `Cancel` button popping the route.

On `SpawnSuccessState` the listener calls `sessionsCubit.refresh()` and pops back to the board with
a snackbar naming the new session. **It does not navigate to the session** — see "What M2
deliberately does not include".

The project is seeded on first build from `sessionsCubit.activeProjectId` when that is not
`kAllProjects`, else from the only project when there is exactly one — mirroring RN's
`targetProject()`.

- [ ] **Step 6: Route it and add the entry points**

In `routes_strings.dart`:

```dart
  static const String spawn = '/spawn';
```

In `app_router.dart`:

```dart
      case RoutesStrings.spawn:
        return MaterialPageRoute(
          builder: (context) => BlocProvider(create: (_) => sl<SpawnCubit>(), child: const SpawnScreen()),
          settings: settings,
          fullscreenDialog: true,
        );
```

In `sessions_screen.dart`, add a `FloatingActionButton` with `backgroundColor: context.skin.accent`
and an `Icons.add` child tinted `skin.onAccent`, pushing `RoutesStrings.spawn`. Add a matching
`'New agent'` action to the board's empty state in `sessions_body.dart`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the spawn screen and agent picker"
```

---

### Task 19: Settings logic — build info, theme preference, disconnect

**Files:**
- Create: `packages/mobile/lib/core/utils/app_info.dart`
- Create: `packages/mobile/lib/core/app_themes/colors/theme_preference.dart`
- Create: `packages/mobile/lib/feature/pairing/logic/disconnect.dart`
- Test: `packages/mobile/test/core/utils/app_info_test.dart`
- Test: `packages/mobile/test/feature/pairing/logic/disconnect_test.dart`
- Modify: `packages/mobile/test/core/app_themes/skin_cubit_test.dart`

These three placements come straight from the spec's test-mirroring ledger — `appInfo.test.ts` →
`test/core/utils/app_info_test.dart`, `disconnect.test.ts` →
`test/feature/pairing/logic/disconnect_test.dart`, `themePreference.test.ts` →
`test/core/app_themes/skin_cubit_test.dart`. `disconnect` belongs to `pairing` because it is the
exact inverse of pairing and clears the pairing state; `settings` merely calls it.

**Interfaces:**
- Consumes: `ServerConfigStore`, `CacheHelper`/`CacheKeys` (M0/M1).
- Produces:
  - `class BuildInfo extends Equatable` — `version (String?)`, `build (String?)`
  - `String formatVersion(BuildInfo info)`
  - `String bugReportBody(BuildInfo info, String platform, String osVersion)`
  - `String preferenceLabel(ThemeMode preference)`
  - `Future<void> forgetServer(ServerConfigStore store)`

`formatVersion`/`bugReportBody` stay pure and take a `BuildInfo`; the `package_info_plus` lookup
lives in the screen (Task 20), the same split RN uses between `appInfo.ts` and `expo-constants`.

`preferenceLabel` maps `ThemeMode` rather than RN's own `ThemePreference` union, because M0's
`SkinCubit` already persists `ThemeMode.name` and supports exactly the same three modes — adding a
parallel enum would be two sources of truth for one setting.

`forgetServer` keeps RN's `try`/`finally` shape even though M2 has nothing in the `try` yet:

> The `finally` is the point, not a formality. […] Disconnecting is the one operation that must not
> leave credentials behind: whatever happens upstream, the config gets cleared.

M5 adds `await unregisterFromPush()` inside the existing `try`, and the test below already pins the
guarantee that a throw there still clears the credentials.

- [ ] **Step 1: Write the failing tests**

`app_info_test.dart` (ported from `appInfo.test.ts`):

```dart
void main() {
  group('formatVersion', () {
    test('combines version and build', () {
      expect(formatVersion(const BuildInfo(version: '1.2.0', build: '42')), '1.2.0 (42)');
    });

    test('omits a build number that only repeats the version', () {
      expect(formatVersion(const BuildInfo(version: '1.2.0', build: '1.2.0')), '1.2.0');
    });

    test('omits a missing or blank build number', () {
      expect(formatVersion(const BuildInfo(version: '1.2.0')), '1.2.0');
      expect(formatVersion(const BuildInfo(version: '1.2.0', build: '  ')), '1.2.0');
    });

    test('falls back rather than rendering an empty row', () {
      expect(formatVersion(const BuildInfo()), 'unknown');
      expect(formatVersion(const BuildInfo(build: '42')), 'build 42');
    });
  });

  group('bugReportBody', () {
    test('names the build and platform so a report is actionable', () {
      final body = bugReportBody(const BuildInfo(version: '1.2.0', build: '42'), 'ios', '18.2');
      expect(body, contains('Operator mobile: 1.2.0 (42)'));
      expect(body, contains('Platform: ios 18.2'));
    });

    test('leaves room above the metadata for the user to type', () {
      expect(bugReportBody(const BuildInfo(version: '1.0.0'), 'android', '34').startsWith('\n\n'), isTrue);
    });
  });
}
```

`preferenceLabel`'s three cases are appended to the existing
`test/core/app_themes/skin_cubit_test.dart`, per the ledger: `ThemeMode.light` → `'Light'`,
`ThemeMode.dark` → `'Dark'`, `ThemeMode.system` → `'System'`.

`test/feature/pairing/logic/disconnect_test.dart` (ported from `disconnect.test.ts`, minus the
push step, which lands in M5):

```dart
  test('clears the saved server and re-arms onboarding', () async {
    await CacheHelper.save(CacheKeys.onboardingSkipped, true);
    when(() => store.clear()).thenAnswer((_) async {});

    await forgetServer(store);

    verify(() => store.clear()).called(1);
    expect(CacheHelper.get(CacheKeys.onboardingSkipped), isNull);
  });

  test('still clears onboarding when clearing the config throws', () async {
    await CacheHelper.save(CacheKeys.onboardingSkipped, true);
    when(() => store.clear()).thenAnswer((_) async => throw Exception('keystore unavailable'));

    await expectLater(forgetServer(store), throwsA(isA<Exception>()));

    expect(CacheHelper.get(CacheKeys.onboardingSkipped), isNull);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/utils/app_info_test.dart test/feature/pairing/logic/disconnect_test.dart`
Expected: FAIL — the libraries do not exist.

- [ ] **Step 3: Write the implementations**

```dart
class BuildInfo extends Equatable {
  const BuildInfo({this.version, this.build});

  final String? version;
  final String? build;

  @override
  List<Object?> get props => [version, build];
}

String formatVersion(BuildInfo info) {
  final version = info.version?.trim();
  final build = info.build?.trim();
  if (version == null || version.isEmpty) {
    return build == null || build.isEmpty ? 'unknown' : 'build $build';
  }
  if (build == null || build.isEmpty || build == version) return version;
  return '$version ($build)';
}

String bugReportBody(BuildInfo info, String platform, String osVersion) => [
  '',
  '',
  '---',
  'Operator mobile: ${formatVersion(info)}',
  'Platform: $platform $osVersion',
].join('\n');
```

```dart
String preferenceLabel(ThemeMode preference) {
  switch (preference) {
    case ThemeMode.light:
      return 'Light';
    case ThemeMode.dark:
      return 'Dark';
    case ThemeMode.system:
      return 'System';
  }
}
```

```dart
Future<void> forgetServer(ServerConfigStore store) async {
  try {
    await store.clear();
  } finally {
    await CacheHelper.remove(CacheKeys.onboardingSkipped);
  }
}
```

If `ServerConfigStore` has no `clear()` and `CacheHelper` no `remove()`, add them in this task —
`clear()` deleting host, port, secure and the secure-storage password; `remove(key)` delegating to
`SharedPreferences.remove` — and cover each with a case in their existing test files.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port the settings logic modules"
```

---

### Task 20: The Settings tab

**Files:**
- Create: `packages/mobile/lib/core/widgets/pickers/theme_picker_sheet.dart`
- Create: `packages/mobile/lib/feature/settings/presentation/settings_screen/logic/settings_cubit.dart`
- Create: `packages/mobile/lib/feature/settings/presentation/settings_screen/logic/settings_state.dart`
- Create: `packages/mobile/lib/feature/settings/presentation/settings_screen/ui/settings_screen.dart`
- Create: `packages/mobile/lib/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Modify: `packages/mobile/lib/core/app_routes/home_shell.dart`
- Test: `packages/mobile/test/feature/settings/presentation/settings_screen/logic/settings_cubit_test.dart`
- Test: `packages/mobile/test/feature/settings/presentation/settings_screen/ui/settings_body_test.dart`

**Interfaces:**
- Consumes: `SessionsCubit`, `SkinCubit`, `ServerConfigStore`, `SessionsRepository` (for the
  connection test), `forgetServer` / `formatVersion` / `bugReportBody` / `preferenceLabel` (Task 19),
  `showProjectPickerSheet` (Task 10), `openGitHub` (Task 7), `SettingsGroup`/`SettingsRow`
  (Task 18).
- Produces:
  - `Future<ThemeMode?> showThemePickerSheet(BuildContext context, {required ThemeMode selected})`
  - `sealed class SettingsState` with `SettingsInitialState`, `PingLoadingState`,
    `PingSuccessState(int sessionCount)`, `PingFailureState(Failure failure)`,
    `ForgetSuccessState`
  - `class SettingsCubit extends Cubit<SettingsState>` with `Future<void> testConnection()` and
    `Future<void> forget()`
  - `SettingsScreen`, `SettingsBody`

**Connection is one row, not a form.** The pairing flow already owns camera scan, permission
fallbacks and the manual-entry screen, so editing a connection and creating one go through the same
door — the row pushes `RoutesStrings.pairingScan`.

"Test connection" reuses `SessionsRepository.getBoard()` and reports the session count, exactly as
RN's `pingServer` calls `GET /sessions` and returns `data.sessions.length`. A stale failure is
dropped once the board reports a live connection again, so the row does not keep showing a scary
error while the app is connected.

The About section's version comes from `PackageInfo.fromPlatform()`, mapped to `BuildInfo(version:
info.version, build: info.buildNumber)`.

"Disconnect & forget server" confirms via `AppDialog.confirm` with the destructive styling, then on
`ForgetSuccessState` navigates with `pushNamedAndRemoveUntil(RoutesStrings.onboarding, (_) => false)`
— a user with no server should be offered pairing again, not dropped on a bare board.

- [ ] **Step 1: Write the failing tests**

`settings_cubit_test.dart`:

```dart
  blocTest<SettingsCubit, SettingsState>(
    'reports the session count on a successful test',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(GlobalResponse(
          data: const BoardSnapshot(sessions: [SessionModel(id: 'a'), SessionModel(id: 'b')]),
        )),
      );
      return SettingsCubit(repository, store);
    },
    act: (cubit) => cubit.testConnection(),
    expect: () => [
      isA<PingLoadingState>(),
      isA<PingSuccessState>().having((s) => s.sessionCount, 'sessionCount', 2),
    ],
  );

  blocTest<SettingsCubit, SettingsState>(
    'reports a failed test',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'nope', statusCode: 401)),
      );
      return SettingsCubit(repository, store);
    },
    act: (cubit) => cubit.testConnection(),
    expect: () => [isA<PingLoadingState>(), isA<PingFailureState>()],
  );

  blocTest<SettingsCubit, SettingsState>(
    'clears the saved server on forget',
    build: () {
      when(() => store.clear()).thenAnswer((_) async {});
      return SettingsCubit(repository, store);
    },
    act: (cubit) => cubit.forget(),
    expect: () => [isA<ForgetSuccessState>()],
    verify: (_) => verify(() => store.clear()).called(1),
  );
```

`settings_body_test.dart`:

- the Connection row shows `host:port` when paired and `'Not connected'` otherwise;
- tapping "Test connection" renders `'Connected — 2 sessions'` (and `'1 session'` in the singular);
- the Projects row shows the active project's name, `'All projects'` when unscoped;
- the Theme row shows `preferenceLabel` of the current mode, and choosing Light from the sheet
  calls `SkinCubit.setSkin` with a light skin;
- the About section renders the formatted version;
- "Disconnect & forget server" opens a confirmation, declining leaves `store.clear` uncalled and
  confirming calls it once;
- **no Notifications section is present** — `expect(find.text('Agent notifications'), findsNothing)`,
  pinning the M5 deferral so it is a deliberate absence rather than an oversight.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/feature/settings/`
Expected: FAIL — the cubit and widgets do not exist.

- [ ] **Step 3: Write the theme sheet**

`theme_picker_sheet.dart` — a `showModalBottomSheet<ThemeMode>` with the title `'Theme'`, the
subtitle `'Applies across the app.'`, and three rows (`System`, `Light`, `Dark`) built from
`preferenceLabel`, each popping its `ThemeMode` and showing a check when selected.

- [ ] **Step 4: Write the cubit**

```dart
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._repository, this._store) : super(const SettingsInitialState());

  final SessionsRepository _repository;
  final ServerConfigStore _store;

  Future<void> testConnection() async {
    emit(const PingLoadingState());
    final result = await _repository.getBoard();
    result.when(
      onSuccess: (response) => emit(PingSuccessState(response.data?.sessions.length ?? 0)),
      onFailure: (failure) => emit(PingFailureState(failure)),
    );
  }

  Future<void> forget() async {
    await forgetServer(_store);
    emit(const ForgetSuccessState());
  }
}
```

- [ ] **Step 5: Write the body and screen**

`settings_body.dart` — a `BlocConsumer<SettingsCubit, SettingsState>` over four groups:

1. **Connection** (`footer: "Your PC's Tailscale name / 100.x address, or its LAN IP on the same
   Wi-Fi."`) — a "Connect Operator" row showing `'${config.host}:${config.httpPort}'` or
   `'Not connected'`, with a status dot leading when paired, pushing `RoutesStrings.pairingScan`;
   and a "Test connection" row, disabled when unpaired, showing
   `'Connected — $n session${n == 1 ? '' : 's'}'` in `skin.green` on success or
   `describeConnectionFailure(...).title` in `skin.red` on failure.
2. **Projects** (`title: 'Projects'`, `footer: 'Scopes the Agents and PRs tabs.'`) — an "Active
   project" row opening `showProjectPickerSheet`; on a selection it calls
   `sessionsCubit.setActiveProject(id)` and then `onOpenBoard()`, so the choice and its effect land
   in one step.
3. **Appearance** — a "Theme" row opening `showThemePickerSheet` and applying the result via
   `context.read<SkinCubit>()` (`setSystemSkin()` for `ThemeMode.system`, else
   `setSkin(const LightSkin())` / `setSkin(const DarkSkin())`).
4. **About** — a "Version" row (no `onTap`) showing `formatVersion(buildInfo)`; a "Report a problem"
   row calling `openGitHub('https://github.com/OmarAly92/operator/issues/new?body=' +
   Uri.encodeComponent(bugReportBody(buildInfo, platform, osVersion)))`; and a destructive
   "Disconnect & forget server" row.

`buildInfo` is loaded once in `initState` via `PackageInfo.fromPlatform()`, held in state, and
rendered as `'unknown'` until it resolves — `formatVersion(const BuildInfo())` already returns
exactly that, so no separate loading branch is needed.

`settings_screen.dart` — a `Scaffold` with `GlobalAppbar.main(titleText: 'Settings')`, wrapped in
`BlocProvider(create: (_) => sl<SettingsCubit>())`, taking `onOpenBoard` from the shell.

- [ ] **Step 6: Register and mount**

Add `_settingsFeatureSetup()` to `ServiceLocator.init()` registering `SettingsCubit` as a factory
over `SessionsRepository` and `ServerConfigStore`; extend `service_locator_test.dart`. In
`home_shell.dart`, replace the index-3 placeholder with
`SettingsScreen(onOpenBoard: () => setState(() => _index = 0))`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", full suite green — four tabs live.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the Settings tab"
```

---

## Milestone exit criteria

M2 is done when the spec's bar — **"Four tabs live"** — holds against a real daemon on a real
phone, plus the two things this milestone owes the ones after it:

- [ ] All four tabs render and switch: Agents, Orchestrator, PRs, Settings.
- [ ] The board, the PRs tab and the Orchestrator tab all read **one** `SessionsCubit` instance —
      verify by watching the daemon log for exactly one `/sessions` + `/orchestrators` +
      `/projects` triple per 8s tick, not three.
- [ ] A wrong password costs **one** failed auth attempt per tick, not three — the reason Task 3
      exists. Check the daemon does not arm its 5-failure lockout within two ticks.
- [ ] The project switcher scopes the Agents and PRs tabs, and does **not** scope Orchestrator.
- [ ] Spawning an agent creates a session that appears on the board within one poll tick.
- [ ] `flutter analyze` clean and `flutter test` green from `packages/mobile`.

### Spec ledger rows closed by this milestone

| Ledger row | Landed at | Task |
|---|---|---|
| `agentPicker.test.ts` | `test/feature/spawn/logic/agent_picker_test.dart` | 15 |
| `githubLink.test.ts` | `test/feature/pull_request/logic/github_link_test.dart` | 7 |
| `orchestratorView.test.ts` | `test/feature/orchestrator/logic/orchestrator_view_test.dart` | 12 |
| `prView.test.ts` | `test/feature/pull_request/logic/pr_view_test.dart` | 6, 8 |
| `appInfo.test.ts` | `test/core/utils/app_info_test.dart` | 19 |
| `disconnect.test.ts` | `test/feature/pairing/logic/disconnect_test.dart` | 19 |
| `themePreference.test.ts` | `test/core/app_themes/skin_cubit_test.dart` | 19 |
| `chatError.test.ts` | `test/core/error_handling/chat_preflight_test.dart` (relocated — see deviations) | 11 |

`sheet_result_test.dart` stays deliberately unported. Every remaining row belongs to `chat` (M3),
`terminal` (M4), or push/voice/telemetry (M5).

### What M3 inherits

The three omissions in "What M2 deliberately does not include" are the seams M3 lands into:
`PrCard` and `OrchestratorCard` each have one action to add, and `SpawnBody`'s success listener has
one navigation to add, once `RoutesStrings.session` exists. None of them needs the surrounding
widget restructured.
