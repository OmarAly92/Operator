import 'package:equatable/equatable.dart';

class LaunchOrchestratorParams extends Equatable {
  const LaunchOrchestratorParams({
    required this.projectId,
    required this.clean,
    required this.mode,
  });

  final String projectId;
  final bool clean;
  final String mode;

  Map<String, dynamic> toJson() => {'projectId': projectId, 'clean': clean, 'mode': mode};

  @override
  List<Object?> get props => [projectId, clean, mode];
}
