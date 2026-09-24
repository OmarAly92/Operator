import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';

void main() {
  Widget chevronHost(bool expanded) => MaterialApp(
        home: Scaffold(body: DisclosureChevron(expanded: expanded)),
      );

  Widget disclosureHost(bool expanded) => MaterialApp(
        home: Scaffold(
          body: Disclosure(expanded: expanded, child: const SizedBox(height: 40, width: 100)),
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
  });
}
