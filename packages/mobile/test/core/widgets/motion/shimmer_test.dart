import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/motion/shimmer.dart';

void main() {
  const base = Colors.black;
  const highlight = Colors.white;
  final rect = Rect.fromLTWH(0, 0, 100, 100);

  Widget host({bool enabled = true, bool reduceMotion = false, bool tickerEnabled = true}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: TickerMode(
            enabled: tickerEnabled,
            child: Scaffold(
              body: Shimmer(
                base: base,
                highlight: highlight,
                enabled: enabled,
                child: const SizedBox(key: ValueKey('child'), width: 40, height: 40),
              ),
            ),
          ),
        ),
      );

  group('Shimmer gradient', () {
    test('transform changes as t advances', () {
      final rectAfterStart = Shimmer.gradientAt(t: 0.05, base: base, highlight: highlight)
          .transform!
          .transform(rect, textDirection: TextDirection.ltr);
      final rectMidSweep = Shimmer.gradientAt(t: 0.35, base: base, highlight: highlight)
          .transform!
          .transform(rect, textDirection: TextDirection.ltr);

      expect(rectAfterStart, isNot(equals(rectMidSweep)));
    });

    test('transform is static during the pause', () {
      final pauseStart = Shimmer.gradientAt(t: 0.85, base: base, highlight: highlight)
          .transform!
          .transform(rect, textDirection: TextDirection.ltr);
      final pauseEnd = Shimmer.gradientAt(t: 0.99, base: base, highlight: highlight)
          .transform!
          .transform(rect, textDirection: TextDirection.ltr);

      expect(pauseStart, equals(pauseEnd));
    });
  });

  group('Shimmer widget', () {
    testWidgets('renders a ShaderMask when enabled', (tester) async {
      await tester.pumpWidget(host());

      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.byKey(const ValueKey('child')), findsOneWidget);
    });

    testWidgets('renders the static child when disabled', (tester) async {
      await tester.pumpWidget(host(enabled: false));

      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byKey(const ValueKey('child')), findsOneWidget);
    });

    testWidgets('renders the static child under reduce motion', (tester) async {
      await tester.pumpWidget(host(reduceMotion: true));

      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byKey(const ValueKey('child')), findsOneWidget);
    });

    testWidgets('renders the static child when TickerMode is off', (tester) async {
      await tester.pumpWidget(host(tickerEnabled: false));

      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byKey(const ValueKey('child')), findsOneWidget);
    });

    testWidgets('schedules no frame when disabled', (tester) async {
      await tester.pumpWidget(host(enabled: false));
      await tester.pump();

      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('schedules no frame under reduce motion', (tester) async {
      await tester.pumpWidget(host(reduceMotion: true));
      await tester.pump();

      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('schedules no frame when TickerMode is off', (tester) async {
      await tester.pumpWidget(host(tickerEnabled: false));
      await tester.pump();

      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('resumes animating once re-enabled', (tester) async {
      await tester.pumpWidget(host(enabled: false));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(host());
      await tester.pump();

      expect(tester.hasRunningAnimations, isTrue);
    });
  });
}
