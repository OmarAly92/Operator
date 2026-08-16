import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';

Future<String?> showAgentPickerSheet(
  BuildContext context, {
  required List<RankedAgent> agents,
  required String selected,
  required Future<void> Function() onRefresh,
  bool refreshing = false,
  String? error,
}) {
  final skin = context.skin;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: skin.bgSurface,
    isScrollControlled: true,
    builder: (sheetContext) {
      var isRefreshing = refreshing;
      return StatefulBuilder(
        builder: (builderContext, setState) {
          Future<void> handleRefresh() async {
            Haptics.tap();
            setState(() => isRefreshing = true);
            await onRefresh();
            setState(() => isRefreshing = false);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText('Agent', style: AppTextStyle.style17SemiBold),
                            const VerticalSpace(4),
                            AppText(
                              'Which harness should run this task.',
                              style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                      AppInkWell(
                        onTap: isRefreshing ? null : handleRefresh,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: isRefreshing
                              ? const SizedBox(width: 16, height: 16, child: AppLoader(strokeWidth: 2))
                              : AppText('Refresh', style: AppTextStyle.style13Regular.copyWith(color: skin.blue)),
                        ),
                      ),
                    ],
                  ),
                  if (error != null) ...[
                    const VerticalSpace(8),
                    AppText(error, style: AppTextStyle.style13Regular.copyWith(color: skin.red), maxLines: 2),
                  ],
                  const VerticalSpace(8),
                  if (agents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: AppText(
                        'No agents reported. Check that Operator is running on your computer, then refresh.',
                        style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
                        maxLines: 3,
                      ),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final agent in agents)
                            _AgentOption(
                              agent: agent,
                              selected: agent.id == selected,
                              onTap: agent.selectable
                                  ? () {
                                      Haptics.select();
                                      Navigator.of(sheetContext).pop(agent.id);
                                    }
                                  : null,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _AgentOption extends StatelessWidget {
  const _AgentOption({required this.agent, required this.selected, required this.onTap});

  final RankedAgent agent;
  final bool selected;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final statusColor =
        agent.availability == AgentAvailability.authUnknown || agent.availability == AgentAvailability.needsAuth
        ? skin.amber
        : skin.textTertiary;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          AgentLogo(harness: agent.id, size: 22),
          const HorizontalSpace(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  agent.label,
                  style: AppTextStyle.style15Medium.copyWith(color: selected ? skin.blue : skin.textPrimary),
                ),
                if (agent.status.isNotEmpty)
                  AppText(agent.status, style: AppTextStyle.style12Regular.copyWith(color: statusColor)),
              ],
            ),
          ),
          if (selected) Icon(Icons.check, size: 18, color: skin.blue),
        ],
      ),
    );

    if (!agent.selectable) {
      return Opacity(opacity: 0.45, child: row);
    }

    return AppInkWell(onTap: onTap, child: row);
  }
}
