import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

abstract class SessionsRemoteDataSource {
  Future<GlobalResponse<BoardSnapshot>> getBoard();
  Future<GlobalResponse<BoardSnapshot>> getSessions(List<ProjectModel> projects);
  Future<void> kill(String id);
  Future<void> restore(String id);
}

class SessionsRemoteDataSourceImp implements SessionsRemoteDataSource {
  SessionsRemoteDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Future<GlobalResponse<BoardSnapshot>> getBoard() async {
    final sessionsResponse = await _apiConsumer.get(EndPoints.sessions);

    final projects = await _fetchProjects();
    return _board(sessionsResponse.data, projects);
  }

  @override
  Future<GlobalResponse<BoardSnapshot>> getSessions(List<ProjectModel> projects) async {
    final response = await _apiConsumer.get(EndPoints.sessions);
    return _board(response.data, projects);
  }

  GlobalResponse<BoardSnapshot> _board(dynamic sessionsBody, List<ProjectModel> projects) {
    final nameOf = {
      for (final project in projects)
        if (project.id != null) project.id!: project.name ?? project.id!,
    };

    return GlobalResponse<BoardSnapshot>.fromJson(
      sessionsBody as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => BoardSnapshot(
        allSessions: _rows(json).map(SessionModel.fromJson).toList(),
        sessions: _rows(json)
            .map(SessionModel.fromJson)
            .where((s) => s.kind != 'orchestrator')
            .toList(),
        orchestrators: _bestPerProject(_rows(json).where((row) => row['kind'] == 'orchestrator').toList())
            .map((row) => OrchestratorModel.fromJson(row, projectName: nameOf[row['projectId']]))
            .toList(),
        projects: projects,
      ),
    );
  }

  Future<List<ProjectModel>> _fetchProjects() async {
    final response = await _apiConsumer.get(EndPoints.projects);
    final body = response.data as Map<String, dynamic>;
    return (body['projects'] as List<dynamic>? ?? const [])
        .map((p) => ProjectModel.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  static List<Map<String, dynamic>> _rows(dynamic body) =>
      ((body as Map<String, dynamic>?)?['sessions'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();

  static List<Map<String, dynamic>> _bestPerProject(List<Map<String, dynamic>> rows) {
    final best = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final projectId = row['projectId'] as String? ?? '';
      final current = best[projectId];
      if (current == null || (current['isTerminated'] as bool? ?? false)) {
        best[projectId] = row;
      }
    }
    return best.values.toList();
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
