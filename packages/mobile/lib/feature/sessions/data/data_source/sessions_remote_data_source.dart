import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';

abstract class SessionsRemoteDataSource {
  Future<BoardPayload> getBoard();
  Future<void> kill(String id);
  Future<void> restore(String id);
}

class SessionsRemoteDataSourceImp implements SessionsRemoteDataSource {
  SessionsRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<BoardPayload> getBoard() async {
    final sessionsResponse = await _apiConsumer.get(EndPoints.sessions);
    final sessions = sessionsResponse.data;
    if (sessions is! Map<String, dynamic>) {
      throw MappingFailure(error: 'sessions body is ${sessions.runtimeType}', stacktrace: StackTrace.current);
    }

    final projectsFuture = _optionalBody(EndPoints.projects);
    final accountsFuture = _optionalBody(EndPoints.claudeAccounts);
    final projects = await projectsFuture;
    final accounts = await accountsFuture;

    return BoardPayload(sessions: sessions, projects: projects, accounts: accounts);
  }

  Future<Map<String, dynamic>?> _optionalBody(String path) async {
    try {
      final response = await _apiConsumer.get(path);
      return response.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> kill(String id) async {
    await _apiConsumer.post(EndPoints.sessionKill(id));
  }

  @override
  Future<void> restore(String id) async {
    await _apiConsumer.post(EndPoints.sessionRestore(id));
  }
}
