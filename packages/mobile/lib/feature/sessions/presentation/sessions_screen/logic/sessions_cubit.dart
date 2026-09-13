import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
  SessionsCubit(this._repository, this._muxClient) : super(const SessionsInitialState()) {
    _muxSub = _muxClient.boardChanges.listen((change) {
      _refreshProjects |= change.requiresFullRefresh;
      _syncFallback();
      _scheduleRefresh();
    });
    _statusSub = _muxClient.status.listen((status) {
      _syncFallback();
      if (status == MuxStatus.open) {
        _refreshProjects = true;
        _scheduleRefresh();
      }
    });
    _muxClient.connect();
    _muxClient.subscribeSessions();
    scheduleMicrotask(() => unawaited(_refreshBoard()));
    _syncFallback();
  }

  final SessionsRepository _repository;
  final MuxClient _muxClient;

  List<SessionModel> sessions = [];
  List<SessionModel> _allSessions = [];
  Failure? refreshFailure;
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
  StreamSubscription<BoardChange>? _muxSub;
  StreamSubscription<MuxStatus>? _statusSub;
  Timer? _refreshTimer;
  Future<void>? _refreshFuture;
  bool _refreshQueued = false;
  bool _refreshProjects = true;
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

  Future<void> _loadBoard() async {
    if (_revision == 0) emit(const GetSessionsLoadingState());
    final refreshProjects = _refreshProjects;
    _refreshProjects = false;
    final result = await (refreshProjects ? _repository.getBoard() : _repository.getSessions(projects));
    if (isClosed || _paused) return;
    result.when(
      onSuccess: (response) {
        _needsRetry = false;
        refreshFailure = null;
        final board = response.data ?? const BoardSnapshot();
        _allSessions = board.allSessions;
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
        _refreshProjects |= refreshProjects;
        refreshFailure = failure;
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
    _fallbackTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => unawaited(refresh()));
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
    _refreshProjects = true;
    _stopped = false;
    _syncFallback();
    return _refreshBoard();
  }

  Stream<SessionModel> watchSession(String sessionId) => Stream<SessionModel>.multi((controller) {
    var observed = false;
    void publish() {
      final session = _findSession(sessionId);
      if (session != null) {
        observed = true;
        controller.add(session);
      } else if (observed) {
        observed = false;
        controller.add(SessionModel(id: sessionId, activity: 'exited', isTerminated: true));
      }
    }
    final subscription = stream.listen((state) {
      if (state is GetSessionsSuccessState) publish();
    }, onDone: controller.close);
    controller.onCancel = subscription.cancel;
    publish();
  }).distinct();

  SessionModel? _findSession(String id) {
    for (final session in [..._allSessions, ...sessions]) {
      if (session.id == id) return session;
    }
    for (final session in orchestrators) {
      if (session.id == id) {
        return SessionModel(
          id: id, projectId: session.projectId, kind: 'orchestrator', status: session.status,
          activity: session.activity, isTerminated: session.isTerminal, updatedAt: session.updatedAt,
        );
      }
    }
    return null;
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
    return super.close();
  }
}
