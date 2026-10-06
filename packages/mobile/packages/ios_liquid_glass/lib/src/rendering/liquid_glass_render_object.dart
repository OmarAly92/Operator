import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/internal/render_liquid_glass_geometry.dart';
import 'package:ios_liquid_glass/src/internal/snap_rect_to_pixels.dart';
import 'package:ios_liquid_glass/src/logging.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
import 'package:meta/meta.dart';

/// A render object that can assemble [RenderLiquidGlassGeometry] shapes and
/// render them to the screen with the liquid glass effect.
@internal
abstract class LiquidGlassRenderObject extends RenderProxyBox {
  LiquidGlassRenderObject({
    required GeometryRenderLink link,
    required this.renderShader,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
    required BackdropKey? backdropKey,
  })  : _settings = settings,
        _devicePixelRatio = devicePixelRatio,
        _backdropKey = backdropKey,
        _link = link {
    _updateShaderSettings();
  }

  static final logger = Logger(LgrLogNames.render);

  final FragmentShader renderShader;

  /// The size that the geometry texture should have.
  Size get desiredMatteSize;

  Matrix4 get matteTransform;

  late GeometryRenderLink _link;
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (_link == value) return;
    markNeedsPaint();
    _link = value;
  }

  LiquidGlassSettings? _settings;
  LiquidGlassSettings? _effective;
  LiquidGlassSettings get settings => _effective ??= _resolveVisibility(_settingsSource?.settings ?? _settings!, _visibility);
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    _visibilityChanged();
  }

  Animation<double>? _visibility;
  Animation<double>? get visibility => _visibility;
  set visibility(Animation<double>? value) {
    if (_visibility == value) return;
    if (attached) _visibility?.removeListener(_visibilityChanged);
    _visibility = value;
    if (attached) _visibility?.addListener(_visibilityChanged);
    _visibilityChanged();
  }

  GlassMaterialSource? _settingsSource;
  set settingsSource(GlassMaterialSource? value) {
    if (_settingsSource == value) return;
    if (attached) _settingsSource?.removeListener(_visibilityChanged);
    _settingsSource = value;
    if (attached) _settingsSource?.addListener(_visibilityChanged);
    _visibilityChanged();
  }

  void _visibilityChanged() {
    _effective = null;
    _updateShaderSettings();
    markNeedsPaint();
  }

  BackdropKey? _backdropKey;
  BackdropKey? get backdropKey => _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    _updateShaderSettings();
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _geometryImage != null;

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;

  /// The bounding box of the geometry matte in the coordinate space of the
  /// shader
  Rect _geometryMatteBounds = Rect.zero;

  @override
  @mustCallSuper
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _visibility?.addListener(_visibilityChanged);
    _settingsSource?.addListener(_visibilityChanged);
    _visibilityChanged();
  }

  @override
  @mustCallSuper
  void detach() {
    _visibility?.removeListener(_visibilityChanged);
    _settingsSource?.removeListener(_visibilityChanged);
    super.detach();
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    needsGeometryUpdate = true;
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  void _updateShaderSettings() {
    renderShader.setFloatUniforms(initialIndex: 6, (value) {
      value
        ..setColor(settings.effectiveGlassColor)
        ..setFloats([
          settings.effectiveThickness * devicePixelRatio,
          settings.effectiveChromaticAberration,
          settings.effectiveSaturation,
          settings.thickness * devicePixelRatio,
          settings.effectiveToneBlack,
          settings.effectiveToneMid,
          settings.effectiveToneWhite,
          0,
          settings.tintBlack,
          settings.tintWhite,
          settings.effectiveSheen,
          settings.sheenWidth * devicePixelRatio,
          settings.effectiveOutline,
          settings.effectiveOutlineTop,
          settings.outlineWidth * devicePixelRatio,
          0,
          settings.effectiveSpecular,
          settings.specularWidth * devicePixelRatio,
          settings.specularPower,
          settings.specularFill,
        ])
        ..setOffset(
          Offset(
            cos(settings.lightAngle),
            sin(settings.lightAngle),
          ),
        );
    });
  }

  ui.Rect _paintBounds = ui.Rect.zero;

  @override
  ui.Rect get paintBounds => _paintBounds;

  // MARK: Painting

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    logger.finest('$hashCode Painting liquid glass with '
        '${link._shapeGeometries.length} shapes.');

    final shapesWithGeometry =
        <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];

    Rect? boundingBox;

    for (final geometryRo in link.shapes) {
      final geometry = geometryRo.maybeRebuildGeometry();

      if (geometry == null) continue;

      final transform = geometryRo.getTransformTo(this);
      shapesWithGeometry.add((geometryRo, geometry, transform));

      final geoBounds = MatrixUtils.transformRect(
        transform,
        geometry.bounds,
      );
      boundingBox = boundingBox == null
          ? geoBounds
          : boundingBox.expandToInclude(geoBounds);
    }

    if (boundingBox == null) {
      _clearGeometryImage();

      super.paint(context, offset);
      return;
    }

    _paintBounds = boundingBox;

    if (settings.effectiveThickness <= 0) {
      _clearGeometryImage();
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: false,
      );
      super.paint(context, offset);
      return;
    }

    if (needsGeometryUpdate || _geometryImage == null || link._dirty) {
      link.updateAllGeometries();
      _clearGeometryImage();
      link._dirty = false;

      needsGeometryUpdate = false;

      final (image, matteBounds) = _buildGeometryImage(
        shapesWithGeometry,
        boundingBox,
      );

      _geometryImage = image;
      _geometryMatteBounds = matteBounds;
    }

    if (debugPaintLiquidGlassGeometry) {
      _debugPaintGeometry(context, offset);
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: false,
      );
    } else {
      if (_geometryImage case final geometryImage?) {
        renderShader
          ..setFloatUniforms(initialIndex: 2, (value) {
            value
              ..setOffset(_geometryMatteBounds.topLeft * devicePixelRatio)
              ..setSize(_geometryMatteBounds.size * devicePixelRatio);
          })
          ..setImageSampler(1, geometryImage);
        paintLiquidGlass(
          context,
          offset,
          shapesWithGeometry,
          _paintBounds,
        );
      }
    }

    super.paint(context, offset);
  }

  void _clearGeometryImage() {
    _geometryImage?.dispose();
    _geometryImage = null;
  }

  /// Subclasses implement the actual glass rendering
  /// (e.g., with backdrop filters)
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  );

  @protected
  void paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes, {
    required bool insideGlass,
  }) {
    for (final (geometryRenderObject, _, _) in shapes) {
      geometryRenderObject.paintShapeContents(
        this,
        context,
        offset,
        insideGlass: insideGlass,
      );
    }
  }

  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (_geometryImage case final geometryImage?) {
      final backToThis = Matrix4.inverted(matteTransform).storage;
      final bounds = MatrixUtils.transformRect(
        matteTransform,
        paintBounds,
      ).snapToPixels(devicePixelRatio);
      context.canvas
        ..save()
        ..transform(backToThis)
        ..translate(
          bounds.left,
          bounds.top,
        )
        ..scale(1 / devicePixelRatio)
        ..drawImage(
          geometryImage,
          offset * devicePixelRatio,
          Paint()..blendMode = BlendMode.src,
        )
        ..restore();
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    _clearGeometryImage();
    super.dispose();
  }

  // MARK: Geometry

  @protected
  bool needsGeometryUpdate = true;

  (ui.Image, Rect) _buildGeometryImage(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
    Rect bounds,
  ) {
    final boundsInMatteSpace = MatrixUtils.transformRect(
      matteTransform,
      bounds,
    ).snapToPixels(devicePixelRatio);

    final size = boundsInMatteSpace.size * devicePixelRatio;

    final buffer = StringBuffer('$hashCode Built geometry image with '
        '${geometries.length} shapes at size ${size.width}x${size.height}:\n');

    final recorder = ui.PictureRecorder();

    final canvas = Canvas(recorder);

    final toMatte = matteTransform;

    for (final (_, geometry, transform) in geometries) {
      if (geometry is RenderedGeometryCache) {
        final translation = pixelTranslation(
          Matrix4.diagonal3Values(devicePixelRatio, devicePixelRatio, 1)
            ..translateByDouble(-boundsInMatteSpace.left, -boundsInMatteSpace.top, 0, 1)
            ..multiply(toMatte)
            ..multiply(transform)
            ..scaleByDouble(1 / devicePixelRatio, 1 / devicePixelRatio, 1, 1)
            ..translateByDouble(geometry.matteBounds.left, geometry.matteBounds.top, 0, 1),
        );
        if (translation != null) {
          buffer.writeln('\t- Rendered @ ${geometry.bounds}, at $translation');
          drawMatteAt(canvas, geometry, translation);
          continue;
        }
      }

      canvas
        ..save()
        ..scale(devicePixelRatio)
        ..translate(
          -boundsInMatteSpace.left,
          -boundsInMatteSpace.top,
        )
        ..transform(toMatte.storage)
        ..transform(transform.storage)
        ..scale(1 / devicePixelRatio)
        ..translate(
          geometry.matteBounds.topLeft.dx,
          geometry.matteBounds.topLeft.dy,
        );

      switch (geometry) {
        case UnrenderedGeometryCache(matte: final picture):
          buffer.writeln(
            '\t- Unrendered @ ${geometry.bounds}',
          );
          canvas.drawPicture(picture);
        case RenderedGeometryCache():
          buffer.writeln(
            '\t- Rendered @ ${geometry.bounds}',
          );
          canvas.drawImage(geometry.matteAt(Offset.zero), Offset.zero, Paint());
      }

      canvas.restore();
    }

    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      size.width.toPixelCount(),
      size.height.toPixelCount(),
    );

    logger.fine(buffer.toString());
    picture.dispose();
    return (image, boundsInMatteSpace);
  }
}

LiquidGlassSettings _resolveVisibility(LiquidGlassSettings settings, Animation<double>? visibility) =>
    visibility == null ? settings : settings.atVisibility(visibility.value);

@internal
LiquidGlassSettings resolveVisibility(LiquidGlassSettings settings, Animation<double>? visibility) =>
    _resolveVisibility(settings, visibility);

@internal
class GeometryRenderLink {
  final List<RenderLiquidGlassGeometry> _shapeGeometries = [];

  UnmodifiableListView<RenderLiquidGlassGeometry> get shapes =>
      UnmodifiableListView(_shapeGeometries);

  bool _dirty = false;

  void updateAllGeometries() {
    for (final renderObject in _shapeGeometries) {
      renderObject.maybeRebuildGeometry();
    }
  }

  void registerGeometry(
    RenderLiquidGlassGeometry renderObject,
  ) {
    _dirty = true;
    _shapeGeometries.add(renderObject);
  }

  void markRebuilt(RenderLiquidGlassGeometry renderObject) {
    _dirty = true;
  }

  void unregisterGeometry(RenderLiquidGlassGeometry renderObject) {
    _shapeGeometries.remove(renderObject);
  }

  void dispose() {
    _shapeGeometries.clear();
  }
}

@internal
class InheritedGeometryRenderLink extends InheritedWidget {
  const InheritedGeometryRenderLink({
    required this.link,
    required super.child,
    super.key,
  });

  final GeometryRenderLink link;

  static GeometryRenderLink? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedGeometryRenderLink>()
        ?.link;
  }

  @override
  bool updateShouldNotify(covariant InheritedGeometryRenderLink oldWidget) {
    return oldWidget.link != link;
  }
}
