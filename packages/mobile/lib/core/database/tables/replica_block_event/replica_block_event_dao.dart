import 'package:drift/drift.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_table.dart';
import 'package:operator_mobile/core/error_handling/drift_error_handler/drift_error_handler.dart';
import 'package:operator_mobile/core/replica/replica_limits.dart';

part 'replica_block_event_dao.g.dart';

@DriftAccessor(tables: [ReplicaBlockEvents])
class ReplicaBlockEventDao extends DatabaseAccessor<AppDatabase> with _$ReplicaBlockEventDaoMixin {
  ReplicaBlockEventDao(super.db);

  Future<List<ReplicaBlockEventEntity>> latest(String desktopId, String sessionId) async {
    final newestFirst = await (select(replicaBlockEvents)
          ..where((t) => t.desktopId.equals(desktopId) & t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.seq)])
          ..limit(ReplicaLimits.blockEventsPerSession))
        .get()
        .handleLocalFailure();
    return newestFirst.reversed.toList();
  }

  Future<void> write(String desktopId, String sessionId, Map<int, String> bodies) => transaction(() async {
    if (bodies.isEmpty) return;
    await batch((batch) {
      batch.insertAllOnConflictUpdate(replicaBlockEvents, [
        for (final entry in bodies.entries)
          ReplicaBlockEventsCompanion.insert(
            desktopId: desktopId,
            sessionId: sessionId,
            seq: entry.key,
            body: entry.value,
          ),
      ]);
    });
    final floor = await (select(replicaBlockEvents)
          ..where((t) => t.desktopId.equals(desktopId) & t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.seq)])
          ..limit(1, offset: ReplicaLimits.blockEventsPerSession - 1))
        .getSingleOrNull();
    if (floor == null) return;
    await (delete(replicaBlockEvents)
          ..where(
            (t) => t.desktopId.equals(desktopId) & t.sessionId.equals(sessionId) & t.seq.isSmallerThanValue(floor.seq),
          ))
        .go();
  }).handleLocalFailure();

  Future<void> removeSession(String desktopId, String sessionId) =>
      (delete(replicaBlockEvents)..where((t) => t.desktopId.equals(desktopId) & t.sessionId.equals(sessionId)))
          .go()
          .handleLocalFailure();
}
