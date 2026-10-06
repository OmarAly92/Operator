import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';
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

  factory BoardSnapshot.fromPayload(BoardPayload payload) => BoardSnapshot(
    sessions: (payload.sessions['sessions'] as List<dynamic>? ?? const [])
        .map((row) => SessionModel.fromJson(row as Map<String, dynamic>))
        .toList(),
    projects: _projects(payload.projects),
    accountLabels: _accountLabels(payload.accounts),
  );

  static List<ProjectModel> _projects(Map<String, dynamic>? body) {
    try {
      return (body?['projects'] as List<dynamic>? ?? const [])
          .map((row) => ProjectModel.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Map<String, String> _accountLabels(Map<String, dynamic>? body) {
    try {
      return {
        for (final account in (body?['accounts'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
          if (account['id'] is String) account['id'] as String: (account['label'] as String?) ?? account['id'] as String,
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  List<Object?> get props => [sessions, projects, accountLabels];
}
