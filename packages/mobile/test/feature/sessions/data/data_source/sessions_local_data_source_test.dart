import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_local_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';

void main() {
  late AppDatabase db;
  late SessionsLocalDataSourceImp source;
  final at = DateTime.utc(2026, 9, 25, 9);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    source = SessionsLocalDataSourceImp(db.replicaDocumentDao);
  });

  tearDown(() => db.close());

  test('writeBoard then readBoard round-trips the three bodies and when they were fetched', () async {
    const payload = BoardPayload(
      sessions: {'sessions': [{'id': 'w-1'}]},
      projects: {'projects': [{'id': 'p'}]},
      accounts: {'accounts': [{'id': 'default'}]},
    );

    await source.writeBoard('a', payload, at);
    final stored = await source.readBoard('a');

    expect(stored!.value, payload);
    expect(stored.fetchedAt.isAtSameMomentAs(at), isTrue);
  });

  test('a desktop with nothing stored reads as a miss', () async {
    expect(await source.readBoard('a'), isNull);
  });

  test('a write without projects keeps the projects stored earlier', () async {
    await source.writeBoard('a', const BoardPayload(sessions: {'sessions': []}, projects: {'projects': [{'id': 'p'}]}), at);
    await source.writeBoard('a', const BoardPayload(sessions: {'sessions': [{'id': 'w-2'}]}), at);

    final stored = await source.readBoard('a');

    expect(stored!.value.projects, {'projects': [{'id': 'p'}]});
    expect(stored.value.sessions, {'sessions': [{'id': 'w-2'}]});
  });

  test('deleteBoard removes every board body of that desktop', () async {
    await source.writeBoard('a', const BoardPayload(sessions: {'sessions': []}, projects: {'projects': []}), at);

    await source.deleteBoard('a');

    expect(await source.readBoard('a'), isNull);
  });

  test('a body that is not JSON throws for the repository to drop', () async {
    await db.replicaDocumentDao.write('a', {'board.sessions': 'not json'}, at);

    expect(() => source.readBoard('a'), throwsA(isA<FormatException>()));
  });
}
