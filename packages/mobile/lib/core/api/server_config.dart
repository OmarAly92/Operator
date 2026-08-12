import 'package:equatable/equatable.dart';

class ServerConfig extends Equatable {
  const ServerConfig({
    required this.host,
    required this.httpPort,
    required this.secure,
    required this.password,
  });

  final String host;
  final String httpPort;
  final bool secure;
  final String password;

  String get httpBase => '${secure ? 'https' : 'http'}://$host:$httpPort';

  String get wsBase => '${secure ? 'wss' : 'ws'}://$host:$httpPort';

  @override
  List<Object?> get props => [host, httpPort, secure, password];
}
