import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
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

    final orchestratorsFuture = _apiConsumer.get(EndPoints.orchestrators);
    final projectsFuture = _fetchProjects();
    final orchestratorsResponse = await orchestratorsFuture;
    final projects = await projectsFuture;

    final nameOf = {
      for (final project in projects)
        if (project.id != null) project.id!: project.name ?? project.id!,
    };

    return GlobalResponse<BoardSnapshot>.fromJson(
      sessionsResponse.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) => BoardSnapshot(
        sessions: _rows(json)
            .map(SessionModel.fromJson)
            .where((s) => s.kind != 'orchestrator')
            .toList(),
        orchestrators: _bestPerProject(_rows(orchestratorsResponse.data))
            .map((row) => OrchestratorModel.fromJson(row, projectName: nameOf[row['projectId']]))
            .toList(),
        projects: projects,
      ),
    );
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
