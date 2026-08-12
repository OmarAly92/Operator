import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';

class ServerConfigStore implements ServerConfigSource {
  ServerConfigStore(this._secureStorage);

  final FlutterSecureStorage _secureStorage;

  ServerConfig? _current;

  @override
  ServerConfig? get current => _current;

  Future<void> load() async {
    final host = CacheHelper.get(CacheKeys.serverHost) as String?;
    final httpPort = CacheHelper.get(CacheKeys.serverHttpPort) as String?;
    final password = await _secureStorage.read(key: CacheKeys.serverPassword);
    if (host == null || httpPort == null || password == null) return;

    _current = ServerConfig(
      host: host,
      httpPort: httpPort,
      secure: (CacheHelper.get(CacheKeys.serverSecure) as bool?) ?? false,
      password: password,
    );
  }

  Future<void> save(ServerConfig config) async {
    _current = config;
    await CacheHelper.save(CacheKeys.serverHost, config.host);
    await CacheHelper.save(CacheKeys.serverHttpPort, config.httpPort);
    await CacheHelper.save(CacheKeys.serverSecure, config.secure);
    await _secureStorage.write(
      key: CacheKeys.serverPassword,
      value: config.password,
    );
  }

  Future<void> clear() async {
    _current = null;
    await CacheHelper.remove(CacheKeys.serverHost);
    await CacheHelper.remove(CacheKeys.serverHttpPort);
    await CacheHelper.remove(CacheKeys.serverSecure);
    await _secureStorage.delete(key: CacheKeys.serverPassword);
  }
}
