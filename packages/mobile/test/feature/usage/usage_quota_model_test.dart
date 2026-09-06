import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/usage/data/model/usage_quota_model.dart';

void main() {
  group('UsageQuotaModel', () {
    test('parses both windows', () {
      final m = UsageQuotaModel.fromJson(const {
        'harness': 'codex', 'limitId': 'codex', 'planType': 'plus',
        'observedAt': '2026-09-05T15:26:55Z',
        'windows': [
          {'kind': 'primary', 'windowMinutes': 300, 'usedPercent': 77, 'resetsAt': '2026-09-05T19:23:55Z', 'stale': false},
          {'kind': 'secondary', 'windowMinutes': 10080, 'usedPercent': 12, 'resetsAt': '2026-09-12T14:23:55Z', 'stale': false},
        ],
      });
      expect(m.windows, hasLength(2));
      expect(m.windows.first.usedPercent, 77);
      expect(m.windows.first.windowMinutes, 300);
      expect(m.planType, 'plus');
    });

    test('keeps a stale window rather than dropping it', () {
      final m = UsageQuotaModel.fromJson(const {
        'harness': 'codex',
        'windows': [
          {'kind': 'primary', 'windowMinutes': 300, 'usedPercent': 77, 'stale': true},
        ],
      });
      expect(m.windows.single.stale, isTrue);
      expect(m.windows.single.usedPercent, 77);
    });

    test('tolerates missing fields', () {
      final m = UsageQuotaModel.fromJson(const {});
      expect(m.windows, isEmpty);
      expect(m.planType, isNull);
    });
  });
}
