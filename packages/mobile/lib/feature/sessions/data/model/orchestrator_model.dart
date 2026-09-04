import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/sessions/data/model/activity_string.dart';

class OrchestratorModel extends Equatable {
  const OrchestratorModel({
    this.id,
    this.projectId,
    this.projectName,
    this.status,
    this.activity,
    this.harness,
    this.updatedAt,
    this.hasRuntime,
    this.isTerminal,
  });

  final String? id;
  final String? projectId;
  final String? projectName;
  final String? status;
  final String? activity;
  final String? harness;
  final String? updatedAt;
  final bool? hasRuntime;
  final bool? isTerminal;

  factory OrchestratorModel.fromJson(Map<String, dynamic> json, {String? projectName}) {
    final isTerminated = json['isTerminated'] as bool? ?? false;
    final projectId = json['projectId'] as String?;
    return OrchestratorModel(
      id: json['id'] as String?,
      projectId: projectId,
      projectName: projectName ?? projectId,
      status: json['status'] as String?,
      activity: activityString(json['activity']),
      harness: json['harness'] as String?,
      updatedAt: json['updatedAt'] as String?,
      hasRuntime: !isTerminated,
      isTerminal: isTerminated,
    );
  }

  @override
  List<Object?> get props => [
    id, projectId, projectName, status, activity, harness, updatedAt, hasRuntime, isTerminal,
  ];
}
