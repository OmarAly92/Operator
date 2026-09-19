import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/subagents.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/subagent_strip.dart';

class _MockBlocksCubit extends MockCubit<BlocksState> implements BlocksCubit {}

SessionBlock _agent(String id, String agentId, {bool running = true}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.tool,
  status: running ? BlockStatus.running : BlockStatus.ok,
  title: 'Agent',
  body: '',
  toolName: 'Agent',
  createdAt: '2026-09-19T10:00:00Z',
  detail: AgentBlockDetail(description: 'Task $id', agentId: agentId, status: running ? 'running' : 'completed', durationMs: 5000, toolUseCount: 3),
);

Future<void> _pump(WidgetTester tester, _MockBlocksCubit cubit, {void Function(SubagentEntry)? onOpen}) => tester.pumpWidget(
  SkinScope(
    skin: const DarkSkin(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        home: Scaffold(body: BlocProvider<BlocksCubit>.value(value: cubit, child: SubagentStrip(onOpen: onOpen))),
      ),
    ),
  ),
);

void main() {
  late _MockBlocksCubit cubit;

  setUp(() {
    cubit = _MockBlocksCubit();
    when(() => cubit.state).thenReturn(const BlocksReadyState(1));
    when(() => cubit.subagentSummaries).thenReturn(const {});
  });

  testWidgets('renders nothing without agents', (tester) async {
    when(() => cubit.blocks).thenReturn(const []);
    await _pump(tester, cubit);
    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.textContaining('done'), findsNothing);
  });

  testWidgets('lists running agents and folds finished ones into a count', (tester) async {
    when(() => cubit.blocks).thenReturn([_agent('1', 'a1'), _agent('2', 'a2', running: false), _agent('3', 'a3', running: false)]);
    SubagentEntry? opened;
    await _pump(tester, cubit, onOpen: (entry) => opened = entry);

    expect(find.text('Task 1'), findsOneWidget);
    expect(find.text('2 done'), findsOneWidget);
    expect(find.text('Task 2'), findsNothing);

    await tester.tap(find.text('Task 1'));
    expect(opened?.agentId, 'a1');

    await tester.tap(find.text('2 done'));
    await tester.pumpAndSettle();
    expect(find.text('Task 2'), findsOneWidget);
    expect(find.text('Task 3'), findsOneWidget);
    await tester.tap(find.text('Task 3'));
    await tester.pumpAndSettle();
    expect(opened?.agentId, 'a3');
  });
}
