import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';

enum BoardZone { working, action, pending, merge }

BoardZone boardZoneOf(SessionModel session) {
  switch (attentionOf(session)) {
    case AttentionLevel.merge:
      return BoardZone.merge;
    case AttentionLevel.pending:
      return BoardZone.pending;
    case AttentionLevel.respond:
    case AttentionLevel.review:
      return BoardZone.action;
    case AttentionLevel.working:
    case AttentionLevel.done:
      return BoardZone.working;
  }
}

class ZoneMeta {
  const ZoneMeta({required this.label, required this.color});
  final String label;
  final Color color;
}

ZoneMeta zoneMeta(AppSkin skin, BoardZone zone) {
  switch (zone) {
    case BoardZone.merge:
      return ZoneMeta(label: 'Ready to merge', color: skin.green);
    case BoardZone.action:
      return ZoneMeta(label: 'Needs you', color: skin.amber);
    case BoardZone.pending:
      return ZoneMeta(label: 'In review', color: skin.textTertiary);
    case BoardZone.working:
      return ZoneMeta(label: 'Working', color: skin.orange);
  }
}

bool isArchived(SessionModel session) => session.isTerminated == true || session.status == 'terminated';

class BoardSection {
  const BoardSection({required this.zone, required this.label, required this.color, required this.sessions});
  final BoardZone zone;
  final String label;
  final Color color;
  final List<SessionModel> sessions;
}

class GroupedSessions {
  const GroupedSessions({required this.sections, required this.archived});
  final List<BoardSection> sections;
  final List<SessionModel> archived;
}

GroupedSessions groupSessions(AppSkin skin, List<SessionModel> sessions) {
  final live = <SessionModel>[];
  final archived = <SessionModel>[];
  for (final s in sessions) {
    (isArchived(s) ? archived : live).add(s);
  }

  final byZone = <BoardZone, List<SessionModel>>{};
  for (final s in live) {
    byZone.putIfAbsent(boardZoneOf(s), () => []).add(s);
  }

  final sections = BoardZone.values.where((z) => byZone[z]?.isNotEmpty == true).map((z) {
    final meta = zoneMeta(skin, z);
    return BoardSection(zone: z, label: meta.label, color: meta.color, sessions: byZone[z]!);
  }).toList();

  archived.sort((a, b) => (b.updatedAt ?? '').compareTo(a.updatedAt ?? ''));
  return GroupedSessions(sections: sections, archived: archived);
}

bool showBranch(String? branch, String title) {
  final b = branch?.trim();
  if (b == null || b.isEmpty) return false;

  String normalize(String v) => v
      .toLowerCase()
      .replaceFirst(RegExp(r'^(feat|fix|chore|refactor|session)/'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

  return normalize(b) != normalize(title);
}

const List<String> _trackerProviderPrefixes = ['github:'];

String? trackerIssueId(String? issueId) {
  final id = issueId?.trim();
  if (id == null || id.isEmpty) return null;
  return _trackerProviderPrefixes.any(id.startsWith) ? id : null;
}

enum Tone { neutral, passive, success, warning, error }

String prLifecycle(SessionPrModel pr) {
  if (pr.state == 'merged') return 'merged';
  if (pr.state == 'closed') return 'closed';
  if (pr.state == 'draft') return 'draft';
  return 'open';
}

class PrLineSummary {
  const PrLineSummary({required this.text, required this.tone});
  final String text;
  final Tone tone;
}

PrLineSummary? prLine(SessionModel session) {
  final real = (session.prs ?? []).where((pr) => (pr.number ?? 0) > 0).toList();
  if (real.isEmpty) return null;

  final groups = <String, List<int>>{};
  for (final pr in real) {
    groups.putIfAbsent(prLifecycle(pr), () => []).add(pr.number!);
  }

  final parts = groups.entries.map((e) => '${e.value.map((n) => '#$n').join(', ')} ${e.key}');
  final lifecycles = groups.keys.toSet();
  final tone = lifecycles.contains('closed')
      ? Tone.error
      : lifecycles.contains('open')
          ? Tone.success
          : lifecycles.contains('merged')
              ? Tone.neutral
              : Tone.passive;

  return PrLineSummary(text: 'PR ${parts.join(' · ')}', tone: tone);
}
