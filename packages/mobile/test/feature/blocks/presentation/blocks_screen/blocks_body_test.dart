import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_find_bar.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart';

class _MockBlocksCubit extends MockCubit<BlocksState> implements BlocksCubit {}

SessionBlock _block({
  String id = 'seq-1',
  int firstSeq = 1,
  BlockKind kind = BlockKind.tool,
  BlockStatus status = BlockStatus.ok,
  String title = 'Bash',
  String body = 'ok',
  String? errorType,
  int truncatedLines = 0,
  bool redacted = false,
}) => SessionBlock(
  id: id,
  firstSeq: firstSeq,
  lastSeq: firstSeq,
  kind: kind,
  status: status,
  title: title,
  body: body,
  errorType: errorType,
  truncatedLines: truncatedLines,
  redacted: redacted,
);

Future<void> _pump(WidgetTester tester, _MockBlocksCubit cubit) =>
    tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<BlocksCubit>.value(
                value: cubit,
                child: const SizedBox(
                  width: 400,
                  height: 700,
                  child: BlocksBody(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _showOlderControl(WidgetTester tester) async {
  final controller = tester
      .state<BlockListState>(find.byType(BlockList))
      .controller;
  controller.jumpTo(controller.position.minScrollExtent);
  await tester.pumpAndSettle();
}

void main() {
  late _MockBlocksCubit cubit;

  setUp(() {
    cubit = _MockBlocksCubit();
    when(() => cubit.state).thenReturn(const BlocksReadyState(1));
    when(() => cubit.sessionId).thenReturn('s-1');
    when(() => cubit.supported).thenReturn(true);
    when(() => cubit.harness).thenReturn('claude-code');
    when(() => cubit.blocks).thenReturn(const []);
    when(() => cubit.loading).thenReturn(false);
    when(() => cubit.loadingOlder).thenReturn(false);
    when(() => cubit.hasOlder).thenReturn(false);
    when(() => cubit.error).thenReturn(null);
    when(() => cubit.refresh()).thenAnswer((_) async {});
    when(() => cubit.loadOlder()).thenAnswer((_) async {});
  });

  testWidgets('renders one card per block', (tester) async {
    when(() => cubit.blocks).thenReturn([
      _block(
        id: 'seq-1',
        kind: BlockKind.prompt,
        title: 'Prompt',
        body: 'run the tests',
      ),
      _block(id: 'src-tu-1', title: 'Bash', body: 'ok 42 tests'),
    ]);

    await _pump(tester, cubit);

    expect(find.byType(BlockCard), findsNWidgets(2));
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('run the tests'), findsOneWidget);
    expect(find.text('ok 42 tests'), findsOneWidget);
  });

  testWidgets('a long body wraps instead of being clipped to one line', (
    tester,
  ) async {
    final long = List.filled(40, 'wrapping').join(' ');
    when(() => cubit.blocks).thenReturn([_block(body: long)]);

    await _pump(tester, cubit);

    final text = tester.widget<Text>(find.text(long));
    expect(
      text.maxLines,
      isNull,
      reason: 'a block body must not be capped to one line',
    );
    expect(text.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('says how much was dropped rather than dropping it silently', (
    tester,
  ) async {
    when(() => cubit.blocks).thenReturn([_block(truncatedLines: 4212)]);

    await _pump(tester, cubit);

    expect(find.textContaining('4212'), findsOneWidget);
    expect(find.textContaining('truncated'), findsOneWidget);
  });

  testWidgets('marks a block that had secrets removed', (tester) async {
    when(() => cubit.blocks).thenReturn([_block(redacted: true)]);

    await _pump(tester, cubit);

    expect(find.textContaining('redacted'), findsOneWidget);
  });

  testWidgets('shows a permission request as blocked and names the tool', (
    tester,
  ) async {
    when(() => cubit.blocks).thenReturn([
      _block(
        id: 'src-pr-1',
        kind: BlockKind.permission,
        status: BlockStatus.blocked,
        title: 'Permission requested',
        body: 'Bash\ngit branch -D feat/x',
      ),
    ]);

    await _pump(tester, cubit);

    expect(find.text('Permission requested'), findsOneWidget);
    expect(find.textContaining('git branch -D feat/x'), findsOneWidget);
  });

  testWidgets('says blocks are unavailable for an uncovered harness', (
    tester,
  ) async {
    when(() => cubit.state).thenReturn(const BlocksUnsupportedState('aider'));
    when(() => cubit.supported).thenReturn(false);
    when(() => cubit.harness).thenReturn('aider');

    await _pump(tester, cubit);

    expect(find.textContaining('aider'), findsOneWidget);
    expect(find.byType(BlockCard), findsNothing);
  });

  testWidgets('an empty covered session says so instead of showing nothing', (
    tester,
  ) async {
    await _pump(tester, cubit);

    expect(find.byType(BlockCard), findsNothing);
    expect(find.textContaining('No blocks yet'), findsOneWidget);
  });

  testWidgets('a failed tool is visibly failed', (tester) async {
    when(() => cubit.blocks).thenReturn([
      _block(
        status: BlockStatus.failed,
        errorType: 'tool_failed',
        body: 'no such table',
      ),
    ]);

    await _pump(tester, cubit);

    final dot = tester.widget<BlockStatusDot>(find.byType(BlockStatusDot));
    expect(dot.status, BlockStatus.failed);
    expect(find.textContaining('no such table'), findsOneWidget);
  });

  testWidgets('offers to load older blocks only when there are some', (
    tester,
  ) async {
    when(() => cubit.blocks).thenReturn([_block()]);
    when(() => cubit.hasOlder).thenReturn(true);

    await _pump(tester, cubit);
    await _showOlderControl(tester);
    expect(find.text('Load older blocks'), findsOneWidget);

    await tester.tap(find.text('Load older blocks'));
    await tester.pump();
    verify(() => cubit.loadOlder()).called(1);
  });

  testWidgets('hides the older control once the log is exhausted', (
    tester,
  ) async {
    when(() => cubit.blocks).thenReturn([_block()]);
    when(() => cubit.hasOlder).thenReturn(false);

    await _pump(tester, cubit);

    expect(find.text('Load older blocks'), findsNothing);
  });

  testWidgets('shows progress instead of the control while paging back', (
    tester,
  ) async {
    when(() => cubit.blocks).thenReturn([_block()]);
    when(() => cubit.hasOlder).thenReturn(true);
    when(() => cubit.loadingOlder).thenReturn(true);

    await _pump(tester, cubit);
    await _showOlderControl(tester);

    expect(find.text('Load older blocks'), findsNothing);
    expect(find.textContaining('Loading older'), findsOneWidget);
  });

  testWidgets('surfaces a load failure and offers a retry', (tester) async {
    when(() => cubit.error).thenReturn('offline');

    await _pump(tester, cubit);

    expect(find.textContaining('offline'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    verify(() => cubit.refresh()).called(1);
  });

  testWidgets('offers a way back to the newest block once scrolled away', (
    tester,
  ) async {
    when(() => cubit.blocks).thenReturn(
      List.generate(60, (index) => _block(id: 'seq-$index', firstSeq: index)),
    );

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

  testWidgets(
    'dragging from the visible sticky header scrolls the block list',
    (tester) async {
      when(() => cubit.blocks).thenReturn(
        List.generate(
          60,
          (index) => _block(id: 'seq-$index', firstSeq: index, body: 'body'),
        ),
      );

      await _pump(tester, cubit);
      final state = tester.state<BlockListState>(find.byType(BlockList));
      state.controller.jumpTo(0);
      await tester.pumpAndSettle();

      final header = tester.getRect(find.byType(StickyBlockHeader));
      final before = state.controller.position.pixels;
      await tester.dragFrom(header.center, const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(state.controller.position.pixels, greaterThan(before));
    },
  );

  testWidgets(
    'resets find state when the session id changes',
    (tester) async {
      when(() => cubit.blocks).thenReturn([
        _block(
          id: 'seq-1',
          kind: BlockKind.prompt,
          title: 'Prompt',
          body: 'run the tests',
        ),
        _block(id: 'seq-2', firstSeq: 2, title: 'Bash', body: 'ok 42 tests'),
        _block(id: 'seq-3', firstSeq: 3, title: 'Grep', body: 'more tests'),
      ]);

      await _pump(tester, cubit);

      final state = tester.state<BlocksBodyState>(find.byType(BlocksBody));
      state.openFind();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'tests');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_downward));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.filter_alt_outlined));
      await tester.pump();

      expect(find.byType(BlockFindBar), findsOneWidget);
      final findBar = tester.widget<BlockFindBar>(find.byType(BlockFindBar));
      expect(findBar.queryController.text, 'tests');
      expect(findBar.filtering, isTrue);

      final cubitB = _MockBlocksCubit();
      when(() => cubitB.state).thenReturn(const BlocksReadyState(1));
      when(() => cubitB.sessionId).thenReturn('s-2');
      when(() => cubitB.supported).thenReturn(true);
      when(() => cubitB.harness).thenReturn('claude-code');
      when(() => cubitB.blocks).thenReturn([
        _block(
          id: 'seq-1',
          kind: BlockKind.prompt,
          title: 'Prompt',
          body: 'run the tests',
        ),
      ]);
      when(() => cubitB.loading).thenReturn(false);
      when(() => cubitB.loadingOlder).thenReturn(false);
      when(() => cubitB.hasOlder).thenReturn(false);
      when(() => cubitB.error).thenReturn(null);
      when(() => cubitB.refresh()).thenAnswer((_) async {});
      when(() => cubitB.loadOlder()).thenAnswer((_) async {});

      await _pump(tester, cubitB);
      await tester.pump();

      expect(find.byType(BlockFindBar), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.filter_alt), findsNothing);
      expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);

      final sameState = tester.state<BlocksBodyState>(find.byType(BlocksBody));
      expect(identical(sameState, state), isTrue);
    },
  );
}
