import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';

void main() {
  testWidgets('renders its label and reflects typed text in the controller', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: AppTextField(controller: controller, label: 'HOST', hintText: '192.168.1.5'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('HOST'), findsOneWidget);
    expect(find.text('192.168.1.5'), findsNothing);

    await tester.enterText(find.byType(TextField), '10.0.0.5');
    expect(controller.text, '10.0.0.5');
  });

  testWidgets('obscures text when obscureText is set', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(body: AppTextField(controller: controller, obscureText: true)),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
  });
}
