import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_dao.dart';
import 'package:operator_mobile/core/replica/replica_limits.dart';

Map<int, String> _events(int from, int to) => {for (var seq = from; seq <= to; seq++) seq: '{"seq":$seq}'};

void main() {
  late AppDatabase db;
  late ReplicaBlockEventDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = db.replicaBlockEventDao;
  });

  tearDown(() => db.close());

  test('latest returns the session rows oldest first', () async {
    await dao.write('a', 's', {3: '{"seq":3}', 1: '{"seq":1}', 2: '{"seq":2}'});

    expect((await dao.latest('a', 's')).map((row) => row.seq), [1, 2, 3]);
  });

  test('keeps only the newest 200 events of a session', () async {
    await dao.write('a', 's', _events(1, 250));

    final kept = await dao.latest('a', 's');
    expect(kept, hasLength(ReplicaLimits.blockEventsPerSession));
    expect(kept.first.seq, 51);
    expect(kept.last.seq, 250);

    await dao.write('a', 's', _events(251, 260));

    final after = await dao.latest('a', 's');
    expect(after, hasLength(ReplicaLimits.blockEventsPerSession));
    expect(after.first.seq, 61);
    expect(after.last.seq, 260);
  });

  test('an event older than the kept window is trimmed on the write that adds it', () async {
    await dao.write('a', 's', _events(1, 200));
    await dao.write('a', 's', {0: '{"seq":0}'});

    final kept = await dao.latest('a', 's');
    expect(kept.first.seq, 1);
    expect(kept, hasLength(ReplicaLimits.blockEventsPerSession));
  });

  test('trimming one session leaves other sessions and desktops alone', () async {
    await dao.write('a', 'other', _events(1, 5));
    await dao.write('b', 's', _events(1, 5));
    await dao.write('a', 's', _events(1, 250));

    expect(await dao.latest('a', 'other'), hasLength(5));
    expect(await dao.latest('b', 's'), hasLength(5));
  });

  test('write replaces the body of an existing seq', () async {
    await dao.write('a', 's', {1: '{"seq":1,"text":"old"}'});
    await dao.write('a', 's', {1: '{"seq":1,"text":"new"}'});

    expect((await dao.latest('a', 's')).single.body, '{"seq":1,"text":"new"}');
  });

  test('removeSession deletes that session only', () async {
    await dao.write('a', 's', _events(1, 3));
    await dao.write('a', 't', _events(1, 3));

    await dao.removeSession('a', 's');

    expect(await dao.latest('a', 's'), isEmpty);
    expect(await dao.latest('a', 't'), hasLength(3));
  });
}
