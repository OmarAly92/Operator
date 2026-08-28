import 'dart:async';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';

class TurnGroupStatus extends StatefulWidget {
  const TurnGroupStatus({super.key, required this.group});

  final TurnGroup group;

  @override
  State<TurnGroupStatus> createState() => _TurnGroupStatusState();
}

class _TurnGroupStatusState extends State<TurnGroupStatus> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(TurnGroupStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.running != widget.group.running) _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!widget.group.running) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final duration = group.running
        ? _elapsedSince(group.startedAt)
        : group.durationMs;
    final text = duration == null
        ? (group.running ? 'RUNNING' : 'FINISHED')
        : '${group.running ? 'RUNNING' : 'FINISHED'} · ${_formatDuration(duration)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(height: 1, color: context.skin.borderSubtle),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AppText(
              text,
              style: AppTextStyle.mono10Regular.copyWith(
                color: context.skin.textFaint,
              ),
            ),
          ),
          Expanded(
            child: Container(height: 1, color: context.skin.borderSubtle),
          ),
        ],
      ),
    );
  }

  int? _elapsedSince(String? startedAt) {
    if (startedAt == null) return null;
    final start = DateTime.tryParse(startedAt);
    if (start == null) return null;
    return _now.difference(start).inMilliseconds.clamp(0, 1 << 53);
  }
}

String _formatDuration(int durationMs) {
  final seconds = durationMs ~/ 1000;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}
