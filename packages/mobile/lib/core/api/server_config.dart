import 'package:equatable/equatable.dart';

class ServerConfig extends Equatable {
  const ServerConfig({
    required this.host,
    required this.httpPort,
    required this.secure,
    required this.password,
    this.desktopId,
  });

  final String host;
  final String httpPort;
  final bool secure;
  final String password;
  final String? desktopId;

  String get httpBase => '${secure ? 'https' : 'http'}://$host:$httpPort';

  String get wsBase => '${secure ? 'wss' : 'ws'}://$host:$httpPort';

  @override
  List<Object?> get props => [host, httpPort, secure, password, desktopId];
}

bool hasServer(ServerConfig? server) => (server?.host.trim() ?? '').isNotEmpty;
