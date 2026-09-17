import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';

void main() {
  test('reads activity from a session_updated change payload', () {
    final patch = SessionPatch.fromChangePayload('s-7', {'id': 's-7', 'activity': 'active', 'isTerminated': false});

    expect(patch, const SessionPatch(id: 's-7', activity: 'active'));
  });

  test('a terminated session reads as status terminated', () {
    final patch = SessionPatch.fromChangePayload('s-7', {'id': 's-7', 'activity': 'exited', 'isTerminated': true});

    expect(patch?.status, 'terminated');
  });

  test('a payload without activity yields no patch', () {
    expect(SessionPatch.fromChangePayload('s-7', {'id': 's-7'}), isNull);
    expect(SessionPatch.fromChangePayload('s-7', null), isNull);
  });
}
