import 'package:drift/drift.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_table.dart';
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_table.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_table.dart';
import 'package:operator_mobile/core/error_handling/drift_error_handler/drift_error_handler.dart';

part 'desktop_dao.g.dart';

@DriftAccessor(tables: [Desktops, ReplicaDocuments, ReplicaBlockEvents])
class DesktopDao extends DatabaseAccessor<AppDatabase> with _$DesktopDaoMixin {
  DesktopDao(super.db);

  Stream<List<DesktopEntity>> watchAll() => (select(desktops)..orderBy(_order)).watch().handleLocalFailure();

  Future<List<DesktopEntity>> getAll() => (select(desktops)..orderBy(_order)).get().handleLocalFailure();

  Future<DesktopEntity?> getActive() =>
      (select(desktops)..where((t) => t.isActive.equals(true))).getSingleOrNull().handleLocalFailure();

  Future<DesktopEntity?> findByEndpoint(String host, String port, bool secure) =>
      (select(desktops)..where((t) => t.host.equals(host) & t.port.equals(port) & t.secure.equals(secure)))
          .getSingleOrNull()
          .handleLocalFailure();

  Future<String> upsert(DesktopsCompanion row) => transaction(() async {
    final existing = await findByEndpoint(row.host.value, row.port.value, row.secure.value);
    if (existing == null) {
      await into(desktops).insert(row);
      return row.id.value;
    }
    if (!existing.renamed) {
      await (update(desktops)..where((t) => t.id.equals(existing.id))).write(DesktopsCompanion(name: row.name));
    }
    return existing.id;
  }).handleLocalFailure();

  Future<void> setActive(String id) => transaction(() async {
    await update(desktops).write(const DesktopsCompanion(isActive: Value(false)));
    await (update(desktops)..where((t) => t.id.equals(id))).write(
      DesktopsCompanion(isActive: const Value(true), lastConnectedAt: Value(DateTime.now())),
    );
  }).handleLocalFailure();

  Future<void> clearActive() =>
      update(desktops).write(const DesktopsCompanion(isActive: Value(false))).handleLocalFailure();

  Future<void> refreshName(String id, String name) =>
      (update(desktops)..where((t) => t.id.equals(id) & t.renamed.equals(false)))
          .write(DesktopsCompanion(name: Value(name)))
          .handleLocalFailure();

  Future<void> rename(String id, String name) => (update(desktops)..where((t) => t.id.equals(id)))
      .write(DesktopsCompanion(name: Value(name), renamed: const Value(true)))
      .handleLocalFailure();

  Future<void> remove(String id) => transaction(() async {
    await (delete(replicaDocuments)..where((t) => t.desktopId.equals(id))).go();
    await (delete(replicaBlockEvents)..where((t) => t.desktopId.equals(id))).go();
    await (delete(desktops)..where((t) => t.id.equals(id))).go();
  }).handleLocalFailure();

  static final List<OrderingTerm Function($DesktopsTable)> _order = [
    (t) => OrderingTerm.desc(t.isActive),
    (t) => OrderingTerm.desc(t.lastConnectedAt),
    (t) => OrderingTerm.desc(t.createdAt),
  ];
}
