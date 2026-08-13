import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';

class ConversationTurnModel extends Equatable {
  final String? id;
  final String? state;
  final String? providerTurnId;
  final String? errorMessage;
  final String? requestedAt;
  final String? startedAt;
  final String? completedAt;
  final bool? rolledBack;
  final bool hasDiff;
  final List<DiffFileModel> diffFiles;
  final bool? diffTruncated;
  final String? planExplanation;
  final List<PlanStepModel> planSteps;

  const ConversationTurnModel({
    this.id,
    this.state,
    this.providerTurnId,
    this.errorMessage,
    this.requestedAt,
    this.startedAt,
    this.completedAt,
    this.rolledBack,
    this.hasDiff = false,
    this.diffFiles = const [],
    this.diffTruncated,
    this.planExplanation,
    this.planSteps = const [],
  });

  factory ConversationTurnModel.fromJson(Map<String, dynamic> json) {
    final diff = json['diff'] is Map<String, dynamic>
        ? json['diff'] as Map<String, dynamic>
        : null;
    final plan = json['plan'] is Map<String, dynamic>
        ? json['plan'] as Map<String, dynamic>
        : null;
    return ConversationTurnModel(
      id: json['id'] as String?,
      state: json['state'] as String?,
      providerTurnId: json['providerTurnId'] as String?,
      errorMessage: json['errorMessage'] as String?,
      requestedAt: json['requestedAt'] as String?,
      startedAt: json['startedAt'] as String?,
      completedAt: json['completedAt'] as String?,
      rolledBack: json['rolledBack'] as bool?,
      hasDiff: diff != null,
      diffFiles: DiffFileModel.listFrom(diff?['files']),
      diffTruncated: diff?['truncated'] as bool?,
      planExplanation: plan?['explanation'] as String?,
      planSteps: PlanStepModel.listFrom(plan?['steps']),
    );
  }

  bool get hasPlan => planSteps.isNotEmpty;

  bool get isInFlight => state == 'running' || state == 'queued';

  @override
  List<Object?> get props => [
    id,
    state,
    providerTurnId,
    errorMessage,
    requestedAt,
    startedAt,
    completedAt,
    rolledBack,
    hasDiff,
    diffFiles,
    diffTruncated,
    planExplanation,
    planSteps,
  ];
}
