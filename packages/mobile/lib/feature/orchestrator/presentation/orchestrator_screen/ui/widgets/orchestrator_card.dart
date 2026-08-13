import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
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
  });

  final String projectId;
  final String projectName;
  final OrchestratorModel? link;
  final List<SessionModel> workers;
  final VoidCallback onOpenBoard;

  @override
  State<OrchestratorCard> createState() => _OrchestratorCardState();
}

class _OrchestratorCardState extends State<OrchestratorCard> {
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

    return AppContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
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
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
                        ),
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
              if (intent.confirm)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Restart orchestrator',
                  onPressed: isLaunching ? null : _onLaunch,
                )
              else
                ElevatedButton(
                  onPressed: isLaunching ? null : _onLaunch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: skin.blue,
                    foregroundColor: skin.onAccent,
                    elevation: 0,
                  ),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        borderRadius: BorderRadius.circular(999),
        backgroundColor: meta.tint,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
            const HorizontalSpace(4),
            AppText('$count', style: AppTextStyle.mono12Bold.copyWith(color: meta.color)),
            const HorizontalSpace(4),
            AppText(meta.label, style: AppTextStyle.style11SemiBold),
          ],
        ),
      ),
    );
  }
}
