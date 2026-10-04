// ignore_for_file: avoid_setters_without_getters

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/glass_shadow.dart';
import 'package:ios_liquid_glass/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
import 'package:ios_liquid_glass/src/liquid_glass_render_scope.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
import 'package:meta/meta.dart';

/// A liquid glass shape.
///
/// To render liquid glass, you probably want to wrap this in a
/// [LiquidGlassLayer], where the glass effect will be rendered.
///
/// This can either create a single shape, or be blended together with other
/// shapes in a parent [LiquidGlassBlendGroup] by using the
/// [LiquidGlass.grouped] constructor.
///
/// If you only need a single shape with its own settings, you can also use the
/// [LiquidGlass.withOwnLayer] constructor, which will create its own
/// [LiquidGlassLayer] internally.
/// Be mindful that creating many individual layers can be expensive.
///
/// If you don't know whether a [LiquidGlassLayer] ancestor exists, use the
/// [LiquidGlass.auto] constructor. It will render on a parent layer if one is
/// found, or create its own layer otherwise.
///
/// See the [LiquidGlassLayer] documentation for more information.
class LiquidGlass extends StatelessWidget {
  /// Creates a new [LiquidGlass] with the given [child] and [shape].
  ///
  /// This will expect a parent [LiquidGlassLayer] to be present in the widget
  /// tree, where the liquid glass effect will be rendered.
  const LiquidGlass({
    required this.child,
    required this.shape,
    this.glassContainsChild = false,
    this.clipBehavior = Clip.hardEdge,
    this.shadows = const [],
    super.key,
  })  : grouped = false,
        blendGroupLink = null,
        ownLayerConfig = null,
        motion = null,
        visibility = null,
        settingsSource = null,
        shadowSource = null,
        _auto = false;

  /// Creates a new [LiquidGlass] that automatically renders on a parent
  /// [LiquidGlassLayer] if one exists, or creates its own layer if not.
  ///
  /// This is useful when you don't know whether a [LiquidGlassLayer] ancestor
  /// is present. If one is found in the widget tree, the glass will render on
  /// that layer. Otherwise, it will create its own layer with the given
  /// [settings] (or default settings if not provided).
  ///
  /// Note that creating many individual layers can be expensive, so prefer
  /// placing a [LiquidGlassLayer] ancestor in the tree when possible.
  const LiquidGlass.auto({
    required this.child,
    required this.shape,
    LiquidGlassSettings settings = const LiquidGlassSettings(),
    bool fake = false,
    super.key,
    this.glassContainsChild = false,
    this.clipBehavior = Clip.hardEdge,
    this.shadows = const [],
  })  : grouped = true,
        blendGroupLink = null,
        ownLayerConfig = (settings, fake),
        motion = null,
        visibility = null,
        settingsSource = null,
        shadowSource = null,
        _auto = true;

  /// Creates a new [LiquidGlass] that is part of a [LiquidGlassBlendGroup].
  ///
  /// This will expect a parent [LiquidGlassBlendGroup] to be present in the
  /// widget tree, as well as a parent [LiquidGlassLayer] above that, where the
  /// result will be rendered.
  const LiquidGlass.grouped({
    required this.child,
    required this.shape,
    super.key,
    this.glassContainsChild = false,
    this.clipBehavior = Clip.hardEdge,
    this.blendGroupLink,
    this.shadows = const [],
    @internal this.motion,
    @internal this.shadowSource,
  })  : ownLayerConfig = null,
        grouped = true,
        visibility = null,
        settingsSource = null,
        _auto = false;

  /// Creates a new [LiquidGlass] that creates its own [LiquidGlassLayer].
  ///
  /// While this might seem convenient, creating many individual layers can be
  /// expensive.
  ///
  /// You should prefer rendering multiple [LiquidGlass] shapes that share the
  /// same settings inside a single [LiquidGlassLayer] for better performance.
  const LiquidGlass.withOwnLayer({
    required this.child,
    required this.shape,
    LiquidGlassSettings settings = const LiquidGlassSettings(),
    bool fake = false,
    super.key,
    this.glassContainsChild = false,
    this.clipBehavior = Clip.hardEdge,
    this.blendGroupLink,
    this.shadows = const [],
    @internal this.motion,
    @internal this.visibility,
    @internal this.settingsSource,
    @internal this.shadowSource,
  })  : ownLayerConfig = (settings, fake),
        grouped = false,
        _auto = false;

  /// The child of this widget.
  ///
  /// You can choose whether this should be rendered "inside" of the glass, or
  /// on top using [glassContainsChild].
  final Widget child;

  /// {@template ios_liquid_glass.LiquidGlass.shape}
  /// The shape of this glass.
  ///
  /// This is the shape of the glass that will be rendered.
  /// {@endtemplate}
  final LiquidShape shape;

  /// Whether this glass should be rendered "inside" of the glass, or on top.
  ///
  /// If it is rendered inside, the color tint
  /// of the glass will affect the child, and it will also be refracted.
  ///
  /// Defaults to `false`.
  final bool glassContainsChild;

  /// The clip behavior of this glass.
  ///
  /// Defaults to [Clip.none], so [child] will not be clipped.
  final Clip clipBehavior;

  /// Whether this glass is part of a blend group.
  final bool grouped;

  /// The link to this glass's blend group if it is part of one.
  final GlassGroupLink? blendGroupLink;

  /// The settings for this glass if it is supposed to create its own layer.
  final (LiquidGlassSettings settings, bool fake)? ownLayerConfig;

  /// The list of shadows to paint.
  ///
  /// Only outer-equivalent shadows are supported; [BoxShadow.blurStyle] is
  /// ignored. When any shadow has a non-zero [BoxShadow.offset], the glass
  /// shape is cut out of the composed shadow stack so the shadow does not
  /// bleed through the translucent glass body.
  final List<BoxShadow> shadows;

  @internal
  final GlassShapeMotion? motion;

  @internal
  final Animation<double>? visibility;

  @internal
  final GlassMaterialSource? settingsSource;

  @internal
  final GlassMaterialSource? shadowSource;

  /// Whether this glass should automatically detect a parent layer.
  final bool _auto;

  @override
  Widget build(BuildContext context) {
    final hasLayer = LiquidGlassLayer.existsIn(context);
    // If we are in auto mode, check if a parent layer exists.
    // If it does, render on the parent layer instead of creating our own.
    if (_auto && hasLayer) {
      return _buildWithParentLayer(context);
    }

    // If we have our own layer config, we create our own layer.
    if (ownLayerConfig case (final settings, final fake)) {
      if (fake) {
        return FakeGlass(
          shape: shape,
          settings: settings,
          shadows: shadows,
          child: child,
        );
      }

      return LiquidGlassLayer(
        settings: settings,
        visibility: visibility,
        settingsSource: settingsSource,
        child: LiquidGlassBlendGroup(
          blend: 0,
          child: Builder(
            builder: _buildContent,
          ),
        ),
      );
    }

    final scopeSettings = LiquidGlassRenderScope.of(context);
    final fake = scopeSettings.useFake;

    if (fake) {
      return FakeGlass.inLayer(
        shape: shape,
        shadows: shadows,
        child: child,
      );
    }

    final blendGroupLink = grouped
        ? this.blendGroupLink ?? LiquidGlassBlendGroup.maybeOf(context)
        : null;

    if (blendGroupLink == null) {
      // For now we create our own blend group until we support non-blended
      // geometry generation
      return LiquidGlassBlendGroup(
        blend: 0,
        child: Builder(
          builder: (context) => _buildContent(
            context,
            LiquidGlassBlendGroup.of(context),
          ),
        ),
      );
    }

    return _buildContent(
      context,
      blendGroupLink,
    );
  }

  /// Builds the glass using an existing parent [LiquidGlassLayer].
  ///
  /// This is used by the [LiquidGlass.auto] constructor when a parent layer
  /// is detected.
  Widget _buildWithParentLayer(BuildContext context) {
    final scopeSettings = LiquidGlassRenderScope.of(context);
    final fake = scopeSettings.useFake;

    if (fake) {
      return FakeGlass.inLayer(
        shape: shape,
        shadows: shadows,
        child: child,
      );
    }

    final hasGroup = LiquidGlassBlendGroup.maybeOf(context) != null;

    if (hasGroup) {
      // If we are part of a blend group, we need to register with it.
      return _buildContent(
        context,
        LiquidGlassBlendGroup.of(context),
      );
    }

    // For non-grouped, non-own-layer glass: create a blend group wrapper
    return LiquidGlassBlendGroup(
      blend: 0,
      child: Builder(
        builder: (context) => _buildContent(
          context,
          LiquidGlassBlendGroup.of(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, [GlassGroupLink? blendGroupLink]) {
    final scope = LiquidGlassRenderScope.of(context);
    final settings = scope.settings;

    if (!ImageFilter.isShaderFilterSupported) {
      return FakeGlass(
        shape: shape,
        shadows: shadows,
        child: child,
      );
    }

    final content = Opacity(
      opacity: settings.visibility.clamp(0, 1),
      child: GlassGlowLayer(
        child: child,
      ),
    );
    final animated = scope.visibility;
    return GlassShadow(
      settings: settings,
      shape: shape,
      shadows: shadows,
      visibility: animated,
      motion: motion,
      shadowSource: shadowSource,
      child: _RawLiquidGlass(
        blendGroupLink: blendGroupLink ?? LiquidGlassBlendGroup.of(context),
        shape: shape,
        glassContainsChild: glassContainsChild,
        motion: motion,
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          clipBehavior: clipBehavior,
          child: animated == null ? content : FadeTransition(opacity: animated, child: content),
        ),
      ),
    );
  }
}

class _RawLiquidGlass extends SingleChildRenderObjectWidget {
  const _RawLiquidGlass({
    required super.child,
    required this.shape,
    required this.glassContainsChild,
    required this.blendGroupLink,
    this.motion,
  });

  final LiquidShape shape;

  final bool glassContainsChild;

  final GlassGroupLink? blendGroupLink;

  final GlassShapeMotion? motion;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlass(
      shape: shape,
      glassContainsChild: glassContainsChild,
      blendGroupLink: blendGroupLink,
    )..motion = motion;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlass renderObject,
  ) {
    renderObject
      ..shape = shape
      ..glassContainsChild = glassContainsChild
      ..blendGroupLink = blendGroupLink
      ..motion = motion;
  }
}

@internal
class RenderLiquidGlass extends RenderProxyBox
    with TransformTrackingRenderObjectMixin {
  RenderLiquidGlass({
    required LiquidShape shape,
    required bool glassContainsChild,
    required GlassGroupLink? blendGroupLink,
  })  : _shape = shape,
        _glassContainsChild = glassContainsChild,
        _blendGroupLink = blendGroupLink;

  late LiquidShape _shape;
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
    _updateBlendGroupLink();
  }

  bool _glassContainsChild = true;
  bool get glassContainsChild => _glassContainsChild;
  set glassContainsChild(bool value) {
    if (_glassContainsChild == value) return;
    _glassContainsChild = value;
    _updateBlendGroupLink();
  }

  GlassGroupLink? _blendGroupLink;
  set blendGroupLink(GlassGroupLink? value) {
    if (_blendGroupLink == value) return;
    _unregisterFromParentLayer();
    _blendGroupLink = value;
    _registerWithLink();
  }

  final transformLayerHandle = LayerHandle<TransformLayer>();

  GlassShapeMotion? _motion;
  GlassShapeMotion? get motion => _motion;
  set motion(GlassShapeMotion? value) {
    if (_motion == value) return;
    if (attached) _motion?.removeListener(_motionChanged);
    _motion = value;
    if (attached) _motion?.addListener(_motionChanged);
    _motionChanged();
  }

  void _motionChanged() {
    _blendGroupLink?.notifyShapeLayoutChanged(this);
    markNeedsPaint();
  }

  Rect get drawnRect => _motion?.resolve(this) ?? Offset.zero & size;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _motion?.addListener(_motionChanged);
    _registerWithLink();
  }

  @override
  void detach() {
    _motion?.removeListener(_motionChanged);
    _unregisterFromParentLayer();
    transformLayerHandle.layer = null;
    super.detach();
  }

  void _registerWithLink() {
    if (_blendGroupLink != null) {
      _blendGroupLink!.registerShape(
        this,
        _shape,
        glassContainsChild: _glassContainsChild,
      );
    }
  }

  void _unregisterFromParentLayer() {
    _blendGroupLink?.unregisterShape(this);
  }

  void _updateBlendGroupLink() {
    _blendGroupLink?.updateShape(
      this,
      _shape,
      glassContainsChild: _glassContainsChild,
    );
  }

  late Path _lastPath;

  @override
  void performLayout() {
    super.performLayout();
    // Notify parent layer when our layout changes
    _lastPath = shape.getOuterPath(Offset.zero & size);
    _blendGroupLink?.notifyShapeLayoutChanged(this);
  }

  @override
  void onTransformChanged() {
    _blendGroupLink?.notifyShapeLayoutChanged(this);
  }

  @override
  // ignore: must_call_super
  void paint(PaintingContext context, Offset offset) {
    setUpLayer(offset);
  }

  void paintFromLayer(
    PaintingContext context,
    Matrix4 transform,
    Offset offset,
  ) {
    if (attached) {
      final layout = Offset.zero & size;
      final shift = _motion == null ? Offset.zero : drawnRect.center - layout.center;
      transformLayerHandle.layer = context.pushTransform(
        needsCompositing,
        offset,
        shift == Offset.zero ? transform : (Matrix4.copy(transform)..translateByDouble(shift.dx, shift.dy, 0, 1)),
        super.paint,
        oldLayer: transformLayerHandle.layer,
      );
    }
  }

  Path getPath() {
    if (_motion == null) return _lastPath;
    return shape.getOuterPath(drawnRect);
  }
}
