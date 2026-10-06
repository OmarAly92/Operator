import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';

class BackgroundTaskModel extends Equatable {
  final String? taskId;
  final String? kind;
  final String? status;
  final String? toolUseId;
  final String? description;
  final String? command;
  final String? summary;
  final int? exitCode;
  final int? durationMs;
  final String? outputFile;
  final String? startedAt;
  final String? endedAt;
  final String? agentId;
  final bool? canStop;
  final int? updatedSeq;

  const BackgroundTaskModel({
    this.taskId,
    this.kind,
    this.status,
    this.toolUseId,
    this.description,
    this.command,
    this.summary,
    this.exitCode,
    this.durationMs,
    this.outputFile,
    this.startedAt,
    this.endedAt,
    this.agentId,
    this.canStop,
    this.updatedSeq,
  });

  factory BackgroundTaskModel.fromJson(Map<String, dynamic> json) => BackgroundTaskModel(
    taskId: json['taskId'] as String?,
    kind: json['kind'] as String?,
    status: json['status'] as String?,
    toolUseId: json['toolUseId'] as String?,
    description: json['description'] as String?,
    command: json['command'] as String?,
    summary: json['summary'] as String?,
    exitCode: (json['exitCode'] as num?)?.toInt(),
    durationMs: (json['durationMs'] as num?)?.toInt(),
    outputFile: json['outputFile'] as String?,
    startedAt: json['startedAt'] as String?,
    endedAt: json['endedAt'] as String?,
    agentId: json['agentId'] as String?,
    canStop: json['canStop'] as bool?,
    updatedSeq: (json['updatedSeq'] as num?)?.toInt(),
  );

  static List<BackgroundTaskModel> listFromJson(Map<String, dynamic> json) =>
      (json['tasks'] as List<dynamic>? ?? [])
          .map((task) => BackgroundTaskModel.fromJson(task as Map<String, dynamic>))
          .toList();

  static BackgroundTaskModel? fromEvent(BlockEventModel event) {
    if (event.kind != 'task_update') return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(event.detail ?? '');
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final detail = BackgroundTaskModel.fromJson(decoded);
    final taskId = (detail.taskId ?? '').isNotEmpty ? detail.taskId : event.sourceId;
    if (taskId == null || taskId.isEmpty) return null;
    final agentId = event.agentId;
    return detail.copyWith(
      taskId: taskId,
      toolUseId: detail.toolUseId ?? event.toolUseId,
      agentId: agentId == null || agentId.isEmpty ? null : agentId,
      updatedSeq: event.seq,
    );
  }

  BackgroundTaskModel copyWith({
    String? taskId,
    String? toolUseId,
    String? agentId,
    int? updatedSeq,
  }) => BackgroundTaskModel(
    taskId: taskId ?? this.taskId,
    kind: kind,
    status: status,
    toolUseId: toolUseId ?? this.toolUseId,
    description: description,
    command: command,
    summary: summary,
    exitCode: exitCode,
    durationMs: durationMs,
    outputFile: outputFile,
    startedAt: startedAt,
    endedAt: endedAt,
    agentId: agentId ?? this.agentId,
    canStop: canStop,
    updatedSeq: updatedSeq ?? this.updatedSeq,
  );

  @override
  List<Object?> get props => [
    taskId,
    kind,
    status,
    toolUseId,
    description,
    command,
    summary,
    exitCode,
    durationMs,
    outputFile,
    startedAt,
    endedAt,
    agentId,
    canStop,
    updatedSeq,
  ];
}
