// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'desktop_dao.dart';

// ignore_for_file: type=lint
mixin _$DesktopDaoMixin on DatabaseAccessor<AppDatabase> {
  $DesktopsTable get desktops => attachedDatabase.desktops;
  DesktopDaoManager get managers => DesktopDaoManager(this);
}

class DesktopDaoManager {
  final _$DesktopDaoMixin _db;
  DesktopDaoManager(this._db);
  $$DesktopsTableTableManager get desktops =>
      $$DesktopsTableTableManager(_db.attachedDatabase, _db.desktops);
}
