import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_effect_container.dart';
import 'package:ios_liquid_glass/src/api/glass_material_context.dart';
import 'package:ios_liquid_glass/src/api/glass_shape.dart';
import 'package:ios_liquid_glass/src/liquid_glass.dart';

class GlassEffect extends StatefulWidget {
  const GlassEffect({
    super.key,
    this.glass = Glass.regular,
    this.shape = const GlassShape.capsule(),
    this.sideHint,
    required this.child,
  });

  static const double fallbackSide = 88;

  final Glass glass;
  final GlassShape shape;
  final double? sideHint;
  final Widget child;

  @override
  State<GlassEffect> createState() => _GlassEffectState();
}

class _GlassEffectState extends State<GlassEffect> {
  final _childKey = GlobalKey();
  double? _shorterSide;

  void _measured(Size size) {
    final side = size.shortestSide;
    if (_shorterSide != null && (side - _shorterSide!).abs() < 0.5) return;
    setState(() => _shorterSide = side);
  }

  @override
  Widget build(BuildContext context) {
    final child = _SizeReporter(
      key: _childKey,
      onSize: _measured,
      child: GlassEffectScope(glass: widget.glass, child: widget.child),
    );
    if (widget.glass.kind == GlassKind.identity) return child;
    return ListenableBuilder(
      listenable: GlassAccessibility.platform,
      builder: (context, _) {
        final material = resolveGlassMaterial(
          context,
          glass: widget.glass,
          shorterSide: _shorterSide ?? widget.sideHint ?? GlassEffect.fallbackSide,
        );
        final tint = widget.glass.tintColor;
        final container = GlassEffectContainer.glassOf(context);
        if (container != null && container.sameMaterial(widget.glass)) {
          return LiquidGlass.grouped(shape: widget.shape.liquidShape, shadows: material.shadows, child: child);
        }
        return LiquidGlass.withOwnLayer(
          settings: material.toSettings(tint: tint),
          shape: widget.shape.liquidShape,
          shadows: material.shadows,
          child: child,
        );
      },
    );
  }
}

class GlassEffectScope extends InheritedWidget {
  const GlassEffectScope({super.key, required this.glass, required super.child});

  final Glass glass;

  static Glass? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassEffectScope>()?.glass;

  @override
  bool updateShouldNotify(GlassEffectScope oldWidget) => oldWidget.glass != glass;
}

class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({super.key, required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (_reported == size) return;
    _reported = size;
    final measured = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(measured);
    });
  }
}
