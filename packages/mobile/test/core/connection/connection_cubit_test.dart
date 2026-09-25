import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_backoff.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';

import '../../helpers/connection_harness.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 25, 9);

  group('maps each outcome to its state', () {
    final cases = <ConnectionOutcome, Matcher>{
      ConnectionOutcome.online: isA<ConnectionOnlineState>(),
      ConnectionOutcome.unreachable: isA<ConnectionOfflineState>().having(
        (s) => s.reason,
        'reason',
        ConnectionFailure.unreachable,
      ),
      ConnectionOutcome.rateLimited: isA<ConnectionOfflineState>().having(
        (s) => s.reason,
        'reason',
        ConnectionFailure.rateLimited,
      ),
      ConnectionOutcome.serverError: isA<ConnectionOfflineState>().having(
        (s) => s.reason,
        'reason',
        ConnectionFailure.serverError,
      ),
      ConnectionOutcome.auth: isA<ConnectionAuthFailedState>(),
    };
    for (final entry in cases.entries) {
      test(entry.key.name, () async {
        final harness = ConnectionHarness();
        harness.report(entry.key, at: t0);
        expect(harness.cubit.state, entry.value);
        expect(harness.cubit.state.desktopName, 'Mac');
        await harness.dispose();
      });
    }
  });

  test('starts connecting', () async {
    final harness = ConnectionHarness();
    expect(harness.cubit.state, isA<ConnectionConnectingState>());
    await harness.dispose();
  });

  test('seeds itself from a report that landed before it existed', () async {
    final reports = ConnectionReports()
      ..add(ConnectionReport(ConnectionOutcome.auth, path: EndPoints.sessions, at: t0));

    final cubit = ConnectionCubit(reports, const Stream<MuxStatus>.empty(), TestConfigSource());

    expect(cubit.state, isA<ConnectionAuthFailedState>());
    await cubit.close();
  });

  test('offline remembers when the desktop was last seen', () async {
    final harness = ConnectionHarness();
    harness.report(ConnectionOutcome.online, at: t0);
    harness.report(ConnectionOutcome.unreachable, at: t0.add(const Duration(minutes: 5)));

    expect(harness.cubit.state, isA<ConnectionOfflineState>().having((s) => s.lastSeenAt, 'lastSeenAt', t0));
    await harness.dispose();
  });

  test('backs off 1 s, 2 s, 4 s … up to 30 s while offline, and resets once online', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      final retriesAt = <int>[];
      harness.cubit.retries.listen((_) {
        retriesAt.add(async.elapsed.inSeconds);
        harness.report(ConnectionOutcome.unreachable);
      });

      harness.report(ConnectionOutcome.unreachable);
      async.elapse(const Duration(seconds: 125));
      expect(retriesAt, [1, 3, 7, 15, 31, 61, 91, 121]);

      harness.report(ConnectionOutcome.online);
      retriesAt.clear();
      final back = async.elapsed.inSeconds;
      harness.report(ConnectionOutcome.unreachable);
      async.elapse(const Duration(seconds: 2));
      expect(retriesAt, [back + 1]);
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('a /healthz 200 while offline neither recovers nor resets the backoff', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      final retriesAt = <int>[];
      final states = <AppConnectionState>[];
      harness.cubit.stream.listen(states.add);
      harness.cubit.retries.listen((_) {
        retriesAt.add(async.elapsed.inSeconds);
        harness.report(ConnectionOutcome.online, path: EndPoints.health);
        harness.report(ConnectionOutcome.serverError);
      });

      harness.report(ConnectionOutcome.serverError);
      async.elapse(const Duration(seconds: 125));

      expect(retriesAt, [1, 3, 7, 15, 31, 61, 91, 121]);
      expect(states, everyElement(isA<ConnectionOfflineState>()));
      expect(harness.cubit.state, isA<ConnectionOfflineState>());
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('a /healthz 200 while offline refreshes when the desktop was last seen', () async {
    final harness = ConnectionHarness();
    harness.report(ConnectionOutcome.unreachable, at: t0);
    harness.report(ConnectionOutcome.online, path: EndPoints.health, at: t0.add(const Duration(minutes: 1)));

    expect(
      harness.cubit.state,
      isA<ConnectionOfflineState>().having((s) => s.lastSeenAt, 'lastSeenAt', t0.add(const Duration(minutes: 1))),
    );
    await harness.dispose();
  });

  test('rate-limited waits a full minute before the next probe', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      var retries = 0;
      harness.cubit.retries.listen((_) => retries++);

      harness.report(ConnectionOutcome.rateLimited);
      async.elapse(const Duration(seconds: 59));
      expect(retries, 0);
      async.elapse(const Duration(seconds: 1));
      expect(retries, 1);
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('an auth failure stops every retry, and neither /healthz nor more failures clear it', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      var retries = 0;
      harness.cubit.retries.listen((_) => retries++);

      harness.report(ConnectionOutcome.unreachable);
      harness.report(ConnectionOutcome.auth);
      async.elapse(const Duration(minutes: 5));
      expect(retries, 0);
      expect(harness.cubit.authFailed, isTrue);

      harness.report(ConnectionOutcome.online, path: EndPoints.health);
      harness.report(ConnectionOutcome.unreachable);
      harness.cubit.resumed();
      async.elapse(const Duration(minutes: 1));
      expect(harness.cubit.state, isA<ConnectionAuthFailedState>());
      expect(retries, 0);

      harness.report(ConnectionOutcome.online);
      expect(harness.cubit.state, isA<ConnectionOnlineState>());
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('each auth episode is counted once', () async {
    final harness = ConnectionHarness();
    final episodes = <int>[];
    final sub = harness.cubit.stream.listen((state) {
      if (state is ConnectionAuthFailedState) episodes.add(state.episode);
    });

    harness.report(ConnectionOutcome.auth);
    harness.report(ConnectionOutcome.auth);
    harness.report(ConnectionOutcome.online);
    harness.report(ConnectionOutcome.auth);
    await Future<void>.delayed(Duration.zero);

    expect(episodes, [1, 2]);
    await sub.cancel();
    await harness.dispose();
  });

  test('resuming while offline probes at once and restarts the backoff', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      var retries = 0;
      harness.cubit.retries.listen((_) => retries++);
      harness.report(ConnectionOutcome.unreachable);
      async.elapse(const Duration(milliseconds: 500));

      harness.cubit.resumed();
      async.flushMicrotasks();
      expect(retries, 1);

      harness.report(ConnectionOutcome.online);
      harness.cubit.resumed();
      async.flushMicrotasks();
      expect(retries, 1);
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('the mux opening means online, even after an auth failure', () async {
    final harness = ConnectionHarness();
    harness.report(ConnectionOutcome.auth);

    harness.muxStatus.add(MuxStatus.open);

    expect(harness.cubit.state, isA<ConnectionOnlineState>());
    await harness.dispose();
  });

  test('mux errors while online probe at most once per backoff window', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      var retries = 0;
      harness.cubit.retries.listen((_) => retries++);
      harness.report(ConnectionOutcome.online);

      harness.muxStatus.add(MuxStatus.error);
      harness.muxStatus.add(MuxStatus.error);
      async.elapse(const Duration(milliseconds: 500));
      harness.muxStatus.add(MuxStatus.error);
      async.flushMicrotasks();
      expect(retries, 1);

      async.elapse(ConnectionBackoff.initial);
      harness.muxStatus.add(MuxStatus.error);
      async.flushMicrotasks();
      expect(retries, 2);
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('a report from the desktop the app switched away from is ignored', () async {
    final harness = ConnectionHarness();
    harness.report(ConnectionOutcome.online, sentTo: kTestDesktop);
    const next = ServerConfig(host: 'h', httpPort: '1', secure: false, password: 'p', desktopId: 'd-2');
    harness.config.set(next);

    harness.report(ConnectionOutcome.auth, sentTo: kTestDesktop);

    expect(harness.cubit.state, isA<ConnectionConnectingState>());
    expect(harness.cubit.authFailed, isFalse);

    harness.report(ConnectionOutcome.auth, sentTo: next);
    expect(harness.cubit.state, isA<ConnectionAuthFailedState>());
    await harness.dispose();
  });

  test('a report that landed before a desktop switch does not seed the cubit', () async {
    final reports = ConnectionReports()
      ..add(ConnectionReport(ConnectionOutcome.auth, path: EndPoints.sessions, at: t0, sentTo: kTestDesktop));
    final config = TestConfigSource(
      const ServerConfig(host: 'h', httpPort: '1', secure: false, password: 'p', desktopId: 'd-2'),
    );

    final cubit = ConnectionCubit(reports, const Stream<MuxStatus>.empty(), config);

    expect(cubit.state, isA<ConnectionConnectingState>());
    await cubit.close();
    await config.controller.close();
  });

  test('clearing an auth failure asks everyone to retry once', () async {
    final harness = ConnectionHarness();
    var retries = 0;
    harness.cubit.retries.listen((_) => retries++);
    harness.report(ConnectionOutcome.auth);

    harness.report(ConnectionOutcome.online);
    harness.report(ConnectionOutcome.online);
    await Future<void>.delayed(Duration.zero);

    expect(retries, 1);
    await harness.dispose();
  });

  test('a mux error while online asks for one probe instead of going offline', () async {
    final harness = ConnectionHarness();
    var retries = 0;
    harness.cubit.retries.listen((_) => retries++);
    harness.report(ConnectionOutcome.online);

    harness.muxStatus.add(MuxStatus.error);
    await Future<void>.delayed(Duration.zero);

    expect(harness.cubit.state, isA<ConnectionOnlineState>());
    expect(retries, 1);
    await harness.dispose();
  });

  test('a desktop change cancels the pending retry and starts connecting, keeping the name', () {
    fakeAsync((async) {
      final harness = ConnectionHarness();
      var retries = 0;
      harness.cubit.retries.listen((_) => retries++);
      harness.report(ConnectionOutcome.unreachable);

      harness.config.set(const ServerConfig(host: 'h', httpPort: '1', secure: false, password: 'p', desktopId: 'd-2'));
      async.elapse(const Duration(seconds: 5));

      expect(retries, 0);
      expect(harness.cubit.state, isA<ConnectionConnectingState>());
      expect(harness.cubit.state.desktopName, 'Mac');
      harness.cubit.close();
      async.flushMicrotasks();
    });
  });

  test('the desktop name follows the active desktop row', () async {
    final harness = ConnectionHarness(desktopName: null);
    harness.report(ConnectionOutcome.online);

    harness.names.add('MacBook');

    expect(harness.cubit.state, isA<ConnectionOnlineState>().having((s) => s.desktopName, 'name', 'MacBook'));
    await harness.dispose();
  });
}
