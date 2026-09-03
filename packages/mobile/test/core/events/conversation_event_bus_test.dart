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
  late List<StreamController<ConversationEventModel>> opened;
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
      final controller = StreamController<ConversationEventModel>();
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

    opened.first.add(event(90, 'w-1'));
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

    opened.first.add(event(91, 'w-1'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(one, [91]);
    expect(two, isEmpty);
    await bus.disconnect();
  });

  test('reports connecting then connected, and reconnecting on loss', () async {
    final bus = build();
    final seen = <EventStreamStatus>[];
    bus.status.listen(seen.add);
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    opened.first.addError(
      const StaleEventStreamException(Duration(seconds: 35)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(seen.first, EventStreamStatus.connecting);
    expect(seen, contains(EventStreamStatus.connected));
    expect(seen, contains(EventStreamStatus.reconnecting));
    await bus.disconnect();
  });

  test('signals a reconnect so subscribers can cover the gap', () async {
    final bus = build();
    var reconnects = 0;
    bus.reconnects.listen((_) => reconnects += 1);
    bus.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(reconnects, 1);

    await opened.first.close();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(reconnects, 2);
    await bus.disconnect();
  });
}
