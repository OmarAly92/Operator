import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_material_source.dart';
import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
import 'package:ios_liquid_glass/src/motion/glass_spring.dart';
import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_layer.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';

class _Motion extends ChangeNotifier implements GlassShapeMotion {
  Rect drawn = const Rect.fromLTWH(-10, -5, 120, 50);

  @override
  Rect resolve(RenderBox shape) => drawn;

  void move(Rect rect) {
    drawn = rect;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a layer reads an animated visibility without being rebuilt', () async {
    final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
    final visibility = GlassMotionValue(1);
    const settings = LiquidGlassSettings(thickness: 20, blur: 6, specular: 0.4);
    final layer = RenderLiquidGlassLayer(
      renderShader: program.fragmentShader(),
      backdropKey: null,
      devicePixelRatio: 3,
      settings: settings,
      link: GeometryRenderLink(),
    )
      ..visibility = visibility
      ..attach(PipelineOwner());
    expect(layer.settings, settings);
    visibility.value = 0.25;
    expect(layer.settings.effectiveThickness, 5);
    expect(layer.settings.effectiveBlur, closeTo(6 * math.pow(0.25, ios27BlurRampExponent), 1e-9));
    expect(layer.settings.thickness, 20);
    layer.settings = settings.copyWith(blur: 8);
    expect(layer.settings.effectiveBlur, closeTo(8 * math.pow(0.25, ios27BlurRampExponent), 1e-9));
    visibility.value = 1.04;
    expect(layer.settings.effectiveThickness, closeTo(20.8, 1e-9));
    visibility.value = -0.1;
    expect(layer.settings.effectiveThickness, 0);
    expect(layer.settings.effectiveBlur, 0);
    layer.visibility = null;
    expect(layer.settings.effectiveBlur, 8);
  });

  test('settings at a visibility scale it and ramp the blur, the one formula the lab scans with', () {
    const settings = LiquidGlassSettings(thickness: 20, blur: 8);
    final half = settings.atVisibility(0.5, blurRampExponent: 3);
    expect(half.visibility, 0.5);
    expect(half.blur, closeTo(2, 1e-12));
    expect(half.effectiveBlur, closeTo(1, 1e-12));
    expect(settings.atVisibility(0.5).blur, closeTo(8 * math.pow(0.5, ios27BlurRampExponent - 1), 1e-12));
    expect(settings.atVisibility(0).blur, 0);
    expect(settings.atVisibility(-0.2).visibility, 0);
    expect(settings.atVisibility(1), settings);
  });

  test('a layer follows a material source without being rebuilt, and visibility still applies on top', () async {
    final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
    final source = GlassMaterialSource(resolve: (side) => GlassMaterial({'thickness': side / 4, 'frost': 2}), side: 44);
    final visibility = GlassMotionValue(1);
    final layer = RenderLiquidGlassLayer(
      renderShader: program.fragmentShader(),
      backdropKey: null,
      devicePixelRatio: 3,
      settings: const LiquidGlassSettings(thickness: 99),
      link: GeometryRenderLink(),
    )
      ..settingsSource = source
      ..visibility = visibility
      ..attach(PipelineOwner());
    expect(layer.settings.thickness, 11);
    source.resize(88);
    expect(layer.settings.thickness, 22);
    source.resize(88.3);
    expect(layer.settings.thickness, 22);
    source.resize(88.3, exact: true);
    expect(layer.settings.thickness, closeTo(22.075, 1e-9));
    visibility.value = 0.5;
    expect(layer.settings.effectiveThickness, closeTo(11.0375, 1e-9));
    layer.settingsSource = null;
    expect(layer.settings.thickness, 99);
  });

  test('glass paints its geometry and its path at the drawn rect, and follows it', () {
    final motion = _Motion();
    final glass = RenderLiquidGlass(shape: const LiquidRoundedRectangle(borderRadius: 10), glassContainsChild: false, blendGroupLink: null)
      ..motion = motion
      ..layout(BoxConstraints.tight(const Size(100, 40)));
    expect(glass.drawnRect, const Rect.fromLTWH(-10, -5, 120, 50));
    expect(glass.getPath().getBounds(), const Rect.fromLTWH(-10, -5, 120, 50));
    motion.move(const Rect.fromLTWH(0, 0, 60, 40));
    expect(glass.getPath().getBounds(), const Rect.fromLTWH(0, 0, 60, 40));
    glass.motion = null;
    expect(glass.drawnRect, const Rect.fromLTWH(0, 0, 100, 40));
  });
}
