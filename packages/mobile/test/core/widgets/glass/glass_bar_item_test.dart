import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_bar_item.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => SkinScope(skin: const LightSkin(), child: Center(child: child)),
        ),
      );

  testWidgets('default extent is 44', (tester) async {
    await tester.pumpWidget(host(GlassBarItem(child: const Text('Done'))));
    final size = tester.getSize(find.byType(GlassSurface));
    expect(size.height, 44);
  });

  testWidgets('a given extent sets the exact height and min width', (tester) async {
    await tester.pumpWidget(host(GlassBarItem(extent: 38, child: const Text('Done'))));
    final size = tester.getSize(find.byType(GlassSurface));
    expect(size.height, 38);
  });
}
