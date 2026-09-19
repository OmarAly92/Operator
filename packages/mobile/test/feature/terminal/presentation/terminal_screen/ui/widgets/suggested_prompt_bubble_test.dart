import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/suggested_prompt_bubble.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';

import '../../../../terminal_harness.dart';

void main() {
  late TerminalHarness harness;

  setUp(() => harness = TerminalHarness()..start());

  tearDown(() => harness.dispose());

  Future<void> pumpComposer(WidgetTester tester) async {
    await harness.pump(tester, const TerminalComposer());
    await tester.pumpAndSettle();
  }

  testWidgets('stays hidden while there is no suggestion', (tester) async {
    await pumpComposer(tester);

    expect(find.byType(SuggestedPromptBubble), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
  });

  testWidgets('animates the suggestion in once the fetch lands', (tester) async {
    when(() => harness.terminalRepository.getSuggestion(any()))
        .thenAnswer((_) async => Result.success('what is new in iOS 27'));
    await pumpComposer(tester);

    harness.cubit.attach();
    await tester.pumpAndSettle();

    expect(find.text('what is new in iOS 27'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });

  testWidgets('tapping the bubble fills the field and hides the bubble without sending', (
    tester,
  ) async {
    harness.cubit.suggestion = 'what is new in iOS 27';
    await pumpComposer(tester);

    await tester.tap(find.text('what is new in iOS 27'));
    await tester.pumpAndSettle();

    expect(harness.cubit.composer.text, 'what is new in iOS 27');
    expect(harness.cubit.suggestion, isNull);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    verifyNever(() => harness.mux.sendInput(any(), any(), projectId: any(named: 'projectId')));
  });

  testWidgets('the dismiss button hides the bubble and leaves the field alone', (
    tester,
  ) async {
    harness.cubit.suggestion = 'what is new in iOS 27';
    await pumpComposer(tester);

    await tester.tap(find.bySemanticsLabel('Dismiss suggestion'));
    await tester.pumpAndSettle();

    expect(harness.cubit.composer.text, isEmpty);
    expect(find.text('what is new in iOS 27'), findsNothing);
  });

  testWidgets('hides while the user is typing and returns once the field is cleared', (
    tester,
  ) async {
    harness.cubit.suggestion = 'what is new in iOS 27';
    await pumpComposer(tester);

    await tester.enterText(find.byType(TextField), 'my own words');
    await tester.pumpAndSettle();
    expect(find.text('what is new in iOS 27'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('what is new in iOS 27'), findsOneWidget);
  });
}
