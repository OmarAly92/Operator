import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/spawn/data/data_source/spawn_remote_data_source.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';

class _MockSpawnRemoteDataSource extends Mock implements SpawnRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

void main() {
  late _MockSpawnRemoteDataSource dataSource;
  late _MockNetworkStatus network;
  late SpawnRepositoryImp repository;

  setUpAll(() {
    registerFallbackValue(const SpawnSessionParams(projectId: 'p'));
  });

  setUp(() {
    dataSource = _MockSpawnRemoteDataSource();
    network = _MockNetworkStatus();
    repository = SpawnRepositoryImp(dataSource, network);
  });

  group('getAgents', () {
    test('fails fast with noNetwork when the daemon is unreachable', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      final result = await repository.getAgents();

      expect(result.isFailure, isTrue);
      verifyNever(() => dataSource.getAgents());
    });

    test('returns the agent catalog on success', () async {
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(() => dataSource.getAgents()).thenAnswer(
        (_) async => const GlobalResponse<AgentCatalog>(
          data: AgentCatalog(supported: [AgentInfo(id: 'codex', label: 'Codex')]),
        ),
      );

      final result = await repository.getAgents();

      expect(result.isSuccess, isTrue);
      result.when(
        onSuccess: (r) => expect(r.data!.supported.single.id, 'codex'),
        onFailure: (_) => fail('expected success'),
      );
    });

    test('propagates a Failure', () async {
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(() => dataSource.getAgents()).thenThrow(ServerFailure.noNetwork());

      final result = await repository.getAgents();

      expect(result.isFailure, isTrue);
    });
  });

  group('refreshAgents', () {
    test('fails fast with noNetwork when the daemon is unreachable', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      final result = await repository.refreshAgents();

      expect(result.isFailure, isTrue);
      verifyNever(() => dataSource.refreshAgents());
    });

    test('returns the refreshed agent catalog on success', () async {
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(() => dataSource.refreshAgents()).thenAnswer(
        (_) async => const GlobalResponse<AgentCatalog>(
          data: AgentCatalog(installed: [AgentInfo(id: 'codex', label: 'Codex')]),
        ),
      );

      final result = await repository.refreshAgents();

      expect(result.isSuccess, isTrue);
      result.when(
        onSuccess: (r) => expect(r.data!.installed.single.id, 'codex'),
        onFailure: (_) => fail('expected success'),
      );
    });

    test('propagates a Failure', () async {
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(() => dataSource.refreshAgents()).thenThrow(ServerFailure.noNetwork());

      final result = await repository.refreshAgents();

      expect(result.isFailure, isTrue);
    });
  });

  group('spawn', () {
    const params = SpawnSessionParams(projectId: 'p');

    test('fails fast with noNetwork when the daemon is unreachable', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      final result = await repository.spawn(params);

      expect(result.isFailure, isTrue);
      verifyNever(() => dataSource.spawn(any()));
    });

    test('returns the spawned session on success', () async {
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(() => dataSource.spawn(params)).thenAnswer(
        (_) async => const GlobalResponse<SessionModel>(
          data: SessionModel(id: 's1', projectId: 'p'),
        ),
      );

      final result = await repository.spawn(params);

      expect(result.isSuccess, isTrue);
      result.when(
        onSuccess: (r) => expect(r.data!.id, 's1'),
        onFailure: (_) => fail('expected success'),
      );
    });

    test('propagates a Failure', () async {
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(() => dataSource.spawn(params)).thenThrow(ServerFailure.noNetwork());

      final result = await repository.spawn(params);

      expect(result.isFailure, isTrue);
    });
  });
}
