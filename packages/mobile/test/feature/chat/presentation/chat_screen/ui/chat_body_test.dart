import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_state.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/chat_screen.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/live_turn_bar.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/shell_terminal_model.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockChatCubit extends MockCubit<ChatState> implements ChatCubit {}

class _MockConversationBlocksCubit extends MockCubit<ConversationBlocksState>
    implements ConversationBlocksCubit {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _MockTerminalRepository extends Mock implements TerminalRepository {}

class _MockInterfaceSwitchCubit extends MockCubit<InterfaceSwitchState>
    implements InterfaceSwitchCubit {}

class _InertVoiceProvider implements VoiceProvider {
  @override
  bool get available => false;

  @override
  String? get language => null;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> start(
    VoiceCallbacks callbacks, {
    VoiceMode mode = VoiceMode.push,
  }) async {}

  @override
  void stop() {}

  @override
  void abort() {}
}

class _RouteCapturingObserver extends NavigatorObserver {
  final List<String> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) pushed.add(name);
  }
}

ConversationSnapshotModel snapshot({
  String controllerState = 'ready',
  String? controllerError,
  List<ConversationTurnModel> turns = const [],
  List<McpServerModel> mcpServers = const [],
  List<String> capabilities = const [],
  ConversationAccountModel? account,
  ConversationThreadStateModel? threadState,
  ConversationRateLimitsModel? rateLimits,
  ConversationUsageModel? usage,
}) => ConversationSnapshotModel(
  conversationId: 'c-1',
  sessionId: 'w-1',
  harness: 'codex',
  controllerState: controllerState,
  controllerError: controllerError,
  latestSequence: 1,
  turns: turns,
  mcpServers: mcpServers,
  capabilities: capabilities,
  account: account,
  threadState: threadState,
  rateLimits: rateLimits,
  usage: usage,
);

ConversationBlocksCubit _blocksCubit() {
  final cubit = _MockConversationBlocksCubit();
  when(() => cubit.state).thenReturn(const ConversationBlocksInitialState());
  when(() => cubit.snapshot).thenReturn(null);
  when(() => cubit.onResumed()).thenAnswer((_) async {});
  return cubit;
}

void main() {
  late _MockChatCubit cubit;
  late ConversationBlocksCubit blocksCubit;
  late SessionsCubit sessionsCubit;
  late _MockTerminalRepository terminalRepository;
  late _MockInterfaceSwitchCubit switchCubit;
  late _RouteCapturingObserver routeObserver;

  setUpAll(() {
    registerFallbackValue(
      const OpenSessionShellParams(projectId: '', sessionId: ''),
    );
  });

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    await sl.reset();
    HomeShell.selectedTab.value = 0;
    routeObserver = _RouteCapturingObserver();

    blocksCubit = _blocksCubit();
    cubit = _MockChatCubit();
    final sessionsRepository = _MockSessionsRepository();
    final mux = _MockMuxClient();
    terminalRepository = _MockTerminalRepository();
    switchCubit = _MockInterfaceSwitchCubit();
    when(
      () => mux.sessionPatches,
    ).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const BoardSnapshot())),
    );
    sessionsCubit = SessionsCubit(sessionsRepository, mux);
    sl.registerLazySingleton<SessionsCubit>(() => sessionsCubit);
    sl.registerLazySingleton<TerminalRepository>(() => terminalRepository);
    sl.registerFactoryParam<VoiceInputCubit, void Function(String), void>(
      (onTranscript, _) =>
          VoiceInputCubit(_InertVoiceProvider(), onTranscript: onTranscript),
    );
    when(
      () => switchCubit.state,
    ).thenReturn(const InterfaceSwitchInitialState());
    when(() => switchCubit.supported).thenReturn(true);
    when(() => switchCubit.reason).thenReturn(null);
    when(() => switchCubit.error).thenReturn(null);
    when(() => switchCubit.active).thenReturn(false);
    when(() => switchCubit.cancellable).thenReturn(false);
    when(() => switchCubit.cancelling).thenReturn(false);
    when(() => switchCubit.phase).thenReturn(null);
    when(() => switchCubit.start(any(), any())).thenAnswer((_) async {});
    when(() => switchCubit.cancel()).thenAnswer((_) async {});
    when(() => cubit.state).thenReturn(const ChatReadyState(1));
    when(() => cubit.sessionId).thenReturn('w-1');
    when(() => cubit.loading).thenReturn(false);
    when(() => cubit.refreshing).thenReturn(false);
    when(() => cubit.loadingOlder).thenReturn(false);
    when(() => cubit.error).thenReturn(null);
    when(() => cubit.unavailable).thenReturn(null);
    when(() => cubit.models).thenReturn(const []);
    when(() => cubit.configOptions).thenReturn(const []);
    when(() => cubit.skills).thenReturn(const []);
    when(() => cubit.workspace).thenReturn(const WorkspacePathsModel());
    when(() => cubit.pendingSends).thenReturn(const []);
    when(() => cubit.pendingActions).thenReturn(const {});
    when(() => cubit.actionError).thenReturn(null);
    when(() => cubit.actionErrors).thenReturn(const {});
    when(() => cubit.actionCodes).thenReturn(const {});
    when(() => cubit.snapshot).thenReturn(snapshot());
    when(() => cubit.refresh()).thenAnswer((_) async {});
    when(() => cubit.resumeAgent()).thenAnswer((_) async {});
    when(() => cubit.interrupt()).thenAnswer((_) async {});
    when(() => cubit.retrySend(any())).thenAnswer((_) async {});
    when(() => cubit.compact()).thenAnswer((_) async {});
    when(() => cubit.onResumed()).thenAnswer((_) async {});
  });

  tearDown(() async {
    await sessionsCubit.close();
    await sl.reset();
  });

  Future<void> pumpBody(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            navigatorObservers: [routeObserver],
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const SizedBox(),
            ),
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<ChatCubit>.value(value: cubit),
                  BlocProvider<ConversationBlocksCubit>.value(
                    value: blocksCubit,
                  ),
                  BlocProvider<InterfaceSwitchCubit>.value(value: switchCubit),
                ],
                child: const ChatBody(projectId: 'p-1'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openMenuAndTap(WidgetTester tester, String label) async {
    tester.state<ChatBodyState>(find.byType(ChatBody)).openMenu();
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a spinner before the first page arrives', (tester) async {
    when(() => cubit.loading).thenReturn(true);
    when(() => cubit.snapshot).thenReturn(null);

    await pumpBody(tester);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('the pull requests menu action selects the project and PR tab', (
    tester,
  ) async {
    await pumpBody(tester);

    tester.state<ChatBodyState>(find.byType(ChatBody)).openMenu();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pull requests'));
    await tester.pumpAndSettle();

    expect(sessionsCubit.activeProjectId, 'p-1');
    expect(HomeShell.selectedTab.value, 2);
  });

  testWidgets(
    'explains a permanently unavailable conversation without offering a retry',
    (tester) async {
      when(() => cubit.snapshot).thenReturn(null);
      when(() => cubit.unavailable).thenReturn(
        const ChatUnavailable(
          code: 'CHAT_RESUME_FAILED',
          message: 'Operator could not resume this agent.',
        ),
      );

      await pumpBody(tester);
      expect(find.text('Conversation unavailable'), findsOneWidget);
      expect(find.textContaining('worktree is untouched'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    },
  );

  testWidgets('offers a retry for a transient load failure', (tester) async {
    when(() => cubit.snapshot).thenReturn(null);
    when(() => cubit.error).thenReturn('Could not reach your Operator server');

    await pumpBody(tester);
    expect(find.text('Could not load conversation'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    verify(() => cubit.refresh()).called(1);
  });

  testWidgets('shows the harness, mode and context readout', (tester) async {
    when(() => cubit.snapshot).thenReturn(
      snapshot(
        usage: const ConversationUsageModel(
          contextUsed: 900,
          contextWindow: 1000,
          totalTokens: 900,
        ),
      ),
    );

    await pumpBody(tester);
    expect(find.text('codex'), findsOneWidget);
    expect(find.text('CHAT'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
  });

  testWidgets('offers to resume a stopped controller', (tester) async {
    when(() => cubit.snapshot).thenReturn(
      snapshot(
        controllerState: 'stopped',
        controllerError: 'The agent controller is stopped.',
      ),
    );

    await pumpBody(tester);
    expect(find.text('The agent controller is stopped.'), findsOneWidget);

    await tester.tap(find.text('Resume agent'));
    await tester.pump();
    verify(() => cubit.resumeAgent()).called(1);
  });

  testWidgets('warns that broken MCP servers are silent', (tester) async {
    when(() => cubit.snapshot).thenReturn(
      snapshot(
        mcpServers: const [
          McpServerModel(
            name: 'github',
            status: 'failed',
            error: 'token expired',
          ),
        ],
      ),
    );

    await pumpBody(tester);
    expect(
      find.textContaining('github (token expired) did not start'),
      findsOneWidget,
    );
  });

  testWidgets('warns near the account quota', (tester) async {
    when(() => cubit.snapshot).thenReturn(
      snapshot(
        rateLimits: const ConversationRateLimitsModel(
          primaryUsedPercent: 93,
          secondaryUsedPercent: -1,
          primaryResetsInSeconds: 3600,
          planLabel: 'weekly',
        ),
      ),
    );

    await pumpBody(tester);
    expect(
      find.textContaining('93% of the weekly account quota is used'),
      findsOneWidget,
    );
    expect(find.textContaining('resets in 1h'), findsOneWidget);
  });

  testWidgets('offers to stop or clear a running turn', (tester) async {
    when(() => cubit.snapshot).thenReturn(
      snapshot(
        turns: const [
          ConversationTurnModel(
            id: 't1',
            state: 'running',
            requestedAt: '2026-08-05T00:00:00Z',
          ),
          ConversationTurnModel(
            id: 't2',
            state: 'queued',
            requestedAt: '2026-08-05T00:00:01Z',
          ),
        ],
      ),
    );

    await pumpBody(tester);
    expect(
      find.descendant(
        of: find.byType(LiveTurnBar),
        matching: find.textContaining('Agent is working'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('1 queued'), findsOneWidget);

    await tester.tap(find.text('Stop and clear queue'));
    await tester.pump();
    verify(() => cubit.interrupt()).called(1);
  });

  testWidgets('offers to retry or discard a message that never sent', (
    tester,
  ) async {
    when(() => cubit.pendingSends).thenReturn(const [
      PendingSend(
        id: 'p1',
        text: 'ship it',
        failed: true,
        error: 'Delivery failed',
      ),
    ]);

    await pumpBody(tester);
    expect(
      find.textContaining('Message not sent: Delivery failed'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();
    verify(() => cubit.retrySend('p1')).called(1);
  });

  testWidgets('refreshes when the app returns to the foreground', (
    tester,
  ) async {
    await pumpBody(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    verify(() => cubit.onResumed()).called(1);
    verify(() => blocksCubit.onResumed()).called(1);
  });

  testWidgets('stacks every applicable banner in priority order', (
    tester,
  ) async {
    when(() => cubit.snapshot).thenReturn(
      snapshot(
        controllerState: 'stopped',
        controllerError: 'Controller stopped',
        turns: const [
          ConversationTurnModel(
            id: 'rolled',
            state: 'completed',
            requestedAt: '2026-08-05T00:00:00Z',
            rolledBack: true,
          ),
        ],
        mcpServers: const [
          McpServerModel(name: 'github', status: 'failed', error: 'expired'),
        ],
        account: const ConversationAccountModel(
          reauthRequiredAt: '2026-08-05T00:00:00Z',
          reauthReason: 'Sign in again',
        ),
        threadState: const ConversationThreadStateModel(status: 'system_error'),
        rateLimits: const ConversationRateLimitsModel(
          primaryUsedPercent: 93,
          primaryResetsInSeconds: 3600,
          planLabel: 'weekly',
        ),
      ),
    );
    when(() => cubit.error).thenReturn('Transient load error');
    when(() => cubit.actionError).thenReturn('Action error');
    when(() => cubit.pendingSends).thenReturn(const [
      PendingSend(
        id: 'p1',
        text: 'ship it',
        failed: true,
        error: 'Delivery failed',
      ),
    ]);

    await pumpBody(tester);

    final banners = <Finder>[
      find.textContaining('Sign in again'),
      find.text('Controller stopped'),
      find.textContaining('internal fault'),
      find.textContaining('github (expired) did not start'),
      find.text('Transient load error'),
      find.textContaining('93% of the weekly account quota is used'),
      find.text('Action error'),
      find.textContaining('1 turn was rolled back'),
      find.textContaining('Message not sent: Delivery failed'),
    ];
    for (final banner in banners) {
      expect(banner, findsOneWidget);
    }
    final positions = banners.map((banner) => tester.getTopLeft(banner).dy);
    expect(positions, orderedEquals([...positions]..sort()));
  });

  testWidgets('keeps compaction visible and explains why it is disabled', (
    tester,
  ) async {
    when(() => cubit.snapshot).thenReturn(
      snapshot(
        capabilities: const ['compaction'],
        turns: const [
          ConversationTurnModel(
            id: 't1',
            state: 'running',
            requestedAt: '2026-08-05T00:00:00Z',
          ),
        ],
      ),
    );

    await pumpBody(tester);

    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
    expect(
      find.bySemanticsLabel('Compact after the current turn finishes'),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.archive_outlined));
    verifyNever(() => cubit.compact());
  });

  testWidgets('keeps the screen shell separate from the body content', (
    tester,
  ) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>.value(value: cubit),
                BlocProvider<ConversationBlocksCubit>.value(
                  value: blocksCubit,
                ),
                BlocProvider<InterfaceSwitchCubit>.value(value: switchCubit),
              ],
              child: ChatScreen(sessionId: 'w-1', title: 'Conversation'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppScaffold), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(ChatBody), findsOneWidget);
  });

  testWidgets('titles the screen with the conversation, not the board row', (
    tester,
  ) async {
    when(() => cubit.snapshot).thenReturn(
      ConversationSnapshotModel(
        conversationId: 'c-1',
        sessionId: 'w-1',
        harness: 'codex',
        controllerState: 'ready',
        latestSequence: 1,
        title: 'Renamed thread',
      ),
    );

    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>.value(value: cubit),
                BlocProvider<ConversationBlocksCubit>.value(
                  value: blocksCubit,
                ),
                BlocProvider<InterfaceSwitchCubit>.value(value: switchCubit),
              ],
              child: const ChatScreen(
                sessionId: 'w-1',
                title: 'Board row title',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Renamed thread'), findsOneWidget);
    expect(find.text('Board row title'), findsNothing);
  });

  testWidgets('falls back to the board title before a conversation loads', (
    tester,
  ) async {
    when(() => cubit.snapshot).thenReturn(null);

    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>.value(value: cubit),
                BlocProvider<ConversationBlocksCubit>.value(
                  value: blocksCubit,
                ),
                BlocProvider<InterfaceSwitchCubit>.value(value: switchCubit),
              ],
              child: const ChatScreen(
                sessionId: 'w-1',
                title: 'Board row title',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Board row title'), findsOneWidget);
  });

  testWidgets('opens a worktree shell and pushes the terminal route', (
    tester,
  ) async {
    when(() => terminalRepository.openSessionShell(any())).thenAnswer(
      (_) async => Result.success(
        const GlobalResponse(
          data: ShellTerminalModel(handleId: 'h-1', title: 'Worktree shell'),
        ),
      ),
    );
    await pumpBody(tester);

    await openMenuAndTap(tester, 'Open worktree shell');

    final captured =
        verify(
              () => terminalRepository.openSessionShell(captureAny()),
            ).captured.single
            as OpenSessionShellParams;
    expect(captured.sessionId, 'w-1');
    expect(routeObserver.pushed, contains(RoutesStrings.terminal));
  });

  testWidgets(
    'reports why a shell could not be opened instead of failing silently',
    (tester) async {
      when(() => terminalRepository.openSessionShell(any())).thenAnswer(
        (_) async =>
            Result.failure(ServerFailure(error: 'x', message: 'no worktree')),
      );
      await pumpBody(tester);

      await openMenuAndTap(tester, 'Open worktree shell');
      await tester.pump();

      expect(find.text('Could not open shell: no worktree'), findsOneWidget);
    },
  );

  testWidgets('asks how to hand off before switching to the Terminal UI', (
    tester,
  ) async {
    when(() => switchCubit.supported).thenReturn(true);
    await pumpBody(tester);

    await openMenuAndTap(tester, 'Open Terminal UI');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop and switch'));
    await tester.pumpAndSettle();

    verify(() => switchCubit.start('tui', 'interrupt')).called(1);
  });
}
