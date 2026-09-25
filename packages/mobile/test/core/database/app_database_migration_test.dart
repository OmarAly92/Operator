import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';

const _v1Desktops =
    'CREATE TABLE "desktops" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "host" TEXT NOT NULL, "port" TEXT NOT NULL, '
    '"secure" INTEGER NOT NULL CHECK ("secure" IN (0, 1)), '
    '"is_active" INTEGER NOT NULL DEFAULT 0 CHECK ("is_active" IN (0, 1)), '
    '"renamed" INTEGER NOT NULL DEFAULT 0 CHECK ("renamed" IN (0, 1)), '
    '"last_connected_at" TEXT NULL, "created_at" TEXT NOT NULL, '
    'PRIMARY KEY ("id"), UNIQUE ("host", "port", "secure"))';

Future<List<String>> _tables(AppDatabase db) => db
    .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
    .map((row) => row.read<String>('name'))
    .get();

Future<int> _userVersion(AppDatabase db) =>
    db.customSelect('PRAGMA user_version').map((row) => row.read<int>('user_version')).getSingle();

void main() {
  test('a real v1 database is wiped to v2 and its saved passwords are purged', () async {
    var wipes = 0;
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(_v1Desktops);
          raw.execute(
            'INSERT INTO desktops (id, name, host, port, secure, is_active, renamed, last_connected_at, created_at) '
            "VALUES ('a', 'Mac', '10.0.0.5', '3011', 0, 1, 0, NULL, '2026-09-01T00:00:00.000')",
          );
          raw.execute('PRAGMA user_version = 1');
        },
      ),
      onWipe: () async => wipes++,
    );
    addTearDown(db.close);

    expect(await db.desktopDao.getAll(), isEmpty);
    expect(wipes, 1);
    expect(await _tables(db), containsAll(['desktops', 'settings', 'replica_documents', 'replica_block_events']));
    expect(await _userVersion(db), 2);
  });

  test('a fresh install creates every table and clears passwords an earlier install left behind', () async {
    var wipes = 0;
    final db = AppDatabase.forTesting(NativeDatabase.memory(), onWipe: () async => wipes++);
    addTearDown(db.close);

    expect(await _tables(db), containsAll(['desktops', 'settings', 'replica_documents', 'replica_block_events']));
    expect(wipes, 1);
  });

  test('a failing password purge still opens the database', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(),
      onWipe: () async => throw StateError('keychain locked'),
    );
    addTearDown(db.close);

    expect(await db.desktopDao.getAll(), isEmpty);
  });
}
