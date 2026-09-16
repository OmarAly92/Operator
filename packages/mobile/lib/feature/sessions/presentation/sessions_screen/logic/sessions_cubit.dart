import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
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
  SessionsCubit(this._repository, this._muxClient, this._configSource) : super(const SessionsInitialState()) {
    _muxSub = _muxClient.boardChanges.listen((_) {
      _syncFallback();
      _scheduleRefresh();
    });
    _statusSub = _muxClient.status.listen((status) {
      _syncFallback();
      if (status == MuxStatus.open) _scheduleRefresh();
    });
    _configSub = _configSource.changes.listen(_onConfigChanged);
    _muxClient.connect();
    _muxClient.subscribeSessions();
    scheduleMicrotask(() => unawaited(_refreshBoard()));
    _syncFallback();
  }

  final SessionsRepository _repository;
  final MuxClient _muxClient;
  final ServerConfigSource _configSource;

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

  Timer? _fallbackTimer;
  StreamSubscription<void>? _muxSub;
  StreamSubscription<MuxStatus>? _statusSub;
  StreamSubscription<ServerConfig?>? _configSub;
  int _boardEpoch = 0;
  Timer? _refreshTimer;
  Future<void>? _refreshFuture;
  bool _refreshQueued = false;
  bool _paused = false;
  bool _needsRetry = false;
  bool _stopped = false;
  int _revision = 0;
  bool _connectionOpen = false;
  bool _everConnected = false;

  void _emitSessions() => emit(GetSessionsSuccessState(++_revision));

  Future<void> _refreshBoard() async {
    if (_stopped || _paused || isClosed) return;
    if (_refreshFuture != null) {
      _refreshQueued = true;
      return _refreshFuture;
    }
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshFuture = _loadBoard();
    try {
      await _refreshFuture;
    } finally {
      _refreshFuture = null;
      if (_refreshQueued) {
        _refreshQueued = false;
        _scheduleRefresh();
      }
    }
  }

  void _onConfigChanged(ServerConfig? next) {
    if (isClosed) return;
    _boardEpoch++;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshQueued = false;
    sessions = [];
    orchestrators = [];
    projects = [];
    _needsRetry = false;
    _connectionOpen = false;
    _revision = 0;
    emit(const SessionsInitialState());
    if (next == null) {
      _stopped = true;
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
      return;
    }
    unawaited(refresh());
  }

  Future<void> _loadBoard() async {
    final epoch = _boardEpoch;
    if (_revision == 0) emit(const GetSessionsLoadingState());
    final result = await _repository.getBoard();
    if (isClosed || _paused || epoch != _boardEpoch) return;
    result.when(
      onSuccess: (response) {
        _needsRetry = false;
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
        _needsRetry = true;
        _connectionOpen = false;
        emit(GetSessionsFailureState(failure));
        if (!shouldKeepPolling(failure.statusCode)) {
          _stopped = true;
          _fallbackTimer?.cancel();
        }
      },
    );
    _syncFallback();
  }

  void _scheduleRefresh() {
    if (_stopped || _paused || isClosed) return;
    _refreshTimer ??= Timer(const Duration(milliseconds: 200), () {
      _refreshTimer = null;
      unawaited(_refreshBoard());
    });
  }

  void _syncFallback() {
    if (_stopped || _paused || isClosed || (_muxClient.boardStreamReady && !_needsRetry)) {
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
      return;
    }
    _fallbackTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_refreshBoard()));
  }

  void pauseUpdates() {
    _paused = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _syncFallback();
  }

  void resumeUpdates() {
    if (!_paused) return;
    _paused = false;
    unawaited(refresh());
  }

  Future<void> refresh() {
    _stopped = false;
    _syncFallback();
    return _refreshBoard();
  }

  Future<void> kill(String id) async {
    final result = await _repository.kill(id);
    TelemetryRuntime.featureUsed('kill', succeeded: result.isSuccess);
    result.when(onSuccess: (_) => _refreshBoard(), onFailure: (failure) => emit(KillFailureState(failure)));
  }

  Future<void> restore(String id) async {
    final result = await _repository.restore(id);
    TelemetryRuntime.featureUsed('restore', succeeded: result.isSuccess);
    result.when(onSuccess: (_) => _refreshBoard(), onFailure: (failure) => emit(RestoreFailureState(failure)));
  }

  @override
  Future<void> close() {
    _stopped = true;
    _fallbackTimer?.cancel();
    _refreshTimer?.cancel();
    unawaited(_muxSub?.cancel());
    unawaited(_statusSub?.cancel());
    unawaited(_configSub?.cancel());
    return super.close();
  }
}
