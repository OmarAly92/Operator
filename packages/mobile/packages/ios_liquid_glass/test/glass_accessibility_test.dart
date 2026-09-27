import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

void main() {
  tearDown(GlassAccessibility.debugReset);

  Future<GlassAccessibilityData> read(WidgetTester tester, {MediaQueryData media = const MediaQueryData()}) async {
    late GlassAccessibilityData data;
    await tester.pumpWidget(
      MediaQuery(
        data: media,
        child: Builder(builder: (context) {
          data = GlassAccessibility.of(context);
          return const SizedBox();
        }),
      ),
    );
    return data;
  }

  test('parses the channel map and merges with or', () {
    final data = GlassAccessibilityData.fromMap({'reduceTransparency': true, 'increaseContrast': false});
    expect(data, const GlassAccessibilityData(reduceTransparency: true));
    expect(data.merge(const GlassAccessibilityData(reduceMotion: true)), const GlassAccessibilityData(reduceTransparency: true, reduceMotion: true));
  });

  testWidgets('without the plugin, contrast and motion come from MediaQuery and transparency is off', (tester) async {
    final data = await read(tester, media: const MediaQueryData(highContrast: true, disableAnimations: true));
    expect(data, const GlassAccessibilityData(increaseContrast: true, reduceMotion: true));
  });

  testWidgets('on iOS the channel supplies reduce transparency and updates live', (tester) async {
    late MockStreamHandlerEventSink sink;
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      GlassAccessibility.channel,
      MockStreamHandler.inline(onListen: (arguments, events) {
        sink = events;
        events.success({'reduceTransparency': true, 'increaseContrast': false, 'reduceMotion': false});
      }),
    );
    await read(tester);
    await tester.pump();
    expect(GlassAccessibility.platform.value.reduceTransparency, isTrue);
    sink.success({'reduceTransparency': false, 'increaseContrast': true, 'reduceMotion': false});
    await tester.pump();
    expect(await read(tester), const GlassAccessibilityData(increaseContrast: true));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a debug override wins', (tester) async {
    GlassAccessibility.debugOverride = const GlassAccessibilityData(reduceTransparency: true);
    expect(await read(tester, media: const MediaQueryData(highContrast: true)), const GlassAccessibilityData(reduceTransparency: true));
  });
}
