import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_surface.dart';

import '../../../terminal_harness.dart';

void main() {
  late TerminalHarness harness;

  setUp(() => harness = TerminalHarness()..start());

  tearDown(() => harness.dispose());

  testWidgets('shows the terminal, its title and the dock', (tester) async {
    await harness.pump(tester, const TerminalScreen());

    expect(find.text('Session'), findsOneWidget);
    expect(find.byType(TerminalSurface), findsOneWidget);
    expect(find.byType(TerminalKeyRow), findsOneWidget);
    expect(find.byType(TerminalComposer), findsOneWidget);
  });

  testWidgets('dismisses the banner when tapped', (tester) async {
    await harness.pump(tester, const TerminalScreen());

    await tester.runAsync(() async {
      harness.events.add(const TerminalErrorEvent('s-1', 'pty write failed'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(find.textContaining('pty write failed'), findsOneWidget);

    await tester.tap(find.textContaining('pty write failed'));
    await tester.pump();
    expect(find.textContaining('pty write failed'), findsNothing);
  });

  testWidgets('offers Restore over the dead terminal', (tester) async {
    when(() => harness.sessionsRepository.restore(any()))
        .thenAnswer((_) async => Result.success(true));
    await harness.pump(tester, const TerminalScreen());

    await tester.runAsync(() async {
      harness.events.add(const TerminalExitedEvent('s-1', 1));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    expect(find.text('Session terminated'), findsOneWidget);
    await tester.tap(find.text('Restore session'));
    await tester.pump();
    verify(() => harness.sessionsRepository.restore('s-1')).called(1);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('confirms before killing, and leaves once the session is gone', (tester) async {
    when(() => harness.sessionsRepository.kill(any()))
        .thenAnswer((_) async => Result.success(true));
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Kill session'));
    await tester.pumpAndSettle();
    expect(find.text('Kill session?'), findsOneWidget);

    await tester.tap(find.text('Kill'));
    await tester.pumpAndSettle();
    verify(() => harness.sessionsRepository.kill('s-1')).called(1);
  });

  testWidgets('a shell asks to close rather than kill', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
    when(() => harness.terminalRepository.closeShellTerminal(any()))
        .thenAnswer((_) async => Result.success(true));
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Close shell'));
    await tester.pumpAndSettle();
    expect(find.text('Close shell?'), findsOneWidget);
  });

  testWidgets('a covered harness opens in blocks and never joins the terminal channel', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(harness: 'claude-code');
    await harness.pump(tester, const TerminalScreen());

    expect(find.byType(BlocksBody), findsOneWidget);
    expect(find.byType(TerminalSurface), findsNothing);
    verifyNever(() => harness.mux.openTerminal(any(), projectId: any(named: 'projectId')));
    verifyNever(() => harness.mux.resize(any(), any(), any(), projectId: any(named: 'projectId')));
  });

  testWidgets('the toggle swaps to raw, which is what joins the channel', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(harness: 'claude-code');
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Show raw terminal'));
    await tester.pumpAndSettle();

    expect(find.byType(TerminalSurface), findsOneWidget);
    verify(() => harness.mux.openTerminal('s-1', projectId: null)).called(1);
  });

  testWidgets('toggling back to blocks leaves the terminal channel again', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(harness: 'claude-code');
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Show raw terminal'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Show blocks'));
    await tester.pumpAndSettle();

    expect(find.byType(BlocksBody), findsOneWidget);
    verify(() => harness.mux.closeTerminal('s-1', projectId: null)).called(1);
  });

  testWidgets('a worktree shell has no blocks toggle and opens raw', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
    await harness.pump(tester, const TerminalScreen());

    expect(find.byType(TerminalSurface), findsOneWidget);
    expect(find.bySemanticsLabel('Show blocks'), findsNothing);
    expect(find.bySemanticsLabel('Show raw terminal'), findsNothing);
  });
}
