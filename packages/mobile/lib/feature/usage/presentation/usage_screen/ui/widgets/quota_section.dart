import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/usage/data/model/usage_quota_model.dart';
import 'package:operator_mobile/feature/usage/logic/quota_readout.dart';

class QuotaSection extends StatelessWidget {
  const QuotaSection({super.key, required this.quota});

  final UsageQuotaModel? quota;

  @override
  Widget build(BuildContext context) {
    final current = quota;
    if (current == null) return const SizedBox.shrink();

    final skin = context.skin;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            'Codex plan usage',
            style: AppTextStyle.style13SemiBold.copyWith(color: skin.textPrimary),
          ),
          const SizedBox(height: 10),
          for (final window in current.windows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _QuotaWindowRow(window: window, observedAt: current.observedAt),
            ),
          AppText(
            'Claude Code: not reported',
            style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _QuotaWindowRow extends StatelessWidget {
  const _QuotaWindowRow({required this.window, required this.observedAt});

  final UsageQuotaWindowModel window;
  final DateTime? observedAt;

  @override
  Widget build(BuildContext context) {
    final readout = QuotaReadout.of(window);
    if (readout == null) return const SizedBox.shrink();

    final skin = context.skin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AppText(
              readout.label,
              style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
            ),
            if (readout.percentLabel != null)
              AppText(
                readout.percentLabel!,
                style: AppTextStyle.style12SemiBold.copyWith(color: skin.textPrimary),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (readout.isUnknown)
          AppText(
            'Unknown — last seen ${_relativeTime(observedAt)}',
            style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: readout.fraction,
              minHeight: 5,
              backgroundColor: skin.bgSubtle,
              valueColor: AlwaysStoppedAnimation<Color>(skin.blue),
            ),
          ),
      ],
    );
  }

  String _relativeTime(DateTime? time) {
    if (time == null) return 'an unknown time ago';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
