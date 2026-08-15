import 'package:operator_mobile/core/telemetry/daily_active.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/sanitize.dart';

abstract class MobileTelemetryClient {
  void capture(String event, Map<String, dynamic> properties);

  void register(Map<String, dynamic> properties);
}

bool _allowEverything(String event) => true;

class MobileTelemetry {
  MobileTelemetry(
    this._client,
    Map<String, dynamic> context, {
    List<String> disabledEvents = const [],
    bool Function(String event)? allow,
  }) : _denied = disabledEvents.toSet(),
       _allow = allow ?? _allowEverything {
    _client.register(context);
  }

  final MobileTelemetryClient _client;
  final Set<String> _denied;
  final bool Function(String event) _allow;

  void capture(String event, [Map<String, dynamic>? properties]) {
    if (!MobileEvents.allowlist.containsKey(event)) return;
    if (_denied.contains(event)) return;
    if (!_allow(event)) return;
    _client.capture(event, {
      ...sanitizeMobileProperties(event, properties),
      r'$process_person_profile': false,
    });
  }

  Future<void> active(ActiveStorage? storage, [DateTime? now]) async {
    if (await reserveDailyActive(storage, now ?? DateTime.now())) {
      capture(MobileEvents.active);
    }
  }
}
