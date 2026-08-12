import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';

void main() {
  test('parses a mux sessions-snapshot entry', () {
    final patch = SessionPatch.fromJson({
      'id': 'proj-7',
      'status': 'working',
      'activity': 'active',
      'attentionLevel': 'working',
      'lastActivityAt': '2026-08-12T10:00:00Z',
    });

    expect(patch.id, 'proj-7');
    expect(patch.status, 'working');
    expect(patch.activity, 'active');
    expect(patch.attentionLevel, 'working');
    expect(patch.lastActivityAt, '2026-08-12T10:00:00Z');
  });

  test('tolerates a null activity', () {
    final patch = SessionPatch.fromJson({
      'id': 'proj-7',
      'status': 'idle',
      'activity': null,
      'attentionLevel': 'working',
      'lastActivityAt': '2026-08-12T10:00:00Z',
    });

    expect(patch.activity, isNull);
  });

  test('two patches with the same fields are equal', () {
    Map<String, dynamic> json() => {
      'id': 'proj-7',
      'status': 'working',
      'activity': 'active',
      'attentionLevel': 'working',
      'lastActivityAt': '2026-08-12T10:00:00Z',
    };
    expect(SessionPatch.fromJson(json()), SessionPatch.fromJson(json()));
  });
}
