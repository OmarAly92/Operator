import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/sessions/logic/harness_logo.dart';

class AgentLogo extends StatelessWidget {
  const AgentLogo({super.key, required this.harness, required this.size});

  final String? harness;
  final double size;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    if (!hasLogo(harness)) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: skin.bgElevated,
        child: AppText(harnessInitial(harness), style: AppTextStyle.style11SemiBold.copyWith(color: skin.textSecondary)),
      );
    }

    final backdrop = backdropFor(harness);
    final backdropColor = switch (backdrop) {
      BackdropPolarity.needsDark => Colors.black,
      BackdropPolarity.needsLight => Colors.white,
      BackdropPolarity.neutral => null,
    };

    final image = Image.asset('assets/agents/${logoKey(harness)}.png', width: size, height: size, fit: BoxFit.contain);

    if (backdropColor == null) return image;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(color: backdropColor, borderRadius: BorderRadius.circular(size * 0.2)),
      child: image,
    );
  }
}
