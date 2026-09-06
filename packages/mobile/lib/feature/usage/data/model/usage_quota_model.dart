import 'package:equatable/equatable.dart';

class UsageQuotaWindowModel extends Equatable {
  final String? kind;
  final int? windowMinutes;
  final int? usedPercent;
  final DateTime? resetsAt;
  final bool? stale;

  const UsageQuotaWindowModel({
    this.kind,
    this.windowMinutes,
    this.usedPercent,
    this.resetsAt,
    this.stale,
  });

  factory UsageQuotaWindowModel.fromJson(Map<String, dynamic> json) =>
      UsageQuotaWindowModel(
        kind: json['kind'] as String?,
        windowMinutes: (json['windowMinutes'] as num?)?.toInt(),
        usedPercent: (json['usedPercent'] as num?)?.toInt(),
        resetsAt: json['resetsAt'] == null
            ? null
            : DateTime.tryParse(json['resetsAt'] as String),
        stale: json['stale'] as bool?,
      );

  @override
  List<Object?> get props => [kind, windowMinutes, usedPercent, resetsAt, stale];
}

class UsageQuotaModel extends Equatable {
  final String? harness;
  final String? limitId;
  final String? planType;
  final DateTime? observedAt;
  final List<UsageQuotaWindowModel> windows;

  const UsageQuotaModel({
    this.harness,
    this.limitId,
    this.planType,
    this.observedAt,
    this.windows = const [],
  });

  factory UsageQuotaModel.fromJson(Map<String, dynamic> json) {
    final rawWindows = json['windows'];
    return UsageQuotaModel(
      harness: json['harness'] as String?,
      limitId: json['limitId'] as String?,
      planType: json['planType'] as String?,
      observedAt: json['observedAt'] == null
          ? null
          : DateTime.tryParse(json['observedAt'] as String),
      windows: rawWindows is List
          ? rawWindows
              .whereType<Map>()
              .map((w) => UsageQuotaWindowModel.fromJson(Map<String, dynamic>.from(w)))
              .toList()
          : const [],
    );
  }

  @override
  List<Object?> get props => [harness, limitId, planType, observedAt, windows];
}
