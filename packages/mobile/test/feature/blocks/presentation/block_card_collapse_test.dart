import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';
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

    expect(tester.widget<DisclosureChevron>(find.byType(DisclosureChevron)).expanded, isTrue);
  });

  testWidgets('renders the right chevron when collapsed', (tester) async {
    await _pump(
      tester,
      block: _shell('b-1'),
      collapsed: true,
      onToggleCollapse: () {},
    );

    final chevron = tester.widget<DisclosureChevron>(find.byType(DisclosureChevron));
    expect(chevron.expanded, isFalse);
    expect(chevron.collapsedTurns, -0.25);
    expect(chevron.expandedTurns, 0);
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

    expect(find.byType(DisclosureChevron), findsNothing);
  });

  testWidgets('calls onToggleCollapse when the header is tapped', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      block: _shell('b-1'),
      onToggleCollapse: () => taps++,
    );

    await tester.tap(find.byType(DisclosureChevron));
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

    await tester.tap(find.byType(DisclosureChevron));
    await tester.pump();
    await tester.tap(find.byType(DisclosureChevron));
    await tester.pump();

    expect(taps, 2);
  });

  group('animated disclosure', () {
    final haptics = <String>[];

    setUp(() {
      haptics.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    Future<void> toggleHost(WidgetTester tester, SessionBlock block) async {
      var collapsed = true;
      await tester.pumpWidget(
        SkinScope(
          skin: const DarkSkin(),
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, _) => MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 400,
                  child: StatefulBuilder(
                    builder: (context, setState) => BlockCard(
                      block: block,
                      collapsed: collapsed,
                      onToggleCollapse: () => setState(() => collapsed = !collapsed),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    double bodyHeight(WidgetTester tester, Finder inside) =>
        tester.getSize(find.ancestor(of: inside, matching: find.byType(Disclosure)).first).height;

    testWidgets('a tool body grows and shrinks over the disclosure duration with a haptic', (tester) async {
      await toggleHost(tester, _shell('b-1'));
      expect(find.text('ls'), findsNothing);

      await tester.tap(find.byType(DisclosureChevron));
      await tester.pump();
      await tester.pump(AppMotion.disclosure ~/ 2);
      final opening = bodyHeight(tester, find.text('ls'));
      await tester.pumpAndSettle();
      final full = bodyHeight(tester, find.text('ls'));
      expect(opening, greaterThan(0));
      expect(opening, lessThan(full));
      expect(haptics, ['HapticFeedbackType.selectionClick']);

      await tester.tap(find.byType(DisclosureChevron));
      await tester.pump();
      await tester.pump(AppMotion.disclosure ~/ 2);
      final closing = bodyHeight(tester, find.text('ls'));
      expect(closing, greaterThan(0));
      expect(closing, lessThan(full));
      await tester.pumpAndSettle();
      expect(find.text('ls'), findsNothing);
      expect(haptics, hasLength(2));
    });

    testWidgets('a reasoning body grows over the disclosure duration with a haptic', (tester) async {
      const reasoning = SessionBlock(
        id: 'r-1',
        firstSeq: 1,
        lastSeq: 1,
        kind: BlockKind.reasoning,
        status: BlockStatus.ok,
        title: 'Thinking',
        body: 'first thought\nsecond thought\nthird thought',
      );
      await toggleHost(tester, reasoning);
      expect(find.textContaining('second thought'), findsNothing);
      final chevron = tester.widget<DisclosureChevron>(find.byType(DisclosureChevron));
      expect(chevron.expanded, isFalse);

      await tester.tap(find.byType(DisclosureChevron));
      await tester.pump();
      await tester.pump(AppMotion.disclosure ~/ 2);
      final opening = bodyHeight(tester, find.textContaining('second thought'));
      await tester.pumpAndSettle();
      final full = bodyHeight(tester, find.textContaining('second thought'));
      expect(opening, greaterThan(0));
      expect(opening, lessThan(full));
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(tester.widget<DisclosureChevron>(find.byType(DisclosureChevron)).expanded, isTrue);
    });
  });
}
