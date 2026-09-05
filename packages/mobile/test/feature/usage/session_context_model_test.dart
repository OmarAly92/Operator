import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/usage/data/model/session_context_model.dart';

void main() {
  group('SessionContextModel', () {
    test('parses a Codex context with a known window', () {
      final model = SessionContextModel.fromJson(const {
        'harness': 'codex',
        'modelId': 'gpt-5.6-luna',
        'used': 25000,
        'window': 200000,
        'observedAt': '2026-09-05T12:05:00Z',
      });
      expect(model.used, 25000);
      expect(model.window, 200000);
      expect(model.fraction, closeTo(0.125, 0.0001));
      expect(model.hasWindow, isTrue);
    });

    test('treats a zero window as unknown, not as an empty context', () {
      final model = SessionContextModel.fromJson(const {
        'harness': 'claude-code',
        'used': 64880,
        'window': 0,
      });
      expect(model.hasWindow, isFalse);
      expect(model.fraction, isNull);
    });

    test('tolerates missing fields', () {
      final model = SessionContextModel.fromJson(const {});
      expect(model.used, isNull);
      expect(model.hasWindow, isFalse);
      expect(model.fraction, isNull);
    });
  });
}
