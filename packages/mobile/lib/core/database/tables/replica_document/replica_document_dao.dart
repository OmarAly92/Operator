import 'package:drift/drift.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_table.dart';
import 'package:operator_mobile/core/error_handling/drift_error_handler/drift_error_handler.dart';

part 'replica_document_dao.g.dart';

@DriftAccessor(tables: [ReplicaDocuments])
class ReplicaDocumentDao extends DatabaseAccessor<AppDatabase> with _$ReplicaDocumentDaoMixin {
  ReplicaDocumentDao(super.db);

  Future<List<ReplicaDocumentEntity>> read(String desktopId, List<String> keys) =>
      (select(replicaDocuments)..where((t) => t.desktopId.equals(desktopId) & t.key.isIn(keys)))
          .get()
          .handleLocalFailure();

  Future<void> write(String desktopId, Map<String, String> bodies, DateTime fetchedAt) => batch((batch) {
    batch.insertAllOnConflictUpdate(replicaDocuments, [
      for (final entry in bodies.entries)
        ReplicaDocumentsCompanion.insert(desktopId: desktopId, key: entry.key, body: entry.value, fetchedAt: fetchedAt),
    ]);
  }).handleLocalFailure();

  Future<void> remove(String desktopId, List<String> keys) =>
      (delete(replicaDocuments)..where((t) => t.desktopId.equals(desktopId) & t.key.isIn(keys)))
          .go()
          .handleLocalFailure();
}
