import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/spawn/data/data_source/spawn_remote_data_source.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

void main() {
  late _MockApiConsumer apiConsumer;
  late SpawnRemoteDataSource dataSource;

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = SpawnRemoteDataSourceImp(apiConsumer);
  });

  Response<dynamic> jsonResponse(Map<String, dynamic> body) =>
      Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: body);

  test('parses the three agent lists', () async {
    when(() => apiConsumer.get(EndPoints.agents)).thenAnswer(
      (_) async => jsonResponse({
        'supported': [{'id': 'codex', 'label': 'Codex'}],
        'installed': [{'id': 'codex', 'label': 'Codex', 'authStatus': 'authorized'}],
        'authorized': [{'id': 'codex', 'label': 'Codex'}],
      }),
    );

    final catalog = (await dataSource.getAgents()).data!;
    expect(catalog.supported.single.label, 'Codex');
    expect(catalog.installed.single.authStatus, 'authorized');
    expect(catalog.authorized.single.id, 'codex');
  });

  test('tolerates a daemon that omits the lists entirely', () async {
    when(() => apiConsumer.get(EndPoints.agents)).thenAnswer((_) async => jsonResponse({}));

    final catalog = (await dataSource.getAgents()).data!;
    expect(catalog.supported, isEmpty);
    expect(catalog.installed, isEmpty);
    expect(catalog.authorized, isEmpty);
  });

  test('refreshes the catalog with a POST', () async {
    when(() => apiConsumer.post(EndPoints.agentsRefresh))
        .thenAnswer((_) async => jsonResponse({'supported': <dynamic>[]}));

    await dataSource.refreshAgents();

    verify(() => apiConsumer.post(EndPoints.agentsRefresh)).called(1);
  });

  test('defaults the session mode to chat and keeps only string harnesses', () async {
    when(() => apiConsumer.get(EndPoints.settings)).thenAnswer(
      (_) async => jsonResponse({'chatHarnesses': ['claude-code', 7, null, 'codex']}),
    );

    final settings = (await dataSource.getSettings()).data!;
    expect(settings.defaultSessionMode, 'chat');
    expect(settings.chatHarnesses, ['claude-code', 'codex']);
  });

  test('honours an explicit tui default', () async {
    when(() => apiConsumer.get(EndPoints.settings))
        .thenAnswer((_) async => jsonResponse({'defaultSessionMode': 'tui'}));

    expect((await dataSource.getSettings()).data!.defaultSessionMode, 'tui');
  });

  test('omits the optional spawn fields it was not given', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => jsonResponse({'session': {'id': 's1', 'projectId': 'p'}}));

    await dataSource.spawn(const SpawnSessionParams(projectId: 'p', mode: 'chat'));

    final body = verify(() => apiConsumer.post(EndPoints.sessions, body: captureAny(named: 'body')))
        .captured.single as Map<String, dynamic>;
    expect(body, {'projectId': 'p', 'mode': 'chat', 'kind': 'worker'});
  });

  test('sends every field it was given', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => jsonResponse({'session': {'id': 's1', 'projectId': 'p'}}));

    await dataSource.spawn(const SpawnSessionParams(
      projectId: 'p',
      prompt: 'fix the test',
      issueId: 'flaky login',
      harness: 'codex',
      mode: 'tui',
    ));

    final body = verify(() => apiConsumer.post(EndPoints.sessions, body: captureAny(named: 'body')))
        .captured.single as Map<String, dynamic>;
    expect(body, {
      'projectId': 'p',
      'prompt': 'fix the test',
      'issueId': 'flaky login',
      'harness': 'codex',
      'mode': 'tui',
      'kind': 'worker',
    });
  });

  test('reads the spawned session out of either envelope', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => jsonResponse({'session': {'id': 's1', 'projectId': 'p'}}));
    expect((await dataSource.spawn(const SpawnSessionParams(projectId: 'p', mode: 'chat'))).data!.id, 's1');

    when(() => apiConsumer.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => jsonResponse({'id': 's2', 'projectId': 'p'}));
    expect((await dataSource.spawn(const SpawnSessionParams(projectId: 'p', mode: 'chat'))).data!.id, 's2');
  });
}
