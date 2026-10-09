import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/glass/glass_bar_item.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_screen.dart';

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1206, 2622);
    binding.platformDispatcher.views.first.devicePixelRatio = 3;
  });

  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());

  testWidgets('navbar.inline draws one glass member per trailing action, as the app screens do', (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(home: GlassLabScreen(launch: const GlassLabLaunch(scene: 'navbar.inline'))),
      ),
    );
    await tester.pump();
    expect(find.byType(GlassBarItem), findsNWidgets(2));
    expect(find.descendant(of: find.byType(GlassBarItem), matching: find.byType(GlassButton)), findsNothing);
    expect(find.descendant(of: find.byType(GlassSurface), matching: find.byType(GlassSurface)), findsNothing);
    expect(find.descendant(of: find.byType(GlassBarItem), matching: find.byType(GlassSurface)), findsNWidgets(2));
    expect(tester.getSize(find.byType(GlassBarItem).first), const Size(44, 44));
    expect(tester.getSize(find.byType(GlassBarItem).last), const Size(44, 44));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
