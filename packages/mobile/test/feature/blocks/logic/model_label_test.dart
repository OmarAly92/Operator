import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/model_label.dart';

void main() {
  test('claude model ids become short labels', () {
    expect(formatModelLabel('claude-sonnet-5'), 'Sonnet 5');
    expect(formatModelLabel('claude-opus-5[1m]'), 'Opus 5 (1M)');
    expect(formatModelLabel('claude-fable-5-1'), 'Fable 5.1');
    expect(formatModelLabel('claude-haiku-4-5-20251001'), 'Haiku 4.5');
  });

  test('anything else passes through', () {
    expect(formatModelLabel('gpt-5.6-sol'), 'gpt-5.6-sol');
    expect(formatModelLabel('Sonnet'), 'Sonnet');
    expect(formatModelLabel(''), '');
  });
}
