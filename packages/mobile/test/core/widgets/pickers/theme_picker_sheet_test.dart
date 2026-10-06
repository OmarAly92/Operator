import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/pickers/theme_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';

void main() {
  Widget host(AppSkin skin, void Function(BuildContext context) open) => SkinScope(
        skin: skin,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(onPressed: () => open(context), child: const Text('Open')),
              ),
            ),
          ),
        ),
      );

  testWidgets('a picked theme is still returned', (tester) async {
    ThemeMode? picked;
    await tester.pumpWidget(
      host(const LightSkin(), (context) async => picked = await showThemePickerSheet(context, selected: ThemeMode.system)),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(picked, ThemeMode.dark);
    expect(find.byKey(AppSheet.surfaceKey), findsNothing);
  });

  testWidgets('the subtitle and the options start on the same column', (tester) async {
    await tester.pumpWidget(host(const LightSkin(), (context) => showThemePickerSheet(context, selected: ThemeMode.system)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final subtitle = tester.getTopLeft(find.text('Applies across the app.')).dx;
    for (final label in ['System', 'Light', 'Dark']) {
      expect(tester.getTopLeft(find.text(label)).dx, subtitle, reason: label);
    }
  });
}
