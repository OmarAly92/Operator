import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/replica/replica_limits.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_tasks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/background_tasks_repository.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';

class _MockMux extends Mock implements MuxClient {}

class _MockRepository extends Mock implements BlocksRepository {}

class _MockTasks extends Mock implements BackgroundTasksRepository {}

Map<String, dynamic> _stop(int seq, {String? agentId}) => {
  'seq': seq,
  'sessionId': 's-1',
  'kind': 'stop',
  'text': 'line $seq',
  'agentId': ?agentId,
};

BlockEventModel _row(int seq) => BlockEventModel.fromJson(_stop(seq));

void main() {
  late _MockMux mux;
  late _MockRepository repository;
  late _MockTasks tasks;
  late StreamController<BlockEventEnvelope> events;
  late StreamController<MuxStatus> statuses;

  setUpAll(() {
    registerFallbackValue(const GetSessionBlocksParams());
    registerFallbackValue(const GetSessionTasksParams(sessionId: ''));
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mux = _MockMux();
    repository = _MockRepository();
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
    when(() => repository.cachedHistory(any())).thenAnswer((_) async => const []);
    when(() => repository.rememberLive(any(), any())).thenAnswer((_) async {});
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success(const <BlockEventModel>[]),
    );
  });

  tearDown(() async {
    await events.close();
    await statuses.close();
  });

  BlocksCubit build({String? agentId}) => BlocksCubit(
    mux,
    repository,
    BlocksScope(sessionId: 's-1', harness: 'claude-code', agentId: agentId),
    tasks: tasks,
  );

  test('draws the cached history before the network answers, then fetches only what came after it', () async {
    final gate = Completer<Result<List<BlockEventModel>, Failure>>();
    when(() => repository.cachedHistory('s-1')).thenAnswer((_) async => [_row(1), _row(2)]);
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer((_) => gate.future);

    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.map((block) => block.id), ['seq-1', 'seq-2']);
    verify(() => repository.getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 2))).called(1);

    gate.complete(Result.success([_row(2), _row(3)]));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.map((block) => block.id), ['seq-1', 'seq-2', 'seq-3']);
    await cubit.close();
  });

  test('a live event that lands before the cache keeps the first fetch anchored to the cached tail', () async {
    final cache = Completer<List<BlockEventModel>>();
    when(() => repository.cachedHistory('s-1')).thenAnswer((_) => cache.future);

    final cubit = build();
    events.add(BlockEventEnvelope('s-1', _stop(150)));
    await Future<void>.delayed(Duration.zero);
    cache.complete([for (var seq = 1; seq <= 100; seq++) _row(seq)]);
    await Future<void>.delayed(Duration.zero);

    verify(() => repository.getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 100))).called(1);
    expect(cubit.blocks.last.id, 'seq-150');
    await cubit.close();
  });

  test('a full cache offers older history from the daemon', () async {
    when(() => repository.cachedHistory('s-1')).thenAnswer(
      (_) async => [for (var seq = 1; seq <= ReplicaLimits.blockEventsPerSession; seq++) _row(seq + 1000)],
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.hasOlder, isTrue);
    await cubit.close();
  });

  test('live main-conversation events are remembered', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    events.add(BlockEventEnvelope('s-1', _stop(7)));
    await Future<void>.delayed(Duration.zero);

    verify(() => repository.rememberLive('s-1', _stop(7))).called(1);
    await cubit.close();
  });

  test('a subagent screen neither reads nor writes the replica', () async {
    final cubit = build(agentId: 'a1');
    await Future<void>.delayed(Duration.zero);

    events.add(BlockEventEnvelope('s-1', _stop(7, agentId: 'a1')));
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => repository.cachedHistory(any()));
    verifyNever(() => repository.rememberLive(any(), any()));
    await cubit.close();
  });

  test('a live copy that lands before the cache is not overwritten by the cached one', () async {
    final cache = Completer<List<BlockEventModel>>();
    when(() => repository.cachedHistory('s-1')).thenAnswer((_) => cache.future);

    final cubit = build();
    events.add(BlockEventEnvelope('s-1', {..._stop(5), 'text': 'new'}));
    await Future<void>.delayed(Duration.zero);
    cache.complete([BlockEventModel.fromJson({..._stop(5), 'text': 'old'})]);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.single.id, 'seq-5');
    expect(cubit.blocks.single.body, 'new');
    await cubit.close();
  });

  test('after a failed first fetch the retry still asks from the cached tail', () async {
    when(() => repository.cachedHistory('s-1')).thenAnswer((_) async => [for (var seq = 1; seq <= 100; seq++) _row(seq)]);
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: 503)),
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    events.add(BlockEventEnvelope('s-1', _stop(150)));
    await Future<void>.delayed(Duration.zero);
    statuses.add(MuxStatus.open);
    await Future<void>.delayed(Duration.zero);

    final asked = verify(() => repository.getSessionBlocks('s-1', captureAny())).captured.cast<GetSessionBlocksParams>();
    expect(asked.map((params) => params.afterSeq), [100, 100]);
    await cubit.close();
  });
}
