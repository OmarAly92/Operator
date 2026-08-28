import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/search/text_match.dart';
import 'package:operator_mobile/feature/blocks/logic/block_find.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

void main() {
  final file = File('../../testdata/blocks/block_find.json');
  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  test('the shared fixture exists', () {
    expect(file.existsSync(), isTrue, reason: 'the shared fixture is missing; never fix a failing fixture by editing it');
  });

  for (final item in (fixture['matches'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test(item['name'] as String, () => expect(BlockFind.matches(_blocks(item['blocks']), item['query'] as String), _matches(item['expect'])));
  }
  for (final item in (fixture['filter'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test(item['name'] as String, () {
      final result = BlockFind.filter(_blocks(item['blocks']), item['query'] as String, (item['contextBlocks'] as num).toInt());
      expect(result.blocks.map((block) => block.id).toList(), (item['expectIds'] as List<dynamic>).cast<String>());
      expect(result.matchIds, (item['matchIds'] as List<dynamic>).cast<String>().toSet());
      expect(result.hiddenCount, item['hiddenCount']);
    });
  }
  for (final item in (fixture['navigation'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test(item['name'] as String, () {
      final matches = (item['ids'] as List<dynamic>).cast<String>().map((id) => BlockMatch(blockId: id, field: BlockMatchField.displayName, score: const MatchScore(tier: 0, offset: 0), ranges: const [])).toList();
      expect(BlockFind.nextMatchId(matches, item['currentId'] as String?, forward: item['forward'] as bool), item['expect']);
    });
  }
  test('empty query preserves the input list', () {
    final blocks = _blocks([{ 'id': 'empty', 'kind': 'notice', 'status': 'ok', 'title': 'Notice', 'body': 'text' }]);
    expect(BlockFind.matches(blocks, ' '), isEmpty);
    final result = BlockFind.filter(blocks, ' ', 0);
    expect(identical(result.blocks, blocks), isTrue);
    expect(result.matchIds, isEmpty);
    expect(result.hiddenCount, 0);
  });
  test('search fields use the display rather than raw block data', () {
    final block = blockFromFixture({ 'id': 'shell', 'kind': 'tool', 'status': 'ok', 'title': 'Tool', 'body': 'ignored', 'detail': { 'type': 'shell', 'command': 'pwd', 'output': 'root' } });
    expect(BlockFind.searchFields(block), ['Shell', 'pwd\n\nroot']);
  });
}

List<SessionBlock> _blocks(Object? value) => (value as List<dynamic>).cast<Map<String, dynamic>>().map(blockFromFixture).toList();

List<BlockMatch> _matches(Object? value) => (value as List<dynamic>).cast<Map<String, dynamic>>().map((json) {
  final score = (json['score'] as Map).cast<String, dynamic>();
  return BlockMatch(
    blockId: json['blockId'] as String,
    field: BlockMatchField.values.byName(json['field'] as String),
    score: MatchScore(tier: (score['tier'] as num).toInt(), offset: (score['offset'] as num).toInt(), spread: (score['spread'] as num?)?.toInt()),
    ranges: (json['ranges'] as List<dynamic>).cast<Map<String, dynamic>>().map((range) => MatchRange(start: (range['start'] as num).toInt(), length: (range['length'] as num).toInt())).toList(),
  );
}).toList();

SessionBlock blockFromFixture(Map<String, dynamic> json) => SessionBlock(
  id: json['id'] as String,
  firstSeq: (json['firstSeq'] as num?)?.toInt() ?? 1,
  lastSeq: (json['lastSeq'] as num?)?.toInt() ?? 1,
  kind: BlockKind.values.byName(json['kind'] as String),
  status: BlockStatus.values.byName(json['status'] as String),
  turnId: json['turnId'] as String?,
  title: json['title'] as String,
  body: json['body'] as String? ?? '',
  detail: json['detail'] is Map ? BlockDetail.fromJson((json['detail'] as Map).cast<String, dynamic>()) : null,
  toolName: json['toolName'] as String?,
  errorType: json['errorType'] as String?,
  truncatedLines: (json['truncatedLines'] as num?)?.toInt() ?? 0,
  redacted: json['redacted'] as bool? ?? false,
  children: (json['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>().map(blockFromFixture).toList(),
);
