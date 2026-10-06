import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_success/ui/pairing_success_view.dart';

void main() {
  testWidgets('confirms the connection and names the desktop', (tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => const MaterialApp(home: Scaffold(body: PairingSuccessView(desktopName: 'MacBook'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('MacBook'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
