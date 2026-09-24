import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_sheet.dart';

Widget _host(double childHeight) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(402, 874)),
        child: SkinScope(
          skin: const LightSkin(),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GlassSheetChrome(child: SizedBox(height: childHeight, child: const Text('Sheet'))),
          ),
        ),
      ),
    );

void main() {
  test('floats below 90% of the screen and anchors above', () {
    expect(GlassSheetLogic.isFloating(sheetHeight: 437, screenHeight: 874), isTrue);
    expect(GlassSheetLogic.isFloating(sheetHeight: 800, screenHeight: 874), isFalse);
  });

  testWidgets('a half-height sheet floats as glass', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(400));
    await tester.pump();
    expect(find.byKey(GlassSheetChrome.floatingKey), findsOneWidget);
    expect(find.byKey(GlassSheetChrome.anchoredKey), findsNothing);
  });

  testWidgets('a full-height sheet anchors opaque', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(820));
    await tester.pump();
    expect(find.byKey(GlassSheetChrome.anchoredKey), findsOneWidget);
    expect(find.byKey(GlassSheetChrome.floatingKey), findsNothing);
  });
}
