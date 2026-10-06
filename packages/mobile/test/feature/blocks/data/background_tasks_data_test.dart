import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/dio_error_handler.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/background_tasks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_tasks_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/stop_session_task_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/background_tasks_repository.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

class _Network implements NetworkStatus {
  _Network(this.online);

  final bool online;

  @override
  Future<bool> get isConnected async => online;
}

Response<dynamic> _ok(Map<String, dynamic> data, {int status = 200}) =>
    Response(requestOptions: RequestOptions(path: ''), data: data, statusCode: status);

ServerFailure<Map<String, dynamic>> _envelope(int status, String code) => handleDioError(
  DioException(
    requestOptions: RequestOptions(path: ''),
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: status,
      data: {'error': 'conflict', 'code': code, 'message': 'task is ambiguous', 'requestId': 'req-9'},
    ),
  ),
);

void main() {
  late _MockApiConsumer api;
  late BackgroundTasksRepositoryImp repository;

  setUpAll(() => registerFallbackValue(Options()));

  setUp(() {
    api = _MockApiConsumer();
    repository = BackgroundTasksRepositoryImp(BackgroundTasksRemoteDataSourceImp(api), _Network(true));
  });

  test('the endpoints encode the session and task ids', () {
    expect(EndPoints.sessionTasks('a b'), '/api/v1/sessions/a%20b/tasks');
    expect(EndPoints.sessionTaskStop('a b', 't/1'), '/api/v1/sessions/a%20b/tasks/t%2F1/stop');
  });

  test('getTasks reads the tasks list from the unwrapped body', () async {
    when(() => api.get(any())).thenAnswer(
      (_) async => _ok({
        'tasks': [
          {'taskId': 'b1', 'kind': 'shell', 'status': 'running', 'canStop': true, 'updatedSeq': 7},
        ],
      }),
    );

    final result = await repository.getTasks(const GetSessionTasksParams(sessionId: 's-1'));

    verify(() => api.get('/api/v1/sessions/s-1/tasks')).called(1);
    final tasks = result.valueOrNull!.data!;
    expect(tasks.single.taskId, 'b1');
    expect(tasks.single.canStop, isTrue);
  });

  test('stopTask posts with no body and parses the task and confirmation', () async {
    when(() => api.post(any(), options: any(named: 'options'))).thenAnswer(
      (_) async => _ok({
        'task': {'taskId': 'b1', 'kind': 'shell', 'status': 'running'},
        'confirmed': false,
      }, status: 202),
    );

    final result = await repository.stopTask(const StopSessionTaskParams(sessionId: 's-1', taskId: 'b1'));

    final options = verify(() => api.post('/api/v1/sessions/s-1/tasks/b1/stop', options: captureAny(named: 'options'))).captured.single as Options;
    expect(options.receiveTimeout, BackgroundTasksRemoteDataSourceImp.stopReceiveTimeout);
    expect(options.receiveTimeout, greaterThan(const Duration(seconds: 40)));
    final body = result.valueOrNull!.data!;
    expect(body.task?.taskId, 'b1');
    expect(body.confirmed, isFalse);
  });

  test('an error envelope keeps its code and requestId', () async {
    when(() => api.post(any(), options: any(named: 'options'))).thenThrow(_envelope(409, 'TASK_AMBIGUOUS'));

    final result = await repository.stopTask(const StopSessionTaskParams(sessionId: 's-1', taskId: 'b1'));

    Failure? failure;
    result.when(onSuccess: (_) {}, onFailure: (error) => failure = error);
    expect(failure?.statusCode, 409);
    expect(failure?.apiStatus, 'TASK_AMBIGUOUS');
    expect((failure?.validationErrors as Map<String, dynamic>)['requestId'], 'req-9');
  });

  test('offline fails without calling the daemon', () async {
    final offline = BackgroundTasksRepositoryImp(BackgroundTasksRemoteDataSourceImp(api), _Network(false));

    final result = await offline.getTasks(const GetSessionTasksParams(sessionId: 's-1'));

    expect(result.isFailure, isTrue);
    verifyNever(() => api.get(any()));
  });
}
