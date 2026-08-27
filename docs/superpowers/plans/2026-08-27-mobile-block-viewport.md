# Mobile Block Viewport Implementation Plan (Plan 4a)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the mobile block list scroll correctly and cheaply over a long session — windowed rendering, anchored appends and prepends, sticky block headers with the tall-block exception, and block-boundary navigation.

**Architecture:** `BlocksBody` currently renders every block into a plain `ListView.builder` and chases the tail with a single `jumpTo(maxScrollExtent)` scheduled from inside `build`. This plan replaces the list with a `CustomScrollView` whose **`center` sliver** is pinned to the oldest block present at first render. Blocks older than that pivot render in a leading sliver at negative scroll offsets, which makes "load older" cost zero scroll movement — Flutter's own viewport does the anchoring. Appends keep their position for free for the same reason, and the pinned-to-bottom follow becomes a **bounded one-jump-per-frame loop** because `maxScrollExtent` on a lazily laid-out variable-height list grows as you approach it. The sticky header is an overlay driven by a `ValueNotifier` that only fires when the block under the viewport's top edge changes, so scrolling rebuilds the header and nothing else.

**Tech Stack:** Flutter 3.44.5 / Dart 3.12.2, `flutter_bloc` (Cubit only), `equatable`, `mocktail` + `bloc_test` for tests.

**Spec:** `docs/superpowers/specs/2026-08-27-session-blocks-design.md` — the "Viewport" section, and spec sequencing step 6. This plan is **4a**; `2026-08-27-desktop-block-viewport.md` is 4b. They share a requirements list and no code.

## Global Constraints

- **No code comments.** The user's global instruction is "don't make comments". Every explanation an implementer needs is in this plan; do not carry it into the source. Do not add a comment even to justify a subtle line.
- **Cubit only** — never `Bloc` with events. Static-only classes are `sealed class X`.
- **No `drift`, `freezed`, `json_serializable`, or `build_runner`** in first-party code.
- **Feature code never imports `flutter_screenutil`** — spacing, padding and radii take raw ints. (`AppTextStyle` uses `.spMin` internally, which is why *tests* must wrap in `ScreenUtilInit`.)
- **User-facing copy is inline English.** There is no `LocaleKeys` catalogue for product copy on mobile.
- **No new pub dependencies.** Everything here is core Flutter.
- **Gates, run from `packages/mobile`:** `flutter analyze` must print `No issues found!`, and `flutter test` must be green. Both must pass at the end of every task before its commit.
- Nothing in this plan touches `ios/`, `android/`, or a vendored package's platform code, so no native build is required.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/feature/blocks/logic/block_viewport.dart` | **Create.** Pure viewport arithmetic: pivot resolution, pinned test, sticky-header eligibility, boundary stepping. No Flutter widget imports beyond `dart:ui`-free math. |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart` | **Create.** The `CustomScrollView`, the center pivot, the tail-follow loop, the sticky probe, and the imperative scroll API. Owns the `ScrollController`. |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart` | **Create.** The overlay widget and its `StickyBlock` value type. |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart` | **Modify.** Extract the header row into a public `BlockCardHeader` so the sticky overlay renders the identical thing rather than a copy. |
| `lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart` | **Modify.** Owns the sticky `ValueNotifier` and the `GlobalKey<BlockListState>`, hosts the `Stack`, and keeps every existing notice/error/empty branch untouched. |
| `test/feature/blocks/logic/block_viewport_test.dart` | **Create.** Unit tests for the pure logic. |
| `test/feature/blocks/presentation/blocks_screen/block_list_test.dart` | **Create.** Widget tests for anchoring, windowing, sticky headers, navigation, and scroll cost. |
| `test/feature/blocks/presentation/blocks_screen/blocks_body_test.dart` | **Modify.** Existing suite; only the two assertions that name `ListView` change. |

### What is NOT in this plan

Cross-block **selection and find** are spec step 8 / plan 6. **Block actions** (copy, re-run, collapse, filter) are also plan 6. Do not build them here, and do not leave hooks for them.

---

## Facts established by running the real thing

These were measured in this repository on Flutter 3.44.5 before the plan was written. They are why the design is what it is. Do not re-litigate them; do re-run them if something surprises you.

1. **`ListView.builder` already virtualizes.** A 30-item list in a 300px viewport builds 12 children. There is no `sum_tree` to port and no height cache to write — Flutter's sliver protocol is the height cache. Building one would be dead code.
2. **A single `jumpTo(maxScrollExtent)` does not reach the tail of a variable-height list.** On a 400-item list with heights cycling 24–324px, one jump landed at `52500.0` while the true extent was `73248.0`. `maxScrollExtent` is an extrapolation from the children laid out so far and grows as you approach it.
3. **Jumping repeatedly *within one frame* overshoots.** Three jumps with no `pump` between them landed at `73248.0` against a settled extent of `69090.0` — past the end. The extent can shrink as well as grow. The loop must be **one jump per frame**.
4. **One jump per frame converges in 3 hops** on that same 400-item list, landing exactly on `69090.0 / 69090.0`.
5. **`CustomScrollView(center: key)` gives prepend anchoring for free.** Prepending 20 items left the anchored block at `top=100.0` and `pixels=200.0` unchanged; `minScrollExtent` moved `0.0 → -1000.0`. Appending below while scrolled up also left it at `top=100.0`.
6. **The `center` key must be a `GlobalKey` if you also want to read that sliver's render object.** `CustomScrollView` asserts exactly one sliver carries the `center` key, so the center sliver cannot have a second key. A `GlobalKey` is a `Key`, so pass the same object to both `center:` and the sliver's `key:`.
7. **`RenderBox.localToGlobal` locates the top block across both slivers.** Walking `firstChild`/`childAfter` on each `RenderSliverMultiBoxAdaptor` and comparing `localToGlobal(Offset.zero).dy` against the viewport's own global top correctly returned `center#0 h=40`, `center#3 h=220` at offset 500, and `lead#1 h=220` at offset −300, including after a prepend. `childScrollOffset` also works but forces you to reason about the center sliver's negative offsets; `localToGlobal` does not.

---

### Task 1: Pure viewport arithmetic

Everything in this file is a pure function so the tricky cases are pinned by fast unit tests rather than by widget tests that have to lay out a scroll view.

**Files:**
- Create: `packages/mobile/lib/feature/blocks/logic/block_viewport.dart`
- Test: `packages/mobile/test/feature/blocks/logic/block_viewport_test.dart`

**Interfaces:**
- Consumes: `SessionBlock` from `lib/feature/blocks/logic/session_block.dart` (fields used: `firstSeq`, `id`).
- Produces: `kTailSlack`, `kMaxFollowHops`, and `sealed class BlockViewport` with statics `pivotIndex`, `isPinned`, `headerSticks`, `nextBoundary`, `previousBoundary`. Tasks 2–5 call all of them.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/blocks/logic/block_viewport_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/block_viewport.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

SessionBlock _block(int seq) => SessionBlock(
  id: 'seq-$seq',
  firstSeq: seq,
  lastSeq: seq,
  kind: BlockKind.tool,
  status: BlockStatus.ok,
  title: 'Bash',
  body: 'ok',
);

void main() {
  group('pivotIndex', () {
    test('an unset pivot puts every block after the centre', () {
      expect(BlockViewport.pivotIndex([_block(4), _block(5)], null), 0);
    });

    test('splits older blocks out of the centre sliver', () {
      final blocks = [_block(1), _block(2), _block(3), _block(4)];
      expect(BlockViewport.pivotIndex(blocks, 3), 2);
    });

    test('a pivot older than everything held leaves the leading sliver empty', () {
      expect(BlockViewport.pivotIndex([_block(7), _block(8)], 2), 0);
    });

    test('a pivot newer than everything held puts every block before the centre', () {
      expect(BlockViewport.pivotIndex([_block(1), _block(2)], 9), 2);
    });

    test('an evicted pivot still splits at the same seq boundary', () {
      final afterEviction = [_block(3), _block(4), _block(5)];
      expect(BlockViewport.pivotIndex(afterEviction, 4), 1);
    });

    test('an empty window has nothing before the centre', () {
      expect(BlockViewport.pivotIndex(const [], 4), 0);
    });
  });

  group('isPinned', () {
    test('is pinned exactly at the tail', () {
      expect(BlockViewport.isPinned(1000, 1000), isTrue);
    });

    test('is pinned inside the slack', () {
      expect(BlockViewport.isPinned(980, 1000), isTrue);
    });

    test('is not pinned once scrolled clear of the slack', () {
      expect(BlockViewport.isPinned(900, 1000), isFalse);
    });

    test('an unscrollable list is pinned', () {
      expect(BlockViewport.isPinned(0, 0), isTrue);
    });

    test('a negative offset in the leading sliver is not pinned', () {
      expect(BlockViewport.isPinned(-400, 1000), isFalse);
    });
  });

  group('headerSticks', () {
    test('a block shorter than the viewport keeps its header pinned', () {
      expect(BlockViewport.headerSticks(200, 600), isTrue);
    });

    test('a block exactly as tall as the viewport still sticks', () {
      expect(BlockViewport.headerSticks(600, 600), isTrue);
    });

    test('a block taller than the viewport does not trap its own header', () {
      expect(BlockViewport.headerSticks(900, 600), isFalse);
    });
  });

  group('boundaries', () {
    test('next steps forward and stops at the last block', () {
      expect(BlockViewport.nextBoundary(0, 3), 1);
      expect(BlockViewport.nextBoundary(2, 3), isNull);
    });

    test('next from nothing selects the first block', () {
      expect(BlockViewport.nextBoundary(null, 3), 0);
    });

    test('previous steps back and stops at the first block', () {
      expect(BlockViewport.previousBoundary(2, 3), 1);
      expect(BlockViewport.previousBoundary(0, 3), isNull);
    });

    test('an empty list has no boundaries in either direction', () {
      expect(BlockViewport.nextBoundary(null, 0), isNull);
      expect(BlockViewport.previousBoundary(0, 0), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd packages/mobile && flutter test test/feature/blocks/logic/block_viewport_test.dart
```

Expected: compilation failure — `Error: Couldn't resolve the package 'operator_mobile/feature/blocks/logic/block_viewport.dart'` or `Undefined name 'BlockViewport'`.

- [ ] **Step 3: Write the implementation**

Create `packages/mobile/lib/feature/blocks/logic/block_viewport.dart`:

```dart
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

const double kTailSlack = 24;

const int kMaxFollowHops = 20;

sealed class BlockViewport {
  static int pivotIndex(List<SessionBlock> blocks, int? pivotSeq) {
    if (pivotSeq == null) return 0;
    for (var index = 0; index < blocks.length; index++) {
      if (blocks[index].firstSeq >= pivotSeq) return index;
    }
    return blocks.length;
  }

  static bool isPinned(double pixels, double maxScrollExtent) =>
      pixels >= maxScrollExtent - kTailSlack;

  static bool headerSticks(double blockHeight, double viewportHeight) =>
      blockHeight <= viewportHeight;

  static int? nextBoundary(int? current, int count) {
    if (count == 0) return null;
    if (current == null) return 0;
    final next = current + 1;
    return next >= count ? null : next;
  }

  static int? previousBoundary(int? current, int count) {
    if (count == 0 || current == null) return null;
    final previous = current - 1;
    return previous < 0 ? null : previous;
  }
}
```

- [ ] **Step 4: Run the gates**

```bash
cd packages/mobile && flutter test test/feature/blocks/logic/block_viewport_test.dart && flutter analyze
```

Expected: all tests pass; `flutter analyze` prints `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/blocks/logic/block_viewport.dart packages/mobile/test/feature/blocks/logic/block_viewport_test.dart
git commit -m "feat(mobile): add pure block viewport arithmetic"
```

---

### Task 2: The bidirectional list, anchored on a centre pivot

This is the structural change. After it the list still looks identical, still windows, and additionally holds its position when older blocks arrive.

**Files:**
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`
- Modify: `packages/mobile/test/feature/blocks/presentation/blocks_screen/blocks_body_test.dart`
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_screen/block_list_test.dart`

**Interfaces:**
- Consumes: `BlockViewport.pivotIndex` (Task 1); `BlockCard` from `ui/widgets/block_card.dart`; `SessionBlock`.
- Produces: `class BlockList extends StatefulWidget` with named parameters `{Key? key, required String sessionId, required List<SessionBlock> blocks, Widget? header}`, and `class BlockListState extends State<BlockList>`. Tasks 3, 4 and 5 add members to `BlockListState`; task 5 reaches it through a `GlobalKey<BlockListState>`.

**Why a centre sliver rather than correcting `scrollTop` after the fact.** A prepend of 100 blocks whose heights have never been laid out cannot be corrected by measuring the extent delta — the delta is an extrapolation, and correcting by it produces exactly the drifting scrollbar the spec calls out. With a centre sliver there is nothing to correct: older blocks occupy negative scroll offsets, so `pixels` is still the same number pointing at the same content. Fact 5 above is the measurement.

**Why the pivot is a seq and not a block id.** The cubit evicts the lowest-seq event once the window is full (`BlocksCubit._merge`). If the pivot were an id, eviction of that block would force a pivot reset, which empties the leading sliver and shifts the view. Splitting on `firstSeq >= pivotSeq` survives eviction: the leading sliver simply gets shorter, and every remaining block stays on the side it was already on.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/blocks/presentation/blocks_screen/block_list_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';

SessionBlock block(int seq, {int lines = 1}) => SessionBlock(
  id: 'seq-$seq',
  firstSeq: seq,
  lastSeq: seq,
  kind: BlockKind.tool,
  status: BlockStatus.ok,
  title: 'Bash $seq',
  body: List.generate(lines, (line) => 'line $line of block $seq').join('\n'),
);

List<SessionBlock> range(int from, int to, {int Function(int)? lines}) => [
  for (var seq = from; seq <= to; seq++) block(seq, lines: lines?.call(seq) ?? 1),
];

class ListHarness extends StatefulWidget {
  const ListHarness({super.key, required this.initial, this.sessionId = 's-1'});

  final List<SessionBlock> initial;
  final String sessionId;

  @override
  State<ListHarness> createState() => ListHarnessState();
}

class ListHarnessState extends State<ListHarness> {
  late List<SessionBlock> blocks = widget.initial;
  late String sessionId = widget.sessionId;

  void prepend(List<SessionBlock> older) => setState(() => blocks = [...older, ...blocks]);

  void append(List<SessionBlock> newer) => setState(() => blocks = [...blocks, ...newer]);

  void switchSession(String id, List<SessionBlock> next) => setState(() {
    sessionId = id;
    blocks = next;
  });

  @override
  Widget build(BuildContext context) =>
      BlockList(key: const ValueKey('list'), sessionId: sessionId, blocks: blocks);
}

Future<ListHarnessState> pumpList(WidgetTester tester, List<SessionBlock> blocks) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 390, height: 600, child: ListHarness(initial: blocks)),
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

  testWidgets('builds only a window of a long session', (tester) async {
    await pumpList(tester, range(1, 800));

    final built = find.byType(BlockCard, skipOffstage: false).evaluate().length;
    expect(built, lessThan(40), reason: 'a long session must not build every card');
    expect(built, greaterThan(0));
  });

  testWidgets('older blocks arriving do not move the block being read', (tester) async {
    final harness = await pumpList(tester, range(100, 140));
    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;
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

  testWidgets('a new block below does not move the block being read', (tester) async {
    final harness = await pumpList(tester, range(1, 40));
    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;
    controller.jumpTo(300);
    await tester.pumpAndSettle();

    final anchor = find.byKey(const ValueKey('seq-6'));
    final before = tester.getTopLeft(anchor).dy;

    harness.append([block(41)]);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(anchor).dy, before);
  });

  testWidgets('switching session starts a fresh pivot instead of inheriting one', (tester) async {
    final harness = await pumpList(tester, range(100, 140));
    harness.prepend(range(60, 99));
    await tester.pumpAndSettle();
    expect(
      tester.state<BlockListState>(find.byType(BlockList)).controller.position.minScrollExtent,
      lessThan(0),
    );

    harness.switchSession('s-2', range(1, 10));
    await tester.pumpAndSettle();

    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;
    expect(
      controller.position.minScrollExtent,
      greaterThan(-20),
      reason: 'a fresh session has no older page, so only the 6px spacer sits above the centre',
    );
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/block_list_test.dart
```

Expected: compilation failure — `block_list.dart` does not exist.

- [ ] **Step 3: Write `BlockList`**

Create `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/feature/blocks/logic/block_viewport.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

class BlockList extends StatefulWidget {
  const BlockList({
    super.key,
    required this.sessionId,
    required this.blocks,
    this.header,
  });

  final String sessionId;
  final List<SessionBlock> blocks;
  final Widget? header;

  @override
  State<BlockList> createState() => BlockListState();
}

class BlockListState extends State<BlockList> {
  final ScrollController controller = ScrollController();
  final GlobalKey centerKey = GlobalKey();
  final GlobalKey leadingKey = GlobalKey();
  final GlobalKey viewportKey = GlobalKey();

  int? _pivotSeq;

  @override
  void initState() {
    super.initState();
    _adoptPivot();
  }

  @override
  void didUpdateWidget(BlockList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionId != oldWidget.sessionId) _pivotSeq = null;
    _adoptPivot();
  }

  void _adoptPivot() {
    if (_pivotSeq != null || widget.blocks.isEmpty) return;
    _pivotSeq = widget.blocks.first.firstSeq;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocks = widget.blocks;
    final pivot = BlockViewport.pivotIndex(blocks, _pivotSeq);
    final header = widget.header;

    return SizedBox.expand(
      key: viewportKey,
      child: CustomScrollView(
        controller: controller,
        center: centerKey,
        slivers: [
          if (header != null) SliverToBoxAdapter(child: header),
          const SliverToBoxAdapter(child: SizedBox(height: 6)),
          SliverList.builder(
            key: leadingKey,
            itemCount: pivot,
            itemBuilder: (context, index) {
              final block = blocks[pivot - 1 - index];
              return BlockCard(key: ValueKey(block.id), block: block);
            },
          ),
          SliverList.builder(
            key: centerKey,
            itemCount: blocks.length - pivot,
            itemBuilder: (context, index) {
              final block = blocks[pivot + index];
              return BlockCard(key: ValueKey(block.id), block: block);
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 6)),
        ],
      ),
    );
  }
}
```

Three things here are load-bearing and easy to get wrong:

- **Sliver order.** Slivers listed *before* the centre are laid out in reverse away from it, so the first entry in the list is the top-most thing on screen. That is why the header sliver comes first and the leading list second.
- **Index mapping in the leading sliver.** Its own index 0 is the sliver row nearest the centre, which is the *newest* of the older blocks — hence `blocks[pivot - 1 - index]`. Getting this backwards renders the older page upside down and no test above will say so in those words; the prepend test will simply show the wrong anchor.
- **`centerKey` is a `GlobalKey` passed to both `center:` and the centre sliver's `key:`.** `CustomScrollView` asserts exactly one sliver carries the centre key, so the sliver cannot carry a second one, and Task 4 needs a `GlobalKey` on that sliver to reach its render object.

- [ ] **Step 4: Point `BlocksBody` at the new list**

In `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`, replace the `ListView.builder` return and the scroll plumbing that fed it. Delete `_BlocksBodyState._controller`, `_pinned`, `_followTail`, `dispose`, and the `addPostFrameCallback` block; `BlockList` owns all of that now. `BlocksBody` becomes a `StatelessWidget`.

Replace the whole file with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';

class BlocksBody extends StatelessWidget {
  const BlocksBody({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<BlocksCubit, BlocksState>(
      builder: (context, state) {
        final cubit = context.read<BlocksCubit>();

        if (state is BlocksUnsupportedState) {
          return _notice(
            context,
            'Blocks are unavailable for ${state.harness ?? 'this agent'}. Use the raw terminal instead.',
          );
        }

        final error = cubit.error;
        if (error != null && cubit.blocks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(
                  error,
                  style: AppTextStyle.style12Regular.copyWith(color: skin.attention),
                  maxLines: 3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                TextButton(onPressed: cubit.refresh, child: const Text('Retry')),
              ],
            ),
          );
        }

        if (cubit.blocks.isEmpty) {
          return _notice(
            context,
            cubit.loading ? 'Loading blocks...' : 'No blocks yet. They appear as the agent works.',
          );
        }

        return BlockList(
          sessionId: cubit.sessionId,
          blocks: cubit.blocks,
          header: _olderControl(context, cubit),
        );
      },
    );
  }

  Widget? _olderControl(BuildContext context, BlocksCubit cubit) {
    if (cubit.loadingOlder) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: AppText(
          'Loading older blocks...',
          style: AppTextStyle.style11Regular.copyWith(color: context.skin.textTertiary),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (!cubit.hasOlder) return null;
    return Center(
      child: TextButton(onPressed: cubit.loadOlder, child: const Text('Load older blocks')),
    );
  }

  Widget _notice(BuildContext context, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: AppText(
        message,
        style: AppTextStyle.style12Regular.copyWith(color: context.skin.textTertiary),
        maxLines: 4,
        textAlign: TextAlign.center,
      ),
    ),
  );
}
```

`BlocksCubit.sessionId` is already a public final field, so no cubit change is needed. The existing `blocks_body_test.dart` mocks `BlocksCubit`, so add `when(() => cubit.sessionId).thenReturn('s-1');` to its `setUp` — without it `mocktail` throws on the unstubbed getter.

**Expect one temporary regression across this task's boundary.** `BlocksBody`'s old `_followTail` is deleted here and `BlockList` does not grow its own until Task 3, so between the two commits the list opens at the oldest block instead of the newest. No test asserts tail behaviour yet, so the tree stays green; do not paper over it with a stopgap jump that Task 3 would then have to unpick.

- [ ] **Step 5: Update the two existing assertions that named the old list**

In `packages/mobile/test/feature/blocks/presentation/blocks_screen/blocks_body_test.dart`, add the `sessionId` stub to `setUp`:

```dart
    when(() => cubit.sessionId).thenReturn('s-1');
```

Every other test in that file asserts on rendered text or `BlockCard`, which the new list still produces. Run it and fix only what actually fails.

- [ ] **Step 6: Run the gates**

```bash
cd packages/mobile && flutter test test/feature/blocks/ && flutter analyze
```

Expected: `block_list_test.dart` and `blocks_body_test.dart` both green; `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib/feature/blocks packages/mobile/test/feature/blocks
git commit -m "feat(mobile): anchor the block list on a centre sliver"
```

---

### Task 3: A tail follow that actually reaches the tail

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart`
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_screen/block_list_test.dart` (append to the existing `main()`)

**Interfaces:**
- Consumes: `BlockViewport.isPinned`, `kMaxFollowHops` (Task 1).
- Produces: `BlockListState.pinned` (a `bool` getter) and `BlockListState.jumpToLatest()`. Task 5 calls `jumpToLatest`.

**Why a loop.** Facts 2–4 above. `maxScrollExtent` on a lazily laid-out list is an extrapolation from the children built so far; jumping to it builds more children and moves it. One jump per frame, re-reading the extent each time, converges — and jumping several times inside one frame overshoots past a settled extent, because the extent can shrink as well as grow.

- [ ] **Step 1: Write the failing tests**

Append to `main()` in `block_list_test.dart`:

```dart
  testWidgets('a fresh list opens at the newest block', (tester) async {
    await pumpList(tester, range(1, 200, lines: (seq) => 1 + seq % 6));

    expect(find.text('Bash 200'), findsOneWidget);
    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;
    expect(controller.position.pixels, controller.position.maxScrollExtent);
  });

  testWidgets('a single jump would not have reached the tail', (tester) async {
    await pumpList(tester, range(1, 200, lines: (seq) => 1 + seq % 6));
    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;

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
    final harness = await pumpList(tester, range(1, 60, lines: (seq) => 1 + seq % 4));
    expect(find.text('Bash 60'), findsOneWidget);

    harness.append([block(61, lines: 3)]);
    await tester.pumpAndSettle();

    expect(find.text('Bash 61'), findsOneWidget);
  });

  testWidgets('a block appended while scrolled up is not followed', (tester) async {
    final harness = await pumpList(tester, range(1, 60, lines: (seq) => 1 + seq % 4));
    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;
    controller.jumpTo(200);
    await tester.pumpAndSettle();
    expect(tester.state<BlockListState>(find.byType(BlockList)).pinned, isFalse);

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
    expect(state.controller.position.pixels, state.controller.position.maxScrollExtent);
  });
```

- [ ] **Step 2: Run them and confirm they fail**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/block_list_test.dart
```

Expected: `a fresh list opens at the newest block` fails (`Bash 200` not found — the list opens at the top), and `jumpToLatest` fails to compile (`The method 'jumpToLatest' isn't defined`). Fix the compile error last: comment nothing out, just implement Step 3 and re-run.

- [ ] **Step 3: Add the follow loop to `BlockListState`**

Add these fields to `BlockListState`, next to `_pivotSeq`:

```dart
  bool _pinned = true;
  bool _followScheduled = false;
  int _followHops = 0;
```

Add a getter and the loop:

```dart
  bool get pinned => _pinned;

  void jumpToLatest() {
    _pinned = true;
    _scheduleFollow();
  }

  void _onScroll() {
    if (!controller.hasClients) return;
    _pinned = BlockViewport.isPinned(
      controller.position.pixels,
      controller.position.maxScrollExtent,
    );
  }

  void _scheduleFollow() {
    if (_followScheduled) return;
    _followScheduled = true;
    _followHops = 0;
    _followStep();
  }

  void _followStep() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients || !_pinned || _followHops >= kMaxFollowHops) {
        _followScheduled = false;
        return;
      }
      final extent = controller.position.maxScrollExtent;
      if ((controller.position.pixels - extent).abs() < 0.5) {
        _followScheduled = false;
        return;
      }
      _followHops++;
      controller.jumpTo(extent);
      _followStep();
    });
  }
```

Wire it into the lifecycle. `initState` becomes:

```dart
  @override
  void initState() {
    super.initState();
    controller.addListener(_onScroll);
    _adoptPivot();
    _scheduleFollow();
  }
```

`didUpdateWidget` becomes:

```dart
  @override
  void didUpdateWidget(BlockList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionId != oldWidget.sessionId) {
      _pivotSeq = null;
      _pinned = true;
    }
    _adoptPivot();
    if (_pinned) _scheduleFollow();
  }
```

`dispose` becomes:

```dart
  @override
  void dispose() {
    controller.removeListener(_onScroll);
    controller.dispose();
    super.dispose();
  }
```

Two details that matter. `_onScroll` reads pinned-ness continuously from the user's own scrolling, so by the time `didUpdateWidget` runs it reflects where the user left the view rather than what the not-yet-laid-out new content did to the extent — that is what makes "appended while scrolled up" work without comparing block lists. And `_scheduleFollow` is safe to call unconditionally: when already at the tail the first `_followStep` sees `pixels == extent` and stops.

- [ ] **Step 4: Run the gates**

```bash
cd packages/mobile && flutter test test/feature/blocks/ && flutter analyze
```

Expected: all green, `No issues found!`. If `pumpAndSettle` ever times out, the follow loop is not terminating — check that `_followScheduled` is cleared on every exit path and that `kMaxFollowHops` is respected.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/feature/blocks packages/mobile/test/feature/blocks
git commit -m "feat(mobile): converge the block list on the true tail"
```

---

### Task 4: Sticky block headers, with the tall-block exception

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_screen/block_list_test.dart`

**Interfaces:**
- Consumes: `BlockViewport.headerSticks` (Task 1); `BlockListState.controller`, `viewportKey`, `leadingKey`, `centerKey` (Task 2).
- Produces: `class StickyBlock extends Equatable` with fields `block` and `height`; `class StickyBlockHeader extends StatelessWidget` taking `{required ValueListenable<StickyBlock?> sticky}`; `class BlockCardHeader extends StatelessWidget` taking `{required SessionBlock block}`; a new `BlockList` parameter `ValueNotifier<StickyBlock?>? sticky` and `BlockListState.topBlockIndex`. Task 5 uses `topBlockIndex`.

**Why the header is a `ValueNotifier` and not `setState`.** The spec names the profiling obligation: "the same smoothness is available provided the list does not re-render during scroll". A `setState` in a scroll listener rebuilds `BlockList`, which rebuilds every visible `BlockCard`, every frame of every scroll. A `ValueNotifier<StickyBlock?>` whose value is `Equatable` on `(block, height)` notifies only when the block under the top edge actually changes — once per block boundary crossed, not once per frame — and `ValueListenableBuilder` confines that rebuild to the overlay. Task 6 pins both halves of this.

**Why the exception is `height <= viewportHeight`.** Straight from the spec, which cites Warp's `block_list_element.rs:135`: sticky headers are "disabled when the block is taller than the viewport … without the exception a tall block traps its own header".

- [ ] **Step 1: Write the failing tests**

Append to `main()` in `block_list_test.dart`:

```dart
  testWidgets('the header of the block under the top edge is pinned', (tester) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, range(1, 40, lines: (seq) => 2), sticky: sticky);

    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(sticky.value?.block.id, 'seq-1');

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(sticky.value?.block.id, isNot('seq-1'));
    expect(find.byType(StickyBlockHeader), findsOneWidget);
  });

  testWidgets('a block taller than the viewport does not pin its own header', (tester) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, [block(1, lines: 1), block(2, lines: 400), block(3, lines: 1)], sticky: sticky);

    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;
    controller.jumpTo(400);
    await tester.pumpAndSettle();

    expect(sticky.value, isNull, reason: 'a block taller than the viewport must not trap its header');
  });

  testWidgets('the pinned header names the same block the top card does', (tester) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, range(1, 40, lines: (seq) => 2), sticky: sticky);

    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;
    controller.jumpTo(0);
    await tester.pumpAndSettle();

    expect(find.text('Bash 1'), findsNWidgets(2));
  });
```

Extend the `pumpList` helper in that file to take the notifier and render the overlay the way `BlocksBody` will:

```dart
Future<ListHarnessState> pumpList(
  WidgetTester tester,
  List<SessionBlock> blocks, {
  ValueNotifier<StickyBlock?>? sticky,
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
                    Positioned.fill(child: ListHarness(initial: blocks, sticky: sticky)),
                    if (sticky != null)
                      Positioned(top: 0, left: 0, right: 0, child: StickyBlockHeader(sticky: sticky)),
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
```

and give `ListHarness` a `sticky` field it forwards to `BlockList`:

```dart
class ListHarness extends StatefulWidget {
  const ListHarness({super.key, required this.initial, this.sessionId = 's-1', this.sticky});

  final List<SessionBlock> initial;
  final String sessionId;
  final ValueNotifier<StickyBlock?>? sticky;
  ...
}
```

with `build` becoming:

```dart
  @override
  Widget build(BuildContext context) => BlockList(
    key: const ValueKey('list'),
    sessionId: sessionId,
    blocks: blocks,
    sticky: widget.sticky,
  );
```

Add the imports for `StickyBlock` and `StickyBlockHeader` to the test file.

- [ ] **Step 2: Run them and confirm they fail**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/block_list_test.dart
```

Expected: compilation failure — `sticky_block_header.dart` does not exist and `BlockList` has no `sticky` parameter.

- [ ] **Step 3: Extract `BlockCardHeader`**

In `block_card.dart`, replace the header `Container` inside `BlockCard.build` with `BlockCardHeader(block: block)` and add the widget below `BlockCard`, moving `_kindLabel` onto it:

```dart
class BlockCardHeader extends StatelessWidget {
  const BlockCardHeader({super.key, required this.block});

  final SessionBlock block;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: skin.borderSubtle)),
      ),
      child: Row(
        children: [
          BlockStatusDot(status: block.status),
          const SizedBox(width: 8),
          Expanded(
            child: AppText(
              block.title,
              style: AppTextStyle.style12SemiBold.copyWith(color: skin.textPrimary),
            ),
          ),
          AppText(
            _kindLabel(block.kind),
            style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }

  String _kindLabel(BlockKind kind) => switch (kind) {
    BlockKind.prompt => 'you',
    BlockKind.assistant => 'agent',
    BlockKind.tool => 'tool',
    BlockKind.permission => 'permission',
    BlockKind.notice => 'notice',
  };
}
```

Delete the now-unused `_kindLabel` from `BlockCard`.

- [ ] **Step 4: Write the overlay**

Create `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

class StickyBlock extends Equatable {
  const StickyBlock({required this.block, required this.height});

  final SessionBlock block;
  final double height;

  @override
  List<Object?> get props => [block.id, block.status, block.title, height];
}

class StickyBlockHeader extends StatelessWidget {
  const StickyBlockHeader({super.key, required this.sticky});

  final ValueListenable<StickyBlock?> sticky;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<StickyBlock?>(
    valueListenable: sticky,
    builder: (context, value, _) {
      if (value == null) return const SizedBox.shrink();
      final skin = context.skin;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: skin.bgElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          border: Border.all(color: skin.borderSubtle),
        ),
        child: BlockCardHeader(block: value.block),
      );
    },
  );
}
```

`ValueListenable` comes from `package:flutter/foundation.dart`, which `material.dart` re-exports, so the import above is sufficient.

`props` includes `status` and `title` because a `running` block's dot and title change while it is the top block; without them the pinned header would go stale mid-turn. It deliberately does **not** include `body`, so a streaming body does not notify.

- [ ] **Step 5: Probe the top block from `BlockListState`**

Add to the imports of `block_list.dart`:

```dart
import 'package:flutter/rendering.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart';
```

Add the `sticky` parameter to `BlockList`:

```dart
  const BlockList({
    super.key,
    required this.sessionId,
    required this.blocks,
    this.header,
    this.sticky,
  });

  final ValueNotifier<StickyBlock?>? sticky;
```

Add to `BlockListState`:

```dart
  int? _topIndex;

  int? get topBlockIndex => _topIndex;

  void _updateSticky() {
    final notifier = widget.sticky;
    final viewport = viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) {
      _topIndex = null;
      notifier?.value = null;
      return;
    }

    final top = viewport.localToGlobal(Offset.zero).dy + 0.5;
    final pivot = BlockViewport.pivotIndex(widget.blocks, _pivotSeq);

    for (final key in [leadingKey, centerKey]) {
      final sliver = key.currentContext?.findRenderObject();
      if (sliver is! RenderSliverMultiBoxAdaptor) continue;
      RenderBox? child = sliver.firstChild;
      while (child != null) {
        final childTop = child.localToGlobal(Offset.zero).dy;
        final height = child.size.height;
        if (childTop <= top && childTop + height > top) {
          final sliverIndex = sliver.indexOf(child);
          final blockIndex = key == leadingKey ? pivot - 1 - sliverIndex : pivot + sliverIndex;
          if (blockIndex < 0 || blockIndex >= widget.blocks.length) {
            _topIndex = null;
            notifier?.value = null;
            return;
          }
          _topIndex = blockIndex;
          notifier?.value = BlockViewport.headerSticks(height, viewport.size.height)
              ? StickyBlock(block: widget.blocks[blockIndex], height: height)
              : null;
          return;
        }
        child = sliver.childAfter(child);
      }
    }

    _topIndex = null;
    notifier?.value = null;
  }
```

Call it from `_onScroll`, after the pinned update:

```dart
  void _onScroll() {
    if (!controller.hasClients) return;
    _pinned = BlockViewport.isPinned(
      controller.position.pixels,
      controller.position.maxScrollExtent,
    );
    _updateSticky();
  }
```

and once per frame after the content itself changes, so an arriving block that lands under the top edge updates the header without any scrolling. Add to the end of `build`, wrapped so it runs after layout:

```dart
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateSticky();
    });
    ...
  }
```

This post-frame callback does no work when nothing changed, because the notifier dedupes on `StickyBlock`'s `props`.

- [ ] **Step 6: Host the overlay in `BlocksBody`**

`BlocksBody` must own the notifier's lifetime, so it becomes a `StatefulWidget` again — but with no scroll state of its own. Change the class declaration and add:

```dart
class BlocksBody extends StatefulWidget {
  const BlocksBody({super.key});

  @override
  State<BlocksBody> createState() => _BlocksBodyState();
}

class _BlocksBodyState extends State<BlocksBody> {
  final ValueNotifier<StickyBlock?> _sticky = ValueNotifier<StickyBlock?>(null);

  @override
  void dispose() {
    _sticky.dispose();
    super.dispose();
  }
```

and replace the `BlockList` return with:

```dart
        return Stack(
          children: [
            Positioned.fill(
              child: BlockList(
                sessionId: cubit.sessionId,
                blocks: cubit.blocks,
                header: _olderControl(context, cubit),
                sticky: _sticky,
              ),
            ),
            Positioned(top: 6, left: 0, right: 0, child: StickyBlockHeader(sticky: _sticky)),
          ],
        );
```

Add the `sticky_block_header.dart` import. Keep `_notice` and `_olderControl` as methods of the state class.

- [ ] **Step 7: Run the gates**

```bash
cd packages/mobile && flutter test test/feature/blocks/ && flutter analyze
```

Expected: all green, `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib/feature/blocks packages/mobile/test/feature/blocks
git commit -m "feat(mobile): pin the header of the block under the viewport top"
```

---

### Task 5: Block-boundary navigation and jump-to-latest

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart`
- Create: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_nav_controls.dart`
- Modify: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_screen/block_list_test.dart`

**Interfaces:**
- Consumes: `BlockViewport.nextBoundary`, `BlockViewport.previousBoundary` (Task 1); `BlockListState.topBlockIndex`, `jumpToLatest`, `pinned` (Tasks 3–4).
- Produces: `BlockListState.scrollToBoundary({required bool forward})` and `BlockListState.scrollBlockIntoView(int index)`; `class BlockNavControls extends StatelessWidget` taking `{required VoidCallback onPrevious, required VoidCallback onNext, required VoidCallback onLatest, required bool showLatest}`.

**Why "previous" sometimes means "the top of this block".** If the top block is scrolled halfway out of view, the useful previous stop is its own start, not the block before it. This matches how block navigation behaves in a terminal that has it, and it is the difference between one press feeling precise and feeling like it skipped.

- [ ] **Step 1: Write the failing tests**

Append to `main()` in `block_list_test.dart`:

```dart
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
    expect(tester.getTopLeft(find.byKey(const ValueKey('seq-2'))).dy, closeTo(0, 1.5));
  });

  testWidgets('previous returns to the top of a partly scrolled block first', (tester) async {
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

  testWidgets('previous from a boundary steps to the block before it', (tester) async {
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
    await pumpList(tester, range(1, 3), sticky: sticky);

    final state = tester.state<BlockListState>(find.byType(BlockList));
    state.controller.jumpTo(0);
    await tester.pumpAndSettle();
    final atTop = state.controller.position.pixels;

    state.scrollToBoundary(forward: false);
    await tester.pumpAndSettle();

    expect(state.controller.position.pixels, atTop);
  });
```

And a control test in `blocks_body_test.dart`:

```dart
  testWidgets('offers a way back to the newest block once scrolled away', (tester) async {
    when(() => cubit.blocks).thenReturn(List.generate(60, (index) => _block(id: 'seq-$index')));

    await _pump(tester, cubit);
    expect(find.text('Jump to latest'), findsNothing);

    final state = tester.state<BlockListState>(find.byType(BlockList));
    state.controller.jumpTo(0);
    await tester.pumpAndSettle();

    expect(find.text('Jump to latest'), findsOneWidget);
    await tester.tap(find.text('Jump to latest'));
    await tester.pumpAndSettle();
    expect(find.text('Jump to latest'), findsNothing);
  });
```

`_block` in that file takes `id` already; give each generated block a distinct `firstSeq` by adding a `firstSeq` parameter to the helper, defaulting to 1, and passing `index`. Update `_block` accordingly:

```dart
SessionBlock _block({
  String id = 'seq-1',
  int firstSeq = 1,
  ...
}) => SessionBlock(
  id: id,
  firstSeq: firstSeq,
  lastSeq: firstSeq,
  ...
);
```

and call it as `_block(id: 'seq-$index', firstSeq: index)`. Import `block_list.dart` there.

- [ ] **Step 2: Run them and confirm they fail**

```bash
cd packages/mobile && flutter test test/feature/blocks/
```

Expected: `The method 'scrollToBoundary' isn't defined for the class 'BlockListState'`, and `Jump to latest` not found.

- [ ] **Step 3: Add the scroll API to `BlockListState`**

```dart
  double? _viewportTopDelta(int index) {
    final viewport = viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final pivot = BlockViewport.pivotIndex(widget.blocks, _pivotSeq);

    for (final key in [leadingKey, centerKey]) {
      final sliver = key.currentContext?.findRenderObject();
      if (sliver is! RenderSliverMultiBoxAdaptor) continue;
      RenderBox? child = sliver.firstChild;
      while (child != null) {
        final sliverIndex = sliver.indexOf(child);
        final blockIndex = key == leadingKey ? pivot - 1 - sliverIndex : pivot + sliverIndex;
        if (blockIndex == index) return child.localToGlobal(Offset.zero).dy - top;
        child = sliver.childAfter(child);
      }
    }
    return null;
  }

  void scrollBlockIntoView(int index) {
    if (!controller.hasClients) return;
    final delta = _viewportTopDelta(index);
    if (delta == null) return;
    final position = controller.position;
    controller.jumpTo(
      (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void scrollToBoundary({required bool forward}) {
    if (!controller.hasClients) return;
    final current = _topIndex;
    if (forward) {
      final target = BlockViewport.nextBoundary(current, widget.blocks.length);
      if (target != null) scrollBlockIntoView(target);
      return;
    }
    if (current == null) return;
    final delta = _viewportTopDelta(current);
    if (delta != null && delta < -1) {
      scrollBlockIntoView(current);
      return;
    }
    final target = BlockViewport.previousBoundary(current, widget.blocks.length);
    if (target != null) scrollBlockIntoView(target);
  }
```

`_viewportTopDelta` returns `null` for a block that is not currently built. Adjacent blocks are always built or inside the sliver's cache extent, so the two navigation directions always find their target; a request for a far-away block is a no-op rather than a wrong jump.

- [ ] **Step 4: Write the controls**

Create `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/block_nav_controls.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class BlockNavControls extends StatelessWidget {
  const BlockNavControls({
    super.key,
    required this.onPrevious,
    required this.onNext,
    required this.onLatest,
    required this.showLatest,
  });

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onLatest;
  final bool showLatest;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          decoration: BoxDecoration(
            color: skin.bgElevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: skin.borderSubtle),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Step(icon: Icons.keyboard_arrow_up, onTap: onPrevious, tooltip: 'Previous block'),
              _Step(icon: Icons.keyboard_arrow_down, onTap: onNext, tooltip: 'Next block'),
            ],
          ),
        ),
        if (showLatest) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onLatest,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: skin.accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: AppText(
                'Jump to latest',
                style: AppTextStyle.style11SemiBold.copyWith(color: skin.onAccent),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap, required this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 32,
        child: Icon(icon, size: 18, color: context.skin.textSecondary),
      ),
    ),
  );
}
```

- [ ] **Step 5: Mount the controls**

First publish pinned-ness out of `BlockList`. Add the parameter to the constructor and the field:

```dart
  const BlockList({
    super.key,
    required this.sessionId,
    required this.blocks,
    this.header,
    this.sticky,
    this.pinnedListenable,
  });

  final ValueNotifier<bool>? pinnedListenable;
```

Publish it from `_onScroll`, right after `_pinned` is computed and before `_updateSticky()`:

```dart
    widget.pinnedListenable?.value = _pinned;
```

and from `jumpToLatest`, so the control disappears the moment it is tapped rather than a frame later:

```dart
  void jumpToLatest() {
    _pinned = true;
    widget.pinnedListenable?.value = true;
    _scheduleFollow();
  }
```

Then in `_BlocksBodyState` add the handle and the notifier, disposing the notifier:

```dart
  final GlobalKey<BlockListState> _listKey = GlobalKey<BlockListState>();
  final ValueNotifier<bool> _pinned = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _sticky.dispose();
    _pinned.dispose();
    super.dispose();
  }
```

Then in `BlocksBody`, add to the `Stack`:

```dart
            Positioned(
              right: 12,
              bottom: 12,
              child: ValueListenableBuilder<bool>(
                valueListenable: _pinned,
                builder: (context, pinned, _) => BlockNavControls(
                  onPrevious: () => _listKey.currentState?.scrollToBoundary(forward: false),
                  onNext: () => _listKey.currentState?.scrollToBoundary(forward: true),
                  onLatest: () => _listKey.currentState?.jumpToLatest(),
                  showLatest: !pinned,
                ),
              ),
            ),
```

and give the `BlockList` `key: _listKey` and `pinnedListenable: _pinned`.

- [ ] **Step 6: Run the gates**

```bash
cd packages/mobile && flutter test && flutter analyze
```

Run the **whole** suite here, not just the blocks directory — `blocks_body.dart` is reachable from the terminal screen's tests.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/lib/feature/blocks packages/mobile/test/feature/blocks
git commit -m "feat(mobile): navigate block boundaries and return to the newest block"
```

---

### Task 6: Prove scrolling stays cheap

The spec calls frame-time profiling "part of the work, not an afterthought", and names the failure directly: parity is lost if the list re-renders during scroll. These three assertions are that obligation in a form CI can run.

**Files:**
- Test: `packages/mobile/test/feature/blocks/presentation/blocks_screen/block_list_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 2–5. Adds no production code unless an assertion fails.

- [ ] **Step 1: Write the tests**

Append to `main()` in `block_list_test.dart`:

```dart
  testWidgets('scrolling does not rebuild the list subtree', (tester) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, range(1, 200, lines: (seq) => 1 + seq % 4), sticky: sticky);

    final before = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;

    for (var step = 0; step < 12; step++) {
      controller.jumpTo(controller.position.pixels - 40);
      await tester.pump();
    }

    final after = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    expect(
      identical(before, after),
      isTrue,
      reason: 'a setState on scroll would rebuild every visible card every frame',
    );
  });

  testWidgets('the sticky header notifies per boundary, not per frame', (tester) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, range(1, 200, lines: (seq) => 8), sticky: sticky);

    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;
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

  testWidgets('a long session keeps its built window small while scrolling', (tester) async {
    final sticky = ValueNotifier<StickyBlock?>(null);
    addTearDown(sticky.dispose);
    await pumpList(tester, range(1, 800, lines: (seq) => 1 + seq % 5), sticky: sticky);

    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;
    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();

    final built = find.byType(BlockCard, skipOffstage: false).evaluate().length;
    expect(built, lessThan(40));
    expect(built, greaterThan(0));
  });
```

- [ ] **Step 2: Run them**

```bash
cd packages/mobile && flutter test test/feature/blocks/presentation/blocks_screen/block_list_test.dart
```

Expected: all three pass against the code from Tasks 2–5. **If one fails, it is a real defect in this plan's own output, not a test to relax:**

- `identical(before, after)` false → something calls `setState` on scroll. The pinned flag, the top index and the sticky value are all plain fields or notifiers precisely so they do not.
- non-zero notifications → `StickyBlock.props` is including something that changes mid-block (a `body`, a height that is being re-measured), or `_updateSticky` is constructing a value even when nothing changed.
- built count ≥ 40 → a sliver lost its laziness, most likely by something forcing a full `itemCount` build such as a `shrinkWrap: true` or a `SliverChildListDelegate` in place of `SliverList.builder`.

- [ ] **Step 3: Run the full gates**

```bash
cd packages/mobile && flutter analyze && flutter test
```

Expected: `No issues found!` and a green suite.

- [ ] **Step 4: Commit**

```bash
git add packages/mobile/test/feature/blocks
git commit -m "test(mobile): pin the scroll cost of the block viewport"
```

---

## Done means

- `flutter analyze` prints `No issues found!` and `flutter test` is green from `packages/mobile`.
- Opening a covered `tui` session lands on the newest block, not the oldest.
- "Load older blocks" adds a page above without moving what is on screen.
- A block arriving while scrolled up does not move the view; one arriving while pinned is followed.
- The header of the block under the top edge is pinned there, unless that block is taller than the viewport.
- The chevrons step block by block and "Jump to latest" appears only when the view has left the tail.
- No file added or changed by this plan contains a comment.
