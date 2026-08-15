import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

class _FakeProvider implements VoiceProvider {
  bool availableValue = true;
  bool permission = true;
  int starts = 0;
  int stops = 0;
  int aborts = 0;
  VoiceMode? lastMode;
  VoiceCallbacks? callbacks;

  @override
  bool get available => availableValue;

  @override
  String? get language => 'en-US';

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<void> start(VoiceCallbacks callbacks, {VoiceMode mode = VoiceMode.push}) async {
    starts++;
    lastMode = mode;
    this.callbacks = callbacks;
  }

  @override
  void stop() => stops++;

  @override
  void abort() => aborts++;
}

const Duration tapThreshold = Duration(milliseconds: 40);
const Duration doubleTapWindow = Duration(milliseconds: 60);
const Duration restartDelay = Duration(milliseconds: 10);

void main() {
  late _FakeProvider provider;
  late List<String> transcripts;

  setUp(() {
    provider = _FakeProvider();
    transcripts = [];
  });

  VoiceInputCubit build() => VoiceInputCubit(
    provider,
    onTranscript: transcripts.add,
    tapThreshold: tapThreshold,
    doubleTapWindow: doubleTapWindow,
    restartDelay: restartDelay,
  );

  test('reports unavailable when the device has no recogniser', () async {
    provider.availableValue = false;
    final cubit = build();

    expect(cubit.phase, VoiceState.unavailable);
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    expect(provider.starts, 0);
    await cubit.close();
  });

  test('a denied permission moves to denied and explains itself', () async {
    provider.permission = false;
    final cubit = build();

    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.phase, VoiceState.denied);
    expect(cubit.error, contains('Settings'));
    await cubit.close();
  });

  test('a hold starts the recogniser and only claims recording once it is ready', () async {
    final cubit = build();

    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.phase, VoiceState.starting);
    expect(provider.lastMode, VoiceMode.push);

    provider.callbacks!.onReady();
    expect(cubit.phase, VoiceState.recording);
    await cubit.close();
  });

  test('the live partial reaches the cubit and clears when the phrase lands', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    provider.callbacks!.onReady();

    provider.callbacks!.onPartial('ship the release');
    expect(cubit.partial, 'ship the release');

    provider.callbacks!.onFinal('ship the release');
    expect(transcripts, ['ship the release']);
    expect(cubit.partial, isEmpty);
    expect(cubit.phase, VoiceState.idle);
    await cubit.close();
  });

  test('an empty transcript is a no-op, not a send', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    provider.callbacks!.onReady();

    provider.callbacks!.onFinal('');

    expect(transcripts, isEmpty);
    expect(cubit.phase, VoiceState.idle);
    await cubit.close();
  });

  test('an error surfaces and returns to idle', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    provider.callbacks!.onReady();

    provider.callbacks!.onError('Could not capture audio from the microphone.');

    expect(cubit.error, 'Could not capture audio from the microphone.');
    expect(cubit.phase, VoiceState.idle);
    await cubit.close();
  });

  test('releasing before the recogniser is live aborts instead of finalising', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);

    await Future<void>.delayed(tapThreshold * 2);
    cubit.pressOut();

    expect(provider.aborts, 1);
    expect(provider.stops, 0);
    expect(cubit.phase, VoiceState.idle);
    await cubit.close();
  });

  test('a hold longer than the threshold stops and keeps the transcript', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    provider.callbacks!.onReady();

    await Future<void>.delayed(tapThreshold * 2);
    cubit.pressOut();

    expect(provider.stops, 1);
    expect(cubit.phase, VoiceState.recording);
    await cubit.close();
  });

  test('a tap throws away its sliver of audio and opens the double-tap window', () async {
    final cubit = build();

    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    cubit.pressOut();

    expect(provider.aborts, 1);
    expect(cubit.phase, VoiceState.idle);
    await cubit.close();
  });

  test('a second tap latches, and the latched recording ignores the finger', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    cubit.pressOut();

    cubit.pressIn();
    await Future<void>.delayed(restartDelay * 3);

    expect(cubit.mode, VoiceMode.latched);
    expect(provider.lastMode, VoiceMode.latched);

    cubit.pressOut();
    expect(provider.stops, 0);
    await cubit.close();
  });

  test('pressing again while latched stops the recording', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    cubit.pressOut();
    cubit.pressIn();
    await Future<void>.delayed(restartDelay * 3);
    provider.callbacks!.onReady();

    cubit.pressIn();

    expect(provider.stops, 1);
    await cubit.close();
  });

  test('backgrounding the app closes the microphone', () async {
    final cubit = build();
    cubit.pressIn();
    await Future<void>.delayed(Duration.zero);
    provider.callbacks!.onReady();

    cubit.onAppBackgrounded();

    expect(provider.aborts, 1);
    expect(cubit.phase, VoiceState.idle);
    expect(cubit.mode, VoiceMode.push);
    await cubit.close();
  });
}
