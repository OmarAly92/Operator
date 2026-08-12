import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/tone.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';

enum PrLifecycle { open, draft, merged, closed }

PrLifecycle prLifecycleOf(SessionPrModel pr) {
  switch (pr.state) {
    case 'merged':
      return PrLifecycle.merged;
    case 'closed':
      return PrLifecycle.closed;
    case 'draft':
      return PrLifecycle.draft;
    default:
      return PrLifecycle.open;
  }
}

class PrEntry extends Equatable {
  const PrEntry({required this.pr, required this.session});

  final SessionPrModel pr;
  final SessionModel session;

  @override
  List<Object?> get props => [pr, session];
}

List<PrEntry> collectPrs(List<SessionModel> sessions) {
  final seen = <String>{};
  final out = <PrEntry>[];
  for (final session in sessions) {
    for (final pr in session.prs ?? const <SessionPrModel>[]) {
      final number = pr.number ?? 0;
      if (number <= 0) continue;
      if (!seen.add('${session.projectId}#$number')) continue;
      out.add(PrEntry(pr: pr, session: session));
    }
  }
  return out;
}

String prTitle(SessionPrModel pr, [String? fallback]) {
  final backfill = fallback?.trim();
  if (backfill != null && backfill.isNotEmpty) return backfill;
  return 'Pull request #${pr.number}';
}

String mergeReasonLabel(String reason) {
  switch (reason) {
    case 'behind_base':
      return 'branch behind base';
    case 'ci_failing':
      return 'CI failing';
    case 'changes_requested':
      return 'changes requested';
    case 'review_required':
      return 'review required';
    case 'blocked_by_provider':
      return 'provider blocked';
    default:
      return reason.replaceAll('_', ' ');
  }
}

class PrStatusAtom extends Equatable {
  const PrStatusAtom({required this.text, required this.tone});

  final String text;
  final Tone tone;

  @override
  List<Object?> get props => [text, tone];
}

PrStatusAtom prSummaryLine(SessionPrModel pr) {
  final life = prLifecycleOf(pr);
  if (life == PrLifecycle.merged) return const PrStatusAtom(text: 'Merged', tone: Tone.success);
  if (life == PrLifecycle.closed) {
    return const PrStatusAtom(text: 'Closed without merging', tone: Tone.passive);
  }

  final atoms = <PrStatusAtom>[];
  if (pr.ci == 'failing') atoms.add(const PrStatusAtom(text: 'CI failing', tone: Tone.error));
  if (pr.review == 'changes_requested') {
    atoms.add(const PrStatusAtom(text: 'Changes requested', tone: Tone.warning));
  } else if (pr.reviewComments == true) {
    atoms.add(const PrStatusAtom(text: 'Unresolved comments', tone: Tone.warning));
  }

  if (atoms.isEmpty) {
    if (life == PrLifecycle.draft) return const PrStatusAtom(text: 'Draft', tone: Tone.passive);
    if (pr.mergeable == true && pr.review == 'approved') {
      return const PrStatusAtom(text: 'Ready to merge', tone: Tone.success);
    }
    if (pr.ci == 'pending') return const PrStatusAtom(text: 'CI running', tone: Tone.neutral);
    if (pr.review == 'approved') return const PrStatusAtom(text: 'Approved', tone: Tone.success);
    if (pr.review == 'pending') return const PrStatusAtom(text: 'Awaiting review', tone: Tone.neutral);
    return const PrStatusAtom(text: 'Open', tone: Tone.passive);
  }

  final shown = atoms.take(2).toList();
  final tone = shown.any((a) => a.tone == Tone.error) ? Tone.error : Tone.warning;
  return PrStatusAtom(text: shown.map((a) => a.text).join(' · '), tone: tone);
}

class PrStateVisual {
  const PrStateVisual({required this.label, required this.color, required this.tint});

  final PrLifecycle label;
  final Color color;
  final Color tint;
}

PrStateVisual stateVisualOf(AppSkin skin, PrLifecycle life) {
  switch (life) {
    case PrLifecycle.merged:
      return PrStateVisual(label: life, color: skin.purple, tint: skin.tintPurple);
    case PrLifecycle.closed:
      return PrStateVisual(label: life, color: skin.red, tint: skin.tintRed);
    case PrLifecycle.draft:
      return PrStateVisual(label: life, color: skin.textTertiary, tint: skin.bgSubtle);
    case PrLifecycle.open:
      return PrStateVisual(label: life, color: skin.green, tint: skin.tintGreen);
  }
}

PrStateVisual prStateVisual(AppSkin skin, SessionPrModel pr) => stateVisualOf(skin, prLifecycleOf(pr));

PrLifecycle prLifecycleFromName(String? name) {
  for (final life in PrLifecycle.values) {
    if (life.name == name) return life;
  }
  return PrLifecycle.open;
}

const Map<PrLifecycle, int> _lifecycleOrder = {
  PrLifecycle.open: 0,
  PrLifecycle.draft: 1,
  PrLifecycle.merged: 2,
  PrLifecycle.closed: 3,
};

int _openRank(SessionPrModel pr) {
  if (pr.mergeable == true && pr.review == 'approved') return 0;
  if (pr.ci == 'failing') return 1;
  if (pr.review == 'changes_requested' || pr.reviewComments == true) return 2;
  return 3;
}

int comparePrs(SessionPrModel a, SessionPrModel b) {
  final life = _lifecycleOrder[prLifecycleOf(a)]! - _lifecycleOrder[prLifecycleOf(b)]!;
  if (life != 0) return life;
  final rank = _openRank(a) - _openRank(b);
  if (rank != 0) return rank;
  return (b.number ?? 0) - (a.number ?? 0);
}
