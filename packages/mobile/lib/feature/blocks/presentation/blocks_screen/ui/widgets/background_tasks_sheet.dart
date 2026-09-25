import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/turn_elapsed.dart';
import 'package:operator_mobile/core/utils/working_clock.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';
import 'package:operator_mobile/core/widgets/motion/shimmer.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/blocks/logic/background_tasks.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';

typedef BackgroundTasksOf = List<BackgroundTask> Function(BlocksCubit cubit);

typedef StopBackgroundTask = Future<Failure?> Function(BackgroundTask task);

List<BackgroundTask> defaultBackgroundTasksOf(BlocksCubit cubit) =>
    backgroundTasksOf(cubit.blocks, cubit.subagentSummaries, feed: cubit.taskFeed.values);

void openSubagentTask(NavigatorState navigator, BlocksCubit cubit, BackgroundTask task, {String? parentTitle}) {
  final entry = task.subagent;
  if (entry == null) return;
  navigator.pushNamed(
    RoutesStrings.subagent,
    arguments: {
      'sessionId': cubit.sessionId,
      'agentId': entry.agentId,
      'detail': entry.detail,
      'harness': cubit.harness,
      'parentTitle': parentTitle,
    },
  );
}

Future<void> showBackgroundTasksSheet(
  BuildContext context, {
  String? parentTitle,
  WorkingClock? clock,
  BackgroundTasksOf? tasksOf,
  StopBackgroundTask? onStop,
}) {
  final cubit = context.read<BlocksCubit>();
  final navigator = Navigator.of(context);
  return showAppSheet<void>(
    context: context,
    detent: AppSheetDetent.fit,
    scope: (sheetContext, sheet) => BlocProvider<BlocksCubit>.value(value: cubit, child: sheet),
    page: AppSheetPage(
      title: 'Background tasks',
      closeable: true,
      rows: (context, _) => [
        BackgroundTasksView(
          clock: clock ?? WorkingClock.shared,
          tasksOf: tasksOf ?? defaultBackgroundTasksOf,
          onStop: onStop ?? (task) => cubit.stopTask(task.id),
          onOpen: (task) {
            AppSheet.of(context).close();
            openSubagentTask(navigator, cubit, task, parentTitle: parentTitle);
          },
        ),
      ],
    ),
  );
}

class BackgroundTasksView extends StatefulWidget {
  const BackgroundTasksView({
    super.key,
    required this.clock,
    required this.tasksOf,
    required this.onOpen,
    this.onStop,
  });

  static const Key cardKey = ValueKey('background-task-card');
  static const Key stopKey = ValueKey('background-task-stop');
  static const Key stoppingKey = ValueKey('background-task-stopping');
  static const Key agentGlyphKey = ValueKey('background-task-agent-glyph');

  final WorkingClock clock;
  final BackgroundTasksOf tasksOf;
  final void Function(BackgroundTask task) onOpen;
  final StopBackgroundTask? onStop;

  @override
  State<BackgroundTasksView> createState() => _BackgroundTasksViewState();
}

class _BackgroundTasksViewState extends State<BackgroundTasksView> {
  static const double _firstSectionGap = 16;
  static const double _sectionGap = 24;
  static const double _cardGap = 12;

  bool _runningOpen = true;
  bool _finishedOpen = true;
  final Set<String> _stopping = <String>{};
  final Map<String, String> _stopErrors = <String, String>{};
  final Map<String, Timer> _errorTimers = <String, Timer>{};

  @override
  void dispose() {
    for (final timer in _errorTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _clearError(String id) {
    _errorTimers.remove(id)?.cancel();
    _stopErrors.remove(id);
  }

  Future<void> _stop(BackgroundTask task) async {
    final onStop = widget.onStop;
    if (onStop == null || _stopping.contains(task.id)) return;
    Haptics.tap();
    setState(() {
      _stopping.add(task.id);
      _clearError(task.id);
    });
    final failure = await onStop(task);
    if (!mounted || failure == null) return;
    Haptics.error();
    setState(() {
      _stopping.remove(task.id);
      _stopErrors[task.id] = taskStopErrorMessage(failure.apiStatus);
    });
    _errorTimers[task.id] = Timer(AppMotion.taskStopErrorHold, () {
      if (!mounted) return;
      setState(() => _clearError(task.id));
    });
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<BlocksCubit, BlocksState>(
    builder: (context, _) {
      final skin = context.skin;
      final tasks = widget.tasksOf(context.read<BlocksCubit>());
      final running = tasks.where((task) => task.running).toList();
      final finished = tasks.where((task) => !task.running).toList();
      final runningIds = {for (final task in running) task.id};
      _stopping.removeWhere((id) => !runningIds.contains(id));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: _firstSectionGap),
          _SectionHeader(
            key: const ValueKey('section-Running'),
            label: 'Running',
            expanded: _runningOpen,
            onTap: () => setState(() => _runningOpen = !_runningOpen),
          ),
          Disclosure(
            expanded: _runningOpen,
            child: running.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No running tasks',
                      style: AppTextStyle.style15Regular.copyWith(color: skin.textTertiary),
                    ),
                  )
                : _cards(running),
          ),
          Disclosure(
            expanded: finished.isNotEmpty,
            child: finished.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: _sectionGap),
                      _SectionHeader(
                        key: const ValueKey('section-Finished'),
                        label: 'Finished ${finished.length}',
                        expanded: _finishedOpen,
                        onTap: () => setState(() => _finishedOpen = !_finishedOpen),
                      ),
                      Disclosure(expanded: _finishedOpen, child: _cards(finished)),
                    ],
                  ),
          ),
        ],
      );
    },
  );

  Widget _cards(List<BackgroundTask> tasks) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < tasks.length; index++)
        Padding(
          key: ValueKey<String>('task-${tasks[index].kind.name}-${tasks[index].id}'),
          padding: EdgeInsets.only(top: index == 0 ? 4 : _cardGap),
          child: _TaskCard(
            task: tasks[index],
            clock: widget.clock,
            onOpen: tasks[index].subagent == null ? null : () => widget.onOpen(tasks[index]),
            onStop: widget.onStop == null ? null : () => _stop(tasks[index]),
            stopping: _stopping.contains(tasks[index].id),
            stopError: _stopErrors[tasks[index].id],
          ),
        ),
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.label, required this.expanded, required this.onTap});

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      button: true,
      expanded: expanded,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.select();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            children: [
              Text(
                label,
                style: AppTextStyle.style15Medium.copyWith(
                  color: skin.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              DisclosureChevron(
                expanded: expanded,
                size: 18,
                color: skin.textSecondary,
                collapsedTurns: -0.25,
                expandedTurns: 0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.clock,
    this.onOpen,
    this.onStop,
    this.stopping = false,
    this.stopError,
  });

  static const double _titleLine = 22;

  final BackgroundTask task;
  final WorkingClock clock;
  final VoidCallback? onOpen;
  final VoidCallback? onStop;
  final bool stopping;
  final String? stopError;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final agent = task.kind == BackgroundTaskKind.agent;
    final error = stopError;
    final titleStyle = AppTextStyle.style17Medium.copyWith(color: skin.textPrimary, height: _titleLine / 17);
    final title = Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle);
    return Material(
      key: BackgroundTasksView.cardKey,
      color: skin.bgElevated,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                height: _titleLine,
                child: Center(
                  child: agent
                      ? Transform.rotate(
                          key: BackgroundTasksView.agentGlyphKey,
                          angle: math.pi / 4,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              border: Border.all(color: skin.textSecondary, width: 1.5),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        )
                      : Icon(Icons.terminal_outlined, size: 18, color: skin.textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    task.running ? Shimmer(base: skin.textSecondary, highlight: skin.textPrimary, child: title) : title,
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          switch (task.kind) {
                            BackgroundTaskKind.agent => 'Agent',
                            BackgroundTaskKind.shell => 'Shell',
                            BackgroundTaskKind.monitor => 'Monitor',
                          },
                          style: AppTextStyle.style15Regular.copyWith(color: skin.textPrimary),
                        ),
                        const SizedBox(width: 12),
                        Flexible(child: _TaskStatus(task: task, clock: clock)),
                      ],
                    ),
                    Disclosure(
                      expanded: error != null,
                      child: error == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                error,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.style13Regular.copyWith(color: skin.red),
                              ),
                            ),
                    ),
                    if (agent) ...[
                      const SizedBox(height: 10),
                      Text('View transcript', style: AppTextStyle.style15Medium.copyWith(color: skin.blue)),
                    ],
                  ],
                ),
              ),
              if (task.canStop) ...[
                const SizedBox(width: 12),
                _StopButton(onTap: onStop, stopping: stopping),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskStatus extends StatelessWidget {
  const _TaskStatus({required this.task, required this.clock});

  final BackgroundTask task;
  final WorkingClock clock;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final style = AppTextStyle.style15Regular.copyWith(
      color: skin.textTertiary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final startedAt = task.startedAt;
    switch (task.status) {
      case BackgroundTaskStatus.running:
        if (startedAt == null) return const SizedBox.shrink();
        return ValueListenableBuilder<DateTime>(
          valueListenable: clock,
          builder: (context, now, _) => Text(turnElapsed(now.difference(startedAt)), maxLines: 1, style: style),
        );
      case BackgroundTaskStatus.completed:
        return Text('Completed', maxLines: 1, style: style);
      case BackgroundTaskStatus.stopped:
        return Text('Stopped', maxLines: 1, style: style);
      case BackgroundTaskStatus.failed:
        return Text('Failed', maxLines: 1, style: style.copyWith(color: skin.red));
    }
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onTap, required this.stopping});

  static const double size = 28;

  final VoidCallback? onTap;
  final bool stopping;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      button: true,
      label: stopping ? 'Stopping task' : 'Stop task',
      excludeSemantics: true,
      child: GestureDetector(
        key: BackgroundTasksView.stopKey,
        behavior: HitTestBehavior.opaque,
        onTap: stopping ? null : onTap,
        child: SizedBox.square(
          dimension: size,
          child: stopping
              ? Center(
                  child: SizedBox.square(
                    key: BackgroundTasksView.stoppingKey,
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: skin.textSecondary),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: skin.textSecondary, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: skin.textSecondary, borderRadius: BorderRadius.circular(2.5)),
                  ),
                ),
        ),
      ),
    );
  }
}
