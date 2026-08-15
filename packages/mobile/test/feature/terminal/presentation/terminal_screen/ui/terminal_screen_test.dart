import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
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

  testWidgets('explains why Chat is unavailable instead of starting a handoff', (tester) async {
    when(() => harness.switchCubit.supported).thenReturn(false);
    when(() => harness.switchCubit.reason).thenReturn('This agent has no chat driver.');
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Open Chat interface'));
    await tester.pumpAndSettle();

    expect(find.text('This agent has no chat driver.'), findsOneWidget);
    verifyNever(() => harness.switchCubit.start(any(), any()));
  });

  testWidgets('asks how to hand off, then starts the chosen policy', (tester) async {
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Open Chat interface'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish, then switch'));
    await tester.pumpAndSettle();

    verify(() => harness.switchCubit.start('chat', 'drain')).called(1);
  });

  testWidgets('covers the terminal while a transition is in flight', (tester) async {
    when(() => harness.switchCubit.active).thenReturn(true);
    when(() => harness.switchCubit.cancellable).thenReturn(true);
    when(() => harness.switchCubit.phase).thenReturn('draining');
    await harness.pump(tester, const TerminalScreen());

    expect(find.text('Switching to Chat'), findsOneWidget);
    expect(find.textContaining('Waiting for the current terminal turn'), findsOneWidget);

    await tester.tap(find.text('Cancel switch'));
    await tester.pump();
    verify(() => harness.switchCubit.cancel()).called(1);
  });

  testWidgets('a worktree shell has no Chat handoff at all', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
    await harness.pump(tester, const TerminalScreen());

    expect(find.bySemanticsLabel('Open Chat interface'), findsNothing);
  });
}
