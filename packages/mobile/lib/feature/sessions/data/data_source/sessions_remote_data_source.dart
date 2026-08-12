import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

abstract class SessionsRemoteDataSource {
  Future<GlobalResponse<List<SessionModel>>> getSessions();
  Future<void> kill(String id);
  Future<void> restore(String id);
}

class SessionsRemoteDataSourceImp implements SessionsRemoteDataSource {
  SessionsRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<List<SessionModel>>> getSessions() async {
    final response = await _apiConsumer.get(EndPoints.sessions);
    return GlobalResponse<List<SessionModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => (json['sessions'] as List<dynamic>)
          .map((s) => SessionModel.fromJson(s as Map<String, dynamic>))
          .where((s) => s.kind != 'orchestrator')
          .toList(),
    );
  }

  @override
  Future<void> kill(String id) async {
    await _apiConsumer.post(EndPoints.sessionKill(id));
  }

  @override
  Future<void> restore(String id) async {
    await _apiConsumer.post(EndPoints.sessionRestore(id));
  }
}
