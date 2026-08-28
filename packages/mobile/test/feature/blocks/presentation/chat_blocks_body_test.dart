import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_state.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/chat_blocks_body.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_approval_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_input_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/rollback_turn_params.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';

class _MockCubit extends MockCubit<ConversationBlocksState>
    implements ConversationBlocksCubit {}

class _MockRepository extends Mock implements ChatRepository {}

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

Future<void> _pump(
  WidgetTester tester,
  _MockCubit cubit, {
  _MockRepository? repository,
}) =>
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
                  child: ChatBlocksBody(
                    repository: repository ?? _MockRepository(),
                    sessionId: 's-1',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  late _MockCubit cubit;
  late _MockRepository repository;

  setUpAll(() {
    registerFallbackValue(
      const ResolveApprovalParams(requestId: 'req', decisionId: 'approve'),
    );
    registerFallbackValue(
      const ResolveInputParams(requestId: 'req', action: 'accept'),
    );
    registerFallbackValue(const RollbackTurnParams(turnId: 'turn'));
  });

  setUp(() {
    cubit = _MockCubit();
    repository = _MockRepository();
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
    when(
      () => repository.resolveApproval(any(), any()),
    ).thenAnswer((_) async => Result<bool, Failure>.success(true));
    when(
      () => repository.resolveInput(any(), any()),
    ).thenAnswer((_) async => Result<bool, Failure>.success(true));
    when(
      () => repository.rollbackTurn(any(), any()),
    ).thenAnswer((_) async => Result<int, Failure>.success(0));
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

  group('capability-gated action wiring', () {
    SessionBlock approvalBlock(String id) => SessionBlock(
      id: id,
      firstSeq: 1,
      lastSeq: 1,
      kind: BlockKind.permission,
      status: BlockStatus.blocked,
      title: 'Approval',
      body: 'Bash',
      truncatedLines: 0,
      redacted: false,
    );

    SessionBlock userInputBlock(String id) => SessionBlock(
      id: id,
      firstSeq: 1,
      lastSeq: 1,
      kind: BlockKind.permission,
      status: BlockStatus.blocked,
      title: 'Input',
      body: 'Pick a color',
      truncatedLines: 0,
      redacted: false,
    );

    SessionBlock promptBlock(String id, String turnId) => SessionBlock(
      id: id,
      firstSeq: 1,
      lastSeq: 1,
      kind: BlockKind.prompt,
      status: BlockStatus.ok,
      turnId: turnId,
      title: 'Prompt',
      body: 'do the thing',
      truncatedLines: 0,
      redacted: false,
    );

    SessionBlock assistantBlock(String id, String turnId) => SessionBlock(
      id: id,
      firstSeq: 2,
      lastSeq: 2,
      kind: BlockKind.assistant,
      status: BlockStatus.ok,
      turnId: turnId,
      title: 'Assistant',
      body: 'ok',
      truncatedLines: 0,
      redacted: false,
    );

    testWidgets(
      'renders approve and deny buttons when capabilities includes approve',
      (tester) async {
        when(() => cubit.snapshot).thenReturn(
          ConversationSnapshotModel(
            sessionId: 's-1',
            items: const [
              ConversationActivityModel(
                id: 'req-1',
                activityKind: 'approval',
                status: 'pending',
                requestId: 'req-1',
              ),
            ],
            capabilities: const ['approve'],
          ),
        );
        when(() => cubit.state).thenReturn(
          ConversationBlocksReadyState(
            revision: 1,
            blocks: [approvalBlock('req-1')],
            isLoading: false,
          ),
        );

        await _pump(tester, cubit);

        expect(find.byKey(const ValueKey('block-approve')), findsOneWidget);
        expect(find.byKey(const ValueKey('block-decline')), findsOneWidget);
      },
    );

    testWidgets(
      'does not render approve or deny buttons when capabilities is empty',
      (tester) async {
        when(() => cubit.snapshot).thenReturn(
          ConversationSnapshotModel(
            sessionId: 's-1',
            items: const [
              ConversationActivityModel(
                id: 'req-1',
                activityKind: 'approval',
                status: 'pending',
                requestId: 'req-1',
              ),
            ],
            capabilities: const [],
          ),
        );
        when(() => cubit.state).thenReturn(
          ConversationBlocksReadyState(
            revision: 1,
            blocks: [approvalBlock('req-1')],
            isLoading: false,
          ),
        );

        await _pump(tester, cubit);

        expect(find.byKey(const ValueKey('block-approve')), findsNothing);
        expect(find.byKey(const ValueKey('block-decline')), findsNothing);
      },
    );

    testWidgets(
      'calls repository.resolveApproval with the request id and the approve decision',
      (tester) async {
        when(() => cubit.snapshot).thenReturn(
          ConversationSnapshotModel(
            sessionId: 's-1',
            items: const [
              ConversationActivityModel(
                id: 'req-1',
                activityKind: 'approval',
                status: 'pending',
                requestId: 'req-1',
              ),
            ],
            capabilities: const ['approve'],
          ),
        );
        when(() => cubit.state).thenReturn(
          ConversationBlocksReadyState(
            revision: 1,
            blocks: [approvalBlock('req-1')],
            isLoading: false,
          ),
        );

        await _pump(tester, cubit, repository: repository);

        await tester.tap(find.byKey(const ValueKey('block-approve')));
        await tester.pump();
        await tester.pump();

        final captured = verify(
          () => repository.resolveApproval(captureAny(), captureAny()),
        ).captured;
        expect(captured.length, 2);
        expect(captured[0], 's-1');
        final params = captured[1] as ResolveApprovalParams;
        expect(params.requestId, 'req-1');
        expect(params.decisionId, 'approve');
      },
    );

    testWidgets(
      'renders the answer button when capabilities includes elicitation',
      (tester) async {
        when(() => cubit.snapshot).thenReturn(
          ConversationSnapshotModel(
            sessionId: 's-1',
            items: const [
              ConversationActivityModel(
                id: 'req-2',
                activityKind: 'user_input',
                status: 'pending',
                requestId: 'req-2',
              ),
            ],
            capabilities: const ['elicitation'],
          ),
        );
        when(() => cubit.state).thenReturn(
          ConversationBlocksReadyState(
            revision: 1,
            blocks: [userInputBlock('req-2')],
            isLoading: false,
          ),
        );

        await _pump(tester, cubit);

        expect(find.byKey(const ValueKey('block-answer')), findsOneWidget);
      },
    );

    testWidgets(
      'does not render the answer button when capabilities is empty',
      (tester) async {
        when(() => cubit.snapshot).thenReturn(
          ConversationSnapshotModel(
            sessionId: 's-1',
            items: const [
              ConversationActivityModel(
                id: 'req-2',
                activityKind: 'user_input',
                status: 'pending',
                requestId: 'req-2',
              ),
            ],
            capabilities: const [],
          ),
        );
        when(() => cubit.state).thenReturn(
          ConversationBlocksReadyState(
            revision: 1,
            blocks: [userInputBlock('req-2')],
            isLoading: false,
          ),
        );

        await _pump(tester, cubit);

        expect(find.byKey(const ValueKey('block-answer')), findsNothing);
      },
    );

    testWidgets(
      'renders the rollback button when capabilities includes rollback and the turn is rollback-eligible',
      (tester) async {
        when(() => cubit.snapshot).thenReturn(
          ConversationSnapshotModel(
            sessionId: 's-1',
            turns: const [
              ConversationTurnModel(
                id: 't-1',
                state: 'completed',
                providerTurnId: 'prov-1',
                rolledBack: false,
                requestedAt: '2026-08-28T10:00:00Z',
                startedAt: '2026-08-28T10:00:01Z',
                completedAt: '2026-08-28T10:00:05Z',
              ),
            ],
            capabilities: const ['rollback'],
          ),
        );
        when(() => cubit.state).thenReturn(
          ConversationBlocksReadyState(
            revision: 1,
            blocks: [promptBlock('p-1', 't-1'), assistantBlock('a-1', 't-1')],
            isLoading: false,
          ),
        );

        await _pump(tester, cubit);

        expect(find.byKey(const ValueKey('turn-rollback')), findsOneWidget);
      },
    );

    testWidgets(
      'does not render the rollback button when capabilities is empty',
      (tester) async {
        when(() => cubit.snapshot).thenReturn(
          ConversationSnapshotModel(
            sessionId: 's-1',
            turns: const [
              ConversationTurnModel(
                id: 't-1',
                state: 'completed',
                providerTurnId: 'prov-1',
                rolledBack: false,
                requestedAt: '2026-08-28T10:00:00Z',
                startedAt: '2026-08-28T10:00:01Z',
                completedAt: '2026-08-28T10:00:05Z',
              ),
            ],
            capabilities: const [],
          ),
        );
        when(() => cubit.state).thenReturn(
          ConversationBlocksReadyState(
            revision: 1,
            blocks: [promptBlock('p-1', 't-1'), assistantBlock('a-1', 't-1')],
            isLoading: false,
          ),
        );

        await _pump(tester, cubit);

        expect(find.byKey(const ValueKey('turn-rollback')), findsNothing);
      },
    );
  });
}
