import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer_draft_hint.dart';

import '../../../terminal_harness.dart';

void main() {
  late TerminalHarness harness;

  setUp(() => harness = TerminalHarness()..start());

  tearDown(() => harness.dispose());

  Future<void> pumpComposer(WidgetTester tester) =>
      harness.pump(tester, const TerminalComposer());

  testWidgets('shows a remote draft as prefill while the field is empty', (tester) async {
    harness.cubit.draft = 'run the sample task';

    await pumpComposer(tester);

    expect(find.text('run the sample task'), findsOneWidget);
  });

  testWidgets('hides the remote draft once the user has typed something', (tester) async {
    harness.cubit.draft = 'run the sample task';
    harness.cubit.composer.text = 'already typing';

    await pumpComposer(tester);

    expect(find.text('run the sample task'), findsNothing);
  });

  testWidgets('tapping the remote draft fills the field without sending', (tester) async {
    harness.cubit.draft = 'run the sample task';

    await pumpComposer(tester);
    await tester.tap(find.text('run the sample task'));
    await tester.pump();

    expect(harness.cubit.composer.text, 'run the sample task');
    verifyNever(
      () => harness.mux.sendInput(any(), any(), projectId: any(named: 'projectId')),
    );
  });

  // In the running app fetchDraft() always resolves AFTER the composer's first
  // build, so a hint that reads cubit.draft once at build time never appears.
  testWidgets('a draft that arrives after the first build still shows', (tester) async {
    when(() => harness.terminalRepository.getDraft(any()))
        .thenAnswer((_) async => Result.success('run the sample task'));

    await pumpComposer(tester);
    expect(find.text('run the sample task'), findsNothing);

    await harness.cubit.fetchDraft();
    await tester.pump();
    await tester.pump();

    expect(find.text('run the sample task'), findsOneWidget);
  });

  testWidgets('an empty remote draft shows nothing', (tester) async {
    harness.cubit.draft = '';

    await pumpComposer(tester);

    expect(find.byType(TerminalComposerDraftHint), findsOneWidget);
    expect(
      find.descendant(of: find.byType(TerminalComposerDraftHint), matching: find.byType(AppText)),
      findsNothing,
    );
  });
}
