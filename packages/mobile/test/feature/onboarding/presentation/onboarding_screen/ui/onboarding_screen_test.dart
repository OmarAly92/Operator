import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    AppPreferences.debugLoad(const {});
    TelemetryRuntime.reset();
  });

  tearDown(TelemetryRuntime.reset);

  Widget pushingHost(Widget onboarding) => SkinScope(
    skin: const DarkSkin(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        routes: {RoutesStrings.sessions: (_) => const SizedBox.shrink()},
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => onboarding)),
              child: const Text('Open onboarding'),
            ),
          ),
        ),
      ),
    ),
  );

  Finder backButton() => find.byWidgetPredicate(
    (widget) => widget is GlassButton && widget.icon == Icons.arrow_back_ios_new_rounded,
  );

  testWidgets('pushed onto the stack shows the glass back button and pops on tap', (tester) async {
    await tester.pumpWidget(pushingHost(const OnboardingScreen(fromDesktops: true)));
    await tester.tap(find.text('Open onboarding'));
    await tester.pumpAndSettle();

    expect(find.byType(IconButton), findsNothing);
    expect(backButton(), findsOneWidget);

    await tester.tap(backButton());
    await tester.pumpAndSettle();

    expect(find.text('Open onboarding'), findsOneWidget);
  });

  testWidgets('as the first route it shows no back button', (tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => const MaterialApp(home: OnboardingScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(IconButton), findsNothing);
    expect(backButton(), findsNothing);
  });
}
