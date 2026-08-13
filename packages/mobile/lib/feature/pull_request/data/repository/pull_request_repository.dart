import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pull_request/data/data_source/pull_request_remote_data_source.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';

abstract class PullRequestRepository {
  FutureResult<GlobalResponse<List<SessionPrSummaryModel>>> getSessionPr(String sessionId);
  FutureResult<bool> merge(int number);
}

class PullRequestRepositoryImp implements PullRequestRepository {
  PullRequestRepositoryImp(this._remoteDataSource, this._network);

  final PullRequestRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<List<SessionPrSummaryModel>>> getSessionPr(String sessionId) async {
    if (await _network.isConnected) {
      try {
        return Result.success(await _remoteDataSource.getSessionPr(sessionId));
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  @override
  FutureResult<bool> merge(int number) async {
    if (await _network.isConnected) {
      try {
        await _remoteDataSource.merge(number);
        return Result.success(true);
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }
}
