import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/preferences/preference_keys.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/rate_limit.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';

import 'telemetry_test.dart' show RecordingClient;

const TelemetryContextInput _context = TelemetryContextInput(
  platformOs: 'ios',
  isPhysicalDevice: true,
  dev: false,
  appVersion: '1.1.0',
);

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    AppPreferences.debugLoad(const {});
    TelemetryRuntime.reset();
  });

  tearDown(TelemetryRuntime.reset);

  test('stays null without a client, and every capture is a no-op', () {
    TelemetryRuntime.init(context: _context);

    expect(TelemetryRuntime.instance, isNull);
    TelemetryRuntime.capture(MobileEvents.paired, {'method': 'qr'});
    TelemetryRuntime.featureUsed('spawn', succeeded: true);
  });

  test('registers the built context and captures through the client it is given', () {
    final client = RecordingClient();

    TelemetryRuntime.init(client: client, context: _context);
    TelemetryRuntime.capture(MobileEvents.paired, {'method': 'qr'});

    expect(client.registrations.single['client'], 'mobile');
    expect(client.registrations.single['app_version'], '1.1.0');
    expect(client.captures.single.event, MobileEvents.paired);
  });

  test('reports both outcomes of a feature', () {
    final client = RecordingClient();
    TelemetryRuntime.init(client: client, context: _context);

    TelemetryRuntime.featureUsed('kill', succeeded: true);
    TelemetryRuntime.featureUsed('kill', succeeded: false);

    expect(client.captures.map((capture) => capture.properties['outcome']), [
      'succeeded',
      'failed',
    ]);
  });

  test('seeds the daily ceiling from persisted state so a restart cannot reset it', () async {
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    AppPreferences.debugLoad({
      PreferenceKeys.telemetryRateLimit: jsonEncode({
        MobileEvents.paired: NameWindow(
          minuteStart: 0,
          minuteCount: 0,
          day: today,
          dayCount: kEventsPerNamePerDay,
        ).toJson(),
      }),
    });
    final client = RecordingClient();

    TelemetryRuntime.init(client: client, context: _context);
    TelemetryRuntime.capture(MobileEvents.paired, {'method': 'qr'});

    expect(client.captures, isEmpty);
  });
}
