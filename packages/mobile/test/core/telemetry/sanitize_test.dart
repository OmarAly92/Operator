import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/sanitize.dart';

const Map<String, Map<String, PropRule>> _countAllowlist = {
  'opr.v2.test.counted': {'items': CountRule()},
};

void main() {
  test('keeps allowlisted enum values and flags', () {
    expect(
      sanitizeMobileProperties(MobileEvents.paired, {
        'method': 'qr',
        'from_onboarding': true,
      }),
      {'method': 'qr', 'from_onboarding': true},
    );
  });

  test('drops an enum value outside the closed set', () {
    expect(sanitizeMobileProperties(MobileEvents.paired, {'method': 'nfc'}), isEmpty);
  });

  test('drops any unregistered key, so titles and secrets cannot leak', () {
    expect(
      sanitizeMobileProperties(MobileEvents.featureUsed, {
        'feature': 'spawn',
        'outcome': 'succeeded',
        'session_title': 'fix the auth bug in secret-repo',
        'project': 'acme/secret-repo',
        'password': 'hunter2',
        'terminal_tail': r'$ cat .env',
      }),
      {'feature': 'spawn', 'outcome': 'succeeded'},
    );
  });

  test('returns nothing for an unknown event rather than passing the payload through', () {
    expect(sanitizeMobileProperties('opr.v2.mobile_app.not_a_real_event', {'anything': 'x'}), isEmpty);
    expect(sanitizeMobileProperties(MobileEvents.active, null), isEmpty);
  });

  test('keeps a flag only when the value is a real boolean', () {
    expect(
      sanitizeMobileProperties(MobileEvents.notificationOpened, {
        'target': 'session',
        'cold_start': 'yes',
      }),
      {'target': 'session'},
    );
    expect(
      sanitizeMobileProperties(MobileEvents.notificationOpened, {
        'target': 'session',
        'cold_start': true,
      }),
      {'target': 'session', 'cold_start': true},
    );
  });

  test('keeps a non-negative integer count and drops negatives, doubles and strings', () {
    Map<String, dynamic> counted(Object? value) =>
        sanitizeMobileProperties('opr.v2.test.counted', {'items': value}, allowlist: _countAllowlist);

    expect(counted(0), {'items': 0});
    expect(counted(7), {'items': 7});
    expect(counted(-1), isEmpty);
    expect(counted(1.5), isEmpty);
    expect(counted('7'), isEmpty);
  });
}
