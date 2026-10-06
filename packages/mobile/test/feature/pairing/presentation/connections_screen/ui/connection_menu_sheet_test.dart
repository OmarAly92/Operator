import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connection_menu_sheet.dart';

void main() {
  void phone(WidgetTester tester, {double keyboard = 0}) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.reset);
  }

  Widget host(AppSkin skin, void Function(BuildContext context) open) => SkinScope(
        skin: skin,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(onPressed: () => open(context), child: const Text('Open')),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('Rename opens a page in the same sheet and Save returns the trimmed name', (tester) async {
    phone(tester);
    ConnectionMenuResult? result;
    await tester.pumpWidget(
      host(const LightSkin(), (context) async => result = await showConnectionMenuSheet(context, name: 'Studio')),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Studio'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Rename desktop'), findsOneWidget);
    expect(find.byKey(AppSheet.backKey), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Office Mac  ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isA<RenameDesktopResult>());
    expect((result! as RenameDesktopResult).name, 'Office Mac');
  });

  testWidgets('Save is disabled while the name is blank', (tester) async {
    phone(tester);
    ConnectionMenuResult? result;
    await tester.pumpWidget(
      host(const LightSkin(), (context) async => result = await showConnectionMenuSheet(context, name: 'Studio')),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Rename desktop'), findsOneWidget);
  });

  testWidgets('Back from Rename returns to the menu, and Remove returns a remove result', (tester) async {
    phone(tester);
    ConnectionMenuResult? result;
    await tester.pumpWidget(
      host(const LightSkin(), (context) async => result = await showConnectionMenuSheet(context, name: 'Studio')),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppSheet.backKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove desktop'));
    await tester.pumpAndSettle();
    expect(result, isA<RemoveDesktopResult>());
  });

  testWidgets('Cancel on the Rename page closes the sheet with no result', (tester) async {
    phone(tester);
    var finished = false;
    ConnectionMenuResult? result;
    await tester.pumpWidget(
      host(const LightSkin(), (context) async {
        result = await showConnectionMenuSheet(context, name: 'Studio');
        finished = true;
      }),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(result, isNull);
  });
}
