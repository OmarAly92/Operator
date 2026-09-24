import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/active_since.dart';

void main() {
  const since = '2026-09-23T12:00:00Z';

  test('an active session starts its clock when the daemon marked it active', () {
    const sessions = [
      SessionModel(id: 'other', activity: 'active', activitySince: '2026-09-23T11:00:00Z'),
      SessionModel(id: 's-1', activity: 'active', activitySince: since),
    ];
    expect(activeSince(sessions, 's-1'), DateTime.parse(since));
  });

  test('a session that is not active has no clock', () {
    const sessions = [SessionModel(id: 's-1', activity: 'idle', activitySince: since)];
    expect(activeSince(sessions, 's-1'), isNull);
  });

  test('an unknown session or a missing timestamp has no clock', () {
    const sessions = [SessionModel(id: 's-1', activity: 'active')];
    expect(activeSince(sessions, 's-1'), isNull);
    expect(activeSince(sessions, 'missing'), isNull);
  });
}
