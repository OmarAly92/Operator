import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_dao.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/rename_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';

abstract class DesktopsLocalDataSource {
  Stream<List<DesktopModel>> watchAll();
  Future<DesktopModel?> getActive();
  Future<DesktopModel> save(SaveDesktopParams params);
  Future<void> activate(String id);
  Future<void> deactivate();
  Future<void> rename(RenameDesktopParams params);
  Future<void> remove(String id);
  Future<String?> passwordFor(String id);
}

class DesktopsLocalDataSourceImp implements DesktopsLocalDataSource {
  DesktopsLocalDataSourceImp(this._dao, this._secureStorage);

  final DesktopDao _dao;
  final FlutterSecureStorage _secureStorage;

  static String passwordKey(String id) => 'server.password.$id';

  @override
  Stream<List<DesktopModel>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map(DesktopModel.fromDB).toList());

  @override
  Future<DesktopModel?> getActive() async {
    final row = await _dao.getActive();
    return row == null ? null : DesktopModel.fromDB(row);
  }

  @override
  Future<DesktopModel> save(SaveDesktopParams params) async {
    final id = await _dao.upsert(
      DesktopsCompanion.insert(
        id: _newId(),
        name: params.name,
        host: params.host,
        port: params.port,
        secure: params.secure,
      ),
    );
    await _secureStorage.write(key: passwordKey(id), value: params.password);
    await _dao.setActive(id);
    final row = await _dao.getActive();
    return DesktopModel.fromDB(row!);
  }

  @override
  Future<void> activate(String id) => _dao.setActive(id);

  @override
  Future<void> deactivate() => _dao.clearActive();

  @override
  Future<void> rename(RenameDesktopParams params) => _dao.rename(params.id, params.name);

  @override
  Future<void> remove(String id) async {
    await _dao.remove(id);
    await _secureStorage.delete(key: passwordKey(id));
  }

  @override
  Future<String?> passwordFor(String id) => _secureStorage.read(key: passwordKey(id));

  static String _newId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
