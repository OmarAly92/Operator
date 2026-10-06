import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/dio_consumer.dart';
import 'package:operator_mobile/core/api/interceptors/connection_report_interceptor.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';

class _StaticConfig implements ServerConfigSource {
  @override
  ServerConfig? get current => const ServerConfig(host: 'h', httpPort: '3011', secure: false, password: 'pw');

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

void main() {
  test('every request carries the ngrok interstitial bypass header', () {
    final consumer = DioConsumer(_StaticConfig());
    expect(consumer.client.options.headers['ngrok-skip-browser-warning'], '1');
  });

  test('the standard json headers are still present', () {
    final consumer = DioConsumer(_StaticConfig());
    expect(consumer.client.options.headers['accept'], 'application/json');
    expect(consumer.client.options.headers['Content-Type'], 'application/json');
  });

  test('reports every outcome to the connection state and keeps the 12 s timeouts', () {
    final consumer = DioConsumer(_StaticConfig(), reports: ConnectionReports());

    expect(consumer.client.interceptors.whereType<ConnectionReportInterceptor>(), hasLength(1));
    expect(consumer.client.options.connectTimeout, const Duration(seconds: 12));
    expect(consumer.client.options.receiveTimeout, const Duration(seconds: 12));
  });
}
