import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_scroll.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_surface.dart';
import 'package:xterm/xterm.dart';

import '../../../terminal_harness.dart';

/// Escape sequences the pane sends to describe itself, so each test can put the
/// terminal into the state whose scrolling it is pinning.
const String _enterAltBuffer = '\x1b[?1049h';
const String _enableMouseTracking = '\x1b[?1000h\x1b[?1006h';

void main() {
  late TerminalHarness harness;
  late List<String> sent;

  void listen() {
    sent = [];
    when(() => harness.mux.sendInput(any(), any(), projectId: any(named: 'projectId')))
        .thenAnswer((invocation) => sent.add(invocation.positionalArguments[1] as String));
  }

  tearDown(() => harness.dispose());

  Future<void> pump(WidgetTester tester, {String? harnessName}) async {
    harness = TerminalHarness()..start(harness: harnessName);
    listen();
    await harness.pump(tester, const TerminalSurface());
  }

  /// A drag far enough to cross several tmux wheel steps.
  Future<void> dragBy(WidgetTester tester, double dy) async {
    sent.clear();
    await tester.drag(find.byType(TerminalView), Offset(0, dy));
    await tester.pumpAndSettle();
  }

  testWidgets('reports the wheel to tmux with no modifier bits', (tester) async {
    await pump(tester);
    harness.cubit.terminal.write('$_enterAltBuffer$_enableMouseTracking');
    await tester.pump();

    await dragBy(tester, 240);

    expect(sent, isNotEmpty);
    expect(sent.every((s) => s == sgrWheelReport(up: true)), isTrue,
        reason: 'expected plain wheel-up reports, got $sent');
  });

  testWidgets('reports wheel down when dragging toward newer output', (tester) async {
    await pump(tester);
    harness.cubit.terminal.write('$_enterAltBuffer$_enableMouseTracking');
    await tester.pump();

    await dragBy(tester, -240);

    expect(sent, isNotEmpty);
    expect(sent.every((s) => s == sgrWheelReport(up: false)), isTrue,
        reason: 'expected plain wheel-down reports, got $sent');
  });

  testWidgets('sends one report per tmux wheel step so the drag tracks 1:1', (tester) async {
    await pump(tester);
    harness.cubit.terminal.write('$_enterAltBuffer$_enableMouseTracking');
    await tester.pump();

    await dragBy(tester, 240);
    final divided = sent.length;

    await dragBy(tester, 240 * kTmuxWheelLines.toDouble());

    expect(sent.length, closeTo(divided * kTmuxWheelLines, kTmuxWheelLines),
        reason: 'reports should scale with drag distance, divided by the tmux step');
  });

  testWidgets('never sends arrow keys, which would edit the agent prompt', (tester) async {
    await pump(tester);
    harness.cubit.terminal.write(_enterAltBuffer);
    await tester.pump();

    await dragBy(tester, 240);

    expect(sent, isNot(contains('\x1b[A')));
    expect(sent, isNot(contains('\x1b[B')));
  });

  testWidgets('falls back to page keys in an alt buffer with no mouse tracking', (tester) async {
    await pump(tester);
    harness.cubit.terminal.write(_enterAltBuffer);
    await tester.pump();

    await dragBy(tester, 240);

    expect(sent, isNotEmpty);
    expect(sent.every((s) => s == pageKeyReport(up: true)), isTrue,
        reason: 'expected PageUp, got $sent');
  });

  testWidgets('pages a keyboard-scroll agent even when it tracks the mouse', (tester) async {
    await pump(tester, harnessName: 'opencode');
    harness.cubit.terminal.write('$_enterAltBuffer$_enableMouseTracking');
    await tester.pump();

    await dragBy(tester, 240);

    expect(sent, isNotEmpty);
    expect(sent.every((s) => s == pageKeyReport(up: true)), isTrue,
        reason: 'expected PageUp for a keyboard-scroll TUI, got $sent');
  });

  testWidgets('leaves a plain shell to scroll its own scrollback', (tester) async {
    await pump(tester);
    for (var i = 0; i < 200; i++) {
      harness.cubit.terminal.write('line $i\r\n');
    }
    await tester.pump();

    await dragBy(tester, 240);

    expect(sent, isEmpty);
  });
}
