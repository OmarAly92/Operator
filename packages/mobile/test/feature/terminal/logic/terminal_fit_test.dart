import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cell = Size(8, 16);

  group('naturalFit', () {
    test('floors the box into whole cells', () {
      expect(naturalFit(const Size(400, 800), cell), const TerminalGrid(50, 50));
      expect(naturalFit(const Size(403, 807), cell), const TerminalGrid(50, 50));
    });

    test('never proposes an empty grid', () {
      expect(naturalFit(const Size(2, 2), cell), const TerminalGrid(1, 1));
      expect(naturalFit(Size.zero, cell), const TerminalGrid(1, 1));
    });

    test('survives an unmeasured cell instead of dividing by zero', () {
      expect(naturalFit(const Size(400, 800), Size.zero), const TerminalGrid(1, 1));
    });
  });

  group('fitScale', () {
    test('is 1:1 when the daemon grid already fits the width', () {
      expect(fitScale(const TerminalGrid(40, 20), cell, 400), 1);
    });

    // The daemon's grid is authoritative: when a co-viewing desktop makes it
    // wider than the phone, the phone shrinks the whole grid rather than
    // re-fitting and mis-drawing a full-screen TUI.
    test('shrinks to width when the daemon grid is wider than the phone', () {
      expect(fitScale(const TerminalGrid(100, 20), cell, 400), 0.5);
    });

    test('never magnifies past 1:1 and never returns zero', () {
      expect(fitScale(const TerminalGrid(10, 20), cell, 400), 1);
      expect(fitScale(const TerminalGrid(0, 0), cell, 400), 1);
      expect(fitScale(const TerminalGrid(100, 20), cell, 0), 1);
    });
  });

  test('gridSize multiplies the grid out by the cell', () {
    expect(gridSize(const TerminalGrid(80, 24), cell), const Size(640, 384));
  });

  test('measureCell returns a positive monospace cell', () {
    final size = measureCell(const TextStyle(fontSize: 12, fontFamilyFallback: ['Menlo', 'monospace']));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
  });
}
