import 'dart:math';

enum Severity { normal, warn, critical }

class ContextReadout {
  const ContextReadout({
    required this.severity,
    required this.tokens,
    this.percent,
    this.fillPercent,
  });

  final int? percent;
  final double? fillPercent;
  final Severity severity;
  final int tokens;
}

class QuotaWarning {
  const QuotaWarning({
    required this.percent,
    required this.severity,
    this.resetsInSeconds,
    this.planLabel,
  });

  final int percent;
  final Severity severity;
  final int? resetsInSeconds;
  final String? planLabel;
}

ContextReadout? contextReadout({
  required int? contextUsed,
  required int? contextWindow,
  required int? totalTokens,
}) {
  if (contextUsed == null && contextWindow == null && totalTokens == null) {
    return null;
  }
  final used = contextUsed ?? 0;
  final window = contextWindow ?? 0;
  final tokens = used != 0 ? used : totalTokens ?? 0;
  if (window <= 0) {
    return ContextReadout(severity: Severity.normal, tokens: tokens);
  }

  final fraction = min(1, max(0, used / window)).toDouble();
  return ContextReadout(
    percent: (fraction * 100).round(),
    fillPercent: max(2, fraction * 100).toDouble(),
    severity: fraction >= 0.9
        ? Severity.critical
        : fraction >= 0.7
        ? Severity.warn
        : Severity.normal,
    tokens: tokens,
  );
}

QuotaWarning? quotaWarning({
  required num? primaryUsedPercent,
  required num? secondaryUsedPercent,
  int? primaryResetsInSeconds,
  int? secondaryResetsInSeconds,
  String? planLabel,
}) {
  final windows = <({num percent, int? resetsInSeconds})>[
    if (primaryUsedPercent != null &&
        primaryUsedPercent.isFinite &&
        primaryUsedPercent >= 0)
      (percent: primaryUsedPercent, resetsInSeconds: primaryResetsInSeconds),
    if (secondaryUsedPercent != null &&
        secondaryUsedPercent.isFinite &&
        secondaryUsedPercent >= 0)
      (
        percent: secondaryUsedPercent,
        resetsInSeconds: secondaryResetsInSeconds,
      ),
  ];
  if (windows.isEmpty) return null;

  final worst = windows.reduce(
    (current, candidate) =>
        candidate.percent > current.percent ? candidate : current,
  );
  if (worst.percent < 75) return null;

  return QuotaWarning(
    percent: worst.percent.round(),
    severity: worst.percent >= 90 ? Severity.critical : Severity.warn,
    resetsInSeconds: worst.resetsInSeconds,
    planLabel: planLabel,
  );
}

String? elapsedLabel(String? startedAt, int nowMs) {
  if (startedAt == null) return null;
  final started = DateTime.tryParse(startedAt);
  if (started == null) return null;

  final elapsed = max(0, nowMs - started.millisecondsSinceEpoch);
  final seconds = elapsed ~/ 1000;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String? resetLabel(int? seconds) {
  if (seconds == null || seconds < 0) return null;
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${(seconds / 60).ceil()}m';
  if (seconds < 86400) return '${(seconds / 3600).ceil()}h';
  return '${(seconds / 86400).ceil()}d';
}

String mcpServerFailureLabel({
  required String name,
  String? failureReason,
  String? error,
}) {
  final details = [
    failureReason,
    error,
  ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
  return details.isEmpty ? name : '$name (${details.join(': ')})';
}
