import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';

abstract class NetworkStatus {
  Future<bool> get isConnected;
}

class NetworkStatusImp implements NetworkStatus {
  NetworkStatusImp(this._apiConsumer, this._configSource);

  final ApiConsumer _apiConsumer;
  final ServerConfigSource _configSource;

  @override
  Future<bool> get isConnected async {
    if (_configSource.current == null) return false;
    try {
      await _apiConsumer.get(EndPoints.projects);
      return true;
    } catch (_) {
      return false;
    }
  }
}
