import 'package:operator_mobile/feature/usage/data/model/usage_quota_model.dart';

class QuotaReadoutData {
  const QuotaReadoutData({
    required this.label,
    required this.percentLabel,
    required this.fraction,
    required this.isUnknown,
  });

  final String label;
  final String? percentLabel;
  final double? fraction;
  final bool isUnknown;
}

sealed class QuotaReadout {
  static QuotaReadoutData? of(UsageQuotaWindowModel? window) {
    if (window == null) return null;

    final label = _labelFor(window.windowMinutes);
    final usedPercent = window.usedPercent;
    final isStale = window.stale ?? false;

    if (isStale || usedPercent == null) {
      return QuotaReadoutData(
        label: label,
        percentLabel: null,
        fraction: null,
        isUnknown: true,
      );
    }

    return QuotaReadoutData(
      label: label,
      percentLabel: '$usedPercent%',
      fraction: usedPercent / 100.0,
      isUnknown: false,
    );
  }

  static String _labelFor(int? windowMinutes) => switch (windowMinutes) {
    300 => '5-hour window',
    10080 => 'Weekly',
    final minutes? => '$minutes-minute window',
    null => 'Window',
  };
}
