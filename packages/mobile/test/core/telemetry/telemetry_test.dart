import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/telemetry/daily_active.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/telemetry.dart';

class RecordingClient implements MobileTelemetryClient {
  final List<({String event, Map<String, dynamic> properties})> captures = [];
  final List<Map<String, dynamic>> registrations = [];

  @override
  void capture(String event, Map<String, dynamic> properties) =>
      captures.add((event: event, properties: properties));

  @override
  void register(Map<String, dynamic> properties) => registrations.add(properties);
}

class _MemoryStorage implements ActiveStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> getItem(String key) async => values[key];

  @override
  Future<void> setItem(String key, String value) async => values[key] = value;
}

void main() {
  late RecordingClient client;

  setUp(() => client = RecordingClient());

  test('registers the context as super-properties once on creation', () {
    MobileTelemetry(client, const {'client': 'mobile', 'platform': 'ios'});

    expect(client.registrations, [
      {'client': 'mobile', 'platform': 'ios'},
    ]);
  });

  test('sanitizes properties on capture, dropping anything unregistered', () {
    MobileTelemetry(client, const {}).capture(MobileEvents.featureUsed, {
      'feature': 'spawn',
      'outcome': 'succeeded',
      'session_title': 'leak me',
      'password': 'hunter2',
    });

    expect(client.captures.single.event, MobileEvents.featureUsed);
    expect(client.captures.single.properties, {
      'feature': 'spawn',
      'outcome': 'succeeded',
      r'$process_person_profile': false,
    });
  });

  test('drops an event name that is not in the allowlist', () {
    MobileTelemetry(client, const {}).capture('opr.v2.mobile_app.typo', {'feature': 'spawn'});

    expect(client.captures, isEmpty);
  });

  test('stamps the anonymous-rate flag on every event', () {
    MobileTelemetry(client, const {}).capture(MobileEvents.paired, {'method': 'qr'});

    expect(client.captures.single.properties[r'$process_person_profile'], isFalse);
  });

  test('drops an event named in the build-time kill switch', () {
    final telemetry = MobileTelemetry(
      client,
      const {},
      disabledEvents: const [MobileEvents.connected],
    );

    telemetry.capture(MobileEvents.connected, {'trigger': 'launch'});
    telemetry.capture(MobileEvents.paired, {'method': 'qr'});

    expect(client.captures.map((capture) => capture.event), [MobileEvents.paired]);
  });

  test('drops an event the rate limiter rejects', () {
    var calls = 0;
    final telemetry = MobileTelemetry(client, const {}, allow: (_) => ++calls <= 1);

    telemetry.capture(MobileEvents.paired, {'method': 'qr'});
    telemetry.capture(MobileEvents.paired, {'method': 'qr'});

    expect(client.captures, hasLength(1));
  });

  test('emits the daily active heartbeat once per UTC day', () async {
    final telemetry = MobileTelemetry(client, const {});
    final storage = _MemoryStorage();

    await telemetry.active(storage, DateTime.utc(2026, 8, 6, 1));
    await telemetry.active(storage, DateTime.utc(2026, 8, 6, 20));
    await telemetry.active(storage, DateTime.utc(2026, 8, 7, 0, 1));

    expect(client.captures.map((capture) => capture.event), [
      MobileEvents.active,
      MobileEvents.active,
    ]);
  });

  test('marks the active day in storage', () async {
    final storage = _MemoryStorage();

    await MobileTelemetry(client, const {}).active(storage, DateTime.utc(2026, 8, 6, 1));

    expect(storage.values[kActiveStorageKey], '2026-08-06');
  });
}
