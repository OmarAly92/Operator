import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

void main() {
  testWidgets('AppText renders its string', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: const Scaffold(body: AppText('Sessions')),
        ),
      ),
    );

    expect(find.text('Sessions'), findsOneWidget);
  });

  testWidgets('AppScaffold paints the base background', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: const AppScaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF0A0B0D));
  });
}
