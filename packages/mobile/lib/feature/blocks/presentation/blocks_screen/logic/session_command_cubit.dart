import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/pending_interaction_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_answer_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_decision_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/command_confirmation.dart';

part 'session_command_state.dart';

class SessionCommandCubit extends Cubit<SessionCommandState> {
  SessionCommandCubit(
    this._mux,
    this._repo, {
    required this.sessionId,
    String? initialActivity,
    this.budget = kCommandConfirmationBudget,
  }) : super(const SessionCommandState()) {
    // Seeded before the first patch arrives: the mux only pushes a session
    // patch when something CHANGES, so a cubit built while the session sits
    // idle would otherwise never learn its activity and refuse every command.
    _activity = initialActivity;
    _patchesSub = _mux.sessionPatches.listen(_onPatches);
    _eventsSub = _mux.blockEvents.where((event) => event.sessionId == sessionId).listen(_onLive);
    unawaited(_reconcileInteractions());
  }

  final MuxClient _mux;
  final SessionControlRepository _repo;
  final String sessionId;
  final Duration budget;

  final Map<String, Timer> _timers = {};
  final Set<String> _pendingConfirm = {};
  String? _activity;

  StreamSubscription<List<SessionPatch>>? _patchesSub;
  StreamSubscription<BlockEventEnvelope>? _eventsSub;

  /// The dialog the daemon says is pending, learned from the reconnect
  /// reconciliation endpoint rather than from a block event. A phone that was
  /// backgrounded when the dialog appeared never saw that event.
  PendingInteractionModel? pendingInteraction;

  String? get activity => _activity;

  void _onPatches(List<SessionPatch> patches) {
    for (final patch in patches) {
      if (patch.id != sessionId) continue;
      onActivity(patch.activity);
      return;
    }
  }

  void _onLive(BlockEventEnvelope envelope) {
    final event = BlockEventModel.fromJson(envelope.block);
    if ((event.interactionId ?? '').isNotEmpty) pendingInteraction = null;
    onEvent(event);
  }

  /// Backfills the dialog a client that reconnected (or opened the session
  /// late) has no block event for. A failure is silent: the block-event stream
  /// remains the primary path and a refusal here must not disable the row.
  Future<void> _reconcileInteractions() async {
    final result = await _repo.getInteractions(sessionId);
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        final pending = response.data;
        if (pending == null || pending.isEmpty) return;
        pendingInteraction = pending.first;
        _emitPhases(Map<String, CommandPhase>.of(state.phases));
      },
      onFailure: (_) {},
    );
  }

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

  /// A refusal must never leave a command at sent; failures reset to idle.
  Future<void> run(String command, {String? model}) async {
    _setPhase(command, CommandPhase.sending);
    final result = await _repo.sendCommand(sessionId, SessionCommandParams(command: command, model: model));
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        final offered = response.data?.models;
        if (_pendingConfirm.remove(command)) {
          _setPhase(command, CommandPhase.confirmed, models: offered);
          return;
        }
        _setPhase(command, CommandPhase.sent, models: offered);
        if (command != 'model') _startTimer(command);
      },
      onFailure: (failure) {
        List<String>? offered;
        if (command == 'model' && failure is ServerFailure && failure.validationErrors?['models'] is List) {
          offered = (failure.validationErrors!['models'] as List).cast<String>();
        }
        _pendingConfirm.remove(command);
        _setPhase(command, CommandPhase.idle, models: offered);
      },
    );
  }

  void onEvent(BlockEventModel event) {
    final next = Map<String, CommandPhase>.of(state.phases);
    var changed = false;
    for (final key in state.phases.keys.toList()) {
      if (key != 'compact' && key != 'model') continue;
      final phase = next[key];
      if (phase == CommandPhase.sending) {
        if (confirmsCommand(key, event)) _pendingConfirm.add(key);
        continue;
      }
      if (phase != CommandPhase.sent) continue;
      if (!confirmsCommand(key, event)) continue;
      _timers.remove(key)?.cancel();
      next[key] = CommandPhase.confirmed;
      changed = true;
    }
    if (changed) _emitPhases(next);
  }

  void onActivity(String? activity) {
    _activity = activity;
    final phase = state.phases['stop'];
    if (phase == CommandPhase.sending) {
      if (confirmsStop(activity)) _pendingConfirm.add('stop');
      return;
    }
    if (phase == CommandPhase.sent && confirmsStop(activity)) {
      _timers.remove('stop')?.cancel();
      _setPhase('stop', CommandPhase.confirmed);
    }
  }

  Future<void> decide(String requestId, String behavior) async {
    _setPhase('decision', CommandPhase.sending);
    final result = await _repo.decide(sessionId, SessionDecisionParams(requestId: requestId, behavior: behavior));
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        final phase = response.data?.state == 'unconfirmed' ? CommandPhase.unconfirmed : CommandPhase.sent;
        _setPhase('decision', phase);
      },
      onFailure: (_) => _setPhase('decision', CommandPhase.idle),
    );
  }

  Future<void> answer(String requestId, List<List<String>> selections) async {
    _setPhase('answer', CommandPhase.sending);
    final result = await _repo.answer(sessionId, SessionAnswerParams(requestId: requestId, selections: selections));
    if (isClosed) return;
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
      if (isClosed) return;
      if (state.phases[command] == CommandPhase.sent) _setPhase(command, CommandPhase.unconfirmed);
    });
  }

  void _setPhase(String command, CommandPhase phase, {List<String>? models}) {
    final next = Map<String, CommandPhase>.of(state.phases)..[command] = phase;
    _emitPhases(next, models: models);
  }

  void _emitPhases(Map<String, CommandPhase> phases, {List<String>? models}) {
    if (isClosed) return;
    emit(state.copyWith(phases: phases, models: models));
  }

  @override
  Future<void> close() {
    unawaited(_patchesSub?.cancel());
    unawaited(_eventsSub?.cancel());
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    return super.close();
  }
}
