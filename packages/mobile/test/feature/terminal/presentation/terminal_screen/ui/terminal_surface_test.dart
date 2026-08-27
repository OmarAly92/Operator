import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_surface.dart';
import 'package:xterm/xterm.dart';

import '../../../terminal_harness.dart';

void main() {
  late TerminalHarness harness;

  setUp(() => harness = TerminalHarness()..start());

  tearDown(() => harness.dispose());

  Future<void> pumpSurface(WidgetTester tester) =>
      harness.pump(tester, const TerminalSurface());

  testWidgets('renders the terminal and reports the phone fit to the daemon', (tester) async {
    final cubit = harness.cubit;
    final mux = harness.mux;
    cubit.attach();
    await pumpSurface(tester);

    expect(find.byType(TerminalView), findsOneWidget);
    expect(cubit.grid, isNotNull);
    expect(cubit.grid!.cols, greaterThan(1));
    expect(cubit.grid!.rows, greaterThan(1));
    verify(() => mux.resize('s-1', cubit.grid!.cols, cubit.grid!.rows, projectId: null)).called(1);
  });

  testWidgets('re-reports the fit after a zoom changes the cell size', (tester) async {
    final cubit = harness.cubit;
    cubit.attach();
    await pumpSurface(tester);
    final before = cubit.grid!;

    cubit.zoom(-3);
    await tester.pump();
    await tester.pump();

    expect(cubit.grid!.cols, greaterThan(before.cols));
  });

  testWidgets('renders the daemon grid rather than its own fit once told', (tester) async {
    final cubit = harness.cubit;
    cubit.attach();
    await pumpSurface(tester);

    harness.events.add(const TerminalResizeEvent('s-1', 200, 50));
    await tester.pump();

    expect(cubit.grid, isNotNull);
    expect(cubit.grid!.cols, 200);
    expect(cubit.terminal.viewWidth, 200);
  });

  testWidgets(
    'a pinch ended by lifting the anchor finger last is not misread as a tap',
    (tester) async {
      final cubit = harness.cubit;
      cubit.attach();
      await pumpSurface(tester);

      cubit.zoom(-1);
      await tester.pump();
      await tester.pump();

      harness.events.add(const TerminalResizeEvent('s-1', 40, 45));
      await tester.pump();
      await tester.pump();

      final transformFinder = find
          .descendant(of: find.byType(OverflowBox), matching: find.byType(Transform))
          .first;
      Matrix4 currentTransform() => tester.widget<Transform>(transformFinder).transform;
      final before = currentTransform();
      expect(before, isNot(Matrix4.identity()));

      final anchor = tester.getCenter(find.byType(TerminalSurface));
      final moving = anchor + const Offset(40, 0);

      final movingGesture = await tester.startGesture(moving, pointer: 2);
      final anchorGesture = await tester.startGesture(anchor, pointer: 1);
      await tester.pump();

      await movingGesture.moveBy(const Offset(-20, 0));
      await tester.pump();

      await movingGesture.up();
      await tester.pump();
      await anchorGesture.up();
      await tester.pump();

      await tester.tapAt(anchor);
      await tester.pump(const Duration(seconds: 1));

      expect(currentTransform(), before);
    },
  );
}
