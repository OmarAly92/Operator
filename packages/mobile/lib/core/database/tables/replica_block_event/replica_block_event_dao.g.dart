// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'replica_block_event_dao.dart';

// ignore_for_file: type=lint
mixin _$ReplicaBlockEventDaoMixin on DatabaseAccessor<AppDatabase> {
  $ReplicaBlockEventsTable get replicaBlockEvents =>
      attachedDatabase.replicaBlockEvents;
  ReplicaBlockEventDaoManager get managers => ReplicaBlockEventDaoManager(this);
}

class ReplicaBlockEventDaoManager {
  final _$ReplicaBlockEventDaoMixin _db;
  ReplicaBlockEventDaoManager(this._db);
  $$ReplicaBlockEventsTableTableManager get replicaBlockEvents =>
      $$ReplicaBlockEventsTableTableManager(
        _db.attachedDatabase,
        _db.replicaBlockEvents,
      );
}
