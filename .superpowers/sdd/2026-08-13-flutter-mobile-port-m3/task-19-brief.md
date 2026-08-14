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

- [x] **Step 1: Write the failing test**

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

- [x] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/logic/chat_cubit_stream_test.dart`
Expected: FAIL — `configStore`, `refreshDebounce` and `onResumed` are not defined.

- [x] **Step 3: Extend the constructor**

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

- [x] **Step 4: Add the stream loop**

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

- [x] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/logic/`
Expected: PASS — all three cubit test files.

- [x] **Step 6: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 530/530 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): stream live conversation updates into ChatCubit"
```

---
