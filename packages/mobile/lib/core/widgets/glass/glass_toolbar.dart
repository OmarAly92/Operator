import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class GlassToolbar extends StatelessWidget {
  const GlassToolbar({super.key, this.leading, this.title, this.trailing = const []});

  final Widget? leading;
  final String? title;
  final List<Widget> trailing;

  static const double _maxTextScaleFactor = 1.8;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final clampedScaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _maxTextScaleFactor);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        GlassMetrics.toolbarSideInset,
        top + GlassMetrics.toolbarTopGap,
        GlassMetrics.toolbarSideInset,
        0,
      ),
      child: SizedBox(
        height: GlassMetrics.hitTarget,
        child: GlassScope(
          variant: GlassVariant.regular,
          size: GlassMetrics.hitTarget,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: clampedScaler),
            child: NavigationToolbar(
              leading: leading,
              middle: title == null
                  ? null
                  : AppText(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.style16SemiBold.copyWith(color: context.skin.textPrimary),
                    ),
              trailing: trailing.isEmpty
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < trailing.length; i++) ...[
                          if (i > 0) const SizedBox(width: GlassMetrics.toolbarItemGap),
                          trailing[i],
                        ],
                      ],
                    ),
              middleSpacing: GlassMetrics.toolbarItemGap,
            ),
          ),
        ),
      ),
    );
  }
}
