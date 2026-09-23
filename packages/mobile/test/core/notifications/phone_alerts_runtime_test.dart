import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/deep_link/deep_link_target.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/mux_notification.dart';
import 'package:operator_mobile/core/notifications/local_alert_sink.dart';
import 'package:operator_mobile/core/notifications/phone_alerts_runtime.dart';
import 'package:operator_mobile/core/notifications/viewed_session.dart';

class _MockMux extends Mock implements MuxClient {}

class _MockRuntime extends Mock implements PhoneAlertsRuntime {}

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
  Future<bool> ready = Future.value(true);

  @override
  Future<bool> init(void Function(String payload) onTap) async {
    this.onTap = onTap;
    return ready;
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
  final owner = Object();

  _MockMux newMux() {
    final m = _MockMux();
    when(() => m.notifications).thenAnswer((_) => feed.stream);
    return m;
  }

  setUp(() async {
    ViewedSession.reset();
    feed = StreamController<MuxNotification>.broadcast(sync: true);
    mux = newMux();
    sink = _FakeSink();
    opened = [];
    runtime = PhoneAlertsRuntime(mux, sink, (uri) {
      opened.add(uri);
      return true;
    });
    await runtime.start();
  });

  tearDown(() async {
    ViewedSession.reset();
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
    ViewedSession.show(owner, 's1');
    feed.add(_n('n1', 's1'));
    feed.add(_n('n2', 's2', quiet: true));
    expect(sink.shown, isEmpty);
    feed.add(_n('n3', 's2'));
    expect(sink.shown.single.payload, 'operator://session/s2');
  });

  test('pull request alerts open the PRs tab', () {
    for (final type in ['ready_to_merge', 'pr_merged', 'pr_closed_unmerged']) {
      sink.shown.clear();
      feed.add(MuxNotification(id: type, sessionId: 's1', type: type, title: 'PR', body: 'merged', quiet: false));
      expect(sink.shown.single.payload, 'operator://prs', reason: type);
      expect(resolveDeepLink(Uri.parse(sink.shown.single.payload))?.tabIndex, kPrsTabIndex, reason: type);
    }
  });

  test('gives every notification its own id', () {
    feed.add(_n('n1', 's1'));
    feed.add(_n('n2', 's2'));
    expect(sink.shown.map((s) => s.id).toSet(), hasLength(2));
  });

  test('seeds ids from the clock so a relaunch does not reuse tray ids, staying within 31 bits', () async {
    await runtime.dispose();
    final seeded = PhoneAlertsRuntime(newMux(), sink, (_) => true, now: () => DateTime.fromMillisecondsSinceEpoch(0x17fffffff));
    await seeded.start();
    feed.add(_n('n1', 's1'));
    feed.add(_n('n2', 's2'));
    await seeded.dispose();
    expect(sink.shown.map((s) => s.id), [0x7fffffff, 0]);
  });

  test('start subscribes; foreground and background follow the app', () {
    verify(() => mux.subscribeNotifications()).called(1);
    runtime.background();
    verify(() => mux.unsubscribeNotifications()).called(1);
    verifyNever(() => mux.subscribeNotifications());
    runtime.foreground();
    verify(() => mux.subscribeNotifications()).called(1);
  });

  test('repeated lifecycle callbacks send one frame per change', () {
    clearInteractions(mux);
    runtime.foreground();
    runtime.background();
    runtime.background();
    runtime.foreground();
    runtime.foreground();
    verify(() => mux.unsubscribeNotifications()).called(1);
    verify(() => mux.subscribeNotifications()).called(1);
  });

  test('a background that arrives while start is still initialising keeps the feed unsubscribed', () async {
    final slowMux = newMux();
    final gate = Completer<bool>();
    final slowSink = _FakeSink()..ready = gate.future;
    final slow = PhoneAlertsRuntime(slowMux, slowSink, (_) => true);

    final starting = slow.start();
    slow.background();
    gate.complete(true);
    await starting;

    verifyNever(() => slowMux.subscribeNotifications());
    slow.foreground();
    verify(() => slowMux.subscribeNotifications()).called(1);
    await slow.dispose();
  });

  test('does not subscribe when the sink fails to initialise', () async {
    final failingMux = newMux();
    final failingSink = _FakeSink()..ready = Future<bool>.error(StateError('no plugin'));
    final failing = PhoneAlertsRuntime(failingMux, failingSink, (_) => true);

    await failing.start();
    failing.foreground();

    verifyNever(() => failingMux.subscribeNotifications());
    await failing.dispose();
  });

  test('does not subscribe when notification permission is denied, so the daemon keeps ntfy', () async {
    final deniedMux = newMux();
    final deniedSink = _FakeSink()..ready = Future.value(false);
    final denied = PhoneAlertsRuntime(deniedMux, deniedSink, (_) => true);

    await denied.start();
    denied.background();
    denied.foreground();

    verifyNever(() => deniedMux.subscribeNotifications());
    verifyNever(() => deniedMux.unsubscribeNotifications());
    await denied.dispose();
  });

  group('phoneAlertsLifecycle', () {
    testWidgets('pause and hide go to background; show and resume come back to foreground', (tester) async {
      final alerts = _MockRuntime();
      var resumed = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final listener = phoneAlertsLifecycle(() => alerts, onResume: () => resumed++);
      addTearDown(listener.dispose);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      verify(() => alerts.background()).called(1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      verify(() => alerts.background()).called(1);
      verifyNever(() => alerts.foreground());

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      verifyNever(() => alerts.foreground());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      verify(() => alerts.foreground()).called(1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      verify(() => alerts.foreground()).called(1);
      verifyNever(() => alerts.background());
      expect(resumed, 1);
    });
  });
}
