import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/terminal/logic/permission_modes.dart';

class PermissionModeState extends Equatable {
  const PermissionModeState({this.mode, this.supported = false, this.cycle = const [], this.pending, this.error});

  final String? mode;
  final bool supported;
  final List<String> cycle;
  final String? pending;
  final String? error;

  bool restarts(String target) => !cycle.contains(target);

  PermissionModeState copyWith({
    String? mode,
    bool? supported,
    List<String>? cycle,
    String? pending,
    bool clearPending = false,
    String? error,
    bool clearError = false,
  }) => PermissionModeState(
    mode: mode ?? this.mode,
    supported: supported ?? this.supported,
    cycle: cycle ?? this.cycle,
    pending: clearPending ? null : pending ?? this.pending,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [mode, supported, cycle, pending, error];
}

class PermissionModeCubit extends Cubit<PermissionModeState> {
  PermissionModeCubit(
    this._mux,
    this._control, {
    required this.sessionId,
    required SessionModel? Function() session,
    required Stream<Object?> sessionChanges,
  }) : _session = session,
       super(_fromSession(session())) {
    _observed = state.mode;
    _eventsSub = _mux.blockEvents.where((envelope) => envelope.sessionId == sessionId).listen(_onEvent);
    _sessionsSub = sessionChanges.listen((_) => _onSession());
  }

  final MuxClient _mux;
  final SessionControlRepository _control;
  final String sessionId;
  final SessionModel? Function() _session;

  String? _observed;
  bool _eventSeen = false;
  StreamSubscription<BlockEventEnvelope>? _eventsSub;
  StreamSubscription<Object?>? _sessionsSub;

  static PermissionModeState _fromSession(SessionModel? session) => PermissionModeState(
    mode: session?.permissionMode,
    supported: session?.permissionModeSupported ?? false,
    cycle: session?.permissionModeCycle ?? const [],
  );

  void _onEvent(BlockEventEnvelope envelope) {
    final event = BlockEventModel.fromJson(envelope.block);
    if (event.kind != kPermissionModeEventKind || (event.agentId ?? '').isNotEmpty) return;
    final mode = event.text;
    if (mode == null || !kPermissionModes.contains(mode)) return;
    _eventSeen = true;
    _observed = mode;
    if (state.pending != null) return;
    emit(state.copyWith(mode: mode, clearError: true));
  }

  void _onSession() {
    final fresh = _fromSession(_session());
    final mode = _eventSeen ? null : fresh.mode;
    if (mode != null) _observed = mode;
    emit(state.copyWith(
      mode: state.pending == null ? mode : null,
      supported: fresh.supported,
      cycle: fresh.cycle,
    ));
  }

  Future<bool> choose(String mode) async {
    if (state.pending != null) return false;
    if (mode == state.mode) return true;
    emit(state.copyWith(mode: mode, pending: mode, clearError: true));
    final result = await _control.sendCommand(
      sessionId,
      SessionCommandParams(command: 'permission-mode', mode: mode),
    );
    if (isClosed) return false;
    var applied = false;
    result.when(
      onSuccess: (response) {
        final confirmed = response.data?.permissionMode ?? mode;
        _observed = confirmed;
        applied = true;
        emit(state.copyWith(mode: confirmed, clearPending: true));
      },
      onFailure: (failure) => emit(PermissionModeState(
        mode: _observed,
        supported: state.supported,
        cycle: state.cycle,
        error: permissionModeRefusal(failure.apiStatus),
      )),
    );
    return applied;
  }

  @override
  Future<void> close() {
    unawaited(_eventsSub?.cancel());
    unawaited(_sessionsSub?.cancel());
    return super.close();
  }
}
