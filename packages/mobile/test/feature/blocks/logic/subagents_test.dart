import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/subagents.dart';

SessionBlock _agent(String id, {String? agentId, String prompt = 'p', String status = 'running', BlockStatus blockStatus = BlockStatus.running}) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.tool,
  status: blockStatus,
  title: 'Agent',
  body: '',
  toolName: 'Agent',
  createdAt: '2026-09-19T10:00:00Z',
  detail: AgentBlockDetail(description: 'Task $id', prompt: prompt, model: 'sonnet', agentId: agentId, status: status),
);

void main() {
  test('joins a tail to its card by agent id, else by prompt', () {
    final entries = subagentsOf(
      [_agent('c1', agentId: 'a1'), _agent('c2', prompt: 'Implement task 2')],
      {
        'a1': const SubagentSummary(agentId: 'a1', prompt: 'other', startedAt: '2026-09-19T10:00:00Z'),
        'a2': const SubagentSummary(agentId: 'a2', prompt: 'Implement task 2', startedAt: '2026-09-19T10:00:01Z'),
      },
    );
    expect(entries.map((e) => (e.card?.id, e.agentId)), [('c1', 'a1'), ('c2', 'a2')]);
  });

  test('a tail matching nothing is still listed under its agent id', () {
    final entries = subagentsOf(const [], {'zz': const SubagentSummary(agentId: 'zz', prompt: 'x')});
    expect(entries.single.agentId, 'zz');
    expect(entries.single.card, isNull);
    expect(entries.single.title, 'Agent');
  });

  test('running agents come first, then finished newest first', () {
    final entries = subagentsOf(
      [
        _agent('done-old', agentId: 'd1', status: 'completed', blockStatus: BlockStatus.ok),
        _agent('run', agentId: 'r1'),
        _agent('done-new', agentId: 'd2', status: 'completed', blockStatus: BlockStatus.ok),
      ],
      {
        'd1': const SubagentSummary(agentId: 'd1', lastSeenAt: '2026-09-19T10:01:00Z', stopped: true),
        'r1': const SubagentSummary(agentId: 'r1', lastSeenAt: '2026-09-19T10:02:00Z'),
        'd2': const SubagentSummary(agentId: 'd2', lastSeenAt: '2026-09-19T10:03:00Z', stopped: true),
      },
    );
    expect(entries.map((e) => e.agentId), ['r1', 'd2', 'd1']);
    expect(entries.first.running, isTrue);
  });
}
