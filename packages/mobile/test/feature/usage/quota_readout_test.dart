import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/usage/data/model/usage_quota_model.dart';
import 'package:operator_mobile/feature/usage/logic/quota_readout.dart';

void main() {
  test('labels the windows from their length', () {
    expect(QuotaReadout.of(const UsageQuotaWindowModel(windowMinutes: 300, usedPercent: 77))!.label, '5-hour window');
    expect(QuotaReadout.of(const UsageQuotaWindowModel(windowMinutes: 10080, usedPercent: 12))!.label, 'Weekly');
  });

  test('renders a stale window as unknown with no percentage', () {
    final r = QuotaReadout.of(const UsageQuotaWindowModel(windowMinutes: 300, usedPercent: 77, stale: true))!;
    expect(r.percentLabel, isNull);
    expect(r.fraction, isNull);
    expect(r.isUnknown, isTrue);
  });

  test('keeps a fresh reading', () {
    final r = QuotaReadout.of(const UsageQuotaWindowModel(windowMinutes: 300, usedPercent: 77))!;
    expect(r.percentLabel, '77%');
    expect(r.fraction, closeTo(0.77, 0.0001));
    expect(r.isUnknown, isFalse);
  });

  test('zero percent is a reading, not an absence', () {
    final r = QuotaReadout.of(const UsageQuotaWindowModel(windowMinutes: 300, usedPercent: 0))!;
    expect(r.percentLabel, '0%');
    expect(r.isUnknown, isFalse);
  });

  test('renders nothing without a window', () {
    expect(QuotaReadout.of(null), isNull);
  });
}
