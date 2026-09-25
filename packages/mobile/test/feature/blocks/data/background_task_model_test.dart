import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/background_task_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/stop_session_task_result_model.dart';

void main() {
  const view = {
    'taskId': 'a70676e4ddf0ba990',
    'kind': 'agent',
    'status': 'running',
    'toolUseId': 'toolu_01',
    'description': 'blocker three',
    'command': 'sleep 900',
    'summary': 'Task stopped',
    'exitCode': 143,
    'durationMs': 7412,
    'outputFile': '/tmp/tasks/a7.output',
    'startedAt': '2026-09-25T01:27:01.531Z',
    'endedAt': '2026-09-25T01:28:01.531Z',
    'agentId': 'sub-1',
    'canStop': true,
    'updatedSeq': 1234,
  };

  test('parses every field of a SessionTaskView', () {
    final model = BackgroundTaskModel.fromJson(view);

    expect(model.taskId, 'a70676e4ddf0ba990');
    expect(model.kind, 'agent');
    expect(model.status, 'running');
    expect(model.toolUseId, 'toolu_01');
    expect(model.description, 'blocker three');
    expect(model.command, 'sleep 900');
    expect(model.summary, 'Task stopped');
    expect(model.exitCode, 143);
    expect(model.durationMs, 7412);
    expect(model.outputFile, '/tmp/tasks/a7.output');
    expect(model.startedAt, '2026-09-25T01:27:01.531Z');
    expect(model.endedAt, '2026-09-25T01:28:01.531Z');
    expect(model.agentId, 'sub-1');
    expect(model.canStop, isTrue);
    expect(model.updatedSeq, 1234);
  });

  test('absent keys stay null', () {
    final model = BackgroundTaskModel.fromJson(const {'taskId': 'b1', 'kind': 'shell', 'status': 'running'});

    expect(model.command, isNull);
    expect(model.exitCode, isNull);
    expect(model.canStop, isNull);
    expect(model.updatedSeq, isNull);
  });

  test('the list response reads the tasks key', () {
    final tasks = BackgroundTaskModel.listFromJson({
      'tasks': [view, {'taskId': 'b2', 'kind': 'shell', 'status': 'completed'}],
    });

    expect(tasks.map((task) => task.taskId), ['a70676e4ddf0ba990', 'b2']);
    expect(BackgroundTaskModel.listFromJson(const {}), isEmpty);
  });

  test('a task_update event parses its detail JSON and takes seq and agentId from the event', () {
    final event = BlockEventModel.fromJson({
      'seq': 88,
      'kind': 'task_update',
      'sourceId': 'buulbcjq7',
      'agentId': 'sub-2',
      'detail': jsonEncode({
        'taskId': 'buulbcjq7',
        'kind': 'shell',
        'status': 'killed',
        'description': 'Background sleep',
        'command': 'sleep 900',
        'exitCode': 0,
        'startedAt': '2026-09-25T00:55:20.045Z',
        'endedAt': '2026-09-25T00:58:45.929Z',
      }),
    });

    final model = BackgroundTaskModel.fromEvent(event)!;

    expect(model.taskId, 'buulbcjq7');
    expect(model.kind, 'shell');
    expect(model.status, 'killed');
    expect(model.description, 'Background sleep');
    expect(model.endedAt, '2026-09-25T00:58:45.929Z');
    expect(model.updatedSeq, 88);
    expect(model.agentId, 'sub-2');
    expect(model.canStop, isNull);
  });

  test('an event without a task id in its detail falls back to sourceId', () {
    final event = BlockEventModel.fromJson({
      'seq': 3,
      'kind': 'task_update',
      'sourceId': 'm1',
      'detail': jsonEncode({'kind': 'monitor', 'status': 'running'}),
    });

    expect(BackgroundTaskModel.fromEvent(event)?.taskId, 'm1');
  });

  test('other kinds, broken detail and a missing id yield nothing', () {
    expect(BackgroundTaskModel.fromEvent(BlockEventModel.fromJson(const {'seq': 1, 'kind': 'stop'})), isNull);
    expect(
      BackgroundTaskModel.fromEvent(
        BlockEventModel.fromJson(const {'seq': 1, 'kind': 'task_update', 'sourceId': 'x', 'detail': '{not json'}),
      ),
      isNull,
    );
    expect(
      BackgroundTaskModel.fromEvent(
        BlockEventModel.fromJson({'seq': 1, 'kind': 'task_update', 'detail': jsonEncode({'status': 'running'})}),
      ),
      isNull,
    );
  });

  test('the stop response carries the task and whether the stop is confirmed', () {
    final result = StopSessionTaskResultModel.fromJson({'task': view, 'confirmed': true});

    expect(result.task?.taskId, 'a70676e4ddf0ba990');
    expect(result.confirmed, isTrue);
    expect(StopSessionTaskResultModel.fromJson(const {}).task, isNull);
  });
}
