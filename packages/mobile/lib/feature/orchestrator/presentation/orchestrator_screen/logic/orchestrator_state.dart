import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';

sealed class OrchestratorLaunchState extends Equatable {
  const OrchestratorLaunchState();

  @override
  List<Object?> get props => [];
}

class OrchestratorInitialState extends OrchestratorLaunchState {
  const OrchestratorInitialState();
}

class LaunchLoadingState extends OrchestratorLaunchState {
  const LaunchLoadingState(this.projectId);

  final String projectId;

  @override
  List<Object?> get props => [projectId];
}

class LaunchSuccessState extends OrchestratorLaunchState {
  const LaunchSuccessState(this.link);

  final OrchestratorModel link;

  @override
  List<Object?> get props => [link];
}

class LaunchFailureState extends OrchestratorLaunchState {
  const LaunchFailureState(this.failure, {required this.chatUnavailable});

  final Failure failure;
  final bool chatUnavailable;

  @override
  List<Object?> get props => [failure, chatUnavailable];
}
