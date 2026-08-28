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

SessionBlock _prompt(String id) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.prompt,
  status: BlockStatus.ok,
  title: 'Prompt',
  body: 'run the tests',
  truncatedLines: 0,
  redacted: false,
);

Future<void> _pump(
  WidgetTester tester, {
  required SessionBlock block,
  Widget? Function(SessionBlock block)? actionsBuilder,
}) => tester.pumpWidget(
  SkinScope(
    skin: const DarkSkin(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: BlockCard(block: block, actionsBuilder: actionsBuilder),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('renders whatever the caller supplies for a block', (tester) async {
    await _pump(
      tester,
      block: _permission('req-1'),
      actionsBuilder: (_) => const Text('Allow once'),
    );

    expect(find.text('Allow once'), findsOneWidget);
  });

  testWidgets('draws nothing when the caller supplies no builder', (tester) async {
    await _pump(tester, block: _permission('req-1'));

    expect(find.byType(BlockActionButton), findsNothing);
  });

  testWidgets('draws nothing when the caller returns null for this block', (tester) async {
    await _pump(tester, block: _permission('req-1'), actionsBuilder: (_) => null);

    expect(find.byType(BlockActionButton), findsNothing);
  });

  testWidgets('passes each block to the caller so it can decide per block', (tester) async {
    final seen = <String>[];
    await _pump(
      tester,
      block: _prompt('p-1'),
      actionsBuilder: (block) {
        seen.add(block.id);
        return null;
      },
    );

    expect(seen, contains('p-1'));
  });

  testWidgets('wires the caller\'s tap handler', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      block: _permission('req-1'),
      actionsBuilder: (_) => BlockActionButton(
        key: const ValueKey('allow'),
        label: 'Allow',
        onTap: () => taps++,
        primary: true,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('allow')));
    expect(taps, 1);
  });
}
