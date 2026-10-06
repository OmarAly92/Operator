import 'package:flutter/widgets.dart';

class GlassLabMarker extends StatelessWidget {
  const GlassLabMarker(this.id, {super.key, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(identifier: id, label: id, container: true, child: child);
}

class GlassLabReady extends StatelessWidget {
  const GlassLabReady({super.key});

  @override
  Widget build(BuildContext context) => const GlassLabMarker('scene.ready', child: SizedBox(width: 1, height: 1));
}

class GlassLabTouchMarker extends StatefulWidget {
  const GlassLabTouchMarker({super.key, required this.child});

  static const Rect rect = Rect.fromLTWH(16, 662, 18, 18);
  static const Duration restDelay = Duration(milliseconds: 250);
  static const Color idle = Color(0xFF000000);
  static const Color down = Color(0xFFFF0000);
  static const Color moved = Color(0xFF00FF00);
  static const Color up = Color(0xFF0000FF);

  final Widget child;

  @override
  State<GlassLabTouchMarker> createState() => _GlassLabTouchMarkerState();
}

class _GlassLabTouchMarkerState extends State<GlassLabTouchMarker> {
  Color _color = GlassLabTouchMarker.idle;
  int _generation = 0;

  void _show(Color color) {
    final generation = ++_generation;
    setState(() => _color = color);
    if (color != GlassLabTouchMarker.up) return;
    Future<void>.delayed(GlassLabTouchMarker.restDelay, () {
      if (mounted && _generation == generation) setState(() => _color = GlassLabTouchMarker.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _show(GlassLabTouchMarker.down),
      onPointerMove: (_) => _show(GlassLabTouchMarker.moved),
      onPointerUp: (_) => _show(GlassLabTouchMarker.up),
      onPointerCancel: (_) => _show(GlassLabTouchMarker.up),
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          Positioned.fromRect(
            rect: GlassLabTouchMarker.rect,
            child: IgnorePointer(child: ColoredBox(key: const ValueKey('touch.marker'), color: _color)),
          ),
        ],
      ),
    );
  }
}
