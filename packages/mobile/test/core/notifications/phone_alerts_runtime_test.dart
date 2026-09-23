import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/mux_notification.dart';
import 'package:operator_mobile/core/notifications/local_alert_sink.dart';
import 'package:operator_mobile/core/notifications/phone_alerts_runtime.dart';
import 'package:operator_mobile/core/notifications/viewed_session.dart';

class _MockMux extends Mock implements MuxClient {}

class _Shown {
  _Shown(this.id, this.title, this.body, this.payload);
  final int id;
  final String title;
  final String body;
  final String payload;
}

class _FakeSink implements LocalAlertSink {
  final shown = <_Shown>[];
  void Function(String payload)? onTap;
  Future<void> ready = Future.value();

  @override
  Future<void> init(void Function(String payload) onTap) async {
    this.onTap = onTap;
    await ready;
  }

  @override
  Future<void> show({required int id, required String title, required String body, required String payload}) async =>
      shown.add(_Shown(id, title, body, payload));
}

MuxNotification _n(String id, String session, {bool quiet = false}) => MuxNotification(
  id: id,
  sessionId: session,
  type: 'turn_finished',
  title: '$session finished',
  body: 'done',
  quiet: quiet,
);

void main() {
  late _MockMux mux;
  late StreamController<MuxNotification> feed;
  late _FakeSink sink;
  late List<Uri> opened;
  late PhoneAlertsRuntime runtime;

  setUp(() async {
    ViewedSession.current.value = null;
    mux = _MockMux();
    feed = StreamController<MuxNotification>.broadcast(sync: true);
    when(() => mux.notifications).thenAnswer((_) => feed.stream);
    sink = _FakeSink();
    opened = [];
    runtime = PhoneAlertsRuntime(mux, sink, (uri) {
      opened.add(uri);
      return true;
    });
    await runtime.start();
  });

  tearDown(() async {
    await runtime.dispose();
    await feed.close();
  });

  test('shows exactly one local notification per frame, and it opens the session', () {
    feed.add(_n('n1', 's1'));
    expect(sink.shown, hasLength(1));
    expect(sink.shown.single.title, 's1 finished');
    expect(sink.shown.single.body, 'done');
    expect(sink.shown.single.payload, 'operator://session/s1');
    sink.onTap!(sink.shown.single.payload);
    expect(opened, [Uri.parse('operator://session/s1')]);
  });

  test('skips the session on screen and quiet notifications', () {
    ViewedSession.current.value = 's1';
    feed.add(_n('n1', 's1'));
    feed.add(_n('n2', 's2', quiet: true));
    expect(sink.shown, isEmpty);
    feed.add(_n('n3', 's2'));
    expect(sink.shown.single.payload, 'operator://session/s2');
  });

  test('gives every notification its own id', () {
    feed.add(_n('n1', 's1'));
    feed.add(_n('n2', 's2'));
    expect(sink.shown.map((s) => s.id).toSet(), hasLength(2));
  });

  test('start subscribes; foreground and background follow the app', () {
    verify(() => mux.subscribeNotifications()).called(1);
    runtime.background();
    verify(() => mux.unsubscribeNotifications()).called(1);
    verifyNever(() => mux.subscribeNotifications());
    runtime.foreground();
    verify(() => mux.subscribeNotifications()).called(1);
  });

  test('a background that arrives while start is still initialising keeps the feed unsubscribed', () async {
    final slowMux = _MockMux();
    when(() => slowMux.notifications).thenAnswer((_) => feed.stream);
    final gate = Completer<void>();
    final slowSink = _FakeSink()..ready = gate.future;
    final slow = PhoneAlertsRuntime(slowMux, slowSink, (_) => true);

    final starting = slow.start();
    slow.background();
    gate.complete();
    await starting;

    verifyNever(() => slowMux.subscribeNotifications());
    verify(() => slowMux.unsubscribeNotifications()).called(1);
    await slow.dispose();
  });
}
