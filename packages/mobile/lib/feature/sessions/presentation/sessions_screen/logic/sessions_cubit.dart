import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';

part 'sessions_state.dart';

const String kAllProjects = 'all';

class SessionsCubit extends Cubit<SessionsState> {
  SessionsCubit(this._repository, this._muxClient) : super(const SessionsInitialState()) {
    _muxSub = _muxClient.sessionPatches.listen(_applyPatches);
    _muxClient.connect();
    _muxClient.subscribeSessions();
    scheduleMicrotask(() => unawaited(_tick()));
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => unawaited(_tick()));
  }

  final SessionsRepository _repository;
  final MuxClient _muxClient;

  List<SessionModel> sessions = [];
  List<OrchestratorModel> orchestrators = [];
  List<ProjectModel> projects = [];
  String activeProjectId = (CacheHelper.get(CacheKeys.activeProjectId) as String?) ?? kAllProjects;

  List<SessionModel> get visibleSessions => activeProjectId == kAllProjects
      ? sessions
      : sessions.where((s) => s.projectId == activeProjectId).toList();

  void setActiveProject(String id) {
    activeProjectId = id;
    CacheHelper.save(CacheKeys.activeProjectId, id);
    _emitSessions();
  }

  Timer? _pollTimer;
  StreamSubscription<List<SessionPatch>>? _muxSub;
  bool _stopped = false;
  int _revision = 0;
  bool _connectionOpen = false;
  bool _everConnected = false;

  void _emitSessions() => emit(GetSessionsSuccessState(++_revision));

  Future<void> _tick() async {
    if (_stopped) return;
    emit(const GetSessionsLoadingState());
    final result = await _repository.getBoard();
    result.when(
      onSuccess: (response) {
        final board = response.data ?? const BoardSnapshot();
        sessions = board.sessions;
        orchestrators = board.orchestrators;
        projects = board.projects;
        if (!_connectionOpen) {
          _connectionOpen = true;
          TelemetryRuntime.capture(MobileEvents.connected, {
            'trigger': _everConnected ? 'reconnect' : 'launch',
          });
          _everConnected = true;
        }
        _emitSessions();
      },
      onFailure: (failure) {
        _connectionOpen = false;
        emit(GetSessionsFailureState(failure));
        if (!shouldKeepPolling(failure.statusCode)) {
          _stopped = true;
          _pollTimer?.cancel();
        }
      },
    );
  }

  void resume() {
    if (!_stopped) return;
    _stopped = false;
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => unawaited(_tick()));
  }

  Future<void> refresh() {
    resume();
    return _tick();
  }

  void _applyPatches(List<SessionPatch> patches) {
    if (patches.isEmpty) return;
    final byId = {for (final patch in patches) patch.id: patch};
    sessions = sessions
        .map(
          (s) => byId[s.id] == null
              ? s
              : SessionModel(
                  id: s.id,
                  projectId: s.projectId,
                  kind: s.kind,
                  status: byId[s.id]!.status,
                  activity: byId[s.id]!.activity,
                  harness: s.harness,
                  branch: s.branch,
                  issueId: s.issueId,
                  displayName: s.displayName,
                  createdAt: s.createdAt,
                  updatedAt: byId[s.id]!.lastActivityAt,
                  previewUrl: s.previewUrl,
                  isTerminated: s.isTerminated,
                  prs: s.prs,
                ),
        )
        .toList();
    _emitSessions();
  }

  Future<void> kill(String id) async {
    final result = await _repository.kill(id);
    TelemetryRuntime.featureUsed('kill', succeeded: result.isSuccess);
    result.when(onSuccess: (_) => _tick(), onFailure: (failure) => emit(KillFailureState(failure)));
  }

  Future<void> restore(String id) async {
    final result = await _repository.restore(id);
    TelemetryRuntime.featureUsed('restore', succeeded: result.isSuccess);
    result.when(onSuccess: (_) => _tick(), onFailure: (failure) => emit(RestoreFailureState(failure)));
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    unawaited(_muxSub?.cancel());
    return super.close();
  }
}
