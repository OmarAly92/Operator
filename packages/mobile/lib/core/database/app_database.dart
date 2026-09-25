import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_dao.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_table.dart';
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_dao.dart';
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_table.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_dao.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_table.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_dao.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_table.dart';
import 'package:operator_mobile/core/helpers/logging/app_logger.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Desktops, Settings, ReplicaDocuments, ReplicaBlockEvents],
  daos: [DesktopDao, SettingsDao, ReplicaDocumentDao, ReplicaBlockEventDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({this._onWipe}) : super(driftDatabase(name: 'operator_mobile'));

  AppDatabase.forTesting(super.executor, {this._onWipe});

  final Future<void> Function()? _onWipe;

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _wipeSecrets();
    },
    onUpgrade: (m, from, to) async {
      for (final table in allTables) {
        await m.deleteTable(table.actualTableName);
      }
      await m.createAll();
      await _wipeSecrets();
    },
  );

  Future<void> _wipeSecrets() async {
    final wipe = _onWipe;
    if (wipe == null) return;
    try {
      await wipe();
    } catch (error, stackTrace) {
      AppLogger.warning('Could not clear saved desktop passwords', exception: error, stackTrace: stackTrace);
    }
  }

  @override
  DriftDatabaseOptions get options => const DriftDatabaseOptions(storeDateTimeAsText: true);
}
