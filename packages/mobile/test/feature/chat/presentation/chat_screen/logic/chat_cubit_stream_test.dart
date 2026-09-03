import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/events/cdc_cursor.dart';
import 'package:operator_mobile/core/events/conversation_event_bus.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';

class _MockChatRepository extends Mock implements ChatRepository {}

class _MockChatEventDataSource extends Mock implements ChatEventDataSource {}

class _FakeCancelToken extends Fake implements CancelToken {}

void main() {
  late _MockChatRepository repository;
  late _MockChatEventDataSource eventSource;
  late StreamController<ConversationEventModel> events;

  setUpAll(() {
    registerFallbackValue(_FakeCancelToken());
    registerFallbackValue(const CdcCursor.latest());
  });

  setUp(() {
    repository = _MockChatRepository();
    eventSource = _MockChatEventDataSource();
    events = StreamController<ConversationEventModel>.broadcast();

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
      () => eventSource.stream(
        after: any(named: 'after'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) => events.stream);
  });

  tearDown(() => events.close());

  ChatCubit build() => ChatCubit(
    repository,
    'w-1',
    eventBus: ConversationEventBus(
      eventSource,
      reconnectMin: const Duration(milliseconds: 10),
      reconnectMax: const Duration(milliseconds: 20),
    ),
    refreshDebounce: const Duration(milliseconds: 10),
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
      () => eventSource.stream(
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
      await Future<void>.delayed(const Duration(milliseconds: 20));
    },
    verify: (_) => verify(
      () => repository.getConversationPage('w-1', beforeSequence: null),
    ).called(3),
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
      () => eventSource.stream(
        after: any(named: 'after'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ),
  );

  blocTest<ChatCubit, ChatState>(
    'stops refreshing when the conversation becomes permanently unavailable',
    build: () {
      var calls = 0;
      when(
        () => repository.getConversationPage('w-1', beforeSequence: null),
      ).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) {
          return Result.success(
            GlobalResponse(
              data: const ConversationSnapshotModel(
                conversationId: 'c-1',
                sessionId: 'w-1',
                harness: 'codex',
                controllerState: 'ready',
                latestSequence: 1,
              ),
            ),
          );
        }
        return Result.failure(
          ServerFailure(
            error: 'x',
            message: 'gone',
            apiStatus: 'SESSION_NOT_FOUND',
          ),
        );
      });
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.refresh();
      events.addError(
        ServerFailure(error: 'dropped', message: 'stream closed'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
    },
    verify: (_) => verify(
      () => repository.getConversationPage('w-1', beforeSequence: null),
    ).called(2),
  );
}
