import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_screen.dart';

const Size _screen = Size(402, 874);

Map<String, dynamic> _entry() => (jsonDecode(File('../../../tool/glass_lab/scenes.json').readAsStringSync()) as List<dynamic>)
    .cast<Map<String, dynamic>>()
    .singleWhere((entry) => entry['id'] == 'material.union');

Rect _region(Map<String, dynamic> entry, String name) {
  final values = (entry['regions'][name] as List<dynamic>).cast<num>();
  return Rect.fromLTWH(values[0].toDouble(), values[1].toDouble(), values[2].toDouble(), values[3].toDouble());
}

void main() {
  testWidgets('the union scene lays out four 64 pt glasses in two unions as native does, centred on y 451', (tester) async {
    tester.view.physicalSize = _screen * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.union'))));
    await tester.pump();
    final glasses = tester.widgetList<GlassEffect>(find.byType(GlassEffect)).toList();
    expect(glasses, hasLength(4));
    final rects = [for (final glass in glasses) tester.getRect(find.byWidget(glass))];
    expect(rects, [
      for (final left in [49.0, 129.0, 209.0, 289.0]) Rect.fromLTWH(left, 419, 64, 64),
    ]);
    expect(rects.first.center.dy, 451);
    expect([for (final glass in glasses) glass.union!.id], ['first', 'first', 'second', 'second']);
    expect(glasses.map((glass) => glass.union!.namespace).toSet(), hasLength(1));
    expect(glasses.map((glass) => glass.shape).toSet(), {const GlassShape.capsule()});
    expect(glasses.map((glass) => glass.glass).toSet(), {Glass.regular});
    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
    expect([for (final icon in icons) icon.icon], [Icons.star, Icons.favorite, Icons.bolt, Icons.eco]);
    expect(icons.map((icon) => icon.size).toSet(), {24});
    for (final (index, icon) in icons.indexed) {
      expect(tester.getCenter(find.byWidget(icon)), rects[index].center);
      expect(find.ancestor(of: find.byWidget(icon), matching: find.byType(GlassForeground)), findsOneWidget);
    }
    expect(tester.widget<GlassEffectContainer>(find.byType(GlassEffectContainer)).spacing, 8);
    final namespace = glasses.first.union!.namespace;
    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.union'))));
    expect(tester.widget<GlassEffect>(find.byType(GlassEffect).first).union!.namespace, same(namespace));
  });

  test('the union manifest pins each union and the pair padded by 12 pt, and judges their topology on its stills', () {
    final entry = _entry();
    expect(_region(entry, 'first'), const Rect.fromLTRB(49, 419, 193, 483).inflate(12));
    expect(_region(entry, 'second'), const Rect.fromLTRB(209, 419, 353, 483).inflate(12));
    expect(_region(entry, 'pair'), const Rect.fromLTRB(49, 419, 353, 483).inflate(12));
    expect(entry['topology'], ['first', 'second', 'pair']);
    expect(entry['backdrops'], ['stripes']);
    expect(entry['appearances'], ['light', 'dark']);
    expect(entry['steps'], isEmpty);
  });
}
