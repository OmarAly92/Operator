import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_dao.dart';

void main() {
  late AppDatabase db;
  late ReplicaDocumentDao dao;
  final at = DateTime.utc(2026, 9, 25, 9);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = db.replicaDocumentDao;
  });

  tearDown(() => db.close());

  test('read returns only the asked keys of that desktop', () async {
    await dao.write('a', {'board.sessions': '{"sessions":[]}', 'board.projects': '{"projects":[]}'}, at);
    await dao.write('b', {'board.sessions': '{"sessions":[1]}'}, at);

    final rows = await dao.read('a', ['board.sessions']);

    expect(rows.single.body, '{"sessions":[]}');
    expect(rows.single.fetchedAt.isAtSameMomentAs(at), isTrue);
  });

  test('write replaces the body and fetchedAt of an existing key', () async {
    await dao.write('a', {'board.sessions': '{"v":1}'}, at);
    final later = at.add(const Duration(minutes: 5));
    await dao.write('a', {'board.sessions': '{"v":2}'}, later);

    final row = (await dao.read('a', ['board.sessions'])).single;

    expect(row.body, '{"v":2}');
    expect(row.fetchedAt.isAtSameMomentAs(later), isTrue);
  });

  test('remove deletes only the named keys of that desktop', () async {
    await dao.write('a', {'board.sessions': '{}', 'notifications.first': '{}'}, at);
    await dao.write('b', {'board.sessions': '{}'}, at);

    await dao.remove('a', ['board.sessions']);

    expect((await dao.read('a', ['board.sessions', 'notifications.first'])).map((row) => row.key), ['notifications.first']);
    expect(await dao.read('b', ['board.sessions']), hasLength(1));
  });
}
