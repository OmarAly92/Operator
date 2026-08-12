import 'package:equatable/equatable.dart';

class SessionPatch extends Equatable {
  const SessionPatch({
    required this.id,
    required this.status,
    required this.activity,
    required this.attentionLevel,
    required this.lastActivityAt,
  });

  final String id;
  final String status;
  final String? activity;
  final String attentionLevel;
  final String lastActivityAt;

  factory SessionPatch.fromJson(Map<String, dynamic> json) => SessionPatch(
    id: json['id'] as String,
    status: json['status'] as String,
    activity: json['activity'] as String?,
    attentionLevel: json['attentionLevel'] as String,
    lastActivityAt: json['lastActivityAt'] as String,
  );

  @override
  List<Object?> get props => [id, status, activity, attentionLevel, lastActivityAt];
}
