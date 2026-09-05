import 'package:equatable/equatable.dart';

class UsageRollupParams extends Equatable {
  final String bucket;
  final int? days;

  const UsageRollupParams({required this.bucket, this.days});

  Map<String, dynamic> toJson() => {'bucket': bucket, 'days': days};

  @override
  List<Object?> get props => [bucket, days];
}
