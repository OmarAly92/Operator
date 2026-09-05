import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/blocks/data/model/pending_interaction_model.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/session_route/ui/session_route_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _MockTerminalRepository extends Mock implements TerminalRepository {}

class _MockPreviewRepository extends Mock implements PreviewRepository {}

class _MockBlocksRepository extends Mock implements BlocksRepository {}

class _MockSessionControlRepository extends Mock implements SessionControlRepository {}

class _InertVoiceProvider implements VoiceProvider {
  @override
  bool get available => false;

  @override
  String? get language => null;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> start(VoiceCallbacks callbacks, {VoiceMode mode = VoiceMode.push}) async {}

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
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    registerFallbackValue(const GetSessionBlocksParams());

    repository = _MockSessionsRepository();
    mux = _MockMuxClient();
    terminalRepository = _MockTerminalRepository();
    when(
      () => mux.sessionPatches,
    ).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => mux.status).thenAnswer((_) => const Stream<MuxStatus>.empty());
    when(() => mux.terminalEvents).thenAnswer((_) => const Stream<TerminalEvent>.empty());
    when(() => mux.blockEvents).thenAnswer(
      (_) => const Stream<BlockEventEnvelope>.empty(),
    );
    when(() => mux.subscribeBlocks(any())).thenReturn(null);
    when(() => mux.unsubscribeBlocks(any())).thenReturn(null);
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => mux.openTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.closeTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.resize(any(), any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);

    await sl.reset();
    sl.registerFactoryParam<TerminalCubit, TerminalArgs, void>(
      (args, _) => TerminalCubit(mux, terminalRepository, repository, args),
    );
    sl.registerFactoryParam<SessionViewCubit, TerminalArgs, void>(
      (args, _) => SessionViewCubit(defaultViewMode(args)),
    );
    final blocksRepository = _MockBlocksRepository();
    when(
      () => blocksRepository.getSessionBlocks(any(), any()),
    ).thenAnswer((_) async => Result.success(const []));
    sl.registerFactoryParam<BlocksCubit, String, String?>(
      (sessionId, harness) => BlocksCubit(mux, blocksRepository, sessionId, harness: harness),
    );
    final sessionControlRepository = _MockSessionControlRepository();
    when(() => sessionControlRepository.getInteractions(any()))
        .thenAnswer((_) async => Result.success(GlobalResponse<List<PendingInteractionModel>>()));
    sl.registerFactoryParam<SessionCommandCubit, String, String?>(
      (sessionId, activity) => SessionCommandCubit(
        mux,
        sessionControlRepository,
        sessionId: sessionId,
        initialActivity: activity,
      ),
    );
    sl.registerFactoryParam<VoiceInputCubit, void Function(String), void>(
      (onTranscript, _) => VoiceInputCubit(_InertVoiceProvider(), onTranscript: onTranscript),
    );
    final previewRepository = _MockPreviewRepository();
    when(
      () => previewRepository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
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

  Future<void> pumpRoute(
    WidgetTester tester, {
    required List<SessionModel> sessions,
  }) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: BoardSnapshot(sessions: sessions)),
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
                BlocProvider<SessionsCubit>(create: (_) => SessionsCubit(repository, mux)),
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

  Future<SessionsCubit> settledCubit(List<SessionModel> sessions) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: BoardSnapshot(sessions: sessions)),
      ),
    );
    final cubit = SessionsCubit(repository, mux);
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
              providers: [
                BlocProvider<SessionsCubit>.value(value: cubit),
              ],
              child: const SessionRouteScreen(sessionId: 'w-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders the terminal for any session it can find', (tester) async {
    await pumpRoute(
      tester,
      sessions: const [SessionModel(id: 'w-1', projectId: 'p', harness: 'claude-code')],
    );

    expect(find.byType(TerminalScreen), findsOneWidget);
  });

  testWidgets('reports a session the daemon does not have', (tester) async {
    await pumpRoute(tester, sessions: const []);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Session not found.'), findsOneWidget);
    verify(() => repository.getBoard()).called(1);
  });

  testWidgets('refreshes a settled empty cache once before reporting the session missing', (tester) async {
    final cubit = await settledCubit(const []);
    try {
      await pumpSettledRoute(tester, cubit);

      expect(find.text('Session not found.'), findsOneWidget);
      verify(() => repository.getBoard()).called(1);
    } finally {
      await cubit.close();
    }
  });

  testWidgets('uses a cached session without another board refresh', (tester) async {
    final cubit = await settledCubit(
      const [SessionModel(id: 'w-1', projectId: 'p', harness: 'claude-code')],
    );
    try {
      await pumpSettledRoute(tester, cubit);

      expect(find.byType(TerminalScreen), findsOneWidget);
      verifyNever(() => repository.getBoard());
    } finally {
      await cubit.close();
    }
  });
}
