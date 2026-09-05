import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/session_control_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_answer_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_decision_params.dart';

class MockApiConsumer extends Mock implements ApiConsumer {}

void main() {
  late MockApiConsumer api;
  late SessionControlRemoteDataSourceImp dataSource;

  setUp(() {
    api = MockApiConsumer();
    dataSource = SessionControlRemoteDataSourceImp(api);
  });

  test('sendCommand posts to the session command endpoint', () async {
    when(() => api.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: {'state': 'sent'},
            ));

    final result = await dataSource.sendCommand('s1', const SessionCommandParams(command: 'stop'));

    verify(() => api.post('/api/v1/sessions/s1/command', body: {'command': 'stop'})).called(1);
    expect(result.data?.state, 'sent');
  });

  test('sendCommand carries the model label and parses the offered rows', () async {
    when(() => api.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: {'state': 'sent', 'models': ['sonnet', 'opus']},
            ));

    final result = await dataSource.sendCommand(
      's1',
      const SessionCommandParams(command: 'model', model: 'opus'),
    );

    verify(() => api.post('/api/v1/sessions/s1/command', body: {'command': 'model', 'model': 'opus'})).called(1);
    expect(result.data?.models, ['sonnet', 'opus']);
  });

  test('decide posts the request id and behavior', () async {
    when(() => api.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: {'state': 'sent'},
            ));

    await dataSource.decide('s1', const SessionDecisionParams(requestId: 'i1', behavior: 'allow'));

    verify(() => api.post('/api/v1/sessions/s1/decision',
        body: {'requestId': 'i1', 'behavior': 'allow'})).called(1);
  });

  test('answer posts the nested selections as option label text, not row indices', () async {
    when(() => api.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: {'state': 'sent'},
            ));

    await dataSource.answer(
      's1',
      const SessionAnswerParams(requestId: 'q1', selections: [
        ['Red'],
        ['Green', 'Type something.'],
      ]),
    );

    verify(() => api.post('/api/v1/sessions/s1/answer', body: {
      'requestId': 'q1',
      'selections': [
        ['Red'],
        ['Green', 'Type something.'],
      ],
    })).called(1);
  });

  test('getInteractions parses the reconnect list', () async {
    when(() => api.get(any())).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          data: {
            'interactions': [
              {'id': 'i1', 'kind': 'permission', 'toolName': 'Bash', 'toolInput': '{}'}
            ]
          },
        ));

    final result = await dataSource.getInteractions('s1');

    verify(() => api.get('/api/v1/sessions/s1/interactions')).called(1);
    expect(result.data?.single.id, 'i1');
    expect(result.data?.single.kind, 'permission');
  });

  test('a missing field parses to null rather than throwing', () async {
    when(() => api.get(any())).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          data: {'interactions': [<String, dynamic>{}]},
        ));

    final result = await dataSource.getInteractions('s1');

    expect(result.data?.single.id, isNull);
    expect(result.data?.single.toolName, isNull);
  });
}
