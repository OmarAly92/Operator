import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

class TerminalZoomBox extends Equatable {
  const TerminalZoomBox({required this.content, required this.view});

  final Size content;
  final Size view;

  @override
  List<Object?> get props => [content, view];
}

class TerminalZoom extends Equatable {
  const TerminalZoom({this.scale = 1, this.dx = 0, this.dy = 0});

  final double scale;
  final double dx;
  final double dy;

  bool isZoomed(double minScale) => scale > minScale + 0.001;

  @override
  List<Object?> get props => [scale, dx, dy];
}

TerminalZoom clampZoom(TerminalZoom zoom, TerminalZoomBox box, double minScale) {
  if (!zoom.isZoomed(minScale)) return TerminalZoom(scale: minScale);
  final minDx = min(0.0, box.view.width - box.content.width * zoom.scale);
  final minDy = min(0.0, box.view.height - box.content.height * zoom.scale);
  return TerminalZoom(
    scale: zoom.scale,
    dx: zoom.dx.clamp(minDx, 0.0),
    dy: zoom.dy.clamp(minDy, 0.0),
  );
}

TerminalZoom scaleAround(
  TerminalZoom zoom, {
  required double scale,
  required Offset focal,
  required TerminalZoomBox box,
  required double minScale,
}) {
  final next = scale.clamp(minScale, 1.0);
  final contentX = (focal.dx - zoom.dx) / zoom.scale;
  final contentY = (focal.dy - zoom.dy) / zoom.scale;
  return clampZoom(
    TerminalZoom(
      scale: next,
      dx: focal.dx - contentX * next,
      dy: focal.dy - contentY * next,
    ),
    box,
    minScale,
  );
}

TerminalZoom panBy(TerminalZoom zoom, Offset delta, TerminalZoomBox box, double minScale) {
  if (!zoom.isZoomed(minScale)) return zoom;
  return clampZoom(
    TerminalZoom(scale: zoom.scale, dx: zoom.dx + delta.dx, dy: zoom.dy + delta.dy),
    box,
    minScale,
  );
}

TerminalZoom toggleZoom(
  TerminalZoom zoom, {
  required Offset focal,
  required TerminalZoomBox box,
  required double minScale,
}) => zoom.isZoomed(minScale)
    ? TerminalZoom(scale: minScale)
    : scaleAround(zoom, scale: 1, focal: focal, box: box, minScale: minScale);
