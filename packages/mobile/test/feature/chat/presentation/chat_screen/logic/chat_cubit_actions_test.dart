import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
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
  late Completer<Result<bool, Failure>> compactResponse;
  late Completer<Result<bool, Failure>> interruptResponse;
  late Completer<Result<GlobalResponse<ConversationSnapshotModel>, Failure>>
  rollbackRefreshResponse;

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
    return ChatCubit(repository, 'w-1');
  }

  setUp(() {
    repository = _MockChatRepository();
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

  blocTest<ChatCubit, ChatState>(
    'sends a message with a generated client id and refreshes afterwards',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.send('ship it');
    },
    verify: (cubit) {
      final params =
          verify(
                () => repository.sendMessage('w-1', captureAny()),
              ).captured.single
              as SendMessageParams;
      expect(params.text, 'ship it');
      expect(params.clientMessageId, startsWith('mobile-'));
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
    'keeps an attachment staging failure retryable without delivering',
    build: () {
      when(() => repository.stageAttachments(any(), any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(
            error: 'x',
            message: 'sign in',
            apiStatus: 'CHAT_AUTH_REQUIRED',
          ),
        ),
      );
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
      expect(cubit.pendingSends.single.failed, isTrue);
      expect(cubit.pendingSends.single.error, contains('Sign in'));
      verifyNever(() => repository.sendMessage(any(), any()));
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
      return ChatCubit(repository, 'w-1');
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
      await cubit.setConfigOption(
        const SetConfigOptionParams(optionId: 'fast', enabled: true),
      );
      await cubit.resumeAgent();
      await Future<void>.delayed(Duration.zero);
    },
    verify: (_) {
      verify(() => repository.interrupt('w-1')).called(1);
      verify(() => repository.resolveApproval('w-1', any())).called(1);
      verify(() => repository.resolveInput('w-1', any())).called(1);
      verify(() => repository.reloadMcpServers('w-1')).called(1);
      verify(() => repository.setTitle('w-1', any())).called(1);
      verify(() => repository.setSettings('w-1', any())).called(1);
      verify(() => repository.setConfigOption('w-1', any())).called(1);
      verify(() => repository.resumeAgent('w-1')).called(1);
    },
  );
}
