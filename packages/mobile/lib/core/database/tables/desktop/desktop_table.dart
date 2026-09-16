import 'package:drift/drift.dart';

@DataClassName('DesktopEntity')
class Desktops extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get host => text()();
  TextColumn get port => text()();
  BoolColumn get secure => boolean()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  BoolColumn get renamed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastConnectedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {host, port, secure},
  ];
}
