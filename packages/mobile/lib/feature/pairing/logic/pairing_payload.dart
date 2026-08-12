import 'dart:convert';

import 'package:equatable/equatable.dart';

class PairingPayload extends Equatable {
  const PairingPayload({required this.host, required this.port, required this.password});

  final String host;
  final String port;
  final String password;

  @override
  List<Object?> get props => [host, port, password];
}

PairingPayload? parsePairingPayload(String raw) {
  dynamic parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return null;
  }

  if (parsed is! Map<String, dynamic>) return null;
  if (parsed['v'] != 1) return null;

  final host = parsed['host'];
  if (host is! String || host.isEmpty) return null;

  final port = parsed['port'];
  if (port is! String && port is! num) return null;

  final password = parsed['password'];
  return PairingPayload(host: host, port: port.toString(), password: password is String ? password : '');
}
