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
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

class MockSessionCommandCubit extends Mock implements SessionCommandCubit {}

class _MockBlocksCubit extends MockCubit<BlocksState> implements BlocksCubit {}

SessionBlock _permissionBlock({String? interactionId}) => SessionBlock(
  id: 'b-1',
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.permission,
  status: BlockStatus.blocked,
  title: 'Permission requested',
  body: 'Bash: rm -rf /tmp/x',
  interactionId: interactionId,
);

SessionBlock _questionBlock({
  String? interactionId,
  required List<String> options,
  bool multiSelect = false,
  BlockStatus status = BlockStatus.blocked,
  String? result,
}) =>
    SessionBlock(
      id: 'b-2',
      firstSeq: 1,
      lastSeq: 1,
      kind: BlockKind.notice,
      status: status,
      title: 'Which one?',
      body: '',
      result: result,
      interactionId: interactionId,
      detail: QuestionBlockDetail(
        questions: [
          BlockQuestion(
            question: 'Which one?',
            multiSelect: multiSelect,
            options: [for (final option in options) BlockQuestionOption(label: option)],
          ),
        ],
      ),
    );

SessionBlock _agentBlock({String status = 'running', BlockStatus blockStatus = BlockStatus.running}) => SessionBlock(
  id: 'src-toolu_a',
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.tool,
  status: blockStatus,
  title: 'Agent',
  body: '',
  toolName: 'Agent',
  createdAt: DateTime.now().toUtc().subtract(const Duration(seconds: 75)).toIso8601String(),
  detail: AgentBlockDetail(description: 'Implement Task 1', prompt: 'p', model: 'haiku', agentType: 'general-purpose', agentId: 'a1', status: status, toolUseCount: 7, durationMs: 362000),
);

void _stubBloc(MockSessionCommandCubit cubit) {
  when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
  when(() => cubit.state).thenReturn(const SessionCommandState());
  when(() => cubit.close()).thenAnswer((_) async {});
}

Widget _card(
  SessionBlock block, {
  MockSessionCommandCubit? cubit,
  void Function(SessionBlock block)? onOpenAgent,
  BlocksCubit? blocksCubit,
  RouteFactory? onGenerateRoute,
}) {
  final commandCubit = cubit ?? MockSessionCommandCubit();
  _stubBloc(commandCubit);
  Widget body = BlocProvider<SessionCommandCubit>.value(
    value: commandCubit,
    child: BlockCard(block: block, onOpenAgent: onOpenAgent),
  );
  if (blocksCubit != null) {
    body = BlocProvider<BlocksCubit>.value(value: blocksCubit, child: body);
  }
  return SkinScope(
    skin: const DarkSkin(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        onGenerateRoute: onGenerateRoute,
        home: Scaffold(body: body),
      ),
    ),
  );
}

void main() {
  testWidgets('short user messages align with the right conversation edge', (tester) async {
    await tester.pumpWidget(_card(const SessionBlock(
      id: 'prompt', firstSeq: 1, lastSeq: 1, kind: BlockKind.prompt,
      status: BlockStatus.ok, title: '', body: 'Hello',
    )));
    final bubbleText = tester.getRect(find.text('Hello'));
    final screen = tester.getSize(find.byType(Scaffold));
    expect(bubbleText.right, closeTo(screen.width - 16 - 14, 1));
  });

  testWidgets('a permission block without dialog options offers deny and allow once only', (tester) async {
    await tester.pumpWidget(_card(_permissionBlock(interactionId: 'i1')));

    expect(find.text('Deny'), findsOneWidget);
    expect(find.text('Allow once'), findsOneWidget);
    expect(find.byType(BlockActionButton), findsNWidgets(2));
  });

  testWidgets('allow once calls decide with the block interaction id', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.decide(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(_card(_permissionBlock(interactionId: 'i1'), cubit: cubit));
    await tester.tap(find.text('Allow once'));
    await tester.pump();

    verify(() => cubit.decide('i1', 'allow')).called(1);
  });

  testWidgets('deny calls decide with deny', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.decide(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(_card(_permissionBlock(interactionId: 'i1'), cubit: cubit));
    await tester.tap(find.text('Deny'));
    await tester.pump();

    verify(() => cubit.decide('i1', 'deny')).called(1);
  });

  testWidgets('a permission block with no interaction id is not actionable', (tester) async {
    await tester.pumpWidget(_card(_permissionBlock(interactionId: null)));

    expect(find.text('Allow once'), findsNothing);
    expect(find.text('Answer in the terminal'), findsOneWidget);
  });

  testWidgets('question options are tappable and post the selection', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.answer(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      _card(_questionBlock(interactionId: 'q1', options: ['first', 'second']), cubit: cubit),
    );
    await tester.tap(find.text('second'));
    await tester.pump();

    verify(() => cubit.answer('q1', [
      ['second'],
    ])).called(1);
  });

  testWidgets('a multi-select question submits every chosen row', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.answer(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      _card(
        _questionBlock(interactionId: 'q1', options: ['a', 'b', 'c'], multiSelect: true),
        cubit: cubit,
      ),
    );
    await tester.tap(find.text('a'));
    await tester.tap(find.text('c'));
    await tester.tap(find.text('Submit'));
    await tester.pump();

    verify(() => cubit.answer('q1', [
      ['a', 'c'],
    ])).called(1);
  });

  testWidgets('an answered question marks the chosen option and stops taking taps', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.answer(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      _card(
        _questionBlock(
          interactionId: 'q1',
          options: ['first', 'second'],
          status: BlockStatus.ok,
          result: 'Your questions have been answered: "Which one?"="second". You can now continue.',
        ),
        cubit: cubit,
      ),
    );

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('Answer in the terminal'), findsNothing);
    final chosen = find.ancestor(of: find.text('second'), matching: find.byType(AnimatedContainer)).first;
    expect(find.descendant(of: chosen, matching: find.byIcon(Icons.check_rounded)), findsOneWidget);

    await tester.tap(find.text('first'));
    await tester.pump();
    verifyNever(() => cubit.answer(any(), any()));
  });

  testWidgets('a tapped single-select option is highlighted while the answer is in flight', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.answer(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      _card(_questionBlock(interactionId: 'q1', options: ['first', 'second']), cubit: cubit),
    );
    await tester.tap(find.text('second'));
    await tester.pump();

    final chosen = find.ancestor(of: find.text('second'), matching: find.byType(AnimatedContainer)).first;
    expect(find.descendant(of: chosen, matching: find.byIcon(Icons.check_rounded)), findsOneWidget);
  });

  testWidgets('a running agent card shows its description, type, model and live elapsed time', (tester) async {
    await tester.pumpWidget(_card(_agentBlock()));
    expect(find.text('Implement Task 1'), findsOneWidget);
    expect(find.textContaining('general-purpose'), findsOneWidget);
    expect(find.textContaining('haiku'), findsOneWidget);
    expect(find.textContaining(RegExp(r'1m1[3-6]s')), findsOneWidget);
  });

  testWidgets('a finished agent card shows duration and tool count and no timer', (tester) async {
    await tester.pumpWidget(_card(_agentBlock(status: 'completed', blockStatus: BlockStatus.ok)));
    expect(find.textContaining('6m02s'), findsOneWidget);
    expect(find.textContaining('7 tools'), findsOneWidget);
  });

  testWidgets('tapping an agent card reports the block to open', (tester) async {
    SessionBlock? opened;
    await tester.pumpWidget(_card(_agentBlock(), onOpenAgent: (block) => opened = block));
    await tester.tap(find.text('Implement Task 1'));
    expect(opened?.id, 'src-toolu_a');
  });

  testWidgets(
    'tapping a running agent card with no agentId yet resolves it from a prompt-matched live tail',
    (tester) async {
      final block = SessionBlock(
        id: 'src-toolu_a',
        firstSeq: 1,
        lastSeq: 1,
        kind: BlockKind.tool,
        status: BlockStatus.running,
        title: 'Agent',
        body: '',
        toolName: 'Agent',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        detail: const AgentBlockDetail(
          description: 'Implement Task 1',
          prompt: 'You are implementing Task 1',
          model: 'haiku',
          agentType: 'general-purpose',
          agentId: null,
          status: 'running',
        ),
      );
      final blocksCubit = _MockBlocksCubit();
      when(() => blocksCubit.state).thenReturn(const BlocksReadyState(1));
      when(() => blocksCubit.blocks).thenReturn([block]);
      when(() => blocksCubit.subagentSummaries).thenReturn({
        'a1': const SubagentSummary(agentId: 'a1', prompt: 'You are implementing Task 1'),
      });
      when(() => blocksCubit.sessionId).thenReturn('s-1');
      when(() => blocksCubit.harness).thenReturn('claude-code');

      RouteSettings? pushed;
      await tester.pumpWidget(
        _card(
          block,
          blocksCubit: blocksCubit,
          onGenerateRoute: (settings) {
            pushed = settings;
            return MaterialPageRoute(builder: (_) => const SizedBox.shrink());
          },
        ),
      );
      await tester.tap(find.text('Implement Task 1'));
      await tester.pumpAndSettle();

      final args = pushed?.arguments as Map<String, dynamic>?;
      expect(args?['agentId'], 'a1');
    },
  );
}
