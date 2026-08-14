import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/spawn/data/model/operator_settings_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSpawnRepository extends Mock implements SpawnRepository {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

AgentInfo _agent(String id) => AgentInfo(id: id, label: id, authStatus: 'authorized');

void main() {
  late _MockSpawnRepository spawnRepository;
  late _MockSessionsRepository sessionsRepository;
  late _MockMuxClient mux;

  setUpAll(() => registerFallbackValue(const SpawnSessionParams(projectId: 'p1', mode: 'chat')));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    spawnRepository = _MockSpawnRepository();
    sessionsRepository = _MockSessionsRepository();
    mux = _MockMuxClient();

    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: const BoardSnapshot(projects: [ProjectModel(id: 'p1', name: 'Alpha')]),
        ),
      ),
    );

    await sl.reset();
  });

  tearDown(() => sl.reset());

  SessionsCubit buildSessionsCubit({String activeProjectId = 'p1'}) {
    final cubit = SessionsCubit(sessionsRepository, mux);
    cubit.activeProjectId = activeProjectId;
    sl.registerLazySingleton<SessionsCubit>(() => cubit);
    return cubit;
  }

  Future<void> pumpBody(WidgetTester tester, SpawnCubit spawnCubit) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (_) => Text((settings.arguments as Map<String, dynamic>)['sessionId'] as String),
          ),
          home: SkinScope(
            skin: const DarkSkin(),
            child: BlocProvider<SessionsCubit>(
              create: (_) => sl<SessionsCubit>(),
              lazy: false,
              child: BlocProvider<SpawnCubit>(
                create: (_) => spawnCubit,
                child: const Scaffold(body: SpawnBody()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void stubChatOnlyCatalog() {
    when(() => spawnRepository.getAgents()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: AgentCatalog(supported: [_agent('amp'), _agent('claude-code')], installed: [_agent('amp'), _agent('claude-code')], authorized: [_agent('amp'), _agent('claude-code')])),
      ),
    );
    when(() => spawnRepository.getSettings()).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const OperatorSettingsModel(chatHarnesses: ['amp']))),
    );
  }

  void stubEmptyChatCatalog() {
    when(() => spawnRepository.getAgents()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: AgentCatalog(supported: [_agent('claude-code')], installed: [_agent('claude-code')], authorized: [_agent('claude-code')])),
      ),
    );
    when(() => spawnRepository.getSettings()).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const OperatorSettingsModel(chatHarnesses: []))),
    );
  }

  testWidgets('both mode choices render, Chat starts selected, and its hint copy is shown', (tester) async {
    stubChatOnlyCatalog();
    buildSessionsCubit();
    final spawnCubit = SpawnCubit(spawnRepository);

    await pumpBody(tester, spawnCubit);

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Terminal UI'), findsOneWidget);
    expect(spawnCubit.mode, 'chat');
    expect(find.text('Chat opens a conversation with the agent inside Operator.'), findsOneWidget);
  });

  testWidgets("with a chat-only catalog and tui selected, the agent row's value changes to the tui default", (
    tester,
  ) async {
    stubChatOnlyCatalog();
    buildSessionsCubit();
    final spawnCubit = SpawnCubit(spawnRepository)..setMode('tui');

    await pumpBody(tester, spawnCubit);

    expect(find.text('Terminal UI'), findsOneWidget);
    expect(find.text('claude-code'), findsOneWidget);
    expect(find.text('amp'), findsNothing);
  });

  testWidgets('submitting with an empty name shows the required message and calls no repository', (tester) async {
    stubChatOnlyCatalog();
    buildSessionsCubit();
    final spawnCubit = SpawnCubit(spawnRepository);

    await pumpBody(tester, spawnCubit);

    await tester.tap(find.text('Spawn agent'));
    await tester.pumpAndSettle();

    expect(find.text('Name and task are required.'), findsOneWidget);
    verifyNever(() => spawnRepository.spawn(any()));
  });

  testWidgets('a filled form calls repository.spawn once', (tester) async {
    stubChatOnlyCatalog();
    when(() => spawnRepository.spawn(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const SessionModel(id: 's1', displayName: 'flaky login'))),
    );
    buildSessionsCubit();
    final spawnCubit = SpawnCubit(spawnRepository);

    await pumpBody(tester, spawnCubit);

    await tester.enterText(find.byType(TextField).at(0), 'flaky login');
    await tester.enterText(find.byType(TextField).at(1), 'fix the flake');
    await tester.tap(find.text('Spawn agent'));
    await tester.pumpAndSettle();

    verify(() => spawnRepository.spawn(any())).called(1);
    expect(find.text('s1'), findsOneWidget);
  });

  testWidgets(
    "a CHAT_DRIVER_UNAVAILABLE failure renders the daemon's detail plus a Create as Terminal UI instead action, "
    'and tapping it flips the mode to tui',
    (tester) async {
      stubChatOnlyCatalog();
      when(() => spawnRepository.spawn(any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(error: 'x', message: 'no chat driver available right now', apiStatus: 'CHAT_DRIVER_UNAVAILABLE'),
        ),
      );
      buildSessionsCubit();
      final spawnCubit = SpawnCubit(spawnRepository);

      await pumpBody(tester, spawnCubit);

      await tester.enterText(find.byType(TextField).at(0), 'flaky login');
      await tester.enterText(find.byType(TextField).at(1), 'fix the flake');
      await tester.tap(find.text('Spawn agent'));
      await tester.pumpAndSettle();

      expect(find.text('no chat driver available right now'), findsOneWidget);
      expect(find.text('Create as Terminal UI instead'), findsOneWidget);

      await tester.tap(find.text('Create as Terminal UI instead'));
      await tester.pumpAndSettle();

      expect(spawnCubit.mode, 'tui');
    },
  );

  testWidgets('when chat mode has no capable agents, the amber warning about installing a Chat-capable agent is shown', (
    tester,
  ) async {
    stubEmptyChatCatalog();
    buildSessionsCubit();
    final spawnCubit = SpawnCubit(spawnRepository);

    await pumpBody(tester, spawnCubit);

    expect(find.textContaining('Chat-capable'), findsOneWidget);
  });
}
