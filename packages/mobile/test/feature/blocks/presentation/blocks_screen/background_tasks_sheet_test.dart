import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/working_clock.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';
import 'package:operator_mobile/core/widgets/motion/shimmer.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/blocks/logic/background_tasks.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/background_tasks_sheet.dart';

class _MockBlocksCubit extends MockCubit<BlocksState> implements BlocksCubit {}

final DateTime _start = DateTime.utc(2026, 9, 19, 10);

SessionBlock _agent(String id, String agentId, {String status = 'running', int second = 0}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.tool,
  status: switch (status) {
    'running' => BlockStatus.running,
    'failed' => BlockStatus.failed,
    _ => BlockStatus.ok,
  },
  title: 'Agent',
  body: '',
  toolName: 'Agent',
  createdAt: _start.add(Duration(seconds: second)).toIso8601String(),
  detail: AgentBlockDetail(
    description: 'Task $id',
    agentId: agentId,
    agentType: 'Explore',
    status: status,
    durationMs: status == 'running' ? null : 5000,
    toolUseCount: 3,
  ),
);

BackgroundTask _shell(String id, {BackgroundTaskStatus status = BackgroundTaskStatus.running, bool canStop = false}) =>
    BackgroundTask(
      id: id,
      kind: BackgroundTaskKind.shell,
      title: 'Shell $id',
      status: status,
      startedAt: _start,
      canStop: canStop,
    );

void main() {
  late _MockBlocksCubit cubit;
  late StreamController<BlocksState> states;
  late DateTime now;
  late WorkingClock clock;
  final haptics = <String>[];
  final pushed = <RouteSettings>[];

  setUp(() {
    haptics.clear();
    pushed.clear();
    now = _start.add(const Duration(minutes: 2, seconds: 5));
    clock = WorkingClock(now: () => now);
    cubit = _MockBlocksCubit();
    states = StreamController<BlocksState>.broadcast();
    whenListen(cubit, states.stream, initialState: const BlocksReadyState(1));
    when(() => cubit.subagentSummaries).thenReturn(const {});
    when(() => cubit.sessionId).thenReturn('s-1');
    when(() => cubit.harness).thenReturn('claude-code');
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

  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
  }

  Future<void> open(
    WidgetTester tester, {
    List<BackgroundTask> Function(BlocksCubit cubit)? tasksOf,
    void Function(BackgroundTask task)? onStop,
  }) async {
    phone(tester);
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            onGenerateRoute: (settings) {
              if (settings.name != RoutesStrings.subagent) return null;
              pushed.add(settings);
              return MaterialPageRoute<void>(settings: settings, builder: (_) => const Scaffold(body: Text('subagent page')));
            },
            home: BlocProvider<BlocksCubit>.value(
              value: cubit,
              child: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () => showBackgroundTasksSheet(
                        context,
                        parentTitle: 'Parent chat',
                        clock: clock,
                        tasksOf: tasksOf,
                        onStop: onStop,
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  bool shimmers(WidgetTester tester, String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(Shimmer)).evaluate().isNotEmpty;

  testWidgets('lists running cards with their live elapsed time, then the finished ones by status', (tester) async {
    when(() => cubit.blocks).thenReturn([
      _agent('1', 'a1'),
      _agent('2', 'a2', second: 30),
      _agent('3', 'a3', status: 'completed'),
      _agent('4', 'a4', status: 'failed'),
    ]);
    await open(tester);

    expect(find.text('Background tasks'), findsOneWidget);
    expect(find.byKey(AppSheet.closeKey), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Finished 2'), findsOneWidget);
    for (final title in ['Task 1', 'Task 2', 'Task 3', 'Task 4']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('2m 5s'), findsOneWidget);
    expect(find.text('1m 35s'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Failed')).style?.color, const DarkSkin().red);
    expect(find.text('Agent'), findsNWidgets(4));
    expect(find.text('View transcript'), findsNWidgets(4));
    expect(find.byKey(BackgroundTasksView.agentGlyphKey), findsNWidgets(4));
    expect(tester.getSize(find.byKey(BackgroundTasksView.agentGlyphKey).first), const Size(10, 10));
    expect(find.text('5s'), findsNothing);

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Running'), lessThan(top('Task 1')));
    expect(top('Task 1'), lessThan(top('Task 2')));
    expect(top('Task 2'), lessThan(top('Finished 2')));
    expect(top('Finished 2'), lessThan(top('Task 3')));

    expect(shimmers(tester, 'Task 1'), isTrue);
    expect(shimmers(tester, 'Task 3'), isFalse);
    expect(tester.widget<Text>(find.text('Task 3')).style?.color, const DarkSkin().textPrimary);
  });

  testWidgets('cards are rounded 16 elevated tiles 12pt apart', (tester) async {
    when(() => cubit.blocks).thenReturn([_agent('1', 'a1'), _agent('2', 'a2', second: 1)]);
    await open(tester);

    final cards = find.byKey(BackgroundTasksView.cardKey);
    expect(cards, findsNWidgets(2));
    final material = tester.widget<Material>(cards.first);
    expect(material.color, const DarkSkin().bgElevated);
    expect(material.borderRadius, BorderRadius.circular(16));
    expect(tester.getTopLeft(cards.at(1)).dy - tester.getBottomLeft(cards.first).dy, 12);
    expect(tester.getTopLeft(find.text('Task 1')).dy - tester.getTopLeft(cards.first).dy, 16);
  });

  testWidgets('the elapsed time ticks every second from the shared clock', (tester) async {
    when(() => cubit.blocks).thenReturn([_agent('1', 'a1')]);
    await open(tester);
    expect(find.text('2m 5s'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(WorkingClock.period);
    expect(find.text('2m 6s'), findsOneWidget);
  });

  testWidgets('nothing running shows No running tasks, and no finished hides that section', (tester) async {
    when(() => cubit.blocks).thenReturn(const []);
    await open(tester);

    expect(find.text('No running tasks'), findsOneWidget);
    expect(find.textContaining('Finished'), findsNothing);
  });

  testWidgets('a section header collapses and expands its cards with a haptic', (tester) async {
    when(() => cubit.blocks).thenReturn([_agent('1', 'a1'), _agent('3', 'a3', status: 'completed')]);
    await open(tester);

    double height() => tester.getSize(
      find.ancestor(of: find.text('Task 3'), matching: find.byType(Disclosure)).first,
    ).height;
    final full = height();
    expect(
      tester.widget<DisclosureChevron>(
        find.descendant(of: find.byKey(const ValueKey('section-Finished')), matching: find.byType(DisclosureChevron)),
      ).expanded,
      isTrue,
    );

    await tester.tap(find.text('Finished 1'));
    await tester.pump();
    await tester.pump(AppMotion.disclosure ~/ 2);
    expect(height(), inExclusiveRange(0, full));
    await settle(tester);
    expect(find.text('Task 3'), findsNothing);
    expect(find.text('Task 1'), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.selectionClick']);

    await tester.tap(find.text('Finished 1'));
    await settle(tester);
    expect(find.text('Task 3'), findsOneWidget);
    expect(haptics, hasLength(2));

    await tester.tap(find.text('Running'));
    await settle(tester);
    expect(find.text('Task 1'), findsNothing);
  });

  testWidgets('tapping a card closes the sheet and opens that subagent', (tester) async {
    when(() => cubit.blocks).thenReturn([_agent('1', 'a1'), _agent('3', 'a3', status: 'completed')]);
    await open(tester);

    await tester.tap(find.text('Task 3'));
    await settle(tester);

    expect(find.text('Background tasks'), findsNothing);
    expect(find.text('subagent page'), findsOneWidget);
    final arguments = pushed.single.arguments! as Map<String, Object?>;
    expect(arguments['sessionId'], 's-1');
    expect(arguments['agentId'], 'a3');
    expect((arguments['detail']! as AgentBlockDetail).description, 'Task 3');
    expect(arguments['harness'], 'claude-code');
    expect(arguments['parentTitle'], 'Parent chat');
  });

  testWidgets('View transcript opens the running subagent too', (tester) async {
    when(() => cubit.blocks).thenReturn([_agent('1', 'a1')]);
    await open(tester);

    await tester.tap(find.text('View transcript'));
    await settle(tester);

    expect((pushed.single.arguments! as Map<String, Object?>)['agentId'], 'a1');
  });

  testWidgets('a task that finishes while the sheet is open moves from Running to Finished', (tester) async {
    when(() => cubit.blocks).thenReturn([_agent('1', 'a1'), _agent('2', 'a2', second: 1)]);
    await open(tester);
    expect(find.textContaining('Finished'), findsNothing);

    when(() => cubit.blocks).thenReturn([_agent('1', 'a1', status: 'completed'), _agent('2', 'a2', second: 1)]);
    states.add(const BlocksReadyState(2));
    await settle(tester);

    expect(find.text('Finished 1'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Task 1')).dy, greaterThan(tester.getTopLeft(find.text('Finished 1')).dy));
    expect(tester.getTopLeft(find.text('Task 2')).dy, lessThan(tester.getTopLeft(find.text('Finished 1')).dy));
    expect(find.text('Completed'), findsOneWidget);
    expect(shimmers(tester, 'Task 1'), isFalse);

    when(() => cubit.blocks).thenReturn([_agent('1', 'a1', status: 'completed'), _agent('2', 'a2', status: 'completed')]);
    states.add(const BlocksReadyState(3));
    await settle(tester);
    expect(find.text('No running tasks'), findsOneWidget);
    expect(find.text('Finished 2'), findsOneWidget);
  });

  testWidgets('shell tasks show a terminal glyph and Shell, and no transcript link', (tester) async {
    when(() => cubit.blocks).thenReturn([_agent('1', 'a1', second: 10)]);
    await open(
      tester,
      tasksOf: (cubit) => sortBackgroundTasks([
        ...backgroundTasksOf(cubit.blocks, cubit.subagentSummaries),
        _shell('run'),
        _shell('done', status: BackgroundTaskStatus.completed),
        _shell('stop', status: BackgroundTaskStatus.stopped),
      ]),
    );

    expect(find.byIcon(Icons.terminal_outlined), findsNWidgets(3));
    expect(find.text('Shell'), findsNWidgets(3));
    expect(find.text('View transcript'), findsOneWidget);
    expect(find.text('2m 5s'), findsOneWidget);
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Shell run')).dy, lessThan(tester.getTopLeft(find.text('Task 1')).dy));
    expect(shimmers(tester, 'Shell run'), isTrue);

    await tester.tap(find.text('Shell done'));
    await settle(tester);
    expect(pushed, isEmpty);
    expect(find.text('Background tasks'), findsOneWidget);
  });

  testWidgets('the stop button shows only for a task that can stop, and taps stop it', (tester) async {
    when(() => cubit.blocks).thenReturn(const []);
    final stopped = <String>[];
    await open(
      tester,
      tasksOf: (_) => [_shell('a', canStop: true), _shell('b')],
      onStop: (task) => stopped.add(task.id),
    );

    final stop = find.byKey(BackgroundTasksView.stopKey);
    expect(stop, findsOneWidget);
    expect(tester.getSize(stop), const Size(28, 28));
    expect(tester.getTopLeft(stop).dy, closeTo(tester.getTopLeft(find.text('Shell a')).dy, 2));

    await tester.tap(stop);
    await tester.pump();
    expect(stopped, ['a']);
  });

  testWidgets('the close button closes the sheet', (tester) async {
    when(() => cubit.blocks).thenReturn([_agent('1', 'a1')]);
    await open(tester);

    await tester.tap(find.byKey(AppSheet.closeKey));
    await settle(tester);

    expect(find.text('Background tasks'), findsNothing);
    expect(clock.ticking, isFalse);
  });
}
