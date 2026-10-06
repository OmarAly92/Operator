import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

DateTime? activeSince(Iterable<SessionModel> sessions, String sessionId) {
  final session = sessions.where((candidate) => candidate.id == sessionId).firstOrNull;
  if (session == null || session.activity != 'active') return null;
  return DateTime.tryParse(session.activitySince ?? '');
}
