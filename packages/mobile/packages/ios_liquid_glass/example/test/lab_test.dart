import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_marker.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_registry.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_screen.dart';
import 'package:ios_liquid_glass_example/lab/scenes/lab_parts.dart';
import 'package:ios_liquid_glass_example/lab/scenes/perf_scenes.dart';

List<String> labSceneIds() {
  final raw = jsonDecode(File('../../../tool/glass_lab/scenes.json').readAsStringSync()) as List<dynamic>;
  return [
    for (final entry in raw.cast<Map<String, dynamic>>())
      if (entry['app'] == 'lab') entry['id'] as String,
  ];
}

void main() {
  test('reads material overrides from the launch file', () {
    final launch = GlassLabLaunch.fromJson({'scene': 'material.regular', 'material': {'toneBlack': 0.2, 'toneWhite': 1}});
    expect(launch?.material, {'toneBlack': 0.2, 'toneWhite': 1.0});
    expect(launch?.materialSide, isNull);
    expect(GlassLabLaunch.fromJson({'scene': 'material.regular', 'materialSide': 200})?.materialSide, 200);
  });

  test('consume reads the launch file once and deletes it', () {
    final directory = Directory.systemTemp.createTempSync('glass_lab');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/${GlassLabLaunch.launchFile}').writeAsStringSync('{"scene": "material.clear"}');
    expect(GlassLabLaunch.consume(directory)?.scene, 'material.clear');
    expect(GlassLabLaunch.consume(directory), isNull);
  });

  test('perf stats report median, p90 and max', () {
    expect(PerfScenes.stats([4, 1, 3, 2, 5]), {'median': 3, 'p90': 5, 'max': 5});
    expect(PerfScenes.stats([]), {'median': 0, 'p90': 0, 'max': 0});
  });

  test('tool scenes are registered outside the manifest', () {
    expect(labSceneIds(), isNot(contains('perf.glass')));
    expect(GlassLabRegistry.tools.keys, containsAll(['perf.none', 'perf.glass', 'perf.material', 'perf.edge']));
  });

  testWidgets('the tinted Run button has native geometry, 78 by 37 points', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.tinted'))));
    await tester.pump();
    expect(tester.getSize(find.bySemanticsIdentifier('tinted.run')), const Size(78, 37));
    semantics.dispose();
  });

  test('scenes centre on whole points, as SwiftUI places the native column', () {
    const center = WholePointCenter();
    expect(center.getPositionForChild(const Size(402, 778), const Size(250, 173)), const Offset(76, 303));
    expect(center.getPositionForChild(const Size(402, 778), const Size(360, 428)), const Offset(21, 175));
  });

  test('every registered scene is in the manifest', () {
    expect(labSceneIds(), containsAll(GlassLabRegistry.scenes.keys));
  });

  testWidgets('every manifest scene renders its scene or the missing placeholder', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    for (final id in labSceneIds()) {
      await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: id))));
      await tester.pump();
      final missing = GlassLabRegistry.scenes.containsKey(id) ? findsNothing : findsOneWidget;
      expect(find.bySemanticsIdentifier('scene.missing'), missing, reason: id);
      expect(find.bySemanticsIdentifier('scene.ready'), findsOneWidget, reason: id);
      expect(tester.takeException(), isNull, reason: id);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }
    semantics.dispose();
  });

  test('reads the touch marker and a fixed visibility from the launch file', () {
    final launch = GlassLabLaunch.fromJson({'scene': 'tool.visibility', 'marker': true, 'visibility': 0.35, 'blurRamp': 2});
    expect(launch?.marker, isTrue);
    expect(launch?.visibility, 0.35);
    expect(launch?.blurRamp, 2);
    expect(GlassLabLaunch.fromJson({'scene': 'material.regular'})?.marker, isFalse);
  });

  testWidgets('the touch marker is red while down, blue after release and black again', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.regular', marker: true))));
    Color colour() => tester.widget<ColoredBox>(find.byKey(const ValueKey('touch.marker'))).color;
    expect(tester.getRect(find.byKey(const ValueKey('touch.marker'))), GlassLabTouchMarker.rect);
    expect(colour(), GlassLabTouchMarker.idle);
    final gesture = await tester.startGesture(const Offset(201, 300));
    await tester.pump();
    expect(colour(), GlassLabTouchMarker.down);
    await gesture.up();
    await tester.pump();
    expect(colour(), GlassLabTouchMarker.up);
    await tester.pump(const Duration(milliseconds: 300));
    expect(colour(), GlassLabTouchMarker.idle);
  });

  testWidgets('the materialize scene removes and restores its glass on the toggle', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.materialize.snappy'))));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GlassEffect), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('toggle'));
    await tester.pump();
    expect(find.byType(GlassEffect), findsNothing);
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('toggle'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassEffect), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the visibility tool ramps blur by the launch exponent, as the package ramps it', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'tool.visibility', visibility: 0.5, blurRamp: 3))));
    final settings = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings;
    final full = GlassMaterial.resolve(glass: Glass.regular, shorterSide: 88, brightness: GlassTheme.brightnessOf(tester.element(find.byType(LiquidGlassLayer)))).toSettings();
    expect(settings.visibility, 0.5);
    expect(settings.effectiveBlur, closeTo(full.blur * 0.125, 1e-9));
  });

  testWidgets('the standalone ghost tool removes glass that is in no container', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'tool.ghost.standalone'))));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GlassEffectContainer), findsNothing);
    final images = find.byType(RawImage).evaluate().length;
    await tester.tap(find.bySemanticsIdentifier('toggle'));
    await tester.pump();
    expect(find.byType(GlassEffect), findsNothing);
    expect(find.byType(RawImage).evaluate().length, images + 1);
    await tester.pumpAndSettle();
    expect(find.byType(RawImage).evaluate().length, images);
    semantics.dispose();
  });
}
