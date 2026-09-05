import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/session_control_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_answer_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_decision_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/pending_interaction_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';

abstract class SessionControlRepository {
  FutureResult<GlobalResponse<SessionCommandResultModel>> sendCommand(
    String sessionId,
    SessionCommandParams params,
  );
  FutureResult<GlobalResponse<SessionCommandResultModel>> decide(
    String sessionId,
    SessionDecisionParams params,
  );
  FutureResult<GlobalResponse<SessionCommandResultModel>> answer(
    String sessionId,
    SessionAnswerParams params,
  );
  FutureResult<GlobalResponse<List<PendingInteractionModel>>> getInteractions(String sessionId);
}

class SessionControlRepositoryImp implements SessionControlRepository {
  SessionControlRepositoryImp(this._remoteDataSource, this._network);

  final SessionControlRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<SessionCommandResultModel>> sendCommand(
    String sessionId,
    SessionCommandParams params,
  ) => _guard(() => _remoteDataSource.sendCommand(sessionId, params));

  @override
  FutureResult<GlobalResponse<SessionCommandResultModel>> decide(
    String sessionId,
    SessionDecisionParams params,
  ) => _guard(() => _remoteDataSource.decide(sessionId, params));

  @override
  FutureResult<GlobalResponse<SessionCommandResultModel>> answer(
    String sessionId,
    SessionAnswerParams params,
  ) => _guard(() => _remoteDataSource.answer(sessionId, params));

  @override
  FutureResult<GlobalResponse<List<PendingInteractionModel>>> getInteractions(String sessionId) =>
      _guard(() => _remoteDataSource.getInteractions(sessionId));

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
