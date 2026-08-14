import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

class TerminalGrid extends Equatable {
  const TerminalGrid(this.cols, this.rows);

  final int cols;
  final int rows;

  @override
  List<Object?> get props => [cols, rows];
}

const String _probe = 'mmmmmmmmmm';

/// xterm.dart measures its own cell the same way (`char_metrics.dart`), but does
/// not export that helper, so the app measures with the identical probe.
Size measureCell(TextStyle style) {
  final painter = TextPainter(
    text: const TextSpan(text: _probe),
    textDirection: TextDirection.ltr,
  );
  painter.text = TextSpan(text: _probe, style: style);
  painter.layout();
  final size = Size(painter.width / _probe.length, painter.height);
  painter.dispose();
  return size;
}

TerminalGrid naturalFit(Size available, Size cell) {
  if (cell.width <= 0 || cell.height <= 0) return const TerminalGrid(1, 1);
  return TerminalGrid(
    max(1, (available.width / cell.width).floor()),
    max(1, (available.height / cell.height).floor()),
  );
}

Size gridSize(TerminalGrid grid, Size cell) =>
    Size(grid.cols * cell.width, grid.rows * cell.height);

double fitScale(TerminalGrid grid, Size cell, double availableWidth) {
  final natural = grid.cols * cell.width;
  if (natural <= 0 || availableWidth <= 0) return 1;
  return min(1, availableWidth / natural);
}
