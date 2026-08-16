import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_row.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/approval_card.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_markdown.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/user_input_card.dart';

class TimelineItem extends StatelessWidget {
  const TimelineItem({
    super.key,
    required this.item,
    required this.approvalPending,
    required this.inputPending,
    required this.onDecide,
    required this.onResolveInput,
  });

  final ConversationItemModel item;
  final bool approvalPending;
  final bool inputPending;
  final Future<void> Function(String requestId, String decisionId) onDecide;
  final Future<void> Function(
    String requestId,
    String action, [
    Map<String, dynamic>? content,
  ])
  onResolveInput;

  @override
  Widget build(BuildContext context) {
    if (item is ConversationMessageModel) {
      return _MessageItem(message: item as ConversationMessageModel);
    }

    final activity = item as ConversationActivityModel;
    if (activity.activityKind == 'approval') {
      return ApprovalCard(
        activity: activity,
        busy: approvalPending,
        onDecide: onDecide,
      );
    }
    if (activity.activityKind == 'user_input') {
      return UserInputCard(
        activity: activity,
        busy: inputPending,
        onResolve: onResolveInput,
      );
    }
    if (activity.activityKind == 'system' &&
        activity.detail?.event == 'compaction') {
      return _CompactionMarker(activity: activity);
    }
    if (activity.activityKind == 'system' &&
        activity.detail?.event == 'steer') {
      return _SteerMessage(activity: activity);
    }
    if (activity.detail?.event == 'model.rerouted') {
      final detail = activity.detail;
      return _SystemSignal(
        icon: Icons.shuffle,
        title: 'Answered by ${detail?.toModel ?? 'another model'}',
        detail: detail?.fromModel != null
            ? 'Instead of ${detail!.fromModel}'
                  '${detail.reason == null ? '' : ' · ${detail.reason}'}'
            : detail?.reason,
      );
    }
    if (activity.detail?.event == 'auth.reauth_required') {
      return _SystemSignal(
        icon: Icons.key_outlined,
        danger: true,
        title: 'The provider asked you to sign in again',
        detail: activity.detail?.reason,
      );
    }
    if (activity.activityKind == 'error') {
      return _ErrorActivity(activity: activity);
    }
    return ActivityRowWidget(activity: activity);
  }
}

class _MessageItem extends StatelessWidget {
  const _MessageItem({required this.message});

  final ConversationMessageModel message;

  @override
  Widget build(BuildContext context) {
    if (message.role == 'user' && message.origin == 'human') {
      return _HumanMessage(message: message);
    }
    if (message.role == 'user') return _OriginMessage(message: message);
    return _AssistantMessage(message: message);
  }
}

class _HumanMessage extends StatelessWidget {
  const _HumanMessage({required this.message});

  final ConversationMessageModel message;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final delivery = _deliveryCopy(message.delivery);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.86,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: skin.bgElevated,
          border: Border.all(color: skin.borderDefault),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(17),
            topRight: Radius.circular(17),
            bottomLeft: Radius.circular(17),
            bottomRight: Radius.circular(5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              message.text ?? '',
              style: AppTextStyle.style16Regular.copyWith(
                color: skin.textPrimary,
                height: 1.4,
              ),
            ),
            if (delivery != null) ...[
              const VerticalSpace(5),
              AppText(
                delivery,
                style: AppTextStyle.style10Regular.copyWith(color: skin.amber),
                maxLines: 2,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({required this.message});

  final ConversationMessageModel message;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = message.text ?? '';
    final streaming = message.streaming == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.senderLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: AppText(
                message.senderLabel!,
                style: AppTextStyle.style11SemiBold.copyWith(
                  color: skin.textTertiary,
                ),
              ),
            ),
          ChatMarkdown(
            text: text.isEmpty && streaming ? '…' : text,
            streaming: streaming,
          ),
          if (!streaming && text.isNotEmpty)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Haptics.success();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_outlined, size: 12, color: skin.textFaint),
                    const HorizontalSpace(5),
                    AppText(
                      'Copy',
                      style: AppTextStyle.style10Regular.copyWith(
                        color: skin.textFaint,
                      ),
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

class _OriginMessage extends StatefulWidget {
  const _OriginMessage({required this.message});

  final ConversationMessageModel message;

  @override
  State<_OriginMessage> createState() => _OriginMessageState();
}

class _OriginMessageState extends State<_OriginMessage> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final message = widget.message;
    final text = message.text ?? '';
    final long = text.length > 600;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: skin.borderStrong, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.podcasts, size: 11, color: skin.textTertiary),
              const HorizontalSpace(5),
              AppText(
                message.senderLabel ??
                    (message.origin == 'automation'
                        ? 'Automation'
                        : 'Operator'),
                style: AppTextStyle.style10Bold.copyWith(
                  color: skin.textTertiary,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const VerticalSpace(5),
          if (long && _expanded)
            ChatMarkdown(text: text)
          else
            SelectableText(
              text,
              maxLines: long ? 5 : null,
              style: AppTextStyle.style14Regular.copyWith(
                color: skin.textSecondary,
                height: 1.45,
              ),
            ),
          if (long)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _expanded ? Icons.expand_less : Icons.chevron_right,
                      size: 12,
                      color: skin.blue,
                    ),
                    const HorizontalSpace(4),
                    AppText(
                      _expanded ? 'Hide report' : 'Show full report',
                      style: AppTextStyle.style11SemiBold.copyWith(
                        color: skin.blue,
                      ),
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

class _SteerMessage extends StatelessWidget {
  const _SteerMessage({required this.activity});

  final ConversationActivityModel activity;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: skin.tintBlue,
          border: Border.all(color: skin.borderSubtle),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText(
              'STEERED',
              style: AppTextStyle.style9Bold.copyWith(
                color: skin.blue,
                letterSpacing: 1,
              ),
            ),
            const VerticalSpace(3),
            SelectableText(
              activity.detail?.text ?? activity.summary ?? '',
              style: AppTextStyle.style16Regular.copyWith(
                color: skin.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemSignal extends StatelessWidget {
  const _SystemSignal({
    required this.icon,
    required this.title,
    this.detail,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: danger ? skin.red : skin.borderDefault),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: danger ? skin.red : skin.textTertiary),
          const HorizontalSpace(9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  title,
                  style: AppTextStyle.style11SemiBold.copyWith(
                    color: danger ? skin.red : skin.textPrimary,
                  ),
                  maxLines: 2,
                ),
                if (detail != null)
                  AppText(
                    detail!,
                    style: AppTextStyle.style10Regular.copyWith(
                      color: skin.textTertiary,
                    ),
                    maxLines: 3,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorActivity extends StatelessWidget {
  const _ErrorActivity({required this.activity});

  final ConversationActivityModel activity;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final body = activity.detail?.error ?? activity.detail?.message;
    final summary = activity.summary ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: skin.tintRed),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: skin.red),
          const HorizontalSpace(9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  summary.isEmpty ? 'Agent error' : summary,
                  style: AppTextStyle.style12SemiBold,
                  maxLines: 2,
                ),
                if (body != null)
                  SelectableText(
                    body,
                    style: AppTextStyle.style12Regular.copyWith(
                      color: skin.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactionMarker extends StatelessWidget {
  const _CompactionMarker({required this.activity});

  final ConversationActivityModel activity;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final after = activity.detail?.tokensAfter;
    final window = activity.detail?.contextWindow;
    final reclaimed = activity.detail?.tokensReclaimed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: skin.borderSubtle)),
          const HorizontalSpace(10),
          Icon(Icons.archive_outlined, size: 12, color: skin.textFaint),
          const HorizontalSpace(6),
          AppText(
            'HISTORY COMPACTED'
            '${reclaimed == null ? '' : '  −${formatTokens(reclaimed)}'}'
            '${after != null && window != null && window > 0 ? '  ${(after / window * 100).round()}% FULL' : ''}',
            style: AppTextStyle.style9Bold.copyWith(
              color: skin.textFaint,
              letterSpacing: 0.8,
            ),
          ),
          const HorizontalSpace(10),
          Expanded(child: Container(height: 1, color: skin.borderSubtle)),
        ],
      ),
    );
  }
}

String? _deliveryCopy(String? state) {
  switch (state) {
    case 'queued':
      return 'Queued — sends when the agent finishes';
    case 'sending':
      return 'Sending…';
    case 'uncertain':
      return 'Delivery unconfirmed — check the conversation before retrying';
    case 'failed':
      return 'Not sent';
    default:
      return null;
  }
}

String formatTokens(int value) => value >= 1000
    ? '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k'
    : '$value';
