import 'dart:async';

import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';

const kTestDesktop = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'd-1');

class TestConfigSource implements ServerConfigSource {
  TestConfigSource([this.current = kTestDesktop]);

  final StreamController<ServerConfig?> controller = StreamController<ServerConfig?>.broadcast(sync: true);

  @override
  ServerConfig? current;

  @override
  Stream<ServerConfig?> get changes => controller.stream;

  void set(ServerConfig? next) {
    current = next;
    controller.add(next);
  }
}

class ConnectionHarness {
  ConnectionHarness({TestConfigSource? config, String? desktopName = 'Mac', DateTime Function()? clock})
    : config = config ?? TestConfigSource() {
    cubit = ConnectionCubit(reports, muxStatus.stream, this.config, desktopNames: names.stream, clock: clock);
    if (desktopName != null) names.add(desktopName);
  }

  final ConnectionReports reports = ConnectionReports();
  final StreamController<MuxStatus> muxStatus = StreamController<MuxStatus>.broadcast(sync: true);
  final StreamController<String?> names = StreamController<String?>.broadcast(sync: true);
  final TestConfigSource config;
  late final ConnectionCubit cubit;

  void report(ConnectionOutcome outcome, {String path = '/api/v1/sessions', DateTime? at, ServerConfig? sentTo}) =>
      reports.add(ConnectionReport(outcome, path: path, at: at ?? DateTime.now(), sentTo: sentTo));

  Future<void> dispose() async {
    await cubit.close();
    await muxStatus.close();
    await names.close();
    await config.controller.close();
  }
}
