import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/glass_shadow.dart';
import 'package:ios_liquid_glass/src/internal/render_liquid_glass_geometry.dart';
import 'package:ios_liquid_glass/src/liquid_glass.dart';
import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_widgets.dart';
import 'package:ios_liquid_glass/src/motion/glass_shape_motion.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_render_object.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

const LiquidShape _capsule = LiquidRoundedRectangle(borderRadius: 999);

class _Scene extends StatefulWidget {
  const _Scene({required this.children, this.container = true});

  final List<Widget> Function(_SceneState state) children;
  final bool container;

  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> {
  final GlassNamespace namespace = GlassNamespace();
  final GlassNamespace other = GlassNamespace();
  bool shown = true;
  double gap = 16;

  void update(VoidCallback change) => setState(change);

  @override
  Widget build(BuildContext context) {
    final row = Row(mainAxisSize: MainAxisSize.min, children: widget.children(this));
    return MaterialApp(
      home: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: Align(alignment: Alignment.topLeft, child: widget.container ? GlassEffectContainer(child: row) : row),
      ),
    );
  }
}

Widget _glass(String key, {GlassEffectUnion? union, GlassShape shape = const GlassShape.capsule(), Glass glass = Glass.regular}) =>
    GlassEffect(key: ValueKey(key), union: union, shape: shape, glass: glass, child: const SizedBox.square(dimension: 64));

GlassMember _member(WidgetTester tester, String key) => tester
    .renderObject<RenderGlassMemberBox>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlassMemberBox)).first)
    .member;

_SceneState _state(WidgetTester tester) => tester.state<_SceneState>(find.byType(_Scene));

Rect _bounds(Iterable<GlassMember> members) => members.map((member) => member.drawn!).reduce((a, b) => a.expandToInclude(b));

class _Motion extends ChangeNotifier implements GlassShapeMotion {
  _Motion(this.drawn, [this.outline]);

  Rect drawn;
  GlassUnionOutline? outline;

  @override
  Rect resolve(RenderBox shape) => drawn;

  @override
  bool get isTransient => false;

  @override
  bool syncMoved() => false;

  @override
  GlassUnionOutline? union(RenderBox shape) => outline;
}

class _Group extends RenderLiquidGlassBlendGroup {
  _Group({required super.geometryShader, required super.link})
    : super(renderLink: GeometryRenderLink(), devicePixelRatio: 3, settings: const LiquidGlassSettings(thickness: 20), blend: 8);

  @override
  void updateShaderWithSettings(LiquidGlassSettings settings, double devicePixelRatio) {}

  @override
  void updateGeometryShaderShapes(List<ShapeGeometry> shapes) {}

  void remember() {
    final (bounds, shapes, _) = gatherShapeData();
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    geometry = UnrenderedGeometryCache(matte: recorder.endRecording(), matteBounds: bounds, bounds: bounds, shapes: shapes, path: Path());
  }
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
  isLocalTest = true;
  tearDown(debugResetGlassAnimation);

  test('a union is equal to another with the same id in the same namespace, and to no other', () {
    final namespace = GlassNamespace();
    final other = GlassNamespace();
    expect(GlassEffectUnion('first', namespace), GlassEffectUnion('first', namespace));
    expect(GlassEffectUnion('first', namespace).hashCode, GlassEffectUnion('first', namespace).hashCode);
    expect(GlassEffectUnion('first', namespace), isNot(GlassEffectUnion('second', namespace)));
    expect(GlassEffectUnion('first', namespace), isNot(GlassEffectUnion('first', other)));
    expect(namespace, isNot(other));
    expect(const GlassEffect(child: SizedBox()).union, isNull);
  });

  testWidgets('each union in a container draws as one capsule on the bounding rect of its members, led by its first member', (tester) async {
    await tester.pumpWidget(_Scene(children: (state) => [
      for (final (index, key) in ['a', 'b', 'c', 'd'].indexed) ...[
        if (index > 0) const SizedBox(width: 16),
        _glass(key, union: GlassEffectUnion(index < 2 ? 'first' : 'second', state.namespace)),
      ],
    ]));
    await tester.pump(const Duration(seconds: 1));
    final [a, b, c, d] = [for (final key in ['a', 'b', 'c', 'd']) _member(tester, key)];
    expect(a.unionOutline, GlassUnionOutline(rect: Rect.fromLTRB(a.drawn!.left, a.drawn!.top, b.drawn!.right, b.drawn!.bottom), shape: _capsule, leads: true));
    expect(a.unionOutline!.rect.size, const Size(144, 64));
    expect(b.unionOutline, GlassUnionOutline(rect: a.unionOutline!.rect, shape: _capsule, leads: false));
    expect(c.unionOutline!.rect, Rect.fromLTRB(c.drawn!.left, c.drawn!.top, d.drawn!.right, d.drawn!.bottom));
    expect(c.unionOutline!.leads, isTrue);
    expect(d.unionOutline!.leads, isFalse);
    expect(c.unionOutline!.rect.left - a.unionOutline!.rect.right, 16);
  });

  testWidgets('union members keep their own drawn rects, so their content stays where each is laid out', (tester) async {
    await tester.pumpWidget(_Scene(children: (state) => [
      _glass('a', union: GlassEffectUnion('first', state.namespace)),
      const SizedBox(width: 16),
      _glass('b', union: GlassEffectUnion('first', state.namespace)),
    ]));
    await tester.pump(const Duration(seconds: 1));
    final a = _member(tester, 'a'), b = _member(tester, 'b');
    final boxA = tester.renderObject<RenderGlassMemberBox>(find.descendant(of: find.byKey(const ValueKey('a')), matching: find.byType(GlassMemberBox)).first);
    final boxB = tester.renderObject<RenderGlassMemberBox>(find.descendant(of: find.byKey(const ValueKey('b')), matching: find.byType(GlassMemberBox)).first);
    expect(a.resolve(boxA), const Rect.fromLTWH(0, 0, 64, 64));
    expect(b.resolve(boxB), const Rect.fromLTWH(0, 0, 64, 64));
    expect(a.union(boxA), GlassUnionOutline(rect: const Rect.fromLTWH(0, 0, 144, 64), shape: _capsule, leads: true));
    expect(b.union(boxB), GlassUnionOutline(rect: const Rect.fromLTWH(-80, 0, 144, 64), shape: _capsule, leads: false));
  });

  testWidgets('a union of circles is a capsule of its rect; a union of rounded rects keeps their corner radius', (tester) async {
    await tester.pumpWidget(_Scene(children: (state) => [
      _glass('a', union: GlassEffectUnion('circles', state.namespace), shape: const GlassShape.circle()),
      _glass('b', union: GlassEffectUnion('circles', state.namespace), shape: const GlassShape.circle()),
      _glass('c', union: GlassEffectUnion('rects', state.namespace), shape: const GlassShape.rect(20)),
      _glass('d', union: GlassEffectUnion('rects', state.namespace), shape: const GlassShape.rect(20)),
    ]));
    await tester.pump(const Duration(seconds: 1));
    expect(_member(tester, 'a').unionOutline!.shape, _capsule);
    expect(_member(tester, 'a').unionOutline!.rect.size, const Size(128, 64));
    expect(_member(tester, 'c').unionOutline!.shape, const LiquidRoundedRectangle(borderRadius: 20));
  });

  testWidgets('only glass with the same shape and the same glass joins a union, as SwiftUI documents', (tester) async {
    await tester.pumpWidget(_Scene(children: (state) => [
      _glass('a', union: GlassEffectUnion('u', state.namespace)),
      _glass('b', union: GlassEffectUnion('u', state.namespace)),
      _glass('rect', union: GlassEffectUnion('u', state.namespace), shape: const GlassShape.rect(20)),
      _glass('interactive', union: GlassEffectUnion('u', state.namespace), glass: Glass.regular.interactive()),
    ]));
    await tester.pump(const Duration(seconds: 1));
    final a = _member(tester, 'a'), b = _member(tester, 'b');
    expect(a.unionOutline!.rect, _bounds([a, b]));
    expect(_member(tester, 'rect').unionOutline, isNull);
    expect(_member(tester, 'interactive').unionOutline, isNull);
  });

  testWidgets('the same id in different namespaces, or no union, draws each glass on its own', (tester) async {
    await tester.pumpWidget(_Scene(children: (state) => [
      _glass('a', union: GlassEffectUnion('first', state.namespace)),
      _glass('b', union: GlassEffectUnion('first', state.other)),
      _glass('c'),
    ]));
    await tester.pump(const Duration(seconds: 1));
    for (final key in ['a', 'b', 'c']) {
      expect(_member(tester, key).unionOutline, isNull, reason: key);
    }
  });

  testWidgets('standalone glass with a union id draws on its own: a union needs a container', (tester) async {
    await tester.pumpWidget(_Scene(container: false, children: (state) => [
      _glass('a', union: GlassEffectUnion('first', state.namespace)),
      _glass('b', union: GlassEffectUnion('first', state.namespace)),
    ]));
    await tester.pump(const Duration(seconds: 1));
    expect(_member(tester, 'a').unionOutline, isNull);
    expect(_member(tester, 'b').unionOutline, isNull);
  });

  testWidgets('a union follows a moving member: its rect is the bounding rect of the drawn rects on every frame', (tester) async {
    await tester.pumpWidget(_Scene(children: (state) => [
      _glass('a', union: GlassEffectUnion('first', state.namespace)),
      SizedBox(width: state.gap),
      _glass('b', union: GlassEffectUnion('first', state.namespace)),
    ]));
    await tester.pump(const Duration(seconds: 1));
    final a = _member(tester, 'a'), b = _member(tester, 'b');
    var notified = 0;
    a.addListener(() => notified++);
    expect(a.unionOutline!.rect.width, 144);
    _state(tester).update(() => _state(tester).gap = 116);
    await tester.pump();
    final widths = <double>[];
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(a.unionOutline!.rect, _bounds([a, b]));
      widths.add(a.unionOutline!.rect.width);
    }
    expect(widths.first, inExclusiveRange(144, 244));
    expect(widths.last, greaterThan(widths.first));
    expect(a.isMoving, isFalse);
    expect(notified, greaterThan(4));
    await tester.pumpAndSettle();
    expect(a.unionOutline!.rect, Rect.fromLTWH(a.drawn!.left, a.drawn!.top, 244, 64));
  });

  testWidgets('an inserted member materializes on its own and joins its union when it settles', (tester) async {
    await tester.pumpWidget(_Scene(children: (state) => [
      _glass('a', union: GlassEffectUnion('first', state.namespace)),
      _glass('b', union: GlassEffectUnion('first', state.namespace)),
      if (!state.shown) _glass('c', union: GlassEffectUnion('first', state.namespace)),
    ]));
    await tester.pump(const Duration(seconds: 1));
    final a = _member(tester, 'a'), b = _member(tester, 'b');
    _state(tester).update(() => _state(tester).shown = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final c = _member(tester, 'c');
    expect(c.ownsLayer, isTrue);
    expect(c.unionOutline, isNull);
    expect(a.unionOutline!.rect, _bounds([a, b]));
    await tester.pumpAndSettle();
    expect(c.ownsLayer, isFalse);
    expect(a.unionOutline!.rect, _bounds([a, b, c]));
    expect(c.unionOutline!.leads, isFalse);
  });

  testWidgets('a removed member leaves its union at once and dematerializes on its own; the rest notice', (tester) async {
    await tester.pumpWidget(_Scene(children: (state) => [
      if (state.shown) _glass('a', union: GlassEffectUnion('first', state.namespace)),
      _glass('b', union: GlassEffectUnion('first', state.namespace)),
      _glass('c', union: GlassEffectUnion('first', state.namespace)),
    ]));
    await tester.pump(const Duration(seconds: 1));
    final b = _member(tester, 'b'), c = _member(tester, 'c');
    expect(b.unionOutline!.leads, isFalse);
    var notified = 0;
    b.addListener(() => notified++);
    _state(tester).update(() => _state(tester).shown = false);
    await tester.pump();
    expect(notified, greaterThan(0));
    expect(b.unionOutline!.leads, isTrue);
    expect(b.unionOutline!.rect, _bounds([b, c]));
    final ghost = b.coordinator.ghosts.single;
    expect(ghost.rect.size, const Size(64, 64));
    expect(ghost.shape, _capsule);
    await tester.pumpAndSettle();
    expect(b.coordinator.ghosts, isEmpty);
  });

  testWidgets('a union left with one member draws that member on its own', (tester) async {
    await tester.pumpWidget(_Scene(children: (state) => [
      if (state.shown) _glass('a', union: GlassEffectUnion('first', state.namespace)),
      _glass('b', union: GlassEffectUnion('first', state.namespace)),
    ]));
    await tester.pump(const Duration(seconds: 1));
    _state(tester).update(() => _state(tester).shown = false);
    await tester.pump();
    expect(_member(tester, 'b').unionOutline, isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('a union whose id changes in a rebuild leaves the old union and its members notice', (tester) async {
    await tester.pumpWidget(_Scene(children: (state) => [
      _glass('a', union: GlassEffectUnion(state.shown ? 'first' : 'second', state.namespace)),
      _glass('b', union: GlassEffectUnion('first', state.namespace)),
    ]));
    await tester.pump(const Duration(seconds: 1));
    final b = _member(tester, 'b');
    expect(b.unionOutline, isNotNull);
    var notified = 0;
    b.addListener(() => notified++);
    _state(tester).update(() => _state(tester).shown = false);
    await tester.pump();
    expect(notified, greaterThan(0));
    expect(b.unionOutline, isNull);
    expect(_member(tester, 'a').unionOutline, isNull);
  });

  test('a blend group gathers one shape per union, at the union rect and shape, and skips the members it does not lead', () async {
    final (group, glasses) = await _group([
      _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(0, 0, 60, 20), shape: _capsule, leads: true)),
      _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(-40, 0, 60, 20), shape: _capsule, leads: false)),
      _Motion(const Rect.fromLTWH(0, 0, 20, 20)),
    ]);
    final (_, shapes, changed) = group.gatherShapeData();
    expect(changed, isTrue);
    expect(shapes, hasLength(2));
    expect(shapes[0].renderObject, glasses[0]);
    expect(shapes[0].shapeBounds, const Rect.fromLTWH(0, 0, 60, 20));
    expect(shapes[0].shape, _capsule);
    expect(shapes[1].renderObject, glasses[2]);
    expect(shapes[1].shapeBounds, const Rect.fromLTWH(40, 0, 20, 20));
    expect(glasses[0].getPath().getBounds(), const Rect.fromLTWH(0, 0, 60, 20));
    expect(glasses[1].getPath().getBounds(), Rect.zero);
  });

  test('a union counts as one shape against the 16-shape cap', () async {
    final (group, _) = await _group([
      _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(0, 0, 40, 20), shape: _capsule, leads: true)),
      _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(-20, 0, 40, 20), shape: _capsule, leads: false)),
      for (var i = 0; i < 15; i++) _Motion(const Rect.fromLTWH(0, 0, 20, 20)),
    ]);
    final (_, shapes, _) = group.gatherShapeData();
    expect(shapes, hasLength(LiquidGlassBlendGroup.maxShapesPerLayer));
  });

  test('a union rect that moves while its leader stays marks the gathered geometry changed', () async {
    final follower = _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(-20, 0, 40, 20), shape: _capsule, leads: false));
    final leader = _Motion(const Rect.fromLTWH(0, 0, 20, 20), const GlassUnionOutline(rect: Rect.fromLTWH(0, 0, 40, 20), shape: _capsule, leads: true));
    final (group, _) = await _group([leader, follower]);
    group.remember();
    expect(group.gatherShapeData().$3, isFalse);
    leader.outline = const GlassUnionOutline(rect: Rect.fromLTWH(0, 0, 50, 20), shape: _capsule, leads: true);
    expect(group.gatherShapeData().$3, isTrue);
  });

  testWidgets('a union leader paints one shadow on the union rect and shape; the members it leads paint none', (tester) async {
    const shadow = BoxShadow(color: Color(0x40000000), blurRadius: 6);
    final leader = _Motion(const Rect.fromLTWH(0, 0, 64, 64), const GlassUnionOutline(rect: Rect.fromLTWH(0, 0, 144, 64), shape: _capsule, leads: true));
    final follower = _Motion(const Rect.fromLTWH(0, 0, 64, 64), const GlassUnionOutline(rect: Rect.fromLTWH(-80, 0, 144, 64), shape: _capsule, leads: false));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassShadow(key: const ValueKey('leader'), shape: _capsule, shadows: const [shadow], settings: const LiquidGlassSettings(), motion: leader, child: const SizedBox.square(dimension: 64)),
            const SizedBox(width: 16),
            GlassShadow(key: const ValueKey('follower'), shape: _capsule, shadows: const [shadow], settings: const LiquidGlassSettings(), motion: follower, child: const SizedBox.square(dimension: 64)),
          ],
        ),
      ),
    ));
    expect(
      tester.renderObject(find.byKey(const ValueKey('leader'))),
      paints..rrect(rrect: RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 144, 64), const Radius.circular(999))),
    );
    expect(tester.renderObject(find.byKey(const ValueKey('follower'))), paintsNothing);
  });
}
