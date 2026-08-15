import 'package:equatable/equatable.dart';

class NotificationModel extends Equatable {
  const NotificationModel({
    this.id,
    this.sessionId,
    this.projectId,
    this.prUrl,
    this.type,
    this.title,
    this.body,
    this.status,
    this.createdAt,
  });

  final String? id;
  final String? sessionId;
  final String? projectId;
  final String? prUrl;
  final String? type;
  final String? title;
  final String? body;
  final String? status;
  final String? createdAt;

  factory NotificationModel.fromJson(Map<String, dynamic> json) => NotificationModel(
    id: json['id'] as String?,
    sessionId: json['sessionId'] as String?,
    projectId: json['projectId'] as String?,
    prUrl: json['prUrl'] as String?,
    type: json['type'] as String?,
    title: json['title'] as String?,
    body: json['body'] as String?,
    status: json['status'] as String?,
    createdAt: json['createdAt'] as String?,
  );

  NotificationModel copyWith({String? status}) => NotificationModel(
    id: id,
    sessionId: sessionId,
    projectId: projectId,
    prUrl: prUrl,
    type: type,
    title: title,
    body: body,
    status: status ?? this.status,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [id, sessionId, projectId, prUrl, type, title, body, status, createdAt];
}
