import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

void main() {
  group('SessionModel.fromJson', () {
    test('parses a payload with no kind key', () {
      final session = SessionModel.fromJson({'id': 'a', 'status': 'working'});
      expect(session.id, 'a');
      expect(session.status, 'working');
    });

    test('ignores a stale kind key from an older daemon', () {
      final session = SessionModel.fromJson({
        'id': 'a',
        'status': 'working',
        'kind': 'worker',
      });
      expect(session.id, 'a');
      expect(session.status, 'working');
    });

    test('parses the agent report and tolerates its absence', () {
      final reported = SessionModel.fromJson({
        'id': 'a',
        'status': 'needs_input',
        'agentReport': {'state': 'needs_you', 'reason': 'Postgres or SQLite?', 'at': '2026-09-24T12:00:00Z'},
      });
      expect(reported.agentReportState, 'needs_you');
      expect(reported.agentReportReason, 'Postgres or SQLite?');

      final plain = SessionModel.fromJson({'id': 'a', 'status': 'idle', 'agentReport': null});
      expect(plain.agentReportState, isNull);
      expect(plain.agentReportReason, isNull);
    });

    test('reads when the current activity state began', () {
      final session = SessionModel.fromJson({
        'id': 'a',
        'activity': {'state': 'active', 'lastActivityAt': '2026-09-23T12:00:00Z'},
      });
      expect(session.activity, 'active');
      expect(session.activitySince, '2026-09-23T12:00:00Z');
    });

    test('parses the permission mode and its capabilities, and tolerates their absence', () {
      final session = SessionModel.fromJson({
        'id': 'a',
        'permissionMode': 'plan',
        'capabilities': {
          'permissionMode': true,
          'permissionModeCycle': ['default', 'accept-edits', 'plan'],
        },
      });
      expect(session.permissionMode, 'plan');
      expect(session.permissionModeSupported, isTrue);
      expect(session.permissionModeCycle, ['default', 'accept-edits', 'plan']);

      final bare = SessionModel.fromJson({'id': 'b'});
      expect(bare.permissionMode, isNull);
      expect(bare.permissionModeSupported, isNull);
      expect(bare.permissionModeCycle, isNull);
    });
  });
}
