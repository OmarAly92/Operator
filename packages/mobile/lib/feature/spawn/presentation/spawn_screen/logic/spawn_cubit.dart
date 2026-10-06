import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/claude_account_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/get_project_branches_params.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/data/model/project_branch_model.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/logic/spawn_option_values.dart';

part 'spawn_state.dart';

const String kDefaultSpawnPermissionMode = 'bypass-permissions';

class SpawnCubit extends Cubit<SpawnState> {
  SpawnCubit(this._repository) : super(const SpawnInitialState());

  final SpawnRepository _repository;

  AgentCatalog? _catalog;
  int _revision = 0;

  String? projectId;
  String? projectKind;
  String harness = '';
  String name = '';
  String prompt = '';
  bool useWorktree = false;
  String permissionMode = kDefaultSpawnPermissionMode;

  List<ClaudeAccountModel> claudeAccounts = const [];
  String claudeAccountId = 'default';
  bool _accountChosen = false;

  List<ProjectBranchModel> branches = const [];
  String currentBranch = '';
  bool branchesLoading = false;
  Failure? branchesError;
  String? selectedBranch;

  List<RankedAgent> get agents => rankAgents(_catalog);

  bool get _isSingleRepo => projectKind == 'single_repo';

  Future<void> setProject(String? next, {String? kind}) async {
    projectId = next;
    projectKind = kind;
    selectedBranch = null;
    branches = const [];
    currentBranch = '';
    branchesError = null;
    final project = next;
    branchesLoading = _isSingleRepo && project != null && project.isNotEmpty;
    _bump();
    if (branchesLoading) await _loadBranches(project!);
  }

  Future<void> _loadBranches(String project) async {
    final result = await _repository.getBranches(GetProjectBranchesParams(projectId: project));
    if (isClosed || projectId != project || !_isSingleRepo) return;
    result.when(
      onSuccess: (response) {
        branches = response.data?.branches ?? const [];
        currentBranch = response.data?.current ?? '';
        branchesError = null;
      },
      onFailure: (failure) => branchesError = failure,
    );
    branchesLoading = false;
    final current = state;
    if (current is SpawnInitialState || current is CatalogReadyState) {
      _bump();
    } else if (current is CatalogFailureState) {
      emit(CatalogFailureState(current.failure, ++_revision));
    }
  }

  void setBranch(String? next) {
    selectedBranch = next;
    _bump();
  }

  void setHarness(String next) {
    harness = next;
    claudeAccountId = ClaudeAccountModel.preferredId(claudeAccounts);
    _accountChosen = false;
    if (!SpawnOptionValues.permissionModesFor(next).contains(permissionMode)) {
      permissionMode = kDefaultSpawnPermissionMode;
    }
    _bump();
  }

  void setClaudeAccount(String next) {
    claudeAccountId = next;
    _accountChosen = true;
    _bump();
  }

  void setUseWorktree(bool value) {
    useWorktree = value;
    selectedBranch = null;
    _bump();
  }

  void setPermissionMode(String next) {
    permissionMode = next;
    _bump();
  }

  String _pickHarness(String current) =>
      agents.any((agent) => agent.id == current) ? current : (defaultAgent(agents) ?? '');

  Future<void> loadCatalog() async {
    emit(const CatalogLoadingState());
    final result = await _repository.getAgents();
    var catalogLoaded = false;
    result.when(
      onSuccess: (response) {
        _catalog = response.data;
        harness = _pickHarness(harness);
        catalogLoaded = true;
      },
      onFailure: (failure) => emit(CatalogFailureState(failure)),
    );
    if (catalogLoaded) {
      _bump();
      await _loadClaudeAccounts();
    }
  }

  Future<void> _loadClaudeAccounts() async {
    final result = await _repository.getClaudeAccounts();
    result.when(
      onSuccess: (response) {
        claudeAccounts = response.data ?? const [];
        if (!_accountChosen || !claudeAccounts.any((account) => account.id == claudeAccountId)) {
          claudeAccountId = ClaudeAccountModel.preferredId(claudeAccounts);
        }
        _bump();
      },
      onFailure: (_) {},
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
      workspaceMode: _isSingleRepo ? (useWorktree ? 'worktree' : 'in_place') : null,
      claudeAccountId: harness == 'claude-code' ? claudeAccountId : null,
      permissionMode: permissionMode,
      branch: _submitBranch,
    ));
    TelemetryRuntime.featureUsed('spawn', succeeded: result.isSuccess);
    result.when(
      onSuccess: (response) => emit(SpawnSuccessState(response.data ?? const SessionModel())),
      onFailure: (failure) => emit(SpawnFailureState(failure)),
    );
  }

  String? get _submitBranch {
    if (!_isSingleRepo) return null;
    if (useWorktree) return selectedBranch;
    return currentBranch.isEmpty ? null : currentBranch;
  }

  void _bump() => emit(CatalogReadyState(++_revision));
}
