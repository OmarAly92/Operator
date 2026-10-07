import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/internal/render_liquid_glass_geometry.dart';
import 'package:ios_liquid_glass/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:ios_liquid_glass/src/liquid_glass.dart';
import 'package:ios_liquid_glass/src/liquid_glass_render_scope.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

/// A widget that groups multiple liquid glass shapes for blending.
///
/// Any [LiquidGlass.grouped] widgets inside this group will blend together.
///
/// This widget will expect a parent [LiquidGlassLayer] to render the liquid
/// glass effect on.
class LiquidGlassBlendGroup extends StatefulWidget {
  /// Creates a new [LiquidGlassBlendGroup].
  const LiquidGlassBlendGroup({
    required this.child,
    this.blend = 20.0,
    this.blendMotion,
    super.key,
  });

  /// The amount of blending between shapes in this group.
  ///
  /// Roughly corresponds to distance of logical pixels at which shapes start to
  /// blend.
  final double blend;

  @internal
  final ValueListenable<double>? blendMotion;

  /// The child widget containing liquid glass shapes.
  final Widget child;

  /// Maximum number of shapes supported per layer.
  static const int maxShapesPerLayer = 16;

  /// Retrieves the [GlassGroupLink] from the nearest ancestor
  /// [LiquidGlassBlendGroup].
  ///
  /// Can be used by child shapes to register themselves for blending.
  static GlassGroupLink of(BuildContext context) {
    final inherited = _InheritedLiquidGlassBlendGroup.of(context);
    assert(inherited != null, 'No LiquidGlassBlendGroup found in context');
    return inherited!.link;
  }

  /// Retrieves the [GlassGroupLink] from the nearest ancestor
  /// [LiquidGlassBlendGroup], or null if none is found.
  static GlassGroupLink? maybeOf(BuildContext context) {
    final inherited = _InheritedLiquidGlassBlendGroup.of(context);
    return inherited?.link;
  }

  @override
  State<LiquidGlassBlendGroup> createState() => _LiquidGlassBlendGroupState();
}

class _LiquidGlassBlendGroupState extends State<LiquidGlassBlendGroup> {
  late final GlassGroupLink _geometryLink = GlassGroupLink();

  @override
  void dispose() {
    _geometryLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useFake = LiquidGlassRenderScope.of(context).useFake;

    if (useFake) {
      return _InheritedLiquidGlassBlendGroup(
        link: _geometryLink,
        child: widget.child,
      );
    }

    return _InheritedLiquidGlassBlendGroup(
      link: _geometryLink,
      child: ShaderBuilder(
        (context, shader, child) => _RawLiquidGlassBlendGroup(
          blend: widget.blend,
          blendMotion: widget.blendMotion,
          shader: shader,
          link: _geometryLink,
          renderLink: InheritedGeometryRenderLink.of(context)!,
          settings: LiquidGlassRenderScope.of(context).settings,
          visibility: LiquidGlassRenderScope.of(context).visibility,
          settingsSource: LiquidGlassRenderScope.of(context).settingsSource,
          child: child,
        ),
        assetKey: ShaderKeys.blendedGeometry,
        child: widget.child,
      ),
    );
  }
}

class _InheritedLiquidGlassBlendGroup extends InheritedWidget {
  const _InheritedLiquidGlassBlendGroup({
    required this.link,
    required super.child,
  });

  final GlassGroupLink link;

  static _InheritedLiquidGlassBlendGroup? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_InheritedLiquidGlassBlendGroup>();
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return oldWidget is! _InheritedLiquidGlassBlendGroup ||
        oldWidget.link != link;
  }
}

class _RawLiquidGlassBlendGroup extends SingleChildRenderObjectWidget {
  const _RawLiquidGlassBlendGroup({
    required this.blend,
    required this.shader,
    required this.renderLink,
    required this.link,
    required this.settings,
    this.blendMotion,
    this.visibility,
    this.settingsSource,
    super.child,
  });

  final double blend;
  final ValueListenable<double>? blendMotion;
  final FragmentShader shader;
  final GeometryRenderLink renderLink;
  final GlassGroupLink link;
  final LiquidGlassSettings settings;
  final Animation<double>? visibility;
  final GlassMaterialSource? settingsSource;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassBlendGroup(
      renderLink: renderLink,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      geometryShader: shader,
      settings: settings,
      link: link,
      blend: blendMotion?.value ?? blend,
    )
      ..blendMotion = blendMotion
      ..visibility = visibility
      ..settingsSource = settingsSource;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassBlendGroup renderObject,
  ) {
    renderObject
      ..blend = blendMotion?.value ?? blend
      ..blendMotion = blendMotion
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..settings = settings
      ..visibility = visibility
      ..settingsSource = settingsSource
      ..link = link;
  }
}

@visibleForTesting
@internal
class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry
    with TransformTrackingRenderObjectMixin {
  RenderLiquidGlassBlendGroup({
    required super.renderLink,
    required super.devicePixelRatio,
    required super.geometryShader,
    required super.settings,
    required GlassGroupLink link,
    required double blend,
  })  : _link = link,
        _blend = blend {
    link.addListener(_onLinkUpdate);
  }

  GlassGroupLink _link;

  /// The link that provides shape information to this geometry.
  GlassGroupLink get link => _link;

  set link(GlassGroupLink value) {
    if (_link == value) return;
    _link.removeListener(_onLinkUpdate);
    _link = value;
    value.addListener(_onLinkUpdate);
    markNeedsPaint();
  }

  double _blend = 0;
  double get blend => _blend;
  set blend(double value) {
    if (_blend == value) return;
    _blend = value;
    updateShaderWithSettings(settings, devicePixelRatio);
    markGeometryNeedsUpdate(force: true);
    markNeedsPaint();
  }

  ValueListenable<double>? _blendMotion;
  set blendMotion(ValueListenable<double>? value) {
    if (_blendMotion == value) return;
    if (attached) _blendMotion?.removeListener(_followBlend);
    _blendMotion = value;
    if (attached) value?.addListener(_followBlend);
    _followBlend();
  }

  void _followBlend() {
    final motion = _blendMotion;
    if (motion != null) blend = motion.value;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _blendMotion?.addListener(_followBlend);
    _followBlend();
  }

  @override
  void detach() {
    _blendMotion?.removeListener(_followBlend);
    super.detach();
  }

  void _onLinkUpdate() {
    // One of the shapes might have changed.
    markGeometryNeedsUpdate();
    markNeedsPaint();
  }

  @override
  void onTransformChanged() {
    markGeometryNeedsUpdate();
    markNeedsPaint();
  }

  @override
  void updateShaderWithSettings(
    LiquidGlassSettings settings,
    double devicePixelRatio,
  ) {
    geometryShader.setFloatUniforms(initialIndex: 2, (value) {
      value.setFloats([
        settings.refractiveIndex,
        settings.outlineWidth * devicePixelRatio,
        settings.effectiveThickness * devicePixelRatio,
        blend * devicePixelRatio,
      ]);
    });
    geometryShader.setFloatUniforms(initialIndex: 7 + LiquidGlassBlendGroup.maxShapesPerLayer * 6, (value) {
      value.setFloat(settings.thickness * devicePixelRatio);
    });
  }

  @override
  void updateGeometryShaderShapes(
    List<ShapeGeometry> shapes,
  ) {
    if (shapes.length > LiquidGlassBlendGroup.maxShapesPerLayer) {
      throw UnsupportedError(
        'Only ${LiquidGlassBlendGroup.maxShapesPerLayer} shapes are supported '
        'at the moment!',
      );
    }

    geometryShader.setFloatUniforms(initialIndex: 6, (value) {
      value.setFloat(shapes.length.toDouble());
      for (final shape in shapes) {
        final center = shape.shapeBounds.center;
        final size = shape.shapeBounds.size;
        value
          ..setFloat(shape.rawShapeType.shaderIndex)
          ..setFloat((center.dx) * devicePixelRatio)
          ..setFloat((center.dy) * devicePixelRatio)
          ..setFloat(size.width * devicePixelRatio)
          ..setFloat(size.height * devicePixelRatio)
          ..setFloat(shape.rawCornerRadius * devicePixelRatio);
      }
    });
  }

  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData() {
    final candidates = <(ShapeGeometry, bool)>[];
    final cachedShapes = geometry?.shapes ?? [];

    var anyShapeChangedInLayer = false;

    Rect? layerBounds;

    for (final MapEntry(
          key: renderObject,
          value: (shape, glassContainsChild),
        ) in link.shapeEntries) {
      if (!renderObject.attached || !renderObject.hasSize) continue;

      try {
        final union = renderObject.unionOutline;
        if (union != null && !union.leads) continue;
        candidates.add((
          _computeShapeInfo(
            renderObject,
            union?.shape ?? shape,
            glassContainsChild,
            union?.rect ?? renderObject.drawnRect,
          ),
          renderObject.motion?.isTransient ?? false,
        ));
      } catch (e) {
        debugPrint('Failed to compute shape info: $e');
      }
    }

    var excess = candidates.length - LiquidGlassBlendGroup.maxShapesPerLayer;
    for (var i = candidates.length - 1; i >= 0 && excess > 0; i--) {
      if (!candidates[i].$2) continue;
      candidates.removeAt(i);
      excess--;
    }

    final shapes = [for (final (shapeData, _) in candidates) shapeData];

    for (final (index, shapeData) in shapes.indexed) {
      layerBounds = layerBounds?.expandToInclude(shapeData.shapeBounds) ??
          shapeData.shapeBounds;

      final existingShape =
          cachedShapes.length > index ? cachedShapes[index] : null;

      if (existingShape == null) {
        anyShapeChangedInLayer = true;
      } else if (existingShape.shapeBounds != shapeData.shapeBounds ||
          existingShape.shape != shapeData.shape) {
        anyShapeChangedInLayer = true;
      }
    }

    if (cachedShapes.length != shapes.length) anyShapeChangedInLayer = true;

    return (
      (layerBounds ?? Rect.zero).inflate(blend * .25 + settings.outlineWidth + 1),
      shapes,
      anyShapeChangedInLayer,
    );
  }

  @override
  void paintShapeContents(
    RenderObject from,
    PaintingContext context,
    Offset offset, {
    required bool insideGlass,
  }) {
    for (final shapeEntry in link.shapeEntries) {
      final renderObject = shapeEntry.key;
      if (!renderObject.attached ||
          renderObject.glassContainsChild != insideGlass) {
        continue;
      }

      renderObject.paintFromLayer(
        context,
        renderObject.getTransformTo(from),
        offset,
      );
    }
  }

  ShapeGeometry _computeShapeInfo(
    RenderLiquidGlass renderObject,
    LiquidShape shape,
    bool glassContainsChild,
    Rect drawnRect,
  ) {
    if (!hasSize) {
      throw StateError(
        'Cannot compute shape info for $renderObject because '
        '$this LiquidGlassGeometry has no size yet.',
      );
    }

    if (!renderObject.hasSize) {
      throw StateError(
        'Cannot compute shape info for LiquidGlass $renderObject because it '
        'has no size yet.',
      );
    }

    // We remember the shapes transform to this blend group.
    final transformToGeometry = renderObject.getTransformTo(this);

    final blendGroupRect = MatrixUtils.transformRect(
      transformToGeometry,
      drawnRect,
    );

    return ShapeGeometry(
      renderObject: renderObject,
      shape: shape,
      glassContainsChild: glassContainsChild,
      shapeBounds: blendGroupRect,
      shapeToGeometry: transformToGeometry,
    );
  }
}

/// A link that connects liquid glass shapes to their parent
/// [LiquidGlassBlendGroup] for efficient communication of position, size, and
/// transform changes.
@internal
class GlassGroupLink with ChangeNotifier {
  /// Creates a new [GlassGroupLink].
  GlassGroupLink();

  /// Information about a shape registered with this link.
  final Map<RenderLiquidGlass, (LiquidShape shape, bool glassContainsChild)>
      _shapes = {};

  List<
      MapEntry<RenderLiquidGlass,
          (LiquidShape shape, bool glassContainsChild)>> get shapeEntries =>
      _shapes.entries.toList();

  /// Check if any shapes are registered.
  bool get hasShapes => _shapes.isNotEmpty;

  /// Register a shape with this link.
  void registerShape(
    RenderLiquidGlass renderObject,
    LiquidShape shape, {
    required bool glassContainsChild,
  }) {
    _shapes[renderObject] = (shape, glassContainsChild);
    notifyListeners();
  }

  /// Unregister a shape from this link.
  void unregisterShape(RenderLiquidGlass renderObject) {
    _shapes.remove(renderObject);
    notifyListeners();
  }

  /// Update the shape properties for a registered render object.
  void updateShape(
    RenderLiquidGlass renderObject,
    LiquidShape shape, {
    required bool glassContainsChild,
  }) {
    _shapes[renderObject] = (shape, glassContainsChild);
    notifyListeners();
  }

  /// Notify that a shape's layout has changed.
  void notifyShapeLayoutChanged(RenderObject renderObject) {
    if (_shapes.containsKey(renderObject)) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _shapes.clear();
    super.dispose();
  }
}
