import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';

class SessionModel extends Equatable {
  const SessionModel({
    this.id,
    this.projectId,
    this.kind,
    this.status,
    this.activity,
    this.harness,
    this.mode,
    this.branch,
    this.issueId,
    this.displayName,
    this.createdAt,
    this.updatedAt,
    this.previewUrl,
    this.isTerminated,
    this.prs,
  });

  final String? id;
  final String? projectId;
  final String? kind;
  final String? status;
  final String? activity;
  final String? harness;
  final String? mode;
  final String? branch;
  final String? issueId;
  final String? displayName;
  final String? createdAt;
  final String? updatedAt;
  final String? previewUrl;
  final bool? isTerminated;
  final List<SessionPrModel>? prs;

  static String? _activityString(dynamic raw) {
    if (raw is String) return raw.isEmpty ? null : raw;
    if (raw is Map<String, dynamic> && raw['state'] is String) {
      final state = raw['state'] as String;
      return state.isEmpty ? null : state;
    }
    return null;
  }

  factory SessionModel.fromJson(Map<String, dynamic> json) => SessionModel(
    id: json['id'] as String?,
    projectId: json['projectId'] as String?,
    kind: json['kind'] as String?,
    status: json['status'] as String?,
    activity: _activityString(json['activity']),
    harness: json['harness'] as String?,
    mode: json['mode'] as String?,
    branch: json['branch'] as String?,
    issueId: json['issueId'] as String?,
    displayName: json['displayName'] as String?,
    createdAt: json['createdAt'] as String?,
    updatedAt: json['updatedAt'] as String?,
    previewUrl: json['previewUrl'] as String?,
    isTerminated: json['isTerminated'] as bool?,
    prs: (json['prs'] as List<dynamic>?)
        ?.map((pr) => SessionPrModel.fromJson(pr as Map<String, dynamic>))
        .toList(),
  );

  @override
  List<Object?> get props => [
    id, projectId, kind, status, activity, harness, mode, branch, issueId,
    displayName, createdAt, updatedAt, previewUrl, isTerminated, prs,
  ];
}
