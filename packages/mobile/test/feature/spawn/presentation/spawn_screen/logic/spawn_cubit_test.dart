import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/claude_account_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/logic/spawn_option_values.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';

class _MockSpawnRepository extends Mock implements SpawnRepository {}

AgentInfo _agent(String id) => AgentInfo(id: id, label: id, authStatus: 'authorized');

AgentCatalog get _catalog => AgentCatalog(
  supported: [_agent('claude-code'), _agent('codex')],
  installed: [_agent('claude-code'), _agent('codex')],
  authorized: [_agent('claude-code'), _agent('codex')],
);

List<ClaudeAccountModel> get _accounts => const [
  ClaudeAccountModel(id: 'default', label: 'Default', isDefault: true, loggedIn: true, subscriptionType: 'max'),
  ClaudeAccountModel(id: 'personal', label: 'Personal', isDefault: false, loggedIn: true, subscriptionType: 'pro'),
];

void main() {
  group('SpawnSessionParams', () {
    test('omits workspaceMode when not given, so the server default applies', () {
      final params = SpawnSessionParams(projectId: 'p-1');
      expect(params.toJson().containsKey('workspaceMode'), isFalse);
    });

    test('sends in_place when explicitly chosen', () {
      final params = SpawnSessionParams(projectId: 'p-1', workspaceMode: 'in_place');
      expect(params.toJson()['workspaceMode'], 'in_place');
    });

    test('sends worktree when the toggle is on', () {
      final params = SpawnSessionParams(projectId: 'p-1', workspaceMode: 'worktree');
      expect(params.toJson()['workspaceMode'], 'worktree');
    });
  });

  late _MockSpawnRepository repository;

  SpawnCubit buildCubit() {
    when(() => repository.getAgents())
        .thenAnswer((_) async => Result.success(GlobalResponse(data: _catalog)));
    return SpawnCubit(repository);
  }

  setUpAll(() => registerFallbackValue(const SpawnSessionParams(projectId: 'p')));

  setUp(() {
    repository = _MockSpawnRepository();
    when(() => repository.spawn(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const SessionModel(id: 's1'))),
    );
    when(() => repository.getClaudeAccounts())
        .thenAnswer((_) async => Result.success(GlobalResponse(data: _accounts)));
  });

  blocTest<SpawnCubit, SpawnState>(
    'offers the whole catalog and picks its default agent',
    build: buildCubit,
    act: (cubit) => cubit.loadCatalog(),
    verify: (cubit) {
      expect(cubit.agents.map((a) => a.id), ['claude-code', 'codex']);
      expect(cubit.harness, 'claude-code');
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'emits when the project changes',
    build: () => SpawnCubit(repository),
    act: (cubit) => cubit.setProject('p'),
    expect: () => [isA<CatalogReadyState>().having((s) => s.revision, 'revision', 1)],
    verify: (cubit) => expect(cubit.projectId, 'p'),
  );

  blocTest<SpawnCubit, SpawnState>(
    'emits when the harness changes',
    build: () => SpawnCubit(repository),
    act: (cubit) => cubit.setHarness('codex'),
    expect: () => [isA<CatalogReadyState>().having((s) => s.revision, 'revision', 1)],
    verify: (cubit) => expect(cubit.harness, 'codex'),
  );

  blocTest<SpawnCubit, SpawnState>(
    'reports a catalog fetch failure instead of showing an empty picker',
    build: () {
      when(() => repository.getAgents())
          .thenAnswer((_) async => Result.failure(ServerFailure(error: 'x', message: 'boom')));
      return SpawnCubit(repository);
    },
    act: (cubit) => cubit.loadCatalog(),
    expect: () => [isA<CatalogLoadingState>(), isA<CatalogFailureState>()],
  );

  blocTest<SpawnCubit, SpawnState>(
    'refuses to submit without a name and a task',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p');
      cubit.name = '  ';
      cubit.prompt = 'do the thing';
      await cubit.submit();
    },
    verify: (cubit) => verifyNever(() => repository.spawn(any())),
    expect: () => [
      isA<CatalogLoadingState>(),
      isA<CatalogReadyState>(),
      isA<CatalogReadyState>(),
      isA<CatalogReadyState>(),
      isA<SpawnValidationFailureState>(),
    ],
  );

  blocTest<SpawnCubit, SpawnState>(
    'spawns with the chosen project and agent and never names a session mode',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p');
      cubit.name = 'flaky login';
      cubit.prompt = 'fix it';
      await cubit.submit();
    },
    verify: (cubit) {
      final params = verify(() => repository.spawn(captureAny())).captured.single
          as SpawnSessionParams;
      expect(params.projectId, 'p');
      expect(params.issueId, 'flaky login');
      expect(params.prompt, 'fix it');
      expect(params.harness, 'claude-code');
      expect(params.toJson().containsKey('mode'), isFalse);
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'surfaces a spawn failure with the daemon message',
    build: () {
      when(() => repository.getAgents())
          .thenAnswer((_) async => Result.success(GlobalResponse(data: _catalog)));
      when(() => repository.spawn(any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'branch is busy')),
      );
      return SpawnCubit(repository);
    },
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p');
      cubit.name = 'n';
      cubit.prompt = 'p';
      await cubit.submit();
    },
    verify: (cubit) => expect((cubit.state as SpawnFailureState).failure.message, 'branch is busy'),
  );

  blocTest<SpawnCubit, SpawnState>(
    'emits when the worktree toggle changes',
    build: () => SpawnCubit(repository),
    act: (cubit) => cubit.setUseWorktree(true),
    expect: () => [isA<CatalogReadyState>().having((s) => s.revision, 'revision', 1)],
    verify: (cubit) => expect(cubit.useWorktree, isTrue),
  );

  blocTest<SpawnCubit, SpawnState>(
    'defaults to in_place and sends worktree only when toggled on',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p', kind: 'single_repo');
      cubit.setUseWorktree(true);
      cubit.name = 'flaky login';
      cubit.prompt = 'fix it';
      await cubit.submit();
    },
    verify: (cubit) {
      final params = verify(() => repository.spawn(captureAny())).captured.single
          as SpawnSessionParams;
      expect(params.workspaceMode, 'worktree');
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'omits workspaceMode for a non-single_repo project regardless of the toggle',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p', kind: 'workspace');
      cubit.setUseWorktree(true);
      cubit.name = 'flaky login';
      cubit.prompt = 'fix it';
      await cubit.submit();
    },
    verify: (cubit) {
      final params = verify(() => repository.spawn(captureAny())).captured.single
          as SpawnSessionParams;
      expect(params.workspaceMode, isNull);
      expect(params.toJson().containsKey('workspaceMode'), isFalse);
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'loads Claude accounts with the catalog',
    build: buildCubit,
    act: (cubit) => cubit.loadCatalog(),
    verify: (cubit) {
      expect(cubit.claudeAccounts.map((a) => a.id), ['default', 'personal']);
      expect(cubit.claudeAccountId, 'default');
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'preselects the preferred account and resets to it on agent change',
    build: () {
      when(() => repository.getClaudeAccounts()).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(
            data: const [
              ClaudeAccountModel(id: 'default', label: 'Default', isDefault: true, isPreferred: false, loggedIn: true, subscriptionType: 'max'),
              ClaudeAccountModel(id: 'personal', label: 'Personal', isDefault: false, isPreferred: true, loggedIn: true, subscriptionType: 'pro'),
            ],
          ),
        ),
      );
      return buildCubit();
    },
    act: (cubit) async {
      await cubit.loadCatalog();
      expect(cubit.claudeAccountId, 'personal');
      cubit.setClaudeAccount('default');
      cubit.setHarness('claude-code');
    },
    verify: (cubit) => expect(cubit.claudeAccountId, 'personal'),
  );

  test('ClaudeAccountModel parses isPreferred and resolves the preferred id', () {
    final accounts = ClaudeAccountModel.listFromJson({
      'accounts': [
        {'id': 'default', 'label': 'Default', 'isDefault': true, 'isPreferred': false, 'status': {'loggedIn': true}},
        {'id': 'personal', 'label': 'Personal', 'isDefault': false, 'isPreferred': true, 'status': {'loggedIn': true}},
      ],
    });
    expect(accounts[1].isPreferred, isTrue);
    expect(ClaudeAccountModel.preferredId(accounts), 'personal');
    expect(ClaudeAccountModel.preferredId(const []), 'default');
  });

  blocTest<SpawnCubit, SpawnState>(
    'changing the agent resets the account',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setClaudeAccount('personal');
      cubit.setHarness('codex');
    },
    verify: (cubit) => expect(cubit.claudeAccountId, 'default'),
  );

  blocTest<SpawnCubit, SpawnState>(
    'submits the account only for claude-code',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit
        ..setProject('p-1')
        ..name = 'n'
        ..prompt = 'p'
        ..setHarness('claude-code')
        ..setClaudeAccount('personal');
      await cubit.submit();
    },
    verify: (_) {
      final params = verify(() => repository.spawn(captureAny())).captured.single as SpawnSessionParams;
      expect(params.claudeAccountId, 'personal');
    },
  );

  test('SpawnSessionParams omits claudeAccountId when absent', () {
    expect(const SpawnSessionParams(projectId: 'p').toJson().containsKey('claudeAccountId'), isFalse);
    expect(const SpawnSessionParams(projectId: 'p', claudeAccountId: 'personal').toJson()['claudeAccountId'], 'personal');
  });

  blocTest<SpawnCubit, SpawnState>(
    'spawns in bypass permissions unless another mode is chosen',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setProject('p');
      cubit.name = 'flaky login';
      cubit.prompt = 'fix it';
      await cubit.submit();
      cubit.setPermissionMode('accept-edits');
      await cubit.submit();
    },
    verify: (cubit) {
      final captured = verify(() => repository.spawn(captureAny())).captured.cast<SpawnSessionParams>();
      expect(captured.map((params) => params.permissionMode), ['bypass-permissions', 'accept-edits']);
      expect(captured.first.toJson()['permissionMode'], 'bypass-permissions');
    },
  );

  test('plan is offered only for Claude Code and falls back to bypass on another agent', () async {
    final cubit = buildCubit();
    await cubit.loadCatalog();
    cubit.setHarness('claude-code');
    cubit.setPermissionMode('plan');

    cubit.setHarness('codex');

    expect(cubit.permissionMode, kDefaultSpawnPermissionMode);
    expect(SpawnOptionValues.permissionModesFor('codex'), isNot(contains('plan')));
    expect(SpawnOptionValues.permissionModesFor('claude-code'), contains('plan'));
    await cubit.close();
  });

  test('a params object without a permission mode sends none', () {
    expect(const SpawnSessionParams(projectId: 'p').toJson().containsKey('permissionMode'), isFalse);
    expect(const SpawnSessionParams(projectId: 'p', permissionMode: 'auto').toJson()['permissionMode'], 'auto');
  });
}
