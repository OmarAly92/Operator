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

Future<(_Group, List<RenderLiquidGlass>)> _placed(List<(LiquidShape, Rect)> members, {Set<int> ghosts = const {}}) async {
  final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
  final link = GlassGroupLink();
  final glasses = [
    for (final (index, (shape, rect)) in members.indexed)
      RenderLiquidGlass(shape: shape, glassContainsChild: false, blendGroupLink: link)
        ..motion = ghosts.contains(index) ? _Motion(transient: true) : null
        ..child = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(rect.size)),
  ];
  final stack = RenderStack(textDirection: TextDirection.ltr, children: glasses);
  for (final (index, glass) in glasses.indexed) {
    final rect = members[index].$2;
    (glass.parentData! as StackParentData)
      ..left = rect.left
      ..top = rect.top;
  }
  final group = _Group(geometryShader: program.fragmentShader(), link: link)..child = stack;
  final root = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(800, 400)), child: group);
  PipelineOwner().rootNode = root;
  root.layout(const BoxConstraints());
  return (group, glasses);
}

const LiquidShape _oval = LiquidOval();
const Rect _first = Rect.fromLTWH(10, 10, 44, 44);
const Rect _second = Rect.fromLTWH(62, 10, 44, 44);

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

  test('a capsule and an oval on the same square rect are one shape in the geometry', () async {
    final (group, glasses) = await _placed([(_capsule, _first), (_oval, _first)]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(1));
    expect(shapes.single.renderObject, glasses.first);
  });

  test('two such doubled buttons side by side are two shapes, not four', () async {
    final (group, _) = await _placed([(_capsule, _first), (_oval, _first), (_capsule, _second), (_oval, _second)]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(2));
    expect(shapes.map((shape) => shape.shapeBounds), [_first, _second]);
  });

  test('the doubled member still paints its content', () async {
    final (group, glasses) = await _placed([(_capsule, _first), (_oval, _first)]);
    group.gatherShapeData();
    expect(glasses.every((glass) => glass.attached), isTrue);
    expect(group.link.shapeEntries.map((entry) => entry.key), glasses);
  });

  test('a rounded rectangle whose radius is below half the side is not an oval', () async {
    final (group, _) = await _placed([(const LiquidRoundedRectangle(borderRadius: 10), _first), (_oval, _first)]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(2));
  });

  test('a rounded rectangle at exactly half the side is an oval', () async {
    final (group, _) = await _placed([(const LiquidRoundedRectangle(borderRadius: 22), _first), (_oval, _first)]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(1));
  });

  test('on a wide rect a capsule is not an oval', () async {
    const wide = Rect.fromLTWH(10, 10, 102, 44);
    final (group, _) = await _placed([(_capsule, wide), (_oval, wide)]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(2));
  });

  test('two capsules of the same rect are one shape however large their radii', () async {
    const wide = Rect.fromLTWH(10, 10, 102, 44);
    final (group, _) = await _placed([(_capsule, wide), (const LiquidRoundedRectangle(borderRadius: 40), wide)]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(1));
  });

  test('a superellipse is never an oval and a rect shifted by a pixel is not the same rect', () async {
    final (group, _) = await _placed([(const LiquidRoundedSuperellipse(borderRadius: 22), _first), (_oval, _first), (_oval, _first.shift(const Offset(1, 0)))]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(3));
  });

  test('the sixteen shape cap counts the shapes left after doubled members are dropped', () async {
    final (group, glasses) = await _placed([
      for (var i = 0; i < 16; i++) ...[(_capsule, Rect.fromLTWH(10.0 + i * 46, 10, 44, 44)), (_oval, Rect.fromLTWH(10.0 + i * 46, 10, 44, 44))],
    ]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(16));
    expect(shapes.map((shape) => shape.renderObject), [for (var i = 0; i < 32; i += 2) glasses[i]]);
  });

  test('a ghost on the same rect as a member never stands in for the member', () async {
    final (group, glasses) = await _placed([(_capsule, _first), (_capsule, _first)], ghosts: {0});
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(1));
    expect(shapes.single.renderObject, glasses.last);
  });

  test('a member registered first keeps its place when a ghost sits on its rect', () async {
    final (group, glasses) = await _placed([(_capsule, _first), (_capsule, _first)], ghosts: {1});
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(1));
    expect(shapes.single.renderObject, glasses.first);
  });
}
