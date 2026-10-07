import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_screen.dart';

const Size _screen = Size(402, 874);

Map<String, dynamic> _entry(String id) => (jsonDecode(File('../../../tool/glass_lab/scenes.json').readAsStringSync()) as List<dynamic>)
    .cast<Map<String, dynamic>>()
    .singleWhere((entry) => entry['id'] == id);

Rect _region(Map<String, dynamic> entry, String name) {
  final values = (entry['regions'][name] as List<dynamic>).cast<num>();
  return Rect.fromLTWH(values[0].toDouble(), values[1].toDouble(), values[2].toDouble(), values[3].toDouble());
}

Future<void> _show(WidgetTester tester, String scene) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: scene))));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

List<Rect> _rects(WidgetTester tester) => [for (final glass in tester.widgetList<GlassEffect>(find.byType(GlassEffect))) tester.getRect(find.byWidget(glass))];

void main() {
  tearDown(debugResetGlassAnimation);

  for (final (scene, interactive) in [('material.morph', true), ('material.morph.plain', false)]) {
    testWidgets('$scene lays out native MorphScene: a 56 pt toggle at y 451 that expands into three badges above it, 16 pt apart, in a spacing 20 container', (tester) async {
      await _show(tester, scene);
      final toggle = tester.widget<GlassEffect>(find.byType(GlassEffect));
      expect(_rects(tester), [const Rect.fromLTWH(173, 423, 56, 56)]);
      expect(toggle.glass, interactive ? Glass.regular.interactive() : Glass.regular);
      expect(toggle.id!.id, 'toggle');
      expect(toggle.effectiveTransition, GlassEffectTransition.matchedGeometry);
      expect(toggle.shape, const GlassShape.capsule());
      expect(tester.widget<GlassEffectContainer>(find.byType(GlassEffectContainer)).spacing, 20);
      expect(find.byIcon(Icons.add), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('morph'));
      await tester.pumpAndSettle();
      final glasses = tester.widgetList<GlassEffect>(find.byType(GlassEffect)).toList();
      expect([for (final glass in glasses) glass.id!.id], ['star.fill', 'heart.fill', 'bolt.fill', 'toggle']);
      expect(glasses.map((glass) => glass.id!.namespace).toSet(), hasLength(1));
      expect(glasses.map((glass) => glass.transition).toSet(), {null});
      expect(_rects(tester), [for (final top in [315.0, 387.0, 459.0, 531.0]) Rect.fromLTWH(173, top, 56, 56)]);
      expect([for (final icon in tester.widgetList<Icon>(find.byType(Icon))) icon.icon], [Icons.star, Icons.favorite, Icons.bolt, Icons.close]);
      expect(tester.widgetList<Icon>(find.byType(Icon)).map((icon) => icon.size).toSet(), {22});
      await tester.tap(find.bySemanticsIdentifier('morph'));
      await tester.pumpAndSettle();
      expect(_rects(tester), [const Rect.fromLTWH(173, 423, 56, 56)]);
    });
  }

  testWidgets('material.tap is one 56 pt interactive glass button at y 451 whose tap changes nothing', (tester) async {
    await _show(tester, 'material.tap');
    final glass = tester.widget<GlassEffect>(find.byType(GlassEffect));
    expect(glass.glass, Glass.regular.interactive());
    expect(_rects(tester), [const Rect.fromLTWH(173, 423, 56, 56)]);
    expect(tester.widget<GlassEffectContainer>(find.byType(GlassEffectContainer)).spacing, 20);
    await tester.tap(find.bySemanticsIdentifier('glass'));
    await tester.pumpAndSettle();
    expect(_rects(tester), [const Rect.fromLTWH(173, 423, 56, 56)]);
  });

  test('the morph manifest tracks the toggle at both of its rests and each badge, and judges the stack topology', () {
    final entry = _entry('material.morph');
    expect(entry['track'], ['star', 'heart', 'bolt', 'toggle', 'collapsed']);
    expect(entry['topology'], ['stack']);
    expect(_region(entry, 'collapsed').center, const Offset(201, 451));
    expect(_region(entry, 'toggle').center, const Offset(201, 559));
    expect(_region(entry, 'star').center, const Offset(201, 343));
    expect(_region(entry, 'heart').center, const Offset(201, 415));
    expect(_region(entry, 'bolt').center, const Offset(201, 487));
    expect(_region(entry, 'stack').top, lessThanOrEqualTo(315 - 12));
    expect(_region(entry, 'stack').bottom, greaterThanOrEqualTo(587 + 12));
    expect((entry['steps'] as List<dynamic>).where((step) => (step as Map).containsKey('tap')).map((step) => (step as Map)['tap']), ['morph', 'morph']);
  });
}
