import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/spawn/data/data_source/spawn_remote_data_source.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';

abstract class SpawnRepository {
  FutureResult<GlobalResponse<AgentCatalog>> getAgents();
  FutureResult<GlobalResponse<AgentCatalog>> refreshAgents();
  FutureResult<GlobalResponse<SessionModel>> spawn(SpawnSessionParams params);
}

class SpawnRepositoryImp implements SpawnRepository {
  SpawnRepositoryImp(this._remoteDataSource, this._network);

  final SpawnRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<AgentCatalog>> getAgents() async {
    if (await _network.isConnected) {
      try {
        return Result.success(await _remoteDataSource.getAgents());
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  @override
  FutureResult<GlobalResponse<AgentCatalog>> refreshAgents() async {
    if (await _network.isConnected) {
      try {
        return Result.success(await _remoteDataSource.refreshAgents());
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  @override
  FutureResult<GlobalResponse<SessionModel>> spawn(SpawnSessionParams params) async {
    if (await _network.isConnected) {
      try {
        return Result.success(await _remoteDataSource.spawn(params));
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }
}
