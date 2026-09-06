import 'package:flutter/foundation.dart';

/// `transcribing` is unreachable for the on-device recogniser, which streams. It
/// exists so a later batch provider needs no UI change.
enum VoiceState { idle, starting, recording, transcribing, denied, unavailable }

/// `push` holds the key; `latched` is double-tap, hands-free until tapped again.
enum VoiceMode { push, latched }

class VoiceCallbacks {
  const VoiceCallbacks({
    required this.onReady,
    required this.onPartial,
    required this.onFinal,
    required this.onError,
  });

  /// The microphone is actually capturing. Anything said before this is lost, so
  /// this — not the return of [VoiceProvider.start] — is when the UI may invite
  /// the user to speak.
  final VoidCallback onReady;
  final void Function(String text) onPartial;
  final void Function(String text) onFinal;
  final void Function(String message) onError;
}

abstract class VoiceProvider {
  bool get available;

  String? get language;

  Future<bool> requestPermission();

  Future<void> start(VoiceCallbacks callbacks, {VoiceMode mode = VoiceMode.push});

  /// Finish and emit a final result.
  void stop();

  /// Discard — no final result.
  void abort();
}
