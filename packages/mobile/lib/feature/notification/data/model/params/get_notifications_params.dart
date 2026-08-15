import 'package:equatable/equatable.dart';

class GetNotificationsParams extends Equatable {
  const GetNotificationsParams({this.status, this.limit, this.cursor});

  final String? status;
  final int? limit;
  final String? cursor;

  Map<String, dynamic> toJson() => {
    if (status != null) 'status': status,
    if (limit != null) 'limit': limit,
    if (cursor != null) 'cursor': cursor,
  };

  @override
  List<Object?> get props => [status, limit, cursor];
}
