import 'package:operator_mobile/feature/usage/data/model/session_context_model.dart';

enum ContextSeverity { normal, warn, critical }

class ContextReadoutData {
  const ContextReadoutData({
    required this.label,
    required this.percentLabel,
    required this.fraction,
    required this.severity,
  });

  final String label;
  final String? percentLabel;
  final double? fraction;
  final ContextSeverity severity;
}

sealed class ContextReadout {
  static ContextReadoutData? of(SessionContextModel? context) {
    final used = context?.used;
    if (used == null || used < 0) return null;

    final fraction = context!.fraction;
    final percentLabel = fraction == null
        ? null
        : '${(fraction * 100).round()}%';
    final severity = switch (fraction) {
      null => ContextSeverity.normal,
      >= 0.9 => ContextSeverity.critical,
      >= 0.7 => ContextSeverity.warn,
      _ => ContextSeverity.normal,
    };
    return ContextReadoutData(
      label: _formatTokenCount(used),
      percentLabel: percentLabel,
      fraction: fraction,
      severity: severity,
    );
  }

  static String _formatTokenCount(int used) {
    if (used < 1000) return '$used tokens';
    return '${(used / 1000).toStringAsFixed(1)}k tokens';
  }
}
