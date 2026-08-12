import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';

SessionModel session({
  String? id = 'proj-7',
  String? displayName,
  String? status,
  String? issueId,
  List<SessionPrModel>? prs,
}) => SessionModel(
  id: id,
  projectId: 'proj',
  displayName: displayName,
  status: status,
  issueId: issueId,
  prs: prs,
);

void main() {
  group('sessionTitle', () {
    test('prefers displayName, then issueId', () {
      expect(sessionTitle(session(displayName: 'Fix auth', issueId: 'Operator-12')), 'Fix auth');
      expect(sessionTitle(session(issueId: 'Operator-12')), 'Operator-12');
    });

    test('falls back to the id when nothing is named', () {
      expect(sessionTitle(session()), 'proj-7');
    });

    test('treats a whitespace-only name as absent', () {
      expect(sessionTitle(session(displayName: '   ')), 'proj-7');
      expect(sessionTitle(session(displayName: '\t\n', issueId: 'Operator-12')), 'Operator-12');
    });

    test('trims a name that has content', () {
      expect(sessionTitle(session(displayName: '  Fix auth  ')), 'Fix auth');
    });

    test('never returns blank', () {
      for (final s in [session(), session(displayName: ' '), session(displayName: ' ', issueId: ' ')]) {
        expect(sessionTitle(s).isNotEmpty, isTrue);
      }
    });
  });

  group('isTerminalStatus', () {
    test('recognises the terminal set', () {
      for (final s in ['killed', 'terminated', 'done', 'cleanup', 'errored', 'merged']) {
        expect(isTerminalStatus(s), isTrue);
      }
    });

    test('is false for live and missing statuses', () {
      expect(isTerminalStatus('working'), isFalse);
      expect(isTerminalStatus(null), isFalse);
      expect(isTerminalStatus(''), isFalse);
    });
  });

  group('attentionOf', () {
    test('maps terminal statuses to done', () {
      expect(attentionOf(session(status: 'merged')), AttentionLevel.done);
      expect(attentionOf(session(status: 'killed')), AttentionLevel.done);
    });

    test('maps a mergeable PR to merge', () {
      final s = session(prs: [const SessionPrModel(url: 'u', number: 1, mergeable: true)]);
      expect(attentionOf(s), AttentionLevel.merge);
    });

    test('maps blocked statuses to respond', () {
      expect(attentionOf(session(status: 'needs_input')), AttentionLevel.respond);
      expect(attentionOf(session(status: 'stuck')), AttentionLevel.respond);
    });

    test('maps failing CI and requested changes to review', () {
      expect(attentionOf(session(status: 'ci_failed')), AttentionLevel.review);
      final s = session(prs: [const SessionPrModel(url: 'u', number: 1, ci: 'failing')]);
      expect(attentionOf(s), AttentionLevel.review);
    });

    test('defaults to working', () {
      expect(attentionOf(session()), AttentionLevel.working);
    });
  });
}
