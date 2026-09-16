import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/pairing/logic/relative_label.dart';

void main() {
  final now = DateTime(2026, 9, 16, 12);

  test('never connected', () => expect(relativeLabel(null, now), 'not connected yet'));
  test('just now', () => expect(relativeLabel(now.subtract(const Duration(seconds: 30)), now), 'just now'));
  test('minutes', () => expect(relativeLabel(now.subtract(const Duration(minutes: 5)), now), '5m ago'));
  test('hours', () => expect(relativeLabel(now.subtract(const Duration(hours: 2)), now), '2h ago'));
  test('days', () => expect(relativeLabel(now.subtract(const Duration(days: 3)), now), '3d ago'));
  test('weeks and beyond', () => expect(relativeLabel(now.subtract(const Duration(days: 20)), now), '2w ago'));
}
