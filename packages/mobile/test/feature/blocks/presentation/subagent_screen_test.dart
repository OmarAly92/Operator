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
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/subagent_screen/ui/subagent_screen.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';

class _MockBlocksCubit extends MockCubit<BlocksState> implements BlocksCubit {}

class _MockCommandCubit extends MockCubit<SessionCommandState> implements SessionCommandCubit {}

void main() {
  testWidgets('shows the agent title, breadcrumb and no composer', (tester) async {
    final blocks = _MockBlocksCubit();
    when(() => blocks.state).thenReturn(const BlocksReadyState(1));
    when(() => blocks.sessionId).thenReturn('s-1');
    when(() => blocks.agentId).thenReturn('a1');
    when(() => blocks.supported).thenReturn(true);
    when(() => blocks.harness).thenReturn('claude-code');
    when(() => blocks.blocks).thenReturn([
      SessionBlock(id: 'seq-1', firstSeq: 1, lastSeq: 1, kind: BlockKind.prompt, status: BlockStatus.ok, title: 'Prompt', body: 'Implement task 1', agentId: 'a1'),
      SessionBlock(id: 'seq-2', firstSeq: 2, lastSeq: 2, kind: BlockKind.permission, status: BlockStatus.blocked, title: 'Permission requested', body: 'Bash\nls', agentId: 'a1', interactionId: 'i1'),
    ]);
    when(() => blocks.loading).thenReturn(false);
    when(() => blocks.active).thenReturn(true);
    when(() => blocks.loadingOlder).thenReturn(false);
    when(() => blocks.hasOlder).thenReturn(false);
    when(() => blocks.error).thenReturn(null);
    when(() => blocks.refresh()).thenAnswer((_) async {});
    when(() => blocks.loadOlder()).thenAnswer((_) async {});
    final commands = _MockCommandCubit();
    when(() => commands.state).thenReturn(const SessionCommandState());

    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<BlocksCubit>.value(value: blocks),
                BlocProvider<SessionCommandCubit>.value(value: commands),
              ],
              child: const SubagentScreen(
                sessionId: 's-1',
                agentId: 'a1',
                parentTitle: 'Impl Plan A',
                detail: AgentBlockDetail(description: 'Implement Task 1', agentType: 'general-purpose', model: 'haiku', status: 'running'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Implement Task 1'), findsOneWidget);
    expect(find.textContaining('Impl Plan A'), findsOneWidget);
    expect(find.textContaining('general-purpose'), findsOneWidget);
    expect(find.byType(TerminalComposer), findsNothing);
    expect(find.text('Answer in the parent session'), findsOneWidget);
    expect(find.text('Allow once'), findsNothing);
  });
}
