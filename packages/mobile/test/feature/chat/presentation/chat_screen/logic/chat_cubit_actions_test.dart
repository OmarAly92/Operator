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
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
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
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../core/telemetry/telemetry_test.dart' show RecordingClient;

class _MockChatRepository extends Mock implements ChatRepository {}

class _MockConfigStore extends Mock implements ServerConfigStore {}

class _FakeCancelToken extends Fake implements CancelToken {}

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
  late _MockConfigStore configStore;
  late StreamController<ConversationEventModel> events;
  late Completer<Result<bool, Failure>> compactResponse;
  late Completer<Result<bool, Failure>> interruptResponse;
  late Completer<Result<GlobalResponse<ConversationSnapshotModel>, Failure>>
  rollbackRefreshResponse;
  late Completer<Result<GlobalResponse<ConversationSnapshotModel>, Failure>>
  rollbackOlderResponse;
  late Completer<Result<GlobalResponse<ConversationSnapshotModel>, Failure>>
  actionRefreshResponse;
  late Completer<Result<GlobalResponse<List<ChatConfigOptionModel>>, Failure>>
  configResponse;
  late Completer<Result<bool, Failure>> resumeResponse;
  late Completer<Result<List<String>, Failure>> stageRetryResponse;
  late bool stagingRetryFailedState;
  late String stagingFailedPendingId;
  late Completer<Result<GlobalResponse<ConversationSnapshotModel>, Failure>>
  supersedingRefreshResponse;
  late Set<ConversationAction> pendingDuringSupersedingRefresh;
  late bool actionCompletedBeforeSupersedingRefresh;

  setUpAll(() {
    registerFallbackValue(_FakeCancelToken());
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

  ConversationSnapshotModel page({
    List<String> capabilities = const [],
    int oldestSequence = 1,
    bool hasMoreBefore = false,
    List<ConversationItemModel> items = const [],
  }) => ConversationSnapshotModel(
    conversationId: 'c-1',
    sessionId: 'w-1',
    harness: 'codex',
    controllerState: 'ready',
    latestSequence: 1,
    oldestSequence: oldestSequence,
    hasMoreBefore: hasMoreBefore,
    items: items,
    capabilities: capabilities,
  );

  ChatCubit build({List<String> capabilities = const []}) {
    when(
      () => repository.getConversationPage('w-1', beforeSequence: null),
    ).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: page(capabilities: capabilities)),
      ),
    );
    return ChatCubit(repository, 'w-1', configStore: configStore);
  }

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
    when(
      () => repository.sendMessage(any(), any()),
    ).thenAnswer((_) async => Result.success(true));
    when(
      () => repository.steer(any(), any()),
    ).thenAnswer((_) async => Result.success(true));
    when(
      () => repository.interrupt(any()),
    ).thenAnswer((_) async => Result.success(true));
    when(
      () => repository.compact(any()),
    ).thenAnswer((_) async => Result.success(true));
    when(
      () => repository.reloadMcpServers(any()),
    ).thenAnswer((_) async => Result.success(true));
    when(
      () => repository.setTitle(any(), any()),
    ).thenAnswer((_) async => Result.success(true));
    when(
      () => repository.setSettings(any(), any()),
    ).thenAnswer((_) async => Result.success(true));
    when(
      () => repository.resolveApproval(any(), any()),
    ).thenAnswer((_) async => Result.success(true));
    when(
      () => repository.resolveInput(any(), any()),
    ).thenAnswer((_) async => Result.success(true));
    when(
      () => repository.rollbackTurn(any(), any()),
    ).thenAnswer((_) async => Result.success(2));
    when(
      () => repository.resumeAgent(any()),
    ).thenAnswer((_) async => Result.success(true));
    when(() => repository.setConfigOption(any(), any())).thenAnswer(
      (_) async =>
          Result.success(const GlobalResponse(data: <ChatConfigOptionModel>[])),
    );
  });

  tearDown(() => events.close());

  blocTest<ChatCubit, ChatState>(
    'sends a message with a generated client id and refreshes afterwards',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send(
        'ship it',
        resources: const [
          ChatResourceModel(uri: 'file:///w/readme.md', name: 'readme'),
        ],
      );
    },
    verify: (cubit) {
      final params =
          verify(
                () => repository.sendMessage('w-1', captureAny()),
              ).captured.single
              as SendMessageParams;
      expect(params.text, 'ship it');
      expect(params.clientMessageId, startsWith('mobile-'));
      expect(params.attachments, isNull);
      expect(params.resources!.single.uri, 'file:///w/readme.md');
      expect(params.resources!.single.name, 'readme');
      expect(cubit.pendingSends, isEmpty);
      verify(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).called(2);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'keeps a failed send retryable with the daemon reason',
    build: () {
      when(() => repository.sendMessage(any(), any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(error: 'x', message: 'Delivery failed'),
        ),
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
            ? Result.failure(
                ServerFailure(error: 'x', message: 'Delivery failed'),
              )
            : Result.success(true);
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
        (_) async => Result.failure(
          ServerFailure(error: 'x', message: 'Delivery failed'),
        ),
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
      when(
        () => repository.stageAttachments(any(), any()),
      ).thenAnswer((_) async => Result.success(const ['/w/shot.png']));
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send(
        'look',
        attachments: const [ChatImageModel(mimeType: 'image/png', data: 'AAA')],
      );
    },
    verify: (cubit) {
      final params =
          verify(
                () => repository.sendMessage('w-1', captureAny()),
              ).captured.single
              as SendMessageParams;
      expect(
        params.text,
        'look\n\nAttached files are available in the worktree:\n- /w/shot.png',
      );
      expect(params.attachments, isNull);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'keeps the inline image when the provider advertises images',
    build: () {
      when(
        () => repository.stageAttachments(any(), any()),
      ).thenAnswer((_) async => Result.success(const ['/w/shot.png']));
      return build(capabilities: const ['images']);
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send(
        'look',
        attachments: const [ChatImageModel(mimeType: 'image/png', data: 'AAA')],
      );
    },
    verify: (cubit) {
      final params =
          verify(
                () => repository.sendMessage('w-1', captureAny()),
              ).captured.single
              as SendMessageParams;
      expect(params.attachments, hasLength(1));
    },
  );

  blocTest<ChatCubit, ChatState>(
    'retries attachment staging with the same client id before delivery',
    build: () {
      stageRetryResponse = Completer();
      var stageCalls = 0;
      when(() => repository.stageAttachments(any(), any())).thenAnswer((_) {
        stageCalls += 1;
        return stageCalls == 1
            ? Future.value(
                Result.failure(
                  ServerFailure(
                    error: 'x',
                    message: 'sign in',
                    apiStatus: 'CHAT_AUTH_REQUIRED',
                  ),
                ),
              )
            : stageRetryResponse.future;
      });
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send(
        'look',
        attachments: const [ChatImageModel(mimeType: 'image/png', data: 'AAA')],
      );
      stagingFailedPendingId = cubit.pendingSends.single.id;
      final retry = cubit.retrySend(stagingFailedPendingId);
      await Future<void>.delayed(Duration.zero);
      stagingRetryFailedState = cubit.pendingSends.single.failed;
      stageRetryResponse.complete(Result.success(const ['/w/shot.png']));
      await retry;
    },
    verify: (cubit) {
      final stageParams = verify(
        () => repository.stageAttachments('w-1', captureAny()),
      ).captured.cast<StageAttachmentsParams>();
      expect(stageParams, hasLength(2));
      expect(stageParams[0].attachments.single.data, 'AAA');
      expect(stageParams[1].attachments.single.data, 'AAA');
      final sendParams =
          verify(
                () => repository.sendMessage('w-1', captureAny()),
              ).captured.single
              as SendMessageParams;
      expect(sendParams.clientMessageId, stagingFailedPendingId);
      expect(
        sendParams.text,
        'look\n\nAttached files are available in the worktree:\n- /w/shot.png',
      );
      expect(sendParams.attachments, isNull);
      expect(stagingRetryFailedState, isFalse);
      expect(cubit.pendingSends, isEmpty);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'retries a staged delivery failure without staging the attachment again',
    build: () {
      when(
        () => repository.stageAttachments(any(), any()),
      ).thenAnswer((_) async => Result.success(const ['/w/shot.png']));
      var deliveryCalls = 0;
      when(() => repository.sendMessage(any(), any())).thenAnswer((_) {
        deliveryCalls += 1;
        return deliveryCalls == 1
            ? Future.value(
                Result.failure(
                  ServerFailure(error: 'x', message: 'Delivery failed'),
                ),
              )
            : Future.value(Result.success(true));
      });
      return build(capabilities: const ['images']);
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send(
        'look',
        attachments: const [ChatImageModel(mimeType: 'image/png', data: 'AAA')],
      );
      await cubit.retrySend(cubit.pendingSends.single.id);
    },
    verify: (cubit) {
      verify(() => repository.stageAttachments('w-1', any())).called(1);
      final deliveries = verify(
        () => repository.sendMessage('w-1', captureAny()),
      ).captured.cast<SendMessageParams>();
      expect(deliveries, hasLength(2));
      expect(deliveries[1].clientMessageId, deliveries[0].clientMessageId);
      expect(deliveries[1].text, deliveries[0].text);
      expect(deliveries[1].attachments!.single.data, 'AAA');
      expect(cubit.pendingSends, isEmpty);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'records the message and the machine code when an action is refused',
    build: () {
      when(() => repository.steer(any(), any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(
            error: 'x',
            message: 'nope',
            apiStatus: 'CHAT_STEER_UNSUPPORTED',
          ),
        ),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.steer('use the other file');
    },
    verify: (cubit) {
      expect(
        cubit.actionErrors[ConversationAction.steer],
        contains('Queue a new message'),
      );
      expect(
        cubit.actionCodes[ConversationAction.steer],
        'CHAT_STEER_UNSUPPORTED',
      );
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
            ? Result.failure(
                ServerFailure(
                  error: 'x',
                  message: 'busy',
                  apiStatus: 'CHAT_COMPACTION_BUSY',
                ),
              )
            : Result.success(true);
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
    build: () {
      rollbackRefreshResponse = Completer();
      var liveCalls = 0;
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) {
        liveCalls += 1;
        if (liveCalls > 1) return rollbackRefreshResponse.future;
        return Future.value(
          Result.success(
            GlobalResponse(
              data: page(
                oldestSequence: 2,
                hasMoreBefore: true,
                items: const [ConversationMessageModel(id: 'm-2', sequence: 2)],
              ),
            ),
          ),
        );
      });
      when(
        () => repository.getConversationPage('w-1', beforeSequence: 2),
      ).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(
            data: page(
              items: const [ConversationMessageModel(id: 'm-1', sequence: 1)],
            ),
          ),
        ),
      );
      return ChatCubit(repository, 'w-1', configStore: configStore);
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.loadOlder();
      expect(cubit.snapshot!.items.map((item) => item.id), ['m-1', 'm-2']);
      final rollbackAction = cubit.rollback('t-1');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.snapshot!.items.map((item) => item.id), ['m-2']);
      rollbackRefreshResponse.complete(
        Result.success(
          GlobalResponse(
            data: page(
              oldestSequence: 2,
              hasMoreBefore: true,
              items: const [ConversationMessageModel(id: 'm-2', sequence: 2)],
            ),
          ),
        ),
      );
      expect(await rollbackAction, 2);
    },
    verify: (cubit) {
      final params =
          verify(
                () => repository.rollbackTurn('w-1', captureAny()),
              ).captured.single
              as RollbackTurnParams;
      expect(params.turnId, 't-1');
      expect(cubit.snapshot!.items.map((item) => item.id), ['m-2']);
      verify(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).called(2);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'preserves another pending action when one concurrent action finishes',
    build: () {
      compactResponse = Completer<Result<bool, Failure>>();
      interruptResponse = Completer<Result<bool, Failure>>();
      when(
        () => repository.compact('w-1'),
      ).thenAnswer((_) => compactResponse.future);
      when(
        () => repository.interrupt('w-1'),
      ).thenAnswer((_) => interruptResponse.future);
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final compactAction = cubit.compact();
      final interruptAction = cubit.interrupt();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.pendingActions, {
        ConversationAction.compact,
        ConversationAction.interrupt,
      });
      compactResponse.complete(Result.success(true));
      await compactAction;
      expect(cubit.pendingActions, {ConversationAction.interrupt});
      interruptResponse.complete(Result.success(true));
      await interruptAction;
    },
    verify: (cubit) => expect(cubit.pendingActions, isEmpty),
  );

  blocTest<ChatCubit, ChatState>(
    'keeps a successful action pending until its refresh completes',
    build: () {
      actionRefreshResponse = Completer();
      var liveCalls = 0;
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) {
        liveCalls += 1;
        if (liveCalls > 1) return actionRefreshResponse.future;
        return Future.value(Result.success(GlobalResponse(data: page())));
      });
      return ChatCubit(repository, 'w-1', configStore: configStore);
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final action = cubit.compact();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.refreshing, isTrue);
      expect(cubit.pendingActions, {ConversationAction.compact});
      actionRefreshResponse.complete(
        Result.success(GlobalResponse(data: page())),
      );
      await action;
    },
    verify: (cubit) => expect(cubit.pendingActions, isEmpty),
  );

  blocTest<ChatCubit, ChatState>(
    'keeps an action pending when its refresh is superseded',
    build: () {
      actionRefreshResponse = Completer();
      supersedingRefreshResponse = Completer();
      var liveCalls = 0;
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) {
        liveCalls += 1;
        if (liveCalls == 2) return actionRefreshResponse.future;
        if (liveCalls == 3) return supersedingRefreshResponse.future;
        return Future.value(Result.success(GlobalResponse(data: page())));
      });
      return ChatCubit(repository, 'w-1', configStore: configStore);
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      var actionCompleted = false;
      final action = cubit.compact().whenComplete(() => actionCompleted = true);
      await Future<void>.delayed(Duration.zero);
      final supersedingRefresh = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      actionRefreshResponse.complete(
        Result.success(GlobalResponse(data: page())),
      );
      await Future<void>.delayed(Duration.zero);
      pendingDuringSupersedingRefresh = {...cubit.pendingActions};
      actionCompletedBeforeSupersedingRefresh = actionCompleted;
      supersedingRefreshResponse.complete(
        Result.success(GlobalResponse(data: page())),
      );
      await Future.wait([action, supersedingRefresh]);
    },
    verify: (cubit) {
      expect(pendingDuringSupersedingRefresh, {ConversationAction.compact});
      expect(actionCompletedBeforeSupersedingRefresh, isFalse);
      expect(cubit.pendingActions, isEmpty);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'rejects an older page that completes during rollback refresh',
    build: () {
      rollbackOlderResponse = Completer();
      rollbackRefreshResponse = Completer();
      var liveCalls = 0;
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) {
        liveCalls += 1;
        if (liveCalls > 1) return rollbackRefreshResponse.future;
        return Future.value(
          Result.success(
            GlobalResponse(
              data: page(
                oldestSequence: 2,
                hasMoreBefore: true,
                items: const [ConversationMessageModel(id: 'm-2', sequence: 2)],
              ),
            ),
          ),
        );
      });
      when(
        () => repository.getConversationPage('w-1', beforeSequence: 2),
      ).thenAnswer((_) => rollbackOlderResponse.future);
      return ChatCubit(repository, 'w-1', configStore: configStore);
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final pagination = cubit.loadOlder();
      await Future<void>.delayed(Duration.zero);
      final rollbackAction = cubit.rollback('t-1');
      await Future<void>.delayed(Duration.zero);
      rollbackOlderResponse.complete(
        Result.success(
          GlobalResponse(
            data: page(
              items: const [ConversationMessageModel(id: 'm-1', sequence: 1)],
            ),
          ),
        ),
      );
      await pagination;
      rollbackRefreshResponse.complete(
        Result.success(
          GlobalResponse(
            data: page(
              oldestSequence: 2,
              hasMoreBefore: true,
              items: const [ConversationMessageModel(id: 'm-2', sequence: 2)],
            ),
          ),
        ),
      );
      await rollbackAction;
    },
    verify: (cubit) {
      expect(cubit.snapshot!.items.map((item) => item.id), ['m-2']);
      expect(cubit.loadingOlder, isFalse);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'routes each remaining action to its endpoint',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.steer('use the other file');
      await cubit.interrupt();
      await cubit.resolveApproval('req-1', 'accept');
      await cubit.resolveInput('req-2', 'accept', const {'token': 'x'});
      await cubit.reloadMcp();
      await cubit.rename('New title');
      await cubit.chooseSettings(
        const TurnSettingsModel(
          model: 'opus',
          reasoningEffort: 'high',
          approvalMode: 'on-request',
        ),
      );
      await cubit.setConfigOption(
        const SetConfigOptionParams(optionId: 'fast', enabled: true),
      );
      await cubit.resumeAgent();
      await Future<void>.delayed(Duration.zero);
    },
    verify: (_) {
      final steerParams =
          verify(() => repository.steer('w-1', captureAny())).captured.single
              as SteerConversationParams;
      expect(steerParams.text, 'use the other file');
      expect(steerParams.clientMessageId, startsWith('mobile-'));
      verify(() => repository.interrupt('w-1')).called(1);
      final approvalParams =
          verify(
                () => repository.resolveApproval('w-1', captureAny()),
              ).captured.single
              as ResolveApprovalParams;
      expect(approvalParams.requestId, 'req-1');
      expect(approvalParams.decisionId, 'accept');
      final inputParams =
          verify(
                () => repository.resolveInput('w-1', captureAny()),
              ).captured.single
              as ResolveInputParams;
      expect(inputParams.requestId, 'req-2');
      expect(inputParams.action, 'accept');
      expect(inputParams.content, const {'token': 'x'});
      verify(() => repository.reloadMcpServers('w-1')).called(1);
      final titleParams =
          verify(() => repository.setTitle('w-1', captureAny())).captured.single
              as SetConversationTitleParams;
      expect(titleParams.title, 'New title');
      final settings =
          verify(
                () => repository.setSettings('w-1', captureAny()),
              ).captured.single
              as TurnSettingsModel;
      expect(settings.model, 'opus');
      expect(settings.reasoningEffort, 'high');
      expect(settings.approvalMode, 'on-request');
      final configParams =
          verify(
                () => repository.setConfigOption('w-1', captureAny()),
              ).captured.single
              as SetConfigOptionParams;
      expect(configParams.optionId, 'fast');
      expect(configParams.enabled, isTrue);
      expect(configParams.value, isNull);
      verify(() => repository.resumeAgent('w-1')).called(1);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'ignores a config response after conversation ownership changes',
    build: () {
      configResponse = Completer();
      var liveCalls = 0;
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) {
        liveCalls += 1;
        return Future.value(
          Result.success(
            GlobalResponse(
              data: ConversationSnapshotModel(
                conversationId: liveCalls == 1 ? 'c-1' : 'c-2',
                sessionId: 'w-1',
                harness: 'codex',
                controllerState: 'ready',
                latestSequence: liveCalls,
                capabilities: const ['config_options'],
              ),
            ),
          ),
        );
      });
      when(
        () => repository.setConfigOption('w-1', any()),
      ).thenAnswer((_) => configResponse.future);
      return ChatCubit(repository, 'w-1', configStore: configStore);
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final update = cubit.setConfigOption(
        const SetConfigOptionParams(optionId: 'fast', enabled: true),
      );
      await Future<void>.delayed(Duration.zero);
      await cubit.refresh();
      configResponse.complete(
        Result.success(
          const GlobalResponse(
            data: [ChatConfigOptionModel(id: 'stale', name: 'Stale')],
          ),
        ),
      );
      await update;
    },
    verify: (cubit) {
      expect(cubit.snapshot!.conversationId, 'c-2');
      expect(cubit.configOptions, isEmpty);
    },
  );

  blocTest<ChatCubit, ChatState>(
    'clears resume errors before retry and refreshes after success',
    build: () {
      resumeResponse = Completer();
      var resumeCalls = 0;
      when(() => repository.resumeAgent('w-1')).thenAnswer((_) {
        resumeCalls += 1;
        return resumeCalls == 1
            ? resumeResponse.future
            : Future.value(Result.success(true));
      });
      when(() => repository.steer(any(), any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(
            error: 'x',
            message: 'nope',
            apiStatus: 'CHAT_STEER_UNSUPPORTED',
          ),
        ),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.steer('guide');
      final firstResume = cubit.resumeAgent();
      await Future<void>.delayed(Duration.zero);
      final errorWhilePending = cubit.actionError;
      resumeResponse.complete(
        Result.failure(
          ServerFailure(
            error: 'x',
            message: 'auth',
            apiStatus: 'CHAT_AUTH_REQUIRED',
          ),
        ),
      );
      await firstResume;
      expect(errorWhilePending, isNull);
      expect(cubit.actionError, contains('Sign in'));
      await cubit.resumeAgent();
      expect(cubit.actionError, isNull);
    },
    verify: (_) {
      verify(() => repository.resumeAgent('w-1')).called(2);
      verify(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).called(2);
    },
  );

  test(
    'closed cubit rejects every Task 18 action before repository I/O',
    () async {
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) async => Result.success(GlobalResponse(data: page())));
      when(
        () => repository.stageAttachments(any(), any()),
      ).thenAnswer((_) async => Result.success(const ['/w/shot.png']));
      final cubit = build();
      await cubit.close();
      await cubit.send(
        'look',
        attachments: const [ChatImageModel(mimeType: 'image/png', data: 'AAA')],
      );
      cubit.pendingSends = const [PendingSend(id: 'p-1', text: 'pending')];
      await cubit.retrySend('p-1');
      cubit.discardSend('p-1');
      await cubit.steer('guide');
      await cubit.interrupt();
      await cubit.resolveApproval('req-1', 'accept');
      await cubit.resolveInput('req-2', 'accept', const {'token': 'x'});
      await cubit.compact();
      await cubit.rollback('t-1');
      await cubit.chooseSettings(const TurnSettingsModel(model: 'opus'));
      await cubit.setConfigOption(
        const SetConfigOptionParams(optionId: 'fast', enabled: true),
      );
      await cubit.reloadMcp();
      await cubit.rename('Title');
      await cubit.resumeAgent();

      expect(cubit.pendingSends.single.id, 'p-1');
      verifyNever(() => repository.getConversationPage(any()));
      verifyNever(() => repository.stageAttachments(any(), any()));
      verifyNever(() => repository.sendMessage(any(), any()));
      verifyNever(() => repository.steer(any(), any()));
      verifyNever(() => repository.interrupt(any()));
      verifyNever(() => repository.resolveApproval(any(), any()));
      verifyNever(() => repository.resolveInput(any(), any()));
      verifyNever(() => repository.compact(any()));
      verifyNever(() => repository.rollbackTurn(any(), any()));
      verifyNever(() => repository.setSettings(any(), any()));
      verifyNever(() => repository.setConfigOption(any(), any()));
      verifyNever(() => repository.reloadMcpServers(any()));
      verifyNever(() => repository.setTitle(any(), any()));
      verifyNever(() => repository.resumeAgent(any()));
    },
  );

  test('a delivered message reports feature_used with the send feature', () async {
    TelemetryRuntime.reset();
    final client = RecordingClient();
    TelemetryRuntime.init(
      client: client,
      context: const TelemetryContextInput(
        platformOs: 'ios',
        isPhysicalDevice: true,
        dev: false,
        appVersion: '1.1.0',
      ),
    );
    addTearDown(TelemetryRuntime.reset);
    when(() => repository.sendMessage(any(), any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'offline', statusCode: 503)),
    );
    final cubit = build();

    await cubit.send('ship it');

    expect(
      client.captures.where((capture) => capture.event == MobileEvents.featureUsed).single.properties,
      containsPair('feature', 'send'),
    );
    await cubit.close();
  });
}
