import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/blocks/data/model/background_task_model.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/subagents.dart';

enum BackgroundTaskKind { agent, shell, monitor }

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

List<BackgroundTask> backgroundTasksOf(
  List<SessionBlock> mainBlocks,
  Map<String, SubagentSummary> tails, {
  Iterable<BackgroundTaskModel> feed = const [],
}) {
  final entries = subagentsOf(mainBlocks, tails);
  final byAgent = {
    for (final entry in entries)
      if (entry.agentId != null) entry.agentId!: entry,
  };
  final fed = [
    for (final model in feed)
      if ((model.taskId ?? '').isNotEmpty) model,
  ];
  final covered = {
    for (final model in fed)
      if (model.kind == 'agent') model.taskId,
  };
  return sortBackgroundTasks([
    for (final model in fed) _fromFeed(model, model.kind == 'agent' ? byAgent[model.taskId] : null),
    for (final entry in entries)
      if (!covered.contains(entry.agentId)) _fromSubagent(entry),
  ]);
}

BackgroundTaskModel mergeBackgroundTask(BackgroundTaskModel? current, BackgroundTaskModel update) {
  if (current == null) return update;
  final newer = (update.updatedSeq ?? 0) >= (current.updatedSeq ?? 0);
  final primary = newer ? update : current;
  final secondary = newer ? current : update;
  return BackgroundTaskModel(
    taskId: primary.taskId ?? secondary.taskId,
    kind: primary.kind ?? secondary.kind,
    status: primary.status ?? secondary.status,
    toolUseId: primary.toolUseId ?? secondary.toolUseId,
    description: primary.description ?? secondary.description,
    command: primary.command ?? secondary.command,
    summary: primary.summary ?? secondary.summary,
    exitCode: primary.exitCode ?? secondary.exitCode,
    durationMs: primary.durationMs ?? secondary.durationMs,
    outputFile: primary.outputFile ?? secondary.outputFile,
    startedAt: primary.startedAt ?? secondary.startedAt,
    endedAt: primary.endedAt ?? secondary.endedAt,
    agentId: primary.agentId ?? secondary.agentId,
    canStop: primary.canStop ?? secondary.canStop,
    updatedSeq: primary.updatedSeq ?? secondary.updatedSeq,
  );
}

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

BackgroundTask _fromFeed(BackgroundTaskModel model, SubagentEntry? entry) {
  final status = backgroundTaskStatusOf(model.status);
  final running = status == BackgroundTaskStatus.running;
  final title = [model.description, model.command, entry?.title].firstWhere(
    (candidate) => candidate != null && candidate.trim().isNotEmpty,
    orElse: () => null,
  );
  return BackgroundTask(
    id: model.taskId!,
    kind: switch (model.kind) {
      'agent' => BackgroundTaskKind.agent,
      'monitor' => BackgroundTaskKind.monitor,
      _ => BackgroundTaskKind.shell,
    },
    title: title ?? (model.kind == 'agent' ? 'Agent' : model.taskId!),
    status: status,
    startedAt: _parse(model.startedAt) ?? _parse(entry?.startedAt),
    finishedAt: running ? null : _parse(model.endedAt) ?? _parse(entry?.lastSeenAt),
    canStop: running && (model.canStop ?? false),
    subagent: entry,
  );
}

BackgroundTaskStatus backgroundTaskStatusOf(String? status) => switch (status) {
  'running' => BackgroundTaskStatus.running,
  'failed' => BackgroundTaskStatus.failed,
  'killed' || 'stopped' => BackgroundTaskStatus.stopped,
  _ => BackgroundTaskStatus.completed,
};

String taskStopErrorMessage(String? code) => switch (code) {
  'TASK_AMBIGUOUS' => "Couldn't stop — ambiguous",
  'TASK_NOT_FOUND' => "Couldn't stop — not found",
  'TASK_FINISHED' => "Couldn't stop — already finished",
  'TASK_STOP_UNCONFIRMED' => "Couldn't stop — not confirmed",
  'TASK_STOP_UNSUPPORTED' => "Couldn't stop — not supported",
  'TASK_PANEL_UNAVAILABLE' => "Couldn't stop — tasks panel busy",
  'SESSION_COMPOSER_NOT_EMPTY' => "Couldn't stop — draft in composer",
  'SESSION_AWAITING_DECISION' => "Couldn't stop — waiting on a decision",
  _ => "Couldn't stop",
};
