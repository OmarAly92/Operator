// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'replica_document_dao.dart';

// ignore_for_file: type=lint
mixin _$ReplicaDocumentDaoMixin on DatabaseAccessor<AppDatabase> {
  $ReplicaDocumentsTable get replicaDocuments =>
      attachedDatabase.replicaDocuments;
  ReplicaDocumentDaoManager get managers => ReplicaDocumentDaoManager(this);
}

class ReplicaDocumentDaoManager {
  final _$ReplicaDocumentDaoMixin _db;
  ReplicaDocumentDaoManager(this._db);
  $$ReplicaDocumentsTableTableManager get replicaDocuments =>
      $$ReplicaDocumentsTableTableManager(
        _db.attachedDatabase,
        _db.replicaDocuments,
      );
}
