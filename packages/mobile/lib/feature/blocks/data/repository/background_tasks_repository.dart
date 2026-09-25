import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/background_tasks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/background_task_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_tasks_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/stop_session_task_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/stop_session_task_result_model.dart';

abstract class BackgroundTasksRepository {
  FutureResult<GlobalResponse<List<BackgroundTaskModel>>> getTasks(GetSessionTasksParams params);
  FutureResult<GlobalResponse<StopSessionTaskResultModel>> stopTask(StopSessionTaskParams params);
}

class BackgroundTasksRepositoryImp implements BackgroundTasksRepository {
  BackgroundTasksRepositoryImp(this._remoteDataSource, this._network);

  final BackgroundTasksRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<List<BackgroundTaskModel>>> getTasks(GetSessionTasksParams params) =>
      _guard(() => _remoteDataSource.getTasks(params));

  @override
  FutureResult<GlobalResponse<StopSessionTaskResultModel>> stopTask(StopSessionTaskParams params) =>
      _guard(() => _remoteDataSource.stopTask(params));

  Future<Result<T, Failure>> _guard<T>(Future<T> Function() action) async {
    if (await _network.isConnected) {
      try {
        return Result.success(await action());
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }
}
