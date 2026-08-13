# Flutter Mobile Port — M3 (Chat) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A chat session is usable end to end on the phone — open a chat-mode session from
the board, read its timeline, watch it stream live, answer approvals and elicitations, send
messages with attachments, steer or interrupt a running turn, change turn settings, compact,
rename, and roll back.

**Architecture:** One new feature, `lib/feature/chat/`, owning everything conversation-shaped.
Its spine is a **per-session `ChatCubit`** holding a list of conversation *pages* merged into one
snapshot, refreshed by a debounced reload that a long-lived **SSE stream** triggers. The daemon
owns durable replay; the phone persists only the event cursor. The chat screen is pushed above
the four-tab shell by a new session route that resolves the daemon-authoritative session mode.
Every module with an RN test lands logic-and-test first, before the widget that consumes it.

**Tech Stack:** Everything from M2, plus `image_picker` (composer image attachments) and
`file_selector` (composer text-file attachments). Chat's realtime transport is **SSE over Dio's
`ResponseType.stream`**, not the mux socket — the mux carries board patches and terminal I/O only.

**Spec:** `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`

## Global Constraints

- Source spec: `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`.
- Source of truth for RN behavior: `packages/mobile_rn/` (frozen reference). Quoted verbatim
  throughout this plan; file paths below are relative to `packages/mobile_rn/` unless stated
  otherwise. One module comes from `packages/shared/chat/ansi.ts`, which is outside `mobile_rn`.
- Conventions are the `flutter-knowledge` skill. Where the mirrored RN source contradicts it, the
  skill wins. Invoke `flutter-testing` before the first test file, exactly as M0, M1 and M2 did.
- Cubit only — never `Bloc` with events. Static-only classes are `sealed class X`. **No comments**
  except non-obvious business rules. Single quotes, `const` constructors, full 8-digit hex colors,
  `final` locals. No `flutter_screenutil` extensions outside `AppTextStyle`. No `drift`, no
  `freezed`, no `json_serializable`, no `build_runner`.
- Verification after every task: `flutter analyze` clean and `flutter test` green, both run from
  `packages/mobile`.
- **Baseline this plan starts from: `flutter analyze` → "No issues found!", `flutter test` →
  416/416 green.** Every task's expected test count is baseline-plus-its-own; never let the suite
  shrink.
- New dependency versions below were verified conflict-free against the exact
  `packages/mobile/pubspec.yaml` this plan starts from (`flutter pub add image_picker
  file_selector`, then `flutter analyze` → "No issues found!", `flutter test` → 416/416 green,
  then reverted). Do not re-litigate the versions — add them as pinned.
- Package name is `operator_mobile`; imports are `package:operator_mobile/...`.
- All app state resolves under `~/.operator` — unaffected by this milestone, called out per
  `AGENTS.md`'s hard rule for completeness.

### New dependencies (pinned, verified conflict-free)

```yaml
dependencies:
  image_picker: ^1.2.3
  file_selector: ^1.1.0
```

`file_picker` was tried first and **rejected**: `package_info_plus ^10.2.1` (added in M2) requires
`win32 ^6.0.1` while every `file_picker` from 8.3.3 up requires `win32 ^5.9.0`, so pub resolves
`file_picker` down to **3.0.4** — a 2021 release. `file_selector` is the flutter.dev-maintained
plugin, has no `win32` constraint, and covers the one thing the composer needs (pick text files).

### What M3 deliberately does not include

The RN chat screen links to three surfaces that do not exist yet and one subsystem the spec
assigns to a later milestone. Their controls are **omitted, not stubbed**, exactly as M2 handled
the same situation.

| Omitted | Why | Lands in |
|---|---|---|
| The menu's "Open Terminal UI" row and all of `useInterfaceTransition.ts` (start/cancel/poll, the switching banner, the drain-vs-interrupt dialog) | Every phase of an interface transition ends in the terminal screen. `terminal` is M4; shipping the handoff now would hand off to nothing. | M4 |
| The menu's "Open worktree shell" row, `openSessionShell`, `closeShellTerminal`, and the shell action on the unavailable/stopped banners | Same destination — the shell is a terminal route. | M4 |
| `lib/session/sendRoute.ts` → ledger row `test/feature/sessions/logic/send_route_test.dart` | Its only consumer is `TerminalSessionScreen.tsx`: it decides when a composer send is re-routed *to the PTY*. Chat has no PTY. | M4 |
| The menu's "Open preview" row | `preview` is M5 per the spec's build order. | M5 |
| The composer's `MicKey` and all of `lib/voice/*` | `voice` is M5 per the spec's build order. The composer is built with the mic slot absent, not disabled. | M5 |

`keyboardInset.ts` **is** ported here (Task 10), because the spec's ledger assigns it to
`test/feature/chat/logic/keyboard_inset_test.dart` and the chat composer dock is its first
consumer. Its RN test file also covers `CONTROL_KEYS` from `lib/session/keys.ts`; that half is a
terminal key row and is **not** ported here — M4 ports `keys.ts` and adds those cases to a
`test/feature/terminal/logic/keys_test.dart`. The ledger row is satisfied by the `dockInset` half
and M6's parity sweep accounts for the split.

### Deliberate deviations from the RN reference

| RN source | What it does | Why M3 departs |
|---|---|---|
| `lib/chat/api.ts` `streamConversationEvents` uses `expo/fetch` | React Native's global `fetch` does not expose a streaming body under Hermes, so Expo's polyfill is used. | Dart has no `EventSource` on mobile either, but Dio already speaks streams: `ResponseType.stream` yields a `ResponseBody` whose `.stream` is a `Stream<Uint8List>`. The spec anticipates exactly this ("these port as pure functions over a `ResponseType.stream` Dio response"). |
| `lib/chat/api.ts` — no explicit timeout on the event stream | `expoFetch` has no request timeout at all. | `DioConsumer` sets `receiveTimeout: 12s` globally (the spec's load-bearing Tailscale rule), which would **kill an idle SSE stream after twelve seconds**. Task 15 passes `receiveTimeout: Duration.zero` for this one request. Verified against `dio-5.9.0/lib/src/adapters/io_adapter.dart:162` — the adapter reads `options.receiveTimeout ?? Duration.zero` and only arms the timer `if (receiveTimeout > Duration.zero)`. Passing `null` would **not** work: `Options.compose` resolves `receiveTimeout ?? baseOpt.receiveTimeout`, so null inherits the 12s base. |
| `lib/chat/types.ts` `ActivityDetail` is an open bag (`[key: string]: unknown`) with ~50 optional fields | TypeScript structural typing lets the renderer read any field and lets unknown provider fields ride along untouched. | `ActivityDetailModel` keeps the parsed `Map<String, dynamic> raw` and exposes typed getters for the fields the UI actually reads. Fifty nullable Dart fields would be write-only ceremony, and re-serializing into a fixed shape would silently drop provider fields Operator does not model yet. |
| `lib/chat/useConversation.ts` — a React hook with 15 `useState` cells | Re-renders on every state cell. | One `ChatCubit` with plain fields and a revision-carrying `ChatReadyState(revision)`, the pattern `PullRequestCubit` established in M2. Banners, action errors and pending sends are **fields**, not cubit states, because the screen renders several of them at once — a state machine would make them mutually exclusive, which is the opposite of the RN behavior. |
| `useConversation.ts` persists the event cursor in `AsyncStorage` under `opr.chat.events.<host>.<port>.<sessionId>` | Per-server, per-session cursor. | Same key, in `CacheHelper` (`SharedPreferences`). It is a resume hint, not a secret, so it does not go to `flutter_secure_storage`. `CacheKeys` gains its first *method* (`chatEventCursor(...)`) beside its constants. |
| `ChatSessionScreen.tsx` `Alert.alert` confirmations | React Native's imperative alert. | `AppDialog.confirm` (M1) and `context.showSnackBar` (M1), which is what every other Flutter surface in this app already uses. |
| `ChatComposer.tsx` uses `expo-image-picker` (`base64: true`) and `expo-document-picker` | Expo's pickers return base64 inline. | `image_picker` returns `XFile`s; the composer reads bytes and base64-encodes them itself. `file_selector` replaces the document picker for the reasons in the dependency note above. Limits (8 attachments, 10 MB per image, 25 MB total, 500 KB per embedded text file) and their exact copy are ported unchanged. |
| `ChatTimeline.tsx` `FlatList` with `maintainVisibleContentPosition` and `scrollToIndex` | RN list virtualization. | `ListView.builder` with a `ScrollController`; "jump to latest" and the conversation map's jump-to-sequence use `Scrollable.ensureVisible` on a `GlobalKey` per group. Flutter has no `scrollToIndex`, and index-to-offset estimation is what RN's own `onScrollToIndexFailed` fallback exists to paper over. |
| `app/session/[id].tsx` renders `TerminalSessionScreen` for `mode === "tui"` | Both renderers exist in RN. | The route's `tui` branch renders an honest "Terminal UI is not in this build yet" panel until M4 replaces it. Guessing Chat for a TUI session would attach a chat controller to a PTY session — the exact failure RN's own comment warns about ("never guess TUI merely because the local cache is cold", and the converse). |
| `ChatSessionScreen.tsx` `onPullRequests` does `router.push("/(tabs)/prs")` | Expo Router addresses a tab by URL. | `HomeShell` gains a `static final ValueNotifier<int> selectedTab`; the menu sets the active project, sets the tab, and pops back to the shell. Flutter's `Navigator` has no addressable tab route, and threading a callback down four widget layers to do it would be worse. |

### Cross-feature imports introduced here, and why

`chat` imports `SessionModel`/`OrchestratorModel` from `sessions` (the route resolves the session
being opened) and `SessionsCubit` (the menu's project switch, and the resume/restore actions that
already live on `SessionsRepository`). Nothing imports *from* `chat` except the new session route
and the three entry points in Task 26. `ansi.dart` lands in `chat/logic/` per the spec's ledger
even though M4's terminal will also want `caretNotation`; M4 imports it rather than duplicating it.

---

### Task 1: M3 dependencies, endpoints, and the cursor cache key

**Files:**
- Modify: `packages/mobile/pubspec.yaml`
- Modify: `packages/mobile/ios/Runner/Info.plist`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Modify: `packages/mobile/lib/core/helpers/cache/cache_keys.dart`
- Test: `packages/mobile/test/core/api/end_points_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `image_picker` and `file_selector` available to Task 23.
  - On `EndPoints`: `events`, `sessionConversation(String)`, `conversationMessages(String)`,
    `conversationSteer(String)`, `conversationInterrupt(String)`, `conversationCompact(String)`,
    `conversationModels(String)`, `conversationConfigOptions(String)`,
    `conversationConfigOption(String, String)`, `conversationSkills(String)`,
    `conversationSettings(String)`, `conversationTitle(String)`, `conversationMcpReload(String)`,
    `conversationApprovalResolve(String, String)`, `conversationInputResolve(String, String)`,
    `conversationTurnRollback(String, String)`, `sessionAttachments(String)`,
    `sessionWorkspaceFiles(String)`, `sessionResumeAgent(String)`.
  - `CacheKeys.chatEventCursor(String host, String port, String sessionId)`.

The new endpoint helpers percent-encode their path segments, because `chat/api.ts` does
(`encodeURIComponent(sessionId)`, `encodeURIComponent(requestId)`, `encodeURIComponent(turnId)`).
The M1/M2 board helpers above them do not, mirroring `lib/api.ts`, which also does not — that
asymmetry is RN's, and it is preserved rather than tidied.

iOS needs the photo-library usage string before `image_picker` can be used at all; without it the
picker crashes the app on first tap rather than failing softly.

- [x] **Step 1: Add the two dependencies**

In `packages/mobile/pubspec.yaml`, under `dependencies:`, after `package_info_plus: ^10.2.1`:

```yaml
  image_picker: ^1.2.3
  file_selector: ^1.1.0
```

- [x] **Step 2: Declare the iOS photo-library purpose string**

In `packages/mobile/ios/Runner/Info.plist`, inside the top-level `<dict>`:

```xml
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Operator attaches images you pick to the message you send your agent.</string>
```

- [x] **Step 3: Write the failing endpoint test**

`packages/mobile/test/core/api/end_points_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';

void main() {
  group('conversation endpoints', () {
    test('address the daemon conversation routes', () {
      expect(EndPoints.events, '/api/v1/events');
      expect(EndPoints.sessionConversation('w-1'), '/api/v1/sessions/w-1/conversation');
      expect(EndPoints.conversationMessages('w-1'), '/api/v1/sessions/w-1/conversation/messages');
      expect(EndPoints.conversationSteer('w-1'), '/api/v1/sessions/w-1/conversation/steer');
      expect(EndPoints.conversationInterrupt('w-1'), '/api/v1/sessions/w-1/conversation/interrupt');
      expect(EndPoints.conversationCompact('w-1'), '/api/v1/sessions/w-1/conversation/compact');
      expect(EndPoints.conversationModels('w-1'), '/api/v1/sessions/w-1/conversation/models');
      expect(EndPoints.conversationSkills('w-1'), '/api/v1/sessions/w-1/conversation/skills');
      expect(EndPoints.conversationSettings('w-1'), '/api/v1/sessions/w-1/conversation/settings');
      expect(EndPoints.conversationTitle('w-1'), '/api/v1/sessions/w-1/conversation/title');
      expect(EndPoints.conversationMcpReload('w-1'), '/api/v1/sessions/w-1/conversation/mcp/reload');
      expect(EndPoints.conversationConfigOptions('w-1'), '/api/v1/sessions/w-1/conversation/config-options');
      expect(
        EndPoints.conversationConfigOption('w-1', 'fast'),
        '/api/v1/sessions/w-1/conversation/config-options/fast',
      );
      expect(
        EndPoints.conversationApprovalResolve('w-1', 'req-1'),
        '/api/v1/sessions/w-1/conversation/approvals/req-1/resolve',
      );
      expect(
        EndPoints.conversationInputResolve('w-1', 'req-1'),
        '/api/v1/sessions/w-1/conversation/inputs/req-1/resolve',
      );
      expect(
        EndPoints.conversationTurnRollback('w-1', 't-1'),
        '/api/v1/sessions/w-1/conversation/turns/t-1/rollback',
      );
      expect(EndPoints.sessionAttachments('w-1'), '/api/v1/sessions/w-1/attachments');
      expect(EndPoints.sessionWorkspaceFiles('w-1'), '/api/v1/sessions/w-1/workspace/files');
      expect(EndPoints.sessionResumeAgent('w-1'), '/api/v1/sessions/w-1/resume-agent');
    });

    test('escape identifiers so a slash cannot forge a route', () {
      expect(EndPoints.sessionConversation('a/b'), '/api/v1/sessions/a%2Fb/conversation');
      expect(
        EndPoints.conversationApprovalResolve('w-1', 'req 1/x'),
        '/api/v1/sessions/w-1/conversation/approvals/req%201%2Fx/resolve',
      );
    });
  });
}
```

- [x] **Step 4: Run it to verify it fails**

Run: `flutter test test/core/api/end_points_test.dart`
Expected: FAIL — `events`, `sessionConversation` and the rest are not defined.

- [x] **Step 5: Add the endpoints**

In `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`, after `notifications`:

```dart
  static const String events = '/api/v1/events';
```

and after `prMerge`:

```dart
  static String sessionConversation(String sessionId) => '${_session(sessionId)}/conversation';
  static String conversationMessages(String sessionId) => '${sessionConversation(sessionId)}/messages';
  static String conversationSteer(String sessionId) => '${sessionConversation(sessionId)}/steer';
  static String conversationInterrupt(String sessionId) => '${sessionConversation(sessionId)}/interrupt';
  static String conversationCompact(String sessionId) => '${sessionConversation(sessionId)}/compact';
  static String conversationModels(String sessionId) => '${sessionConversation(sessionId)}/models';
  static String conversationSkills(String sessionId) => '${sessionConversation(sessionId)}/skills';
  static String conversationSettings(String sessionId) => '${sessionConversation(sessionId)}/settings';
  static String conversationTitle(String sessionId) => '${sessionConversation(sessionId)}/title';
  static String conversationMcpReload(String sessionId) => '${sessionConversation(sessionId)}/mcp/reload';
  static String conversationConfigOptions(String sessionId) =>
      '${sessionConversation(sessionId)}/config-options';
  static String conversationConfigOption(String sessionId, String optionId) =>
      '${sessionConversation(sessionId)}/config-options/${Uri.encodeComponent(optionId)}';
  static String conversationApprovalResolve(String sessionId, String requestId) =>
      '${sessionConversation(sessionId)}/approvals/${Uri.encodeComponent(requestId)}/resolve';
  static String conversationInputResolve(String sessionId, String requestId) =>
      '${sessionConversation(sessionId)}/inputs/${Uri.encodeComponent(requestId)}/resolve';
  static String conversationTurnRollback(String sessionId, String turnId) =>
      '${sessionConversation(sessionId)}/turns/${Uri.encodeComponent(turnId)}/rollback';
  static String sessionAttachments(String sessionId) => '${_session(sessionId)}/attachments';
  static String sessionWorkspaceFiles(String sessionId) => '${_session(sessionId)}/workspace/files';
  static String sessionResumeAgent(String sessionId) => '${_session(sessionId)}/resume-agent';

  static String _session(String sessionId) => '$sessions/${Uri.encodeComponent(sessionId)}';
```

- [x] **Step 6: Add the cursor cache key**

In `packages/mobile/lib/core/helpers/cache/cache_keys.dart`, after `activeProjectId`:

```dart
  static String chatEventCursor(String host, String port, String sessionId) =>
      'opr.chat.events.$host.$port.$sessionId';
```

- [x] **Step 7: Resolve and verify**

Run: `flutter pub get && flutter analyze && flutter test`
Expected: dependencies resolve, "No issues found!", 418/418 tests pass.

- [x] **Step 8: Commit**

```bash
git add packages/mobile/pubspec.yaml packages/mobile/pubspec.lock packages/mobile/ios/Runner/Info.plist packages/mobile/lib packages/mobile/test
git commit -m "chore(mobile): add M3 dependencies and the conversation endpoints"
```

---

### Task 2: SSE frames (`sse.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/data/sse.dart`
- Test: `packages/mobile/test/feature/chat/data/sse_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class SseSplit` — `frames (List<String>)`, `remainder (String)`
  - `SseSplit takeSseFrames(String buffer)`
  - `class ConversationEventModel extends Equatable` — `seq (int)`, `projectId`, `sessionId`,
    `type`, `payload (Map<String, dynamic>?)`, `createdAt` (all but `seq` nullable);
    `bool get touchesConversation => payload?['conversationId'] != null`
  - `ConversationEventModel? parseSseFrame(String frame)`

The spec singles these three behaviors out as field experience that must survive the port:
proxies send **CRLF** frame boundaries; older daemons omit `seq`, so the SSE `id:` is the
fallback; malformed `data` is dropped, not thrown. The test below is the ledger's
`chat/sse.test.ts` row, mirrored 1:1.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/data/sse_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

void main() {
  group('mobile conversation SSE', () {
    test('keeps an incomplete tail while reading multiple LF frames', () {
      final result = takeSseFrames('id: 1\ndata: {"seq":1}\n\nid: 2\ndata: {"seq":2}\n\nid: 3\nda');
      expect(result.frames, hasLength(2));
      expect(result.remainder, 'id: 3\nda');
    });

    test('accepts CRLF boundaries from proxies', () {
      final result = takeSseFrames('id: 4\r\ndata: {"seq":4}\r\n\r\n');
      expect(result.frames, ['id: 4\r\ndata: {"seq":4}']);
      expect(parseSseFrame(result.frames.first)?.seq, 4);
    });

    test('uses the SSE id when old daemons omit seq and ignores malformed data', () {
      expect(parseSseFrame('id: 9\ndata: {"projectId":"p","type":"session_updated"}')?.seq, 9);
      expect(parseSseFrame('id: 10\ndata: nope'), isNull);
    });

    test('reports whether an event touches a conversation', () {
      final touching = parseSseFrame('id: 1\ndata: {"seq":1,"payload":{"conversationId":"c-1"}}');
      expect(touching?.touchesConversation, isTrue);
      expect(parseSseFrame('id: 2\ndata: {"seq":2}')?.touchesConversation, isFalse);
    });

    test('drops a frame with no data line at all', () {
      expect(parseSseFrame('id: 3\n: keep-alive'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/data/sse_test.dart`
Expected: FAIL — `package:operator_mobile/feature/chat/data/sse.dart` does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/data/sse.dart`:

```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';

final RegExp _boundary = RegExp(r'\r?\n\r?\n');

class SseSplit {
  const SseSplit({required this.frames, required this.remainder});

  final List<String> frames;
  final String remainder;
}

class ConversationEventModel extends Equatable {
  const ConversationEventModel({
    required this.seq,
    this.projectId,
    this.sessionId,
    this.type,
    this.payload,
    this.createdAt,
  });

  final int seq;
  final String? projectId;
  final String? sessionId;
  final String? type;
  final Map<String, dynamic>? payload;
  final String? createdAt;

  bool get touchesConversation => payload?['conversationId'] != null;

  @override
  List<Object?> get props => [seq, projectId, sessionId, type, payload, createdAt];
}

SseSplit takeSseFrames(String buffer) {
  final frames = <String>[];
  var remainder = buffer;
  var boundary = _boundary.firstMatch(remainder);
  while (boundary != null) {
    frames.add(remainder.substring(0, boundary.start));
    remainder = remainder.substring(boundary.end);
    boundary = _boundary.firstMatch(remainder);
  }
  return SseSplit(frames: frames, remainder: remainder);
}

ConversationEventModel? parseSseFrame(String frame) {
  var id = 0;
  final data = <String>[];
  for (final raw in frame.replaceAll('\r', '').split('\n')) {
    if (raw.startsWith('id:')) {
      id = int.tryParse(raw.substring(3).trim()) ?? 0;
    } else if (raw.startsWith('data:')) {
      data.add(raw.substring(5).trimLeft());
    }
  }
  if (data.isEmpty) return null;

  try {
    final decoded = jsonDecode(data.join('\n'));
    if (decoded is! Map<String, dynamic>) return null;
    final seq = decoded['seq'];
    return ConversationEventModel(
      seq: seq is num ? seq.toInt() : id,
      projectId: decoded['projectId'] as String?,
      sessionId: decoded['sessionId'] as String?,
      type: decoded['type'] as String?,
      payload: decoded['payload'] as Map<String, dynamic>?,
      createdAt: decoded['createdAt'] as String?,
    );
  } catch (_) {
    return null;
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/data/sse_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 423/423 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port the conversation SSE frame reader"
```

---

### Task 3: Conversation action errors (`conversationErrors.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/conversation_errors.dart`
- Test: `packages/mobile/test/feature/chat/logic/conversation_action_test.dart`

**Interfaces:**
- Consumes: `Failure` (`core/error_handling/failures/failure.dart`).
- Produces:
  - `String? conversationErrorCode(Failure failure)`
  - `String conversationActionError(Failure failure)`
  - `bool conversationActionUnsupported(String action, String? code)` — `action` is one of
    `'steer'`, `'compact'`, `'mcp'`
  - `const Set<String> kPermanentConversationCodes`

RN reads `error.code` off a thrown `ApiError`. Dart's equivalent is already carried:
`handleDioError` puts the daemon's `code` on `ServerFailure.apiStatus` and its `requestId` in
`validationErrors`. `conversationErrorCode` therefore reads `apiStatus`, and the `requestId` the
spec insists must not be discarded stays reachable on the same failure.

`kPermanentConversationCodes` is `classifyConversationError`'s permanent set from
`useConversation.ts`, lifted here so Task 17 can branch on it without redefining the list.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/conversation_action_test.dart` (ported from
`chat/conversationAction.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_errors.dart';

Failure failure(String? code, [String message = 'conflict']) =>
    ServerFailure(error: message, message: message, statusCode: 409, apiStatus: code);

void main() {
  group('mobile conversation action errors', () {
    test('turns protocol codes into instructions the user can act on', () {
      expect(conversationActionError(failure('CHAT_NO_ACTIVE_TURN')), contains('Queue it as a new message'));
      expect(
        conversationActionError(failure('CHAT_COMPACTION_BUSY')),
        'Stop the current turn before compacting history.',
      );
      expect(
        conversationActionError(failure('CHAT_MCP_RELOAD_UNSUPPORTED')),
        'This agent cannot reload its MCP servers.',
      );
      expect(conversationActionError(failure('CHAT_STEER_UNSUPPORTED')), contains('Queue a new message'));
      expect(conversationActionError(failure('CHAT_TURN_RUNNING')), contains('Stop the current turn'));
      expect(conversationActionError(failure('CHAT_REQUEST_NOT_PENDING')), contains('already answered'));
    });

    test('keeps the daemon detail for codes that carry their own message', () {
      expect(
        conversationActionError(failure('CHAT_TURN_NOT_STEERABLE', 'The turn is draining.')),
        startsWith('The turn is draining.'),
      );
      expect(
        conversationActionError(failure('CHAT_PROVIDER_REFUSED', 'The provider said no.')),
        'The provider said no.',
      );
      expect(conversationActionError(failure(null, 'Could not reach your Operator server')),
          'Could not reach your Operator server');
    });

    test('preserves typed refusal identities so unsupported controls can withdraw', () {
      final error = failure('CHAT_STEER_UNSUPPORTED');
      expect(conversationErrorCode(error), 'CHAT_STEER_UNSUPPORTED');
      expect(conversationActionUnsupported('steer', conversationErrorCode(error)), isTrue);
      expect(conversationActionUnsupported('compact', conversationErrorCode(error)), isFalse);
    });

    test('names the codes that make a conversation permanently unavailable', () {
      expect(kPermanentConversationCodes, contains('SESSION_MODE_MISMATCH'));
      expect(kPermanentConversationCodes, contains('CHAT_RESUME_FAILED'));
      expect(kPermanentConversationCodes, isNot(contains('CHAT_COMPACTION_BUSY')));
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/conversation_action_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/conversation_errors.dart`:

```dart
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

const Set<String> kPermanentConversationCodes = {
  'SESSION_MODE_MISMATCH',
  'SESSION_NOT_FOUND',
  'SESSION_MODE_UNSUPPORTED',
  'CHAT_DRIVER_UNAVAILABLE',
  'CHAT_DRIVER_INCOMPATIBLE',
  'CHAT_AUTH_REQUIRED',
  'CHAT_RESUME_FAILED',
  'CHAT_CONTROLLER_NOT_READY',
};

const Map<String, String> _unsupportedCodes = {
  'steer': 'CHAT_STEER_UNSUPPORTED',
  'compact': 'CHAT_COMPACTION_UNSUPPORTED',
  'mcp': 'CHAT_MCP_RELOAD_UNSUPPORTED',
};

String? conversationErrorCode(Failure failure) {
  final code = failure.apiStatus?.trim();
  return code == null || code.isEmpty ? null : code;
}

String conversationActionError(Failure failure) {
  switch (conversationErrorCode(failure)) {
    case 'CHAT_NO_ACTIVE_TURN':
      return 'The turn finished before this guidance landed. Queue it as a new message instead.';
    case 'CHAT_STEER_UNSUPPORTED':
      return 'This agent cannot take guidance while it is working. Queue a new message instead.';
    case 'CHAT_STEER_TEXT_REQUIRED':
      return 'Enter guidance before steering the running turn.';
    case 'CHAT_TURN_NOT_STEERABLE':
      final detail = failure.message.trim();
      final head = detail.isEmpty ? 'This turn cannot be steered right now.' : detail;
      return '$head Try again when it finishes, or queue a new message.';
    case 'CHAT_COMPACTION_BUSY':
      return 'Stop the current turn before compacting history.';
    case 'CHAT_COMPACTION_UNSUPPORTED':
      return 'This agent cannot compact its history.';
    case 'CHAT_MCP_RELOAD_UNSUPPORTED':
      return 'This agent cannot reload its MCP servers.';
    case 'CHAT_TURN_RUNNING':
      return 'Stop the current turn before rolling back conversation history.';
    case 'CHAT_TURN_NOT_ROLLBACKABLE':
      return 'That turn never reached the agent, so there is nothing to roll back.';
    case 'CHAT_ROLLBACK_UNSUPPORTED':
      return 'This agent cannot roll back conversation history.';
    case 'CHAT_TURN_NOT_FOUND':
      return 'That turn is no longer in this conversation. Refresh and choose another turn.';
    case 'CHAT_REQUEST_NOT_PENDING':
      return 'This request was already answered or is no longer waiting. Refresh the conversation.';
    case 'CHAT_DECISION_NOT_OFFERED':
      return 'That choice is no longer available. Refresh the conversation and choose an offered answer.';
    case 'CHAT_CONFIG_OPTION_INVALID':
      return 'The provider no longer accepts that setting. Refresh its controls and choose again.';
    case 'CHAT_CONFIG_OPTION_VALUE_REQUIRED':
      return 'Choose a value for that provider setting.';
    case 'CHAT_APPROVAL_MODE_INVALID':
      return 'The provider does not accept that approval mode.';
    case 'CHAT_DECISION_REQUIRED':
      return "Choose one of the provider's approval options.";
    case 'CHAT_INPUT_ACTION_INVALID':
      return 'That response is not available for this request.';
    case 'CHAT_INPUT_CONTENT_INVALID':
      return 'The provider rejected the submitted form. Check the fields and try again.';
    case 'CHAT_RENAME_UNSUPPORTED':
      return 'This agent does not support conversation titles.';
    case 'CHAT_TITLE_REQUIRED':
      return 'Enter a conversation title.';
    case 'CHAT_CONTROLLER_NOT_READY':
      return 'The agent controller is not running. Resume it before trying again.';
    case 'CHAT_AUTH_REQUIRED':
      return 'Sign in with the agent CLI on the Operator host, then resume this session.';
    case 'CHAT_DRIVER_UNAVAILABLE':
      return 'The agent CLI is unavailable on the Operator host. Install it or open the worktree shell.';
    case 'CHAT_DRIVER_INCOMPATIBLE':
      return 'The installed agent CLI is not compatible with Operator Chat. Update it, then resume this session.';
    case 'CHAT_RESUME_FAILED':
      return 'Operator could not resume this agent. The conversation and worktree are preserved.';
    case 'CHAT_PROVIDER_REFUSED':
      final refusal = failure.message.trim();
      return refusal.isEmpty ? 'The provider refused this action.' : refusal;
    default:
      final message = failure.message.trim();
      return message.isEmpty ? 'The conversation request failed.' : message;
  }
}

bool conversationActionUnsupported(String action, String? code) =>
    code != null && _unsupportedCodes[action] == code;
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/conversation_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 427/427 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port conversation action error copy"
```

---

### Task 4: Terminal text projection (`shared/chat/ansi.ts` + `chat/ansi.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/ansi.dart`
- Test: `packages/mobile/test/feature/chat/logic/ansi_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `String stripAnsi(String text)`
  - `String caretNotation(String text)`
  - `String commandOutputText(dynamic raw)`

`stripAnsi`/`caretNotation` come from `packages/shared/chat/ansi.ts` (shared with the desktop app);
`commandOutputText` comes from `packages/mobile_rn/lib/chat/ansi.ts`. This is deliberately **not a
terminal emulator**: color is discarded, while carriage-return and backspace overwrites are applied
so progress output resembles the final line a terminal displayed.

The escape pattern accepts end-of-string mid-sequence on purpose — streamed chunks can end halfway
through a control sequence. Dart's `RegExp` has no `s`/`dotAll` here; `[\s\S]` is used exactly as
in the TypeScript source, which works identically in Dart.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/ansi_test.dart` (ported from `chat/ansi.test.ts`, with
the shared module's own edge cases added because Dart's regex engine is not JavaScript's):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/ansi.dart';

void main() {
  group('mobile Chat terminal text', () {
    test('removes ANSI and applies carriage-return redraws', () {
      expect(stripAnsi('\x1b[32mok\x1b[0m 12%\rready'), 'ready%');
    });

    test('leaves text with no control bytes untouched', () {
      expect(stripAnsi(''), '');
      expect(stripAnsi('plain output'), 'plain output');
    });

    test('applies backspace overwrites per line', () {
      expect(stripAnsi('abc\b\bXY'), 'aXY');
      expect(stripAnsi('one\ntwo\rTWO'), 'one\nTWO');
    });

    test('drops an escape sequence cut off by the end of a chunk', () {
      expect(stripAnsi('done\x1b['), 'done');
    });

    test('reads structured historical output without crashing', () {
      expect(commandOutputText({'metadata': {'text': 'done'}}), 'done');
      expect(commandOutputText(null), '');
      expect(commandOutputText('\x1b[31mred\x1b[0m'), 'red');
      expect(commandOutputText({'count': 2}), '{\n  "count": 2\n}');
    });

    test('keeps terminal input meaningful', () {
      expect(caretNotation('\x03\n'), '^C\n');
      expect(caretNotation('a\tb'), 'a\tb');
      expect(caretNotation('\x7f'), '^?');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/ansi_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/ansi.dart`:

```dart
import 'dart:convert';

final RegExp _escape = RegExp(
  r'\x1B(?:\[[0-?]*[ -/]*(?:[@-~]|$)|\][\s\S]*?(?:\x07|\x1B\\|$)|[P^_X][\s\S]*?(?:\x1B\\|\x07|$)|[@-Z\\-_]|[ -/]+[0-~])',
);
final RegExp _leftoverControls = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

const List<String> _outputKeys = ['output', 'text', 'error', 'metadata'];

String stripAnsi(String text) {
  if (text.isEmpty ||
      (!text.contains('\x1B') && !text.contains('\r') && !text.contains('\b') && !text.contains('\x07'))) {
    return text;
  }

  final withoutEscapes = text.replaceAll(_escape, '');
  if (!withoutEscapes.contains('\r') && !withoutEscapes.contains('\b')) {
    return withoutEscapes.replaceAll(_leftoverControls, '');
  }
  return withoutEscapes.split('\n').map(_overwrite).join('\n').replaceAll(_leftoverControls, '');
}

String caretNotation(String text) {
  final output = StringBuffer();
  for (final character in text.runes) {
    if (character == 0x0A || character == 0x09) {
      output.writeCharCode(character);
    } else if (character < 0x20) {
      output.write('^${String.fromCharCode(character + 64)}');
    } else {
      output.write(character == 0x7F ? '^?' : String.fromCharCode(character));
    }
  }
  return output.toString();
}

String commandOutputText(dynamic raw) {
  if (raw is String) return stripAnsi(raw);
  if (raw is! Map) return '';
  for (final key in _outputKeys) {
    final text = commandOutputText(raw[key]);
    if (text.isNotEmpty) return text;
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(raw);
  } catch (_) {
    return '';
  }
}

String _overwrite(String line) {
  if (!line.contains('\r') && !line.contains('\b')) return line;
  var output = '';
  var column = 0;
  for (final character in line.split('')) {
    if (character == '\r') {
      column = 0;
      continue;
    }
    if (character == '\b') {
      column = column > 0 ? column - 1 : 0;
      continue;
    }
    output = column < output.length
        ? output.substring(0, column) + character + output.substring(column + 1)
        : output + character;
    column += 1;
  }
  return output;
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/ansi_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 433/433 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port ANSI stripping and caret notation"
```

---

### Task 5: Markdown block parser (`markdownBlocks.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/markdown_blocks.dart`
- Test: `packages/mobile/test/feature/chat/logic/chat_markdown_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `sealed class MarkdownBlock extends Equatable` with
    `ParagraphBlock(text)`, `HeadingBlock(text, level)`, `QuoteBlock(text)`,
    `ListBlock(ordered, items)` where `items` is `List<ListItem>`,
    `CodeBlock(language, text)`, `TableBlock(headers, rows)`, `ImageBlock(alt, url)`,
    `RuleBlock()`
  - `class ListItem extends Equatable` — `text (String)`, `checked (bool?)`
  - `List<MarkdownBlock> parseBlocks(String input)`

RN models blocks as a discriminated union; Dart's equivalent is a sealed class, which also gives
Task 20's renderer an exhaustive `switch` with no default branch to forget.

Unknown syntax stays readable paragraph text. The renderer never hides content because a provider
used syntax it does not know.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/chat_markdown_test.dart` (ported from
`chat/ChatMarkdown.test.ts`, extended to pin the block kinds the renderer switches on):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/markdown_blocks.dart';

void main() {
  group('mobile Chat markdown blocks', () {
    test('keeps GFM tables, tasks and remote images structured', () {
      final blocks = parseBlocks([
        '| File | State |',
        '| --- | --- |',
        '| app.ts | changed |',
        '',
        '- [x] inspect',
        '- [ ] test',
        '',
        '![result](https://example.com/result.png)',
      ].join('\n'));

      expect(
        blocks[0],
        const TableBlock(headers: ['File', 'State'], rows: [['app.ts', 'changed']]),
      );
      expect(
        blocks[1],
        const ListBlock(
          ordered: false,
          items: [ListItem(text: 'inspect', checked: true), ListItem(text: 'test', checked: false)],
        ),
      );
      expect(blocks[2], const ImageBlock(alt: 'result', url: 'https://example.com/result.png'));
    });

    test('keeps fenced code with its language and its blank lines', () {
      final blocks = parseBlocks('```dart\nvoid main() {}\n\nfinal x = 1;\n```');
      expect(blocks.single, const CodeBlock(language: 'dart', text: 'void main() {}\n\nfinal x = 1;'));
    });

    test('reads headings, quotes, ordered lists and rules', () {
      expect(parseBlocks('## Findings').single, const HeadingBlock(text: 'Findings', level: 2));
      expect(parseBlocks('> one\n> two').single, const QuoteBlock(text: 'one\ntwo'));
      expect(
        parseBlocks('1. first\n2. second').single,
        const ListBlock(ordered: true, items: [ListItem(text: 'first'), ListItem(text: 'second')]),
      );
      expect(parseBlocks('---').single, const RuleBlock());
    });

    test('leaves unknown syntax as readable paragraph text', () {
      expect(parseBlocks(':::note\nhi\n:::').single, const ParagraphBlock(text: ':::note\nhi\n:::'));
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/chat_markdown_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/markdown_blocks.dart`:

```dart
import 'package:equatable/equatable.dart';

final RegExp _heading = RegExp(r'^(#{1,6})\s+(.+)$');
final RegExp _image = RegExp(r'^!\[([^\]]*)\]\((https?://[^\s)]+)\)\s*$');
final RegExp _rule = RegExp(r'^\s*(---+|\*\*\*+)\s*$');
final RegExp _listItem = RegExp(r'^\s*(?:(\d+)\.|[-*+])\s+(.+)$');
final RegExp _quote = RegExp(r'^>\s?');
final RegExp _task = RegExp(r'^\[([ xX])\]\s+(.+)$');
final RegExp _divider = RegExp(r'^:?-{3,}:?$');

sealed class MarkdownBlock extends Equatable {
  const MarkdownBlock();

  @override
  List<Object?> get props => [];
}

final class ParagraphBlock extends MarkdownBlock {
  const ParagraphBlock({required this.text});

  final String text;

  @override
  List<Object?> get props => [text];
}

final class HeadingBlock extends MarkdownBlock {
  const HeadingBlock({required this.text, required this.level});

  final String text;
  final int level;

  @override
  List<Object?> get props => [text, level];
}

final class QuoteBlock extends MarkdownBlock {
  const QuoteBlock({required this.text});

  final String text;

  @override
  List<Object?> get props => [text];
}

class ListItem extends Equatable {
  const ListItem({required this.text, this.checked});

  final String text;
  final bool? checked;

  @override
  List<Object?> get props => [text, checked];
}

final class ListBlock extends MarkdownBlock {
  const ListBlock({required this.ordered, required this.items});

  final bool ordered;
  final List<ListItem> items;

  @override
  List<Object?> get props => [ordered, items];
}

final class CodeBlock extends MarkdownBlock {
  const CodeBlock({required this.text, this.language});

  final String text;
  final String? language;

  @override
  List<Object?> get props => [text, language];
}

final class TableBlock extends MarkdownBlock {
  const TableBlock({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  @override
  List<Object?> get props => [headers, rows];
}

final class ImageBlock extends MarkdownBlock {
  const ImageBlock({required this.alt, required this.url});

  final String alt;
  final String url;

  @override
  List<Object?> get props => [alt, url];
}

final class RuleBlock extends MarkdownBlock {
  const RuleBlock();
}

List<MarkdownBlock> parseBlocks(String input) {
  final lines = input.replaceAll('\r', '').split('\n');
  final blocks = <MarkdownBlock>[];
  var paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isNotEmpty) blocks.add(ParagraphBlock(text: paragraph.join('\n').trim()));
    paragraph = <String>[];
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    if (line.startsWith('```')) {
      flushParagraph();
      final language = line.substring(3).trim();
      final code = <String>[];
      for (i += 1; i < lines.length && !lines[i].startsWith('```'); i++) {
        code.add(lines[i]);
      }
      blocks.add(CodeBlock(language: language.isEmpty ? null : language, text: code.join('\n')));
      continue;
    }

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(HeadingBlock(level: heading.group(1)!.length, text: heading.group(2)!));
      continue;
    }

    final image = _image.firstMatch(line.trim());
    if (image != null) {
      flushParagraph();
      blocks.add(ImageBlock(alt: image.group(1)!, url: image.group(2)!));
      continue;
    }

    if (line.contains('|') && i + 1 < lines.length && _isTableDivider(lines[i + 1])) {
      flushParagraph();
      final headers = _tableCells(line);
      final rows = <List<String>>[];
      i += 2;
      while (i < lines.length && lines[i].contains('|') && lines[i].trim().isNotEmpty) {
        rows.add(_tableCells(lines[i]));
        i++;
      }
      i--;
      blocks.add(TableBlock(headers: headers, rows: rows));
      continue;
    }

    if (_rule.hasMatch(line)) {
      flushParagraph();
      blocks.add(const RuleBlock());
      continue;
    }

    final item = _listItem.firstMatch(line);
    if (item != null) {
      flushParagraph();
      final ordered = item.group(1) != null;
      final items = [_taskItem(item.group(2)!)];
      while (i + 1 < lines.length) {
        final next = _listItem.firstMatch(lines[i + 1]);
        if (next == null || (next.group(1) != null) != ordered) break;
        items.add(_taskItem(next.group(2)!));
        i += 1;
      }
      blocks.add(ListBlock(ordered: ordered, items: items));
      continue;
    }

    if (_quote.hasMatch(line)) {
      flushParagraph();
      final quote = [line.replaceFirst(_quote, '')];
      while (i + 1 < lines.length && _quote.hasMatch(lines[i + 1])) {
        quote.add(lines[++i].replaceFirst(_quote, ''));
      }
      blocks.add(QuoteBlock(text: quote.join('\n')));
      continue;
    }

    if (line.trim().isEmpty) {
      flushParagraph();
    } else {
      paragraph.add(line);
    }
  }

  flushParagraph();
  return blocks;
}

ListItem _taskItem(String value) {
  final task = _task.firstMatch(value);
  if (task == null) return ListItem(text: value);
  return ListItem(text: task.group(2)!, checked: task.group(1)!.toLowerCase() == 'x');
}

bool _isTableDivider(String value) {
  final cells = _tableCells(value);
  return cells.isNotEmpty && cells.every(_divider.hasMatch);
}

List<String> _tableCells(String value) => value
    .trim()
    .replaceFirst(RegExp(r'^\|'), '')
    .replaceFirst(RegExp(r'\|$'), '')
    .split('|')
    .map((cell) => cell.trim())
    .toList();
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/chat_markdown_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 437/437 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port the chat markdown block parser"
```

---

### Task 6: Syntax highlighting (`syntaxHighlight.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/syntax_highlight.dart`
- Test: `packages/mobile/test/feature/chat/logic/syntax_highlight_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum SyntaxTokenKind { plain, comment, string, number, keyword, type, addition, deletion, meta }`
  - `class SyntaxToken extends Equatable` — `text (String)`, `kind (SyntaxTokenKind)`
  - `List<SyntaxToken>? highlightCode(String code, [String? rawLanguage])`

Lightweight native tokenization. Unknown grammars return `null` and stay exact plain text — the
renderer must never rewrite code it does not understand.

Two Dart-specific notes for the implementer. First, JavaScript's `s` (dotAll) flag is spelled
`dotAll: true` on `RegExp`; the source uses `gis`, so this is `caseSensitive: false, dotAll: true`
with `allMatches` standing in for `g`. Second, `String.split(RegExp)` in Dart drops nothing but
also has no lookbehind support in older engines — Dart *does* support `(?<=\n)`, so the diff
splitter ports as written.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/syntax_highlight_test.dart` (ported from
`chat/syntaxHighlight.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/syntax_highlight.dart';

void main() {
  group('mobile Chat syntax highlighting', () {
    test('tokenizes known coding languages without changing the source', () {
      const code = 'const answer: Result = "yes"; // note';
      final tokens = highlightCode(code, 'typescript')!;

      expect(tokens.map((token) => token.text).join(), code);
      expect(tokens, contains(const SyntaxToken(text: 'const', kind: SyntaxTokenKind.keyword)));
      expect(tokens, contains(const SyntaxToken(text: 'Result', kind: SyntaxTokenKind.type)));
      expect(tokens, contains(const SyntaxToken(text: '"yes"', kind: SyntaxTokenKind.string)));
      expect(tokens, contains(const SyntaxToken(text: '// note', kind: SyntaxTokenKind.comment)));
    });

    test('colors diffs structurally and leaves unknown languages plain', () {
      expect(
        highlightCode('+added\n-removed\n', 'diff')?.map((token) => token.kind).toList(),
        [SyntaxTokenKind.addition, SyntaxTokenKind.deletion],
      );
      expect(highlightCode('opaque', 'made-up-language'), isNull);
      expect(highlightCode('opaque'), isNull);
    });

    test('resolves aliases and the language- prefix', () {
      expect(highlightCode('x = 1 # note', 'py')?.last.kind, SyntaxTokenKind.comment);
      expect(highlightCode('const x = 1', 'language-ts'), isNotNull);
    });

    test('numbers survive a round trip through hex and decimals', () {
      final tokens = highlightCode('0xFF + 1.5', 'javascript')!;
      expect(tokens.map((token) => token.text).join(), '0xFF + 1.5');
      expect(
        tokens.where((token) => token.kind == SyntaxTokenKind.number).map((token) => token.text),
        ['0xFF', '1.5'],
      );
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/syntax_highlight_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/syntax_highlight.dart`:

```dart
import 'package:equatable/equatable.dart';

enum SyntaxTokenKind { plain, comment, string, number, keyword, type, addition, deletion, meta }

class SyntaxToken extends Equatable {
  const SyntaxToken({required this.text, required this.kind});

  final String text;
  final SyntaxTokenKind kind;

  @override
  List<Object?> get props => [text, kind];
}

const Map<String, String> _languageAliases = {
  'js': 'javascript', 'jsx': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript',
  'ts': 'typescript', 'tsx': 'typescript',
  'py': 'python', 'rs': 'rust', 'sh': 'shell', 'bash': 'shell', 'zsh': 'shell',
  'yml': 'yaml', 'html': 'markup', 'xml': 'markup', 'md': 'markdown',
};

final Map<String, Set<String>> _keywords = {
  'javascript': _words(
      'as async await break case catch class const continue debugger default delete do else export extends finally for from function get if implements import in instanceof interface let new of package private protected public return set static super switch throw try type typeof undefined var void while with yield'),
  'typescript': _words(
      'as async await break case catch class const continue declare default delete do else enum export extends finally for from function get if implements import in infer instanceof interface keyof let namespace never new of private protected public readonly return satisfies set static super switch throw try type typeof undefined unknown var void while yield'),
  'go': _words(
      'break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var'),
  'python': _words(
      'and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield'),
  'rust': _words(
      'as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while'),
  'shell': _words(
      'case do done elif else esac export fi for function if in local readonly return set then unset while'),
  'sql': _words(
      'alter and as asc begin by case commit create delete desc distinct drop else end exists from group having in index insert into is join left like limit not null on or order outer primary references right rollback select set table then union unique update values view when where'),
  'css': _words('important inherit initial revert unset var calc media supports keyframes from to'),
  'yaml': _words('true false null yes no on off'),
  'json': _words('true false null'),
};

final Set<String> _supported = {..._keywords.keys, 'diff', 'markup', 'markdown'};

final RegExp _diffLines = RegExp(r'(?<=\n)');

List<SyntaxToken>? highlightCode(String code, [String? rawLanguage]) {
  if (rawLanguage == null) return null;
  final lowered = rawLanguage.trim().toLowerCase().replaceFirst(RegExp(r'^language-'), '');
  final language = _languageAliases[lowered] ?? lowered;
  if (!_supported.contains(language)) return null;
  if (language == 'diff') return _diffTokens(code);

  final comment = ['python', 'shell', 'yaml'].contains(language)
      ? r'#[^\n]*'
      : language == 'sql'
          ? r'--[^\n]*|/\*[\s\S]*?\*/'
          : language == 'markup'
              ? r'<!--[\s\S]*?-->'
              : r'//[^\n]*|/\*[\s\S]*?\*/';
  const stringLiteral =
      r'"(?:\\.|[^"\\])*"|' "'" r'(?:\\.|[^' "'" r'\\])*' "'" r'|`(?:\\.|[^`\\])*`';
  final source = RegExp(
    '($comment)|($stringLiteral)|' r'(\b(?:0x[\da-f]+|\d+(?:\.\d+)?)\b)|(\b[A-Za-z_$][\w$]*\b)',
    caseSensitive: false,
    dotAll: true,
  );

  final keywords = _keywords[language] ?? const <String>{};
  final tokens = <SyntaxToken>[];
  var at = 0;
  for (final match in source.allMatches(code)) {
    if (match.start > at) {
      tokens.add(SyntaxToken(text: code.substring(at, match.start), kind: SyntaxTokenKind.plain));
    }
    final text = match.group(0)!;
    final kind = match.group(1) != null
        ? SyntaxTokenKind.comment
        : match.group(2) != null
            ? SyntaxTokenKind.string
            : match.group(3) != null
                ? SyntaxTokenKind.number
                : keywords.contains(text.toLowerCase())
                    ? SyntaxTokenKind.keyword
                    : RegExp(r'^[A-Z]').hasMatch(text)
                        ? SyntaxTokenKind.type
                        : SyntaxTokenKind.plain;
    tokens.add(SyntaxToken(text: text, kind: kind));
    at = match.end;
  }
  if (at < code.length) {
    tokens.add(SyntaxToken(text: code.substring(at), kind: SyntaxTokenKind.plain));
  }
  return tokens;
}

List<SyntaxToken> _diffTokens(String code) => code
    .split(_diffLines)
    .where((line) => line.isNotEmpty)
    .map(
      (line) => SyntaxToken(
        text: line,
        kind: line.startsWith('+++') ||
                line.startsWith('---') ||
                line.startsWith('@@') ||
                line.startsWith('diff ')
            ? SyntaxTokenKind.meta
            : line.startsWith('+')
                ? SyntaxTokenKind.addition
                : line.startsWith('-')
                    ? SyntaxTokenKind.deletion
                    : SyntaxTokenKind.plain,
      ),
    )
    .toList();

Set<String> _words(String value) => value.split(' ').toSet();
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/syntax_highlight_test.dart`
Expected: PASS. If the string-literal pattern misbehaves, check the single-quote concatenation
first — Dart raw strings cannot contain the quote character that delimits them, which is why the
literal is assembled from three pieces.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 441/441 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port chat syntax highlighting"
```

---

### Task 7: Conversation chrome (`conversationChrome.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/conversation_chrome.dart`
- Test: `packages/mobile/test/feature/chat/logic/conversation_chrome_test.dart`

**Interfaces:**
- Consumes: `ConversationUsageModel`, `ConversationRateLimitsModel`, `McpServerModel` — **not yet
  written** (Task 11). This task therefore takes the four primitives it needs directly, and Task 11
  adds the model classes that carry them:
  - `enum Severity { normal, warn, critical }`
  - `class ContextReadout` — `percent (int?)`, `fillPercent (double?)`, `severity (Severity)`,
    `tokens (int)`
  - `ContextReadout? contextReadout({required int? contextUsed, required int? contextWindow, required int? totalTokens})`
  - `class QuotaWarning` — `percent (int)`, `severity (Severity)`, `resetsInSeconds (int?)`,
    `planLabel (String?)`
  - `QuotaWarning? quotaWarning({required num? primaryUsedPercent, required num? secondaryUsedPercent, int? primaryResetsInSeconds, int? secondaryResetsInSeconds, String? planLabel})`
  - `String? elapsedLabel(String? startedAt, int nowMs)`
  - `String? resetLabel(int? seconds)`
  - `String mcpServerFailureLabel({required String name, String? failureReason, String? error})`

Taking primitives rather than models keeps this module ahead of Task 11 in the build order, which
matters: it is pure presentation arithmetic and its test is the ledger's `conversationChrome`
row, which must not wait on the wire shapes.

`quotaWarning` filters out windows the daemon reports as `-1` (meaning "not reported") before
picking the worst, and returns nothing below 75%. `contextReadout`'s `fillPercent` floors at 2 so a
1%-full context is still a visible sliver rather than an empty rail.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/conversation_chrome_test.dart` (ported from
`chat/conversationChrome.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_chrome.dart';

void main() {
  group('mobile Chat conversation chrome', () {
    test('uses the same context thresholds and visible minimum as desktop', () {
      final low = contextReadout(contextUsed: 1, contextWindow: 1000, totalTokens: 1)!;
      expect(low.percent, 0);
      expect(low.fillPercent, 2);
      expect(low.severity, Severity.normal);

      expect(
        contextReadout(contextUsed: 70, contextWindow: 100, totalTokens: 70)?.severity,
        Severity.warn,
      );
      expect(
        contextReadout(contextUsed: 900, contextWindow: 1000, totalTokens: 900)?.severity,
        Severity.critical,
      );
    });

    test('falls back to total tokens when no window is reported', () {
      final unbounded = contextReadout(contextUsed: 0, contextWindow: 0, totalTokens: 4200)!;
      expect(unbounded.percent, isNull);
      expect(unbounded.tokens, 4200);
      expect(unbounded.severity, Severity.normal);
      expect(contextReadout(contextUsed: null, contextWindow: null, totalTokens: null), isNull);
    });

    test('warns on the tighter reported quota window and ignores absent ones', () {
      final warned = quotaWarning(
        primaryUsedPercent: -1,
        secondaryUsedPercent: 82,
        secondaryResetsInSeconds: 7200,
        planLabel: 'weekly',
      )!;
      expect(warned.percent, 82);
      expect(warned.severity, Severity.warn);
      expect(warned.resetsInSeconds, 7200);
      expect(warned.planLabel, 'weekly');

      expect(quotaWarning(primaryUsedPercent: 40, secondaryUsedPercent: -1), isNull);
      expect(
        quotaWarning(primaryUsedPercent: 91, secondaryUsedPercent: 80)?.severity,
        Severity.critical,
      );
      expect(quotaWarning(primaryUsedPercent: null, secondaryUsedPercent: null), isNull);
    });

    test('formats live turn and reset durations without wall-clock assumptions', () {
      expect(
        elapsedLabel('2026-08-05T00:00:00Z', DateTime.parse('2026-08-05T00:02:03Z').millisecondsSinceEpoch),
        '2m 3s',
      );
      expect(
        elapsedLabel('2026-08-05T00:00:00Z', DateTime.parse('2026-08-05T01:05:00Z').millisecondsSinceEpoch),
        '1h 5m',
      );
      expect(elapsedLabel(null, 0), isNull);
      expect(elapsedLabel('not a date', 0), isNull);
      expect(resetLabel(172800), '2d');
      expect(resetLabel(90), '2m');
      expect(resetLabel(null), isNull);
      expect(resetLabel(-1), isNull);
    });

    test('keeps both the MCP failure class and provider diagnostic', () {
      expect(
        mcpServerFailureLabel(name: 'github', failureReason: 'auth', error: 'token expired'),
        'github (auth: token expired)',
      );
      expect(mcpServerFailureLabel(name: 'github'), 'github');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/conversation_chrome_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/conversation_chrome.dart`:

```dart
import 'dart:math';

enum Severity { normal, warn, critical }

class ContextReadout {
  const ContextReadout({required this.severity, required this.tokens, this.percent, this.fillPercent});

  final int? percent;
  final double? fillPercent;
  final Severity severity;
  final int tokens;
}

class QuotaWarning {
  const QuotaWarning({
    required this.percent,
    required this.severity,
    this.resetsInSeconds,
    this.planLabel,
  });

  final int percent;
  final Severity severity;
  final int? resetsInSeconds;
  final String? planLabel;
}

ContextReadout? contextReadout({
  required int? contextUsed,
  required int? contextWindow,
  required int? totalTokens,
}) {
  if (contextUsed == null && contextWindow == null && totalTokens == null) return null;
  final used = contextUsed ?? 0;
  final window = contextWindow ?? 0;
  final tokens = used != 0 ? used : totalTokens ?? 0;
  if (window <= 0) return ContextReadout(severity: Severity.normal, tokens: tokens);

  final fraction = min(1, max(0, used / window)).toDouble();
  return ContextReadout(
    percent: (fraction * 100).round(),
    fillPercent: max(2, fraction * 100),
    severity: fraction >= 0.9
        ? Severity.critical
        : fraction >= 0.7
            ? Severity.warn
            : Severity.normal,
    tokens: tokens,
  );
}

QuotaWarning? quotaWarning({
  required num? primaryUsedPercent,
  required num? secondaryUsedPercent,
  int? primaryResetsInSeconds,
  int? secondaryResetsInSeconds,
  String? planLabel,
}) {
  final windows = <({num percent, int? resetsInSeconds})>[
    if (primaryUsedPercent != null && primaryUsedPercent.isFinite && primaryUsedPercent >= 0)
      (percent: primaryUsedPercent, resetsInSeconds: primaryResetsInSeconds),
    if (secondaryUsedPercent != null && secondaryUsedPercent.isFinite && secondaryUsedPercent >= 0)
      (percent: secondaryUsedPercent, resetsInSeconds: secondaryResetsInSeconds),
  ];
  if (windows.isEmpty) return null;

  final worst = windows.reduce((current, candidate) => candidate.percent > current.percent ? candidate : current);
  if (worst.percent < 75) return null;

  return QuotaWarning(
    percent: worst.percent.round(),
    severity: worst.percent >= 90 ? Severity.critical : Severity.warn,
    resetsInSeconds: worst.resetsInSeconds,
    planLabel: planLabel,
  );
}

String? elapsedLabel(String? startedAt, int nowMs) {
  if (startedAt == null) return null;
  final started = DateTime.tryParse(startedAt);
  if (started == null) return null;

  final elapsed = max(0, nowMs - started.millisecondsSinceEpoch);
  final seconds = elapsed ~/ 1000;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String? resetLabel(int? seconds) {
  if (seconds == null || seconds < 0) return null;
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${(seconds / 60).ceil()}m';
  if (seconds < 86400) return '${(seconds / 3600).ceil()}h';
  return '${(seconds / 86400).ceil()}d';
}

String mcpServerFailureLabel({required String name, String? failureReason, String? error}) {
  final details = [failureReason, error]
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty)
      .toList();
  return details.isEmpty ? name : '$name (${details.join(': ')})';
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/conversation_chrome_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 446/446 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port conversation chrome readouts"
```

---

### Task 8: Elicitation model (`elicitationModel.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/elicitation_model.dart`
- Test: `packages/mobile/test/feature/chat/logic/elicitation_model_test.dart`

**Interfaces:**
- Consumes: nothing (it takes the same primitive shape Task 11's `InputPropertyModel` will expose,
  via a small local contract).
- Produces:
  - `class InputChoice extends Equatable` — `value (String)`, `label (String)`, `description (String?)`
  - `abstract class ElicitationProperty` — `type`, `title`, `description`, `defaultValue`,
    `enumValues`, `oneOf`, `itemsAnyOf`, `minimum`, `maximum`, `minLength`, `maxLength`
  - `dynamic initialInputValue(ElicitationProperty property)`
  - `List<InputChoice> inputOptions(ElicitationProperty property)`
  - `List<String> toggleInputValue(List<dynamic> values, String value)`
  - `List<String> missingRequiredInputs(List<String>? required, Map<String, dynamic> values)`
  - `String? validateInput(ElicitationProperty property, dynamic value)`
  - `String humanizeInputName(String value)`
  - `Uri? safeHttpUrl(dynamic value)`

`ElicitationProperty` is an abstract contract, not a model: Task 11's `InputPropertyModel`
implements it. That keeps this pure module ahead of the wire shapes in the build order while
letting the widget in Task 22 pass a parsed model straight in. The test below supplies its own
implementation, exactly as a caller would.

`safeHttpUrl` is a security boundary, not a convenience: it is the gate deciding whether the app
will hand a provider-supplied string to `url_launcher`. `javascript:` and `file:` must not pass.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/elicitation_model_test.dart` (ported from
`chat/elicitationModel.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/elicitation_model.dart';

class _Property implements ElicitationProperty {
  const _Property({
    this.type,
    this.title,
    this.description,
    this.defaultValue,
    this.enumValues,
    this.oneOf,
    this.itemsAnyOf,
    this.minimum,
    this.maximum,
    this.minLength,
    this.maxLength,
  });

  @override
  final String? type;
  @override
  final String? title;
  @override
  final String? description;
  @override
  final dynamic defaultValue;
  @override
  final List<dynamic>? enumValues;
  @override
  final List<InputChoice>? oneOf;
  @override
  final List<InputChoice>? itemsAnyOf;
  @override
  final num? minimum;
  @override
  final num? maximum;
  @override
  final int? minLength;
  @override
  final int? maxLength;
}

void main() {
  group('mobile Chat elicitation model', () {
    test('opens only explicit web URLs', () {
      expect(safeHttpUrl('https://example.com/login')?.host, 'example.com');
      expect(safeHttpUrl('http://example.com'), isNotNull);
      expect(safeHttpUrl('javascript:alert(1)'), isNull);
      expect(safeHttpUrl('file:///etc/passwd'), isNull);
      expect(safeHttpUrl('not a URL'), isNull);
      expect(safeHttpUrl(7), isNull);
    });

    test('validates required, string, number and integer constraints', () {
      expect(missingRequiredInputs(['name', 'scopes'], {'name': '', 'scopes': <dynamic>[]}),
          ['name', 'scopes']);
      expect(missingRequiredInputs(['name'], {'name': 'ok'}), isEmpty);
      expect(validateInput(const _Property(type: 'string', minLength: 3), 'ab'), contains('at least 3'));
      expect(validateInput(const _Property(type: 'string', maxLength: 2), 'abc'), contains('at most 2'));
      expect(validateInput(const _Property(type: 'integer'), 1.5), contains('whole number'));
      expect(validateInput(const _Property(type: 'number', minimum: 2, maximum: 4), 1),
          contains('at least 2'));
      expect(validateInput(const _Property(type: 'number', minimum: 2, maximum: 4), 5),
          contains('at most 4'));
      expect(validateInput(const _Property(type: 'number', minimum: 2, maximum: 4), 3), isNull);
    });

    test('normalizes provider choices and multi-select toggles', () {
      expect(
        inputOptions(const _Property(
          type: 'string',
          oneOf: [InputChoice(value: 'fast', label: 'Fast', description: 'Less context')],
        )),
        [const InputChoice(value: 'fast', label: 'Fast', description: 'Less context')],
      );
      expect(
        inputOptions(const _Property(type: 'string', enumValues: ['read', 7, 'write'])),
        [const InputChoice(value: 'read', label: 'read'), const InputChoice(value: 'write', label: 'write')],
      );
      expect(toggleInputValue(['read'], 'write'), ['read', 'write']);
      expect(toggleInputValue(['read', 'write'], 'read'), ['write']);
    });

    test('seeds each field with a value its control can render', () {
      expect(initialInputValue(const _Property(type: 'array')), <dynamic>[]);
      expect(initialInputValue(const _Property(type: 'boolean')), false);
      expect(initialInputValue(const _Property(type: 'string')), '');
      expect(initialInputValue(const _Property(type: 'boolean', defaultValue: true)), true);
    });

    test('humanizes a schema key for a label', () {
      expect(humanizeInputName('api_token'), 'Api token');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/elicitation_model_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/elicitation_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class InputChoice extends Equatable {
  const InputChoice({required this.value, required this.label, this.description});

  final String value;
  final String label;
  final String? description;

  @override
  List<Object?> get props => [value, label, description];
}

abstract class ElicitationProperty {
  String? get type;
  String? get title;
  String? get description;
  dynamic get defaultValue;
  List<dynamic>? get enumValues;
  List<InputChoice>? get oneOf;
  List<InputChoice>? get itemsAnyOf;
  num? get minimum;
  num? get maximum;
  int? get minLength;
  int? get maxLength;
}

dynamic initialInputValue(ElicitationProperty property) {
  if (property.defaultValue != null) return property.defaultValue;
  if (property.type == 'array') return <dynamic>[];
  if (property.type == 'boolean') return false;
  return '';
}

List<InputChoice> inputOptions(ElicitationProperty property) {
  final candidates = property.oneOf ?? property.itemsAnyOf;
  if (candidates != null && candidates.isNotEmpty) return candidates;
  return (property.enumValues ?? const [])
      .whereType<String>()
      .map((value) => InputChoice(value: value, label: value))
      .toList();
}

List<String> toggleInputValue(List<dynamic> values, String value) {
  final strings = values.whereType<String>().toList();
  return strings.contains(value)
      ? strings.where((item) => item != value).toList()
      : [...strings, value];
}

List<String> missingRequiredInputs(List<String>? required, Map<String, dynamic> values) =>
    (required ?? const []).where((name) {
      final value = values[name];
      return value == null || value == '' || (value is List && value.isEmpty);
    }).toList();

String? validateInput(ElicitationProperty property, dynamic value) {
  if (value is String) {
    final minLength = property.minLength;
    final maxLength = property.maxLength;
    if (minLength != null && value.length < minLength) return 'must be at least $minLength characters';
    if (maxLength != null && value.length > maxLength) return 'must be at most $maxLength characters';
  }
  if ((property.type == 'number' || property.type == 'integer') && value is num) {
    if (!value.isFinite) return 'must be a number';
    if (property.type == 'integer' && value != value.roundToDouble()) return 'must be a whole number';
    final minimum = property.minimum;
    final maximum = property.maximum;
    if (minimum != null && value < minimum) return 'must be at least ${_number(minimum)}';
    if (maximum != null && value > maximum) return 'must be at most ${_number(maximum)}';
  }
  return null;
}

String humanizeInputName(String value) {
  final spaced = value.replaceAll('_', ' ');
  return spaced.isEmpty ? spaced : spaced[0].toUpperCase() + spaced.substring(1);
}

Uri? safeHttpUrl(dynamic value) {
  if (value is! String) return null;
  final url = Uri.tryParse(value);
  if (url == null || !url.hasScheme || url.host.isEmpty) return null;
  return url.scheme == 'https' || url.scheme == 'http' ? url : null;
}

String _number(num value) => value == value.roundToDouble() ? '${value.toInt()}' : '$value';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/elicitation_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 451/451 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port the elicitation form model"
```

---

### Task 9: Composer suggestions (`composerSuggestions.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/composer_suggestions.dart`
- Test: `packages/mobile/test/feature/chat/logic/composer_suggestions_test.dart`

**Interfaces:**
- Consumes: nothing (skills arrive as a small contract, as in Task 8).
- Produces:
  - `enum SuggestionKind { skills, files }`
  - `class ComposerSuggestion extends Equatable` — `kind`, `query`, `start`, `end`
  - `class RankedSuggestion extends Equatable` — `value`, `label`, `detail (String?)`, `badge (String?)`
  - `abstract class SuggestibleSkill` — `name`, `displayName`, `description`, `inputHint`, `source`
  - `ComposerSuggestion? findComposerSuggestion(String text, [int? cursor])`
  - `String replaceComposerSuggestion(String text, ComposerSuggestion trigger, String value)`
  - `List<RankedSuggestion> rankComposerSkills(List<SuggestibleSkill> skills, String query)`
  - `List<RankedSuggestion> rankComposerFiles(List<String> paths, String query)`

This matches the desktop composer's text contract exactly. A skill is a slash command and
therefore only starts at the beginning of the message (ignoring leading whitespace). A file may be
mentioned after any whitespace boundary. Email addresses, URLs and ordinary paths remain text.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/composer_suggestions_test.dart` (ported from
`chat/composerSuggestions.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/composer_suggestions.dart';

class _Skill implements SuggestibleSkill {
  const _Skill({required this.name, required this.displayName, this.description, this.inputHint, this.source});

  @override
  final String name;
  @override
  final String displayName;
  @override
  final String? description;
  @override
  final String? inputHint;
  @override
  final String? source;
}

void main() {
  group('mobile Chat composer suggestions', () {
    test('finds slash skills and @ files at token boundaries', () {
      final skill = findComposerSuggestion('/rev')!;
      expect(skill.kind, SuggestionKind.skills);
      expect(skill.query, 'rev');
      expect(skill.start, 0);

      final file = findComposerSuggestion('inspect @src/app')!;
      expect(file.kind, SuggestionKind.files);
      expect(file.query, 'src/app');

      expect(findComposerSuggestion('https://opr.dev'), isNull);
      expect(findComposerSuggestion('please /review'), isNull);
      expect(findComposerSuggestion('email@example.com'), isNull);
      expect(findComposerSuggestion('done '), isNull);
    });

    test('replaces only the active token', () {
      const text = 'please inspect @src/ap now';
      final trigger = findComposerSuggestion(text, 'please inspect @src/ap'.length)!;
      expect(replaceComposerSuggestion(text, trigger, 'src/app.ts'), 'please inspect src/app.ts now');
    });

    test('quotes paths with spaces and keeps the slash for provider skills', () {
      expect(
        replaceComposerSuggestion('open @my', findComposerSuggestion('open @my')!, 'my notes/todo.md'),
        'open "my notes/todo.md" ',
      );
      expect(
        replaceComposerSuggestion('/rev', findComposerSuggestion('/rev')!, 'review'),
        '/review ',
      );
    });

    test('ranks names and basenames ahead of descriptions and deep paths', () {
      const skills = [
        _Skill(name: 'code-review', displayName: 'Code review', description: 'Review a change'),
        _Skill(name: 'review', displayName: 'Review', description: 'Inspect code'),
      ];
      expect(
        rankComposerSkills(skills, 'rev').map((item) => item.value).toList(),
        ['review', 'code-review'],
      );
      expect(
        rankComposerFiles(['deep/src/app.ts', 'app.ts', 'docs/application.md'], 'app')
            .map((item) => item.value)
            .toList(),
        ['app.ts', 'deep/src/app.ts', 'docs/application.md'],
      );
    });

    test('carries the detail and badge the picker renders', () {
      const skills = [
        _Skill(
          name: 'review',
          displayName: 'Review',
          description: 'Inspect code\nsecond line',
          inputHint: 'a path',
          source: 'plugin',
        ),
      ];
      final ranked = rankComposerSkills(skills, '').single;
      expect(ranked.label, 'Review');
      expect(ranked.detail, 'Inspect code · a path');
      expect(ranked.badge, 'plugin');
      expect(rankComposerFiles(['src/app.ts'], '').single.detail, 'src');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/composer_suggestions_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/composer_suggestions.dart`:

```dart
import 'dart:math';

import 'package:equatable/equatable.dart';

const int _maxSuggestions = 80;

final RegExp _whitespace = RegExp(r'\s');

enum SuggestionKind { skills, files }

class ComposerSuggestion extends Equatable {
  const ComposerSuggestion({
    required this.kind,
    required this.query,
    required this.start,
    required this.end,
  });

  final SuggestionKind kind;
  final String query;
  final int start;
  final int end;

  @override
  List<Object?> get props => [kind, query, start, end];
}

class RankedSuggestion extends Equatable {
  const RankedSuggestion({required this.value, required this.label, this.detail, this.badge});

  final String value;
  final String label;
  final String? detail;
  final String? badge;

  @override
  List<Object?> get props => [value, label, detail, badge];
}

abstract class SuggestibleSkill {
  String get name;
  String get displayName;
  String? get description;
  String? get inputHint;
  String? get source;
}

ComposerSuggestion? findComposerSuggestion(String text, [int? cursor]) {
  final caret = max(0, min(cursor ?? text.length, text.length));
  for (var index = caret - 1; index >= 0; index -= 1) {
    final char = text[index];
    if (_whitespace.hasMatch(char)) return null;
    if (char != '/' && char != '@') continue;

    final preceding = index > 0 ? text[index - 1] : null;
    if (preceding != null && !_whitespace.hasMatch(preceding)) continue;
    if (char == '/' && text.substring(0, index).trim().isNotEmpty) return null;

    return ComposerSuggestion(
      kind: char == '/' ? SuggestionKind.skills : SuggestionKind.files,
      query: text.substring(index + 1, caret),
      start: index,
      end: caret,
    );
  }
  return null;
}

String replaceComposerSuggestion(String text, ComposerSuggestion trigger, String value) {
  final inserted = trigger.kind == SuggestionKind.skills ? '/$value' : _quotePath(value);
  final suffix = text.substring(trigger.end);
  final separator = suffix.isNotEmpty && _whitespace.hasMatch(suffix[0]) ? '' : ' ';
  return '${text.substring(0, trigger.start)}$inserted$separator$suffix';
}

List<RankedSuggestion> rankComposerSkills(List<SuggestibleSkill> skills, String query) {
  final needle = query.trim().toLowerCase();
  final scored = <({double score, String name, RankedSuggestion suggestion})>[];

  for (final skill in skills) {
    if (skill.name.isEmpty) continue;
    final scores = <double>[
      ?_score(skill.name, needle, 0),
      ?_score(skill.displayName.isEmpty ? skill.name : skill.displayName, needle, 10),
      if (needle.isNotEmpty) ?_score(skill.description ?? '', needle, 40),
      if (needle.isNotEmpty) ?_score(skill.inputHint ?? '', needle, 50),
    ];
    if (scores.isEmpty) continue;

    final description = _firstLine(skill.description);
    final hint = _firstLine(skill.inputHint);
    scored.add((
      score: scores.reduce(min),
      name: skill.name,
      suggestion: RankedSuggestion(
        value: skill.name,
        label: skill.displayName.isEmpty ? skill.name : skill.displayName,
        detail: description != null && hint != null ? '$description · $hint' : description ?? hint,
        badge: skill.source,
      ),
    ));
  }

  scored.sort((left, right) {
    final byScore = left.score.compareTo(right.score);
    return byScore != 0 ? byScore : left.name.compareTo(right.name);
  });
  return scored.take(_maxSuggestions).map((entry) => entry.suggestion).toList();
}

List<RankedSuggestion> rankComposerFiles(List<String> paths, String query) {
  final needle = query.trim().toLowerCase();
  final scored = <({double score, String path, RankedSuggestion suggestion})>[];

  for (final path in paths) {
    if (path.isEmpty) continue;
    final slash = path.lastIndexOf('/');
    final basename = slash < 0 ? path : path.substring(slash + 1);
    final parent = slash < 0 ? null : path.substring(0, slash);
    final scores = <double>[?_score(basename, needle, 0), ?_score(path, needle, 10)];
    if (scores.isEmpty) continue;

    scored.add((
      score: scores.reduce(min),
      path: path,
      suggestion: RankedSuggestion(value: path, label: basename, detail: parent),
    ));
  }

  scored.sort((left, right) {
    final byScore = left.score.compareTo(right.score);
    if (byScore != 0) return byScore;
    final byLength = left.path.length.compareTo(right.path.length);
    return byLength != 0 ? byLength : left.path.compareTo(right.path);
  });
  return scored.take(_maxSuggestions).map((entry) => entry.suggestion).toList();
}

double? _score(String value, String query, int base) {
  final haystack = value.toLowerCase();
  if (query.isEmpty || haystack == query) return base.toDouble();
  if (haystack.startsWith(query)) return base + 1;
  if (['-', '_', '/', ':', '.'].any((marker) => haystack.contains('$marker$query'))) return base + 2;
  final index = haystack.indexOf(query);
  return index < 0 ? null : base + 3 + min(index, 20) / 100;
}

String _quotePath(String path) => _whitespace.hasMatch(path) ? '"$path"' : path;

String? _firstLine(String? value) {
  final line = value?.split('\n').first.trim();
  return line == null || line.isEmpty ? null : line;
}
```

The `?_score(...)` spread entries are Dart 3.9's null-aware elements: a `null` score contributes
nothing to the list, which is exactly what the TypeScript `.filter((value) => value !== undefined)`
does. If the analyzer rejects them, fall back to building the list and calling
`.whereType<double>().toList()` — the behavior must stay "a field that does not match at all does
not vote".

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/composer_suggestions_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 456/456 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port composer skill and file suggestions"
```

---

### Task 10: Composer dock inset (`keyboardInset.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/keyboard_inset.dart`
- Test: `packages/mobile/test/feature/chat/logic/keyboard_inset_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `const double kMinDockInset = 8`
  - `double dockInset(double keyboardHeight, double safeAreaBottom)`

The regression this exists for, in RN's own words: the dock used to keep its own padding while the
root view was already padded by the keyboard height, so opening the keyboard moved the bar twice in
opposite directions. In Flutter the same two numbers are `MediaQuery.viewInsets.bottom` and
`MediaQuery.viewPadding.bottom`, which is the ledger's "adapted — `MediaQuery.viewInsets`" row.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/keyboard_inset_test.dart` (ported from
`session/keyboardInset.test.ts`; its `CONTROL_KEYS` group belongs to M4's terminal key row):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/keyboard_inset.dart';

void main() {
  group('dockInset', () {
    test('owes nothing while the keyboard is up', () {
      expect(dockInset(336, 34), 0);
      expect(dockInset(1, 34), 0);
    });

    test('carries the home-indicator inset while the keyboard is down', () {
      expect(dockInset(0, 34), 34);
    });

    test('falls back to a minimum on a device with no home indicator', () {
      expect(dockInset(0, 0), kMinDockInset);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/keyboard_inset_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/keyboard_inset.dart`:

```dart
const double kMinDockInset = 8;

double dockInset(double keyboardHeight, double safeAreaBottom) {
  if (keyboardHeight > 0) return 0;
  return safeAreaBottom > 0 ? safeAreaBottom : kMinDockInset;
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/keyboard_inset_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 459/459 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port the composer dock inset rule"
```

---

### Task 11: The conversation wire model (`types.ts` + `toSnapshot` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/data/model/activity_detail_model.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/conversation_item_model.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/conversation_turn_model.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/conversation_snapshot_model.dart`
- Test: `packages/mobile/test/feature/chat/data/model/conversation_snapshot_model_test.dart`

**Interfaces:**
- Consumes: `ElicitationProperty`/`InputChoice` (Task 8), `PlanStepModel` (defined here).
- Produces:
  - `class DecisionOptionModel extends Equatable` — `id (String)`, `label (String)`
  - `class PlanStepModel extends Equatable` — `text (String)`, `status (String)`
  - `class DiffFileModel extends Equatable` — `path (String)`, `oldPath`, `status (String)`,
    `additions (int)`, `deletions (int)`, `patch (String?)`, `patchTruncated (bool)`;
    `DiffFileModel.fromJson`; `static List<DiffFileModel> listFrom(dynamic value)`
  - `class InputPropertyModel implements ElicitationProperty` — plus `InputPropertyModel.fromJson`
  - `class InputSchemaModel extends Equatable` — `title`, `description`, `required (List<String>)`,
    `properties (Map<String, InputPropertyModel>)`
  - `class ActivityDetailModel extends Equatable` — `raw (Map<String, dynamic>)` plus typed getters
    (`text`, `command`, `cwd`, `output`, `outputSource`, `outputMayBePartial`, `outputTruncated`,
    `reason`, `terminalInput`, `terminalInputTruncated`, `parentProviderItemId`, `files`,
    `patchOutput`, `patchOutputTruncated`, `server`, `toolName`, `namespace`, `arguments`,
    `result`, `error`, `success`, `progress`, `progressTruncated`, `riskLevel`, `rationale`,
    `decisionSource`, `status`, `host`, `event`, `fromModel`, `toModel`, `explanation`, `steps`,
    `tokensAfter`, `tokensReclaimed`, `contextWindow`, `inputMode`, `message`, `schema`, `url`,
    `decisions`)
  - `sealed class ConversationItemModel extends Equatable` — `id`, `turnId`, `sequence (int)`,
    `revision (int)`, `createdAt`; `String get itemKey`
  - `final class ConversationMessageModel extends ConversationItemModel` — `role`, `origin`, `text`,
    `streaming (bool)`, `delivery`, `senderLabel`
  - `final class ConversationActivityModel extends ConversationItemModel` — `activityKind`,
    `status`, `summary`, `detail (ActivityDetailModel?)`, `requestId`, `providerItemId`,
    `decisions (List<DecisionOptionModel>?)`
  - `class ConversationTurnModel extends Equatable` — `id`, `state`, `providerTurnId`,
    `errorMessage`, `requestedAt`, `startedAt`, `completedAt`, `rolledBack (bool)`,
    `diffFiles (List<DiffFileModel>)`, `diffTruncated (bool)`, `hasDiff (bool)`,
    `planSteps (List<PlanStepModel>)`, `planExplanation`, `hasPlan (bool)`
  - `class TurnSettingsModel extends Equatable` — `model`, `reasoningEffort`, `approvalMode`;
    `Map<String, dynamic> toJson()`
  - `class ConversationUsageModel`, `ConversationRateLimitsModel`, `ConversationAccountModel`,
    `ConversationThreadStateModel`, `McpServerModel`, `ModelRerouteModel`
  - `class ConversationSnapshotModel extends Equatable` — every field above, plus
    `ConversationSnapshotModel.fromJson`, `copyWith({oldestSequence, hasMoreBefore, items, turns})`,
    `bool can(String capability)`, `ConversationTurnModel? get activeTurn`,
    `ConversationTurnModel? turnForItem(ConversationItemModel item)`,
    `List<McpServerModel> get brokenMcpServers`, `bool get hasTurnInFlight`,
    `bool get hasPendingRequest`

Scalar fields are nullable per the spec; **list fields are non-null with a `const []` default**,
which is the shape `BoardSnapshot` already established in M2 and which spares the timeline a null
check on every render.

`ActivityDetailModel` keeps the raw map. `ActivityDetail` in RN is an open bag with an index
signature — providers put fields there that Operator does not model, and the daemon adds more over
time. Re-serializing into a closed Dart class would silently drop them; the getters cover what the
UI reads and `raw` keeps the rest reachable.

Three wire conversions carry real behavior and are what the test pins:

- `controller` arrives as a **bare string**, not an object (`{controller: "busy"}` → `controllerState`).
- `oldestSequence` falls back to `latestSequence + 1`, which is what "nothing loaded yet" means.
- `detail.decisions` entries with no string `id` are dropped; a missing `label` falls back to the
  `id`; an empty result becomes `null`, not `[]`, so the approval card can tell "no decisions
  offered" from "decisions not parsed".

`items` is `messages + activities` sorted by `sequence`, exactly as `toSnapshot` does — the daemon
sends them as two arrays and the timeline needs one ordered stream.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/data/model/conversation_snapshot_model_test.dart` (the
conversation-mapping half of the ledger's `chatModeApi.test.ts` row):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';

Map<String, dynamic> wire({
  List<dynamic> messages = const [],
  List<dynamic> activities = const [],
  List<dynamic> turns = const [],
  Map<String, dynamic> extra = const {},
}) => {
      'conversationId': 'c-1',
      'sessionId': 'w-1',
      'harness': 'claude-code',
      'mode': 'chat',
      'controller': 'busy',
      'latestSequence': 2,
      'settings': <String, dynamic>{},
      'messages': messages,
      'activities': activities,
      'turns': turns,
      ...extra,
    };

void main() {
  group('ConversationSnapshotModel', () {
    test('maps the provider-neutral wire model without inventing protocol state', () {
      final snapshot = ConversationSnapshotModel.fromJson(wire(
        activities: [
          {
            'id': 'a-1',
            'sequence': 2,
            'revision': 1,
            'activityKind': 'approval',
            'status': 'pending',
            'summary': 'Run command',
            'requestId': 'req-1',
            'detail': {
              'output': {'text': 'legacy'},
              'decisions': [
                {'id': 'accept'},
                {'id': '', 'label': 'ignored'},
                {'label': 'no id'},
              ],
            },
            'createdAt': '2026-08-05T00:00:00Z',
          },
        ],
        extra: {'capabilities': ['config_options', 'steer']},
      ));

      expect(snapshot.controllerState, 'busy');
      expect(snapshot.capabilities, ['config_options', 'steer']);
      expect(snapshot.can('steer'), isTrue);
      expect(snapshot.can('rollback'), isFalse);

      final activity = snapshot.items.single as ConversationActivityModel;
      expect(activity.activityKind, 'approval');
      expect(activity.requestId, 'req-1');
      expect(activity.decisions, hasLength(1));
      expect(activity.decisions!.single.id, 'accept');
      expect(activity.decisions!.single.label, 'accept');
      expect(activity.detail!.output, {'text': 'legacy'});
      expect(activity.detail!.raw['output'], {'text': 'legacy'});
    });

    test('leaves decisions absent rather than empty when none parse', () {
      final snapshot = ConversationSnapshotModel.fromJson(wire(activities: [
        {'id': 'a-1', 'sequence': 1, 'activityKind': 'approval', 'status': 'pending', 'detail': {'decisions': <dynamic>[]}},
      ]));
      expect((snapshot.items.single as ConversationActivityModel).decisions, isNull);
    });

    test('interleaves messages and activities by sequence', () {
      final snapshot = ConversationSnapshotModel.fromJson(wire(
        messages: [
          {'id': 'm-1', 'sequence': 1, 'role': 'user', 'origin': 'human', 'text': 'hi'},
          {'id': 'm-2', 'sequence': 3, 'role': 'assistant', 'origin': 'provider', 'text': 'done'},
        ],
        activities: [
          {'id': 'a-1', 'sequence': 2, 'activityKind': 'command', 'status': 'completed', 'summary': 'ls'},
        ],
      ));
      expect(snapshot.items.map((item) => item.id), ['m-1', 'a-1', 'm-2']);
      expect(snapshot.items.first, isA<ConversationMessageModel>());
      expect(snapshot.items[1], isA<ConversationActivityModel>());
      expect(snapshot.items.first.itemKey, 'message:m-1');
      expect(snapshot.items[1].itemKey, 'activity:a-1');
    });

    test('treats a missing oldestSequence as one past the newest row', () {
      expect(ConversationSnapshotModel.fromJson(wire()).oldestSequence, 3);
      expect(ConversationSnapshotModel.fromJson(wire()).hasMoreBefore, isFalse);
      expect(
        ConversationSnapshotModel.fromJson(wire(extra: {'oldestSequence': 1, 'hasMoreBefore': true}))
            .oldestSequence,
        1,
      );
    });

    test('drops empty setting strings so the picker shows the provider default', () {
      final snapshot = ConversationSnapshotModel.fromJson(
        wire(extra: {'settings': {'model': '', 'reasoningEffort': 'high', 'approvalMode': ''}}),
      );
      expect(snapshot.settings.model, isNull);
      expect(snapshot.settings.reasoningEffort, 'high');
      expect(snapshot.settings.approvalMode, isNull);
    });

    test('reads turn plans, diffs and lifecycle helpers', () {
      final snapshot = ConversationSnapshotModel.fromJson(wire(turns: [
        {'id': 't-1', 'state': 'completed', 'providerTurnId': 'p-1', 'requestedAt': '2026-08-05T00:00:00Z'},
        {
          'id': 't-2',
          'state': 'running',
          'requestedAt': '2026-08-05T00:00:01Z',
          'plan': {'explanation': 'why', 'steps': [{'text': 'Do it', 'status': 'in_progress'}]},
          'diff': {
            'truncated': true,
            'files': [
              {'path': 'a.dart', 'status': 'added', 'additions': 3, 'deletions': 0},
              {'path': 'b.dart', 'status': 'nonsense'},
            ],
          },
        },
      ]));

      expect(snapshot.activeTurn?.id, 't-2');
      expect(snapshot.hasTurnInFlight, isTrue);
      expect(snapshot.turns[1].planSteps.single.text, 'Do it');
      expect(snapshot.turns[1].planExplanation, 'why');
      expect(snapshot.turns[1].hasPlan, isTrue);
      expect(snapshot.turns[1].diffTruncated, isTrue);
      expect(snapshot.turns[1].diffFiles.first.additions, 3);
      expect(snapshot.turns[1].diffFiles[1].status, 'modified');
      expect(snapshot.turns[0].hasPlan, isFalse);
    });

    test('prefers a running turn but accepts a queued one', () {
      final queued = ConversationSnapshotModel.fromJson(wire(turns: [
        {'id': 't-1', 'state': 'completed', 'requestedAt': '2026-08-05T00:00:00Z'},
        {'id': 't-2', 'state': 'queued', 'requestedAt': '2026-08-05T00:00:01Z'},
      ]));
      expect(queued.activeTurn?.id, 't-2');
      expect(queued.hasTurnInFlight, isTrue);
    });

    test('reports pending requests and broken MCP servers', () {
      final snapshot = ConversationSnapshotModel.fromJson(wire(
        activities: [
          {'id': 'a-1', 'sequence': 1, 'activityKind': 'user_input', 'status': 'pending', 'summary': 'Sign in'},
        ],
        extra: {
          'mcpServers': [
            {'name': 'github', 'status': 'failed', 'error': 'token expired'},
            {'name': 'fs', 'status': 'ready'},
          ],
        },
      ));
      expect(snapshot.hasPendingRequest, isTrue);
      expect(snapshot.brokenMcpServers.map((server) => server.name), ['github']);
    });

    test('parses the elicitation schema the input card renders', () {
      final snapshot = ConversationSnapshotModel.fromJson(wire(activities: [
        {
          'id': 'a-1',
          'sequence': 1,
          'activityKind': 'user_input',
          'status': 'pending',
          'summary': 'Sign in',
          'detail': {
            'inputMode': 'form',
            'schema': {
              'title': 'Credentials',
              'required': ['token'],
              'properties': {
                'token': {'type': 'string', 'title': 'Token', 'minLength': 8},
                'scopes': {
                  'type': 'array',
                  'items': {
                    'anyOf': [
                      {'const': 'read', 'title': 'Read'},
                      {'const': 'write'},
                    ],
                  },
                },
              },
            },
          },
        },
      ]));

      final schema = (snapshot.items.single as ConversationActivityModel).detail!.schema!;
      expect(schema.title, 'Credentials');
      expect(schema.required, ['token']);
      expect(schema.properties['token']!.minLength, 8);
      expect(schema.properties['scopes']!.itemsAnyOf!.map((choice) => choice.label), ['Read', 'write']);
    });

    test('copyWith replaces only what pagination merges', () {
      final snapshot = ConversationSnapshotModel.fromJson(wire());
      final merged = snapshot.copyWith(oldestSequence: 1, hasMoreBefore: true, items: const [], turns: const []);
      expect(merged.oldestSequence, 1);
      expect(merged.hasMoreBefore, isTrue);
      expect(merged.conversationId, 'c-1');
      expect(merged.harness, 'claude-code');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/data/model/conversation_snapshot_model_test.dart`
Expected: FAIL — the model libraries do not exist.

- [ ] **Step 3: Write the detail model**

`packages/mobile/lib/feature/chat/data/model/activity_detail_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/logic/elicitation_model.dart';

const Set<String> _diffStatuses = {'added', 'modified', 'deleted', 'renamed'};

class DecisionOptionModel extends Equatable {
  const DecisionOptionModel({required this.id, required this.label});

  final String id;
  final String label;

  @override
  List<Object?> get props => [id, label];
}

class PlanStepModel extends Equatable {
  const PlanStepModel({required this.text, required this.status});

  final String text;
  final String status;

  factory PlanStepModel.fromJson(Map<String, dynamic> json) => PlanStepModel(
        text: json['text'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
      );

  static List<PlanStepModel> listFrom(dynamic value) => value is List
      ? value
          .whereType<Map<String, dynamic>>()
          .map(PlanStepModel.fromJson)
          .toList()
      : const [];

  @override
  List<Object?> get props => [text, status];
}

class DiffFileModel extends Equatable {
  const DiffFileModel({
    required this.path,
    required this.status,
    required this.additions,
    required this.deletions,
    this.oldPath,
    this.patch,
    this.patchTruncated = false,
  });

  final String path;
  final String? oldPath;
  final String status;
  final int additions;
  final int deletions;
  final String? patch;
  final bool patchTruncated;

  factory DiffFileModel.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    return DiffFileModel(
      path: json['path'] as String? ?? '',
      oldPath: json['oldPath'] as String?,
      status: status is String && _diffStatuses.contains(status) ? status : 'modified',
      additions: (json['additions'] as num?)?.toInt() ?? 0,
      deletions: (json['deletions'] as num?)?.toInt() ?? 0,
      patch: json['patch'] as String?,
      patchTruncated: json['patchTruncated'] == true,
    );
  }

  static List<DiffFileModel> listFrom(dynamic value) => value is List
      ? value
          .whereType<Map<String, dynamic>>()
          .where((file) => file['path'] is String)
          .map(DiffFileModel.fromJson)
          .toList()
      : const [];

  @override
  List<Object?> get props => [path, oldPath, status, additions, deletions, patch, patchTruncated];
}

class InputPropertyModel extends Equatable implements ElicitationProperty {
  const InputPropertyModel({
    this.type,
    this.title,
    this.description,
    this.defaultValue,
    this.enumValues,
    this.oneOf,
    this.itemsAnyOf,
    this.minimum,
    this.maximum,
    this.minLength,
    this.maxLength,
  });

  @override
  final String? type;
  @override
  final String? title;
  @override
  final String? description;
  @override
  final dynamic defaultValue;
  @override
  final List<dynamic>? enumValues;
  @override
  final List<InputChoice>? oneOf;
  @override
  final List<InputChoice>? itemsAnyOf;
  @override
  final num? minimum;
  @override
  final num? maximum;
  @override
  final int? minLength;
  @override
  final int? maxLength;

  factory InputPropertyModel.fromJson(Map<String, dynamic> json) => InputPropertyModel(
        type: json['type'] as String?,
        title: json['title'] as String?,
        description: json['description'] as String?,
        defaultValue: json['default'],
        enumValues: json['enum'] as List<dynamic>?,
        oneOf: _choices(json['oneOf']),
        itemsAnyOf: _choices((json['items'] as Map<String, dynamic>?)?['anyOf']),
        minimum: json['minimum'] as num?,
        maximum: json['maximum'] as num?,
        minLength: (json['minLength'] as num?)?.toInt(),
        maxLength: (json['maxLength'] as num?)?.toInt(),
      );

  static List<InputChoice>? _choices(dynamic value) {
    if (value is! List) return null;
    final choices = value
        .whereType<Map<String, dynamic>>()
        .where((candidate) => candidate['const'] is String)
        .map(
          (candidate) => InputChoice(
            value: candidate['const'] as String,
            label: (candidate['title'] as String?)?.isNotEmpty == true
                ? candidate['title'] as String
                : candidate['const'] as String,
            description: candidate['description'] as String?,
          ),
        )
        .toList();
    return choices.isEmpty ? null : choices;
  }

  @override
  List<Object?> get props =>
      [type, title, description, defaultValue, enumValues, oneOf, itemsAnyOf, minimum, maximum, minLength, maxLength];
}

class InputSchemaModel extends Equatable {
  const InputSchemaModel({
    this.title,
    this.description,
    this.required = const [],
    this.properties = const {},
  });

  final String? title;
  final String? description;
  final List<String> required;
  final Map<String, InputPropertyModel> properties;

  factory InputSchemaModel.fromJson(Map<String, dynamic> json) => InputSchemaModel(
        title: json['title'] as String?,
        description: json['description'] as String?,
        required: (json['required'] as List<dynamic>? ?? const []).whereType<String>().toList(),
        properties: {
          for (final entry in (json['properties'] as Map<String, dynamic>? ?? const {}).entries)
            if (entry.value is Map<String, dynamic>)
              entry.key: InputPropertyModel.fromJson(entry.value as Map<String, dynamic>),
        },
      );

  @override
  List<Object?> get props => [title, description, required, properties];
}

class ActivityDetailModel extends Equatable {
  const ActivityDetailModel(this.raw);

  final Map<String, dynamic> raw;

  factory ActivityDetailModel.fromJson(Map<String, dynamic> json) => ActivityDetailModel(json);

  String? get text => raw['text'] as String?;
  String? get command => raw['command'] as String?;
  String? get cwd => raw['cwd'] as String?;
  dynamic get output => raw['output'];
  String? get outputSource => raw['outputSource'] as String?;
  bool get outputMayBePartial => raw['outputMayBePartial'] == true;
  bool get outputTruncated => raw['outputTruncated'] == true;
  String? get reason => raw['reason'] as String?;
  String? get terminalInput => raw['terminalInput'] as String?;
  bool get terminalInputTruncated => raw['terminalInputTruncated'] == true;
  String? get parentProviderItemId => raw['parentProviderItemId'] as String?;
  dynamic get files => raw['files'];
  String? get patchOutput => raw['patchOutput'] as String?;
  bool get patchOutputTruncated => raw['patchOutputTruncated'] == true;
  String? get server => raw['server'] as String?;
  String? get toolName => raw['toolName'] as String?;
  String? get namespace => raw['namespace'] as String?;
  dynamic get arguments => raw['arguments'];
  dynamic get result => raw['result'];
  String? get error => raw['error'] as String?;
  bool? get success => raw['success'] as bool?;
  String? get progress => raw['progress'] as String?;
  bool get progressTruncated => raw['progressTruncated'] == true;
  String? get riskLevel => raw['riskLevel'] as String?;
  String? get rationale => raw['rationale'] as String?;
  String? get decisionSource => raw['decisionSource'] as String?;
  String? get status => raw['status'] as String?;
  String? get host => raw['host'] as String?;
  String? get event => raw['event'] as String?;
  String? get fromModel => raw['fromModel'] as String?;
  String? get toModel => raw['toModel'] as String?;
  String? get explanation => raw['explanation'] as String?;
  List<PlanStepModel> get steps => PlanStepModel.listFrom(raw['steps']);
  int? get tokensAfter => (raw['tokensAfter'] as num?)?.toInt();
  int? get tokensReclaimed => (raw['tokensReclaimed'] as num?)?.toInt();
  int? get contextWindow => (raw['contextWindow'] as num?)?.toInt();
  String? get inputMode => raw['inputMode'] as String?;
  String? get message => raw['message'] as String?;
  String? get url => raw['url'] as String?;

  InputSchemaModel? get schema {
    final value = raw['schema'];
    return value is Map<String, dynamic> ? InputSchemaModel.fromJson(value) : null;
  }

  List<DecisionOptionModel>? get decisions {
    final value = raw['decisions'];
    if (value is! List) return null;
    final decisions = value
        .whereType<Map<String, dynamic>>()
        .where((option) => option['id'] is String && (option['id'] as String).isNotEmpty)
        .map(
          (option) => DecisionOptionModel(
            id: option['id'] as String,
            label: option['label'] is String && (option['label'] as String).isNotEmpty
                ? option['label'] as String
                : option['id'] as String,
          ),
        )
        .toList();
    return decisions.isEmpty ? null : decisions;
  }

  @override
  List<Object?> get props => [raw];
}
```

- [ ] **Step 4: Write the item and turn models**

`packages/mobile/lib/feature/chat/data/model/conversation_item_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';

sealed class ConversationItemModel extends Equatable {
  const ConversationItemModel({
    required this.id,
    required this.sequence,
    required this.revision,
    this.turnId,
    this.createdAt,
  });

  final String id;
  final String? turnId;
  final int sequence;
  final int revision;
  final String? createdAt;

  String get itemKey;
}

final class ConversationMessageModel extends ConversationItemModel {
  const ConversationMessageModel({
    required super.id,
    required super.sequence,
    required super.revision,
    super.turnId,
    super.createdAt,
    this.role,
    this.origin,
    this.text = '',
    this.streaming = false,
    this.delivery,
    this.senderLabel,
  });

  final String? role;
  final String? origin;
  final String text;
  final bool streaming;
  final String? delivery;
  final String? senderLabel;

  factory ConversationMessageModel.fromJson(Map<String, dynamic> json) => ConversationMessageModel(
        id: json['id'] as String? ?? '',
        turnId: json['turnId'] as String?,
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] as String?,
        role: json['role'] as String?,
        origin: json['origin'] as String?,
        text: json['text'] as String? ?? '',
        streaming: json['streaming'] == true,
        delivery: json['delivery'] as String?,
        senderLabel: json['senderLabel'] as String?,
      );

  @override
  String get itemKey => 'message:$id';

  @override
  List<Object?> get props =>
      [id, turnId, sequence, revision, createdAt, role, origin, text, streaming, delivery, senderLabel];
}

final class ConversationActivityModel extends ConversationItemModel {
  const ConversationActivityModel({
    required super.id,
    required super.sequence,
    required super.revision,
    super.turnId,
    super.createdAt,
    this.activityKind,
    this.status,
    this.summary = '',
    this.detail,
    this.requestId,
    this.providerItemId,
    this.decisions,
  });

  final String? activityKind;
  final String? status;
  final String summary;
  final ActivityDetailModel? detail;
  final String? requestId;
  final String? providerItemId;
  final List<DecisionOptionModel>? decisions;

  factory ConversationActivityModel.fromJson(Map<String, dynamic> json) {
    final detail = json['detail'];
    final parsed = detail is Map<String, dynamic> ? ActivityDetailModel.fromJson(detail) : null;
    return ConversationActivityModel(
      id: json['id'] as String? ?? '',
      turnId: json['turnId'] as String?,
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String?,
      activityKind: json['activityKind'] as String?,
      status: json['status'] as String?,
      summary: json['summary'] as String? ?? '',
      detail: parsed,
      requestId: json['requestId'] as String?,
      providerItemId: json['providerItemId'] as String?,
      decisions: parsed?.decisions,
    );
  }

  bool get isPending => status == 'pending';

  @override
  String get itemKey => 'activity:$id';

  @override
  List<Object?> get props => [
        id,
        turnId,
        sequence,
        revision,
        createdAt,
        activityKind,
        status,
        summary,
        detail,
        requestId,
        providerItemId,
        decisions,
      ];
}
```

`packages/mobile/lib/feature/chat/data/model/conversation_turn_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';

class ConversationTurnModel extends Equatable {
  const ConversationTurnModel({
    required this.id,
    this.state,
    this.providerTurnId,
    this.errorMessage,
    this.requestedAt,
    this.startedAt,
    this.completedAt,
    this.rolledBack = false,
    this.hasDiff = false,
    this.diffFiles = const [],
    this.diffTruncated = false,
    this.planExplanation,
    this.planSteps = const [],
  });

  final String id;
  final String? state;
  final String? providerTurnId;
  final String? errorMessage;
  final String? requestedAt;
  final String? startedAt;
  final String? completedAt;
  final bool rolledBack;
  final bool hasDiff;
  final List<DiffFileModel> diffFiles;
  final bool diffTruncated;
  final String? planExplanation;
  final List<PlanStepModel> planSteps;

  factory ConversationTurnModel.fromJson(Map<String, dynamic> json) {
    final diff = json['diff'] as Map<String, dynamic>?;
    final plan = json['plan'] as Map<String, dynamic>?;
    return ConversationTurnModel(
      id: json['id'] as String? ?? '',
      state: json['state'] as String?,
      providerTurnId: json['providerTurnId'] as String?,
      errorMessage: json['errorMessage'] as String?,
      requestedAt: json['requestedAt'] as String?,
      startedAt: json['startedAt'] as String?,
      completedAt: json['completedAt'] as String?,
      rolledBack: json['rolledBack'] == true,
      hasDiff: diff != null,
      diffFiles: DiffFileModel.listFrom(diff?['files']),
      diffTruncated: diff?['truncated'] == true,
      planExplanation: plan?['explanation'] as String?,
      planSteps: PlanStepModel.listFrom(plan?['steps']),
    );
  }

  bool get hasPlan => planSteps.isNotEmpty;

  bool get isInFlight => state == 'running' || state == 'queued';

  @override
  List<Object?> get props => [
        id,
        state,
        providerTurnId,
        errorMessage,
        requestedAt,
        startedAt,
        completedAt,
        rolledBack,
        hasDiff,
        diffFiles,
        diffTruncated,
        planExplanation,
        planSteps,
      ];
}
```

- [ ] **Step 5: Write the snapshot model**

`packages/mobile/lib/feature/chat/data/model/conversation_snapshot_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';

class TurnSettingsModel extends Equatable {
  const TurnSettingsModel({this.model, this.reasoningEffort, this.approvalMode});

  final String? model;
  final String? reasoningEffort;
  final String? approvalMode;

  factory TurnSettingsModel.fromJson(Map<String, dynamic>? json) => TurnSettingsModel(
        model: _present(json?['model']),
        reasoningEffort: _present(json?['reasoningEffort']),
        approvalMode: _present(json?['approvalMode']),
      );

  Map<String, dynamic> toJson() => {
        if (model != null) 'model': model,
        if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
        if (approvalMode != null) 'approvalMode': approvalMode,
      };

  TurnSettingsModel copyWith({String? model, String? reasoningEffort, String? approvalMode}) =>
      TurnSettingsModel(
        model: model ?? this.model,
        reasoningEffort: reasoningEffort,
        approvalMode: approvalMode ?? this.approvalMode,
      );

  static String? _present(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;

  @override
  List<Object?> get props => [model, reasoningEffort, approvalMode];
}

class ConversationUsageModel extends Equatable {
  const ConversationUsageModel({
    this.contextUsed,
    this.contextWindow,
    this.inputTokens,
    this.outputTokens,
    this.cachedTokens,
    this.totalTokens,
    this.cost,
    this.currency,
  });

  final int? contextUsed;
  final int? contextWindow;
  final int? inputTokens;
  final int? outputTokens;
  final int? cachedTokens;
  final int? totalTokens;
  final double? cost;
  final String? currency;

  factory ConversationUsageModel.fromJson(Map<String, dynamic> json) => ConversationUsageModel(
        contextUsed: (json['contextUsed'] as num?)?.toInt(),
        contextWindow: (json['contextWindow'] as num?)?.toInt(),
        inputTokens: (json['inputTokens'] as num?)?.toInt(),
        outputTokens: (json['outputTokens'] as num?)?.toInt(),
        cachedTokens: (json['cachedTokens'] as num?)?.toInt(),
        totalTokens: (json['totalTokens'] as num?)?.toInt(),
        cost: (json['cost'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
      );

  @override
  List<Object?> get props =>
      [contextUsed, contextWindow, inputTokens, outputTokens, cachedTokens, totalTokens, cost, currency];
}

class ConversationRateLimitsModel extends Equatable {
  const ConversationRateLimitsModel({
    this.primaryUsedPercent,
    this.secondaryUsedPercent,
    this.primaryResetsInSeconds,
    this.secondaryResetsInSeconds,
    this.planLabel,
  });

  final num? primaryUsedPercent;
  final num? secondaryUsedPercent;
  final int? primaryResetsInSeconds;
  final int? secondaryResetsInSeconds;
  final String? planLabel;

  factory ConversationRateLimitsModel.fromJson(Map<String, dynamic> json) => ConversationRateLimitsModel(
        primaryUsedPercent: json['primaryUsedPercent'] as num?,
        secondaryUsedPercent: json['secondaryUsedPercent'] as num?,
        primaryResetsInSeconds: (json['primaryResetsInSeconds'] as num?)?.toInt(),
        secondaryResetsInSeconds: (json['secondaryResetsInSeconds'] as num?)?.toInt(),
        planLabel: json['planLabel'] as String?,
      );

  @override
  List<Object?> get props => [
        primaryUsedPercent,
        secondaryUsedPercent,
        primaryResetsInSeconds,
        secondaryResetsInSeconds,
        planLabel,
      ];
}

class ConversationAccountModel extends Equatable {
  const ConversationAccountModel({this.authMode, this.planLabel, this.reauthRequiredAt, this.reauthReason});

  final String? authMode;
  final String? planLabel;
  final String? reauthRequiredAt;
  final String? reauthReason;

  factory ConversationAccountModel.fromJson(Map<String, dynamic> json) => ConversationAccountModel(
        authMode: json['authMode'] as String?,
        planLabel: json['planLabel'] as String?,
        reauthRequiredAt: json['reauthRequiredAt'] as String?,
        reauthReason: json['reauthReason'] as String?,
      );

  @override
  List<Object?> get props => [authMode, planLabel, reauthRequiredAt, reauthReason];
}

class ConversationThreadStateModel extends Equatable {
  const ConversationThreadStateModel({this.status, this.waitingOn = const [], this.archivedAt, this.closedAt});

  final String? status;
  final List<String> waitingOn;
  final String? archivedAt;
  final String? closedAt;

  factory ConversationThreadStateModel.fromJson(Map<String, dynamic> json) => ConversationThreadStateModel(
        status: json['status'] as String?,
        waitingOn: (json['waitingOn'] as List<dynamic>? ?? const []).whereType<String>().toList(),
        archivedAt: json['archivedAt'] as String?,
        closedAt: json['closedAt'] as String?,
      );

  @override
  List<Object?> get props => [status, waitingOn, archivedAt, closedAt];
}

class McpServerModel extends Equatable {
  const McpServerModel({required this.name, this.status, this.error, this.failureReason});

  final String name;
  final String? status;
  final String? error;
  final String? failureReason;

  factory McpServerModel.fromJson(Map<String, dynamic> json) => McpServerModel(
        name: json['name'] as String? ?? '',
        status: json['status'] as String?,
        error: json['error'] as String?,
        failureReason: json['failureReason'] as String?,
      );

  bool get isBroken => status == 'failed' || status == 'cancelled';

  @override
  List<Object?> get props => [name, status, error, failureReason];
}

class ModelRerouteModel extends Equatable {
  const ModelRerouteModel({this.fromModel, this.toModel, this.reason, this.at});

  final String? fromModel;
  final String? toModel;
  final String? reason;
  final String? at;

  factory ModelRerouteModel.fromJson(Map<String, dynamic> json) => ModelRerouteModel(
        fromModel: json['fromModel'] as String?,
        toModel: json['toModel'] as String?,
        reason: json['reason'] as String?,
        at: json['at'] as String?,
      );

  @override
  List<Object?> get props => [fromModel, toModel, reason, at];
}

class ConversationSnapshotModel extends Equatable {
  const ConversationSnapshotModel({
    this.conversationId,
    this.sessionId,
    this.harness,
    this.mode,
    this.controllerState,
    this.controllerError,
    this.latestSequence = 0,
    this.oldestSequence = 0,
    this.hasMoreBefore = false,
    this.turns = const [],
    this.items = const [],
    this.settings = const TurnSettingsModel(),
    this.title,
    this.usage,
    this.rateLimits,
    this.compactedAt,
    this.modelReroute,
    this.account,
    this.threadState,
    this.mcpServers = const [],
    this.capabilities = const [],
  });

  final String? conversationId;
  final String? sessionId;
  final String? harness;
  final String? mode;
  final String? controllerState;
  final String? controllerError;
  final int latestSequence;
  final int oldestSequence;
  final bool hasMoreBefore;
  final List<ConversationTurnModel> turns;
  final List<ConversationItemModel> items;
  final TurnSettingsModel settings;
  final String? title;
  final ConversationUsageModel? usage;
  final ConversationRateLimitsModel? rateLimits;
  final String? compactedAt;
  final ModelRerouteModel? modelReroute;
  final ConversationAccountModel? account;
  final ConversationThreadStateModel? threadState;
  final List<McpServerModel> mcpServers;
  final List<String> capabilities;

  factory ConversationSnapshotModel.fromJson(Map<String, dynamic> json) {
    final controller = json['controller'];
    final latestSequence = (json['latestSequence'] as num?)?.toInt() ?? 0;
    final items = <ConversationItemModel>[
      ...(json['messages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ConversationMessageModel.fromJson),
      ...(json['activities'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ConversationActivityModel.fromJson),
    ]..sort((left, right) => left.sequence.compareTo(right.sequence));

    return ConversationSnapshotModel(
      conversationId: json['conversationId'] as String?,
      sessionId: json['sessionId'] as String?,
      harness: json['harness'] as String?,
      mode: json['mode'] as String?,
      controllerState: controller is String ? controller : (controller as Map<String, dynamic>?)?['state'] as String?,
      controllerError: controller is Map<String, dynamic> ? controller['error'] as String? : json['controllerError'] as String?,
      latestSequence: latestSequence,
      oldestSequence: (json['oldestSequence'] as num?)?.toInt() ?? latestSequence + 1,
      hasMoreBefore: json['hasMoreBefore'] == true,
      turns: (json['turns'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ConversationTurnModel.fromJson)
          .toList(),
      items: items,
      settings: TurnSettingsModel.fromJson(json['settings'] as Map<String, dynamic>?),
      title: json['title'] as String?,
      usage: json['usage'] is Map<String, dynamic>
          ? ConversationUsageModel.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      rateLimits: json['rateLimits'] is Map<String, dynamic>
          ? ConversationRateLimitsModel.fromJson(json['rateLimits'] as Map<String, dynamic>)
          : null,
      compactedAt: json['compactedAt'] as String?,
      modelReroute: json['modelReroute'] is Map<String, dynamic>
          ? ModelRerouteModel.fromJson(json['modelReroute'] as Map<String, dynamic>)
          : null,
      account: json['account'] is Map<String, dynamic>
          ? ConversationAccountModel.fromJson(json['account'] as Map<String, dynamic>)
          : null,
      threadState: json['threadState'] is Map<String, dynamic>
          ? ConversationThreadStateModel.fromJson(json['threadState'] as Map<String, dynamic>)
          : null,
      mcpServers: (json['mcpServers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(McpServerModel.fromJson)
          .toList(),
      capabilities: (json['capabilities'] as List<dynamic>? ?? const []).whereType<String>().toList(),
    );
  }

  ConversationSnapshotModel copyWith({
    int? oldestSequence,
    bool? hasMoreBefore,
    List<ConversationItemModel>? items,
    List<ConversationTurnModel>? turns,
  }) =>
      ConversationSnapshotModel(
        conversationId: conversationId,
        sessionId: sessionId,
        harness: harness,
        mode: mode,
        controllerState: controllerState,
        controllerError: controllerError,
        latestSequence: latestSequence,
        oldestSequence: oldestSequence ?? this.oldestSequence,
        hasMoreBefore: hasMoreBefore ?? this.hasMoreBefore,
        turns: turns ?? this.turns,
        items: items ?? this.items,
        settings: settings,
        title: title,
        usage: usage,
        rateLimits: rateLimits,
        compactedAt: compactedAt,
        modelReroute: modelReroute,
        account: account,
        threadState: threadState,
        mcpServers: mcpServers,
        capabilities: capabilities,
      );

  bool can(String capability) => capabilities.contains(capability);

  ConversationTurnModel? get activeTurn {
    for (final turn in turns) {
      if (turn.state == 'running') return turn;
    }
    for (final turn in turns) {
      if (turn.state == 'queued') return turn;
    }
    return null;
  }

  ConversationTurnModel? turnForItem(ConversationItemModel item) {
    if (item.turnId == null) return null;
    for (final turn in turns) {
      if (turn.id == item.turnId) return turn;
    }
    return null;
  }

  bool get hasTurnInFlight => turns.any((turn) => turn.isInFlight);

  bool get hasPendingRequest => items.any(
        (item) =>
            item is ConversationActivityModel &&
            item.isPending &&
            (item.activityKind == 'approval' || item.activityKind == 'user_input'),
      );

  List<McpServerModel> get brokenMcpServers =>
      mcpServers.where((server) => server.isBroken).toList();

  @override
  List<Object?> get props => [
        conversationId,
        sessionId,
        harness,
        mode,
        controllerState,
        controllerError,
        latestSequence,
        oldestSequence,
        hasMoreBefore,
        turns,
        items,
        settings,
        title,
        usage,
        rateLimits,
        compactedAt,
        modelReroute,
        account,
        threadState,
        mcpServers,
        capabilities,
      ];
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/data/model/conversation_snapshot_model_test.dart`
Expected: PASS.

- [ ] **Step 7: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 469/469 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port the conversation wire model"
```

---

### Task 12: Page merging (`snapshot.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/conversation_pages.dart`
- Test: `packages/mobile/test/feature/chat/logic/snapshot_test.dart`

**Interfaces:**
- Consumes: `ConversationSnapshotModel`, `ConversationItemModel`, `ConversationTurnModel` (Task 11).
- Produces:
  - `List<ConversationSnapshotModel> discardHistoricalPages(List<ConversationSnapshotModel> pages)`
  - `ConversationSnapshotModel? mergeConversationPages(List<ConversationSnapshotModel> pages)`

Pages are held newest-first: `pages[0]` is the live page, later entries are older history loaded by
"Load earlier messages".

A rollback rewrites the projection by removing rows. A live first page cannot carry tombstones for
rows cached in older pages, so those pages must be discarded before the authoritative refresh and
may be paged in again later — that is `discardHistoricalPages`.

The merge walks pages **oldest first** so a newer page replaces the same item or turn with its
latest revision when a page boundary overlaps a streaming update. The `oldestSequence` and
`hasMoreBefore` come from the oldest page; everything else comes from the live one.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/snapshot_test.dart` (ported from `chat/snapshot.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_pages.dart';

ConversationSnapshotModel page({
  int oldestSequence = 1,
  bool hasMoreBefore = false,
  List<ConversationItemModel> items = const [],
  List<ConversationTurnModel> turns = const [],
}) =>
    ConversationSnapshotModel(
      conversationId: 'conv-1',
      sessionId: 'session-1',
      harness: 'codex',
      mode: 'chat',
      controllerState: 'ready',
      latestSequence: 3,
      oldestSequence: oldestSequence,
      hasMoreBefore: hasMoreBefore,
      items: items,
      turns: turns,
    );

ConversationMessageModel message(String id, int sequence, {int revision = 1, String text = ''}) =>
    ConversationMessageModel(id: id, sequence: sequence, revision: revision, text: text);

void main() {
  group('mobile conversation pagination', () {
    test('keeps chronological order and the oldest page cursor', () {
      final merged = mergeConversationPages([
        page(oldestSequence: 3, hasMoreBefore: true, items: [message('m3', 3, text: 'new')]),
        page(oldestSequence: 1, items: [message('m1', 1, text: 'old')]),
      ])!;

      expect(merged.items.map((item) => item.id), ['m1', 'm3']);
      expect(merged.oldestSequence, 1);
      expect(merged.hasMoreBefore, isFalse);
    });

    test('lets the live page replace an overlapping streaming revision', () {
      final historical = message('m2', 2, text: 'hel');
      final live = message('m2', 2, revision: 2, text: 'hello');
      final merged = mergeConversationPages([page(items: [live]), page(items: [historical])])!;
      expect(merged.items, [live]);
    });

    test('keeps one row per turn, newest revision, ordered by request time', () {
      final merged = mergeConversationPages([
        page(turns: [
          const ConversationTurnModel(id: 't2', state: 'running', requestedAt: '2026-08-05T00:00:02Z'),
          const ConversationTurnModel(id: 't1', state: 'completed', requestedAt: '2026-08-05T00:00:01Z'),
        ]),
        page(turns: [
          const ConversationTurnModel(id: 't1', state: 'running', requestedAt: '2026-08-05T00:00:01Z'),
        ]),
      ])!;

      expect(merged.turns.map((turn) => turn.id), ['t1', 't2']);
      expect(merged.turns.first.state, 'completed');
    });

    test('drops stale historical rows before a rollback projection is reloaded', () {
      final live = page(oldestSequence: 3, hasMoreBefore: true);
      final historical = page();
      expect(discardHistoricalPages([live, historical]), [live]);
      expect(discardHistoricalPages(const []), isEmpty);
    });

    test('has nothing to merge before the first page lands', () {
      expect(mergeConversationPages(const []), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/snapshot_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/conversation_pages.dart`:

```dart
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';

List<ConversationSnapshotModel> discardHistoricalPages(List<ConversationSnapshotModel> pages) =>
    pages.isEmpty ? pages : pages.sublist(0, 1);

ConversationSnapshotModel? mergeConversationPages(List<ConversationSnapshotModel> pages) {
  if (pages.isEmpty) return null;
  final live = pages.first;
  final items = <String, ConversationItemModel>{};
  final turns = <String, ConversationTurnModel>{};

  for (final page in pages.reversed) {
    for (final item in page.items) {
      items[item.itemKey] = item;
    }
    for (final turn in page.turns) {
      turns[turn.id] = turn;
    }
  }

  final mergedItems = items.values.toList()
    ..sort((left, right) => left.sequence.compareTo(right.sequence));
  final mergedTurns = turns.values.toList()
    ..sort((left, right) => (left.requestedAt ?? '').compareTo(right.requestedAt ?? ''));
  final oldest = pages.last;

  return live.copyWith(
    oldestSequence: oldest.oldestSequence,
    hasMoreBefore: oldest.hasMoreBefore,
    items: mergedItems,
    turns: mergedTurns,
  );
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/snapshot_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 474/474 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port conversation page merging"
```

---

### Task 13: Timeline model (`timelineModel.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/timeline_model.dart`
- Test: `packages/mobile/test/feature/chat/logic/timeline_model_test.dart`

**Interfaces:**
- Consumes: the Task 11 models.
- Produces:
  - `class ConversationGroup extends Equatable` — `key`, `turnId`, `anchor (int)`,
    `items (List<ConversationItemModel>)`, `turn (ConversationTurnModel?)`
  - `class ConversationMarker extends Equatable` — `key`, `sequence (int)`, `title`,
    `detail (String?)`, `state (String?)`
  - `class ActivityNode` — `activity (ConversationActivityModel)`, `children (List<ActivityNode>)`
  - `List<ConversationItemModel> readableConversationItems(ConversationSnapshotModel snapshot)`
  - `List<ConversationGroup> groupConversationByTurn(ConversationSnapshotModel snapshot, [List<ConversationItemModel>? items])`
  - `List<ConversationMarker> conversationMarkers(ConversationSnapshotModel snapshot)`
  - `bool canRollbackTurn(ConversationSnapshotModel snapshot, ConversationTurnModel turn)`
  - `bool activityStartsExpanded(ConversationActivityModel activity)`
  - `List<ActivityNode> activityHierarchy(List<ConversationActivityModel> activities)`
  - `int countActivityNodes(List<ActivityNode> nodes)`
  - `bool activityNodesRunning(List<ActivityNode> nodes)`

Three rules here are load-bearing and are exactly what the mirrored test pins:

- A turn remains **one readable exchange** even when queued-message sequencing interleaves it with
  the turn currently running. This is presentation grouping over daemon-owned sequence and turn
  identities, never inferred lifecycle state.
- A group's key is `turn-<turnId>`, its **durable** identity. The first loaded item can move
  backward when an older page arrives; the turn id cannot. Keying on the item would reset expanded
  rows and scroll position on every pagination.
- `activityHierarchy` reconstructs provider-owned nested agent work without inventing lifecycle
  state. Unknown parents and malformed cycles stay visible as roots rather than disappearing.

Usage and reasoning rows are filtered out of the mobile timeline: they remain in the durable
record, but prose and work are the primary surface on a phone. A `plan` activity is dropped only
when its own turn already carries a plan, so the same plan is not rendered twice.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/timeline_model_test.dart` (ported from
`chat/timelineModel.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';

ConversationActivityModel activity(
  String kind,
  int sequence, {
  String? turnId = 't1',
  String status = 'completed',
  Map<String, dynamic>? detail,
  String? providerItemId,
}) =>
    ConversationActivityModel(
      id: '$kind-$sequence',
      turnId: turnId,
      sequence: sequence,
      revision: 1,
      activityKind: kind,
      status: status,
      summary: kind,
      providerItemId: providerItemId,
      detail: detail == null ? null : ActivityDetailModel(detail),
    );

ConversationSnapshotModel snapshot({
  List<ConversationTurnModel>? turns,
  List<ConversationItemModel>? items,
  List<String> capabilities = const ['rollback'],
}) =>
    ConversationSnapshotModel(
      conversationId: 'c',
      sessionId: 's',
      harness: 'codex',
      mode: 'chat',
      controllerState: 'ready',
      latestSequence: 4,
      oldestSequence: 1,
      capabilities: capabilities,
      turns: turns ??
          const [
            ConversationTurnModel(
                id: 't1', state: 'completed', providerTurnId: 'p1', requestedAt: '2026-08-05T00:00:00Z'),
            ConversationTurnModel(
                id: 't2', state: 'completed', providerTurnId: 'p2', requestedAt: '2026-08-05T00:00:01Z'),
          ],
      items: items ??
          const [
            ConversationMessageModel(
                id: 'u1', turnId: 't1', sequence: 1, revision: 1, role: 'user', origin: 'human', text: 'First task'),
            ConversationMessageModel(
                id: 'u2', turnId: 't2', sequence: 2, revision: 1, role: 'user', origin: 'human', text: 'Queued task'),
            ConversationMessageModel(
                id: 'a1',
                turnId: 't1',
                sequence: 3,
                revision: 1,
                role: 'assistant',
                origin: 'provider',
                text: 'First answer'),
            ConversationMessageModel(
                id: 'a2',
                turnId: 't2',
                sequence: 4,
                revision: 1,
                role: 'assistant',
                origin: 'provider',
                text: 'Queued answer'),
          ],
    );

void main() {
  group('mobile Chat timeline model', () {
    test('keeps queued questions with their own answers instead of strict-sequence interleaving', () {
      final groups = groupConversationByTurn(snapshot());
      expect(
        groups.map((group) => group.items.map((item) => item.id).toList()).toList(),
        [
          ['u1', 'a1'],
          ['u2', 'a2'],
        ],
      );

      final markers = conversationMarkers(snapshot());
      expect(markers.map((marker) => marker.sequence), [1, 2]);
      expect(markers.map((marker) => marker.title), ['First task', 'Queued task']);
      expect(markers.map((marker) => marker.detail), ['First answer', 'Queued answer']);
    });

    test('keys a loaded turn by durable identity rather than its current page boundary', () {
      final withoutFirst = snapshot(
        items: snapshot().items.where((item) => item.id != 'u1').toList(),
      );
      expect(
        groupConversationByTurn(withoutFirst).firstWhere((group) => group.turnId == 't1').key,
        'turn-t1',
      );
      expect(
        groupConversationByTurn(snapshot()).firstWhere((group) => group.turnId == 't1').key,
        'turn-t1',
      );
    });

    test('collects loose items with no turn into one trailing group', () {
      final loose = snapshot(items: [
        activity('system', 1, turnId: null),
        activity('system', 2, turnId: null),
      ]);
      final groups = groupConversationByTurn(loose);
      expect(groups, hasLength(1));
      expect(groups.single.key, 'loose-1');
      expect(groups.single.items, hasLength(2));
    });

    test('filters usage, reasoning and duplicate plan rows without hiding unknown work', () {
      final planned = snapshot(
        turns: const [
          ConversationTurnModel(
            id: 't1',
            state: 'completed',
            providerTurnId: 'p1',
            requestedAt: '2026-08-05T00:00:00Z',
            planSteps: [PlanStepModel(text: 'Do it', status: 'pending')],
          ),
        ],
        items: [
          activity('usage', 5),
          activity('reasoning', 6),
          activity('plan', 7),
          activity('system', 8),
        ],
      );
      expect(readableConversationItems(planned).map((item) => item.id), ['system-8']);
    });

    test('keeps a plan activity whose turn carries no plan of its own', () {
      final unplanned = snapshot(items: [activity('plan', 7)]);
      expect(readableConversationItems(unplanned).map((item) => item.id), ['plan-7']);
    });

    test('gates rollback on the daemon capability, accepted history and idle state', () {
      final idle = snapshot();
      expect(canRollbackTurn(idle, idle.turns.first), isTrue);

      final busy = snapshot(turns: const [
        ConversationTurnModel(id: 't1', state: 'completed', providerTurnId: 'p1', requestedAt: 'a'),
        ConversationTurnModel(id: 't2', state: 'running', providerTurnId: 'p2', requestedAt: 'b'),
      ]);
      expect(canRollbackTurn(busy, busy.turns.first), isFalse);

      final uncapable = snapshot(capabilities: const []);
      expect(canRollbackTurn(uncapable, uncapable.turns.first), isFalse);

      final unaccepted = snapshot(turns: const [
        ConversationTurnModel(id: 't1', state: 'completed', requestedAt: 'a'),
      ]);
      expect(canRollbackTurn(unaccepted, unaccepted.turns.first), isFalse);

      final already = snapshot(turns: const [
        ConversationTurnModel(id: 't1', state: 'completed', providerTurnId: 'p1', requestedAt: 'a', rolledBack: true),
      ]);
      expect(canRollbackTurn(already, already.turns.first), isFalse);
    });

    test('opens failed and live-output activities but keeps settled mechanics collapsed', () {
      expect(
        activityStartsExpanded(activity('command', 1, status: 'running', detail: {'output': 'tick'})),
        isTrue,
      );
      expect(
        activityStartsExpanded(activity('command', 1, status: 'completed', detail: {'output': 'tick'})),
        isFalse,
      );
      expect(activityStartsExpanded(activity('command', 1, status: 'failed')), isTrue);
      expect(activityStartsExpanded(activity('command', 1, status: 'cancelled')), isFalse);
      expect(activityStartsExpanded(activity('command', 1, status: 'running')), isFalse);
    });

    test('builds nested provider work without hiding or looping malformed events', () {
      final parent = activity('command', 1, providerItemId: 'parent');
      final child = activity('command', 2, providerItemId: 'child', detail: {'parentProviderItemId': 'parent'});
      final orphan = activity('command', 3, detail: {'parentProviderItemId': 'missing'});

      final roots = activityHierarchy([parent, child, orphan]);
      expect(roots.map((node) => node.activity.id), [parent.id, orphan.id]);
      expect(roots.first.children.single.activity.id, child.id);
      expect(countActivityNodes(roots), 3);
      expect(activityNodesRunning(roots), isFalse);

      final running = activity('command', 2, status: 'running', providerItemId: 'child', detail: {
        'parentProviderItemId': 'parent',
      });
      expect(activityNodesRunning(activityHierarchy([parent, running])), isTrue);

      final cyclicParent =
          activity('command', 1, providerItemId: 'parent', detail: {'parentProviderItemId': 'child'});
      expect(activityHierarchy([cyclicParent, child]), hasLength(2));
      expect(countActivityNodes(activityHierarchy([cyclicParent, child])), 2);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/timeline_model_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/timeline_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';

final RegExp _fence = RegExp(r'```[\s\S]*?```');
final RegExp _link = RegExp(r'\[([^\]]+)]\([^)]*\)');
final RegExp _marks = RegExp(r'[*_`#>~]+');
final RegExp _whitespaceRun = RegExp(r'\s+');

class ConversationGroup extends Equatable {
  const ConversationGroup({
    required this.key,
    required this.anchor,
    required this.items,
    this.turnId,
    this.turn,
  });

  final String key;
  final String? turnId;
  final int anchor;
  final List<ConversationItemModel> items;
  final ConversationTurnModel? turn;

  @override
  List<Object?> get props => [key, turnId, anchor, items, turn];
}

class ConversationMarker extends Equatable {
  const ConversationMarker({
    required this.key,
    required this.sequence,
    required this.title,
    this.detail,
    this.state,
  });

  final String key;
  final int sequence;
  final String title;
  final String? detail;
  final String? state;

  @override
  List<Object?> get props => [key, sequence, title, detail, state];
}

class ActivityNode {
  ActivityNode(this.activity);

  final ConversationActivityModel activity;
  final List<ActivityNode> children = [];
}

List<ConversationItemModel> readableConversationItems(ConversationSnapshotModel snapshot) {
  final plannedTurns = snapshot.turns.where((turn) => turn.hasPlan).map((turn) => turn.id).toSet();
  return snapshot.items.where((item) {
    if (item is! ConversationActivityModel) return true;
    if (item.activityKind == 'usage' || item.activityKind == 'reasoning') return false;
    return !(item.activityKind == 'plan' && item.turnId != null && plannedTurns.contains(item.turnId));
  }).toList();
}

List<ConversationGroup> groupConversationByTurn(
  ConversationSnapshotModel snapshot, [
  List<ConversationItemModel>? items,
]) {
  final rows = items ?? readableConversationItems(snapshot);
  final turns = {for (final turn in snapshot.turns) turn.id: turn};
  final byTurn = <String, List<ConversationItemModel>>{};
  final groups = <ConversationGroup>[];
  final looseItems = <int, List<ConversationItemModel>>{};

  for (final item in rows) {
    final turnId = item.turnId;
    if (turnId == null) {
      final previous = groups.isEmpty ? null : groups.last;
      if (previous != null && previous.turnId == null) {
        looseItems[previous.anchor]!.add(item);
      } else {
        final bucket = <ConversationItemModel>[item];
        looseItems[item.sequence] = bucket;
        groups.add(ConversationGroup(key: 'loose-${item.sequence}', anchor: item.sequence, items: bucket));
      }
      continue;
    }

    final existing = byTurn[turnId];
    if (existing != null) {
      existing.add(item);
      continue;
    }
    final bucket = <ConversationItemModel>[item];
    byTurn[turnId] = bucket;
    groups.add(ConversationGroup(
      key: 'turn-$turnId',
      turnId: turnId,
      anchor: item.sequence,
      items: bucket,
      turn: turns[turnId],
    ));
  }

  return groups..sort((left, right) => left.anchor.compareTo(right.anchor));
}

List<ConversationMarker> conversationMarkers(ConversationSnapshotModel snapshot) =>
    groupConversationByTurn(snapshot).map((group) {
      final human = group.items
          .whereType<ConversationMessageModel>()
          .where((item) => item.role == 'user' && item.origin == 'human')
          .firstOrNull;
      final assistant = group.items.reversed
          .whereType<ConversationMessageModel>()
          .where((item) => item.role == 'assistant' && item.text.trim().isNotEmpty)
          .firstOrNull;
      final activity = group.items.whereType<ConversationActivityModel>().firstOrNull;

      final title = _previewText(
        human?.text ?? (activity?.summary.isNotEmpty == true ? activity!.summary : 'Conversation update'),
        120,
      );
      final detailSource = assistant?.text ?? activity?.detail?.text ?? activity?.summary;
      final detail = detailSource == null || detailSource.isEmpty ? null : _previewText(detailSource, 240);

      return ConversationMarker(
        key: group.key,
        sequence: group.anchor,
        title: title,
        detail: detail != null && detail != title ? detail : null,
        state: group.turn?.state,
      );
    }).toList();

bool canRollbackTurn(ConversationSnapshotModel snapshot, ConversationTurnModel turn) =>
    snapshot.can('rollback') &&
    !snapshot.hasTurnInFlight &&
    !turn.isInFlight &&
    turn.providerTurnId != null &&
    !turn.rolledBack;

bool activityStartsExpanded(ConversationActivityModel activity) {
  final detail = activity.detail;
  final liveBody = activity.status == 'running' &&
      (detail?.output != null ||
          detail?.result != null ||
          detail?.error != null ||
          detail?.patchOutput != null);
  return activity.status == 'failed' || liveBody;
}

List<ActivityNode> activityHierarchy(List<ConversationActivityModel> activities) {
  final byProvider = <String, ActivityNode>{};
  final nodes = activities.map((activity) {
    final node = ActivityNode(activity);
    final providerItemId = activity.providerItemId;
    if (providerItemId != null) byProvider[providerItemId] = node;
    return node;
  }).toList();

  final roots = <ActivityNode>[];
  for (final node in nodes) {
    final parentId = node.activity.detail?.parentProviderItemId;
    final parent = parentId == null ? null : byProvider[parentId];
    if (parent != null && !_activityCycle(node, parent, byProvider)) {
      parent.children.add(node);
    } else {
      roots.add(node);
    }
  }
  return roots;
}

int countActivityNodes(List<ActivityNode> nodes) =>
    nodes.fold(0, (count, node) => count + 1 + countActivityNodes(node.children));

bool activityNodesRunning(List<ActivityNode> nodes) =>
    nodes.any((node) => node.activity.status == 'running' || activityNodesRunning(node.children));

bool _activityCycle(ActivityNode node, ActivityNode parent, Map<String, ActivityNode> byProvider) {
  final visited = <ActivityNode>{node};
  ActivityNode? current = parent;
  while (current != null) {
    if (visited.contains(current)) return true;
    visited.add(current);
    final parentId = current.activity.detail?.parentProviderItemId;
    current = parentId == null ? null : byProvider[parentId];
  }
  return false;
}

String _previewText(String value, int limit) {
  final plain = value
      .replaceAll(_fence, ' code sample ')
      .replaceAllMapped(_link, (match) => match.group(1)!)
      .replaceAll(_marks, ' ')
      .replaceAll(_whitespaceRun, ' ')
      .trim();
  return plain.length > limit ? '${plain.substring(0, limit - 1).trimRight()}…' : plain;
}
```

`firstOrNull` comes from `dart:collection`'s `IterableExtension`, which Flutter re-exports through
`package:flutter/foundation.dart`'s `collection` dependency. If the analyzer cannot resolve it, add
`import 'package:collection/collection.dart';` — `collection` is already a transitive dependency of
`flutter_test` and `equatable`.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/timeline_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 483/483 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port the chat timeline model"
```

---

### Task 14: The chat REST data source (`chat/api.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/data/model/chat_catalog_model.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/chat_attachment_model.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/workspace_paths_model.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/params/send_message_params.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/params/steer_conversation_params.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/params/resolve_approval_params.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/params/resolve_input_params.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/params/rollback_turn_params.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/params/set_conversation_title_params.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/params/set_config_option_params.dart`
- Create: `packages/mobile/lib/feature/chat/data/model/params/stage_attachments_params.dart`
- Create: `packages/mobile/lib/feature/chat/data/data_source/chat_remote_data_source.dart`
- Test: `packages/mobile/test/feature/chat/data/data_source/chat_remote_data_source_test.dart`

**Interfaces:**
- Consumes: `ApiConsumer`, `EndPoints` (Task 1), the Task 11 models, `TurnSettingsModel`.
- Produces:
  - `class ChatModelModel extends Equatable` — `id`, `displayName`, `description`, `isDefault (bool)`,
    `efforts (List<String>)`, `defaultEffort`
  - `class ChatConfigChoiceModel extends Equatable` — `value`, `name`, `description`, `group`, `groupName`
  - `class ChatConfigOptionModel extends Equatable` — `id`, `name`, `description`, `category`,
    `type`, `currentValue`, `currentBoolean`, `choices (List<ChatConfigChoiceModel>)`
  - `class ChatSkillModel extends Equatable implements SuggestibleSkill`
  - `class ChatImageModel extends Equatable` — `mimeType`, `data`; `toJson()`
  - `class ChatResourceModel extends Equatable` — `uri`, `name`, `mimeType`, `text`; `toJson()`
  - `class WorkspacePathsModel extends Equatable` — `paths (List<String>)`, `truncated (bool)`
  - the eight params classes, each with `toJson()`
  - `abstract class ChatRemoteDataSource` and `ChatRemoteDataSourceImp` with:
    `getConversationPage(String sessionId, {int? beforeSequence})`, `sendMessage`, `steer`,
    `interrupt`, `compact`, `resolveApproval`, `resolveInput`, `rollbackTurn`, `setTitle`,
    `getModels`, `setSettings`, `getConfigOptions`, `setConfigOption`, `getSkills`,
    `reloadMcpServers`, `stageAttachments`, `getWorkspacePaths`, `resumeAgent`

Every read parses with `GlobalResponse.fromJson(..., withDataKey: false)`, per the spec: the daemon
does not use a `data` key.

Three details are ported deliberately, not incidentally:

- **`CHAT_PAGE_SIZE` is 200** and travels as `limit`; `beforeSequence` is added only when paging.
- **`stageConversationAttachments` gets a 60-second timeout**, overriding the global 12s. Uploading
  photos over a home LAN routinely exceeds twelve seconds, and the spec's 12s rule exists for
  *sleeping-host detection*, not for uploads.
- **`getWorkspacePaths` drops `deleted` files** and preserves the daemon's `truncated` flag. The
  composer's `@` picker must not offer a path that no longer exists, and the truncation warning is
  what tells the user to type a path instead of scrolling.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/data/data_source/chat_remote_data_source_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_remote_data_source.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_input_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/rollback_turn_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/send_message_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_config_option_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/stage_attachments_params.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

void main() {
  late _MockApiConsumer apiConsumer;
  late ChatRemoteDataSource dataSource;

  Response<dynamic> jsonResponse(Map<String, dynamic> body) =>
      Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: body);

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = ChatRemoteDataSourceImp(apiConsumer);
    when(() => apiConsumer.post(any(), body: any(named: 'body'), options: any(named: 'options')))
        .thenAnswer((_) async => jsonResponse(const {}));
    when(() => apiConsumer.patch(any(), body: any(named: 'body')))
        .thenAnswer((_) async => jsonResponse(const {}));
    when(() => apiConsumer.put(any(), body: any(named: 'body')))
        .thenAnswer((_) async => jsonResponse(const {}));
  });

  group('getConversationPage', () {
    test('asks for a full page and omits the cursor on the live page', () async {
      when(() => apiConsumer.get(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
        (_) async => jsonResponse({'conversationId': 'c-1', 'latestSequence': 4, 'controller': 'ready'}),
      );

      final page = await dataSource.getConversationPage('w-1');

      expect(page.data, isA<ConversationSnapshotModel>());
      expect(page.data!.conversationId, 'c-1');
      final captured = verify(
        () => apiConsumer.get(EndPoints.sessionConversation('w-1'),
            queryParameters: captureAny(named: 'queryParameters')),
      ).captured.single as Map<String, dynamic>;
      expect(captured, {'limit': 200});
    });

    test('sends beforeSequence when paging backwards', () async {
      when(() => apiConsumer.get(any(), queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => jsonResponse(const {'latestSequence': 4, 'controller': 'ready'}));

      await dataSource.getConversationPage('w-1', beforeSequence: 12);

      final captured = verify(
        () => apiConsumer.get(any(), queryParameters: captureAny(named: 'queryParameters')),
      ).captured.single as Map<String, dynamic>;
      expect(captured, {'limit': 200, 'beforeSequence': 12});
    });
  });

  group('writes', () {
    test('posts a message with its client id and attachments', () async {
      await dataSource.sendMessage(
        'w-1',
        const SendMessageParams(
          text: 'hello',
          clientMessageId: 'mobile-1',
          attachments: [ChatImageModel(mimeType: 'image/png', data: 'AAA')],
        ),
      );

      final captured = verify(
        () => apiConsumer.post(EndPoints.conversationMessages('w-1'),
            body: captureAny(named: 'body'), options: any(named: 'options')),
      ).captured.single as Map<String, dynamic>;
      expect(captured['text'], 'hello');
      expect(captured['clientMessageId'], 'mobile-1');
      expect(captured['attachments'], [
        {'mimeType': 'image/png', 'data': 'AAA'},
      ]);
      expect(captured.containsKey('resources'), isFalse);
    });

    test('resolves an input request with its action and content', () async {
      await dataSource.resolveInput(
        'w-1',
        const ResolveInputParams(requestId: 'req-1', action: 'accept', content: {'token': 'x'}),
      );

      final captured = verify(
        () => apiConsumer.post(EndPoints.conversationInputResolve('w-1', 'req-1'),
            body: captureAny(named: 'body'), options: any(named: 'options')),
      ).captured.single as Map<String, dynamic>;
      expect(captured, {'action': 'accept', 'content': {'token': 'x'}});
    });

    test('reports how many turns a rollback discarded', () async {
      when(() => apiConsumer.post(any(), body: any(named: 'body'), options: any(named: 'options')))
          .thenAnswer((_) async => jsonResponse(const {'turnsDiscarded': 3}));

      expect(await dataSource.rollbackTurn('w-1', const RollbackTurnParams(turnId: 't-1')), 3);
      verify(() => apiConsumer.post(EndPoints.conversationTurnRollback('w-1', 't-1'),
          body: any(named: 'body'), options: any(named: 'options'))).called(1);
    });

    test('patches a provider config option and returns the refreshed catalog', () async {
      when(() => apiConsumer.patch(any(), body: any(named: 'body'))).thenAnswer(
        (_) async => jsonResponse({
          'options': [
            {
              'id': 'fast',
              'name': 'Fast mode',
              'type': 'boolean',
              'currentBoolean': true,
              'choices': <dynamic>[],
            },
          ],
        }),
      );

      final options = await dataSource.setConfigOption(
        'w-1',
        const SetConfigOptionParams(optionId: 'fast', enabled: true),
      );

      expect(options.data!.single.id, 'fast');
      expect(options.data!.single.currentBoolean, isTrue);
      final captured = verify(
        () => apiConsumer.patch(EndPoints.conversationConfigOption('w-1', 'fast'),
            body: captureAny(named: 'body')),
      ).captured.single as Map<String, dynamic>;
      expect(captured, {'enabled': true});
    });

    test('sends a select config option as a value', () async {
      when(() => apiConsumer.patch(any(), body: any(named: 'body')))
          .thenAnswer((_) async => jsonResponse(const {'options': <dynamic>[]}));

      await dataSource.setConfigOption('w-1', const SetConfigOptionParams(optionId: 'model', value: 'opus'));

      final captured = verify(
        () => apiConsumer.patch(any(), body: captureAny(named: 'body')),
      ).captured.single as Map<String, dynamic>;
      expect(captured, {'value': 'opus'});
    });

    test('gives attachment staging a minute rather than the twelve-second budget', () async {
      when(() => apiConsumer.post(any(), body: any(named: 'body'), options: any(named: 'options')))
          .thenAnswer((_) async => jsonResponse(const {'paths': ['/w/a.png']}));

      final paths = await dataSource.stageAttachments(
        'w-1',
        const StageAttachmentsParams(attachments: [ChatImageModel(mimeType: 'image/png', data: 'AAA')]),
      );

      expect(paths, ['/w/a.png']);
      final options = verify(
        () => apiConsumer.post(EndPoints.sessionAttachments('w-1'),
            body: any(named: 'body'), options: captureAny(named: 'options')),
      ).captured.single as Options;
      expect(options.receiveTimeout, const Duration(seconds: 60));
      expect(options.sendTimeout, const Duration(seconds: 60));
    });
  });

  group('catalogs', () {
    test('reads models, skills and config options, tolerating an empty daemon', () async {
      when(() => apiConsumer.get(EndPoints.conversationModels('w-1'))).thenAnswer(
        (_) async => jsonResponse({
          'models': [
            {'id': 'opus', 'displayName': 'Opus', 'default': true, 'efforts': ['low', 'high']},
          ],
        }),
      );
      when(() => apiConsumer.get(EndPoints.conversationSkills('w-1'))).thenAnswer(
        (_) async => jsonResponse({
          'skills': [
            {'name': 'review', 'displayName': 'Review', 'source': 'plugin'},
          ],
        }),
      );
      when(() => apiConsumer.get(EndPoints.conversationConfigOptions('w-1')))
          .thenAnswer((_) async => jsonResponse(const {}));

      final models = await dataSource.getModels('w-1');
      expect(models.data!.single.id, 'opus');
      expect(models.data!.single.isDefault, isTrue);
      expect(models.data!.single.efforts, ['low', 'high']);

      final skills = await dataSource.getSkills('w-1');
      expect(skills.data!.single.name, 'review');
      expect(skills.data!.single.source, 'plugin');

      expect((await dataSource.getConfigOptions('w-1')).data, isEmpty);
    });

    test('keeps workspace truncation and drops deleted files', () async {
      when(() => apiConsumer.get(EndPoints.sessionWorkspaceFiles('w-1'))).thenAnswer(
        (_) async => jsonResponse({
          'files': [
            {'path': 'src/app.ts', 'status': 'modified'},
            {'path': 'old.ts', 'status': 'deleted'},
          ],
          'truncated': true,
        }),
      );

      final workspace = await dataSource.getWorkspacePaths('w-1');
      expect(workspace.data!.paths, ['src/app.ts']);
      expect(workspace.data!.truncated, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/data/data_source/chat_remote_data_source_test.dart`
Expected: FAIL — the data source does not exist. If `apiConsumer.patch` is also reported as
undefined, that is expected: `ApiConsumer` already declares `put`/`post`/`delete`, and **`patch` is
added in Step 3**.

- [ ] **Step 3: Add `patch` to the API consumer**

The daemon uses `PATCH` for `/conversation/settings` and `/conversation/config-options/{id}`;
`ApiConsumer` has no `patch` yet. In
`packages/mobile/lib/core/api/api_request_helpers/api_consumer.dart`, after `put`:

```dart
  Future<Response> patch<T>(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    T Function(Map<String, dynamic>)? errorFromJsonT,
  });
```

and in `packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart`, after `put`:

```dart
  @override
  Future<Response> patch<T>(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    T Function(Map<String, dynamic>)? errorFromJsonT,
  }) async {
    try {
      return await client.patch(path, queryParameters: queryParameters, data: body);
    } on DioException catch (error) {
      throw handleDioError(error);
    }
  }
```

- [ ] **Step 4: Write the catalog, attachment and workspace models**

`packages/mobile/lib/feature/chat/data/model/chat_catalog_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/logic/composer_suggestions.dart';

class ChatModelModel extends Equatable {
  const ChatModelModel({
    required this.id,
    required this.displayName,
    this.description,
    this.isDefault = false,
    this.efforts = const [],
    this.defaultEffort,
  });

  final String id;
  final String displayName;
  final String? description;
  final bool isDefault;
  final List<String> efforts;
  final String? defaultEffort;

  factory ChatModelModel.fromJson(Map<String, dynamic> json) => ChatModelModel(
        id: json['id'] as String? ?? '',
        displayName: json['displayName'] as String? ?? json['id'] as String? ?? '',
        description: json['description'] as String?,
        isDefault: json['default'] == true,
        efforts: (json['efforts'] as List<dynamic>? ?? const []).whereType<String>().toList(),
        defaultEffort: json['defaultEffort'] as String?,
      );

  @override
  List<Object?> get props => [id, displayName, description, isDefault, efforts, defaultEffort];
}

class ChatConfigChoiceModel extends Equatable {
  const ChatConfigChoiceModel({
    required this.value,
    required this.name,
    this.description,
    this.group,
    this.groupName,
  });

  final String value;
  final String name;
  final String? description;
  final String? group;
  final String? groupName;

  factory ChatConfigChoiceModel.fromJson(Map<String, dynamic> json) => ChatConfigChoiceModel(
        value: json['value'] as String? ?? '',
        name: json['name'] as String? ?? json['value'] as String? ?? '',
        description: json['description'] as String?,
        group: json['group'] as String?,
        groupName: json['groupName'] as String?,
      );

  @override
  List<Object?> get props => [value, name, description, group, groupName];
}

class ChatConfigOptionModel extends Equatable {
  const ChatConfigOptionModel({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.category,
    this.currentValue,
    this.currentBoolean,
    this.choices = const [],
  });

  final String id;
  final String name;
  final String type;
  final String? description;
  final String? category;
  final String? currentValue;
  final bool? currentBoolean;
  final List<ChatConfigChoiceModel> choices;

  factory ChatConfigOptionModel.fromJson(Map<String, dynamic> json) => ChatConfigOptionModel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'select',
        description: json['description'] as String?,
        category: json['category'] as String?,
        currentValue: json['currentValue'] as String?,
        currentBoolean: json['currentBoolean'] as bool?,
        choices: (json['choices'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChatConfigChoiceModel.fromJson)
            .toList(),
      );

  @override
  List<Object?> get props =>
      [id, name, type, description, category, currentValue, currentBoolean, choices];
}

class ChatSkillModel extends Equatable implements SuggestibleSkill {
  const ChatSkillModel({
    required this.name,
    required this.displayName,
    this.description,
    this.inputHint,
    this.source,
  });

  @override
  final String name;
  @override
  final String displayName;
  @override
  final String? description;
  @override
  final String? inputHint;
  @override
  final String? source;

  factory ChatSkillModel.fromJson(Map<String, dynamic> json) => ChatSkillModel(
        name: json['name'] as String? ?? '',
        displayName: json['displayName'] as String? ?? json['name'] as String? ?? '',
        description: json['description'] as String?,
        inputHint: json['inputHint'] as String?,
        source: json['source'] as String?,
      );

  @override
  List<Object?> get props => [name, displayName, description, inputHint, source];
}
```

`packages/mobile/lib/feature/chat/data/model/chat_attachment_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class ChatImageModel extends Equatable {
  const ChatImageModel({required this.mimeType, required this.data});

  final String mimeType;
  final String data;

  Map<String, dynamic> toJson() => {'mimeType': mimeType, 'data': data};

  @override
  List<Object?> get props => [mimeType, data];
}

class ChatResourceModel extends Equatable {
  const ChatResourceModel({required this.uri, required this.name, this.mimeType, this.text});

  final String uri;
  final String name;
  final String? mimeType;
  final String? text;

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'name': name,
        if (mimeType != null) 'mimeType': mimeType,
        if (text != null) 'text': text,
      };

  @override
  List<Object?> get props => [uri, name, mimeType, text];
}
```

`packages/mobile/lib/feature/chat/data/model/workspace_paths_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class WorkspacePathsModel extends Equatable {
  const WorkspacePathsModel({this.paths = const [], this.truncated = false});

  final List<String> paths;
  final bool truncated;

  factory WorkspacePathsModel.fromJson(Map<String, dynamic> json) => WorkspacePathsModel(
        paths: (json['files'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .where((file) => file['status'] != 'deleted' && file['path'] is String)
            .map((file) => file['path'] as String)
            .toList(),
        truncated: json['truncated'] == true,
      );

  @override
  List<Object?> get props => [paths, truncated];
}
```

- [ ] **Step 5: Write the params classes**

`packages/mobile/lib/feature/chat/data/model/params/send_message_params.dart`:

```dart
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';

class SendMessageParams {
  const SendMessageParams({
    required this.text,
    required this.clientMessageId,
    this.attachments,
    this.resources,
  });

  final String text;
  final String clientMessageId;
  final List<ChatImageModel>? attachments;
  final List<ChatResourceModel>? resources;

  Map<String, dynamic> toJson() => {
        'text': text,
        'clientMessageId': clientMessageId,
        if (attachments != null) 'attachments': attachments!.map((image) => image.toJson()).toList(),
        if (resources != null) 'resources': resources!.map((resource) => resource.toJson()).toList(),
      };
}
```

`packages/mobile/lib/feature/chat/data/model/params/steer_conversation_params.dart`:

```dart
class SteerConversationParams {
  const SteerConversationParams({required this.text, required this.clientMessageId});

  final String text;
  final String clientMessageId;

  Map<String, dynamic> toJson() => {'text': text, 'clientMessageId': clientMessageId};
}
```

`packages/mobile/lib/feature/chat/data/model/params/resolve_approval_params.dart`:

```dart
class ResolveApprovalParams {
  const ResolveApprovalParams({required this.requestId, required this.decisionId});

  final String requestId;
  final String decisionId;

  Map<String, dynamic> toJson() => {'decisionId': decisionId};
}
```

`packages/mobile/lib/feature/chat/data/model/params/resolve_input_params.dart`:

```dart
class ResolveInputParams {
  const ResolveInputParams({required this.requestId, required this.action, this.content});

  final String requestId;
  final String action;
  final Map<String, dynamic>? content;

  Map<String, dynamic> toJson() => {'action': action, if (content != null) 'content': content};
}
```

`packages/mobile/lib/feature/chat/data/model/params/rollback_turn_params.dart`:

```dart
class RollbackTurnParams {
  const RollbackTurnParams({required this.turnId});

  final String turnId;
}
```

`packages/mobile/lib/feature/chat/data/model/params/set_conversation_title_params.dart`:

```dart
class SetConversationTitleParams {
  const SetConversationTitleParams({required this.title});

  final String title;

  Map<String, dynamic> toJson() => {'title': title};
}
```

`packages/mobile/lib/feature/chat/data/model/params/set_config_option_params.dart`:

```dart
class SetConfigOptionParams {
  const SetConfigOptionParams({required this.optionId, this.value, this.enabled});

  final String optionId;
  final String? value;
  final bool? enabled;

  Map<String, dynamic> toJson() => enabled != null ? {'enabled': enabled} : {'value': value};
}
```

`packages/mobile/lib/feature/chat/data/model/params/stage_attachments_params.dart`:

```dart
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';

class StageAttachmentsParams {
  const StageAttachmentsParams({required this.attachments});

  final List<ChatImageModel> attachments;

  Map<String, dynamic> toJson() => {'attachments': attachments.map((image) => image.toJson()).toList()};
}
```

`SetConversationSettingsParams` is not a new class: the settings body **is**
`TurnSettingsModel.toJson()`, which Task 11 already defines and which the settings sheet already
holds. Inventing a second identical shape would be the "never shared even where fields overlap"
rule applied past the point where it means anything — there is one settings shape, and the daemon
round-trips it.

- [ ] **Step 6: Write the data source**

`packages/mobile/lib/feature/chat/data/data_source/chat_remote_data_source.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_approval_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_input_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/rollback_turn_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/send_message_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_config_option_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_conversation_title_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/stage_attachments_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/steer_conversation_params.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';

const int kChatPageSize = 200;

const Duration _attachmentTimeout = Duration(seconds: 60);

abstract class ChatRemoteDataSource {
  Future<GlobalResponse<ConversationSnapshotModel>> getConversationPage(
    String sessionId, {
    int? beforeSequence,
  });
  Future<void> sendMessage(String sessionId, SendMessageParams params);
  Future<void> steer(String sessionId, SteerConversationParams params);
  Future<void> interrupt(String sessionId);
  Future<void> compact(String sessionId);
  Future<void> resolveApproval(String sessionId, ResolveApprovalParams params);
  Future<void> resolveInput(String sessionId, ResolveInputParams params);
  Future<int> rollbackTurn(String sessionId, RollbackTurnParams params);
  Future<void> setTitle(String sessionId, SetConversationTitleParams params);
  Future<GlobalResponse<List<ChatModelModel>>> getModels(String sessionId);
  Future<void> setSettings(String sessionId, TurnSettingsModel settings);
  Future<GlobalResponse<List<ChatConfigOptionModel>>> getConfigOptions(String sessionId);
  Future<GlobalResponse<List<ChatConfigOptionModel>>> setConfigOption(
    String sessionId,
    SetConfigOptionParams params,
  );
  Future<GlobalResponse<List<ChatSkillModel>>> getSkills(String sessionId);
  Future<void> reloadMcpServers(String sessionId);
  Future<List<String>> stageAttachments(String sessionId, StageAttachmentsParams params);
  Future<GlobalResponse<WorkspacePathsModel>> getWorkspacePaths(String sessionId);
  Future<void> resumeAgent(String sessionId);
}

class ChatRemoteDataSourceImp implements ChatRemoteDataSource {
  ChatRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<ConversationSnapshotModel>> getConversationPage(
    String sessionId, {
    int? beforeSequence,
  }) async {
    final response = await _apiConsumer.get(
      EndPoints.sessionConversation(sessionId),
      queryParameters: {
        'limit': kChatPageSize,
        if (beforeSequence != null) 'beforeSequence': beforeSequence,
      },
    );
    return GlobalResponse<ConversationSnapshotModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: ConversationSnapshotModel.fromJson,
    );
  }

  @override
  Future<void> sendMessage(String sessionId, SendMessageParams params) async {
    await _apiConsumer.post(EndPoints.conversationMessages(sessionId), body: params.toJson());
  }

  @override
  Future<void> steer(String sessionId, SteerConversationParams params) async {
    await _apiConsumer.post(EndPoints.conversationSteer(sessionId), body: params.toJson());
  }

  @override
  Future<void> interrupt(String sessionId) async {
    await _apiConsumer.post(EndPoints.conversationInterrupt(sessionId));
  }

  @override
  Future<void> compact(String sessionId) async {
    await _apiConsumer.post(EndPoints.conversationCompact(sessionId));
  }

  @override
  Future<void> resolveApproval(String sessionId, ResolveApprovalParams params) async {
    await _apiConsumer.post(
      EndPoints.conversationApprovalResolve(sessionId, params.requestId),
      body: params.toJson(),
    );
  }

  @override
  Future<void> resolveInput(String sessionId, ResolveInputParams params) async {
    await _apiConsumer.post(
      EndPoints.conversationInputResolve(sessionId, params.requestId),
      body: params.toJson(),
    );
  }

  @override
  Future<int> rollbackTurn(String sessionId, RollbackTurnParams params) async {
    final response = await _apiConsumer.post(
      EndPoints.conversationTurnRollback(sessionId, params.turnId),
    );
    final body = response.data;
    return body is Map<String, dynamic> ? (body['turnsDiscarded'] as num?)?.toInt() ?? 0 : 0;
  }

  @override
  Future<void> setTitle(String sessionId, SetConversationTitleParams params) async {
    await _apiConsumer.put(EndPoints.conversationTitle(sessionId), body: params.toJson());
  }

  @override
  Future<GlobalResponse<List<ChatModelModel>>> getModels(String sessionId) async {
    final response = await _apiConsumer.get(EndPoints.conversationModels(sessionId));
    return GlobalResponse<List<ChatModelModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => (json['models'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatModelModel.fromJson)
          .toList(),
    );
  }

  @override
  Future<void> setSettings(String sessionId, TurnSettingsModel settings) async {
    await _apiConsumer.patch(EndPoints.conversationSettings(sessionId), body: settings.toJson());
  }

  @override
  Future<GlobalResponse<List<ChatConfigOptionModel>>> getConfigOptions(String sessionId) async {
    final response = await _apiConsumer.get(EndPoints.conversationConfigOptions(sessionId));
    return _configOptions(response.data as Map<String, dynamic>);
  }

  @override
  Future<GlobalResponse<List<ChatConfigOptionModel>>> setConfigOption(
    String sessionId,
    SetConfigOptionParams params,
  ) async {
    final response = await _apiConsumer.patch(
      EndPoints.conversationConfigOption(sessionId, params.optionId),
      body: params.toJson(),
    );
    return _configOptions(response.data as Map<String, dynamic>);
  }

  @override
  Future<GlobalResponse<List<ChatSkillModel>>> getSkills(String sessionId) async {
    final response = await _apiConsumer.get(EndPoints.conversationSkills(sessionId));
    return GlobalResponse<List<ChatSkillModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => (json['skills'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatSkillModel.fromJson)
          .toList(),
    );
  }

  @override
  Future<void> reloadMcpServers(String sessionId) async {
    await _apiConsumer.post(EndPoints.conversationMcpReload(sessionId));
  }

  @override
  Future<List<String>> stageAttachments(String sessionId, StageAttachmentsParams params) async {
    final response = await _apiConsumer.post(
      EndPoints.sessionAttachments(sessionId),
      body: params.toJson(),
      options: Options(sendTimeout: _attachmentTimeout, receiveTimeout: _attachmentTimeout),
    );
    final body = response.data;
    return body is Map<String, dynamic>
        ? (body['paths'] as List<dynamic>? ?? const []).whereType<String>().toList()
        : const [];
  }

  @override
  Future<GlobalResponse<WorkspacePathsModel>> getWorkspacePaths(String sessionId) async {
    final response = await _apiConsumer.get(EndPoints.sessionWorkspaceFiles(sessionId));
    return GlobalResponse<WorkspacePathsModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: WorkspacePathsModel.fromJson,
    );
  }

  @override
  Future<void> resumeAgent(String sessionId) async {
    await _apiConsumer.post(EndPoints.sessionResumeAgent(sessionId));
  }

  GlobalResponse<List<ChatConfigOptionModel>> _configOptions(Map<String, dynamic> body) =>
      GlobalResponse<List<ChatConfigOptionModel>>.fromJson(
        body,
        withDataKey: false,
        fromJsonT: (json) => (json['options'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChatConfigOptionModel.fromJson)
            .toList(),
      );
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/data/data_source/chat_remote_data_source_test.dart`
Expected: PASS.

- [ ] **Step 8: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 492/492 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the chat REST data source"
```

---

### Task 15: The conversation event stream

**Files:**
- Modify: `packages/mobile/lib/core/api/api_request_helpers/api_consumer.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart`
- Create: `packages/mobile/lib/feature/chat/data/data_source/chat_event_data_source.dart`
- Test: `packages/mobile/test/feature/chat/data/data_source/chat_event_data_source_test.dart`

**Interfaces:**
- Consumes: `ApiConsumer`, `EndPoints.events`, `takeSseFrames`/`parseSseFrame` (Task 2).
- Produces:
  - `ApiConsumer.get(..., {CancelToken? cancelToken})` — one new optional named parameter
  - `abstract class ChatEventDataSource` with
    `Stream<ConversationEventModel> stream({required int after, required CancelToken cancelToken})`
  - `class ChatEventDataSourceImp implements ChatEventDataSource`

This is the one long-lived HTTP request in the app, and it needs three things the ordinary consumer
does not give it:

1. **No receive timeout.** `DioConsumer` sets `receiveTimeout: 12s` globally. An SSE stream is idle
   between events by design, so the global budget would tear it down every twelve quiet seconds.
   `Options(receiveTimeout: Duration.zero)` disables the timer — verified against
   `dio-5.9.0/lib/src/adapters/io_adapter.dart:162`, which arms the timeout only when
   `receiveTimeout > Duration.zero`. `connectTimeout` is left at 12s: failing to *reach* a sleeping
   host must still fail fast, which is the whole point of the spec's rule.
2. **A cancel token.** The cubit aborts the stream when the screen closes. `ApiConsumer.get` has no
   `cancelToken` parameter today; adding one optional named parameter is smaller and more honest
   than reaching around the abstraction into `DioConsumer.client`.
3. **`ResponseType.stream`.** The response body arrives as a `ResponseBody` whose `.stream` yields
   `Uint8List` chunks. Decoding is incremental (`utf8.decoder` in non-fatal mode) because a chunk
   boundary can split a multi-byte character.

The stream yields **every** event for the daemon, not just this session's; filtering by `sessionId`
is the caller's job, exactly as in `streamConversationEvents`'s callback contract.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/data/data_source/chat_event_data_source_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

class _FakeCancelToken extends Fake implements CancelToken {}

void main() {
  late _MockApiConsumer apiConsumer;
  late ChatEventDataSource dataSource;
  late StreamController<Uint8List> chunks;

  setUpAll(() => registerFallbackValue(_FakeCancelToken()));

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = ChatEventDataSourceImp(apiConsumer);
    chunks = StreamController<Uint8List>();

    when(
      () => apiConsumer.get(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: EndPoints.events),
        data: ResponseBody(chunks.stream, 200),
      ),
    );
  });

  tearDown(() => chunks.close());

  Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

  test('asks the daemon to replay from the cursor with no receive timeout', () async {
    final events = dataSource.stream(after: 7, cancelToken: CancelToken()).listen((_) {});
    await Future<void>.delayed(Duration.zero);

    final call = verify(
      () => apiConsumer.get(
        EndPoints.events,
        queryParameters: captureAny(named: 'queryParameters'),
        options: captureAny(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).captured;

    expect(call[0], {'after': 7});
    final options = call[1] as Options;
    expect(options.responseType, ResponseType.stream);
    expect(options.receiveTimeout, Duration.zero);
    expect(options.headers!['Accept'], 'text/event-stream');
    await events.cancel();
  });

  test('never asks for a negative cursor', () async {
    final events = dataSource.stream(after: -4, cancelToken: CancelToken()).listen((_) {});
    await Future<void>.delayed(Duration.zero);

    final captured = verify(
      () => apiConsumer.get(
        any(),
        queryParameters: captureAny(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).captured.single as Map<String, dynamic>;
    expect(captured, {'after': 0});
    await events.cancel();
  });

  test('emits parsed events and survives a chunk split mid-frame', () async {
    final received = <int>[];
    final events = dataSource
        .stream(after: 0, cancelToken: CancelToken())
        .listen((event) => received.add(event.seq));
    await Future<void>.delayed(Duration.zero);

    chunks.add(bytes('id: 1\ndata: {"seq":1,"sessionId":"w-1"}\n\nid: 2\ndata: {"se'));
    await Future<void>.delayed(Duration.zero);
    expect(received, [1]);

    chunks.add(bytes('q":2,"sessionId":"w-1"}\n\n'));
    await Future<void>.delayed(Duration.zero);
    expect(received, [1, 2]);

    chunks.add(bytes('id: 3\ndata: broken\n\n'));
    await Future<void>.delayed(Duration.zero);
    expect(received, [1, 2]);

    await events.cancel();
  });

  test('closes when the daemon ends the stream', () async {
    final done = Completer<void>();
    dataSource.stream(after: 0, cancelToken: CancelToken()).listen((_) {}, onDone: done.complete);
    await Future<void>.delayed(Duration.zero);

    await chunks.close();
    await done.future.timeout(const Duration(seconds: 1));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/data/data_source/chat_event_data_source_test.dart`
Expected: FAIL — `cancelToken` is not a parameter of `ApiConsumer.get`, and the data source does
not exist.

- [ ] **Step 3: Give `ApiConsumer.get` a cancel token**

In `packages/mobile/lib/core/api/api_request_helpers/api_consumer.dart`, add to `get`'s signature:

```dart
    CancelToken? cancelToken,
```

and in `packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart`, add the same parameter
to `get` and thread it through:

```dart
      return await client.get(
        path,
        queryParameters: queryParameters,
        data: body,
        options: options,
        cancelToken: cancelToken,
      );
```

- [ ] **Step 4: Write the event data source**

`packages/mobile/lib/feature/chat/data/data_source/chat_event_data_source.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

abstract class ChatEventDataSource {
  Stream<ConversationEventModel> stream({required int after, required CancelToken cancelToken});
}

class ChatEventDataSourceImp implements ChatEventDataSource {
  ChatEventDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Stream<ConversationEventModel> stream({
    required int after,
    required CancelToken cancelToken,
  }) async* {
    final response = await _apiConsumer.get(
      EndPoints.events,
      queryParameters: {'after': max(0, after)},
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: Duration.zero,
        headers: const {'Accept': 'text/event-stream'},
      ),
      cancelToken: cancelToken,
    );

    final body = response.data as ResponseBody;
    final decoder = const Utf8Decoder(allowMalformed: true);
    var buffer = '';

    await for (final chunk in body.stream) {
      buffer += decoder.convert(Uint8List.fromList(chunk));
      final split = takeSseFrames(buffer);
      buffer = split.remainder;
      for (final frame in split.frames) {
        final event = parseSseFrame(frame);
        if (event != null) yield event;
      }
    }
  }
}
```

A note for the implementer on the decoder: `Utf8Decoder.convert` on a chunk that ends mid-character
would normally throw or emit a replacement character. `allowMalformed: true` keeps it from
throwing, and the only realistic split is inside a UTF-8 sequence in message text, which the very
next chunk repairs at the frame level because a frame is only parsed once its boundary arrives. If
this ever shows up as a mangled character in a streamed message, the fix is
`utf8.decoder.bind(body.stream)` as a stream transformer rather than per-chunk `convert`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/data/data_source/chat_event_data_source_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 496/496 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): stream conversation events over SSE"
```

---

### Task 16: The chat repository

**Files:**
- Create: `packages/mobile/lib/feature/chat/data/repository/chat_repository.dart`
- Test: `packages/mobile/test/feature/chat/data/repository/chat_repository_test.dart`

**Interfaces:**
- Consumes: `ChatRemoteDataSource` (Task 14), `ChatEventDataSource` (Task 15), `NetworkStatus`.
- Produces `abstract class ChatRepository` / `ChatRepositoryImp` with one method per data-source
  method, each returning `FutureResult<...>` gated on `NetworkStatus`, plus
  `Stream<ConversationEventModel> events({required int after, required CancelToken cancelToken})`
  which is **not** gated.

Every request-shaped method follows M2's exact repository shape: check `isConnected`, `try` the
data source, catch `Failure`, and short-circuit offline to `ServerFailure.noNetwork()`.

`events` is deliberately outside that pattern. It is a `Stream`, not a `Future<Result>`, so there
is nothing to short-circuit into; and gating it on a `/healthz` round-trip before every reconnect
attempt would double the traffic of the reconnect loop that already exists to handle exactly this
failure. Its failures surface as stream errors, which Task 19's loop already treats as "reconnect".

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/data/repository/chat_repository_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_remote_data_source.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/rollback_turn_params.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

class _MockRemote extends Mock implements ChatRemoteDataSource {}

class _MockEvents extends Mock implements ChatEventDataSource {}

class _MockNetwork extends Mock implements NetworkStatus {}

class _FakeCancelToken extends Fake implements CancelToken {}

class _FakeRollbackParams extends Fake implements RollbackTurnParams {}

void main() {
  late _MockRemote remote;
  late _MockEvents events;
  late _MockNetwork network;
  late ChatRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeCancelToken());
    registerFallbackValue(_FakeRollbackParams());
  });

  setUp(() {
    remote = _MockRemote();
    events = _MockEvents();
    network = _MockNetwork();
    repository = ChatRepositoryImp(remote, events, network);
    when(() => network.isConnected).thenAnswer((_) async => true);
  });

  test('returns the conversation page when the daemon answers', () async {
    when(() => remote.getConversationPage('w-1', beforeSequence: null)).thenAnswer(
      (_) async => const GlobalResponse(data: ConversationSnapshotModel(conversationId: 'c-1')),
    );

    final result = await repository.getConversationPage('w-1');
    expect(result.isSuccess, isTrue);
    result.when(
      onSuccess: (response) => expect(response.data!.conversationId, 'c-1'),
      onFailure: (_) => fail('expected success'),
    );
  });

  test('surfaces the daemon failure rather than throwing', () async {
    when(() => remote.getConversationPage('w-1', beforeSequence: null))
        .thenThrow(ServerFailure(error: 'nope', message: 'Conversation unavailable', apiStatus: 'CHAT_RESUME_FAILED'));

    final result = await repository.getConversationPage('w-1');
    expect(result.isFailure, isTrue);
    result.when(
      onSuccess: (_) => fail('expected failure'),
      onFailure: (failure) => expect(failure.apiStatus, 'CHAT_RESUME_FAILED'),
    );
  });

  test('short-circuits every request while offline', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);

    expect((await repository.getConversationPage('w-1')).isFailure, isTrue);
    expect((await repository.interrupt('w-1')).isFailure, isTrue);
    expect((await repository.rollbackTurn('w-1', const RollbackTurnParams(turnId: 't-1'))).isFailure, isTrue);
    verifyNever(() => remote.getConversationPage(any(), beforeSequence: any(named: 'beforeSequence')));
    verifyNever(() => remote.interrupt(any()));
  });

  test('reports a void action as a success flag', () async {
    when(() => remote.interrupt('w-1')).thenAnswer((_) async {});
    expect((await repository.interrupt('w-1')).getOrDefault(false), isTrue);
  });

  test('passes the event stream through without a network gate', () async {
    when(() => events.stream(after: 3, cancelToken: any(named: 'cancelToken')))
        .thenAnswer((_) => Stream.value(const ConversationEventModel(seq: 4)));
    when(() => network.isConnected).thenAnswer((_) async => false);

    final received = await repository.events(after: 3, cancelToken: CancelToken()).toList();
    expect(received.single.seq, 4);
    verifyNever(() => network.isConnected);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/data/repository/chat_repository_test.dart`
Expected: FAIL — the repository does not exist.

- [ ] **Step 3: Write the repository**

`packages/mobile/lib/feature/chat/data/repository/chat_repository.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_remote_data_source.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_approval_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_input_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/rollback_turn_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/send_message_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_config_option_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_conversation_title_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/stage_attachments_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/steer_conversation_params.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

abstract class ChatRepository {
  FutureResult<GlobalResponse<ConversationSnapshotModel>> getConversationPage(
    String sessionId, {
    int? beforeSequence,
  });
  FutureResult<bool> sendMessage(String sessionId, SendMessageParams params);
  FutureResult<bool> steer(String sessionId, SteerConversationParams params);
  FutureResult<bool> interrupt(String sessionId);
  FutureResult<bool> compact(String sessionId);
  FutureResult<bool> resolveApproval(String sessionId, ResolveApprovalParams params);
  FutureResult<bool> resolveInput(String sessionId, ResolveInputParams params);
  FutureResult<int> rollbackTurn(String sessionId, RollbackTurnParams params);
  FutureResult<bool> setTitle(String sessionId, SetConversationTitleParams params);
  FutureResult<GlobalResponse<List<ChatModelModel>>> getModels(String sessionId);
  FutureResult<bool> setSettings(String sessionId, TurnSettingsModel settings);
  FutureResult<GlobalResponse<List<ChatConfigOptionModel>>> getConfigOptions(String sessionId);
  FutureResult<GlobalResponse<List<ChatConfigOptionModel>>> setConfigOption(
    String sessionId,
    SetConfigOptionParams params,
  );
  FutureResult<GlobalResponse<List<ChatSkillModel>>> getSkills(String sessionId);
  FutureResult<bool> reloadMcpServers(String sessionId);
  FutureResult<List<String>> stageAttachments(String sessionId, StageAttachmentsParams params);
  FutureResult<GlobalResponse<WorkspacePathsModel>> getWorkspacePaths(String sessionId);
  FutureResult<bool> resumeAgent(String sessionId);
  Stream<ConversationEventModel> events({required int after, required CancelToken cancelToken});
}

class ChatRepositoryImp implements ChatRepository {
  ChatRepositoryImp(this._remoteDataSource, this._eventDataSource, this._network);

  final ChatRemoteDataSource _remoteDataSource;
  final ChatEventDataSource _eventDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<ConversationSnapshotModel>> getConversationPage(
    String sessionId, {
    int? beforeSequence,
  }) =>
      _guard(() => _remoteDataSource.getConversationPage(sessionId, beforeSequence: beforeSequence));

  @override
  FutureResult<bool> sendMessage(String sessionId, SendMessageParams params) =>
      _run(() => _remoteDataSource.sendMessage(sessionId, params));

  @override
  FutureResult<bool> steer(String sessionId, SteerConversationParams params) =>
      _run(() => _remoteDataSource.steer(sessionId, params));

  @override
  FutureResult<bool> interrupt(String sessionId) => _run(() => _remoteDataSource.interrupt(sessionId));

  @override
  FutureResult<bool> compact(String sessionId) => _run(() => _remoteDataSource.compact(sessionId));

  @override
  FutureResult<bool> resolveApproval(String sessionId, ResolveApprovalParams params) =>
      _run(() => _remoteDataSource.resolveApproval(sessionId, params));

  @override
  FutureResult<bool> resolveInput(String sessionId, ResolveInputParams params) =>
      _run(() => _remoteDataSource.resolveInput(sessionId, params));

  @override
  FutureResult<int> rollbackTurn(String sessionId, RollbackTurnParams params) =>
      _guard(() => _remoteDataSource.rollbackTurn(sessionId, params));

  @override
  FutureResult<bool> setTitle(String sessionId, SetConversationTitleParams params) =>
      _run(() => _remoteDataSource.setTitle(sessionId, params));

  @override
  FutureResult<GlobalResponse<List<ChatModelModel>>> getModels(String sessionId) =>
      _guard(() => _remoteDataSource.getModels(sessionId));

  @override
  FutureResult<bool> setSettings(String sessionId, TurnSettingsModel settings) =>
      _run(() => _remoteDataSource.setSettings(sessionId, settings));

  @override
  FutureResult<GlobalResponse<List<ChatConfigOptionModel>>> getConfigOptions(String sessionId) =>
      _guard(() => _remoteDataSource.getConfigOptions(sessionId));

  @override
  FutureResult<GlobalResponse<List<ChatConfigOptionModel>>> setConfigOption(
    String sessionId,
    SetConfigOptionParams params,
  ) =>
      _guard(() => _remoteDataSource.setConfigOption(sessionId, params));

  @override
  FutureResult<GlobalResponse<List<ChatSkillModel>>> getSkills(String sessionId) =>
      _guard(() => _remoteDataSource.getSkills(sessionId));

  @override
  FutureResult<bool> reloadMcpServers(String sessionId) =>
      _run(() => _remoteDataSource.reloadMcpServers(sessionId));

  @override
  FutureResult<List<String>> stageAttachments(String sessionId, StageAttachmentsParams params) =>
      _guard(() => _remoteDataSource.stageAttachments(sessionId, params));

  @override
  FutureResult<GlobalResponse<WorkspacePathsModel>> getWorkspacePaths(String sessionId) =>
      _guard(() => _remoteDataSource.getWorkspacePaths(sessionId));

  @override
  FutureResult<bool> resumeAgent(String sessionId) => _run(() => _remoteDataSource.resumeAgent(sessionId));

  @override
  Stream<ConversationEventModel> events({required int after, required CancelToken cancelToken}) =>
      _eventDataSource.stream(after: after, cancelToken: cancelToken);

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

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/data/repository/chat_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 501/501 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the chat repository"
```

---

### Task 17: `ChatCubit` — pages, pagination, catalogs (`useConversation.ts` part 1)

**Files:**
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/logic/chat_cubit.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/logic/chat_state.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/logic/chat_cubit_test.dart`

**Interfaces:**
- Consumes: `ChatRepository` (Task 16), `mergeConversationPages`/`discardHistoricalPages` (Task 12),
  `conversationActionError`/`kPermanentConversationCodes` (Task 3).
- Produces:
  - `sealed class ChatState extends Equatable` with `ChatInitialState` and `ChatReadyState(revision)`
  - `class ChatUnavailable extends Equatable` — `code (String?)`, `message (String)`
  - `class ChatCubit extends Cubit<ChatState>` with, in this task:
    fields `snapshot`, `loading`, `refreshing`, `loadingOlder`, `error`, `unavailable`, `models`,
    `configOptions`, `skills`, `workspace`; methods `refresh()`, `loadOlder()`, `close()`
  - `ChatCubit` constructor:
    `ChatCubit(ChatRepository repository, String sessionId, {Duration configPoll, Duration skillPoll, Duration workspacePoll})`
  - `sl.registerFactoryParam<ChatCubit, String, void>` registration

**One cubit per open chat screen**, registered as a `registerFactoryParam` keyed on the session id —
the same shape `PairingScanCubit` uses for its one parameter. It is emphatically **not** a lazy
singleton: `SessionsCubit` is a singleton because there is one board, but there is one conversation
per session and its poll loops must die with its screen.

The three poll intervals are constructor parameters with the RN defaults (`5s` config options,
`60s` skills, `30s` workspace paths). Hard-coding them the way `SessionsCubit` hard-codes its 8s
would make every test of this behavior take a real minute. The defaults are the shipped values; the
parameters exist only so tests can compress them.

Provider catalogs are live session state and **fail independently**: a missing optional facility
must never hide an otherwise healthy conversation. `models` is fetched only when the provider does
*not* advertise `config_options`, and `configOptions` only when it does — that is RN's exact
either/or, because a provider that owns its own controls has no Operator-side model list.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/presentation/chat_screen/logic/chat_cubit_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';

class _MockChatRepository extends Mock implements ChatRepository {}

ConversationSnapshotModel page({
  String conversationId = 'c-1',
  int oldestSequence = 1,
  bool hasMoreBefore = false,
  List<ConversationItemModel> items = const [],
  List<String> capabilities = const [],
}) =>
    ConversationSnapshotModel(
      conversationId: conversationId,
      sessionId: 'w-1',
      harness: 'codex',
      controllerState: 'ready',
      latestSequence: 4,
      oldestSequence: oldestSequence,
      hasMoreBefore: hasMoreBefore,
      items: items,
      capabilities: capabilities,
    );

ConversationMessageModel message(String id, int sequence) =>
    ConversationMessageModel(id: id, sequence: sequence, revision: 1, text: id);

void main() {
  late _MockChatRepository repository;

  void stubIdleCatalogs() {
    when(() => repository.getModels(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: <ChatModelModel>[])));
    when(() => repository.getConfigOptions(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: <ChatConfigOptionModel>[])));
    when(() => repository.getSkills(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: <ChatSkillModel>[])));
    when(() => repository.getWorkspacePaths(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: WorkspacePathsModel())));
  }

  ChatCubit build() => ChatCubit(
        repository,
        'w-1',
        configPoll: const Duration(milliseconds: 20),
        skillPoll: const Duration(milliseconds: 40),
        workspacePoll: const Duration(milliseconds: 60),
      );

  setUp(() {
    repository = _MockChatRepository();
    stubIdleCatalogs();
    when(() => repository.events(after: any(named: 'after'), cancelToken: any(named: 'cancelToken')))
        .thenAnswer((_) => const Stream<ConversationEventModel>.empty());
  });

  blocTest<ChatCubit, ChatState>(
    'loads the live page and clears the loading flag',
    build: () {
      when(() => repository.getConversationPage('w-1', beforeSequence: null))
          .thenAnswer((_) async => Result.success(GlobalResponse(data: page(items: [message('m1', 1)]))));
      return build();
    },
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 10)),
    verify: (cubit) {
      expect(cubit.loading, isFalse);
      expect(cubit.snapshot!.items.single.id, 'm1');
      expect(cubit.error, isNull);
      expect(cubit.unavailable, isNull);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'treats a permanent code as unavailable and an ordinary one as retryable',
    build: () {
      when(() => repository.getConversationPage('w-1', beforeSequence: null)).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(error: 'x', message: 'Operator could not resume this agent.', apiStatus: 'CHAT_RESUME_FAILED'),
        ),
      );
      return build();
    },
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 10)),
    verify: (cubit) {
      expect(cubit.unavailable!.code, 'CHAT_RESUME_FAILED');
      expect(cubit.unavailable!.message, contains('could not resume'));
      expect(cubit.error, isNull);
      expect(cubit.loading, isFalse);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'keeps a transient failure retryable',
    build: () {
      when(() => repository.getConversationPage('w-1', beforeSequence: null)).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'Could not reach your Operator server')),
      );
      return build();
    },
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 10)),
    verify: (cubit) {
      expect(cubit.unavailable, isNull);
      expect(cubit.error, 'Could not reach your Operator server');
    },
  );

  blocTest<ChatCubit, ChatState>(
    'appends an older page behind the live one and merges them in order',
    build: () {
      when(() => repository.getConversationPage('w-1', beforeSequence: null)).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: page(oldestSequence: 3, hasMoreBefore: true, items: [message('m3', 3)])),
        ),
      );
      when(() => repository.getConversationPage('w-1', beforeSequence: 3)).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: page(items: [message('m1', 1)]))),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.loadOlder();
    },
    verify: (cubit) {
      expect(cubit.snapshot!.items.map((item) => item.id), ['m1', 'm3']);
      expect(cubit.snapshot!.hasMoreBefore, isFalse);
      expect(cubit.loadingOlder, isFalse);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'does not page backwards when there is no more history',
    build: () {
      when(() => repository.getConversationPage('w-1', beforeSequence: null))
          .thenAnswer((_) async => Result.success(GlobalResponse(data: page())));
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.loadOlder();
    },
    verify: (_) => verifyNever(() => repository.getConversationPage('w-1', beforeSequence: any(named: 'beforeSequence'))),
  );

  blocTest<ChatCubit, ChatState>(
    'drops every cached page when the conversation identity changes',
    build: () {
      var call = 0;
      when(() => repository.getConversationPage('w-1', beforeSequence: null)).thenAnswer((_) async {
        call += 1;
        return Result.success(
          GlobalResponse(
            data: call == 1
                ? page(oldestSequence: 3, hasMoreBefore: true, items: [message('m3', 3)])
                : page(conversationId: 'c-2', items: [message('n1', 1)]),
          ),
        );
      });
      when(() => repository.getConversationPage('w-1', beforeSequence: 3)).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: page(items: [message('m1', 1)]))),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.loadOlder();
      await cubit.refresh();
    },
    verify: (cubit) => expect(cubit.snapshot!.items.map((item) => item.id), ['n1']),
  );

  blocTest<ChatCubit, ChatState>(
    'reads the model list only when the provider owns no config options',
    build: () {
      when(() => repository.getConversationPage('w-1', beforeSequence: null))
          .thenAnswer((_) async => Result.success(GlobalResponse(data: page())));
      when(() => repository.getModels('w-1')).thenAnswer(
        (_) async => const Result.success(
          GlobalResponse(data: [ChatModelModel(id: 'opus', displayName: 'Opus')]),
        ),
      );
      return build();
    },
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 10)),
    verify: (cubit) {
      expect(cubit.models.single.id, 'opus');
      verifyNever(() => repository.getConfigOptions(any()));
    },
  );

  blocTest<ChatCubit, ChatState>(
    'reads provider config options instead when the provider advertises them',
    build: () {
      when(() => repository.getConversationPage('w-1', beforeSequence: null)).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: page(capabilities: const ['config_options']))),
      );
      when(() => repository.getConfigOptions('w-1')).thenAnswer(
        (_) async => const Result.success(
          GlobalResponse(data: [ChatConfigOptionModel(id: 'fast', name: 'Fast', type: 'boolean')]),
        ),
      );
      return build();
    },
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 10)),
    verify: (cubit) {
      expect(cubit.configOptions.single.id, 'fast');
      verifyNever(() => repository.getModels(any()));
    },
  );

  blocTest<ChatCubit, ChatState>(
    'keeps the conversation when an optional catalog fails',
    build: () {
      when(() => repository.getConversationPage('w-1', beforeSequence: null))
          .thenAnswer((_) async => Result.success(GlobalResponse(data: page(items: [message('m1', 1)]))));
      when(() => repository.getSkills('w-1'))
          .thenAnswer((_) async => Result.failure(ServerFailure(error: 'x', message: 'no skills route')));
      return build();
    },
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 10)),
    verify: (cubit) {
      expect(cubit.snapshot, isNotNull);
      expect(cubit.skills, isEmpty);
      expect(cubit.error, isNull);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'keeps polling the catalogs it owns',
    build: () {
      when(() => repository.getConversationPage('w-1', beforeSequence: null))
          .thenAnswer((_) async => Result.success(GlobalResponse(data: page())));
      return build();
    },
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 150)),
    verify: (_) {
      verify(() => repository.getSkills('w-1')).called(greaterThan(1));
      verify(() => repository.getWorkspacePaths('w-1')).called(greaterThan(1));
    },
  );

  blocTest<ChatCubit, ChatState>(
    'never polls anything once the conversation is permanently unavailable',
    build: () {
      when(() => repository.getConversationPage('w-1', beforeSequence: null)).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(error: 'x', message: 'gone', apiStatus: 'SESSION_NOT_FOUND'),
        ),
      );
      return build();
    },
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 120)),
    verify: (_) {
      verifyNever(() => repository.getSkills(any()));
      verifyNever(() => repository.getWorkspacePaths(any()));
    },
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/logic/chat_cubit_test.dart`
Expected: FAIL — `ChatCubit` does not exist.

- [ ] **Step 3: Write the state**

`packages/mobile/lib/feature/chat/presentation/chat_screen/logic/chat_state.dart`:

```dart
part of 'chat_cubit.dart';

sealed class ChatState extends Equatable {
  const ChatState();

  @override
  List<Object?> get props => [];
}

final class ChatInitialState extends ChatState {
  const ChatInitialState();
}

final class ChatReadyState extends ChatState {
  const ChatReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
```

- [ ] **Step 4: Write the cubit**

`packages/mobile/lib/feature/chat/presentation/chat_screen/logic/chat_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_errors.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_pages.dart';

part 'chat_state.dart';

class ChatUnavailable extends Equatable {
  const ChatUnavailable({required this.message, this.code});

  final String? code;
  final String message;

  @override
  List<Object?> get props => [code, message];
}

class ChatCubit extends Cubit<ChatState> {
  ChatCubit(
    this._repository,
    this.sessionId, {
    Duration configPoll = const Duration(seconds: 5),
    Duration skillPoll = const Duration(seconds: 60),
    Duration workspacePoll = const Duration(seconds: 30),
  })  : _configPoll = configPoll,
        _skillPoll = skillPoll,
        _workspacePoll = workspacePoll,
        super(const ChatInitialState()) {
    scheduleMicrotask(() => unawaited(refresh()));
  }

  final ChatRepository _repository;
  final String sessionId;
  final Duration _configPoll;
  final Duration _skillPoll;
  final Duration _workspacePoll;

  final List<ConversationSnapshotModel> _pages = [];

  ConversationSnapshotModel? snapshot;
  bool loading = true;
  bool refreshing = false;
  bool loadingOlder = false;
  String? error;
  ChatUnavailable? unavailable;
  List<ChatModelModel> models = [];
  List<ChatConfigOptionModel> configOptions = [];
  List<ChatSkillModel> skills = [];
  WorkspacePathsModel workspace = const WorkspacePathsModel();

  Timer? _configTimer;
  Timer? _skillTimer;
  Timer? _workspaceTimer;
  bool _catalogsStarted = false;
  int _revision = 0;

  bool get usesProviderConfig => snapshot?.can('config_options') ?? false;

  Future<void> refresh() async {
    refreshing = true;
    _emit();

    final result = await _repository.getConversationPage(sessionId);
    if (isClosed) return;

    result.when(
      onSuccess: (response) {
        final live = response.data;
        if (live != null) _replaceLivePage(live);
        unavailable = null;
        error = null;
      },
      onFailure: (failure) {
        final code = conversationErrorCode(failure);
        final message = conversationActionError(failure);
        if (code != null && kPermanentConversationCodes.contains(code)) {
          unavailable = ChatUnavailable(code: code, message: message);
        } else {
          error = message;
        }
      },
    );

    loading = false;
    refreshing = false;
    _emit();
    _startCatalogs();
  }

  Future<void> loadOlder() async {
    final current = snapshot;
    if (current == null || !current.hasMoreBefore || loadingOlder) return;

    loadingOlder = true;
    _emit();

    final result = await _repository.getConversationPage(
      sessionId,
      beforeSequence: current.oldestSequence,
    );
    if (isClosed) return;

    result.when(
      onSuccess: (response) {
        final older = response.data;
        if (older != null) {
          _pages.add(older);
          _mergePages();
        }
      },
      onFailure: (failure) => error = conversationActionError(failure),
    );

    loadingOlder = false;
    _emit();
  }

  void _replaceLivePage(ConversationSnapshotModel live) {
    final previous = _pages.isEmpty ? null : _pages.first;
    if (previous?.conversationId != null && previous!.conversationId != live.conversationId) {
      _pages
        ..clear()
        ..add(live);
    } else if (_pages.isEmpty) {
      _pages.add(live);
    } else {
      _pages[0] = live;
    }
    _mergePages();
  }

  void _mergePages() => snapshot = mergeConversationPages(_pages);

  void _startCatalogs() {
    if (_catalogsStarted || unavailable != null || snapshot == null) return;
    _catalogsStarted = true;

    unawaited(_loadCatalogs());
    if (usesProviderConfig) {
      _configTimer = Timer.periodic(_configPoll, (_) => unawaited(_loadConfigOptions()));
    }
    _skillTimer = Timer.periodic(_skillPoll, (_) => unawaited(_loadSkills()));
    _workspaceTimer = Timer.periodic(_workspacePoll, (_) => unawaited(_loadWorkspace()));
  }

  Future<void> _loadCatalogs() async {
    await Future.wait([
      if (usesProviderConfig) _loadConfigOptions() else _loadModels(),
      _loadSkills(),
      _loadWorkspace(),
    ]);
  }

  Future<void> _loadModels() async {
    final result = await _repository.getModels(sessionId);
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        models = response.data ?? const [];
        _emit();
      },
      onFailure: (_) {},
    );
  }

  Future<void> _loadConfigOptions() async {
    final result = await _repository.getConfigOptions(sessionId);
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        configOptions = response.data ?? const [];
        _emit();
      },
      onFailure: (_) {},
    );
  }

  Future<void> _loadSkills() async {
    final result = await _repository.getSkills(sessionId);
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        skills = response.data ?? const [];
        _emit();
      },
      onFailure: (_) {},
    );
  }

  Future<void> _loadWorkspace() async {
    final result = await _repository.getWorkspacePaths(sessionId);
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        workspace = response.data ?? const WorkspacePathsModel();
        _emit();
      },
      onFailure: (_) {},
    );
  }

  void _emit() {
    if (!isClosed) emit(ChatReadyState(++_revision));
  }

  @override
  Future<void> close() {
    _configTimer?.cancel();
    _skillTimer?.cancel();
    _workspaceTimer?.cancel();
    return super.close();
  }
}
```

- [ ] **Step 5: Register the feature**

In `packages/mobile/lib/core/utils/service_locator.dart`, add `_chatFeatureSetup();` to `init()`
after `_settingsFeatureSetup();`, and the method itself:

```dart
  static void _chatFeatureSetup() {
    sl.registerFactoryParam<ChatCubit, String, void>(
      (sessionId, _) => ChatCubit(sl<ChatRepository>(), sessionId!),
    );

    sl.registerLazySingleton<ChatRepository>(
      () => ChatRepositoryImp(sl<ChatRemoteDataSource>(), sl<ChatEventDataSource>(), sl<NetworkStatus>()),
    );
    sl.registerLazySingleton<ChatRemoteDataSource>(() => ChatRemoteDataSourceImp(sl<ApiConsumer>()));
    sl.registerLazySingleton<ChatEventDataSource>(() => ChatEventDataSourceImp(sl<ApiConsumer>()));
  }
```

with the matching imports.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/logic/chat_cubit_test.dart`
Expected: PASS.

- [ ] **Step 7: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 512/512 green. `service_locator_test.dart` exercises every
registration, so a missing import or a wrong dependency order fails there rather than at runtime.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add ChatCubit with paging and provider catalogs"
```

---

### Task 18: `ChatCubit` — actions and pending sends (`useConversation.ts` part 2)

**Files:**
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/logic/chat_cubit.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/logic/chat_cubit_actions_test.dart`

**Interfaces:**
- Consumes: everything from Task 17, plus the params classes (Task 14).
- Produces, on `ChatCubit`:
  - `enum ConversationAction { steer, interrupt, approval, input, compact, rollback, settings, config, mcp, rename }`
  - `class PendingSend extends Equatable` — `id`, `text`, `failed (bool)`, `error (String?)`,
    `attachments`, `resources`
  - fields `pendingSends (List<PendingSend>)`, `pendingActions (Set<ConversationAction>)`,
    `actionError (String?)`, `actionErrors (Map<ConversationAction, String>)`,
    `actionCodes (Map<ConversationAction, String>)`
  - methods `send(String text, {List<ChatImageModel>? attachments, List<ChatResourceModel>? resources})`,
    `retrySend(String id)`, `discardSend(String id)`, `steer(String text)`, `interrupt()`,
    `resolveApproval(String requestId, String decisionId)`,
    `resolveInput(String requestId, String action, [Map<String, dynamic>? content])`, `compact()`,
    `rollback(String turnId)`, `chooseSettings(TurnSettingsModel settings)`,
    `setConfigOption(SetConfigOptionParams params)`, `reloadMcp()`, `rename(String title)`,
    `resumeAgent()`

Every action runs through one `_runAction` helper that marks the action pending, clears its
previous error, refreshes the conversation on success, and records both the human message and the
**machine code** on failure. Keeping the code is what lets the screen withdraw an unsupported
control after the daemon refuses it once (`conversationActionUnsupported`) instead of offering a
button that will always fail.

`rollback` additionally discards historical pages before its refresh: a rollback rewrites the
projection by removing rows, and a live first page cannot carry tombstones for rows cached in older
pages.

Attachment staging happens **before** delivery: images are uploaded to the worktree, their returned
paths are appended to the message text as a reference block, and the inline image payload is
dropped unless the provider advertises the `images` capability. A provider that cannot read images
still gets the paths, which it can open itself.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/presentation/chat_screen/logic/chat_cubit_actions_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_approval_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_input_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/rollback_turn_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/send_message_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_config_option_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_conversation_title_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/stage_attachments_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/steer_conversation_params.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';

class _MockChatRepository extends Mock implements ChatRepository {}

class _FakeSendMessageParams extends Fake implements SendMessageParams {}

class _FakeSteerParams extends Fake implements SteerConversationParams {}

class _FakeApprovalParams extends Fake implements ResolveApprovalParams {}

class _FakeInputParams extends Fake implements ResolveInputParams {}

class _FakeRollbackParams extends Fake implements RollbackTurnParams {}

class _FakeTitleParams extends Fake implements SetConversationTitleParams {}

class _FakeConfigParams extends Fake implements SetConfigOptionParams {}

class _FakeStageParams extends Fake implements StageAttachmentsParams {}

class _FakeSettings extends Fake implements TurnSettingsModel {}

void main() {
  late _MockChatRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeSendMessageParams());
    registerFallbackValue(_FakeSteerParams());
    registerFallbackValue(_FakeApprovalParams());
    registerFallbackValue(_FakeInputParams());
    registerFallbackValue(_FakeRollbackParams());
    registerFallbackValue(_FakeTitleParams());
    registerFallbackValue(_FakeConfigParams());
    registerFallbackValue(_FakeStageParams());
    registerFallbackValue(_FakeSettings());
  });

  ConversationSnapshotModel page({List<String> capabilities = const []}) => ConversationSnapshotModel(
        conversationId: 'c-1',
        sessionId: 'w-1',
        harness: 'codex',
        controllerState: 'ready',
        latestSequence: 1,
        capabilities: capabilities,
      );

  ChatCubit build({List<String> capabilities = const []}) {
    when(() => repository.getConversationPage('w-1', beforeSequence: null))
        .thenAnswer((_) async => Result.success(GlobalResponse(data: page(capabilities: capabilities))));
    return ChatCubit(repository, 'w-1');
  }

  setUp(() {
    repository = _MockChatRepository();
    when(() => repository.getModels(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: <ChatModelModel>[])));
    when(() => repository.getConfigOptions(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: <ChatConfigOptionModel>[])));
    when(() => repository.getSkills(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: <ChatSkillModel>[])));
    when(() => repository.getWorkspacePaths(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: WorkspacePathsModel())));
    when(() => repository.events(after: any(named: 'after'), cancelToken: any(named: 'cancelToken')))
        .thenAnswer((_) => const Stream<ConversationEventModel>.empty());
    when(() => repository.sendMessage(any(), any())).thenAnswer((_) async => const Result.success(true));
    when(() => repository.steer(any(), any())).thenAnswer((_) async => const Result.success(true));
    when(() => repository.interrupt(any())).thenAnswer((_) async => const Result.success(true));
    when(() => repository.compact(any())).thenAnswer((_) async => const Result.success(true));
    when(() => repository.reloadMcpServers(any())).thenAnswer((_) async => const Result.success(true));
    when(() => repository.setTitle(any(), any())).thenAnswer((_) async => const Result.success(true));
    when(() => repository.setSettings(any(), any())).thenAnswer((_) async => const Result.success(true));
    when(() => repository.resolveApproval(any(), any())).thenAnswer((_) async => const Result.success(true));
    when(() => repository.resolveInput(any(), any())).thenAnswer((_) async => const Result.success(true));
    when(() => repository.rollbackTurn(any(), any())).thenAnswer((_) async => const Result.success(2));
  });

  blocTest<ChatCubit, ChatState>(
    'sends a message with a generated client id and refreshes afterwards',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send('ship it');
    },
    verify: (cubit) {
      final params = verify(() => repository.sendMessage('w-1', captureAny())).captured.single as SendMessageParams;
      expect(params.text, 'ship it');
      expect(params.clientMessageId, startsWith('mobile-'));
      expect(cubit.pendingSends, isEmpty);
      verify(() => repository.getConversationPage('w-1', beforeSequence: null)).called(2);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'keeps a failed send retryable with the daemon reason',
    build: () {
      when(() => repository.sendMessage(any(), any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'Delivery failed')),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send('ship it');
    },
    verify: (cubit) {
      expect(cubit.pendingSends.single.failed, isTrue);
      expect(cubit.pendingSends.single.error, 'Delivery failed');
      expect(cubit.pendingSends.single.text, 'ship it');
    },
  );

  blocTest<ChatCubit, ChatState>(
    'retries and discards a pending send by id',
    build: () {
      var call = 0;
      when(() => repository.sendMessage(any(), any())).thenAnswer((_) async {
        call += 1;
        return call == 1
            ? Result.failure(ServerFailure(error: 'x', message: 'Delivery failed'))
            : const Result.success(true);
      });
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send('ship it');
      final id = cubit.pendingSends.single.id;
      await cubit.retrySend(id);
    },
    verify: (cubit) => expect(cubit.pendingSends, isEmpty),
  );

  blocTest<ChatCubit, ChatState>(
    'discards a pending send without sending it again',
    build: () {
      when(() => repository.sendMessage(any(), any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'Delivery failed')),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send('ship it');
      cubit.discardSend(cubit.pendingSends.single.id);
    },
    verify: (cubit) {
      expect(cubit.pendingSends, isEmpty);
      verify(() => repository.sendMessage(any(), any())).called(1);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'stages attachments, references their paths, and drops payloads a provider cannot read',
    build: () {
      when(() => repository.stageAttachments(any(), any()))
          .thenAnswer((_) async => const Result.success(['/w/shot.png']));
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send('look', attachments: const [ChatImageModel(mimeType: 'image/png', data: 'AAA')]);
    },
    verify: (cubit) {
      final params = verify(() => repository.sendMessage('w-1', captureAny())).captured.single as SendMessageParams;
      expect(params.text, 'look\n\nAttached files are available in the worktree:\n- /w/shot.png');
      expect(params.attachments, isNull);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'keeps the inline image when the provider advertises images',
    build: () {
      when(() => repository.stageAttachments(any(), any()))
          .thenAnswer((_) async => const Result.success(['/w/shot.png']));
      return build(capabilities: const ['images']);
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send('look', attachments: const [ChatImageModel(mimeType: 'image/png', data: 'AAA')]);
    },
    verify: (cubit) {
      final params = verify(() => repository.sendMessage('w-1', captureAny())).captured.single as SendMessageParams;
      expect(params.attachments, hasLength(1));
    },
  );

  blocTest<ChatCubit, ChatState>(
    'records the message and the machine code when an action is refused',
    build: () {
      when(() => repository.steer(any(), any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(error: 'x', message: 'nope', apiStatus: 'CHAT_STEER_UNSUPPORTED'),
        ),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.steer('use the other file');
    },
    verify: (cubit) {
      expect(cubit.actionErrors[ConversationAction.steer], contains('Queue a new message'));
      expect(cubit.actionCodes[ConversationAction.steer], 'CHAT_STEER_UNSUPPORTED');
      expect(cubit.actionError, contains('Queue a new message'));
      expect(cubit.pendingActions, isEmpty);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'clears a previous refusal when the same action is retried',
    build: () {
      var call = 0;
      when(() => repository.compact(any())).thenAnswer((_) async {
        call += 1;
        return call == 1
            ? Result.failure(ServerFailure(error: 'x', message: 'busy', apiStatus: 'CHAT_COMPACTION_BUSY'))
            : const Result.success(true);
      });
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.compact();
      await cubit.compact();
    },
    verify: (cubit) {
      expect(cubit.actionErrors[ConversationAction.compact], isNull);
      expect(cubit.actionCodes[ConversationAction.compact], isNull);
      expect(cubit.actionError, isNull);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'drops historical pages before reloading after a rollback',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await cubit.rollback('t-1'), 2);
    },
    verify: (cubit) {
      final params = verify(() => repository.rollbackTurn('w-1', captureAny())).captured.single as RollbackTurnParams;
      expect(params.turnId, 't-1');
      verify(() => repository.getConversationPage('w-1', beforeSequence: null)).called(2);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'routes each remaining action to its endpoint',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.interrupt();
      await cubit.resolveApproval('req-1', 'accept');
      await cubit.resolveInput('req-2', 'accept', const {'token': 'x'});
      await cubit.reloadMcp();
      await cubit.rename('New title');
      await cubit.chooseSettings(const TurnSettingsModel(model: 'opus'));
      await cubit.setConfigOption(const SetConfigOptionParams(optionId: 'fast', enabled: true));
    },
    verify: (_) {
      verify(() => repository.interrupt('w-1')).called(1);
      verify(() => repository.resolveApproval('w-1', any())).called(1);
      verify(() => repository.resolveInput('w-1', any())).called(1);
      verify(() => repository.reloadMcpServers('w-1')).called(1);
      verify(() => repository.setTitle('w-1', any())).called(1);
      verify(() => repository.setSettings('w-1', any())).called(1);
      verify(() => repository.setConfigOption('w-1', any())).called(1);
    },
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/logic/chat_cubit_actions_test.dart`
Expected: FAIL — `send`, `ConversationAction` and the rest are not defined.

- [ ] **Step 3: Add the action surface to the cubit**

At the top of `chat_cubit.dart`, beside `ChatUnavailable`:

```dart
enum ConversationAction { steer, interrupt, approval, input, compact, rollback, settings, config, mcp, rename }

class PendingSend extends Equatable {
  const PendingSend({
    required this.id,
    required this.text,
    this.failed = false,
    this.error,
    this.attachments,
    this.resources,
  });

  final String id;
  final String text;
  final bool failed;
  final String? error;
  final List<ChatImageModel>? attachments;
  final List<ChatResourceModel>? resources;

  PendingSend copyWith({bool? failed, String? error}) => PendingSend(
        id: id,
        text: text,
        failed: failed ?? this.failed,
        error: error,
        attachments: attachments,
        resources: resources,
      );

  @override
  List<Object?> get props => [id, text, failed, error, attachments, resources];
}
```

Inside `ChatCubit`, beside the Task 17 fields:

```dart
  List<PendingSend> pendingSends = [];
  Set<ConversationAction> pendingActions = {};
  String? actionError;
  Map<ConversationAction, String> actionErrors = {};
  Map<ConversationAction, String> actionCodes = {};
```

and the methods:

```dart
  Future<void> send(
    String text, {
    List<ChatImageModel>? attachments,
    List<ChatResourceModel>? resources,
  }) async {
    var message = text;
    var payload = attachments;

    if (attachments != null && attachments.isNotEmpty) {
      final staged = await _repository.stageAttachments(
        sessionId,
        StageAttachmentsParams(attachments: attachments),
      );
      if (isClosed) return;
      staged.when(
        onSuccess: (paths) {
          message = _withAttachmentReferences(text, paths);
          if (!(snapshot?.can('images') ?? false)) payload = null;
        },
        onFailure: (failure) => message = text,
      );
      if (staged.isFailure) {
        final pending = PendingSend(
          id: _clientMessageId(),
          text: text,
          failed: true,
          error: staged.errorMessage,
          attachments: attachments,
          resources: resources,
        );
        pendingSends = [...pendingSends, pending];
        _emit();
        return;
      }
    }

    await _deliver(PendingSend(
      id: _clientMessageId(),
      text: message,
      attachments: payload,
      resources: resources,
    ));
  }

  Future<void> retrySend(String id) async {
    for (final pending in pendingSends) {
      if (pending.id == id) {
        await _deliver(pending);
        return;
      }
    }
  }

  void discardSend(String id) {
    pendingSends = pendingSends.where((pending) => pending.id != id).toList();
    _emit();
  }

  Future<void> steer(String text) => _runAction(
        ConversationAction.steer,
        () => _repository.steer(
          sessionId,
          SteerConversationParams(text: text, clientMessageId: _clientMessageId()),
        ),
      );

  Future<void> interrupt() =>
      _runAction(ConversationAction.interrupt, () => _repository.interrupt(sessionId));

  Future<void> resolveApproval(String requestId, String decisionId) => _runAction(
        ConversationAction.approval,
        () => _repository.resolveApproval(
          sessionId,
          ResolveApprovalParams(requestId: requestId, decisionId: decisionId),
        ),
      );

  Future<void> resolveInput(String requestId, String action, [Map<String, dynamic>? content]) =>
      _runAction(
        ConversationAction.input,
        () => _repository.resolveInput(
          sessionId,
          ResolveInputParams(requestId: requestId, action: action, content: content),
        ),
      );

  Future<void> compact() => _runAction(ConversationAction.compact, () => _repository.compact(sessionId));

  Future<int> rollback(String turnId) async {
    var discarded = 0;
    await _runAction(
      ConversationAction.rollback,
      () async {
        final result = await _repository.rollbackTurn(sessionId, RollbackTurnParams(turnId: turnId));
        discarded = result.getOrDefault(0);
        return result.isSuccess ? const Result<bool, Failure>.success(true) : result.asFailure();
      },
      resetHistoricalPages: true,
    );
    return discarded;
  }

  Future<void> chooseSettings(TurnSettingsModel settings) => _runAction(
        ConversationAction.settings,
        () => _repository.setSettings(sessionId, settings),
      );

  Future<void> setConfigOption(SetConfigOptionParams params) => _runAction(
        ConversationAction.config,
        () async {
          final result = await _repository.setConfigOption(sessionId, params);
          result.when(
            onSuccess: (response) => configOptions = response.data ?? configOptions,
            onFailure: (_) {},
          );
          return result.isSuccess ? const Result<bool, Failure>.success(true) : result.asFailure();
        },
      );

  Future<void> reloadMcp() =>
      _runAction(ConversationAction.mcp, () => _repository.reloadMcpServers(sessionId));

  Future<void> rename(String title) => _runAction(
        ConversationAction.rename,
        () => _repository.setTitle(sessionId, SetConversationTitleParams(title: title)),
      );

  Future<void> resumeAgent() async {
    final result = await _repository.resumeAgent(sessionId);
    if (isClosed) return;
    result.when(
      onSuccess: (_) => unawaited(refresh()),
      onFailure: (failure) {
        actionError = conversationActionError(failure);
        _emit();
      },
    );
  }

  Future<void> _deliver(PendingSend pending) async {
    pendingSends = _upsertPending(pendingSends, pending.copyWith(failed: false));
    _emit();

    final result = await _repository.sendMessage(
      sessionId,
      SendMessageParams(
        text: pending.text,
        clientMessageId: pending.id,
        attachments: pending.attachments,
        resources: pending.resources,
      ),
    );
    if (isClosed) return;

    await result.when(
      onSuccess: (_) async {
        pendingSends = pendingSends.where((item) => item.id != pending.id).toList();
        await refresh();
      },
      onFailure: (failure) async {
        pendingSends = _upsertPending(
          pendingSends,
          pending.copyWith(failed: true, error: conversationActionError(failure)),
        );
        _emit();
      },
    );
  }

  Future<void> _runAction(
    ConversationAction kind,
    Future<Result<bool, Failure>> Function() action, {
    bool resetHistoricalPages = false,
  }) async {
    pendingActions = {...pendingActions, kind};
    actionError = null;
    actionErrors = {...actionErrors}..remove(kind);
    actionCodes = {...actionCodes}..remove(kind);
    _emit();

    final result = await action();
    if (isClosed) return;

    await result.when(
      onSuccess: (_) async {
        if (resetHistoricalPages) {
          _pages
            ..clear()
            ..addAll(discardHistoricalPages(_pages));
        }
        pendingActions = {...pendingActions}..remove(kind);
        await refresh();
      },
      onFailure: (failure) async {
        final message = conversationActionError(failure);
        actionError = message;
        actionErrors = {...actionErrors, kind: message};
        final code = conversationErrorCode(failure);
        if (code != null) actionCodes = {...actionCodes, kind: code};
        pendingActions = {...pendingActions}..remove(kind);
        _emit();
      },
    );
  }

  static List<PendingSend> _upsertPending(List<PendingSend> items, PendingSend next) {
    final index = items.indexWhere((item) => item.id == next.id);
    if (index < 0) return [...items, next];
    return [...items]..[index] = next;
  }

  static String _clientMessageId() =>
      'mobile-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-'
      '${Random().nextInt(1 << 32).toRadixString(36)}';

  static String _withAttachmentReferences(String text, List<String> paths) {
    if (paths.isEmpty) return text;
    final references = paths.map((path) => '- $path').join('\n');
    final trimmed = text.trim();
    return '$trimmed${trimmed.isEmpty ? '' : '\n\n'}'
        'Attached files are available in the worktree:\n$references';
  }
```

Add `import 'dart:math';` and imports for `ChatImageModel`, `ChatResourceModel` and the params
classes.

- [ ] **Step 4: Give `Result` the two helpers this uses**

`_runAction` needs to re-type a `Result<T, Failure>` as `Result<bool, Failure>` when the action's
own payload has already been consumed. In
`packages/mobile/lib/core/helpers/result/result.dart`, add to `ResultExtensions`:

```dart
  Result<R, E> asFailure<R>() => switch (this) {
    _ResultFailure<T, E>(:final error) => Result<R, E>.failure(error),
    _ => throw StateError('asFailure called on a success'),
  };
```

`errorMessage` already exists there and returns the failure's `toString()`; `send` uses it only for
the staging-failure path, where the daemon message is already the useful part.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/logic/chat_cubit_actions_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 523/523 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add chat actions and pending sends"
```

---

### Task 19: `ChatCubit` — the live event stream (`useConversation.ts` part 3)

**Files:**
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/logic/chat_cubit.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/logic/chat_cubit_stream_test.dart`

**Interfaces:**
- Consumes: `ChatRepository.events` (Task 16), `ServerConfigStore`, `CacheHelper`/`CacheKeys` (Task 1).
- Produces, on `ChatCubit`:
  - constructor gains `ServerConfigStore configStore` and the optional
    `Duration refreshDebounce`, `Duration reconnectMin`, `Duration reconnectMax`
  - `Future<void> onResumed()` — called by the screen when the app returns to the foreground

The daemon owns durable replay. The phone persists **only the cursor**; after backgrounding it
reconnects from that point and then reloads the authoritative page. That is the whole design: the
SSE stream is a *hint that something changed*, never the source of conversation content.

Four behaviors matter and are what the test pins:

- Only events whose `sessionId` matches this session and that carry a `conversationId` trigger a
  reload. Everything else advances the cursor and is dropped — the `/events` stream is
  daemon-wide.
- Reloads are **debounced by 120 ms**. A streaming assistant message produces a burst of events;
  without the debounce each one would start its own full page fetch.
- The cursor is persisted on every event, so a backgrounded app resumes where it left off.
- The stream reconnects with backoff from 1s to 15s, resetting to 1s after a clean run — the same
  ladder `MuxBackoff` uses for the board socket, but local to this cubit because the daemon's SSE
  endpoint and the mux socket fail independently.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/presentation/chat_screen/logic/chat_cubit_stream_test.dart`:

```dart
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockChatRepository extends Mock implements ChatRepository {}

class _MockConfigStore extends Mock implements ServerConfigStore {}

void main() {
  late _MockChatRepository repository;
  late _MockConfigStore configStore;
  late StreamController<ConversationEventModel> events;

  const config = ServerConfig(host: 'opr.test', httpPort: '3011', secure: false, password: 'secret12');

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();

    repository = _MockChatRepository();
    configStore = _MockConfigStore();
    events = StreamController<ConversationEventModel>.broadcast();

    when(() => configStore.current).thenReturn(config);
    when(() => repository.getConversationPage('w-1', beforeSequence: null)).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: const ConversationSnapshotModel(
            conversationId: 'c-1',
            sessionId: 'w-1',
            harness: 'codex',
            controllerState: 'ready',
            latestSequence: 1,
          ),
        ),
      ),
    );
    when(() => repository.getModels(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: <ChatModelModel>[])));
    when(() => repository.getConfigOptions(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: <ChatConfigOptionModel>[])));
    when(() => repository.getSkills(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: <ChatSkillModel>[])));
    when(() => repository.getWorkspacePaths(any()))
        .thenAnswer((_) async => const Result.success(GlobalResponse(data: WorkspacePathsModel())));
    when(() => repository.events(after: any(named: 'after'), cancelToken: any(named: 'cancelToken')))
        .thenAnswer((_) => events.stream);
  });

  tearDown(() => events.close());

  ChatCubit build() => ChatCubit(
        repository,
        'w-1',
        configStore: configStore,
        refreshDebounce: const Duration(milliseconds: 10),
        reconnectMin: const Duration(milliseconds: 10),
        reconnectMax: const Duration(milliseconds: 20),
      );

  blocTest<ChatCubit, ChatState>(
    'reloads once for a burst of conversation events',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      for (var seq = 1; seq <= 4; seq++) {
        events.add(ConversationEventModel(seq: seq, sessionId: 'w-1', payload: const {'conversationId': 'c-1'}));
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    },
    verify: (_) => verify(() => repository.getConversationPage('w-1', beforeSequence: null)).called(2),
  );

  blocTest<ChatCubit, ChatState>(
    'ignores events for other sessions and events with no conversation',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      events.add(const ConversationEventModel(seq: 2, sessionId: 'other', payload: {'conversationId': 'c-9'}));
      events.add(const ConversationEventModel(seq: 3, sessionId: 'w-1'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    },
    verify: (_) => verify(() => repository.getConversationPage('w-1', beforeSequence: null)).called(1),
  );

  blocTest<ChatCubit, ChatState>(
    'persists the cursor so a reconnect resumes where it stopped',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      events.add(const ConversationEventModel(seq: 12, sessionId: 'w-1'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    },
    verify: (_) => expect(
      CacheHelper.get(CacheKeys.chatEventCursor('opr.test', '3011', 'w-1')),
      12,
    ),
  );

  blocTest<ChatCubit, ChatState>(
    'resumes the stream from the persisted cursor on a later mount',
    setUp: () async {
      await CacheHelper.save(CacheKeys.chatEventCursor('opr.test', '3011', 'w-1'), 41);
    },
    build: build,
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 10)),
    verify: (_) => verify(() => repository.events(after: 41, cancelToken: any(named: 'cancelToken'))).called(1),
  );

  blocTest<ChatCubit, ChatState>(
    'reconnects after the stream drops',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      events.addError(ServerFailure(error: 'dropped', message: 'stream closed'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    },
    verify: (_) => verify(() => repository.events(after: any(named: 'after'), cancelToken: any(named: 'cancelToken')))
        .called(greaterThan(1)),
  );

  blocTest<ChatCubit, ChatState>(
    'reloads when the app returns to the foreground',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.onResumed();
    },
    verify: (_) => verify(() => repository.getConversationPage('w-1', beforeSequence: null)).called(2),
  );

  blocTest<ChatCubit, ChatState>(
    'never opens a stream for a conversation that is permanently unavailable',
    build: () {
      when(() => repository.getConversationPage('w-1', beforeSequence: null)).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'gone', apiStatus: 'SESSION_NOT_FOUND')),
      );
      return build();
    },
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 40)),
    verify: (_) => verifyNever(() => repository.events(after: any(named: 'after'), cancelToken: any(named: 'cancelToken'))),
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/logic/chat_cubit_stream_test.dart`
Expected: FAIL — `configStore`, `refreshDebounce` and `onResumed` are not defined.

- [ ] **Step 3: Extend the constructor**

```dart
  ChatCubit(
    this._repository,
    this.sessionId, {
    required ServerConfigStore configStore,
    Duration configPoll = const Duration(seconds: 5),
    Duration skillPoll = const Duration(seconds: 60),
    Duration workspacePoll = const Duration(seconds: 30),
    Duration refreshDebounce = const Duration(milliseconds: 120),
    Duration reconnectMin = const Duration(seconds: 1),
    Duration reconnectMax = const Duration(seconds: 15),
  })  : _configStore = configStore,
        _configPoll = configPoll,
        _skillPoll = skillPoll,
        _workspacePoll = workspacePoll,
        _refreshDebounce = refreshDebounce,
        _reconnectMin = reconnectMin,
        _reconnectMax = reconnectMax,
        super(const ChatInitialState()) {
    scheduleMicrotask(() => unawaited(refresh()));
  }
```

with the matching `final` fields, and update the service-locator registration from Task 17 to pass
`configStore: sl<ServerConfigStore>()`. The Task 17 and Task 18 tests construct `ChatCubit`
directly and must be updated to pass a `_MockConfigStore` whose `current` returns a
`ServerConfig`, plus `SharedPreferences.setMockInitialValues({})` and `await CacheHelper.init()` in
their `setUp` — the cursor read happens on the first stream attempt.

- [ ] **Step 4: Add the stream loop**

Inside `ChatCubit`:

```dart
  CancelToken? _eventCancel;
  StreamSubscription<ConversationEventModel>? _eventSub;
  Timer? _refreshTimer;
  Timer? _reconnectTimer;
  Duration _reconnectDelay = Duration.zero;
  int _cursor = 0;
  bool _streaming = false;

  Future<void> onResumed() => refresh();

  void _startEvents() {
    if (_streaming || unavailable != null || snapshot == null) return;
    _streaming = true;
    _reconnectDelay = _reconnectMin;
    _cursor = (CacheHelper.get(_cursorKey) as int?) ?? 0;
    _openEventStream();
  }

  void _openEventStream() {
    if (isClosed || !_streaming) return;
    final cancelToken = CancelToken();
    _eventCancel = cancelToken;
    _eventSub = _repository.events(after: _cursor, cancelToken: cancelToken).listen(
          _onEvent,
          onError: (Object _) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
  }

  void _onEvent(ConversationEventModel event) {
    _reconnectDelay = _reconnectMin;
    if (event.seq > _cursor) {
      _cursor = event.seq;
      unawaited(CacheHelper.save(_cursorKey, _cursor));
    }
    if (event.sessionId != sessionId || !event.touchesConversation) return;

    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () => unawaited(refresh()));
  }

  void _scheduleReconnect() {
    unawaited(_eventSub?.cancel());
    _eventSub = null;
    if (isClosed || !_streaming) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, _openEventStream);
    final next = _reconnectDelay * 2;
    _reconnectDelay = next > _reconnectMax ? _reconnectMax : next;
  }

  String get _cursorKey {
    final config = _configStore.current;
    return CacheKeys.chatEventCursor(config?.host ?? '', config?.httpPort ?? '', sessionId);
  }
```

Call `_startEvents();` immediately after `_startCatalogs();` at the end of `refresh()`, and extend
`close()`:

```dart
  @override
  Future<void> close() {
    _streaming = false;
    _configTimer?.cancel();
    _skillTimer?.cancel();
    _workspaceTimer?.cancel();
    _refreshTimer?.cancel();
    _reconnectTimer?.cancel();
    _eventCancel?.cancel();
    unawaited(_eventSub?.cancel());
    return super.close();
  }
```

Add `import 'package:dio/dio.dart';`, `import 'package:operator_mobile/core/api/server_config_store.dart';`
and `import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/logic/`
Expected: PASS — all three cubit test files.

- [ ] **Step 6: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 530/530 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): stream live conversation updates into ChatCubit"
```

---

### Task 20: Markdown, code and the shared timeline atoms

**Files:**
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/highlighted_code_text.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_markdown.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_markdown_test.dart`

**Interfaces:**
- Consumes: `parseBlocks` (Task 5), `highlightCode` (Task 6), `AppSkin`, `AppTextStyle`.
- Produces:
  - `class HighlightedCodeText extends StatelessWidget` — `code`, `language`, `streaming`, `style`
  - `class ChatMarkdown extends StatelessWidget` — `text`, `streaming`
  - `class ChatActionButton extends StatelessWidget` — `label`, `hint`, `onPressed`, `primary`,
    `danger`, `enabled`
  - `class LabelValue extends StatelessWidget` — `label`, `value`
  - `class CodeOutput extends StatelessWidget` — `value`
  - `class DetailLabel extends StatelessWidget` — `label`
  - `class PartialNote extends StatelessWidget` — `text`, `warning`

Streaming code stays **plain text**: rapidly arriving deltas would otherwise trigger a full grammar
pass on every character. It is highlighted once the stream settles, which is why `streaming` is a
parameter rather than something the widget infers.

Everything selectable in RN stays selectable here (`SelectableText.rich`), and long-pressing a code
block copies it, matching `CodeOutput`'s `onLongPress`.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_markdown_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_markdown.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders prose, headings and list markers', (tester) async {
    await pump(tester, const ChatMarkdown(text: '# Findings\n\nAll good\n\n- one\n- two'));

    expect(find.text('Findings'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
  });

  testWidgets('renders a fenced code block with its language and a copy control', (tester) async {
    await pump(tester, const ChatMarkdown(text: '```dart\nvoid main() {}\n```'));

    expect(find.text('DART'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.textContaining('void main()'), findsOneWidget);
  });

  testWidgets('marks completed task items', (tester) async {
    await pump(tester, const ChatMarkdown(text: '- [x] inspect\n- [ ] test'));

    expect(find.text('☑'), findsOneWidget);
    expect(find.text('☐'), findsOneWidget);
  });

  testWidgets('renders a table without overflowing the page', (tester) async {
    await pump(tester, const ChatMarkdown(text: '| File | State |\n| --- | --- |\n| app.ts | changed |'));

    expect(find.text('File'), findsOneWidget);
    expect(find.text('app.ts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a streaming placeholder rather than an empty bubble', (tester) async {
    await pump(tester, const ChatMarkdown(text: '…', streaming: true));
    expect(find.text('…'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_markdown_test.dart`
Expected: FAIL — the widgets do not exist.

- [ ] **Step 3: Write the code renderer**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/highlighted_code_text.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/feature/chat/logic/syntax_highlight.dart';

class HighlightedCodeText extends StatelessWidget {
  const HighlightedCodeText({
    super.key,
    required this.code,
    this.language,
    this.streaming = false,
    this.style,
  });

  final String code;
  final String? language;
  final bool streaming;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final base = (style ?? AppTextStyle.mono13Regular).copyWith(
      color: style?.color ?? skin.textPrimary,
      height: 1.5,
    );
    final tokens = streaming ? null : highlightCode(code, language);

    if (tokens == null) return SelectableText(code, style: base);

    return SelectableText.rich(
      TextSpan(
        children: [
          for (final token in tokens)
            TextSpan(text: token.text, style: base.copyWith(color: _tokenColor(skin, token.kind))),
        ],
      ),
      style: base,
    );
  }

  Color _tokenColor(AppSkin skin, SyntaxTokenKind kind) {
    switch (kind) {
      case SyntaxTokenKind.comment:
        return skin.textFaint;
      case SyntaxTokenKind.string:
      case SyntaxTokenKind.addition:
        return skin.green;
      case SyntaxTokenKind.number:
        return skin.orange;
      case SyntaxTokenKind.keyword:
        return skin.purple;
      case SyntaxTokenKind.type:
      case SyntaxTokenKind.meta:
        return skin.blue;
      case SyntaxTokenKind.deletion:
        return skin.red;
      case SyntaxTokenKind.plain:
        return skin.textPrimary;
    }
  }
}
```

- [ ] **Step 4: Write the shared atoms**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class ChatActionButton extends StatelessWidget {
  const ChatActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.hint,
    this.primary = false,
    this.danger = false,
    this.enabled = true,
  });

  final String label;
  final String? hint;
  final VoidCallback onPressed;
  final bool primary;
  final bool danger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final fill = danger ? skin.tintRed : (primary ? skin.blue : skin.bgElevated);
    final ink = danger ? skin.red : (primary ? skin.onAccent : skin.textPrimary);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(label, style: AppTextStyle.style13SemiBold.copyWith(color: ink)),
                if (hint != null) ...[
                  const VerticalSpace(2),
                  AppText(hint!, style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary), maxLines: 2),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DetailLabel extends StatelessWidget {
  const DetailLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => AppText(
        label.toUpperCase(),
        style: AppTextStyle.mono10Regular.copyWith(color: context.skin.textFaint, letterSpacing: 0.7),
      );
}

class LabelValue extends StatelessWidget {
  const LabelValue({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DetailLabel(label: label),
            const HorizontalSpace(8),
            Expanded(
              child: SelectableText(
                value,
                style: AppTextStyle.mono11Regular.copyWith(color: context.skin.textSecondary),
              ),
            ),
          ],
        ),
      );
}

class CodeOutput extends StatelessWidget {
  const CodeOutput({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return GestureDetector(
      onLongPress: () => Clipboard.setData(ClipboardData(text: value)),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: skin.bgColumn, borderRadius: BorderRadius.circular(8)),
        child: SelectableText(
          value,
          style: AppTextStyle.mono11Regular.copyWith(color: skin.textSecondary, height: 1.5),
        ),
      ),
    );
  }
}

class PartialNote extends StatelessWidget {
  const PartialNote({super.key, required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AppText(
        text,
        style: AppTextStyle.style10Regular.copyWith(color: warning ? skin.amber : skin.textTertiary),
        maxLines: 4,
      ),
    );
  }
}
```

- [ ] **Step 5: Write the markdown renderer**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_markdown.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/logic/markdown_blocks.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/highlighted_code_text.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _inline = RegExp(
  r'(\[([^\]]+)\]\((https?://[^\s)]+)\)|<(https?://[^\s>]+)>|`([^`]+)`|\*\*([^*]+)\*\*|__([^_]+)__|'
  r'~~([^~]+)~~|\*([^*\n]+)\*|_([^_\n]+)_|(https?://[^\s<]+))',
);

class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown({super.key, required this.text, this.streaming = false});

  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final blocks = parseBlocks(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          if (index > 0) const VerticalSpace(10),
          _block(context, skin, blocks[index]),
        ],
      ],
    );
  }

  Widget _block(BuildContext context, AppSkin skin, MarkdownBlock block) {
    switch (block) {
      case CodeBlock(:final text, :final language):
        return _CodeCard(code: text, language: language, streaming: streaming);
      case ImageBlock(:final alt, :final url):
        return _MarkdownImage(alt: alt, url: url);
      case TableBlock(:final headers, :final rows):
        return _MarkdownTable(headers: headers, rows: rows);
      case RuleBlock():
        return Container(height: 1, color: skin.borderSubtle);
      case ListBlock(:final ordered, :final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < items.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: AppText(
                        items[index].checked != null
                            ? (items[index].checked! ? '☑' : '☐')
                            : (ordered ? '${index + 1}.' : '•'),
                        style: AppTextStyle.style15Regular.copyWith(color: skin.textTertiary),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const HorizontalSpace(8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: _spans(context, skin, items[index].text)),
                        style: AppTextStyle.style16Regular.copyWith(
                          color: items[index].checked == true ? skin.textTertiary : skin.textPrimary,
                          height: 1.5,
                          decoration:
                              items[index].checked == true ? TextDecoration.lineThrough : TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case HeadingBlock(:final text, :final level):
        return Text.rich(
          TextSpan(children: _spans(context, skin, text)),
          style: (level > 2 ? AppTextStyle.style16Bold : AppTextStyle.style19SemiBold)
              .copyWith(color: skin.textPrimary, height: 1.35),
        );
      case QuoteBlock(:final text):
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: skin.borderStrong, width: 2)),
          ),
          child: Text.rich(
            TextSpan(children: _spans(context, skin, text)),
            style: AppTextStyle.style15Regular.copyWith(
              color: skin.textSecondary,
              height: 1.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      case ParagraphBlock(:final text):
        return SelectableText.rich(
          TextSpan(children: _spans(context, skin, text)),
          style: AppTextStyle.style16Regular.copyWith(color: skin.textPrimary, height: 1.5),
        );
    }
  }

  List<InlineSpan> _spans(BuildContext context, AppSkin skin, String value) {
    final spans = <InlineSpan>[];
    var at = 0;

    for (final match in _inline.allMatches(value)) {
      if (match.start > at) spans.add(TextSpan(text: value.substring(at, match.start)));

      final url = match.group(3) ?? match.group(4) ?? match.group(11);
      if (url != null) {
        spans.add(
          TextSpan(
            text: match.group(2) ?? url,
            style: TextStyle(color: skin.blue, decoration: TextDecoration.underline),
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        );
      } else if (match.group(5) != null) {
        spans.add(
          TextSpan(
            text: match.group(5),
            style: AppTextStyle.mono13Regular.copyWith(color: skin.blue, backgroundColor: skin.bgSubtle),
          ),
        );
      } else if (match.group(6) != null || match.group(7) != null) {
        spans.add(TextSpan(
          text: match.group(6) ?? match.group(7),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (match.group(8) != null) {
        spans.add(TextSpan(
          text: match.group(8),
          style: const TextStyle(decoration: TextDecoration.lineThrough),
        ));
      } else {
        spans.add(TextSpan(
          text: match.group(9) ?? match.group(10),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }
      at = match.end;
    }

    if (at < value.length) spans.add(TextSpan(text: value.substring(at)));
    return spans;
  }
}

class _CodeCard extends StatefulWidget {
  const _CodeCard({required this.code, required this.streaming, this.language});

  final String code;
  final String? language;
  final bool streaming;

  @override
  State<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<_CodeCard> {
  bool _wrap = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final body = HighlightedCodeText(
      code: widget.code,
      language: widget.language,
      streaming: widget.streaming,
      style: AppTextStyle.mono13Regular,
    );

    return Container(
      decoration: BoxDecoration(
        color: skin.bgColumn,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: skin.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppText(
                    (widget.language ?? 'code').toUpperCase(),
                    style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary),
                  ),
                ),
                _CodeAction(
                  icon: Icons.wrap_text,
                  label: 'Wrap',
                  active: _wrap,
                  onTap: () => setState(() => _wrap = !_wrap),
                ),
                _CodeAction(
                  icon: _copied ? Icons.check : Icons.copy_outlined,
                  label: _copied ? 'Copied' : 'Copy',
                  active: _copied,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: widget.code));
                    if (!mounted) return;
                    setState(() => _copied = true);
                    await Future<void>.delayed(const Duration(milliseconds: 1400));
                    if (mounted) setState(() => _copied = false);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _wrap
                ? body
                : SingleChildScrollView(scrollDirection: Axis.horizontal, child: body),
          ),
        ],
      ),
    );
  }
}

class _CodeAction extends StatelessWidget {
  const _CodeAction({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final color = active ? skin.blue : skin.textTertiary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 13, color: color),
            const HorizontalSpace(5),
            AppText(label, style: AppTextStyle.style11SemiBold.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _MarkdownImage extends StatefulWidget {
  const _MarkdownImage({required this.alt, required this.url});

  final String alt;
  final String url;

  @override
  State<_MarkdownImage> createState() => _MarkdownImageState();
}

class _MarkdownImageState extends State<_MarkdownImage> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    if (_failed) {
      return AppText(
        'Image unavailable: ${widget.alt.isEmpty ? widget.url : widget.alt}',
        style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary, fontStyle: FontStyle.italic),
        maxLines: 2,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: skin.bgColumn,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120, maxHeight: 420),
            child: Image.network(
              widget.url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _failed = true);
                });
                return const SizedBox.shrink();
              },
            ),
          ),
          if (widget.alt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: AppText(
                widget.alt,
                style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
                maxLines: 2,
              ),
            ),
        ],
      ),
    );
  }
}

class _MarkdownTable extends StatelessWidget {
  const _MarkdownTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    Widget cell(String value, {bool header = false}) => Container(
          constraints: const BoxConstraints(minWidth: 110, maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: AppText(
            value,
            style: header
                ? AppTextStyle.style12Bold.copyWith(color: skin.textPrimary)
                : AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
            maxLines: 3,
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: skin.borderSubtle),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: skin.bgSubtle,
              child: Row(children: [for (final header in headers) cell(header, header: true)]),
            ),
            for (final row in rows)
              Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: skin.borderSubtle))),
                child: Row(
                  children: [
                    for (var index = 0; index < headers.length; index++)
                      cell(index < row.length ? row[index] : ''),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_markdown_test.dart`
Expected: PASS.

- [ ] **Step 7: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 535/535 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): render chat markdown and highlighted code"
```

---

### Task 21: Approval and elicitation cards

**Files:**
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/approval_card.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/user_input_card.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/ui/request_cards_test.dart`

**Interfaces:**
- Consumes: `ConversationActivityModel`, `InputSchemaModel`/`InputPropertyModel` (Task 11), the
  elicitation model (Task 8), Task 20's atoms.
- Produces:
  - `class ApprovalCard extends StatefulWidget` — `activity`, `busy`,
    `onDecide(String requestId, String decisionId)`
  - `class UserInputCard extends StatefulWidget` — `activity`, `busy`,
    `onResolve(String requestId, String action, [Map<String, dynamic>? content])`

These two cards are the only places in chat where the phone **blocks the agent**, so their failure
modes are spelled out rather than implied:

- An approval with no decisions Operator can present says so instead of rendering an empty card —
  the provider offered something Operator cannot express, and the user needs to know to go to the
  host.
- A pending request with **no `requestId`** cannot be answered safely at all; both cards refuse to
  offer buttons in that case, with copy that says why.
- A resolved card is kept in the timeline for the record, not removed.
- The URL mode passes its URL through `safeHttpUrl` before offering "Open link". This is the gate
  described in Task 8: a provider-supplied `javascript:` or `file:` URL must never reach
  `url_launcher`.

Validation runs before submit and reports the **first** problem, naming the field by its schema
title (falling back to `humanizeInputName`), exactly as `UserInputCard` does today.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/presentation/chat_screen/ui/request_cards_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/approval_card.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/user_input_card.dart';

ConversationActivityModel request({
  required String kind,
  String status = 'pending',
  String? requestId = 'req-1',
  Map<String, dynamic> detail = const {},
  String summary = 'Run rm -rf build',
}) =>
    ConversationActivityModel(
      id: 'a-1',
      sequence: 1,
      revision: 1,
      activityKind: kind,
      status: status,
      summary: summary,
      requestId: requestId,
      detail: ActivityDetailModel(detail),
    );

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ApprovalCard', () {
    testWidgets('offers each decision and reports the chosen one', (tester) async {
      final chosen = <String>[];
      await pump(
        tester,
        ApprovalCard(
          activity: request(
            kind: 'approval',
            detail: const {
              'command': 'rm -rf build',
              'cwd': '/w',
              'decisions': [
                {'id': 'accept', 'label': 'Allow once'},
                {'id': 'deny', 'label': 'Deny'},
              ],
            },
          ),
          busy: false,
          onDecide: (requestId, decisionId) async => chosen.add('$requestId:$decisionId'),
        ),
      );

      expect(find.text('Approval required'), findsOneWidget);
      expect(find.text('rm -rf build'), findsOneWidget);
      await tester.tap(find.text('Allow once'));
      await tester.pumpAndSettle();
      expect(chosen, ['req-1:accept']);
    });

    testWidgets('says so when the provider offered nothing Operator can present', (tester) async {
      await pump(
        tester,
        ApprovalCard(
          activity: request(kind: 'approval'),
          busy: false,
          onDecide: (_, __) async {},
        ),
      );
      expect(find.textContaining('offered no decisions'), findsOneWidget);
    });

    testWidgets('keeps a resolved approval for the record', (tester) async {
      await pump(
        tester,
        ApprovalCard(
          activity: request(kind: 'approval', status: 'resolved'),
          busy: false,
          onDecide: (_, __) async {},
        ),
      );
      expect(find.text('Approval resolved'), findsOneWidget);
      expect(find.textContaining('kept for the record'), findsOneWidget);
    });
  });

  group('UserInputCard', () {
    testWidgets('submits the form once every required field is filled', (tester) async {
      Map<String, dynamic>? submitted;
      await pump(
        tester,
        UserInputCard(
          activity: request(
            kind: 'user_input',
            summary: 'Sign in',
            detail: const {
              'inputMode': 'form',
              'message': 'Paste a token',
              'schema': {
                'title': 'Credentials',
                'required': ['token'],
                'properties': {
                  'token': {'type': 'string', 'title': 'Token', 'minLength': 4},
                },
              },
            },
          ),
          busy: false,
          onResolve: (requestId, action, [content]) async => submitted = content,
        ),
      );

      expect(find.text('Credentials'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Complete token'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ab');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least 4 characters'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'abcd');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(submitted, {'token': 'abcd'});
    });

    testWidgets('refuses to open a URL the provider made unsafe', (tester) async {
      await pump(
        tester,
        UserInputCard(
          activity: request(
            kind: 'user_input',
            detail: const {'inputMode': 'url', 'url': 'javascript:alert(1)'},
          ),
          busy: false,
          onResolve: (_, __, [___]) async {},
        ),
      );
      expect(find.textContaining('unsafe or invalid URL'), findsOneWidget);
    });

    testWidgets('cannot answer a request with no provider identity', (tester) async {
      await pump(
        tester,
        UserInputCard(
          activity: request(kind: 'user_input', requestId: null),
          busy: false,
          onResolve: (_, __, [___]) async {},
        ),
      );
      expect(find.textContaining('no provider identity'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/request_cards_test.dart`
Expected: FAIL — the cards do not exist.

- [ ] **Step 3: Write the approval card**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/approval_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';

class ApprovalCard extends StatefulWidget {
  const ApprovalCard({
    super.key,
    required this.activity,
    required this.busy,
    required this.onDecide,
  });

  final ConversationActivityModel activity;
  final bool busy;
  final Future<void> Function(String requestId, String decisionId) onDecide;

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  String? _submitting;
  String? _submitError;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final activity = widget.activity;
    final detail = activity.detail;
    final pending = activity.isPending;
    final decisions = activity.decisions ?? const [];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: pending ? skin.amber : skin.borderDefault),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 15, color: pending ? skin.amber : skin.textTertiary),
              const HorizontalSpace(8),
              Expanded(
                child: AppText(
                  pending ? 'Approval required' : 'Approval resolved',
                  style: AppTextStyle.style13SemiBold,
                ),
              ),
              if (activity.requestId != null)
                AppText(
                  'req ${activity.requestId}',
                  style: AppTextStyle.mono10Regular.copyWith(color: skin.textFaint),
                ),
            ],
          ),
          if (detail?.reason != null) ...[
            const VerticalSpace(7),
            AppText(
              detail!.reason!,
              style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
              maxLines: 6,
            ),
          ],
          const VerticalSpace(7),
          SelectableText(
            detail?.command ?? activity.summary,
            style: AppTextStyle.mono12Regular.copyWith(color: skin.textPrimary),
          ),
          if (detail?.cwd != null) LabelValue(label: 'cwd', value: detail!.cwd!),
          const VerticalSpace(10),
          if (pending && activity.requestId != null && decisions.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < decisions.length; index++)
                  ChatActionButton(
                    label: _submitting == decisions[index].id ? 'Sending…' : decisions[index].label,
                    primary: index == 0,
                    enabled: !widget.busy && _submitting == null,
                    onPressed: () async {
                      setState(() {
                        _submitting = decisions[index].id;
                        _submitError = null;
                      });
                      try {
                        await widget.onDecide(activity.requestId!, decisions[index].id);
                      } catch (error) {
                        if (mounted) setState(() => _submitError = error.toString());
                      } finally {
                        if (mounted) setState(() => _submitting = null);
                      }
                    },
                  ),
              ],
            )
          else if (pending)
            const PartialNote(
              warning: true,
              text: 'The agent offered no decisions Operator can present. Open diagnostics from the host.',
            )
          else
            const PartialNote(text: 'Already answered. This card is kept for the record.'),
          if (_submitError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(
                _submitError!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write the elicitation card**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/user_input_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/logic/elicitation_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';
import 'package:url_launcher/url_launcher.dart';

class UserInputCard extends StatefulWidget {
  const UserInputCard({
    super.key,
    required this.activity,
    required this.busy,
    required this.onResolve,
  });

  final ConversationActivityModel activity;
  final bool busy;
  final Future<void> Function(String requestId, String action, [Map<String, dynamic>? content]) onResolve;

  @override
  State<UserInputCard> createState() => _UserInputCardState();
}

class _UserInputCardState extends State<UserInputCard> {
  late Map<String, dynamic> _values = {
    for (final entry in (widget.activity.detail?.schema?.properties ?? const {}).entries)
      entry.key: initialInputValue(entry.value),
  };
  String? _validationError;
  String? _submitError;
  bool _submitting = false;

  Future<void> _resolve(String action, [Map<String, dynamic>? content]) async {
    final requestId = widget.activity.requestId;
    if (_submitting || requestId == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.onResolve(requestId, action, content);
    } catch (error) {
      if (mounted) setState(() => _submitError = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submit(InputSchemaModel? schema) async {
    final missing = missingRequiredInputs(schema?.required, _values);
    if (missing.isNotEmpty) {
      setState(() => _validationError = 'Complete ${missing.join(', ')} before continuing.');
      return;
    }
    for (final entry in (schema?.properties ?? const {}).entries) {
      final problem = validateInput(entry.value, _values[entry.key]);
      if (problem != null) {
        setState(() => _validationError =
            '${entry.value.title ?? humanizeInputName(entry.key)} $problem.');
        return;
      }
    }
    setState(() => _validationError = null);
    await _resolve('accept', _values);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final activity = widget.activity;
    final detail = activity.detail;
    final schema = detail?.schema;
    final pending = activity.isPending;
    final isUrlMode = detail?.inputMode == 'url';
    final url = isUrlMode ? safeHttpUrl(detail?.url) : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: pending ? skin.blue : skin.borderDefault),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 15, color: pending ? skin.blue : skin.textTertiary),
              const HorizontalSpace(8),
              Expanded(
                child: AppText(
                  schema?.title ?? (pending ? 'Agent needs input' : 'Input resolved'),
                  style: AppTextStyle.style13SemiBold,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const VerticalSpace(7),
          AppText(
            detail?.message ?? schema?.description ?? activity.summary,
            style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
            maxLines: 8,
          ),
          if (pending && isUrlMode) ...[
            const VerticalSpace(9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: skin.bgColumn, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(
                url?.toString() ?? 'The provider supplied an unsafe or invalid URL.',
                style: AppTextStyle.mono11Regular.copyWith(color: skin.textSecondary),
              ),
            ),
          ],
          if (pending && !isUrlMode && schema != null)
            for (final entry in schema.properties.entries)
              _InputField(
                name: entry.key,
                property: entry.value,
                required: schema.required.contains(entry.key),
                value: _values[entry.key],
                onChanged: (value) => setState(() {
                  _validationError = null;
                  _values = {..._values, entry.key: value};
                }),
              ),
          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(
                _validationError!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
          if (_submitError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(
                _submitError!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
          const VerticalSpace(10),
          if (pending && activity.requestId != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChatActionButton(
                  label: 'Cancel',
                  enabled: !widget.busy && !_submitting,
                  onPressed: () => _resolve('cancel'),
                ),
                ChatActionButton(
                  label: isUrlMode ? 'Decline' : 'Skip',
                  enabled: !widget.busy && !_submitting,
                  onPressed: () => _resolve('decline'),
                ),
                if (isUrlMode)
                  ChatActionButton(
                    label: _submitting ? 'Opening…' : 'Open link',
                    primary: true,
                    enabled: !widget.busy && !_submitting && url != null,
                    onPressed: () async {
                      final opened = await launchUrl(url!, mode: LaunchMode.externalApplication);
                      if (!mounted) return;
                      if (opened) {
                        await _resolve('accept');
                      } else {
                        setState(() => _validationError = 'This link could not be opened on this device.');
                      }
                    },
                  )
                else
                  ChatActionButton(
                    label: _submitting ? 'Sending…' : 'Continue',
                    primary: true,
                    enabled: !widget.busy && !_submitting,
                    onPressed: () => _submit(schema),
                  ),
              ],
            )
          else if (pending)
            const PartialNote(
              warning: true,
              text: 'This request has no provider identity, so Operator cannot answer it safely. '
                  'Open diagnostics on the host.',
            )
          else
            const PartialNote(text: 'Already answered. This card is kept for the record.'),
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.name,
    required this.property,
    required this.required,
    required this.value,
    required this.onChanged,
  });

  final String name;
  final InputPropertyModel property;
  final bool required;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final label = '${property.title ?? humanizeInputName(name)}${required ? ' *' : ''}';

    if (property.type == 'boolean') {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Expanded(child: AppText(label, style: AppTextStyle.style12SemiBold)),
            Switch(value: value == true, activeThumbColor: skin.blue, onChanged: onChanged),
          ],
        ),
      );
    }

    final options = inputOptions(property);
    if (options.isNotEmpty) {
      final multi = property.type == 'array';
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(label, style: AppTextStyle.style12SemiBold),
            if (property.description != null)
              AppText(
                property.description!,
                style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
                maxLines: 3,
              ),
            const VerticalSpace(6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in options)
                  ChatActionButton(
                    label: choice.label,
                    hint: choice.description,
                    primary: multi
                        ? (value is List && (value as List).contains(choice.value))
                        : value == choice.value,
                    onPressed: () => onChanged(
                      multi
                          ? toggleInputValue(value is List ? value as List<dynamic> : const [], choice.value)
                          : choice.value,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    final numeric = property.type == 'number' || property.type == 'integer';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(label, style: AppTextStyle.style12SemiBold),
          if (property.description != null)
            AppText(
              property.description!,
              style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
              maxLines: 3,
            ),
          const VerticalSpace(6),
          TextField(
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            maxLength: property.maxLength,
            style: AppTextStyle.style14Regular.copyWith(color: skin.textPrimary),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: skin.bgElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: skin.borderDefault),
              ),
            ),
            onChanged: (text) =>
                onChanged(numeric ? (text.isEmpty ? '' : num.tryParse(text) ?? text) : text),
          ),
        ],
      ),
    );
  }
}
```

`activeThumbColor` is the Flutter 3.44 name for `Switch`'s selected thumb color; if the analyzer
reports it as undefined on this SDK, use `activeColor` — the two differ only by version, and the
project pins Flutter 3.44.5 in `.github/workflows/mobile-flutter.yml`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/request_cards_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 542/542 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add approval and elicitation cards"
```

---

### Task 22: The timeline

**Files:**
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_row.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/file_change_list.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/plan_card.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/turn_summary.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/timeline_item.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_timeline_test.dart`

**Interfaces:**
- Consumes: Task 13's timeline model, Task 20's widgets, Task 4's `commandOutputText`/`caretNotation`.
- Produces:
  - `class ActivityMeta` — `icon (IconData)`, `prefix (String?)`, `Color color(AppSkin, ConversationActivityModel)`
    and `ActivityMeta activityMeta(ConversationActivityModel)`
  - `List<TimelineRow> activityRuns(List<ConversationItemModel> items)` and
    `sealed class TimelineRow` with `SingleRow(item)` / `ActivitiesRow(key, activities)`
  - `String summarizeActivities(List<ConversationActivityModel>)`
  - widgets `ActivityRowWidget`, `ActivityRunWidget`, `FileChangeList`, `PlanCard`, `TurnPlanCard`,
    `ChangedFilesCard`, `TurnSummary`, `TimelineItem`, `ChatTimeline`

`activityRuns` collapses consecutive mechanics into one summarized row so agent prose stays the
visual hierarchy. Approvals, elicitations, errors, file changes, reasoning and anything carrying a
`detail.event` are never folded — those are the rows a person must actually see.

`ChatTimeline` uses a `ListView.builder` over `groupConversationByTurn`, a `GlobalKey` per group so
the conversation map can `Scrollable.ensureVisible` a specific exchange, and a tail-follow rule: it
auto-scrolls to the bottom while the user is within 120 logical pixels of it, and shows a "Latest"
button otherwise. That is the same threshold RN uses.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_timeline_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart';

ConversationSnapshotModel snapshot({
  List<ConversationItemModel> items = const [],
  List<ConversationTurnModel> turns = const [],
  bool hasMoreBefore = false,
  List<String> capabilities = const [],
}) =>
    ConversationSnapshotModel(
      conversationId: 'c-1',
      sessionId: 'w-1',
      harness: 'codex',
      controllerState: 'ready',
      latestSequence: 9,
      hasMoreBefore: hasMoreBefore,
      items: items,
      turns: turns,
      capabilities: capabilities,
    );

Future<void> pumpTimeline(WidgetTester tester, ConversationSnapshotModel value) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: Scaffold(
            body: ChatTimeline(
              snapshot: value,
              loadingOlder: false,
              onLoadOlder: () {},
              approvalPending: false,
              inputPending: false,
              onDecide: (_, __) async {},
              onResolveInput: (_, __, [___]) async {},
              onRollback: (_) async => 0,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('invites the first message on an empty conversation', (tester) async {
    await pumpTimeline(tester, snapshot());
    expect(find.text('Start the conversation'), findsOneWidget);
  });

  testWidgets('renders a human message and an assistant answer differently', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(items: const [
        ConversationMessageModel(
            id: 'u1', sequence: 1, revision: 1, role: 'user', origin: 'human', text: 'do the thing'),
        ConversationMessageModel(
            id: 'a1', sequence: 2, revision: 1, role: 'assistant', origin: 'provider', text: 'Done.'),
      ]),
    );

    expect(find.text('do the thing'), findsOneWidget);
    expect(find.text('Done.'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('warns about an unconfirmed delivery', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(items: const [
        ConversationMessageModel(
          id: 'u1',
          sequence: 1,
          revision: 1,
          role: 'user',
          origin: 'human',
          text: 'hi',
          delivery: 'uncertain',
        ),
      ]),
    );
    expect(find.textContaining('Delivery unconfirmed'), findsOneWidget);
  });

  testWidgets('summarizes a run of mechanics instead of listing each one', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(items: [
        for (var index = 1; index <= 3; index++)
          ConversationActivityModel(
            id: 'c$index',
            turnId: 't1',
            sequence: index,
            revision: 1,
            activityKind: 'command',
            status: 'completed',
            summary: 'cat file$index.dart',
            detail: ActivityDetailModel({'command': 'cat file$index.dart'}),
          ),
      ]),
    );

    expect(find.text('Explored 3 files'), findsOneWidget);
    expect(find.textContaining('cat file1.dart'), findsNothing);
  });

  testWidgets('expands a failed activity by default', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(items: [
        ConversationActivityModel(
          id: 'c1',
          turnId: 't1',
          sequence: 1,
          revision: 1,
          activityKind: 'command',
          status: 'failed',
          summary: 'npm test',
          detail: ActivityDetailModel(const {'command': 'npm test', 'output': 'boom'}),
        ),
      ]),
    );
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('shows a turn plan with its progress count', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(
        items: const [
          ConversationMessageModel(id: 'u1', turnId: 't1', sequence: 1, revision: 1, role: 'user', text: 'go'),
        ],
        turns: const [
          ConversationTurnModel(
            id: 't1',
            state: 'completed',
            requestedAt: '2026-08-05T00:00:00Z',
            planSteps: [
              PlanStepModel(text: 'Read the code', status: 'completed'),
              PlanStepModel(text: 'Change it', status: 'pending'),
            ],
          ),
        ],
      ),
    );

    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
  });

  testWidgets('offers rollback only when the daemon allows it', (tester) async {
    const turn = ConversationTurnModel(
      id: 't1',
      state: 'completed',
      providerTurnId: 'p1',
      requestedAt: '2026-08-05T00:00:00Z',
    );
    const item = ConversationMessageModel(
        id: 'u1', turnId: 't1', sequence: 1, revision: 1, role: 'user', text: 'go');

    await pumpTimeline(tester, snapshot(items: const [item], turns: const [turn]));
    expect(find.byIcon(Icons.settings_backup_restore), findsNothing);

    await pumpTimeline(
      tester,
      snapshot(items: const [item], turns: const [turn], capabilities: const ['rollback']),
    );
    expect(find.byIcon(Icons.settings_backup_restore), findsOneWidget);
  });

  testWidgets('offers to load earlier messages only when there are any', (tester) async {
    await pumpTimeline(tester, snapshot(hasMoreBefore: true));
    expect(find.text('Load earlier messages'), findsOneWidget);
  });

  test('summarizes activity categories the way the desktop does', () {
    ConversationActivityModel command(String summary) => ConversationActivityModel(
          id: summary,
          sequence: 1,
          revision: 1,
          activityKind: 'command',
          status: 'completed',
          summary: summary,
        );

    expect(summarizeActivities([command('cat a'), command('rg foo')]), 'Explored 1 file, 1 search');
    expect(summarizeActivities([command('git status')]), 'Ran 1 git check');
    expect(summarizeActivities([command('npm test')]), 'Ran 1 command');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_timeline_test.dart`
Expected: FAIL — the timeline widgets do not exist.

- [ ] **Step 3: Write the activity metadata and run grouping**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';

const Set<String> _readCommands = {'cat', 'sed', 'nl', 'head', 'tail', 'bat', 'less', 'more', 'wc', 'jq'};
const Set<String> _searchCommands = {'rg', 'grep', 'find', 'fd', 'ls', 'tree', 'glob', 'ag'};

class ActivityMeta {
  const ActivityMeta({required this.icon, required this.color, this.prefix});

  final IconData icon;
  final String? prefix;
  final Color Function(AppSkin skin) color;
}

ActivityMeta activityMeta(ConversationActivityModel activity) {
  switch (activity.activityKind) {
    case 'command':
      return ActivityMeta(
        icon: Icons.terminal,
        color: (skin) => activity.status == 'failed' ? skin.red : skin.textTertiary,
      );
    case 'file_change':
      return ActivityMeta(icon: Icons.edit_outlined, prefix: 'Changed', color: (skin) => skin.blue);
    case 'mcp_tool':
      return ActivityMeta(
        icon: Icons.build_outlined,
        prefix: activity.detail?.server != null ? '${activity.detail!.server} ·' : 'MCP ·',
        color: (skin) => skin.purple,
      );
    case 'auto_review':
      return ActivityMeta(icon: Icons.shield_outlined, prefix: 'Reviewed', color: (skin) => skin.green);
    default:
      return ActivityMeta(icon: Icons.bolt_outlined, color: (skin) => skin.textTertiary);
  }
}

String summarizeActivities(List<ConversationActivityModel> activities) {
  var reads = 0;
  var searches = 0;
  var vcs = 0;
  var commands = 0;
  var tools = 0;
  var reviews = 0;
  var plans = 0;

  for (final activity in activities) {
    switch (activity.activityKind) {
      case 'mcp_tool':
        tools++;
        continue;
      case 'auto_review':
        reviews++;
        continue;
      case 'plan':
        plans++;
        continue;
    }
    switch (_commandCategory(activity.detail?.command ?? activity.summary)) {
      case 'read':
        reads++;
      case 'search':
        searches++;
      case 'vcs':
        vcs++;
      default:
        commands++;
    }
  }

  final parts = <String>[
    if (reads > 0) '$reads ${reads == 1 ? 'file' : 'files'}',
    if (searches > 0) '$searches ${searches == 1 ? 'search' : 'searches'}',
    if (vcs > 0) '$vcs git ${vcs == 1 ? 'check' : 'checks'}',
    if (commands > 0) '$commands ${commands == 1 ? 'command' : 'commands'}',
    if (tools > 0) '$tools tool ${tools == 1 ? 'call' : 'calls'}',
    if (reviews > 0) '$reviews auto-${reviews == 1 ? 'decision' : 'decisions'}',
    if (plans > 0) 'updated plan',
  ];

  final verb = reads > 0 || searches > 0 ? 'Explored' : 'Ran';
  return '$verb ${parts.isEmpty ? '${activities.length} steps' : parts.join(', ')}';
}

String _commandCategory(String text) {
  final head = text.trim().split(RegExp(r'\s+')).first;
  final binary = head.substring(head.lastIndexOf('/') + 1);
  if (_readCommands.contains(binary)) return 'read';
  if (_searchCommands.contains(binary)) return 'search';
  if (binary == 'git' || binary == 'gh') return 'vcs';
  return 'run';
}
```

- [ ] **Step 4: Write the activity rows**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_row.dart` — the
expandable generic row, the MCP tool row, and the auto-review row:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/logic/ansi.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/file_change_list.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/plan_card.dart';

String printable(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

class ActivityRowWidget extends StatelessWidget {
  const ActivityRowWidget({super.key, required this.activity});

  final ConversationActivityModel activity;

  @override
  Widget build(BuildContext context) {
    switch (activity.activityKind) {
      case 'mcp_tool':
        return _McpToolRow(activity: activity);
      case 'auto_review':
        return _AutoReviewRow(activity: activity);
      case 'file_change':
        return FileChangeActivity(activity: activity);
      case 'plan':
        return PlanCard(activity: activity);
      default:
        return _GenericActivityRow(activity: activity);
    }
  }
}

class _GenericActivityRow extends StatefulWidget {
  const _GenericActivityRow({required this.activity});

  final ConversationActivityModel activity;

  @override
  State<_GenericActivityRow> createState() => _GenericActivityRowState();
}

class _GenericActivityRowState extends State<_GenericActivityRow> {
  bool? _override;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final activity = widget.activity;
    final detail = activity.detail;
    final output = commandOutputText(
      detail?.output ?? detail?.result ?? detail?.error ?? detail?.patchOutput,
    );
    final open = _override ?? activityStartsExpanded(activity);
    final expandable = output.isNotEmpty ||
        detail?.cwd != null ||
        detail?.arguments != null ||
        detail?.files != null ||
        detail?.reason != null ||
        detail?.text != null ||
        detail?.terminalInput != null;
    final meta = activityMeta(activity);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: expandable ? () => setState(() => _override = !open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(meta.icon, size: 13, color: meta.color(skin)),
                  const HorizontalSpace(8),
                  Expanded(
                    child: AppText(
                      '${meta.prefix == null ? '' : '${meta.prefix} '}'
                      '${detail?.command ?? detail?.toolName ?? activity.summary}',
                      style: AppTextStyle.mono12Regular.copyWith(
                        color: activity.status == 'failed' ? skin.red : skin.textSecondary,
                      ),
                      maxLines: open ? 6 : 2,
                    ),
                  ),
                  if (activity.status == 'running')
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: skin.orange),
                    )
                  else if (activity.status == 'cancelled')
                    AppText('stopped', style: AppTextStyle.style10Regular.copyWith(color: skin.textFaint)),
                  if (expandable)
                    Icon(open ? Icons.expand_less : Icons.chevron_right, size: 15, color: skin.textFaint),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(left: 21, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (detail?.cwd != null) LabelValue(label: 'cwd', value: detail!.cwd!),
                  if (detail?.reason != null || detail?.text != null)
                    AppText(
                      detail!.reason ?? detail.text!,
                      style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                      maxLines: 12,
                    ),
                  if (detail?.arguments != null) CodeOutput(value: printable(detail!.arguments)),
                  if (detail?.terminalInput != null) ...[
                    const VerticalSpace(6),
                    const DetailLabel(label: 'agent typed'),
                    CodeOutput(value: caretNotation(detail!.terminalInput!)),
                    if (detail.terminalInputTruncated)
                      const PartialNote(text: 'Operator stopped recording keystrokes at its cap; more were sent.'),
                  ],
                  if (output.isNotEmpty) CodeOutput(value: output),
                  if (detail?.outputTruncated == true || detail?.patchOutputTruncated == true)
                    const PartialNote(
                      warning: true,
                      text: 'This output is longer than Operator stores, so it stops early. '
                          'Open the worktree shell for the full run.',
                    )
                  else if (detail?.outputMayBePartial == true)
                    PartialNote(
                      text: '${detail!.outputSource == 'stream' ? 'Streamed live; the provider may have omitted the beginning.' : "The provider's rolled-up output may omit the beginning."}'
                          ' Open the worktree shell for the full run.',
                    ),
                  if (detail?.files is List) FileNameList(files: detail!.files as List<dynamic>),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _McpToolRow extends StatefulWidget {
  const _McpToolRow({required this.activity});

  final ConversationActivityModel activity;

  @override
  State<_McpToolRow> createState() => _McpToolRowState();
}

class _McpToolRowState extends State<_McpToolRow> {
  late bool _open = widget.activity.status == 'failed';

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final detail = widget.activity.detail;
    final failed = widget.activity.status == 'failed' || detail?.success == false || detail?.error != null;
    final body = detail?.arguments != null ||
        detail?.result != null ||
        detail?.error != null ||
        detail?.progress != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: body ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(Icons.build_outlined, size: 13, color: failed ? skin.red : skin.purple),
                  const HorizontalSpace(8),
                  if (detail?.server != null || detail?.namespace != null)
                    AppText(
                      '${detail!.server ?? detail.namespace}/',
                      style: AppTextStyle.mono11Regular.copyWith(color: skin.purple),
                    ),
                  Expanded(
                    child: AppText(
                      detail?.toolName ?? widget.activity.summary,
                      style: AppTextStyle.mono12Regular.copyWith(color: failed ? skin.red : skin.textSecondary),
                    ),
                  ),
                  if (body)
                    Icon(_open ? Icons.expand_less : Icons.chevron_right, size: 15, color: skin.textFaint),
                ],
              ),
            ),
          ),
          if (_open && body)
            Padding(
              padding: const EdgeInsets.only(left: 21, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (detail?.error != null)
                    AppText(
                      detail!.error!,
                      style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                      maxLines: 6,
                    ),
                  if (detail?.arguments != null) ...[
                    const DetailLabel(label: 'arguments'),
                    CodeOutput(value: printable(detail!.arguments)),
                  ],
                  if (detail?.result != null) ...[
                    const DetailLabel(label: 'result'),
                    CodeOutput(value: printable(detail!.result)),
                  ],
                  if (detail?.progress != null) ...[
                    const DetailLabel(label: 'progress'),
                    CodeOutput(value: detail!.progress!),
                    if (detail.progressTruncated)
                      const PartialNote(text: 'Progress was longer than Operator stores.'),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AutoReviewRow extends StatefulWidget {
  const _AutoReviewRow({required this.activity});

  final ConversationActivityModel activity;

  @override
  State<_AutoReviewRow> createState() => _AutoReviewRowState();
}

class _AutoReviewRowState extends State<_AutoReviewRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final detail = widget.activity.detail;
    final denied = (detail?.status ?? '').toLowerCase().contains('den');
    final paths = _reviewPaths(detail?.files);
    final body = detail?.rationale != null ||
        detail?.command != null ||
        detail?.cwd != null ||
        detail?.host != null ||
        detail?.decisionSource != null ||
        paths.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: body ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(denied ? Icons.gpp_bad_outlined : Icons.verified_user_outlined,
                      size: 13, color: denied ? skin.red : skin.green),
                  const HorizontalSpace(8),
                  AppText(
                    denied ? 'Auto-declined' : 'Auto-approved',
                    style: AppTextStyle.style11SemiBold.copyWith(color: denied ? skin.red : skin.green),
                  ),
                  const HorizontalSpace(8),
                  Expanded(
                    child: AppText(
                      widget.activity.summary,
                      style: AppTextStyle.mono12Regular.copyWith(color: skin.textSecondary),
                    ),
                  ),
                  if (detail?.riskLevel != null)
                    AppText(
                      detail!.riskLevel!,
                      style: AppTextStyle.style10Regular.copyWith(
                        color: ['high', 'critical'].contains(detail.riskLevel!.toLowerCase())
                            ? skin.red
                            : skin.textFaint,
                      ),
                    ),
                  if (body)
                    Icon(_open ? Icons.expand_less : Icons.chevron_right, size: 15, color: skin.textFaint),
                ],
              ),
            ),
          ),
          if (_open && body)
            Padding(
              padding: const EdgeInsets.only(left: 21, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    denied
                        ? 'The provider declined this on your behalf. You were not asked.'
                        : 'The provider allowed this on your behalf. You were not asked.',
                    style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                    maxLines: 3,
                  ),
                  if (detail?.rationale != null)
                    AppText(
                      detail!.rationale!,
                      style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
                      maxLines: 6,
                    ),
                  if (detail?.command != null) LabelValue(label: 'cmd', value: detail!.command!),
                  if (detail?.cwd != null) LabelValue(label: 'cwd', value: detail!.cwd!),
                  if (detail?.host != null) LabelValue(label: 'host', value: detail!.host!),
                  if (paths.isNotEmpty) LabelValue(label: 'files', value: paths.join(', ')),
                  if (detail?.decisionSource != null) LabelValue(label: 'by', value: detail!.decisionSource!),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<String> _reviewPaths(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((entry) => entry is String
            ? entry
            : entry is Map && entry['path'] is String
                ? entry['path'] as String
                : null)
        .whereType<String>()
        .toList();
  }
}
```

- [ ] **Step 5: Write the file-change, plan and turn-summary widgets**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/file_change_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/highlighted_code_text.dart';

class FileChangeActivity extends StatefulWidget {
  const FileChangeActivity({super.key, required this.activity});

  final ConversationActivityModel activity;

  @override
  State<FileChangeActivity> createState() => _FileChangeActivityState();
}

class _FileChangeActivityState extends State<FileChangeActivity> {
  bool? _override;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final detail = widget.activity.detail;
    final files = DiffFileModel.listFrom(detail?.files);
    final fallbackPatch = detail?.patchOutput;
    final live = widget.activity.status == 'running';
    final open = _override ?? (live && (fallbackPatch != null || files.any((file) => file.patch != null)));
    final expandable = files.isNotEmpty || fallbackPatch != null;
    final title = widget.activity.summary.isNotEmpty
        ? widget.activity.summary
        : '${files.length} changed ${files.length == 1 ? 'file' : 'files'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: expandable ? () => setState(() => _override = !open) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 13, color: skin.blue),
                const HorizontalSpace(8),
                Expanded(
                  child: AppText(title, style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary)),
                ),
                if (expandable)
                  Icon(open ? Icons.expand_less : Icons.chevron_right, size: 15, color: skin.textFaint),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 21, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final file in files) FileChangeRow(file: file, live: live),
                if (fallbackPatch != null)
                  PatchBlock(patch: fallbackPatch, truncated: detail!.patchOutputTruncated),
              ],
            ),
          ),
      ],
    );
  }
}

class FileChangeRow extends StatefulWidget {
  const FileChangeRow({super.key, required this.file, this.live = false});

  final DiffFileModel file;
  final bool live;

  @override
  State<FileChangeRow> createState() => _FileChangeRowState();
}

class _FileChangeRowState extends State<FileChangeRow> {
  late bool _open = widget.live && widget.file.patch != null;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final file = widget.file;
    final mark = switch (file.status) {
      'added' => 'A',
      'deleted' => 'D',
      'renamed' => 'R',
      _ => 'M',
    };
    final color = switch (file.status) {
      'deleted' => skin.red,
      'added' => skin.green,
      _ => skin.blue,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: file.patch == null ? null : () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                AppText(mark, style: AppTextStyle.mono11Bold.copyWith(color: color)),
                const HorizontalSpace(8),
                Expanded(
                  child: AppText(
                    file.oldPath == null ? file.path : '${file.oldPath} → ${file.path}',
                    style: AppTextStyle.mono11Regular.copyWith(color: skin.textSecondary),
                    maxLines: 2,
                  ),
                ),
                AppText(
                  '+${file.additions} −${file.deletions}',
                  style: AppTextStyle.mono10Regular.copyWith(color: skin.textFaint),
                ),
                if (file.patch != null)
                  Icon(_open ? Icons.expand_less : Icons.chevron_right, size: 13, color: skin.textFaint),
              ],
            ),
          ),
        ),
        if (_open && file.patch != null) PatchBlock(patch: file.patch!, truncated: file.patchTruncated),
      ],
    );
  }
}

class PatchBlock extends StatelessWidget {
  const PatchBlock({super.key, required this.patch, this.truncated = false});

  final String patch;
  final bool truncated;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: () => Clipboard.setData(ClipboardData(text: patch)),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: skin.bgColumn, borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: HighlightedCodeText(code: patch, language: 'diff', style: AppTextStyle.mono11Regular),
            ),
          ),
        ),
        if (truncated)
          const PartialNote(
            warning: true,
            text: 'This patch is longer than Operator stores. The complete change remains in the worktree.',
          ),
      ],
    );
  }
}

class FileNameList extends StatelessWidget {
  const FileNameList({super.key, required this.files});

  final List<dynamic> files;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final file in files)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: AppText(
                '• ${file is String ? file : file.toString()}',
                style: AppTextStyle.mono11Regular.copyWith(color: context.skin.textSecondary),
                maxLines: 2,
              ),
            ),
        ],
      );
}
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/plan_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';

class PlanCard extends StatefulWidget {
  const PlanCard({super.key, required this.activity});

  final ConversationActivityModel activity;

  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  late bool _open = widget.activity.status == 'running';

  @override
  Widget build(BuildContext context) {
    final detail = widget.activity.detail;
    return PlanShell(
      title: widget.activity.summary.isEmpty ? 'Plan updated' : widget.activity.summary,
      steps: detail?.steps ?? const [],
      explanation: detail?.explanation,
      emptyFallback: detail?.text ?? widget.activity.summary,
      open: _open,
      onToggle: () => setState(() => _open = !_open),
    );
  }
}

class PlanShell extends StatelessWidget {
  const PlanShell({
    super.key,
    required this.title,
    required this.steps,
    required this.open,
    required this.onToggle,
    this.explanation,
    this.emptyFallback,
    this.liveLabel,
  });

  final String title;
  final List<PlanStepModel> steps;
  final bool open;
  final VoidCallback onToggle;
  final String? explanation;
  final String? emptyFallback;
  final String? liveLabel;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final done = steps.where((step) => step.status == 'completed').length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  Icon(Icons.checklist, size: 13, color: skin.textTertiary),
                  const HorizontalSpace(8),
                  Expanded(child: AppText(title, style: AppTextStyle.style12SemiBold)),
                  if (liveLabel != null) ...[
                    AppText(liveLabel!, style: AppTextStyle.style9Bold.copyWith(color: skin.orange)),
                    const HorizontalSpace(8),
                  ],
                  AppText(
                    '$done/${steps.length}',
                    style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more, size: 15, color: skin.textTertiary),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (explanation != null)
                    AppText(
                      explanation!,
                      style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                      maxLines: 8,
                    ),
                  for (final step in steps)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            step.status == 'completed' ? Icons.check_circle : Icons.circle_outlined,
                            size: 14,
                            color: step.status == 'completed'
                                ? skin.green
                                : step.status == 'in_progress'
                                    ? skin.orange
                                    : skin.textFaint,
                          ),
                          const HorizontalSpace(8),
                          Expanded(
                            child: AppText(
                              step.text,
                              style: AppTextStyle.style13Regular.copyWith(
                                color: step.status == 'completed' ? skin.textTertiary : skin.textPrimary,
                                decoration: step.status == 'completed'
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                              maxLines: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (steps.isEmpty && emptyFallback != null)
                    AppText(
                      emptyFallback!,
                      style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                      maxLines: 6,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/turn_summary.dart` — the
turn's plan, changed files, state line and rollback confirmation:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/file_change_list.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/plan_card.dart';

class TurnSummary extends StatefulWidget {
  const TurnSummary({super.key, required this.turn, this.onRollback});

  final ConversationTurnModel turn;
  final Future<int> Function(String turnId)? onRollback;

  @override
  State<TurnSummary> createState() => _TurnSummaryState();
}

class _TurnSummaryState extends State<TurnSummary> {
  bool _planOpen = false;
  bool _filesOpen = false;
  bool _confirming = false;
  bool _rollingBack = false;
  String? _rollbackError;

  @override
  void initState() {
    super.initState();
    _planOpen = widget.turn.state == 'running';
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final turn = widget.turn;
    final duration = _elapsed(turn.startedAt ?? turn.requestedAt, turn.completedAt);
    final settled = !turn.isInFlight;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (turn.hasPlan)
            PlanShell(
              title: 'Plan',
              steps: turn.planSteps,
              explanation: turn.planExplanation,
              open: _planOpen,
              liveLabel: turn.state == 'running' ? 'STILL CHANGING' : null,
              onToggle: () => setState(() => _planOpen = !_planOpen),
            ),
          if (turn.diffFiles.isNotEmpty) _changedFiles(context),
          Row(
            children: [
              Expanded(child: Container(height: 1, color: skin.borderSubtle)),
              const HorizontalSpace(10),
              AppText(
                turn.rolledBack ? 'ROLLED BACK' : (turn.state ?? '').toUpperCase(),
                style: AppTextStyle.style9Bold.copyWith(
                  color: turn.state == 'failed' ? skin.red : skin.textFaint,
                  letterSpacing: 0.8,
                ),
              ),
              if (duration != null) ...[
                const HorizontalSpace(8),
                AppText(duration, style: AppTextStyle.mono10Regular.copyWith(color: skin.textFaint)),
              ],
              if (widget.onRollback != null && settled && turn.providerTurnId != null && !turn.rolledBack) ...[
                const HorizontalSpace(8),
                InkWell(
                  onTap: () => setState(() => _confirming = true),
                  child: Icon(Icons.settings_backup_restore, size: 15, color: skin.textTertiary),
                ),
              ],
              const HorizontalSpace(10),
              Expanded(child: Container(height: 1, color: skin.borderSubtle)),
            ],
          ),
          if (turn.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: AppText(
                turn.errorMessage!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                maxLines: 6,
              ),
            ),
          if (_confirming) _confirmation(context),
        ],
      ),
    );
  }

  Widget _changedFiles(BuildContext context) {
    final skin = context.skin;
    final turn = widget.turn;
    final additions = turn.diffFiles.fold<int>(0, (sum, file) => sum + file.additions);
    final deletions = turn.diffFiles.fold<int>(0, (sum, file) => sum + file.deletions);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _filesOpen = !_filesOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 13, color: skin.textTertiary),
                  const HorizontalSpace(8),
                  Expanded(
                    child: AppText(
                      '${turn.diffFiles.length} changed ${turn.diffFiles.length == 1 ? 'file' : 'files'}',
                      style: AppTextStyle.style12SemiBold,
                    ),
                  ),
                  if (turn.state == 'running')
                    AppText('GROWING', style: AppTextStyle.style9Bold.copyWith(color: skin.orange)),
                  const HorizontalSpace(8),
                  AppText('+$additions', style: AppTextStyle.mono11Regular.copyWith(color: skin.green)),
                  const HorizontalSpace(5),
                  AppText('−$deletions', style: AppTextStyle.mono11Regular.copyWith(color: skin.red)),
                  Icon(_filesOpen ? Icons.expand_less : Icons.expand_more, size: 15, color: skin.textTertiary),
                ],
              ),
            ),
          ),
          if (_filesOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final file in turn.diffFiles) FileChangeRow(file: file),
                  if (turn.diffTruncated)
                    const PartialNote(
                      warning: true,
                      text: 'This turn changed more files than Operator lists here. '
                          'Open the worktree shell for the complete diff.',
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _confirmation(BuildContext context) {
    final skin = context.skin;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: skin.borderDefault),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            'Make the agent forget this turn and everything after it?',
            style: AppTextStyle.style13SemiBold,
            maxLines: 3,
          ),
          const VerticalSpace(4),
          AppText(
            'Files stay changed. Only conversation memory is rolled back, and this cannot be undone.',
            style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
            maxLines: 3,
          ),
          const VerticalSpace(10),
          Row(
            children: [
              ChatActionButton(
                label: 'Cancel',
                enabled: !_rollingBack,
                onPressed: () => setState(() {
                  _rollbackError = null;
                  _confirming = false;
                }),
              ),
              const HorizontalSpace(8),
              ChatActionButton(
                label: _rollingBack ? 'Rolling back…' : 'Roll back',
                danger: true,
                enabled: !_rollingBack,
                onPressed: () async {
                  setState(() {
                    _rollingBack = true;
                    _rollbackError = null;
                  });
                  try {
                    await widget.onRollback!(widget.turn.id);
                    if (mounted) setState(() => _confirming = false);
                  } catch (error) {
                    if (mounted) setState(() => _rollbackError = error.toString());
                  } finally {
                    if (mounted) setState(() => _rollingBack = false);
                  }
                },
              ),
            ],
          ),
          if (_rollbackError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(
                _rollbackError!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
        ],
      ),
    );
  }

  String? _elapsed(String? start, String? end) {
    if (start == null || end == null) return null;
    final from = DateTime.tryParse(start);
    final to = DateTime.tryParse(end);
    if (from == null || to == null) return null;
    final seconds = to.difference(from).inSeconds;
    if (seconds < 0) return null;
    return seconds < 60 ? '${seconds}s' : '${seconds ~/ 60}m ${seconds % 60}s';
  }
}
```

- [ ] **Step 6: Write the run grouping, the item renderer and the list**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart` — the
collapsed run, its subagent tree, and `activityRuns`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_row.dart';

export 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart'
    show summarizeActivities;

sealed class TimelineRow {
  const TimelineRow(this.key);

  final String key;
}

final class SingleRow extends TimelineRow {
  const SingleRow(super.key, this.item);

  final ConversationItemModel item;
}

final class ActivitiesRow extends TimelineRow {
  ActivitiesRow(super.key, this.activities);

  final List<ConversationActivityModel> activities;
}

List<TimelineRow> activityRuns(List<ConversationItemModel> items) {
  final rows = <TimelineRow>[];
  for (final item in items) {
    final runnable = item is ConversationActivityModel &&
        item.activityKind != 'approval' &&
        item.activityKind != 'user_input' &&
        item.activityKind != 'error' &&
        item.activityKind != 'file_change' &&
        item.activityKind != 'reasoning' &&
        item.detail?.event == null;
    final previous = rows.isEmpty ? null : rows.last;

    if (runnable && previous is ActivitiesRow && previous.activities.first.turnId == item.turnId) {
      previous.activities.add(item);
    } else if (runnable) {
      rows.add(ActivitiesRow('run-${item.sequence}', [item]));
    } else {
      rows.add(SingleRow(item.itemKey, item));
    }
  }
  return rows;
}

class ActivityRunWidget extends StatefulWidget {
  const ActivityRunWidget({super.key, required this.activities});

  final List<ConversationActivityModel> activities;

  @override
  State<ActivityRunWidget> createState() => _ActivityRunWidgetState();
}

class _ActivityRunWidgetState extends State<ActivityRunWidget> {
  bool? _override;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final hierarchy = activityHierarchy(widget.activities);
    if (widget.activities.length == 1 && hierarchy.first.children.isEmpty) {
      return ActivityRowWidget(activity: widget.activities.single);
    }

    final running = widget.activities.any((activity) => activity.status == 'running');
    final failed = widget.activities.where((activity) => activity.status == 'failed').length;
    final cancelled = widget.activities.where((activity) => activity.status == 'cancelled').length;
    final streaming = widget.activities
        .any((activity) => activity.status == 'running' && activity.detail?.output != null);
    final open = _override ?? streaming;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _override = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: AppText(
                      summarizeActivities(widget.activities),
                      style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
                    ),
                  ),
                  if (failed > 0)
                    AppText('$failed failed', style: AppTextStyle.style10Regular.copyWith(color: skin.red)),
                  if (cancelled > 0)
                    AppText('$cancelled stopped',
                        style: AppTextStyle.style10Regular.copyWith(color: skin.textFaint)),
                  if (running)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: skin.textTertiary),
                    ),
                  Icon(open ? Icons.expand_more : Icons.chevron_right, size: 15, color: skin.textFaint),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final node in hierarchy) _ActivityTree(node: node)],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityTree extends StatelessWidget {
  const _ActivityTree({required this.node});

  final ActivityNode node;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActivityRowWidget(activity: node.activity),
          if (node.children.isNotEmpty) _NestedAgentRun(nodes: node.children),
        ],
      );
}

class _NestedAgentRun extends StatefulWidget {
  const _NestedAgentRun({required this.nodes});

  final List<ActivityNode> nodes;

  @override
  State<_NestedAgentRun> createState() => _NestedAgentRunState();
}

class _NestedAgentRunState extends State<_NestedAgentRun> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final count = countActivityNodes(widget.nodes);
    final running = activityNodesRunning(widget.nodes);

    return Container(
      margin: const EdgeInsets.only(left: 12, top: 2),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: skin.borderSubtle))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(Icons.account_tree_outlined, size: 12, color: skin.textTertiary),
                  const HorizontalSpace(6),
                  Expanded(
                    child: AppText(
                      'SUBAGENT · $count ${count == 1 ? 'STEP' : 'STEPS'}',
                      style: AppTextStyle.style9Bold.copyWith(color: skin.textTertiary, letterSpacing: 0.7),
                    ),
                  ),
                  if (running)
                    SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: skin.textTertiary),
                    ),
                  Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 12, color: skin.textFaint),
                ],
              ),
            ),
          ),
          if (_open)
            for (final child in widget.nodes) _ActivityTree(node: child),
        ],
      ),
    );
  }
}
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/timeline_item.dart` — one
conversation row: user bubble, origin report, assistant prose, system signals, or an activity. It
delegates approvals and elicitations to Task 22's cards.

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_row.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/approval_card.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_markdown.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/user_input_card.dart';

class TimelineItem extends StatelessWidget {
  const TimelineItem({
    super.key,
    required this.item,
    required this.approvalPending,
    required this.inputPending,
    required this.onDecide,
    required this.onResolveInput,
  });

  final ConversationItemModel item;
  final bool approvalPending;
  final bool inputPending;
  final Future<void> Function(String requestId, String decisionId) onDecide;
  final Future<void> Function(String requestId, String action, [Map<String, dynamic>? content]) onResolveInput;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    if (item is ConversationMessageModel) {
      final message = item as ConversationMessageModel;
      if (message.role == 'user' && message.origin == 'human') {
        final delivery = _deliveryCopy(message.delivery);
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: skin.bgElevated,
              border: Border.all(color: skin.borderDefault),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(17),
                topRight: Radius.circular(17),
                bottomLeft: Radius.circular(17),
                bottomRight: Radius.circular(5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  message.text,
                  style: AppTextStyle.style16Regular.copyWith(color: skin.textPrimary, height: 1.4),
                ),
                if (delivery != null) ...[
                  const VerticalSpace(5),
                  AppText(delivery, style: AppTextStyle.style10Regular.copyWith(color: skin.amber), maxLines: 2),
                ],
              ],
            ),
          ),
        );
      }
      if (message.role == 'user') return _OriginMessage(message: message);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.senderLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: AppText(
                  message.senderLabel!,
                  style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary),
                ),
              ),
            ChatMarkdown(
              text: message.text.isEmpty && message.streaming ? '…' : message.text,
              streaming: message.streaming,
            ),
            if (!message.streaming && message.text.isNotEmpty)
              InkWell(
                onTap: () => Clipboard.setData(ClipboardData(text: message.text)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_outlined, size: 12, color: skin.textFaint),
                      const HorizontalSpace(5),
                      AppText('Copy', style: AppTextStyle.style10Regular.copyWith(color: skin.textFaint)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final activity = item as ConversationActivityModel;
    if (activity.activityKind == 'approval') {
      return ApprovalCard(activity: activity, busy: approvalPending, onDecide: onDecide);
    }
    if (activity.activityKind == 'user_input') {
      return UserInputCard(activity: activity, busy: inputPending, onResolve: onResolveInput);
    }
    if (activity.activityKind == 'system' && activity.detail?.event == 'compaction') {
      return _CompactionMarker(activity: activity);
    }
    if (activity.activityKind == 'system' && activity.detail?.event == 'steer') {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: skin.tintBlue,
            border: Border.all(color: skin.borderSubtle),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText('STEERED',
                  style: AppTextStyle.style9Bold.copyWith(color: skin.blue, letterSpacing: 1)),
              const VerticalSpace(3),
              SelectableText(
                activity.detail?.text ?? activity.summary,
                style: AppTextStyle.style16Regular.copyWith(color: skin.textPrimary),
              ),
            ],
          ),
        ),
      );
    }
    if (activity.detail?.event == 'model.rerouted') {
      return _SystemSignal(
        icon: Icons.shuffle,
        title: 'Answered by ${activity.detail?.toModel ?? 'another model'}',
        detail: activity.detail?.fromModel != null
            ? 'Instead of ${activity.detail!.fromModel}'
                '${activity.detail!.reason == null ? '' : ' · ${activity.detail!.reason}'}'
            : activity.detail?.reason,
      );
    }
    if (activity.detail?.event == 'auth.reauth_required') {
      return _SystemSignal(
        icon: Icons.key_outlined,
        danger: true,
        title: 'The provider asked you to sign in again',
        detail: activity.detail?.reason,
      );
    }
    if (activity.activityKind == 'error') return _ErrorActivity(activity: activity);
    return ActivityRowWidget(activity: activity);
  }

  String? _deliveryCopy(String? state) {
    switch (state) {
      case 'queued':
        return 'Queued — sends when the agent finishes';
      case 'sending':
        return 'Sending…';
      case 'uncertain':
        return 'Delivery unconfirmed — check the conversation before retrying';
      case 'failed':
        return 'Not sent';
      default:
        return null;
    }
  }
}

class _OriginMessage extends StatefulWidget {
  const _OriginMessage({required this.message});

  final ConversationMessageModel message;

  @override
  State<_OriginMessage> createState() => _OriginMessageState();
}

class _OriginMessageState extends State<_OriginMessage> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final message = widget.message;
    final long = message.text.length > 600;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: skin.borderStrong, width: 2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.podcasts, size: 11, color: skin.textTertiary),
              const HorizontalSpace(5),
              AppText(
                message.senderLabel ?? (message.origin == 'automation' ? 'Automation' : 'Operator'),
                style: AppTextStyle.style10Bold.copyWith(color: skin.textTertiary, letterSpacing: 0.7),
              ),
            ],
          ),
          const VerticalSpace(5),
          if (long && _expanded)
            ChatMarkdown(text: message.text)
          else
            SelectableText(
              message.text,
              maxLines: long ? 5 : null,
              style: AppTextStyle.style14Regular.copyWith(color: skin.textSecondary, height: 1.45),
            ),
          if (long)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_expanded ? Icons.expand_less : Icons.chevron_right, size: 12, color: skin.blue),
                    const HorizontalSpace(4),
                    AppText(
                      _expanded ? 'Hide report' : 'Show full report',
                      style: AppTextStyle.style11SemiBold.copyWith(color: skin.blue),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SystemSignal extends StatelessWidget {
  const _SystemSignal({required this.icon, required this.title, this.detail, this.danger = false});

  final IconData icon;
  final String title;
  final String? detail;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: danger ? skin.red : skin.borderDefault),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: danger ? skin.red : skin.textTertiary),
          const HorizontalSpace(9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  title,
                  style: AppTextStyle.style11SemiBold.copyWith(color: danger ? skin.red : skin.textPrimary),
                  maxLines: 2,
                ),
                if (detail != null)
                  AppText(detail!, style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary), maxLines: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorActivity extends StatelessWidget {
  const _ErrorActivity({required this.activity});

  final ConversationActivityModel activity;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final body = activity.detail?.error ?? activity.detail?.message;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: skin.tintRed),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: skin.red),
          const HorizontalSpace(9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  activity.summary.isEmpty ? 'Agent error' : activity.summary,
                  style: AppTextStyle.style12SemiBold,
                  maxLines: 2,
                ),
                if (body != null)
                  SelectableText(
                    body,
                    style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactionMarker extends StatelessWidget {
  const _CompactionMarker({required this.activity});

  final ConversationActivityModel activity;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final after = activity.detail?.tokensAfter;
    final window = activity.detail?.contextWindow;
    final reclaimed = activity.detail?.tokensReclaimed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: skin.borderSubtle)),
          const HorizontalSpace(10),
          Icon(Icons.archive_outlined, size: 12, color: skin.textFaint),
          const HorizontalSpace(6),
          AppText(
            'HISTORY COMPACTED'
            '${reclaimed == null ? '' : '  −${formatTokens(reclaimed)}'}'
            '${after != null && window != null && window > 0 ? '  ${(after / window * 100).round()}% FULL' : ''}',
            style: AppTextStyle.style9Bold.copyWith(color: skin.textFaint, letterSpacing: 0.8),
          ),
          const HorizontalSpace(10),
          Expanded(child: Container(height: 1, color: skin.borderSubtle)),
        ],
      ),
    );
  }
}

String formatTokens(int value) => value >= 1000
    ? '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k'
    : '$value';
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/timeline_item.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/turn_summary.dart';

class ChatTimeline extends StatefulWidget {
  const ChatTimeline({
    super.key,
    required this.snapshot,
    required this.loadingOlder,
    required this.onLoadOlder,
    required this.approvalPending,
    required this.inputPending,
    required this.onDecide,
    required this.onResolveInput,
    required this.onRollback,
    this.jumpToSequence,
    this.onJumpHandled,
  });

  final ConversationSnapshotModel snapshot;
  final bool loadingOlder;
  final VoidCallback onLoadOlder;
  final bool approvalPending;
  final bool inputPending;
  final Future<void> Function(String requestId, String decisionId) onDecide;
  final Future<void> Function(String requestId, String action, [Map<String, dynamic>? content]) onResolveInput;
  final Future<int> Function(String turnId) onRollback;
  final int? jumpToSequence;
  final VoidCallback? onJumpHandled;

  @override
  State<ChatTimeline> createState() => _ChatTimelineState();
}

class _ChatTimelineState extends State<ChatTimeline> {
  final ScrollController _controller = ScrollController();
  final Map<String, GlobalKey> _anchors = {};
  bool _followsTail = true;
  bool _showJump = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final follows = _controller.position.maxScrollExtent - _controller.offset < 120;
    if (follows != _followsTail) setState(() {
      _followsTail = follows;
      _showJump = !follows;
    });
  }

  @override
  void didUpdateWidget(ChatTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_followsTail) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) _controller.jumpTo(_controller.position.maxScrollExtent);
      });
    }
    final target = widget.jumpToSequence;
    if (target != null && target != oldWidget.jumpToSequence) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(target));
    }
  }

  void _jumpTo(int sequence) {
    final groups = groupConversationByTurn(widget.snapshot);
    for (final group in groups) {
      if (group.anchor != sequence) continue;
      final anchor = _anchors[group.key]?.currentContext;
      if (anchor != null) {
        Scrollable.ensureVisible(anchor, duration: const Duration(milliseconds: 250), alignment: 0.18);
      }
      break;
    }
    widget.onJumpHandled?.call();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final items = readableConversationItems(widget.snapshot);
    final groups = groupConversationByTurn(widget.snapshot, items);

    if (groups.isEmpty) {
      return Container(
        color: skin.bgBase,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: skin.tintBlue, shape: BoxShape.circle),
              child: Icon(Icons.chat_bubble_outline, size: 20, color: skin.blue),
            ),
            const VerticalSpace(12),
            AppText(
              widget.snapshot.controllerState == 'connecting'
                  ? 'Connecting to the agent…'
                  : 'Start the conversation',
              style: AppTextStyle.style17SemiBold,
              maxLines: 2,
            ),
            const VerticalSpace(6),
            AppText(
              'This ${widget.snapshot.harness ?? 'agent'} session works in its own Operator worktree. '
              'Ask it to inspect, change, test, or explain anything there.',
              style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
              textAlign: TextAlign.center,
              maxLines: 4,
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Container(
          color: skin.bgBase,
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            itemCount: groups.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                if (widget.snapshot.hasMoreBefore) {
                  return Center(
                    child: TextButton(
                      onPressed: widget.loadingOlder ? null : widget.onLoadOlder,
                      child: AppText(
                        widget.loadingOlder ? 'Loading history…' : 'Load earlier messages',
                        style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
                      ),
                    ),
                  );
                }
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: AppText(
                      'BEGINNING OF CONVERSATION',
                      style: AppTextStyle.style10Regular.copyWith(color: skin.textFaint, letterSpacing: 1),
                    ),
                  ),
                );
              }

              final group = groups[index - 1];
              final anchor = _anchors.putIfAbsent(group.key, GlobalKey.new);
              return KeyedSubtree(
                key: anchor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in activityRuns(group.items))
                      switch (row) {
                        ActivitiesRow(:final activities) => ActivityRunWidget(activities: activities),
                        SingleRow(:final item) => TimelineItem(
                            item: item,
                            approvalPending: widget.approvalPending,
                            inputPending: widget.inputPending,
                            onDecide: widget.onDecide,
                            onResolveInput: widget.onResolveInput,
                          ),
                      },
                    if (group.turn != null)
                      TurnSummary(
                        turn: group.turn!,
                        onRollback: canRollbackTurn(widget.snapshot, group.turn!) ? widget.onRollback : null,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_showJump)
          Positioned(
            right: 14,
            bottom: 12,
            child: Material(
              color: skin.bgElevated,
              shape: StadiumBorder(side: BorderSide(color: skin.borderStrong)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () {
                  setState(() {
                    _followsTail = true;
                    _showJump = false;
                  });
                  _controller.animateTo(
                    _controller.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_downward, size: 14, color: skin.textPrimary),
                      const HorizontalSpace(6),
                      AppText('Latest', style: AppTextStyle.style11Bold),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_timeline_test.dart`
Expected: PASS. `timeline_item.dart` imports Task 21's `ApprovalCard` and `UserInputCard`; if they
are missing, that task was skipped.

- [ ] **Step 8: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 551/551 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): render the chat timeline"
```

---

### Task 23: The composer

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/attachment_picker.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/suggestion_sheet.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart`
- Modify: `packages/mobile/lib/core/helpers/cache/cache_keys.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart`

**Interfaces:**
- Consumes: the composer suggestion logic (Task 9), `dockInset` (Task 10), `ChatImageModel`/
  `ChatResourceModel` (Task 14), `ConversationSnapshotModel`.
- Produces:
  - `class PickedAttachment extends Equatable` — `id`, `name`, `bytes (int)`, `image`, `resource`
  - `abstract class AttachmentPicker` — `Future<List<PickedAttachment>> pickImages()`,
    `Future<List<PickedAttachment>> pickTextFiles()`, plus
    `class AttachmentPickerException implements Exception`
  - `class PlatformAttachmentPicker implements AttachmentPicker` (image_picker + file_selector)
  - `Future<String?> showSuggestionSheet(BuildContext, {required SuggestionKind kind, required List<ChatSkillModel> skills, required List<String> filePaths, required bool filePathsTruncated})`
  - `class ChatComposer extends StatefulWidget` — `sessionId`, `snapshot`, `skills`, `filePaths`,
    `filePathsTruncated`, `configOptions`, `steerUnavailable`, `pending`, `error`, `onSend`,
    `onSteer`, `onInterrupt`, `onOpenSettings`, `picker`
  - `CacheKeys.chatDraft(String sessionId)`

The picker is an interface with a platform implementation because `image_picker` and
`file_selector` both need a live platform channel: a widget test that touched them directly would
either hang or need a channel mock per test. The composer takes `AttachmentPicker? picker` and
falls back to `PlatformAttachmentPicker()`, so production wiring is unchanged and tests inject a
fake.

The limits and their copy are ported verbatim, because each one is a message a user reads at the
moment something failed: 8 attachments total, 10 MB per image, 25 MB of images combined, 500 KB per
embedded text file (with the "Reference a worktree file with @ instead" advice that tells the user
what to do next).

Two composer behaviors are subtle and load-bearing:

- **Steer is only offered while a turn is running, the provider advertises `steer`, the daemon has
  not already refused it, and there are no attachments.** Attachments start a new turn — an image
  cannot join a turn already in flight — which is why picking one forces the delivery choice to
  "Queue for next".
- **The suggestion trigger is recomputed from text and caret only.** RN's comment records the bug:
  depending on the trigger itself re-runs the effect forever ("Maximum update depth exceeded") and
  reopens a picker the user just dismissed. In Flutter the same trap is a `setState` inside a
  listener that reads the value it writes, so the trigger is derived in `_onTextChanged` and never
  read back as an input.

The mic key is **absent**, not disabled — voice is M5.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/logic/attachment_picker.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePicker implements AttachmentPicker {
  _FakePicker({this.images = const [], this.files = const []});

  final List<PickedAttachment> images;
  final List<PickedAttachment> files;

  @override
  Future<List<PickedAttachment>> pickImages() async => images;

  @override
  Future<List<PickedAttachment>> pickTextFiles() async => files;
}

ConversationSnapshotModel snapshot({
  List<String> capabilities = const [],
  String controllerState = 'ready',
  List<ConversationTurnModel> turns = const [],
}) =>
    ConversationSnapshotModel(
      conversationId: 'c-1',
      sessionId: 'w-1',
      harness: 'codex',
      controllerState: controllerState,
      latestSequence: 1,
      turns: turns,
      capabilities: capabilities,
    );

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
  });

  Future<void> pumpComposer(
    WidgetTester tester, {
    required ConversationSnapshotModel value,
    AttachmentPicker? picker,
    List<ChatSkillModel> skills = const [],
    List<String> filePaths = const [],
    Future<void> Function(String, {List<ChatImageModel>? attachments, List<ChatResourceModel>? resources})? onSend,
    Future<void> Function(String)? onSteer,
    VoidCallback? onInterrupt,
  }) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: ChatComposer(
                sessionId: 'w-1',
                snapshot: value,
                skills: skills,
                filePaths: filePaths,
                filePathsTruncated: false,
                configOptions: const [],
                picker: picker ?? _FakePicker(),
                onSend: onSend ?? (text, {attachments, resources}) async {},
                onSteer: onSteer ?? (text) async {},
                onInterrupt: onInterrupt ?? () {},
                onOpenSettings: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sends the trimmed message and clears the field', (tester) async {
    String? sent;
    await pumpComposer(
      tester,
      value: snapshot(),
      onSend: (text, {attachments, resources}) async => sent = text,
    );

    await tester.enterText(find.byType(TextField), '  ship it  ');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(sent, 'ship it');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('refuses to send an empty message', (tester) async {
    var sends = 0;
    await pumpComposer(
      tester,
      value: snapshot(),
      onSend: (text, {attachments, resources}) async => sends++,
    );

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    expect(sends, 0);
  });

  testWidgets('offers steering only while a turn runs and the provider allows it', (tester) async {
    await pumpComposer(tester, value: snapshot(capabilities: const ['steer']));
    expect(find.text('Steer this turn'), findsNothing);

    await pumpComposer(
      tester,
      value: snapshot(
        capabilities: const ['steer'],
        turns: const [ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a')],
      ),
    );
    expect(find.text('Steer this turn'), findsOneWidget);
    expect(find.text('Queue for next'), findsOneWidget);
  });

  testWidgets('routes a steered message to onSteer instead of onSend', (tester) async {
    String? steered;
    await pumpComposer(
      tester,
      value: snapshot(
        capabilities: const ['steer'],
        turns: const [ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a')],
      ),
      onSteer: (text) async => steered = text,
    );

    await tester.enterText(find.byType(TextField), 'use the other file');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.reply));
    await tester.pumpAndSettle();

    expect(steered, 'use the other file');
  });

  testWidgets('offers to stop a running turn when the field is empty', (tester) async {
    var interrupts = 0;
    await pumpComposer(
      tester,
      value: snapshot(turns: const [ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a')]),
      onInterrupt: () => interrupts++,
    );

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
    expect(interrupts, 1);
  });

  testWidgets('attaches an image and forces the message into a new turn', (tester) async {
    List<ChatImageModel>? sentImages;
    await pumpComposer(
      tester,
      value: snapshot(
        capabilities: const ['steer'],
        turns: const [ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a')],
      ),
      picker: _FakePicker(images: const [
        PickedAttachment(
          id: 'a',
          name: 'shot.png',
          bytes: 12,
          image: ChatImageModel(mimeType: 'image/png', data: 'AAA'),
        ),
      ]),
      onSend: (text, {attachments, resources}) async => sentImages = attachments,
    );

    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();
    expect(find.text('shot.png'), findsOneWidget);
    expect(find.textContaining('Attachments start a new turn'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'look at this');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(sentImages, hasLength(1));
  });

  testWidgets('offers a text-file attachment only when the provider embeds context', (tester) async {
    await pumpComposer(tester, value: snapshot());
    expect(find.byIcon(Icons.note_add_outlined), findsNothing);

    await pumpComposer(tester, value: snapshot(capabilities: const ['embedded_context']));
    expect(find.byIcon(Icons.note_add_outlined), findsOneWidget);
  });

  testWidgets('disables the composer while the controller is stopped', (tester) async {
    await pumpComposer(tester, value: snapshot(controllerState: 'stopped'));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });

  testWidgets('restores a draft saved for this session', (tester) async {
    await CacheHelper.save(CacheKeys.chatDraft('w-1'), 'half a thought');
    await pumpComposer(tester, value: snapshot());
    expect(find.text('half a thought'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart`
Expected: FAIL — the composer does not exist.

- [ ] **Step 3: Add the draft cache key**

In `packages/mobile/lib/core/helpers/cache/cache_keys.dart`:

```dart
  static String chatDraft(String sessionId) => 'opr.chat.draft.$sessionId';
```

- [ ] **Step 4: Write the attachment picker**

`packages/mobile/lib/feature/chat/logic/attachment_picker.dart`:

```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';

const int kMaxAttachments = 8;
const int kMaxImageBytes = 10 * 1024 * 1024;
const int kMaxImageBytesTotal = 25 * 1024 * 1024;
const int kMaxEmbeddedFileBytes = 500000;
const Set<String> kSupportedImageTypes = {
  'image/png',
  'image/jpeg',
  'image/jpg',
  'image/gif',
  'image/webp',
  'image/bmp',
};

class AttachmentPickerException implements Exception {
  const AttachmentPickerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PickedAttachment extends Equatable {
  const PickedAttachment({
    required this.id,
    required this.name,
    required this.bytes,
    this.image,
    this.resource,
  });

  final String id;
  final String name;
  final int bytes;
  final ChatImageModel? image;
  final ChatResourceModel? resource;

  bool get isImage => image != null;

  @override
  List<Object?> get props => [id, name, bytes, image, resource];
}

abstract class AttachmentPicker {
  Future<List<PickedAttachment>> pickImages();
  Future<List<PickedAttachment>> pickTextFiles();
}

class PlatformAttachmentPicker implements AttachmentPicker {
  PlatformAttachmentPicker({ImagePicker? imagePicker}) : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<List<PickedAttachment>> pickImages() async {
    final assets = await _imagePicker.pickMultiImage(imageQuality: 82, limit: 4);
    final picked = <PickedAttachment>[];

    for (final asset in assets) {
      final mimeType = (asset.mimeType ?? 'image/jpeg').toLowerCase();
      if (!kSupportedImageTypes.contains(mimeType)) {
        throw const AttachmentPickerException(
          'Only PNG, JPEG, GIF, WebP, and BMP images are supported.',
        );
      }
      final bytes = await asset.readAsBytes();
      if (bytes.length > kMaxImageBytes) {
        throw const AttachmentPickerException('Each image must be under 10 MB.');
      }
      picked.add(
        PickedAttachment(
          id: '${asset.path}-${DateTime.now().microsecondsSinceEpoch}',
          name: asset.name.isEmpty ? 'Image' : asset.name,
          bytes: bytes.length,
          image: ChatImageModel(mimeType: mimeType, data: base64Encode(bytes)),
        ),
      );
    }
    return picked;
  }

  @override
  Future<List<PickedAttachment>> pickTextFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'text',
          mimeTypes: ['text/*', 'application/json', 'application/xml', 'application/yaml'],
          uniformTypeIdentifiers: ['public.plain-text', 'public.json', 'public.xml', 'public.source-code'],
        ),
      ],
    );

    final picked = <PickedAttachment>[];
    for (final file in files) {
      final body = await file.readAsString();
      final bytes = utf8.encode(body).length;
      if (bytes > kMaxEmbeddedFileBytes) {
        throw AttachmentPickerException(
          '${file.name} is larger than 500 KB. Reference a worktree file with @ instead.',
        );
      }
      picked.add(
        PickedAttachment(
          id: '${file.path}-${DateTime.now().microsecondsSinceEpoch}',
          name: file.name,
          bytes: bytes,
          resource: ChatResourceModel(
            uri: 'mobile-attachment://${Uri.encodeComponent(file.name)}',
            name: file.name,
            mimeType: file.mimeType ?? 'text/plain',
            text: body,
          ),
        ),
      );
    }
    return picked;
  }
}
```

- [ ] **Step 5: Write the suggestion sheet**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/suggestion_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/logic/composer_suggestions.dart';

Future<String?> showSuggestionSheet(
  BuildContext context, {
  required SuggestionKind kind,
  required List<ChatSkillModel> skills,
  required List<String> filePaths,
  required bool filePathsTruncated,
  String initialQuery = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.skin.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => _SuggestionSheet(
      kind: kind,
      skills: skills,
      filePaths: filePaths,
      filePathsTruncated: filePathsTruncated,
      initialQuery: initialQuery,
    ),
  );
}

class _SuggestionSheet extends StatefulWidget {
  const _SuggestionSheet({
    required this.kind,
    required this.skills,
    required this.filePaths,
    required this.filePathsTruncated,
    required this.initialQuery,
  });

  final SuggestionKind kind;
  final List<ChatSkillModel> skills;
  final List<String> filePaths;
  final bool filePathsTruncated;
  final String initialQuery;

  @override
  State<_SuggestionSheet> createState() => _SuggestionSheetState();
}

class _SuggestionSheetState extends State<_SuggestionSheet> {
  late final TextEditingController _query = TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final choices = widget.kind == SuggestionKind.skills
        ? rankComposerSkills(widget.skills, _query.text)
        : rankComposerFiles(widget.filePaths, _query.text);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: AppText(
                      widget.kind == SuggestionKind.skills ? 'Skills' : 'Worktree files',
                      style: AppTextStyle.style17SemiBold,
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close, size: 19, color: skin.textSecondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: AppTextStyle.style14Regular.copyWith(color: skin.textPrimary),
                decoration: InputDecoration(
                  hintText: widget.kind == SuggestionKind.skills ? 'Find a skill' : 'Find a file',
                  hintStyle: AppTextStyle.style14Regular.copyWith(color: skin.textFaint),
                  filled: true,
                  fillColor: skin.bgElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (widget.kind == SuggestionKind.files && widget.filePathsTruncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
                child: AppText(
                  "Showing the daemon's capped path list. Narrow your search or type a path directly.",
                  style: AppTextStyle.style10Regular.copyWith(color: skin.amber),
                  maxLines: 2,
                ),
              ),
            const VerticalSpace(8),
            Expanded(
              child: choices.isEmpty
                  ? Center(
                      child: AppText(
                        'No matches',
                        style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: choices.length,
                      itemBuilder: (context, index) {
                        final choice = choices[index];
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(choice.value),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: skin.borderSubtle)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AppText(choice.label, style: AppTextStyle.style13SemiBold),
                                      if (choice.detail != null)
                                        AppText(
                                          choice.detail!,
                                          style: AppTextStyle.style11Regular
                                              .copyWith(color: skin.textTertiary),
                                          maxLines: 2,
                                        ),
                                    ],
                                  ),
                                ),
                                if (choice.badge != null)
                                  AppText(
                                    choice.badge!.toUpperCase(),
                                    style: AppTextStyle.style9Regular.copyWith(color: skin.textFaint),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Write the composer**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/attachment_picker.dart';
import 'package:operator_mobile/feature/chat/logic/composer_suggestions.dart';
import 'package:operator_mobile/feature/chat/logic/keyboard_inset.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/suggestion_sheet.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.sessionId,
    required this.snapshot,
    required this.skills,
    required this.filePaths,
    required this.filePathsTruncated,
    required this.configOptions,
    required this.onSend,
    required this.onSteer,
    required this.onInterrupt,
    required this.onOpenSettings,
    this.steerUnavailable = false,
    this.pending = false,
    this.error,
    this.picker,
  });

  final String sessionId;
  final ConversationSnapshotModel snapshot;
  final List<ChatSkillModel> skills;
  final List<String> filePaths;
  final bool filePathsTruncated;
  final List<ChatConfigOptionModel> configOptions;
  final bool steerUnavailable;
  final bool pending;
  final String? error;
  final AttachmentPicker? picker;
  final Future<void> Function(String text, {List<ChatImageModel>? attachments, List<ChatResourceModel>? resources}) onSend;
  final Future<void> Function(String text) onSteer;
  final VoidCallback onInterrupt;
  final VoidCallback onOpenSettings;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  late final AttachmentPicker _picker = widget.picker ?? PlatformAttachmentPicker();

  Timer? _draftTimer;
  List<PickedAttachment> _attachments = [];
  ComposerSuggestion? _trigger;
  bool _queueDelivery = false;
  bool _submitting = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    final draft = CacheHelper.get(CacheKeys.chatDraft(widget.sessionId)) as String?;
    if (draft != null && draft.isNotEmpty) _controller.text = draft;
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _turnRunning => widget.snapshot.turns.any((turn) => turn.state == 'running');

  bool get _canSteer =>
      widget.snapshot.can('steer') && !widget.steerUnavailable && _turnRunning;

  bool get _steerEligible => _canSteer && !_queueDelivery && _attachments.isEmpty;

  bool get _stopped => widget.snapshot.controllerState == 'stopped';

  void _onTextChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), () {
      final text = _controller.text;
      unawaited(text.isEmpty
          ? CacheHelper.remove(CacheKeys.chatDraft(widget.sessionId))
          : CacheHelper.save(CacheKeys.chatDraft(widget.sessionId), text));
    });

    final caret = _controller.selection.baseOffset;
    final suggestion = findComposerSuggestion(_controller.text, caret < 0 ? null : caret);
    final available = suggestion == null
        ? false
        : suggestion.kind == SuggestionKind.skills
            ? widget.skills.isNotEmpty
            : widget.filePaths.isNotEmpty;

    if (available && suggestion != _trigger) {
      _trigger = suggestion;
      unawaited(_openSuggestions(suggestion!.kind, suggestion.query));
    } else if (!available) {
      _trigger = null;
    }
    setState(() {});
  }

  Future<void> _openSuggestions(SuggestionKind kind, String query) async {
    final trigger = _trigger;
    final value = await showSuggestionSheet(
      context,
      kind: kind,
      skills: widget.skills,
      filePaths: widget.filePaths,
      filePathsTruncated: widget.filePathsTruncated,
      initialQuery: query,
    );
    if (!mounted) return;

    _trigger = null;
    if (value == null) return;

    final text = _controller.text;
    final next = trigger != null && trigger.kind == kind
        ? replaceComposerSuggestion(text, trigger, value)
        : '$text${text.isEmpty || text.endsWith(' ') ? '' : ' '}'
            '${kind == SuggestionKind.skills ? '/$value' : (value.contains(' ') ? '"$value"' : value)} ';

    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _pick(Future<List<PickedAttachment>> Function() pick) async {
    setState(() => _localError = null);
    try {
      final picked = await pick();
      if (!mounted || picked.isEmpty) return;

      final accepted = [..._attachments];
      var imageBytes = accepted.where((item) => item.isImage).fold<int>(0, (sum, item) => sum + item.bytes);
      String? problem;

      for (final item in picked) {
        if (accepted.length >= kMaxAttachments) {
          problem = 'You can attach up to $kMaxAttachments items.';
          break;
        }
        if (item.isImage && imageBytes + item.bytes > kMaxImageBytesTotal) {
          problem = 'Images must total under 25 MB.';
          break;
        }
        accepted.add(item);
        if (item.isImage) imageBytes += item.bytes;
      }

      setState(() {
        _attachments = accepted;
        _localError = problem;
        if (accepted.isNotEmpty) _queueDelivery = true;
      });
    } on AttachmentPickerException catch (error) {
      if (mounted) setState(() => _localError = error.message);
    } catch (error) {
      if (mounted) setState(() => _localError = 'Could not read that attachment.');
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty && _attachments.isEmpty) return;

    setState(() {
      _submitting = true;
      _localError = null;
    });

    try {
      final images = _attachments.where((item) => item.isImage).map((item) => item.image!).toList();
      final resources = _attachments.where((item) => !item.isImage).map((item) => item.resource!).toList();

      if (_steerEligible) {
        await widget.onSteer(trimmed);
      } else {
        await widget.onSend(
          trimmed,
          attachments: images.isEmpty ? null : images,
          resources: resources.isEmpty ? null : resources,
        );
      }

      if (!mounted) return;
      _controller.clear();
      setState(() => _attachments = []);
      unawaited(CacheHelper.remove(CacheKeys.chatDraft(widget.sessionId)));
      FocusScope.of(context).unfocus();
    } catch (error) {
      if (mounted) setState(() => _localError = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final media = MediaQuery.of(context);
    final hasContent = _controller.text.trim().isNotEmpty || _attachments.isNotEmpty;
    final sendDisabled = _stopped || widget.pending || _submitting || !hasContent;
    final providerModel = widget.configOptions.where(
      (option) => option.category == 'model' || option.id == 'model' || option.id == 'agent',
    ).firstOrNull;
    final providerLabel = providerModel?.type == 'select'
        ? providerModel!.choices
                .where((choice) => choice.value == providerModel.currentValue)
                .map((choice) => choice.name)
                .firstOrNull ??
            providerModel.currentValue
        : null;
    final selectedModel =
        widget.snapshot.modelReroute?.toModel ?? providerLabel ?? widget.snapshot.settings.model;

    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        8 + dockInset(media.viewInsets.bottom, media.viewPadding.bottom),
      ),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border(top: BorderSide(color: skin.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_attachments.isNotEmpty)
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                separatorBuilder: (_, __) => const HorizontalSpace(7),
                itemBuilder: (context, index) {
                  final item = _attachments[index];
                  return Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                    decoration: BoxDecoration(
                      color: skin.bgElevated,
                      border: Border.all(color: skin.borderSubtle),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.isImage)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              base64Decode(item.image!.data),
                              width: 26,
                              height: 26,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Icon(Icons.image_outlined, size: 14, color: skin.blue),
                            ),
                          )
                        else
                          Icon(Icons.description_outlined, size: 14, color: skin.blue),
                        const HorizontalSpace(6),
                        Flexible(
                          child: AppText(
                            item.name,
                            style: AppTextStyle.style11Regular.copyWith(color: skin.textSecondary),
                          ),
                        ),
                        const HorizontalSpace(6),
                        InkWell(
                          onTap: () => setState(
                            () => _attachments = _attachments.where((other) => other.id != item.id).toList(),
                          ),
                          child: Icon(Icons.close, size: 13, color: skin.textTertiary),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (_localError != null || widget.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 3),
              child: AppText(
                _localError ?? widget.error!,
                style: AppTextStyle.style11Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
          Opacity(
            opacity: _stopped ? 0.55 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: skin.bgElevated,
                border: Border.all(color: skin.borderDefault),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: !_stopped,
                      maxLines: null,
                      maxLength: 40000,
                      style: AppTextStyle.style15Regular.copyWith(color: skin.textPrimary, height: 1.4),
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        border: InputBorder.none,
                        hintText: _stopped
                            ? 'Agent is stopped'
                            : _turnRunning
                                ? (_steerEligible
                                    ? 'Agent is working — this goes into its running turn'
                                    : 'Agent is working — this sends when it finishes')
                                : widget.skills.isNotEmpty
                                    ? 'Ask the agent…  / for skills, @ for files'
                                    : 'Ask the agent…  @ for files',
                        hintStyle: AppTextStyle.style15Regular.copyWith(color: skin.textFaint),
                      ),
                    ),
                  ),
                  if (_canSteer) _deliveryChoice(context),
                  Row(
                    children: [
                      _iconButton(context, Icons.attach_file, 'Attach image',
                          _stopped ? null : () => _pick(_picker.pickImages)),
                      if (widget.snapshot.can('embedded_context'))
                        _iconButton(context, Icons.note_add_outlined, 'Attach text file',
                            _stopped ? null : () => _pick(_picker.pickTextFiles)),
                      if (widget.skills.isNotEmpty)
                        _iconButton(context, Icons.terminal, 'Skills',
                            _stopped ? null : () => _openSuggestions(SuggestionKind.skills, '')),
                      if (widget.filePaths.isNotEmpty)
                        _iconButton(context, Icons.alternate_email, 'Worktree files',
                            _stopped ? null : () => _openSuggestions(SuggestionKind.files, '')),
                      Flexible(
                        child: InkWell(
                          onTap: widget.onOpenSettings,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.memory, size: 13, color: skin.textTertiary),
                                const HorizontalSpace(5),
                                Flexible(
                                  child: AppText(
                                    selectedModel ?? 'Default',
                                    style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_turnRunning && _controller.text.trim().isEmpty)
                        _roundButton(
                          context,
                          icon: Icons.stop,
                          background: skin.bgSubtle,
                          foreground: skin.textPrimary,
                          onTap: widget.onInterrupt,
                        )
                      else
                        _roundButton(
                          context,
                          icon: _steerEligible ? Icons.reply : Icons.arrow_upward,
                          background: skin.blue,
                          foreground: skin.onAccent,
                          busy: widget.pending || _submitting,
                          onTap: sendDisabled ? null : _submit,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deliveryChoice(BuildContext context) {
    final skin = context.skin;
    final forced = _attachments.isNotEmpty;
    Widget option(String label, bool queue) {
      final selected = forced ? queue : _queueDelivery == queue;
      final disabled = forced && !queue;
      return Opacity(
        opacity: disabled ? 0.35 : 1,
        child: InkWell(
          onTap: disabled ? null : () => setState(() => _queueDelivery = queue),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? skin.bgSubtle : null,
              borderRadius: BorderRadius.circular(7),
            ),
            child: AppText(
              label,
              style: AppTextStyle.style10SemiBold
                  .copyWith(color: selected ? skin.textPrimary : skin.textTertiary),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          option('Steer this turn', false),
          const HorizontalSpace(3),
          option('Queue for next', true),
          if (forced)
            Expanded(
              child: AppText(
                'Attachments start a new turn.',
                style: AppTextStyle.style9Regular.copyWith(color: skin.textFaint),
                textAlign: TextAlign.right,
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconButton(BuildContext context, IconData icon, String label, VoidCallback? onTap) {
    final skin = context.skin;
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      iconSize: 17,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
      padding: EdgeInsets.zero,
      icon: Icon(icon, color: onTap == null ? skin.textFaint : skin.textTertiary),
    );
  }

  Widget _roundButton(
    BuildContext context, {
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                  )
                : Icon(icon, size: 17, color: foreground),
          ),
        ),
      ),
    );
  }
}
```

`firstOrNull` on the two `where(...)` chains comes from `package:collection`; add
`import 'package:collection/collection.dart';` if the analyzer asks for it.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart`
Expected: PASS.

- [ ] **Step 8: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 560/560 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the chat composer with attachments"
```

---

### Task 24: Turn settings, the conversation menu, and the conversation map

**Files:**
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_settings_sheet.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/conversation_map_sheet.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_sheets_test.dart`

**Interfaces:**
- Consumes: `ConversationSnapshotModel`, the catalog models, `conversationMarkers` (Task 13),
  `TurnSettingsModel`.
- Produces:
  - `Future<void> showChatSettingsSheet(BuildContext, {required ConversationSnapshotModel snapshot, required List<ChatModelModel> models, required List<ChatConfigOptionModel> options, required bool disabled, String? error, required void Function(TurnSettingsModel) onSettings, required void Function(SetConfigOptionParams) onOption})`
  - `enum ConversationMenuAction { map, pullRequests, settings, compact, reloadMcp, rename }`
  - `class ConversationMenuResult` — `action`, `title (String?)`
  - `Future<ConversationMenuResult?> showConversationMenuSheet(BuildContext, {...})`
  - `Future<int?> showConversationMapSheet(BuildContext, {required List<ConversationMarker> markers})`

The settings sheet has one either/or that must not blur: when the provider advertises
`config_options` it owns **all** of its controls, so Operator's Model, Reasoning effort and
Approvals sections disappear entirely rather than sitting there inert beside the provider's own.
When the provider advertises nothing yet, the sheet says so instead of looking empty and broken.

The four approval modes keep their exact copy, because each hint states a different safety
boundary:

> Default — the worktree is the safety boundary · Ask outside worktree — edits here are allowed;
> anything else asks · Ask when unsure — the agent decides when to check with you · Never ask — no
> approvals or sandbox prompts

The menu returns a result rather than taking ten callbacks: it is a modal sheet, its caller is one
screen, and `Navigator.pop(result)` is how Flutter says "the user chose this". Rename is the one
action carrying a value, which is why `ConversationMenuResult` has a `title`.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_sheets_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_config_option_params.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_settings_sheet.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/conversation_map_sheet.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart';

ConversationSnapshotModel snapshot({
  List<String> capabilities = const [],
  TurnSettingsModel settings = const TurnSettingsModel(),
}) =>
    ConversationSnapshotModel(
      conversationId: 'c-1',
      sessionId: 'w-1',
      harness: 'codex',
      controllerState: 'ready',
      latestSequence: 1,
      settings: settings,
      capabilities: capabilities,
    );

Future<void> pumpHost(WidgetTester tester, Future<void> Function(BuildContext) open) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (inner) => TextButton(onPressed: () => open(inner), child: const Text('open')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers Operator turn settings when the provider owns none', (tester) async {
    TurnSettingsModel? chosen;
    await pumpHost(
      tester,
      (context) => showChatSettingsSheet(
        context,
        snapshot: snapshot(),
        models: const [
          ChatModelModel(id: 'opus', displayName: 'Opus', isDefault: true, efforts: ['low', 'high']),
        ],
        options: const [],
        disabled: false,
        onSettings: (settings) => chosen = settings,
        onOption: (_) {},
      ),
    );

    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Approvals'), findsOneWidget);
    expect(find.textContaining('the worktree is the safety boundary'), findsOneWidget);

    await tester.tap(find.text('Never ask'));
    await tester.pumpAndSettle();
    expect(chosen?.approvalMode, 'bypass-permissions');
  });

  testWidgets('hands the whole sheet to the provider when it advertises config options', (tester) async {
    SetConfigOptionParams? chosen;
    await pumpHost(
      tester,
      (context) => showChatSettingsSheet(
        context,
        snapshot: snapshot(capabilities: const ['config_options']),
        models: const [ChatModelModel(id: 'opus', displayName: 'Opus')],
        options: const [
          ChatConfigOptionModel(
            id: 'fast',
            name: 'Fast mode',
            type: 'boolean',
            currentBoolean: false,
          ),
        ],
        disabled: false,
        onSettings: (_) {},
        onOption: (params) => chosen = params,
      ),
    );

    expect(find.text('Model'), findsNothing);
    expect(find.text('Approvals'), findsNothing);
    expect(find.text('Fast mode'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(chosen?.optionId, 'fast');
    expect(chosen?.enabled, isTrue);
  });

  testWidgets('says so when the provider has advertised nothing yet', (tester) async {
    await pumpHost(
      tester,
      (context) => showChatSettingsSheet(
        context,
        snapshot: snapshot(capabilities: const ['config_options']),
        models: const [],
        options: const [],
        disabled: false,
        onSettings: (_) {},
        onOption: (_) {},
      ),
    );
    expect(find.textContaining('has not advertised any turn controls'), findsOneWidget);
  });

  testWidgets('offers only the menu rows this build can honour', (tester) async {
    await pumpHost(
      tester,
      (context) => showConversationMenuSheet(
        context,
        snapshot: snapshot(),
        compactSupported: false,
        mcpReloadSupported: false,
        compacting: false,
        mcpReloading: false,
      ),
    );

    expect(find.text('Conversation map'), findsOneWidget);
    expect(find.text('Pull requests'), findsOneWidget);
    expect(find.text('Turn settings'), findsOneWidget);
    expect(find.text('Compact history'), findsNothing);
    expect(find.text('Reload MCP servers'), findsNothing);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Open Terminal UI'), findsNothing);
  });

  testWidgets('returns the chosen menu action', (tester) async {
    ConversationMenuResult? result;
    await pumpHost(
      tester,
      (context) async => result = await showConversationMenuSheet(
        context,
        snapshot: snapshot(capabilities: const ['compaction']),
        compactSupported: true,
        mcpReloadSupported: false,
        compacting: false,
        mcpReloading: false,
      ),
    );

    await tester.tap(find.text('Compact history'));
    await tester.pumpAndSettle();
    expect(result?.action, ConversationMenuAction.compact);
  });

  testWidgets('lists every exchange in the map and returns the chosen sequence', (tester) async {
    int? chosen;
    await pumpHost(
      tester,
      (context) async => chosen = await showConversationMapSheet(
        context,
        markers: const [
          ConversationMarker(key: 'turn-t1', sequence: 1, title: 'First task', detail: 'First answer'),
          ConversationMarker(key: 'turn-t2', sequence: 5, title: 'Second task', state: 'failed'),
        ],
      ),
    );

    expect(find.text('2 exchanges'), findsOneWidget);
    await tester.tap(find.text('Second task'));
    await tester.pumpAndSettle();
    expect(chosen, 5);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_sheets_test.dart`
Expected: FAIL — the sheets do not exist.

- [ ] **Step 3: Write the settings sheet**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_settings_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_config_option_params.dart';

const List<({String id, String label, String hint})> kApprovalModes = [
  (id: 'default', label: 'Default', hint: 'The worktree is the safety boundary'),
  (id: 'accept-edits', label: 'Ask outside worktree', hint: 'Edits here are allowed; anything else asks'),
  (id: 'auto', label: 'Ask when unsure', hint: 'The agent decides when to check with you'),
  (id: 'bypass-permissions', label: 'Never ask', hint: 'No approvals or sandbox prompts'),
];

Future<void> showChatSettingsSheet(
  BuildContext context, {
  required ConversationSnapshotModel snapshot,
  required List<ChatModelModel> models,
  required List<ChatConfigOptionModel> options,
  required bool disabled,
  required void Function(TurnSettingsModel settings) onSettings,
  required void Function(SetConfigOptionParams params) onOption,
  String? error,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.skin.bgSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => _ChatSettingsSheet(
      snapshot: snapshot,
      models: models,
      options: options,
      disabled: disabled,
      error: error,
      onSettings: onSettings,
      onOption: onOption,
    ),
  );
}

class _ChatSettingsSheet extends StatelessWidget {
  const _ChatSettingsSheet({
    required this.snapshot,
    required this.models,
    required this.options,
    required this.disabled,
    required this.onSettings,
    required this.onOption,
    this.error,
  });

  final ConversationSnapshotModel snapshot;
  final List<ChatModelModel> models;
  final List<ChatConfigOptionModel> options;
  final bool disabled;
  final String? error;
  final void Function(TurnSettingsModel settings) onSettings;
  final void Function(SetConfigOptionParams params) onOption;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final usesProviderOptions = snapshot.can('config_options');
    final selected = models.where((model) => model.id == snapshot.settings.model).firstOrNull ??
        models.where((model) => model.isDefault).firstOrNull;
    final efforts = selected?.efforts ?? const <String>[];

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText('Turn settings', style: AppTextStyle.style17SemiBold),
                      AppText(
                        'Changes apply to the next message.',
                        style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close, size: 20, color: skin.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: [
                if (error != null)
                  Container(
                    padding: const EdgeInsets.all(11),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: skin.tintRed, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 14, color: skin.red),
                        const HorizontalSpace(8),
                        Expanded(
                          child: AppText(
                            error!,
                            style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                            maxLines: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (snapshot.modelReroute != null)
                  Container(
                    padding: const EdgeInsets.all(11),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: skin.tintAmber, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          'Currently answered by ${snapshot.modelReroute!.toModel}',
                          style: AppTextStyle.style12SemiBold,
                          maxLines: 2,
                        ),
                        AppText(
                          '${snapshot.modelReroute!.fromModel == null ? '' : '${snapshot.modelReroute!.fromModel} was requested. '}'
                          '${snapshot.modelReroute!.reason ?? 'The provider selected a fallback model for this conversation.'}',
                          style: AppTextStyle.style11Regular.copyWith(color: skin.textSecondary),
                          maxLines: 4,
                        ),
                      ],
                    ),
                  ),
                if (!usesProviderOptions && models.isNotEmpty)
                  _Section(
                    icon: Icons.memory,
                    title: 'Model',
                    children: [
                      for (final model in models)
                        _Choice(
                          label: model.displayName,
                          hint: model.description ?? (model.isDefault ? 'Provider default' : null),
                          selected: model.id == selected?.id,
                          enabled: !disabled,
                          onTap: () => onSettings(
                            TurnSettingsModel(model: model.id, approvalMode: snapshot.settings.approvalMode),
                          ),
                        ),
                    ],
                  ),
                if (!usesProviderOptions && efforts.isNotEmpty)
                  _Section(
                    icon: Icons.speed,
                    title: 'Reasoning effort',
                    children: [
                      for (final effort in efforts)
                        _Choice(
                          label: '${effort[0].toUpperCase()}${effort.substring(1)}',
                          selected: effort == (snapshot.settings.reasoningEffort ?? selected?.defaultEffort),
                          enabled: !disabled,
                          onTap: () => onSettings(
                            TurnSettingsModel(
                              model: snapshot.settings.model,
                              reasoningEffort: effort,
                              approvalMode: snapshot.settings.approvalMode,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (!usesProviderOptions)
                  _Section(
                    icon: Icons.shield_outlined,
                    title: 'Approvals',
                    children: [
                      for (final mode in kApprovalModes)
                        _Choice(
                          label: mode.label,
                          hint: mode.hint,
                          selected: mode.id == (snapshot.settings.approvalMode ?? 'default'),
                          enabled: !disabled,
                          onTap: () => onSettings(
                            TurnSettingsModel(
                              model: snapshot.settings.model,
                              reasoningEffort: snapshot.settings.reasoningEffort,
                              approvalMode: mode.id,
                            ),
                          ),
                        ),
                    ],
                  ),
                for (final option in options)
                  _Section(
                    icon: _optionIcon(option),
                    title: option.name,
                    description: option.description,
                    children: option.type == 'boolean'
                        ? [
                            Row(
                              children: [
                                Expanded(
                                  child: AppText(
                                    option.currentBoolean == true ? 'On' : 'Off',
                                    style: AppTextStyle.style13Regular,
                                  ),
                                ),
                                Switch(
                                  value: option.currentBoolean == true,
                                  activeThumbColor: skin.blue,
                                  onChanged: disabled
                                      ? null
                                      : (enabled) =>
                                          onOption(SetConfigOptionParams(optionId: option.id, enabled: enabled)),
                                ),
                              ],
                            ),
                          ]
                        : _groupedChoices(option),
                  ),
                if (usesProviderOptions && options.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: AppText(
                      'The provider has not advertised any turn controls yet.',
                      style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _groupedChoices(ChatConfigOptionModel option) {
    final groups = <String, List<ChatConfigChoiceModel>>{};
    for (final choice in option.choices) {
      groups.putIfAbsent(choice.groupName ?? choice.group ?? '', () => []).add(choice);
    }
    return [
      for (final entry in groups.entries) ...[
        if (entry.key.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: AppText(entry.key, style: AppTextStyle.style10Bold),
          ),
        for (final choice in entry.value)
          _Choice(
            label: choice.name,
            hint: choice.description,
            selected: choice.value == option.currentValue,
            enabled: !disabled,
            onTap: () => onOption(SetConfigOptionParams(optionId: option.id, value: choice.value)),
          ),
      ],
    ];
  }

  IconData _optionIcon(ChatConfigOptionModel option) {
    if (option.id == 'fast') return Icons.bolt;
    if (option.id == 'agent') return Icons.person_outline;
    return switch (option.category) {
      'model' => Icons.memory,
      'thought_level' => Icons.speed,
      'mode' => Icons.shield_outlined,
      _ => Icons.tune,
    };
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.children, this.description});

  final IconData icon;
  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: skin.textTertiary),
              const HorizontalSpace(7),
              AppText(title, style: AppTextStyle.style12Bold),
            ],
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: AppText(
                description!,
                style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
                maxLines: 3,
              ),
            ),
          const VerticalSpace(8),
          Container(
            decoration: BoxDecoration(
              color: skin.bgElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.hint,
  });

  final String label;
  final String? hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    label,
                    style: AppTextStyle.style13SemiBold.copyWith(color: selected ? skin.blue : skin.textPrimary),
                  ),
                  if (hint != null)
                    AppText(
                      hint!,
                      style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
                      maxLines: 2,
                    ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check, size: 16, color: skin.blue),
          ],
        ),
      ),
    );
  }
}
```

`firstOrNull` on the two `models.where(...)` chains comes from `package:collection`; add
`import 'package:collection/collection.dart';` if the analyzer asks for it, exactly as in Task 23.

- [ ] **Step 4: Write the menu and map sheets**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';

enum ConversationMenuAction { map, pullRequests, settings, compact, reloadMcp, rename }

class ConversationMenuResult {
  const ConversationMenuResult(this.action, {this.title});

  final ConversationMenuAction action;
  final String? title;
}

Future<ConversationMenuResult?> showConversationMenuSheet(
  BuildContext context, {
  required ConversationSnapshotModel snapshot,
  required bool compactSupported,
  required bool mcpReloadSupported,
  required bool compacting,
  required bool mcpReloading,
}) {
  return showModalBottomSheet<ConversationMenuResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.skin.bgSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => _ConversationMenuSheet(
      snapshot: snapshot,
      compactSupported: compactSupported,
      mcpReloadSupported: mcpReloadSupported,
      compacting: compacting,
      mcpReloading: mcpReloading,
    ),
  );
}

class _ConversationMenuSheet extends StatefulWidget {
  const _ConversationMenuSheet({
    required this.snapshot,
    required this.compactSupported,
    required this.mcpReloadSupported,
    required this.compacting,
    required this.mcpReloading,
  });

  final ConversationSnapshotModel snapshot;
  final bool compactSupported;
  final bool mcpReloadSupported;
  final bool compacting;
  final bool mcpReloading;

  @override
  State<_ConversationMenuSheet> createState() => _ConversationMenuSheetState();
}

class _ConversationMenuSheetState extends State<_ConversationMenuSheet> {
  late final TextEditingController _title = TextEditingController(text: widget.snapshot.title ?? '');
  bool _renaming = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final snapshot = widget.snapshot;
    final turnInFlight = snapshot.hasTurnInFlight;

    if (_renaming) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText('Rename conversation', style: AppTextStyle.style16SemiBold),
              const VerticalSpace(10),
              TextField(
                controller: _title,
                autofocus: true,
                style: AppTextStyle.style14Regular.copyWith(color: skin.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Conversation title',
                  filled: true,
                  fillColor: skin.bgElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: skin.borderDefault),
                  ),
                ),
              ),
              const VerticalSpace(12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _renaming = false),
                    child: AppText('Cancel',
                        style: AppTextStyle.style13SemiBold.copyWith(color: skin.textTertiary)),
                  ),
                  TextButton(
                    onPressed: _title.text.trim().isEmpty
                        ? null
                        : () => Navigator.of(context).pop(
                              ConversationMenuResult(ConversationMenuAction.rename, title: _title.text.trim()),
                            ),
                    child: AppText('Save', style: AppTextStyle.style13Bold.copyWith(color: skin.blue)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: AppText('Conversation', style: AppTextStyle.style16SemiBold),
          ),
          _MenuRow(
            icon: Icons.list_alt,
            label: 'Conversation map',
            hint: 'Jump to any request and response',
            onTap: () => Navigator.of(context).pop(const ConversationMenuResult(ConversationMenuAction.map)),
          ),
          _MenuRow(
            icon: Icons.merge_outlined,
            label: 'Pull requests',
            hint: 'Review CI, feedback and merge state',
            onTap: () =>
                Navigator.of(context).pop(const ConversationMenuResult(ConversationMenuAction.pullRequests)),
          ),
          _MenuRow(
            icon: Icons.tune,
            label: 'Turn settings',
            hint: 'Model, effort, approvals and provider options',
            onTap: () =>
                Navigator.of(context).pop(const ConversationMenuResult(ConversationMenuAction.settings)),
          ),
          if (snapshot.can('rename'))
            _MenuRow(
              icon: Icons.edit_outlined,
              label: 'Rename',
              onTap: () => setState(() => _renaming = true),
            ),
          if (widget.compactSupported)
            _MenuRow(
              icon: Icons.archive_outlined,
              label: widget.compacting ? 'Compacting history…' : 'Compact history',
              hint: turnInFlight
                  ? 'Available after the current turn finishes'
                  : snapshot.compactedAt != null
                      ? 'Last compacted ${snapshot.compactedAt}'
                      : 'Summarize older context without changing files',
              enabled: !turnInFlight && !widget.compacting,
              onTap: () =>
                  Navigator.of(context).pop(const ConversationMenuResult(ConversationMenuAction.compact)),
            ),
          if (widget.mcpReloadSupported)
            _MenuRow(
              icon: Icons.refresh,
              label: widget.mcpReloading ? 'Reloading MCP servers…' : 'Reload MCP servers',
              hint: turnInFlight ? 'Available after the current turn finishes' : null,
              enabled: !turnInFlight && !widget.mcpReloading,
              onTap: () =>
                  Navigator.of(context).pop(const ConversationMenuResult(ConversationMenuAction.reloadMcp)),
            ),
          if (snapshot.usage != null)
            _InfoBox(
              title: 'Context and usage',
              body: '${_tokens(snapshot.usage!.contextUsed)} / ${_tokens(snapshot.usage!.contextWindow)} context'
                  ' · ${_tokens(snapshot.usage!.inputTokens)} in · ${_tokens(snapshot.usage!.outputTokens)} out'
                  '${(snapshot.usage!.cachedTokens ?? 0) > 0 ? ' · ${_tokens(snapshot.usage!.cachedTokens)} cached' : ''}'
                  '${snapshot.usage!.cost != null ? ' · ${snapshot.usage!.currency ?? '\$'}${snapshot.usage!.cost!.toStringAsFixed(4)}' : ''}',
            ),
          if (snapshot.rateLimits != null)
            _InfoBox(
              title: snapshot.rateLimits!.planLabel ?? 'Rate limits',
              body: 'Primary: ${(snapshot.rateLimits!.primaryUsedPercent ?? 0).round()}% used'
                  '${(snapshot.rateLimits!.secondaryUsedPercent ?? -1) >= 0 ? ' · Secondary: ${snapshot.rateLimits!.secondaryUsedPercent!.round()}%' : ''}',
            ),
        ],
      ),
    );
  }

  String _tokens(int? value) {
    final tokens = value ?? 0;
    return tokens >= 1000
        ? '${(tokens / 1000).toStringAsFixed(tokens >= 10000 ? 0 : 1)}k'
        : '$tokens';
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: skin.borderSubtle))),
          child: Row(
            children: [
              Icon(icon, size: 16, color: skin.textTertiary),
              const HorizontalSpace(11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(label, style: AppTextStyle.style13SemiBold),
                    if (hint != null)
                      AppText(
                        hint!,
                        style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
                        maxLines: 2,
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 15, color: skin.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: skin.borderSubtle))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(title, style: AppTextStyle.style11Bold.copyWith(color: skin.textSecondary)),
          const VerticalSpace(3),
          AppText(
            body,
            style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/conversation_map_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';

Future<int?> showConversationMapSheet(
  BuildContext context, {
  required List<ConversationMarker> markers,
}) {
  final skin = context.skin;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: skin.bgSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.of(sheetContext).size.height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText('Conversation map', style: AppTextStyle.style17SemiBold),
                      AppText(
                        '${markers.length} ${markers.length == 1 ? 'exchange' : 'exchanges'}',
                        style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(sheetContext).pop(),
                  child: Icon(Icons.close, size: 19, color: skin.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            child: markers.isEmpty
                ? Center(
                    child: AppText(
                      'No conversation entries yet.',
                      style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
                    ),
                  )
                : ListView.builder(
                    itemCount: markers.length,
                    itemBuilder: (context, index) {
                      final marker = markers[index];
                      return InkWell(
                        onTap: () => Navigator.of(sheetContext).pop(marker.sequence),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(top: 5, right: 12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: switch (marker.state) {
                                    'failed' => skin.red,
                                    'running' => skin.orange,
                                    _ => skin.blue,
                                  },
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 13),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: AppText(marker.title,
                                                style: AppTextStyle.style13SemiBold, maxLines: 2),
                                          ),
                                          if (marker.state != null)
                                            AppText(
                                              marker.state!.toUpperCase(),
                                              style: AppTextStyle.style9Regular
                                                  .copyWith(color: skin.textFaint, letterSpacing: 0.6),
                                            ),
                                        ],
                                      ),
                                      if (marker.detail != null) ...[
                                        const VerticalSpace(4),
                                        AppText(
                                          marker.detail!,
                                          style: AppTextStyle.style11Regular
                                              .copyWith(color: skin.textTertiary),
                                          maxLines: 3,
                                        ),
                                      ],
                                    ],
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
        ],
      ),
    ),
  );
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_sheets_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 566/566 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the turn settings, menu and map sheets"
```

---

### Task 25: The chat screen

**Files:**
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/inline_banner.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_meta_bar.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/conversation_banners.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/live_turn_bar.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/chat_screen.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_body_test.dart`

**Interfaces:**
- Consumes: `ChatCubit` (Tasks 17–19), every widget from Tasks 20–24, `conversationChrome` (Task 7).
- Produces:
  - `class InlineBanner extends StatelessWidget` — `tone (BannerTone)`, `icon`, `text`, `action`,
    `secondary`, `onPressed`, `onSecondary`; `enum BannerTone { warning, danger, muted }`
  - `class ChatMetaBar extends StatelessWidget`
  - `class ConversationBanners extends StatelessWidget`
  - `class LiveTurnBar extends StatefulWidget`
  - `class ChatBody extends StatefulWidget` — the whole conversation column
  - `class ChatScreen extends StatelessWidget` — `sessionId`, `title` — the `Scaffold` and app bar

`ChatBody` owns the `WidgetsBindingObserver` that calls `cubit.onResumed()` when the app returns to
the foreground, which is RN's `AppState` listener. It is on the body, not the screen, because the
body is the widget that already holds the cubit and the timeline's jump state.

The banner stack order is RN's, and the order encodes priority: reauth, controller stopped,
controller connecting/recovering, thread fault, broken MCP servers, transient load error, quota,
action error, rolled-back turns, then one banner per failed pending send. They stack rather than
replace each other because a stopped controller with a broken MCP server is two separate things a
person needs to know.

`ChatMetaBar`'s compact button is disabled — not hidden — while a turn is in flight, and its label
says why. Hiding it would read as "this agent cannot compact", which is a different fact.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_body_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockChatCubit extends MockCubit<ChatState> implements ChatCubit {}

ConversationSnapshotModel snapshot({
  String controllerState = 'ready',
  String? controllerError,
  List<ConversationTurnModel> turns = const [],
  List<McpServerModel> mcpServers = const [],
  ConversationAccountModel? account,
  ConversationRateLimitsModel? rateLimits,
  ConversationUsageModel? usage,
}) =>
    ConversationSnapshotModel(
      conversationId: 'c-1',
      sessionId: 'w-1',
      harness: 'codex',
      controllerState: controllerState,
      controllerError: controllerError,
      latestSequence: 1,
      turns: turns,
      mcpServers: mcpServers,
      account: account,
      rateLimits: rateLimits,
      usage: usage,
    );

void main() {
  late _MockChatCubit cubit;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();

    cubit = _MockChatCubit();
    when(() => cubit.state).thenReturn(const ChatReadyState(1));
    when(() => cubit.sessionId).thenReturn('w-1');
    when(() => cubit.loading).thenReturn(false);
    when(() => cubit.refreshing).thenReturn(false);
    when(() => cubit.loadingOlder).thenReturn(false);
    when(() => cubit.error).thenReturn(null);
    when(() => cubit.unavailable).thenReturn(null);
    when(() => cubit.models).thenReturn(const []);
    when(() => cubit.configOptions).thenReturn(const []);
    when(() => cubit.skills).thenReturn(const []);
    when(() => cubit.workspace).thenReturn(const WorkspacePathsModel());
    when(() => cubit.pendingSends).thenReturn(const []);
    when(() => cubit.pendingActions).thenReturn(const {});
    when(() => cubit.actionError).thenReturn(null);
    when(() => cubit.actionErrors).thenReturn(const {});
    when(() => cubit.actionCodes).thenReturn(const {});
    when(() => cubit.snapshot).thenReturn(snapshot());
  });

  Future<void> pumpBody(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<ChatCubit>.value(value: cubit, child: const ChatBody()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows a spinner before the first page arrives', (tester) async {
    when(() => cubit.loading).thenReturn(true);
    when(() => cubit.snapshot).thenReturn(null);

    await pumpBody(tester);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('explains a permanently unavailable conversation without offering a retry', (tester) async {
    when(() => cubit.snapshot).thenReturn(null);
    when(() => cubit.unavailable)
        .thenReturn(const ChatUnavailable(code: 'CHAT_RESUME_FAILED', message: 'Operator could not resume this agent.'));

    await pumpBody(tester);
    expect(find.text('Conversation unavailable'), findsOneWidget);
    expect(find.textContaining('worktree is untouched'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('offers a retry for a transient load failure', (tester) async {
    when(() => cubit.snapshot).thenReturn(null);
    when(() => cubit.error).thenReturn('Could not reach your Operator server');

    await pumpBody(tester);
    expect(find.text('Could not load conversation'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    verify(() => cubit.refresh()).called(1);
  });

  testWidgets('shows the harness, mode and context readout', (tester) async {
    when(() => cubit.snapshot).thenReturn(
      snapshot(usage: const ConversationUsageModel(contextUsed: 900, contextWindow: 1000, totalTokens: 900)),
    );

    await pumpBody(tester);
    expect(find.text('codex'), findsOneWidget);
    expect(find.text('CHAT'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
  });

  testWidgets('offers to resume a stopped controller', (tester) async {
    when(() => cubit.snapshot)
        .thenReturn(snapshot(controllerState: 'stopped', controllerError: 'The agent controller is stopped.'));

    await pumpBody(tester);
    expect(find.text('The agent controller is stopped.'), findsOneWidget);

    await tester.tap(find.text('Resume agent'));
    await tester.pumpAndSettle();
    verify(() => cubit.resumeAgent()).called(1);
  });

  testWidgets('warns that broken MCP servers are silent', (tester) async {
    when(() => cubit.snapshot).thenReturn(
      snapshot(mcpServers: const [McpServerModel(name: 'github', status: 'failed', error: 'token expired')]),
    );

    await pumpBody(tester);
    expect(find.textContaining('github (token expired) did not start'), findsOneWidget);
  });

  testWidgets('warns near the account quota', (tester) async {
    when(() => cubit.snapshot).thenReturn(
      snapshot(
        rateLimits: const ConversationRateLimitsModel(
          primaryUsedPercent: 93,
          secondaryUsedPercent: -1,
          primaryResetsInSeconds: 3600,
          planLabel: 'weekly',
        ),
      ),
    );

    await pumpBody(tester);
    expect(find.textContaining('93% of the weekly account quota is used'), findsOneWidget);
    expect(find.textContaining('resets in 1h'), findsOneWidget);
  });

  testWidgets('offers to stop or clear a running turn', (tester) async {
    when(() => cubit.snapshot).thenReturn(
      snapshot(turns: const [
        ConversationTurnModel(id: 't1', state: 'running', requestedAt: '2026-08-05T00:00:00Z'),
        ConversationTurnModel(id: 't2', state: 'queued', requestedAt: '2026-08-05T00:00:01Z'),
      ]),
    );

    await pumpBody(tester);
    expect(find.textContaining('Agent is working'), findsOneWidget);
    expect(find.textContaining('1 queued'), findsOneWidget);

    await tester.tap(find.text('Stop and clear queue'));
    await tester.pumpAndSettle();
    verify(() => cubit.interrupt()).called(1);
  });

  testWidgets('offers to retry or discard a message that never sent', (tester) async {
    when(() => cubit.pendingSends).thenReturn(
      const [PendingSend(id: 'p1', text: 'ship it', failed: true, error: 'Delivery failed')],
    );

    await pumpBody(tester);
    expect(find.textContaining('Message not sent: Delivery failed'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    verify(() => cubit.retrySend('p1')).called(1);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_body_test.dart`
Expected: FAIL — `ChatBody` does not exist.

- [ ] **Step 3: Write the banner, meta bar and live turn bar**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/inline_banner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

enum BannerTone { warning, danger, muted }

class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.tone,
    required this.icon,
    required this.text,
    this.action,
    this.secondary,
    this.onPressed,
    this.onSecondary,
  });

  final BannerTone tone;
  final IconData icon;
  final String text;
  final String? action;
  final String? secondary;
  final VoidCallback? onPressed;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final color = switch (tone) {
      BannerTone.danger => skin.red,
      BannerTone.warning => skin.amber,
      BannerTone.muted => skin.textTertiary,
    };
    final fill = switch (tone) {
      BannerTone.danger => skin.tintRed,
      BannerTone.warning => skin.tintAmber,
      BannerTone.muted => skin.bgSubtle,
    };

    return Container(
      width: double.infinity,
      color: fill,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: color),
          const HorizontalSpace(8),
          Expanded(
            child: AppText(
              text,
              style: AppTextStyle.style11Regular.copyWith(color: skin.textSecondary, height: 1.35),
              maxLines: 6,
            ),
          ),
          if (secondary != null)
            InkWell(
              onTap: onSecondary,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: AppText(
                  secondary!,
                  style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary),
                ),
              ),
            ),
          if (action != null)
            InkWell(
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: AppText(action!, style: AppTextStyle.style11Bold.copyWith(color: color)),
              ),
            ),
        ],
      ),
    );
  }
}
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_meta_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_chrome.dart';

class ChatMetaBar extends StatelessWidget {
  const ChatMetaBar({
    super.key,
    required this.snapshot,
    required this.refreshing,
    required this.compacting,
    required this.onRefresh,
    this.onCompact,
    this.compactDisabled = false,
  });

  final ConversationSnapshotModel snapshot;
  final bool refreshing;
  final bool compacting;
  final VoidCallback onRefresh;
  final VoidCallback? onCompact;
  final bool compactDisabled;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final context_ = contextReadout(
      contextUsed: snapshot.usage?.contextUsed,
      contextWindow: snapshot.usage?.contextWindow,
      totalTokens: snapshot.usage?.totalTokens,
    );
    final stateColor = switch (snapshot.controllerState) {
      'busy' => skin.orange,
      'ready' => skin.green,
      'stopped' => skin.red,
      _ => skin.amber,
    };
    final readoutColor = switch (context_?.severity) {
      Severity.critical => skin.red,
      Severity.warn => skin.amber,
      _ => skin.blue,
    };

    return Container(
      constraints: const BoxConstraints(minHeight: 37),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border(bottom: BorderSide(color: skin.borderSubtle)),
      ),
      child: Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle)),
          const HorizontalSpace(8),
          AppText(
            snapshot.harness ?? 'agent',
            style: AppTextStyle.style11SemiBold.copyWith(color: skin.textSecondary),
          ),
          const HorizontalSpace(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: skin.borderSubtle),
              borderRadius: BorderRadius.circular(5),
            ),
            child: AppText(
              'CHAT',
              style: AppTextStyle.style9Regular.copyWith(color: skin.textFaint, letterSpacing: 1),
            ),
          ),
          const Spacer(),
          if (context_?.percent != null) ...[
            SizedBox(
              width: 54,
              height: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (context_!.fillPercent ?? 0) / 100,
                  backgroundColor: skin.bgSubtle,
                  valueColor: AlwaysStoppedAnimation<Color>(readoutColor),
                ),
              ),
            ),
            const HorizontalSpace(8),
            AppText(
              '${context_.percent}%',
              style: AppTextStyle.mono10Regular.copyWith(color: readoutColor),
            ),
          ] else if (context_ != null)
            AppText(
              '${context_.tokens} tokens',
              style: AppTextStyle.mono10Regular.copyWith(color: skin.textTertiary),
            ),
          if (onCompact != null) ...[
            const HorizontalSpace(10),
            InkWell(
              onTap: compactDisabled ? null : onCompact,
              child: compacting
                  ? SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: skin.textTertiary),
                    )
                  : Icon(
                      Icons.archive_outlined,
                      size: 14,
                      color: compactDisabled ? skin.textFaint : skin.textTertiary,
                    ),
            ),
          ],
          const HorizontalSpace(10),
          InkWell(
            onTap: onRefresh,
            child: Opacity(
              opacity: refreshing ? 0.4 : 1,
              child: Icon(Icons.refresh, size: 14, color: skin.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/conversation_banners.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_chrome.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/inline_banner.dart';

class ConversationBanners extends StatelessWidget {
  const ConversationBanners({
    super.key,
    required this.snapshot,
    required this.resuming,
    required this.mcpReloading,
    required this.mcpReloadSupported,
    required this.onResume,
    required this.onReloadMcp,
    this.mcpError,
  });

  final ConversationSnapshotModel snapshot;
  final bool resuming;
  final bool mcpReloading;
  final bool mcpReloadSupported;
  final String? mcpError;
  final VoidCallback onResume;
  final VoidCallback onReloadMcp;

  @override
  Widget build(BuildContext context) {
    final thread = snapshot.threadState;
    final broken = snapshot.brokenMcpServers;
    final signIn = _signInCommand(snapshot.harness);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (snapshot.account?.reauthRequiredAt != null)
          InlineBanner(
            tone: BannerTone.danger,
            icon: Icons.key_outlined,
            text: '${snapshot.account!.reauthReason ?? "The provider rejected this session's credentials."} '
                '${signIn != null ? 'Run “$signIn” on the Operator host, then try again.' : "Sign in with the agent's CLI on the Operator host, then try again."} '
                'Operator holds no credentials of its own. The worktree is untouched.',
          ),
        if (snapshot.controllerState == 'stopped')
          InlineBanner(
            tone: BannerTone.danger,
            icon: Icons.power_settings_new,
            text: snapshot.controllerError ?? 'The agent controller is stopped.',
            action: resuming ? 'Resuming…' : 'Resume agent',
            onPressed: resuming ? null : onResume,
          ),
        if (snapshot.controllerState == 'recovering' || snapshot.controllerState == 'connecting')
          InlineBanner(
            tone: BannerTone.warning,
            icon: Icons.autorenew,
            text: snapshot.controllerState == 'recovering'
                ? 'Reconnecting to the agent…'
                : 'Starting the agent controller…',
          ),
        if (thread?.status == 'system_error')
          InlineBanner(
            tone: BannerTone.danger,
            icon: Icons.warning_amber_rounded,
            text: "The provider reports an internal fault in this thread; Operator's connection may still be healthy. "
                'The conversation and worktree are kept.'
                '${thread!.waitingOn.isEmpty ? '' : ' Waiting on: ${thread.waitingOn.join(', ')}.'}',
          )
        else if (thread?.status == 'closed')
          InlineBanner(
            tone: BannerTone.warning,
            icon: Icons.warning_amber_rounded,
            text: 'The provider closed this thread. Operator kept its history, but the agent no longer holds it.'
                '${thread!.waitingOn.isEmpty ? '' : ' Waiting on: ${thread.waitingOn.join(', ')}.'}',
          ),
        if (broken.isNotEmpty)
          InlineBanner(
            tone: BannerTone.warning,
            icon: Icons.build_outlined,
            text: '${broken.map((server) => mcpServerFailureLabel(name: server.name, failureReason: server.failureReason, error: server.error)).join(', ')}'
                ' did not start. The agent has none of their tools and will not say so—it works around them silently.'
                '${mcpError == null ? '' : ' Reload failed: $mcpError'}',
            action: mcpReloadSupported && !snapshot.hasTurnInFlight
                ? (mcpReloading ? 'Reloading…' : 'Reload')
                : null,
            onPressed: mcpReloading ? null : onReloadMcp,
          ),
      ],
    );
  }

  String? _signInCommand(String? harness) => switch (harness) {
        'codex' => 'codex login',
        'claude-code' || 'claude' => 'claude auth login',
        _ => null,
      };
}
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/live_turn_bar.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_chrome.dart';

class LiveTurnBar extends StatefulWidget {
  const LiveTurnBar({
    super.key,
    required this.snapshot,
    required this.startedAt,
    required this.stopping,
    required this.onInterrupt,
  });

  final ConversationSnapshotModel snapshot;
  final String? startedAt;
  final bool stopping;
  final VoidCallback onInterrupt;

  @override
  State<LiveTurnBar> createState() => _LiveTurnBarState();
}

class _LiveTurnBarState extends State<LiveTurnBar> {
  Timer? _tick;
  int _now = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now().millisecondsSinceEpoch),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final queued = widget.snapshot.turns.where((turn) => turn.state == 'queued').length;
    final blocked = widget.snapshot.hasPendingRequest;
    final elapsed = elapsedLabel(widget.startedAt, _now);
    final stopLabel = queued > 0 ? 'Stop and clear queue' : 'Stop turn';

    return Container(
      constraints: const BoxConstraints(minHeight: 35),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border(top: BorderSide(color: skin.borderSubtle)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.7, color: blocked ? skin.amber : skin.orange),
          ),
          const HorizontalSpace(9),
          Expanded(
            child: AppText(
              '${blocked ? 'Waiting for your input' : 'Agent is working'}'
              '${elapsed == null ? '' : ' · $elapsed'}'
              '${queued > 0 ? ' · $queued queued' : ''}',
              style: AppTextStyle.style11Regular.copyWith(color: skin.textSecondary),
            ),
          ),
          InkWell(
            onTap: widget.stopping ? null : widget.onInterrupt,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: skin.borderDefault),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stop, size: 11, color: skin.textPrimary),
                  const HorizontalSpace(5),
                  AppText(widget.stopping ? 'Stopping…' : stopLabel, style: AppTextStyle.style10SemiBold),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write the body and the screen**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_chrome.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_errors.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_meta_bar.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/conversation_banners.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/inline_banner.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/live_turn_bar.dart';

class ChatBody extends StatefulWidget {
  const ChatBody({super.key});

  @override
  State<ChatBody> createState() => ChatBodyState();
}

class ChatBodyState extends State<ChatBody> with WidgetsBindingObserver {
  int? _jumpToSequence;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<ChatCubit>().onResumed();
  }

  void jumpTo(int sequence) => setState(() => _jumpToSequence = sequence);

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        final cubit = context.read<ChatCubit>();
        final snapshot = cubit.snapshot;

        if (cubit.loading && snapshot == null) {
          return Center(child: CircularProgressIndicator(color: skin.blue));
        }

        final unavailable = cubit.unavailable;
        if (unavailable != null) {
          return _Centered(
            icon: Icons.warning_amber_rounded,
            title: 'Conversation unavailable',
            message: '${unavailable.message}\n\nThe worktree is untouched.',
          );
        }

        if (snapshot == null) {
          return _Centered(
            icon: Icons.warning_amber_rounded,
            title: 'Could not load conversation',
            message: cubit.error ?? 'The daemon did not return a conversation.',
            action: 'Retry',
            onAction: cubit.refresh,
          );
        }

        final quota = quotaWarning(
          primaryUsedPercent: snapshot.rateLimits?.primaryUsedPercent,
          secondaryUsedPercent: snapshot.rateLimits?.secondaryUsedPercent,
          primaryResetsInSeconds: snapshot.rateLimits?.primaryResetsInSeconds,
          secondaryResetsInSeconds: snapshot.rateLimits?.secondaryResetsInSeconds,
          planLabel: snapshot.rateLimits?.planLabel,
        );
        final rolledBack = snapshot.turns.where((turn) => turn.rolledBack).length;
        final compactSupported = snapshot.can('compaction') &&
            !conversationActionUnsupported('compact', cubit.actionCodes[ConversationAction.compact]);
        final mcpReloadSupported = snapshot.can('mcp_reload') &&
            !conversationActionUnsupported('mcp', cubit.actionCodes[ConversationAction.mcp]);
        final activeTurn = snapshot.activeTurn;

        return Column(
          children: [
            ChatMetaBar(
              snapshot: snapshot,
              refreshing: cubit.refreshing,
              compacting: cubit.pendingActions.contains(ConversationAction.compact),
              onRefresh: cubit.refresh,
              onCompact: compactSupported ? cubit.compact : null,
              compactDisabled: snapshot.hasTurnInFlight ||
                  snapshot.controllerState == 'stopped' ||
                  cubit.pendingActions.contains(ConversationAction.compact),
            ),
            ConversationBanners(
              snapshot: snapshot,
              resuming: false,
              mcpReloading: cubit.pendingActions.contains(ConversationAction.mcp),
              mcpReloadSupported: mcpReloadSupported,
              mcpError: cubit.actionErrors[ConversationAction.mcp],
              onResume: cubit.resumeAgent,
              onReloadMcp: cubit.reloadMcp,
            ),
            if (cubit.error != null)
              InlineBanner(
                tone: BannerTone.danger,
                icon: Icons.wifi_off,
                text: cubit.error!,
                action: 'Retry',
                onPressed: cubit.refresh,
              ),
            if (quota != null)
              InlineBanner(
                tone: quota.severity == Severity.critical ? BannerTone.danger : BannerTone.warning,
                icon: Icons.warning_amber_rounded,
                text: '${quota.percent}% of the'
                    '${quota.planLabel == null ? '' : ' ${quota.planLabel}'} account quota is used'
                    '${resetLabel(quota.resetsInSeconds) == null ? '' : '; resets in ${resetLabel(quota.resetsInSeconds)}'}. '
                    '${quota.severity == Severity.critical ? 'Turns may start failing for reasons unrelated to your request.' : 'Turns will stop when the limit is reached.'}',
              ),
            if (cubit.actionError != null)
              InlineBanner(tone: BannerTone.danger, icon: Icons.error_outline, text: cubit.actionError!),
            if (rolledBack > 0)
              InlineBanner(
                tone: BannerTone.muted,
                icon: Icons.settings_backup_restore,
                text: '$rolledBack ${rolledBack == 1 ? 'turn was' : 'turns were'} rolled back. '
                    'The agent no longer remembers ${rolledBack == 1 ? 'it' : 'them'}.',
              ),
            for (final pending in cubit.pendingSends)
              if (pending.failed)
                InlineBanner(
                  tone: BannerTone.danger,
                  icon: Icons.send_outlined,
                  text: 'Message not sent: ${pending.error ?? 'Delivery failed'}',
                  action: 'Retry',
                  secondary: 'Discard',
                  onPressed: () => cubit.retrySend(pending.id),
                  onSecondary: () => cubit.discardSend(pending.id),
                ),
            Expanded(
              child: ChatTimeline(
                snapshot: snapshot,
                loadingOlder: cubit.loadingOlder,
                onLoadOlder: cubit.loadOlder,
                approvalPending: cubit.pendingActions.contains(ConversationAction.approval),
                inputPending: cubit.pendingActions.contains(ConversationAction.input),
                onDecide: cubit.resolveApproval,
                onResolveInput: cubit.resolveInput,
                onRollback: cubit.rollback,
                jumpToSequence: _jumpToSequence,
                onJumpHandled: () => setState(() => _jumpToSequence = null),
              ),
            ),
            if (activeTurn != null)
              LiveTurnBar(
                snapshot: snapshot,
                startedAt: activeTurn.startedAt ?? activeTurn.requestedAt,
                stopping: cubit.pendingActions.contains(ConversationAction.interrupt),
                onInterrupt: cubit.interrupt,
              ),
            ChatComposer(
              sessionId: cubit.sessionId,
              snapshot: snapshot,
              skills: cubit.skills,
              filePaths: cubit.workspace.paths,
              filePathsTruncated: cubit.workspace.truncated,
              configOptions: cubit.configOptions,
              steerUnavailable:
                  conversationActionUnsupported('steer', cubit.actionCodes[ConversationAction.steer]),
              pending: cubit.pendingSends.any((pending) => !pending.failed),
              error: cubit.actionErrors[ConversationAction.steer],
              onSend: (text, {attachments, resources}) =>
                  cubit.send(text, attachments: attachments, resources: resources),
              onSteer: cubit.steer,
              onInterrupt: cubit.interrupt,
              onOpenSettings: () => ChatScreenActions.of(context)?.openSettings(),
            ),
          ],
        );
      },
    );
  }
}

abstract class ChatScreenActions {
  void openSettings();

  static ChatScreenActions? of(BuildContext context) =>
      context.findAncestorWidgetOfExactType<ChatScreenActionsScope>()?.actions;
}

class ChatScreenActionsScope extends InheritedWidget {
  const ChatScreenActionsScope({super.key, required this.actions, required super.child});

  final ChatScreenActions actions;

  @override
  bool updateShouldNotify(ChatScreenActionsScope oldWidget) => actions != oldWidget.actions;
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.title, this.message, this.action, this.onAction});

  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 38),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: skin.amber),
            const VerticalSpace(12),
            AppText(title, style: AppTextStyle.style17SemiBold, maxLines: 2, textAlign: TextAlign.center),
            if (message != null) ...[
              const VerticalSpace(8),
              AppText(
                message!,
                style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
                maxLines: 6,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const VerticalSpace(16),
              PrimaryButton(text: action!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}
```

`PrimaryButton`'s label parameter is `text`, not `title` — verified against
`core/widgets/main_widgets/primary_button.dart` as it stands at the start of this milestone.

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/chat_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_settings_sheet.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/conversation_map_sheet.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_errors.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.sessionId, required this.title, this.projectId});

  final String sessionId;
  final String title;
  final String? projectId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> implements ChatScreenActions {
  final GlobalKey<ChatBodyState> _body = GlobalKey<ChatBodyState>();
  late final ChatCubit _cubit = sl<ChatCubit>(param1: widget.sessionId);

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  void openSettings() {
    final snapshot = _cubit.snapshot;
    if (snapshot == null) return;
    showChatSettingsSheet(
      context,
      snapshot: snapshot,
      models: _cubit.models,
      options: _cubit.configOptions,
      disabled: snapshot.controllerState == 'stopped' ||
          _cubit.pendingActions.contains(ConversationAction.settings) ||
          _cubit.pendingActions.contains(ConversationAction.config),
      error: _cubit.actionErrors[ConversationAction.settings] ??
          _cubit.actionErrors[ConversationAction.config],
      onSettings: _cubit.chooseSettings,
      onOption: _cubit.setConfigOption,
    );
  }

  Future<void> _openMenu() async {
    final snapshot = _cubit.snapshot;
    if (snapshot == null) return;

    final result = await showConversationMenuSheet(
      context,
      snapshot: snapshot,
      compactSupported: snapshot.can('compaction') &&
          !conversationActionUnsupported('compact', _cubit.actionCodes[ConversationAction.compact]),
      mcpReloadSupported: snapshot.can('mcp_reload') &&
          !conversationActionUnsupported('mcp', _cubit.actionCodes[ConversationAction.mcp]),
      compacting: _cubit.pendingActions.contains(ConversationAction.compact),
      mcpReloading: _cubit.pendingActions.contains(ConversationAction.mcp),
    );
    if (!mounted || result == null) return;

    switch (result.action) {
      case ConversationMenuAction.map:
        final sequence = await showConversationMapSheet(
          context,
          markers: conversationMarkers(snapshot),
        );
        if (sequence != null) _body.currentState?.jumpTo(sequence);
      case ConversationMenuAction.pullRequests:
        if (widget.projectId != null) sl<SessionsCubit>().setActiveProject(widget.projectId!);
        HomeShell.selectedTab.value = 2;
        if (mounted) Navigator.of(context).pop();
      case ConversationMenuAction.settings:
        openSettings();
      case ConversationMenuAction.compact:
        await _cubit.compact();
      case ConversationMenuAction.reloadMcp:
        await _cubit.reloadMcp();
      case ConversationMenuAction.rename:
        if (result.title != null) await _cubit.rename(result.title!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _cubit.snapshot?.title ?? widget.title;
    return BlocProvider<ChatCubit>.value(
      value: _cubit,
      child: ChatScreenActionsScope(
        actions: this,
        child: Scaffold(
          backgroundColor: context.skin.bgBase,
          appBar: GlobalAppbar.sub(
            titleText: title.length > 24 ? '${title.substring(0, 22)}…' : title,
            actions: [
              IconButton(
                onPressed: _openMenu,
                icon: Icon(Icons.more_horiz, color: context.skin.textSecondary),
              ),
            ],
          ),
          body: ChatBody(key: _body),
        ),
      ),
    );
  }
}
```

`_cubit.close()` is called from `dispose` because the cubit is created by
`sl<ChatCubit>(param1: ...)` rather than by a `BlocProvider(create:)`, so nothing else owns its
lifetime. `BlocProvider.value` deliberately does **not** close what it is given.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_body_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 575/575 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): assemble the chat screen"
```

---

### Task 26: Opening a session from the board, the PRs tab and the orchestrator tab

**Files:**
- Create: `packages/mobile/lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart`
- Modify: `packages/mobile/lib/core/app_routes/routes_strings.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart`
- Modify: `packages/mobile/lib/core/app_routes/home_shell.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart`
- Modify: `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pr_card.dart`
- Modify: `packages/mobile/lib/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pull_requests_body.dart`
- Modify: `packages/mobile/lib/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_card.dart`
- Modify: `packages/mobile/lib/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_body.dart`
- Modify: `packages/mobile/lib/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart`
- Modify: `packages/mobile/test/feature/pull_request/presentation/pull_requests_screen/ui/pr_card_test.dart`
- Modify: `packages/mobile/test/feature/orchestrator/presentation/orchestrator_screen/ui/orchestrator_card_test.dart`
- Test: `packages/mobile/test/feature/sessions/presentation/session_route/session_route_screen_test.dart`

**Interfaces:**
- Consumes: `SessionsCubit` singleton, `ChatScreen` (Task 25).
- Produces:
  - `RoutesStrings.session = '/session'`
  - `class SessionRouteScreen extends StatefulWidget` — `sessionId`
  - `HomeShell.selectedTab` (`static final ValueNotifier<int>`)
  - `SessionCard`, `PrCard` and `OrchestratorCard` gain a working open action

**The committed session mode is daemon-authoritative.** The board's cached session supplies the
fast path; a missing row triggers one board refresh and waits, rather than guessing. Guessing
either way is wrong in a specific, damaging manner: guessing Chat attaches a chat controller to a
PTY session, and guessing Terminal shows a terminal for a session that has none.

Until M4 lands the terminal, the `tui` branch renders an honest panel saying so. That is not a
stub of a missing feature — it is the accurate state of this build, and it replaces the M2-era
situation where the buttons simply did not exist.

Three M2 tests assert those buttons' **absence** and must be updated here rather than deleted:
`pr_card_test.dart`'s "offers no session action, because no session screen exists yet" and
`orchestrator_card_test.dart`'s "offers no open action, because no session screen exists yet".
Their replacements assert that the action now exists and reports the session id.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/feature/sessions/presentation/session_route/session_route_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/session_route/ui/session_route_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();

    repository = _MockSessionsRepository();
    mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
  });

  Future<void> pumpRoute(WidgetTester tester, {required List<SessionModel> sessions}) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: BoardSnapshot(sessions: sessions))),
    );

    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: BlocProvider(
              create: (_) => SessionsCubit(repository, mux),
              child: const SessionRouteScreen(sessionId: 'w-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
  }

  testWidgets('says a TUI session needs a build that has the terminal', (tester) async {
    await pumpRoute(tester, sessions: const [SessionModel(id: 'w-1', projectId: 'p', mode: 'tui')]);
    expect(find.textContaining('Terminal UI'), findsOneWidget);
  });

  testWidgets('reports a session the daemon does not have', (tester) async {
    await pumpRoute(tester, sessions: const []);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Session not found.'), findsOneWidget);
  });
}
```

Testing the `chat` branch end to end would require a live `ChatCubit` from the service locator, so
the chat path is covered by Task 25's body test and by the card tests below; this test pins the
two branches the route decides on its own.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/sessions/presentation/session_route/session_route_screen_test.dart`
Expected: FAIL — `SessionRouteScreen` does not exist.

- [ ] **Step 3: Write the route screen**

`packages/mobile/lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_empty_state.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/chat_screen.dart';
import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

class SessionRouteScreen extends StatefulWidget {
  const SessionRouteScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SessionRouteScreen> createState() => _SessionRouteScreenState();
}

class _SessionRouteScreenState extends State<SessionRouteScreen> {
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<SessionsCubit>();
    if (_lookup(cubit) == null) {
      _resolving = true;
      cubit.refresh().whenComplete(() {
        if (mounted) setState(() => _resolving = false);
      });
    }
  }

  ({String id, String? mode, String title, String? projectId})? _lookup(SessionsCubit cubit) {
    for (final session in cubit.sessions) {
      if (session.id == widget.sessionId) {
        return (
          id: session.id!,
          mode: session.mode,
          title: sessionTitle(session),
          projectId: session.projectId,
        );
      }
    }
    for (final orchestrator in cubit.orchestrators) {
      if (orchestrator.id == widget.sessionId) {
        return (
          id: orchestrator.id!,
          mode: orchestrator.mode,
          title: orchestrator.projectName ?? orchestrator.id!,
          projectId: orchestrator.projectId,
        );
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionsCubit, SessionsState>(
      builder: (context, state) {
        final session = _lookup(context.read<SessionsCubit>());

        if (session?.mode == 'chat') {
          return ChatScreen(
            sessionId: session!.id,
            title: session.title,
            projectId: session.projectId,
          );
        }

        return Scaffold(
          backgroundColor: context.skin.bgBase,
          appBar: GlobalAppbar.sub(titleText: session?.title ?? 'Session'),
          body: session?.mode == 'tui'
              ? const AppEmptyState(
                  icon: Icons.terminal,
                  title: 'Terminal UI is not in this build yet',
                  message: 'This session runs in the agent\'s terminal interface. '
                      'Open it from the Operator desktop app until the phone can render it.',
                )
              : _resolving
                  ? Center(child: CircularProgressIndicator(color: context.skin.blue))
                  : const AppEmptyState(
                      icon: Icons.help_outline,
                      title: 'Session not found.',
                      message: 'The daemon no longer lists this session.',
                    ),
        );
      },
    );
  }
}
```

The `Session not found.` string is the exact copy `app/session/[id].tsx` shows, and the test above
matches on it, so keep it verbatim including the period.

- [ ] **Step 4: Route it and give the shell an addressable tab**

In `packages/mobile/lib/core/app_routes/routes_strings.dart`:

```dart
  static const String session = '/session';
```

In `packages/mobile/lib/core/app_routes/app_router.dart`, before `default:`:

```dart
      case RoutesStrings.session:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (context) => BlocProvider.value(
            value: sl<SessionsCubit>(),
            child: SessionRouteScreen(sessionId: args?['sessionId'] as String? ?? ''),
          ),
          settings: settings,
        );
```

In `packages/mobile/lib/core/app_routes/home_shell.dart`, replace the `_index` field with a
listener on a static notifier, so the chat menu's "Pull requests" row can select the PRs tab:

```dart
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static final ValueNotifier<int> selectedTab = ValueNotifier<int>(0);
  ...
}
```

and in the state:

```dart
  @override
  void initState() {
    super.initState();
    HomeShell.selectedTab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    HomeShell.selectedTab.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() => setState(() {});
```

with `index: HomeShell.selectedTab.value` on the `IndexedStack`,
`currentIndex: HomeShell.selectedTab.value` on the `BottomNavigationBar`, and
`onTap: (next) => HomeShell.selectedTab.value = next`. The existing `home_shell_test.dart` asserts
`currentIndex` and tab switching, so it keeps passing — but reset `HomeShell.selectedTab.value = 0`
in that file's `setUp`, because a static notifier now outlives a single test.

- [ ] **Step 5: Wire the three entry points**

In `sessions_body.dart`, replace both `onTap: () {}` placeholders:

```dart
                      onTap: () => Navigator.of(context).pushNamed(
                        RoutesStrings.session,
                        arguments: {'sessionId': session.id},
                      ),
```

In `pr_card.dart`, add `this.onOpenSession` to the constructor and the field
`final VoidCallback? onOpenSession;`, then put the action **before** the existing GitHub
`IconButton` in that same `Row` (its tooltip is what both the old and new tests match on):

```dart
              if (onOpenSession != null)
                IconButton(
                  icon: const Icon(Icons.forum_outlined),
                  tooltip: 'Open session',
                  onPressed: onOpenSession,
                ),
```

In `pull_requests_body.dart`, pass it at the `PrCard(...)` call site:

```dart
                    onOpenSession: () => Navigator.of(context).pushNamed(
                      RoutesStrings.session,
                      arguments: {'sessionId': entry.session.id},
                    ),
```

In `orchestrator_card.dart`, add `this.onOpen` to the constructor and
`final VoidCallback? onOpen;` to the widget, then put the action before the launch/restart control
in the `Row` that already holds the worker count:

```dart
              if (widget.onOpen != null)
                IconButton(
                  icon: const Icon(Icons.forum_outlined),
                  tooltip: 'Open orchestrator',
                  onPressed: widget.onOpen,
                ),
```

In `orchestrator_body.dart`, pass it at the `OrchestratorCard(...)` call site with the
orchestrator's id:

```dart
              onOpen: link.id == null
                  ? null
                  : () => Navigator.of(context).pushNamed(
                        RoutesStrings.session,
                        arguments: {'sessionId': link.id},
                      ),
```

In `spawn_body.dart`, on `SpawnSuccessState`, replace the current pop-only behavior with a pop
followed by opening the new session:

```dart
        if (state is SpawnSuccessState) {
          Navigator.of(context).pop();
          Navigator.of(context).pushNamed(
            RoutesStrings.session,
            arguments: {'sessionId': state.session.id},
          );
        }
```

Do the same for `LaunchSuccessState` in `orchestrator_body.dart`. Both destinations resolve the
mode themselves, so a TUI-mode spawn lands on the honest terminal panel rather than a wrong screen.

- [ ] **Step 6: Update the two tests that assert the buttons' absence**

In `pr_card_test.dart`, give `pumpCard` a `VoidCallback? onOpenSession` parameter, pass it to
`PrCard`, and replace the `offers no session action` test with:

```dart
  testWidgets('opens the session behind the pull request', (tester) async {
    var opened = 0;
    await pumpCard(tester, onOpenSession: () => opened++);

    expect(find.byTooltip('Open in GitHub'), findsOneWidget);
    await tester.tap(find.byTooltip('Open session'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
```

In `orchestrator_card_test.dart`, give `pumpCard` a `VoidCallback? onOpen` parameter, pass it to
`OrchestratorCard`, and replace `offers no open action` with:

```dart
  testWidgets('opens the orchestrator session', (tester) async {
    var opened = 0;
    await pumpCard(
      tester,
      link: const OrchestratorModel(id: 'o1', projectId: 'p'),
      workers: const [],
      onOpen: () => opened++,
    );

    await tester.tap(find.byTooltip('Open orchestrator'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 580/580 green.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): open a chat session from the board, PRs and orchestrator"
```

---

## Milestone verification

M3 is done when, from `packages/mobile`:

- `flutter analyze` → "No issues found!"
- `flutter test` → 580/580 green
- On a real phone against a real daemon: tapping a chat-mode session on the Agents tab opens its
  conversation; the timeline renders past turns; sending a message appears without a manual
  refresh; a running turn shows the live bar and can be stopped; an approval can be answered; turn
  settings can be changed; the composer's `/` and `@` pickers list skills and worktree files.

The spec's ledger rows closed here:

| Ledger row | Landed as |
|---|---|
| `chat/ChatMarkdown.test.ts` | `test/feature/chat/logic/chat_markdown_test.dart` (Task 5) |
| `chat/ansi.test.ts` | `test/feature/chat/logic/ansi_test.dart` (Task 4) |
| `chat/composerSuggestions.test.ts` | `test/feature/chat/logic/composer_suggestions_test.dart` (Task 9) |
| `chat/conversationAction.test.ts` | `test/feature/chat/logic/conversation_action_test.dart` (Task 3) |
| `chat/conversationChrome.test.ts` | `test/feature/chat/logic/conversation_chrome_test.dart` (Task 7) |
| `chat/elicitationModel.test.ts` | `test/feature/chat/logic/elicitation_model_test.dart` (Task 8) |
| `chat/snapshot.test.ts` | `test/feature/chat/logic/snapshot_test.dart` (Task 12) |
| `chat/sse.test.ts` | `test/feature/chat/data/sse_test.dart` (Task 2) |
| `chat/syntaxHighlight.test.ts` | `test/feature/chat/logic/syntax_highlight_test.dart` (Task 6) |
| `chat/timelineModel.test.ts` | `test/feature/chat/logic/timeline_model_test.dart` (Task 13) |
| `chatModeApi.test.ts` | `test/feature/chat/data/model/conversation_snapshot_model_test.dart` + `chat_remote_data_source_test.dart` (Tasks 11, 14) |
| `session/keyboardInset.test.ts` | `test/feature/chat/logic/keyboard_inset_test.dart` (Task 10) — `dockInset` half only; `CONTROL_KEYS` is M4 |

Left open for M4: `session/sendRoute.test.ts`, the `CONTROL_KEYS` half of
`session/keyboardInset.test.ts`, the interface-transition handoff, and the worktree shell.
