import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/logic/conversation_blocks.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_state.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

class _MockChatRepository extends Mock implements ChatRepository {}

class _MockChatEventDataSource extends Mock implements ChatEventDataSource {}

ConversationSnapshotModel _snapshot({int latest = 0, bool hasMoreBefore = false}) =>
    ConversationSnapshotModel(latestSequence: latest, hasMoreBefore: hasMoreBefore);

GlobalResponse<ConversationSnapshotModel> _ok(ConversationSnapshotModel snapshot) =>
    GlobalResponse<ConversationSnapshotModel>(data: snapshot);

ConversationEventModel _event({int seq = 1, String? conversationId = 'c-1'}) =>
    ConversationEventModel(
      seq: seq,
      sessionId: 's-1',
      type: 'turn.delta',
      payload: {'conversationId': ?conversationId},
    );

class _CancelTokenFake extends Fake implements CancelToken {
  @override
  Future<DioException> get whenCancel => Completer<DioException>().future;
}

void main() {
  late _MockChatRepository repository;
  late _MockChatEventDataSource eventDataSource;
  late StreamController<ConversationEventModel> events;

  setUpAll(() {
    registerFallbackValue(_CancelTokenFake());
  });

  setUp(() {
    repository = _MockChatRepository();
    eventDataSource = _MockChatEventDataSource();
    events = StreamController<ConversationEventModel>.broadcast();
    when(
      () => eventDataSource.stream(
        after: any(named: 'after'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) => events.stream);
  });

  tearDown(() async {
    await events.close();
  });

  ConversationBlocksCubit build() =>
      ConversationBlocksCubit(repository, eventDataSource, 's-1');

  test('initial fetch emits a Ready state with blocksFromConversation(snapshot)', () async {
    final snapshot = _snapshot(latest: 5);
    when(
      () => repository.getConversationPage(any(), beforeSequence: any(named: 'beforeSequence')),
    ).thenAnswer((_) async => Result.success(_ok(snapshot)));

    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = cubit.state;
    expect(state, isA<ConversationBlocksReadyState>());
    final ready = state as ConversationBlocksReadyState;
    expect(ready.blocks, equals(blocksFromConversation(snapshot)));
    expect(ready.isLoading, isFalse);
    expect(ready.error, isNull);
    expect(ready.unavailable, isNull);
    expect(ready.hasOlder, isFalse);
    await cubit.close();
  });

  test('a new event invalidates and re-fetches the snapshot', () async {
    final firstSnapshot = _snapshot(latest: 1);
    final secondSnapshot = _snapshot(latest: 3);
    var calls = 0;
    when(
      () => repository.getConversationPage(any(), beforeSequence: any(named: 'beforeSequence')),
    ).thenAnswer((_) async {
      calls++;
      return Result.success(_ok(calls == 1 ? firstSnapshot : secondSnapshot));
    });

    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final first = cubit.state as ConversationBlocksReadyState;
    expect(first.blocks, equals(blocksFromConversation(firstSnapshot)));

    events.add(_event(seq: 2));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final second = cubit.state as ConversationBlocksReadyState;
    expect(second.blocks, equals(blocksFromConversation(secondSnapshot)));
    expect(second.revision, greaterThan(first.revision));
    await cubit.close();
  });

  test('a permanent conversation code emits the unsupported state', () async {
    when(
      () => repository.getConversationPage(any(), beforeSequence: any(named: 'beforeSequence')),
    ).thenAnswer(
      (_) async => Result.failure(
        ServerFailure<void>(
          error: 'mode-mismatch',
          message: 'Chat is not supported on this session.',
          apiStatus: 'SESSION_MODE_MISMATCH',
        ),
      ),
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state, isA<ConversationBlocksUnsupportedState>());
    final unsupported = cubit.state as ConversationBlocksUnsupportedState;
    expect(unsupported.unavailable.code, 'SESSION_MODE_MISMATCH');
    await cubit.close();
  });

  test('a non-permanent failure emits Ready with error', () async {
    when(
      () => repository.getConversationPage(any(), beforeSequence: any(named: 'beforeSequence')),
    ).thenAnswer(
      (_) async => Result.failure(
        ServerFailure<void>(
          error: 'timeout',
          message: 'Timed out reaching the daemon.',
        ),
      ),
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = cubit.state;
    expect(state, isA<ConversationBlocksReadyState>());
    final ready = state as ConversationBlocksReadyState;
    expect(ready.error, isNotNull);
    expect(ready.unavailable, isNull);
    expect(ready.supported, isFalse);
    await cubit.close();
  });

  test('close() cancels the event subscription and stops processing', () async {
    final snapshot = _snapshot(latest: 2);
    when(
      () => repository.getConversationPage(any(), beforeSequence: any(named: 'beforeSequence')),
    ).thenAnswer((_) async => Result.success(_ok(snapshot)));

    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    clearInteractions(repository);
    await cubit.close();

    events.add(_event(seq: 99));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    verifyNever(
      () => repository.getConversationPage(
        any(),
        beforeSequence: any(named: 'beforeSequence'),
      ),
    );
  });

  test('loadOlder merges an older page and clears the loading flag', () async {
    final live = _snapshot(latest: 100, hasMoreBefore: true);
    final older = _snapshot(latest: 60, hasMoreBefore: false);
    var calls = 0;
    when(
      () => repository.getConversationPage(any(), beforeSequence: any(named: 'beforeSequence')),
    ).thenAnswer((_) async {
      calls++;
      if (calls == 1) return Result.success(_ok(live));
      return Result.success(_ok(older));
    });

    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final before = cubit.state as ConversationBlocksReadyState;
    expect(before.hasOlder, isTrue);

    await cubit.loadOlder();
    await Future<void>.delayed(Duration.zero);

    final after = cubit.state as ConversationBlocksReadyState;
    expect(after.isLoadingOlder, isFalse);

    final captured = verify(
      () => repository.getConversationPage('s-1', beforeSequence: captureAny(named: 'beforeSequence')),
    ).captured;
    expect(captured.last, isNotNull);
    await cubit.close();
  });

  test('an initial fetch failure with no permanent code is supported=false', () async {
    when(
      () => repository.getConversationPage(any(), beforeSequence: any(named: 'beforeSequence')),
    ).thenAnswer(
      (_) async => Result.failure(
        ServerFailure<void>(error: 'boom', message: 'boom'),
      ),
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state, isA<ConversationBlocksReadyState>());
    expect(cubit.state.supported, isFalse);
    await cubit.close();
  });
}
