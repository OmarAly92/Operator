import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

const String kSpeechListening = SpeechToText.listeningStatus;
const String kSpeechDone = SpeechToText.doneStatus;

class SpeechResult {
  const SpeechResult(this.transcript, {required this.isFinal});

  final String transcript;
  final bool isFinal;
}

class SpeechFailure {
  const SpeechFailure(this.errorMsg, {required this.permanent});

  final String errorMsg;
  final bool permanent;
}

abstract class SpeechRecognizer {
  bool get isAvailable;

  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(SpeechFailure failure)? onError,
  });

  Future<bool> hasPermission();

  Future<List<String>> localeIds();

  Future<String?> systemLocaleId();

  Future<void> listen({
    required void Function(SpeechResult result) onResult,
    String? localeId,
    required Duration pauseFor,
    required Duration listenFor,
  });

  Future<void> stop();

  Future<void> cancel();
}

class SpeechToTextRecognizer implements SpeechRecognizer {
  SpeechToTextRecognizer([SpeechToText? speech]) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  @override
  bool get isAvailable => _speech.isAvailable;

  @override
  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(SpeechFailure failure)? onError,
  }) => _speech.initialize(
    onStatus: onStatus,
    onError: (SpeechRecognitionError error) =>
        onError?.call(SpeechFailure(error.errorMsg, permanent: error.permanent)),
  );

  @override
  Future<bool> hasPermission() => _speech.hasPermission;

  @override
  Future<List<String>> localeIds() async =>
      (await _speech.locales()).map((locale) => locale.localeId).toList();

  @override
  Future<String?> systemLocaleId() async => (await _speech.systemLocale())?.localeId;

  @override
  Future<void> listen({
    required void Function(SpeechResult result) onResult,
    String? localeId,
    required Duration pauseFor,
    required Duration listenFor,
  }) => _speech.listen(
    onResult: (SpeechRecognitionResult result) =>
        onResult(SpeechResult(result.recognizedWords, isFinal: result.finalResult)),
    listenOptions: SpeechListenOptions(
      partialResults: true,
      autoPunctuation: true,
      cancelOnError: false,
      localeId: localeId,
      pauseFor: pauseFor,
      listenFor: listenFor,
    ),
  );

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
