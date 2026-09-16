import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';

class ServerConfigStore implements ServerConfigSource {
  ServerConfigStore(this._desktops);

  final DesktopsLocalDataSource _desktops;

  ServerConfig? _current;

  @override
  ServerConfig? get current => _current;

  Future<void> load() async {
    final active = await _desktops.getActive();
    if (active?.id == null) return;
    final password = await _desktops.passwordFor(active!.id!);
    if (password == null) return;
    _current = active.toServerConfig(password);
  }

  void set(ServerConfig config) => _current = config;

  void clear() => _current = null;
}
