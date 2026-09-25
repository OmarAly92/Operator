import 'package:flutter_test/flutter_test.dart';
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
}
