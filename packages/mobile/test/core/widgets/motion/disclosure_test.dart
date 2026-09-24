import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$count'),
        TextButton(onPressed: () => setState(() => count++), child: const Text('inc')),
      ],
    );
  }
}

void main() {
  Widget chevronHost(bool expanded, {bool reduceMotion = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(body: DisclosureChevron(expanded: expanded)),
        ),
      );

  Widget disclosureHost(bool expanded, {bool reduceMotion = false, Widget? child}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Disclosure(expanded: expanded, child: child ?? const SizedBox(height: 40, width: 100)),
          ),
        ),
      );

  group('DisclosureChevron', () {
    testWidgets('rotation is between the two turn values at half duration', (tester) async {
      await tester.pumpWidget(chevronHost(false));
      await tester.pumpWidget(chevronHost(true));
      await tester.pump(AppMotion.disclosure ~/ 2);

      final turns = tester
          .widget<RotationTransition>(
            find.descendant(of: find.byType(DisclosureChevron), matching: find.byType(RotationTransition)),
          )
          .turns
          .value;

      expect(turns, greaterThan(0));
      expect(turns, lessThan(0.25));
    });

    testWidgets('settles at expandedTurns when expanded', (tester) async {
      await tester.pumpWidget(chevronHost(false));
      await tester.pumpWidget(chevronHost(true));
      await tester.pumpAndSettle();

      final turns = tester
          .widget<RotationTransition>(
            find.descendant(of: find.byType(DisclosureChevron), matching: find.byType(RotationTransition)),
          )
          .turns
          .value;

      expect(turns, 0.25);
    });

    testWidgets('rotates instantly under reduce motion', (tester) async {
      await tester.pumpWidget(chevronHost(false, reduceMotion: true));
      await tester.pumpWidget(chevronHost(true, reduceMotion: true));
      await tester.pump();

      final turns = tester
          .widget<RotationTransition>(
            find.descendant(of: find.byType(DisclosureChevron), matching: find.byType(RotationTransition)),
          )
          .turns
          .value;

      expect(turns, 0.25);
    });
  });

  group('Disclosure', () {
    testWidgets('height is 0 while collapsed', (tester) async {
      await tester.pumpWidget(disclosureHost(false));

      expect(tester.getSize(find.byType(Disclosure)).height, 0);
    });

    testWidgets('height is strictly between 0 and full at half duration', (tester) async {
      await tester.pumpWidget(disclosureHost(false));
      await tester.pumpWidget(disclosureHost(true));
      await tester.pump(AppMotion.disclosure ~/ 2);

      final height = tester.getSize(find.byType(Disclosure)).height;

      expect(height, greaterThan(0));
      expect(height, lessThan(40));
    });

    testWidgets('height reaches full at full duration', (tester) async {
      await tester.pumpWidget(disclosureHost(false));
      await tester.pumpWidget(disclosureHost(true));
      await tester.pump(AppMotion.disclosure);

      expect(tester.getSize(find.byType(Disclosure)).height, 40);
    });

    testWidgets('collapsing reaches 0', (tester) async {
      await tester.pumpWidget(disclosureHost(true));
      await tester.pump(AppMotion.disclosure);
      expect(tester.getSize(find.byType(Disclosure)).height, 40);

      await tester.pumpWidget(disclosureHost(false));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(Disclosure)).height, 0);
    });

    testWidgets('height jumps instantly under reduce motion', (tester) async {
      await tester.pumpWidget(disclosureHost(false, reduceMotion: true));
      await tester.pumpWidget(disclosureHost(true, reduceMotion: true));
      await tester.pump();

      expect(tester.getSize(find.byType(Disclosure)).height, 40);
    });

    testWidgets('collapse holds full height through the fade, then shrinks', (tester) async {
      await tester.pumpWidget(disclosureHost(true));
      await tester.pump(AppMotion.disclosure);
      expect(tester.getSize(find.byType(Disclosure)).height, 40);

      await tester.pumpWidget(disclosureHost(false));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getSize(find.byType(Disclosure)).height, 40);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getSize(find.byType(Disclosure)).height, 40);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getSize(find.byType(Disclosure)).height, 40);

      await tester.pump(const Duration(milliseconds: 50));
      final height = tester.getSize(find.byType(Disclosure)).height;
      expect(height, greaterThan(0));
      expect(height, lessThan(40));
    });

    testWidgets('keeps child state while expanded across rebuilds', (tester) async {
      const key = ValueKey('counter');
      await tester.pumpWidget(disclosureHost(true, child: const _Counter(key: key)));

      await tester.tap(find.text('inc'));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      await tester.pumpWidget(disclosureHost(true, child: const _Counter(key: key)));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
    });
  });
}
