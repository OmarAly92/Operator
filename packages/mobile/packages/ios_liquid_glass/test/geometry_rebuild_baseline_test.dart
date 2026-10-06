import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/internal/render_liquid_glass_geometry.dart';
import 'package:ios_liquid_glass/src/motion/glass_spring.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_layer.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';

class _Geometry extends RenderLiquidGlassGeometry {
  _Geometry({required super.geometryShader, required super.settings})
    : super(renderLink: GeometryRenderLink(), devicePixelRatio: 3);

  int uploads = 0;

  @override
  void updateShaderWithSettings(LiquidGlassSettings settings, double devicePixelRatio) => uploads++;

  @override
  void updateGeometryShaderShapes(List<ShapeGeometry> shapes) {}

  @override
  void paintShapeContents(RenderObject from, PaintingContext context, Offset offset, {required bool insideGlass}) {}

  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData() => (Rect.zero, const [], false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a geometry check against no baseline asks for a rebuild', () {
    const settings = LiquidGlassSettings(thickness: 20);
    expect(settings.requiresGeometryRebuild(null), isTrue);
    expect(settings.requiresGeometryRebuild(settings), isFalse);
  });

  test('re-attaching keeps the geometry baseline, so the next geometry change rebuilds and a non-geometry change does not', () async {
    final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
    const settings = LiquidGlassSettings(thickness: 20, blur: 4);
    final geometry = _Geometry(geometryShader: program.fragmentShader(), settings: settings)..attach(PipelineOwner());
    expect(geometry.settings, settings);
    geometry
      ..detach()
      ..attach(PipelineOwner())
      ..geometryState = LiquidGlassGeometryState.updated;
    geometry.settings = settings.copyWith(blur: 9);
    expect(geometry.geometryState, LiquidGlassGeometryState.updated);
    geometry
      ..detach()
      ..attach(PipelineOwner())
      ..geometryState = LiquidGlassGeometryState.updated;
    geometry.settings = settings.copyWith(blur: 9, thickness: 30);
    expect(geometry.geometryState, LiquidGlassGeometryState.needsUpdate);
  });

  test('a visibility that moved while detached reaches the settings and the geometry on attach', () async {
    final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
    final visibility = GlassMotionValue(1);
    const settings = LiquidGlassSettings(thickness: 20);
    final geometry = _Geometry(geometryShader: program.fragmentShader(), settings: settings)
      ..visibility = visibility
      ..attach(PipelineOwner());
    expect(geometry.settings.effectiveThickness, 20);
    geometry
      ..detach()
      ..geometryState = LiquidGlassGeometryState.updated;
    visibility.value = 0.5;
    final uploads = geometry.uploads;
    geometry.attach(PipelineOwner());
    expect(geometry.settings.effectiveThickness, 10);
    expect(geometry.geometryState, LiquidGlassGeometryState.needsUpdate);
    expect(geometry.uploads, greaterThan(uploads));
  });

  test('a layer whose visibility moved while detached uploads the new uniforms on attach', () async {
    final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
    final visibility = GlassMotionValue(1);
    final layer = RenderLiquidGlassLayer(
      renderShader: program.fragmentShader(),
      backdropKey: null,
      devicePixelRatio: 3,
      settings: const LiquidGlassSettings(thickness: 20),
      link: GeometryRenderLink(),
    )
      ..visibility = visibility
      ..attach(PipelineOwner());
    expect(layer.settings.effectiveThickness, 20);
    layer.detach();
    visibility.value = 0.25;
    layer.attach(PipelineOwner());
    expect(layer.settings.effectiveThickness, 5);
  });
}
