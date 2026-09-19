import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/subagents.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart';

class SubagentStrip extends StatefulWidget {
  const SubagentStrip({super.key, this.onOpen, this.parentTitle});

  final void Function(SubagentEntry entry)? onOpen;
  final String? parentTitle;

  @override
  State<SubagentStrip> createState() => _SubagentStripState();
}

class _SubagentStripState extends State<SubagentStrip> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _open(BuildContext context, SubagentEntry entry) {
    if (widget.onOpen != null) {
      widget.onOpen!(entry);
      return;
    }
    final cubit = context.read<BlocksCubit>();
    Navigator.of(context).pushNamed(
      RoutesStrings.subagent,
      arguments: {
        'sessionId': cubit.sessionId,
        'agentId': entry.agentId,
        'detail': entry.detail,
        'harness': cubit.harness,
        'parentTitle': widget.parentTitle,
      },
    );
  }

  void _showFinished(BuildContext context, List<SubagentEntry> finished) {
    final skin = context.skin;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: skin.bgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusLg))),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final entry in finished)
              ListTile(
                dense: true,
                leading: BlockStatusDot(status: entry.card?.status ?? BlockStatus.ok),
                title: AppText(entry.title, style: AppTextStyle.style12Medium.copyWith(color: skin.textPrimary)),
                subtitle: AppText(_finishedMeta(entry), style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
                trailing: Icon(Icons.chevron_right, size: 16, color: skin.textTertiary),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _open(context, entry);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _finishedMeta(SubagentEntry entry) {
    final detail = entry.detail;
    return [
      detail?.agentType,
      if (detail?.durationMs != null) formatDuration(Duration(milliseconds: detail!.durationMs!)),
      if (detail?.toolUseCount != null) '${detail!.toolUseCount} tools',
    ].whereType<String>().join(' · ');
  }

  String _runningMeta(SubagentEntry entry) {
    final start = DateTime.tryParse(entry.startedAt ?? '');
    return start == null ? '' : formatDuration(DateTime.now().toUtc().difference(start.toUtc()));
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<BlocksCubit, BlocksState>(
    builder: (context, _) {
      final cubit = context.read<BlocksCubit>();
      final entries = subagentsOf(cubit.blocks, cubit.subagentSummaries);
      if (entries.isEmpty) return const SizedBox.shrink();
      final skin = context.skin;
      final running = entries.where((e) => e.running).toList();
      final finished = entries.where((e) => !e.running).toList();
      return Container(
        height: 44,
        decoration: BoxDecoration(color: skin.bgChrome, border: Border(top: BorderSide(color: skin.borderSubtle))),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          children: [
            for (final entry in running) ...[
              _Pill(
                dot: BlockStatusDot(status: BlockStatus.running),
                label: entry.title,
                meta: _runningMeta(entry),
                onTap: () => _open(context, entry),
              ),
              const SizedBox(width: 8),
            ],
            if (finished.isNotEmpty)
              _Pill(
                dot: null,
                label: '${finished.length} done',
                meta: '',
                failed: finished.any((e) => e.card?.status == BlockStatus.failed),
                onTap: () => _showFinished(context, finished),
              ),
          ],
        ),
      );
    },
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.dot, required this.label, required this.meta, required this.onTap, this.failed = false});

  final Widget? dot;
  final String label;
  final String meta;
  final VoidCallback onTap;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final shown = label.length > 22 ? '${label.substring(0, 22)}…' : label;
    return Material(
      color: failed ? skin.tintRed : skin.bgElevated,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[dot!, const SizedBox(width: 6)],
              AppText(shown, style: AppTextStyle.style12Medium.copyWith(color: failed ? skin.red : skin.textSecondary)),
              if (meta.isNotEmpty) ...[
                const SizedBox(width: 6),
                AppText(meta, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
