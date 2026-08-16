import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:operator_mobile/feature/chat/voice/speech_recognizer.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

/// Long enough that the finger, not a silence timer, decides when a phrase ends —
/// the closest `speech_to_text` gets to RN's continuous mode.
const Duration kVoicePauseFor = Duration(seconds: 10);
const Duration kVoiceListenFor = Duration(minutes: 5);

/// Biases the recogniser toward words that show up constantly in agent prompts
/// and would otherwise come back mangled ("get" for "git", "MPM" for "npm").
const List<String> kCodingVocabulary = [
  'git',
  'npm',
  'repo',
  'commit',
  'rebase',
  'branch',
  'merge',
  'PR',
  'diff',
  'refactor',
  'TypeScript',
  'JavaScript',
  'Go',
  'React',
  'Expo',
  'JSON',
  'API',
  'CLI',
  'daemon',
  'worktree',
  'regex',
  'localhost',
  'stack trace',
  'lint',
  'typecheck',
];

/// Silence, a stray tap or a deliberate cancel is not a fault: settle normally so
/// anything already transcribed survives.
const Set<String> _silentErrors = {
  'error_no_match',
  'error_speech_timeout',
  'error_request_cancelled',
};

const Map<String, String> _errorMessages = {
  'error_permission':
      'Microphone or speech permission was denied. Enable it in Settings to dictate.',
  'error_speech_recognizer_request_not_authorized':
      'Microphone or speech permission was denied. Enable it in Settings to dictate.',
  'error_speech_recognizer_disabled':
      'Speech recognition is unavailable on this device.',
  'error_language_not_supported':
      'Speech recognition is not available for this language.',
  'error_language_unavailable':
      'Speech recognition is not available for this language.',
  'error_assets_not_installed':
      'This device has no speech recognition assets installed for this language.',
  'error_network':
      'Speech recognition needs a network connection and could not reach it.',
  'error_network_timeout':
      'Speech recognition needs a network connection and could not reach it.',
  'error_audio_error': 'Could not capture audio from the microphone.',
  'error_listen_failed': 'Could not capture audio from the microphone.',
  'error_speech_recognizer_connection_interrupted':
      'Recording was interrupted.',
  'error_speech_recognizer_connection_invalidated':
      'Recording was interrupted.',
  'error_busy': 'The speech recogniser is busy. Try again in a moment.',
  'error_speech_recognizer_already_active':
      'The speech recogniser is busy. Try again in a moment.',
  'error_server':
      'The speech recognition service could not complete the request.',
  'error_server_disconnected':
      'The speech recognition service could not complete the request.',
};

class _VoiceSession {
  _VoiceSession(this.callbacks);

  final VoiceCallbacks callbacks;
  final List<String> finalized = [];
  String partial = '';
  Timer? settleTimer;

  String get transcript =>
      [...finalized, partial].where((part) => part.isNotEmpty).join(' ').trim();
}

/// Within a segment, successive partials restate the whole segment: they grow and
/// revise words in place, so they keep sharing an opening. A partial that shares
/// none belongs to a new segment, so the previous one is finished and must be
/// banked. This is the last-resort boundary detector — `speech_to_text` does not
/// surface Android's `onBeginningOfSpeech`, which RN used as the authoritative one.
bool _isSameSegment(String previous, String next) {
  if (previous.trim().isEmpty) return true;
  final before = previous.trim().toLowerCase();
  final after = next.trim().toLowerCase();
  if (after.startsWith(before) || before.startsWith(after)) return true;
  String firstWord(String value) {
    final space = value.indexOf(' ');
    return space == -1 ? value : value.substring(0, space);
  }

  return firstWord(before) == firstWord(after) && after.length >= before.length;
}

class DeviceVoiceProvider implements VoiceProvider {
  factory DeviceVoiceProvider(
    SpeechRecognizer recognizer, {
    Duration stopGrace = const Duration(seconds: 4),
    TargetPlatform? platform,
  }) => DeviceVoiceProvider._(
    recognizer,
    stopGrace: stopGrace,
    platform: platform ?? defaultTargetPlatform,
  );

  DeviceVoiceProvider._(
    this._recognizer, {
    required this._stopGrace,
    required this._platform,
  });

  final SpeechRecognizer _recognizer;
  final Duration _stopGrace;
  final TargetPlatform _platform;

  _VoiceSession? _session;
  bool _granted = false;
  String? _language;

  @override
  bool get available => _recognizer.isAvailable;

  @override
  String? get language => _language;

  /// Sticky once granted: permission can only be revoked from system settings,
  /// which restarts the app, and the round-trip sits directly in front of the
  /// microphone starting.
  @override
  Future<bool> requestPermission() async {
    if (_granted) return true;
    try {
      _granted = await _recognizer.initialize(
        onStatus: _onStatus,
        onError: _onError,
      );
      return _granted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start(
    VoiceCallbacks callbacks, {
    VoiceMode mode = VoiceMode.push,
  }) async {
    if (_session != null) abort();
    final session = _VoiceSession(callbacks);
    _session = session;

    _language ??= await _resolveLanguage();
    try {
      await _recognizer.listen(
        onResult: (result) => _onResult(session, result),
        localeId: _language,
        pauseFor: kVoicePauseFor,
        listenFor: kVoiceListenFor,
        longForm: mode == VoiceMode.latched,
      );
    } catch (error) {
      _fail(
        error is StateError ? error.message : 'Could not start the microphone.',
      );
    }
  }

  @override
  void stop() {
    final session = _session;
    unawaited(_recognizer.stop());
    if (session == null) return;
    session.settleTimer = Timer(_stopGrace, () {
      if (identical(_session, session)) _settle();
    });
  }

  @override
  void abort() {
    _close();
    unawaited(_recognizer.cancel());
  }

  Future<String> _resolveLanguage() async {
    const fallback = 'en-US';
    String normalize(String value) => value.replaceAll('_', '-').toLowerCase();
    try {
      final device = normalize(await _recognizer.systemLocaleId() ?? fallback);
      final supported = await _recognizer.localeIds();
      for (final locale in supported) {
        if (normalize(locale) == device) return locale;
      }
      final language = device.split('-').first;
      for (final locale in supported) {
        if (normalize(locale).split('-').first == language) return locale;
      }
    } catch (_) {
      return fallback;
    }
    return fallback;
  }

  void _onResult(_VoiceSession session, SpeechResult result) {
    if (!identical(_session, session)) return;
    final transcript = result.transcript;

    // iOS runs ONE recognition task over the whole recording and every result —
    // `isFinal` ones included — restates everything said so far, so banking a
    // final would append the phrase twice. The one case that does bank is a task
    // restart, whose first result shares no opening with what came before.
    if (_platform == TargetPlatform.iOS) {
      if (!_isSameSegment(session.partial, transcript) &&
          session.partial.trim().isNotEmpty) {
        session.finalized.add(session.partial.trim());
      }
      session.partial = transcript;
      session.callbacks.onPartial(session.transcript);
      return;
    }

    if (result.isFinal) {
      if (transcript.trim().isNotEmpty) {
        session.finalized.add(transcript.trim());
      }
      session.partial = '';
    } else {
      if (!_isSameSegment(session.partial, transcript) &&
          session.partial.trim().isNotEmpty) {
        session.finalized.add(session.partial.trim());
      }
      session.partial = transcript;
    }
    session.callbacks.onPartial(session.transcript);
  }

  void _onStatus(String status) {
    final session = _session;
    if (session == null) return;
    if (status == kSpeechListening) {
      session.callbacks.onReady();
      return;
    }
    if (status == kSpeechDone) _settle();
  }

  void _onError(SpeechFailure failure) {
    if (_session == null) return;
    if (_silentErrors.contains(failure.errorMsg)) {
      _settle();
      return;
    }
    _fail(_errorMessages[failure.errorMsg] ?? 'Speech recognition failed.');
  }

  /// An empty string is a legitimate result meaning "nothing was said", which the
  /// caller treats as a no-op rather than an error.
  void _settle() {
    final session = _session;
    if (session == null) return;
    final text = session.transcript;
    _close();
    session.callbacks.onFinal(text);
  }

  void _fail(String message) {
    final session = _session;
    if (session == null) return;
    _close();
    session.callbacks.onError(message);
  }

  void _close() {
    _session?.settleTimer?.cancel();
    _session = null;
  }
}
