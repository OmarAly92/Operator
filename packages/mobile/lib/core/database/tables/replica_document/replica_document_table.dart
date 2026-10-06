import 'package:drift/drift.dart';

@DataClassName('ReplicaDocumentEntity')
class ReplicaDocuments extends Table {
  TextColumn get desktopId => text()();
  TextColumn get key => text()();
  TextColumn get body => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {desktopId, key};
}
