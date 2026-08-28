import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/conversation_blocks.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';

ConversationMessageModel _message(
  String id,
  int sequence,
  String role,
  String text, {
  String? turnId = 't-1',
  String? createdAt,
  bool? streaming,
  int? revision,
}) => ConversationMessageModel(
  id: id,
  turnId: turnId,
  sequence: sequence,
  revision: revision ?? 0,
  createdAt: createdAt ?? '2026-08-28T10:00:0$sequence Z'.replaceAll(' ', ''),
  role: role,
  origin: role == 'user' ? 'human' : 'provider',
  text: text,
  streaming: streaming,
);

ConversationActivityModel _activity(
  String id,
  int sequence,
  String activityKind,
  String status, {
  String? turnId = 't-1',
  String? createdAt,
  String? summary,
  String? providerItemId,
  ActivityDetailModel? detail,
}) => ConversationActivityModel(
  id: id,
  turnId: turnId,
  sequence: sequence,
  revision: 0,
  createdAt: createdAt ?? '2026-08-28T10:00:0$sequence Z'.replaceAll(' ', ''),
  activityKind: activityKind,
  status: status,
  summary: summary,
  providerItemId: providerItemId,
  detail: detail,
);

ConversationSnapshotModel _snapshot(
  List<ConversationItemModel> items, {
  String? compactedAt,
  List<ConversationTurnModel> turns = const [],
  ConversationUsageModel? usage,
}) => ConversationSnapshotModel(
  conversationId: 'c-1',
  sessionId: 's-1',
  harness: 'claude-code',
  mode: 'chat',
  controllerState: 'ready',
  latestSequence: items.isEmpty
      ? 0
      : items.map((i) => i.sequence ?? 0).reduce((a, b) => a > b ? a : b),
  oldestSequence: 1,
  hasMoreBefore: false,
  items: items,
  turns: turns,
  compactedAt: compactedAt,
  usage: usage,
);

void main() {
  group('blocksFromConversation — mapping table', () {
    test('message role user maps to prompt', () {
      final blocks = blocksFromConversation(_snapshot([_message('m-1', 1, 'user', 'hi')]));
      expect(blocks, hasLength(1));
      expect(blocks.single.id, 'm-1');
      expect(blocks.single.kind, BlockKind.prompt);
      expect(blocks.single.title, 'Prompt');
      expect(blocks.single.body, 'hi');
      expect(blocks.single.status, BlockStatus.ok);
    });

    test('message role assistant with streaming maps to status running', () {
      final blocks = blocksFromConversation(
        _snapshot([_message('m-1', 1, 'assistant', 'hello', streaming: true)]),
      );
      expect(blocks.single.status, BlockStatus.running);
    });

    test('message role assistant settled maps to status ok', () {
      final blocks = blocksFromConversation(
        _snapshot([_message('m-1', 1, 'assistant', 'hello')]),
      );
      expect(blocks.single.status, BlockStatus.ok);
    });

    test('activity reasoning maps to reasoning with body from detail.text', () {
      final blocks = blocksFromConversation(
        _snapshot([
          _activity(
            'a-1',
            1,
            'reasoning',
            'completed',
            detail: const ActivityDetailModel({'text': 'considering'}),
          ),
        ]),
      );
      expect(blocks.single.kind, BlockKind.reasoning);
      expect(blocks.single.body, 'considering');
      expect(blocks.single.title, 'Reasoning');
    });

    test('activity command maps to tool with shell detail and body from output', () {
      final blocks = blocksFromConversation(
        _snapshot([
          _activity(
            'a-1',
            1,
            'command',
            'completed',
            summary: 'ls',
            detail: const ActivityDetailModel({
              'command': 'ls',
              'output': 'file.txt',
              'exitCode': 0,
            }),
          ),
        ]),
      );
      expect(blocks.single.kind, BlockKind.tool);
      expect(blocks.single.title, 'Shell');
      expect(blocks.single.body, 'file.txt');
      expect(
        blocks.single.detail,
        const ShellBlockDetail(command: 'ls', output: 'file.txt', exitCode: 0),
      );
    });

    test('activity file_change maps to tool with file_change detail', () {
      final blocks = blocksFromConversation(
        _snapshot([
          _activity(
            'a-1',
            1,
            'file_change',
            'completed',
            summary: 'edit',
            detail: const ActivityDetailModel({
              'files': [
                {'path': 'a.ts', 'status': 'modified', 'additions': 1, 'deletions': 0},
              ],
            }),
          ),
        ]),
      );
      expect(blocks.single.kind, BlockKind.tool);
      expect(blocks.single.title, 'File change');
      final detail = blocks.single.detail;
      expect(detail, isA<FileChangeBlockDetail>());
    });

    test('activity mcp_tool maps to tool with mcp_tool detail and server/tool title', () {
      final blocks = blocksFromConversation(
        _snapshot([
          _activity(
            'a-1',
            1,
            'mcp_tool',
            'completed',
            summary: 'subagent',
            detail: const ActivityDetailModel({
              'server': 'agent',
              'toolName': 'subagent',
              'arguments': {'task': 'x'},
              'result': 'ok',
            }),
          ),
        ]),
      );
      expect(blocks.single.kind, BlockKind.tool);
      expect(blocks.single.title, 'agent/subagent');
      expect(blocks.single.body, 'ok');
      expect(
        blocks.single.detail,
        const McpToolBlockDetail(
          server: 'agent',
          tool: 'subagent',
          args: {'task': 'x'},
          result: 'ok',
        ),
      );
    });

    test('activity plan maps to todo with plan detail', () {
      final blocks = blocksFromConversation(
        _snapshot([
          _activity(
            'a-1',
            1,
            'plan',
            'completed',
            detail: const ActivityDetailModel({
              'steps': [
                {'text': 'step 1', 'status': 'pending'},
              ],
            }),
          ),
        ]),
      );
      expect(blocks.single.kind, BlockKind.todo);
      expect(blocks.single.title, 'Plan');
      expect(
        blocks.single.detail,
        const PlanBlockDetail(steps: [BlockPlanStep(text: 'step 1', status: 'pending')]),
      );
    });

    test('activity approval maps to permission with status blocked until resolved', () {
      final blocked = blocksFromConversation(
        _snapshot([_activity('a-1', 1, 'approval', 'pending', summary: 'Run command?')]),
      );
      expect(blocked.single.kind, BlockKind.permission);
      expect(blocked.single.status, BlockStatus.blocked);
      expect(blocked.single.title, 'Run command?');

      final resolved = blocksFromConversation(
        _snapshot([_activity('a-1', 1, 'approval', 'resolved', summary: 'Run command?')]),
      );
      expect(resolved.single.status, BlockStatus.ok);
    });

    test('activity user_input maps to permission with distinct title', () {
      final blocks = blocksFromConversation(
        _snapshot([_activity('a-1', 1, 'user_input', 'pending', summary: 'Pick one')]),
      );
      expect(blocks.single.kind, BlockKind.permission);
      expect(blocks.single.title, 'Pick one');

      final noSummary = blocksFromConversation(
        _snapshot([_activity('a-1', 1, 'user_input', 'pending')]),
      );
      expect(noSummary.single.title, 'Input requested');
    });

    test('activity auto_review maps to notice', () {
      final blocks = blocksFromConversation(
        _snapshot([_activity('a-1', 1, 'auto_review', 'completed', summary: 'decided')]),
      );
      expect(blocks.single.kind, BlockKind.notice);
      expect(blocks.single.title, 'decided');
      expect(blocks.single.body, 'decided');
    });

    test('activity usage maps to notice with usage detail', () {
      final blocks = blocksFromConversation(
        _snapshot([
          _activity(
            'a-1',
            1,
            'usage',
            'completed',
            detail: const ActivityDetailModel({'inputTokens': 10, 'outputTokens': 5}),
          ),
        ]),
      );
      expect(blocks.single.kind, BlockKind.notice);
      expect(blocks.single.body, '');
      expect(
        blocks.single.detail,
        const UsageBlockDetail(inputTokens: 10, outputTokens: 5),
      );
    });

    test('activity error maps to notice with status failed', () {
      final blocks = blocksFromConversation(
        _snapshot([_activity('a-1', 1, 'error', 'failed', summary: 'crash')]),
      );
      expect(blocks.single.kind, BlockKind.notice);
      expect(blocks.single.status, BlockStatus.failed);
      expect(blocks.single.body, 'crash');
    });

    test('activity system maps to notice', () {
      final blocks = blocksFromConversation(
        _snapshot([_activity('a-1', 1, 'system', 'completed', summary: 'info')]),
      );
      expect(blocks.single.kind, BlockKind.notice);
      expect(blocks.single.body, 'info');
    });

    test('snapshot compactedAt produces a compaction block', () {
      final blocks = blocksFromConversation(
        _snapshot(
          [
            _message('m-1', 1, 'user', 'x', createdAt: '2026-08-28T09:00:00Z'),
            _message('m-2', 2, 'assistant', 'y', createdAt: '2026-08-28T10:00:00Z'),
          ],
          compactedAt: '2026-08-28T09:30:00Z',
        ),
      );
      final compaction = blocks.where((b) => b.kind == BlockKind.compaction).single;
      expect(compaction.id, 'compaction-1');
      expect(compaction.title, 'Compaction');
      expect(
        compaction.detail,
        const CompactionBlockDetail(trigger: BlockCompactionTrigger.auto),
      );
    });
  });

  group('blocksFromConversation — six rules', () {
    test('rule 1: block id and sequence come from the item, never minted', () {
      final blocks = blocksFromConversation(
        _snapshot([_message('m-1', 5, 'user', 'hi')]),
      );
      expect(blocks.single.id, 'm-1');
      expect(blocks.single.firstSeq, 5);
      expect(blocks.single.lastSeq, 5);
    });

    test('rule 2: revision does not change the block sequence', () {
      final blocks = blocksFromConversation(
        _snapshot([
          _message('m-1', 1, 'assistant', 'draft', revision: 0),
          _message('m-1', 1, 'assistant', 'final', revision: 3),
        ]),
      );
      expect(blocks, hasLength(1));
      expect(blocks[0].firstSeq, 1);
      expect(blocks[0].lastSeq, 1);
      expect(blocks[0].body, 'final');
    });

    test('rule 3: empty settled text on an assistant produces body "" (pinned)', () {
      final blocks = blocksFromConversation(
        _snapshot([_message('m-1', 1, 'assistant', '')]),
      );
      expect(blocks.single.body, '');
    });

    test('rule 4: command output and reasoning text are kept separate', () {
      final blocks = blocksFromConversation(
        _snapshot([
          _activity(
            'a-1',
            1,
            'reasoning',
            'completed',
            detail: const ActivityDetailModel({'text': 'I think'}),
          ),
          _activity(
            'a-2',
            2,
            'command',
            'completed',
            summary: 'pwd',
            detail: const ActivityDetailModel({
              'command': 'pwd',
              'output': '/home',
              'exitCode': 0,
            }),
          ),
        ]),
      );
      final reasoning = blocks.firstWhere((b) => b.kind == BlockKind.reasoning);
      final tool = blocks.firstWhere((b) => b.kind == BlockKind.tool);
      expect(reasoning.body, 'I think');
      expect(tool.body, '/home');
      expect(reasoning.body, isNot(tool.body));
    });

    test('rule 5: outputTruncated and textTruncated map to truncatedLines', () {
      final truncatedCommand = blocksFromConversation(
        _snapshot([
          _activity(
            'a-1',
            1,
            'command',
            'completed',
            detail: const ActivityDetailModel({
              'command': 'ls',
              'output': 'x',
              'outputTruncated': true,
            }),
          ),
        ]),
      );
      expect(truncatedCommand.single.truncatedLines, 1);

      final truncatedReasoning = blocksFromConversation(
        _snapshot([
          _activity(
            'a-1',
            1,
            'reasoning',
            'completed',
            detail: const ActivityDetailModel({'text': 'x', 'textTruncated': true}),
          ),
        ]),
      );
      expect(truncatedReasoning.single.truncatedLines, 1);

      final normalCommand = blocksFromConversation(
        _snapshot([
          _activity(
            'a-1',
            1,
            'command',
            'completed',
            detail: const ActivityDetailModel({'command': 'ls', 'output': 'x'}),
          ),
        ]),
      );
      expect(normalCommand.single.truncatedLines, 0);
    });

    test('rule 6: rolled-back turn is excluded but countable as a notice', () {
      final blocks = blocksFromConversation(
        _snapshot(
          [
            _message('m-1', 1, 'user', 'x', turnId: 't-rolled'),
            _activity(
              'a-1',
              2,
              'command',
              'completed',
              turnId: 't-rolled',
              detail: const ActivityDetailModel({
                'command': 'x',
                'output': 'y',
                'exitCode': 0,
              }),
            ),
            _message('m-2', 3, 'user', 'fresh', turnId: 't-fresh'),
          ],
          turns: const [
            ConversationTurnModel(
              id: 't-rolled',
              state: 'rolled_back',
              rolledBack: true,
              requestedAt: '2026-08-28T10:00:00Z',
            ),
            ConversationTurnModel(
              id: 't-fresh',
              state: 'completed',
              requestedAt: '2026-08-28T11:00:00Z',
            ),
          ],
        ),
      );
      final rolledBack = blocks.where((b) => b.id == 'rolled-back-t-rolled').singleOrNull;
      expect(rolledBack, isNotNull);
      expect(rolledBack!.kind, BlockKind.notice);
      expect(rolledBack.body, 'Rolled back: t-rolled');
      expect(blocks.where((b) => b.id == 'm-1'), isEmpty);
      expect(blocks.where((b) => b.id == 'a-1'), isEmpty);
      expect(blocks.where((b) => b.id == 'm-2'), hasLength(1));
    });
  });

  group('blocksFromConversation — nesting', () {
    test('one level: child appears in parent.children', () {
      final blocks = blocksFromConversation(
        _snapshot([
          _message('m-1', 1, 'user', 'go'),
          _activity(
            'a-parent',
            2,
            'mcp_tool',
            'completed',
            providerItemId: 'parent-1',
            detail: const ActivityDetailModel({
              'server': 'agent',
              'toolName': 'subagent',
              'arguments': {'task': 'x'},
              'result': 'done',
            }),
          ),
          _activity(
            'a-child-1',
            3,
            'command',
            'completed',
            detail: const ActivityDetailModel({
              'command': 'ls',
              'output': 'out',
              'exitCode': 0,
              'parentProviderItemId': 'parent-1',
            }),
          ),
          _message('m-2', 4, 'assistant', 'done'),
        ]),
      );
      final parent = blocks.firstWhere((b) => b.id == 'a-parent');
      expect(parent.children, isNotNull);
      expect(parent.children, hasLength(1));
      expect(parent.children!.single.id, 'a-child-1');
    });

    test('flattened grandchild: grandchild whose parent is a child lands in parent.children after the children', () {
      final blocks = blocksFromConversation(
        _snapshot([
          _message('m-1', 1, 'user', 'go'),
          _activity(
            'a-parent',
            2,
            'mcp_tool',
            'completed',
            providerItemId: 'parent-1',
            detail: const ActivityDetailModel({
              'server': 'agent',
              'toolName': 'subagent',
              'result': 'done',
            }),
          ),
          _activity(
            'a-child-1',
            3,
            'command',
            'completed',
            detail: const ActivityDetailModel({
              'command': 'ls',
              'output': 'out',
              'exitCode': 0,
              'parentProviderItemId': 'parent-1',
            }),
          ),
          _activity(
            'a-grandchild',
            4,
            'command',
            'completed',
            detail: const ActivityDetailModel({
              'command': 'wc',
              'output': '1',
              'exitCode': 0,
              'parentProviderItemId': 'a-child-1',
            }),
          ),
          _message('m-2', 5, 'assistant', 'done'),
        ]),
      );
      final parent = blocks.firstWhere((b) => b.id == 'a-parent');
      expect(parent.children!.map((c) => c.id), ['a-child-1', 'a-grandchild']);
    });

    test('terminated cycle: a node whose parent is its own descendant is included once', () {
      final blocks = blocksFromConversation(
        _snapshot([
          _message('m-1', 1, 'user', 'go'),
          _activity(
            'a-parent',
            2,
            'mcp_tool',
            'completed',
            providerItemId: 'parent-1',
            detail: const ActivityDetailModel({
              'server': 'agent',
              'toolName': 'subagent',
              'result': 'done',
            }),
          ),
          _activity(
            'a-child-1',
            3,
            'command',
            'completed',
            detail: const ActivityDetailModel({
              'command': 'ls',
              'output': 'out',
              'exitCode': 0,
              'parentProviderItemId': 'parent-1',
            }),
          ),
          _activity(
            'a-cycle',
            4,
            'command',
            'completed',
            detail: const ActivityDetailModel({
              'command': 'echo',
              'output': 'x',
              'exitCode': 0,
              'parentProviderItemId': 'a-child-1',
            }),
          ),
          _activity(
            'a-back',
            5,
            'command',
            'completed',
            detail: const ActivityDetailModel({
              'command': 'tail',
              'output': 'y',
              'exitCode': 0,
              'parentProviderItemId': 'a-cycle',
            }),
          ),
          _message('m-2', 6, 'assistant', 'done'),
        ]),
      );
      final parent = blocks.firstWhere((b) => b.id == 'a-parent');
      expect(
        parent.children!.map((c) => c.id),
        ['a-child-1', 'a-cycle', 'a-back'],
      );
    });
  });
}
