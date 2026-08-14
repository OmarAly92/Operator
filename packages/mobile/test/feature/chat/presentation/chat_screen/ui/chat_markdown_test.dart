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

  testWidgets('keeps rendered markdown content selectable', (tester) async {
    await pump(
      tester,
      const ChatMarkdown(
        text:
            '# Findings\n\n- inspect\n\n> quoted\n\n| File | State |\n| --- | --- |\n| app.ts | changed |\n\n![result](https://example.com/result.png)',
      ),
    );

    for (final value in ['Findings', 'inspect', 'quoted', 'File', 'app.ts']) {
      expect(
        find.ancestor(
          of: find.text(value),
          matching: find.byType(SelectableText),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.ancestor(
        of: find.textContaining('Image unavailable: result'),
        matching: find.byType(SelectableText),
      ),
      findsOneWidget,
    );
  });

  testWidgets('seeds later code blocks with the shared wrap preference', (
    tester,
  ) async {
    await pump(
      tester,
      const ChatMarkdown(key: ValueKey('first'), text: '```dart\nfirst\n```'),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Wrap'));
    await tester.pump();

    await pump(
      tester,
      const ChatMarkdown(key: ValueKey('second'), text: '```dart\nsecond\n```'),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );
    await tester.tap(find.text('Wrap'));
    await tester.pump();
  });

  testWidgets('rebuilds linked prose without recognizer exceptions', (
    tester,
  ) async {
    await pump(
      tester,
      const ChatMarkdown(text: '[first](https://example.com/first)'),
    );
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ChatMarkdown(
                  text: '[second](https://example.com/second)',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
