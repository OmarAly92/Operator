import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/orchestrator/data/model/params/launch_orchestrator_params.dart';
import 'package:operator_mobile/feature/orchestrator/data/repository/orchestrator_repository.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_card.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockOrchestratorRepository extends Mock implements OrchestratorRepository {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

void main() {
  late _MockOrchestratorRepository repository;
  late _MockSessionsRepository sessionsRepository;
  late _MockMuxClient mux;

  setUpAll(() => registerFallbackValue(const LaunchOrchestratorParams(projectId: 'p', clean: false, mode: 'chat')));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    repository = _MockOrchestratorRepository();
    sessionsRepository = _MockSessionsRepository();
    mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => sessionsRepository.getBoard())
        .thenAnswer((_) async => Result.success(GlobalResponse(data: const BoardSnapshot())));
    when(() => repository.launch(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const OrchestratorModel(id: 'o1'))),
    );
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    required OrchestratorModel? link,
    required List<SessionModel> workers,
    VoidCallback? onOpen,
  }) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<SessionsCubit>(create: (_) => SessionsCubit(sessionsRepository, mux)),
                BlocProvider<OrchestratorCubit>(create: (_) => OrchestratorCubit(repository)),
              ],
              child: Scaffold(
                body: OrchestratorCard(
                  projectId: 'p',
                  projectName: 'Test project',
                  link: link,
                  workers: workers,
                  onOpenBoard: () {},
                  onOpen: onOpen,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers Start for a project with no orchestrator', (tester) async {
    await pumpCard(tester, link: null, workers: const []);

    expect(find.text('Start orchestrator'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
  });

  testWidgets('starts without a confirmation', (tester) async {
    await pumpCard(tester, link: null, workers: const []);

    await tester.tap(find.text('Start orchestrator'));
    await tester.pumpAndSettle();

    final params = verify(() => repository.launch(captureAny())).captured.single as LaunchOrchestratorParams;
    expect(params.clean, isFalse);
  });

  testWidgets('asks before restarting a running orchestrator', (tester) async {
    await pumpCard(tester, link: const OrchestratorModel(id: 'o1', projectId: 'p'), workers: const []);

    await tester.tap(find.byTooltip('Restart orchestrator'));
    await tester.pumpAndSettle();

    expect(find.text('Restart orchestrator?'), findsOneWidget);
    verifyNever(() => repository.launch(any()));

    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();

    final params = verify(() => repository.launch(captureAny())).captured.single as LaunchOrchestratorParams;
    expect(params.clean, isTrue);
  });

  testWidgets('does not restart when the confirmation is declined', (tester) async {
    await pumpCard(tester, link: const OrchestratorModel(id: 'o1', projectId: 'p'), workers: const []);

    await tester.tap(find.byTooltip('Restart orchestrator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repository.launch(any()));
  });

  testWidgets('counts workers and shows a pill per attention zone', (tester) async {
    await pumpCard(
      tester,
      link: const OrchestratorModel(id: 'o1', projectId: 'p'),
      workers: const [
        SessionModel(id: 'a', projectId: 'p', status: 'working'),
        SessionModel(id: 'b', projectId: 'p', status: 'working'),
        SessionModel(id: 'c', projectId: 'p', status: 'needs_input'),
      ],
    );

    expect(find.text('3 workers'), findsOneWidget);
    expect(find.text('Working'), findsWidgets);
    expect(find.text('Needs you'), findsOneWidget);
  });

  testWidgets('says worker in the singular for one', (tester) async {
    await pumpCard(
      tester,
      link: const OrchestratorModel(id: 'o1', projectId: 'p'),
      workers: const [SessionModel(id: 'a', projectId: 'p', status: 'working')],
    );

    expect(find.text('1 worker'), findsOneWidget);
  });

  testWidgets('opens the orchestrator session', (tester) async {
    var opened = 0;
    await pumpCard(
      tester,
      link: const OrchestratorModel(id: 'o1', projectId: 'p'),
      workers: const [],
      onOpen: () => opened++,
    );

    await tester.tap(find.byTooltip('Open orchestrator'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
}
