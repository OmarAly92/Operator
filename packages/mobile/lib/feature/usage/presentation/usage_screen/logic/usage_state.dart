part of 'usage_cubit.dart';

enum UsageStatus { initial, loading, loaded, error }

class UsageState extends Equatable {
  final UsageStatus status;
  final String bucket;
  final List<UsageBucketModel> buckets;
  final String? error;
  final UsageQuotaModel? quota;

  const UsageState({
    this.status = UsageStatus.initial,
    this.bucket = 'day',
    this.buckets = const [],
    this.error,
    this.quota,
  });

  UsageState copyWith({
    UsageStatus? status,
    String? bucket,
    List<UsageBucketModel>? buckets,
    String? error,
    UsageQuotaModel? quota,
  }) => UsageState(
    status: status ?? this.status,
    bucket: bucket ?? this.bucket,
    buckets: buckets ?? this.buckets,
    error: error,
    quota: quota ?? this.quota,
  );

  @override
  List<Object?> get props => [status, bucket, buckets, error, quota];
}
