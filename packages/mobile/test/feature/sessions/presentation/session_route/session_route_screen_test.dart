import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/app_routes/app_router.dart';
import 'package:operator_mobile/core/deep_link/deep_link_target.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/mux/mux_notification.dart';
import 'package:operator_mobile/core/notifications/local_alert_sink.dart';
import 'package:operator_mobile/core/notifications/phone_alerts_runtime.dart';
import 'package:operator_mobile/core/notifications/viewed_session.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/blocks/data/model/pending_interaction_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/background_task_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_tasks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/background_tasks_repository.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/dictation/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/dictation/voice_types.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/session_route/ui/session_route_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/terminal/data/model/slash_command_model.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart';
import 'package:operator_mobile/feature/usage/data/repository/usage_repository.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _StubConfigSource implements ServerConfigSource {
  @override
  ServerConfig? get current => null;

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

class _MockTerminalRepository extends Mock implements TerminalRepository {}

class _MockPreviewRepository extends Mock implements PreviewRepository {}

class _MockBlocksRepository extends Mock implements BlocksRepository {}

class _MockBackgroundTasksRepository extends Mock implements BackgroundTasksRepository {}

class _MockSessionControlRepository extends Mock
    implements SessionControlRepository {}

class _MockUsageRepository extends Mock implements UsageRepository {}

class _RecordingSink implements LocalAlertSink {
  final payloads = <String>[];

  @override
  Future<bool> init(void Function(String payload) onTap) async => true;

  @override
  Future<void> show({required int id, required String title, required String body, required String payload}) async =>
      payloads.add(payload);
}

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

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;
  late _MockTerminalRepository terminalRepository;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    AppPreferences.debugLoad(const {});
    registerFallbackValue(const GetSessionBlocksParams());
    registerFallbackValue(const GetSessionTasksParams(sessionId: ''));

    repository = _MockSessionsRepository();
    mux = _MockMuxClient();
    terminalRepository = _MockTerminalRepository();
    when(() => repository.cachedBoard()).thenAnswer((_) async => null);
    when(
      () => mux.sessionPatches,
    ).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => mux.boardChanges).thenAnswer((_) => const Stream<void>.empty());
    when(() => mux.boardStreamReady).thenReturn(false);
    when(() => mux.status).thenAnswer((_) => const Stream<MuxStatus>.empty());
    when(
      () => mux.terminalEvents,
    ).thenAnswer((_) => const Stream<TerminalEvent>.empty());
    when(
      () => mux.blockEvents,
    ).thenAnswer((_) => const Stream<BlockEventEnvelope>.empty());
    when(() => mux.subscribeBlocks(any())).thenReturn(null);
    when(() => mux.unsubscribeBlocks(any())).thenReturn(null);
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(
      () => mux.openTerminal(any(), projectId: any(named: 'projectId')),
    ).thenReturn(null);
    when(
      () => mux.closeTerminal(any(), projectId: any(named: 'projectId')),
    ).thenReturn(null);
    when(
      () => mux.sendInput(any(), any(), projectId: any(named: 'projectId')),
    ).thenReturn(null);
    when(
      () => mux.resize(any(), any(), any(), projectId: any(named: 'projectId')),
    ).thenReturn(null);

    when(() => terminalRepository.getSlashCommands(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse<List<SlashCommandModel>>(data: const [])),
    );

    await sl.reset();
    sl.registerFactoryParam<TerminalCubit, TerminalArgs, void>(
      (args, _) => TerminalCubit(mux, terminalRepository, repository, args),
    );
    sl.registerFactoryParam<SlashMenuCubit, TextEditingController, String>(
      (composer, sessionId) => SlashMenuCubit(terminalRepository, composer, sessionId: sessionId),
    );
    sl.registerFactoryParam<SessionViewCubit, TerminalArgs, void>(
      (args, _) => SessionViewCubit(defaultViewMode(args)),
    );
    final blocksRepository = _MockBlocksRepository();
    when(
      () => blocksRepository.getSessionBlocks(any(), any()),
    ).thenAnswer((_) async => Result.success(const []));
    final tasksRepository = _MockBackgroundTasksRepository();
    when(() => tasksRepository.getTasks(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse<List<BackgroundTaskModel>>(data: const [])),
    );
    sl.registerFactoryParam<BlocksCubit, BlocksScope, void>(
      (scope, _) => BlocksCubit(mux, blocksRepository, scope, tasks: tasksRepository),
    );
    final sessionControlRepository = _MockSessionControlRepository();
    when(() => sessionControlRepository.getInteractions(any())).thenAnswer(
      (_) async =>
          Result.success(GlobalResponse<List<PendingInteractionModel>>()),
    );
    final usageRepository = _MockUsageRepository();
    when(
      () => usageRepository.sessionContext(any()),
    ).thenAnswer((_) async => null);
    sl.registerFactoryParam<SessionCommandCubit, String, String?>(
      (sessionId, activity) => SessionCommandCubit(
        mux,
        sessionControlRepository,
        usageRepository,
        sessionId: sessionId,
        initialActivity: activity,
      ),
    );
    sl.registerFactoryParam<VoiceInputCubit, void Function(String), void>(
      (onTranscript, _) =>
          VoiceInputCubit(_InertVoiceProvider(), onTranscript: onTranscript),
    );
    final previewRepository = _MockPreviewRepository();
    when(
      () => previewRepository.getPreview(
        any(),
        previewUrl: any(named: 'previewUrl'),
      ),
    ).thenAnswer((_) async => Result.success(null));
    sl.registerFactoryParam<PreviewCubit, String, String?>(
      (sessionId, previewUrl) => PreviewCubit(
        previewRepository,
        sessionId,
        previewUrl: previewUrl,
        poll: const Duration(hours: 1),
      ),
    );
  });

  tearDown(() async {
    await sl.reset();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<SessionsCubit>(
                  create: (_) => SessionsCubit(repository, mux, _StubConfigSource()),
                ),
              ],
              child: const SessionRouteScreen(sessionId: 'w-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
  }

  Future<void> pumpRoute(
    WidgetTester tester, {
    required List<SessionModel> sessions,
  }) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: BoardSnapshot(sessions: sessions)),
      ),
    );
    await pumpScreen(tester);
  }

  Future<SessionsCubit> settledCubit(List<SessionModel> sessions) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: BoardSnapshot(sessions: sessions)),
      ),
    );
    final cubit = SessionsCubit(repository, mux, _StubConfigSource());
    await cubit.stream.firstWhere((state) => state is GetSessionsSuccessState);
    clearInteractions(repository);
    return cubit;
  }

  Future<void> pumpSettledRoute(
    WidgetTester tester,
    SessionsCubit cubit,
  ) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: MultiBlocProvider(
              providers: [BlocProvider<SessionsCubit>.value(value: cubit)],
              child: const SessionRouteScreen(sessionId: 'w-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders the terminal for any session it can find', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      sessions: const [
        SessionModel(id: 'w-1', projectId: 'p', harness: 'claude-code'),
      ],
    );

    expect(find.byType(TerminalScreen), findsOneWidget);
  });

  testWidgets('reports a session the daemon does not have', (tester) async {
    await pumpRoute(tester, sessions: const []);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Session not found.'), findsOneWidget);
    verify(() => repository.getBoard()).called(1);
  });

  testWidgets('a session missing from the cached board waits for the fresh board before saying so', (tester) async {
    final gate = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
    when(() => repository.cachedBoard()).thenAnswer(
      (_) async => Replicated(value: const BoardSnapshot(), fetchedAt: DateTime.utc(2026, 9, 25)),
    );
    when(() => repository.getBoard()).thenAnswer((_) => gate.future);

    await pumpScreen(tester);
    expect(find.text('Session not found.'), findsNothing);

    gate.complete(Result.success(GlobalResponse(data: const BoardSnapshot())));
    await tester.pump();
    await tester.pump();

    expect(find.text('Session not found.'), findsOneWidget);
  });

  testWidgets('a cached board that lands after a failed fetch still lets the route settle', (tester) async {
    final read = Completer<Replicated<BoardSnapshot>?>();
    when(() => repository.cachedBoard()).thenAnswer((_) => read.future);
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401)),
    );
    final cubit = SessionsCubit(repository, mux, _StubConfigSource());
    try {
      await tester.runAsync(() async {
        await cubit.stream.firstWhere((state) => state is GetSessionsFailureState);
        read.complete(Replicated(value: const BoardSnapshot(), fetchedAt: DateTime.utc(2026, 9, 25)));
        await cubit.cacheReady;
      });
      expect(cubit.boardIsCached, isTrue);
      expect(cubit.state, isA<GetSessionsFailureState>());

      await pumpSettledRoute(tester, cubit);
      await tester.pump();

      expect(find.text('Session not found.'), findsOneWidget);
    } finally {
      await cubit.close();
    }
  });

  testWidgets(
    'refreshes a settled empty cache once before reporting the session missing',
    (tester) async {
      final cubit = await settledCubit(const []);
      try {
        await pumpSettledRoute(tester, cubit);

        expect(find.text('Session not found.'), findsOneWidget);
        verify(() => repository.getBoard()).called(1);
      } finally {
        await cubit.close();
      }
    },
  );

  testWidgets('uses a cached session without another board refresh', (
    tester,
  ) async {
    final cubit = await settledCubit(const [
      SessionModel(id: 'w-1', projectId: 'p', harness: 'claude-code'),
    ]);
    try {
      await pumpSettledRoute(tester, cubit);

      expect(find.byType(TerminalScreen), findsOneWidget);
      verifyNever(() => repository.getBoard());
    } finally {
      await cubit.close();
    }
  });

  testWidgets('the /session/<id> route an alert tap opens marks that session viewed and silences its alerts', (
    tester,
  ) async {
    ViewedSession.reset();
    addTearDown(ViewedSession.reset);
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: BoardSnapshot(
            sessions: const [SessionModel(id: 'w-1', projectId: 'p', harness: 'claude-code')],
          ),
        ),
      ),
    );
    final sessions = SessionsCubit(repository, mux, _StubConfigSource());
    sl.registerSingleton<SessionsCubit>(sessions);
    final feed = StreamController<MuxNotification>.broadcast(sync: true);
    addTearDown(feed.close);
    when(() => mux.notifications).thenAnswer((_) => feed.stream);
    when(() => mux.subscribeNotifications()).thenReturn(null);
    final sink = _RecordingSink();
    final alerts = PhoneAlertsRuntime(mux, sink, (_) => true);
    addTearDown(alerts.dispose);
    await alerts.start();

    final target = resolveDeepLink(Uri.parse('operator://session/w-1'))!;
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            onGenerateInitialRoutes: (_) => [
              AppRouter.generateRoute(RouteSettings(name: target.route, arguments: target.arguments)),
            ],
            onGenerateRoute: AppRouter.generateRoute,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();

    expect(find.byType(TerminalScreen), findsOneWidget);
    expect(ViewedSession.current.value, 'w-1');

    feed.add(
      const MuxNotification(id: 'n1', sessionId: 'w-1', type: 'turn_finished', title: 'w-1 finished', body: '', quiet: false),
    );
    feed.add(
      const MuxNotification(id: 'n2', sessionId: 'w-2', type: 'turn_finished', title: 'w-2 finished', body: '', quiet: false),
    );
    expect(sink.payloads, ['operator://session/w-2']);

    await tester.pumpWidget(const SizedBox());
    expect(ViewedSession.current.value, isNull);
    await sessions.close();
  });
}
