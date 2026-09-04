import 'package:equatable/equatable.dart';

class LaunchOrchestratorParams extends Equatable {
  const LaunchOrchestratorParams({
    required this.projectId,
    required this.clean,
  });

  final String projectId;
  final bool clean;

  Map<String, dynamic> toJson() => {'projectId': projectId, 'clean': clean};

  @override
  List<Object?> get props => [projectId, clean];
}
