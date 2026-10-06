import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/ui/widgets/notification_row.dart';

void main() {
  final hoursAgo = DateTime.now().subtract(const Duration(hours: 5)).toUtc().toIso8601String();

  Future<void> pumpRows(WidgetTester tester, List<NotificationRow> rows) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(body: Column(children: rows)),
          ),
        ),
      ),
    );
  }

  NotificationRow row(String title, {bool unread = false, String body = ''}) => NotificationRow(
        type: 'turn_finished',
        title: title,
        body: body,
        createdAt: hoursAgo,
        unread: unread,
        onTap: () {},
      );

  testWidgets('a long title uses the width up to the time column', (tester) async {
    await pumpRows(tester, [row('Improve code finished a long turn with many changes to review')]);
    final title = tester.getRect(find.textContaining('Improve code'));
    final stamp = tester.getRect(find.byKey(NotificationRow.stampKey));
    expect(stamp.left - title.right, lessThanOrEqualTo(8.5));
    expect(title.width, greaterThan(200));
  });

  testWidgets('the time column lines up whatever the title length', (tester) async {
    await pumpRows(tester, [
      row('hi'),
      row('Improve code finished a long turn with many changes to review', unread: true),
    ]);
    final stamps = [for (final e in find.byKey(NotificationRow.stampKey).evaluate()) tester.getRect(find.byWidget(e.widget))];
    expect(stamps, hasLength(2));
    expect(stamps.first.right, stamps.last.right);
  });

  testWidgets('the preview shows plain text, not markdown', (tester) async {
    await pumpRows(tester, [row('Done', body: 'Wrote **`spec.md`** and ran `flutter test`')]);
    expect(find.text('Wrote spec.md and ran flutter test'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('`'), findsNothing);
  });
}
