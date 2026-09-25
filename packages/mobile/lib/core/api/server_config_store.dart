import 'dart:async';

import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';

class ServerConfigStore implements ServerConfigSource {
  ServerConfigStore(this._desktops);

  final DesktopsLocalDataSource _desktops;
  final _changes = StreamController<ServerConfig?>.broadcast();

  ServerConfig? _current;

  @override
  ServerConfig? get current => _current;

  @override
  Stream<ServerConfig?> get changes => _changes.stream;

  Future<void> load() async {
    final active = await _desktops.getActive();
    if (active?.id == null) return;
    final password = await _desktops.passwordFor(active!.id!);
    if (password == null) return;
    _current = active.toServerConfig(password);
  }

  Stream<String?> get activeDesktopName => _desktops.watchAll().map((desktops) {
    for (final desktop in desktops) {
      if (desktop.isActive == true) return desktop.name;
    }
    return null;
  });

  void set(ServerConfig config) {
    _current = config;
    _changes.add(config);
  }

  void clear() {
    _current = null;
    _changes.add(null);
  }
}
