import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/preferences/preference_keys.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/connection/connection_error_state.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/desktop_switcher/ui/desktop_switcher_sheet.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/re_pair_sheet/ui/re_pair_sheet.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/board_skeleton.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_section_header.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart';

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

class _MockDesktopsRepository extends Mock implements DesktopsRepository {}

class _MockPairingRemoteDataSource extends Mock implements PairingRemoteDataSource {}

void _registerSwitcher() {
  final desktops = _MockDesktopsRepository();
  when(() => desktops.watchDesktops()).thenAnswer((_) => Stream.value(const []));
  sl.registerFactory<ConnectionsCubit>(
    () => ConnectionsCubit(desktops, _MockPairingRemoteDataSource(), _MockServerConfigStore()),
  );
  addTearDown(sl.reset);
}

class _StubConfigSource implements ServerConfigSource {
  const _StubConfigSource([this.current]);

  @override
  final ServerConfig? current;

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;
  late ConnectionHarness connection;
  final List<String> fired = <String>[];

  setUp(() async {
    AppPreferences.debugLoad(const {});
    repository = _MockSessionsRepository();
    when(() => repository.cachedBoard()).thenAnswer((_) async => null);
    mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.boardChanges).thenAnswer((_) => const Stream<void>.empty());
    when(() => mux.status).thenAnswer((_) => const Stream<MuxStatus>.empty());
    when(() => mux.boardStreamReady).thenReturn(false);
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    fired.clear();
    connection = ConnectionHarness();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') fired.add('${call.arguments}');
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await connection.dispose();
  });

  // Session cards can render a perpetually-breathing `StatusDot` for
  // working/detecting sessions (`docs/design/components.md`'s testing note) —
  // `pumpAndSettle` never terminates while one is mounted, so every pump here
  // is bounded instead: a handful of short steps is enough to flush the
  // mocked repository's Future and any one-shot entrance/toggle animation.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpBody(
    WidgetTester tester,
    BoardSnapshot snapshot, {
    ServerConfigSource source = const _StubConfigSource(),
  }) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: snapshot)),
    );
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
                BlocProvider(create: (_) => SessionsCubit(repository, mux, source)),
              ],
              child: const Scaffold(body: SessionsBody()),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('resyncs when returning from the background', (tester) async {
    when(() => mux.boardStreamReady).thenReturn(true);
    await pumpBody(
      tester,
      const BoardSnapshot(
        sessions: [SessionModel(id: 'old', displayName: 'Before resume')],
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: const BoardSnapshot(
            sessions: [SessionModel(id: 'new', displayName: 'After resume')],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Before resume'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.text('After resume'), findsOneWidget);
    expect(find.text('Before resume'), findsNothing);
  });

  testWidgets('groups sessions into their board sections with a stat header', (tester) async {
    await pumpBody(
      tester,
      const BoardSnapshot(
        sessions: [
          SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
          SessionModel(id: 'b', projectId: 'proj', displayName: 'Needs you: fix login', status: 'needs_input'),
        ],
      ),
    );

    expect(find.text('Working one'), findsOneWidget);
    expect(find.text('Needs you: fix login'), findsOneWidget);
    expect(find.text('Working'), findsWidgets);
  });

  for (final target in const [
    (title: 'Active route', id: 'active-session', archived: false),
    (title: 'Archived route', id: 'archived-session', archived: true),
  ]) {
    testWidgets('opens the exact ${target.archived ? 'archived' : 'active'} board session id', (tester) async {
      await pumpBody(
        tester,
        BoardSnapshot(
          sessions: [
            SessionModel(
              id: target.id,
              projectId: 'proj',
              displayName: target.title,
              status: target.archived ? 'terminated' : 'working',
              isTerminated: target.archived,
            ),
          ],
        ),
      );

      if (target.archived) {
        await tester.tap(find.text('ARCHIVE'));
        await settle(tester);
      }

      await tester.tap(find.text(target.title));
      await settle(tester);

      expect(find.text(target.id), findsOneWidget);
    });
  }

  group('filter chips', () {
    testWidgets('tapping a filter chip fires a selection haptic and narrows the board', (tester) async {
      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [
            SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
            SessionModel(id: 'b', projectId: 'proj', displayName: 'Needs you: fix login', status: 'needs_input'),
          ],
        ),
      );

      await tester.tap(find.text('Needs you'));
      await settle(tester);

      expect(fired, contains('HapticFeedbackType.selectionClick'));
      expect(find.text('Needs you: fix login'), findsOneWidget);
      expect(find.text('Working one'), findsNothing);
    });

    testWidgets('a filter with no matching sessions shows the empty-filter message', (tester) async {
      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [
            SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
          ],
        ),
      );

      await tester.tap(find.text('Mergeable'));
      await settle(tester);

      expect(find.text('Nothing here right now.'), findsOneWidget);
    });

    testWidgets('section elements survive a board refresh', (tester) async {
      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [
            SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
          ],
        ),
      );

      final before = tester.element(find.byType(SessionSectionHeader).first);

      await tester.element(find.byType(SessionsBody)).read<SessionsCubit>().refresh();
      await settle(tester);

      final after = tester.element(find.byType(SessionSectionHeader).first);
      expect(identical(before, after), isTrue,
          reason: 'a rebuilt GlobalKey re-inflates the section on every poll tick');
    });
  });

  group('archive', () {
    testWidgets('keeps terminated sessions collapsed until the header is tapped', (tester) async {
      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [
            SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
            SessionModel(
              id: 'b',
              projectId: 'proj',
              displayName: 'Dead one',
              status: 'terminated',
              isTerminated: true,
            ),
          ],
        ),
      );

      expect(find.text('ARCHIVE'), findsOneWidget);
      expect(find.text('Dead one'), findsNothing);

      await tester.tap(find.text('ARCHIVE'));
      await settle(tester);

      expect(find.text('Dead one'), findsOneWidget);
    });
  });

  group('project filter', () {
    testWidgets('names the project a persisted filter is pinned to', (tester) async {
      AppPreferences.debugLoad({PreferenceKeys.activeProject('d-1'): 'scratch'});

      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [
            SessionModel(id: 'a', projectId: 'scratch', displayName: 'Scratch one', status: 'working'),
            SessionModel(id: 'b', projectId: 'other', displayName: 'Other one', status: 'working'),
          ],
          projects: [ProjectModel(id: 'scratch', name: 'Scratch')],
        ),
        source: const _StubConfigSource(
          ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw', desktopId: 'd-1'),
        ),
      );

      expect(find.text('Scratch'), findsOneWidget);
      expect(find.text('Scratch one'), findsOneWidget);
      expect(find.text('Other one'), findsNothing);
    });

    testWidgets('stays hidden on an unfiltered board with a single project', (tester) async {
      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [SessionModel(id: 'a', projectId: 'scratch', displayName: 'Scratch one', status: 'working')],
          projects: [ProjectModel(id: 'scratch', name: 'Scratch')],
        ),
      );

      expect(find.text('PROJECTS'), findsNothing);
    });
  });

  Future<void> pumpWithBoard(WidgetTester tester, Future<Result<GlobalResponse<BoardSnapshot>, Failure>> Function() board) async {
    when(() => repository.getBoard()).thenAnswer((_) => board());
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => Text('route ${settings.name}')),
          builder: (context, child) => SkinScope(skin: const DarkSkin(), child: child!),
          home: SkinScope(
            skin: const DarkSkin(),
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConnectionCubit>.value(value: connection.cubit),
                BlocProvider(create: (_) => SessionsCubit(repository, mux, const _StubConfigSource())),
              ],
              child: const Scaffold(body: SessionsBody()),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  group('start states', () {
    testWidgets('with nothing cached, six skeleton cards stand in until the board arrives', (tester) async {
      final gate = Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>();
      await pumpWithBoard(tester, () => gate.future);

      expect(find.byType(BoardSkeleton), findsOneWidget);
      expect(find.text('No agents yet'), findsNothing);
      expect(tester.widget<BoardSkeleton>(find.byType(BoardSkeleton)).label, 'Loading agents');

      gate.complete(Result.success(GlobalResponse(data: const BoardSnapshot(
        sessions: [SessionModel(id: 'w-1', displayName: 'Worker', status: 'working')],
      ))));
      await settle(tester);

      expect(find.byType(BoardSkeleton), findsNothing);
      expect(find.text('Worker'), findsOneWidget);
    });

    testWidgets('with nothing cached and the desktop down, a full-screen error names it and offers a way forward', (tester) async {
      await pumpWithBoard(
        tester,
        () async => Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6)),
      );

      expect(find.byType(ConnectionErrorState), findsOneWidget);
      expect(find.text("Can't reach Mac"), findsOneWidget);
      expect(find.byKey(ConnectionErrorState.retryKey), findsOneWidget);
      expect(find.byKey(ConnectionErrorState.switchKey), findsOneWidget);
    });

    testWidgets('Retry on the full-screen error fetches the board again', (tester) async {
      var fetches = 0;
      await pumpWithBoard(tester, () async {
        fetches++;
        return Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6));
      });

      await tester.tap(find.byKey(ConnectionErrorState.retryKey));
      await settle(tester);

      expect(fetches, 2);
    });

    testWidgets('an auth failure offers Re-pair instead of a retry that would spend an attempt', (tester) async {
      _registerRePair();
      var fetches = 0;
      await pumpWithBoard(tester, () async {
        fetches++;
        return Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401));
      });

      expect(find.text('Re-pair'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.tap(find.byKey(ConnectionErrorState.retryKey));
      await settle(tester);

      expect(find.byType(RePairForm), findsOneWidget);
      expect(find.text('route ${RoutesStrings.pairingScan}'), findsNothing);
      expect(fetches, 1);
    });

    testWidgets('Switch desktop on the full-screen error opens the desktop switcher', (tester) async {
      _registerSwitcher();
      await pumpWithBoard(
        tester,
        () async => Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6)),
      );

      await tester.tap(find.byKey(ConnectionErrorState.switchKey));
      await settle(tester);
      await settle(tester);

      expect(find.byType(DesktopSwitcherList), findsOneWidget);
    });

    testWidgets('with a cached board, a failure keeps the board on screen', (tester) async {
      when(() => repository.cachedBoard()).thenAnswer(
        (_) async => Replicated(
          value: const BoardSnapshot(sessions: [SessionModel(id: 'w-1', displayName: 'Cached worker', status: 'working')]),
          fetchedAt: DateTime.utc(2026, 9, 25, 8),
        ),
      );
      await pumpWithBoard(
        tester,
        () async => Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6)),
      );

      expect(find.text('Cached worker'), findsOneWidget);
      expect(find.byType(ConnectionErrorState), findsNothing);
    });

    testWidgets('an empty board online invites the first spawn toward the + button', (tester) async {
      await pumpWithBoard(tester, () async => Result.success(GlobalResponse(data: const BoardSnapshot())));

      expect(find.text('No agents yet'), findsOneWidget);
      expect(find.text('Spawn your first agent'), findsOneWidget);
      expect(find.byIcon(Icons.south_east_rounded), findsOneWidget);
    });

    testWidgets('with the cache applied before the first frame, frame one is the board', (tester) async {
      when(() => repository.cachedBoard()).thenAnswer(
        (_) async => Replicated(
          value: const BoardSnapshot(sessions: [SessionModel(id: 'w-1', displayName: 'Cached worker', status: 'working')]),
          fetchedAt: DateTime.utc(2026, 9, 25, 8),
        ),
      );
      when(() => repository.getBoard()).thenAnswer(
        (_) => Completer<Result<GlobalResponse<BoardSnapshot>, Failure>>().future,
      );
      final cubit = SessionsCubit(repository, mux, const _StubConfigSource());
      await cubit.cacheReady;

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: SkinScope(
              skin: const DarkSkin(),
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ConnectionCubit>.value(value: connection.cubit),
                  BlocProvider<SessionsCubit>.value(value: cubit),
                ],
                child: const Scaffold(body: SessionsBody()),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Cached worker'), findsOneWidget);
      expect(find.byType(BoardSkeleton), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    });
  });
}
