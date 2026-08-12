import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config.dart';

abstract class PairingRemoteDataSource {
  Future<void> ping(ServerConfig target);
}

class PairingRemoteDataSourceImp implements PairingRemoteDataSource {
  PairingRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<void> ping(ServerConfig target) async {
    await _apiConsumer.get(EndPoints.sessions, options: Options(extra: {'pairingTarget': target}));
  }
}
