import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/colors/terminal_palette.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_zoom.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:xterm/xterm.dart' hide TerminalState;

const List<String> _monoFallback = ['Menlo', 'Courier New', 'monospace'];
const Duration _doubleTapWindow = Duration(milliseconds: 300);

class TerminalSurface extends StatefulWidget {
  const TerminalSurface({super.key});

  @override
  State<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends State<TerminalSurface> {
  final TerminalController _controller = TerminalController();
  final Map<int, Offset> _pointers = {};

  TerminalZoom _zoom = const TerminalZoom();
  TerminalZoom _pinchStart = const TerminalZoom();
  TerminalZoomBox _box = const TerminalZoomBox(content: Size.zero, view: Size.zero);
  double _minScale = 1;
  double _pinchDistance = 0;
  Offset _downAt = Offset.zero;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  bool _wasMultiTouch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _distance() {
    final points = _pointers.values.toList();
    return (points[0] - points[1]).distance;
  }

  Offset _focal() {
    final points = _pointers.values.toList();
    return (points[0] + points[1]) / 2;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _downAt = event.localPosition;
    if (_pointers.length == 2) {
      _pinchStart = _zoom;
      _pinchDistance = max(1, _distance());
      _wasMultiTouch = true;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length >= 2) {
      setState(() {
        _zoom = scaleAround(
          _pinchStart,
          scale: _pinchStart.scale * (_distance() / _pinchDistance),
          focal: _focal(),
          box: _box,
          minScale: _minScale,
        );
      });
      return;
    }

    // At the overview the grid already fits, so a one-finger drag belongs to the
    // terminal's own scrolling and this handler stays out of the way.
    if (!_zoom.isZoomed(_minScale)) return;
    setState(() => _zoom = panBy(_zoom, event.localDelta, _box, _minScale));
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_wasMultiTouch) {
      if (_pointers.isEmpty) _wasMultiTouch = false;
      return;
    }

    final moved = (event.localPosition - _downAt).distance;
    final now = DateTime.now();
    if (moved <= 10 && now.difference(_lastTap) < _doubleTapWindow) {
      _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
      setState(() {
        _zoom = toggleZoom(
          _zoom,
          focal: event.localPosition,
          box: _box,
          minScale: _minScale,
        );
      });
      return;
    }
    if (moved <= 10) _lastTap = now;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) _wasMultiTouch = false;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TerminalCubit>();
    final skin = context.skin;

    return BlocBuilder<TerminalCubit, TerminalState>(
      buildWhen: (previous, current) => current is TerminalReadyState,
      builder: (context, state) {
        final style = TerminalStyle(
          fontSize: cubit.fontSize,
          fontFamilyFallback: _monoFallback,
        );
        final cell = measureCell(style.toTextStyle());

        return LayoutBuilder(
          builder: (context, constraints) {
            final view = Size(constraints.maxWidth, constraints.maxHeight);
            final fit = naturalFit(view, cell);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) cubit.reportFit(fit);
            });

            final grid = cubit.grid ?? fit;
            final content = gridSize(grid, cell);
            final minScale = fitScale(grid, cell, view.width);
            if (minScale != _minScale) {
              _minScale = minScale;
              _zoom = TerminalZoom(scale: minScale);
            }
            _box = TerminalZoomBox(content: content, view: view);

            return ColoredBox(
              color: skin.bgBase,
              child: ClipRect(
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 0,
                    minHeight: 0,
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: Transform(
                      alignment: Alignment.topLeft,
                      transform: Matrix4.identity()
                        ..translateByDouble(_zoom.dx, _zoom.dy, 0.0, 1.0)
                        ..scaleByDouble(_zoom.scale, _zoom.scale, _zoom.scale, 1.0),
                      child: SizedBox(
                        width: content.width,
                        height: max(content.height, view.height),
                        child: TerminalView(
                          cubit.terminal,
                          controller: _controller,
                          theme: TerminalPalette.forBrightness(skin.themeMode == ThemeMode.light
                              ? Brightness.light
                              : Brightness.dark),
                          textStyle: style,
                          autoResize: false,
                          // The composer and key row own all input; the terminal
                          // must never raise a keyboard of its own.
                          readOnly: true,
                          hardwareKeyboardOnly: true,
                          // Without this, a wheel event the pane does not accept
                          // falls back to arrow keys, which walk the agent's
                          // prompt instead of scrolling. TerminalScrollRouter
                          // answers every wheel event, so the fallback is both
                          // unreachable and unwanted.
                          simulateScroll: false,
                          backgroundOpacity: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
