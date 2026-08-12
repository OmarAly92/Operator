import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/tone.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';
import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';

const _dark = DarkSkin();
const _light = LightSkin();

SessionModel session({
  String? id = 'proj-1',
  String? status,
  bool? isTerminated,
  String? updatedAt,
  List<SessionPrModel>? prs,
}) => SessionModel(id: id, projectId: 'proj', status: status, isTerminated: isTerminated, updatedAt: updatedAt, prs: prs);

SessionPrModel pr({int number = 1, String state = 'open'}) => SessionPrModel(url: '', number: number, state: state);

void main() {
  group('boardZoneOf', () {
    test('declares the four columns in desktop\'s order', () {
      expect(BoardZone.values, [BoardZone.working, BoardZone.action, BoardZone.pending, BoardZone.merge]);
    });

    test('folds review and respond into action', () {
      expect(boardZoneOf(session(status: 'needs_input')), BoardZone.action);
      expect(boardZoneOf(session(status: 'stuck')), BoardZone.action);
      expect(boardZoneOf(session(status: 'ci_failed')), BoardZone.action);
      expect(boardZoneOf(session(status: 'changes_requested')), BoardZone.action);
    });

    test('maps the remaining zones straight through', () {
      expect(boardZoneOf(session(status: 'mergeable')), BoardZone.merge);
      expect(boardZoneOf(session(status: 'approved')), BoardZone.merge);
      expect(boardZoneOf(session(status: 'pr_open')), BoardZone.pending);
      expect(boardZoneOf(session(status: 'review_pending')), BoardZone.pending);
      expect(boardZoneOf(session(status: 'working')), BoardZone.working);
      expect(boardZoneOf(session(status: 'idle')), BoardZone.working);
    });
  });

  group('zoneMeta', () {
    test('uses desktop\'s labels', () {
      expect(BoardZone.values.map((z) => zoneMeta(_dark, z).label), ['Working', 'Needs you', 'In review', 'Ready to merge']);
    });

    test('takes its colours from the passed skin', () {
      expect(zoneMeta(_light, BoardZone.merge).color, isNot(zoneMeta(_dark, BoardZone.merge).color));
    });
  });

  group('isArchived', () {
    test('archives a terminated runtime', () {
      expect(isArchived(session(isTerminated: true)), isTrue);
      expect(isArchived(session(status: 'terminated')), isTrue);
    });

    test('keeps a merged session whose runtime is still alive', () {
      expect(isArchived(session(status: 'merged')), isFalse);
      expect(isArchived(session(status: 'done')), isFalse);
    });

    test('keeps ordinary live sessions', () {
      expect(isArchived(session(status: 'working')), isFalse);
      expect(isArchived(session()), isFalse);
    });
  });

  group('groupSessions', () {
    test('splits the board from the archive', () {
      final result = groupSessions(_dark, [
        session(id: 'a', status: 'working'),
        session(id: 'b', status: 'needs_input'),
        session(id: 'z', isTerminated: true),
      ]);
      expect(result.sections.map((s) => s.zone), [BoardZone.working, BoardZone.action]);
      expect(result.archived.map((s) => s.id), ['z']);
    });

    test('drops empty zones rather than rendering empty headers', () {
      final result = groupSessions(_dark, [session(status: 'working')]);
      expect(result.sections, hasLength(1));
      expect(result.sections.first.label, 'Working');
    });

    test('keeps sections in desktop\'s order regardless of input order', () {
      final result = groupSessions(_dark, [
        session(id: 'm', status: 'mergeable'),
        session(id: 'w', status: 'working'),
        session(id: 'p', status: 'pr_open'),
      ]);
      expect(result.sections.map((s) => s.zone), [BoardZone.working, BoardZone.pending, BoardZone.merge]);
    });

    test('sorts the archive newest first', () {
      final result = groupSessions(_dark, [
        session(id: 'old', isTerminated: true, updatedAt: '2026-01-01T00:00:00Z'),
        session(id: 'new', isTerminated: true, updatedAt: '2026-07-01T00:00:00Z'),
      ]);
      expect(result.archived.map((s) => s.id), ['new', 'old']);
    });

    test('returns nothing for an empty board', () {
      final result = groupSessions(_dark, const []);
      expect(result.sections, isEmpty);
      expect(result.archived, isEmpty);
    });
  });

  group('showBranch', () {
    test('shows a branch that adds information', () {
      expect(showBranch('fix/auth-timeouts', 'Fix auth timeouts on refresh'), isTrue);
    });

    test('hides a branch that merely repeats the title', () {
      expect(showBranch('fix/auth-timeouts', 'auth timeouts'), isFalse);
      expect(showBranch('feat/add-login', 'Add Login'), isFalse);
    });

    test('keeps Operator worktree branches, named session or not', () {
      expect(showBranch('opr/operator-mo-17/root', 'mobile-ui-revamp'), isTrue);
      expect(showBranch('opr/meetyou-2/chat-experience', 'chat-ux'), isTrue);
      expect(showBranch('opr/meetyou-7/root', 'meetyou-7'), isTrue);
      expect(showBranch('opr/precision-market-19/root', 'precision-market-19'), isTrue);
    });

    test('hides an absent branch', () {
      expect(showBranch(null, 't'), isFalse);
      expect(showBranch('  ', 't'), isFalse);
    });
  });

  group('prLine', () {
    test('renders nothing when there is no PR', () {
      expect(prLine(session()), isNull);
      expect(prLine(session(prs: const [])), isNull);
    });

    test('ignores placeholder PRs with no real number', () {
      expect(prLine(session(prs: [pr(number: 0)])), isNull);
    });

    test('groups by lifecycle, the way the desktop board card does', () {
      final line = prLine(session(prs: [pr(number: 12), pr(number: 13)]));
      expect(line?.text, 'PR #12, #13 open');
    });

    test('keeps separate lifecycles apart', () {
      final line = prLine(session(prs: [pr(number: 12), pr(number: 9, state: 'merged')]));
      expect(line?.text, 'PR #12 open · #9 merged');
    });

    test('takes its tone from the worst lifecycle present', () {
      expect(prLine(session(prs: [pr(number: 1, state: 'closed')]))?.tone, Tone.error);
      expect(prLine(session(prs: [pr(number: 1)]))?.tone, Tone.success);
    });
  });

  group('trackerIssueId', () {
    test('keeps a provider-prefixed tracker reference', () {
      expect(trackerIssueId('github:123'), 'github:123');
    });

    test('rejects the free text a manually created session carries', () {
      expect(trackerIssueId('onboarding'), isNull);
      expect(trackerIssueId('say hi back to me'), isNull);
    });

    test('rejects an absent or blank id', () {
      expect(trackerIssueId(null), isNull);
      expect(trackerIssueId('   '), isNull);
    });
  });
}
