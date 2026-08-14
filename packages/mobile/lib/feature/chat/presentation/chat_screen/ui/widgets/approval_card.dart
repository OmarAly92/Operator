import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';

class ApprovalCard extends StatefulWidget {
  const ApprovalCard({
    super.key,
    required this.activity,
    required this.busy,
    required this.onDecide,
  });

  final ConversationActivityModel activity;
  final bool busy;
  final Future<void> Function(String requestId, String decisionId) onDecide;

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  String? _submitting;
  String? _submitError;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final activity = widget.activity;
    final detail = activity.detail;
    final pending = activity.isPending;
    final decisions = activity.decisions ?? detail?.decisions ?? const [];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: pending ? skin.amber : skin.borderDefault),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 15,
                color: pending ? skin.amber : skin.textTertiary,
              ),
              const HorizontalSpace(8),
              Expanded(
                child: AppText(
                  pending ? 'Approval required' : 'Approval resolved',
                  style: AppTextStyle.style13SemiBold,
                ),
              ),
              if (activity.requestId != null)
                AppText(
                  'req ${activity.requestId}',
                  style: AppTextStyle.mono10Regular.copyWith(
                    color: skin.textFaint,
                  ),
                ),
            ],
          ),
          if (detail?.reason != null) ...[
            const VerticalSpace(7),
            AppText(
              detail!.reason!,
              style: AppTextStyle.style12Regular.copyWith(
                color: skin.textSecondary,
              ),
              maxLines: 6,
            ),
          ],
          const VerticalSpace(7),
          SelectableText(
            detail?.command ?? activity.summary ?? '',
            style: AppTextStyle.mono12Regular.copyWith(color: skin.textPrimary),
          ),
          if (detail?.cwd != null)
            LabelValue(label: 'cwd', value: detail!.cwd!),
          const VerticalSpace(10),
          if (pending && activity.requestId != null && decisions.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < decisions.length; index++)
                  ChatActionButton(
                    label: _submitting == decisions[index].id
                        ? 'Sending…'
                        : decisions[index].label!,
                    primary: index == 0,
                    enabled: !widget.busy && _submitting == null,
                    onPressed: () async {
                      setState(() {
                        _submitting = decisions[index].id;
                        _submitError = null;
                      });
                      try {
                        await widget.onDecide(
                          activity.requestId!,
                          decisions[index].id!,
                        );
                      } catch (error) {
                        if (mounted) {
                          setState(() => _submitError = error.toString());
                        }
                      } finally {
                        if (mounted) setState(() => _submitting = null);
                      }
                    },
                  ),
              ],
            )
          else if (pending && activity.requestId == null)
            const PartialNote(
              warning: true,
              text:
                  'This request has no provider identity, so Operator cannot answer it safely. '
                  'Open diagnostics on the host.',
            )
          else if (pending)
            const PartialNote(
              warning: true,
              text:
                  'The agent offered no decisions Operator can present. Open diagnostics from the host.',
            )
          else
            const PartialNote(
              text: 'Already answered. This card is kept for the record.',
            ),
          if (_submitError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(
                _submitError!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
        ],
      ),
    );
  }
}
