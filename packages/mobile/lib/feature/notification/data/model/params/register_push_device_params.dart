import 'package:equatable/equatable.dart';

class RegisterPushDeviceParams extends Equatable {
  const RegisterPushDeviceParams({required this.token, this.platform, this.deviceName});

  final String token;
  final String? platform;
  final String? deviceName;

  Map<String, dynamic> toJson() => {
    'token': token,
    if (platform != null) 'platform': platform,
    if (deviceName != null) 'deviceName': deviceName,
  };

  @override
  List<Object?> get props => [token, platform, deviceName];
}
