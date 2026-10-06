import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('put then readAll round-trips every row', () async {
    await db.settingsDao.put('theme.mode', 'dark');
    await db.settingsDao.put('session.view.s-1', 'raw');

    expect(await db.settingsDao.readAll(), {'theme.mode': 'dark', 'session.view.s-1': 'raw'});
  });

  test('put overwrites an existing key', () async {
    await db.settingsDao.put('theme.mode', 'dark');
    await db.settingsDao.put('theme.mode', 'light');

    expect(await db.settingsDao.readAll(), {'theme.mode': 'light'});
  });
}
