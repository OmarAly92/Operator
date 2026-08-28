import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';

void main() {
  test(
    'keeps canonical turn boundaries while allowing a system-injected response to run together',
    () {
      final file = File('../../testdata/blocks/acp_turn_grouping.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'the shared turn grouping fixture is missing',
      );

      final fixture =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final name in ['acp', 'hooks']) {
        final stream = fixture[name] as Map<String, dynamic>;
        final blocks = (stream['blocks'] as List<dynamic>)
            .map((raw) => _block(raw as Map<String, dynamic>))
            .toList();
        final boundaries = (stream['strictBoundaries'] as List<dynamic>)
            .cast<bool>();
        for (var index = 1; index < blocks.length; index++) {
          expect(
            continuesTurn(blocks[index - 1], blocks[index]),
            !boundaries[index - 1],
          );
        }

        final expected = (stream['turnGroups'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final groups = groupBlocksByTurn(blocks);
        expect(groups, hasLength(expected.length));
        for (var index = 0; index < groups.length; index++) {
          final group = groups[index];
          final want = expected[index];
          expect(group.blocks.map((block) => block.id), want['ids']);
          expect(group.turnId, want['turnId']);
          expect(group.startedAt, want['startedAt']);
          expect(group.completedAt, want['completedAt']);
          expect(group.durationMs, want['durationMs']);
          expect(group.running, want['running']);
        }
      }

      final acp = fixture['acp'] as Map<String, dynamic>;
      final blocks = (acp['blocks'] as List<dynamic>)
          .map((raw) => _block(raw as Map<String, dynamic>))
          .toList();
      expect(continuesResponse(blocks[1], blocks[2]), isTrue);
    },
  );
}

SessionBlock _block(Map<String, dynamic> json) => SessionBlock(
  id: json['id'] as String,
  firstSeq: json['firstSeq'] as int,
  lastSeq: json['lastSeq'] as int,
  kind: BlockKind.values.byName(json['kind'] as String),
  status: BlockStatus.values.byName(json['status'] as String),
  turnId: json['turnId'] as String?,
  title: json['title'] as String,
  body: json['body'] as String,
  truncatedLines: json['truncatedLines'] as int,
  redacted: json['redacted'] as bool,
  createdAt: json['createdAt'] as String?,
);
