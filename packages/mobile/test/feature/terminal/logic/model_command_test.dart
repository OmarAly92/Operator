import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/model_command.dart';

void main() {
  test('bare /model opens the picker', () {
    expect(parseModelCommand('/model')?.label, isNull);
    expect(parseModelCommand('  /model  ')?.label, isNull);
  });

  test('/model with a label switches directly', () {
    expect(parseModelCommand('/model sonnet')?.label, 'sonnet');
    expect(parseModelCommand('/model  opus[1m] ')?.label, 'opus[1m]');
  });

  test('anything else is an ordinary message', () {
    expect(parseModelCommand('/models'), isNull);
    expect(parseModelCommand('/model a b'), isNull);
    expect(parseModelCommand('model'), isNull);
    expect(parseModelCommand('hi /model'), isNull);
  });
}
