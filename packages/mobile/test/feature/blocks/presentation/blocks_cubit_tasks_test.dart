import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/blocks/data/model/background_task_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_tasks_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/stop_session_task_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/stop_session_task_result_model.dart';
import 'package:operator_mobile/feature/blocks/data/repository/background_tasks_repository.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/background_tasks.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';

class _MockMux extends Mock implements MuxClient {}

class _MockBlocksRepository extends Mock implements BlocksRepository {}

class _MockTasksRepository extends Mock implements BackgroundTasksRepository {}

Map<String, dynamic> _update(int seq, String taskId, String status, {String kind = 'shell', String? agentId, String? description}) => {
  'seq': seq,
  'sessionId': 's-1',
  'kind': 'task_update',
  'source': 'transcript',
  'sourceId': taskId,
  'agentId': ?agentId,
  'detail': jsonEncode({'taskId': taskId, 'kind': kind, 'status': status, 'description': ?description}),
};

FutureResult<GlobalResponse<List<BackgroundTaskModel>>> _seed(List<BackgroundTaskModel> tasks) async =>
    Result.success(GlobalResponse(data: tasks));

void main() {
  late _MockMux mux;
  late _MockBlocksRepository blocks;
  late _MockTasksRepository tasks;
  late StreamController<BlockEventEnvelope> events;
  late StreamController<MuxStatus> statuses;
  late StreamController<List<SessionPatch>> patches;

  setUpAll(() {
    registerFallbackValue(const GetSessionBlocksParams());
    registerFallbackValue(const GetSessionTasksParams(sessionId: ''));
    registerFallbackValue(const StopSessionTaskParams(sessionId: '', taskId: ''));
  });

  setUp(() {
    mux = _MockMux();
    blocks = _MockBlocksRepository();
    tasks = _MockTasksRepository();
    events = StreamController<BlockEventEnvelope>.broadcast();
    statuses = StreamController<MuxStatus>.broadcast();
    patches = StreamController<List<SessionPatch>>.broadcast();
    when(() => mux.blockEvents).thenAnswer((_) => events.stream);
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    when(() => mux.sessionPatches).thenAnswer((_) => patches.stream);
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => mux.subscribeBlocks(any())).thenReturn(null);
    when(() => mux.unsubscribeBlocks(any())).thenReturn(null);
    when(() => blocks.getSessionBlocks(any(), any())).thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
    when(() => tasks.getTasks(any())).thenAnswer((_) => _seed(const []));
  });

  tearDown(() async {
    await events.close();
    await statuses.close();
    await patches.close();
  });

  BlocksCubit build({String? agentId}) => BlocksCubit(
    mux,
    blocks,
    BlocksScope(sessionId: 's-1', harness: 'claude-code', agentId: agentId),
    tasks: tasks,
  );

  Future<void> settle() async {
    for (var tick = 0; tick < 5; tick++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('seeds the feed from GET /tasks when the chat opens', () async {
    when(() => tasks.getTasks(any())).thenAnswer(
      (_) => _seed(const [BackgroundTaskModel(taskId: 'b1', kind: 'shell', status: 'running', canStop: true, updatedSeq: 4)]),
    );
    final cubit = build();
    await settle();

    verify(() => tasks.getTasks(const GetSessionTasksParams(sessionId: 's-1'))).called(1);
    expect(cubit.taskFeed['b1']?.canStop, isTrue);
    await cubit.close();
  });

  test('folds live task_update events over the seed, ignoring stale and duplicate seqs', () async {
    when(() => tasks.getTasks(any())).thenAnswer(
      (_) => _seed(const [
        BackgroundTaskModel(taskId: 'b1', kind: 'shell', status: 'running', description: 'Sleep', canStop: true, updatedSeq: 10),
      ]),
    );
    final cubit = build();
    await settle();

    events.add(BlockEventEnvelope('s-1', _update(8, 'b1', 'completed')));
    await settle();
    expect(cubit.taskFeed['b1']?.status, 'running');

    events.add(BlockEventEnvelope('s-1', _update(12, 'b1', 'killed')));
    events.add(BlockEventEnvelope('s-1', _update(12, 'b1', 'killed')));
    await settle();
    expect(cubit.taskFeed['b1']?.status, 'killed');
    expect(cubit.taskFeed['b1']?.description, 'Sleep');
    expect(cubit.taskFeed['b1']?.updatedSeq, 12);
    await cubit.close();
  });

  test('task_update events never become transcript blocks', () async {
    final cubit = build();
    await settle();

    events.add(BlockEventEnvelope('s-1', _update(3, 'b1', 'running')));
    await settle();

    expect(cubit.blocks, isEmpty);
    expect(cubit.taskFeed.keys, ['b1']);
    await cubit.close();
  });

  test('a subagent-launched task joins the main feed and is not summarised as agent activity', () async {
    final cubit = build();
    await settle();

    events.add(BlockEventEnvelope('s-1', _update(5, 'b9', 'running', agentId: 'sub-1')));
    await settle();

    expect(cubit.taskFeed['b9']?.agentId, 'sub-1');
    expect(cubit.subagentSummaries, isEmpty);
    await cubit.close();
  });

  test('a live launch whose canStop is unknown refetches the list to learn it', () async {
    final cubit = build();
    await settle();
    when(() => tasks.getTasks(any())).thenAnswer(
      (_) => _seed(const [BackgroundTaskModel(taskId: 'b2', kind: 'shell', status: 'running', canStop: true, updatedSeq: 6)]),
    );

    events.add(BlockEventEnvelope('s-1', _update(6, 'b2', 'running')));
    await settle();

    verify(() => tasks.getTasks(any())).called(2);
    expect(cubit.taskFeed['b2']?.canStop, isTrue);
    await cubit.close();
  });

  test('reseeds after a reconnect', () async {
    final cubit = build();
    await settle();

    statuses.add(MuxStatus.open);
    await settle();

    verify(() => tasks.getTasks(any())).called(2);
    await cubit.close();
  });

  test('a 404 from an older daemon falls back to subagents and stops asking', () async {
    when(() => tasks.getTasks(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'nf', message: 'not found', statusCode: 404)),
    );
    when(() => blocks.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([
        BlockEventModel.fromJson(const {'seq': 1, 'sessionId': 's-1', 'kind': 'prompt_submit', 'text': 'go'}),
        BlockEventModel.fromJson(const {
          'seq': 2,
          'sessionId': 's-1',
          'kind': 'tool_start',
          'toolName': 'Agent',
          'sourceId': 'toolu_1',
          'toolUseId': 'toolu_1',
          'toolInput': '{"description":"Scout"}',
        }),
      ]),
    );
    final cubit = build();
    await settle();

    expect(cubit.error, isNull);
    expect(cubit.taskFeed, isEmpty);
    expect(
      backgroundTasksOf(cubit.blocks, cubit.subagentSummaries, feed: cubit.taskFeed.values),
      backgroundTasksOf(cubit.blocks, cubit.subagentSummaries),
    );
    expect(backgroundTasksOf(cubit.blocks, cubit.subagentSummaries).single.title, 'Scout');

    statuses.add(MuxStatus.open);
    await settle();
    verify(() => tasks.getTasks(any())).called(1);
    await cubit.close();
  });

  test('a subagent screen never asks for the task list', () async {
    final cubit = build(agentId: 'sub-1');
    await settle();

    verifyNever(() => tasks.getTasks(any()));
    await cubit.close();
  });

  test('stopTask posts the stop and folds the returned task', () async {
    when(() => tasks.getTasks(any())).thenAnswer(
      (_) => _seed(const [BackgroundTaskModel(taskId: 'a1', kind: 'agent', status: 'running', canStop: true, updatedSeq: 3)]),
    );
    when(() => tasks.stopTask(any())).thenAnswer(
      (_) async => Result.success(
        const GlobalResponse(
          data: StopSessionTaskResultModel(
            task: BackgroundTaskModel(taskId: 'a1', kind: 'agent', status: 'killed', updatedSeq: 9),
            confirmed: true,
          ),
        ),
      ),
    );
    final cubit = build();
    await settle();

    final failure = await cubit.stopTask('a1');

    expect(failure, isNull);
    verify(() => tasks.stopTask(const StopSessionTaskParams(sessionId: 's-1', taskId: 'a1'))).called(1);
    expect(cubit.taskFeed['a1']?.status, 'killed');
    await cubit.close();
  });

  test('stopTask hands back the failure with its code', () async {
    when(() => tasks.stopTask(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', statusCode: 409, apiStatus: 'TASK_AMBIGUOUS')),
    );
    final cubit = build();
    await settle();

    final failure = await cubit.stopTask('b1');

    expect(failure?.apiStatus, 'TASK_AMBIGUOUS');
    await cubit.close();
  });

  test('a 501 from a daemon without the task service turns the feed off too', () async {
    when(() => tasks.getTasks(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'ni', message: 'not wired', statusCode: 501)),
    );
    final cubit = build();
    await settle();

    statuses.add(MuxStatus.open);
    await settle();
    await cubit.reseedTasks();

    verify(() => tasks.getTasks(any())).called(1);
    expect(cubit.taskFeed, isEmpty);
    await cubit.close();
  });

  test('reseedTasks fetches the list again', () async {
    final cubit = build();
    await settle();

    await cubit.reseedTasks();

    verify(() => tasks.getTasks(any())).called(2);
    await cubit.close();
  });

  test('task events stay out of the block window but still advance the refresh cursor', () async {
    when(() => blocks.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([
        for (var seq = 1; seq <= kBlockWindow; seq++)
          BlockEventModel.fromJson({'seq': seq, 'sessionId': 's-1', 'kind': 'stop', 'text': 'line $seq'}),
      ]),
    );
    final cubit = build();
    await settle();
    final before = cubit.blocks.length;
    final first = cubit.blocks.first.id;

    for (var seq = kBlockWindow + 1; seq <= kBlockWindow + 500; seq++) {
      events.add(BlockEventEnvelope('s-1', _update(seq, 'b$seq', 'completed')));
    }
    await settle();

    expect(cubit.blocks.length, before);
    expect(cubit.blocks.first.id, first);
    expect(cubit.hasOlder, isFalse);
    expect(cubit.taskFeed, hasLength(500));

    when(() => blocks.getSessionBlocks(any(), any())).thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
    statuses.add(MuxStatus.open);
    await settle();
    final params = verify(() => blocks.getSessionBlocks('s-1', captureAny())).captured.last as GetSessionBlocksParams;
    expect(params.afterSeq, kBlockWindow + 500);
    await cubit.close();
  });

  test('task events from history are dropped from the window too', () async {
    when(() => blocks.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([
        BlockEventModel.fromJson(const {'seq': 1, 'sessionId': 's-1', 'kind': 'stop', 'text': 'done'}),
        BlockEventModel.fromJson(_update(2, 'b1', 'running')),
      ]),
    );
    final cubit = build();
    await settle();

    expect(cubit.blocks.map((block) => block.id), ['seq-1']);
    await cubit.close();
  });
}
