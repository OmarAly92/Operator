import 'package:equatable/equatable.dart';

class DesktopIdentityModel extends Equatable {
  final String? name;
  final String? hostname;

  const DesktopIdentityModel({this.name, this.hostname});

  factory DesktopIdentityModel.fromJson(Map<String, dynamic> json) => DesktopIdentityModel(
    name: json['name'] as String?,
    hostname: json['hostname'] as String?,
  );

  @override
  List<Object?> get props => [name, hostname];
}
