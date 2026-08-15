import 'package:equatable/equatable.dart';

const int kMobileTelemetrySchemaVersion = 2;

class TelemetryContextInput extends Equatable {
  const TelemetryContextInput({
    required this.platformOs,
    required this.isPhysicalDevice,
    required this.dev,
    required this.appVersion,
  });

  final String platformOs;
  final bool isPhysicalDevice;
  final bool dev;
  final String appVersion;

  @override
  List<Object?> get props => [platformOs, isPhysicalDevice, dev, appVersion];
}

class TelemetryContext extends Equatable {
  const TelemetryContext({
    required this.client,
    required this.platform,
    required this.buildMode,
    required this.appVersion,
    this.schemaVersion = kMobileTelemetrySchemaVersion,
  });

  final String client;
  final String platform;
  final String buildMode;
  final String appVersion;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
    'client': client,
    'platform': platform,
    'build_mode': buildMode,
    'app_version': appVersion,
    'telemetry_schema_version': schemaVersion,
  };

  @override
  List<Object?> get props => [client, platform, buildMode, appVersion, schemaVersion];
}

TelemetryContext buildMobileContext(TelemetryContextInput input) {
  final version = input.appVersion.trim();
  return TelemetryContext(
    client: input.platformOs == 'web' ? 'mobile-web' : 'mobile',
    platform: switch (input.platformOs) {
      'ios' || 'android' || 'web' => input.platformOs,
      _ => 'other',
    },
    buildMode: input.dev
        ? 'dev'
        : input.isPhysicalDevice
        ? 'device'
        : 'simulator',
    appVersion: version.isEmpty ? 'unknown' : version,
  );
}
