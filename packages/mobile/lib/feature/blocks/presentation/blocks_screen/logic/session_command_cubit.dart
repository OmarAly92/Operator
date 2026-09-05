import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_answer_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_decision_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/command_confirmation.dart';

part 'session_command_state.dart';

class SessionCommandCubit extends Cubit<SessionCommandState> {
  SessionCommandCubit(this._repo, {required this.sessionId, this.budget = kCommandConfirmationBudget})
    : super(const SessionCommandState());

  final SessionControlRepository _repo;
  final String sessionId;
  final Duration budget;

  final Map<String, Timer> _timers = {};
  String? _activity;

  Map<String, CommandPhase> get phases => state.phases;
  List<String> get models => state.models;

  bool enabled(String command) {
    if (_activity == 'blocked') return false;
    switch (command) {
      case 'stop':
        return _activity == 'active';
      case 'compact':
      case 'model':
        return _activity == 'idle';
      default:
        return false;
    }
  }

  String? disabledReason(String command) {
    if (enabled(command)) return null;
    if (_activity == 'blocked') return 'Answer the permission request first';
    return command == 'stop' ? 'The agent is idle' : 'The agent is working';
  }

  /// A refusal must never leave a command at sent — only run() promotes to sent.
  Future<void> run(String command, {String? model}) async {
    _setPhase(command, CommandPhase.sending);
    final result = await _repo.sendCommand(sessionId, SessionCommandParams(command: command, model: model));
    result.when(
      onSuccess: (response) {
        final offered = response.data?.models;
        _setPhase(command, CommandPhase.sent, models: offered);
        if (command != 'model') _startTimer(command);
      },
      onFailure: (failure) {
        List<String>? offered;
        if (command == 'model' && failure is ServerFailure && failure.validationErrors?['models'] is List) {
          offered = (failure.validationErrors!['models'] as List).cast<String>();
        }
        _setPhase(command, CommandPhase.idle, models: offered);
      },
    );
  }

  void onEvent(BlockEventModel event) {
    final next = Map<String, CommandPhase>.of(state.phases);
    var changed = false;
    for (final key in state.phases.keys.toList()) {
      if (next[key] != CommandPhase.sent) continue;
      if (key != 'compact' && key != 'model') continue;
      if (!confirmsCommand(key, event)) continue;
      _timers.remove(key)?.cancel();
      next[key] = CommandPhase.confirmed;
      changed = true;
    }
    if (changed) emit(state.copyWith(phases: next));
  }

  void onActivity(String? activity) {
    _activity = activity;
    if (state.phases['stop'] == CommandPhase.sent && confirmsStop(activity)) {
      _timers.remove('stop')?.cancel();
      _setPhase('stop', CommandPhase.confirmed);
    }
  }

  Future<void> decide(String requestId, String behavior) async {
    _setPhase('decision', CommandPhase.sending);
    final result = await _repo.decide(sessionId, SessionDecisionParams(requestId: requestId, behavior: behavior));
    result.when(
      onSuccess: (response) {
        final phase = response.data?.state == 'unconfirmed' ? CommandPhase.unconfirmed : CommandPhase.sent;
        _setPhase('decision', phase);
      },
      onFailure: (_) => _setPhase('decision', CommandPhase.idle),
    );
  }

  Future<void> answer(String requestId, List<List<int>> selections) async {
    _setPhase('answer', CommandPhase.sending);
    final result = await _repo.answer(sessionId, SessionAnswerParams(requestId: requestId, selections: selections));
    result.when(
      onSuccess: (response) {
        final phase = response.data?.state == 'unconfirmed' ? CommandPhase.unconfirmed : CommandPhase.sent;
        _setPhase('answer', phase);
      },
      onFailure: (_) => _setPhase('answer', CommandPhase.idle),
    );
  }

  void _startTimer(String command) {
    _timers.remove(command)?.cancel();
    _timers[command] = Timer(budget, () {
      if (state.phases[command] == CommandPhase.sent) _setPhase(command, CommandPhase.unconfirmed);
    });
  }

  void _setPhase(String command, CommandPhase phase, {List<String>? models}) {
    final next = Map<String, CommandPhase>.of(state.phases)..[command] = phase;
    emit(state.copyWith(phases: next, models: models));
  }

  @override
  Future<void> close() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    return super.close();
  }
}
