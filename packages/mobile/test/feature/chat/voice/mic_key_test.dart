import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/ui/mic_key.dart';
import 'package:operator_mobile/feature/chat/voice/ui/voice_strip.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

class _FakeProvider implements VoiceProvider {
  _FakeProvider({this.availableValue = true});

  final bool availableValue;
  VoiceCallbacks? callbacks;

  @override
  bool get available => availableValue;

  @override
  String? get language => 'en-US';

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start(
    VoiceCallbacks callbacks, {
    VoiceMode mode = VoiceMode.push,
  }) async => this.callbacks = callbacks;

  @override
  void stop() {}

  @override
  void abort() {}
}

void main() {
  late _FakeProvider provider;

  Future<VoiceInputCubit> pump(
    WidgetTester tester, {
    bool available = true,
    List<String>? transcripts,
  }) async {
    provider = _FakeProvider(availableValue: available);
    final cubit = VoiceInputCubit(
      provider,
      onTranscript: (text) => transcripts?.add(text),
      tapThreshold: const Duration(milliseconds: 40),
    );
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<VoiceInputCubit>.value(
                value: cubit,
                child: const Column(children: [VoiceStrip(), MicKey()]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(cubit.close);
    return cubit;
  }

  testWidgets('stays in the row but is inert when dictation is unavailable', (
    tester,
  ) async {
    await pump(tester, available: false);

    expect(find.byType(MicKey), findsOneWidget);
    expect(find.byIcon(Icons.mic_off), findsOneWidget);
    expect(
      find.bySemanticsLabel('Dictation unavailable on this device'),
      findsOneWidget,
    );
  });

  testWidgets(
    'holding the key starts a recording and the strip says to keep holding',
    (tester) async {
      await pump(tester);

      await tester.press(find.byType(MicKey));
      await tester.pump();
      await tester.pump();

      expect(find.text('Keep holding…'), findsOneWidget);
    },
  );

  testWidgets(
    'once recording, the strip shows the live partial and the transcript lands',
    (tester) async {
      final transcripts = <String>[];
      await pump(tester, transcripts: transcripts);
      await tester.press(find.byType(MicKey));
      await tester.pump();
      await tester.pump();

      provider.callbacks!.onReady();
      provider.callbacks!.onPartial('ship the release');
      await tester.pump();
      expect(find.text('ship the release'), findsOneWidget);

      provider.callbacks!.onFinal('ship the release');
      await tester.pump();
      expect(transcripts, ['ship the release']);
      expect(find.text('ship the release'), findsNothing);
    },
  );

  testWidgets('the strip takes no room while idle', (tester) async {
    await pump(tester);

    expect(find.byType(VoiceStrip), findsOneWidget);
    expect(find.text('Listening…'), findsNothing);
    expect(find.text('Keep holding…'), findsNothing);
  });

  testWidgets('a voice error is shown on the strip', (tester) async {
    await pump(tester);
    await tester.press(find.byType(MicKey));
    await tester.pump();
    await tester.pump();

    provider.callbacks!.onError('Could not capture audio from the microphone.');
    await tester.pump();

    expect(
      find.text('Could not capture audio from the microphone.'),
      findsOneWidget,
    );
  });

  testWidgets('a double tap latches, and the key names the stop gesture', (
    tester,
  ) async {
    final cubit = await pump(tester);

    await tester.tap(find.byType(MicKey));
    await tester.pump();
    await tester.press(find.byType(MicKey));
    await tester.pump(const Duration(milliseconds: 200));
    provider.callbacks!.onReady();
    await tester.pump();

    expect(cubit.mode, VoiceMode.latched);
    expect(find.bySemanticsLabel('Stop dictating'), findsOneWidget);
  });

  test('appending a transcript respects what is already typed', () {
    expect(appendTranscript('', 'ship it'), 'ship it');
    expect(appendTranscript('please', 'ship it'), 'please ship it');
    expect(appendTranscript('please ', 'ship it'), 'please ship it');
  });
}
