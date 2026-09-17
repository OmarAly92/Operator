import 'dart:convert';

import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

QuestionBlockDetail? parseQuestionDetail(String toolInput) {
  if (toolInput.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(toolInput);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final raw = decoded['questions'];
  if (raw is! List || raw.isEmpty) return null;

  final questions = <BlockQuestion>[];
  for (final item in raw) {
    if (item is! Map<String, dynamic>) continue;
    final options = <BlockQuestionOption>[];
    final rawOptions = item['options'];
    if (rawOptions is List) {
      for (final option in rawOptions) {
        if (option is! Map<String, dynamic>) continue;
        options.add(
          BlockQuestionOption(
            label: option['label'] as String?,
            description: option['description'] as String?,
          ),
        );
      }
    }
    questions.add(
      BlockQuestion(
        question: item['question'] as String?,
        header: item['header'] as String?,
        multiSelect: item['multiSelect'] as bool?,
        options: options,
      ),
    );
  }
  return questions.isEmpty ? null : QuestionBlockDetail(questions: questions);
}

final _answerPair = RegExp(r'"((?:[^"\\]|\\.)*)"="((?:[^"\\]|\\.)*)"');

Map<int, List<String>> parseQuestionAnswers(String result, List<BlockQuestion> questions) {
  final answers = <int, List<String>>{};
  for (final match in _answerPair.allMatches(result)) {
    final question = match.group(1)!;
    final index = questions.indexWhere((q) => q.question == question);
    if (index < 0) continue;
    answers[index] = _splitAnswer(match.group(2)!, questions[index]);
  }
  return answers;
}

List<String> _splitAnswer(String raw, BlockQuestion question) {
  final labels = question.options.map((option) => option.label ?? '').where((label) => label.isNotEmpty).toList();
  final chosen = labels.where((label) => raw.split(', ').contains(label)).toList();
  return chosen.isEmpty ? [raw] : chosen;
}
