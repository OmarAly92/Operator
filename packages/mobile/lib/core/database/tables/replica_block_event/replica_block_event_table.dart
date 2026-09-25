import 'package:drift/drift.dart';

@DataClassName('ReplicaBlockEventEntity')
class ReplicaBlockEvents extends Table {
  TextColumn get desktopId => text()();
  TextColumn get sessionId => text()();
  IntColumn get seq => integer()();
  TextColumn get body => text()();

  @override
  Set<Column> get primaryKey => {desktopId, sessionId, seq};
}
