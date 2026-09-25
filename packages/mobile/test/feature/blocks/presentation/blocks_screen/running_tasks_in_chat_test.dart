import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/background_tasks_sheet.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/running_tasks_bubble.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/thinking_row.dart';

class _MockBlocksCubit extends MockCubit<BlocksState> implements BlocksCubit {}

class _MockSessionCommandCubit extends MockCubit<SessionCommandState> implements SessionCommandCubit {}

String _recent(int secondsAgo) => DateTime.now().toUtc().subtract(Duration(seconds: secondsAgo)).toIso8601String();

SessionBlock _agent(int seq, {bool running = true}) => SessionBlock(
  id: 'agent-$seq',
  turnId: 't',
  firstSeq: seq,
  lastSeq: seq,
  kind: BlockKind.tool,
  status: running ? BlockStatus.running : BlockStatus.ok,
  title: 'Agent',
  body: '',
  toolName: 'Agent',
  createdAt: _recent(5),
  detail: AgentBlockDetail(description: 'Task $seq', agentId: 'a$seq', status: running ? 'running' : 'completed'),
);

SessionBlock _text(int seq, {BlockKind kind = BlockKind.assistant, int lines = 1}) => SessionBlock(
  id: 'text-$seq',
  turnId: 't',
  firstSeq: seq,
  lastSeq: seq,
  kind: kind,
  status: BlockStatus.ok,
  title: kind == BlockKind.prompt ? 'Prompt' : 'Assistant',
  body: [for (var line = 0; line < lines; line++) 'line $line of block $seq'].join('\n'),
  createdAt: _recent(60),
);

void main() {
  late _MockBlocksCubit cubit;
  late StreamController<BlocksState> states;
  final haptics = <String>[];

  setUp(() {
    haptics.clear();
    cubit = _MockBlocksCubit();
    states = StreamController<BlocksState>.broadcast();
    whenListen(cubit, states.stream, initialState: const BlocksReadyState(1));
    when(() => cubit.sessionId).thenReturn('s-1');
    when(() => cubit.supported).thenReturn(true);
    when(() => cubit.harness).thenReturn('claude-code');
    when(() => cubit.loading).thenReturn(false);
    when(() => cubit.active).thenReturn(true);
    when(() => cubit.loadingOlder).thenReturn(false);
    when(() => cubit.hasOlder).thenReturn(false);
    when(() => cubit.error).thenReturn(null);
    when(() => cubit.subagentSummaries).thenReturn(const {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
        return null;
      },
    );
  });

  tearDown(() async {
    await states.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  Future<void> pump(WidgetTester tester, {bool showRunningTasks = true}) {
    final commands = _MockSessionCommandCubit();
    when(() => commands.state).thenReturn(const SessionCommandState());
    when(() => commands.stream).thenAnswer((_) => const Stream.empty());
    when(() => commands.close()).thenAnswer((_) async {});
    return tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<BlocksCubit>.value(value: cubit),
                  BlocProvider<SessionCommandCubit>.value(value: commands),
                ],
                child: SizedBox(
                  width: 400,
                  height: 700,
                  child: BlocksBody(showRunningTasks: showRunningTasks, parentTitle: 'Parent'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> frames(WidgetTester tester, [int count = 20]) async {
    for (var frame = 0; frame < count; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> emit(WidgetTester tester, List<SessionBlock> blocks, int version) async {
    when(() => cubit.blocks).thenReturn(blocks);
    states.add(BlocksReadyState(version));
    await tester.pump();
  }

  testWidgets('hidden while no subagent runs', (tester) async {
    when(() => cubit.blocks).thenReturn([_text(1, kind: BlockKind.prompt), _agent(2, running: false), _text(3)]);
    await pump(tester);
    await frames(tester);

    expect(find.byType(RunningTasksBubble), findsNothing);
  });

  testWidgets('shows one running task in the singular and three in the plural', (tester) async {
    when(() => cubit.blocks).thenReturn([_text(1, kind: BlockKind.prompt), _agent(2)]);
    await pump(tester);
    await frames(tester);
    expect(find.text('1 running task'), findsOneWidget);

    await emit(tester, [_text(1, kind: BlockKind.prompt), _agent(2), _agent(3), _agent(4), _agent(5, running: false)], 2);
    await frames(tester);
    expect(find.text('3 running tasks'), findsOneWidget);
  });

  testWidgets('sits after the last block and the Thinking row, at the assistant text inset', (tester) async {
    when(() => cubit.blocks).thenReturn([_text(1, kind: BlockKind.prompt), _agent(2), _text(3, kind: BlockKind.prompt)]);
    await pump(tester);
    await frames(tester);

    final bubble = tester.getRect(find.byKey(RunningTasksBubble.capsuleKey));
    final thinking = tester.getRect(find.byType(ThinkingRow));
    final lastBlock = tester.getRect(find.text('line 0 of block 3'));
    expect(bubble.top, greaterThanOrEqualTo(thinking.bottom));
    expect(thinking.top, greaterThanOrEqualTo(lastBlock.bottom));
    expect(bubble.left, 16);
  });

  testWidgets('never shows on a host that does not ask for it', (tester) async {
    when(() => cubit.blocks).thenReturn([_text(1, kind: BlockKind.prompt), _agent(2)]);
    await pump(tester, showRunningTasks: false);
    await frames(tester);

    expect(find.byType(RunningTasksBubble), findsNothing);
  });

  testWidgets('shrinks away when the last task finishes: mid-size at half the duration, gone at the end', (tester) async {
    when(() => cubit.blocks).thenReturn([_text(1, kind: BlockKind.prompt), _agent(2)]);
    await pump(tester);
    await frames(tester);
    double height() => tester.getSize(
      find.ancestor(of: find.byType(RunningTasksBubble), matching: find.byType(Disclosure)).first,
    ).height;
    final full = height();
    expect(full, greaterThan(RunningTasksBubble.height));

    await emit(tester, [_text(1, kind: BlockKind.prompt), _agent(2, running: false)], 2);
    await tester.pump(AppMotion.disclosure ~/ 2);
    expect(find.text('1 running task'), findsOneWidget);
    expect(height(), inExclusiveRange(0, full));

    await frames(tester);
    expect(find.byType(RunningTasksBubble), findsNothing);
  });

  testWidgets('a tap opens Background tasks with the running titles, their elapsed time and a haptic', (tester) async {
    when(() => cubit.blocks).thenReturn([_text(1, kind: BlockKind.prompt), _agent(2), _agent(3)]);
    await pump(tester);
    await frames(tester);

    await tester.tap(find.byType(RunningTasksBubble));
    await frames(tester, 40);

    expect(haptics, contains('HapticFeedbackType.selectionClick'));
    expect(find.text('Background tasks'), findsOneWidget);
    Finder inSheet(Finder finder) => find.descendant(of: find.byType(BackgroundTasksView), matching: finder);
    expect(inSheet(find.text('Task 2')), findsOneWidget);
    expect(inSheet(find.text('Task 3')), findsOneWidget);
    expect(inSheet(find.textContaining(RegExp(r'^\d+s$'))), findsNWidgets(2));
  });

  testWidgets('appearing while pinned keeps the list pinned to the new tail', (tester) async {
    final long = [_text(1, kind: BlockKind.prompt), _text(2, lines: 80)];
    when(() => cubit.blocks).thenReturn(long);
    await pump(tester);
    await frames(tester);
    final list = tester.state<BlockListState>(find.byType(BlockList));
    expect(list.pinned, isTrue);

    await emit(tester, [...long, _agent(3)], 2);
    for (var frame = 0; frame < 16; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(list.pinned, isTrue);
    }

    final position = list.controller.position;
    expect(find.text('1 running task'), findsOneWidget);
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
    expect(tester.getRect(find.byKey(RunningTasksBubble.capsuleKey)).bottom, lessThanOrEqualTo(700));
  });

  testWidgets('selection mode hides the bubble', (tester) async {
    when(() => cubit.blocks).thenReturn([_text(1, kind: BlockKind.prompt), _agent(2), _text(3)]);
    await pump(tester);
    await frames(tester);
    expect(find.byType(RunningTasksBubble), findsOneWidget);

    await tester.longPress(find.text('line 0 of block 3'));
    await frames(tester);
    expect(find.byType(RunningTasksBubble), findsNothing);
  });
}
