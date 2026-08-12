import 'dart:async';

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
  late _MockApiConsumer apiConsumer;
  late SessionsRemoteDataSourceImp dataSource;

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = SessionsRemoteDataSourceImp(apiConsumer);
  });

  Response<dynamic> jsonResponse(Map<String, dynamic> body) =>
      Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: body);

  group('getBoard', () {
    test('probes /sessions alone before fanning out to the other two', () async {
      final sessionsGate = Completer<Response<dynamic>>();
      final calls = <String>[];

      when(() => apiConsumer.get(any())).thenAnswer((invocation) {
        final path = invocation.positionalArguments.first as String;
        calls.add(path);
        if (path == EndPoints.sessions) return sessionsGate.future;
        return Future.value(jsonResponse({'sessions': <dynamic>[], 'projects': <dynamic>[]}));
      });

      final pending = dataSource.getBoard();
      await Future<void>.delayed(Duration.zero);

      expect(calls, [EndPoints.sessions]);

      sessionsGate.complete(jsonResponse({'sessions': <dynamic>[]}));
      await pending;

      expect(calls.length, 3);
      expect(calls.first, EndPoints.sessions);
      expect(calls.sublist(1).toSet(), {EndPoints.orchestrators, EndPoints.projects});
    });

    test('drops orchestrator-kind rows from the session list', () async {
      when(() => apiConsumer.get(EndPoints.sessions)).thenAnswer(
        (_) async => jsonResponse({
          'sessions': [
            {'id': 'w1', 'projectId': 'p', 'kind': 'worker'},
            {'id': 'o1', 'projectId': 'p', 'kind': 'orchestrator'},
          ],
        }),
      );
      when(() => apiConsumer.get(EndPoints.orchestrators))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.projects))
          .thenAnswer((_) async => jsonResponse({'projects': <dynamic>[]}));

      final board = await dataSource.getBoard();
      expect(board.data!.sessions.map((s) => s.id), ['w1']);
    });

    test('keeps one orchestrator per project, preferring the live one', () async {
      when(() => apiConsumer.get(EndPoints.sessions))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.orchestrators)).thenAnswer(
        (_) async => jsonResponse({
          'sessions': [
            {'id': 'old', 'projectId': 'p', 'isTerminated': true},
            {'id': 'live', 'projectId': 'p'},
          ],
        }),
      );
      when(() => apiConsumer.get(EndPoints.projects))
          .thenAnswer((_) async => jsonResponse({'projects': <dynamic>[]}));

      final board = await dataSource.getBoard();
      expect(board.data!.orchestrators.map((o) => o.id), ['live']);
    });

    test('falls back to the most recent when every orchestrator is terminated', () async {
      when(() => apiConsumer.get(EndPoints.sessions))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.orchestrators)).thenAnswer(
        (_) async => jsonResponse({
          'sessions': [
            {'id': 'older', 'projectId': 'p', 'isTerminated': true},
            {'id': 'newer', 'projectId': 'p', 'isTerminated': true},
          ],
        }),
      );
      when(() => apiConsumer.get(EndPoints.projects))
          .thenAnswer((_) async => jsonResponse({'projects': <dynamic>[]}));

      final board = await dataSource.getBoard();
      expect(board.data!.orchestrators.map((o) => o.id), ['newer']);
    });

    test('labels orchestrators with their project name', () async {
      when(() => apiConsumer.get(EndPoints.sessions))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.orchestrators)).thenAnswer(
        (_) async => jsonResponse({
          'sessions': [{'id': 'o1', 'projectId': 'p'}],
        }),
      );
      when(() => apiConsumer.get(EndPoints.projects)).thenAnswer(
        (_) async => jsonResponse({
          'projects': [{'id': 'p', 'name': 'My App'}],
        }),
      );

      final board = await dataSource.getBoard();
      expect(board.data!.orchestrators.single.projectName, 'My App');
    });

    test('degrades to no projects rather than failing the whole board', () async {
      when(() => apiConsumer.get(EndPoints.sessions))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.orchestrators))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.projects)).thenAnswer((_) async => throw Exception('404'));

      final board = await dataSource.getBoard();
      expect(board.data!.projects, isEmpty);
    });
  });

  test('kill posts to the session kill endpoint', () async {
    when(() => apiConsumer.post(EndPoints.sessionKill('proj-1'))).thenAnswer((_) async => _response(const {}));
    await dataSource.kill('proj-1');
    verify(() => apiConsumer.post(EndPoints.sessionKill('proj-1'))).called(1);
  });

  test('restore posts to the session restore endpoint', () async {
    when(() => apiConsumer.post(EndPoints.sessionRestore('proj-1'))).thenAnswer((_) async => _response(const {}));
    await dataSource.restore('proj-1');
    verify(() => apiConsumer.post(EndPoints.sessionRestore('proj-1'))).called(1);
  });
}
