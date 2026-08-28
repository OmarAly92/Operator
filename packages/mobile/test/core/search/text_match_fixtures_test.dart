import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/search/text_match.dart';

void main() {
  final file = File('../../testdata/search/text-match.json');
  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  test('the shared fixture exists', () {
    expect(
      file.existsSync(),
      isTrue,
      reason: 'the shared fixture is missing; never fix a failing fixture by editing it',
    );
  });

  for (final item in (fixture['score'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test(item['name'] as String, () {
      final options = (item['options'] as Map).cast<String, dynamic>();
      final fuzzyValue = options['fuzzy'];
      final fuzzy = fuzzyValue == 'auto'
          ? TextMatch.fuzzyPolicyForToken(item['query'] as String)
          : fuzzyValue is Map
          ? FuzzyPolicy(
              maxEdits: (fuzzyValue['maxEdits'] as num).toInt(),
              transpositionsOnly: fuzzyValue['transpositionsOnly'] as bool,
            )
          : null;
      expect(
        TextMatch.score(
          item['query'] as String,
          item['text'] as String,
          fuzzy: fuzzy,
          subsequence: options['subsequence'] as bool? ?? true,
        ),
        _scoreFromJson(item['expect']),
      );
    });
  }

  for (final item in (fixture['policy'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test('policy: ${item['token']}', () {
      final expected = item['expect'];
      expect(
        TextMatch.fuzzyPolicyForToken(item['token'] as String),
        expected == null
            ? null
            : FuzzyPolicy(
                maxEdits: (expected['maxEdits'] as num).toInt(),
                transpositionsOnly: expected['transpositionsOnly'] as bool,
              ),
      );
    });
  }

  for (final item in (fixture['textFields'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test(item['name'] as String, () {
      final options = (item['options'] as Map).cast<String, dynamic>();
      expect(
        TextMatch.scoreTextFields(
          item['query'] as String,
          (item['fields'] as List<dynamic>).cast<String>(),
          typoTolerant: options['typoTolerant'] as bool? ?? false,
          subsequence: options['subsequence'] as bool? ?? true,
        ),
        _scoreFromJson(item['expect']),
      );
    });
  }

  for (final item in (fixture['ranges'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test(item['name'] as String, () {
      final query = item['query'] as String;
      final text = item['text'] as String;
      final score = TextMatch.score(query, text, fuzzy: TextMatch.fuzzyPolicyForToken(query));
      expect(score, isNotNull);
      expect(
        TextMatch.ranges(query, text, score!),
        (item['expect'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((range) => MatchRange(start: (range['start'] as num).toInt(), length: (range['length'] as num).toInt()))
            .toList(),
      );
    });
  }
}

MatchScore? _scoreFromJson(Object? value) {
  if (value == null) return null;
  final json = (value as Map).cast<String, dynamic>();
  return MatchScore(
    tier: (json['tier'] as num).toInt(),
    offset: (json['offset'] as num).toInt(),
    spread: (json['spread'] as num?)?.toInt(),
  );
}
