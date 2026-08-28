import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/block_actions.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

void main() {
  final file = File('../../testdata/blocks/block_actions.json');
  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  test('the shared fixture exists', () {
    expect(file.existsSync(), isTrue, reason: 'the shared fixture is missing; never fix a failing fixture by editing it');
  });

  for (final item in (fixture['actions'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test(item['name'] as String, () {
      final context = (item['context'] as Map).cast<String, dynamic>();
      final expected = (item['expect'] as List<dynamic>).cast<Map<String, dynamic>>().map(_actionFromFixture).toList();
      expect(
        BlockActions.forBlock(
          blockFromFixture((item['block'] as Map).cast<String, dynamic>()),
          BlockActionContext(
            mode: context['mode'] as String? ?? 'tui',
            capabilities: (context['capabilities'] as List<dynamic>? ?? const []).cast<String>(),
            canSend: context['canSend'] as bool? ?? false,
            turnInFlight: context['turnInFlight'] as bool? ?? false,
            rollbackableTurnIds: (context['rollbackableTurnIds'] as List<dynamic>? ?? const []).cast<String>(),
          ),
        ),
        expected,
      );
    });
  }

  for (final item in (fixture['copyText'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test(item['name'] as String, () => expect(BlockActions.copyText(blockFromFixture((item['block'] as Map).cast<String, dynamic>())), item['expect']));
  }

  for (final item in (fixture['selectionText'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test(item['name'] as String, () {
      expect(BlockActions.blocksToText((item['blocks'] as List<dynamic>).cast<Map<String, dynamic>>().map(blockFromFixture).toList()), item['expect']);
    });
  }
}

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

BlockAction _actionFromFixture(Map<String, dynamic> json) => BlockAction(
  kind: BlockActionKind.values.byName(_camel(json['kind'] as String)),
  payload: json['payload'] as String?,
  turnId: json['turnId'] as String?,
);

String _camel(String value) => value.replaceAllMapped(RegExp(r'_([a-z])'), (match) => match.group(1)!.toUpperCase());
