import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

abstract class SessionsRemoteDataSource {
  Future<GlobalResponse<BoardSnapshot>> getBoard();
  Future<void> kill(String id);
  Future<void> restore(String id);
}

class SessionsRemoteDataSourceImp implements SessionsRemoteDataSource {
  SessionsRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<BoardSnapshot>> getBoard() async {
    final sessionsResponse = await _apiConsumer.get(EndPoints.sessions);

    final projectsFuture = _fetchProjects();
    final accountsFuture = _fetchAccountLabels();
    final projects = await projectsFuture;
    final accountLabels = await accountsFuture;

    return GlobalResponse<BoardSnapshot>.fromJson(
      sessionsResponse.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => BoardSnapshot(
        sessions: _rows(json).map(SessionModel.fromJson).toList(),
        projects: projects,
        accountLabels: accountLabels,
      ),
    );
  }

  Future<Map<String, String>> _fetchAccountLabels() async {
    try {
      final response = await _apiConsumer.get(EndPoints.claudeAccounts);
      final body = response.data as Map<String, dynamic>;
      return {
        for (final account in (body['accounts'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
          if (account['id'] is String) account['id'] as String: (account['label'] as String?) ?? account['id'] as String,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<List<ProjectModel>> _fetchProjects() async {
    try {
      final response = await _apiConsumer.get(EndPoints.projects);
      final body = response.data as Map<String, dynamic>;
      return (body['projects'] as List<dynamic>? ?? const [])
          .map((p) => ProjectModel.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<Map<String, dynamic>> _rows(dynamic body) =>
      ((body as Map<String, dynamic>?)?['sessions'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();

  @override
  Future<void> kill(String id) async {
    await _apiConsumer.post(EndPoints.sessionKill(id));
  }

  @override
  Future<void> restore(String id) async {
    await _apiConsumer.post(EndPoints.sessionRestore(id));
  }
}
