import 'package:equatable/equatable.dart';

class InterfaceTransitionModel extends Equatable {
  final String? id;
  final String? sessionId;
  final String? sourceMode;
  final String? targetMode;
  final String? policy;
  final String? phase;
  final String? errorCode;
  final String? errorDetail;
  final String? createdAt;
  final String? updatedAt;
  final String? completedAt;

  const InterfaceTransitionModel({
    this.id,
    this.sessionId,
    this.sourceMode,
    this.targetMode,
    this.policy,
    this.phase,
    this.errorCode,
    this.errorDetail,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  factory InterfaceTransitionModel.fromJson(Map<String, dynamic> json) => InterfaceTransitionModel(
    id: json['id'] as String?,
    sessionId: json['sessionId'] as String?,
    sourceMode: json['sourceMode'] as String?,
    targetMode: json['targetMode'] as String?,
    policy: json['policy'] as String?,
    phase: json['phase'] as String?,
    errorCode: json['errorCode'] as String?,
    errorDetail: json['errorDetail'] as String?,
    createdAt: json['createdAt'] as String?,
    updatedAt: json['updatedAt'] as String?,
    completedAt: json['completedAt'] as String?,
  );

  @override
  List<Object?> get props => [
    id,
    sessionId,
    sourceMode,
    targetMode,
    policy,
    phase,
    errorCode,
    errorDetail,
    createdAt,
    updatedAt,
    completedAt,
  ];
}
