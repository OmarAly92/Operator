import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/subagents.dart';

enum BackgroundTaskKind { agent, shell }

enum BackgroundTaskStatus { running, completed, failed, stopped }

class BackgroundTask extends Equatable {
  const BackgroundTask({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    this.startedAt,
    this.finishedAt,
    this.canStop = false,
    this.subagent,
  });

  final String id;
  final BackgroundTaskKind kind;
  final String title;
  final BackgroundTaskStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final bool canStop;
  final SubagentEntry? subagent;

  bool get running => status == BackgroundTaskStatus.running;

  String? get agentId => subagent?.agentId;

  @override
  List<Object?> get props => [id, kind, title, status, startedAt, finishedAt, canStop, subagent];
}

List<BackgroundTask> backgroundTasksOf(List<SessionBlock> mainBlocks, Map<String, SubagentSummary> tails) =>
    sortBackgroundTasks([for (final entry in subagentsOf(mainBlocks, tails)) _fromSubagent(entry)]);

List<BackgroundTask> sortBackgroundTasks(Iterable<BackgroundTask> tasks) {
  final running = tasks.where((task) => task.running).toList()..sort(_byStartAscending);
  final finished = tasks.where((task) => !task.running).toList()..sort(_byFinishDescending);
  return [...running, ...finished];
}

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

int _byStartAscending(BackgroundTask a, BackgroundTask b) => (a.startedAt ?? _epoch).compareTo(b.startedAt ?? _epoch);

int _byFinishDescending(BackgroundTask a, BackgroundTask b) =>
    (b.finishedAt ?? b.startedAt ?? _epoch).compareTo(a.finishedAt ?? a.startedAt ?? _epoch);

DateTime? _parse(String? raw) => DateTime.tryParse(raw ?? '')?.toUtc();

BackgroundTask _fromSubagent(SubagentEntry entry) {
  final status = _statusOf(entry);
  return BackgroundTask(
    id: entry.agentId ?? entry.card?.id ?? '',
    kind: BackgroundTaskKind.agent,
    title: entry.title,
    status: status,
    startedAt: _parse(entry.startedAt),
    finishedAt: status == BackgroundTaskStatus.running ? null : _parse(entry.lastSeenAt),
    subagent: entry,
  );
}

BackgroundTaskStatus _statusOf(SubagentEntry entry) {
  if (entry.running) return BackgroundTaskStatus.running;
  final detail = entry.detail;
  if (entry.card?.status == BlockStatus.failed || detail?.status == 'failed') return BackgroundTaskStatus.failed;
  if (detail?.status == 'stopped') return BackgroundTaskStatus.stopped;
  return BackgroundTaskStatus.completed;
}
