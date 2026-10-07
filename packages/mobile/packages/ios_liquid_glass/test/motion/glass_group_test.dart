import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/internal/render_liquid_glass_geometry.dart';
import 'package:ios_liquid_glass/src/liquid_glass.dart';
import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';

const LiquidShape _capsule = LiquidRoundedRectangle(borderRadius: 999);

class _Motion extends ChangeNotifier implements GlassShapeMotion {
  _Motion({this.transient = false});

  final bool transient;
  bool moved = false;

  @override
  Rect resolve(RenderBox shape) => Offset.zero & shape.size;

  @override
  bool get isTransient => transient;

  @override
  bool syncMoved() {
    final result = moved;
    moved = false;
    return result;
  }

  @override
  GlassUnionOutline? union(RenderBox shape) => null;
}

class _Group extends RenderLiquidGlassBlendGroup {
  _Group({required super.geometryShader, required super.link})
    : super(renderLink: GeometryRenderLink(), devicePixelRatio: 3, settings: const LiquidGlassSettings(thickness: 20), blend: 8);

  @override
  void updateShaderWithSettings(LiquidGlassSettings settings, double devicePixelRatio) {}

  @override
  void updateGeometryShaderShapes(List<ShapeGeometry> shapes) {}

  LiquidGlassGeometryState get state => geometryState;

  void settle() => geometryState = LiquidGlassGeometryState.updated;
}

Future<(_Group, List<RenderLiquidGlass>)> _group(List<_Motion> motions) async {
  final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
  final link = GlassGroupLink();
  final glasses = [
    for (final motion in motions)
      RenderLiquidGlass(shape: _capsule, glassContainsChild: false, blendGroupLink: link)
        ..motion = motion
        ..child = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(20, 20))),
  ];
  final group = _Group(geometryShader: program.fragmentShader(), link: link)
    ..child = RenderFlex(textDirection: TextDirection.ltr, crossAxisAlignment: CrossAxisAlignment.start, children: glasses);
  final root = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(800, 400)), child: group);
  PipelineOwner().rootNode = root;
  root.layout(const BoxConstraints());
  return (group, glasses);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a sinking or pending ghost counts toward the sixteen shapes of a container, and is left out before a member is', () async {
    final (group, glasses) = await _group([for (var i = 0; i < 15; i++) _Motion(), for (var i = 0; i < 3; i++) _Motion(transient: true)]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(LiquidGlassBlendGroup.maxShapesPerLayer));
    expect(shapes.map((shape) => shape.renderObject), glasses.take(16));
  });

  test('sixteen members and a ghost draw the members and leave the ghost out, where the upload would otherwise throw', () async {
    final (group, glasses) = await _group([for (var i = 0; i < 16; i++) _Motion(), _Motion(transient: true)]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes.map((shape) => shape.renderObject), glasses.take(16));
  });

  test('ghosts under the cap all stay in the geometry', () async {
    final (group, glasses) = await _group([for (var i = 0; i < 12; i++) _Motion(), for (var i = 0; i < 4; i++) _Motion(transient: true)]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes.map((shape) => shape.renderObject), glasses);
  });

  test('a ghost registered before the last member is the one left out', () async {
    final (group, glasses) = await _group([for (var i = 0; i < 8; i++) _Motion(), _Motion(transient: true), for (var i = 0; i < 8; i++) _Motion()]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(16));
    expect(shapes.map((shape) => shape.renderObject), isNot(contains(glasses[8])));
  });

  test('a settled geometry is marked for an update in the frame a member moves, and left alone when none did', () async {
    final moving = _Motion(), still = _Motion();
    final (group, _) = await _group([still, moving]);
    group.settle();
    expect(group.state, LiquidGlassGeometryState.updated);
    group.revalidateGeometry();
    expect(group.state, LiquidGlassGeometryState.updated);
    moving.moved = true;
    group.revalidateGeometry();
    expect(group.state, LiquidGlassGeometryState.mightNeedUpdate);
    expect(moving.moved, isFalse);
  });

  test('a ghost reports nothing, so it never marks the geometry', () async {
    final (group, _) = await _group([_Motion(transient: true)]);
    group.settle();
    group.revalidateGeometry();
    expect(group.state, LiquidGlassGeometryState.updated);
  });
}
