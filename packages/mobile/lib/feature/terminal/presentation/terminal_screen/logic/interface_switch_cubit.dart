import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_status_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/start_interface_transition_params.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/logic/interface_transition.dart';

part 'interface_switch_state.dart';

class InterfaceSwitchCubit extends Cubit<InterfaceSwitchState> {
  InterfaceSwitchCubit(
    this._repository,
    this.sessionId, {
    this.onSettled,
    Duration activePoll = const Duration(milliseconds: 300),
    Duration idlePoll = const Duration(seconds: 10),
  }) : _activePoll = activePoll,
       _idlePoll = idlePoll,
       super(const InterfaceSwitchInitialState()) {
    if (sessionId.isEmpty) return;
    unawaited(refresh());
    _schedule();
  }

  final TerminalRepository _repository;
  final String sessionId;
  final VoidCallback? onSettled;
  final Duration _activePoll;
  final Duration _idlePoll;

  InterfaceTransitionStatusModel? status;
  bool starting = false;
  bool cancelling = false;
  String? error;

  Timer? _timer;
  String _settledId = '';
  int _revision = 0;

  InterfaceTransitionModel? get transition => status?.transition;
  String? get phase => transition?.phase;
  bool get supported => status?.supported ?? false;
  String? get reason => status?.reason;
  bool get active => interfaceTransitionIsActive(phase);
  bool get cancellable => interfaceTransitionIsCancellable(phase);

  void _emit() => emit(InterfaceSwitchReadyState(++_revision));

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(active ? _activePoll : _idlePoll, () {
      unawaited(refresh().then((_) => _schedule()));
    });
  }

  Future<void> refresh() async {
    if (sessionId.isEmpty) return;
    final result = await _repository.getInterfaceTransition(sessionId);
    result.when(
      onSuccess: (response) {
        status = response.data;
        error = null;
        final settled = transition;
        if (settled != null &&
            !interfaceTransitionIsActive(settled.phase) &&
            _settledId != settled.id) {
          _settledId = settled.id ?? '';
          onSettled?.call();
        }
      },
      onFailure: (failure) => error = failure.message,
    );
    _emit();
  }

  Future<void> start(String targetMode, String policy) async {
    starting = true;
    error = null;
    _emit();
    final result = await _repository.startInterfaceTransition(
      sessionId,
      StartInterfaceTransitionParams(targetMode: targetMode, policy: policy),
    );
    result.when(
      onSuccess: (response) => status = InterfaceTransitionStatusModel(
        supported: status?.supported ?? true,
        targetMode: targetMode,
        reasonCode: status?.reasonCode,
        reason: status?.reason,
        transition: response.data,
      ),
      onFailure: (failure) => error = failure.message,
    );
    starting = false;
    _emit();
    _schedule();
  }

  Future<void> cancel() async {
    cancelling = true;
    error = null;
    _emit();
    final result = await _repository.cancelInterfaceTransition(sessionId);
    result.when(
      onSuccess: (_) {},
      onFailure: (failure) => error = failure.message,
    );
    cancelling = false;
    await refresh();
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
