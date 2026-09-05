import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/usage/data/model/usage_quota_model.dart';
import 'package:operator_mobile/feature/usage/presentation/usage_screen/ui/widgets/quota_section.dart';

Widget _wrap(Widget child) => SkinScope(
  skin: const DarkSkin(),
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
  ),
);

void main() {
  testWidgets('names the harness and says Claude is not reported', (tester) async {
    await tester.pumpWidget(_wrap(QuotaSection(quota: UsageQuotaModel.fromJson(const {
      'harness': 'codex', 'planType': 'plus',
      'windows': [
        {'kind': 'primary', 'windowMinutes': 300, 'usedPercent': 77, 'stale': false},
      ],
    }))));
    expect(find.text('Codex plan usage'), findsOneWidget);
    expect(find.text('5-hour window'), findsOneWidget);
    expect(find.text('77%'), findsOneWidget);
    expect(find.textContaining('Claude Code'), findsOneWidget);
    expect(find.textContaining('not reported'), findsOneWidget);
  });

  testWidgets('shows a stale window as unknown with a last-seen time and no bar', (tester) async {
    final observedAt = DateTime.now().subtract(const Duration(minutes: 10));
    await tester.pumpWidget(_wrap(QuotaSection(quota: UsageQuotaModel.fromJson({
      'harness': 'codex', 'planType': 'plus',
      'observedAt': observedAt.toIso8601String(),
      'windows': [
        {'kind': 'primary', 'windowMinutes': 300, 'usedPercent': 77, 'stale': true},
      ],
    }))));
    expect(find.text('Unknown — last seen 10m'), findsOneWidget);
    expect(find.text('77%'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('renders nothing when quota was never observed', (tester) async {
    await tester.pumpWidget(_wrap(const QuotaSection(quota: null)));
    expect(find.text('Codex plan usage'), findsNothing);
  });
}
