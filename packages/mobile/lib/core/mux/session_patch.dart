import 'package:equatable/equatable.dart';

class SessionPatch extends Equatable {
  const SessionPatch({required this.id, required this.activity, this.status});

  final String id;
  final String? activity;
  final String? status;

  static SessionPatch? fromChangePayload(String sessionId, Object? payload) {
    if (payload is! Map<String, dynamic>) return null;
    final activity = payload['activity'];
    if (activity is! String) return null;
    return SessionPatch(
      id: sessionId,
      activity: activity,
      status: payload['isTerminated'] == true ? 'terminated' : null,
    );
  }

  @override
  List<Object?> get props => [id, activity, status];
}
