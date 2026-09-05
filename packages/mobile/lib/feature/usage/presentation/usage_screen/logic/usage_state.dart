part of 'usage_cubit.dart';

enum UsageStatus { initial, loading, loaded, error }

class UsageState extends Equatable {
  final UsageStatus status;
  final String bucket;
  final List<UsageBucketModel> buckets;
  final String? error;

  const UsageState({
    this.status = UsageStatus.initial,
    this.bucket = 'day',
    this.buckets = const [],
    this.error,
  });

  UsageState copyWith({
    UsageStatus? status,
    String? bucket,
    List<UsageBucketModel>? buckets,
    String? error,
  }) => UsageState(
    status: status ?? this.status,
    bucket: bucket ?? this.bucket,
    buckets: buckets ?? this.buckets,
    error: error,
  );

  @override
  List<Object?> get props => [status, bucket, buckets, error];
}
