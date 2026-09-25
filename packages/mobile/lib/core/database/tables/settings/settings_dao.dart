import 'package:drift/drift.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_table.dart';
import 'package:operator_mobile/core/error_handling/drift_error_handler/drift_error_handler.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<Map<String, String>> readAll() async {
    final rows = await select(settings).get().handleLocalFailure();
    return {for (final row in rows) row.key: row.value};
  }

  Future<void> put(String key, String value) => into(settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value))
      .handleLocalFailure();
}
