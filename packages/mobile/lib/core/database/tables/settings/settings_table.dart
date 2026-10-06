import 'package:drift/drift.dart';

@DataClassName('SettingEntity')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
