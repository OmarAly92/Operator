import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/turn_elapsed.dart';
import 'package:operator_mobile/core/utils/working_clock.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';
import 'package:operator_mobile/core/widgets/motion/shimmer.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/blocks/logic/background_tasks.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';

typedef BackgroundTasksOf = List<BackgroundTask> Function(BlocksCubit cubit);

List<BackgroundTask> defaultBackgroundTasksOf(BlocksCubit cubit) =>
    backgroundTasksOf(cubit.blocks, cubit.subagentSummaries);

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
  void Function(BackgroundTask task)? onStop,
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
          onStop: onStop,
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
  static const Key agentGlyphKey = ValueKey('background-task-agent-glyph');

  final WorkingClock clock;
  final BackgroundTasksOf tasksOf;
  final void Function(BackgroundTask task) onOpen;
  final void Function(BackgroundTask task)? onStop;

  @override
  State<BackgroundTasksView> createState() => _BackgroundTasksViewState();
}

class _BackgroundTasksViewState extends State<BackgroundTasksView> {
  static const double _firstSectionGap = 16;
  static const double _sectionGap = 24;
  static const double _cardGap = 12;

  bool _runningOpen = true;
  bool _finishedOpen = true;

  @override
  Widget build(BuildContext context) => BlocBuilder<BlocksCubit, BlocksState>(
    builder: (context, _) {
      final skin = context.skin;
      final tasks = widget.tasksOf(context.read<BlocksCubit>());
      final running = tasks.where((task) => task.running).toList();
      final finished = tasks.where((task) => !task.running).toList();
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
          if (finished.isNotEmpty) ...[
            const SizedBox(height: _sectionGap),
            _SectionHeader(
              key: const ValueKey('section-Finished'),
              label: 'Finished ${finished.length}',
              expanded: _finishedOpen,
              onTap: () => setState(() => _finishedOpen = !_finishedOpen),
            ),
            Disclosure(expanded: _finishedOpen, child: _cards(finished)),
          ],
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
            onStop: widget.onStop == null ? null : () => widget.onStop!(tasks[index]),
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
  const _TaskCard({required this.task, required this.clock, this.onOpen, this.onStop});

  static const double _titleLine = 22;

  final BackgroundTask task;
  final WorkingClock clock;
  final VoidCallback? onOpen;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final agent = task.kind == BackgroundTaskKind.agent;
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
                          agent ? 'Agent' : 'Shell',
                          style: AppTextStyle.style15Regular.copyWith(color: skin.textPrimary),
                        ),
                        const SizedBox(width: 12),
                        Flexible(child: _TaskStatus(task: task, clock: clock)),
                      ],
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
                _StopButton(onTap: onStop),
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
  const _StopButton({required this.onTap});

  static const double size = 28;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      button: true,
      label: 'Stop task',
      excludeSemantics: true,
      child: GestureDetector(
        key: BackgroundTasksView.stopKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                Haptics.tap();
                onTap!();
              },
        child: Container(
          width: size,
          height: size,
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
    );
  }
}
