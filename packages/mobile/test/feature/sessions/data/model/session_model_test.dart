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
  });
}
