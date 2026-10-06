// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'desktop_dao.dart';

// ignore_for_file: type=lint
mixin _$DesktopDaoMixin on DatabaseAccessor<AppDatabase> {
  $DesktopsTable get desktops => attachedDatabase.desktops;
  $ReplicaDocumentsTable get replicaDocuments =>
      attachedDatabase.replicaDocuments;
  $ReplicaBlockEventsTable get replicaBlockEvents =>
      attachedDatabase.replicaBlockEvents;
  DesktopDaoManager get managers => DesktopDaoManager(this);
}

class DesktopDaoManager {
  final _$DesktopDaoMixin _db;
  DesktopDaoManager(this._db);
  $$DesktopsTableTableManager get desktops =>
      $$DesktopsTableTableManager(_db.attachedDatabase, _db.desktops);
  $$ReplicaDocumentsTableTableManager get replicaDocuments =>
      $$ReplicaDocumentsTableTableManager(
        _db.attachedDatabase,
        _db.replicaDocuments,
      );
  $$ReplicaBlockEventsTableTableManager get replicaBlockEvents =>
      $$ReplicaBlockEventsTableTableManager(
        _db.attachedDatabase,
        _db.replicaBlockEvents,
      );
}
