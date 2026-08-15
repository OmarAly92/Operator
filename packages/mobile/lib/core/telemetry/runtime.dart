import 'dart:async';
import 'dart:convert';

import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/telemetry/context.dart';
import 'package:operator_mobile/core/telemetry/daily_active.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/rate_limit.dart';
import 'package:operator_mobile/core/telemetry/telemetry.dart';

export 'package:operator_mobile/core/telemetry/context.dart' show TelemetryContextInput;
export 'package:operator_mobile/core/telemetry/telemetry.dart' show MobileTelemetryClient;

sealed class TelemetryConfig {
  static const bool disabled =
      String.fromEnvironment('OPERATOR_TELEMETRY_DISABLED') == '1';

  static const String _disabledEventsRaw =
      String.fromEnvironment('OPERATOR_TELEMETRY_DISABLED_EVENTS');

  static List<String> get disabledEvents => _disabledEventsRaw
      .split(',')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();
}

class CacheActiveStorage implements ActiveStorage {
  const CacheActiveStorage();

  @override
  Future<String?> getItem(String key) async => CacheHelper.get(key) as String?;

  @override
  Future<void> setItem(String key, String value) => CacheHelper.save(key, value);
}

sealed class TelemetryRuntime {
  static MobileTelemetry? _telemetry;
  static RateLimitState _rateState = {};
  static bool _rateStateLoaded = false;

  static MobileTelemetry? get instance => _telemetry;

  static void init({
    MobileTelemetryClient? client,
    required TelemetryContextInput context,
    List<String>? disabledEvents,
  }) {
    if (_telemetry != null || client == null || TelemetryConfig.disabled) return;
    _loadRateState();
    _telemetry = MobileTelemetry(
      client,
      buildMobileContext(context).toJson(),
      disabledEvents: disabledEvents ?? TelemetryConfig.disabledEvents,
      allow: _allowEvent,
    );
  }

  static void capture(String event, [Map<String, dynamic>? properties]) =>
      _telemetry?.capture(event, properties);

  static void featureUsed(String feature, {required bool succeeded}) => capture(
    MobileEvents.featureUsed,
    {'feature': feature, 'outcome': succeeded ? 'succeeded' : 'failed'},
  );

  static Future<void> active([DateTime? now]) async {
    await _telemetry?.active(const CacheActiveStorage(), now);
  }

  static void reset() {
    _telemetry = null;
    _rateState = {};
    _rateStateLoaded = false;
  }

  static void _loadRateState() {
    if (_rateStateLoaded) return;
    _rateStateLoaded = true;
    final raw = CacheHelper.get(CacheKeys.telemetryRateLimit) as String?;
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _rateState = mergeRateState(
        decoded.map(
          (name, window) => MapEntry(name, NameWindow.fromJson(window as Map<String, dynamic>)),
        ),
        _rateState,
      );
    } catch (_) {
      _rateState = <String, NameWindow>{};
    }
  }

  static bool _allowEvent(String event) {
    final decision = checkRateLimit(
      _rateState,
      event,
      DateTime.now().millisecondsSinceEpoch,
    );
    _rateState = decision.state;
    unawaited(
      CacheHelper.save(
        CacheKeys.telemetryRateLimit,
        jsonEncode(_rateState.map((name, window) => MapEntry(name, window.toJson()))),
      ),
    );
    return decision.allowed;
  }
}
