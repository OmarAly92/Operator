import 'package:equatable/equatable.dart';

class SpawnSessionParams extends Equatable {
  const SpawnSessionParams({
    required this.projectId,
    this.prompt,
    this.issueId,
    this.harness,
    this.workspaceMode,
  });

  final String projectId;
  final String? prompt;
  final String? issueId;
  final String? harness;
  final String? workspaceMode;

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    if (prompt != null && prompt!.isNotEmpty) 'prompt': prompt,
    if (issueId != null && issueId!.isNotEmpty) 'issueId': issueId,
    if (harness != null && harness!.isNotEmpty) 'harness': harness,
    if (workspaceMode != null) 'workspaceMode': workspaceMode,
    'kind': 'worker',
  };

  @override
  List<Object?> get props => [projectId, prompt, issueId, harness, workspaceMode];
}
