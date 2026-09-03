import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/events/cdc_cursor.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart';

class _MockChatRepository extends Mock implements ChatRepository {}

class _MockEventDataSource extends Mock implements ChatEventDataSource {}

class _FakeCancelToken extends Fake implements CancelToken {}

void main() {
  late _MockChatRepository repository;
  late _MockEventDataSource eventSource;
  late List<StreamController<ConversationEventModel>> opened;
  late int fetches;

  setUpAll(() {
    registerFallbackValue(_FakeCancelToken());
    registerFallbackValue(const CdcCursor.latest());
  });

  setUp(() {
    repository = _MockChatRepository();
    eventSource = _MockEventDataSource();
    opened = [];
    fetches = 0;

    when(
      () => repository.getConversationPage('w-1', beforeSequence: null),
    ).thenAnswer((_) async {
      fetches += 1;
      return Result.success(
        GlobalResponse(
          data: const ConversationSnapshotModel(
            conversationId: 'c-1',
            sessionId: 'w-1',
            harness: 'codex',
            controllerState: 'ready',
            latestSequence: 400,
          ),
        ),
      );
    });

    when(
      () => eventSource.stream(
        after: any(named: 'after'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) {
      final controller = StreamController<ConversationEventModel>();
      opened.add(controller);
      return controller.stream;
    });
  });

  ConversationBlocksCubit build() => ConversationBlocksCubit(
    repository,
    eventSource,
    'w-1',
    refreshDebounce: const Duration(milliseconds: 10),
    reconnectMin: const Duration(milliseconds: 10),
    reconnectMax: const Duration(milliseconds: 20),
  );

  ConversationEventModel event(int seq, String sessionId) =>
      ConversationEventModel(
        seq: seq,
        sessionId: sessionId,
        type: 'conversation_updated',
        payload: const {'conversationId': 'c-1'},
      );

  test('reopens the stream after it closes', () async {
    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(opened, hasLength(1));

    await opened.first.close();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(opened, hasLength(2));
    await cubit.close();
  });

  test('reopens the stream after a staleness error', () async {
    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    opened.first.addError(
      const StaleEventStreamException(Duration(seconds: 35)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(opened.length, greaterThan(1));
    await cubit.close();
  });

  test('ignores events belonging to another session', () async {
    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final before = fetches;

    opened.first.add(event(500, 'w-2'));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(fetches, before);
    await cubit.close();
  });

  test('collapses an event burst into a single refetch', () async {
    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final before = fetches;

    for (var seq = 500; seq < 510; seq++) {
      opened.first.add(event(seq, 'w-1'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(fetches, before + 1);
    await cubit.close();
  });
}
