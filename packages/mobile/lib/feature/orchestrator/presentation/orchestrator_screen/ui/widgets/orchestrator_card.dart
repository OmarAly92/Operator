import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/main_widgets/status_dot.dart';
import 'package:operator_mobile/feature/orchestrator/logic/orchestrator_view.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_state.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';

const List<AttentionLevel> _zoneOrder = [
  AttentionLevel.merge,
  AttentionLevel.respond,
  AttentionLevel.review,
  AttentionLevel.pending,
  AttentionLevel.working,
  AttentionLevel.done,
];

class OrchestratorCard extends StatefulWidget {
  const OrchestratorCard({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.link,
    required this.workers,
    required this.onOpenBoard,
    this.onOpen,
    this.index = 0,
  });

  final String projectId;
  final String projectName;
  final OrchestratorModel? link;
  final List<SessionModel> workers;
  final VoidCallback onOpenBoard;
  final VoidCallback? onOpen;
  final int index;

  @override
  State<OrchestratorCard> createState() => _OrchestratorCardState();
}

class _OrchestratorCardState extends State<OrchestratorCard> with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _entrance;

  @override
  void initState() {
    super.initState();
    final delay = AppMotion.staggerDelay(widget.index);
    final total = delay + AppMotion.slow;
    _entranceController = AnimationController(vsync: this, duration: total);
    _entrance = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: AppMotion.easeOut),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _onLaunch() async {
    final intent = launchIntent(orchestratorStateOf(widget.link));
    if (intent.confirm) {
      final confirmed = await AppDialog.confirm(
        context,
        title: 'Restart orchestrator?',
        message: 'The orchestrator for ${widget.projectName} will be retired and replaced with a '
            'fresh one. Its workers keep running.',
        confirmLabel: 'Restart',
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    await context.read<OrchestratorCubit>().launch(widget.projectId, clean: intent.clean);
  }

  void _onZoneTap() {
    Haptics.select();
    context.read<SessionsCubit>().setActiveProject(widget.projectId);
    widget.onOpenBoard();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final status = orchestratorStatus(skin, widget.link);
    final intent = launchIntent(orchestratorStateOf(widget.link));
    final counts = zoneCounts(widget.workers);
    final launchState = context.watch<OrchestratorCubit>().state;
    final isLaunching = launchState is LaunchLoadingState && launchState.projectId == widget.projectId;

    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) => Opacity(
        opacity: _entrance.value,
        child: Transform.translate(
          offset: Offset(0, AppMotion.fadeUpOffset * (1 - _entrance.value)),
          child: child,
        ),
      ),
      child: _card(skin, status, intent, counts, isLaunching),
    );
  }

  Widget _card(
    AppSkin skin,
    OrchestratorStatus status,
    LaunchIntent intent,
    Map<AttentionLevel, int> counts,
    bool isLaunching,
  ) {
    return AppContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      border: Border.all(color: skin.borderDefault),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AgentLogo(harness: widget.link?.harness, size: 26),
              const HorizontalSpace(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(widget.projectName, style: AppTextStyle.style15SemiBold),
                    const VerticalSpace(4),
                    Row(
                      children: [
                        StatusDot(color: status.color, size: 7),
                        const HorizontalSpace(6),
                        AppText(status.label, style: AppTextStyle.style12SemiBold.copyWith(color: status.color)),
                        if (widget.link?.harness != null)
                          AppText(' · ${widget.link!.harness}', style: AppTextStyle.mono12Regular),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.workers.isNotEmpty) ...[
            const VerticalSpace(10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final level in _zoneOrder)
                  if ((counts[level] ?? 0) > 0) _zonePill(skin, level, counts[level]!),
              ],
            ),
          ],
          const VerticalSpace(10),
          Row(
            children: [
              Expanded(
                child: AppText(
                  '${widget.workers.length} worker${widget.workers.length == 1 ? '' : 's'}',
                  style: AppTextStyle.style12Regular,
                ),
              ),
              if (widget.onOpen != null)
                _actionIcon(
                  icon: Icons.forum_outlined,
                  tooltip: 'Open orchestrator',
                  color: skin.textSecondary,
                  onPressed: widget.onOpen,
                ),
              if (intent.confirm)
                _actionIcon(
                  icon: Icons.refresh,
                  tooltip: 'Restart orchestrator',
                  color: skin.textSecondary,
                  onPressed: isLaunching ? null : _onLaunch,
                )
              else
                AppContainer(
                  onTap: isLaunching ? null : _onLaunch,
                  pressScale: true,
                  hapticsOnTap: false,
                  backgroundColor: skin.accent,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: AppText(
                    isLaunching ? 'Starting…' : 'Start orchestrator',
                    style: AppTextStyle.style12SemiBold.copyWith(color: skin.onAccent),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _zonePill(AppSkin skin, AttentionLevel level, int count) {
    final meta = attentionMeta(skin, level);
    return Semantics(
      button: true,
      label: '$count ${meta.label} in ${widget.projectName}. Opens the board.',
      child: AppContainer(
        onTap: _onZoneTap,
        hapticsOnTap: false,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
        backgroundColor: meta.tint,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(color: meta.color, size: 6),
            const HorizontalSpace(4),
            AppText('$count', style: AppTextStyle.mono12Bold.copyWith(color: meta.color)),
            const HorizontalSpace(4),
            AppText(meta.label, style: AppTextStyle.style11SemiBold),
          ],
        ),
      ),
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback? onPressed,
  }) => IconButton(
    icon: Icon(icon),
    iconSize: 20,
    color: color,
    tooltip: tooltip,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: EdgeInsets.zero,
    onPressed: onPressed,
  );
}
