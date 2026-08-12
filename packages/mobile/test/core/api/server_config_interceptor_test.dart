import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';

class _StubStore implements ServerConfigSource {
  _StubStore(this.current);

  @override
  final ServerConfig? current;
}

void main() {
  group('ServerConfigInterceptor', () {
    test('stamps base url and authorization from the paired config', () {
      final interceptor = ServerConfigInterceptor(
        _StubStore(
          const ServerConfig(
            host: '10.0.0.5',
            httpPort: '3011',
            secure: false,
            password: 'secret12',
          ),
        ),
      );
      final options = RequestOptions(path: '/api/v1/projects');
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.baseUrl, 'http://10.0.0.5:3011');
      expect(options.headers['Authorization'], 'Bearer secret12');
    });

    test('rejects the request when no config is paired', () {
      final interceptor = ServerConfigInterceptor(_StubStore(null));
      final options = RequestOptions(path: '/api/v1/projects');

      expect(
        () => interceptor.onRequest(options, RequestInterceptorHandler()),
        throwsA(isA<DioException>()),
      );
    });

    test('a pairingTarget extra overrides the paired config', () {
      final interceptor = ServerConfigInterceptor(_StubStore(null));
      final target = const ServerConfig(host: '10.0.0.9', httpPort: '3011', secure: false, password: 'candidate');
      final options = RequestOptions(path: '/api/v1/sessions', extra: {'pairingTarget': target});
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.baseUrl, 'http://10.0.0.9:3011');
      expect(options.headers['Authorization'], 'Bearer candidate');
    });

    test('the paired config wins when no pairingTarget extra is set', () {
      final interceptor = ServerConfigInterceptor(
        _StubStore(const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'paired')),
      );
      final options = RequestOptions(path: '/api/v1/sessions');
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], 'Bearer paired');
    });
  });
}
