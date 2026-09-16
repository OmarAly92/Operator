import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_dao.dart';

DesktopsCompanion _row(String id, {String host = '192.168.1.2', String name = 'Mac'}) => DesktopsCompanion.insert(
  id: id,
  name: name,
  host: host,
  port: '58682',
  secure: false,
);

void main() {
  late AppDatabase db;
  late DesktopDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = db.desktopDao;
  });

  tearDown(() => db.close());

  test('upsert inserts a new endpoint and returns its id', () async {
    final id = await dao.upsert(_row('a'));
    expect(id, 'a');
    expect(await dao.getAll(), hasLength(1));
  });

  test('upsert on an existing endpoint keeps the row and refreshes the name', () async {
    await dao.upsert(_row('a', name: 'Old'));
    final id = await dao.upsert(_row('b', name: 'New'));
    expect(id, 'a');
    final all = await dao.getAll();
    expect(all.single.name, 'New');
  });

  test('upsert keeps a user rename', () async {
    await dao.upsert(_row('a', name: 'Old'));
    await dao.rename('a', 'Mine');
    await dao.upsert(_row('b', name: 'New'));
    expect((await dao.getAll()).single.name, 'Mine');
  });

  test('setActive leaves exactly one active row and stamps lastConnectedAt', () async {
    await dao.upsert(_row('a', host: '1.1.1.1'));
    await dao.upsert(_row('b', host: '2.2.2.2'));
    await dao.setActive('a');
    await dao.setActive('b');
    final active = await dao.getActive();
    expect(active?.id, 'b');
    expect(active?.lastConnectedAt, isNotNull);
    expect((await dao.getAll()).where((d) => d.isActive), hasLength(1));
  });

  test('clearActive leaves no active row', () async {
    await dao.upsert(_row('a'));
    await dao.setActive('a');
    await dao.clearActive();
    expect(await dao.getActive(), isNull);
  });

  test('watchAll orders active first, then most recently connected', () async {
    await dao.upsert(_row('a', host: '1.1.1.1'));
    await dao.upsert(_row('b', host: '2.2.2.2'));
    await dao.upsert(_row('c', host: '3.3.3.3'));
    await dao.setActive('b');
    await dao.setActive('c');
    await dao.setActive('a');
    await dao.clearActive();
    await dao.setActive('b');
    final ids = (await dao.watchAll().first).map((d) => d.id).toList();
    expect(ids.first, 'b');
    expect(ids, ['b', 'a', 'c']);
  });

  test('delete removes the row', () async {
    await dao.upsert(_row('a'));
    await dao.remove('a');
    expect(await dao.getAll(), isEmpty);
  });
}
