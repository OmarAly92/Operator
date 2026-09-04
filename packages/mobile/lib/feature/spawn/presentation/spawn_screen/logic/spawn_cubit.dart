import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';

part 'spawn_state.dart';

class SpawnCubit extends Cubit<SpawnState> {
  SpawnCubit(this._repository) : super(const SpawnInitialState());

  final SpawnRepository _repository;

  AgentCatalog? _catalog;
  int _revision = 0;

  String? projectId;
  String harness = '';
  String name = '';
  String prompt = '';

  List<RankedAgent> get agents => rankAgents(_catalog);

  void setProject(String? next) {
    projectId = next;
    _bump();
  }

  void setHarness(String next) {
    harness = next;
    _bump();
  }

  String _pickHarness(String current) =>
      agents.any((agent) => agent.id == current) ? current : (defaultAgent(agents) ?? '');

  Future<void> loadCatalog() async {
    emit(const CatalogLoadingState());
    final result = await _repository.getAgents();
    result.when(
      onSuccess: (response) {
        _catalog = response.data;
        harness = _pickHarness(harness);
        _bump();
      },
      onFailure: (failure) => emit(CatalogFailureState(failure)),
    );
  }

  Future<void> refreshCatalog() async {
    emit(const CatalogLoadingState());
    final result = await _repository.refreshAgents();
    result.when(
      onSuccess: (response) {
        _catalog = response.data;
        harness = _pickHarness(harness);
        _bump();
      },
      onFailure: (failure) => emit(CatalogFailureState(failure)),
    );
  }

  Future<void> submit() async {
    if (name.trim().isEmpty || prompt.trim().isEmpty) {
      emit(const SpawnValidationFailureState('Name and task are required.'));
      return;
    }
    final project = projectId;
    if (project == null || project.isEmpty) {
      emit(const SpawnValidationFailureState('Choose a project.'));
      return;
    }
    emit(const SpawnLoadingState());
    final result = await _repository.spawn(SpawnSessionParams(
      projectId: project,
      prompt: prompt.trim(),
      issueId: name.trim(),
      harness: harness,
    ));
    TelemetryRuntime.featureUsed('spawn', succeeded: result.isSuccess);
    result.when(
      onSuccess: (response) => emit(SpawnSuccessState(response.data ?? const SessionModel())),
      onFailure: (failure) => emit(SpawnFailureState(failure)),
    );
  }

  void _bump() => emit(CatalogReadyState(++_revision));
}
