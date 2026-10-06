import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_local_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';

class _MockDataSource extends Mock implements BlocksRemoteDataSource {}

class _MockLocal extends Mock implements BlocksLocalDataSource {}

class _OnlineNetwork implements NetworkStatus {
  @override
  Future<bool> get isConnected async => true;
}

class _OfflineNetwork implements NetworkStatus {
  @override
  Future<bool> get isConnected async => false;
}

class _Config implements ServerConfigSource {
  @override
  ServerConfig? current = const ServerConfig(
    host: '10.0.0.5',
    httpPort: '3011',
    secure: false,
    password: 'pw',
    desktopId: 'a',
  );

  @override
  Stream<ServerConfig?> get changes => const Stream.empty();
}

void main() {
  late _MockDataSource source;
  late _MockLocal local;
  late _Config config;

  setUpAll(() {
    registerFallbackValue(const GetSessionBlocksParams());
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    source = _MockDataSource();
    local = _MockLocal();
    config = _Config();
    when(() => local.writeHistory(any(), any(), any())).thenAnswer((_) async {});
    when(() => local.deleteHistory(any(), any())).thenAnswer((_) async {});
  });

  BlocksRepositoryImp online() => BlocksRepositoryImp(source, _OnlineNetwork(), local, config);

  test('the endpoint encodes the session id', () {
    expect(EndPoints.sessionBlocks('a b/c'), '/api/v1/sessions/a%20b%2Fc/blocks');
  });

  test('returns the parsed log', () async {
    when(() => source.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => {
        'blocks': [
          {'seq': 1, 'kind': 'stop'},
        ],
      },
    );

    final result = await online().getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 4));

    expect(result.isSuccess, isTrue);
    expect(result.getOrDefault(const []).single.seq, 1);
    verify(() => source.getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 4))).called(1);
  });

  test('fails without a network instead of calling the daemon', () async {
    final repository = BlocksRepositoryImp(source, _OfflineNetwork(), local, config);

    final result = await repository.getSessionBlocks('s-1', const GetSessionBlocksParams());

    expect(result.isFailure, isTrue);
    verifyNever(() => source.getSessionBlocks(any(), any()));
  });

  test('surfaces a data-source failure as a Result failure', () async {
    when(() => source.getSessionBlocks(any(), any())).thenThrow(
      ServerFailure(error: 'boom', message: 'boom', statusCode: 500),
    );

    final result = await online().getSessionBlocks('s-1', const GetSessionBlocksParams());

    expect(result.isFailure, isTrue);
  });

  test('stores main-conversation rows, not task updates or subagent rows', () async {
    when(() => source.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => {
        'blocks': [
          {'seq': 1, 'kind': 'stop'},
          {'seq': 2, 'kind': 'task_update'},
          {'seq': 3, 'kind': 'stop', 'agentId': 'a1'},
        ],
      },
    );

    await online().getSessionBlocks('s-1', const GetSessionBlocksParams());

    verify(() => local.writeHistory('a', 's-1', [
      {'seq': 1, 'kind': 'stop'},
    ])).called(1);
  });

  test('permission mode rows outlive the trim, so they are never stored', () async {
    when(() => source.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => {
        'blocks': [
          {'seq': 1, 'kind': 'permission_mode', 'text': 'plan'},
          {'seq': 5, 'kind': 'stop'},
        ],
      },
    );

    await online().getSessionBlocks('s-1', const GetSessionBlocksParams());

    verify(() => local.writeHistory('a', 's-1', [
      {'seq': 5, 'kind': 'stop'},
    ])).called(1);
  });

  test('a subagent page is never stored', () async {
    when(() => source.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => {
        'blocks': [
          {'seq': 3, 'kind': 'stop', 'agentId': 'a1'},
        ],
      },
    );

    await online().getSessionBlocks('s-1', const GetSessionBlocksParams(agentId: 'a1'));

    verifyNever(() => local.writeHistory(any(), any(), any()));
  });

  test('an older page fetched by scrolling back is not stored', () async {
    when(() => source.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => {
        'blocks': [
          {'seq': 3, 'kind': 'stop'},
        ],
      },
    );

    final result = await online().getSessionBlocks('s-1', const GetSessionBlocksParams(beforeSeq: 50, limit: 100));

    expect(result.getOrDefault(const []).single.seq, 3);
    verifyNever(() => local.writeHistory(any(), any(), any()));
  });

  test('cachedHistory parses the stored rows through BlockEventModel', () async {
    when(() => local.readHistory('a', 's-1')).thenAnswer(
      (_) async => [
        {'seq': 1, 'kind': 'prompt_submit', 'text': 'hi'},
      ],
    );

    final cached = await online().cachedHistory('s-1');

    expect(cached.single.seq, 1);
    expect(cached.single.text, 'hi');
  });

  test('history that no longer parses is deleted and read as empty', () async {
    when(() => local.readHistory('a', 's-1')).thenAnswer(
      (_) async => [
        {'seq': 'not a number'},
      ],
    );

    expect(await online().cachedHistory('s-1'), isEmpty);
    verify(() => local.deleteHistory('a', 's-1')).called(1);
  });

  test('rememberLive stores one main row and ignores it with no active desktop', () async {
    await online().rememberLive('s-1', {'seq': 9, 'kind': 'stop'});
    verify(() => local.writeHistory('a', 's-1', [
      {'seq': 9, 'kind': 'stop'},
    ])).called(1);

    config.current = null;
    await online().rememberLive('s-1', {'seq': 10, 'kind': 'stop'});
    verifyNever(() => local.writeHistory(any(), 's-1', [
      {'seq': 10, 'kind': 'stop'},
    ]));
  });

  test('a fetch that finishes after a desktop switch is stored under neither desktop', () async {
    final gate = Completer<Map<String, dynamic>>();
    when(() => source.getSessionBlocks(any(), any())).thenAnswer((_) => gate.future);

    final pending = online().getSessionBlocks('s-1', const GetSessionBlocksParams());
    await Future<void>.delayed(Duration.zero);
    config.current = const ServerConfig(
      host: '10.0.0.6',
      httpPort: '3011',
      secure: false,
      password: 'pw',
      desktopId: 'b',
    );
    gate.complete({
      'blocks': [
        {'seq': 1, 'kind': 'stop'},
      ],
    });
    await pending;

    verifyNever(() => local.writeHistory(any(), any(), any()));
  });
}
