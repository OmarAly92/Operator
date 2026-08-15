import 'package:operator_mobile/core/telemetry/events.dart';

Map<String, dynamic> sanitizeMobileProperties(
  String event,
  Map<String, dynamic>? properties, {
  Map<String, Map<String, PropRule>> allowlist = MobileEvents.allowlist,
}) {
  final allowed = allowlist[event];
  if (allowed == null) return {};
  final sanitized = <String, dynamic>{};
  if (properties == null) return sanitized;

  for (final rule in allowed.entries) {
    if (!properties.containsKey(rule.key)) continue;
    final value = properties[rule.key];
    final keep = switch (rule.value) {
      OneOfRule(:final values) => value is String && values.contains(value),
      FlagRule() => value is bool,
      CountRule() => value is int && !value.isNegative,
    };
    if (keep) sanitized[rule.key] = value;
  }
  return sanitized;
}
