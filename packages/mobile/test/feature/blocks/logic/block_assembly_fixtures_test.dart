import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/block_assembly.dart';
import 'package:operator_mobile/feature/blocks/logic/conversation_blocks.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';

const _fixtures = [
  'assembly_turn',
  'assembly_permission',
  'assembly_out_of_order',
  'assembly_truncation',
  'assembly_tool_failure',
  'assembly_question',
];

const _acpFixtures = [
  'acp_stream_basic',
  'acp_stream_tool_failure',
  'acp_stream_compaction',
  'acp_stream_nested_subagent',
];

void main() {
  for (final name in _fixtures) {
    test('$name assembles as the shared fixture says', () {
      final file = File('../../testdata/blocks/$name.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'the shared fixture is missing; never fix a failing fixture by editing it',
      );

      final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final records = (fixture['records'] as List<dynamic>)
          .map((raw) => BlockEventModel.fromJson(raw as Map<String, dynamic>))
          .toList();
      final expected = (fixture['expected'] as List<dynamic>).cast<Map<String, dynamic>>();

      final blocks = assembleBlocks(records);

      expect(blocks, hasLength(expected.length), reason: 'block count for $name');
      for (var i = 0; i < expected.length; i++) {
        final want = expected[i];
        final got = blocks[i];
        expect(got.id, want['id'], reason: '$name block $i id');
        expect(got.kind.name, want['kind'], reason: '$name block $i kind');
        expect(got.status.name, want['status'], reason: '$name block $i status');
        expect(got.title, want['title'], reason: '$name block $i title');
        expect(got.body, want['body'] ?? '', reason: '$name block $i body');
        expect(got.errorType ?? '', want['errorType'] ?? '', reason: '$name block $i errorType');
        expect(got.truncatedLines, want['truncatedLines'] ?? 0, reason: '$name block $i truncatedLines');
        expect(got.redacted, want['redacted'] ?? false, reason: '$name block $i redacted');
      }
    });
  }

  test('acp_detail_variants has a display for every detail variant', () {
    final file = File('../../testdata/blocks/acp_detail_variants.json');
    expect(file.existsSync(), isTrue, reason: 'the shared ACP detail fixture is missing');

    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final details = (fixture['details'] as List<dynamic>).cast<Map<String, dynamic>>();

    for (final item in details) {
      final expected = item['display'] as Map<String, dynamic>;
      final display = blockDisplay(
        SessionBlock(
          id: 'acp-detail',
          firstSeq: 1,
          lastSeq: 1,
          kind: BlockKind.tool,
          status: BlockStatus.ok,
          title: 'Tool',
          body: '',
          detail: BlockDetail.fromJson(item['detail'] as Map<String, dynamic>),
        ),
      );

      expect(display.displayName, expected['displayName']);
      expect(display.summary, expected['summary']);
      expect(display.errorText, expected['errorText']);
    }
  });

  test('BlockDetail preserves unsupported payloads and rejects malformed known detail', () {
    final future = <String, dynamic>{'type': 'future_tool', 'value': 7};
    final malformed = <String, dynamic>{'type': 'compaction', 'trigger': 'later', 'preTokens': 20};

    expect(BlockDetail.fromJson(future), UnknownBlockDetail(raw: future));
    expect(BlockDetail.fromJson(malformed), UnknownBlockDetail(raw: malformed));
    expect(
      BlockDetail.fromJson(<String, dynamic>{'type': 'unknown', 'raw': 'provider data'}),
      const UnknownBlockDetail(raw: 'provider data'),
    );
  });

  for (final name in _acpFixtures) {
    test('$name assembles as the shared ACP fixture says', () {
      final file = File('../../testdata/blocks/$name.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'the shared ACP fixture is missing; never fix a failing fixture by editing it',
      );

      final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final snapshotJson = fixture['snapshot'] as Map<String, dynamic>;
      final expected = (fixture['expected'] as List<dynamic>).cast<Map<String, dynamic>>();

      final rawItems = (snapshotJson['items'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      final items = <ConversationItemModel>[
        for (final raw in rawItems)
          if (raw['kind'] == 'message')
            ConversationMessageModel.fromJson(raw)
          else if (raw['kind'] == 'activity')
            ConversationActivityModel.fromJson(raw)
          else
            throw StateError('unknown item kind: ${raw['kind']}'),
      ]..sort(
        (left, right) => (left.sequence ?? 0).compareTo(right.sequence ?? 0),
      );

      final snapshot = ConversationSnapshotModel(
        conversationId: snapshotJson['conversationId'] as String?,
        sessionId: snapshotJson['sessionId'] as String?,
        harness: snapshotJson['harness'] as String?,
        mode: snapshotJson['mode'] as String?,
        controllerState: (snapshotJson['controller'] as Map<String, dynamic>?)?['state'] as String?,
        latestSequence: (snapshotJson['latestSequence'] as num?)?.toInt() ?? 0,
        oldestSequence:
            (snapshotJson['oldestSequence'] as num?)?.toInt() ??
            (snapshotJson['latestSequence'] as num?)?.toInt() ??
            0,
        hasMoreBefore: snapshotJson['hasMoreBefore'] == true,
        items: items,
        turns: (snapshotJson['turns'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ConversationTurnModel.fromJson)
            .toList(),
        compactedAt: snapshotJson['compactedAt'] as String?,
      );

      final blocks = blocksFromConversation(snapshot);

      void assertBlock(SessionBlock got, Map<String, dynamic> want) {
        expect(got.id, want['id'], reason: '$name block id');
        expect(got.kind.name, want['kind'], reason: '$name block kind');
        expect(got.status.name, want['status'], reason: '$name block status');
        expect(got.title, want['title'], reason: '$name block title');
        expect(got.body, want['body'] ?? '', reason: '$name block body');
        expect(got.turnId, want['turnId'], reason: '$name block turnId');
        expect(
          got.firstSeq,
          (want['firstSeq'] as num?)?.toInt() ?? got.lastSeq,
          reason: '$name block firstSeq',
        );
        expect(
          got.lastSeq,
          (want['lastSeq'] as num?)?.toInt() ?? got.firstSeq,
          reason: '$name block lastSeq',
        );
        expect(
          got.truncatedLines,
          (want['truncatedLines'] as num?)?.toInt() ?? 0,
          reason: '$name block truncatedLines',
        );
        expect(got.redacted, want['redacted'] == true, reason: '$name block redacted');
        final wantDetail = want['detail'];
        if (wantDetail is Map<String, dynamic>) {
          expect(got.detail, BlockDetail.fromJson(wantDetail), reason: '$name block detail');
        }
      }

      void assertChildren(SessionBlock got, Map<String, dynamic> want) {
        final wantChildren = want['children'];
        if (wantChildren is! List) {
          final gotChildren =
              (got as dynamic).children as List<SessionBlock>? ?? const <SessionBlock>[];
          expect(gotChildren, isEmpty, reason: '$name block children');
          return;
        }
        final gotChildren =
            (got as dynamic).children as List<SessionBlock>? ?? const <SessionBlock>[];
        expect(
          gotChildren,
          hasLength(wantChildren.length),
          reason: '$name block children count',
        );
        for (var i = 0; i < wantChildren.length; i++) {
          final childWant = (wantChildren[i] as Map).cast<String, dynamic>();
          assertBlock(gotChildren[i], childWant);
          assertChildren(gotChildren[i], childWant);
        }
      }

      expect(blocks, hasLength(expected.length), reason: 'block count for $name');
      for (var i = 0; i < expected.length; i++) {
        assertBlock(blocks[i], expected[i]);
        assertChildren(blocks[i], expected[i]);
      }
    });
  }
}
