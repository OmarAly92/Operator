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
    bool clearMode = false,
    String? pending,
    bool clearPending = false,
    String? error,
    bool clearError = false,
  }) => PermissionModeState(
    mode: clearMode ? null : mode ?? this.mode,
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
    _muxStatus = _mux.currentStatus;
    _statusSub = _mux.status.listen(_onStatus);
  }

  final MuxClient _mux;
  final SessionControlRepository _control;
  final String sessionId;
  final SessionModel? Function() _session;

  String? _observed;
  String? _held;
  MuxStatus? _muxStatus;
  StreamSubscription<BlockEventEnvelope>? _eventsSub;
  StreamSubscription<Object?>? _sessionsSub;
  StreamSubscription<MuxStatus>? _statusSub;

  static PermissionModeState _fromSession(SessionModel? session) => PermissionModeState(
    mode: _known(session?.permissionMode),
    supported: session?.permissionModeSupported ?? false,
    cycle: session?.permissionModeCycle ?? const [],
  );

  void _onEvent(BlockEventEnvelope envelope) {
    final event = BlockEventModel.fromJson(envelope.block);
    if (event.kind != kPermissionModeEventKind || (event.agentId ?? '').isNotEmpty) return;
    final mode = _known(event.text);
    if (mode == null && (event.text ?? '').isNotEmpty) return;
    _held = mode;
    _observed = mode;
    if (state.pending != null) return;
    emit(state.copyWith(mode: mode, clearMode: mode == null, clearError: true));
  }

  static String? _known(String? mode) => kPermissionModes.contains(mode) ? mode : null;

  void _onStatus(MuxStatus status) {
    final reopened = status == MuxStatus.open && _muxStatus != MuxStatus.open;
    _muxStatus = status;
    if (reopened) _held = null;
  }

  void _onSession() {
    final session = _session();
    if (session == null) return;
    final fresh = _fromSession(session);
    final reported = fresh.mode;
    final follow = _held == null;
    if (!follow && reported == _held) _held = null;
    if (follow) _observed = reported;
    final apply = follow && state.pending == null;
    emit(state.copyWith(
      mode: apply ? reported : null,
      clearMode: apply && reported == null,
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
        _held = confirmed;
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
    unawaited(_statusSub?.cancel());
    return super.close();
  }
}
