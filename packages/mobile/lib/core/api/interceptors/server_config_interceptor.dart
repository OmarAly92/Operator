import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/server_config.dart';

abstract class ServerConfigSource {
  ServerConfig? get current;
}

class ServerConfigInterceptor extends Interceptor {
  ServerConfigInterceptor(this._source);

  final ServerConfigSource _source;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final override = options.extra['pairingTarget'] as ServerConfig?;
    final config = override ?? _source.current;
    if (config == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        message: 'No paired Operator server',
      );
    }

    options.baseUrl = config.httpBase;
    options.headers['Authorization'] = 'Bearer ${config.password}';
    handler.next(options);
  }
}
