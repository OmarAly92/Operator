import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/logic/keys.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_status_bar.dart';

import '../../../terminal_harness.dart';

void main() {
  late TerminalHarness harness;

  setUpAll(() => registerFallbackValue(const SendSessionMessageParams(message: '')));

  setUp(() => harness = TerminalHarness()..start());

  tearDown(() => harness.dispose());

  testWidgets('every control key writes its sequence to the PTY', (tester) async {
    await harness.pump(tester, const TerminalKeyRow());

    for (final key in kControlKeys) {
      await tester.tap(find.text(key.label));
      await tester.pump();
      verify(() => harness.mux.sendInput('s-1', key.sequence, projectId: null)).called(1);
    }
  });

  testWidgets('the composer sends and clears', (tester) async {
    final cubit = harness.cubit;
    when(() => harness.terminalRepository.sendSessionMessage(any(), any()))
        .thenAnswer((_) async => Result.success(true));
    await harness.pump(tester, const TerminalComposer());

    await tester.enterText(find.byType(TextField), 'ship it');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();

    expect(cubit.composer.text, isEmpty);
  });

  testWidgets('the route toggle switches the composer to the PTY', (tester) async {
    final cubit = harness.cubit;
    await harness.pump(tester, const TerminalComposer());

    await tester.tap(find.byTooltip('Switch to terminal'));
    await tester.pump();

    expect(cubit.sendTarget, SendTarget.terminal);
    expect(find.text('Send to terminal...'), findsOneWidget);
  });

  testWidgets('a plain worktree shell hides the misleading agent toggle', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
    await harness.pump(tester, const TerminalComposer());

    expect(find.byTooltip('Switch to terminal'), findsNothing);
    expect(find.byTooltip('Switch to chat'), findsNothing);
  });

  testWidgets('the status bar shows liveness, the grid and the zoom pair', (tester) async {
    final cubit = harness.cubit;
    await harness.pump(tester, TerminalStatusBar(onKill: () {}, onRestore: () {}));
    cubit.reportFit(const TerminalGrid(80, 24));
    await tester.pump();
    await tester.pump();

    expect(find.text('live'), findsOneWidget);
    expect(find.text('80x24'), findsOneWidget);

    await tester.tap(find.byTooltip('Smaller text'));
    await tester.pump();
    expect(cubit.fontSize, 11);
  });

  testWidgets('the status bar offers Restore instead of Kill once the PTY is gone', (tester) async {
    var restored = 0;
    await harness.pump(tester, TerminalStatusBar(onKill: () {}, onRestore: () => restored++));

    await tester.runAsync(() async {
      harness.events.add(const TerminalExitedEvent('s-1', 1));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    expect(find.bySemanticsLabel('Kill session'), findsNothing);
    await tester.tap(find.text('Restore'));
    expect(restored, 1);
  });
}
