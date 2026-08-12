import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServerConfigStore implements ServerConfigSource {
  ServerConfigStore(this._secureStorage, this._preferences);

  static const _hostKey = 'server.host';
  static const _portKey = 'server.httpPort';
  static const _secureKey = 'server.secure';
  static const _passwordKey = 'server.password';

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _preferences;

  ServerConfig? _current;

  @override
  ServerConfig? get current => _current;

  Future<void> load() async {
    final host = _preferences.getString(_hostKey);
    final httpPort = _preferences.getString(_portKey);
    final password = await _secureStorage.read(key: _passwordKey);
    if (host == null || httpPort == null || password == null) return;

    _current = ServerConfig(
      host: host,
      httpPort: httpPort,
      secure: _preferences.getBool(_secureKey) ?? false,
      password: password,
    );
  }

  Future<void> save(ServerConfig config) async {
    _current = config;
    await _preferences.setString(_hostKey, config.host);
    await _preferences.setString(_portKey, config.httpPort);
    await _preferences.setBool(_secureKey, config.secure);
    await _secureStorage.write(key: _passwordKey, value: config.password);
  }

  Future<void> clear() async {
    _current = null;
    await _preferences.remove(_hostKey);
    await _preferences.remove(_portKey);
    await _preferences.remove(_secureKey);
    await _secureStorage.delete(key: _passwordKey);
  }
}
