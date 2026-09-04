import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

Widget _host(SessionBlock block) => SkinScope(
  skin: const DarkSkin(),
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: BlockCard(block: block))),
    ),
  ),
);

SessionBlock _base({
  required String id,
  required BlockKind kind,
  String title = 'Tool',
  String body = '',
  String? result,
  BlockDetail? detail,
}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: kind,
  status: BlockStatus.ok,
  title: title,
  body: body,
  result: result,
  detail: detail,
);

void main() {
  testWidgets('a tool block shows its input and its result separately', (tester) async {
    await tester.pumpWidget(
      _host(_base(id: 'b-1', kind: BlockKind.tool, title: 'Bash', body: 'go test ./...', result: 'ok 42 tests')),
    );

    expect(find.text('go test ./...'), findsOneWidget);
    expect(find.text('ok 42 tests'), findsOneWidget);
  });

  testWidgets('a long result is collapsed behind a toggle', (tester) async {
    final long = List.generate(40, (index) => 'line $index').join('\n');
    await tester.pumpWidget(_host(_base(id: 'b-2', kind: BlockKind.tool, result: long)));

    expect(find.text('Show full result'), findsOneWidget);
    expect(find.text('line 39'), findsNothing);

    await tester.tap(find.text('Show full result'));
    await tester.pumpAndSettle();

    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('a question block lists every option', (tester) async {
    await tester.pumpWidget(
      _host(
        _base(
          id: 'b-3',
          kind: BlockKind.notice,
          title: 'Which branch?',
          detail: const QuestionBlockDetail(
            questions: [
              BlockQuestion(
                question: 'Which branch?',
                header: 'Branch',
                multiSelect: false,
                options: [
                  BlockQuestionOption(label: 'main', description: 'the default branch'),
                  BlockQuestionOption(label: 'develop', description: 'the integration branch'),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('main'), findsOneWidget);
    expect(find.text('develop'), findsOneWidget);
    expect(find.text('the default branch'), findsOneWidget);
    expect(find.text('Answer in the terminal'), findsOneWidget);
  });

  testWidgets('a todo block renders a checklist', (tester) async {
    await tester.pumpWidget(
      _host(
        _base(
          id: 'b-4',
          kind: BlockKind.todo,
          title: 'Todo',
          body: '{"todos":[{"content":"Rename the branch","status":"completed"},'
              '{"content":"Push it","status":"pending"}]}',
        ),
      ),
    );

    expect(find.text('Rename the branch'), findsOneWidget);
    expect(find.text('Push it'), findsOneWidget);
  });

  testWidgets('a todo block that is not a todo payload falls back to its text', (tester) async {
    await tester.pumpWidget(_host(_base(id: 'b-5', kind: BlockKind.todo, title: 'Todo', body: 'plain text')));

    expect(find.text('plain text'), findsOneWidget);
  });
}
