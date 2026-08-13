import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/orchestrator/data/model/params/launch_orchestrator_params.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';

abstract class OrchestratorRemoteDataSource {
  Future<GlobalResponse<OrchestratorModel>> launch(LaunchOrchestratorParams params);
}

class OrchestratorRemoteDataSourceImp implements OrchestratorRemoteDataSource {
  OrchestratorRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<OrchestratorModel>> launch(LaunchOrchestratorParams params) async {
    final response = await _apiConsumer.post(EndPoints.orchestrators, body: params.toJson());
    return GlobalResponse<OrchestratorModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) {
        final orchestrator = json['orchestrator'] as Map<String, dynamic>? ?? const {};
        return OrchestratorModel.fromJson({
          ...orchestrator,
          'projectId': orchestrator['projectId'] ?? params.projectId,
          'isTerminated': false,
        });
      },
    );
  }
}
