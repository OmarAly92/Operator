import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_scene.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_screen.dart';

void main() {
  group('GlassLabScene.parse', () {
    test('maps known names', () {
      expect(GlassLabScene.parse('sheet'), GlassLabScene.sheet);
      expect(GlassLabScene.parse('corners'), GlassLabScene.corners);
      expect(GlassLabScene.parse('lifted'), GlassLabScene.lifted);
      expect(GlassLabScene.parse('sheetscroll'), GlassLabScene.sheetscroll);
      expect(GlassLabScene.parse('rest'), GlassLabScene.rest);
    });

    test('falls back to rest for null and unknown values', () {
      expect(GlassLabScene.parse(null), GlassLabScene.rest);
      expect(GlassLabScene.parse('nonsense'), GlassLabScene.rest);
    });
  });

  testWidgets('lab screen renders the four scene cards', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => const MaterialApp(home: GlassLabScreen(scene: GlassLabScene.rest)),
      ),
    );
    await tester.pump();
    for (var i = 1; i <= 4; i++) {
      expect(find.text('Session $i'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
