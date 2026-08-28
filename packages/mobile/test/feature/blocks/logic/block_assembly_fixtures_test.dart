import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/block_assembly.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

const _fixtures = [
  'assembly_turn',
  'assembly_permission',
  'assembly_out_of_order',
  'assembly_truncation',
  'assembly_tool_failure',
  'assembly_question',
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
}
