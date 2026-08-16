import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

part 'voice_input_state.dart';

class VoiceInputCubit extends Cubit<VoiceInputState> {
  factory VoiceInputCubit(
    VoiceProvider provider, {
    required void Function(String text) onTranscript,
    Duration tapThreshold = const Duration(milliseconds: 250),
    Duration doubleTapWindow = const Duration(milliseconds: 300),
    Duration restartDelay = const Duration(milliseconds: 120),
  }) => VoiceInputCubit._(
    provider,
    onTranscript: onTranscript,
    tapThreshold: tapThreshold,
    doubleTapWindow: doubleTapWindow,
    restartDelay: restartDelay,
  );

  VoiceInputCubit._(
    this._provider, {
    required this.onTranscript,
    required this._tapThreshold,
    required this._doubleTapWindow,
    required this._restartDelay,
  }) : super(const VoiceInputInitialState()) {
    if (!_provider.available) phase = VoiceState.unavailable;
  }

  final VoiceProvider _provider;
  final void Function(String text) onTranscript;
  final Duration _tapThreshold;
  final Duration _doubleTapWindow;
  final Duration _restartDelay;

  VoiceState phase = VoiceState.idle;
  VoiceMode mode = VoiceMode.push;
  String partial = '';
  String? error;

  DateTime _pressStart = DateTime.now();
  Timer? _tapWindow;
  Timer? _restart;
  bool _startedLatched = false;
  int _revision = 0;

  void _emit() {
    if (isClosed) return;
    emit(VoiceInputReadyState(++_revision));
  }

  void _setPhase(VoiceState next) {
    phase = next;
    _emit();
  }

  void pressIn() {
    if (mode == VoiceMode.latched && phase != VoiceState.idle) {
      _startedLatched = false;
      _finish();
      return;
    }

    if (_tapWindow != null) {
      _tapWindow!.cancel();
      _tapWindow = null;
      _startedLatched = true;
      _restart = Timer(_restartDelay, () => _begin(VoiceMode.latched));
      return;
    }

    _startedLatched = false;
    _pressStart = DateTime.now();
    _begin(VoiceMode.push);
  }

  void pressOut() {
    if (isClosed) return;
    if (_startedLatched) return;
    if (mode == VoiceMode.latched) return;

    if (DateTime.now().difference(_pressStart) < _tapThreshold) {
      _provider.abort();
      partial = '';
      mode = VoiceMode.push;
      _setPhase(VoiceState.idle);
      _tapWindow = Timer(_doubleTapWindow, () => _tapWindow = null);
      return;
    }

    _finish();
  }

  void pressCancel() {
    if (isClosed) return;
    if (_startedLatched) return;
    if (mode == VoiceMode.latched) return;
    if (phase != VoiceState.starting && phase != VoiceState.recording) return;

    _provider.abort();
    partial = '';
    mode = VoiceMode.push;
    _setPhase(VoiceState.idle);
  }

  void onAppBackgrounded() {
    if (phase != VoiceState.recording && phase != VoiceState.starting) return;
    _provider.abort();
    mode = VoiceMode.push;
    partial = '';
    _setPhase(VoiceState.idle);
  }

  void _begin(VoiceMode next) {
    if (phase == VoiceState.unavailable ||
        phase == VoiceState.starting ||
        phase == VoiceState.recording) {
      return;
    }
    mode = next;
    error = null;
    partial = '';
    _setPhase(VoiceState.starting);
    unawaited(_run(next));
  }

  Future<void> _run(VoiceMode next) async {
    final granted = await _provider.requestPermission();
    if (isClosed) return;
    if (!granted) {
      error = 'Microphone access is off. Enable it in Settings to dictate.';
      _setPhase(VoiceState.denied);
      return;
    }
    if (phase != VoiceState.starting) return;

    await _provider.start(
      VoiceCallbacks(
        onReady: () {
          if (isClosed || phase != VoiceState.starting) return;
          _setPhase(VoiceState.recording);
        },
        onPartial: (text) {
          if (isClosed) return;
          partial = text;
          _emit();
        },
        onFinal: (text) {
          mode = VoiceMode.push;
          if (isClosed) return;
          partial = '';
          _setPhase(VoiceState.idle);
          if (text.isNotEmpty) onTranscript(text);
        },
        onError: (message) {
          mode = VoiceMode.push;
          if (isClosed) return;
          partial = '';
          error = message;
          _setPhase(VoiceState.idle);
        },
      ),
      mode: next,
    );
  }

  void _finish() {
    if (phase == VoiceState.starting) {
      _provider.abort();
      partial = '';
      _setPhase(VoiceState.idle);
      return;
    }
    if (phase != VoiceState.recording) return;
    _provider.stop();
  }

  @override
  Future<void> close() {
    _tapWindow?.cancel();
    _restart?.cancel();
    mode = VoiceMode.push;
    _provider.abort();
    return super.close();
  }
}
