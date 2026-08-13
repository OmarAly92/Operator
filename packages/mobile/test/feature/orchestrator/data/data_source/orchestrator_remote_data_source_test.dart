import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/orchestrator/data/data_source/orchestrator_remote_data_source.dart';
import 'package:operator_mobile/feature/orchestrator/data/model/params/launch_orchestrator_params.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

void main() {
  late _MockApiConsumer apiConsumer;
  late OrchestratorRemoteDataSource dataSource;

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = OrchestratorRemoteDataSourceImp(apiConsumer);
  });

  test('posts the project, clean flag and mode', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/'),
        data: {'orchestrator': {'id': 'o1', 'projectId': 'p', 'mode': 'chat'}},
      ),
    );

    await dataSource.launch(const LaunchOrchestratorParams(projectId: 'p', clean: true, mode: 'chat'));

    final captured = verify(
      () => apiConsumer.post(EndPoints.orchestrators, body: captureAny(named: 'body')),
    ).captured.single as Map<String, dynamic>;
    expect(captured, {'projectId': 'p', 'clean': true, 'mode': 'chat'});
  });

  test('reports the fresh orchestrator as live', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/'),
        data: {'orchestrator': {'id': 'o1', 'projectId': 'p', 'isTerminated': true}},
      ),
    );

    final link = (await dataSource.launch(
      const LaunchOrchestratorParams(projectId: 'p', clean: false, mode: 'chat'),
    )).data!;

    expect(link.id, 'o1');
    expect(link.hasRuntime, isTrue);
    expect(link.isTerminal, isFalse);
  });
}
