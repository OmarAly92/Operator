import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_registry.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_screen.dart';

List<String> labSceneIds() {
  final raw = jsonDecode(File('tool/glass_lab/scenes.json').readAsStringSync()) as List<dynamic>;
  return [
    for (final entry in raw.cast<Map<String, dynamic>>())
      if (entry['app'] == 'lab') entry['id'] as String,
  ];
}

Future<void> pumpLab(WidgetTester tester, GlassLabLaunch launch) async {
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, child) => MaterialApp(home: GlassLabScreen(launch: launch)),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1206, 2622);
    binding.platformDispatcher.views.first.devicePixelRatio = 3;
  });

  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());

  test('every registered scene is in the manifest', () {
    expect(labSceneIds(), containsAll(GlassLabRegistry.scenes.keys));
  });

  testWidgets('every manifest scene renders its scene or the missing placeholder', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final id in labSceneIds()) {
      await pumpLab(tester, GlassLabLaunch(scene: id));
      final missing = GlassLabRegistry.scenes.containsKey(id) ? findsNothing : findsOneWidget;
      expect(find.bySemanticsIdentifier('scene.missing'), missing, reason: id);
      expect(find.bySemanticsIdentifier('scene.ready'), findsOneWidget, reason: id);
      expect(tester.takeException(), isNull, reason: id);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }
    semantics.dispose();
  });

  testWidgets('bare mode renders only the backdrop', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLab(tester, const GlassLabLaunch(scene: 'tabbar.rest', bare: true));
    expect(find.bySemanticsLabel('Agents'), findsNothing);
    expect(find.bySemanticsIdentifier('scene.ready'), findsOneWidget);
    semantics.dispose();
  });
}
