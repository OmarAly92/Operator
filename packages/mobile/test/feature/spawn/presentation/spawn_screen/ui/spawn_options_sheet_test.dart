import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/claude_account_model.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_options_sheet.dart';

class _MockSpawnRepository extends Mock implements SpawnRepository {}

const _claude = AgentInfo(id: 'claude-code', label: 'Claude Code', authStatus: 'authorized');
const _codex = AgentInfo(id: 'codex', label: 'Codex', authStatus: 'authorized');
const _catalog = AgentCatalog(supported: [_claude, _codex], installed: [_claude, _codex], authorized: [_claude, _codex]);

const _projects = [
  ProjectModel(id: 'p1', name: 'Alpha', kind: 'single_repo'),
  ProjectModel(id: 'p2', name: 'Beta', kind: 'scratch'),
];

void main() {
  late _MockSpawnRepository repository;
  late SpawnCubit cubit;
  late int refreshes;

  setUp(() async {
    repository = _MockSpawnRepository();
    refreshes = 0;
    when(() => repository.getAgents()).thenAnswer((_) async => Result.success(GlobalResponse(data: _catalog)));
    when(() => repository.getClaudeAccounts()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: const [
          ClaudeAccountModel(id: 'default', label: 'Default', isDefault: true, loggedIn: true, subscriptionType: 'max'),
          ClaudeAccountModel(id: 'work', label: 'Work', isDefault: false, loggedIn: true, subscriptionType: 'pro'),
        ]),
      ),
    );
    cubit = SpawnCubit(repository);
    await cubit.loadCatalog();
    cubit.setHarness('claude-code');
  });

  tearDown(() => cubit.close());

  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
  }

  Future<void> open(WidgetTester tester, SpawnOption option, {Future<void> Function()? onRefreshAgents}) async {
    phone(tester);
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showSpawnOptionsSheet(
                      context,
                      cubit: cubit,
                      projects: _projects,
                      open: option,
                      onRefreshAgents: onRefreshAgents ?? () async => refreshes++,
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('picking an agent sets the harness and pops to the root showing it', (tester) async {
    await open(tester, SpawnOption.agent);

    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('Which harness should run this task.'), findsOneWidget);
    expect(find.byKey(AppSheet.backKey), findsOneWidget);

    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();

    expect(cubit.harness, 'codex');
    expect(find.text('Spawn options'), findsOneWidget);
    expect(find.byKey(AppSheet.backKey), findsNothing);
    expect(find.text('Codex'), findsOneWidget);
  });

  testWidgets('the root has an Account row only for Claude Code with accounts', (tester) async {
    await open(tester, SpawnOption.agent);
    await tester.tap(find.byKey(AppSheet.backKey));
    await tester.pumpAndSettle();

    expect(find.text('Spawn options'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Default · Max'), findsOneWidget);

    cubit.setHarness('codex');
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsNothing);
  });

  testWidgets('searching accounts and picking one sets the Claude account', (tester) async {
    await open(tester, SpawnOption.account);

    expect(find.text('Claude account'), findsOneWidget);
    expect(find.text('Which Claude login this session runs on.'), findsOneWidget);

    await tester.enterText(find.byKey(AppSheet.searchFieldKey), 'wor');
    await tester.pumpAndSettle();
    expect(find.text('Default'), findsNothing);

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    expect(cubit.claudeAccountId, 'work');
    expect(find.text('Spawn options'), findsOneWidget);
    expect(find.text('Work · Pro'), findsOneWidget);
  });

  testWidgets('picking a project sets it with its kind', (tester) async {
    await open(tester, SpawnOption.project);

    expect(find.text('Project'), findsOneWidget);
    expect(find.text('Where this agent gets its workspace.'), findsOneWidget);
    expect(find.text('All projects'), findsNothing);

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    expect(cubit.projectId, 'p2');
    expect(cubit.projectKind, 'scratch');
    expect(find.text('Spawn options'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('Done closes the sheet', (tester) async {
    await open(tester, SpawnOption.agent);
    await tester.tap(find.byKey(AppSheet.backKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byKey(AppSheet.surfaceKey), findsNothing);
  });

  testWidgets('refresh shows a loader while loading and a failure updates the page live', (tester) async {
    final pending = Completer<Result<GlobalResponse<AgentCatalog>, Failure>>();
    when(() => repository.refreshAgents()).thenAnswer((_) => pending.future);
    await open(tester, SpawnOption.agent, onRefreshAgents: () async {
      refreshes++;
      await cubit.refreshCatalog();
    });

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    expect(refreshes, 1);
    expect(find.byType(AppLoader), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);

    await tester.tap(find.byType(AppLoader), warnIfMissed: false);
    await tester.pump();
    expect(refreshes, 1);

    pending.complete(Result.failure(ServerFailure(error: 'x', message: 'boom')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Could not reach your Operator server'), findsOneWidget);
  });
}
