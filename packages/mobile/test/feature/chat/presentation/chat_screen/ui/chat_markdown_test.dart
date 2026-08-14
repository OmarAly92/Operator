import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_markdown.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders prose, headings and list markers', (tester) async {
    await pump(
      tester,
      const ChatMarkdown(text: '# Findings\n\nAll good\n\n- one\n- two'),
    );

    expect(find.text('Findings'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
  });

  testWidgets(
    'renders a fenced code block with its language and a copy control',
    (tester) async {
      await pump(
        tester,
        const ChatMarkdown(text: '```dart\nvoid main() {}\n```'),
      );

      expect(find.text('DART'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.textContaining('void main()'), findsOneWidget);
    },
  );

  testWidgets('marks completed task items', (tester) async {
    await pump(tester, const ChatMarkdown(text: '- [x] inspect\n- [ ] test'));

    expect(find.text('☑'), findsOneWidget);
    expect(find.text('☐'), findsOneWidget);
  });

  testWidgets('renders a table without overflowing the page', (tester) async {
    await pump(
      tester,
      const ChatMarkdown(
        text: '| File | State |\n| --- | --- |\n| app.ts | changed |',
      ),
    );

    expect(find.text('File'), findsOneWidget);
    expect(find.text('app.ts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a streaming placeholder rather than an empty bubble', (
    tester,
  ) async {
    await pump(tester, const ChatMarkdown(text: '…', streaming: true));
    expect(find.text('…'), findsOneWidget);
  });
}
