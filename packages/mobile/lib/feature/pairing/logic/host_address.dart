import 'package:equatable/equatable.dart';

const defaultApiPort = '3011';

class HostAddress extends Equatable {
  const HostAddress({required this.host, required this.port, this.secure});

  final String host;
  final String port;
  final bool? secure;

  @override
  List<Object?> get props => [host, port, secure];
}

HostAddress parseHostAddress(String raw) {
  var text = raw.trim();
  bool? secure;
  final scheme = RegExp(r'^(https?|wss?)://', caseSensitive: false).firstMatch(text);
  if (scheme != null) {
    final name = scheme.group(1)!.toLowerCase();
    secure = name == 'https' || name == 'wss';
    text = text.substring(scheme.end);
  }
  final slash = text.indexOf('/');
  if (slash != -1) text = text.substring(0, slash);

  final bracketed = RegExp(r'^\[([^\]]+)\](?::(\d+))?$').firstMatch(text);
  if (bracketed != null) {
    return HostAddress(host: bracketed.group(1)!, port: bracketed.group(2) ?? _defaultPort(secure), secure: secure);
  }

  final colon = text.lastIndexOf(':');
  if (colon != -1 && text.indexOf(':') == colon) {
    final port = text.substring(colon + 1);
    if (RegExp(r'^\d+$').hasMatch(port)) {
      return HostAddress(host: text.substring(0, colon), port: port, secure: secure);
    }
  }
  return HostAddress(host: text, port: _defaultPort(secure), secure: secure);
}

String formatHostAddress(String host, String port) => port == defaultApiPort ? host : '$host:$port';

String _defaultPort(bool? secure) => switch (secure) {
  null => defaultApiPort,
  true => '443',
  false => '80',
};
