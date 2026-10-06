import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';

void main() {
  test('fromPayload maps sessions, projects and account labels', () {
    final board = BoardSnapshot.fromPayload(
      const BoardPayload(
        sessions: {
          'sessions': [
            {'id': 'w-1', 'projectId': 'p'},
          ],
        },
        projects: {
          'projects': [
            {'id': 'p', 'name': 'Proj'},
          ],
        },
        accounts: {
          'accounts': [
            {'id': 'default', 'label': 'Default'},
            {'id': 'bare'},
          ],
        },
      ),
    );

    expect(board.sessions.single.id, 'w-1');
    expect(board.projects.single.name, 'Proj');
    expect(board.accountLabels, {'default': 'Default', 'bare': 'bare'});
  });

  test('missing or malformed projects and accounts degrade to empty', () {
    final board = BoardSnapshot.fromPayload(
      const BoardPayload(sessions: {'sessions': []}, projects: {'projects': 'nope'}),
    );

    expect(board.projects, isEmpty);
    expect(board.accountLabels, isEmpty);
  });

  test('malformed sessions throw so the caller can drop the body', () {
    expect(
      () => BoardSnapshot.fromPayload(const BoardPayload(sessions: {'sessions': 'nope'})),
      throwsA(isA<TypeError>()),
    );
  });
}
