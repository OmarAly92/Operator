import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/chat_preflight.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/operator_settings_model.dart';
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
  String mode = 'chat';
  String name = '';
  String prompt = '';
  List<String> chatHarnesses = const [];

  List<RankedAgent> get agents {
    final ranked = rankAgents(_catalog);
    if (mode != 'chat') return ranked;
    return ranked.where((agent) => chatHarnesses.contains(agent.id)).toList();
  }

  void setProject(String? next) => projectId = next;

  void setHarness(String next) => harness = next;

  String _pickHarness(String current) =>
      agents.any((agent) => agent.id == current) ? current : (defaultAgent(agents) ?? '');

  void setMode(String next) {
    mode = next;
    harness = _pickHarness(harness);
    _bump();
  }

  Future<void> loadCatalog() async {
    emit(const CatalogLoadingState());
    final results = await Future.wait([_repository.getAgents(), _repository.getSettings()]);
    final agentsResult = results.first as Result<GlobalResponse<AgentCatalog>, Failure>;
    final settingsResult = results.last as Result<GlobalResponse<OperatorSettingsModel>, Failure>;

    Failure? failure;
    agentsResult.when(
      onSuccess: (response) => _catalog = response.data,
      onFailure: (error) => failure = error,
    );
    settingsResult.when(
      onSuccess: (response) => chatHarnesses = response.data?.chatHarnesses ?? const [],
      onFailure: (error) => failure ??= error,
    );

    if (failure != null) {
      emit(CatalogFailureState(failure!));
      return;
    }
    harness = _pickHarness(harness);
    _bump();
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
      mode: mode,
      prompt: prompt.trim(),
      issueId: name.trim(),
      harness: harness,
    ));
    result.when(
      onSuccess: (response) => emit(SpawnSuccessState(response.data ?? const SessionModel())),
      onFailure: (failure) =>
          emit(SpawnFailureState(failure, chatUnavailable: isChatPreflightFailure(failure))),
    );
  }

  void _bump() => emit(CatalogReadyState(++_revision));
}
