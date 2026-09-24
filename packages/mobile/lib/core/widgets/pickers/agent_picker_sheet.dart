import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/pickers/picker_filter.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';

const String kAgentPickerTitle = 'Agent';
const String kAgentPickerSubtitle = 'Which harness should run this task.';
const String kAgentPickerSearchHint = 'Search agents';
const String kNoAgentsText = 'No agents reported. Check that Operator is running on your computer, then refresh.';

AppSheetPage agentPickerPage({
  required List<RankedAgent> agents,
  required String selected,
  required void Function(BuildContext context, String id) onPicked,
  List<Widget> actions = const [],
  String? error,
}) {
  return AppSheetPage(
    title: kAgentPickerTitle,
    subtitle: kAgentPickerSubtitle,
    actions: actions,
    searchHint: kAgentPickerSearchHint,
    emptyText: kNoAgentsText,
    rows: (context, query) {
      final matching = [
        for (final agent in agents)
          if (PickerFilter.matches(query, [agent.label, agent.id])) agent,
      ];
      if (error == null && matching.isEmpty) return const [];
      return [
        if (error != null) _AgentError(error),
        for (final agent in matching)
          _AgentOption(
            agent: agent,
            selected: agent.id == selected,
            onTap: agent.selectable
                ? () {
                    Haptics.select();
                    onPicked(context, agent.id);
                  }
                : null,
          ),
        if (matching.isEmpty) AgentPickerEmpty(query.isEmpty ? kNoAgentsText : 'No matches'),
      ];
    },
  );
}

class _AgentError extends StatelessWidget {
  const _AgentError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppText(message, style: AppTextStyle.style13Regular.copyWith(color: context.skin.red), maxLines: 2),
    );
  }
}

class AgentPickerEmpty extends StatelessWidget {
  const AgentPickerEmpty(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: AppText(
        message,
        style: AppTextStyle.style13Regular.copyWith(color: context.skin.textTertiary),
        maxLines: 3,
      ),
    );
  }
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
                  style: AppTextStyle.style15Medium.copyWith(color: selected ? skin.accent : skin.textPrimary),
                ),
                if (agent.status.isNotEmpty)
                  AppText(agent.status, style: AppTextStyle.style12Regular.copyWith(color: statusColor)),
              ],
            ),
          ),
          if (selected) Icon(Icons.check, size: 18, color: skin.accent),
        ],
      ),
    );

    if (!agent.selectable) {
      return Opacity(opacity: 0.45, child: row);
    }

    return AppInkWell(onTap: onTap, child: row);
  }
}
