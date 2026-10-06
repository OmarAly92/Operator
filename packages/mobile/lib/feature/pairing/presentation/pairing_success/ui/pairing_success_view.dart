import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/fade_up_entrance.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class PairingSuccessView extends StatelessWidget {
  const PairingSuccessView({super.key, required this.desktopName});

  final String desktopName;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return ColoredBox(
      color: skin.bgBase,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeUpEntrance(
              index: 0,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: skin.tintGreen, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, size: 38, color: skin.green),
              ),
            ),
            const VerticalSpace(18),
            FadeUpEntrance(
              index: 1,
              child: AppText('Connected', style: AppTextStyle.style24BoldDisplay.copyWith(letterSpacing: -0.4)),
            ),
            const VerticalSpace(6),
            FadeUpEntrance(
              index: 2,
              child: AppText(
                desktopName,
                style: AppTextStyle.style14Regular.copyWith(color: skin.textSecondary),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
