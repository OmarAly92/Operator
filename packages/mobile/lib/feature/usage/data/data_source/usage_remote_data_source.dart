import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/usage/data/model/params/usage_rollup_params.dart';
import 'package:operator_mobile/feature/usage/data/model/usage_rollup_model.dart';

abstract class UsageRemoteDataSource {
  Future<GlobalResponse<Map<String, dynamic>>> sessionContext(String sessionId);
  Future<GlobalResponse<UsageRollupModel>> rollup(UsageRollupParams params);
}

class UsageRemoteDataSourceImp implements UsageRemoteDataSource {
  UsageRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<Map<String, dynamic>>> sessionContext(
    String sessionId,
  ) async {
    final response = await _apiConsumer.get(EndPoints.usageSession(sessionId));
    return GlobalResponse<Map<String, dynamic>>.fromJson(
      Map<String, dynamic>.from(response.data as Map),
      withDataKey: false,
      fromJsonT: (json) => json,
    );
  }

  @override
  Future<GlobalResponse<UsageRollupModel>> rollup(
    UsageRollupParams params,
  ) async {
    final response = await _apiConsumer.get(
      EndPoints.usageRollup,
      queryParameters: params.toJson(),
    );
    return GlobalResponse<UsageRollupModel>.fromJson(
      Map<String, dynamic>.from(response.data as Map),
      withDataKey: false,
      fromJsonT: UsageRollupModel.fromJson,
    );
  }
}
