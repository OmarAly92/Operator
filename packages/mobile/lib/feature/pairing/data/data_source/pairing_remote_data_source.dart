import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_identity_model.dart';

abstract class PairingRemoteDataSource {
  Future<DesktopIdentityModel> identify(ServerConfig target);
}

class PairingRemoteDataSourceImp implements PairingRemoteDataSource {
  PairingRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<DesktopIdentityModel> identify(ServerConfig target) async {
    final response = await _apiConsumer.get(EndPoints.desktop, options: Options(extra: {'pairingTarget': target}));
    final data = response.data;
    return DesktopIdentityModel.fromJson(data is Map<String, dynamic> ? data : const {});
  }
}
