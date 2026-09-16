import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/database/app_database.dart';

class DesktopModel extends Equatable {
  final String? id;
  final String? name;
  final String? host;
  final String? port;
  final bool? secure;
  final bool? isActive;
  final DateTime? lastConnectedAt;

  const DesktopModel({this.id, this.name, this.host, this.port, this.secure, this.isActive, this.lastConnectedAt});

  factory DesktopModel.fromDB(DesktopEntity entity) => DesktopModel(
    id: entity.id,
    name: entity.name,
    host: entity.host,
    port: entity.port,
    secure: entity.secure,
    isActive: entity.isActive,
    lastConnectedAt: entity.lastConnectedAt,
  );

  ServerConfig toServerConfig(String password) =>
      ServerConfig(host: host ?? '', httpPort: port ?? '', secure: secure ?? false, password: password);

  String get address => '$host:$port';

  DesktopModel copyWithActive(bool active) => DesktopModel(
    id: id, name: name, host: host, port: port, secure: secure, isActive: active, lastConnectedAt: lastConnectedAt,
  );

  @override
  List<Object?> get props => [id, name, host, port, secure, isActive, lastConnectedAt];
}
