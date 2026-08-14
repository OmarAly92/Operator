import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_chrome.dart';

class ChatMetaBar extends StatelessWidget {
  const ChatMetaBar({
    super.key,
    required this.snapshot,
    required this.refreshing,
    required this.compacting,
    required this.onRefresh,
    this.onCompact,
    this.compactDisabled = false,
  });

  final ConversationSnapshotModel snapshot;
  final bool refreshing;
  final bool compacting;
  final VoidCallback onRefresh;
  final VoidCallback? onCompact;
  final bool compactDisabled;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final readout = contextReadout(
      contextUsed: snapshot.usage?.contextUsed,
      contextWindow: snapshot.usage?.contextWindow,
      totalTokens: snapshot.usage?.totalTokens,
    );
    final stateColor = switch (snapshot.controllerState) {
      'busy' => skin.orange,
      'ready' => skin.green,
      'stopped' => skin.red,
      _ => skin.amber,
    };
    final readoutColor = switch (readout?.severity) {
      Severity.critical => skin.red,
      Severity.warn => skin.amber,
      _ => skin.blue,
    };
    final compactLabel = compacting
        ? 'Compacting conversation history'
        : snapshot.hasTurnInFlight
        ? 'Compact after the current turn finishes'
        : snapshot.controllerState == 'stopped'
        ? 'Resume the agent before compacting conversation history'
        : compactDisabled
        ? 'Compaction is unavailable right now'
        : 'Compact conversation history';

    return Container(
      constraints: const BoxConstraints(minHeight: 37),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border(bottom: BorderSide(color: skin.borderSubtle)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: stateColor,
              shape: BoxShape.circle,
            ),
          ),
          const HorizontalSpace(8),
          AppText(
            snapshot.harness ?? 'agent',
            style: AppTextStyle.style11SemiBold.copyWith(
              color: skin.textSecondary,
            ),
          ),
          const HorizontalSpace(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: skin.borderSubtle),
              borderRadius: BorderRadius.circular(5),
            ),
            child: AppText(
              'CHAT',
              style: AppTextStyle.style9Regular.copyWith(
                color: skin.textFaint,
                letterSpacing: 1,
              ),
            ),
          ),
          const Spacer(),
          if (readout?.percent != null) ...[
            SizedBox(
              width: 54,
              height: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (readout!.fillPercent ?? 0) / 100,
                  backgroundColor: skin.bgSubtle,
                  valueColor: AlwaysStoppedAnimation<Color>(readoutColor),
                ),
              ),
            ),
            const HorizontalSpace(8),
            AppText(
              '${readout.percent}%',
              style: AppTextStyle.mono10Regular.copyWith(color: readoutColor),
            ),
          ] else if (readout != null)
            AppText(
              '${readout.tokens} tokens',
              style: AppTextStyle.mono10Regular.copyWith(
                color: skin.textTertiary,
              ),
            ),
          if (onCompact != null) ...[
            const HorizontalSpace(10),
            Semantics(
              button: true,
              enabled: !compactDisabled,
              label: compactLabel,
              child: InkWell(
                onTap: compactDisabled ? null : onCompact,
                child: compacting
                    ? SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: skin.textTertiary,
                        ),
                      )
                    : Icon(
                        Icons.archive_outlined,
                        size: 14,
                        color: compactDisabled
                            ? skin.textFaint
                            : skin.textTertiary,
                      ),
              ),
            ),
          ],
          const HorizontalSpace(10),
          InkWell(
            onTap: onRefresh,
            child: Opacity(
              opacity: refreshing ? 0.4 : 1,
              child: Icon(Icons.refresh, size: 14, color: skin.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
