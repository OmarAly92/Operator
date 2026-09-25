import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/blocks/data/model/background_task_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_tasks_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/stop_session_task_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/stop_session_task_result_model.dart';

abstract class BackgroundTasksRemoteDataSource {
  Future<GlobalResponse<List<BackgroundTaskModel>>> getTasks(GetSessionTasksParams params);
  Future<GlobalResponse<StopSessionTaskResultModel>> stopTask(StopSessionTaskParams params);
}

class BackgroundTasksRemoteDataSourceImp implements BackgroundTasksRemoteDataSource {
  final ApiConsumer _apiConsumer;

  BackgroundTasksRemoteDataSourceImp(this._apiConsumer);

  @override
  Future<GlobalResponse<List<BackgroundTaskModel>>> getTasks(GetSessionTasksParams params) async {
    final response = await _apiConsumer.get(EndPoints.sessionTasks(params.sessionId));
    return GlobalResponse<List<BackgroundTaskModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: BackgroundTaskModel.listFromJson,
    );
  }

  @override
  Future<GlobalResponse<StopSessionTaskResultModel>> stopTask(StopSessionTaskParams params) async {
    final response = await _apiConsumer.post(EndPoints.sessionTaskStop(params.sessionId, params.taskId));
    return GlobalResponse<StopSessionTaskResultModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: StopSessionTaskResultModel.fromJson,
    );
  }
}
