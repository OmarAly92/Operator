import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_dao.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Desktops], daos: [DesktopDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'operator_mobile'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) => m.createAll());
}
