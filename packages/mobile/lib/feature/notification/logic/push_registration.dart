import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/helpers/logging/app_logger.dart';

const String kPushRegistrationKey = 'opr.pushRegistration';
const String kPushPendingUnregisterKey = 'opr.pushPendingUnregister';
const int kMaxPendingUnregister = 10;

abstract class PushSecureStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterPushSecureStorage implements PushSecureStorage {
  const FlutterPushSecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class PushRegistration extends Equatable {
  const PushRegistration({
    required this.token,
    required this.host,
    required this.httpPort,
    required this.secure,
    required this.password,
  });

  final String token;
  final String host;
  final String httpPort;
  final bool secure;
  final String password;

  factory PushRegistration.fromJson(Map<String, dynamic> json) => PushRegistration(
    token: json['token'] as String? ?? '',
    host: json['host'] as String? ?? '',
    httpPort: json['httpPort'] as String? ?? '',
    secure: json['secure'] as bool? ?? false,
    password: json['password'] as String? ?? '',
  );

  factory PushRegistration.of(String token, ServerConfig config) => PushRegistration(
    token: token,
    host: config.host,
    httpPort: config.httpPort,
    secure: config.secure,
    password: config.password,
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'host': host,
    'httpPort': httpPort,
    'secure': secure,
    'password': password,
  };

  ServerConfig get config =>
      ServerConfig(host: host, httpPort: httpPort, secure: secure, password: password);

  /// Identity is the address, not the credential: a password change is the same
  /// daemon.
  bool sameDaemon(ServerConfig other) =>
      host == other.host && httpPort == other.httpPort && secure == other.secure;

  @override
  List<Object?> get props => [token, host, httpPort, secure, password];
}

class PushRegistrationStore {
  const PushRegistrationStore(this._storage);

  final PushSecureStorage _storage;

  Future<PushRegistration?> load() async {
    final raw = await _storage.read(kPushRegistrationKey);
    if (raw == null) return null;
    try {
      return PushRegistration.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PushRegistration registration) =>
      _storage.write(kPushRegistrationKey, jsonEncode(registration.toJson()));

  Future<void> clear() => _storage.delete(kPushRegistrationKey);

  Future<List<PushRegistration>> pending() async {
    final raw = await _storage.read(kPushPendingUnregisterKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((entry) => PushRegistration.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePending(List<PushRegistration> registrations) async {
    if (registrations.isEmpty) {
      await _storage.delete(kPushPendingUnregisterKey);
      return;
    }
    // Dropping the oldest entries means those daemons keep a token they can
    // push to; the queue is still bounded, but the loss must not be silent.
    final dropped = registrations.length - kMaxPendingUnregister;
    if (dropped > 0) {
      AppLogger.warning(
        'Dropping $dropped stale push unregistration(s) past the queue cap of '
        '$kMaxPendingUnregister; those daemons may keep pushing to this device.',
      );
    }
    final bounded = dropped > 0
        ? registrations.sublist(registrations.length - kMaxPendingUnregister)
        : registrations;
    await _storage.write(
      kPushPendingUnregisterKey,
      jsonEncode(bounded.map((registration) => registration.toJson()).toList()),
    );
  }

  Future<void> queuePending(PushRegistration registration) async {
    final queued = await pending();
    final duplicate = queued.any(
      (entry) => entry.token == registration.token && entry.sameDaemon(registration.config),
    );
    if (duplicate) return;
    await savePending([...queued, registration]);
  }
}
