import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';

class NotificationPageModel extends Equatable {
  const NotificationPageModel({
    this.notifications = const [],
    this.nextCursor,
    this.unreadCount = 0,
  });

  final List<NotificationModel> notifications;
  final String? nextCursor;
  final int unreadCount;

  factory NotificationPageModel.fromJson(Map<String, dynamic> json) {
    final cursor = json['nextCursor'];
    return NotificationPageModel(
      notifications: (json['notifications'] as List<dynamic>? ?? [])
          .map((item) => NotificationModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextCursor: cursor is String && cursor.isNotEmpty ? cursor : null,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [notifications, nextCursor, unreadCount];
}
