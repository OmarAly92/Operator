import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/tone.dart';
import 'package:operator_mobile/feature/pull_request/data/model/session_pr_summary_model.dart';
import 'package:operator_mobile/feature/pull_request/logic/pr_view.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';

SessionPrModel pr({
  int? number = 184,
  String? state = 'open',
  String? ci,
  String? review,
  bool? mergeable,
  bool? reviewComments,
}) => SessionPrModel(
  url: 'https://github.com/o/r/pull/184',
  number: number,
  state: state,
  ci: ci,
  review: review,
  mergeable: mergeable,
  reviewComments: reviewComments,
);

SessionModel session(String projectId, List<SessionPrModel> prs, [String? id]) =>
    SessionModel(id: id ?? '$projectId-1', projectId: projectId, prs: prs);

void main() {
  const skin = DarkSkin();

  group('collectPrs', () {
    test('keeps the same PR number in two different projects', () {
      final got = collectPrs([
        session('alpha', [pr(number: 12)]),
        session('beta', [pr(number: 12)]),
      ]);
      expect(got.map((e) => e.session.projectId), ['alpha', 'beta']);
    });

    test('collapses the same PR seen from two sessions in one project', () {
      final got = collectPrs([
        session('alpha', [pr(number: 12)], 'alpha-1'),
        session('alpha', [pr(number: 12)], 'alpha-2'),
      ]);
      expect(got, hasLength(1));
    });

    test('skips placeholder PRs with no real number', () {
      expect(collectPrs([session('alpha', [pr(number: 0)])]), isEmpty);
      expect(collectPrs([session('alpha', [pr(number: null)])]), isEmpty);
    });

    test('tolerates a session with no PR list at all', () {
      expect(collectPrs([const SessionModel(id: 'a', projectId: 'alpha')]), isEmpty);
    });
  });

  group('prTitle', () {
    test('falls back to the session title when the daemon sent none', () {
      expect(prTitle(pr(), 'Fix auth timeouts on refresh'), 'Fix auth timeouts on refresh');
    });

    test('falls back to the PR number only when there is nothing else', () {
      expect(prTitle(pr()), 'Pull request #184');
      expect(prTitle(pr(), ''), 'Pull request #184');
      expect(prTitle(pr(), '   '), 'Pull request #184');
    });
  });

  group('prLifecycleOf', () {
    test('reports a draft', () {
      expect(prLifecycleOf(pr(state: 'draft')), PrLifecycle.draft);
    });

    test('reports merged and closed', () {
      expect(prLifecycleOf(pr(state: 'merged')), PrLifecycle.merged);
      expect(prLifecycleOf(pr(state: 'closed')), PrLifecycle.closed);
    });

    test('defaults to open', () {
      expect(prLifecycleOf(pr()), PrLifecycle.open);
      expect(prLifecycleOf(pr(state: null)), PrLifecycle.open);
    });
  });

  group('prLifecycleFromName', () {
    test('maps each known lifecycle name', () {
      expect(prLifecycleFromName('open'), PrLifecycle.open);
      expect(prLifecycleFromName('draft'), PrLifecycle.draft);
      expect(prLifecycleFromName('merged'), PrLifecycle.merged);
      expect(prLifecycleFromName('closed'), PrLifecycle.closed);
    });

    test('falls back to open for an unknown or missing name', () {
      expect(prLifecycleFromName('some_garbage'), PrLifecycle.open);
      expect(prLifecycleFromName(null), PrLifecycle.open);
    });
  });

  group('mergeReasonLabel', () {
    test('humanises the reasons desktop knows', () {
      expect(mergeReasonLabel('behind_base'), 'branch behind base');
      expect(mergeReasonLabel('ci_failing'), 'CI failing');
      expect(mergeReasonLabel('changes_requested'), 'changes requested');
      expect(mergeReasonLabel('review_required'), 'review required');
      expect(mergeReasonLabel('blocked_by_provider'), 'provider blocked');
    });

    test('degrades an unknown reason into readable words', () {
      expect(mergeReasonLabel('some_new_reason'), 'some new reason');
    });
  });

  group('prSummaryLine', () {
    test('says only the outcome for a decided PR', () {
      expect(prSummaryLine(pr(state: 'merged', ci: 'failing')).text, 'Merged');
      expect(prSummaryLine(pr(state: 'closed')).text, 'Closed without merging');
    });

    test('leads with the worst problem', () {
      final line = prSummaryLine(pr(ci: 'failing', review: 'changes_requested'));
      expect(line.text.startsWith('CI failing'), isTrue);
      expect(line.tone, Tone.error);
    });

    test('never shows more than two problems', () {
      final line = prSummaryLine(pr(ci: 'failing', review: 'changes_requested', reviewComments: true));
      expect(line.text.split(' · '), hasLength(2));
    });

    test('calls out a PR that is ready to go', () {
      final line = prSummaryLine(pr(review: 'approved', mergeable: true));
      expect(line.text, 'Ready to merge');
      expect(line.tone, Tone.success);
    });

    test('reports a draft as a draft', () {
      expect(prSummaryLine(pr(state: 'draft')).text, 'Draft');
    });

    test('falls back through CI and review before plain open', () {
      expect(prSummaryLine(pr(ci: 'pending')).text, 'CI running');
      expect(prSummaryLine(pr(review: 'pending')).text, 'Awaiting review');
      expect(prSummaryLine(pr()).text, 'Open');
    });

    test('surfaces unresolved comments when there is no formal refusal', () {
      expect(prSummaryLine(pr(reviewComments: true)).text, 'Unresolved comments');
    });
  });

  group('stateVisualOf', () {
    test('gives merged its own hue, distinct from open', () {
      expect(stateVisualOf(skin, PrLifecycle.merged).color, skin.purple);
      expect(stateVisualOf(skin, PrLifecycle.open).color, skin.green);
      expect(stateVisualOf(skin, PrLifecycle.closed).color, skin.red);
      expect(stateVisualOf(skin, PrLifecycle.draft).color, skin.textTertiary);
    });

    test('reads the lifecycle off a board PR', () {
      expect(prStateVisual(skin, pr(state: 'merged')).label, PrLifecycle.merged);
    });
  });

  group('comparePrs', () {
    List<int?> sorted(List<SessionPrModel> list) =>
        ([...list]..sort(comparePrs)).map((p) => p.number).toList();

    test('orders open before draft before merged before closed', () {
      expect(
        sorted([
          pr(number: 1, state: 'closed'),
          pr(number: 2, state: 'merged'),
          pr(number: 3, state: 'draft'),
          pr(number: 4),
        ]),
        [4, 3, 2, 1],
      );
    });

    test('floats a ready-to-merge PR to the top of the open bucket', () {
      expect(sorted([pr(number: 10), pr(number: 2, review: 'approved', mergeable: true)]).first, 2);
    });

    test('puts PRs needing attention above quiet ones', () {
      expect(
        sorted([pr(number: 9), pr(number: 5, review: 'changes_requested'), pr(number: 3, ci: 'failing')]),
        [3, 5, 9],
      );
    });

    test('breaks ties with the newest PR first', () {
      expect(sorted([pr(number: 4), pr(number: 12), pr(number: 7)]), [12, 7, 4]);
    });
  });

  group('prStatusAtoms', () {
    SessionPrSummaryModel rich({
      String? state = 'open',
      String? ci,
      String? merge,
      String? review,
      bool? unresolved,
    }) => SessionPrSummaryModel(
      state: state,
      ciState: ci,
      mergeabilityState: merge,
      reviewDecision: review,
      hasUnresolvedHumanComments: unresolved,
    );

    test('collapses a decided PR to one atom', () {
      expect(prStatusAtoms(rich(state: 'merged', ci: 'passing')),
          const [PrStatusAtom(text: 'Merged', tone: Tone.success)]);
      expect(prStatusAtoms(rich(state: 'closed')),
          const [PrStatusAtom(text: 'Closed', tone: Tone.passive)]);
    });

    test('reports CI, merge and review in that order', () {
      final atoms = prStatusAtoms(rich(ci: 'passing', merge: 'mergeable', review: 'approved'));
      expect(atoms.map((a) => a.text), ['CI passing', 'Mergeable', 'Approved']);
    });

    test('omits anything the daemon has not determined', () {
      expect(prStatusAtoms(rich(ci: 'unknown', merge: 'unknown')), isEmpty);
      expect(prStatusAtoms(rich()), isEmpty);
    });

    test('colours failures and blockers correctly', () {
      final atoms = prStatusAtoms(rich(ci: 'failing', merge: 'conflicting', review: 'changes_requested'));
      expect(atoms.map((a) => a.tone), [Tone.error, Tone.error, Tone.warning]);
    });

    test('surfaces unresolved comments when there is no formal decision', () {
      expect(prStatusAtoms(rich(review: 'none', unresolved: true)),
          const [PrStatusAtom(text: 'Unresolved comments', tone: Tone.warning)]);
    });
  });

  group('prBlockerLine', () {
    test('names failing checks and merge reasons together', () {
      expect(
        prBlockerLine(const SessionPrSummaryModel(
          failingChecks: ['go test'],
          mergeReasons: ['behind_base'],
        )),
        'go test · branch behind base',
      );
    });

    test('caps the list and counts the remainder rather than truncating silently', () {
      expect(
        prBlockerLine(const SessionPrSummaryModel(failingChecks: ['a', 'b', 'c', 'd'])),
        'a · b +2 more',
      );
    });

    test('returns nothing when there is nothing blocking', () {
      expect(prBlockerLine(const SessionPrSummaryModel()), isNull);
    });
  });
}
