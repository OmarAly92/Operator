import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

SessionBlock _shell(String id, {String summary = 'hello world'}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.tool,
  status: BlockStatus.ok,
  title: 'Shell',
  body: summary,
  truncatedLines: 0,
  redacted: false,
  detail: const ShellBlockDetail(command: 'ls', output: 'hello world', exitCode: 0),
);

Future<void> _pump(
  WidgetTester tester, {
  required SessionBlock block,
  bool collapsed = false,
  VoidCallback? onToggleCollapse,
}) => tester.pumpWidget(
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
              collapsed: collapsed,
              onToggleCollapse: onToggleCollapse,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('renders the expand chevron when not collapsed', (tester) async {
    await _pump(
      tester,
      block: _shell('b-1'),
      onToggleCollapse: () {},
    );

    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('renders the right chevron when collapsed', (tester) async {
    await _pump(
      tester,
      block: _shell('b-1'),
      collapsed: true,
      onToggleCollapse: () {},
    );

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('hides the body when collapsed', (tester) async {
    await _pump(
      tester,
      block: _shell('b-1'),
      collapsed: true,
      onToggleCollapse: () {},
    );

    expect(find.textContaining('hello world'), findsNothing);
  });

  testWidgets('shows the body when not collapsed', (tester) async {
    await _pump(
      tester,
      block: _shell('b-1'),
      onToggleCollapse: () {},
    );

    expect(find.textContaining('hello world'), findsWidgets);
  });

  testWidgets('does not render the chevron when onToggleCollapse is null', (tester) async {
    await _pump(tester, block: _shell('b-1'));

    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('calls onToggleCollapse when the header is tapped', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      block: _shell('b-1'),
      onToggleCollapse: () => taps++,
    );

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('tapping the header a second time still fires the callback', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      block: _shell('b-1'),
      onToggleCollapse: () => taps++,
    );

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();

    expect(taps, 2);
  });
}
