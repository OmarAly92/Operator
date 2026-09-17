import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/block_question.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

const _input =
    '{"questions":[{"question":"Which branch?","header":"Branch","multiSelect":false,'
    '"options":[{"label":"main","description":"the default branch"},'
    '{"label":"develop","description":"the integration branch"}]}]}';

void main() {
  _answerTests();
  test('parses the AskUserQuestion input into questions and options', () {
    final detail = parseQuestionDetail(_input);

    expect(detail, isNotNull);
    expect(detail!.questions, hasLength(1));
    final question = detail.questions.first;
    expect(question.question, 'Which branch?');
    expect(question.header, 'Branch');
    expect(question.multiSelect, isFalse);
    expect(question.options.map((option) => option.label), ['main', 'develop']);
    expect(question.options.first.description, 'the default branch');
  });

  test('returns null for input that is not a question payload', () {
    expect(parseQuestionDetail(''), isNull);
    expect(parseQuestionDetail('not json'), isNull);
    expect(parseQuestionDetail('{"command":"ls"}'), isNull);
    expect(parseQuestionDetail('{"questions":[]}'), isNull);
  });

  test('a question detail is a BlockDetail', () {
    expect(parseQuestionDetail(_input), isA<BlockDetail>());
  });
}

void _answerTests() {
  const questions = [
    BlockQuestion(question: 'Which colour?', options: [BlockQuestionOption(label: 'Red'), BlockQuestionOption(label: 'Blue')]),
    BlockQuestion(question: 'Which sizes?', multiSelect: true, options: [BlockQuestionOption(label: 'S'), BlockQuestionOption(label: 'M'), BlockQuestionOption(label: 'L')]),
  ];

  group('parseQuestionAnswers', () {
    test('reads the chosen label for each question from the tool result', () {
      const result = 'Your questions have been answered: "Which colour?"="Blue", "Which sizes?"="S, L". You can now continue.';

      expect(parseQuestionAnswers(result, questions), {0: ['Blue'], 1: ['S', 'L']});
    });

    test('a label the question does not offer is kept verbatim', () {
      const result = 'Your questions have been answered: "Which colour?"="Green"';

      expect(parseQuestionAnswers(result, questions), {0: ['Green']});
    });

    test('an unrelated result yields nothing', () {
      expect(parseQuestionAnswers('Todos have been modified', questions), isEmpty);
      expect(parseQuestionAnswers('', questions), isEmpty);
    });
  });
}
