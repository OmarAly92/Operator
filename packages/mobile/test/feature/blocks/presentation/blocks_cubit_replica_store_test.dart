import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_local_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_tasks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/background_tasks_repository.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';

class _MockMux extends Mock implements MuxClient {}

class _MockRemote extends Mock implements BlocksRemoteDataSource {}

class _MockTasks extends Mock implements BackgroundTasksRepository {}

class _OnlineNetwork implements NetworkStatus {
  @override
  Future<bool> get isConnected async => true;
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

Map<String, dynamic> _stop(int seq) => {'seq': seq, 'sessionId': 's-1', 'kind': 'stop', 'text': 'line $seq'};

Map<String, dynamic> _page(Iterable<int> seqs) => {
  'blocks': [for (final seq in seqs) _stop(seq)],
};

void main() {
  late AppDatabase db;
  late BlocksLocalDataSourceImp local;
  late _Config config;
  late _MockMux mux;
  late _MockTasks tasks;
  late StreamController<BlockEventEnvelope> events;
  late StreamController<MuxStatus> statuses;

  setUpAll(() {
    registerFallbackValue(const GetSessionBlocksParams());
    registerFallbackValue(const GetSessionTasksParams(sessionId: ''));
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    local = BlocksLocalDataSourceImp(db.replicaBlockEventDao);
    config = _Config();
    mux = _MockMux();
    tasks = _MockTasks();
    events = StreamController<BlockEventEnvelope>.broadcast();
    statuses = StreamController<MuxStatus>.broadcast();
    when(() => mux.blockEvents).thenAnswer((_) => events.stream);
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.subscribeBlocks(any())).thenReturn(null);
    when(() => mux.unsubscribeBlocks(any())).thenReturn(null);
    when(() => tasks.getTasks(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'nf', statusCode: 404)),
    );
    await local.writeHistory('a', 's-1', [for (var seq = 1; seq <= 100; seq++) _stop(seq)]);
  });

  tearDown(() async {
    await events.close();
    await statuses.close();
    await db.close();
  });

  BlocksCubit open(BlocksRemoteDataSource remote) => BlocksCubit(
    mux,
    BlocksRepositoryImp(remote, _OnlineNetwork(), local, config),
    const BlocksScope(sessionId: 's-1', harness: 'claude-code'),
    tasks: tasks,
  );

  Future<int?> nextOpenAnchor() async {
    final remote = _MockRemote();
    when(() => remote.getSessionBlocks(any(), any())).thenAnswer((_) async => _page(const []));
    final cubit = open(remote);
    await pumpEventQueue();
    final asked = verify(() => remote.getSessionBlocks('s-1', captureAny())).captured.first as GetSessionBlocksParams;
    await cubit.close();
    return asked.afterSeq;
  }

  test('a live event during the first fetch is not stored when the app dies before the fetch lands', () async {
    final remote = _MockRemote();
    when(() => remote.getSessionBlocks(any(), any())).thenAnswer((_) => Completer<Map<String, dynamic>>().future);
    final cubit = open(remote);
    await pumpEventQueue();

    events.add(BlockEventEnvelope('s-1', _stop(150)));
    await pumpEventQueue();
    await cubit.close();

    expect(await nextOpenAnchor(), 100);
  });

  test('a live event after a failed first fetch is not stored', () async {
    final remote = _MockRemote();
    when(() => remote.getSessionBlocks(any(), any())).thenThrow(
      ServerFailure(error: 'down', message: 'down', statusCode: 503),
    );
    final cubit = open(remote);
    await pumpEventQueue();

    events.add(BlockEventEnvelope('s-1', _stop(150)));
    await pumpEventQueue();
    await cubit.close();

    expect(await nextOpenAnchor(), 100);
  });

  test('a live event during the gap-filling fetch after a reconnect is not stored', () async {
    final remote = _MockRemote();
    final gap = Completer<Map<String, dynamic>>();
    var calls = 0;
    when(() => remote.getSessionBlocks(any(), any())).thenAnswer((_) {
      calls++;
      return calls == 1 ? Future.value(_page([for (var seq = 101; seq <= 120; seq++) seq])) : gap.future;
    });
    final cubit = open(remote);
    await pumpEventQueue();
    events.add(BlockEventEnvelope('s-1', _stop(121)));
    await pumpEventQueue();

    statuses.add(MuxStatus.closed);
    statuses.add(MuxStatus.open);
    await pumpEventQueue();
    events.add(BlockEventEnvelope('s-1', _stop(150)));
    await pumpEventQueue();
    await cubit.close();

    expect(await nextOpenAnchor(), 121);
  });

  test('a live event that lands during a fetch that succeeds is stored with it', () async {
    final remote = _MockRemote();
    final gate = Completer<Map<String, dynamic>>();
    when(() => remote.getSessionBlocks(any(), any())).thenAnswer((_) => gate.future);
    final cubit = open(remote);
    await pumpEventQueue();

    events.add(BlockEventEnvelope('s-1', _stop(150)));
    await pumpEventQueue();
    gate.complete(_page([for (var seq = 101; seq <= 149; seq++) seq]));
    await pumpEventQueue();
    await cubit.close();

    expect(await nextOpenAnchor(), 150);
    expect((await local.readHistory('a', 's-1')).map((row) => row['seq']), [for (var seq = 1; seq <= 150; seq++) seq]);
  });
}
