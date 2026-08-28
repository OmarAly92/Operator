import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_state.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/chat_blocks_body.dart';

class _MockCubit extends MockCubit<ConversationBlocksState>
    implements ConversationBlocksCubit {}

SessionBlock _block({
  String id = 'seq-1',
  int firstSeq = 1,
  BlockKind kind = BlockKind.prompt,
  BlockStatus status = BlockStatus.ok,
  String title = 'Prompt',
  String body = 'run the tests',
}) => SessionBlock(
  id: id,
  firstSeq: firstSeq,
  lastSeq: firstSeq,
  kind: kind,
  status: status,
  title: title,
  body: body,
);

Future<void> _pump(WidgetTester tester, _MockCubit cubit) =>
    tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<ConversationBlocksCubit>.value(
                value: cubit,
                child: SizedBox(
                  width: 400,
                  height: 700,
                  child: ChatBlocksBody(sessionId: 's-1'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  late _MockCubit cubit;

  setUp(() {
    cubit = _MockCubit();
    when(() => cubit.state).thenReturn(
      ConversationBlocksReadyState(
        revision: 1,
        blocks: const [],
        isLoading: true,
      ),
    );
    when(() => cubit.sessionId).thenReturn('s-1');
    when(() => cubit.refresh()).thenAnswer((_) async {});
    when(() => cubit.loadOlder()).thenAnswer((_) async {});
  });

  testWidgets('renders the blocks when the cubit emits a Ready state with blocks', (tester) async {
    when(() => cubit.state).thenReturn(
      ConversationBlocksReadyState(
        revision: 1,
        blocks: [
          _block(
            id: 'msg-1',
            kind: BlockKind.prompt,
            title: 'Prompt',
            body: 'run the tests',
          ),
          _block(
            id: 'msg-2',
            firstSeq: 2,
            kind: BlockKind.assistant,
            title: 'Assistant',
            body: 'ok',
          ),
        ],
        isLoading: false,
        hasOlder: true,
      ),
    );

    await _pump(tester, cubit);

    expect(find.byType(BlockCard), findsNWidgets(2));
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Assistant'), findsOneWidget);
  });

  testWidgets('renders the unavailable notice when unsupported', (tester) async {
    when(() => cubit.state).thenReturn(
      const ConversationBlocksUnsupportedState(
        (code: 'SESSION_MODE_MISMATCH', message: 'Chat is not supported here.'),
      ),
    );

    await _pump(tester, cubit);

    expect(find.byType(BlockCard), findsNothing);
    expect(find.textContaining('Chat is not supported here.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('does not render a Raw toggle', (tester) async {
    when(() => cubit.state).thenReturn(
      ConversationBlocksReadyState(
        revision: 1,
        blocks: [_block()],
        isLoading: false,
      ),
    );

    await _pump(tester, cubit);

    expect(find.text('Raw'), findsNothing);
    expect(find.text('Blocks'), findsNothing);
  });

  testWidgets('renders an error with a retry button when error and blocks are empty', (tester) async {
    when(() => cubit.state).thenReturn(
      const ConversationBlocksReadyState(
        revision: 1,
        blocks: [],
        isLoading: false,
        error: 'offline',
      ),
    );

    await _pump(tester, cubit);

    expect(find.textContaining('offline'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    verify(() => cubit.refresh()).called(1);
  });
}
