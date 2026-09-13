import 'dart:convert';

import 'package:equatable/equatable.dart';

class PairingPayload extends Equatable {
  const PairingPayload({
    required this.host,
    required this.port,
    required this.password,
    required this.secure,
  });

  final String host;
  final String port;
  final String password;
  final bool secure;

  @override
  List<Object?> get props => [host, port, password, secure];
}

int? pairingPayloadVersion(String raw) {
  final map = _decodeObject(raw);
  if (map == null) return null;
  final version = map['v'];
  return version is int ? version : null;
}

PairingPayload? parsePairingPayload(String raw) {
  final map = _decodeObject(raw);
  if (map == null) return null;

  final password = map['password'];
  final asString = password is String ? password : '';

  switch (map['v']) {
    case 1:
      return _parseV1(map, asString);
    case 2:
      return _parseV2(map, asString);
    default:
      return null;
  }
}

Map<String, dynamic>? _decodeObject(String raw) {
  dynamic parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  return parsed is Map<String, dynamic> ? parsed : null;
}

PairingPayload? _parseV1(Map<String, dynamic> map, String password) {
  final host = map['host'];
  if (host is! String || host.isEmpty) return null;

  final port = map['port'];
  if (port is! String && port is! num) return null;

  return PairingPayload(host: host, port: port.toString(), password: password, secure: false);
}

PairingPayload? _parseV2(Map<String, dynamic> map, String password) {
  final url = map['url'];
  if (url is! String || url.isEmpty) return null;

  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;

  return PairingPayload(
    host: uri.host,
    port: (uri.hasPort ? uri.port : 443).toString(),
    password: password,
    secure: true,
  );
}
