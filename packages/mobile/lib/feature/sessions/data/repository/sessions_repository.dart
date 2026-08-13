import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';

abstract class SessionsRepository {
  FutureResult<GlobalResponse<BoardSnapshot>> getBoard();
  FutureResult<bool> kill(String id);
  FutureResult<bool> restore(String id);
}

class SessionsRepositoryImp implements SessionsRepository {
  SessionsRepositoryImp(this._remoteDataSource, this._network);

  final SessionsRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<BoardSnapshot>> getBoard() async {
    if (await _network.isConnected) {
      try {
        return Result.success(await _remoteDataSource.getBoard());
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  @override
  FutureResult<bool> kill(String id) async {
    if (await _network.isConnected) {
      try {
        await _remoteDataSource.kill(id);
        return Result.success(true);
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  @override
  FutureResult<bool> restore(String id) async {
    if (await _network.isConnected) {
      try {
        await _remoteDataSource.restore(id);
        return Result.success(true);
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }
}
