import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/operator_settings_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';

abstract class SpawnRemoteDataSource {
  Future<GlobalResponse<AgentCatalog>> getAgents();
  Future<GlobalResponse<AgentCatalog>> refreshAgents();
  Future<GlobalResponse<OperatorSettingsModel>> getSettings();
  Future<GlobalResponse<SessionModel>> spawn(SpawnSessionParams params);
}

class SpawnRemoteDataSourceImp implements SpawnRemoteDataSource {
  SpawnRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<AgentCatalog>> getAgents() async {
    final response = await _apiConsumer.get(EndPoints.agents);
    return GlobalResponse<AgentCatalog>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => AgentCatalog.fromJson(json),
    );
  }

  @override
  Future<GlobalResponse<AgentCatalog>> refreshAgents() async {
    final response = await _apiConsumer.post(EndPoints.agentsRefresh);
    return GlobalResponse<AgentCatalog>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => AgentCatalog.fromJson(json),
    );
  }

  @override
  Future<GlobalResponse<OperatorSettingsModel>> getSettings() async {
    final response = await _apiConsumer.get(EndPoints.settings);
    return GlobalResponse<OperatorSettingsModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => OperatorSettingsModel.fromJson(json),
    );
  }

  @override
  Future<GlobalResponse<SessionModel>> spawn(SpawnSessionParams params) async {
    final response = await _apiConsumer.post(EndPoints.sessions, body: params.toJson());
    return GlobalResponse<SessionModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => SessionModel.fromJson(
        json['session'] as Map<String, dynamic>? ?? json,
      ),
    );
  }
}
