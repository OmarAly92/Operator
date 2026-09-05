import 'package:equatable/equatable.dart';

class SessionContextModel extends Equatable {
  final String? harness;
  final String? modelId;
  final int? used;
  final int? window;
  final DateTime? observedAt;

  const SessionContextModel({
    this.harness,
    this.modelId,
    this.used,
    this.window,
    this.observedAt,
  });

  factory SessionContextModel.fromJson(Map<String, dynamic> json) =>
      SessionContextModel(
        harness: json['harness'] as String?,
        modelId: json['modelId'] as String?,
        used: (json['used'] as num?)?.toInt(),
        window: (json['window'] as num?)?.toInt(),
        observedAt: json['observedAt'] == null
            ? null
            : DateTime.tryParse(json['observedAt'] as String),
      );

  bool get hasWindow => (window ?? 0) > 0;

  double? get fraction {
    if (!hasWindow) return null;
    final contextUsed = used ?? 0;
    if (contextUsed >= window!) return 1;
    return contextUsed / window!;
  }

  @override
  List<Object?> get props => [harness, modelId, used, window, observedAt];
}
