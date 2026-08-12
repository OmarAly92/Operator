import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/connection_failure_banner.dart';

void main() {
  testWidgets('renders the title and message, and shows the Local Network hint when set', (tester) async {
    const copy = ConnectionErrorCopy(
      title: 'Your desktop disconnected',
      message: 'Reached nothing at 192.168.1.5:3011.',
      showLocalNetworkHint: true,
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(body: ConnectionFailureBanner(copy: copy)),
          ),
        ),
      ),
    );

    expect(find.text('Your desktop disconnected'), findsOneWidget);
    expect(find.text('Reached nothing at 192.168.1.5:3011.'), findsOneWidget);
    expect(find.textContaining('Local Network'), findsOneWidget);
  });

  testWidgets('omits the hint when not set', (tester) async {
    const copy = ConnectionErrorCopy(title: 'Too many attempts', message: 'Wait a minute.', showLocalNetworkHint: false);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(body: ConnectionFailureBanner(copy: copy)),
          ),
        ),
      ),
    );

    expect(find.textContaining('Local Network'), findsNothing);
  });
}
