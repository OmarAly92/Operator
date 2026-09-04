import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/block_question.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

const _input =
    '{"questions":[{"question":"Which branch?","header":"Branch","multiSelect":false,'
    '"options":[{"label":"main","description":"the default branch"},'
    '{"label":"develop","description":"the integration branch"}]}]}';

void main() {
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
