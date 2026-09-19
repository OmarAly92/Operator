import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

class SubagentSummary extends Equatable {
  const SubagentSummary({required this.agentId, this.prompt, this.startedAt, this.lastSeenAt, this.stopped = false});

  final String agentId;
  final String? prompt;
  final String? startedAt;
  final String? lastSeenAt;
  final bool stopped;

  SubagentSummary absorb({String? prompt, String? at, bool stopped = false}) => SubagentSummary(
    agentId: agentId,
    prompt: this.prompt ?? prompt,
    startedAt: startedAt ?? at,
    lastSeenAt: at ?? lastSeenAt,
    stopped: this.stopped || stopped,
  );

  @override
  List<Object?> get props => [agentId, prompt, startedAt, lastSeenAt, stopped];
}

class SubagentEntry extends Equatable {
  const SubagentEntry({required this.agentId, this.card, this.summary});

  final String? agentId;
  final SessionBlock? card;
  final SubagentSummary? summary;

  AgentBlockDetail? get detail => card?.detail is AgentBlockDetail ? card!.detail! as AgentBlockDetail : null;
  String get title => detail?.description ?? detail?.agentType ?? 'Agent';
  bool get running => !(summary?.stopped ?? false) && !(detail?.finished ?? false) && card?.status != BlockStatus.ok && card?.status != BlockStatus.failed;
  String? get startedAt => card?.createdAt ?? summary?.startedAt;
  String? get lastSeenAt => summary?.lastSeenAt ?? card?.createdAt;

  @override
  List<Object?> get props => [agentId, card, summary];
}

List<SubagentEntry> subagentsOf(List<SessionBlock> mainBlocks, Map<String, SubagentSummary> tails) {
  final unclaimed = Map<String, SubagentSummary>.of(tails);
  final entries = <SubagentEntry>[];
  for (final block in _flatten(mainBlocks)) {
    final detail = block.detail;
    if (detail is! AgentBlockDetail) continue;
    SubagentSummary? match;
    if (detail.agentId != null) {
      match = unclaimed.remove(detail.agentId);
    } else {
      final byPrompt = unclaimed.values.where((s) => s.prompt != null && s.prompt == detail.prompt).firstOrNull;
      if (byPrompt != null) match = unclaimed.remove(byPrompt.agentId);
    }
    entries.add(SubagentEntry(agentId: detail.agentId ?? match?.agentId, card: block, summary: match));
  }
  for (final summary in unclaimed.values) {
    entries.add(SubagentEntry(agentId: summary.agentId, summary: summary));
  }
  entries.sort((a, b) {
    if (a.running != b.running) return a.running ? -1 : 1;
    if (a.running) return (a.startedAt ?? '').compareTo(b.startedAt ?? '');
    return (b.lastSeenAt ?? '').compareTo(a.lastSeenAt ?? '');
  });
  return entries;
}

Iterable<SessionBlock> _flatten(List<SessionBlock> blocks) sync* {
  for (final block in blocks) {
    yield block;
    if (block.children != null) yield* _flatten(block.children!);
  }
}
