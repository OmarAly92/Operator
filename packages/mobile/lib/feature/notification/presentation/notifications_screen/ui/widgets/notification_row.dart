import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/notification/logic/notification_view.dart';

class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.unread,
    required this.onTap,
  });

  final String type;
  final String title;
  final String body;
  final String createdAt;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final visual = notificationVisual(skin, type);
    final stamp = relativeTime(createdAt);

    return AppInkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: skin.bgSubtle,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(visual.icon, size: 15, color: visual.color),
            ),
            const HorizontalSpace(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: AppText(
                          title.isEmpty ? visual.label : title,
                          style: AppTextStyle.style15SemiBold.copyWith(
                            color: unread ? skin.textPrimary : skin.textSecondary,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const HorizontalSpace(7),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: skin.blue, shape: BoxShape.circle),
                        ),
                      ],
                      const Spacer(),
                      if (stamp.isNotEmpty)
                        AppText(
                          stamp,
                          style: AppTextStyle.style12Regular.copyWith(color: skin.textFaint),
                        ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const VerticalSpace(3),
                    AppText(
                      body,
                      style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
                      maxLines: 2,
                    ),
                  ],
                ],
              ),
            ),
            const HorizontalSpace(8),
            Icon(Icons.chevron_right, size: 16, color: skin.textFaint),
          ],
        ),
      ),
    );
  }
}
