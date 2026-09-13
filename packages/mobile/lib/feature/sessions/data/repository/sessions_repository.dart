import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';

abstract class SessionsRepository {
  FutureResult<GlobalResponse<BoardSnapshot>> getBoard();
  FutureResult<GlobalResponse<BoardSnapshot>> getSessions(List<ProjectModel> projects);
  FutureResult<bool> kill(String id);
  FutureResult<bool> restore(String id);
}

class SessionsRepositoryImp implements SessionsRepository {
  SessionsRepositoryImp(this._remoteDataSource);

  final SessionsRemoteDataSource _remoteDataSource;

  @override
  FutureResult<GlobalResponse<BoardSnapshot>> getBoard() => _request(_remoteDataSource.getBoard);

  @override
  FutureResult<GlobalResponse<BoardSnapshot>> getSessions(List<ProjectModel> projects) =>
      _request(() => _remoteDataSource.getSessions(projects));

  @override
  FutureResult<bool> kill(String id) => _request(() async {
    await _remoteDataSource.kill(id);
    return true;
  });

  @override
  FutureResult<bool> restore(String id) => _request(() async {
    await _remoteDataSource.restore(id);
    return true;
  });

  FutureResult<T> _request<T>(Future<T> Function() request) async {
    try {
      return Result.success(await request());
    } on Failure catch (failure) {
      return Result.failure(failure);
    }
  }
}
