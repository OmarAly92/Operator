import 'package:equatable/equatable.dart';

class SpawnSessionParams extends Equatable {
  const SpawnSessionParams({
    required this.projectId,
    required this.mode,
    this.prompt,
    this.issueId,
    this.harness,
  });

  final String projectId;
  final String mode;
  final String? prompt;
  final String? issueId;
  final String? harness;

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    if (prompt != null && prompt!.isNotEmpty) 'prompt': prompt,
    if (issueId != null && issueId!.isNotEmpty) 'issueId': issueId,
    if (harness != null && harness!.isNotEmpty) 'harness': harness,
    'mode': mode,
    'kind': 'worker',
  };

  @override
  List<Object?> get props => [projectId, mode, prompt, issueId, harness];
}
