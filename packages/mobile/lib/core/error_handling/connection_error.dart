import 'package:flutter/foundation.dart';

enum ConnectionFailure { notOprQr, unreachable, auth, rateLimited, serverError }

ConnectionFailure classifyConnectionFailure(int? status) {
  if (status == null) return ConnectionFailure.unreachable;
  if (status == 401 || status == 403) return ConnectionFailure.auth;
  if (status == 429) return ConnectionFailure.rateLimited;
  return ConnectionFailure.serverError;
}

bool shouldKeepPolling(int? status) {
  final failure = classifyConnectionFailure(status);
  return failure != ConnectionFailure.auth && failure != ConnectionFailure.rateLimited;
}

bool isLocalNetworkHost(String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty) return false;
  if (h == 'localhost' || h.endsWith('.local')) return true;
  final match = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
  if (match == null) return false;
  final a = int.parse(match.group(1)!);
  final b = int.parse(match.group(2)!);
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 169 && b == 254) return true;
  if (a == 127) return true;
  return false;
}

class ConnectionErrorCopy {
  const ConnectionErrorCopy({required this.title, required this.message, required this.showLocalNetworkHint});

  final String title;
  final String message;
  final bool showLocalNetworkHint;
}

ConnectionErrorCopy describeConnectionFailure(
  ConnectionFailure reason, {
  required String host,
  required String port,
  required TargetPlatform platform,
}) {
  final showLocalNetworkHint =
      reason == ConnectionFailure.unreachable && platform == TargetPlatform.iOS && isLocalNetworkHost(host);

  switch (reason) {
    case ConnectionFailure.notOprQr:
      return const ConnectionErrorCopy(
        title: 'Not an Operator pairing code',
        message: "That QR code isn't an Operator pairing code.",
        showLocalNetworkHint: false,
      );
    case ConnectionFailure.unreachable:
      return ConnectionErrorCopy(
        title: 'Your desktop disconnected',
        message: 'Reached nothing at $host:$port. '
            'Is Connect Mobile still on, and is your phone on the same Wi-Fi?',
        showLocalNetworkHint: showLocalNetworkHint,
      );
    case ConnectionFailure.auth:
      return const ConnectionErrorCopy(
        title: 'Your desktop rejected the password',
        message: 'That password was rotated. Re-scan the code on your computer.',
        showLocalNetworkHint: false,
      );
    case ConnectionFailure.rateLimited:
      return const ConnectionErrorCopy(
        title: 'Too many attempts',
        message: 'Your computer locked this device out after too many failed attempts. '
            'It clears on its own in about a minute — check the password, then try again.',
        showLocalNetworkHint: false,
      );
    case ConnectionFailure.serverError:
      return ConnectionErrorCopy(
        title: 'Your desktop returned an error',
        message: '$host:$port answered, but with an error. Check the Operator logs on your computer.',
        showLocalNetworkHint: false,
      );
  }
}

const String kLocalNetworkHint =
    'If you denied the Local Network prompt, enable it in Settings › Privacy & Security › Local Network › Operator.';
