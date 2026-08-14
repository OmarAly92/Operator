import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
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

class _FakeCancelToken extends Fake implements CancelToken {}

void main() {
  late _MockChatRepository repository;
  late _MockConfigStore configStore;
  late StreamController<ConversationEventModel> events;

  const config = ServerConfig(
    host: 'opr.test',
    httpPort: '3011',
    secure: false,
    password: 'secret12',
  );

  setUpAll(() {
    registerFallbackValue(_FakeCancelToken());
  });

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();

    repository = _MockChatRepository();
    configStore = _MockConfigStore();
    events = StreamController<ConversationEventModel>.broadcast();

    when(() => configStore.current).thenReturn(config);
    when(
      () => repository.getConversationPage('w-1', beforeSequence: null),
    ).thenAnswer(
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
    when(() => repository.getModels(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: <ChatModelModel>[])),
    );
    when(() => repository.getConfigOptions(any())).thenAnswer(
      (_) async =>
          Result.success(GlobalResponse(data: <ChatConfigOptionModel>[])),
    );
    when(() => repository.getSkills(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: <ChatSkillModel>[])),
    );
    when(() => repository.getWorkspacePaths(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: WorkspacePathsModel())),
    );
    when(
      () => repository.events(
        after: any(named: 'after'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) => events.stream);
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
        events.add(
          ConversationEventModel(
            seq: seq,
            sessionId: 'w-1',
            payload: const {'conversationId': 'c-1'},
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    },
    verify: (_) => verify(
      () => repository.getConversationPage('w-1', beforeSequence: null),
    ).called(2),
  );

  blocTest<ChatCubit, ChatState>(
    'ignores events for other sessions and events with no conversation',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      events.add(
        const ConversationEventModel(
          seq: 2,
          sessionId: 'other',
          payload: {'conversationId': 'c-9'},
        ),
      );
      events.add(const ConversationEventModel(seq: 3, sessionId: 'w-1'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    },
    verify: (_) => verify(
      () => repository.getConversationPage('w-1', beforeSequence: null),
    ).called(1),
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
      await CacheHelper.save(
        CacheKeys.chatEventCursor('opr.test', '3011', 'w-1'),
        41,
      );
    },
    build: build,
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 10)),
    verify: (_) => verify(
      () =>
          repository.events(after: 41, cancelToken: any(named: 'cancelToken')),
    ).called(1),
  );

  blocTest<ChatCubit, ChatState>(
    'reconnects after the stream drops',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      events.addError(
        ServerFailure(error: 'dropped', message: 'stream closed'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
    },
    verify: (_) => verify(
      () => repository.events(
        after: any(named: 'after'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(greaterThan(1)),
  );

  blocTest<ChatCubit, ChatState>(
    'reloads when the app returns to the foreground',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.onResumed();
    },
    verify: (_) => verify(
      () => repository.getConversationPage('w-1', beforeSequence: null),
    ).called(2),
  );

  blocTest<ChatCubit, ChatState>(
    'never opens a stream for a conversation that is permanently unavailable',
    build: () {
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(
            error: 'x',
            message: 'gone',
            apiStatus: 'SESSION_NOT_FOUND',
          ),
        ),
      );
      return build();
    },
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 40)),
    verify: (_) => verifyNever(
      () => repository.events(
        after: any(named: 'after'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ),
  );
}
