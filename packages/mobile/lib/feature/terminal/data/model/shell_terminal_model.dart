import 'package:equatable/equatable.dart';

class ShellTerminalModel extends Equatable {
  final String? handleId;
  final String? projectId;
  final String? sessionId;
  final String? workingDir;
  final String? title;
  final String? createdAt;

  const ShellTerminalModel({
    this.handleId,
    this.projectId,
    this.sessionId,
    this.workingDir,
    this.title,
    this.createdAt,
  });

  factory ShellTerminalModel.fromJson(Map<String, dynamic> json) => ShellTerminalModel(
    handleId: json['handleId'] as String?,
    projectId: json['projectId'] as String?,
    sessionId: json['sessionId'] as String?,
    workingDir: json['workingDir'] as String?,
    title: json['title'] as String?,
    createdAt: json['createdAt'] as String?,
  );

  static List<ShellTerminalModel> listFromJson(Map<String, dynamic> json) =>
      (json['shellTerminals'] as List<dynamic>? ?? [])
          .map((shell) => ShellTerminalModel.fromJson(shell as Map<String, dynamic>))
          .toList();

  @override
  List<Object?> get props => [handleId, projectId, sessionId, workingDir, title, createdAt];
}
