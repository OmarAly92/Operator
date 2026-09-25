import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_status_line.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';

void main() {
  final now = DateTime.utc(2026, 9, 25, 12);

  test('connecting shows a spinner', () {
    final line = connectionStatusLine(const ConnectionConnectingState(), now: now);
    expect(line.text, 'Connecting…');
    expect(line.busy, isTrue);
    expect(line.tone, StatusTone.neutral);
  });

  test('online reads updated just now, then minutes once the data is over a minute old', () {
    expect(
      connectionStatusLine(ConnectionOnlineState(updatedAt: now.subtract(const Duration(seconds: 40))), now: now).text,
      'Updated just now',
    );
    expect(
      connectionStatusLine(ConnectionOnlineState(updatedAt: now.subtract(const Duration(minutes: 5))), now: now).text,
      'Updated 5m ago',
    );
    expect(
      connectionStatusLine(ConnectionOnlineState(updatedAt: now.subtract(const Duration(hours: 3))), now: now).text,
      'Updated 3h ago',
    );
  });

  test('offline names when the desktop was last seen, falling back to the cached board time', () {
    final seen = ConnectionOfflineState(
      reason: ConnectionFailure.unreachable,
      lastSeenAt: now.subtract(const Duration(minutes: 5)),
    );
    final line = connectionStatusLine(seen, now: now);
    expect(line.text, 'Offline · last seen 5m ago');
    expect(line.tone, StatusTone.attention);

    const coldStart = ConnectionOfflineState(reason: ConnectionFailure.unreachable);
    expect(
      connectionStatusLine(coldStart, now: now, fetchedAt: now.subtract(const Duration(days: 2))).text,
      'Offline · last seen 2d ago',
    );
    expect(connectionStatusLine(coldStart, now: now).text, 'Offline');
  });

  test('auth failure asks for re-pairing in red', () {
    final line = connectionStatusLine(const ConnectionAuthFailedState(episode: 1), now: now);
    expect(line.text, 'Needs re-pairing');
    expect(line.tone, StatusTone.danger);
  });
}
