import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/orchestrator/data/model/params/launch_orchestrator_params.dart';
import 'package:operator_mobile/feature/orchestrator/data/repository/orchestrator_repository.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_body.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _MockOrchestratorRepository extends Mock implements OrchestratorRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

void main() {
  late _MockSessionsRepository sessionsRepository;
  late _MockMuxClient mux;
  late _MockOrchestratorRepository orchestratorRepository;

  setUpAll(() => registerFallbackValue(const LaunchOrchestratorParams(projectId: 'p', clean: false, mode: 'chat')));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    sessionsRepository = _MockSessionsRepository();
    mux = _MockMuxClient();
    orchestratorRepository = _MockOrchestratorRepository();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);

    final serverConfigStore = _MockServerConfigStore();
    when(() => serverConfigStore.current).thenReturn(
      const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12'),
    );
    await sl.reset();
    sl.registerLazySingleton<ServerConfigStore>(() => serverConfigStore);
  });

  tearDown(() => sl.reset());

  Future<void> pumpBody(WidgetTester tester, SessionsCubit sessionsCubit) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (_) => Text((settings.arguments as Map<String, dynamic>)['sessionId'] as String),
            ),
            home: MultiBlocProvider(
              providers: [
                BlocProvider<SessionsCubit>(create: (_) => sessionsCubit),
                BlocProvider<OrchestratorCubit>(create: (_) => OrchestratorCubit(orchestratorRepository)),
              ],
              child: Scaffold(body: OrchestratorBody(onOpenBoard: () {})),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every project gets a card even when the active project is set to one of them', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: const BoardSnapshot(
            sessions: [
              SessionModel(id: 's1', projectId: 'p1'),
              SessionModel(id: 's2', projectId: 'p2'),
            ],
            projects: [ProjectModel(id: 'p1', name: 'One'), ProjectModel(id: 'p2', name: 'Two')],
          ),
        ),
      ),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux);
    sessionsCubit.setActiveProject('p2');

    await pumpBody(tester, sessionsCubit);

    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
  });

  testWidgets('the orchestrator body opens the exact linked session id', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: const BoardSnapshot(
            projects: [ProjectModel(id: 'p1', name: 'One')],
            orchestrators: [OrchestratorModel(id: 'orchestrator-session', projectId: 'p1')],
          ),
        ),
      ),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux);

    await pumpBody(tester, sessionsCubit);
    await tester.tap(find.byTooltip('Open orchestrator'));
    await tester.pumpAndSettle();

    expect(find.text('orchestrator-session'), findsOneWidget);
  });

  testWidgets('with no projects and the board failed, the connection-failure copy shows with a Retry action', (
    tester,
  ) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401)),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux);

    await pumpBody(tester, sessionsCubit);

    expect(find.text('No projects'), findsNothing);
    expect(find.text('Your desktop rejected the password'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('with no projects and no failure, No projects shows', (tester) async {
    when(() => sessionsRepository.getBoard())
        .thenAnswer((_) async => Result.success(GlobalResponse(data: const BoardSnapshot())));
    final sessionsCubit = SessionsCubit(sessionsRepository, mux);

    await pumpBody(tester, sessionsCubit);

    expect(find.text('No projects'), findsOneWidget);
  });

}
