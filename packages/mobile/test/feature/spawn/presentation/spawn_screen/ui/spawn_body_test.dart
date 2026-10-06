import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/spawn/data/model/claude_account_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/get_project_branches_params.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/data/model/project_branch_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/project_branches_model.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart';

class _MockSpawnRepository extends Mock implements SpawnRepository {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _StubConfigSource implements ServerConfigSource {
  @override
  ServerConfig? get current => null;

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

AgentInfo _agent(String id) => AgentInfo(id: id, label: id, authStatus: 'authorized');

void main() {
  late _MockSpawnRepository spawnRepository;
  late _MockSessionsRepository sessionsRepository;
  late _MockMuxClient mux;

  setUpAll(() {
    registerFallbackValue(const SpawnSessionParams(projectId: 'p1'));
    registerFallbackValue(const GetProjectBranchesParams(projectId: 'p1'));
  });

  setUp(() async {
    AppPreferences.debugLoad(const {});
    spawnRepository = _MockSpawnRepository();
    sessionsRepository = _MockSessionsRepository();
    when(() => sessionsRepository.cachedBoard()).thenAnswer((_) async => null);
    mux = _MockMuxClient();
    when(() => spawnRepository.getBranches(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const ProjectBranchesModel(current: 'main', branches: []))),
    );

    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.boardChanges).thenAnswer((_) => const Stream<void>.empty());
    when(() => mux.status).thenAnswer((_) => const Stream<MuxStatus>.empty());
    when(() => mux.boardStreamReady).thenReturn(false);
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
    final cubit = SessionsCubit(sessionsRepository, mux, _StubConfigSource());
    cubit.activeProjectId = activeProjectId;
    sl.registerLazySingleton<SessionsCubit>(() => cubit);
    return cubit;
  }

  Future<void> pumpBody(WidgetTester tester, SpawnCubit spawnCubit) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (_) => Text((settings.arguments as Map<String, dynamic>)['sessionId'] as String),
            ),
            home: BlocProvider<SessionsCubit>(
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

  void stubCatalog() {
    when(() => spawnRepository.getAgents()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: AgentCatalog(supported: [_agent('amp'), _agent('claude-code')], installed: [_agent('amp'), _agent('claude-code')], authorized: [_agent('amp'), _agent('claude-code')])),
      ),
    );
    when(() => spawnRepository.getClaudeAccounts()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: const [
          ClaudeAccountModel(id: 'default', label: 'Default', isDefault: true, loggedIn: true, subscriptionType: 'max'),
          ClaudeAccountModel(id: 'personal', label: 'Personal', isDefault: false, loggedIn: true, subscriptionType: 'pro'),
        ]),
      ),
    );
  }

  void stubProjectKind(String? kind) {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: BoardSnapshot(projects: [ProjectModel(id: 'p1', name: 'Alpha', kind: kind)]),
        ),
      ),
    );
  }

  testWidgets('a project that never uses a worktree is not described as the project checkout', (tester) async {
    stubCatalog();
    stubProjectKind('scratch');
    buildSessionsCubit();

    await pumpBody(tester, SpawnCubit(spawnRepository));
    await tester.pumpAndSettle();

    expect(find.textContaining('project checkout'), findsNothing);
    expect(find.textContaining('isolated workspace'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('a single-repo project defaults to working in the project checkout', (tester) async {
    stubCatalog();
    stubProjectKind('single_repo');
    buildSessionsCubit();

    await pumpBody(tester, SpawnCubit(spawnRepository));
    await tester.pumpAndSettle();

    expect(find.textContaining('project checkout'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('submitting with an empty name shows the required message and calls no repository', (tester) async {
    stubCatalog();
    buildSessionsCubit();
    final spawnCubit = SpawnCubit(spawnRepository);

    await pumpBody(tester, spawnCubit);

    await tester.tap(find.text('Spawn agent'));
    await tester.pumpAndSettle();

    expect(find.text('Name and task are required.'), findsOneWidget);
    verifyNever(() => spawnRepository.spawn(any()));
  });

  testWidgets('a filled form calls repository.spawn once', (tester) async {
    stubCatalog();
    when(() => spawnRepository.spawn(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const SessionModel(id: 's1', displayName: 'flaky login'))),
    );
    buildSessionsCubit();
    final spawnCubit = SpawnCubit(spawnRepository);

    await pumpBody(tester, spawnCubit);

    expect(find.text('INTERFACE'), findsNothing);
    expect(find.text('Chat'), findsNothing);

    await tester.enterText(find.byType(TextField).at(0), 'flaky login');
    await tester.enterText(find.byType(TextField).at(1), 'fix the flake');
    await tester.tap(find.text('Spawn agent'));
    await tester.pumpAndSettle();

    verify(() => spawnRepository.spawn(any())).called(1);
    expect(find.text('s1'), findsOneWidget);
  });

  testWidgets('the Account row appears only for Claude Code', (tester) async {
    stubCatalog();
    stubProjectKind('single_repo');
    buildSessionsCubit();
    final spawnCubit = SpawnCubit(spawnRepository);

    await pumpBody(tester, spawnCubit);
    spawnCubit.setHarness('amp');
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsNothing);

    spawnCubit.setHarness('claude-code');
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Default · Max'), findsOneWidget);
  });

  group('Branch row', () {
    const listing = ProjectBranchesModel(
      current: 'logic/home',
      branches: [
        ProjectBranchModel(name: 'logic/home', checkedOutAt: '/Users/me/rafeeq', isMainCheckout: true),
        ProjectBranchModel(name: 'feat/x', checkedOutAt: '/Users/me/.worktrees/rafeeq-3', isMainCheckout: false),
        ProjectBranchModel(name: 'main', isMainCheckout: false),
      ],
    );

    void phone(WidgetTester tester) {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
    }

    void stubBranches(ProjectBranchesModel model) {
      when(() => spawnRepository.getBranches(any()))
          .thenAnswer((_) async => Result.success(GlobalResponse(data: model)));
    }

    Finder branchRow() => find.byKey(const ValueKey('spawn-branch-row'));

    Future<SpawnCubit> pumpSingleRepo(WidgetTester tester, {ProjectBranchesModel model = listing}) async {
      phone(tester);
      stubCatalog();
      stubProjectKind('single_repo');
      stubBranches(model);
      buildSessionsCubit();
      final spawnCubit = SpawnCubit(spawnRepository);
      await pumpBody(tester, spawnCubit);
      return spawnCubit;
    }

    Future<void> openBranchPage(WidgetTester tester, SpawnCubit spawnCubit) async {
      spawnCubit.setUseWorktree(true);
      await tester.pumpAndSettle();
      await tester.tap(branchRow());
      await tester.pumpAndSettle();
    }

    testWidgets('is absent for a project that is not a single repo', (tester) async {
      phone(tester);
      stubCatalog();
      stubProjectKind('scratch');
      buildSessionsCubit();

      await pumpBody(tester, SpawnCubit(spawnRepository));

      expect(branchRow(), findsNothing);
      verifyNever(() => spawnRepository.getBranches(any()));
    });

    testWidgets('without a worktree shows the current branch and is not tappable', (tester) async {
      await pumpSingleRepo(tester);

      expect(find.descendant(of: branchRow(), matching: find.text('Branch')), findsOneWidget);
      expect(find.descendant(of: branchRow(), matching: find.text('logic/home')), findsOneWidget);
      expect(find.descendant(of: branchRow(), matching: find.byIcon(Icons.chevron_right)), findsNothing);

      await tester.tap(branchRow());
      await tester.pumpAndSettle();
      expect(find.byKey(AppSheet.surfaceKey), findsNothing);
    });

    testWidgets('without a worktree on a detached HEAD reads Detached HEAD', (tester) async {
      await pumpSingleRepo(tester, model: const ProjectBranchesModel(current: '', branches: []));

      expect(find.descendant(of: branchRow(), matching: find.text('Detached HEAD')), findsOneWidget);
    });

    testWidgets('with a worktree defaults to New branch and sits under the worktree switch', (tester) async {
      final spawnCubit = await pumpSingleRepo(tester);
      spawnCubit.setUseWorktree(true);
      await tester.pumpAndSettle();

      expect(find.descendant(of: branchRow(), matching: find.text('New branch')), findsOneWidget);
      expect(
        tester.getTopLeft(branchRow()).dy,
        greaterThan(tester.getTopLeft(find.text('Create a git worktree')).dy),
      );
    });

    testWidgets('the page lists New branch first and disables busy branches with their reason', (tester) async {
      final spawnCubit = await pumpSingleRepo(tester);
      await openBranchPage(tester, spawnCubit);

      final newBranch = find.byKey(const ValueKey('spawn-branch-new'));
      final home = find.byKey(const ValueKey('spawn-branch-logic/home'));
      final feat = find.byKey(const ValueKey('spawn-branch-feat/x'));
      final main = find.byKey(const ValueKey('spawn-branch-main'));
      expect(newBranch, findsOneWidget);
      expect(tester.getTopLeft(newBranch).dy, lessThan(tester.getTopLeft(home).dy));
      expect(tester.getTopLeft(home).dy, lessThan(tester.getTopLeft(feat).dy));
      expect(tester.getTopLeft(feat).dy, lessThan(tester.getTopLeft(main).dy));

      expect(
        find.descendant(
          of: home,
          matching: find.text('Checked out in your project folder — turn off worktree to work on it'),
        ),
        findsOneWidget,
      );
      expect(find.descendant(of: feat, matching: find.text('In use by rafeeq-3')), findsOneWidget);
      expect(find.ancestor(of: home, matching: find.byType(Opacity)), findsOneWidget);
      expect(find.ancestor(of: main, matching: find.byType(Opacity)), findsNothing);

      await tester.tap(feat);
      await tester.pumpAndSettle();
      expect(spawnCubit.selectedBranch, isNull);
      expect(find.byKey(AppSheet.surfaceKey), findsOneWidget);

      await tester.tap(main);
      await tester.pumpAndSettle();
      expect(spawnCubit.selectedBranch, 'main');
      expect(find.byKey(AppSheet.surfaceKey), findsNothing);
      expect(find.descendant(of: branchRow(), matching: find.text('main')), findsOneWidget);
    });

    testWidgets('search appears only above ten branches and filters by substring', (tester) async {
      final ten = ProjectBranchesModel(
        current: 'b0',
        branches: [for (var i = 0; i < 10; i++) ProjectBranchModel(name: 'b$i')],
      );
      final spawnCubit = await pumpSingleRepo(tester, model: ten);
      await openBranchPage(tester, spawnCubit);
      expect(find.byKey(const ValueKey('spawn-branch-b9')), findsOneWidget);
      expect(find.byKey(const ValueKey('spawn-branch-search')), findsNothing);
      Navigator.of(tester.element(find.byKey(AppSheet.surfaceKey))).pop();
      await tester.pumpAndSettle();

      final eleven = ProjectBranchesModel(
        current: 'main',
        branches: [
          const ProjectBranchModel(name: 'Feat/Login'),
          for (var i = 0; i < 9; i++) ProjectBranchModel(name: 'b$i'),
          const ProjectBranchModel(name: 'fix/login-flake'),
        ],
      );
      stubBranches(eleven);
      await spawnCubit.setProject('p1', kind: 'single_repo');
      await tester.pumpAndSettle();
      await openBranchPage(tester, spawnCubit);

      expect(find.byKey(const ValueKey('spawn-branch-search')), findsOneWidget);
      expect(find.byType(AppTextField), findsNWidgets(3));
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('spawn-branch-search')), matching: find.byType(TextField)),
        'LOGIN',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('spawn-branch-Feat/Login')), findsOneWidget);
      expect(find.byKey(const ValueKey('spawn-branch-fix/login-flake')), findsOneWidget);
      expect(find.byKey(const ValueKey('spawn-branch-b0')), findsNothing);
      expect(find.byKey(const ValueKey('spawn-branch-new')), findsNothing);
    });

    testWidgets('a failed load says so on the row and New branch still works', (tester) async {
      phone(tester);
      stubCatalog();
      stubProjectKind('single_repo');
      when(() => spawnRepository.getBranches(any()))
          .thenAnswer((_) async => Result.failure(ServerFailure(error: 'x', message: 'boom')));
      buildSessionsCubit();
      final spawnCubit = SpawnCubit(spawnRepository);
      await pumpBody(tester, spawnCubit);

      expect(find.descendant(of: branchRow(), matching: find.text("Couldn't load branches")), findsOneWidget);

      await openBranchPage(tester, spawnCubit);
      await tester.tap(find.byKey(const ValueKey('spawn-branch-new')));
      await tester.pumpAndSettle();
      expect(spawnCubit.selectedBranch, isNull);
      expect(find.descendant(of: branchRow(), matching: find.text('New branch')), findsOneWidget);
    });

    for (final (code, message) in [
      ('BRANCH_CHECKED_OUT_ELSEWHERE', 'That branch is checked out somewhere else. Pick another branch or New branch.'),
      ('BRANCH_NOT_CHECKED_OUT', 'The project folder is on a different branch now. Reopen this screen and try again.'),
    ]) {
      testWidgets('a $code refusal explains itself and keeps the typed text', (tester) async {
        when(() => spawnRepository.spawn(any())).thenAnswer(
          (_) async => Result.failure(ServerFailure(error: 'x', message: 'raw', statusCode: 409, apiStatus: code)),
        );
        await pumpSingleRepo(tester);

        await tester.enterText(find.byType(TextField).at(0), 'flaky login');
        await tester.enterText(find.byType(TextField).at(1), 'fix the flake');
        await tester.tap(find.text('Spawn agent'));
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(find.text('flaky login'), findsOneWidget);
        expect(find.text('fix the flake'), findsOneWidget);
      });
    }
  });
}
