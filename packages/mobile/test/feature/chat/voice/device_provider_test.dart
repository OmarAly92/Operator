import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/voice/device_provider.dart';
import 'package:operator_mobile/feature/chat/voice/speech_recognizer.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

class FakeRecognizer implements SpeechRecognizer {
  FakeRecognizer({this.availableValue = true, this.permission = true});

  bool availableValue;
  bool permission;
  int permissionChecks = 0;
  int listenCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  bool throwOnListen = false;
  List<String> supportedLocales = ['en-US', 'en-GB', 'en-IN'];
  String? systemLocale = 'en-IN';
  ({Duration pauseFor, Duration listenFor, String? localeId})? lastOptions;

  void Function(String status)? _onStatus;
  void Function(SpeechFailure failure)? _onError;
  void Function(SpeechResult result)? _onResult;

  void emitResult(String transcript, {bool isFinal = false}) =>
      _onResult?.call(SpeechResult(transcript, isFinal: isFinal));

  void emitStatus(String status) => _onStatus?.call(status);

  void emitError(String errorMsg, {bool permanent = false}) =>
      _onError?.call(SpeechFailure(errorMsg, permanent: permanent));

  @override
  bool get isAvailable => availableValue;

  @override
  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(SpeechFailure failure)? onError,
  }) async {
    permissionChecks++;
    _onStatus = onStatus;
    _onError = onError;
    return permission;
  }

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<List<String>> localeIds() async => supportedLocales;

  @override
  Future<String?> systemLocaleId() async => systemLocale;

  @override
  Future<void> listen({
    required void Function(SpeechResult result) onResult,
    String? localeId,
    required Duration pauseFor,
    required Duration listenFor,
  }) async {
    listenCalls++;
    if (throwOnListen) throw StateError('mic busy');
    _onResult = onResult;
    lastOptions = (pauseFor: pauseFor, listenFor: listenFor, localeId: localeId);
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> cancel() async => cancelCalls++;
}

class Harness {
  final List<String> partials = [];
  final List<String> finals = [];
  final List<String> errors = [];
  int readies = 0;

  VoiceCallbacks get callbacks => VoiceCallbacks(
    onReady: () => readies++,
    onPartial: partials.add,
    onFinal: finals.add,
    onError: errors.add,
  );
}

const Duration grace = Duration(milliseconds: 30);

void main() {
  late FakeRecognizer recognizer;

  setUp(() => recognizer = FakeRecognizer());

  DeviceVoiceProvider provider({TargetPlatform platform = TargetPlatform.android}) =>
      DeviceVoiceProvider(recognizer, stopGrace: grace, platform: platform);

  Future<(DeviceVoiceProvider, Harness)> started({
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    final voice = provider(platform: platform);
    final harness = Harness();
    await voice.requestPermission();
    await voice.start(harness.callbacks);
    return (voice, harness);
  }

  group('availability and permission', () {
    test('reports unavailable when the device has no recogniser', () async {
      recognizer.availableValue = false;
      final voice = provider();
      await voice.requestPermission();

      expect(voice.available, isFalse);
    });

    test('reports a declined permission rather than throwing', () async {
      recognizer.permission = false;

      expect(await provider().requestPermission(), isFalse);
    });

    test('does not re-ask the recogniser once permission is granted', () async {
      final voice = provider();

      await voice.requestPermission();
      await voice.requestPermission();
      await voice.requestPermission();

      expect(recognizer.permissionChecks, 1);
    });

    test('resolves the recogniser locale against the device locale', () async {
      recognizer.systemLocale = 'en_IN';
      final voice = provider();
      await voice.requestPermission();
      await voice.start(Harness().callbacks);

      expect(voice.language, 'en-IN');
      expect(recognizer.lastOptions?.localeId, 'en-IN');
    });

    test('falls back to the same language in another region, then to en-US', () async {
      recognizer.supportedLocales = ['en-GB', 'fr-FR'];
      recognizer.systemLocale = 'en-AU';
      final first = provider();
      await first.requestPermission();
      await first.start(Harness().callbacks);
      expect(first.language, 'en-GB');

      recognizer.supportedLocales = ['fr-FR'];
      final second = provider();
      await second.requestPermission();
      await second.start(Harness().callbacks);
      expect(second.language, 'en-US');
    });
  });

  group('warm-up', () {
    test('signals readiness only when the recogniser actually starts capturing', () async {
      final (_, harness) = await started();

      expect(harness.readies, 0);

      recognizer.emitStatus(kSpeechListening);
      expect(harness.readies, 1);
    });

    test('does not signal readiness for a session already abandoned', () async {
      final (voice, harness) = await started();

      voice.abort();
      recognizer.emitStatus(kSpeechListening);

      expect(harness.readies, 0);
    });

    test('asks for partial results and a pause window long enough to think in', () async {
      await started();

      expect(recognizer.lastOptions?.pauseFor, const Duration(seconds: 10));
      expect(recognizer.lastOptions?.listenFor.inMinutes, greaterThanOrEqualTo(5));
    });
  });

  group('transcript delivery', () {
    test('streams partials and delivers one final transcript', () async {
      final (_, harness) = await started();

      recognizer.emitResult('add a test');
      recognizer.emitResult('add a test for pairing');
      expect(harness.partials, ['add a test', 'add a test for pairing']);

      recognizer.emitResult('add a test for pairing.', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['add a test for pairing.']);
    });

    test('delivers the transcript exactly once even when done repeats', () async {
      final (_, harness) = await started();

      recognizer.emitResult('ship it', isFinal: true);
      recognizer.emitStatus(kSpeechDone);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['ship it']);
    });

    test('does not end the recording on a final result — the user may still be talking', () async {
      final (_, harness) = await started();

      recognizer.emitResult('open the pull request', isFinal: true);
      expect(harness.finals, isEmpty);

      recognizer.emitResult('and rerun the tests', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['open the pull request and rerun the tests']);
    });

    test('keeps banked segments while a later segment is still forming', () async {
      final (_, harness) = await started();

      recognizer.emitResult('fix the parser', isFinal: true);
      recognizer.emitResult('then');
      expect(harness.partials.last, 'fix the parser then');

      recognizer.emitResult('then commit');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['fix the parser then commit']);
    });

    test('keeps earlier speech when Android rolls over to a new segment with no final', () async {
      final (_, harness) = await started();

      recognizer.emitResult('add a test');
      recognizer.emitResult('add a test for the pairing flow');
      recognizer.emitResult('then run');
      recognizer.emitResult('then run the linter');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['add a test for the pairing flow then run the linter']);
    });

    test('does not treat an in-place revision as a new segment', () async {
      final (_, harness) = await started();

      recognizer.emitResult('add a test');
      recognizer.emitResult('add a test for pairing');
      recognizer.emitResult('add attest for pairing flow');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['add attest for pairing flow']);
    });

    test('does not duplicate a segment that ends with a final result', () async {
      final (_, harness) = await started();

      recognizer.emitResult('open the');
      recognizer.emitResult('open the pull request');
      recognizer.emitResult('open the pull request', isFinal: true);
      recognizer.emitResult('then merge it');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['open the pull request then merge it']);
    });

    test('does not duplicate when iOS emits a cumulative final mid-recording', () async {
      final (_, harness) = await started(platform: TargetPlatform.iOS);

      recognizer.emitResult('how is the system');
      recognizer.emitResult('how is the system turning', isFinal: true);
      recognizer.emitResult('how is the system turning right now');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['how is the system turning right now']);
    });

    test('does not duplicate across several cumulative iOS finals', () async {
      final (_, harness) = await started(platform: TargetPlatform.iOS);

      recognizer.emitResult('open the', isFinal: true);
      recognizer.emitResult('open the pull request', isFinal: true);
      recognizer.emitResult('open the pull request and merge it', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['open the pull request and merge it']);
    });

    test('keeps the live readout cumulative-but-not-doubled on iOS', () async {
      final (_, harness) = await started(platform: TargetPlatform.iOS);

      recognizer.emitResult('ship the');
      recognizer.emitResult('ship the release', isFinal: true);

      expect(harness.partials.last, 'ship the release');
    });

    test('preserves earlier speech across an iOS recognition-task restart', () async {
      final (_, harness) = await started(platform: TargetPlatform.iOS);

      recognizer.emitResult('first half of the sentence');
      recognizer.emitResult('first half of the sentence complete', isFinal: true);
      recognizer.emitResult('second');
      recognizer.emitResult('second half now');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['first half of the sentence complete second half now']);
    });

    test('keeps the words already heard when the session ends without a final result', () async {
      final (_, harness) = await started();

      recognizer.emitResult('run the tests');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['run the tests']);
      expect(harness.errors, isEmpty);
    });

    test('reports an empty transcript rather than an error when nothing was said', () async {
      final (_, harness) = await started();

      recognizer.emitError('error_no_match');

      expect(harness.finals, ['']);
      expect(harness.errors, isEmpty);
    });

    test('trims the transcript', () async {
      final (_, harness) = await started();

      recognizer.emitResult('  hello world  ', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, ['hello world']);
    });
  });

  group('failures', () {
    test('surfaces a readable message for a real error', () async {
      final (_, harness) = await started();

      recognizer.emitError('error_permission', permanent: true);

      expect(harness.errors.single, contains('permission'));
      expect(harness.finals, isEmpty);
    });

    test('does not emit a transcript after an error', () async {
      final (_, harness) = await started();

      recognizer.emitError('error_audio_error', permanent: true);
      recognizer.emitResult('too late', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, isEmpty);
      expect(harness.errors, hasLength(1));
    });

    test('reports a start failure through onError', () async {
      recognizer.throwOnListen = true;
      final voice = provider();
      final harness = Harness();
      await voice.requestPermission();

      await voice.start(harness.callbacks);

      expect(harness.errors.single, contains('mic busy'));
    });
  });

  group('lifecycle', () {
    test('aborting delivers nothing and drops its callbacks', () async {
      final (voice, harness) = await started();

      voice.abort();
      expect(recognizer.cancelCalls, 1);

      recognizer.emitError('error_request_cancelled');
      recognizer.emitStatus(kSpeechDone);

      expect(harness.finals, isEmpty);
      expect(harness.errors, isEmpty);
    });

    test('does not leave the previous recording attached on restart', () async {
      final voice = provider();
      final first = Harness();
      final second = Harness();
      await voice.requestPermission();

      await voice.start(first.callbacks);
      await voice.start(second.callbacks);
      recognizer.emitResult('second phrase', isFinal: true);
      recognizer.emitStatus(kSpeechDone);

      expect(first.finals, isEmpty);
      expect(second.finals, ['second phrase']);
    });

    test('delivers the transcript even if done never arrives after stop', () async {
      final (voice, harness) = await started();

      recognizer.emitResult('deploy to staging');
      voice.stop();
      expect(harness.finals, isEmpty);

      await Future<void>.delayed(grace * 2);

      expect(harness.finals, ['deploy to staging']);
    });

    test('does not double-deliver when done arrives after stop', () async {
      final (voice, harness) = await started();

      recognizer.emitResult('run the linter');
      voice.stop();
      recognizer.emitStatus(kSpeechDone);
      await Future<void>.delayed(grace * 2);

      expect(harness.finals, ['run the linter']);
    });
  });
}
