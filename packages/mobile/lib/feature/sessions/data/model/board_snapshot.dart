import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

class BoardSnapshot extends Equatable {
  const BoardSnapshot({
    this.sessions = const [],
    this.projects = const [],
    this.accountLabels = const {},
  });

  final List<SessionModel> sessions;
  final List<ProjectModel> projects;
  final Map<String, String> accountLabels;

  @override
  List<Object?> get props => [sessions, projects, accountLabels];
}
