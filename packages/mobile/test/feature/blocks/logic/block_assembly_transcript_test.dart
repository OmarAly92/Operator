import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/block_assembly.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

const _fixtures = [
  'assembly_transcript_turn',
  'assembly_transcript_tool_merge',
  'assembly_transcript_codex',
  'assembly_transcript_question',
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

      expect(blocks, hasLength(expected.length), reason: 'block count for $name: ${blocks.map((b) => b.id)}');
      for (var i = 0; i < expected.length; i++) {
        final want = expected[i];
        final got = blocks[i];
        expect(got.id, want['id'], reason: '$name block $i id');
        expect(got.kind.name, want['kind'], reason: '$name block $i kind');
        expect(got.status.name, want['status'], reason: '$name block $i status');
        expect(got.title, want['title'], reason: '$name block $i title');
        expect(got.body, want['body'] ?? '', reason: '$name block $i body');
        expect(got.result ?? '', want['result'] ?? '', reason: '$name block $i result');
        expect(got.model ?? '', want['model'] ?? '', reason: '$name block $i model');
        expect(got.errorType ?? '', want['errorType'] ?? '', reason: '$name block $i errorType');

        final wantQuestions = want['questions'] as List<dynamic>?;
        if (wantQuestions == null) continue;
        final detail = got.detail;
        expect(detail, isA<QuestionBlockDetail>(), reason: '$name block $i detail');
        final questions = (detail as QuestionBlockDetail).questions;
        expect(questions, hasLength(wantQuestions.length), reason: '$name block $i question count');
        for (var q = 0; q < wantQuestions.length; q++) {
          final wantQuestion = wantQuestions[q] as Map<String, dynamic>;
          expect(questions[q].question, wantQuestion['question'], reason: '$name block $i question $q');
          expect(
            questions[q].options.map((option) => option.label).toList(),
            wantQuestion['options'],
            reason: '$name block $i options $q',
          );
        }
      }
    });
  }
}
