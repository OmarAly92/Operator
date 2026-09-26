import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/sessions/data/model/activity_string.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';

class SessionModel extends Equatable {
  const SessionModel({
    this.id,
    this.projectId,
    this.status,
    this.activity,
    this.activitySince,
    this.harness,
    this.branch,
    this.issueId,
    this.displayName,
    this.createdAt,
    this.updatedAt,
    this.previewUrl,
    this.isTerminated,
    this.prs,
    this.workspaceMode,
    this.workspacePath,
    this.claudeAccountId,
    this.model,
    this.agentReportState,
    this.agentReportReason,
    this.permissionMode,
    this.permissionModeSupported,
    this.permissionModeCycle,
  });

  final String? id;
  final String? projectId;
  final String? status;
  final String? activity;
  final String? activitySince;
  final String? harness;
  final String? branch;
  final String? issueId;
  final String? displayName;
  final String? createdAt;
  final String? updatedAt;
  final String? previewUrl;
  final bool? isTerminated;
  final List<SessionPrModel>? prs;
  final String? workspaceMode;
  final String? workspacePath;
  final String? claudeAccountId;
  final String? model;

  /// What the agent reported about its own card through the Operator MCP server:
  /// `needs_you` or `ready_for_review`; null when it reported nothing.
  final String? agentReportState;

  /// The agent's one-line reason for [agentReportState].
  final String? agentReportReason;

  final String? permissionMode;
  final bool? permissionModeSupported;
  final List<String>? permissionModeCycle;

  factory SessionModel.fromJson(Map<String, dynamic> json) => SessionModel(
    id: json['id'] as String?,
    projectId: json['projectId'] as String?,
    status: json['status'] as String?,
    activity: activityString(json['activity']),
    activitySince: activitySinceString(json['activity']),
    harness: json['harness'] as String?,
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
    workspaceMode: json['workspaceMode'] as String?,
    workspacePath: json['workspacePath'] as String?,
    claudeAccountId: json['claudeAccountId'] as String?,
    model: json['model'] as String?,
    agentReportState: _agentReport(json)?['state'] as String?,
    agentReportReason: _agentReport(json)?['reason'] as String?,
    permissionMode: json['permissionMode'] as String?,
    permissionModeSupported: _capabilities(json)?['permissionMode'] as bool?,
    permissionModeCycle: (_capabilities(json)?['permissionModeCycle'] as List<dynamic>?)?.whereType<String>().toList(),
  );

  static Map<String, dynamic>? _agentReport(Map<String, dynamic> json) {
    final report = json['agentReport'];
    return report is Map<String, dynamic> ? report : null;
  }

  static Map<String, dynamic>? _capabilities(Map<String, dynamic> json) {
    final capabilities = json['capabilities'];
    return capabilities is Map<String, dynamic> ? capabilities : null;
  }

  @override
  List<Object?> get props => [
    id, projectId, status, activity, activitySince, harness, branch, issueId,
    displayName, createdAt, updatedAt, previewUrl, isTerminated, prs,
    workspaceMode, workspacePath, claudeAccountId, model,
    agentReportState, agentReportReason,
    permissionMode, permissionModeSupported, permissionModeCycle,
  ];
}
