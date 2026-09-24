import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_sheet_chrome.dart';

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

  testWidgets('sheet content spans the sheet and ink rows work inside it', (tester) async {
    const contentKey = ValueKey('content');
    var tapped = 0;
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showAppSheet<void>(
          context: context,
          builder: (_) => AppSheetChrome(
            child: Column(
              key: contentKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 20),
                ListTile(title: const Text('Row'), onTap: () => tapped++),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final screenWidth = tester.getSize(find.byType(Scaffold).first).width;
    expect(tester.getSize(find.byKey(contentKey)).width, screenWidth - 8 * 2 - 16 * 2);
    await tester.tap(find.text('Row'));
    await tester.pump();
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
  });
}
