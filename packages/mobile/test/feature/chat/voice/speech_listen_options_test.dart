import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (call) async {
        calls.add(call);
        return true;
      },
    );
  });

  group('SpeechListenOptions', () {
    test('defaults send an empty vocabulary and no session override', () async {
      await SpeechToTextPlatform.instance.listen(options: SpeechListenOptions());
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['contextualStrings'], isEmpty);
      expect(args['iosAudioCategory'], isNull);
      expect(args['possiblyCompleteSilence'], isNull);
    });

    test('carries the vocabulary, the session and the Android silence extra', () async {
      await SpeechToTextPlatform.instance.listen(
        options: SpeechListenOptions(
          contextualStrings: const ['git', 'npm'],
          iosAudioSession: const IosAudioSession(
            category: 'playAndRecord',
            categoryOptions: ['allowBluetooth', 'defaultToSpeaker'],
            mode: 'measurement',
          ),
          androidPossiblyCompleteSilenceMillis: 10000,
        ),
      );
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['contextualStrings'], ['git', 'npm']);
      expect(args['iosAudioCategory'], 'playAndRecord');
      expect(args['iosAudioCategoryOptions'], ['allowBluetooth', 'defaultToSpeaker']);
      expect(args['iosAudioMode'], 'measurement');
      expect(args['possiblyCompleteSilence'], 10000);
    });

    test('copyWith preserves the three new fields', () {
      final base = SpeechListenOptions(
        contextualStrings: const ['git'],
        iosAudioSession: const IosAudioSession(category: 'record', categoryOptions: [], mode: 'default'),
        androidPossiblyCompleteSilenceMillis: 10000,
      );
      final copy = base.copyWith(partialResults: false);
      expect(copy.contextualStrings, ['git']);
      expect(copy.iosAudioSession?.category, 'record');
      expect(copy.androidPossiblyCompleteSilenceMillis, 10000);
    });
  });
}
