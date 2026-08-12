import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

const Set<String> _terminalStatuses = {'killed', 'terminated', 'done', 'cleanup', 'errored', 'merged'};

bool isTerminalStatus(String? status) => status != null && _terminalStatuses.contains(status);

String sessionTitle(SessionModel session) {
  for (final candidate in [session.displayName, session.issueId]) {
    final trimmed = candidate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return session.id?.trim() ?? '';
}

enum AttentionLevel { merge, respond, review, pending, working, done }

AttentionLevel attentionOf(SessionModel session) {
  final pr = session.prs?.isNotEmpty == true ? session.prs!.first : null;

  if (session.status == 'merged' || session.status == 'done' || isTerminalStatus(session.status)) {
    return AttentionLevel.done;
  }
  if ((pr?.mergeable ?? false) || session.status == 'mergeable' || session.status == 'approved') {
    return AttentionLevel.merge;
  }
  if (session.status == 'needs_input' || session.status == 'stuck') {
    return AttentionLevel.respond;
  }
  if (pr?.ci == 'failing' ||
      pr?.review == 'changes_requested' ||
      session.status == 'ci_failed' ||
      session.status == 'changes_requested') {
    return AttentionLevel.review;
  }
  if (session.status == 'pr_open' || session.status == 'review_pending') {
    return AttentionLevel.pending;
  }
  return AttentionLevel.working;
}
