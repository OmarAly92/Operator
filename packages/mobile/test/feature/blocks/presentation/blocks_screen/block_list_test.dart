import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/search/text_match.dart';
import 'package:operator_mobile/feature/blocks/logic/block_find.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart';

SessionBlock block(
  int seq, {
  int lines = 1,
  BlockKind kind = BlockKind.tool,
  BlockStatus status = BlockStatus.ok,
  String? createdAt,
}) => SessionBlock(
  id: 'seq-$seq',
  firstSeq: seq,
  lastSeq: seq,
  kind: kind,
  status: status,
  title: 'Bash $seq',
  body: List.generate(lines, (line) => 'line $line of block $seq').join('\n'),
  createdAt: createdAt,
);

List<SessionBlock> range(int from, int to, {int Function(int)? lines}) => [
  for (var seq = from; seq <= to; seq++)
    block(seq, lines: lines?.call(seq) ?? 1),
];

class ListHarness extends StatefulWidget {
  const ListHarness({
    super.key,
    required this.initial,
    this.sessionId = 's-1',
    this.sticky,
    this.pinned,
    this.highlights = const {},
  });

  final List<SessionBlock> initial;
  final String sessionId;
  final ValueNotifier<StickyBlock?>? sticky;
  final ValueNotifier<bool>? pinned;
  final Map<String, BlockMatch> highlights;

  @override
  State<ListHarness> createState() => ListHarnessState();
}

class ListHarnessState extends State<ListHarness> {
  late List<SessionBlock> blocks = widget.initial;
  late String sessionId = widget.sessionId;

  void prepend(List<SessionBlock> older) =>
      setState(() => blocks = [...older, ...blocks]);

  void append(List<SessionBlock> newer) =>
      setState(() => blocks = [...blocks, ...newer]);

  void switchSession(String id, List<SessionBlock> next) => setState(() {
    sessionId = id;
    blocks = next;
  });

  void grow(String id, int lines) => setState(() {
    blocks = [
      for (final item in blocks)
        if (item.id == id) block(item.firstSeq, lines: lines) else item,
    ];
  });

  @override
  Widget build(BuildContext context) => BlockList(
    key: const ValueKey('list'),
    sessionId: sessionId,
    blocks: blocks,
    sticky: widget.sticky,
    pinnedListenable: widget.pinned,
    highlights: widget.highlights,
  );
}

Future<ListHarnessState> pumpList(
  WidgetTester tester,
  List<SessionBlock> blocks, {
  ValueNotifier<StickyBlock?>? sticky,
  ValueNotifier<bool>? pinned,
  bool renderStickyHeader = true,
  Map<String, BlockMatch> highlights = const {},
}) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 390,
                height: 600,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ListHarness(
                        initial: blocks,
                        sticky: sticky,
                        pinned: pinned,
                        highlights: highlights,
                      ),
                    ),
                    if (sticky != null && renderStickyHeader)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: StickyBlockHeader(sticky: sticky),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<ListHarnessState>(find.byType(ListHarness));
}

void main() {
  testWidgets('renders one card per block', (tester) async {
    await pumpList(tester, range(1, 3));

    expect(find.byType(BlockCard), findsNWidgets(3));
    expect(find.text('Bash 1'), findsOneWidget);
    expect(find.text('Bash 3'), findsOneWidget);
  });

  testWidgets('renders finished and running turn group status', (tester) async {
    await pumpList(tester, [
      block(1, kind: BlockKind.prompt, createdAt: '2026-08-28T10:00:00Z'),
      block(2, kind: BlockKind.assistant, createdAt: '2026-08-28T10:00:05Z'),
      block(
        3,
        kind: BlockKind.prompt,
        status: BlockStatus.running,
        createdAt: '2026-08-28T10:01:00Z',
      ),
    ]);

    expect(find.text('FINISHED · 5s'), findsOneWidget);
    expect(find.textContaining('RUNNING'), findsOneWidget);
  });

  testWidgets('builds only a window of a long session', (tester) async {
    await pumpList(tester, range(1, 800));

    final built = find.byType(BlockCard, skipOffstage: false).evaluate().length;
    expect(
      built,
      lessThan(40),
      reason: 'a long session must not build every card',
    );
    expect(built, greaterThan(0));
  });

  testWidgets('older blocks arriving do not move the block being read', (
    tester,
  ) async {
    final harness = await pumpList(tester, range(100, 140));
    final controller = tester
        .state<BlockListState>(find.byType(BlockList))
        .controller;
    controller.jumpTo(300);
    await tester.pumpAndSettle();

    final anchor = find.byKey(const ValueKey('seq-105'));
    final before = tester.getTopLeft(anchor).dy;
    final pixelsBefore = controller.position.pixels;

    harness.prepend(range(60, 99));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(anchor).dy, before);
    expect(controller.position.pixels, pixelsBefore);
    expect(controller.position.minScrollExtent, lessThan(0));
  });

  testWidgets('a new block below does not move the block being read', (
    tester,
  ) async {
    final harness = await pumpList(tester, range(1, 40));
    final controller = tester
        .state<BlockListState>(find.byType(BlockList))
        .controller;
    controller.jumpTo(300);
    await tester.pumpAndSettle();

    final anchor = find.byKey(const ValueKey('seq-6'));
    final before = tester.getTopLeft(anchor).dy;

    harness.append([block(41)]);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(anchor).dy, before);
  });

  testWidgets(
    'switching session starts a fresh pivot instead of inheriting one',
    (tester) async {
      final harness = await pumpList(tester, range(100, 140));
      harness.prepend(range(60, 99));
      await tester.pumpAndSettle();
      expect(
        tester
            .state<BlockListState>(find.byType(BlockList))
            .controller
            .position
            .minScrollExtent,
        lessThan(0),
      );

      harness.switchSession('s-2', range(1, 10));
      await tester.pumpAndSettle();

      final controller = tester
          .state<BlockListState>(find.byType(BlockList))
          .controller;
      expect(
        controller.position.minScrollExtent,
        greaterThan(-20),
        reason:
            'a fresh session has no older page, so only the 6px spacer sits above the centre',
      );
    },
  );

  testWidgets('a fresh list opens at the newest block', (tester) async {
    await pumpList(tester, range(1, 200, lines: (seq) => 1 + seq % 6));

    expect(find.text('Bash 200'), findsOneWidget);
    final controller = tester
        .state<BlockListState>(find.byType(BlockList))
        .controller;
    expect(controller.position.pixels, controller.position.maxScrollExtent);
  });

  testWidgets('a single jump would not have reached the tail', (tester) async {
    await pumpList(tester, range(1, 200, lines: (seq) => 1 + seq % 6));
    final controller = tester
        .state<BlockListState>(find.byType(BlockList))
        .controller;

    controller.jumpTo(0);
    await tester.pump();
    final settledExtent = controller.position.maxScrollExtent;
    controller.jumpTo(settledExtent);
    await tester.pump();

    expect(
      controller.position.maxScrollExtent,
      greaterThan(settledExtent),
      reason: 'this is why the follow is a loop rather than one jumpTo',
    );
  });

  testWidgets('a block appended while pinned is followed', (tester) async {
    final harness = await pumpList(
      tester,
      range(1, 60, lines: (seq) => 1 + seq % 4),
    );
    expect(find.text('Bash 60'), findsOneWidget);

    harness.append([block(61, lines: 3)]);
    await tester.pumpAndSettle();

    expect(find.text('Bash 61'), findsOneWidget);
  });

  testWidgets('a block appended while scrolled up is not followed', (
    tester,
  ) async {
    final harness = await pumpList(
      tester,
      range(1, 60, lines: (seq) => 1 + seq % 4),
    );
    final controller = tester
        .state<BlockListState>(find.byType(BlockList))
        .controller;
    controller.jumpTo(200);
    await tester.pumpAndSettle();
    expect(
      tester.state<BlockListState>(find.byType(BlockList)).pinned,
      isFalse,
    );

    harness.append([block(61, lines: 3)]);
    await tester.pumpAndSettle();

    expect(find.text('Bash 61'), findsNothing);
    expect(controller.position.pixels, 200);
  });

  testWidgets('jumpToLatest returns to the tail from anywhere', (tester) async {
    await pumpList(tester, range(1, 200, lines: (seq) => 1 + seq % 6));
    final state = tester.state<BlockListState>(find.byType(BlockList));
    state.controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Bash 200'), findsNothing);

    state.jumpToLatest();
    await tester.pumpAndSettle();

    expect(find.text('Bash 200'), findsOneWidget);
    expect(
      state.controller.position.pixels,
      state.controller.position.maxScrollExtent,
    );
  });

  testWidgets('the header of the block under the top edge is pinned', (
    tester,
  ) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, range(1, 40, lines: (seq) => 2), sticky: sticky);

    final controller = tester
        .state<BlockListState>(find.byType(BlockList))
        .controller;
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(sticky.value?.block.id, 'seq-1');

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(sticky.value?.block.id, isNot('seq-1'));
    expect(find.byType(StickyBlockHeader), findsOneWidget);
  });

  testWidgets('a block taller than the viewport does not pin its own header', (
    tester,
  ) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, [
      block(1, lines: 1),
      block(2, lines: 400),
      block(3, lines: 1),
    ], sticky: sticky);

    final controller = tester
        .state<BlockListState>(find.byType(BlockList))
        .controller;
    controller.jumpTo(400);
    await tester.pumpAndSettle();

    expect(
      sticky.value,
      isNull,
      reason: 'a block taller than the viewport must not trap its header',
    );
  });

  testWidgets('the pinned header names the same block the top card does', (
    tester,
  ) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, range(1, 40, lines: (seq) => 2), sticky: sticky);

    final controller = tester
        .state<BlockListState>(find.byType(BlockList))
        .controller;
    controller.jumpTo(0);
    await tester.pumpAndSettle();

    expect(find.text('Bash 1'), findsNWidgets(2));
  });

  testWidgets('next moves to the following block boundary', (tester) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, range(1, 40, lines: (seq) => 2), sticky: sticky);

    final state = tester.state<BlockListState>(find.byType(BlockList));
    state.controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(state.topBlockIndex, 0);

    state.scrollToBoundary(forward: true);
    await tester.pumpAndSettle();

    expect(state.topBlockIndex, 1);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('seq-2'))).dy,
      closeTo(0, 1.5),
    );
  });

  testWidgets('next reaches an adjacent block outside the sliver cache', (
    tester,
  ) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, [
      block(1, lines: 400),
      ...range(2, 40),
    ], sticky: sticky);

    final state = tester.state<BlockListState>(find.byType(BlockList));
    state.controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(state.topBlockIndex, 0);
    expect(
      find.byKey(const ValueKey('seq-2'), skipOffstage: false),
      findsNothing,
    );

    state.scrollToBoundary(forward: true);
    await tester.pumpAndSettle();

    expect(state.topBlockIndex, 1);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('seq-2'))).dy,
      closeTo(0, 1.5),
    );
  });

  testWidgets('previous returns to the top of a partly scrolled block first', (
    tester,
  ) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, range(1, 40, lines: (seq) => 6), sticky: sticky);

    final state = tester.state<BlockListState>(find.byType(BlockList));
    state.controller.jumpTo(0);
    await tester.pumpAndSettle();
    state.scrollToBoundary(forward: true);
    await tester.pumpAndSettle();
    final atBoundary = state.topBlockIndex;

    state.controller.jumpTo(state.controller.position.pixels + 20);
    await tester.pumpAndSettle();

    state.scrollToBoundary(forward: false);
    await tester.pumpAndSettle();

    expect(state.topBlockIndex, atBoundary);
  });

  testWidgets('previous from a boundary steps to the block before it', (
    tester,
  ) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, range(1, 40, lines: (seq) => 2), sticky: sticky);

    final state = tester.state<BlockListState>(find.byType(BlockList));
    state.controller.jumpTo(0);
    await tester.pumpAndSettle();
    state.scrollToBoundary(forward: true);
    await tester.pumpAndSettle();
    expect(state.topBlockIndex, 1);

    state.scrollToBoundary(forward: false);
    await tester.pumpAndSettle();

    expect(state.topBlockIndex, 0);
  });

  testWidgets('navigating past either end does nothing', (tester) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(
      tester,
      range(1, 3, lines: (seq) => seq == 3 ? 100 : 1),
      sticky: sticky,
    );

    final state = tester.state<BlockListState>(find.byType(BlockList));
    state.controller.jumpTo(0);
    await tester.pumpAndSettle();
    final atTop = state.controller.position.pixels;

    state.scrollToBoundary(forward: false);
    await tester.pumpAndSettle();

    expect(state.controller.position.pixels, atTop);

    state.controller.jumpTo(state.controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final atBottom = state.controller.position.pixels;
    expect(state.topBlockIndex, 2);

    state.scrollToBoundary(forward: true);
    await tester.pumpAndSettle();

    expect(state.controller.position.pixels, atBottom);
  });

  testWidgets('switching sessions republishes the reset pinned state', (
    tester,
  ) async {
    final pinned = ValueNotifier<bool>(true);
    addTearDown(pinned.dispose);
    final harness = await pumpList(
      tester,
      range(1, 60, lines: (seq) => 2),
      pinned: pinned,
    );
    final state = tester.state<BlockListState>(find.byType(BlockList));
    state.controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(pinned.value, isFalse);

    harness.switchSession('s-2', [block(1)]);
    await tester.pumpAndSettle();

    expect(state.pinned, isTrue);
    expect(pinned.value, isTrue);
  });

  testWidgets(
    'switching sessions refreshes a sticky header when only kind changes',
    (tester) async {
      final sticky = ValueNotifier<StickyBlock?>(null);
      addTearDown(sticky.dispose);
      final harness = await pumpList(
        tester,
        [block(1)],
        sticky: sticky,
        renderStickyHeader: false,
      );
      final state = tester.state<BlockListState>(find.byType(BlockList));
      state.controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(sticky.value?.block.kind, BlockKind.tool);
      expect(find.text('tool'), findsOneWidget);

      harness.switchSession('s-2', [block(1, kind: BlockKind.prompt)]);
      await tester.pumpAndSettle();

      expect(sticky.value?.block.kind, BlockKind.prompt);
      expect(find.text('you'), findsOneWidget);
    },
  );

  testWidgets('a pinned block streaming past the viewport drops its header', (
    tester,
  ) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    final harness = await pumpList(
      tester,
      range(1, 40, lines: (seq) => 2),
      sticky: sticky,
    );
    final state = tester.state<BlockListState>(find.byType(BlockList));
    state.controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(sticky.value?.block.id, 'seq-1');

    harness.grow('seq-1', 400);
    await tester.pumpAndSettle();

    expect(
      sticky.value,
      isNull,
      reason: 'a block that streams past the viewport must release its header',
    );
  });

  testWidgets(
    'a block above the viewport growing does not move the read block',
    (tester) async {
      final harness = await pumpList(tester, range(1, 60, lines: (seq) => 2));
      final state = tester.state<BlockListState>(find.byType(BlockList));
      state.controller.jumpTo(600);
      await tester.pumpAndSettle();

      final anchor = find.byKey(const ValueKey('seq-12'));
      final before = tester.getTopLeft(anchor).dy;
      final pixelsBefore = state.controller.position.pixels;

      harness.grow('seq-2', 60);
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(anchor).dy, before);
      expect(state.controller.position.pixels, pixelsBefore);
    },
  );

  testWidgets(
    'the tail block growing while pinned keeps the view at the tail',
    (tester) async {
      final harness = await pumpList(tester, range(1, 60, lines: (seq) => 2));
      final state = tester.state<BlockListState>(find.byType(BlockList));
      expect(find.text('Bash 60'), findsOneWidget);

      harness.grow('seq-60', 30);
      await tester.pumpAndSettle();

      expect(find.text('Bash 60'), findsOneWidget);
      expect(
        state.controller.position.pixels,
        state.controller.position.maxScrollExtent,
      );
    },
  );

  testWidgets('scrolling does not rebuild the list subtree', (tester) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(
      tester,
      range(1, 200, lines: (seq) => 1 + seq % 4),
      sticky: sticky,
    );

    final before = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    final controller = tester
        .state<BlockListState>(find.byType(BlockList))
        .controller;

    for (var step = 0; step < 12; step++) {
      controller.jumpTo(controller.position.pixels - 40);
      await tester.pump();
    }

    final after = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(
      identical(before, after),
      isTrue,
      reason:
          'a setState on scroll would rebuild every visible card every frame',
    );
  });

  testWidgets('the sticky header notifies per boundary, not per frame', (
    tester,
  ) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, range(1, 200, lines: (seq) => 8), sticky: sticky);

    final controller = tester
        .state<BlockListState>(find.byType(BlockList))
        .controller;
    controller.jumpTo(0);
    await tester.pumpAndSettle();

    var notifications = 0;
    void count() => notifications++;
    sticky.addListener(count);
    addTearDown(() => sticky.removeListener(count));

    final firstHeight = sticky.value!.height;
    var travelled = 0.0;
    while (travelled < firstHeight * 0.8) {
      controller.jumpTo(controller.position.pixels + 8);
      await tester.pump();
      travelled += 8;
    }

    expect(
      notifications,
      0,
      reason: 'scrolling inside one block must not touch the header notifier',
    );
  });

  testWidgets('a long session keeps its built window small while scrolling', (
    tester,
  ) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(
      tester,
      range(1, 800, lines: (seq) => 1 + seq % 5),
      sticky: sticky,
    );

    final controller = tester
        .state<BlockListState>(find.byType(BlockList))
        .controller;
    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();

    final built = find.byType(BlockCard, skipOffstage: false).evaluate().length;
    expect(built, lessThan(40));
    expect(built, greaterThan(0));
  });

  testWidgets('a highlighted card renders the match with a tinted background', (
    tester,
  ) async {
    const skin = DarkSkin();
    final blocks = range(1, 3);
    final match = BlockMatch(
      blockId: 'seq-2',
      field: BlockMatchField.summary,
      score: const MatchScore(tier: 0, offset: 0),
      ranges: const [MatchRange(start: 0, length: 4)],
    );

    await pumpList(
      tester,
      blocks,
      highlights: {'seq-2': match},
    );

    final richTextFinder = find.descendant(
      of: find.byKey(const ValueKey('seq-2')),
      matching: find.byType(RichText),
    );
    expect(richTextFinder, findsWidgets);
    final highlighted = richTextFinder.evaluate().any((element) {
      final rich = element.widget as RichText;
      return _hasHighlightedSpan(rich, skin.tintAmber);
    });
    expect(
      highlighted,
      isTrue,
      reason: 'the matching card must render the matched range with a tinted background',
    );
  });
}

bool _hasHighlightedSpan(RichText rich, Color expected) {
  final root = rich.text as TextSpan;
  return _spanHasBackground(root, expected);
}

bool _spanHasBackground(TextSpan span, Color expected) {
  if (span.style?.backgroundColor == expected) return true;
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan && _spanHasBackground(child, expected)) return true;
  }
  return false;
}
