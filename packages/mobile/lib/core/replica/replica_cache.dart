import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

class ReplicaCache {
  ReplicaCache(this._config);

  final ServerConfigSource _config;

  String? get desktopId => _config.current?.desktopId;

  Future<T?> read<S, T>({
    required Future<S?> Function(String desktopId) load,
    required T Function(S stored) parse,
    required Future<void> Function(String desktopId) forget,
  }) async {
    final desktopId = this.desktopId;
    if (desktopId == null) return null;
    final S? stored;
    try {
      stored = await load(desktopId);
    } on Failure {
      return null;
    } catch (_) {
      await _quietly(() => forget(desktopId));
      return null;
    }
    if (stored == null) return null;
    try {
      return parse(stored);
    } catch (_) {
      await _quietly(() => forget(desktopId));
      return null;
    }
  }

  Future<void> remember(String? desktopId, Future<void> Function(String desktopId) write) async {
    if (desktopId == null || this.desktopId != desktopId) return;
    await _quietly(() => write(desktopId));
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on Failure {
      return;
    }
  }
}
