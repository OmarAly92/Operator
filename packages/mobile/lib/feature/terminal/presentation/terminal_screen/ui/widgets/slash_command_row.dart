import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class SlashCommandRow extends StatelessWidget {
  const SlashCommandRow({
    super.key,
    required this.name,
    required this.description,
    required this.source,
    required this.onTap,
  });

  final String name;
  final String description;
  final String source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppInkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText('/$name', style: AppTextStyle.mono12Regular.copyWith(color: skin.textPrimary)),
                  if (description.isNotEmpty)
                    AppText(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
                    ),
                ],
              ),
            ),
            if (source != 'builtin') ...[
              const HorizontalSpace(8),
              AppText(source, style: AppTextStyle.style10Regular.copyWith(color: skin.textFaint)),
            ],
          ],
        ),
      ),
    );
  }
}
