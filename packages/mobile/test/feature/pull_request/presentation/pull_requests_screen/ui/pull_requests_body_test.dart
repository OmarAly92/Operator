import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/re_pair_sheet/ui/re_pair_sheet.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/core/widgets/connection/connection_error_state.dart';
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
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/board_skeleton.dart';

import '../../../../../helpers/connection_harness.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _MockPairingRepository extends Mock implements PairingRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

void _registerRePair() {
  final store = _MockServerConfigStore();
  when(() => store.current).thenReturn(kTestDesktop);
  sl.registerFactoryParam<ManualConnectCubit, ManualConnectMode, void>(
    (mode, _) => ManualConnectCubit(_MockPairingRepository(), store, mode: mode),
  );
  addTearDown(sl.reset);
}

class _StubConfigSource implements ServerConfigSource {
  @override
  ServerConfig? get current => null;

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

class _MockPullRequestRepository extends Mock implements PullRequestRepository {}

void main() {
  late _MockSessionsRepository sessionsRepository;
  late _MockMuxClient mux;
  late _MockPullRequestRepository prRepository;
  late ConnectionHarness connection;

  setUp(() async {
    AppPreferences.debugLoad(const {});
    sessionsRepository = _MockSessionsRepository();
    when(() => sessionsRepository.cachedBoard()).thenAnswer((_) async => null);
    mux = _MockMuxClient();
    prRepository = _MockPullRequestRepository();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.boardChanges).thenAnswer((_) => const Stream<void>.empty());
    when(() => mux.status).thenAnswer((_) => const Stream<MuxStatus>.empty());
    when(() => mux.boardStreamReady).thenReturn(false);
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => prRepository.getSessionPr(any())).thenAnswer(
      (_) async => Result<GlobalResponse<List<SessionPrSummaryModel>>, Failure>.success(
        const GlobalResponse(data: []),
      ),
    );
    connection = ConnectionHarness();
  });

  tearDown(() => connection.dispose());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpBody(
    WidgetTester tester,
    SessionsCubit sessionsCubit,
    PullRequestCubit prCubit, {
    bool untilIdle = true,
  }) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (_) => Text(
              settings.name == RoutesStrings.session
                  ? (settings.arguments as Map<String, dynamic>)['sessionId'] as String
                  : 'route ${settings.name}',
            ),
          ),
          builder: (context, child) => SkinScope(skin: const DarkSkin(), child: child!),
          home: SkinScope(
            skin: const DarkSkin(),
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConnectionCubit>.value(value: connection.cubit),
                BlocProvider<SessionsCubit>(create: (_) => sessionsCubit),
                BlocProvider<PullRequestCubit>(create: (_) => prCubit),
              ],
              child: const Scaffold(body: PullRequestsBody()),
            ),
          ),
        ),
      ),
    );
    if (untilIdle) {
      await tester.pumpAndSettle();
    } else {
      await settle(tester);
    }
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
    final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
    final prCubit = PullRequestCubit(prRepository);

    await pumpBody(tester, sessionsCubit, prCubit);

    expect(find.text('Open 1'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
  });

  testWidgets('the PR body opens the exact backing session id', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: const BoardSnapshot(
            sessions: [
              SessionModel(
                id: 'pr-session',
                projectId: 'p1',
                prs: [SessionPrModel(number: 1, state: 'open')],
              ),
            ],
          ),
        ),
      ),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
    final prCubit = PullRequestCubit(prRepository);

    await pumpBody(tester, sessionsCubit, prCubit);
    await tester.tap(find.byTooltip('Open session'));
    await tester.pumpAndSettle();

    expect(find.text('pr-session'), findsOneWidget);
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
    final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
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
    final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
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
    final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
    final prCubit = PullRequestCubit(prRepository);

    await pumpBody(tester, sessionsCubit, prCubit);

    expect(find.text('No pull requests'), findsOneWidget);
  });

  testWidgets('with the board failing and nothing cached, the connection-failure copy is shown instead', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401)),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
    final prCubit = PullRequestCubit(prRepository);

    await pumpBody(tester, sessionsCubit, prCubit);

    expect(find.text('No pull requests'), findsNothing);
    expect(find.text('Your desktop rejected the password'), findsOneWidget);
  });

  testWidgets('with an unreachable failure, the paired host and port appear in the message', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad')),
    );
    final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
    final prCubit = PullRequestCubit(prRepository);

    await pumpBody(tester, sessionsCubit, prCubit);

    expect(find.textContaining('10.0.0.5:3011'), findsOneWidget);
  });

  group('start states', () {
    testWidgets('with nothing cached, skeleton cards stand in until the board arrives', (tester) async {
      final gate = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
      when(() => sessionsRepository.getBoard()).thenAnswer((_) => gate.future);
      final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
      final prCubit = PullRequestCubit(prRepository);

      await pumpBody(tester, sessionsCubit, prCubit, untilIdle: false);

      expect(find.byType(BoardSkeleton), findsOneWidget);
      expect(tester.widget<BoardSkeleton>(find.byType(BoardSkeleton)).label, 'Loading pull requests');
      expect(find.text('No pull requests'), findsNothing);

      gate.complete(Result.success(GlobalResponse(data: const BoardSnapshot())));
      await settle(tester);

      expect(find.byType(BoardSkeleton), findsNothing);
      expect(find.text('No pull requests'), findsOneWidget);
    });

    testWidgets('with nothing cached and the desktop down, the full-screen error names it and offers Switch desktop', (tester) async {
      when(() => sessionsRepository.getBoard()).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6)),
      );
      final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
      final prCubit = PullRequestCubit(prRepository);

      await pumpBody(tester, sessionsCubit, prCubit);

      expect(find.byType(ConnectionErrorState), findsOneWidget);
      expect(find.text("Can't reach Mac"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.byKey(ConnectionErrorState.switchKey));
      await tester.pumpAndSettle();

      expect(find.text('route ${RoutesStrings.connections}'), findsOneWidget);
    });

    testWidgets('Retry on the full-screen error fetches the board again', (tester) async {
      var fetches = 0;
      when(() => sessionsRepository.getBoard()).thenAnswer((_) async {
        fetches++;
        return Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6));
      });
      final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
      final prCubit = PullRequestCubit(prRepository);

      await pumpBody(tester, sessionsCubit, prCubit);
      await tester.tap(find.byKey(ConnectionErrorState.retryKey));
      await tester.pumpAndSettle();

      expect(fetches, 2);
    });

    testWidgets('an auth failure offers Re-pair instead of a retry that would spend an attempt', (tester) async {
      _registerRePair();
      var fetches = 0;
      when(() => sessionsRepository.getBoard()).thenAnswer((_) async {
        fetches++;
        return Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401));
      });
      final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
      final prCubit = PullRequestCubit(prRepository);

      await pumpBody(tester, sessionsCubit, prCubit);

      expect(find.text('Re-pair'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.tap(find.byKey(ConnectionErrorState.retryKey));
      await tester.pumpAndSettle();

      expect(find.byType(RePairForm), findsOneWidget);
      expect(find.text('route ${RoutesStrings.pairingScan}'), findsNothing);
      expect(fetches, 1);
    });

    testWidgets('with a cached board, a failure keeps its pull requests on screen', (tester) async {
      when(() => sessionsRepository.cachedBoard()).thenAnswer(
        (_) async => Replicated(
          value: const BoardSnapshot(
            sessions: [
              SessionModel(id: 's1', projectId: 'p1', prs: [SessionPrModel(number: 7, state: 'open')]),
            ],
          ),
          fetchedAt: DateTime.utc(2026, 9, 25, 8),
        ),
      );
      when(() => sessionsRepository.getBoard()).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6)),
      );
      final sessionsCubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
      final prCubit = PullRequestCubit(prRepository);

      await pumpBody(tester, sessionsCubit, prCubit);

      expect(find.text('#7'), findsOneWidget);
      expect(find.byType(ConnectionErrorState), findsNothing);
    });
  });
}
