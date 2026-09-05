import 'package:equatable/equatable.dart';

class UsageRollupModel extends Equatable {
  final String? bucket;
  final List<UsageBucketModel> buckets;

  const UsageRollupModel({this.bucket, this.buckets = const []});

  factory UsageRollupModel.fromJson(Map<String, dynamic> json) =>
      UsageRollupModel(
        bucket: json['bucket'] as String?,
        buckets: (json['buckets'] as List<dynamic>? ?? [])
            .map(
              (bucket) =>
                  UsageBucketModel.fromJson(bucket as Map<String, dynamic>),
            )
            .toList(),
      );

  @override
  List<Object?> get props => [bucket, buckets];
}

class UsageBucketModel extends Equatable {
  final String? start;
  final int? inputTokens;
  final int? uncachedInputTokens;
  final int? cacheReadTokens;
  final int? cacheWriteTokens;
  final int? outputTokens;
  final int? reasoningTokens;

  const UsageBucketModel({
    this.start,
    this.inputTokens,
    this.uncachedInputTokens,
    this.cacheReadTokens,
    this.cacheWriteTokens,
    this.outputTokens,
    this.reasoningTokens,
  });

  factory UsageBucketModel.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>? ?? const {};
    return UsageBucketModel(
      start: json['start'] as String?,
      inputTokens: (totals['inputTokens'] as num?)?.toInt(),
      uncachedInputTokens: (totals['uncachedInputTokens'] as num?)?.toInt(),
      cacheReadTokens: (totals['cacheReadTokens'] as num?)?.toInt(),
      cacheWriteTokens: (totals['cacheWriteTokens'] as num?)?.toInt(),
      outputTokens: (totals['outputTokens'] as num?)?.toInt(),
      reasoningTokens: (totals['reasoningTokens'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [
    start,
    inputTokens,
    uncachedInputTokens,
    cacheReadTokens,
    cacheWriteTokens,
    outputTokens,
    reasoningTokens,
  ];
}
