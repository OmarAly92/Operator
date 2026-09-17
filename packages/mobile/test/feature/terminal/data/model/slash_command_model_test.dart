import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/data/model/slash_command_model.dart';

void main() {
  test('listFromJson reads the commands envelope', () {
    final list = SlashCommandModel.listFromJson({
      'commands': [
        {'name': 'compact', 'description': 'Keep a summary', 'source': 'builtin', 'interactive': false},
        {'name': 'model', 'description': 'Pick a model', 'source': 'builtin', 'interactive': true},
        {'name': 'sc:analyze', 'description': 'Analyze', 'source': 'user'},
      ],
    });

    expect(list, hasLength(3));
    expect(list[0], const SlashCommandModel(name: 'compact', description: 'Keep a summary', source: 'builtin', interactive: false));
    expect(list[1].interactive, isTrue);
    expect(list[2].interactive, isNull);
  });

  test('a missing commands key is an empty list', () {
    expect(SlashCommandModel.listFromJson({}), isEmpty);
  });
}
