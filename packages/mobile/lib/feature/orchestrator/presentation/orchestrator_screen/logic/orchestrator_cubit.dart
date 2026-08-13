import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/chat_preflight.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/orchestrator/data/model/params/launch_orchestrator_params.dart';
import 'package:operator_mobile/feature/orchestrator/data/repository/orchestrator_repository.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_state.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';

class OrchestratorCubit extends Cubit<OrchestratorLaunchState> {
  OrchestratorCubit(this._repository) : super(const OrchestratorInitialState());

  final OrchestratorRepository _repository;

  Future<void> launch(String projectId, {required bool clean, String mode = 'chat'}) async {
    emit(LaunchLoadingState(projectId, clean: clean));
    final result = await _repository.launch(
      LaunchOrchestratorParams(projectId: projectId, clean: clean, mode: mode),
    );
    result.when(
      onSuccess: (response) => emit(LaunchSuccessState(response.data ?? const OrchestratorModel())),
      onFailure: (failure) =>
          emit(LaunchFailureState(failure, chatUnavailable: isChatPreflightFailure(failure))),
    );
  }
}
