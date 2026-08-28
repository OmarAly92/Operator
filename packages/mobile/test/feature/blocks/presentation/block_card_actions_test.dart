import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

SessionBlock _permission(String id) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.permission,
  status: BlockStatus.blocked,
  title: 'Permission requested',
  body: 'Bash',
  truncatedLines: 0,
  redacted: false,
);

Future<void> _pump(
  WidgetTester tester, {
  required SessionBlock block,
  BlockPermissionKind? permissionKind,
  void Function(String, String)? onApprove,
  void Function(String, String)? onDecline,
  void Function(String)? onAnswer,
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
                child: BlockCard(
                  block: block,
                  onAnswer: onAnswer,
                  onApprove: onApprove,
                  onDecline: onDecline,
                  permissionKind: permissionKind,
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders approve and deny for an approval permission block', (tester) async {
    await _pump(
      tester,
      block: _permission('req-1'),
      permissionKind: BlockPermissionKind.approval,
      onApprove: (_, _) {},
      onDecline: (_, _) {},
    );

    expect(find.byKey(const ValueKey('block-approve')), findsOneWidget);
    expect(find.byKey(const ValueKey('block-decline')), findsOneWidget);
  });

  testWidgets('hides approve and deny when onApprove and onDecline are not provided', (tester) async {
    await _pump(
      tester,
      block: _permission('req-1'),
      permissionKind: BlockPermissionKind.approval,
    );

    expect(find.byKey(const ValueKey('block-approve')), findsNothing);
    expect(find.byKey(const ValueKey('block-decline')), findsNothing);
  });

  testWidgets('hides approve and deny when permissionKind is not approval', (tester) async {
    await _pump(
      tester,
      block: _permission('req-1'),
      permissionKind: BlockPermissionKind.userInput,
      onApprove: (_, _) {},
      onDecline: (_, _) {},
    );

    expect(find.byKey(const ValueKey('block-approve')), findsNothing);
    expect(find.byKey(const ValueKey('block-decline')), findsNothing);
  });

  testWidgets('renders the answer button for a user_input permission block', (tester) async {
    await _pump(
      tester,
      block: _permission('req-1'),
      permissionKind: BlockPermissionKind.userInput,
      onAnswer: (_) {},
    );

    expect(find.byKey(const ValueKey('block-answer')), findsOneWidget);
  });

  testWidgets('hides the answer button when onAnswer is not provided', (tester) async {
    await _pump(
      tester,
      block: _permission('req-1'),
      permissionKind: BlockPermissionKind.userInput,
    );

    expect(find.byKey(const ValueKey('block-answer')), findsNothing);
  });

  testWidgets('hides the answer button when permissionKind is not user_input', (tester) async {
    await _pump(
      tester,
      block: _permission('req-1'),
      permissionKind: BlockPermissionKind.approval,
      onAnswer: (_) {},
    );

    expect(find.byKey(const ValueKey('block-answer')), findsNothing);
  });

  testWidgets('hides all action buttons when the block is not blocked', (tester) async {
    final block = SessionBlock(
      id: 'req-1',
      firstSeq: 1,
      lastSeq: 1,
      kind: BlockKind.permission,
      status: BlockStatus.ok,
      title: 'Permission requested',
      body: 'Bash',
      truncatedLines: 0,
      redacted: false,
    );
    await _pump(
      tester,
      block: block,
      permissionKind: BlockPermissionKind.approval,
      onApprove: (_, _) {},
      onDecline: (_, _) {},
      onAnswer: (_) {},
    );

    expect(find.byKey(const ValueKey('block-approve')), findsNothing);
    expect(find.byKey(const ValueKey('block-decline')), findsNothing);
    expect(find.byKey(const ValueKey('block-answer')), findsNothing);
  });

  testWidgets('approves with the request id and the approve decision', (tester) async {
    String? capturedRequestId;
    String? capturedDecisionId;
    await _pump(
      tester,
      block: _permission('req-1'),
      permissionKind: BlockPermissionKind.approval,
      onApprove: (requestId, decisionId) {
        capturedRequestId = requestId;
        capturedDecisionId = decisionId;
      },
    );

    await tester.tap(find.byKey(const ValueKey('block-approve')));
    await tester.pump();

    expect(capturedRequestId, 'req-1');
    expect(capturedDecisionId, 'approve');
  });

  testWidgets('declines with the decline decision', (tester) async {
    String? capturedDecisionId;
    await _pump(
      tester,
      block: _permission('req-1'),
      permissionKind: BlockPermissionKind.approval,
      onDecline: (_, decisionId) {
        capturedDecisionId = decisionId;
      },
    );

    await tester.tap(find.byKey(const ValueKey('block-decline')));
    await tester.pump();

    expect(capturedDecisionId, 'decline');
  });

  testWidgets('answers with the request id', (tester) async {
    String? capturedRequestId;
    await _pump(
      tester,
      block: _permission('req-1'),
      permissionKind: BlockPermissionKind.userInput,
      onAnswer: (requestId) {
        capturedRequestId = requestId;
      },
    );

    await tester.tap(find.byKey(const ValueKey('block-answer')));
    await tester.pump();

    expect(capturedRequestId, 'req-1');
  });
}
