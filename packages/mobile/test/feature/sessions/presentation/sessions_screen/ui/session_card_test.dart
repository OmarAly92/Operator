import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart';

void main() {
  testWidgets('renders title, status, PR line, and relative time, and reports taps', (tester) async {
    var tapped = false;
    var longPressed = false;
    final session = SessionModel(
      id: 'proj-1',
      projectId: 'proj',
      displayName: 'Fix auth',
      status: 'working',
      branch: 'fix/auth-timeouts',
      updatedAt: DateTime.now().subtract(const Duration(minutes: 3)).toIso8601String(),
      prs: const [SessionPrModel(url: 'u', number: 12, state: 'open')],
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(
                session: session,
                showProject: true,
                onTap: () => tapped = true,
                onLongPress: () => longPressed = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Fix auth'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('PR #12 open'), findsOneWidget);
    expect(find.text('3m'), findsOneWidget);

    await tester.tap(find.byType(SessionCard));
    expect(tapped, isTrue);

    await tester.longPress(find.byType(SessionCard));
    expect(longPressed, isTrue);
  });

  testWidgets('renders no timestamp when the session has never reported one', (tester) async {
    const session = SessionModel(id: 'proj-1', projectId: 'proj', displayName: 'Fix auth', status: 'working');

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(session: session, showProject: true, onTap: () {}, onLongPress: () {}),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Fix auth'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });
}
