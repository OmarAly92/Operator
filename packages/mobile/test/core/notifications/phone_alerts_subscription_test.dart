import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/mux_socket.dart';
import 'package:operator_mobile/core/notifications/local_alert_sink.dart';
import 'package:operator_mobile/core/notifications/phone_alerts_runtime.dart';

class _Socket implements MuxSocket {
  final opened = Completer<void>();
  final _incoming = StreamController<dynamic>.broadcast();
  final List<String> sent = [];

  @override
  Future<void> get ready => opened.future;

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() => _incoming.close();

  List<String> get notificationFrames => sent
      .map((s) => jsonDecode(s) as Map<String, dynamic>)
      .where((m) => m['ch'] == 'notifications')
      .map((m) => m['type'] as String)
      .toList();
}

class _Source implements ServerConfigSource {
  @override
  ServerConfig? current = const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12');

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

class _AllowedSink implements LocalAlertSink {
  @override
  Future<bool> init(void Function(String payload) onTap) async => true;

  @override
  Future<void> show({required int id, required String title, required String body, required String payload}) async {}
}

void main() {
  testWidgets('cold launch with permission allowed sends one subscribe once the socket opens, and follows the app',
      (tester) async {
    final sockets = <_Socket>[];
    final mux = MuxClient(_Source(), connect: (_, _) {
      final socket = _Socket();
      sockets.add(socket);
      return socket;
    });
    final runtime = PhoneAlertsRuntime(mux, _AllowedSink(), (_) => true);
    final lifecycle = phoneAlertsLifecycle(() => runtime);

    mux.connect();
    mux.subscribeSessions();
    await runtime.start();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    sockets.single.opened.complete();
    await tester.pump();
    expect(sockets.single.notificationFrames, ['subscribe']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(sockets.single.notificationFrames, ['subscribe', 'unsubscribe']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(sockets.single.notificationFrames, ['subscribe', 'unsubscribe', 'subscribe']);

    lifecycle.dispose();
    unawaited(runtime.dispose());
    unawaited(mux.disconnect());
    await tester.pump();
  });
}
