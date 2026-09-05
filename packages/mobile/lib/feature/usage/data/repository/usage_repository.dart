import 'package:operator_mobile/feature/usage/data/data_source/usage_remote_data_source.dart';
import 'package:operator_mobile/feature/usage/data/model/params/usage_rollup_params.dart';
import 'package:operator_mobile/feature/usage/data/model/session_context_model.dart';
import 'package:operator_mobile/feature/usage/data/model/usage_rollup_model.dart';

class UsageRepository {
  UsageRepository(this._remoteDataSource);

  final UsageRemoteDataSource _remoteDataSource;

  Future<SessionContextModel?> sessionContext(String sessionId) async {
    final response = await _remoteDataSource.sessionContext(sessionId);
    final context = response.data?['context'];
    if (context is! Map) return null;
    return SessionContextModel.fromJson(Map<String, dynamic>.from(context));
  }

  Future<UsageRollupModel> rollup(UsageRollupParams params) async {
    final response = await _remoteDataSource.rollup(params);
    return response.data ?? const UsageRollupModel();
  }
}
