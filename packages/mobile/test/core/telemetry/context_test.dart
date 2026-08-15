import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/telemetry/context.dart';

TelemetryContext context({
  String platformOs = 'ios',
  bool isPhysicalDevice = true,
  bool dev = false,
  String appVersion = '1.1.0',
}) => buildMobileContext(
  TelemetryContextInput(
    platformOs: platformOs,
    isPhysicalDevice: isPhysicalDevice,
    dev: dev,
    appVersion: appVersion,
  ),
);

void main() {
  test('tags the native app as client=mobile with the OS platform', () {
    final built = context();

    expect(built.client, 'mobile');
    expect(built.platform, 'ios');
    expect(built.buildMode, 'device');
    expect(built.appVersion, '1.1.0');
    expect(built.schemaVersion, kMobileTelemetrySchemaVersion);
  });

  test('tags the web build as client=mobile-web so it cannot inflate installs', () {
    final built = context(platformOs: 'web', isPhysicalDevice: false);

    expect(built.client, 'mobile-web');
    expect(built.platform, 'web');
  });

  test('distinguishes dev, simulator and device builds', () {
    expect(context(platformOs: 'android', dev: true).buildMode, 'dev');
    expect(context(platformOs: 'android', isPhysicalDevice: false).buildMode, 'simulator');
    expect(context(platformOs: 'android').buildMode, 'device');
  });

  test('falls back to platform=other and version=unknown for junk input', () {
    final built = context(platformOs: 'windows', appVersion: '   ');

    expect(built.platform, 'other');
    expect(built.appVersion, 'unknown');
  });

  test('serialises the wire keys every event rides with', () {
    expect(context().toJson(), {
      'client': 'mobile',
      'platform': 'ios',
      'build_mode': 'device',
      'app_version': '1.1.0',
      'telemetry_schema_version': kMobileTelemetrySchemaVersion,
    });
  });
}
