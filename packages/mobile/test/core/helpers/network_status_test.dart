import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

class _StubSource implements ServerConfigSource {
  _StubSource(this.current);

  @override
  final ServerConfig? current;
}

const _config = ServerConfig(
  host: '10.0.0.5',
  httpPort: '3011',
  secure: false,
  password: 'secret12',
);

void main() {
  late _MockApiConsumer api;

  setUp(() => api = _MockApiConsumer());

  test('is disconnected when nothing is paired', () async {
    final status = NetworkStatusImp(api, _StubSource(null));
    expect(await status.isConnected, isFalse);
    verifyNever(() => api.get(any()));
  });

  test('is connected when the daemon answers the ping', () async {
    when(() => api.get(any())).thenAnswer(
      (_) async => Response<dynamic>(requestOptions: RequestOptions(path: '/'), statusCode: 200),
    );

    final status = NetworkStatusImp(api, _StubSource(_config));
    expect(await status.isConnected, isTrue);
  });

  test('is disconnected when the daemon is unreachable', () async {
    when(() => api.get(any())).thenThrow(
      DioException(requestOptions: RequestOptions(path: '/'), type: DioExceptionType.connectionTimeout),
    );

    final status = NetworkStatusImp(api, _StubSource(_config));
    expect(await status.isConnected, isFalse);
  });
}
