import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

import '../../terminal/terminal_harness.dart';

void main() {
  group('defaultViewMode', () {
    test('a worktree shell opens raw because shell blocks do not exist yet', () {
      expect(
        defaultViewMode(const TerminalArgs(id: 'h-1', sessionId: 's-1', title: 'Shell', shellOnly: true)),
        SessionViewMode.raw,
      );
    });

    test('a covered harness opens in blocks', () {
      expect(
        defaultViewMode(const TerminalArgs(id: 's-1', sessionId: 's-1', title: 'S', harness: 'claude-code')),
        SessionViewMode.blocks,
      );
    });

    test('an uncovered or unknown harness opens raw', () {
      expect(
        defaultViewMode(const TerminalArgs(id: 's-1', sessionId: 's-1', title: 'S', harness: 'aider')),
        SessionViewMode.raw,
      );
      expect(
        defaultViewMode(const TerminalArgs(id: 's-1', sessionId: 's-1', title: 'S')),
        SessionViewMode.raw,
      );
    });
  });

  group('SessionViewCubit', () {
    test('toggles between the two modes', () {
      final cubit = SessionViewCubit(SessionViewMode.blocks);

      expect(cubit.mode, SessionViewMode.blocks);
      cubit.toggle();
      expect(cubit.mode, SessionViewMode.raw);
      cubit.toggle();
      expect(cubit.mode, SessionViewMode.blocks);
      cubit.close();
    });
  });

  group('TerminalCubit attach', () {
    late TerminalHarness harness;

    setUp(() => harness = TerminalHarness()..start());
    tearDown(() => harness.dispose());

    test('constructing the cubit does not join the terminal channel', () {
      verifyNever(() => harness.mux.openTerminal(any(), projectId: any(named: 'projectId')));
      expect(harness.cubit.attached, isFalse);
    });

    test('attach joins once, however many times it is called', () {
      harness.cubit.attach();
      harness.cubit.attach();

      verify(() => harness.mux.openTerminal('s-1', projectId: null)).called(1);
      expect(harness.cubit.attached, isTrue);
    });

    test('detach leaves, and a second detach is a no-op', () {
      harness.cubit.attach();
      harness.cubit.detach();
      harness.cubit.detach();

      verify(() => harness.mux.closeTerminal('s-1', projectId: null)).called(1);
      expect(harness.cubit.attached, isFalse);
    });

    test('a detached cubit reports no grid, so it cannot drive arbitration', () {
      harness.cubit.reportFit(const TerminalGrid(80, 24));

      verifyNever(() => harness.mux.resize(any(), any(), any(), projectId: any(named: 'projectId')));
    });

    test('an attached cubit does report its grid', () {
      harness.cubit.attach();
      harness.cubit.reportFit(const TerminalGrid(80, 24));

      verify(() => harness.mux.resize('s-1', 80, 24, projectId: null)).called(1);
    });

    test('a detached cubit does not write keystrokes to a PTY it does not hold', () {
      harness.cubit.sendKey('q');

      verifyNever(() => harness.mux.sendInput(any(), any(), projectId: any(named: 'projectId')));
    });

    test('closing a detached cubit does not close a terminal it never opened', () async {
      final local = TerminalHarness()..start();
      try {
        await local.cubit.close();
        verifyNever(() => local.mux.closeTerminal(any(), projectId: any(named: 'projectId')));
      } finally {
        await local.statuses.close();
        await local.events.close();
      }
    });
  });
}
