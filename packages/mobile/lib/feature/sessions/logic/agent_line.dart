import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

String? sessionAccountLabel(SessionModel session, Map<String, String> accountLabels) {
  if (session.harness != 'claude-code') return null;
  final id = (session.claudeAccountId ?? '').trim();
  final key = id.isEmpty ? 'default' : id;
  final known = accountLabels[key];
  if (known != null && known.isNotEmpty) return known;
  return '${key[0].toUpperCase()}${key.substring(1)}';
}
