import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_under_bars.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';

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
    expect(scaffold.backgroundColor, const Color(0xFF18171C));
  });

  Widget wrap(Widget child) => SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(home: child),
        ),
      );

  testWidgets('AppScaffold keeps the body below the glass bar by default', (tester) async {
    await tester.pumpWidget(wrap(const AppScaffold(appBar: GlobalAppbar.sub(titleText: 'T'), body: SizedBox.expand())));
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBodyBehindAppBar, isFalse);
    expect(find.byType(ScrollUnderBars), findsNothing);
  });

  testWidgets('AppScaffold scrollsUnderAppBar extends the body and adds the top fade', (tester) async {
    double? bodyTop;
    await tester.pumpWidget(
      wrap(
        AppScaffold(
          appBar: const GlobalAppbar.sub(titleText: 'T'),
          scrollsUnderAppBar: true,
          body: Builder(
            builder: (context) {
              bodyTop = MediaQuery.paddingOf(context).top;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBodyBehindAppBar, isTrue);
    expect(find.byType(ScrollUnderBars), findsOneWidget);
    expect(bodyTop, 44);
  });
}
