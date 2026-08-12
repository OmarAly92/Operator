import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';

part 'sessions_state.dart';

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

  Timer? _pollTimer;
  StreamSubscription<List<SessionPatch>>? _muxSub;
  bool _stopped = false;
  int _revision = 0;

  void _emitSessions() => emit(GetSessionsSuccessState(++_revision));

  Future<void> _tick() async {
    if (_stopped) return;
    emit(const GetSessionsLoadingState());
    final result = await _repository.getSessions();
    result.when(
      onSuccess: (response) {
        sessions = response.data ?? [];
        _emitSessions();
      },
      onFailure: (failure) {
        emit(GetSessionsFailureState(failure));
        if (!shouldKeepPolling(failure.statusCode)) {
          _stopped = true;
          _pollTimer?.cancel();
        }
      },
    );
  }

  Future<void> refresh() => _tick();

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
                  mode: s.mode,
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
    result.when(onSuccess: (_) => _tick(), onFailure: (failure) => emit(KillFailureState(failure)));
  }

  Future<void> restore(String id) async {
    final result = await _repository.restore(id);
    result.when(onSuccess: (_) => _tick(), onFailure: (failure) => emit(RestoreFailureState(failure)));
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    unawaited(_muxSub?.cancel());
    return super.close();
  }
}
