import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/orchestrator/data/data_source/orchestrator_remote_data_source.dart';
import 'package:operator_mobile/feature/orchestrator/data/model/params/launch_orchestrator_params.dart';
import 'package:operator_mobile/feature/orchestrator/data/repository/orchestrator_repository.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';

class _MockOrchestratorRemoteDataSource extends Mock implements OrchestratorRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

void main() {
  late _MockOrchestratorRemoteDataSource dataSource;
  late _MockNetworkStatus network;
  late OrchestratorRepositoryImp repository;

  const params = LaunchOrchestratorParams(projectId: 'p', clean: false);

  setUpAll(() => registerFallbackValue(params));

  setUp(() {
    dataSource = _MockOrchestratorRemoteDataSource();
    network = _MockNetworkStatus();
    repository = OrchestratorRepositoryImp(dataSource, network);
  });

  group('launch', () {
    test('fails fast with noNetwork when the daemon is unreachable', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      final result = await repository.launch(params);

      expect(result.isFailure, isTrue);
      verifyNever(() => dataSource.launch(any()));
    });

    test('returns the launched orchestrator on success', () async {
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(() => dataSource.launch(params)).thenAnswer(
        (_) async => const GlobalResponse<OrchestratorModel>(data: OrchestratorModel(id: 'o1')),
      );

      final result = await repository.launch(params);

      expect(result.isSuccess, isTrue);
      result.when(
        onSuccess: (r) => expect(r.data!.id, 'o1'),
        onFailure: (_) => fail('expected success'),
      );
      verify(() => dataSource.launch(params)).called(1);
    });

    test('propagates a Failure', () async {
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(() => dataSource.launch(params)).thenThrow(ServerFailure.noNetwork());

      final result = await repository.launch(params);

      expect(result.isFailure, isTrue);
      verify(() => dataSource.launch(params)).called(1);
    });
  });
}
