import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
import 'package:meta/meta.dart';

/// Paints [BoxShadow]s for a [LiquidShape] using canvas primitives
/// (drawRRect, drawCircle, drawRSuperellipse, etc.) instead of drawPath.
///
/// This avoids the cost of rasterizing an arbitrary [Path] with a blur
/// [MaskFilter], which is significantly slower than the dedicated GPU-
/// accelerated primitives that Impeller/Skia provide for simple shapes.
@internal
class GlassShadow extends SingleChildRenderObjectWidget {
  /// Creates a new [GlassShadow] widget with the given [shape], [shadows], and
  /// optional [child].
  const GlassShadow({
    required this.shape,
    required this.shadows,
    required this.settings,
    this.visibility,
    this.motion,
    this.shadowSource,
    super.child,
    super.key,
  });

  final Animation<double>? visibility;

  final GlassShapeMotion? motion;

  final GlassMaterialSource? shadowSource;

  /// The shape to paint shadows for.
  final LiquidShape shape;

  final LiquidGlassSettings settings;

  /// The list of shadows to paint.
  ///
  /// Only outer-equivalent shadows are supported; [BoxShadow.blurStyle] is
  /// ignored. When any shadow has a non-zero [BoxShadow.offset], the glass
  /// shape is cut out of the composed shadow stack so the shadow does not
  /// bleed through the translucent glass body.
  final List<BoxShadow> shadows;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGlassShadow(
      shape: shape,
      shadows: shadows,
      visibility: settings.visibility,
    )
      ..animatedVisibility = visibility
      ..motion = motion
      ..shadowSource = shadowSource;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    // ignore: library_private_types_in_public_api
    _RenderGlassShadow renderObject,
  ) {
    renderObject
      ..shape = shape
      ..shadows = shadows
      ..visibility = settings.visibility
      ..animatedVisibility = visibility
      ..motion = motion
      ..shadowSource = shadowSource;
  }
}

class _RenderGlassShadow extends RenderProxyBox {
  _RenderGlassShadow({
    required LiquidShape shape,
    required List<BoxShadow> shadows,
    required double visibility,
  })  : _shape = shape,
        _shadows = shadows,
        _visibility = visibility.clamp(0, 1);

  LiquidShape get shape => _shape;
  LiquidShape _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  List<BoxShadow> get shadows => _shadowSource?.shadows ?? _shadows;
  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (_shadows == value) return;
    _shadows = value;
    markNeedsPaint();
  }

  double get visibility => _visibility * (_animatedVisibility?.value.clamp(0.0, 1.0) ?? 1);
  double _visibility = 1;
  set visibility(double value) {
    if (_visibility == value) return;
    _visibility = value.clamp(0, 1);
    markNeedsPaint();
  }

  Animation<double>? _animatedVisibility;
  set animatedVisibility(Animation<double>? value) {
    if (_animatedVisibility == value) return;
    if (attached) _animatedVisibility?.removeListener(markNeedsPaint);
    _animatedVisibility = value;
    if (attached) _animatedVisibility?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  GlassMaterialSource? _shadowSource;
  set shadowSource(GlassMaterialSource? value) {
    if (_shadowSource == value) return;
    if (attached) _shadowSource?.removeListener(markNeedsPaint);
    _shadowSource = value;
    if (attached) _shadowSource?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  GlassShapeMotion? _motion;
  set motion(GlassShapeMotion? value) {
    if (_motion == value) return;
    if (attached) _motion?.removeListener(markNeedsPaint);
    _motion = value;
    if (attached) _motion?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animatedVisibility?.addListener(markNeedsPaint);
    _motion?.addListener(markNeedsPaint);
    _shadowSource?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animatedVisibility?.removeListener(markNeedsPaint);
    _motion?.removeListener(markNeedsPaint);
    _shadowSource?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final union = _motion?.union(this);
    if (shadows.isNotEmpty && visibility > 0 && (union == null || union.leads)) {
      final rect = (union?.rect ?? _motion?.resolve(this) ?? Offset.zero & size).shift(offset);
      final shape = union?.shape ?? this.shape;
      final canvas = context.canvas;

      final needsCutout = shadows.any((s) => s.offset != Offset.zero);

      if (needsCutout) {
        var layerBounds = rect;
        for (final shadow in shadows) {
          layerBounds = layerBounds.expandToInclude(
            rect.shift(shadow.offset).inflate(
                  shadow.spreadRadius + (shadow.blurRadius * 2 + 2) * visibility,
                ),
          );
        }
        canvas
          ..save()
          ..clipPath(
            Path.combine(
              PathOperation.difference,
              Path()..addRect(layerBounds),
              _shapePath(shape, rect.deflate(.5)),
            ),
          );
      }

      for (final shadow in shadows) {
        final shadowRect =
            rect.shift(shadow.offset).inflate(shadow.spreadRadius);
        final paint = shadow
            .copyWith(
              blurRadius: shadow.blurRadius * visibility,
              blurStyle: needsCutout ? BlurStyle.normal : BlurStyle.outer,
              color: shadow.color.withValues(
                alpha: shadow.color.a * visibility,
              ),
            )
            .toPaint();

        _drawShape(canvas, shape, shadowRect, paint);
      }

      if (needsCutout) {
        canvas.restore();
      }
    }

    super.paint(context, offset);
  }

  Path _shapePath(LiquidShape shape, Rect rect) => switch (shape) {
        LiquidRoundedSuperellipse(:final borderRadius) => Path()
          ..addRSuperellipse(
            RSuperellipse.fromRectAndRadius(
              rect,
              Radius.circular(borderRadius),
            ),
          ),
        LiquidOval() => Path()..addOval(rect),
        LiquidRoundedRectangle(:final borderRadius) => Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              rect,
              Radius.circular(borderRadius),
            ),
          ),
      };

  void _drawShape(Canvas canvas, LiquidShape shape, Rect rect, Paint paint) {
    switch (shape) {
      case LiquidRoundedSuperellipse(:final borderRadius):
        canvas.drawRSuperellipse(
          RSuperellipse.fromRectAndRadius(
            rect,
            Radius.circular(borderRadius),
          ),
          paint,
        );
      case LiquidOval():
        canvas.drawOval(rect, paint);
      case LiquidRoundedRectangle(:final borderRadius):
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect,
            Radius.circular(borderRadius),
          ),
          paint,
        );
    }
  }
}
