import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/session_activity.dart';

void main() {
  test('only an active session is working', () {
    expect(sessionIsWorking('active'), isTrue);
    expect(sessionIsWorking('idle'), isFalse);
    expect(sessionIsWorking('blocked'), isFalse);
    expect(sessionIsWorking(null), isFalse);
  });

  test('only a blocked session is waiting', () {
    expect(sessionIsWaiting('blocked'), isTrue);
    expect(sessionIsWaiting('active'), isFalse);
    expect(sessionIsWaiting(null), isFalse);
  });
}
