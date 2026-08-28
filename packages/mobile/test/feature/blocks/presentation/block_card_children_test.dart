import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

SessionBlock _child(String id, String command, String output) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.tool,
  status: BlockStatus.ok,
  title: 'Shell',
  body: output,
  truncatedLines: 0,
  redacted: false,
  detail: ShellBlockDetail(command: command, output: output, exitCode: 0),
);

SessionBlock _parent(List<SessionBlock> children) => SessionBlock(
  id: 'a-parent',
  firstSeq: 2,
  lastSeq: 6,
  kind: BlockKind.tool,
  status: BlockStatus.ok,
  title: 'agent/subagent',
  body: 'done',
  truncatedLines: 0,
  redacted: false,
  detail: McpToolBlockDetail(
    server: 'agent',
    tool: 'subagent',
    args: const {'task': 'explore'},
    result: 'done',
  ),
  children: children,
);

Future<void> _pump(WidgetTester tester, {required SessionBlock block}) =>
    tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: BlockCard(block: block),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders a child BlockCard with the child summary when a parent has children', (tester) async {
    await _pump(
      tester,
      block: _parent([_child('a-child-1', 'ls', 'file.txt')]),
    );

    expect(find.byKey(const ValueKey('child-a-child-1')), findsOneWidget);
    expect(find.textContaining('file.txt'), findsWidgets);
  });

  testWidgets('renders multiple child BlockCards in order', (tester) async {
    await _pump(
      tester,
      block: _parent([
        _child('a-child-1', 'ls', 'file.txt'),
        _child('a-child-2', 'cat file.txt', 'hello'),
      ]),
    );

    expect(find.byKey(const ValueKey('child-a-child-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('child-a-child-2')), findsOneWidget);
    expect(find.textContaining('file.txt'), findsWidgets);
    expect(find.textContaining('hello'), findsWidgets);
  });

  testWidgets('does not render child cards when the parent has no children', (tester) async {
    await _pump(tester, block: _parent(const <SessionBlock>[]));

    expect(find.byKey(const ValueKey('child-a-child-1')), findsNothing);
  });
}
