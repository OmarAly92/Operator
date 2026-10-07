import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_registry.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_screen.dart';
import 'package:ios_liquid_glass_example/lab/scenes/spacing_scenes.dart';

const Size _screen = Size(402, 874);
const double _top = 62;
const double _bottom = 34;

List<Map<String, dynamic>> _manifest() =>
    (jsonDecode(File('../../../tool/glass_lab/scenes.json').readAsStringSync()) as List<dynamic>).cast<Map<String, dynamic>>();

double _pixel(double points) => (points * 3 + 0.5).floorToDouble() / 3;

void _iPhone17Pro(WidgetTester tester) {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: _top * 3, bottom: _bottom * 3);
  addTearDown(tester.view.reset);
}

List<Rect> _glass(WidgetTester tester) {
  final rects = [for (final element in find.byType(GlassEffect).evaluate()) tester.getRect(find.byWidget(element.widget))];
  rects.sort((a, b) => a.top != b.top ? a.top.compareTo(b.top) : a.left.compareTo(b.left));
  return rects;
}

void main() {
  final spacingIds = [
    for (final entry in _manifest())
      if ((entry['id'] as String).startsWith('material.spacing.')) entry['id'] as String,
  ];

  test('every N7 spacing scene and the merge scene are registered, with the gaps their manifest regions name', () {
    expect(spacingIds, hasLength(23));
    expect(GlassLabRegistry.scenes.keys, containsAll([...spacingIds, 'material.merge']));
    for (final entry in _manifest()) {
      final id = entry['id'] as String;
      if (!spacingIds.contains(id)) continue;
      final regions = (entry['regions'] as Map<String, dynamic>).keys;
      expect([for (final gap in SpacingScenes.gaps[id]!) 'g${gap.toInt()}'], regions.toList(), reason: id);
      final spacing = id.split('.')[2];
      expect(SpacingScenes.spacing[id], spacing == 'default' ? isNull : double.parse(spacing), reason: id);
    }
  });

  testWidgets('each spacing scene places its pairs as native does: 80 pt circles, 100 pt apart, centred on the pixel grid', (tester) async {
    _iPhone17Pro(tester);
    final safe = _screen.height - _top - _bottom;
    for (final entry in _manifest()) {
      final id = entry['id'] as String;
      if (!spacingIds.contains(id)) continue;
      await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: id))));
      await tester.pump();
      final gaps = SpacingScenes.gaps[id]!;
      final height = gaps.length * 80 + (gaps.length - 1) * 100;
      final rects = _glass(tester);
      expect(rects, hasLength(gaps.length * 2), reason: id);
      final regions = (entry['regions'] as Map<String, dynamic>).values.map((r) => (r as List<dynamic>).cast<num>()).toList();
      for (final (index, gap) in gaps.indexed) {
        final top = _top + (safe - height) / 2 + index * 180;
        final left = _pixel((_screen.width - 160 - gap) / 2);
        expect(rects[2 * index], Rect.fromLTWH(left, top, 80, 80), reason: '$id g$gap');
        expect(rects[2 * index + 1], Rect.fromLTWH(left + 80 + gap, top, 80, 80), reason: '$id g$gap');
        final region = Rect.fromLTWH(regions[index][0].toDouble(), regions[index][1].toDouble(), regions[index][2].toDouble(), regions[index][3].toDouble());
        expect(region.inflate(-11).contains(rects[2 * index].topLeft) && region.inflate(-11).contains(rects[2 * index + 1].bottomRight), isTrue, reason: '$id g$gap');
      }
      final containers = tester.widgetList<GlassEffectContainer>(find.byType(GlassEffectContainer)).toList();
      expect(containers, hasLength(gaps.length), reason: id);
      for (final container in containers) {
        expect(container.spacing, SpacingScenes.spacing[id] ?? 8, reason: id);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('an odd-width pair sits half a pixel right of the half point, as native g5 does at x 118.667', (tester) async {
    _iPhone17Pro(tester);
    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.spacing.default.d'))));
    await tester.pump();
    expect(_glass(tester)[2].left, closeTo(356 / 3, 1e-9));
  });

  testWidgets('the merge scene closes its gap on Merge and opens it again on Split, centred in its container', (tester) async {
    _iPhone17Pro(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.merge'))));
    await tester.pump();
    expect(tester.widget<GlassEffectContainer>(find.byType(GlassEffectContainer)).spacing, 40);
    const top = _top + (874 - _top - _bottom - 80) / 2;
    expect(_glass(tester), [const Rect.fromLTWH(81, top, 80, 80), const Rect.fromLTWH(241, top, 80, 80)]);
    final merge = tester.getRect(find.bySemanticsIdentifier('merge'));
    final split = tester.getRect(find.bySemanticsIdentifier('split'));
    expect(merge.bottom, _screen.height - _bottom - 120);
    expect(split.left - merge.right, 24);
    expect((merge.left + split.right) / 2, _screen.width / 2);
    await tester.tap(find.bySemanticsIdentifier('merge'));
    await tester.pumpAndSettle();
    expect(_glass(tester), [const Rect.fromLTWH(121, top, 80, 80), const Rect.fromLTWH(201, top, 80, 80)]);
    await tester.tap(find.bySemanticsIdentifier('split'));
    await tester.pumpAndSettle();
    expect(_glass(tester), [const Rect.fromLTWH(81, top, 80, 80), const Rect.fromLTWH(241, top, 80, 80)]);
    semantics.dispose();
  });
}
