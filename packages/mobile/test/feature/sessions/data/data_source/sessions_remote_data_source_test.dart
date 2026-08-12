import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

Response<dynamic> _response(Map<String, dynamic> body) =>
    Response<dynamic>(requestOptions: RequestOptions(path: EndPoints.sessions), statusCode: 200, data: body);

void main() {
  late _MockApiConsumer api;
  late SessionsRemoteDataSourceImp dataSource;

  setUp(() {
    api = _MockApiConsumer();
    dataSource = SessionsRemoteDataSourceImp(api);
  });

  test('parses the bare sessions payload and drops orchestrator-kind sessions', () async {
    when(() => api.get(EndPoints.sessions)).thenAnswer(
      (_) async => _response({
        'sessions': [
          {'id': 'proj-1', 'kind': 'worker', 'status': 'working'},
          {'id': 'proj-conductor', 'kind': 'orchestrator', 'status': 'working'},
        ],
      }),
    );

    final result = await dataSource.getSessions();

    expect(result.data, hasLength(1));
    expect(result.data!.single.id, 'proj-1');
  });

  test('kill posts to the session kill endpoint', () async {
    when(() => api.post(EndPoints.sessionKill('proj-1'))).thenAnswer((_) async => _response(const {}));
    await dataSource.kill('proj-1');
    verify(() => api.post(EndPoints.sessionKill('proj-1'))).called(1);
  });

  test('restore posts to the session restore endpoint', () async {
    when(() => api.post(EndPoints.sessionRestore('proj-1'))).thenAnswer((_) async => _response(const {}));
    await dataSource.restore('proj-1');
    verify(() => api.post(EndPoints.sessionRestore('proj-1'))).called(1);
  });
}
