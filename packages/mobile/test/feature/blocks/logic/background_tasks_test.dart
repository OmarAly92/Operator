import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/background_task_model.dart';
import 'package:operator_mobile/feature/blocks/logic/background_tasks.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/subagents.dart';

SessionBlock _agent(
  String id, {
  String? agentId,
  String status = 'running',
  BlockStatus blockStatus = BlockStatus.running,
  int? durationMs,
  String? agentType,
}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.tool,
  status: blockStatus,
  title: 'Agent',
  body: '',
  toolName: 'Agent',
  createdAt: '2026-09-19T10:00:00Z',
  detail: AgentBlockDetail(
    description: 'Task $id',
    agentId: agentId,
    status: status,
    durationMs: durationMs,
    agentType: agentType,
    toolUseCount: 3,
  ),
);

void main() {
  test('a running subagent is a running agent task with its title, start and entry', () {
    final tasks = backgroundTasksOf([_agent('c1', agentId: 'a1', agentType: 'Explore')], const {});

    final task = tasks.single;
    expect(task.id, 'a1');
    expect(task.kind, BackgroundTaskKind.agent);
    expect(task.title, 'Task c1');
    expect(task.status, BackgroundTaskStatus.running);
    expect(task.running, isTrue);
    expect(task.startedAt, DateTime.utc(2026, 9, 19, 10));
    expect(task.canStop, isFalse);
    expect(task.agentId, 'a1');
    expect(task.subagent?.detail?.agentType, 'Explore');
  });

  test('finished subagents are completed, stopped or failed', () {
    final tasks = backgroundTasksOf(
      [
        _agent('c1', agentId: 'a1', status: 'completed', blockStatus: BlockStatus.ok, durationMs: 65000),
        _agent('c2', agentId: 'a2', status: 'failed', blockStatus: BlockStatus.failed),
        _agent('c3', agentId: 'a3', status: 'stopped', blockStatus: BlockStatus.ok),
      ],
      const {},
    );

    final byId = {for (final task in tasks) task.id: task};
    expect(byId['a1']!.status, BackgroundTaskStatus.completed);
    expect(byId['a2']!.status, BackgroundTaskStatus.failed);
    expect(byId['a3']!.status, BackgroundTaskStatus.stopped);
    expect(tasks.every((task) => !task.running), isTrue);
  });

  test('an agent_stop on the tail finishes the task as completed, since the hook fires on every completion', () {
    final tasks = backgroundTasksOf(
      [_agent('c1', agentId: 'a1', status: 'async_launched')],
      {'a1': const SubagentSummary(agentId: 'a1', stopped: true)},
    );

    expect(tasks.single.running, isFalse);
    expect(tasks.single.status, BackgroundTaskStatus.completed);
  });

  test('a tail with no card is a running agent titled Agent, keyed by its agent id', () {
    final tasks = backgroundTasksOf(const [], {
      'zz': const SubagentSummary(agentId: 'zz', startedAt: '2026-09-19T10:00:05Z'),
    });

    expect(tasks.single.id, 'zz');
    expect(tasks.single.title, 'Agent');
    expect(tasks.single.running, isTrue);
    expect(tasks.single.startedAt, DateTime.utc(2026, 9, 19, 10, 0, 5));
  });

  test('running tasks come first, in the order subagentsOf gives', () {
    final tasks = backgroundTasksOf(
      [
        _agent('c1', agentId: 'a1', status: 'completed', blockStatus: BlockStatus.ok),
        _agent('c2', agentId: 'a2'),
      ],
      const {},
    );

    expect(tasks.map((task) => task.id), ['a2', 'a1']);
  });

  test('running tasks start oldest first and finished ones end newest first, kinds interleaved', () {
    DateTime at(int second) => DateTime.utc(2026, 9, 19, 10, 0, second);
    final sorted = sortBackgroundTasks([
      BackgroundTask(id: 'r-late', kind: BackgroundTaskKind.shell, title: 't', status: BackgroundTaskStatus.running, startedAt: at(30)),
      BackgroundTask(id: 'f-old', kind: BackgroundTaskKind.agent, title: 't', status: BackgroundTaskStatus.completed, startedAt: at(0), finishedAt: at(10)),
      BackgroundTask(id: 'r-early', kind: BackgroundTaskKind.agent, title: 't', status: BackgroundTaskStatus.running, startedAt: at(5)),
      BackgroundTask(id: 'f-new', kind: BackgroundTaskKind.shell, title: 't', status: BackgroundTaskStatus.failed, startedAt: at(1), finishedAt: at(40)),
    ]);

    expect(sorted.map((task) => task.id), ['r-early', 'r-late', 'f-new', 'f-old']);
  });

  BackgroundTaskModel feedTask(
    String id, {
    String kind = 'shell',
    String status = 'running',
    int? seq,
    bool? canStop,
    String? description,
    String? command,
    String? startedAt,
    String? endedAt,
  }) => BackgroundTaskModel(
    taskId: id,
    kind: kind,
    status: status,
    updatedSeq: seq,
    canStop: canStop,
    description: description,
    command: command,
    startedAt: startedAt,
    endedAt: endedAt,
  );

  group('the task feed', () {
    test('maps daemon statuses: killed and stopped are Stopped', () {
      final tasks = backgroundTasksOf(const [], const {}, feed: [
        feedTask('r', status: 'running'),
        feedTask('c', status: 'completed'),
        feedTask('f', status: 'failed'),
        feedTask('k', status: 'killed'),
        feedTask('s', status: 'stopped'),
      ]);

      final byId = {for (final task in tasks) task.id: task.status};
      expect(byId, {
        'r': BackgroundTaskStatus.running,
        'c': BackgroundTaskStatus.completed,
        'f': BackgroundTaskStatus.failed,
        'k': BackgroundTaskStatus.stopped,
        's': BackgroundTaskStatus.stopped,
      });
    });

    test('shells and monitors take the description, then the command, as their title and their times from the feed', () {
      final tasks = backgroundTasksOf(const [], const {}, feed: [
        feedTask('b1', description: 'Run the tests', command: 'npm test', startedAt: '2026-09-25T01:00:00Z'),
        feedTask('m1', kind: 'monitor', command: 'tail -f log', status: 'completed', endedAt: '2026-09-25T01:05:00Z'),
      ]);

      final shell = tasks.firstWhere((task) => task.id == 'b1');
      expect(shell.kind, BackgroundTaskKind.shell);
      expect(shell.title, 'Run the tests');
      expect(shell.startedAt, DateTime.utc(2026, 9, 25, 1));
      final monitor = tasks.firstWhere((task) => task.id == 'm1');
      expect(monitor.kind, BackgroundTaskKind.monitor);
      expect(monitor.title, 'tail -f log');
      expect(monitor.finishedAt, DateTime.utc(2026, 9, 25, 1, 5));
    });

    test('canStop holds only while the task runs', () {
      final tasks = backgroundTasksOf(const [], const {}, feed: [
        feedTask('a', canStop: true),
        feedTask('b', status: 'completed', canStop: true),
        feedTask('c'),
      ]);

      final byId = {for (final task in tasks) task.id: task.canStop};
      expect(byId, {'a': true, 'b': false, 'c': false});
    });

    test('the feed owns an agent it knows, keeping the subagent entry for its transcript', () {
      final tasks = backgroundTasksOf(
        [_agent('c1', agentId: 'a1'), _agent('c2', agentId: 'a2')],
        const {},
        feed: [feedTask('a1', kind: 'agent', status: 'killed', description: 'Feed title')],
      );

      expect(tasks, hasLength(2));
      final fed = tasks.firstWhere((task) => task.id == 'a1');
      expect(fed.kind, BackgroundTaskKind.agent);
      expect(fed.status, BackgroundTaskStatus.stopped);
      expect(fed.title, 'Feed title');
      expect(fed.subagent?.agentId, 'a1');
      final fallback = tasks.firstWhere((task) => task.id == 'a2');
      expect(fallback.running, isTrue);
      expect(fallback.subagent?.agentId, 'a2');
    });
  });

  group('folding updates', () {
    test('a newer update replaces the status and keeps launch fields it lacks', () {
      final merged = mergeBackgroundTask(
        feedTask('b1', seq: 5, description: 'Sleep', command: 'sleep 9', startedAt: '2026-09-25T01:00:00Z', canStop: true),
        feedTask('b1', seq: 9, status: 'killed', endedAt: '2026-09-25T01:01:00Z'),
      );

      expect(merged.status, 'killed');
      expect(merged.description, 'Sleep');
      expect(merged.command, 'sleep 9');
      expect(merged.startedAt, '2026-09-25T01:00:00Z');
      expect(merged.endedAt, '2026-09-25T01:01:00Z');
      expect(merged.updatedSeq, 9);
    });

    test('an older update arriving late never rolls the status back but fills missing fields', () {
      final merged = mergeBackgroundTask(
        feedTask('b1', seq: 9, status: 'completed'),
        feedTask('b1', seq: 5, description: 'Sleep', canStop: true),
      );

      expect(merged.status, 'completed');
      expect(merged.description, 'Sleep');
      expect(merged.updatedSeq, 9);
    });

    test('a duplicate seq keeps the status and takes canStop from whichever copy has it', () {
      final seeded = feedTask('b1', seq: 7, canStop: true, description: 'Sleep');
      final live = feedTask('b1', seq: 7);

      final merged = mergeBackgroundTask(seeded, live);
      expect(merged, mergeBackgroundTask(seeded, seeded));
      expect(merged.canStop, isTrue);
      expect(merged.status, 'running');
      expect(mergeBackgroundTask(live, seeded).canStop, isTrue);
    });

    test('the first update for a task is taken as is', () {
      final update = feedTask('b1', seq: 1);
      expect(mergeBackgroundTask(null, update), update);
    });
  });
}
