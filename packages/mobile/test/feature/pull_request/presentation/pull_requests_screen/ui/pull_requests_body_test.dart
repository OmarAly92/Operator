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
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';
import 'package:operator_mobile/feature/pull_request/data/repository/pull_request_repository.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pull_requests_body.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _MockPullRequestRepository extends Mock implements PullRequestRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

void main() {
  late _MockSessionsRepository sessionsRepository;
  late _MockMuxClient mux;
  late _MockPullRequestRepository prRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    sessionsRepository = _MockSessionsRepository();
    mux = _MockMuxClient();
    prRepository = _MockPullRequestRepository();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => prRepository.getSessionPr(any())).thenAnswer(
      (_) async => Result<GlobalResponse<List<SessionPrSummaryModel>>, Failure>.success(
        const GlobalResponse(data: []),
      ),
    );

    final serverConfigStore = _MockServerConfigStore();
    when(() => serverConfigStore.current).thenReturn(
      const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12'),
    );
    await sl.reset();
    sl.registerLazySingleton<ServerConfigStore>(() => serverConfigStore);
  });

  tearDown(() => sl.reset());

  Future<void> pumpBody(WidgetTester tester, SessionsCubit sessionsCubit, PullRequestCubit prCubit) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: BlocProvider<SessionsCubit>(
              create: (_) => sessionsCubit,
              child: BlocProvider<PullRequestCubit>(
                create: (_) => prCubit,
                child: const Scaffold(body: PullRequestsBody()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a session carrying an open PR renders one card, and the Open pill reads that count', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: const BoardSnapshot(
            sessions: [
              SessionModel(
                id: 's1',
                projectId: 'p1',
                displayName: 'Fix auth',
                prs: [SessionPrModel(number: 1, state: 'open')],
              ),
            ],
          ),
        ),
      ),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux);
    final prCubit = PullRequestCubit(prRepository);

    await pumpBody(tester, sessionsCubit, prCubit);

    expect(find.text('Open 1'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
  });

  testWidgets('tapping the Merged pill hides the open PR and shows a merged one', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: const BoardSnapshot(
            sessions: [
              SessionModel(id: 's1', projectId: 'p1', prs: [SessionPrModel(number: 1, state: 'open')]),
              SessionModel(id: 's2', projectId: 'p1', prs: [SessionPrModel(number: 2, state: 'merged')]),
            ],
          ),
        ),
      ),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux);
    final prCubit = PullRequestCubit(prRepository);

    await pumpBody(tester, sessionsCubit, prCubit);

    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsNothing);

    await tester.tap(find.text('Merged 1'));
    await tester.pumpAndSettle();

    expect(find.text('#1'), findsNothing);
    expect(find.text('#2'), findsOneWidget);
  });

  testWidgets('with two projects and the active project set to the second, only that project PR is listed', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: const BoardSnapshot(
            sessions: [
              SessionModel(id: 's1', projectId: 'p1', prs: [SessionPrModel(number: 1, state: 'open')]),
              SessionModel(id: 's2', projectId: 'p2', prs: [SessionPrModel(number: 2, state: 'open')]),
            ],
            projects: [ProjectModel(id: 'p1', name: 'One'), ProjectModel(id: 'p2', name: 'Two')],
          ),
        ),
      ),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux);
    sessionsCubit.setActiveProject('p2');
    final prCubit = PullRequestCubit(prRepository);

    await pumpBody(tester, sessionsCubit, prCubit);

    expect(find.text('#1'), findsNothing);
    expect(find.text('#2'), findsOneWidget);
  });

  testWidgets('with no PRs at all, the empty state reads No pull requests', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const BoardSnapshot())),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux);
    final prCubit = PullRequestCubit(prRepository);

    await pumpBody(tester, sessionsCubit, prCubit);

    expect(find.text('No pull requests'), findsOneWidget);
  });

  testWidgets('with the board failing and nothing cached, the connection-failure copy is shown instead', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401)),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux);
    final prCubit = PullRequestCubit(prRepository);

    await pumpBody(tester, sessionsCubit, prCubit);

    expect(find.text('No pull requests'), findsNothing);
    expect(find.text('Your desktop rejected the password'), findsOneWidget);
  });

  testWidgets('with an unreachable failure, the paired host and port appear in the message', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad')),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux);
    final prCubit = PullRequestCubit(prRepository);

    await pumpBody(tester, sessionsCubit, prCubit);

    expect(find.textContaining('10.0.0.5:3011'), findsOneWidget);
  });
}
