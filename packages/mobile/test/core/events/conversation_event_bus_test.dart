import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/events/cdc_cursor.dart';
import 'package:operator_mobile/core/events/conversation_event_bus.dart';
import 'package:operator_mobile/core/events/event_stream_status.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

class _MockEventDataSource extends Mock implements ChatEventDataSource {}

class _FakeCancelToken extends Fake implements CancelToken {}

void main() {
  late _MockEventDataSource source;
  late List<StreamController<ConversationStreamFrame>> opened;
  late List<CdcCursor> cursors;

  setUpAll(() {
    registerFallbackValue(_FakeCancelToken());
    registerFallbackValue(const CdcCursor.latest());
  });

  setUp(() {
    source = _MockEventDataSource();
    opened = [];
    cursors = [];
    when(
      () => source.stream(
        after: any(named: 'after'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((invocation) {
      cursors.add(invocation.namedArguments[#after] as CdcCursor);
      final controller = StreamController<ConversationStreamFrame>();
      opened.add(controller);
      return controller.stream;
    });
  });

  ConversationEventBus build() => ConversationEventBus(
    source,
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

  void daemonAnswers() => opened.last.add(const ConversationStreamOpened());

  void emit(int seq, String sessionId) =>
      opened.last.add(ConversationStreamEvent(event(seq, sessionId)));

  test('opens exactly one stream for many subscribers', () async {
    final bus = build();
    bus.eventsFor('w-1').listen((_) {});
    bus.eventsFor('w-2').listen((_) {});
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(opened, hasLength(1));
    await bus.disconnect();
  });

  test('starts at the log head and resumes from the last seq seen', () async {
    final bus = build();
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(cursors.single, isA<CdcCursorLatest>());

    daemonAnswers();
    emit(90, 'w-1');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await opened.first.close();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(cursors.last, isA<CdcCursorAt>());
    expect((cursors.last as CdcCursorAt).seq, 90);
    await bus.disconnect();
  });

  test('routes an event only to its own session', () async {
    final bus = build();
    final one = <int>[];
    final two = <int>[];
    bus.eventsFor('w-1').listen((e) => one.add(e.seq));
    bus.eventsFor('w-2').listen((e) => two.add(e.seq));
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    daemonAnswers();
    emit(91, 'w-1');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(one, [91]);
    expect(two, isEmpty);
    await bus.disconnect();
  });

  test('reports connected only once the daemon answers', () async {
    final bus = build();
    final seen = <EventStreamStatus>[];
    bus.status.listen(seen.add);
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      seen,
      isEmpty,
      reason: 'subscribing is not connecting; the request is not even sent yet',
    );
    expect(bus.currentStatus, EventStreamStatus.connecting);

    daemonAnswers();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(seen, [EventStreamStatus.connected]);

    opened.last.addError(
      const StaleEventStreamException(Duration(seconds: 35)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(seen, contains(EventStreamStatus.reconnecting));
    await bus.disconnect();
  });

  test('stays reconnecting across a retry that never answers', () async {
    final bus = build();
    final seen = <EventStreamStatus>[];
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    daemonAnswers();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    bus.status.listen(seen.add);
    await opened.last.close();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(
      opened.length,
      greaterThan(1),
      reason: 'the backoff timer should have retried by now',
    );
    expect(
      bus.currentStatus,
      EventStreamStatus.reconnecting,
      reason: 'a retry that has not answered must not read as connected',
    );
    expect(
      seen.where((s) => s == EventStreamStatus.connected),
      isEmpty,
      reason: 'the offline banner must not blink off during a failed retry',
    );
    await bus.disconnect();
  });

  test('signals a reconnect only on a proven connection', () async {
    final bus = build();
    var reconnects = 0;
    bus.reconnects.listen((_) => reconnects += 1);
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      reconnects,
      0,
      reason: 'refetching per attempt would hammer an unreachable daemon',
    );

    daemonAnswers();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(reconnects, 1);

    await opened.last.close();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(reconnects, 1, reason: 'the retry has not answered yet');

    daemonAnswers();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(reconnects, 2);
    await bus.disconnect();
  });

  test('connect() during a pending backoff does not reopen or reset the delay', () async {
    final bus = ConversationEventBus(
      source,
      reconnectMin: const Duration(milliseconds: 60),
      reconnectMax: const Duration(milliseconds: 200),
    );
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(opened, hasLength(1));
    daemonAnswers();

    await opened.first.close();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(opened, hasLength(1));

    bus.connect();
    expect(
      opened,
      hasLength(1),
      reason: 'connect() while backoff is pending must not reopen early',
    );

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      opened,
      hasLength(1),
      reason: 'connect() while backoff is pending must not reset the delay',
    );

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(opened, hasLength(2));
    await bus.disconnect();
  });

  test('onResumed() called twice in quick succession only reopens once', () async {
    final bus = build();
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    daemonAnswers();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(opened, hasLength(1));

    bus.onResumed();
    bus.onResumed();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(opened, hasLength(2));
    await bus.disconnect();
  });
}
