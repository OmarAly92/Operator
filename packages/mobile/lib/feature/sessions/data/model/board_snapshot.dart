import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

class BoardSnapshot extends Equatable {
  const BoardSnapshot({
    this.sessions = const [],
    this.orchestrators = const [],
    this.projects = const [],
  });

  final List<SessionModel> sessions;
  final List<OrchestratorModel> orchestrators;
  final List<ProjectModel> projects;

  @override
  List<Object?> get props => [sessions, orchestrators, projects];
}
