import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pr_card.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, {SessionPrSummaryModel? summary}) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: Scaffold(
              body: PrCard(
                pr: const SessionPrModel(number: 184, state: 'open', ci: 'failing'),
                session: const SessionModel(
                  id: 's1',
                  projectId: 'my-app_98d163a851',
                  displayName: 'Fix auth timeouts',
                ),
                summary: summary,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders from the thin board facts before the summary arrives', (tester) async {
    await pumpCard(tester);

    expect(find.text('#184'), findsOneWidget);
    expect(find.text('Fix auth timeouts'), findsOneWidget);
    expect(find.text('CI failing'), findsOneWidget);
  });

  testWidgets('middle-truncates a long project id so two projects stay distinguishable', (tester) async {
    await pumpCard(tester);

    expect(find.text('my-app_98d163a851'), findsNothing);
    expect(find.textContaining('…'), findsWidgets);
  });

  testWidgets('appends the rich lines once the summary lands', (tester) async {
    await pumpCard(
      tester,
      summary: const SessionPrSummaryModel(
        number: 184,
        title: 'Fix auth timeouts on refresh',
        state: 'open',
        repo: 'o/r',
        author: 'omar',
        sourceBranch: 'fix/auth',
        targetBranch: 'main',
        additions: 12,
        deletions: 3,
        changedFiles: 2,
        ciState: 'failing',
        failingChecks: ['go test'],
        mergeabilityState: 'conflicting',
        mergeReasons: ['behind_base'],
      ),
    );

    expect(find.text('Fix auth timeouts on refresh'), findsOneWidget);
    expect(find.text('fix/auth → main · omar'), findsOneWidget);
    expect(find.text('2 files'), findsOneWidget);
    expect(find.text('+12'), findsOneWidget);
    expect(find.text('−3'), findsOneWidget);
    expect(find.text('go test · branch behind base'), findsOneWidget);
  });

  testWidgets('offers no session action, because no session screen exists yet', (tester) async {
    await pumpCard(tester);

    expect(find.byTooltip('Open session'), findsNothing);
    expect(find.byTooltip('Open in GitHub'), findsOneWidget);
  });
}
