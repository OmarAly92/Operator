import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';
import 'package:operator_mobile/core/widgets/motion/shimmer.dart';
import 'package:operator_mobile/feature/blocks/logic/block_find.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/thinking_row.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/tool_group_header.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/turn_fold_row.dart';

import 'block_list_test.dart' show block, pumpList;

String _at(int seconds) => DateTime.utc(2026, 8, 28, 10).add(Duration(seconds: seconds)).toIso8601String();

List<SessionBlock> _turn(int base, {int tools = 2, int toolLines = 1, int replyLines = 1, int startSecond = 0}) => [
  block(base, kind: BlockKind.prompt, createdAt: _at(startSecond)),
  for (var index = 1; index <= tools; index++)
    block(base + index, kind: BlockKind.tool, lines: toolLines, createdAt: _at(startSecond + index)),
  block(base + tools + 1, kind: BlockKind.assistant, lines: replyLines, createdAt: _at(startSecond + 13)),
];

double _height(WidgetTester tester, Finder inside) =>
    tester.getSize(find.ancestor(of: inside, matching: find.byType(Disclosure)).first).height;

BlockListState _list(WidgetTester tester) => tester.state<BlockListState>(find.byType(BlockList));

void main() {
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

  group('turn fold', () {
    testWidgets('a settled turn is folded by default behind its duration', (tester) async {
      await pumpList(tester, _turn(1));

      expect(find.text('Worked for 13s'), findsOneWidget);
      expect(find.text('Used 2 tools'), findsNothing);
      expect(find.text('line 0 of block 1'), findsOneWidget);
      expect(find.text('line 0 of block 4'), findsOneWidget);
      final row = tester.getRect(find.byType(TurnFoldRow));
      final reply = tester.getRect(find.text('line 0 of block 4'));
      expect(row.bottom, lessThanOrEqualTo(reply.top));
    });

    testWidgets('a running turn is never folded', (tester) async {
      await pumpList(tester, _turn(1), sessionActive: true);

      expect(find.byType(TurnFoldRow), findsNothing);
      expect(find.text('Used 2 tools'), findsOneWidget);
    });

    testWidgets('tapping expands the turn and tapping again folds it, both animated', (tester) async {
      await pumpList(tester, _turn(1));

      await tester.tap(find.text('Worked for 13s'));
      await tester.pump();
      await tester.pump(AppMotion.disclosure ~/ 2);
      final opening = _height(tester, find.text('Used 2 tools'));
      await tester.pumpAndSettle();
      final full = _height(tester, find.text('Used 2 tools'));
      expect(opening, greaterThan(0));
      expect(opening, lessThan(full));
      expect(haptics, ['HapticFeedbackType.selectionClick']);

      await tester.tap(find.text('Worked for 13s'));
      await tester.pump();
      await tester.pump(AppMotion.disclosure ~/ 2);
      final closing = _height(tester, find.text('Used 2 tools'));
      expect(closing, greaterThan(0));
      expect(closing, lessThan(full));
      await tester.pumpAndSettle();
      expect(find.text('Used 2 tools'), findsNothing);
      expect(haptics, hasLength(2));
    });

    testWidgets('the fold state survives a rebuild with new blocks', (tester) async {
      final harness = await pumpList(tester, _turn(1));
      await tester.tap(find.text('Worked for 13s'));
      await tester.pumpAndSettle();

      harness.append(_turn(10, startSecond: 60));
      await tester.pumpAndSettle();
      _list(tester).jumpToLatest();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
      await tester.pumpAndSettle();

      expect(find.text('Used 2 tools'), findsOneWidget);
      expect(find.byType(TurnFoldRow), findsNWidgets(2));
    });

    testWidgets('the fold state survives scrolling away and back', (tester) async {
      await pumpList(tester, [..._turn(1), ..._turn(10, tools: 1, replyLines: 400, startSecond: 60)]);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 100000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Worked for 13s').first);
      await tester.pumpAndSettle();
      expect(find.text('Used 2 tools'), findsOneWidget);

      _list(tester).jumpToLatest();
      await tester.pumpAndSettle();
      expect(find.text('Used 2 tools'), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 100000));
      await tester.pumpAndSettle();

      expect(find.text('Used 2 tools'), findsOneWidget);
    });

    testWidgets('find moving into a folded turn expands it', (tester) async {
      final blocks = _turn(1);
      final harness = await pumpList(tester, blocks);
      final matches = BlockFind.matches(blocks, 'Bash 2');

      harness.findMatch('seq-2', {for (final match in matches) match.blockId: match});
      await tester.pumpAndSettle();

      expect(find.text('Bash 2', findRichText: true), findsOneWidget);
      expect(tester.getSize(find.ancestor(of: find.text('Bash 2', findRichText: true), matching: find.byType(Disclosure)).first).height, greaterThan(0));
    });

    testWidgets('selection mode shows every block', (tester) async {
      final harness = await pumpList(tester, _turn(1));

      harness.select(true);
      await tester.pumpAndSettle();

      expect(find.byType(TurnFoldRow), findsNothing);
      expect(find.text('Bash 2'), findsOneWidget);
      expect(find.text('Bash 3'), findsOneWidget);
    });

    testWidgets('a turn settling while pinned folds and stays pinned', (tester) async {
      final pinned = ValueNotifier<bool>(true);
      final harness = await pumpList(tester, _turn(1, tools: 12, replyLines: 3), sessionActive: true, pinned: pinned);
      expect(find.byType(TurnFoldRow), findsNothing);

      harness.replace(harness.blocks, active: false);
      await tester.pumpAndSettle();

      expect(find.text('Worked for 13s'), findsOneWidget);
      final position = _list(tester).controller.position;
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
      expect(pinned.value, isTrue);
    });

    testWidgets('toggling a fold while pinned at the bottom keeps the list pinned', (tester) async {
      final pinned = ValueNotifier<bool>(true);
      final seen = <bool>[];
      pinned.addListener(() => seen.add(pinned.value));
      await pumpList(tester, [..._turn(1, tools: 12, toolLines: 3, replyLines: 2)], pinned: pinned);
      final position = _list(tester).controller.position;
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));

      await tester.tap(find.text('Worked for 13s'));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
      expect(pinned.value, isTrue);
      expect(seen.where((value) => !value), isEmpty);

      await tester.tap(find.text('Worked for 13s'));
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
      expect(pinned.value, isTrue);
    });

    testWidgets('expanding a fold while scrolled up keeps the row where it was tapped', (tester) async {
      await pumpList(tester, [..._turn(1, tools: 6), ..._turn(20, tools: 1, replyLines: 400, startSecond: 60)]);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 100000));
      await tester.pumpAndSettle();
      final before = tester.getRect(find.text('Worked for 13s').first).top;

      await tester.tap(find.text('Worked for 13s').first);
      await tester.pump();
      await tester.pump(AppMotion.disclosure ~/ 2);
      expect(tester.getRect(find.text('Worked for 13s').first).top, closeTo(before, 1));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Worked for 13s').first).top, closeTo(before, 1));
    });
  });

  group('tool group disclosure', () {
    testWidgets('collapsing and expanding a tool group animates with a haptic', (tester) async {
      await pumpList(tester, [block(1, kind: BlockKind.tool), block(2, kind: BlockKind.tool)]);
      final full = _height(tester, find.text('Bash 1'));
      final chevron = tester.widget<DisclosureChevron>(
        find.descendant(of: find.byType(ToolGroupHeader), matching: find.byType(DisclosureChevron)),
      );
      expect(chevron.expanded, isTrue);

      await tester.tap(find.text('Used 2 tools'));
      await tester.pump();
      await tester.pump(AppMotion.disclosure ~/ 2);
      final closing = _height(tester, find.text('Bash 1'));
      expect(closing, greaterThan(0));
      expect(closing, lessThan(full));
      await tester.pumpAndSettle();
      expect(find.text('Bash 1'), findsNothing);
      expect(haptics, ['HapticFeedbackType.selectionClick']);

      await tester.tap(find.text('Used 2 tools'));
      await tester.pump();
      await tester.pump(AppMotion.disclosure ~/ 2);
      final opening = _height(tester, find.text('Bash 1'));
      expect(opening, greaterThan(0));
      expect(opening, lessThan(full));
      await tester.pumpAndSettle();
      expect(_height(tester, find.text('Bash 1')), full);
      expect(haptics, hasLength(2));
    });
  });

  group('thinking row', () {
    testWidgets('shows while the running turn has streamed nothing since the prompt', (tester) async {
      await pumpList(tester, [block(1, kind: BlockKind.prompt)], sessionActive: true, settle: false);

      expect(find.byType(ThinkingRow), findsOneWidget);
      expect(find.text('Thinking'), findsOneWidget);
      final row = tester.getRect(find.text('Thinking'));
      final prompt = tester.getRect(find.text('line 0 of block 1'));
      expect(row.top, greaterThan(prompt.bottom));
    });

    testWidgets('shows while the latest block is reasoning', (tester) async {
      await pumpList(
        tester,
        [block(1, kind: BlockKind.prompt), block(2, kind: BlockKind.reasoning, status: BlockStatus.running)],
        sessionActive: true,
        settle: false,
      );

      expect(find.text('Thinking'), findsOneWidget);
    });

    testWidgets('hides once a non-reasoning block streams', (tester) async {
      final harness = await pumpList(tester, [block(1, kind: BlockKind.prompt)], sessionActive: true, settle: false);

      harness.append([block(2, kind: BlockKind.tool, status: BlockStatus.running)]);
      await tester.pump();
      await tester.pump(AppMotion.disclosure);
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.text('Thinking'), findsNothing);
    });

    testWidgets('does not show for a settled session', (tester) async {
      await pumpList(tester, [block(1, kind: BlockKind.prompt)]);

      expect(find.text('Thinking'), findsNothing);
    });

    testWidgets('its shimmer stops under reduce motion', (tester) async {
      await pumpList(tester, [block(1, kind: BlockKind.prompt)], sessionActive: true, settle: false);
      expect(find.descendant(of: find.byType(Shimmer), matching: find.byType(ShaderMask)), findsOneWidget);

      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pump();
      await tester.pump();

      expect(find.text('Thinking'), findsOneWidget);
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });

    testWidgets('appearing while pinned keeps the list pinned to the new tail', (tester) async {
      final pinned = ValueNotifier<bool>(true);
      final harness = await pumpList(tester, _turn(1, tools: 1, replyLines: 60), sessionActive: true, pinned: pinned);

      harness.append([block(10, kind: BlockKind.prompt)]);
      await tester.pump();
      for (var frame = 0; frame < 16; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final position = _list(tester).controller.position;
      expect(find.text('Thinking'), findsOneWidget);
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
      expect(pinned.value, isTrue);
    });
  });
}
