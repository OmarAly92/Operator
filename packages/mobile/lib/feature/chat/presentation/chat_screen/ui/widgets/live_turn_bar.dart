import 'dart:async';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_chrome.dart';

class LiveTurnBar extends StatefulWidget {
  const LiveTurnBar({
    super.key,
    required this.snapshot,
    required this.startedAt,
    required this.stopping,
    required this.onInterrupt,
  });

  final ConversationSnapshotModel snapshot;
  final String? startedAt;
  final bool stopping;
  final VoidCallback onInterrupt;

  @override
  State<LiveTurnBar> createState() => _LiveTurnBarState();
}

class _LiveTurnBarState extends State<LiveTurnBar> {
  Timer? _tick;
  int _now = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now().millisecondsSinceEpoch),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final queued = widget.snapshot.turns
        .where((turn) => turn.state == 'queued')
        .length;
    final blocked = widget.snapshot.hasPendingRequest;
    final elapsed = elapsedLabel(widget.startedAt, _now);
    final stopLabel = queued > 0 ? 'Stop and clear queue' : 'Stop turn';

    return Container(
      constraints: const BoxConstraints(minHeight: 35),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border(top: BorderSide(color: skin.borderSubtle)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.7,
              color: blocked ? skin.amber : skin.orange,
            ),
          ),
          const HorizontalSpace(9),
          Expanded(
            child: AppText(
              '${blocked ? 'Waiting for your input' : 'Agent is working'}'
              '${elapsed == null ? '' : ' · $elapsed'}'
              '${queued > 0 ? ' · $queued queued' : ''}',
              style: AppTextStyle.style11Regular.copyWith(
                color: skin.textSecondary,
              ),
            ),
          ),
          InkWell(
            onTap: widget.stopping ? null : widget.onInterrupt,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: skin.borderDefault),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stop, size: 11, color: skin.textPrimary),
                  const HorizontalSpace(5),
                  AppText(
                    widget.stopping ? 'Stopping…' : stopLabel,
                    style: AppTextStyle.style10SemiBold,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
