import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/turn_group_status.dart';

TurnGroup _group({String? turnId = 't-1', bool running = false}) => TurnGroup(
  turnId: turnId,
  blocks: const [],
  running: running,
);

Future<void> _pump(
  WidgetTester tester, {
  required TurnGroup group,
  void Function(String turnId)? onRollback,
}) =>
    tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 200,
                child: TurnGroupStatus(group: group, onRollback: onRollback),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows a rollback button when onRollback is provided and turnId is set', (tester) async {
    String? capturedTurnId;
    await _pump(
      tester,
      group: _group(),
      onRollback: (turnId) {
        capturedTurnId = turnId;
      },
    );

    final button = find.byKey(const ValueKey('turn-rollback'));
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();

    expect(capturedTurnId, 't-1');
  });

  testWidgets('hides the rollback button when onRollback is not provided', (tester) async {
    await _pump(tester, group: _group());

    expect(find.byKey(const ValueKey('turn-rollback')), findsNothing);
  });

  testWidgets('hides the rollback button when the group has no turnId', (tester) async {
    await _pump(
      tester,
      group: _group(turnId: null),
      onRollback: (_) {},
    );

    expect(find.byKey(const ValueKey('turn-rollback')), findsNothing);
  });
}
