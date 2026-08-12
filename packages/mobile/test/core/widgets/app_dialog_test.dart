import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';

void main() {
  Future<bool?> pumpAndConfirm(WidgetTester tester, {required bool tapConfirm}) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => SkinScope(
            skin: const DarkSkin(),
            child: AppScaffold(
              body: Builder(
                builder: (context) => PrimaryButton(
                  text: 'Kill',
                  onPressed: () async {
                    result = await AppDialog.confirm(
                      context,
                      title: 'Kill session?',
                      message: 'This stops proj-1.',
                      confirmLabel: 'Kill',
                      destructive: true,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Kill').first);
    await tester.pumpAndSettle();
    expect(find.text('Kill session?'), findsOneWidget);
    expect(find.text('This stops proj-1.'), findsOneWidget);

    await tester.tap(find.text(tapConfirm ? 'Kill' : 'Cancel').last);
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('resolves true when confirmed', (tester) async {
    expect(await pumpAndConfirm(tester, tapConfirm: true), isTrue);
  });

  testWidgets('resolves false when cancelled', (tester) async {
    expect(await pumpAndConfirm(tester, tapConfirm: false), isFalse);
  });
}
