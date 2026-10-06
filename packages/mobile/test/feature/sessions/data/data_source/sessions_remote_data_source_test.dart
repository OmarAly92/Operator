import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';

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
    test('awaits /sessions alone before fanning out, and never calls /orchestrators', () async {
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

      expect(calls.first, EndPoints.sessions);
      expect(calls, isNot(contains('/api/v1/orchestrators')));
      expect(calls.length, 3);
      expect(calls.sublist(1).toSet(), {EndPoints.projects, EndPoints.claudeAccounts});
    });

    test('maps claude account ids to their labels and survives a failed accounts read', () async {
      when(() => apiConsumer.get(EndPoints.sessions)).thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.projects)).thenAnswer((_) async => jsonResponse({'projects': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.claudeAccounts)).thenAnswer(
        (_) async => jsonResponse({
          'accounts': [
            {'id': 'default', 'label': 'Default'},
            {'id': 'personal', 'label': 'Personal'},
          ],
        }),
      );

      final board = BoardSnapshot.fromPayload(await dataSource.getBoard());
      expect(board.accountLabels, {'default': 'Default', 'personal': 'Personal'});

      when(() => apiConsumer.get(EndPoints.claudeAccounts)).thenThrow(Exception('older daemon'));
      final degraded = BoardSnapshot.fromPayload(await dataSource.getBoard());
      expect(degraded.accountLabels, isEmpty);
    });

    test('degrades to no projects rather than failing the whole board', () async {
      when(() => apiConsumer.get(EndPoints.sessions))
          .thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.projects)).thenAnswer((_) async => throw Exception('404'));

      final board = BoardSnapshot.fromPayload(await dataSource.getBoard());
      expect(board.projects, isEmpty);
    });

    test('returns each body exactly as the daemon sent it', () async {
      when(() => apiConsumer.get(EndPoints.sessions)).thenAnswer((_) async => jsonResponse({'sessions': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.projects)).thenAnswer((_) async => jsonResponse({'projects': <dynamic>[]}));
      when(() => apiConsumer.get(EndPoints.claudeAccounts)).thenThrow(Exception('older daemon'));

      final payload = await dataSource.getBoard();

      expect(payload.sessions, {'sessions': <dynamic>[]});
      expect(payload.projects, {'projects': <dynamic>[]});
      expect(payload.accounts, isNull);
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
