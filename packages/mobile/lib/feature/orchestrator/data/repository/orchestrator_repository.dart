import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/orchestrator/data/data_source/orchestrator_remote_data_source.dart';
import 'package:operator_mobile/feature/orchestrator/data/model/params/launch_orchestrator_params.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';

abstract class OrchestratorRepository {
  FutureResult<GlobalResponse<OrchestratorModel>> launch(LaunchOrchestratorParams params);
}

class OrchestratorRepositoryImp implements OrchestratorRepository {
  OrchestratorRepositoryImp(this._remoteDataSource, this._network);

  final OrchestratorRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<OrchestratorModel>> launch(LaunchOrchestratorParams params) async {
    if (await _network.isConnected) {
      try {
        return Result.success(await _remoteDataSource.launch(params));
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }
}
