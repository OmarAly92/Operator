import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/operator_settings_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';

class _MockSpawnRepository extends Mock implements SpawnRepository {}

AgentInfo _agent(String id) => AgentInfo(id: id, label: id, authStatus: 'authorized');

AgentCatalog get _catalog => AgentCatalog(
  supported: [_agent('claude-code'), _agent('codex')],
  installed: [_agent('claude-code'), _agent('codex')],
  authorized: [_agent('claude-code'), _agent('codex')],
);

void main() {
  late _MockSpawnRepository repository;

  SpawnCubit buildCubit() {
    when(() => repository.getAgents())
        .thenAnswer((_) async => Result.success(GlobalResponse(data: _catalog)));
    when(() => repository.getSettings()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: const OperatorSettingsModel(chatHarnesses: ['claude-code'])),
      ),
    );
    return SpawnCubit(repository);
  }

  setUpAll(() => registerFallbackValue(const SpawnSessionParams(projectId: 'p', mode: 'chat')));

  setUp(() {
    repository = _MockSpawnRepository();
    when(() => repository.spawn(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const SessionModel(id: 's1'))),
    );
  });

  blocTest<SpawnCubit, SpawnState>(
    'offers only chat-capable agents in chat mode',
    build: buildCubit,
    act: (cubit) => cubit.loadCatalog(),
    verify: (cubit) {
      expect(cubit.mode, 'chat');
      expect(cubit.agents.map((a) => a.id), ['claude-code']);
      expect(cubit.harness, 'claude-code');
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'offers the whole catalog in tui mode',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setMode('tui');
    },
    verify: (cubit) => expect(cubit.agents.map((a) => a.id), ['claude-code', 'codex']),
  );

  blocTest<SpawnCubit, SpawnState>(
    're-picks a chat-capable default when switching back to chat',
    build: buildCubit,
    act: (cubit) async {
      await cubit.loadCatalog();
      cubit.setMode('tui');
      cubit.setHarness('codex');
      cubit.setMode('chat');
    },
    verify: (cubit) => expect(cubit.harness, 'claude-code'),
  );

  blocTest<SpawnCubit, SpawnState>(
    'reports a catalog fetch failure instead of showing an empty picker',
    build: () {
      when(() => repository.getAgents())
          .thenAnswer((_) async => Result.failure(ServerFailure(error: 'x', message: 'boom')));
      when(() => repository.getSettings()).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const OperatorSettingsModel())),
      );
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
      isA<SpawnValidationFailureState>(),
    ],
  );

  blocTest<SpawnCubit, SpawnState>(
    'spawns with the chosen project, agent and mode',
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
      expect(params.mode, 'chat');
    },
  );

  blocTest<SpawnCubit, SpawnState>(
    'flags a chat-preflight refusal so the screen can offer Terminal UI',
    build: () {
      when(() => repository.getAgents())
          .thenAnswer((_) async => Result.success(GlobalResponse(data: _catalog)));
      when(() => repository.getSettings()).thenAnswer(
        (_) async => Result.success(
          GlobalResponse(data: const OperatorSettingsModel(chatHarnesses: ['claude-code'])),
        ),
      );
      when(() => repository.spawn(any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(
            error: 'x',
            message: 'no chat driver',
            apiStatus: 'CHAT_DRIVER_UNAVAILABLE',
          ),
        ),
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
    verify: (cubit) => expect(
      (cubit.state as SpawnFailureState).chatUnavailable,
      isTrue,
    ),
  );
}
