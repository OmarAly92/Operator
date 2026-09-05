import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

class MockSessionCommandCubit extends Mock implements SessionCommandCubit {}

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

SessionBlock _questionBlock({String? interactionId, required List<String> options, bool multiSelect = false}) =>
    SessionBlock(
      id: 'b-2',
      firstSeq: 1,
      lastSeq: 1,
      kind: BlockKind.notice,
      status: BlockStatus.blocked,
      title: 'Which one?',
      body: '',
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

void _stubBloc(MockSessionCommandCubit cubit) {
  when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
  when(() => cubit.state).thenReturn(const SessionCommandState());
  when(() => cubit.close()).thenAnswer((_) async {});
}

Widget _card(SessionBlock block, {MockSessionCommandCubit? cubit}) {
  final commandCubit = cubit ?? MockSessionCommandCubit();
  _stubBloc(commandCubit);
  return SkinScope(
    skin: const DarkSkin(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        home: Scaffold(
          body: BlocProvider<SessionCommandCubit>.value(
            value: commandCubit,
            child: BlockCard(block: block),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a permission block offers allow and deny', (tester) async {
    await tester.pumpWidget(_card(_permissionBlock(interactionId: 'i1')));

    expect(find.text('Allow'), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);
  });

  testWidgets('allow calls decide with the block interaction id', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.decide(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(_card(_permissionBlock(interactionId: 'i1'), cubit: cubit));
    await tester.tap(find.text('Allow'));
    await tester.pump();

    verify(() => cubit.decide('i1', 'allow')).called(1);
  });

  testWidgets('a permission block with no interaction id is not actionable', (tester) async {
    await tester.pumpWidget(_card(_permissionBlock(interactionId: null)));

    expect(find.text('Allow'), findsNothing);
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
}
