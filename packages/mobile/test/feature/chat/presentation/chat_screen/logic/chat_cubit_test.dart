import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockChatRepository extends Mock implements ChatRepository {}

class _MockConfigStore extends Mock implements ServerConfigStore {}

class _FakeCancelToken extends Fake implements CancelToken {}

typedef _ConversationPageResult =
    Result<GlobalResponse<ConversationSnapshotModel>, Failure>;

ConversationSnapshotModel page({
  String conversationId = 'c-1',
  int oldestSequence = 1,
  bool hasMoreBefore = false,
  List<ConversationItemModel> items = const [],
  List<String> capabilities = const [],
}) => ConversationSnapshotModel(
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
  late _MockConfigStore configStore;
  late StreamController<ConversationEventModel> events;
  late Completer<_ConversationPageResult> olderPageResponse;
  late Completer<_ConversationPageResult> firstRefreshResponse;
  late Completer<_ConversationPageResult> secondRefreshResponse;

  setUpAll(() {
    registerFallbackValue(_FakeCancelToken());
  });

  void stubIdleCatalogs() {
    when(() => repository.getModels(any())).thenAnswer(
      (_) async =>
          Result.success(const GlobalResponse(data: <ChatModelModel>[])),
    );
    when(() => repository.getConfigOptions(any())).thenAnswer(
      (_) async =>
          Result.success(const GlobalResponse(data: <ChatConfigOptionModel>[])),
    );
    when(() => repository.getSkills(any())).thenAnswer(
      (_) async =>
          Result.success(const GlobalResponse(data: <ChatSkillModel>[])),
    );
    when(() => repository.getWorkspacePaths(any())).thenAnswer(
      (_) async =>
          Result.success(const GlobalResponse(data: WorkspacePathsModel())),
    );
  }

  ChatCubit build() => ChatCubit(
    repository,
    'w-1',
    configStore: configStore,
    configPoll: const Duration(milliseconds: 20),
    skillPoll: const Duration(milliseconds: 40),
    workspacePoll: const Duration(milliseconds: 60),
  );

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    repository = _MockChatRepository();
    configStore = _MockConfigStore();
    events = StreamController<ConversationEventModel>.broadcast();
    when(() => configStore.current).thenReturn(
      const ServerConfig(
        host: 'opr.test',
        httpPort: '3011',
        secure: false,
        password: 'secret12',
      ),
    );
    when(
      () => repository.events(
        after: any(named: 'after'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) => events.stream);
    stubIdleCatalogs();
  });

  tearDown(() => events.close());

  blocTest<ChatCubit, ChatState>(
    'loads the live page and clears the loading flag',
    build: () {
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: page(items: [message('m1', 1)])),
        ),
      );
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
    'treats a permanent code as unavailable',
    build: () {
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(
            error: 'x',
            message: 'Operator could not resume this agent.',
            apiStatus: 'CHAT_RESUME_FAILED',
          ),
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
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(
            error: 'x',
            message: 'Could not reach your Operator server',
          ),
        ),
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
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(
            data: page(
              oldestSequence: 3,
              hasMoreBefore: true,
              items: [message('m3', 3)],
            ),
          ),
        ),
      );
      when(
        () => repository.getConversationPage('w-1', beforeSequence: 3),
      ).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: page(items: [message('m1', 1)])),
        ),
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
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) async => Result.success(GlobalResponse(data: page())));
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.loadOlder();
    },
    verify: (_) => verifyNever(
      () => repository.getConversationPage(
        'w-1',
        beforeSequence: any(named: 'beforeSequence', that: isNotNull),
      ),
    ),
  );

  blocTest<ChatCubit, ChatState>(
    'drops every cached page when the conversation identity changes',
    build: () {
      var call = 0;
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) async {
        call += 1;
        return Result.success(
          GlobalResponse(
            data: call == 1
                ? page(
                    oldestSequence: 3,
                    hasMoreBefore: true,
                    items: [message('m3', 3)],
                  )
                : page(conversationId: 'c-2', items: [message('n1', 1)]),
          ),
        );
      });
      when(
        () => repository.getConversationPage('w-1', beforeSequence: 3),
      ).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: page(items: [message('m1', 1)])),
        ),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.loadOlder();
      await cubit.refresh();
    },
    verify: (cubit) =>
        expect(cubit.snapshot!.items.map((item) => item.id), ['n1']),
  );

  blocTest<ChatCubit, ChatState>(
    'discards an older page when the live conversation changes while it loads',
    build: () {
      var liveCalls = 0;
      olderPageResponse = Completer<_ConversationPageResult>();
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) async {
        liveCalls += 1;
        return Result.success(
          GlobalResponse(
            data: liveCalls == 1
                ? page(
                    oldestSequence: 3,
                    hasMoreBefore: true,
                    items: [message('m3', 3)],
                  )
                : page(conversationId: 'c-2', items: [message('n1', 1)]),
          ),
        );
      });
      when(
        () => repository.getConversationPage('w-1', beforeSequence: 3),
      ).thenAnswer((_) => olderPageResponse.future);
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      final pagination = cubit.loadOlder();
      await Future<void>.delayed(Duration.zero);
      await cubit.refresh();
      olderPageResponse.complete(
        Result.success(GlobalResponse(data: page(items: [message('m1', 1)]))),
      );
      await pagination;
    },
    verify: (cubit) {
      expect(cubit.snapshot!.conversationId, 'c-2');
      expect(cubit.snapshot!.items.map((item) => item.id), ['n1']);
      expect(cubit.loadingOlder, isFalse);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'discards a stale refresh that completes after a newer refresh',
    build: () {
      firstRefreshResponse = Completer<_ConversationPageResult>();
      secondRefreshResponse = Completer<_ConversationPageResult>();
      var calls = 0;
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) {
        calls += 1;
        return calls == 1
            ? firstRefreshResponse.future
            : secondRefreshResponse.future;
      });
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      final newerRefresh = cubit.refresh();
      secondRefreshResponse.complete(
        Result.success(
          GlobalResponse(
            data: page(conversationId: 'c-2', items: [message('n1', 1)]),
          ),
        ),
      );
      await newerRefresh;
      firstRefreshResponse.complete(
        Result.success(GlobalResponse(data: page(items: [message('m1', 1)]))),
      );
      await Future<void>.delayed(Duration.zero);
    },
    verify: (cubit) {
      expect(cubit.snapshot!.conversationId, 'c-2');
      expect(cubit.snapshot!.items.map((item) => item.id), ['n1']);
      expect(cubit.refreshing, isFalse);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'reads the model list only when the provider owns no config options',
    build: () {
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) async => Result.success(GlobalResponse(data: page())));
      when(() => repository.getModels('w-1')).thenAnswer(
        (_) async => Result.success(
          const GlobalResponse(
            data: [ChatModelModel(id: 'opus', displayName: 'Opus')],
          ),
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
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: page(capabilities: const ['config_options'])),
        ),
      );
      when(() => repository.getConfigOptions('w-1')).thenAnswer(
        (_) async => Result.success(
          const GlobalResponse(
            data: [
              ChatConfigOptionModel(id: 'fast', name: 'Fast', type: 'boolean'),
            ],
          ),
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
    'switches from models to provider config without resetting session catalogs',
    build: () {
      var calls = 0;
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) async {
        calls += 1;
        return Result.success(
          GlobalResponse(
            data: page(
              capabilities: calls == 1 ? const [] : const ['config_options'],
            ),
          ),
        );
      });
      when(() => repository.getModels('w-1')).thenAnswer(
        (_) async => Result.success(
          const GlobalResponse(
            data: [ChatModelModel(id: 'opus', displayName: 'Opus')],
          ),
        ),
      );
      when(() => repository.getConfigOptions('w-1')).thenAnswer(
        (_) async => Result.success(
          const GlobalResponse(
            data: [ChatConfigOptionModel(id: 'fast', name: 'Fast')],
          ),
        ),
      );
      when(() => repository.getSkills('w-1')).thenAnswer(
        (_) async => Result.success(
          const GlobalResponse(
            data: [ChatSkillModel(name: 'review', displayName: 'Review')],
          ),
        ),
      );
      when(() => repository.getWorkspacePaths('w-1')).thenAnswer(
        (_) async => Result.success(
          const GlobalResponse(
            data: WorkspacePathsModel(paths: ['lib/a.dart']),
          ),
        ),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.refresh();
      await Future<void>.delayed(Duration.zero);
    },
    verify: (cubit) {
      expect(cubit.models, isEmpty);
      expect(cubit.configOptions.single.id, 'fast');
      expect(cubit.skills.single.name, 'review');
      expect(cubit.workspace.paths, ['lib/a.dart']);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'switches from provider config to models without resetting session catalogs',
    build: () {
      var calls = 0;
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) async {
        calls += 1;
        return Result.success(
          GlobalResponse(
            data: page(
              capabilities: calls == 1 ? const ['config_options'] : const [],
            ),
          ),
        );
      });
      when(() => repository.getModels('w-1')).thenAnswer(
        (_) async => Result.success(
          const GlobalResponse(
            data: [ChatModelModel(id: 'opus', displayName: 'Opus')],
          ),
        ),
      );
      when(() => repository.getConfigOptions('w-1')).thenAnswer(
        (_) async => Result.success(
          const GlobalResponse(
            data: [ChatConfigOptionModel(id: 'fast', name: 'Fast')],
          ),
        ),
      );
      when(() => repository.getSkills('w-1')).thenAnswer(
        (_) async => Result.success(
          const GlobalResponse(
            data: [ChatSkillModel(name: 'review', displayName: 'Review')],
          ),
        ),
      );
      when(() => repository.getWorkspacePaths('w-1')).thenAnswer(
        (_) async => Result.success(
          const GlobalResponse(
            data: WorkspacePathsModel(paths: ['lib/a.dart']),
          ),
        ),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.refresh();
      await Future<void>.delayed(Duration.zero);
    },
    verify: (cubit) {
      expect(cubit.configOptions, isEmpty);
      expect(cubit.models.single.id, 'opus');
      expect(cubit.skills.single.name, 'review');
      expect(cubit.workspace.paths, ['lib/a.dart']);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'keeps the conversation when an optional catalog fails',
    build: () {
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: page(items: [message('m1', 1)])),
        ),
      );
      when(() => repository.getSkills('w-1')).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(error: 'x', message: 'no skills route'),
        ),
      );
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
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) async => Result.success(GlobalResponse(data: page())));
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
    act: (cubit) => Future<void>.delayed(const Duration(milliseconds: 120)),
    verify: (_) {
      verifyNever(() => repository.getSkills(any()));
      verifyNever(() => repository.getWorkspacePaths(any()));
    },
  );

  test('stops existing catalog timers after becoming unavailable', () {
    fakeAsync((async) {
      var conversationCalls = 0;
      var skillCalls = 0;
      var workspaceCalls = 0;
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) async {
        conversationCalls += 1;
        if (conversationCalls == 1) {
          return Result.success(GlobalResponse(data: page()));
        }
        return Result.failure(
          ServerFailure(
            error: 'x',
            message: 'gone',
            apiStatus: 'SESSION_NOT_FOUND',
          ),
        );
      });
      when(() => repository.getSkills('w-1')).thenAnswer((_) async {
        skillCalls += 1;
        return Result.success(const GlobalResponse(data: <ChatSkillModel>[]));
      });
      when(() => repository.getWorkspacePaths('w-1')).thenAnswer((_) async {
        workspaceCalls += 1;
        return Result.success(
          const GlobalResponse(data: WorkspacePathsModel()),
        );
      });

      final cubit = ChatCubit(
        repository,
        'w-1',
        configStore: configStore,
        skillPoll: const Duration(milliseconds: 10),
        workspacePoll: const Duration(milliseconds: 10),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 20));
      async.flushMicrotasks();

      unawaited(cubit.refresh());
      async.flushMicrotasks();
      final skillCallsAfterFailure = skillCalls;
      final workspaceCallsAfterFailure = workspaceCalls;

      async.elapse(const Duration(milliseconds: 50));
      async.flushMicrotasks();

      expect(skillCalls, skillCallsAfterFailure);
      expect(workspaceCalls, workspaceCallsAfterFailure);
      unawaited(cubit.close());
    });
  });

  test('immediate close prevents every scheduled repository request', () async {
    when(
      () => repository.getConversationPage('w-1', beforeSequence: null),
    ).thenAnswer((_) async => Result.success(GlobalResponse(data: page())));

    final cubit = build();
    await cubit.close();
    await Future<void>.delayed(Duration.zero);

    verifyNever(
      () => repository.getConversationPage('w-1', beforeSequence: null),
    );
    verifyNever(() => repository.getModels(any()));
    verifyNever(() => repository.getConfigOptions(any()));
    verifyNever(() => repository.getSkills(any()));
    verifyNever(() => repository.getWorkspacePaths(any()));
  });
}
